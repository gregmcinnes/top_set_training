import Foundation
import ActivityKit

/// Defines the data structure for the rest timer Live Activity
public struct RestTimerAttributes: ActivityAttributes {
    
    /// Static attributes that don't change during the activity
    public struct ContentState: Codable, Hashable {
        /// Seconds remaining in the timer
        public var secondsRemaining: Int
        /// Whether the timer is paused
        public var isPaused: Bool
        /// The end time of the timer (for system countdown display)
        public var endTime: Date
        
        public init(secondsRemaining: Int, isPaused: Bool, endTime: Date) {
            self.secondsRemaining = secondsRemaining
            self.isPaused = isPaused
            self.endTime = endTime
        }
    }
    
    /// The exercise name being rested from
    public var exerciseName: String
    /// The total duration of the timer in seconds
    public var totalDuration: Int
    /// Next set info (e.g., "Set 3 of 5")
    public var nextSetInfo: String
    
    public init(exerciseName: String, totalDuration: Int, nextSetInfo: String) {
        self.exerciseName = exerciseName
        self.totalDuration = totalDuration
        self.nextSetInfo = nextSetInfo
    }
}



