import ActivityKit
import SwiftUI
import WidgetKit

// The rest timer Live Activity in the Top Set design system: the timer numeral
// (Barlow Condensed, tabular) and an orange progress bar on a hairline track.
// Colours are the shared tokens (Shared/Tokens.xcassets); the lock screen follows
// the system theme, the Dynamic Island is always dark so it always gets Iron.
//
// Deviations from the in-app rest timer: no knurl (too fine for the Dynamic Island
// and the lock screen), no −15s/+15s keys (Live Activity buttons would need App
// Intents), and the lock screen card is the system's rounded platter, not radiusSm.

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.surface)
                .activitySystemActionForegroundColor(Color.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RestStatusLabel(isPaused: context.state.isPaused)
                        .padding(.leading, 4)
                        .padding(.top, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(context: context, size: 40)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(context.attributes.exerciseName)
                                .font(LiveActivityFonts.heading())
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(context.attributes.nextSetInfo)
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(1)
                        }
                        RestProgressBar(context: context)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                RestGlyph(isPaused: context.state.isPaused)
            } compactTrailing: {
                RestCountdown(context: context, size: 17)
                    .frame(maxWidth: 44, alignment: .trailing)
            } minimal: {
                RestGlyph(isPaused: context.state.isPaused)
            }
            .keylineTint(Color.orangeFill)
        }
    }
}

// MARK: - Type

/// The brand faces, bundled in the extension (project.yml UIAppFonts).
enum LiveActivityFonts {
    static func timer(size: CGFloat) -> Font {
        .custom("BarlowCondensed-Bold", size: size, relativeTo: .largeTitle).monospacedDigit()
    }

    static func eyebrow() -> Font {
        .custom("ArchivoSemiCondensed-Bold", size: 12, relativeTo: .caption2)
    }

    static func heading() -> Font {
        .custom("Archivo-Bold", size: 17, relativeTo: .headline)
    }
}

// MARK: - Pieces

private extension ActivityViewContext<RestTimerAttributes> {
    var timerRange: ClosedRange<Date> {
        let end = state.endTime
        return end.addingTimeInterval(-Double(attributes.totalDuration))...end
    }

    /// Fraction of the rest still to go, for the frozen bar while paused.
    var pausedRemaining: Double {
        let total = Double(attributes.totalDuration)
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(state.secondsRemaining) / total))
    }

    var pausedTime: String {
        let s = max(0, state.secondsRemaining)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Status as glyph plus word: "REST" in orange-text, or "PAUSED" in ink-secondary.
private struct RestStatusLabel: View {
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPaused ? "pause.fill" : "timer")
                .font(.caption2.weight(.bold))
            Text(isPaused ? "PAUSED" : "REST")
                .font(LiveActivityFonts.eyebrow())
                .tracking(1.1)
                .accessibilityLabel(isPaused ? "Rest paused" : "Rest")
        }
        .foregroundStyle(isPaused ? Color.inkSecondary : Color.orangeText)
    }
}

/// The glyph alone, for the compact and minimal Dynamic Island.
private struct RestGlyph: View {
    let isPaused: Bool

    var body: some View {
        Image(systemName: isPaused ? "pause.fill" : "timer")
            .font(.body.weight(.semibold))
            .foregroundStyle(isPaused ? Color.inkSecondary : Color.orangeText)
            .accessibilityLabel(isPaused ? "Rest paused" : "Rest")
    }
}

/// The countdown numeral. Ticks on its own (Text(timerInterval:)) so it stays live
/// on the lock screen without the app pushing updates. Paused shows the frozen time.
private struct RestCountdown: View {
    let context: ActivityViewContext<RestTimerAttributes>
    let size: CGFloat

    var body: some View {
        Group {
            if context.state.isPaused {
                Text(context.pausedTime)
                    .foregroundStyle(Color.inkSecondary)
            } else {
                Text(timerInterval: min(Date(), context.state.endTime)...context.state.endTime, countsDown: true)
                    .foregroundStyle(Color.ink)
            }
        }
        .font(LiveActivityFonts.timer(size: size))
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
    }
}

/// Orange progress on its track, draining as the rest runs down. The system linear
/// style, tinted: only the system styles animate a timerInterval ProgressView in a
/// Live Activity (a custom ProgressViewStyle gets one snapshot and never drains).
private struct RestProgressBar: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        Group {
            if context.state.isPaused {
                ProgressView(value: context.pausedRemaining)
            } else {
                ProgressView(timerInterval: context.timerRange, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.linear)
        .tint(Color.orangeFill)
        .accessibilityHidden(true)
    }
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    RestStatusLabel(isPaused: context.state.isPaused)
                    Text(context.attributes.exerciseName)
                        .font(LiveActivityFonts.heading())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(context.attributes.nextSetInfo)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                RestCountdown(context: context, size: 52)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            RestProgressBar(context: context)
        }
        .padding(16)
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
