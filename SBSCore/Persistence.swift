import Foundation

// MARK: - Storage Protocol

public protocol KeyValueStore {
    func set(_ value: Data, forKey key: String)
    func data(forKey key: String) -> Data?
    func remove(forKey key: String)
}

public final class UserDefaultsStore: KeyValueStore {
    private let defaults: UserDefaults
    
    public init(suiteName: String? = nil) {
        if let suiteName = suiteName {
            self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        } else {
            self.defaults = .standard
        }
    }
    
    public func set(_ value: Data, forKey key: String) {
        defaults.set(value, forKey: key)
    }
    
    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }
    
    public func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Weight Adjustments (TM adjustment based on rep performance)

public struct WeightAdjustments: Codable, Equatable {
    /// Adjustment when below rep target by 2+ reps
    public var belowBy2Plus: Double
    /// Adjustment when below rep target by 1 rep
    public var belowBy1: Double
    /// Adjustment when hitting rep target exactly
    public var hitTarget: Double
    /// Adjustment when beating by 1 rep
    public var beatBy1: Double
    /// Adjustment when beating by 2 reps
    public var beatBy2: Double
    /// Adjustment when beating by 3 reps
    public var beatBy3: Double
    /// Adjustment when beating by 4 reps
    public var beatBy4: Double
    /// Adjustment when beating by 5+ reps
    public var beatBy5Plus: Double
    
    public init(
        belowBy2Plus: Double = -0.05,
        belowBy1: Double = -0.02,
        hitTarget: Double = 0.0,
        beatBy1: Double = 0.005,
        beatBy2: Double = 0.01,
        beatBy3: Double = 0.015,
        beatBy4: Double = 0.02,
        beatBy5Plus: Double = 0.03
    ) {
        self.belowBy2Plus = belowBy2Plus
        self.belowBy1 = belowBy1
        self.hitTarget = hitTarget
        self.beatBy1 = beatBy1
        self.beatBy2 = beatBy2
        self.beatBy3 = beatBy3
        self.beatBy4 = beatBy4
        self.beatBy5Plus = beatBy5Plus
    }
    
    public static let `default` = WeightAdjustments()
    
    /// Get the adjustment for a given rep difference from target
    public func adjustment(for repDiff: Int) -> Double {
        if repDiff <= -2 { return belowBy2Plus }
        if repDiff == -1 { return belowBy1 }
        if repDiff == 0 { return hitTarget }
        if repDiff == 1 { return beatBy1 }
        if repDiff == 2 { return beatBy2 }
        if repDiff == 3 { return beatBy3 }
        if repDiff == 4 { return beatBy4 }
        return beatBy5Plus
    }
    
    /// Format a value as a percentage string
    public static func formatPercent(_ value: Double) -> String {
        let percent = value * 100
        if percent >= 0 {
            return "+\(String(format: "%.1f", percent))%"
        }
        return "\(String(format: "%.1f", percent))%"
    }
}

// MARK: - User Settings

// MARK: - Appearance Mode

public enum AppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark
    
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    public var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

public struct UserSettings: Codable, Equatable {
    public var useMetric: Bool
    public var roundingIncrement: Double
    public var currentWeek: Int
    public var currentDay: Int
    public var restTimerDuration: Int  // seconds
    public var supersetAccessories: Bool  // show accessories during rest timer
    public var weightAdjustments: WeightAdjustments  // TM adjustment based on rep performance
    public var barWeight: Double  // in lbs (45 for standard, 35 for women's, etc.)
    public var showPlateCalculator: Bool  // show visual plate calculator in workouts
    public var playSoundNotifications: Bool  // play chime when rest timer ends
    public var appearanceMode: AppearanceMode  // light/dark/system appearance setting
    public var bodyweight: Double?  // user's bodyweight in lbs (nil if not set)
    public var isMale: Bool  // for strength standards calculations
    public var showPRCelebrations: Bool  // show PR celebration animation when new PR is achieved
    public var healthKitEnabled: Bool  // sync workouts to Apple Fitness
    public var pushNotificationsEnabled: Bool  // send push notification when rest timer ends (background only)
    
    public init(
        useMetric: Bool = false,
        roundingIncrement: Double = 5.0,
        currentWeek: Int = 1,
        currentDay: Int = 1,
        restTimerDuration: Int = 120,  // default 2 minutes
        supersetAccessories: Bool = false,
        weightAdjustments: WeightAdjustments = .default,
        barWeight: Double = 45.0,
        showPlateCalculator: Bool = true,
        playSoundNotifications: Bool = true,
        appearanceMode: AppearanceMode = .system,
        bodyweight: Double? = nil,
        isMale: Bool = true,
        showPRCelebrations: Bool = true,
        healthKitEnabled: Bool = false,  // default off, user must opt-in
        pushNotificationsEnabled: Bool = true  // default on for better UX
    ) {
        self.useMetric = useMetric
        self.roundingIncrement = roundingIncrement
        self.currentWeek = currentWeek
        self.currentDay = currentDay
        self.restTimerDuration = restTimerDuration
        self.supersetAccessories = supersetAccessories
        self.weightAdjustments = weightAdjustments
        self.barWeight = barWeight
        self.showPlateCalculator = showPlateCalculator
        self.playSoundNotifications = playSoundNotifications
        self.appearanceMode = appearanceMode
        self.bodyweight = bodyweight
        self.isMale = isMale
        self.showPRCelebrations = showPRCelebrations
        self.healthKitEnabled = healthKitEnabled
        self.pushNotificationsEnabled = pushNotificationsEnabled
    }
    
    public static let `default` = UserSettings()
}

// MARK: - Personal Record

public struct PersonalRecord: Codable, Equatable {
    public var estimatedOneRM: Double  // Best E1RM achieved
    public var weight: Double          // Weight used
    public var reps: Int               // Reps performed
    public var date: Date              // When it was achieved
    public var cycleNumber: Int        // Which cycle
    public var week: Int               // Which week
    
    public init(estimatedOneRM: Double, weight: Double, reps: Int, date: Date = Date(), cycleNumber: Int = 1, week: Int = 1) {
        self.estimatedOneRM = estimatedOneRM
        self.weight = weight
        self.reps = reps
        self.date = date
        self.cycleNumber = cycleNumber
        self.week = week
    }
}

// MARK: - User Data (Logs + Custom TMs + Custom Exercises)

public struct UserData: Codable, Equatable {
    // MARK: - Program-specific logs (for week-based tracking within a program)
    
    // logs[liftName][week][day] = LogEntry (SBS-style)
    public var logs: [String: [Int: [Int: LogEntry]]]
    // Structured exercise logs: structuredLogs[liftName][week][day] = StructuredLogEntry
    public var structuredLogs: [String: [Int: [Int: StructuredLogEntry]]]
    // Linear progression logs: linearLogs[liftName][week][day] = LinearLogEntry
    public var linearLogs: [String: [Int: [Int: LinearLogEntry]]]
    
    // MARK: - Program-specific configuration
    
    // Custom starting TMs for current program cycle (overrides config defaults)
    public var customInitialMaxes: [String: Double]
    // Custom day configurations (overrides config defaults)
    // customDays[dayNumber] = [DayItem]
    public var customDays: [Int: [DayItem]]
    // Accessory logs - keyed by accessory name
    public var accessoryLogs: [String: AccessoryLog]
    // Selected program ID
    public var selectedProgram: String?
    
    // MARK: - Universal tracking (program-agnostic)
    
    // Current training max per lift - used across all programs
    public var trainingMaxes: [String: Double]
    // Complete lift history - all recorded performances
    public var liftHistory: [LiftRecord]
    // Personal records per lift (best E1RM) - derived from liftHistory
    public var personalRecords: [String: PersonalRecord]
    // Complete workout records - stores all data for history display (new system)
    public var workoutRecords: [WorkoutRecord]
    
    // MARK: - Cycle management
    
    // When the current cycle started
    public var currentCycleStartDate: Date
    // History of completed cycles
    public var cycleHistory: [CompletedCycle]
    
    // MARK: - Custom templates
    
    // User-created workout templates
    public var customTemplates: [CustomTemplate]
    
    // MARK: - App state
    
    // Whether onboarding has been completed
    public var hasCompletedOnboarding: Bool
    
    public init(
        logs: [String: [Int: [Int: LogEntry]]] = [:],
        structuredLogs: [String: [Int: [Int: StructuredLogEntry]]] = [:],
        linearLogs: [String: [Int: [Int: LinearLogEntry]]] = [:],
        customInitialMaxes: [String: Double] = [:],
        customDays: [Int: [DayItem]] = [:],
        accessoryLogs: [String: AccessoryLog] = [:],
        selectedProgram: String? = nil,
        trainingMaxes: [String: Double] = [:],
        liftHistory: [LiftRecord] = [],
        personalRecords: [String: PersonalRecord] = [:],
        workoutRecords: [WorkoutRecord] = [],
        currentCycleStartDate: Date = Date(),
        cycleHistory: [CompletedCycle] = [],
        customTemplates: [CustomTemplate] = [],
        hasCompletedOnboarding: Bool = false
    ) {
        self.logs = logs
        self.structuredLogs = structuredLogs
        self.linearLogs = linearLogs
        self.customInitialMaxes = customInitialMaxes
        self.customDays = customDays
        self.accessoryLogs = accessoryLogs
        self.selectedProgram = selectedProgram
        self.trainingMaxes = trainingMaxes
        self.liftHistory = liftHistory
        self.personalRecords = personalRecords
        self.workoutRecords = workoutRecords
        self.currentCycleStartDate = currentCycleStartDate
        self.cycleHistory = cycleHistory
        self.customTemplates = customTemplates
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
    
    // MARK: - Lift History Helpers
    
    /// Add a lift record to history and update PR if applicable
    public mutating func recordLift(_ record: LiftRecord) {
        liftHistory.append(record)
        
        // Check if this is a new PR
        if let existingPR = personalRecords[record.liftName] {
            if record.estimatedOneRM > existingPR.estimatedOneRM {
                personalRecords[record.liftName] = PersonalRecord(
                    estimatedOneRM: record.estimatedOneRM,
                    weight: record.weight,
                    reps: record.reps,
                    date: record.date,
                    cycleNumber: cycleHistory.count + 1,
                    week: record.week ?? 0
                )
            }
        } else {
            // First record for this lift is automatically a PR
            personalRecords[record.liftName] = PersonalRecord(
                estimatedOneRM: record.estimatedOneRM,
                weight: record.weight,
                reps: record.reps,
                date: record.date,
                cycleNumber: cycleHistory.count + 1,
                week: record.week ?? 0
            )
        }
    }
    
    /// Get all records for a specific lift, sorted by date
    public func history(for liftName: String) -> [LiftRecord] {
        liftHistory
            .filter { $0.liftName == liftName }
            .sorted { $0.date < $1.date }
    }
    
    /// Get the best E1RM record for a lift
    public func bestRecord(for liftName: String) -> LiftRecord? {
        liftHistory
            .filter { $0.liftName == liftName }
            .max { $0.estimatedOneRM < $1.estimatedOneRM }
    }
    
    /// Get all unique lift names from history
    public var allRecordedLifts: [String] {
        Array(Set(liftHistory.map { $0.liftName })).sorted()
    }
    
    // MARK: - Template Management
    
    /// Add a new custom template
    public mutating func addTemplate(_ template: CustomTemplate) {
        customTemplates.append(template)
    }
    
    /// Update an existing template
    public mutating func updateTemplate(_ template: CustomTemplate) {
        if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
            var updated = template
            updated.updatedAt = Date()
            customTemplates[index] = updated
        }
    }
    
    /// Delete a template by ID
    public mutating func deleteTemplate(id: UUID) {
        customTemplates.removeAll { $0.id == id }
    }
    
    /// Get a template by ID
    public func template(withId id: UUID) -> CustomTemplate? {
        customTemplates.first { $0.id == id }
    }
    
    /// Get the program ID string for a custom template
    public static func programId(for templateId: UUID) -> String {
        "custom_\(templateId.uuidString)"
    }
    
    /// Check if a program ID corresponds to a custom template
    public static func isCustomTemplate(programId: String) -> Bool {
        programId.hasPrefix("custom_")
    }
    
    /// Extract template UUID from a custom program ID
    public static func templateId(from programId: String) -> UUID? {
        guard isCustomTemplate(programId: programId) else { return nil }
        let uuidString = String(programId.dropFirst("custom_".count))
        return UUID(uuidString: uuidString)
    }
    
    public static let empty = UserData()
}

// MARK: - Persistence Manager

public final class ProgramPersistence {
    private let store: KeyValueStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private let settingsKey = "sbs_settings"
    private let userDataKey = "sbs_user_data"
    private let programStateKey = "sbs_program_state"
    
    public init(store: KeyValueStore = UserDefaultsStore()) {
        self.store = store
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    
    // MARK: - Settings
    
    public func saveSettings(_ settings: UserSettings) throws {
        let data = try encoder.encode(settings)
        store.set(data, forKey: settingsKey)
    }
    
    public func loadSettings() -> UserSettings {
        guard let data = store.data(forKey: settingsKey),
              let settings = try? decoder.decode(UserSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    // MARK: - User Data (Logs + Custom TMs)
    
    public func saveUserData(_ userData: UserData) throws {
        let data = try encoder.encode(userData)
        store.set(data, forKey: userDataKey)
    }
    
    public func loadUserData() -> UserData {
        guard let data = store.data(forKey: userDataKey),
              let userData = try? decoder.decode(UserData.self, from: data) else {
            return .empty
        }
        return userData
    }
    
    // MARK: - Full Program State (Legacy support)
    
    public func saveProgramState(_ state: ProgramState) throws {
        let data = try encoder.encode(state)
        store.set(data, forKey: programStateKey)
    }
    
    public func loadProgramState() -> ProgramState? {
        guard let data = store.data(forKey: programStateKey) else { return nil }
        return try? decoder.decode(ProgramState.self, from: data)
    }
    
    // MARK: - Export/Import
    
    public func exportUserDataJSON() throws -> Data {
        let userData = loadUserData()
        return try encoder.encode(userData)
    }
    
    public func importUserDataJSON(_ data: Data) throws {
        let userData = try decoder.decode(UserData.self, from: data)
        try saveUserData(userData)
    }
    
    // MARK: - Reset
    
    public func resetAllLogs() {
        var userData = loadUserData()
        userData.logs = [:]
        try? saveUserData(userData)
    }
    
    public func resetEverything() {
        store.remove(forKey: settingsKey)
        store.remove(forKey: userDataKey)
        store.remove(forKey: programStateKey)
    }
}
