import SwiftUI

// MARK: - Plate Definition

struct Plate: Identifiable, Equatable {
    let id = UUID()
    let weight: Double  // in lbs (stored internally as lbs)
    let color: Color
    let height: CGFloat  // relative height (0-1)
    
    var displayWeight: String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
    }
    
    func displayWeight(useMetric: Bool) -> String {
        let value = useMetric ? weight * 0.453592 : weight
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Standard Plates

enum StandardPlates {
    // Olympic plates in lbs with competition-inspired colors
    static let plates: [Plate] = [
        Plate(weight: 45, color: Color(red: 0.2, green: 0.4, blue: 0.8), height: 1.0),      // Blue - 45lb
        Plate(weight: 35, color: Color(red: 0.9, green: 0.75, blue: 0.1), height: 0.9),     // Yellow - 35lb
        Plate(weight: 25, color: Color(red: 0.2, green: 0.7, blue: 0.3), height: 0.8),      // Green - 25lb
        Plate(weight: 10, color: Color(red: 0.95, green: 0.95, blue: 0.95), height: 0.6),   // White - 10lb
        Plate(weight: 5, color: Color(red: 0.85, green: 0.2, blue: 0.2), height: 0.5),      // Red - 5lb
        Plate(weight: 2.5, color: Color(red: 0.6, green: 0.6, blue: 0.65), height: 0.4),    // Silver - 2.5lb
    ]
    
    // Metric plates (kg) with competition colors
    static let metricPlates: [Plate] = [
        Plate(weight: 55, color: Color(red: 0.85, green: 0.2, blue: 0.2), height: 1.0),     // Red - 25kg (55lb)
        Plate(weight: 44, color: Color(red: 0.2, green: 0.4, blue: 0.8), height: 0.95),     // Blue - 20kg (44lb)
        Plate(weight: 33, color: Color(red: 0.9, green: 0.75, blue: 0.1), height: 0.85),    // Yellow - 15kg (33lb)
        Plate(weight: 22, color: Color(red: 0.2, green: 0.7, blue: 0.3), height: 0.75),     // Green - 10kg (22lb)
        Plate(weight: 11, color: Color(red: 0.95, green: 0.95, blue: 0.95), height: 0.6),   // White - 5kg (11lb)
        Plate(weight: 5.5, color: Color(red: 0.85, green: 0.2, blue: 0.2), height: 0.5),    // Red small - 2.5kg
        Plate(weight: 2.75, color: Color(red: 0.6, green: 0.6, blue: 0.65), height: 0.4),   // Silver - 1.25kg
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
            while weightPerSide >= plate.weight {
                plates.append(plate)
                weightPerSide -= plate.weight
            }
        }
        
        // Round remainder to avoid floating point issues
        let remainder = (weightPerSide * 10).rounded() / 10
        
        return PlateCalculatorResult(
            platesPerSide: plates,
            totalWeight: totalWeight,
            barWeight: barWeight,
            remainder: remainder
        )
    }
}

// MARK: - Barbell Visual View

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
    
    private let maxPlateHeight: CGFloat = 80
    private let plateWidth: CGFloat = 14
    private let plateSpacing: CGFloat = 2
    private let barHeight: CGFloat = 12
    private let sleeveHeight: CGFloat = 20
    private let collarWidth: CGFloat = 8
    
    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            // Barbell visualization
            barbellGraphic
            
            // Weight breakdown text
            if showLabels && !compact {
                weightBreakdown
            }
        }
        .onChange(of: weight) { _, _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                // Sort smallest-first so largest plates end up closest to center/collar
                // (index 0 is at the sleeve end, higher indices are toward center)
                animatedPlates = result.platesPerSide.sorted { $0.weight < $1.weight }
            }
        }
        .onChange(of: barWeight) { _, _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                // Recalculate plates when bar weight changes
                animatedPlates = result.platesPerSide.sorted { $0.weight < $1.weight }
            }
        }
        .onAppear {
            // Sort smallest-first so largest plates end up closest to center/collar
            animatedPlates = result.platesPerSide.sorted { $0.weight < $1.weight }
        }
    }
    
    private var barbellGraphic: some View {
        GeometryReader { geo in
            let centerY = geo.size.height / 2
            let startX: CGFloat = 16
            
            ZStack {
                // Bar (horizontal line through center)
                barGraphic(centerY: centerY, width: geo.size.width)
                
                // Left side plates
                platesGraphic(
                    centerY: centerY,
                    startX: startX,
                    plates: animatedPlates,
                    mirrored: false
                )
                
                // Right side plates (mirrored)
                platesGraphic(
                    centerY: centerY,
                    startX: geo.size.width - startX,
                    plates: animatedPlates,
                    mirrored: true
                )
            }
        }
        .frame(height: compact ? 60 : maxPlateHeight + 20)
    }
    
    private func barGraphic(centerY: CGFloat, width: CGFloat) -> some View {
        ZStack {
            // Main bar
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.75),
                            Color(white: 0.85),
                            Color(white: 0.7)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width - 32, height: barHeight)
                .position(x: width / 2, y: centerY)
            
            // Knurling pattern (subtle texture in center)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(white: 0.65).opacity(0.5))
                .frame(width: 60, height: barHeight - 2)
                .position(x: width / 2, y: centerY)
        }
    }
    
    private func platesGraphic(centerY: CGFloat, startX: CGFloat, plates: [Plate], mirrored: Bool) -> some View {
        // Left side (mirrored=false): plates go RIGHT (positive x) toward center, so direction = 1
        // Right side (mirrored=true): plates go LEFT (negative x) toward center, so direction = -1
        let direction: CGFloat = mirrored ? -1 : 1
        let baseX = startX + (direction * collarWidth / 2)
        
        return ZStack {
            // Collar
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.5), Color(white: 0.65), Color(white: 0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: collarWidth, height: sleeveHeight)
                .position(x: startX, y: centerY)
            
            // Plates
            ForEach(Array(plates.enumerated()), id: \.offset) { index, plate in
                let plateHeight = plate.height * (compact ? maxPlateHeight * 0.7 : maxPlateHeight)
                let xPos = baseX + (direction * (plateWidth / 2 + plateSpacing + CGFloat(index) * (plateWidth + plateSpacing)))
                
                PlateView(
                    plate: plate,
                    height: plateHeight,
                    width: plateWidth,
                    showLabel: showLabels && !compact,
                    useMetric: useMetric
                )
                .position(x: xPos, y: centerY)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private var weightBreakdown: some View {
        HStack(spacing: 16) {
            // Bar weight
            VStack(spacing: 2) {
                Text("Bar")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                Text(formatWeight(barWeight))
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Text("+")
                .foregroundStyle(SBSColors.textTertiaryFallback)
            
            // Per side
            VStack(spacing: 2) {
                Text("Each side")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                Text(formatWeight((weight - barWeight) / 2))
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Text("=")
                .foregroundStyle(SBSColors.textTertiaryFallback)
            
            // Total
            VStack(spacing: 2) {
                Text("Total")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                Text(formatWeight(weight))
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.accentFallback)
            }
        }
    }
    
    private func formatWeight(_ weight: Double) -> String {
        let value = useMetric ? weight * 0.453592 : weight
        let unit = useMetric ? "kg" : "lb"
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value)) \(unit)"
        }
        return String(format: "%.1f \(unit)", value)
    }
}

// MARK: - Individual Plate View

struct PlateView: View {
    let plate: Plate
    let height: CGFloat
    let width: CGFloat
    var showLabel: Bool = true
    var useMetric: Bool = false
    
    var body: some View {
        ZStack {
            // Plate body with 3D effect
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [
                            plate.color.opacity(0.7),
                            plate.color,
                            plate.color.opacity(0.8)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 1, y: 0)
            
            // Inner ring detail
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: width - 2, height: height - 4)
            
            // Weight label (rotated for vertical plates)
            if showLabel && height > 30 {
                Text(plate.displayWeight(useMetric: useMetric))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
            }
        }
    }
}

// MARK: - Plate Legend View

struct PlateLegendView: View {
    let useMetric: Bool
    
    private var plates: [Plate] {
        useMetric ? StandardPlates.metricPlates : StandardPlates.plates
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plate Colors")
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(plates) { plate in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(plate.color)
                            .frame(width: 16, height: 24)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                        
                        Text(plate.displayWeight(useMetric: useMetric))
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
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

// MARK: - Compact Plate List (alternative display)

struct PlateListView: View {
    let weight: Double
    let barWeight: Double
    let useMetric: Bool
    
    private var result: PlateCalculatorResult {
        PlateCalculator(barWeight: barWeight, useMetric: useMetric)
            .calculate(totalWeight: weight)
    }
    
    var body: some View {
        if result.platesPerSide.isEmpty {
            Text("Bar only")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textSecondaryFallback)
        } else {
            // Group plates by weight, sorted largest first (closest to bar)
            let grouped = Dictionary(grouping: result.platesPerSide) { $0.weight }
            let sortedWeights = grouped.keys.sorted(by: >)  // Largest first
            
            HStack(spacing: 4) {
                Text("Load:")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                ForEach(sortedWeights, id: \.self) { weight in
                    if let plates = grouped[weight], let plate = plates.first {
                        HStack(spacing: 2) {
                            if plates.count > 1 {
                                Text("\(plates.count)×")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                            
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(plate.color)
                                    .frame(width: 10, height: 10)
                                Text(plate.displayWeight(useMetric: useMetric))
                                    .font(SBSFonts.captionBold())
                                    .foregroundStyle(SBSColors.textPrimaryFallback)
                            }
                        }
                        
                        if weight != sortedWeights.last {
                            Text("+")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Barbell View") {
    VStack(spacing: 24) {
        Text("135 lb")
            .font(.headline)
        BarbellView(weight: 135, useMetric: false)
        
        Divider()
        
        Text("225 lb")
            .font(.headline)
        BarbellView(weight: 225, useMetric: false)
        
        Divider()
        
        Text("315 lb")
            .font(.headline)
        BarbellView(weight: 315, useMetric: false)
        
        Divider()
        
        Text("405 lb")
            .font(.headline)
        BarbellView(weight: 405, useMetric: false)
    }
    .padding()
    .sbsBackground()
}

#Preview("Compact") {
    VStack(spacing: 16) {
        BarbellView(weight: 185, useMetric: false, compact: true)
        BarbellView(weight: 225, useMetric: false, compact: true)
        BarbellView(weight: 275, useMetric: false, compact: true)
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
                            .font(.system(size: compact ? 10 : 12))
                        if !compact {
                            Text("Plate Calculator")
                                .font(SBSFonts.captionBold())
                        }
                        PremiumBadge(isCompact: true)
                    }
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .padding(.horizontal, compact ? 10 : 14)
                    .padding(.vertical, compact ? 6 : 8)
                    .background(
                        Capsule()
                            .fill(SBSColors.surfaceFallback)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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
                VStack(spacing: SBSLayout.sectionSpacing) {
                    // Hero section
                    heroSection
                    
                    // How it works
                    howItWorksSection
                    
                    // Examples
                    examplesSection
                    
                    // Plate legend
                    PlateLegendView(useMetric: useMetric)
                        .padding(.horizontal)
                    
                    // Unlock CTA for non-premium
                    if !canAccess {
                        unlockSection
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .background(SBSColors.backgroundFallback.ignoresSafeArea())
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
        VStack(spacing: SBSLayout.paddingMedium) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [SBSColors.accentFallback.opacity(0.2), SBSColors.accentSecondaryFallback.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "circle.grid.2x1.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Never Calculate Plates Again")
                .font(SBSFonts.title())
                .foregroundStyle(SBSColors.textPrimaryFallback)
                .multilineTextAlignment(.center)
            
            Text("See exactly which plates to load on each side of the barbell, with competition-style color coding.")
                .font(SBSFonts.body())
                .foregroundStyle(SBSColors.textSecondaryFallback)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, SBSLayout.paddingLarge)
    }
    
    // MARK: - How It Works Section
    
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            Text("How It Works")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                featureRow(
                    icon: "eye.fill",
                    title: "Visual Display",
                    description: "See a barbell graphic showing exactly which plates to load"
                )
                
                featureRow(
                    icon: "paintpalette.fill",
                    title: "Color Coded",
                    description: "Olympic-style plate colors for quick identification"
                )
                
                featureRow(
                    icon: "arrow.left.arrow.right",
                    title: "Per-Side Breakdown",
                    description: "Shows plates for each side, starting from heaviest"
                )
                
                    featureRow(
                        icon: "gearshape.fill",
                        title: "Customizable Bar",
                        description: "Adjusts for your bar weight (men's, women's, or custom)"
                    )
                }
                
                // Tip about Calculators section
                HStack(spacing: SBSLayout.paddingSmall) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.yellow)
                    
                    Text("Try the full Plate Calculator in the **Calculators** tab!")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                .padding(.top, SBSLayout.paddingSmall)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(SBSColors.surfaceFallback)
            )
            .padding(.horizontal)
        }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: SBSLayout.paddingMedium) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(SBSColors.accentFallback)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text(description)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Examples Section
    
    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            Text("Examples")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
                .padding(.horizontal)
            
            ForEach(exampleWeights, id: \.weight) { example in
                exampleCard(weight: example.weight, description: example.description)
            }
        }
    }
    
    private func exampleCard(weight: Double, description: String) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            HStack {
                Text(weight.formattedWeight(useMetric: useMetric))
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("• \(description)")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
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
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
        )
        .padding(.horizontal)
    }
    
    // MARK: - Unlock Section
    
    private var unlockSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            Text("Ready to load plates faster?")
                .font(SBSFonts.bodyBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            Button {
                dismiss()
                // Small delay to let sheet dismiss before showing paywall
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingPaywall = true
                }
            } label: {
                HStack(spacing: SBSLayout.paddingSmall) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16))
                    Text("Unlock Plate Calculator")
                        .font(SBSFonts.button())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SBSLayout.paddingMedium)
                .background(
                    LinearGradient(
                        colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
            }
            .buttonStyle(.plain)
            
            Text("Included with Premium • \(storeManager.premiumPriceString)")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(
                    LinearGradient(
                        colors: [
                            SBSColors.accentFallback.opacity(0.08),
                            SBSColors.accentSecondaryFallback.opacity(0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .padding(.horizontal)
    }
}

#Preview("Plate List") {
    VStack(spacing: 16) {
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

