import SwiftUI

// Data for rep log sheet
struct RepLogData: Identifiable {
    let id = UUID()
    let lift: String
    let target: Int
    let currentReps: Int?
    let currentNote: String?
    var prRepsNeeded: Int? = nil
}

// Data for nSuns AMRAP log sheet
struct StructuredLogData: Identifiable {
    let id = UUID()
    let lift: String
    let setIndex: Int
    let target: Int
    let currentReps: Int?
    var prRepsNeeded: Int? = nil
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
    var prescribedReps: String? = nil
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
    /// What's waiting on the answer to "a workout is already in progress"
    private enum PendingStart {
        case workout
        case accessoriesOnly
    }

    @Bindable var appState: AppState
    let week: Int
    let day: Int
    
    @State private var repLogData: RepLogData?
    @State private var accessoryLogData: AccessoryLogData?
    @State private var weightOverrideData: WeightOverrideData?
    @State private var structuredLogData: StructuredLogData?
    @State private var linearLogData: LinearLogData?
    @State private var showingRedoConfirm = false
    @State private var pendingStart: PendingStart?
    @State private var showingAccessoryEditor = false
    @State private var showingAccessoryPicker = false
    @State private var celebratingPR: AppState.LogRepsResult?  // Drives the PR cover; set after a short delay
    
    var body: some View {
        ScrollView {
            VStack(spacing: SBSLayout.space4) {
                // Session header with workout button
                SessionHeaderWithWorkout(
                    week: week,
                    day: day,
                    dayTitle: appState.dayTitle(day: day),
                    logStatus: appState.dayDisplayStatus(week: week, day: day),
                    workoutAction: workoutAction,
                    onStartWorkout: {
                        requestStart(.workout)
                    },
                    onResumeWorkout: {
                        appState.resumeWorkout()
                    },
                    onRedoWorkout: {
                        if appState.activeSession != nil {
                            pendingStart = .workout
                        } else {
                            showingRedoConfirm = true
                        }
                    }
                )
                .padding(.horizontal)
                
                // Exercise items
                if let plan = appState.dayPlan(week: week, day: day) {
                    ForEach(Array(plan.enumerated()), id: \.offset) { _, item in
                        planItemView(for: item)
                            .padding(.horizontal)
                    }
                    
                    SessionAccessoryActions(
                        canStartAccessoriesOnly: canStartAccessoriesOnly(in: plan),
                        hasAccessories: hasAccessories(in: plan),
                        onStartAccessoriesOnly: {
                            requestStart(.accessoriesOnly)
                        },
                        onEdit: {
                            showingAccessoryEditor = true
                        },
                        onAdd: {
                            showingAccessoryPicker = true
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, SBSLayout.space2)
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
        .alert("Redo This Workout?", isPresented: $showingRedoConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Redo Workout") {
                appState.startWorkout(week: week, day: day)
            }
        } message: {
            Text(redoExplanation)
        }
        .alert("Workout in Progress", isPresented: Binding(
            get: { pendingStart != nil },
            set: { if !$0 { pendingStart = nil } }
        )) {
            Button("Resume Current Workout") {
                pendingStart = nil
                appState.resumeWorkout()
            }
            Button("Discard and Start New", role: .destructive) {
                let start = pendingStart
                pendingStart = nil
                appState.activeSession?.exitWorkoutWithoutSaving()
                if let start { beginStart(start) }
            }
            Button("Cancel", role: .cancel) {
                pendingStart = nil
            }
        } message: {
            Text(inProgressExplanation)
        }
        .sheet(item: $repLogData) { data in
            RepLogSheet(
                liftName: data.lift,
                target: data.target,
                currentReps: data.currentReps,
                currentNote: data.currentNote,
                prRepsNeeded: data.prRepsNeeded,
                onSave: { reps, note in
                    // Re-entrancy guard: a second ✓ tap during the sheet's dismiss
                    // animation would re-run logReps (duplicate history record / a
                    // second celebration). Once the first save nils the binding,
                    // drop any further save for this presentation.
                    guard repLogData != nil else { return }
                    // Log reps and check for PR
                    if let result = appState.logReps(lift: data.lift, week: week, day: day, reps: reps, note: note) {
                        if result.isNewPR {
                            let prResult = result
                            repLogData = nil
                            // Count this PR toward review-request eligibility
                            // (queued; presented later, never on the celebration).
                            ReviewRequestManager.shared.recordPRAchieved()
                            // Show PR celebration if enabled in settings
                            if appState.settings.prConfetti {
                                // Small delay before showing celebration
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    celebratingPR = prResult
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
        // item-driven: an isPresented cover reading separate optional state can render
        // empty, and a clear background makes that an invisible, undismissable screen.
        .fullScreenCover(item: $celebratingPR) { result in
            PRCelebrationView(
                liftName: result.liftName,
                newE1RM: result.newE1RM,
                previousE1RM: result.previousE1RM,
                weight: result.weight,
                reps: result.reps,
                useMetric: appState.settings.useMetric,
                week: week,
                day: day,
                programName: appState.programData?.displayName ?? appState.programData?.name,
                onDismiss: {
                    celebratingPR = nil
                }
            )
        }
        .sheet(item: $accessoryLogData) { data in
            AccessoryLogSheet(
                accessoryName: data.name,
                defaultSets: data.defaultSets,
                defaultReps: data.defaultReps,
                currentLog: data.currentLog,
                useMetric: appState.settings.useMetric,
                roundingIncrement: appState.settings.roundingIncrement,
                onSave: { weight, sets, reps, note, wasEasy in
                    appState.logAccessory(name: data.name, weight: weight, sets: sets, reps: reps, note: note, wasEasy: wasEasy)
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $weightOverrideData) { data in
            WeightOverrideSheet(
                liftName: data.liftName,
                calculatedWeight: data.calculatedWeight,
                currentOverride: data.currentOverride,
                prescribedReps: data.prescribedReps,
                useMetric: appState.settings.useMetric,
                roundingIncrement: appState.settings.roundingIncrement,
                onSave: { weight in
                    appState.setWeightOverride(lift: data.lift, week: week, day: day, weight: weight, itemName: data.liftName)
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $structuredLogData) { data in
            RepLogSheet(
                liftName: data.lift,
                target: data.target,
                currentReps: data.currentReps,
                currentNote: appState.getStructuredLog(lift: data.lift, week: week, day: day)?.note,
                setLabel: RepLogSheet.structuredSetLabel(target: data.target),
                structuredContext: StructuredProgressionContext(
                    liftName: data.lift,
                    useMetric: appState.settings.useMetric,
                    manualProgression: appState.programState?.manualProgression ?? false
                ),
                prRepsNeeded: data.prRepsNeeded,
                onSave: { reps, note in
                    // Re-entrancy guard: block a duplicate save landing during
                    // the sheet's dismiss animation.
                    guard structuredLogData != nil else { return }
                    // Log reps and check for PR
                    if let result = appState.logStructuredReps(lift: data.lift, week: week, day: day, setIndex: data.setIndex, reps: reps, note: note) {
                        if result.isNewPR {
                            let prResult = result
                            structuredLogData = nil
                            // Count this PR toward review-request eligibility
                            // (queued; presented later, never on the celebration).
                            ReviewRequestManager.shared.recordPRAchieved()
                            // Show PR celebration if enabled in settings
                            if appState.settings.prConfetti {
                                // Small delay before showing celebration
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    celebratingPR = prResult
                                }
                                return
                            }
                        }
                    }
                    structuredLogData = nil
                },
                onClear: {
                    // Clear just this set's reps
                    appState.clearStructuredSet(lift: data.lift, week: week, day: day, setIndex: data.setIndex)
                    structuredLogData = nil
                },
                onCancel: {
                    structuredLogData = nil
                }
            )
            .presentationDetents([.height(500), .large])
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
                    // Re-entrancy guard: block a duplicate success landing during
                    // the sheet's dismiss animation (duplicate log / celebration).
                    guard linearLogData != nil else { return }
                    if let result = appState.logLinearSuccess(lift: data.lift, week: week, day: day, weight: data.weight, reps: data.reps, sets: data.sets) {
                        if result.isNewPR {
                            let prResult = result
                            linearLogData = nil
                            // Count this PR toward review-request eligibility
                            // (queued; presented later, never on the celebration).
                            ReviewRequestManager.shared.recordPRAchieved()
                            // Show PR celebration if enabled in settings
                            if appState.settings.prConfetti {
                                // Small delay before showing celebration
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    celebratingPR = prResult
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
        .sheet(isPresented: $showingAccessoryPicker) {
            AccessoryExercisePickerSheet(
                title: "Add Accessory",
                onSelect: { name in
                    appState.addAccessory(to: day, name: name)
                    showingAccessoryPicker = false
                },
                onCancel: { showingAccessoryPicker = false }
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
                        currentNote: currentNote,
                        prRepsNeeded: E1RM.newPRRepThreshold(
                            weight: weight,
                            targetReps: repOutTarget,
                            bestE1RM: appState.personalRecord(for: lift)?.estimatedOneRM
                        )
                    )
                },
                onWeightTap: {
                    let normal = max(0, sets - 1)
                    let prescribed = normal > 0
                        ? "\(normal) × \(repsPerSet), then \(repOutTarget)+ AMRAP"
                        : "\(repOutTarget)+ AMRAP"
                    weightOverrideData = WeightOverrideData(
                        lift: lift,
                        liftName: name,
                        calculatedWeight: calculatedWeight,
                        currentOverride: isOverridden ? weight : nil,
                        prescribedReps: prescribed
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
                            currentReps: setInfo.loggedReps,
                            prRepsNeeded: setInfo.isAMRAP ? E1RM.newPRRepThreshold(
                                weight: setInfo.weight,
                                targetReps: setInfo.targetReps,
                                bestE1RM: appState.personalRecord(for: lift)?.estimatedOneRM
                            ) : nil
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
    
    /// The main button: resume this day's session, or start it unless it's already logged
    private var workoutAction: SessionWorkoutAction {
        if let session = appState.activeSession, session.week == week, session.day == day {
            return .resume
        }
        return appState.dayDisplayStatus(week: week, day: day) == .complete ? .done : .start
    }

    private var redoExplanation: String {
        guard appState.dayCanBeLogged(day: day) else {
            return "Finishing it again adds new entries to your accessory history. The earlier ones stay."
        }
        return "Your logged results stay until you log new ones, which replace them lift by lift. Later workouts update to match. Any lift you don't finish keeps its current result."
    }

    private var inProgressExplanation: String {
        var text = "You're partway through a workout"
        if let session = appState.activeSession {
            text += " (Week \(session.week), Day \(session.day))"
        }
        text += ". Discarding it keeps lift results you've already logged, but its accessory sets won't be logged and your place in it will be lost."
        if pendingStart == .workout, appState.dayDisplayStatus(week: week, day: day) == .complete {
            text += " " + redoExplanation
        }
        return text
    }

    /// Start something new, asking first if a workout is already in progress
    private func requestStart(_ start: PendingStart) {
        if appState.activeSession != nil {
            pendingStart = start
        } else {
            beginStart(start)
        }
    }

    private func beginStart(_ start: PendingStart) {
        appState.startWorkout(week: week, day: day, accessoriesOnly: start == .accessoriesOnly)
    }

    /// Worth offering when the day has lifts to leave out. On an accessory-only day Start
    /// Workout is the same thing, and while this day's session runs the button resumes it.
    private func canStartAccessoriesOnly(in plan: [PlanItem]) -> Bool {
        guard hasAccessories(in: plan), appState.dayCanBeLogged(day: day) else { return false }
        return workoutAction != .resume
    }

    private func hasAccessories(in plan: [PlanItem]) -> Bool {
        plan.contains { item in
            if case .accessory = item { return true }
            return false
        }
    }
}

// MARK: - Session Accessory Actions

/// Below the day's exercises: change its accessories, or do only those
struct SessionAccessoryActions: View {
    let canStartAccessoriesOnly: Bool
    let hasAccessories: Bool
    let onStartAccessoriesOnly: () -> Void
    let onEdit: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: SBSLayout.space2) {
            if canStartAccessoriesOnly {
                Button(action: onStartAccessoriesOnly) {
                    label("Start Accessories Only", systemImage: "play.fill")
                }
            }

            HStack(spacing: SBSLayout.space2) {
                Button(action: onAdd) {
                    label("Add Accessory", systemImage: "plus.circle.fill")
                }

                if hasAccessories {
                    Button(action: onEdit) {
                        label("Edit", systemImage: "pencil")
                    }
                    .accessibilityLabel("Edit accessories")
                    .frame(maxWidth: 110)
                }
            }
        }
    }

    private func label(_ title: String, systemImage: String) -> some View {
        HStack(spacing: SBSLayout.space2) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(SBSFonts.bodyStrong())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(SBSColors.accentSecondaryFallback)
        .frame(maxWidth: .infinity)
        .padding(.vertical, SBSLayout.space4)
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                .strokeBorder(SBSColors.accentSecondaryFallback, lineWidth: 1.5)
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
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayTitle)
                        .font(SBSFonts.title())
                        .foregroundStyle(Color.ink)
                    
                    Text("Week \(week) • Day \(day)")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                
                Spacer()
                
                LogStatusBadge(status: logStatus)
            }
        }
        .padding()
        .card()
    }
}

// MARK: - Session Header With Workout Button

/// What the Session screen's main button offers for this day
enum SessionWorkoutAction {
    case start
    case resume
    case done
}

struct SessionHeaderWithWorkout: View {
    let week: Int
    let day: Int
    let dayTitle: String
    let logStatus: DayLogStatus
    let workoutAction: SessionWorkoutAction
    let onStartWorkout: () -> Void
    let onResumeWorkout: () -> Void
    let onRedoWorkout: () -> Void
    
    var body: some View {
        VStack(spacing: SBSLayout.space4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayTitle)
                        .font(SBSFonts.title())
                        .foregroundStyle(Color.ink)
                    
                    Text("Week \(week) • Day \(day)")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                
                Spacer()
                
                LogStatusBadge(status: logStatus)
            }
            
            switch workoutAction {
            case .start:
                primaryButton("Start Workout", action: onStartWorkout)
            case .resume:
                primaryButton("Resume Workout", action: onResumeWorkout)
            case .done:
                doneState
            }
        }
        .padding()
        .card()
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: SBSLayout.space2) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))

                Text(title)
                    .font(SBSFonts.bodyStrong())
            }
            .foregroundStyle(Color.orangeInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SBSLayout.space4)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .fill(SBSColors.accentFallback)
            )
        }
    }

    /// This day is logged, so starting it again is a quiet option rather than the
    /// main action.
    private var doneState: some View {
        VStack(spacing: SBSLayout.space2) {
            HStack(spacing: SBSLayout.space2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))

                Text("Workout Complete")
                    .font(SBSFonts.bodyStrong())
            }
            .foregroundStyle(Color.success)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SBSLayout.space4)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .fill(Color.success.opacity(0.12))
            )
            .accessibilityElement(children: .combine)

            Button("Redo Workout", action: onRedoWorkout)
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
                .frame(minHeight: 44)
        }
    }
}


// MARK: - Rep Log Sheet

struct RepLogSheet: View {
    let liftName: String
    let target: Int
    let currentReps: Int?
    let currentNote: String?
    var setLabel: String? = nil  // A structured program's set, e.g. "3+ Set"
    var structuredContext: StructuredProgressionContext? = nil  // nil = percentage display
    var prRepsNeeded: Int? = nil
    let onSave: (Int, String) -> Void
    var onClear: (() -> Void)? = nil  // Nil where undo does this instead, as in a workout
    let onCancel: () -> Void

    static func structuredSetLabel(target: Int) -> String {
        target == 1 ? "1+ Set (Heavy Single)" : "\(target)+ Set"
    }

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
                        .foregroundStyle(Color.ink)
                    
                    if let setLabel {
                        Text(setLabel)
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.warning)
                            .padding(.horizontal, SBSLayout.space4)
                            .padding(.vertical, SBSLayout.space2)
                            .background(
                                Capsule()
                                    .fill(Color.warning.opacity(0.15))
                            )
                    }

                    Text("How many reps on your AMRAP set?")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top)
                
                // Note field (collapsible)
                VStack(spacing: SBSLayout.space2) {
                    if showingNoteField || !note.isEmpty {
                        HStack {
                            Image(systemName: "note.text")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.inkSecondary)
                            
                            TextField("Add a note (optional)", text: $note, axis: .vertical)
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.ink)
                                .lineLimit(1...3)
                                .focused($isNoteFocused)
                            
                            if !note.isEmpty {
                                Button {
                                    note = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                .accessibilityLabel("Clear note")
                            }
                        }
                        .padding(SBSLayout.space4)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                .fill(Color.surface)
                        )
                        .padding(.horizontal)
                        .padding(.top, SBSLayout.space2)
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
                            .foregroundStyle(Color.orangeText)
                        }
                        .padding(.top, SBSLayout.space2)
                    }
                }
                
                NumberPad(
                    value: $reps,
                    target: target,
                    structuredContext: structuredContext,
                    prRepsNeeded: prRepsNeeded,
                    onConfirm: {
                        if let r = reps {
                            onSave(r, note)
                        }
                    }
                )
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentReps != nil, let onClear {
                        Button("Clear", role: .destructive) {
                            onClear()
                        }
                        .foregroundStyle(Color.danger)
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
    let onSave: (Double, Int, Int, String, Bool?) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    @State private var weightText: String = ""
    @State private var sets: Int = 4
    @State private var reps: Int = 10
    @State private var note: String = ""
    @State private var showingNoteField: Bool = false
    @State private var wasEasy: Bool = false
    
    private var weight: Double? {
        parseDecimalInput(weightText)?.poundsFromInput(useMetric: useMetric)
    }
    
    private var canSave: Bool {
        // 0 is a real weight for an accessory: a bodyweight one has no load to enter
        (weight ?? -1) >= 0
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Text(accessoryName)
                        .font(SBSFonts.title())
                        .foregroundStyle(Color.ink)
                    
                    Text("Log your weight for this accessory")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top)
                
                ScrollView {
                    VStack(spacing: SBSLayout.space6) {
                        // Quick weight buttons
                        if let lastWeight = currentLog?.weight, lastWeight > 0 {
                            HStack(spacing: SBSLayout.space2) {
                                QuickWeightButton(
                                    label: "-\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                                    weight: max(0, lastWeight - roundingIncrement),
                                    useMetric: useMetric,
                                    onTap: { weightText = (max(0, lastWeight - roundingIncrement)).weightInputText(useMetric: useMetric) }
                                )
                                QuickWeightButton(
                                    label: "Same",
                                    weight: lastWeight,
                                    useMetric: useMetric,
                                    onTap: { weightText = (lastWeight).weightInputText(useMetric: useMetric) }
                                )
                                QuickWeightButton(
                                    label: "+\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                                    weight: lastWeight + roundingIncrement,
                                    useMetric: useMetric,
                                    onTap: { weightText = (lastWeight + roundingIncrement).weightInputText(useMetric: useMetric) }
                                )
                            }
                            .padding(.horizontal)
                        }

                        // Sets and reps
                        VStack(spacing: SBSLayout.space2) {
                            Stepper("Sets: \(sets)", value: $sets, in: 1...10)
                            Stepper("Reps: \(reps)", value: $reps, in: 1...30)
                        }
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)
                        .padding(SBSLayout.space4)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                .fill(Color.surface)
                        )
                        .padding(.horizontal)

                        // Easy toggle - hint shown next time
                        Toggle(isOn: $wasEasy) {
                            HStack(spacing: SBSLayout.space2) {
                                Image(systemName: "hand.thumbsup.fill")
                                    .foregroundStyle(Color.success)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("That was easy")
                                        .font(SBSFonts.bodyStrong())
                                        .foregroundStyle(Color.ink)
                                    Text("We'll prompt you to push it next time")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(Color.inkSecondary)
                                }
                            }
                        }
                        .tint(Color.success)
                        .padding(SBSLayout.space4)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                .fill(Color.surface)
                        )
                        .padding(.horizontal)

                        // Note field (collapsible)
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            if showingNoteField || !note.isEmpty {
                                Text("Note")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.inkSecondary)
                                
                                HStack {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.inkSecondary)
                                    
                                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                                        .font(SBSFonts.body())
                                        .foregroundStyle(Color.ink)
                                        .lineLimit(1...4)
                                    
                                    if !note.isEmpty {
                                        Button {
                                            note = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(Color.inkSecondary)
                                        }
                                        .accessibilityLabel("Clear note")
                                    }
                                }
                                .padding(SBSLayout.space4)
                                .background(
                                    RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                        .fill(Color.surface)
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
                                    .foregroundStyle(Color.orangeText)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, SBSLayout.space6)
                }
                .scrollDismissesKeyboard(.interactively)

                WeightPad(
                    text: $weightText,
                    useMetric: useMetric,
                    canConfirm: canSave,
                    onConfirm: {
                        if let w = weight {
                            onSave(w, sets, reps, note, wasEasy ? true : nil)
                        }
                    }
                )
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentLog != nil {
                        Button("Clear", role: .destructive) {
                            onClear()
                        }
                        .foregroundStyle(Color.danger)
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
                weightText = (log.weight).weightInputText(useMetric: useMetric)
                sets = log.sets
                reps = log.reps
                note = log.note
                showingNoteField = !log.note.isEmpty
                // Deliberately don't pre-fill wasEasy from the previous log:
                // the toggle describes the session being logged now, and
                // carrying it forward would re-show the nudge forever.
            } else {
                sets = defaultSets
                reps = defaultReps
            }
        }
    }
}

// MARK: - Accessory Weight Sheet

/// Sets an accessory's weight for the workout in progress
struct AccessoryWeightSheet: View {
    let accessoryName: String
    let currentWeight: Double?
    let useMetric: Bool
    let roundingIncrement: Double
    let onSave: (Double) -> Void
    let onCancel: () -> Void

    @State private var weightText: String = ""

    private var weight: Double? {
        parseDecimalInput(weightText)?.poundsFromInput(useMetric: useMetric)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: SBSLayout.space6) {
                VStack(spacing: 4) {
                    Text(accessoryName)
                        .font(SBSFonts.title())
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)

                    Text("Set your weight for this accessory")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top)

                if let lastWeight = currentWeight, lastWeight > 0 {
                    HStack(spacing: SBSLayout.space2) {
                        QuickWeightButton(
                            label: "-\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                            weight: max(0, lastWeight - roundingIncrement),
                            useMetric: useMetric,
                            onTap: { weightText = (max(0, lastWeight - roundingIncrement)).weightInputText(useMetric: useMetric) }
                        )
                        QuickWeightButton(
                            label: "Same",
                            weight: lastWeight,
                            useMetric: useMetric,
                            onTap: { weightText = (lastWeight).weightInputText(useMetric: useMetric) }
                        )
                        QuickWeightButton(
                            label: "+\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                            weight: lastWeight + roundingIncrement,
                            useMetric: useMetric,
                            onTap: { weightText = (lastWeight + roundingIncrement).weightInputText(useMetric: useMetric) }
                        )
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 0)

                WeightPad(
                    text: $weightText,
                    useMetric: useMetric,
                    // 0 is a real weight for an accessory: a bodyweight one has no load to enter
                    canConfirm: (weight ?? -1) >= 0,
                    onConfirm: {
                        if let weight { onSave(weight) }
                    }
                )
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
        .onAppear {
            if let currentWeight, currentWeight > 0 {
                weightText = currentWeight.weightInputText(useMetric: useMetric)
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
                    .font(SBSFonts.caption().weight(.semibold))
                Text(weight.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
            .foregroundStyle(Color.orangeText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SBSLayout.space2)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .fill(Color.orangeSoft)
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
        .foregroundStyle(Color.orangeText)
        .padding(.horizontal)
    }
}

// MARK: - Weight Override Sheet

struct WeightOverrideSheet: View {
    let liftName: String
    let calculatedWeight: Double
    let currentOverride: Double?
    var prescribedReps: String? = nil  // e.g. "5 × 5+" or "AMRAP at 1+"
    let useMetric: Bool
    let roundingIncrement: Double
    let onSave: (Double) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    @State private var weightText: String = ""
    
    private var weight: Double? {
        parseDecimalInput(weightText)?.poundsFromInput(useMetric: useMetric)
    }
    
    private var canSave: Bool {
        guard let w = weight else { return false }
        // Compared loosely: a re-entered kg value converts to a slightly different lb one
        return w > 0 && abs(w - calculatedWeight) > 0.05
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 4) {
                    Text(liftName)
                        .font(SBSFonts.title())
                        .foregroundStyle(Color.ink)

                    if let prescribedReps {
                        Text(prescribedReps)
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.inkSecondary)
                    }

                    Text("Override the recommended weight")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top)

                // Recommended weight display
                VStack(spacing: SBSLayout.space2) {
                    Text("Recommended")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)

                    Text(calculatedWeight.formattedWeight(useMetric: useMetric))
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                        .fill(Color.surface)
                )
                .padding(.horizontal)
                .padding(.top, SBSLayout.space6)

                // Weight input
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    // Quick adjust buttons
                    HStack(spacing: SBSLayout.space2) {
                        QuickAdjustButton(
                            label: "-\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                            onTap: {
                                let current = weight ?? calculatedWeight
                                weightText = (max(0, current - roundingIncrement)).weightInputText(useMetric: useMetric)
                            }
                        )

                        QuickAdjustButton(
                            label: "Reset",
                            onTap: {
                                weightText = (calculatedWeight).weightInputText(useMetric: useMetric)
                            }
                        )

                        QuickAdjustButton(
                            label: "+\(roundingIncrement.formattedWeightShort(useMetric: useMetric))",
                            onTap: {
                                let current = weight ?? calculatedWeight
                                weightText = (current + roundingIncrement).weightInputText(useMetric: useMetric)
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, SBSLayout.space6)

                // Info text
                HStack(spacing: SBSLayout.space2) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                    Text("Weight changes will cascade to future weeks")
                        .font(SBSFonts.caption())
                }
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, SBSLayout.space4)

                Spacer(minLength: 0)

                WeightPad(
                    text: $weightText,
                    useMetric: useMetric,
                    canConfirm: canSave,
                    onConfirm: {
                        if let w = weight {
                            onSave(w)
                        }
                    }
                )
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentOverride != nil {
                        Button("Clear", role: .destructive) {
                            onClear()
                        }
                        .foregroundStyle(Color.danger)
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
                weightText = (override).weightInputText(useMetric: useMetric)
            } else {
                weightText = (calculatedWeight).weightInputText(useMetric: useMetric)
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
                .font(SBSFonts.caption().weight(.semibold))
                .foregroundStyle(Color.orangeText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SBSLayout.space2)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                        .fill(Color.orangeSoft)
                )
        }
        .buttonStyle(.plain)
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
            VStack(spacing: SBSLayout.space6) {
                // Header
                VStack(spacing: SBSLayout.space2) {
                    Text(liftName)
                        .font(SBSFonts.largeTitle())
                        .foregroundStyle(Color.ink)
                    
                    Text("\(sets)×\(reps) @ \(weight.formattedWeight(useMetric: useMetric))")
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.inkSecondary)
                    
                    // Linear progression badge
                    HStack(spacing: SBSLayout.space2) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text("LINEAR PROGRESSION")
                            .font(SBSFonts.caption().weight(.semibold))
                    }
                    .foregroundStyle(Color.orangeText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.orangeSoft)
                    )
                }
                .padding(.top, SBSLayout.space6)
                
                // Current status
                if let entry = logEntry {
                    HStack(spacing: SBSLayout.space4) {
                        Image(systemName: entry.completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(entry.completed ? Color.success : Color.danger)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.completed ? "Completed" : "Failed")
                                .font(SBSFonts.bodyStrong())
                                .foregroundStyle(entry.completed ? Color.success : Color.danger)
                            
                            if entry.deloadApplied {
                                Text("Deload was applied")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.warning)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Clear") {
                            onClear()
                        }
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                            .fill((entry.completed ? Color.success : Color.danger).opacity(0.1))
                    )
                    .padding(.horizontal)
                } else {
                    // Deload warning
                    if isDeloadPending {
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.warning)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Deload Warning")
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.warning)
                                
                                Text("You've failed \(consecutiveFailures) time\(consecutiveFailures == 1 ? "" : "s"). One more failure triggers a 10% deload.")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                .fill(Color.warning.opacity(0.1))
                        )
                        .padding(.horizontal)
                    }
                    
                    // Progression info
                    VStack(spacing: SBSLayout.space2) {
                        Text("Did you complete all \(sets) sets of \(reps) reps?")
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.center)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Success:")
                                    .font(SBSFonts.caption().weight(.semibold))
                                    .foregroundStyle(Color.success)
                                Text("+\(increment.formattedWeight(useMetric: useMetric)) next time")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.inkSecondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing) {
                                Text("Failure:")
                                    .font(SBSFonts.caption().weight(.semibold))
                                    .foregroundStyle(Color.danger)
                                Text("Same weight")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                            .fill(Color.surface)
                    )
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Buttons (only show if not already logged)
                if logEntry == nil {
                    VStack(spacing: SBSLayout.space4) {
                        Button(action: onSuccess) {
                            HStack(spacing: SBSLayout.space2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                
                                Text("Yes - Completed All Reps")
                                    .font(SBSFonts.bodyStrong())
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.space4)
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                    .fill(Color.success)
                            )
                        }
                        
                        Button(action: onFailure) {
                            HStack(spacing: SBSLayout.space2) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                
                                Text("No - Missed Reps")
                                    .font(SBSFonts.bodyStrong())
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.space4)
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                    .fill(Color.danger)
                            )
                        }
                    }
                    .padding(.horizontal, SBSLayout.space6)
                    .padding(.bottom, SBSLayout.space6)
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
                    VStack(spacing: SBSLayout.space6) {
                        Spacer()
                        
                        Image(systemName: "dumbbell")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.inkSecondary)
                        
                        Text("No Accessories")
                            .font(SBSFonts.title())
                            .foregroundStyle(Color.ink)
                        
                        Text("Add accessories to customize your workout")
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
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
                
                VStack(spacing: SBSLayout.space2) {
                    Button {
                        showingAddAccessory = true
                    } label: {
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))

                            Text("Add Accessory")
                                .font(SBSFonts.bodyStrong())
                        }
                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.space4)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                .strokeBorder(SBSColors.accentSecondaryFallback, lineWidth: 1.5)
                        )
                    }

                    Button {
                        saveChanges()
                        onDismiss()
                    } label: {
                        Text("Save")
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(hasChanges ? Color.orangeInk : Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.space4)
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                    .fill(hasChanges ? SBSColors.accentFallback : Color.surface)
                            )
                    }
                    .disabled(!hasChanges)
                }
                .padding()
            }
            .sbsBackground()
            .navigationTitle("Edit Accessories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !accessories.isEmpty {
                        EditButton()
                            .foregroundStyle(Color.orangeText)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onDismiss()
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
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            Text(accessory.name)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.ink)
            
            // Stacked: side by side the two steppers squeeze their labels to one letter a line
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                // Sets stepper
                HStack(spacing: SBSLayout.space2) {
                    Text("Sets:")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 40, alignment: .leading)
                    
                    Stepper("\(accessory.sets)", value: Binding(
                        get: { accessory.sets },
                        set: { onUpdateSets($0) }
                    ), in: 1...10)
                    .labelsHidden()
                    
                    Text("\(accessory.sets)")
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                        .frame(width: 24)
                }
                
                // Reps stepper
                HStack(spacing: SBSLayout.space2) {
                    Text("Reps:")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 40, alignment: .leading)
                    
                    Stepper("\(accessory.reps)", value: Binding(
                        get: { accessory.reps },
                        set: { onUpdateReps($0) }
                    ), in: 1...30)
                    .labelsHidden()
                    
                    Text("\(accessory.reps)")
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                        .frame(width: 24)
                }
            }
        }
        .padding(.vertical, SBSLayout.space2)
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

