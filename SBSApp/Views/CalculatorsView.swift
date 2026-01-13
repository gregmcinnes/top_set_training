import SwiftUI

// MARK: - Main Calculators View

struct CalculatorsView: View {
    @Bindable var appState: AppState
    @State private var showingPaywall = false
    
    private var canAccessStrengthScores: Bool {
        StoreManager.shared.canAccess(.e1rmChart)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SBSLayout.sectionSpacing) {
                    // Calculator cards
                    VStack(spacing: SBSLayout.cardSpacing) {
                        NavigationLink {
                            OneRepMaxCalculatorView(useMetric: appState.settings.useMetric)
                        } label: {
                            CalculatorCard(
                                icon: "trophy.fill",
                                iconColor: .orange,
                                title: "One-Rep Max",
                                description: "Estimate your 1RM from submaximal lifts"
                            )
                        }
                        .buttonStyle(.plain)
                        
                        NavigationLink {
                            RPECalculatorView(useMetric: appState.settings.useMetric)
                        } label: {
                            CalculatorCard(
                                icon: "gauge.with.needle.fill",
                                iconColor: .purple,
                                title: "RPE Calculator",
                                description: "Find weights for target RPE levels"
                            )
                        }
                        .buttonStyle(.plain)
                        
                        NavigationLink {
                            StandalonePlateCalculatorView(
                                useMetric: appState.settings.useMetric,
                                defaultBarWeight: appState.settings.barWeight
                            )
                        } label: {
                            CalculatorCard(
                                icon: "circle.grid.2x1.fill",
                                iconColor: .blue,
                                title: "Plate Calculator",
                                description: "Visualize which plates to load"
                            )
                        }
                        .buttonStyle(.plain)
                        
                        NavigationLink {
                            TrainingMaxCalculatorView(useMetric: appState.settings.useMetric)
                        } label: {
                            CalculatorCard(
                                icon: "percent",
                                iconColor: .green,
                                title: "Training Max",
                                description: "Calculate TM and percentage charts"
                            )
                        }
                        .buttonStyle(.plain)
                        
                        NavigationLink {
                            StrengthScoresView(
                                useMetric: appState.settings.useMetric,
                                appState: appState,
                                canImportPRs: canAccessStrengthScores
                            )
                        } label: {
                            CalculatorCard(
                                icon: "medal.fill",
                                iconColor: .yellow,
                                title: "Strength Scores",
                                description: "WILKS, DOTS & IPF GL Points"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .sbsBackground()
            .navigationTitle("Calculators")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }
}

// MARK: - Calculator Card

struct CalculatorCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text(description)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding()
        .sbsCard()
    }
}

// MARK: - Premium Calculator Card (Locked State)

struct PremiumCalculatorCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            // Icon with lock overlay
            ZStack {
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconColor.opacity(0.5))
                
                // Lock badge
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(SBSColors.accentFallback))
                    .offset(x: 16, y: 16)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    // Premium badge
                    Text("PRO")
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
                
                Text(description)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            // Unlock button indicator
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(SBSColors.accentFallback)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
                .overlay(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .stroke(
                            LinearGradient(
                                colors: [SBSColors.accentFallback.opacity(0.3), SBSColors.accentSecondaryFallback.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.1), radius: SBSLayout.shadowRadius, x: 0, y: SBSLayout.shadowY)
    }
}

// MARK: - One-Rep Max Calculator

struct OneRepMaxCalculatorView: View {
    let useMetric: Bool
    
    @State private var weight: String = ""
    @State private var reps: String = ""
    @State private var showResults = false
    @FocusState private var focusedField: Field?
    
    enum Field {
        case weight, reps
    }
    
    private var weightValue: Double? {
        Double(weight)
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
        
        return [
            ("Epley", w * (1 + repsDouble / 30.0), "Most common formula"),
            ("Brzycki", w * (36.0 / (37.0 - repsDouble)), "Popular for lower reps"),
            ("Lombardi", w * pow(repsDouble, 0.10), "Simple power formula"),
            ("Mayhew", w * (100.0 / (52.2 + 41.9 * exp(-0.055 * repsDouble))), "Research-based"),
            ("O'Conner", w * (1 + 0.025 * repsDouble), "Conservative estimate"),
            ("Wathan", w * (100.0 / (48.8 + 53.8 * exp(-0.075 * repsDouble))), "Football-based")
        ]
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
            VStack(spacing: SBSLayout.sectionSpacing) {
                // Input section
                inputSection
                
                // Calculate button
                if canCalculate {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showResults = true
                        }
                        focusedField = nil
                    } label: {
                        Text("Calculate")
                            .font(SBSFonts.button())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.paddingMedium)
                            .background(SBSColors.accentFallback)
                            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
                    }
                    .padding(.horizontal)
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
        VStack(spacing: SBSLayout.paddingMedium) {
            HStack {
                Text("Enter Your Lift")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Spacer()
            }
            
            HStack(spacing: SBSLayout.paddingMedium) {
                // Weight input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weight (\(unit))")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    TextField("0", text: $weight)
                        .font(SBSFonts.weightLarge())
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: .weight)
                        .padding()
                        .background(SBSColors.surfaceFallback)
                        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                }
                
                Text("×")
                    .font(SBSFonts.title())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                // Reps input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reps")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    TextField("0", text: $reps)
                        .font(SBSFonts.weightLarge())
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: .reps)
                        .padding()
                        .background(SBSColors.surfaceFallback)
                        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                }
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var resultsSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            // Average estimate (highlighted)
            if let avg = averageE1RM {
                VStack(spacing: 8) {
                    Text("Estimated 1RM")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    Text(formatWeight(avg))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(SBSColors.accentFallback)
                    
                    Text("Average of all formulas")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SBSLayout.paddingLarge)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.accentFallback.opacity(0.1))
                )
            }
            
            // Individual formula results
            VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                Text("By Formula")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                ForEach(results, id: \.name) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                                .font(SBSFonts.bodyBold())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text(result.description)
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        }
                        
                        Spacer()
                        
                        Text(formatWeight(result.value))
                            .font(SBSFonts.number())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                    }
                    .padding(.vertical, 8)
                    
                    if result.name != results.last?.name {
                        Divider()
                    }
                }
            }
            .padding()
            .background(SBSColors.surfaceFallback)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
            
            // Training percentages
            if let avg = averageE1RM {
                trainingPercentagesSection(e1rm: avg)
            }
        }
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    private func trainingPercentagesSection(e1rm: Double) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text("Training Percentages")
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: SBSLayout.paddingSmall) {
                ForEach([95, 90, 85, 80, 75, 70, 65, 60], id: \.self) { percentage in
                    VStack(spacing: 4) {
                        Text("\(percentage)%")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                        
                        Text(formatWeight(e1rm * Double(percentage) / 100.0))
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SBSColors.surfaceElevatedFallback)
                    .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                }
            }
        }
        .padding()
        .background(SBSColors.surfaceFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                Text("How It Works")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Text("Enter a weight and the number of reps you completed. The calculator uses multiple formulas to estimate your one-rep max. Results are most accurate for 1-10 reps; higher rep ranges become less reliable.")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding()
        .background(SBSColors.surfaceFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
        .padding(.horizontal)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight)) \(unit)"
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
    
    private var e1rmValue: Double? {
        Double(e1rm)
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
            VStack(spacing: SBSLayout.sectionSpacing) {
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
        VStack(spacing: SBSLayout.paddingSmall) {
            HStack {
                Text("Your Estimated 1RM")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Spacer()
            }
            
            HStack {
                TextField("Enter E1RM", text: $e1rm)
                    .font(SBSFonts.weightLarge())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($isE1RMFocused)
                
                Text(unit)
                    .font(SBSFonts.title2())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            .padding()
            .background(SBSColors.surfaceFallback)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
            
            Text("Use the 1RM Calculator if you don't know your estimated max")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var repsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text("Target Reps: \(targetReps)")
                .font(SBSFonts.bodyBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...12, id: \.self) { rep in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                targetReps = rep
                            }
                        } label: {
                            Text("\(rep)")
                                .font(SBSFonts.bodyBold())
                                .foregroundStyle(targetReps == rep ? .white : SBSColors.textPrimaryFallback)
                                .frame(width: 44, height: 44)
                                .background(
                                    targetReps == rep ? SBSColors.accentFallback : SBSColors.surfaceFallback
                                )
                                .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                        }
                    }
                }
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var rpeSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            HStack {
                Text("Target RPE: \(String(format: "%.1f", selectedRPE))")
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Spacer()
                
                Text(rpeDescription(selectedRPE))
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            HStack(spacing: 8) {
                ForEach(rpeValues, id: \.self) { rpe in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRPE = rpe
                        }
                    } label: {
                        Text(String(format: "%.1f", rpe))
                            .font(SBSFonts.caption())
                            .foregroundStyle(selectedRPE == rpe ? .white : SBSColors.textPrimaryFallback)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                selectedRPE == rpe ? rpeColor(rpe) : SBSColors.surfaceFallback
                            )
                            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                    }
                }
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private func resultSection(weight: Double) -> some View {
        VStack(spacing: 8) {
            Text("Target Weight")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            Text(formatWeight(weight))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(SBSColors.accentFallback)
            
            let percentage = percentageFor(reps: targetReps, rpe: selectedRPE)
            Text("\(Int(percentage * 100))% of E1RM for \(targetReps) reps @ RPE \(String(format: "%.1f", selectedRPE))")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SBSLayout.paddingLarge)
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.accentFallback.opacity(0.1))
        )
        .padding(.horizontal)
    }
    
    private var rpeTableSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text("RPE Reference")
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            VStack(spacing: 8) {
                ForEach([10.0, 9.5, 9.0, 8.5, 8.0, 7.5, 7.0, 6.5], id: \.self) { rpe in
                    HStack {
                        Text(String(format: "%.1f", rpe))
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(rpeColor(rpe))
                            .frame(width: 40)
                        
                        Text(rpeFullDescription(rpe))
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(SBSColors.surfaceFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
        .padding(.horizontal)
    }
    
    private func rpeColor(_ rpe: Double) -> Color {
        switch rpe {
        case 10: return .red
        case 9.5: return .orange
        case 9: return .orange
        case 8.5: return .yellow
        case 8: return .green
        case 7.5: return .green
        case 7: return .blue
        default: return .blue
        }
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
            return "\(Int(weight)) \(unit)"
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
    
    init(useMetric: Bool, defaultBarWeight: Double) {
        self.useMetric = useMetric
        self.defaultBarWeight = defaultBarWeight
        _barWeight = State(initialValue: defaultBarWeight)
    }
    
    private var targetWeightValue: Double {
        Double(targetWeight) ?? 0
    }
    
    private var unit: String {
        useMetric ? "kg" : "lb"
    }
    
    private var commonBarWeights: [Double] {
        useMetric ? [20, 15, 10] : [45, 35, 25, 15]
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: SBSLayout.sectionSpacing) {
                // Weight input
                weightInputSection
                
                // Bar weight selector
                barWeightSection
                
                // Barbell visualization
                if targetWeightValue > 0 {
                    barbellSection
                }
                
                // Plate legend
                PlateLegendView(useMetric: useMetric)
                    .padding(.horizontal)
                
                // Quick weights
                quickWeightsSection
                
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
        VStack(spacing: SBSLayout.paddingSmall) {
            HStack {
                Text("Total Weight")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Spacer()
            }
            
            HStack {
                TextField("0", text: $targetWeight)
                    .font(SBSFonts.weightLarge())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($isWeightFocused)
                
                Text(unit)
                    .font(SBSFonts.title2())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            .padding()
            .background(SBSColors.surfaceFallback)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var barWeightSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text("Bar Weight: \(formatWeight(barWeight))")
                .font(SBSFonts.bodyBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            HStack(spacing: 8) {
                ForEach(commonBarWeights, id: \.self) { weight in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            barWeight = weight
                        }
                    } label: {
                        Text(formatWeightShort(weight))
                            .font(SBSFonts.caption())
                            .foregroundStyle(barWeight == weight ? .white : SBSColors.textPrimaryFallback)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                barWeight == weight ? SBSColors.accentFallback : SBSColors.surfaceFallback
                            )
                            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var barbellSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            BarbellView(
                weight: targetWeightValue,
                useMetric: useMetric,
                barWeight: barWeight,
                showLabels: true,
                compact: false
            )
            
            // Plate breakdown
            let result = PlateCalculator(barWeight: barWeight, useMetric: useMetric)
                .calculate(totalWeight: targetWeightValue)
            
            if !result.platesPerSide.isEmpty {
                PlateBreakdownView(result: result, useMetric: useMetric)
            } else if targetWeightValue <= barWeight {
                Text("Bar only - no plates needed")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            if !result.isExact && result.remainder > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SBSColors.warning)
                    Text("Unable to make exact weight. Missing \(formatWeight(result.remainder * 2)) total.")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.warning)
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var quickWeightsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text("Quick Select")
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            let quickWeights: [Double] = useMetric
                ? [60, 80, 100, 120, 140, 160, 180, 200]
                : [135, 185, 225, 275, 315, 365, 405, 455]
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(quickWeights, id: \.self) { weight in
                    Button {
                        targetWeight = formatWeightShort(weight)
                        isWeightFocused = false
                    } label: {
                        Text(formatWeightShort(weight))
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(SBSColors.surfaceElevatedFallback)
                            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                    }
                }
            }
        }
        .padding()
        .background(SBSColors.surfaceFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
        .padding(.horizontal)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight)) \(unit)"
        }
        return String(format: "%.1f \(unit)", weight)
    }
    
    private func formatWeightShort(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - Plate Breakdown View

struct PlateBreakdownView: View {
    let result: PlateCalculatorResult
    let useMetric: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Load per side:")
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            // Group plates by weight
            let grouped = Dictionary(grouping: result.platesPerSide) { $0.weight }
            let sortedWeights = grouped.keys.sorted(by: >)
            
            HStack(spacing: 12) {
                ForEach(sortedWeights, id: \.self) { weight in
                    if let plates = grouped[weight], let plate = plates.first {
                        HStack(spacing: 4) {
                            if plates.count > 1 {
                                Text("\(plates.count)×")
                                    .font(SBSFonts.caption())
                                    .foregroundStyle(SBSColors.textSecondaryFallback)
                            }
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(plate.color)
                                .frame(width: 12, height: 20)
                            
                            Text(plate.displayWeight(useMetric: useMetric))
                                .font(SBSFonts.captionBold())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Training Max Calculator

struct TrainingMaxCalculatorView: View {
    let useMetric: Bool
    
    @State private var actualMax: String = ""
    @State private var tmPercentage: Double = 90
    @FocusState private var isMaxFocused: Bool
    
    private var actualMaxValue: Double? {
        Double(actualMax)
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
            VStack(spacing: SBSLayout.sectionSpacing) {
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
                }
                
                // Info section
                infoSection
                
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
        VStack(spacing: SBSLayout.paddingSmall) {
            HStack {
                Text("Your Actual 1RM")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Spacer()
            }
            
            HStack {
                TextField("Enter 1RM", text: $actualMax)
                    .font(SBSFonts.weightLarge())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($isMaxFocused)
                
                Text(unit)
                    .font(SBSFonts.title2())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            .padding()
            .background(SBSColors.surfaceFallback)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
            
            Text("Your tested or estimated one-rep max")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var tmPercentageSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            HStack {
                Text("TM Percentage: \(Int(tmPercentage))%")
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Spacer()
            }
            
            // Slider
            Slider(value: $tmPercentage, in: 80...100, step: 2.5)
                .tint(SBSColors.accentFallback)
            
            // Quick select buttons
            HStack(spacing: 8) {
                ForEach(tmPercentages, id: \.value) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tmPercentage = preset.value
                        }
                    } label: {
                        Text("\(Int(preset.value))%")
                            .font(SBSFonts.caption())
                            .foregroundStyle(tmPercentage == preset.value ? .white : SBSColors.textPrimaryFallback)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                tmPercentage == preset.value ? SBSColors.accentFallback : SBSColors.surfaceFallback
                            )
                            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                    }
                }
            }
            
            // Show which program uses this percentage
            if let matchingPreset = tmPercentages.first(where: { $0.value == tmPercentage }) {
                Text(matchingPreset.program)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .padding(.top, 4)
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private func trainingMaxResultSection(tm: Double) -> some View {
        VStack(spacing: 8) {
            Text("Training Max")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            Text(formatWeight(tm))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(SBSColors.accentFallback)
            
            if let max = actualMaxValue {
                Text("\(Int(tmPercentage))% of \(formatWeight(max))")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SBSLayout.paddingLarge)
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.accentFallback.opacity(0.1))
        )
        .padding(.horizontal)
    }
    
    private func percentageChartSection(tm: Double) -> some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            Text("Percentage Chart (of TM)")
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            // Two-column layout
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(chartPercentages, id: \.self) { percentage in
                    let weight = tm * Double(percentage) / 100.0
                    
                    HStack {
                        Text("\(percentage)%")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .frame(width: 40, alignment: .leading)
                        
                        Spacer()
                        
                        Text(formatWeight(weight))
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(percentage == 100 ? SBSColors.accentFallback : SBSColors.textPrimaryFallback)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        percentage == 100 
                            ? SBSColors.accentFallback.opacity(0.1) 
                            : SBSColors.surfaceElevatedFallback
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                }
            }
            
            // Common rep schemes
            VStack(alignment: .leading, spacing: 8) {
                Text("Common Programming")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .padding(.top, 8)
                
                programmingRow(name: "5/3/1 Week 1 (5s)", percentage: 85, tm: tm)
                programmingRow(name: "5/3/1 Week 2 (3s)", percentage: 90, tm: tm)
                programmingRow(name: "5/3/1 Week 3 (5/3/1)", percentage: 95, tm: tm)
                programmingRow(name: "Joker Sets", percentage: 100, tm: tm)
            }
        }
        .padding()
        .background(SBSColors.surfaceFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
        .padding(.horizontal)
    }
    
    private func programmingRow(name: String, percentage: Int, tm: Double) -> some View {
        let weight = tm * Double(percentage) / 100.0
        
        return HStack {
            Text(name)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textSecondaryFallback)
            
            Spacer()
            
            Text("\(percentage)%")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
            
            Text(formatWeight(weight))
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(SBSColors.accentSecondaryFallback)
                Text("What is a Training Max?")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Text("A Training Max (TM) is a percentage of your true 1RM used for programming. Using a TM (typically 85-90%) instead of your actual max allows for better bar speed, reduced injury risk, and room to progress over time. Most percentage-based programs calculate weights from your TM, not your true max.")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding()
        .background(SBSColors.surfaceFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
        .padding(.horizontal)
    }
    
    private func formatWeight(_ weight: Double) -> String {
        // Round to nearest 2.5 (or 1 for metric)
        let roundingIncrement = useMetric ? 1.0 : 2.5
        let rounded = (weight / roundingIncrement).rounded() * roundingIncrement
        
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded)) \(unit)"
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
    var canImportPRs: Bool = true  // Premium feature: auto-import from PRs
    
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
        appState?.userData.personalRecords["Squat"]?.estimatedOneRM
    }
    
    private var benchPR: Double? {
        appState?.userData.personalRecords["Bench"]?.estimatedOneRM
    }
    
    private var deadliftPR: Double? {
        appState?.userData.personalRecords["Deadlift"]?.estimatedOneRM
    }
    
    private var hasPRData: Bool {
        squatPR != nil || benchPR != nil || deadliftPR != nil
    }
    
    // Get actual values based on mode
    private var squat: Double {
        if inputMode == .fromPRs, let pr = squatPR {
            return useMetric ? pr * 0.453592 : pr
        }
        return Double(squatInput) ?? 0
    }
    
    private var bench: Double {
        if inputMode == .fromPRs, let pr = benchPR {
            return useMetric ? pr * 0.453592 : pr
        }
        return Double(benchInput) ?? 0
    }
    
    private var deadlift: Double {
        if inputMode == .fromPRs, let pr = deadliftPR {
            return useMetric ? pr * 0.453592 : pr
        }
        return Double(deadliftInput) ?? 0
    }
    
    private var bodyweightKg: Double {
        guard let bw = Double(bodyweight), bw > 0 else { return 0 }
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
    
    // WILKS Calculation (2020 coefficients)
    private var wilksScore: Double? {
        guard bodyweightKg > 0 && total > 0 else { return nil }
        
        let x = bodyweightKg
        
        let (a, b, c, d, e, f): (Double, Double, Double, Double, Double, Double)
        
        if gender == .male {
            a = 47.46178854
            b = 8.472061379
            c = 0.07369410346
            d = -0.001395833811
            e = 7.07665973070743e-6
            f = -1.20804336482315e-8
        } else {
            a = -125.4255398
            b = 13.71219419
            c = -0.03307250631
            d = -0.001050400051
            e = 9.38773881462799e-6
            f = -2.3334613884954e-8
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
            VStack(spacing: SBSLayout.sectionSpacing) {
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
                
                // Calculate button
                if canCalculate {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showResults = true
                        }
                        focusedField = nil
                    } label: {
                        Text("Calculate Scores")
                            .font(SBSFonts.button())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SBSLayout.paddingMedium)
                            .background(SBSColors.accentFallback)
                            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
                    }
                    .padding(.horizontal)
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
        VStack(spacing: SBSLayout.paddingSmall) {
            HStack {
                Text("Input Source")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Spacer()
            }
            
            if canImportPRs {
                // Premium users get full picker
                Picker("Input Mode", selection: $inputMode) {
                    ForEach(InputMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                // Free users see custom selected with locked "From PRs" option
                HStack(spacing: SBSLayout.paddingSmall) {
                    // Custom button (always selected for free users)
                    Text("Custom")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(SBSColors.accentFallback)
                        )
                    
                    // Locked "From PRs" button
                    Button {
                        showingPaywall = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                            Text("From PRs")
                                .font(SBSFonts.captionBold())
                            PremiumBadge(isCompact: true)
                        }
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(SBSColors.surfaceFallback)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Text("Upgrade to auto-import your personal records")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var genderPicker: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            HStack {
                Text("Category")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Spacer()
            }
            
            Picker("Gender", selection: $gender) {
                ForEach(Gender.allCases, id: \.self) { g in
                    Text(g.rawValue).tag(g)
                }
            }
            .pickerStyle(.segmented)
            
            Text("Competition category for formula coefficients")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var bodyweightSection: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            HStack {
                Text("Bodyweight")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Spacer()
            }
            
            HStack {
                TextField("0", text: $bodyweight)
                    .font(SBSFonts.weightLarge())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($focusedField, equals: .bodyweight)
                    .padding()
                    .background(SBSColors.surfaceElevatedFallback)
                    .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                
                Text(unit)
                    .font(SBSFonts.title2())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .frame(width: 40)
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private var liftsSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            HStack {
                Text("Powerlifting Total")
                    .font(SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                Spacer()
                
                if inputMode == .fromPRs {
                    Text("From PRs")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.accentFallback)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SBSColors.accentFallback.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            // Squat
            liftInputRow(
                label: "Squat",
                icon: "figure.strengthtraining.traditional",
                value: inputMode == .fromPRs ? formatLiftFromPR(squatPR) : nil,
                inputBinding: $squatInput,
                field: .squat
            )
            
            // Bench
            liftInputRow(
                label: "Bench",
                icon: "figure.mixed.cardio",
                value: inputMode == .fromPRs ? formatLiftFromPR(benchPR) : nil,
                inputBinding: $benchInput,
                field: .bench
            )
            
            // Deadlift
            liftInputRow(
                label: "Deadlift",
                icon: "figure.strengthtraining.functional",
                value: inputMode == .fromPRs ? formatLiftFromPR(deadliftPR) : nil,
                inputBinding: $deadliftInput,
                field: .deadlift
            )
            
            // Total display
            Divider()
            
            HStack {
                Text("Total")
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Spacer()
                
                let displayTotal = squat + bench + deadlift
                if displayTotal > 0 {
                    Text("\(formatWeight(displayTotal)) \(unit)")
                        .font(SBSFonts.weight())
                        .foregroundStyle(SBSColors.accentFallback)
                } else {
                    Text("-- \(unit)")
                        .font(SBSFonts.weight())
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private func liftInputRow(
        label: String,
        icon: String,
        value: String?,
        inputBinding: Binding<String>,
        field: LiftField
    ) -> some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(SBSColors.accentFallback)
                .frame(width: 24)
            
            Text(label)
                .font(SBSFonts.body())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            Spacer()
            
            if let value = value {
                // PR value display
                Text(value)
                    .font(SBSFonts.number())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text(unit)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            } else {
                // Custom input
                TextField("0", text: inputBinding)
                    .font(SBSFonts.number())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: field)
                    .frame(width: 80)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(SBSColors.surfaceElevatedFallback)
                    .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall))
                
                Text(unit)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .frame(width: 24)
            }
        }
    }
    
    private func formatLiftFromPR(_ pr: Double?) -> String? {
        guard let pr = pr else { return nil }
        let value = useMetric ? pr * 0.453592 : pr
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        } else {
            return String(format: "%.1f", value)
        }
    }
    
    private var resultsSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            // Header with total summary
            VStack(spacing: 4) {
                Text("Your Strength Scores")
                    .font(SBSFonts.title2())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Total: \(formatWeight(total)) kg @ \(formatWeight(bodyweightKg)) kg BW")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            .padding(.bottom, 8)
            
            // Score cards
            VStack(spacing: SBSLayout.paddingMedium) {
                if let wilks = wilksScore {
                    scoreCard(
                        name: "WILKS",
                        score: wilks,
                        description: "Classic powerlifting scoring formula",
                        color: .blue,
                        rating: wilksRating(wilks)
                    )
                }
                
                if let dots = dotsScore {
                    scoreCard(
                        name: "DOTS",
                        score: dots,
                        description: "Modern replacement for WILKS",
                        color: .purple,
                        rating: dotsRating(dots)
                    )
                }
                
                if let ipf = ipfGLPoints {
                    scoreCard(
                        name: "IPF GL",
                        score: ipf,
                        description: "Official IPF Goodlift Points",
                        color: .orange,
                        rating: ipfRating(ipf)
                    )
                }
            }
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    private func scoreCard(
        name: String,
        score: Double,
        description: String,
        color: Color,
        rating: (text: String, color: Color)
    ) -> some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            // Score circle
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 70, height: 70)
                
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    
                    Text(name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color.opacity(0.8))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Spacer()
                    
                    Text(rating.text)
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(rating.color)
                        .clipShape(Capsule())
                }
                
                Text(description)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                // Score breakdown
                Text(String(format: "%.2f points", score))
                    .font(SBSFonts.number())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
            }
        }
        .padding()
        .background(SBSColors.surfaceElevatedFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
    }
    
    // Rating helpers based on common competition standards
    private func wilksRating(_ score: Double) -> (text: String, color: Color) {
        switch score {
        case 500...: return ("Elite", .purple)
        case 400..<500: return ("Advanced", .blue)
        case 300..<400: return ("Intermediate", .green)
        case 200..<300: return ("Novice", .orange)
        default: return ("Beginner", .gray)
        }
    }
    
    private func dotsRating(_ score: Double) -> (text: String, color: Color) {
        // DOTS scores are slightly higher than WILKS on average
        switch score {
        case 500...: return ("Elite", .purple)
        case 400..<500: return ("Advanced", .blue)
        case 300..<400: return ("Intermediate", .green)
        case 200..<300: return ("Novice", .orange)
        default: return ("Beginner", .gray)
        }
    }
    
    private func ipfRating(_ score: Double) -> (text: String, color: Color) {
        // IPF GL ranges differently
        switch score {
        case 100...: return ("Elite", .purple)
        case 80..<100: return ("Advanced", .blue)
        case 60..<80: return ("Intermediate", .green)
        case 40..<60: return ("Novice", .orange)
        default: return ("Beginner", .gray)
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingMedium) {
            Text("About These Scores")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
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
            }
            
            Divider()
            
            Text("All formulas use your SBD total and bodyweight to calculate a standardized score, allowing fair comparison between lifters of different sizes.")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding()
        .sbsCard()
        .padding(.horizontal)
    }
    
    private func infoItem(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            Text(description)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textSecondaryFallback)
        }
    }
    
    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
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

