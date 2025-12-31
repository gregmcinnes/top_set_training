import Foundation
import SwiftUI

@Observable
public final class AppState {
    // MARK: - Program Data (Immutable from config)
    private(set) var programData: ProgramData?
    private(set) var programState: ProgramState?
    
    // MARK: - User Settings
    var settings: UserSettings {
        didSet {
            persistSettings()
            // Sync weight adjustments to engine
            engine.weightAdjustments = settings.weightAdjustments
        }
    }
    
    // MARK: - User Data
    var userData: UserData {
        didSet { persistUserData() }
    }
    
    // MARK: - UI State
    var selectedWeek: Int {
        get { settings.currentWeek }
        set {
            let maxWeek = programState?.weeks.max() ?? 20
            settings.currentWeek = newValue.clamped(to: 1...maxWeek)
            // After changing week, ensure selectedDay is valid for the new week
            let visible = visibleDays(forWeek: settings.currentWeek)
            if !visible.isEmpty && !visible.contains(settings.currentDay) {
                // Select the first visible day for the new week
                settings.currentDay = visible.first ?? 1
            }
        }
    }
    
    var selectedDay: Int {
        get {
            let current = settings.currentDay
            let visible = visibleDays(forWeek: selectedWeek)
            // If current day is not visible for the current week, return first visible day
            if !visible.isEmpty && !visible.contains(current) {
                return visible.first ?? 1
            }
            return current
        }
        set {
            let visible = visibleDays(forWeek: selectedWeek)
            // Only allow setting to visible days
            if visible.isEmpty || visible.contains(newValue) {
                settings.currentDay = newValue
            } else if let first = visible.first {
                settings.currentDay = first
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var weeks: [Int] {
        programState?.weeks ?? Array(1...20)
    }
    
    /// Returns visible days for the current week (filtered by dayVisibility if present)
    var days: [Int] {
        visibleDays(forWeek: selectedWeek)
    }
    
    /// Returns all days in the program, regardless of week visibility
    var allDays: [Int] {
        guard let state = programState else { return Array(1...5) }
        return state.days.keys.sorted()
    }
    
    /// Returns visible days for a specific week (filtered by dayVisibility if present)
    func visibleDays(forWeek week: Int) -> [Int] {
        guard let state = programState else { return Array(1...5) }
        
        // If there's no dayVisibility configuration, return all days
        guard let visibility = state.dayVisibility else {
            return state.days.keys.sorted()
        }
        
        // Filter days that are visible for this week
        return state.days.keys.filter { day in
            guard let visibleWeeks = visibility[day] else {
                // No visibility specified for this day = always visible
                return true
            }
            return visibleWeeks.contains(week)
        }.sorted()
    }
    
    var liftNames: [String] {
        var lifts = Set<String>()
        
        // Add lifts from program state
        if let state = programState {
            // Get lifts from the lifts dictionary (SBS-style programs)
            lifts.formUnion(state.lifts.keys)
            
            // Also get lifts from day items (for nSuns programs which may not use the lifts dict)
            for (_, items) in state.days {
                for item in items {
                    if let lift = item.lift {
                        lifts.insert(lift)
                    }
                }
            }
        }
        
        // Also include lifts from unified history (program-agnostic)
        lifts.formUnion(userData.allRecordedLifts)
        
        return lifts.sorted()
    }
    
    var rounding: Double {
        settings.roundingIncrement
    }
    
    /// Whether to show the plate calculator (combines user setting with premium access check)
    var shouldShowPlateCalculator: Bool {
        settings.showPlateCalculator && StoreManager.shared.canAccess(.plateCalculator)
    }
    
    // MARK: - Dependencies
    
    private let persistence: ProgramPersistence
    private let engine: ProgramEngine
    
    // MARK: - Initialization
    
    public init(persistence: ProgramPersistence = ProgramPersistence()) {
        self.persistence = persistence
        let loadedSettings = persistence.loadSettings()
        self.engine = ProgramEngine(weightAdjustments: loadedSettings.weightAdjustments)
        self.settings = loadedSettings
        self.userData = persistence.loadUserData()
    }
    
    // MARK: - Available Programs
    
    /// Info about an available program in the bundle
    struct AvailableProgramInfo: Identifiable, Equatable {
        let id: String  // filename without extension
        let name: String
        /// Generic display name to avoid trademark issues (uses displayName if available, falls back to name)
        let displayName: String
        /// Description of the program for display in the UI
        let programDescription: String
        let weeks: Int
        let days: Int
        let url: URL
    }
    
    /// Cached list of available programs
    private(set) var availablePrograms: [AvailableProgramInfo] = []
    
    /// Discover all available program JSON files in the bundle
    func discoverAvailablePrograms() async {
        // Known program files to check
        let programFiles = [
            "stronglifts_5x5_12week",
            "starting_strength_12week",
            "greyskull_lp_12week",
            "gzclp_12week",
            "gzclp_3day_12week",
            "531_bbb_12week",
            "531_triumvirate_12week",
            "nsuns_4day_12week",
            "nsuns_5day_12week",
            "reddit_ppl_12week",
            "sbs_program_config"
        ]
        
        var discoveredPrograms: [AvailableProgramInfo] = []
        
        for filename in programFiles {
            if let url = Bundle.main.url(forResource: filename, withExtension: "json") {
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    let pdata = try decoder.decode(ProgramData.self, from: data)
                    
                    discoveredPrograms.append(AvailableProgramInfo(
                        id: filename,
                        name: pdata.name,
                        displayName: pdata.displayName ?? pdata.name,
                        programDescription: pdata.programDescription ?? "A structured training program to help you get stronger.",
                        weeks: pdata.weeks.count,
                        days: pdata.daysPerWeek ?? pdata.days.count,
                        url: url
                    ))
                } catch {
                    // Skip files that fail to parse
                    print("Failed to parse program \(filename): \(error)")
                }
            }
        }
        
        let programsToSet = discoveredPrograms
        await MainActor.run {
            self.availablePrograms = programsToSet
        }
    }
    
    // MARK: - Load Program Config
    
    /// Load the default program or previously selected program
    func loadProgramConfig() async throws {
        // First discover available programs
        await discoverAvailablePrograms()
        
        // Check if user has a previously selected program
        if let selectedId = userData.selectedProgram,
           let program = availablePrograms.first(where: { $0.id == selectedId }) {
            try await loadFromURL(program.url)
            return
        }
        
        // Try loading default (StrongLifts 5x5 - beginner friendly)
        if let program = availablePrograms.first(where: { $0.id == "stronglifts_5x5_12week" }) {
            try await loadFromURL(program.url)
            return
        }
        
        // Fallback to first available
        if let program = availablePrograms.first {
            try await loadFromURL(program.url)
            return
        }
        
        throw AppError.configNotFound
    }
    
    /// Load a specific program by its ID
    func loadProgram(_ programId: String) async throws {
        // Check if we're switching to a different program
        let isSwitchingPrograms = userData.selectedProgram != nil && userData.selectedProgram != programId
        
        // Check if this is a custom template
        if UserData.isCustomTemplate(programId: programId) {
            guard let templateId = UserData.templateId(from: programId),
                  let template = userData.template(withId: templateId) else {
                throw AppError.configNotFound
            }
            
            // Clear program-specific data when switching programs
            if isSwitchingPrograms {
                userData.customDays = [:]
                userData.customInitialMaxes = [:]
            }
            
            // Save the selection
            userData.selectedProgram = programId
            
            // Convert template to ProgramData and load it
            let pdata = template.toProgramData()
            await MainActor.run {
                self.programData = pdata
                self.programState = ProgramState.fromProgramData(pdata)
                
                // Apply user data to program state
                if let state = self.programState {
                    state.logs = self.userData.logs
                    state.structuredLogs = self.userData.structuredLogs
                    state.linearLogs = self.userData.linearLogs
                    
                    // Apply custom initial maxes (only if not switching programs)
                    if !isSwitchingPrograms {
                        for (lift, max) in self.userData.customInitialMaxes {
                            state.initialMaxes[lift] = max
                        }
                        
                        // Apply custom day configurations
                        for (day, items) in self.userData.customDays {
                            state.days[day] = items
                        }
                    }
                    
                    // Apply rounding from settings
                    state.rounding = self.settings.roundingIncrement
                }
            }
            return
        }
        
        // Standard program loading
        guard let program = availablePrograms.first(where: { $0.id == programId }) else {
            throw AppError.configNotFound
        }
        
        // Clear program-specific data when switching programs
        if isSwitchingPrograms {
            userData.customDays = [:]
            userData.customInitialMaxes = [:]
        }
        
        // Save the selection
        userData.selectedProgram = programId
        
        try await loadFromURL(program.url)
    }
    
    private func loadFromURL(_ url: URL) async throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let pdata = try decoder.decode(ProgramData.self, from: data)
        
        await MainActor.run {
            self.programData = pdata
            self.programState = ProgramState.fromProgramData(pdata)
            
            // Apply user data to program state
            if let state = self.programState {
                state.logs = self.userData.logs
                state.structuredLogs = self.userData.structuredLogs
                state.linearLogs = self.userData.linearLogs
                
                // Apply custom initial maxes
                for (lift, max) in self.userData.customInitialMaxes {
                    state.initialMaxes[lift] = max
                }
                
                // Apply custom day configurations
                for (day, items) in self.userData.customDays {
                    state.days[day] = items
                }
                
                // Apply rounding from settings
                state.rounding = self.settings.roundingIncrement
            }
        }
    }
    
    // MARK: - Get Plans
    
    func weekPlan(for week: Int) -> [Int: [PlanItem]]? {
        guard let state = programState else { return nil }
        // Sync logs before computing
        state.logs = userData.logs
        state.structuredLogs = userData.structuredLogs
        state.linearLogs = userData.linearLogs
        state.rounding = settings.roundingIncrement
        
        // Sync custom initial maxes (from user onboarding) with program state
        // This ensures structured TM calculations use the correct starting values
        for (lift, max) in userData.customInitialMaxes {
            state.initialMaxes[lift] = max
        }
        
        return try? engine.weekPlan(state: state, week: week, accessoryLogs: userData.accessoryLogs)
    }
    
    func dayPlan(week: Int, day: Int) -> [PlanItem]? {
        weekPlan(for: week)?[day]
    }
    
    func currentDayPlan() -> [PlanItem]? {
        dayPlan(week: selectedWeek, day: selectedDay)
    }
    
    // MARK: - Lift-Based Training Maxes (Program-Agnostic)
    
    /// Get the current training max for a lift (program-agnostic)
    func currentTrainingMax(for lift: String) -> Double? {
        // First check user's lift-based TMs
        if let tm = userData.trainingMaxes[lift] {
            return tm
        }
        // Fall back to custom initial maxes (from cycle setup)
        if let tm = userData.customInitialMaxes[lift] {
            return tm
        }
        // Fall back to program defaults
        return programState?.initialMaxes[lift]
    }
    
    /// Set the training max for a lift (program-agnostic)
    func setTrainingMax(for lift: String, value: Double) {
        userData.trainingMaxes[lift] = value
    }
    
    /// Get all current training maxes
    var currentTrainingMaxes: [String: Double] {
        var tms: [String: Double] = [:]
        // Start with program defaults
        if let state = programState {
            for (lift, tm) in state.initialMaxes {
                tms[lift] = tm
            }
        }
        // Override with custom initial maxes
        for (lift, tm) in userData.customInitialMaxes {
            tms[lift] = tm
        }
        // Override with lift-based TMs
        for (lift, tm) in userData.trainingMaxes {
            tms[lift] = tm
        }
        return tms
    }
    
    // MARK: - Unified Lift History (Program-Agnostic)
    
    /// Get lift history for a specific lift
    func liftHistory(for lift: String) -> [LiftRecord] {
        userData.history(for: lift)
    }
    
    /// Get all-time personal record for a lift
    func personalRecord(for lift: String) -> PersonalRecord? {
        userData.personalRecords[lift]
    }
    
    /// Get all unique lifts that have been recorded
    var allRecordedLifts: [String] {
        userData.allRecordedLifts
    }
    
    /// Get E1RM progression data for charting (from unified history)
    func e1rmProgression(for lift: String) -> [(date: Date, e1rm: Double, weight: Double, reps: Int)] {
        userData.history(for: lift).map { record in
            (record.date, record.estimatedOneRM, record.weight, record.reps)
        }
    }
    
    // MARK: - Training Max Calculations (Program-Specific)
    
    func trainingMax(for lift: String, week: Int) -> Double? {
        guard let state = programState else { return nil }
        state.logs = userData.logs
        state.structuredLogs = userData.structuredLogs
        
        // Sync custom initial maxes (from user onboarding) with program state
        for (liftName, max) in userData.customInitialMaxes {
            state.initialMaxes[liftName] = max
        }
        
        // First try SBS-style TM calculation
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: week)
        if let tm = tms[week]?[lift] {
            return tm
        }
        
        // Try structured TM calculation
        let structuredLiftInfo = getAllStructuredLiftInfo()
        if structuredLiftInfo[lift] != nil {
            let structuredTMs = engine.computeStructuredTrainingMaxes(state: state, upToWeek: week, structuredLiftInfo: structuredLiftInfo)
            if let tm = structuredTMs[week]?[lift] {
                return tm
            }
        }
        
        // Fallback to initial max
        return userData.customInitialMaxes[lift] ?? state.initialMaxes[lift]
    }
    
    func allTrainingMaxes(for lift: String) -> [(week: Int, tm: Double)] {
        guard let state = programState else { return [] }
        state.logs = userData.logs
        state.structuredLogs = userData.structuredLogs
        state.linearLogs = userData.linearLogs
        
        // Sync custom initial maxes (from user onboarding) with program state
        for (liftName, max) in userData.customInitialMaxes {
            state.initialMaxes[liftName] = max
        }
        
        let maxWeek = weeks.max() ?? 20
        
        // Check if this is a linear progression lift
        let isLinearLift = state.days.values.flatMap { $0 }.contains { item in
            item.type == .linear && item.lift == lift
        }
        
        if isLinearLift {
            // For linear lifts, gather TM data from linearLogs
            // The "training max" for linear is the working weight at each session
            var result: [(week: Int, tm: Double)] = []
            
            if let liftLogs = userData.linearLogs[lift] {
                for (week, dayLogs) in liftLogs.sorted(by: { $0.key < $1.key }) {
                    // Get the weight from any logged day in this week
                    for (_, entry) in dayLogs {
                        result.append((week, entry.weight))
                        break // Only take one entry per week for the chart
                    }
                }
            }
            
            return result
        }
        
        // Check if this is a structured lift
        let structuredLiftInfo = getAllStructuredLiftInfo()
        let isStructuredLift = structuredLiftInfo[lift] != nil
        
        if isStructuredLift {
            // Use structured TM calculation with weekly adjustments based on 1+ set
            let structuredTMs = engine.computeStructuredTrainingMaxes(state: state, upToWeek: maxWeek, structuredLiftInfo: structuredLiftInfo)
            return weeks.compactMap { week in
                guard let tm = structuredTMs[week]?[lift] else { return nil }
                // Include if we have structured logs for this week or any previous week (any day)
                let hasLogsUpToWeek = (1...week).contains { wk in
                    userData.structuredLogs[lift]?[wk]?.values.contains { $0.amrapReps.count > 0 } == true
                }
                if hasLogsUpToWeek {
                    return (week, tm)
                }
                return nil
            }
        }
        
        // SBS-style: return computed TMs for weeks with logs
        let tms = engine.computeTrainingMaxes(state: state, upToWeek: maxWeek)
        return weeks.compactMap { week in
            guard let tm = tms[week]?[lift] else { return nil }
            // Only include weeks with actual logs (any day in the week)
            let hasLog = userData.logs[lift]?[week]?.values.contains { $0.repsLastSet != nil } == true
            if hasLog {
                return (week, tm)
            }
            return nil
        }
    }
    
    /// Get info about all structured lifts and their primary (1+) AMRAP sets
    private func getAllStructuredLiftInfo() -> [String: (setIndex: Int, intensity: Double)] {
        guard let state = programState else { return [:] }
        var liftInfo: [String: (setIndex: Int, intensity: Double)] = [:]
        
        for (_, items) in state.days {
            for item in items {
                guard item.type == .structured,
                      let lift = item.lift,
                      liftInfo[lift] == nil else { continue }
                
                // Get sets_detail - prefer static, or use week 1 from week-based
                // Note: Must use explicit ["1"] key, not .values.first, because dictionaries are unordered
                // Using .values.first could return week 4 (deload) which has no AMRAP sets
                let setsDetail: [SetDetail]
                if let staticSets = item.setsDetail {
                    setsDetail = staticSets
                } else if let weekBasedSets = item.setsDetailByWeek?["1"] {
                    setsDetail = weekBasedSets
                } else {
                    continue
                }
                
                // Find the 1+ set (AMRAP with target of 1 rep)
                for (index, setDetail) in setsDetail.enumerated() {
                    if setDetail.isAMRAP && setDetail.reps == 1 {
                        liftInfo[lift] = (index, setDetail.intensity)
                        break
                    }
                }
                
                // Fallback: find any AMRAP set with highest intensity
                if liftInfo[lift] == nil {
                    let amrapSets = setsDetail.enumerated().filter { $0.element.isAMRAP }
                    if let primary = amrapSets.max(by: { $0.element.intensity < $1.element.intensity }) {
                        liftInfo[lift] = (primary.offset, primary.element.intensity)
                    }
                }
            }
        }
        
        return liftInfo
    }
    
    /// Calculate estimated 1RM for completed weeks only
    /// Uses Epley formula: 1RM = weight × (1 + reps/30)
    /// Works for both SBS (last set AMRAP) and structured (1+ set AMRAP)
    func estimatedOneRepMaxes(for lift: String) -> [(week: Int, e1rm: Double, weight: Double, reps: Int)] {
        guard let state = programState else { return [] }
        state.logs = userData.logs
        state.structuredLogs = userData.structuredLogs
        state.linearLogs = userData.linearLogs
        
        let maxWeek = weeks.max() ?? 20
        
        // Pre-compute TMs for all weeks
        let sbsTMs = engine.computeTrainingMaxes(state: state, upToWeek: maxWeek)
        let structuredLiftInfo = getAllStructuredLiftInfo()
        let structuredTMs = engine.computeStructuredTrainingMaxes(state: state, upToWeek: maxWeek, structuredLiftInfo: structuredLiftInfo)
        
        // Check if this is a linear progression lift
        let isLinearLift = state.days.values.flatMap { $0 }.contains { item in
            item.type == .linear && item.lift == lift
        }
        
        // For linear lifts, get data directly from linearLogs
        if isLinearLift {
            var result: [(week: Int, e1rm: Double, weight: Double, reps: Int)] = []
            
            if let liftLogs = userData.linearLogs[lift] {
                for (week, dayLogs) in liftLogs.sorted(by: { $0.key < $1.key }) {
                    for (_, entry) in dayLogs {
                        // Find the default reps for this lift
                        let defaultReps = state.days.values.flatMap { $0 }
                            .first { $0.type == .linear && $0.lift == lift }?.reps ?? 5
                        let reps = entry.completed ? defaultReps : max(1, defaultReps - 1)
                        let e1rm = calculateE1RM(weight: entry.weight, reps: reps)
                        result.append((week, e1rm, entry.weight, reps))
                        break // Only take one entry per week
                    }
                }
            }
            
            return result
        }
        
        return weeks.compactMap { week -> (Int, Double, Double, Int)? in
            // First, try SBS-style logs (find any day with a log for this lift/week)
            if let dayLogs = userData.logs[lift]?[week],
               let weekData = state.lifts[lift]?[week] {
                // Find the first day with logged reps
                for (_, logEntry) in dayLogs {
                    if let reps = logEntry.repsLastSet {
                        guard let tm = sbsTMs[week]?[lift] else { continue }
                        let weight = roundWeight(tm * weekData.intensity)
                        let e1rm = weight * (1.0 + Double(reps) / 30.0)
                        return (week, e1rm, weight, reps)
                    }
                }
            }
            
            // Try structured-style logs - look for the 1+ set (primary progression set)
            if let dayLogs = userData.structuredLogs[lift]?[week],
               let setInfo = structuredLiftInfo[lift] {
                // Find the first day with logged AMRAP reps
                for (_, structuredLog) in dayLogs {
                    if let reps = structuredLog.amrapReps[setInfo.setIndex] {
                        // Use weekly-adjusted structured TM
                        let tm = structuredTMs[week]?[lift] ?? state.initialMaxes[lift] ?? 0
                        let weight = roundWeight(tm * setInfo.intensity)
                        let e1rm = weight * (1.0 + Double(reps) / 30.0)
                        return (week, e1rm, weight, reps)
                    }
                }
            }
            
            return nil
        }
    }
    
    
    /// Round weight to the configured increment
    private func roundWeight(_ weight: Double) -> Double {
        let increment = settings.roundingIncrement
        guard increment > 0 else { return weight }
        return (weight / increment).rounded() * increment
    }
    
    // MARK: - Logging
    
    /// Result of logging reps - includes PR information
    struct LogRepsResult {
        let isNewPR: Bool
        let newE1RM: Double
        let previousE1RM: Double?
        let weight: Double
        let reps: Int
        let liftName: String
    }
    
    /// Log reps and check for a new personal record
    /// Returns information about whether a PR was achieved
    @discardableResult
    func logReps(lift: String, week: Int, day: Int, reps: Int, note: String = "") -> LogRepsResult? {
        // Ensure nested dictionaries exist
        if userData.logs[lift] == nil {
            userData.logs[lift] = [:]
        }
        if userData.logs[lift]?[week] == nil {
            userData.logs[lift]?[week] = [:]
        }
        // Preserve existing weight override if any
        let existingOverride = userData.logs[lift]?[week]?[day]?.weightOverride
        userData.logs[lift]?[week]?[day] = LogEntry(repsLastSet: reps, note: note, weightOverride: existingOverride)
        
        // Calculate E1RM for this set
        guard let state = programState,
              let weekData = state.lifts[lift]?[week],
              let tm = trainingMax(for: lift, week: week) else {
            return nil
        }
        
        // Use overridden weight if set, otherwise calculate from TM
        let calculatedWeight = roundWeight(tm * weekData.intensity)
        let weight = existingOverride ?? calculatedWeight
        let newE1RM = calculateE1RM(weight: weight, reps: reps)
        
        // Record to unified lift history (program-agnostic)
        let record = LiftRecord(
            liftName: lift,
            weight: weight,
            reps: reps,
            estimatedOneRM: newE1RM,
            programId: userData.selectedProgram,
            week: week,
            setType: "volume"
        )
        
        // Check if this is a new PR (before recording, to get previous value)
        let previousPR = userData.personalRecords[lift]
        let previousE1RM = previousPR?.estimatedOneRM
        
        // Record to history (this also updates PR if applicable)
        userData.recordLift(record)
        
        let isNewPR = previousE1RM == nil || newE1RM > (previousE1RM ?? 0)
        
        return LogRepsResult(
            isNewPR: isNewPR,
            newE1RM: newE1RM,
            previousE1RM: previousE1RM,
            weight: weight,
            reps: reps,
            liftName: lift
        )
    }
    
    /// Calculate estimated 1RM using Epley formula
    private func calculateE1RM(weight: Double, reps: Int) -> Double {
        return weight * (1.0 + Double(reps) / 30.0)
    }
    
    func getLog(lift: String, week: Int, day: Int) -> LogEntry? {
        userData.logs[lift]?[week]?[day]
    }
    
    func clearLog(lift: String, week: Int, day: Int) {
        userData.logs[lift]?[week]?[day] = nil
    }
    
    // MARK: - Weight Overrides
    
    /// Set a weight override for a lift on a specific week/day
    /// This will cascade to subsequent weeks by affecting the effective TM calculation
    func setWeightOverride(lift: String, week: Int, day: Int, weight: Double) {
        if userData.logs[lift] == nil {
            userData.logs[lift] = [:]
        }
        if userData.logs[lift]?[week] == nil {
            userData.logs[lift]?[week] = [:]
        }
        
        // Get existing log entry or create a new one
        var logEntry = userData.logs[lift]?[week]?[day] ?? LogEntry()
        logEntry.weightOverride = weight
        userData.logs[lift]?[week]?[day] = logEntry
    }
    
    /// Clear the weight override for a lift on a specific week/day
    func clearWeightOverride(lift: String, week: Int, day: Int) {
        guard var logEntry = userData.logs[lift]?[week]?[day] else { return }
        logEntry.weightOverride = nil
        
        // If the log entry is now empty (no reps, no note, no override), remove it
        if logEntry.repsLastSet == nil && logEntry.note.isEmpty && logEntry.weightOverride == nil {
            userData.logs[lift]?[week]?[day] = nil
        } else {
            userData.logs[lift]?[week]?[day] = logEntry
        }
    }
    
    /// Get the weight override for a lift on a specific week/day (if any)
    func getWeightOverride(lift: String, week: Int, day: Int) -> Double? {
        userData.logs[lift]?[week]?[day]?.weightOverride
    }
    
    /// Get the calculated (recommended) weight for a lift on a specific week
    func calculatedWeight(for lift: String, week: Int) -> Double? {
        // Use visible days for the specific week
        let weekDays = visibleDays(forWeek: week)
        guard let firstDay = weekDays.first, let plan = dayPlan(week: week, day: firstDay) else {
            // Try all visible days for this week to find this lift
            for day in weekDays {
                if let dayPlan = dayPlan(week: week, day: day) {
                    for item in dayPlan {
                        if case let .volume(_, itemLift, _, _, _, _, _, _, _, _, calculatedWeight) = item,
                           itemLift == lift {
                            return calculatedWeight
                        }
                    }
                }
            }
            return nil
        }
        
        for item in plan {
            if case let .volume(_, itemLift, _, _, _, _, _, _, _, _, calculatedWeight) = item,
               itemLift == lift {
                return calculatedWeight
            }
        }
        return nil
    }
    
    // MARK: - Accessory Logging
    
    func logAccessory(name: String, weight: Double, sets: Int, reps: Int, note: String = "") {
        userData.accessoryLogs[name] = AccessoryLog(weight: weight, sets: sets, reps: reps, note: note)
    }
    
    func getAccessoryLog(name: String) -> AccessoryLog? {
        userData.accessoryLogs[name]
    }
    
    func clearAccessoryLog(name: String) {
        userData.accessoryLogs.removeValue(forKey: name)
    }
    
    // MARK: - Structured Exercise Logging
    
    /// Log reps for a structured exercise AMRAP set
    func logStructuredReps(lift: String, week: Int, day: Int, setIndex: Int, reps: Int) {
        // Ensure nested dictionaries exist
        if userData.structuredLogs[lift] == nil {
            userData.structuredLogs[lift] = [:]
        }
        if userData.structuredLogs[lift]?[week] == nil {
            userData.structuredLogs[lift]?[week] = [:]
        }
        if userData.structuredLogs[lift]?[week]?[day] == nil {
            userData.structuredLogs[lift]?[week]?[day] = StructuredLogEntry()
        }
        userData.structuredLogs[lift]?[week]?[day]?.amrapReps[setIndex] = reps
        
        // Also update program state
        if programState?.structuredLogs[lift] == nil {
            programState?.structuredLogs[lift] = [:]
        }
        if programState?.structuredLogs[lift]?[week] == nil {
            programState?.structuredLogs[lift]?[week] = [:]
        }
        programState?.structuredLogs[lift]?[week]?[day] = userData.structuredLogs[lift]?[week]?[day]
        
        // Record to unified lift history for AMRAP sets
        // Get the weight for this set from the current plan
        if let dayPlan = currentDayPlan() {
            for item in dayPlan {
                if case let .structured(_, itemLift, _, sets, _) = item, itemLift == lift {
                    if let setInfo = sets.first(where: { $0.setIndex == setIndex }) {
                        let weight = setInfo.weight
                        let e1rm = calculateE1RM(weight: weight, reps: reps)
                        
                        // Determine set type based on target reps
                        let setType = setInfo.targetReps == 1 ? "1+" : "\(setInfo.targetReps)+"
                        
                        let record = LiftRecord(
                            liftName: lift,
                            weight: weight,
                            reps: reps,
                            estimatedOneRM: e1rm,
                            programId: userData.selectedProgram,
                            week: week,
                            setType: setType
                        )
                        userData.recordLift(record)
                    }
                    break
                }
            }
        }
    }
    
    /// Get logged reps for a structured exercise AMRAP set
    func getStructuredReps(lift: String, week: Int, day: Int, setIndex: Int) -> Int? {
        userData.structuredLogs[lift]?[week]?[day]?.amrapReps[setIndex]
    }
    
    /// Get the full structured log entry for a lift/week/day
    func getStructuredLog(lift: String, week: Int, day: Int) -> StructuredLogEntry? {
        userData.structuredLogs[lift]?[week]?[day]
    }
    
    /// Clear structured log for a lift/week/day
    func clearStructuredLog(lift: String, week: Int, day: Int) {
        userData.structuredLogs[lift]?[week]?[day] = nil
        programState?.structuredLogs[lift]?[week]?[day] = nil
    }
    
    /// Mark a structured exercise as completed (for exercises without AMRAP sets like BBB or deload weeks)
    /// This creates an empty log entry if one doesn't exist, so the day shows as completed
    func markStructuredCompleted(lift: String, week: Int, day: Int) {
        // Only create log entry if one doesn't already exist
        guard userData.structuredLogs[lift]?[week]?[day] == nil else { return }
        
        // Ensure nested dictionaries exist
        if userData.structuredLogs[lift] == nil {
            userData.structuredLogs[lift] = [:]
        }
        if userData.structuredLogs[lift]?[week] == nil {
            userData.structuredLogs[lift]?[week] = [:]
        }
        userData.structuredLogs[lift]?[week]?[day] = StructuredLogEntry()
        
        // Also update program state
        if programState?.structuredLogs[lift] == nil {
            programState?.structuredLogs[lift] = [:]
        }
        if programState?.structuredLogs[lift]?[week] == nil {
            programState?.structuredLogs[lift]?[week] = [:]
        }
        programState?.structuredLogs[lift]?[week]?[day] = userData.structuredLogs[lift]?[week]?[day]
    }
    
    // MARK: - Linear Progression Logging
    
    /// Log a linear progression session as completed (all sets/reps done)
    /// Returns LogRepsResult with PR information
    @discardableResult
    func logLinearSuccess(lift: String, week: Int, day: Int, weight: Double, reps: Int = 5, sets: Int = 5, note: String = "") -> LogRepsResult? {
        // Ensure nested dictionaries exist
        if userData.linearLogs[lift] == nil {
            userData.linearLogs[lift] = [:]
        }
        if userData.linearLogs[lift]?[week] == nil {
            userData.linearLogs[lift]?[week] = [:]
        }
        if programState?.linearLogs[lift] == nil {
            programState?.linearLogs[lift] = [:]
        }
        if programState?.linearLogs[lift]?[week] == nil {
            programState?.linearLogs[lift]?[week] = [:]
        }
        
        // When successful, we reset consecutive failures to 0
        let entry = LinearLogEntry(
            completed: true,
            consecutiveFailures: 0,
            deloadApplied: false,
            weight: weight,
            note: note
        )
        
        userData.linearLogs[lift]?[week]?[day] = entry
        programState?.linearLogs[lift]?[week]?[day] = entry
        
        // Record to unified lift history for progress tracking
        // Calculate E1RM using Epley formula: weight × (1 + reps/30)
        let e1rm = calculateE1RM(weight: weight, reps: reps)
        
        // Check if this is a new PR (before recording)
        let previousPR = userData.personalRecords[lift]
        let previousE1RM = previousPR?.estimatedOneRM
        
        let record = LiftRecord(
            liftName: lift,
            weight: weight,
            reps: reps,
            estimatedOneRM: e1rm,
            programId: userData.selectedProgram,
            week: week,
            setType: "\(sets)×\(reps)"
        )
        userData.recordLift(record)
        
        // Update training max for linear programs
        // For linear progression, the working weight IS the effective "training max"
        // On success, next session will be higher, so we store current weight as TM
        userData.trainingMaxes[lift] = weight
        
        // Check if this is a new PR
        let isNewPR = previousE1RM == nil || e1rm > (previousE1RM ?? 0)
        
        return LogRepsResult(
            isNewPR: isNewPR,
            newE1RM: e1rm,
            previousE1RM: previousE1RM,
            weight: weight,
            reps: reps,
            liftName: lift
        )
    }
    
    /// Log a linear progression session as failed (missed at least one rep)
    func logLinearFailure(lift: String, week: Int, day: Int, weight: Double, reps: Int = 5, sets: Int = 5, note: String = "") {
        // Ensure nested dictionaries exist
        if userData.linearLogs[lift] == nil {
            userData.linearLogs[lift] = [:]
        }
        if userData.linearLogs[lift]?[week] == nil {
            userData.linearLogs[lift]?[week] = [:]
        }
        if programState?.linearLogs[lift] == nil {
            programState?.linearLogs[lift] = [:]
        }
        if programState?.linearLogs[lift]?[week] == nil {
            programState?.linearLogs[lift]?[week] = [:]
        }
        
        // Get current consecutive failures from previous sessions
        let config = programState?.linearProgressionConfig ?? LinearProgressionConfig()
        let currentFailures = getCurrentLinearFailures(lift: lift, beforeWeek: week, beforeDay: day)
        let newFailures = currentFailures + 1
        let willDeload = newFailures >= config.failuresBeforeDeload
        
        let entry = LinearLogEntry(
            completed: false,
            consecutiveFailures: newFailures,
            deloadApplied: willDeload,
            weight: weight,
            note: note
        )
        
        userData.linearLogs[lift]?[week]?[day] = entry
        programState?.linearLogs[lift]?[week]?[day] = entry
        
        // Still record to lift history even on failure (shows attempted weight)
        // Use a reduced rep count to indicate it was a failed attempt
        // E1RM will be lower, reflecting the failed session
        let attemptedReps = max(1, reps - 1) // Assume they got close but missed
        let e1rm = calculateE1RM(weight: weight, reps: attemptedReps)
        let record = LiftRecord(
            liftName: lift,
            weight: weight,
            reps: attemptedReps,
            estimatedOneRM: e1rm,
            programId: userData.selectedProgram,
            week: week,
            setType: "\(sets)×\(reps) (failed)"
        )
        userData.recordLift(record)
        
        // Update training max for linear programs
        // On failure, weight stays the same (or deloads), so update TM accordingly
        if willDeload {
            // Calculate deloaded weight
            let deloadedWeight = roundWeight(weight * (1.0 - config.deloadPercentage))
            userData.trainingMaxes[lift] = deloadedWeight
        } else {
            // No deload, TM stays at current weight
            userData.trainingMaxes[lift] = weight
        }
    }
    
    /// Get current consecutive failure count for a lift by searching all previous sessions
    private func getCurrentLinearFailures(lift: String, beforeWeek: Int, beforeDay: Int) -> Int {
        guard let liftLogs = userData.linearLogs[lift] else { return 0 }
        
        // Collect all logs and sort by (week, day) descending
        var allLogs: [(week: Int, day: Int, entry: LinearLogEntry)] = []
        for (week, dayLogs) in liftLogs {
            for (day, entry) in dayLogs {
                // Only include logs before the current session
                if week < beforeWeek || (week == beforeWeek && day < beforeDay) {
                    allLogs.append((week, day, entry))
                }
            }
        }
        
        // Sort by week desc, then day desc to get most recent first
        allLogs.sort { ($0.week, $0.day) > ($1.week, $1.day) }
        
        // Get most recent log
        if let mostRecent = allLogs.first {
            if mostRecent.entry.completed {
                return 0  // Success resets the count
            } else {
                return mostRecent.entry.consecutiveFailures
            }
        }
        
        return 0  // No logs, start at 0
    }
    
    /// Get the linear progression log for a lift/week/day
    func getLinearLog(lift: String, week: Int, day: Int) -> LinearLogEntry? {
        userData.linearLogs[lift]?[week]?[day]
    }
    
    /// Clear linear progression log for a lift/week/day
    func clearLinearLog(lift: String, week: Int, day: Int) {
        userData.linearLogs[lift]?[week]?[day] = nil
        programState?.linearLogs[lift]?[week]?[day] = nil
    }
    
    /// Check if a linear lift is at risk of deload (consecutive failures approaching threshold)
    func isLinearDeloadWarning(lift: String, week: Int, day: Int) -> Bool {
        guard let config = programState?.linearProgressionConfig else { return false }
        let currentFailures = getCurrentLinearFailures(lift: lift, beforeWeek: week, beforeDay: day + 1)
        return currentFailures == config.failuresBeforeDeload - 1
    }
    
    /// Check if a linear lift will deload if failed again
    func willLinearDeloadOnFailure(lift: String, week: Int, day: Int) -> Bool {
        guard let config = programState?.linearProgressionConfig else { return false }
        let currentFailures = getCurrentLinearFailures(lift: lift, beforeWeek: week, beforeDay: day + 1)
        return currentFailures >= config.failuresBeforeDeload - 1
    }
    
    func isWeekLogged(_ week: Int) -> Bool {
        // Check if any lift has a log for this week (any day)
        for (_, weekLogs) in userData.logs {
            if let dayLogs = weekLogs[week] {
                for (_, entry) in dayLogs {
                    if entry.repsLastSet != nil {
                        return true
                    }
                }
            }
        }
        // Also check structured and linear logs
        for (_, weekLogs) in userData.structuredLogs {
            if let dayLogs = weekLogs[week] {
                for (_, entry) in dayLogs {
                    if !entry.amrapReps.isEmpty {
                        return true
                    }
                }
            }
        }
        for (_, weekLogs) in userData.linearLogs {
            if let dayLogs = weekLogs[week], !dayLogs.isEmpty {
                return true
            }
        }
        return false
    }
    
    func isDayLogged(week: Int, day: Int) -> Bool {
        guard let plan = dayPlan(week: week, day: day) else { return false }
        
        // Get all trackable lifts for this day (volume, linear, structured)
        var trackableLifts: [(lift: String, type: String)] = []
        
        for item in plan {
            switch item {
            case .volume(_, let lift, _, _, _, _, _, _, _, _, _):
                trackableLifts.append((lift, "volume"))
            case .linear(_, let info):
                trackableLifts.append((info.lift, "linear"))
            case .structured(_, let lift, _, _, _):
                trackableLifts.append((lift, "structured"))
            default:
                break
            }
        }
        
        // Check if all trackable lifts have logs
        guard !trackableLifts.isEmpty else { return false }
        
        return trackableLifts.allSatisfy { item in
            switch item.type {
            case "volume":
                return userData.logs[item.lift]?[week]?[day]?.repsLastSet != nil
            case "linear":
                return userData.linearLogs[item.lift]?[week]?[day] != nil
            case "structured":
                return userData.structuredLogs[item.lift]?[week]?[day] != nil
            default:
                return false
            }
        }
    }
    
    func dayLogStatus(week: Int, day: Int) -> DayLogStatus {
        guard let plan = dayPlan(week: week, day: day) else { return .notStarted }
        
        // Get all trackable lifts for this day (volume, linear, structured)
        var trackableLifts: [(lift: String, type: String)] = []
        
        for item in plan {
            switch item {
            case .volume(_, let lift, _, _, _, _, _, _, _, _, _):
                trackableLifts.append((lift, "volume"))
            case .linear(_, let info):
                trackableLifts.append((info.lift, "linear"))
            case .structured(_, let lift, _, _, _):
                trackableLifts.append((lift, "structured"))
            default:
                break
            }
        }
        
        guard !trackableLifts.isEmpty else { return .notStarted }
        
        let loggedCount = trackableLifts.filter { item in
            switch item.type {
            case "volume":
                return userData.logs[item.lift]?[week]?[day]?.repsLastSet != nil
            case "linear":
                return userData.linearLogs[item.lift]?[week]?[day] != nil
            case "structured":
                return userData.structuredLogs[item.lift]?[week]?[day] != nil
            default:
                return false
            }
        }.count
        
        if loggedCount == 0 {
            return .notStarted
        } else if loggedCount == trackableLifts.count {
            return .complete
        } else {
            return .partial
        }
    }
    
    /// Returns the fraction of workouts completed for a given week (0.0 to 1.0)
    /// Based on how many days have all their volume lifts logged
    func weekCompletionFraction(for week: Int) -> Double {
        // Use visible days for the SPECIFIC week, not the currently selected week
        let weekDays = visibleDays(forWeek: week)
        var completedDays = 0
        let totalDays = weekDays.count
        
        for day in weekDays {
            if dayLogStatus(week: week, day: day) == .complete {
                completedDays += 1
            }
        }
        
        guard totalDays > 0 else { return 0.0 }
        return Double(completedDays) / Double(totalDays)
    }
    
    // MARK: - Initial TM Management
    
    func initialMax(for lift: String) -> Double {
        userData.customInitialMaxes[lift] ?? programData?.initialMaxes[lift] ?? 0
    }
    
    func setInitialMax(for lift: String, value: Double) {
        userData.customInitialMaxes[lift] = value
        // Update program state
        programState?.initialMaxes[lift] = value
    }
    
    func resetInitialMax(for lift: String) {
        userData.customInitialMaxes.removeValue(forKey: lift)
        if let defaultMax = programData?.initialMaxes[lift] {
            programState?.initialMaxes[lift] = defaultMax
        }
    }
    
    // MARK: - Day Info
    
    func dayTitle(day: Int) -> String {
        // Check for explicit day title from program data
        if let explicitTitle = programData?.dayTitles?[String(day)] {
            return explicitTitle
        }
        
        guard let plan = dayPlan(week: 1, day: day) else { return "Day \(day)" }
        
        // Get the first TM item's lift name as the "main" lift
        for item in plan {
            if case .tm(_, let lift, _, _) = item {
                return "\(lift) Day"
            }
        }
        
        // For linear programs, use the first lift's name
        for item in plan {
            if case .linear(_, let info) = item {
                return "\(info.lift) Day"
            }
        }
        
        return "Day \(day)"
    }
    
    func dayLifts(day: Int) -> [String] {
        guard let plan = dayPlan(week: 1, day: day) else { return [] }
        
        var lifts: [String] = []
        for item in plan {
            if case .tm(_, let lift, _, _) = item {
                lifts.append(lift)
            }
        }
        return lifts
    }
    
    // MARK: - Exercise Customization
    
    /// Get the day items for a specific day (custom or default)
    func dayItems(for day: Int) -> [DayItem] {
        // Check for custom configuration first
        if let customItems = userData.customDays[day] {
            return customItems
        }
        // Fall back to program config
        return programState?.days[day] ?? []
    }
    
    /// Get default day items from program config
    func defaultDayItems(for day: Int) -> [DayItem] {
        programState?.days[day] ?? []
    }
    
    /// Check if a day has custom exercises
    func hasCustomExercises(for day: Int) -> Bool {
        userData.customDays[day] != nil
    }
    
    /// Set custom exercises for a day
    /// For programs with day variants (like Greyskull A/B), accessories are synced across all days of the same variant
    func setDayItems(for day: Int, items: [DayItem]) {
        // Get all days that share the same variant (same day_title)
        let variantDays = daysWithSameVariant(as: day)
        
        // Separate accessories from main lifts
        let accessories = items.filter { $0.type == .accessory }
        let mainItems = items.filter { $0.type != .accessory }
        
        // Set the full items for the primary day (including any main lift changes)
        userData.customDays[day] = items
        programState?.days[day] = items
        
        // For other variant days, sync only the accessories (keep their own main lifts)
        for variantDay in variantDays where variantDay != day {
            // Get the current items for this variant day (custom or default)
            var dayItems: [DayItem]
            if let customItems = userData.customDays[variantDay] {
                // Already has customizations - keep main lifts, replace accessories
                dayItems = customItems.filter { $0.type != .accessory }
            } else {
                // Use default items
                dayItems = programData?.days[String(variantDay)] ?? []
            }
            
            // Add the synced accessories
            dayItems.append(contentsOf: accessories)
            
            userData.customDays[variantDay] = dayItems
            programState?.days[variantDay] = dayItems
        }
    }
    
    /// Get all days that share the same variant (day_title) as the given day
    func daysWithSameVariant(as day: Int) -> [Int] {
        guard let dayTitles = programData?.dayTitles,
              let thisTitle = dayTitles[String(day)] else {
            return [day]
        }
        
        // Find all days with the same title
        var matchingDays: [Int] = []
        for (dayStr, title) in dayTitles {
            if title == thisTitle, let dayNum = Int(dayStr) {
                matchingDays.append(dayNum)
            }
        }
        
        return matchingDays.sorted()
    }
    
    /// Reset a day to default exercises
    /// For programs with day variants, this also resets accessories on all days of the same variant
    func resetDayItems(for day: Int) {
        // Get all days that share the same variant
        let variantDays = daysWithSameVariant(as: day)
        
        for variantDay in variantDays {
            userData.customDays.removeValue(forKey: variantDay)
            // Restore from program data
            if let defaultItems = programData?.days[String(variantDay)] {
                programState?.days[variantDay] = defaultItems
            }
        }
    }
    
    /// Get all available lifts (for swapping main lifts)
    var availableLifts: [String] {
        var lifts = Set<String>()
        
        // Add lifts from the lifts dictionary (SBS-style programs)
        if let liftKeys = programData?.lifts.keys {
            lifts.formUnion(liftKeys)
        }
        
        // Also get lifts from day items (for programs that define lifts in day items)
        if let state = programState {
            for (_, items) in state.days {
                for item in items {
                    if let lift = item.lift {
                        lifts.insert(lift)
                    }
                }
            }
        }
        
        return lifts.sorted()
    }
    
    /// Add an accessory to a day
    func addAccessory(to day: Int, name: String) {
        var items = dayItems(for: day)
        items.append(DayItem(type: .accessory, lift: nil, name: name))
        setDayItems(for: day, items: items)
    }
    
    /// Remove an item at index from a day
    func removeItem(from day: Int, at index: Int) {
        var items = dayItems(for: day)
        guard index < items.count else { return }
        items.remove(at: index)
        setDayItems(for: day, items: items)
    }
    
    /// Update an accessory name
    func updateAccessory(day: Int, at index: Int, newName: String) {
        var items = dayItems(for: day)
        guard index < items.count, items[index].type == .accessory else { return }
        items[index] = DayItem(type: .accessory, lift: nil, name: newName)
        setDayItems(for: day, items: items)
    }
    
    /// Swap a main lift (tm + volume pair) for another available lift
    func swapMainLift(day: Int, oldLift: String, newLift: String) {
        var items = dayItems(for: day)
        
        // Find and replace both TM and volume items for this lift
        for i in items.indices {
            if items[i].lift == oldLift {
                let type = items[i].type
                let newName = type == .tm ? "\(newLift) TM" : newLift
                items[i] = DayItem(type: type, lift: newLift, name: newName)
            }
        }
        
        setDayItems(for: day, items: items)
        
        // Also ensure the new lift has an initial max if not set
        if userData.customInitialMaxes[newLift] == nil,
           let defaultMax = programData?.initialMaxes[newLift] {
            programState?.initialMaxes[newLift] = defaultMax
        }
    }
    
    // MARK: - Persistence Helpers
    
    private func persistSettings() {
        try? persistence.saveSettings(settings)
    }
    
    private func persistUserData() {
        try? persistence.saveUserData(userData)
    }
    
    // MARK: - Export/Import
    
    func exportData() throws -> Data {
        try persistence.exportUserDataJSON()
    }
    
    func importData(_ data: Data) throws {
        try persistence.importUserDataJSON(data)
        self.userData = persistence.loadUserData()
    }
    
    // MARK: - Reset
    
    func resetLogs() {
        userData.logs = [:]
        userData.structuredLogs = [:]
        userData.linearLogs = [:]
        userData.accessoryLogs = [:]
        userData.cycleHistory = []
        userData.currentCycleStartDate = Date()
        settings.currentWeek = 1
        settings.currentDay = 1
    }
    
    func resetAll() {
        persistence.resetEverything()
        settings = .default
        userData = .empty
    }
    
    // MARK: - Cycle Management
    
    /// Get the current cycle number (1-indexed)
    var currentCycleNumber: Int {
        userData.cycleHistory.count + 1
    }
    
    /// Get cycle history sorted by most recent first
    var cycleHistory: [CompletedCycle] {
        userData.cycleHistory.sorted { $0.endDate > $1.endDate }
    }
    
    /// Calculate the final training maxes for the current week
    /// This uses the TM calculation engine to get the TMs after all logged adjustments
    /// Handles SBS, structured (531/nSuns/Greyskull), and linear (Starting Strength/StrongLifts) programs
    func finalTrainingMaxes(atWeek week: Int) -> [String: Double] {
        guard let state = programState else { return [:] }
        
        // Sync all log types
        state.logs = userData.logs
        state.structuredLogs = userData.structuredLogs
        state.linearLogs = userData.linearLogs
        
        // Sync custom initial maxes
        for (liftName, max) in userData.customInitialMaxes {
            state.initialMaxes[liftName] = max
        }
        
        var result: [String: Double] = [:]
        
        for lift in liftNames {
            // Use allTrainingMaxes which already handles all program types correctly
            let tmData = allTrainingMaxes(for: lift)
            if let lastTM = tmData.filter({ $0.week <= week }).max(by: { $0.week < $1.week }) {
                result[lift] = lastTM.tm
            } else if let initial = userData.customInitialMaxes[lift] ?? state.initialMaxes[lift] {
                // Fallback to initial max if no logged data yet
                result[lift] = initial
            }
        }
        
        return result
    }
    
    /// Get the starting maxes for the current cycle
    func currentCycleStartingMaxes() -> [String: Double] {
        var maxes: [String: Double] = [:]
        for lift in liftNames {
            maxes[lift] = initialMax(for: lift)
        }
        return maxes
    }
    
    /// Find the highest week that has any logged data (checks all log types)
    func highestLoggedWeek() -> Int {
        var maxWeek = 1
        
        // Check SBS-style logs [lift][week][day]
        for (_, weekLogs) in userData.logs {
            for (week, dayLogs) in weekLogs {
                for (_, entry) in dayLogs {
                    if entry.repsLastSet != nil && week > maxWeek {
                        maxWeek = week
                    }
                }
            }
        }
        
        // Check structured logs (for nSuns-style programs) [lift][week][day]
        for (_, weekLogs) in userData.structuredLogs {
            for (week, dayLogs) in weekLogs {
                for (_, entry) in dayLogs {
                    if !entry.amrapReps.isEmpty && week > maxWeek {
                        maxWeek = week
                    }
                }
            }
        }
        
        // Check linear logs (for Starting Strength/StrongLifts-style programs) [lift][week][day]
        for (_, weekLogs) in userData.linearLogs {
            for (week, dayLogs) in weekLogs {
                if !dayLogs.isEmpty && week > maxWeek {
                    maxWeek = week
                }
            }
        }
        
        return maxWeek
    }
    
    /// Check if the current cycle has any logged data (checks all log types)
    var hasLoggedData: Bool {
        // Check SBS-style logs [lift][week][day]
        for (_, weekLogs) in userData.logs {
            for (_, dayLogs) in weekLogs {
                for (_, entry) in dayLogs {
                    if entry.repsLastSet != nil {
                        return true
                    }
                }
            }
        }
        
        // Check structured logs (for nSuns-style programs) [lift][week][day]
        for (_, weekLogs) in userData.structuredLogs {
            for (_, dayLogs) in weekLogs {
                for (_, entry) in dayLogs {
                    if !entry.amrapReps.isEmpty {
                        return true
                    }
                }
            }
        }
        
        // Check linear logs (for Starting Strength/StrongLifts-style programs) [lift][week][day]
        if !userData.linearLogs.isEmpty {
            for (_, weekLogs) in userData.linearLogs {
                for (_, dayLogs) in weekLogs {
                    if !dayLogs.isEmpty {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// Build a completed cycle record with all necessary data for history reconstruction
    private func buildCompletedCycle(lastWeek: Int, startingMaxes: [String: Double], endingMaxes: [String: Double]) -> CompletedCycle {
        // Build TM history for each lift at each week
        var tmHistory: [String: [Int: Double]] = [:]
        var liftData: [String: [Int: CompletedCycle.LiftWeekData]] = [:]
        
        for lift in liftNames {
            tmHistory[lift] = [:]
            liftData[lift] = [:]
            
            // Get all TM data for this lift
            let tmData = allTrainingMaxes(for: lift)
            for (week, tm) in tmData {
                tmHistory[lift]?[week] = tm
            }
            
            // Get E1RM/weight data for this lift
            let e1rmData = estimatedOneRepMaxes(for: lift)
            for item in e1rmData {
                // Get target reps based on program type
                var targetReps = 5 // default
                if let state = programState {
                    // SBS-style: get from lifts dictionary
                    if let weekData = state.lifts[lift]?[item.week] {
                        targetReps = weekData.repOutTarget
                    }
                    // Structured: get from setsDetail AMRAP set
                    else if let dayItem = state.days.values.flatMap({ $0 }).first(where: { $0.lift == lift && $0.type == .structured }) {
                        // Get sets detail (prefer week-specific, fall back to static)
                        let setsDetail = dayItem.setsDetailByWeek?[String(item.week)] ?? dayItem.setsDetail
                        if let amrapSet = setsDetail?.first(where: { $0.isAMRAP }) {
                            targetReps = amrapSet.reps
                        }
                    }
                    // Linear: get from item.reps
                    else if let dayItem = state.days.values.flatMap({ $0 }).first(where: { $0.lift == lift && $0.type == .linear }) {
                        targetReps = dayItem.reps ?? 5
                    }
                }
                
                liftData[lift]?[item.week] = CompletedCycle.LiftWeekData(
                    weight: item.weight,
                    reps: item.reps,
                    e1rm: item.e1rm,
                    targetReps: targetReps
                )
            }
        }
        
        return CompletedCycle(
            cycleNumber: currentCycleNumber,
            startDate: userData.currentCycleStartDate,
            endDate: Date(),
            startingMaxes: startingMaxes,
            endingMaxes: endingMaxes,
            logs: userData.logs,
            accessoryLogs: userData.accessoryLogs,
            lastCompletedWeek: lastWeek,
            programId: userData.selectedProgram,
            programName: programData?.displayName ?? programData?.name,
            structuredLogs: userData.structuredLogs,
            linearLogs: userData.linearLogs,
            tmHistory: tmHistory,
            liftData: liftData
        )
    }
    
    /// Start a new training cycle
    /// - Parameter carryOverTMs: If true, use current calculated TMs as starting point for next cycle
    func startNewCycle(carryOverTMs: Bool = true) {
        let lastWeek = highestLoggedWeek()
        
        // Calculate ending TMs before we clear anything
        let endingMaxes = finalTrainingMaxes(atWeek: lastWeek)
        let startingMaxes = currentCycleStartingMaxes()
        
        // Archive current cycle if there's any logged data
        if hasLoggedData {
            let completedCycle = buildCompletedCycle(
                lastWeek: lastWeek,
                startingMaxes: startingMaxes,
                endingMaxes: endingMaxes
            )
            userData.cycleHistory.append(completedCycle)
        }
        
        // Set new starting maxes if carrying over TMs
        if carryOverTMs && !endingMaxes.isEmpty {
            for (lift, tm) in endingMaxes {
                userData.customInitialMaxes[lift] = tm
                programState?.initialMaxes[lift] = tm
            }
        }
        
        // Clear current cycle logs (all log types)
        userData.logs = [:]
        userData.structuredLogs = [:]
        userData.linearLogs = [:]
        userData.accessoryLogs = [:]
        
        // Reset to week 1, day 1
        settings.currentWeek = 1
        settings.currentDay = 1
        
        // Set new cycle start date
        userData.currentCycleStartDate = Date()
    }
    
    /// Delete a cycle from history
    func deleteCycle(id: UUID) {
        userData.cycleHistory.removeAll { $0.id == id }
    }
    
    // MARK: - Onboarding & Cycle Builder
    
    /// Whether the user needs to complete onboarding
    var needsOnboarding: Bool {
        !userData.hasCompletedOnboarding
    }
    
    /// Mark onboarding as complete
    func completeOnboarding() {
        userData.hasCompletedOnboarding = true
        userData.currentCycleStartDate = Date()
        
        // Ensure we start at week 1, day 1
        settings.currentWeek = 1
        settings.currentDay = 1
    }
    
    /// Get all program info for cycle builder
    var programInfo: (name: String, weeks: Int, days: Int)? {
        guard let data = programData else { return nil }
        return (data.name, data.weeks.count, data.days.count)
    }
    
    /// Get lifts used in a specific day (for cycle builder)
    func liftsInDay(_ day: Int) -> [(lift: String, type: DayItem.ItemType)] {
        let items = dayItems(for: day)
        return items.compactMap { item in
            guard let lift = item.lift else { return nil }
            return (lift, item.type)
        }
    }
    
    /// Get accessories for a specific day (for cycle builder)
    func accessoriesInDay(_ day: Int) -> [String] {
        let items = dayItems(for: day)
        return items.filter { $0.type == .accessory }.map { $0.name }
    }
    
    /// Set multiple initial maxes at once (for cycle builder)
    func setInitialMaxes(_ maxes: [String: Double]) {
        for (lift, value) in maxes {
            userData.customInitialMaxes[lift] = value
            programState?.initialMaxes[lift] = value
        }
    }
    
    /// Apply exercise customizations from cycle builder
    func applyExerciseCustomizations(_ customizations: [Int: [DayItem]]) {
        for (day, items) in customizations {
            setDayItems(for: day, items: items)
        }
    }
    
    /// Get all unique lifts across all days (all variants)
    var allConfiguredLifts: Set<String> {
        var lifts = Set<String>()
        // Use allDays to get lifts from ALL day variants, not just currently visible ones
        for day in allDays {
            let dayLifts = liftsInDay(day)
            for (lift, _) in dayLifts {
                lifts.insert(lift)
            }
        }
        return lifts
    }
    
    /// Start a new cycle with the cycle builder (more comprehensive than startNewCycle)
    /// - Parameters:
    ///   - carryOverTMs: Whether to use current TMs as starting point
    ///   - newMaxes: Optional new training maxes to set
    ///   - exerciseCustomizations: Optional exercise customizations per day
    func startNewCycleWithBuilder(
        carryOverTMs: Bool = true,
        newMaxes: [String: Double]? = nil,
        exerciseCustomizations: [Int: [DayItem]]? = nil
    ) {
        let lastWeek = highestLoggedWeek()
        
        // Calculate ending TMs before we clear anything
        let endingMaxes = finalTrainingMaxes(atWeek: lastWeek)
        let startingMaxes = currentCycleStartingMaxes()
        
        // Archive current cycle if there's any logged data
        if hasLoggedData {
            let completedCycle = buildCompletedCycle(
                lastWeek: lastWeek,
                startingMaxes: startingMaxes,
                endingMaxes: endingMaxes
            )
            userData.cycleHistory.append(completedCycle)
        }
        
        // Clear current cycle logs (all log types)
        userData.logs = [:]
        userData.structuredLogs = [:]
        userData.linearLogs = [:]
        userData.accessoryLogs = [:]
        
        // Clear old customDays and restore program defaults before applying new customizations
        userData.customDays = [:]
        if let pdata = programData {
            for (dayStr, items) in pdata.days {
                if let dayNum = Int(dayStr) {
                    programState?.days[dayNum] = items
                }
            }
        }
        
        // Apply new maxes from builder, or carry over
        if let newMaxes = newMaxes {
            setInitialMaxes(newMaxes)
        } else if carryOverTMs && !endingMaxes.isEmpty {
            for (lift, tm) in endingMaxes {
                userData.customInitialMaxes[lift] = tm
                programState?.initialMaxes[lift] = tm
            }
        }
        
        // Apply exercise customizations if provided
        if let customizations = exerciseCustomizations {
            applyExerciseCustomizations(customizations)
        }
        
        // Reset to week 1, day 1
        settings.currentWeek = 1
        settings.currentDay = 1
        
        // Set new cycle start date
        userData.currentCycleStartDate = Date()
    }
}

// MARK: - Supporting Types

public enum DayLogStatus {
    case notStarted
    case partial
    case complete
}

public enum AppError: LocalizedError {
    case configNotFound
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "Program configuration file not found in app bundle."
        case .invalidData:
            return "Failed to parse program data."
        }
    }
}

// MARK: - Extensions

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

