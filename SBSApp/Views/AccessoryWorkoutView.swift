import SwiftUI
import AVFoundation
import ActivityKit

// MARK: - Accessory Workout State

@Observable
final class AccessoryWorkoutState {
    var accessories: [AccessoryItem] = []
    var currentAccessoryIndex: Int = 0
    var currentSetNumber: Int = 1
    var completedSets: [UUID: Set<Int>] = [:]  // accessory.id -> set of completed set numbers
    
    // Timer state
    var timerRemaining: Int = 0
    var timerDuration: Int = 120
    var timerIsRunning: Bool = false
    var timerIsPaused: Bool = false
    var showingTimer: Bool = false
    var timerEndDate: Date?  // Absolute end time for background persistence
    var timerPausedRemaining: Int?  // Remaining time when paused
    
    var currentAccessory: AccessoryItem? {
        guard currentAccessoryIndex < accessories.count else { return nil }
        return accessories[currentAccessoryIndex]
    }
    
    var isWorkoutComplete: Bool {
        guard let lastAccessory = accessories.last else { return true }
        guard let completedForLast = completedSets[lastAccessory.id] else { return false }
        return currentAccessoryIndex >= accessories.count - 1 &&
               completedForLast.count >= lastAccessory.sets
    }
    
    var currentSetCompletedCount: Int {
        guard let accessory = currentAccessory else { return 0 }
        return completedSets[accessory.id]?.count ?? 0
    }
    
    var progress: Double {
        let totalSets = accessories.reduce(0) { $0 + $1.sets }
        guard totalSets > 0 else { return 0 }
        let completedCount = completedSets.values.reduce(0) { $0 + $1.count }
        return Double(completedCount) / Double(totalSets)
    }
    
    func markSetComplete() {
        guard let accessory = currentAccessory else { return }
        
        if completedSets[accessory.id] == nil {
            completedSets[accessory.id] = []
        }
        completedSets[accessory.id]?.insert(currentSetNumber)
        
        // Advance to next set or exercise
        if currentSetNumber < accessory.sets {
            currentSetNumber += 1
        } else if currentAccessoryIndex < accessories.count - 1 {
            currentAccessoryIndex += 1
            currentSetNumber = 1
        }
    }
    
    func isSetCompleted(_ setNumber: Int) -> Bool {
        guard let accessory = currentAccessory else { return false }
        return completedSets[accessory.id]?.contains(setNumber) ?? false
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
    
    func selectAccessory(at index: Int) {
        guard index < accessories.count else { return }
        currentAccessoryIndex = index
        currentSetNumber = (completedSets[accessories[index].id]?.count ?? 0) + 1
        if currentSetNumber > accessories[index].sets {
            currentSetNumber = accessories[index].sets
        }
    }
}

// MARK: - Accessory Item

struct AccessoryItem: Identifiable {
    let id: UUID
    let name: String
    let sets: Int
    let reps: Int
    let lastLogWeight: Double?
    
    init(id: UUID = UUID(), name: String, sets: Int, reps: Int, lastLogWeight: Double?) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.lastLogWeight = lastLogWeight
    }
}

// MARK: - Accessory Workout View

struct AccessoryWorkoutView: View {
    @Bindable var appState: AppState
    let week: Int
    let day: Int
    
    @State private var workoutState = AccessoryWorkoutState()
    @State private var timer: Timer?
    @State private var showingExitConfirm = false
    @State private var showingWeightSheet = false
    @State private var editingAccessoryIndex: Int?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Progress header (only show for accessory workouts)
                if !workoutState.accessories.isEmpty {
                    AccessoryProgressHeader(
                        progress: workoutState.progress,
                        exerciseName: workoutState.currentAccessory?.name ?? "Accessories",
                        setInfo: setInfoText
                    )
                }
                
                if workoutState.accessories.isEmpty {
                    // No accessories - show standalone timer
                    StandaloneTimerView(
                        workoutState: workoutState,
                        timerDuration: appState.settings.restTimerDuration,
                        onStartTimer: {
                            workoutState.startTimer(duration: appState.settings.restTimerDuration)
                            startTimerLoop()
                        },
                        onTimerEnd: handleTimerEnd,
                        onPause: {
                            NotificationManager.shared.cancelRestTimerNotification()
                        },
                        onResume: {
                            if appState.settings.pushNotificationsEnabled {
                                NotificationManager.shared.scheduleRestTimerNotification(
                                    duration: workoutState.timerRemaining,
                                    exerciseName: "Rest",
                                    nextSetInfo: "Rest Timer"
                                )
                            }
                        }
                    )
                } else if workoutState.isWorkoutComplete {
                    AccessoryCompleteView(onDone: { finishAndDismiss() })
                } else if workoutState.showingTimer {
                    AccessoryTimerView(
                        workoutState: workoutState,
                        useMetric: appState.settings.useMetric,
                        onTimerEnd: handleTimerEnd,
                        onPause: {
                            NotificationManager.shared.cancelRestTimerNotification()
                        },
                        onResume: {
                            if appState.settings.pushNotificationsEnabled, let accessory = workoutState.currentAccessory {
                                NotificationManager.shared.scheduleRestTimerNotification(
                                    duration: workoutState.timerRemaining,
                                    exerciseName: accessory.name,
                                    nextSetInfo: "Set \(workoutState.currentSetNumber) of \(accessory.sets)"
                                )
                            }
                        }
                    )
                } else {
                    AccessorySetView(
                        workoutState: workoutState,
                        useMetric: appState.settings.useMetric,
                        onComplete: handleSetComplete,
                        onEditWeight: {
                            editingAccessoryIndex = workoutState.currentAccessoryIndex
                            showingWeightSheet = true
                        }
                    )
                }
            }
            .sbsBackground()
        }
        .navigationTitle(workoutState.accessories.isEmpty ? "Rest Timer" : "Accessories")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if workoutState.progress > 0 && !workoutState.accessories.isEmpty {
                        showingExitConfirm = true
                    } else {
                        // End any running timer
                        if workoutState.timerIsRunning {
                            stopTimer()
                            LiveActivityManager.shared.endTimerSync()
                        }
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
            }
            
            if !workoutState.accessories.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    // Accessory picker menu
                    Menu {
                        ForEach(Array(workoutState.accessories.enumerated()), id: \.element.id) { index, accessory in
                            Button {
                                workoutState.skipTimer()
                                stopTimer()
                                workoutState.selectAccessory(at: index)
                            } label: {
                                let completed = workoutState.completedSets[accessory.id]?.count ?? 0
                                HStack {
                                    Text(accessory.name)
                                    if completed == accessory.sets {
                                        Image(systemName: "checkmark.circle.fill")
                                    } else if completed > 0 {
                                        Text("\(completed)/\(accessory.sets)")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SBSColors.accentFallback)
                    }
                }
            }
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
            Text("Your accessory workout progress will not be saved.")
        }
        .sheet(isPresented: $showingWeightSheet) {
            if let index = editingAccessoryIndex, index < workoutState.accessories.count {
                let accessory = workoutState.accessories[index]
                AccessoryWeightSheet(
                    accessoryName: accessory.name,
                    currentWeight: accessory.lastLogWeight,
                    defaultSets: accessory.sets,
                    defaultReps: accessory.reps,
                    useMetric: appState.settings.useMetric,
                    roundingIncrement: appState.settings.roundingIncrement,
                    onSave: { weight, sets, reps in
                        appState.logAccessory(name: accessory.name, weight: weight, sets: sets, reps: reps)
                        // Update the local accessory with new weight (preserving ID for completed sets tracking)
                        workoutState.accessories[index] = AccessoryItem(
                            id: accessory.id,
                            name: accessory.name,
                            sets: accessory.sets,
                            reps: accessory.reps,
                            lastLogWeight: weight
                        )
                        showingWeightSheet = false
                    },
                    onCancel: {
                        showingWeightSheet = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
        .onAppear {
            setupAccessories()
            resumeTimerLoopIfNeeded()
            startHealthKitWorkout()
        }
        .onDisappear {
            // Only invalidate the Timer object, don't reset timer state
            // This allows the timer to continue when navigating to other tabs
            invalidateTimerOnly()
        }
    }
    
    private var setInfoText: String {
        guard let accessory = workoutState.currentAccessory else { return "" }
        return "Set \(workoutState.currentSetNumber) of \(accessory.sets)"
    }
    
    // MARK: - HealthKit Integration
    
    private func startHealthKitWorkout() {
        // Apple Fitness is a premium feature
        guard StoreManager.shared.canAccess(.appleFitness) else { return }
        guard appState.settings.healthKitEnabled else { return }
        
        // Only start if there are accessories to do
        guard !workoutState.accessories.isEmpty else { return }
        
        let workoutName = "Accessory Workout - Day \(day)"
        Task {
            do {
                try await HealthKitManager.shared.startWorkout(name: workoutName)
            } catch {
                Logger.error("Failed to start HealthKit workout: \(error)", category: .healthKit)
            }
        }
    }
    
    private func finishAndDismiss() {
        // End HealthKit workout if active (premium feature)
        if StoreManager.shared.canAccess(.appleFitness) && appState.settings.healthKitEnabled && HealthKitManager.shared.isWorkoutActive {
            // Calculate workout stats for HealthKit
            let stats = calculateAccessoryStats()
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
        
        // Record workout completion for review request tracking
        ReviewRequestManager.shared.recordWorkoutCompleted()
        
        dismiss()
    }
    
    /// Calculate total volume, sets, and reps from accessories
    private func calculateAccessoryStats() -> (volume: Double, sets: Int, reps: Int) {
        var totalVolume: Double = 0
        var totalSets = 0
        var totalReps = 0
        
        for accessory in workoutState.accessories {
            guard let completedSetNumbers = workoutState.completedSets[accessory.id] else { continue }
            let setsCompleted = completedSetNumbers.count
            totalSets += setsCompleted
            
            let repsCompleted = setsCompleted * accessory.reps
            totalReps += repsCompleted
            
            // Use last logged weight if available for volume calculation
            if let weight = accessory.lastLogWeight, weight > 0 {
                totalVolume += weight * Double(repsCompleted)
            }
        }
        
        return (totalVolume, totalSets, totalReps)
    }
    
    private func setupAccessories() {
        guard let plan = appState.dayPlan(week: week, day: day) else { return }
        
        var accessories: [AccessoryItem] = []
        
        for item in plan {
            if case let .accessory(name, sets, reps, lastLog) = item {
                accessories.append(AccessoryItem(
                    name: name,
                    sets: sets,
                    reps: reps,
                    lastLogWeight: lastLog?.weight
                ))
            }
        }
        
        workoutState.accessories = accessories
        workoutState.timerDuration = appState.settings.restTimerDuration
    }
    
    private func handleSetComplete() {
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
        if StoreManager.shared.canAccess(.liveActivity) {
            if let accessory = workoutState.currentAccessory {
                LiveActivityManager.shared.startTimer(
                    exerciseName: accessory.name,
                    duration: appState.settings.restTimerDuration,
                    nextSetInfo: "Set \(workoutState.currentSetNumber) of \(accessory.sets)"
                )
            } else {
                // Standalone timer mode
                LiveActivityManager.shared.startTimer(
                    exerciseName: "Rest",
                    duration: workoutState.timerDuration,
                    nextSetInfo: "Rest Timer"
                )
            }
        }
        
        // Schedule push notification for background alert
        if appState.settings.pushNotificationsEnabled {
            if let accessory = workoutState.currentAccessory {
                NotificationManager.shared.scheduleRestTimerNotification(
                    duration: appState.settings.restTimerDuration,
                    exerciseName: accessory.name,
                    nextSetInfo: "Set \(workoutState.currentSetNumber) of \(accessory.sets)"
                )
            } else {
                NotificationManager.shared.scheduleRestTimerNotification(
                    duration: workoutState.timerDuration,
                    exerciseName: "Rest",
                    nextSetInfo: "Rest Timer"
                )
            }
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
        
        // Cancel push notification (app is in foreground, no need for notification)
        NotificationManager.shared.cancelRestTimerNotification()
        
        // Play haptics and chime
        playTimerEndFeedback()
    }
    
    private func playTimerEndFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            generator.notificationOccurred(.warning)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            generator.notificationOccurred(.success)
        }
        
        // Only play sound if user has sound notifications enabled
        // Using AudioServicesPlayAlertSound to respect silent mode (vibrates only when silenced)
        if appState.settings.playSoundNotifications {
            AudioServicesPlayAlertSound(1322)  // "Anticipate" - respects silent switch
        }
    }
}

// MARK: - Accessory Progress Header

struct AccessoryProgressHeader: View {
    let progress: Double
    let exerciseName: String
    let setInfo: String
    
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
                                colors: [SBSColors.accentSecondaryFallback, SBSColors.success],
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
                    Text(exerciseName)
                        .font(SBSFonts.title3())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text(setInfo)
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.accentSecondaryFallback)
            }
            .padding(.horizontal)
            .padding(.bottom, SBSLayout.paddingSmall)
        }
        .background(SBSColors.surfaceFallback)
    }
}

// MARK: - Accessory Set View

struct AccessorySetView: View {
    let workoutState: AccessoryWorkoutState
    let useMetric: Bool
    let onComplete: () -> Void
    let onEditWeight: () -> Void
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingLarge) {
            Spacer()
            
            if let accessory = workoutState.currentAccessory {
                // Set indicators
                AccessorySetIndicatorStrip(
                    totalSets: accessory.sets,
                    currentSet: workoutState.currentSetNumber,
                    completedSets: workoutState.completedSets[accessory.id] ?? []
                )
                
                // Main display
                VStack(spacing: SBSLayout.paddingMedium) {
                    // Exercise name with icon
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                        
                        Text(accessory.name)
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                    }
                    
                    // Weight display - tappable to edit
                    Button(action: onEditWeight) {
                        if let weight = accessory.lastLogWeight {
                            // Show logged weight (including 0 for bodyweight exercises)
                            VStack(spacing: 4) {
                                Text(weight.formattedWeight(useMetric: useMetric))
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12))
                                    Text("Tap to edit")
                                        .font(SBSFonts.caption())
                                }
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            }
                        } else {
                            // Show add weight prompt
                            VStack(spacing: SBSLayout.paddingSmall) {
                                ZStack {
                                    Circle()
                                        .fill(SBSColors.surfaceFallback)
                                        .frame(width: 64, height: 64)
                                    
                                    Image(systemName: "plus")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                                }
                                
                                Text("Add Weight")
                                    .font(SBSFonts.bodyBold())
                                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Reps
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Text("\(accessory.reps)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("reps")
                            .font(SBSFonts.title2())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                }
                
                Spacer()
                
                // Complete button
                Button(action: onComplete) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                        
                        Text("Complete Set")
                            .font(SBSFonts.button())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingMedium + 4)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                            .fill(SBSColors.accentSecondaryFallback)
                    )
                }
                .padding(.horizontal, SBSLayout.paddingLarge)
                .padding(.bottom, SBSLayout.paddingXLarge)
            }
        }
    }
}

// MARK: - Accessory Set Indicator Strip

struct AccessorySetIndicatorStrip: View {
    let totalSets: Int
    let currentSet: Int
    let completedSets: Set<Int>
    
    var body: some View {
        HStack(spacing: SBSLayout.paddingSmall) {
            ForEach(1...totalSets, id: \.self) { setNumber in
                AccessorySetIndicator(
                    setNumber: setNumber,
                    isCompleted: completedSets.contains(setNumber),
                    isCurrent: setNumber == currentSet
                )
            }
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
    }
}

struct AccessorySetIndicator: View {
    let setNumber: Int
    let isCompleted: Bool
    let isCurrent: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 44, height: 44)
            
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(setNumber)")
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(isCurrent ? .white : SBSColors.textSecondaryFallback)
            }
        }
    }
    
    private var backgroundColor: Color {
        if isCompleted {
            return SBSColors.success
        } else if isCurrent {
            return SBSColors.accentSecondaryFallback
        } else {
            return SBSColors.surfaceFallback
        }
    }
}

// MARK: - Accessory Timer View

struct AccessoryTimerView: View {
    @Bindable var workoutState: AccessoryWorkoutState
    let useMetric: Bool
    let onTimerEnd: () -> Void
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingLarge) {
            Spacer()
            
            // Timer circle
            ZStack {
                // Background circle
                Circle()
                    .stroke(SBSColors.surfaceFallback, lineWidth: 12)
                    .frame(width: 200, height: 200)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: timerProgress)
                    .stroke(
                        timerColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timerProgress)
                
                // Timer text
                VStack(spacing: 4) {
                    Text(timerText)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("REST")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
            }
            
            // Timer controls
            HStack(spacing: SBSLayout.paddingXLarge) {
                // Pause/Resume
                Button {
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
                        .font(.system(size: 24))
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                        .frame(width: 56, height: 56)
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
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(SBSColors.accentSecondaryFallback)
                        )
                }
            }
            
            Spacer()
            
            // Next set preview
            if let accessory = workoutState.currentAccessory {
                AccessoryNextSetPreview(
                    accessoryName: accessory.name,
                    weight: accessory.lastLogWeight,
                    reps: accessory.reps,
                    setNumber: workoutState.currentSetNumber,
                    totalSets: accessory.sets,
                    useMetric: useMetric
                )
            }
        }
        .onChange(of: workoutState.timerRemaining) { oldValue, newValue in
            // Automatically end timer when it reaches 0
            if oldValue > 0 && newValue <= 0 && workoutState.timerIsRunning {
                onTimerEnd()
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
            return SBSColors.accentSecondaryFallback
        } else {
            return SBSColors.accentSecondaryFallback.opacity(0.7)
        }
    }
    
    private var timerText: String {
        let minutes = workoutState.timerRemaining / 60
        let seconds = workoutState.timerRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Accessory Next Set Preview

struct AccessoryNextSetPreview: View {
    let accessoryName: String
    let weight: Double?
    let reps: Int
    let setNumber: Int
    let totalSets: Int
    let useMetric: Bool
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            Text("NEXT UP")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(accessoryName)
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Set \(setNumber) of \(totalSets)")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
                HStack(spacing: SBSLayout.paddingSmall) {
                    if let w = weight, w > 0 {
                        Text(w.formattedWeightShort(useMetric: useMetric))
                            .font(SBSFonts.weight())
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                        
                        Text("×")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    Text("\(reps)")
                        .font(SBSFonts.weight())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(SBSColors.surfaceFallback)
            )
        }
        .padding(.horizontal)
        .padding(.bottom, SBSLayout.paddingLarge)
    }
}

// MARK: - Accessory Complete View

struct AccessoryCompleteView: View {
    let onDone: () -> Void
    
    @State private var confettiScale: CGFloat = 0.5
    @State private var confettiOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingXLarge) {
            Spacer()
            
            // Celebration icon
            ZStack {
                Circle()
                    .fill(SBSColors.success.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .scaleEffect(confettiScale)
                    .opacity(confettiOpacity)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(SBSColors.success)
            }
            
            VStack(spacing: SBSLayout.paddingSmall) {
                Text("Accessories Done!")
                    .font(SBSFonts.largeTitle())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Great work on those accessories!")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button(action: onDone) {
                Text("Done")
                    .font(SBSFonts.button())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingMedium + 4)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                            .fill(SBSColors.success)
                    )
            }
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.bottom, SBSLayout.paddingXLarge)
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
        }
    }
}

// MARK: - Accessory Weight Sheet

struct AccessoryWeightSheet: View {
    let accessoryName: String
    let currentWeight: Double?
    let defaultSets: Int
    let defaultReps: Int
    let useMetric: Bool
    let roundingIncrement: Double
    let onSave: (Double, Int, Int) -> Void
    let onCancel: () -> Void
    
    @State private var weightText: String = ""
    @State private var sets: Int = 4
    @State private var reps: Int = 10
    
    private var weight: Double? {
        Double(weightText)
    }
    
    private var canSave: Bool {
        weight != nil && weight! >= 0
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SBSLayout.paddingLarge) {
                    // Header
                    VStack(spacing: 4) {
                        Text(accessoryName)
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("Set your weight for this accessory")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .padding(.top)
                    
                    // Weight input
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Text("Weight")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                        
                        HStack {
                            TextField("0", text: $weightText)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                        .fill(SBSColors.surfaceFallback)
                                )
                            
                            Text(useMetric ? "kg" : "lbs")
                                .font(SBSFonts.title2())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                                .frame(width: 50)
                        }
                        
                        // Quick weight buttons (if there's a current weight)
                        if let lastWeight = currentWeight, lastWeight > 0 {
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Button {
                                    weightText = String(format: "%.1f", lastWeight - roundingIncrement)
                                } label: {
                                    Text("-\(roundingIncrement.formattedWeightShort(useMetric: useMetric))")
                                        .font(SBSFonts.captionBold())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, SBSLayout.paddingSmall)
                                        .background(
                                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                                                .fill(SBSColors.surfaceFallback)
                                        )
                                }
                                
                                Button {
                                    weightText = String(format: "%.1f", lastWeight)
                                } label: {
                                    Text("Same")
                                        .font(SBSFonts.captionBold())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, SBSLayout.paddingSmall)
                                        .background(
                                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                                                .fill(SBSColors.surfaceFallback)
                                        )
                                }
                                
                                Button {
                                    weightText = String(format: "%.1f", lastWeight + roundingIncrement)
                                } label: {
                                    Text("+\(roundingIncrement.formattedWeightShort(useMetric: useMetric))")
                                        .font(SBSFonts.captionBold())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, SBSLayout.paddingSmall)
                                        .background(
                                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                                                .fill(SBSColors.surfaceFallback)
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                    
                    // Save button
                    Button {
                        if let w = weight {
                            onSave(w, sets, reps)
                        }
                    } label: {
                        Text("Save")
                            .font(SBSFonts.button())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.paddingMedium + 4)
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                    .fill(canSave ? SBSColors.accentSecondaryFallback : SBSColors.surfaceFallback)
                            )
                    }
                    .disabled(!canSave)
                    .padding(.horizontal)
                    .padding(.bottom, SBSLayout.paddingLarge)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                }
            }
        }
        .onAppear {
            sets = defaultSets
            reps = defaultReps
            if let w = currentWeight, w > 0 {
                weightText = String(format: "%.1f", w)
            }
        }
    }
}

// MARK: - Standalone Timer View

struct StandaloneTimerView: View {
    @Bindable var workoutState: AccessoryWorkoutState
    let timerDuration: Int
    let onStartTimer: () -> Void
    let onTimerEnd: () -> Void
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingLarge) {
            Spacer()
            
            if workoutState.showingTimer {
                // Timer is running - show timer interface
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(SBSColors.surfaceFallback, lineWidth: 12)
                        .frame(width: 200, height: 200)
                    
                    // Progress circle
                    Circle()
                        .trim(from: 0, to: timerProgress)
                        .stroke(
                            timerColor,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: timerProgress)
                    
                    // Timer text
                    VStack(spacing: 4) {
                        Text(timerText)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("REST")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                }
                
                // Timer controls
                HStack(spacing: SBSLayout.paddingXLarge) {
                    // Pause/Resume
                    Button {
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
                            .font(.system(size: 24))
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(SBSColors.surfaceFallback)
                            )
                    }
                    
                    // Skip/Reset
                    Button {
                        onTimerEnd()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(SBSColors.accentSecondaryFallback)
                            )
                    }
                }
            } else {
                // Timer not running - show start button
                VStack(spacing: SBSLayout.paddingLarge) {
                    // Timer icon
                    ZStack {
                        Circle()
                            .fill(SBSColors.accentSecondaryFallback.opacity(0.15))
                            .frame(width: 140, height: 140)
                        
                        Image(systemName: "timer")
                            .font(.system(size: 56, weight: .medium))
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                    }
                    
                    VStack(spacing: SBSLayout.paddingSmall) {
                        Text("Rest Timer")
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("Track rest between your sets")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .multilineTextAlignment(.center)
                        
                        Text("\(timerDuration / 60):\(String(format: "%02d", timerDuration % 60))")
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .padding(.top, SBSLayout.paddingSmall)
                    }
                }
            }
            
            Spacer()
            
            // Start Timer button (only show when timer not running)
            if !workoutState.showingTimer {
                Button(action: onStartTimer) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                        
                        Text("Start Timer")
                            .font(SBSFonts.button())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingMedium + 4)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                            .fill(SBSColors.accentSecondaryFallback)
                    )
                }
                .padding(.horizontal, SBSLayout.paddingLarge)
                .padding(.bottom, SBSLayout.paddingXLarge)
            } else {
                // Restart button when timer is running
                Button(action: onStartTimer) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                        
                        Text("Restart Timer")
                            .font(SBSFonts.button())
                    }
                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingMedium + 4)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                            .strokeBorder(SBSColors.accentSecondaryFallback, lineWidth: 2)
                    )
                }
                .padding(.horizontal, SBSLayout.paddingLarge)
                .padding(.bottom, SBSLayout.paddingXLarge)
            }
        }
        .onChange(of: workoutState.timerRemaining) { oldValue, newValue in
            // Automatically end timer when it reaches 0
            if oldValue > 0 && newValue <= 0 && workoutState.timerIsRunning {
                onTimerEnd()
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
            return SBSColors.accentSecondaryFallback
        } else {
            return SBSColors.accentSecondaryFallback.opacity(0.7)
        }
    }
    
    private var timerText: String {
        let minutes = workoutState.timerRemaining / 60
        let seconds = workoutState.timerRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        AccessoryWorkoutView(
            appState: AppState(),
            week: 1,
            day: 1
        )
    }
}

