import SwiftUI

// MARK: - Program Recommendation Quiz

/// A quiz flow that helps users find the right training program based on their experience,
/// availability, and goals.
struct ProgramRecommendationQuiz: View {
    @Bindable var appState: AppState
    @Binding var selectedProgram: String
    let onDismiss: () -> Void
    /// "Browse All Programs" on the results. Screens already showing the list can leave
    /// this nil, and closing the quiz gets there.
    var onBrowseAll: (() -> Void)? = nil
    let onProgramSelected: (String) -> Void

    @State private var currentQuestion = 0
    @State private var answers = QuizAnswers()
    @State private var showingResults = false
    @State private var animateIn = false
    
    private let questions: [QuizQuestion] = QuizQuestion.allQuestions
    
    var body: some View {
        ZStack {
            // Background: plain bg, no tint
            Color.bg
                .ignoresSafeArea()
            
            if showingResults {
                RecommendationResultsView(
                    appState: appState,
                    answers: answers,
                    selectedProgram: $selectedProgram,
                    onSelectProgram: { programId in
                        onProgramSelected(programId)
                    },
                    onBack: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingResults = false
                            currentQuestion = questions.count - 1
                        }
                    },
                    onDismiss: onDismiss,
                    onBrowseAll: onBrowseAll ?? onDismiss
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                VStack(spacing: 0) {
                    // Header with progress and close button
                    HStack {
                        Button {
                            if currentQuestion > 0 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    currentQuestion -= 1
                                }
                            } else {
                                onDismiss()
                            }
                        } label: {
                            Image(systemName: currentQuestion > 0 ? "chevron.left" : "xmark")
                                .font(SBSFonts.heading())
                                .foregroundStyle(Color.ink)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(currentQuestion > 0 ? "Previous question" : "Close")
                        
                        Spacer()
                        
                        // Progress: square segments, ink once reached, hairline ahead
                        HStack(spacing: SBSLayout.space1) {
                            ForEach(0..<questions.count, id: \.self) { index in
                                Rectangle()
                                    .fill(index <= currentQuestion ? Color.ink : Color.hairline)
                                    .frame(width: index == currentQuestion ? 24 : 12, height: 4)
                                    .animation(.easeOut(duration: 0.15), value: currentQuestion)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Question \(currentQuestion + 1) of \(questions.count)")
                        
                        Spacer()
                        
                        // Skip button
                        Button {
                            onDismiss()
                        } label: {
                            Text("Skip")
                                .font(SBSFonts.caption().weight(.semibold))
                                .foregroundStyle(Color.inkSecondary)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal)
                    
                    // Question content
                    TabView(selection: $currentQuestion) {
                        ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                            QuestionView(
                                question: question,
                                answers: $answers,
                                onAnswer: {
                                    advanceToNextQuestion()
                                }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentQuestion)
                    // Block free swiping between questions — the user must answer
                    // the current question (tapping an option auto-advances) so no
                    // question can be skipped and left scoring on its default value.
                    .gesture(DragGesture())
                }
            }
        }
        .opacity(animateIn ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                animateIn = true
            }
        }
    }
    
    private func advanceToNextQuestion() {
        if currentQuestion < questions.count - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentQuestion += 1
            }
        } else {
            // All questions answered, show results
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showingResults = true
            }
        }
    }
}

// MARK: - Quiz Question Model

struct QuizQuestion {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let options: [QuizOption]
    
    static let allQuestions: [QuizQuestion] = [
        QuizQuestion(
            id: "experience",
            title: "How long have you been lifting?",
            subtitle: "This helps us recommend appropriate progression",
            icon: "figure.strengthtraining.traditional",
            options: [
                QuizOption(id: "beginner", label: "Just starting out", description: "Less than 6 months", icon: "leaf.fill", value: 0),
                QuizOption(id: "novice", label: "Getting the hang of it", description: "6 months to 1 year", icon: "person.fill", value: 1),
                QuizOption(id: "intermediate", label: "Solid foundation", description: "1-3 years consistent", icon: "person.2.fill", value: 2),
                QuizOption(id: "advanced", label: "Experienced lifter", description: "3+ years serious training", icon: "star.fill", value: 3)
            ]
        ),
        QuizQuestion(
            id: "days",
            title: "How many days can you train?",
            subtitle: "Be realistic — consistency beats intensity",
            icon: "calendar",
            options: [
                QuizOption(id: "2", label: "2 days", description: "Busy schedule, max effort", icon: "2.circle.fill", value: 2),
                QuizOption(id: "3", label: "3 days", description: "Great for full body", icon: "3.circle.fill", value: 3),
                QuizOption(id: "4", label: "4 days", description: "Upper/Lower or specialized", icon: "4.circle.fill", value: 4),
                QuizOption(id: "5", label: "5 days", description: "High frequency training", icon: "5.circle.fill", value: 5),
                QuizOption(id: "6", label: "6 days", description: "Maximum volume", icon: "6.circle.fill", value: 6)
            ]
        ),
        QuizQuestion(
            id: "goal",
            title: "What's your main goal?",
            subtitle: "We'll prioritize programs that match your focus",
            icon: "target",
            options: [
                QuizOption(id: "strength", label: "Get stronger", description: "Focus on the big lifts", icon: "bolt.fill", value: 0),
                QuizOption(id: "size", label: "Build muscle", description: "Hypertrophy and volume", icon: "figure.arms.open", value: 1),
                QuizOption(id: "both", label: "Both equally", description: "Balanced approach", icon: "scale.3d", value: 2),
                QuizOption(id: "learn", label: "Learn the lifts", description: "Build a foundation first", icon: "book.fill", value: 3)
            ]
        ),
        QuizQuestion(
            id: "time",
            title: "How long are your workouts?",
            subtitle: "Including warm-up and rest periods",
            icon: "clock.fill",
            options: [
                QuizOption(id: "short", label: "30-45 minutes", description: "Quick and efficient", icon: "hare.fill", value: 0),
                QuizOption(id: "medium", label: "45-75 minutes", description: "Standard session", icon: "clock.fill", value: 1),
                QuizOption(id: "long", label: "75-90+ minutes", description: "I've got time", icon: "tortoise.fill", value: 2)
            ]
        ),
        QuizQuestion(
            id: "complexity",
            title: "How much detail do you want?",
            subtitle: "Some prefer simple, others want optimization",
            icon: "slider.horizontal.3",
            options: [
                QuizOption(id: "simple", label: "Keep it simple", description: "Just tell me what to do", icon: "checkmark.circle.fill", value: 0),
                QuizOption(id: "moderate", label: "Some structure", description: "Progression with clear rules", icon: "list.bullet.rectangle.fill", value: 1),
                QuizOption(id: "detailed", label: "All the details", description: "Percentages, autoregulation, periodization", icon: "chart.bar.doc.horizontal.fill", value: 2)
            ]
        )
    ]
}

struct QuizOption: Identifiable {
    let id: String
    let label: String
    let description: String
    let icon: String
    let value: Int
}

// MARK: - Quiz Answers

struct QuizAnswers {
    var experience: String = ""
    var days: Int = 3
    /// Whether the user explicitly answered the days question. `days` carries a
    /// non-zero default for scoring, so a separate flag is needed to know it was
    /// actually chosen rather than left at its placeholder value.
    var daysAnswered: Bool = false
    var goal: String = ""
    var sessionTime: String = ""
    var complexity: String = ""

    var isComplete: Bool {
        !experience.isEmpty && daysAnswered && !goal.isEmpty && !sessionTime.isEmpty && !complexity.isEmpty
    }
}

// MARK: - Question View

struct QuestionView: View {
    let question: QuizQuestion
    @Binding var answers: QuizAnswers
    let onAnswer: () -> Void
    
    @State private var animateOptions = false
    @State private var isAdvancing = false
    
    private func isSelected(_ optionId: String) -> Bool {
        switch question.id {
        case "experience": return answers.experience == optionId
        case "days": return answers.daysAnswered && answers.days == (Int(optionId) ?? 3)
        case "goal": return answers.goal == optionId
        case "time": return answers.sessionTime == optionId
        case "complexity": return answers.complexity == optionId
        default: return false
        }
    }
    
    private func selectOption(_ option: QuizOption) {
        // A second tap during the short advance delay would skip the next question
        guard !isAdvancing else { return }
        isAdvancing = true

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        switch question.id {
        case "experience": answers.experience = option.id
        case "days":
            answers.days = option.value
            answers.daysAnswered = true
        case "goal": answers.goal = option.id
        case "time": answers.sessionTime = option.id
        case "complexity": answers.complexity = option.id
        default: break
        }
        
        // Small delay before advancing for visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isAdvancing = false
            onAnswer()
        }
    }
    
    var body: some View {
        VStack(spacing: SBSLayout.space6) {
            // Question header
            VStack(spacing: SBSLayout.space4) {
                // The question's glyph in orange-text on a hairline tile, no tint
                Image(systemName: question.icon)
                    .font(SBSFonts.titleLarge())
                    .foregroundStyle(Color.orangeText)
                    .frame(width: 72, height: 72)
                    .card()
                    .accessibilityHidden(true)
                
                VStack(spacing: SBSLayout.space2) {
                    Text(question.title)
                        .font(SBSFonts.title())
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                    
                    Text(question.subtitle)
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, SBSLayout.space4)
            .padding(.top, SBSLayout.space6)

            Spacer()
            
            // Options
            VStack(spacing: SBSLayout.space2) {
                ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                    OptionButton(
                        option: option,
                        isSelected: isSelected(option.id),
                        onTap: { selectOption(option) }
                    )
                    .opacity(animateOptions ? 1 : 0)
                    .offset(y: animateOptions ? 0 : 20)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.7)
                        .delay(Double(index) * 0.05),
                        value: animateOptions
                    )
                }
            }
            .padding(.horizontal, SBSLayout.space4)

            Spacer()
        }
        .onAppear {
            // Reset and animate options
            animateOptions = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                animateOptions = true
            }
        }
    }
}

struct OptionButton: View {
    let option: QuizOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SBSLayout.space3) {
                Image(systemName: option.icon)
                    .font(SBSFonts.heading())
                    .foregroundStyle(isSelected ? Color.orangeText : Color.inkSecondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)

                    Text(option.description)
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
            .selectionCell(isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Recommendation Results View

struct RecommendationResultsView: View {
    @Bindable var appState: AppState
    let answers: QuizAnswers
    @Binding var selectedProgram: String
    let onSelectProgram: (String) -> Void
    let onBack: () -> Void
    let onDismiss: () -> Void
    let onBrowseAll: () -> Void

    @State private var animateIn = false
    @State private var showingPaywall = false
    
    private let storeManager = StoreManager.shared
    
    private var recommendations: [ProgramRecommendation] {
        ProgramScorer.scorePrograms(
            answers: answers,
            availablePrograms: appState.availablePrograms
        )
    }
    
    private func isProgramLocked(_ programId: String) -> Bool {
        !storeManager.canAccessProgram(programId)
    }
    
    private func programInfo(for programId: String) -> AppState.AvailableProgramInfo? {
        appState.availablePrograms.first { $0.id == programId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back to the questions")

                Spacer()

                Text("Recommendations")
                    .font(SBSFonts.heading())
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal)

            ScrollView {
                VStack(spacing: SBSLayout.space6) {
                    // Summary card
                    VStack(alignment: .leading, spacing: SBSLayout.space2) {
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "sparkles")
                                .font(SBSFonts.caption().weight(.semibold))
                                .foregroundStyle(Color.orangeText)
                                .accessibilityHidden(true)
                            SBSEyebrow("Based on your answers")
                                .foregroundStyle(Color.inkSecondary)
                        }

                        Text(summaryText)
                            .font(SBSFonts.body())
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    .padding(.horizontal)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)

                    // Recommended programs
                    VStack(alignment: .leading, spacing: SBSLayout.space3) {
                        SBSSectionEyebrow("Our top picks")
                            .padding(.horizontal)

                        ForEach(Array(recommendations.prefix(3).enumerated()), id: \.element.programId) { index, recommendation in
                            let isLocked = isProgramLocked(recommendation.programId)
                            RecommendationCard(
                                recommendation: recommendation,
                                programInfo: programInfo(for: recommendation.programId),
                                isTopPick: index == 0 && !isLocked,
                                isSelected: selectedProgram == recommendation.programId,
                                isLocked: isLocked,
                                onSelect: {
                                    selectedProgram = recommendation.programId
                                    onSelectProgram(recommendation.programId)
                                },
                                onLockedTap: {
                                    showingPaywall = true
                                }
                            )
                            .padding(.horizontal)
                            .opacity(animateIn ? 1 : 0)
                            .offset(y: animateIn ? 0 : 20)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.7)
                                .delay(0.1 + Double(index) * 0.1),
                                value: animateIn
                            )
                        }
                    }

                    // Other options
                    if recommendations.count > 3 {
                        VStack(alignment: .leading, spacing: SBSLayout.space3) {
                            SBSSectionEyebrow("Other options")
                                .padding(.horizontal)

                            ForEach(recommendations.dropFirst(3), id: \.programId) { recommendation in
                                let isLocked = isProgramLocked(recommendation.programId)
                                RecommendationCardCompact(
                                    recommendation: recommendation,
                                    programInfo: programInfo(for: recommendation.programId),
                                    isSelected: selectedProgram == recommendation.programId,
                                    isLocked: isLocked,
                                    onSelect: {
                                        selectedProgram = recommendation.programId
                                        onSelectProgram(recommendation.programId)
                                    },
                                    onLockedTap: {
                                        showingPaywall = true
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                        .opacity(animateIn ? 1 : 0)
                    }

                    // Browse all: the alternative to picking a card, so secondary
                    Button {
                        onBrowseAll()
                    } label: {
                        HStack(spacing: SBSLayout.space2) {
                            Image(systemName: "list.bullet")
                                .font(SBSFonts.button())
                                .accessibilityHidden(true)
                            SBSButtonTitle("Browse All Programs")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SBSSecondaryButtonStyle())
                    .padding(.horizontal)
                    .padding(.bottom, SBSLayout.space6)
                    .opacity(animateIn ? 1 : 0)
                }
                .padding(.vertical)
            }
        }
        .background(Color.bg)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(triggeredByFeature: .allPrograms)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                animateIn = true
            }
        }
    }

    private var summaryText: String {
        var parts: [String] = []
        
        switch answers.experience {
        case "beginner", "novice":
            parts.append("Starting with a beginner-friendly program")
        case "intermediate":
            parts.append("Ready for intermediate programming")
        case "advanced":
            parts.append("Advanced periodization recommended")
        default: break
        }
        
        parts.append("\(answers.days) days per week")
        
        switch answers.goal {
        case "strength":
            parts.append("strength focus")
        case "size":
            parts.append("hypertrophy focus")
        case "both":
            parts.append("balanced strength & size")
        case "learn":
            parts.append("technique development")
        default: break
        }
        
        return parts.joined(separator: " · ")
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    let recommendation: ProgramRecommendation
    let programInfo: AppState.AvailableProgramInfo?
    let isTopPick: Bool
    let isSelected: Bool
    let isLocked: Bool
    let onSelect: () -> Void
    let onLockedTap: () -> Void
    
    @State private var showingDetail = false
    
    private var programLevel: ProgramLevel {
        // Determine level based on program ID
        switch recommendation.programId {
        case "stronglifts_5x5_12week", "greyskull_lp_12week", "starting_strength_12week":
            return .beginner
        case "gzclp_12week", "gzclp_3day_12week", "531_triumvirate_12week", "531_bbb_12week", "reddit_ppl_12week", "nsuns_5day_12week", "nsuns_4day_12week":
            return .intermediate
        case "sbs_program_config":
            return .advanced
        default:
            return .intermediate
        }
    }
    
    var body: some View {
        // The card selects; the info button beside it is its own target
        HStack(alignment: .top, spacing: 0) {
            Button(action: {
                if isLocked {
                    onLockedTap()
                } else {
                    onSelect()
                }
            }) {
                VStack(alignment: .leading, spacing: SBSLayout.space3) {
                    // Best match: an orange-text eyebrow, never a coloured stroke
                    if isTopPick && !isLocked {
                        HStack(spacing: SBSLayout.space1) {
                            Image(systemName: "star.fill")
                                .font(SBSFonts.eyebrow())
                                .accessibilityHidden(true)
                            SBSEyebrow("Best match")
                        }
                        .foregroundStyle(Color.orangeText)
                    }

                    // Program name, match and Free/Pro
                    HStack(alignment: .top, spacing: SBSLayout.space3) {
                        ProgramSelectionMark(isSelected: isSelected, isLocked: isLocked)

                        VStack(alignment: .leading, spacing: SBSLayout.space1) {
                            Text(recommendation.displayName)
                                .font(SBSFonts.heading())
                                .foregroundStyle(isLocked ? Color.inkSecondary : Color.ink)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: SBSLayout.space2) {
                                if recommendation.isFree {
                                    SBSBadge(text: "Free")
                                } else {
                                    SBSBadge(text: "Pro", variant: .pro, systemImage: "lock.fill")
                                }

                                Text("\(Int(recommendation.matchScore))% match")
                                    .font(SBSFonts.numberSmall())
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Description
                    Text(recommendation.programDescription)
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Tags: neutral badges, the word does the work
                    HStack(spacing: SBSLayout.space1) {
                        ForEach(recommendation.tags.prefix(3), id: \.self) { tag in
                            SBSBadge(text: tag)
                        }
                    }

                    // Why this program (only show if not locked)
                    if !recommendation.reasons.isEmpty && !isLocked {
                        VStack(alignment: .leading, spacing: SBSLayout.space1) {
                            ForEach(recommendation.reasons.prefix(2), id: \.self) { reason in
                                HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                                    Image(systemName: "checkmark")
                                        .font(SBSFonts.caption().weight(.bold))
                                        .foregroundStyle(Color.success)
                                        .accessibilityHidden(true)
                                    Text(reason)
                                        .font(SBSFonts.caption())
                                        .foregroundStyle(Color.inkSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }

                    // Upgrade prompt for locked programs
                    if isLocked {
                        HStack(spacing: SBSLayout.space1) {
                            Image(systemName: "lock.fill")
                                .font(SBSFonts.caption())
                                .accessibilityHidden(true)
                            Text("Upgrade to unlock this program")
                                .font(SBSFonts.caption().weight(.semibold))
                        }
                        .foregroundStyle(Color.orangeText)
                    }
                }
                .padding(.vertical, SBSLayout.space4)
                .padding(.leading, SBSLayout.space4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected && !isLocked ? [.isSelected] : [])

            if programInfo != nil {
                ProgramInfoButton(label: "About \(recommendation.displayName)") {
                    showingDetail = true
                }
                .padding(.top, SBSLayout.space2)
                .padding(.trailing, SBSLayout.space1)
            }
        }
        .selectionCell(isSelected && !isLocked)
        .sheet(isPresented: $showingDetail) {
            if let info = programInfo {
                ProgramDetailView(
                    program: info,
                    // Orange as text and icons; no colour per level
                    level: programLevel
                )
            }
        }
    }
}

struct RecommendationCardCompact: View {
    let recommendation: ProgramRecommendation
    let programInfo: AppState.AvailableProgramInfo?
    let isSelected: Bool
    let isLocked: Bool
    let onSelect: () -> Void
    let onLockedTap: () -> Void

    @State private var showingDetail = false

    private var programLevel: ProgramLevel {
        switch recommendation.programId {
        case "stronglifts_5x5_12week", "greyskull_lp_12week", "starting_strength_12week":
            return .beginner
        case "gzclp_12week", "gzclp_3day_12week", "531_triumvirate_12week", "531_bbb_12week", "reddit_ppl_12week", "nsuns_5day_12week", "nsuns_4day_12week":
            return .intermediate
        case "sbs_program_config":
            return .advanced
        default:
            return .intermediate
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: {
                if isLocked {
                    onLockedTap()
                } else {
                    onSelect()
                }
            }) {
                HStack(alignment: .top, spacing: SBSLayout.space3) {
                    ProgramSelectionMark(isSelected: isSelected, isLocked: isLocked)

                    VStack(alignment: .leading, spacing: SBSLayout.space1) {
                        Text(recommendation.displayName)
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(isLocked ? Color.inkSecondary : Color.ink)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: SBSLayout.space2) {
                            if recommendation.isFree {
                                SBSBadge(text: "Free")
                            } else {
                                SBSBadge(text: "Pro", variant: .pro, systemImage: "lock.fill")
                            }

                            SBSRowSubtitle("\(recommendation.days) days/week · \(Int(recommendation.matchScore))%")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, SBSLayout.space3)
                .padding(.leading, SBSLayout.space4)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected && !isLocked ? [.isSelected] : [])

            if programInfo != nil {
                ProgramInfoButton(label: "About \(recommendation.displayName)") {
                    showingDetail = true
                }
                .padding(.trailing, SBSLayout.space1)
            }
        }
        .selectionCell(isSelected && !isLocked)
        .sheet(isPresented: $showingDetail) {
            if let info = programInfo {
                ProgramDetailView(
                    program: info,
                    // Orange as text and icons; no colour per level
                    level: programLevel
                )
            }
        }
    }
}

// MARK: - Program Scoring Engine

struct ProgramRecommendation: Identifiable {
    let id: String
    let programId: String
    let displayName: String
    let programDescription: String
    let days: Int
    let matchScore: Double
    let tags: [String]
    let reasons: [String]
    let isFree: Bool
}

struct ProgramScorer {
    /// Metadata about each program for scoring
    struct ProgramMetadata {
        let id: String
        let experienceLevel: Int        // 0 = beginner, 1 = novice, 2 = intermediate, 3 = advanced
        let days: Int
        let goalFocus: String            // "strength", "size", "both", "learn"
        let sessionTime: String          // "short", "medium", "long"
        let complexity: String           // "simple", "moderate", "detailed"
        let tags: [String]
    }
    
    static let programMetadata: [String: ProgramMetadata] = [
        "stronglifts_5x5_12week": ProgramMetadata(
            id: "stronglifts_5x5_12week",
            experienceLevel: 0,
            days: 3,
            goalFocus: "strength",
            sessionTime: "short",
            complexity: "simple",
            tags: ["Beginner", "3 Days", "Linear", "Simple"]
        ),
        "starting_strength_12week": ProgramMetadata(
            id: "starting_strength_12week",
            experienceLevel: 0,
            days: 3,
            goalFocus: "learn",
            sessionTime: "short",
            complexity: "simple",
            tags: ["Beginner", "3 Days", "Foundational", "Classic"]
        ),
        "greyskull_lp_12week": ProgramMetadata(
            id: "greyskull_lp_12week",
            experienceLevel: 0,
            days: 3,
            goalFocus: "both",
            sessionTime: "short",
            complexity: "simple",
            tags: ["Beginner", "3 Days", "AMRAP", "Flexible"]
        ),
        "gzclp_12week": ProgramMetadata(
            id: "gzclp_12week",
            experienceLevel: 1,
            days: 4,
            goalFocus: "both",
            sessionTime: "medium",
            complexity: "moderate",
            tags: ["Late Beginner", "4 Days", "Tiered", "Structured"]
        ),
        "gzclp_3day_12week": ProgramMetadata(
            id: "gzclp_3day_12week",
            experienceLevel: 1,
            days: 3,
            goalFocus: "both",
            sessionTime: "medium",
            complexity: "moderate",
            tags: ["Late Beginner", "3 Days", "Tiered", "Rotating"]
        ),
        "531_triumvirate_12week": ProgramMetadata(
            id: "531_triumvirate_12week",
            experienceLevel: 2,
            days: 4,
            goalFocus: "strength",
            sessionTime: "medium",
            complexity: "moderate",
            tags: ["Intermediate", "4 Days", "Wave Loading", "Time-Efficient"]
        ),
        "531_bbb_12week": ProgramMetadata(
            id: "531_bbb_12week",
            experienceLevel: 2,
            days: 4,
            goalFocus: "both",
            sessionTime: "long",
            complexity: "moderate",
            tags: ["Intermediate", "4 Days", "High Volume", "Size + Strength"]
        ),
        "nsuns_4day_12week": ProgramMetadata(
            id: "nsuns_4day_12week",
            experienceLevel: 2,
            days: 4,
            goalFocus: "strength",
            sessionTime: "long",
            complexity: "detailed",
            tags: ["Intermediate", "4 Days", "High Volume", "Intense"]
        ),
        "nsuns_5day_12week": ProgramMetadata(
            id: "nsuns_5day_12week",
            experienceLevel: 2,
            days: 5,
            goalFocus: "strength",
            sessionTime: "long",
            complexity: "detailed",
            tags: ["Intermediate", "5 Days", "High Volume", "Maximum Gains"]
        ),
        "reddit_ppl_12week": ProgramMetadata(
            id: "reddit_ppl_12week",
            experienceLevel: 2,
            days: 6,
            goalFocus: "size",
            sessionTime: "medium",
            complexity: "moderate",
            tags: ["Intermediate", "6 Days", "PPL Split", "Hypertrophy"]
        ),
        "sbs_program_config": ProgramMetadata(
            id: "sbs_program_config",
            experienceLevel: 3,
            days: 5,
            goalFocus: "both",
            sessionTime: "long",
            complexity: "detailed",
            tags: ["Advanced", "5 Days", "Auto-Regulated", "20 Weeks"]
        ),
        "basic_ppl_12week": ProgramMetadata(
            id: "basic_ppl_12week",
            experienceLevel: 1,
            days: 3,
            goalFocus: "size",
            sessionTime: "medium",
            complexity: "simple",
            tags: ["Beginner", "3 Days", "PPL Split", "Hypertrophy"]
        ),
        "phul_12week": ProgramMetadata(
            id: "phul_12week",
            experienceLevel: 2,
            days: 4,
            goalFocus: "both",
            sessionTime: "medium",
            complexity: "moderate",
            tags: ["Intermediate", "4 Days", "Upper/Lower", "Power + Size"]
        ),
        "531_fsl_12week": ProgramMetadata(
            id: "531_fsl_12week",
            experienceLevel: 2,
            days: 4,
            goalFocus: "both",
            sessionTime: "medium",
            complexity: "moderate",
            tags: ["Intermediate", "4 Days", "Wave Loading", "Lower Volume"]
        ),
        "back_friendly_hypertrophy_12week": ProgramMetadata(
            id: "back_friendly_hypertrophy_12week",
            experienceLevel: 2,
            days: 5,
            goalFocus: "size",
            sessionTime: "long",
            complexity: "moderate",
            tags: ["Intermediate", "5 Days", "Low Spinal Load", "Hypertrophy"]
        ),
        "nsuns_6day_squat_12week": ProgramMetadata(
            id: "nsuns_6day_squat_12week",
            experienceLevel: 2,
            days: 6,
            goalFocus: "strength",
            sessionTime: "long",
            complexity: "detailed",
            tags: ["Intermediate", "6 Days", "High Volume", "Extra Squats"]
        ),
        "nsuns_6day_deadlift_12week": ProgramMetadata(
            id: "nsuns_6day_deadlift_12week",
            experienceLevel: 2,
            days: 6,
            goalFocus: "strength",
            sessionTime: "long",
            complexity: "detailed",
            tags: ["Intermediate", "6 Days", "High Volume", "Extra Deadlifts"]
        )
    ]
    
    static func scorePrograms(
        answers: QuizAnswers,
        availablePrograms: [AppState.AvailableProgramInfo]
    ) -> [ProgramRecommendation] {
        
        var recommendations: [ProgramRecommendation] = []
        
        let userExperience: Int
        switch answers.experience {
        case "beginner": userExperience = 0
        case "novice": userExperience = 1
        case "intermediate": userExperience = 2
        case "advanced": userExperience = 3
        default: userExperience = 1
        }
        
        for program in availablePrograms {
            guard let metadata = programMetadata[program.id] else { continue }
            
            var score: Double = 0
            var reasons: [String] = []
            
            // Experience match (30 points max)
            let expDiff = abs(metadata.experienceLevel - userExperience)
            if expDiff == 0 {
                score += 30
                reasons.append("Perfect match for your experience level")
            } else if expDiff == 1 {
                score += 20
                if metadata.experienceLevel < userExperience {
                    reasons.append("Slightly easier — good for deload phases")
                }
            } else {
                score += Double(max(0, 10 - expDiff * 5))
            }
            
            // Days match (30 points max)
            let daysDiff = abs(metadata.days - answers.days)
            if daysDiff == 0 {
                score += 30
                reasons.append("Matches your \(answers.days)-day schedule exactly")
            } else if daysDiff == 1 {
                score += 20
            } else {
                score += Double(max(0, 10 - daysDiff * 5))
            }
            
            // Goal match (20 points max)
            if metadata.goalFocus == answers.goal {
                score += 20
                switch answers.goal {
                case "strength": reasons.append("Strength-focused programming")
                case "size": reasons.append("Hypertrophy-optimized volume")
                case "both": reasons.append("Balanced strength and size approach")
                case "learn": reasons.append("Great for building technique")
                default: break
                }
            } else if metadata.goalFocus == "both" || answers.goal == "both" {
                score += 15
            } else {
                score += 5
            }
            
            // Session time match (10 points max)
            if metadata.sessionTime == answers.sessionTime {
                score += 10
            } else if (metadata.sessionTime == "medium") || (answers.sessionTime == "medium") {
                score += 5
            }
            
            // Complexity match (10 points max)
            if metadata.complexity == answers.complexity {
                score += 10
                switch answers.complexity {
                case "simple": reasons.append("Simple, no-nonsense approach")
                case "moderate": reasons.append("Clear structure with room to grow")
                case "detailed": reasons.append("Full periodization and autoregulation")
                default: break
                }
            } else if (metadata.complexity == "moderate") || (answers.complexity == "moderate") {
                score += 5
            }
            
            // Normalize to 100
            let normalizedScore = min(100, score)
            
            recommendations.append(ProgramRecommendation(
                id: program.id,
                programId: program.id,
                displayName: program.displayName,
                programDescription: program.programDescription,
                days: metadata.days,
                matchScore: normalizedScore,
                tags: metadata.tags,
                reasons: reasons,
                isFree: StoreManager.isProgramFree(program.id)
            ))
        }
        
        // Sort by score descending
        return recommendations.sorted { $0.matchScore > $1.matchScore }
    }
}

// MARK: - Preview

#Preview {
    ProgramRecommendationQuiz(
        appState: AppState(),
        selectedProgram: .constant("stronglifts_5x5_12week"),
        onDismiss: {},
        onProgramSelected: { _ in }
    )
}

