import SwiftUI

@main
struct SBSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Clean up any stale Live Activities on app launch
        // This handles the case where the app was force-closed while a timer was running
        Task { @MainActor in
            await LiveActivityManager.shared.endAllActivities()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // When app becomes active, check if there are orphaned activities
                // that don't correspond to an active timer
                print("📱 App became active - checking for orphaned Live Activities")
            }
        }
    }
}
