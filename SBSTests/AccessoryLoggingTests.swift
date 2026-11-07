import XCTest
@testable import SBSApp

/// What a finished session writes for its accessories, and the weight pad's input rules
final class AccessoryLoggingTests: XCTestCase {

    private func accessory(_ name: String = "Face Pull", sets: Int = 3, reps: Int = 12, weight: Double? = 25) -> WorkoutExercise {
        WorkoutExercise.fromAccessory(name: name, sets: sets, reps: reps, lastLogWeight: weight)
    }

    private func linear(_ lift: String = "Squat", sets: Int = 5) -> WorkoutExercise {
        WorkoutExercise.fromLinear(name: lift, info: LinearExerciseInfo(
            lift: lift, weight: 135, sets: sets, reps: 5, consecutiveFailures: 0,
            increment: 5, isDeloadPending: false, logEntry: nil))
    }

    // MARK: - Which accessories count as performed

    func testOnlyAccessoriesWithSetsDoneAreLogged() {
        let state = WorkoutState()
        let done = accessory("Face Pull")
        let untouched = accessory("Curl")
        state.exercises = [done, untouched]
        state.completedSets[done.id] = [1, 2]

        XCTAssertEqual(state.performedAccessories, [
            PerformedAccessory(name: "Face Pull", weight: 25, sets: 2, reps: 12, wasEasy: nil)
        ])
    }

    func testAWeightEditWithNoSetsDoneLogsNothing() {
        let state = WorkoutState()
        var edited = accessory()
        edited.weight = 40
        edited.markedEasy = true
        state.exercises = [edited]

        XCTAssertTrue(state.performedAccessories.isEmpty)
    }

    func testTheSessionsWeightAndEasyMarkAreWhatGetLogged() {
        let state = WorkoutState()
        var edited = accessory()
        edited.weight = 40
        edited.markedEasy = true
        state.exercises = [edited]
        state.completedSets[edited.id] = [1]

        XCTAssertEqual(state.performedAccessories.first?.weight, 40)
        XCTAssertEqual(state.performedAccessories.first?.wasEasy, true)
    }

    func testAnUndoneSetIsNotLogged() {
        let state = WorkoutState()
        let exercise = accessory()
        state.exercises = [exercise]
        state.markSetComplete(undo: SetUndoInfo())
        XCTAssertEqual(state.performedAccessories.first?.sets, 1)

        _ = state.reopenSet(exerciseId: exercise.id, setNumber: 1)
        XCTAssertTrue(state.performedAccessories.isEmpty)
    }

    func testAStopWithLiftsOpenStillLogsAccessoriesDone() {
        let state = WorkoutState()
        let lift = linear()
        let extra = accessory()
        state.exercises = [lift, extra]
        state.completedSets[extra.id] = [1]
        state.finishedEarly = true

        XCTAssertEqual(state.performedAccessories.map(\.name), ["Face Pull"])
    }

    func testABodyweightAccessoryLogsAtZero() {
        let state = WorkoutState()
        let exercise = accessory("Plank", weight: nil)
        state.exercises = [exercise]
        state.completedSets[exercise.id] = [1]

        XCTAssertEqual(state.performedAccessories.first?.weight, 0)
    }

    // MARK: - Supersets

    func testASupersetAccessoryRidesAlongWithItsLift() {
        let state = WorkoutState()
        let lift = linear(sets: 5)
        state.exercises = [lift]
        state.supersetAccessories[0] = SupersetAccessoryData(name: "Curl", sets: 3, reps: 10, weight: 30)
        XCTAssertTrue(state.performedAccessories.isEmpty, "Nothing done on the pair yet")

        state.completedSets[lift.id] = [1, 2]
        XCTAssertEqual(state.performedAccessories, [
            PerformedAccessory(name: "Curl", weight: 30, sets: 2, reps: 10, wasEasy: nil)
        ])

        state.completedSets[lift.id] = [1, 2, 3, 4, 5]
        XCTAssertEqual(state.performedAccessories.first?.sets, 3, "Capped at the accessory's own sets")
    }

    func testThePairStaysOnScreenThroughTheRestAfterTheLiftsLastSet() {
        let state = WorkoutState()
        let lift = linear(sets: 1)
        let extra = accessory("Face Pull")
        state.exercises = [lift, extra]
        state.supersetAccessories[0] = SupersetAccessoryData(name: "Curl", sets: 1, reps: 10, weight: 30)

        state.markSetComplete(undo: SetUndoInfo())
        XCTAssertEqual(state.currentExercise?.name, "Face Pull", "The workout has moved on")
        state.startTimer(duration: 60, forExercise: lift.id)
        XCTAssertEqual(state.currentSupersetAccessory?.name, "Curl")

        state.setCurrentSupersetAccessoryWeight(35)
        XCTAssertEqual(state.supersetAccessories[0]?.weight, 35)

        state.skipTimer()
        XCTAssertNil(state.currentSupersetAccessory, "The rest is over")
    }

    func testAccessoriesAreLoggedInWorkoutOrder() {
        let state = WorkoutState()
        let lift = linear()
        let extra = accessory("Face Pull")
        state.exercises = [lift, extra]
        state.supersetAccessories[0] = SupersetAccessoryData(name: "Curl", sets: 3, reps: 10, weight: nil)
        state.completedSets[lift.id] = [1]
        state.completedSets[extra.id] = [1]

        XCTAssertEqual(state.performedAccessories.map(\.name), ["Curl", "Face Pull"])
    }

    // MARK: - Writing the log

    func testRecordingKeepsTheLastLogsNoteButDoesNotCopyItToTheNewEntry() {
        var data = UserData()
        data.accessoryLogs["Curl"] = AccessoryLog(weight: 20, sets: 3, reps: 10, note: "Use the EZ bar", wasEasy: true)
        let when = Date(timeIntervalSince1970: 1_000)

        data.recordPerformedAccessory(
            PerformedAccessory(name: "Curl", weight: 25, sets: 2, reps: 10, wasEasy: nil),
            bodyPart: nil,
            date: when
        )

        XCTAssertEqual(data.accessoryLogs["Curl"], AccessoryLog(weight: 25, sets: 2, reps: 10, note: "Use the EZ bar", wasEasy: nil))
        XCTAssertEqual(data.accessoryHistory.count, 1)
        XCTAssertEqual(data.accessoryHistory[0].date, when)
        XCTAssertEqual(data.accessoryHistory[0].sets, 2)
        XCTAssertEqual(data.accessoryHistory[0].note, "")
    }

    func testRecordingLeavesEarlierHistoryAlone() {
        let earlier = AccessoryRecord(date: Date(timeIntervalSince1970: 1), name: "Curl", bodyPart: nil, weight: 20, sets: 3, reps: 10, note: "old")
        var data = UserData(accessoryHistory: [earlier])

        data.recordPerformedAccessory(
            PerformedAccessory(name: "Curl", weight: 25, sets: 3, reps: 10, wasEasy: nil),
            bodyPart: nil,
            date: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(data.accessoryHistory.first, earlier)
    }

    func testDataSavedBeforeAccessoryDaysDoneStillDecodes() throws {
        let data = try JSONDecoder().decode(UserData.self, from: Data(#"{"hasCompletedOnboarding":true}"#.utf8))
        XCTAssertEqual(data.accessoryDaysDone, [:])
    }

    func testAccessoryDaysDoneSurviveASave() throws {
        var data = UserData()
        data.accessoryDaysDone[2] = [1, 3]
        let decoded = try JSONDecoder().decode(UserData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.accessoryDaysDone, [2: [1, 3]])
    }

    // MARK: - Joining a workout in History

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func at(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour))!
    }

    private func squatRecord(_ date: Date) -> WorkoutRecord {
        WorkoutRecord(date: date, programId: "p", programName: "P", week: 1, day: 1, dayTitle: "A", exercises: [
            WorkoutExerciseRecord(lift: "Squat", exerciseName: "Squat", trainingMax: 135, exerciseType: .linear, sets: [
                WorkoutSetRecord(setNumber: 1, weight: 135, targetReps: 5, actualReps: 5, isAMRAP: false, completed: true)
            ])
        ])
    }

    private func curl(_ date: Date) -> AccessoryRecord {
        AccessoryRecord(date: date, name: "Curl", bodyPart: nil, weight: 25, sets: 3, reps: 10, note: "")
    }

    func testAccessoriesFinishedBeforeTheLiftsAreStillOneWorkout() {
        let sessions = HistorySessionBuilder.sessions(records: [squatRecord(at(hour: 18))], accessories: [curl(at(hour: 9))], calendar: calendar)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].accessories.map(\.name), ["Curl"])
    }

    func testAccessoriesFinishedAfterTheLiftsAreStillOneWorkout() {
        let sessions = HistorySessionBuilder.sessions(records: [squatRecord(at(hour: 9))], accessories: [curl(at(hour: 18))], calendar: calendar)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].accessories.map(\.name), ["Curl"])
    }

    // MARK: - Weight pad

    func testPadBuildsADecimalWeight() {
        var text = ""
        for digit in [1, 3, 5] { text = WeightPadInput.appending(digit: digit, to: text) }
        text = WeightPadInput.appendingSeparator(".", to: text)
        text = WeightPadInput.appending(digit: 5, to: text)
        XCTAssertEqual(text, "135.5")
        XCTAssertEqual(parseDecimalInput(text), 135.5)
    }

    func testPadAllowsOneSeparatorAndLimitsDigits() {
        XCTAssertEqual(WeightPadInput.appendingSeparator(".", to: "12.5"), "12.5")
        XCTAssertEqual(WeightPadInput.appendingSeparator(",", to: "12,5"), "12,5")
        XCTAssertEqual(WeightPadInput.appending(digit: 9, to: "12.25"), "12.25")
        XCTAssertEqual(WeightPadInput.appending(digit: 9, to: "1234"), "1234")
    }

    func testPadStartsADecimalFromZeroAndDropsALeadingZero() {
        XCTAssertEqual(WeightPadInput.appendingSeparator(".", to: ""), "0.")
        XCTAssertEqual(WeightPadInput.appending(digit: 7, to: "0"), "7")
        XCTAssertEqual(WeightPadInput.appending(digit: 5, to: "0."), "0.5")
    }

    func testPadCanEnterZero() {
        XCTAssertEqual(parseDecimalInput(WeightPadInput.appending(digit: 0, to: "")), 0)
    }

    func testPadReadsACommaSeparator() {
        XCTAssertEqual(parseDecimalInput(WeightPadInput.appending(digit: 5, to: "102,")), 102.5)
    }
}
