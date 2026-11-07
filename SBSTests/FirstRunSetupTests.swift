import XCTest
@testable import SBSApp

/// First-run setup logic: starter weights, estimates, units, lift order, draft restore
final class FirstRunSetupTests: XCTestCase {

    private let lbPerKg = 1.0 / 0.45359237
    private let kgBar = 20.0 / 0.45359237

    private func linear(_ lift: String, reps: Int = 5) -> DayItem {
        DayItem(type: .linear, lift: lift, name: lift, sets: 5, reps: reps)
    }

    private func structured(_ lift: String, intensities: [Double], reps: Int = 5) -> DayItem {
        DayItem(type: .structured, lift: lift, name: lift,
                setsDetail: intensities.map { SetDetail(intensity: $0, reps: reps, isAMRAP: false) })
    }

    private func starter(_ lift: String, metric: Bool = false, kind: StartingWeightKind = .firstWorkingWeight) -> Double {
        StarterWeights.starter(for: lift, useMetric: metric, barWeight: metric ? kgBar : 45, kind: kind)
    }

    // MARK: - Kind

    func testLinearProgramEntersFirstWorkingWeight() {
        XCTAssertEqual(StartingWeightKind.classify(items: [linear("Squat"), linear("Bench Press")]), .firstWorkingWeight)
    }

    func testStructuredAtFullIntensityEntersFirstWorkingWeight() {
        XCTAssertEqual(StartingWeightKind.classify(items: [structured("Squat", intensities: [1, 1, 1])]), .firstWorkingWeight)
    }

    func testPercentageProgramEntersTrainingMax() {
        XCTAssertEqual(StartingWeightKind.classify(items: [structured("Squat", intensities: [0.65, 0.75, 0.85])]), .trainingMax)
    }

    func testVolumeAndTMItemsAreTrainingMax() {
        XCTAssertEqual(StartingWeightKind.classify(items: [DayItem(type: .volume, lift: "Squat", name: "Squat")]), .trainingMax)
        XCTAssertEqual(StartingWeightKind.classify(items: [DayItem(type: .tm, lift: "Squat", name: "Squat TM")]), .trainingMax)
    }

    func testMixedProgramIsTrainingMax() {
        let items = [structured("Squat", intensities: [1]), structured("Deadlift", intensities: [0.85])]
        XCTAssertEqual(StartingWeightKind.classify(items: items), .trainingMax)
    }

    func testAccessoriesDontAffectKind() {
        let items = [linear("Squat"), DayItem(type: .accessory, lift: nil, name: "Curl")]
        XCTAssertEqual(StartingWeightKind.classify(items: items), .firstWorkingWeight)
    }

    func testWeekOneSetsDecideWeekBasedPrograms() {
        let sets = ["1": [SetDetail(intensity: 0.65, reps: 5, isAMRAP: false)]]
        let item = DayItem(type: .structured, lift: "Squat", name: "Squat", setsDetailByWeek: sets)
        XCTAssertEqual(StartingWeightKind.classify(items: [item]), .trainingMax)
    }

    // MARK: - Lift order

    func testLiftsKeepProgramOrderNotAlphabetical() {
        let days = [[linear("Squat"), linear("Overhead Press")], [linear("Deadlift"), linear("Squat"), linear("Bench Press")]]
        XCTAssertEqual(ProgramLifts.ordered(days: days), ["Squat", "Overhead Press", "Deadlift", "Bench Press"])
    }

    func testSquatMovesFirstWhereItAppears() {
        let days = [[structured("Overhead Press", intensities: [0.85])], [structured("Squat", intensities: [0.85])]]
        XCTAssertEqual(ProgramLifts.ordered(days: days), ["Squat", "Overhead Press"])
    }

    func testLiftOrderSkipsAccessories() {
        let days = [[DayItem(type: .accessory, lift: "Curl", name: "Curl"), linear("Bench Press")]]
        XCTAssertEqual(ProgramLifts.ordered(days: days), ["Bench Press"])
    }

    func testTargetRepsReadsTheLiftsFirstAppearance() {
        let days = [[linear("Squat", reps: 3), structured("Bench Press", intensities: [1], reps: 10)]]
        XCTAssertEqual(ProgramLifts.targetReps(for: "Squat", days: days), 3)
        XCTAssertEqual(ProgramLifts.targetReps(for: "Bench Press", days: days), 10)
        XCTAssertEqual(ProgramLifts.targetReps(for: "Unknown", days: days), 5)
    }

    // MARK: - Starter table

    func testFirstWorkingWeightsInPounds() {
        XCTAssertEqual(starter("Squat"), 95)
        XCTAssertEqual(starter("Bench Press"), 75)
        XCTAssertEqual(starter("Barbell Row"), 75)
        XCTAssertEqual(starter("Overhead Press"), 55)
        XCTAssertEqual(starter("Deadlift"), 135)
    }

    func testFirstWorkingWeightsAreRoundInKilograms() {
        XCTAssertEqual(starter("Squat", metric: true), 40 * lbPerKg, accuracy: 0.001)
        XCTAssertEqual(starter("Bench Press", metric: true), 35 * lbPerKg, accuracy: 0.001)
        XCTAssertEqual(starter("Barbell Row", metric: true), 35 * lbPerKg, accuracy: 0.001)
        XCTAssertEqual(starter("Overhead Press", metric: true), 25 * lbPerKg, accuracy: 0.001)
        XCTAssertEqual(starter("Deadlift", metric: true), 60 * lbPerKg, accuracy: 0.001)
    }

    func testTrainingMaxStartersAreHigherAndLoadable() {
        XCTAssertEqual(starter("Squat", kind: .trainingMax), 110)
        XCTAssertEqual(starter("Bench Press", kind: .trainingMax), 90)
        XCTAssertEqual(starter("Overhead Press", kind: .trainingMax), 65)
        XCTAssertEqual(starter("Deadlift", kind: .trainingMax), 160)
        XCTAssertEqual(starter("Squat", metric: true, kind: .trainingMax), 47.5 * lbPerKg, accuracy: 0.001)
        XCTAssertEqual(starter("Deadlift", metric: true, kind: .trainingMax), 70 * lbPerKg, accuracy: 0.001)
    }

    func testVariationsGetTheirOwnStarters() {
        XCTAssertEqual(starter("Front Squat"), 75)
        XCTAssertEqual(starter("Paused Squat"), 95)
        XCTAssertEqual(starter("Romanian Deadlift"), 95)
        XCTAssertEqual(starter("Sumo Deadlift"), 135)
        XCTAssertEqual(starter("Incline Bench"), 65)
        XCTAssertEqual(starter("Close-Grip Bench"), 65)
        XCTAssertEqual(starter("Push Press"), 55)
    }

    func testBodyweightLiftsStartWithNoAddedWeight() {
        for lift in ["Weighted Dips", "Weighted Pull-Ups", "Pull-Ups", "Dips (Chest)", "Bench Dips", "Chin-Ups"] {
            XCTAssertEqual(starter(lift), 0, lift)
            XCTAssertEqual(starter(lift, metric: true), 0, lift)
            XCTAssertEqual(starter(lift, kind: .trainingMax), 0, lift)
        }
    }

    func testWeightedBodyweightLiftsHaveDistinctShortNames() {
        XCTAssertEqual(ExerciseLibrary.shortName(for: "Weighted Dips"), "DIP")
        XCTAssertEqual(ExerciseLibrary.shortName(for: "Weighted Pull-Ups"), "PU")
    }

    func testOnlyBodyweightLiftsAcceptZero() {
        XCTAssertTrue(StarterWeights.startsWithNoAddedWeight("Weighted Dips"))
        for lift in ["Machine Dips", "Assisted Pull-Ups", "Squat", "Bench Press", "EZ Bar Curl"] {
            XCTAssertFalse(StarterWeights.startsWithNoAddedWeight(lift), lift)
        }
    }

    func testNonBarbellAndUnknownLiftsStartAtTheBar() {
        XCTAssertEqual(starter("EZ Bar Curl"), 45)
        XCTAssertEqual(starter("Something Unknown"), 45)
        XCTAssertEqual(starter("Something Unknown", metric: true), kgBar, accuracy: 0.001)
    }

    func testStarterIsNeverBelowTheBar() {
        let result = StarterWeights.starter(for: "Overhead Press", useMetric: false, barWeight: 66, kind: .firstWorkingWeight)
        XCTAssertEqual(result, 66)
    }

    // MARK: - Estimate

    func testEstimateForTrainingMaxIsNinetyPercentOfE1RM() {
        // 135 x 5 -> e1RM 157.5, x 0.9 = 141.75, nearest 5 lb
        let result = StarterWeights.estimate(weightLifted: 135, reps: 5, kind: .trainingMax, targetReps: 5, useMetric: false, barWeight: 45)
        XCTAssertEqual(result, 140)
    }

    func testEstimateForFirstWorkingWeightUsesProgramReps() {
        // 135 x 5 is a 5 rep max of 135, x 0.9 = 121.5, nearest 5 lb
        let five = StarterWeights.estimate(weightLifted: 135, reps: 5, kind: .firstWorkingWeight, targetReps: 5, useMetric: false, barWeight: 45)
        XCTAssertEqual(five, 120)
        // A 10-rep program starts lighter from the same set: 157.5 / 1.333 x 0.9 = 106.3
        let ten = StarterWeights.estimate(weightLifted: 135, reps: 5, kind: .firstWorkingWeight, targetReps: 10, useMetric: false, barWeight: 45)
        XCTAssertEqual(ten, 105)
    }

    func testEstimateRoundsToKilogramSteps() throws {
        // 100 kg x 5 -> e1RM 116.67 kg, x 0.9 = 105 kg
        let result = try XCTUnwrap(StarterWeights.estimate(weightLifted: 100 * lbPerKg, reps: 5, kind: .trainingMax, targetReps: 5, useMetric: true, barWeight: kgBar))
        XCTAssertEqual(result, 105 * lbPerKg, accuracy: 0.001)
    }

    func testEstimateIsNeverBelowTheBar() {
        let result = StarterWeights.estimate(weightLifted: 20, reps: 5, kind: .firstWorkingWeight, targetReps: 5, useMetric: false, barWeight: 45)
        XCTAssertEqual(result, 45)
    }

    func testEstimateRejectsUnusableSets() {
        func estimate(_ weight: Double, _ reps: Int) -> Double? {
            StarterWeights.estimate(weightLifted: weight, reps: reps, kind: .trainingMax, targetReps: 5, useMetric: false, barWeight: 45)
        }
        XCTAssertNil(estimate(0, 5))
        XCTAssertNil(estimate(135, 0))
        XCTAssertNil(estimate(135, StarterWeights.maxEstimateReps + 1))
        XCTAssertNotNil(estimate(135, StarterWeights.maxEstimateReps))
    }

    // MARK: - Changing units during setup

    private func afterChange(_ stored: Double, lift: String = "Squat", toMetric: Bool) -> Double {
        StarterWeights.valueAfterUnitChange(
            stored, lift: lift, kind: .firstWorkingWeight,
            fromMetric: !toMetric, fromBarWeight: toMetric ? 45 : kgBar,
            toMetric: toMetric, toBarWeight: toMetric ? kgBar : 45
        )
    }

    func testTypedNumberKeepsItsDigitsWhenUnitChanges() {
        XCTAssertEqual(afterChange(100, toMetric: true), 100 * lbPerKg, accuracy: 0.001)
        XCTAssertEqual(afterChange(100 * lbPerKg, toMetric: false), 100, accuracy: 0.001)
    }

    func testUntouchedStarterBecomesTheOtherUnitsStarter() {
        XCTAssertEqual(afterChange(95, toMetric: true), 40 * lbPerKg, accuracy: 0.001)
        XCTAssertEqual(afterChange(40 * lbPerKg, toMetric: false), 95, accuracy: 0.001)
    }

    func testClearedValueStaysClearedWhenUnitChanges() {
        XCTAssertEqual(afterChange(0, toMetric: true), 0)
    }

    func testSameUnitChangesNothing() {
        let result = StarterWeights.valueAfterUnitChange(
            123, lift: "Squat", kind: .trainingMax,
            fromMetric: false, fromBarWeight: 45, toMetric: false, toBarWeight: 45
        )
        XCTAssertEqual(result, 123)
    }

    // MARK: - Locale default

    func testLocalePreference() {
        XCTAssertFalse(UnitDefaults.prefersMetric(locale: Locale(identifier: "en_US")))
        XCTAssertTrue(UnitDefaults.prefersMetric(locale: Locale(identifier: "de_DE")))
        XCTAssertTrue(UnitDefaults.prefersMetric(locale: Locale(identifier: "en_GB")))
    }

    func testBrandNewUserTakesLocaleUnits() {
        XCTAssertTrue(UnitDefaults.shouldApplyLocale(settings: .default, userData: UserData(), hasOnboardingDraft: false))
    }

    func testExistingUsersNeverTakeLocaleUnits() {
        var completed = UserData()
        completed.hasCompletedOnboarding = true
        XCTAssertFalse(UnitDefaults.shouldApplyLocale(settings: .default, userData: completed, hasOnboardingDraft: false))

        var withProgram = UserData()
        withProgram.selectedProgram = "stronglifts_5x5_12week"
        XCTAssertFalse(UnitDefaults.shouldApplyLocale(settings: .default, userData: withProgram, hasOnboardingDraft: false))

        var withMaxes = UserData()
        withMaxes.trainingMaxes = ["Squat": 225]
        XCTAssertFalse(UnitDefaults.shouldApplyLocale(settings: .default, userData: withMaxes, hasOnboardingDraft: false))

        XCTAssertFalse(UnitDefaults.shouldApplyLocale(settings: .default, userData: UserData(), hasOnboardingDraft: true))

        var movedBar = UserSettings.default
        movedBar.barWeight = 35
        XCTAssertFalse(UnitDefaults.shouldApplyLocale(settings: movedBar, userData: UserData(), hasOnboardingDraft: false))
    }

    // MARK: - Steps and drafts

    func testPersistedRawValuesAreStable() {
        XCTAssertEqual(SetupStep.welcome.rawValue, 0)
        XCTAssertEqual(SetupStep.program.rawValue, 1)
        XCTAssertEqual(SetupStep.exercises.rawValue, 2)
        XCTAssertEqual(SetupStep.trainingMaxes.rawValue, 3)
        XCTAssertEqual(SetupStep.summary.rawValue, 5)
        XCTAssertNil(SetupStep(rawValue: 4), "4 was the settings step and must not be reused")
    }

    func testIndicatorMatchesTheScreensThatShowIt() {
        XCTAssertEqual(SetupStep.indicatorSteps, [.program, .exercises, .trainingMaxes, .summary])
        XCTAssertEqual(SetupStep.indicatorSteps.map(\.title), ["Program", "Exercises", "Weights", "Review"])
    }

    func testDraftsFromAnyOldStepRestore() {
        func restored(_ step: Int, usable: Bool = true) -> SetupStep {
            SetupStep(restoringDraftStep: step, hasUsableMaxes: usable)
        }
        XCTAssertEqual(restored(0), .welcome)
        XCTAssertEqual(restored(1), .program)
        XCTAssertEqual(restored(2), .exercises)
        XCTAssertEqual(restored(3), .trainingMaxes)
        XCTAssertEqual(restored(4), .summary, "The removed settings step continues to Review")
        XCTAssertEqual(restored(5), .summary)
        XCTAssertEqual(restored(99), .program)
        XCTAssertEqual(restored(-1), .program)
    }

    func testReviewNeedsUsableWeights() {
        XCTAssertEqual(SetupStep(restoringDraftStep: 4, hasUsableMaxes: false), .trainingMaxes)
        XCTAssertEqual(SetupStep(restoringDraftStep: 5, hasUsableMaxes: false), .trainingMaxes)
    }

    func testOldDraftJSONStillDecodes() throws {
        let json = #"{"step":4,"selectedProgram":"stronglifts_5x5_12week","trainingMaxes":{"Squat":100,"Deadlift":100}}"#
        let draft = try JSONDecoder().decode(OnboardingDraft.self, from: Data(json.utf8))
        XCTAssertEqual(draft.selectedProgram, "stronglifts_5x5_12week")
        XCTAssertEqual(draft.trainingMaxes["Squat"], 100)
        XCTAssertEqual(draft.restoredStep, .summary)
    }

    func testDraftWithClearedOrMissingWeightsReopensOnWeights() {
        let cleared = OnboardingDraft(step: 5, selectedProgram: "p", trainingMaxes: ["Squat": 0, "Deadlift": 100])
        XCTAssertEqual(cleared.restoredStep, .trainingMaxes)
        let empty = OnboardingDraft(step: 4, selectedProgram: "p", trainingMaxes: [:])
        XCTAssertEqual(empty.restoredStep, .trainingMaxes)
    }
}
