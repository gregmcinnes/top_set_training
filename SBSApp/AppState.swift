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
        get {
            // Clamp on read: a stale persisted week (e.g. week 15 carried into a
            // 12-week program) would make weekPlan() throw and views render empty.
            let maxWeek = programState?.weeks.max() ?? 20
            return settings.currentWeek.clamped(to: 1...maxWeek)
        }
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
        // If a previous launch preserved an undecodable blob and this build can
        // now decode it (e.g. a decoding bug was fixed), restore it first.
        persistence.restoreUserDataBackupIfDecodable()
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
    /// Set while the accessory workout screen is open, to clean up if it closes from
    /// outside. Not persisted or observed: it only bridges to that live view.
    @ObservationIgnored var activeWorkoutTeardown: (() -> Void)?

    // MARK: - Active Workout

    /// The workout in progress, on screen or minimized
    private(set) var activeSession: ActiveWorkoutSession?

    /// The session showing full screen. Nil while minimized or restored, when the
    /// resume bar stands in for it.
    private(set) var presentedSession: ActiveWorkoutSession? {
        didSet {
            let isVisible = presentedSession != nil
            RestTimerStatus.shared.isWorkoutScreenVisible = isVisible
            // Keep screen awake during workout
            UIApplication.shared.isIdleTimerDisabled = isVisible
        }
    }

    /// A restored session is old enough to ask about instead of resuming silently
    var showingStaleSessionPrompt = false

    /// Goes up when a finished workout should land on Home, from whichever tab
    private(set) var returnToHomeCount = 0

    /// The next workout from a given week, for Done and for Home's next-workout card
    func nextWorkout(fromWeek week: Int) -> (week: Int, day: Int)? {
        NextWorkout.find(
            fromWeek: week,
            weeks: weeks,
            visibleDays: { visibleDays(forWeek: $0) },
            isNotStarted: { dayLogStatus(week: $0, day: $1) == .notStarted }
        )
    }

    /// What Home's card offers next. Asks from the highest logged week, not the selected
    /// one, so browsing weeks in the strip doesn't change the answer.
    var nextWorkoutInCycle: (week: Int, day: Int)? {
        nextWorkout(fromWeek: highestLoggedWeek())
    }

    /// Nothing left to do in this cycle. Matches returnToHomeAfterWorkout, which stays on
    /// the final week when no workout is next, so the lifter always lands on the
    /// completion card, even if the last day was only partly logged.
    var isCycleComplete: Bool {
        hasLoggedData && nextWorkoutInCycle == nil
    }

    /// Days done and logged across every week of the cycle
    var cycleDayTally: CycleProgress.Tally {
        CycleProgress.tally(
            weeks: weeks,
            visibleDays: { visibleDays(forWeek: $0) },
            state: { week, day in
                switch dayLogStatus(week: week, day: day) {
                case .notStarted: return .notStarted
                case .partial: return .partial
                case .complete: return .complete
                }
            }
        )
    }

    /// Completed days over all visible days of all weeks
    var cycleCompletionFraction: Double {
        cycleDayTally.completedFraction
    }

    /// Whether this program works from training maxes. Linear programs use a weight.
    var programHasTrainingMaxes: Bool {
        CycleProgress.usesTrainingMaxes(allDays.flatMap { dayItems(for: $0) })
    }

    /// Sessions and gains for the cycle-complete card. Gains compare this cycle's start
    /// with the next one's, so a 5/3/1 lifter sees the increase they're about to get.
    func cycleCompletionSummary() -> CycleCompletionSummary {
        let liftOrder = allDays.flatMap { CycleProgress.mainLifts(in: dayItems(for: $0)) }
        return CycleCompletionSummary(
            sessionsCompleted: cycleDayTally.loggedDays,
            gains: CycleProgress.gains(
                liftOrder: liftOrder,
                starting: currentCycleStartingMaxes(),
                next: nextCycleStartingMaxes()
            ),
            usesTrainingMaxes: programHasTrainingMaxes
        )
    }

    /// A workout finished: select what's next and go to Home. With nothing left, stay on
    /// the final week so its cycle-complete card shows.
    func returnToHomeAfterWorkout(week: Int) {
        if let next = nextWorkout(fromWeek: week) {
            selectedWeek = next.week
            selectedDay = next.day
        } else if let lastWeek = weeks.max() {
            selectedWeek = lastWeek
        }
        returnToHomeCount += 1
    }

    /// Start a workout, assuming the caller has settled any session already active
    @MainActor
    func startWorkout(week: Int, day: Int) {
        if let activeSession, activeSession.week == week, activeSession.day == day {
            presentedSession = activeSession
            return
        }
        activeSession?.exitWorkoutWithoutSaving()

        let session = ActiveWorkoutSession(appState: self, week: week, day: day)
        guard !session.workoutState.exercises.isEmpty else {
            session.markEnded()
            Logger.error("Week \(week), day \(day) has no exercises to start", category: .general)
            return
        }
        activeSession = session
        session.activateSurfaces()
        presentedSession = session
    }

    /// Reopen the session. A restored session still waiting on the stale question gets
    /// its surfaces here too, however it's reopened.
    @MainActor
    func resumeWorkout() {
        guard let activeSession else { return }
        if activeSession.isStale { activeSession.touch() }
        activeSession.activateSurfaces()
        presentedSession = activeSession
    }

    @MainActor
    func minimizeWorkout() {
        presentedSession = nil
    }

    /// The session has finished or been abandoned: close it and forget the saved copy
    @MainActor
    func closeActiveSession(_ session: ActiveWorkoutSession) {
        session.markEnded()
        guard activeSession === session else { return }
        presentedSession = nil
        activeSession = nil
        showingStaleSessionPrompt = false
        persistence.clearActiveWorkoutSession()
    }

    func saveWorkoutSession(_ session: PersistedWorkoutSession) {
        do {
            persistence.saveActiveWorkoutSession(try JSONEncoder().encode(session))
        } catch {
            Logger.error("Failed to save workout in progress: \(error)", category: .general)
        }
    }

    /// Bring back a workout saved before the app was killed. Anything unreadable or no
    /// longer valid is dropped: it must never block launch.
    @MainActor
    func restoreActiveSessionIfNeeded() {
        guard activeSession == nil else { return }
        defer {
            if activeSession == nil {
                WatchConnectivityManager.shared.endAbandonedWorkoutIfIdle()
            }
        }
        guard let data = persistence.loadActiveWorkoutSession() else { return }

        guard let saved = PersistedWorkoutSession.decode(data),
              saved.isResumable(
                programId: userData.selectedProgram,
                cycleStartDate: userData.currentCycleStartDate
              ) else {
            Logger.error("Dropping saved workout: it's unreadable or no longer fits this cycle", category: .general)
            persistence.clearActiveWorkoutSession()
            return
        }

        let session = ActiveWorkoutSession(appState: self, restoring: saved)
        activeSession = session
        if saved.isStale() {
            showingStaleSessionPrompt = true
        } else {
            session.activateSurfaces()
        }
    }

    /// Ask about a session left untouched for too long, on a return to the app too
    @MainActor
    func promptIfActiveSessionIsStale() {
        guard let activeSession, presentedSession == nil, activeSession.isStale else { return }
        showingStaleSessionPrompt = true
    }

    /// Answer to the stale session question: carry on
    @MainActor
    func keepStaleSession() {
        resumeWorkout()
    }

    /// A cycle or program change makes the session meaningless: end it with no save
    @MainActor
    func endWorkoutForCycleChange() {
        activeWorkoutTeardown?()
        activeWorkoutTeardown = nil
        activeSession?.exitWorkoutWithoutSaving()
    }

    func discoverAvailablePrograms() async {
        // Known program files to check
        let programFiles = [
            "stronglifts_5x5_12week",
            "starting_strength_12week",
            "greyskull_lp_12week",
            "gzclp_12week",
            "gzclp_3day_12week",
            "531_bbb_12week",
            "531_fsl_12week",
            "531_triumvirate_12week",
            "nsuns_4day_12week",
            "nsuns_5day_12week",
            "nsuns_6day_squat_12week",
            "nsuns_6day_deadlift_12week",
            "phul_12week",
            "reddit_ppl_12week",
            "basic_ppl_12week",
            "back_friendly_hypertrophy_12week",
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
                    Logger.warning("Failed to parse program \(filename): \(error)", category: .program)
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
        if let selectedId = userData.selectedProgram {
            if let program = availablePrograms.first(where: { $0.id == selectedId }) {
                try await loadFromURL(program.url)
                return
            }
            // Custom templates aren't in availablePrograms — load them directly.
            if UserData.isCustomTemplate(programId: selectedId),
               let templateId = UserData.templateId(from: selectedId),
               let template = userData.template(withId: templateId) {
                let pdata = template.toProgramData()
                await MainActor.run {
                    self.applyProgramData(pdata)
                }
                return
            }
            // A selected template that no longer exists can never resolve. Drop its day
            // overlays so they aren't applied on top of the default program below. The
            // selection stays: loadProgram needs it to archive these logs on the next
            // switch, rather than merging them into the new program.
            if UserData.isCustomTemplate(programId: selectedId) {
                Logger.error("Selected template \(selectedId) no longer exists — clearing its day overlays", category: .program)
                userData.customDays = [:]
            }
            // Do NOT silently fall through: the selection is kept, but the user
            // sees the default program until the resolution problem is fixed
            // (e.g. a program JSON missing from the bundle).
            Logger.error("Selected program \(selectedId) could not be resolved (\(availablePrograms.count) programs discovered) — falling back to default", category: .program)
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

        // Resolve and decode the target program BEFORE any destructive work below,
        // so an invalid id or corrupt config can't archive/clear the current cycle.
        let pdata: ProgramData
        if UserData.isCustomTemplate(programId: programId) {
            guard let templateId = UserData.templateId(from: programId),
                  let template = userData.template(withId: templateId) else {
                throw AppError.configNotFound
            }
            pdata = template.toProgramData()
        } else {
            guard let program = availablePrograms.first(where: { $0.id == programId }) else {
                throw AppError.configNotFound
            }
            let data = try Data(contentsOf: program.url)
            pdata = try JSONDecoder().decode(ProgramData.self, from: data)
        }

        // Archive current cycle BEFORE switching programs (while we still have the old programData)
        if isSwitchingPrograms && hasLoggedData {
            let lastWeek = highestLoggedWeek()
            let endingMaxes = finalTrainingMaxes(atWeek: lastWeek)
            let startingMaxes = currentCycleStartingMaxes()
            let completedCycle = buildCompletedCycle(
                lastWeek: lastWeek,
                startingMaxes: startingMaxes,
                endingMaxes: endingMaxes
            )
            userData.cycleHistory.append(completedCycle)
            
            // Save ending TMs to universal trainingMaxes so they carry forward to new programs
            // This is critical - SBS/structured programs don't update trainingMaxes during the cycle,
            // only linear programs do. So we need to save the final calculated TMs here.
            for (lift, tm) in endingMaxes {
                userData.trainingMaxes.setCanonicalLiftValue(tm, for: lift)
            }

            // Save current customizations for the old program before switching
            if let oldProgramId = userData.selectedProgram {
                userData.saveCustomizations(for: oldProgramId)
            }

            // Clear logs since they've been archived
            userData.logs = [:]
            userData.structuredLogs = [:]
            userData.linearLogs = [:]
            // Capture date before removeAll to avoid exclusivity violation
            let cycleStartDate = userData.currentCycleStartDate
            userData.workoutRecords.removeAll { $0.date >= cycleStartDate }
            userData.currentCycleStartDate = Date()
        }

        if isSwitchingPrograms {
            // Always start a switched program at week 1, day 1 — the previous
            // position may not exist in the new program at all.
            settings.currentWeek = 1
            settings.currentDay = 1

            // Restore or clear program-specific data when switching programs
            if !userData.restoreCustomizations(for: programId) {
                userData.customDays = [:]
                userData.customInitialMaxes = [:]
                userData.accessoryLogs = [:]
            }
        }

        // Save the selection
        userData.selectedProgram = programId

        await MainActor.run {
            self.applyProgramData(pdata)
        }
    }

    /// Install decoded program data as the active program and overlay the user's
    /// logs and customizations onto the fresh state.
    @MainActor
    private func applyProgramData(_ pdata: ProgramData) {
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

            // Apply custom day configurations and copy WeekData for swapped lifts
            for (day, items) in self.userData.customDays {
                // Copy WeekData for any swapped lifts before applying
                let originalItems = pdata.days[String(day)] ?? []
                self.copyWeekDataForSwappedLifts(newItems: items, originalItems: originalItems)
                state.days[day] = items
            }

            // Apply rounding and units from settings
            state.rounding = self.settings.roundingIncrement
            state.useMetric = self.settings.useMetric
        }
    }
    
    private func loadFromURL(_ url: URL) async throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let pdata = try decoder.decode(ProgramData.self, from: data)

        await MainActor.run {
            self.applyProgramData(pdata)
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
        state.useMetric = settings.useMetric

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
        if let tm = userData.trainingMaxes.canonicalLiftValue(for: lift) {
            return tm
        }
        // Fall back to custom initial maxes (from cycle setup)
        if let tm = userData.customInitialMaxes.canonicalLiftValue(for: lift) {
            return tm
        }
        // Fall back to program defaults
        return programState?.initialMaxes.canonicalLiftValue(for: lift)
    }

    /// Set the training max for a lift (program-agnostic)
    func setTrainingMax(for lift: String, value: Double) {
        userData.trainingMaxes.setCanonicalLiftValue(value, for: lift)
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
        let canonical = ExerciseLibrary.canonicalLiftName(lift)
        return userData.liftHistory
            .filter { ExerciseLibrary.canonicalLiftName($0.liftName) == canonical }
            .sorted { $0.date < $1.date }
    }

    /// Get all-time personal record for a lift
    func personalRecord(for lift: String) -> PersonalRecord? {
        userData.personalRecords.canonicalLiftValue(for: lift)
    }
    
    /// Get all unique lifts that have been recorded
    var allRecordedLifts: [String] {
        userData.allRecordedLifts
    }
    
    /// Get E1RM progression data for charting (from unified history)
    func e1rmProgression(for lift: String) -> [(date: Date, e1rm: Double, weight: Double, reps: Int)] {
        liftHistory(for: lift).map { record in
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
                    // Use the week's last session: dictionary order is random per launch
                    if let entry = dayLogs.max(by: { $0.key < $1.key })?.value {
                        result.append((week, entry.weight)) // One entry per week for the chart
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
    /// For programs like GZCLP with multiple exercises for the same lift (T1, T2), we use the one with highest intensity
    private func getAllStructuredLiftInfo() -> [String: (setIndex: Int, intensity: Double, targetReps: Int)] {
        guard let state = programState else { return [:] }
        return engine.gatherStructuredLiftInfo(from: state)
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
                    // Use the week's last session: dictionary order is random per launch
                    if let entry = dayLogs.max(by: { $0.key < $1.key })?.value {
                        // Find the default reps for this lift
                        let defaultReps = state.days.values.flatMap { $0 }
                            .first { $0.type == .linear && $0.lift == lift }?.reps ?? 5
                        let reps = entry.completed ? defaultReps : max(1, defaultReps - 1)
                        let e1rm = calculateE1RM(weight: entry.weight, reps: reps)
                        result.append((week, e1rm, entry.weight, reps)) // One entry per week
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
            
            // Try structured-style logs - look for the primary progression set (highest intensity AMRAP)
            if let dayLogs = userData.structuredLogs[lift]?[week],
               let setInfo = structuredLiftInfo[lift] {
                // For programs like Reddit PPL where the same lift appears on multiple days,
                // search for any logged AMRAP that matches our progression criteria
                
                // First, try the exact set index
                for (_, structuredLog) in dayLogs {
                    if let reps = structuredLog.amrapReps[setInfo.setIndex] {
                        let tm = structuredTMs[week]?[lift] ?? state.initialMaxes[lift] ?? 0
                        let weight = roundWeight(tm * setInfo.intensity)
                        let e1rm = weight * (1.0 + Double(reps) / 30.0)
                        return (week, e1rm, weight, reps)
                    }
                }
                
                // Fallback: look for any AMRAP that matches the target reps
                for (day, structuredLog) in dayLogs {
                    if let dayItems = state.days[day] {
                        for item in dayItems {
                            guard item.type == .structured, item.lift == lift else { continue }
                            
                            let setsDetail = item.setsDetail ?? item.setsDetailByWeek?[String(week)] ?? []
                            for (index, setDetail) in setsDetail.enumerated() {
                                if setDetail.isAMRAP && setDetail.reps == setInfo.targetReps,
                                   let reps = structuredLog.amrapReps[index] {
                                    let tm = structuredTMs[week]?[lift] ?? state.initialMaxes[lift] ?? 0
                                    let weight = roundWeight(tm * setInfo.intensity)
                                    let e1rm = weight * (1.0 + Double(reps) / 30.0)
                                    return (week, e1rm, weight, reps)
                                }
                            }
                        }
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
    
    // MARK: - Workout Record Management
    
    /// Find or create a WorkoutRecord for the current workout session
    private func findOrCreateWorkoutRecord(week: Int, day: Int) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        
        // Find existing record for today's workout
        if let index = userData.workoutRecords.firstIndex(where: { record in
            Calendar.current.isDate(record.date, inSameDayAs: today) &&
            record.week == week &&
            record.day == day &&
            record.programId == userData.selectedProgram
        }) {
            return index
        }
        
        // Create new workout record
        let newRecord = WorkoutRecord(
            date: Date(),
            programId: userData.selectedProgram ?? "",
            programName: programData?.displayName ?? programData?.name ?? "Unknown",
            week: week,
            day: day,
            dayTitle: dayTitle(day: day)
        )
        userData.workoutRecords.append(newRecord)
        return userData.workoutRecords.count - 1
    }
    
    /// Record a completed set to the workout record
    private func recordSetToWorkout(
        lift: String,
        exerciseName: String,
        week: Int,
        day: Int,
        setNumber: Int,
        weight: Double,
        targetReps: Int,
        actualReps: Int?,
        isAMRAP: Bool,
        trainingMax: Double,
        exerciseType: WorkoutExerciseType,
        intensity: Double? = nil,
        completed: Bool = true,
        note: String? = nil
    ) {
        let workoutIndex = findOrCreateWorkoutRecord(week: week, day: day)
        
        // Find or create exercise record
        if let exerciseIndex = userData.workoutRecords[workoutIndex].exercises.firstIndex(where: { $0.lift == lift }) {
            // Update existing exercise
            let setRecord = WorkoutSetRecord(
                setNumber: setNumber,
                weight: weight,
                targetReps: targetReps,
                actualReps: actualReps,
                isAMRAP: isAMRAP,
                intensity: intensity,
                completed: completed
            )
            
            // Check if this set already exists (update) or is new (append)
            if let setIndex = userData.workoutRecords[workoutIndex].exercises[exerciseIndex].sets.firstIndex(where: { $0.setNumber == setNumber }) {
                userData.workoutRecords[workoutIndex].exercises[exerciseIndex].sets[setIndex] = setRecord
            } else {
                userData.workoutRecords[workoutIndex].exercises[exerciseIndex].sets.append(setRecord)
            }
            
            // Update note if provided
            if let note = note {
                userData.workoutRecords[workoutIndex].exercises[exerciseIndex].note = note
            }
        } else {
            // Create new exercise record
            let setRecord = WorkoutSetRecord(
                setNumber: setNumber,
                weight: weight,
                targetReps: targetReps,
                actualReps: actualReps,
                isAMRAP: isAMRAP,
                intensity: intensity,
                completed: completed
            )
            
            let exerciseRecord = WorkoutExerciseRecord(
                lift: lift,
                exerciseName: exerciseName,
                trainingMax: trainingMax,
                exerciseType: exerciseType,
                sets: [setRecord],
                note: note
            )
            
            userData.workoutRecords[workoutIndex].exercises.append(exerciseRecord)
        }
        
        persistUserData()
    }
    
    /// Get workout records for the current cycle (since cycle start date)
    func currentCycleWorkoutRecords() -> [WorkoutRecord] {
        userData.workoutRecords.filter { $0.date >= userData.currentCycleStartDate }
    }
    
    /// Get workout records for a specific lift in the current cycle
    func workoutRecords(for lift: String) -> [WorkoutExerciseRecord] {
        currentCycleWorkoutRecords().flatMap { workout in
            workout.exercises.filter { $0.lift == lift }
        }
    }
    
    // MARK: - Logging
    
    /// Result of logging reps - includes PR information
    struct LogRepsResult: Identifiable {
        let id = UUID()
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
        let existingEntry = userData.logs[lift]?[week]?[day]
        let existingOverride = existingEntry?.weightOverride
        userData.logs[lift]?[week]?[day] = LogEntry(
            repsLastSet: reps,
            note: note,
            weightOverride: existingOverride,
            overrideItemName: existingEntry?.overrideItemName
        )
        
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
            liftName: ExerciseLibrary.canonicalLiftName(lift),
            weight: weight,
            reps: reps,
            estimatedOneRM: newE1RM,
            programId: userData.selectedProgram,
            week: week,
            setType: "volume",
            day: day
        )

        // A re-log replaces the earlier entry, including any PR it set
        removeLiftRecords(lift: lift, week: week, day: day, setType: "volume")
        removeWorkoutSets(lift: lift, week: week, day: day, setNumber: weekData.sets)

        // Check if this is a new PR (before recording, to get previous value)
        let previousPR = userData.personalRecords.canonicalLiftValue(for: lift)
        let previousE1RM = previousPR?.estimatedOneRM
        
        // Record to history (this also updates PR if applicable)
        userData.recordLift(record)
        
        // Record to WorkoutRecords (new self-contained history system)
        let sets = weekData.sets
        recordSetToWorkout(
            lift: lift,
            exerciseName: lift,
            week: week,
            day: day,
            setNumber: sets, // Last set is the rep-out set
            weight: weight,
            targetReps: weekData.repOutTarget,
            actualReps: reps,
            isAMRAP: true,
            trainingMax: tm,
            exerciseType: .volume,
            intensity: weekData.intensity,
            completed: true,
            note: note.isEmpty ? nil : note
        )
        
        let isNewPR = E1RM.isNewPR(newE1RM: newE1RM, previousE1RM: previousE1RM)
        
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
        return E1RM.epley(weight: weight, reps: reps)
    }
    
    func getLog(lift: String, week: Int, day: Int) -> LogEntry? {
        userData.logs[lift]?[week]?[day]
    }
    
    func clearLog(lift: String, week: Int, day: Int) {
        userData.logs[lift]?[week]?[day] = nil
        removeLiftRecords(lift: lift, week: week, day: day)
        removeWorkoutSets(lift: lift, week: week, day: day)
    }

    /// Remove this cycle's history records for a session, recomputing the PR if one of
    /// them held it. Otherwise a mistyped rep count would stay the PR permanently.
    /// Records saved before `LiftRecord.day` existed can't be matched and are left alone.
    private func removeLiftRecords(lift: String, week: Int, day: Int, setType: String? = nil, setIndex: Int? = nil) {
        userData.removeLiftRecords(
            liftName: ExerciseLibrary.canonicalLiftName(lift),
            programId: userData.selectedProgram,
            week: week,
            day: day,
            setType: setType,
            setIndex: setIndex,
            since: userData.currentCycleStartDate
        )
    }

    /// Remove this cycle's workout-history sets for a session (nil setNumber: all of them)
    private func removeWorkoutSets(lift: String, week: Int, day: Int, setNumber: Int? = nil) {
        userData.removeWorkoutSets(
            lift: lift,
            programId: userData.selectedProgram,
            week: week,
            day: day,
            setNumber: setNumber,
            since: userData.currentCycleStartDate
        )
    }
    
    // MARK: - Weight Overrides
    
    /// Set a weight override for a lift on a specific week/day
    /// This will cascade to subsequent weeks by affecting the effective TM calculation
    /// `itemName` is the exercise it was set on, for days that list a lift twice (5/3/1 FSL)
    func setWeightOverride(lift: String, week: Int, day: Int, weight: Double, itemName: String? = nil) {
        if userData.logs[lift] == nil {
            userData.logs[lift] = [:]
        }
        if userData.logs[lift]?[week] == nil {
            userData.logs[lift]?[week] = [:]
        }
        
        // Get existing log entry or create a new one
        var logEntry = userData.logs[lift]?[week]?[day] ?? LogEntry()
        logEntry.weightOverride = weight
        logEntry.overrideItemName = itemName
        userData.logs[lift]?[week]?[day] = logEntry
    }
    
    /// Clear the weight override for a lift on a specific week/day
    func clearWeightOverride(lift: String, week: Int, day: Int) {
        guard var logEntry = userData.logs[lift]?[week]?[day] else { return }
        logEntry.weightOverride = nil
        logEntry.overrideItemName = nil
        
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
    
    /// The override affecting one exercise. A day listing a lift twice shares one log
    /// entry, so an override on the main work must not read as set on the FSL back-off.
    func weightOverride(forExercise name: String, lift: String, week: Int, day: Int) -> Double? {
        guard let override = getWeightOverride(lift: lift, week: week, day: day) else { return nil }
        for item in dayPlan(week: week, day: day) ?? [] {
            if case let .structured(itemName, itemLift, _, sets, _) = item, itemLift == lift, itemName == name {
                return sets.contains { $0.weight != $0.calculatedWeight } ? override : nil
            }
        }
        return override
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
    
    func logAccessory(name: String, weight: Double, sets: Int, reps: Int, note: String = "", wasEasy: Bool? = nil) {
        userData.accessoryLogs[name] = AccessoryLog(weight: weight, sets: sets, reps: reps, note: note, wasEasy: wasEasy)

        // Also append to time-series accessoryHistory for the volume-by-body-part view.
        // Body part comes from the library; unknown names (custom exercises) get nil
        // and bucket as "Other" in the volume card.
        let record = AccessoryRecord(
            date: Date(),
            name: name,
            bodyPart: ExerciseLibrary.shared.bodyPart(for: name),
            weight: weight,
            sets: sets,
            reps: reps,
            note: note
        )
        userData.accessoryHistory.append(record)
    }
    
    func getAccessoryLog(name: String) -> AccessoryLog? {
        userData.accessoryLogs[name]
    }

    /// Update only the wasEasy flag on an existing accessory log, preserving
    /// weight/sets/reps/note and without appending to accessoryHistory.
    func setAccessoryWasEasy(name: String, wasEasy: Bool?) {
        guard var log = userData.accessoryLogs[name] else { return }
        log.wasEasy = wasEasy
        userData.accessoryLogs[name] = log
    }
    
    func clearAccessoryLog(name: String) {
        userData.accessoryLogs.removeValue(forKey: name)
    }
    
    // MARK: - Structured Exercise Logging
    
    /// Log reps for a structured exercise AMRAP set
    /// Log reps for a structured (nSuns/GZCLP) AMRAP set and check for a new PR.
    @discardableResult
    func logStructuredReps(lift: String, week: Int, day: Int, setIndex: Int, reps: Int, note: String = "") -> LogRepsResult? {
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
        if !note.isEmpty {
            userData.structuredLogs[lift]?[week]?[day]?.note = note
        }
        
        // Also update program state
        if programState?.structuredLogs[lift] == nil {
            programState?.structuredLogs[lift] = [:]
        }
        if programState?.structuredLogs[lift]?[week] == nil {
            programState?.structuredLogs[lift]?[week] = [:]
        }
        programState?.structuredLogs[lift]?[week]?[day] = userData.structuredLogs[lift]?[week]?[day]
        
        // Record to unified lift history for AMRAP sets
        // Get the weight for this set from the plan for the logged week/day
        // (includes any manual weight override, so the E1RM/PR uses what was lifted)
        if let dayPlan = self.dayPlan(week: week, day: day) {
            for item in dayPlan {
                if case let .structured(name, itemLift, _, sets, _) = item, itemLift == lift {
                    // A day can list the lift twice (5/3/1 main + FSL): the AMRAP set
                    // belongs to whichever item actually defines one at this index.
                    if let setInfo = sets.first(where: { $0.setIndex == setIndex && $0.isAMRAP }) {
                        let weight = setInfo.weight
                        let e1rm = calculateE1RM(weight: weight, reps: reps)

                        // Determine set type based on target reps
                        let setType = setInfo.targetReps == 1 ? "1+" : "\(setInfo.targetReps)+"

                        let record = LiftRecord(
                            liftName: ExerciseLibrary.canonicalLiftName(lift),
                            weight: weight,
                            reps: reps,
                            estimatedOneRM: e1rm,
                            programId: userData.selectedProgram,
                            week: week,
                            setType: setType,
                            day: day,
                            setIndex: setIndex
                        )

                        // A re-log replaces this set's earlier entry, including any PR it set
                        removeLiftRecords(lift: lift, week: week, day: day, setIndex: setIndex)
                        removeWorkoutSets(lift: lift, week: week, day: day, setNumber: setIndex)

                        // Check if this is a new PR (before recording, to get previous value)
                        let previousE1RM = userData.personalRecords.canonicalLiftValue(for: lift)?.estimatedOneRM

                        userData.recordLift(record)

                        // Record to WorkoutRecords (new self-contained history system)
                        let currentTM = trainingMax(for: lift, week: week) ?? (userData.customInitialMaxes[lift] ?? 0)
                        recordSetToWorkout(
                            lift: lift,
                            exerciseName: name,
                            week: week,
                            day: day,
                            setNumber: setIndex,
                            weight: weight,
                            targetReps: setInfo.targetReps,
                            actualReps: reps,
                            isAMRAP: setInfo.isAMRAP,
                            trainingMax: currentTM,
                            exerciseType: .structured,
                            intensity: setInfo.intensity,
                            completed: true,
                            note: note.isEmpty ? nil : note
                        )

                        let isNewPR = E1RM.isNewPR(newE1RM: e1rm, previousE1RM: previousE1RM)

                        return LogRepsResult(
                            isNewPR: isNewPR,
                            newE1RM: e1rm,
                            previousE1RM: previousE1RM,
                            weight: weight,
                            reps: reps,
                            liftName: lift
                        )
                    }
                }
            }
        }
        return nil
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
        removeLiftRecords(lift: lift, week: week, day: day)
        removeWorkoutSets(lift: lift, week: week, day: day)
    }

    /// Clear one AMRAP set's reps, leaving the day's other logged sets in place
    func clearStructuredSet(lift: String, week: Int, day: Int, setIndex: Int) {
        guard var entry = userData.structuredLogs[lift]?[week]?[day] else { return }
        entry.amrapReps[setIndex] = nil
        if entry.amrapReps.isEmpty {
            clearStructuredLog(lift: lift, week: week, day: day)
            return
        }
        userData.structuredLogs[lift]?[week]?[day] = entry
        programState?.structuredLogs[lift]?[week]?[day] = entry

        removeLiftRecords(lift: lift, week: week, day: day, setIndex: setIndex)
        removeWorkoutSets(lift: lift, week: week, day: day, setNumber: setIndex)
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
            note: note,
            usesUnroundedReplay: true
        )
        
        userData.linearLogs[lift]?[week]?[day] = entry
        programState?.linearLogs[lift]?[week]?[day] = entry

        // A re-log replaces the earlier result, including any PR it set
        removeLiftRecords(lift: lift, week: week, day: day)
        removeWorkoutSets(lift: lift, week: week, day: day)
        
        // Record to unified lift history for progress tracking
        // Calculate E1RM using Epley formula: weight × (1 + reps/30)
        let e1rm = calculateE1RM(weight: weight, reps: reps)
        
        // Check if this is a new PR (before recording)
        let previousPR = userData.personalRecords.canonicalLiftValue(for: lift)
        let previousE1RM = previousPR?.estimatedOneRM

        let record = LiftRecord(
            liftName: ExerciseLibrary.canonicalLiftName(lift),
            weight: weight,
            reps: reps,
            estimatedOneRM: e1rm,
            programId: userData.selectedProgram,
            week: week,
            setType: "\(sets)×\(reps)",
            day: day
        )
        userData.recordLift(record)
        
        // Record to WorkoutRecords (new self-contained history system)
        // For linear programs, record all sets as completed
        for setNum in 1...sets {
            recordSetToWorkout(
                lift: lift,
                exerciseName: lift,
                week: week,
                day: day,
                setNumber: setNum,
                weight: weight,
                targetReps: reps,
                actualReps: reps,
                isAMRAP: false,
                trainingMax: weight, // For linear progression, working weight IS the TM
                exerciseType: .linear,
                completed: true,
                note: setNum == sets ? (note.isEmpty ? nil : note) : nil
            )
        }
        
        // Update training max for linear programs
        // For linear progression, the working weight IS the effective "training max"
        // On success, next session will be higher, so we store current weight as TM
        userData.trainingMaxes.setCanonicalLiftValue(weight, for: lift)
        
        // Check if this is a new PR
        let isNewPR = E1RM.isNewPR(newE1RM: e1rm, previousE1RM: previousE1RM)
        
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
            note: note,
            usesUnroundedReplay: true
        )
        
        userData.linearLogs[lift]?[week]?[day] = entry
        programState?.linearLogs[lift]?[week]?[day] = entry

        // A re-log replaces the earlier result, including any PR it set
        removeLiftRecords(lift: lift, week: week, day: day)
        removeWorkoutSets(lift: lift, week: week, day: day)
        
        // Still record to lift history even on failure (shows attempted weight)
        // Use a reduced rep count to indicate it was a failed attempt
        // E1RM will be lower, reflecting the failed session
        let attemptedReps = max(1, reps - 1) // Assume they got close but missed
        let e1rm = calculateE1RM(weight: weight, reps: attemptedReps)
        let record = LiftRecord(
            liftName: ExerciseLibrary.canonicalLiftName(lift),
            weight: weight,
            reps: attemptedReps,
            estimatedOneRM: e1rm,
            programId: userData.selectedProgram,
            week: week,
            setType: "\(sets)×\(reps) (failed)",
            day: day
        )
        // The rep count here is assumed, not measured, so it can't set a PR
        userData.recordLift(record, updatesPR: false)
        
        // Record to WorkoutRecords (new self-contained history system)
        // For failed attempts, mark as not fully completed
        for setNum in 1...sets {
            recordSetToWorkout(
                lift: lift,
                exerciseName: lift,
                week: week,
                day: day,
                setNumber: setNum,
                weight: weight,
                targetReps: reps,
                actualReps: attemptedReps,
                isAMRAP: false,
                trainingMax: weight,
                exerciseType: .linear,
                completed: false,
                note: setNum == sets ? (note.isEmpty ? nil : note) : nil
            )
        }
        
        // Update training max for linear programs
        // On failure, weight stays the same (or deloads), so update TM accordingly
        if willDeload {
            // Calculate deloaded weight
            let deloadedWeight = roundWeight(weight * (1.0 - config.deloadPercentage))
            userData.trainingMaxes.setCanonicalLiftValue(deloadedWeight, for: lift)
        } else {
            // No deload, TM stays at current weight
            userData.trainingMaxes.setCanonicalLiftValue(weight, for: lift)
        }
    }
    
    /// Undo a linear result: clear it, or put back the one it replaced in a redo. The
    /// old entry goes back exactly as it was, because replay reads its flags.
    func revertLinearLog(lift: String, week: Int, day: Int, reps: Int, sets: Int, undo: SetUndoInfo) {
        clearLinearLog(lift: lift, week: week, day: day)
        if let previous = undo.previousLinearEntry {
            // Logged again for its history records, then overwritten with the original
            if previous.completed {
                logLinearSuccess(lift: lift, week: week, day: day, weight: previous.weight, reps: reps, sets: sets, note: previous.note)
            } else {
                logLinearFailure(lift: lift, week: week, day: day, weight: previous.weight, reps: reps, sets: sets, note: previous.note)
            }
            userData.linearLogs[lift]?[week]?[day] = previous
            programState?.linearLogs[lift]?[week]?[day] = previous
        }
        if let previousTM = undo.previousTrainingMax {
            userData.trainingMaxes.setCanonicalLiftValue(previousTM, for: lift)
        }
    }

    /// Undo a volume rep-out log, keeping any weight override: it cascades into later
    /// weeks and isn't part of what the set logged.
    func revertVolumeReps(lift: String, week: Int, day: Int, previousReps: Int?) {
        if let previousReps {
            logReps(lift: lift, week: week, day: day, reps: previousReps)
            return
        }
        let override = getLog(lift: lift, week: week, day: day)
        clearLog(lift: lift, week: week, day: day)
        if let weight = override?.weightOverride {
            setWeightOverride(lift: lift, week: week, day: day, weight: weight, itemName: override?.overrideItemName)
        }
    }

    /// Undo a structured AMRAP log
    func revertStructuredReps(lift: String, week: Int, day: Int, setIndex: Int, previousReps: Int?) {
        if let previousReps {
            logStructuredReps(lift: lift, week: week, day: day, setIndex: setIndex, reps: previousReps)
        } else {
            clearStructuredSet(lift: lift, week: week, day: day, setIndex: setIndex)
        }
    }

    /// What the lifter last did on a lift, leaving out this session's own day
    func lastPerformance(lift: String, week: Int, day: Int) -> LiftRecord? {
        let name = ExerciseLibrary.canonicalLiftName(lift)
        let cycleStart = userData.currentCycleStartDate
        return userData.liftHistory
            .filter { record in
                guard record.liftName == name else { return false }
                let isThisSession = record.programId == userData.selectedProgram
                    && record.week == week && record.day == day && record.date >= cycleStart
                return !isThisSession
            }
            .max { $0.date < $1.date }
    }

    /// The weight planned for an exercise the next time it appears after this session.
    /// Matches on the exercise, not just the lift: nSuns follows heavy Bench with a lighter
    /// secondary Bench, which says nothing about the next heavy day. Structured exercises
    /// report their heaviest set. Nil if it doesn't come up again.
    func nextPlannedWeight(exercise name: String, lift: String, afterWeek week: Int, day: Int) -> Double? {
        for candidateWeek in weeks.sorted() where candidateWeek >= week {
            for candidateDay in visibleDays(forWeek: candidateWeek) where candidateWeek > week || candidateDay > day {
                for item in dayPlan(week: candidateWeek, day: candidateDay) ?? [] {
                    switch item {
                    case let .linear(itemName, info) where itemName == name && info.lift == lift:
                        return info.weight
                    case let .volume(itemName, itemLift, weight, _, _, _, _, _, _, _, _) where itemName == name && itemLift == lift:
                        return weight
                    case let .structured(itemName, itemLift, _, sets, _) where itemName == name && itemLift == lift:
                        return sets.map(\.weight).max()
                    default:
                        continue
                    }
                }
            }
        }
        return nil
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
            if mostRecent.entry.completed || mostRecent.entry.deloadApplied {
                return 0  // Success or a deload resets the count
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
        removeLiftRecords(lift: lift, week: week, day: day)
        removeWorkoutSets(lift: lift, week: week, day: day)
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
        // Use full reassignment to guarantee @Observable tracking and didSet persistence
        var updated = userData
        updated.customInitialMaxes[lift] = value
        userData = updated
        // Update program state
        programState?.initialMaxes[lift] = value
    }

    func resetInitialMax(for lift: String) {
        // Use full reassignment to guarantee @Observable tracking and didSet persistence
        var updated = userData
        updated.customInitialMaxes.removeValue(forKey: lift)
        userData = updated
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
    
    /// The lifts to name for a day in a given week. Falls back to what's configured when
    /// the plan has no main lift, so a visible day doesn't read as blank.
    func dayLifts(week: Int, day: Int) -> [String] {
        let lifts = CycleProgress.mainLifts(in: dayPlan(week: week, day: day) ?? [])
        return lifts.isEmpty ? CycleProgress.fallbackLifts(from: dayItems(for: day)) : lifts
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
        
        // Detect swapped lifts and copy WeekData for them
        // Compare new items to original program items to find what was swapped
        let originalItems = programData?.days[String(day)] ?? []
        copyWeekDataForSwappedLifts(newItems: items, originalItems: originalItems)
        
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
                // Use default main lifts; accessories come from the synced list below
                dayItems = (programData?.days[String(variantDay)] ?? []).filter { $0.type != .accessory }
            }
            
            // Add the synced accessories
            dayItems.append(contentsOf: accessories)
            
            userData.customDays[variantDay] = dayItems
            programState?.days[variantDay] = dayItems
        }
    }
    
    /// Copy WeekData, singleAt8Percent, and initialMaxes for swapped lifts
    /// Compares new day items to original program items and copies data for any lifts that were swapped
    private func copyWeekDataForSwappedLifts(newItems: [DayItem], originalItems: [DayItem]) {
        // Build a mapping of position -> original lift for main lifts
        var originalLiftsByPosition: [Int: String] = [:]
        for (index, item) in originalItems.enumerated() {
            if let lift = item.lift, item.type != .accessory {
                originalLiftsByPosition[index] = lift
            }
        }
        
        // Check each new main lift - if it's different from the original at that position, copy data
        for (index, item) in newItems.enumerated() {
            guard let newLift = item.lift, item.type != .accessory else { continue }
            
            // Get the original lift at this position (if any)
            let originalLift = originalLiftsByPosition[index]
            
            // If the new lift is different and doesn't have WeekData, copy from the original
            if let originalLift = originalLift, originalLift != newLift {
                // Copy WeekData if the new lift doesn't have it
                if programState?.lifts[newLift] == nil, let oldLiftData = programState?.lifts[originalLift] {
                    programState?.lifts[newLift] = oldLiftData
                }
                
                // Copy singleAt8Percent
                if programState?.singleAt8Percent[newLift] == nil,
                   let oldPercent = programState?.singleAt8Percent[originalLift] {
                    programState?.singleAt8Percent[newLift] = oldPercent
                }
                
                // Copy initialMax if new lift doesn't have one set
                if userData.customInitialMaxes[newLift] == nil && programState?.initialMaxes[newLift] == nil {
                    if let oldMax = userData.customInitialMaxes[originalLift] ?? programState?.initialMaxes[originalLift] {
                        programState?.initialMaxes[newLift] = oldMax
                        userData.customInitialMaxes[newLift] = oldMax
                    }
                }
            }
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
    
    /// Reset all days to default exercises and clear accessory logs
    func resetAllDayItems() {
        userData.customDays = [:]
        userData.accessoryLogs = [:]
        if let pdata = programData {
            for (dayStr, items) in pdata.days {
                if let dayNum = Int(dayStr) {
                    programState?.days[dayNum] = items
                }
            }
        }
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
                // Mutate in place: rebuilding the item would drop its set scheme
                // (setsDetail, sets, reps), which removes structured lifts from the
                // workout and turns Starting Strength's 3x5 into the default 5x5.
                items[i].lift = newLift
                items[i].name = items[i].type == .tm ? "\(newLift) TM" : newLift
            }
        }
        
        setDayItems(for: day, items: items)
        
        // Copy the WeekData from the old lift to the new lift so ProgramEngine can calculate weights
        // This is critical: without WeekData, the lift won't appear in the workout view
        if programState?.lifts[newLift] == nil, let oldLiftData = programState?.lifts[oldLift] {
            programState?.lifts[newLift] = oldLiftData
        }
        
        // Copy the singleAt8Percent data for TM calculations
        if programState?.singleAt8Percent[newLift] == nil,
           let oldPercent = programState?.singleAt8Percent[oldLift] {
            programState?.singleAt8Percent[newLift] = oldPercent
        }
        
        // Ensure the new lift has an initial max
        // First check if the program has a default, otherwise copy from the old lift
        if userData.customInitialMaxes[newLift] == nil {
            if let defaultMax = programData?.initialMaxes[newLift] {
                programState?.initialMaxes[newLift] = defaultMax
            } else if let oldMax = userData.customInitialMaxes[oldLift] ?? programState?.initialMaxes[oldLift] {
                // Copy TM from the old lift since this is a substitution
                programState?.initialMaxes[newLift] = oldMax
                userData.customInitialMaxes[newLift] = oldMax
            }
        }
    }
    
    // MARK: - Persistence Helpers
    
    private func persistSettings() {
        do {
            try persistence.saveSettings(settings)
        } catch {
            Logger.error("Failed to persist settings: \(error)", category: .program)
        }
    }

    private func persistUserData() {
        do {
            try persistence.saveUserData(userData)
        } catch {
            Logger.error("Failed to persist user data: \(error)", category: .program)
        }
    }
    
    // MARK: - Export/Import
    
    func exportData() throws -> Data {
        try persistence.exportUserDataJSON()
    }
    
    func importData(_ data: Data) throws {
        try persistence.importUserDataJSON(data)
        self.userData = persistence.loadUserData()

        // The training position lives in settings, which a backup doesn't include.
        // Resume at the backup's latest logged week, on its first day not yet logged.
        let week = highestLoggedWeek()
        let days = visibleDays(forWeek: week)
        settings.currentWeek = week
        settings.currentDay = days.first { !isDayLogged(week: week, day: $0) } ?? days.first ?? 1
    }
    
    // MARK: - Reset
    
    func resetLogs() {
        userData.logs = [:]
        userData.structuredLogs = [:]
        userData.linearLogs = [:]
        userData.accessoryLogs = [:]
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
        // max + 1, not count + 1: after deleting an archived cycle, count + 1 would
        // reuse a number that a remaining cycle already has.
        (userData.cycleHistory.map(\.cycleNumber).max() ?? 0) + 1
    }
    
    /// Get cycle history sorted by most recent first
    var cycleHistory: [CompletedCycle] {
        userData.cycleHistory.sorted { $0.endDate > $1.endDate }
    }
    
    /// Calculate the final training maxes after the specified week
    /// This uses the TM calculation engine to get the TMs after all logged adjustments
    /// IMPORTANT: Returns the TM for week+1 which includes progression from the AMRAP performance at `week`
    /// Handles SBS, structured (531/nSuns/Greyskull), and linear (Starting Strength/StrongLifts) programs
    func finalTrainingMaxes(atWeek week: Int) -> [String: Double] {
        guard let state = programState else { return [:] }
        
        // Sync all log types
        state.logs = userData.logs
        state.structuredLogs = userData.structuredLogs
        state.linearLogs = userData.linearLogs
        state.rounding = settings.roundingIncrement
        state.useMetric = settings.useMetric

        // Sync custom initial maxes
        for (liftName, max) in userData.customInitialMaxes {
            state.initialMaxes[liftName] = max
        }

        var result: [String: Double] = [:]
        
        // The "final" TM after completing week N is actually the TM for week N+1
        // because progression from AMRAP performance is applied to the next week
        let targetWeek = week + 1

        // Only this program's lifts: liftNames also includes every lift in history,
        // whose stale or alias-spelled values must not overwrite universal TMs.
        var programLifts = Set(state.lifts.keys)
        for items in state.days.values {
            programLifts.formUnion(items.compactMap(\.lift))
        }
        
        for lift in programLifts.sorted() {
            // Check if this is a structured lift
            let structuredLiftInfo = getAllStructuredLiftInfo()
            if structuredLiftInfo[lift] != nil {
                // For structured lifts, compute TMs up to targetWeek to get the progressed TM
                let structuredTMs = engine.computeStructuredTrainingMaxes(state: state, upToWeek: targetWeek, structuredLiftInfo: structuredLiftInfo)
                if let tm = structuredTMs[targetWeek]?[lift] {
                    result[lift] = tm
                    continue
                } else if let tm = structuredTMs[week]?[lift] {
                    // Fallback to current week if next week not computed
                    result[lift] = tm
                    continue
                }
            }
            
            // Check if this is a linear lift
            let isLinearLift = state.days.values.flatMap { $0 }.contains { item in
                item.type == .linear && item.lift == lift
            }
            if isLinearLift {
                // For linear lifts, get the most recent logged weight
                if let liftLogs = userData.linearLogs[lift] {
                    let sortedLogs = liftLogs.sorted(by: { $0.key < $1.key })
                    if let lastLog = sortedLogs.filter({ $0.key <= week }).last,
                       let lastSession = lastLog.value.max(by: { $0.key < $1.key }) {
                        // The week's latest session, not whichever a Dictionary yields
                        result[lift] = lastSession.value.weight
                        continue
                    }
                }
            }
            
            // Try SBS-style TM calculation
            let sbsTMs = engine.computeTrainingMaxes(state: state, upToWeek: targetWeek)
            if let tm = sbsTMs[targetWeek]?[lift] {
                result[lift] = tm
                continue
            } else if let tm = sbsTMs[week]?[lift] {
                result[lift] = tm
                continue
            }
            
            // Fallback to initial max if no logged data yet. Consult the user's universal
            // training maxes before the program defaults so structured programs that ship
            // no initial_maxes fall back to the user's real TMs instead of 0.
            if let initial = userData.customInitialMaxes.canonicalLiftValue(for: lift) ?? userData.trainingMaxes.canonicalLiftValue(for: lift) ?? state.initialMaxes[lift] {
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
                // Any entry counts: sets without AMRAPs log an empty one (markStructuredCompleted)
                if !dayLogs.isEmpty && week > maxWeek {
                    maxWeek = week
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
                // Any entry counts: sets without AMRAPs log an empty one (markStructuredCompleted)
                if !dayLogs.isEmpty {
                    return true
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
        
        // Filter workout records to only include those from this cycle
        let cycleWorkoutRecords = userData.workoutRecords.filter { record in
            record.date >= userData.currentCycleStartDate
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
            liftData: liftData,
            workoutRecords: cycleWorkoutRecords
        )
    }
    
    /// What each lift would start the next cycle at, from the logs as they stand. Reads
    /// the logs, so call it before they're cleared. Quick Repeat and the builder's prefill
    /// both use this, and the result is final: nothing applies the increment again.
    func nextCycleStartingMaxes() -> [String: Double] {
        let lastWeek = highestLoggedWeek()
        var carriedMaxes = finalTrainingMaxes(atWeek: lastWeek)

        // Manual-progression programs (5/3/1) hold TMs through the cycle, so a
        // finished cycle is the one point they rise. Without this a one-tap repeat
        // would run the same weights forever. Partial cycles carry over unchanged.
        if hasLoggedData, let state = programState, state.manualProgression,
           let finalWeek = state.weeks.max(), lastWeek >= finalWeek {
            for lift in getAllStructuredLiftInfo().keys {
                guard let tm = carriedMaxes[lift], tm > 0 else { continue }
                carriedMaxes[lift] = tm + engine.manualCycleIncrement(lift: lift, useMetric: settings.useMetric)
            }
        }

        return carriedMaxes.filter { $0.value > 0 }
    }

    /// What each lift's number is called in this program
    private var liftValuesName: String {
        programHasTrainingMaxes ? "training maxes" : "working weights"
    }

    /// The wording for the Start New Cycle dialog, from Home or Settings
    var newCycleDialogMessage: String {
        let choices = "Customize lets you change program, exercises, or \(liftValuesName)."
        var parts: [String]
        if isCycleComplete {
            parts = [
                "Cycle \(currentCycleNumber) is complete and will be saved to Past Cycles.",
                "Quick Repeat starts the same program from your new \(liftValuesName). \(choices)"
            ]
        } else if hasLoggedData {
            parts = [
                "You have a cycle in progress. Starting a new one ends it now: what you've logged moves to Past Cycles, and the workouts you haven't done are dropped.",
                "Quick Repeat starts the same program from your current \(liftValuesName). \(choices)"
            ]
        } else {
            parts = [
                "Nothing is logged in this cycle yet.",
                "Quick Repeat restarts the same program from your current \(liftValuesName). \(choices)"
            ]
        }
        if activeSession != nil {
            parts.append("Your workout in progress will be discarded.")
        }
        return parts.joined(separator: " ")
    }

    /// The one place a finished cycle counts toward a review request. Pass whether the cycle
    /// was finished as read before starting, because starting clears the logs that say so.
    /// The prompt itself waits a moment and flushes only where no celebration is showing.
    @MainActor
    func newCycleStarted(afterFinishedCycle finishedCycle: Bool) {
        if finishedCycle {
            ReviewRequestManager.shared.recordCycleCompleted()
        }
        ReviewRequestManager.shared.presentPendingReviewRequestIfNeeded()
    }

    /// Start a new training cycle
    /// - Parameter carryOverTMs: If true, use current calculated TMs as starting point for next cycle
    func startNewCycle(carryOverTMs: Bool = true) {
        let lastWeek = highestLoggedWeek()

        // Calculate ending TMs before we clear anything
        let endingMaxes = finalTrainingMaxes(atWeek: lastWeek)
        let startingMaxes = currentCycleStartingMaxes()
        let carriedMaxes = carryOverTMs ? nextCycleStartingMaxes() : [:]
        
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
        for (lift, tm) in carriedMaxes {
            userData.customInitialMaxes[lift] = tm
            programState?.initialMaxes[lift] = tm
            // Also update universal trainingMaxes for cross-program consistency
            userData.trainingMaxes.setCanonicalLiftValue(tm, for: lift)
        }
        
        // Clear current cycle logs (preserve accessoryLogs — they represent user preferences)
        userData.logs = [:]
        userData.structuredLogs = [:]
        userData.linearLogs = [:]
        // Clear workout records from this cycle (they're archived in cycleHistory now)
        // Capture date before removeAll to avoid exclusivity violation
        let cycleStartDate = userData.currentCycleStartDate
        userData.workoutRecords.removeAll { $0.date >= cycleStartDate }

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

    // MARK: - History Progress Display

    /// How a lift's progress should be described. Takes canonical or program spellings.
    func progressKind(for lift: String) -> LiftProgressKind {
        let canonical = ExerciseLibrary.canonicalLiftName(lift)
        let types = allDays.flatMap { liftsInDay($0) }
            .filter { ExerciseLibrary.canonicalLiftName($0.lift) == canonical }
            .map(\.type)
        return LiftProgressKind.resolve(itemTypes: types, manualProgression: programState?.manualProgression ?? false)
    }

    /// The working weight a linear lift will use next session. Read-only: same replay as
    /// the plan, so it respects the old-log anchoring.
    func nextLinearWorkingWeight(for lift: String) -> Double? {
        guard let state = programState else { return nil }
        state.logs = userData.logs
        state.linearLogs = userData.linearLogs
        state.rounding = settings.roundingIncrement
        state.useMetric = settings.useMetric
        for (liftName, max) in userData.customInitialMaxes {
            state.initialMaxes[liftName] = max
        }
        return engine.nextLinearWorkingWeight(state: state, lift: lift)
    }

    /// The current program's main lifts in program order, with this cycle's movement.
    /// Linear lifts report next session's weight: `finalTrainingMaxes` gives the last
    /// logged weight, which is what must carry into a new cycle but doesn't show progress.
    func currentCycleProgress() -> CycleProgressSummary {
        let items = allDays.flatMap { liftsInDay($0) }
        let finalMaxes = finalTrainingMaxes(atWeek: highestLoggedWeek())
        let manual = programState?.manualProgression ?? false

        let lifts: [LiftCycleProgress] = HistoryLiftOrder.programOrder(items).compactMap { lift in
            let start = initialMax(for: lift)
            guard start > 0 else { return nil }
            let kind = LiftProgressKind.resolve(
                itemTypes: items.filter { $0.lift == lift }.map(\.type),
                manualProgression: manual
            )
            let latest = kind == .workingWeight ? nextLinearWorkingWeight(for: lift) : finalMaxes[lift]
            return LiftCycleProgress(lift: lift, kind: kind, start: start, current: latest ?? start)
        }
        return CycleProgressSummary(lifts: lifts)
    }

    /// Send the user to the Workout tab from anywhere, for "nothing here yet" prompts
    func goToWorkoutTab() {
        returnToHomeCount += 1
    }
    
    // MARK: - Program Switch Preview (Cycle Builder)

    /// Snapshot taken before the cycle builder starts previewing programs, so
    /// cancelling the builder restores everything loadProgram may have archived,
    /// cleared, or switched. UserData is a value type — one copy captures logs,
    /// records, cycle history, customizations, and the program selection. Settings
    /// are captured too, since the builder's settings step edits them directly.
    private struct ProgramPreviewSnapshot {
        let userData: UserData
        let settings: UserSettings
    }

    private var programPreviewSnapshot: ProgramPreviewSnapshot?

    /// Call before the cycle builder starts loading candidate programs.
    func beginProgramPreview() {
        guard programPreviewSnapshot == nil else { return }
        programPreviewSnapshot = ProgramPreviewSnapshot(
            userData: userData,
            settings: settings
        )
    }

    /// The user committed to the new cycle — drop the rollback snapshot.
    func commitProgramPreview() {
        programPreviewSnapshot = nil
    }

    /// The user cancelled the cycle builder — restore all user data and reload
    /// the program that was active before previewing started.
    func cancelProgramPreview() async {
        guard let snapshot = programPreviewSnapshot else { return }
        programPreviewSnapshot = nil

        // A template saved inside the builder is deliberate work, not a preview
        // side effect, so it survives the cancel.
        var restored = snapshot.userData
        restored.customTemplates = userData.customTemplates
        userData = restored
        settings = snapshot.settings

        // Reload the original program. selectedProgram was restored with the
        // snapshot, so this load is a plain re-open, not a destructive switch.
        if let previousProgram = snapshot.userData.selectedProgram {
            try? await loadProgram(previousProgram)
        }
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

    /// Complete onboarding immediately with a sensible default program, used by
    /// the "Skip for now" affordance. Preselects a free program (StrongLifts 5x5
    /// falling back to any free/first program) so the app opens onto a valid
    /// cycle with program-default training maxes rather than an empty state.
    func skipOnboardingWithDefault() async {
        let preferred = "stronglifts_5x5_12week"
        let programId: String? = availablePrograms.contains(where: { $0.id == preferred })
            ? preferred
            : (availablePrograms.first(where: { StoreManager.isProgramFree($0.id) })?.id
               ?? availablePrograms.first?.id)

        if let programId, userData.selectedProgram != programId {
            try? await loadProgram(programId)
        }
        seedStarterWeightsForUnsetLifts()
        completeOnboarding()
    }
    
    /// Programs ship no starting weights, so a user who skipped setup would otherwise
    /// open every lift at 0. Give each unset lift a light weight that suits it, which they
    /// can raise from Settings. A lift with a value already is left alone.
    private func seedStarterWeightsForUnsetLifts() {
        guard let state = programState else { return }
        let kind = StartingWeightKind.classify(items: state.days.values.flatMap { $0 })
var lifts = Set(state.lifts.keys)
        for items in state.days.values {
            lifts.formUnion(items.filter { $0.type != .accessory }.compactMap(\.lift))
        }
        for lift in lifts where (userData.customInitialMaxes[lift] ?? 0) <= 0 {
            let starter = userData.trainingMaxes.canonicalLiftValue(for: lift).flatMap { $0 > 0 ? $0 : nil }
                ?? StarterWeights.starter(for: lift, useMetric: settings.useMetric, barWeight: settings.barWeight, kind: kind)
userData.customInitialMaxes[lift] = starter
            state.initialMaxes[lift] = starter
        }
    }

    /// Get all program info for cycle builder
    var programInfo: (name: String, weeks: Int, days: Int)? {
        guard let data = programData else { return nil }
        return (data.name, data.weeks.count, data.days.count)
    }

    /// Best user-facing name for the CURRENTLY loaded program.
    ///
    /// Resolution order: active custom template's name -> availablePrograms
    /// display name -> programData.displayName -> programData.name -> generic
    /// fallback. Never returns a raw program id or a trademarked internal name
    /// where a generic display name exists.
    var programDisplayName: String {
        if let programId = userData.selectedProgram {
            // Custom template: use the template's own user-chosen name.
            if UserData.isCustomTemplate(programId: programId),
               let templateId = UserData.templateId(from: programId),
               let template = userData.template(withId: templateId) {
                return template.name
            }
            // Bundled program: prefer the generic display name.
            if let info = availablePrograms.first(where: { $0.id == programId }) {
                return info.displayName
            }
        }
        if let data = programData {
            if let display = data.displayName, !display.isEmpty { return display }
            if !data.name.isEmpty { return data.name }
        }
        return "Your Program"
    }

    /// Best user-facing name for an arbitrary program id.
    ///
    /// Resolution order: availablePrograms display name -> custom template name
    /// (by id) -> generic fallback. Never returns the raw id.
    func displayName(forProgramId id: String) -> String {
        if let info = availablePrograms.first(where: { $0.id == id }) {
            return info.displayName
        }
        if UserData.isCustomTemplate(programId: id),
           let templateId = UserData.templateId(from: id),
           let template = userData.template(withId: templateId) {
            return template.name
        }
        return "Your Program"
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
        // Use full reassignment to guarantee @Observable tracking and didSet persistence
        var updated = userData
        for (lift, value) in maxes {
            updated.customInitialMaxes[lift] = value
            programState?.initialMaxes[lift] = value
            // Also update universal trainingMaxes for cross-program consistency
            updated.trainingMaxes.setCanonicalLiftValue(value, for: lift)
        }
        userData = updated
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
        // The builder's newMaxes are already final, so this applies only without them
        let carriedMaxes = (newMaxes == nil && carryOverTMs) ? nextCycleStartingMaxes() : [:]

        // Archive current cycle if there's any logged data
        if hasLoggedData {
            let completedCycle = buildCompletedCycle(
                lastWeek: lastWeek,
                startingMaxes: startingMaxes,
                endingMaxes: endingMaxes
            )
            userData.cycleHistory.append(completedCycle)
        }

        // Clear current cycle logs (preserve accessoryLogs — they represent user preferences)
        userData.logs = [:]
        userData.structuredLogs = [:]
        userData.linearLogs = [:]

        // Existing customDays stay: the builder's review step showed them, and only
        // days the user edited there arrive in exerciseCustomizations (applied below).

        // Apply new maxes from builder, or carry over
        if let newMaxes = newMaxes {
            setInitialMaxes(newMaxes)
        } else {
            for (lift, tm) in carriedMaxes {
                userData.customInitialMaxes[lift] = tm
                programState?.initialMaxes[lift] = tm
                // Also update universal trainingMaxes for cross-program consistency
                userData.trainingMaxes.setCanonicalLiftValue(tm, for: lift)
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

