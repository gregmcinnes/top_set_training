import SwiftUI

// MARK: - Template List View

struct TemplateListView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingTemplateBuilder = false
    @State private var templateToEdit: CustomTemplate?
    @State private var templateToDelete: CustomTemplate?
    @State private var showingDeleteConfirmation = false
    @State private var showingPaywall = false
    
    private let storeManager = StoreManager.shared
    
    private var templates: [CustomTemplate] {
        appState.userData.customTemplates.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    private var canCreateTemplate: Bool {
        storeManager.canCreateTemplate(currentTemplateCount: templates.count)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    emptyStateView
                } else {
                    templateListView
                }
            }
            .navigationTitle("My Templates")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    if !templates.isEmpty {
                        createButton
                    }
                }
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
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
    
    // MARK: - Template List
    
    private var templateListView: some View {
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
                    TemplateRow(
                        template: template,
                        onEdit: {
                            templateToEdit = template
                        },
                        onDelete: {
                            templateToDelete = template
                            showingDeleteConfirmation = true
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
    
    // MARK: - Create Button
    
    @ViewBuilder
    private var createButton: some View {
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
}

// MARK: - Template Row

struct TemplateRow: View {
    let template: CustomTemplate
    let onEdit: () -> Void
    let onDelete: () -> Void
    
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
                        
                        // Mode badge
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
            }
            
            // Stats row
            HStack(spacing: SBSLayout.paddingMedium) {
                Label(daysDescription, systemImage: "calendar")
                Label(weeksDescription, systemImage: "clock")
                Label("\(exerciseCount) exercises", systemImage: "figure.strengthtraining.traditional")
            }
            .font(SBSFonts.caption())
            .foregroundStyle(SBSColors.textTertiaryFallback)
            
            // Last updated
            HStack {
                Text("Updated \(template.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Spacer()
                
                // Action buttons
                HStack(spacing: SBSLayout.paddingMedium) {
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
    }
}

#Preview {
    TemplateListView(appState: AppState())
}

