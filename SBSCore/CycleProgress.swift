import Foundation

/// The counting and comparing behind Home's progress bar and cycle-complete card
enum CycleProgress {
    enum DayState {
        case notStarted
        case partial
        case complete
    }

    struct Tally: Equatable {
        var completedDays = 0
        /// Days with anything logged, complete or not
        var loggedDays = 0
        var totalDays = 0

        var completedFraction: Double {
            totalDays > 0 ? Double(completedDays) / Double(totalDays) : 0
        }
    }

    struct LiftGain: Equatable {
        let lift: String
        let from: Double
        let to: Double

        var gain: Double { to - from }
    }

    /// Smallest rise worth showing, in stored pounds. Anything less rounds away to
    /// "+0" in one of the units (0.1 kg is about 0.22 lb, and rounds up from half that).
    static let minimumVisibleGain = 0.12

    static func tally(
        weeks: [Int],
        visibleDays: (Int) -> [Int],
        state: (_ week: Int, _ day: Int) -> DayState
    ) -> Tally {
        var tally = Tally()
        for week in weeks {
            for day in visibleDays(week) {
                tally.totalDays += 1
                switch state(week, day) {
                case .notStarted:
                    break
                case .partial:
                    tally.loggedDays += 1
                case .complete:
                    tally.loggedDays += 1
                    tally.completedDays += 1
                }
            }
        }
        return tally
    }

    /// Lifts that rose, in the order given. A lift with no positive starting value has
    /// nothing real to compare against, so it isn't shown as a gain of its whole weight.
    static func gains(
        liftOrder: [String],
        starting: [String: Double],
        next: [String: Double]
    ) -> [LiftGain] {
        unique(liftOrder).compactMap { lift in
            guard let from = starting[lift], from > 0,
                  let to = next[lift], to - from >= minimumVisibleGain else { return nil }
            return LiftGain(lift: lift, from: from, to: to)
        }
    }

    /// The main lifts in a day's plan, in plan order. A lift can appear more than once,
    /// as with nSuns' paired TM and volume items or GZCLP's tiers. Accessories aren't
    /// main lifts.
    static func mainLifts(in plan: [PlanItem]) -> [String] {
        unique(plan.compactMap { item in
            switch item {
            case .tm(_, let lift, _, _):
                return lift
            case .volume(_, let lift, _, _, _, _, _, _, _, _, _):
                return lift
            case .structured(_, let lift, _, _, _):
                return lift
            case .linear(_, let info):
                return info.lift
            case .accessory:
                return nil
            }
        })
    }

    /// Lifts in configured order, for lists that span the cycle
    static func mainLifts(in items: [DayItem]) -> [String] {
        unique(items.filter { $0.type != .accessory }.compactMap(\.lift))
    }

    /// What to list for a day whose plan has no main lift: its configured lifts, which a
    /// plan drops while they have no training max, or else the accessories, when those
    /// are all the day holds.
    static func fallbackLifts(from items: [DayItem]) -> [String] {
        let lifts = mainLifts(in: items)
        return lifts.isEmpty ? unique(items.map(\.name)) : lifts
    }

    /// Linear programs work from a weight, not a training max
    static func usesTrainingMaxes(_ items: [DayItem]) -> Bool {
        items.contains { $0.type == .tm || $0.type == .volume || $0.type == .structured }
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}

/// What the cycle-complete card shows
struct CycleCompletionSummary: Equatable {
    let sessionsCompleted: Int
    let gains: [CycleProgress.LiftGain]
    let usesTrainingMaxes: Bool
}
