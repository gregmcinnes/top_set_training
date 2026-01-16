import SwiftUI
import HealthKit

@main
struct SBSWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager()
    @StateObject private var sessionManager = WatchSessionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Connect session manager to workout manager immediately at app launch
        // This ensures the connection is ready before any messages arrive from iPhone
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
                .environmentObject(sessionManager)
                .task {
                    // Connect session manager to workout manager
                    // Using task ensures this runs as soon as the view hierarchy is created
                    sessionManager.workoutManager = workoutManager
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        // Re-sync state when app becomes active
                        sessionManager.syncFromApplicationContext()
                    }
                }
        }
    }
}
