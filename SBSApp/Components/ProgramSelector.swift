import SwiftUI

// MARK: - Program Selector (Redesigned)

/// A clean, intuitive program selector with filtering and grouped program families
struct ProgramSelector: View {
    @Bindable var appState: AppState
    @Binding var selectedProgram: String
    let onTakeQuiz: () -> Void
    let onBuildTemplate: () -> Void
    /// The step title, drawn above the filters; it scrolls with the list at
    /// the accessibility sizes so the list keeps most of the screen
    var title: String? = nil
    var subtitle: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        filterBar
                        programList
                    }
                }
            } else {
                header
                filterBar
                ScrollView { programList }
            }
        }
        .background(Color.bg)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(triggeredByFeature: .allPrograms)
        }
    }

    @ViewBuilder
    private var header: some View {
        if let title {
            VStack(spacing: SBSLayout.space2) {
                Text(title)
                    .font(SBSFonts.title())
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal)
            .padding(.top, SBSLayout.space4)
            .padding(.bottom, SBSLayout.space2)
        }
    }

    private var filterBar: some View {
        // Filter bar
        VStack(spacing: SBSLayout.space2) {
            // Days filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SBSLayout.space2) {
                    SBSChip(title: "All Days", isSelected: selectedDaysFilter == nil) {
                        selectedDaysFilter = nil
                    }

                    ForEach(availableDays, id: \.self) { days in
                        SBSChip(title: "\(days) Days", isSelected: selectedDaysFilter == days) {
                            selectedDaysFilter = days
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 1)
            }

            // Level filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SBSLayout.space2) {
                    SBSChip(title: "All Levels", isSelected: selectedLevelFilter == nil) {
                        selectedLevelFilter = nil
                    }

                    ForEach(ProgramLevel.allCases, id: \.self) { level in
                        SBSChip(title: level.rawValue, systemImage: level.icon, isSelected: selectedLevelFilter == level) {
                            selectedLevelFilter = level
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 1)
            }
        }
        .padding(.vertical, SBSLayout.space3)
        .background(Color.bg)
        .overlay(alignment: .bottom) { SBSRowDivider() }
    }

    private var programList: some View {
            LazyVStack(spacing: SBSLayout.space3) {
                // Quiz prompt: the same row as the Programs tab's
                Button(action: onTakeQuiz) {
                    SBSListRow("Not sure which to pick?", showsChevron: true) {
                        Text("Take the quiz to find the best program for you")
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)

                // Disclaimer note
                HStack(alignment: .firstTextBaseline, spacing: SBSLayout.space2) {
                    Image(systemName: "info.circle")
                        .font(SBSFonts.caption())
                        .accessibilityHidden(true)
                    Text("All programs are based on popular training programs. Some names are changed.")
                        .font(SBSFonts.caption())
                }
                .foregroundStyle(Color.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                            .font(SBSFonts.titleLarge())
                            .foregroundStyle(Color.inkSecondary)
                            .accessibilityHidden(true)

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
                        .frame(minHeight: 44)
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

    var body: some View {
        VStack(spacing: 0) {
            // Family header: the same row as the Programs tab's family groups. The
            // selected program shows its own selection, so the header isn't tinted.
            if programs.count > 1 {
                Button(action: onToggle) {
                    SBSListRow(family) {
                        SBSRowSubtitle("\(programs.count) variants")
                    } trailing: {
                        SBSChevron(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Hides the variants" : "Shows the variants")
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
                .padding(.leading, programs.count > 1 ? SBSLayout.space4 : 0)
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
        // The card selects; the info button beside it is its own target
        HStack(alignment: .top, spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: SBSLayout.space3) {
                    ProgramSelectionMark(isSelected: isSelected, isLocked: isLocked)

                    VStack(alignment: .leading, spacing: SBSLayout.space1) {
                        Text(program.displayName)
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(isLocked ? Color.inkSecondary : Color.ink)
                            .multilineTextAlignment(.leading)

                        // Two badges at most: Pro or Free, and Modified
                        HStack(spacing: SBSLayout.space1) {
                            if isLocked {
                                SBSBadge(text: "Pro", variant: .pro, systemImage: "lock.fill")
                            }

                            if ProgramCatalog.showsFreeBadge(programId: program.id, isLocked: isLocked, isPremiumUser: isPremiumUser) {
                                SBSBadge(text: "Free")
                            }

                            if isCustomized {
                                SBSBadge(text: "Modified", systemImage: "pencil")
                            }
                        }

                        Text(meta?.shortDescription ?? program.programDescription)
                            .font(SBSFonts.caption())
                            .foregroundStyle(Color.inkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        // Days, weeks and level: one neutral line and badge, no colour per level
                        HStack(spacing: SBSLayout.space2) {
                            SBSRowSubtitle("\(program.days) days · \(program.weeks) weeks")

                            if let level = meta?.level {
                                SBSBadge(text: level.rawValue, systemImage: level.icon)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, SBSLayout.space4)
                .padding(.leading, SBSLayout.space4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected && !isLocked ? [.isSelected] : [])

            ProgramInfoButton(label: "About \(program.displayName)") {
                showingDetail = true
            }
            .padding(.top, SBSLayout.space2)
            .padding(.trailing, SBSLayout.space1)
        }
        .selectionCell(isSelected && !isLocked)
        .sheet(isPresented: $showingDetail) {
            ProgramDetailView(
                program: program,
                // Orange as text and icons; no colour per level
                level: meta?.level ?? .intermediate
            )
        }
    }
}

// MARK: - Selection Mark

/// A program choice's mark: an orange-text check when chosen, a hairline square
/// when not, a lock when it needs Premium. The card's selectionCell carries the
/// selection; this repeats it as a glyph so it never rests on colour alone.
struct ProgramSelectionMark: View {
    let isSelected: Bool
    var isLocked: Bool = false

    var body: some View {
        Group {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.inkSecondary)
            } else if isSelected {
                Image(systemName: "checkmark")
                    .font(SBSFonts.bodyStrong().weight(.bold))
                    .foregroundStyle(Color.orangeText)
            } else {
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(Color.inkSecondary, lineWidth: SBSLayout.strokeHairline)
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// The info button on a program or template card: orange-text glyph, 44pt target.
struct ProgramInfoButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(SBSFonts.heading())
                .foregroundStyle(Color.orangeText)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Custom Templates Group

struct CustomTemplatesGroup: View {
    let templates: [CustomTemplate]
    @Binding var selectedProgram: String
    let isExpanded: Bool
    let hasCustomizations: (String) -> Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggle) {
                SBSListRow("My Templates") {
                    Image(systemName: "square.stack.3d.up")
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                } subtitle: {
                    SBSRowSubtitle("\(templates.count) custom")
                } trailing: {
                    SBSChevron(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides your templates" : "Shows your templates")

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
                .padding(.leading, SBSLayout.space4)
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
        HStack(alignment: .top, spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: SBSLayout.space3) {
                    ProgramSelectionMark(isSelected: isSelected)

                    VStack(alignment: .leading, spacing: SBSLayout.space1) {
                        Text(template.name)
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: SBSLayout.space1) {
                            SBSBadge(text: "Custom")

                            if isCustomized {
                                SBSBadge(text: "Modified", systemImage: "pencil")
                            }
                        }

                        if !template.templateDescription.isEmpty {
                            Text(template.templateDescription)
                                .font(SBSFonts.caption())
                                .foregroundStyle(Color.inkSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        // Days, weeks and mode
                        HStack(spacing: SBSLayout.space2) {
                            SBSRowSubtitle("\(template.daysPerWeek) days · \(template.weeks.count) weeks")

                            SBSBadge(
                                text: template.mode.displayName,
                                systemImage: template.mode == .simple ? "list.bullet" : "slider.horizontal.3"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, SBSLayout.space4)
                .padding(.leading, SBSLayout.space4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            ProgramInfoButton(label: "About \(template.name)") {
                showingDetail = true
            }
            .padding(.top, SBSLayout.space2)
            .padding(.trailing, SBSLayout.space1)
        }
        .selectionCell(isSelected)
        .sheet(isPresented: $showingDetail) {
            CustomTemplateDetailView(template: template)
        }
    }
}

// MARK: - Template Builder Prompt Card

/// A navigation row like the quiz prompt: hairline card, no tint.
struct TemplateBuilderPromptCard: View {
    let onBuildTemplate: () -> Void

    var body: some View {
        Button(action: onBuildTemplate) {
            SBSListRow("Not seeing what you want?", showsChevron: true) {
                Text("Build your own in the Template Builder")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
            .card()
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
