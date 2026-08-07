import SwiftUI

/// Floating pill shown above the tab bar while a rest timer is running but
/// the workout screen is off screen (user switched tabs mid-workout).
/// Tapping it returns to the workout.
struct RestTimerPill: View {
    let status: RestTimerStatus
    let onTap: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(labelText)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(status.isExpired ? Color.white : SBSColors.accentFallback)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(status.isExpired ? AnyShapeStyle(SBSColors.accentFallback) : AnyShapeStyle(.regularMaterial))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(SBSColors.accentFallback.opacity(status.isExpired ? 0 : 0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: SBSLayout.shadowRadius, x: 0, y: SBSLayout.shadowY)
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(accessibilityText)
    }

    private var iconName: String {
        if status.isExpired { return "checkmark.circle.fill" }
        if status.isPaused { return "pause.fill" }
        return "timer"
    }

    private var labelText: String {
        if status.isExpired { return "Rest done — back to it!" }
        let remaining = status.remaining
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private var accessibilityText: String {
        if status.isExpired { return "Rest complete. Return to workout." }
        return "Rest timer, \(status.remaining) seconds remaining. Return to workout."
    }
}
