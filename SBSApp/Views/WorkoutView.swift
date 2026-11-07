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
    @State private var showingSaveToFitnessPrompt = false
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
                // Progress header
                WorkoutProgressHeader(
                    progress: workoutState.progress,
                    exerciseName: workoutState.currentExercise?.name ?? "Workout",
                    setInfo: session.setInfoText,
                    isAccessory: workoutState.isCurrentExerciseAccessory,
                    heartRate: watchConnectivity.currentHeartRate
                )
                
                if workoutState.isWorkoutComplete {
                    WorkoutCompleteView(
                        workoutState: workoutState,
                        appState: appState,
                        week: week,
                        day: day,
                        onDone: { session.finishAndDismiss() },
                        onShare: { showingShareSheet = true }
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
                        }
                    )
                } else {
                    // Current set view
                    CurrentSetView(
                        workoutState: workoutState,
                        useMetric: appState.settings.useMetric,
                        barWeight: appState.settings.barWeight,
                        showPlateCalculator: appState.shouldShowPlateCalculator,
                        onComplete: session.handleSetComplete,
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
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // Cap Dynamic Type so the largest accessibility sizes can't break the
        // fixed-height number pad / rest-timer layouts on this screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .toolbar {
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
                    // If Apple Fitness is enabled and there's workout progress, offer to save
                    if storeManager.canAccess(.appleFitness) && appState.settings.healthKitEnabled && session.hasWorkoutProgress {
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
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Exit Workout?", isPresented: $showingExitConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Exit", role: .destructive) {
                session.exitWorkoutWithoutSaving()
            }
        } message: {
            Text("Results you've already logged are kept, but your place in this session will be lost.")
        }
        .alert("Save to Apple Fitness?", isPresented: $showingSaveToFitnessPrompt) {
            Button("Don't Save", role: .destructive) {
                session.exitWorkoutWithoutSaving()
            }
            Button("Save Workout") {
                session.exitWorkoutAndSaveToFitness()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save this workout to Apple Fitness? You've completed \(workoutState.completedSetsCount) sets.")
        }
        .sheet(isPresented: $session.showingRepInput) {
            RepOutInputSheet(
                liftName: workoutState.currentExercise?.name ?? "",
                target: session.currentRepTarget,
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
            .presentationDetents([.height(420), .medium])
            .presentationDragIndicator(.visible)
        }
        // item-driven: an isPresented cover reading separate optional state can render
        // empty, and a clear background makes that an invisible, undismissable screen.
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
        .sheet(isPresented: $session.showingLinearResult) {
            LinearResultSheet(
                exerciseName: session.pendingLinearExercise?.name ?? "",
                weight: session.pendingLinearExercise?.weight ?? 0,
                sets: session.pendingLinearExercise?.totalSets ?? 0,
                reps: session.pendingLinearExercise?.repsPerSet ?? 0,
                failedSets: session.pendingLinearExerciseFailedCount,
                increment: session.pendingLinearExercise?.linearInfo?.increment ?? 5,
                isDeloadPending: session.pendingLinearExercise?.linearInfo?.isDeloadPending ?? false,
                consecutiveFailures: session.pendingLinearExercise?.linearInfo?.consecutiveFailures ?? 0,
                useMetric: appState.settings.useMetric,
                onSuccess: {
                    session.handleLinearSuccess()
                    session.showingLinearResult = false
                    session.advanceLinearResultQueue()
                },
                onFailure: {
                    session.handleLinearFailure()
                    session.showingLinearResult = false
                    session.advanceLinearResultQueue()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            // Swiping this away would skip logging, so the lift wouldn't progress
            .interactiveDismissDisabled()
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
                    defaultSets: accessory.sets,
                    defaultReps: accessory.reps,
                    useMetric: appState.settings.useMetric,
                    roundingIncrement: appState.settings.roundingIncrement,
                    onSave: { weight, sets, reps in
                        // Update the accessory weight in the workout state
                        session.updateAccessoryWeight(weight: weight, sets: sets, reps: reps)
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
                        session.updateStandaloneAccessoryWeight(weight: weight, sets: sets, reps: reps)
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            session.workoutScreenDidAppear()
        }
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
            if structuredSet.isWeightOverridden { return "Adjusted" }
            return "\(Int(round(structuredSet.intensity * 100)))% TM"
        }
        // For volume and linear exercises, use the exercise-level intensity
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
    let appState = AppState()
    return WorkoutView(
        appState: appState,
        session: ActiveWorkoutSession(appState: appState, week: 1, day: 1)
    )
}

