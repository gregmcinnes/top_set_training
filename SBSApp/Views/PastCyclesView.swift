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
                CycleDetailView(cycle: cycle, useMetric: appState.settings.useMetric)
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
                .font(SBSFonts.body())
                .foregroundStyle(SBSColors.textSecondaryFallback)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SBSLayout.paddingLarge)
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
                Text("Cycle \(cycle.cycleNumber)")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
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
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                Label(durationText, systemImage: "clock")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            // Quick TM summary
            HStack(spacing: SBSLayout.paddingMedium) {
                ForEach(Array(cycle.endingMaxes.keys.sorted().prefix(4)), id: \.self) { lift in
                    if let endTM = cycle.endingMaxes[lift] {
                        VStack(spacing: 2) {
                            Text(liftAbbreviation(lift))
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            Text(endTM.formattedWeightShort(useMetric: useMetric))
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.accentFallback)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
        }
        .padding(.vertical, SBSLayout.paddingSmall)
    }
    
    private func liftAbbreviation(_ lift: String) -> String {
        switch lift.lowercased() {
        case "squat": return "SQ"
        case "bench": return "BP"
        case "deadlift": return "DL"
        case "ohp", "overhead press": return "OHP"
        case "row", "barbell row": return "ROW"
        default:
            // Take first 3 characters
            return String(lift.prefix(3)).uppercased()
        }
    }
}

// MARK: - Cycle Detail View

struct CycleDetailView: View {
    let cycle: CompletedCycle
    let useMetric: Bool
    @Environment(\.dismiss) private var dismiss
    
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
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text("\(cycle.lastCompletedWeek) weeks")
                        .font(SBSFonts.title3())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Completed")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text(dateFormatter.string(from: cycle.endDate))
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Started")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text(dateFormatter.string(from: cycle.startDate))
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Workouts")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    Text("\(totalLoggedWorkouts)")
                        .font(SBSFonts.title3())
                        .foregroundStyle(SBSColors.accentFallback)
                }
            }
        }
        .padding()
        .sbsCard()
    }
    
    private var totalLoggedWorkouts: Int {
        var count = 0
        for (_, weekLogs) in cycle.logs {
            for (_, dayLogs) in weekLogs {
                count += dayLogs.values.filter { $0.repsLastSet != nil }.count
            }
        }
        return count
    }
    
    private var tmProgressionSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            Text("Training Max Progression")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            VStack(spacing: SBSLayout.paddingSmall) {
                ForEach(Array(cycle.startingMaxes.keys.sorted()), id: \.self) { lift in
                    TMProgressionRow(
                        liftName: lift,
                        startTM: cycle.startingMaxes[lift] ?? 0,
                        endTM: cycle.endingMaxes[lift] ?? 0,
                        useMetric: useMetric
                    )
                }
            }
        }
    }
    
    private var weeklyLogsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            Text("Weekly Rep-Outs")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            let lifts = Array(cycle.logs.keys.sorted())
            
            ForEach(lifts, id: \.self) { lift in
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    Text(lift)
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    let weekLogs = cycle.logs[lift] ?? [:]
                    let sortedWeeks = weekLogs.keys.sorted()
                    
                    if sortedWeeks.isEmpty {
                        Text("No logs recorded")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                            ForEach(1...20, id: \.self) { week in
                                // Find any logged reps for this week (from any day)
                                let reps = weekLogs[week]?.values.compactMap { $0.repsLastSet }.first
                                if let reps = reps {
                                    Text("\(reps)")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(SBSColors.accentFallback.opacity(0.2))
                                        )
                                } else {
                                    Text("-")
                                        .font(SBSFonts.caption())
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

// MARK: - TM Progression Row

struct TMProgressionRow: View {
    let liftName: String
    let startTM: Double
    let endTM: Double
    let useMetric: Bool
    
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
                .font(SBSFonts.body())
                .foregroundStyle(SBSColors.textPrimaryFallback)
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            // Start TM
            VStack(alignment: .trailing, spacing: 2) {
                Text("Start")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                Text(startTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.number())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Image(systemName: "arrow.right")
                .font(.system(size: 12))
                .foregroundStyle(SBSColors.textTertiaryFallback)
                .padding(.horizontal, SBSLayout.paddingSmall)
            
            // End TM
            VStack(alignment: .trailing, spacing: 2) {
                Text("End")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                Text(endTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.number())
                    .foregroundStyle(SBSColors.accentFallback)
            }
            
            // Progression badge
            HStack(spacing: 2) {
                Image(systemName: progression >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%.1f%%", abs(progression)))
                    .font(SBSFonts.captionBold())
            }
            .foregroundStyle(progression >= 0 ? SBSColors.success : SBSColors.error)
            .frame(width: 60, alignment: .trailing)
        }
        .padding()
        .sbsCard()
    }
}

#Preview {
    PastCyclesView(appState: AppState())
}

