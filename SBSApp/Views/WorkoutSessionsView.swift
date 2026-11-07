import SwiftUI

extension Date {
    /// "Nov 5", with the year once it isn't this year
    var historyDateText: String {
        if Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.month(.abbreviated).day())
        }
        return formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Links from the History tab

struct HistoryLinkRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        SBSListRow(title, showsChevron: true) {
            Image(systemName: systemImage)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
        } subtitle: {
            Text(subtitle)
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        } trailing: {
            EmptyView()
        }
        .card()
    }
}

/// Shown where an account without full history has archived cycles it can't open
struct HistoryLockedCyclesRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            SBSListRow("View Past Cycles") {
                Image(systemName: "clock.arrow.circlepath")
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            } subtitle: {
                Text("Unlock full workout history with Premium")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            } trailing: {
                SBSBadge(text: "Pro", variant: .pro, systemImage: "lock.fill")
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("historyLockedCyclesRow")
    }
}

// MARK: - Session List

/// Every workout, newest first, grouped by cycle. Current-cycle sessions are always
/// visible; archived cycles need `.fullHistory`, the same check as the rest of History.
struct WorkoutSessionsView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false
    @State private var selectedCycle: CompletedCycle?

    var body: some View {
        // Grouped here, once per update, rather than from the rows
        let list = HistorySessionBuilder.list(
            records: appState.userData.workoutRecords,
            accessoryHistory: appState.userData.accessoryHistory,
            currentCycleStart: appState.userData.currentCycleStartDate,
            currentCycleNumber: appState.currentCycleNumber,
            currentProgramName: appState.programData?.displayName ?? appState.programData?.name,
            archivedCycles: appState.userData.cycleHistory,
            includeArchived: StoreManager.shared.canAccess(.fullHistory)
        )

        ScrollView {
            LazyVStack(alignment: .leading, spacing: SBSLayout.space6) {
                if list.isEmpty {
                    emptyState(hasLockedCycles: list.lockedCycleCount > 0)
                }

                ForEach(list.sections) { section in
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        sectionHeader(section)

                        if !section.sessions.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(section.sessions.enumerated()), id: \.element.id) { index, session in
                                    if index > 0 { SBSRowDivider() }
                                    NavigationLink {
                                        WorkoutSessionDetailView(session: session, useMetric: appState.settings.useMetric)
                                    } label: {
                                        WorkoutSessionRow(session: session)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("historySessionRow")
                                }
                            }
                            .card()
                        }

                        if let cycle = section.cycleWithoutSessionRecords {
                            legacyCycleRow(cycle)
                        }
                    }
                }

                if list.lockedCycleCount > 0 {
                    HistoryLockedCyclesRow { showingPaywall = true }
                }

                if !list.isEmpty {
                    Text("Shows the results saved for each workout. For lifts with rep-out sets, that's the rep-out sets.")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .padding()
        }
        .sbsBackground()
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(triggeredByFeature: .fullHistory)
        }
        .sheet(item: $selectedCycle) { cycle in
            CycleDetailView(
                cycle: cycle,
                useMetric: appState.settings.useMetric,
                accessoryHistory: appState.userData.accessoryHistory
            )
        }
    }

    private func emptyState(hasLockedCycles: Bool) -> some View {
        ContentUnavailableView {
            Label(hasLockedCycles ? "No Workouts This Cycle" : "No Workouts Yet", systemImage: "list.bullet.rectangle")
        } description: {
            Text(appState.hasLoggedData
                ? "Workouts from earlier versions of the app aren't listed here. New workouts will be."
                : "Log a workout and it will show up here with all its results.")
        } actions: {
            Button {
                dismiss()
                appState.goToWorkoutTab()
            } label: {
                SBSButtonTitle("Go to Workout")
            }
            .buttonStyle(SBSPrimaryButtonStyle())
            .accessibilityIdentifier("historySessionsGoToWorkoutButton")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func sectionHeader(_ section: HistorySessionSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SBSSectionEyebrow(section.isCurrent ? "Cycle \(section.cycleNumber) · Current" : "Cycle \(section.cycleNumber)")

            if let programName = section.programName, !programName.isEmpty {
                Text(programName)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    /// Cycles from before per-session records still have their summary
    private func legacyCycleRow(_ cycle: CompletedCycle) -> some View {
        Button {
            selectedCycle = cycle
        } label: {
            HistoryLinkRow(
                systemImage: "calendar",
                title: "Cycle Summary",
                subtitle: "This cycle's workouts weren't saved one by one"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("historyLegacyCycleRow")
    }
}

struct WorkoutSessionRow: View {
    let session: HistorySession

    private var metadata: String {
        var parts = [session.date.historyDateText]
        if let position = session.positionLabel { parts.append(position) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        SBSListRow(session.title, showsChevron: true) {
            VStack(alignment: .leading, spacing: 2) {
                SBSRowSubtitle(metadata)

                Text(session.exerciseNames.joined(separator: ", "))
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

// MARK: - Session Detail

struct WorkoutSessionDetailView: View {
    let session: HistorySession
    let useMetric: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SBSLayout.space4) {
                header

                ForEach(session.exercises) { exercise in
                    WorkoutSessionExerciseCard(exercise: exercise, useMetric: useMetric)
                }

                if !session.accessories.isEmpty {
                    SBSSectionEyebrow("Accessories")
                        .padding(.top, SBSLayout.space2)

                    VStack(spacing: 0) {
                        ForEach(Array(session.accessories.enumerated()), id: \.element.id) { index, accessory in
                            if index > 0 { SBSRowDivider() }
                            accessoryRow(accessory)
                        }
                    }
                    .card()
                }
            }
            .padding()
        }
        .sbsBackground()
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            let details = [session.programName, session.positionLabel ?? ""].filter { !$0.isEmpty }
            if !details.isEmpty {
                SBSEyebrow(details.joined(separator: " · "))
                    .foregroundStyle(Color.inkSecondary)
            }

            Text(session.date.formatted(date: .long, time: .shortened))
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("historySessionDetail")
    }

    private func accessoryRow(_ accessory: HistorySessionAccessory) -> some View {
        SBSListRow(accessory.name) {
            if let note = accessory.note {
                Text(note)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
        } trailing: {
            Text(accessoryResultText(
                weight: accessory.weight,
                sets: accessory.sets,
                reps: accessory.reps,
                useMetric: useMetric
            ))
            .font(SBSFonts.numberSmall())
            .foregroundStyle(Color.ink)
        }
    }
}

/// "3 × 10 · 45 lb", leaving the weight out when none was logged (bodyweight work)
private func accessoryResultText(weight: Double, sets: Int, reps: Int, useMetric: Bool) -> String {
    let volume = "\(sets) × \(reps)"
    return weight > 0 ? "\(volume) · \(weight.formattedWeight(useMetric: useMetric))" : volume
}

private struct WorkoutSessionExerciseCard: View {
    let exercise: HistorySessionExercise
    let useMetric: Bool

    /// A linear lift's "training max" is just its working weight, shown on the line itself
    private var trainingMaxText: String? {
        guard exercise.type != .linear, exercise.trainingMax > 0 else { return nil }
        return "TM \(exercise.trainingMax.formattedWeight(useMetric: useMetric))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSAdaptiveStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(SBSFonts.heading())
                    .foregroundStyle(Color.ink)

                Spacer(minLength: 0)

                if let trainingMaxText {
                    Text(trainingMaxText)
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            ForEach(exercise.lines) { line in
                setLine(line)
            }

            if let note = exercise.note {
                HStack(alignment: .top, spacing: SBSLayout.space2) {
                    Image(systemName: "note.text")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .accessibilityHidden(true)

                    Text(note)
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .card()
    }

    private func setLine(_ line: HistorySetLine) -> some View {
        let weight = line.weight.formattedWeight(useMetric: useMetric)
        return HStack {
            if line.isAMRAP {
                Text("\(weight) × \(line.reps) reps")
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.ink)
            } else {
                Text("\(line.count) × \(line.reps) · \(weight)")
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.ink)
            }

            Spacer(minLength: SBSLayout.space2)

            if line.missed {
                SBSBadge(text: "Missed", variant: .status(.warning), systemImage: "xmark")
            } else if line.isAMRAP {
                let hit = line.reps >= line.targetReps
                SBSBadge(text: "Target \(line.targetReps)+", variant: .status(hit ? .success : .warning), systemImage: hit ? "checkmark" : nil)
            }
        }
    }
}

// MARK: - Accessory History

/// Logged accessory work by exercise, under the same gate as the session list
struct AccessoryHistoryView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    private var canAccessFullHistory: Bool {
        StoreManager.shared.canAccess(.fullHistory)
    }

    var body: some View {
        let groups = AccessoryHistoryBuilder.groups(
            accessoryHistory: appState.userData.accessoryHistory,
            currentCycleStart: appState.userData.currentCycleStartDate,
            archivedCycles: appState.userData.cycleHistory,
            includeArchived: canAccessFullHistory
        )

        ScrollView {
            LazyVStack(alignment: .leading, spacing: SBSLayout.space2) {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Accessories This Cycle", systemImage: "dumbbell")
                    } description: {
                        Text("Log accessory work in a workout and it will show up here.")
                    } actions: {
                        Button {
                            dismiss()
                            appState.goToWorkoutTab()
                        } label: {
                            SBSButtonTitle("Go to Workout")
                        }
                        .buttonStyle(SBSPrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }

                if !groups.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            if index > 0 { SBSRowDivider() }
                            AccessoryHistoryCard(group: group, useMetric: appState.settings.useMetric)
                        }
                    }
                    .card()
                }

                if !canAccessFullHistory && !appState.userData.cycleHistory.isEmpty {
                    HistoryLockedCyclesRow { showingPaywall = true }
                }
            }
            .padding()
        }
        .sbsBackground()
        .navigationTitle("Accessories")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(triggeredByFeature: .fullHistory)
        }
    }
}

private struct AccessoryHistoryCard: View {
    let group: AccessoryHistoryGroup
    let useMetric: Bool
    @State private var isExpanded = false

    private var earlierEntries: ArraySlice<AccessoryRecord> { group.entries.dropFirst() }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.ink)

                        if let latest = group.latest {
                            entryText(latest)
                        }
                    }

                    Spacer()

                    if !earlierEntries.isEmpty {
                        SBSChevron(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(earlierEntries.isEmpty)
            .accessibilityIdentifier("historyAccessoryRow")

            if isExpanded {
                ForEach(earlierEntries) { entry in
                    entryText(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.vertical, SBSLayout.space3)
        .padding(.horizontal, SBSLayout.space4)
    }

    private func entryText(_ entry: AccessoryRecord) -> some View {
        let result = accessoryResultText(weight: entry.weight, sets: entry.sets, reps: entry.reps, useMetric: useMetric)
        return SBSRowSubtitle("\(entry.date.historyDateText) · \(result)")
    }
}
