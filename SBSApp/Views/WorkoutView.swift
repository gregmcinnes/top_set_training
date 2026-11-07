import SwiftUI
import AVFoundation
import ActivityKit

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Workout View

struct WorkoutView: View {
    @Bindable var appState: AppState
    @Bindable var session: ActiveWorkoutSession

    @State private var showingExitConfirm = false
    @State private var showingExercisePicker = false
    @State private var showingPaywall = false  // For premium features
    @State private var showingShareSheet = false  // For workout summary share
    @State private var showingAccessoryWeightSheet = false  // For editing superset accessory weight
    @State private var showingStandaloneAccessoryWeight = false  // For editing the current standalone accessory's weight
    @State private var showingWeightOverride = false  // For overriding exercise weight mid-workout
    @ObservedObject private var watchConnectivity = WatchConnectivityManager.shared

    private let storeManager = StoreManager.shared

    private var workoutState: WorkoutState { session.workoutState }
    private var week: Int { session.week }
    private var day: Int { session.day }

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // The summary has its own header: the workout is over
                if !workoutState.isFinished {
                    WorkoutProgressHeader(
                        progress: workoutState.progress,
                        exerciseName: workoutState.currentExercise?.name ?? "Workout",
                        setInfo: session.setInfoText,
                        isAccessory: workoutState.isCurrentExerciseAccessory,
                        heartRate: watchConnectivity.currentHeartRate
                    )
                }

                if workoutState.isFinished {
                    WorkoutCompleteView(
                        workoutState: workoutState,
                        stats: session.calculateWorkoutStats(),
                        duration: session.workoutDuration,
                        outlooks: session.liftOutlooks(),
                        useMetric: appState.settings.useMetric,
                        canUndo: session.canUndoLastSet,
                        onDone: { session.finishAndDismiss() },
                        onShare: { showingShareSheet = true },
                        onUndo: { session.undoLastSet() }
                    )
                } else if workoutState.showingTimer {
                    // Timer view with next set preview
                    TimerView(
                        workoutState: workoutState,
                        useMetric: appState.settings.useMetric,
                        showSuperset: session.supersetsEnabled,
                        barWeight: appState.settings.barWeight,
                        showPlateCalculator: appState.shouldShowPlateCalculator,
                        onSkip: { session.handleTimerSkip() },
                        onUnlockTap: { showingPaywall = true },
                        onAccessoryWeightTap: { showingAccessoryWeightSheet = true },
                        onPause: {
                            NotificationManager.shared.cancelRestTimerNotification()
                            // Freeze the Watch countdown (endDate nil, isPaused true).
                            session.sendRestTimerStateToWatch()
                        },
                        onResume: {
                            // Pausing doesn't stop the tick loop, but a paused rest
                            // restored after a kill has none running yet.
                            session.startTimerTickLoop()
                            if appState.settings.pushNotificationsEnabled, let exercise = workoutState.currentExercise {
                                NotificationManager.shared.scheduleRestTimerNotification(
                                    duration: workoutState.timerRemaining,
                                    exerciseName: exercise.name,
                                    nextSetInfo: "Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
                                )
                            }
                            // Restart the Watch countdown from the fresh endDate.
                            session.sendRestTimerStateToWatch()
                        },
                        onAdjust: { delta in
                            session.handleTimerAdjust(by: delta)
                        },
                        onUndo: session.canUndoLastSet ? { session.undoLastSet() } : nil
                    )
                } else {
                    // Current set view
                    CurrentSetView(
                        workoutState: workoutState,
                        useMetric: appState.settings.useMetric,
                        barWeight: appState.settings.barWeight,
                        showPlateCalculator: appState.shouldShowPlateCalculator,
                        onComplete: session.handleSetComplete,
                        onMissed: session.handleSetMissed,
                        onUndoSet: { exerciseId, setNumber in
                            session.undoSet(exerciseId: exerciseId, setNumber: setNumber)
                        },
                        lastTime: lastTimeText,
                        onUnlockTap: { showingPaywall = true },
                        onWeightTap: {
                            guard let exercise = workoutState.currentExercise else { return }
                            if exercise.isAccessory {
                                showingStandaloneAccessoryWeight = true
                            } else {
                                showingWeightOverride = true
                            }
                        },
                        onMarkEasy: session.toggleCurrentAccessoryEasy,
                        personalRecordE1RM: { appState.personalRecord(for: $0)?.estimatedOneRM }
                    )
                }
            }
            .sbsBackground()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // Cap Dynamic Type so the largest accessibility sizes can't break the
        // fixed-height number pad / rest-timer layouts on this screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .toolbar {
            if !workoutState.isFinished {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(appState.dayTitle(day: day))
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .lineLimit(1)
                        Text("Week \(week) · \(appState.programDisplayName)")
                            .font(SBSFonts.caption2())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }

                ToolbarItem(placement: .topBarLeading) {
                    // Minimizing leaves the session running behind the resume bar
                    Button {
                        appState.minimizeWorkout()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .accessibilityLabel("Minimize workout")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingExercisePicker = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .accessibilityLabel("Exercise list")

                    Button {
                        showingExitConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .accessibilityLabel("Exit workout")
                }
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
                    session.cancelRestSurfaces()
                    workoutState.jumpToExercise(index)
                    showingExercisePicker = false
                    // Otherwise the Watch keeps showing the old set, and its next
                    // completion is dropped by the identity guard.
                    session.syncWorkoutStateToWatch()
                },
                onFinish: {
                    session.finishEarly()
                    showingExercisePicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Exit Workout?", isPresented: $showingExitConfirm) {
            Button("Keep Going", role: .cancel) {}
            if session.hasWorkoutProgress {
                Button("Finish Workout") {
                    session.finishEarly()
                }
            }
            Button("Exit", role: .destructive) {
                session.exitWorkoutWithoutSaving()
            }
        } message: {
            if session.hasWorkoutProgress {
                Text("Finish Workout shows your summary, logs your accessory sets and saves to Apple Fitness if it's on. Exit drops this session without any of that. Lift results already logged are kept.")
            } else {
                Text("Nothing has been logged in this session.")
            }
        }
        .alert("Lifts Still Open", isPresented: $session.showingOpenExercisesPrompt) {
            Button("Go Back") {
                session.goBackToOpenExercise()
            }
            Button("Finish Workout") {
                session.finishEarly()
            }
        } message: {
            Text("You still have \(workoutState.remainingSetsCount) \(workoutState.remainingSetsCount == 1 ? "set" : "sets") left. Go back to them, or finish here? Lifts you don't finish log nothing and keep their weight.")
        }
        .sheet(isPresented: $session.showingRepInput) {
            RepLogSheet(
                liftName: workoutState.currentExercise?.name ?? "",
                target: session.currentRepTarget,
                currentReps: session.pendingAMRAPLog.reps,
                currentNote: session.pendingAMRAPLog.note,
                setLabel: session.pendingStructuredSetIndex == nil ? nil : RepLogSheet.structuredSetLabel(target: session.currentRepTarget),
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
                    if let setIndex = session.pendingStructuredSetIndex,
                       let sets = exercise.structuredSetInfo,
                       let setInfo = sets.first(where: { $0.setIndex == setIndex }) {
                        weight = setInfo.weight
                    } else {
                        weight = exercise.weight
                    }
                    let lift = exercise.lift ?? exercise.name
                    return E1RM.newPRRepThreshold(
                        weight: weight,
                        targetReps: session.currentRepTarget,
                        bestE1RM: appState.personalRecord(for: lift)?.estimatedOneRM
                    )
                }(),
                onSave: { reps, note in
                    // Identity guard: the sheet was opened for a specific set. If the
                    // workout state has moved on (re-entrant ✓ tap during the sheet's
                    // dismiss animation) or that set is already completed, ignore the
                    // tap — otherwise we'd log duplicate reps and complete the next
                    // exercise's set 1.
                    guard let pending = session.pendingRepEntry,
                          pending.exerciseIndex == workoutState.currentExerciseIndex,
                          pending.setNumber == workoutState.currentSetNumber,
                          !workoutState.isSetCompleted(pending.setNumber) else {
                        Logger.debug("Ignoring stale rep-input save (current: exercise \(workoutState.currentExerciseIndex), set \(workoutState.currentSetNumber))", category: .general)
                        return
                    }
                    session.pendingRepEntry = nil

                    let setIndex = session.pendingStructuredSetIndex
                    session.pendingStructuredSetIndex = nil

                    if let exercise = workoutState.currentExercise,
                       let result = session.logAMRAPSet(exercise: exercise, structuredSetIndex: setIndex, reps: reps, note: note),
                       result.isNewPR, appState.settings.showPRCelebrations {
                        session.showingRepInput = false
                        // Complete the set and start timer (same as non-PR flow)
                        session.completeSetAndStartTimer()
                        session.presentPRCelebration(result)
                        return
                    }
                    session.completeSetAndStartTimer()
                    session.showingRepInput = false
                },
                onCancel: {
                    session.pendingStructuredSetIndex = nil
                    session.pendingRepEntry = nil
                    session.showingRepInput = false
                }
            )
            .presentationDetents([.height(session.pendingStructuredSetIndex == nil ? 420 : 500), .large])
            .presentationDragIndicator(.visible)
        }
        // item-driven: an isPresented cover reading separate optional state can render empty
        .fullScreenCover(item: $session.celebratingPR) { result in
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
                    session.celebratingPR = nil
                }
            )
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(triggeredByFeature: .plateCalculator)
        }
        .sheet(isPresented: $showingShareSheet) {
            WorkoutShareSheet(
                summary: session.buildWorkoutSummary(),
                useMetric: appState.settings.useMetric,
                onDismiss: { showingShareSheet = false }
            )
        }
        .sheet(isPresented: $showingAccessoryWeightSheet) {
            if let accessory = workoutState.currentSupersetAccessory {
                AccessoryWeightSheet(
                    accessoryName: accessory.name,
                    currentWeight: accessory.weight,
                    useMetric: appState.settings.useMetric,
                    roundingIncrement: appState.settings.roundingIncrement,
                    onSave: { weight in
                        workoutState.setCurrentSupersetAccessoryWeight(weight)
                        showingAccessoryWeightSheet = false
                    },
                    onCancel: { showingAccessoryWeightSheet = false }
                )
                .presentationDetents([.height(600), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingStandaloneAccessoryWeight) {
            if let exercise = workoutState.currentExercise, exercise.isAccessory {
                AccessoryWeightSheet(
                    accessoryName: exercise.name,
                    currentWeight: exercise.weight > 0 ? exercise.weight : nil,
                    useMetric: appState.settings.useMetric,
                    roundingIncrement: appState.settings.roundingIncrement,
                    onSave: { weight in
                        session.updateStandaloneAccessoryWeight(weight)
                        showingStandaloneAccessoryWeight = false
                    },
                    onCancel: { showingStandaloneAccessoryWeight = false }
                )
                .presentationDetents([.height(600), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingWeightOverride) {
            if let exercise = workoutState.currentExercise, let lift = exercise.lift {
                let currentOverride = appState.weightOverride(forExercise: exercise.name, lift: lift, week: week, day: day)
                let baseWeight = exercise.calculatedWeight ?? exercise.weight
                WeightOverrideSheet(
                    liftName: exercise.name,
                    calculatedWeight: baseWeight,
                    currentOverride: currentOverride,
                    prescribedReps: session.prescribedRepsDescription(for: exercise),
                    useMetric: appState.settings.useMetric,
                    roundingIncrement: appState.settings.roundingIncrement,
                    onSave: { newWeight in
                        session.applyWeightOverride(newWeight: newWeight, lift: lift)
                        showingWeightOverride = false
                    },
                    onClear: {
                        session.clearWeightOverride(lift: lift)
                        showingWeightOverride = false
                    },
                    onCancel: { showingWeightOverride = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            session.workoutScreenDidAppear()
        }
    }

    /// What the lifter last did on a main lift, e.g. "Last time: 100 lb, 5×5"
    private func lastTimeText(for exercise: WorkoutExercise) -> String? {
        guard !exercise.isAccessory, let lift = exercise.lift,
              let record = appState.lastPerformance(lift: lift, week: week, day: day) else { return nil }
        let useMetric = appState.settings.useMetric
        let weight = record.weight.formattedWeight(useMetric: useMetric)
        if let setType = record.setType, setType.contains("×") {
            // Linear results are stored as "5×5" or "5×5 (failed)"
            let scheme = setType.replacingOccurrences(of: " (failed)", with: "")
            return "Last time: \(weight), \(scheme)\(setType.contains("(failed)") ? ", missed reps" : "")"
        }
        return "Last time: \(weight) × \(record.reps)"
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
            .padding(.horizontal)
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
    var onMissed: (() -> Void)?
    var onUndoSet: ((UUID, Int) -> Void)?
    var lastTime: (WorkoutExercise) -> String? = { _ in nil }
    var onUnlockTap: (() -> Void)?
    var onWeightTap: (() -> Void)?
    var onMarkEasy: (() -> Void)?
    var personalRecordE1RM: (String) -> Double? = { _ in nil }

    @State private var setToUndo: Int?

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
            if structuredSet.isWeightOverridden { return "Adjusted" }
            return "\(Int(round(structuredSet.intensity * 100)))% TM"
        }
        // A linear lift's weight isn't a percentage of anything, so only say if it's changed
        if let exercise = workoutState.currentExercise, exercise.isLinear {
            if let calculated = exercise.calculatedWeight, calculated != exercise.weight {
                return "Adjusted"
            }
            return nil
        }
        // For volume exercises, use the exercise-level intensity
        if let exercise = workoutState.currentExercise,
           let intensity = exercise.intensity,
           intensity > 0 {
            if let calculated = exercise.calculatedWeight, calculated != exercise.weight {
                return "Adjusted"
            }
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
                        useMetric: useMetric,
                        onCompletedTap: { setToUndo = $0 }
                    )
                } else {
                    SetIndicatorStrip(
                        totalSets: exercise.totalSets,
                        currentSet: workoutState.currentSetNumber,
                        completedSets: workoutState.completedSets[exercise.id] ?? [],
                        failedSets: workoutState.failedSets[exercise.id] ?? [],
                        onCompletedTap: { setToUndo = $0 },
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
                        PrescriptionHero(
                            weight: exercise.weight.formattedWeight(useMetric: useMetric),
                            reps: "\(exercise.repsPerSet)",
                            repsLabel: "reps",
                            weightColor: SBSColors.accentSecondaryFallback,
                            repsColor: SBSColors.textPrimaryFallback,
                            onWeightTap: onWeightTap
                        )

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
                        PrescriptionHero(
                            weight: currentWeight.formattedWeight(useMetric: useMetric),
                            reps: isCurrentAMRAP ? "\(currentReps)+" : "\(currentReps)",
                            repsLabel: isCurrentAMRAP ? "reps (AMRAP)" : "reps",
                            weightColor: isCurrentAMRAP ? SBSColors.warning : SBSColors.accentFallback,
                            repsColor: isCurrentAMRAP ? SBSColors.warning : SBSColors.textPrimaryFallback,
                            onWeightTap: onWeightTap
                        )

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
                        
                        lastTimeLabel(for: exercise)

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
                        PrescriptionHero(
                            weight: exercise.weight.formattedWeight(useMetric: useMetric),
                            reps: "\(exercise.repsPerSet)",
                            repsLabel: "reps",
                            weightColor: SBSColors.accentFallback,
                            repsColor: SBSColors.textPrimaryFallback,
                            onWeightTap: onWeightTap
                        )

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

                        lastTimeLabel(for: exercise)

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
                        PrescriptionHero(
                            weight: exercise.weight.formattedWeight(useMetric: useMetric),
                            reps: workoutState.isCurrentSetRepOut ? "\(exercise.repOutTarget)+" : "\(exercise.repsPerSet)",
                            repsLabel: workoutState.isCurrentSetRepOut ? "reps (AMRAP)" : "reps",
                            weightColor: SBSColors.accentFallback,
                            repsColor: workoutState.isCurrentSetRepOut ? SBSColors.success : SBSColors.textPrimaryFallback,
                            onWeightTap: onWeightTap
                        )

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
                        
                        lastTimeLabel(for: exercise)

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
                .padding(.bottom, exercise.isLinear ? 0 : SBSLayout.paddingXLarge)

                // Only linear lifts progress from each set's result. Elsewhere a set's
                // reps don't change anything, and an AMRAP asks for its count anyway.
                if exercise.isLinear {
                    Button("Missed Reps") {
                        onMissed?()
                    }
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .frame(minHeight: 44)
                    .padding(.bottom, SBSLayout.paddingMedium)
                    .disabled(workoutState.isSetCompleted(workoutState.currentSetNumber))
                }
            }
        }
        .alert(
            "Undo Set \(setToUndo ?? 0)?",
            isPresented: Binding(get: { setToUndo != nil }, set: { if !$0 { setToUndo = nil } })
        ) {
            Button("Keep It", role: .cancel) {}
            Button("Undo Set") {
                if let setToUndo, let exercise = workoutState.currentExercise {
                    onUndoSet?(exercise.id, setToUndo)
                }
            }
        } message: {
            Text("This reopens the set and removes anything it logged.")
        }
    }

    @ViewBuilder
    private func lastTimeLabel(for exercise: WorkoutExercise) -> some View {
        if let text = lastTime(exercise) {
            Text(text)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textSecondaryFallback)
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

// MARK: - Prescription Hero

/// The two numbers a lifter needs from across the room: the weight and the reps
struct PrescriptionHero: View {
    let weight: String
    let reps: String
    let repsLabel: String
    let weightColor: Color
    let repsColor: Color
    var onWeightTap: (() -> Void)?

    @ScaledMetric(relativeTo: .largeTitle) private var weightSize: CGFloat = 60
    @ScaledMetric(relativeTo: .largeTitle) private var repsSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 2) {
            Button {
                onWeightTap?()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(weight)
                        .font(.system(size: weightSize, weight: .bold, design: .rounded))
                        .foregroundStyle(weightColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    Image(systemName: "pencil.circle")
                        .font(SBSFonts.title3())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
            }
            .accessibilityLabel("Edit weight, \(weight)")
            .padding(.horizontal, SBSLayout.paddingLarge)

            HStack(alignment: .firstTextBaseline, spacing: SBSLayout.paddingSmall) {
                Text(reps)
                    .font(.system(size: repsSize, weight: .bold, design: .rounded))
                    .foregroundStyle(repsColor)

                Text(repsLabel)
                    .font(SBSFonts.title2())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
        }
    }
}

// MARK: - nSuns Set Indicator Strip

struct StructuredSetIndicatorStrip: View {
    let sets: [StructuredSetInfo]
    let currentSet: Int  // 1-indexed
    let completedSets: Set<Int>  // 1-indexed set numbers
    let useMetric: Bool
    var onCompletedTap: ((Int) -> Void)?
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sets, id: \.setIndex) { setInfo in
                        let setNumber = setInfo.setIndex + 1  // Convert to 1-indexed
                        CompletedSetTapTarget(
                            setNumber: setNumber,
                            isCompleted: completedSets.contains(setNumber),
                            onTap: onCompletedTap
                        ) {
                            StructuredSetIndicator(
                                setInfo: setInfo,
                                isCompleted: completedSets.contains(setNumber),
                                isCurrent: setNumber == currentSet,
                                useMetric: useMetric
                            )
                        }
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

/// A set indicator that offers undo once its set is completed
struct CompletedSetTapTarget<Content: View>: View {
    let setNumber: Int
    let isCompleted: Bool
    let onTap: ((Int) -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isCompleted, let onTap {
            Button {
                onTap(setNumber)
            } label: {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo set \(setNumber)")
        } else {
            content()
        }
    }
}

// MARK: - Set Indicator Strip

struct SetIndicatorStrip: View {
    let totalSets: Int
    let currentSet: Int
    let completedSets: Set<Int>
    var failedSets: Set<Int> = []
    var onCompletedTap: ((Int) -> Void)?
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
                        CompletedSetTapTarget(
                            setNumber: setNumber,
                            isCompleted: completedSets.contains(setNumber),
                            onTap: onCompletedTap
                        ) {
                            SetIndicator(
                                setNumber: setNumber,
                                reps: reps,
                                isAmrap: isAmrap,
                                isCompleted: completedSets.contains(setNumber),
                                isCurrent: setNumber == currentSet,
                                isFailed: failedSets.contains(setNumber),
                                isAccessory: isAccessory
                            )
                        }
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
    var isFailed: Bool = false
    var isAccessory: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)
                
                if isCompleted {
                    Image(systemName: isFailed ? "xmark" : "checkmark")
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
                .foregroundStyle(isCurrent ? (isAccessory ? SBSColors.accentSecondaryFallback : isAmrap ? SBSColors.success : SBSColors.accentFallback) : SBSColors.textTertiaryFallback)
        }
    }
    
    private var backgroundColor: Color {
        if isFailed {
            return SBSColors.warning
        } else if isCompleted {
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
    var onSkip: (() -> Void)?
    var onUnlockTap: (() -> Void)?
    var onAccessoryWeightTap: (() -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onAdjust: ((Int) -> Void)?
    var onUndo: (() -> Void)?
    
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

            if let onUndo {
                Button(action: onUndo) {
                    Label("Undo Last Set", systemImage: "arrow.uturn.backward")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                        .frame(minHeight: 44)
                }
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
    let stats: (volume: Double, sets: Int, reps: Int)
    let duration: TimeInterval?
    let outlooks: [ActiveWorkoutSession.LiftOutlook]
    let useMetric: Bool
    let canUndo: Bool
    let onDone: () -> Void
    let onShare: () -> Void
    let onUndo: () -> Void

    @State private var showConfetti = false

    private var prs: [WorkoutPRRecord] { workoutState.prsAchieved }

    private var durationText: String? {
        guard let duration else { return nil }
        let minutes = Int((duration / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }

    private var volumeText: String {
        // Grouped: a workout's volume runs to five figures
        let value = useMetric ? stats.volume * lbToKg : stats.volume
        return "\(Int(value.rounded()).formatted()) \(useMetric ? "kg" : "lb")"
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: SBSLayout.paddingLarge) {
                        header
                        statsRow
                        if !prs.isEmpty { prSection }
                        if !outlooks.isEmpty { outlookSection }
                        if !workoutState.performedAccessories.isEmpty { accessorySection }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, SBSLayout.paddingLarge)
                }

                buttons
            }

            if showConfetti && !prs.isEmpty {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Play celebration haptic (fires on every finish, PR or not)
            Haptics.success()

            if !prs.isEmpty {
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

    private var header: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            Image(systemName: prs.isEmpty ? "checkmark.circle.fill" : "trophy.fill")
                .font(.system(size: 56))
                .foregroundStyle(prs.isEmpty ? SBSColors.success : .orange)

            Text(workoutState.finishedEarly ? "Workout Finished" : "Workout Complete")
                .font(SBSFonts.largeTitle())
                .foregroundStyle(SBSColors.textPrimaryFallback)
                .multilineTextAlignment(.center)
        }
    }

    private var statsRow: some View {
        HStack(spacing: SBSLayout.paddingSmall) {
            if let durationText {
                StatBubble(icon: "clock.fill", value: durationText, label: "duration")
            }
            StatBubble(icon: "scalemass.fill", value: volumeText, label: "volume")
            StatBubble(icon: "checkmark.circle.fill", value: "\(stats.sets)", label: "sets")
        }
    }

    private var prSection: some View {
        summarySection(title: prs.count == 1 ? "New PR" : "\(prs.count) New PRs") {
            ForEach(prs) { pr in
                summaryRow(
                    pr.liftName,
                    detail: "\(pr.weight.formattedWeight(useMetric: useMetric)) × \(pr.reps)",
                    note: "Est. 1RM \(pr.newE1RM.formattedWeight(useMetric: useMetric))"
                )
            }
        }
    }

    private var outlookSection: some View {
        summarySection(title: "Next Time") {
            ForEach(outlooks) { outlook in
                summaryRow(
                    outlook.name,
                    detail: outlook.nextWeight?.formattedWeight(useMetric: useMetric),
                    note: outlook.note
                )
            }
        }
    }

    /// What Done will log
    private var accessorySection: some View {
        summarySection(title: "Accessories") {
            ForEach(workoutState.performedAccessories, id: \.name) { accessory in
                summaryRow(
                    accessory.name,
                    detail: accessory.weight > 0 ? accessory.weight.formattedWeight(useMetric: useMetric) : nil,
                    note: "\(accessory.sets) × \(accessory.reps)"
                )
            }
        }
    }

    private func summarySection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text(title)
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            VStack(spacing: SBSLayout.paddingMedium) {
                content()
            }
            .padding(SBSLayout.paddingMedium)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(SBSColors.surfaceFallback)
            )
        }
    }

    private func summaryRow(_ name: String, detail: String?, note: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                if let note {
                    Text(note)
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
            }
            Spacer()
            if let detail {
                Text(detail)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            Button(action: onDone) {
                Text("Done")
                    .font(SBSFonts.button())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingMedium + 2)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                            .fill(SBSColors.accentFallback)
                    )
            }

            HStack(spacing: SBSLayout.paddingLarge) {
                Button(action: onShare) {
                    Label(prs.isEmpty ? "Share Workout" : "Share Your PR", systemImage: "square.and.arrow.up")
                }

                // The last set has no rest screen to undo it from
                if canUndo && !workoutState.finishedEarly {
                    Button(action: onUndo) {
                        Label("Undo Last Set", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            .font(SBSFonts.caption())
            .foregroundStyle(SBSColors.textSecondaryFallback)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
        .padding(.bottom, SBSLayout.paddingSmall)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
            Text(label)
                .font(SBSFonts.caption2())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SBSLayout.paddingSmall)
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
    var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showingFinishConfirm = false

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
                // Pinned: at the sheet's first height it would be below the fold of a
                // long list. Needs something to summarize, and X leaves an untouched session.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if workoutState.completedSetsCount > 0 {
                        Button {
                            showingFinishConfirm = true
                        } label: {
                            Text("Finish Workout")
                                .font(SBSFonts.button())
                                .foregroundStyle(SBSColors.accentFallback)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, SBSLayout.paddingSmall)
                        .background(SBSColors.surfaceFallback)
                    }
                }
                .onAppear {
                    // Scroll to current exercise
                    proxy.scrollTo(workoutState.currentExerciseIndex, anchor: .center)
                }
            }
            .alert("Finish Workout?", isPresented: $showingFinishConfirm) {
                Button("Keep Going", role: .cancel) {}
                Button("Finish Workout") {
                    onFinish?()
                }
            } message: {
                Text("You have \(workoutState.remainingSetsCount) \(workoutState.remainingSetsCount == 1 ? "set" : "sets") left. Lifts you don't finish log nothing and keep their weight.")
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
    var amrapResult: WorkoutAMRAPResult? = nil
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

#Preview {
    let appState = AppState()
    return WorkoutView(
        appState: appState,
        session: ActiveWorkoutSession(appState: appState, week: 1, day: 1)
    )
}

