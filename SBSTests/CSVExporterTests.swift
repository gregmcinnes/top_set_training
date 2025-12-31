import XCTest
@testable import SBSApp

/// Tests for CSV export functionality
final class CSVExporterTests: XCTestCase {
    
    // MARK: - Basic Export Tests
    
    func testExportEmptyPlan() {
        let plan: [Int: [PlanItem]] = [:]
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        // Should only have header row
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1)
    }
    
    func testExportHasHeader() {
        let plan: [Int: [PlanItem]] = [
            1: [.tm(name: "Squat", lift: "Squat", trainingMax: 300, topSingleAt8: 270)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        let lines = csv.components(separatedBy: "\n")
        
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        
        // Header should contain expected fields
        let header = lines[0]
        XCTAssertTrue(header.contains("Week"))
        XCTAssertTrue(header.contains("Day"))
        XCTAssertTrue(header.contains("Name"))
        XCTAssertTrue(header.contains("Type"))
    }
    
    // MARK: - TM Item Export Tests
    
    func testExportTMItem() {
        let plan: [Int: [PlanItem]] = [
            1: [.tm(name: "Squat", lift: "Squat", trainingMax: 315.5, topSingleAt8: 284.25)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 3)
        
        XCTAssertTrue(csv.contains("Squat"))
        XCTAssertTrue(csv.contains("tm"))
        XCTAssertTrue(csv.contains("315.50"))
        XCTAssertTrue(csv.contains("284.25"))
        XCTAssertTrue(csv.contains("3")) // Week 3
    }
    
    // MARK: - Volume Item Export Tests
    
    func testExportVolumeItem() {
        let plan: [Int: [PlanItem]] = [
            2: [.volume(
                name: "Bench Press",
                lift: "Bench Press",
                weight: 185.0,
                intensity: 0.75,
                sets: 4,
                repsPerSet: 8,
                repOutTarget: 10,
                loggedRepsLastSet: nil,
                nextWeekTmDelta: nil,
                isWeightOverridden: false,
                calculatedWeight: 185.0
            )]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 5)
        
        XCTAssertTrue(csv.contains("Bench Press"))
        XCTAssertTrue(csv.contains("volume"))
        XCTAssertTrue(csv.contains("185.00"))
        XCTAssertTrue(csv.contains("8")) // reps per set
        XCTAssertTrue(csv.contains("10")) // rep out target
    }
    
    // MARK: - Structured Item Export Tests
    
    func testExportStructuredItem() {
        let sets = [
            StructuredSetInfo(setIndex: 0, intensity: 0.75, targetReps: 5, isAMRAP: false, weight: 150),
            StructuredSetInfo(setIndex: 1, intensity: 0.85, targetReps: 3, isAMRAP: false, weight: 170),
            StructuredSetInfo(setIndex: 2, intensity: 0.95, targetReps: 1, isAMRAP: true, weight: 190)
        ]
        
        let plan: [Int: [PlanItem]] = [
            1: [.structured(
                name: "OHP",
                lift: "OHP",
                trainingMax: 135.0,
                sets: sets,
                logEntry: nil
            )]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        XCTAssertTrue(csv.contains("OHP"))
        XCTAssertTrue(csv.contains("structured"))
        XCTAssertTrue(csv.contains("135.00")) // TM
        XCTAssertTrue(csv.contains("3")) // 3 sets
        XCTAssertTrue(csv.contains("190.00")) // Heaviest weight
    }
    
    func testExportStructuredItemUsesHeaviestWeight() {
        let sets = [
            StructuredSetInfo(setIndex: 0, intensity: 0.65, targetReps: 5, isAMRAP: false, weight: 130),
            StructuredSetInfo(setIndex: 1, intensity: 0.95, targetReps: 1, isAMRAP: true, weight: 190), // Heaviest
            StructuredSetInfo(setIndex: 2, intensity: 0.70, targetReps: 5, isAMRAP: false, weight: 140)
        ]
        
        let plan: [Int: [PlanItem]] = [
            1: [.structured(name: "Test", lift: "Test", trainingMax: 200, sets: sets, logEntry: nil)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        // Should contain 190 (the heaviest weight), not 140
        XCTAssertTrue(csv.contains("190.00"))
    }
    
    // MARK: - Accessory Item Export Tests
    
    func testExportAccessoryItem() {
        let plan: [Int: [PlanItem]] = [
            1: [.accessory(name: "Cable Rows", sets: 4, reps: 12, lastLog: nil)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        XCTAssertTrue(csv.contains("Cable Rows"))
        XCTAssertTrue(csv.contains("accessory"))
        XCTAssertTrue(csv.contains("4")) // sets
        XCTAssertTrue(csv.contains("12")) // reps
    }
    
    func testExportAccessoryItemWithLastLog() {
        let lastLog = AccessoryLog(weight: 100, sets: 4, reps: 12, note: "")
        let plan: [Int: [PlanItem]] = [
            1: [.accessory(name: "Face Pulls", sets: 3, reps: 15, lastLog: lastLog)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        XCTAssertTrue(csv.contains("Face Pulls"))
        XCTAssertTrue(csv.contains("100.00")) // Weight from last log
    }
    
    // MARK: - Linear Item Export Tests
    
    func testExportLinearItem() {
        let info = LinearExerciseInfo(
            lift: "Squat",
            weight: 185.0,
            sets: 5,
            reps: 5,
            consecutiveFailures: 1,
            increment: 5.0,
            isDeloadPending: false,
            logEntry: nil
        )
        
        let plan: [Int: [PlanItem]] = [
            1: [.linear(name: "Squat 5x5", info: info)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        XCTAssertTrue(csv.contains("Squat 5x5"))
        XCTAssertTrue(csv.contains("linear"))
        XCTAssertTrue(csv.contains("185.00"))
        XCTAssertTrue(csv.contains("5")) // sets and reps
        XCTAssertTrue(csv.contains("5.00")) // increment
        XCTAssertTrue(csv.contains("1")) // consecutive failures
    }
    
    // MARK: - Multiple Days Tests
    
    func testExportMultipleDays() {
        let plan: [Int: [PlanItem]] = [
            1: [.tm(name: "Squat", lift: "Squat", trainingMax: 300, topSingleAt8: 270)],
            2: [.tm(name: "Bench", lift: "Bench", trainingMax: 225, topSingleAt8: 202)],
            3: [.tm(name: "Deadlift", lift: "Deadlift", trainingMax: 400, topSingleAt8: 360)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        let lines = csv.components(separatedBy: "\n")
        
        // Header + 3 data rows
        XCTAssertEqual(lines.count, 4)
        
        XCTAssertTrue(csv.contains("Squat"))
        XCTAssertTrue(csv.contains("Bench"))
        XCTAssertTrue(csv.contains("Deadlift"))
    }
    
    func testExportDaysAreSorted() {
        let plan: [Int: [PlanItem]] = [
            3: [.tm(name: "Day3", lift: "Day3", trainingMax: 100, topSingleAt8: 90)],
            1: [.tm(name: "Day1", lift: "Day1", trainingMax: 100, topSingleAt8: 90)],
            2: [.tm(name: "Day2", lift: "Day2", trainingMax: 100, topSingleAt8: 90)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        let lines = csv.components(separatedBy: "\n")
        
        // Check order in output (after header)
        let day1Index = csv.range(of: "Day1")?.lowerBound
        let day2Index = csv.range(of: "Day2")?.lowerBound
        let day3Index = csv.range(of: "Day3")?.lowerBound
        
        XCTAssertNotNil(day1Index)
        XCTAssertNotNil(day2Index)
        XCTAssertNotNil(day3Index)
        
        XCTAssertLessThan(day1Index!, day2Index!)
        XCTAssertLessThan(day2Index!, day3Index!)
    }
    
    // MARK: - Multiple Items Per Day Tests
    
    func testExportMultipleItemsPerDay() {
        let plan: [Int: [PlanItem]] = [
            1: [
                .tm(name: "Squat", lift: "Squat", trainingMax: 300, topSingleAt8: 270),
                .volume(
                    name: "Squat Volume",
                    lift: "Squat",
                    weight: 210,
                    intensity: 0.70,
                    sets: 4,
                    repsPerSet: 8,
                    repOutTarget: 10,
                    loggedRepsLastSet: nil,
                    nextWeekTmDelta: nil,
                    isWeightOverridden: false,
                    calculatedWeight: 210
                ),
                .accessory(name: "Leg Press", sets: 4, reps: 10, lastLog: nil)
            ]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        let lines = csv.components(separatedBy: "\n")
        
        // Header + 3 items
        XCTAssertEqual(lines.count, 4)
        
        XCTAssertTrue(csv.contains("Squat"))
        XCTAssertTrue(csv.contains("Squat Volume"))
        XCTAssertTrue(csv.contains("Leg Press"))
    }
    
    // MARK: - CSV Escaping Tests
    
    func testEscapeCommaInName() {
        let plan: [Int: [PlanItem]] = [
            1: [.accessory(name: "Rows, Cable", sets: 4, reps: 10, lastLog: nil)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        // Should be quoted
        XCTAssertTrue(csv.contains("\"Rows, Cable\""))
    }
    
    func testEscapeQuoteInName() {
        let plan: [Int: [PlanItem]] = [
            1: [.accessory(name: "\"Air\" Squats", sets: 4, reps: 10, lastLog: nil)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        // Quotes should be doubled and wrapped
        XCTAssertTrue(csv.contains("\"\"\"Air\"\" Squats\""))
    }
    
    func testEscapeNewlineInNote() {
        // Note: The current implementation doesn't export notes, 
        // but this tests the escaping function
        let plan: [Int: [PlanItem]] = [
            1: [.accessory(name: "Test\nExercise", sets: 4, reps: 10, lastLog: nil)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        // Newlines should be wrapped in quotes
        XCTAssertTrue(csv.contains("\"Test\nExercise\""))
    }
    
    // MARK: - Week Number Tests
    
    func testWeekNumberInOutput() {
        let plan: [Int: [PlanItem]] = [
            1: [.tm(name: "Squat", lift: "Squat", trainingMax: 300, topSingleAt8: 270)]
        ]
        
        // Test different weeks
        let week5Csv = CSVExporter.exportWeekCSV(plan: plan, week: 5)
        let week12Csv = CSVExporter.exportWeekCSV(plan: plan, week: 12)
        
        XCTAssertTrue(week5Csv.contains(",5,") || week5Csv.contains("5,") || week5Csv.contains(",5\n"))
        XCTAssertTrue(week12Csv.contains(",12,") || week12Csv.contains("12,") || week12Csv.contains(",12\n"))
    }
    
    // MARK: - Field Names Tests
    
    func testFieldNamesAreSorted() {
        let plan: [Int: [PlanItem]] = [
            1: [
                .tm(name: "Squat", lift: "Squat", trainingMax: 300, topSingleAt8: 270),
                .volume(
                    name: "Volume",
                    lift: "Squat",
                    weight: 210,
                    intensity: 0.70,
                    sets: 4,
                    repsPerSet: 8,
                    repOutTarget: 10,
                    loggedRepsLastSet: nil,
                    nextWeekTmDelta: nil,
                    isWeightOverridden: false,
                    calculatedWeight: 210
                )
            ]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        let header = csv.components(separatedBy: "\n").first ?? ""
        let fields = header.components(separatedBy: ",")
        
        // Fields should be sorted alphabetically
        let sortedFields = fields.sorted()
        XCTAssertEqual(fields, sortedFields)
    }
    
    // MARK: - Missing Values Tests
    
    func testMissingValuesAreEmpty() {
        let plan: [Int: [PlanItem]] = [
            1: [.accessory(name: "Curls", sets: 3, reps: 12, lastLog: nil)]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 1)
        
        // Accessory doesn't have TM, so that field should be empty
        // The row should have the right number of commas
        let lines = csv.components(separatedBy: "\n")
        guard lines.count > 1 else {
            XCTFail("Expected data rows")
            return
        }
        
        let header = lines[0]
        let dataRow = lines[1]
        
        let headerFields = header.components(separatedBy: ",").count
        let dataFields = dataRow.components(separatedBy: ",").count
        
        XCTAssertEqual(headerFields, dataFields)
    }
    
    // MARK: - Full Integration Test
    
    func testFullWorkoutExport() {
        // Create a realistic workout plan
        let plan: [Int: [PlanItem]] = [
            1: [
                .tm(name: "Squat TM", lift: "Squat", trainingMax: 315, topSingleAt8: 283),
                .volume(
                    name: "Squat",
                    lift: "Squat",
                    weight: 220,
                    intensity: 0.70,
                    sets: 4,
                    repsPerSet: 8,
                    repOutTarget: 10,
                    loggedRepsLastSet: 12,
                    nextWeekTmDelta: 0.01,
                    isWeightOverridden: false,
                    calculatedWeight: 220
                ),
                .accessory(name: "Leg Press", sets: 4, reps: 10, lastLog: nil),
                .accessory(name: "Leg Curls", sets: 3, reps: 12, lastLog: nil)
            ],
            2: [
                .structured(
                    name: "Bench Press",
                    lift: "Bench Press",
                    trainingMax: 225,
                    sets: [
                        StructuredSetInfo(setIndex: 0, intensity: 0.75, targetReps: 5, isAMRAP: false, weight: 170),
                        StructuredSetInfo(setIndex: 1, intensity: 0.85, targetReps: 3, isAMRAP: false, weight: 190),
                        StructuredSetInfo(setIndex: 2, intensity: 0.95, targetReps: 1, isAMRAP: true, weight: 215)
                    ],
                    logEntry: nil
                ),
                .linear(
                    name: "OHP 5x5",
                    info: LinearExerciseInfo(
                        lift: "OHP",
                        weight: 95,
                        sets: 5,
                        reps: 5,
                        consecutiveFailures: 0,
                        increment: 5,
                        isDeloadPending: false,
                        logEntry: nil
                    )
                )
            ]
        ]
        
        let csv = CSVExporter.exportWeekCSV(plan: plan, week: 8)
        let lines = csv.components(separatedBy: "\n")
        
        // Header + 6 data rows
        XCTAssertEqual(lines.count, 7)
        
        // Verify all items are present
        XCTAssertTrue(csv.contains("Squat TM"))
        XCTAssertTrue(csv.contains("Squat"))
        XCTAssertTrue(csv.contains("Leg Press"))
        XCTAssertTrue(csv.contains("Leg Curls"))
        XCTAssertTrue(csv.contains("Bench Press"))
        XCTAssertTrue(csv.contains("OHP 5x5"))
        
        // Verify week number
        XCTAssertTrue(csv.contains("8"))
        
        // Verify all types are present
        XCTAssertTrue(csv.contains("tm"))
        XCTAssertTrue(csv.contains("volume"))
        XCTAssertTrue(csv.contains("accessory"))
        XCTAssertTrue(csv.contains("structured"))
        XCTAssertTrue(csv.contains("linear"))
    }
}

