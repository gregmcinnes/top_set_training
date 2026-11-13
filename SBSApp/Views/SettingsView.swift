import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ViewBuilder private var restDurationOptions: some View {
        Text("1 minute").tag(60)
        Text("1:30").tag(90)
        Text("2 minutes").tag(120)
        Text("2:30").tag(150)
        Text("3 minutes").tag(180)
        Text("4 minutes").tag(240)
        Text("5 minutes").tag(300)
    }

    @Bindable var appState: AppState
    @State private var exportPayload: ExportPayload?
    @State private var showingResetAlert = false
    @State private var showingTMEditor = false
    @State private var showingExerciseEditor = false
    @State private var showingPastCycles = false
    @State private var showingNewCycleAlert = false
    @State private var showingNewCycleBuilder = false
    @State private var showingNewCycleOptions = false
    @State private var builderOpenedOnFinishedCycle = false
    @State private var showingWeightAdjustments = false
    @State private var showingTemplateList = false
    @State private var carryOverTMs = true
    @State private var showingPaywall = false
    @State private var showingManageSubscription = false
    @State private var isRestoringPurchases = false
    @State private var programInfoSheet: AppState.AvailableProgramInfo?
    @State private var showingPlateCalculatorInfo = false
    @State private var showingImporter = false
    @State private var pendingImportData: Data?
    @State private var showingImportConfirm = false
    @State private var showingDataAlert = false
    @State private var dataAlertTitle = ""
    @State private var dataAlertMessage = ""
    
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

    /// A standard load for the plate preview, on the plate grid of the user's unit.
    private var platePreviewWeight: Double {
        appState.settings.useMetric ? 100 * BarWeightOptions.lbPerKg : 225
    }

    private var platePreviewLabel: String {
        appState.settings.useMetric ? "Preview (100 kg)" : "Preview (225 lb)"
    }

    private func showDataAlert(title: String, message: String) {
        dataAlertTitle = title
        dataAlertMessage = message
        showingDataAlert = true
    }

    /// Read a chosen backup and ask for confirmation before anything is overwritten.
    /// UserData decodes leniently (every field is optional), so an unrelated JSON file
    /// would "succeed" as empty data; require keys a real export always contains.
    private func handleImportSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["logs"] != nil, object["cycleHistory"] != nil else {
                showDataAlert(title: "Couldn't Restore", message: "That file isn't a Top Set Training backup. Nothing was changed.")
                return
            }
            pendingImportData = data
            showingImportConfirm = true
        } catch {
            showDataAlert(title: "Couldn't Restore", message: "The file couldn't be read. Nothing was changed.")
        }
    }

    private func restorePendingImport() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            try appState.importData(data)
            // The active program may have changed with the restored selection.
            Task { try? await appState.loadProgramConfig() }
            showDataAlert(title: "Backup Restored", message: "Your data was restored from the backup.")
        } catch {
            showDataAlert(title: "Couldn't Restore", message: "The backup couldn't be read. Nothing was changed.")
        }
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
                // An empty section whose header is the title: as a plain row it sat under
                // the grouped style's top gap, lower than the other tabs' titles.
                Section {
                } header: {
                    SBSTabHeader("Settings")
                        .textCase(nil)
                        .padding(.horizontal, SBSLayout.space4)
                        .padding(.top, SBSLayout.space2)
                        .listRowInsets(EdgeInsets())
                }

                // Premium Section - only show for non-premium users
                if !storeManager.isPremium {
                    Section {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack(spacing: SBSLayout.space3) {
                                Image(systemName: "crown.fill")
                                    .font(SBSFonts.heading())
                                    .foregroundStyle(Color.orangeText)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Upgrade to Premium")
                                        .font(SBSFonts.bodyStrong())
                                        .foregroundStyle(Color.ink)

                                    Text("Unlock all programs & features")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(Color.inkSecondary)
                                }

                                Spacer()

                                Text(storeManager.premiumPriceString)
                                    .font(SBSFonts.number())
                                    .foregroundStyle(Color.ink)

                                SBSChevron()
                            }
                        }
                    }
                    .sbsListRows()
                }

                // Current Program
                Section {
                    Button {
                        programInfoSheet = currentProgramInfo
                    } label: {
                        HStack(spacing: SBSLayout.space3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appState.programDisplayName)
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.ink)

                                if let programInfo = currentProgramInfo {
                                    SBSRowSubtitle("\(programInfo.days) days/week · \(programInfo.weeks) weeks")
                                }
                            }

                            Spacer()

                            if currentProgramInfo != nil {
                                Image(systemName: "info.circle")
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.orangeText)
                                    .accessibilityLabel("Program info")
                            }
                        }
                    }
                    .disabled(currentProgramInfo == nil)
                } header: {
                    SBSListHeader("Current Program")
                }
                .sbsListRows()

                // Units & Rounding
                Section {
                    Toggle("Use Metric (kg)", isOn: $appState.settings.useMetric)
                        .onChange(of: appState.settings.useMetric) { _, useMetric in
                            BarWeightOptions.applyUnitDefaults(to: &appState.settings, useMetric: useMetric)
                        }

                    Picker("Rounding", selection: roundingBinding) {
                        ForEach(roundingChoices, id: \.value) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                    .sbsValuePicker()

                    Picker("Barbell Weight", selection: barWeightBinding) {
                        ForEach(barWeightChoices) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .sbsValuePicker()
                } header: {
                    SBSListHeader("Units & Rounding")
                } footer: {
                    SBSListFooter("Weights will be rounded to the nearest increment. Barbell weight is used for plate calculations.")
                }
                .sbsListRows()

                // Bodyweight & Standards
                Section {
                    HStack {
                        Text("Bodyweight")
                        Spacer()
                        TextField(
                            "Not set",
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
                        .font(SBSFonts.numberUnit())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)

                        Text(appState.settings.useMetric ? "kg" : "lb")
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)
                    }

                    // Scoring formulas use different coefficients for men and women
                    Picker("Scoring Category", selection: $appState.settings.isMale) {
                        Text("Men").tag(true)
                        Text("Women").tag(false)
                    }
                    .sbsValuePicker()

                    // Fetch from HealthKit button
                    if HealthKitManager.shared.isHealthKitAvailable {
                        Button {
                            Task {
                                await fetchBodyWeightFromHealthKit()
                            }
                        } label: {
                            Label("Fetch from HealthKit", systemImage: "heart.text.square")
                        }
                    }

                } header: {
                    SBSListHeader("Strength Scores")
                } footer: {
                    SBSListFooter("Used for strength scores in History and Calculators.")
                }
                .sbsListRows()

                // Display
                Section {
                    Picker("Appearance", selection: $appState.settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .sbsValuePicker()
                } header: {
                    SBSListHeader("Display")
                } footer: {
                    SBSListFooter("Choose light mode, dark mode, or follow your device's system setting.")
                }
                .sbsListRows()

                // Plate Calculator
                Section {
                    if storeManager.canAccess(.plateCalculator) {
                        HStack(spacing: SBSLayout.space3) {
                            Button {
                                showingPlateCalculatorInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.orangeText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("About the plate calculator")

                            Toggle("Show Plate Calculator", isOn: $appState.settings.showPlateCalculator)
                        }

                        if appState.settings.showPlateCalculator {
                            // Preview of current barbell
                            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                                SBSEyebrow(platePreviewLabel)
                                    .foregroundStyle(Color.inkSecondary)

                                BarbellView(
                                    weight: platePreviewWeight,
                                    useMetric: appState.settings.useMetric,
                                    barWeight: appState.settings.barWeight,
                                    showLabels: true,
                                    compact: true
                                )
                            }
                            .padding(.vertical, SBSLayout.space1)
                        }

                        NavigationLink {
                            BarsSettingsView(appState: appState)
                        } label: {
                            HStack {
                                Text("My Bars")
                                Spacer()
                                if !appState.settings.bars.isEmpty {
                                    Text("\(appState.settings.bars.count)")
                                        .font(SBSFonts.numberSmall())
                                        .foregroundStyle(Color.inkSecondary)
                                }
                            }
                        }
                    } else {
                        // Non-premium: show locked toggle with preview and info button
                        VStack(alignment: .leading, spacing: SBSLayout.space3) {
                            HStack(spacing: SBSLayout.space3) {
                                Text("Show Plate Calculator")
                                    .foregroundStyle(Color.ink)
                                Spacer()

                                Button {
                                    showingPlateCalculatorInfo = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(SBSFonts.bodyStrong())
                                        .foregroundStyle(Color.orangeText)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("About the plate calculator")

                                SBSBadge(text: "Pro", variant: .pro)
                            }

                            // Preview for free users - enticing teaser
                            Button {
                                showingPaywall = true
                            } label: {
                                ZStack {
                                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                                        SBSEyebrow(platePreviewLabel)
                                            .foregroundStyle(Color.inkSecondary)

                                        BarbellView(
                                            weight: platePreviewWeight,
                                            useMetric: appState.settings.useMetric,
                                            barWeight: appState.settings.barWeight,
                                            showLabels: true,
                                            compact: true
                                        )
                                    }
                                    .blur(radius: 2)
                                    .opacity(0.6)

                                    // Unlock tag
                                    SBSBadge(text: "Tap to unlock", variant: .pro, systemImage: "lock.fill")
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, SBSLayout.space1)

                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Text("My Bars")
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                SBSBadge(text: "Pro", variant: .pro)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("EZ, hex and specialty bars for the plate calculator. Opens the upgrade screen.")
                    }
                } header: {
                    SBSListHeader("Plate Calculator")
                } footer: {
                    if storeManager.canAccess(.plateCalculator) {
                        SBSListFooter("Visual barbell display showing which plates to load during workouts. Add your EZ, hex or other bars under My Bars.")
                    } else {
                        SBSListFooter("Never calculate plates in your head again. Upgrade to Premium to enable.")
                    }
                }
                .sbsListRows()

                // Rest Timer
                Section {
                    Picker("Main Lift Rest", selection: $appState.settings.restTimerDuration) {
                        restDurationOptions
                    }
                    .sbsValuePicker()

                    Picker("Accessory Rest", selection: $appState.settings.accessoryRestSeconds) {
                        restDurationOptions
                    }
                    .sbsValuePicker()

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

                    Toggle("Celebrate PRs with confetti", isOn: $appState.settings.prConfetti)

                    // Superset Accessories - Premium feature
                    if storeManager.canAccess(.supersets) {
                        Toggle("Superset Accessories", isOn: $appState.settings.supersetAccessories)
                    } else {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Text("Superset Accessories")
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                SBSBadge(text: "Pro", variant: .pro)
                            }
                        }
                    }
                } header: {
                    SBSListHeader("Workout Timer")
                } footer: {
                    SBSListFooter("Sound notification plays a chime when the timer ends (respects silent mode). Push notifications alert you when the rest timer ends while the app is in the background. PR celebrations show a full-screen animation when you achieve a new personal record. When superset is enabled, accessories are shown during rest periods. Choose which accessory goes with each lift on the day screen; choices are remembered for that day.")
                }
                .sbsListRows()

                // HealthKit / Apple Fitness Integration (Premium)
                Section {
                    if StoreManager.shared.canAccess(.appleFitness) {
                        Toggle(isOn: $appState.settings.healthKitEnabled) {
                            Label("Enable HealthKit Sync", systemImage: "heart")
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
                                    SBSBadge(text: "Connected", variant: .status(.success), systemImage: "checkmark")
                                } else if appState.settings.healthKitEnabled {
                                    SBSBadge(text: "Pending", variant: .status(.warning), systemImage: "exclamationmark")
                                } else {
                                    Text("Disabled")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(Color.inkSecondary)
                                }
                            }

                            // Show what data is accessed
                            if appState.settings.healthKitEnabled {
                                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                                    Text("Data Accessed via HealthKit:")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(Color.inkSecondary)

                                    VStack(alignment: .leading, spacing: SBSLayout.space1) {
                                        Label("Workouts (write)", systemImage: "figure.strengthtraining.traditional")
                                        Label("Active Energy (write)", systemImage: "flame")
                                        Label("Body Weight (read)", systemImage: "scalemass")
                                        Label("Heart Rate (read, via Watch)", systemImage: "heart")
                                    }
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.inkSecondary)
                                }
                                .padding(.vertical, SBSLayout.space1)
                            }
                        }
                    } else {
                        // Show premium prompt for free users
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack(spacing: SBSLayout.space3) {
                                Label("Enable HealthKit Sync", systemImage: "heart")
                                    .foregroundStyle(Color.ink)

                                Spacer()

                                SBSBadge(text: "Pro", variant: .pro, systemImage: "lock.fill")
                            }
                        }
                    }
                } header: {
                    HStack(spacing: SBSLayout.space2) {
                        SBSListHeader("HealthKit & Apple Fitness")
                        if !StoreManager.shared.canAccess(.appleFitness) {
                            SBSBadge(text: "Pro", variant: .pro)
                        }
                    }
                } footer: {
                    if StoreManager.shared.canAccess(.appleFitness) {
                        if HealthKitManager.shared.isHealthKitAvailable {
                            SBSListFooter("This app uses Apple HealthKit to log workouts to Apple Fitness. When enabled, starting a workout automatically begins a Strength Training workout. Your workout duration, calories burned, and heart rate (via Apple Watch) are tracked and saved to the Health app when you finish.")
                        } else {
                            SBSListFooter("HealthKit is not available on this device.")
                        }
                    } else {
                        SBSListFooter("Upgrade to Premium to use HealthKit and automatically log your workouts to Apple Fitness with duration, calories, and volume tracking.")
                    }
                }
                .sbsListRows()

                // Training Maxes
                Section {
                    navigationRow("Edit Starting TMs") { showingTMEditor = true }
                } header: {
                    SBSListHeader("Training Maxes")
                } footer: {
                    SBSListFooter("Adjust your Week 1 training maxes. This will recalculate all subsequent weeks.")
                }
                .sbsListRows()

                // Weight Adjustments
                Section {
                    navigationRow("Weight Adjustments") { showingWeightAdjustments = true }
                } header: {
                    SBSListHeader("Progression")
                } footer: {
                    SBSListFooter("Adjust how much your training max changes based on rep-out performance.")
                }
                .sbsListRows()

                // Exercises
                Section {
                    navigationRow("Edit Exercises") { showingExerciseEditor = true }
                } header: {
                    SBSListHeader("Exercises")
                } footer: {
                    SBSListFooter("Customize which lifts and accessories you do each day.")
                }
                .sbsListRows()

                // Custom Templates
                Section {
                    Button {
                        showingTemplateList = true
                    } label: {
                        HStack(spacing: SBSLayout.space3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("My Templates")
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.ink)

                                SBSRowSubtitle(templateCountText)
                            }

                            Spacer()

                            SBSChevron()
                        }
                    }
                } header: {
                    SBSListHeader("Custom Templates")
                } footer: {
                    SBSListFooter("Create your own workout programs with custom exercises, sets, and progression rules.")
                }
                .sbsListRows()

                // Program Cycle
                Section {
                    // Current cycle info
                    HStack {
                        Text("Current Cycle")
                        Spacer()
                        Text("Cycle \(appState.currentCycleNumber)")
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)
                    }

                    HStack {
                        Text("Started")
                        Spacer()
                        Text(appState.userData.currentCycleStartDate, style: .date)
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)
                    }

                    // Past cycles
                    Button {
                        if storeManager.canAccess(.fullHistory) {
                            showingPastCycles = true
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        HStack(spacing: SBSLayout.space2) {
                            Text("Past Cycles")
                                .foregroundStyle(Color.ink)
                            Spacer()
                            if !storeManager.canAccess(.fullHistory) {
                                SBSBadge(text: "Pro", variant: .pro)
                            }
                            if !appState.cycleHistory.isEmpty {
                                Text("\(appState.cycleHistory.count)")
                                    .font(SBSFonts.numberSmall())
                                    .foregroundStyle(Color.inkSecondary)
                            }
                            SBSChevron()
                        }
                    }

                    // Start new cycle
                    Button {
                        showingNewCycleOptions = true
                    } label: {
                        Label("Start New Cycle", systemImage: "arrow.clockwise")
                            .foregroundStyle(Color.orangeText)
                    }
                } header: {
                    SBSListHeader("Program Cycle")
                } footer: {
                    SBSListFooter("Start a new \(appState.weeks.count)-week cycle. Your current progress will be archived and you can choose to carry over your training maxes.")
                }
                .sbsListRows()

                // Data
                Section {
                    Button {
                        do {
                            exportPayload = ExportPayload(data: try appState.exportData())
                        } catch {
                            showDataAlert(title: "Export Failed", message: "Your data couldn't be exported. Please try again.")
                        }
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Color.orangeText)
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Restore from Backup", systemImage: "square.and.arrow.down")
                            .foregroundStyle(Color.orangeText)
                    }
                } header: {
                    SBSListHeader("Data")
                } footer: {
                    SBSListFooter("Backups include your logs, history, PRs, and templates. Settings such as units aren't included.")
                }
                .sbsListRows()

                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset All Logs", systemImage: "trash")
                            .foregroundStyle(Color.danger)
                    }
                } header: {
                    SBSListHeader("Reset")
                } footer: {
                    SBSListFooter("Clears the current cycle's logged sets and your saved accessory weights, and returns to Week 1, Day 1. Past cycles, PRs, lift history, and training maxes are kept.")
                }
                .sbsListRows()

                // About
                Section {

                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString)
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)
                    }

                    // Premium status
                    HStack {
                        Text("Premium")
                        Spacer()
                        if storeManager.isPremium {
                            SBSBadge(text: "Active", variant: .status(.success), systemImage: "checkmark")
                        } else {
                            Text("Free")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }

                    // Subscribers need a way to cancel, e.g. after buying Lifetime
                    if storeManager.isSubscribed {
                        Button {
                            showingManageSubscription = true
                        } label: {
                            Text("Manage Subscription")
                                .foregroundStyle(Color.orangeText)
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
                                .foregroundStyle(Color.orangeText)
                            Spacer()
                            if isRestoringPurchases {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRestoringPurchases)
                } header: {
                    SBSListHeader("About")
                }
                .sbsListRows()

                // Legal
                Section {
                    Link(destination: URL(string: "https://gregorymcinnes.com/apps/top-set-training/")!) {
                        externalLinkRow("Privacy Policy")
                    }
                    Link(destination: URL(string: "https://gregorymcinnes.com/terms")!) {
                        externalLinkRow("Terms of Use")
                    }
                } header: {
                    SBSListHeader("Legal")
                }
                .sbsListRows()

                // More Apps - Cross promotion
                Section {
                    Link(destination: URL(string: "https://apps.apple.com/us/app/top-set-timer/id6756226855")!) {
                        appRow(image: "TopSetTimerIcon", title: "Top Set Timer", subtitle: "Rest timer built for strength training")
                    }

                    Link(destination: URL(string: "https://apps.apple.com/us/app/top-set-calculator/id6757142146")!) {
                        appRow(image: "TopSetCalculatorIcon", title: "Top Set Calculator", subtitle: "Strength calculators & tools")
                    }
                } header: {
                    SBSListHeader("More From Top Set")
                } footer: {
                    SBSListFooter("More strength training tools from Top Set Training.")
                }
                .sbsListRows()
            }
            .sbsGroupedList()
            .scrollDismissesKeyboard(.interactively)
            .sbsTabRoot("Settings")
            .manageSubscriptionsSheet(isPresented: $showingManageSubscription)
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
                        appState.newCycleStarted(afterFinishedCycle: builderOpenedOnFinishedCycle)
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
                Text("This permanently clears the current cycle's logged sets and your saved accessory weights, and returns to Week 1, Day 1. Past cycles, PRs, lift history, and training maxes are kept. This cannot be undone.")
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                handleImportSelection(result)
            }
            .alert("Replace All Data?", isPresented: $showingImportConfirm) {
                Button("Cancel", role: .cancel) {
                    pendingImportData = nil
                }
                Button("Restore", role: .destructive) {
                    restorePendingImport()
                }
            } message: {
                Text("Everything currently in the app, including logs, history, PRs, and templates, will be replaced by this backup. This cannot be undone.")
            }
            .alert(dataAlertTitle, isPresented: $showingDataAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dataAlertMessage)
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
                        let finishedCycle = appState.isCycleComplete
                        appState.startNewCycle(carryOverTMs: true)
                        appState.newCycleStarted(afterFinishedCycle: finishedCycle)
                    }
                }
                
                Button("Customize New Cycle") {
                    builderOpenedOnFinishedCycle = appState.isCycleComplete
                    showingNewCycleBuilder = true
                }
                
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(appState.newCycleDialogMessage)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(item: $programInfoSheet) { programInfo in
                ProgramDetailView(
                    program: programInfo,
                    programData: appState.programData,
                    // Orange as text and icons; no colour per program family
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
        }
    }
    
    // MARK: - Rows

    /// A row that opens a sheet: the title and a chevron
    private func navigationRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(Color.ink)
                Spacer()
                SBSChevron()
            }
        }
    }

    private func externalLinkRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.ink)
            Spacer()
            SBSChevron(systemName: "arrow.up.forward")
        }
    }

    private func appRow(image: String, title: String, subtitle: String) -> some View {
        HStack(spacing: SBSLayout.space3) {
            Image(image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: SBSLayout.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: SBSLayout.radiusMd)
                        .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.ink)

                Text(subtitle)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }

            Spacer()

            SBSChevron(systemName: "arrow.up.forward")
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
        } else {
            showDataAlert(title: "No Bodyweight Found", message: "Apple Health has no bodyweight we can read. Add one in the Health app, or check that Top Set Training has permission to read it.")
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
                .sbsListRows()
            }
            .sbsGroupedList()
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
    @State private var suppressNextCommit = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(liftName)
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.ink)

                Spacer()
                
                if currentValue != defaultValue {
                    Button("Reset") {
                        onReset()
                        let resetText = formatValue(defaultValue)
                        // Don't let this programmatic text change be saved back as a user edit
                        suppressNextCommit = inputText != resetText
                        inputText = resetText
                    }
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.orangeText)
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                TextField("Weight", text: $inputText)
                    .keyboardType(.decimalPad)
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.ink)
                    .focused($isFocused)
                    .onChange(of: inputText) { _, newValue in
                        if suppressNextCommit {
                            suppressNextCommit = false
                            return
                        }
                        // Only the user's own typing saves. Populating the field on
                        // appear must not write a rounded, or zero, value back.
                        guard isFocused, let value = parseInput(newValue), value > 0 else { return }
                        onChange(value)
                    }
                
                Text(useMetric ? "kg" : "lb")
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }
            .sbsFieldCell()
        }
        .padding(.vertical, SBSLayout.space1)
        .onAppear {
            inputText = formatValue(currentValue)
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        let displayValue = useMetric ? value * 0.453592 : value
        if displayValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", displayValue)
        }
        return String(format: "%.1f", displayValue)
    }
    
    private func parseInput(_ text: String) -> Double? {
        guard let value = parseDecimalInput(text) else { return nil }
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
                    SBSListHeader("Below Target")
                } footer: {
                    SBSListFooter("Negative values reduce your training max.")
                }
                .sbsListRows()
                
                Section {
                    AdjustmentRow(
                        label: "Hit rep target",
                        value: $appState.settings.weightAdjustments.hitTarget,
                        defaultValue: WeightAdjustments.default.hitTarget
                    )
                } header: {
                    SBSListHeader("On Target")
                }
                .sbsListRows()
                
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
                    SBSListHeader("Above Target")
                } footer: {
                    SBSListFooter("Positive values increase your training max for the next week.")
                }
                .sbsListRows()
                
                Section {
                    Button(role: .destructive) {
                        appState.settings.weightAdjustments = .default
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(Color.danger)
                    }
                }
                .sbsListRows()
            }
            .sbsGroupedList()
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
                .foregroundStyle(Color.ink)

            Spacer()

            HStack(spacing: SBSLayout.space1) {
                TextField("0", text: $inputText)
                    // Not .decimalPad: it has no minus key, and these values can be negative
                    .keyboardType(.numbersAndPunctuation)
                    .font(SBSFonts.numberUnit())
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused($isFocused)
                    .onChange(of: inputText) { _, newValue in
                        guard isFocused, let parsed = parseInput(newValue) else { return }
                        value = parsed
                    }
                
                Text("%")
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }
            .sbsFieldCell()
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
        guard let percent = parseDecimalInput(cleanText) else { return nil }
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
                SBSSegmentedControl(options: appState.allDays, selection: $selectedDay) { "Day \($0)" }
                    .padding(SBSLayout.space4)
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
                        SBSListHeader("Main Lifts")
                    } footer: {
                        SBSListFooter("Tap to swap for a different lift.")
                    }
                    .sbsListRows()
                    
                    // Accessories section
                    Section {
                        // Real indices: accessories aren't always contiguous, so "first
                        // accessory + offset" could rename or delete a main lift.
                        ForEach(accessoryIndices, id: \.self) { actualIndex in
                            AccessoryRow(
                                name: dayItems[actualIndex].name,
                                onRename: { newName in
                                    appState.updateAccessory(day: selectedDay, at: actualIndex, newName: newName)
                                },
                                onDelete: {
                                    appState.removeItem(from: selectedDay, at: actualIndex)
                                }
                            )
                        }
                        
                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add Accessory", systemImage: "plus")
                                .foregroundStyle(Color.orangeText)
                        }
                    } header: {
                        SBSListHeader("Accessories")
                    }
                    .sbsListRows()
                    
                    // Reset section
                    if appState.hasCustomExercises(for: selectedDay) {
                        Section {
                            Button(role: .destructive) {
                                appState.resetDayItems(for: selectedDay)
                            } label: {
                                Label("Reset Day \(selectedDay) to Default", systemImage: "arrow.counterclockwise")
                                    .foregroundStyle(Color.danger)
                            }
                        }
                        .sbsListRows()
                    }
                }
                .sbsGroupedList()
            }
            .background(Color.bg.ignoresSafeArea())
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
    
    private var accessoryIndices: [Int] {
        dayItems.indices.filter { dayItems[$0].type == .accessory }
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
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)

                    if let subtitle = liftSubtitle {
                        Text(subtitle)
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                }

                Spacer()

                SBSChevron(systemName: "chevron.up.chevron.down")
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
                    .font(SBSFonts.body())
                    .sbsFieldCell()
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
                .font(SBSFonts.caption().weight(.semibold))
                .foregroundStyle(Color.orangeText)
                .buttonStyle(.borderless)
            } else {
                Text(name)
                    .font(SBSFonts.body())
                    .foregroundStyle(Color.ink)
                
                Spacer()
                
                Button {
                    editedName = name
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(Color.orangeText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename accessory")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.danger)
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

#Preview {
    SettingsView(appState: AppState())
}

