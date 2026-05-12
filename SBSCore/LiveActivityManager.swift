import Foundation
import ActivityKit
import SwiftUI

/// Manages the Live Activity for the rest timer
@MainActor
public final class LiveActivityManager: ObservableObject {
    
    public static let shared = LiveActivityManager()
    
    private var currentActivity: Activity<RestTimerAttributes>?
    private var timerEndTime: Date?
    
    private init() {
        // Clean up any stale activities on init
        Task {
            await endAllActivities()
        }
    }
    
    /// Check if Live Activities are supported and enabled
    public var isLiveActivitySupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    /// End all running Live Activities (cleanup on app launch)
    public func endAllActivities() async {
        Logger.debug("🧹 Cleaning up any stale Live Activities...", category: .liveActivity)

        for activity in Activity<RestTimerAttributes>.activities {
            Logger.debug("   - Ending activity: \(activity.id)", category: .liveActivity)
            await endActivity(activity)
        }

        currentActivity = nil
        timerEndTime = nil

        let remaining = Activity<RestTimerAttributes>.activities.count
        Logger.debug("   - Remaining activities: \(remaining)", category: .liveActivity)
    }

    /// End any activities whose timer has already expired. Safe to call on app
    /// foreground — won't disturb a still-running timer.
    public func endExpiredActivities() async {
        let now = Date()
        for activity in Activity<RestTimerAttributes>.activities {
            if activity.content.state.endTime <= now {
                Logger.debug("🧹 Ending expired Live Activity: \(activity.id)", category: .liveActivity)
                await endActivity(activity)
                if currentActivity?.id == activity.id {
                    currentActivity = nil
                    timerEndTime = nil
                }
            }
        }
    }

    /// Ends a single activity with a refreshed final content state. Passing a
    /// fresh ActivityContent (rather than nil) is important because iOS will
    /// not reliably dismiss an already-stale activity ended with nil content.
    private func endActivity(_ activity: Activity<RestTimerAttributes>) async {
        let finalState = RestTimerAttributes.ContentState(
            secondsRemaining: 0,
            isPaused: false,
            endTime: Date()
        )
        let finalContent = ActivityContent(
            state: finalState,
            staleDate: Date().addingTimeInterval(60 * 60)
        )
        await activity.end(finalContent, dismissalPolicy: .immediate)
    }
    
    /// Start a Live Activity for the rest timer
    /// - Parameters:
    ///   - exerciseName: Name of the exercise
    ///   - duration: Total timer duration in seconds
    ///   - nextSetInfo: Info about the next set (e.g., "Set 3 of 5")
    public func startTimer(
        exerciseName: String,
        duration: Int,
        nextSetInfo: String
    ) {
        Logger.debug("🔵 LiveActivityManager.startTimer called", category: .liveActivity)
        Logger.debug("   - Exercise: \(exerciseName)", category: .liveActivity)
        Logger.debug("   - Duration: \(duration)s", category: .liveActivity)
        Logger.debug("   - isLiveActivitySupported: \(isLiveActivitySupported)", category: .liveActivity)
        
        guard isLiveActivitySupported else {
            Logger.warning("Live Activities are not supported or enabled on this device", category: .liveActivity)
            return
        }
        
        // End any existing activities first, then create the new one in
        // sequence so they can't race.
        Task { @MainActor in
            await endAllActivities()
            createNewActivity(exerciseName: exerciseName, duration: duration, nextSetInfo: nextSetInfo)
        }
    }

    private func createNewActivity(exerciseName: String, duration: Int, nextSetInfo: String) {
        let endTime = Date().addingTimeInterval(TimeInterval(duration))
        timerEndTime = endTime
        
        let attributes = RestTimerAttributes(
            exerciseName: exerciseName,
            totalDuration: duration,
            nextSetInfo: nextSetInfo
        )
        
        let contentState = RestTimerAttributes.ContentState(
            secondsRemaining: duration,
            isPaused: false,
            endTime: endTime
        )
        
        // No near-term staleDate: a short staleDate causes iOS to overlay the
        // "stale" sparkle indicator over the icons/text once the timer hits 0,
        // which looks broken on the lock screen / Dynamic Island. The activity
        // is dismissed explicitly by endTimer(); if the timer expires while the
        // app is backgrounded, scenePhase-active cleanup ends it on reopen.
        let content = ActivityContent(
            state: contentState,
            staleDate: nil
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            Logger.info("✅ Started Live Activity for rest timer - ID: \(currentActivity?.id ?? "unknown")", category: .liveActivity)
        } catch {
            Logger.error("Failed to start Live Activity: \(error)", category: .liveActivity)
        }
    }
    
    /// Update the timer state (for pause/resume or manual time adjustments)
    /// - Parameters:
    ///   - secondsRemaining: Current seconds remaining
    ///   - isPaused: Whether the timer is paused
    public func updateTimer(secondsRemaining: Int, isPaused: Bool) {
        guard let activity = currentActivity else { return }
        
        let endTime: Date
        if isPaused {
            // When paused, set end time far in future to prevent countdown
            endTime = Date().addingTimeInterval(86400) // 24 hours
        } else {
            endTime = Date().addingTimeInterval(TimeInterval(secondsRemaining))
        }
        timerEndTime = endTime
        
        let contentState = RestTimerAttributes.ContentState(
            secondsRemaining: secondsRemaining,
            isPaused: isPaused,
            endTime: endTime
        )
        
        let content = ActivityContent(
            state: contentState,
            staleDate: nil
        )
        
        Task {
            await activity.update(content)
        }
    }
    
    /// End the Live Activity
    public func endTimer() async {
        if let activity = currentActivity {
            Logger.debug("🛑 Ending tracked Live Activity: \(activity.id)", category: .liveActivity)
            await endActivity(activity)
        }

        // Also end any other activities that might be lingering
        for activity in Activity<RestTimerAttributes>.activities {
            Logger.debug("🛑 Ending lingering activity: \(activity.id)", category: .liveActivity)
            await endActivity(activity)
        }

        currentActivity = nil
        timerEndTime = nil
        Logger.info("✅ All Live Activities ended", category: .liveActivity)
    }
    
    /// End the timer synchronously (for use in non-async contexts)
    public func endTimerSync() {
        Task {
            await endTimer()
        }
    }
    
    /// Force cleanup - call this if activities are stuck
    public func forceCleanup() {
        Task {
            await endAllActivities()
        }
    }
}
