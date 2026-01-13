import XCTest
@testable import SBSApp

/// Tests for CustomTemplate creation and validation
final class CustomTemplateTests: XCTestCase {
    
    // MARK: - Basic Creation Tests
    
    func testDefaultTemplateCreation() {
        let template = CustomTemplate()
        
        XCTAssertNotNil(template.id)
        XCTAssertEqual(template.name, "")
        XCTAssertEqual(template.templateDescription, "")
        XCTAssertEqual(template.mode, .simple)
        XCTAssertEqual(template.daysPerWeek, 4)
        XCTAssertEqual(template.weeks, Array(1...12))
        XCTAssertTrue(template.days.isEmpty)
        XCTAssertEqual(template.rounding, 5.0)
    }
    
    func testCustomTemplateCreation() {
        let template = CustomTemplate(
            name: "My Program",
            templateDescription: "A custom lifting program",
            daysPerWeek: 3,
            weeks: Array(1...8),
            days: ["1": [DayItem(type: .volume, lift: "Squat", name: "Squat")]],
            initialMaxes: ["Squat": 300],
            rounding: 2.5
        )
        
        XCTAssertEqual(template.name, "My Program")
        XCTAssertEqual(template.templateDescription, "A custom lifting program")
        XCTAssertEqual(template.daysPerWeek, 3)
        XCTAssertEqual(template.weeks.count, 8)
        XCTAssertEqual(template.rounding, 2.5)
    }
    
    // MARK: - Template Mode Tests
    
    func testTemplateModeDisplayName() {
        XCTAssertEqual(TemplateMode.simple.displayName, "Simple")
        XCTAssertEqual(TemplateMode.advanced.displayName, "Advanced")
    }
    
    func testTemplateModeDescription() {
        XCTAssertTrue(TemplateMode.simple.description.contains("Fixed sets"))
        XCTAssertTrue(TemplateMode.advanced.description.contains("Percentage"))
    }
    
    // MARK: - Validation Tests
    
    func testValidTemplateWithMinimalData() {
        let template = CustomTemplate(
            name: "Valid Template",
            daysPerWeek: 1,
            weeks: [1],
            days: ["1": [DayItem(type: .accessory, lift: nil, name: "Curls")]]
        )
        
        XCTAssertTrue(template.isValid)
    }
    
    func testInvalidTemplateEmptyName() {
        let template = CustomTemplate(
            name: "",
            daysPerWeek: 1,
            weeks: [1],
            days: ["1": [DayItem(type: .accessory, lift: nil, name: "Curls")]]
        )
        
        XCTAssertFalse(template.isValid)
    }
    
    func testInvalidTemplateTooManyDays() {
        let template = CustomTemplate(
            name: "Too Many Days",
            daysPerWeek: 8,  // > 7
            weeks: [1],
            days: [:]
        )
        
        XCTAssertFalse(template.isValid)
    }
    
    func testInvalidTemplateZeroDays() {
        let template = CustomTemplate(
            name: "Zero Days",
            daysPerWeek: 0,
            weeks: [1],
            days: [:]
        )
        
        XCTAssertFalse(template.isValid)
    }
    
    func testInvalidTemplateNoWeeks() {
        let template = CustomTemplate(
            name: "No Weeks",
            daysPerWeek: 1,
            weeks: [],
            days: ["1": [DayItem(type: .accessory, lift: nil, name: "Curls")]]
        )
        
        XCTAssertFalse(template.isValid)
    }
    
    func testInvalidTemplateNoDays() {
        let template = CustomTemplate(
            name: "No Days",
            daysPerWeek: 1,
            weeks: [1],
            days: [:]
        )
        
        XCTAssertFalse(template.isValid)
    }
    
    func testInvalidTemplateEmptyDay() {
        let template = CustomTemplate(
            name: "Empty Day",
            daysPerWeek: 2,
            weeks: [1],
            days: [
                "1": [DayItem(type: .accessory, lift: nil, name: "Curls")],
                "2": []  // Empty!
            ]
        )
        
        XCTAssertFalse(template.isValid)
    }
    
    func testInvalidTemplateMissingDay() {
        let template = CustomTemplate(
            name: "Missing Day",
            daysPerWeek: 3,
            weeks: [1],
            days: [
                "1": [DayItem(type: .accessory, lift: nil, name: "Curls")],
                "3": [DayItem(type: .accessory, lift: nil, name: "Rows")]
                // Day 2 is missing!
            ]
        )
        
        XCTAssertFalse(template.isValid)
    }
    
    // MARK: - Duplicate Progression Set Tests
    
    func testNoDuplicateProgressionSets() {
        let template = CustomTemplate(
            name: "Valid",
            daysPerWeek: 2,
            weeks: [1],
            days: [
                "1": [DayItem(type: .structured, lift: "Squat", name: "Squat", progressionSetIndex: 2)],
                "2": [DayItem(type: .structured, lift: "Bench", name: "Bench", progressionSetIndex: 2)]
            ]
        )
        
        XCTAssertTrue(template.duplicateProgressionSetLifts.isEmpty)
        XCTAssertTrue(template.isValid)
    }
    
    func testDuplicateProgressionSetsInvalid() {
        let template = CustomTemplate(
            name: "Duplicate Progression",
            daysPerWeek: 2,
            weeks: [1],
            days: [
                "1": [DayItem(type: .structured, lift: "Squat", name: "Squat", progressionSetIndex: 2)],
                "2": [DayItem(type: .structured, lift: "Squat", name: "Squat Again", progressionSetIndex: 2)]
            ]
        )
        
        XCTAssertTrue(template.duplicateProgressionSetLifts.contains("Squat"))
        XCTAssertFalse(template.isValid)
    }
    
    func testNoProgressionSetIndexIsOk() {
        let template = CustomTemplate(
            name: "No Index",
            daysPerWeek: 2,
            weeks: [1],
            days: [
                "1": [DayItem(type: .structured, lift: "Squat", name: "Squat")],  // No progressionSetIndex
                "2": [DayItem(type: .structured, lift: "Squat", name: "Squat Again")]  // No progressionSetIndex
            ]
        )
        
        // Without progressionSetIndex, no conflicts
        XCTAssertTrue(template.duplicateProgressionSetLifts.isEmpty)
    }
    
    // MARK: - Validation Warnings Tests
    
    func testValidationWarningsForDuplicates() {
        let template = CustomTemplate(
            name: "Has Warnings",
            daysPerWeek: 2,
            weeks: [1],
            days: [
                "1": [DayItem(type: .volume, lift: "Squat", name: "Squat", progressionSetIndex: 0)],
                "2": [DayItem(type: .volume, lift: "Squat", name: "Squat Again", progressionSetIndex: 0)]
            ]
        )
        
        let warnings = template.validationWarnings
        
        XCTAssertGreaterThan(warnings.count, 0)
        XCTAssertTrue(warnings.first?.contains("Squat") ?? false)
    }
    
    func testNoValidationWarningsForValidTemplate() {
        let template = CustomTemplate(
            name: "Valid",
            daysPerWeek: 1,
            weeks: [1],
            days: ["1": [DayItem(type: .accessory, lift: nil, name: "Curls")]]
        )
        
        XCTAssertTrue(template.validationWarnings.isEmpty)
    }
    
    // MARK: - Tracked Lifts Tests
    
    func testTrackedLiftsExcludesAccessories() {
        let template = CustomTemplate(
            name: "Mixed",
            daysPerWeek: 1,
            weeks: [1],
            days: ["1": [
                DayItem(type: .volume, lift: "Squat", name: "Squat"),
                DayItem(type: .structured, lift: "Bench", name: "Bench"),
                DayItem(type: .accessory, lift: "Curls", name: "Curls"),  // Should be excluded
                DayItem(type: .linear, lift: "OHP", name: "OHP")
            ]]
        )
        
        let trackedLifts = template.trackedLifts
        
        XCTAssertEqual(trackedLifts.count, 3)
        XCTAssertTrue(trackedLifts.contains("Squat"))
        XCTAssertTrue(trackedLifts.contains("Bench"))
        XCTAssertTrue(trackedLifts.contains("OHP"))
        XCTAssertFalse(trackedLifts.contains("Curls"))
    }
    
    func testTrackedLiftsDeduplicated() {
        let template = CustomTemplate(
            name: "Duplicated",
            daysPerWeek: 2,
            weeks: [1],
            days: [
                "1": [DayItem(type: .volume, lift: "Squat", name: "Squat")],
                "2": [DayItem(type: .volume, lift: "Squat", name: "Squat")]
            ]
        )
        
        let trackedLifts = template.trackedLifts
        
        XCTAssertEqual(trackedLifts.count, 1)
        XCTAssertTrue(trackedLifts.contains("Squat"))
    }
    
    func testTrackedLiftsSorted() {
        let template = CustomTemplate(
            name: "Sorted",
            daysPerWeek: 1,
            weeks: [1],
            days: ["1": [
                DayItem(type: .volume, lift: "Squat", name: "Squat"),
                DayItem(type: .volume, lift: "Bench", name: "Bench"),
                DayItem(type: .volume, lift: "OHP", name: "OHP")
            ]]
        )
        
        let trackedLifts = template.trackedLifts
        
        XCTAssertEqual(trackedLifts, ["Bench", "OHP", "Squat"])
    }
    
    // MARK: - Convert to ProgramData Tests
    
    func testToProgramData() {
        let template = CustomTemplate(
            name: "My Template",
            templateDescription: "Test description",
            daysPerWeek: 4,
            weeks: Array(1...8),
            days: ["1": [DayItem(type: .volume, lift: "Squat", name: "Squat")]],
            initialMaxes: ["Squat": 300],
            singleAt8Percent: ["Squat": 0.88],
            rounding: 2.5
        )
        
        let programData = template.toProgramData()
        
        XCTAssertEqual(programData.name, "custom_\(template.id.uuidString)")
        XCTAssertEqual(programData.displayName, "My Template")
        XCTAssertEqual(programData.programDescription, "Test description")
        XCTAssertEqual(programData.rounding, 2.5)
        XCTAssertEqual(programData.weeks, Array(1...8))
        XCTAssertEqual(programData.initialMaxes["Squat"], 300)
        XCTAssertEqual(programData.singleAt8Percent["Squat"], 0.88)
    }
    
    func testToProgramDataDefaultSingleAt8() {
        let template = CustomTemplate(
            name: "No Single@8",
            daysPerWeek: 1,
            weeks: [1],
            days: ["1": [DayItem(type: .volume, lift: "Squat", name: "Squat")]],
            initialMaxes: ["Squat": 300, "Bench": 225],
            singleAt8Percent: [:]  // Empty
        )
        
        let programData = template.toProgramData()
        
        // Should generate default 0.9 for all tracked lifts
        XCTAssertEqual(programData.singleAt8Percent["Squat"], 0.9)
        XCTAssertEqual(programData.singleAt8Percent["Bench"], 0.9)
    }
    
    func testToProgramDataWithLinearConfig() {
        let config = LinearProgressionConfig(
            defaultIncrement: 5.0,
            liftIncrements: ["Deadlift": 10.0],
            failuresBeforeDeload: 3,
            deloadPercentage: 0.10
        )
        
        let template = CustomTemplate(
            name: "Linear",
            daysPerWeek: 1,
            weeks: [1],
            days: ["1": [DayItem(type: .linear, lift: "Squat", name: "Squat", sets: 5, reps: 5)]],
            linearProgressionConfig: config
        )
        
        let programData = template.toProgramData()
        
        XCTAssertNotNil(programData.linearProgressionConfig)
        XCTAssertEqual(programData.linearProgressionConfig?.defaultIncrement, 5.0)
        XCTAssertEqual(programData.linearProgressionConfig?.increment(for: "Deadlift"), 10.0)
    }
    
    // MARK: - Codable Tests
    
    func testCustomTemplateCodable() throws {
        let original = CustomTemplate(
            name: "Codable Test",
            templateDescription: "Test encoding/decoding",
            mode: .advanced,
            daysPerWeek: 3,
            weeks: [1, 2, 3, 4],
            days: [
                "1": [DayItem(type: .volume, lift: "Squat", name: "Squat")],
                "2": [DayItem(type: .accessory, lift: nil, name: "Rows", defaultSets: 4, defaultReps: 10)],
                "3": [DayItem(type: .linear, lift: "Bench", name: "Bench", sets: 5, reps: 5)]
            ],
            initialMaxes: ["Squat": 300, "Bench": 225],
            singleAt8Percent: ["Squat": 0.9, "Bench": 0.9],
            rounding: 2.5
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CustomTemplate.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.templateDescription, original.templateDescription)
        XCTAssertEqual(decoded.mode, original.mode)
        XCTAssertEqual(decoded.daysPerWeek, original.daysPerWeek)
        XCTAssertEqual(decoded.weeks, original.weeks)
        XCTAssertEqual(decoded.rounding, original.rounding)
    }
    
    func testCustomTemplateDecodeWithMissingOptionals() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "Minimal",
            "created_at": 0,
            "updated_at": 0,
            "days_per_week": 1,
            "weeks": [1],
            "days": {
                "1": [{"type": "accessory", "name": "Curls"}]
            }
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        let template = try decoder.decode(CustomTemplate.self, from: json)
        
        XCTAssertEqual(template.name, "Minimal")
        XCTAssertEqual(template.templateDescription, "")
        XCTAssertEqual(template.mode, .simple)  // Default
        XCTAssertEqual(template.rounding, 5.0)  // Default
        XCTAssertTrue(template.initialMaxes.isEmpty)
    }
    
    // MARK: - Identifiable Tests
    
    func testTemplateIdentifiable() {
        let template1 = CustomTemplate(name: "Template 1")
        let template2 = CustomTemplate(name: "Template 2")
        
        XCTAssertNotEqual(template1.id, template2.id)
    }
    
    // MARK: - Equatable Tests
    
    func testTemplateEquatable() {
        let id = UUID()
        let template1 = CustomTemplate(id: id, name: "Same")
        var template2 = CustomTemplate(id: id, name: "Same")
        template2.createdAt = template1.createdAt
        template2.updatedAt = template1.updatedAt
        
        XCTAssertEqual(template1, template2)
    }
    
    func testTemplateNotEqual() {
        let template1 = CustomTemplate(name: "Template 1")
        let template2 = CustomTemplate(name: "Template 2")
        
        XCTAssertNotEqual(template1, template2)
    }
    
    // MARK: - Advanced Mode Tests
    
    func testAdvancedModeWithLifts() {
        let weekData: [String: [String: WeekData]] = [
            "Squat": [
                "1": WeekData(intensity: 0.70, repsPerNormalSet: 8, repOutTarget: 10, sets: 4),
                "2": WeekData(intensity: 0.75, repsPerNormalSet: 6, repOutTarget: 8, sets: 4)
            ]
        ]
        
        let template = CustomTemplate(
            name: "Advanced",
            mode: .advanced,
            daysPerWeek: 1,
            weeks: [1, 2],
            days: ["1": [DayItem(type: .volume, lift: "Squat", name: "Squat")]],
            lifts: weekData
        )
        
        let programData = template.toProgramData()
        
        XCTAssertNotNil(programData.lifts["Squat"])
        XCTAssertEqual(programData.lifts["Squat"]?["1"]?.intensity, 0.70)
        XCTAssertEqual(programData.lifts["Squat"]?["2"]?.intensity, 0.75)
    }
    
    // MARK: - Update Date Tests
    
    func testCreatedAtAndUpdatedAt() {
        let template = CustomTemplate(name: "Test")
        
        XCTAssertLessThanOrEqual(
            abs(template.createdAt.timeIntervalSinceNow),
            1.0  // Within 1 second
        )
        XCTAssertLessThanOrEqual(
            abs(template.updatedAt.timeIntervalSinceNow),
            1.0
        )
    }
}


