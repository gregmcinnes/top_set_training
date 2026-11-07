import XCTest
@testable import SBSApp

final class CycleProgressTests: XCTestCase {

    // MARK: - Tally

    private func tally(
        weeks: [Int] = [1, 2],
        days: [Int] = [1, 2],
        states: [[Int]: CycleProgress.DayState] = [:]
    ) -> CycleProgress.Tally {
        CycleProgress.tally(
            weeks: weeks,
            visibleDays: { _ in days },
            state: { states[[$0, $1]] ?? .notStarted }
        )
    }

    func testNothingDoneReadsZero() {
        XCTAssertEqual(tally().completedFraction, 0)
    }

    func testOnlyCompleteDaysMoveTheFraction() {
        let result = tally(states: [[1, 1]: .complete, [1, 2]: .partial])
        XCTAssertEqual(result.completedDays, 1)
        XCTAssertEqual(result.totalDays, 4)
        XCTAssertEqual(result.completedFraction, 0.25)
    }

    func testPartialDaysCountAsSessions() {
        let result = tally(states: [[1, 1]: .complete, [1, 2]: .partial])
        XCTAssertEqual(result.loggedDays, 2)
    }

    func testEveryDayCompleteReadsFull() {
        let all: [[Int]: CycleProgress.DayState] = [
            [1, 1]: .complete, [1, 2]: .complete, [2, 1]: .complete, [2, 2]: .complete
        ]
        XCTAssertEqual(tally(states: all).completedFraction, 1)
    }

    func testTallyHonorsDaysVisiblePerWeek() {
        // A/B alternation: week 1 shows days 1 and 2, week 2 shows only day 3
        let result = CycleProgress.tally(
            weeks: [1, 2],
            visibleDays: { $0 == 1 ? [1, 2] : [3] },
            state: { week, day in week == 2 && day == 3 ? .complete : .notStarted }
        )
        XCTAssertEqual(result.totalDays, 3)
        XCTAssertEqual(result.completedDays, 1)
    }

    func testNoDaysDoesNotDivideByZero() {
        XCTAssertEqual(tally(days: []).completedFraction, 0)
    }

    // MARK: - Gains

    func testGainsFollowTheGivenOrder() {
        let gains = CycleProgress.gains(
            liftOrder: ["Squat", "Bench", "Deadlift"],
            starting: ["Bench": 100, "Deadlift": 200, "Squat": 150],
            next: ["Bench": 105, "Deadlift": 210, "Squat": 160]
        )
        XCTAssertEqual(gains.map(\.lift), ["Squat", "Bench", "Deadlift"])
        XCTAssertEqual(gains.map(\.gain), [10, 5, 10])
    }

    func testUnchangedAndLoweredLiftsAreLeftOut() {
        let gains = CycleProgress.gains(
            liftOrder: ["Squat", "Bench", "Row"],
            starting: ["Squat": 150, "Bench": 100, "Row": 80],
            next: ["Squat": 150, "Bench": 95, "Row": 85]
        )
        XCTAssertEqual(gains.map(\.lift), ["Row"])
    }

    func testAGainTooSmallToDisplayIsLeftOut() {
        let gains = CycleProgress.gains(
            liftOrder: ["Squat"],
            starting: ["Squat": 150],
            next: ["Squat": 150.04]
        )
        XCTAssertTrue(gains.isEmpty)
    }

    func testASmallMetricGainStillCounts() {
        // 0.1 kg, the smallest change metric weights can show
        let tenthOfAKilo = 0.1 / 0.45359237
        let gains = CycleProgress.gains(
            liftOrder: ["Squat"],
            starting: ["Squat": 100],
            next: ["Squat": 100 + tenthOfAKilo]
        )
        XCTAssertEqual(gains.map(\.lift), ["Squat"])
    }

    func testALiftWithNoStartingValueIsNotAGainOfItsWholeWeight() {
        let gains = CycleProgress.gains(
            liftOrder: ["Squat", "Bench"],
            starting: ["Squat": 0],
            next: ["Squat": 225, "Bench": 135]
        )
        XCTAssertTrue(gains.isEmpty)
    }

    func testRepeatedLiftsInTheOrderAreShownOnce() {
        let gains = CycleProgress.gains(
            liftOrder: ["Squat", "Squat"],
            starting: ["Squat": 100],
            next: ["Squat": 110]
        )
        XCTAssertEqual(gains.count, 1)
    }

    // MARK: - Lifts in a plan

    private func linearItem(_ lift: String) -> PlanItem {
        .linear(name: lift, info: LinearExerciseInfo(
            lift: lift, weight: 100, sets: 5, reps: 5, consecutiveFailures: 0,
            increment: 5, isDeloadPending: false, logEntry: nil, calculatedWeight: 100
        ))
    }

    private func volumeItem(_ lift: String) -> PlanItem {
        .volume(
            name: lift, lift: lift, weight: 100, intensity: 0.7, sets: 4, repsPerSet: 8,
            repOutTarget: 10, loggedRepsLastSet: nil, nextWeekTmDelta: nil,
            isWeightOverridden: false, calculatedWeight: 100
        )
    }

    func testLinearLiftsAreListed() {
        XCTAssertEqual(
            CycleProgress.mainLifts(in: [linearItem("Squat"), linearItem("Bench Press")]),
            ["Squat", "Bench Press"]
        )
    }

    func testEveryMainLiftTypeIsListedInPlanOrder() {
        let plan: [PlanItem] = [
            volumeItem("Squat"),
            .structured(name: "T1 Bench", lift: "Bench", trainingMax: 100, sets: [], logEntry: nil),
            .tm(name: "Row TM", lift: "Row", trainingMax: 100, topSingleAt8: 90),
            linearItem("Deadlift")
        ]
        XCTAssertEqual(CycleProgress.mainLifts(in: plan), ["Squat", "Bench", "Row", "Deadlift"])
    }

    func testALiftInTheDayTwiceIsListedOnce() {
        let plan: [PlanItem] = [
            .tm(name: "Bench TM", lift: "Bench", trainingMax: 100, topSingleAt8: 90),
            .structured(name: "Bench Volume", lift: "Bench", trainingMax: 100, sets: [], logEntry: nil),
            .structured(name: "OHP", lift: "OHP", trainingMax: 60, sets: [], logEntry: nil)
        ]
        XCTAssertEqual(CycleProgress.mainLifts(in: plan), ["Bench", "OHP"])
    }

    func testAccessoriesAreNotMainLifts() {
        let plan: [PlanItem] = [
            linearItem("Squat"),
            .accessory(name: "Curls", sets: 3, reps: 10, lastLog: nil)
        ]
        XCTAssertEqual(CycleProgress.mainLifts(in: plan), ["Squat"])
    }

    // MARK: - Days without a main lift in the plan

    func testFallbackPrefersConfiguredLiftsOverAccessories() {
        let items = [
            DayItem(type: .structured, lift: "Squat", name: "T1 Squat"),
            DayItem(type: .accessory, lift: nil, name: "Curls")
        ]
        XCTAssertEqual(CycleProgress.fallbackLifts(from: items), ["Squat"])
    }

    func testAnAccessoryOnlyDayListsItsAccessories() {
        let items = [
            DayItem(type: .accessory, lift: nil, name: "Curls"),
            DayItem(type: .accessory, lift: nil, name: "Dips")
        ]
        XCTAssertEqual(CycleProgress.fallbackLifts(from: items), ["Curls", "Dips"])
    }

    // MARK: - Training max or working weight

    func testLinearProgramsDoNotUseTrainingMaxes() {
        let items = [
            DayItem(type: .linear, lift: "Squat", name: "Squat"),
            DayItem(type: .accessory, lift: nil, name: "Curls")
        ]
        XCTAssertFalse(CycleProgress.usesTrainingMaxes(items))
    }

    func testOtherProgramTypesUseTrainingMaxes() {
        for type in [DayItem.ItemType.tm, .volume, .structured] {
            XCTAssertTrue(CycleProgress.usesTrainingMaxes([DayItem(type: type, lift: "Squat", name: "Squat")]))
        }
    }

    // MARK: - Next workout at the end of a cycle

    func testNoWorkoutLeftEvenWhenTheLastDayIsPartial() {
        // A partly logged day isn't "not started", so nothing is next. Home shows the
        // completion card rather than a dead end.
        let states: [[Int]: CycleProgress.DayState] = [[2, 1]: .complete, [2, 2]: .partial]
        let next = NextWorkout.find(
            fromWeek: 2,
            weeks: [1, 2],
            visibleDays: { _ in [1, 2] },
            isNotStarted: { (states[[$0, $1]] ?? .notStarted) == .notStarted }
        )
        XCTAssertNil(next)
    }

    func testADayLeftInAnEarlierWeekIsNotOfferedFromTheHighestLoggedWeek() {
        let logged: Set<[Int]> = [[1, 1], [2, 1]]
        let next = NextWorkout.find(
            fromWeek: 2,
            weeks: [1, 2],
            visibleDays: { _ in [1, 2] },
            isNotStarted: { !logged.contains([$0, $1]) }
        )
        XCTAssertEqual(next?.week, 2)
        XCTAssertEqual(next?.day, 2)
    }
}
