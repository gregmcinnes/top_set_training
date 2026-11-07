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
        VStack(spacing: SBSLayout.paddingLarge) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundStyle(SBSColors.textTertiaryFallback)
            
            Text("No Past Cycles")
                .font(SBSFonts.title2())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            Text("When you complete a training cycle and start a new one, your history will appear here.")
                .font(SBSFonts.legacyBody())
                .foregroundStyle(SBSColors.textSecondaryFallback)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SBSLayout.paddingLarge)

            Button("Go to Workout") {
                dismiss()
                appState.goToWorkoutTab()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
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
    
    private let summaryColumns = Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .leading), count: 4)

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
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycle \(cycle.cycleNumber)")
                        .font(SBSFonts.title3())
                        .foregroundStyle(SBSColors.textPrimaryFallback)

                    if let programName = cycle.programName, !programName.isEmpty {
                        Text(programName)
                            .font(SBSFonts.legacyCaption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                }

                Spacer()

                // Average TM gain badge
                if averageTMGain != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: averageTMGain >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.1f%%", averageTMGain))
                            .font(SBSFonts.captionBold())
                    }
                    .foregroundStyle(averageTMGain >= 0 ? SBSColors.success : SBSColors.error)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill((averageTMGain >= 0 ? SBSColors.success : SBSColors.error).opacity(0.15))
                    )
                }
            }
            
            HStack(spacing: SBSLayout.paddingMedium) {
                Label(dateFormatter.string(from: cycle.startDate), systemImage: "calendar")
                    .font(SBSFonts.legacyCaption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                Label(durationText, systemImage: "clock")
                    .font(SBSFonts.legacyCaption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            // Quick summary of every lift
            HStack(spacing: SBSLayout.paddingMedium) {
                LazyVGrid(columns: summaryColumns, spacing: SBSLayout.paddingSmall) {
                    ForEach(cycle.summaryLifts, id: \.self) { lift in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ExerciseLibrary.shortName(for: lift))
                                .font(SBSFonts.legacyCaption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            Text((cycle.endingMaxes[lift] ?? 0).formattedWeightShort(useMetric: useMetric))
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(Color.orangeText)
                        }
                    }
                }

Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
        }
        .padding(.vertical, SBSLayout.paddingSmall)
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
                VStack(spacing: SBSLayout.sectionSpacing) {
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
                .padding()
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
        VStack(spacing: SBSLayout.paddingMedium) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duration")
                        .font(SBSFonts.legacyCaption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text("\(cycle.lastCompletedWeek) week\(cycle.lastCompletedWeek == 1 ? "" : "s")")
                        .font(SBSFonts.title3())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Completed")
                        .font(SBSFonts.legacyCaption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text(dateFormatter.string(from: cycle.endDate))
                        .font(SBSFonts.legacyBody())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Started")
                        .font(SBSFonts.legacyCaption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text(dateFormatter.string(from: cycle.startDate))
                        .font(SBSFonts.legacyBody())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Workouts")
                        .font(SBSFonts.legacyCaption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text("\(totalLoggedWorkouts)")
                        .font(SBSFonts.title3())
                        .foregroundStyle(Color.orangeText)
                }
            }
        }
        .padding()
        .sbsCard()
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
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            Text(progressionTitle)
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)

            VStack(spacing: SBSLayout.paddingSmall) {
                ForEach(cycle.progressedLifts, id: \.self) { lift in
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
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        let sessions = HistorySessionBuilder.sessions(for: cycle, accessoryHistory: accessoryHistory)
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
                Text("Workouts")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)

                LazyVStack(spacing: SBSLayout.paddingSmall) {
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
            VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
                Text("Weekly Results")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)

                ForEach(performances) { performance in
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Text(performance.lift)
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)

                        if performance.labelsByWeek.isEmpty {
                            Text("No logs recorded")
                                .font(SBSFonts.legacyCaption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                                ForEach(1...weekCount, id: \.self) { week in
                                    if let label = performance.labelsByWeek[week] {
                                        Text(label)
                                            .font(SBSFonts.legacyCaption())
                                            .foregroundStyle(SBSColors.textPrimaryFallback)
                                            .frame(width: 28, height: 28)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(SBSColors.accentFallback.opacity(0.2))
                                            )
                                    } else {
                                        Text("-")
                                            .font(SBSFonts.legacyCaption())
                                            .foregroundStyle(SBSColors.textTertiaryFallback)
                                            .frame(width: 28, height: 28)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(SBSColors.surfaceFallback)
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .sbsCard()
                }
            }
        }
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
        HStack {
            Text(liftName)
                .font(SBSFonts.legacyBody())
                .foregroundStyle(SBSColors.textPrimaryFallback)
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            // Start TM
            VStack(alignment: .trailing, spacing: 2) {
                Text("Start")
                    .font(SBSFonts.legacyCaption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                Text(startTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.legacyNumber())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Image(systemName: "arrow.right")
                .font(.system(size: 12))
                .foregroundStyle(SBSColors.textTertiaryFallback)
                .padding(.horizontal, SBSLayout.paddingSmall)
            
            // End TM
            VStack(alignment: .trailing, spacing: 2) {
                Text(endLabel)
                    .font(SBSFonts.legacyCaption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                Text(endTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.legacyNumber())
                    .foregroundStyle(Color.orangeText)
            }
            
            // Progression badge
            if hasChange {
                HStack(spacing: 2) {
                    Image(systemName: progression >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%.1f%%", abs(progression)))
                        .font(SBSFonts.captionBold())
                }
                .foregroundStyle(progression >= 0 ? SBSColors.success : SBSColors.error)
                .frame(width: 60, alignment: .trailing)
            } else {
                Text("—")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .frame(width: 60, alignment: .trailing)
                    .accessibilityLabel("No change")
            }
}
        .padding()
        .sbsCard()
    }
}

#Preview {
    PastCyclesView(appState: AppState())
}

