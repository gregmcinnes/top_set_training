import Foundation

// MARK: - Exercise Library

/// A predefined exercise with metadata
public struct Exercise: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let bodyPart: BodyPart
    public let category: ExerciseCategory
    public let equipment: Equipment
    public let isCompound: Bool
    
    public init(
        id: String? = nil,
        name: String,
        bodyPart: BodyPart,
        category: ExerciseCategory,
        equipment: Equipment = .barbell,
        isCompound: Bool = false
    ) {
        self.id = id ?? name.lowercased().replacingOccurrences(of: " ", with: "_")
        self.name = name
        self.bodyPart = bodyPart
        self.category = category
        self.equipment = equipment
        self.isCompound = isCompound
    }
}

// MARK: - Body Part

public enum BodyPart: String, CaseIterable, Codable, Identifiable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case forearms = "Forearms"
    case core = "Core"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case fullBody = "Full Body"
    
    public var id: String { rawValue }
    
    public var icon: String {
        "dumbbell.fill"
    }
    
    public var color: String {
        switch self {
        case .chest: return "red"
        case .back: return "blue"
        case .shoulders: return "orange"
        case .biceps: return "purple"
        case .triceps: return "pink"
        case .forearms: return "brown"
        case .core: return "yellow"
        case .quads: return "green"
        case .hamstrings: return "teal"
        case .glutes: return "indigo"
        case .calves: return "mint"
        case .fullBody: return "gray"
        }
    }
}

// MARK: - Exercise Category

public enum ExerciseCategory: String, CaseIterable, Codable {
    case mainLift = "Main Lift"
    case compound = "Compound"
    case isolation = "Isolation"
    case accessory = "Accessory"
}

// MARK: - Equipment

public enum Equipment: String, CaseIterable, Codable {
    case barbell = "Barbell"
    case dumbbell = "Dumbbell"
    case cable = "Cable"
    case machine = "Machine"
    case bodyweight = "Bodyweight"
    case kettlebell = "Kettlebell"
    case ezBar = "EZ Bar"
    case smithMachine = "Smith Machine"
    case bands = "Bands"
    case other = "Other"
}

// MARK: - Exercise Library (Singleton)

public final class ExerciseLibrary {
    public static let shared = ExerciseLibrary()
    
    /// All predefined exercises
    public let exercises: [Exercise]
    
    /// Exercises grouped by body part
    public var exercisesByBodyPart: [BodyPart: [Exercise]] {
        Dictionary(grouping: exercises) { $0.bodyPart }
    }
    
    /// Main compound lifts (for main lift selection)
    public var mainLifts: [Exercise] {
        exercises.filter { $0.category == .mainLift }
    }
    
    /// All accessory exercises (non-main lifts)
    public var accessories: [Exercise] {
        exercises.filter { $0.category != .mainLift }
    }
    
    /// Get exercises for a specific body part
    public func exercises(for bodyPart: BodyPart) -> [Exercise] {
        exercisesByBodyPart[bodyPart] ?? []
    }
    
    /// Search exercises by name
    public func search(_ query: String) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        let lowercased = query.lowercased()
        return exercises.filter { $0.name.lowercased().contains(lowercased) }
    }
    
    /// Create a custom exercise
    public static func customExercise(name: String, bodyPart: BodyPart) -> Exercise {
        Exercise(
            id: "custom_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))",
            name: name,
            bodyPart: bodyPart,
            category: .accessory,
            equipment: .other,
            isCompound: false
        )
    }
    
    private init() {
        self.exercises = Self.buildExerciseLibrary()
    }
    
    // MARK: - Build Exercise Library
    
    private static func buildExerciseLibrary() -> [Exercise] {
        var exercises: [Exercise] = []
        
        // MARK: - Main Lifts (Big 4 + variations)
        exercises.append(contentsOf: [
            Exercise(name: "Squat", bodyPart: .quads, category: .mainLift, equipment: .barbell, isCompound: true),
            Exercise(name: "Bench Press", bodyPart: .chest, category: .mainLift, equipment: .barbell, isCompound: true),
            Exercise(name: "Deadlift", bodyPart: .back, category: .mainLift, equipment: .barbell, isCompound: true),
            Exercise(name: "Overhead Press", bodyPart: .shoulders, category: .mainLift, equipment: .barbell, isCompound: true),
            Exercise(name: "Front Squat", bodyPart: .quads, category: .mainLift, equipment: .barbell, isCompound: true),
            Exercise(name: "Sumo Deadlift", bodyPart: .back, category: .mainLift, equipment: .barbell, isCompound: true),
            Exercise(name: "Close Grip Bench Press", bodyPart: .chest, category: .mainLift, equipment: .barbell, isCompound: true),
            Exercise(name: "Incline Bench Press", bodyPart: .chest, category: .mainLift, equipment: .barbell, isCompound: true),
            Exercise(name: "Barbell Row", bodyPart: .back, category: .mainLift, equipment: .barbell, isCompound: true),
            Exercise(name: "Pendlay Row", bodyPart: .back, category: .mainLift, equipment: .barbell, isCompound: true),
        ])
        
        // MARK: - Chest
        exercises.append(contentsOf: [
            Exercise(name: "Dumbbell Bench Press", bodyPart: .chest, category: .compound, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Incline Dumbbell Press", bodyPart: .chest, category: .compound, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Decline Bench Press", bodyPart: .chest, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Dumbbell Flyes", bodyPart: .chest, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Cable Flyes", bodyPart: .chest, category: .isolation, equipment: .cable),
            Exercise(name: "Incline Cable Flyes", bodyPart: .chest, category: .isolation, equipment: .cable),
            Exercise(name: "Pec Deck", bodyPart: .chest, category: .isolation, equipment: .machine),
            Exercise(name: "Machine Chest Press", bodyPart: .chest, category: .compound, equipment: .machine),
            Exercise(name: "Push-Ups", bodyPart: .chest, category: .compound, equipment: .bodyweight, isCompound: true),
            Exercise(name: "Dips (Chest)", bodyPart: .chest, category: .compound, equipment: .bodyweight, isCompound: true),
            Exercise(name: "Landmine Press", bodyPart: .chest, category: .compound, equipment: .barbell),
            Exercise(name: "Svend Press", bodyPart: .chest, category: .isolation, equipment: .other),
        ])
        
        // MARK: - Back
        exercises.append(contentsOf: [
            Exercise(name: "Pull-Ups", bodyPart: .back, category: .compound, equipment: .bodyweight, isCompound: true),
            Exercise(name: "Chin-Ups", bodyPart: .back, category: .compound, equipment: .bodyweight, isCompound: true),
            Exercise(name: "Lat Pulldown", bodyPart: .back, category: .compound, equipment: .cable),
            Exercise(name: "Wide Grip Lat Pulldown", bodyPart: .back, category: .compound, equipment: .cable),
            Exercise(name: "Close Grip Lat Pulldown", bodyPart: .back, category: .compound, equipment: .cable),
            Exercise(name: "Dumbbell Row", bodyPart: .back, category: .compound, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Cable Row", bodyPart: .back, category: .compound, equipment: .cable),
            Exercise(name: "Seated Cable Row", bodyPart: .back, category: .compound, equipment: .cable),
            Exercise(name: "T-Bar Row", bodyPart: .back, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Chest Supported Row", bodyPart: .back, category: .compound, equipment: .dumbbell),
            Exercise(name: "Machine Row", bodyPart: .back, category: .compound, equipment: .machine),
            Exercise(name: "Face Pulls", bodyPart: .back, category: .accessory, equipment: .cable),
            Exercise(name: "Straight Arm Pulldown", bodyPart: .back, category: .isolation, equipment: .cable),
            Exercise(name: "Rack Pulls", bodyPart: .back, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Romanian Deadlift", bodyPart: .back, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Good Mornings", bodyPart: .back, category: .compound, equipment: .barbell),
            Exercise(name: "Hyperextensions", bodyPart: .back, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Reverse Hyperextensions", bodyPart: .back, category: .accessory, equipment: .machine),
            Exercise(name: "Meadows Row", bodyPart: .back, category: .compound, equipment: .barbell),
            Exercise(name: "Kroc Row", bodyPart: .back, category: .compound, equipment: .dumbbell),
        ])
        
        // MARK: - Shoulders
        exercises.append(contentsOf: [
            Exercise(name: "Dumbbell Shoulder Press", bodyPart: .shoulders, category: .compound, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Arnold Press", bodyPart: .shoulders, category: .compound, equipment: .dumbbell),
            Exercise(name: "Push Press", bodyPart: .shoulders, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Machine Shoulder Press", bodyPart: .shoulders, category: .compound, equipment: .machine),
            Exercise(name: "Lateral Raises", bodyPart: .shoulders, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Cable Lateral Raises", bodyPart: .shoulders, category: .isolation, equipment: .cable),
            Exercise(name: "Machine Lateral Raises", bodyPart: .shoulders, category: .isolation, equipment: .machine),
            Exercise(name: "Front Raises", bodyPart: .shoulders, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Rear Delt Flyes", bodyPart: .shoulders, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Cable Rear Delt Flyes", bodyPart: .shoulders, category: .isolation, equipment: .cable),
            Exercise(name: "Reverse Pec Deck", bodyPart: .shoulders, category: .isolation, equipment: .machine),
            Exercise(name: "Upright Rows", bodyPart: .shoulders, category: .compound, equipment: .barbell),
            Exercise(name: "Shrugs", bodyPart: .shoulders, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Barbell Shrugs", bodyPart: .shoulders, category: .isolation, equipment: .barbell),
            Exercise(name: "Face Pulls", bodyPart: .shoulders, category: .accessory, equipment: .cable),
            Exercise(name: "Lu Raises", bodyPart: .shoulders, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Plate Front Raises", bodyPart: .shoulders, category: .isolation, equipment: .other),
        ])
        
        // MARK: - Biceps
        exercises.append(contentsOf: [
            Exercise(name: "Barbell Curls", bodyPart: .biceps, category: .isolation, equipment: .barbell),
            Exercise(name: "Dumbbell Curls", bodyPart: .biceps, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Hammer Curls", bodyPart: .biceps, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Incline Dumbbell Curls", bodyPart: .biceps, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Preacher Curls", bodyPart: .biceps, category: .isolation, equipment: .ezBar),
            Exercise(name: "EZ Bar Curls", bodyPart: .biceps, category: .isolation, equipment: .ezBar),
            Exercise(name: "Cable Curls", bodyPart: .biceps, category: .isolation, equipment: .cable),
            Exercise(name: "Concentration Curls", bodyPart: .biceps, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Spider Curls", bodyPart: .biceps, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Drag Curls", bodyPart: .biceps, category: .isolation, equipment: .barbell),
            Exercise(name: "21s", bodyPart: .biceps, category: .isolation, equipment: .barbell),
            Exercise(name: "Cross Body Hammer Curls", bodyPart: .biceps, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Machine Curls", bodyPart: .biceps, category: .isolation, equipment: .machine),
            Exercise(name: "Reverse Curls", bodyPart: .biceps, category: .isolation, equipment: .barbell),
        ])
        
        // MARK: - Triceps
        exercises.append(contentsOf: [
            Exercise(name: "Tricep Pushdowns", bodyPart: .triceps, category: .isolation, equipment: .cable),
            Exercise(name: "Rope Pushdowns", bodyPart: .triceps, category: .isolation, equipment: .cable),
            Exercise(name: "Overhead Tricep Extension", bodyPart: .triceps, category: .isolation, equipment: .cable),
            Exercise(name: "Dumbbell Overhead Extension", bodyPart: .triceps, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Skull Crushers", bodyPart: .triceps, category: .isolation, equipment: .ezBar),
            Exercise(name: "French Press", bodyPart: .triceps, category: .isolation, equipment: .barbell),
            Exercise(name: "JM Press", bodyPart: .triceps, category: .compound, equipment: .barbell),
            Exercise(name: "Dips (Tricep)", bodyPart: .triceps, category: .compound, equipment: .bodyweight, isCompound: true),
            Exercise(name: "Close Grip Push-Ups", bodyPart: .triceps, category: .compound, equipment: .bodyweight),
            Exercise(name: "Tricep Kickbacks", bodyPart: .triceps, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Cable Kickbacks", bodyPart: .triceps, category: .isolation, equipment: .cable),
            Exercise(name: "Machine Dips", bodyPart: .triceps, category: .compound, equipment: .machine),
            Exercise(name: "Bench Dips", bodyPart: .triceps, category: .compound, equipment: .bodyweight),
            Exercise(name: "Diamond Push-Ups", bodyPart: .triceps, category: .compound, equipment: .bodyweight),
        ])
        
        // MARK: - Forearms
        exercises.append(contentsOf: [
            Exercise(name: "Wrist Curls", bodyPart: .forearms, category: .isolation, equipment: .barbell),
            Exercise(name: "Reverse Wrist Curls", bodyPart: .forearms, category: .isolation, equipment: .barbell),
            Exercise(name: "Farmer's Walk", bodyPart: .forearms, category: .compound, equipment: .dumbbell),
            Exercise(name: "Dead Hangs", bodyPart: .forearms, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Plate Pinches", bodyPart: .forearms, category: .isolation, equipment: .other),
            Exercise(name: "Wrist Roller", bodyPart: .forearms, category: .isolation, equipment: .other),
            Exercise(name: "Fat Grip Holds", bodyPart: .forearms, category: .accessory, equipment: .other),
        ])
        
        // MARK: - Core
        exercises.append(contentsOf: [
            Exercise(name: "Planks", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Side Planks", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Ab Wheel Rollouts", bodyPart: .core, category: .accessory, equipment: .other),
            Exercise(name: "Hanging Leg Raises", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Hanging Knee Raises", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Cable Crunches", bodyPart: .core, category: .accessory, equipment: .cable),
            Exercise(name: "Decline Crunches", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Russian Twists", bodyPart: .core, category: .accessory, equipment: .other),
            Exercise(name: "Pallof Press", bodyPart: .core, category: .accessory, equipment: .cable),
            Exercise(name: "Dead Bug", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Bird Dog", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Woodchoppers", bodyPart: .core, category: .accessory, equipment: .cable),
            Exercise(name: "Sit-Ups", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Bicycle Crunches", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "V-Ups", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Dragon Flags", bodyPart: .core, category: .accessory, equipment: .bodyweight),
            Exercise(name: "L-Sit", bodyPart: .core, category: .accessory, equipment: .bodyweight),
        ])
        
        // MARK: - Quads
        exercises.append(contentsOf: [
            Exercise(name: "Leg Press", bodyPart: .quads, category: .compound, equipment: .machine, isCompound: true),
            Exercise(name: "Hack Squat", bodyPart: .quads, category: .compound, equipment: .machine, isCompound: true),
            Exercise(name: "Goblet Squat", bodyPart: .quads, category: .compound, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Bulgarian Split Squat", bodyPart: .quads, category: .compound, equipment: .dumbbell, isCompound: true),
            Exercise(name: "Walking Lunges", bodyPart: .quads, category: .compound, equipment: .dumbbell),
            Exercise(name: "Reverse Lunges", bodyPart: .quads, category: .compound, equipment: .dumbbell),
            Exercise(name: "Split Squats", bodyPart: .quads, category: .compound, equipment: .bodyweight),
            Exercise(name: "Leg Extensions", bodyPart: .quads, category: .isolation, equipment: .machine),
            Exercise(name: "Sissy Squat", bodyPart: .quads, category: .isolation, equipment: .bodyweight),
            Exercise(name: "Step-Ups", bodyPart: .quads, category: .compound, equipment: .dumbbell),
            Exercise(name: "Box Squats", bodyPart: .quads, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Pause Squats", bodyPart: .quads, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Safety Bar Squat", bodyPart: .quads, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Belt Squat", bodyPart: .quads, category: .compound, equipment: .machine, isCompound: true),
        ])
        
        // MARK: - Hamstrings
        exercises.append(contentsOf: [
            Exercise(name: "Romanian Deadlift", bodyPart: .hamstrings, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Stiff Leg Deadlift", bodyPart: .hamstrings, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Dumbbell RDL", bodyPart: .hamstrings, category: .compound, equipment: .dumbbell),
            Exercise(name: "Single Leg RDL", bodyPart: .hamstrings, category: .compound, equipment: .dumbbell),
            Exercise(name: "Lying Leg Curls", bodyPart: .hamstrings, category: .isolation, equipment: .machine),
            Exercise(name: "Seated Leg Curls", bodyPart: .hamstrings, category: .isolation, equipment: .machine),
            Exercise(name: "Nordic Curls", bodyPart: .hamstrings, category: .isolation, equipment: .bodyweight),
            Exercise(name: "Good Mornings", bodyPart: .hamstrings, category: .compound, equipment: .barbell),
            Exercise(name: "Glute Ham Raise", bodyPart: .hamstrings, category: .compound, equipment: .machine),
            Exercise(name: "Cable Pull Through", bodyPart: .hamstrings, category: .compound, equipment: .cable),
            Exercise(name: "Kettlebell Swings", bodyPart: .hamstrings, category: .compound, equipment: .kettlebell),
        ])
        
        // MARK: - Glutes
        exercises.append(contentsOf: [
            Exercise(name: "Hip Thrusts", bodyPart: .glutes, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Barbell Hip Thrust", bodyPart: .glutes, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Dumbbell Hip Thrust", bodyPart: .glutes, category: .compound, equipment: .dumbbell),
            Exercise(name: "Glute Bridge", bodyPart: .glutes, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Single Leg Glute Bridge", bodyPart: .glutes, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Cable Kickbacks", bodyPart: .glutes, category: .isolation, equipment: .cable),
            Exercise(name: "Banded Walks", bodyPart: .glutes, category: .accessory, equipment: .bands),
            Exercise(name: "Clamshells", bodyPart: .glutes, category: .accessory, equipment: .bands),
            Exercise(name: "Fire Hydrants", bodyPart: .glutes, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Donkey Kicks", bodyPart: .glutes, category: .accessory, equipment: .bodyweight),
            Exercise(name: "Sumo Squats", bodyPart: .glutes, category: .compound, equipment: .dumbbell),
            Exercise(name: "Hip Abduction Machine", bodyPart: .glutes, category: .isolation, equipment: .machine),
            Exercise(name: "Kickbacks (Machine)", bodyPart: .glutes, category: .isolation, equipment: .machine),
        ])
        
        // MARK: - Calves
        exercises.append(contentsOf: [
            Exercise(name: "Standing Calf Raises", bodyPart: .calves, category: .isolation, equipment: .machine),
            Exercise(name: "Seated Calf Raises", bodyPart: .calves, category: .isolation, equipment: .machine),
            Exercise(name: "Leg Press Calf Raises", bodyPart: .calves, category: .isolation, equipment: .machine),
            Exercise(name: "Dumbbell Calf Raises", bodyPart: .calves, category: .isolation, equipment: .dumbbell),
            Exercise(name: "Single Leg Calf Raises", bodyPart: .calves, category: .isolation, equipment: .bodyweight),
            Exercise(name: "Donkey Calf Raises", bodyPart: .calves, category: .isolation, equipment: .machine),
            Exercise(name: "Smith Machine Calf Raises", bodyPart: .calves, category: .isolation, equipment: .smithMachine),
        ])
        
        // MARK: - Full Body
        exercises.append(contentsOf: [
            Exercise(name: "Clean and Jerk", bodyPart: .fullBody, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Power Cleans", bodyPart: .fullBody, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Hang Cleans", bodyPart: .fullBody, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Snatch", bodyPart: .fullBody, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Turkish Get-Ups", bodyPart: .fullBody, category: .compound, equipment: .kettlebell),
            Exercise(name: "Burpees", bodyPart: .fullBody, category: .compound, equipment: .bodyweight),
            Exercise(name: "Thrusters", bodyPart: .fullBody, category: .compound, equipment: .barbell, isCompound: true),
            Exercise(name: "Man Makers", bodyPart: .fullBody, category: .compound, equipment: .dumbbell),
            Exercise(name: "Farmer's Walk", bodyPart: .fullBody, category: .compound, equipment: .dumbbell),
            Exercise(name: "Sled Push", bodyPart: .fullBody, category: .compound, equipment: .other),
            Exercise(name: "Sled Pull", bodyPart: .fullBody, category: .compound, equipment: .other),
            Exercise(name: "Battle Ropes", bodyPart: .fullBody, category: .accessory, equipment: .other),
        ])
        
        return exercises
    }
}

