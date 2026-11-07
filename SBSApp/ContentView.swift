import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedTab: Tab = .home
    @State private var showingOnboarding = false
    
    enum Tab {
        case home
        case programs
        case history
        case calculators
        case settings
    }
    
    private var preferredColorScheme: ColorScheme? {
        switch appState.settings.appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if let error = loadError {
                ErrorView(message: error) {
                    Task {
                        await loadData()
                    }
                }
            } else if showingOnboarding {
                CycleBuilderView(
                    appState: appState,
                    isOnboarding: true,
                    onComplete: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingOnboarding = false
                            selectedTab = .home
                        }
                    },
                    onCancel: nil
                )
                .transition(.opacity)
            } else {
                MainTabView(appState: appState, selectedTab: $selectedTab)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        isLoading = true
        loadError = nil
        
        do {
            try await appState.loadProgramConfig()

            // A workout saved before the app was killed comes back behind the resume bar
            if !appState.needsOnboarding {
                appState.restoreActiveSessionIfNeeded()
            }
            
            // Only reads the status. The permission prompt waits for the first rest timer.
            await NotificationManager.shared.checkAuthorizationStatus()

            // Check if onboarding is needed
            await MainActor.run {
                if appState.needsOnboarding {
                    showingOnboarding = true
                }
            }
            
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @Bindable var appState: AppState
    @Binding var selectedTab: ContentView.Tab
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(appState: appState)
                .safeAreaInset(edge: .bottom, spacing: 0) { resumeBar }
                .tag(ContentView.Tab.home)
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }
            
            ProgramsView(appState: appState, selectedTab: $selectedTab)
                .safeAreaInset(edge: .bottom, spacing: 0) { resumeBar }
                .tag(ContentView.Tab.programs)
                .tabItem {
                    Label("Programs", systemImage: "book.pages")
                }
            
            HistoryView(appState: appState)
                .safeAreaInset(edge: .bottom, spacing: 0) { resumeBar }
                .tag(ContentView.Tab.history)
                .tabItem {
                    Label("History", systemImage: "chart.line.uptrend.xyaxis")
                }
            
            CalculatorsView(appState: appState)
                .safeAreaInset(edge: .bottom, spacing: 0) { resumeBar }
                .tag(ContentView.Tab.calculators)
                .tabItem {
                    Label("Calculators", systemImage: "function")
                }
            
            SettingsView(appState: appState)
                .safeAreaInset(edge: .bottom, spacing: 0) { resumeBar }
                .tag(ContentView.Tab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(SBSColors.accentFallback)
        .animation(.spring(duration: 0.3), value: appState.activeSession?.id)
        // Above the tab bar, so nothing in it can pop the workout. Item-driven, so the
        // screen keeps its session while animating away after the session has ended.
        .fullScreenCover(item: Binding(
            get: { appState.presentedSession },
            set: { if $0 == nil { appState.minimizeWorkout() } }
        )) { session in
            WorkoutView(appState: appState, session: session)
        }
        .alert("Resume Your Workout?", isPresented: $appState.showingStaleSessionPrompt) {
            // The cancel role, or iOS adds a third button that answers nothing
            Button("Resume", role: .cancel) {
                appState.keepStaleSession()
            }
            Button("Discard", role: .destructive) {
                appState.activeSession?.exitWorkoutWithoutSaving()
            }
        } message: {
            Text("This workout has been sitting for a while. Results you've already logged are kept either way.")
        }
        .onChange(of: appState.returnToHomeCount) { _, _ in
            selectedTab = .home
        }
        // Here rather than on a tab, which may not be updating while off screen
        .onChange(of: appState.userData.currentCycleStartDate) { _, _ in
            appState.endWorkoutForCycleChange()
        }
        // Switching programs with nothing logged leaves the cycle date alone
        .onChange(of: appState.userData.selectedProgram) { _, _ in
            appState.endWorkoutForCycleChange()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                appState.activeSession?.appDidBecomeActive()
                appState.promptIfActiveSessionIsStale()
            case .background:
                appState.activeSession?.persist()
            default:
                break
            }
        }
    }

    /// Shows a workout is running whenever it's minimized. A per-tab safe-area inset
    /// sits above the tab bar whatever its height and keeps the bar from covering the
    /// end of a scrolled list.
    @ViewBuilder
    private var resumeBar: some View {
        if let session = appState.activeSession {
            ResumeWorkoutBar(session: session) {
                appState.resumeWorkout()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingLarge) {
            // App icon / logo
            ZStack {
                Circle()
                    .fill(SBSColors.accentFallback.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(SBSColors.accentFallback)
                    .rotationEffect(.degrees(rotation))
            }
            
            VStack(spacing: SBSLayout.paddingSmall) {
                Text("Loading...")
                    .font(SBSFonts.legacyTitle())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Preparing your workout")
                    .font(SBSFonts.legacyCaption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            ProgressView()
                .tint(SBSColors.accentFallback)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sbsBackground()
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: SBSLayout.paddingLarge) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(SBSColors.warning)
            
            VStack(spacing: SBSLayout.paddingSmall) {
                Text("Unable to Load")
                    .font(SBSFonts.legacyTitle())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text(message)
                    .font(SBSFonts.legacyBody())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Try Again") {
                onRetry()
            }
            .buttonStyle(SBSLegacyPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sbsBackground()
    }
}

#Preview {
    ContentView()
}
