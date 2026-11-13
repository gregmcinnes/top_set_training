import SwiftUI

struct HomeView: View {
    @Bindable var appState: AppState
    @State private var showingSession = false
    @State private var selectedSessionDay: Int = 1
    @State private var showingNewCycleOptions = false
    @State private var showingNewCycleBuilder = false
    /// Whether the cycle was finished when the builder opened. The builder's program
    /// preview can clear logs, so this can't be read when it completes.
    @State private var builderOpenedOnFinishedCycle = false
    @State private var showingPastCycles = false
    @State private var programInfoSheet: AppState.AvailableProgramInfo?
    @State private var showingProgramPaywall = false

    /// Repeating a cycle re-runs the current program, so it needs program access.
    /// A grandfathered user (mid-cycle on a program that left the free tier)
    /// hits the paywall here — their in-progress cycle is unaffected.
    private var canRepeatCurrentProgram: Bool {
        guard let programId = appState.userData.selectedProgram else { return true }
        return StoreManager.shared.canAccessProgram(programId)
    }

    private func quickRepeat() {
        guard canRepeatCurrentProgram else {
            showingProgramPaywall = true
            return
        }
        // Starting clears the logs that say whether the cycle was finished
        let finishedCycle = appState.isCycleComplete
        appState.startNewCycle(carryOverTMs: true)
        appState.newCycleStarted(afterFinishedCycle: finishedCycle)
    }

    private func openCycleBuilder() {
        builderOpenedOnFinishedCycle = appState.isCycleComplete
        showingNewCycleBuilder = true
    }

    private func startNextWorkout(week: Int, day: Int) {
        appState.selectedWeek = week
        appState.selectedDay = day
        selectedSessionDay = day
        appState.startWorkout(week: week, day: day)
    }

    /// The workout the strip and day list mark as current: the one in progress, else what's next
    private var currentWorkout: (week: Int, day: Int)? {
        if let session = appState.activeSession {
            return (session.week, session.day)
        }
        return appState.nextWorkoutInCycle
    }

    /// The top of Home: the workout in progress, else what's next, else the end of the
    /// cycle. Each hides the ones after it.
    @ViewBuilder
    private var topCard: some View {
        if let session = appState.activeSession {
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                SBSSectionEyebrow("In progress", knurled: true)
                NextWorkoutCard(
                    heading: appState.dayTitle(day: session.day),
                    week: session.week,
                    day: session.day,
                    lifts: appState.dayLifts(week: session.week, day: session.day),
                    actionTitle: "Resume Workout",
                    action: { appState.resumeWorkout() }
                )
            }
        } else if let next = appState.nextWorkoutInCycle {
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                SBSSectionEyebrow("Up next", knurled: true)
                NextWorkoutCard(
                    heading: appState.dayTitle(day: next.day),
                    week: next.week,
                    day: next.day,
                    lifts: appState.dayLifts(week: next.week, day: next.day),
                    actionTitle: "Start Workout",
                    action: { startNextWorkout(week: next.week, day: next.day) }
                )
            }
        } else if appState.isCycleComplete {
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                SBSSectionEyebrow("End of cycle", knurled: true)
                CycleCompletionCard(
                    cycleNumber: appState.currentCycleNumber,
                    summary: appState.cycleCompletionSummary(),
                    useMetric: appState.settings.useMetric,
                    onQuickRepeat: quickRepeat,
                    onCustomize: openCycleBuilder
                )
            }
            .transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }

    /// Program info, new cycle, past cycles: the header's trailing menu
    private var moreMenu: some View {
        Menu {
            if currentProgramInfo != nil {
                Button {
                    programInfoSheet = currentProgramInfo
                } label: {
                    Label("Program Info", systemImage: "info.circle")
                }

                Divider()
            }

            Button {
                showingNewCycleOptions = true
            } label: {
                Label("Start New Cycle", systemImage: "arrow.clockwise.circle")
            }
            
            if !appState.cycleHistory.isEmpty {
                Button {
                    showingPastCycles = true
                } label: {
                    Label("Past Cycles", systemImage: "clock.arrow.circlepath")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More options")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSLayout.space6) {
                    SBSTabHeader(appState.programDisplayName) { moreMenu }

                    topCard

                    // Week selector strip
                    WeekStrip(
                        selectedWeek: $appState.selectedWeek,
                        totalWeeks: appState.weeks.count,
                        currentWeek: currentWorkout?.week,
                        currentDay: currentWorkout?.day,
                        days: { week in
                            appState.visibleDays(forWeek: week).map { day in
                                WeekStripDay(day: day, status: appState.dayDisplayStatus(week: week, day: day))
                            }
                        }
                    )

                    // Progress indicator, for programs that have days it can count
                    if appState.programHasLoggableDays {
                        WeekProgressBar(progress: appState.cycleCompletionFraction)
                    }

                    // Day list
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        SBSSectionEyebrow("Days in week \(appState.selectedWeek)", knurled: true)

                        VStack(spacing: 0) {
                            ForEach(Array(appState.days.enumerated()), id: \.element) { index, day in
                                if index > 0 {
                                    SBSRowDivider()
                                }
                                DayCard(
                                    day: day,
                                    title: appState.dayTitle(day: day),
                                    lifts: appState.dayLifts(week: appState.selectedWeek, day: day),
                                    logStatus: appState.dayDisplayStatus(week: appState.selectedWeek, day: day),
                                    isCurrent: currentWorkout.map { $0.week == appState.selectedWeek && $0.day == day } ?? false,
                                    onTap: {
                                        appState.selectedDay = day
                                        selectedSessionDay = day
                                        showingSession = true
                                    }
                                )
                            }
                        }
                        .card()
                    }

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, SBSLayout.space4)
                .padding(.top, SBSLayout.space2)
            }
            .sbsBackground()
            .onChange(of: appState.returnToHomeCount) { _, _ in
                showingSession = false
            }
            .sbsTabRoot(appState.programDisplayName)
            .navigationDestination(isPresented: $showingSession) {
                SessionView(
                    appState: appState,
                    week: appState.selectedWeek,
                    day: selectedSessionDay
                )
            }
            .confirmationDialog(
                "Start New Cycle",
                isPresented: $showingNewCycleOptions,
                titleVisibility: .visible
            ) {
                Button("Quick Repeat", action: quickRepeat)

                Button("Customize New Cycle", action: openCycleBuilder)

                Button("Cancel", role: .cancel) {}
            } message: {
                Text(appState.newCycleDialogMessage)
            }
            .fullScreenCover(isPresented: $showingNewCycleBuilder) {
                CycleBuilderView(
                    appState: appState,
                    isOnboarding: false,
                    onComplete: {
                        showingNewCycleBuilder = false
                        // Reset navigation to ensure views are recreated with new week/day values
                        showingSession = false
                        appState.newCycleStarted(afterFinishedCycle: builderOpenedOnFinishedCycle)
                    },
                    onCancel: {
                        // No cycle started, so nothing to record and no review prompt
                        showingNewCycleBuilder = false
                    }
                )
            }
            // Reset navigation when a new cycle starts (settings.currentWeek resets to 1)
            .onChange(of: appState.userData.currentCycleStartDate) { _, _ in
                showingSession = false
            }
            .sheet(isPresented: $showingPastCycles) {
                PastCyclesView(appState: appState)
            }
            .sheet(isPresented: $showingProgramPaywall) {
                PaywallView(triggeredByFeature: .allPrograms)
            }
            .sheet(item: $programInfoSheet) { programInfo in
                ProgramDetailView(
                    program: programInfo,
                    programData: appState.programData,
                    // Orange as text and icons; no colour per program family
                    level: programExperienceLevel
                )
            }
        }
    }
    
    // MARK: - Current Program Info
    
    private var currentProgramInfo: AppState.AvailableProgramInfo? {
        guard let selectedId = appState.userData.selectedProgram ?? "sbs_program_config" as String?,
              let program = appState.availablePrograms.first(where: { $0.id == selectedId }) else {
            return nil
        }
        return program
    }
    
    private var programExperienceLevel: ProgramLevel {
        guard let selectedId = appState.userData.selectedProgram else { return .intermediate }
        switch selectedId {
        case "stronglifts_5x5_12week", "greyskull_lp_12week", "starting_strength_12week":
            return .beginner
        case "gzclp_12week", "531_triumvirate_12week", "531_bbb_12week", "reddit_ppl_12week", "nsuns_5day_12week", "nsuns_4day_12week":
            return .intermediate
        case "sbs_program_config":
            return .advanced
        default:
            return .intermediate
        }
    }
}

// MARK: - Next Workout Card

/// What's next (or in progress): the week and day, the workout, its lifts, and
/// Home's one primary button.
struct NextWorkoutCard: View {
    let heading: String
    let week: Int
    let day: Int
    let lifts: [String]
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space4) {
            VStack(alignment: .leading, spacing: SBSLayout.space1) {
                // Always named: the strip may be showing a different week
                SBSEyebrow("Week \(week) · Day \(day)")
                    .foregroundStyle(Color.inkSecondary)

                Text(heading)
                    .font(SBSFonts.heading())
                    .foregroundStyle(Color.ink)

                Text(lifts.isEmpty ? "No exercises" : lifts.joined(separator: " · "))
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)
            }

            Button(action: action) {
                SBSButtonTitle(actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SBSPrimaryButtonStyle())
        }
        .padding(SBSLayout.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nextWorkoutCard")
    }
}

// MARK: - Cycle Completion Card

struct CycleCompletionCard: View {
    let cycleNumber: Int
    let summary: CycleCompletionSummary
    let useMetric: Bool
    let onQuickRepeat: () -> Void
    let onCustomize: () -> Void

    /// Enough for a program's main lifts without pushing the day list far down
    private let maximumGainRows = 6

    private var sessionsText: String {
        summary.sessionsCompleted == 1 ? "1 session completed" : "\(summary.sessionsCompleted) sessions completed"
    }

    private var gainsHeading: String {
        summary.usesTrainingMaxes ? "Training Max Gains" : "Working Weight Gains"
    }

    private var noGainsText: String {
        let values = summary.usesTrainingMaxes ? "training maxes" : "working weights"
        return "No increases this cycle. Your next cycle picks up from your latest \(values)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space4) {
            SBSAdaptiveStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycle \(cycleNumber) Complete")
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.ink)

                    SBSRowSubtitle(sessionsText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SBSBadge(text: "Complete", variant: .status(.success), systemImage: "checkmark")
            }

            SBSRowDivider()

            if summary.gains.isEmpty {
                Text(noGainsText)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            } else {
                gainsList
            }

            VStack(spacing: SBSLayout.space2) {
                Button(action: onQuickRepeat) {
                    SBSButtonTitle("Quick Repeat")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())

                Button(action: onCustomize) {
                    SBSButtonTitle("Customize")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSSecondaryButtonStyle())
            }
        }
        .padding(SBSLayout.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycleCompletionCard")
    }

    private var gainsList: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSEyebrow(gainsHeading)
                .foregroundStyle(Color.inkSecondary)

            ForEach(summary.gains.prefix(maximumGainRows), id: \.lift) { gain in
                HStack(spacing: SBSLayout.space2) {
                    Text(gain.lift)
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)

                    Spacer()

                    Text(gain.to.formattedWeight(useMetric: useMetric))
                        .font(SBSFonts.numberSmall().weight(.semibold))
                        .foregroundStyle(Color.ink)

                    SBSChangeLabel(text: gain.gain.formattedWeight(useMetric: useMetric), isUp: true)
                }
                .accessibilityElement(children: .combine)
            }

            if summary.gains.count > maximumGainRows {
                Text("and \(summary.gains.count - maximumGainRows) more")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }
}

/// Days done across the cycle: a knurled eyebrow with the percentage, and an
/// ink bar on a hairline track (orange stays with the Start button).
struct WeekProgressBar: View {
    /// Completed days across the cycle, 0 to 1
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("Program Progress", knurled: true) {
                Text("\(Int(progress * 100))%")
                    .font(SBSFonts.numberSmall().weight(.semibold))
                    .foregroundStyle(Color.ink)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.surface)
                        .overlay(Rectangle().strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline))

                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: geo.size.width * min(max(progress, 0), 1))
                        .animation(.easeOut(duration: 0.25), value: progress)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
    }
}

#Preview {
    HomeView(appState: AppState())
}

