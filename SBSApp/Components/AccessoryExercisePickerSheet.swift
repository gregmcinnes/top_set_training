import SwiftUI

// MARK: - Accessory Exercise Picker Sheet

/// A sheet for picking exercises from the exercise library when adding accessories
struct AccessoryExercisePickerSheet: View {
    let title: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    /// If true, shows only main lifts by default. If false, shows all exercises.
    var mainLiftsOnly: Bool = false

    /// If true, shows filter chips to toggle between all exercises and main lifts
    var showFilterChips: Bool = false

    /// Current exercise name (for showing checkmark)
    var currentExercise: String? = nil

    /// Custom exercises the user has added
    @State private var customExercises: [String] = []

    @State private var searchText: String = ""
    @State private var expandedBodyParts: Set<BodyPart> = []
    @State private var showingAddCustom = false
    @State private var customExerciseName = ""
    @State private var customExerciseBodyPart: BodyPart = .chest
    @State private var filterMainLiftsOnly: Bool = false

    private let library = ExerciseLibrary.shared

    private var effectiveMainLiftsOnly: Bool {
        mainLiftsOnly || filterMainLiftsOnly
    }

    private var exercises: [Exercise] {
        effectiveMainLiftsOnly ? library.mainLifts : library.exercises
    }

    private var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises
        }
        let query = searchText.lowercased()
        return exercises.filter { $0.name.lowercased().contains(query) }
    }

    private var exercisesByBodyPart: [BodyPart: [Exercise]] {
        Dictionary(grouping: filteredExercises) { $0.bodyPart }
    }

    private var sortedBodyParts: [BodyPart] {
        BodyPart.allCases.filter { exercisesByBodyPart[$0] != nil && !(exercisesByBodyPart[$0]?.isEmpty ?? true) }
    }

    private var hasSearchResults: Bool {
        !filteredExercises.isEmpty || !filteredCustomExercises.isEmpty
    }

    private var filteredCustomExercises: [String] {
        if searchText.isEmpty {
            return customExercises
        }
        let query = searchText.lowercased()
        return customExercises.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
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

                // Filter chips
                if showFilterChips {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SBSLayout.space2) {
                            FilterChip(
                                title: "All Exercises",
                                isSelected: !filterMainLiftsOnly,
                                onTap: { filterMainLiftsOnly = false }
                            )

                            FilterChip(
                                title: "Compound Lifts",
                                icon: "figure.strengthtraining.traditional",
                                isSelected: filterMainLiftsOnly,
                                onTap: { filterMainLiftsOnly = true }
                            )
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, SBSLayout.space2)
                }

                if hasSearchResults {
                    ScrollView {
                        LazyVStack(spacing: SBSLayout.space3) {
                            // Custom exercises section (if any)
                            if !filteredCustomExercises.isEmpty {
                                CustomExercisesSection(
                                    exercises: filteredCustomExercises,
                                    currentExercise: currentExercise,
                                    onSelect: onSelect
                                )
                            }

                            // Body part sections
                            ForEach(sortedBodyParts) { bodyPart in
                                BodyPartSection(
                                    bodyPart: bodyPart,
                                    exercises: exercisesByBodyPart[bodyPart] ?? [],
                                    currentExercise: currentExercise,
                                    isExpanded: isExpanded(bodyPart),
                                    onToggle: { toggleBodyPart(bodyPart) },
                                    onSelect: onSelect
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, SBSLayout.space4)
                    }
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    // No results
                    ContentUnavailableView(
                        "No Exercises Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or add a custom exercise")
                    )
                }

                // The sheet's action is picking a row, so adding one is the hairline alternative
                Button {
                    showingAddCustom = true
                } label: {
                    HStack(spacing: SBSLayout.space2) {
                        Image(systemName: "plus")
                            .font(SBSFonts.button())
                            .accessibilityHidden(true)
                        SBSButtonTitle("Add Custom Exercise")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSSecondaryButtonStyle())
                .padding(.horizontal)
                .padding(.top, SBSLayout.space2)
                .padding(.bottom, SBSLayout.space4)
            }
            .sbsBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(Color.inkSecondary)
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomExerciseSheet(
                    name: $customExerciseName,
                    bodyPart: $customExerciseBodyPart,
                    onAdd: { name in
                        customExercises.append(name)
                        onSelect(name)
                    },
                    onCancel: {
                        customExerciseName = ""
                        showingAddCustom = false
                    }
                )
                .presentationDetents([.medium])
            }
            .onAppear {
                // Load custom exercises from UserDefaults
                loadCustomExercises()

                // Auto-expand the first body part if search is empty
                if searchText.isEmpty && !sortedBodyParts.isEmpty {
                    expandedBodyParts.insert(sortedBodyParts[0])
                }
            }
        }
    }

    private func isExpanded(_ bodyPart: BodyPart) -> Bool {
        // If searching, show all expanded
        if !searchText.isEmpty {
            return true
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

    private func loadCustomExercises() {
        if let saved = UserDefaults.standard.stringArray(forKey: "customExercises") {
            customExercises = saved
        }
    }

    private func saveCustomExercises() {
        UserDefaults.standard.set(customExercises, forKey: "customExercises")
    }
}

// MARK: - Body Part Section

/// One hairline group per body part: a header row that expands it, then its exercises.
/// Body parts are told apart by name and glyph, not by a colour each.
struct BodyPartSection: View {
    let bodyPart: BodyPart
    let exercises: [Exercise]
    let currentExercise: String?
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                PickerGroupHeader(
                    systemImage: bodyPart.icon,
                    title: bodyPart.rawValue,
                    count: exercises.count,
                    chevron: isExpanded ? "chevron.up" : "chevron.down"
                )
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                ForEach(exercises) { exercise in
                    SBSRowDivider()
                    ExerciseRow(
                        exercise: exercise,
                        isSelected: currentExercise == exercise.name,
                        onSelect: { onSelect(exercise.name) }
                    )
                }
            }
        }
        .card()
    }
}

/// A picker group's header: an ink-secondary glyph, the title, the count in
/// number-small and an optional chevron.
private struct PickerGroupHeader: View {
    let systemImage: String
    let title: String
    let count: Int
    var chevron: String? = nil

    var body: some View {
        HStack(spacing: SBSLayout.space3) {
            Image(systemName: systemImage)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(title)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.ink)

            Text("\(count)")
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)
                .accessibilityLabel("\(count) exercises")

            Spacer(minLength: 0)

            if let chevron {
                SBSChevron(systemName: chevron)
            }
        }
        .padding(.horizontal, SBSLayout.space4)
        .padding(.vertical, SBSLayout.space3)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - Exercise Row

struct ExerciseRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            PickerExerciseRow(
                systemImage: equipmentIcon,
                name: exercise.name,
                detail: exercise.equipment.rawValue,
                badge: exercise.isCompound ? "Compound" : nil,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var equipmentIcon: String {
        switch exercise.equipment {
        case .barbell: return "line.horizontal.3"
        case .dumbbell: return "dumbbell.fill"
        case .cable: return "arrow.up.and.down"
        case .machine: return "gearshape.fill"
        case .bodyweight: return "figure.stand"
        case .kettlebell: return "drop.fill"
        case .ezBar: return "line.3.horizontal.decrease"
        case .smithMachine: return "square.stack.3d.up.fill"
        case .bands: return "lasso"
        case .other: return "circle.fill"
        }
    }
}

/// An exercise row inside a picker group. The current exercise is orange-soft
/// with an orange-text check; its text stays ink.
private struct PickerExerciseRow: View {
    let systemImage: String
    let name: String
    let detail: String?
    let badge: String?
    let isSelected: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: SBSLayout.space3) {
            Image(systemName: systemImage)
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SBSFonts.body())
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)

                if let detail {
                    Text(detail)
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }

                // Under the name at the accessibility sizes, where beside it the
                // name breaks a letter a line
                if let badge, dynamicTypeSize.isAccessibilitySize {
                    SBSBadge(text: badge)
                }
            }

            Spacer(minLength: SBSLayout.space2)

            if let badge, !dynamicTypeSize.isAccessibilitySize {
                SBSBadge(text: badge)
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(SBSFonts.bodyStrong().weight(.bold))
                    .foregroundStyle(Color.orangeText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, SBSLayout.space4)
        .padding(.vertical, SBSLayout.space3)
        .frame(minHeight: 56)
        .background(isSelected ? Color.orangeSoft : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Custom Exercises Section

struct CustomExercisesSection: View {
    let exercises: [String]
    let currentExercise: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PickerGroupHeader(systemImage: "star", title: "My Exercises", count: exercises.count)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

            ForEach(exercises, id: \.self) { name in
                SBSRowDivider()
                Button {
                    onSelect(name)
                } label: {
                    PickerExerciseRow(
                        systemImage: "dumbbell",
                        name: name,
                        detail: nil,
                        badge: "Custom",
                        isSelected: currentExercise == name
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(currentExercise == name ? [.isSelected] : [])
            }
        }
        .card()
    }
}

// MARK: - Add Custom Exercise Sheet

struct AddCustomExerciseSheet: View {
    @Binding var name: String
    @Binding var bodyPart: BodyPart
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: SBSLayout.space6) {
                // Header
                VStack(spacing: SBSLayout.space2) {
                    Text("Add Custom Exercise")
                        .font(SBSFonts.title())
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)

                    Text("Create your own exercise to track")
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, SBSLayout.space6)
                .padding(.horizontal)

                // Name input
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    SBSEyebrow("Exercise Name")
                        .foregroundStyle(Color.inkSecondary)

                    TextField("e.g., Chest Flyes, Hip Thrust", text: $name)
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.ink)
                        .frame(minHeight: 32)
                        .sbsFieldCell()
                        .focused($isNameFocused)
                }
                .padding(.horizontal)

                // Body part picker
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    SBSEyebrow("Body Part (optional)")
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SBSLayout.space2) {
                            ForEach(BodyPart.allCases) { part in
                                BodyPartChip(
                                    bodyPart: part,
                                    isSelected: bodyPart == part,
                                    onSelect: { bodyPart = part }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer()

                // Add button: the sheet's one primary action
                Button {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    saveCustomExercise(trimmedName)
                    onAdd(trimmedName)
                } label: {
                    SBSButtonTitle("Add Exercise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SBSPrimaryButtonStyle())
                .disabled(!isValid)
                .padding(.horizontal)
                // Room for the hard shadow
                .padding(.trailing, SBSLayout.hardShadowOffset)
                .padding(.bottom, SBSLayout.space6)
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(Color.inkSecondary)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
    }

    private func saveCustomExercise(_ exerciseName: String) {
        var customs = UserDefaults.standard.stringArray(forKey: "customExercises") ?? []
        if !customs.contains(exerciseName) {
            customs.append(exerciseName)
            UserDefaults.standard.set(customs, forKey: "customExercises")
        }
    }
}

// MARK: - Body Part Chip

/// A body part choice: an SBSChip (selected orange-soft with an orange-text edge),
/// no longer filled in the body part's own colour.
struct BodyPartChip: View {
    let bodyPart: BodyPart
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        SBSChip(title: bodyPart.rawValue, systemImage: bodyPart.icon, isSelected: isSelected, action: onSelect)
    }
}

// MARK: - Filter Chip

/// Kept for its call sites (ProgramSelector too): an SBSChip.
struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        SBSChip(title: title, systemImage: icon, isSelected: isSelected, action: onTap)
    }
}

// MARK: - Preview

#Preview {
    AccessoryExercisePickerSheet(
        title: "Select Exercise",
        onSelect: { Logger.debug("Selected: \($0)", category: .ui) },
        onCancel: { },
        showFilterChips: true
    )
}

