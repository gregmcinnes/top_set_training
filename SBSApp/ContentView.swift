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
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(appState: appState)
                .tag(ContentView.Tab.home)
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }
            
            ProgramsView(appState: appState, selectedTab: $selectedTab)
                .tag(ContentView.Tab.programs)
                .tabItem {
                    Label("Programs", systemImage: "book.pages")
                }
            
            HistoryView(appState: appState)
                .tag(ContentView.Tab.history)
                .tabItem {
                    Label("History", systemImage: "chart.line.uptrend.xyaxis")
                }
            
            CalculatorsView(appState: appState)
                .tag(ContentView.Tab.calculators)
                .tabItem {
                    Label("Calculators", systemImage: "function")
                }
            
            SettingsView(appState: appState)
                .tag(ContentView.Tab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(SBSColors.accentFallback)
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
                    .font(SBSFonts.title())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Preparing your workout")
                    .font(SBSFonts.caption())
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
                    .font(SBSFonts.title())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text(message)
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Try Again") {
                onRetry()
            }
            .buttonStyle(SBSPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sbsBackground()
    }
}

#Preview {
    ContentView()
}
