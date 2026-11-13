import SwiftUI
import Charts

/// Display mode for the progress chart
enum ChartDisplayMode: String, CaseIterable {
    case e1rm = "Est. 1RM"
    case trainingMax = "Training Max"
}

/// Time period for the volume-by-body-part card
enum VolumePeriod: String, CaseIterable {
    case thisWeek = "This week"
    case last4Weeks = "Last 4 weeks"
    case thisCycle = "This cycle"
    case allTime = "All time"
}

/// Metric for the volume-by-body-part card
enum VolumeMetric: String, CaseIterable {
    case hardSets = "Sets"
    case tonnage = "Tonnage"
}

/// Sort modes for the lift selector pills
enum LiftSortMode: String, CaseIterable {
    case mostRecent = "Most recent"
    case mostData = "Most data"
    case alphabetical = "A–Z"

    var systemImage: String {
        switch self {
        case .mostRecent: return "clock"
        case .mostData: return "chart.bar.fill"
        case .alphabetical: return "textformat.abc"
        }
    }
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
}

/// Identifiable wrapper so share sheets can be presented via `.sheet(item:)`,
/// guaranteeing the image exists when the sheet's content is built
/// (avoids a blank sheet on the first tap).
struct ShareImagePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct HistoryView: View {
    @Bindable var appState: AppState
    @State private var selectedLift: String?
    @State private var showingTMProgress = false
    @State private var chartDisplayMode: ChartDisplayMode = .trainingMax // Default to TM for free users
    @State private var showingPaywall = false
    @State private var sharePayload: ShareImagePayload?
    @Environment(\.colorScheme) private var colorScheme
    @State private var ageCategory: AgeCategory = .allAges
    @State private var selectedStrengthFormula: StrengthScoreFormula = .wilks
    @State private var showStrengthScore = true // Show strength score by default
    @State private var liftSortMode: LiftSortMode = .mostRecent
    @State private var volumePeriod: VolumePeriod = .thisWeek
    @State private var volumeMetric: VolumeMetric = .hardSets

    private let storeManager = StoreManager.shared

    /// Volume-by-body-part is disabled until exercise-name → body-part resolution is
    /// reliable (most logged lifts/accessories currently fall through to "Other").
    /// Flip to `true` to re-enable. See ExerciseLibrary.bodyPart(for:).
    private let showVolumeByBodyPart = false

    /// Classic lifts that should always appear first (in this order)
    private let classicLifts = ["Squat", "Deadlift", "Bench Press", "Overhead Press"]
    
    /// Alternate names for classic lifts for matching
    private let classicLiftAliases: [String: [String]] = [
        "Squat": ["Squat", "Back Squat"],
        "Deadlift": ["Deadlift", "Trap Bar Deadlift"],
        "Bench Press": ["Bench Press", "Bench"],
        "Overhead Press": ["Overhead Press", "OHP", "Press"]
    ]
    
    /// Volume aggregated per body part for the current `volumePeriod` and
    /// `volumeMetric`. Main lifts come from per-set `workoutRecords`;
    /// accessories come from `accessoryHistory`. Returned sorted desc; rows
    /// with zero volume are dropped. A nil body-part bucket holds custom or
    /// unrecognized exercises ("Other" in the UI).
    private var volumeByBodyPart: [(bodyPart: BodyPart?, value: Double)] {
        let (start, end) = volumeDateRange(for: volumePeriod)
        var totals: [BodyPart?: Double] = [:]

        for workout in appState.userData.workoutRecords where workout.date >= start && workout.date < end {
            for exercise in workout.exercises {
                let bp = ExerciseLibrary.shared.bodyPart(for: exercise.lift)
                for set in exercise.sets where set.completed {
                    let reps = set.actualReps ?? 0
                    guard reps > 0 else { continue }
                    switch volumeMetric {
                    case .hardSets:
                        totals[bp, default: 0] += 1
                    case .tonnage:
                        totals[bp, default: 0] += set.weight * Double(reps)
                    }
                }
            }
        }

        for record in appState.userData.accessoryHistory where record.date >= start && record.date < end {
            switch volumeMetric {
            case .hardSets:
                totals[record.bodyPart, default: 0] += Double(record.sets)
            case .tonnage:
                totals[record.bodyPart, default: 0] += record.weight * Double(record.sets) * Double(record.reps)
            }
        }

        return totals
            .filter { $0.value > 0 }
            .map { (bodyPart: $0.key, value: $0.value) }
            .sorted { $0.value > $1.value }
    }

    /// [start, end) date range for a `VolumePeriod`. End is the start of
    /// tomorrow so today's records are always included.
    private func volumeDateRange(for period: VolumePeriod) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        let endOfToday = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: endOfToday) ?? now
        switch period {
        case .thisWeek:
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (start, end)
        case .last4Weeks:
            let start = cal.date(byAdding: .day, value: -28, to: endOfToday) ?? now
            return (start, end)
        case .thisCycle:
            return (appState.userData.currentCycleStartDate, end)
        case .allTime:
            return (.distantPast, end)
        }
    }

    /// Per-lift record count and most-recent activity date. Drives both the
    /// "only show lifts with data" filter and the sort orderings below. Pulls
    /// from `liftHistory` (canonical, dated per-record) and — for paid users —
    /// past cycle logs (using cycle.endDate as the proxy date since per-entry
    /// dates aren't stored in the cycle log dictionaries).
    private var liftStats: [String: (count: Int, lastDate: Date)] {
        var stats: [String: (count: Int, lastDate: Date)] = [:]

        for record in appState.userData.liftHistory {
            let liftName = ExerciseLibrary.canonicalLiftName(record.liftName)
            if let existing = stats[liftName] {
                stats[liftName] = (
                    count: existing.count + 1,
                    lastDate: max(existing.lastDate, record.date)
                )
            } else {
                stats[liftName] = (count: 1, lastDate: record.date)
            }
        }

        if canAccessFullHistory {
            for cycle in appState.userData.cycleHistory {
                let liftsInCycle = Set(cycle.logs.keys)
                    .union(cycle.structuredLogs.keys)
                    .union(cycle.linearLogs.keys)
                for lift in liftsInCycle {
                    var count = 0
                    if let liftLogs = cycle.logs[lift] {
                        for (_, dayLogs) in liftLogs {
                            count += dayLogs.values.filter { $0.repsLastSet != nil }.count
                        }
                    }
                    if let liftLogs = cycle.structuredLogs[lift] {
                        for (_, dayLogs) in liftLogs {
                            count += dayLogs.values.count
                        }
                    }
                    if let liftLogs = cycle.linearLogs[lift] {
                        for (_, dayLogs) in liftLogs {
                            count += dayLogs.values.count
                        }
                    }
                    guard count > 0 else { continue }

                    let liftName = ExerciseLibrary.canonicalLiftName(lift)
                    if let existing = stats[liftName] {
                        stats[liftName] = (
                            count: existing.count + count,
                            lastDate: max(existing.lastDate, cycle.endDate)
                        )
                    } else {
                        stats[liftName] = (count: count, lastDate: cycle.endDate)
                    }
                }
            }
        }

        return stats
    }

    /// Lifts to show in the selector. Filtered to lifts with logged data (no
    /// more clutter from program lifts the user has never touched) and sorted
    /// by `liftSortMode`. The classic-lifts-first rule applies only in the
    /// alphabetical mode — the data-driven modes are purely data-driven.
    private var orderedLifts: [String] {
        let stats = liftStats
        let liftsWithData = Array(stats.keys)

        switch liftSortMode {
        case .mostRecent:
            return liftsWithData.sorted { a, b in
                let da = stats[a]?.lastDate ?? .distantPast
                let db = stats[b]?.lastDate ?? .distantPast
                if da != db { return da > db }
                return a < b
            }
        case .mostData:
            return liftsWithData.sorted { a, b in
                let ca = stats[a]?.count ?? 0
                let cb = stats[b]?.count ?? 0
                if ca != cb { return ca > cb }
                return a < b
            }
        case .alphabetical:
            var result: [String] = []
            var used = Set<String>()
            for classicLift in classicLifts {
                if let aliases = classicLiftAliases[classicLift] {
                    for alias in aliases {
                        if stats.keys.contains(alias) && !used.contains(alias) {
                            result.append(alias)
                            used.insert(alias)
                            break
                        }
                    }
                }
            }
            let remaining = liftsWithData.filter { !used.contains($0) }.sorted()
            result.append(contentsOf: remaining)
            return result
        }
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
        appState.userData.personalRecords.canonicalLiftValue(for: liftName)?.estimatedOneRM
    }
    
    /// Get bodyweight in kg for strength score calculations
    private var bodyweightInKg: Double {
        guard let bw = appState.settings.bodyweight, bw > 0 else { return 0 }
        // Settings bodyweight is always stored in lbs
        return bw * 0.453592
    }
    
    /// Sort menu for the lift selector
    private var liftSortMenu: some View {
        Menu {
            ForEach(LiftSortMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        liftSortMode = mode
                    }
                } label: {
                    HStack {
                        Label(mode.rawValue, systemImage: mode.systemImage)
                        if mode == liftSortMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HistoryControlLabel(title: liftSortMode.rawValue, systemImage: liftSortMode.systemImage, showsMenuChevron: true)
        }
        .accessibilityLabel("Sort lifts: \(liftSortMode.rawValue)")
    }

    /// Whether there's enough data to generate a shareable progress image
    private var canShareLiftProgress: Bool {
        guard let lift = selectedLift else { return false }
        return !allE1RMData(for: lift).isEmpty
    }

    /// Share lift progress button
    private var shareLiftProgressButton: some View {
        Button {
            generateLiftProgressShareImage()
        } label: {
            HistoryControlLabel(title: "Share progress", systemImage: "square.and.arrow.up", tint: .orangeText)
        }
        .buttonStyle(.plain)
        .disabled(!canShareLiftProgress)
        .opacity(canShareLiftProgress ? 1 : 0.4)
    }

    /// Prompt to set bodyweight for strength standards
    private var setBodyweightPrompt: some View {
        NavigationLink {
            SettingsView(appState: appState)
        } label: {
            HistoryControlLabel(title: "Set bodyweight for scores", systemImage: "scalemass", showsChevron: true)
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
            HistoryControlLabel(
                title: showStrengthScore ? "Hide score" : "Show score",
                systemImage: showStrengthScore ? "medal.fill" : "medal",
                isSelected: showStrengthScore
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
                        if formula == selectedStrengthFormula {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HistoryControlLabel(title: selectedStrengthFormula.rawValue, showsMenuChevron: true)
        }
        .accessibilityLabel("Score formula: \(selectedStrengthFormula.rawValue)")
    }

    /// Locked strength score button for non-premium users
    private var lockedStrengthScoreButton: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack(spacing: SBSLayout.space2) {
                HistoryControlLabel(title: "Strength scores", systemImage: "lock.fill")
                SBSBadge(text: "Pro", variant: .pro)
            }
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSLayout.space6) {
                    SBSTabHeader("History")

                    // Current Cycle TM Progress Card
                    CurrentCycleTMProgressCard(
                        appState: appState,
                        // With no history at all, the empty state below has the one prompt
                        showsEmptyAction: !orderedLifts.isEmpty,
                        onTap: { showingTMProgress = true }
                    )

                    if hasAnySessionHistory {
                        historyLinks
                    }

                    // Volume by Body Part card (disabled — see showVolumeByBodyPart)
                    if showVolumeByBodyPart {
                        VolumeByBodyPartCard(
                            period: $volumePeriod,
                            metric: $volumeMetric,
                            rows: volumeByBodyPart,
                            useMetric: appState.settings.useMetric
                        )
                    }

                    // Lift selector with sort menu
                    if !orderedLifts.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            SBSSectionEyebrow("Lifts") {
                                liftSortMenu
                            }

                            LiftSelector(
                                lifts: orderedLifts,
                                selectedLift: $selectedLift
                            )
                        }
                    }

                    // Progress Chart with mode toggle
                    if let lift = selectedLift {
                        VStack(alignment: .leading, spacing: SBSLayout.space3) {
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
                                ageCategory: ageCategory,
                                progressKind: appState.progressKind(for: lift),
                                onGoToWorkout: { appState.goToWorkoutTab() }
                            )

                            // Strength score display and share button
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: SBSLayout.space2) {
                                    strengthScoreControls
                                    Spacer(minLength: 0)
                                    shareLiftProgressButton
                                }
                                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                                    HStack(spacing: SBSLayout.space2) {
                                        strengthScoreControls
                                    }
                                    shareLiftProgressButton
                                }
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

                        // Log history for this lift (includes past cycles)
                        // Free users only see current cycle
                        LogHistoryList(
                            liftName: lift,
                            logs: canAccessFullHistory ? allLogsForLift(lift) : currentCycleLogsOnly(lift),
                            useMetric: appState.settings.useMetric,
                            barWeight: appState.barWeight(for: lift),
                            showPastCyclesLocked: !canAccessFullHistory && hasPastCycles,
                            onUnlockTap: { showingPaywall = true },
                            onGoToWorkout: { appState.goToWorkoutTab() }
                        )
                    } else if orderedLifts.isEmpty {
                        ContentUnavailableView {
                            Label("No Lifts Yet", systemImage: "chart.line.uptrend.xyaxis")
                                .font(SBSFonts.heading())
                                .foregroundStyle(Color.ink)
                        } description: {
                            Text("Log your first workout and your progress will show up here.")
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.inkSecondary)
                        } actions: {
                            // The screen's one action, so the primary button
                            Button { appState.goToWorkoutTab() } label: {
                                SBSButtonTitle("Go to Workout")
                            }
                            .buttonStyle(SBSPrimaryButtonStyle())
                            .accessibilityIdentifier("historyGoToWorkoutButton")
                        }
                        .padding(.top, SBSLayout.space8)
                    } else {
                        ContentUnavailableView {
                            Label("Select a Lift", systemImage: "chart.line.uptrend.xyaxis")
                                .font(SBSFonts.heading())
                                .foregroundStyle(Color.ink)
                        } description: {
                            Text("Choose a lift above to see your progress.")
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.inkSecondary)
                        }
                        .padding(.top, SBSLayout.space8)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, SBSLayout.space4)
            }
            .sbsBackground()
            .sbsTabRoot("History")
            .sheet(isPresented: $showingTMProgress) {
                TMProgressDetailView(appState: appState)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(triggeredByFeature: canAccessE1RM ? .fullHistory : .e1rmChart)
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: [payload.image])
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

    /// Show/hide, formula, or the way to unlock or enable strength scores
    @ViewBuilder
    private var strengthScoreControls: some View {
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
            lockedStrengthScoreButton
        }
    }

    /// Check if there are any past cycles
    private var hasPastCycles: Bool {
        !appState.userData.cycleHistory.isEmpty
    }

    private var hasAnySessionHistory: Bool {
        !appState.userData.workoutRecords.isEmpty || hasPastCycles
            || !appState.userData.accessoryHistory.isEmpty || appState.hasLoggedData
    }

    /// The ways into the per-workout and accessory screens
    private var historyLinks: some View {
        SBSListGroup(title: "Sessions") {
            NavigationLink {
                WorkoutSessionsView(appState: appState)
            } label: {
                SBSListRow("Workouts", showsChevron: true) {
                    Text("Every session, with its exercises and results")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("historySessionsLink")

            if !appState.userData.accessoryHistory.isEmpty {
                SBSRowDivider()
                NavigationLink {
                    AccessoryHistoryView(appState: appState)
                } label: {
                    SBSListRow("Accessories", showsChevron: true) {
                        Text("Your logged accessory work, by exercise")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("historyAccessoriesLink")
            }
        }
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

        // ImageRenderer (via View.snapshot()) lays out synchronously, so the
        // image is ready immediately — no settling delay or off-window race.
        sharePayload = ShareImagePayload(image: shareableCard.snapshot(colorScheme: colorScheme))
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
                date: log.date,
                note: log.note,
                programName: appState.programData?.displayName ?? appState.programData?.name,
                missedTarget: log.missedTarget
            )
        }
    }
    
    /// The lift pills use canonical names, but program data is keyed by the program's
    /// own spelling ("Close-Grip Bench"), so program lookups need that spelling back.
    private func programLiftName(for lift: String) -> String {
        let canonical = ExerciseLibrary.canonicalLiftName(lift)
        return appState.allConfiguredLifts.first { ExerciseLibrary.canonicalLiftName($0) == canonical } ?? lift
    }

    /// Get all e1RM data from unified lift history (program-agnostic)
    /// Prioritizes WorkoutRecords (new system), falls back to unified history and legacy reconstruction
    private func allE1RMData(for lift: String) -> [(date: Date, e1rm: Double, weight: Double, reps: Int)] {
        var allData: [(date: Date, e1rm: Double, weight: Double, reps: Int)] = []
        
        // Add data from past cycles (in chronological order)
        let sortedCycles = appState.userData.cycleHistory.sorted { $0.startDate < $1.startDate }
        
        for cycle in sortedCycles {
            var foundData = false
            
            // PRIORITY 1: Use WorkoutRecords (new self-contained system)
            if !cycle.workoutRecords.isEmpty {
                for workout in cycle.workoutRecords {
                    for exercise in workout.exercises where ExerciseLibrary.canonicalLiftName(exercise.lift) == ExerciseLibrary.canonicalLiftName(lift) {
                        // Use the computed E1RM from the exercise record
                        if let e1rm = exercise.estimatedOneRM {
                            // Get the best set for weight/reps data
                            if let bestSet = exercise.sets.filter({ $0.actualReps != nil }).max(by: { ($0.actualReps ?? 0) < ($1.actualReps ?? 0) }) {
                                allData.append((workout.date, e1rm, bestSet.weight, bestSet.actualReps ?? 0))
                                foundData = true
                            }
                        }
                    }
                }
            }
            
            // PRIORITY 2: Use liftData (pre-calculated, legacy)
            if !foundData, let liftDataForLift = cycle.liftData.canonicalLiftValue(for: lift), !liftDataForLift.isEmpty {
                for (week, weekData) in liftDataForLift.sorted(by: { $0.key < $1.key }) {
                    let date = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: cycle.startDate) ?? cycle.startDate
                    allData.append((date, weekData.e1rm, weekData.weight, weekData.reps))
                    foundData = true
                }
            }
            
            // FALLBACK: calculate from logs + current program state (may not work if program changed)
            if !foundData, let liftLogs = cycle.logs.canonicalLiftValue(for: lift) {
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
        let currentCycleStart = appState.userData.currentCycleStartDate
        let currentCycleWorkouts = appState.userData.workoutRecords.filter { $0.date >= currentCycleStart }
        
        // PRIORITY 1: Use current cycle WorkoutRecords
        var currentE1RMFound = false
        for workout in currentCycleWorkouts {
            for exercise in workout.exercises where ExerciseLibrary.canonicalLiftName(exercise.lift) == ExerciseLibrary.canonicalLiftName(lift) {
                if let e1rm = exercise.estimatedOneRM {
                    if let bestSet = exercise.sets.filter({ $0.actualReps != nil }).max(by: { ($0.actualReps ?? 0) < ($1.actualReps ?? 0) }) {
                        allData.append((workout.date, e1rm, bestSet.weight, bestSet.actualReps ?? 0))
                        currentE1RMFound = true
                    }
                }
            }
        }
        
        // FALLBACK: Use unified lift history if no WorkoutRecords
        if !currentE1RMFound {
            let unifiedHistory = appState.liftHistory(for: lift)
            let currentCycleRecords = unifiedHistory.filter { $0.date >= currentCycleStart }
            
            for record in currentCycleRecords {
                allData.append((record.date, record.estimatedOneRM, record.weight, record.reps))
            }
        }
        
        return allData
    }
    
    /// Get all training max data across all cycles for the chart
    /// Prioritizes WorkoutRecords (new system), falls back to tmHistory/reconstruction (legacy)
    private func allTMData(for lift: String) -> [(date: Date, tm: Double)] {
        var allData: [(date: Date, tm: Double)] = []
        
        // Add data from past cycles (in chronological order)
        let sortedCycles = appState.userData.cycleHistory.sorted { $0.startDate < $1.startDate }
        
        for cycle in sortedCycles {
            var foundData = false
            
            // PRIORITY 1: Use WorkoutRecords (new self-contained system)
            if !cycle.workoutRecords.isEmpty {
                // Get TM from workout records for this lift, grouped by week
                var weeklyTM: [Int: (date: Date, tm: Double)] = [:]
                
                for workout in cycle.workoutRecords {
                    for exercise in workout.exercises where ExerciseLibrary.canonicalLiftName(exercise.lift) == ExerciseLibrary.canonicalLiftName(lift) {
                        guard exercise.trainingMax > 0 else { continue }
                        // Keep latest TM for each week
                        if weeklyTM[workout.week] == nil || workout.date > weeklyTM[workout.week]!.date {
                            weeklyTM[workout.week] = (workout.date, exercise.trainingMax)
                        }
                    }
                }
                
                if !weeklyTM.isEmpty {
                    foundData = true
                    for (_, data) in weeklyTM.sorted(by: { $0.key < $1.key }) {
                        allData.append((data.date, data.tm))
                    }
                }
            }
            
            // PRIORITY 2: Use tmHistory (pre-calculated, legacy)
            if !foundData, let tmHistoryForLift = cycle.tmHistory.canonicalLiftValue(for: lift), !tmHistoryForLift.isEmpty {
                foundData = true
                for (week, tm) in tmHistoryForLift.sorted(by: { $0.key < $1.key }) {
                    guard tm > 0 else { continue }  // Skip zero TMs
                    let date = Calendar.current.date(byAdding: .weekOfYear, value: week - 1, to: cycle.startDate) ?? cycle.startDate
                    allData.append((date, tm))
                }
            }
            
            // FALLBACK 1: check SBS-style logs (for legacy cycles without tmHistory)
            if !foundData, let liftLogs = cycle.logs.canonicalLiftValue(for: lift) {
                let startTM = cycle.startingMaxes.canonicalLiftValue(for: lift) ?? 0
                let endTM = cycle.endingMaxes.canonicalLiftValue(for: lift) ?? startTM
                
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
            
            // FALLBACK 2: check structuredLogs (for structured programs)
            if !foundData, let structuredLiftLogs = cycle.structuredLogs.canonicalLiftValue(for: lift) {
                let startTM = cycle.startingMaxes.canonicalLiftValue(for: lift) ?? 0
                let endTM = cycle.endingMaxes.canonicalLiftValue(for: lift) ?? startTM
                
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
            
            // FALLBACK 3: check linearLogs (for linear programs)
            if !foundData, let linearLiftLogs = cycle.linearLogs.canonicalLiftValue(for: lift) {
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
        let currentCycleStart = appState.userData.currentCycleStartDate
        let currentCycleWorkouts = appState.userData.workoutRecords.filter { $0.date >= currentCycleStart }
        
        // PRIORITY 1: Use current cycle WorkoutRecords
        var currentWeeklyTM: [Int: (date: Date, tm: Double)] = [:]
        for workout in currentCycleWorkouts {
            for exercise in workout.exercises where ExerciseLibrary.canonicalLiftName(exercise.lift) == ExerciseLibrary.canonicalLiftName(lift) {
                guard exercise.trainingMax > 0 else { continue }
                if currentWeeklyTM[workout.week] == nil || workout.date > currentWeeklyTM[workout.week]!.date {
                    currentWeeklyTM[workout.week] = (workout.date, exercise.trainingMax)
                }
            }
        }
        
        if !currentWeeklyTM.isEmpty {
            for (_, data) in currentWeeklyTM.sorted(by: { $0.key < $1.key }) {
                allData.append((data.date, data.tm))
            }
        } else {
            // FALLBACK: Use legacy TM calculation
            let currentTMData = appState.allTrainingMaxes(for: programLiftName(for: lift))
            
            // Get the starting max for this cycle (for the chart's starting point)
            let startingMax = appState.currentCycleStartingMaxes().canonicalLiftValue(for: lift) ?? 0
            
            // If we have no TM data yet but have a valid starting max, add it as the first point
            if currentTMData.isEmpty && startingMax > 0 && allData.isEmpty {
                allData.append((currentCycleStart, startingMax))
            }
            
            // Filter to only include weeks with actual logs (check SBS, structured, AND linear logs)
            for item in currentTMData {
                guard item.tm > 0 else { continue }  // Skip zero TMs
                
                let hasSBSLog = appState.userData.logs.canonicalLiftValue(for: lift)?[item.week]?.values.contains { $0.repsLastSet != nil } == true
                let hasStructuredLog = appState.userData.structuredLogs.canonicalLiftValue(for: lift)?[item.week]?.values.contains { !$0.amrapReps.isEmpty } == true
                let hasLinearLog = appState.userData.linearLogs.canonicalLiftValue(for: lift)?[item.week] != nil
                
                if hasSBSLog || hasStructuredLog || hasLinearLog {
                    var date = Calendar.current.date(byAdding: .weekOfYear, value: item.week - 1, to: currentCycleStart) ?? currentCycleStart
                    
                    // Check if we have actual date from lift history
                    let liftHistory = appState.liftHistory(for: lift)
                    if let actualRecord = liftHistory.first(where: { $0.week == item.week }) {
                        date = actualRecord.date
                    }
                    
                    allData.append((date, item.tm))
                }
            }
        }
        
        return allData
    }
    
    /// Calculate the weight used for a specific week in a past cycle
    /// Uses linear interpolation between starting and ending TM for simplicity
    private func calculateWeight(cycle: CompletedCycle, week: Int, lift: String) -> Double {
        guard let state = appState.programState,
              let weekData = state.lifts.canonicalLiftValue(for: lift)?[week],
              let startTM = cycle.startingMaxes.canonicalLiftValue(for: lift),
              let endTM = cycle.endingMaxes.canonicalLiftValue(for: lift) else { return 0 }
        
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
    /// Prioritizes WorkoutRecords (new system), falls back to liftData/reconstruction (legacy)
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
            
            // PRIORITY 1: Use WorkoutRecords (new self-contained system)
            if !cycle.workoutRecords.isEmpty {
                // The best set per week for this lift
                let weeklyBest = WeeklyBestSet.perWeek(records: cycle.workoutRecords, lift: lift)
                if !weeklyBest.isEmpty {
                    foundData = true
                    for best in weeklyBest {
                        allLogs.append(HistoryLogEntry(
                            cycleNumber: cycle.cycleNumber,
                            week: best.week,
                            reps: best.reps,
                            target: best.target,
                            weight: best.weight,
                            e1rm: best.e1rm,
                            date: best.date,
                            note: best.note,
                            programName: programName,
                            missedTarget: best.missedTarget
                        ))
                    }
                }
            }

            // PRIORITY 2: Use liftData (pre-calculated, legacy)
            if !foundData, let liftDataForLift = cycle.liftData.canonicalLiftValue(for: lift), !liftDataForLift.isEmpty {
                foundData = true
                for (week, weekData) in liftDataForLift.sorted(by: { $0.key < $1.key }) {
                    // Get note from any day in this week (check all log types)
                    let note = cycle.logs.canonicalLiftValue(for: lift)?[week]?.values.first(where: { !$0.note.isEmpty })?.note
                    allLogs.append(HistoryLogEntry(
                        cycleNumber: cycle.cycleNumber,
                        week: week,
                        reps: weekData.reps,
                        target: weekData.targetReps,
                        weight: weekData.weight,
                        e1rm: weekData.e1rm,
                        date: nil,
                        note: note?.isEmpty == false ? note : nil,
                        programName: programName
                    ))
                }
            }
            
            // FALLBACK 1: check SBS-style logs (for legacy cycles without liftData)
            if !foundData, let liftLogs = cycle.logs.canonicalLiftValue(for: lift) {
                for week in 1...cycle.lastCompletedWeek {
                    guard let dayLogs = liftLogs[week] else { continue }
                    for (_, entry) in dayLogs {
                        guard let reps = entry.repsLastSet else { continue }
                        let weight = calculateWeight(cycle: cycle, week: week, lift: lift)
                        guard weight > 0 else { continue }
                        let e1rm = weight * (1.0 + Double(reps) / 30.0)
                        let targetReps = appState.programState?.lifts.canonicalLiftValue(for: lift)?[week]?.repOutTarget ?? 5
                        let note = entry.note.isEmpty ? nil : entry.note
                        
                        allLogs.append(HistoryLogEntry(
                            cycleNumber: cycle.cycleNumber,
                            week: week,
                            reps: reps,
                            target: targetReps,
                            weight: weight,
                            e1rm: e1rm,
                            date: nil,
                            note: note,
                            programName: programName
                        ))
                        foundData = true
                    }
                }
            }
            
            // FALLBACK 2: check structuredLogs (for structured programs like 531, nSuns, Greyskull)
            if !foundData, let structuredLiftLogs = cycle.structuredLogs.canonicalLiftValue(for: lift) {
                for (week, dayLogs) in structuredLiftLogs.sorted(by: { $0.key < $1.key }) {
                    for (_, entry) in dayLogs {
                        guard !entry.amrapReps.isEmpty else { continue }
                        // Get the AMRAP reps (use the first one available)
                        guard let reps = entry.amrapReps.values.first else { continue }
                        // Get TM from archived tmHistory, or fall back to starting maxes
                        let tm = cycle.tmHistory.canonicalLiftValue(for: lift)?[week] ?? cycle.startingMaxes.canonicalLiftValue(for: lift) ?? 0
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
                            date: nil,
                            note: nil,
                            programName: programName
                        ))
                        foundData = true
                    }
                }
            }
            
            // FALLBACK 3: check linearLogs (for linear programs like Starting Strength, StrongLifts)
            if !foundData, let linearLiftLogs = cycle.linearLogs.canonicalLiftValue(for: lift) {
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
                            date: nil,
                            note: nil,
                            programName: programName,
                            missedTarget: !entry.completed
                        ))
                        foundData = true
                    }
                }
            }
        }
        
        // Add current cycle data from WorkoutRecords first, then fallback
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
                date: log.date,
                note: log.note,
                programName: currentProgramName,
                missedTarget: log.missedTarget
            ))
        }
        
        return allLogs
    }
    
    private func logsForCurrentCycle(_ lift: String) -> [(week: Int, reps: Int, target: Int, weight: Double, e1rm: Double, note: String?, date: Date, missedTarget: Bool)] {
        let currentCycleStart = appState.userData.currentCycleStartDate
        var weeklyLogs: [Int: (week: Int, reps: Int, target: Int, weight: Double, e1rm: Double, note: String?, date: Date, missedTarget: Bool)] = [:]

        // PRIORITY 1: Use WorkoutRecords (new self-contained system)
        let currentCycleWorkouts = appState.userData.workoutRecords.filter { $0.date >= currentCycleStart }
        for best in WeeklyBestSet.perWeek(records: currentCycleWorkouts, lift: lift) {
            weeklyLogs[best.week] = (best.week, best.reps, best.target, best.weight, best.e1rm, best.note, best.date, best.missedTarget)
        }

        // FALLBACK: Use unified lift history (legacy)
        if weeklyLogs.isEmpty {
            let liftHistory = appState.liftHistory(for: lift)
            let currentCycleRecords = liftHistory.filter { $0.date >= currentCycleStart }
            
            for record in currentCycleRecords {
                let week = record.week ?? 1
                // A failed linear session saves an assumed rep count, marked in its set type
                let missed = record.setType?.hasSuffix("(failed)") == true
                // Parse target from setType (e.g., "5+" -> 5, "3×5" -> 5, "volume" -> 5)
                var target = 5
if let setType = record.setType {
                    if setType.hasSuffix("+") {
                        target = Int(setType.dropLast()) ?? 5
                    } else if setType.contains("×") {
                        let parts = setType.components(separatedBy: "×")
                        // Tolerates the "(failed)" suffix on a linear set type
                        if parts.count == 2, let reps = Int(parts[1].prefix { $0.isNumber }) {
                            target = reps
                        }
}
                }
                
                // Keep the entry with the highest E1RM for each week
                if let existing = weeklyLogs[week] {
                    if record.estimatedOneRM > existing.e1rm {
                        weeklyLogs[week] = (week, missed ? target : record.reps, target, record.weight, record.estimatedOneRM, nil, record.date, missed)
                    }
                } else {
                    weeklyLogs[week] = (week, missed ? target : record.reps, target, record.weight, record.estimatedOneRM, nil, record.date, missed)
                }
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
    /// When this result happened. Nil for older cycles that didn't save per-session dates.
    let date: Date?
    let note: String?
    let programName: String?  // Program name for this cycle
    /// A missed linear session, whose saved rep count is assumed rather than measured
    var missedTarget: Bool = false
}

// MARK: - Controls

/// A small hairline control for History's toolbar rows: menus, toggles, links.
/// Selected is orange-soft with an orange-text edge; the text stays as tinted.
struct HistoryControlLabel: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .ink
    var isSelected: Bool = false
    var showsMenuChevron: Bool = false
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: SBSLayout.space1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(SBSFonts.caption().weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(SBSFonts.caption().weight(.semibold))
                .lineLimit(1)
            if showsMenuChevron {
                SBSChevron(systemName: "chevron.down")
            } else if showsChevron {
                SBSChevron()
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, SBSLayout.space3)
        .frame(minHeight: 32)
        .selectionCell(isSelected)
        .contentShape(Rectangle())
    }
}

// MARK: - Volume by Body Part

struct VolumeByBodyPartCard: View {
    @Binding var period: VolumePeriod
    @Binding var metric: VolumeMetric
    let rows: [(bodyPart: BodyPart?, value: Double)]
    let useMetric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space4) {
            HStack(alignment: .center) {
                Text("Volume by Body Part")
                    .font(SBSFonts.heading())
                    .foregroundStyle(Color.ink)
                Spacer()
                periodMenu
            }

            SBSSegmentedControl(options: VolumeMetric.allCases, selection: $metric) { $0.rawValue }

            if rows.isEmpty {
                Text("Log a workout to see your volume.")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.vertical, SBSLayout.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let maxValue = rows.first?.value ?? 1
                VStack(spacing: SBSLayout.space2) {
                    ForEach(rows.indices, id: \.self) { i in
                        VolumeRow(
                            label: rows[i].bodyPart?.rawValue ?? "Other",
                            value: rows[i].value,
                            maxValue: maxValue,
                            metric: metric,
                            useMetric: useMetric
                        )
                    }
                }
            }
        }
        .padding(SBSLayout.space4)
        .card()
    }

    private var periodMenu: some View {
        Menu {
            ForEach(VolumePeriod.allCases, id: \.self) { p in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        period = p
                    }
                } label: {
                    HStack {
                        Text(p.rawValue)
                        if p == period {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HistoryControlLabel(title: period.rawValue, showsMenuChevron: true)
        }
    }
}

private struct VolumeRow: View {
    let label: String
    let value: Double
    let maxValue: Double
    let metric: VolumeMetric
    let useMetric: Bool

    var body: some View {
        HStack(spacing: SBSLayout.space2) {
            Text(label)
                .font(SBSFonts.body())
                .foregroundStyle(Color.ink)
                .frame(width: 90, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.surfaceRaised)
                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: max(2, geo.size.width * CGFloat(value / max(maxValue, 1))))
                }
            }
            .frame(height: 8)

            Text(formattedValue)
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.ink)
                .frame(minWidth: 60, alignment: .trailing)
        }
    }

    private var formattedValue: String {
        switch metric {
        case .hardSets:
            let sets = Int(value.rounded())
            return "\(sets) \(sets == 1 ? "set" : "sets")"
        case .tonnage:
            let converted = useMetric ? value * 0.453592 : value
            let unit = useMetric ? "kg" : "lb"
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            let str = formatter.string(from: NSNumber(value: converted)) ?? String(format: "%.0f", converted)
            return "\(str) \(unit)"
        }
    }
}

// MARK: - Lift Selector

struct LiftSelector: View {
    let lifts: [String]
    @Binding var selectedLift: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SBSLayout.space2) {
                ForEach(lifts, id: \.self) { lift in
                    SBSChip(title: shortName(for: lift), isSelected: selectedLift == lift) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedLift = lift
                        }
                    }
                }
            }
            // Room for the selected chip's edge
            .padding(.vertical, 1)
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

/// One series in ink; the latest (or tapped) point is the one orange mark.
/// The legend names both, so neither rests on colour.
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
    var progressKind: LiftProgressKind = .autoregulatedTrainingMax
    var onGoToWorkout: (() -> Void)?

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

    /// The tapped point, else the latest: the one point drawn in orange
    private var highlightedIndex: Int? {
        selectedDataPoint?.index ?? chartDataPoints.last?.index
    }

    private var seriesName: String {
        displayMode == .e1rm ? "Est. 1RM" : progressKind.chartModeLabel
    }

    private var latestValue: Double? {
        chartDataPoints.last?.value
    }

    private var firstValue: Double? {
        chartDataPoints.first?.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space4) {
            // Header with mode toggle
            VStack(alignment: .leading, spacing: SBSLayout.space3) {
                SBSAdaptiveStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayMode == .e1rm ? "Estimated 1RM Progress" : progressKind.chartTitle)
                            .font(SBSFonts.heading())
                            .foregroundStyle(Color.ink)

                        Text(displayMode == .e1rm ? "Based on completed sets" : progressKind.chartSubtitle)
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let latest = latestValue {
                        Text(latest.formattedWeight(useMetric: useMetric))
                            .font(SBSFonts.number())
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                            .accessibilityLabel("Latest \(seriesName): \(latest.formattedWeight(useMetric: useMetric))")
                    }
                }

                // Mode toggle
                if canAccessE1RM {
                    SBSSegmentedControl(options: ChartDisplayMode.allCases, selection: $displayMode) { mode in
                        mode == .trainingMax ? progressKind.chartModeLabel : mode.rawValue
                    }
                } else {
                    // Est. 1RM is a locked option
                    HStack(spacing: SBSLayout.space1) {
                        Text(progressKind.chartModeLabel)
                            .font(SBSFonts.caption().weight(.semibold))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, SBSLayout.space2)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .selectionCell(true)
                            .accessibilityAddTraits(.isSelected)

                        Button {
                            onE1RMLockedTap?()
                        } label: {
                            HStack(spacing: SBSLayout.space1) {
                                Image(systemName: "lock.fill")
                                    .font(SBSFonts.caption())
                                Text("Est. 1RM")
                                    .font(SBSFonts.caption().weight(.semibold))
                                SBSBadge(text: "Pro", variant: .pro)
                            }
                            .foregroundStyle(Color.inkSecondary)
                            .padding(.horizontal, SBSLayout.space2)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .selectionCell(false)
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
                            y: .value(seriesName, displayWeight(item.value))
                        )
                        .foregroundStyle(Color.ink)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                    }

                    // Selection rule line
                    if let selected = selectedDataPoint {
                        RuleMark(x: .value("Selected", selected.index))
                            .foregroundStyle(Color.inkSecondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }

                    ForEach(chartDataPoints) { item in
                        PointMark(
                            x: .value("Record", item.index),
                            y: .value(seriesName, displayWeight(item.value))
                        )
                        .symbol {
                            ChartPointSymbol(isHighlighted: item.index == highlightedIndex)
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: SBSLayout.strokeHairline))
                            .foregroundStyle(Color.hairline)
                        // No labels - points are evenly spaced, tap to see date
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: SBSLayout.strokeHairline))
                            .foregroundStyle(Color.hairline)
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text("\(Int(val))")
                                    .font(SBSFonts.numberSmall())
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedIndex)
                .frame(height: 200)
                .animation(.easeInOut(duration: 0.3), value: displayMode)
                .animation(.easeInOut(duration: 0.15), value: selectedIndex)

                legend

                // Tooltip for selected point
                if let selected = selectedDataPoint {
                    HStack(spacing: SBSLayout.space4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(SBSFonts.numberSmall())
                                .foregroundStyle(Color.ink)

                            if displayMode == .e1rm, let weight = selected.weight, let reps = selected.reps {
                                Text("\(weight.formattedWeight(useMetric: useMetric)) × \(reps) reps")
                                    .font(SBSFonts.numberSmall())
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }

                        Spacer()

                        Text(selected.value.formattedWeight(useMetric: useMetric))
                            .font(SBSFonts.number())
                            .foregroundStyle(Color.ink)
                    }
                    .padding(SBSLayout.space2)
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                            .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
                    )
                    .transition(.opacity)
                }
            } else if chartDataPoints.count == 1 {
                // Single data point - show info instead of chart
                VStack(spacing: SBSLayout.space2) {
                    Text("Complete more weeks to see progress chart")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)

                    if let single = chartDataPoints.first {
                        if displayMode == .e1rm, let weight = single.weight, let reps = single.reps {
                            Text("\(single.date, format: .dateTime.month(.abbreviated).day()): \(weight.formattedWeight(useMetric: useMetric)) × \(reps) reps")
                                .font(SBSFonts.numberSmall())
                                .foregroundStyle(Color.ink)
                        } else {
                            Text("\(single.date, format: .dateTime.month(.abbreviated).day()): \(progressKind == .workingWeight ? "" : "TM ")\(single.value.formattedWeight(useMetric: useMetric))")
                                .font(SBSFonts.numberSmall())
                                .foregroundStyle(Color.ink)
                        }
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: SBSLayout.space2) {
                    Text(displayMode == .e1rm && !tmData.isEmpty ? "No rep results for this lift yet" : "No completed workouts yet")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)

                    if let onGoToWorkout {
                        Button("Go to Workout", action: onGoToWorkout)
                            .font(SBSFonts.caption().weight(.semibold))
                            .foregroundStyle(Color.orangeText)
                    }
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
            }

            // Stats row
            if let first = firstValue, let last = latestValue, chartDataPoints.count > 1 {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: SBSLayout.space3) { stats(first: first, last: last) }
                    VStack(alignment: .leading, spacing: SBSLayout.space3) { stats(first: first, last: last) }
                }
            }
        }
        .padding(SBSLayout.space4)
        .card()
    }

    /// Names the line and the orange point
    private var legend: some View {
        HStack(spacing: SBSLayout.space4) {
            HStack(spacing: SBSLayout.space1) {
                Rectangle()
                    .fill(Color.ink)
                    .frame(width: 16, height: 2)
                Text(seriesName)
            }
            HStack(spacing: SBSLayout.space1) {
                ChartPointSymbol(isHighlighted: true)
                Text(selectedDataPoint == nil ? "Latest" : "Selected")
            }
        }
        .font(SBSFonts.caption())
        .foregroundStyle(Color.inkSecondary)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func stats(first: Double, last: Double) -> some View {
        StatBox(
            label: displayMode == .e1rm ? "First Est. 1RM" : progressKind.chartStartLabel,
            value: first.formattedWeight(useMetric: useMetric)
        )

        StatBox(
            label: displayMode == .e1rm ? "Latest Est. 1RM" : progressKind.chartLatestLabel,
            value: last.formattedWeight(useMetric: useMetric)
        )

        StatBox(
            label: "Progress",
            value: gainString(from: first, to: last)
        )
    }

    private func displayWeight(_ weight: Double) -> Double {
        useMetric ? weight * 0.453592 : weight
    }

    private func gainString(from start: Double, to end: Double) -> String {
        let diff = end - start
        guard abs(diff) >= 0.01 else { return "No change" }
        let sign = diff >= 0 ? "+" : "-"
        // From 0 added weight on a bodyweight lift there's no percentage to give
        guard start > 0 else { return "\(sign)\(abs(diff).formattedWeightShort(useMetric: useMetric))" }
        let pct = (diff / start) * 100
        return "\(sign)\(abs(diff).formattedWeightShort(useMetric: useMetric)) (\(sign)\(String(format: "%.1f", abs(pct)))%)"
    }
}

/// A chart point: a small ink-edged square, or the one orange point (latest or tapped).
struct ChartPointSymbol: View {
    let isHighlighted: Bool

    var body: some View {
        let size: CGFloat = isHighlighted ? 11 : 7
        Rectangle()
            .fill(isHighlighted ? Color.orangeFill : Color.surface)
            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: isHighlighted ? 1.5 : 1))
            .frame(width: size, height: size)
    }
}

struct StatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space1) {
            SBSEyebrow(label)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(2)

            Text(value)
                .font(SBSFonts.numberSmall().weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Log History List

struct LogHistoryList: View {
    let liftName: String
    let logs: [HistoryLogEntry]
    let useMetric: Bool
    var barWeight: Double = 45
    var showPastCyclesLocked: Bool = false
    var onUnlockTap: (() -> Void)?
    var onGoToWorkout: (() -> Void)?

    /// Group logs by cycle number and include program name
    private var logsByCycle: [(cycleNumber: Int, programName: String?, logs: [HistoryLogEntry])] {
        let grouped = Dictionary(grouping: logs) { $0.cycleNumber }
        return grouped.keys.sorted(by: >).map { cycle in
            let cycleLogs = grouped[cycle]?.sorted { $0.week > $1.week } ?? []
            let programName = cycleLogs.first?.programName
            return (cycle, programName, cycleLogs)
        }
    }

    /// The best set by estimated 1RM: the record, so it carries the PR badge.
    /// Nothing to beat with a single result, and a missed session's reps are assumed.
    private var recordID: UUID? {
        let measured = logs.filter { !$0.missedTarget }
        guard measured.count > 1 else { return nil }
        return measured.max { $0.e1rm < $1.e1rm }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space3) {
            VStack(alignment: .leading, spacing: SBSLayout.space1) {
                SBSSectionEyebrow("Best sets")

                if !logs.isEmpty {
                    Text("Your top set each week, by estimated 1RM")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            if logs.isEmpty {
                VStack(spacing: SBSLayout.space2) {
                    Text("No workouts recorded yet")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)

                    if let onGoToWorkout {
                        Button("Go to Workout", action: onGoToWorkout)
                            .font(SBSFonts.caption().weight(.semibold))
                            .foregroundStyle(Color.orangeText)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(SBSLayout.space4)
                .card()
            } else {
                let record = recordID
                LazyVStack(alignment: .leading, spacing: SBSLayout.space4) {
                    ForEach(logsByCycle, id: \.cycleNumber) { cycleGroup in
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            // Cycle eyebrow with program name
                            SBSEyebrow(cycleTitle(cycleGroup.cycleNumber, program: cycleGroup.programName))
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(2)

                            VStack(spacing: 0) {
                                ForEach(Array(cycleGroup.logs.enumerated()), id: \.element.id) { index, log in
                                    if index > 0 {
                                        SBSRowDivider()
                                    }
                                    LogHistoryRow(
                                        week: log.week,
                                        reps: log.reps,
                                        target: log.target,
                                        weight: log.weight,
                                        e1rm: log.e1rm,
                                        note: log.note,
                                        useMetric: useMetric,
                                        date: log.date,
                                        missedTarget: log.missedTarget,
                                        isRecord: log.id == record,
                                        barWeight: barWeight
                                    )
                                }
                            }
                            .card()
                        }
                    }
                }
            }

            // Show locked past cycles prompt
            if showPastCyclesLocked {
                Button {
                    onUnlockTap?()
                } label: {
                    SBSListRow("View Past Cycles") {
                        Text("Unlock full workout history with Premium")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    } trailing: {
                        SBSBadge(text: "Pro", variant: .pro)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cycleTitle(_ cycle: Int, program: String?) -> String {
        guard let program, !program.isEmpty else { return "Cycle \(cycle)" }
        return "Cycle \(cycle) · \(program)"
    }
}

/// A best-set row: the week and a PR tag, the date and estimated 1RM in
/// number-small, the result against target as glyph and words, the compact
/// plate strip, and the set as the trailing number.
struct LogHistoryRow: View {
    let week: Int
    let reps: Int
    let target: Int
    let weight: Double
    let e1rm: Double
    let note: String?
    let useMetric: Bool
    /// The workout this set came from, when the saved data knows it
    var date: Date? = nil
    var missedTarget: Bool = false
    /// The best estimated 1RM in this lift's history
    var isRecord: Bool = false
    var barWeight: Double = 45

    private var diff: Int { reps - target }

    private var hasNote: Bool {
        guard let note = note else { return false }
        return !note.isEmpty
    }

    @State private var isNoteExpanded: Bool = false

    /// "Nov 4 · e1RM 262 lb". No estimate for a missed session, whose rep count is assumed.
    private var detailLine: String? {
        var parts: [String] = []
        if let date { parts.append(date.historyDateText) }
        if !missedTarget { parts.append("e1RM \(e1rm.formattedWeight(useMetric: useMetric))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var plates: [Plate]? {
        // Bodyweight and sub-bar loads have nothing to show on a bar
        guard weight > barWeight else { return nil }
        return PlateCalculator(barWeight: barWeight, useMetric: useMetric).calculate(totalWeight: weight).platesPerSide
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space1) {
            SBSAdaptiveStack(alignment: .firstTextBaseline) {
                HStack(spacing: SBSLayout.space2) {
                    Text("Week \(week)")
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)

                    if isRecord {
                        PRBadge()
                    }

                    if hasNote {
                        Image(systemName: "note.text")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                            .accessibilityLabel("Has a note")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The set itself: the row's value
                Text("\(weight.formattedWeightShort(useMetric: useMetric)) × \(reps)")
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .accessibilityLabel("\(weight.formattedWeight(useMetric: useMetric)) × \(reps) reps")
            }

            if let detailLine {
                SBSRowSubtitle(detailLine)
            }

            HStack(spacing: SBSLayout.space2) {
                resultLabel
                Spacer(minLength: 0)
                if let plates {
                    PlateStrip(plates: plates, height: PlateStrip.rowHeight)
                }
            }

            // Note display (if present)
            if hasNote, let note = note {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNoteExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: SBSLayout.space2) {
                        Image(systemName: "note.text")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)

                        Text(note)
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(isNoteExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        if note.count > 60 {
                            SBSChevron(systemName: isNoteExpanded ? "chevron.up" : "chevron.down")
                        }
                    }
                    .padding(SBSLayout.space2)
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
                }
                .buttonStyle(.plain)
                .padding(.top, SBSLayout.space1)
            }
        }
        .padding(.vertical, SBSLayout.space3)
        .padding(.horizontal, SBSLayout.space4)
    }

    /// The result against target: glyph and words, coloured to match
    private var resultLabel: some View {
        HStack(spacing: SBSLayout.space1) {
            Image(systemName: resultGlyph)
                .font(SBSFonts.numberSmall().weight(.bold))
                .accessibilityHidden(true)
            Text(diffText)
                .font(SBSFonts.numberSmall())
        }
        .foregroundStyle(resultColor)
    }

    private var diffText: String {
        if missedTarget { return "Missed" }
        if diff > 0 {
            return "+\(diff) vs target"
        } else if diff < 0 {
            return "\(diff) vs target"
        } else {
            return "Hit target"
        }
    }

    private var resultGlyph: String {
        if missedTarget { return "xmark" }
        if diff > 0 { return "arrow.up" }
        if diff == 0 { return "checkmark" }
        return "arrow.down"
    }

    private var resultColor: Color {
        if missedTarget { return Color.warning }
        if diff >= 0 {
            return Color.success
        } else if diff == -1 {
            return Color.warning
        } else {
            return Color.danger
        }
    }
}

// MARK: - Current Cycle TM Progress Card

struct CurrentCycleTMProgressCard: View {
    let appState: AppState
    var showsEmptyAction: Bool = true
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: SBSLayout.space2, alignment: .leading),
              count: dynamicTypeSize.isAccessibilitySize ? 2 : 4)
    }

    private var currentWeek: Int {
        appState.highestLoggedWeek()
    }

    var body: some View {
        // Computed once per render: this replays the program's progression
        let summary = appState.currentCycleProgress()

        if appState.hasLoggedData {
            Button(action: onTap) {
                card(summary)
            }
            .buttonStyle(.plain)
        } else {
            card(summary)
        }
    }

    private func card(_ summary: CycleProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.space3) {
            // Header
            SBSAdaptiveStack(alignment: .top) {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    SBSEyebrow("Cycle \(appState.currentCycleNumber) · Week \(currentWeek)")
                        .foregroundStyle(Color.inkSecondary)

                    Text(summary.cardTitle)
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Average gain
                if appState.hasLoggedData && summary.showsAverageBadge {
                    SBSChangeLabel(
                        text: String(format: "%.1f%%", abs(summary.averagePercent)),
                        isUp: summary.averagePercent >= 0
                    )
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 0 : SBSLayout.space1)
                }
            }

            if appState.hasLoggedData {
                SBSRowDivider()

                // Every main lift, in program order
                LazyVGrid(columns: columns, alignment: .leading, spacing: SBSLayout.space3) {
                    ForEach(summary.lifts) { progress in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ExerciseLibrary.shortName(for: progress.lift))
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(1)

                            Text(progress.current.formattedWeightShort(useMetric: appState.settings.useMetric))
                                .font(SBSFonts.number())
                                .foregroundStyle(Color.ink)

                            changeLabel(progress)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                // Tap hint
                HStack(spacing: SBSLayout.space1) {
                    Spacer()
                    Text("Tap for details")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                    SBSChevron()
                }
            } else {
                // No data yet
                Text(summary.emptyMessage)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.leading)

                if showsEmptyAction {
                    Button("Go to Workout") { appState.goToWorkoutTab() }
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.orangeText)
                }
            }
        }
        .padding(SBSLayout.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func changeLabel(_ progress: LiftCycleProgress) -> some View {
        if progress.kind == .fixedTrainingMax {
            Text("Fixed")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        } else if progress.hasChange {
            SBSChangeLabel(
                text: abs(progress.gain).formattedWeightShort(useMetric: appState.settings.useMetric),
                isUp: progress.gain > 0
            )
        } else {
            Text("No change")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
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

    /// Computed once when the sheet opens: it replays the program's progression
    @State private var summary = CycleProgressSummary(lifts: [])

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSLayout.space6) {
                    // Summary card
                    summaryCard

                    // Share progress: the sheet's one action
                    if appState.hasLoggedData {
                        shareProgressButton
                    }

                    // All lifts breakdown
                    allLiftsSection

                    // Personal Records section
                    personalRecordsSection
                }
                .padding(SBSLayout.space4)
            }
            .sbsBackground()
            .navigationTitle(summary.detailTitle)
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
            .onAppear {
                summary = appState.currentCycleProgress()
            }
        }
    }

    private var shareProgressButton: some View {
        Button {
            showingShareSheet = true
        } label: {
            HStack(spacing: SBSLayout.space2) {
                Image(systemName: "square.and.arrow.up")
                    .font(SBSFonts.button())
                SBSButtonTitle("Share Progress")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SBSPrimaryButtonStyle())
    }

    private func buildProgressSummary() -> ProgressSummary {
        let lifts: [ProgressSummary.LiftProgress] = summary.lifts.map { progress in
            ProgressSummary.LiftProgress(
                name: progress.lift,
                startingTM: progress.start,
                currentTM: progress.current,
                bestE1RM: appState.personalRecord(for: progress.lift)?.estimatedOneRM
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
        VStack(alignment: .leading, spacing: SBSLayout.space4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    SBSEyebrow("Current cycle")
                        .foregroundStyle(Color.inkSecondary)
                    Text("Cycle \(appState.currentCycleNumber)")
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.ink)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SBSLayout.space1) {
                    SBSEyebrow("Progress")
                        .foregroundStyle(Color.inkSecondary)
                    Text("Week \(currentWeek) of \(appState.weeks.max() ?? 20)")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.ink)
                }
            }

            SBSRowDivider()

            if summary.isFixedThroughCycle {
                Text(summary.explanation)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: SBSLayout.space4) {
                    // Average % gain
                    VStack(alignment: .leading, spacing: SBSLayout.space1) {
                        HStack(spacing: SBSLayout.space1) {
                            changeIcon
                            Text(String(format: "%.1f%%", abs(summary.averagePercent)))
                                .font(SBSFonts.numberLarge())
                                .foregroundStyle(Color.ink)
                        }

                        Text(summary.averageLabel)
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    // Total weight gained
                    VStack(alignment: .leading, spacing: SBSLayout.space1) {
                        Text("\(summary.totalGain < 0 ? "-" : "")\(abs(summary.totalGain).formattedWeightShort(useMetric: appState.settings.useMetric))")
                            .font(SBSFonts.numberLarge())
                            .foregroundStyle(Color.ink)

                        Text(summary.totalLabel)
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(SBSLayout.space4)
        .card()
    }

    /// Direction as a glyph beside the number, in success or danger
    @ViewBuilder
    private var changeIcon: some View {
        if abs(summary.averagePercent) < 0.05 {
            Image(systemName: "minus")
                .font(SBSFonts.number())
                .foregroundStyle(Color.inkSecondary)
                .accessibilityLabel("No change")
        } else {
            let isUp = summary.averagePercent > 0
            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                .font(SBSFonts.number().weight(.bold))
                .foregroundStyle(isUp ? Color.success : Color.danger)
                .accessibilityLabel(isUp ? "Up" : "Down")
        }
    }

    private var allLiftsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("All lifts")

            if !summary.isFixedThroughCycle {
                Text(summary.explanation)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(summary.lifts.enumerated()), id: \.element.id) { index, progress in
                    if index > 0 {
                        SBSRowDivider()
                    }
                    CurrentCycleTMRow(
                        liftName: progress.lift,
                        startTM: progress.start,
                        currentTM: progress.current,
                        personalRecord: appState.personalRecord(for: progress.lift),
                        useMetric: appState.settings.useMetric,
                        kind: progress.kind
                    )
                }
            }
            .card()
        }
    }

    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("Personal records")

            let liftsWithPRs = appState.liftNames.filter { appState.personalRecord(for: $0) != nil }

            if liftsWithPRs.isEmpty {
                Text("Complete workouts to track your personal records")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .padding(SBSLayout.space4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(liftsWithPRs.enumerated()), id: \.element) { index, lift in
                        if let pr = appState.personalRecord(for: lift) {
                            if index > 0 {
                                SBSRowDivider()
                            }
                            PRRow(liftName: lift, pr: pr, useMetric: appState.settings.useMetric)
                        }
                    }
                }
                .card()
            }
        }
    }
}

// MARK: - Current Cycle TM Row

/// A row in a hairline group: lift and PR tag, start → current, the change.
struct CurrentCycleTMRow: View {
    let liftName: String
    let startTM: Double
    let currentTM: Double
    let personalRecord: PersonalRecord?
    let useMetric: Bool
    var kind: LiftProgressKind = .autoregulatedTrainingMax

    private var hasChange: Bool { abs(gain) >= 0.01 }
    private var gain: Double { currentTM - startTM }
    private var gainPercent: Double {
        guard startTM > 0 else { return 0 }
        return ((currentTM - startTM) / startTM) * 100
    }

    var body: some View {
        SBSAdaptiveStack {
            // Lift name
            HStack(spacing: SBSLayout.space2) {
                Text(liftName)
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.ink)

                if personalRecord != nil {
                    PRBadge(small: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if kind == .fixedTrainingMax {
                // Held through the cycle, so there's no start and end to compare
                VStack(alignment: .trailing, spacing: 0) {
                    Text(currentTM.formattedWeightShort(useMetric: useMetric))
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.ink)
                    Text("Fixed")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
            } else {
                HStack(spacing: SBSLayout.space3) {
                // Start → Current
                HStack(spacing: SBSLayout.space1) {
                    Text(startTM.formattedWeightShort(useMetric: useMetric))
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)

                    Image(systemName: "arrow.right")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)
                        .accessibilityLabel("to")

                    Text(currentTM.formattedWeightShort(useMetric: useMetric))
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.ink)
                }

                // Gain
                Group {
                    if hasChange {
                        VStack(alignment: .trailing, spacing: 0) {
                            SBSChangeLabel(text: abs(gain).formattedWeightShort(useMetric: useMetric), isUp: gain >= 0)
                            Text(String(format: "%.1f%%", abs(gainPercent)))
                                .font(SBSFonts.numberSmall())
                                .foregroundStyle(Color.inkSecondary)
                        }
                    } else {
                        Text("—")
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)
                            .accessibilityLabel("No change")
                    }
                }
                .frame(minWidth: 56, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, SBSLayout.space3)
        .padding(.horizontal, SBSLayout.space4)
        .frame(minHeight: 56)
    }
}

// MARK: - PR Row

/// A personal record row: the lift, the set in number-small, the estimate as the value.
struct PRRow: View {
    let liftName: String
    let pr: PersonalRecord
    let useMetric: Bool

    var body: some View {
        SBSListRow(liftName) {
            SBSRowSubtitle("\(pr.weight.formattedWeightShort(useMetric: useMetric)) × \(pr.reps) reps")
        } trailing: {
            VStack(alignment: .trailing, spacing: 2) {
                SBSEyebrow("Est. 1RM")
                    .foregroundStyle(Color.inkSecondary)

                Text(pr.estimatedOneRM.formattedWeight(useMetric: useMetric))
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.ink)
            }
        }
        .accessibilityElement(children: .combine)
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

    private var isPartialTotal: Bool {
        squatE1RM == nil || benchE1RM == nil || deadliftE1RM == nil
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
            a = -216.0475144
            b = 16.2606339
            c = -0.002388645
            d = -0.00113732
            e = 7.01863e-6
            f = -1.291e-8
        } else {
            a = 594.31747775582
            b = -27.23842536447
            c = 0.82112226871
            d = -0.00930733913
            e = 4.731582e-5
            f = -9.054e-8
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
    
    /// The rating is a word on a standard badge: no colour per level
    private var rating: String {
        guard let score = score else { return "--" }

        switch formula {
        case .wilks, .dots:
            switch score {
            case 500...: return "Elite"
            case 400..<500: return "Advanced"
            case 300..<400: return "Intermediate"
            case 200..<300: return "Novice"
            default: return "Beginner"
            }
        case .ipfGL:
            switch score {
            case 100...: return "Elite"
            case 80..<100: return "Advanced"
            case 60..<80: return "Intermediate"
            case 40..<60: return "Novice"
            default: return "Beginner"
            }
        }
    }

    private var unit: String {
        useMetric ? "kg" : "lb"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space4) {
            // Header
            HStack(alignment: .top, spacing: SBSLayout.space3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formula.rawValue) Score")
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.ink)

                    Text(formula.description)
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Score display
                if let score = score {
                    VStack(alignment: .trailing, spacing: SBSLayout.space1) {
                        Text(String(format: "%.1f", score))
                            .font(SBSFonts.numberLarge())
                            .foregroundStyle(Color.ink)

                        // A rating is only meaningful for a full squat/bench/deadlift total
                        SBSBadge(text: isPartialTotal ? "Partial total" : rating)
                    }
                }
            }

            SBSRowDivider()

            // Lift breakdown
            HStack(alignment: .top, spacing: SBSLayout.space2) {
                liftColumn(name: "Squat", value: squatDisplay, hasData: squatE1RM != nil)
                liftColumn(name: "Bench", value: benchDisplay, hasData: benchE1RM != nil)
                liftColumn(name: "Deadlift", value: deadliftDisplay, hasData: deadliftE1RM != nil)
                liftColumn(name: "Total", value: totalDisplay, hasData: totalDisplay > 0)
            }

            // Bodyweight info
            HStack {
                Text("@ \(formatWeight(useMetric ? bodyweightKg : bodyweightKg * 2.20462)) \(unit) BW")
                    .font(SBSFonts.numberSmall())

                Spacer()

                Text(isMale ? "Men's" : "Women's")
                    .font(SBSFonts.caption())
            }
            .foregroundStyle(Color.inkSecondary)
        }
        .padding(SBSLayout.space4)
        .card()
    }

    private func liftColumn(name: String, value: Double, hasData: Bool) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.space1) {
            SBSEyebrow(name)
                .foregroundStyle(Color.inkSecondary)

            Text(hasData ? formatWeight(value) : "--")
                .font(SBSFonts.numberSmall().weight(.semibold))
                .foregroundStyle(hasData ? Color.ink : Color.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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

