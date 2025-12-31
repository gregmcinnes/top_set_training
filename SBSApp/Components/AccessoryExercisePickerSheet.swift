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
                
                // Filter chips
                if showFilterChips {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SBSLayout.paddingSmall) {
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
                    .padding(.top, SBSLayout.paddingSmall)
                }
                
                if hasSearchResults {
                    ScrollView {
                        LazyVStack(spacing: SBSLayout.paddingSmall) {
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
                        .padding(.vertical, SBSLayout.paddingMedium)
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
                
                // Add custom button
                Button {
                    showingAddCustom = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Custom Exercise")
                    }
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.accentFallback)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .strokeBorder(SBSColors.accentFallback.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, SBSLayout.paddingMedium)
            }
            .sbsBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(SBSColors.textSecondaryFallback)
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

struct BodyPartSection: View {
    let bodyPart: BodyPart
    let exercises: [Exercise]
    let currentExercise: String?
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelect: (String) -> Void
    
    private var bodyPartColor: Color {
        switch bodyPart.color {
        case "red": return .red
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "indigo": return .indigo
        case "mint": return .mint
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (tappable to expand/collapse)
            Button(action: onToggle) {
                HStack(spacing: SBSLayout.paddingSmall) {
                    // Body part icon
                    Image(systemName: bodyPart.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(bodyPartColor)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(bodyPartColor.opacity(0.15))
                        )
                    
                    Text(bodyPart.rawValue)
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("(\(exercises.count))")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: isExpanded ? 12 : SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.surfaceFallback)
                )
            }
            .buttonStyle(.plain)
            
            // Expanded exercises
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(exercises) { exercise in
                        ExerciseRow(
                            exercise: exercise,
                            isSelected: currentExercise == exercise.name,
                            bodyPartColor: bodyPartColor,
                            onSelect: { onSelect(exercise.name) }
                        )
                    }
                }
                .background(SBSColors.surfaceFallback.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Exercise Row

struct ExerciseRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let bodyPartColor: Color
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: SBSLayout.paddingMedium) {
                // Equipment indicator
                Image(systemName: equipmentIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text(exercise.equipment.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                
                Spacer()
                
                // Category badge
                if exercise.isCompound {
                    Text("Compound")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(bodyPartColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(bodyPartColor.opacity(0.12))
                        )
                }
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SBSColors.accentFallback)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(
                isSelected ? SBSColors.accentFallback.opacity(0.08) : Color.clear
            )
        }
        .buttonStyle(.plain)
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

// MARK: - Custom Exercises Section

struct CustomExercisesSection: View {
    let exercises: [String]
    let currentExercise: String?
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: SBSLayout.paddingSmall) {
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.yellow.opacity(0.15))
                    )
                
                Text("My Exercises")
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("(\(exercises.count))")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(SBSColors.surfaceFallback)
            )
            
            // Exercises
            VStack(spacing: 1) {
                ForEach(exercises, id: \.self) { name in
                    Button {
                        onSelect(name)
                    } label: {
                        HStack {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                                .frame(width: 24)
                            
                            Text(name)
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Spacer()
                            
                            Text("Custom")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.yellow.opacity(0.12))
                                )
                            
                            if currentExercise == name {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(SBSColors.accentFallback)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(
                            currentExercise == name ? SBSColors.accentFallback.opacity(0.08) : Color.clear
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(SBSColors.surfaceFallback.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
            .padding(.top, 2)
        }
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
            VStack(spacing: SBSLayout.sectionSpacing) {
                // Header
                VStack(spacing: SBSLayout.paddingSmall) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(SBSColors.accentFallback)
                    
                    Text("Add Custom Exercise")
                        .font(SBSFonts.title())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Create your own exercise to track")
                        .font(SBSFonts.body())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .padding(.top, SBSLayout.paddingLarge)
                
                // Name input
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    Text("Exercise Name")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    TextField("e.g., Chest Flyes, Hip Thrust", text: $name)
                        .font(SBSFonts.body())
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .fill(SBSColors.surfaceFallback)
                        )
                        .focused($isNameFocused)
                }
                .padding(.horizontal)
                
                // Body part picker
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    Text("Body Part (optional)")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: SBSLayout.paddingSmall) {
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
                
                // Add button
                Button {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    saveCustomExercise(trimmedName)
                    onAdd(trimmedName)
                } label: {
                    Text("Add Exercise")
                        .font(SBSFonts.button())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingMedium)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .fill(isValid ? SBSColors.accentFallback : SBSColors.surfaceFallback)
                        )
                }
                .disabled(!isValid)
                .padding(.horizontal)
                .padding(.bottom, SBSLayout.paddingLarge)
            }
            .sbsBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundStyle(SBSColors.textSecondaryFallback)
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

struct BodyPartChip: View {
    let bodyPart: BodyPart
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var chipColor: Color {
        switch bodyPart.color {
        case "red": return .red
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "indigo": return .indigo
        case "mint": return .mint
        default: return .gray
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Image(systemName: bodyPart.icon)
                    .font(.system(size: 12))
                Text(bodyPart.rawValue)
                    .font(SBSFonts.captionBold())
            }
            .foregroundStyle(isSelected ? .white : SBSColors.textPrimaryFallback)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? chipColor : SBSColors.surfaceFallback)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(SBSFonts.captionBold())
            }
            .foregroundStyle(isSelected ? .white : SBSColors.textPrimaryFallback)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? SBSColors.accentFallback : SBSColors.surfaceFallback)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : SBSColors.textTertiaryFallback.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    AccessoryExercisePickerSheet(
        title: "Select Exercise",
        onSelect: { print("Selected: \($0)") },
        onCancel: { },
        showFilterChips: true
    )
}

