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

    private var isDeletingActiveTemplate: Bool {
        guard let template = templateToDelete else { return false }
        return appState.userData.selectedProgram == UserData.programId(for: template.id)
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        TemplatesEmptyState(
            showsFreeTierInfo: !storeManager.isPremium,
            onCreate: { showingTemplateBuilder = true },
            onUpgrade: { showingPaywall = true }
        )
    }

    // MARK: - Template List
    
    private var templateListView: some View {
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
                SBSListHeader("Saved Templates")
            } footer: {
                SBSListFooter("Templates can be selected when starting a new training cycle.")
            }
            .sbsListRows()
        }
        .sbsGroupedList()
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
    
}

// MARK: - Template Row

struct TemplateRow: View {
    let template: CustomTemplate
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            VStack(alignment: .leading, spacing: SBSLayout.space1) {
                HStack(spacing: SBSLayout.space2) {
                    Text(template.name)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)

                    // Mode badge
                    SBSBadge(text: template.mode.displayName)
                }

                if !template.templateDescription.isEmpty {
                    Text(template.templateDescription)
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(2)
                }
            }

            TemplateMetaLine(template: template)

            // Last updated
            HStack {
                SBSRowSubtitle("Updated \(template.updatedAt.formatted(.relative(presentation: .named)))")

                Spacer()

                // Action buttons
                HStack(spacing: SBSLayout.space4) {
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
    }
}

#Preview {
    TemplateListView(appState: AppState())
}

