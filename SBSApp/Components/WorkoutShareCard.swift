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
        .background(Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
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
        VStack(spacing: SBSLayout.space2) {
            // Celebration banner for PRs
            if hasPRs {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(SBSFonts.caption().weight(.semibold))
                    Text("NEW PERSONAL RECORD\(summary.prs.count > 1 ? "S" : "")!")
                        .font(SBSFonts.caption().weight(.semibold))
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
                .padding(.top, SBSLayout.space4)
            }
            
            // Date and workout info
            VStack(spacing: 4) {
                Text(dateFormatter.string(from: summary.date))
                    .font(SBSFonts.caption())
                    .foregroundStyle(hasPRs ? Color.orange : Color.inkSecondary)
                
                Text(summary.dayTitle)
                    .font(compact ? SBSFonts.title() : SBSFonts.display())
                    .foregroundStyle(Color.ink)
                
                HStack(spacing: SBSLayout.space2) {
                    Text("Week \(summary.week)")
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.inkSecondary)
                    
                    if let programName = summary.programName {
                        Text("•")
                            .foregroundStyle(Color.inkSecondary)
                        Text(programName)
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, hasPRs ? SBSLayout.space2 : SBSLayout.space6)
            .padding(.bottom, SBSLayout.space4)
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
                        colors: [Color.orangeSoft, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }
    
    // MARK: - Exercises Section
    
    private var exercisesSection: some View {
        VStack(spacing: SBSLayout.space2) {
            // Main lifts
            let mainExercises = summary.exercises.filter { !$0.isAccessory }
            
            ForEach(mainExercises) { exercise in
                ShareCardExerciseRow(exercise: exercise, useMetric: useMetric, compact: compact, isPR: summary.prs.contains { $0.liftName == exercise.name })
            }
            
            // Accessories summary (if any)
            let accessories = summary.exercises.filter { $0.isAccessory }
            if !accessories.isEmpty {
                Divider()
                    .background(Color.inkTertiary.opacity(0.3))
                    .padding(.vertical, SBSLayout.space2)
                
                HStack {
                    Image(systemName: "dumbbell.fill")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.accentSecondaryFallback)
                    
                    Text("\(accessories.count) accessories completed")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
    }
    
    // MARK: - PRs Section
    
    private var prsSection: some View {
        VStack(spacing: SBSLayout.space4) {
            Divider()
                .background(Color.orange.opacity(0.3))
            
            VStack(spacing: SBSLayout.space2) {
                ForEach(summary.prs) { pr in
                    ShareCardPRRow(pr: pr, useMetric: useMetric, compact: compact)
                }
            }
            .padding(.horizontal, SBSLayout.space6)
            .padding(.bottom, SBSLayout.space4)
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
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.orangeText)

                Text("Top Set Training")
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            
            Spacer()
            
            // Total sets
            Text("\(summary.totalSets) sets completed")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
        .background(Color.surface.opacity(0.5))
    }
}

// MARK: - Share Card Exercise Row

private struct ShareCardExerciseRow: View {
    let exercise: WorkoutSummary.ExerciseSummary
    let useMetric: Bool
    var compact: Bool = false
    var isPR: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: SBSLayout.space4) {
            // Exercise info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                        .font(compact ? SBSFonts.bodyStrong() : SBSFonts.heading())
                        .foregroundStyle(Color.ink)
                    
                    if isPR {
                        PRBadge(small: true)
                    }
                }
                
                // Sets x Reps info
                HStack(spacing: 4) {
                    Text("\(exercise.sets) × \(exercise.reps)")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                    
                    if exercise.isAMRAP {
                        Text("AMRAP")
                            .font(SBSFonts.caption().weight(.semibold))
                            .foregroundStyle(Color.success)
                    }
                }
            }
            
            Spacer()
            
            // Weight and E1RM
            VStack(alignment: .trailing, spacing: 2) {
                Text(exercise.weight.formattedWeight(useMetric: useMetric))
                    .font(compact ? SBSFonts.bodyStrong() : SBSFonts.number())
                    .foregroundStyle(isPR ? Color.orange : Color.orangeText)
                
                if let e1rm = exercise.estimatedOneRM {
                    Text("Est. 1RM: \(e1rm.rounded().formattedWeightShort(useMetric: useMetric))")
                        .font(SBSFonts.caption())
                        .foregroundStyle(isPR ? Color.green : Color.inkSecondary)
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
        HStack(spacing: SBSLayout.space4) {
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
                    .font(compact ? SBSFonts.bodyStrong() : SBSFonts.heading())
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
                    .font(compact ? SBSFonts.bodyStrong() : SBSFonts.heading())
                    .foregroundStyle(Color.ink)
                
                Text("\(pr.weight.formattedWeightShort(useMetric: useMetric)) × \(pr.reps) reps")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
            
            Spacer()
            
            // E1RM and improvement
            VStack(alignment: .trailing, spacing: 2) {
                Text(pr.newE1RM.rounded().formattedWeight(useMetric: useMetric))
                    .font(compact ? SBSFonts.bodyStrong() : SBSFonts.number())
                    .foregroundStyle(Color.green)
                
                if let improvement = improvement, let percent = improvementPercent {
                    Text("+\(improvement.rounded().formattedWeightShort(useMetric: useMetric)) (\(String(format: "%.1f", percent))%)")
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.green)
                } else {
                    Text("First PR!")
                        .font(SBSFonts.caption())
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
            // Rendered off-screen at a fixed pixel width for export — pin to
            // the default type size so the image is deterministic regardless
            // of the user's Dynamic Type setting.
            .dynamicTypeSize(.large)
            .frame(width: 360)
            .padding(.horizontal, SBSLayout.space6)
            .padding(.top, SBSLayout.space6)
            .padding(.bottom, SBSLayout.space6 + shadowPadding)
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
    /// Renders the view to a `UIImage` using `ImageRenderer`.
    ///
    /// This replaces the old off-window `UIHostingController` + `drawHierarchy`
    /// approach, which required a fixed sleep for layout to settle (a race that
    /// could produce blank images) and always rendered in light mode.
    ///
    /// Export is pinned to a fixed color scheme so share cards look identical
    /// regardless of the user's current appearance — the cards are designed
    /// against a fixed dark textured export background — and the sizing/layout
    /// is deterministic without any timing delay.
    @MainActor
    func snapshot(colorScheme: ColorScheme = .dark, scale: CGFloat = 3) -> UIImage {
        let renderer = ImageRenderer(content: self.environment(\.colorScheme, colorScheme))
        renderer.scale = scale
        return renderer.uiImage ?? UIImage()
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
            VStack(spacing: SBSLayout.space6) {
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
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "square.and.arrow.up")
                                .font(SBSFonts.bodyStrong())
                            
                            Text("Share Workout")
                                .font(SBSFonts.bodyStrong())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.space4)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
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
                    .padding(.horizontal, SBSLayout.space6)
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
        // ImageRenderer lays out synchronously, so no sleep-based settling is
        // needed — this avoids the previous race that could yield a blank image.
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
        .background(Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                .strokeBorder(
                    hasPRs
                        ? LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [isPositiveProgress ? Color.success.opacity(0.4) : SBSColors.accentFallback.opacity(0.3)], startPoint: .top, endPoint: .bottom),
                    lineWidth: hasPRs ? 2 : 1
                )
        )
        .shadow(color: hasPRs ? Color.orange.opacity(0.25) : Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: SBSLayout.space2) {
            // Achievement badge for PRs
            if hasPRs {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(SBSFonts.caption().weight(.semibold))
                    Text("\(summary.personalRecords.count) PR\(summary.personalRecords.count > 1 ? "S" : "") ACHIEVED!")
                        .font(SBSFonts.caption().weight(.semibold))
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
                .padding(.top, SBSLayout.space4)
            }
            
            // Program and cycle info
            VStack(spacing: 4) {
                Text(summary.programName)
                    .font(compact ? SBSFonts.heading() : SBSFonts.title())
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                HStack(spacing: SBSLayout.space2) {
                    Text("Cycle \(summary.cycleNumber)")
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.orangeText)
                    
                    Text("•")
                        .foregroundStyle(Color.inkSecondary)
                    
                    Text(summary.isComplete ? "Completed" : "In Progress")
                        .font(SBSFonts.caption())
                        .foregroundStyle(summary.isComplete ? Color.success : Color.inkSecondary)
                }
                
                // Date range
                Text("\(dateFormatter.string(from: summary.startDate)) → \(dateFormatter.string(from: summary.currentDate))")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.top, hasPRs ? SBSLayout.space2 : SBSLayout.space6)
            .padding(.bottom, SBSLayout.space4)
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
                        colors: [Color.orangeSoft, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }
    
    // MARK: - Progress Bar Section
    
    private var progressBarSection: some View {
        VStack(spacing: SBSLayout.space2) {
            // Week progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.surface)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [SBSColors.accentFallback, Color.success],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(summary.progressPercent / 100))
                }
            }
            .frame(height: 8)
            .padding(.horizontal, SBSLayout.space6)
            
            // Week labels
            HStack {
                Text("Week \(summary.currentWeek) of \(summary.totalWeeks)")
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
                
                Spacer()
                
                Text(String(format: "%.0f%% complete", summary.progressPercent))
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, SBSLayout.space6)
        }
        .padding(.vertical, SBSLayout.space4)
        .background(Color.surface.opacity(0.3))
    }
    
    // MARK: - Lifts Section
    
    private var liftsSection: some View {
        VStack(spacing: SBSLayout.space2) {
            // Overall summary stats
            HStack(spacing: SBSLayout.space6) {
                // Average gain
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: isPositiveProgress ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(SBSFonts.body())
                        Text(String(format: "%.1f%%", summary.averageGainPercent))
                            .font(SBSFonts.heading())
                    }
                    .foregroundStyle(isPositiveProgress ? Color.success : Color.danger)

                    Text("Avg Gain")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                
                // Total weight gained
                VStack(spacing: 2) {
                    Text(summary.totalWeightGained >= 0 ? "+\(summary.totalWeightGained.formattedWeightShort(useMetric: useMetric))" : summary.totalWeightGained.formattedWeightShort(useMetric: useMetric))
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.orangeText)

                    Text("Total Gained")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                
                // PRs count
                if hasPRs {
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            Image(systemName: "trophy.fill")
                                .font(SBSFonts.caption())
                                .foregroundStyle(.yellow)
                            Text("\(summary.personalRecords.count)")
                                .font(SBSFonts.heading())
                                .foregroundStyle(Color.ink)
                        }

                        Text("New PRs")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
            }
            .padding(.vertical, SBSLayout.space4)
            
            Divider()
                .background(Color.inkTertiary.opacity(0.2))
            
            // Individual lifts
            ForEach(summary.lifts) { lift in
                LiftProgressRow(lift: lift, useMetric: useMetric, compact: compact, hasPR: summary.personalRecords.contains { $0.liftName == lift.name })
            }
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space2)
    }
    
    // MARK: - PRs Section
    
    private var prsSection: some View {
        VStack(spacing: SBSLayout.space2) {
            Divider()
                .background(Color.orange.opacity(0.3))
            
            HStack {
                Image(systemName: "trophy.fill")
                    .font(SBSFonts.caption())
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                
                Text("Personal Records")
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.ink)
                
                Spacer()
            }
            .padding(.horizontal, SBSLayout.space6)
            .padding(.top, SBSLayout.space2)
            
            VStack(spacing: 6) {
                ForEach(summary.personalRecords) { pr in
                    HStack {
                        Text(pr.liftName)
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.ink)
                        
                        Spacer()
                        
                        Text("\(pr.weight.formattedWeightShort(useMetric: useMetric)) × \(pr.reps)")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                        
                        Text("→")
                            .foregroundStyle(Color.inkSecondary)
                        
                        Text(pr.e1rm.rounded().formattedWeight(useMetric: useMetric))
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.success)
                    }
                }
            }
            .padding(.horizontal, SBSLayout.space6)
            .padding(.bottom, SBSLayout.space4)
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
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.orangeText)

                Text("Top Set Training")
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            
            Spacer()
            
            Text("\(summary.weeksCompleted) weeks of gains")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
        .background(Color.surface.opacity(0.5))
    }
}

// MARK: - Lift Progress Row

private struct LiftProgressRow: View {
    let lift: ProgressSummary.LiftProgress
    let useMetric: Bool
    var compact: Bool = false
    var hasPR: Bool = false
    
    var body: some View {
        HStack(spacing: SBSLayout.space4) {
            // Lift name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lift.name)
                        .font(compact ? SBSFonts.body() : SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)
                    
                    if hasPR {
                        PRBadge(small: true)
                    }
                }
                
                if let e1rm = lift.bestE1RM {
                    Text("Best Est. 1RM: \(e1rm.formattedWeightShort(useMetric: useMetric))")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            
            Spacer()
            
            // TM progression
            HStack(spacing: 6) {
                Text(lift.startingTM.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                
                Image(systemName: "arrow.right")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)

                Text(lift.currentTM.formattedWeightShort(useMetric: useMetric))
                    .font(compact ? SBSFonts.bodyStrong() : SBSFonts.number())
                    .foregroundStyle(hasPR ? Color.orange : Color.orangeText)
            }
            
            // Gain percentage
            HStack(spacing: 2) {
                Image(systemName: lift.gain >= 0 ? "arrow.up" : "arrow.down")
                    .font(SBSFonts.caption().weight(.semibold))
                Text(String(format: "%.1f%%", lift.gainPercent))
                    .font(SBSFonts.caption().weight(.semibold))
            }
            .foregroundStyle(lift.gain >= 0 ? Color.success : Color.danger)
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
            // Rendered off-screen at a fixed pixel width for export — pin to
            // the default type size so the image is deterministic regardless
            // of the user's Dynamic Type setting.
            .dynamicTypeSize(.large)
            .frame(width: 380)
            .padding(.horizontal, SBSLayout.space6)
            .padding(.top, SBSLayout.space6)
            .padding(.bottom, SBSLayout.space6 + shadowPadding)
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
            VStack(spacing: SBSLayout.space6) {
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
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "square.and.arrow.up")
                                .font(SBSFonts.bodyStrong())
                            
                            Text("Share Progress")
                                .font(SBSFonts.bodyStrong())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SBSLayout.space4)
                        .background(
                            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
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
                    .padding(.horizontal, SBSLayout.space6)
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
        // ImageRenderer lays out synchronously — no settling delay required.
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
                    .init(name: ExerciseLibrary.shortName(for: "Overhead Press"), startingTM: 115, currentTM: 125, bestE1RM: 150)
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
        summary.isPositiveProgress ? Color.success : Color.danger
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
        .background(Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
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
        VStack(spacing: SBSLayout.space2) {
            // Progress badge
            HStack(spacing: 6) {
                Image(systemName: summary.isPositiveProgress ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .font(SBSFonts.caption().weight(.semibold))
                Text(String(format: "%@%.1f%% PROGRESS", summary.isPositiveProgress ? "+" : "", summary.gainPercent))
                    .font(SBSFonts.caption().weight(.semibold))
            }
            .foregroundStyle(summary.isPositiveProgress ? .white : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(progressColor)
            )
            .padding(.top, SBSLayout.space4)
            
            // Lift name
            Text(summary.liftName)
                .font(compact ? SBSFonts.title() : SBSFonts.display())
                .foregroundStyle(Color.ink)
            
            // Date range
            HStack(spacing: SBSLayout.space2) {
                Text(dateFormatter.string(from: summary.startDate))
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                
                Text("→")
                    .foregroundStyle(Color.inkSecondary)
                
                Text(dateFormatter.string(from: summary.currentDate))
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, SBSLayout.space4)
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
        HStack(spacing: SBSLayout.space4) {
            // Starting E1RM
            VStack(alignment: .leading, spacing: 2) {
                Text("Started")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                
                Text("\(Int(summary.startE1RM.rounded())) \(summary.unit)")
                    .font(compact ? SBSFonts.heading() : SBSFonts.heading())
                    .foregroundStyle(Color.inkSecondary)
            }
            
            Spacer()
            
            // Arrow
            Image(systemName: "arrow.right")
                .font(SBSFonts.heading())
                .foregroundStyle(Color.inkSecondary)
            
            Spacer()
            
            // Current E1RM
            VStack(alignment: .trailing, spacing: 2) {
                Text("Current")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                
                HStack(spacing: 6) {
                    Text("\(Int(summary.currentE1RM.rounded())) \(summary.unit)")
                        .font(compact ? SBSFonts.heading() : SBSFonts.title())
                        .foregroundStyle(Color.orangeText)
                    
                    // Gain indicator
                    HStack(spacing: 2) {
                        Image(systemName: summary.isPositiveProgress ? "arrow.up" : "arrow.down")
                            .font(SBSFonts.caption().weight(.semibold))
                        Text(String(format: "%@%.0f", summary.isPositiveProgress ? "+" : "", summary.gain))
                            .font(SBSFonts.caption().weight(.semibold))
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
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.orangeText)

                Text("Top Set Training")
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            
            Spacer()
            
            Text("Estimated 1RM Progress")
                .font(SBSFonts.caption())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
        .background(Color.surface.opacity(0.5))
    }
}

// MARK: - Shareable Lift Progress Card (for snapshot)

struct ShareableLiftProgressCard: View {
    let summary: LiftProgressSummary
    
    var body: some View {
        LiftProgressShareCard(summary: summary)
            // Rendered off-screen at a fixed pixel width for export — pin to
            // the default type size so the image is deterministic regardless
            // of the user's Dynamic Type setting.
            .dynamicTypeSize(.large)
            .frame(width: 340)
    }

    // Uses the unified `View.snapshot()` (ImageRenderer, fixed dark scheme,
    // scale 3) for a deterministic export — see the extension above.
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

