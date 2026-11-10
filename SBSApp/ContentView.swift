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
        // The bars sit under the TabView rather than in a safe-area inset on each tab:
        // that inset never reached the scroll views inside a tab's NavigationStack, so
        // the end of every list stayed under the tab bar. Stacked, each tab ends above
        // the bars.
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                tabs
            }
            bottomBars
        }
        // Orange as text and icons (links, toggles) is orange-text, never the fill
        .tint(Color.orangeText)
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

    @ViewBuilder
    private var tabs: some View {
        HomeView(appState: appState)
            .toolbar(.hidden, for: .tabBar)
            .tag(ContentView.Tab.home)

        ProgramsView(appState: appState, selectedTab: $selectedTab)
            .toolbar(.hidden, for: .tabBar)
            .tag(ContentView.Tab.programs)

        HistoryView(appState: appState)
            .toolbar(.hidden, for: .tabBar)
            .tag(ContentView.Tab.history)

        CalculatorsView(appState: appState)
            .toolbar(.hidden, for: .tabBar)
            .tag(ContentView.Tab.calculators)

        SettingsView(appState: appState)
            .toolbar(.hidden, for: .tabBar)
            .tag(ContentView.Tab.settings)
    }

    static let tabItems: [SBSTabBar.Item] = [
        .init(tab: .home, title: "Workout", symbol: "dumbbell"),
        .init(tab: .programs, title: "Programs", symbol: "book.pages"),
        .init(tab: .history, title: "History", symbol: "chart.bar"),
        .init(tab: .calculators, title: "Calculators", symbol: "number.square"),
        .init(tab: .settings, title: "Settings", symbol: "gearshape"),
    ]

    /// The resume bar above the tab bar
    private var bottomBars: some View {
        VStack(spacing: 0) {
            resumeBar
            SBSTabBar(selection: $selectedTab, items: Self.tabItems) {
                // The active tab again: back to its root, then to the top, as the system
                // bar does. The workout is a cover above this bar, so nothing here can
                // reach it.
                ScrollToTop.reselectVisibleTab()
            }
        }
    }

    /// Shows a workout is running whenever it's minimized
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

// MARK: - Tab Bar

/// The app's tab bar: surface, the signature 2px rule along its top edge, SF Symbols
/// outlined when inactive and filled when active, labels in the tab style. The
/// active item is orange-text; nothing sits behind it.
struct SBSTabBar: View {
    struct Item: Identifiable {
        let tab: ContentView.Tab
        let title: String
        let symbol: String
        var id: ContentView.Tab { tab }
    }

    @Binding var selection: ContentView.Tab
    let items: [Item]
    /// Tapping the tab that's already selected
    let onReselect: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isActive = item.tab == selection
                Button {
                    if isActive {
                        onReselect()
                    } else {
                        selection = item.tab
                    }
                } label: {
                    VStack(spacing: SBSLayout.space1) {
                        Image(systemName: item.symbol)
                            .symbolVariant(isActive ? .fill : .none)
                            .font(.system(size: 22, weight: .semibold))
                            .frame(height: 26)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .tabText()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(isActive ? Color.orangeText : Color.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // One element per tab, named by its title (the visible text is uppercased)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(.horizontal, SBSLayout.space1)
        // Held at the default size like the system tab bar: five labels in a phone's
        // width have no room to grow. They truncate rather than wrap, and a long press
        // shows the large content viewer at accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .background(Color.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.rule)
                .frame(height: SBSLayout.strokeRule)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .accessibilityIdentifier("tabBar")
    }
}

// MARK: - Scroll To Top

/// What the system tab bar does when its selected tab is tapped again: pop a pushed
/// screen back to the tab's root, or, already at the root, scroll to the top. Only the
/// selected tab's views are in the window, so everything found on screen belongs to it.
enum ScrollToTop {
    @MainActor
    static func reselectVisibleTab() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        // Nothing presented over the tabs: a sheet or the workout cover owns the screen
        guard window.rootViewController?.presentedViewController == nil else { return }
        if let navigation = pushedNavigationController(in: window) {
            navigation.popToRootViewController(animated: true)
            return
        }
        for scrollView in scrollViews(in: window) {
            let top = CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top)
            if scrollView.contentOffset.y > top.y {
                scrollView.setContentOffset(top, animated: true)
            }
        }
    }

    /// A navigation controller on screen with something pushed on it
    @MainActor
    private static func pushedNavigationController(in view: UIView) -> UINavigationController? {
        guard !view.isHidden else { return nil }
        if let navigation = view.next as? UINavigationController,
           navigation.viewControllers.count > 1 {
            return navigation
        }
        for subview in view.subviews {
            if let found = pushedNavigationController(in: subview) { return found }
        }
        return nil
    }

    @MainActor
    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        guard !view.isHidden, view.alpha > 0.01 else { return [] }
        var found: [UIScrollView] = []
        if let scrollView = view as? UIScrollView,
           scrollView.isScrollEnabled,
           scrollView.contentSize.height > scrollView.bounds.height,
           // Horizontal strips (a week strip, a carousel) stay where they are
           scrollView.contentSize.width <= scrollView.bounds.width + 1,
           !(scrollView is UITextView) {
            found.append(scrollView)
        }
        for subview in view.subviews {
            found += scrollViews(in: subview)
        }
        return found
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: SBSLayout.space6) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.ink)
            
            VStack(spacing: SBSLayout.space2) {
                Text("Loading")
                    .titleLargeText()
                    .foregroundStyle(Color.ink)
                
                Text("Preparing your workout")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            }
            
            ProgressView()
                .tint(Color.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sbsBackground()
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: SBSLayout.space6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.warning)
            
            VStack(spacing: SBSLayout.space2) {
                Text("Unable to load")
                    .font(SBSFonts.title())
                    .foregroundStyle(Color.ink)
                
                Text(message)
                    .font(SBSFonts.body())
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SBSLayout.space4)
            }
            
            Button(action: onRetry) {
                SBSButtonTitle("Try again")
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
