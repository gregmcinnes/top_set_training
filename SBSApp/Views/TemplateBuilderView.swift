import SwiftUI

// MARK: - Template Builder View

struct TemplateBuilderView: View {
    @Bindable var appState: AppState
    let existingTemplate: CustomTemplate?
    let onSave: (CustomTemplate) -> Void
    let onCancel: () -> Void
    
    @State private var currentStep: TemplateBuilderStep = .basics
    @State private var template: CustomTemplate
    @State private var animateIn: Bool = false
    
    init(
        appState: AppState,
        existingTemplate: CustomTemplate?,
        onSave: @escaping (CustomTemplate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.appState = appState
        self.existingTemplate = existingTemplate
        self.onSave = onSave
        self.onCancel = onCancel
        self._template = State(initialValue: existingTemplate ?? CustomTemplate())
    }
    
    enum TemplateBuilderStep: Int, CaseIterable {
        case basics = 0
        case days = 1
        case exercises = 2
        case review = 3
        
        var title: String {
            switch self {
            case .basics: return "Basics"
            case .days: return "Days"
            case .exercises: return "Exercises"
            case .review: return "Review"
            }
        }
        
        var icon: String {
            switch self {
            case .basics: return "doc.text.fill"
            case .days: return "calendar"
            case .exercises: return "list.bullet.clipboard.fill"
            case .review: return "checkmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background
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
                TemplateStepProgressView(currentStep: currentStep)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // Content
                TabView(selection: $currentStep) {
                    BasicsStepView(
                        template: $template,
                        onContinue: { goToStep(.days) }
                    )
                    .tag(TemplateBuilderStep.basics)
                    
                    DaysStepView(
                        template: $template,
                        onBack: { goToStep(.basics) },
                        onContinue: { goToStep(.exercises) }
                    )
                    .tag(TemplateBuilderStep.days)
                    
                    ExercisesStepView(
                        template: $template,
                        onBack: { goToStep(.days) },
                        onContinue: { goToStep(.review) }
                    )
                    .tag(TemplateBuilderStep.exercises)
                    
                    ReviewStepView(
                        template: template,
                        isEditing: existingTemplate != nil,
                        onBack: { goToStep(.exercises) },
                        onSave: {
                            onSave(template)
                        }
                    )
                    .tag(TemplateBuilderStep.review)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
            
            // Close button
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
        .opacity(animateIn ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                animateIn = true
            }
        }
    }
    
    private func goToStep(_ step: TemplateBuilderStep) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = step
        }
    }
}

// MARK: - Step Progress View

struct TemplateStepProgressView: View {
    let currentStep: TemplateBuilderView.TemplateBuilderStep
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(TemplateBuilderView.TemplateBuilderStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue ? SBSColors.accentFallback : SBSColors.surfaceFallback)
                            .frame(width: 28, height: 28)
                        
                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(step.rawValue <= currentStep.rawValue ? .white : SBSColors.textTertiaryFallback)
                        }
                    }
                    
                    if step != TemplateBuilderView.TemplateBuilderStep.allCases.last {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? SBSColors.accentFallback : SBSColors.surfaceFallback)
                            .frame(height: 2)
                    }
                }
            }
        }
        .padding(.vertical, SBSLayout.paddingSmall)
    }
}

// MARK: - Step 1: Basics

struct BasicsStepView: View {
    @Binding var template: CustomTemplate
    let onContinue: () -> Void
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, description
    }
    
    private var canContinue: Bool {
        !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SBSLayout.sectionSpacing) {
                // Header
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    Text("Template Basics")
                        .font(SBSFonts.title())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Give your template a name and configure the basic structure.")
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .padding(.top, SBSLayout.paddingLarge)
                
                // Name
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    Text("Template Name")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    TextField("e.g., My Upper/Lower Split", text: $template.name)
                        .font(SBSFonts.body())
                        .textFieldStyle(.plain)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                                .fill(SBSColors.surfaceFallback)
                        )
                        .focused($focusedField, equals: .name)
                }
                
                // Description
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    Text("Description (Optional)")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    TextField("Describe your program...", text: $template.templateDescription, axis: .vertical)
                        .font(SBSFonts.body())
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                                .fill(SBSColors.surfaceFallback)
                        )
                        .focused($focusedField, equals: .description)
                }
                
                // Mode Selection
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    Text("Template Mode")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    ForEach(TemplateMode.allCases, id: \.self) { mode in
                        Button {
                            template.mode = mode
                        } label: {
                            HStack(spacing: SBSLayout.paddingMedium) {
                                Image(systemName: template.mode == mode ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(template.mode == mode ? SBSColors.accentFallback : SBSColors.textTertiaryFallback)
                                    .font(.title2)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .font(SBSFonts.bodyBold())
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                    
                                    Text(mode.description)
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                        .multilineTextAlignment(.leading)
                                }
                                
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                    .fill(template.mode == mode ? SBSColors.accentFallback.opacity(0.1) : SBSColors.surfaceFallback)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                    .strokeBorder(template.mode == mode ? SBSColors.accentFallback : Color.clear, lineWidth: 2)
                            )
                        }
                    }
                }
                
                // Days per week
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    Text("Days per Week")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    HStack(spacing: SBSLayout.paddingSmall) {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                template.daysPerWeek = day
                                // Trim or add days as needed
                                ensureDayStructure()
                            } label: {
                                Text("\(day)")
                                    .font(SBSFonts.bodyBold())
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle()
                                            .fill(template.daysPerWeek == day ? SBSColors.accentFallback : SBSColors.surfaceFallback)
                                    )
                                    .foregroundStyle(template.daysPerWeek == day ? .white : SBSColors.textPrimaryFallback)
                            }
                        }
                    }
                }
                
                // Number of weeks
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    Text("Program Length")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    HStack(spacing: SBSLayout.paddingMedium) {
                        ForEach([4, 8, 12, 16, 20], id: \.self) { weekCount in
                            Button {
                                template.weeks = Array(1...weekCount)
                            } label: {
                                Text("\(weekCount)w")
                                    .font(SBSFonts.captionBold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(template.weeks.count == weekCount ? SBSColors.accentFallback : SBSColors.surfaceFallback)
                                    )
                                    .foregroundStyle(template.weeks.count == weekCount ? .white : SBSColors.textPrimaryFallback)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                Button {
                    ensureDayStructure()
                    onContinue()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
                .disabled(!canContinue)
            }
            .padding()
            .background(SBSColors.backgroundFallback)
        }
    }
    
    private func ensureDayStructure() {
        // Ensure we have the right number of days
        for day in 1...template.daysPerWeek {
            let key = String(day)
            if template.days[key] == nil {
                template.days[key] = []
            }
        }
        // Remove extra days
        for key in template.days.keys {
            if let dayNum = Int(key), dayNum > template.daysPerWeek {
                template.days.removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Step 2: Days Configuration

struct DaysStepView: View {
    @Binding var template: CustomTemplate
    let onBack: () -> Void
    let onContinue: () -> Void
    
    @State private var selectedDay: Int = 1
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                Text("Configure Days")
                    .font(SBSFonts.title())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Select each day to add exercises.")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            // Day selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SBSLayout.paddingSmall) {
                    ForEach(1...template.daysPerWeek, id: \.self) { day in
                        TemplateDayTab(
                            day: day,
                            isSelected: selectedDay == day,
                            exerciseCount: template.days[String(day)]?.count ?? 0,
                            onTap: { selectedDay = day }
                        )
                    }
                }
                .padding(.horizontal)
            }
            
            Divider()
                .padding(.top, SBSLayout.paddingSmall)
            
            // Exercise list for selected day
            DayExerciseListView(
                template: $template,
                day: selectedDay
            )
            
            // Navigation
            HStack(spacing: SBSLayout.paddingMedium) {
                Button {
                    onBack()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSSecondaryButtonStyle())
                
                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
                .disabled(!hasAtLeastOneExercise)
            }
            .padding()
            .background(SBSColors.backgroundFallback)
        }
    }
    
    private var hasAtLeastOneExercise: Bool {
        for day in 1...template.daysPerWeek {
            if let exercises = template.days[String(day)], !exercises.isEmpty {
                return true
            }
        }
        return false
    }
}

struct TemplateDayTab: View {
    let day: Int
    let isSelected: Bool
    let exerciseCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("Day \(day)")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(isSelected ? .white : SBSColors.textPrimaryFallback)
                
                Text("\(exerciseCount) ex")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : SBSColors.textTertiaryFallback)
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

struct DayExerciseListView: View {
    @Binding var template: CustomTemplate
    let day: Int
    
    @State private var showingExercisePicker = false
    @State private var editingExerciseIndex: Int?
    
    private var dayKey: String { String(day) }
    
    private var exercises: [DayItem] {
        template.days[dayKey] ?? []
    }
    
    var body: some View {
        List {
            if exercises.isEmpty {
                Section {
                    VStack(spacing: SBSLayout.paddingMedium) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 40))
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                        
                        Text("No exercises yet")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                        
                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add Exercise", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(SBSSecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.paddingLarge)
                }
            } else {
                Section {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { index, item in
                        ExerciseRowView(
                            item: item,
                            mode: template.mode,
                            onEdit: {
                                editingExerciseIndex = index
                            },
                            onDelete: {
                                deleteExercise(at: index)
                            }
                        )
                    }
                    .onMove { from, to in
                        moveExercise(from: from, to: to)
                    }
                    
                    Button {
                        showingExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Day \(day) Exercises")
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingExercisePicker) {
            TemplateExercisePickerSheet(
                mode: template.mode,
                onSelect: { item in
                    addExercise(item)
                    showingExercisePicker = false
                },
                onCancel: {
                    showingExercisePicker = false
                }
            )
        }
        .sheet(item: $editingExerciseIndex) { index in
            if index < exercises.count {
                ExerciseEditorSheet(
                    item: exercises[index],
                    mode: template.mode,
                    onSave: { updatedItem in
                        updateExercise(at: index, with: updatedItem)
                        editingExerciseIndex = nil
                    },
                    onDelete: {
                        deleteExercise(at: index)
                        editingExerciseIndex = nil
                    },
                    onCancel: {
                        editingExerciseIndex = nil
                    }
                )
            }
        }
    }
    
    private func addExercise(_ item: DayItem) {
        var exercises = template.days[dayKey] ?? []
        exercises.append(item)
        template.days[dayKey] = exercises
    }
    
    private func updateExercise(at index: Int, with item: DayItem) {
        var exercises = template.days[dayKey] ?? []
        guard index < exercises.count else { return }
        exercises[index] = item
        template.days[dayKey] = exercises
    }
    
    private func deleteExercise(at index: Int) {
        var exercises = template.days[dayKey] ?? []
        guard index < exercises.count else { return }
        exercises.remove(at: index)
        template.days[dayKey] = exercises
    }
    
    private func moveExercise(from: IndexSet, to: Int) {
        var exercises = template.days[dayKey] ?? []
        exercises.move(fromOffsets: from, toOffset: to)
        template.days[dayKey] = exercises
    }
}

// Make Int Identifiable for sheet binding
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct ExerciseRowView: View {
    let item: DayItem
    let mode: TemplateMode
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private var typeLabel: String {
        switch item.type {
        case .tm: return "TM Display"
        case .volume: return "Autoregulated"
        case .accessory: return "Accessory"
        case .structured: return "Autoregulated"
        case .linear: return "Linear"
        }
    }
    
    private var typeColor: Color {
        switch item.type {
        case .tm: return SBSColors.accentSecondaryFallback
        case .volume: return SBSColors.accentFallback
        case .accessory: return SBSColors.textSecondaryFallback
        case .structured: return SBSColors.accentFallback
        case .linear: return .green
        }
    }
    
    var body: some View {
        Button {
            onEdit()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Text(typeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(typeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(typeColor.opacity(0.15))
                            )
                        
                        if item.type == .accessory {
                            Text("\(item.defaultSets ?? 4)x\(item.defaultReps ?? 10)")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        } else if item.type == .linear {
                            Text("\(item.sets ?? 5)x\(item.reps ?? 5)")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        } else if let setsDetail = item.setsDetail {
                            Text("\(setsDetail.count) sets")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Exercise Picker Sheet

struct TemplateExercisePickerSheet: View {
    let mode: TemplateMode
    let onSelect: (DayItem) -> Void
    let onCancel: () -> Void
    
    @State private var searchText = ""
    @State private var selectedExercise: Exercise?
    @State private var selectedType: DayItem.ItemType = .accessory
    @State private var sets: Int = 4
    @State private var reps: Int = 10
    @State private var customSetsDetail: [SetDetail] = []
    @State private var showingTypeInfo: DayItem.ItemType?
    @State private var editingSetIndex: Int?
    // Progression set - only this set's performance affects TM
    @State private var progressionSetIndex: Int = 0
    @State private var expandedBodyParts: Set<BodyPart> = []
    
    private let library = ExerciseLibrary.shared
    
    private var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return library.exercises
        }
        return library.search(searchText)
    }
    
    private var exercisesByBodyPart: [BodyPart: [Exercise]] {
        Dictionary(grouping: filteredExercises) { $0.bodyPart }
    }
    
    private var sortedBodyParts: [BodyPart] {
        BodyPart.allCases.filter { exercisesByBodyPart[$0] != nil && !(exercisesByBodyPart[$0]?.isEmpty ?? true) }
    }
    
    private var availableTypes: [DayItem.ItemType] {
        if mode == .simple {
            return [.accessory]
        } else {
            // Only 3 progression schemes: Accessory (no auto), Linear, Autoregulated
            return [.accessory, .linear, .structured]
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selectedExercise == nil {
                    // Exercise selection with styled sections
                    VStack(spacing: 0) {
                        // Search bar
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            
                            TextField("Search exercises...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(SBSFonts.body())
                            
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(SBSColors.textTertiaryFallback)
                                }
                            }
                        }
                        .padding()
                        .background(SBSColors.surfaceFallback)
                        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
                        .padding(.horizontal)
                        .padding(.top, SBSLayout.paddingSmall)
                        
                        if !filteredExercises.isEmpty {
                            ScrollView {
                                LazyVStack(spacing: SBSLayout.paddingSmall) {
                                    ForEach(sortedBodyParts) { bodyPart in
                                        BodyPartSection(
                                            bodyPart: bodyPart,
                                            exercises: exercisesByBodyPart[bodyPart] ?? [],
                                            currentExercise: nil,
                                            isExpanded: isExpanded(bodyPart),
                                            onToggle: { toggleBodyPart(bodyPart) },
                                            onSelect: { exerciseName in
                                                // Look up the exercise by name
                                                if let exercise = library.exercises.first(where: { $0.name == exerciseName }) {
                                                    selectExercise(exercise)
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, SBSLayout.paddingMedium)
                            }
                            .scrollDismissesKeyboard(.interactively)
                        } else {
                            ContentUnavailableView(
                                "No Exercises Found",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different search term")
                            )
                        }
                    }
                    .sbsBackground()
                } else {
                    // Configuration
                    exerciseConfigView
                }
            }
            .navigationTitle(selectedExercise == nil ? "Add Exercise" : "Configure Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selectedExercise == nil ? "Cancel" : "Back") {
                        if selectedExercise == nil {
                            onCancel()
                        } else {
                            selectedExercise = nil
                        }
                    }
                }
                
                if selectedExercise != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") {
                            addExercise()
                        }
                    }
                }
            }
            .onAppear {
                // Auto-expand the first body part
                if !sortedBodyParts.isEmpty {
                    expandedBodyParts.insert(sortedBodyParts[0])
                }
            }
        }
    }
    
    private func isExpanded(_ bodyPart: BodyPart) -> Bool {
        if !searchText.isEmpty {
            return true  // Show all expanded when searching
        }
        return expandedBodyParts.contains(bodyPart)
    }
    
    private func toggleBodyPart(_ bodyPart: BodyPart) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedBodyParts.contains(bodyPart) {
                expandedBodyParts.remove(bodyPart)
            } else {
                expandedBodyParts.insert(bodyPart)
            }
        }
    }
    
    private func selectExercise(_ exercise: Exercise) {
        selectedExercise = exercise
        // Set default type based on exercise
        if exercise.category == .mainLift && mode == .advanced {
            selectedType = .linear
        } else {
            selectedType = .accessory
        }
        // Initialize default sets
        if customSetsDetail.isEmpty {
            switch selectedType {
            case .accessory:
                customSetsDetail = [
                    SetDetail(intensity: 0.70, reps: 10, isAMRAP: false),
                    SetDetail(intensity: 0.70, reps: 10, isAMRAP: false),
                    SetDetail(intensity: 0.70, reps: 10, isAMRAP: false)
                ]
            case .linear:
                customSetsDetail = [
                    SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                    SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                    SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                    SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                    SetDetail(intensity: 0.80, reps: 5, isAMRAP: false)
                ]
            default:
                customSetsDetail = defaultSets
            }
        }
    }
    
    private var exerciseConfigView: some View {
        List {
            Section {
                HStack {
                    Text("Exercise")
                    Spacer()
                    Text(selectedExercise?.name ?? "")
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
            }
            
            if mode == .advanced {
                Section {
                    ForEach(availableTypes, id: \.self) { type in
                        Button {
                            selectedType = type
                            // Initialize set designer with sensible defaults
                            if customSetsDetail.isEmpty {
                                switch type {
                                case .accessory:
                                    // 3x10 at 70% for accessories
                                    customSetsDetail = [
                                        SetDetail(intensity: 0.70, reps: 10, isAMRAP: false),
                                        SetDetail(intensity: 0.70, reps: 10, isAMRAP: false),
                                        SetDetail(intensity: 0.70, reps: 10, isAMRAP: false)
                                    ]
                                case .linear:
                                    // 5x5 at 80% for linear
                                    customSetsDetail = [
                                        SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                                        SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                                        SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                                        SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                                        SetDetail(intensity: 0.80, reps: 5, isAMRAP: false)
                                    ]
                                case .structured:
                                    // Ramping sets for autoregulated
                                    customSetsDetail = defaultSets
                                default:
                                    customSetsDetail = defaultSets
                                }
                            }
                            // Set progression index for autoregulated
                            if type == .structured {
                                if let lastAmrapIndex = customSetsDetail.lastIndex(where: { $0.isAMRAP }) {
                                    progressionSetIndex = lastAmrapIndex
                                } else {
                                    progressionSetIndex = customSetsDetail.count - 1
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(typeName(for: type))
                                        .foregroundStyle(SBSColors.textPrimaryFallback)
                                    Text(typeShortDescription(for: type))
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textTertiaryFallback)
                                }
                                
                                Spacer()
                                
                                // Info button
                                Button {
                                    showingTypeInfo = type
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                                }
                                .buttonStyle(.borderless)
                                
                                if selectedType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(SBSColors.accentFallback)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("Exercise Type")
                } footer: {
                    Text("Tap ⓘ for detailed information about each type.")
                }
            }
            
            // Set Designer - shown for ALL progression types
            Section {
                ForEach(Array(customSetsDetail.enumerated()), id: \.offset) { index, setDetail in
                    SetDesignerRow(
                        setNumber: index + 1,
                        setDetail: setDetail,
                        isOnlySet: customSetsDetail.count == 1,
                        isProgressionSet: index == progressionSetIndex,
                        showProgressionOption: selectedType == .structured,
                        onUpdate: { updated in
                            customSetsDetail[index] = updated
                        },
                        onDelete: {
                            customSetsDetail.remove(at: index)
                            if progressionSetIndex >= customSetsDetail.count {
                                progressionSetIndex = max(0, customSetsDetail.count - 1)
                            }
                        },
                        onSetAsProgression: {
                            progressionSetIndex = index
                        }
                    )
                }
                
                Button {
                    let lastIntensity = customSetsDetail.last?.intensity ?? 0.75
                    let lastReps = customSetsDetail.last?.reps ?? 5
                    customSetsDetail.append(SetDetail(
                        intensity: min(lastIntensity + 0.05, 1.0),
                        reps: lastReps,
                        isAMRAP: false
                    ))
                } label: {
                    Label("Add Set", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Set Design")
            } footer: {
                switch selectedType {
                case .accessory:
                    Text("Design your sets. Weight is logged manually each session.")
                case .linear:
                    Text("Complete all sets at prescribed reps → weight increases next session.")
                case .structured:
                    Text("AMRAP sets (marked +) let you do max reps. The ⭐ progression set determines your TM adjustment.")
                default:
                    Text("Configure your sets below.")
                }
            }
        }
        .sheet(item: $showingTypeInfo) { type in
            ExerciseTypeInfoSheet(type: type)
        }
    }
    
    private func typeShortDescription(for type: DayItem.ItemType) -> String {
        switch type {
        case .accessory: return "No auto-progression, you decide when to add weight"
        case .linear: return "Add weight each successful session"
        case .structured: return "AMRAP performance adjusts your training max"
        case .volume: return "AMRAP performance adjusts your training max"
        case .tm: return "Display training max"
        }
    }
    
    private var defaultSets: [SetDetail] {
        [
            SetDetail(intensity: 0.75, reps: 5, isAMRAP: false),
            SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
            SetDetail(intensity: 0.85, reps: 5, isAMRAP: true)
        ]
    }
    
    private func typeName(for type: DayItem.ItemType) -> String {
        switch type {
        case .accessory: return "Accessory (No Auto-Progression)"
        case .linear: return "Linear Progression"
        case .structured: return "Autoregulated"
        case .volume: return "Autoregulated"
        case .tm: return "Training Max Display"
        }
    }
    
    private func addExercise() {
        guard let exercise = selectedExercise else { return }
        
        // All types now use setsDetail for set configuration
        let setsToUse = customSetsDetail.isEmpty ? defaultSets : customSetsDetail
        
        let item: DayItem
        switch selectedType {
        case .accessory:
            item = DayItem(
                type: .accessory,
                lift: nil,
                name: exercise.name,
                setsDetail: setsToUse
            )
        case .linear:
            item = DayItem(
                type: .linear,
                lift: exercise.name,
                name: exercise.name,
                setsDetail: setsToUse,
                progressionSetIndex: setsToUse.count - 1  // Last set determines progression
            )
        case .structured:
            item = DayItem(
                type: .structured,
                lift: exercise.name,
                name: exercise.name,
                setsDetail: setsToUse,
                progressionSetIndex: progressionSetIndex
            )
        case .volume:
            // Volume is now merged with structured/autoregulated
            item = DayItem(
                type: .structured,
                lift: exercise.name,
                name: exercise.name,
                setsDetail: setsToUse,
                progressionSetIndex: progressionSetIndex
            )
        case .tm:
            item = DayItem(
                type: .tm,
                lift: exercise.name,
                name: "\(exercise.name) TM"
            )
        }
        
        onSelect(item)
    }
}

// MARK: - Exercise Editor Sheet (for editing existing exercises)

struct ExerciseEditorSheet: View {
    let item: DayItem
    let mode: TemplateMode
    let onSave: (DayItem) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    
    @State private var selectedType: DayItem.ItemType
    @State private var sets: Int
    @State private var reps: Int
    @State private var customSetsDetail: [SetDetail]
    @State private var progressionSetIndex: Int
    @State private var showingTypeInfo: DayItem.ItemType?
    @State private var showingDeleteConfirmation = false
    
    init(item: DayItem, mode: TemplateMode, onSave: @escaping (DayItem) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.item = item
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        
        // Initialize state from existing item
        // Map volume type to structured (autoregulated) for display
        let displayType = item.type == .volume ? .structured : item.type
        self._selectedType = State(initialValue: displayType)
        self._sets = State(initialValue: item.sets ?? item.defaultSets ?? item.setsDetail?.count ?? 4)
        self._reps = State(initialValue: item.reps ?? item.defaultReps ?? item.setsDetail?.first?.reps ?? 10)
        
        // Initialize customSetsDetail - create from existing data or generate defaults
        if let existingSets = item.setsDetail, !existingSets.isEmpty {
            self._customSetsDetail = State(initialValue: existingSets)
        } else if let sets = item.sets ?? item.defaultSets, let reps = item.reps ?? item.defaultReps {
            // Convert legacy sets/reps to setsDetail
            let intensity = 0.80  // Default intensity
            var generatedSets: [SetDetail] = []
            for _ in 0..<sets {
                generatedSets.append(SetDetail(intensity: intensity, reps: reps, isAMRAP: false))
            }
            self._customSetsDetail = State(initialValue: generatedSets)
        } else {
            self._customSetsDetail = State(initialValue: [])
        }
        
        self._progressionSetIndex = State(initialValue: item.progressionSetIndex ?? 0)
    }
    
    private var availableTypes: [DayItem.ItemType] {
        if mode == .simple {
            return [.accessory]
        } else {
            // Only 3 progression schemes: Accessory (no auto), Linear, Autoregulated
            return [.accessory, .linear, .structured]
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Exercise name (read-only)
                Section {
                    HStack {
                        Text("Exercise")
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                        Spacer()
                        Text(item.name)
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                    }
                }
                
                // Type selection (only in advanced mode)
                if mode == .advanced {
                    Section {
                        ForEach(availableTypes, id: \.self) { type in
                            Button {
                                withAnimation {
                                    selectedType = type
                                    
                                    // Initialize set designer if empty
                                    if customSetsDetail.isEmpty {
                                        switch type {
                                        case .accessory:
                                            customSetsDetail = [
                                                SetDetail(intensity: 0.70, reps: 10, isAMRAP: false),
                                                SetDetail(intensity: 0.70, reps: 10, isAMRAP: false),
                                                SetDetail(intensity: 0.70, reps: 10, isAMRAP: false)
                                            ]
                                        case .linear:
                                            customSetsDetail = [
                                                SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                                                SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                                                SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                                                SetDetail(intensity: 0.80, reps: 5, isAMRAP: false),
                                                SetDetail(intensity: 0.80, reps: 5, isAMRAP: false)
                                            ]
                                        case .structured:
                                            customSetsDetail = defaultSets
                                        default:
                                            customSetsDetail = defaultSets
                                        }
                                    }
                                    
                                    // Set progression index for autoregulated
                                    if type == .structured {
                                        if let lastAmrapIndex = customSetsDetail.lastIndex(where: { $0.isAMRAP }) {
                                            progressionSetIndex = lastAmrapIndex
                                        } else {
                                            progressionSetIndex = customSetsDetail.count - 1
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(typeName(for: type))
                                            .font(SBSFonts.body())
                                            .foregroundStyle(SBSColors.textPrimaryFallback)
                                        Text(typeShortDescription(for: type))
                                            .font(SBSFonts.caption())
                                            .foregroundStyle(SBSColors.textTertiaryFallback)
                                    }
                                    
                                    Spacer()
                                    
                                    Button {
                                        showingTypeInfo = type
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .foregroundStyle(SBSColors.accentFallback)
                                    }
                                    .buttonStyle(.borderless)
                                    
                                    if selectedType == type {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(SBSColors.accentFallback)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Exercise Type")
                    }
                }
                
                // Set Designer - shown for ALL progression types
                Section {
                    ForEach(Array(customSetsDetail.enumerated()), id: \.offset) { index, setDetail in
                        SetDesignerRow(
                            setNumber: index + 1,
                            setDetail: setDetail,
                            isOnlySet: customSetsDetail.count == 1,
                            isProgressionSet: index == progressionSetIndex,
                            showProgressionOption: selectedType == .structured,
                            onUpdate: { updated in
                                customSetsDetail[index] = updated
                            },
                            onDelete: {
                                customSetsDetail.remove(at: index)
                                if progressionSetIndex >= customSetsDetail.count {
                                    progressionSetIndex = max(0, customSetsDetail.count - 1)
                                }
                            },
                            onSetAsProgression: {
                                progressionSetIndex = index
                            }
                        )
                    }
                    
                    Button {
                        let lastIntensity = customSetsDetail.last?.intensity ?? 0.75
                        let lastReps = customSetsDetail.last?.reps ?? 5
                        customSetsDetail.append(SetDetail(
                            intensity: min(lastIntensity + 0.05, 1.0),
                            reps: lastReps,
                            isAMRAP: false
                        ))
                    } label: {
                        Label("Add Set", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Set Design")
                } footer: {
                    switch selectedType {
                    case .accessory:
                        Text("Design your sets. Weight is logged manually each session.")
                    case .linear:
                        Text("Complete all sets at prescribed reps → weight increases next session.")
                    case .structured:
                        Text("AMRAP sets (marked +) let you do max reps. The ⭐ progression set determines your TM adjustment.")
                    default:
                        Text("Configure your sets below.")
                    }
                }
                
                // Delete exercise section
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Exercise")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveExercise()
                    }
                }
            }
            .sheet(item: $showingTypeInfo) { type in
                ExerciseTypeInfoSheet(type: type)
            }
            .confirmationDialog("Delete Exercise?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove \(item.name) from this day. This cannot be undone.")
            }
        }
    }
    
    private var defaultSets: [SetDetail] {
        [
            SetDetail(intensity: 0.65, reps: 5, isAMRAP: false),
            SetDetail(intensity: 0.75, reps: 5, isAMRAP: false),
            SetDetail(intensity: 0.85, reps: 5, isAMRAP: true)
        ]
    }
    
    private func typeName(for type: DayItem.ItemType) -> String {
        switch type {
        case .accessory: return "Accessory (No Auto-Progression)"
        case .linear: return "Linear Progression"
        case .structured: return "Autoregulated"
        case .volume: return "Autoregulated"
        case .tm: return "Training Max Display"
        }
    }
    
    private func typeShortDescription(for type: DayItem.ItemType) -> String {
        switch type {
        case .accessory: return "No auto-progression, you decide when to add weight"
        case .linear: return "Add weight each successful session"
        case .structured: return "AMRAP performance adjusts your training max"
        case .volume: return "AMRAP performance adjusts your training max"
        case .tm: return "Display training max"
        }
    }
    
    private func saveExercise() {
        // All types now use setsDetail for set configuration
        let setsToUse = customSetsDetail.isEmpty ? defaultSets : customSetsDetail
        
        let updatedItem: DayItem
        switch selectedType {
        case .accessory:
            updatedItem = DayItem(
                type: .accessory,
                lift: item.lift,
                name: item.name,
                setsDetail: setsToUse
            )
        case .linear:
            updatedItem = DayItem(
                type: .linear,
                lift: item.lift ?? item.name,
                name: item.name,
                setsDetail: setsToUse,
                progressionSetIndex: setsToUse.count - 1
            )
        case .structured, .volume:
            updatedItem = DayItem(
                type: .structured,
                lift: item.lift ?? item.name,
                name: item.name,
                setsDetail: setsToUse,
                progressionSetIndex: progressionSetIndex
            )
        case .tm:
            updatedItem = DayItem(
                type: .tm,
                lift: item.lift ?? item.name,
                name: item.name
            )
        }
        
        onSave(updatedItem)
    }
}

// MARK: - Set Designer Row (Editable)

struct SetDesignerRow: View {
    let setNumber: Int
    let setDetail: SetDetail
    let isOnlySet: Bool
    let isProgressionSet: Bool
    let showProgressionOption: Bool  // Only show progression set button for autoregulated
    let onUpdate: (SetDetail) -> Void
    let onDelete: () -> Void
    let onSetAsProgression: () -> Void
    
    @State private var isExpanded = false
    @State private var intensityPercent: Double
    @State private var reps: Int
    @State private var isAMRAP: Bool
    
    init(setNumber: Int, setDetail: SetDetail, isOnlySet: Bool, isProgressionSet: Bool, showProgressionOption: Bool, onUpdate: @escaping (SetDetail) -> Void, onDelete: @escaping () -> Void, onSetAsProgression: @escaping () -> Void) {
        self.setNumber = setNumber
        self.setDetail = setDetail
        self.isOnlySet = isOnlySet
        self.isProgressionSet = isProgressionSet
        self.showProgressionOption = showProgressionOption
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onSetAsProgression = onSetAsProgression
        self._intensityPercent = State(initialValue: setDetail.intensity * 100)
        self._reps = State(initialValue: setDetail.reps)
        self._isAMRAP = State(initialValue: setDetail.isAMRAP)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary row (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    HStack(spacing: 6) {
                        Text("Set \(setNumber)")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        // Progression set indicator (only for autoregulated)
                        if showProgressionOption && isProgressionSet {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(SBSColors.warning)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("\(Int(intensityPercent))%")
                            .font(SBSFonts.captionBold())
                            .foregroundStyle(SBSColors.accentFallback)
                        
                        Text("×")
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                        
                        Text("\(reps)\(isAMRAP ? "+" : "")")
                            .font(SBSFonts.captionBold())
                            .foregroundStyle(isAMRAP ? SBSColors.success : SBSColors.textSecondaryFallback)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
            }
            .buttonStyle(.plain)
            
            // Expanded editing controls
            if isExpanded {
                VStack(spacing: SBSLayout.paddingMedium) {
                    // Intensity slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Intensity")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                            Spacer()
                            Text("\(Int(intensityPercent))% of TM")
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.accentFallback)
                        }
                        
                        Slider(value: $intensityPercent, in: 50...100, step: 5) { _ in
                            saveChanges()
                        }
                        .tint(SBSColors.accentFallback)
                    }
                    
                    // Reps stepper
                    Stepper("Target Reps: \(reps)", value: $reps, in: 1...20) { _ in
                        saveChanges()
                    }
                    
                    // AMRAP toggle
                    Toggle(isOn: $isAMRAP) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AMRAP")
                                .font(SBSFonts.body())
                            Text("Do as many reps as possible")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                    .onChange(of: isAMRAP) { _, _ in
                        saveChanges()
                    }
                    
                    // Progression set button (only for autoregulated)
                    if showProgressionOption {
                        Button {
                            onSetAsProgression()
                        } label: {
                            HStack {
                                Image(systemName: isProgressionSet ? "star.fill" : "star")
                                    .foregroundStyle(isProgressionSet ? SBSColors.warning : SBSColors.textTertiaryFallback)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isProgressionSet ? "Progression Set" : "Use for Progression")
                                        .font(SBSFonts.body())
                                        .foregroundStyle(isProgressionSet ? SBSColors.warning : SBSColors.textPrimaryFallback)
                                    
                                    Text(isProgressionSet ? "This set determines your TM adjustment" : "Make this set determine TM changes")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textTertiaryFallback)
                                }
                                
                                Spacer()
                                
                                if isProgressionSet {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(SBSColors.warning)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isProgressionSet ? SBSColors.warning.opacity(0.1) : Color.clear)
                        )
                    }
                    
                    // Delete button
                    if !isOnlySet {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Remove Set", systemImage: "trash")
                                .font(SBSFonts.caption())
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.top, SBSLayout.paddingSmall)
                .padding(.leading, SBSLayout.paddingMedium)
            }
        }
    }
    
    private func saveChanges() {
        let updated = SetDetail(
            intensity: intensityPercent / 100.0,
            reps: reps,
            isAMRAP: isAMRAP
        )
        onUpdate(updated)
    }
}

// MARK: - Exercise Type Info Sheet

extension DayItem.ItemType: Identifiable {
    public var id: String { rawValue }
}

struct ExerciseTypeInfoSheet: View {
    let type: DayItem.ItemType
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSLayout.sectionSpacing) {
                    // Icon and title
                    HStack(spacing: SBSLayout.paddingMedium) {
                        Image(systemName: iconName)
                            .font(.system(size: 32))
                            .foregroundStyle(iconColor)
                            .frame(width: 56, height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(iconColor.opacity(0.15))
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(SBSFonts.title2())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text(subtitle)
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                    }
                    .padding(.top)
                    
                    // Description
                    Text(description)
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    // How it works
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Text("How It Works")
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        ForEach(howItWorks, id: \.self) { point in
                            HStack(alignment: .top, spacing: SBSLayout.paddingSmall) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SBSColors.success)
                                    .font(.system(size: 14))
                                    .padding(.top, 2)
                                
                                Text(point)
                                    .font(SBSFonts.body())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                        }
                    }
                    
                    // Best for
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Text("Best For")
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text(bestFor)
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    // Example
                    if let example = example {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                            Text("Example")
                                .font(SBSFonts.bodyBold())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text(example)
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                                        .fill(SBSColors.surfaceFallback)
                                )
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("About \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var iconName: String {
        switch type {
        case .accessory: return "dumbbell.fill"
        case .linear: return "arrow.up.right"
        case .structured: return "chart.line.uptrend.xyaxis"
        case .volume: return "chart.line.uptrend.xyaxis"
        case .tm: return "scalemass.fill"
        }
    }
    
    private var iconColor: Color {
        switch type {
        case .accessory: return SBSColors.textSecondaryFallback
        case .linear: return .green
        case .structured: return SBSColors.accentFallback
        case .volume: return SBSColors.accentFallback
        case .tm: return SBSColors.accentSecondaryFallback
        }
    }
    
    private var title: String {
        switch type {
        case .accessory: return "Accessory"
        case .linear: return "Linear Progression"
        case .structured: return "Autoregulated"
        case .volume: return "Autoregulated"
        case .tm: return "Training Max Display"
        }
    }
    
    private var subtitle: String {
        switch type {
        case .accessory: return "No auto-progression, you control when to add weight"
        case .linear: return "Add weight after each successful session"
        case .structured: return "AMRAP performance adjusts your training max"
        case .volume: return "AMRAP performance adjusts your training max"
        case .tm: return "Reference display only"
        }
    }
    
    private var description: String {
        switch type {
        case .accessory:
            return "Accessory exercises have no automatic progression. You design your sets with intensity and reps, log the weight each session, and decide when to increase. Perfect for isolation movements and supplementary work."
        case .linear:
            return "Linear progression automatically adds weight after each successful session. If you complete all sets and reps, the weight goes up next time. After repeated failures, a deload is applied."
        case .structured:
            return "Autoregulated progression adjusts your training max based on AMRAP (As Many Reps As Possible) performance. Beat the rep target and your TM increases; fall short and it decreases. The program adapts to your recovery and performance."
        case .volume:
            return "Autoregulated progression adjusts your training max based on AMRAP performance. Beat the rep target and your TM increases; fall short and it decreases. The program adapts to your recovery."
        case .tm:
            return "Displays your current training max and a suggested top single (typically 90% of TM). This is a reference only - no sets are performed."
        }
    }
    
    private var howItWorks: [String] {
        switch type {
        case .accessory:
            return [
                "Design your sets with intensity and rep targets",
                "Perform the prescribed workout",
                "Log the weight you used",
                "Increase weight when it feels too easy - you decide"
            ]
        case .linear:
            return [
                "Design your sets with intensity and rep targets",
                "Complete all reps = SUCCESS → add weight next session",
                "Fail to complete = FAILURE → retry same weight",
                "Multiple failures trigger a 10% deload"
            ]
        case .structured:
            return [
                "Design your sets with intensity, reps, and AMRAP markers",
                "Mark one set as the 'progression set' (⭐)",
                "Performance on the progression set adjusts your TM",
                "Beat the rep target → TM increases for next week"
            ]
        case .volume:
            return [
                "Perform sets at the week's prescribed intensity",
                "Final set is typically an AMRAP",
                "Beat the rep target → TM increases",
                "Miss the target → TM decreases or stays flat"
            ]
        case .tm:
            return [
                "Shows your current training max",
                "Displays suggested top single weight",
                "No logging required",
                "Used as reference for other exercises"
            ]
        }
    }
    
    private var bestFor: String {
        switch type {
        case .accessory:
            return "Isolation exercises, arm work, core, and any movement where you want full control over progression."
        case .linear:
            return "Beginners, or any lift where you can add weight frequently. Classic programs like 5×5 use this."
        case .structured:
            return "Main compound lifts where you want the program to adapt to your day-to-day performance. Great for intermediate and advanced lifters."
        case .volume:
            return "Main compound lifts where you want the program to adapt to your day-to-day performance."
        case .tm:
            return "Displaying your training max at the start of a workout for reference."
        }
    }
    
    private var example: String? {
        switch type {
        case .accessory:
            return "Bicep Curls: 3 sets\n• 70% × 12\n• 70% × 12\n• 70% × 12\nYou pick 25 lb, complete all sets. Next week you try 30 lb when ready."
        case .linear:
            return "Squat: 5 sets\n• 80% × 5\n• 80% × 5\n• 80% × 5\n• 80% × 5\n• 80% × 5\nComplete all reps → Next session: weight goes up"
        case .structured:
            return "Bench Press:\n• 75% × 5\n• 80% × 5\n• 85% × 5+ ⭐ (AMRAP, progression set)\nHit 8 reps on the progression set → TM goes up"
        case .volume:
            return "Squat: 4 sets\n• 80% × 8\n• 80% × 8\n• 80% × 8\n• 80% × 8+ ⭐ (AMRAP)\nTarget: 8 reps. You hit 11 → TM increases"
        case .tm:
            return nil
        }
    }
}

// MARK: - Step 3: Exercise Details

struct ExercisesStepView: View {
    @Binding var template: CustomTemplate
    let onBack: () -> Void
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSLayout.sectionSpacing) {
                    // Header
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Text("Review Exercises")
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("Review the exercises you've added to each day.")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .padding(.top, SBSLayout.paddingLarge)
                    
                    // Summary by day
                    ForEach(1...template.daysPerWeek, id: \.self) { day in
                        DaySummaryCard(
                            day: day,
                            exercises: template.days[String(day)] ?? []
                        )
                    }
                    
                    // Tracked lifts
                    if !template.trackedLifts.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                            Text("Lifts Requiring Training Maxes")
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                            
                            FlowLayout(spacing: SBSLayout.paddingSmall) {
                                ForEach(template.trackedLifts, id: \.self) { lift in
                                    Text(lift)
                                        .font(SBSFonts.caption())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(SBSColors.accentFallback.opacity(0.15))
                                        )
                                        .foregroundStyle(SBSColors.accentFallback)
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Navigation
            HStack(spacing: SBSLayout.paddingMedium) {
                Button {
                    onBack()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSSecondaryButtonStyle())
                
                Button {
                    // Initialize training maxes for tracked lifts
                    for lift in template.trackedLifts {
                        if template.initialMaxes[lift] == nil {
                            template.initialMaxes[lift] = 135.0  // Default starting weight
                        }
                    }
                    onContinue()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
            }
            .padding()
            .background(SBSColors.backgroundFallback)
        }
    }
}

struct DaySummaryCard: View {
    let day: Int
    let exercises: [DayItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text("Day \(day)")
                .font(SBSFonts.bodyBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            if exercises.isEmpty {
                Text("No exercises")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            } else {
                ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                    HStack {
                        Text("\(index + 1).")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                            .frame(width: 20)
                        
                        Text(exercise.name)
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
        )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Step 4: Review

struct ReviewStepView: View {
    let template: CustomTemplate
    let isEditing: Bool
    let onBack: () -> Void
    let onSave: () -> Void
    
    private var totalExercises: Int {
        template.days.values.flatMap { $0 }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSLayout.sectionSpacing) {
                    // Header
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        Text("Review Template")
                            .font(SBSFonts.title())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("Review your template before saving.")
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    .padding(.top, SBSLayout.paddingLarge)
                    
                    // Template summary card
                    VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(SBSFonts.title2())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                                
                                HStack(spacing: SBSLayout.paddingSmall) {
                                    Text(template.mode.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(template.mode == .advanced ? SBSColors.accentSecondaryFallback : SBSColors.textSecondaryFallback)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule()
                                                .fill(template.mode == .advanced ? SBSColors.accentSecondaryFallback.opacity(0.15) : SBSColors.surfaceFallback)
                                        )
                                    
                                    Text("Custom")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(SBSColors.accentFallback)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule()
                                                .fill(SBSColors.accentFallback.opacity(0.15))
                                        )
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        if !template.templateDescription.isEmpty {
                            Text(template.templateDescription)
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        
                        Divider()
                        
                        // Stats
                        HStack(spacing: SBSLayout.paddingLarge) {
                            TemplateStatItem(label: "Days/Week", value: "\(template.daysPerWeek)")
                            TemplateStatItem(label: "Weeks", value: "\(template.weeks.count)")
                            TemplateStatItem(label: "Exercises", value: "\(totalExercises)")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(SBSColors.surfaceFallback)
                    )
                    
                    // Validation
                    VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                        if template.isValid {
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SBSColors.success)
                                Text("Template is ready to save")
                                    .font(SBSFonts.body())
                                    .foregroundStyle(SBSColors.success)
                            }
                        } else {
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(SBSColors.error)
                                Text("Template has issues that need to be fixed")
                                    .font(SBSFonts.body())
                                    .foregroundStyle(SBSColors.error)
                            }
                            
                            // Show specific validation errors
                            ForEach(template.validationWarnings, id: \.self) { warning in
                                HStack(alignment: .top, spacing: SBSLayout.paddingSmall) {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundStyle(SBSColors.error)
                                        .font(.system(size: 14))
                                        .padding(.top, 2)
                                    
                                    Text(warning)
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(SBSColors.textSecondaryFallback)
                                }
                                .padding(.leading, SBSLayout.paddingMedium)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                            .fill(template.isValid ? SBSColors.success.opacity(0.1) : SBSColors.error.opacity(0.1))
                    )
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Navigation
            HStack(spacing: SBSLayout.paddingMedium) {
                Button {
                    onBack()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSSecondaryButtonStyle())
                
                Button {
                    onSave()
                } label: {
                    Text(isEditing ? "Save Changes" : "Save Template")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
                .disabled(!template.isValid)
            }
            .padding()
            .background(SBSColors.backgroundFallback)
        }
    }
}

struct TemplateStatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(SBSFonts.title2())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            Text(label)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
    }
}

#Preview {
    TemplateBuilderView(
        appState: AppState(),
        existingTemplate: nil,
        onSave: { _ in },
        onCancel: {}
    )
}

