import XCTest
@testable import SBSApp

/// Tests for linear progression (StrongLifts-style) programs
final class LinearProgressionTests: XCTestCase {
    
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
    
    private func createLinearProgramState(
        initialMaxes: [String: Double] = ["Squat": 135, "Bench Press": 95, "Deadlift": 135],
        config: LinearProgressionConfig = LinearProgressionConfig()
    ) -> ProgramState {
        let squatItem = DayItem(type: .linear, lift: "Squat", name: "Squat 5x5", sets: 5, reps: 5)
        let benchItem = DayItem(type: .linear, lift: "Bench Press", name: "Bench 5x5", sets: 5, reps: 5)
        let deadliftItem = DayItem(type: .linear, lift: "Deadlift", name: "Deadlift 1x5", sets: 1, reps: 5)
        
        return ProgramState(
            rounding: 5,
            initialMaxes: initialMaxes,
            singleAt8Percent: [:],
            lifts: [:],
            days: [
                1: [squatItem, benchItem],
                2: [squatItem, deadliftItem]
            ],
            weeks: Array(1...12),
            linearProgressionConfig: config
        )
    }
    
    // MARK: - Gather Linear Lifts Tests
    
    func testGatherLinearLifts() {
        let state = createLinearProgramState()
        let lifts = engine.gatherLinearLifts(from: state)
        
        XCTAssertEqual(lifts.count, 3)
        XCTAssertTrue(lifts.contains("Squat"))
        XCTAssertTrue(lifts.contains("Bench Press"))
        XCTAssertTrue(lifts.contains("Deadlift"))
    }
    
    func testGatherLinearLiftsExcludesNonLinear() {
        var state = createLinearProgramState()
        state.days[3] = [DayItem(type: .volume, lift: "OHP", name: "OHP Volume")]
        
        let lifts = engine.gatherLinearLifts(from: state)
        
        XCTAssertFalse(lifts.contains("OHP"))
    }
    
    // MARK: - Initial Weight Tests
    
    func testInitialWeightIsStartingMax() {
        let state = createLinearProgramState(initialMaxes: ["Squat": 135])
        
        let (weight, failures) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 1,
            day: 1
        )
        
        XCTAssertEqual(weight, 135)
        XCTAssertEqual(failures, 0)
    }
    
    // MARK: - Success Progression Tests
    
    func testWeightIncreasesAfterSuccess() {
        var state = createLinearProgramState(initialMaxes: ["Squat": 135])
        
        // Log a successful session on week 1, day 1
        state.linearLogs["Squat"] = [
            1: [1: LinearLogEntry(completed: true, weight: 135)]
        ]
        
        // Next session should have increased weight
        let (weight, failures) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 1,
            day: 2
        )
        
        XCTAssertEqual(weight, 140) // 135 + 5 (default increment)
        XCTAssertEqual(failures, 0)
    }
    
    func testMultipleSuccessfulSessions() {
        var state = createLinearProgramState(initialMaxes: ["Squat": 135])
        
        // Log 3 successful sessions
        state.linearLogs["Squat"] = [
            1: [
                1: LinearLogEntry(completed: true, weight: 135),
                2: LinearLogEntry(completed: true, weight: 140)
            ],
            2: [
                1: LinearLogEntry(completed: true, weight: 145)
            ]
        ]
        
        // Next session (week 2, day 2)
        let (weight, _) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 2,
            day: 2
        )
        
        // 135 + 5 + 5 + 5 = 150
        XCTAssertEqual(weight, 150)
    }
    
    func testDeadliftIncrementIs10() {
        var state = createLinearProgramState(
            initialMaxes: ["Deadlift": 135],
            config: LinearProgressionConfig(
                defaultIncrement: 5.0,
                liftIncrements: ["Deadlift": 10.0]
            )
        )
        
        state.linearLogs["Deadlift"] = [
            1: [2: LinearLogEntry(completed: true, weight: 135)]
        ]
        
        let (weight, _) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Deadlift",
            week: 2,
            day: 1
        )
        
        XCTAssertEqual(weight, 145) // 135 + 10
    }
    
    // MARK: - Failure Tests
    
    func testSingleFailureKeepsWeight() {
        var state = createLinearProgramState(initialMaxes: ["Squat": 185])
        
        state.linearLogs["Squat"] = [
            1: [1: LinearLogEntry(completed: false, consecutiveFailures: 1, weight: 185)]
        ]
        
        let (weight, failures) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 1,
            day: 2
        )
        
        XCTAssertEqual(weight, 185) // Same weight
        XCTAssertEqual(failures, 1)
    }
    
    func testConsecutiveFailuresTracking() {
        var state = createLinearProgramState(initialMaxes: ["Squat": 185])
        
        state.linearLogs["Squat"] = [
            1: [
                1: LinearLogEntry(completed: false, weight: 185),
                2: LinearLogEntry(completed: false, weight: 185)
            ]
        ]
        
        let (weight, failures) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 2,
            day: 1
        )
        
        XCTAssertEqual(weight, 185) // Still same weight
        XCTAssertEqual(failures, 2) // 2 consecutive failures
    }
    
    func testDeloadAfterThreeFailures() {
        var state = createLinearProgramState(
            initialMaxes: ["Squat": 200],
            config: LinearProgressionConfig(
                defaultIncrement: 5.0,
                failuresBeforeDeload: 3,
                deloadPercentage: 0.10
            )
        )
        
        // Three failures in a row
        state.linearLogs["Squat"] = [
            1: [
                1: LinearLogEntry(completed: false, weight: 200),
                2: LinearLogEntry(completed: false, weight: 200)
            ],
            2: [
                1: LinearLogEntry(completed: false, weight: 200)
            ]
        ]
        
        let (weight, failures) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 2,
            day: 2
        )
        
        // 200 * 0.9 = 180
        XCTAssertEqual(weight, 180)
        XCTAssertEqual(failures, 0) // Reset after deload
    }
    
    func testDeloadResetsFailureCount() {
        var state = createLinearProgramState(
            initialMaxes: ["Squat": 200],
            config: LinearProgressionConfig(failuresBeforeDeload: 3, deloadPercentage: 0.10)
        )
        
        // Three failures trigger deload, then a success
        state.linearLogs["Squat"] = [
            1: [
                1: LinearLogEntry(completed: false, weight: 200),
                2: LinearLogEntry(completed: false, weight: 200)
            ],
            2: [
                1: LinearLogEntry(completed: false, weight: 200),
                2: LinearLogEntry(completed: true, weight: 180) // After deload
            ]
        ]
        
        let (weight, failures) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 3,
            day: 1
        )
        
        // 180 + 5 = 185
        XCTAssertEqual(weight, 185)
        XCTAssertEqual(failures, 0)
    }
    
    // MARK: - Is Deload Pending Tests
    
    func testIsDeloadPendingTrue() {
        var state = createLinearProgramState(
            initialMaxes: ["Squat": 200],
            config: LinearProgressionConfig(failuresBeforeDeload: 3)
        )
        
        // Two consecutive failures (one more triggers deload)
        state.linearLogs["Squat"] = [
            1: [
                1: LinearLogEntry(completed: false, weight: 200),
                2: LinearLogEntry(completed: false, weight: 200)
            ]
        ]
        
        let isPending = engine.isDeloadPending(state: state, lift: "Squat", week: 2)
        XCTAssertTrue(isPending)
    }
    
    func testIsDeloadPendingFalse() {
        var state = createLinearProgramState(
            initialMaxes: ["Squat": 200],
            config: LinearProgressionConfig(failuresBeforeDeload: 3)
        )
        
        // Only one failure
        state.linearLogs["Squat"] = [
            1: [1: LinearLogEntry(completed: false, weight: 200)]
        ]
        
        let isPending = engine.isDeloadPending(state: state, lift: "Squat", week: 2)
        XCTAssertFalse(isPending)
    }
    
    // MARK: - Week Plan Linear Item Tests
    
    func testWeekPlanLinearItem() throws {
        let state = createLinearProgramState(initialMaxes: ["Squat": 135])
        let plan = try engine.weekPlan(state: state, week: 1)
        
        guard case let .linear(name, info) = plan[1]?.first else {
            XCTFail("Expected linear item")
            return
        }
        
        XCTAssertEqual(name, "Squat 5x5")
        XCTAssertEqual(info.lift, "Squat")
        XCTAssertEqual(info.weight, 135)
        XCTAssertEqual(info.sets, 5)
        XCTAssertEqual(info.reps, 5)
        XCTAssertEqual(info.consecutiveFailures, 0)
        XCTAssertEqual(info.increment, 5.0)
        XCTAssertFalse(info.isDeloadPending)
    }
    
    func testWeekPlanLinearItemWithProgress() throws {
        var state = createLinearProgramState(initialMaxes: ["Squat": 135])
        
        // Log successful sessions
        state.linearLogs["Squat"] = [
            1: [1: LinearLogEntry(completed: true, weight: 135)]
        ]
        
        let plan = try engine.weekPlan(state: state, week: 1)
        
        // Day 2 should show increased weight
        guard case let .linear(_, info) = plan[2]?.first else {
            XCTFail("Expected linear item")
            return
        }
        
        XCTAssertEqual(info.weight, 140)
    }
    
    // MARK: - Rounding Tests
    
    func testWeightRoundsToNearestIncrement() {
        var state = createLinearProgramState(
            initialMaxes: ["Squat": 137],
            config: LinearProgressionConfig(deloadPercentage: 0.10)
        )
        state.rounding = 5
        
        // Three failures trigger deload
        state.linearLogs["Squat"] = [
            1: [
                1: LinearLogEntry(completed: false, weight: 137),
                2: LinearLogEntry(completed: false, weight: 137)
            ],
            2: [
                1: LinearLogEntry(completed: false, weight: 137)
            ]
        ]
        
        let (weight, _) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 2,
            day: 2
        )
        
        // 137 * 0.9 = 123.3, rounded to 125
        XCTAssertEqual(weight, 125)
    }
    
    // MARK: - Edge Cases
    
    func testSuccessAfterFailure() {
        var state = createLinearProgramState(initialMaxes: ["Squat": 185])
        
        // Fail then succeed
        state.linearLogs["Squat"] = [
            1: [
                1: LinearLogEntry(completed: false, weight: 185),
                2: LinearLogEntry(completed: true, weight: 185)
            ]
        ]
        
        let (weight, failures) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 2,
            day: 1
        )
        
        // Success adds weight and resets failures
        XCTAssertEqual(weight, 190)
        XCTAssertEqual(failures, 0)
    }
    
    func testInterleavedSuccessAndFailure() {
        var state = createLinearProgramState(initialMaxes: ["Squat": 185])
        
        // S-F-S pattern (never deload)
        state.linearLogs["Squat"] = [
            1: [
                1: LinearLogEntry(completed: true, weight: 185),   // +5 -> 190
                2: LinearLogEntry(completed: false, weight: 190)   // fail, failures=1
            ],
            2: [
                1: LinearLogEntry(completed: true, weight: 190)    // +5 -> 195, reset
            ]
        ]
        
        let (weight, failures) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 2,
            day: 2
        )
        
        XCTAssertEqual(weight, 195)
        XCTAssertEqual(failures, 0)
    }
    
    func testEmptyLogsReturnsInitialWeight() {
        let state = createLinearProgramState(initialMaxes: ["Squat": 135])
        
        let (weight, failures) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 5,
            day: 2
        )
        
        XCTAssertEqual(weight, 135)
        XCTAssertEqual(failures, 0)
    }
    
    func testOnlyFutureLogsIgnored() {
        var state = createLinearProgramState(initialMaxes: ["Squat": 135])
        
        // Log something in the future
        state.linearLogs["Squat"] = [
            5: [1: LinearLogEntry(completed: true, weight: 200)]
        ]
        
        // Should ignore future logs
        let (weight, _) = engine.computeLinearWeightForSession(
            state: state,
            lift: "Squat",
            week: 1,
            day: 1
        )
        
        XCTAssertEqual(weight, 135)
    }
}



