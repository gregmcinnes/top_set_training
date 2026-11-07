import XCTest
@testable import SBSApp

/// The rules behind finishing, undoing and resting that the workout screen relies on
final class WorkoutFlowTests: XCTestCase {

    private func linear(_ name: String, sets: Int = 3) -> WorkoutExercise {
        WorkoutExercise.fromLinear(name: name, info: LinearExerciseInfo(
            lift: name, weight: 100, sets: sets, reps: 5, consecutiveFailures: 0,
            increment: 5, isDeloadPending: false, logEntry: nil, calculatedWeight: 100
        ))
    }

    private func makeState(_ exercises: [WorkoutExercise]) -> WorkoutState {
        let state = WorkoutState()
        state.exercises = exercises
        return state
    }

    private func completeAllSets(of index: Int, in state: WorkoutState) {
        state.jumpToExercise(index)
        for _ in 0..<state.exercises[index].totalSets { state.markSetComplete() }
    }

    // MARK: - PRs

    func testFirstEverLogIsABaselineNotAPR() {
        XCTAssertFalse(E1RM.isNewPR(newE1RM: 150, previousE1RM: nil))
    }

    func testOnlyBeatingThePreviousBestIsAPR() {
        XCTAssertTrue(E1RM.isNewPR(newE1RM: 151, previousE1RM: 150))
        XCTAssertFalse(E1RM.isNewPR(newE1RM: 150, previousE1RM: 150))
        XCTAssertFalse(E1RM.isNewPR(newE1RM: 149, previousE1RM: 150))
    }

    // MARK: - Completion

    func testFinishingOnlyTheLastExerciseDoesNotCompleteTheWorkout() {
        let state = makeState([linear("Squat"), linear("Bench")])
        completeAllSets(of: 1, in: state)

        XCTAssertFalse(state.isWorkoutComplete)
        XCTAssertFalse(state.isFinished)
        XCTAssertTrue(state.reachedEndWithOpenExercises)
        XCTAssertEqual(state.firstOpenExerciseIndex, 0)
        XCTAssertEqual(state.remainingSetsCount, 3)
    }

    func testFinishingEverythingCompletesTheWorkout() {
        let state = makeState([linear("Squat"), linear("Bench")])
        completeAllSets(of: 0, in: state)
        XCTAssertFalse(state.reachedEndWithOpenExercises, "Bench is still ahead")
        XCTAssertEqual(state.currentExercise?.name, "Bench")

        completeAllSets(of: 1, in: state)
        XCTAssertTrue(state.isWorkoutComplete)
        XCTAssertFalse(state.reachedEndWithOpenExercises)
    }

    func testFinishingEarlyGoesToTheSummaryWithoutClaimingCompletion() {
        let state = makeState([linear("Squat")])
        state.markSetComplete()
        state.finishedEarly = true

        XCTAssertTrue(state.isFinished)
        XCTAssertFalse(state.isWorkoutComplete)
        XCTAssertFalse(state.reachedEndWithOpenExercises)
    }

    // MARK: - Undo

    func testReopenPutsTheLifterBackOnTheSet() throws {
        let state = makeState([linear("Squat"), linear("Bench")])
        let squat = state.exercises[0]
        completeAllSets(of: 0, in: state)
        XCTAssertEqual(state.currentExercise?.name, "Bench")

        let record = try XCTUnwrap(state.reopenSet(exerciseId: squat.id, setNumber: 3))
        XCTAssertEqual(record.setNumber, 3)
        XCTAssertEqual(state.currentExercise?.name, "Squat")
        XCTAssertEqual(state.currentSetNumber, 3)
        XCTAssertEqual(state.completedSets[squat.id], [1, 2])
        XCTAssertEqual(state.completionHistory.count, 2)
    }

    func testReopenClearsAMissedSet() {
        let state = makeState([linear("Squat")])
        let squat = state.exercises[0]
        state.markSetFailed()
        XCTAssertTrue(state.hasFailedSets(for: squat.id))

        state.reopenSet(exerciseId: squat.id, setNumber: 1)
        XCTAssertFalse(state.hasFailedSets(for: squat.id))
    }

    func testCompletingACompletedSetAgainAddsNoHistory() {
        let state = makeState([linear("Squat")])
        state.markSetComplete()
        state.jumpToExercise(0)
        state.currentSetNumber = 1
        state.markSetComplete()
        XCTAssertEqual(state.completionHistory.count, 1)
    }

    /// Reopening an earlier set of a finished lift still un-finishes it, once
    func testLinearFinishCanBeTakenFromAnotherSet() {
        let state = makeState([linear("Squat")])
        let squat = state.exercises[0]
        state.markSetComplete()
        state.markSetComplete()
        var undo = SetUndoInfo()
        undo.finishedLinearLift = true
        undo.previousTrainingMax = 95
        state.markSetComplete(undo: undo)

        XCTAssertEqual(state.takeLinearFinish(exerciseId: squat.id)?.previousTrainingMax, 95)
        XCTAssertNil(state.takeLinearFinish(exerciseId: squat.id))
    }

    func testUndoingAnAMRAPFallsBackToTheNextBestResult() {
        let bench = WorkoutExercise.fromStructured(name: "Bench", lift: "Bench", sets: [
            StructuredSetInfo(setIndex: 0, intensity: 0.75, targetReps: 5, isAMRAP: true, weight: 150),
            StructuredSetInfo(setIndex: 1, intensity: 0.95, targetReps: 1, isAMRAP: true, weight: 190)
        ])
        let state = makeState([bench])
        state.structuredLoggedReps[bench.id] = [0: 8, 1: 4]
        state.recomputeAMRAPResult(lift: "Bench") { E1RM.epley(weight: $0, reps: $1) }
        XCTAssertEqual(state.amrapResults["Bench"]?.weight, 190)

        state.structuredLoggedReps[bench.id]?[1] = nil
        state.recomputeAMRAPResult(lift: "Bench") { E1RM.epley(weight: $0, reps: $1) }
        XCTAssertEqual(state.amrapResults["Bench"]?.weight, 150)

        state.structuredLoggedReps[bench.id]?[0] = nil
        state.recomputeAMRAPResult(lift: "Bench") { E1RM.epley(weight: $0, reps: $1) }
        XCTAssertNil(state.amrapResults["Bench"])
    }

    // MARK: - Rest

    func testRestAdjustmentStaysWithItsExercise() {
        let state = makeState([linear("Squat"), linear("Bench")])
        let squat = state.exercises[0]
        let bench = state.exercises[1]
        state.startTimer(duration: 120, forExercise: squat.id)
        state.adjustTimer(by: 15)
        state.skipTimer()

        XCTAssertEqual(state.restDuration(for: squat, default: 120), 135)
        XCTAssertEqual(state.restDuration(for: bench, default: 120), 120)
    }

    func testRestWithoutAnExerciseRecordsNoOverride() {
        let state = makeState([linear("Squat")])
        state.startTimer(duration: 120)
        state.adjustTimer(by: 15)
        XCTAssertTrue(state.restOverrides.isEmpty)
    }

    // MARK: - Settings

    func testSettingsSavedBeforeAccessoryRestStillDecode() throws {
        var settings = UserSettings()
        settings.restTimerDuration = 240
        let data = try JSONEncoder().encode(settings)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["accessoryRestTimerDuration"] = nil

        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.restTimerDuration, 240, "Existing users keep their main-lift value")
        XCTAssertEqual(decoded.accessoryRestSeconds, 90)
    }

    // MARK: - Next Workout

    private func next(
        from week: Int,
        weeks: [Int] = [1, 2],
        days: [Int] = [1, 2, 3],
        logged: Set<[Int]>
    ) -> [Int]? {
        NextWorkout.find(
            fromWeek: week,
            weeks: weeks,
            visibleDays: { _ in days },
            isNotStarted: { !logged.contains([$0, $1]) }
        ).map { [$0.week, $0.day] }
    }

    func testNextWorkoutIsTheFirstUnloggedDay() {
        XCTAssertEqual(next(from: 1, logged: [[1, 1]]), [1, 2])
        XCTAssertEqual(next(from: 1, logged: [[1, 2]]), [1, 1], "An earlier day skipped is still next")
    }

    func testNextWorkoutRollsToTheNextWeek() {
        XCTAssertEqual(next(from: 1, logged: [[1, 1], [1, 2], [1, 3]]), [2, 1])
    }

    func testNextWorkoutStopsAtTheEndOfTheCycle() {
        XCTAssertNil(next(from: 2, logged: [[2, 1], [2, 2], [2, 3]]))
    }

    func testNextWorkoutHonorsDaysVisiblePerWeek() {
        let result = NextWorkout.find(
            fromWeek: 1,
            weeks: [1, 2],
            visibleDays: { $0 == 1 ? [1] : [2] },
            isNotStarted: { !($0 == 1 && $1 == 1) }
        )
        XCTAssertEqual(result?.week, 2)
        XCTAssertEqual(result?.day, 2)
    }
}
