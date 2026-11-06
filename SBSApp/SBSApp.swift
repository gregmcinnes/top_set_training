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

        // Activate WCSession at launch, not at the first workout: this is what
        // lets a relaunch tell the Watch that a workout from a killed process is over.
        Task { @MainActor in
            _ = WatchConnectivityManager.shared
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                Logger.debug("📱 App became active - checking for orphaned Live Activities", category: .liveActivity)

                // Clear any delivered rest timer notifications (user is back in app)
                NotificationManager.shared.clearDeliveredNotifications()

                // Re-check premium entitlements (purchase on another device,
                // Ask to Buy approval, or a product fetch that failed at launch).
                Task { @MainActor in
                    await StoreManager.shared.refreshEntitlements()
                }

                // End any Live Activity this process isn't tracking. Covers
                // both the expired-while-backgrounded case (foreground Timer
                // can't fire handleTimerEnd) and the force-quit case (relaunched
                // process has currentActivity=nil so every survivor is orphaned).
                // A still-active foreground timer is matched and left alone.
                // Then end a tracked timer that expired, and start the activity for a
                // rest that began while backgrounded (iOS refused it at the time).
                Task { @MainActor in
                    await LiveActivityManager.shared.endOrphanedActivities()
                    await LiveActivityManager.shared.endExpiredActivities()
                    LiveActivityManager.shared.startDeferredActivityIfNeeded()
                }
            }
        }
    }
}
