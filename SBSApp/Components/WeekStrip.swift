import SwiftUI

/// One day of a week in the strip
struct WeekStripDay: Hashable {
    let day: Int
    let status: DayLogStatus
}

/// Where the lifter is in the cycle (WeekStrip guideline): a pill per week with a
/// square per day, filled ink when done. The week being shown below is selected
/// (orange-soft, orange-text edge); the week the lifter is in has its label in
/// orange-text, an ink edge, and its next day's square in orange.
struct WeekStrip: View {
    @Binding var selectedWeek: Int
    let totalWeeks: Int
    /// The week and day of the next (or in-progress) workout, when there is one
    var currentWeek: Int? = nil
    var currentDay: Int? = nil
    /// The days of a week and how far each got
    var days: (Int) -> [WeekStripDay] = { _ in [] }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("Week \(selectedWeek) of \(totalWeeks)", knurled: true)

            // Scrolls when the cycle is longer than fits; never wraps
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SBSLayout.space2) {
                        ForEach(1...max(totalWeeks, 1), id: \.self) { week in
                            WeekPill(
                                week: week,
                                days: days(week),
                                isSelected: week == selectedWeek,
                                isCurrent: week == currentWeek,
                                currentDay: week == currentWeek ? currentDay : nil
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    selectedWeek = week
                                }
                            }
                            .id(week)
                        }
                    }
                    // Room for the selected pill's edge
                    .padding(.vertical, 1)
                }
                .onChange(of: selectedWeek) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(selectedWeek, anchor: .center)
                }
            }
        }
    }
}

struct WeekPill: View {
    let week: Int
    let days: [WeekStripDay]
    let isSelected: Bool
    let isCurrent: Bool
    /// The next day in the current week: its square is orange
    var currentDay: Int? = nil
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .caption2) private var squareSize: CGFloat = 10

    private var doneCount: Int {
        days.filter { $0.status == .complete }.count
    }

    private var labelColor: Color {
        if isCurrent { return .orangeText }
        return isSelected ? .ink : .inkSecondary
    }

    private var edgeColor: Color {
        if isSelected { return .orangeText }
        return isCurrent ? .ink : .hairline
    }

    private var accessibilityValue: String {
        var parts = ["\(doneCount) of \(days.count) days done"]
        if isCurrent { parts.append("current week") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Week \(week)".uppercased())
                    .font(SBSFonts.eyebrow())
                    .tracking(0.9)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    ForEach(days, id: \.self) { day in
                        DaySquare(status: day.status, isCurrent: day.day == currentDay)
                            .frame(width: squareSize, height: squareSize)
                    }
                }
                .frame(minHeight: squareSize)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, SBSLayout.space2)
            .frame(minWidth: 64, alignment: .leading)
            .background(isSelected ? Color.orangeSoft : Color.surface, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(edgeColor, lineWidth: SBSLayout.strokeHairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(week)")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A day in a week pill: an ink outline, filled ink when done, the lower half
/// filled when partly done, orange with an ink edge for the next workout. The
/// fill is the state; no checkmarks.
private struct DaySquare: View {
    let status: DayLogStatus
    let isCurrent: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            if isCurrent && status != .complete {
                Rectangle().fill(Color.orangeFill)
            } else {
                switch status {
                case .complete:
                    Rectangle().fill(Color.ink)
                case .partial:
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.ink)
                            .frame(height: geo.size.height / 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                case .notStarted:
                    Color.clear
                }
            }
            Rectangle().strokeBorder(Color.ink, lineWidth: SBSLayout.strokeHairline)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack {
        WeekStrip(
            selectedWeek: .constant(3),
            totalWeeks: 12,
            currentWeek: 3,
            currentDay: 2,
            days: { week in
                (1...4).map { day in
                    let status: DayLogStatus = week < 3 ? .complete : (week == 3 && day == 1 ? .complete : (week == 3 && day == 3 ? .partial : .notStarted))
                    return WeekStripDay(day: day, status: status)
                }
            }
        )
    }
    .padding()
    .sbsBackground()
}
