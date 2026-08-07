import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var exportPayload: ExportPayload?
    @State private var showingResetAlert = false
    @State private var showingTMEditor = false
    @State private var showingExerciseEditor = false
    @State private var showingPastCycles = false
    @State private var showingNewCycleAlert = false
    @State private var showingNewCycleBuilder = false
    @State private var showingNewCycleOptions = false
    @State private var showingNewCycleWarning = false
    @State private var showingWeightAdjustments = false
    @State private var showingTemplateList = false
    @State private var carryOverTMs = true
    @State private var showingPaywall = false
    @State private var isRestoringPurchases = false
    @State private var programInfoSheet: AppState.AvailableProgramInfo?
    @State private var showingPlateCalculatorInfo = false
    @State private var versionTapCount = 0
    @State private var lastVersionTapTime: Date?
    @State private var showingReviewerLogin = false
    @State private var showingReviewerUnlockAlert = false
    
    private let storeManager = StoreManager.shared

    private var roundingChoices: [(value: Double, label: String)] {
        if appState.settings.useMetric {
            return [
                (1 * BarWeightOptions.lbPerKg, "1 kg"),
                (2.5 * BarWeightOptions.lbPerKg, "2.5 kg"),
                (5 * BarWeightOptions.lbPerKg, "5 kg"),
            ]
        } else {
            return [(2.5, "2.5 lb"), (5.0, "5 lb"), (10.0, "10 lb")]
        }
    }

    private var roundingBinding: Binding<Double> {
        Binding(
            get: {
                let current = appState.settings.roundingIncrement
                return roundingChoices.first { abs($0.value - current) <= 0.3 }?.value ?? current
            },
            set: { appState.settings.roundingIncrement = $0 }
        )
    }

    private var barWeightChoices: [BarWeightOption] {
        let base = BarWeightOptions.options(useMetric: appState.settings.useMetric)
        let current = appState.settings.barWeight
        if BarWeightOptions.selection(for: current, useMetric: appState.settings.useMetric) == nil {
            return base + [BarWeightOption(value: current, label: current.formattedWeight(useMetric: appState.settings.useMetric))]
        }
        return base
    }

    private var barWeightBinding: Binding<Double> {
        Binding(
            get: {
                BarWeightOptions.selection(for: appState.settings.barWeight, useMetric: appState.settings.useMetric)
                    ?? appState.settings.barWeight
            },
            set: { appState.settings.barWeight = $0 }
        )
    }

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
                        programInfoSheet = currentProgramInfo
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
                                Text(appState.programDisplayName)
                                    .font(SBSFonts.bodyBold())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                
                                if let programInfo = currentProgramInfo {
                                    HStack(spacing: 8) {
                                        Label("\(programInfo.days)d/wk", systemImage: "calendar")
                                        Label("\(programInfo.weeks)wk", systemImage: "clock")
                                    }
                                    .font(SBSFonts.caption2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                            }
                            
                            Spacer()

                            if currentProgramInfo != nil {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(programFamilyColor)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(currentProgramInfo == nil)
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
                                appState.settings.roundingIncrement = 2.5 * BarWeightOptions.lbPerKg
                                appState.settings.barWeight = 20 * BarWeightOptions.lbPerKg
                            } else {
                                // Imperial defaults: 5 lb rounding, 45 lb bar
                                appState.settings.roundingIncrement = 5.0
                                appState.settings.barWeight = 45.0
                            }
                        }

                    Picker("Rounding", selection: roundingBinding) {
                        ForEach(roundingChoices, id: \.value) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }

                    Picker("Barbell Weight", selection: barWeightBinding) {
                        ForEach(barWeightChoices) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                } header: {
                    Text("Units & Rounding")
                } footer: {
                    Text("Weights will be rounded to the nearest increment. Barbell weight is used for plate calculations.")
                }
                
                // Bodyweight & Standards
                Section {
                    HStack {
                        Text("Bodyweight")
                        Spacer()
                        TextField(
                            appState.settings.useMetric ? "kg" : "lb",
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
                        
                        Text(appState.settings.useMetric ? "kg" : "lb")
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    // Fetch from HealthKit button
                    if HealthKitManager.shared.isHealthKitAvailable {
                        Button {
                            Task {
                                await fetchBodyWeightFromHealthKit()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "heart.text.square.fill")
                                    .foregroundStyle(.red)
                                Text("Fetch from HealthKit")
                            }
                        }
                    }
                    
                } header: {
                    Text("Strength Scores")
                } footer: {
                    Text("Used for strength scores in History and Calculators.")
                }
                
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
                    
                    Toggle("Push Notifications", isOn: Binding(
                        get: { appState.settings.pushNotificationsEnabled },
                        set: { newValue in
                            if newValue {
                                // Request permission when enabling
                                Task {
                                    let granted = await NotificationManager.shared.requestAuthorization()
                                    await MainActor.run {
                                        appState.settings.pushNotificationsEnabled = granted
                                    }
                                }
                            } else {
                                appState.settings.pushNotificationsEnabled = false
                            }
                        }
                    ))
                    
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
                    Text("Sound notification plays a chime when the timer ends (respects silent mode). Push notifications alert you when the rest timer ends while the app is in the background. PR celebrations show a full-screen animation when you achieve a new personal record. When superset is enabled, accessories will be shown during rest periods.")
                }
                
                // HealthKit / Apple Fitness Integration (Premium)
                Section {
                    if StoreManager.shared.canAccess(.appleFitness) {
                        Toggle(isOn: $appState.settings.healthKitEnabled) {
                            HStack(spacing: SBSLayout.paddingMedium) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.red)
                                }
                                
                                Text("Enable HealthKit Sync")
                            }
                        }
                        .onChange(of: appState.settings.healthKitEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    do {
                                        try await HealthKitManager.shared.requestAuthorization()
                                        if !HealthKitManager.shared.isAuthorized {
                                            appState.settings.healthKitEnabled = false
                                        }
                                    } catch {
                                        appState.settings.healthKitEnabled = false
                                    }
                                }
                            }
                        }
                        
                        if HealthKitManager.shared.isHealthKitAvailable {
                            HStack {
                                Text("HealthKit Status")
                                Spacer()
                                if appState.settings.healthKitEnabled && HealthKitManager.shared.isAuthorized {
                                    Label("Connected", systemImage: "checkmark.circle.fill")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(.green)
                                } else if appState.settings.healthKitEnabled {
                                    Label("Pending", systemImage: "exclamationmark.circle.fill")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("Disabled")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                            }
                            
                            // Show what data is accessed
                            if appState.settings.healthKitEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Data Accessed via HealthKit:")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("Workouts (write)", systemImage: "figure.strengthtraining.traditional")
                                        Label("Active Energy (write)", systemImage: "flame.fill")
                                        Label("Body Weight (read)", systemImage: "scalemass.fill")
                                        Label("Heart Rate (read, via Watch)", systemImage: "heart.fill")
                                    }
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } else {
                        // Show premium prompt for free users
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack(spacing: SBSLayout.paddingMedium) {
                                ZStack {
                                    Circle()
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.red)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enable HealthKit Sync")
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                    
                                    Text("Premium Feature")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.accentFallback)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SBSColors.accentFallback)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(.red)
                        Text("HealthKit & Apple Fitness")
                        if !StoreManager.shared.canAccess(.appleFitness) {
                            Text("PRO")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SBSColors.accentFallback)
                                .cornerRadius(4)
                        }
                    }
                } footer: {
                    if StoreManager.shared.canAccess(.appleFitness) {
                        if HealthKitManager.shared.isHealthKitAvailable {
                            Text("This app uses Apple HealthKit to log workouts to Apple Fitness. When enabled, starting a workout automatically begins a Strength Training workout. Your workout duration, calories burned, and heart rate (via Apple Watch) are tracked and saved to the Health app when you finish.")
                        } else {
                            Text("HealthKit is not available on this device.")
                        }
                    } else {
                        Text("Upgrade to Premium to use HealthKit and automatically log your workouts to Apple Fitness with duration, calories, and volume tracking.")
                    }
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
                        if appState.hasLoggedData {
                            showingNewCycleWarning = true
                        } else {
                            showingNewCycleOptions = true
                        }
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
                    Text("Start a new \(appState.weeks.count)-week cycle. Your current progress will be archived and you can choose to carry over your training maxes.")
                }
                
                // Data
                Section {
                    Button {
                        if let data = try? appState.exportData() {
                            exportPayload = ExportPayload(data: data)
                        }
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
                        Text(appVersionString)
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleVersionTap()
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

                // Legal
                Section {
                    Link(destination: URL(string: "https://gregorymcinnes.com/apps/top-set-training/")!) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 12))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                    Link(destination: URL(string: "https://gregorymcinnes.com/terms")!) {
                        HStack {
                            Text("Terms of Use")
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 12))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                } header: {
                    Text("Legal")
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
                    
                    Link(destination: URL(string: "https://apps.apple.com/us/app/top-set-calculator/id6757142146")!) {
                        HStack(spacing: SBSLayout.paddingMedium) {
                            Image("TopSetCalculatorIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Top Set Calculator")
                                    .font(SBSFonts.bodyBold())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                
                                Text("Strength calculators & tools")
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
                    Text("More From Top Set")
                } footer: {
                    Text("More strength training tools from Top Set Training.")
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
            .sheet(item: $exportPayload) { payload in
                ShareSheet(items: [ExportFile(data: payload.data)])
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
                    // Repeating re-runs the current program, so it needs program
                    // access (grandfathered users hit the paywall here; their
                    // in-progress cycle is unaffected).
                    if let programId = appState.userData.selectedProgram,
                       !StoreManager.shared.canAccessProgram(programId) {
                        showingPaywall = true
                    } else {
                        // Start new cycle with same program and carried-over TMs
                        appState.startNewCycle(carryOverTMs: true)
                    }
                }
                
                Button("Customize New Cycle") {
                    showingNewCycleBuilder = true
                }
                
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Quick Repeat will start a new cycle with your current program and carry over your training maxes. Choose Customize to change program, exercises, or adjust maxes.")
            }
            .alert("Start New Cycle?", isPresented: $showingNewCycleWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    showingNewCycleOptions = true
                }
            } message: {
                Text("You have a cycle in progress. Starting a new cycle will clear your current cycle's workout data. Your workout history will still be available in Past Cycles.")
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(item: $programInfoSheet) { programInfo in
                ProgramDetailView(
                    program: programInfo,
                    programData: appState.programData,
                    familyColor: programFamilyColor,
                    level: programExperienceLevel
                )
            }
            .sheet(isPresented: $showingPlateCalculatorInfo) {
                PlateCalculatorInfoView(
                    useMetric: appState.settings.useMetric,
                    barWeight: appState.settings.barWeight,
                    showingPaywall: $showingPaywall
                )
            }
            .sheet(isPresented: $showingReviewerLogin) {
                ReviewerLoginView(
                    onSuccess: {
                        showingReviewerLogin = false
                        storeManager.toggleReviewerUnlock()
                        showingReviewerUnlockAlert = true
                    },
                    onCancel: {
                        showingReviewerLogin = false
                    }
                )
            }
            .alert(
                storeManager.isReviewerUnlocked ? "Reviewer Mode Enabled" : "Reviewer Mode Disabled",
                isPresented: $showingReviewerUnlockAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storeManager.isReviewerUnlocked 
                     ? "Premium features are now unlocked for review."
                     : "Premium features have been locked.")
            }
        }
    }
    
    // MARK: - App Version

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return version
        }
        return "\(version) (\(build))"
    }

    // MARK: - Secret Reviewer Unlock

    private func handleVersionTap() {
        let now = Date()
        
        // Reset counter if more than 1.5 seconds since last tap
        if let lastTap = lastVersionTapTime, now.timeIntervalSince(lastTap) > 1.5 {
            versionTapCount = 0
        }
        
        lastVersionTapTime = now
        versionTapCount += 1
        
        // Show login after 7 consecutive taps
        if versionTapCount >= 7 {
            versionTapCount = 0
            showingReviewerLogin = true
        }
    }
    
    // MARK: - HealthKit Body Weight
    
    private func fetchBodyWeightFromHealthKit() async {
        // Request authorization if needed
        if !HealthKitManager.shared.isAuthorized {
            try? await HealthKitManager.shared.requestAuthorization()
        }
        
        // Fetch body weight (returns kg)
        if let weightKg = await HealthKitManager.shared.getUserBodyWeight() {
            // Convert kg to lbs for internal storage
            let weightLbs = weightKg / 0.453592
            appState.settings.bodyweight = weightLbs
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
                    ForEach(appState.allDays, id: \.self) { day in
                        Text("Day \(day)").tag(day)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onAppear {
                    if !appState.allDays.contains(selectedDay) {
                        selectedDay = appState.allDays.first ?? 1
                    }
                }
                
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
        dayItems.filter { $0.type == .tm || $0.type == .volume || $0.type == .structured || $0.type == .linear }
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

    private var liftSubtitle: String? {
        switch item.type {
        case .tm: return "Training Max"
        case .volume: return "Working Sets"
        case .structured, .linear: return "Main Lift"
        default: return nil
        }
    }

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    if let subtitle = liftSubtitle {
                        Text(subtitle)
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
                .accessibilityLabel("Rename accessory")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(SBSColors.error)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete accessory")
            }
        }
    }
}

// MARK: - Share Sheet

/// Identifiable wrapper so the data-export sheet is presented via `.sheet(item:)`,
/// guaranteeing the data exists when the sheet's content is built
/// (avoids a blank sheet on the first tap).
struct ExportPayload: Identifiable {
    let id = UUID()
    let data: Data
}

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

// MARK: - Reviewer Login View

struct ReviewerLoginView: View {
    let onSuccess: () -> Void
    let onCancel: () -> Void
    
    @State private var username = ""
    @State private var password = ""
    @State private var showError = false
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case username, password
    }
    
    // Credentials for Apple reviewers (provide these in App Store Connect review notes)
    private let validUsername = "app_review"
    private let validPassword = "TopSet2026!"
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(SBSColors.accentFallback)
                
                Text("Reviewer Access")
                    .font(SBSFonts.title())
                
                Text("Enter your credentials to unlock premium features for review.")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 16) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit {
                            attemptLogin()
                        }
                }
                .padding(.horizontal, 32)
                
                if showError {
                    Text("Invalid credentials")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.error)
                }
                
                Button {
                    attemptLogin()
                } label: {
                    Text("Sign In")
                        .font(SBSFonts.bodyBold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(SBSColors.accentFallback)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
                }
                .padding(.horizontal, 32)
                .disabled(username.isEmpty || password.isEmpty)
                .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1)
                
                Spacer()
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            focusedField = .username
        }
    }
    
    private func attemptLogin() {
        if username.lowercased() == validUsername.lowercased() && password == validPassword {
            showError = false
            onSuccess()
        } else {
            showError = true
            password = ""
        }
    }
}

#Preview {
    SettingsView(appState: AppState())
}

