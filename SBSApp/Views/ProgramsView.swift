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
    
    // Template builder state
    @State private var showingTemplateBuilder = false
    @State private var templateToEdit: CustomTemplate?
    @State private var templateToDelete: CustomTemplate?
    @State private var showingDeleteConfirmation = false
    
    private let storeManager = StoreManager.shared
    
    enum ProgramSection: String, CaseIterable {
        case programs = "Programs"
        case templates = "My Templates"
    }
    
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
        var groups: [String: [AppState.AvailableProgramInfo]] = [:]
        
        for program in filteredPrograms {
            let family = programMetadata[program.id]?.family ?? "Other"
            groups[family, default: []].append(program)
        }
        
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
            if let daysFilter = selectedDaysFilter {
                guard program.days == daysFilter else { return false }
            }
            if let levelFilter = selectedLevelFilter {
                guard programMetadata[program.id]?.level == levelFilter else { return false }
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
    
    private func isProgramLocked(_ programId: String) -> Bool {
        !storeManager.canAccessProgram(programId)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Section picker
                Picker("Section", selection: $selectedSection) {
                    ForEach(ProgramSection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
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
                    },
                    onCancel: {
                        templateToEdit = nil
                    }
                )
            }
            .alert("Delete Template?", isPresented: $showingDeleteConfirmation) {
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
            } message: {
                if let template = templateToDelete {
                    Text("Are you sure you want to delete \"\(template.name)\"? This cannot be undone.")
                }
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
                        showingCycleBuilder = true
                    }
                )
            }
        }
    }
    
    // MARK: - Programs Content
    
    private var programsContent: some View {
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
                    // Quiz prompt
                    QuizPromptCard(onTakeQuiz: { showingProgramQuiz = true })
                        .padding(.horizontal)
                        .padding(.top, SBSLayout.paddingMedium)
                    
                    // Disclaimer note
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                        Text("All programs are based on popular training programs. Some names have been changed to avoid trademark issues.")
                            .font(SBSFonts.caption())
                    }
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .padding(.horizontal)
                    .padding(.vertical, SBSLayout.paddingSmall)
                    
                    // Program families
                    ForEach(groupedPrograms, id: \.family) { group in
                        ProgramFamilyGroupView(
                            family: group.family,
                            programs: group.programs,
                            isExpanded: shouldExpandFamily(group.family, programs: group.programs),
                            metadata: programMetadata,
                            isProgramLocked: isProgramLocked,
                            onToggle: { toggleFamily(group.family) },
                            onLockedTap: { showingPaywall = true },
                            onStartCycle: { programId in
                                selectedProgramForCycle = programId
                                showingCycleBuilder = true
                            }
                        )
                    }
                    
                    // Empty state
                    if filteredPrograms.isEmpty {
                        VStack(spacing: SBSLayout.paddingMedium) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(SBSColors.textTertiaryFallback)
                            
                            Text("No programs matched your filters")
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
                }
                .padding(.horizontal)
                .padding(.vertical, SBSLayout.paddingMedium)
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
        VStack(spacing: SBSLayout.paddingLarge) {
            Spacer()
            
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: SBSLayout.paddingSmall) {
                Text("No Templates Yet")
                    .font(SBSFonts.title())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Create your own custom workout program with exercises, sets, reps, and progression rules.")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SBSLayout.paddingLarge)
            }
            
            Button {
                showingTemplateBuilder = true
            } label: {
                Label("Create Template", systemImage: "plus")
            }
            .buttonStyle(SBSPrimaryButtonStyle())
            .padding(.top, SBSLayout.paddingMedium)
            
            Spacer()
            
            // Template limit info for free users
            if !storeManager.isPremium {
                freeTierInfoCard
                    .padding(.horizontal)
                    .padding(.bottom, SBSLayout.paddingLarge)
            }
        }
        .padding()
    }
    
    private var templatesList: some View {
        List {
            // Template limit section for free users
            if !storeManager.isPremium {
                Section {
                    freeTierRow
                }
            }
            
            // Templates section
            Section {
                ForEach(templates) { template in
                    TemplateRowView(
                        template: template,
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
                            showingCycleBuilder = true
                        }
                    )
                }
            } header: {
                Text("Saved Templates")
            } footer: {
                Text("Templates can be selected when starting a new training cycle.")
            }
        }
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
    
    // MARK: - Free Tier Info
    
    private var freeTierInfoCard: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            HStack(spacing: SBSLayout.paddingSmall) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(SBSColors.accentFallback)
                
                Text("Free users can save 1 template")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Button {
                showingPaywall = true
            } label: {
                Text("Upgrade for Unlimited")
                    .font(SBSFonts.captionBold())
            }
            .buttonStyle(SBSSecondaryButtonStyle())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
        )
    }
    
    private var freeTierRow: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [SBSColors.accentFallback.opacity(0.2), SBSColors.accentSecondaryFallback.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "crown.fill")
                    .foregroundStyle(SBSColors.accentFallback)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(templates.count) / \(FreeTierLimits.maxSavedTemplates) Template Used")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text(canCreateTemplate ? "You can create 1 more" : "Upgrade for unlimited templates")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            if !canCreateTemplate {
                Button {
                    showingPaywall = true
                } label: {
                    Text("Upgrade")
                        .font(SBSFonts.captionBold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(SBSColors.accentFallback)
                        )
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

// MARK: - Program Family Group View (for ProgramsView)

struct ProgramFamilyGroupView: View {
    let family: String
    let programs: [AppState.AvailableProgramInfo]
    let isExpanded: Bool
    let metadata: [String: ProgramMeta]
    let isProgramLocked: (String) -> Bool
    let onToggle: () -> Void
    let onLockedTap: () -> Void
    let onStartCycle: (String) -> Void
    
    private var familyColor: Color {
        if let first = programs.first, let meta = metadata[first.id] {
            return meta.level.color
        }
        return SBSColors.accentFallback
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Family header
            if programs.count > 1 {
                Button(action: onToggle) {
                    HStack(spacing: SBSLayout.paddingMedium) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(family)
                                .font(SBSFonts.title3())
                                .foregroundStyle(SBSColors.textPrimaryFallback)
                            
                            Text("\(programs.count) variants")
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
                            .fill(SBSColors.surfaceFallback)
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
                        
                        ProgramCardView(
                            program: program,
                            meta: meta,
                            isLocked: isLocked,
                            onLockedTap: onLockedTap,
                            onStartCycle: { onStartCycle(program.id) }
                        )
                    }
                }
                .padding(.top, programs.count > 1 ? SBSLayout.paddingSmall : 0)
                .padding(.leading, programs.count > 1 ? SBSLayout.paddingLarge : 0)
            }
        }
    }
}

// MARK: - Program Card View (for ProgramsView)

struct ProgramCardView: View {
    let program: AppState.AvailableProgramInfo
    let meta: ProgramMeta?
    let isLocked: Bool
    let onLockedTap: () -> Void
    let onStartCycle: () -> Void
    
    @State private var showingDetail = false
    
    private var familyColor: Color {
        meta?.level.color ?? SBSColors.accentFallback
    }
    
    var body: some View {
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
                        
                        if meta?.isFree == true && !isLocked {
                            FreeBadge()
                        }
                    }
                    
                    Text(meta?.shortDescription ?? program.programDescription)
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                        .lineLimit(2)
                }
                
                Spacer(minLength: SBSLayout.paddingMedium)
                
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                }
            }
            
            // Badges row
            HStack(spacing: SBSLayout.paddingSmall) {
                ProgramBadge(
                    icon: "calendar",
                    label: "\(program.days) Days",
                    color: .blue
                )
                
                ProgramBadge(
                    icon: "clock",
                    label: "\(program.weeks) Weeks",
                    color: .gray
                )
                
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
            
            // Start Cycle button
            Button {
                if isLocked {
                    onLockedTap()
                } else {
                    onStartCycle()
                }
            } label: {
                HStack {
                    Image(systemName: isLocked ? "lock.fill" : "play.fill")
                        .font(.system(size: 12))
                    Text(isLocked ? "Unlock to Start" : "Start Cycle")
                        .font(SBSFonts.captionBold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                        .fill(isLocked ? SBSColors.surfaceElevatedFallback : SBSColors.accentFallback)
                )
                .foregroundStyle(isLocked ? SBSColors.textSecondaryFallback : .white)
            }
            .buttonStyle(.plain)
            .padding(.top, SBSLayout.paddingSmall)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
        )
        .opacity(isLocked ? 0.7 : 1.0)
        .sheet(isPresented: $showingDetail) {
            ProgramDetailView(
                program: program,
                familyColor: familyColor,
                level: meta?.level ?? .intermediate,
                onStartCycle: isLocked ? nil : { onStartCycle() }
            )
        }
    }
}

// MARK: - Template Row View (for ProgramsView)

struct TemplateRowView: View {
    let template: CustomTemplate
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onStartCycle: () -> Void
    
    @State private var showingDetail = false
    
    private var daysDescription: String {
        "\(template.daysPerWeek) day\(template.daysPerWeek == 1 ? "" : "s")/week"
    }
    
    private var weeksDescription: String {
        "\(template.weeks.count) week\(template.weeks.count == 1 ? "" : "s")"
    }
    
    private var exerciseCount: Int {
        template.days.values.flatMap { $0 }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.paddingSmall) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Text(template.name)
                            .font(SBSFonts.bodyBold())
                            .foregroundStyle(SBSColors.textPrimaryFallback)
                        
                        Text(template.mode.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(template.mode == .advanced ? SBSColors.accentSecondaryFallback : SBSColors.textSecondaryFallback)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(template.mode == .advanced ? SBSColors.accentSecondaryFallback.opacity(0.15) : SBSColors.surfaceFallback)
                            )
                    }
                    
                    if !template.templateDescription.isEmpty {
                        Text(template.templateDescription)
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                            .lineLimit(2)
                    }
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
                .buttonStyle(.borderless)
            }
            
            // Stats row
            HStack(spacing: SBSLayout.paddingMedium) {
                Label(daysDescription, systemImage: "calendar")
                Label(weeksDescription, systemImage: "clock")
                Label("\(exerciseCount) exercises", systemImage: "figure.strengthtraining.traditional")
            }
            .font(SBSFonts.caption())
            .foregroundStyle(SBSColors.textTertiaryFallback)
            
            // Action buttons row
            HStack {
                Text("Updated \(template.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Spacer()
                
                HStack(spacing: SBSLayout.paddingMedium) {
                    Button {
                        onStartCycle()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .font(SBSFonts.caption())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(SBSColors.accentFallback)
                    
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(SBSFonts.caption())
                    }
                    .buttonStyle(.borderless)
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(SBSFonts.caption())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
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

