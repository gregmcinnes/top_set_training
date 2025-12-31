import SwiftUI
import Charts

/// Display mode for the progress chart
enum ChartDisplayMode: String, CaseIterable {
    case e1rm = "Est. 1RM"
    case trainingMax = "Training Max"
}

/// Strength score formula options
enum StrengthScoreFormula: String, CaseIterable {
    case wilks = "WILKS"
    case dots = "DOTS"
    case ipfGL = "IPF GL"
    
    var description: String {
        switch self {
        case .wilks: return "Classic powerlifting formula"
        case .dots: return "Modern WILKS replacement"
        case .ipfGL: return "Official IPF scoring"
        }
    }
    
    var color: Color {
        switch self {
        case .wilks: return .blue
        case .dots: return .purple
        case .ipfGL: return .orange
        }
    }
}

struct HistoryView: View {
    @Bindable var appState: AppState
    @State private var selectedLift: String?
    @State private var showingTMProgress = false
    @State private var chartDisplayMode: ChartDisplayMode = .trainingMax // Default to TM for free users
    @State private var showingPaywall = false
    @State private var showingShareSheet = false
    @State private var shareImage: UIImage?
    @State private var ageCategory: AgeCategory = .allAges
    @State private var selectedStrengthFormula: StrengthScoreFormula = .wilks
    @State private var showStrengthScore = true // Show strength score by default
    
    private let storeManager = StoreManager.shared
    
    /// Classic lifts that should always appear first (in this order)
    private let classicLifts = ["Squat", "Deadlift", "Bench Press", "Overhead Press"]
    
    /// Alternate names for classic lifts for matching
    private let classicLiftAliases: [String: [String]] = [
        "Squat": ["Squat", "Back Squat"],
        "Deadlift": ["Deadlift", "Trap Bar Deadlift"],
        "Bench Press": ["Bench Press", "Bench"],
        "Overhead Press": ["Overhead Press", "OHP", "Press"]
    ]
    
    /// Get lifts ordered for history view: classic lifts first, then other program lifts
    /// For paid users, also includes lifts from past cycles and unified history
    private var orderedLifts: [String] {
        var allLifts = Set<String>()
        
        // Get lifts from current program state
        if let state = appState.programState {
            // Get lifts from the lifts dictionary (programs with training maxes)
            allLifts.formUnion(state.lifts.keys)
            
            // Also get lifts from day items (for nSuns programs which may use lifts dict differently)
            for (_, items) in state.days {
                for item in items {
                    if let lift = item.lift {
                        allLifts.insert(lift)
                    }
                }
            }
        }
        
        // Always include lifts from current unified history (all users can see current cycle)
        allLifts.formUnion(appState.allRecordedLifts)
        
        // For paid users, also include lifts from past cycle history
        if canAccessFullHistory {
            for cycle in appState.userData.cycleHistory {
                allLifts.formUnion(cycle.logs.keys)
                allLifts.formUnion(cycle.liftData.keys)
                allLifts.formUnion(cycle.tmHistory.keys)
                allLifts.formUnion(cycle.structuredLogs.keys)
                allLifts.formUnion(cycle.linearLogs.keys)
            }
        }
        
        var result: [String] = []
        var usedLifts = Set<String>()
        
        // First, add classic lifts in order (if they exist in our lifts)
        for classicLift in classicLifts {
            if let aliases = classicLiftAliases[classicLift] {
                for alias in aliases {
                    if allLifts.contains(alias) && !usedLifts.contains(alias) {
                        result.append(alias)
                        usedLifts.insert(alias)
                        break // Only add one version of each classic lift
                    }
                }
            }
        }
        
        // Then add any remaining lifts alphabetically
        let remainingLifts = allLifts
            .filter { !usedLifts.contains($0) }
            .sorted()
        
        result.append(contentsOf: remainingLifts)
        
        return result
    }
    
    /// Whether the user can access the E1RM chart
    private var canAccessE1RM: Bool {
        storeManager.canAccess(.e1rmChart)
    }
    
    /// Whether the user can access full history
    private var canAccessFullHistory: Bool {
        storeManager.canAccess(.fullHistory)
    }
    
    /// Whether the user can access strength scores
    private var canAccessStrengthScores: Bool {
        storeManager.canAccess(.e1rmChart)
    }
    
    /// Whether bodyweight is set
    private var hasBodyweight: Bool {
        appState.settings.bodyweight != nil && appState.settings.bodyweight! > 0
    }
    
    /// Whether the user has SBD (Squat, Bench, Deadlift) data for strength score calculation
    private var hasSBDData: Bool {
        let hasSquat = bestE1RM(for: "Squat") != nil
        let hasBench = bestE1RM(for: "Bench") != nil || bestE1RM(for: "Bench Press") != nil
        let hasDeadlift = bestE1RM(for: "Deadlift") != nil || bestE1RM(for: "Trap Bar Deadlift") != nil
        return hasSquat || hasBench || hasDeadlift
    }
    
    /// Get the best E1RM for a lift from PR data
    private func bestE1RM(for liftName: String) -> Double? {
        appState.userData.personalRecords[liftName]?.estimatedOneRM
    }
    
    /// Get bodyweight in kg for strength score calculations
    private var bodyweightInKg: Double {
        guard let bw = appState.settings.bodyweight, bw > 0 else { return 0 }
        // Settings bodyweight is always stored in lbs
        return bw * 0.453592
    }
    
    /// Age category selector for competitive data
    private var ageCategoryMenu: some View {
        Menu {
            ForEach(AgeCategory.allCases) { category in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        ageCategory = category
                    }
                } label: {
                    HStack {
                        Text(category.displayName)
                        if category == ageCategory {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(ageCategory == .allAges ? "All Ages" : ageCategory.displayName)
                    .font(SBSFonts.caption())
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.15))
            )
        }
    }
    
    /// Share lift progress button
    private var shareLiftProgressButton: some View {
        Button {
            generateLiftProgressShareImage()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
                Text("Share Progress")
                    .font(SBSFonts.caption())
            }
            .foregroundStyle(SBSColors.accentFallback)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(SBSColors.accentFallback.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .disabled(selectedLift == nil || allE1RMData(for: selectedLift ?? "").isEmpty)
    }
    
    /// Prompt to set bodyweight for strength standards
    private var setBodyweightPrompt: some View {
        NavigationLink {
            SettingsView(appState: appState)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "scalemass")
                    .font(.system(size: 12))
                Text("Set bodyweight for strength scores")
                    .font(SBSFonts.caption())
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
            }
            .foregroundStyle(SBSColors.textTertiaryFallback)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(SBSColors.surfaceFallback)
            )
        }
        .buttonStyle(.plain)
    }
    
    /// Toggle for showing strength score
    private var strengthScoreToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showStrengthScore.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showStrengthScore ? "medal.fill" : "medal")
                    .font(.system(size: 12))
                Text(showStrengthScore ? "Hide Score" : "Show Score")
                    .font(SBSFonts.caption())
            }
            .foregroundStyle(showStrengthScore ? selectedStrengthFormula.color : SBSColors.textSecondaryFallback)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(showStrengthScore ? selectedStrengthFormula.color.opacity(0.15) : SBSColors.surfaceFallback)
            )
        }
        .buttonStyle(.plain)
    }
    
    /// Strength formula selector menu
    private var strengthFormulaMenu: some View {
        Menu {
            ForEach(StrengthScoreFormula.allCases, id: \.self) { formula in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedStrengthFormula = formula
                    }
                } label: {
                    HStack {
                        Text(formula.rawValue)
                        Text("• \(formula.description)")
                            .foregroundStyle(.secondary)
                        if formula == selectedStrengthFormula {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedStrengthFormula.rawValue)
                    .font(SBSFonts.caption())
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(selectedStrengthFormula.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selectedStrengthFormula.color.opacity(0.15))
            )
        }
    }
    
    /// Locked strength score button for non-premium users
    private var lockedStrengthScoreButton: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                Text("Strength Scores")
                    .font(SBSFonts.caption())
                PremiumBadge(isCompact: true)
            }
            .foregroundStyle(SBSColors.textTertiaryFallback)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(SBSColors.surfaceFallback)
            )
        }
        .buttonStyle(.plain)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SBSLayout.sectionSpacing) {
                    // Current Cycle TM Progress Card
                    CurrentCycleTMProgressCard(
                        appState: appState,
                        onTap: { showingTMProgress = true }
                    )
                    .padding(.horizontal)
                    
                    // Lift selector
                    LiftSelector(
                        lifts: orderedLifts,
                        selectedLift: $selectedLift
                    )
                    .padding(.horizontal)
                    
                    // Progress Chart with mode toggle
                    if let lift = selectedLift {
                        VStack(spacing: SBSLayout.paddingSmall) {
                            ProgressChart(
                                liftName: lift,
                                displayMode: $chartDisplayMode,
                                e1rmData: canAccessE1RM ? allE1RMData(for: lift) : [],
                                tmData: allTMData(for: lift),
                                useMetric: appState.settings.useMetric,
                                canAccessE1RM: canAccessE1RM,
                                onE1RMLockedTap: { showingPaywall = true },
                                showStrengthBands: false,
                                bodyweight: bodyweightInKg,
                                isMale: appState.settings.isMale,
                                ageCategory: ageCategory
                            )
                            
                            // Strength score display and share button
                            HStack {
                                if canAccessStrengthScores {
                                    if hasBodyweight {
                                        strengthScoreToggle
                                        if showStrengthScore {
                                            strengthFormulaMenu
                                        }
                                    } else {
                                        setBodyweightPrompt
                                    }
                                } else {
                                    // Show locked strength score toggle for non-premium users
                                    lockedStrengthScoreButton
                                }
                                Spacer()
                                shareLiftProgressButton
                            }
                            
                            // Strength score card (when enabled and data available)
                            if canAccessStrengthScores && showStrengthScore && hasBodyweight && hasSBDData {
                                StrengthScoreCard(
                                    formula: selectedStrengthFormula,
                                    squatE1RM: bestE1RM(for: "Squat"),
                                    benchE1RM: bestE1RM(for: "Bench") ?? bestE1RM(for: "Bench Press"),
                                    deadliftE1RM: bestE1RM(for: "Deadlift") ?? bestE1RM(for: "Trap Bar Deadlift"),
                                    bodyweightKg: bodyweightInKg,
                                    isMale: appState.settings.isMale,
                                    useMetric: appState.settings.useMetric
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Log history for this lift (includes past cycles)
                        // Free users only see current cycle
                        LogHistoryList(
                            liftName: lift,
                            logs: canAccessFullHistory ? allLogsForLift(lift) : currentCycleLogsOnly(lift),
                            useMetric: appState.settings.useMetric,
                            showPastCyclesLocked: !canAccessFullHistory && hasPastCycles,
                            onUnlockTap: { showingPaywall = true }
                        )
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView(
                            "Select a Lift",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Choose a lift above to see your progress.")
                        )
                        .padding(.top, 60)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .sbsBackground()
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingTMProgress) {
                TMProgressDetailView(appState: appState)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(triggeredByFeature: canAccessE1RM ? .fullHistory : .e1rmChart)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = shareImage {
                    ShareSheet(items: [image])
                }
            }
        }
        .onAppear {
            if selectedLift == nil, let first = orderedLifts.first {
                selectedLift = first
            }
            // If user can't access E1RM, make sure we're showing TM
            if !canAccessE1RM && chartDisplayMode == .e1rm {
                chartDisplayMode = .trainingMax
            }
        }
    }
    
    /// Check if there are any past cycles
    private var hasPastCycles: Bool {
        !appState.userData.cycleHistory.isEmpty
    }
    
    /// Generate shareable lift progress image for the currently selected lift
    @MainActor
    private func generateLiftProgressShareImage() {
        guard let lift = selectedLift else { return }
        
        // Get E1RM data for this lift
        let e1rmData = allE1RMData(for: lift)
        guard e1rmData.count >= 1 else { return }
        
        // Get first and last E1RM
        let sortedData = e1rmData.sorted { $0.date < $1.date }
        guard let first = sortedData.first, let last = sortedData.last else { return }
        
        // Convert to display units
        let startE1RM = appState.settings.useMetric ? first.e1rm * 0.453592 : first.e1rm
        let currentE1RM = appState.settings.useMetric ? last.e1rm * 0.453592 : last.e1rm
        
        let summary = LiftProgressSummary(
            liftName: lift,
            startE1RM: startE1RM,
            startDate: first.date,
            currentE1RM: currentE1RM,
            currentDate: last.date,
            useMetric: appState.settings.useMetric,
            percentile: nil,
            isMale: appState.settings.isMale
        )
        
        let shareableCard = ShareableLiftProgressCard(summary: summary)
        
        // Generate image asynchronously to ensure it's ready before showing sheet
        Task { @MainActor in
            // Small delay to ensure view is fully laid out
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
            shareImage = shareableCard.snapshot()
            showingShareSheet = true
        }
    }
    
    /// Get only current cycle logs for free users
    private func currentCycleLogsOnly(_ lift: String) -> [HistoryLogEntry] {
        logsForCurrentCycle(lift).map { log in
            HistoryLogEntry(
                cycleNumber: appState.currentCycleNumber,
                week: log.week,
                reps: log.reps,
                target: log.target,
                weight: log.weight,
                e1rm: log.e1rm,
                date: appState.userData.currentCycleStartDate,
                note: log.note,
                programName: appState.programData?.displayName ?? appState.programData?.name
            )
        }
    }
    
    /// Get all e1RM data from unified lift history (program-agnostic)
    private func allE1RMData(for lift: String) -> [(date: Date, e1rm: Double, weight: Double, reps: Int)] {
        // Primary source: unified lift history (program-agnostic)
        let unifiedHistory = appState.liftHistory(for: lift)
        
        if !unifiedHistory.isEmpty {
            // Use unified history if available
            return unifiedHistory.map { record in
                (record.date, record.estimatedOneRM, record.weight, record.reps)
            }
        }
        
        // Fallback: legacy approach for older data not yet in unified history
        var allData: [(date: Date, e1rm: Double, weight: Double, reps: Int)] = []
        
        // Add data from past cycles (in chronological order)
        let sortedCycles = appState.userData.cycleHistory.sorted { $0.startDate < $1.startDate }
        
        for cycle in sortedCycles {
            // First, try to use stored liftData (preferred, program-agnostic)
            if let liftDataForLift = cycle.liftData[lift], !liftDataForLift.isEmpty {
                for (week, weekData) in liftDataForLift.sorted(by: { $0.key < $1.key }) {
                    let date = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: cycle.startDate) ?? cycle.startDate
                    allData.append((date, weekData.e1rm, weekData.weight, weekData.reps))
                }
            } else if let liftLogs = cycle.logs[lift] {
                // Fallback: calculate from logs + current program state (may not work if program changed)
                for week in 1...cycle.lastCompletedWeek {
                    guard let dayLogs = liftLogs[week] else { continue }
                    // Find any entry with logged reps from any day
                    for (_, entry) in dayLogs {
                        guard let reps = entry.repsLastSet else { continue }
                        // Calculate weight and e1RM for this historical entry
                        let weight = calculateWeight(cycle: cycle, week: week, lift: lift)
                        guard weight > 0 else { continue }
                        let e1rm = weight * (1.0 + Double(reps) / 30.0)
                        // Calculate date: start date + (week - 1) weeks
                        let date = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: cycle.startDate) ?? cycle.startDate
                        allData.append((date, e1rm, weight, reps))
                        break // Only take the first valid entry per week
                    }
                }
            }
        }
        
        // Add current cycle data
        let currentE1RMData = appState.estimatedOneRepMaxes(for: lift)
        let currentStartDate = appState.userData.currentCycleStartDate
        for item in currentE1RMData {
            let date = Calendar.current.date(byAdding: .weekOfYear, value: item.week - 1, to: currentStartDate) ?? currentStartDate
            allData.append((date, item.e1rm, item.weight, item.reps))
        }
        
        return allData
    }
    
    /// Get all training max data across all cycles for the chart
    /// Uses stored tmHistory from CompletedCycle for program-agnostic display
    private func allTMData(for lift: String) -> [(date: Date, tm: Double)] {
        var allData: [(date: Date, tm: Double)] = []
        
        // Add data from past cycles (in chronological order)
        let sortedCycles = appState.userData.cycleHistory.sorted { $0.startDate < $1.startDate }
        
        for cycle in sortedCycles {
            var foundData = false
            
            // First, try to use the stored tmHistory (preferred, program-agnostic)
            if let tmHistoryForLift = cycle.tmHistory[lift], !tmHistoryForLift.isEmpty {
                foundData = true
                for (week, tm) in tmHistoryForLift.sorted(by: { $0.key < $1.key }) {
                    guard tm > 0 else { continue }  // Skip zero TMs
                    let date = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: cycle.startDate) ?? cycle.startDate
                    allData.append((date, tm))
                }
            }
            
            // Fallback: check SBS-style logs (for legacy cycles without tmHistory)
            if !foundData, let liftLogs = cycle.logs[lift] {
                let startTM = cycle.startingMaxes[lift] ?? 0
                let endTM = cycle.endingMaxes[lift] ?? startTM
                
                guard startTM > 0 else { continue }
                
                for week in 1...cycle.lastCompletedWeek {
                    let hasLog = liftLogs[week]?.values.contains { $0.repsLastSet != nil } == true
                    if hasLog {
                        let progress = Double(week - 1) / Double(max(cycle.lastCompletedWeek - 1, 1))
                        let tm = startTM + (endTM - startTM) * progress
                        let date = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: cycle.startDate) ?? cycle.startDate
                        allData.append((date, tm))
                        foundData = true
                    }
                }
            }
            
            // Fallback: check structuredLogs (for structured programs)
            if !foundData, let structuredLiftLogs = cycle.structuredLogs[lift] {
                let startTM = cycle.startingMaxes[lift] ?? 0
                let endTM = cycle.endingMaxes[lift] ?? startTM
                
                guard startTM > 0 else { continue }
                
                for (week, dayLogs) in structuredLiftLogs.sorted(by: { $0.key < $1.key }) {
                    let hasLog = dayLogs.values.contains { !$0.amrapReps.isEmpty }
                    if hasLog {
                        let progress = Double(week - 1) / Double(max(cycle.lastCompletedWeek - 1, 1))
                        let tm = startTM + (endTM - startTM) * progress
                        let date = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: cycle.startDate) ?? cycle.startDate
                        allData.append((date, tm))
                        foundData = true
                    }
                }
            }
            
            // Fallback: check linearLogs (for linear programs)
            if !foundData, let linearLiftLogs = cycle.linearLogs[lift] {
                for (week, dayLogs) in linearLiftLogs.sorted(by: { $0.key < $1.key }) {
                    for (_, entry) in dayLogs {
                        guard entry.weight > 0 else { continue }
                        let date = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: cycle.startDate) ?? cycle.startDate
                        // For linear, the working weight IS the TM
                        allData.append((date, entry.weight))
                        foundData = true
                    }
                }
            }
        }
        
        // Add current cycle data
        let currentTMData = appState.allTrainingMaxes(for: lift)
        let currentStartDate = appState.userData.currentCycleStartDate
        
        // Get the starting max for this cycle (for the chart's starting point)
        let startingMax = appState.currentCycleStartingMaxes()[lift] ?? 0
        
        // If we have no TM data yet but have a valid starting max, add it as the first point
        if currentTMData.isEmpty && startingMax > 0 && allData.isEmpty {
            allData.append((currentStartDate, startingMax))
        }
        
        // Filter to only include weeks with actual logs (check SBS, structured, AND linear logs)
        for item in currentTMData {
            guard item.tm > 0 else { continue }  // Skip zero TMs
            
            let hasSBSLog = appState.userData.logs[lift]?[item.week]?.values.contains { $0.repsLastSet != nil } == true
            let hasStructuredLog = appState.userData.structuredLogs[lift]?[item.week]?.values.contains { !$0.amrapReps.isEmpty } == true
            let hasLinearLog = appState.userData.linearLogs[lift]?[item.week] != nil
            
            if hasSBSLog || hasStructuredLog || hasLinearLog {
                var date = Calendar.current.date(byAdding: .weekOfYear, value: item.week - 1, to: currentStartDate) ?? currentStartDate
                
                // Check if we have actual date from lift history
                let liftHistory = appState.liftHistory(for: lift)
                if let actualRecord = liftHistory.first(where: { $0.week == item.week }) {
                    date = actualRecord.date
                }
                
                allData.append((date, item.tm))
            }
        }
        
        return allData
    }
    
    /// Calculate the weight used for a specific week in a past cycle
    /// Uses linear interpolation between starting and ending TM for simplicity
    private func calculateWeight(cycle: CompletedCycle, week: Int, lift: String) -> Double {
        guard let state = appState.programState,
              let weekData = state.lifts[lift]?[week],
              let startTM = cycle.startingMaxes[lift],
              let endTM = cycle.endingMaxes[lift] else { return 0 }
        
        // Linear interpolation of TM across the cycle
        let progress = Double(week - 1) / Double(max(cycle.lastCompletedWeek - 1, 1))
        let currentTM = startTM + (endTM - startTM) * progress
        
        let weight = currentTM * weekData.intensity
        return roundWeight(weight)
    }
    
    private func roundWeight(_ weight: Double) -> Double {
        let increment = appState.settings.roundingIncrement
        guard increment > 0 else { return weight }
        return (weight / increment).rounded() * increment
    }
    
    /// Get all logs including past cycles
    /// Uses stored liftData from CompletedCycle for program-agnostic history display
    private func allLogsForLift(_ lift: String) -> [HistoryLogEntry] {
        var allLogs: [HistoryLogEntry] = []
        
        // Add data from past cycles (in chronological order)
        let sortedCycles = appState.userData.cycleHistory.sorted { $0.startDate < $1.startDate }
        
        for cycle in sortedCycles {
            // Use stored programName directly, fall back to lookup, then use programId as last resort
            let programName = cycle.programName 
                ?? cycle.programId.flatMap { programId in
                    appState.availablePrograms.first { $0.id == programId }?.displayName
                }
                ?? cycle.programId  // Use programId as display name if all else fails
            
            var foundData = false
            
            // First, try to use the stored liftData (preferred, program-agnostic)
            if let liftDataForLift = cycle.liftData[lift], !liftDataForLift.isEmpty {
                foundData = true
                for (week, weekData) in liftDataForLift.sorted(by: { $0.key < $1.key }) {
                    // Get note from any day in this week (check all log types)
                    let note = cycle.logs[lift]?[week]?.values.first(where: { !$0.note.isEmpty })?.note
                    allLogs.append(HistoryLogEntry(
                        cycleNumber: cycle.cycleNumber,
                        week: week,
                        reps: weekData.reps,
                        target: weekData.targetReps,
                        weight: weekData.weight,
                        e1rm: weekData.e1rm,
                        date: cycle.startDate,
                        note: note?.isEmpty == false ? note : nil,
                        programName: programName
                    ))
                }
            }
            
            // Fallback: check SBS-style logs (for legacy cycles without liftData)
            if !foundData, let liftLogs = cycle.logs[lift] {
                for week in 1...cycle.lastCompletedWeek {
                    guard let dayLogs = liftLogs[week] else { continue }
                    for (_, entry) in dayLogs {
                        guard let reps = entry.repsLastSet else { continue }
                        let weight = calculateWeight(cycle: cycle, week: week, lift: lift)
                        guard weight > 0 else { continue }
                        let e1rm = weight * (1.0 + Double(reps) / 30.0)
                        let targetReps = appState.programState?.lifts[lift]?[week]?.repOutTarget ?? 5
                        let note = entry.note.isEmpty ? nil : entry.note
                        
                        allLogs.append(HistoryLogEntry(
                            cycleNumber: cycle.cycleNumber,
                            week: week,
                            reps: reps,
                            target: targetReps,
                            weight: weight,
                            e1rm: e1rm,
                            date: cycle.startDate,
                            note: note,
                            programName: programName
                        ))
                        foundData = true
                    }
                }
            }
            
            // Fallback: check structuredLogs (for structured programs like 531, nSuns, Greyskull)
            if !foundData, let structuredLiftLogs = cycle.structuredLogs[lift] {
                for (week, dayLogs) in structuredLiftLogs.sorted(by: { $0.key < $1.key }) {
                    for (_, entry) in dayLogs {
                        guard !entry.amrapReps.isEmpty else { continue }
                        // Get the AMRAP reps (use the first one available)
                        guard let reps = entry.amrapReps.values.first else { continue }
                        // Get TM from archived tmHistory, or fall back to starting maxes
                        let tm = cycle.tmHistory[lift]?[week] ?? cycle.startingMaxes[lift] ?? 0
                        guard tm > 0 else { continue }
                        // Weight is approximately TM (structured programs often work at 100% or close)
                        let weight = tm
                        let e1rm = weight * (1.0 + Double(reps) / 30.0)
                        // Default target for structured programs (varies by program)
                        let targetReps = 5
                        
                        allLogs.append(HistoryLogEntry(
                            cycleNumber: cycle.cycleNumber,
                            week: week,
                            reps: reps,
                            target: targetReps,
                            weight: weight,
                            e1rm: e1rm,
                            date: cycle.startDate,
                            note: nil,
                            programName: programName
                        ))
                        foundData = true
                    }
                }
            }
            
            // Fallback: check linearLogs (for linear programs like Starting Strength, StrongLifts)
            if !foundData, let linearLiftLogs = cycle.linearLogs[lift] {
                for (week, dayLogs) in linearLiftLogs.sorted(by: { $0.key < $1.key }) {
                    for (_, entry) in dayLogs {
                        let reps = entry.completed ? 5 : 4  // Approximate reps based on success/failure
                        let weight = entry.weight
                        guard weight > 0 else { continue }
                        let e1rm = weight * (1.0 + Double(reps) / 30.0)
                        
                        allLogs.append(HistoryLogEntry(
                            cycleNumber: cycle.cycleNumber,
                            week: week,
                            reps: reps,
                            target: 5,
                            weight: weight,
                            e1rm: e1rm,
                            date: cycle.startDate,
                            note: nil,
                            programName: programName
                        ))
                        foundData = true
                    }
                }
            }
        }
        
        // Add current cycle data
        let currentLogs = logsForCurrentCycle(lift)
        let currentProgramName = appState.programData?.displayName ?? appState.programData?.name
        for log in currentLogs {
            allLogs.append(HistoryLogEntry(
                cycleNumber: appState.currentCycleNumber,
                week: log.week,
                reps: log.reps,
                target: log.target,
                weight: log.weight,
                e1rm: log.e1rm,
                date: appState.userData.currentCycleStartDate,
                note: log.note,
                programName: currentProgramName
            ))
        }
        
        return allLogs
    }
    
    private func logsForCurrentCycle(_ lift: String) -> [(week: Int, reps: Int, target: Int, weight: Double, e1rm: Double, note: String?)] {
        // Use unified lift history to get logs for this lift in the current cycle
        let liftHistory = appState.liftHistory(for: lift)
        let currentCycleStart = appState.userData.currentCycleStartDate
        
        // Filter to current cycle only (after cycle start date)
        let currentCycleRecords = liftHistory.filter { $0.date >= currentCycleStart }
        
        // Group by week and return the best record per week
        var weeklyLogs: [Int: (week: Int, reps: Int, target: Int, weight: Double, e1rm: Double, note: String?)] = [:]
        
        for record in currentCycleRecords {
            let week = record.week ?? 1
            // Parse target from setType (e.g., "5+" -> 5, "3×5" -> 5, "volume" -> 5)
            var target = 5
            if let setType = record.setType {
                if setType.hasSuffix("+") {
                    target = Int(setType.dropLast()) ?? 5
                } else if setType.contains("×") {
                    let parts = setType.components(separatedBy: "×")
                    if parts.count == 2, let reps = Int(parts[1]) {
                        target = reps
                    }
                }
            }
            
            // Keep the entry with the highest E1RM for each week
            if let existing = weeklyLogs[week] {
                if record.estimatedOneRM > existing.e1rm {
                    weeklyLogs[week] = (week, record.reps, target, record.weight, record.estimatedOneRM, nil)
                }
            } else {
                weeklyLogs[week] = (week, record.reps, target, record.weight, record.estimatedOneRM, nil)
            }
        }
        
        // Sort by week and return
        return weeklyLogs.values.sorted { $0.week < $1.week }
    }
}

/// History log entry that includes cycle information
struct HistoryLogEntry: Identifiable {
    let id = UUID()
    let cycleNumber: Int
    let week: Int
    let reps: Int
    let target: Int
    let weight: Double
    let e1rm: Double
    let date: Date
    let note: String?
    let programName: String?  // Program name for this cycle
}

// MARK: - Lift Selector

struct LiftSelector: View {
    let lifts: [String]
    @Binding var selectedLift: String?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lifts, id: \.self) { lift in
                    LiftPill(
                        name: shortName(for: lift),
                        isSelected: selectedLift == lift
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedLift = lift
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func shortName(for lift: String) -> String {
        // Shorten common lift names for pills
        let shortcuts: [String: String] = [
            "Trap Bar Deadlift": "Trap Bar DL",
            "Bench Press": "Bench",
            "Front Squat": "Front Squat",
            "Paused Squat": "Paused Squat",
            "Incline Press": "Incline",
            "Spoto Press": "Spoto",
            "Rack Pull": "Rack Pull",
            "Push Press": "Push Press"
        ]
        return shortcuts[lift] ?? lift
    }
}

struct LiftPill: View {
    let name: String
    let isSelected: Bool
    
    var body: some View {
        Text(name)
            .font(SBSFonts.captionBold())
            .foregroundStyle(isSelected ? .white : SBSColors.textPrimaryFallback)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? SBSColors.accentFallback : SBSColors.surfaceFallback)
            )
    }
}

// MARK: - Progress Chart (E1RM or Training Max)

/// Data point for the chart with index for even spacing
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let index: Int
    let date: Date
    let value: Double
    // Extra info for E1RM tooltip
    var weight: Double?
    var reps: Int?
}

struct ProgressChart: View {
    let liftName: String
    @Binding var displayMode: ChartDisplayMode
    let e1rmData: [(date: Date, e1rm: Double, weight: Double, reps: Int)]
    let tmData: [(date: Date, tm: Double)]
    let useMetric: Bool
    var canAccessE1RM: Bool = true
    var onE1RMLockedTap: (() -> Void)?
    
    // Strength standard bands (optional)
    var showStrengthBands: Bool = false
    var bodyweight: Double = 0
    var isMale: Bool = true
    var ageCategory: AgeCategory = .allAges
    
    @State private var selectedIndex: Int?
    
    /// Chart data values with index for even spacing
    private var chartDataPoints: [ChartDataPoint] {
        switch displayMode {
        case .e1rm:
            guard canAccessE1RM else { return [] }
            return e1rmData.enumerated().map { idx, item in
                ChartDataPoint(index: idx, date: item.date, value: item.e1rm, weight: item.weight, reps: item.reps)
            }
        case .trainingMax:
            return tmData.enumerated().map { idx, item in
                ChartDataPoint(index: idx, date: item.date, value: item.tm)
            }
        }
    }
    
    /// Selected data point for tooltip
    private var selectedDataPoint: ChartDataPoint? {
        guard let idx = selectedIndex else { return nil }
        return chartDataPoints.first { $0.index == idx }
    }
    
    private var chartColor: Color {
        switch displayMode {
        case .e1rm:
            return SBSColors.accentFallback
        case .trainingMax:
            return SBSColors.accentSecondaryFallback
        }
    }
    
    private var latestValue: Double? {
        chartDataPoints.last?.value
    }
    
    private var firstValue: Double? {
        chartDataPoints.first?.value
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            // Header with mode toggle
            VStack(spacing: SBSLayout.paddingSmall) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayMode == .e1rm ? "Estimated 1RM Progress" : "Training Max Progress")
                            .font(SBSFonts.title3())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text(displayMode == .e1rm ? "Based on completed sets" : "Autoregulated from performance")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                    
                    Spacer()
                    
                    if let latest = latestValue {
                        Text(latest.formattedWeight(useMetric: useMetric))
                            .font(SBSFonts.weight())
                            .foregroundStyle(chartColor)
                    }
                }
                
                // Mode toggle picker
                if canAccessE1RM {
                    Picker("Display Mode", selection: $displayMode) {
                        ForEach(ChartDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    // Show E1RM as locked option
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Text("Training Max")
                            .font(SBSFonts.captionBold())
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(SBSColors.accentSecondaryFallback.opacity(0.15))
                            )
                        
                        Button {
                            onE1RMLockedTap?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                Text("Est. 1RM")
                                    .font(SBSFonts.captionBold())
                                PremiumBadge(isCompact: true)
                            }
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(SBSColors.surfaceFallback)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Chart
            if chartDataPoints.count > 1 {
                Chart {
                    ForEach(chartDataPoints) { item in
                        LineMark(
                            x: .value("Record", item.index),
                            y: .value("Value", displayWeight(item.value))
                        )
                        .foregroundStyle(chartColor)
                        .interpolationMethod(.catmullRom)
                        
                        AreaMark(
                            x: .value("Record", item.index),
                            y: .value("Value", displayWeight(item.value))
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [chartColor.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        
                        PointMark(
                            x: .value("Record", item.index),
                            y: .value("Value", displayWeight(item.value))
                        )
                        .foregroundStyle(item.index == selectedIndex ? .white : chartColor)
                        .symbolSize(item.index == selectedIndex ? 120 : 50)
                    }
                    
                    // Selection rule line
                    if let selected = selectedDataPoint {
                        RuleMark(x: .value("Selected", selected.index))
                            .foregroundStyle(chartColor.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        // No labels - points are evenly spaced, tap to see date
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text("\(Int(val))")
                                    .font(SBSFonts.caption())
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedIndex)
                .frame(height: 200)
                .animation(.easeInOut(duration: 0.3), value: displayMode)
                .animation(.easeInOut(duration: 0.15), value: selectedIndex)
                
                // Tooltip for selected point
                if let selected = selectedDataPoint {
                    HStack(spacing: SBSLayout.paddingMedium) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            if displayMode == .e1rm, let weight = selected.weight, let reps = selected.reps {
                                Text("\(weight.formattedWeight(useMetric: useMetric)) × \(reps) reps")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                        }
                        
                        Spacer()
                        
                        Text(selected.value.formattedWeight(useMetric: useMetric))
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(chartColor)
                    }
                    .padding(SBSLayout.paddingSmall)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                            .fill(SBSColors.surfaceFallback)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            } else if chartDataPoints.count == 1 {
                // Single data point - show info instead of chart
                VStack(spacing: 8) {
                    Text("Complete more weeks to see progress chart")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                    
                    if let single = chartDataPoints.first {
                        if displayMode == .e1rm, let weight = single.weight, let reps = single.reps {
                            Text("\(single.date, format: .dateTime.month(.abbreviated).day()): \(Int(weight)) × \(reps) reps")
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        } else {
                            Text("\(single.date, format: .dateTime.month(.abbreviated).day()): TM \(single.value.formattedWeight(useMetric: useMetric))")
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            } else {
                Text("No completed workouts yet")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            }
            
            // Stats row
            if let first = firstValue, let last = latestValue, chartDataPoints.count > 1 {
                HStack(spacing: SBSLayout.paddingLarge) {
                    StatBox(
                        label: displayMode == .e1rm ? "First E1RM" : "Start TM",
                        value: first.formattedWeight(useMetric: useMetric)
                    )
                    
                    StatBox(
                        label: displayMode == .e1rm ? "Latest E1RM" : "Current TM",
                        value: last.formattedWeight(useMetric: useMetric)
                    )
                    
                    StatBox(
                        label: "Progress",
                        value: gainString(from: first, to: last)
                    )
                }
            }
        }
        .padding()
        .sbsCard()
    }
    
    private func displayWeight(_ weight: Double) -> Double {
        useMetric ? weight * 0.453592 : weight
    }
    
    private func gainString(from start: Double, to end: Double) -> String {
        let diff = end - start
        let pct = (diff / start) * 100
        let displayDiff = useMetric ? diff * 0.453592 : diff
        let sign = diff >= 0 ? "+" : ""
        return String(format: "%@%.0f (%@%.1f%%)", sign, displayDiff, sign, pct)
    }
}

struct StatBox: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
            
            Text(value)
                .font(SBSFonts.bodyBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Log History List

struct LogHistoryList: View {
    let liftName: String
    let logs: [HistoryLogEntry]
    let useMetric: Bool
    var showPastCyclesLocked: Bool = false
    var onUnlockTap: (() -> Void)?
    
    /// Group logs by cycle number and include program name
    private var logsByCycle: [(cycleNumber: Int, programName: String?, logs: [HistoryLogEntry])] {
        let grouped = Dictionary(grouping: logs) { $0.cycleNumber }
        return grouped.keys.sorted(by: >).map { cycle in
            let cycleLogs = grouped[cycle]?.sorted { $0.week > $1.week } ?? []
            let programName = cycleLogs.first?.programName
            return (cycle, programName, cycleLogs)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            Text("Workout History")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            if logs.isEmpty {
                Text("No workouts recorded yet")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .padding()
            } else {
                VStack(spacing: SBSLayout.paddingMedium) {
                    ForEach(logsByCycle, id: \.cycleNumber) { cycleGroup in
                        VStack(alignment: .leading, spacing: 8) {
                            // Cycle header with program name
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cycle \(cycleGroup.cycleNumber)")
                                        .font(SBSFonts.captionBold())
                                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                                    
                                    if let programName = cycleGroup.programName {
                                        Text(programName)
                                            .font(SBSFonts.caption())
                                            .foregroundStyle(SBSColors.textTertiaryFallback)
                                    }
                                }
                                
                                Rectangle()
                                    .fill(SBSColors.surfaceFallback)
                                    .frame(height: 1)
                            }
                            
                            // Logs for this cycle
                            ForEach(cycleGroup.logs) { log in
                                LogHistoryRow(
                                    week: log.week,
                                    reps: log.reps,
                                    target: log.target,
                                    weight: log.weight,
                                    e1rm: log.e1rm,
                                    note: log.note,
                                    useMetric: useMetric
                                )
                            }
                        }
                    }
                }
            }
            
            // Show locked past cycles prompt
            if showPastCyclesLocked {
                Button {
                    onUnlockTap?()
                } label: {
                    HStack(spacing: SBSLayout.paddingMedium) {
                        ZStack {
                            Circle()
                                .fill(SBSColors.accentFallback.opacity(0.12))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(SBSColors.accentFallback)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("View Past Cycles")
                                .font(SBSFonts.bodyBold())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text("Unlock full workout history with Premium")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        
                        Spacer()
                        
                        PremiumBadge(isCompact: false)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.accentFallback.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                    .strokeBorder(SBSColors.accentFallback.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .sbsCard()
    }
}

struct LogHistoryRow: View {
    let week: Int
    let reps: Int
    let target: Int
    let weight: Double
    let e1rm: Double
    let note: String?
    let useMetric: Bool
    
    private var diff: Int { reps - target }
    
    private var hasNote: Bool {
        guard let note = note else { return false }
        return !note.isEmpty
    }
    
    @State private var isNoteExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: SBSLayout.paddingSmall) {
                    Text("Week \(week)")
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    // Note indicator
                    if hasNote {
                        Image(systemName: "note.text")
                            .font(.system(size: 12))
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                    }
                }
                
                Spacer()
                
                Text(diffText)
                    .font(SBSFonts.caption())
                    .foregroundStyle(resultColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(resultColor.opacity(0.12))
                    )
            }
            
            HStack {
                // Weight × Reps
                Text("\(weight.formattedWeight(useMetric: useMetric)) × \(reps) reps")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                Spacer()
                
                // Estimated 1RM
                Text("E1RM: \(e1rm.formattedWeight(useMetric: useMetric))")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.accentFallback)
            }
            
            // Note display (if present)
            if hasNote, let note = note {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNoteExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "note.text")
                            .font(.system(size: 12))
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                        
                        Text(note)
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .lineLimit(isNoteExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        if note.count > 60 {
                            Image(systemName: isNoteExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                    .padding(SBSLayout.paddingSmall)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                            .fill(SBSColors.accentSecondaryFallback.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var diffText: String {
        if diff > 0 {
            return "+\(diff) vs target"
        } else if diff < 0 {
            return "\(diff) vs target"
        } else {
            return "Hit target"
        }
    }
    
    private var resultColor: Color {
        if diff >= 0 {
            return SBSColors.success
        } else if diff == -1 {
            return SBSColors.warning
        } else {
            return SBSColors.error
        }
    }
}

// MARK: - Current Cycle TM Progress Card

struct CurrentCycleTMProgressCard: View {
    let appState: AppState
    let onTap: () -> Void
    
    private var currentWeek: Int {
        appState.highestLoggedWeek()
    }
    
    private var startingMaxes: [String: Double] {
        appState.currentCycleStartingMaxes()
    }
    
    private var currentMaxes: [String: Double] {
        appState.finalTrainingMaxes(atWeek: currentWeek)
    }
    
    private var averageGain: Double {
        var totalGain = 0.0
        var count = 0
        
        for lift in startingMaxes.keys {
            guard let start = startingMaxes[lift], start > 0,
                  let current = currentMaxes[lift] else { continue }
            let gain = ((current - start) / start) * 100
            totalGain += gain
            count += 1
        }
        
        return count > 0 ? totalGain / Double(count) : 0
    }
    
    private var totalWeightGained: Double {
        var total = 0.0
        for lift in startingMaxes.keys {
            guard let start = startingMaxes[lift],
                  let current = currentMaxes[lift] else { continue }
            total += (current - start)
        }
        return total
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: SBSLayout.paddingMedium) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SBSColors.accentFallback)
                            
                            Text("Training Max Progress")
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                        }
                        
                        Text("Cycle \(appState.currentCycleNumber) • Week \(currentWeek)")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    Spacer()
                    
                    // Average gain badge
                    if appState.hasLoggedData {
                        HStack(spacing: 2) {
                            Image(systemName: averageGain >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 12, weight: .bold))
                            Text(String(format: "%.1f%%", averageGain))
                                .font(SBSFonts.bodyBold())
                        }
                        .foregroundStyle(averageGain >= 0 ? SBSColors.success : SBSColors.error)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill((averageGain >= 0 ? SBSColors.success : SBSColors.error).opacity(0.15))
                        )
                    }
                }
                
                if appState.hasLoggedData {
                    Divider()
                    
                    // Quick summary of top lifts
                    HStack(spacing: 0) {
                        ForEach(Array(appState.liftNames.prefix(4)), id: \.self) { lift in
                            if let start = startingMaxes[lift], let current = currentMaxes[lift] {
                                let gain = current - start
                                
                                VStack(spacing: 4) {
                                    Text(liftAbbreviation(lift))
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textTertiaryFallback)
                                    
                                    Text(current.formattedWeightShort(useMetric: appState.settings.useMetric))
                                        .font(SBSFonts.number())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                    
                                    HStack(spacing: 1) {
                                        Image(systemName: gain >= 0 ? "arrow.up" : "arrow.down")
                                            .font(.system(size: 8, weight: .bold))
                                        Text(abs(gain).formattedWeightShort(useMetric: appState.settings.useMetric))
                                            .font(SBSFonts.caption())
                                    }
                                    .foregroundStyle(gain >= 0 ? SBSColors.success : SBSColors.error)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    
                    // Tap hint
                    HStack {
                        Spacer()
                        Text("Tap for details")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                } else {
                    // No data yet
                    Text("Complete workouts to track your training max changes")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, SBSLayout.paddingSmall)
                }
            }
            .padding()
            .sbsCard()
        }
        .buttonStyle(.plain)
    }
    
    private func liftAbbreviation(_ lift: String) -> String {
        switch lift.lowercased() {
        case "squat": return "SQ"
        case "bench press": return "BP"
        case "trap bar deadlift": return "DL"
        case "ohp", "overhead press": return "OHP"
        case "front squat": return "FSQ"
        case "paused squat": return "PSQ"
        case "incline press": return "INC"
        case "spoto press": return "SPO"
        case "rack pull": return "RP"
        case "push press": return "PP"
        default:
            return String(lift.prefix(3)).uppercased()
        }
    }
}

// MARK: - TM Progress Detail View

struct TMProgressDetailView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    
    private var currentWeek: Int {
        appState.highestLoggedWeek()
    }
    
    private var startingMaxes: [String: Double] {
        appState.currentCycleStartingMaxes()
    }
    
    private var currentMaxes: [String: Double] {
        appState.finalTrainingMaxes(atWeek: currentWeek)
    }
    
    private var totalGain: Double {
        var total = 0.0
        for lift in startingMaxes.keys {
            guard let start = startingMaxes[lift],
                  let current = currentMaxes[lift] else { continue }
            total += (current - start)
        }
        return total
    }
    
    private var averageGainPercent: Double {
        var totalGain = 0.0
        var count = 0
        
        for lift in startingMaxes.keys {
            guard let start = startingMaxes[lift], start > 0,
                  let current = currentMaxes[lift] else { continue }
            let gain = ((current - start) / start) * 100
            totalGain += gain
            count += 1
        }
        
        return count > 0 ? totalGain / Double(count) : 0
    }
    
    private var hasPRs: Bool {
        appState.liftNames.contains { appState.personalRecord(for: $0) != nil }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SBSLayout.sectionSpacing) {
                    // Summary card
                    summaryCard
                    
                    // Share progress button
                    if appState.hasLoggedData {
                        shareProgressButton
                    }
                    
                    // All lifts breakdown
                    allLiftsSection
                    
                    // Personal Records section
                    personalRecordsSection
                }
                .padding()
            }
            .sbsBackground()
            .navigationTitle("TM Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ProgressShareSheet(
                    summary: buildProgressSummary(),
                    useMetric: appState.settings.useMetric,
                    onDismiss: { showingShareSheet = false }
                )
            }
        }
    }
    
    private var shareProgressButton: some View {
        Button {
            showingShareSheet = true
        } label: {
            HStack(spacing: SBSLayout.paddingSmall) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                
                Text(hasPRs ? "Share Your Progress" : "Share Progress")
                    .font(SBSFonts.button())
            }
            .foregroundStyle(hasPRs ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SBSLayout.paddingMedium)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                    .fill(
                        hasPRs
                            ? LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [SBSColors.accentFallback], startPoint: .leading, endPoint: .trailing)
                    )
            )
        }
    }
    
    private func buildProgressSummary() -> ProgressSummary {
        let lifts: [ProgressSummary.LiftProgress] = appState.liftNames.compactMap { liftName in
            guard let startTM = startingMaxes[liftName],
                  let currentTM = currentMaxes[liftName] else { return nil }
            
            let pr = appState.personalRecord(for: liftName)
            
            return ProgressSummary.LiftProgress(
                name: liftName,
                startingTM: startTM,
                currentTM: currentTM,
                bestE1RM: pr?.estimatedOneRM
            )
        }
        
        let prs: [ProgressSummary.PRProgress] = appState.liftNames.compactMap { liftName in
            guard let pr = appState.personalRecord(for: liftName) else { return nil }
            
            return ProgressSummary.PRProgress(
                liftName: liftName,
                weight: pr.weight,
                reps: pr.reps,
                e1rm: pr.estimatedOneRM,
                date: pr.date
            )
        }
        
        let programName = appState.programData?.displayName ?? appState.programData?.name ?? "Training Program"
        let totalWeeks = appState.weeks.max() ?? 20
        
        return ProgressSummary(
            programName: programName,
            cycleNumber: appState.currentCycleNumber,
            startDate: appState.userData.currentCycleStartDate,
            currentDate: Date(),
            currentWeek: currentWeek,
            totalWeeks: totalWeeks,
            lifts: lifts,
            personalRecords: prs,
            isComplete: currentWeek >= totalWeeks
        )
    }
    
    private var summaryCard: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Cycle")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text("Cycle \(appState.currentCycleNumber)")
                        .font(SBSFonts.title2())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Progress")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text("Week \(currentWeek) of 20")
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
            }
            
            Divider()
            
            HStack(spacing: SBSLayout.paddingLarge) {
                // Average % gain
                VStack(spacing: 4) {
                    Image(systemName: averageGainPercent >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(averageGainPercent >= 0 ? SBSColors.success : SBSColors.error)
                    
                    Text(String(format: "%.1f%%", averageGainPercent))
                        .font(SBSFonts.title2())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Avg TM Change")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                .frame(maxWidth: .infinity)
                
                // Total weight gained
                VStack(spacing: 4) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(SBSColors.accentFallback)
                    
                    Text(totalGain.formattedWeightShort(useMetric: appState.settings.useMetric))
                        .font(SBSFonts.title2())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Total TM Gained")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .sbsCard()
    }
    
    private var allLiftsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            Text("All Lifts")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            VStack(spacing: SBSLayout.paddingSmall) {
                ForEach(appState.liftNames, id: \.self) { lift in
                    CurrentCycleTMRow(
                        liftName: lift,
                        startTM: startingMaxes[lift] ?? 0,
                        currentTM: currentMaxes[lift] ?? 0,
                        personalRecord: appState.personalRecord(for: lift),
                        useMetric: appState.settings.useMetric
                    )
                }
            }
        }
    }
    
    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text("Personal Records")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
            }
            
            let liftsWithPRs = appState.liftNames.filter { appState.personalRecord(for: $0) != nil }
            
            if liftsWithPRs.isEmpty {
                Text("Complete AMRAP sets to track your personal records")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .sbsCard()
            } else {
                VStack(spacing: SBSLayout.paddingSmall) {
                    ForEach(liftsWithPRs, id: \.self) { lift in
                        if let pr = appState.personalRecord(for: lift) {
                            PRRow(liftName: lift, pr: pr, useMetric: appState.settings.useMetric)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Current Cycle TM Row

struct CurrentCycleTMRow: View {
    let liftName: String
    let startTM: Double
    let currentTM: Double
    let personalRecord: PersonalRecord?
    let useMetric: Bool
    
    private var gain: Double { currentTM - startTM }
    private var gainPercent: Double {
        guard startTM > 0 else { return 0 }
        return ((currentTM - startTM) / startTM) * 100
    }
    
    var body: some View {
        HStack {
            // Lift name
            VStack(alignment: .leading, spacing: 2) {
                Text(liftName)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                if personalRecord != nil {
                    PRBadge(small: true)
                }
            }
            
            Spacer()
            
            // Start → Current
            HStack(spacing: SBSLayout.paddingSmall) {
                Text(startTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Text(currentTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.accentFallback)
            }
            
            // Gain
            HStack(spacing: 2) {
                Image(systemName: gain >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                VStack(alignment: .trailing, spacing: 0) {
                    Text(gain >= 0 ? "+\(abs(gain).formattedWeightShort(useMetric: useMetric))" : "-\(abs(gain).formattedWeightShort(useMetric: useMetric))")
                        .font(SBSFonts.captionBold())
                    Text(String(format: "%.1f%%", gainPercent))
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(gain >= 0 ? SBSColors.success : SBSColors.error)
            .frame(width: 55, alignment: .trailing)
        }
        .padding()
        .sbsCard()
    }
}

// MARK: - PR Row

struct PRRow: View {
    let liftName: String
    let pr: PersonalRecord
    let useMetric: Bool
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }
    
    var body: some View {
        HStack {
            // Trophy
            Image(systemName: "trophy.fill")
                .font(.system(size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(liftName)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("\(pr.weight.formattedWeightShort(useMetric: useMetric)) × \(pr.reps) reps")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("E1RM")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Text(pr.estimatedOneRM.formattedWeight(useMetric: useMetric))
                    .font(SBSFonts.number())
                    .foregroundStyle(SBSColors.success)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(Color.yellow.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .strokeBorder(Color.yellow.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Strength Score Card

struct StrengthScoreCard: View {
    let formula: StrengthScoreFormula
    let squatE1RM: Double?
    let benchE1RM: Double?
    let deadliftE1RM: Double?
    let bodyweightKg: Double
    let isMale: Bool
    let useMetric: Bool
    
    // Total in kg
    private var totalKg: Double {
        let squat = (squatE1RM ?? 0) * 0.453592  // Convert from lbs to kg
        let bench = (benchE1RM ?? 0) * 0.453592
        let deadlift = (deadliftE1RM ?? 0) * 0.453592
        return squat + bench + deadlift
    }
    
    // Individual lift values for display
    private var squatDisplay: Double {
        guard let squat = squatE1RM else { return 0 }
        return useMetric ? squat * 0.453592 : squat
    }
    
    private var benchDisplay: Double {
        guard let bench = benchE1RM else { return 0 }
        return useMetric ? bench * 0.453592 : bench
    }
    
    private var deadliftDisplay: Double {
        guard let deadlift = deadliftE1RM else { return 0 }
        return useMetric ? deadlift * 0.453592 : deadlift
    }
    
    private var totalDisplay: Double {
        squatDisplay + benchDisplay + deadliftDisplay
    }
    
    private var score: Double? {
        guard bodyweightKg > 0 && totalKg > 0 else { return nil }
        
        switch formula {
        case .wilks:
            return calculateWilks()
        case .dots:
            return calculateDots()
        case .ipfGL:
            return calculateIPFGL()
        }
    }
    
    private func calculateWilks() -> Double? {
        let x = bodyweightKg
        
        let (a, b, c, d, e, f): (Double, Double, Double, Double, Double, Double)
        
        if isMale {
            a = 47.46178854
            b = 8.472061379
            c = 0.07369410346
            d = -0.001395833811
            e = 7.07665973070743e-6
            f = -1.20804336482315e-8
        } else {
            a = -125.4255398
            b = 13.71219419
            c = -0.03307250631
            d = -0.001050400051
            e = 9.38773881462799e-6
            f = -2.3334613884954e-8
        }
        
        let denominator = a + b*x + c*pow(x,2) + d*pow(x,3) + e*pow(x,4) + f*pow(x,5)
        guard denominator > 0 else { return nil }
        
        return totalKg * (500.0 / denominator)
    }
    
    private func calculateDots() -> Double? {
        let x = bodyweightKg
        
        let (a, b, c, d, e): (Double, Double, Double, Double, Double)
        
        if isMale {
            a = -307.75076
            b = 24.0900756
            c = -0.1918759221
            d = 0.0007391293
            e = -0.000001093
        } else {
            a = -57.96288
            b = 13.6175032
            c = -0.1126655495
            d = 0.0005158568
            e = -0.0000010706
        }
        
        let denominator = a + b*x + c*pow(x,2) + d*pow(x,3) + e*pow(x,4)
        guard denominator > 0 else { return nil }
        
        return totalKg * (500.0 / denominator)
    }
    
    private func calculateIPFGL() -> Double? {
        let (a, b, c): (Double, Double, Double)
        
        if isMale {
            a = 1199.72839
            b = 1025.18162
            c = 0.00921465671
        } else {
            a = 610.32796
            b = 1045.59282
            c = 0.03048036225
        }
        
        let denominator = a - b * exp(-c * bodyweightKg)
        guard denominator > 0 else { return nil }
        
        return totalKg * 100.0 / denominator
    }
    
    private var rating: (text: String, color: Color) {
        guard let score = score else { return ("--", .gray) }
        
        switch formula {
        case .wilks, .dots:
            switch score {
            case 500...: return ("Elite", .purple)
            case 400..<500: return ("Advanced", .blue)
            case 300..<400: return ("Intermediate", .green)
            case 200..<300: return ("Novice", .orange)
            default: return ("Beginner", .gray)
            }
        case .ipfGL:
            switch score {
            case 100...: return ("Elite", .purple)
            case 80..<100: return ("Advanced", .blue)
            case 60..<80: return ("Intermediate", .green)
            case 40..<60: return ("Novice", .orange)
            default: return ("Beginner", .gray)
            }
        }
    }
    
    private var unit: String {
        useMetric ? "kg" : "lb"
    }
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formula.rawValue) Score")
                        .font(SBSFonts.title3())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text(formula.description)
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                
                Spacer()
                
                // Score display
                if let score = score {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f", score))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(formula.color)
                        
                        Text(rating.text)
                            .font(SBSFonts.captionBold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(rating.color)
                            .clipShape(Capsule())
                    }
                }
            }
            
            Divider()
            
            // Lift breakdown
            HStack(spacing: 0) {
                liftColumn(name: "Squat", value: squatDisplay, hasData: squatE1RM != nil)
                liftColumn(name: "Bench", value: benchDisplay, hasData: benchE1RM != nil)
                liftColumn(name: "Deadlift", value: deadliftDisplay, hasData: deadliftE1RM != nil)
                
                // Total
                VStack(spacing: 4) {
                    Text("Total")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(formula.color)
                    
                    if totalDisplay > 0 {
                        Text(formatWeight(totalDisplay))
                            .font(SBSFonts.number())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                    } else {
                        Text("--")
                            .font(SBSFonts.number())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            // Bodyweight info
            HStack {
                Image(systemName: "scalemass")
                    .font(.system(size: 10))
                Text("@ \(formatWeight(useMetric ? bodyweightKg : bodyweightKg * 2.20462)) \(unit) BW")
                    .font(SBSFonts.caption())
                
                Spacer()
                
                Text(isMale ? "Men's" : "Women's")
                    .font(SBSFonts.caption())
            }
            .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(formula.color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .strokeBorder(formula.color.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func liftColumn(name: String, value: Double, hasData: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            if hasData {
                Text(formatWeight(value))
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
            } else {
                Text("--")
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        } else {
            return String(format: "%.1f", weight)
        }
    }
}

#Preview {
    HistoryView(appState: AppState())
}

