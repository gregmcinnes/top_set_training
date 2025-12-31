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
        print("🧹 Cleaning up any stale Live Activities...")
        
        for activity in Activity<RestTimerAttributes>.activities {
            print("   - Ending stale activity: \(activity.id)")
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        
        currentActivity = nil
        timerEndTime = nil
        
        let remaining = Activity<RestTimerAttributes>.activities.count
        print("   - Remaining activities: \(remaining)")
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
        print("🔵 LiveActivityManager.startTimer called")
        print("   - Exercise: \(exerciseName)")
        print("   - Duration: \(duration)s")
        print("   - isLiveActivitySupported: \(isLiveActivitySupported)")
        
        guard isLiveActivitySupported else {
            print("❌ Live Activities are not supported or enabled on this device")
            return
        }
        
        // End ALL existing activities first (not just tracked one)
        Task {
            await endAllActivities()
        }
        
        // Small delay to ensure cleanup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            self.createNewActivity(exerciseName: exerciseName, duration: duration, nextSetInfo: nextSetInfo)
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
        
        let content = ActivityContent(
            state: contentState,
            staleDate: endTime.addingTimeInterval(10) // Stale 10s after timer ends
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("✅ Started Live Activity for rest timer - ID: \(currentActivity?.id ?? "unknown")")
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
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
            staleDate: isPaused ? nil : endTime.addingTimeInterval(10)
        )
        
        Task {
            await activity.update(content)
        }
    }
    
    /// End the Live Activity
    public func endTimer() async {
        // End the tracked activity
        if let activity = currentActivity {
            print("🛑 Ending tracked Live Activity: \(activity.id)")
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        
        // Also end any other activities that might be lingering
        for activity in Activity<RestTimerAttributes>.activities {
            print("🛑 Ending lingering activity: \(activity.id)")
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        
        currentActivity = nil
        timerEndTime = nil
        print("✅ All Live Activities ended")
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
