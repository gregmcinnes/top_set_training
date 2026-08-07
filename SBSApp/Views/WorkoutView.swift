import SwiftUI
import AVFoundation
import ActivityKit

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Workout Exercise Model

struct WorkoutExercise: Identifiable {
    let id = UUID()
    let name: String
    let lift: String?
    var weight: Double
    let totalSets: Int
    let repsPerSet: Int
    let repOutTarget: Int
    let isRepOutSet: (Int) -> Bool  // Given set number (1-indexed), is it a rep-out?
    let isAccessory: Bool  // True if this is an accessory exercise
    let isStructured: Bool  // True if this is a structured exercise
    var structuredSetInfo: [StructuredSetInfo]?  // Set details for structured exercises (mutable so weight overrides can scale per-set weights)
    let isLinear: Bool  // True if this is a linear progression exercise
    let linearInfo: LinearExerciseInfo?  // Linear progression info
    let intensity: Double?  // Percentage of training max (0.0-1.0)
    let calculatedWeight: Double?  // Original calculated weight (before any override)
    var lastWasEasy: Bool? = nil  // For accessories: did the user mark the previous session as easy?
    var markedEasy: Bool = false  // For accessories: did the user mark this current session as easy?
    
    /// For volume exercises, the last set is the rep-out
    static func fromVolumeItem(name: String, lift: String, weight: Double, sets: Int, repsPerSet: Int, repOutTarget: Int, intensity: Double, calculatedWeight: Double? = nil) -> WorkoutExercise {
        WorkoutExercise(
            name: name,
            lift: lift,
            weight: weight,
            totalSets: sets,
            repsPerSet: repsPerSet,
            repOutTarget: repOutTarget,
            isRepOutSet: { setNumber in setNumber == sets },
            isAccessory: false,
            isStructured: false,
            structuredSetInfo: nil,
            isLinear: false,
            linearInfo: nil,
            intensity: intensity,
            calculatedWeight: calculatedWeight ?? weight
        )
    }
    
    /// For accessory exercises (no rep-out)
    static func fromAccessory(name: String, sets: Int, reps: Int, lastLogWeight: Double?, lastWasEasy: Bool? = nil) -> WorkoutExercise {
        var ex = WorkoutExercise(
            name: name,
            lift: nil,
            weight: lastLogWeight ?? 0,
            totalSets: sets,
            repsPerSet: reps,
            repOutTarget: 0,
            isRepOutSet: { _ in false },
            isAccessory: true,
            isStructured: false,
            structuredSetInfo: nil,
            isLinear: false,
            linearInfo: nil,
            intensity: nil,
            calculatedWeight: nil
        )
        ex.lastWasEasy = lastWasEasy
        return ex
    }
    
    /// For nSuns exercises with varying sets
    static func fromStructured(name: String, lift: String, sets: [StructuredSetInfo]) -> WorkoutExercise {
        // Find the heaviest weight as the display weight
        let heaviestWeight = sets.max(by: { $0.weight < $1.weight })?.weight ?? 0
        // Find the target reps for display (use the 1+ set if available)
        let primarySet = sets.first { $0.isAMRAP && $0.targetReps == 1 } ?? sets.first { $0.isAMRAP }
        let repOutTarget = primarySet?.targetReps ?? 1
        
        return WorkoutExercise(
            name: name,
            lift: lift,
            weight: heaviestWeight,
            totalSets: sets.count,
            repsPerSet: 0,  // Not used for structured
            repOutTarget: repOutTarget,
            isRepOutSet: { setNumber in
                // setNumber is 1-indexed, sets array is 0-indexed
                guard setNumber > 0 && setNumber <= sets.count else { return false }
                return sets[setNumber - 1].isAMRAP
            },
            isAccessory: false,
            isStructured: true,
            structuredSetInfo: sets,
            isLinear: false,
            linearInfo: nil,
            intensity: nil,  // Structured exercises have per-set intensity
            // Pre-override weight, so the override sheet still shows the prescribed load
            calculatedWeight: sets.max(by: { $0.calculatedWeight < $1.calculatedWeight })?.calculatedWeight ?? heaviestWeight
        )
    }
    
    /// For linear progression exercises (StrongLifts, Starting Strength style)
    static func fromLinear(name: String, info: LinearExerciseInfo) -> WorkoutExercise {
        WorkoutExercise(
            name: name,
            lift: info.lift,
            weight: info.weight,
            totalSets: info.sets,
            repsPerSet: info.reps,
            repOutTarget: info.reps,  // Target is to complete all reps
            isRepOutSet: { _ in false },  // No AMRAP sets in linear progression
            isAccessory: false,
            isStructured: false,
            structuredSetInfo: nil,
            isLinear: true,
            linearInfo: info,
            intensity: 1.0,  // Linear progression is always at 100% working weight
            calculatedWeight: info.weight
        )
    }
}

// MARK: - Superset Accessory Data

struct SupersetAccessoryData {
    let name: String
    let sets: Int
    let reps: Int
    let weight: Double?  // from lastLog if available
    var lastWasEasy: Bool? = nil
}

// MARK: - Workout PR Record

/// Record of a PR achieved during a workout
struct WorkoutPRRecord: Identifiable, Equatable {
    let id = UUID()
    let liftName: String
    let weight: Double
    let reps: Int
    let newE1RM: Double
    let previousE1RM: Double?
}

// MARK: - Workout State

@Observable
final class WorkoutState {
    var exercises: [WorkoutExercise] = []
    var currentExerciseIndex: Int = 0
    var currentSetNumber: Int = 1  // 1-indexed
    var completedSets: [UUID: Set<Int>] = [:]  // exercise.id -> set of completed set numbers
    var repOutLogs: [String: Int] = [:]  // lift name -> reps logged
    
    // Linear progression tracking
    var failedSets: [UUID: Set<Int>] = [:]  // exercise.id -> set of failed set numbers (for linear progression)
    var linearExerciseCompleted: [UUID: Bool] = [:]  // exercise.id -> was exercise fully completed (no failures)?
    
    // Accessories paired with exercises (by exercise index)
    var supersetAccessories: [Int: SupersetAccessoryData] = [:]
    
    // PRs achieved during this workout
    var prsAchieved: [WorkoutPRRecord] = []
    
    // AMRAP results for exercises (for E1RM calculation in share card)
    var amrapResults: [String: (weight: Double, reps: Int, e1rm: Double)] = [:]  // lift name -> result
    
    // Timer state
    var timerRemaining: Int = 0
    var timerDuration: Int = 120
    var timerIsRunning: Bool = false
    var timerIsPaused: Bool = false
    var showingTimer: Bool = false
    var timerEndDate: Date?  // When the timer should end (for resuming after navigation)
    var timerPausedRemaining: Int?  // Remaining seconds when paused (for accurate resume)
    
    /// Get the accessory to superset with the current exercise (if any)
    var currentSupersetAccessory: SupersetAccessoryData? {
        supersetAccessories[currentExerciseIndex]
    }
    
    var currentExercise: WorkoutExercise? {
        guard currentExerciseIndex < exercises.count else { return nil }
        return exercises[currentExerciseIndex]
    }
    
    var isCurrentSetRepOut: Bool {
        currentExercise?.isRepOutSet(currentSetNumber) ?? false
    }
    
    var isCurrentExerciseAccessory: Bool {
        currentExercise?.isAccessory ?? false
    }
    
    var isWorkoutComplete: Bool {
        guard let lastExercise = exercises.last else { return true }
        guard let completedForLast = completedSets[lastExercise.id] else { return false }
        return currentExerciseIndex >= exercises.count - 1 && 
               completedForLast.count >= lastExercise.totalSets
    }
    
    var currentSetCompletedCount: Int {
        guard let exercise = currentExercise else { return 0 }
        return completedSets[exercise.id]?.count ?? 0
    }
    
    /// Total number of sets completed across all exercises
    var completedSetsCount: Int {
        completedSets.values.reduce(0) { $0 + $1.count }
    }
    
    var progress: Double {
        let totalSets = exercises.reduce(0) { $0 + $1.totalSets }
        guard totalSets > 0 else { return 0 }
        let completedCount = completedSets.values.reduce(0) { $0 + $1.count }
        return Double(completedCount) / Double(totalSets)
    }
    
    func markSetComplete() {
        guard let exercise = currentExercise else { return }
        
        if completedSets[exercise.id] == nil {
            completedSets[exercise.id] = []
        }
        completedSets[exercise.id]?.insert(currentSetNumber)
        
        // Advance to next set or exercise
        if currentSetNumber < exercise.totalSets {
            currentSetNumber += 1
        } else if currentExerciseIndex < exercises.count - 1 {
            currentExerciseIndex += 1
            currentSetNumber = 1
        }
    }
    
    func isSetCompleted(_ setNumber: Int) -> Bool {
        guard let exercise = currentExercise else { return false }
        return completedSets[exercise.id]?.contains(setNumber) ?? false
    }
    
    func isSetFailed(_ setNumber: Int) -> Bool {
        guard let exercise = currentExercise else { return false }
        return failedSets[exercise.id]?.contains(setNumber) ?? false
    }
    
    /// Mark a set as failed (for linear progression)
    func markSetFailed() {
        guard let exercise = currentExercise else { return }
        
        if failedSets[exercise.id] == nil {
            failedSets[exercise.id] = []
        }
        failedSets[exercise.id]?.insert(currentSetNumber)
        
        // Also count as "completed" for progress purposes
        if completedSets[exercise.id] == nil {
            completedSets[exercise.id] = []
        }
        completedSets[exercise.id]?.insert(currentSetNumber)
        
        // Advance to next set or exercise
        if currentSetNumber < exercise.totalSets {
            currentSetNumber += 1
        } else if currentExerciseIndex < exercises.count - 1 {
            currentExerciseIndex += 1
            currentSetNumber = 1
        }
    }
    
    /// Check if a linear exercise had any failed sets
    func hasFailedSets(for exerciseId: UUID) -> Bool {
        !(failedSets[exerciseId]?.isEmpty ?? true)
    }
    
    /// Check if current linear exercise is fully completed with no failures
    var isCurrentLinearExerciseSuccessful: Bool {
        guard let exercise = currentExercise, exercise.isLinear else { return false }
        let completed = completedSets[exercise.id]?.count ?? 0
        let failed = failedSets[exercise.id]?.count ?? 0
        return completed >= exercise.totalSets && failed == 0
    }
    
    /// Jump to a specific exercise by index
    func jumpToExercise(_ index: Int) {
        guard index >= 0 && index < exercises.count else { return }
        
        // Stop any running timer
        timerIsRunning = false
        timerIsPaused = false
        showingTimer = false
        timerRemaining = 0
        RestTimerStatus.shared.timerCleared()

        currentExerciseIndex = index
        
        // Reset to first incomplete set for this exercise, or set 1 if none completed
        if let exercise = exercises[safe: index],
           let completedForExercise = completedSets[exercise.id] {
            // Find first incomplete set
            for setNum in 1...exercise.totalSets {
                if !completedForExercise.contains(setNum) {
                    currentSetNumber = setNum
                    return
                }
            }
            // All sets complete, go to set 1
            currentSetNumber = 1
        } else {
            currentSetNumber = 1
        }
    }
    
    /// Check how many sets are completed for a given exercise index
    func completedSetsForExercise(at index: Int) -> Int {
        guard let exercise = exercises[safe: index] else { return 0 }
        return completedSets[exercise.id]?.count ?? 0
    }
    
    func startTimer(duration: Int) {
        timerDuration = duration
        timerRemaining = duration
        timerIsRunning = true
        timerIsPaused = false
        showingTimer = true
        let endDate = Date().addingTimeInterval(TimeInterval(duration))
        timerEndDate = endDate
        timerPausedRemaining = nil
        RestTimerStatus.shared.timerStarted(endDate: endDate)
    }

    func pauseTimer() {
        timerIsPaused = true
        timerIsRunning = false
        timerPausedRemaining = timerRemaining
        timerEndDate = nil
        RestTimerStatus.shared.timerPaused(remaining: timerRemaining)
    }

    func resumeTimer() {
        timerIsPaused = false
        timerIsRunning = true
        // Restore end date based on remaining time
        if let pausedRemaining = timerPausedRemaining {
            let endDate = Date().addingTimeInterval(TimeInterval(pausedRemaining))
            timerEndDate = endDate
            RestTimerStatus.shared.timerStarted(endDate: endDate)
        }
        timerPausedRemaining = nil
    }

    func skipTimer() {
        timerIsRunning = false
        timerIsPaused = false
        showingTimer = false
        timerRemaining = 0
        timerEndDate = nil
        timerPausedRemaining = nil
        RestTimerStatus.shared.timerCleared()
    }

    /// Adjust the running rest timer by `delta` seconds, continuing from the elapsed time.
    /// Example: 60s timer with 12s elapsed (48s remaining) + 15s → 75s timer with 63s remaining.
    /// Returns the new effective `timerDuration` (clamped to `minimumDuration`).
    @discardableResult
    func adjustTimer(by delta: Int, minimumDuration: Int = 15) -> Int {
        let newDuration = max(minimumDuration, timerDuration + delta)
        let appliedDelta = newDuration - timerDuration
        timerDuration = newDuration

        if timerIsRunning, let endDate = timerEndDate {
            let shifted = endDate.addingTimeInterval(TimeInterval(appliedDelta))
            timerEndDate = shifted
            timerRemaining = max(0, Int(ceil(shifted.timeIntervalSinceNow)))
            RestTimerStatus.shared.timerStarted(endDate: shifted)
        } else if timerIsPaused, let paused = timerPausedRemaining {
            let newRemaining = max(0, paused + appliedDelta)
            timerPausedRemaining = newRemaining
            timerRemaining = newRemaining
            RestTimerStatus.shared.timerPaused(remaining: newRemaining)
        } else {
            // Timer hasn't started yet — only the planned duration changes.
            timerRemaining = max(0, timerRemaining + appliedDelta)
        }
        return newDuration
    }
    
    func timerTick() {
        if timerIsRunning, let endDate = timerEndDate {
            // Calculate remaining time from end date for accuracy
            let remaining = Int(ceil(endDate.timeIntervalSinceNow))
            timerRemaining = max(0, remaining)
        }
    }
    
    /// Check if timer should still be running and recalculate remaining time
    func recalculateTimerIfNeeded() {
        if timerIsRunning, let endDate = timerEndDate {
            let remaining = Int(ceil(endDate.timeIntervalSinceNow))
            if remaining > 0 {
                timerRemaining = remaining
            } else {
                // Timer has expired while view was away
                timerRemaining = 0
            }
        }
    }
}

// MARK: - Workout View

struct WorkoutView: View {
    @Bindable var appState: AppState
    let week: Int
    let day: Int
    
    @State private var workoutState = WorkoutState()
    @State private var showingRepInput = false
    @State private var repInputValue: Int?
    @State private var timer: Timer?
    @State private var showingExitConfirm = false
    @State private var showingSaveToFitnessPrompt = false
    @State private var prResult: AppState.LogRepsResult?
    @State private var showingPRCelebration = false
    @State private var pendingStructuredSetIndex: Int?  // For structured AMRAP logging
    @State private var showingExercisePicker = false
    @State private var showingLinearResult = false  // For linear progression success/fail dialog
    @State private var pendingLinearExercise: WorkoutExercise?  // Captured before advancing to next exercise
    @State private var showingPaywall = false  // For premium features
    @State private var showingShareSheet = false  // For workout summary share
    @State private var showingAccessoryWeightSheet = false  // For editing superset accessory weight
    @State private var showingStandaloneAccessoryWeight = false  // For editing the current standalone accessory's weight
    @State private var showingWeightOverride = false  // For overriding exercise weight mid-workout
    @State private var pendingRepEntry: (exerciseIndex: Int, setNumber: Int)?  // Identity of the set the rep-input sheet was opened for
    @State private var lastSyncedWatchSet: (exerciseIndex: Int, setNumber: Int)?  // Set identity last synced to the Watch
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared
    
    private let storeManager = StoreManager.shared
    
    /// Whether supersets are enabled (requires premium + user setting)
    private var supersetsEnabled: Bool {
        storeManager.canAccess(.supersets) && appState.settings.supersetAccessories
    }
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Progress header
                WorkoutProgressHeader(
                    progress: workoutState.progress,
                    exerciseName: workoutState.currentExercise?.name ?? "Workout",
                    setInfo: setInfoText,
                    isAccessory: workoutState.isCurrentExerciseAccessory,
                    heartRate: watchConnectivity.currentHeartRate
                )
                
                if workoutState.isWorkoutComplete {
                    WorkoutCompleteView(
                        workoutState: workoutState,
                        appState: appState,
                        week: week,
                        day: day,
                        onDone: { finishAndDismiss() },
                        onShare: { showingShareSheet = true }
                    )
                } else if workoutState.showingTimer {
                    // Timer view with next set preview
                    TimerView(
                        workoutState: workoutState,
                        useMetric: appState.settings.useMetric,
                        showSuperset: supersetsEnabled,
                        barWeight: appState.settings.barWeight,
                        showPlateCalculator: appState.shouldShowPlateCalculator,
                        onTimerEnd: { handleTimerEnd() },
                        onSkip: { handleTimerSkip() },
                        onUnlockTap: { showingPaywall = true },
                        onAccessoryWeightTap: { showingAccessoryWeightSheet = true },
                        onPause: {
                            NotificationManager.shared.cancelRestTimerNotification()
                            // Freeze the Watch countdown (endDate nil, isPaused true).
                            sendRestTimerStateToWatch()
                        },
                        onResume: {
                            // Pause + tab-switch invalidates the tick Timer, so
                            // restart it — otherwise the countdown stays frozen
                            // and never reaches handleTimerEnd().
                            startTimerTickLoop()
                            if appState.settings.pushNotificationsEnabled, let exercise = workoutState.currentExercise {
                                NotificationManager.shared.scheduleRestTimerNotification(
                                    duration: workoutState.timerRemaining,
                                    exerciseName: exercise.name,
                                    nextSetInfo: "Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
                                )
                            }
                            // Restart the Watch countdown from the fresh endDate.
                            sendRestTimerStateToWatch()
                        },
                        onAdjust: { delta in
                            handleTimerAdjust(by: delta)
                        }
                    )
                } else {
                    // Current set view
                    CurrentSetView(
                        workoutState: workoutState,
                        useMetric: appState.settings.useMetric,
                        barWeight: appState.settings.barWeight,
                        showPlateCalculator: appState.shouldShowPlateCalculator,
                        onComplete: handleSetComplete,
                        onUnlockTap: { showingPaywall = true },
                        onWeightTap: {
                            guard let exercise = workoutState.currentExercise else { return }
                            if exercise.isAccessory {
                                showingStandaloneAccessoryWeight = true
                            } else {
                                showingWeightOverride = true
                            }
                        },
                        onMarkEasy: toggleCurrentAccessoryEasy,
                        personalRecordE1RM: { appState.personalRecord(for: $0)?.estimatedOneRM }
                    )
                }
            }
            .sbsBackground()
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // Cap Dynamic Type so the largest accessibility sizes can't break the
        // fixed-height number pad / rest-timer layouts on this screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // If Apple Fitness is enabled and there's workout progress, offer to save
                    if storeManager.canAccess(.appleFitness) && appState.settings.healthKitEnabled && hasWorkoutProgress {
                        showingSaveToFitnessPrompt = true
                    } else {
                        showingExitConfirm = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .accessibilityLabel("Exit workout")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingExercisePicker = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .accessibilityLabel("Exercise list")
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(
                workoutState: workoutState,
                useMetric: appState.settings.useMetric,
                onSelect: { index in
                    // Jumping to another exercise abandons any running rest —
                    // cancel every surface (notification / Live Activity / Watch)
                    // so none orphans, not just the local Timer.
                    cancelRestSurfaces()
                    workoutState.jumpToExercise(index)
                    showingExercisePicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Exit Workout?", isPresented: $showingExitConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Exit", role: .destructive) {
                exitWorkoutWithoutSaving()
            }
        } message: {
            Text("Your progress for this session will be lost.")
        }
        .alert("Save to Apple Fitness?", isPresented: $showingSaveToFitnessPrompt) {
            Button("Don't Save", role: .destructive) {
                exitWorkoutWithoutSaving()
            }
            Button("Save Workout") {
                exitWorkoutAndSaveToFitness()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save this workout to Apple Fitness? You've completed \(workoutState.completedSetsCount) sets.")
        }
        .sheet(isPresented: $showingRepInput) {
            RepOutInputSheet(
                liftName: workoutState.currentExercise?.name ?? "",
                target: currentRepTarget,
                structuredContext: {
                    // Use structured progression context for Greyskull/GZCLP style programs
                    if let exercise = workoutState.currentExercise,
                       exercise.isStructured,
                       let lift = exercise.lift {
                        return StructuredProgressionContext(
                            liftName: lift,
                            useMetric: appState.settings.useMetric,
                            manualProgression: appState.programState?.manualProgression ?? false
                        )
                    }
                    return nil
                }(),
                prRepsNeeded: {
                    guard let exercise = workoutState.currentExercise else { return nil }
                    let weight: Double
                    if let setIndex = pendingStructuredSetIndex,
                       let sets = exercise.structuredSetInfo,
                       let setInfo = sets.first(where: { $0.setIndex == setIndex }) {
                        weight = setInfo.weight
                    } else {
                        weight = exercise.weight
                    }
                    let lift = exercise.lift ?? exercise.name
                    return E1RM.newPRRepThreshold(
                        weight: weight,
                        targetReps: currentRepTarget,
                        bestE1RM: appState.personalRecord(for: lift)?.estimatedOneRM
                    )
                }(),
                onSave: { reps, note in
                    // Identity guard: the sheet was opened for a specific set. If the
                    // workout state has moved on (re-entrant ✓ tap during the sheet's
                    // dismiss animation) or that set is already completed, ignore the
                    // tap — otherwise we'd log duplicate reps and complete the next
                    // exercise's set 1.
                    guard let pending = pendingRepEntry,
                          pending.exerciseIndex == workoutState.currentExerciseIndex,
                          pending.setNumber == workoutState.currentSetNumber,
                          !workoutState.isSetCompleted(pending.setNumber) else {
                        Logger.debug("Ignoring stale rep-input save (current: exercise \(workoutState.currentExerciseIndex), set \(workoutState.currentSetNumber))", category: .general)
                        return
                    }
                    pendingRepEntry = nil

                    if let lift = workoutState.currentExercise?.lift,
                       let exercise = workoutState.currentExercise {
                        // Check if this is a structured (nSuns/GZCLP) set
                        if let setIndex = pendingStructuredSetIndex {
                            // Log structured AMRAP - check for PR
                            let result = appState.logStructuredReps(lift: lift, week: week, day: day, setIndex: setIndex, reps: reps)

                            // Track AMRAP result for share card - only for 1+ progression sets (not back-off AMRAPs)
                            // This ensures we use the heavy 1+ set for e1RM, not the lighter final AMRAP
                            if exercise.isStructured, let sets = exercise.structuredSetInfo,
                               let setInfo = sets.first(where: { $0.setIndex == setIndex }),
                               setInfo.targetReps == 1 {  // Only track 1+ sets
                                let weight = setInfo.weight
                                let e1rm = weight * (1.0 + Double(reps) / 30.0)
                                workoutState.amrapResults[lift] = (weight, reps, e1rm)
                            }

                            pendingStructuredSetIndex = nil

                            if let result, result.isNewPR {
                                // Track PR for share card
                                let prRecord = WorkoutPRRecord(
                                    liftName: result.liftName,
                                    weight: result.weight,
                                    reps: result.reps,
                                    newE1RM: result.newE1RM,
                                    previousE1RM: result.previousE1RM
                                )
                                workoutState.prsAchieved.append(prRecord)

                                // Count this PR toward review-request eligibility
                                // (queued only; presented later once the workout
                                // is dismissed, never on the PR celebration).
                                ReviewRequestManager.shared.recordPRAchieved()

                                // Show PR celebration if enabled in settings
                                if appState.settings.showPRCelebrations {
                                    prResult = result
                                    showingRepInput = false

                                    // Complete the set and start timer (same as non-PR flow)
                                    completeSetAndStartTimer()

                                    // Small delay before showing celebration
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showingPRCelebration = true
                                    }
                                    return
                                }
                                // If celebrations are disabled, fall through to normal completion
                            }
                        } else {
                            // Standard volume log - check for PR
                            if let result = appState.logReps(lift: lift, week: week, day: day, reps: reps, note: note) {
                                workoutState.repOutLogs[lift] = reps
                                
                                // Track AMRAP result for share card
                                workoutState.amrapResults[lift] = (result.weight, result.reps, result.newE1RM)
                                
                                if result.isNewPR {
                                    // Track PR for share card
                                    let prRecord = WorkoutPRRecord(
                                        liftName: result.liftName,
                                        weight: result.weight,
                                        reps: result.reps,
                                        newE1RM: result.newE1RM,
                                        previousE1RM: result.previousE1RM
                                    )
                                    workoutState.prsAchieved.append(prRecord)

                                    // Count this PR toward review-request eligibility
                                    // (queued only; presented later once the workout
                                    // is dismissed, never on the PR celebration).
                                    ReviewRequestManager.shared.recordPRAchieved()

                                    // Show PR celebration if enabled in settings
                                    if appState.settings.showPRCelebrations {
                                        prResult = result
                                        showingRepInput = false
                                        
                                        // Complete the set and start timer (same as non-PR flow)
                                        completeSetAndStartTimer()
                                        
                                        // Small delay before showing celebration
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showingPRCelebration = true
                                        }
                                        return
                                    }
                                    // If celebrations are disabled, fall through to normal completion
                                }
                            }
                        }
                    }
                    completeSetAndStartTimer()
                    showingRepInput = false
                },
                onCancel: {
                    pendingStructuredSetIndex = nil
                    pendingRepEntry = nil
                    showingRepInput = false
                }
            )
            .presentationDetents([.height(420), .medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showingPRCelebration) {
            if let result = prResult {
                PRCelebrationView(
                    liftName: result.liftName,
                    newE1RM: result.newE1RM,
                    previousE1RM: result.previousE1RM,
                    weight: result.weight,
                    reps: result.reps,
                    useMetric: appState.settings.useMetric,
                    week: week,
                    day: day,
                    programName: appState.programData?.displayName ?? appState.programData?.name,
                    onDismiss: {
                        showingPRCelebration = false
                        prResult = nil
                        // Note: completeSetAndStartTimer() is now called before showing the celebration
                        // to match the non-PR flow and prevent skipping sets
                    }
                )
                // Make the cover itself transparent so the celebration's own
                // dim scrim composites over the live workout rather than an
                // opaque system background. (.background(Color.clear) does not
                // achieve this on a fullScreenCover.)
                .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showingLinearResult) {
            LinearResultSheet(
                exerciseName: pendingLinearExercise?.name ?? "",
                weight: pendingLinearExercise?.weight ?? 0,
                sets: pendingLinearExercise?.totalSets ?? 0,
                reps: pendingLinearExercise?.repsPerSet ?? 0,
                failedSets: pendingLinearExerciseFailedCount,
                increment: pendingLinearExercise?.linearInfo?.increment ?? 5,
                isDeloadPending: pendingLinearExercise?.linearInfo?.isDeloadPending ?? false,
                consecutiveFailures: pendingLinearExercise?.linearInfo?.consecutiveFailures ?? 0,
                useMetric: appState.settings.useMetric,
                onSuccess: {
                    handleLinearSuccess()
                    showingLinearResult = false
                    pendingLinearExercise = nil
                },
                onFailure: {
                    handleLinearFailure()
                    showingLinearResult = false
                    pendingLinearExercise = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(triggeredByFeature: .plateCalculator)
        }
        .sheet(isPresented: $showingShareSheet) {
            WorkoutShareSheet(
                summary: buildWorkoutSummary(),
                useMetric: appState.settings.useMetric,
                onDismiss: { showingShareSheet = false }
            )
        }
        .sheet(isPresented: $showingAccessoryWeightSheet) {
            if let accessory = workoutState.currentSupersetAccessory {
                AccessoryWeightSheet(
                    accessoryName: accessory.name,
                    currentWeight: accessory.weight,
                    defaultSets: accessory.sets,
                    defaultReps: accessory.reps,
                    useMetric: appState.settings.useMetric,
                    roundingIncrement: appState.settings.roundingIncrement,
                    onSave: { weight, sets, reps in
                        // Update the accessory weight in the workout state
                        updateAccessoryWeight(weight: weight, sets: sets, reps: reps)
                        showingAccessoryWeightSheet = false
                    },
                    onCancel: { showingAccessoryWeightSheet = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingStandaloneAccessoryWeight) {
            if let exercise = workoutState.currentExercise, exercise.isAccessory {
                AccessoryWeightSheet(
                    accessoryName: exercise.name,
                    currentWeight: exercise.weight > 0 ? exercise.weight : nil,
                    defaultSets: exercise.totalSets,
                    defaultReps: exercise.repsPerSet,
                    useMetric: appState.settings.useMetric,
                    roundingIncrement: appState.settings.roundingIncrement,
                    onSave: { weight, sets, reps in
                        updateStandaloneAccessoryWeight(weight: weight, sets: sets, reps: reps)
                        showingStandaloneAccessoryWeight = false
                    },
                    onCancel: { showingStandaloneAccessoryWeight = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingWeightOverride) {
            if let exercise = workoutState.currentExercise, let lift = exercise.lift {
                let currentOverride = appState.getWeightOverride(lift: lift, week: week, day: day)
                let baseWeight = exercise.calculatedWeight ?? exercise.weight
                WeightOverrideSheet(
                    liftName: exercise.name,
                    calculatedWeight: baseWeight,
                    currentOverride: currentOverride,
                    prescribedReps: prescribedRepsDescription(for: exercise),
                    useMetric: appState.settings.useMetric,
                    roundingIncrement: appState.settings.roundingIncrement,
                    onSave: { newWeight in
                        applyWeightOverride(newWeight: newWeight, lift: lift)
                        showingWeightOverride = false
                    },
                    onClear: {
                        clearWeightOverride(lift: lift)
                        showingWeightOverride = false
                    },
                    onCancel: { showingWeightOverride = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            RestTimerStatus.shared.isWorkoutScreenVisible = true
            setupWorkout()
            resumeTimerLoopIfNeeded()
            startHealthKitWorkout()
            setupWatchSync()

            // Keep screen awake during workout
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            RestTimerStatus.shared.isWorkoutScreenVisible = false

            // Only invalidate the Timer object, don't reset timer state
            // This allows the timer to continue when navigating to other tabs
            invalidateTimerOnly()

            // Re-enable screen sleep when leaving workout
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    private var setInfoText: String {
        guard let exercise = workoutState.currentExercise else { return "" }
        return "Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
    }
    
    /// Get the target reps for the current AMRAP set (for the input sheet)
    private var currentRepTarget: Int {
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
    
    private func setupWorkout() {
        // Only set up the workout once - don't reset if we already have exercises
        // This prevents losing completed sets when navigating away and back
        guard workoutState.exercises.isEmpty else { return }
        
        guard let plan = appState.dayPlan(week: week, day: day) else { return }
        
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
        
        if appState.settings.supersetAccessories {
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
    
    private func startHealthKitWorkout() {
        // Apple Fitness is a premium feature
        guard storeManager.canAccess(.appleFitness) else { return }
        guard appState.settings.healthKitEnabled else { return }
        
        let workoutName = "Week \(week), Day \(day) - \(appState.dayTitle(day: day))"
        Task {
            do {
                try await HealthKitManager.shared.startWorkout(name: workoutName)
            } catch {
                Logger.error("Failed to start HealthKit workout: \(error)", category: .healthKit)
            }
        }
    }
    
    // MARK: - Watch Sync
    
    /// Notify Watch to start workout session for heart rate collection
    private func setupWatchSync() {
        let isReachable = WatchConnectivityManager.shared.isWatchReachable
        Logger.debug("🔵 setupWatchSync: isReachable=\(isReachable)", category: .general)
        
        // Tell the Watch whether it may write its own HealthKit workout. Pass the
        // same HealthKit setting that gates the phone's HKWorkoutBuilder below so
        // the two stay in agreement about who owns the HealthKit workout.
        WatchConnectivityManager.shared.sendWorkoutStarted(healthKitEnabled: appState.settings.healthKitEnabled)
        Logger.debug("✅ Sent workoutStarted to Watch (healthKitEnabled: \(appState.settings.healthKitEnabled))", category: .general)
        
        // Set up callback for set completion from Watch
        WatchConnectivityManager.shared.onSetCompletedFromWatch = { reps, exerciseIndex, setNumber in
            handleSetCompleteFromWatch(reps: reps, exerciseIndex: exerciseIndex, setNumber: setNumber)
        }
        
        // Send initial workout state after a brief delay (to allow workout to start on Watch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.syncWorkoutStateToWatch()
        }
    }
    
    /// Notify Watch to end workout session
    private func syncWorkoutEndedToWatch() {
        WatchConnectivityManager.shared.onSetCompletedFromWatch = nil
        WatchConnectivityManager.shared.sendWorkoutEnded()
    }
    
    /// Handle set completion triggered from Watch
    /// - Parameters:
    ///   - reps: Rep count from Watch for AMRAP sets, nil for normal sets
    ///   - exerciseIndex: Exercise index the Watch was showing (nil on older Watch builds)
    ///   - setNumber: Set number the Watch was showing (nil on older Watch builds)
    private func handleSetCompleteFromWatch(reps: Int?, exerciseIndex: Int?, setNumber: Int?) {
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
        
        // Check if current set is a structured AMRAP (nSuns, etc.)
        let structuredSetInfo: StructuredSetInfo? = {
            guard exercise.isStructured,
                  let sets = exercise.structuredSetInfo,
                  workoutState.currentSetNumber > 0 && workoutState.currentSetNumber <= sets.count else {
                return nil
            }
            return sets[workoutState.currentSetNumber - 1]
        }()
        let isStructuredAMRAP = structuredSetInfo?.isAMRAP ?? false
        
        // For AMRAP/rep-out sets, log the reps from Watch (or target reps as fallback)
        if workoutState.isCurrentSetRepOut {
            // Volume program rep-out set
            let repsToLog = reps ?? exercise.repOutTarget
            if let result = appState.logReps(lift: exercise.lift ?? exercise.name, week: week, day: day, reps: repsToLog) {
                workoutState.repOutLogs[exercise.lift ?? exercise.name] = repsToLog
                workoutState.amrapResults[exercise.lift ?? exercise.name] = (result.weight, result.reps, result.newE1RM)
            }
            Logger.debug("⌚️ Logged AMRAP reps: \(repsToLog)", category: .general)
        } else if isStructuredAMRAP {
            // Structured program AMRAP set (nSuns, etc.)
            if let reps = reps,
               let setInfo = structuredSetInfo,
               let lift = exercise.lift {
                if let result = appState.logStructuredReps(lift: lift, week: week, day: day, setIndex: setInfo.setIndex, reps: reps),
                   setInfo.targetReps == 1 {  // Only track 1+ progression sets for share card
                    workoutState.amrapResults[lift] = (result.weight, result.reps, result.newE1RM)
                }
                Logger.debug("⌚️ Logged structured AMRAP reps: \(reps) for set \(setInfo.setIndex)", category: .general)
            }
        }
        
        // Complete the set and start rest timer
        completeSetAndStartTimer()
        
        // Sync updated state back to Watch
        syncWorkoutStateToWatch()
    }
    
    /// Send current workout state to Watch
    private func syncWorkoutStateToWatch() {
        guard let exercise = workoutState.currentExercise else { return }
        
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
    private var hasWorkoutProgress: Bool {
        workoutState.completedSetsCount > 0
    }
    
    /// Exit workout without saving to Apple Fitness
    private func exitWorkoutWithoutSaving() {
        stopTimer()

        // The workout state dies with this view — clear the app-wide timer
        // mirror and any pending rest-complete notification so neither
        // outlives the workout.
        RestTimerStatus.shared.timerCleared()
        NotificationManager.shared.cancelRestTimerNotification()

        // End Watch workout session
        syncWorkoutEndedToWatch()

        // End Live Activity
        LiveActivityManager.shared.endTimerSync()
        
        // Discard the HealthKit workout (don't save)
        if storeManager.canAccess(.appleFitness) && appState.settings.healthKitEnabled {
            HealthKitManager.shared.discardWorkout()
        }
        
        dismiss()
    }
    
    /// Exit workout and save to Apple Fitness
    private func exitWorkoutAndSaveToFitness() {
        stopTimer()
        RestTimerStatus.shared.timerCleared()
        NotificationManager.shared.cancelRestTimerNotification()

        // Capture whether the Watch owns the HealthKit workout BEFORE
        // syncWorkoutEndedToWatch() clears the flag (sendWorkoutEnded resets it).
        let watchOwnsHealthKitWorkout = WatchConnectivityManager.shared.isWatchWorkoutSessionActive

        // End Watch workout session
        syncWorkoutEndedToWatch()

        // End Live Activity
        LiveActivityManager.shared.endTimerSync()

        // Save to Apple Fitness with current progress
        if storeManager.canAccess(.appleFitness) && appState.settings.healthKitEnabled {
            if watchOwnsHealthKitWorkout {
                // The Watch is running its own HealthKit-saving session — discard
                // the phone's builder so we don't write a duplicate workout.
                HealthKitManager.shared.discardWorkout()
            } else {
                let stats = calculateWorkoutStats()
                Task {
                    do {
                        try await HealthKitManager.shared.endWorkout(
                            totalVolume: stats.volume,
                            setCount: stats.sets,
                            repCount: stats.reps
                        )
                        Logger.debug("✅ Saved partial workout to Apple Fitness", category: .healthKit)
                    } catch {
                        Logger.error("Failed to save workout to Apple Fitness: \(error)", category: .healthKit)
                    }
                }
            }
        }

        dismiss()
    }
    
    private func finishAndDismiss() {
        stopTimer()
        RestTimerStatus.shared.timerCleared()
        NotificationManager.shared.cancelRestTimerNotification()

        // The easy nudge has now been seen for any accessory trained this
        // session — clear stale flags so it only shows once.
        consumeAccessoryEasyFlags()

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
        if storeManager.canAccess(.appleFitness) && appState.settings.healthKitEnabled {
            if watchOwnsHealthKitWorkout {
                // The Watch is running its own HealthKit-saving session (with live
                // heart-rate data) — discard the phone's builder so we don't write
                // a duplicate HealthKit workout.
                HealthKitManager.shared.discardWorkout()
            } else {
                // Calculate workout stats for HealthKit
                let stats = calculateWorkoutStats()
                Task {
                    do {
                        try await HealthKitManager.shared.endWorkout(
                            totalVolume: stats.volume,
                            setCount: stats.sets,
                            repCount: stats.reps
                        )
                    } catch {
                        Logger.error("Failed to end HealthKit workout: \(error)", category: .healthKit)
                    }
                }
            }
        }

        // Record workout completion for review request tracking. This may
        // queue a review request at milestone workouts (3rd, 10th, 25th, etc.),
        // but presentation is deferred so the rating prompt never lands on the
        // workout-complete celebration — it's flushed below once this view has
        // dismissed.
        ReviewRequestManager.shared.recordWorkoutCompleted()

        // Check if completing this workout completes the week
        // We need to check after the workout is logged, so do it on the next run loop
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

        dismiss()
    }
    
    /// Calculate total volume, sets, and reps from the workout
    private func calculateWorkoutStats() -> (volume: Double, sets: Int, reps: Int) {
        var totalVolume: Double = 0
        var totalSets = 0
        var totalReps = 0
        
        for exercise in workoutState.exercises {
            guard let completedSetNumbers = workoutState.completedSets[exercise.id] else { continue }
            let setsCompleted = completedSetNumbers.count
            totalSets += setsCompleted
            
            if exercise.isStructured, let setInfos = exercise.structuredSetInfo {
                // Structured exercises have different weights per set
                for setNumber in completedSetNumbers {
                    let setIndex = setNumber - 1  // Convert 1-indexed to 0-indexed
                    if setIndex >= 0 && setIndex < setInfos.count {
                        let setInfo = setInfos[setIndex]
                        let reps = setInfo.loggedReps ?? setInfo.targetReps
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
                    // No rep-out logged, use standard reps
                    totalReps += setsCompleted * repsPerCompletedSet
                    totalVolume += exercise.weight * Double(setsCompleted * repsPerCompletedSet)
                }
            }
        }
        
        return (totalVolume, totalSets, totalReps)
    }
    
    private func handleSetComplete() {
        guard let exercise = workoutState.currentExercise else { return }

        // Tactile confirmation for the app's most-pressed button.
        Haptics.medium()

        // Check if this is a linear progression exercise - on last set, show result dialog
        if exercise.isLinear && workoutState.currentSetNumber == exercise.totalSets {
            // Capture the exercise BEFORE advancing to the next one
            pendingLinearExercise = exercise
            
            // On final set - show linear result dialog after marking set complete
            completeSetAndStartTimer()
            
            // Small delay then show the result dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingLinearResult = true
            }
            return
        }
        
        // Guard: Don't show rep input if current set is already completed
        // This prevents an endless loop if the user taps Done on an already-logged set
        if workoutState.isSetCompleted(workoutState.currentSetNumber) {
            Logger.debug("Set \(workoutState.currentSetNumber) already completed, advancing without rep input", category: .general)
            // Just advance to next set/exercise
            completeSetAndStartTimer()
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
            
            // If this is the last set of a structured exercise with no remaining AMRAPs,
            // mark the exercise as completed so the day shows as complete
            // (This handles BBB sets and deload weeks that have no AMRAP sets)
            if workoutState.currentSetNumber == exercise.totalSets,
               let lift = exercise.lift,
               !sets.contains(where: { $0.isAMRAP }) {
                appState.markStructuredCompleted(lift: lift, week: week, day: day)
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
    
    private func completeSetAndStartTimer() {
        workoutState.markSetComplete()

        // Don't start timer if workout is complete
        guard !workoutState.isWorkoutComplete else { return }

        // Start rest timer — the surfaces (Live Activity / notification /
        // Watch) are created exactly once here, when the rest actually
        // begins; the tick loop can be restarted freely on reappear.
        workoutState.startTimer(duration: appState.settings.restTimerDuration)
        startRestSurfaces()
        startTimerTickLoop()
    }

    /// Bump the running rest timer by `delta` seconds for this session only.
    /// Deliberately does NOT write `appState.settings.restTimerDuration` — a
    /// ±15s tap adjusts the running timer, not the user's saved default.
    private func handleTimerAdjust(by delta: Int) {
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
    private func startRestSurfaces() {
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

        // Schedule push notification for background alert
        if appState.settings.pushNotificationsEnabled, let exercise = workoutState.currentExercise {
            NotificationManager.shared.scheduleRestTimerNotification(
                duration: workoutState.timerDuration,
                exerciseName: exercise.name,
                nextSetInfo: "Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
            )
        }

        // Send initial timer state to Watch (workout context + set-completion
        // identity), then the authoritative endDate-based rest-timer timeline.
        syncWorkoutStateToWatch()
        sendRestTimerStateToWatch()
    }

    /// Push the current rest-timer timeline to the Watch as a single
    /// endDate-based message. Call once when the rest starts and again ONLY on a
    /// timeline change (pause / resume / ±15s adjust). It reads the live
    /// `workoutState`, so it must run AFTER the state mutation: a paused timer
    /// has `timerEndDate == nil` and `timerIsPaused == true`, while running/
    /// resumed/adjusted timers carry a fresh `timerEndDate`. The Watch renders
    /// the countdown locally from the endDate and schedules its own completion
    /// haptic, so no per-second traffic is needed.
    private func sendRestTimerStateToWatch() {
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

    /// (Re)start the 1s in-app tick loop that drives the countdown UI and the
    /// per-second Live Activity / Watch updates. Safe to call on reappear or
    /// on resume — it creates no surface and resets nothing; it only reads the
    /// existing endDate-driven timer state.
    private func startTimerTickLoop() {
        stopTimer()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak workoutState] _ in
            Task { @MainActor in
                guard let workoutState = workoutState else { return }
                workoutState.timerTick()
                
                // Update Live Activity with current time (Pro only)
                if StoreManager.shared.canAccess(.liveActivity) {
                    LiveActivityManager.shared.updateTimer(
                        secondsRemaining: workoutState.timerRemaining,
                        isPaused: workoutState.timerIsPaused
                    )
                }
                
                // The Watch renders the countdown locally from the endDate sent
                // once via sendRestTimerState(...), so no per-second Watch traffic
                // is sent here — only pause/resume/adjust push a new timeline.

                // Note: Timer end is handled by the View through handleTimerEnd()
                // which is called when timerRemaining <= 0 is detected in the View
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        // Note: Don't end Live Activity here - it's handled in handleTimerEnd()
    }
    
    /// Invalidates the Timer object without resetting timer state
    /// Used when view disappears (navigating to other tabs)
    private func invalidateTimerOnly() {
        timer?.invalidate()
        timer = nil
        // Don't end Live Activity or reset timer state - timer is still logically running
    }

    /// Fully tear down the rest timer and every surface it drives: the in-app
    /// tick loop, the timer state + RestTimerStatus mirror, the pending
    /// rest-complete notification, the Live Activity, and the Watch timer. Any
    /// path that abandons a running rest without ending the workout (jumping to
    /// or picking another exercise) must route through here so no surface
    /// outlives the rest it belonged to.
    private func cancelRestSurfaces() {
        stopTimer()
        workoutState.skipTimer()  // clears timer state + RestTimerStatus mirror
        NotificationManager.shared.cancelRestTimerNotification()
        LiveActivityManager.shared.endTimerSync()
        WatchConnectivityManager.shared.sendRestTimerEnded()
    }
    
    /// Restarts the timer loop if a timer is still running after view reappears
    private func resumeTimerLoopIfNeeded() {
        // Recalculate remaining time from end date
        workoutState.recalculateTimerIfNeeded()
        
        // If timer is running and has time left, restart only the tick loop.
        // The surfaces (Live Activity / notification / Watch) are endDate-driven
        // and still valid — recreating them here would reset them to full
        // duration.
        if workoutState.timerIsRunning && workoutState.timerRemaining > 0 {
            startTimerTickLoop()
        } else if workoutState.timerIsRunning && workoutState.timerRemaining <= 0 {
            // Timer expired while the view was away. Only play the end fanfare
            // if it *just* expired (~2s); a stale expiry already surfaced via
            // the foreground notification banner, so replaying haptics/chime
            // minutes late would be jarring.
            let justExpired = (workoutState.timerEndDate?.timeIntervalSinceNow ?? -100) > -2
            handleTimerEnd(playFeedback: justExpired)
        }
    }

    private func handleTimerEnd(playFeedback: Bool = true) {
        workoutState.skipTimer()
        stopTimer()
        
        // End Live Activity
        LiveActivityManager.shared.endTimerSync()
        
        // Cancel push notification (app is in foreground, no need for notification)
        NotificationManager.shared.cancelRestTimerNotification()
        
        // Notify Watch that timer ended (plays haptic on Watch)
        WatchConnectivityManager.shared.sendRestTimerEnded()
        
        // Send updated workout state after a small delay to ensure timer state is cleared
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.syncWorkoutStateToWatch()
        }

        // Play haptics and chime — suppressed for a stale expiry detected on
        // reappear (see resumeTimerLoopIfNeeded).
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
    private func handleTimerSkip() {
        Haptics.light()
        workoutState.skipTimer()
        stopTimer()
        LiveActivityManager.shared.endTimerSync()
        NotificationManager.shared.cancelRestTimerNotification()
        WatchConnectivityManager.shared.sendRestTimerEnded()

        // Send updated workout state after a small delay to ensure timer state is cleared
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.syncWorkoutStateToWatch()
        }
    }

    private func playTimerEndFeedback() {
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
        
        // Only play sound if user has sound notifications enabled
        // Using AudioServicesPlayAlertSound to respect silent mode (vibrates only when silenced)
        if appState.settings.playSoundNotifications {
            // 1322 = anticipate, 1323 = bloom, 1324 = calypso, 1325 = choo choo
            AudioServicesPlayAlertSound(1322)  // "Anticipate" - respects silent switch
        }
    }
    
    // MARK: - Linear Progression Helpers
    
    /// Get the count of failed sets for the pending linear exercise
    private var pendingLinearExerciseFailedCount: Int {
        guard let exercise = pendingLinearExercise else { return 0 }
        return workoutState.failedSets[exercise.id]?.count ?? 0
    }
    
    /// Log linear progression as success
    private func handleLinearSuccess() {
        guard let exercise = pendingLinearExercise,
              let lift = exercise.lift else { return }
        
        if let result = appState.logLinearSuccess(
            lift: lift,
            week: week,
            day: day,
            weight: exercise.weight,
            reps: exercise.repsPerSet,
            sets: exercise.totalSets
        ) {
            // Check for PR
            if result.isNewPR {
                // Track PR for share card
                let prRecord = WorkoutPRRecord(
                    liftName: result.liftName,
                    weight: result.weight,
                    reps: result.reps,
                    newE1RM: result.newE1RM,
                    previousE1RM: result.previousE1RM
                )
                workoutState.prsAchieved.append(prRecord)

                // Count this PR toward review-request eligibility (queued only;
                // presented later once the workout is dismissed).
                ReviewRequestManager.shared.recordPRAchieved()

                // Show PR celebration if enabled in settings
                if appState.settings.showPRCelebrations {
                    prResult = result

                    // Small delay before showing celebration
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingPRCelebration = true
                    }
                }
            }
        }
    }
    
    /// Log linear progression as failure
    private func handleLinearFailure() {
        guard let exercise = pendingLinearExercise,
              let lift = exercise.lift else { return }
        
        appState.logLinearFailure(
            lift: lift,
            week: week,
            day: day,
            weight: exercise.weight,
            reps: exercise.repsPerSet,
            sets: exercise.totalSets
        )
    }
    
    /// Update accessory weight from the sheet
    private func updateAccessoryWeight(weight: Double, sets: Int, reps: Int) {
        guard let accessory = workoutState.currentSupersetAccessory else { return }

        // Update the accessory in the workout state (for current session display)
        let updatedAccessory = SupersetAccessoryData(
            name: accessory.name,
            sets: sets,
            reps: reps,
            weight: weight
        )
        workoutState.supersetAccessories[workoutState.currentExerciseIndex] = updatedAccessory

        // Persist to appState so it shows in future workouts
        appState.logAccessory(name: accessory.name, weight: weight, sets: sets, reps: reps)
    }

    /// Toggle the "that was easy" flag on the current standalone accessory and
    /// persist it to the accessory log so the nudge shows up next session.
    private func toggleCurrentAccessoryEasy() {
        let idx = workoutState.currentExerciseIndex
        guard idx < workoutState.exercises.count else { return }
        var exercise = workoutState.exercises[idx]
        guard exercise.isAccessory else { return }
        exercise.markedEasy.toggle()
        workoutState.exercises[idx] = exercise

        if appState.getAccessoryLog(name: exercise.name) != nil {
            // Flip just the flag — logAccessory would clobber the note and
            // append a spurious accessoryHistory record on every toggle.
            appState.setAccessoryWasEasy(name: exercise.name, wasEasy: exercise.markedEasy ? true : nil)
        } else {
            appState.logAccessory(
                name: exercise.name,
                weight: exercise.weight,
                sets: exercise.totalSets,
                reps: exercise.repsPerSet,
                wasEasy: exercise.markedEasy ? true : nil
            )
        }
    }

    /// The "last time was easy" nudge is one-shot: once the user has trained
    /// the accessory again, clear the stored flag unless they re-marked it
    /// easy this session. Called when the workout is finished.
    private func consumeAccessoryEasyFlags() {
        for exercise in workoutState.exercises where exercise.isAccessory {
            let performed = !(workoutState.completedSets[exercise.id]?.isEmpty ?? true)
            if performed && !exercise.markedEasy {
                appState.setAccessoryWasEasy(name: exercise.name, wasEasy: nil)
            }
        }
        // Superset accessories ride along with their paired main lift and have
        // no re-mark control, so performing the pair consumes the flag.
        for (index, accessory) in workoutState.supersetAccessories {
            guard index < workoutState.exercises.count else { continue }
            let mainLift = workoutState.exercises[index]
            if !(workoutState.completedSets[mainLift.id]?.isEmpty ?? true) {
                appState.setAccessoryWasEasy(name: accessory.name, wasEasy: nil)
            }
        }
    }

    /// Update the weight of the current standalone accessory exercise (not a superset).
    private func updateStandaloneAccessoryWeight(weight: Double, sets: Int, reps: Int) {
        let idx = workoutState.currentExerciseIndex
        guard idx < workoutState.exercises.count else { return }
        var exercise = workoutState.exercises[idx]
        guard exercise.isAccessory else { return }
        exercise.weight = weight
        workoutState.exercises[idx] = exercise

        // Persist as the new last-log so it pre-fills next time. Keep the easy
        // flag if the user marked this session easy before adjusting weight.
        appState.logAccessory(
            name: exercise.name,
            weight: weight,
            sets: sets,
            reps: reps,
            wasEasy: exercise.markedEasy ? true : nil
        )
    }
    
    /// Build a human-readable prescribed-reps line for the weight override sheet
    /// (e.g. "5 × 5+", "3 × 5", "3+ AMRAP at 95% TM").
    private func prescribedRepsDescription(for exercise: WorkoutExercise) -> String? {
        if exercise.isStructured, let sets = exercise.structuredSetInfo {
            // Show the topmost AMRAP set for context (the "primary" set in nSuns)
            let amrapSets = sets.filter { $0.isAMRAP }
            if let primary = amrapSets.first(where: { $0.targetReps == 1 }) ?? amrapSets.first {
                return "\(sets.count) sets · \(primary.targetReps)+ AMRAP @ \(Int(primary.intensity * 100))% TM"
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
    private func applyWeightOverride(newWeight: Double, lift: String) {
        // Persist the override
        appState.setWeightOverride(lift: lift, week: week, day: day, weight: newWeight)
        // Update the live workout state so the display changes immediately
        let idx = workoutState.currentExerciseIndex
        guard idx < workoutState.exercises.count else { return }
        var exercise = workoutState.exercises[idx]
        let oldWeight = exercise.weight
        exercise.weight = newWeight

        // For structured exercises, the per-set weight is rendered from structuredSetInfo
        // (not from exercise.weight), so scale every set proportionally.
        if exercise.isStructured, let sets = exercise.structuredSetInfo, oldWeight > 0 {
            let ratio = newWeight / oldWeight
            exercise.structuredSetInfo = sets.map { set in
                StructuredSetInfo(
                    setIndex: set.setIndex,
                    intensity: set.intensity,
                    targetReps: set.targetReps,
                    isAMRAP: set.isAMRAP,
                    weight: (set.weight * ratio * 100).rounded() / 100,
                    loggedReps: set.loggedReps,
                    calculatedWeight: set.calculatedWeight
                )
            }
        }
        workoutState.exercises[idx] = exercise
    }

    /// Clear a weight override and revert to the calculated weight
    private func clearWeightOverride(lift: String) {
        appState.clearWeightOverride(lift: lift, week: week, day: day)
        let idx = workoutState.currentExerciseIndex
        guard idx < workoutState.exercises.count else { return }
        var exercise = workoutState.exercises[idx]

        if exercise.isStructured {
            // Re-fetch the per-set weights from the day plan now that the override is
            // cleared, so they revert to the calculated TM-based weights.
            if let plan = appState.dayPlan(week: week, day: day) {
                for item in plan {
                    if case let .structured(_, planLift, _, setInfos, _) = item, planLift == lift {
                        exercise.structuredSetInfo = setInfos
                        if let heaviest = setInfos.max(by: { $0.weight < $1.weight }) {
                            exercise.weight = heaviest.weight
                        }
                        break
                    }
                }
            }
        } else if let calcWeight = exercise.calculatedWeight {
            exercise.weight = calcWeight
        }
        workoutState.exercises[idx] = exercise
    }

    /// Build workout summary for sharing
    private func buildWorkoutSummary() -> WorkoutSummary {
        let exercises: [WorkoutSummary.ExerciseSummary] = workoutState.exercises.map { exercise in
            let amrapResult = workoutState.amrapResults[exercise.lift ?? ""]
            let isAMRAP = exercise.isRepOutSet(exercise.totalSets) || (exercise.structuredSetInfo?.contains { $0.isAMRAP } == true)
            
            // Determine reps string
            let repsString: String
            if exercise.isStructured, let sets = exercise.structuredSetInfo {
                // For structured (nSuns), show varied reps
                let amrapSets = sets.filter { $0.isAMRAP }
                if let primary = amrapSets.first {
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
                sets: exercise.totalSets,
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
        
        let totalSets = workoutState.exercises.reduce(0) { $0 + $1.totalSets }
        
        return WorkoutSummary(
            date: Date(),
            dayTitle: appState.dayTitle(day: day),
            week: week,
            day: day,
            programName: appState.programData?.displayName ?? appState.programData?.name,
            exercises: exercises,
            totalSets: totalSets,
            duration: nil,
            prs: prs
        )
    }
}

// MARK: - Workout Progress Header

struct WorkoutProgressHeader: View {
    let progress: Double
    let exerciseName: String
    let setInfo: String
    var isAccessory: Bool = false
    var heartRate: Double? = nil
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(SBSColors.surfaceFallback)
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: isAccessory 
                                    ? [SBSColors.accentSecondaryFallback, SBSColors.success]
                                    : [SBSColors.accentFallback, SBSColors.success],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 4)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        if isAccessory {
                            Image(systemName: "dumbbell.fill")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.accentSecondaryFallback)
                        }
                        
                        Text(exerciseName)
                            .font(SBSFonts.title3())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .lineLimit(2)
                    }
                    
                    Text(setInfo)
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
                // Heart rate from Apple Watch (if available)
                if let hr = heartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(SBSFonts.caption())
                            .foregroundStyle(.red)
                        Text("\(Int(hr))")
                            .font(SBSFonts.captionBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SBSColors.surfaceFallback.opacity(0.8))
                    .clipShape(Capsule())
                }
                
                Text("\(Int(progress * 100))%")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(isAccessory ? SBSColors.accentSecondaryFallback : SBSColors.accentFallback)
            }
            .padding(.leading, 40) // Account for navigation bar X button
            .padding(.trailing)
            .padding(.bottom, SBSLayout.paddingSmall)
        }
        .background(SBSColors.surfaceFallback)
    }
}

// MARK: - Current Set View

struct CurrentSetView: View {
    let workoutState: WorkoutState
    let useMetric: Bool
    var barWeight: Double = 45
    var showPlateCalculator: Bool = true
    let onComplete: () -> Void
    var onUnlockTap: (() -> Void)?
    var onWeightTap: (() -> Void)?
    var onMarkEasy: (() -> Void)?
    var personalRecordE1RM: (String) -> Double? = { _ in nil }

    /// Get the current set info for nSuns exercises
    private var currentStructuredSet: StructuredSetInfo? {
        guard let exercise = workoutState.currentExercise,
              exercise.isStructured,
              let sets = exercise.structuredSetInfo,
              workoutState.currentSetNumber > 0 && workoutState.currentSetNumber <= sets.count else {
            return nil
        }
        return sets[workoutState.currentSetNumber - 1]
    }
    
    /// Weight to display for current set
    private var currentWeight: Double {
        if let structuredSet = currentStructuredSet {
            return structuredSet.weight
        }
        return workoutState.currentExercise?.weight ?? 0
    }
    
    /// Reps to display for current set
    private var currentReps: Int {
        if let structuredSet = currentStructuredSet {
            return structuredSet.targetReps
        }
        return workoutState.currentExercise?.repsPerSet ?? 0
    }
    
    /// Is current set an AMRAP?
    private var isCurrentAMRAP: Bool {
        if let structuredSet = currentStructuredSet {
            return structuredSet.isAMRAP
        }
        return workoutState.isCurrentSetRepOut
    }
    
    /// Reps that would set a new E1RM PR on the current AMRAP set, if within
    /// reach (5 reps past the AMRAP target). nil = no hint.
    private var prHintReps: Int? {
        guard isCurrentAMRAP, let exercise = workoutState.currentExercise else { return nil }
        let lift = exercise.lift ?? exercise.name
        // Volume rep-out sets target repOutTarget, not repsPerSet
        let target = currentStructuredSet != nil ? currentReps : exercise.repOutTarget
        return E1RM.newPRRepThreshold(
            weight: currentWeight,
            targetReps: target,
            bestE1RM: personalRecordE1RM(lift)
        )
    }

    /// Intensity percentage for the current set/exercise
    private var intensityText: String? {
        // For structured exercises, use the per-set intensity
        if let structuredSet = currentStructuredSet {
            return "\(Int(structuredSet.intensity * 100))% TM"
        }
        // For volume and linear exercises, use the exercise-level intensity
        if let exercise = workoutState.currentExercise,
           let intensity = exercise.intensity,
           intensity > 0 {
            return "\(Int(round(intensity * 100)))% TM"
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingLarge) {
            Spacer()
            
            if let exercise = workoutState.currentExercise {
                // Set indicators
                if exercise.isStructured, let sets = exercise.structuredSetInfo {
                    StructuredSetIndicatorStrip(
                        sets: sets,
                        currentSet: workoutState.currentSetNumber,
                        completedSets: workoutState.completedSets[exercise.id] ?? [],
                        useMetric: useMetric
                    )
                } else {
                    SetIndicatorStrip(
                        totalSets: exercise.totalSets,
                        currentSet: workoutState.currentSetNumber,
                        completedSets: workoutState.completedSets[exercise.id] ?? [],
                        repsPerSet: exercise.repsPerSet,
                        repOutTarget: exercise.repOutTarget,
                        isRepOutSet: exercise.isRepOutSet,
                        isAccessory: exercise.isAccessory
                    )
                }
                
                if exercise.isAccessory {
                    // Accessory display
                    VStack(spacing: SBSLayout.paddingMedium) {
                        // Accessory badge
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "dumbbell.fill")
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.accentSecondaryFallback)

                            Text("ACCESSORY")
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.accentSecondaryFallback)
                        }
                        .padding(.horizontal, SBSLayout.paddingMedium)
                        .padding(.vertical, SBSLayout.paddingSmall)
                        .background(
                            Capsule()
                                .fill(SBSColors.accentSecondaryFallback.opacity(0.15))
                        )

                        // Weight (tappable to edit; shown even if 0 for bodyweight)
                        Button {
                            onWeightTap?()
                        } label: {
                            HStack(spacing: 6) {
                                Text(exercise.weight.formattedWeight(useMetric: useMetric))
                                    .font(SBSFonts.display())
                                    .foregroundStyle(SBSColors.accentSecondaryFallback)

                                Image(systemName: "pencil.circle")
                                    .font(SBSFonts.title3())
                                    .foregroundStyle(SBSColors.textTertiaryFallback)
                            }
                        }

                        // Reps
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Text("\(exercise.repsPerSet)")
                                .font(SBSFonts.title())
                                .foregroundStyle(SBSColors.textPrimaryFallback)

                            Text("reps")
                                .font(SBSFonts.title2())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }

                        if exercise.lastWasEasy == true {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.thumbsup.fill")
                                    .font(SBSFonts.caption())
                                Text("Last time was easy, go heavier")
                                    .font(SBSFonts.caption())
                            }
                            .foregroundStyle(SBSColors.success)
                            .padding(.horizontal, SBSLayout.paddingMedium)
                            .padding(.vertical, SBSLayout.paddingSmall)
                            .background(
                                Capsule()
                                    .fill(SBSColors.success.opacity(0.15))
                            )
                        }

                        if workoutState.currentSetNumber == exercise.totalSets {
                            Button(action: { onMarkEasy?() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: exercise.markedEasy ? "hand.thumbsup.fill" : "hand.thumbsup")
                                        .font(SBSFonts.caption())
                                    Text(exercise.markedEasy ? "Marked easy" : "That was easy?")
                                        .font(SBSFonts.caption())
                                }
                                .foregroundStyle(exercise.markedEasy ? SBSColors.success : SBSColors.textSecondaryFallback)
                                .padding(.horizontal, SBSLayout.paddingMedium)
                                .padding(.vertical, SBSLayout.paddingSmall)
                                .background(
                                    Capsule()
                                        .fill(exercise.markedEasy ? SBSColors.success.opacity(0.15) : SBSColors.surfaceFallback)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(
                                                    exercise.markedEasy ? SBSColors.success.opacity(0.4) : SBSColors.textTertiaryFallback.opacity(0.3),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if exercise.isStructured {
                    // nSuns display - show current set's weight and reps
                    VStack(spacing: SBSLayout.paddingMedium) {
                        // Intensity badge
                        if let intensity = intensityText {
                            Text(intensity)
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.warning)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(SBSColors.warning.opacity(0.15))
                                )
                        }
                        
                        // Weight for THIS set (tappable to override)
                        Button {
                            onWeightTap?()
                        } label: {
                            HStack(spacing: 6) {
                                Text(currentWeight.formattedWeight(useMetric: useMetric))
                                    .font(SBSFonts.display())
                                    .foregroundStyle(isCurrentAMRAP ? SBSColors.warning : SBSColors.accentFallback)

                                Image(systemName: "pencil.circle")
                                    .font(SBSFonts.title3())
                                    .foregroundStyle(SBSColors.textTertiaryFallback)
                            }
                        }
                        
                        // Plate Calculator
                        if showPlateCalculator && currentWeight >= barWeight {
                            PremiumBarbellView(
                                weight: currentWeight,
                                useMetric: useMetric,
                                barWeight: barWeight,
                                showLabels: true,
                                compact: false,
                                onUnlockTap: onUnlockTap
                            )
                            .padding(.horizontal, SBSLayout.paddingMedium)
                        }
                        
                        // Reps
                        HStack(spacing: SBSLayout.paddingSmall) {
                            if isCurrentAMRAP {
                                Text("\(currentReps)+")
                                    .font(SBSFonts.title())
                                    .foregroundStyle(SBSColors.warning)
                                
                                Text("reps (AMRAP)")
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            } else {
                                Text("\(currentReps)")
                                    .font(SBSFonts.title())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                
                                Text("reps")
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                        }
                        
                        if isCurrentAMRAP {
                            Text(currentReps == 1 ? "Heavy single - go for it!" : "AMRAP set - push it!")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.warning)
                                .padding(.horizontal, SBSLayout.paddingMedium)
                                .padding(.vertical, SBSLayout.paddingSmall)
                                .background(
                                    Capsule()
                                        .fill(SBSColors.warning.opacity(0.15))
                                )
                        }

                        if let prReps = prHintReps {
                            Text("\(prReps) reps would be a new 1RM!")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.warning)
                                .padding(.horizontal, SBSLayout.paddingMedium)
                                .padding(.vertical, SBSLayout.paddingSmall)
                                .background(
                                    Capsule()
                                        .fill(SBSColors.warning.opacity(0.15))
                                )
                        }
                    }
                } else if exercise.isLinear {
                    // Linear progression display
                    VStack(spacing: SBSLayout.paddingMedium) {
                        // Intensity badge
                        if let intensity = intensityText {
                            Text(intensity)
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.accentFallback)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(SBSColors.accentFallback.opacity(0.15))
                                )
                        }

                        // Weight (tappable to override)
                        Button {
                            onWeightTap?()
                        } label: {
                            HStack(spacing: 6) {
                                Text(exercise.weight.formattedWeight(useMetric: useMetric))
                                    .font(SBSFonts.display())
                                    .foregroundStyle(SBSColors.accentFallback)

                                Image(systemName: "pencil.circle")
                                    .font(SBSFonts.title3())
                                    .foregroundStyle(SBSColors.textTertiaryFallback)
                            }
                        }
                        
                        // Plate Calculator - visual barbell
                        if showPlateCalculator && exercise.weight >= barWeight {
                            PremiumBarbellView(
                                weight: exercise.weight,
                                useMetric: useMetric,
                                barWeight: barWeight,
                                showLabels: true,
                                compact: false,
                                onUnlockTap: onUnlockTap
                            )
                            .padding(.horizontal, SBSLayout.paddingMedium)
                        }
                        
                        // Reps
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Text("\(exercise.repsPerSet)")
                                .font(SBSFonts.title())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text("reps")
                                .font(SBSFonts.title2())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        
                        // Deload warning
                        if let info = exercise.linearInfo, info.isDeloadPending {
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(SBSFonts.caption())
                                
                                Text("Deload pending (\(info.consecutiveFailures) failures)")
                                    .font(SBSFonts.caption())
                            }
                            .foregroundStyle(SBSColors.warning)
                            .padding(.horizontal, SBSLayout.paddingMedium)
                            .padding(.vertical, SBSLayout.paddingSmall)
                            .background(
                                Capsule()
                                    .fill(SBSColors.warning.opacity(0.15))
                            )
                        }
                    }
                } else {
                    // Standard volume display
                    VStack(spacing: SBSLayout.paddingMedium) {
                        // Intensity badge
                        if let intensity = intensityText {
                            Text(intensity)
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.accentFallback)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(SBSColors.accentFallback.opacity(0.15))
                                )
                        }

                        // Weight (tappable to override)
                        Button {
                            onWeightTap?()
                        } label: {
                            HStack(spacing: 6) {
                                Text(exercise.weight.formattedWeight(useMetric: useMetric))
                                    .font(SBSFonts.display())
                                    .foregroundStyle(SBSColors.accentFallback)

                                Image(systemName: "pencil.circle")
                                    .font(SBSFonts.title3())
                                    .foregroundStyle(SBSColors.textTertiaryFallback)
                            }
                        }
                        
                        // Plate Calculator - visual barbell
                        if showPlateCalculator && exercise.weight >= barWeight {
                            PremiumBarbellView(
                                weight: exercise.weight,
                                useMetric: useMetric,
                                barWeight: barWeight,
                                showLabels: true,
                                compact: false,
                                onUnlockTap: onUnlockTap
                            )
                            .padding(.horizontal, SBSLayout.paddingMedium)
                        }
                        
                        // Reps
                        HStack(spacing: SBSLayout.paddingSmall) {
                            if workoutState.isCurrentSetRepOut {
                                Text("\(exercise.repOutTarget)+")
                                    .font(SBSFonts.title())
                                    .foregroundStyle(SBSColors.success)
                                
                                Text("reps (AMRAP)")
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            } else {
                                Text("\(exercise.repsPerSet)")
                                    .font(SBSFonts.title())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                
                                Text("reps")
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                        }
                        
                        if workoutState.isCurrentSetRepOut {
                            Text("Last set! Go for max reps")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.success)
                                .padding(.horizontal, SBSLayout.paddingMedium)
                                .padding(.vertical, SBSLayout.paddingSmall)
                                .background(
                                    Capsule()
                                        .fill(SBSColors.success.opacity(0.15))
                                )
                        }

                        if let prReps = prHintReps {
                            Text("\(prReps) reps would be a new 1RM!")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.success)
                                .padding(.horizontal, SBSLayout.paddingMedium)
                                .padding(.vertical, SBSLayout.paddingSmall)
                                .background(
                                    Capsule()
                                        .fill(SBSColors.success.opacity(0.15))
                                )
                        }
                    }
                }
                
                Spacer()
                
                // Complete button
                Button(action: onComplete) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(SBSFonts.title())
                        
                        Text(isCurrentAMRAP ? "Log Reps" : "Complete Set")
                            .font(SBSFonts.button())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingMedium + 4)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                            .fill(buttonColor)
                    )
                }
                .padding(.horizontal, SBSLayout.paddingLarge)
                .padding(.bottom, SBSLayout.paddingXLarge)
            }
        }
    }
    
    private var buttonColor: Color {
        if let exercise = workoutState.currentExercise, exercise.isStructured {
            return isCurrentAMRAP ? SBSColors.warning : SBSColors.accentFallback
        }
        if workoutState.isCurrentSetRepOut {
            return SBSColors.success
        } else if workoutState.isCurrentExerciseAccessory {
            return SBSColors.accentSecondaryFallback
        } else {
            return SBSColors.accentFallback
        }
    }
}

// MARK: - nSuns Set Indicator Strip

struct StructuredSetIndicatorStrip: View {
    let sets: [StructuredSetInfo]
    let currentSet: Int  // 1-indexed
    let completedSets: Set<Int>  // 1-indexed set numbers
    let useMetric: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sets, id: \.setIndex) { setInfo in
                        let setNumber = setInfo.setIndex + 1  // Convert to 1-indexed
                        StructuredSetIndicator(
                            setInfo: setInfo,
                            isCompleted: completedSets.contains(setNumber),
                            isCurrent: setNumber == currentSet,
                            useMetric: useMetric
                        )
                    }
                }
                .padding(.horizontal, SBSLayout.paddingLarge)
                .frame(minWidth: geometry.size.width)
            }
        }
        .frame(height: 58)  // Circle (40) + spacing (2) + label (~16)
    }
}

struct StructuredSetIndicator: View {
    let setInfo: StructuredSetInfo
    let isCompleted: Bool
    let isCurrent: Bool
    let useMetric: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    VStack(spacing: 0) {
                        Text(setInfo.isAMRAP ? "\(setInfo.targetReps)+" : "\(setInfo.targetReps)")
                            .font(SBSFonts.captionBold())
                            .foregroundStyle(isCurrent ? .white : (setInfo.isAMRAP ? SBSColors.warning : SBSColors.textSecondaryFallback))
                    }
                }
            }
            
            // Weight label
            Text(setInfo.weight.formattedWeightShort(useMetric: useMetric))
                .font(SBSFonts.label())
                .foregroundStyle(isCurrent ? (setInfo.isAMRAP ? SBSColors.warning : SBSColors.accentFallback) : SBSColors.textTertiaryFallback)
        }
    }
    
    private var backgroundColor: Color {
        if isCompleted {
            return SBSColors.success
        } else if isCurrent {
            return setInfo.isAMRAP ? SBSColors.warning : SBSColors.accentFallback
        } else {
            return setInfo.isAMRAP ? SBSColors.warning.opacity(0.2) : SBSColors.surfaceFallback
        }
    }
}

// MARK: - Set Indicator Strip

struct SetIndicatorStrip: View {
    let totalSets: Int
    let currentSet: Int
    let completedSets: Set<Int>
    let repsPerSet: Int
    let repOutTarget: Int
    let isRepOutSet: (Int) -> Bool
    var isAccessory: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SBSLayout.paddingSmall) {
                    ForEach(1...totalSets, id: \.self) { setNumber in
                        let isAmrap = isRepOutSet(setNumber)
                        let reps = isAmrap ? repOutTarget : repsPerSet
                        SetIndicator(
                            setNumber: setNumber,
                            reps: reps,
                            isAmrap: isAmrap,
                            isCompleted: completedSets.contains(setNumber),
                            isCurrent: setNumber == currentSet,
                            isAccessory: isAccessory
                        )
                    }
                }
                .padding(.horizontal, SBSLayout.paddingLarge)
                .frame(minWidth: geometry.size.width)
            }
        }
        .frame(height: 64)  // Circle (44) + spacing (4) + label (~16)
    }
}

struct SetIndicator: View {
    let setNumber: Int
    let reps: Int
    let isAmrap: Bool
    let isCompleted: Bool
    let isCurrent: Bool
    var isAccessory: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    // Show rep count with + only for AMRAP sets
                    Text(isAmrap && !isAccessory ? "\(reps)+" : "\(reps)")
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(isCurrent ? .white : SBSColors.textSecondaryFallback)
                }
            }
            
            // Show set number label below
            Text("Set \(setNumber)")
                .font(SBSFonts.label())
                .foregroundStyle(isCurrent ? (isAmrap && !isAccessory ? SBSColors.success : SBSColors.accentFallback) : SBSColors.textTertiaryFallback)
        }
    }
    
    private var backgroundColor: Color {
        if isCompleted {
            return SBSColors.success
        } else if isCurrent {
            if isAccessory {
                return SBSColors.accentSecondaryFallback
            }
            return isAmrap ? SBSColors.success : SBSColors.accentFallback
        } else {
            return SBSColors.surfaceFallback
        }
    }
}

// MARK: - Timer View

struct TimerView: View {
    @Bindable var workoutState: WorkoutState
    let useMetric: Bool
    let showSuperset: Bool
    var barWeight: Double = 45
    var showPlateCalculator: Bool = true
    let onTimerEnd: () -> Void
    var onSkip: (() -> Void)?
    var onUnlockTap: (() -> Void)?
    var onAccessoryWeightTap: (() -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onAdjust: ((Int) -> Void)?
    
    private var hasSuperset: Bool {
        showSuperset && workoutState.currentSupersetAccessory != nil
    }
    
    var body: some View {
        VStack(spacing: hasSuperset ? SBSLayout.paddingMedium : SBSLayout.paddingLarge) {
            // Superset accessory card (shown at top when enabled)
            if let accessory = workoutState.currentSupersetAccessory, showSuperset {
                SupersetAccessoryCard(
                    accessory: accessory,
                    useMetric: useMetric,
                    compact: true,
                    onWeightTap: onAccessoryWeightTap
                )
                    .padding(.horizontal)
                    .padding(.top, SBSLayout.paddingSmall)
            }
            
            Spacer(minLength: hasSuperset ? 8 : 20)
            
            // Timer circle - smaller when superset is showing
            ZStack {
                let circleSize: CGFloat = hasSuperset ? 160 : 200
                let lineWidth: CGFloat = hasSuperset ? 10 : 12
                
                // Background circle
                Circle()
                    .stroke(SBSColors.surfaceFallback, lineWidth: lineWidth)
                    .frame(width: circleSize, height: circleSize)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: timerProgress)
                    .stroke(
                        timerColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: circleSize, height: circleSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timerProgress)
                
                // Timer text
                VStack(spacing: 4) {
                    Text(timerText)
                        .font(SBSFonts.displayMono())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                        .accessibilityLabel(hasSuperset ? "Superset timer" : "Rest timer")
                        .accessibilityValue(timerAccessibilityValue)

                    Text(hasSuperset ? "SUPERSET" : "REST")
                        .font(SBSFonts.caption())
                        .foregroundStyle(hasSuperset ? SBSColors.accentSecondaryFallback : SBSColors.textSecondaryFallback)

                    if workoutState.timerDuration > 0 {
                        Text("of \(formatDuration(workoutState.timerDuration))")
                            .font(SBSFonts.caption2())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                }
            }
            
            // Timer controls - smaller when superset is showing
            HStack(spacing: hasSuperset ? SBSLayout.paddingMedium : SBSLayout.paddingLarge) {
                let buttonSize: CGFloat = hasSuperset ? 48 : 56
                let adjustSize: CGFloat = hasSuperset ? 44 : 50

                // -15s
                Button {
                    onAdjust?(-15)
                } label: {
                    Text("−15s")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                        .frame(width: adjustSize, height: adjustSize)
                        .background(
                            Circle().fill(SBSColors.surfaceFallback)
                        )
                }
                .accessibilityLabel("Subtract 15 seconds")

                // Pause/Resume
                Button {
                    Haptics.light()
                    if workoutState.timerIsPaused {
                        workoutState.resumeTimer()
                        onResume?()
                    } else {
                        workoutState.pauseTimer()
                        onPause?()
                    }
                    // Update Live Activity with pause state (Pro only)
                    if StoreManager.shared.canAccess(.liveActivity) {
                        LiveActivityManager.shared.updateTimer(
                            secondsRemaining: workoutState.timerRemaining,
                            isPaused: workoutState.timerIsPaused
                        )
                    }
                } label: {
                    Image(systemName: workoutState.timerIsPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: hasSuperset ? 20 : 24))
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(
                            Circle()
                                .fill(SBSColors.surfaceFallback)
                        )
                }
                .accessibilityLabel(workoutState.timerIsPaused ? "Resume timer" : "Pause timer")

                // Skip
                Button {
                    onSkip?()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: hasSuperset ? 20 : 24))
                        .foregroundStyle(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(
                            Circle()
                                .fill(workoutState.isCurrentExerciseAccessory ? SBSColors.accentSecondaryFallback : SBSColors.accentFallback)
                        )
                }
                .accessibilityLabel("Skip rest timer")

                // +15s
                Button {
                    onAdjust?(15)
                } label: {
                    Text("+15s")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                        .frame(width: adjustSize, height: adjustSize)
                        .background(
                            Circle().fill(SBSColors.surfaceFallback)
                        )
                }
                .accessibilityLabel("Add 15 seconds")
            }
            
            Spacer(minLength: hasSuperset ? 8 : 20)
            
            // Next set preview
            if let exercise = workoutState.currentExercise {
                // Structured exercises store per-set targets in
                // structuredSetInfo and intentionally leave the top-level
                // weight/reps fields blank (heaviest weight, 0 reps) — read
                // from the per-set info when available so the upcoming set
                // shows its actual targets. Mirrors CurrentSetView.
                let upcomingSet: StructuredSetInfo? = {
                    guard exercise.isStructured,
                          let sets = exercise.structuredSetInfo,
                          workoutState.currentSetNumber > 0,
                          workoutState.currentSetNumber <= sets.count
                    else { return nil }
                    return sets[workoutState.currentSetNumber - 1]
                }()
                let nextWeight = upcomingSet?.weight ?? exercise.weight
                let nextReps: String = {
                    if workoutState.isCurrentSetRepOut {
                        return "\(exercise.repOutTarget)+"
                    }
                    if let s = upcomingSet { return "\(s.targetReps)" }
                    return "\(exercise.repsPerSet)"
                }()

                NextSetPreview(
                    exerciseName: exercise.name,
                    weight: nextWeight,
                    reps: nextReps,
                    isRepOut: workoutState.isCurrentSetRepOut,
                    isAccessory: exercise.isAccessory,
                    setNumber: workoutState.currentSetNumber,
                    totalSets: exercise.totalSets,
                    useMetric: useMetric,
                    barWeight: barWeight,
                    showPlateCalculator: showPlateCalculator,
                    compact: hasSuperset,
                    onUnlockTap: onUnlockTap
                )
            }
        }
        .onChange(of: workoutState.timerRemaining) { oldValue, newValue in
            // Automatically end timer when it reaches 0
            if oldValue > 0 && newValue <= 0 && workoutState.timerIsRunning {
                onTimerEnd()
            }
        }
        // Keep the fixed-size timer ring and control buttons intact at large
        // accessibility text sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var timerProgress: Double {
        guard workoutState.timerDuration > 0 else { return 0 }
        return Double(workoutState.timerRemaining) / Double(workoutState.timerDuration)
    }
    
    private var timerColor: Color {
        if workoutState.timerRemaining <= 10 {
            return SBSColors.warning
        } else if workoutState.timerRemaining <= 30 {
            return SBSColors.accentFallback
        } else {
            return SBSColors.accentSecondaryFallback
        }
    }
    
    private var timerText: String {
        let minutes = workoutState.timerRemaining / 60
        let seconds = workoutState.timerRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Spoken form of the countdown for VoiceOver, e.g. "1 minute 30 seconds
    /// remaining". The digit-clock `timerText` reads poorly on its own.
    private var timerAccessibilityValue: String {
        let minutes = workoutState.timerRemaining / 60
        let seconds = workoutState.timerRemaining % 60
        var parts: [String] = []
        if minutes > 0 {
            parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")")
        }
        if seconds > 0 || minutes == 0 {
            parts.append("\(seconds) second\(seconds == 1 ? "" : "s")")
        }
        let base = parts.joined(separator: " ")
        return workoutState.timerIsPaused ? "\(base) remaining, paused" : "\(base) remaining"
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Next Set Preview

struct NextSetPreview: View {
    let exerciseName: String
    let weight: Double
    let reps: String
    let isRepOut: Bool
    var isAccessory: Bool = false
    let setNumber: Int
    let totalSets: Int
    let useMetric: Bool
    var barWeight: Double = 45
    var showPlateCalculator: Bool = true
    var compact: Bool = false
    var onUnlockTap: (() -> Void)?
    
    var body: some View {
        VStack(spacing: compact ? 4 : SBSLayout.paddingSmall) {
            Text("NEXT UP")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
            
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            if isAccessory {
                                Image(systemName: "dumbbell.fill")
                                    .font(SBSFonts.caption2())
                                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                            }
                            
                            Text(exerciseName)
                                .font(compact ? SBSFonts.body() : SBSFonts.bodyBold())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        
                        Text("Set \(setNumber) of \(totalSets)")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: SBSLayout.paddingSmall) {
                        // Show weight (0 is valid for bodyweight accessories)
                        Text(weight.formattedWeightShort(useMetric: useMetric))
                            .font(compact ? SBSFonts.bodyBold() : SBSFonts.weight())
                            .foregroundStyle(isAccessory ? SBSColors.accentSecondaryFallback : SBSColors.accentFallback)
                        
                        Text("×")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                        
                        Text(reps)
                            .font(compact ? SBSFonts.bodyBold() : SBSFonts.weight())
                            .foregroundStyle(isRepOut ? SBSColors.success : SBSColors.textPrimaryFallback)
                    }
                }
                .padding(compact ? SBSLayout.paddingMedium : SBSLayout.paddingMedium + 4)
                
                // Plate calculator for barbell exercises
                if !isAccessory && showPlateCalculator && weight >= barWeight {
                    PremiumBarbellView(
                        weight: weight,
                        useMetric: useMetric,
                        barWeight: barWeight,
                        showLabels: true,
                        compact: true,
                        onUnlockTap: onUnlockTap
                    )
                    .scaleEffect(compact ? 0.85 : 1.0)
                    .frame(height: compact ? 35 : 44)
                    .padding(.horizontal, SBSLayout.paddingSmall)
                    .padding(.bottom, compact ? SBSLayout.paddingSmall : SBSLayout.paddingMedium)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(isAccessory ? SBSColors.accentSecondaryFallback.opacity(0.08) : SBSColors.surfaceFallback)
                    .overlay(
                        isAccessory ?
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .strokeBorder(SBSColors.accentSecondaryFallback.opacity(0.2), lineWidth: 1)
                        : nil
                    )
            )
        }
        .padding(.horizontal)
        .padding(.bottom, compact ? SBSLayout.paddingMedium : SBSLayout.paddingLarge)
    }
}

// MARK: - Superset Accessory Card

struct SupersetAccessoryCard: View {
    let accessory: SupersetAccessoryData
    let useMetric: Bool
    var compact: Bool = false
    var onWeightTap: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: compact ? 4 : SBSLayout.paddingSmall) {
            HStack(spacing: SBSLayout.paddingSmall) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                
                Text("SUPERSET")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.accentSecondaryFallback)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "dumbbell.fill")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                        
                        Text(accessory.name)
                            .font(compact ? SBSFonts.bodyBold() : SBSFonts.title3())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    
                    // Sets and reps info
                    Text("\(accessory.sets) × \(accessory.reps) reps")
                        .font(compact ? SBSFonts.caption() : SBSFonts.body())
                        .foregroundStyle(SBSColors.textSecondaryFallback)

                    if accessory.lastWasEasy == true {
                        HStack(spacing: 3) {
                            Image(systemName: "hand.thumbsup.fill")
                                .font(SBSFonts.caption2())
                            Text("Last time was easy, go heavier")
                                .font(SBSFonts.caption())
                        }
                        .foregroundStyle(SBSColors.success)
                    }
                }
                
                Spacer()
                
                // Weight section - tappable to add/edit
                Button(action: { onWeightTap?() }) {
                    if let weight = accessory.weight {
                        // Show logged weight with edit indicator
                        HStack(spacing: 4) {
                            Text(weight.formattedWeightShort(useMetric: useMetric))
                                .font(compact ? SBSFonts.bodyBold() : SBSFonts.weight())
                                .foregroundStyle(SBSColors.accentSecondaryFallback)
                            
                            Text(useMetric ? "kg" : "lb")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            
                            Image(systemName: "chevron.right")
                                .font(SBSFonts.caption2())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    } else {
                        // No weight logged - show add indicator
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.accentSecondaryFallback)
                            
                            Text("Add Weight")
                                .font(compact ? SBSFonts.caption() : SBSFonts.body())
                                .foregroundStyle(SBSColors.accentSecondaryFallback)
                        }
                        .padding(.horizontal, compact ? 8 : 12)
                        .padding(.vertical, compact ? 4 : 6)
                        .background(
                            Capsule()
                                .fill(SBSColors.accentSecondaryFallback.opacity(0.15))
                        )
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(compact ? SBSLayout.paddingMedium : SBSLayout.paddingMedium + 4)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(SBSColors.accentSecondaryFallback.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .strokeBorder(SBSColors.accentSecondaryFallback.opacity(0.3), lineWidth: 1.5)
                    )
            )
        }
    }
}

// MARK: - Workout Complete View

struct WorkoutCompleteView: View {
    let workoutState: WorkoutState
    let appState: AppState
    let week: Int
    let day: Int
    let onDone: () -> Void
    let onShare: () -> Void
    
    @State private var confettiScale: CGFloat = 0.5
    @State private var confettiOpacity: Double = 0
    @State private var showConfetti = false
    
    private var hasPRs: Bool {
        !workoutState.prsAchieved.isEmpty
    }
    
    private var prCount: Int {
        workoutState.prsAchieved.count
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: SBSLayout.paddingLarge) {
                Spacer()
                
                // Celebration icon
                ZStack {
                    // Glow for PRs
                    if hasPRs {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.yellow.opacity(0.4), Color.clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 180, height: 180)
                            .scaleEffect(showConfetti ? 1.2 : 0.8)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: showConfetti)
                    }
                    
                    Circle()
                        .fill((hasPRs ? Color.orange : SBSColors.success).opacity(0.15))
                        .frame(width: 140, height: 140)
                        .scaleEffect(confettiScale)
                        .opacity(confettiOpacity)
                    
                    if hasPRs {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 70))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .orange.opacity(0.5), radius: 10, x: 0, y: 5)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(SBSColors.success)
                    }
                }
                
                VStack(spacing: SBSLayout.paddingSmall) {
                    if hasPRs {
                        Text("🎉 \(prCount) NEW PR\(prCount > 1 ? "S" : "")! 🎉")
                            .font(SBSFonts.title())
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Workout Complete!")
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                    } else {
                        Text("Workout Complete!")
                            .font(SBSFonts.largeTitle())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                    }
                    
                    Text("Great work! Your progress has been saved.")
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                        .multilineTextAlignment(.center)
                }
                
                // Quick stats
                HStack(spacing: SBSLayout.paddingLarge) {
                    StatBubble(
                        icon: "dumbbell.fill",
                        value: "\(workoutState.exercises.count)",
                        label: "exercises"
                    )
                    
                    StatBubble(
                        icon: "checkmark.circle.fill",
                        value: "\(workoutState.completedSets.values.reduce(0) { $0 + $1.count })",
                        label: "sets"
                    )
                    
                    if !workoutState.amrapResults.isEmpty {
                        StatBubble(
                            icon: "flame.fill",
                            value: "\(workoutState.amrapResults.count)",
                            label: "AMRAPs"
                        )
                    }
                }
                .padding(.top, SBSLayout.paddingMedium)
                
                Spacer()
                
                // Buttons
                VStack(spacing: SBSLayout.paddingMedium) {
                    // Share button (more prominent for PRs)
                    Button(action: onShare) {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "square.and.arrow.up")
                                .font(SBSFonts.bodyBold())
                            
                            Text(hasPRs ? "Share Your PR!" : "Share Workout")
                                .font(SBSFonts.button())
                        }
                        .foregroundStyle(hasPRs ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingMedium + 2)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                .fill(
                                    hasPRs
                                        ? LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                                        : LinearGradient(colors: [SBSColors.accentFallback], startPoint: .leading, endPoint: .trailing)
                                )
                        )
                    }
                    
                    // Done button
                    Button(action: onDone) {
                        Text("Done")
                            .font(SBSFonts.button())
                            .foregroundStyle(hasPRs ? SBSColors.textPrimaryFallback : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.paddingMedium + 2)
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                    .fill(hasPRs ? SBSColors.surfaceFallback : SBSColors.success)
                                    .overlay(
                                        hasPRs
                                            ? RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                                .strokeBorder(SBSColors.textTertiaryFallback.opacity(0.3), lineWidth: 1)
                                            : nil
                                    )
                            )
                    }
                }
                .padding(.horizontal, SBSLayout.paddingLarge)
                .padding(.bottom, SBSLayout.paddingXLarge)
            }
            
            // Confetti for PRs
            if showConfetti && hasPRs {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Play celebration haptic (fires on every finish, PR or not)
            Haptics.success()

            // Animate celebration
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                confettiScale = 1.2
                confettiOpacity = 1
            }
            
            if hasPRs {
                withAnimation(.easeIn(duration: 0.3).delay(0.2)) {
                    showConfetti = true
                }
                
                // Extra haptic for PRs
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let impact = UIImpactFeedbackGenerator(style: .heavy)
                    impact.impactOccurred()
                }
            }
        }
    }
}

// MARK: - Stat Bubble

private struct StatBubble: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.accentFallback)
                
                Text(value)
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
            }
            
            Text(label)
                .font(SBSFonts.caption2())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding(.horizontal, SBSLayout.paddingMedium)
        .padding(.vertical, SBSLayout.paddingSmall)
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                .fill(SBSColors.surfaceFallback)
        )
    }
}

// MARK: - Exercise Picker Sheet

struct ExercisePickerSheet: View {
    let workoutState: WorkoutState
    let useMetric: Bool
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Check if workout has any accessory exercises
    private var hasAccessories: Bool {
        workoutState.exercises.contains { $0.isAccessory }
    }

    private var totalSets: Int {
        workoutState.exercises.reduce(0) { $0 + $1.totalSets }
    }

    private var completedExerciseCount: Int {
        workoutState.exercises.enumerated().filter { idx, ex in
            workoutState.completedSetsForExercise(at: idx) >= ex.totalSets
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        WorkoutOverviewSummary(
                            progress: workoutState.progress,
                            completedSets: workoutState.completedSetsCount,
                            totalSets: totalSets,
                            completedExercises: completedExerciseCount,
                            totalExercises: workoutState.exercises.count,
                            prCount: workoutState.prsAchieved.count
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    ForEach(Array(workoutState.exercises.enumerated()), id: \.element.id) { index, exercise in
                        ExercisePickerRow(
                            exercise: exercise,
                            index: index,
                            isCurrent: index == workoutState.currentExerciseIndex,
                            completedSets: workoutState.completedSetsForExercise(at: index),
                            amrapResult: workoutState.amrapResults[exercise.lift ?? exercise.name],
                            useMetric: useMetric,
                            onTap: {
                                onSelect(index)
                            }
                        )
                        .id(index)
                        .listRowBackground(
                            index == workoutState.currentExerciseIndex
                                ? SBSColors.accentFallback.opacity(0.1)
                                : Color.clear
                        )
                    }

                    // Hint about adding accessories if none are configured
                    if !hasAccessories {
                        Section {
                            HStack(spacing: SBSLayout.paddingMedium) {
                                Image(systemName: "plus.circle")
                                    .font(SBSFonts.title3())
                                    .foregroundStyle(SBSColors.accentSecondaryFallback)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Add Accessories")
                                        .font(SBSFonts.bodyBold())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)

                                    Text("You can add accessory exercises to each day via Settings → Day Accessories")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                            }
                            .padding(.vertical, SBSLayout.paddingSmall)
                        }
                        .listRowBackground(SBSColors.accentSecondaryFallback.opacity(0.08))
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    // Scroll to current exercise
                    proxy.scrollTo(workoutState.currentExerciseIndex, anchor: .center)
                }
            }
            .navigationTitle("Workout Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sbsBackground()
        }
    }
}

// MARK: - Workout Overview Summary

private struct WorkoutOverviewSummary: View {
    let progress: Double
    let completedSets: Int
    let totalSets: Int
    let completedExercises: Int
    let totalExercises: Int
    let prCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(progress * 100))%")
                    .font(SBSFonts.title())
                    .foregroundStyle(SBSColors.accentFallback)
                Text("complete")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                Spacer()
                if prCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                        Text("\(prCount) PR\(prCount == 1 ? "" : "s")")
                            .font(SBSFonts.captionBold())
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SBSColors.surfaceFallback)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SBSColors.accentFallback)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 6)

            HStack(spacing: SBSLayout.paddingLarge) {
                summaryStat(label: "Sets", value: "\(completedSets) / \(totalSets)")
                summaryStat(label: "Exercises", value: "\(completedExercises) / \(totalExercises)")
                Spacer()
            }
        }
        .padding(SBSLayout.paddingMedium)
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback.opacity(0.5))
        )
        .padding(.horizontal, SBSLayout.paddingMedium)
        .padding(.vertical, SBSLayout.paddingSmall)
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(SBSFonts.bodyBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            Text(label)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
    }
}

struct ExercisePickerRow: View {
    let exercise: WorkoutExercise
    let index: Int
    let isCurrent: Bool
    let completedSets: Int
    var amrapResult: (weight: Double, reps: Int, e1rm: Double)? = nil
    let useMetric: Bool
    let onTap: () -> Void

    private var isComplete: Bool {
        completedSets >= exercise.totalSets
    }

    private var isInProgress: Bool {
        completedSets > 0 && !isComplete
    }

    private var repsLabel: String {
        if exercise.isStructured, let sets = exercise.structuredSetInfo,
           let amrap = sets.first(where: { $0.isAMRAP }) {
            return "\(sets.count) × \(amrap.targetReps)+"
        }
        if exercise.isLinear {
            return "\(exercise.totalSets) × \(exercise.repsPerSet)"
        }
        if exercise.isAccessory {
            return "\(exercise.totalSets) × \(exercise.repsPerSet)"
        }
        // Volume: last set is rep-out
        let normal = max(0, exercise.totalSets - 1)
        if normal > 0 {
            return "\(normal) × \(exercise.repsPerSet) + \(exercise.repOutTarget)+"
        }
        return "\(exercise.repOutTarget)+"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SBSLayout.paddingMedium) {
                // Status indicator
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(SBSColors.success)
                    } else {
                        Text("\(index + 1)")
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(statusColor)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        if exercise.isAccessory {
                            Image(systemName: "dumbbell.fill")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.accentSecondaryFallback)
                        }

                        Text(exercise.name)
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    HStack(spacing: SBSLayout.paddingSmall) {
                        Text(exercise.weight.formattedWeightShort(useMetric: useMetric))
                            .font(SBSFonts.caption())
                            .foregroundStyle(exercise.isAccessory ? SBSColors.accentSecondaryFallback : SBSColors.accentFallback)

                        Text("·")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)

                        Text(repsLabel)
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)

                        Text("·")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)

                        Text("\(completedSets)/\(exercise.totalSets) sets")
                            .font(SBSFonts.caption())
                            .foregroundStyle(isComplete ? SBSColors.success : SBSColors.textSecondaryFallback)
                    }

                    if let amrap = amrapResult {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(SBSFonts.caption2())
                            Text("AMRAP: \(amrap.reps) reps @ \(amrap.weight.formattedWeightShort(useMetric: useMetric))")
                                .font(SBSFonts.caption())
                        }
                        .foregroundStyle(SBSColors.success)
                    }
                }

                Spacer()

                // Status badge: CURRENT > IN PROGRESS > COMPLETE > nothing
                if isCurrent {
                    Text("CURRENT")
                        .font(SBSFonts.label())
                        .foregroundStyle(SBSColors.accentFallback)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(SBSColors.accentFallback.opacity(0.15)))
                } else if isInProgress {
                    Text("IN PROGRESS")
                        .font(SBSFonts.label())
                        .foregroundStyle(SBSColors.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(SBSColors.warning.opacity(0.15)))
                } else if isComplete {
                    Text("DONE")
                        .font(SBSFonts.label())
                        .foregroundStyle(SBSColors.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(SBSColors.success.opacity(0.15)))
                }

                Image(systemName: "chevron.right")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            .padding(.vertical, SBSLayout.paddingSmall)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        if isComplete {
            return SBSColors.success
        } else if isCurrent {
            return SBSColors.accentFallback
        } else if isInProgress {
            return SBSColors.warning
        } else if exercise.isAccessory {
            return SBSColors.accentSecondaryFallback
        } else {
            return SBSColors.textSecondaryFallback
        }
    }
}

// MARK: - Rep Out Input Sheet

struct RepOutInputSheet: View {
    let liftName: String
    let target: Int
    let structuredContext: StructuredProgressionContext?  // nil = percentage display (SBS style)
    var prRepsNeeded: Int? = nil
    let onSave: (Int, String) -> Void
    let onCancel: () -> Void
    
    @State private var reps: Int?
    @State private var note: String = ""
    @State private var showingNoteField: Bool = false
    @FocusState private var isNoteFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Text(liftName)
                        .font(SBSFonts.title())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("How many reps on your AMRAP set?")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .padding(.top)
                
                // Note field (collapsible)
                VStack(spacing: SBSLayout.paddingSmall) {
                    if showingNoteField || !note.isEmpty {
                        HStack {
                            Image(systemName: "note.text")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            
                            TextField("Add a note (optional)", text: $note, axis: .vertical)
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                                .lineLimit(1...3)
                                .focused($isNoteFocused)
                            
                            if !note.isEmpty {
                                Button {
                                    note = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(SBSFonts.body())
                                        .foregroundStyle(SBSColors.textTertiaryFallback)
                                }
                            }
                        }
                        .padding(SBSLayout.paddingMedium)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .fill(SBSColors.surfaceFallback)
                        )
                        .padding(.horizontal)
                        .padding(.top, SBSLayout.paddingSmall)
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingNoteField = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isNoteFocused = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(SBSFonts.caption())
                                Text("Add note")
                                    .font(SBSFonts.caption())
                            }
                            .foregroundStyle(SBSColors.accentFallback)
                        }
                        .padding(.top, SBSLayout.paddingSmall)
                    }
                }
                
                // Number pad
                NumberPad(
                    value: $reps,
                    target: target,
                    structuredContext: structuredContext,
                    prRepsNeeded: prRepsNeeded,
                    onConfirm: {
                        if let r = reps {
                            onSave(r, note)
                        }
                    },
                    onCancel: onCancel
                )
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

// MARK: - Linear Result Sheet

struct LinearResultSheet: View {
    let exerciseName: String
    let weight: Double
    let sets: Int
    let reps: Int
    let failedSets: Int
    let increment: Double
    let isDeloadPending: Bool
    let consecutiveFailures: Int
    let useMetric: Bool
    let onSuccess: () -> Void
    let onFailure: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: SBSLayout.paddingLarge) {
                // Header
                VStack(spacing: SBSLayout.paddingSmall) {
                    Text(exerciseName)
                        .font(SBSFonts.largeTitle())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("\(sets)×\(reps) @ \(weight.formattedWeight(useMetric: useMetric))")
                        .font(SBSFonts.title2())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .padding(.top, SBSLayout.paddingLarge * 2)
                
                // Question
                Text("Did you complete all sets and reps?")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                Spacer()
                
                // Warning if deload pending
                if isDeloadPending {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(SBSColors.warning)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Warning: Deload Pending")
                                .font(SBSFonts.bodyBold())
                                .foregroundStyle(SBSColors.warning)
                            
                            Text("You've failed this lift \(consecutiveFailures) time\(consecutiveFailures == 1 ? "" : "s"). One more failure triggers a 10% deload.")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(SBSLayout.paddingMedium)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.warning.opacity(0.1))
                    )
                    .padding(.horizontal)
                    .padding(.bottom, SBSLayout.paddingSmall)
                }
                
                // Progression info
                VStack(spacing: SBSLayout.paddingSmall) {
                    HStack(alignment: .top, spacing: SBSLayout.paddingMedium) {
                        VStack(alignment: .leading) {
                            Text("If Success:")
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.success)
                            Text("+\(increment.formattedWeight(useMetric: useMetric)) next session")
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .trailing) {
                            Text("If Failed:")
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.error)
                            Text("Same weight")
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.surfaceFallback)
                )
                .padding(.horizontal)
                
                Spacer()
                
                // Buttons
                VStack(spacing: SBSLayout.paddingMedium) {
                    Button(action: onSuccess) {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(SBSFonts.title3())
                            
                            Text("Yes - All Reps Completed!")
                                .font(SBSFonts.button())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingMedium + 2)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                .fill(SBSColors.success)
                        )
                    }
                    
                    Button(action: onFailure) {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "xmark.circle.fill")
                                .font(SBSFonts.title3())
                            
                            Text("No - Missed Some Reps")
                                .font(SBSFonts.button())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingMedium + 2)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                .fill(SBSColors.error)
                        )
                    }
                }
                .padding(.horizontal, SBSLayout.paddingLarge)
                .padding(.bottom, SBSLayout.paddingXLarge)
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutView(
            appState: AppState(),
            week: 1,
            day: 1
        )
    }
}

