import SwiftUI

// MARK: - Cycle Builder View

struct CycleBuilderView: View {
    @Bindable var appState: AppState
    let isOnboarding: Bool
    let initialProgram: String?
    let onComplete: () -> Void
    let onCancel: (() -> Void)?
    
    init(
        appState: AppState,
        isOnboarding: Bool,
        initialProgram: String? = nil,
        onComplete: @escaping () -> Void,
        onCancel: (() -> Void)?
    ) {
        self.appState = appState
        self.isOnboarding = isOnboarding
        self.initialProgram = initialProgram
        self.onComplete = onComplete
        self.onCancel = onCancel
        
        // If initialProgram is provided and not onboarding, start at exercises step
        // We'll load the program in onAppear/task
        if let program = initialProgram, !isOnboarding {
            _currentStep = State(initialValue: .exercises)
            _selectedProgram = State(initialValue: program)
            _isLoadingProgram = State(initialValue: true)
        } else if let program = initialProgram {
            _selectedProgram = State(initialValue: program)
        } else if !isOnboarding {
            // Someone starting another cycle knows the app, so Welcome has nothing for them
            _currentStep = State(initialValue: .program)
        }
    }

    @State private var currentStep: BuilderStep = .welcome
    @State private var selectedProgram: String = "stronglifts_5x5_12week"
    @State private var trainingMaxes: [String: Double] = [:]
    @State private var exerciseCustomizations: [Int: [DayItem]] = [:]
    @State private var carryOverTMs: Bool = true
    @State private var animateIn: Bool = false
    @State private var isLoadingProgram: Bool = false
    @State private var showingLockedProgramPaywall: Bool = false
    @State private var lastLoadedProgram: String? = nil
    @State private var showingProgramQuiz: Bool = false
    @State private var showingTemplateBuilder: Bool = false
    @State private var showingTemplatePaywall: Bool = false
    @State private var didSetUp: Bool = false
    @State private var programLoadFailure: ProgramLoadFailure? = nil
    /// The cycle being replaced, captured before any preview load can archive it. Comparing
    /// against this tells a repeat of the same program from a switch, even after the user
    /// has previewed another program and come back.
    @State private var originalProgram: String? = nil
    @State private var originalNextCycleMaxes: [String: Double] = [:]

    private struct ProgramLoadFailure {
        let message: String
        let retry: () -> Void
    }

    /// Each day's items in day order, using customizations where the user has made them.
    /// Use this instead of appState's lifts during cycle setup, so swapped lifts count.
    private var configuredDays: [[DayItem]] {
        appState.allDays.map { exerciseCustomizations[$0] ?? appState.dayItems(for: $0) }
    }

    /// The main lifts being set up, in program order
    private var configuredLifts: [String] {
        ProgramLifts.ordered(days: configuredDays)
    }

    private var startingWeightKind: StartingWeightKind {
        StartingWeightKind.classify(items: configuredDays.flatMap { $0 })
    }

    typealias BuilderStep = SetupStep
    
    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator
                if currentStep != .welcome {
                    StepProgressView(currentStep: currentStep)
                        .padding(.horizontal)
                        // Clear the close button in the top corner
                        .padding(.trailing, isOnboarding ? 0 : 28)
                        .padding(.top, 8)
}
                
                // Content
                TabView(selection: $currentStep) {
                    if isOnboarding {
                        WelcomeStepView(
                            isOnboarding: isOnboarding,
                            onContinue: { goToStep(.program) },
                            onTakeQuiz: { showingProgramQuiz = true },
                            onSkip: { skipOnboarding() }
                        )
                        .tag(BuilderStep.welcome)
                    }

                    ProgramSelectionStepView(
                        appState: appState,
                        selectedProgram: $selectedProgram,
                        // The first step outside onboarding, so going back means leaving
                        backTitle: isOnboarding ? "Back" : "Cancel",
                        onBack: {
                            if isOnboarding {
                                goToStep(.welcome)
                            } else {
                                cancelAndRestore()
                            }
                        },
onContinue: { loadSelectedProgramAndContinue() },
                        onTakeQuiz: { showingProgramQuiz = true },
                        onBuildTemplate: {
                            // Same limit as the other template entry points
                            if StoreManager.shared.canCreateTemplate(currentTemplateCount: appState.userData.customTemplates.count) {
                                showingTemplateBuilder = true
                            } else {
                                showingTemplatePaywall = true
                            }
                        }
                    )
                    .tag(BuilderStep.program)
                    
                    ExerciseReviewStepView(
                        appState: appState,
                        exerciseCustomizations: $exerciseCustomizations,
                        onBack: { goToStep(.program) },
                        onContinue: { 
                            initializeTrainingMaxes()
                            goToStep(.trainingMaxes) 
                        }
                    )
                    .tag(BuilderStep.exercises)
                    
                    TrainingMaxesStepView(
                        appState: appState,
                        trainingMaxes: $trainingMaxes,
                        carryOverTMs: $carryOverTMs,
                        isOnboarding: isOnboarding,
                        configuredLifts: configuredLifts,
                        kind: startingWeightKind,
                        targetReps: { ProgramLifts.targetReps(for: $0, days: configuredDays) },
                        carriedMax: { carriedMax(for: $0, from: carriedMaxes()) },
                        defaultMax: { defaultMax(for: $0) },
                        onChangeUnits: { changeUnits(toMetric: $0) },
                        onBack: { goToStep(.exercises) },
                        onContinue: { goToStep(.summary) }
                    )
                    .tag(BuilderStep.trainingMaxes)

SummaryStepView(
                        appState: appState,
                        selectedProgram: selectedProgram,
                        trainingMaxes: trainingMaxes,
                        orderedLifts: configuredLifts,
                        kind: startingWeightKind,
                        exerciseCustomizations: exerciseCustomizations,
                        isOnboarding: isOnboarding,
                        onBack: { goToStep(.trainingMaxes) },
onComplete: completeCycleSetup
                    )
                    .tag(BuilderStep.summary)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
                .gesture(DragGesture())
            }

            // Close button (for non-onboarding)
            if !isOnboarding, onCancel != nil {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            cancelAndRestore()
                        } label: {
                            Image(systemName: "xmark")
                                .font(SBSFonts.heading())
                                .foregroundStyle(Color.ink)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Cancel new cycle")
                        .padding()
                    }
                    Spacer()
                }
            }
            
            // Loading overlay when switching programs
            if isLoadingProgram {
                Color.bg.opacity(0.7)
                    .ignoresSafeArea()
                
                VStack(spacing: SBSLayout.space4) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.ink)
                    
                    Text("Loading program...")
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.ink)
                }
                .padding(SBSLayout.space6)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: SBSLayout.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: SBSLayout.radiusMd)
                        .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
                )
            }
        }
        .opacity(animateIn ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                animateIn = true
            }
            // Once only: covers presented from here can make this fire again
            guard !didSetUp else { return }
            didSetUp = true

            if !isOnboarding {
                // Both before any load below can switch programs and archive the logs
                originalProgram = appState.userData.selectedProgram
                originalNextCycleMaxes = appState.nextCycleStartingMaxes()
                // Snapshot user data before any program preview so cancelling the
                // builder can restore the cycle exactly as it was.
                appState.beginProgramPreview()
            }
            // If an initial program was provided (e.g., from ProgramsView), load it
            // The step was already set to .exercises in init
            if let initial = initialProgram, !isOnboarding {
                loadProgram(initial) {}
            } else if isOnboarding {
                applyLocaleUnitsIfNewUser()
                restoreOnboardingDraftIfNeeded()
            } else if let currentProgram = appState.userData.selectedProgram {
                // Initialize with currently loaded program so we don't reload unnecessarily
                selectedProgram = currentProgram
                lastLoadedProgram = currentProgram
            }
        }
        // Persist onboarding progress as the user advances so an app kill mid-flow
        // doesn't restart from zero. Guarded to onboarding inside the helper.
        .onChange(of: currentStep) { _, _ in persistOnboardingDraftIfNeeded() }
        .onChange(of: selectedProgram) { _, _ in persistOnboardingDraftIfNeeded() }
        .onChange(of: trainingMaxes) { _, _ in persistOnboardingDraftIfNeeded() }
        .fullScreenCover(isPresented: $showingProgramQuiz) {
            ProgramRecommendationQuiz(
                appState: appState,
                selectedProgram: $selectedProgram,
                onDismiss: {
                    showingProgramQuiz = false
                },
                onBrowseAll: {
                    showingProgramQuiz = false
                    goToStep(.program)
                },
                onProgramSelected: { programId in
selectedProgram = programId
                    showingProgramQuiz = false
                    // Go to program step if not already there
                    if currentStep == .welcome {
                        goToStep(.program)
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showingTemplateBuilder) {
            TemplateBuilderView(
                appState: appState,
                existingTemplate: nil,
                onSave: { template in
                    appState.userData.addTemplate(template)
                    showingTemplateBuilder = false
                    // Select the newly created template
                    selectedProgram = UserData.programId(for: template.id)
                },
                onCancel: {
                    showingTemplateBuilder = false
                }
            )
        }
        .sheet(isPresented: $showingLockedProgramPaywall) {
            PaywallView(triggeredByFeature: .allPrograms)
        }
        .sheet(isPresented: $showingTemplatePaywall) {
            PaywallView(triggeredByFeature: .unlimitedTemplates)
        }
        .alert(
            "Couldn't Load Program",
            isPresented: Binding(
                get: { programLoadFailure != nil },
                set: { if !$0 { programLoadFailure = nil } }
            ),
            presenting: programLoadFailure
        ) { failure in
            Button("Try Again") { failure.retry() }
            Button("Choose Another", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    private func goToStep(_ step: BuilderStep) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = step
        }
    }
    
    /// Every builder load goes through here. `AppState.loadProgram` decodes before it changes
    /// anything, so a failure leaves the current program in place: the user lands on the
    /// program list, with an alert offering a retry, and can pick something else from there.
    private func loadProgram(_ programId: String, onSuccess: @escaping () -> Void) {
        isLoadingProgram = true
        Task { @MainActor in
            do {
                try await appState.loadProgram(programId)
                lastLoadedProgram = programId
                isLoadingProgram = false
                onSuccess()
            } catch {
                Logger.error("Failed to load program \(programId): \(error)", category: .program)
                isLoadingProgram = false
                goToStep(.program)
                programLoadFailure = ProgramLoadFailure(
                    message: "\(appState.displayName(forProgramId: programId)) couldn't be opened. Try again, or choose a different program.",
                    retry: { loadProgram(programId, onSuccess: onSuccess) }
                )
            }
        }
    }

    /// Load the selected program into appState before going to exercises step
    private func loadSelectedProgramAndContinue() {
        let isNewSelection = lastLoadedProgram != selectedProgram
        loadProgram(selectedProgram) {
            // Customizations and entered maxes belong to the program they were made for.
            // Cleared only now, so a failed load doesn't cost the user their edits.
            if isNewSelection {
                exerciseCustomizations = [:]
                trainingMaxes = [:]
            }
            goToStep(.exercises)
        }
    }

    private func initializeTrainingMaxes() {
        // Use configuredLifts to get lifts from exerciseCustomizations (not appState)
        // This ensures we show the swapped-in lifts, not the original program lifts
        let lifts = configuredLifts
        // Drop stale entries for lifts no longer configured (e.g., after a swap)
        trainingMaxes = trainingMaxes.filter { lifts.contains($0.key) }
        let carried = (!isOnboarding && carryOverTMs) ? carriedMaxes() : nil
        // Keep values already here: coming back through this step must not discard what
        // the user entered, so only lifts without a value get a default.
        for lift in lifts where trainingMaxes[lift] == nil {
            if let carried {
                trainingMaxes[lift] = carriedMax(for: lift, from: carried)
            } else {
                trainingMaxes[lift] = defaultMax(for: lift)
            }
        }
    }

    /// The maxes a new cycle carries over. Repeating the program uses the value captured
    /// when the builder opened, which already includes any end-of-cycle increase. That
    /// makes it an absolute number, so reapplying it can't add the increase twice. A
    /// different program gets no increase.
    private func carriedMaxes() -> [String: Double] {
        if originalProgram != nil, selectedProgram == originalProgram {
            return originalNextCycleMaxes
        }
        return appState.finalTrainingMaxes(atWeek: appState.highestLoggedWeek())
    }

    /// Priority: carried TMs > custom initial maxes > universal TMs > program defaults > starter
    private func carriedMax(for lift: String, from carried: [String: Double]) -> Double {
        let candidates = [
            carried[lift],
            appState.userData.customInitialMaxes[lift],
            appState.userData.trainingMaxes.canonicalLiftValue(for: lift),
            appState.initialMax(for: lift)
        ]
        return candidates.compactMap { $0 }.first { $0 > 0 } ?? starterMax(for: lift)
    }

    /// What a lift starts at when nothing is carried over. Programs ship no starting
    /// weights, so this is normally the starter.
    private func defaultMax(for lift: String) -> Double {
        if let programDefault = appState.programData?.initialMaxes[lift], programDefault > 0 {
            return programDefault
        }
        return starterMax(for: lift)
    }

    private func starterMax(for lift: String) -> Double {
        StarterWeights.starter(
            for: lift,
            useMetric: appState.settings.useMetric,
            barWeight: appState.settings.barWeight,
            kind: startingWeightKind
        )
    }

    /// Onboarding only: set which unit the user's numbers are in, moving rounding and the
    /// bar onto that unit's grid as Settings does.
    private func changeUnits(toMetric: Bool) {
        let old = appState.settings
        guard old.useMetric != toMetric else { return }
        var updated = old
        updated.useMetric = toMetric
        BarWeightOptions.applyUnitDefaults(to: &updated, useMetric: toMetric)
        appState.settings = updated

        let kind = startingWeightKind
        for (lift, value) in trainingMaxes {
            trainingMaxes[lift] = StarterWeights.valueAfterUnitChange(
                value,
                lift: lift,
                kind: kind,
                fromMetric: old.useMetric,
                fromBarWeight: old.barWeight,
                toMetric: toMetric,
                toBarWeight: updated.barWeight
            )
        }
    }

    /// A true first run starts in the unit the user's locale uses. Runs before draft restore
    /// reads anything; a draft means this already had its chance.
    private func applyLocaleUnitsIfNewUser() {
        guard UnitDefaults.shouldApplyLocale(
            settings: appState.settings,
            userData: appState.userData,
            hasOnboardingDraft: OnboardingDraft.load() != nil
        ), UnitDefaults.prefersMetric(locale: .current) else { return }

        var updated = appState.settings
        updated.useMetric = true
        BarWeightOptions.applyUnitDefaults(to: &updated, useMetric: true)
        appState.settings = updated
    }

    /// Persist onboarding progress (program pick, step, entered maxes). No-op
    /// outside onboarding.
    private func persistOnboardingDraftIfNeeded() {
        guard isOnboarding else { return }
        OnboardingDraft(
            step: currentStep.rawValue,
            selectedProgram: selectedProgram,
            trainingMaxes: trainingMaxes
        ).save()
    }

    /// Restore a saved onboarding draft, if any. Steps past program selection need
    /// the chosen program loaded into appState, so those load asynchronously before
    /// jumping to the restored step; a load failure lands on program selection with an error.
    private func restoreOnboardingDraftIfNeeded() {
        guard let draft = OnboardingDraft.load() else { return }
        let restoredStep = draft.restoredStep

        selectedProgram = draft.selectedProgram
        trainingMaxes = draft.trainingMaxes

        guard restoredStep.rawValue > BuilderStep.program.rawValue else {
            currentStep = restoredStep
            return
        }

        loadProgram(draft.selectedProgram) {
            // The draft may have reached weights without a value for every lift
            if restoredStep.rawValue >= BuilderStep.trainingMaxes.rawValue {
                initializeTrainingMaxes()
            }
            goToStep(restoredStep)
        }
    }

    /// "Skip for now": finish onboarding with a sensible default free program so
    /// the user lands on a usable app rather than an empty state.
    private func skipOnboarding() {
        Haptics.light()
        isLoadingProgram = true
        Task {
            await appState.skipOnboardingWithDefault()
            await MainActor.run {
                OnboardingDraft.clear()
                appState.commitProgramPreview()
                isLoadingProgram = false
                onComplete()
            }
        }
    }

    private func completeCycleSetup() {
        // Backstop: every path into the builder gates locked programs (selector
        // taps, program-step Continue, ProgramsView rows), but never commit a
        // cycle on a program the user can't access.
        guard StoreManager.shared.canAccessProgram(selectedProgram) else {
            showingLockedProgramPaywall = true
            return
        }
        if isOnboarding {
            // Apply all customizations
            appState.setInitialMaxes(trainingMaxes)
            if !exerciseCustomizations.isEmpty {
                appState.applyExerciseCustomizations(exerciseCustomizations)
            }
            appState.completeOnboarding()
            // Onboarding finished successfully — discard the resume draft.
            OnboardingDraft.clear()
        } else {
            // Start new cycle with builder settings
            appState.startNewCycleWithBuilder(
                carryOverTMs: false, // We're setting explicit maxes
                newMaxes: trainingMaxes,
                exerciseCustomizations: exerciseCustomizations.isEmpty ? nil : exerciseCustomizations
            )
        }
        appState.commitProgramPreview()
        onComplete()
    }

    /// Cancel the builder: roll back any previewed program switch (archived
    /// cycle, cleared logs, changed selection) before dismissing.
    private func cancelAndRestore() {
        guard let onCancel else { return }
        isLoadingProgram = true
        Task {
            await appState.cancelProgramPreview()
            await MainActor.run {
                isLoadingProgram = false
                onCancel()
            }
        }
    }
}

// MARK: - Step Progress View

struct StepProgressView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let currentStep: CycleBuilderView.BuilderStep

    private let steps = CycleBuilderView.BuilderStep.indicatorSteps

    private func isReached(_ step: CycleBuilderView.BuilderStep) -> Bool {
        step.rawValue <= currentStep.rawValue
    }

    // Done steps are ink, the current step is the orange block, upcoming ones hairline
    private func connector(isReached: Bool, isHidden: Bool) -> some View {
        Rectangle()
            .fill(isReached ? Color.ink : Color.hairline)
            .frame(height: SBSLayout.strokeHairline)
            .opacity(isHidden ? 0 : 1)
    }

    private func marker(for step: CycleBuilderView.BuilderStep) -> some View {
        let isCurrent = step == currentStep
        let isDone = step.rawValue < currentStep.rawValue
        return Rectangle()
            .fill(isCurrent ? Color.orangeFill : (isDone ? Color.ink : Color.surface))
            .overlay(
                Rectangle().strokeBorder(isCurrent || isDone ? Color.ink : Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
            .frame(width: 10, height: 10)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(steps, id: \.rawValue) { step in
                // Equal columns with the connector inside, so a label never gets squeezed
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        connector(isReached: isReached(step), isHidden: step == steps.first)
                        marker(for: step)
                        connector(isReached: step.rawValue < currentStep.rawValue, isHidden: step == steps.last)
                    }

                    // Markers only at the accessibility sizes: four labels can't fit
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(step.title)
                            .font(step == currentStep ? SBSFonts.caption().weight(.bold) : SBSFonts.caption())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(isReached(step)
                                            ? Color.ink
                                            : Color.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let position = (steps.firstIndex(of: currentStep) ?? 0) + 1
        return "Step \(position) of \(steps.count), \(currentStep.title)"
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let isOnboarding: Bool
    let onContinue: () -> Void
    let onTakeQuiz: () -> Void
    /// Onboarding-only escape hatch that finishes setup with sensible defaults.
    var onSkip: (() -> Void)? = nil

    @State private var animateIcon = false
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: SBSLayout.space6) {
                    // Icon on a square hairline tile: the screen's one orange is its button
                    Image(systemName: isOnboarding ? "figure.strengthtraining.traditional" : "arrow.clockwise")
                        .font(SBSFonts.titleLarge())
                        .foregroundStyle(Color.ink)
                        .frame(width: 88, height: 88)
                        .card()
                        .scaleEffect(animateIcon ? 1.0 : 0.8)
                        .opacity(animateContent ? 1 : 0)
                        .padding(.top, SBSLayout.space6)
                        .accessibilityHidden(true)

                    VStack(spacing: SBSLayout.space2) {
                        BuilderScreenTitle(isOnboarding ? "Welcome to\nTop Set Training" : "New Training Cycle")
                            .multilineTextAlignment(.center)
                        
                        Text(isOnboarding 
                             ? "Let's set up your personalized training program. This will only take a minute."
                             : "Ready to start a new cycle? Let's review your setup.")
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, SBSLayout.space6)
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                    
                    // Features list
                    VStack(spacing: SBSLayout.space3) {
                        VStack(spacing: 0) {
                            FeatureRow(icon: "doc.text", title: "Choose your program", description: "Select from available training templates")
                            SBSRowDivider()
                            FeatureRow(icon: "list.bullet.clipboard", title: "Customize exercises", description: "Adjust lifts and accessories for each day")
                            SBSRowDivider()
                            FeatureRow(icon: "scalemass", title: "Set your weights", description: "Enter yours, or start from our suggestions")
                        }
                        .card()

                        if isOnboarding {
                            // Reassuring message
                            HStack(spacing: SBSLayout.space2) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.inkSecondary)
                                    .accessibilityHidden(true)

                                Text("Don't worry, you can change all of these settings later in the app.")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.inkSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, SBSLayout.space2)

                            // Point new users toward the custom template builder.
                            HStack(spacing: SBSLayout.space2) {
                                Image(systemName: "hammer")
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.inkSecondary)
                                    .accessibilityHidden(true)

                                Text("Prefer your own routine? You can build a custom program anytime in Settings.")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.inkSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, SBSLayout.space6)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 30)
                }
                .padding(.bottom, SBSLayout.space6)
            }
            
            // Action buttons - pinned at bottom
            VStack(spacing: SBSLayout.space2) {
                // Primary: Get Started
                Button {
                    Haptics.light()
                    onContinue()
                } label: {
                    HStack(spacing: SBSLayout.space2) {
                        SBSButtonTitle(isOnboarding ? "I Know What I Want" : "Get Started")
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
                
                // Secondary: Help me choose (especially helpful for onboarding)
                if isOnboarding {
                    Button {
                        onTakeQuiz()
                    } label: {
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "sparkles")
                                .accessibilityHidden(true)
                            SBSButtonTitle("Help Me Choose a Program")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SBSSecondaryButtonStyle())

                    // Tertiary: escape hatch — finish now with sensible defaults.
                    if let onSkip {
                        Button {
                            onSkip()
                        } label: {
                            Text("Skip for now")
                                .font(SBSFonts.caption().weight(.semibold))
                                .foregroundStyle(Color.inkSecondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
            }
            .padding(.horizontal, SBSLayout.space6)
            .padding(.bottom, SBSLayout.space6)
            .opacity(animateContent ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                animateIcon = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                animateContent = true
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: SBSLayout.space4) {
            Image(systemName: icon)
                .font(SBSFonts.heading())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 32)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.ink)
                Text(description)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, SBSLayout.space3)
        .padding(.horizontal, SBSLayout.space4)
        .frame(minHeight: 56)
    }
}

/// A builder screen title in title-large: uppercase on screen, as written for VoiceOver.
private struct BuilderScreenTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(SBSFonts.titleLarge())
            .tracking(-0.34)
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text.replacingOccurrences(of: "\n", with: " "))
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Program Selection Step

struct ProgramSelectionStepView: View {
    @Bindable var appState: AppState
    @Binding var selectedProgram: String
    let backTitle: String
    let onBack: () -> Void
    let onContinue: () -> Void
    let onTakeQuiz: () -> Void
    let onBuildTemplate: () -> Void

    @State private var showingProgramPaywall = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: SBSLayout.space2) {
                Text("Select Program")
                    .font(SBSFonts.title())
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // The fixed header gives the list room at the accessibility sizes
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Choose your training template")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .padding(.top, SBSLayout.space4)
            .padding(.bottom, SBSLayout.space2)
            
            // Program selector (new clean design)
            ProgramSelector(
                appState: appState,
                selectedProgram: $selectedProgram,
                onTakeQuiz: onTakeQuiz,
                onBuildTemplate: onBuildTemplate
            )
            
            // Navigation buttons
            NavigationButtons(
                backTitle: backTitle,
                continueTitle: "Continue",
                onBack: onBack,
                onContinue: {
                    // The selector blocks *tapping* locked programs, but the
                    // current program is preselected on entry — a grandfathered
                    // user (mid-cycle on a program that left the free tier)
                    // hits the paywall here when starting a new cycle on it.
                    guard StoreManager.shared.canAccessProgram(selectedProgram) else {
                        showingProgramPaywall = true
                        return
                    }
                    onContinue()
                }
            )
            .sheet(isPresented: $showingProgramPaywall) {
                PaywallView(triggeredByFeature: .allPrograms)
            }
        }
        .onAppear {
            // Keep a selection that's already valid (quiz result, restored draft, or a
            // template just built). Only fall back when there's nothing usable.
            let isKnownSelection = appState.availablePrograms.contains { $0.id == selectedProgram }
                || (UserData.templateId(from: selectedProgram).flatMap { appState.userData.template(withId: $0) } != nil)
            guard !isKnownSelection else { return }

            // Set initial selection to currently loaded program or first free program
            if let currentProgramId = appState.userData.selectedProgram {
                selectedProgram = currentProgramId
            } else if let firstFree = appState.availablePrograms.first(where: { StoreManager.isProgramFree($0.id) }) {
                selectedProgram = firstFree.id
            } else if let first = appState.availablePrograms.first {
                selectedProgram = first.id
            }
        }
    }
}

// MARK: - Exercise Review Step

struct ExerciseReviewStepView: View {
    @Bindable var appState: AppState
    @Binding var exerciseCustomizations: [Int: [DayItem]]
    let onBack: () -> Void
    let onContinue: () -> Void
    
    @State private var selectedDay: Int = 1
    @State private var showingLiftPicker = false
    @State private var editingLift: String? = nil
    @State private var showingAddAccessory = false
    @State private var showingExercisePicker = false
    @State private var showingAccessoryEditor = false
    @State private var editingAccessoryIndex: Int? = nil
    @State private var editingAccessorySets: Int = 4
    @State private var editingAccessoryReps: Int = 10
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: SBSLayout.space2) {
                Text("Review Exercises")
                    .font(SBSFonts.title())
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                // The fixed header gives the list room at the accessibility sizes
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Customize the lifts for each training day")
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)

                    // Reassuring message
                    Text("Exercises can be changed in Settings")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .padding(.top, SBSLayout.space6)
            .padding(.horizontal)
            .padding(.bottom, SBSLayout.space4)
            
            // Day selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SBSLayout.space2) {
                    ForEach(appState.days, id: \.self) { day in
                        DayTab(
                            day: day,
                            title: "Day \(day)",
                            subtitle: appState.dayTitle(day: day),
                            isSelected: selectedDay == day,
                            onTap: { selectedDay = day }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, SBSLayout.space2)
            
            // Exercise list
            ScrollView {
                VStack(spacing: SBSLayout.space2) {
                    let items = currentDayItems
                    
                    // Main lifts (includes tm, volume, structured, and linear types)
                    let mainLifts = items.filter { $0.type == .tm || $0.type == .volume || $0.type == .structured || $0.type == .linear }
                    if !mainLifts.isEmpty {
                        SectionHeader(title: "Main Lifts")

                        VStack(spacing: 0) {
                            ForEach(Array(mainLifts.enumerated()), id: \.offset) { index, item in
                                if let lift = item.lift {
                                    if index > 0 { SBSRowDivider() }
                                    ExerciseItemRow(
                                        name: item.name,
                                        subtitle: subtitleForDayItem(item),
                                        icon: "figure.strengthtraining.traditional",
                                        onEdit: {
                                            editingLift = lift
                                            showingLiftPicker = true
                                        }
                                    )
                                }
                            }
                        }
                        .card()
                        .padding(.horizontal)
                    }

                    // Accessories
                    let accessoryIndices = items.indices.filter { items[$0].type == .accessory }
                    SectionHeader(title: "Accessories")

                    if !accessoryIndices.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(accessoryIndices, id: \.self) { actualIndex in
                                let item = items[actualIndex]
                                if actualIndex != accessoryIndices.first { SBSRowDivider() }
                                ExerciseItemRow(
                                    name: item.name,
                                    subtitle: "\(item.defaultSets ?? 4) × \(item.defaultReps ?? 10)",
                                    subtitleIsNumber: true,
                                    icon: "dumbbell",
                                    onEdit: {
                                        editingAccessoryIndex = actualIndex
                                        editingAccessorySets = item.defaultSets ?? 4
                                        editingAccessoryReps = item.defaultReps ?? 10
                                        showingAccessoryEditor = true
                                    },
                                    onDelete: {
                                        removeAccessory(at: actualIndex)
                                    }
                                )
                            }
                        }
                        .card()
                        .padding(.horizontal)
                    }

                    // Add accessory button
                    Button {
                        showingExercisePicker = true
                    } label: {
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "plus")
                                .accessibilityHidden(true)
                            SBSButtonTitle("Add Accessory")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SBSSecondaryButtonStyle())
                    .padding(.horizontal)
                    .padding(.top, SBSLayout.space2)
                }
                .padding(.bottom, SBSLayout.space6)
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Navigation buttons
            NavigationButtons(
                backTitle: "Back",
                continueTitle: "Continue",
                onBack: onBack,
                onContinue: onContinue
            )
        }
        .sheet(isPresented: $showingLiftPicker) {
            AccessoryExercisePickerSheet(
                title: "Select Main Lift",
                onSelect: { newLift in
                    if let oldLift = editingLift {
                        swapLift(from: oldLift, to: newLift)
                    }
                    showingLiftPicker = false
                },
                onCancel: { showingLiftPicker = false },
                mainLiftsOnly: false,
                showFilterChips: true,  // Show filter to toggle compound lifts
                currentExercise: editingLift
            )
        }
        .sheet(isPresented: $showingExercisePicker) {
            AccessoryExercisePickerSheet(
                title: "Add Accessory",
                onSelect: { exerciseName in
                    addAccessory(name: exerciseName)
                    showingExercisePicker = false
                },
                onCancel: { showingExercisePicker = false },
                mainLiftsOnly: false
            )
        }
        .sheet(isPresented: $showingAccessoryEditor) {
            AccessorySetsRepsEditor(
                sets: $editingAccessorySets,
                reps: $editingAccessoryReps,
                accessoryName: editingAccessoryIndex.flatMap { idx in
                    currentDayItems[safe: idx]?.name
                } ?? "Accessory",
                onSave: {
                    if let index = editingAccessoryIndex {
                        updateAccessorySetsReps(at: index, sets: editingAccessorySets, reps: editingAccessoryReps)
                    }
                    showingAccessoryEditor = false
                },
                onCancel: { showingAccessoryEditor = false }
            )
            .presentationDetents([.height(400)])
        }
    }
    
    private var currentDayItems: [DayItem] {
        exerciseCustomizations[selectedDay] ?? appState.dayItems(for: selectedDay)
    }
    
    private func subtitleForDayItem(_ item: DayItem) -> String {
        switch item.type {
        case .tm:
            return "Training Max"
        case .volume:
            return "Working Sets"
        case .structured:
            let setCount = item.setsDetail?.count ?? 9
            return "\(setCount) sets"
        case .accessory:
            return "Accessory"
        case .linear:
            return "\(item.sets ?? 5)×\(item.reps ?? 5) Linear"
        }
    }
    
    private func swapLift(from oldLift: String, to newLift: String) {
        // Days sharing a title are the same workout (Greyskull "Workout A"), and some of
        // them may have no tab this week, so a swap applies to all of them.
        for day in appState.daysWithSameVariant(as: selectedDay) {
            var items = exerciseCustomizations[day] ?? appState.dayItems(for: day)
            for i in items.indices {
                if items[i].lift == oldLift {
                    let newName = items[i].type == .tm ? "\(newLift) TM" : newLift
                    items[i].lift = newLift
                    items[i].name = newName
                }
            }
            exerciseCustomizations[day] = items
        }
    }
    
    private func addAccessory(name: String) {
        var items = currentDayItems
        items.append(DayItem(type: .accessory, lift: nil, name: name, defaultSets: 4, defaultReps: 10))
        saveItemsForSelectedDay(items)
    }
    
    private func removeAccessory(at index: Int) {
        var items = currentDayItems
        guard index < items.count else { return }
        items.remove(at: index)
        saveItemsForSelectedDay(items)
    }
    
    private func updateAccessorySetsReps(at index: Int, sets: Int, reps: Int) {
        var items = currentDayItems
        guard index < items.count, items[index].type == .accessory else { return }
        let item = items[index]
        items[index] = DayItem(type: .accessory, lift: nil, name: item.name, defaultSets: sets, defaultReps: reps)
        saveItemsForSelectedDay(items)
    }

    /// Store this day's items and keep accessories in step on same-workout days already
    /// customized here. Otherwise their stale list could win when setDayItems syncs
    /// accessories across those days on commit.
    private func saveItemsForSelectedDay(_ items: [DayItem]) {
        exerciseCustomizations[selectedDay] = items
        let accessories = items.filter { $0.type == .accessory }
        for day in appState.daysWithSameVariant(as: selectedDay) where day != selectedDay {
            guard let other = exerciseCustomizations[day] else { continue }
            exerciseCustomizations[day] = other.filter { $0.type != .accessory } + accessories
        }
    }
}

// MARK: - Accessory Sets/Reps Editor

struct AccessorySetsRepsEditor: View {
    @Binding var sets: Int
    @Binding var reps: Int
    let accessoryName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: SBSLayout.space6) {
                // Header with exercise name
                VStack(spacing: SBSLayout.space2) {
                    SBSEyebrow("Accessory")
                        .foregroundStyle(Color.inkSecondary)

                    Text(accessoryName)
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, SBSLayout.space4)
                
                // Steppers
                VStack(spacing: 0) {
                    SBSStepperRow(title: "Sets", value: $sets, range: 1...10)
                    SBSRowDivider()
                    SBSStepperRow(title: "Reps", value: $reps, range: 1...30)
                }
                .card()
                .padding(.horizontal)
                
                Spacer()
                
                // Save button
                Button(action: onSave) {
                    SBSButtonTitle("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
                .padding(.horizontal, SBSLayout.space6)
                .padding(.bottom, SBSLayout.space6)
            }
            .sbsBackground()
            .navigationTitle("Edit Sets & Reps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

struct DayTab: View {
    let day: Int
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                SBSEyebrow(title)
                    .foregroundStyle(Color.ink)
                Text(subtitle.replacingOccurrences(of: " Day", with: ""))
                    .font(SBSFonts.caption())
                    .foregroundStyle(isSelected ? Color.ink : Color.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, SBSLayout.space4)
            .padding(.vertical, SBSLayout.space2)
            .frame(minHeight: 44)
            .selectionCell(isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        SBSSectionEyebrow(title)
            .padding(.horizontal)
            .padding(.top, SBSLayout.space4)
    }
}

struct ExerciseItemRow: View {
    let name: String
    let subtitle: String
    var subtitleIsNumber: Bool = false
    let icon: String
    let onEdit: (() -> Void)?
    var onDelete: (() -> Void)? = nil

    var body: some View {
        SBSListRow(name) {
            Image(systemName: icon)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
        } subtitle: {
            if subtitleIsNumber {
                SBSRowSubtitle(subtitle)
            } else {
                Text(subtitle)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
        } trailing: {
            HStack(spacing: SBSLayout.space2) {
                if let onEdit = onEdit {
                    Button(action: onEdit) {
                        HStack(spacing: SBSLayout.space1) {
                            Image(systemName: "pencil")
                                .accessibilityHidden(true)
                            Text("Edit")
                        }
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, SBSLayout.space3)
                        .frame(minHeight: 36)
                        .selectionCell(false)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(name)")
                }

                if let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.danger)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(name)")
                }
            }
        }
    }
}

// MARK: - Training Maxes Step

struct TrainingMaxesStepView: View {
    @Bindable var appState: AppState
    @Binding var trainingMaxes: [String: Double]
    @Binding var carryOverTMs: Bool
    let isOnboarding: Bool
    /// The actual configured lifts (including any swapped-in exercises from cycle builder), in program order
    let configuredLifts: [String]
    /// Whether the entered number is a first working weight or a training max
    let kind: StartingWeightKind
    let targetReps: (String) -> Int
    /// A lift's value when carrying over from the last cycle
    let carriedMax: (String) -> Double
    /// A lift's value when not carrying over
    let defaultMax: (String) -> Double
    let onChangeUnits: (Bool) -> Void
    let onBack: () -> Void
    let onContinue: () -> Void

    @FocusState private var focusedLift: String?
    @State private var helpTarget: HelpTarget?

    private struct HelpTarget: Identifiable {
        let lift: String
        var id: String { lift }
    }

    private var entersWorkingWeight: Bool { kind == .firstWorkingWeight }

    private var heading: String {
        entersWorkingWeight ? "Set Starting Weights" : "Set Training Maxes"
    }

    private var currentValuesName: String {
        entersWorkingWeight ? "Current Weights" : "Current Training Maxes"
    }

    private var headerSubtitle: String {
        if !isOnboarding && carryOverTMs && appState.hasLoggedData {
            return entersWorkingWeight
                ? "Review your weights and adjust if needed"
                : "Review your training maxes and adjust if needed"
        }
        return entersWorkingWeight
            ? "The weight for your first workout on each lift"
            : "A training max for each lift. The program works from percentages of it."
    }

    private var infoTitle: String {
        entersWorkingWeight ? "What Weight Should I Enter?" : "What is a Training Max?"
    }

    private var infoBody: String {
        entersWorkingWeight
            ? "Enter what you'll lift in your first workout: a weight you can finish every rep with, in good form. The program adds weight as you hit your reps."
            : "Your training max (TM) should be about 85-90% of your true 1 rep max. This ensures you can hit all prescribed reps while leaving room for progression."
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: SBSLayout.space6) {
                    // Header
                    VStack(spacing: SBSLayout.space2) {
                        Text(heading)
                            .font(SBSFonts.title())
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text(headerSubtitle)
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, SBSLayout.space6)
                    .padding(.horizontal)

                    // Units come before any number is entered. Outside onboarding the
                    // unit is already set, and Settings is the place to change it.
                    if isOnboarding {
                        unitsControl
                    }

                    // Current TMs notice and option to customize (only for new cycles)
                    if !isOnboarding && appState.hasLoggedData {
                        VStack(spacing: SBSLayout.space2) {
                            // Notice that current TMs are being applied
                            if carryOverTMs {
                                HStack(alignment: .top, spacing: SBSLayout.space3) {
                                    Image(systemName: "checkmark")
                                        .font(SBSFonts.bodyStrong().weight(.bold))
                                        .foregroundStyle(Color.success)
                                        .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Using Your \(currentValuesName)")
                                            .font(SBSFonts.bodyStrong())
                                            .foregroundStyle(Color.ink)
                                        Text("These are pre-filled based on your last cycle. Adjust below if needed.")
                                            .font(SBSFonts.caption())
                                            .foregroundStyle(Color.inkSecondary)
                                    }

                                    Spacer()
                                }
                                .padding()
                                .card()
                            }

                            // Button to reset or use current TMs
                            Button(action: {
                                carryOverTMs.toggle()
                                for lift in configuredLifts {
                                    trainingMaxes[lift] = carryOverTMs ? carriedMax(lift) : defaultMax(lift)
                                }
                            }) {
                                HStack(spacing: SBSLayout.space1) {
                                    Image(systemName: carryOverTMs ? "arrow.counterclockwise" : "arrow.uturn.backward")
                                        .accessibilityHidden(true)
                                    Text(carryOverTMs ? "Reset to Default Values" : "Use \(currentValuesName)")
                                }
                                .font(SBSFonts.caption().weight(.semibold))
                                .foregroundStyle(Color.orangeText)
                                .frame(minHeight: 44)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal)
                    }

                    // Info box
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        Label(infoTitle, systemImage: "info.circle")
                            .font(SBSFonts.caption().weight(.semibold))
                            .foregroundStyle(Color.ink)

                        Text(infoBody)
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    .padding(.horizontal)

                    // Reassuring message for onboarding
                    if isOnboarding {
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "checkmark.seal")
                                .font(SBSFonts.bodyStrong())
                                .foregroundStyle(Color.inkSecondary)
                                .accessibilityHidden(true)

                            Text("We've filled in light starter weights. Change any you know, or tap \"Not sure?\" on a lift. You can adjust these anytime in Settings.")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal)
                    }

                    // Weight inputs
                    VStack(spacing: SBSLayout.space2) {
                        ForEach(configuredLifts, id: \.self) { lift in
                            TMInputRow(
                                liftName: lift,
                                value: Binding(
                                    get: { trainingMaxes[lift] ?? 0 },
                                    set: { trainingMaxes[lift] = $0 }
                                ),
                                useMetric: appState.settings.useMetric,
                                focus: $focusedLift,
                                onNotSure: {
                                    focusedLift = nil
                                    helpTarget = HelpTarget(lift: lift)
                                }
                            )
                            .id(lift)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, SBSLayout.space8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedLift) { _, lift in
                guard let lift else { return }
                // Once the keyboard has taken its space, or the row ends up behind the buttons
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation { proxy.scrollTo(lift, anchor: .center) }
                }
            }
            }

            // Navigation buttons
            NavigationButtons(
                backTitle: "Back",
                continueTitle: "Continue",
                onBack: onBack,
                onContinue: {
                    focusedLift = nil  // Dismiss keyboard before advancing
                    onContinue()
                },
                // Each empty row says why. A weight of 0 would produce 0 lb working sets.
                continueDisabled: configuredLifts.contains {
                    (trainingMaxes[$0] ?? 0) <= 0 && !StarterWeights.startsWithNoAddedWeight($0)
                }
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedLift = nil
                }
            }
        }
        .sheet(item: $helpTarget) { target in
            StartingWeightHelpSheet(
                lift: target.lift,
                kind: kind,
                targetReps: targetReps(target.lift),
                useMetric: appState.settings.useMetric,
                barWeight: appState.settings.barWeight,
                onUse: { trainingMaxes[target.lift] = $0 }
            )
        }
    }

    private var unitsControl: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSEyebrow("Units")
                .foregroundStyle(Color.inkSecondary)
                .accessibilityAddTraits(.isHeader)

            SBSSegmentedControl(
                options: [false, true],
                selection: Binding(
                    get: { appState.settings.useMetric },
                    set: { useMetric in
                        focusedLift = nil
                        onChangeUnits(useMetric)
                    }
                )
            ) { $0 ? "Kilograms (kg)" : "Pounds (lb)" }

            Text("Numbers you've typed stay the same. Only the unit changes.")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
    }
}

struct TMInputRow: View {
    let liftName: String
    @Binding var value: Double
    let useMetric: Bool
    let focus: FocusState<String?>.Binding
    let onNotSure: () -> Void

    @State private var inputText: String = ""

    private var isFocused: Bool { focus.wrappedValue == liftName }
    /// Zero is a real value here: no added weight
    private var isBodyweightLift: Bool { StarterWeights.startsWithNoAddedWeight(liftName) }
    /// Cleared or zero. Holds the step's Continue, so the row has to say why.
    private var needsValue: Bool { value <= 0 && !isBodyweightLift }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSAdaptiveStack(alignment: .firstTextBaseline) {
                Text(liftName)
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.ink)

                Spacer(minLength: 0)

                Button("Not sure?", action: onNotSure)
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.orangeText)
                    .frame(minHeight: 32)
                    .accessibilityLabel("Not sure about \(liftName)?")
            }

            HStack {
                TextField("Weight", text: $inputText)
                    .keyboardType(.decimalPad)
                    .font(SBSFonts.number())
                    .focused(focus, equals: liftName)
                    .accessibilityLabel("\(liftName) weight")
                    .onChange(of: isFocused) { _, focused in
                        // Tidy what was typed ("102.50") once the user moves on
                        if !focused { inputText = formatValue(value) }
                    }
                    .onChange(of: inputText) { _, newValue in
                        // Only the user's own typing edits the value. Formatting it for
                        // display must not write the rounded number back. Text that isn't
                        // a weight clears it rather than leaving the old number in force.
                        guard isFocused else { return }
                        value = parseInput(newValue) ?? 0
                    }

                Text(useMetric ? "kg" : "lb")
                    .font(SBSFonts.numberUnit())
                    .foregroundStyle(Color.inkSecondary)

                // Quick adjust buttons
                HStack(spacing: SBSLayout.space2) {
                    Button {
                        adjustValue(by: useMetric ? -2.5 : -5)
                    } label: {
                        adjustKey("minus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Decrease \(liftName) weight")

                    Button {
                        adjustValue(by: useMetric ? 2.5 : 5)
                    } label: {
                        adjustKey("plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Increase \(liftName) weight")
                }
            }
            .padding(.horizontal, SBSLayout.space4)
            .padding(.vertical, SBSLayout.space3)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                // 1px edge: orange-text while typing, warning when a value is missing
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(borderColor, lineWidth: SBSLayout.strokeHairline)
            )

            if needsValue {
                Label("Enter a weight above 0 to continue", systemImage: "exclamationmark.triangle")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.warning)
            }
            if isBodyweightLift {
                Text("Weight added to your bodyweight. 0 means none.")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .onAppear {
            inputText = formatValue(value)
        }
        .onChange(of: value) { _, newValue in
            // Update inputText when value changes from outside (e.g., carry over toggle)
            let newText = formatValue(newValue)
            if inputText != newText && !isFocused {
                inputText = newText
            }
        }
        .onChange(of: useMetric) { _, _ in
            inputText = formatValue(value)
        }
    }

    private var borderColor: Color {
        if needsValue { return Color.warning }
        return isFocused ? Color.orangeText : Color.hairline
    }

    private func adjustKey(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(SBSFonts.bodyStrong().weight(.bold))
            .foregroundStyle(Color.ink)
            .frame(width: 44, height: 36)
            .selectionCell(false)
            .contentShape(Rectangle())
    }

    /// An empty field rather than "0", so the placeholder and the message explain it
    private func formatValue(_ value: Double) -> String {
        guard value > 0 else { return isBodyweightLift ? "0" : "" }
        let displayValue = ((useMetric ? value * lbToKg : value) * 10).rounded() / 10
        if displayValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", displayValue)
        }
        return String(format: "%.1f", displayValue)
    }

    private func parseInput(_ text: String) -> Double? {
        guard let parsed = parseDecimalInput(text), parsed > 0 else { return nil }
        return parsed.poundsFromInput(useMetric: useMetric)
    }

    private func adjustValue(by amount: Double) {
        value = max(0, value + amount.poundsFromInput(useMetric: useMetric))
        inputText = formatValue(value)
    }
}

// MARK: - Starting Weight Help

/// For someone who doesn't know what to enter: a suggested starter, or an estimate from
/// a set they've done. Uses the same units and meaning as the row that opened it.
struct StartingWeightHelpSheet: View {
    let lift: String
    let kind: StartingWeightKind
    let targetReps: Int
    let useMetric: Bool
    let barWeight: Double
    let onUse: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var repsText = ""
    @FocusState private var isEditing: Bool

    private var starter: Double {
        StarterWeights.starter(for: lift, useMetric: useMetric, barWeight: barWeight, kind: kind)
    }

    private var reps: Int? {
        Int(repsText.trimmingCharacters(in: .whitespaces))
    }

    private var estimate: Double? {
        guard let weight = parseDecimalInput(weightText), let reps else { return nil }
        return StarterWeights.estimate(
            weightLifted: weight.poundsFromInput(useMetric: useMetric),
            reps: reps,
            kind: kind,
            targetReps: targetReps,
            useMetric: useMetric,
            barWeight: StarterWeights.startsWithNoAddedWeight(lift) ? 0 : barWeight
        )
    }

    private var starterExplanation: String {
        if StarterWeights.startsWithNoAddedWeight(lift) {
            return "Start with your bodyweight and no added weight."
        }
        return kind == .firstWorkingWeight
            ? "A light first working weight for most people new to this lift."
            : "A light training max for most people new to this lift."
    }

    private var estimateExplanation: String {
        if let reps, reps > StarterWeights.maxEstimateReps {
            return "Use a set of \(StarterWeights.maxEstimateReps) reps or fewer. Longer sets don't estimate well."
        }
        return kind == .firstWorkingWeight
            ? "This gives a first working weight for sets of \(targetReps), a little under your limit."
            : "This gives a training max: 90% of your estimated 1 rep max."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SBSLayout.space4) {
                    card(title: "Use a Suggestion", explanation: starterExplanation) {
                        Button {
                            use(starter)
                        } label: {
                            SBSButtonTitle("Use \(starter.formattedWeight(useMetric: useMetric))")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SBSSecondaryButtonStyle())
                    }

                    card(title: "Estimate From a Recent Set", explanation: estimateExplanation) {
                        HStack(spacing: SBSLayout.space2) {
                            TextField("Weight", text: $weightText)
                                .keyboardType(.decimalPad)
                                .focused($isEditing)
                                .font(SBSFonts.number())
                                .sbsFieldCell()
                                .accessibilityLabel("Weight lifted")

                            Text(useMetric ? "kg for" : "lb for")
                                .font(SBSFonts.numberUnit())
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize()

                            TextField("Reps", text: $repsText)
                                .keyboardType(.numberPad)
                                .focused($isEditing)
                                .font(SBSFonts.number())
                                .sbsFieldCell()
                                .accessibilityLabel("Reps")
                        }

                        // The sheet's one primary action; disabled it drops to a hairline
                        Button {
                            if let estimate { use(estimate) }
                        } label: {
                            SBSButtonTitle(estimate.map { "Use \($0.formattedWeight(useMetric: useMetric))" } ?? "Enter a Weight and Reps")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SBSPrimaryButtonStyle())
                        .disabled(estimate == nil)
                        .padding(.trailing, SBSLayout.hardShadowOffset)
                        .padding(.bottom, SBSLayout.hardShadowOffset)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .sbsBackground()
            .navigationTitle(lift)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditing = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func use(_ weight: Double) {
        Haptics.light()
        onUse(weight)
        dismiss()
    }

    private func card<Content: View>(
        title: String,
        explanation: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            Text(title)
                .font(SBSFonts.heading())
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)

            Text(explanation)
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Summary Step

struct SummaryStepView: View {
    @Bindable var appState: AppState
    let selectedProgram: String
    let trainingMaxes: [String: Double]
    let orderedLifts: [String]
    let kind: StartingWeightKind
    let exerciseCustomizations: [Int: [DayItem]]
let isOnboarding: Bool
    let onBack: () -> Void
    let onComplete: () -> Void
    
    @State private var animateCheckmark = false
    
    private var programInfo: AppState.AvailableProgramInfo? {
        appState.availablePrograms.first { $0.id == selectedProgram }
    }
    
    private var customTemplate: CustomTemplate? {
        guard UserData.isCustomTemplate(programId: selectedProgram),
              let templateId = UserData.templateId(from: selectedProgram) else {
            return nil
        }
        return appState.userData.template(withId: templateId)
    }
    
    private var programName: String {
        // Check for custom template first
        if let template = customTemplate {
            return template.name
        }
        return programInfo?.displayName ?? appState.displayName(forProgramId: selectedProgram)
    }
    
    private var programWeeks: Int {
        if let template = customTemplate {
            return template.weeks.count
        }
        return programInfo?.weeks ?? appState.programInfo?.weeks ?? 20
    }
    
    private var programDays: Int {
        if let template = customTemplate {
            return template.daysPerWeek
        }
        return programInfo?.days ?? appState.programInfo?.days ?? 5
    }
    
    private var isCustomTemplate: Bool {
        customTemplate != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: SBSLayout.space6) {
                    // Header with animation
                    VStack(spacing: SBSLayout.space4) {
                        // A glyph on a hairline tile, not a status fill
                        Image(systemName: "checkmark")
                            .font(SBSFonts.titleLarge())
                            .foregroundStyle(Color.success)
                            .frame(width: 88, height: 88)
                            .card()
                            .scaleEffect(animateCheckmark ? 1.0 : 0.5)
                            .accessibilityHidden(true)

                        Text(isOnboarding ? "Ready to Begin!" : "Review Your Cycle")
                            .font(SBSFonts.title())
                            .foregroundStyle(Color.ink)
                            .accessibilityAddTraits(.isHeader)
                        
                        Text("Here's a summary of your setup")
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .padding(.top, SBSLayout.space6)
                    
                    // Program summary
                    SummaryCard(title: "Program") {
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: isCustomTemplate ? "square.stack.3d.up" : "doc.text")
                                .foregroundStyle(Color.inkSecondary)
                                .accessibilityHidden(true)
                            Text(programName)
                                .font(SBSFonts.heading())
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            if isCustomTemplate {
                                SBSBadge(text: "Custom")
                            }

                            Spacer(minLength: 0)
                        }

                        SBSRowDivider()

                        HStack {
                            SummaryStatItem(value: "\(programWeeks)", label: "Weeks")
                            SummaryStatItem(value: "\(programDays)", label: "Days/Week")
                            SummaryStatItem(value: "\(trainingMaxes.count)", label: "Lifts")
                        }
                    }
                    
                    // Training maxes summary
                    SummaryCard(title: kind == .firstWorkingWeight ? "Starting Weights" : "Starting Training Maxes") {
                        ForEach(orderedLifts, id: \.self) { lift in
if let value = trainingMaxes[lift] {
                                SBSAdaptiveStack {
                                    Text(lift)
                                        .font(SBSFonts.body())
                                        .foregroundStyle(Color.ink)
                                    Spacer(minLength: 0)
                                    Text(value.formattedWeight(useMetric: appState.settings.useMetric))
                                        .font(SBSFonts.number())
                                        .foregroundStyle(Color.ink)
                                }
                                .accessibilityElement(children: .combine)

                                if lift != orderedLifts.last {
                                    SBSRowDivider()
                                }
                            }
                        }
                    }
                    
                    // Customizations note
                    if !exerciseCustomizations.isEmpty {
                        SummaryCard(title: "Customizations") {
                            HStack {
                                Image(systemName: "pencil")
                                    .foregroundStyle(Color.inkSecondary)
                                    .accessibilityHidden(true)
                                Text("You've customized \(exerciseCustomizations.count) day(s)")
                                    .font(SBSFonts.body())
                                    .foregroundStyle(Color.ink)
                                Spacer()
                            }
                        }
                    }
                    
                    // Tips
                    // "Tips", not "Pro Tips": Pro is the paywall badge's word
                    SummaryCard(title: "Tips") {
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            TipItem(text: "Log your rep-outs honestly for accurate progression")
                            TipItem(text: "You can adjust weights mid-workout if needed")
                            TipItem(text: kind == .firstWorkingWeight ? "Review your weights in Settings anytime" : "Review your training maxes in Settings anytime")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, SBSLayout.space8)
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Complete button
            VStack(spacing: SBSLayout.space4) {
                Button {
                    Haptics.success()
                    onComplete()
                } label: {
                    HStack(spacing: SBSLayout.space2) {
                        SBSButtonTitle(isOnboarding ? "Start Training" : "Start New Cycle")
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())

                Button {
                    onBack()
                } label: {
                    Text("Go Back")
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, SBSLayout.space6)
            .padding(.vertical, SBSLayout.space4)
            .background(Color.bg)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.2)) {
                animateCheckmark = true
            }
        }
    }
}

struct SummaryCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow(title)

            VStack(spacing: SBSLayout.space3) {
                content
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .padding(.horizontal)
    }
}

struct SummaryStatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: SBSLayout.space1) {
            Text(value)
                .font(SBSFonts.numberLarge())
                .foregroundStyle(Color.ink)
            SBSEyebrow(label)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct TipItem: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
            Image(systemName: "checkmark")
                .font(SBSFonts.caption().weight(.bold))
                .foregroundStyle(Color.inkSecondary)
                .accessibilityHidden(true)

            Text(text)
                .font(SBSFonts.body())
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Navigation Buttons

struct NavigationButtons: View {
    let backTitle: String
    let continueTitle: String
    let onBack: () -> Void
    let onContinue: () -> Void
    var continueDisabled: Bool = false
    
    var body: some View {
        // Back is the hairline alternative; Continue is the step's one primary button
        SBSAdaptiveStack(spacing: SBSLayout.space3) {
            Button {
                onBack()
            } label: {
                HStack(spacing: SBSLayout.space2) {
                    Image(systemName: "arrow.left")
                        .accessibilityHidden(true)
                    SBSButtonTitle(backTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SBSSecondaryButtonStyle())

            Button {
                Haptics.light()
                onContinue()
            } label: {
                HStack(spacing: SBSLayout.space2) {
                    SBSButtonTitle(continueTitle)
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SBSPrimaryButtonStyle())
            .disabled(continueDisabled)
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
        .background(Color.bg)
    }
}

// MARK: - Program Detail View

struct ProgramDetailView: View {
    let program: AppState.AvailableProgramInfo
    var programData: ProgramData? = nil  // Optional initial data (used when already loaded)
    let level: ProgramLevel
    var onStartCycle: (() -> Void)? = nil  // Optional callback to start a cycle with this program
    @Environment(\.dismiss) private var dismiss
    @State private var loadedProgramData: ProgramData?
    @State private var isLoading = true
    
    private var effectiveProgramData: ProgramData? {
        loadedProgramData ?? programData
    }
    
    private var mainLifts: [String] {
        guard let data = effectiveProgramData else { return [] }
        var lifts = Set<String>()
        for (_, items) in data.days {
            for item in items {
                if let lift = item.lift, item.type != .accessory && item.type != .tm {
                    lifts.insert(lift)
                }
            }
        }
        return lifts.sorted()
    }
    
    private var accessoryExercises: [String] {
        guard let data = effectiveProgramData else { return [] }
        var accessories = Set<String>()
        for (_, items) in data.days {
            for item in items {
                if item.type == .accessory {
                    accessories.insert(item.name)
                }
            }
        }
        return accessories.sorted()
    }
    
    private var progressionType: String {
        guard let data = effectiveProgramData else { return "Progressive Overload" }
        
        // Determine based on exercise types in the program
        var hasVolume = false
        var hasStructured = false
        var hasLinear = false
        
        for (_, items) in data.days {
            for item in items {
                switch item.type {
                case .volume: hasVolume = true
                case .structured: hasStructured = true
                case .linear: hasLinear = true
                default: break
                }
            }
        }
        
        if hasVolume {
            return "Autoregulated (Rep-Out Based)"
        } else if hasStructured {
            return "AMRAP-Driven Progression"
        } else if hasLinear {
            return "Linear (Add Weight Each Session)"
        }
        return "Progressive Overload"
    }
    
    private func dayItems(for dayNumber: Int) -> [DayItem] {
        guard let data = effectiveProgramData else { return [] }
        return data.days[String(dayNumber)] ?? []
    }
    
    private func loadProgramData() async {
        // If we already have data, use it
        if programData != nil {
            loadedProgramData = programData
            isLoading = false
            return
        }
        
        // Load from the program URL
        do {
            let data = try Data(contentsOf: program.url)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(ProgramData.self, from: data)
            await MainActor.run {
                loadedProgramData = decoded
                isLoading = false
            }
        } catch {
            Logger.error("Failed to load program data: \(error)", category: .program)
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    /// Format a compact summary of sets/reps for the exercise
    private func formatSetsReps(for item: DayItem) -> String {
        if let setsDetail = item.setsDetail {
            return formatStructuredCompact(setsDetail)
        } else if let sets = item.sets, let reps = item.reps {
            // Linear progression - always at 100% TM
            return "\(sets)×\(reps) @ 100%"
        } else if let defaultSets = item.defaultSets, let defaultReps = item.defaultReps {
            return "\(defaultSets)×\(defaultReps)"
        } else if item.type == .volume, let lift = item.lift {
            // SBS volume - get week 1 data
            return formatVolumeCompact(lift: lift)
        }
        return ""
    }
    
    /// Format structured exercise sets into a compact display
    private func formatStructuredCompact(_ setsDetail: [SetDetail]) -> String {
        let setCount = setsDetail.count
        let intensities = setsDetail.map { $0.intensity }
        let minIntensity = intensities.min() ?? 0
        let maxIntensity = intensities.max() ?? 0
        let hasAmrap = setsDetail.contains { $0.isAMRAP }
        
        let intensityStr: String
        if minIntensity == maxIntensity {
            intensityStr = "\(Int(minIntensity * 100))%"
        } else {
            intensityStr = "\(Int(minIntensity * 100))-\(Int(maxIntensity * 100))%"
        }
        
        let amrapIndicator = hasAmrap ? "+" : ""
        return "\(setCount) sets\(amrapIndicator) @ \(intensityStr)"
    }
    
    /// Format SBS volume exercise using week 1 data
    private func formatVolumeCompact(lift: String) -> String {
        guard let data = effectiveProgramData,
              let weekData = data.lifts[lift]?["1"] else {
            return "Varies by week"
        }
        
        let intensity = Int(weekData.intensity * 100)
        return "\(weekData.sets)×\(weekData.repsPerNormalSet)+ @ \(intensity)%"
    }
    
    /// Generate detailed preview info for an exercise
    private func detailedPreviewInfo(for item: DayItem) -> ExercisePreviewInfo {
        // Handle structured exercises with explicit per-set configuration
        if let setsDetail = item.setsDetail {
            let intensities = setsDetail.map { $0.intensity }
            let minIntensity = intensities.min() ?? 0
            let maxIntensity = intensities.max() ?? 0
            let hasAmrap = setsDetail.contains { $0.isAMRAP }
            
            let intensityText: String
            if minIntensity == maxIntensity {
                intensityText = "\(Int(minIntensity * 100))% TM"
            } else {
                intensityText = "\(Int(minIntensity * 100))-\(Int(maxIntensity * 100))% TM"
            }
            
            // Create detailed rows for expansion
            let detailRows = setsDetail.map { set in
                SetPreviewRow(
                    reps: set.isAMRAP ? "\(set.reps)+" : "\(set.reps)",
                    intensity: Int(set.intensity * 100)
                )
            }
            
            let noteText: String? = setsDetail.count > 3 ? "Structured" : nil
            
            return ExercisePreviewInfo(
                setsText: "\(setsDetail.count) sets",
                intensityText: intensityText,
                hasAMRAP: hasAmrap,
                noteText: noteText,
                detailRows: detailRows
            )
        }
        
        // Handle linear progression
        if let sets = item.sets, let reps = item.reps {
            return ExercisePreviewInfo(
                setsText: "\(sets)×\(reps)",
                intensityText: "100% TM",
                hasAMRAP: false,
                noteText: nil,
                detailRows: nil
            )
        }
        
        // Handle SBS volume exercises
        if item.type == .volume, let lift = item.lift,
           let data = effectiveProgramData,
           let weekData = data.lifts[lift]?["1"] {
            return ExercisePreviewInfo(
                setsText: "\(weekData.sets)×\(weekData.repsPerNormalSet)",
                intensityText: "\(Int(weekData.intensity * 100))% TM",
                hasAMRAP: true,
                noteText: "Week 1",
                detailRows: nil
            )
        }
        
        // Handle accessories with default values
        if let defaultSets = item.defaultSets, let defaultReps = item.defaultReps {
            return ExercisePreviewInfo(
                setsText: "\(defaultSets)×\(defaultReps)",
                intensityText: "User weight",
                hasAMRAP: false,
                noteText: nil,
                detailRows: nil
            )
        }
        
        // Fallback
        return ExercisePreviewInfo(
            setsText: "Variable",
            intensityText: "",
            hasAMRAP: false,
            noteText: nil,
            detailRows: nil
        )
    }
    
    /// Get the day title from program data
    private func dayTitle(for dayNumber: Int) -> String? {
        effectiveProgramData?.dayTitles?[String(dayNumber)]
    }
    
    // MARK: - Weekly Volume Calculation
    
    /// Calculate total weekly sets for each lift
    private var weeklyVolume: [VolumeEntry] {
        guard let data = effectiveProgramData else { return [] }
        
        var volumeByLift: [String: Int] = [:]
        var muscleGroupByLift: [String: MuscleGroup] = [:]
        
        // Count sets from all days
        for dayNumber in 1...program.days {
            guard let dayItems = data.days[String(dayNumber)] else { continue }
            
            for item in dayItems where item.type != .tm {
                let liftName = item.lift ?? item.name
                let muscleGroup = MuscleGroup.forLift(liftName)
                muscleGroupByLift[liftName] = muscleGroup
                
                let setCount: Int
                if let setsDetail = item.setsDetail {
                    // nSuns-style with detailed sets
                    setCount = setsDetail.count
                } else if let sets = item.sets {
                    // Linear progression
                    setCount = sets
                } else if let defaultSets = item.defaultSets {
                    // Accessories
                    setCount = defaultSets
                } else if item.type == .volume, let lift = item.lift,
                          let weekData = data.lifts[lift]?["1"] {
                    // SBS volume - use week 1 sets
                    setCount = weekData.sets
                } else {
                    // Default for accessories without specified sets
                    setCount = item.type == .accessory ? 3 : 0
                }
                
                volumeByLift[liftName, default: 0] += setCount
            }
        }
        
        // Convert to sorted array
        return volumeByLift.map { lift, sets in
            VolumeEntry(
                liftName: lift,
                weeklySets: sets,
                muscleGroup: muscleGroupByLift[lift] ?? .other
            )
        }
        .sorted { a, b in
            // Sort by muscle group, then by sets (descending)
            if a.muscleGroup.sortOrder != b.muscleGroup.sortOrder {
                return a.muscleGroup.sortOrder < b.muscleGroup.sortOrder
            }
            return a.weeklySets > b.weeklySets
        }
    }
    
    /// Group volume by muscle group for summary
    private var volumeByMuscleGroup: [(group: MuscleGroup, totalSets: Int, lifts: [VolumeEntry])] {
        let grouped = Dictionary(grouping: weeklyVolume) { $0.muscleGroup }
        
        return grouped.map { group, entries in
            (group: group, totalSets: entries.reduce(0) { $0 + $1.weeklySets }, lifts: entries)
        }
        .sorted { $0.group.sortOrder < $1.group.sortOrder }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSLayout.space6) {
                    // Header
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        SBSAdaptiveStack(alignment: .firstTextBaseline) {
                            Text(program.displayName)
                                .font(SBSFonts.title())
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)

                            Spacer(minLength: 0)

                            SBSBadge(text: level.rawValue)
                        }

                        Text(program.programDescription)
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Quick Stats
                    ProgramStatsRow(days: program.days, weeks: program.weeks, mainLifts: mainLifts.count)

                    // Progression Section
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        SBSSectionEyebrow("Progression")

                        HStack(spacing: SBSLayout.space3) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(SBSFonts.bodyStrong())
                                .foregroundStyle(Color.inkSecondary)
                                .accessibilityHidden(true)

                            Text(progressionType)
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.ink)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    // Weekly Volume Section
                    if !volumeByMuscleGroup.isEmpty {
                        WeeklyVolumeCard(
                            volumeByGroup: volumeByMuscleGroup,
                            accentColor: Color.ink
                        )
                    }

                    // Main Lifts Section
                    if !mainLifts.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            SBSSectionEyebrow("Main Lifts")

                            FlowLayout(spacing: SBSLayout.space2) {
                                ForEach(mainLifts, id: \.self) { lift in
                                    HairlineTag(text: lift, isStrong: true)
                                }
                            }
                        }
                    }

                    // Accessories Section
                    if !accessoryExercises.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            SBSSectionEyebrow("Accessories")

                            FlowLayout(spacing: SBSLayout.space2) {
                                ForEach(accessoryExercises, id: \.self) { exercise in
                                    HairlineTag(text: exercise)
                                }
                            }
                        }
                    }

                    // Weekly Schedule
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        SBSSectionEyebrow("Weekly Schedule") {
                            // Note about percentages
                            Text("% = Training Max")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                        }

                        VStack(spacing: SBSLayout.space3) {
                            ForEach(1...program.days, id: \.self) { day in
                                DayPreviewCard(
                                    dayNumber: day,
                                    dayTitle: dayTitle(for: day),
                                    items: dayItems(for: day),
                                    formatSetsReps: formatSetsReps,
                                    formatDetailedSets: detailedPreviewInfo,
                                    accentColor: Color.ink
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.orangeText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let startCycle = onStartCycle {
                    VStack {
                        Button {
                            dismiss()
                            startCycle()
                        } label: {
                            HStack(spacing: SBSLayout.space2) {
                                Image(systemName: "play.fill")
                                    .accessibilityHidden(true)
                                SBSButtonTitle("Start Cycle with This Program")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SBSPrimaryButtonStyle())
                    }
                    .padding()
                    .padding(.trailing, SBSLayout.hardShadowOffset)
                    .background(Color.bg)
                }
            }
            .overlay {
                if isLoading && effectiveProgramData == nil {
                    VStack(spacing: SBSLayout.space4) {
                        ProgressView()
                            .tint(Color.ink)
                        Text("Loading program...")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bg)
                }
            }
            .task {
                await loadProgramData()
            }
        }
    }
}

// MARK: - Supporting Views for Program Detail

/// The three stats under a program's title, in one hairline group.
struct ProgramStatsRow: View {
    let days: Int
    let weeks: Int
    let mainLifts: Int

    var body: some View {
        HStack(spacing: 0) {
            StatCard(icon: "calendar", value: "\(days)", label: "Days/Week")
            hairline
            StatCard(icon: "clock", value: "\(weeks)", label: "Weeks")
            hairline
            StatCard(icon: "dumbbell", value: "\(mainLifts)", label: "Main Lifts")
        }
        .fixedSize(horizontal: false, vertical: true)
        .card()
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(width: SBSLayout.strokeHairline)
            .accessibilityHidden(true)
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: SBSLayout.space1) {
            Image(systemName: icon)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.inkSecondary)
                .accessibilityHidden(true)

            Text(value)
                .font(SBSFonts.numberLarge())
                .foregroundStyle(Color.ink)

            SBSEyebrow(label)
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SBSLayout.space3)
        .padding(.horizontal, SBSLayout.space1)
        .accessibilityElement(children: .combine)
    }
}

/// A non-interactive name tag on a hairline cell: lifts and accessories in a program preview.
struct HairlineTag: View {
    let text: String
    var isStrong: Bool = false

    var body: some View {
        Text(text)
            .font(isStrong ? SBSFonts.caption().weight(.semibold) : SBSFonts.caption())
            .foregroundStyle(isStrong ? Color.ink : Color.inkSecondary)
            .padding(.horizontal, SBSLayout.space3)
            .padding(.vertical, 6)
            .selectionCell(false)
    }
}

struct DayPreviewCard: View {
    let dayNumber: Int
    let dayTitle: String?
    let items: [DayItem]
    let formatSetsReps: (DayItem) -> String
    let formatDetailedSets: ((DayItem) -> ExercisePreviewInfo)?
    let accentColor: Color
    
    init(
        dayNumber: Int,
        dayTitle: String? = nil,
        items: [DayItem],
        formatSetsReps: @escaping (DayItem) -> String,
        formatDetailedSets: ((DayItem) -> ExercisePreviewInfo)? = nil,
        accentColor: Color
    ) {
        self.dayNumber = dayNumber
        self.dayTitle = dayTitle
        self.items = items
        self.formatSetsReps = formatSetsReps
        self.formatDetailedSets = formatDetailedSets
        self.accentColor = accentColor
    }
    
    private var mainExercises: [DayItem] {
        items.filter { $0.type != .accessory && $0.type != .tm }
    }
    
    private var accessories: [DayItem] {
        items.filter { $0.type == .accessory }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            // Header with day number and title
            SBSAdaptiveStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    SBSEyebrow("Day \(dayNumber)")
                        .foregroundStyle(Color.inkSecondary)

                    if let title = dayTitle {
                        Text(title)
                            .font(SBSFonts.heading())
                            .foregroundStyle(Color.ink)
                    }
                }

                Spacer(minLength: 0)

                Text("\(mainExercises.count) main · \(accessories.count) acc")
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }

            SBSRowDivider()
            
            // Main exercises with detailed info
            ForEach(Array(mainExercises.enumerated()), id: \.offset) { _, item in
                ExercisePreviewRow(
                    item: item,
                    info: formatDetailedSets?(item),
                    compactInfo: formatSetsReps(item),
                    accentColor: accentColor
                )
            }
            
            // Accessories (collapsed)
            if !accessories.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "plus")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .accessibilityHidden(true)

                    Text(accessories.map { $0.name }.joined(separator: ", "))
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .card()
    }
}

/// Detailed preview info for an exercise
struct ExercisePreviewInfo {
    let setsText: String           // e.g., "9 sets" or "4×10"
    let intensityText: String      // e.g., "65-95% TM" or "70% TM"
    let hasAMRAP: Bool
    let noteText: String?          // e.g., "Structured" or "Week 1"
    let detailRows: [SetPreviewRow]? // Optional detailed breakdown
}

struct SetPreviewRow: Identifiable {
    let id = UUID()
    let reps: String    // e.g., "5" or "1+"
    let intensity: Int  // percentage
}

/// Row displaying a single exercise with preview info
struct ExercisePreviewRow: View {
    let item: DayItem
    let info: ExercisePreviewInfo?
    let compactInfo: String
    let accentColor: Color
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.lift ?? item.name)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)

                    if let info = info {
                        // Wraps rather than truncating at large text sizes
                        FlowLayout(spacing: 6) {
                            Text("\(info.setsText) @ \(info.intensityText)")
                                .font(SBSFonts.numberSmall())
                                .foregroundStyle(Color.inkSecondary)

                            if info.hasAMRAP {
                                SBSBadge(text: "AMRAP")
                            }

                            if let note = info.noteText {
                                Text(note)
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                    } else {
                        Text(compactInfo)
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)
                    }
                }

                Spacer()

                // Expand button for structured sets
                if let info = info, let details = info.detailRows, details.count > 3 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        SBSChevron(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Hide set details" : "Show set details")
                }
            }
            
            // Expanded set details (for structured exercises)
            if isExpanded, let info = info, let details = info.detailRows {
                SetPreviewGrid(rows: details, accentColor: accentColor)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }
}

/// Grid showing detailed set breakdown
struct SetPreviewGrid: View {
    let rows: [SetPreviewRow]
    let accentColor: Color
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(rows.count, 5)), spacing: 4) {
            ForEach(rows) { row in
                // Set grid cells: reps over percentage, both tabular
                VStack(spacing: 1) {
                    Text(row.reps)
                        .font(SBSFonts.numberSmall().weight(.semibold))
                        .foregroundStyle(Color.ink)

                    Text("\(row.intensity)%")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 2)
                .selectionCell(false)
            }
        }
    }
}

// MARK: - Custom Template Detail View

/// Detail view for previewing a custom template (matches ProgramDetailView functionality)
struct CustomTemplateDetailView: View {
    let template: CustomTemplate
    var onStartCycle: (() -> Void)? = nil  // Optional callback to start a cycle with this template
    @Environment(\.dismiss) private var dismiss
    
    /// Detail views are ink; orange is for the one action
    private let accentColor: Color = Color.ink
    
    private var programData: ProgramData {
        template.toProgramData()
    }
    
    private var mainLifts: [String] {
        var lifts = Set<String>()
        for (_, items) in template.days {
            for item in items {
                if let lift = item.lift, item.type != .accessory && item.type != .tm {
                    lifts.insert(lift)
                }
            }
        }
        return lifts.sorted()
    }
    
    private var accessoryExercises: [String] {
        var accessories = Set<String>()
        for (_, items) in template.days {
            for item in items {
                if item.type == .accessory {
                    accessories.insert(item.name)
                }
            }
        }
        return accessories.sorted()
    }
    
    private var progressionType: String {
        // Determine based on exercise types in the template
        var hasVolume = false
        var hasStructured = false
        var hasLinear = false
        
        for (_, items) in template.days {
            for item in items {
                switch item.type {
                case .volume: hasVolume = true
                case .structured: hasStructured = true
                case .linear: hasLinear = true
                default: break
                }
            }
        }
        
        if hasVolume {
            return "Autoregulated (Rep-Out Based)"
        } else if hasStructured {
            return "AMRAP-Driven Progression"
        } else if hasLinear {
            return "Linear (Add Weight Each Session)"
        }
        return "Fixed Sets/Reps"
    }
    
    private func dayItems(for dayNumber: Int) -> [DayItem] {
        template.days[String(dayNumber)] ?? []
    }
    
    private func dayTitle(for dayNumber: Int) -> String? {
        nil  // Custom templates don't have day titles currently
    }
    
    /// Format a compact summary of sets/reps for the exercise
    private func formatSetsReps(for item: DayItem) -> String {
        if let setsDetail = item.setsDetail {
            return formatNSunsCompact(setsDetail)
        } else if let sets = item.sets, let reps = item.reps {
            return "\(sets)×\(reps) @ 100%"
        } else if let defaultSets = item.defaultSets, let defaultReps = item.defaultReps {
            return "\(defaultSets)×\(defaultReps)"
        } else if item.type == .volume, let lift = item.lift {
            return formatVolumeCompact(lift: lift)
        }
        return ""
    }
    
    private func formatNSunsCompact(_ setsDetail: [SetDetail]) -> String {
        let setCount = setsDetail.count
        let intensities = setsDetail.map { $0.intensity }
        let minIntensity = intensities.min() ?? 0
        let maxIntensity = intensities.max() ?? 0
        let hasAmrap = setsDetail.contains { $0.isAMRAP }
        
        let intensityStr: String
        if minIntensity == maxIntensity {
            intensityStr = "\(Int(minIntensity * 100))%"
        } else {
            intensityStr = "\(Int(minIntensity * 100))-\(Int(maxIntensity * 100))%"
        }
        
        let amrapIndicator = hasAmrap ? "+" : ""
        return "\(setCount) sets\(amrapIndicator) @ \(intensityStr)"
    }
    
    private func formatVolumeCompact(lift: String) -> String {
        guard let weekData = template.lifts?[lift]?["1"] else {
            return "Varies by week"
        }
        
        let intensity = Int(weekData.intensity * 100)
        return "\(weekData.sets)×\(weekData.repsPerNormalSet)+ @ \(intensity)%"
    }
    
    private func detailedPreviewInfo(for item: DayItem) -> ExercisePreviewInfo {
        // Handle nSuns pyramid exercises
        if let setsDetail = item.setsDetail {
            let intensities = setsDetail.map { $0.intensity }
            let minIntensity = intensities.min() ?? 0
            let maxIntensity = intensities.max() ?? 0
            let hasAmrap = setsDetail.contains { $0.isAMRAP }
            
            let intensityText: String
            if minIntensity == maxIntensity {
                intensityText = "\(Int(minIntensity * 100))% TM"
            } else {
                intensityText = "\(Int(minIntensity * 100))-\(Int(maxIntensity * 100))% TM"
            }
            
            let detailRows = setsDetail.map { set in
                SetPreviewRow(
                    reps: set.isAMRAP ? "\(set.reps)+" : "\(set.reps)",
                    intensity: Int(set.intensity * 100)
                )
            }
            
            let noteText: String? = setsDetail.count > 3 ? "Pyramid" : nil
            
            return ExercisePreviewInfo(
                setsText: "\(setsDetail.count) sets",
                intensityText: intensityText,
                hasAMRAP: hasAmrap,
                noteText: noteText,
                detailRows: detailRows
            )
        }
        
        // Handle linear progression
        if let sets = item.sets, let reps = item.reps {
            return ExercisePreviewInfo(
                setsText: "\(sets)×\(reps)",
                intensityText: "100% TM",
                hasAMRAP: false,
                noteText: nil,
                detailRows: nil
            )
        }
        
        // Handle volume exercises
        if item.type == .volume, let lift = item.lift,
           let weekData = template.lifts?[lift]?["1"] {
            return ExercisePreviewInfo(
                setsText: "\(weekData.sets)×\(weekData.repsPerNormalSet)",
                intensityText: "\(Int(weekData.intensity * 100))% TM",
                hasAMRAP: true,
                noteText: "Week 1",
                detailRows: nil
            )
        }
        
        // Handle accessories with default values
        if let defaultSets = item.defaultSets, let defaultReps = item.defaultReps {
            return ExercisePreviewInfo(
                setsText: "\(defaultSets)×\(defaultReps)",
                intensityText: "User weight",
                hasAMRAP: false,
                noteText: nil,
                detailRows: nil
            )
        }
        
        // Fallback
        return ExercisePreviewInfo(
            setsText: "Variable",
            intensityText: "",
            hasAMRAP: false,
            noteText: nil,
            detailRows: nil
        )
    }
    
    // MARK: - Weekly Volume Calculation
    
    private var weeklyVolume: [VolumeEntry] {
        var volumeByLift: [String: Int] = [:]
        var muscleGroupByLift: [String: MuscleGroup] = [:]
        
        for dayNumber in 1...template.daysPerWeek {
            guard let dayItems = template.days[String(dayNumber)] else { continue }
            
            for item in dayItems where item.type != .tm {
                let liftName = item.lift ?? item.name
                let muscleGroup = MuscleGroup.forLift(liftName)
                muscleGroupByLift[liftName] = muscleGroup
                
                let setCount: Int
                if let setsDetail = item.setsDetail {
                    setCount = setsDetail.count
                } else if let sets = item.sets {
                    setCount = sets
                } else if let defaultSets = item.defaultSets {
                    setCount = defaultSets
                } else if item.type == .volume, let lift = item.lift,
                          let weekData = template.lifts?[lift]?["1"] {
                    setCount = weekData.sets
                } else {
                    setCount = item.type == .accessory ? 3 : 0
                }
                
                volumeByLift[liftName, default: 0] += setCount
            }
        }
        
        return volumeByLift.map { lift, sets in
            VolumeEntry(
                liftName: lift,
                weeklySets: sets,
                muscleGroup: muscleGroupByLift[lift] ?? .other
            )
        }
        .sorted { a, b in
            if a.muscleGroup.sortOrder != b.muscleGroup.sortOrder {
                return a.muscleGroup.sortOrder < b.muscleGroup.sortOrder
            }
            return a.weeklySets > b.weeklySets
        }
    }
    
    private var volumeByMuscleGroup: [(group: MuscleGroup, totalSets: Int, lifts: [VolumeEntry])] {
        let grouped = Dictionary(grouping: weeklyVolume) { $0.muscleGroup }
        
        return grouped.map { group, entries in
            (group: group, totalSets: entries.reduce(0) { $0 + $1.weeklySets }, lifts: entries)
        }
        .sorted { $0.group.sortOrder < $1.group.sortOrder }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSLayout.space6) {
                    // Header
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        SBSAdaptiveStack(alignment: .firstTextBaseline) {
                            Text(template.name)
                                .font(SBSFonts.title())
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)

                            Spacer(minLength: 0)

                            SBSBadge(text: "Custom", systemImage: "square.stack.3d.up")
                        }

                        if !template.templateDescription.isEmpty {
                            Text(template.templateDescription)
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Quick Stats
                    ProgramStatsRow(days: template.daysPerWeek, weeks: template.weeks.count, mainLifts: mainLifts.count)

                    // Progression Section
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        SBSSectionEyebrow("Progression")

                        HStack(spacing: SBSLayout.space3) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(SBSFonts.bodyStrong())
                                .foregroundStyle(Color.inkSecondary)
                                .accessibilityHidden(true)

                            Text(progressionType)
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.ink)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    // Weekly Volume Section
                    if !volumeByMuscleGroup.isEmpty {
                        WeeklyVolumeCard(
                            volumeByGroup: volumeByMuscleGroup,
                            accentColor: accentColor
                        )
                    }

                    // Main Lifts Section
                    if !mainLifts.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            SBSSectionEyebrow("Main Lifts")

                            FlowLayout(spacing: SBSLayout.space2) {
                                ForEach(mainLifts, id: \.self) { lift in
                                    HairlineTag(text: lift, isStrong: true)
                                }
                            }
                        }
                    }

                    // Accessories Section
                    if !accessoryExercises.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            SBSSectionEyebrow("Accessories")

                            FlowLayout(spacing: SBSLayout.space2) {
                                ForEach(accessoryExercises, id: \.self) { exercise in
                                    HairlineTag(text: exercise)
                                }
                            }
                        }
                    }

                    // Weekly Schedule
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        SBSSectionEyebrow("Weekly Schedule") {
                            Text("% = Training Max")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                        }

                        VStack(spacing: SBSLayout.space3) {
                            ForEach(1...template.daysPerWeek, id: \.self) { day in
                                DayPreviewCard(
                                    dayNumber: day,
                                    dayTitle: dayTitle(for: day),
                                    items: dayItems(for: day),
                                    formatSetsReps: formatSetsReps,
                                    formatDetailedSets: detailedPreviewInfo,
                                    accentColor: accentColor
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.orangeText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let startCycle = onStartCycle {
                    VStack {
                        Button {
                            dismiss()
                            startCycle()
                        } label: {
                            HStack(spacing: SBSLayout.space2) {
                                Image(systemName: "play.fill")
                                    .accessibilityHidden(true)
                                SBSButtonTitle("Start Cycle with This Template")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SBSPrimaryButtonStyle())
                    }
                    .padding()
                    .padding(.trailing, SBSLayout.hardShadowOffset)
                    .background(Color.bg)
                }
            }
        }
    }
}

// MARK: - Volume Tracking Types

/// Weekly volume entry for a single lift
struct VolumeEntry: Identifiable {
    let id = UUID()
    let liftName: String
    let weeklySets: Int
    let muscleGroup: MuscleGroup
}

/// Muscle group categorization for volume tracking
enum MuscleGroup: String, CaseIterable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case arms = "Arms"
    case core = "Core"
    case fullBody = "Full Body"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .chest: return "figure.arms.open"
        case .back: return "figure.rowing"
        case .shoulders: return "figure.boxing"
        case .quads: return "figure.walk"
        case .hamstrings: return "figure.run"
        case .glutes: return "figure.strengthtraining.functional"
        case .arms: return "figure.wave"
        case .core: return "figure.core.training"
        case .fullBody: return "figure.strengthtraining.traditional"
        case .other: return "dumbbell"
        }
    }
    
    
    var sortOrder: Int {
        switch self {
        case .chest: return 0
        case .back: return 1
        case .shoulders: return 2
        case .quads: return 3
        case .hamstrings: return 4
        case .glutes: return 5
        case .arms: return 6
        case .core: return 7
        case .fullBody: return 8
        case .other: return 9
        }
    }
    
    /// Categorize a lift into a muscle group
    static func forLift(_ liftName: String) -> MuscleGroup {
        let name = liftName.lowercased()
        
        // Compound movements
        if name.contains("squat") && !name.contains("front") {
            return .quads
        }
        if name.contains("front squat") {
            return .quads
        }
        if name.contains("deadlift") || name.contains("rack pull") {
            return .hamstrings
        }
        if name.contains("bench") || name.contains("press") && !name.contains("ohp") && !name.contains("shoulder") && !name.contains("leg") {
            if name.contains("incline") || name.contains("close") || name.contains("spoto") {
                return .chest
            }
            return .chest
        }
        if name.contains("ohp") || name.contains("overhead") || name.contains("shoulder press") || name.contains("push press") {
            return .shoulders
        }
        
        // Back exercises
        if name.contains("row") || name.contains("pull") && !name.contains("rack") {
            return .back
        }
        if name.contains("lat") || name.contains("chin") {
            return .back
        }
        
        // Shoulder accessories
        if name.contains("lateral") || name.contains("rear delt") || name.contains("face pull") {
            return .shoulders
        }
        
        // Leg accessories
        if name.contains("leg press") || name.contains("extension") || name.contains("lunge") {
            return .quads
        }
        if name.contains("leg curl") || name.contains("rdl") || name.contains("hip thrust") {
            return .hamstrings
        }
        if name.contains("glute") || name.contains("hip") {
            return .glutes
        }
        if name.contains("calf") {
            return .other
        }
        
        // Arms
        if name.contains("curl") || name.contains("bicep") {
            return .arms
        }
        if name.contains("tricep") || name.contains("pushdown") || name.contains("skull") || name.contains("dip") {
            return .arms
        }
        
        // Core
        if name.contains("ab") || name.contains("crunch") || name.contains("plank") || 
           name.contains("leg raise") || name.contains("rollout") || name.contains("wheel") {
            return .core
        }
        
        return .other
    }
}

/// View showing weekly volume breakdown
struct WeeklyVolumeCard: View {
    let volumeByGroup: [(group: MuscleGroup, totalSets: Int, lifts: [VolumeEntry])]
    /// Unused: the chart is ink with labelled bars, never a colour per group
    let accentColor: Color

    @State private var expandedGroups: Set<MuscleGroup> = []

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("Weekly Volume")

            VStack(spacing: 0) {
                // Summary bar chart
                VolumeBarChart(volumeByGroup: volumeByGroup)

                // Detailed breakdown
                ForEach(volumeByGroup, id: \.group) { entry in
                    SBSRowDivider()
                    VolumeGroupRow(
                        group: entry.group,
                        totalSets: entry.totalSets,
                        lifts: entry.lifts,
                        isExpanded: expandedGroups.contains(entry.group),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedGroups.contains(entry.group) {
                                    expandedGroups.remove(entry.group)
                                } else {
                                    expandedGroups.insert(entry.group)
                                }
                            }
                        }
                    )
                }
            }
            .card()
        }
    }
}

/// Bar chart showing volume distribution: ink bars, each labelled with its
/// set count and its group, so no colour key is needed.
struct VolumeBarChart: View {
    let volumeByGroup: [(group: MuscleGroup, totalSets: Int, lifts: [VolumeEntry])]

    @ScaledMetric(relativeTo: .footnote) private var maxBarHeight: CGFloat = 40

    private var maxSets: Int {
        volumeByGroup.map { $0.totalSets }.max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: SBSLayout.space1) {
            ForEach(volumeByGroup, id: \.group) { entry in
                VStack(spacing: 2) {
                    Text("\(entry.totalSets)")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: barWidth, height: barHeight(for: entry.totalSets))

                    Text(entry.group.rawValue)
                        .font(SBSFonts.eyebrow())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(entry.group.rawValue), \(entry.totalSets) sets a week")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SBSLayout.space3)
        .padding(.horizontal, SBSLayout.space4)
    }

    private var barWidth: CGFloat {
        let count = CGFloat(max(volumeByGroup.count, 1))
        return min(24, (UIScreen.main.bounds.width - 80) / count)
    }

    private func barHeight(for sets: Int) -> CGFloat {
        let ratio = CGFloat(sets) / CGFloat(max(maxSets, 1))
        return max(4, ratio * maxBarHeight)
    }
}

/// Row showing a muscle group's volume
struct VolumeGroupRow: View {
    let group: MuscleGroup
    let totalSets: Int
    let lifts: [VolumeEntry]
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space1) {
            // Group header
            Button(action: onToggle) {
                SBSAdaptiveStack {
                    Text(group.rawValue)
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.ink)

                    Spacer(minLength: 0)

                    HStack(spacing: SBSLayout.space2) {
                        Text("\(totalSets) sets/week")
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.ink)

                        if lifts.count > 1 {
                            SBSChevron(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                    }
                }
                .padding(.vertical, SBSLayout.space2)
                .padding(.horizontal, SBSLayout.space4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded lift details
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(lifts) { lift in
                        SBSAdaptiveStack {
                            Text(lift.liftName)
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)

                            Spacer(minLength: 0)

                            Text("\(lift.weeklySets) sets")
                                .font(SBSFonts.numberSmall())
                                .foregroundStyle(Color.inkSecondary)
                        }
                        .padding(.horizontal, SBSLayout.space6)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.bottom, SBSLayout.space2)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    CycleBuilderView(
        appState: AppState(),
        isOnboarding: true,
        onComplete: {},
        onCancel: nil
    )
}

#Preview("New Cycle") {
    CycleBuilderView(
        appState: AppState(),
        isOnboarding: false,
        onComplete: {},
        onCancel: {}
    )
}

