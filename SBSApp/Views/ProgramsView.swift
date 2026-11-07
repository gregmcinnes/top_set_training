import SwiftUI

// MARK: - Programs View

struct ProgramsView: View {
    @Bindable var appState: AppState
    @Binding var selectedTab: ContentView.Tab
    
    @State private var selectedSection: ProgramSection = .programs
    @State private var selectedDaysFilter: Int? = nil
    @State private var selectedLevelFilter: ProgramLevel? = nil
    @State private var expandedFamilies: Set<String> = []
    @State private var showingPaywall = false
    @State private var showingProgramQuiz = false
    
    // Cycle builder state
    @State private var showingCycleBuilder = false
    @State private var selectedProgramForCycle: String? = nil
    @State private var showingNewCycleWarning = false
    
    // Template builder state
    @State private var showingTemplateBuilder = false
    @State private var templateToEdit: CustomTemplate?
    @State private var templateToDelete: CustomTemplate?
    @State private var showingDeleteConfirmation = false

    // Reset customizations state
    @State private var programToResetCustomizations: String?
    @State private var showingResetCustomizationsAlert = false
    
    private let storeManager = StoreManager.shared
    
    enum ProgramSection: String, CaseIterable {
        case programs = "Programs"
        case templates = "My Templates"
    }
    
    // MARK: - Computed Properties

    private var groupedPrograms: [(family: String, programs: [AppState.AvailableProgramInfo])] {
        var groups: [String: [AppState.AvailableProgramInfo]] = [:]

        for program in filteredPrograms {
            let family = ProgramCatalog.metadata[program.id]?.family ?? "Other"
            groups[family, default: []].append(program)
        }

        return groups.map { (family: $0.key, programs: $0.value) }
            .sorted { lhs, rhs in
                ProgramCatalog.familySortIndex(lhs.family) < ProgramCatalog.familySortIndex(rhs.family)
            }
    }

    private var filteredPrograms: [AppState.AvailableProgramInfo] {
        appState.availablePrograms.filter { program in
            if let daysFilter = selectedDaysFilter {
                guard program.days == daysFilter else { return false }
            }
            if let levelFilter = selectedLevelFilter {
                guard ProgramCatalog.metadata[program.id]?.level == levelFilter else { return false }
            }
            return true
        }
    }
    
    private var availableDays: [Int] {
        Set(appState.availablePrograms.map { $0.days }).sorted()
    }
    
    private var templates: [CustomTemplate] {
        appState.userData.customTemplates.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    private var canCreateTemplate: Bool {
        storeManager.canCreateTemplate(currentTemplateCount: templates.count)
    }

    private var isDeletingActiveTemplate: Bool {
        guard let template = templateToDelete else { return false }
        return appState.userData.selectedProgram == UserData.programId(for: template.id)
    }
    
    private func isProgramLocked(_ programId: String) -> Bool {
        !storeManager.canAccessProgram(programId)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section picker
                SBSSegmentedControl(options: ProgramSection.allCases, selection: $selectedSection) { $0.rawValue }
                    .padding(.horizontal, SBSLayout.space4)
                    .padding(.vertical, SBSLayout.space3)
                
                // Content based on selected section
                if selectedSection == .programs {
                    programsContent
                } else {
                    templatesContent
                }
            }
            .sbsBackground()
            .navigationTitle("Programs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if selectedSection == .templates {
                    ToolbarItem(placement: .topBarTrailing) {
                        createTemplateButton
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(triggeredByFeature: .allPrograms)
            }
            .fullScreenCover(isPresented: $showingCycleBuilder) {
                CycleBuilderView(
                    appState: appState,
                    isOnboarding: false,
                    initialProgram: selectedProgramForCycle,
                    onComplete: {
                        showingCycleBuilder = false
                        selectedProgramForCycle = nil
                        // Navigate to workout tab with Week 1 ready
                        selectedTab = .home
                    },
                    onCancel: {
                        showingCycleBuilder = false
                        selectedProgramForCycle = nil
                    }
                )
            }
            .fullScreenCover(isPresented: $showingTemplateBuilder) {
                TemplateBuilderView(
                    appState: appState,
                    existingTemplate: nil,
                    onSave: { template in
                        appState.userData.addTemplate(template)
                        showingTemplateBuilder = false
                    },
                    onCancel: {
                        showingTemplateBuilder = false
                    }
                )
            }
            .fullScreenCover(item: $templateToEdit) { template in
                TemplateBuilderView(
                    appState: appState,
                    existingTemplate: template,
                    onSave: { updatedTemplate in
                        appState.userData.updateTemplate(updatedTemplate)
                        templateToEdit = nil
                        // Editing the active template must take effect now, not at next launch
                        let programId = UserData.programId(for: updatedTemplate.id)
                        if appState.userData.selectedProgram == programId {
                            Task { try? await appState.loadProgram(programId) }
                        }
                    },
                    onCancel: {
                        templateToEdit = nil
                    }
                )
            }
            .alert(isDeletingActiveTemplate ? "Template In Use" : "Delete Template?", isPresented: $showingDeleteConfirmation) {
                if isDeletingActiveTemplate {
                    Button("OK", role: .cancel) {
                        templateToDelete = nil
                    }
                } else {
                    Button("Cancel", role: .cancel) {
                        templateToDelete = nil
                    }
                    Button("Delete", role: .destructive) {
                        if let template = templateToDelete {
                            withAnimation {
                                appState.userData.deleteTemplate(id: template.id)
                            }
                        }
                        templateToDelete = nil
                    }
                }
            } message: {
                if let template = templateToDelete {
                    if isDeletingActiveTemplate {
                        Text("\"\(template.name)\" is your current program. Switch to another program before deleting it.")
                    } else {
                        Text("Are you sure you want to delete \"\(template.name)\"? This cannot be undone.")
                    }
                }
            }
            .alert("Start New Cycle?", isPresented: $showingNewCycleWarning) {
                Button("Cancel", role: .cancel) {
                    selectedProgramForCycle = nil
                }
                Button("Continue") {
                    showingCycleBuilder = true
                }
            } message: {
                Text(appState.isCycleComplete
                     ? "Cycle \(appState.currentCycleNumber) is complete and will be saved to Past Cycles."
                     : "You have a cycle in progress. Starting a new one ends it now: what you've logged moves to Past Cycles, and the workouts you haven't done are dropped.")
            }
            .alert("Reset Customizations?", isPresented: $showingResetCustomizationsAlert) {
                Button("Cancel", role: .cancel) {
                    programToResetCustomizations = nil
                }
                Button("Reset", role: .destructive) {
                    if let programId = programToResetCustomizations {
                        appState.userData.clearSavedCustomizations(for: programId)
                        if appState.userData.selectedProgram == programId {
                            appState.resetAllDayItems()
                        }
                    }
                    programToResetCustomizations = nil
                }
            } message: {
                Text("This will remove all your saved accessory and exercise customizations for this program. This cannot be undone.")
            }
            .fullScreenCover(isPresented: $showingProgramQuiz) {
                ProgramRecommendationQuiz(
                    appState: appState,
                    selectedProgram: .constant(""),
                    onDismiss: {
                        showingProgramQuiz = false
                    },
                    onProgramSelected: { programId in
                        showingProgramQuiz = false
                        selectedProgramForCycle = programId
                        if appState.hasLoggedData {
                            showingNewCycleWarning = true
                        } else {
                            showingCycleBuilder = true
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - Programs Content
    
    private var programsContent: some View {
        VStack(spacing: 0) {
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
                    .padding(.horizontal, SBSLayout.space4)
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
                    .padding(.horizontal, SBSLayout.space4)
                    .padding(.vertical, 1)
                }
            }
            .padding(.bottom, SBSLayout.space3)
            .background(Color.bg)
            .overlay(alignment: .bottom) { SBSRowDivider() }
            
            // Program list
            ScrollView {
                LazyVStack(spacing: SBSLayout.space3) {
                    // Quiz prompt
                    Button {
                        showingProgramQuiz = true
                    } label: {
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
                        Text("All programs are based on popular training programs. Some names are changed.")
                            .font(SBSFonts.caption())
                    }
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Program families
                    ForEach(groupedPrograms, id: \.family) { group in
                        ProgramFamilyGroupView(
                            family: group.family,
                            programs: group.programs,
                            isExpanded: shouldExpandFamily(group.family, programs: group.programs),
                            metadata: ProgramCatalog.metadata,
                            isProgramLocked: isProgramLocked,
                            hasCustomizations: { appState.userData.hasCustomizations(for: $0) },
                            onToggle: { toggleFamily(group.family) },
                            onLockedTap: { showingPaywall = true },
                            onStartCycle: { programId in
                                selectedProgramForCycle = programId
                                if appState.hasLoggedData {
                                    showingNewCycleWarning = true
                                } else {
                                    showingCycleBuilder = true
                                }
                            },
                            onResetCustomizations: { programId in
                                programToResetCustomizations = programId
                                showingResetCustomizationsAlert = true
                            }
                        )
                    }
                    
                    // Empty state
                    if filteredPrograms.isEmpty {
                        VStack(spacing: SBSLayout.space4) {
                            Image(systemName: "magnifyingglass")
                                .font(SBSFonts.title())
                                .foregroundStyle(Color.inkSecondary)

                            Text("No programs matched your filters")
                                .font(SBSFonts.body())
                                .foregroundStyle(Color.inkSecondary)
                                .multilineTextAlignment(.center)

                            Button {
                                selectedDaysFilter = nil
                                selectedLevelFilter = nil
                            } label: {
                                SBSButtonTitle("Clear Filters")
                            }
                            .buttonStyle(SBSSecondaryButtonStyle())
                        }
                        .padding(.vertical, SBSLayout.space8)
                    }
                }
                .padding(.horizontal, SBSLayout.space4)
                .padding(.vertical, SBSLayout.space4)
            }
        }
    }
    
    // MARK: - Templates Content
    
    private var templatesContent: some View {
        Group {
            if templates.isEmpty {
                templatesEmptyState
            } else {
                templatesList
            }
        }
    }
    
    private var templatesEmptyState: some View {
        TemplatesEmptyState(
            showsFreeTierInfo: !storeManager.isPremium,
            onCreate: { showingTemplateBuilder = true },
            onUpgrade: { showingPaywall = true }
        )
    }

    private var templatesList: some View {
        List {
            // Template limit section for free users
            if !storeManager.isPremium {
                Section {
                    TemplateFreeTierRow(
                        templateCount: templates.count,
                        canCreateTemplate: canCreateTemplate,
                        onUpgrade: { showingPaywall = true }
                    )
                }
                .sbsListRows()
            }
            
            // Templates section
            Section {
                ForEach(templates) { template in
                    TemplateRowView(
                        template: template,
                        isCustomized: appState.userData.hasCustomizations(for: UserData.programId(for: template.id)),
                        onEdit: {
                            templateToEdit = template
                        },
                        onDelete: {
                            templateToDelete = template
                            showingDeleteConfirmation = true
                        },
                        onStartCycle: {
                            let programId = UserData.programId(for: template.id)
                            selectedProgramForCycle = programId
                            if appState.hasLoggedData {
                                showingNewCycleWarning = true
                            } else {
                                showingCycleBuilder = true
                            }
                        }
                    )
                }
            } header: {
                SBSListHeader("Saved Templates")
            } footer: {
                SBSListFooter("Templates can be selected when starting a new training cycle.")
            }
            .sbsListRows()
        }
        .sbsGroupedList()
    }
    
    // MARK: - Create Template Button
    
    @ViewBuilder
    private var createTemplateButton: some View {
        if canCreateTemplate {
            Button {
                showingTemplateBuilder = true
            } label: {
                Image(systemName: "plus")
            }
        } else {
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func shouldExpandFamily(_ family: String, programs: [AppState.AvailableProgramInfo]) -> Bool {
        if programs.count == 1 { return true }
        if expandedFamilies.contains(family) { return true }
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

// MARK: - Templates Empty State (Programs and My Templates)

/// No templates yet: what a template is, the one primary action, and the free-tier limit.
struct TemplatesEmptyState: View {
    let showsFreeTierInfo: Bool
    let onCreate: () -> Void
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: SBSLayout.space6) {
            Spacer()

            Image(systemName: "square.stack.3d.up")
                .font(SBSFonts.titleLarge())
                .foregroundStyle(Color.inkSecondary)
                .accessibilityHidden(true)

            VStack(spacing: SBSLayout.space2) {
                Text("No Templates Yet")
                    .font(SBSFonts.title())
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)

                Text("Create your own custom workout program with exercises, sets, reps, and progression rules.")
                    .font(SBSFonts.body())
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SBSLayout.space6)
            }

            Button(action: onCreate) {
                HStack(spacing: SBSLayout.space2) {
                    Image(systemName: "plus")
                        .font(SBSFonts.button())
                    SBSButtonTitle("Create Template")
                }
            }
            .buttonStyle(SBSPrimaryButtonStyle())

            Spacer()

            // Template limit info for free users
            if showsFreeTierInfo {
                VStack(spacing: SBSLayout.space3) {
                    Text("Free users can save 1 template")
                        .font(SBSFonts.body())
                        .foregroundStyle(Color.inkSecondary)

                    Button(action: onUpgrade) {
                        SBSButtonTitle("Upgrade for Unlimited")
                    }
                    .buttonStyle(SBSSecondaryButtonStyle())
                }
                .padding(SBSLayout.space4)
                .frame(maxWidth: .infinity)
                .card()
            }
        }
        .padding(SBSLayout.space4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg.ignoresSafeArea())
    }
}

/// How many templates a free account has used, and the way to more.
struct TemplateFreeTierRow: View {
    let templateCount: Int
    let canCreateTemplate: Bool
    let onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: SBSLayout.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Templates used")
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.ink)

                Text(canCreateTemplate ? "You can create one more" : "Upgrade for unlimited templates")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }

            Spacer()

            Text("\(templateCount) / \(FreeTierLimits.maxSavedTemplates)")
                .font(SBSFonts.number())
                .foregroundStyle(Color.ink)
                .accessibilityLabel("\(templateCount) of \(FreeTierLimits.maxSavedTemplates)")

            if !canCreateTemplate {
                Button("Upgrade", action: onUpgrade)
                    .font(SBSFonts.caption().weight(.semibold))
                    .foregroundStyle(Color.orangeText)
                    .buttonStyle(.borderless)
            }
        }
    }
}

/// "4 days/week · 12 weeks · 18 exercises" in number-small.
struct TemplateMetaLine: View {
    let template: CustomTemplate

    var body: some View {
        let days = template.daysPerWeek
        let weeks = template.weeks.count
        let exercises = template.days.values.flatMap { $0 }.count
        SBSRowSubtitle("\(days) day\(days == 1 ? "" : "s")/week · \(weeks) week\(weeks == 1 ? "" : "s") · \(exercises) exercises")
    }
}

// MARK: - Program Family Group View (for ProgramsView)

struct ProgramFamilyGroupView: View {
    let family: String
    let programs: [AppState.AvailableProgramInfo]
    let isExpanded: Bool
    let metadata: [String: ProgramMeta]
    let isProgramLocked: (String) -> Bool
    let hasCustomizations: (String) -> Bool
    let onToggle: () -> Void
    let onLockedTap: () -> Void
    let onStartCycle: (String) -> Void
    let onResetCustomizations: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Family header
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

                        ProgramCardView(
                            program: program,
                            meta: meta,
                            isLocked: isLocked,
                            isCustomized: hasCustomizations(program.id),
                            onLockedTap: onLockedTap,
                            onStartCycle: { onStartCycle(program.id) },
                            onResetCustomizations: { onResetCustomizations(program.id) }
                        )
                    }
                }
                .padding(.top, programs.count > 1 ? SBSLayout.space2 : 0)
                .padding(.leading, programs.count > 1 ? SBSLayout.space4 : 0)
            }
        }
    }
}

// MARK: - Program Card View (for ProgramsView)

struct ProgramCardView: View {
    let program: AppState.AvailableProgramInfo
    let meta: ProgramMeta?
    let isLocked: Bool
    let isCustomized: Bool
    let onLockedTap: () -> Void
    let onStartCycle: () -> Void
    let onResetCustomizations: () -> Void

    @State private var showingDetail = false
    private let storeManager = StoreManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space3) {
            // Header row
            HStack(alignment: .top, spacing: SBSLayout.space3) {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    Text(program.displayName)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(isLocked ? Color.inkSecondary : Color.ink)

                    // Two badges at most: Pro or Free, and Modified
                    HStack(spacing: SBSLayout.space1) {
                        if isLocked {
                            SBSBadge(text: "Pro", variant: .pro, systemImage: "lock.fill")
                        }

                        if ProgramCatalog.showsFreeBadge(programId: program.id, isLocked: isLocked, isPremiumUser: storeManager.isPremium) {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Info button
                Button {
                    showingDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.orangeText)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(program.displayName)")
            }

            // Days, weeks and level
            HStack(spacing: SBSLayout.space2) {
                SBSRowSubtitle("\(program.days) days · \(program.weeks) weeks")

                if let level = meta?.level {
                    SBSBadge(text: level.rawValue, systemImage: level.icon)
                }
            }

            // Start Cycle: secondary, since every card has one
            Button {
                if isLocked {
                    onLockedTap()
                } else {
                    onStartCycle()
                }
            } label: {
                HStack(spacing: SBSLayout.space2) {
                    Image(systemName: isLocked ? "lock.fill" : "play.fill")
                        .font(SBSFonts.caption())
                    SBSButtonTitle(isLocked ? "Unlock to Start" : "Start Cycle")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SBSSecondaryButtonStyle())
        }
        .padding(SBSLayout.space4)
        .card()
        .contextMenu {
            if isCustomized {
                Button(role: .destructive) {
                    onResetCustomizations()
                } label: {
                    Label("Reset Customizations", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .sheet(isPresented: $showingDetail) {
            ProgramDetailView(
                program: program,
                // Orange as text and icons; no colour per level
                level: meta?.level ?? .intermediate,
                onStartCycle: isLocked ? nil : { onStartCycle() }
            )
        }
    }
}

// MARK: - Template Row View (for ProgramsView)

struct TemplateRowView: View {
    let template: CustomTemplate
    let isCustomized: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onStartCycle: () -> Void

    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: SBSLayout.space1) {
                    HStack(spacing: SBSLayout.space2) {
                        Text(template.name)
                            .font(SBSFonts.bodyStrong())
                            .foregroundStyle(Color.ink)

                        SBSBadge(text: template.mode.displayName)

                        if isCustomized {
                            SBSBadge(text: "Modified", systemImage: "pencil")
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

                // Info button
                Button {
                    showingDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(SBSFonts.heading())
                        .foregroundStyle(Color.orangeText)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("About \(template.name)")
            }

            TemplateMetaLine(template: template)

            // Action buttons row
            HStack {
                SBSRowSubtitle("Updated \(template.updatedAt.formatted(.relative(presentation: .named)))")

                Spacer()

                HStack(spacing: SBSLayout.space4) {
                    Button {
                        onStartCycle()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .foregroundStyle(Color.orangeText)

                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .foregroundStyle(Color.ink)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .foregroundStyle(Color.danger)
                }
                .font(SBSFonts.caption().weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, SBSLayout.space1)
        .sheet(isPresented: $showingDetail) {
            CustomTemplateDetailView(
                template: template,
                onStartCycle: { onStartCycle() }
            )
        }
    }
}

#Preview {
    ProgramsView(appState: AppState(), selectedTab: .constant(.programs))
}

