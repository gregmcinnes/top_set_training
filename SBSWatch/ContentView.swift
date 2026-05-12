import SwiftUI
import HealthKit

struct ContentView: View {
    @EnvironmentObject var workoutManager: WatchWorkoutManager
    @EnvironmentObject var sessionManager: WatchSessionManager
    
    var body: some View {
        NavigationStack {
            if workoutManager.isWorkoutActive {
                // Workout in progress - show status
                WorkoutActiveView()
            } else if sessionManager.isWorkoutActive {
                // Workout starting from iPhone - show connecting state
                WorkoutConnectingView()
            } else {
                // No workout - show idle state
                IdleView()
            }
        }
    }
}

// MARK: - Idle View

struct IdleView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                
                Text("Top Set")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Start a workout on your iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

// MARK: - Workout Connecting View

struct WorkoutConnectingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding(.bottom, 8)
                
                Text("Starting Workout")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Connecting to iPhone...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

// MARK: - Workout Active View

struct WorkoutActiveView: View {
    @EnvironmentObject var workoutManager: WatchWorkoutManager
    @EnvironmentObject var sessionManager: WatchSessionManager
    
    private var state: WatchWorkoutStateData {
        sessionManager.workoutState
    }
    
    private var hasWorkoutData: Bool {
        !state.exerciseName.isEmpty && state.totalSets > 0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if state.isRestTimerActive {
                    // Rest Timer View
                    RestTimerView(state: state)
                } else if hasWorkoutData {
                    // Current Exercise View
                    CurrentExerciseView(state: state, heartRate: workoutManager.currentHeartRate)
                } else {
                    // Fallback - basic workout tracking (no state from iPhone yet)
                    BasicWorkoutView(workoutManager: workoutManager)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Rest Timer View

struct RestTimerView: View {
    let state: WatchWorkoutStateData
    
    var body: some View {
        VStack(spacing: 8) {
            // Rest label
            Text("REST")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
            
            // Timer countdown
            Text(state.formattedTimerRemaining)
                .font(.system(size: 52, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
            
            // Progress ring
            ZStack {
                Circle()
                    .stroke(.gray.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: state.timerProgress)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: state.timerProgress)
            }
            .frame(width: 60, height: 60)
            
            // Next set info
            if let nextInfo = state.nextSetInfo {
                Text(nextInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("\(state.exerciseName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Current Exercise View

struct CurrentExerciseView: View {
    let state: WatchWorkoutStateData
    let heartRate: Double?
    @EnvironmentObject var sessionManager: WatchSessionManager
    @State private var showingRepPicker = false
    
    var body: some View {
        VStack(spacing: 6) {
            // Exercise name
            Text(state.exerciseName)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            // Set info
            HStack(spacing: 4) {
                Text("Set \(state.currentSet)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("of \(state.totalSets)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            // Weight and reps
            VStack(spacing: 2) {
                Text(state.formattedWeight)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .monospacedDigit()
                
                HStack(spacing: 2) {
                    if state.isAMRAPSet {
                        Text("\(state.targetReps)+")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                        Text("reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(state.targetReps)")
                            .font(.callout)
                            .fontWeight(.semibold)
                        Text("reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Complete Set Button - different behavior for AMRAP vs normal sets
            if state.isAMRAPSet {
                // AMRAP set - show rep picker
                Button(action: {
                    showingRepPicker = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "number.circle.fill")
                            .font(.caption)
                        Text("Log Reps")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                // Normal set - complete directly
                Button(action: {
                    sessionManager.sendSetCompleted(reps: nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Done")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            
            Divider()
                .padding(.vertical, 2)
            
            // Heart rate
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                if let hr = heartRate {
                    Text("\(Int(hr))")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                } else {
                    Text("--")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                Text("BPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        .sheet(isPresented: $showingRepPicker) {
            RepPickerView(
                targetReps: state.targetReps,
                exerciseName: state.exerciseName
            ) { reps in
                sessionManager.sendSetCompleted(reps: reps)
                showingRepPicker = false
            }
        }
    }
}

// MARK: - Rep Picker View

struct RepPickerView: View {
    let targetReps: Int
    let exerciseName: String
    let onComplete: (Int) -> Void
    
    @State private var selectedRepsDouble: Double
    @FocusState private var isFocused: Bool
    
    private var selectedReps: Int {
        Int(selectedRepsDouble.rounded())
    }
    
    init(targetReps: Int, exerciseName: String, onComplete: @escaping (Int) -> Void) {
        self.targetReps = targetReps
        self.exerciseName = exerciseName
        self.onComplete = onComplete
        // Start with target reps as default
        _selectedRepsDouble = State(initialValue: Double(targetReps))
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Reps Completed")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Rep counter with Digital Crown support
            Text("\(selectedReps)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .focusable()
                .focused($isFocused)
                .digitalCrownRotation(
                    $selectedRepsDouble,
                    from: 1.0,
                    through: 30.0,
                    by: 1.0,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
            
            // +/- buttons for manual adjustment
            HStack(spacing: 20) {
                Button(action: {
                    if selectedRepsDouble > 1 {
                        selectedRepsDouble -= 1
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if selectedRepsDouble < 30 {
                        selectedRepsDouble += 1
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
            
            Text("Use crown to adjust")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            // Confirm button
            Button(action: {
                onComplete(selectedReps)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.caption)
                    Text("Log \(selectedReps) reps")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green)
                )
            }
            .buttonStyle(.plain)
        }
        .padding()
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Basic Workout View (Fallback)

struct BasicWorkoutView: View {
    @ObservedObject var workoutManager: WatchWorkoutManager
    
    var body: some View {
            VStack(spacing: 12) {
                // Workout indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Workout Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Duration
                Text(workoutManager.formattedDuration)
                    .font(.system(size: 40, weight: .medium, design: .rounded))
                    .monospacedDigit()
                
                // Heart rate
                if let heartRate = workoutManager.currentHeartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("\(Int(heartRate))")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("BPM")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.5))
                        Text("--")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text("BPM")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text("Tracking on iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
    }
}

#Preview("Idle") {
    ContentView()
        .environmentObject(WatchWorkoutManager())
        .environmentObject(WatchSessionManager.shared)
}

#Preview("Workout Active") {
    let manager = WatchWorkoutManager()
    let session = WatchSessionManager.shared
    session.workoutState = WatchWorkoutStateData(
        exerciseName: "Bench Press",
        currentSet: 2,
        totalSets: 5,
        weight: 185,
        targetReps: 5,
        isRestTimerActive: false,
        restTimerRemaining: 0,
        restTimerDuration: 120,
        useMetric: false,
        nextSetInfo: nil,
        isRepOutSet: false
    )
    return WorkoutActiveView()
        .environmentObject(manager)
        .environmentObject(session)
}

#Preview("Rest Timer") {
    let manager = WatchWorkoutManager()
    let session = WatchSessionManager.shared
    session.workoutState = WatchWorkoutStateData(
        exerciseName: "Bench Press",
        currentSet: 3,
        totalSets: 5,
        weight: 185,
        targetReps: 5,
        isRestTimerActive: true,
        restTimerRemaining: 87,
        restTimerDuration: 120,
        useMetric: false,
        nextSetInfo: "Next: Set 3 of 5",
        isRepOutSet: false
    )
    return WorkoutActiveView()
        .environmentObject(manager)
        .environmentObject(session)
}

#Preview("AMRAP Set") {
    let manager = WatchWorkoutManager()
    let session = WatchSessionManager.shared
    session.workoutState = WatchWorkoutStateData(
        exerciseName: "Squat",
        currentSet: 5,
        totalSets: 5,
        weight: 225,
        targetReps: 5,
        isRestTimerActive: false,
        restTimerRemaining: 0,
        restTimerDuration: 120,
        useMetric: false,
        nextSetInfo: nil,
        isRepOutSet: true,
        isAMRAPSet: true
    )
    return WorkoutActiveView()
        .environmentObject(manager)
        .environmentObject(session)
}

#Preview("Rep Picker") {
    RepPickerView(targetReps: 5, exerciseName: "Squat") { reps in
        print("Logged \(reps) reps")
    }
}
