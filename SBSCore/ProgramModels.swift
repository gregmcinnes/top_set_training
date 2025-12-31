import Foundation
import SwiftUI

// MARK: - Program Level

/// Experience level for training programs - used across the app for filtering and display
public enum ProgramLevel: String, CaseIterable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    
    public var color: Color {
        switch self {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .purple
        }
    }
    
    public var icon: String {
        switch self {
        case .beginner: return "leaf.fill"
        case .intermediate: return "flame.fill"
        case .advanced: return "bolt.fill"
        }
    }
}

// MARK: - Program Focus

/// Training focus for programs
public enum ProgramFocus: String, Codable {
    case strength = "Strength"
    case hypertrophy = "Hypertrophy"
    case balanced = "Balanced"
    
    public var color: Color {
        switch self {
        case .strength: return .blue
        case .hypertrophy: return .purple
        case .balanced: return .orange
        }
    }
    
    public var icon: String {
        switch self {
        case .strength: return "bolt.fill"
        case .hypertrophy: return "figure.arms.open"
        case .balanced: return "scale.3d"
        }
    }
}

// MARK: - Core Data Models mirroring Python structures

// MARK: - Universal Lift Record (program-agnostic)

/// A single lift performance record - used for tracking progress across all programs
public struct LiftRecord: Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let liftName: String
    public let weight: Double           // Weight used
    public let reps: Int                // Reps achieved
    public let estimatedOneRM: Double   // E1RM calculated at log time (Epley formula)
    
    // Optional context (for reference, not required for calculations)
    public let programId: String?       // "sbs_program_config", "nsuns_5day_12week", etc.
    public let week: Int?               // Which week in that program
    public let setType: String?         // "volume", "1+", "5+", etc.
    
    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        liftName: String,
        weight: Double,
        reps: Int,
        estimatedOneRM: Double? = nil,
        programId: String? = nil,
        week: Int? = nil,
        setType: String? = nil
    ) {
        self.id = id
        self.date = date
        self.liftName = liftName
        self.weight = weight
        self.reps = reps
        // Calculate E1RM using Epley formula if not provided
        self.estimatedOneRM = estimatedOneRM ?? (weight * (1.0 + Double(reps) / 30.0))
        self.programId = programId
        self.week = week
        self.setType = setType
    }
}

// MARK: - Structured Set Detail (for per-set intensity/reps)

/// Represents a single set in a structured exercise with varying intensity per set
public struct SetDetail: Codable, Equatable {
    /// Intensity as percentage of TM (e.g., 0.75 = 75%)
    public let intensity: Double
    /// Target reps for this set
    public let reps: Int
    /// Whether this is an AMRAP (As Many Reps As Possible) set
    public let isAMRAP: Bool
    
    public init(intensity: Double, reps: Int, isAMRAP: Bool = false) {
        self.intensity = intensity
        self.reps = reps
        self.isAMRAP = isAMRAP
    }
}

// MARK: - Structured Log Entry (for per-set logging)

/// Log entry for structured exercises - tracks AMRAP reps per set
public struct StructuredLogEntry: Codable, Equatable {
    /// Reps achieved on each AMRAP set (keyed by set index, 0-based)
    public var amrapReps: [Int: Int]
    /// Optional note
    public var note: String
    
    public init(amrapReps: [Int: Int] = [:], note: String = "") {
        self.amrapReps = amrapReps
        self.note = note
    }
}

public struct LogEntry: Codable, Equatable {
    public var repsLastSet: Int?
    public var note: String
    /// Optional weight override - if set, this weight was used instead of the calculated weight
    public var weightOverride: Double?
    
    public init(repsLastSet: Int? = nil, note: String = "", weightOverride: Double? = nil) {
        self.repsLastSet = repsLastSet
        self.note = note
        self.weightOverride = weightOverride
    }
}

/// Log entry for accessory exercises - tracks weight used
public struct AccessoryLog: Codable, Equatable {
    public var weight: Double
    public var sets: Int
    public var reps: Int
    public var note: String
    
    public init(weight: Double, sets: Int = 4, reps: Int = 10, note: String = "") {
        self.weight = weight
        self.sets = sets
        self.reps = reps
        self.note = note
    }
}

// MARK: - Linear Progression (StrongLifts-style)

/// Log entry for linear progression exercises - tracks success/failure per session
public struct LinearLogEntry: Codable, Equatable {
    /// Whether all sets and reps were completed successfully
    public var completed: Bool
    /// Running count of consecutive failures for this lift
    public var consecutiveFailures: Int
    /// Whether a deload was applied this session
    public var deloadApplied: Bool
    /// The weight used for this session
    public var weight: Double
    /// Optional note
    public var note: String
    
    public init(
        completed: Bool,
        consecutiveFailures: Int = 0,
        deloadApplied: Bool = false,
        weight: Double = 0,
        note: String = ""
    ) {
        self.completed = completed
        self.consecutiveFailures = consecutiveFailures
        self.deloadApplied = deloadApplied
        self.weight = weight
        self.note = note
    }
}

/// Configuration for linear progression programs (StrongLifts, Starting Strength, etc.)
public struct LinearProgressionConfig: Codable, Equatable {
    /// Default weight increment per session (e.g., 5.0 lbs)
    public var defaultIncrement: Double
    /// Per-lift increments that override the default (e.g., {"Deadlift": 10.0})
    public var liftIncrements: [String: Double]
    /// Number of consecutive failures before triggering a deload
    public var failuresBeforeDeload: Int
    /// Deload percentage (e.g., 0.10 for 10% reduction)
    public var deloadPercentage: Double
    
    public init(
        defaultIncrement: Double = 5.0,
        liftIncrements: [String: Double] = [:],
        failuresBeforeDeload: Int = 3,
        deloadPercentage: Double = 0.10
    ) {
        self.defaultIncrement = defaultIncrement
        self.liftIncrements = liftIncrements
        self.failuresBeforeDeload = failuresBeforeDeload
        self.deloadPercentage = deloadPercentage
    }
    
    private enum CodingKeys: String, CodingKey {
        case defaultIncrement = "default_increment"
        case liftIncrements = "lift_increments"
        case failuresBeforeDeload = "failures_before_deload"
        case deloadPercentage = "deload_percentage"
    }
    
    /// Get the increment for a specific lift
    public func increment(for lift: String) -> Double {
        return liftIncrements[lift] ?? defaultIncrement
    }
}

public struct DayItem: Codable, Equatable {
    public enum ItemType: String, Codable {
        case tm
        case volume
        case accessory
        case structured  // Exercise with explicit per-set intensity/reps configuration
        case linear // Linear progression exercise (StrongLifts, Starting Strength style)
    }
    public var type: ItemType
    public var lift: String?
    public var name: String
    /// Default sets for accessories (e.g., 4)
    public var defaultSets: Int?
    /// Default reps for accessories (e.g., 10)
    public var defaultReps: Int?
    /// Set details for structured exercises (per-set intensity and reps)
    public var setsDetail: [SetDetail]?
    /// Week-based set details for structured exercises (e.g., 5/3/1 where reps change each week)
    /// Keys are week numbers as strings (e.g., "1", "2", "3", "4")
    public var setsDetailByWeek: [String: [SetDetail]]?
    /// Number of sets for linear progression exercises (e.g., 5 for 5x5)
    public var sets: Int?
    /// Number of reps per set for linear progression exercises (e.g., 5 for 5x5)
    public var reps: Int?
    /// Index of the set used for TM progression calculation (0-based). Only this set's performance affects next week's TM.
    public var progressionSetIndex: Int?
    
    public init(type: ItemType, lift: String?, name: String, defaultSets: Int? = nil, defaultReps: Int? = nil, setsDetail: [SetDetail]? = nil, setsDetailByWeek: [String: [SetDetail]]? = nil, sets: Int? = nil, reps: Int? = nil, progressionSetIndex: Int? = nil) {
        self.type = type
        self.lift = lift
        self.name = name
        self.defaultSets = defaultSets
        self.defaultReps = defaultReps
        self.setsDetail = setsDetail
        self.setsDetailByWeek = setsDetailByWeek
        self.sets = sets
        self.reps = reps
        self.progressionSetIndex = progressionSetIndex
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case lift
        case name
        case defaultSets
        case defaultReps
        case setsDetail = "sets_detail"
        case setsDetailByWeek = "sets_detail_by_week"
        case sets
        case reps
        case progressionSetIndex = "progression_set_index"
    }
}

public struct WeekData: Codable, Equatable {
    public let intensity: Double
    public let repsPerNormalSet: Int
    public let repOutTarget: Int
    public let sets: Int

    private enum CodingKeys: String, CodingKey {
        case intensity = "Intensity"
        case repsPerNormalSet = "Reps per normal set"
        case repOutTarget = "Rep out target"
        case sets = "Sets"
    }
}

public struct ProgramData: Codable, Equatable {
    public var name: String
    /// Generic display name to avoid trademark issues (optional, falls back to name)
    public var displayName: String?
    /// Description of the program for display in the UI
    public var programDescription: String?
    public var rounding: Double
    public var singleAt8Percent: [String: Double]
    public var initialMaxes: [String: Double]
    // lifts["Squat"]["1"] -> WeekData (string week keys in JSON)
    public var lifts: [String: [String: WeekData]]
    public var days: [String: [DayItem]]
    public var weeks: [Int]
    /// Configuration for linear progression programs (optional - only for StrongLifts-style programs)
    public var linearProgressionConfig: LinearProgressionConfig?
    /// Optional explicit day titles (e.g., "Push", "Pull", "Legs", "Workout A")
    public var dayTitles: [String: String]?
    /// Optional day visibility by week - specifies which weeks each day is visible
    /// Keys are day numbers as strings, values are arrays of week numbers
    /// If not specified, all days are visible every week (backwards compatible)
    public var dayVisibility: [String: [Int]]?
    /// Optional explicit days per week - overrides auto-detection from days.count
    /// Useful when day_visibility creates more day entries than actual training days per week
    public var daysPerWeek: Int?

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case programDescription = "description"
        case rounding
        case singleAt8Percent = "single_at_8_percent"
        case initialMaxes = "initial_maxes"
        case lifts
        case days
        case weeks
        case linearProgressionConfig = "linear_progression"
        case dayTitles = "day_titles"
        case dayVisibility = "day_visibility"
        case daysPerWeek = "days_per_week"
    }
    
    public init(
        name: String,
        displayName: String? = nil,
        programDescription: String? = nil,
        rounding: Double,
        singleAt8Percent: [String: Double],
        initialMaxes: [String: Double] = [:],
        lifts: [String: [String: WeekData]],
        days: [String: [DayItem]],
        weeks: [Int],
        linearProgressionConfig: LinearProgressionConfig? = nil,
        dayTitles: [String: String]? = nil,
        dayVisibility: [String: [Int]]? = nil,
        daysPerWeek: Int? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.programDescription = programDescription
        self.rounding = rounding
        self.singleAt8Percent = singleAt8Percent
        self.initialMaxes = initialMaxes
        self.lifts = lifts
        self.days = days
        self.weeks = weeks
        self.linearProgressionConfig = linearProgressionConfig
        self.dayTitles = dayTitles
        self.dayVisibility = dayVisibility
        self.daysPerWeek = daysPerWeek
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        programDescription = try container.decodeIfPresent(String.self, forKey: .programDescription)
        rounding = try container.decode(Double.self, forKey: .rounding)
        singleAt8Percent = try container.decode([String: Double].self, forKey: .singleAt8Percent)
        // Default to empty dictionary if initial_maxes is not present (user will set their own)
        initialMaxes = try container.decodeIfPresent([String: Double].self, forKey: .initialMaxes) ?? [:]
        lifts = try container.decode([String: [String: WeekData]].self, forKey: .lifts)
        days = try container.decode([String: [DayItem]].self, forKey: .days)
        weeks = try container.decode([Int].self, forKey: .weeks)
        linearProgressionConfig = try container.decodeIfPresent(LinearProgressionConfig.self, forKey: .linearProgressionConfig)
        dayTitles = try container.decodeIfPresent([String: String].self, forKey: .dayTitles)
        dayVisibility = try container.decodeIfPresent([String: [Int]].self, forKey: .dayVisibility)
        daysPerWeek = try container.decodeIfPresent(Int.self, forKey: .daysPerWeek)
    }
}

// ProgramState is a normalized, runtime-friendly form
public final class ProgramState: Codable {
    public var rounding: Double
    public var initialMaxes: [String: Double]
    public var singleAt8Percent: [String: Double]
    // Int week keys for convenience
    public var lifts: [String: [Int: WeekData]]
    public var days: [Int: [DayItem]]
    public var weeks: [Int]
    /// SBS-style logs: logs[liftName][week][day] = LogEntry
    public var logs: [String: [Int: [Int: LogEntry]]]
    /// Structured logs: structuredLogs[liftName][week][day] = StructuredLogEntry
    public var structuredLogs: [String: [Int: [Int: StructuredLogEntry]]]
    /// Linear progression logs: linearLogs[liftName][week][day] = LinearLogEntry
    public var linearLogs: [String: [Int: [Int: LinearLogEntry]]]
    /// Configuration for linear progression (optional)
    public var linearProgressionConfig: LinearProgressionConfig?
    /// Day visibility by week - specifies which weeks each day is visible
    /// Keys are day numbers, values are arrays of week numbers
    /// If nil, all days are visible every week
    public var dayVisibility: [Int: [Int]]?

    public init(rounding: Double,
                initialMaxes: [String: Double],
                singleAt8Percent: [String: Double],
                lifts: [String: [Int: WeekData]],
                days: [Int: [DayItem]],
                weeks: [Int],
                logs: [String: [Int: [Int: LogEntry]]] = [:],
                structuredLogs: [String: [Int: [Int: StructuredLogEntry]]] = [:],
                linearLogs: [String: [Int: [Int: LinearLogEntry]]] = [:],
                linearProgressionConfig: LinearProgressionConfig? = nil,
                dayVisibility: [Int: [Int]]? = nil) {
        self.rounding = rounding
        self.initialMaxes = initialMaxes
        self.singleAt8Percent = singleAt8Percent
        self.lifts = lifts
        self.days = days
        self.weeks = weeks
        self.logs = logs
        self.structuredLogs = structuredLogs
        self.linearLogs = linearLogs
        self.linearProgressionConfig = linearProgressionConfig
        self.dayVisibility = dayVisibility
    }

    public static func fromProgramData(_ data: ProgramData) -> ProgramState {
        let liftsIntWeeks: [String: [Int: WeekData]] = data.lifts.mapValues { weekMap in
            var out: [Int: WeekData] = [:]
            for (k, v) in weekMap {
                if let wk = Int(k) { out[wk] = v }
            }
            return out
        }
        let daysInt: [Int: [DayItem]] = Dictionary(uniqueKeysWithValues: data.days.compactMap { (k, v) in
            guard let day = Int(k) else { return nil }
            return (day, v)
        })
        // Convert dayVisibility from string keys to int keys
        var dayVisibilityInt: [Int: [Int]]? = nil
        if let visibility = data.dayVisibility {
            dayVisibilityInt = Dictionary(uniqueKeysWithValues: visibility.compactMap { (k, v) in
                guard let day = Int(k) else { return nil }
                return (day, v)
            })
        }
        // Initialize empty logs for known lifts
        var logs: [String: [Int: [Int: LogEntry]]] = [:]
        for lift in data.lifts.keys { logs[lift] = [:] }
        return ProgramState(
            rounding: data.rounding,
            initialMaxes: data.initialMaxes,
            singleAt8Percent: data.singleAt8Percent,
            lifts: liftsIntWeeks,
            days: daysInt,
            weeks: data.weeks,
            logs: logs,
            structuredLogs: [:],
            linearLogs: [:],
            linearProgressionConfig: data.linearProgressionConfig,
            dayVisibility: dayVisibilityInt
        )
    }
}

// MARK: - Plan Item DTOs used by UI

/// Represents a single set in a structured exercise with calculated weight
public struct StructuredSetInfo: Equatable {
    public let setIndex: Int        // 0-based set index
    public let intensity: Double    // e.g., 0.75
    public let targetReps: Int      // target reps for this set
    public let isAMRAP: Bool        // whether this is a "+" set
    public let weight: Double       // calculated weight for this set
    public let loggedReps: Int?     // reps logged (for AMRAP sets only)
    
    public init(setIndex: Int, intensity: Double, targetReps: Int, isAMRAP: Bool, weight: Double, loggedReps: Int? = nil) {
        self.setIndex = setIndex
        self.intensity = intensity
        self.targetReps = targetReps
        self.isAMRAP = isAMRAP
        self.weight = weight
        self.loggedReps = loggedReps
    }
}

/// Information about a linear progression exercise for UI display
public struct LinearExerciseInfo: Equatable {
    public let lift: String
    public let weight: Double           // Current working weight
    public let sets: Int                // Number of sets (e.g., 5)
    public let reps: Int                // Reps per set (e.g., 5)
    public let consecutiveFailures: Int // Running failure count
    public let increment: Double        // Weight to add on success
    public let isDeloadPending: Bool    // Will deload if failed again
    public let logEntry: LinearLogEntry? // Previous log if exists
    
    public init(
        lift: String,
        weight: Double,
        sets: Int,
        reps: Int,
        consecutiveFailures: Int,
        increment: Double,
        isDeloadPending: Bool,
        logEntry: LinearLogEntry?
    ) {
        self.lift = lift
        self.weight = weight
        self.sets = sets
        self.reps = reps
        self.consecutiveFailures = consecutiveFailures
        self.increment = increment
        self.isDeloadPending = isDeloadPending
        self.logEntry = logEntry
    }
}

public enum PlanItem: Equatable {
    case tm(name: String, lift: String, trainingMax: Double, topSingleAt8: Double)
    case volume(name: String, lift: String, weight: Double, intensity: Double, sets: Int, repsPerSet: Int, repOutTarget: Int, loggedRepsLastSet: Int?, nextWeekTmDelta: Double?, isWeightOverridden: Bool, calculatedWeight: Double)
    case accessory(name: String, sets: Int, reps: Int, lastLog: AccessoryLog?)
    /// Structured exercise with explicit per-set intensity/reps configuration
    case structured(name: String, lift: String, trainingMax: Double, sets: [StructuredSetInfo], logEntry: StructuredLogEntry?)
    /// Linear progression exercise (StrongLifts, Starting Strength style)
    case linear(name: String, info: LinearExerciseInfo)
}

// MARK: - Custom Template

/// Mode for custom template - determines available options
public enum TemplateMode: String, Codable, CaseIterable {
    /// Simple mode - fixed sets/reps, no percentage-based progression
    case simple
    /// Advanced mode - full control with intensity curves, AMRAP sets, progression rules
    case advanced
    
    public var displayName: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        }
    }
    
    public var description: String {
        switch self {
        case .simple:
            return "Fixed sets and reps for each exercise. Great for straightforward programs."
        case .advanced:
            return "Percentage-based loading, AMRAP sets, and progression rules. For complex periodized programs."
        }
    }
}

/// A user-created custom workout template
public struct CustomTemplate: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var templateDescription: String
    public var createdAt: Date
    public var updatedAt: Date
    public var mode: TemplateMode
    public var daysPerWeek: Int
    public var weeks: [Int]
    public var days: [String: [DayItem]]  // String keys for JSON compatibility
    public var initialMaxes: [String: Double]
    public var singleAt8Percent: [String: Double]
    public var rounding: Double
    
    // Advanced mode only - week-based intensity progression
    public var lifts: [String: [String: WeekData]]?
    public var linearProgressionConfig: LinearProgressionConfig?
    
    public init(
        id: UUID = UUID(),
        name: String = "",
        templateDescription: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        mode: TemplateMode = .simple,
        daysPerWeek: Int = 4,
        weeks: [Int] = Array(1...12),
        days: [String: [DayItem]] = [:],
        initialMaxes: [String: Double] = [:],
        singleAt8Percent: [String: Double] = [:],
        rounding: Double = 5.0,
        lifts: [String: [String: WeekData]]? = nil,
        linearProgressionConfig: LinearProgressionConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.templateDescription = templateDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.daysPerWeek = daysPerWeek
        self.weeks = weeks
        self.days = days
        self.initialMaxes = initialMaxes
        self.singleAt8Percent = singleAt8Percent
        self.rounding = rounding
        self.lifts = lifts
        self.linearProgressionConfig = linearProgressionConfig
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case templateDescription = "description"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mode
        case daysPerWeek = "days_per_week"
        case weeks
        case days
        case initialMaxes = "initial_maxes"
        case singleAt8Percent = "single_at_8_percent"
        case rounding
        case lifts
        case linearProgressionConfig = "linear_progression"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        templateDescription = try container.decodeIfPresent(String.self, forKey: .templateDescription) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        mode = try container.decodeIfPresent(TemplateMode.self, forKey: .mode) ?? .simple
        daysPerWeek = try container.decode(Int.self, forKey: .daysPerWeek)
        weeks = try container.decode([Int].self, forKey: .weeks)
        days = try container.decode([String: [DayItem]].self, forKey: .days)
        // Default to empty dictionary if initial_maxes is not present (user will set their own)
        initialMaxes = try container.decodeIfPresent([String: Double].self, forKey: .initialMaxes) ?? [:]
        singleAt8Percent = try container.decodeIfPresent([String: Double].self, forKey: .singleAt8Percent) ?? [:]
        rounding = try container.decodeIfPresent(Double.self, forKey: .rounding) ?? 5.0
        lifts = try container.decodeIfPresent([String: [String: WeekData]].self, forKey: .lifts)
        linearProgressionConfig = try container.decodeIfPresent(LinearProgressionConfig.self, forKey: .linearProgressionConfig)
    }
    
    /// Convert this template to ProgramData for use with the existing workout system
    public func toProgramData() -> ProgramData {
        return ProgramData(
            name: "custom_\(id.uuidString)",
            displayName: name,
            programDescription: templateDescription,
            rounding: rounding,
            singleAt8Percent: singleAt8Percent.isEmpty ? defaultSingleAt8() : singleAt8Percent,
            initialMaxes: initialMaxes,
            lifts: lifts ?? [:],
            days: days,
            weeks: weeks,
            linearProgressionConfig: linearProgressionConfig
        )
    }
    
    /// Generate default single@8 percentages for all tracked lifts
    private func defaultSingleAt8() -> [String: Double] {
        var result: [String: Double] = [:]
        for lift in initialMaxes.keys {
            result[lift] = 0.9
        }
        return result
    }
    
    /// Get all unique lift names that require training maxes
    public var trackedLifts: [String] {
        var lifts: Set<String> = []
        for dayItems in days.values {
            for item in dayItems {
                if let lift = item.lift, item.type != .accessory {
                    lifts.insert(lift)
                }
            }
        }
        return lifts.sorted()
    }
    
    /// Validate the template has required data
    public var isValid: Bool {
        guard !name.isEmpty else { return false }
        guard daysPerWeek > 0 && daysPerWeek <= 7 else { return false }
        guard !weeks.isEmpty else { return false }
        guard !days.isEmpty else { return false }
        
        // Check all days have at least one exercise
        for dayNum in 1...daysPerWeek {
            guard let dayItems = days[String(dayNum)], !dayItems.isEmpty else {
                return false
            }
        }
        
        // Note: Training maxes are NOT required in the template - users set them when starting a cycle
        
        // Check no duplicate progression sets per lift
        guard duplicateProgressionSetLifts.isEmpty else { return false }
        
        return true
    }
    
    /// Find lifts that have multiple progression sets across the week (which would cause ambiguous TM calculation)
    public var duplicateProgressionSetLifts: [String] {
        // Track which lifts have a progression set marked (for autoregulated exercises)
        var liftsWithProgressionSet: [String: Int] = [:]  // lift name -> count of progression sets
        
        for (_, dayItems) in days {
            for item in dayItems {
                // Only check autoregulated exercises (structured type) that have a progression set marked
                guard item.type == .structured || item.type == .volume else { continue }
                guard let lift = item.lift else { continue }
                guard item.progressionSetIndex != nil else { continue }
                
                liftsWithProgressionSet[lift, default: 0] += 1
            }
        }
        
        // Return lifts that appear more than once
        return liftsWithProgressionSet
            .filter { $0.value > 1 }
            .map { $0.key }
            .sorted()
    }
    
    /// Get all validation warnings for the template
    public var validationWarnings: [String] {
        var warnings: [String] = []
        
        // Check for duplicate progression sets
        for lift in duplicateProgressionSetLifts {
            warnings.append("\(lift) has multiple progression sets. Each lift should only have one progression set per week.")
        }
        
        return warnings
    }
}

// MARK: - Completed Cycle (for history)

public struct CompletedCycle: Codable, Equatable, Identifiable {
    public var id: UUID
    public var cycleNumber: Int
    public var startDate: Date
    public var endDate: Date
    /// Starting training maxes for this cycle
    public var startingMaxes: [String: Double]
    /// Final calculated training maxes at end of cycle
    public var endingMaxes: [String: Double]
    /// All logged reps for this cycle: logs[liftName][week][day] = LogEntry
    public var logs: [String: [Int: [Int: LogEntry]]]
    /// Accessory logs from this cycle
    public var accessoryLogs: [String: AccessoryLog]
    /// The week the user was on when they ended the cycle (may not always be 20)
    public var lastCompletedWeek: Int
    /// Program ID that was used for this cycle (added for history reconstruction)
    public var programId: String?
    /// Display name of the program used for this cycle (stored directly to avoid lookup issues)
    public var programName: String?
    /// Structured logs for programs like nSuns: structuredLogs[liftName][week][day] = StructuredLogEntry
    public var structuredLogs: [String: [Int: [Int: StructuredLogEntry]]]
    /// Linear progression logs: linearLogs[liftName][week][day] = LinearLogEntry
    public var linearLogs: [String: [Int: [Int: LinearLogEntry]]]
    /// Pre-calculated TM history for each lift by week: tmHistory[liftName][week] = TM value
    /// This allows history to be displayed independently of the current program state
    public var tmHistory: [String: [Int: Double]]
    /// Pre-calculated weight/reps data for history display: liftData[liftName][week] = (weight, reps, e1rm)
    public var liftData: [String: [Int: LiftWeekData]]
    
    /// Data for a single week's lift performance
    public struct LiftWeekData: Codable, Equatable {
        public var weight: Double
        public var reps: Int
        public var e1rm: Double
        public var targetReps: Int
        
        public init(weight: Double, reps: Int, e1rm: Double, targetReps: Int) {
            self.weight = weight
            self.reps = reps
            self.e1rm = e1rm
            self.targetReps = targetReps
        }
    }
    
    public init(
        id: UUID = UUID(),
        cycleNumber: Int,
        startDate: Date,
        endDate: Date = Date(),
        startingMaxes: [String: Double],
        endingMaxes: [String: Double],
        logs: [String: [Int: [Int: LogEntry]]],
        accessoryLogs: [String: AccessoryLog] = [:],
        lastCompletedWeek: Int,
        programId: String? = nil,
        programName: String? = nil,
        structuredLogs: [String: [Int: [Int: StructuredLogEntry]]] = [:],
        linearLogs: [String: [Int: [Int: LinearLogEntry]]] = [:],
        tmHistory: [String: [Int: Double]] = [:],
        liftData: [String: [Int: LiftWeekData]] = [:]
    ) {
        self.id = id
        self.cycleNumber = cycleNumber
        self.startDate = startDate
        self.endDate = endDate
        self.startingMaxes = startingMaxes
        self.endingMaxes = endingMaxes
        self.logs = logs
        self.accessoryLogs = accessoryLogs
        self.lastCompletedWeek = lastCompletedWeek
        self.programId = programId
        self.programName = programName
        self.structuredLogs = structuredLogs
        self.linearLogs = linearLogs
        self.tmHistory = tmHistory
        self.liftData = liftData
    }
    
    /// Calculate the TM progression for a specific lift
    public func tmProgression(for lift: String) -> Double? {
        guard let start = startingMaxes[lift], let end = endingMaxes[lift], start > 0 else {
            return nil
        }
        return ((end - start) / start) * 100  // Percentage change
    }
}



