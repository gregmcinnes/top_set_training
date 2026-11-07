import SwiftUI

// MARK: - Plate Definition

struct Plate: Identifiable, Equatable {
    let id = UUID()
    let weight: Double  // in lbs (stored internally as lbs)
    let color: Color
    let height: CGFloat  // relative height (0-1): 1 is the 80pt full-size plate
    /// Yellow, white and silver plates take a dark label; white also takes an outline.
    var isLight: Bool = false
    var isWhite: Bool = false

    var displayWeight: String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
    }

    func displayWeight(useMetric: Bool) -> String {
        if useMetric {
            // Metric plates are stored as lb-equivalents; round to plate
            // granularity (0.25 kg) so labels read clean (20, 15, 2.5, 1.25).
            let kg = (weight * 0.45359237 / 0.25).rounded() * 0.25
            return String(format: "%g", kg)
        }
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - Standard Plates

enum StandardPlates {
    // Competition colours; heights per the Barbell guideline (45 lb is 80pt, 2.5 lb 32pt)
    static let plates: [Plate] = [
        Plate(weight: 45, color: Color.plateBlue, height: 1.0),
        Plate(weight: 35, color: Color.plateYellow, height: 0.9, isLight: true),
        Plate(weight: 25, color: Color.plateGreen, height: 0.8),
        Plate(weight: 10, color: Color.plateWhite, height: 0.6, isLight: true, isWhite: true),
        Plate(weight: 5, color: Color.plateRed, height: 0.5),
        Plate(weight: 2.5, color: Color.plateSilver, height: 0.4, isLight: true),
    ]

    // Metric plates (kg) with competition colors
    static let metricPlates: [Plate] = [
        // Exact lb equivalents: the calculator works in lb, and rounded values here
        // would leave a false "missing weight" remainder on every kg target.
        Plate(weight: 25 * BarWeightOptions.lbPerKg, color: Color.plateRed, height: 1.0),
        Plate(weight: 20 * BarWeightOptions.lbPerKg, color: Color.plateBlue, height: 0.95),
        Plate(weight: 15 * BarWeightOptions.lbPerKg, color: Color.plateYellow, height: 0.9, isLight: true),
        Plate(weight: 10 * BarWeightOptions.lbPerKg, color: Color.plateGreen, height: 0.8),
        Plate(weight: 5 * BarWeightOptions.lbPerKg, color: Color.plateWhite, height: 0.6, isLight: true, isWhite: true),
        Plate(weight: 2.5 * BarWeightOptions.lbPerKg, color: Color.plateRed, height: 0.5),
        Plate(weight: 1.25 * BarWeightOptions.lbPerKg, color: Color.plateSilver, height: 0.4, isLight: true),
    ]
}

// MARK: - Plate Calculator Logic

struct PlateCalculatorResult {
    let platesPerSide: [Plate]
    let totalWeight: Double
    let barWeight: Double
    let remainder: Double  // weight that couldn't be made up with available plates

    var isExact: Bool { remainder == 0 }
}

struct PlateCalculator {
    let barWeight: Double
    let availablePlates: [Plate]

    init(barWeight: Double = 45, useMetric: Bool = false) {
        self.barWeight = barWeight
        self.availablePlates = useMetric ? StandardPlates.metricPlates : StandardPlates.plates
    }

    func calculate(totalWeight: Double) -> PlateCalculatorResult {
        guard totalWeight > barWeight else {
            return PlateCalculatorResult(
                platesPerSide: [],
                totalWeight: barWeight,
                barWeight: barWeight,
                remainder: 0
            )
        }

        var weightPerSide = (totalWeight - barWeight) / 2.0
        var plates: [Plate] = []

        // Greedy algorithm: use largest plates first
        // This naturally produces plates sorted largest-to-smallest,
        // which matches how they should be loaded (heaviest closest to collar)
        for plate in availablePlates.sorted(by: { $0.weight > $1.weight }) {
            // Small tolerance so floating-point drift can't skip a plate that fits exactly
            while weightPerSide >= plate.weight - 0.01 {
                plates.append(plate)
                weightPerSide = max(0, weightPerSide - plate.weight)
            }
        }

        // Round remainder to avoid floating point issues
        let remainder = weightPerSide < 0.05 ? 0 : (weightPerSide * 10).rounded() / 10

        return PlateCalculatorResult(
            platesPerSide: plates,
            totalWeight: totalWeight,
            barWeight: barWeight,
            remainder: remainder
        )
    }
}

// MARK: - Plate Text

/// The words that go with a plate visualisation, shared by the strip and the full bar.
enum PlateText {
    /// "45 · 45 · 45 · 10 per side", heaviest first; "Bar only" with no plates.
    static func perSide(_ result: PlateCalculatorResult, useMetric: Bool) -> String {
        guard !result.platesPerSide.isEmpty else { return "Bar only" }
        let plates = result.platesPerSide
            .sorted { $0.weight > $1.weight }
            .map { $0.displayWeight(useMetric: useMetric) }
            .joined(separator: " · ")
        return "\(plates) per side"
    }

    /// "2.5 lb short, no plate small enough", or nil when the load is exact.
    static func remainder(_ result: PlateCalculatorResult, useMetric: Bool) -> String? {
        guard result.remainder > 0 else { return nil }
        // Both sides are short by the per-side remainder
        return "\(formatWeight(result.remainder * 2, useMetric: useMetric)) short, no plate small enough"
    }

    static func formatWeight(_ weight: Double, useMetric: Bool) -> String {
        if useMetric {
            let kg = (weight * 0.45359237 / 0.25).rounded() * 0.25
            return String(format: "%g kg", kg)
        }
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight)) lb"
        }
        return String(format: "%.1f lb", weight)
    }
}

// MARK: - Compact Plate Strip

/// One side of the bar as a strip of plate bars: no bar, no labels, heaviest first.
/// The live set card and history rows show this; the full barbell is BarbellView.
struct PlateStrip: View {
    let plates: [Plate]

    static let maxHeight: CGFloat = 26
    private let plateWidth: CGFloat = 8
    private let spacing: CGFloat = 3

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            if plates.isEmpty {
                // Bar only: a short length of shaft
                Rectangle()
                    .fill(Color.bar)
                    .frame(width: 40, height: 4)
                    .frame(height: Self.maxHeight, alignment: .center)
            } else {
                ForEach(Array(plates.sorted { $0.weight > $1.weight }.enumerated()), id: \.offset) { _, plate in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(plate.color)
                        .overlay {
                            if plate.isWhite {
                                RoundedRectangle(cornerRadius: 1)
                                    .strokeBorder(Color.ink, lineWidth: SBSLayout.strokeHairline)
                            }
                        }
                        .frame(width: plateWidth, height: (Self.maxHeight * plate.height).rounded())
                }
            }
        }
        .frame(height: Self.maxHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// The strip with its per-side list beneath, and the remainder warning when the
/// plates can't make the weight. What the live set card shows.
struct PlateLoadSummary: View {
    let weight: Double
    let barWeight: Double
    let useMetric: Bool

    private var result: PlateCalculatorResult {
        PlateCalculator(barWeight: barWeight, useMetric: useMetric).calculate(totalWeight: weight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space1) {
            PlateStrip(plates: result.platesPerSide)
                .padding(.top, SBSLayout.space2)

            Text(PlateText.perSide(result, useMetric: useMetric))
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(2)

            if let remainder = PlateText.remainder(result, useMetric: useMetric) {
                Label(remainder, systemImage: "exclamationmark.triangle")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.warning)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plates: \(PlateText.perSide(result, useMetric: useMetric))")
    }
}

/// PlateLoadSummary behind the plate-calculator entitlement. Locked, it's a row
/// that opens the paywall instead.
struct PremiumPlateLoadSummary: View {
    let weight: Double
    let barWeight: Double
    let useMetric: Bool
    var onUnlockTap: (() -> Void)?

    var body: some View {
        if StoreManager.shared.canAccess(.plateCalculator) {
            PlateLoadSummary(weight: weight, barWeight: barWeight, useMetric: useMetric)
        } else {
            Button {
                onUnlockTap?()
            } label: {
                HStack(spacing: SBSLayout.space2) {
                    Image(systemName: "lock.fill")
                        .font(SBSFonts.caption())
                    Text("Plate calculator")
                        .font(SBSFonts.caption())
                    SBSBadge(text: "Pro", variant: .pro)
                }
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, SBSLayout.space2)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Barbell Visual View

/// The full barbell: bar shaft and sleeves, ink collars, plates stacked outward from
/// each collar heaviest first, labelled, with the breakdown line beneath.
struct BarbellView: View {
    let weight: Double
    let useMetric: Bool
    var barWeight: Double = 45
    var showLabels: Bool = true
    var compact: Bool = false

    @State private var animatedPlates: [Plate] = []

    private var calculator: PlateCalculator {
        PlateCalculator(barWeight: barWeight, useMetric: useMetric)
    }

    private var result: PlateCalculatorResult {
        calculator.calculate(totalWeight: weight)
    }

    private var scale: CGFloat { compact ? 0.7 : 1 }
    private var maxPlateHeight: CGFloat { 80 * scale }
    private var plateWidth: CGFloat { 14 * scale }
    private let plateSpacing: CGFloat = 2
    private var shaftHeight: CGFloat { 12 * scale }
    private var sleeveHeight: CGFloat { 20 * scale }
    private var sleeveWidth: CGFloat { 36 * scale }
    private var collarSize: CGSize { CGSize(width: 8 * scale, height: 28 * scale) }

    /// Plates nearest the collar first
    private var heaviestFirst: [Plate] {
        animatedPlates.sorted { $0.weight > $1.weight }
    }

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            barbellGraphic

            if showLabels && !compact {
                weightBreakdown
            }
        }
        .onChange(of: weight) { _, _ in loadPlates(animated: true) }
        .onChange(of: barWeight) { _, _ in loadPlates(animated: true) }
        .onChange(of: useMetric) { _, _ in loadPlates(animated: true) }
        .onAppear { loadPlates(animated: false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Barbell, \(PlateText.perSide(result, useMetric: useMetric)), \(PlateText.formatWeight(max(weight, barWeight), useMetric: useMetric)) total")
    }

    private func loadPlates(animated: Bool) {
        // 400ms spring, no bounce: plates slide on from the sleeve end
        withAnimation(animated ? .spring(duration: 0.4, bounce: 0) : nil) {
            animatedPlates = result.platesPerSide
        }
    }

    private var barbellGraphic: some View {
        ZStack {
            // Shaft, full width
            Rectangle()
                .fill(Color.bar)
                .frame(height: shaftHeight)

            HStack(spacing: 0) {
                sleeveEnd
                // Left side: lightest at the sleeve end, heaviest against the collar
                HStack(spacing: plateSpacing) {
                    ForEach(Array(heaviestFirst.enumerated()).reversed(), id: \.offset) { _, plate in
                        plateView(plate)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    collar
                }
                Spacer(minLength: 0)
                HStack(spacing: plateSpacing) {
                    collar
                    ForEach(Array(heaviestFirst.enumerated()), id: \.offset) { _, plate in
                        plateView(plate)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                sleeveEnd
            }
        }
        .frame(height: maxPlateHeight + 16 * scale)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var sleeveEnd: some View {
        Rectangle()
            .fill(Color.bar)
            .frame(width: sleeveWidth, height: sleeveHeight)
    }

    private var collar: some View {
        Rectangle()
            .fill(Color.ink)
            .frame(width: collarSize.width, height: collarSize.height)
    }

    private func plateView(_ plate: Plate) -> some View {
        PlateView(
            plate: plate,
            height: maxPlateHeight * plate.height,
            width: plateWidth,
            showLabel: showLabels && !compact,
            useMetric: useMetric
        )
    }

    /// "45 · 45 · 45 · 10 per side · 335 lb total"
    private var weightBreakdown: some View {
        VStack(spacing: SBSLayout.space1) {
            (Text(PlateText.perSide(result, useMetric: useMetric)).foregroundStyle(Color.ink)
             + Text(" · \(PlateText.formatWeight(max(weight, barWeight), useMetric: useMetric)) total"))
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)

            if let remainder = PlateText.remainder(result, useMetric: useMetric) {
                Label(remainder, systemImage: "exclamationmark.triangle")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.warning)
            }
        }
    }
}

// MARK: - Individual Plate View

/// One plate of the full barbell: a flat competition-colour bar with its weight at
/// the bottom. Plates are physical objects, so they look the same in both themes.
struct PlateView: View {
    let plate: Plate
    let height: CGFloat
    let width: CGFloat
    var showLabel: Bool = true
    var useMetric: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(plate.color)
            .overlay {
                if plate.isWhite {
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(Color.ink, lineWidth: SBSLayout.strokeHairline)
                }
            }
            .overlay(alignment: .bottom) {
                if showLabel && height > 30 {
                    Text(plate.displayWeight(useMetric: useMetric))
                        // Sized to the 14pt plate, so it doesn't follow Dynamic Type
                        .font(.custom(SBSFontName.plexMonoSemiBold, fixedSize: 9))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        // Fixed colours: the plate is the same in both themes
                        .foregroundStyle(plate.isLight ? Color.orangeInk : Color.white)
                        .padding(.bottom, 3)
                        .padding(.horizontal, 1)
                }
            }
            .frame(width: width, height: height)
    }
}

// MARK: - Plate Legend View

struct PlateLegendView: View {
    let useMetric: Bool

    private var plates: [Plate] {
        useMetric ? StandardPlates.metricPlates : StandardPlates.plates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            Text("Plate colours")
                .eyebrowText()
                .foregroundStyle(Color.inkSecondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: SBSLayout.space2) {
                ForEach(plates) { plate in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(plate.color)
                            .overlay {
                                if plate.isWhite {
                                    RoundedRectangle(cornerRadius: 1)
                                        .strokeBorder(Color.ink, lineWidth: SBSLayout.strokeHairline)
                                }
                            }
                            .frame(width: 8, height: 24)

                        Text(plate.displayWeight(useMetric: useMetric))
                            .font(SBSFonts.numberSmall())
                            .foregroundStyle(Color.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(SBSLayout.space4)
        .card()
    }
}

// MARK: - Compact Plate List (alternative display)

/// The compact strip with its per-side list beside it, for cards and rows.
struct PlateListView: View {
    let weight: Double
    let barWeight: Double
    let useMetric: Bool

    private var result: PlateCalculatorResult {
        PlateCalculator(barWeight: barWeight, useMetric: useMetric)
            .calculate(totalWeight: weight)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: SBSLayout.space2) {
            PlateStrip(plates: result.platesPerSide)
            Text(PlateText.perSide(result, useMetric: useMetric))
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Barbell View") {
    VStack(spacing: 24) {
        BarbellView(weight: 135, useMetric: false)
        BarbellView(weight: 225, useMetric: false)
        BarbellView(weight: 335, useMetric: false)
        BarbellView(weight: 405, useMetric: false)
        BarbellView(weight: 187.5, useMetric: false)
    }
    .padding()
    .sbsBackground()
}

#Preview("Compact") {
    VStack(alignment: .leading, spacing: 16) {
        BarbellView(weight: 185, useMetric: false, compact: true)
        PlateLoadSummary(weight: 335, barWeight: 45, useMetric: false)
        PlateLoadSummary(weight: 187.5, barWeight: 45, useMetric: false)
        PlateLoadSummary(weight: 45, barWeight: 45, useMetric: false)
    }
    .padding()
    .sbsBackground()
}

// MARK: - Premium Gated Barbell View

/// A barbell view that shows a lock overlay for non-premium users
struct PremiumBarbellView: View {
    let weight: Double
    let useMetric: Bool
    var barWeight: Double = 45
    var showLabels: Bool = true
    var compact: Bool = false
    var onUnlockTap: (() -> Void)?

    private let storeManager = StoreManager.shared

    private var canAccess: Bool {
        storeManager.canAccess(.plateCalculator)
    }

    var body: some View {
        if canAccess {
            BarbellView(
                weight: weight,
                useMetric: useMetric,
                barWeight: barWeight,
                showLabels: showLabels,
                compact: compact
            )
        } else {
            // Locked state - show teaser with blur
            ZStack {
                BarbellView(
                    weight: weight,
                    useMetric: useMetric,
                    barWeight: barWeight,
                    showLabels: showLabels,
                    compact: compact
                )
                .blur(radius: 3)
                .opacity(0.6)

                // Unlock button overlay
                Button {
                    onUnlockTap?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(SBSFonts.caption())
                        if !compact {
                            Text("Plate calculator")
                                .font(SBSFonts.caption())
                        }
                        SBSBadge(text: "Pro", variant: .pro)
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, compact ? 10 : 14)
                    .padding(.vertical, compact ? 6 : 8)
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                            .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Plate Calculator Info View

/// A detailed info view explaining the plate calculator feature
struct PlateCalculatorInfoView: View {
    let useMetric: Bool
    var barWeight: Double = 45
    @Binding var showingPaywall: Bool
    @Environment(\.dismiss) private var dismiss

    private let storeManager = StoreManager.shared

    private var canAccess: Bool {
        storeManager.canAccess(.plateCalculator)
    }

    // Example weights to showcase - chosen to display a variety of plate colors
    private var exampleWeights: [(weight: Double, description: String)] {
        if useMetric {
            return [
                (75, "Warm-up"),      // 20kg bar + 27.5kg/side = variety of plates
                (115, "Working sets"), // Shows multiple plate types
                (175, "Heavy singles") // Full barbell with variety
            ]
        } else {
            return [
                (165, "Warm-up"),      // 45 + 10 + 5 per side - 3 plate colors
                (255, "Working sets"), // 45 + 45 + 10 per side - shows 10s
                (385, "Heavy singles") // 45 + 45 + 45 + 25 + 5 - variety
            ]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SBSLayout.space6) {
                    heroSection
                    howItWorksSection
                    examplesSection

                    PlateLegendView(useMetric: useMetric)
                        .padding(.horizontal, SBSLayout.space4)

                    if !canAccess {
                        unlockSection
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: SBSLayout.space4) {
            BarbellView(weight: useMetric ? 140 / lbToKg : 315, useMetric: useMetric, barWeight: barWeight, showLabels: false, compact: true)
                .padding(.horizontal, SBSLayout.space6)

            Text("Never calculate plates again")
                .font(SBSFonts.title())
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)

            Text("See exactly which plates to load on each side of the barbell, in competition colours.")
                .font(SBSFonts.body())
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SBSLayout.space4)
        }
        .padding(.top, SBSLayout.space6)
    }

    // MARK: - How It Works Section

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space4) {
            Text("How it works")
                .font(SBSFonts.heading())
                .foregroundStyle(Color.ink)

            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                featureRow(
                    icon: "eye",
                    title: "Visual display",
                    description: "See a barbell graphic showing exactly which plates to load"
                )

                featureRow(
                    icon: "paintpalette",
                    title: "Colour coded",
                    description: "Competition plate colours for quick identification"
                )

                featureRow(
                    icon: "arrow.left.arrow.right",
                    title: "Per-side breakdown",
                    description: "Shows plates for each side, starting from heaviest"
                )

                featureRow(
                    icon: "gearshape",
                    title: "Customizable bar",
                    description: "Adjusts for your bar weight (men's, women's, or custom)"
                )
            }

            HStack(spacing: SBSLayout.space2) {
                Image(systemName: "lightbulb")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.orangeText)

                Text("Try the full plate calculator in the **Calculators** tab.")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.top, SBSLayout.space2)
        }
        .padding(SBSLayout.space4)
        .card()
        .padding(.horizontal, SBSLayout.space4)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: SBSLayout.space4) {
            Image(systemName: icon)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.ink)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.ink)

                Text(description)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(.vertical, SBSLayout.space1)
    }

    // MARK: - Examples Section

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space3) {
            Text("Examples")
                .font(SBSFonts.heading())
                .foregroundStyle(Color.ink)
                .padding(.horizontal, SBSLayout.space4)

            ForEach(exampleWeights, id: \.weight) { example in
                exampleCard(weight: example.weight, description: example.description)
            }
        }
    }

    private func exampleCard(weight: Double, description: String) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                Text(weight.formattedWeight(useMetric: useMetric))
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.ink)

                Text(description)
                    .eyebrowText()
                    .foregroundStyle(Color.inkSecondary)
            }

            // Always show the barbell clearly - this is a preview to entice users
            BarbellView(
                weight: weight,
                useMetric: useMetric,
                barWeight: barWeight,
                showLabels: true,
                compact: false
            )
        }
        .padding(SBSLayout.space4)
        .card()
        .padding(.horizontal, SBSLayout.space4)
    }

    // MARK: - Unlock Section

    private var unlockSection: some View {
        VStack(spacing: SBSLayout.space4) {
            Text("Ready to load plates faster?")
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.ink)

            Button {
                dismiss()
                // Small delay to let sheet dismiss before showing paywall
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingPaywall = true
                }
            } label: {
                SBSButtonTitle("Unlock plate calculator")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SBSPrimaryButtonStyle())

            Text("Included with Premium · \(storeManager.premiumPriceString)")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(SBSLayout.space4)
        .card()
        .padding(.horizontal, SBSLayout.space4)
    }
}

#Preview("Plate List") {
    VStack(alignment: .leading, spacing: 16) {
        PlateListView(weight: 45, barWeight: 45, useMetric: false)
        PlateListView(weight: 135, barWeight: 45, useMetric: false)
        PlateListView(weight: 225, barWeight: 45, useMetric: false)
        PlateListView(weight: 315, barWeight: 45, useMetric: false)
    }
    .padding()
    .sbsBackground()
}

#Preview("Legend") {
    VStack(spacing: 24) {
        PlateLegendView(useMetric: false)
        PlateLegendView(useMetric: true)
    }
    .padding()
    .sbsBackground()
}

#Preview("Plate Calculator Info") {
    PlateCalculatorInfoView(
        useMetric: false,
        barWeight: 45,
        showingPaywall: .constant(false)
    )
}
