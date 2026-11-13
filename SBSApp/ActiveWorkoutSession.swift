import SwiftUI
import AVFoundation
import Combine

/// A workout in progress. Owned by `AppState` rather than the workout screen, so it
/// keeps running while minimized (the rest timer, Watch messages, logging) and is saved
/// on every change so it comes back after an app kill.
///
/// `WorkoutView` is only a presentation of this object: closing it doesn't end anything.
/// Finishing, exiting or discarding all end here and clear every surface.
@MainActor
@Observable
final class ActiveWorkoutSession: Identifiable {
    let id: UUID
    let week: Int
    let day: Int
    let programId: String?
    let cycleStartDate: Date
    let startedAt: Date
    let workoutState: WorkoutState

    // In-progress UI state that must survive minimizing, but not a kill: reopening at
    // the same set is enough to enter reps again.
    var pendingStructuredSetIndex: Int?  // For structured AMRAP logging
    var pendingRepEntry: (exerciseIndex: Int, setNumber: Int)?  // Identity of the set the rep-input sheet was opened for
    var showingRepInput = false
    var showingOpenExercisesPrompt = false  // Finished the end of the list with earlier lifts open
    var celebratingPR: AppState.LogRepsResult?  // Drives the confetti PR cover; set after a short delay
    /// The latest PR, flashed on the live set card. Set with every PR, confetti or not.
    var prFlash: AppState.LogRepsResult?
    /// A rest ended while minimized and the workout hasn't reopened yet
    private(set) var restDoneWhileMinimized = false
    /// True when this session came back from a saved copy after an app kill
    let wasRestoredAfterKill: Bool

    @ObservationIgnored private unowned let appState: AppState
    @ObservationIgnored private let storeManager = StoreManager.shared
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var watchReachability: AnyCancellable?
    @ObservationIgnored private var lastSyncedWatchSet: (exerciseIndex: Int, setNumber: Int)?  // Set identity last synced to the Watch
    @ObservationIgnored private var queuedCelebration: AppState.LogRepsResult?
    @ObservationIgnored private var watchWorkoutId: String?
    @ObservationIgnored private var surfacesActive = false
    @ObservationIgnored private var isEnded = false
    @ObservationIgnored private var lastUpdatedAt: Date
    @ObservationIgnored private var pendingSetUndo = SetUndoInfo()  // What an AMRAP log replaced, until its set completes
    @ObservationIgnored private var legacyPendingLifts: [WorkoutExercise] = []

    private var isOnScreen: Bool {
        appState.presentedSession === self
    }

    /// Whether supersets are enabled (requires premium + user setting)
    var supersetsEnabled: Bool {
        storeManager.canAccess(.supersets) && appState.settings.supersetAccessories
    }

    // MARK: - Lifecycle

    /// Start a new session on a day of the current program
    init(appState: AppState, week: Int, day: Int, accessoriesOnly: Bool = false) {
        let now = Date()
        self.id = UUID()
        self.appState = appState
        self.week = week
        self.day = day
        self.programId = appState.userData.selectedProgram
        self.cycleStartDate = appState.userData.currentCycleStartDate
        self.startedAt = now
        self.lastUpdatedAt = now
        self.workoutState = WorkoutState()
        self.wasRestoredAfterKill = false
        setupWorkout(accessoriesOnly: accessoriesOnly)
        observeChangesToSave()
    }

    /// Bring back a saved session. Nothing outside the app is touched until
    /// `activateSurfaces` runs, which waits for the answer if the session is stale.
    init(appState: AppState, restoring saved: PersistedWorkoutSession) {
        self.id = saved.id
        self.appState = appState
        self.week = saved.week
        self.day = saved.day
        self.programId = saved.programId
        self.cycleStartDate = saved.cycleStartDate
        self.startedAt = saved.startedAt
        self.lastUpdatedAt = saved.lastUpdatedAt
        self.watchWorkoutId = saved.watchWorkoutId
        self.workoutState = WorkoutState(snapshot: saved.state)
        self.legacyPendingLifts = [saved.pendingLinearExercise].compactMap { $0 } + (saved.queuedLinearExercises ?? [])
        self.wasRestoredAfterKill = true
        observeChangesToSave()
    }

    /// Start what lives outside the app: Fitness and the Watch, plus the rest surfaces
    /// when resuming a saved rest. Runs once per session.
    func activateSurfaces() {
        guard !surfacesActive, !isEnded else { return }
        surfacesActive = true

        guard wasRestoredAfterKill else {
            startHealthKitWorkout()
            setupWatchSync()
            persist()
            return
        }

        // HKWorkoutBuilder doesn't survive a kill, so build a new one from the saved
        // start date. What gets saved is only dates and totals, so nothing is lost.
        // A session saved by an earlier build may still be waiting on its question sheet
        for exercise in legacyPendingLifts {
            logLinearResult(for: exercise)
        }
        legacyPendingLifts = []

        let fitnessStart = savedSession().fitnessStartDate()
        Logger.info("Restored workout: rebuilding the Fitness workout from \(fitnessStart)", category: .healthKit)
        startHealthKitWorkout(startDate: fitnessStart)
        setupWatchSync()
        restoreRestSurfaces()
    }

    /// Bring back what a kill took from a rest. Launch ends every Live Activity, so a
    /// rest still running gets a new one, on its original end date. The notification is
    /// still scheduled with the system, and a rest that ended meanwhile was cleared
    /// silently by `WorkoutState(snapshot:)`, so neither needs anything here.
    private func restoreRestSurfaces() {
        if workoutState.timerIsRunning, let endDate = workoutState.timerEndDate, let exercise = workoutState.currentExercise {
            if storeManager.canAccess(.liveActivity) {
                LiveActivityManager.shared.startTimer(
                    exerciseName: exercise.name,
                    duration: workoutState.timerDuration,
                    nextSetInfo: "Set \(workoutState.currentSetNumber) of \(exercise.totalSets)",
                    endTime: endDate
                )
            }
            startTimerTickLoop()
        }
        sendRestTimerStateToWatchIfResting()
    }

    /// The workout screen opened: anything that waited for it can show now
    func workoutScreenDidAppear() {
        restDoneWhileMinimized = false
        reconcileSupersets()
        if workoutState.reachedEndWithOpenExercises {
            showingOpenExercisesPrompt = true
        }
        if let queuedCelebration {
            self.queuedCelebration = nil
            presentPRCelebration(queuedCelebration)
        }
    }

    /// Pairs are made when the workout starts, but the setting (or the subscription
    /// behind it) can change mid-workout. Turned off, the pairs not yet started become
    /// their own exercises rather than staying attached to a card nobody sees.
    func reconcileSupersets() {
        guard !supersetsEnabled, workoutState.unpairUnstartedSupersets() else { return }
        persist()
        syncWorkoutStateToWatch()
    }

    /// Catch up after the app was in the background, where the tick loop doesn't run
    func appDidBecomeActive() {
        guard workoutState.timerIsRunning else { return }
        timerTick()
    }

    /// Mark the session over. Any later callback or pending save does nothing.
    func markEnded() {
        isEnded = true
        stopTimer()
    }

    // MARK: - Saving

    /// Save whenever anything in the snapshot changes, however it changed. Ticks don't
    /// count: the snapshot holds the end date, not the seconds remaining.
    private func observeChangesToSave() {
        withObservationTracking {
            _ = workoutState.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isEnded else { return }
                self.lastUpdatedAt = Date()
                self.persist()
                self.observeChangesToSave()
            }
        }
    }

    func persist() {
        guard !isEnded else { return }
        appState.saveWorkoutSession(savedSession())
    }

    private func savedSession() -> PersistedWorkoutSession {
        PersistedWorkoutSession(
            id: id,
            week: week,
            day: day,
            programId: programId,
            cycleStartDate: cycleStartDate,
            startedAt: startedAt,
            lastUpdatedAt: lastUpdatedAt,
            watchWorkoutId: watchWorkoutId,
            state: workoutState.snapshot,
            pendingLinearExercise: nil,
            queuedLinearExercises: nil
        )
    }

    /// Counts as activity: the lifter chose to carry on with a stale session
    func touch() {
        lastUpdatedAt = Date()
        persist()
    }

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdatedAt) > PersistedWorkoutSession.staleInterval
    }

    // MARK: - Set Info

    var setInfoText: String {
        guard let exercise = workoutState.currentExercise else { return "" }
        return "Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
    }

    /// Build the exercise list from the day's plan. Its weights are the session's
    /// snapshot from here on. Accessories-only leaves out the main lifts, so there's
    /// nothing to pair with and every accessory is its own exercise.
    private func setupWorkout(accessoriesOnly: Bool) {
        guard var plan = appState.dayPlan(week: week, day: day) else { return }
        if accessoriesOnly {
            plan = plan.filter { if case .accessory = $0 { return true } else { return false } }
        }

        var exercises: [WorkoutExercise] = []
        var accessories: [SupersetAccessoryData] = []
        var accessoryExercises: [WorkoutExercise] = []
        
        for item in plan {
            switch item {
            case let .volume(name, lift, weight, intensity, sets, repsPerSet, repOutTarget, _, _, _, calcWeight):
                exercises.append(
                    WorkoutExercise.fromVolumeItem(
                        name: name,
                        lift: lift,
                        weight: weight,
                        sets: sets,
                        repsPerSet: repsPerSet,
                        repOutTarget: repOutTarget,
                        intensity: intensity,
                        calculatedWeight: calcWeight
                    )
                )
            case let .structured(name, lift, _, setInfos, _):
                exercises.append(
                    WorkoutExercise.fromStructured(
                        name: name,
                        lift: lift,
                        sets: setInfos
                    )
                )
            case let .linear(name, info):
                exercises.append(
                    WorkoutExercise.fromLinear(
                        name: name,
                        info: info
                    )
                )
            case let .accessory(name, sets, reps, lastLog):
                accessories.append(SupersetAccessoryData(
                    name: name,
                    sets: sets,
                    reps: reps,
                    weight: lastLog?.weight,
                    lastWasEasy: lastLog?.wasEasy
                ))
                // Also create workout exercise for standalone accessory mode
                accessoryExercises.append(
                    WorkoutExercise.fromAccessory(
                        name: name,
                        sets: sets,
                        reps: reps,
                        lastLogWeight: lastLog?.weight,
                        lastWasEasy: lastLog?.wasEasy
                    )
                )
            default:
                break
            }
        }
        
        let mainLiftCount = exercises.count
        
        // Pairs are made only while supersets are available; turning them off later
        // unpairs what hasn't started (reconcileSupersets).
        if supersetsEnabled {
            // Superset mode: pair accessories with main lifts
            // Any "extra" accessories beyond the number of main lifts get added at the end
            for (index, accessory) in accessories.enumerated() {
                if index < mainLiftCount {
                    // Pair with corresponding main lift
                    workoutState.supersetAccessories[index] = accessory
                } else {
                    // Extra accessory - add as standalone exercise at the end
                    exercises.append(accessoryExercises[index])
                }
            }
        } else {
            // Superset mode is OFF - add all accessories as exercises at the end
            exercises.append(contentsOf: accessoryExercises)
        }
        
        workoutState.exercises = exercises
        workoutState.timerDuration = appState.settings.restTimerDuration
    }
    
    // MARK: - HealthKit Integration
    
    private func startHealthKitWorkout(startDate: Date? = nil) {
        // Apple Fitness is a premium feature
        guard storeManager.canAccess(.appleFitness) else { return }
        guard appState.settings.healthKitEnabled else { return }
        
        let workoutName = workoutState.exercises.allSatisfy(\.isAccessory)
            ? "Accessory Workout - Day \(day)"
            : "Week \(week), Day \(day) - \(appState.dayTitle(day: day))"
        Task {
            do {
                try await HealthKitManager.shared.startWorkout(name: workoutName, startDate: startDate)
            } catch {
                Logger.error("Failed to start HealthKit workout: \(error)", category: .healthKit)
            }
        }
    }
    
    // MARK: - Watch Sync
    
    /// Notify Watch to start workout session for heart rate collection. Messages from
    /// the Watch come here rather than to a view, so they arrive while minimized.
    private func setupWatchSync() {
        let manager = WatchConnectivityManager.shared
        Logger.debug("🔵 setupWatchSync: isReachable=\(manager.isWatchReachable)", category: .general)

        // Tell the Watch whether it may write its own HealthKit workout, using the
        // same premium + setting gate as the phone's HKWorkoutBuilder so the two agree
        // about who owns the workout (and a lapsed subscription can't sync via Watch).
        let healthKitEnabled = storeManager.canAccess(.appleFitness) && appState.settings.healthKitEnabled
        if let watchWorkoutId {
            // A relaunch: the same id lets the Watch carry on with its session.
            manager.resumeWorkout(id: watchWorkoutId, healthKitEnabled: healthKitEnabled)
        } else {
            manager.sendWorkoutStarted(healthKitEnabled: healthKitEnabled)
            watchWorkoutId = manager.activeWorkoutId
        }
        Logger.debug("✅ Sent workout start to Watch (healthKitEnabled: \(healthKitEnabled))", category: .general)

        manager.onSetCompletedFromWatch = { [weak self] reps, exerciseIndex, setNumber in
            self?.handleSetCompleteFromWatch(reps: reps, exerciseIndex: exerciseIndex, setNumber: setNumber)
        }

        // The Watch only learns set details from live messages, so a Watch that
        // connects mid-workout needs the current state resent.
        watchReachability = manager.$isWatchReachable
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.syncWorkoutStateToWatch()
                self?.sendRestTimerStateToWatchIfResting()
            }

        // Send initial workout state after a brief delay (to allow workout to start on Watch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.syncWorkoutStateToWatch()
        }
    }

    /// Notify Watch to end workout session
    func syncWorkoutEndedToWatch(saveWorkout: Bool = true) {
        WatchConnectivityManager.shared.onSetCompletedFromWatch = nil
        watchReachability = nil
        WatchConnectivityManager.shared.sendWorkoutEnded(saveWorkout: saveWorkout)
    }
    
    /// Handle set completion triggered from Watch
    /// - Parameters:
    ///   - reps: Rep count from Watch for AMRAP sets, nil for normal sets
    ///   - exerciseIndex: Exercise index the Watch was showing (nil on older Watch builds)
    ///   - setNumber: Set number the Watch was showing (nil on older Watch builds)
    func handleSetCompleteFromWatch(reps: Int?, exerciseIndex: Int?, setNumber: Int?) {
        guard let exercise = workoutState.currentExercise else { return }

        let currentExercise = workoutState.currentExerciseIndex
        let currentSet = workoutState.currentSetNumber

        // Resolve which set the Watch was acting on. Newer Watch builds stamp the
        // completion with the exact (exerciseIndex, setNumber) the Watch was
        // showing; older builds omit both, so fall back to the set last synced to
        // the Watch.
        let watchTarget: (exerciseIndex: Int, setNumber: Int)?
        if let exerciseIndex = exerciseIndex, let setNumber = setNumber {
            watchTarget = (exerciseIndex: exerciseIndex, setNumber: setNumber)
        } else {
            watchTarget = lastSyncedWatchSet
        }

        // Identity guard: only complete the set the Watch was actually showing,
        // and only if the phone is still on that exact set and it isn't already
        // done. Drops stale "set complete" messages that arrive after the phone
        // advanced (which would otherwise complete the next exercise's set 1).
        guard let target = watchTarget,
              target.exerciseIndex == currentExercise,
              target.setNumber == currentSet,
              !workoutState.isSetCompleted(currentSet) else {
            Logger.debug("Ignoring stale Watch set-complete (target: \(String(describing: watchTarget)), current: exercise \(currentExercise) set \(currentSet))", category: .general)
            return
        }

        Logger.debug("⌚️ Completing set from Watch: \(exercise.name) set \(currentSet) (reps: \(reps?.description ?? "nil"))", category: .general)
        
        // Same logic as the phone's Complete button, so a set finished on the Watch
        // progresses, logs and counts toward PRs just the same. A linear lift's result
        // comes from its sets, so several can finish here with the phone in a pocket.
        let structuredSetInfo = exercise.structuredSetInfo.flatMap { sets in
            sets.indices.contains(currentSet - 1) ? sets[currentSet - 1] : nil
        }

        var celebration: AppState.LogRepsResult?
        if let setInfo = structuredSetInfo, setInfo.isAMRAP {
            // Tested first: isCurrentSetRepOut is also true for structured AMRAPs,
            // and those must not go through the volume logger.
            celebration = logAMRAPSet(exercise: exercise, structuredSetIndex: setInfo.setIndex, reps: reps ?? setInfo.targetReps)
        } else if workoutState.isCurrentSetRepOut {
            celebration = logAMRAPSet(exercise: exercise, structuredSetIndex: nil, reps: reps ?? exercise.repOutTarget)
        }

        completeSetAndStartTimer()

        if let celebration, celebration.isNewPR {
            presentPRCelebration(celebration)
        }
        
        // Sync updated state back to Watch
        syncWorkoutStateToWatch()
    }

    /// Log reps for an AMRAP set (structured when given a set index, otherwise volume)
    /// and record any PR for the share card and review-prompt tracking.
    func logAMRAPSet(exercise: WorkoutExercise, structuredSetIndex: Int?, reps: Int, note: String = "") -> AppState.LogRepsResult? {
        guard let lift = exercise.lift else { return nil }

        if let setIndex = structuredSetIndex {
            pendingSetUndo.previousReps = appState.getStructuredReps(lift: lift, week: week, day: day, setIndex: setIndex)
        } else {
            pendingSetUndo.previousReps = appState.getLog(lift: lift, week: week, day: day)?.repsLastSet
        }

        let result: AppState.LogRepsResult?
        if let setIndex = structuredSetIndex {
            result = appState.logStructuredReps(lift: lift, week: week, day: day, setIndex: setIndex, reps: reps, note: note)
            workoutState.structuredLoggedReps[exercise.id, default: [:]][setIndex] = reps
        } else {
            result = appState.logReps(lift: lift, week: week, day: day, reps: reps, note: note)
            if result != nil {
                workoutState.repOutLogs[lift] = reps
            }
        }
        guard let result else { return nil }

        // The share card shows each lift's strongest AMRAP result, so a back-off
        // AMRAP doesn't replace the heavy top set's E1RM.
        if result.newE1RM > (workoutState.amrapResults[lift]?.e1rm ?? 0) {
            workoutState.amrapResults[lift] = WorkoutAMRAPResult(weight: result.weight, reps: result.reps, e1rm: result.newE1RM)
        }

        recordPRIfNew(result)
        return result
    }

    /// Note a PR for the summary and share card, and count it toward review-request
    /// eligibility (queued only; presented once the workout is dismissed).
    private func recordPRIfNew(_ result: AppState.LogRepsResult) {
        guard result.isNewPR else { return }
        workoutState.prsAchieved.append(WorkoutPRRecord(
            liftName: result.liftName,
            weight: result.weight,
            reps: result.reps,
            newE1RM: result.newE1RM,
            previousE1RM: result.previousE1RM
        ))
        ReviewRequestManager.shared.recordPRAchieved()
    }

    /// Celebrate a PR after the sheet underneath has had time to dismiss: the flash on
    /// the live set card always, the confetti cover when that setting is on. A PR on the
    /// last set is celebrated by the summary it lands on, so it appears only once.
    func presentPRCelebration(_ result: AppState.LogRepsResult) {
        guard !workoutState.isFinished else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if self.isOnScreen {
                self.prFlash = result
                if self.appState.settings.prConfetti {
                    self.celebratingPR = result
                }
            } else {
                // A Watch set while minimized: celebrate when the workout reopens.
                self.queuedCelebration = result
            }
        }
    }

    /// Log a linear lift's result, derived from its sets: any missed set is a failure.
    private func logLinearResult(for exercise: WorkoutExercise) {
        guard let lift = exercise.lift else { return }

        guard !workoutState.hasFailedSets(for: exercise.id) else {
            appState.logLinearFailure(
                lift: lift,
                week: week,
                day: day,
                weight: exercise.weight,
                reps: exercise.repsPerSet,
                sets: exercise.totalSets
            )
            return
        }

        guard let result = appState.logLinearSuccess(
            lift: lift,
            week: week,
            day: day,
            weight: exercise.weight,
            reps: exercise.repsPerSet,
            sets: exercise.totalSets
        ) else { return }

        recordPRIfNew(result)
        if result.isNewPR {
            presentPRCelebration(result)
        }
    }
    
    /// Send current workout state to Watch
    func syncWorkoutStateToWatch() {
        guard !isEnded, let exercise = workoutState.currentExercise else { return }
        
        // Get current set weight and reps
        let currentWeight: Double
        let currentReps: Int
        
        if exercise.isStructured,
           let sets = exercise.structuredSetInfo,
           workoutState.currentSetNumber > 0 && workoutState.currentSetNumber <= sets.count {
            let setInfo = sets[workoutState.currentSetNumber - 1]
            currentWeight = setInfo.weight
            currentReps = setInfo.targetReps
        } else {
            currentWeight = exercise.weight
            currentReps = exercise.repsPerSet
        }
        
        // Build next set info
        var nextSetInfo: String? = nil
        if workoutState.showingTimer {
            nextSetInfo = "Next: Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
        }
        
        // Determine if current set is any type of AMRAP (volume or structured)
        let isStructuredAMRAP: Bool = {
            guard exercise.isStructured,
                  let sets = exercise.structuredSetInfo,
                  workoutState.currentSetNumber > 0 && workoutState.currentSetNumber <= sets.count else {
                return false
            }
            return sets[workoutState.currentSetNumber - 1].isAMRAP
        }()
        let isAnyAMRAP = workoutState.isCurrentSetRepOut || isStructuredAMRAP
        
        let state = WatchWorkoutState(
            exerciseName: exercise.name,
            currentSet: workoutState.currentSetNumber,
            totalSets: exercise.totalSets,
            weight: currentWeight,
            targetReps: currentReps,
            isRestTimerActive: workoutState.showingTimer && workoutState.timerIsRunning,
            restTimerRemaining: workoutState.timerRemaining,
            restTimerDuration: workoutState.timerDuration,
            useMetric: appState.settings.useMetric,
            nextSetInfo: nextSetInfo,
            isRepOutSet: workoutState.isCurrentSetRepOut,
            isAMRAPSet: isAnyAMRAP,
            exerciseIndex: workoutState.currentExerciseIndex
        )

        // Record the set identity the Watch is now displaying. A Watch "set
        // complete" acts on this set; handleSetCompleteFromWatch uses it as the
        // backward-compatible fallback when the message carries no identity.
        lastSyncedWatchSet = (exerciseIndex: workoutState.currentExerciseIndex, setNumber: workoutState.currentSetNumber)

        WatchConnectivityManager.shared.sendWorkoutState(state)
    }
    
    /// Whether the user has made any progress in this workout (completed at least one set)
    var hasWorkoutProgress: Bool {
        workoutState.completedSetsCount > 0
    }
    
    /// Exit workout without saving to Apple Fitness
    func exitWorkoutWithoutSaving() {
        tearDownWorkout(saveWatchWorkout: false)
        appState.closeActiveSession(self)
    }

    /// End every surface of an abandoned workout: the timer mirror, pending
    /// notification, Live Activity, Watch session and HealthKit builder.
    func tearDownWorkout(saveWatchWorkout: Bool) {
        stopTimer()
        RestTimerStatus.shared.timerCleared()
        NotificationManager.shared.cancelRestTimerNotification()

        // End Watch workout session
        syncWorkoutEndedToWatch(saveWorkout: saveWatchWorkout)

        // End Live Activity
        LiveActivityManager.shared.endTimerSync()
        
        // Unconditional: Fitness access may have changed since the builder started,
        // and a leftover builder would absorb the next workout.
        HealthKitManager.shared.discardWorkout()
    }
    
    /// Stop with work left and go to the summary. What's already logged stays. Linear
    /// lifts with sets left never logged, so they hold their weight.
    func finishEarly() {
        cancelRestSurfacesIfResting()
        showingOpenExercisesPrompt = false
        workoutState.finishedEarly = true
    }

    /// Go back to the first exercise with sets left
    func goBackToOpenExercise() {
        showingOpenExercisesPrompt = false
        guard let index = workoutState.firstOpenExerciseIndex else { return }
        workoutState.jumpToExercise(index)
        syncWorkoutStateToWatch()
    }

    func finishAndDismiss() {
        guard !isEnded else { return }  // A second tap on Done must not log twice
        stopTimer()
        RestTimerStatus.shared.timerCleared()
        NotificationManager.shared.cancelRestTimerNotification()

        // Accessories log here, not set by set, so undo has nothing to take back and only
        // work that was done gets recorded. Dated at the last activity, so a summary left
        // open overnight still lands on the day of the workout. Each log also replaces
        // the easy flag, which is how the "last time was easy" nudge shows only once.
        appState.logPerformedAccessories(workoutState.performedAccessories, date: lastUpdatedAt, week: week, day: day)

        // Capture whether the Watch owns the HealthKit workout BEFORE
        // syncWorkoutEndedToWatch() clears the flag (sendWorkoutEnded resets it).
        let watchOwnsHealthKitWorkout = WatchConnectivityManager.shared.isWatchWorkoutSessionActive

        // End Watch sync
        syncWorkoutEndedToWatch()

        // End Live Activity (lock screen / Dynamic Island) — abort paths do
        // this; the normal-completion path used to skip it and orphan the
        // activity if a rest timer was still running when the user tapped Done.
        LiveActivityManager.shared.endTimerSync()

        // End HealthKit workout if active (premium feature)
        saveToFitness(watchOwnsHealthKitWorkout: watchOwnsHealthKitWorkout)

        // Record workout completion for review request tracking. This may
        // queue a review request at milestone workouts (3rd, 10th, 25th, etc.),
        // but presentation is deferred so the rating prompt never lands on the
        // workout-complete celebration — it's flushed below once this view has
        // dismissed. A workout stopped early doesn't count toward these milestones.
        if workoutState.isWorkoutComplete {
            ReviewRequestManager.shared.recordWorkoutCompleted()
        }

        // Check if completing this workout completes the week
        // We need to check after the workout is logged, so do it on the next run loop
        let appState = appState
        let week = week
        Task { @MainActor in
            // Small delay to ensure logs are saved
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            if appState.weekCompletionFraction(for: week) == 1.0 {
                ReviewRequestManager.shared.recordWeekCompleted(weekNumber: week)
            }
            // Flush any queued review request (workout milestone, week, or PR)
            // now that this view is dismissed — presents ~2s later over a clean
            // screen with no celebration/summary/sheet on top.
            ReviewRequestManager.shared.presentPendingReviewRequestIfNeeded()
        }

        appState.closeActiveSession(self)
        appState.returnToHomeAfterWorkout(week: week)
    }

    /// Write the workout to Apple Fitness, or drop the builder if it shouldn't be saved.
    /// Every outcome is logged, including a builder that couldn't be rebuilt after a
    /// relaunch, so a missing Fitness workout can be traced.
    private func saveToFitness(watchOwnsHealthKitWorkout: Bool) {
        guard storeManager.canAccess(.appleFitness) && appState.settings.healthKitEnabled else {
            HealthKitManager.shared.discardWorkout()
            return
        }
        if watchOwnsHealthKitWorkout {
            // The Watch is running its own HealthKit-saving session (with live
            // heart-rate data) — discard the phone's builder so we don't write a
            // duplicate workout.
            HealthKitManager.shared.discardWorkout()
            Logger.info("Fitness: the Watch owns this workout, so the phone isn't saving one", category: .healthKit)
            return
        }
        let stats = calculateWorkoutStats()
        let wasRestored = wasRestoredAfterKill
        Task {
            do {
                if try await HealthKitManager.shared.endWorkout(
                    totalVolume: stats.volume,
                    setCount: stats.sets,
                    repCount: stats.reps
                ) == nil {
                    Logger.error("Fitness: no workout saved because no HealthKit workout was active (restored after relaunch: \(wasRestored))", category: .healthKit)
                }
            } catch {
                Logger.error("Fitness: failed to save workout (restored after relaunch: \(wasRestored)): \(error)", category: .healthKit)
            }
        }
    }
    
    /// Calculate total volume, sets, and reps from the workout
    func calculateWorkoutStats() -> (volume: Double, sets: Int, reps: Int) {
        var totalVolume: Double = 0
        var totalSets = 0
        var totalReps = 0
        
        for exercise in workoutState.exercises {
            guard let completedSetNumbers = workoutState.completedSets[exercise.id] else { continue }
            let setsCompleted = completedSetNumbers.count
            let setsMissed = workoutState.failedSets[exercise.id]?.count ?? 0
            totalSets += setsCompleted
            
            if exercise.isStructured, let setInfos = exercise.structuredSetInfo {
                // Structured exercises have different weights per set
                for setNumber in completedSetNumbers {
                    let setIndex = setNumber - 1  // Convert 1-indexed to 0-indexed
                    if setIndex >= 0 && setIndex < setInfos.count {
                        let setInfo = setInfos[setIndex]
                        let reps = workoutState.structuredLoggedReps[exercise.id]?[setInfo.setIndex] ?? setInfo.loggedReps ?? setInfo.targetReps
                        totalReps += reps
                        totalVolume += setInfo.weight * Double(reps)
                    }
                }
            } else {
                // Standard exercises: same weight for all sets
                let repsPerCompletedSet = exercise.repsPerSet
                
                // Check if there's a rep-out log for this lift
                if let lift = exercise.lift, let repOutReps = workoutState.repOutLogs[lift] {
                    // Count regular sets and the rep-out set separately
                    let regularSets = max(0, setsCompleted - 1)
                    let regularReps = regularSets * repsPerCompletedSet
                    totalReps += regularReps + repOutReps
                    totalVolume += exercise.weight * Double(regularReps + repOutReps)
                } else {
                    // No rep-out logged, use standard reps. A missed set counts one rep
                    // short, the same assumption its logged result makes.
                    let reps = setsCompleted * repsPerCompletedSet - setsMissed
                    totalReps += reps
                    totalVolume += exercise.weight * Double(reps)
                }
            }
        }
        
        return (totalVolume, totalSets, totalReps)
    }
    
    func handleSetComplete() {
        guard let exercise = workoutState.currentExercise else { return }

        // Tactile confirmation for the app's most-pressed button.
        Haptics.medium()

        // Guard: an already-logged set (reached via the exercise list) just moves on.
        // No rep input, result dialog or rest timer, which would log it a second time.
        if workoutState.isSetCompleted(workoutState.currentSetNumber) {
            Logger.debug("Set \(workoutState.currentSetNumber) already completed, advancing without rep input", category: .general)
            workoutState.markSetComplete()
            showingOpenExercisesPrompt = workoutState.reachedEndWithOpenExercises
            syncWorkoutStateToWatch()
            return
        }

        // Check if this is an nSuns AMRAP set
        if exercise.isStructured,
           let sets = exercise.structuredSetInfo,
           workoutState.currentSetNumber > 0 && workoutState.currentSetNumber <= sets.count {
            let currentSetInfo = sets[workoutState.currentSetNumber - 1]
            if currentSetInfo.isAMRAP {
                // Store the set index for logging
                pendingStructuredSetIndex = currentSetInfo.setIndex
                // Stamp the identity of the set the sheet is opened for so a
                // re-entrant ✓ tap during the dismiss animation can't log the
                // next set (see onSave identity guard).
                pendingRepEntry = (exerciseIndex: workoutState.currentExerciseIndex, setNumber: workoutState.currentSetNumber)
                showingRepInput = true
                return
            }
        } else if workoutState.isCurrentSetRepOut {
            // Standard volume AMRAP set
            pendingStructuredSetIndex = nil
            // Stamp the identity of the set the sheet is opened for (see onSave
            // identity guard) to block a re-entrant ✓ tap during dismissal.
            pendingRepEntry = (exerciseIndex: workoutState.currentExerciseIndex, setNumber: workoutState.currentSetNumber)
            showingRepInput = true
            return
        }
        
        // Not an AMRAP - just complete the set and start timer
        completeSetAndStartTimer()
    }
    
    /// The lifter missed reps on this set. It still counts as done and they still rest,
    /// but the lift's result becomes a failure.
    func handleSetMissed() {
        guard let exercise = workoutState.currentExercise, exercise.isLinear,
              !workoutState.isSetCompleted(workoutState.currentSetNumber) else { return }
        Haptics.medium()
        completeSetAndStartTimer(missed: true)
    }

    func completeSetAndStartTimer(missed: Bool = false) {
        guard let exercise = workoutState.currentExercise else { return }

        var undo = pendingSetUndo
        pendingSetUndo = SetUndoInfo()

        // Captured before logging, so undo can put back what a redo replaces
        let completedSoFar = workoutState.completedSets[exercise.id] ?? []
        let finishesExercise = completedSoFar.union([workoutState.currentSetNumber]).count >= exercise.totalSets
        if exercise.isLinear, finishesExercise, let lift = exercise.lift {
            undo.finishedLinearLift = true
            undo.previousLinearEntry = appState.getLinearLog(lift: lift, week: week, day: day)
            undo.previousTrainingMax = appState.userData.trainingMaxes.canonicalLiftValue(for: lift)
        }
        let marksStructuredDone = finishesExercise && exercise.isStructured
            && exercise.structuredSetInfo?.contains(where: { $0.isAMRAP }) == false
        if marksStructuredDone, let lift = exercise.lift {
            undo.createdStructuredLog = appState.getStructuredLog(lift: lift, week: week, day: day) == nil
        }

        if missed {
            workoutState.markSetFailed(undo: undo)
        } else {
            workoutState.markSetComplete(undo: undo)
        }

        if undo.finishedLinearLift {
            logLinearResult(for: exercise)
        }
        // Marks a structured lift with no AMRAP sets (BBB, deload weeks) as done, so the
        // day shows as complete.
        if marksStructuredDone, let lift = exercise.lift {
            appState.markStructuredCompleted(lift: lift, week: week, day: day)
        }

        // No rest before the summary, or before asking about lifts still open
        guard !workoutState.isFinished else { return }
        guard !workoutState.reachedEndWithOpenExercises else {
            syncWorkoutStateToWatch()
            if isOnScreen { showingOpenExercisesPrompt = true }
            return
        }

        // Start rest timer — the surfaces (Live Activity / notification /
        // Watch) are created exactly once here, when the rest actually
        // begins; the tick loop can be restarted freely.
        restDoneWhileMinimized = false
        let defaultRest = exercise.isAccessory ? appState.settings.accessoryRestSeconds : appState.settings.restTimerDuration
        workoutState.startTimer(
            duration: workoutState.restDuration(for: exercise, default: defaultRest),
            forExercise: exercise.id
        )
        startRestSurfaces()
        startTimerTickLoop()
    }

    // MARK: - Undo

    var canUndoLastSet: Bool {
        !workoutState.completionHistory.isEmpty && !workoutState.finishedEarly
    }

    /// Undo the most recently completed set
    func undoLastSet() {
        guard canUndoLastSet, let last = workoutState.completionHistory.last else { return }
        undoSet(exerciseId: last.exerciseId, setNumber: last.setNumber)
    }

    /// Reopen a completed set and reverse what it logged. Any running rest belonged to
    /// that set, so it goes too, and the Watch moves back with the phone.
    func undoSet(exerciseId: UUID, setNumber: Int) {
        guard let exercise = workoutState.exercises.first(where: { $0.id == exerciseId }) else { return }
        Haptics.light()
        cancelRestSurfacesIfResting()
        celebratingPR = nil
        prFlash = nil
        queuedCelebration = nil
        showingOpenExercisesPrompt = false

        let record = workoutState.reopenSet(exerciseId: exerciseId, setNumber: setNumber)
        if let lift = exercise.lift {
            revertLogs(for: exercise, lift: lift, setNumber: setNumber, undo: record?.undo ?? SetUndoInfo())
        }
        syncWorkoutStateToWatch()
    }

    private func revertLogs(for exercise: WorkoutExercise, lift: String, setNumber: Int, undo: SetUndoInfo) {
        if exercise.isLinear {
            // Records can sit on another set if the lifter reopened sets out of order
            let finish = undo.finishedLinearLift ? undo : workoutState.takeLinearFinish(exerciseId: exercise.id)
            if let finish {
                appState.revertLinearLog(lift: lift, week: week, day: day, reps: exercise.repsPerSet, sets: exercise.totalSets, undo: finish)
                removePR(lift: lift)
            }
            return
        }

        if let sets = exercise.structuredSetInfo {
            if sets.indices.contains(setNumber - 1), sets[setNumber - 1].isAMRAP {
                let setIndex = sets[setNumber - 1].setIndex
                if let reps = workoutState.structuredLoggedReps[exercise.id]?[setIndex] {
                    workoutState.structuredLoggedReps[exercise.id]?[setIndex] = nil
                    appState.revertStructuredReps(lift: lift, week: week, day: day, setIndex: setIndex, previousReps: undo.previousReps)
                    removePR(lift: lift, reps: reps)
                    workoutState.recomputeAMRAPResult(lift: lift) { E1RM.epley(weight: $0, reps: $1) }
                }
            } else if undo.createdStructuredLog || workoutState.takeStructuredLogCreation(exerciseId: exercise.id) {
                appState.clearStructuredLog(lift: lift, week: week, day: day)
            }
            return
        }

        // Volume: only the rep-out set logs anything
        if exercise.isRepOutSet(setNumber), let reps = workoutState.repOutLogs[lift] {
            workoutState.repOutLogs[lift] = nil
            appState.revertVolumeReps(lift: lift, week: week, day: day, previousReps: undo.previousReps)
            removePR(lift: lift, reps: reps)
            workoutState.recomputeAMRAPResult(lift: lift) { E1RM.epley(weight: $0, reps: $1) }
        }
    }

    /// Take back this session's PR for a lift, narrowed to a rep count when there can be several
    private func removePR(lift: String, reps: Int? = nil) {
        if let index = workoutState.prsAchieved.lastIndex(where: { $0.liftName == lift && (reps == nil || $0.reps == reps) }) {
            workoutState.prsAchieved.remove(at: index)
        }
    }

    /// Bump the running rest timer by `delta` seconds for this session only.
    /// Deliberately does NOT write `appState.settings.restTimerDuration` — a
    /// ±15s tap adjusts the running timer, not the user's saved default.
    func handleTimerAdjust(by delta: Int) {
        workoutState.adjustTimer(by: delta)

        // Mirror the new remaining to dependent sinks.
        if storeManager.canAccess(.liveActivity) {
            LiveActivityManager.shared.updateTimer(
                secondsRemaining: workoutState.timerRemaining,
                isPaused: workoutState.timerIsPaused
            )
        }
        if appState.settings.pushNotificationsEnabled,
           workoutState.timerIsRunning,
           let exercise = workoutState.currentExercise {
            NotificationManager.shared.cancelRestTimerNotification()
            NotificationManager.shared.scheduleRestTimerNotification(
                duration: workoutState.timerRemaining,
                exerciseName: exercise.name,
                nextSetInfo: "Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
            )
        }

        // Push the shifted timeline to the Watch (fresh endDate when running, or a
        // frozen remaining when paused). If the timer just hit zero the
        // handleTimerEnd() below immediately follows with sendRestTimerEnded().
        sendRestTimerStateToWatch()

        // If we shrunk past zero, end the timer immediately.
        if workoutState.timerRemaining <= 0 && workoutState.showingTimer {
            handleTimerEnd()
        }

        // ±15s tap feedback (light impact).
        Haptics.light()
    }
    
    /// Create the endDate-driven "surfaces" for a freshly started rest timer:
    /// Live Activity, background notification, and Watch state. Call exactly
    /// ONCE when a rest actually begins (see `completeSetAndStartTimer`). It
    /// must NOT run on resume/reappear — those surfaces are still valid, and
    /// re-creating them would restart the Dynamic Island / lock screen at full
    /// duration and fire the rest-complete notification late.
    func startRestSurfaces() {
        // Start Live Activity for lock screen / Dynamic Island (Pro only)
        let canAccessLiveActivity = storeManager.canAccess(.liveActivity)
        Logger.debug("🔵 Timer started - canAccess(.liveActivity): \(canAccessLiveActivity), isPremium: \(storeManager.isPremium)", category: .liveActivity)

        if canAccessLiveActivity, let exercise = workoutState.currentExercise {
            LiveActivityManager.shared.startTimer(
                exerciseName: exercise.name,
                duration: workoutState.timerDuration,
                nextSetInfo: "Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
            )
        }

        scheduleRestNotificationAfterAsking()

        // Send initial timer state to Watch (workout context + set-completion
        // identity), then the authoritative endDate-based rest-timer timeline.
        syncWorkoutStateToWatch()
        sendRestTimerStateToWatch()
    }

    /// Schedule the background alert for this rest. The first rest is where the app asks
    /// for notification permission, and that prompt can stay up for a while, so the rest
    /// may have been adjusted or ended by the time it's answered: read the timer afterwards.
    private func scheduleRestNotificationAfterAsking() {
        guard appState.settings.pushNotificationsEnabled else { return }
        Task { @MainActor [weak self] in
            await NotificationManager.shared.requestAuthorizationIfNeeded(notificationsEnabled: true)
            guard let self,
                  self.appState.activeSession === self,
                  self.appState.settings.pushNotificationsEnabled,
                  self.workoutState.timerIsRunning,
                  let endDate = self.workoutState.timerEndDate,
                  let exercise = self.workoutState.currentExercise else { return }
            NotificationManager.shared.scheduleRestTimerNotification(
                duration: Int(endDate.timeIntervalSinceNow.rounded(.up)),
                exerciseName: exercise.name,
                nextSetInfo: "Set \(self.workoutState.currentSetNumber) of \(exercise.totalSets)"
            )
        }
    }

    /// Push the current rest-timer timeline to the Watch as a single
    /// endDate-based message. Call once when the rest starts and again ONLY on a
    /// timeline change (pause / resume / ±15s adjust). It reads the live
    /// `workoutState`, so it must run AFTER the state mutation: a paused timer
    /// has `timerEndDate == nil` and `timerIsPaused == true`, while running/
    /// resumed/adjusted timers carry a fresh `timerEndDate`. The Watch renders
    /// the countdown locally from the endDate and schedules its own completion
    /// haptic, so no per-second traffic is needed.
    func sendRestTimerStateToWatch() {
        guard let exercise = workoutState.currentExercise else { return }
        WatchConnectivityManager.shared.sendRestTimerState(
            endDate: workoutState.timerIsPaused ? nil : workoutState.timerEndDate,
            duration: workoutState.timerDuration,
            remaining: workoutState.timerRemaining,
            isPaused: workoutState.timerIsPaused,
            exerciseName: exercise.name,
            nextSetInfo: "Next: Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
        )
    }

    /// Push the rest timeline to the Watch only if there is a rest. `sendRestTimerState`
    /// always counts as a running rest.
    private func sendRestTimerStateToWatchIfResting() {
        guard workoutState.showingTimer else { return }
        sendRestTimerStateToWatch()
    }

    /// (Re)start the 1s in-app tick loop that drives the countdown UI, the per-second
    /// Live Activity updates and the end of the rest. It belongs to the session, so a
    /// rest ends properly while minimized. Safe to call any time: it creates no surface
    /// and resets nothing, it only reads the endDate-driven timer state.
    func startTimerTickLoop() {
        stopTimer()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timerTick()
            }
        }
        // .common so scrolling a list while minimized doesn't hold back the end of a rest
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func timerTick() {
        workoutState.timerTick()

        // Update Live Activity with current time (Pro only)
        if storeManager.canAccess(.liveActivity) {
            LiveActivityManager.shared.updateTimer(
                secondsRemaining: workoutState.timerRemaining,
                isPaused: workoutState.timerIsPaused
            )
        }

        // The Watch renders the countdown locally from the endDate sent once via
        // sendRestTimerState(...), so no per-second Watch traffic is sent here —
        // only pause/resume/adjust push a new timeline.

        if workoutState.timerIsRunning && workoutState.timerRemaining <= 0 {
            handleTimerEnd()
        }
    }

    func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
        // Note: Don't end Live Activity here - it's handled in handleTimerEnd()
    }

    /// Fully tear down the rest timer and every surface it drives: the in-app
    /// tick loop, the timer state + RestTimerStatus mirror, the pending
    /// rest-complete notification, the Live Activity, and the Watch timer. Any
    /// path that abandons a running rest without ending the workout (jumping to
    /// or picking another exercise) must route through here so no surface
    /// outlives the rest it belonged to.
    func cancelRestSurfacesIfResting() {
        if workoutState.showingTimer { cancelRestSurfaces() }
    }

    func cancelRestSurfaces() {
        stopTimer()
        workoutState.skipTimer()  // clears timer state + RestTimerStatus mirror
        NotificationManager.shared.cancelRestTimerNotification()
        LiveActivityManager.shared.endTimerSync()
        WatchConnectivityManager.shared.sendRestTimerEnded()
    }
    
    func handleTimerEnd(playFeedback: Bool = true) {
        // Returning from the background ticks straight to 0, so a rest that ended
        // minutes ago also lands here. Its notification already alerted the user.
        let isStaleExpiry = (workoutState.timerEndDate?.timeIntervalSinceNow ?? 0) < -2
        let playFeedback = playFeedback && !isStaleExpiry
        // Off screen, the resume bar says the rest is over until the workout reopens.
        restDoneWhileMinimized = !isOnScreen
        workoutState.skipTimer()
        stopTimer()
        
        // End Live Activity
        LiveActivityManager.shared.endTimerSync()
        
        // Cancel push notification (app is in foreground, no need for notification)
        NotificationManager.shared.cancelRestTimerNotification()
        
        // Notify Watch that timer ended (plays haptic on Watch)
        WatchConnectivityManager.shared.sendRestTimerEnded()
        
        // Send updated workout state after a small delay to ensure timer state is cleared
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.syncWorkoutStateToWatch()
        }

        // Play haptics and chime — suppressed for a stale expiry detected on
        // returning from the background.
        if playFeedback {
            playTimerEndFeedback()
        }
    }

    /// Manual skip of the rest timer. Performs the same surface teardown as
    /// `handleTimerEnd` (Live Activity, notification, RestTimerStatus/timer
    /// state, Watch) and advances state, but deliberately skips
    /// `playTimerEndFeedback()` — a skip is a user action, not a rest
    /// completion, so it gets only a light tap on the phone with no chime and
    /// no triple-buzz fanfare. `sendRestTimerEnded()` still runs so the Watch's
    /// pending completion haptic is cancelled and no surface orphans.
    func handleTimerSkip() {
        Haptics.light()
        workoutState.skipTimer()
        stopTimer()
        LiveActivityManager.shared.endTimerSync()
        NotificationManager.shared.cancelRestTimerNotification()
        WatchConnectivityManager.shared.sendRestTimerEnded()

        // Send updated workout state after a small delay to ensure timer state is cleared
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.syncWorkoutStateToWatch()
        }
    }

    func playTimerEndFeedback() {
        // Strong haptic pattern - triple buzz (the final .success is the phone's
        // completion buzz; the Watch buzzes independently via sendRestTimerEnded).
        Haptics.warning()

        // Delay and buzz again for emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Haptics.warning()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            Haptics.success()
        }
        
        // While minimized the rest-complete notification is presented with its own sound
        // (see NotificationManager), so the chime would make it two.
        let notificationPlaysSound = !isOnScreen
            && appState.settings.pushNotificationsEnabled
            && NotificationManager.shared.isAuthorized

        // Only play sound if user has sound notifications enabled
        // Using AudioServicesPlayAlertSound to respect silent mode (vibrates only when silenced)
        if appState.settings.playSoundNotifications && !notificationPlaysSound {
            // 1322 = anticipate, 1323 = bloom, 1324 = calypso, 1325 = choo choo
            AudioServicesPlayAlertSound(1322)  // "Anticipate" - respects silent switch
        }
    }
    
    /// Mark the current standalone accessory as easy. It's logged at finish, for the
    /// "try heavier" nudge next time.
    func toggleCurrentAccessoryEasy() {
        let idx = workoutState.currentExerciseIndex
        guard idx < workoutState.exercises.count, workoutState.exercises[idx].isAccessory else { return }
        workoutState.exercises[idx].markedEasy.toggle()
    }

    /// Change the current standalone accessory's weight for this session. It's logged at finish.
    func updateStandaloneAccessoryWeight(_ weight: Double) {
        let idx = workoutState.currentExerciseIndex
        guard idx < workoutState.exercises.count, workoutState.exercises[idx].isAccessory else { return }
        workoutState.exercises[idx].weight = weight
    }

    /// Build a human-readable prescribed-reps line for the weight override sheet
    /// (e.g. "5 × 5+", "3 × 5", "3+ AMRAP at 95% TM").
    func prescribedRepsDescription(for exercise: WorkoutExercise) -> String? {
        if exercise.isStructured, let sets = exercise.structuredSetInfo {
            // Show the topmost AMRAP set for context (the "primary" set in nSuns)
            let amrapSets = sets.filter { $0.isAMRAP }
            if let primary = amrapSets.first(where: { $0.targetReps == 1 }) ?? amrapSets.first {
                return "\(sets.count) sets · \(primary.targetReps)+ AMRAP @ \(Int(round(primary.intensity * 100)))% TM"
            }
            return "\(sets.count) sets"
        }
        if exercise.isLinear {
            return "\(exercise.totalSets) × \(exercise.repsPerSet)"
        }
        if exercise.isAccessory {
            return "\(exercise.totalSets) × \(exercise.repsPerSet)"
        }
        // Volume (5/3/1 style): last set is rep-out
        let normalSets = max(0, exercise.totalSets - 1)
        if normalSets > 0 {
            return "\(normalSets) × \(exercise.repsPerSet), then \(exercise.repOutTarget)+ AMRAP"
        }
        return "\(exercise.repOutTarget)+ AMRAP"
    }

    /// Apply a weight override to the current exercise and persist it
    func applyWeightOverride(newWeight: Double, lift: String) {
        let exerciseName = workoutState.currentExercise?.name
        appState.setWeightOverride(lift: lift, week: week, day: day, weight: newWeight, itemName: exerciseName)
        refreshCurrentExerciseWeights(lift: lift, fallbackWeight: newWeight)
    }

    /// Clear a weight override and revert to the calculated weight
    func clearWeightOverride(lift: String) {
        appState.clearWeightOverride(lift: lift, week: week, day: day)
        refreshCurrentExerciseWeights(lift: lift, fallbackWeight: workoutState.currentExercise?.calculatedWeight)
    }

    /// Update the live exercise so the display changes immediately. Structured sets are
    /// re-read from the plan so they match what gets logged, matching by exercise name
    /// since a day can list the same lift twice (5/3/1 main + FSL).
    func refreshCurrentExerciseWeights(lift: String, fallbackWeight: Double?) {
        let idx = workoutState.currentExerciseIndex
        guard idx < workoutState.exercises.count else { return }
        var exercise = workoutState.exercises[idx]

        if exercise.isStructured {
            for item in appState.dayPlan(week: week, day: day) ?? [] {
                if case let .structured(name, planLift, _, setInfos, _) = item,
                   planLift == lift, name == exercise.name {
                    exercise.structuredSetInfo = setInfos
                    if let heaviest = setInfos.max(by: { $0.weight < $1.weight }) {
                        exercise.weight = heaviest.weight
                    }
                    break
                }
            }
        } else if let fallbackWeight {
            exercise.weight = fallbackWeight
        }
        workoutState.exercises[idx] = exercise
        syncWorkoutStateToWatch()
    }

    /// How long the workout took: up to its last change, so a summary left open doesn't
    /// keep counting. Nil for a session resumed long after it began, whose elapsed time
    /// says nothing about the workout.
    var workoutDuration: TimeInterval? {
        let duration = lastUpdatedAt.timeIntervalSince(startedAt)
        return duration <= PersistedWorkoutSession.staleInterval ? duration : nil
    }

    /// What happens next for one main lift, for the summary
    struct LiftOutlook: Identifiable {
        var id: String { lift }
        let lift: String
        let name: String
        let nextWeight: Double?
        /// Plain-language result, e.g. "+5 lb" or "Not finished, weight stays"
        let note: String?
    }

    /// One row per main lift. A day can list a lift twice (5/3/1 main + FSL), which gets
    /// one row, from the exercise that decides its progression.
    func liftOutlooks() -> [LiftOutlook] {
        var seen = Set<String>()
        return workoutState.exercises.compactMap { exercise in
            guard !exercise.isAccessory, let lift = exercise.lift, seen.insert(lift).inserted else { return nil }
            let doneSets = workoutState.completedSets[exercise.id]?.count ?? 0
            guard doneSets > 0 || workoutState.finishedEarly else { return nil }

            let next = appState.nextPlannedWeight(exercise: exercise.name, lift: lift, afterWeek: week, day: day)
            return LiftOutlook(lift: lift, name: exercise.name, nextWeight: next, note: outlookNote(for: exercise, next: next))
        }
    }

    private func outlookNote(for exercise: WorkoutExercise, next: Double?) -> String? {
        let finished = workoutState.isExerciseFinished(exercise)
        let useMetric = appState.settings.useMetric
        guard exercise.isLinear else {
            return finished ? nil : "Not finished"
        }
        guard finished else { return "Not finished, weight stays" }
        guard let next else { return workoutState.hasFailedSets(for: exercise.id) ? "Missed reps" : nil }
        if next > exercise.weight {
            return "+\((next - exercise.weight).formattedWeight(useMetric: useMetric))"
        }
        if next < exercise.weight { return "Missed reps, deload" }
        return workoutState.hasFailedSets(for: exercise.id) ? "Missed reps, weight stays" : nil
    }

    /// Each performed exercise's bar, under both its name and lift key (PRs use the lift)
    private func summaryBarWeights(for exercises: [WorkoutExercise]) -> [String: Double] {
        var map: [String: Double] = [:]
        for exercise in exercises {
            let weight = appState.barWeight(for: exercise.barKeySource)
            for key in [exercise.name, exercise.lift].compactMap({ $0 }) {
                map[UserSettings.barKey(key)] = weight
            }
        }
        return map
    }

    /// Build workout summary for sharing, covering what was actually done
    func buildWorkoutSummary() -> WorkoutSummary {
        let performed = workoutState.exercises.filter { (workoutState.completedSets[$0.id]?.count ?? 0) > 0 }
        let exercises: [WorkoutSummary.ExerciseSummary] = performed.map { exercise in
            let amrapResult = workoutState.amrapResults[exercise.lift ?? ""]
            let isAMRAP = exercise.isRepOutSet(exercise.totalSets) || (exercise.structuredSetInfo?.contains { $0.isAMRAP } == true)
            
            // Determine reps string
            let repsString: String
            if exercise.isStructured, let sets = exercise.structuredSetInfo {
                // For structured (nSuns), show varied reps
                let amrapSets = sets.filter { $0.isAMRAP }
                if let result = amrapResult {
                    repsString = "\(result.reps)"
                } else if let primary = amrapSets.first {
                    repsString = "\(primary.targetReps)+"
                } else {
                    repsString = "varied"
                }
            } else if exercise.isLinear {
                repsString = "\(exercise.repsPerSet)"
            } else if isAMRAP {
                if let result = amrapResult {
                    repsString = "\(result.reps)"
                } else {
                    repsString = "\(exercise.repOutTarget)+"
                }
            } else {
                repsString = "\(exercise.repsPerSet)"
            }
            
            return WorkoutSummary.ExerciseSummary(
                name: exercise.name,
                weight: amrapResult?.weight ?? exercise.weight,
                sets: workoutState.completedSets[exercise.id]?.count ?? 0,
                reps: repsString,
                isAMRAP: isAMRAP,
                estimatedOneRM: amrapResult?.e1rm,
                isAccessory: exercise.isAccessory
            )
        }
        
        let prs: [WorkoutSummary.PRSummary] = workoutState.prsAchieved.map { pr in
            WorkoutSummary.PRSummary(
                liftName: pr.liftName,
                weight: pr.weight,
                reps: pr.reps,
                newE1RM: pr.newE1RM,
                previousE1RM: pr.previousE1RM
            )
        }
        
        return WorkoutSummary(
            date: Date(),
            dayTitle: appState.dayTitle(day: day),
            week: week,
            day: day,
            programName: appState.programData?.displayName ?? appState.programData?.name,
            exercises: exercises,
            totalSets: workoutState.completedSetsCount,
            duration: workoutDuration,
            prs: prs,
            barWeight: appState.settings.barWeight,
            barWeights: summaryBarWeights(for: performed)
        )
    }

    /// What's already logged for the AMRAP set being entered. Only a redo has anything,
    /// and the sheet starts from it.
    var pendingAMRAPLog: (reps: Int?, note: String?) {
        guard let lift = workoutState.currentExercise?.lift else { return (nil, nil) }
        if let setIndex = pendingStructuredSetIndex {
            let log = appState.getStructuredLog(lift: lift, week: week, day: day)
            return (log?.amrapReps[setIndex], log?.note)
        }
        let log = appState.getLog(lift: lift, week: week, day: day)
        return (log?.repsLastSet, log?.note)
    }

    /// Get the target reps for the current AMRAP set (for the input sheet)
    var currentRepTarget: Int {
        guard let exercise = workoutState.currentExercise else { return 0 }
        
        // For nSuns, get the target from the current set
        if exercise.isStructured,
           let sets = exercise.structuredSetInfo,
           workoutState.currentSetNumber > 0 && workoutState.currentSetNumber <= sets.count {
            return sets[workoutState.currentSetNumber - 1].targetReps
        }
        
        // Standard volume
        return exercise.repOutTarget
    }
}
