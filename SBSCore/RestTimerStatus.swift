import Foundation
import Observation

/// App-wide mirror of the in-workout rest timer.
///
/// `WorkoutState` / `AccessoryWorkoutState` own the real timer; they publish
/// transitions here so that:
/// - views outside the workout screen (other tabs) can show a countdown pill
/// - `NotificationManager` can tell whether the workout screen is visible
///   when deciding to present the rest-complete notification in-foreground
@Observable
public final class RestTimerStatus {

    public static let shared = RestTimerStatus()

    /// True while a rest timer is logically running or paused.
    public private(set) var isActive = false

    public private(set) var isPaused = false

    /// Wall-clock end of a running timer (nil while paused).
    public private(set) var endDate: Date?

    /// Remaining seconds captured at pause time.
    public private(set) var pausedRemaining: Int?

    /// True while WorkoutView or AccessoryWorkoutView is on screen.
    /// The pill hides and foreground notifications are suppressed when set.
    public var isWorkoutScreenVisible = false

    private init() {}

    public func timerStarted(endDate: Date) {
        isActive = true
        isPaused = false
        self.endDate = endDate
        pausedRemaining = nil
    }

    public func timerPaused(remaining: Int) {
        isActive = true
        isPaused = true
        endDate = nil
        pausedRemaining = remaining
    }

    public func timerCleared() {
        isActive = false
        isPaused = false
        endDate = nil
        pausedRemaining = nil
    }

    /// Seconds remaining right now (0 once expired or inactive).
    public var remaining: Int {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, Int(ceil(endDate.timeIntervalSinceNow)))
    }

    /// A running timer reached zero but hasn't been dismissed yet
    /// (it expired while the workout screen was off screen).
    public var isExpired: Bool {
        isActive && !isPaused && remaining <= 0
    }
}
