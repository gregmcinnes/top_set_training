import SwiftUI

// MARK: - My Bars (Settings)

/// Pro: the lifter's own bars and which exercise uses which. The plate calculator
/// loads plates onto the assigned bar; everything else uses the standard bar.
struct BarsSettingsView: View {
    @Bindable var appState: AppState
    @State private var editing: BarEditTarget?

    private var useMetric: Bool { appState.settings.useMetric }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Standard barbell")
                    Spacer()
                    Text(appState.settings.barWeight.formattedWeight(useMetric: useMetric))
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)
                }
                .accessibilityElement(children: .combine)

                ForEach(appState.settings.bars) { bar in
                    Button {
                        editing = BarEditTarget(bar: bar)
                    } label: {
                        HStack {
                            Text(bar.name)
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Text(bar.weight.formattedWeight(useMetric: useMetric))
                                .font(SBSFonts.numberSmall())
                                .foregroundStyle(Color.inkSecondary)
                            Image(systemName: "chevron.right")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit this bar")
                }
                .onDelete { offsets in
                    let ids = offsets.map { appState.settings.bars[$0].id }
                    ids.forEach { appState.settings.removeBar(id: $0) }
                }

                Button {
                    editing = BarEditTarget(bar: nil)
                } label: {
                    Label("Add Bar", systemImage: "plus")
                        .foregroundStyle(Color.orangeText)
                }
            } header: {
                SBSListHeader("Bars")
            } footer: {
                SBSListFooter("The standard barbell is set under Units & Rounding. Swipe a bar to delete it.")
            }
            .sbsListRows()

            let exercises = appState.barAssignableExercises
            if !exercises.isEmpty {
                Section {
                    ForEach(exercises, id: \.name) { exercise in
                        Picker(exercise.name, selection: assignmentBinding(for: exercise.name)) {
                            Text("Standard (\(appState.settings.barWeight.formattedWeight(useMetric: useMetric)))")
                                .tag(UUID?.none)
                            ForEach(appState.settings.bars) { bar in
                                Text("\(bar.name) (\(bar.weight.formattedWeight(useMetric: useMetric)))")
                                    .tag(UUID?.some(bar.id))
                            }
                        }
                        .sbsValuePicker()
                        .disabled(appState.settings.bars.isEmpty)
                    }
                } header: {
                    SBSListHeader("Exercises")
                } footer: {
                    SBSListFooter(appState.settings.bars.isEmpty
                        ? "Add a bar above, then choose which exercises use it."
                        : "Accessories show plates once they have a bar.")
                }
                .sbsListRows()
            }
        }
        .sbsGroupedList()
        .navigationTitle("My Bars")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            BarEditSheet(
                bar: target.bar,
                useMetric: useMetric,
                onSave: { bar in
                    appState.settings.upsertBar(bar)
                    editing = nil
                },
                onDelete: target.bar.map { bar in
                    {
                        appState.settings.removeBar(id: bar.id)
                        editing = nil
                    }
                },
                onCancel: { editing = nil }
            )
        }
    }

    private func assignmentBinding(for exercise: String) -> Binding<UUID?> {
        Binding(
            get: { appState.settings.assignedBar(for: exercise)?.id },
            set: { appState.settings.assignBar($0, to: exercise) }
        )
    }
}

/// Sheet identity for adding (nil bar) or editing a bar
struct BarEditTarget: Identifiable {
    let id = UUID()
    let bar: CustomBar?
}

// MARK: - Add / Edit Bar

struct BarEditSheet: View {
    let bar: CustomBar?
    let useMetric: Bool
    let onSave: (CustomBar) -> Void
    var onDelete: (() -> Void)? = nil
    let onCancel: () -> Void

    @State private var name = ""
    @State private var weightText = ""

    /// Common bars, in each unit's usual weight (lb, kg)
    private static let presets: [(name: String, lb: Double, kg: Double)] = [
        ("EZ Curl Bar", 25, 10),
        ("Hex Bar", 60, 25),
        ("Safety Squat Bar", 65, 30),
        ("Women's Bar", 35, 15),
    ]

    private var weight: Double? {
        guard let value = parseDecimalInput(weightText), value > 0 else { return nil }
        return value.poundsFromInput(useMetric: useMetric)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedName.isEmpty && weight != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    HStack {
                        TextField("Weight", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(SBSFonts.numberUnit())
                        Text(useMetric ? "kg" : "lb")
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)
                    }
                } header: {
                    SBSListHeader("Bar")
                }
                .sbsListRows()

                if bar == nil {
                    Section {
                        ForEach(Self.presets, id: \.name) { preset in
                            let value = useMetric ? preset.kg : preset.lb
                            Button {
                                name = preset.name
                                weightText = value.formatted()
                            } label: {
                                HStack {
                                    Text(preset.name).foregroundStyle(Color.ink)
                                    Spacer()
                                    Text("\(value.formatted()) \(useMetric ? "kg" : "lb")")
                                        .font(SBSFonts.numberSmall())
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        SBSListHeader("Common Bars")
                    } footer: {
                        SBSListFooter("Bars vary by maker. Check yours and adjust the weight.")
                    }
                    .sbsListRows()
                }

                if let onDelete {
                    Section {
                        Button("Delete Bar", role: .destructive, action: onDelete)
                    } footer: {
                        SBSListFooter("Exercises using this bar go back to the standard barbell.")
                    }
                    .sbsListRows()
                }
            }
            .sbsGroupedList()
            .navigationTitle(bar == nil ? "New Bar" : "Edit Bar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let weight else { return }
                        onSave(CustomBar(id: bar?.id ?? UUID(), name: trimmedName, weight: weight))
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if let bar {
                name = bar.name
                let shown = useMetric ? bar.weight / BarWeightOptions.lbPerKg : bar.weight
                weightText = ((shown * 10).rounded() / 10).formatted()
            }
        }
    }
}

// MARK: - Bar Picker (in workout)

/// Choose the bar for one exercise. Pushed inside a sheet's NavigationStack, or
/// wrapped in one by `BarPickerSheet`.
struct BarPickerList: View {
    @Bindable var appState: AppState
    /// `lift ?? name`, as `WorkoutExercise.barKeySource`
    let exercise: String
    var onPicked: (() -> Void)? = nil

    @State private var addingBar = false

    private var useMetric: Bool { appState.settings.useMetric }
    private var selectedID: UUID? { appState.settings.assignedBar(for: exercise)?.id }

    var body: some View {
        List {
            Section {
                row(title: "Standard barbell", weight: appState.settings.barWeight, isSelected: selectedID == nil) {
                    appState.settings.assignBar(nil, to: exercise)
                    onPicked?()
                }
                ForEach(appState.settings.bars) { bar in
                    row(title: bar.name, weight: bar.weight, isSelected: selectedID == bar.id) {
                        appState.settings.assignBar(bar.id, to: exercise)
                        onPicked?()
                    }
                }
                Button {
                    addingBar = true
                } label: {
                    Label("New Bar", systemImage: "plus")
                        .foregroundStyle(Color.orangeText)
                }
            } header: {
                SBSListHeader(exercise)
            } footer: {
                SBSListFooter("Used for this exercise's plates in every workout. Manage bars in Settings › My Bars.")
            }
            .sbsListRows()
        }
        .sbsGroupedList()
        .navigationTitle("Bar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingBar) {
            BarEditSheet(
                bar: nil,
                useMetric: useMetric,
                onSave: { bar in
                    appState.settings.upsertBar(bar)
                    appState.settings.assignBar(bar.id, to: exercise)
                    addingBar = false
                    onPicked?()
                },
                onCancel: { addingBar = false }
            )
        }
    }

    private func row(title: String, weight: Double, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Color.ink)
                Spacer()
                Text(weight.formattedWeight(useMetric: useMetric))
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
                Image(systemName: "checkmark")
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.orangeText)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// `BarPickerList` as its own sheet, for the bar caption on the live set card
struct BarPickerSheet: View {
    @Bindable var appState: AppState
    let exercise: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BarPickerList(appState: appState, exercise: exercise, onPicked: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
