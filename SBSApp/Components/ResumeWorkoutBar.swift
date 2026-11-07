import SwiftUI

/// Bar above the tab bar while a workout is minimized: what's next, the rest countdown
/// when there is one, and a tap to reopen the workout. It has a solid background, since
/// list content scrolls behind it.
struct ResumeWorkoutBar: View {
    let session: ActiveWorkoutSession
    let onTap: () -> Void

    private let status = RestTimerStatus.shared

    var body: some View {
        // A running rest ticks in step with the number changing, so the bar stays level
        // with the Live Activity.
        TimelineView(.periodic(from: tickAnchor, by: 1)) { _ in
            Button(action: onTap) {
                HStack(spacing: SBSLayout.paddingSmall) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SBSColors.accentFallback)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .lineLimit(1)
                    }

                    Spacer(minLength: SBSLayout.paddingSmall)

                    if let restText {
                        Text(restText)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(SBSColors.accentFallback)
                            .lineLimit(1)
                            .fixedSize()
                    }

                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("resumeWorkoutBar")
        }
        .background(SBSColors.surfaceFallback)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    /// A past date on the same fractional second as the timer's end, so each tick lands
    /// on the moment the displayed number changes rather than up to a second after it.
    private var tickAnchor: Date {
        guard let endDate = status.endDate else { return .now }
        return endDate.addingTimeInterval(-(ceil(endDate.timeIntervalSinceNow) + 1))
    }

    private var state: WorkoutState { session.workoutState }

    private var title: String {
        if let pending = session.pendingLinearExercise { return pending.name }
        if state.isWorkoutComplete { return "Workout Complete" }
        return state.currentExercise?.name ?? "Workout"
    }

    private var subtitle: String {
        if session.pendingLinearExercise != nil { return "Tap to log your result" }
        if state.isWorkoutComplete { return "Tap to finish" }
        return session.setInfoText
    }

    private var restText: String? {
        if session.restDoneWhileMinimized { return "Rest done" }
        guard status.isActive else { return nil }
        let remaining = status.remaining
        let time = String(format: "%d:%02d", remaining / 60, remaining % 60)
        return status.isPaused ? "\(time) paused" : time
    }

    private var accessibilityText: String {
        var parts = ["Resume workout", title, subtitle]
        if session.restDoneWhileMinimized {
            parts.append("Rest done")
        } else if status.isActive {
            parts.append("Rest timer, \(status.remaining) seconds remaining\(status.isPaused ? ", paused" : "")")
        }
        return parts.joined(separator: ", ")
    }
}
