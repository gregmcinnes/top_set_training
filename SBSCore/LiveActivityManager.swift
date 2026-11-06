import Foundation
import ActivityKit
import SwiftUI

/// Manages the Live Activity for the rest timer
@MainActor
public final class LiveActivityManager: ObservableObject {
    
    public static let shared = LiveActivityManager()
    
    private var currentActivity: Activity<RestTimerAttributes>?
    private var timerEndTime: Date?
    /// Ends the activity shortly after its timer expires while the app is running,
    /// e.g. the user is on another tab where nothing else observes the expiry.
    private var expiryCleanupTask: Task<Void, Never>?

    /// A rest that could not get an activity because iOS refuses to start one while
    /// the app is backgrounded (a rest begun from the Watch with the phone locked).
    /// Retried on foreground while that rest is still running.
    private struct DeferredActivity {
        var exerciseName: String
        var duration: Int
        var nextSetInfo: String
        var endTime: Date
        var isPaused: Bool
    }
    private var deferredActivity: DeferredActivity?
    
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
        deferredActivity = nil
        expiryCleanupTask?.cancel()
        expiryCleanupTask = nil

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

    /// End any activity that this process isn't tracking as `currentActivity`.
    /// Catches activities left behind by a force-quit / memory-pressure kill:
    /// after relaunch `currentActivity` is nil, so every still-registered
    /// activity is an orphan and gets ended. A genuinely active in-foreground
    /// timer is matched and left alone.
    public func endOrphanedActivities() async {
        let trackedID = currentActivity?.id
        for activity in Activity<RestTimerAttributes>.activities where activity.id != trackedID {
            Logger.debug("🧹 Ending orphaned Live Activity: \(activity.id)", category: .liveActivity)
            await endActivity(activity)
        }
    }

    /// Ends a single activity with a refreshed final content state. Passing a
    /// fresh ActivityContent (rather than nil) is important because iOS will
    /// not reliably dismiss an already-stale activity ended with nil content.
    /// staleDate must be nil here: a future staleDate combined with
    /// `dismissalPolicy: .immediate` causes iOS to keep the ended activity
    /// visible in a redacted/shimmer presentation on the lock screen until the
    /// staleDate passes (a 1-hour value here was leaving frozen icons up for
    /// ~an hour after exiting a workout).
    private func endActivity(_ activity: Activity<RestTimerAttributes>) async {
        let finalState = RestTimerAttributes.ContentState(
            secondsRemaining: 0,
            isPaused: false,
            endTime: Date()
        )
        let finalContent = ActivityContent(
            state: finalState,
            staleDate: nil
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

    private func createNewActivity(exerciseName: String, duration: Int, nextSetInfo: String, endTime: Date? = nil) {
        let endTime = endTime ?? Date().addingTimeInterval(TimeInterval(duration))
        timerEndTime = endTime
        
        let attributes = RestTimerAttributes(
            exerciseName: exerciseName,
            totalDuration: duration,
            nextSetInfo: nextSetInfo
        )
        
        let contentState = RestTimerAttributes.ContentState(
            secondsRemaining: max(0, Int(ceil(endTime.timeIntervalSinceNow))),
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
            deferredActivity = nil
            scheduleExpiryCleanup(at: endTime)
            Logger.info("✅ Started Live Activity for rest timer - ID: \(currentActivity?.id ?? "unknown")", category: .liveActivity)
        } catch {
            deferredActivity = DeferredActivity(
                exerciseName: exerciseName,
                duration: duration,
                nextSetInfo: nextSetInfo,
                endTime: endTime,
                isPaused: false
            )
            Logger.error("Failed to start Live Activity: \(error)", category: .liveActivity)
        }
    }

    /// Start the activity for a rest whose request failed while backgrounded.
    /// Call on app foreground; a no-op unless such a rest is still running.
    public func startDeferredActivityIfNeeded() {
        guard currentActivity == nil, let deferred = deferredActivity, !deferred.isPaused else { return }
        guard deferred.endTime > Date() else {
            deferredActivity = nil
            return
        }
        createNewActivity(
            exerciseName: deferred.exerciseName,
            duration: deferred.duration,
            nextSetInfo: deferred.nextSetInfo,
            endTime: deferred.endTime
        )
    }

    private func scheduleExpiryCleanup(at endTime: Date) {
        expiryCleanupTask?.cancel()
        let delay = max(0, endTime.timeIntervalSinceNow) + 1
        expiryCleanupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.endExpiredActivities()
        }
    }
    
    /// Update the timer state (for pause/resume or manual time adjustments)
    /// - Parameters:
    ///   - secondsRemaining: Current seconds remaining
    ///   - isPaused: Whether the timer is paused
    public func updateTimer(secondsRemaining: Int, isPaused: Bool) {
        guard let activity = currentActivity else {
            if deferredActivity != nil {
                deferredActivity?.endTime = Date().addingTimeInterval(TimeInterval(secondsRemaining))
                deferredActivity?.isPaused = isPaused
            }
            return
        }

        // A once-a-second tick from a running timer carries no new information.
        // Rewriting endTime from a rounded-up count only makes the countdown jitter
        // and can leave it up to a second late, so only real changes get through.
        if !isPaused, !activity.content.state.isPaused, let existing = timerEndTime,
           abs(existing.timeIntervalSinceNow - TimeInterval(secondsRemaining)) < 1.5 {
            return
        }
        
        let endTime: Date
        if isPaused {
            // When paused, set end time far in future to prevent countdown
            endTime = Date().addingTimeInterval(86400) // 24 hours
        } else {
            endTime = Date().addingTimeInterval(TimeInterval(secondsRemaining))
        }
        timerEndTime = endTime
        if isPaused {
            expiryCleanupTask?.cancel()
            expiryCleanupTask = nil
        } else {
            scheduleExpiryCleanup(at: endTime)
        }
        
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
        deferredActivity = nil
        expiryCleanupTask?.cancel()
        expiryCleanupTask = nil
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
