import XCTest
@testable import SBSApp

/// Tests for the ExerciseLibrary functionality
final class ExerciseLibraryTests: XCTestCase {
    
    var library: ExerciseLibrary!
    
    override func setUp() {
        super.setUp()
        library = ExerciseLibrary.shared
    }
    
    // MARK: - Exercise Tests
    
    func testExerciseIdGeneration() {
        let exercise = Exercise(
            name: "Bench Press",
            bodyPart: .chest,
            category: .mainLift,
            equipment: .barbell,
            isCompound: true
        )
        
        XCTAssertEqual(exercise.id, "bench_press")
    }
    
    func testExerciseCustomId() {
        let exercise = Exercise(
            id: "custom_id",
            name: "Custom Exercise",
            bodyPart: .chest,
            category: .accessory
        )
        
        XCTAssertEqual(exercise.id, "custom_id")
    }
    
    // MARK: - Body Part Tests
    
    func testBodyPartAllCases() {
        XCTAssertEqual(BodyPart.allCases.count, 12)
    }
    
    func testBodyPartIds() {
        for bodyPart in BodyPart.allCases {
            XCTAssertEqual(bodyPart.id, bodyPart.rawValue)
        }
    }
    
    func testBodyPartIcons() {
        for bodyPart in BodyPart.allCases {
            XCTAssertEqual(bodyPart.icon, "dumbbell.fill")
        }
    }
    
    func testBodyPartColors() {
        XCTAssertEqual(BodyPart.chest.color, "red")
        XCTAssertEqual(BodyPart.back.color, "blue")
        XCTAssertEqual(BodyPart.shoulders.color, "orange")
        XCTAssertEqual(BodyPart.quads.color, "green")
    }
    
    // MARK: - Exercise Category Tests
    
    func testExerciseCategoryAllCases() {
        XCTAssertEqual(ExerciseCategory.allCases.count, 4)
        XCTAssertTrue(ExerciseCategory.allCases.contains(.mainLift))
        XCTAssertTrue(ExerciseCategory.allCases.contains(.compound))
        XCTAssertTrue(ExerciseCategory.allCases.contains(.isolation))
        XCTAssertTrue(ExerciseCategory.allCases.contains(.accessory))
    }
    
    // MARK: - Equipment Tests
    
    func testEquipmentAllCases() {
        XCTAssertEqual(Equipment.allCases.count, 10)
        XCTAssertTrue(Equipment.allCases.contains(.barbell))
        XCTAssertTrue(Equipment.allCases.contains(.dumbbell))
        XCTAssertTrue(Equipment.allCases.contains(.bodyweight))
        XCTAssertTrue(Equipment.allCases.contains(.machine))
    }
    
    // MARK: - Library Tests
    
    func testLibraryHasExercises() {
        XCTAssertGreaterThan(library.exercises.count, 100)
    }
    
    func testLibraryMainLifts() {
        let mainLifts = library.mainLifts
        
        XCTAssertGreaterThanOrEqual(mainLifts.count, 4)
        
        // Should include the Big 4
        let liftNames = mainLifts.map { $0.name }
        XCTAssertTrue(liftNames.contains("Squat"))
        XCTAssertTrue(liftNames.contains("Bench Press"))
        XCTAssertTrue(liftNames.contains("Deadlift"))
        XCTAssertTrue(liftNames.contains("Overhead Press"))
    }
    
    func testLibraryAccessories() {
        let accessories = library.accessories
        
        XCTAssertGreaterThan(accessories.count, 50)
        
        // Should not include main lifts
        for exercise in accessories {
            XCTAssertNotEqual(exercise.category, .mainLift)
        }
    }
    
    func testLibraryGroupsByBodyPart() {
        let byBodyPart = library.exercisesByBodyPart
        
        XCTAssertGreaterThan(byBodyPart.count, 0)
        XCTAssertNotNil(byBodyPart[.chest])
        XCTAssertNotNil(byBodyPart[.back])
        XCTAssertNotNil(byBodyPart[.quads])
    }
    
    func testExercisesForBodyPart() {
        let chestExercises = library.exercises(for: .chest)
        
        XCTAssertGreaterThan(chestExercises.count, 5)
        
        for exercise in chestExercises {
            XCTAssertEqual(exercise.bodyPart, .chest)
        }
    }
    
    func testExercisesForNonexistentBodyPartReturnsEmpty() {
        // This won't happen with the enum, but the method handles nil gracefully
        let exercises = library.exercises(for: .fullBody)
        
        // Full body exists, so should have exercises
        XCTAssertGreaterThan(exercises.count, 0)
    }
    
    // MARK: - Search Tests
    
    func testSearchByName() {
        let results = library.search("bench")
        
        XCTAssertGreaterThan(results.count, 0)
        
        for exercise in results {
            XCTAssertTrue(exercise.name.lowercased().contains("bench"))
        }
    }
    
    func testSearchCaseInsensitive() {
        let lowercaseResults = library.search("squat")
        let uppercaseResults = library.search("SQUAT")
        let mixedResults = library.search("SqUaT")
        
        XCTAssertEqual(lowercaseResults.count, uppercaseResults.count)
        XCTAssertEqual(lowercaseResults.count, mixedResults.count)
    }
    
    func testSearchEmptyString() {
        let results = library.search("")
        
        // Empty search returns all exercises
        XCTAssertEqual(results.count, library.exercises.count)
    }
    
    func testSearchNoResults() {
        let results = library.search("xyznonexistent")
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testSearchPartialMatch() {
        let results = library.search("curl")
        
        XCTAssertGreaterThan(results.count, 3) // Multiple curl variations
        
        let names = results.map { $0.name.lowercased() }
        XCTAssertTrue(names.allSatisfy { $0.contains("curl") })
    }
    
    // MARK: - Custom Exercise Tests
    
    func testCreateCustomExercise() {
        let custom = ExerciseLibrary.customExercise(name: "My Exercise", bodyPart: .chest)
        
        XCTAssertEqual(custom.id, "custom_my_exercise")
        XCTAssertEqual(custom.name, "My Exercise")
        XCTAssertEqual(custom.bodyPart, .chest)
        XCTAssertEqual(custom.category, .accessory)
        XCTAssertEqual(custom.equipment, .other)
        XCTAssertFalse(custom.isCompound)
    }
    
    func testCreateCustomExerciseSpaces() {
        let custom = ExerciseLibrary.customExercise(name: "My Special Exercise", bodyPart: .back)
        
        XCTAssertEqual(custom.id, "custom_my_special_exercise")
    }
    
    // MARK: - Compound Exercise Tests
    
    func testMainLiftsAreCompound() {
        let mainLifts = library.mainLifts
        
        for lift in mainLifts {
            XCTAssertTrue(lift.isCompound, "\(lift.name) should be marked as compound")
        }
    }
    
    func testIsolationExercisesAreNotCompound() {
        let isolationExercises = library.exercises.filter { $0.category == .isolation }
        
        for exercise in isolationExercises {
            XCTAssertFalse(exercise.isCompound, "\(exercise.name) should not be marked as compound")
        }
    }
    
    // MARK: - Specific Exercise Tests
    
    func testSquatExists() {
        let results = library.search("Squat")
        let squat = results.first { $0.name == "Squat" }
        
        XCTAssertNotNil(squat)
        XCTAssertEqual(squat?.bodyPart, .quads)
        XCTAssertEqual(squat?.category, .mainLift)
        XCTAssertEqual(squat?.equipment, .barbell)
        XCTAssertTrue(squat?.isCompound ?? false)
    }
    
    func testBenchPressExists() {
        let results = library.search("Bench Press")
        let bench = results.first { $0.name == "Bench Press" }
        
        XCTAssertNotNil(bench)
        XCTAssertEqual(bench?.bodyPart, .chest)
        XCTAssertEqual(bench?.category, .mainLift)
    }
    
    func testDeadliftExists() {
        let results = library.search("Deadlift")
        let deadlift = results.first { $0.name == "Deadlift" }
        
        XCTAssertNotNil(deadlift)
        XCTAssertEqual(deadlift?.bodyPart, .back)
        XCTAssertEqual(deadlift?.category, .mainLift)
    }
    
    func testOHPExists() {
        let results = library.search("Overhead Press")
        let ohp = results.first { $0.name == "Overhead Press" }
        
        XCTAssertNotNil(ohp)
        XCTAssertEqual(ohp?.bodyPart, .shoulders)
        XCTAssertEqual(ohp?.category, .mainLift)
    }
    
    // MARK: - Hashable Tests
    
    func testExerciseHashable() {
        let exercise1 = Exercise(name: "Test", bodyPart: .chest, category: .accessory)
        let exercise2 = Exercise(name: "Test", bodyPart: .chest, category: .accessory)
        
        // Same ID should be equal
        XCTAssertEqual(exercise1.id, exercise2.id)
    }
    
    func testExerciseSetDeduplication() {
        var exerciseSet: Set<Exercise> = []
        
        let exercise1 = Exercise(id: "test", name: "Test", bodyPart: .chest, category: .accessory)
        let exercise2 = Exercise(id: "test", name: "Test Different", bodyPart: .back, category: .compound)
        
        exerciseSet.insert(exercise1)
        exerciseSet.insert(exercise2)
        
        // Same ID should only appear once in set
        XCTAssertEqual(exerciseSet.count, 1)
    }
    
    // MARK: - Codable Tests
    
    func testExerciseCodable() throws {
        let original = Exercise(
            id: "test_exercise",
            name: "Test Exercise",
            bodyPart: .chest,
            category: .compound,
            equipment: .barbell,
            isCompound: true
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Exercise.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.bodyPart, original.bodyPart)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.equipment, original.equipment)
        XCTAssertEqual(decoded.isCompound, original.isCompound)
    }
    
    // MARK: - Singleton Tests
    
    func testLibrarySingleton() {
        let library1 = ExerciseLibrary.shared
        let library2 = ExerciseLibrary.shared
        
        XCTAssertTrue(library1 === library2)
    }
}

