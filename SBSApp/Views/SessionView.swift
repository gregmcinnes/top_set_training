import SwiftUI

// Data for rep log sheet
struct RepLogData: Identifiable {
    let id = UUID()
    let lift: String
    let target: Int
    let currentReps: Int?
    let currentNote: String?
}

// Data for nSuns AMRAP log sheet
struct StructuredLogData: Identifiable {
    let id = UUID()
    let lift: String
    let setIndex: Int
    let target: Int
    let currentReps: Int?
}

// Data for accessory log sheet
struct AccessoryLogData: Identifiable {
    let id = UUID()
    let name: String
    let defaultSets: Int
    let defaultReps: Int
    let currentLog: AccessoryLog?
}

// Data for weight override sheet
struct WeightOverrideData: Identifiable {
    let id = UUID()
    let lift: String
    let liftName: String
    let calculatedWeight: Double
    let currentOverride: Double?
}

// Data for linear progression log sheet
struct LinearLogData: Identifiable {
    let id = UUID()
    let lift: String
    let liftName: String
    let weight: Double
    let sets: Int
    let reps: Int
    let increment: Double
    let consecutiveFailures: Int
    let isDeloadPending: Bool
    let logEntry: LinearLogEntry?
}

struct SessionView: View {
    @Bindable var appState: AppState
    let week: Int
    let day: Int
    
    @State private var repLogData: RepLogData?
    @State private var accessoryLogData: AccessoryLogData?
    @State private var weightOverrideData: WeightOverrideData?
    @State private var structuredLogData: StructuredLogData?
    @State private var linearLogData: LinearLogData?
    @State private var showingWorkout = false
    @State private var showingAccessoryWorkout = false
    @State private var showingAccessoryEditor = false
    @State private var prResult: AppState.LogRepsResult?
    @State private var showingPRCelebration = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: SBSLayout.paddingMedium) {
                // Session header with workout button
                SessionHeaderWithWorkout(
                    week: week,
                    day: day,
                    dayTitle: appState.dayTitle(day: day),
                    logStatus: appState.dayLogStatus(week: week, day: day),
                    onStartWorkout: {
                        showingWorkout = true
                    }
                )
                .padding(.horizontal)
                
                // Exercise items
                if let plan = appState.dayPlan(week: week, day: day) {
                    ForEach(Array(plan.enumerated()), id: \.offset) { _, item in
                        planItemView(for: item)
                            .padding(.horizontal)
                    }
                    
                    // Accessory Workout / Timer button - always show
                    AccessoryWorkoutCard(
                        hasAccessories: hasAccessories(in: plan),
                        onStart: {
                            showingAccessoryWorkout = true
                        },
                        onEdit: {
                            showingAccessoryEditor = true
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, SBSLayout.paddingSmall)
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Could not load workout plan for this day.")
                    )
                }
                
                Spacer(minLength: 100)
            }
            .padding(.top)
        }
        .scrollDismissesKeyboard(.interactively)
        .sbsBackground()
        .navigationTitle("Week \(week), Day \(day)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingWorkout) {
            WorkoutView(appState: appState, week: week, day: day)
        }
        .navigationDestination(isPresented: $showingAccessoryWorkout) {
            AccessoryWorkoutView(appState: appState, week: week, day: day)
        }
        .sheet(item: $repLogData) { data in
            RepLogSheet(
                liftName: data.lift,
                target: data.target,
                currentReps: data.currentReps,
                currentNote: data.currentNote,
                onSave: { reps, note in
                    // Log reps and check for PR
                    if let result = appState.logReps(lift: data.lift, week: week, day: day, reps: reps, note: note) {
                        if result.isNewPR {
                            prResult = result
                            repLogData = nil
                            // Show PR celebration if enabled in settings
                            if appState.settings.showPRCelebrations {
                                // Small delay before showing celebration
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    showingPRCelebration = true
                                }
                                return
                            }
                        }
                    }
                    repLogData = nil
                },
                onClear: {
                    appState.clearLog(lift: data.lift, week: week, day: day)
                    repLogData = nil
                },
                onCancel: {
                    repLogData = nil
                }
            )
            .presentationDetents([.height(420), .medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showingPRCelebration) {
            if let result = prResult {
                PRCelebrationView(
                    liftName: result.liftName,
                    newE1RM: result.newE1RM,
                    previousE1RM: result.previousE1RM,
                    weight: result.weight,
                    reps: result.reps,
                    useMetric: appState.settings.useMetric,
                    onDismiss: {
                        showingPRCelebration = false
                        prResult = nil
                    }
                )
            }
        }
        .sheet(item: $accessoryLogData) { data in
            AccessoryLogSheet(
                accessoryName: data.name,
                defaultSets: data.defaultSets,
                defaultReps: data.defaultReps,
                currentLog: data.currentLog,
                useMetric: appState.settings.useMetric,
                roundingIncrement: appState.settings.roundingIncrement,
                onSave: { weight, sets, reps, note in
                    appState.logAccessory(name: data.name, weight: weight, sets: sets, reps: reps, note: note)
                    accessoryLogData = nil
                },
                onClear: {
                    appState.clearAccessoryLog(name: data.name)
                    accessoryLogData = nil
                },
                onCancel: {
                    accessoryLogData = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $weightOverrideData) { data in
            WeightOverrideSheet(
                liftName: data.liftName,
                calculatedWeight: data.calculatedWeight,
                currentOverride: data.currentOverride,
                useMetric: appState.settings.useMetric,
                roundingIncrement: appState.settings.roundingIncrement,
                onSave: { weight in
                    appState.setWeightOverride(lift: data.lift, week: week, day: day, weight: weight)
                    weightOverrideData = nil
                },
                onClear: {
                    appState.clearWeightOverride(lift: data.lift, week: week, day: day)
                    weightOverrideData = nil
                },
                onCancel: {
                    weightOverrideData = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $structuredLogData) { data in
            StructuredRepLogSheet(
                liftName: data.lift,
                setIndex: data.setIndex,
                target: data.target,
                currentReps: data.currentReps,
                structuredContext: StructuredProgressionContext(
                    liftName: data.lift,
                    useMetric: appState.settings.useMetric,
                    manualProgression: appState.programState?.manualProgression ?? false
                ),
                onSave: { reps in
                    appState.logStructuredReps(lift: data.lift, week: week, day: day, setIndex: data.setIndex, reps: reps)
                    structuredLogData = nil
                },
                onClear: {
                    // Clear just this set's reps
                    if var logEntry = appState.getStructuredLog(lift: data.lift, week: week, day: day) {
                        logEntry.amrapReps.removeValue(forKey: data.setIndex)
                        // If empty, clear the whole entry
                        if logEntry.amrapReps.isEmpty {
                            appState.clearStructuredLog(lift: data.lift, week: week, day: day)
                        }
                    }
                    structuredLogData = nil
                },
                onCancel: {
                    structuredLogData = nil
                }
            )
            .presentationDetents([.height(400), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $linearLogData) { data in
            LinearLogSheet(
                liftName: data.liftName,
                weight: data.weight,
                sets: data.sets,
                reps: data.reps,
                increment: data.increment,
                consecutiveFailures: data.consecutiveFailures,
                isDeloadPending: data.isDeloadPending,
                logEntry: data.logEntry,
                useMetric: appState.settings.useMetric,
                onSuccess: {
                    if let result = appState.logLinearSuccess(lift: data.lift, week: week, day: day, weight: data.weight, reps: data.reps, sets: data.sets) {
                        if result.isNewPR {
                            prResult = result
                            linearLogData = nil
                            // Show PR celebration if enabled in settings
                            if appState.settings.showPRCelebrations {
                                // Small delay before showing celebration
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    showingPRCelebration = true
                                }
                                return
                            }
                        }
                    }
                    linearLogData = nil
                },
                onFailure: {
                    appState.logLinearFailure(lift: data.lift, week: week, day: day, weight: data.weight, reps: data.reps, sets: data.sets)
                    linearLogData = nil
                },
                onClear: {
                    appState.clearLinearLog(lift: data.lift, week: week, day: day)
                    linearLogData = nil
                },
                onCancel: {
                    linearLogData = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAccessoryEditor) {
            AccessoryEditorSheet(
                appState: appState,
                day: day,
                onDismiss: { showingAccessoryEditor = false }
            )
        }
    }
    
    @ViewBuilder
    private func planItemView(for item: PlanItem) -> some View {
        switch item {
        case let .tm(name, _, trainingMax, topSingleAt8):
            TMCard(
                name: name,
                trainingMax: trainingMax,
                topSingleAt8: topSingleAt8,
                useMetric: appState.settings.useMetric,
                barWeight: appState.settings.barWeight,
                showPlateCalculator: appState.shouldShowPlateCalculator
            )
            
        case let .volume(name, lift, weight, intensity, sets, repsPerSet, repOutTarget, loggedReps, tmDelta, isOverridden, calculatedWeight):
            VolumeCard(
                name: name,
                weight: weight,
                sets: sets,
                repsPerSet: repsPerSet,
                repOutTarget: repOutTarget,
                loggedReps: loggedReps,
                tmDelta: tmDelta,
                useMetric: appState.settings.useMetric,
                barWeight: appState.settings.barWeight,
                showPlateCalculator: appState.shouldShowPlateCalculator,
                isWeightOverridden: isOverridden,
                calculatedWeight: calculatedWeight,
                loggedNote: appState.getLog(lift: lift, week: week, day: day)?.note,
                intensity: intensity,
                onLogTap: {
                    let currentNote = appState.getLog(lift: lift, week: week, day: day)?.note
                    repLogData = RepLogData(
                        lift: lift,
                        target: repOutTarget,
                        currentReps: loggedReps,
                        currentNote: currentNote
                    )
                },
                onWeightTap: {
                    weightOverrideData = WeightOverrideData(
                        lift: lift,
                        liftName: name,
                        calculatedWeight: calculatedWeight,
                        currentOverride: isOverridden ? weight : nil
                    )
                }
            )
            
        case let .structured(name, lift, trainingMax, sets, logEntry):
            StructuredCard(
                name: name,
                lift: lift,
                trainingMax: trainingMax,
                sets: sets,
                logEntry: logEntry,
                useMetric: appState.settings.useMetric,
                barWeight: appState.settings.barWeight,
                showPlateCalculator: appState.shouldShowPlateCalculator,
                onSetTap: { setIndex in
                    // Find the set info for this index
                    if let setInfo = sets.first(where: { $0.setIndex == setIndex }) {
                        structuredLogData = StructuredLogData(
                            lift: lift,
                            setIndex: setIndex,
                            target: setInfo.targetReps,
                            currentReps: setInfo.loggedReps
                        )
                    }
                }
            )
            
        case let .accessory(name, sets, reps, lastLog):
            AccessoryCard(
                name: name,
                sets: sets,
                reps: reps,
                lastLog: lastLog,
                useMetric: appState.settings.useMetric,
                onLogTap: {
                    accessoryLogData = AccessoryLogData(
                        name: name,
                        defaultSets: sets,
                        defaultReps: reps,
                        currentLog: lastLog
                    )
                }
            )
            
        case let .linear(name, info):
            LinearCard(
                name: name,
                info: info,
                useMetric: appState.settings.useMetric,
                barWeight: appState.settings.barWeight,
                showPlateCalculator: appState.shouldShowPlateCalculator,
                onLogTap: {
                    linearLogData = LinearLogData(
                        lift: info.lift,
                        liftName: name,
                        weight: info.weight,
                        sets: info.sets,
                        reps: info.reps,
                        increment: info.increment,
                        consecutiveFailures: info.consecutiveFailures,
                        isDeloadPending: info.isDeloadPending,
                        logEntry: info.logEntry
                    )
                }
            )
        }
    }
    
    private func hasAccessories(in plan: [PlanItem]) -> Bool {
        plan.contains { item in
            if case .accessory = item { return true }
            return false
        }
    }
}

// MARK: - Accessory Workout Card

struct AccessoryWorkoutCard: View {
    var hasAccessories: Bool = true
    let onStart: () -> Void
    var onEdit: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "timer")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                        
                        Text(hasAccessories ? "Accessory Workout" : "Rest Timer")
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                    }
                    
                    Text(hasAccessories ? "Use the timer to track your accessory sets" : "Track rest between sets")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
                // Edit button
                if let onEdit = onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                    }
                }
            }
            
            Button(action: onStart) {
                HStack(spacing: SBSLayout.paddingSmall) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                    
                    Text("Start Timer")
                        .font(SBSFonts.button())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SBSLayout.paddingMedium)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.accentSecondaryFallback)
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.accentSecondaryFallback.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .strokeBorder(SBSColors.accentSecondaryFallback.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Session Header

struct SessionHeader: View {
    let week: Int
    let day: Int
    let dayTitle: String
    let logStatus: DayLogStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayTitle)
                        .font(SBSFonts.title())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Week \(week) • Day \(day)")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
                LogStatusBadge(status: logStatus)
            }
        }
        .padding()
        .sbsCard()
    }
}

// MARK: - Session Header With Workout Button

struct SessionHeaderWithWorkout: View {
    let week: Int
    let day: Int
    let dayTitle: String
    let logStatus: DayLogStatus
    let onStartWorkout: () -> Void
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayTitle)
                        .font(SBSFonts.title())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Week \(week) • Day \(day)")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
                LogStatusBadge(status: logStatus)
            }
            
            // Start Workout button
            Button(action: onStartWorkout) {
                HStack(spacing: SBSLayout.paddingSmall) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Start Workout")
                        .font(SBSFonts.button())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SBSLayout.paddingMedium)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.accentFallback)
                )
            }
        }
        .padding()
        .sbsCard()
    }
}


// MARK: - Rep Log Sheet

struct RepLogSheet: View {
    let liftName: String
    let target: Int
    let currentReps: Int?
    let currentNote: String?
    let onSave: (Int, String) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    
    @State private var reps: Int?
    @State private var note: String = ""
    @State private var showingNoteField: Bool = false
    @FocusState private var isNoteFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Lift name header
                VStack(spacing: 4) {
                    Text(liftName)
                        .font(SBSFonts.title())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("How many reps on your last set?")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .padding(.top)
                
                // Note field (collapsible)
                VStack(spacing: SBSLayout.paddingSmall) {
                    if showingNoteField || !note.isEmpty {
                        HStack {
                            Image(systemName: "note.text")
                                .font(.system(size: 14))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            
                            TextField("Add a note (optional)", text: $note, axis: .vertical)
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                                .lineLimit(1...3)
                                .focused($isNoteFocused)
                            
                            if !note.isEmpty {
                                Button {
                                    note = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(SBSColors.textTertiaryFallback)
                                }
                            }
                        }
                        .padding(SBSLayout.paddingMedium)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .fill(SBSColors.surfaceFallback)
                        )
                        .padding(.horizontal)
                        .padding(.top, SBSLayout.paddingSmall)
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingNoteField = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isNoteFocused = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 14))
                                Text("Add note")
                                    .font(SBSFonts.caption())
                            }
                            .foregroundStyle(SBSColors.accentFallback)
                        }
                        .padding(.top, SBSLayout.paddingSmall)
                    }
                }
                
                // Number pad (nil = percentage display for volume-based programs)
                NumberPad(
                    value: $reps,
                    target: target,
                    structuredContext: nil,
                    onConfirm: {
                        if let r = reps {
                            onSave(r, note)
                        }
                    },
                    onCancel: onCancel
                )
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentReps != nil {
                        Button("Clear", role: .destructive) {
                            onClear()
                        }
                        .foregroundStyle(SBSColors.error)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            reps = currentReps
            note = currentNote ?? ""
            showingNoteField = !(currentNote ?? "").isEmpty
        }
    }
}

// MARK: - Accessory Log Sheet

struct AccessoryLogSheet: View {
    let accessoryName: String
    let defaultSets: Int
    let defaultReps: Int
    let currentLog: AccessoryLog?
    let useMetric: Bool
    let roundingIncrement: Double
    let onSave: (Double, Int, Int, String) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    
    @State private var weightText: String = ""
    @State private var sets: Int = 4
    @State private var reps: Int = 10
    @State private var note: String = ""
    @State private var showingNoteField: Bool = false
    
    private var weight: Double? {
        Double(weightText)
    }
    
    private var canSave: Bool {
        weight != nil && weight! > 0
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Text(accessoryName)
                        .font(SBSFonts.title())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Log your weight for this accessory")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .padding(.top)
                
                ScrollView {
                    VStack(spacing: SBSLayout.paddingLarge) {
                        // Weight input
                        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                            Text("Weight")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                            
                            HStack {
                                TextField("0", text: $weightText)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                            .fill(SBSColors.surfaceFallback)
                                    )
                                
                                Text(useMetric ? "kg" : "lbs")
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                    .frame(width: 50)
                            }
                            
                            // Quick weight buttons
                            if let lastWeight = currentLog?.weight {
                                HStack(spacing: SBSLayout.paddingSmall) {
                                    QuickWeightButton(
                                        label: "-\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                                        weight: lastWeight - roundingIncrement,
                                        useMetric: useMetric,
                                        onTap: { weightText = String(format: "%.1f", lastWeight - roundingIncrement) }
                                    )
                                    QuickWeightButton(
                                        label: "Same",
                                        weight: lastWeight,
                                        useMetric: useMetric,
                                        onTap: { weightText = String(format: "%.1f", lastWeight) }
                                    )
                                    QuickWeightButton(
                                        label: "+\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                                        weight: lastWeight + roundingIncrement,
                                        useMetric: useMetric,
                                        onTap: { weightText = String(format: "%.1f", lastWeight + roundingIncrement) }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Sets and Reps pickers
                        HStack(spacing: SBSLayout.paddingLarge) {
                            VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                                Text("Sets")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                
                                Picker("Sets", selection: $sets) {
                                    ForEach(1...10, id: \.self) { num in
                                        Text("\(num)").tag(num)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 100)
                                .background(
                                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                        .fill(SBSColors.surfaceFallback)
                                )
                            }
                            
                            VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                                Text("Reps")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                
                                Picker("Reps", selection: $reps) {
                                    ForEach(1...30, id: \.self) { num in
                                        Text("\(num)").tag(num)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 100)
                                .background(
                                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                        .fill(SBSColors.surfaceFallback)
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Note field (collapsible)
                        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                            if showingNoteField || !note.isEmpty {
                                Text("Note")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                
                                HStack {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 14))
                                        .foregroundStyle(SBSColors.textTertiaryFallback)
                                    
                                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                                        .font(SBSFonts.body())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                        .lineLimit(1...4)
                                    
                                    if !note.isEmpty {
                                        Button {
                                            note = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(SBSColors.textTertiaryFallback)
                                        }
                                    }
                                }
                                .padding(SBSLayout.paddingMedium)
                                .background(
                                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                        .fill(SBSColors.surfaceFallback)
                                )
                            } else {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingNoteField = true
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 14))
                                        Text("Add note")
                                            .font(SBSFonts.caption())
                                    }
                                    .foregroundStyle(SBSColors.accentFallback)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                        
                        // Save button
                        Button(action: {
                            if let w = weight {
                                onSave(w, sets, reps, note)
                            }
                        }) {
                            Text("Save")
                                .font(SBSFonts.button())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SBSLayout.paddingMedium + 4)
                                .background(
                                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                        .fill(canSave ? SBSColors.accentFallback : SBSColors.surfaceFallback)
                                )
                        }
                        .disabled(!canSave)
                        .padding(.horizontal)
                    }
                    .padding(.top, SBSLayout.paddingLarge)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentLog != nil {
                        Button("Clear", role: .destructive) {
                            onClear()
                        }
                        .foregroundStyle(SBSColors.error)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            // Pre-fill with current values
            if let log = currentLog {
                weightText = String(format: "%.1f", log.weight)
                sets = log.sets
                reps = log.reps
                note = log.note
                showingNoteField = !log.note.isEmpty
            } else {
                sets = defaultSets
                reps = defaultReps
            }
        }
    }
}

// MARK: - Quick Weight Button

struct QuickWeightButton: View {
    let label: String
    let weight: Double
    let useMetric: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(label)
                    .font(SBSFonts.captionBold())
                Text(weight.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            .foregroundStyle(SBSColors.accentFallback)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SBSLayout.paddingSmall)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(SBSColors.accentFallback.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Day Navigation

struct DayNavigator: View {
    @Binding var currentDay: Int
    let totalDays: Int
    
    var body: some View {
        HStack {
            Button {
                withAnimation {
                    currentDay = max(1, currentDay - 1)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Day \(currentDay - 1)")
                }
                .font(SBSFonts.caption())
            }
            .disabled(currentDay <= 1)
            .opacity(currentDay <= 1 ? 0.3 : 1)
            
            Spacer()
            
            Button {
                withAnimation {
                    currentDay = min(totalDays, currentDay + 1)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Day \(currentDay + 1)")
                    Image(systemName: "chevron.right")
                }
                .font(SBSFonts.caption())
            }
            .disabled(currentDay >= totalDays)
            .opacity(currentDay >= totalDays ? 0.3 : 1)
        }
        .foregroundStyle(SBSColors.accentFallback)
        .padding(.horizontal)
    }
}

// MARK: - Weight Override Sheet

struct WeightOverrideSheet: View {
    let liftName: String
    let calculatedWeight: Double
    let currentOverride: Double?
    let useMetric: Bool
    let roundingIncrement: Double
    let onSave: (Double) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    
    @State private var weightText: String = ""
    
    private var weight: Double? {
        Double(weightText)
    }
    
    private var canSave: Bool {
        guard let w = weight else { return false }
        return w > 0 && w != calculatedWeight
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Text(liftName)
                        .font(SBSFonts.title())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Override the recommended weight")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .padding(.top)
                
                ScrollView {
                    VStack(spacing: SBSLayout.paddingLarge) {
                        // Recommended weight display
                        VStack(spacing: SBSLayout.paddingSmall) {
                            Text("Recommended")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            
                            Text(calculatedWeight.formattedWeight(useMetric: useMetric))
                                .font(SBSFonts.weight())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .fill(SBSColors.surfaceFallback)
                        )
                        .padding(.horizontal)
                        
                        // Weight input
                        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                            Text("Your Weight")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                            
                            HStack {
                                TextField("0", text: $weightText)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                            .fill(SBSColors.surfaceFallback)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                                    .strokeBorder(SBSColors.accentFallback, lineWidth: 2)
                                            )
                                    )
                                
                                Text(useMetric ? "kg" : "lbs")
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                    .frame(width: 50)
                            }
                            
                            // Quick adjust buttons
                            HStack(spacing: SBSLayout.paddingSmall) {
                                QuickAdjustButton(
                                    label: "-\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                                    onTap: {
                                        let current = weight ?? calculatedWeight
                                        weightText = String(format: "%.1f", max(0, current - roundingIncrement))
                                    }
                                )
                                
                                QuickAdjustButton(
                                    label: "Reset",
                                    onTap: {
                                        weightText = String(format: "%.1f", calculatedWeight)
                                    }
                                )
                                
                                QuickAdjustButton(
                                    label: "+\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                                    onTap: {
                                        let current = weight ?? calculatedWeight
                                        weightText = String(format: "%.1f", current + roundingIncrement)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Info text
                        VStack(spacing: SBSLayout.paddingSmall) {
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14))
                                Text("Weight changes will cascade to future weeks")
                                    .font(SBSFonts.caption())
                            }
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                        
                        // Save button
                        Button(action: {
                            if let w = weight {
                                onSave(w)
                            }
                        }) {
                            Text("Save Override")
                                .font(SBSFonts.button())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SBSLayout.paddingMedium + 4)
                                .background(
                                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                        .fill(canSave ? SBSColors.accentFallback : SBSColors.surfaceFallback)
                                )
                        }
                        .disabled(!canSave)
                        .padding(.horizontal)
                    }
                    .padding(.top, SBSLayout.paddingLarge)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentOverride != nil {
                        Button("Clear", role: .destructive) {
                            onClear()
                        }
                        .foregroundStyle(SBSColors.error)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            // Pre-fill with current override or calculated weight
            if let override = currentOverride {
                weightText = String(format: "%.1f", override)
            } else {
                weightText = String(format: "%.1f", calculatedWeight)
            }
        }
    }
}

// MARK: - Quick Adjust Button

struct QuickAdjustButton: View {
    let label: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.accentFallback)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SBSLayout.paddingSmall)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                        .fill(SBSColors.accentFallback.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - nSuns Rep Log Sheet

struct StructuredRepLogSheet: View {
    let liftName: String
    let setIndex: Int
    let target: Int
    let currentReps: Int?
    let structuredContext: StructuredProgressionContext?  // Pass context for weight-based display
    let onSave: (Int) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    
    @State private var reps: Int?
    
    private var setLabel: String {
        if target == 1 {
            return "1+ Set (Heavy Single)"
        } else {
            return "\(target)+ Set"
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Text(liftName)
                        .font(SBSFonts.title())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Text(setLabel)
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.warning)
                    }
                    .padding(.horizontal, SBSLayout.paddingMedium)
                    .padding(.vertical, SBSLayout.paddingSmall)
                    .background(
                        Capsule()
                            .fill(SBSColors.warning.opacity(0.15))
                    )
                    
                    Text("How many reps did you get?")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                        .padding(.top, SBSLayout.paddingSmall)
                }
                .padding(.top)
                
                // Number pad (structured context for weight-based display)
                NumberPad(
                    value: $reps,
                    target: target,
                    structuredContext: structuredContext,
                    onConfirm: {
                        if let r = reps {
                            onSave(r)
                        }
                    },
                    onCancel: onCancel
                )
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentReps != nil {
                        Button("Clear", role: .destructive) {
                            onClear()
                        }
                        .foregroundStyle(SBSColors.error)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            reps = currentReps
        }
    }
}

// MARK: - Linear Log Sheet

struct LinearLogSheet: View {
    let liftName: String
    let weight: Double
    let sets: Int
    let reps: Int
    let increment: Double
    let consecutiveFailures: Int
    let isDeloadPending: Bool
    let logEntry: LinearLogEntry?
    let useMetric: Bool
    let onSuccess: () -> Void
    let onFailure: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: SBSLayout.paddingLarge) {
                // Header
                VStack(spacing: SBSLayout.paddingSmall) {
                    Text(liftName)
                        .font(SBSFonts.largeTitle())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("\(sets)×\(reps) @ \(weight.formattedWeight(useMetric: useMetric))")
                        .font(SBSFonts.title2())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    // Linear progression badge
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text("LINEAR PROGRESSION")
                            .font(SBSFonts.captionBold())
                    }
                    .foregroundStyle(SBSColors.accentFallback)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(SBSColors.accentFallback.opacity(0.15))
                    )
                }
                .padding(.top, SBSLayout.paddingLarge)
                
                // Current status
                if let entry = logEntry {
                    HStack(spacing: SBSLayout.paddingMedium) {
                        Image(systemName: entry.completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(entry.completed ? SBSColors.success : SBSColors.error)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.completed ? "Completed" : "Failed")
                                .font(SBSFonts.bodyBold())
                                .foregroundStyle(entry.completed ? SBSColors.success : SBSColors.error)
                            
                            if entry.deloadApplied {
                                Text("Deload was applied")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.warning)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Clear") {
                            onClear()
                        }
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill((entry.completed ? SBSColors.success : SBSColors.error).opacity(0.1))
                    )
                    .padding(.horizontal)
                } else {
                    // Deload warning
                    if isDeloadPending {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(SBSColors.warning)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Deload Warning")
                                    .font(SBSFonts.bodyBold())
                                    .foregroundStyle(SBSColors.warning)
                                
                                Text("You've failed \(consecutiveFailures) time\(consecutiveFailures == 1 ? "" : "s"). One more failure triggers a 10% deload.")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .fill(SBSColors.warning.opacity(0.1))
                        )
                        .padding(.horizontal)
                    }
                    
                    // Progression info
                    VStack(spacing: SBSLayout.paddingSmall) {
                        Text("Did you complete all \(sets) sets of \(reps) reps?")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .multilineTextAlignment(.center)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Success:")
                                    .font(SBSFonts.captionBold())
                                    .foregroundStyle(SBSColors.success)
                                Text("+\(increment.formattedWeight(useMetric: useMetric)) next time")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("Failure:")
                                    .font(SBSFonts.captionBold())
                                    .foregroundStyle(SBSColors.error)
                                Text("Same weight")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.surfaceFallback)
                    )
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Buttons (only show if not already logged)
                if logEntry == nil {
                    VStack(spacing: SBSLayout.paddingMedium) {
                        Button(action: onSuccess) {
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                
                                Text("Yes - Completed All Reps")
                                    .font(SBSFonts.button())
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.paddingMedium)
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                    .fill(SBSColors.success)
                            )
                        }
                        
                        Button(action: onFailure) {
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                
                                Text("No - Missed Reps")
                                    .font(SBSFonts.button())
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.paddingMedium)
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                    .fill(SBSColors.error)
                            )
                        }
                    }
                    .padding(.horizontal, SBSLayout.paddingLarge)
                    .padding(.bottom, SBSLayout.paddingLarge)
                }
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

// MARK: - Accessory Editor Sheet

struct AccessoryEditorSheet: View {
    @Bindable var appState: AppState
    let day: Int
    let onDismiss: () -> Void
    
    @State private var accessories: [AccessoryEditItem] = []
    @State private var showingAddAccessory = false
    @State private var hasChanges = false
    
    private var currentDayItems: [DayItem] {
        appState.dayItems(for: day)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if accessories.isEmpty {
                    // Empty state
                    VStack(spacing: SBSLayout.paddingLarge) {
                        Spacer()
                        
                        Image(systemName: "dumbbell")
                            .font(.system(size: 56))
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                        
                        Text("No Accessories")
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("Add accessories to customize your workout")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .multilineTextAlignment(.center)
                        
                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        ForEach(accessories) { accessory in
                            AccessoryEditRow(
                                accessory: accessory,
                                useMetric: appState.settings.useMetric,
                                onUpdateSets: { newSets in
                                    if let index = accessories.firstIndex(where: { $0.id == accessory.id }) {
                                        accessories[index].sets = newSets
                                        hasChanges = true
                                    }
                                },
                                onUpdateReps: { newReps in
                                    if let index = accessories.firstIndex(where: { $0.id == accessory.id }) {
                                        accessories[index].reps = newReps
                                        hasChanges = true
                                    }
                                }
                            )
                        }
                        .onDelete(perform: deleteAccessories)
                        .onMove(perform: moveAccessories)
                    }
                    .listStyle(.insetGrouped)
                }
                
                // Add button
                Button {
                    showingAddAccessory = true
                } label: {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                        
                        Text("Add Accessory")
                            .font(SBSFonts.button())
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingMedium)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.accentSecondaryFallback)
                    )
                }
                .padding()
            }
            .sbsBackground()
            .navigationTitle("Edit Accessories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        onDismiss()
                    }
                    .font(.body.bold())
                    .foregroundStyle(hasChanges ? SBSColors.accentFallback : SBSColors.textTertiaryFallback)
                    .disabled(!hasChanges)
                }
                
                if !accessories.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                            .foregroundStyle(SBSColors.accentFallback)
                    }
                }
            }
            .sheet(isPresented: $showingAddAccessory) {
                AccessoryExercisePickerSheet(
                    title: "Add Accessory",
                    onSelect: { name in
                        addAccessory(name: name)
                        showingAddAccessory = false
                    },
                    onCancel: { showingAddAccessory = false }
                )
            }
            .onAppear {
                loadAccessories()
            }
        }
    }
    
    private func loadAccessories() {
        accessories = currentDayItems
            .filter { $0.type == .accessory }
            .map { AccessoryEditItem(
                name: $0.name,
                sets: $0.defaultSets ?? 4,
                reps: $0.defaultReps ?? 10
            )}
    }
    
    private func addAccessory(name: String) {
        // Don't add duplicates
        guard !accessories.contains(where: { $0.name == name }) else { return }
        
        accessories.append(AccessoryEditItem(
            name: name,
            sets: 4,
            reps: 10
        ))
        hasChanges = true
    }
    
    private func deleteAccessories(at offsets: IndexSet) {
        accessories.remove(atOffsets: offsets)
        hasChanges = true
    }
    
    private func moveAccessories(from source: IndexSet, to destination: Int) {
        accessories.move(fromOffsets: source, toOffset: destination)
        hasChanges = true
    }
    
    private func saveChanges() {
        // Get non-accessory items from the current day
        var items = currentDayItems.filter { $0.type != .accessory }
        
        // Add the updated accessories
        for accessory in accessories {
            items.append(DayItem(
                type: .accessory,
                lift: nil,
                name: accessory.name,
                defaultSets: accessory.sets,
                defaultReps: accessory.reps
            ))
        }
        
        // Save to AppState (this will sync across variant days)
        appState.setDayItems(for: day, items: items)
    }
}

// MARK: - Accessory Edit Item

struct AccessoryEditItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var sets: Int
    var reps: Int
}

// MARK: - Accessory Edit Row

struct AccessoryEditRow: View {
    let accessory: AccessoryEditItem
    let useMetric: Bool
    let onUpdateSets: (Int) -> Void
    let onUpdateReps: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text(accessory.name)
                .font(SBSFonts.bodyBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            HStack(spacing: SBSLayout.paddingLarge) {
                // Sets stepper
                HStack(spacing: SBSLayout.paddingSmall) {
                    Text("Sets:")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    Stepper("\(accessory.sets)", value: Binding(
                        get: { accessory.sets },
                        set: { onUpdateSets($0) }
                    ), in: 1...10)
                    .labelsHidden()
                    
                    Text("\(accessory.sets)")
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                        .frame(width: 24)
                }
                
                // Reps stepper
                HStack(spacing: SBSLayout.paddingSmall) {
                    Text("Reps:")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    Stepper("\(accessory.reps)", value: Binding(
                        get: { accessory.reps },
                        set: { onUpdateReps($0) }
                    ), in: 1...30)
                    .labelsHidden()
                    
                    Text("\(accessory.reps)")
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                        .frame(width: 24)
                }
            }
        }
        .padding(.vertical, SBSLayout.paddingSmall)
    }
}

#Preview {
    NavigationStack {
        SessionView(
            appState: AppState(),
            week: 1,
            day: 1
        )
    }
}

