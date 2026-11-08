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
            VStack(spacing: WatchLayout.space3) {
                Image("TopSetMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48)
                    .foregroundStyle(Color.ink)
                    .accessibilityHidden(true)

                Text("Top Set")
                    .font(.headline)
                    .foregroundStyle(Color.ink)

                Text("Start a workout on your iPhone")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WatchLayout.space2)
        }
    }
}

// MARK: - Workout Connecting View

struct WorkoutConnectingView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        ScrollView {
            VStack(spacing: WatchLayout.space3) {
                ProgressView()
                    .tint(Color.ink)

                WatchEyebrow("Starting workout")
                    .foregroundStyle(Color.ink)

                Text("Connecting to iPhone…")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)

                // Way out if the start never completes (phone gone, session failed).
                Button {
                    sessionManager.endWorkoutFromWatch(save: false)
                } label: {
                    WatchButtonLabel("Cancel")
                }
                .buttonStyle(WatchSecondaryButtonStyle())
                .padding(.top, WatchLayout.space1)
            }
            .padding(.vertical, WatchLayout.space2)
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
            VStack(spacing: WatchLayout.space2) {
                if workoutManager.healthKitError {
                    // HealthKit auth failed — workout still tracks, just no HR / save.
                    HStack(spacing: WatchLayout.space1) {
                        Image(systemName: "heart.slash")
                            .accessibilityHidden(true)
                        Text("Allow Health access on your watch")
                            .multilineTextAlignment(.leading)
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, WatchLayout.space2)
                    .padding(.vertical, WatchLayout.space1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: WatchLayout.radiusSm)
                            .strokeBorder(Color.hairline, lineWidth: WatchLayout.hairline)
                    )
                    .accessibilityElement(children: .combine)
                }

                if state.isRestTimerActive {
                    RestTimerView(state: state)
                } else if hasWorkoutData {
                    CurrentExerciseView(state: state, heartRate: workoutManager.currentHeartRate)
                } else {
                    // Fallback - basic workout tracking (no state from iPhone yet)
                    BasicWorkoutView(workoutManager: workoutManager)
                }

                EndWorkoutButton()
                    .padding(.top, WatchLayout.space2)
            }
        }
    }
}

// MARK: - End Workout Button

/// Ends the workout on the Watch. Normally the phone does this; without it, a
/// session outlives a killed or out-of-range phone with no way to stop it.
struct EndWorkoutButton: View {
    @EnvironmentObject var workoutManager: WatchWorkoutManager
    @EnvironmentObject var sessionManager: WatchSessionManager
    @State private var showingConfirmation = false

    var body: some View {
        // Secondary, not red: the Watch is ink, orange and chalk only. The
        // confirmation dialog carries the destructive role.
        Button {
            showingConfirmation = true
        } label: {
            WatchButtonLabel("End workout")
        }
        .buttonStyle(WatchSecondaryButtonStyle())
        .confirmationDialog("End workout on Watch?", isPresented: $showingConfirmation) {
            if workoutManager.isSavingToHealthKit {
                Button("Save Workout") {
                    sessionManager.endWorkoutFromWatch(save: true)
                }
                Button("Discard", role: .destructive) {
                    sessionManager.endWorkoutFromWatch(save: false)
                }
            } else {
                Button("End Workout", role: .destructive) {
                    sessionManager.endWorkoutFromWatch(save: false)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Rest Timer View

struct RestTimerView: View {
    let state: WatchWorkoutStateData

    var body: some View {
        // Drive the countdown locally so it keeps ticking even while the phone is
        // backgrounded/locked. When paused, hold a static value.
        if state.isPaused {
            content(at: Date())
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                content(at: context.date)
            }
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        VStack(spacing: WatchLayout.space2) {
            // Status: glyph plus word. Orange as text is orange-text.
            WatchEyebrow(state.isPaused ? "Paused" : "Rest",
                         systemImage: state.isPaused ? "pause.fill" : "timer")
                .foregroundStyle(state.isPaused ? Color.inkSecondary : Color.orangeText)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                WatchHeroNumber(
                    value: state.formattedTimerRemaining(at: now),
                    color: state.isPaused ? .inkSecondary : .ink,
                    baseSize: 56
                )
                .accessibilityLabel("\(state.remaining(at: now)) seconds of rest left")

                Text("of \(state.formattedTimerDuration)")
                    .font(WatchFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WatchProgressBar(progress: state.timerProgress(at: now))

            Text(state.nextSetInfo ?? state.exerciseName)
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, WatchLayout.space1)
    }
}

// MARK: - Current Exercise View

struct CurrentExerciseView: View {
    let state: WatchWorkoutStateData
    let heartRate: Double?
    @EnvironmentObject var sessionManager: WatchSessionManager
    @State private var showingRepPicker = false

    private var setLabel: String {
        let base = "Set \(state.currentSet) of \(state.totalSets)"
        return state.isAMRAPSet ? "\(base) · AMRAP" : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WatchLayout.space1) {
            WatchEyebrow(setLabel)
                .foregroundStyle(Color.inkSecondary)

            Text(state.exerciseName)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .lineLimit(2)

            // The working weight is the hero.
            WatchHeroNumber(value: state.weightNumber, unit: state.weightUnit)
                .accessibilityLabel(state.formattedWeight)

            Text(state.isAMRAPSet ? "× \(state.targetReps)+" : "× \(state.targetReps)")
                .font(WatchFonts.number())
                .foregroundStyle(Color.ink)
                .accessibilityLabel(state.isAMRAPSet
                                    ? "\(state.targetReps) or more reps"
                                    : "\(state.targetReps) reps")

            if state.isAMRAPSet {
                Button {
                    showingRepPicker = true
                } label: {
                    WatchButtonLabel("Log reps", systemImage: "number")
                }
                .buttonStyle(WatchPrimaryButtonStyle())
                .padding(.top, WatchLayout.space1)
            } else {
                Button {
                    sessionManager.sendSetCompleted(reps: nil)
                } label: {
                    WatchButtonLabel("Log set", systemImage: "checkmark")
                }
                .buttonStyle(WatchPrimaryButtonStyle())
                .padding(.top, WatchLayout.space1)
            }

            WatchHairline()
                .padding(.vertical, WatchLayout.space1)

            HeartRateRow(heartRate: heartRate)
        }
        .padding(.top, WatchLayout.space1)
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

// MARK: - Heart Rate Row

/// Glyph, number, unit. The heart is ink-secondary: no red on the Watch.
struct HeartRateRow: View {
    let heartRate: Double?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WatchLayout.space1) {
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(Color.inkSecondary)
                .accessibilityHidden(true)
            Text(heartRate.map { "\(Int($0))" } ?? "--")
                .font(WatchFonts.number())
                .foregroundStyle(heartRate == nil ? Color.inkSecondary : Color.ink)
            Text("BPM")
                .font(WatchFonts.eyebrow())
                .foregroundStyle(Color.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heartRate.map { "Heart rate \(Int($0)) beats per minute" } ?? "Heart rate not available")
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
        ScrollView {
            VStack(spacing: WatchLayout.space2) {
                WatchEyebrow("Reps done")
                    .foregroundStyle(Color.inkSecondary)

                HStack(spacing: WatchLayout.space2) {
                    stepButton(systemImage: "minus", label: "One fewer rep") {
                        if selectedRepsDouble > 1 { selectedRepsDouble -= 1 }
                    }

                    // Rep counter with Digital Crown support
                    WatchHeroNumber(value: "\(selectedReps)", baseSize: 56)
                        .frame(maxWidth: .infinity)
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
                        .accessibilityLabel("\(selectedReps) reps")

                    stepButton(systemImage: "plus", label: "One more rep") {
                        if selectedRepsDouble < 30 { selectedRepsDouble += 1 }
                    }
                }

                Text("Turn the crown to adjust")
                    .font(.caption2)
                    .foregroundStyle(Color.inkSecondary)

                Button {
                    onComplete(selectedReps)
                } label: {
                    WatchButtonLabel("Log \(selectedReps) reps", systemImage: "checkmark")
                }
                .buttonStyle(WatchPrimaryButtonStyle())
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    /// Square −/+ key: surface, hairline edge, ink glyph.
    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 36, height: 36)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: WatchLayout.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: WatchLayout.radiusSm)
                        .strokeBorder(Color.hairline, lineWidth: WatchLayout.hairline)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Basic Workout View (Fallback)

struct BasicWorkoutView: View {
    @ObservedObject var workoutManager: WatchWorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: WatchLayout.space2) {
            WatchEyebrow("Workout active", systemImage: "figure.strengthtraining.traditional")
                .foregroundStyle(Color.ink)

            WatchHeroNumber(value: workoutManager.formattedDuration, baseSize: 44)

            HeartRateRow(heartRate: workoutManager.currentHeartRate)

            Text("Tracking on iPhone")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, WatchLayout.space1)
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
