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
            Color.bg
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator
                TemplateStepProgressView(currentStep: currentStep)
                    .padding(.leading)
                    // Clear of the close button
                    .padding(.trailing, 56)
                    .padding(.top, SBSLayout.space2)
                
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
                .gesture(DragGesture())
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(SBSFonts.bodyStrong().weight(.bold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                    .padding(.horizontal, SBSLayout.space2)
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
        // Done steps are ink, the current one orange, the rest hairline cells
        HStack(spacing: 0) {
            ForEach(TemplateBuilderView.TemplateBuilderStep.allCases, id: \.rawValue) { step in
                let isDone = step.rawValue < currentStep.rawValue
                let isCurrent = step == currentStep
                HStack(spacing: SBSLayout.space1) {
                    ZStack {
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                            .fill(isCurrent ? Color.orangeFill : (isDone ? Color.ink : Color.surface))
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                            .strokeBorder(isCurrent || isDone ? Color.clear : Color.hairline, lineWidth: SBSLayout.strokeHairline)

                        if isDone {
                            Image(systemName: "checkmark")
                                .font(SBSFonts.numberSmall().weight(.bold))
                                .foregroundStyle(Color.bg)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(SBSFonts.numberSmall().weight(.bold))
                                .foregroundStyle(isCurrent ? Color.orangeInk : Color.inkSecondary)
                        }
                    }
                    .frame(width: 28, height: 28)

                    if step != TemplateBuilderView.TemplateBuilderStep.allCases.last {
                        Rectangle()
                            .fill(isDone ? Color.ink : Color.hairline)
                            .frame(height: SBSLayout.strokeHairline)
                    }
                }
            }
        }
        .padding(.vertical, SBSLayout.space2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep.rawValue + 1) of \(TemplateBuilderView.TemplateBuilderStep.allCases.count), \(currentStep.title)")
    }
}

// MARK: - Step 1: Basics

struct BasicsStepView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            VStack(alignment: .leading, spacing: SBSLayout.space6) {
                // Header
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    Text("Template Basics")
                        .font(SBSFonts.title())
                        .foregroundStyle(Color.ink)
                    
                    Text("Give your template a name and configure the basic structure.")
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top, SBSLayout.space6)
                
                // Name
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    SBSSectionEyebrow("Template Name")

                    TextField("e.g., My Upper/Lower Split", text: $template.name)
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.ink)
                        .textFieldStyle(.plain)
                        .frame(minHeight: 32)
                        .sbsFieldCell()
                        .focused($focusedField, equals: .name)
                }

                // Description
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    SBSSectionEyebrow("Description (Optional)")

                    TextField("Describe your program...", text: $template.templateDescription, axis: .vertical)
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.ink)
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .padding(.vertical, SBSLayout.space1)
                        .sbsFieldCell()
                        .focused($focusedField, equals: .description)
                }

                // Mode Selection
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    SBSSectionEyebrow("Template Mode")

                    ForEach(TemplateMode.allCases, id: \.self) { mode in
                        let isSelected = template.mode == mode
                        Button {
                            template.mode = mode
                        } label: {
                            HStack(alignment: .top, spacing: SBSLayout.space3) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .font(SBSFonts.heading())
                                    .foregroundStyle(isSelected ? Color.orangeText : Color.inkSecondary)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .font(SBSFonts.bodyStrong())
                                        .foregroundStyle(Color.ink)

                                    Text(mode.description)
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(Color.inkSecondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding()
                            .selectionCell(isSelected)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }

                // Days per week
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    SBSSectionEyebrow("Days per Week")

                    HStack(spacing: SBSLayout.space1) {
                        ForEach(1...7, id: \.self) { day in
                            let isSelected = template.daysPerWeek == day
                            Button {
                                template.daysPerWeek = day
                                // Trim or add days as needed
                                ensureDayStructure()
                            } label: {
                                Text("\(day)")
                                    .font(SBSFonts.number())
                                    .foregroundStyle(Color.ink)
                                    .minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .selectionCell(isSelected)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(day) days per week")
                            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        }
                    }
                }

                // Number of weeks
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    SBSSectionEyebrow("Program Length")

                    // A grid of three at the accessibility sizes: five across reads "4 wk8 wk12 wk"
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: SBSLayout.space1), count: dynamicTypeSize.isAccessibilitySize ? 3 : 5),
                        spacing: SBSLayout.space1
                    ) {
                        ForEach([4, 8, 12, 16, 20], id: \.self) { weekCount in
                            let isSelected = template.weeks.count == weekCount
                            Button {
                                template.weeks = Array(1...weekCount)
                            } label: {
                                Text("\(weekCount) wk")
                                    .font(SBSFonts.numberSmall().weight(.semibold))
                                    .foregroundStyle(Color.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .selectionCell(isSelected)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(weekCount) weeks")
                            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
                    SBSButtonTitle("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
                .disabled(!canContinue)
            }
            .padding()
            // Room for the hard shadow
            .padding(.trailing, SBSLayout.hardShadowOffset)
            .background(Color.bg)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                Text("Configure Days")
                    .font(SBSFonts.title())
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                // The fixed header gives the list room at the accessibility sizes
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Select each day to add exercises.")
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            // Day selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SBSLayout.space2) {
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
            
            SBSRowDivider()
                .padding(.top, SBSLayout.space2)
            
            // Exercise list for selected day
            DayExerciseListView(
                template: $template,
                day: selectedDay
            )
            .onChange(of: template.daysPerWeek) { _, newCount in
                // Reducing days per week must not leave the list on a day with no tab
                selectedDay = min(selectedDay, newCount)
            }
            .onAppear {
                selectedDay = min(selectedDay, template.daysPerWeek)
            }
            
            // Navigation
            HStack(spacing: SBSLayout.space4) {
                Button {
                    onBack()
                } label: {
                    SBSButtonTitle("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSSecondaryButtonStyle())

                Button {
                    onContinue()
                } label: {
                    SBSButtonTitle("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
                .disabled(!hasAtLeastOneExercise)
            }
            .padding()
            // Room for the hard shadow
            .padding(.trailing, SBSLayout.hardShadowOffset)
            .background(Color.bg)
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
            VStack(spacing: 2) {
                SBSEyebrow("Day \(day)")
                    .foregroundStyle(Color.ink)

                Text("\(exerciseCount) ex")
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, SBSLayout.space4)
            .padding(.vertical, SBSLayout.space2)
            .frame(minHeight: 44)
            .selectionCell(isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Day \(day), \(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
                    VStack(spacing: SBSLayout.space4) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(SBSFonts.titleLarge())
                            .foregroundStyle(Color.inkSecondary)
                            .accessibilityHidden(true)

                        Text("No exercises yet")
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)

                        Button {
                            showingExercisePicker = true
                        } label: {
                            HStack(spacing: SBSLayout.space2) {
                                Image(systemName: "plus")
                                    .font(SBSFonts.button())
                                    .accessibilityHidden(true)
                                SBSButtonTitle("Add Exercise")
                            }
                        }
                        .buttonStyle(SBSSecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.space6)
                }
                .sbsListRows()
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
                        Label("Add Exercise", systemImage: "plus")
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.orangeText)
                    }
                } header: {
                    SBSListHeader("Day \(day) Exercises")
                }
                .sbsListRows()
            }
        }
        .sbsGroupedList()
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
    
    var body: some View {
        Button {
            onEdit()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    Text(item.name)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)

                    // The type is named by a neutral badge: the word does the work
                    HStack(spacing: SBSLayout.space2) {
                        SBSBadge(text: typeLabel)

                        if item.type == .accessory {
                            SBSRowSubtitle("\(item.defaultSets ?? 4) × \(item.defaultReps ?? 10)")
                        } else if item.type == .linear {
                            SBSRowSubtitle("\(item.sets ?? 5) × \(item.reps ?? 5)")
                        } else if let setsDetail = item.setsDetail {
                            SBSRowSubtitle("\(setsDetail.count) sets")
                        }
                    }
                }

                Spacer(minLength: SBSLayout.space2)

                SBSChevron()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
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
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "magnifyingglass")
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.inkSecondary)
                                .accessibilityHidden(true)

                            TextField("Search exercises...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.ink)

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(SBSFonts.body())
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                .accessibilityLabel("Clear search")
                            }
                        }
                        .frame(minHeight: 32)
                        .sbsFieldCell()
                        .padding(.horizontal)
                        .padding(.top, SBSLayout.space2)

                        if !filteredExercises.isEmpty {
                            ScrollView {
                                LazyVStack(spacing: SBSLayout.space3) {
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
                                .padding(.vertical, SBSLayout.space4)
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
                SBSAdaptiveStack {
                    Text("Exercise")
                        .foregroundStyle(Color.inkSecondary)
                    Spacer(minLength: 0)
                    Text(selectedExercise?.name ?? "")
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)
                }
            }
            .sbsListRows()
            
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
                                        .foregroundStyle(Color.ink)
                                    Text(typeShortDescription(for: type))
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                
                                Spacer()
                                
                                // Info button
                                Button {
                                    showingTypeInfo = type
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(SBSFonts.body())
                                        .foregroundStyle(Color.inkSecondary)
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("About \(typeName(for: type))")

                                if selectedType == type {
                                    Image(systemName: "checkmark")
                                        .font(SBSFonts.bodyStrong().weight(.bold))
                                        .foregroundStyle(Color.orangeText)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityAddTraits(selectedType == type ? [.isSelected] : [])
                    }
                } header: {
                    SBSListHeader("Exercise Type")
                } footer: {
                    SBSListFooter("Tap ⓘ for detailed information about each type.")
                }
                .sbsListRows()
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
                    Label("Add Set", systemImage: "plus")
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.orangeText)
                }
            } header: {
                SBSListHeader("Set Design")
            } footer: {
                switch selectedType {
                case .accessory:
                    SBSListFooter("Design your sets. Weight is logged manually each session.")
                case .linear:
                    SBSListFooter("Complete all sets at prescribed reps → weight increases next session.")
                case .structured:
                    SBSListFooter("AMRAP sets (marked +) let you do max reps. The starred progression set determines your TM adjustment.")
                default:
                    SBSListFooter("Configure your sets below.")
                }
            }
            .sbsListRows()
        }
        .sbsGroupedList()
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
                defaultSets: setsToUse.count,
                defaultReps: setsToUse.first?.reps,
                setsDetail: setsToUse
            )
        case .linear:
            item = DayItem(
                type: .linear,
                lift: exercise.name,
                name: exercise.name,
                setsDetail: setsToUse,
                sets: setsToUse.count,
                reps: setsToUse.first?.reps,
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
            List {  // A List, not a Form: sbsGroupedList squares it
                // Exercise name (read-only)
                Section {
                    SBSAdaptiveStack {
                        Text("Exercise")
                            .foregroundStyle(Color.inkSecondary)
                        Spacer(minLength: 0)
                        Text(item.name)
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.ink)
                    }
                }
                .sbsListRows()
                
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
                                            .foregroundStyle(Color.ink)
                                        Text(typeShortDescription(for: type))
                                            .font(SBSFonts.caption())
                                            .foregroundStyle(Color.inkSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button {
                                        showingTypeInfo = type
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .font(SBSFonts.body())
                                            .foregroundStyle(Color.inkSecondary)
                                            .frame(minWidth: 44, minHeight: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("About \(typeName(for: type))")

                                    if selectedType == type {
                                        Image(systemName: "checkmark")
                                            .font(SBSFonts.bodyStrong().weight(.bold))
                                            .foregroundStyle(Color.orangeText)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .accessibilityAddTraits(selectedType == type ? [.isSelected] : [])
                        }
                    } header: {
                        SBSListHeader("Exercise Type")
                    }
                    .sbsListRows()
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
                        Label("Add Set", systemImage: "plus")
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.orangeText)
                    }
                } header: {
                    SBSListHeader("Set Design")
                } footer: {
                    switch selectedType {
                    case .accessory:
                        SBSListFooter("Design your sets. Weight is logged manually each session.")
                    case .linear:
                        SBSListFooter("Complete all sets at prescribed reps → weight increases next session.")
                    case .structured:
                        SBSListFooter("AMRAP sets (marked +) let you do max reps. The starred progression set determines your TM adjustment.")
                    default:
                        SBSListFooter("Configure your sets below.")
                    }
                }
                .sbsListRows()

                // Delete exercise section
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "trash")
                                .accessibilityHidden(true)
                            Text("Delete Exercise")
                        }
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.danger)
                        .frame(maxWidth: .infinity)
                    }
                }
                .sbsListRows()
            }
            .sbsGroupedList()
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
                defaultSets: setsToUse.count,
                defaultReps: setsToUse.first?.reps,
                setsDetail: setsToUse
            )
        case .linear:
            updatedItem = DayItem(
                type: .linear,
                lift: item.lift ?? item.name,
                name: item.name,
                setsDetail: setsToUse,
                sets: setsToUse.count,
                reps: setsToUse.first?.reps,
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
                    HStack(spacing: SBSLayout.space2) {
                        Text("Set \(setNumber)")
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.ink)

                        // Progression set indicator (only for autoregulated)
                        if showProgressionOption && isProgressionSet {
                            Image(systemName: "star.fill")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.ink)
                                .accessibilityLabel("Progression set")
                        }
                    }

                    Spacer(minLength: SBSLayout.space2)

                    // Values are ink; an AMRAP set reads "5+"
                    Text("\(Int(intensityPercent))% × \(reps)\(isAMRAP ? "+" : "")")
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    SBSChevron(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded editing controls
            if isExpanded {
                VStack(spacing: SBSLayout.space4) {
                    // Intensity slider
                    VStack(alignment: .leading, spacing: SBSLayout.space1) {
                        SBSAdaptiveStack(alignment: .firstTextBaseline) {
                            SBSEyebrow("Intensity")
                                .foregroundStyle(Color.inkSecondary)
                            Spacer(minLength: 0)
                            Text("\(Int(intensityPercent))% of TM")
                                .font(SBSFonts.numberSmall().weight(.semibold))
                                .foregroundStyle(Color.ink)
                        }

                        Slider(value: $intensityPercent, in: 50...100, step: 5) { _ in
                            saveChanges()
                        }
                        .tint(Color.orangeFill)
                    }

                    // Reps stepper
                    SBSStepperRow(title: "Target reps", value: $reps, range: 1...20, compact: true)
                        .onChange(of: reps) { _, _ in
                            saveChanges()
                        }

                    // AMRAP toggle
                    Toggle(isOn: $isAMRAP) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AMRAP")
                                .font(SBSFonts.bodyStrong())
                                .foregroundStyle(Color.ink)
                            Text("Do as many reps as possible")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
                    .toggleStyle(SBSToggleStyle())
                    .onChange(of: isAMRAP) { _, _ in
                        saveChanges()
                    }

                    // Progression set button (only for autoregulated)
                    if showProgressionOption {
                        Button {
                            onSetAsProgression()
                        } label: {
                            HStack(spacing: SBSLayout.space3) {
                                Image(systemName: isProgressionSet ? "star.fill" : "star")
                                    .font(SBSFonts.body())
                                    .foregroundStyle(isProgressionSet ? Color.orangeText : Color.inkSecondary)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isProgressionSet ? "Progression Set" : "Use for Progression")
                                        .font(SBSFonts.bodyStrong())
                                        .foregroundStyle(Color.ink)

                                    Text(isProgressionSet ? "This set determines your TM adjustment" : "Make this set determine TM changes")
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(Color.inkSecondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 0)

                                if isProgressionSet {
                                    Image(systemName: "checkmark")
                                        .font(SBSFonts.bodyStrong().weight(.bold))
                                        .foregroundStyle(Color.orangeText)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(SBSLayout.space3)
                            .selectionCell(isProgressionSet)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityAddTraits(isProgressionSet ? [.isSelected] : [])
                    }

                    // Delete button
                    if !isOnlySet {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Remove Set", systemImage: "trash")
                                .font(SBSFonts.caption().weight(.semibold))
                                .foregroundStyle(Color.danger)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.top, SBSLayout.space2)
                .padding(.leading, SBSLayout.space4)
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
                VStack(alignment: .leading, spacing: SBSLayout.space6) {
                    // Icon and title
                    HStack(spacing: SBSLayout.space4) {
                        Image(systemName: iconName)
                            .font(SBSFonts.title())
                            .foregroundStyle(Color.ink)
                            .frame(width: 56, height: 56)
                            .card()
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(SBSFonts.heading())
                                .foregroundStyle(Color.ink)
                            
                            Text(subtitle)
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
                    .padding(.top)
                    
                    // Description
                    Text(description)
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.inkSecondary)
                    
                    // How it works
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        SBSSectionEyebrow("How It Works")

                        ForEach(howItWorks, id: \.self) { point in
                            HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                                Image(systemName: "checkmark")
                                    .font(SBSFonts.caption().weight(.bold))
                                    .foregroundStyle(Color.success)
                                    .accessibilityHidden(true)
                                
                                Text(point)
                                    .font(SBSFonts.body())
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                    }
                    
                    // Best for
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        SBSSectionEyebrow("Best For")

                        Text(bestFor)
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    
                    // Example
                    if let example = example {
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            SBSSectionEyebrow("Example")

                            Text(example)
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.ink)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card()
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .sbsBackground()
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
                "Mark one set as the 'progression set' (★)",
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
            return "Bench Press:\n• 75% × 5\n• 80% × 5\n• 85% × 5+ ★ (AMRAP, progression set)\nHit 8 reps on the progression set → TM goes up"
        case .volume:
            return "Squat: 4 sets\n• 80% × 8\n• 80% × 8\n• 80% × 8\n• 80% × 8+ ★ (AMRAP)\nTarget: 8 reps. You hit 11 → TM increases"
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
                VStack(alignment: .leading, spacing: SBSLayout.space6) {
                    // Header
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        Text("Review Exercises")
                            .font(SBSFonts.title())
                            .foregroundStyle(Color.ink)
                        
                        Text("Review the exercises you've added to each day.")
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .padding(.top, SBSLayout.space6)
                    
                    // Summary by day
                    ForEach(1...template.daysPerWeek, id: \.self) { day in
                        DaySummaryCard(
                            day: day,
                            exercises: template.days[String(day)] ?? []
                        )
                    }
                    
                    // Tracked lifts
                    if !template.trackedLifts.isEmpty {
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            SBSSectionEyebrow("Lifts Requiring Training Maxes")

                            FlowLayout(spacing: SBSLayout.space2) {
                                ForEach(template.trackedLifts, id: \.self) { lift in
                                    SBSBadge(text: lift)
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
            HStack(spacing: SBSLayout.space4) {
                Button {
                    onBack()
                } label: {
                    SBSButtonTitle("Back")
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
                    SBSButtonTitle("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
            }
            .padding()
            // Room for the hard shadow
            .padding(.trailing, SBSLayout.hardShadowOffset)
            .background(Color.bg)
        }
    }
}

struct DaySummaryCard: View {
    let day: Int
    let exercises: [DayItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("Day \(day)")

            VStack(alignment: .leading, spacing: 0) {
                if exercises.isEmpty {
                    Text("No exercises")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal, SBSLayout.space4)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                } else {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                        if index > 0 { SBSRowDivider() }
                        HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space3) {
                            Text("\(index + 1)")
                                .font(SBSFonts.numberSmall())
                                .foregroundStyle(Color.inkSecondary)
                                .frame(minWidth: 20, alignment: .leading)

                            Text(exercise.name)
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.ink)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, SBSLayout.space4)
                        .padding(.vertical, SBSLayout.space3)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
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
                self.size.width = max(self.size.width, x + size.width)
                x += size.width + spacing
            }

            // Never report wider than offered: an item wider than a line
            // would otherwise widen every parent up to the screen
            if maxWidth > 0 { self.size.width = min(self.size.width, maxWidth) }
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
                VStack(alignment: .leading, spacing: SBSLayout.space6) {
                    // Header
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        Text("Review Template")
                            .font(SBSFonts.title())
                            .foregroundStyle(Color.ink)
                        
                        Text("Review your template before saving.")
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .padding(.top, SBSLayout.space6)
                    
                    // Template summary card
                    VStack(alignment: .leading, spacing: SBSLayout.space4) {
                        VStack(alignment: .leading, spacing: SBSLayout.space2) {
                            Text(template.name)
                                .font(SBSFonts.heading())
                                .foregroundStyle(Color.ink)

                            HStack(spacing: SBSLayout.space2) {
                                SBSBadge(text: template.mode.displayName)
                                SBSBadge(text: "Custom")
                            }
                        }

                        if !template.templateDescription.isEmpty {
                            Text(template.templateDescription)
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.inkSecondary)
                        }

                        SBSRowDivider()

                        // Stats
                        SBSAdaptiveStack(alignment: .top, spacing: SBSLayout.space6) {
                            TemplateStatItem(label: "Days/Week", value: "\(template.daysPerWeek)")
                            TemplateStatItem(label: "Weeks", value: "\(template.weeks.count)")
                            TemplateStatItem(label: "Exercises", value: "\(totalExercises)")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // Validation: a glyph and a word on a hairline card, never a tint
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        if template.isValid {
                            HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                                Image(systemName: "checkmark")
                                    .font(SBSFonts.bodyStrong().weight(.bold))
                                    .foregroundStyle(Color.success)
                                    .accessibilityHidden(true)
                                Text("Template is ready to save")
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.ink)
                            }
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.danger)
                                    .accessibilityHidden(true)
                                Text("Template has issues that need to be fixed")
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(Color.ink)
                            }

                            // Show specific validation errors
                            ForEach(template.validationWarnings, id: \.self) { warning in
                                HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                                    Image(systemName: "xmark")
                                        .font(SBSFonts.caption().weight(.bold))
                                        .foregroundStyle(Color.danger)
                                        .accessibilityHidden(true)

                                    Text(warning)
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                .padding(.leading, SBSLayout.space4)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            
            // Navigation
            HStack(spacing: SBSLayout.space4) {
                Button {
                    onBack()
                } label: {
                    SBSButtonTitle("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSSecondaryButtonStyle())

                Button {
                    onSave()
                } label: {
                    SBSButtonTitle(isEditing ? "Save Changes" : "Save Template")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
                .disabled(!template.isValid)
            }
            .padding()
            // Room for the hard shadow
            .padding(.trailing, SBSLayout.hardShadowOffset)
            .background(Color.bg)
        }
    }
}

struct TemplateStatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(SBSFonts.numberLarge())
                .foregroundStyle(Color.ink)

            SBSEyebrow(label)
                .foregroundStyle(Color.inkSecondary)
        }
        .accessibilityElement(children: .combine)
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

