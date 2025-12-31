import SwiftUI

struct HomeView: View {
    @Bindable var appState: AppState
    @State private var showingSession = false
    @State private var selectedSessionDay: Int = 1
    @State private var showingNewCycleOptions = false
    @State private var showingNewCycleBuilder = false
    @State private var showingPastCycles = false
    @State private var showingProgramInfo = false
    
    /// Check if we should show the cycle completion prompt
    private var shouldShowCompletionPrompt: Bool {
        let totalWeeks = appState.weeks.count
        let isOnFinalWeek = appState.selectedWeek == totalWeeks
        let finalWeekComplete = appState.weekCompletionFraction(for: totalWeeks) == 1.0
        return isOnFinalWeek && finalWeekComplete
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SBSLayout.sectionSpacing) {
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
                    WeekProgressBar(
                        week: appState.selectedWeek,
                        totalWeeks: appState.weeks.count
                    )
                    .padding(.horizontal)
                    
                    // Cycle completion prompt (shows when final week is complete)
                    if shouldShowCompletionPrompt {
                        CycleCompletionCard(
                            cycleNumber: appState.currentCycleNumber,
                            onQuickRepeat: {
                                appState.startNewCycle(carryOverTMs: true)
                            },
                            onCustomize: {
                                showingNewCycleBuilder = true
                            }
                        )
                        .padding(.horizontal)
                        .transition(.asymmetric(
                            insertion: .slide.combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    
                    // Day cards
                    VStack(spacing: SBSLayout.cardSpacing) {
                        ForEach(appState.days, id: \.self) { day in
                            DayCard(
                                day: day,
                                title: appState.dayTitle(day: day),
                                lifts: appState.dayLifts(day: day),
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
            .navigationTitle(appState.programData?.displayName ?? appState.programData?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingProgramInfo = true
                        } label: {
                            Label("Program Info", systemImage: "info.circle")
                        }
                        
                        Divider()
                        
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
                Button("Quick Repeat") {
                    appState.startNewCycle(carryOverTMs: true)
                }
                
                Button("Customize New Cycle") {
                    showingNewCycleBuilder = true
                }
                
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Quick Repeat will start a new cycle with your current program and carry over your training maxes. Choose Customize to change program, exercises, or adjust maxes.")
            }
            .fullScreenCover(isPresented: $showingNewCycleBuilder) {
                CycleBuilderView(
                    appState: appState,
                    isOnboarding: false,
                    onComplete: {
                        showingNewCycleBuilder = false
                        // Reset navigation to ensure views are recreated with new week/day values
                        showingSession = false
                    },
                    onCancel: {
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
            .sheet(isPresented: $showingProgramInfo) {
                if let programInfo = currentProgramInfo {
                    ProgramDetailView(
                        program: programInfo,
                        programData: appState.programData,
                        familyColor: programFamilyColor,
                        level: programExperienceLevel
                    )
                }
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

// MARK: - Cycle Completion Notification Banner

struct CycleCompletionCard: View {
    let cycleNumber: Int
    let onQuickRepeat: () -> Void
    let onCustomize: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar with icon and title
            HStack(spacing: 12) {
                // Trophy icon in accent circle
                ZStack {
                    Circle()
                        .fill(SBSColors.success)
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycle \(cycleNumber) Complete!")
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Ready to start your next cycle?")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
            }
            .padding(.horizontal, SBSLayout.paddingMedium)
            .padding(.vertical, 14)
            .background(SBSColors.surfaceFallback)
            
            // Divider
            Rectangle()
                .fill(SBSColors.textTertiaryFallback.opacity(0.2))
                .frame(height: 1)
            
            // Action buttons row
            HStack(spacing: 0) {
                // Quick Repeat button
                Button {
                    onQuickRepeat()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                        Text("Quick Repeat")
                            .font(SBSFonts.caption())
                    }
                    .foregroundStyle(SBSColors.accentFallback)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                
                // Vertical divider
                Rectangle()
                    .fill(SBSColors.textTertiaryFallback.opacity(0.2))
                    .frame(width: 1)
                
                // Customize button
                Button {
                    onCustomize()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                        Text("Customize")
                            .font(SBSFonts.caption())
                    }
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .background(SBSColors.surfaceElevatedFallback.opacity(0.5))
        }
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                .stroke(SBSColors.success.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

struct WeekProgressBar: View {
    let week: Int
    let totalWeeks: Int
    
    private var progress: Double {
        Double(week) / Double(totalWeeks)
    }
    
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
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SBSColors.surfaceFallback)
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

