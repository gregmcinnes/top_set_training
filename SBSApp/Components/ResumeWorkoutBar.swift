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
                HStack(spacing: SBSLayout.space3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: SBSLayout.space2)

                    restPill

                    Image(systemName: "chevron.up")
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.horizontal, SBSLayout.space4)
                .padding(.vertical, SBSLayout.space2)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("resumeWorkoutBar")
        }
        .background(Color.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.hairline).frame(height: SBSLayout.strokeHairline)
        }
        // One line each: at accessibility sizes the bar would crowd out the screen
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// The rest countdown as a pill: raised and hairline while counting, an orange
    /// block once the rest is over.
    @ViewBuilder
    private var restPill: some View {
        if session.restDoneWhileMinimized {
            Text("Rest done · back to it")
                .eyebrowText()
                .foregroundStyle(Color.orangeInk)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, SBSLayout.space3)
                .padding(.vertical, SBSLayout.space2)
                .background(Color.orangeFill, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
        } else if let restText {
            HStack(spacing: SBSLayout.space1) {
                Image(systemName: status.isPaused ? "pause" : "timer")
                    .font(SBSFonts.caption().weight(.semibold))
                Text(restText)
                    .font(SBSFonts.numberSmall())
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, SBSLayout.space2)
            .padding(.vertical, 6)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
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
        if state.isFinished { return "Workout Complete" }
        return state.currentExercise?.name ?? "Workout"
    }

    private var subtitle: String {
        if state.isFinished { return "Tap to finish" }
        return session.setInfoText
    }

    private var restText: String? {
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
