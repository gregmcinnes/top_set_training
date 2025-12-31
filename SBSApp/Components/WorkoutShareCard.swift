import SwiftUI

// MARK: - Workout Summary Data

/// Summary of a completed workout for sharing
struct WorkoutSummary: Equatable {
    let date: Date
    let dayTitle: String
    let week: Int
    let day: Int
    let programName: String?
    let exercises: [ExerciseSummary]
    let totalSets: Int
    let duration: TimeInterval?  // Optional workout duration
    let prs: [PRSummary]  // PRs achieved during this workout
    
    struct ExerciseSummary: Equatable, Identifiable {
        let id = UUID()
        let name: String
        let weight: Double
        let sets: Int
        let reps: String  // e.g., "5x5" or "8" for AMRAP
        let isAMRAP: Bool
        let estimatedOneRM: Double?  // Only for AMRAP sets
        let isAccessory: Bool
    }
    
    struct PRSummary: Equatable, Identifiable {
        let id = UUID()
        let liftName: String
        let weight: Double
        let reps: Int
        let newE1RM: Double
        let previousE1RM: Double?
    }
}

// MARK: - Workout Share Card View

struct WorkoutShareCard: View {
    let summary: WorkoutSummary
    let useMetric: Bool
    var compact: Bool = false
    
    private var hasPRs: Bool {
        !summary.prs.isEmpty
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient
            headerSection
            
            // Exercises list
            exercisesSection
            
            // PRs section (if any)
            if hasPRs {
                prsSection
            }
            
            // Footer with branding
            footerSection
        }
        .background(SBSColors.backgroundFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                .strokeBorder(
                    hasPRs
                        ? LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [SBSColors.accentFallback.opacity(0.3)], startPoint: .top, endPoint: .bottom),
                    lineWidth: hasPRs ? 2 : 1
                )
        )
        .shadow(color: hasPRs ? Color.orange.opacity(0.3) : Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            // Celebration banner for PRs
            if hasPRs {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("NEW PERSONAL RECORD\(summary.prs.count > 1 ? "S" : "")!")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .padding(.top, SBSLayout.paddingMedium)
            }
            
            // Date and workout info
            VStack(spacing: 4) {
                Text(dateFormatter.string(from: summary.date))
                    .font(SBSFonts.caption())
                    .foregroundStyle(hasPRs ? Color.orange : SBSColors.textSecondaryFallback)
                
                Text(summary.dayTitle)
                    .font(.system(size: compact ? 22 : 28, weight: .bold, design: .rounded))
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                HStack(spacing: SBSLayout.paddingSmall) {
                    Text("Week \(summary.week)")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    if let programName = summary.programName {
                        Text("•")
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                        Text(programName)
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, hasPRs ? SBSLayout.paddingSmall : SBSLayout.paddingLarge)
            .padding(.bottom, SBSLayout.paddingMedium)
        }
        .frame(maxWidth: .infinity)
        .background(
            hasPRs
                ? AnyView(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.15), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                : AnyView(
                    LinearGradient(
                        colors: [SBSColors.accentFallback.opacity(0.08), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }
    
    // MARK: - Exercises Section
    
    private var exercisesSection: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            // Main lifts
            let mainExercises = summary.exercises.filter { !$0.isAccessory }
            
            ForEach(mainExercises) { exercise in
                ShareCardExerciseRow(exercise: exercise, useMetric: useMetric, compact: compact, isPR: summary.prs.contains { $0.liftName == exercise.name })
            }
            
            // Accessories summary (if any)
            let accessories = summary.exercises.filter { $0.isAccessory }
            if !accessories.isEmpty {
                Divider()
                    .background(SBSColors.textTertiaryFallback.opacity(0.3))
                    .padding(.vertical, SBSLayout.paddingSmall)
                
                HStack {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                    
                    Text("\(accessories.count) accessories completed")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
        .padding(.vertical, SBSLayout.paddingMedium)
    }
    
    // MARK: - PRs Section
    
    private var prsSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            Divider()
                .background(Color.orange.opacity(0.3))
            
            VStack(spacing: SBSLayout.paddingSmall) {
                ForEach(summary.prs) { pr in
                    ShareCardPRRow(pr: pr, useMetric: useMetric, compact: compact)
                }
            }
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.bottom, SBSLayout.paddingMedium)
        }
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.05), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        HStack {
            // App branding
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SBSColors.accentFallback)
                
                Text("Top Set Training")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            // Total sets
            Text("\(summary.totalSets) sets completed")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
        .padding(.vertical, SBSLayout.paddingMedium)
        .background(SBSColors.surfaceFallback.opacity(0.5))
    }
}

// MARK: - Share Card Exercise Row

private struct ShareCardExerciseRow: View {
    let exercise: WorkoutSummary.ExerciseSummary
    let useMetric: Bool
    var compact: Bool = false
    var isPR: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: SBSLayout.paddingMedium) {
            // Exercise info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                        .font(compact ? SBSFonts.bodyBold() : SBSFonts.title3())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    if isPR {
                        PRBadge(small: true)
                    }
                }
                
                // Sets x Reps info
                HStack(spacing: 4) {
                    Text("\(exercise.sets) × \(exercise.reps)")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                    
                    if exercise.isAMRAP {
                        Text("AMRAP")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(SBSColors.success)
                    }
                }
            }
            
            Spacer()
            
            // Weight and E1RM
            VStack(alignment: .trailing, spacing: 2) {
                Text(exercise.weight.formattedWeight(useMetric: useMetric))
                    .font(compact ? SBSFonts.bodyBold() : SBSFonts.weight())
                    .foregroundStyle(isPR ? Color.orange : SBSColors.accentFallback)
                
                if let e1rm = exercise.estimatedOneRM {
                    Text("E1RM: \(e1rm.rounded().formattedWeightShort(useMetric: useMetric))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isPR ? Color.green : SBSColors.textTertiaryFallback)
                }
            }
        }
        .padding(.vertical, compact ? 4 : 6)
    }
}

// MARK: - Share Card PR Row

private struct ShareCardPRRow: View {
    let pr: WorkoutSummary.PRSummary
    let useMetric: Bool
    var compact: Bool = false
    
    private var improvement: Double? {
        guard let previous = pr.previousE1RM, previous > 0 else { return nil }
        return pr.newE1RM - previous
    }
    
    private var improvementPercent: Double? {
        guard let previous = pr.previousE1RM, previous > 0 else { return nil }
        return ((pr.newE1RM - previous) / previous) * 100
    }
    
    var body: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            // Trophy icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                
                Image(systemName: "trophy.fill")
                    .font(.system(size: compact ? 16 : 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            // PR info
            VStack(alignment: .leading, spacing: 2) {
                Text(pr.liftName)
                    .font(compact ? SBSFonts.bodyBold() : SBSFonts.title3())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("\(pr.weight.formattedWeightShort(useMetric: useMetric)) × \(pr.reps) reps")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            // E1RM and improvement
            VStack(alignment: .trailing, spacing: 2) {
                Text(pr.newE1RM.rounded().formattedWeight(useMetric: useMetric))
                    .font(compact ? SBSFonts.bodyBold() : SBSFonts.weight())
                    .foregroundStyle(Color.green)
                
                if let improvement = improvement, let percent = improvementPercent {
                    Text("+\(improvement.rounded().formattedWeightShort(useMetric: useMetric)) (\(String(format: "%.1f", percent))%)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.green)
                } else {
                    Text("First PR!")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange)
                }
            }
        }
    }
}

// MARK: - Share Card Wrapper (for screenshot/export)

struct ShareableWorkoutCard: View {
    let summary: WorkoutSummary
    let useMetric: Bool
    
    // Extra padding to account for shadow (radius + y offset)
    private let shadowPadding: CGFloat = 32
    
    var body: some View {
        WorkoutShareCard(summary: summary, useMetric: useMetric)
            .frame(width: 360)
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.top, SBSLayout.paddingLarge)
            .padding(.bottom, SBSLayout.paddingLarge + shadowPadding)
            .background(
                // Dark textured background for the share image
                ZStack {
                    Color(light: .init(white: 0.95), dark: .init(white: 0.05))
                    
                    // Subtle pattern
                    GeometryReader { geo in
                        Path { path in
                            let spacing: CGFloat = 20
                            for x in stride(from: 0, to: geo.size.width, by: spacing) {
                                for y in stride(from: 0, to: geo.size.height, by: spacing) {
                                    path.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                                }
                            }
                        }
                        .fill(Color.white.opacity(0.03))
                    }
                }
            )
    }
}

// MARK: - Image Renderer

extension View {
    @MainActor
    func snapshot() -> UIImage {
        let controller = UIHostingController(rootView: self)
        let view = controller.view
        
        // Use sizeThatFits for more accurate sizing that respects the view hierarchy
        let targetSize = controller.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear
        
        // Force layout pass to ensure all subviews are positioned
        view?.layoutIfNeeded()
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - Share Sheet Helper

struct WorkoutShareSheet: View {
    let summary: WorkoutSummary
    let useMetric: Bool
    let onDismiss: () -> Void
    
    @State private var shareImage: UIImage?
    @State private var isGenerating = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: SBSLayout.paddingLarge) {
                if isGenerating {
                    ProgressView("Generating share image...")
                        .padding()
                } else {
                    // Preview
                    ScrollView {
                        WorkoutShareCard(summary: summary, useMetric: useMetric, compact: false)
                            .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // Share button
                if let image = shareImage {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview(
                            "Workout Complete - \(summary.dayTitle)",
                            image: Image(uiImage: image)
                        )
                    ) {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                            
                            Text("Share Workout")
                                .font(SBSFonts.button())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingMedium)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                .fill(
                                    LinearGradient(
                                        colors: summary.prs.isEmpty 
                                            ? [SBSColors.accentFallback, SBSColors.accentFallback]
                                            : [.yellow, .orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .padding(.horizontal, SBSLayout.paddingLarge)
                }
            }
            .padding(.vertical)
            .sbsBackground()
            .navigationTitle("Share Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        .task {
            await generateShareImage()
        }
    }
    
    @MainActor
    private func generateShareImage() async {
        // Add small delay for view to settle
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let shareableView = ShareableWorkoutCard(summary: summary, useMetric: useMetric)
        shareImage = shareableView.snapshot()
        isGenerating = false
    }
}

// MARK: - Program Progress Summary Data

/// Summary of program progress for sharing
struct ProgressSummary: Equatable {
    let programName: String
    let cycleNumber: Int
    let startDate: Date
    let currentDate: Date
    let currentWeek: Int
    let totalWeeks: Int
    let lifts: [LiftProgress]
    let personalRecords: [PRProgress]
    let isComplete: Bool  // True if this is a completed cycle
    
    struct LiftProgress: Equatable, Identifiable {
        let id = UUID()
        let name: String
        let startingTM: Double
        let currentTM: Double
        let bestE1RM: Double?
        
        var gain: Double { currentTM - startingTM }
        var gainPercent: Double {
            guard startingTM > 0 else { return 0 }
            return ((currentTM - startingTM) / startingTM) * 100
        }
    }
    
    struct PRProgress: Equatable, Identifiable {
        let id = UUID()
        let liftName: String
        let weight: Double
        let reps: Int
        let e1rm: Double
        let date: Date
    }
    
    var totalWeightGained: Double {
        lifts.reduce(0) { $0 + $1.gain }
    }
    
    var averageGainPercent: Double {
        guard !lifts.isEmpty else { return 0 }
        return lifts.reduce(0) { $0 + $1.gainPercent } / Double(lifts.count)
    }
    
    var weeksCompleted: Int {
        currentWeek
    }
    
    var progressPercent: Double {
        guard totalWeeks > 0 else { return 0 }
        return Double(currentWeek) / Double(totalWeeks) * 100
    }
}

// MARK: - Progress Share Card View

struct ProgressShareCard: View {
    let summary: ProgressSummary
    let useMetric: Bool
    var compact: Bool = false
    
    private var hasPRs: Bool {
        !summary.personalRecords.isEmpty
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }
    
    private var isPositiveProgress: Bool {
        summary.averageGainPercent >= 0
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with celebration for PRs
            headerSection
            
            // Progress bar
            progressBarSection
            
            // Lifts summary
            liftsSection
            
            // PRs section (if any)
            if hasPRs {
                prsSection
            }
            
            // Footer
            footerSection
        }
        .background(SBSColors.backgroundFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                .strokeBorder(
                    hasPRs
                        ? LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [isPositiveProgress ? SBSColors.success.opacity(0.4) : SBSColors.accentFallback.opacity(0.3)], startPoint: .top, endPoint: .bottom),
                    lineWidth: hasPRs ? 2 : 1
                )
        )
        .shadow(color: hasPRs ? Color.orange.opacity(0.25) : Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            // Achievement badge for PRs
            if hasPRs {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("\(summary.personalRecords.count) PR\(summary.personalRecords.count > 1 ? "S" : "") ACHIEVED!")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .padding(.top, SBSLayout.paddingMedium)
            }
            
            // Program and cycle info
            VStack(spacing: 4) {
                Text(summary.programName)
                    .font(.system(size: compact ? 20 : 26, weight: .bold, design: .rounded))
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                HStack(spacing: SBSLayout.paddingSmall) {
                    Text("Cycle \(summary.cycleNumber)")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(SBSColors.accentFallback)
                    
                    Text("•")
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                    
                    Text(summary.isComplete ? "Completed" : "In Progress")
                        .font(SBSFonts.caption())
                        .foregroundStyle(summary.isComplete ? SBSColors.success : SBSColors.textSecondaryFallback)
                }
                
                // Date range
                Text("\(dateFormatter.string(from: summary.startDate)) → \(dateFormatter.string(from: summary.currentDate))")
                    .font(.system(size: 11))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            .padding(.top, hasPRs ? SBSLayout.paddingSmall : SBSLayout.paddingLarge)
            .padding(.bottom, SBSLayout.paddingMedium)
        }
        .frame(maxWidth: .infinity)
        .background(
            hasPRs
                ? AnyView(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.12), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                : AnyView(
                    LinearGradient(
                        colors: [SBSColors.accentFallback.opacity(0.06), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }
    
    // MARK: - Progress Bar Section
    
    private var progressBarSection: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            // Week progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SBSColors.surfaceFallback)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [SBSColors.accentFallback, SBSColors.success],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(summary.progressPercent / 100))
                }
            }
            .frame(height: 8)
            .padding(.horizontal, SBSLayout.paddingLarge)
            
            // Week labels
            HStack {
                Text("Week \(summary.currentWeek) of \(summary.totalWeeks)")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                Spacer()
                
                Text(String(format: "%.0f%% complete", summary.progressPercent))
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            .padding(.horizontal, SBSLayout.paddingLarge)
        }
        .padding(.vertical, SBSLayout.paddingMedium)
        .background(SBSColors.surfaceFallback.opacity(0.3))
    }
    
    // MARK: - Lifts Section
    
    private var liftsSection: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            // Overall summary stats
            HStack(spacing: SBSLayout.paddingLarge) {
                // Average gain
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: isPositiveProgress ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 16))
                        Text(String(format: "%.1f%%", summary.averageGainPercent))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(isPositiveProgress ? SBSColors.success : SBSColors.error)
                    
                    Text("Avg TM Gain")
                        .font(.system(size: 10))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                
                // Total weight gained
                VStack(spacing: 2) {
                    Text(summary.totalWeightGained >= 0 ? "+\(summary.totalWeightGained.formattedWeightShort(useMetric: useMetric))" : summary.totalWeightGained.formattedWeightShort(useMetric: useMetric))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(SBSColors.accentFallback)
                    
                    Text("Total TM Gained")
                        .font(.system(size: 10))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                
                // PRs count
                if hasPRs {
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.yellow)
                            Text("\(summary.personalRecords.count)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                        }
                        
                        Text("New PRs")
                            .font(.system(size: 10))
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                }
            }
            .padding(.vertical, SBSLayout.paddingMedium)
            
            Divider()
                .background(SBSColors.textTertiaryFallback.opacity(0.2))
            
            // Individual lifts
            ForEach(summary.lifts) { lift in
                LiftProgressRow(lift: lift, useMetric: useMetric, compact: compact, hasPR: summary.personalRecords.contains { $0.liftName == lift.name })
            }
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
        .padding(.vertical, SBSLayout.paddingSmall)
    }
    
    // MARK: - PRs Section
    
    private var prsSection: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            Divider()
                .background(Color.orange.opacity(0.3))
            
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                
                Text("Personal Records")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Spacer()
            }
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.top, SBSLayout.paddingSmall)
            
            VStack(spacing: 6) {
                ForEach(summary.personalRecords) { pr in
                    HStack {
                        Text(pr.liftName)
                            .font(SBSFonts.body())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Spacer()
                        
                        Text("\(pr.weight.formattedWeightShort(useMetric: useMetric)) × \(pr.reps)")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                        
                        Text("→")
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                        
                        Text(pr.e1rm.rounded().formattedWeight(useMetric: useMetric))
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.success)
                    }
                }
            }
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.bottom, SBSLayout.paddingMedium)
        }
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.05), Color.clear],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SBSColors.accentFallback)
                
                Text("Top Set Training")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            Text("\(summary.weeksCompleted) weeks of gains")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
        .padding(.vertical, SBSLayout.paddingMedium)
        .background(SBSColors.surfaceFallback.opacity(0.5))
    }
}

// MARK: - Lift Progress Row

private struct LiftProgressRow: View {
    let lift: ProgressSummary.LiftProgress
    let useMetric: Bool
    var compact: Bool = false
    var hasPR: Bool = false
    
    var body: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            // Lift name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lift.name)
                        .font(compact ? SBSFonts.body() : SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    if hasPR {
                        PRBadge(small: true)
                    }
                }
                
                if let e1rm = lift.bestE1RM {
                    Text("Best E1RM: \(e1rm.formattedWeightShort(useMetric: useMetric))")
                        .font(.system(size: 10))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
            }
            
            Spacer()
            
            // TM progression
            HStack(spacing: 6) {
                Text(lift.startingTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Text(lift.currentTM.formattedWeightShort(useMetric: useMetric))
                    .font(compact ? SBSFonts.bodyBold() : SBSFonts.weight())
                    .foregroundStyle(hasPR ? Color.orange : SBSColors.accentFallback)
            }
            
            // Gain percentage
            HStack(spacing: 2) {
                Image(systemName: lift.gain >= 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%.1f%%", lift.gainPercent))
                    .font(SBSFonts.captionBold())
            }
            .foregroundStyle(lift.gain >= 0 ? SBSColors.success : SBSColors.error)
            .frame(width: 55, alignment: .trailing)
        }
        .padding(.vertical, compact ? 4 : 6)
    }
}

// MARK: - Shareable Progress Card Wrapper

struct ShareableProgressCard: View {
    let summary: ProgressSummary
    let useMetric: Bool
    
    // Extra padding to account for shadow (radius + y offset)
    private let shadowPadding: CGFloat = 28
    
    var body: some View {
        ProgressShareCard(summary: summary, useMetric: useMetric)
            .frame(width: 380)
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.top, SBSLayout.paddingLarge)
            .padding(.bottom, SBSLayout.paddingLarge + shadowPadding)
            .background(
                ZStack {
                    Color(light: .init(white: 0.95), dark: .init(white: 0.05))
                    
                    GeometryReader { geo in
                        Path { path in
                            let spacing: CGFloat = 20
                            for x in stride(from: 0, to: geo.size.width, by: spacing) {
                                for y in stride(from: 0, to: geo.size.height, by: spacing) {
                                    path.addEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                                }
                            }
                        }
                        .fill(Color.white.opacity(0.03))
                    }
                }
            )
    }
}

// MARK: - Progress Share Sheet

struct ProgressShareSheet: View {
    let summary: ProgressSummary
    let useMetric: Bool
    let onDismiss: () -> Void
    
    @State private var shareImage: UIImage?
    @State private var isGenerating = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: SBSLayout.paddingLarge) {
                if isGenerating {
                    ProgressView("Generating share image...")
                        .padding()
                } else {
                    ScrollView {
                        ProgressShareCard(summary: summary, useMetric: useMetric, compact: false)
                            .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                if let image = shareImage {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview(
                            "\(summary.programName) - Cycle \(summary.cycleNumber) Progress",
                            image: Image(uiImage: image)
                        )
                    ) {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                            
                            Text("Share Progress")
                                .font(SBSFonts.button())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.paddingMedium)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                                .fill(
                                    LinearGradient(
                                        colors: summary.personalRecords.isEmpty 
                                            ? [SBSColors.accentFallback, SBSColors.accentFallback]
                                            : [.yellow, .orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .padding(.horizontal, SBSLayout.paddingLarge)
                }
            }
            .padding(.vertical)
            .sbsBackground()
            .navigationTitle("Share Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        .task {
            await generateShareImage()
        }
    }
    
    @MainActor
    private func generateShareImage() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let shareableView = ShareableProgressCard(summary: summary, useMetric: useMetric)
        shareImage = shareableView.snapshot()
        isGenerating = false
    }
}

// MARK: - Preview

#Preview("Workout Card with PRs") {
    ScrollView {
        WorkoutShareCard(
            summary: WorkoutSummary(
                date: Date(),
                dayTitle: "Squat Day",
                week: 8,
                day: 1,
                programName: "SBS Hypertrophy",
                exercises: [
                    .init(name: "Squat", weight: 315, sets: 5, reps: "5+", isAMRAP: true, estimatedOneRM: 380, isAccessory: false),
                    .init(name: "Romanian Deadlift", weight: 225, sets: 4, reps: "8", isAMRAP: false, estimatedOneRM: nil, isAccessory: false),
                    .init(name: "Leg Press", weight: 450, sets: 3, reps: "12", isAMRAP: false, estimatedOneRM: nil, isAccessory: true)
                ],
                totalSets: 12,
                duration: nil,
                prs: [
                    .init(liftName: "Squat", weight: 315, reps: 8, newE1RM: 380, previousE1RM: 365)
                ]
            ),
            useMetric: false
        )
        .padding()
    }
    .sbsBackground()
}

#Preview("Workout Card - No PRs") {
    ScrollView {
        WorkoutShareCard(
            summary: WorkoutSummary(
                date: Date(),
                dayTitle: "Bench Day",
                week: 4,
                day: 2,
                programName: "nSuns 5-Day",
                exercises: [
                    .init(name: "Bench Press", weight: 185, sets: 9, reps: "1+", isAMRAP: true, estimatedOneRM: 210, isAccessory: false),
                    .init(name: "Close Grip Bench", weight: 155, sets: 8, reps: "3-8", isAMRAP: false, estimatedOneRM: nil, isAccessory: false)
                ],
                totalSets: 17,
                duration: nil,
                prs: []
            ),
            useMetric: false
        )
        .padding()
    }
    .sbsBackground()
}

#Preview("Share Sheet") {
    WorkoutShareSheet(
        summary: WorkoutSummary(
            date: Date(),
            dayTitle: "Deadlift Day",
            week: 12,
            day: 3,
            programName: "SBS RTF",
            exercises: [
                .init(name: "Deadlift", weight: 405, sets: 5, reps: "5+", isAMRAP: true, estimatedOneRM: 475, isAccessory: false)
            ],
            totalSets: 5,
            duration: nil,
            prs: [
                .init(liftName: "Deadlift", weight: 405, reps: 7, newE1RM: 475, previousE1RM: 450)
            ]
        ),
        useMetric: false,
        onDismiss: {}
    )
}

#Preview("Progress Card with PRs") {
    ScrollView {
        ProgressShareCard(
            summary: ProgressSummary(
                programName: "SBS Hypertrophy 5x",
                cycleNumber: 2,
                startDate: Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date())!,
                currentDate: Date(),
                currentWeek: 12,
                totalWeeks: 20,
                lifts: [
                    .init(name: "Squat", startingTM: 285, currentTM: 315, bestE1RM: 380),
                    .init(name: "Bench Press", startingTM: 185, currentTM: 205, bestE1RM: 245),
                    .init(name: "Deadlift", startingTM: 345, currentTM: 385, bestE1RM: 455),
                    .init(name: "OHP", startingTM: 115, currentTM: 125, bestE1RM: 150)
                ],
                personalRecords: [
                    .init(liftName: "Squat", weight: 315, reps: 8, e1rm: 380, date: Date()),
                    .init(liftName: "Deadlift", weight: 385, reps: 7, e1rm: 455, date: Date())
                ],
                isComplete: false
            ),
            useMetric: false
        )
        .padding()
    }
    .sbsBackground()
}

#Preview("Progress Card - Completed Cycle") {
    ScrollView {
        ProgressShareCard(
            summary: ProgressSummary(
                programName: "nSuns 5-Day LP",
                cycleNumber: 1,
                startDate: Calendar.current.date(byAdding: .weekOfYear, value: -20, to: Date())!,
                currentDate: Date(),
                currentWeek: 20,
                totalWeeks: 20,
                lifts: [
                    .init(name: "Squat", startingTM: 225, currentTM: 295, bestE1RM: 345),
                    .init(name: "Bench Press", startingTM: 155, currentTM: 195, bestE1RM: 225),
                    .init(name: "Deadlift", startingTM: 275, currentTM: 365, bestE1RM: 420)
                ],
                personalRecords: [
                    .init(liftName: "Squat", weight: 275, reps: 6, e1rm: 345, date: Date()),
                    .init(liftName: "Bench Press", weight: 185, reps: 5, e1rm: 225, date: Date()),
                    .init(liftName: "Deadlift", weight: 355, reps: 5, e1rm: 420, date: Date())
                ],
                isComplete: true
            ),
            useMetric: false
        )
        .padding()
    }
    .sbsBackground()
}

#Preview("Progress Card - No PRs") {
    ScrollView {
        ProgressShareCard(
            summary: ProgressSummary(
                programName: "StrongLifts 5×5",
                cycleNumber: 1,
                startDate: Calendar.current.date(byAdding: .weekOfYear, value: -6, to: Date())!,
                currentDate: Date(),
                currentWeek: 6,
                totalWeeks: 12,
                lifts: [
                    .init(name: "Squat", startingTM: 135, currentTM: 175, bestE1RM: nil),
                    .init(name: "Bench Press", startingTM: 95, currentTM: 120, bestE1RM: nil),
                    .init(name: "Row", startingTM: 95, currentTM: 125, bestE1RM: nil)
                ],
                personalRecords: [],
                isComplete: false
            ),
            useMetric: false
        )
        .padding()
    }
    .sbsBackground()
}

// MARK: - Lift Progress Summary Data

/// Summary of lift progress for sharing
struct LiftProgressSummary: Equatable {
    let liftName: String
    let startE1RM: Double
    let startDate: Date
    let currentE1RM: Double
    let currentDate: Date
    let useMetric: Bool
    let percentile: Double? // Optional strength standard percentile
    let isMale: Bool?
    
    var gain: Double {
        currentE1RM - startE1RM
    }
    
    var gainPercent: Double {
        guard startE1RM > 0 else { return 0 }
        return ((currentE1RM - startE1RM) / startE1RM) * 100
    }
    
    var unit: String {
        useMetric ? "kg" : "lb"
    }
    
    var isPositiveProgress: Bool {
        gain >= 0
    }
}

// MARK: - Lift Progress Share Card View

struct LiftProgressShareCard: View {
    let summary: LiftProgressSummary
    var compact: Bool = false
    
    private var progressColor: Color {
        summary.isPositiveProgress ? SBSColors.success : SBSColors.error
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            // Main progress row
            progressRow
            
            // Footer
            footerSection
        }
        .background(SBSColors.backgroundFallback)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                .strokeBorder(
                    LinearGradient(
                        colors: [progressColor.opacity(0.4), progressColor.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            // Progress badge
            HStack(spacing: 6) {
                Image(systemName: summary.isPositiveProgress ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(String(format: "%@%.1f%% PROGRESS", summary.isPositiveProgress ? "+" : "", summary.gainPercent))
                    .font(.system(size: 12, weight: .black, design: .rounded))
            }
            .foregroundStyle(summary.isPositiveProgress ? .white : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(progressColor)
            )
            .padding(.top, SBSLayout.paddingMedium)
            
            // Lift name
            Text(summary.liftName)
                .font(.system(size: compact ? 22 : 28, weight: .bold, design: .rounded))
                .foregroundStyle(SBSColors.textPrimaryFallback)
            
            // Date range
            HStack(spacing: SBSLayout.paddingSmall) {
                Text(dateFormatter.string(from: summary.startDate))
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                
                Text("→")
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Text(dateFormatter.string(from: summary.currentDate))
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, SBSLayout.paddingMedium)
        .background(
            LinearGradient(
                colors: [progressColor.opacity(0.1), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Progress Row
    
    private var progressRow: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            // Starting E1RM
            VStack(alignment: .leading, spacing: 2) {
                Text("Started")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Text("\(Int(summary.startE1RM.rounded())) \(summary.unit)")
                    .font(.system(size: compact ? 18 : 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SBSColors.textTertiaryFallback)
            
            Spacer()
            
            // Current E1RM
            VStack(alignment: .trailing, spacing: 2) {
                Text("Current")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                HStack(spacing: 6) {
                    Text("\(Int(summary.currentE1RM.rounded())) \(summary.unit)")
                        .font(.system(size: compact ? 18 : 22, weight: .bold, design: .rounded))
                        .foregroundStyle(SBSColors.accentFallback)
                    
                    // Gain indicator
                    HStack(spacing: 2) {
                        Image(systemName: summary.isPositiveProgress ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%@%.0f", summary.isPositiveProgress ? "+" : "", summary.gain))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(progressColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(progressColor.opacity(0.15))
                    )
                }
            }
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
        .padding(.vertical, SBSLayout.paddingMedium)
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SBSColors.accentFallback)
                
                Text("Top Set Training")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            Text("Estimated 1RM Progress")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
        }
        .padding(.horizontal, SBSLayout.paddingLarge)
        .padding(.vertical, SBSLayout.paddingMedium)
        .background(SBSColors.surfaceFallback.opacity(0.5))
    }
}

// MARK: - Shareable Lift Progress Card (for snapshot)

struct ShareableLiftProgressCard: View {
    let summary: LiftProgressSummary
    
    var body: some View {
        LiftProgressShareCard(summary: summary)
            .frame(width: 340)
    }
    
    @MainActor
    func snapshot() -> UIImage {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3.0
        return renderer.uiImage ?? UIImage()
    }
}

#Preview("Lift Progress Card") {
    ScrollView {
        LiftProgressShareCard(
            summary: LiftProgressSummary(
                liftName: "Squat",
                startE1RM: 285,
                startDate: Calendar.current.date(byAdding: .month, value: -3, to: Date())!,
                currentE1RM: 325,
                currentDate: Date(),
                useMetric: false,
                percentile: 72,
                isMale: true
            )
        )
        .padding()
    }
    .sbsBackground()
}

