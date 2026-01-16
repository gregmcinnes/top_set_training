import XCTest
@testable import SBSApp

/// Mock KeyValueStore for testing persistence without UserDefaults
final class MockKeyValueStore: KeyValueStore {
    private var storage: [String: Data] = [:]
    
    func set(_ value: Data, forKey key: String) {
        storage[key] = value
    }
    
    func data(forKey key: String) -> Data? {
        return storage[key]
    }
    
    func remove(forKey key: String) {
        storage.removeValue(forKey: key)
    }
    
    var isEmpty: Bool {
        storage.isEmpty
    }
    
    var keys: [String] {
        Array(storage.keys)
    }
}

/// Tests for data persistence
final class PersistenceTests: XCTestCase {
    
    var mockStore: MockKeyValueStore!
    var persistence: ProgramPersistence!
    
    override func setUp() {
        super.setUp()
        mockStore = MockKeyValueStore()
        persistence = ProgramPersistence(store: mockStore)
    }
    
    override func tearDown() {
        mockStore = nil
        persistence = nil
        super.tearDown()
    }
    
    // MARK: - UserSettings Tests
    
    func testSaveAndLoadSettings() throws {
        let settings = UserSettings(
            useMetric: true,
            roundingIncrement: 2.5,
            currentWeek: 5,
            currentDay: 3,
            restTimerDuration: 180,
            supersetAccessories: true,
            barWeight: 20.0,
            showPlateCalculator: false,
            playSoundNotifications: false,
            appearanceMode: .dark,
            bodyweight: 80,
            isMale: true
        )
        
        try persistence.saveSettings(settings)
        let loaded = persistence.loadSettings()
        
        XCTAssertEqual(loaded.useMetric, true)
        XCTAssertEqual(loaded.roundingIncrement, 2.5)
        XCTAssertEqual(loaded.currentWeek, 5)
        XCTAssertEqual(loaded.currentDay, 3)
        XCTAssertEqual(loaded.restTimerDuration, 180)
        XCTAssertEqual(loaded.supersetAccessories, true)
        XCTAssertEqual(loaded.barWeight, 20.0)
        XCTAssertEqual(loaded.showPlateCalculator, false)
        XCTAssertEqual(loaded.playSoundNotifications, false)
        XCTAssertEqual(loaded.appearanceMode, .dark)
        XCTAssertEqual(loaded.bodyweight, 80)
        XCTAssertEqual(loaded.isMale, true)
    }
    
    func testLoadSettingsReturnsDefaultWhenEmpty() {
        let settings = persistence.loadSettings()
        
        XCTAssertEqual(settings.useMetric, UserSettings.default.useMetric)
        XCTAssertEqual(settings.roundingIncrement, UserSettings.default.roundingIncrement)
        XCTAssertEqual(settings.currentWeek, UserSettings.default.currentWeek)
    }
    
    // MARK: - UserData Tests
    
    func testSaveAndLoadUserData() throws {
        var userData = UserData()
        userData.selectedProgram = "sbs_program_config"
        userData.customInitialMaxes = ["Squat": 300, "Bench Press": 225]
        userData.accessoryLogs["Cable Rows"] = AccessoryLog(weight: 100, sets: 4, reps: 12)
        userData.hasCompletedOnboarding = true
        
        try persistence.saveUserData(userData)
        let loaded = persistence.loadUserData()
        
        XCTAssertEqual(loaded.selectedProgram, "sbs_program_config")
        XCTAssertEqual(loaded.customInitialMaxes["Squat"], 300)
        XCTAssertEqual(loaded.customInitialMaxes["Bench Press"], 225)
        XCTAssertEqual(loaded.accessoryLogs["Cable Rows"]?.weight, 100)
        XCTAssertEqual(loaded.hasCompletedOnboarding, true)
    }
    
    func testSaveAndLoadLogs() throws {
        var userData = UserData()
        userData.logs["Squat"] = [
            1: [1: LogEntry(repsLastSet: 12, note: "Felt good")],
            2: [1: LogEntry(repsLastSet: 10, note: "")]
        ]
        
        try persistence.saveUserData(userData)
        let loaded = persistence.loadUserData()
        
        XCTAssertEqual(loaded.logs["Squat"]?[1]?[1]?.repsLastSet, 12)
        XCTAssertEqual(loaded.logs["Squat"]?[1]?[1]?.note, "Felt good")
        XCTAssertEqual(loaded.logs["Squat"]?[2]?[1]?.repsLastSet, 10)
    }
    
    func testSaveAndLoadStructuredLogs() throws {
        var userData = UserData()
        userData.structuredLogs["Bench Press"] = [
            1: [1: StructuredLogEntry(amrapReps: [2: 4, 8: 12], note: "PR attempt")]
        ]
        
        try persistence.saveUserData(userData)
        let loaded = persistence.loadUserData()
        
        XCTAssertEqual(loaded.structuredLogs["Bench Press"]?[1]?[1]?.amrapReps[2], 4)
        XCTAssertEqual(loaded.structuredLogs["Bench Press"]?[1]?[1]?.amrapReps[8], 12)
        XCTAssertEqual(loaded.structuredLogs["Bench Press"]?[1]?[1]?.note, "PR attempt")
    }
    
    func testSaveAndLoadLinearLogs() throws {
        var userData = UserData()
        userData.linearLogs["Squat"] = [
            1: [
                1: LinearLogEntry(completed: true, weight: 135),
                2: LinearLogEntry(completed: false, consecutiveFailures: 1, weight: 140)
            ]
        ]
        
        try persistence.saveUserData(userData)
        let loaded = persistence.loadUserData()
        
        XCTAssertEqual(loaded.linearLogs["Squat"]?[1]?[1]?.completed, true)
        XCTAssertEqual(loaded.linearLogs["Squat"]?[1]?[2]?.completed, false)
        XCTAssertEqual(loaded.linearLogs["Squat"]?[1]?[2]?.consecutiveFailures, 1)
    }
    
    func testLoadUserDataReturnsEmptyWhenNoData() {
        let userData = persistence.loadUserData()
        
        XCTAssertEqual(userData.logs.count, 0)
        XCTAssertNil(userData.selectedProgram)
        XCTAssertFalse(userData.hasCompletedOnboarding)
    }
    
    // MARK: - Lift History Tests
    
    func testSaveAndLoadLiftHistory() throws {
        var userData = UserData()
        let record = LiftRecord(
            liftName: "Squat",
            weight: 315,
            reps: 5,
            programId: "test_program",
            week: 3
        )
        userData.recordLift(record)
        
        try persistence.saveUserData(userData)
        let loaded = persistence.loadUserData()
        
        XCTAssertEqual(loaded.liftHistory.count, 1)
        XCTAssertEqual(loaded.liftHistory.first?.liftName, "Squat")
        XCTAssertEqual(loaded.liftHistory.first?.weight, 315)
        XCTAssertEqual(loaded.liftHistory.first?.reps, 5)
    }
    
    func testSaveAndLoadPersonalRecords() throws {
        var userData = UserData()
        
        // Add a lift record which should create a PR
        let record = LiftRecord(
            liftName: "Bench Press",
            weight: 225,
            reps: 3
        )
        userData.recordLift(record)
        
        try persistence.saveUserData(userData)
        let loaded = persistence.loadUserData()
        
        XCTAssertNotNil(loaded.personalRecords["Bench Press"])
        XCTAssertEqual(loaded.personalRecords["Bench Press"]?.weight, 225)
        XCTAssertEqual(loaded.personalRecords["Bench Press"]?.reps, 3)
    }
    
    // MARK: - Custom Templates Tests
    
    func testSaveAndLoadCustomTemplates() throws {
        var userData = UserData()
        
        let template = CustomTemplate(
            name: "My Template",
            templateDescription: "A test template",
            daysPerWeek: 4,
            weeks: Array(1...12),
            days: ["1": [DayItem(type: .volume, lift: "Squat", name: "Squat")]],
            initialMaxes: ["Squat": 300],
            rounding: 5
        )
        
        userData.addTemplate(template)
        
        try persistence.saveUserData(userData)
        let loaded = persistence.loadUserData()
        
        XCTAssertEqual(loaded.customTemplates.count, 1)
        XCTAssertEqual(loaded.customTemplates.first?.name, "My Template")
        XCTAssertEqual(loaded.customTemplates.first?.daysPerWeek, 4)
    }
    
    // MARK: - Cycle History Tests
    
    func testSaveAndLoadCycleHistory() throws {
        var userData = UserData()
        
        let cycle = CompletedCycle(
            cycleNumber: 1,
            startDate: Date(),
            startingMaxes: ["Squat": 300],
            endingMaxes: ["Squat": 315],
            logs: [:],
            lastCompletedWeek: 12,
            programId: "test_program"
        )
        userData.cycleHistory.append(cycle)
        
        try persistence.saveUserData(userData)
        let loaded = persistence.loadUserData()
        
        XCTAssertEqual(loaded.cycleHistory.count, 1)
        XCTAssertEqual(loaded.cycleHistory.first?.cycleNumber, 1)
        XCTAssertEqual(loaded.cycleHistory.first?.startingMaxes["Squat"], 300)
        XCTAssertEqual(loaded.cycleHistory.first?.endingMaxes["Squat"], 315)
    }
    
    // MARK: - ProgramState Tests
    
    func testSaveAndLoadProgramState() throws {
        let state = ProgramState(
            rounding: 5,
            initialMaxes: ["Squat": 300, "Bench Press": 225],
            singleAt8Percent: ["Squat": 0.9, "Bench Press": 0.9],
            lifts: [:],
            days: [:],
            weeks: [1, 2, 3, 4]
        )
        
        try persistence.saveProgramState(state)
        let loaded = persistence.loadProgramState()
        
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.rounding, 5)
        XCTAssertEqual(loaded?.initialMaxes["Squat"], 300)
        XCTAssertEqual(loaded?.weeks, [1, 2, 3, 4])
    }
    
    func testLoadProgramStateReturnsNilWhenEmpty() {
        let state = persistence.loadProgramState()
        
        XCTAssertNil(state)
    }
    
    // MARK: - Export/Import Tests
    
    func testExportUserDataJSON() throws {
        var userData = UserData()
        userData.selectedProgram = "test_program"
        userData.customInitialMaxes = ["Squat": 300]
        try persistence.saveUserData(userData)
        
        let exportedData = try persistence.exportUserDataJSON()
        
        XCTAssertGreaterThan(exportedData.count, 0)
        
        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: exportedData)
        XCTAssertNotNil(json)
    }
    
    func testImportUserDataJSON() throws {
        // Create JSON to import
        let userData = UserData(
            selectedProgram: "imported_program",
            customInitialMaxes: ["Deadlift": 400]
        )
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(userData)
        
        // Import
        try persistence.importUserDataJSON(jsonData)
        
        // Verify
        let loaded = persistence.loadUserData()
        XCTAssertEqual(loaded.selectedProgram, "imported_program")
        XCTAssertEqual(loaded.customInitialMaxes["Deadlift"], 400)
    }
    
    // MARK: - Reset Tests
    
    func testResetAllLogs() throws {
        var userData = UserData()
        userData.logs["Squat"] = [1: [1: LogEntry(repsLastSet: 10, note: "")]]
        userData.selectedProgram = "test"
        try persistence.saveUserData(userData)
        
        persistence.resetAllLogs()
        
        let loaded = persistence.loadUserData()
        XCTAssertTrue(loaded.logs.isEmpty)
        // Other data should be preserved
        XCTAssertEqual(loaded.selectedProgram, "test")
    }
    
    func testResetEverything() throws {
        let settings = UserSettings(useMetric: true)
        var userData = UserData()
        userData.selectedProgram = "test"
        
        try persistence.saveSettings(settings)
        try persistence.saveUserData(userData)
        
        persistence.resetEverything()
        
        // Everything should be back to defaults/nil
        XCTAssertEqual(persistence.loadSettings().useMetric, UserSettings.default.useMetric)
        XCTAssertNil(persistence.loadUserData().selectedProgram)
    }
    
    // MARK: - UserData Helper Method Tests
    
    func testRecordLiftCreatesFirstPR() {
        var userData = UserData()
        
        let record = LiftRecord(liftName: "Squat", weight: 315, reps: 5)
        userData.recordLift(record)
        
        XCTAssertNotNil(userData.personalRecords["Squat"])
        XCTAssertEqual(userData.personalRecords["Squat"]?.weight, 315)
    }
    
    func testRecordLiftUpdatesPROnImprovement() {
        var userData = UserData()
        
        // First record
        let record1 = LiftRecord(liftName: "Squat", weight: 315, reps: 5)
        userData.recordLift(record1)
        
        // Better E1RM
        let record2 = LiftRecord(liftName: "Squat", weight: 350, reps: 3)
        userData.recordLift(record2)
        
        // Should update PR
        XCTAssertEqual(userData.personalRecords["Squat"]?.weight, 350)
    }
    
    func testRecordLiftKeepsPROnNoImprovement() {
        var userData = UserData()
        
        // First record (high E1RM)
        let record1 = LiftRecord(liftName: "Squat", weight: 400, reps: 1)
        userData.recordLift(record1)
        
        // Lower E1RM
        let record2 = LiftRecord(liftName: "Squat", weight: 315, reps: 3)
        userData.recordLift(record2)
        
        // Should keep original PR
        XCTAssertEqual(userData.personalRecords["Squat"]?.weight, 400)
    }
    
    func testHistoryForLift() {
        var userData = UserData()
        
        userData.recordLift(LiftRecord(liftName: "Squat", weight: 300, reps: 5))
        userData.recordLift(LiftRecord(liftName: "Bench Press", weight: 200, reps: 5))
        userData.recordLift(LiftRecord(liftName: "Squat", weight: 305, reps: 5))
        
        let squatHistory = userData.history(for: "Squat")
        
        XCTAssertEqual(squatHistory.count, 2)
        XCTAssertTrue(squatHistory.allSatisfy { $0.liftName == "Squat" })
    }
    
    func testBestRecordForLift() {
        var userData = UserData()
        
        userData.recordLift(LiftRecord(liftName: "Squat", weight: 300, reps: 5))
        userData.recordLift(LiftRecord(liftName: "Squat", weight: 350, reps: 3)) // Best E1RM
        userData.recordLift(LiftRecord(liftName: "Squat", weight: 315, reps: 4))
        
        let best = userData.bestRecord(for: "Squat")
        
        XCTAssertEqual(best?.weight, 350)
    }
    
    func testAllRecordedLifts() {
        var userData = UserData()
        
        userData.recordLift(LiftRecord(liftName: "Squat", weight: 300, reps: 5))
        userData.recordLift(LiftRecord(liftName: "Bench Press", weight: 200, reps: 5))
        userData.recordLift(LiftRecord(liftName: "Deadlift", weight: 400, reps: 5))
        userData.recordLift(LiftRecord(liftName: "Squat", weight: 305, reps: 5)) // Duplicate
        
        let lifts = userData.allRecordedLifts
        
        XCTAssertEqual(lifts.count, 3)
        XCTAssertTrue(lifts.contains("Squat"))
        XCTAssertTrue(lifts.contains("Bench Press"))
        XCTAssertTrue(lifts.contains("Deadlift"))
    }
    
    // MARK: - Template Management Tests
    
    func testAddTemplate() {
        var userData = UserData()
        let template = CustomTemplate(name: "Test Template")
        
        userData.addTemplate(template)
        
        XCTAssertEqual(userData.customTemplates.count, 1)
        XCTAssertEqual(userData.customTemplates.first?.name, "Test Template")
    }
    
    func testUpdateTemplate() {
        var userData = UserData()
        var template = CustomTemplate(name: "Original")
        userData.addTemplate(template)
        
        template.name = "Updated"
        userData.updateTemplate(template)
        
        XCTAssertEqual(userData.customTemplates.count, 1)
        XCTAssertEqual(userData.customTemplates.first?.name, "Updated")
    }
    
    func testDeleteTemplate() {
        var userData = UserData()
        let template = CustomTemplate(name: "To Delete")
        userData.addTemplate(template)
        
        userData.deleteTemplate(id: template.id)
        
        XCTAssertTrue(userData.customTemplates.isEmpty)
    }
    
    func testGetTemplateById() {
        var userData = UserData()
        let template = CustomTemplate(name: "Find Me")
        userData.addTemplate(template)
        
        let found = userData.template(withId: template.id)
        
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Find Me")
    }
    
    // MARK: - Static Helper Tests
    
    func testProgramIdForTemplate() {
        let id = UUID()
        let programId = UserData.programId(for: id)
        
        XCTAssertEqual(programId, "custom_\(id.uuidString)")
    }
    
    func testIsCustomTemplate() {
        XCTAssertTrue(UserData.isCustomTemplate(programId: "custom_12345"))
        XCTAssertFalse(UserData.isCustomTemplate(programId: "sbs_program_config"))
    }
    
    func testTemplateIdFromProgramId() {
        let uuid = UUID()
        let programId = "custom_\(uuid.uuidString)"
        
        let extractedId = UserData.templateId(from: programId)
        
        XCTAssertEqual(extractedId, uuid)
    }
    
    func testTemplateIdFromNonCustomProgramIdReturnsNil() {
        let extractedId = UserData.templateId(from: "sbs_program_config")
        
        XCTAssertNil(extractedId)
    }
}



