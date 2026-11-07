import SwiftUI

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

    // MARK: - Computed Properties

    private var groupedPrograms: [(family: String, programs: [AppState.AvailableProgramInfo])] {
        // Group by family
        var groups: [String: [AppState.AvailableProgramInfo]] = [:]

        for program in filteredPrograms {
            let family = ProgramCatalog.metadata[program.id]?.family ?? "Other"
            groups[family, default: []].append(program)
        }

        // Sort by family name in desired display order
        return groups.map { (family: $0.key, programs: $0.value) }
            .sorted { lhs, rhs in
                ProgramCatalog.familySortIndex(lhs.family) < ProgramCatalog.familySortIndex(rhs.family)
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
                guard ProgramCatalog.metadata[program.id]?.level == levelFilter else { return false }
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
            VStack(spacing: SBSLayout.space4) {
                // Days filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SBSLayout.space2) {
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
                    HStack(spacing: SBSLayout.space2) {
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
            .padding(.vertical, SBSLayout.space4)
            .background(Color.bg)
            
            // Program list
            ScrollView {
                LazyVStack(spacing: SBSLayout.space4) {

                    // Quiz prompt (only show if no programs are selected)
                    QuizPromptCard(onTakeQuiz: onTakeQuiz)
                        .padding(.horizontal)
                        .padding(.top, SBSLayout.space4)
                    
                    // Disclaimer note
                    HStack(spacing: SBSLayout.space2) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                        Text("All programs are based on popular training programs. Some names are changed.")
                            .font(SBSFonts.caption())
                    }
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal)
                    .padding(.vertical, SBSLayout.space2)

                    // Custom templates (if any)
                    if !appState.userData.customTemplates.isEmpty {
                        CustomTemplatesGroup(
                            templates: appState.userData.customTemplates,
                            selectedProgram: $selectedProgram,
                            isExpanded: expandedFamilies.contains("__custom__"),
                            hasCustomizations: { appState.userData.hasCustomizations(for: $0) },
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
                            metadata: ProgramCatalog.metadata,
                            isProgramLocked: isProgramLocked,
                            isPremiumUser: storeManager.isPremium,
                            hasCustomizations: { appState.userData.hasCustomizations(for: $0) },
                            onToggle: { toggleFamily(group.family) },
                            onLockedTap: { showingPaywall = true }
                        )
                    }
                    
                    // Empty state
                    if filteredPrograms.isEmpty {
                        VStack(spacing: SBSLayout.space4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.inkSecondary)
                            
                            Text("No programs matched your filters. More coming soon")
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.inkSecondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Clear Filters") {
                                selectedDaysFilter = nil
                                selectedLevelFilter = nil
                            }
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.orangeText)
                        }
                        .padding(.vertical, SBSLayout.space8)
                    }
                    
                    // Template Builder prompt
                    TemplateBuilderPromptCard(onBuildTemplate: onBuildTemplate)
                        .padding(.top, SBSLayout.space2)
                    
                    
                }
                .padding(.horizontal)
                .padding(.vertical, SBSLayout.space4)
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
    let hasCustomizations: (String) -> Bool
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
                    HStack(spacing: SBSLayout.space4) {
                        // Family name
                        VStack(alignment: .leading, spacing: 2) {
                            Text(family)
                                .font(SBSFonts.heading())
                                .foregroundStyle(Color.ink)
                            
                            Text("\(programs.count) variants")
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                        }
                        
                        Spacer()
                        
                        // Chevron
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.inkTertiary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                            .fill(hasSelectedProgram ? familyColor.opacity(0.08) : Color.surface)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Programs
            if isExpanded || programs.count == 1 {
                VStack(spacing: SBSLayout.space2) {
                    ForEach(programs) { program in
                        let meta = metadata[program.id]
                        let isLocked = isProgramLocked(program.id)
                        
                        ProgramCard(
                            program: program,
                            meta: meta,
                            isSelected: selectedProgram == program.id,
                            isLocked: isLocked,
                            isPremiumUser: isPremiumUser,
                            isCustomized: hasCustomizations(program.id),
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
                .padding(.top, programs.count > 1 ? SBSLayout.space2 : 0)
                .padding(.leading, programs.count > 1 ? SBSLayout.space6 : 0)
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
    let isCustomized: Bool
    let onSelect: () -> Void
    
    @State private var showingDetail = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Main card content (tappable for selection)
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    // Header row
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: SBSLayout.space2) {
                                Text(program.displayName)
                                    .font(SBSFonts.bodyStrong())
                                    .foregroundStyle(isLocked ? Color.inkSecondary : Color.ink)
                                
                                if isLocked {
                                    PremiumBadge(isCompact: true)
                                }
                                
                                if ProgramCatalog.showsFreeBadge(programId: program.id, isLocked: isLocked, isPremiumUser: isPremiumUser) {
                                    FreeBadge()
                                }

                                if isCustomized {
                                    ModifiedBadge()
                                }
                            }

                            Text(meta?.shortDescription ?? program.programDescription)
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(2)
                        }
                        
                        Spacer(minLength: SBSLayout.space4)
                        
                        // Selection indicator
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.inkSecondary)
                        } else if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.orangeText)
                        } else {
                            Circle()
                                .strokeBorder(Color.inkTertiary, lineWidth: 2)
                                .frame(width: 24, height: 24)
                        }
                    }
                    
                    // Badges row with info button
                    HStack(spacing: SBSLayout.space2) {
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
                                .foregroundStyle(Color.orangeText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                        .fill(Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
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

// MARK: - Modified Badge

struct ModifiedBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "pencil")
                .font(.system(size: 8, weight: .bold))
            Text("MODIFIED")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.orange)
        )
    }
}

// MARK: - Custom Templates Group

struct CustomTemplatesGroup: View {
    let templates: [CustomTemplate]
    @Binding var selectedProgram: String
    let isExpanded: Bool
    let hasCustomizations: (String) -> Bool
    let onToggle: () -> Void
    
    private var hasSelectedTemplate: Bool {
        templates.contains { UserData.programId(for: $0.id) == selectedProgram }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                HStack(spacing: SBSLayout.space4) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.orangeText)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Templates")
                            .font(SBSFonts.heading())
                            .foregroundStyle(Color.ink)
                        
                        Text("\(templates.count) custom")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.inkTertiary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                        .fill(hasSelectedTemplate ? Color.orangeSoft : Color.surface)
                )
            }
            .buttonStyle(.plain)
            
            // Templates
            if isExpanded {
                VStack(spacing: SBSLayout.space2) {
                    ForEach(templates) { template in
                        let programId = UserData.programId(for: template.id)
                        CustomTemplateRow(
                            template: template,
                            isSelected: selectedProgram == programId,
                            isCustomized: hasCustomizations(programId),
                            onSelect: { selectedProgram = programId }
                        )
                    }
                }
                .padding(.top, SBSLayout.space2)
                .padding(.leading, SBSLayout.space6)
            }
        }
    }
}

struct CustomTemplateRow: View {
    let template: CustomTemplate
    let isSelected: Bool
    let isCustomized: Bool
    let onSelect: () -> Void
    
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: SBSLayout.space2) {
                            Text(template.name)
                                .font(SBSFonts.bodyStrong())
                                .foregroundStyle(Color.ink)
                            
                            Text("CUSTOM")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.orangeInk)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(SBSColors.accentFallback))

                            if isCustomized {
                                ModifiedBadge()
                            }
                        }

                        if !template.templateDescription.isEmpty {
                            Text(template.templateDescription)
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.orangeText)
                    } else {
                        Circle()
                            .strokeBorder(Color.inkTertiary, lineWidth: 2)
                            .frame(width: 24, height: 24)
                    }
                }
                
                // Badges row with info button
                HStack(spacing: SBSLayout.space2) {
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
                            .foregroundStyle(Color.orangeText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
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
            HStack(spacing: SBSLayout.space4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.orangeText)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not sure which to pick?")
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)
                    
                    Text("Take the quiz to find the best program for you")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .fill(Color.orangeSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
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
            HStack(spacing: SBSLayout.space4) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.orangeText)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not seeing what you want?")
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)
                    
                    Text("Build your own in the Template Builder")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .fill(Color.orangeSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
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

