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

    /// The top of Home: the workout in progress, else what's next, else the end of the
    /// cycle. Each hides the ones after it.
    @ViewBuilder
    private var topCard: some View {
        if let session = appState.activeSession {
            NextWorkoutCard(
                heading: "In Progress: \(appState.dayTitle(day: session.day))",
                week: session.week,
                day: session.day,
                lifts: appState.dayLifts(week: session.week, day: session.day),
                actionTitle: "Resume Workout",
                action: { appState.resumeWorkout() }
            )
            .padding(.horizontal)
        } else if let next = appState.nextWorkoutInCycle {
            NextWorkoutCard(
                heading: "Next: \(appState.dayTitle(day: next.day))",
                week: next.week,
                day: next.day,
                lifts: appState.dayLifts(week: next.week, day: next.day),
                actionTitle: "Start Workout",
                action: { startNextWorkout(week: next.week, day: next.day) }
            )
            .padding(.horizontal)
        } else if appState.isCycleComplete {
            CycleCompletionCard(
                cycleNumber: appState.currentCycleNumber,
                summary: appState.cycleCompletionSummary(),
                useMetric: appState.settings.useMetric,
                onQuickRepeat: quickRepeat,
                onCustomize: openCycleBuilder
            )
            .padding(.horizontal)
            .transition(.asymmetric(
                insertion: .slide.combined(with: .opacity),
                removal: .opacity
            ))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SBSLayout.sectionSpacing) {
                    topCard

                    // Week selector strip
                    WeekStrip(
                        selectedWeek: $appState.selectedWeek,
                        totalWeeks: appState.weeks.count,
                        weekCompletionFraction: { week in
                            appState.weekCompletionFraction(for: week)
                        }
                    )
                    .padding(.horizontal)
                    
                    // Progress indicator
                    WeekProgressBar(progress: appState.cycleCompletionFraction)
                        .padding(.horizontal)

                    // Day cards
                    VStack(spacing: SBSLayout.cardSpacing) {
                        ForEach(appState.days, id: \.self) { day in
                            DayCard(
                                day: day,
                                title: appState.dayTitle(day: day),
                                lifts: appState.dayLifts(week: appState.selectedWeek, day: day),
                                logStatus: appState.dayLogStatus(week: appState.selectedWeek, day: day),
                                isSelected: day == appState.selectedDay,
                                onTap: {
                                    appState.selectedDay = day
                                    selectedSessionDay = day
                                    showingSession = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .sbsBackground()
            .onChange(of: appState.returnToHomeCount) { _, _ in
                showingSession = false
            }
            .navigationTitle(appState.programDisplayName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                            .font(.system(size: 17))
                    }
                    .accessibilityLabel("More options")
                }
            }
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
                    familyColor: programFamilyColor,
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
    
    private var programFamilyColor: Color {
        guard let selectedId = appState.userData.selectedProgram else { return SBSColors.accentFallback }
        switch selectedId {
        case "nsuns_5day_12week", "nsuns_4day_12week":
            return .orange
        case "531_bbb_12week", "531_triumvirate_12week":
            return .blue
        case "stronglifts_5x5_12week", "greyskull_lp_12week", "starting_strength_12week", "gzclp_12week":
            return .green
        case "reddit_ppl_12week", "sbs_program_config":
            return .purple
        default:
            return SBSColors.accentFallback
        }
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

struct NextWorkoutCard: View {
    let heading: String
    let week: Int
    let day: Int
    let lifts: [String]
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            VStack(alignment: .leading, spacing: 4) {
                // Always named: the strip may be showing a different week
                Text("WEEK \(week), DAY \(day)")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .tracking(1)

                Text(heading)
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)

                Text(lifts.isEmpty ? "No exercises" : lifts.joined(separator: " • "))
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .lineLimit(2)
            }

            Button(action: action) {
                Text(actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SBSPrimaryButtonStyle())
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .sbsCard()
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
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(SBSColors.success)
                        .frame(width: 44, height: 44)

                    Image(systemName: "trophy.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycle \(cycleNumber) Complete")
                        .font(SBSFonts.title3())
                        .foregroundStyle(SBSColors.textPrimaryFallback)

                    Text(sessionsText)
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }

                Spacer()
            }

            Rectangle()
                .fill(SBSColors.textTertiaryFallback.opacity(0.2))
                .frame(height: 1)

            if summary.gains.isEmpty {
                Text(noGainsText)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            } else {
                gainsList
            }

            VStack(spacing: SBSLayout.paddingSmall) {
                Button(action: onQuickRepeat) {
                    Text("Quick Repeat")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())

                Button(action: onCustomize) {
                    Text("Customize")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingSmall)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .sbsCard()
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .strokeBorder(SBSColors.success.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cycleCompletionCard")
    }

    private var gainsList: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text(gainsHeading)
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)

            ForEach(summary.gains.prefix(maximumGainRows), id: \.lift) { gain in
                HStack(spacing: SBSLayout.paddingSmall) {
                    Text(gain.lift)
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                        .lineLimit(1)

                    Spacer()

                    Text(gain.to.formattedWeight(useMetric: useMetric))
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)

                    Text("+\(gain.gain.formattedWeight(useMetric: useMetric))")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.success)
                }
            }

            if summary.gains.count > maximumGainRows {
                Text("and \(summary.gains.count - maximumGainRows) more")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
        }
    }
}

struct WeekProgressBar: View {
    /// Completed days across the cycle, 0 to 1
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            HStack {
                Text("Program Progress")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.accentFallback)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track, visible against the card at 0%
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SBSColors.textTertiaryFallback.opacity(0.25))
                        .frame(height: 8)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .sbsCard()
    }
}

// MARK: - Quick Stats Card (optional enhancement)

struct QuickStatsCard: View {
    let appState: AppState
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            HStack {
                Text("This Week")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Spacer()
            }
            
            HStack(spacing: SBSLayout.paddingLarge) {
                StatItem(
                    icon: "checkmark.circle.fill",
                    value: "\(completedDays)",
                    label: "Days Done",
                    color: SBSColors.success
                )
                
                StatItem(
                    icon: "flame.fill",
                    value: "\(totalSets)",
                    label: "Total Sets",
                    color: SBSColors.accentFallback
                )
                
                StatItem(
                    icon: "arrow.up.circle.fill",
                    value: tmGains,
                    label: "TM Gains",
                    color: SBSColors.accentSecondaryFallback
                )
            }
        }
        .padding()
        .sbsCard()
    }
    
    private var completedDays: Int {
        appState.days.filter { day in
            appState.dayLogStatus(week: appState.selectedWeek, day: day) == .complete
        }.count
    }
    
    private var totalSets: Int {
        // Each day has approximately 8 working sets (2 lifts × 4 sets)
        completedDays * 8
    }
    
    private var tmGains: String {
        // Calculate average TM change for the week
        "+1.2%"
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            
            Text(value)
                .font(SBSFonts.title2())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            Text(label)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HomeView(appState: AppState())
}

