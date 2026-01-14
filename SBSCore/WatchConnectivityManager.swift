import Foundation
import WatchConnectivity

// MARK: - Watch Workout State

/// Workout state data to sync to Watch
public struct WatchWorkoutState: Codable {
    public let exerciseName: String
    public let currentSet: Int
    public let totalSets: Int
    public let weight: Double
    public let targetReps: Int
    public let isRestTimerActive: Bool
    public let restTimerRemaining: Int
    public let restTimerDuration: Int
    public let useMetric: Bool
    public let nextSetInfo: String?  // e.g. "Next: Set 3 of 5"
    public let isRepOutSet: Bool
    
    public init(
        exerciseName: String,
        currentSet: Int,
        totalSets: Int,
        weight: Double,
        targetReps: Int,
        isRestTimerActive: Bool,
        restTimerRemaining: Int,
        restTimerDuration: Int,
        useMetric: Bool,
        nextSetInfo: String?,
        isRepOutSet: Bool
    ) {
        self.exerciseName = exerciseName
        self.currentSet = currentSet
        self.totalSets = totalSets
        self.weight = weight
        self.targetReps = targetReps
        self.isRestTimerActive = isRestTimerActive
        self.restTimerRemaining = restTimerRemaining
        self.restTimerDuration = restTimerDuration
        self.useMetric = useMetric
        self.nextSetInfo = nextSetInfo
        self.isRepOutSet = isRepOutSet
    }
}

// MARK: - Watch Connectivity Manager (iOS)

/// Manages Watch Connectivity for starting/stopping workout sessions on the Watch
/// This enables heart rate collection during workouts via HKWorkoutSession on the Watch
@MainActor
public final class WatchConnectivityManager: NSObject, ObservableObject {
    public static let shared = WatchConnectivityManager()
    
    @Published public private(set) var isWatchReachable = false
    @Published public private(set) var isWatchAppInstalled = false
    @Published public private(set) var currentHeartRate: Double?
    
    private var session: WCSession?
    
    private override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        guard WCSession.isSupported() else {
            Logger.debug("Watch Connectivity not supported on this device", category: .general)
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    // MARK: - Public Methods
    
    /// Notify Watch to start a workout session (for heart rate collection)
    public func sendWorkoutStarted() {
        guard let session = session,
              session.activationState == .activated,
              session.isReachable else {
            Logger.debug("Watch not reachable, cannot send workout start", category: .general)
            return
        }
        
        session.sendMessage(["type": "workoutStarted"], replyHandler: nil) { error in
            Logger.error("Failed to send workout start to Watch: \(error.localizedDescription)", category: .general)
        }
        Logger.debug("Sent workout start to Watch", category: .general)
    }
    
    /// Notify Watch to end the workout session
    public func sendWorkoutEnded() {
        // Clear heart rate when workout ends
        currentHeartRate = nil
        
        guard let session = session,
              session.activationState == .activated,
              session.isReachable else {
            Logger.debug("Watch not reachable, cannot send workout end", category: .general)
            return
        }
        
        session.sendMessage(["type": "workoutEnded"], replyHandler: nil) { error in
            Logger.error("Failed to send workout end to Watch: \(error.localizedDescription)", category: .general)
        }
        Logger.debug("Sent workout end to Watch", category: .general)
    }
    
    /// Send workout state update to Watch
    public func sendWorkoutState(_ state: WatchWorkoutState) {
        guard let session = session,
              session.activationState == .activated,
              session.isReachable else {
            return  // Silently fail - state updates are best-effort
        }
        
        // Encode state to JSON data then to dictionary
        guard let data = try? JSONEncoder().encode(state),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        var message: [String: Any] = ["type": "workoutState"]
        message["state"] = json
        
        session.sendMessage(message, replyHandler: nil) { _ in
            // Silently fail - state updates are best-effort
        }
    }
    
    /// Send rest timer update to Watch
    public func sendRestTimerUpdate(remaining: Int, duration: Int, exerciseName: String) {
        guard let session = session,
              session.activationState == .activated,
              session.isReachable else {
            return
        }
        
        session.sendMessage([
            "type": "restTimerUpdate",
            "remaining": remaining,
            "duration": duration,
            "exerciseName": exerciseName
        ], replyHandler: nil) { _ in
            // Silently fail
        }
    }
    
    /// Send rest timer ended notification to Watch
    public func sendRestTimerEnded() {
        guard let session = session,
              session.activationState == .activated,
              session.isReachable else {
            return
        }
        
        session.sendMessage(["type": "restTimerEnded"], replyHandler: nil) { _ in
            // Silently fail
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                Logger.error("Watch session activation failed: \(error.localizedDescription)", category: .general)
            } else {
                Logger.debug("Watch session activated: \(activationState.rawValue)", category: .general)
                self.isWatchReachable = session.isReachable
                self.isWatchAppInstalled = session.isWatchAppInstalled
            }
        }
    }
    
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        Logger.debug("Watch session became inactive", category: .general)
    }
    
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        Logger.debug("Watch session deactivated", category: .general)
        // Reactivate for switching watches
        session.activate()
    }
    
    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
            Logger.debug("Watch reachability changed: \(session.isReachable)", category: .general)
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            guard let type = message["type"] as? String else { return }
            
            switch type {
            case "heartRateUpdate":
                if let heartRate = message["heartRate"] as? Double {
                    self.currentHeartRate = heartRate
                }
            default:
                break
            }
        }
    }
}
