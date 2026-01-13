import XCTest
@testable import SBSApp

/// Tests for the ProgramEngine - training max calculations and workout planning
final class ProgramEngineTests: XCTestCase {
    
    var engine: ProgramEngine!
    
    override func setUp() {
        super.setUp()
        engine = ProgramEngine()
    }
    
    override func tearDown() {
        engine = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Creates a minimal program state for testing
    private func createTestProgramState(
        initialMaxes: [String: Double] = ["Squat": 300, "Bench Press": 225],
        weeks: [Int] = Array(1...4)
    ) -> ProgramState {
        // Create week data for each lift
        var lifts: [String: [Int: WeekData]] = [:]
        
        for lift in initialMaxes.keys {
            var weekData: [Int: WeekData] = [:]
            for week in weeks {
                // Simulate progressive intensity
                let intensity = 0.70 + Double(week) * 0.025
                let reps = max(5, 12 - week)
                weekData[week] = WeekData(
                    intensity: intensity,
                    repsPerNormalSet: reps,
                    repOutTarget: reps + 2,
                    sets: 4
                )
            }
            lifts[lift] = weekData
        }
        
        let squatItem = DayItem(type: .volume, lift: "Squat", name: "Squat")
        let benchItem = DayItem(type: .volume, lift: "Bench Press", name: "Bench Press")
        
        return ProgramState(
            rounding: 5,
            initialMaxes: initialMaxes,
            singleAt8Percent: ["Squat": 0.9, "Bench Press": 0.9],
            lifts: lifts,
            days: [1: [squatItem], 2: [benchItem]],
            weeks: weeks
        )
    }
    
    // MARK: - Rounding Tests
    
    func testRoundTo5() {
        // Test internal rounding logic via public methods
        let state = createTestProgramState(initialMaxes: ["Squat": 302.5])
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: 1)
        
        // Initial max should be preserved
        XCTAssertEqual(tms[1]?["Squat"], 302.5)
    }
    
    // MARK: - Training Max Computation Tests
    
    func testComputeTrainingMaxesWeek1() {
        let state = createTestProgramState()
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: 1)
        
        XCTAssertEqual(tms[1]?["Squat"], 300)
        XCTAssertEqual(tms[1]?["Bench Press"], 225)
    }
    
    func testComputeTrainingMaxesNoLogs() {
        // Without any logs, TM should progress at "hit target" rate (0%)
        let state = createTestProgramState()
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: 4)
        
        // With default 0% adjustment for hitting target, TMs stay the same
        XCTAssertEqual(tms[1]?["Squat"], 300)
        XCTAssertEqual(tms[2]?["Squat"], 300)
        XCTAssertEqual(tms[3]?["Squat"], 300)
        XCTAssertEqual(tms[4]?["Squat"], 300)
    }
    
    func testComputeTrainingMaxesWithBeatTargetLogs() {
        var state = createTestProgramState()
        
        // Log beating target by 3 reps on week 1
        let repOutTarget = state.lifts["Squat"]?[1]?.repOutTarget ?? 10
        state.logs["Squat"] = [1: [1: LogEntry(repsLastSet: repOutTarget + 3, note: "")]]
        
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: 2)
        
        // Week 2 should have increased TM (1.5% for +3 reps)
        let expectedTM = 300 * (1.0 + 0.015)
        XCTAssertEqual(tms[2]?["Squat"]!, expectedTM, accuracy: 0.01)
    }
    
    func testComputeTrainingMaxesWithBelowTargetLogs() {
        var state = createTestProgramState()
        
        // Log below target by 2 reps on week 1
        let repOutTarget = state.lifts["Squat"]?[1]?.repOutTarget ?? 10
        state.logs["Squat"] = [1: [1: LogEntry(repsLastSet: repOutTarget - 2, note: "")]]
        
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: 2)
        
        // Week 2 should have decreased TM (-5% for -2 or more reps)
        let expectedTM = 300 * (1.0 - 0.05)
        XCTAssertEqual(tms[2]?["Squat"]!, expectedTM, accuracy: 0.01)
    }
    
    func testComputeTrainingMaxesCumulativeProgression() {
        var state = createTestProgramState()
        
        // Beat target by 2 reps each week
        for week in 1...3 {
            let repOutTarget = state.lifts["Squat"]?[week]?.repOutTarget ?? 10
            state.logs["Squat", default: [:]][week] = [1: LogEntry(repsLastSet: repOutTarget + 2, note: "")]
        }
        
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: 4)
        
        // Each week should compound: +1% per week
        let week2TM = 300 * 1.01
        let week3TM = week2TM * 1.01
        let week4TM = week3TM * 1.01
        
        XCTAssertEqual(tms[2]?["Squat"]!, week2TM, accuracy: 0.1)
        XCTAssertEqual(tms[3]?["Squat"]!, week3TM, accuracy: 0.1)
        XCTAssertEqual(tms[4]?["Squat"]!, week4TM, accuracy: 0.1)
    }
    
    func testComputeTrainingMaxesWithWeightOverride() {
        var state = createTestProgramState()
        
        // Override weight on week 1
        let intensity = state.lifts["Squat"]?[1]?.intensity ?? 0.7
        let overrideWeight = 250.0  // Different from calculated
        state.logs["Squat"] = [1: [1: LogEntry(repsLastSet: 10, note: "", weightOverride: overrideWeight)]]
        
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: 1)
        
        // TM should be back-calculated: TM = weight / intensity
        let expectedTM = overrideWeight / intensity
        XCTAssertEqual(tms[1]?["Squat"]!, expectedTM, accuracy: 0.1)
    }
    
    // MARK: - Per Week Adjustment Tests
    
    func testPerWeekAdjustmentBelowBy2Plus() {
        let adjustment = engine.perWeekAdjustment(diffReps: -3)
        XCTAssertEqual(adjustment, -0.05)
    }
    
    func testPerWeekAdjustmentBelowBy1() {
        let adjustment = engine.perWeekAdjustment(diffReps: -1)
        XCTAssertEqual(adjustment, -0.02)
    }
    
    func testPerWeekAdjustmentHitTarget() {
        let adjustment = engine.perWeekAdjustment(diffReps: 0)
        XCTAssertEqual(adjustment, 0.0)
    }
    
    func testPerWeekAdjustmentBeatBy1() {
        let adjustment = engine.perWeekAdjustment(diffReps: 1)
        XCTAssertEqual(adjustment, 0.005)
    }
    
    func testPerWeekAdjustmentBeatBy5Plus() {
        let adjustment = engine.perWeekAdjustment(diffReps: 7)
        XCTAssertEqual(adjustment, 0.03)
    }
    
    // MARK: - Week Plan Tests
    
    func testWeekPlanBasicStructure() throws {
        let state = createTestProgramState()
        let plan = try engine.weekPlan(state: state, week: 1)
        
        XCTAssertEqual(plan.count, 2) // 2 days
        XCTAssertNotNil(plan[1])
        XCTAssertNotNil(plan[2])
    }
    
    func testWeekPlanVolumeSetsCalculation() throws {
        let state = createTestProgramState()
        let plan = try engine.weekPlan(state: state, week: 1)
        
        guard case let .volume(_, lift, weight, intensity, sets, repsPerSet, repOutTarget, _, _, _, _) = plan[1]?.first else {
            XCTFail("Expected volume item")
            return
        }
        
        XCTAssertEqual(lift, "Squat")
        XCTAssertEqual(intensity, 0.725, accuracy: 0.01) // Week 1 intensity from our test data
        XCTAssertEqual(sets, 4)
        XCTAssertGreaterThan(weight, 0)
        XCTAssertGreaterThan(repsPerSet, 0)
        XCTAssertGreaterThan(repOutTarget, 0)
    }
    
    func testWeekPlanTMItem() throws {
        // Create a state with a TM display item
        var state = createTestProgramState()
        let tmItem = DayItem(type: .tm, lift: "Squat", name: "Squat TM")
        state.days[1] = [tmItem]
        
        let plan = try engine.weekPlan(state: state, week: 1)
        
        guard case let .tm(_, lift, trainingMax, topSingleAt8) = plan[1]?.first else {
            XCTFail("Expected TM item")
            return
        }
        
        XCTAssertEqual(lift, "Squat")
        XCTAssertEqual(trainingMax, 300, accuracy: 0.01)
        XCTAssertEqual(topSingleAt8, 270, accuracy: 1) // 300 * 0.9 = 270
    }
    
    func testWeekPlanAccessoryItem() throws {
        var state = createTestProgramState()
        let accessoryItem = DayItem(
            type: .accessory,
            lift: nil,
            name: "Cable Rows",
            defaultSets: 4,
            defaultReps: 12
        )
        state.days[3] = [accessoryItem]
        
        let plan = try engine.weekPlan(state: state, week: 1)
        
        guard case let .accessory(name, sets, reps, _) = plan[3]?.first else {
            XCTFail("Expected accessory item")
            return
        }
        
        XCTAssertEqual(name, "Cable Rows")
        XCTAssertEqual(sets, 4)
        XCTAssertEqual(reps, 12)
    }
    
    func testWeekPlanInvalidWeekThrows() {
        let state = createTestProgramState(weeks: [1, 2, 3])
        
        XCTAssertThrowsError(try engine.weekPlan(state: state, week: 5)) { error in
            guard case ProgramEngineError.invalidWeek = error else {
                XCTFail("Expected invalidWeek error")
                return
            }
        }
    }
    
    func testWeekPlanWithLoggedReps() throws {
        var state = createTestProgramState()
        let repOutTarget = state.lifts["Squat"]?[1]?.repOutTarget ?? 10
        state.logs["Squat"] = [1: [1: LogEntry(repsLastSet: repOutTarget + 2, note: "")]]
        
        let plan = try engine.weekPlan(state: state, week: 1)
        
        guard case let .volume(_, _, _, _, _, _, _, loggedRepsLastSet, nextWeekTmDelta, _, _) = plan[1]?.first else {
            XCTFail("Expected volume item")
            return
        }
        
        XCTAssertEqual(loggedRepsLastSet, repOutTarget + 2)
        XCTAssertNotNil(nextWeekTmDelta)
        XCTAssertEqual(nextWeekTmDelta!, 0.01, accuracy: 0.001) // +2 reps = +1%
    }
    
    // MARK: - Day Visibility Tests
    
    func testWeekPlanRespectsVisibility() throws {
        var state = createTestProgramState(weeks: [1, 2])
        
        // Day 1 only visible on week 1, Day 2 only visible on week 2
        state.dayVisibility = [1: [1], 2: [2]]
        
        let week1Plan = try engine.weekPlan(state: state, week: 1)
        let week2Plan = try engine.weekPlan(state: state, week: 2)
        
        XCTAssertNotNil(week1Plan[1])
        XCTAssertNil(week1Plan[2])
        
        XCTAssertNil(week2Plan[1])
        XCTAssertNotNil(week2Plan[2])
    }
    
    // MARK: - Upper/Lower Body Detection Tests
    
    func testIsUpperBodyLift() {
        XCTAssertTrue(engine.isUpperBodyLift("Bench Press"))
        XCTAssertTrue(engine.isUpperBodyLift("OHP"))
        XCTAssertTrue(engine.isUpperBodyLift("Overhead Press"))
        XCTAssertTrue(engine.isUpperBodyLift("Incline Press"))
        XCTAssertTrue(engine.isUpperBodyLift("Barbell Row"))
    }
    
    func testIsLowerBodyLift() {
        XCTAssertFalse(engine.isUpperBodyLift("Squat"))
        XCTAssertFalse(engine.isUpperBodyLift("Front Squat"))
        XCTAssertFalse(engine.isUpperBodyLift("Deadlift"))
        XCTAssertFalse(engine.isUpperBodyLift("Sumo Deadlift"))
        XCTAssertFalse(engine.isUpperBodyLift("Leg Press"))
        XCTAssertFalse(engine.isUpperBodyLift("Hip Thrust"))
        XCTAssertFalse(engine.isUpperBodyLift("Lunges"))
    }
    
    // MARK: - Custom Weight Adjustments Tests
    
    func testCustomWeightAdjustments() {
        let customAdjustments = WeightAdjustments(
            belowBy2Plus: -0.10,
            belowBy1: -0.05,
            hitTarget: 0.01,
            beatBy1: 0.02,
            beatBy2: 0.03,
            beatBy3: 0.04,
            beatBy4: 0.05,
            beatBy5Plus: 0.06
        )
        
        engine.weightAdjustments = customAdjustments
        
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: -3), -0.10)
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: 0), 0.01)
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: 5), 0.06)
    }
    
    // MARK: - Multiple Lifts Progression Tests
    
    func testIndependentLiftProgression() {
        var state = createTestProgramState()
        
        // Squat beats target, Bench misses target
        let squatTarget = state.lifts["Squat"]?[1]?.repOutTarget ?? 10
        let benchTarget = state.lifts["Bench Press"]?[1]?.repOutTarget ?? 10
        
        state.logs["Squat"] = [1: [1: LogEntry(repsLastSet: squatTarget + 3, note: "")]]
        state.logs["Bench Press"] = [1: [2: LogEntry(repsLastSet: benchTarget - 2, note: "")]]
        
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: 2)
        
        // Squat should increase
        XCTAssertGreaterThan(tms[2]?["Squat"] ?? 0, tms[1]?["Squat"] ?? 0)
        
        // Bench should decrease
        XCTAssertLessThan(tms[2]?["Bench Press"] ?? 0, tms[1]?["Bench Press"] ?? 0)
    }
}


