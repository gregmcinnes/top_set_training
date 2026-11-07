import SwiftUI

// MARK: - Main Calculators View

struct CalculatorsView: View {
    @Bindable var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SBSLayout.space6) {
                    // One hairline group of calculators
                    VStack(spacing: 0) {
                        NavigationLink {
                            OneRepMaxCalculatorView(useMetric: appState.settings.useMetric)
                        } label: {
                            CalculatorCard(
                                icon: "trophy",
                                title: "One-Rep Max",
                                description: "Estimate your 1RM from submaximal lifts"
                            )
                        }
                        .buttonStyle(.plain)

                        SBSRowDivider()

                        NavigationLink {
                            RPECalculatorView(useMetric: appState.settings.useMetric)
                        } label: {
                            CalculatorCard(
                                icon: "gauge.with.needle",
                                title: "RPE Calculator",
                                description: "Find weights for target RPE levels"
                            )
                        }
                        .buttonStyle(.plain)

                        SBSRowDivider()

                        NavigationLink {
                            StandalonePlateCalculatorView(
                                useMetric: appState.settings.useMetric,
                                defaultBarWeight: appState.settings.barWeight
                            )
                        } label: {
                            CalculatorCard(
                                icon: "circle.grid.2x1",
                                title: "Plate Calculator",
                                description: "Visualize which plates to load"
                            )
                        }
                        .buttonStyle(.plain)

                        SBSRowDivider()

                        NavigationLink {
                            TrainingMaxCalculatorView(useMetric: appState.settings.useMetric)
                        } label: {
                            CalculatorCard(
                                icon: "percent",
                                title: "Training Max",
                                description: "Calculate TM and percentage charts"
                            )
                        }
                        .buttonStyle(.plain)

                        SBSRowDivider()

                        NavigationLink {
                            StrengthScoresView(
                                useMetric: appState.settings.useMetric,
                                appState: appState
                            )
                        } label: {
                            CalculatorCard(
                                icon: "medal",
                                title: "Strength Scores",
                                description: "WILKS, DOTS & IPF GL Points"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .card()
                    .padding(.horizontal)

                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .sbsBackground()
            .navigationTitle("Calculators")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Calculator Card

/// A calculator in the hub's hairline group: an ink glyph on a hairline cell,
/// title, description, chevron.
struct CalculatorCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        SBSListRow(title, showsChevron: true) {
            Image(systemName: icon)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.ink)
                .frame(width: 40, height: 40)
                .selectionCell(false)
                .accessibilityHidden(true)
        } subtitle: {
            Text(description)
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        } trailing: {
            EmptyView()
        }
    }
}

// MARK: - Shared calculator pieces

/// A calculator section: an eyebrow (with an optional trailing value in
/// number-small) over a padded hairline card.
private struct CalculatorSection<Content: View>: View {
    let title: String
    var value: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow(title) {
                if let value {
                    Text(value)
                        .font(SBSFonts.numberSmall().weight(.semibold))
                        .foregroundStyle(Color.ink)
                }
            }
            VStack(alignment: .leading, spacing: SBSLayout.space3) {
                content
            }
            .padding(SBSLayout.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .padding(.horizontal)
    }
}

/// A calculator's answer: eyebrow, the number in the timer numeral with its unit
/// in number-unit beside it, and a caption. Ink on a hairline card: the value is
/// the hero, so it carries no orange.
private struct CalculatorResult: View {
    let label: String
    let value: String
    let unit: String?
    var caption: String? = nil

    var body: some View {
        VStack(spacing: SBSLayout.space2) {
            SBSEyebrow(label)
                .foregroundStyle(Color.inkSecondary)

            HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space1) {
                Text(value)
                    .font(SBSFonts.timer())
                    .foregroundStyle(Color.ink)
                if let unit {
                    Text(unit)
                        .font(SBSFonts.numberUnit())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            // The numeral shrinks rather than wraps
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            if let caption {
                Text(caption)
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SBSLayout.space6)
        .padding(.horizontal, SBSLayout.space4)
        .card()
        .accessibilityElement(children: .combine)
        .padding(.horizontal)
    }
}

/// A selectable number: number-small on a hairline cell, orange-soft with an
/// orange-text edge when selected. Text stays ink.
private struct CalculatorNumberChip: View {
    let title: String
    let isSelected: Bool
    var minWidth: CGFloat? = nil
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(SBSFonts.numberSmall().weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, SBSLayout.space2)
                .frame(minWidth: minWidth, maxWidth: minWidth == nil ? .infinity : nil, minHeight: 44)
                .selectionCell(isSelected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A numeric field on a bg cell with its unit beside it.
private struct CalculatorNumberField: View {
    let placeholder: String
    @Binding var text: String
    var unit: String? = nil
    var keyboard: UIKeyboardType = .decimalPad
    var alignment: TextAlignment = .center

    var body: some View {
        HStack(spacing: SBSLayout.space2) {
            TextField(placeholder, text: $text)
                .font(SBSFonts.numberLarge())
                .foregroundStyle(Color.ink)
                .keyboardType(keyboard)
                .multilineTextAlignment(alignment)
            if let unit {
                Text(unit)
                    .font(SBSFonts.numberUnit())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .sbsFieldCell()
    }
}

/// "How it works" footnote: an eyebrow with an ink-secondary glyph, then caption text.
private struct CalculatorInfo: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            HStack(spacing: SBSLayout.space2) {
                Image(systemName: "info.circle")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .accessibilityHidden(true)
                SBSEyebrow(title)
                    .foregroundStyle(Color.inkSecondary)
                    .accessibilityAddTraits(.isHeader)
            }

            Text(text)
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SBSLayout.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal)
    }
}

/// The calculator's one primary action, with room for the hard shadow.
private struct CalculatorPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SBSButtonTitle(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SBSPrimaryButtonStyle())
        .padding(.trailing, SBSLayout.hardShadowOffset)
        .padding(.horizontal)
    }
}

/// Columns for a number grid: `count` normally, fewer at the accessibility sizes.
private func calculatorColumns(_ count: Int, accessibilityCount: Int = 1, dynamicTypeSize: DynamicTypeSize) -> [GridItem] {
    let n = dynamicTypeSize.isAccessibilitySize ? accessibilityCount : count
    return Array(repeating: GridItem(.flexible(), spacing: SBSLayout.space2), count: n)
}

/// A weight and its unit, split so the number and the unit can take different styles.
private func splitWeight(_ text: String) -> (value: String, unit: String?) {
    let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
    return (parts.first ?? text, parts.count > 1 ? parts[1] : nil)
}

// MARK: - One-Rep Max Calculator

struct OneRepMaxCalculatorView: View {
    let useMetric: Bool

    @State private var weight: String = ""
    @State private var reps: String = ""
    @State private var showResults = false
    @FocusState private var focusedField: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum Field {
        case weight, reps
    }

    private var weightValue: Double? {
        parseDecimalInput(weight)
    }

    private var repsValue: Int? {
        Int(reps)
    }

    private var canCalculate: Bool {
        guard let w = weightValue, let r = repsValue else { return false }
        return w > 0 && r > 0 && r <= 30
    }

    // Different formulas for calculating 1RM
    private var results: [(name: String, value: Double, description: String)] {
        guard let w = weightValue, let r = repsValue, r > 0 else { return [] }

        let repsDouble = Double(r)

        let estimates: [(name: String, value: Double, description: String)] = [
            ("Epley", w * (1 + repsDouble / 30.0), "Most common formula"),
            ("Brzycki", w * (36.0 / (37.0 - repsDouble)), "Popular for lower reps"),
            ("Lombardi", w * pow(repsDouble, 0.10), "Simple power formula"),
            ("Mayhew", w * (100.0 / (52.2 + 41.9 * exp(-0.055 * repsDouble))), "Research-based"),
            ("O'Conner", w * (1 + 0.025 * repsDouble), "Conservative estimate"),
            ("Wathan", w * (100.0 / (48.8 + 53.8 * exp(-0.075 * repsDouble))), "Football-based")
        ]
        // A single rep already is a 1RM, whatever each formula predicts for it.
        if r == 1 {
            return estimates.map { ($0.name, w, $0.description) }
        }
        // Brzycki divides by (37 - reps), so it goes infinite or negative at high reps.
        return estimates.filter { $0.value.isFinite && $0.value > 0 }
    }

    private var averageE1RM: Double? {
        guard !results.isEmpty else { return nil }
        return results.map { $0.value }.reduce(0, +) / Double(results.count)
    }

    private var unit: String {
        useMetric ? "kg" : "lb"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SBSLayout.space6) {
                // Input section
                inputSection

                // Calculate button: the screen's one primary action
                if canCalculate {
                    CalculatorPrimaryButton(title: "Calculate") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showResults = true
                        }
                        focusedField = nil
                    }
                }

                // Results section
                if showResults && canCalculate {
                    resultsSection
                }

                // Info section
                CalculatorInfo(
                    title: "How it works",
                    text: "Enter a weight and the number of reps you completed. The calculator uses multiple formulas to estimate your one-rep max. Results are most accurate for 1-10 reps; higher rep ranges become less reliable."
                )

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .scrollDismissesKeyboard(.interactively)
        .sbsBackground()
        .navigationTitle("One-Rep Max")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: weight) { _, _ in
            showResults = false
        }
        .onChange(of: reps) { _, _ in
            showResults = false
        }
    }

    private var inputSection: some View {
        CalculatorSection(title: "Enter your lift") {
            HStack(alignment: .bottom, spacing: SBSLayout.space3) {
                // Weight input
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    SBSEyebrow("Weight (\(unit))")
                        .foregroundStyle(Color.inkSecondary)

                    CalculatorNumberField(placeholder: "0", text: $weight)
                        .focused($focusedField, equals: .weight)
                }

                Text("×")
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.bottom, SBSLayout.space3)
                    .accessibilityHidden(true)

                // Reps input
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    SBSEyebrow("Reps")
                        .foregroundStyle(Color.inkSecondary)

                    CalculatorNumberField(placeholder: "0", text: $reps, keyboard: .numberPad)
                        .focused($focusedField, equals: .reps)
                }
            }
        }
    }

    private var resultsSection: some View {
        VStack(spacing: SBSLayout.space6) {
            // Average estimate: the hero
            if let avg = averageE1RM {
                let split = splitWeight(formatWeight(avg))
                CalculatorResult(
                    label: "Estimated 1RM",
                    value: split.value,
                    unit: split.unit,
                    caption: "Average of all formulas"
                )
            }

            // Individual formula results
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                SBSSectionEyebrow("By formula")

                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.name) { index, result in
                        if index > 0 { SBSRowDivider() }
                        SBSListRow(result.name) {
                            Text(result.description)
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                        } trailing: {
                            Text(formatWeight(result.value))
                                .font(SBSFonts.number())
                                .foregroundStyle(Color.ink)
                        }
                    }
                }
                .card()
            }
            .padding(.horizontal)

            // Training percentages
            if let avg = averageE1RM {
                trainingPercentagesSection(e1rm: avg)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func trainingPercentagesSection(e1rm: Double) -> some View {
        CalculatorSection(title: "Training percentages") {
            LazyVGrid(
                columns: calculatorColumns(3, accessibilityCount: 2, dynamicTypeSize: dynamicTypeSize),
                spacing: SBSLayout.space2
            ) {
                ForEach([95, 90, 85, 80, 75, 70, 65, 60], id: \.self) { percentage in
                    VStack(spacing: 2) {
                        Text("\(percentage)%")
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)

                        Text(formatWeight(e1rm * Double(percentage) / 100.0))
                            .font(SBSFonts.numberSmall().weight(.semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SBSLayout.space2)
                    .selectionCell(false)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f \(unit)", weight)
        }
        return String(format: "%.1f \(unit)", weight)
    }
}

// MARK: - RPE Calculator

struct RPECalculatorView: View {
    let useMetric: Bool

    @State private var e1rm: String = ""
    @State private var targetReps: Int = 5
    @State private var selectedRPE: Double = 8.0
    @FocusState private var isE1RMFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var e1rmValue: Double? {
        parseDecimalInput(e1rm)
    }

    private var unit: String {
        useMetric ? "kg" : "lb"
    }

    // RPE percentage table (based on Mike Tuchscherer's research)
    // Rows: reps (1-12), Columns: RPE (6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10)
    private let rpeTable: [[Double]] = [
        // 1 rep
        [0.88, 0.89, 0.91, 0.92, 0.94, 0.96, 0.98, 1.00],
        // 2 reps
        [0.85, 0.86, 0.88, 0.89, 0.91, 0.92, 0.94, 0.96],
        // 3 reps
        [0.82, 0.84, 0.85, 0.86, 0.88, 0.89, 0.91, 0.92],
        // 4 reps
        [0.79, 0.81, 0.82, 0.84, 0.85, 0.86, 0.88, 0.89],
        // 5 reps
        [0.77, 0.78, 0.79, 0.81, 0.82, 0.84, 0.85, 0.86],
        // 6 reps
        [0.74, 0.75, 0.77, 0.78, 0.79, 0.81, 0.82, 0.84],
        // 7 reps
        [0.71, 0.73, 0.74, 0.75, 0.77, 0.78, 0.79, 0.81],
        // 8 reps
        [0.68, 0.70, 0.71, 0.73, 0.74, 0.75, 0.77, 0.78],
        // 9 reps
        [0.65, 0.67, 0.68, 0.70, 0.71, 0.73, 0.74, 0.75],
        // 10 reps
        [0.63, 0.65, 0.66, 0.67, 0.68, 0.70, 0.71, 0.73],
        // 11 reps
        [0.60, 0.62, 0.63, 0.65, 0.66, 0.67, 0.68, 0.70],
        // 12 reps
        [0.58, 0.60, 0.61, 0.62, 0.63, 0.65, 0.66, 0.67]
    ]

    private let rpeValues: [Double] = [6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0]

    private func percentageFor(reps: Int, rpe: Double) -> Double {
        let repsIndex = min(max(reps - 1, 0), 11)
        let rpeIndex = rpeValues.firstIndex(of: rpe) ?? 3
        return rpeTable[repsIndex][rpeIndex]
    }

    private var calculatedWeight: Double? {
        guard let e1rm = e1rmValue else { return nil }
        let percentage = percentageFor(reps: targetReps, rpe: selectedRPE)
        return e1rm * percentage
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SBSLayout.space6) {
                // E1RM input
                e1rmInputSection

                // Reps selector
                repsSection

                // RPE selector
                rpeSection

                // Result
                if let weight = calculatedWeight {
                    resultSection(weight: weight)
                }

                // RPE table
                rpeTableSection

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .scrollDismissesKeyboard(.interactively)
        .sbsBackground()
        .navigationTitle("RPE Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var e1rmInputSection: some View {
        CalculatorSection(title: "Your estimated 1RM") {
            CalculatorNumberField(placeholder: "Enter E1RM", text: $e1rm, unit: unit)
                .focused($isE1RMFocused)

            Text("Use the 1RM Calculator if you don't know your estimated max")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        }
    }

    private var repsSection: some View {
        CalculatorSection(title: "Target reps", value: "\(targetReps)") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SBSLayout.space2) {
                    ForEach(1...12, id: \.self) { rep in
                        CalculatorNumberChip(
                            title: "\(rep)",
                            isSelected: targetReps == rep,
                            minWidth: 44,
                            accessibilityLabel: "\(rep) reps"
                        ) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                targetReps = rep
                            }
                        }
                    }
                }
                // Room for the selected cell's edge
                .padding(.vertical, 1)
            }
        }
    }

    private var rpeSection: some View {
        CalculatorSection(title: "Target RPE", value: String(format: "%.1f", selectedRPE)) {
            Text(rpeDescription(selectedRPE))
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)

            LazyVGrid(
                columns: calculatorColumns(4, accessibilityCount: 2, dynamicTypeSize: dynamicTypeSize),
                spacing: SBSLayout.space2
            ) {
                ForEach(rpeValues, id: \.self) { rpe in
                    CalculatorNumberChip(
                        title: String(format: "%.1f", rpe),
                        isSelected: selectedRPE == rpe,
                        accessibilityLabel: "RPE \(String(format: "%.1f", rpe))"
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedRPE = rpe
                        }
                    }
                }
            }
        }
    }

    private func resultSection(weight: Double) -> some View {
        let percentage = percentageFor(reps: targetReps, rpe: selectedRPE)
        let split = splitWeight(formatWeight(weight))
        return CalculatorResult(
            label: "Target weight",
            value: split.value,
            unit: split.unit,
            caption: "\(Int((percentage * 100).rounded()))% of E1RM · \(targetReps) reps @ RPE \(String(format: "%.1f", selectedRPE))"
        )
    }

    private var rpeTableSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("RPE reference")

            VStack(spacing: 0) {
                ForEach(Array([10.0, 9.5, 9.0, 8.5, 8.0, 7.5, 7.0, 6.5].enumerated()), id: \.element) { index, rpe in
                    if index > 0 { SBSRowDivider() }
                    HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space3) {
                        Text(String(format: "%.1f", rpe))
                            .font(SBSFonts.number())
                            .foregroundStyle(Color.ink)
                            .frame(minWidth: 48, alignment: .leading)

                        Text(rpeFullDescription(rpe))
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, SBSLayout.space2)
                    .padding(.horizontal, SBSLayout.space4)
                    // The selected RPE's row: orange-soft, as in the selector
                    .background(rpe == selectedRPE ? Color.orangeSoft : Color.clear)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(rpe == selectedRPE ? [.isSelected] : [])
                }
            }
            .card()
        }
        .padding(.horizontal)
    }

    private func rpeDescription(_ rpe: Double) -> String {
        switch rpe {
        case 10: return "Max effort"
        case 9.5: return "Maybe 1 more"
        case 9: return "1 rep left"
        case 8.5: return "1-2 reps left"
        case 8: return "2 reps left"
        case 7.5: return "2-3 reps left"
        case 7: return "3 reps left"
        default: return "3+ reps left"
        }
    }

    private func rpeFullDescription(_ rpe: Double) -> String {
        switch rpe {
        case 10: return "Maximum effort, no reps left in the tank"
        case 9.5: return "Could maybe get 1 more rep"
        case 9: return "Could definitely get 1 more rep"
        case 8.5: return "Could get 1-2 more reps"
        case 8: return "Could get 2 more reps"
        case 7.5: return "Could get 2-3 more reps"
        case 7: return "Could get 3 more reps"
        default: return "Could get 3-4+ more reps"
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f \(unit)", weight)
        }
        return String(format: "%.1f \(unit)", weight)
    }
}

// MARK: - Standalone Plate Calculator

struct StandalonePlateCalculatorView: View {
    let useMetric: Bool
    let defaultBarWeight: Double

    @State private var targetWeight: String = ""
    @State private var barWeight: Double
    @FocusState private var isWeightFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(useMetric: Bool, defaultBarWeight: Double) {
        self.useMetric = useMetric
        self.defaultBarWeight = defaultBarWeight
        _barWeight = State(initialValue: defaultBarWeight)
    }

    private var targetWeightValue: Double {
        parseDecimalInput(targetWeight) ?? 0
    }

    // PlateCalculator/BarbellView work internally in lb. The text field holds
    // the user's unit (kg when metric), so convert to lb before computing.
    private var targetWeightLb: Double {
        useMetric ? targetWeightValue / 0.45359237 : targetWeightValue
    }

    private var unit: String {
        useMetric ? "kg" : "lb"
    }

    // Bar weights are stored in lb; metric values are lb-equivalents of 20/15/10 kg.
    private var commonBarWeights: [Double] {
        useMetric ? [44.0, 33.0, 22.0] : [45, 35, 25, 15]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SBSLayout.space6) {
                // Weight input
                weightInputSection

                // Barbell visualization: the full bar, right under the number it loads
                if targetWeightValue > 0 {
                    barbellSection
                }

                // Bar weight selector
                barWeightSection

                // Quick weights
                quickWeightsSection

                // Plate legend
                PlateLegendView(useMetric: useMetric)
                    .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .scrollDismissesKeyboard(.interactively)
        .sbsBackground()
        .navigationTitle("Plate Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var weightInputSection: some View {
        CalculatorSection(title: "Total weight") {
            CalculatorNumberField(placeholder: "0", text: $targetWeight, unit: unit)
                .focused($isWeightFocused)
        }
    }

    private var barWeightSection: some View {
        CalculatorSection(title: "Bar weight", value: formatWeightFromLb(barWeight)) {
            LazyVGrid(
                columns: calculatorColumns(4, accessibilityCount: 2, dynamicTypeSize: dynamicTypeSize),
                spacing: SBSLayout.space2
            ) {
                ForEach(commonBarWeights, id: \.self) { weight in
                    CalculatorNumberChip(
                        title: formatWeightFromLb(weight),
                        isSelected: abs(barWeight - weight) < 0.5
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            barWeight = weight
                        }
                    }
                }
            }
        }
    }

    /// The full barbell: BarbellView draws the bar, the plates heaviest first,
    /// the "45 · 45 · 10 per side · 245 lb total" line and the short-load warning.
    private var barbellSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("Load")

            BarbellView(
                weight: targetWeightLb,
                useMetric: useMetric,
                barWeight: barWeight,
                showLabels: true,
                compact: false
            )
            .padding(.vertical, SBSLayout.space4)
            .padding(.horizontal, SBSLayout.space2)
            .frame(maxWidth: .infinity)
            .card()
        }
        .padding(.horizontal)
    }

    private var quickWeightsSection: some View {
        let quickWeights: [Double] = useMetric
            ? [60, 80, 100, 120, 140, 160, 180, 200]
            : [135, 185, 225, 275, 315, 365, 405, 455]

        return CalculatorSection(title: "Quick select") {
            LazyVGrid(
                columns: calculatorColumns(4, accessibilityCount: 2, dynamicTypeSize: dynamicTypeSize),
                spacing: SBSLayout.space2
            ) {
                ForEach(quickWeights, id: \.self) { weight in
                    CalculatorNumberChip(
                        title: formatWeightShort(weight),
                        isSelected: abs(targetWeightValue - weight) < 0.01,
                        accessibilityLabel: "\(formatWeightShort(weight)) \(unit)"
                    ) {
                        targetWeight = formatWeightShort(weight)
                        isWeightFocused = false
                    }
                }
            }
        }
    }

    // Converts an internal lb weight (bar, plate remainder) to the display unit.
    private func formatWeightFromLb(_ lb: Double) -> String {
        if useMetric {
            let kg = (lb * 0.45359237 / 0.25).rounded() * 0.25
            return String(format: "%g kg", kg)
        }
        if lb.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f lb", lb)
        }
        return String(format: "%.1f lb", lb)
    }

    private func formatWeightShort(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", weight)
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - Training Max Calculator

struct TrainingMaxCalculatorView: View {
    let useMetric: Bool

    @State private var actualMax: String = ""
    @State private var tmPercentage: Double = 90
    @FocusState private var isMaxFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var actualMaxValue: Double? {
        parseDecimalInput(actualMax)
    }

    private var trainingMax: Double? {
        guard let max = actualMaxValue else { return nil }
        return max * (tmPercentage / 100.0)
    }

    private var unit: String {
        useMetric ? "kg" : "lb"
    }

    // Common TM percentages used in different programs
    private let tmPercentages: [(value: Double, program: String)] = [
        (85, "Conservative / 5/3/1 BBB"),
        (90, "Standard / 5/3/1"),
        (92.5, "Moderate"),
        (95, "Aggressive")
    ]

    // Percentages to show in the chart
    private let chartPercentages = [100, 95, 90, 85, 80, 75, 70, 65, 60, 55, 50]

    var body: some View {
        ScrollView {
            VStack(spacing: SBSLayout.space6) {
                // Actual max input
                actualMaxSection

                // TM percentage selector
                tmPercentageSection

                // Training max result
                if let tm = trainingMax {
                    trainingMaxResultSection(tm: tm)
                }

                // Percentage chart
                if let tm = trainingMax {
                    percentageChartSection(tm: tm)
                    programmingSection(tm: tm)
                }

                // Info section
                CalculatorInfo(
                    title: "What is a training max?",
                    text: "A Training Max (TM) is a percentage of your true 1RM used for programming. Using a TM (typically 85-90%) instead of your actual max allows for better bar speed, reduced injury risk, and room to progress over time. Most percentage-based programs calculate weights from your TM, not your true max."
                )

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .scrollDismissesKeyboard(.interactively)
        .sbsBackground()
        .navigationTitle("Training Max")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var actualMaxSection: some View {
        CalculatorSection(title: "Your actual 1RM") {
            CalculatorNumberField(placeholder: "Enter 1RM", text: $actualMax, unit: unit)
                .focused($isMaxFocused)

            Text("Your tested or estimated one-rep max")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        }
    }

    private var tmPercentageSection: some View {
        CalculatorSection(title: "TM percentage", value: "\(String(format: "%g", tmPercentage))%") {
            // Slider
            Slider(value: $tmPercentage, in: 80...100, step: 2.5)
                .tint(Color.orangeText)

            // Quick select buttons
            LazyVGrid(
                columns: calculatorColumns(4, accessibilityCount: 2, dynamicTypeSize: dynamicTypeSize),
                spacing: SBSLayout.space2
            ) {
                ForEach(tmPercentages, id: \.value) { preset in
                    CalculatorNumberChip(
                        title: "\(String(format: "%g", preset.value))%",
                        isSelected: tmPercentage == preset.value
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            tmPercentage = preset.value
                        }
                    }
                }
            }

            // Show which program uses this percentage
            if let matchingPreset = tmPercentages.first(where: { $0.value == tmPercentage }) {
                Text(matchingPreset.program)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private func trainingMaxResultSection(tm: Double) -> some View {
        let split = splitWeight(formatWeight(tm))
        return CalculatorResult(
            label: "Training max",
            value: split.value,
            unit: split.unit,
            caption: actualMaxValue.map { "\(String(format: "%g", tmPercentage))% of \(formatWeight($0))" }
        )
    }

    /// The percentage chart: ink rows, the 100% row (the TM itself) highlighted
    /// orange with orange-ink text.
    private func percentageChartSection(tm: Double) -> some View {
        CalculatorSection(title: "Percentage chart · of TM") {
            LazyVGrid(
                columns: calculatorColumns(2, accessibilityCount: 1, dynamicTypeSize: dynamicTypeSize),
                spacing: SBSLayout.space2
            ) {
                ForEach(chartPercentages, id: \.self) { percentage in
                    let weight = tm * Double(percentage) / 100.0
                    let isTM = percentage == 100

                    HStack(spacing: SBSLayout.space2) {
                        Text("\(percentage)%")
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(isTM ? Color.orangeInk : Color.inkSecondary)

                        Spacer(minLength: SBSLayout.space1)

                        Text(formatWeight(weight))
                            .font(SBSFonts.numberSmall().weight(.semibold))
                            .foregroundStyle(isTM ? Color.orangeInk : Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, SBSLayout.space3)
                    .frame(minHeight: 40)
                    .background(isTM ? Color.orangeFill : Color.surface, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                            .strokeBorder(isTM ? Color.ink : Color.hairline, lineWidth: SBSLayout.strokeHairline)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(isTM ? "\(percentage)%, your training max, \(formatWeight(weight))" : "\(percentage)%, \(formatWeight(weight))")
                }
            }
        }
    }

    private func programmingSection(tm: Double) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("Common programming")

            VStack(spacing: 0) {
                programmingRow(name: "5/3/1 Week 1 (5s)", percentage: 85, tm: tm)
                SBSRowDivider()
                programmingRow(name: "5/3/1 Week 2 (3s)", percentage: 90, tm: tm)
                SBSRowDivider()
                programmingRow(name: "5/3/1 Week 3 (5/3/1)", percentage: 95, tm: tm)
                SBSRowDivider()
                programmingRow(name: "Joker Sets", percentage: 100, tm: tm)
            }
            .card()
        }
        .padding(.horizontal)
    }

    private func programmingRow(name: String, percentage: Int, tm: Double) -> some View {
        let weight = tm * Double(percentage) / 100.0

        return SBSListRow(name) {
            SBSRowSubtitle("\(percentage)% of TM")
        } trailing: {
            Text(formatWeight(weight))
                .font(SBSFonts.number())
                .foregroundStyle(Color.ink)
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        // Round to nearest 2.5 (or 1 for metric)
        let roundingIncrement = useMetric ? 1.0 : 2.5
        let rounded = (weight / roundingIncrement).rounded() * roundingIncrement

        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f \(unit)", rounded)
        }
        return String(format: "%.1f \(unit)", rounded)
    }
}

// MARK: - Age Category for Competitive Data

/// Age categories available in OpenPowerlifting data
enum AgeCategory: String, CaseIterable, Identifiable {
    case allAges = "all_ages"
    case junior = "junior"
    case open = "open"
    case masters40 = "masters_40"
    case masters50 = "masters_50"
    case masters60 = "masters_60"
    case masters70 = "masters_70"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .allAges: return "All Ages"
        case .junior: return "Junior (U23)"
        case .open: return "Open (23-39)"
        case .masters40: return "Masters 40+"
        case .masters50: return "Masters 50+"
        case .masters60: return "Masters 60+"
        case .masters70: return "Masters 70+"
        }
    }
    
    var jsonKey: String { rawValue }
}

// MARK: - Competitive Lifting Data (OpenPowerlifting)

/// Loads and provides access to competitive powerlifting percentile data
class CompetitiveLiftingData {
    static let shared = CompetitiveLiftingData()
    
    private var data: PowerliftingPercentileData?
    private(set) var loadError: String?
    
    /// Whether competitive data is available
    var isLoaded: Bool { data != nil }
    
    /// Get lifter count from metadata
    var lifterCount: Int { data?.metadata.lifterCount ?? 0 }
    
    // Weight classes in kg
    private let maleWeightClasses: [Double] = [59, 66, 74, 83, 93, 105, 120, 140]
    private let femaleWeightClasses: [Double] = [47, 52, 57, 63, 69, 76, 84, 100]
    
    private init() {
        loadData()
    }
    
    private func loadData() {
        guard let url = Bundle.main.url(forResource: "powerlifting_percentiles", withExtension: "json") else {
            loadError = "Could not find powerlifting_percentiles.json in bundle"
            Logger.error("CompetitiveLiftingData: \(loadError!)", category: .general)
            return
        }
        
        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            data = try decoder.decode(PowerliftingPercentileData.self, from: jsonData)
            Logger.info("CompetitiveLiftingData: Successfully loaded data for \(data?.metadata.lifterCount ?? 0) lifters", category: .general)
        } catch {
            loadError = "Failed to decode JSON: \(error.localizedDescription)"
            Logger.error("CompetitiveLiftingData: \(loadError!)", category: .general)
        }
    }
    
    /// Get the appropriate weight class for a given bodyweight (in kg)
    func weightClass(for bodyweight: Double, isMale: Bool) -> String {
        let classes = isMale ? maleWeightClasses : femaleWeightClasses
        
        for wc in classes {
            if bodyweight <= wc {
                return String(Int(wc))
            }
        }
        
        // Super heavyweight - return the highest class (JSON uses "140" not "140+")
        return String(Int(classes.last!))
    }
    
    /// Calculate percentile for a lift among competitive lifters
    /// - Parameters:
    ///   - lift: The lift type ("squat", "bench", "deadlift")
    ///   - weight: The weight lifted in kg
    ///   - bodyweight: The lifter's bodyweight in kg
    ///   - isMale: Whether the lifter is male
    ///   - ageCategory: The age category to compare against (default: all ages)
    /// - Returns: The percentile (0-100) or nil if data not available
    func percentile(forLift lift: String, weight: Double, bodyweight: Double, isMale: Bool, ageCategory: AgeCategory = .allAges) -> Double? {
        guard let data = data else { return nil }
        
        // OHP is not in competitive powerlifting data
        if lift == "ohp" { return nil }
        
        let sexData = isMale ? data.male : data.female
        let wc = weightClass(for: bodyweight, isMale: isMale)
        
        guard let wcData = sexData[wc] else { return nil }
        
        // Branch based on age category
        let liftData: LiftPercentileData?
        if ageCategory == .allAges {
            liftData = wcData.allAges[lift]
        } else {
            liftData = wcData.byAge?[ageCategory.jsonKey]?[lift]
        }
        
        guard let liftData = liftData, !liftData.percentiles.isEmpty else {
            return nil
        }
        
        // Find where this weight falls in the percentile distribution
        let percentileKeys = liftData.percentiles.keys.compactMap { Int($0) }.sorted()
        
        for i in 0..<percentileKeys.count - 1 {
            let lowerPercentile = percentileKeys[i]
            let upperPercentile = percentileKeys[i + 1]
            
            guard let lowerWeight = liftData.percentiles[String(lowerPercentile)],
                  let upperWeight = liftData.percentiles[String(upperPercentile)] else {
                continue
            }
            
            if weight >= lowerWeight && weight < upperWeight {
                // Linear interpolation
                let ratio = (weight - lowerWeight) / (upperWeight - lowerWeight)
                return Double(lowerPercentile) + ratio * Double(upperPercentile - lowerPercentile)
            }
        }
        
        // Below minimum
        if let firstPercentile = percentileKeys.first,
           let firstWeight = liftData.percentiles[String(firstPercentile)],
           weight < firstWeight {
            return max(1, Double(firstPercentile) * (weight / firstWeight))
        }
        
        // Above maximum
        if let lastPercentile = percentileKeys.last,
           let lastWeight = liftData.percentiles[String(lastPercentile)],
           weight >= lastWeight {
            return min(99.9, Double(lastPercentile))
        }
        
        return nil
    }
    
    /// Check if data is available for a specific age category
    func hasData(forAgeCategory ageCategory: AgeCategory, isMale: Bool) -> Bool {
        guard let data = data else { return false }
        
        if ageCategory == .allAges { return true }
        
        let sexData = isMale ? data.male : data.female
        // Check if any weight class has data for this age category
        return sexData.values.contains { wcData in
            wcData.byAge?[ageCategory.jsonKey] != nil
        }
    }
}

// MARK: - Powerlifting JSON Data Models

struct PowerliftingPercentileData: Codable {
    let metadata: PowerliftingMetadata
    let male: [String: WeightClassData]
    let female: [String: WeightClassData]
}

struct PowerliftingMetadata: Codable {
    let source: String
    let url: String
    let lifterCount: Int
    let description: String
    let units: String
    let percentiles: [Int]
    
    enum CodingKeys: String, CodingKey {
        case source, url, description, units, percentiles
        case lifterCount = "lifter_count"
    }
}

struct WeightClassData: Codable {
    let allAges: [String: LiftPercentileData]
    let byAge: [String: [String: LiftPercentileData]]?
    
    enum CodingKeys: String, CodingKey {
        case allAges = "all_ages"
        case byAge = "by_age"
    }
}

struct LiftPercentileData: Codable {
    let count: Int
    let percentiles: [String: Double]
}

// MARK: - Strength Scores Calculator (WILKS, DOTS, IPF GL)

struct StrengthScoresView: View {
    let useMetric: Bool
    let appState: AppState?

    // Premium feature: auto-import from PRs. Read live from StoreManager
    // (@Observable) so a purchase made in the paywall sheet unlocks immediately.
    private var canImportPRs: Bool {
        StoreManager.shared.canAccess(.e1rmChart)
    }

    enum Gender: String, CaseIterable {
        case male = "Male"
        case female = "Female"
    }
    
    enum InputMode: String, CaseIterable {
        case fromPRs = "From PRs"
        case custom = "Custom"
    }
    
    @State private var inputMode: InputMode = .custom  // Default to custom
    @State private var gender: Gender = .male
    @State private var bodyweight: String = ""
    @State private var squatInput: String = ""
    @State private var benchInput: String = ""
    @State private var deadliftInput: String = ""
    @State private var showResults = false
    @State private var showingPaywall = false
    @FocusState private var focusedField: LiftField?
    
    enum LiftField {
        case bodyweight, squat, bench, deadlift
    }
    
    // Get PRs from app state
    private var squatPR: Double? {
        appState?.userData.personalRecords.canonicalLiftValue(for: "Squat")?.estimatedOneRM
    }

    private var benchPR: Double? {
        appState?.userData.personalRecords.canonicalLiftValue(for: "Bench Press")?.estimatedOneRM
    }

    private var deadliftPR: Double? {
        let records = appState?.userData.personalRecords
        return (records?.canonicalLiftValue(for: "Deadlift") ?? records?.canonicalLiftValue(for: "Trap Bar Deadlift"))?.estimatedOneRM
    }
    
    private var hasPRData: Bool {
        squatPR != nil || benchPR != nil || deadliftPR != nil
    }
    
    // Get actual values based on mode
    private var squat: Double {
        if inputMode == .fromPRs, let pr = squatPR {
            return useMetric ? pr * 0.453592 : pr
        }
        return parseDecimalInput(squatInput) ?? 0
    }
    
    private var bench: Double {
        if inputMode == .fromPRs, let pr = benchPR {
            return useMetric ? pr * 0.453592 : pr
        }
        return parseDecimalInput(benchInput) ?? 0
    }
    
    private var deadlift: Double {
        if inputMode == .fromPRs, let pr = deadliftPR {
            return useMetric ? pr * 0.453592 : pr
        }
        return parseDecimalInput(deadliftInput) ?? 0
    }
    
    private var bodyweightKg: Double {
        guard let bw = parseDecimalInput(bodyweight), bw > 0 else { return 0 }
        return useMetric ? bw : bw * 0.453592
    }
    
    private var total: Double {
        // Convert to kg for calculations if in lbs
        let squatKg = useMetric ? squat : squat * 0.453592
        let benchKg = useMetric ? bench : bench * 0.453592
        let deadliftKg = useMetric ? deadlift : deadlift * 0.453592
        return squatKg + benchKg + deadliftKg
    }
    
    private var canCalculate: Bool {
        bodyweightKg > 0 && total > 0
    }
    
    private var unit: String {
        useMetric ? "kg" : "lb"
    }
    
    // WILKS Calculation (classic 1994 coefficients, 500 numerator)
    private var wilksScore: Double? {
        guard bodyweightKg > 0 && total > 0 else { return nil }
        
        let x = bodyweightKg
        
        let (a, b, c, d, e, f): (Double, Double, Double, Double, Double, Double)
        
        if gender == .male {
            a = -216.0475144
            b = 16.2606339
            c = -0.002388645
            d = -0.00113732
            e = 7.01863e-6
            f = -1.291e-8
        } else {
            a = 594.31747775582
            b = -27.23842536447
            c = 0.82112226871
            d = -0.00930733913
            e = 4.731582e-5
            f = -9.054e-8
        }
        
        let denominator = a + b*x + c*pow(x,2) + d*pow(x,3) + e*pow(x,4) + f*pow(x,5)
        guard denominator > 0 else { return nil }
        
        let coefficient = 500.0 / denominator
        return total * coefficient
    }
    
    // DOTS Calculation
    private var dotsScore: Double? {
        guard bodyweightKg > 0 && total > 0 else { return nil }
        
        let x = bodyweightKg
        
        let (a, b, c, d, e): (Double, Double, Double, Double, Double)
        
        if gender == .male {
            a = -307.75076
            b = 24.0900756
            c = -0.1918759221
            d = 0.0007391293
            e = -0.000001093
        } else {
            a = -57.96288
            b = 13.6175032
            c = -0.1126655495
            d = 0.0005158568
            e = -0.0000010706
        }
        
        let denominator = a + b*x + c*pow(x,2) + d*pow(x,3) + e*pow(x,4)
        guard denominator > 0 else { return nil }
        
        let coefficient = 500.0 / denominator
        return total * coefficient
    }
    
    // IPF GL Points (Goodlift Points) Calculation
    private var ipfGLPoints: Double? {
        guard bodyweightKg > 0 && total > 0 else { return nil }
        
        // IPF GL coefficients (Classic Raw)
        let (a, b, c): (Double, Double, Double)
        
        if gender == .male {
            // Men's Classic coefficients
            a = 1199.72839
            b = 1025.18162
            c = 0.00921465671
        } else {
            // Women's Classic coefficients
            a = 610.32796
            b = 1045.59282
            c = 0.03048036225
        }
        
        // IPF GL formula: Total × 100 / (a - b × e^(-c × bodyweight))
        let denominator = a - b * exp(-c * bodyweightKg)
        guard denominator > 0 else { return nil }
        
        return total * 100.0 / denominator
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SBSLayout.space6) {
                // Input mode picker
                if hasPRData {
                    inputModePicker
                }

                // Gender picker
                genderPicker

                // Bodyweight input
                bodyweightSection

                // Lift inputs
                liftsSection

                // Calculate button: the screen's one primary action
                if canCalculate {
                    CalculatorPrimaryButton(title: "Calculate Scores") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showResults = true
                        }
                        focusedField = nil
                    }
                }

                // Results section
                if showResults && canCalculate {
                    resultsSection
                }

                // Info section
                infoSection

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .scrollDismissesKeyboard(.interactively)
        .sbsBackground()
        .navigationTitle("Strength Scores")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Set input mode based on premium status and PR data
            if canImportPRs && hasPRData {
                inputMode = .fromPRs
            } else {
                inputMode = .custom
            }
        }
        .onChange(of: canImportPRs) { _, unlocked in
            // Unlock "From PRs" live when the user purchases in the paywall sheet
            if unlocked && hasPRData && inputMode == .custom {
                inputMode = .fromPRs
            }
        }
        .onChange(of: bodyweight) { _, _ in showResults = false }
        .onChange(of: squatInput) { _, _ in showResults = false }
        .onChange(of: benchInput) { _, _ in showResults = false }
        .onChange(of: deadliftInput) { _, _ in showResults = false }
        .onChange(of: inputMode) { _, _ in showResults = false }
        .onChange(of: gender) { _, _ in showResults = false }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(triggeredByFeature: nil)
        }
    }

    private var inputModePicker: some View {
        CalculatorSection(title: "Input source") {
            if canImportPRs {
                // Premium users get full picker
                SBSSegmentedControl(options: InputMode.allCases, selection: $inputMode) { $0.rawValue }
            } else {
                // Free users see custom selected with locked "From PRs" option
                HStack(spacing: SBSLayout.space1) {
                    // Custom (always selected for free users)
                    Text("Custom")
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .padding(.horizontal, SBSLayout.space2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .selectionCell(true)
                        .accessibilityAddTraits(.isSelected)

                    // Locked "From PRs" option: opens the paywall
                    Button {
                        showingPaywall = true
                    } label: {
                        HStack(spacing: SBSLayout.space1) {
                            Image(systemName: "lock.fill")
                                .font(SBSFonts.caption())
                                .accessibilityHidden(true)
                            Text("From PRs")
                                .font(SBSFonts.caption().weight(.semibold))
                                .lineLimit(1)
                            SBSBadge(text: "Pro", variant: .pro)
                        }
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal, SBSLayout.space2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .selectionCell(false)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("From PRs, Pro")
                }

                Text("Upgrade to auto-import your personal records")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private var genderPicker: some View {
        CalculatorSection(title: "Category") {
            SBSSegmentedControl(options: Gender.allCases, selection: $gender) { $0.rawValue }

            Text("Competition category for formula coefficients")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        }
    }

    private var bodyweightSection: some View {
        CalculatorSection(title: "Bodyweight") {
            CalculatorNumberField(placeholder: "0", text: $bodyweight, unit: unit)
                .focused($focusedField, equals: .bodyweight)
        }
    }

    private var liftsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("Powerlifting total") {
                if inputMode == .fromPRs {
                    SBSBadge(text: "From PRs")
                }
            }

            VStack(spacing: 0) {
                liftInputRow(
                    label: "Squat",
                    icon: "figure.strengthtraining.traditional",
                    value: inputMode == .fromPRs ? formatLiftFromPR(squatPR) : nil,
                    inputBinding: $squatInput,
                    field: .squat
                )

                SBSRowDivider()

                liftInputRow(
                    label: "Bench",
                    icon: "figure.mixed.cardio",
                    value: inputMode == .fromPRs ? formatLiftFromPR(benchPR) : nil,
                    inputBinding: $benchInput,
                    field: .bench
                )

                SBSRowDivider()

                liftInputRow(
                    label: "Deadlift",
                    icon: "figure.strengthtraining.functional",
                    value: inputMode == .fromPRs ? formatLiftFromPR(deadliftPR) : nil,
                    inputBinding: $deadliftInput,
                    field: .deadlift
                )

                SBSRowDivider()

                // Total display
                let displayTotal = squat + bench + deadlift
                SBSListRow("Total") {
                    EmptyView()
                } trailing: {
                    HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space1) {
                        Text(displayTotal > 0 ? formatWeight(displayTotal) : "--")
                            .font(SBSFonts.number())
                            .foregroundStyle(displayTotal > 0 ? Color.ink : Color.inkSecondary)
                        Text(unit)
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .card()
        }
        .padding(.horizontal)
    }

    private func liftInputRow(
        label: String,
        icon: String,
        value: String?,
        inputBinding: Binding<String>,
        field: LiftField
    ) -> some View {
        SBSAdaptiveStack {
            HStack(spacing: SBSLayout.space3) {
                Image(systemName: icon)
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(label)
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.ink)
            }

            Spacer(minLength: SBSLayout.space2)

            HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                if let value = value {
                    // PR value display
                    Text(value)
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.ink)
                } else {
                    // Custom input
                    TextField("0", text: inputBinding)
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.ink)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: field)
                        .frame(minWidth: 72, maxWidth: 120)
                        .sbsFieldCell()
                        .accessibilityLabel(label)
                }

                Text(unit)
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(.vertical, SBSLayout.space2)
        .padding(.horizontal, SBSLayout.space4)
        .frame(minHeight: 56)
    }

    private func formatLiftFromPR(_ pr: Double?) -> String? {
        guard let pr = pr else { return nil }
        let value = useMetric ? pr * 0.453592 : pr
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("Your strength scores")

            Text("Total \(formatWeight(total)) kg @ \(formatWeight(bodyweightKg)) kg bodyweight")
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)

            // One hairline group, a row per score
            VStack(spacing: 0) {
                if let wilks = wilksScore {
                    scoreRow(
                        name: "WILKS",
                        score: wilks,
                        description: "Classic powerlifting scoring formula",
                        rating: wilksRating(wilks)
                    )
                }

                if let dots = dotsScore {
                    if wilksScore != nil { SBSRowDivider() }
                    scoreRow(
                        name: "DOTS",
                        score: dots,
                        description: "Modern replacement for WILKS",
                        rating: dotsRating(dots)
                    )
                }

                if let ipf = ipfGLPoints {
                    if wilksScore != nil || dotsScore != nil { SBSRowDivider() }
                    scoreRow(
                        name: "IPF GL",
                        score: ipf,
                        description: "Official IPF Goodlift Points",
                        rating: ipfRating(ipf)
                    )
                }
            }
            .card()
        }
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// A score: its name as an eyebrow, the points in number-large, the rating as
    /// a badge (the word carries it, no colour per level).
    private func scoreRow(
        name: String,
        score: Double,
        description: String,
        rating: String
    ) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.space1) {
            HStack(spacing: SBSLayout.space2) {
                SBSEyebrow(name)
                    .foregroundStyle(Color.inkSecondary)
                Spacer(minLength: SBSLayout.space2)
                SBSBadge(text: rating)
            }

            Text(String(format: "%.2f", score))
                .font(SBSFonts.numberLarge())
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(description)
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(.vertical, SBSLayout.space3)
        .padding(.horizontal, SBSLayout.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // Rating helpers based on common competition standards
    private func wilksRating(_ score: Double) -> String {
        switch score {
        case 500...: return "Elite"
        case 400..<500: return "Advanced"
        case 300..<400: return "Intermediate"
        case 200..<300: return "Novice"
        default: return "Beginner"
        }
    }

    private func dotsRating(_ score: Double) -> String {
        // DOTS scores are slightly higher than WILKS on average
        switch score {
        case 500...: return "Elite"
        case 400..<500: return "Advanced"
        case 300..<400: return "Intermediate"
        case 200..<300: return "Novice"
        default: return "Beginner"
        }
    }

    private func ipfRating(_ score: Double) -> String {
        // IPF GL ranges differently
        switch score {
        case 100...: return "Elite"
        case 80..<100: return "Advanced"
        case 60..<80: return "Intermediate"
        case 40..<60: return "Novice"
        default: return "Beginner"
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSSectionEyebrow("About these scores")

            VStack(alignment: .leading, spacing: SBSLayout.space3) {
                infoItem(
                    title: "WILKS",
                    description: "The original powerlifting scoring formula, widely used since 1994. Compares lifters across different bodyweights."
                )

                infoItem(
                    title: "DOTS",
                    description: "Developed in 2019 as a more accurate alternative to WILKS, addressing issues with extreme weight classes."
                )

                infoItem(
                    title: "IPF GL Points",
                    description: "The official scoring system used by the International Powerlifting Federation since 2020."
                )

                SBSRowDivider()

                Text("All formulas use your SBD total and bodyweight to calculate a standardized score, allowing fair comparison between lifters of different sizes.")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SBSLayout.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .padding(.horizontal)
    }

    private func infoItem(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.ink)

            Text(description)
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", weight)
        } else {
            return String(format: "%.1f", weight)
        }
    }
}


// MARK: - Previews

#Preview("Calculators") {
    CalculatorsView(appState: AppState())
}

#Preview("1RM Calculator") {
    NavigationStack {
        OneRepMaxCalculatorView(useMetric: false)
    }
}

#Preview("RPE Calculator") {
    NavigationStack {
        RPECalculatorView(useMetric: false)
    }
}

#Preview("Plate Calculator") {
    NavigationStack {
        StandalonePlateCalculatorView(useMetric: false, defaultBarWeight: 45)
    }
}

#Preview("Training Max Calculator") {
    NavigationStack {
        TrainingMaxCalculatorView(useMetric: false)
    }
}

#Preview("Strength Scores") {
    NavigationStack {
        StrengthScoresView(useMetric: false, appState: nil)
    }
}

