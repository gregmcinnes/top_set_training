import ActivityKit
import SwiftUI
import WidgetKit

// App theme color - orange
private let themeColor = Color.orange

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: context.state.isPaused ? "pause.fill" : "dumbbell.fill")
                            .font(.caption)
                            .foregroundStyle(context.state.isPaused ? .yellow : themeColor)
                        Text("Rest")
                            .font(.subheadline.bold())
                            .foregroundStyle(context.state.isPaused ? .yellow : themeColor)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if context.state.isPaused {
                            Text("--:--")
                                .font(.title3.bold())
                                .monospacedDigit()
                                .foregroundStyle(.yellow)
                        } else {
                            Text(timerInterval: Date()...context.state.endTime, countsDown: true)
                                .font(.title3.bold())
                                .monospacedDigit()
                                .foregroundStyle(themeColor)
                        }
                        Text(context.attributes.nextSetInfo)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(context.attributes.exerciseName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        ProgressView(value: progressValue(context: context))
                            .tint(context.state.isPaused ? .yellow : themeColor)
                    }
                }
            } compactLeading: {
                // Compact leading (left side of notch)
                Image(systemName: context.state.isPaused ? "pause.fill" : "dumbbell.fill")
                    .foregroundStyle(context.state.isPaused ? .yellow : themeColor)
            } compactTrailing: {
                // Compact trailing (right side of notch)
                if context.state.isPaused {
                    Text("--:--")
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundStyle(.yellow)
                        .frame(width: 35, alignment: .trailing)
                } else {
                    Text(timerInterval: Date()...context.state.endTime, countsDown: true)
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundStyle(themeColor)
                        .frame(width: 35, alignment: .trailing)
                }
            } minimal: {
                // Minimal (when multiple activities)
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(themeColor)
            }
        }
    }
    
    private func progressValue(context: ActivityViewContext<RestTimerAttributes>) -> Double {
        let total = Double(context.attributes.totalDuration)
        let remaining = Double(context.state.secondsRemaining)
        guard total > 0 else { return 0 }
        return remaining / total
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>
    
    var body: some View {
        HStack(spacing: 16) {
            // Timer circle
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                    .frame(width: 56, height: 56)
                
                Circle()
                    .trim(from: 0, to: progressValue)
                    .stroke(
                        themeColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                
                if context.state.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.yellow)
                } else {
                    Text(timerInterval: Date()...context.state.endTime, countsDown: true)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(themeColor)
                    
                    Text("REST TIMER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                
                Text(context.attributes.exerciseName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(context.attributes.nextSetInfo)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Open hint
            VStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(themeColor)
                
                Text("OPEN")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.08, blue: 0.04),
                    Color(red: 0.08, green: 0.06, blue: 0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private var progressValue: Double {
        let total = Double(context.attributes.totalDuration)
        let remaining = Double(context.state.secondsRemaining)
        guard total > 0 else { return 0 }
        return remaining / total
    }
}

// MARK: - Progress Circle

struct ProgressCircle: View {
    let progress: Double
    let isPaused: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isPaused ? Color.yellow : themeColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.yellow)
            } else {
                Text("\(Int(progress * 100))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Previews

#Preview("Lock Screen", as: .content, using: RestTimerAttributes(
    exerciseName: "Bench Press",
    totalDuration: 120,
    nextSetInfo: "Set 3 of 5"
)) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(
        secondsRemaining: 90,
        isPaused: false,
        endTime: Date().addingTimeInterval(90)
    )
    RestTimerAttributes.ContentState(
        secondsRemaining: 45,
        isPaused: true,
        endTime: Date().addingTimeInterval(45)
    )
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: RestTimerAttributes(
    exerciseName: "Squat",
    totalDuration: 90,
    nextSetInfo: "Set 2 of 4"
)) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(
        secondsRemaining: 60,
        isPaused: false,
        endTime: Date().addingTimeInterval(60)
    )
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: RestTimerAttributes(
    exerciseName: "Deadlift",
    totalDuration: 180,
    nextSetInfo: "Set 4 of 5"
)) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(
        secondsRemaining: 120,
        isPaused: false,
        endTime: Date().addingTimeInterval(120)
    )
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: RestTimerAttributes(
    exerciseName: "OHP",
    totalDuration: 60,
    nextSetInfo: "Set 1 of 3"
)) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(
        secondsRemaining: 30,
        isPaused: false,
        endTime: Date().addingTimeInterval(30)
    )
}
