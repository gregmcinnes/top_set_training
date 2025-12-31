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
    let weight: Double
    let totalSets: Int
    let repsPerSet: Int
    let repOutTarget: Int
    let isRepOutSet: (Int) -> Bool  // Given set number (1-indexed), is it a rep-out?
    let isAccessory: Bool  // True if this is an accessory exercise
    let isStructured: Bool  // True if this is a structured exercise
    let structuredSetInfo: [StructuredSetInfo]?  // Set details for structured exercises
    let isLinear: Bool  // True if this is a linear progression exercise
    let linearInfo: LinearExerciseInfo?  // Linear progression info
    
    /// For volume exercises, the last set is the rep-out
    static func fromVolumeItem(name: String, lift: String, weight: Double, sets: Int, repsPerSet: Int, repOutTarget: Int) -> WorkoutExercise {
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
            linearInfo: nil
        )
    }
    
    /// For accessory exercises (no rep-out)
    static func fromAccessory(name: String, sets: Int, reps: Int, lastLogWeight: Double?) -> WorkoutExercise {
        WorkoutExercise(
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
            linearInfo: nil
        )
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
            linearInfo: nil
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
            linearInfo: info
        )
    }
}

// MARK: - Superset Accessory Data

struct SupersetAccessoryData {
    let name: String
    let sets: Int
    let reps: Int
    let weight: Double?  // from lastLog if available
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
        timerEndDate = Date().addingTimeInterval(TimeInterval(duration))
        timerPausedRemaining = nil
    }
    
    func pauseTimer() {
        timerIsPaused = true
        timerIsRunning = false
        timerPausedRemaining = timerRemaining
        timerEndDate = nil
    }
    
    func resumeTimer() {
        timerIsPaused = false
        timerIsRunning = true
        // Restore end date based on remaining time
        if let pausedRemaining = timerPausedRemaining {
            timerEndDate = Date().addingTimeInterval(TimeInterval(pausedRemaining))
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
    @State private var prResult: AppState.LogRepsResult?
    @State private var showingPRCelebration = false
    @State private var pendingStructuredSetIndex: Int?  // For structured AMRAP logging
    @State private var showingExercisePicker = false
    @State private var showingLinearResult = false  // For linear progression success/fail dialog
    @State private var pendingLinearExercise: WorkoutExercise?  // Captured before advancing to next exercise
    @State private var showingPaywall = false  // For premium features
    @State private var showingShareSheet = false  // For workout summary share
    @State private var showingAccessoryWeightSheet = false  // For editing superset accessory weight
    @Environment(\.dismiss) private var dismiss
    
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
                    isAccessory: workoutState.isCurrentExerciseAccessory
                )
                
                if workoutState.isWorkoutComplete {
                    WorkoutCompleteView(
                        workoutState: workoutState,
                        appState: appState,
                        week: week,
                        day: day,
                        onDone: { dismiss() },
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
                        onTimerEnd: handleTimerEnd,
                        onUnlockTap: { showingPaywall = true },
                        onAccessoryWeightTap: { showingAccessoryWeightSheet = true }
                    )
                } else {
                    // Current set view
                    CurrentSetView(
                        workoutState: workoutState,
                        useMetric: appState.settings.useMetric,
                        barWeight: appState.settings.barWeight,
                        showPlateCalculator: appState.shouldShowPlateCalculator,
                        onComplete: handleSetComplete,
                        onUnlockTap: { showingPaywall = true }
                    )
                }
            }
            .sbsBackground()
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingExitConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingExercisePicker = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(
                workoutState: workoutState,
                useMetric: appState.settings.useMetric,
                onSelect: { index in
                    workoutState.jumpToExercise(index)
                    showingExercisePicker = false
                    stopTimer()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Exit Workout?", isPresented: $showingExitConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Exit", role: .destructive) {
                stopTimer()
                // End Live Activity when exiting workout
                LiveActivityManager.shared.endTimerSync()
                dismiss()
            }
        } message: {
            Text("Your progress for this session will be lost.")
        }
        .sheet(isPresented: $showingRepInput) {
            RepOutInputSheet(
                liftName: workoutState.currentExercise?.name ?? "",
                target: currentRepTarget,
                onSave: { reps, note in
                    if let lift = workoutState.currentExercise?.lift,
                       let exercise = workoutState.currentExercise {
                        // Check if this is an nSuns set
                        if let setIndex = pendingStructuredSetIndex {
                            // Log nSuns AMRAP
                            appState.logStructuredReps(lift: lift, week: week, day: day, setIndex: setIndex, reps: reps)
                            
                            // Track AMRAP result for share card
                            if exercise.isStructured, let sets = exercise.structuredSetInfo,
                               let setInfo = sets.first(where: { $0.setIndex == setIndex }) {
                                let weight = setInfo.weight
                                let e1rm = weight * (1.0 + Double(reps) / 30.0)
                                workoutState.amrapResults[lift] = (weight, reps, e1rm)
                            }
                            
                            pendingStructuredSetIndex = nil
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
                    onDismiss: {
                        showingPRCelebration = false
                        prResult = nil
                        // Note: completeSetAndStartTimer() is now called before showing the celebration
                        // to match the non-PR flow and prevent skipping sets
                    }
                )
                .background(Color.clear)
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
        .onAppear {
            setupWorkout()
            resumeTimerLoopIfNeeded()
        }
        .onDisappear {
            // Only invalidate the Timer object, don't reset timer state
            // This allows the timer to continue when navigating to other tabs
            invalidateTimerOnly()
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
        guard let plan = appState.dayPlan(week: week, day: day) else { return }
        
        var exercises: [WorkoutExercise] = []
        var accessories: [SupersetAccessoryData] = []
        var accessoryExercises: [WorkoutExercise] = []
        
        for item in plan {
            switch item {
            case let .volume(name, lift, weight, _, sets, repsPerSet, repOutTarget, _, _, _, _):
                exercises.append(
                    WorkoutExercise.fromVolumeItem(
                        name: name,
                        lift: lift,
                        weight: weight,
                        sets: sets,
                        repsPerSet: repsPerSet,
                        repOutTarget: repOutTarget
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
                    weight: lastLog?.weight
                ))
                // Also create workout exercise for standalone accessory mode
                accessoryExercises.append(
                    WorkoutExercise.fromAccessory(
                        name: name,
                        sets: sets,
                        reps: reps,
                        lastLogWeight: lastLog?.weight
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
    
    private func handleSetComplete() {
        guard let exercise = workoutState.currentExercise else { return }
        
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
        
        // Check if this is an nSuns AMRAP set
        if exercise.isStructured,
           let sets = exercise.structuredSetInfo,
           workoutState.currentSetNumber > 0 && workoutState.currentSetNumber <= sets.count {
            let currentSetInfo = sets[workoutState.currentSetNumber - 1]
            if currentSetInfo.isAMRAP {
                // Store the set index for logging
                pendingStructuredSetIndex = currentSetInfo.setIndex
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
        
        // Start rest timer
        workoutState.startTimer(duration: appState.settings.restTimerDuration)
        startTimerLoop()
    }
    
    private func startTimerLoop() {
        stopTimer()
        
        // Start Live Activity for lock screen / Dynamic Island (Pro only)
        let canAccessLiveActivity = storeManager.canAccess(.liveActivity)
        print("🔵 Timer started - canAccess(.liveActivity): \(canAccessLiveActivity), isPremium: \(storeManager.isPremium)")
        
        if canAccessLiveActivity, let exercise = workoutState.currentExercise {
            LiveActivityManager.shared.startTimer(
                exerciseName: exercise.name,
                duration: appState.settings.restTimerDuration,
                nextSetInfo: "Set \(workoutState.currentSetNumber) of \(exercise.totalSets)"
            )
        }
        
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
                
                if workoutState.timerRemaining <= 0 && workoutState.timerIsRunning {
                    self.handleTimerEnd()
                }
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
    
    /// Restarts the timer loop if a timer is still running after view reappears
    private func resumeTimerLoopIfNeeded() {
        // Recalculate remaining time from end date
        workoutState.recalculateTimerIfNeeded()
        
        // If timer is running and has time left, restart the loop
        if workoutState.timerIsRunning && workoutState.timerRemaining > 0 {
            startTimerLoop()
        } else if workoutState.timerIsRunning && workoutState.timerRemaining <= 0 {
            // Timer expired while view was away
            handleTimerEnd()
        }
    }
    
    private func handleTimerEnd() {
        workoutState.skipTimer()
        stopTimer()
        
        // End Live Activity
        LiveActivityManager.shared.endTimerSync()
        
        // Play haptics and chime
        playTimerEndFeedback()
    }
    
    private func playTimerEndFeedback() {
        // Strong haptic pattern - triple buzz
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        // Delay and buzz again for emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            generator.notificationOccurred(.warning)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            generator.notificationOccurred(.success)
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
        
        // Update the accessory in the workout state
        let updatedAccessory = SupersetAccessoryData(
            name: accessory.name,
            sets: sets,
            reps: reps,
            weight: weight
        )
        workoutState.supersetAccessories[workoutState.currentExerciseIndex] = updatedAccessory
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
                                .font(.system(size: 14))
                                .foregroundStyle(SBSColors.accentSecondaryFallback)
                        }
                        
                        Text(exerciseName)
                            .font(SBSFonts.title3())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .lineLimit(1)
                    }
                    
                    Text(setInfo)
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
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
    
    /// Intensity percentage for nSuns
    private var intensityText: String? {
        guard let structuredSet = currentStructuredSet else { return nil }
        return "\(Int(structuredSet.intensity * 100))% TM"
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
                                .font(.system(size: 16))
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
                        
                        // Weight (show even if 0 for bodyweight exercises)
                        Text(exercise.weight.formattedWeight(useMetric: useMetric))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                        
                        // Reps
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Text("\(exercise.repsPerSet)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text("reps")
                                .font(SBSFonts.title2())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
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
                        
                        // Weight for THIS set
                        Text(currentWeight.formattedWeight(useMetric: useMetric))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(isCurrentAMRAP ? SBSColors.warning : SBSColors.accentFallback)
                        
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
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(SBSColors.warning)
                                
                                Text("reps (AMRAP)")
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            } else {
                                Text("\(currentReps)")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
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
                    }
                } else if exercise.isLinear {
                    // Linear progression display
                    VStack(spacing: SBSLayout.paddingMedium) {
                        // Linear progression badge
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text("LINEAR PROGRESSION")
                                .font(SBSFonts.captionBold())
                        }
                        .foregroundStyle(SBSColors.accentFallback)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(SBSColors.accentFallback.opacity(0.15))
                        )
                        
                        // Weight
                        Text(exercise.weight.formattedWeight(useMetric: useMetric))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(SBSColors.accentFallback)
                        
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
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text("reps")
                                .font(SBSFonts.title2())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        
                        // Deload warning
                        if let info = exercise.linearInfo, info.isDeloadPending {
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                
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
                        // Weight
                        Text(exercise.weight.formattedWeight(useMetric: useMetric))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(SBSColors.accentFallback)
                        
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
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(SBSColors.success)
                                
                                Text("reps (AMRAP)")
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            } else {
                                Text("\(exercise.repsPerSet)")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                
                                Text("reps")
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                        }
                        
                        if workoutState.isCurrentSetRepOut {
                            Text("Last set - go for max reps!")
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
                            .font(.system(size: 24))
                        
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isCurrent ? .white : (setInfo.isAMRAP ? SBSColors.warning : SBSColors.textSecondaryFallback))
                    }
                }
            }
            
            // Weight label
            Text(setInfo.weight.formattedWeightShort(useMetric: useMetric))
                .font(.system(size: 8, weight: .medium))
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
                .font(.system(size: 9, weight: .semibold))
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
    var onUnlockTap: (() -> Void)?
    var onAccessoryWeightTap: (() -> Void)?
    
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
                        .font(.system(size: hasSuperset ? 36 : 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text(hasSuperset ? "SUPERSET" : "REST")
                        .font(SBSFonts.caption())
                        .foregroundStyle(hasSuperset ? SBSColors.accentSecondaryFallback : SBSColors.textSecondaryFallback)
                }
            }
            
            // Timer controls - smaller when superset is showing
            HStack(spacing: hasSuperset ? SBSLayout.paddingLarge : SBSLayout.paddingXLarge) {
                let buttonSize: CGFloat = hasSuperset ? 48 : 56
                
                // Pause/Resume
                Button {
                    if workoutState.timerIsPaused {
                        workoutState.resumeTimer()
                    } else {
                        workoutState.pauseTimer()
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
                
                // Skip
                Button {
                    onTimerEnd()
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
            }
            
            Spacer(minLength: hasSuperset ? 8 : 20)
            
            // Next set preview
            if let exercise = workoutState.currentExercise {
                NextSetPreview(
                    exerciseName: exercise.name,
                    weight: exercise.weight,
                    reps: workoutState.isCurrentSetRepOut ? "\(exercise.repOutTarget)+" : "\(exercise.repsPerSet)",
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
                                    .font(.system(size: compact ? 10 : 12))
                                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                            }
                            
                            Text(exerciseName)
                                .font(compact ? SBSFonts.body() : SBSFonts.bodyBold())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                                .lineLimit(1)
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
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                
                Text("SUPERSET")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.accentSecondaryFallback)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: compact ? 14 : 16))
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                        
                        Text(accessory.name)
                            .font(compact ? SBSFonts.bodyBold() : SBSFonts.title3())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .lineLimit(1)
                    }
                    
                    // Sets and reps info
                    Text("\(accessory.sets) × \(accessory.reps) reps")
                        .font(compact ? SBSFonts.caption() : SBSFonts.body())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
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
                                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    } else {
                        // No weight logged - show add indicator
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: compact ? 16 : 20))
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
                            .font(.system(size: 24, weight: .black, design: .rounded))
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
                                .font(.system(size: 16, weight: .semibold))
                            
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
            // Play celebration haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
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
                    .font(.system(size: 12))
                    .foregroundStyle(SBSColors.accentFallback)
                
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(SBSColors.textPrimaryFallback)
            }
            
            Text(label)
                .font(.system(size: 11))
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
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(workoutState.exercises.enumerated()), id: \.element.id) { index, exercise in
                        ExercisePickerRow(
                            exercise: exercise,
                            index: index,
                            isCurrent: index == workoutState.currentExerciseIndex,
                            completedSets: workoutState.completedSetsForExercise(at: index),
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
                                    .font(.system(size: 20))
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
            .navigationTitle("Exercises")
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

struct ExercisePickerRow: View {
    let exercise: WorkoutExercise
    let index: Int
    let isCurrent: Bool
    let completedSets: Int
    let useMetric: Bool
    let onTap: () -> Void
    
    private var isComplete: Bool {
        completedSets >= exercise.totalSets
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
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        if exercise.isAccessory {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(SBSColors.accentSecondaryFallback)
                        }
                        
                        if exercise.isStructured, let sets = exercise.structuredSetInfo {
                            // Show number of sets for nSuns exercises
                            Text("\(sets.count) sets")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        
                        Text(exercise.name)
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Text(exercise.weight.formattedWeightShort(useMetric: useMetric))
                            .font(SBSFonts.caption())
                            .foregroundStyle(exercise.isAccessory ? SBSColors.accentSecondaryFallback : SBSColors.accentFallback)
                        
                        Text("\(completedSets)/\(exercise.totalSets) sets")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                }
                
                Spacer()
                
                // Current indicator
                if isCurrent {
                    Text("CURRENT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SBSColors.accentFallback)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(SBSColors.accentFallback.opacity(0.15))
                        )
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
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
                                .font(.system(size: 14))
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
                                        .font(.system(size: 16))
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
                                    .font(.system(size: 14))
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
                                .font(.system(size: 20))
                            
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
                                .font(.system(size: 20))
                            
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

