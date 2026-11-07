import Foundation

/// The cycle builder's screens. Raw values are persisted in `OnboardingDraft.step`, so
/// they must not be renumbered. 4 was the settings step, removed in 2026: it's retired
/// rather than reused, and `init(restoringDraftStep:hasUsableMaxes:)` maps old drafts.
public enum SetupStep: Int, CaseIterable {
    case welcome = 0
    case program = 1
    case exercises = 2
    case trainingMaxes = 3
    case summary = 5

    /// The screens with a dot in the step indicator. Welcome shows no indicator, and
    /// non-onboarding builds never visit it, so this list is right for both.
    public static let indicatorSteps: [SetupStep] = [.program, .exercises, .trainingMaxes, .summary]

    /// Label under the indicator dot. Short enough to fit a column on the smallest phone.
    public var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .program: return "Program"
        case .exercises: return "Exercises"
        case .trainingMaxes: return "Weights"
        case .summary: return "Review"
        }
    }

    /// Where a saved draft should reopen. Review needs real weights behind it, so without
    /// them it reopens on the weights step. A draft from the settings step had passed
    /// weights already, so it continues to Review. An unknown value reopens on the program
    /// list, which is always usable and keeps the draft's selection.
    public init(restoringDraftStep rawValue: Int, hasUsableMaxes: Bool) {
        switch rawValue {
        case SetupStep.welcome.rawValue: self = .welcome
        case SetupStep.program.rawValue: self = .program
        case SetupStep.exercises.rawValue: self = .exercises
        case SetupStep.trainingMaxes.rawValue: self = .trainingMaxes
        case 4, SetupStep.summary.rawValue: self = hasUsableMaxes ? .summary : .trainingMaxes
        default: self = .program
        }
    }
}

/// Lightweight UserDefaults-backed snapshot of onboarding progress. Persisted as the user
/// advances so an app kill mid-flow restores their program pick, step, and entered
/// training maxes instead of restarting from zero. Deliberately not a full state machine,
/// just enough to avoid losing meaningful work.
public struct OnboardingDraft: Codable, Equatable {
    public var step: Int
    public var selectedProgram: String
    public var trainingMaxes: [String: Double]

    private static let key = "onboarding.draft.v1"

    public init(step: Int, selectedProgram: String, trainingMaxes: [String: Double]) {
        self.step = step
        self.selectedProgram = selectedProgram
        self.trainingMaxes = trainingMaxes
    }

    public static func load() -> OnboardingDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OnboardingDraft.self, from: data)
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Where this draft should reopen
    public var restoredStep: SetupStep {
        let usable = !trainingMaxes.isEmpty && trainingMaxes.values.allSatisfy { $0 > 0 }
        return SetupStep(restoringDraftStep: step, hasUsableMaxes: usable)
    }
}
