import XCTest
@testable import SBSApp

/// Grouping and wording behind the History screens' sessions, log rows and progress cards
final class WorkoutHistoryTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func set(_ number: Int, weight: Double = 135, target: Int = 5, reps: Int? = 5,
                     amrap: Bool = false, completed: Bool = true) -> WorkoutSetRecord {
        WorkoutSetRecord(setNumber: number, weight: weight, targetReps: target, actualReps: reps,
                         isAMRAP: amrap, completed: completed)
    }

    private func record(_ when: Date, week: Int = 1, day: Int = 1, title: String? = "Workout A",
                        lift: String = "Squat", type: WorkoutExerciseType = .linear,
                        sets: [WorkoutSetRecord]) -> WorkoutRecord {
        WorkoutRecord(date: when, programId: "p", programName: "StrongLifts", week: week, day: day, dayTitle: title,
                      exercises: [WorkoutExerciseRecord(lift: lift, exerciseName: lift, trainingMax: 135, exerciseType: type, sets: sets)])
    }

    private func accessory(_ name: String, _ when: Date, weight: Double = 25) -> AccessoryRecord {
        AccessoryRecord(date: when, name: name, bodyPart: nil, weight: weight, sets: 3, reps: 10)
    }

    private func cycle(_ number: Int, from start: Int, to end: Int, records: [WorkoutRecord] = []) -> CompletedCycle {
        CompletedCycle(cycleNumber: number, startDate: date(start), endDate: date(end),
                       startingMaxes: ["Squat": 100], endingMaxes: ["Squat": 110], logs: [:],
                       lastCompletedWeek: 1, programName: "Old Program", workoutRecords: records)
    }

    private func list(records: [WorkoutRecord] = [], accessories: [AccessoryRecord] = [], cycleStart: Int = 20,
                      archived: [CompletedCycle] = [], includeArchived: Bool) -> HistorySessionList {
        HistorySessionBuilder.list(
            records: records, accessoryHistory: accessories, currentCycleStart: date(cycleStart),
            currentCycleNumber: 3, currentProgramName: "StrongLifts", archivedCycles: archived,
            includeArchived: includeArchived, calendar: calendar
        )
    }

    // MARK: - Set lines

    func testIdenticalLinearSetsCollapseIntoOneLine() {
        let lines = HistorySetLine.lines(from: (1...5).map { set($0) })
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].count, 5)
        XCTAssertEqual(lines[0].reps, 5)
        XCTAssertFalse(lines[0].missed)
    }

    func testMissedLinearSessionShowsTargetNotTheAssumedReps() {
        let lines = HistorySetLine.lines(from: (1...5).map { set($0, reps: 4, completed: false) })
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].missed)
        XCTAssertEqual(lines[0].reps, 5, "The saved 4 is a guess, so it isn't shown as a result")
    }

    func testAMRAPSetsStaySeparateAndInSetOrder() {
        let lines = HistorySetLine.lines(from: [
            set(8, weight: 185, target: 1, reps: 4, amrap: true),
            set(2, weight: 185, target: 1, reps: 4, amrap: true)
        ])
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.isAMRAP && $0.count == 1 })
    }

    // MARK: - Sessions

    func testSessionsNewestFirstAndEmptyRecordsDropped() {
        let empty = WorkoutRecord(date: date(23), programId: "p", programName: "P", week: 1, day: 3)
        let sessions = HistorySessionBuilder.sessions(
            records: [record(date(21), sets: [set(1)]), record(date(22), day: 2, sets: [set(1)]), empty],
            accessories: [], calendar: calendar
        )
        XCTAssertEqual(sessions.map(\.date), [date(22), date(21)])
    }

    func testExerciseWithNoSetsIsLeftOutOfItsSession() {
        var workout = record(date(21), sets: [set(1)])
        workout.exercises.append(WorkoutExerciseRecord(lift: "Row", exerciseName: "Row", trainingMax: 0, exerciseType: .linear))
        let sessions = HistorySessionBuilder.sessions(records: [workout], accessories: [], calendar: calendar)
        XCTAssertEqual(sessions.first?.exercises.map(\.name), ["Squat"])
    }

    func testBlankDayTitleFallsBackToDayNumber() {
        let sessions = HistorySessionBuilder.sessions(
            records: [record(date(21), day: 4, title: "  ", sets: [set(1)])], accessories: [], calendar: calendar
        )
        XCTAssertEqual(sessions.first?.title, "Day 4")
    }

    func testRedoOnALaterDateKeepsBothDatedSessions() {
        let sessions = HistorySessionBuilder.sessions(
            records: [record(date(21), lift: "Bench Press", sets: [set(1)]), record(date(24), sets: [set(1)])],
            accessories: [], calendar: calendar
        )
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.positionLabel), ["Week 1 · Day 1", "Week 1 · Day 1"])
    }

    func testAccessoryJoinsTheWorkoutUnderWayThatDay() {
        let morning = record(date(21, hour: 8), day: 1, sets: [set(1)])
        let evening = record(date(21, hour: 18), day: 2, sets: [set(1)])
        let sessions = HistorySessionBuilder.sessions(
            records: [morning, evening],
            accessories: [accessory("Curl", date(21, hour: 9)), accessory("Dip", date(21, hour: 19))],
            calendar: calendar
        )
        XCTAssertEqual(sessions.first { $0.id == morning.id }?.accessories.map(\.name), ["Curl"])
        XCTAssertEqual(sessions.first { $0.id == evening.id }?.accessories.map(\.name), ["Dip"])
    }

    func testAccessoryLoggedBeforeTheFirstSetJoinsThatDaysWorkout() {
        let workout = record(date(21, hour: 10), sets: [set(1)])
        let sessions = HistorySessionBuilder.sessions(
            records: [workout], accessories: [accessory("Curl", date(21, hour: 9))], calendar: calendar
        )
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].accessories.map(\.name), ["Curl"])
    }

    func testAccessoryOnlyDayGetsItsOwnSession() {
        let sessions = HistorySessionBuilder.sessions(
            records: [], accessories: [accessory("Curl", date(21)), accessory("Dip", date(21, hour: 13))], calendar: calendar
        )
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].title, "Accessories")
        XCTAssertNil(sessions[0].positionLabel)
        XCTAssertEqual(sessions[0].accessories.map(\.name), ["Curl", "Dip"])
    }

    func testRepeatedAccessoryEditsInASessionKeepTheLast() {
        let sessions = HistorySessionBuilder.sessions(
            records: [record(date(21, hour: 8), sets: [set(1)])],
            accessories: [accessory("Curl", date(21, hour: 9), weight: 20), accessory("Curl", date(21, hour: 10), weight: 30)],
            calendar: calendar
        )
        XCTAssertEqual(sessions[0].accessories.count, 1)
        XCTAssertEqual(sessions[0].accessories[0].weight, 30)
    }

    // MARK: - Free-tier gate

    func testWithoutFullHistoryNothingArchivedComesBack() {
        let old = cycle(1, from: 1, to: 10, records: [record(date(5), sets: [set(1)])])
        let result = list(
            records: [record(date(21), sets: [set(1)])],
            accessories: [accessory("Curl", date(5)), accessory("Dip", date(21))],
            archived: [old],
            includeArchived: false
        )
        XCTAssertEqual(result.sections.map(\.id), ["current"])
        XCTAssertEqual(result.sections[0].sessions.count, 1)
        XCTAssertEqual(result.sections[0].sessions[0].accessories.map(\.name), ["Dip"], "Accessories aren't archived with their cycle, so they need the date gate")
        XCTAssertEqual(result.lockedCycleCount, 1)
    }

    func testFreeAccountWithOnlyArchivedDataSeesNoSessionsButIsTold() {
        let old = cycle(1, from: 1, to: 10, records: [record(date(5), sets: [set(1)])])
        let result = list(archived: [old], includeArchived: false)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.lockedCycleCount, 1)
    }

    func testWithFullHistoryArchivedCyclesFollowCurrentNewestFirst() {
        let first = cycle(1, from: 1, to: 5, records: [record(date(3), sets: [set(1)])])
        let second = cycle(2, from: 6, to: 10, records: [record(date(8), sets: [set(1)])])
        let result = list(records: [record(date(21), sets: [set(1)])], archived: [first, second], includeArchived: true)
        XCTAssertEqual(result.sections.map(\.cycleNumber), [3, 2, 1])
        XCTAssertEqual(result.lockedCycleCount, 0)
    }

    func testArchivedAccessoriesJoinTheirCycleByDate() {
        let old = cycle(1, from: 1, to: 10, records: [record(date(5), sets: [set(1)])])
        let result = list(accessories: [accessory("Curl", date(5, hour: 13))], archived: [old], includeArchived: true)
        XCTAssertEqual(result.sections.first?.sessions.first?.accessories.map(\.name), ["Curl"])
    }

    func testCycleFromBeforeSessionRecordsFallsBackToItsSummary() {
        let legacy = cycle(1, from: 1, to: 10)
        let result = list(archived: [legacy], includeArchived: true)
        XCTAssertEqual(result.sections.count, 1)
        XCTAssertEqual(result.sections[0].cycleWithoutSessionRecords?.id, legacy.id)
        XCTAssertTrue(result.sections[0].sessions.isEmpty)
    }

    func testOldCycleJSONWithoutRecordsOrProgramStillDecodes() throws {
        let start = date(1).timeIntervalSinceReferenceDate
        let json = """
        {"id":"\(UUID().uuidString)","cycleNumber":1,"startDate":\(start),"endDate":\(start + 86400),
        "startingMaxes":{},"endingMaxes":{},"logs":{},"accessoryLogs":{},"lastCompletedWeek":1,
        "structuredLogs":{},"linearLogs":{},"tmHistory":{},"liftData":{},"workoutRecords":[]}
        """
        let decoded = try JSONDecoder().decode(CompletedCycle.self, from: Data(json.utf8))
        XCTAssertNil(decoded.programName)
        XCTAssertTrue(HistorySessionBuilder.sessions(for: decoded, accessoryHistory: [], calendar: calendar).isEmpty)
    }

    // MARK: - Accessory history

    func testAccessoryGroupsRespectTheGate() {
        let old = cycle(1, from: 1, to: 10)
        let records = [accessory("Curl", date(5)), accessory("Curl", date(21)), accessory("Dip", date(5))]

        let free = AccessoryHistoryBuilder.groups(
            accessoryHistory: records, currentCycleStart: date(20), archivedCycles: [old],
            includeArchived: false, calendar: calendar
        )
        XCTAssertEqual(free.map(\.name), ["Curl"])
        XCTAssertEqual(free[0].entries.count, 1)

        let premium = AccessoryHistoryBuilder.groups(
            accessoryHistory: records, currentCycleStart: date(20), archivedCycles: [old],
            includeArchived: true, calendar: calendar
        )
        XCTAssertEqual(premium.map(\.name), ["Curl", "Dip"], "Most recently trained first")
        XCTAssertEqual(premium[0].entries.count, 2)
    }

    func testAccessoriesFromADeletedCycleStayHidden() {
        let groups = AccessoryHistoryBuilder.groups(
            accessoryHistory: [accessory("Curl", date(5))], currentCycleStart: date(20), archivedCycles: [],
            includeArchived: true, calendar: calendar
        )
        XCTAssertTrue(groups.isEmpty)
    }

    func testAccessoryGroupKeepsOneEntryPerDayLastWins() {
        let groups = AccessoryHistoryBuilder.groups(
            accessoryHistory: [accessory("Curl", date(21, hour: 8), weight: 20), accessory("Curl", date(21, hour: 9), weight: 30)],
            currentCycleStart: date(20), archivedCycles: [], includeArchived: false, calendar: calendar
        )
        XCTAssertEqual(groups[0].entries.map(\.weight), [30])
    }

    // MARK: - Best set per week

    func testWeeklyBestDatesComeFromTheBestSetsWorkout() {
        let light = record(date(21), day: 1, type: .structured, sets: [set(0, weight: 100, reps: 5, amrap: true)])
        let heavy = record(date(23), day: 2, type: .structured, sets: [set(0, weight: 150, reps: 5, amrap: true)])
        let best = WeeklyBestSet.perWeek(records: [light, heavy], lift: "Squat")
        XCTAssertEqual(best.count, 1)
        XCTAssertEqual(best[0].weight, 150)
        XCTAssertEqual(best[0].date, date(23))
    }

    func testWeeklyBestMatchesAliasedLiftNames() {
        let workout = record(date(21), lift: "Bench", type: .structured, sets: [set(0, amrap: true)])
        XCTAssertEqual(WeeklyBestSet.perWeek(records: [workout], lift: "Bench Press").count, 1)
    }

    func testAMeasuredSetBeatsAHeavierMissedSession() {
        let missed = record(date(21), day: 1, sets: [set(1, weight: 140, reps: 4, completed: false)])
        let done = record(date(23), day: 2, sets: [set(1, weight: 135, reps: 5)])
        let best = WeeklyBestSet.perWeek(records: [missed, done], lift: "Squat")
        XCTAssertEqual(best[0].weight, 135)
        XCTAssertFalse(best[0].missedTarget)
    }

    func testWeekWithOnlyAMissedSessionIsFlaggedAndShowsTheTarget() {
        let missed = record(date(21), sets: [set(1, weight: 140, reps: 4, completed: false)])
        let best = WeeklyBestSet.perWeek(records: [missed], lift: "Squat")
        XCTAssertTrue(best[0].missedTarget)
        XCTAssertEqual(best[0].reps, 5)
    }

    // MARK: - Lift order

    func testProgramOrderKeepsFirstUseAndSkipsAccessories() {
        let order = HistoryLiftOrder.programOrder([
            (lift: "Squat", type: .linear),
            (lift: "Bench Press", type: .linear),
            (lift: "Curl", type: .accessory),
            (lift: "Row", type: .linear),
            (lift: "Squat", type: .linear),
            (lift: "Overhead Press", type: .linear),
            (lift: "Deadlift", type: .linear)
        ])
        XCTAssertEqual(order, ["Squat", "Bench Press", "Row", "Overhead Press", "Deadlift"])
    }

    func testArchivedCycleListsBigFourFirstAndSkipsLiftsWithNoEndValue() {
        var old = cycle(1, from: 1, to: 10)
        old.startingMaxes = ["Squat": 100, "Bench Press": 80, "Deadlift": 120, "Overhead Press": 60, "Arnold Press": 40, "Old Lift": 50]
        old.endingMaxes = ["Squat": 110, "Bench Press": 85, "Deadlift": 130, "Overhead Press": 65, "Arnold Press": 45]
        XCTAssertEqual(old.progressedLifts, ["Squat", "Bench Press", "Deadlift", "Overhead Press", "Arnold Press"])
    }

    // MARK: - Progress wording

    func testProgressKindFollowsProgramType() {
        XCTAssertEqual(LiftProgressKind.resolve(itemTypes: [.linear], manualProgression: false), .workingWeight)
        XCTAssertEqual(LiftProgressKind.resolve(itemTypes: [.structured], manualProgression: true), .fixedTrainingMax)
        XCTAssertEqual(LiftProgressKind.resolve(itemTypes: [.tm, .volume], manualProgression: false), .autoregulatedTrainingMax)
        XCTAssertEqual(LiftProgressKind.resolve(itemTypes: [], manualProgression: false), .notInProgram)
        XCTAssertEqual(LiftProgressKind.resolve(itemTypes: [.accessory], manualProgression: false), .notInProgram)
    }

    func testLinearSummaryTalksAboutWorkingWeight() {
        let summary = CycleProgressSummary(lifts: [
            LiftCycleProgress(lift: "Squat", kind: .workingWeight, start: 100, current: 105)
        ])
        XCTAssertEqual(summary.cardTitle, "Working Weight Progress")
        XCTAssertEqual(summary.totalLabel, "Total Weight Added")
        XCTAssertEqual(summary.totalGain, 5)
        XCTAssertEqual(summary.averagePercent, 5, accuracy: 0.001)
        XCTAssertTrue(summary.showsAverageBadge)
        XCTAssertFalse(LiftProgressKind.workingWeight.chartSubtitle.contains("Autoregulated"))
    }

    func testFixedTrainingMaxSummaryImpliesNoGainMidCycle() {
        let summary = CycleProgressSummary(lifts: [
            LiftCycleProgress(lift: "Squat", kind: .fixedTrainingMax, start: 200, current: 200)
        ])
        XCTAssertTrue(summary.isFixedThroughCycle)
        XCTAssertFalse(summary.showsAverageBadge)
        XCTAssertEqual(summary.cardTitle, "Training Maxes")
        XCTAssertFalse(summary.lifts[0].hasChange)
    }

    func testNoChangeShowsNoBadge() {
        let summary = CycleProgressSummary(lifts: [
            LiftCycleProgress(lift: "Squat", kind: .autoregulatedTrainingMax, start: 200, current: 200)
        ])
        XCTAssertFalse(summary.showsAverageBadge)
        XCTAssertFalse(summary.lifts[0].hasChange)
    }

    func testMixedProgramsUseNeutralWording() {
        let summary = CycleProgressSummary(lifts: [
            LiftCycleProgress(lift: "Squat", kind: .workingWeight, start: 100, current: 105),
            LiftCycleProgress(lift: "Bench Press", kind: .autoregulatedTrainingMax, start: 100, current: 100)
        ])
        XCTAssertEqual(summary.cardTitle, "Lift Progress")
        XCTAssertEqual(summary.averageLabel, "Avg Change")
    }

    // MARK: - Next linear weight

    private func linearState(_ logs: [Int: [Int: LinearLogEntry]], rounding: Double = 5) -> ProgramState {
        var item = DayItem(type: .linear, lift: "Squat", name: "Squat")
        item.sets = 5
        item.reps = 5
        return ProgramState(
            rounding: rounding,
            initialMaxes: ["Squat": 100],
            singleAt8Percent: [:],
            lifts: [:],
            days: [1: [item], 2: [item], 3: [item]],
            weeks: [1, 2],
            linearLogs: ["Squat": logs],
            linearProgressionConfig: LinearProgressionConfig(defaultIncrement: 5)
        )
    }

    func testNextWeightAfterASuccessIsTheIncreasedWeight() {
        let state = linearState([1: [1: LinearLogEntry(completed: true, weight: 100, usesUnroundedReplay: true)]])
        XCTAssertEqual(ProgramEngine().nextLinearWorkingWeight(state: state, lift: "Squat"), 105)
    }

    func testNextWeightAfterAFailureHolds() {
        let state = linearState([1: [1: LinearLogEntry(completed: false, consecutiveFailures: 1, weight: 100, usesUnroundedReplay: true)]])
        XCTAssertEqual(ProgramEngine().nextLinearWorkingWeight(state: state, lift: "Squat"), 100)
    }

    func testNextWeightWithNoLogsIsTheStartingWeight() {
        XCTAssertEqual(ProgramEngine().nextLinearWorkingWeight(state: linearState([:]), lift: "Squat"), 100)
    }

    func testNextWeightAnchorsOldLogsToTheirRecordedWeight() {
        // usesUnroundedReplay nil: an old log, whose next weight comes from what was lifted
        let state = linearState([1: [1: LinearLogEntry(completed: true, weight: 150)]])
        XCTAssertEqual(ProgramEngine().nextLinearWorkingWeight(state: state, lift: "Squat"), 155)
    }

    func testNextWeightMatchesWhatThePlanWouldComputeForTheNextSession() {
        let state = linearState([
            1: [1: LinearLogEntry(completed: true, weight: 150), 2: LinearLogEntry(completed: true, weight: 155, usesUnroundedReplay: true)]
        ])
        let engine = ProgramEngine()
        XCTAssertEqual(
            engine.nextLinearWorkingWeight(state: state, lift: "Squat"),
            engine.computeLinearWeightForSession(state: state, lift: "Squat", week: 1, day: 3).weight
        )
    }
}
