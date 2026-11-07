import SwiftUI

/// A day in Home's list: a row in a hairline group. The day pill follows the
/// WeekStrip guideline (done, current, upcoming); the status is a glyph and word.
struct DayCard: View {
    let day: Int
    let title: String
    let lifts: [String]
    let logStatus: DayLogStatus
    /// The next (or in-progress) workout: its pill is orange
    var isCurrent: Bool = false
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var liftsText: String {
        lifts.isEmpty ? "No exercises" : lifts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts = ["Day \(day)", title, lifts.isEmpty ? "No exercises" : lifts.joined(separator: ", ")]
        if isCurrent { parts.append("Next workout") }
        // The status last: UI tests and VoiceOver users both read it there
        parts.append(LogStatusBadge.word(for: logStatus))
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    // Stacked, so the title isn't squeezed to a letter a line
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        HStack(spacing: SBSLayout.space2) {
                            DayBadge(day: day, status: logStatus, isCurrent: isCurrent)
                            Spacer(minLength: 0)
                            SBSChevron()
                        }
                        titleAndLifts
                        // Its own line: beside the pill it runs off the screen
                        statusBadge
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: SBSLayout.space3) {
                        DayBadge(day: day, status: logStatus, isCurrent: isCurrent)
                        titleAndLifts
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        statusBadge
                        SBSChevron()
                    }
                }
            }
            .padding(.vertical, SBSLayout.space3)
            .padding(.horizontal, SBSLayout.space4)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // On the button itself: a wrapping element would make a second one
        .accessibilityLabel(accessibilityText)
    }

    private var titleAndLifts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.ink)

            Text(liftsText)
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.leading)
        }
    }

    /// Done and partial days say so; an upcoming day needs no tag
    @ViewBuilder
    private var statusBadge: some View {
        if logStatus != .notStarted {
            LogStatusBadge(status: logStatus)
                .fixedSize()
        }
    }
}

/// The day pill: done is surface-raised with struck-through ink-secondary text,
/// the current day orange with orange-ink and an ink edge, upcoming plain.
struct DayBadge: View {
    let day: Int
    let status: DayLogStatus
    var isCurrent: Bool = false

    private var isDone: Bool { status == .complete && !isCurrent }

    private var fill: Color {
        if isCurrent { return .orangeFill }
        return isDone ? .surfaceRaised : .surface
    }

    private var edge: Color {
        isCurrent ? .ink : .hairline
    }

    private var textColor: Color {
        if isCurrent { return .orangeInk }
        return isDone ? .inkSecondary : .ink
    }

    var body: some View {
        Text("Day \(day)")
            .font(SBSFonts.numberSmall().weight(.semibold))
            .strikethrough(isDone, color: Color.inkSecondary)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(fill, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(edge, lineWidth: SBSLayout.strokeHairline)
            )
    }
}

/// A day's log status as a status badge: glyph and word, never a solid fill.
struct LogStatusBadge: View {
    let status: DayLogStatus

    /// The status as VoiceOver and UI tests read it. An upcoming day has no
    /// visible badge, but its label still says "To Do".
    static func word(for status: DayLogStatus) -> String {
        switch status {
        case .complete: return "Done"
        case .partial: return "Partial"
        case .notStarted: return "To Do"
        }
    }

    var body: some View {
        switch status {
        case .complete:
            SBSBadge(text: "Done", variant: .status(.success), systemImage: "checkmark")
        case .partial:
            SBSBadge(text: "Partial", variant: .status(.warning), systemImage: "circle.lefthalf.filled")
        case .notStarted:
            SBSBadge(text: "To Do")
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        DayCard(
            day: 1,
            title: "Squat Day",
            lifts: ["Squat", "Push Press"],
            logStatus: .complete,
            onTap: {}
        )
        SBSRowDivider()
        DayCard(
            day: 2,
            title: "Bench Day",
            lifts: ["Bench Press", "Front Squat"],
            logStatus: .partial,
            isCurrent: true,
            onTap: {}
        )
        SBSRowDivider()
        DayCard(
            day: 3,
            title: "Deadlift Day",
            lifts: ["Trap Bar Deadlift", "Incline Press"],
            logStatus: .notStarted,
            onTap: {}
        )
    }
    .card()
    .padding()
    .sbsBackground()
}
