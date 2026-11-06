import XCTest
@testable import SBSApp

/// Regressions from the November 2026 review: wrong weights and training maxes in
/// normal use of shipped programs.
final class ProgressionRegressionTests: XCTestCase {

    private let engine = ProgramEngine()

    private func structuredItem(_ name: String, lift: String, sets: [SetDetail]) -> DayItem {
        var item = DayItem(type: .structured, lift: lift, name: name)
        item.setsDetail = sets
        return item
    }

    private func linearState(
        rounding: Double,
        initial: Double,
        sessions: Int,
        useMetric: Bool = false,
        increment: Double = 5
    ) -> ProgramState {
        var item = DayItem(type: .linear, lift: "Squat", name: "Squat")
        item.sets = 5
        item.reps = 5
        var logs: [Int: [Int: LinearLogEntry]] = [:]
        for session in 1...sessions {
            logs[session, default: [:]][1] = LinearLogEntry(completed: true)
        }
        return ProgramState(
            rounding: rounding,
            initialMaxes: ["Squat": initial],
            singleAt8Percent: [:],
            lifts: [:],
            days: [1: [item]],
            weeks: Array(1...20),
            linearLogs: ["Squat": logs],
            linearProgressionConfig: LinearProgressionConfig(defaultIncrement: increment),
            useMetric: useMetric
        )
    }

    private func linearWeight(_ state: ProgramState, week: Int) throws -> Double {
        let plan = try engine.weekPlan(state: state, week: week)
        guard case let .linear(_, info)? = plan[1]?.first else {
            XCTFail("expected a linear item")
            return 0
        }
        return info.weight
    }

    // MARK: - Manual progression (5/3/1)

    func testManualProgressionHoldsTrainingMaxThroughTheCycle() {
        let sets = [SetDetail(intensity: 0.85, reps: 5, isAMRAP: true)]
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["Overhead Press": 100],
            singleAt8Percent: [:],
            lifts: [:],
            days: [1: [structuredItem("Overhead Press", lift: "Overhead Press", sets: sets)]],
            weeks: [1, 2, 3, 4],
            // Reps that would change the TM under automatic progression
            structuredLogs: ["Overhead Press": [
                1: [1: StructuredLogEntry(amrapReps: [0: 1])],
                2: [1: StructuredLogEntry(amrapReps: [0: 1])],
                3: [1: StructuredLogEntry(amrapReps: [0: 20])]
            ]],
            manualProgression: true
        )
        let info = engine.gatherStructuredLiftInfo(from: state)
        let tms = engine.computeStructuredTrainingMaxes(state: state, upToWeek: 5, structuredLiftInfo: info)
        for week in 1...5 {
            XCTAssertEqual(tms[week]?["Overhead Press"], 100, "week \(week)")
        }
    }

    // MARK: - Same lift on several days

    func testT1WinsOverT2RegardlessOfDayOrder() {
        // T2 on the earlier day; T1 has no 1+ set, so this exercised the fallback path
        let t2 = [SetDetail(intensity: 0.6, reps: 10, isAMRAP: true)]
        let t1 = [SetDetail(intensity: 0.85, reps: 3, isAMRAP: true)]
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["Squat": 200],
            singleAt8Percent: [:],
            lifts: [:],
            days: [
                1: [structuredItem("Squat T2", lift: "Squat", sets: t2)],
                2: [structuredItem("Squat T1", lift: "Squat", sets: t1)]
            ],
            weeks: [1, 2]
        )
        let info = engine.gatherStructuredLiftInfo(from: state)
        XCTAssertEqual(info["Squat"]?.targetReps, 3)
        XCTAssertEqual(info["Squat"]?.intensity, 0.85)
    }

    func testProgressionUsesTheHeaviestLoggedDayNotAnArbitraryOne() {
        // Both days log index 2. Dictionary order used to pick the reps at random.
        let heavy = [
            SetDetail(intensity: 0.7, reps: 5),
            SetDetail(intensity: 0.8, reps: 3),
            SetDetail(intensity: 0.95, reps: 1, isAMRAP: true)
        ]
        let light = [
            SetDetail(intensity: 0.5, reps: 5),
            SetDetail(intensity: 0.6, reps: 3),
            SetDetail(intensity: 0.7, reps: 1, isAMRAP: true)
        ]
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["Bench Press": 200],
            singleAt8Percent: [:],
            lifts: [:],
            days: [
                1: [structuredItem("Bench", lift: "Bench Press", sets: heavy)],
                5: [structuredItem("Light Bench", lift: "Bench Press", sets: light)]
            ],
            weeks: [1, 2],
            structuredLogs: ["Bench Press": [1: [
                1: StructuredLogEntry(amrapReps: [2: 6]),   // heavy: 5+ reps = +10
                5: StructuredLogEntry(amrapReps: [2: 1])    // light: stall
            ]]]
        )
        let info = engine.gatherStructuredLiftInfo(from: state)
        let tms = engine.computeStructuredTrainingMaxes(state: state, upToWeek: 2, structuredLiftInfo: info)
        XCTAssertEqual(tms[2]?["Bench Press"], 210)
    }

    func testDifferentTargetOnAnotherDayIsNotScoredAgainstTheMainSet() {
        // Reddit PPL shape: Bench 5+ on day 1, 10+ on day 4, same AMRAP index
        let fives = [SetDetail(intensity: 0.8, reps: 5), SetDetail(intensity: 0.8, reps: 5, isAMRAP: true)]
        let tens = [SetDetail(intensity: 0.6, reps: 10), SetDetail(intensity: 0.6, reps: 10, isAMRAP: true)]
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["Bench Press": 200],
            singleAt8Percent: [:],
            lifts: [:],
            days: [
                1: [structuredItem("Bench", lift: "Bench Press", sets: fives)],
                4: [structuredItem("Bench Volume", lift: "Bench Press", sets: tens)]
            ],
            weeks: [1, 2],
            // Only the 10+ day logged: 12 reps must not count as 7 over a target of 5
            structuredLogs: ["Bench Press": [1: [4: StructuredLogEntry(amrapReps: [1: 12])]]]
        )
        let info = engine.gatherStructuredLiftInfo(from: state)
        let tms = engine.computeStructuredTrainingMaxes(state: state, upToWeek: 2, structuredLiftInfo: info)
        XCTAssertEqual(tms[2]?["Bench Press"], 200)
    }

    // MARK: - Final week carry-over

    func testFinalWeekProgressionIsAvailableForCarryOver() {
        let sets = [SetDetail(intensity: 0.95, reps: 1, isAMRAP: true)]
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["Bench Press": 200],
            singleAt8Percent: [:],
            lifts: [:],
            days: [1: [structuredItem("Bench", lift: "Bench Press", sets: sets)]],
            weeks: [1, 2],
            structuredLogs: ["Bench Press": [2: [1: StructuredLogEntry(amrapReps: [0: 5])]]]
        )
        let info = engine.gatherStructuredLiftInfo(from: state)
        let tms = engine.computeStructuredTrainingMaxes(state: state, upToWeek: 3, structuredLiftInfo: info)
        XCTAssertEqual(tms[3]?["Bench Press"], 210)
    }

    // MARK: - Weight overrides

    private func fslState(overrideItemName: String?) -> ProgramState {
        let main = [
            SetDetail(intensity: 0.65, reps: 5),
            SetDetail(intensity: 0.75, reps: 5),
            SetDetail(intensity: 0.85, reps: 5, isAMRAP: true)
        ]
        let fsl = Array(repeating: SetDetail(intensity: 0.65, reps: 5), count: 5)
        return ProgramState(
            rounding: 5,
            initialMaxes: ["Bench Press": 200],
            singleAt8Percent: [:],
            lifts: [:],
            days: [1: [
                structuredItem("Bench Press", lift: "Bench Press", sets: main),
                structuredItem("Bench FSL", lift: "Bench Press", sets: fsl)
            ]],
            weeks: [1],
            logs: ["Bench Press": [1: [1: LogEntry(weightOverride: 150, overrideItemName: overrideItemName)]]]
        )
    }

    private func structuredSets(_ plan: [PlanItem]?, named name: String) -> [StructuredSetInfo] {
        for item in plan ?? [] {
            if case let .structured(itemName, _, _, sets, _) = item, itemName == name {
                return sets
            }
        }
        XCTFail("no structured item named \(name)")
        return []
    }

    func testOverrideOnMainWorkDoesNotLeakToFSLSets() throws {
        let plan = try engine.weekPlan(state: fslState(overrideItemName: "Bench Press"), week: 1)[1]
        XCTAssertEqual(structuredSets(plan, named: "Bench Press").last?.weight, 150)
        XCTAssertEqual(structuredSets(plan, named: "Bench FSL").map(\.weight), Array(repeating: 130, count: 5))
    }

    func testOverrideOnFSLDoesNotChangeTheMainTopSet() throws {
        let plan = try engine.weekPlan(state: fslState(overrideItemName: "Bench FSL"), week: 1)[1]
        XCTAssertEqual(structuredSets(plan, named: "Bench Press").last?.weight, 170)
        XCTAssertEqual(structuredSets(plan, named: "Bench FSL").first?.weight, 150)
    }

    func testOverrideSavedBeforeItemNamesExistedAppliesToTheHeaviestItem() throws {
        let plan = try engine.weekPlan(state: fslState(overrideItemName: nil), week: 1)[1]
        XCTAssertEqual(structuredSets(plan, named: "Bench Press").last?.weight, 150)
        XCTAssertEqual(structuredSets(plan, named: "Bench FSL").first?.weight, 130)
    }

    func testLogEntryDecodesWithoutOverrideItemName() throws {
        let json = #"{"note":"","weightOverride":150}"#.data(using: .utf8)!
        let entry = try JSONDecoder().decode(LogEntry.self, from: json)
        XCTAssertEqual(entry.weightOverride, 150)
        XCTAssertNil(entry.overrideItemName)
    }

    func testLiftRecordDecodesWithoutDay() throws {
        let original = LiftRecord(liftName: "Squat", weight: 100, reps: 5)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        object.removeValue(forKey: "day")
        let decoded = try JSONDecoder().decode(LiftRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.day)
    }

    func testLinearOverrideAppliesAndProgressesFromWhatWasLifted() throws {
        var state = linearState(rounding: 5, initial: 200, sessions: 1)
        state.logs = ["Squat": [2: [1: LogEntry(weightOverride: 180)]]]
        XCTAssertEqual(try linearWeight(state, week: 2), 180)

        state.linearLogs["Squat"]?[2] = [1: LinearLogEntry(completed: true)]
        XCTAssertEqual(try linearWeight(state, week: 3), 185)
    }

    // MARK: - Linear rounding

    func testMetricLinearProgressionDoesNotStallOnA5KgGrid() throws {
        let fiveKg = 5 / 0.45359237
        let start = 60 / 0.45359237
        // +2.5 kg per session: four sessions must have added 10 kg
        let state = linearState(rounding: fiveKg, initial: start, sessions: 4, useMetric: true)
        XCTAssertEqual(try linearWeight(state, week: 5) * 0.45359237, 70, accuracy: 0.01)
    }

    func testPoundLinearProgressionDoesNotDoubleOnA10LbGrid() throws {
        // +5 lb per session: four sessions must have added 20 lb, not 40
        let state = linearState(rounding: 10, initial: 100, sessions: 4)
        XCTAssertEqual(try linearWeight(state, week: 5), 120)
    }

    // MARK: - History corrections

    private func dataWithPR(_ e1rm: Double, week: Int, day: Int, since: Date) -> UserData {
        var data = UserData.empty
        data.recordLift(LiftRecord(date: since.addingTimeInterval(-1000), liftName: "Squat", weight: 200, reps: 5, programId: "p", week: 1, setType: "5+"))
        data.recordLift(LiftRecord(date: since.addingTimeInterval(10), liftName: "Squat", weight: 200, reps: 5, estimatedOneRM: e1rm, programId: "p", week: week, setType: "5+", day: day))
        return data
    }

    func testRemovingATypoRecordRestoresThePreviousPR() {
        let since = Date()
        var data = dataWithPR(9999, week: 2, day: 1, since: since)
        XCTAssertEqual(data.personalRecords["Squat"]?.estimatedOneRM, 9999)

        data.removeLiftRecords(liftName: "Squat", programId: "p", week: 2, day: 1, since: since)

        XCTAssertEqual(data.liftHistory.count, 1)
        XCTAssertEqual(data.personalRecords["Squat"]?.estimatedOneRM ?? 0, 200 * (1 + 5.0 / 30), accuracy: 0.001)
    }

    func testRemovalLeavesEarlierCyclesAndOtherSessionsAlone() {
        let since = Date()
        var data = dataWithPR(9999, week: 2, day: 1, since: since)
        data.removeLiftRecords(liftName: "Squat", programId: "p", week: 2, day: 3, since: since)
        XCTAssertEqual(data.liftHistory.count, 2)
        XCTAssertEqual(data.personalRecords["Squat"]?.estimatedOneRM, 9999)
    }

    func testFailedSessionCannotSetAPR() {
        var data = UserData.empty
        data.recordLift(LiftRecord(liftName: "Squat", weight: 500, reps: 4, setType: "5×5 (failed)"), updatesPR: false)
        XCTAssertNil(data.personalRecords["Squat"])
        XCTAssertEqual(data.liftHistory.count, 1)
    }

    // MARK: - Input

    func testDecimalInputAcceptsEitherSeparatorAndRejectsNonFinite() {
        XCTAssertEqual(parseDecimalInput("102,5"), 102.5)
        XCTAssertEqual(parseDecimalInput(" 102.5 "), 102.5)
        XCTAssertNil(parseDecimalInput(""))
        XCTAssertNil(parseDecimalInput("nan"))
        XCTAssertNil(parseDecimalInput("1e999"))
    }

    func testMetricWeightEntryRoundTripsThroughStoredPounds() {
        let stored = 100.0.poundsFromInput(useMetric: true)
        XCTAssertEqual(stored, 220.462, accuracy: 0.001)
        XCTAssertEqual(stored.weightInputText(useMetric: true), "100.0")
        XCTAssertEqual(225.0.weightInputText(useMetric: false), "225.0")
    }

    func testAMRAPPreviewMatchesEngineInMetric() {
        let context = StructuredProgressionContext(liftName: "Bench Press", useMetric: true)
        // 3+ over target on an upper lift: +10 lb, which is +5 kg for a metric user
        XCTAssertEqual(context.weightAdjustment(reps: 8, target: 5), 5)
    }

    // MARK: - Program data

    func testNSuns4DayOverheadPressMatchesOtherNSunsSchemes() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "nsuns_4day_12week", withExtension: "json"))
        let program = try JSONDecoder().decode(ProgramData.self, from: Data(contentsOf: url))
        let press = try XCTUnwrap(program.days.values.flatMap { $0 }.first { $0.lift == "Overhead Press" && $0.setsDetail?.count == 9 })
        XCTAssertEqual(press.setsDetail?[4].reps, 3)
    }
}

/// Second round, from reviewing the fixes above.
final class ProgressionUpdateSafetyTests: XCTestCase {

    private let engine = ProgramEngine()

    private func state(rounding: Double, entries: [LinearLogEntry], useMetric: Bool = false) -> ProgramState {
        var item = DayItem(type: .linear, lift: "Squat", name: "Squat")
        item.sets = 5
        item.reps = 5
        var logs: [Int: [Int: LinearLogEntry]] = [:]
        for (index, entry) in entries.enumerated() {
            logs[index + 1, default: [:]][1] = entry
        }
        return ProgramState(
            rounding: rounding,
            initialMaxes: ["Squat": 100],
            singleAt8Percent: [:],
            lifts: [:],
            days: [1: [item]],
            weeks: Array(1...20),
            linearLogs: ["Squat": logs],
            linearProgressionConfig: LinearProgressionConfig(defaultIncrement: 5),
            useMetric: useMetric
        )
    }

    func testLogsFromBeforeTheUpdateProgressFromWhatWasLifted() {
        // Old 10 lb rounding doubled progress: 100 -> 110 -> 120 -> 130 actually lifted.
        // The next session must follow on from 130, not drop back to a recomputed 115.
        let lifted: [Double] = [110, 120, 130]
        let entries = lifted.map { LinearLogEntry(completed: true, weight: $0) }
        let (weight, _) = engine.computeLinearWeightForSession(state: state(rounding: 10, entries: entries), lift: "Squat", week: 4, day: 1)
        XCTAssertGreaterThanOrEqual(weight, 130)
        XCTAssertLessThanOrEqual(weight, 140)
    }

    func testNewLogsReplayFromTheUnroundedRunningWeight() {
        // +5 lb per session on a 10 lb grid: four new logs add 20 lb, however they displayed
        let entries = Array(repeating: LinearLogEntry(completed: true, weight: 110, usesUnroundedReplay: true), count: 4)
        let (weight, _) = engine.computeLinearWeightForSession(state: state(rounding: 10, entries: entries), lift: "Squat", week: 5, day: 1)
        XCTAssertEqual(weight, 120)
    }

    func testOldLinearLogEntriesStillDecode() throws {
        let json = #"{"completed":true,"consecutiveFailures":0,"deloadApplied":false,"weight":135,"note":""}"#.data(using: .utf8)!
        let entry = try JSONDecoder().decode(LinearLogEntry.self, from: json)
        XCTAssertEqual(entry.weight, 135)
        XCTAssertNil(entry.usesUnroundedReplay)
    }

    func testRemovingOneAMRAPSetLeavesAnotherWithTheSameTarget() {
        let since = Date()
        var data = UserData.empty
        data.recordLift(LiftRecord(date: since.addingTimeInterval(1), liftName: "Bench Press", weight: 225, reps: 8, programId: "p", week: 1, setType: "5+", day: 1, setIndex: 0))
        data.recordLift(LiftRecord(date: since.addingTimeInterval(2), liftName: "Bench Press", weight: 225, reps: 6, programId: "p", week: 1, setType: "5+", day: 1, setIndex: 3))

        data.removeLiftRecords(liftName: "Bench Press", programId: "p", week: 1, day: 1, setIndex: 3, since: since)

        XCTAssertEqual(data.liftHistory.map(\.reps), [8])
        XCTAssertEqual(data.personalRecords["Bench Press"]?.reps, 8)
    }

    func testManualCycleIncrementMatchesTheProgramDescription() {
        XCTAssertEqual(engine.manualCycleIncrement(lift: "Bench Press", useMetric: false), 5)
        XCTAssertEqual(engine.manualCycleIncrement(lift: "Squat", useMetric: false), 10)
        XCTAssertEqual(engine.manualCycleIncrement(lift: "Deadlift", useMetric: true) * 0.45359237, 5, accuracy: 0.0001)
    }
}
