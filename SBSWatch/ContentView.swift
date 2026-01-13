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
                
                if sessionManager.isPhoneReachable {
                    Text("Start a workout on your iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("iPhone not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

// MARK: - Workout Active View

struct WorkoutActiveView: View {
    @EnvironmentObject var workoutManager: WatchWorkoutManager
    
    var body: some View {
        ScrollView {
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
}

#Preview {
    ContentView()
        .environmentObject(WatchWorkoutManager())
        .environmentObject(WatchSessionManager.shared)
}
