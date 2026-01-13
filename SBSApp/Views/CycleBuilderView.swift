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
        }
    }
    
    @State private var currentStep: BuilderStep = .welcome
    @State private var selectedProgram: String = "stronglifts_5x5_12week"
    @State private var trainingMaxes: [String: Double] = [:]
    @State private var exerciseCustomizations: [Int: [DayItem]] = [:]
    @State private var carryOverTMs: Bool = true
    @State private var animateIn: Bool = false
    @State private var isLoadingProgram: Bool = false
    @State private var lastLoadedProgram: String? = nil
    @State private var showingProgramQuiz: Bool = false
    @State private var showingTemplateBuilder: Bool = false
    
    /// Get the actual configured lifts, taking into account any exercise customizations
    /// This should be used instead of appState.allConfiguredLifts during cycle setup
    private var actualConfiguredLifts: Set<String> {
        var lifts = Set<String>()
        for day in appState.allDays {
            // Use customizations if available, otherwise fall back to appState
            let items = exerciseCustomizations[day] ?? appState.dayItems(for: day)
            for item in items {
                if let lift = item.lift, item.type != .accessory {
                    lifts.insert(lift)
                }
            }
        }
        return lifts
    }
    
    enum BuilderStep: Int, CaseIterable {
        case welcome = 0
        case program = 1
        case exercises = 2
        case trainingMaxes = 3
        case settings = 4
        case summary = 5
        
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .program: return "Program"
            case .exercises: return "Exercises"
            case .trainingMaxes: return "Training Maxes"
            case .settings: return "Settings"
            case .summary: return "Review"
            }
        }
        
        var icon: String {
            switch self {
            case .welcome: return "hand.wave.fill"
            case .program: return "doc.text.fill"
            case .exercises: return "list.bullet.clipboard.fill"
            case .trainingMaxes: return "scalemass.fill"
            case .settings: return "gearshape.fill"
            case .summary: return "checkmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    SBSColors.backgroundFallback,
                    SBSColors.backgroundFallback.opacity(0.95),
                    SBSColors.accentFallback.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator
                if currentStep != .welcome {
                    StepProgressView(currentStep: currentStep)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                // Content
                TabView(selection: $currentStep) {
                    WelcomeStepView(
                        isOnboarding: isOnboarding,
                        onContinue: { goToStep(.program) },
                        onTakeQuiz: { showingProgramQuiz = true }
                    )
                    .tag(BuilderStep.welcome)
                    
                    ProgramSelectionStepView(
                        appState: appState,
                        selectedProgram: $selectedProgram,
                        onBack: { goToStep(.welcome) },
                        onContinue: { loadSelectedProgramAndContinue() },
                        onTakeQuiz: { showingProgramQuiz = true },
                        onBuildTemplate: { showingTemplateBuilder = true }
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
                        configuredLifts: actualConfiguredLifts,
                        onBack: { goToStep(.exercises) },
                        onContinue: { goToStep(.settings) }
                    )
                    .tag(BuilderStep.trainingMaxes)
                    
                    WorkoutSettingsStepView(
                        appState: appState,
                        onBack: { goToStep(.trainingMaxes) },
                        onContinue: { goToStep(.summary) }
                    )
                    .tag(BuilderStep.settings)
                    
                    SummaryStepView(
                        appState: appState,
                        selectedProgram: selectedProgram,
                        trainingMaxes: trainingMaxes,
                        exerciseCustomizations: exerciseCustomizations,
                        isOnboarding: isOnboarding,
                        onBack: { goToStep(.settings) },
                        onComplete: completeCycleSetup
                    )
                    .tag(BuilderStep.summary)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
            
            // Close button (for non-onboarding)
            if !isOnboarding, let onCancel = onCancel {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            onCancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
            
            // Loading overlay when switching programs
            if isLoadingProgram {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: SBSLayout.paddingMedium) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Loading program...")
                        .font(SBSFonts.body())
                        .foregroundStyle(.white)
                }
                .padding(SBSLayout.paddingLarge)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.surfaceFallback.opacity(0.9))
                )
            }
        }
        .opacity(animateIn ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                animateIn = true
            }
            // If an initial program was provided (e.g., from ProgramsView), load it
            // The step was already set to .exercises in init
            if let initial = initialProgram, !isOnboarding {
                Task {
                    do {
                        try await appState.loadProgram(initial)
                        await MainActor.run {
                            lastLoadedProgram = initial
                            isLoadingProgram = false
                        }
                    } catch {
                        await MainActor.run {
                            isLoadingProgram = false
                        }
                    }
                }
            } else if let currentProgram = appState.userData.selectedProgram {
                // Initialize with currently loaded program so we don't reload unnecessarily
                selectedProgram = currentProgram
                lastLoadedProgram = currentProgram
            }
        }
        .fullScreenCover(isPresented: $showingProgramQuiz) {
            ProgramRecommendationQuiz(
                appState: appState,
                selectedProgram: $selectedProgram,
                onDismiss: {
                    showingProgramQuiz = false
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
    }
    
    private func goToStep(_ step: BuilderStep) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = step
        }
    }
    
    /// Load the selected program into appState before going to exercises step
    private func loadSelectedProgramAndContinue() {
        // Check if we need to load a different program
        let needsLoad = lastLoadedProgram != selectedProgram
        
        if needsLoad {
            isLoadingProgram = true
            // Clear exercise customizations when switching programs
            exerciseCustomizations = [:]
            
            Task {
                do {
                    try await appState.loadProgram(selectedProgram)
                    await MainActor.run {
                        lastLoadedProgram = selectedProgram
                        isLoadingProgram = false
                        goToStep(.exercises)
                    }
                } catch {
                    await MainActor.run {
                        isLoadingProgram = false
                        // Still navigate even if load fails - will show current program
                        goToStep(.exercises)
                    }
                }
            }
        } else {
            goToStep(.exercises)
        }
    }
    
    private func initializeTrainingMaxes() {
        // Use actualConfiguredLifts to get lifts from exerciseCustomizations (not appState)
        // This ensures we show the swapped-in lifts, not the original program lifts
        for lift in actualConfiguredLifts {
            if !isOnboarding && carryOverTMs {
                // For new cycles, use current TMs with multiple fallbacks
                let lastWeek = appState.highestLoggedWeek()
                let currentTMs = appState.finalTrainingMaxes(atWeek: lastWeek)
                
                // Priority: calculated TMs > custom initial maxes > universal TMs > program defaults
                if let calculatedTM = currentTMs[lift], calculatedTM > 0 {
                    trainingMaxes[lift] = calculatedTM
                } else if let customMax = appState.userData.customInitialMaxes[lift], customMax > 0 {
                    trainingMaxes[lift] = customMax
                } else if let universalTM = appState.userData.trainingMaxes[lift], universalTM > 0 {
                    trainingMaxes[lift] = universalTM
                } else {
                    trainingMaxes[lift] = appState.initialMax(for: lift)
                }
            } else {
                // For onboarding, use defaults from config
                trainingMaxes[lift] = appState.programData?.initialMaxes[lift] ?? 100
            }
        }
    }
    
    private func completeCycleSetup() {
        if isOnboarding {
            // Apply all customizations
            appState.setInitialMaxes(trainingMaxes)
            if !exerciseCustomizations.isEmpty {
                appState.applyExerciseCustomizations(exerciseCustomizations)
            }
            appState.completeOnboarding()
        } else {
            // Start new cycle with builder settings
            appState.startNewCycleWithBuilder(
                carryOverTMs: false, // We're setting explicit maxes
                newMaxes: trainingMaxes,
                exerciseCustomizations: exerciseCustomizations.isEmpty ? nil : exerciseCustomizations
            )
        }
        onComplete()
    }
}

// MARK: - Step Progress View

struct StepProgressView: View {
    let currentStep: CycleBuilderView.BuilderStep
    
    private let steps: [CycleBuilderView.BuilderStep] = [.program, .exercises, .trainingMaxes, .summary]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(steps, id: \.rawValue) { step in
                VStack(spacing: 4) {
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue 
                              ? SBSColors.accentFallback 
                              : SBSColors.textTertiaryFallback.opacity(0.3))
                        .frame(width: 8, height: 8)
                    
                    Text(step.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(step.rawValue <= currentStep.rawValue 
                                        ? SBSColors.textPrimaryFallback 
                                        : SBSColors.textTertiaryFallback)
                }
                .frame(maxWidth: .infinity)
                
                if step != steps.last {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue 
                              ? SBSColors.accentFallback 
                              : SBSColors.textTertiaryFallback.opacity(0.3))
                        .frame(height: 2)
                        .offset(y: -8)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let isOnboarding: Bool
    let onContinue: () -> Void
    let onTakeQuiz: () -> Void
    
    @State private var animateIcon = false
    @State private var animateContent = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: SBSLayout.paddingLarge) {
                    // Animated icon
                    ZStack {
                        Circle()
                            .fill(SBSColors.accentFallback.opacity(0.1))
                            .frame(width: 120, height: 120)
                            .scaleEffect(animateIcon ? 1.0 : 0.8)
                        
                        Circle()
                            .fill(SBSColors.accentFallback.opacity(0.15))
                            .frame(width: 90, height: 90)
                            .scaleEffect(animateIcon ? 1.0 : 0.9)
                        
                        Image(systemName: isOnboarding ? "figure.strengthtraining.traditional" : "arrow.clockwise.circle.fill")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(SBSColors.accentFallback)
                            .scaleEffect(animateIcon ? 1.0 : 0.5)
                    }
                    .opacity(animateContent ? 1 : 0)
                    .padding(.top, SBSLayout.paddingLarge)
                    
                    VStack(spacing: SBSLayout.paddingSmall) {
                        Text(isOnboarding ? "Welcome to\nTop Set Training" : "New Training Cycle")
                            .font(SBSFonts.largeTitle())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text(isOnboarding 
                             ? "Let's set up your personalized training program. This will only take a minute."
                             : "Ready to start a new 20-week cycle? Let's review your setup.")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, SBSLayout.paddingLarge)
                    }
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                    
                    // Features list
                    VStack(spacing: SBSLayout.paddingSmall) {
                        FeatureRow(icon: "doc.text.fill", title: "Choose your program", description: "Select from available training templates")
                        FeatureRow(icon: "list.bullet.clipboard.fill", title: "Customize exercises", description: "Adjust lifts and accessories for each day")
                        FeatureRow(icon: "scalemass.fill", title: "Set training maxes", description: "Enter your starting weights")
                        
                        if isOnboarding {
                            // Reassuring message
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(SBSColors.success)
                                
                                Text("Don't worry, you can change all of these settings later in the app.")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, SBSLayout.paddingSmall)
                        }
                    }
                    .padding(.horizontal, SBSLayout.paddingLarge)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 30)
                }
                .padding(.bottom, SBSLayout.paddingLarge)
            }
            
            // Action buttons - pinned at bottom
            VStack(spacing: SBSLayout.paddingSmall) {
                // Primary: Get Started
                Button {
                    onContinue()
                } label: {
                    HStack {
                        Text(isOnboarding ? "I Know What I Want" : "Get Started")
                        Image(systemName: "arrow.right")
                    }
                    .font(SBSFonts.button())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingMedium)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.accentFallback)
                    )
                }
                
                // Secondary: Help me choose (especially helpful for onboarding)
                if isOnboarding {
                    Button {
                        onTakeQuiz()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Help Me Choose a Program")
                        }
                        .font(SBSFonts.button())
                        .foregroundStyle(SBSColors.accentFallback)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingMedium)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .strokeBorder(SBSColors.accentFallback, lineWidth: 2)
                        )
                    }
                }
            }
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.bottom, SBSLayout.paddingLarge)
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
        HStack(spacing: SBSLayout.paddingMedium) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(SBSColors.accentFallback)
                .frame(width: 35, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                        .fill(SBSColors.accentFallback.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Text(description)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
        )
    }
}

// MARK: - Program Selection Step

struct ProgramSelectionStepView: View {
    @Bindable var appState: AppState
    @Binding var selectedProgram: String
    let onBack: () -> Void
    let onContinue: () -> Void
    let onTakeQuiz: () -> Void
    let onBuildTemplate: () -> Void
    
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: SBSLayout.paddingSmall) {
                Text("Select Program")
                    .font(SBSFonts.title())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Choose your training template")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            .padding(.top, SBSLayout.paddingMedium)
            .padding(.bottom, SBSLayout.paddingSmall)
            
            // Program selector (new clean design)
            ProgramSelector(
                appState: appState,
                selectedProgram: $selectedProgram,
                onTakeQuiz: onTakeQuiz,
                onBuildTemplate: onBuildTemplate
            )
            
            // Navigation buttons
            NavigationButtons(
                backTitle: "Back",
                continueTitle: isLoading ? "Loading..." : "Continue",
                onBack: onBack,
                onContinue: {
                    isLoading = true
                    Task {
                        do {
                            try await appState.loadProgram(selectedProgram)
                            await MainActor.run {
                                isLoading = false
                                onContinue()
                            }
                        } catch {
                            await MainActor.run {
                                isLoading = false
                            }
                            Logger.error("Failed to load program: \(error)", category: .program)
                        }
                    }
                }
            )
            .disabled(isLoading)
        }
        .onAppear {
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: SBSLayout.paddingSmall) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(SBSColors.accentFallback)
                
                Text("Review Exercises")
                    .font(SBSFonts.title())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Customize the lifts for each training day")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                // Reassuring message
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SBSColors.success)
                    
                    Text("Exercises can be changed in Settings")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                .padding(.top, 4)
            }
            .padding(.top, SBSLayout.paddingLarge)
            .padding(.bottom, SBSLayout.paddingMedium)
            
            // Day selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SBSLayout.paddingSmall) {
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
            .padding(.bottom, SBSLayout.paddingSmall)
            
            // Exercise list
            ScrollView {
                VStack(spacing: SBSLayout.paddingSmall) {
                    let items = currentDayItems
                    
                    // Main lifts (includes tm, volume, structured, and linear types)
                    let mainLifts = items.filter { $0.type == .tm || $0.type == .volume || $0.type == .structured || $0.type == .linear }
                    if !mainLifts.isEmpty {
                        SectionHeader(title: "Main Lifts")
                        
                        ForEach(Array(mainLifts.enumerated()), id: \.offset) { index, item in
                            if let lift = item.lift {
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
                    
                    // Accessories
                    let accessories = items.filter { $0.type == .accessory }
                    SectionHeader(title: "Accessories")
                    
                    ForEach(Array(accessories.enumerated()), id: \.offset) { index, item in
                        let actualIndex = items.firstIndex { $0.type == .accessory && $0.name == item.name } ?? 0
                        ExerciseItemRow(
                            name: item.name,
                            subtitle: "\(item.defaultSets ?? 4) sets × \(item.defaultReps ?? 10) reps",
                            icon: "dumbbell.fill",
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
                    
                    // Add accessory button
                    Button {
                        showingExercisePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Accessory")
                        }
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.accentFallback)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .strokeBorder(SBSColors.accentFallback.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    }
                    .padding(.horizontal)
                    .padding(.top, SBSLayout.paddingSmall)
                }
                .padding(.bottom, SBSLayout.paddingLarge)
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
        var items = currentDayItems
        
        for i in items.indices {
            if items[i].lift == oldLift {
                let type = items[i].type
                let newName = type == .tm ? "\(newLift) TM" : newLift
                items[i] = DayItem(type: type, lift: newLift, name: newName, defaultSets: items[i].defaultSets, defaultReps: items[i].defaultReps)
            }
        }
        
        exerciseCustomizations[selectedDay] = items
    }
    
    private func addAccessory(name: String) {
        var items = currentDayItems
        items.append(DayItem(type: .accessory, lift: nil, name: name, defaultSets: 4, defaultReps: 10))
        exerciseCustomizations[selectedDay] = items
    }
    
    private func removeAccessory(at index: Int) {
        var items = currentDayItems
        guard index < items.count else { return }
        items.remove(at: index)
        exerciseCustomizations[selectedDay] = items
    }
    
    private func updateAccessorySetsReps(at index: Int, sets: Int, reps: Int) {
        var items = currentDayItems
        guard index < items.count, items[index].type == .accessory else { return }
        let item = items[index]
        items[index] = DayItem(type: .accessory, lift: nil, name: item.name, defaultSets: sets, defaultReps: reps)
        exerciseCustomizations[selectedDay] = items
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
            VStack(spacing: SBSLayout.paddingLarge) {
                // Header with exercise name
                VStack(spacing: SBSLayout.paddingSmall) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                    
                    Text(accessoryName)
                        .font(SBSFonts.title3())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, SBSLayout.paddingMedium)
                
                // Steppers
                VStack(spacing: SBSLayout.paddingSmall) {
                    HStack {
                        Text("Sets")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        Spacer()
                        Stepper("\(sets)", value: $sets, in: 1...10)
                            .frame(width: 140)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.surfaceFallback)
                    )
                    
                    HStack {
                        Text("Reps")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        Spacer()
                        Stepper("\(reps)", value: $reps, in: 1...30)
                            .frame(width: 140)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.surfaceFallback)
                    )
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Save button
                Button(action: onSave) {
                    Text("Save")
                        .font(SBSFonts.button())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingMedium)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .fill(SBSColors.accentFallback)
                        )
                }
                .padding(.horizontal, SBSLayout.paddingLarge)
                .padding(.bottom, SBSLayout.paddingLarge)
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
            VStack(spacing: 4) {
                Text(title)
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(isSelected ? .white : SBSColors.textPrimaryFallback)
                Text(subtitle.replacingOccurrences(of: " Day", with: ""))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : SBSColors.textTertiaryFallback)
                    .lineLimit(1)
            }
            .padding(.horizontal, SBSLayout.paddingMedium)
            .padding(.vertical, SBSLayout.paddingSmall)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(isSelected ? SBSColors.accentFallback : SBSColors.surfaceFallback)
            )
        }
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, SBSLayout.paddingMedium)
    }
}

struct ExerciseItemRow: View {
    let name: String
    let subtitle: String
    let icon: String
    let onEdit: (() -> Void)?
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(SBSColors.accentFallback)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                        .fill(SBSColors.accentFallback.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Text(subtitle)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            
            Spacer()
            
            if let onEdit = onEdit {
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                        Text("Edit")
                            .font(SBSFonts.captionBold())
                    }
                    .foregroundStyle(SBSColors.accentFallback)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                            .fill(SBSColors.accentFallback.opacity(0.1))
                    )
                }
            }
            
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(SBSColors.error)
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
}

// MARK: - Training Maxes Step

struct TrainingMaxesStepView: View {
    @Bindable var appState: AppState
    @Binding var trainingMaxes: [String: Double]
    @Binding var carryOverTMs: Bool
    let isOnboarding: Bool
    /// The actual configured lifts (including any swapped-in exercises from cycle builder)
    let configuredLifts: Set<String>
    let onBack: () -> Void
    let onContinue: () -> Void
    
    @FocusState private var focusedLift: String?
    
    private var headerSubtitle: String {
        if isOnboarding {
            return "Enter your starting weights for each lift"
        } else if carryOverTMs && appState.hasLoggedData {
            return "Review your training maxes and adjust if needed"
        } else {
            return "Enter your starting weights for each lift"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: SBSLayout.sectionSpacing) {
                    // Header
                    VStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(SBSColors.accentFallback)
                        
                        Text("Set Training Maxes")
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text(headerSubtitle)
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, SBSLayout.paddingLarge)
                    
                    // Current TMs notice and option to customize (only for new cycles)
                    if !isOnboarding && appState.hasLoggedData {
                        VStack(spacing: SBSLayout.paddingSmall) {
                            // Notice that current TMs are being applied
                            if carryOverTMs {
                                HStack(spacing: SBSLayout.paddingSmall) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(SBSColors.success)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Using Your Current Training Maxes")
                                            .font(SBSFonts.bodyBold())
                                            .foregroundStyle(SBSColors.textPrimaryFallback)
                                        Text("These are pre-filled based on your last cycle. Adjust below if needed.")
                                            .font(SBSFonts.caption())
                                            .foregroundStyle(SBSColors.textSecondaryFallback)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                        .fill(SBSColors.success.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                                .strokeBorder(SBSColors.success.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            
                            // Button to reset or use current TMs
                            Button(action: {
                                carryOverTMs.toggle()
                                if carryOverTMs {
                                    // Populate with current TMs
                                    let lastWeek = appState.highestLoggedWeek()
                                    let currentTMs = appState.finalTrainingMaxes(atWeek: lastWeek)
                                    for (lift, tm) in currentTMs {
                                        trainingMaxes[lift] = tm
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: carryOverTMs ? "arrow.counterclockwise" : "arrow.uturn.backward.circle.fill")
                                        .font(.system(size: 16))
                                    Text(carryOverTMs ? "Reset to Default Values" : "Use Current Training Maxes")
                                        .font(SBSFonts.caption())
                                }
                                .foregroundStyle(SBSColors.accentFallback)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Info box
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Label("What is a Training Max?", systemImage: "info.circle.fill")
                            .font(SBSFonts.captionBold())
                            .foregroundStyle(SBSColors.accentSecondaryFallback)
                        
                        Text("Your training max (TM) should be about 85-90% of your true 1 rep max. This ensures you can hit all prescribed reps while leaving room for progression.")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.accentSecondaryFallback.opacity(0.1))
                    )
                    .padding(.horizontal)
                    
                    // Reassuring message for onboarding
                    if isOnboarding {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(SBSColors.success)
                            
                            Text("Not sure? Just enter your best guess. You can adjust these anytime in Settings.")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Training max inputs
                    VStack(spacing: SBSLayout.paddingSmall) {
                        ForEach(Array(configuredLifts.sorted()), id: \.self) { lift in
                            TMInputRow(
                                liftName: lift,
                                value: Binding(
                                    get: { trainingMaxes[lift] ?? 100 },
                                    set: { trainingMaxes[lift] = $0 }
                                ),
                                useMetric: appState.settings.useMetric,
                                isFocused: focusedLift == lift,
                                onFocus: { focusedLift = lift }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, SBSLayout.paddingXLarge)
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Navigation buttons
            NavigationButtons(
                backTitle: "Back",
                continueTitle: "Continue",
                onBack: onBack,
                onContinue: {
                    focusedLift = nil  // Dismiss keyboard before advancing
                    onContinue()
                }
            )
        }
    }
}

struct TMInputRow: View {
    let liftName: String
    @Binding var value: Double
    let useMetric: Bool
    let isFocused: Bool
    let onFocus: () -> Void
    
    @State private var inputText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(liftName)
                .font(SBSFonts.bodyBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            HStack {
                TextField("Weight", text: $inputText)
                    .keyboardType(.decimalPad)
                    .font(SBSFonts.number())
                    .focused($isTextFieldFocused)
                    .onChange(of: isTextFieldFocused) { _, focused in
                        if focused { onFocus() }
                    }
                    .onChange(of: inputText) { _, newValue in
                        if let parsed = parseInput(newValue) {
                            value = parsed
                        }
                    }
                
                Text(useMetric ? "kg" : "lb")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                // Quick adjust buttons
                HStack(spacing: 8) {
                    Button {
                        adjustValue(by: useMetric ? -2.5 : -5)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(SBSColors.backgroundFallback)
                            )
                    }
                    
                    Button {
                        adjustValue(by: useMetric ? 2.5 : 5)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(SBSColors.backgroundFallback)
                            )
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(SBSColors.surfaceFallback)
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .stroke(isFocused ? SBSColors.accentFallback : Color.clear, lineWidth: 2)
                    )
            )
        }
        .onAppear {
            inputText = formatValue(value)
        }
        .onChange(of: value) { _, newValue in
            // Update inputText when value changes from outside (e.g., carry over toggle)
            let newText = formatValue(newValue)
            if inputText != newText && !isTextFieldFocused {
                inputText = newText
            }
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
        guard let parsed = Double(text) else { return nil }
        return useMetric ? parsed / 0.453592 : parsed
    }
    
    private func adjustValue(by amount: Double) {
        let adjustment = useMetric ? amount / 0.453592 : amount
        value = max(0, value + adjustment)
        inputText = formatValue(value)
    }
}

// MARK: - Workout Settings Step

struct WorkoutSettingsStepView: View {
    @Bindable var appState: AppState
    let onBack: () -> Void
    let onContinue: () -> Void
    
    @State private var showingPaywall = false
    private let storeManager = StoreManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: SBSLayout.sectionSpacing) {
                    // Header
                    VStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(SBSColors.accentFallback)
                        
                        Text("Workout Settings")
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("Configure your workout preferences")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                        
                        // Reassuring message
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 12))
                                .foregroundStyle(SBSColors.success)
                            
                            Text("These can be adjusted anytime in Settings")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, SBSLayout.paddingLarge)
                    
                    // Rest Timer
                    SettingsCard(title: "Rest Timer", icon: "timer") {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Rest Duration")
                                        .font(SBSFonts.body())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                    Text("Time between sets")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                                
                                Spacer()
                                
                                Picker("Rest Timer", selection: $appState.settings.restTimerDuration) {
                                    Text("1 minute").tag(60)
                                    Text("1:30").tag(90)
                                    Text("2 minutes").tag(120)
                                    Text("2:30").tag(150)
                                    Text("3 minutes").tag(180)
                                    Text("4 minutes").tag(240)
                                    Text("5 minutes").tag(300)
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                    
                    // Superset Accessories (Pro Feature)
                    SettingsCard(title: "Superset Accessories", icon: "arrow.triangle.2.circlepath") {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
                            if storeManager.canAccess(.supersets) {
                                Toggle(isOn: $appState.settings.supersetAccessories) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Enable Supersets")
                                            .font(SBSFonts.body())
                                            .foregroundStyle(SBSColors.textPrimaryFallback)
                                        Text("Show accessories during rest periods")
                                            .font(SBSFonts.caption())
                                            .foregroundStyle(SBSColors.textSecondaryFallback)
                                    }
                                }
                            } else {
                                // Non-premium: show disabled state with premium badge
                                Button {
                                    showingPaywall = true
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: SBSLayout.paddingSmall) {
                                                Text("Enable Supersets")
                                                    .font(SBSFonts.body())
                                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                                PremiumBadge(isCompact: true)
                                            }
                                            Text("Show accessories during rest periods. Upgrade to enable.")
                                                .font(SBSFonts.caption())
                                                .foregroundStyle(SBSColors.textSecondaryFallback)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    
                    // Units
                    SettingsCard(title: "Units", icon: "scalemass") {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
                            Toggle(isOn: $appState.settings.useMetric) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Use Metric (kg)")
                                        .font(SBSFonts.body())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                    Text("Display weights in kilograms")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                            }
                            
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Rounding Increment")
                                        .font(SBSFonts.body())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                    Text("Round weights to nearest")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                                
                                Spacer()
                                
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
                                .pickerStyle(.menu)
                            }
                        }
                    }
                    
                    // Plate Calculator (Pro Feature)
                    SettingsCard(title: "Plate Calculator", icon: "circle.grid.2x2") {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
                            if storeManager.canAccess(.plateCalculator) {
                                Toggle(isOn: $appState.settings.showPlateCalculator) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Show Plate Calculator")
                                            .font(SBSFonts.body())
                                            .foregroundStyle(SBSColors.textPrimaryFallback)
                                        Text("Visual plate breakdown during workouts")
                                            .font(SBSFonts.caption())
                                            .foregroundStyle(SBSColors.textSecondaryFallback)
                                    }
                                }
                                
                                if appState.settings.showPlateCalculator {
                                    Divider()
                                    
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Bar Weight")
                                                .font(SBSFonts.body())
                                                .foregroundStyle(SBSColors.textPrimaryFallback)
                                        }
                                        
                                        Spacer()
                                        
                                        Picker("Bar Weight", selection: $appState.settings.barWeight) {
                                            Text("35 lb / 15 kg").tag(35.0)
                                            Text("45 lb / 20 kg").tag(45.0)
                                            Text("55 lb / 25 kg").tag(55.0)
                                        }
                                        .pickerStyle(.menu)
                                    }
                                }
                            } else {
                                // Non-premium: show disabled state with premium badge
                                Button {
                                    showingPaywall = true
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: SBSLayout.paddingSmall) {
                                                Text("Show Plate Calculator")
                                                    .font(SBSFonts.body())
                                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                                PremiumBadge(isCompact: true)
                                            }
                                            Text("Visual plate breakdown during workouts. Upgrade to enable.")
                                                .font(SBSFonts.caption())
                                                .foregroundStyle(SBSColors.textSecondaryFallback)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    
                    // Apple Fitness Integration (Pro Feature)
                    SettingsCard(title: "Apple Fitness", icon: "heart.fill") {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
                            if storeManager.canAccess(.appleFitness) {
                                Toggle(isOn: $appState.settings.healthKitEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Sync to Apple Fitness")
                                            .font(SBSFonts.body())
                                            .foregroundStyle(SBSColors.textPrimaryFallback)
                                        Text("Log workouts with duration, calories & heart rate")
                                            .font(SBSFonts.caption())
                                            .foregroundStyle(SBSColors.textSecondaryFallback)
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
                            } else {
                                // Non-premium: show disabled state with premium badge
                                Button {
                                    showingPaywall = true
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: SBSLayout.paddingSmall) {
                                                Text("Sync to Apple Fitness")
                                                    .font(SBSFonts.body())
                                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                                PremiumBadge(isCompact: true)
                                            }
                                            Text("Log workouts with duration, calories & heart rate. Upgrade to enable.")
                                                .font(SBSFonts.caption())
                                                .foregroundStyle(SBSColors.textSecondaryFallback)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, SBSLayout.paddingXLarge)
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
        .sheet(isPresented: $showingPaywall) {
            PaywallView(triggeredByFeature: .plateCalculator)
        }
    }
}

// MARK: - Settings Card

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            HStack(spacing: SBSLayout.paddingSmall) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SBSColors.accentFallback)
                
                Text(title)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
            }
            
            content
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
        )
    }
}

// MARK: - Summary Step

struct SummaryStepView: View {
    @Bindable var appState: AppState
    let selectedProgram: String
    let trainingMaxes: [String: Double]
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
        return programInfo?.displayName ?? appState.programInfo?.name ?? selectedProgram
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
                VStack(spacing: SBSLayout.sectionSpacing) {
                    // Header with animation
                    VStack(spacing: SBSLayout.paddingMedium) {
                        ZStack {
                            Circle()
                                .fill(SBSColors.success.opacity(0.1))
                                .frame(width: 100, height: 100)
                                .scaleEffect(animateCheckmark ? 1.0 : 0.5)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(SBSColors.success)
                                .scaleEffect(animateCheckmark ? 1.0 : 0.3)
                        }
                        
                        Text(isOnboarding ? "Ready to Begin!" : "Review Your Cycle")
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("Here's a summary of your setup")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .padding(.top, SBSLayout.paddingLarge)
                    
                    // Program summary
                    SummaryCard(title: "Program") {
                        HStack {
                            Image(systemName: isCustomTemplate ? "square.stack.3d.up.fill" : "doc.text.fill")
                                .foregroundStyle(SBSColors.accentFallback)
                            Text(programName)
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            if isCustomTemplate {
                                Text("Custom")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    )
                            }
                            
                            Spacer()
                        }
                        
                        Divider()
                        
                        HStack {
                            SummaryStatItem(value: "\(programWeeks)", label: "Weeks")
                            SummaryStatItem(value: "\(programDays)", label: "Days/Week")
                            SummaryStatItem(value: "\(trainingMaxes.count)", label: "Lifts")
                        }
                    }
                    
                    // Training maxes summary
                    SummaryCard(title: "Starting Training Maxes") {
                        ForEach(Array(trainingMaxes.keys.sorted()), id: \.self) { lift in
                            if let value = trainingMaxes[lift] {
                                HStack {
                                    Text(lift)
                                        .font(SBSFonts.body())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                    Spacer()
                                    Text(value.formattedWeight(useMetric: appState.settings.useMetric))
                                        .font(SBSFonts.number())
                                        .foregroundStyle(SBSColors.accentFallback)
                                }
                                
                                if lift != trainingMaxes.keys.sorted().last {
                                    Divider()
                                }
                            }
                        }
                    }
                    
                    // Customizations note
                    if !exerciseCustomizations.isEmpty {
                        SummaryCard(title: "Customizations") {
                            HStack {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                                Text("You've customized \(exerciseCustomizations.count) day(s)")
                                    .font(SBSFonts.body())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                Spacer()
                            }
                        }
                    }
                    
                    // Tips
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Label("Pro Tips", systemImage: "lightbulb.fill")
                            .font(SBSFonts.captionBold())
                            .foregroundStyle(SBSColors.warning)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            TipItem(text: "Log your rep-outs honestly for accurate progression")
                            TipItem(text: "You can adjust weights mid-workout if needed")
                            TipItem(text: "Review your training maxes in Settings anytime")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.warning.opacity(0.1))
                    )
                    .padding(.horizontal)
                }
                .padding(.bottom, SBSLayout.paddingXLarge)
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Complete button
            VStack(spacing: SBSLayout.paddingMedium) {
                Button {
                    onComplete()
                } label: {
                    HStack {
                        Text(isOnboarding ? "Start Training" : "Start New Cycle")
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .font(SBSFonts.button())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingMedium)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.success)
                    )
                }
                
                Button {
                    onBack()
                } label: {
                    Text("Go Back")
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
            }
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.vertical, SBSLayout.paddingMedium)
            .background(SBSColors.backgroundFallback)
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
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            Text(title)
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            VStack(spacing: SBSLayout.paddingSmall) {
                content
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
        )
        .padding(.horizontal)
    }
}

struct SummaryStatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(SBSFonts.title2())
                .foregroundStyle(SBSColors.accentFallback)
            Text(label)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TipItem: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(SBSColors.success)
                .padding(.top, 2)
            
            Text(text)
                .font(SBSFonts.body())
                .foregroundStyle(SBSColors.textSecondaryFallback)
        }
    }
}

// MARK: - Navigation Buttons

struct NavigationButtons: View {
    let backTitle: String
    let continueTitle: String
    let onBack: () -> Void
    let onContinue: () -> Void
    
    var body: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            Button {
                onBack()
            } label: {
                HStack {
                    Image(systemName: "arrow.left")
                    Text(backTitle)
                }
                .font(SBSFonts.button())
                .foregroundStyle(SBSColors.textSecondaryFallback)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SBSLayout.paddingMedium)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.surfaceFallback)
                )
            }
            
            Button {
                onContinue()
            } label: {
                HStack {
                    Text(continueTitle)
                    Image(systemName: "arrow.right")
                }
                .font(SBSFonts.button())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SBSLayout.paddingMedium)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.accentFallback)
                )
            }
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
        .padding(.vertical, SBSLayout.paddingMedium)
        .background(SBSColors.backgroundFallback)
    }
}

// MARK: - Program Detail View

struct ProgramDetailView: View {
    let program: AppState.AvailableProgramInfo
    var programData: ProgramData? = nil  // Optional initial data (used when already loaded)
    let familyColor: Color
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
                VStack(alignment: .leading, spacing: SBSLayout.paddingLarge) {
                    // Header
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        HStack {
                            Text(program.displayName)
                                .font(SBSFonts.largeTitle())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Spacer()
                            
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(level.color)
                                    .frame(width: 8, height: 8)
                                Text(level.rawValue)
                                    .font(SBSFonts.captionBold())
                                    .foregroundStyle(level.color)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(level.color.opacity(0.15))
                            )
                        }
                        
                        Text(program.programDescription)
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    // Quick Stats
                    HStack(spacing: SBSLayout.paddingMedium) {
                        StatCard(
                            icon: "calendar",
                            value: "\(program.days)",
                            label: "Days/Week",
                            color: familyColor
                        )
                        StatCard(
                            icon: "clock",
                            value: "\(program.weeks)",
                            label: "Weeks",
                            color: familyColor
                        )
                        StatCard(
                            icon: "dumbbell",
                            value: "\(mainLifts.count)",
                            label: "Main Lifts",
                            color: familyColor
                        )
                    }
                    
                    // Progression Section
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Label("Progression", systemImage: "arrow.up.right")
                            .font(SBSFonts.title3())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 16))
                                .foregroundStyle(familyColor)
                            
                            Text(progressionType)
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                                .fill(SBSColors.surfaceFallback)
                        )
                    }
                    
                    // Weekly Volume Section
                    if !volumeByMuscleGroup.isEmpty {
                        WeeklyVolumeCard(
                            volumeByGroup: volumeByMuscleGroup,
                            accentColor: familyColor
                        )
                    }
                    
                    // Main Lifts Section
                    if !mainLifts.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                            Label("Main Lifts", systemImage: "figure.strengthtraining.traditional")
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(mainLifts, id: \.self) { lift in
                                    Text(lift)
                                        .font(SBSFonts.captionBold())
                                        .foregroundStyle(familyColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(familyColor.opacity(0.15))
                                        )
                                }
                            }
                        }
                    }
                    
                    // Accessories Section
                    if !accessoryExercises.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                            Label("Accessories", systemImage: "plus.circle")
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(accessoryExercises, id: \.self) { exercise in
                                    Text(exercise)
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .strokeBorder(SBSColors.textTertiaryFallback.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                    
                    // Weekly Schedule
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        HStack {
                            Label("Weekly Schedule", systemImage: "calendar.badge.clock")
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Spacer()
                            
                            // Note about percentages
                            Text("% = Training Max")
                                .font(.system(size: 10))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                        
                        VStack(spacing: SBSLayout.paddingSmall) {
                            ForEach(1...program.days, id: \.self) { day in
                                DayPreviewCard(
                                    dayNumber: day,
                                    dayTitle: dayTitle(for: day),
                                    items: dayItems(for: day),
                                    formatSetsReps: formatSetsReps,
                                    formatDetailedSets: detailedPreviewInfo,
                                    accentColor: familyColor
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SBSColors.backgroundFallback)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(familyColor)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let startCycle = onStartCycle {
                    VStack {
                        Button {
                            dismiss()
                            startCycle()
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start Cycle with This Program")
                            }
                            .font(SBSFonts.button())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.paddingMedium)
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                    .fill(familyColor)
                            )
                        }
                    }
                    .padding()
                    .background(SBSColors.backgroundFallback)
                }
            }
            .overlay {
                if isLoading && effectiveProgramData == nil {
                    VStack(spacing: SBSLayout.paddingMedium) {
                        ProgressView()
                            .tint(familyColor)
                        Text("Loading program...")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SBSColors.backgroundFallback)
                }
            }
            .task {
                await loadProgramData()
            }
        }
    }
}

// MARK: - Supporting Views for Program Detail

struct StatCard: View {
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
        .padding(.vertical, SBSLayout.paddingMedium)
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                .fill(SBSColors.surfaceFallback)
        )
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
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            // Header with day number and title
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day \(dayNumber)")
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    if let title = dayTitle {
                        Text(title)
                            .font(SBSFonts.caption())
                            .foregroundStyle(accentColor)
                    }
                }
                
                Spacer()
                
                Text("\(mainExercises.count) main • \(accessories.count) acc")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            
            Divider()
                .opacity(0.3)
            
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
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(SBSColors.textTertiaryFallback.opacity(0.6))
                        .padding(.top, 2)
                    
                    Text(accessories.map { $0.name }.joined(separator: ", "))
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                .fill(SBSColors.surfaceFallback)
        )
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
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.lift ?? item.name)
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    if let info = info {
                        HStack(spacing: 6) {
                            Text(info.setsText)
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                            
                            Text("@")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            
                            Text(info.intensityText)
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(accentColor)
                            
                            if info.hasAMRAP {
                                Text("AMRAP")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule()
                                            .fill(accentColor.opacity(0.8))
                                    )
                            }
                            
                            if let note = info.noteText {
                                Text(note)
                                    .font(.system(size: 9))
                                    .foregroundStyle(SBSColors.textTertiaryFallback)
                                    .italic()
                            }
                        }
                    } else {
                        Text(compactInfo)
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
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
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Expanded set details (for structured exercises)
            if isExpanded, let info = info, let details = info.detailRows {
                SetPreviewGrid(rows: details, accentColor: accentColor)
                    .padding(.leading, 12)
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
                VStack(spacing: 1) {
                    Text(row.reps)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    Text("\(row.intensity)%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.8))
                }
                .frame(minWidth: 32)
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SBSColors.backgroundFallback)
                )
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
    
    private let accentColor: Color = SBSColors.accentFallback
    
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
                VStack(alignment: .leading, spacing: SBSLayout.paddingLarge) {
                    // Header
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        HStack {
                            Text(template.name)
                                .font(SBSFonts.largeTitle())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Spacer()
                            
                            HStack(spacing: 2) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 10))
                                Text("CUSTOM")
                                    .font(SBSFonts.captionBold())
                            }
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(accentColor.opacity(0.15))
                            )
                        }
                        
                        if !template.templateDescription.isEmpty {
                            Text(template.templateDescription)
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                    }
                    
                    // Quick Stats
                    HStack(spacing: SBSLayout.paddingMedium) {
                        StatCard(
                            icon: "calendar",
                            value: "\(template.daysPerWeek)",
                            label: "Days/Week",
                            color: accentColor
                        )
                        StatCard(
                            icon: "clock",
                            value: "\(template.weeks.count)",
                            label: "Weeks",
                            color: accentColor
                        )
                        StatCard(
                            icon: "dumbbell",
                            value: "\(mainLifts.count)",
                            label: "Main Lifts",
                            color: accentColor
                        )
                    }
                    
                    // Progression Section
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Label("Progression", systemImage: "arrow.up.right")
                            .font(SBSFonts.title3())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 16))
                                .foregroundStyle(accentColor)
                            
                            Text(progressionType)
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                                .fill(SBSColors.surfaceFallback)
                        )
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
                        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                            Label("Main Lifts", systemImage: "figure.strengthtraining.traditional")
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(mainLifts, id: \.self) { lift in
                                    Text(lift)
                                        .font(SBSFonts.captionBold())
                                        .foregroundStyle(accentColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(accentColor.opacity(0.15))
                                        )
                                }
                            }
                        }
                    }
                    
                    // Accessories Section
                    if !accessoryExercises.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                            Label("Accessories", systemImage: "plus.circle")
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(accessoryExercises, id: \.self) { exercise in
                                    Text(exercise)
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .strokeBorder(SBSColors.textTertiaryFallback.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                    
                    // Weekly Schedule
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        HStack {
                            Label("Weekly Schedule", systemImage: "calendar.badge.clock")
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Spacer()
                            
                            Text("% = Training Max")
                                .font(.system(size: 10))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                        
                        VStack(spacing: SBSLayout.paddingSmall) {
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
            .background(SBSColors.backgroundFallback)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(accentColor)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let startCycle = onStartCycle {
                    VStack {
                        Button {
                            dismiss()
                            startCycle()
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start Cycle with This Template")
                            }
                            .font(SBSFonts.button())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.paddingMedium)
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                    .fill(accentColor)
                            )
                        }
                    }
                    .padding()
                    .background(SBSColors.backgroundFallback)
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
    
    var color: Color {
        switch self {
        case .chest: return .red
        case .back: return .blue
        case .shoulders: return .orange
        case .quads: return .green
        case .hamstrings: return .cyan
        case .glutes: return .purple
        case .arms: return .pink
        case .core: return .yellow
        case .fullBody: return .indigo
        case .other: return .gray
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
    let accentColor: Color
    
    @State private var expandedGroups: Set<MuscleGroup> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Label("Weekly Volume", systemImage: "chart.bar.fill")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            // Summary bar chart
            VolumeBarChart(volumeByGroup: volumeByGroup)
            
            // Detailed breakdown
            VStack(spacing: 6) {
                ForEach(volumeByGroup, id: \.group) { entry in
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
        }
    }
}

/// Bar chart showing volume distribution
struct VolumeBarChart: View {
    let volumeByGroup: [(group: MuscleGroup, totalSets: Int, lifts: [VolumeEntry])]
    
    private var maxSets: Int {
        volumeByGroup.map { $0.totalSets }.max() ?? 1
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(volumeByGroup, id: \.group) { entry in
                VStack(spacing: 2) {
                    // Bar
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.group.color)
                        .frame(width: barWidth, height: barHeight(for: entry.totalSets))
                    
                    // Label
                    Text("\(entry.totalSets)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
            }
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .padding(.vertical, SBSLayout.paddingSmall)
        .padding(.horizontal, SBSLayout.paddingMedium)
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                .fill(SBSColors.surfaceFallback)
        )
    }
    
    private var barWidth: CGFloat {
        let count = CGFloat(max(volumeByGroup.count, 1))
        return min(24, (UIScreen.main.bounds.width - 80) / count)
    }
    
    private func barHeight(for sets: Int) -> CGFloat {
        let ratio = CGFloat(sets) / CGFloat(max(maxSets, 1))
        return max(4, ratio * 40)
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
        VStack(alignment: .leading, spacing: 4) {
            // Group header
            Button(action: onToggle) {
                HStack {
                    Circle()
                        .fill(group.color)
                        .frame(width: 8, height: 8)
                    
                    Text(group.rawValue)
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Spacer()
                    
                    Text("\(totalSets) sets/week")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(group.color)
                    
                    if lifts.count > 1 {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(group.color.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            
            // Expanded lift details
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(lifts) { lift in
                        HStack {
                            Text(lift.liftName)
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                            
                            Spacer()
                            
                            Text("\(lift.weeklySets) sets")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 2)
                    }
                }
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

