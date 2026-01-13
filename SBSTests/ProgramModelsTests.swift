import XCTest
@testable import SBSApp

/// Tests for all program data models
final class ProgramModelsTests: XCTestCase {
    
    // MARK: - LiftRecord Tests
    
    func testLiftRecordE1RMCalculation() {
        // Epley formula: E1RM = weight * (1 + reps / 30)
        let record = LiftRecord(
            liftName: "Squat",
            weight: 300,
            reps: 5
        )
        
        // E1RM = 300 * (1 + 5/30) = 300 * 1.167 = 350
        XCTAssertEqual(record.estimatedOneRM, 350, accuracy: 0.01)
    }
    
    func testLiftRecordWithProvidedE1RM() {
        let record = LiftRecord(
            liftName: "Bench Press",
            weight: 225,
            reps: 3,
            estimatedOneRM: 250 // Override the calculation
        )
        
        XCTAssertEqual(record.estimatedOneRM, 250)
    }
    
    func testLiftRecordSingleRep() {
        // For 1 rep, E1RM should equal weight
        let record = LiftRecord(
            liftName: "Deadlift",
            weight: 500,
            reps: 1
        )
        
        // E1RM = 500 * (1 + 1/30) = 500 * 1.033 = 516.67
        XCTAssertEqual(record.estimatedOneRM, 500 * (1 + 1.0/30.0), accuracy: 0.01)
    }
    
    // MARK: - SetDetail Tests
    
    func testSetDetailInitialization() {
        let setDetail = SetDetail(intensity: 0.85, reps: 3, isAMRAP: true)
        
        XCTAssertEqual(setDetail.intensity, 0.85)
        XCTAssertEqual(setDetail.reps, 3)
        XCTAssertTrue(setDetail.isAMRAP)
    }
    
    func testSetDetailDefaultsNotAMRAP() {
        let setDetail = SetDetail(intensity: 0.75, reps: 5)
        
        XCTAssertFalse(setDetail.isAMRAP)
    }
    
    // MARK: - LogEntry Tests
    
    func testLogEntryWithReps() {
        let entry = LogEntry(repsLastSet: 12, note: "Felt good")
        
        XCTAssertEqual(entry.repsLastSet, 12)
        XCTAssertEqual(entry.note, "Felt good")
        XCTAssertNil(entry.weightOverride)
    }
    
    func testLogEntryWithWeightOverride() {
        let entry = LogEntry(repsLastSet: 8, note: "", weightOverride: 275)
        
        XCTAssertEqual(entry.weightOverride, 275)
    }
    
    // MARK: - StructuredLogEntry Tests
    
    func testStructuredLogEntry() {
        var entry = StructuredLogEntry()
        entry.amrapReps[2] = 5 // 3rd set (index 2) got 5 reps
        entry.amrapReps[8] = 12 // 9th set got 12 reps
        
        XCTAssertEqual(entry.amrapReps[2], 5)
        XCTAssertEqual(entry.amrapReps[8], 12)
        XCTAssertNil(entry.amrapReps[0])
    }
    
    // MARK: - AccessoryLog Tests
    
    func testAccessoryLogDefaults() {
        let log = AccessoryLog(weight: 50)
        
        XCTAssertEqual(log.weight, 50)
        XCTAssertEqual(log.sets, 4)
        XCTAssertEqual(log.reps, 10)
        XCTAssertEqual(log.note, "")
    }
    
    func testAccessoryLogCustomValues() {
        let log = AccessoryLog(weight: 70, sets: 3, reps: 12, note: "Face pulls")
        
        XCTAssertEqual(log.weight, 70)
        XCTAssertEqual(log.sets, 3)
        XCTAssertEqual(log.reps, 12)
        XCTAssertEqual(log.note, "Face pulls")
    }
    
    // MARK: - LinearLogEntry Tests
    
    func testLinearLogEntrySuccess() {
        let entry = LinearLogEntry(completed: true, weight: 135)
        
        XCTAssertTrue(entry.completed)
        XCTAssertEqual(entry.consecutiveFailures, 0)
        XCTAssertFalse(entry.deloadApplied)
    }
    
    func testLinearLogEntryFailure() {
        let entry = LinearLogEntry(
            completed: false,
            consecutiveFailures: 2,
            deloadApplied: false,
            weight: 185
        )
        
        XCTAssertFalse(entry.completed)
        XCTAssertEqual(entry.consecutiveFailures, 2)
    }
    
    // MARK: - LinearProgressionConfig Tests
    
    func testLinearProgressionConfigDefaults() {
        let config = LinearProgressionConfig()
        
        XCTAssertEqual(config.defaultIncrement, 5.0)
        XCTAssertEqual(config.failuresBeforeDeload, 3)
        XCTAssertEqual(config.deloadPercentage, 0.10)
        XCTAssertTrue(config.liftIncrements.isEmpty)
    }
    
    func testLinearProgressionConfigCustomIncrements() {
        let config = LinearProgressionConfig(
            defaultIncrement: 5.0,
            liftIncrements: ["Deadlift": 10.0, "OHP": 2.5]
        )
        
        XCTAssertEqual(config.increment(for: "Deadlift"), 10.0)
        XCTAssertEqual(config.increment(for: "OHP"), 2.5)
        XCTAssertEqual(config.increment(for: "Bench Press"), 5.0) // Falls back to default
    }
    
    // MARK: - DayItem Tests
    
    func testDayItemVolume() {
        let item = DayItem(type: .volume, lift: "Squat", name: "Main Squat")
        
        XCTAssertEqual(item.type, .volume)
        XCTAssertEqual(item.lift, "Squat")
        XCTAssertEqual(item.name, "Main Squat")
    }
    
    func testDayItemAccessory() {
        let item = DayItem(
            type: .accessory,
            lift: nil,
            name: "Cable Rows",
            defaultSets: 4,
            defaultReps: 12
        )
        
        XCTAssertEqual(item.type, .accessory)
        XCTAssertNil(item.lift)
        XCTAssertEqual(item.defaultSets, 4)
        XCTAssertEqual(item.defaultReps, 12)
    }
    
    func testDayItemStructured() {
        let sets = [
            SetDetail(intensity: 0.75, reps: 5),
            SetDetail(intensity: 0.85, reps: 3),
            SetDetail(intensity: 0.95, reps: 1, isAMRAP: true)
        ]
        
        let item = DayItem(
            type: .structured,
            lift: "Bench Press",
            name: "Bench Press",
            setsDetail: sets
        )
        
        XCTAssertEqual(item.type, .structured)
        XCTAssertEqual(item.setsDetail?.count, 3)
        XCTAssertTrue(item.setsDetail?[2].isAMRAP ?? false)
    }
    
    func testDayItemLinear() {
        let item = DayItem(
            type: .linear,
            lift: "Squat",
            name: "Squat 5x5",
            sets: 5,
            reps: 5
        )
        
        XCTAssertEqual(item.type, .linear)
        XCTAssertEqual(item.sets, 5)
        XCTAssertEqual(item.reps, 5)
    }
    
    // MARK: - WeekData Tests
    
    func testWeekDataProperties() {
        // Simulating JSON decoding
        let json = """
        {
            "Intensity": 0.75,
            "Reps per normal set": 8,
            "Rep out target": 10,
            "Sets": 4
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let weekData = try! decoder.decode(WeekData.self, from: json)
        
        XCTAssertEqual(weekData.intensity, 0.75)
        XCTAssertEqual(weekData.repsPerNormalSet, 8)
        XCTAssertEqual(weekData.repOutTarget, 10)
        XCTAssertEqual(weekData.sets, 4)
    }
    
    // MARK: - ProgramData Tests
    
    func testProgramDataInitialization() {
        let programData = ProgramData(
            name: "TestProgram",
            displayName: "Test Program",
            programDescription: "A test program",
            rounding: 5,
            singleAt8Percent: ["Squat": 0.9, "Bench Press": 0.9],
            initialMaxes: ["Squat": 300, "Bench Press": 225],
            lifts: [:],
            days: [:],
            weeks: Array(1...12)
        )
        
        XCTAssertEqual(programData.name, "TestProgram")
        XCTAssertEqual(programData.displayName, "Test Program")
        XCTAssertEqual(programData.rounding, 5)
        XCTAssertEqual(programData.weeks.count, 12)
    }
    
    // MARK: - ProgramState Tests
    
    func testProgramStateFromProgramData() {
        let weekDataDict: [String: WeekData] = [:]
        let programData = ProgramData(
            name: "TestProgram",
            rounding: 5,
            singleAt8Percent: ["Squat": 0.9],
            initialMaxes: ["Squat": 300],
            lifts: ["Squat": weekDataDict],
            days: ["1": [DayItem(type: .volume, lift: "Squat", name: "Squat")]],
            weeks: [1, 2, 3, 4]
        )
        
        let state = ProgramState.fromProgramData(programData)
        
        XCTAssertEqual(state.rounding, 5)
        XCTAssertEqual(state.initialMaxes["Squat"], 300)
        XCTAssertEqual(state.weeks, [1, 2, 3, 4])
        XCTAssertEqual(state.days.count, 1)
    }
    
    // MARK: - ProgramLevel Tests
    
    func testProgramLevelColors() {
        XCTAssertNotNil(ProgramLevel.beginner.color)
        XCTAssertNotNil(ProgramLevel.intermediate.color)
        XCTAssertNotNil(ProgramLevel.advanced.color)
    }
    
    func testProgramLevelIcons() {
        XCTAssertEqual(ProgramLevel.beginner.icon, "leaf.fill")
        XCTAssertEqual(ProgramLevel.intermediate.icon, "flame.fill")
        XCTAssertEqual(ProgramLevel.advanced.icon, "bolt.fill")
    }
    
    // MARK: - ProgramFocus Tests
    
    func testProgramFocusProperties() {
        XCTAssertEqual(ProgramFocus.strength.rawValue, "Strength")
        XCTAssertEqual(ProgramFocus.hypertrophy.rawValue, "Hypertrophy")
        XCTAssertEqual(ProgramFocus.balanced.rawValue, "Balanced")
    }
    
    // MARK: - CompletedCycle Tests
    
    func testCompletedCycleTMProgression() {
        let cycle = CompletedCycle(
            cycleNumber: 1,
            startDate: Date(),
            startingMaxes: ["Squat": 300, "Bench Press": 200],
            endingMaxes: ["Squat": 330, "Bench Press": 215],
            logs: [:],
            lastCompletedWeek: 12
        )
        
        // Squat: (330 - 300) / 300 * 100 = 10%
        XCTAssertEqual(cycle.tmProgression(for: "Squat")!, 10.0, accuracy: 0.01)
        
        // Bench: (215 - 200) / 200 * 100 = 7.5%
        XCTAssertEqual(cycle.tmProgression(for: "Bench Press")!, 7.5, accuracy: 0.01)
        
        // Unknown lift returns nil
        XCTAssertNil(cycle.tmProgression(for: "Deadlift"))
    }
    
    // MARK: - PlanItem Equatable Tests
    
    func testPlanItemEquatable() {
        let item1 = PlanItem.tm(name: "Squat", lift: "Squat", trainingMax: 300, topSingleAt8: 270)
        let item2 = PlanItem.tm(name: "Squat", lift: "Squat", trainingMax: 300, topSingleAt8: 270)
        let item3 = PlanItem.tm(name: "Squat", lift: "Squat", trainingMax: 305, topSingleAt8: 275)
        
        XCTAssertEqual(item1, item2)
        XCTAssertNotEqual(item1, item3)
    }
    
    // MARK: - Codable Tests
    
    func testLiftRecordCodable() throws {
        let original = LiftRecord(
            liftName: "Squat",
            weight: 315,
            reps: 5,
            programId: "test_program",
            week: 3,
            setType: "volume"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LiftRecord.self, from: data)
        
        XCTAssertEqual(original.liftName, decoded.liftName)
        XCTAssertEqual(original.weight, decoded.weight)
        XCTAssertEqual(original.reps, decoded.reps)
        XCTAssertEqual(original.estimatedOneRM, decoded.estimatedOneRM, accuracy: 0.01)
    }
    
    func testLinearProgressionConfigCodable() throws {
        let json = """
        {
            "default_increment": 5.0,
            "lift_increments": {"Deadlift": 10.0},
            "failures_before_deload": 3,
            "deload_percentage": 0.10
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let config = try decoder.decode(LinearProgressionConfig.self, from: json)
        
        XCTAssertEqual(config.defaultIncrement, 5.0)
        XCTAssertEqual(config.increment(for: "Deadlift"), 10.0)
        XCTAssertEqual(config.failuresBeforeDeload, 3)
        XCTAssertEqual(config.deloadPercentage, 0.10)
    }
}


