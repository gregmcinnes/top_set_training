import Foundation

private let kilogramsPerPound = 0.45359237

// MARK: - What the entered number means

/// What the number a user enters for a lift means in the current program.
public enum StartingWeightKind: Equatable {
    /// The weight on the bar in the first workout: linear lifts start from it directly
    /// (`computeLinearWeightForSession`), and structured lifts whose week 1 sets are all
    /// at 100% of it get the same number.
    case firstWorkingWeight
    /// A training max: the program works from percentages of it.
    case trainingMax

    /// A program is `.firstWorkingWeight` only if every main lift is. Mixed programs
    /// prescribe percentages somewhere, so they get the training max explanation.
    public static func classify(items: [DayItem]) -> StartingWeightKind {
        let main = items.filter(\.isMainLift)
        guard !main.isEmpty else { return .trainingMax }
        return main.allSatisfy(\.startsAtEnteredWeight) ? .firstWorkingWeight : .trainingMax
    }
}

private extension DayItem {
    var isMainLift: Bool { lift != nil && type != .accessory }

    var weekOneSets: [SetDetail]? { setsDetailByWeek?["1"] ?? setsDetail }

    var startsAtEnteredWeight: Bool {
        switch type {
        case .linear:
            return true
        case .structured:
            guard let sets = weekOneSets, !sets.isEmpty else { return false }
            return sets.allSatisfy { abs($0.intensity - 1.0) < 0.001 }
        case .tm, .volume, .accessory:
            return false
        }
    }
}

// MARK: - Lift order

public enum ProgramLifts {
    /// Main lifts in the order the program does them, with Squat first where it appears.
    /// - Parameter days: each day's items, in day order
    public static func ordered(days: [[DayItem]]) -> [String] {
        var seen = Set<String>()
        var lifts: [String] = []
        for items in days {
            for item in items where item.isMainLift {
                if let lift = item.lift, seen.insert(lift).inserted {
                    lifts.append(lift)
                }
            }
        }
        if let squat = lifts.firstIndex(of: "Squat") {
            lifts.insert(lifts.remove(at: squat), at: 0)
        }
        return lifts
    }

    /// Reps per set where the lift first appears, for sizing a first working weight.
    /// Falls back to 5 when the program doesn't say.
    public static func targetReps(for lift: String, days: [[DayItem]]) -> Int {
        for items in days {
            for item in items where item.isMainLift && item.lift == lift {
                if let reps = item.reps ?? item.weekOneSets?.first?.reps, reps > 0 {
                    return reps
                }
            }
        }
        return 5
    }
}

// MARK: - Starter weights

/// Light starting points for someone who doesn't know their numbers. Weights are stored
/// in pounds, so the kilogram column is converted on the way out and shows as a round
/// number in kg.
public enum StarterWeights {
    private struct FirstWorkingWeight {
        let lb: Double
        let kg: Double
    }

    /// Top work sets in percentage programs sit around 85% in week 1, so a training max
    /// starter puts about the same weight on the bar as a first working weight would.
private static let topSetShareOfTrainingMax = 0.85
    /// Training max as a share of estimated 1RM: the top of the 85-90% the app recommends.
private static let trainingMaxShareOfE1RM = 0.9
    /// Start a little under what the user could do for the program's reps.
    private static let firstWorkingWeightShareOfRepMax = 0.9
    /// Epley drifts well off at high reps, so longer sets don't produce an estimate.
    public static let maxEstimateReps = 15

    private static func firstWorkingWeight(for lift: String) -> FirstWorkingWeight? {
        let name = lift.lowercased()
        func has(_ terms: String...) -> Bool { terms.contains { name.contains($0) } }

        // Not loaded like a barbell, so a barbell number means nothing. The bar floor
        // below is what these get.
        if has("dumbbell", "kettlebell", "goblet", "split squat", "lunge", "curl", "dip", "pull-up", "pullup", "pull up", "chin") {
            return nil
        }
        if has("romanian", "rdl", "stiff") { return .init(lb: 95, kg: 40) }
        if has("deadlift", "rack pull", "trap bar") { return .init(lb: 135, kg: 60) }
        if has("front squat") { return .init(lb: 75, kg: 35) }
        if has("squat", "leg press", "hack") { return .init(lb: 95, kg: 40) }
        if has("incline", "close-grip", "close grip") { return .init(lb: 65, kg: 30) }
        if has("bench", "spoto") { return .init(lb: 75, kg: 35) }
        if has("overhead", "ohp", "push press", "military", "shoulder press") || name == "press" {
            return .init(lb: 55, kg: 25)
        }
        if has("clean") { return .init(lb: 65, kg: 30) }
        if has("row") { return .init(lb: 75, kg: 35) }
        return nil
    }

    /// Lifts done on bodyweight, where the number is weight added to the lifter. Zero is a
    /// real value for these: no added weight. For anything else zero still means unset.
    public static func startsWithNoAddedWeight(_ lift: String) -> Bool {
        let name = lift.lowercased()
        guard !name.contains("machine"), !name.contains("assisted") else { return false }
        return ["dip", "pull-up", "pullup", "pull up", "chin"].contains { name.contains($0) }
    }

    /// The starter for a lift, in stored pounds. Never below the bar, apart from bodyweight
    /// lifts, which start with no added weight.
    public static func starter(for lift: String, useMetric: Bool, barWeight: Double, kind: StartingWeightKind) -> Double {
        if startsWithNoAddedWeight(lift) { return 0 }
        guard let base = firstWorkingWeight(for: lift) else { return barWeight }
        var shown = useMetric ? base.kg : base.lb
        if kind == .trainingMax {
            shown = roundToLoadable(shown / topSetShareOfTrainingMax, useMetric: useMetric)
        }
        return max(shown.poundsFromInput(useMetric: useMetric), barWeight)
    }

    /// What to enter for a lift, given a recent set. `nil` until the set can be estimated from.
    /// - Parameters:
    ///   - weightLifted: stored pounds
    ///   - targetReps: reps per set the program asks for, used for a first working weight
    public static func estimate(
        weightLifted: Double,
        reps: Int,
        kind: StartingWeightKind,
        targetReps: Int,
        useMetric: Bool,
        barWeight: Double
    ) -> Double? {
        guard (1...maxEstimateReps).contains(reps) else { return nil }
        let e1RM = E1RM.epley(weight: weightLifted, reps: reps)
        guard e1RM > 0 else { return nil }

        let pounds: Double
        switch kind {
        case .trainingMax:
            pounds = e1RM * trainingMaxShareOfE1RM
        case .firstWorkingWeight:
            // Epley solved for the weight that makes `targetReps` a max set
            pounds = e1RM / (1.0 + Double(max(targetReps, 1)) / 30.0) * firstWorkingWeightShareOfRepMax
        }
        let shown = roundToLoadable(useMetric ? pounds * kilogramsPerPound : pounds, useMetric: useMetric)
        return max(shown.poundsFromInput(useMetric: useMetric), barWeight)
    }

    /// A lift's stored value after the user switches units during setup. That control says
    /// which unit their numbers are in, so typed digits stay as typed (100 lb becomes 100 kg)
    /// rather than converting to 45.4, and an untouched starter becomes the new unit's starter.
    public static func valueAfterUnitChange(
        _ stored: Double,
        lift: String,
        kind: StartingWeightKind,
        fromMetric: Bool,
        fromBarWeight: Double,
        toMetric: Bool,
        toBarWeight: Double
    ) -> Double {
        guard fromMetric != toMetric, stored > 0 else { return stored }
        let oldStarter = starter(for: lift, useMetric: fromMetric, barWeight: fromBarWeight, kind: kind)
        if abs(stored - oldStarter) < 0.01 {
            return starter(for: lift, useMetric: toMetric, barWeight: toBarWeight, kind: kind)
        }
        let shown = ((fromMetric ? stored * kilogramsPerPound : stored) * 10).rounded() / 10
        return shown.poundsFromInput(useMetric: toMetric)
    }

    /// Nearest weight a normal plate set reaches: 5 lb or 2.5 kg steps.
    private static func roundToLoadable(_ shown: Double, useMetric: Bool) -> Double {
        let step = useMetric ? 2.5 : 5.0
        return (shown / step).rounded() * step
    }
}

// MARK: - Default units

public enum UnitDefaults {
    /// Countries that don't use US customary units get kilograms. Stays a default: the
    /// weights step has the control to change it.
    public static func prefersMetric(locale: Locale) -> Bool {
        locale.measurementSystem != .us
    }

    /// Only a true first run takes its units from the locale. Anything suggesting this
    /// person has used the app before (a saved draft, any data, units or rounding moved
    /// off the defaults) leaves `useMetric` alone.
    public static func shouldApplyLocale(settings: UserSettings, userData: UserData, hasOnboardingDraft: Bool) -> Bool {
        let untouchedSettings = settings.useMetric == UserSettings.default.useMetric
            && settings.roundingIncrement == UserSettings.default.roundingIncrement
            && settings.barWeight == UserSettings.default.barWeight
        let noData = userData.selectedProgram == nil
            && userData.logs.isEmpty
            && userData.structuredLogs.isEmpty
            && userData.linearLogs.isEmpty
            && userData.workoutRecords.isEmpty
            && userData.liftHistory.isEmpty
            && userData.cycleHistory.isEmpty
            && userData.customInitialMaxes.isEmpty
            && userData.trainingMaxes.isEmpty
        return !userData.hasCompletedOnboarding && !hasOnboardingDraft && untouchedSettings && noData
    }
}
