import Foundation
import UserNotifications

/// Manages local push notifications for rest timer alerts
@MainActor
public final class NotificationManager: ObservableObject {
    
    public static let shared = NotificationManager()
    
    /// Notification identifier for the rest timer
    private let restTimerNotificationId = "rest_timer_complete"
    
    /// Published authorization status for UI binding
    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Authorization
    
    /// Check current notification authorization status
    public func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    /// Request notification permission from the user
    /// - Returns: Whether permission was granted
    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await checkAuthorizationStatus()
            Logger.info("Notification permission \(granted ? "granted" : "denied")", category: .general)
            return granted
        } catch {
            Logger.error("Failed to request notification permission: \(error)", category: .general)
            return false
        }
    }
    
    /// Request permission if notifications are enabled in settings but permission not yet granted
    /// Call this on app launch
    public func requestAuthorizationIfNeeded(notificationsEnabled: Bool) {
        guard notificationsEnabled else { return }
        
        Task {
            await checkAuthorizationStatus()
            if authorizationStatus == .notDetermined {
                await requestAuthorization()
            }
        }
    }
    
    /// Check if notifications are authorized
    public var isAuthorized: Bool {
        authorizationStatus == .authorized
    }
    
    // MARK: - Rest Timer Notifications
    
    /// Schedule a notification for when the rest timer ends
    /// - Parameters:
    ///   - duration: Timer duration in seconds
    ///   - exerciseName: Name of the exercise (for notification content)
    ///   - nextSetInfo: Info about the next set (e.g., "Set 3 of 5")
    public func scheduleRestTimerNotification(
        duration: Int,
        exerciseName: String,
        nextSetInfo: String
    ) {
        guard duration > 0 else {
            Logger.debug("Skipping notification - duration is 0 or negative", category: .general)
            return
        }
        
        // Cancel any existing timer notification first
        cancelRestTimerNotification()
        
        // Schedule the notification - let the system handle authorization
        // If not authorized, the notification simply won't show
        let content = UNMutableNotificationContent()
        content.title = "Rest Complete! 💪"
        content.body = "Time for \(nextSetInfo) - \(exerciseName)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        
        // Schedule for when the timer ends
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(duration),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: restTimerNotificationId,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.error("Failed to schedule notification: \(error)", category: .general)
            } else {
                Logger.debug("📬 Scheduled rest timer notification for \(duration)s", category: .general)
            }
        }
    }
    
    /// Cancel any pending rest timer notification
    /// Call this when:
    /// - The app comes to foreground and handles timer end itself
    /// - The user skips the timer
    /// - The timer is paused/reset
    public func cancelRestTimerNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [restTimerNotificationId]
        )
        Logger.debug("🚫 Cancelled pending rest timer notification", category: .general)
    }
    
    /// Cancel all delivered notifications (clears notification center)
    public func clearDeliveredNotifications() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [restTimerNotificationId]
        )
    }
}

