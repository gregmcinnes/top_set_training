import XCTest
@testable import SBSApp

/// A workout in progress must survive an app kill, and a bad saved copy must never get
/// in the way of launching.
final class WorkoutSessionPersistenceTests: XCTestCase {

    private final class MemoryStore: KeyValueStore {
        var values: [String: Data] = [:]
        func set(_ value: Data, forKey key: String) { values[key] = value }
        func data(forKey key: String) -> Data? { values[key] }
        func remove(forKey key: String) { values[key] = nil }
    }

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private var linear: WorkoutExercise {
        WorkoutExercise.fromLinear(name: "Squat", info: LinearExerciseInfo(
            lift: "Squat", weight: 225, sets: 5, reps: 5, consecutiveFailures: 1,
            increment: 5, isDeloadPending: false,
            logEntry: LinearLogEntry(completed: false, consecutiveFailures: 1, deloadApplied: false, weight: 225),
            calculatedWeight: 220
        ))
    }

    private var structured: WorkoutExercise {
        WorkoutExercise.fromStructured(name: "Bench", lift: "Bench", sets: [
            StructuredSetInfo(setIndex: 0, intensity: 0.75, targetReps: 5, isAMRAP: false, weight: 150),
            StructuredSetInfo(setIndex: 1, intensity: 0.95, targetReps: 1, isAMRAP: true, weight: 190, loggedReps: 4, calculatedWeight: 185)
        ])
    }

    private var volume: WorkoutExercise {
        WorkoutExercise.fromVolumeItem(name: "Row", lift: "Row", weight: 135, sets: 4, repsPerSet: 8, repOutTarget: 10, intensity: 0.7)
    }

    private var accessory: WorkoutExercise {
        WorkoutExercise.fromAccessory(name: "Curl", sets: 3, reps: 12, lastLogWeight: 30, lastWasEasy: true)
    }

    private func makeState() -> WorkoutState {
        let state = WorkoutState()
        state.exercises = [linear, structured, volume, accessory]
        return state
    }

    private func makeSession(state: WorkoutState? = nil, programId: String? = "stronglifts", lastUpdatedAt: Date? = nil, startedAt: Date? = nil) -> PersistedWorkoutSession {
        PersistedWorkoutSession(
            id: UUID(),
            week: 2,
            day: 3,
            programId: programId,
            cycleStartDate: now.addingTimeInterval(-86_400),
            startedAt: startedAt ?? now.addingTimeInterval(-600),
            lastUpdatedAt: lastUpdatedAt ?? now.addingTimeInterval(-60),
            watchWorkoutId: "watch-id",
            state: (state ?? makeState()).snapshot,
            pendingLinearExercise: nil,
            queuedLinearExercises: []
        )
    }

    private func roundTrip(_ session: PersistedWorkoutSession) throws -> PersistedWorkoutSession {
        try XCTUnwrap(PersistedWorkoutSession.decode(JSONEncoder().encode(session)))
    }

    override func tearDown() {
        RestTimerStatus.shared.timerCleared()
        super.tearDown()
    }

    // MARK: - Encoding

    func testEveryExerciseKindSurvivesEncoding() throws {
        let session = makeSession()
        XCTAssertEqual(try roundTrip(session), session)
    }

    func testExerciseIdsStayStableSoProgressStillMatches() throws {
        let state = makeState()
        let squat = state.exercises[0]
        state.completedSets[squat.id] = [1, 2]
        state.failedSets[squat.id] = [2]
        state.structuredLoggedReps[state.exercises[1].id] = [1: 7]

        let restored = WorkoutState(snapshot: try roundTrip(makeSession(state: state)).state, now: now)

        XCTAssertEqual(restored.exercises[0].id, squat.id)
        XCTAssertEqual(restored.completedSets[squat.id], [1, 2])
        XCTAssertEqual(restored.failedSets[squat.id], [2])
        XCTAssertEqual(restored.structuredLoggedReps[restored.exercises[1].id]?[1], 7)
        XCTAssertEqual(restored.currentSetCompletedCount, 2)
    }

    func testRepOutSetsAreTheSameAfterDecoding() throws {
        let restored = try roundTrip(makeSession()).state.exercises
        let (squat, bench, row, curl) = (restored[0], restored[1], restored[2], restored[3])

        XCTAssertFalse(squat.isRepOutSet(5), "Linear lifts have no rep-out")
        XCTAssertFalse(bench.isRepOutSet(1))
        XCTAssertTrue(bench.isRepOutSet(2), "Structured sets say for themselves")
        XCTAssertFalse(bench.isRepOutSet(3), "Past the end of the sets")
        XCTAssertFalse(row.isRepOutSet(3))
        XCTAssertTrue(row.isRepOutSet(4), "Volume work ends on its rep-out")
        XCTAssertFalse(curl.isRepOutSet(3), "Accessories have no rep-out")
    }

    func testSavedWeightsAreASnapshot() throws {
        let restored = try roundTrip(makeSession()).state.exercises
        XCTAssertEqual(restored[0].weight, 225)
        XCTAssertEqual(restored[0].calculatedWeight, 220)
        XCTAssertEqual(restored[0].linearInfo?.logEntry?.consecutiveFailures, 1)
        XCTAssertEqual(restored[1].structuredSetInfo?[1].weight, 190)
        XCTAssertEqual(restored[1].structuredSetInfo?[1].calculatedWeight, 185)
    }

    func testPendingLiftResultSurvivesEncoding() throws {
        var session = makeSession()
        session.pendingLinearExercise = session.state.exercises[0]
        session.queuedLinearExercises = [session.state.exercises[0]]

        let restored = try roundTrip(session)
        XCTAssertEqual(restored.pendingLinearExercise?.id, session.state.exercises[0].id)
        XCTAssertEqual(restored.queuedLinearExercises.count, 1)
    }

    func testPRsAndAMRAPResultsSurviveEncoding() throws {
        let state = makeState()
        state.prsAchieved = [WorkoutPRRecord(liftName: "Bench", weight: 190, reps: 4, newE1RM: 215, previousE1RM: nil)]
        state.amrapResults["Bench"] = WorkoutAMRAPResult(weight: 190, reps: 4, e1rm: 215)
        state.supersetAccessories[0] = SupersetAccessoryData(name: "Curl", sets: 3, reps: 12, weight: nil, lastWasEasy: true)

        let restored = WorkoutState(snapshot: try roundTrip(makeSession(state: state)).state, now: now)
        XCTAssertEqual(restored.prsAchieved, state.prsAchieved)
        XCTAssertEqual(restored.amrapResults["Bench"]?.e1rm, 215)
        XCTAssertEqual(restored.supersetAccessories[0]?.name, "Curl")
    }

    // MARK: - Rest Timer

    private func restingState(endDate: Date) -> WorkoutState {
        let state = makeState()
        state.timerDuration = 180
        state.timerIsRunning = true
        state.showingTimer = true
        state.timerEndDate = endDate
        return state
    }

    func testRunningRestResumesFromItsEndDate() throws {
        let endDate = now.addingTimeInterval(90)
        let saved = try roundTrip(makeSession(state: restingState(endDate: endDate))).state

        let restored = WorkoutState(snapshot: saved, now: now)

        XCTAssertTrue(restored.timerIsRunning)
        XCTAssertTrue(restored.showingTimer)
        XCTAssertEqual(restored.timerRemaining, 90)
        XCTAssertEqual(restored.timerDuration, 180, "The full duration still drives the ring")
        XCTAssertEqual(restored.timerEndDate, endDate)
        XCTAssertTrue(RestTimerStatus.shared.isActive)
        XCTAssertEqual(RestTimerStatus.shared.endDate, endDate)
    }

    func testRestThatExpiredWhileDeadIsClearedSilently() throws {
        let saved = try roundTrip(makeSession(state: restingState(endDate: now.addingTimeInterval(-5)))).state

        let restored = WorkoutState(snapshot: saved, now: now)

        XCTAssertFalse(restored.timerIsRunning)
        XCTAssertFalse(restored.showingTimer, "Lands on the next set, with nothing left to end")
        XCTAssertNil(restored.timerEndDate)
        XCTAssertFalse(RestTimerStatus.shared.isActive)
    }

    func testPausedRestStaysPausedWithItsRemainingTime() throws {
        let state = makeState()
        state.timerDuration = 180
        state.timerIsPaused = true
        state.showingTimer = true
        state.timerPausedRemaining = 42

        let restored = WorkoutState(snapshot: try roundTrip(makeSession(state: state)).state, now: now)

        XCTAssertTrue(restored.timerIsPaused)
        XCTAssertFalse(restored.timerIsRunning)
        XCTAssertEqual(restored.timerRemaining, 42)
        XCTAssertTrue(RestTimerStatus.shared.isPaused)
        XCTAssertEqual(RestTimerStatus.shared.remaining, 42)
    }

    func testTickingDoesNotChangeWhatGetsSaved() {
        let state = restingState(endDate: Date().addingTimeInterval(90))
        let before = state.snapshot
        state.timerRemaining = 12
        state.timerTick()
        XCTAssertEqual(state.snapshot, before)
    }

    // MARK: - Bad Saved Sessions

    func testCorruptDataIsRejectedRatherThanThrowing() {
        XCTAssertNil(PersistedWorkoutSession.decode(Data("not json".utf8)))
        XCTAssertNil(PersistedWorkoutSession.decode(Data()))
        XCTAssertNil(PersistedWorkoutSession.decode(Data("{\"week\":1}".utf8)), "Missing fields")
        XCTAssertNil(PersistedWorkoutSession.decode(Data("[1,2,3]".utf8)))
    }

    func testUnknownVersionIsRejected() throws {
        var session = makeSession()
        session.version = PersistedWorkoutSession.currentVersion + 1
        XCTAssertNil(PersistedWorkoutSession.decode(try JSONEncoder().encode(session)))
    }

    func testCorruptSessionLeavesUserDataAlone() throws {
        let persistence = ProgramPersistence(store: MemoryStore())
        var userData = UserData.empty
        userData.selectedProgram = "stronglifts"
        try persistence.saveUserData(userData)

        persistence.saveActiveWorkoutSession(Data("garbage".utf8))

        XCTAssertEqual(persistence.loadUserData().selectedProgram, "stronglifts")
        XCTAssertNil(persistence.corruptedUserDataBackup())
    }

    func testSavedSessionIsClearedByResetEverything() {
        let persistence = ProgramPersistence(store: MemoryStore())
        persistence.saveActiveWorkoutSession(Data("x".utf8))
        XCTAssertNotNil(persistence.loadActiveWorkoutSession())

        persistence.resetEverything()
        XCTAssertNil(persistence.loadActiveWorkoutSession())
    }

    func testClearingRemovesTheSavedSession() {
        let persistence = ProgramPersistence(store: MemoryStore())
        persistence.saveActiveWorkoutSession(Data("x".utf8))
        persistence.clearActiveWorkoutSession()
        XCTAssertNil(persistence.loadActiveWorkoutSession())
    }

    // MARK: - Fit For Resuming

    func testSessionFromAnotherProgramOrCycleIsNotResumable() {
        let session = makeSession()
        XCTAssertTrue(session.isResumable(programId: "stronglifts", cycleStartDate: session.cycleStartDate))
        XCTAssertFalse(session.isResumable(programId: "nsuns", cycleStartDate: session.cycleStartDate))
        XCTAssertFalse(session.isResumable(programId: "stronglifts", cycleStartDate: session.cycleStartDate.addingTimeInterval(3_600)))
    }

    func testSessionPointingAtNoRealSetIsNotResumable() {
        var session = makeSession()
        session.state.currentExerciseIndex = 99
        XCTAssertFalse(session.isResumable(programId: "stronglifts", cycleStartDate: session.cycleStartDate))

        session = makeSession()
        session.state.currentSetNumber = 6
        XCTAssertFalse(session.isResumable(programId: "stronglifts", cycleStartDate: session.cycleStartDate))

        session = makeSession()
        session.state.exercises = []
        XCTAssertFalse(session.isResumable(programId: "stronglifts", cycleStartDate: session.cycleStartDate))
    }

    func testStaleAfterTwelveHoursWithoutActivity() {
        let interval = PersistedWorkoutSession.staleInterval
        XCTAssertEqual(interval, 12 * 60 * 60)
        XCTAssertFalse(makeSession(lastUpdatedAt: now.addingTimeInterval(-interval + 60)).isStale(now: now))
        XCTAssertTrue(makeSession(lastUpdatedAt: now.addingTimeInterval(-interval - 60)).isStale(now: now))
    }

    func testFitnessWorkoutKeepsItsRealStartUnlessThatIsHalfADayAgo() {
        let recent = now.addingTimeInterval(-1_800)
        XCTAssertEqual(makeSession(startedAt: recent).fitnessStartDate(now: now), recent)

        let old = now.addingTimeInterval(-PersistedWorkoutSession.staleInterval - 60)
        XCTAssertEqual(makeSession(startedAt: old).fitnessStartDate(now: now), now)
    }

    // MARK: - Redoing A Day

    private func record(date: Date, lift: String = "Squat", sets: [Int], week: Int = 1, day: Int = 1, programId: String = "p") -> WorkoutRecord {
        var record = WorkoutRecord(date: date, programId: programId, programName: "P", week: week, day: day, dayTitle: "A")
        record.exercises = [WorkoutExerciseRecord(
            lift: lift, exerciseName: lift, trainingMax: 100, exerciseType: .linear,
            sets: sets.map { WorkoutSetRecord(setNumber: $0, weight: 100, targetReps: 5, actualReps: 5) }
        )]
        return record
    }

    func testRedoOnALaterDateReplacesTheEarlierHistory() {
        var userData = UserData.empty
        let cycleStart = now.addingTimeInterval(-864_000)
        userData.workoutRecords = [record(date: now.addingTimeInterval(-86_400), sets: [1, 2, 3, 4, 5])]

        userData.removeWorkoutSets(lift: "Squat", programId: "p", week: 1, day: 1, since: cycleStart)

        XCTAssertTrue(userData.workoutRecords.isEmpty, "An emptied workout goes too, or the day counts twice")
    }

    func testRedoLeavesOtherLiftsDaysAndCyclesAlone() {
        var userData = UserData.empty
        let cycleStart = now.addingTimeInterval(-864_000)
        var both = record(date: now, sets: [1, 2])
        both.exercises += record(date: now, lift: "Bench", sets: [1]).exercises
        userData.workoutRecords = [
            both,
            record(date: now, sets: [1], day: 2),
            record(date: now, sets: [1], week: 2),
            record(date: now, sets: [1], programId: "other"),
            record(date: cycleStart.addingTimeInterval(-60), sets: [1])
        ]

        userData.removeWorkoutSets(lift: "Squat", programId: "p", week: 1, day: 1, since: cycleStart)

        XCTAssertEqual(userData.workoutRecords.count, 5)
        XCTAssertEqual(userData.workoutRecords[0].exercises.map(\.lift), ["Bench"])
        XCTAssertEqual(userData.workoutRecords[1].exercises.first?.sets.count, 1)
    }

    func testRedoCanReplaceASingleSet() {
        var userData = UserData.empty
        let cycleStart = now.addingTimeInterval(-864_000)
        userData.workoutRecords = [record(date: now, sets: [0, 1, 2])]

        userData.removeWorkoutSets(lift: "Squat", programId: "p", week: 1, day: 1, setNumber: 1, since: cycleStart)

        XCTAssertEqual(userData.workoutRecords[0].exercises[0].sets.map(\.setNumber), [0, 2])
    }
}
