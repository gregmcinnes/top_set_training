import XCTest
@testable import SBSApp

/// Tests for structured progression (nSuns-style) programs with AMRAP sets
final class StructuredProgressionTests: XCTestCase {
    
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
    
    private func createNSunsStyleState(
        initialMaxes: [String: Double] = ["Bench Press": 200, "Squat": 300],
        weeks: [Int] = Array(1...4)
    ) -> ProgramState {
        // nSuns-style sets with pyramid intensity
        let benchSets: [SetDetail] = [
            SetDetail(intensity: 0.75, reps: 5),
            SetDetail(intensity: 0.85, reps: 3),
            SetDetail(intensity: 0.95, reps: 1, isAMRAP: true),  // The 1+ set
            SetDetail(intensity: 0.90, reps: 3),
            SetDetail(intensity: 0.85, reps: 3),
            SetDetail(intensity: 0.80, reps: 3),
            SetDetail(intensity: 0.75, reps: 5),
            SetDetail(intensity: 0.70, reps: 5),
            SetDetail(intensity: 0.65, reps: 5, isAMRAP: true)
        ]
        
        let squatSets: [SetDetail] = [
            SetDetail(intensity: 0.75, reps: 5),
            SetDetail(intensity: 0.85, reps: 3),
            SetDetail(intensity: 0.95, reps: 1, isAMRAP: true),  // The 1+ set
            SetDetail(intensity: 0.90, reps: 3),
            SetDetail(intensity: 0.85, reps: 3),
            SetDetail(intensity: 0.80, reps: 3),
            SetDetail(intensity: 0.75, reps: 5),
            SetDetail(intensity: 0.70, reps: 5),
            SetDetail(intensity: 0.65, reps: 5, isAMRAP: true)
        ]
        
        let benchItem = DayItem(
            type: .structured,
            lift: "Bench Press",
            name: "Bench Press",
            setsDetail: benchSets
        )
        
        let squatItem = DayItem(
            type: .structured,
            lift: "Squat",
            name: "Squat",
            setsDetail: squatSets
        )
        
        return ProgramState(
            rounding: 5,
            initialMaxes: initialMaxes,
            singleAt8Percent: ["Bench Press": 0.9, "Squat": 0.9],
            lifts: [:],
            days: [1: [benchItem], 2: [squatItem]],
            weeks: weeks
        )
    }
    
    // MARK: - Gather Structured Lift Info Tests
    
    func testGatherStructuredLiftInfo() {
        let state = createNSunsStyleState()
        let liftInfo = engine.gatherStructuredLiftInfo(from: state)
        
        XCTAssertEqual(liftInfo.count, 2)
        
        // Both lifts should have their 1+ set identified
        XCTAssertNotNil(liftInfo["Bench Press"])
        XCTAssertNotNil(liftInfo["Squat"])
        
        // The 1+ set is at index 2 with 95% intensity
        XCTAssertEqual(liftInfo["Bench Press"]?.setIndex, 2)
        XCTAssertEqual(liftInfo["Bench Press"]?.intensity, 0.95)
    }
    
    func testGatherStructuredLiftInfoFindsAMRAPSets() {
        let sets = [
            SetDetail(intensity: 0.70, reps: 5),
            SetDetail(intensity: 0.80, reps: 3),
            SetDetail(intensity: 0.90, reps: 1, isAMRAP: true)  // Should find this one
        ]
        
        let item = DayItem(type: .structured, lift: "OHP", name: "OHP", setsDetail: sets)
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["OHP": 135],
            singleAt8Percent: ["OHP": 0.9],
            lifts: [:],
            days: [1: [item]],
            weeks: [1, 2]
        )
        
        let liftInfo = engine.gatherStructuredLiftInfo(from: state)
        
        XCTAssertEqual(liftInfo["OHP"]?.setIndex, 2)
        XCTAssertEqual(liftInfo["OHP"]?.intensity, 0.90)
    }
    
    // MARK: - nSuns-style 1+ Set Progression Tests (targetReps = 1)
    // nSuns progression: 0-1 reps = stall, 2-4 reps = +5, 5+ reps = +10 (same for all lifts)
    
    func testNSunsProgression0Reps() {
        // 0 reps on 1+ = stall (0 lbs)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 0, targetReps: 1, isUpperBody: true), 0.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 0, targetReps: 1, isUpperBody: false), 0.0)
    }
    
    func testNSunsProgression1Rep() {
        // 1 rep on 1+ = stall (0 lbs) - minimum 2 reps to progress
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 1, targetReps: 1, isUpperBody: true), 0.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 1, targetReps: 1, isUpperBody: false), 0.0)
    }
    
    func testNSunsProgression2to4Reps() {
        // 2-4 reps on 1+ = +5 lbs
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 2, targetReps: 1, isUpperBody: true), 5.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 3, targetReps: 1, isUpperBody: true), 5.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 4, targetReps: 1, isUpperBody: true), 5.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 2, targetReps: 1, isUpperBody: false), 5.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 3, targetReps: 1, isUpperBody: false), 5.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 4, targetReps: 1, isUpperBody: false), 5.0)
    }
    
    func testNSunsProgression5PlusReps() {
        // 5+ reps on 1+ = +10 lbs
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 5, targetReps: 1, isUpperBody: true), 10.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 8, targetReps: 1, isUpperBody: true), 10.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 5, targetReps: 1, isUpperBody: false), 10.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 8, targetReps: 1, isUpperBody: false), 10.0)
    }
    
    // MARK: - Standard Structured Progression Tests (Greyskull, GZCLP with higher target reps)
    // Upper body: miss = -5, hit = 0, 1-2 over = +5, 3+ over = +10
    // Lower body: miss = 0, hit = +5, 1-2 over = +10, 3+ over = +15
    
    func testStructuredProgressionUpperBodyMissTarget() {
        // Miss target (3+ set, got 2 reps) = -5 lbs
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 2, targetReps: 3, isUpperBody: true), -5.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 0, targetReps: 3, isUpperBody: true), -5.0)
    }
    
    func testStructuredProgressionUpperBodyHitTarget() {
        // Hit exact target (3+ set, got 3 reps) = 0 lbs
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 3, targetReps: 3, isUpperBody: true), 0.0)
    }
    
    func testStructuredProgressionUpperBody1to2Over() {
        // 1-2 over target (3+ set, got 4-5 reps) = +5 lbs
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 4, targetReps: 3, isUpperBody: true), 5.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 5, targetReps: 3, isUpperBody: true), 5.0)
    }
    
    func testStructuredProgressionUpperBody3PlusOver() {
        // 3+ over target (3+ set, got 6+ reps) = +10 lbs
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 6, targetReps: 3, isUpperBody: true), 10.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 10, targetReps: 3, isUpperBody: true), 10.0)
    }
    
    func testStructuredProgressionLowerBodyMissTarget() {
        // Miss target (3+ set, got 2 reps) = 0 lbs (stall, don't reduce)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 2, targetReps: 3, isUpperBody: false), 0.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 0, targetReps: 3, isUpperBody: false), 0.0)
    }
    
    func testStructuredProgressionLowerBodyHitTarget() {
        // Hit exact target (3+ set, got 3 reps) = +5 lbs
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 3, targetReps: 3, isUpperBody: false), 5.0)
    }
    
    func testStructuredProgressionLowerBody1to2Over() {
        // 1-2 over target (3+ set, got 4-5 reps) = +10 lbs
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 4, targetReps: 3, isUpperBody: false), 10.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 5, targetReps: 3, isUpperBody: false), 10.0)
    }
    
    func testStructuredProgressionLowerBody3PlusOver() {
        // 3+ over target (3+ set, got 6+ reps) = +15 lbs
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 6, targetReps: 3, isUpperBody: false), 15.0)
        XCTAssertEqual(engine.structuredProgression(repsOnOnePlus: 10, targetReps: 3, isUpperBody: false), 15.0)
    }
    
    // MARK: - Compute Structured Training Maxes Tests
    
    func testStructuredTMsInitialWeek() {
        let state = createNSunsStyleState(initialMaxes: ["Bench Press": 200])
        let liftInfo = engine.gatherStructuredLiftInfo(from: state)
        let tms = engine.computeStructuredTrainingMaxes(
            state: state,
            upToWeek: 1,
            structuredLiftInfo: liftInfo
        )
        
        XCTAssertEqual(tms[1]?["Bench Press"], 200)
    }
    
    func testStructuredTMsProgressWithLogs() {
        var state = createNSunsStyleState(initialMaxes: ["Bench Press": 200])
        
        // Log 3 reps on the 1+ set (set index 2)
        state.structuredLogs["Bench Press"] = [
            1: [1: StructuredLogEntry(amrapReps: [2: 3], note: "")]
        ]
        
        let liftInfo = engine.gatherStructuredLiftInfo(from: state)
        let tms = engine.computeStructuredTrainingMaxes(
            state: state,
            upToWeek: 2,
            structuredLiftInfo: liftInfo
        )
        
        // Bench is upper body, 3 reps = +5 lbs
        XCTAssertEqual(tms[2]?["Bench Press"], 205)
    }
    
    func testStructuredTMsLowerBodyProgression() {
        var state = createNSunsStyleState(initialMaxes: ["Squat": 300])
        
        // Log 4 reps on the 1+ set (set index 2)
        state.structuredLogs["Squat"] = [
            1: [2: StructuredLogEntry(amrapReps: [2: 4], note: "")]
        ]
        
        let liftInfo = engine.gatherStructuredLiftInfo(from: state)
        let tms = engine.computeStructuredTrainingMaxes(
            state: state,
            upToWeek: 2,
            structuredLiftInfo: liftInfo
        )
        
        // Squat is lower body, 4 reps = +15 lbs
        XCTAssertEqual(tms[2]?["Squat"], 315)
    }
    
    func testStructuredTMsNoLogKeepsSame() {
        let state = createNSunsStyleState(initialMaxes: ["Bench Press": 200])
        
        let liftInfo = engine.gatherStructuredLiftInfo(from: state)
        let tms = engine.computeStructuredTrainingMaxes(
            state: state,
            upToWeek: 3,
            structuredLiftInfo: liftInfo
        )
        
        // Without logs, TM should stay the same
        XCTAssertEqual(tms[1]?["Bench Press"], 200)
        XCTAssertEqual(tms[2]?["Bench Press"], 200)
        XCTAssertEqual(tms[3]?["Bench Press"], 200)
    }
    
    func testStructuredTMsCumulativeProgression() {
        var state = createNSunsStyleState(initialMaxes: ["Bench Press": 200])
        
        // Log progressively better AMRAP results
        state.structuredLogs["Bench Press"] = [
            1: [1: StructuredLogEntry(amrapReps: [2: 2], note: "")],  // +5
            2: [1: StructuredLogEntry(amrapReps: [2: 3], note: "")],  // +5
            3: [1: StructuredLogEntry(amrapReps: [2: 5], note: "")]   // +10
        ]
        
        let liftInfo = engine.gatherStructuredLiftInfo(from: state)
        let tms = engine.computeStructuredTrainingMaxes(
            state: state,
            upToWeek: 4,
            structuredLiftInfo: liftInfo
        )
        
        XCTAssertEqual(tms[1]?["Bench Press"], 200)
        XCTAssertEqual(tms[2]?["Bench Press"], 205)  // +5
        XCTAssertEqual(tms[3]?["Bench Press"], 210)  // +5
        XCTAssertEqual(tms[4]?["Bench Press"], 220)  // +10
    }
    
    // MARK: - Week Plan Structured Item Tests
    
    func testWeekPlanStructuredItem() throws {
        let state = createNSunsStyleState(initialMaxes: ["Bench Press": 200])
        let plan = try engine.weekPlan(state: state, week: 1)
        
        guard case let .structured(name, lift, trainingMax, sets, _) = plan[1]?.first else {
            XCTFail("Expected structured item")
            return
        }
        
        XCTAssertEqual(name, "Bench Press")
        XCTAssertEqual(lift, "Bench Press")
        XCTAssertEqual(trainingMax, 200, accuracy: 0.1)
        XCTAssertEqual(sets.count, 9)
    }
    
    func testWeekPlanStructuredSetWeights() throws {
        let state = createNSunsStyleState(initialMaxes: ["Bench Press": 200])
        let plan = try engine.weekPlan(state: state, week: 1)
        
        guard case let .structured(_, _, _, sets, _) = plan[1]?.first else {
            XCTFail("Expected structured item")
            return
        }
        
        // Check weights are calculated correctly
        // Set 0: 75% of 200 = 150
        XCTAssertEqual(sets[0].weight, 150, accuracy: 1)
        
        // Set 1: 85% of 200 = 170
        XCTAssertEqual(sets[1].weight, 170, accuracy: 1)
        
        // Set 2 (1+ set): 95% of 200 = 190
        XCTAssertEqual(sets[2].weight, 190, accuracy: 1)
        XCTAssertTrue(sets[2].isAMRAP)
        
        // Last set: 65% of 200 = 130
        XCTAssertEqual(sets[8].weight, 130, accuracy: 1)
        XCTAssertTrue(sets[8].isAMRAP)
    }
    
    func testWeekPlanStructuredWithLoggedReps() throws {
        var state = createNSunsStyleState(initialMaxes: ["Bench Press": 200])
        
        // Log AMRAP reps on the 1+ set
        state.structuredLogs["Bench Press"] = [
            1: [1: StructuredLogEntry(amrapReps: [2: 4, 8: 12], note: "Felt strong")]
        ]
        
        let plan = try engine.weekPlan(state: state, week: 1)
        
        guard case let .structured(_, _, _, sets, logEntry) = plan[1]?.first else {
            XCTFail("Expected structured item")
            return
        }
        
        // Check logged reps are included
        XCTAssertEqual(sets[2].loggedReps, 4)
        XCTAssertEqual(sets[8].loggedReps, 12)
        XCTAssertNil(sets[0].loggedReps) // Non-AMRAP set
        
        XCTAssertNotNil(logEntry)
        XCTAssertEqual(logEntry?.note, "Felt strong")
    }
    
    // MARK: - Sets Detail By Week Tests
    
    func testSetsDetailByWeek() throws {
        // Create a 5/3/1 style program where sets change each week
        let week1Sets = [
            SetDetail(intensity: 0.65, reps: 5),
            SetDetail(intensity: 0.75, reps: 5),
            SetDetail(intensity: 0.85, reps: 5, isAMRAP: true)
        ]
        
        let week2Sets = [
            SetDetail(intensity: 0.70, reps: 3),
            SetDetail(intensity: 0.80, reps: 3),
            SetDetail(intensity: 0.90, reps: 3, isAMRAP: true)
        ]
        
        let week3Sets = [
            SetDetail(intensity: 0.75, reps: 5),
            SetDetail(intensity: 0.85, reps: 3),
            SetDetail(intensity: 0.95, reps: 1, isAMRAP: true)
        ]
        
        let item = DayItem(
            type: .structured,
            lift: "Squat",
            name: "Squat",
            setsDetailByWeek: [
                "1": week1Sets,
                "2": week2Sets,
                "3": week3Sets
            ]
        )
        
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["Squat": 300],
            singleAt8Percent: ["Squat": 0.9],
            lifts: [:],
            days: [1: [item]],
            weeks: [1, 2, 3]
        )
        
        // Week 1: 5s week
        let plan1 = try engine.weekPlan(state: state, week: 1)
        guard case let .structured(_, _, _, sets1, _) = plan1[1]?.first else {
            XCTFail("Expected structured item")
            return
        }
        XCTAssertEqual(sets1.count, 3)
        XCTAssertEqual(sets1[2].targetReps, 5)
        XCTAssertEqual(sets1[2].intensity, 0.85, accuracy: 0.01)
        
        // Week 2: 3s week
        let plan2 = try engine.weekPlan(state: state, week: 2)
        guard case let .structured(_, _, _, sets2, _) = plan2[1]?.first else {
            XCTFail("Expected structured item")
            return
        }
        XCTAssertEqual(sets2[2].targetReps, 3)
        XCTAssertEqual(sets2[2].intensity, 0.90, accuracy: 0.01)
        
        // Week 3: 1s week
        let plan3 = try engine.weekPlan(state: state, week: 3)
        guard case let .structured(_, _, _, sets3, _) = plan3[1]?.first else {
            XCTFail("Expected structured item")
            return
        }
        XCTAssertEqual(sets3[2].targetReps, 1)
        XCTAssertEqual(sets3[2].intensity, 0.95, accuracy: 0.01)
    }
    
    // MARK: - Mixed Program Tests
    
    func testMixedStructuredAndVolume() throws {
        // Create state with both structured and volume exercises
        let structuredItem = DayItem(
            type: .structured,
            lift: "Bench Press",
            name: "Bench Press",
            setsDetail: [
                SetDetail(intensity: 0.75, reps: 5),
                SetDetail(intensity: 0.85, reps: 3),
                SetDetail(intensity: 0.95, reps: 1, isAMRAP: true)
            ]
        )
        
        let volumeItem = DayItem(type: .volume, lift: "OHP", name: "OHP Accessory")
        
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["Bench Press": 200, "OHP": 135],
            singleAt8Percent: ["Bench Press": 0.9, "OHP": 0.9],
            lifts: ["OHP": [1: WeekData(intensity: 0.70, repsPerNormalSet: 8, repOutTarget: 10, sets: 4)]],
            days: [1: [structuredItem, volumeItem]],
            weeks: [1, 2]
        )
        
        let plan = try engine.weekPlan(state: state, week: 1)
        
        XCTAssertEqual(plan[1]?.count, 2)
        
        // First should be structured
        guard case .structured = plan[1]?[0] else {
            XCTFail("Expected structured item first")
            return
        }
        
        // Second should be volume
        guard case .volume = plan[1]?[1] else {
            XCTFail("Expected volume item second")
            return
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptySetsDetailSkipsExercise() throws {
        let item = DayItem(
            type: .structured,
            lift: "Bench Press",
            name: "Bench Press",
            setsDetailByWeek: [
                "1": [], // Empty sets for week 1 (e.g., deload)
                "2": [SetDetail(intensity: 0.75, reps: 5)]
            ]
        )
        
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["Bench Press": 200],
            singleAt8Percent: ["Bench Press": 0.9],
            lifts: [:],
            days: [1: [item]],
            weeks: [1, 2]
        )
        
        // Week 1 should have no exercises (empty sets)
        let plan1 = try engine.weekPlan(state: state, week: 1)
        XCTAssertTrue(plan1[1]?.isEmpty ?? true)
        
        // Week 2 should have the exercise
        let plan2 = try engine.weekPlan(state: state, week: 2)
        XCTAssertEqual(plan2[1]?.count, 1)
    }
    
    func testFallbackToAnyAMRAPIfNo1Plus() {
        // Create sets without a 1-rep AMRAP
        let sets = [
            SetDetail(intensity: 0.70, reps: 5),
            SetDetail(intensity: 0.80, reps: 5, isAMRAP: true),  // 5+ set (highest intensity AMRAP)
            SetDetail(intensity: 0.60, reps: 10)
        ]
        
        let item = DayItem(type: .structured, lift: "OHP", name: "OHP", setsDetail: sets)
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["OHP": 100],
            singleAt8Percent: ["OHP": 0.9],
            lifts: [:],
            days: [1: [item]],
            weeks: [1]
        )
        
        let liftInfo = engine.gatherStructuredLiftInfo(from: state)
        
        // Should find the 5+ set at index 1 (highest intensity AMRAP)
        XCTAssertEqual(liftInfo["OHP"]?.setIndex, 1)
        XCTAssertEqual(liftInfo["OHP"]?.intensity, 0.80)
    }
}

