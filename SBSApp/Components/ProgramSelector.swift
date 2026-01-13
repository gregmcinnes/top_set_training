import SwiftUI

// MARK: - Program Metadata

/// Metadata for each program (used for filtering and display)
struct ProgramMeta {
    let family: String
    let level: ProgramLevel
    let focus: ProgramFocus
    let shortDescription: String
    let isFree: Bool
}

// MARK: - Program Selector (Redesigned)

/// A clean, intuitive program selector with filtering and grouped program families
struct ProgramSelector: View {
    @Bindable var appState: AppState
    @Binding var selectedProgram: String
    let onTakeQuiz: () -> Void
    let onBuildTemplate: () -> Void
    
    @State private var selectedDaysFilter: Int? = nil
    @State private var selectedLevelFilter: ProgramLevel? = nil
    @State private var expandedFamilies: Set<String> = []
    @State private var showingPaywall = false
    
    private let storeManager = StoreManager.shared
    
    private let programMetadata: [String: ProgramMeta] = [
        "stronglifts_5x5_12week": ProgramMeta(
            family: "Strong Lifts",
            level: .beginner,
            focus: .strength,
            shortDescription: "Classic 5×5. Simple and effective.",
            isFree: true
        ),
        "starting_strength_12week": ProgramMeta(
            family: "Starting Strength",
            level: .beginner,
            focus: .strength,
            shortDescription: "The foundational barbell program.",
            isFree: true
        ),
        "greyskull_lp_12week": ProgramMeta(
            family: "Beginner AMRAP",
            level: .beginner,
            focus: .balanced,
            shortDescription: "LP with AMRAP sets for faster progress.",
            isFree: true
        ),
        "gzclp_12week": ProgramMeta(
            family: "GZCL",
            level: .intermediate,
            focus: .balanced,
            shortDescription: "4-day tiered system: heavy, moderate, light.",
            isFree: false
        ),
        "gzclp_3day_12week": ProgramMeta(
            family: "GZCL",
            level: .intermediate,
            focus: .balanced,
            shortDescription: "3-day rotating tiered system.",
            isFree: false
        ),
        "531_triumvirate_12week": ProgramMeta(
            family: "5/3/1",
            level: .intermediate,
            focus: .strength,
            shortDescription: "Simple strength with assistance work.",
            isFree: false
        ),
        "531_bbb_12week": ProgramMeta(
            family: "5/3/1",
            level: .intermediate,
            focus: .balanced,
            shortDescription: "Strength + 5×10 volume for size.",
            isFree: true
        ),
        "nsuns_4day_12week": ProgramMeta(
            family: "nSuns",
            level: .intermediate,
            focus: .strength,
            shortDescription: "High volume, 4 days per week.",
            isFree: false
        ),
        "nsuns_5day_12week": ProgramMeta(
            family: "nSuns",
            level: .intermediate,
            focus: .strength,
            shortDescription: "Maximum volume, 5 days per week.",
            isFree: true
        ),
        "reddit_ppl_12week": ProgramMeta(
            family: "PPL",
            level: .intermediate,
            focus: .hypertrophy,
            shortDescription: "Push/Pull/Legs split, twice per week.",
            isFree: false
        ),
        "sbs_program_config": ProgramMeta(
            family: "SBS",
            level: .advanced,
            focus: .hypertrophy,
            shortDescription: "20-week auto-regulated hypertrophy.",
            isFree: false
        )
    ]
    
    // MARK: - Computed Properties
    
    private var groupedPrograms: [(family: String, programs: [AppState.AvailableProgramInfo])] {
        // Group by family
        var groups: [String: [AppState.AvailableProgramInfo]] = [:]
        
        for program in filteredPrograms {
            let family = programMetadata[program.id]?.family ?? "Other"
            groups[family, default: []].append(program)
        }
        
        // Sort by family name in desired display order
        return groups.map { (family: $0.key, programs: $0.value) }
            .sorted { lhs, rhs in
                // Priority order matching family names in programMetadata
                let order = ["Strong Lifts", "Starting Strength", "Beginner AMRAP", "GZCL", "5/3/1", "nSuns", "PPL", "SBS"]
                let lhsIndex = order.firstIndex(of: lhs.family) ?? 99
                let rhsIndex = order.firstIndex(of: rhs.family) ?? 99
                return lhsIndex < rhsIndex
            }
    }
    
    private var filteredPrograms: [AppState.AvailableProgramInfo] {
        appState.availablePrograms.filter { program in
            // Filter by days
            if let daysFilter = selectedDaysFilter {
                guard program.days == daysFilter else { return false }
            }
            
            // Filter by level
            if let levelFilter = selectedLevelFilter {
                guard programMetadata[program.id]?.level == levelFilter else { return false }
            }
            
            return true
        }
    }
    
    private var availableDays: [Int] {
        Set(appState.availablePrograms.map { $0.days }).sorted()
    }
    
    private func isProgramLocked(_ programId: String) -> Bool {
        !storeManager.canAccessProgram(programId)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            VStack(spacing: SBSLayout.paddingMedium) {
                // Days filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        FilterChip(
                            title: "All Days",
                            isSelected: selectedDaysFilter == nil,
                            onTap: { selectedDaysFilter = nil }
                        )
                        
                        ForEach(availableDays, id: \.self) { days in
                            FilterChip(
                                title: "\(days) Days",
                                isSelected: selectedDaysFilter == days,
                                onTap: { selectedDaysFilter = days }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Level filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        FilterChip(
                            title: "All Levels",
                            isSelected: selectedLevelFilter == nil,
                            onTap: { selectedLevelFilter = nil }
                        )
                        
                        ForEach(ProgramLevel.allCases, id: \.self) { level in
                            FilterChip(
                                title: level.rawValue,
                                icon: level.icon,
                                isSelected: selectedLevelFilter == level,
                                onTap: { selectedLevelFilter = level }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, SBSLayout.paddingMedium)
            .background(SBSColors.backgroundFallback)
            
            // Program list
            ScrollView {
                LazyVStack(spacing: SBSLayout.paddingMedium) {

                    // Quiz prompt (only show if no programs are selected)
                    QuizPromptCard(onTakeQuiz: onTakeQuiz)
                        .padding(.horizontal)
                        .padding(.top, SBSLayout.paddingMedium)
                    
                    // Disclaimer note
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                        Text("All programs are based on popular training programs. Some names are changed.")
                            .font(SBSFonts.caption())
                    }
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .padding(.horizontal)
                    .padding(.vertical, SBSLayout.paddingSmall)

                    // Custom templates (if any)
                    if !appState.userData.customTemplates.isEmpty {
                        CustomTemplatesGroup(
                            templates: appState.userData.customTemplates,
                            selectedProgram: $selectedProgram,
                            isExpanded: expandedFamilies.contains("__custom__"),
                            onToggle: { toggleFamily("__custom__") }
                        )
                    }
                    
                    // Program families
                    ForEach(groupedPrograms, id: \.family) { group in
                        ProgramFamilyGroup(
                            family: group.family,
                            programs: group.programs,
                            selectedProgram: $selectedProgram,
                            isExpanded: shouldExpandFamily(group.family, programs: group.programs),
                            metadata: programMetadata,
                            isProgramLocked: isProgramLocked,
                            isPremiumUser: storeManager.isPremium,
                            onToggle: { toggleFamily(group.family) },
                            onLockedTap: { showingPaywall = true }
                        )
                    }
                    
                    // Empty state
                    if filteredPrograms.isEmpty {
                        VStack(spacing: SBSLayout.paddingMedium) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            
                            Text("No programs matched your filters. More coming soon")
                                .font(SBSFonts.body())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                                .multilineTextAlignment(.center)
                            
                            Button("Clear Filters") {
                                selectedDaysFilter = nil
                                selectedLevelFilter = nil
                            }
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.accentFallback)
                        }
                        .padding(.vertical, SBSLayout.paddingXLarge)
                    }
                    
                    // Template Builder prompt
                    TemplateBuilderPromptCard(onBuildTemplate: onBuildTemplate)
                        .padding(.top, SBSLayout.paddingSmall)
                    
                    
                }
                .padding(.horizontal)
                .padding(.vertical, SBSLayout.paddingMedium)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(triggeredByFeature: .allPrograms)
        }
    }
    
    private func shouldExpandFamily(_ family: String, programs: [AppState.AvailableProgramInfo]) -> Bool {
        // Auto-expand if only one program in family, or if user expanded, or if contains selected
        if programs.count == 1 { return true }
        if expandedFamilies.contains(family) { return true }
        if programs.contains(where: { $0.id == selectedProgram }) { return true }
        return false
    }
    
    private func toggleFamily(_ family: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedFamilies.contains(family) {
                expandedFamilies.remove(family)
            } else {
                expandedFamilies.insert(family)
            }
        }
    }
}

// MARK: - Program Family Group

struct ProgramFamilyGroup: View {
    let family: String
    let programs: [AppState.AvailableProgramInfo]
    @Binding var selectedProgram: String
    let isExpanded: Bool
    let metadata: [String: ProgramMeta]
    let isProgramLocked: (String) -> Bool
    let isPremiumUser: Bool
    let onToggle: () -> Void
    let onLockedTap: () -> Void
    
    private var familyColor: Color {
        // Use the level color of the first program in the family
        if let first = programs.first, let meta = metadata[first.id] {
            return meta.level.color
        }
        return SBSColors.accentFallback
    }
    
    private var hasSelectedProgram: Bool {
        programs.contains { $0.id == selectedProgram }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Family header
            if programs.count > 1 {
                Button(action: onToggle) {
                    HStack(spacing: SBSLayout.paddingMedium) {
                        // Family name
                        VStack(alignment: .leading, spacing: 2) {
                            Text(family)
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text("\(programs.count) variants")
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                        }
                        
                        Spacer()
                        
                        // Chevron
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .fill(hasSelectedProgram ? familyColor.opacity(0.08) : SBSColors.surfaceFallback)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Programs
            if isExpanded || programs.count == 1 {
                VStack(spacing: SBSLayout.paddingSmall) {
                    ForEach(programs) { program in
                        let meta = metadata[program.id]
                        let isLocked = isProgramLocked(program.id)
                        
                        ProgramCard(
                            program: program,
                            meta: meta,
                            isSelected: selectedProgram == program.id,
                            isLocked: isLocked,
                            isPremiumUser: isPremiumUser,
                            onSelect: {
                                if isLocked {
                                    onLockedTap()
                                } else {
                                    selectedProgram = program.id
                                }
                            }
                        )
                    }
                }
                .padding(.top, programs.count > 1 ? SBSLayout.paddingSmall : 0)
                .padding(.leading, programs.count > 1 ? SBSLayout.paddingLarge : 0)
            }
        }
    }
}

// MARK: - Program Card

struct ProgramCard: View {
    let program: AppState.AvailableProgramInfo
    let meta: ProgramMeta?
    let isSelected: Bool
    let isLocked: Bool
    let isPremiumUser: Bool
    let onSelect: () -> Void
    
    @State private var showingDetail = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Main card content (tappable for selection)
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                    // Header row
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: SBSLayout.paddingSmall) {
                                Text(program.displayName)
                                    .font(SBSFonts.bodyBold())
                                    .foregroundStyle(isLocked ? SBSColors.textTertiaryFallback : SBSColors.textPrimaryFallback)
                                
                                if isLocked {
                                    PremiumBadge(isCompact: true)
                                }
                                
                                if meta?.isFree == true && !isLocked && !isPremiumUser {
                                    FreeBadge()
                                }
                            }
                            
                            Text(meta?.shortDescription ?? program.programDescription)
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                                .lineLimit(2)
                        }
                        
                        Spacer(minLength: SBSLayout.paddingMedium)
                        
                        // Selection indicator
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                        } else if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(SBSColors.accentFallback)
                        } else {
                            Circle()
                                .strokeBorder(SBSColors.textTertiaryFallback, lineWidth: 2)
                                .frame(width: 24, height: 24)
                        }
                    }
                    
                    // Badges row with info button
                    HStack(spacing: SBSLayout.paddingSmall) {
                        // Days badge
                        ProgramBadge(
                            icon: "calendar",
                            label: "\(program.days) Days",
                            color: .blue
                        )
                        
                        // Weeks badge
                        ProgramBadge(
                            icon: "clock",
                            label: "\(program.weeks) Weeks",
                            color: .gray
                        )
                        
                        // Level badge
                        if let level = meta?.level {
                            ProgramBadge(
                                icon: level.icon,
                                label: level.rawValue,
                                color: level.color
                            )
                        }
                        
                        Spacer()
                        
                        // Info button
                        Button {
                            showingDetail = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(SBSColors.accentFallback)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(SBSColors.surfaceFallback)
                        .overlay(
                            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                                .strokeBorder(
                                    isSelected && !isLocked ? SBSColors.accentFallback : Color.clear,
                                    lineWidth: 2
                                )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .opacity(isLocked ? 0.7 : 1.0)
        .sheet(isPresented: $showingDetail) {
            ProgramDetailView(
                program: program,
                familyColor: meta?.level.color ?? SBSColors.accentFallback,
                level: meta?.level ?? .intermediate
            )
        }
    }
}

// MARK: - Program Badge

struct ProgramBadge: View {
    let icon: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - Free Badge

struct FreeBadge: View {
    var body: some View {
        Text("FREE")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.green)
            )
    }
}

// MARK: - Custom Templates Group

struct CustomTemplatesGroup: View {
    let templates: [CustomTemplate]
    @Binding var selectedProgram: String
    let isExpanded: Bool
    let onToggle: () -> Void
    
    private var hasSelectedTemplate: Bool {
        templates.contains { UserData.programId(for: $0.id) == selectedProgram }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack(spacing: SBSLayout.paddingMedium) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SBSColors.accentFallback)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Templates")
                            .font(SBSFonts.title3())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text("\(templates.count) custom")
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .fill(hasSelectedTemplate ? SBSColors.accentFallback.opacity(0.08) : SBSColors.surfaceFallback)
                )
            }
            .buttonStyle(.plain)
            
            // Templates
            if isExpanded {
                VStack(spacing: SBSLayout.paddingSmall) {
                    ForEach(templates) { template in
                        let programId = UserData.programId(for: template.id)
                        CustomTemplateRow(
                            template: template,
                            isSelected: selectedProgram == programId,
                            onSelect: { selectedProgram = programId }
                        )
                    }
                }
                .padding(.top, SBSLayout.paddingSmall)
                .padding(.leading, SBSLayout.paddingLarge)
            }
        }
    }
}

struct CustomTemplateRow: View {
    let template: CustomTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: SBSLayout.paddingSmall) {
                            Text(template.name)
                                .font(SBSFonts.bodyBold())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text("CUSTOM")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(SBSColors.accentFallback))
                        }
                        
                        if !template.templateDescription.isEmpty {
                            Text(template.templateDescription)
                                .font(SBSFonts.caption())
                                .foregroundStyle(SBSColors.textSecondaryFallback)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(SBSColors.accentFallback)
                    } else {
                        Circle()
                            .strokeBorder(SBSColors.textTertiaryFallback, lineWidth: 2)
                            .frame(width: 24, height: 24)
                    }
                }
                
                // Badges row with info button
                HStack(spacing: SBSLayout.paddingSmall) {
                    ProgramBadge(
                        icon: "calendar",
                        label: "\(template.daysPerWeek) Days",
                        color: .blue
                    )
                    
                    ProgramBadge(
                        icon: "clock",
                        label: "\(template.weeks.count) Weeks",
                        color: .gray
                    )
                    
                    ProgramBadge(
                        icon: template.mode == .simple ? "list.bullet" : "slider.horizontal.3",
                        label: template.mode.displayName,
                        color: template.mode == .simple ? .green : .purple
                    )
                    
                    Spacer()
                    
                    // Info button
                    Button {
                        showingDetail = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(SBSColors.accentFallback)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(SBSColors.surfaceFallback)
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .strokeBorder(isSelected ? SBSColors.accentFallback : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            CustomTemplateDetailView(template: template)
        }
    }
}

// MARK: - Quiz Prompt Card

struct QuizPromptCard: View {
    let onTakeQuiz: () -> Void
    
    var body: some View {
        Button(action: onTakeQuiz) {
            HStack(spacing: SBSLayout.paddingMedium) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundStyle(SBSColors.accentFallback)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not sure which to pick?")
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Take the quiz to find the best program for you")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(SBSColors.accentFallback.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .strokeBorder(SBSColors.accentFallback.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Builder Prompt Card

struct TemplateBuilderPromptCard: View {
    let onBuildTemplate: () -> Void
    
    var body: some View {
        Button(action: onBuildTemplate) {
            HStack(spacing: SBSLayout.paddingMedium) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SBSColors.accentFallback)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not seeing what you want?")
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text("Build your own in the Template Builder")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(SBSColors.accentFallback.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                            .strokeBorder(SBSColors.accentFallback.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ProgramSelector(
        appState: AppState(),
        selectedProgram: .constant("stronglifts_5x5_12week"),
        onTakeQuiz: {},
        onBuildTemplate: {}
    )
}

