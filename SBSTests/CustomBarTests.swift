import XCTest
@testable import SBSApp

/// Custom bars: the lifter's EZ / hex / specialty bars, assigned per exercise,
/// that the plate calculator loads plates onto.
final class CustomBarTests: XCTestCase {

    private let hex = CustomBar(name: "Hex Bar", weight: 60)
    private let ez = CustomBar(name: "EZ Curl Bar", weight: 25)

    private func settingsWithBars() -> UserSettings {
        var settings = UserSettings()
        settings.upsertBar(hex)
        settings.upsertBar(ez)
        settings.assignBar(hex.id, to: "Deadlift")
        settings.assignBar(ez.id, to: "EZ Bar Curls")
        return settings
    }

    // MARK: Decoding

    func testSettingsSavedBeforeCustomBarsStillDecode() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(UserSettings())) as! [String: Any]
        json.removeValue(forKey: "customBars")
        json.removeValue(forKey: "barAssignments")
        let data = try JSONSerialization.data(withJSONObject: json)

        let settings = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertTrue(settings.bars.isEmpty)
        XCTAssertEqual(settings.barWeight(for: "Deadlift"), 45)
    }

    func testBarsAndAssignmentsRoundTrip() throws {
        let settings = settingsWithBars()
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.barWeight(for: "Deadlift"), 60)
    }

    // MARK: Resolving

    func testAssignedBarWinsElseStandardBar() {
        let settings = settingsWithBars()
        XCTAssertEqual(settings.barWeight(for: "Deadlift"), 60)
        XCTAssertEqual(settings.barWeight(for: "Squat"), 45)
        XCTAssertEqual(settings.barWeight(for: nil), 45)
        XCTAssertNil(settings.assignedBar(for: "Squat"))
    }

    func testAliasesAndCasingShareOneAssignment() {
        let settings = settingsWithBars()
        XCTAssertEqual(settings.assignedBar(for: "ez bar curl"), ez)
        XCTAssertEqual(settings.assignedBar(for: "ez bar curls"), ez)
        XCTAssertEqual(settings.assignedBar(for: "deadlift "), hex)
    }

    func testStandardBarChangeDoesNotMoveCustomBars() {
        var settings = settingsWithBars()
        settings.barWeight = 35
        XCTAssertEqual(settings.barWeight(for: "Deadlift"), 60)
        XCTAssertEqual(settings.barWeight(for: "Squat"), 35)
    }

    // MARK: Editing

    func testUnassignGoesBackToStandardBar() {
        var settings = settingsWithBars()
        settings.assignBar(nil, to: "deadlift")
        XCTAssertEqual(settings.barWeight(for: "Deadlift"), 45)
        XCTAssertNotNil(settings.assignedBar(for: "EZ Bar Curls"))
    }

    func testEditingABarUpdatesEveryExerciseUsingIt() {
        var settings = settingsWithBars()
        settings.assignBar(hex.id, to: "Shrugs")
        var heavier = hex
        heavier.weight = 65
        settings.upsertBar(heavier)
        XCTAssertEqual(settings.bars.count, 2)
        XCTAssertEqual(settings.barWeight(for: "Deadlift"), 65)
        XCTAssertEqual(settings.barWeight(for: "Shrugs"), 65)
    }

    func testRemovingABarClearsItsAssignments() {
        var settings = settingsWithBars()
        settings.removeBar(id: hex.id)
        XCTAssertEqual(settings.bars, [ez])
        XCTAssertEqual(settings.barWeight(for: "Deadlift"), 45)
        XCTAssertEqual(settings.barAssignments?.count, 1)

        settings.removeBar(id: ez.id)
        XCTAssertNil(settings.barAssignments)
    }

    func testAssignmentToMissingBarIsIgnored() {
        var settings = UserSettings()
        settings.assignBar(UUID(), to: "Deadlift")
        XCTAssertNil(settings.assignedBar(for: "Deadlift"))
        XCTAssertEqual(settings.barWeight(for: "Deadlift"), 45)
    }

    // MARK: Units

    func testUnitSwitchKeepsCustomBarWeights() {
        var settings = settingsWithBars()
        // The standard bar snaps to 20 kg on a unit switch; custom bars are real equipment
        settings.useMetric = true
        settings.barWeight = 20 / 0.45359237
        XCTAssertEqual(settings.barWeight(for: "Deadlift"), 60)
        XCTAssertEqual(settings.barWeight(for: "Squat"), 20 / 0.45359237, accuracy: 0.001)
    }

    // MARK: Plates

    func testHexBarPlateMath() {
        let result = PlateCalculator(barWeight: 60).calculate(totalWeight: 240)
        let perSide = result.platesPerSide.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(perSide, 90, accuracy: 0.001)
    }

    func testWorkoutExerciseBarKey() {
        let accessory = WorkoutExercise.fromAccessory(name: "EZ Bar Curls", sets: 3, reps: 10, lastLogWeight: 60)
        XCTAssertEqual(accessory.barKeySource, "EZ Bar Curls")
        XCTAssertEqual(settingsWithBars().barWeight(for: accessory.barKeySource), 25)
    }
}
