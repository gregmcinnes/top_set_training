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
    /// For the plate strip under the top set
    var barWeight: Double = 45
    /// Per-exercise bars (lb), keyed by `UserSettings.barKey`; missing means `barWeight`
    var barWeights: [String: Double] = [:]

    func barWeight(for exercise: String) -> Double {
        barWeights[UserSettings.barKey(exercise)] ?? barWeight
    }
    
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

/// The workout as an image to share. Rendered off-screen by `snapshot(colorScheme:)`, so
/// every colour is a token that resolves for the scheme it's rendered in: no literal
/// colours, no shadow (an image has nothing to cast one on), hairline edges only.
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

    private var eyebrowText: String {
        var parts = ["Week \(summary.week)", "Day \(summary.day)"]
        if let programName = summary.programName, !programName.isEmpty { parts.append(programName) }
        return parts.joined(separator: " · ")
    }

    private var mainExercises: [WorkoutSummary.ExerciseSummary] {
        summary.exercises.filter { !$0.isAccessory }
    }

    /// The set the card leads with: a PR's set, else the first main lift's
    private var topSet: (name: String, weight: Double, reps: String)? {
        if let pr = summary.prs.first {
            return (pr.liftName, pr.weight, "\(pr.reps)")
        }
        guard let lift = mainExercises.first(where: { $0.weight > 0 }) else { return nil }
        return (lift.name, lift.weight, lift.reps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            if let topSet {
                ShareCardDivider()
                ShareCardTopSet(
                    name: topSet.name,
                    weight: topSet.weight,
                    reps: topSet.reps,
                    barWeight: summary.barWeight(for: topSet.name),
                    useMetric: useMetric,
                    isPR: hasPRs
                )
            }

            if !mainExercises.isEmpty || summary.exercises.contains(where: \.isAccessory) {
                ShareCardDivider()
                exercisesSection
            }

            if hasPRs {
                ShareCardDivider()
                prsSection
            }

            ShareCardDivider()
            ShareCardFooter(detail: "\(summary.totalSets) sets")
        }
        .shareCardFrame()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            HStack(alignment: .top) {
                SBSEyebrow(eyebrowText)
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(2)

                Spacer(minLength: SBSLayout.space2)

                if hasPRs {
                    SBSBadge(text: summary.prs.count > 1 ? "\(summary.prs.count) PRs" : "PR", variant: .pr)
                }
            }

            Text(summary.dayTitle)
                .font(compact ? SBSFonts.heading() : SBSFonts.title())
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(dateFormatter.string(from: summary.date))
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(SBSLayout.space6)
    }

    // MARK: - Exercises Section

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSEyebrow("Lifts")
                .foregroundStyle(Color.inkSecondary)

            ForEach(mainExercises) { exercise in
                ShareCardExerciseRow(exercise: exercise, useMetric: useMetric, compact: compact, isPR: summary.prs.contains { $0.liftName == exercise.name })
            }

            let accessories = summary.exercises.filter { $0.isAccessory }
            if !accessories.isEmpty {
                HStack(spacing: SBSLayout.space2) {
                    Image(systemName: "dumbbell")
                        .font(SBSFonts.caption())
                    Text(accessories.count == 1 ? "1 accessory" : "\(accessories.count) accessories")
                        .font(SBSFonts.caption())
                }
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, SBSLayout.space1)
            }
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
    }

    // MARK: - PRs Section

    private var prsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSEyebrow(summary.prs.count > 1 ? "Personal records" : "Personal record")
                .foregroundStyle(Color.inkSecondary)

            ForEach(summary.prs) { pr in
                ShareCardPRRow(pr: pr, useMetric: useMetric, compact: compact)
            }
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
    }
}

// MARK: - Share Card Pieces

private extension View {
    /// Every share card: surface, a 1px ink edge so it holds its shape on a feed,
    /// radius-sm, no shadow.
    func shareCardFrame() -> some View {
        background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(Color.ink, lineWidth: SBSLayout.strokeHairline)
            )
    }
}

private struct ShareCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: SBSLayout.strokeHairline)
    }
}

/// The working weight in display type with its plates: the brand's hero numeral.
private struct ShareCardTopSet: View {
    let name: String
    let weight: Double
    let reps: String
    let barWeight: Double
    let useMetric: Bool
    let isPR: Bool

    private var result: PlateCalculatorResult {
        PlateCalculator(barWeight: barWeight, useMetric: useMetric).calculate(totalWeight: weight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSEyebrow(isPR ? "PR set · \(name)" : "Top set · \(name)")
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                Text(weight.formattedWeightShort(useMetric: useMetric))
                    .font(SBSFonts.workingWeight())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(useMetric ? "kg" : "lb")
                    .font(SBSFonts.numberUnit())
                    .foregroundStyle(Color.inkSecondary)

                Text("× \(reps)")
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.ink)
                    .padding(.leading, SBSLayout.space2)
            }

            if weight > barWeight {
                PlateStrip(plates: result.platesPerSide)
                Text(PlateText.perSide(result, useMetric: useMetric))
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "TOP SET TRAINING" on the left, a detail in number-small on the right.
private struct ShareCardFooter: View {
    let detail: String

    var body: some View {
        HStack {
            SBSEyebrow("Top Set Training")
                .foregroundStyle(Color.ink)

            Spacer()

            Text(detail)
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
        .background(Color.bg)
    }
}

// MARK: - Share Card Exercise Row

private struct ShareCardExerciseRow: View {
    let exercise: WorkoutSummary.ExerciseSummary
    let useMetric: Bool
    var compact: Bool = false
    var isPR: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space3) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SBSLayout.space2) {
                    Text(exercise.name)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)

                    if isPR {
                        PRBadge(small: true)
                    }
                }

                Text("\(exercise.sets) × \(exercise.reps)\(exercise.isAMRAP ? " · AMRAP" : "")")
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }

            Spacer(minLength: SBSLayout.space2)

            VStack(alignment: .trailing, spacing: 2) {
                Text(exercise.weight.formattedWeight(useMetric: useMetric))
                    .font(compact ? SBSFonts.numberSmall() : SBSFonts.number())
                    .foregroundStyle(Color.ink)

                if let e1rm = exercise.estimatedOneRM {
                    Text("e1RM \(e1rm.rounded().formattedWeightShort(useMetric: useMetric))")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .padding(.vertical, compact ? 2 : 4)
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
        HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pr.liftName)
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.ink)

                Text("\(pr.weight.formattedWeightShort(useMetric: useMetric)) × \(pr.reps)")
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }

            Spacer(minLength: SBSLayout.space2)

            VStack(alignment: .trailing, spacing: 2) {
                Text("e1RM \(pr.newE1RM.rounded().formattedWeight(useMetric: useMetric))")
                    .font(compact ? SBSFonts.numberSmall() : SBSFonts.number())
                    .foregroundStyle(Color.ink)

                if let improvement, let percent = improvementPercent {
                    SBSChangeLabel(
                        text: "\(improvement.rounded().formattedWeightShort(useMetric: useMetric)) (\(String(format: "%.1f", percent))%)",
                        isUp: improvement >= 0
                    )
                } else {
                    Text("First PR")
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.orangeText)
                }
            }
        }
    }
}

// MARK: - Share Card Wrapper (for screenshot/export)

/// The card on a plain bg margin, at a fixed width and type size for export.
private struct ShareCardCanvas<Card: View>: View {
    let width: CGFloat
    @ViewBuilder var card: Card

    var body: some View {
        card
            // Rendered off-screen at a fixed pixel width for export — pin to
            // the default type size so the image is deterministic regardless
            // of the user's Dynamic Type setting.
            .dynamicTypeSize(.large)
            .frame(width: width)
            .padding(SBSLayout.space6)
            .background(Color.bg)
    }
}

struct ShareableWorkoutCard: View {
    let summary: WorkoutSummary
    let useMetric: Bool

    var body: some View {
        ShareCardCanvas(width: 360) {
            WorkoutShareCard(summary: summary, useMetric: useMetric)
        }
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
    /// The colour scheme is set in the environment, so the asset-catalogue tokens
    /// the cards use resolve for it whatever the app's own appearance. The share
    /// sheets pass the scheme they're shown in, so the image matches the preview.
    @MainActor
    func snapshot(colorScheme: ColorScheme = .dark, scale: CGFloat = 3) -> UIImage {
        let renderer = ImageRenderer(content: self.environment(\.colorScheme, colorScheme))
        renderer.scale = scale
        return renderer.uiImage ?? UIImage()
    }
}

// MARK: - Share Sheet Helper

/// The share sheet's one action: a primary ShareLink.
private struct ShareImageButton: View {
    let title: String
    let image: UIImage
    let previewTitle: String

    var body: some View {
        ShareLink(
            item: Image(uiImage: image),
            preview: SharePreview(previewTitle, image: Image(uiImage: image))
        ) {
            HStack(spacing: SBSLayout.space2) {
                Image(systemName: "square.and.arrow.up")
                    .accessibilityHidden(true)
                SBSButtonTitle(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SBSPrimaryButtonStyle())
        .padding(.horizontal, SBSLayout.space6)
        .padding(.trailing, SBSLayout.hardShadowOffset)
        .padding(.bottom, SBSLayout.hardShadowOffset)
    }
}

struct WorkoutShareSheet: View {
    let summary: WorkoutSummary
    let useMetric: Bool
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
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

                if let image = shareImage {
                    ShareImageButton(
                        title: "Share Workout",
                        image: image,
                        previewTitle: "Workout Complete - \(summary.dayTitle)"
                    )
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
        shareImage = shareableView.snapshot(colorScheme: colorScheme)
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
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            ShareCardDivider()
            progressBarSection
            ShareCardDivider()
            liftsSection

            if hasPRs {
                ShareCardDivider()
                prsSection
            }

            ShareCardDivider()
            ShareCardFooter(detail: summary.weeksCompleted == 1 ? "1 week" : "\(summary.weeksCompleted) weeks")
        }
        .shareCardFrame()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            HStack(alignment: .top) {
                SBSEyebrow("Cycle \(summary.cycleNumber) · \(summary.isComplete ? "Complete" : "In progress")")
                    .foregroundStyle(Color.inkSecondary)

                Spacer(minLength: SBSLayout.space2)

                if hasPRs {
                    SBSBadge(text: summary.personalRecords.count > 1 ? "\(summary.personalRecords.count) PRs" : "PR", variant: .pr)
                } else if summary.isComplete {
                    SBSBadge(text: "Done", variant: .status(.success), systemImage: "checkmark")
                }
            }

            Text(summary.programName)
                .font(compact ? SBSFonts.heading() : SBSFonts.title())
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(dateFormatter.string(from: summary.startDate)) → \(dateFormatter.string(from: summary.currentDate))")
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(SBSLayout.space6)
    }

    // MARK: - Progress Bar Section

    private var progressBarSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            // Week progress: an orange fill on a hairline track, square ends
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                        .fill(Color.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                                .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
                        )

                    Rectangle()
                        .fill(Color.orangeFill)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, summary.progressPercent / 100))))
                }
            }
            .frame(height: 8)

            HStack {
                Text("Week \(summary.currentWeek) of \(summary.totalWeeks)")
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.ink)

                Spacer()

                Text(String(format: "%.0f%%", summary.progressPercent))
                    .font(SBSFonts.numberSmall())
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
    }

    // MARK: - Lifts Section

    private var liftsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space3) {
            // Overall summary stats
            HStack(alignment: .top, spacing: SBSLayout.space6) {
                stat("Avg gain") {
                    SBSChangeLabel(text: String(format: "%.1f%%", abs(summary.averageGainPercent)), isUp: isPositiveProgress)
                        .font(SBSFonts.number())
                }

                stat("TM gained") {
                    Text(summary.totalWeightGained >= 0 ? "+\(summary.totalWeightGained.formattedWeightShort(useMetric: useMetric))" : summary.totalWeightGained.formattedWeightShort(useMetric: useMetric))
                        .font(SBSFonts.number())
                        .foregroundStyle(Color.ink)
                }

                if hasPRs {
                    stat("New PRs") {
                        Text("\(summary.personalRecords.count)")
                            .font(SBSFonts.number())
                            .foregroundStyle(Color.ink)
                    }
                }
            }

            SBSEyebrow("Training maxes")
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, SBSLayout.space2)

            ForEach(summary.lifts) { lift in
                LiftProgressRow(lift: lift, useMetric: useMetric, compact: compact, hasPR: summary.personalRecords.contains { $0.liftName == lift.name })
            }
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
    }

    private func stat<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value()
            SBSEyebrow(label)
                .foregroundStyle(Color.inkSecondary)
        }
    }

    // MARK: - PRs Section

    private var prsSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            SBSEyebrow("Personal records")
                .foregroundStyle(Color.inkSecondary)

            ForEach(summary.personalRecords) { pr in
                HStack(alignment: .firstTextBaseline) {
                    Text(pr.liftName)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)

                    Spacer(minLength: SBSLayout.space2)

                    Text("\(pr.weight.formattedWeightShort(useMetric: useMetric)) × \(pr.reps)")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)

                    Text("e1RM \(pr.e1rm.rounded().formattedWeight(useMetric: useMetric))")
                        .font(SBSFonts.numberSmall().weight(.semibold))
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
    }
}

// MARK: - Lift Progress Row

private struct LiftProgressRow: View {
    let lift: ProgressSummary.LiftProgress
    let useMetric: Bool
    var compact: Bool = false
    var hasPR: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space3) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SBSLayout.space2) {
                    Text(lift.name)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)

                    if hasPR {
                        PRBadge(small: true)
                    }
                }

                if let e1rm = lift.bestE1RM {
                    Text("Best e1RM \(e1rm.formattedWeightShort(useMetric: useMetric))")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            Spacer(minLength: SBSLayout.space2)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space1) {
                    Text(lift.startingTM.formattedWeightShort(useMetric: useMetric))
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)

                    Text("→")
                        .font(SBSFonts.numberSmall())
                        .foregroundStyle(Color.inkSecondary)

                    Text(lift.currentTM.formattedWeightShort(useMetric: useMetric))
                        .font(compact ? SBSFonts.numberSmall() : SBSFonts.number())
                        .foregroundStyle(Color.ink)
                }

                SBSChangeLabel(text: String(format: "%.1f%%", abs(lift.gainPercent)), isUp: lift.gain >= 0)
            }
        }
        .padding(.vertical, compact ? 2 : 4)
    }
}

// MARK: - Shareable Progress Card Wrapper

struct ShareableProgressCard: View {
    let summary: ProgressSummary
    let useMetric: Bool

    var body: some View {
        ShareCardCanvas(width: 380) {
            ProgressShareCard(summary: summary, useMetric: useMetric)
        }
    }
}

// MARK: - Progress Share Sheet

struct ProgressShareSheet: View {
    let summary: ProgressSummary
    let useMetric: Bool
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
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
                    ShareImageButton(
                        title: "Share Progress",
                        image: image,
                        previewTitle: "\(summary.programName) - Cycle \(summary.cycleNumber) Progress"
                    )
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
        shareImage = shareableView.snapshot(colorScheme: colorScheme)
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

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            ShareCardDivider()
            progressRow
            ShareCardDivider()
            ShareCardFooter(detail: "Estimated 1RM")
        }
        .shareCardFrame()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            HStack(alignment: .top) {
                SBSEyebrow("Estimated 1RM progress")
                    .foregroundStyle(Color.inkSecondary)

                Spacer(minLength: SBSLayout.space2)

                // The change as a status badge: arrow glyph and the number carry it
                SBSBadge(
                    text: String(format: "%@%.1f%%", summary.isPositiveProgress ? "+" : "", summary.gainPercent),
                    variant: .status(summary.isPositiveProgress ? .success : .danger),
                    systemImage: summary.isPositiveProgress ? "arrow.up" : "arrow.down"
                )
            }

            Text(summary.liftName)
                .font(compact ? SBSFonts.heading() : SBSFonts.title())
                .foregroundStyle(Color.ink)

            Text("\(dateFormatter.string(from: summary.startDate)) → \(dateFormatter.string(from: summary.currentDate))")
                .font(SBSFonts.numberSmall())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(SBSLayout.space6)
    }

    // MARK: - Progress Row

    private var progressRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: SBSLayout.space4) {
            VStack(alignment: .leading, spacing: 2) {
                SBSEyebrow("Started")
                    .foregroundStyle(Color.inkSecondary)

                Text("\(Int(summary.startE1RM.rounded())) \(summary.unit)")
                    .font(SBSFonts.number())
                    .foregroundStyle(Color.inkSecondary)
            }

            Spacer(minLength: SBSLayout.space2)

            Image(systemName: "arrow.right")
                .font(SBSFonts.number())
                .foregroundStyle(Color.inkSecondary)

            Spacer(minLength: SBSLayout.space2)

            VStack(alignment: .trailing, spacing: 2) {
                SBSEyebrow("Now")
                    .foregroundStyle(Color.inkSecondary)

                HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space1) {
                    Text("\(Int(summary.currentE1RM.rounded()))")
                        .font(SBSFonts.numberLarge())
                        .foregroundStyle(Color.ink)
                    Text(summary.unit)
                        .font(SBSFonts.numberUnit())
                        .foregroundStyle(Color.inkSecondary)
                }

                SBSChangeLabel(text: String(format: "%.0f", abs(summary.gain)), isUp: summary.isPositiveProgress)
            }
        }
        .padding(.horizontal, SBSLayout.space6)
        .padding(.vertical, SBSLayout.space4)
    }
}

// MARK: - Shareable Lift Progress Card (for snapshot)

struct ShareableLiftProgressCard: View {
    let summary: LiftProgressSummary

    var body: some View {
        ShareCardCanvas(width: 340) {
            LiftProgressShareCard(summary: summary)
        }
    }

    // Uses the unified `View.snapshot(colorScheme:)` (ImageRenderer, scale 3) for a
    // deterministic export — see the extension above.
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

