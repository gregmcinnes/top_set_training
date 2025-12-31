import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var showingExport = false
    @State private var showingResetAlert = false
    @State private var showingTMEditor = false
    @State private var showingExerciseEditor = false
    @State private var showingPastCycles = false
    @State private var showingNewCycleAlert = false
    @State private var showingNewCycleBuilder = false
    @State private var showingNewCycleOptions = false
    @State private var showingWeightAdjustments = false
    @State private var showingTemplateList = false
    @State private var carryOverTMs = true
    @State private var exportData: Data?
    @State private var showingPaywall = false
    @State private var isRestoringPurchases = false
    @State private var showingProgramInfo = false
    @State private var showingPlateCalculatorInfo = false
    
    private let storeManager = StoreManager.shared
    
    private var templateCountText: String {
        let count = appState.userData.customTemplates.count
        if count == 0 {
            return "Create custom workout programs"
        } else if count == 1 {
            return "1 template saved"
        } else {
            return "\(count) templates saved"
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Premium Section - only show for non-premium users
                if !storeManager.isPremium {
                    Section {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack(spacing: SBSLayout.paddingMedium) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [SBSColors.accentFallback.opacity(0.2), SBSColors.accentSecondaryFallback.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 44, height: 44)
                                    
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Upgrade to Premium")
                                        .font(SBSFonts.bodyBold())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                    
                                    Text("Unlock all programs & features")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                                
                                Spacer()
                                
                                Text(storeManager.premiumPriceString)
                                    .font(SBSFonts.bodyBold())
                                    .foregroundStyle(SBSColors.accentFallback)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // Current Program
                Section {
                    Button {
                        showingProgramInfo = true
                    } label: {
                        HStack(spacing: SBSLayout.paddingMedium) {
                            ZStack {
                                Circle()
                                    .fill(programFamilyColor.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(programFamilyColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appState.programData?.displayName ?? appState.programData?.name ?? "Program")
                                    .font(SBSFonts.bodyBold())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                
                                if let programInfo = currentProgramInfo {
                                    HStack(spacing: 8) {
                                        Label("\(programInfo.days)d/wk", systemImage: "calendar")
                                        Label("\(programInfo.weeks)wk", systemImage: "clock")
                                    }
                                    .font(.system(size: 11))
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "info.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(programFamilyColor)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Current Program")
                }
                
                // Units & Rounding
                Section {
                    Toggle("Use Metric (kg)", isOn: $appState.settings.useMetric)
                        .onChange(of: appState.settings.useMetric) { _, useMetric in
                            // Set appropriate defaults when switching unit systems
                            if useMetric {
                                // Metric defaults: 2.5 kg rounding, 20 kg bar
                                appState.settings.roundingIncrement = 5.5  // 2.5 kg
                                appState.settings.barWeight = 44.0  // 20 kg
                            } else {
                                // Imperial defaults: 5 lb rounding, 45 lb bar
                                appState.settings.roundingIncrement = 5.0  // 5 lb
                                appState.settings.barWeight = 45.0  // 45 lb
                            }
                        }
                    
                    Picker("Rounding", selection: $appState.settings.roundingIncrement) {
                        if appState.settings.useMetric {
                            Text("1 kg").tag(2.2)
                            Text("2.5 kg").tag(5.5)
                            Text("5 kg").tag(11.0)
                        } else {
                            Text("2.5 lb").tag(2.5)
                            Text("5 lb").tag(5.0)
                            Text("10 lb").tag(10.0)
                        }
                    }
                    
                    Picker("Barbell Weight", selection: $appState.settings.barWeight) {
                        if appState.settings.useMetric {
                            Text("15 kg").tag(33.0)
                            Text("20 kg").tag(44.0)
                        } else {
                            Text("35 lb").tag(35.0)
                            Text("45 lb").tag(45.0)
                        }
                    }
                } header: {
                    Text("Units & Rounding")
                } footer: {
                    Text("Weights will be rounded to the nearest increment. Barbell weight is used for plate calculations.")
                }
                
                #if DEBUG
                // TODO: Re-enable after reviewing strength standards data sources
                // Bodyweight & Standards
                Section {
                    HStack {
                        Text("Bodyweight")
                        Spacer()
                        TextField(
                            appState.settings.useMetric ? "kg" : "lbs",
                            value: Binding(
                                get: { 
                                    if let bw = appState.settings.bodyweight {
                                        return appState.settings.useMetric ? bw * 0.453592 : bw
                                    }
                                    return nil
                                },
                                set: { newValue in
                                    if let value = newValue {
                                        // Always store in lbs internally
                                        appState.settings.bodyweight = appState.settings.useMetric ? value / 0.453592 : value
                                    } else {
                                        appState.settings.bodyweight = nil
                                    }
                                }
                            ),
                            format: .number.precision(.fractionLength(0))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        
                        Text(appState.settings.useMetric ? "kg" : "lbs")
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    Picker("Sex", selection: $appState.settings.isMale) {
                        Text("Male").tag(true)
                        Text("Female").tag(false)
                    }
                } header: {
                    Text("Strength Standards (DEBUG)")
                } footer: {
                    Text("Used for strength level comparisons in History and Calculators.")
                }
                #endif
                
                // Display
                Section {
                    Picker("Appearance", selection: $appState.settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Choose light mode, dark mode, or follow your device's system setting.")
                }
                
                // Plate Calculator
                Section {
                    if storeManager.canAccess(.plateCalculator) {
                        HStack {
                            Toggle("Show Plate Calculator", isOn: $appState.settings.showPlateCalculator)
                            
                            Button {
                                showingPlateCalculatorInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(SBSColors.accentFallback)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if appState.settings.showPlateCalculator {
                            // Preview of current barbell
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Preview (225 lb)")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textTertiaryFallback)
                                
                                BarbellView(
                                    weight: 225,
                                    useMetric: appState.settings.useMetric,
                                    barWeight: appState.settings.barWeight,
                                    showLabels: true,
                                    compact: true
                                )
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        // Non-premium: show locked toggle with preview and info button
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Show Plate Calculator")
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                Spacer()
                                
                                Button {
                                    showingPlateCalculatorInfo = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                                .buttonStyle(.plain)
                                
                                PremiumBadge(isCompact: true)
                            }
                            
                            // Preview for free users - enticing teaser
                            Button {
                                showingPaywall = true
                            } label: {
                                ZStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Preview (225 lb)")
                                            .font(SBSFonts.caption())
                                            .foregroundStyle(SBSColors.textTertiaryFallback)
                                        
                                        BarbellView(
                                            weight: 225,
                                            useMetric: appState.settings.useMetric,
                                            barWeight: appState.settings.barWeight,
                                            showLabels: true,
                                            compact: true
                                        )
                                    }
                                    .blur(radius: 2)
                                    .opacity(0.6)
                                    
                                    // Unlock overlay
                                    HStack(spacing: 6) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 10))
                                        Text("Tap to unlock")
                                            .font(SBSFonts.captionBold())
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(SBSColors.accentFallback)
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Plate Calculator")
                } footer: {
                    if storeManager.canAccess(.plateCalculator) {
                        Text("Visual barbell display showing which plates to load during workouts.")
                    } else {
                        Text("Never calculate plates in your head again. Upgrade to Premium to enable.")
                    }
                }
                
                // Rest Timer
                Section {
                    Picker("Rest Timer", selection: $appState.settings.restTimerDuration) {
                        Text("1 minute").tag(60)
                        Text("1:30").tag(90)
                        Text("2 minutes").tag(120)
                        Text("2:30").tag(150)
                        Text("3 minutes").tag(180)
                        Text("4 minutes").tag(240)
                        Text("5 minutes").tag(300)
                    }
                    
                    Toggle("Sound Notification", isOn: $appState.settings.playSoundNotifications)
                    
                    Toggle("PR Celebrations", isOn: $appState.settings.showPRCelebrations)
                    
                    // Superset Accessories - Premium feature
                    if storeManager.canAccess(.supersets) {
                        Toggle("Superset Accessories", isOn: $appState.settings.supersetAccessories)
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Text("Superset Accessories")
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                Spacer()
                                PremiumBadge(isCompact: true)
                            }
                        }
                    }
                } header: {
                    Text("Workout Timer")
                } footer: {
                    Text("Sound notification plays a chime when the timer ends (respects silent mode). PR celebrations show a full-screen animation when you achieve a new personal record. When superset is enabled, accessories will be shown during rest periods.")
                }
                
                // Training Maxes
                Section {
                    Button {
                        showingTMEditor = true
                    } label: {
                        HStack {
                            Text("Edit Starting TMs")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                } header: {
                    Text("Training Maxes")
                } footer: {
                    Text("Adjust your Week 1 training maxes. This will recalculate all subsequent weeks.")
                }
                
                // Weight Adjustments
                Section {
                    Button {
                        showingWeightAdjustments = true
                    } label: {
                        HStack {
                            Text("Weight Adjustments")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                } header: {
                    Text("Progression")
                } footer: {
                    Text("Adjust how much your training max changes based on rep-out performance.")
                }
                
                // Exercises
                Section {
                    Button {
                        showingExerciseEditor = true
                    } label: {
                        HStack {
                            Text("Edit Exercises")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Customize which lifts and accessories you do each day.")
                }
                
                // Custom Templates
                Section {
                    Button {
                        showingTemplateList = true
                    } label: {
                        HStack(spacing: SBSLayout.paddingMedium) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [SBSColors.accentFallback.opacity(0.2), SBSColors.accentSecondaryFallback.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: "square.stack.3d.up.fill")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("My Templates")
                                    .font(SBSFonts.bodyBold())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                
                                Text(templateCountText)
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Custom Templates")
                } footer: {
                    Text("Create your own workout programs with custom exercises, sets, and progression rules.")
                }
                
                // Program Cycle
                Section {
                    // Current cycle info
                    HStack {
                        Text("Current Cycle")
                        Spacer()
                        Text("Cycle \(appState.currentCycleNumber)")
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    HStack {
                        Text("Started")
                        Spacer()
                        Text(appState.userData.currentCycleStartDate, style: .date)
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    // Past cycles
                    Button {
                        showingPastCycles = true
                    } label: {
                        HStack {
                            Text("Past Cycles")
                            Spacer()
                            if !appState.cycleHistory.isEmpty {
                                Text("\(appState.cycleHistory.count)")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(SBSColors.surfaceFallback)
                                    )
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    // Start new cycle
                    Button {
                        showingNewCycleOptions = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundStyle(SBSColors.accentFallback)
                            Text("Start New Cycle")
                        }
                    }
                    .foregroundStyle(SBSColors.accentFallback)
                } header: {
                    Text("Program Cycle")
                } footer: {
                    Text("Start a new 20-week cycle. Your current progress will be archived and you can choose to carry over your training maxes.")
                }
                
                // Data
                Section {
                    Button {
                        exportData = try? appState.exportData()
                        showingExport = true
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Data")
                }
                
                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset All Logs", systemImage: "trash")
                    }
                } header: {
                    Text("Reset")
                } footer: {
                    Text("This will clear all your logged reps. Training max settings will be preserved.")
                }
                
                // About
                Section {
                    
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    // Premium status
                    HStack {
                        Text("Premium")
                        Spacer()
                        if storeManager.isPremium {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SBSColors.success)
                                Text("Active")
                                    .foregroundStyle(SBSColors.success)
                            }
                        } else {
                            Text("Free")
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                    }
                    
                    // Restore Purchases button
                    Button {
                        Task {
                            isRestoringPurchases = true
                            await storeManager.restorePurchases()
                            isRestoringPurchases = false
                        }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            Spacer()
                            if isRestoringPurchases {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRestoringPurchases)
                } header: {
                    Text("About")
                }
                
                // More Apps - Cross promotion
                Section {
                    Link(destination: URL(string: "https://apps.apple.com/us/app/top-set-timer/id6756226855")!) {
                        HStack(spacing: SBSLayout.paddingMedium) {
                            Image("TopSetTimerIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Top Set Timer")
                                    .font(SBSFonts.bodyBold())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                
                                Text("Rest timer built for strength training")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 14))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("More Apps")
                } footer: {
                    Text("A no-frills workout timer for Rest, HIIT, and EMOM modes.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingTMEditor) {
                TMEditorView(appState: appState)
            }
            .sheet(isPresented: $showingExerciseEditor) {
                ExerciseEditorView(appState: appState)
            }
            .sheet(isPresented: $showingWeightAdjustments) {
                WeightAdjustmentsEditorView(appState: appState)
            }
            .sheet(isPresented: $showingPastCycles) {
                PastCyclesView(appState: appState)
            }
            .sheet(isPresented: $showingTemplateList) {
                TemplateListView(appState: appState)
            }
            .fullScreenCover(isPresented: $showingNewCycleBuilder) {
                CycleBuilderView(
                    appState: appState,
                    isOnboarding: false,
                    onComplete: {
                        showingNewCycleBuilder = false
                    },
                    onCancel: {
                        showingNewCycleBuilder = false
                    }
                )
            }
            .sheet(isPresented: $showingExport) {
                if let data = exportData {
                    ShareSheet(items: [ExportFile(data: data)])
                }
            }
            .alert("Reset All Logs?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    appState.resetLogs()
                }
            } message: {
                Text("This will permanently delete all your logged reps. This cannot be undone.")
            }
            .confirmationDialog(
                "Start New Cycle",
                isPresented: $showingNewCycleOptions,
                titleVisibility: .visible
            ) {
                Button("Quick Repeat") {
                    // Start new cycle with same program and carried-over TMs
                    appState.startNewCycle(carryOverTMs: true)
                }
                
                Button("Customize New Cycle") {
                    showingNewCycleBuilder = true
                }
                
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Quick Repeat will start a new cycle with your current program and carry over your training maxes. Choose Customize to change program, exercises, or adjust maxes.")
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
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
            .sheet(isPresented: $showingPlateCalculatorInfo) {
                PlateCalculatorInfoView(
                    useMetric: appState.settings.useMetric,
                    barWeight: appState.settings.barWeight,
                    showingPaywall: $showingPaywall
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

// MARK: - TM Editor View

struct TMEditorView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.liftNames, id: \.self) { lift in
                    TMEditRow(
                        liftName: lift,
                        currentValue: appState.initialMax(for: lift),
                        defaultValue: appState.programData?.initialMaxes[lift] ?? 0,
                        useMetric: appState.settings.useMetric,
                        onChange: { newValue in
                            appState.setInitialMax(for: lift, value: newValue)
                        },
                        onReset: {
                            appState.resetInitialMax(for: lift)
                        }
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Starting TMs")
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
}

struct TMEditRow: View {
    let liftName: String
    let currentValue: Double
    let defaultValue: Double
    let useMetric: Bool
    let onChange: (Double) -> Void
    let onReset: () -> Void
    
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(liftName)
                    .font(SBSFonts.bodyBold())
                
                Spacer()
                
                if currentValue != defaultValue {
                    Button("Reset") {
                        onReset()
                        inputText = formatValue(defaultValue)
                    }
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.accentFallback)
                }
            }
            
            HStack {
                TextField("Weight", text: $inputText)
                    .keyboardType(.decimalPad)
                    .font(SBSFonts.number())
                    .focused($isFocused)
                    .onChange(of: inputText) { _, newValue in
                        if let value = parseInput(newValue) {
                            onChange(value)
                        }
                    }
                
                Text(useMetric ? "kg" : "lb")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(SBSColors.backgroundFallback)
            )
        }
        .onAppear {
            inputText = formatValue(currentValue)
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        let displayValue = useMetric ? value * 0.453592 : value
        if displayValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(displayValue))
        }
        return String(format: "%.1f", displayValue)
    }
    
    private func parseInput(_ text: String) -> Double? {
        guard let value = Double(text) else { return nil }
        // Convert back to lb if using metric
        return useMetric ? value / 0.453592 : value
    }
}

// MARK: - Weight Adjustments Editor View

struct WeightAdjustmentsEditorView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    AdjustmentRow(
                        label: "Below target by 2+ reps",
                        value: $appState.settings.weightAdjustments.belowBy2Plus,
                        defaultValue: WeightAdjustments.default.belowBy2Plus
                    )
                    
                    AdjustmentRow(
                        label: "Below target by 1 rep",
                        value: $appState.settings.weightAdjustments.belowBy1,
                        defaultValue: WeightAdjustments.default.belowBy1
                    )
                } header: {
                    Text("Below Target")
                } footer: {
                    Text("Negative values reduce your training max.")
                }
                
                Section {
                    AdjustmentRow(
                        label: "Hit rep target",
                        value: $appState.settings.weightAdjustments.hitTarget,
                        defaultValue: WeightAdjustments.default.hitTarget
                    )
                } header: {
                    Text("On Target")
                }
                
                Section {
                    AdjustmentRow(
                        label: "Beat by 1 rep",
                        value: $appState.settings.weightAdjustments.beatBy1,
                        defaultValue: WeightAdjustments.default.beatBy1
                    )
                    
                    AdjustmentRow(
                        label: "Beat by 2 reps",
                        value: $appState.settings.weightAdjustments.beatBy2,
                        defaultValue: WeightAdjustments.default.beatBy2
                    )
                    
                    AdjustmentRow(
                        label: "Beat by 3 reps",
                        value: $appState.settings.weightAdjustments.beatBy3,
                        defaultValue: WeightAdjustments.default.beatBy3
                    )
                    
                    AdjustmentRow(
                        label: "Beat by 4 reps",
                        value: $appState.settings.weightAdjustments.beatBy4,
                        defaultValue: WeightAdjustments.default.beatBy4
                    )
                    
                    AdjustmentRow(
                        label: "Beat by 5+ reps",
                        value: $appState.settings.weightAdjustments.beatBy5Plus,
                        defaultValue: WeightAdjustments.default.beatBy5Plus
                    )
                } header: {
                    Text("Above Target")
                } footer: {
                    Text("Positive values increase your training max for the next week.")
                }
                
                Section {
                    Button(role: .destructive) {
                        appState.settings.weightAdjustments = .default
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Weight Adjustments")
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
}

struct AdjustmentRow: View {
    let label: String
    @Binding var value: Double
    let defaultValue: Double
    
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(SBSFonts.body())
            
            Spacer()
            
            HStack(spacing: 4) {
                TextField("0", text: $inputText)
                    .keyboardType(.decimalPad)
                    .font(SBSFonts.number())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused($isFocused)
                    .onChange(of: inputText) { _, newValue in
                        if let parsed = parseInput(newValue) {
                            value = parsed
                        }
                    }
                
                Text("%")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(SBSColors.backgroundFallback)
            )
        }
        .onAppear {
            inputText = formatValue(value)
        }
        .onChange(of: value) { _, newValue in
            if !isFocused {
                inputText = formatValue(newValue)
            }
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        let percent = value * 100
        if percent == 0 {
            return "0"
        }
        // Show sign for non-zero values
        let formatted = String(format: "%.1f", percent)
        if percent > 0 {
            return "+\(formatted)"
        }
        return formatted
    }
    
    private func parseInput(_ text: String) -> Double? {
        // Remove any leading + sign for parsing
        let cleanText = text.replacingOccurrences(of: "+", with: "")
        guard let percent = Double(cleanText) else { return nil }
        return percent / 100.0
    }
}

// MARK: - Exercise Editor View

struct ExerciseEditorView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Int = 1
    @State private var showingExercisePicker = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Day picker
                Picker("Day", selection: $selectedDay) {
                    ForEach(1...5, id: \.self) { day in
                        Text("Day \(day)").tag(day)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                List {
                    // Main lifts section
                    Section {
                        ForEach(Array(mainLifts.enumerated()), id: \.offset) { index, item in
                            MainLiftRow(
                                item: item,
                                availableLifts: appState.availableLifts,
                                onSwap: { newLift in
                                    if let oldLift = item.lift {
                                        appState.swapMainLift(day: selectedDay, oldLift: oldLift, newLift: newLift)
                                    }
                                }
                            )
                        }
                    } header: {
                        Text("Main Lifts")
                    } footer: {
                        Text("Tap to swap for a different lift.")
                    }
                    
                    // Accessories section
                    Section {
                        ForEach(Array(accessories.enumerated()), id: \.offset) { index, item in
                            AccessoryRow(
                                name: item.name,
                                onRename: { newName in
                                    let actualIndex = accessoryStartIndex + index
                                    appState.updateAccessory(day: selectedDay, at: actualIndex, newName: newName)
                                },
                                onDelete: {
                                    let actualIndex = accessoryStartIndex + index
                                    appState.removeItem(from: selectedDay, at: actualIndex)
                                }
                            )
                        }
                        
                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add Accessory", systemImage: "plus.circle.fill")
                        }
                    } header: {
                        Text("Accessories")
                    }
                    
                    // Reset section
                    if appState.hasCustomExercises(for: selectedDay) {
                        Section {
                            Button(role: .destructive) {
                                appState.resetDayItems(for: selectedDay)
                            } label: {
                                Label("Reset Day \(selectedDay) to Default", systemImage: "arrow.counterclockwise")
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                AccessoryExercisePickerSheet(
                    title: "Add Accessory",
                    onSelect: { exerciseName in
                        appState.addAccessory(to: selectedDay, name: exerciseName)
                        showingExercisePicker = false
                    },
                    onCancel: { showingExercisePicker = false },
                    mainLiftsOnly: false
                )
            }
        }
    }
    
    private var dayItems: [DayItem] {
        appState.dayItems(for: selectedDay)
    }
    
    private var mainLifts: [DayItem] {
        dayItems.filter { $0.type == .tm || $0.type == .volume }
    }
    
    private var accessories: [DayItem] {
        dayItems.filter { $0.type == .accessory }
    }
    
    private var accessoryStartIndex: Int {
        dayItems.firstIndex { $0.type == .accessory } ?? dayItems.count
    }
}

// MARK: - Main Lift Row

struct MainLiftRow: View {
    let item: DayItem
    let availableLifts: [String]
    let onSwap: (String) -> Void
    
    @State private var showingPicker = false
    
    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    if item.type == .tm {
                        Text("Training Max")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    } else if item.type == .volume {
                        Text("Working Sets")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
        }
        .sheet(isPresented: $showingPicker) {
            AccessoryExercisePickerSheet(
                title: "Select Main Lift",
                onSelect: { lift in
                    onSwap(lift)
                    showingPicker = false
                },
                onCancel: {
                    showingPicker = false
                },
                mainLiftsOnly: false,
                showFilterChips: true,  // Show filter to toggle compound lifts
                currentExercise: item.lift
            )
        }
    }
}

// MARK: - Accessory Row

struct AccessoryRow: View {
    let name: String
    let onRename: (String) -> Void
    let onDelete: () -> Void
    
    @State private var isEditing = false
    @State private var editedName: String = ""
    
    var body: some View {
        HStack {
            if isEditing {
                TextField("Accessory name", text: $editedName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !editedName.isEmpty {
                            onRename(editedName)
                        }
                        isEditing = false
                    }
                
                Button("Save") {
                    if !editedName.isEmpty {
                        onRename(editedName)
                    }
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(name)
                    .font(SBSFonts.body())
                
                Spacer()
                
                Button {
                    editedName = name
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(SBSColors.accentFallback)
                }
                .buttonStyle(.plain)
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(SBSColors.error)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Export File

class ExportFile: NSObject, UIActivityItemSource {
    let data: Data
    let filename: String
    let fileURL: URL
    
    init(data: Data) {
        self.data = data
        // Create a filename with the current date
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: Date())
        self.filename = "topset_backup_\(dateString).json"
        
        // Write data to a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        self.fileURL = tempDir.appendingPathComponent(self.filename)
        try? data.write(to: self.fileURL)
        
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        "Workout Program Backup"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        UTType.json.identifier
    }
}

#Preview {
    SettingsView(appState: AppState())
}

