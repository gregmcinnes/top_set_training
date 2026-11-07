import SwiftUI

struct PastCyclesView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCycle: CompletedCycle?
    @State private var showingDeleteAlert = false
    @State private var cycleToDelete: CompletedCycle?
    
    var body: some View {
        NavigationStack {
            Group {
                if appState.cycleHistory.isEmpty {
                    emptyState
                } else {
                    cycleList
                }
            }
            .navigationTitle("Past Cycles")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedCycle) { cycle in
                CycleDetailView(
                    cycle: cycle,
                    useMetric: appState.settings.useMetric,
                    accessoryHistory: appState.userData.accessoryHistory
                )
            }
            .alert("Delete Cycle?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let cycle = cycleToDelete {
                        appState.deleteCycle(id: cycle.id)
                    }
                }
            } message: {
                Text("This will permanently delete all data from this cycle. This cannot be undone.")
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: SBSLayout.space6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(SBSFonts.titleLarge())
                .foregroundStyle(Color.inkSecondary)
                .accessibilityHidden(true)

            Text("No Past Cycles")
                .font(SBSFonts.title())
                .foregroundStyle(Color.ink)

            Text("When you complete a training cycle and start a new one, your history will appear here.")
                .font(SBSFonts.body())
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SBSLayout.space6)

            // The screen's one action
            Button {
                dismiss()
                appState.goToWorkoutTab()
            } label: {
                SBSButtonTitle("Go to Workout")
            }
            .buttonStyle(SBSPrimaryButtonStyle())
        }
        .padding(SBSLayout.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg.ignoresSafeArea())
    }

    private var cycleList: some View {
        List {
            ForEach(appState.cycleHistory) { cycle in
                CycleRowView(cycle: cycle, useMetric: appState.settings.useMetric)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCycle = cycle
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            cycleToDelete = cycle
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .sbsListRows()
        }
        .sbsGroupedList()
    }
}

// MARK: - Cycle Row View

struct CycleRowView: View {
    let cycle: CompletedCycle
    let useMetric: Bool
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var summaryColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: SBSLayout.space2, alignment: .leading),
              count: dynamicTypeSize.isAccessibilitySize ? 2 : 4)
    }

    private var durationText: String {
        let weeks = cycle.lastCompletedWeek
        return "\(weeks) week\(weeks == 1 ? "" : "s")"
    }
    
    private var averageTMGain: Double {
        var totalGain = 0.0
        var count = 0
        for lift in cycle.startingMaxes.keys {
            if let gain = cycle.tmProgression(for: lift) {
                totalGain += gain
                count += 1
            }
        }
        return count > 0 ? totalGain / Double(count) : 0
    }
    
    var body: some View {
        HStack(spacing: SBSLayout.space3) {
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                SBSAdaptiveStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cycle \(cycle.cycleNumber)")
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.ink)

                        if let programName = cycle.programName, !programName.isEmpty {
                            Text(programName)
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Average TM gain
                    if averageTMGain != 0 {
                        SBSChangeLabel(text: String(format: "%.1f%%", abs(averageTMGain)), isUp: averageTMGain >= 0)
                    }
                }

                SBSRowSubtitle("\(dateFormatter.string(from: cycle.startDate)) · \(durationText)")

                // Quick summary of every lift
                LazyVGrid(columns: summaryColumns, spacing: SBSLayout.space2) {
                    ForEach(cycle.summaryLifts, id: \.self) { lift in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ExerciseLibrary.shortName(for: lift))
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(1)
                            Text((cycle.endingMaxes[lift] ?? 0).formattedWeightShort(useMetric: useMetric))
                                .font(SBSFonts.numberSmall().weight(.semibold))
                                .foregroundStyle(Color.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            SBSChevron()
        }
        .padding(.vertical, SBSLayout.space2)
    }
}

// MARK: - Cycle Detail View

struct CycleDetailView: View {
    let cycle: CompletedCycle
    let useMetric: Bool
    /// Accessories aren't archived with a cycle, so they're matched by date
    var accessoryHistory: [AccessoryRecord] = []
    @Environment(\.dismiss) private var dismiss

    /// Home opens this screen for free users too, so per-workout detail needs its own gate
    private var canViewSessions: Bool {
        StoreManager.shared.canAccess(.fullHistory)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSLayout.space6) {
                    // Summary card
                    summaryCard
                    
                    // TM progression for each lift
                    tmProgressionSection
                    
                    // Weekly logs breakdown
                    weeklyLogsSection

                    // Each workout in this cycle
                    if canViewSessions {
                        sessionsSection
                    }
                }
                .padding(SBSLayout.space4)
            }
            .sbsBackground()
            .navigationTitle("Cycle \(cycle.cycleNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var summaryCard: some View {
        VStack(spacing: SBSLayout.space4) {
            HStack(alignment: .top) {
                summaryValue("Duration", "\(cycle.lastCompletedWeek) week\(cycle.lastCompletedWeek == 1 ? "" : "s")", alignment: .leading)
                Spacer()
                summaryValue("Completed", dateFormatter.string(from: cycle.endDate), alignment: .trailing)
            }

            SBSRowDivider()

            HStack(alignment: .top) {
                summaryValue("Started", dateFormatter.string(from: cycle.startDate), alignment: .leading)
                Spacer()
                summaryValue("Total Workouts", "\(totalLoggedWorkouts)", alignment: .trailing)
            }
        }
        .padding(SBSLayout.space4)
        .card()
    }

    private func summaryValue(_ label: String, _ value: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: SBSLayout.space1) {
            SBSEyebrow(label)
                .foregroundStyle(Color.inkSecondary)
            Text(value)
                .font(SBSFonts.number())
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var totalLoggedWorkouts: Int {
        // Prefer the self-contained workout records (one per logged session) when present.
        if !cycle.workoutRecords.isEmpty {
            return cycle.workoutRecords.count
        }

        // Fall back to counting logged entries across every logging style so structured
        // (nSuns/5-3-1/GZCLP) and linear (StrongLifts/Starting Strength) cycles aren't shown as "0".
        var count = 0
        for (_, weekLogs) in cycle.logs {
            for (_, dayLogs) in weekLogs {
                count += dayLogs.values.filter { $0.repsLastSet != nil }.count
            }
        }
        for (_, weekLogs) in cycle.structuredLogs {
            for (_, dayLogs) in weekLogs {
                count += dayLogs.values.filter { !$0.amrapReps.isEmpty }.count
            }
        }
        for (_, weekLogs) in cycle.linearLogs {
            for (_, dayLogs) in weekLogs {
                count += dayLogs.count
            }
        }
        return count
    }
    
    /// Linear lifts move their working weight, not a training max
    private var progressionTitle: String {
        let lifts = cycle.progressedLifts
        let linearCount = lifts.filter { cycle.usedLinearProgression(for: $0) }.count
        if linearCount == 0 { return "Training Max Progression" }
        return linearCount == lifts.count ? "Working Weight Progression" : "Lift Progression"
    }

    private var tmProgressionSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow(progressionTitle)

            VStack(spacing: 0) {
                ForEach(Array(cycle.progressedLifts.enumerated()), id: \.element) { index, lift in
                    if index > 0 {
                        SBSRowDivider()
                    }
                    TMProgressionRow(
                        liftName: lift,
                        startTM: cycle.startingMaxes[lift] ?? 0,
                        endTM: cycle.endingMaxes[lift] ?? 0,
                        useMetric: useMetric,
                        // A linear cycle's end value is its last logged weight
                        endLabel: cycle.usedLinearProgression(for: lift) ? "Last" : "End"
                    )
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        let sessions = HistorySessionBuilder.sessions(for: cycle, accessoryHistory: accessoryHistory)
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                SBSSectionEyebrow("Workouts")

                LazyVStack(spacing: SBSLayout.space2) {
                    ForEach(sessions) { session in
                        NavigationLink {
                            WorkoutSessionDetailView(session: session, useMetric: useMetric)
                        } label: {
                            WorkoutSessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("historySessionRow")
                    }
                }
            }
        }
    }

    /// Per-lift weekly performance labels, unified across SBS/structured/linear logging styles.
    private struct WeeklyLiftPerformance: Identifiable {
        let lift: String
        let labelsByWeek: [Int: String]
        var id: String { lift }
    }

    /// The number of weeks to render in the weekly grid, derived from the cycle's own data
    /// (never a hardcoded 20) so a 12-week cycle doesn't show permanently-dashed cells.
    private var weekCount: Int {
        var maxWeek = cycle.lastCompletedWeek
        for (_, weekLogs) in cycle.logs { maxWeek = max(maxWeek, weekLogs.keys.max() ?? 0) }
        for (_, weekLogs) in cycle.structuredLogs { maxWeek = max(maxWeek, weekLogs.keys.max() ?? 0) }
        for (_, weekLogs) in cycle.linearLogs { maxWeek = max(maxWeek, weekLogs.keys.max() ?? 0) }
        for record in cycle.workoutRecords { maxWeek = max(maxWeek, record.week) }
        return max(maxWeek, 1)
    }

    private var weeklyLiftPerformances: [WeeklyLiftPerformance] {
        var labels: [String: [Int: String]] = [:]

        // SBS-style rep-out logs.
        for (lift, weekLogs) in cycle.logs {
            for (week, dayLogs) in weekLogs {
                if let reps = dayLogs.values.compactMap({ $0.repsLastSet }).first {
                    labels[lift, default: [:]][week] = "\(reps)"
                }
            }
        }

        // Structured logs (nSuns/5-3-1/GZCLP) — show the top AMRAP reps for the week.
        for (lift, weekLogs) in cycle.structuredLogs {
            for (week, dayLogs) in weekLogs {
                if let reps = dayLogs.values.flatMap({ $0.amrapReps.values }).max() {
                    labels[lift, default: [:]][week] = "\(reps)"
                }
            }
        }

        // Linear logs (StrongLifts/Starting Strength) — no rep-out, mark success/failure.
        for (lift, weekLogs) in cycle.linearLogs {
            for (week, dayLogs) in weekLogs where !dayLogs.isEmpty {
                let completed = dayLogs.values.contains { $0.completed }
                labels[lift, default: [:]][week] = completed ? "✓" : "✗"
            }
        }

        return labels.keys.sorted().map {
            WeeklyLiftPerformance(lift: $0, labelsByWeek: labels[$0] ?? [:])
        }
    }

    @ViewBuilder
    private var weeklyLogsSection: some View {
        let performances = weeklyLiftPerformances
        if !performances.isEmpty {
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                SBSSectionEyebrow("Weekly Results")

                VStack(spacing: 0) {
                    ForEach(Array(performances.enumerated()), id: \.element.id) { index, performance in
                        if index > 0 {
                            SBSRowDivider()
                        }
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            Text(performance.lift)
                                .font(SBSFonts.bodyStrong())
                                .foregroundStyle(Color.ink)

                            if performance.labelsByWeek.isEmpty {
                                Text("No logs recorded")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.inkSecondary)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SBSLayout.space1), count: 10), spacing: SBSLayout.space1) {
                                    ForEach(1...weekCount, id: \.self) { week in
                                        WeekResultCell(week: week, label: performance.labelsByWeek[week])
                                    }
                                }
                            }
                        }
                        .padding(SBSLayout.space4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .card()
            }
        }
    }
}

/// One week of a lift's results: a hairline cell with the AMRAP reps, or a
/// ✓ / ✗ for a linear session in success or danger. An empty week is a dash.
private struct WeekResultCell: View {
    let week: Int
    let label: String?

    private var color: Color {
        switch label {
        case "✓": return .success
        case "✗": return .danger
        case nil: return .inkTertiary
        default: return .ink
        }
    }

    private var accessibilityText: String {
        switch label {
        case "✓": return "Week \(week): done"
        case "✗": return "Week \(week): missed"
        case nil: return "Week \(week): no log"
        case let reps?: return "Week \(week): \(reps) reps"
        }
    }

    var body: some View {
        Text(label ?? "–")
            .font(SBSFonts.numberSmall().weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: 28, minHeight: 28)
            .background(label == nil ? Color.surface : Color.surfaceRaised, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }
}

// MARK: - TM Progression Row

struct TMProgressionRow: View {
    let liftName: String
    let startTM: Double
    let endTM: Double
    let useMetric: Bool
    var endLabel: String = "End"

    private var hasChange: Bool { abs(absoluteGain) >= 0.01 }

    private var progression: Double {
        guard startTM > 0 else { return 0 }
        return ((endTM - startTM) / startTM) * 100
    }
    
    private var absoluteGain: Double {
        endTM - startTM
    }
    
    var body: some View {
        SBSAdaptiveStack {
            Text(liftName)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Start → end
            HStack(spacing: SBSLayout.space3) {
            VStack(alignment: .trailing, spacing: 2) {
                SBSEyebrow("Start")
                    .foregroundStyle(Color.inkSecondary)
                Text(startTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }

            Image(systemName: "arrow.right")
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)
                .accessibilityLabel("to")

            VStack(alignment: .trailing, spacing: 2) {
                SBSEyebrow(endLabel)
                    .foregroundStyle(Color.inkSecondary)
                Text(endTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.ink)
            }

            // Progression
            Group {
                if hasChange {
                    SBSChangeLabel(text: String(format: "%.1f%%", abs(progression)), isUp: progression >= 0)
                } else {
                    Text("—")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)
                        .accessibilityLabel("No change")
                }
            }
            .frame(minWidth: 60, alignment: .trailing)
            }
        }
        .padding(.vertical, SBSLayout.space3)
        .padding(.horizontal, SBSLayout.space4)
        .frame(minHeight: 56)
    }
}

#Preview {
    PastCyclesView(appState: AppState())
}

