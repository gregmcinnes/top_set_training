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
    public let isRepOutSet: Bool  // Volume program rep-out set
    public let isAMRAPSet: Bool   // Any AMRAP set (volume or structured)
    public let exerciseIndex: Int // Index of the current exercise (for set-completion identity)

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
        isRepOutSet: Bool,
        isAMRAPSet: Bool = false,
        exerciseIndex: Int = 0
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
        self.isAMRAPSet = isAMRAPSet
        self.exerciseIndex = exerciseIndex
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

    /// True while the Watch is running its own HealthKit-saving workout session.
    /// The phone can use this to skip its own `HKWorkoutBuilder` (the Watch's live
    /// workout is strictly better) and avoid writing duplicate HealthKit workouts.
    /// Fed by a `watchWorkoutSession` message from the Watch.
    @Published public private(set) var isWatchWorkoutSessionActive = false
    
    /// Callback triggered when Watch requests set completion
    /// WorkoutView should set this to handle set completion from Watch
    /// Parameters: rep count for AMRAP sets (nil for normal sets), and the
    /// (exerciseIndex, setNumber) the Watch was showing (both nil on older Watch
    /// builds that don't stamp identity) so the phone can drop stale requests.
    public var onSetCompletedFromWatch: ((_ reps: Int?, _ exerciseIndex: Int?, _ setNumber: Int?) -> Void)?

    private var session: WCSession?

    /// Whether the active workout is allowed to write to HealthKit. Sent to the
    /// Watch so it only starts/saves its own HK session when the phone's HealthKit
    /// setting is on. Stored so it can be re-included in every application-context
    /// snapshot (which replaces the whole context each write).
    private var lastHealthKitEnabled = false
    
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
    /// - Parameter healthKitEnabled: whether the Watch is allowed to start/save its
    ///   own HealthKit workout. When `false` (the default), the Watch tracks the
    ///   workout for display only and does NOT write a workout to HealthKit — this
    ///   prevents duplicate HealthKit workouts and honors the user's HealthKit
    ///   setting. The default is `false` so that if this flag is ever absent the
    ///   Watch errs on the side of NOT writing.
    public func sendWorkoutStarted(healthKitEnabled: Bool = false) {
        lastHealthKitEnabled = healthKitEnabled

        guard let session = session,
              session.activationState == .activated else {
            Logger.debug("Watch session not active, cannot send workout start", category: .general)
            return
        }

        // Always update application context (works even when unreachable)
        updateWorkoutContext(workoutActive: true)

        // Also try to send immediate message if reachable
        if session.isReachable {
            session.sendMessage(
                ["type": "workoutStarted", "healthKitEnabled": healthKitEnabled],
                replyHandler: nil
            ) { error in
                Logger.error("Failed to send workout start to Watch: \(error.localizedDescription)", category: .general)
            }
            Logger.debug("Sent workout start to Watch (healthKitEnabled: \(healthKitEnabled))", category: .general)
        } else {
            Logger.debug("Watch not reachable, workout start saved to context", category: .general)
        }
    }
    
    /// Notify Watch to end the workout session
    public func sendWorkoutEnded() {
        // Clear heart rate when workout ends
        currentHeartRate = nil
        isWatchWorkoutSessionActive = false

        guard let session = session,
              session.activationState == .activated else {
            Logger.debug("Watch session not active, cannot send workout end", category: .general)
            return
        }

        // Always update application context (works even when unreachable)
        updateWorkoutContext(workoutActive: false)
        
        // Also try to send immediate message if reachable
        if session.isReachable {
            session.sendMessage(["type": "workoutEnded"], replyHandler: nil) { error in
                Logger.error("Failed to send workout end to Watch: \(error.localizedDescription)", category: .general)
            }
            Logger.debug("Sent workout end to Watch", category: .general)
        } else {
            Logger.debug("Watch not reachable, workout end saved to context", category: .general)
        }
    }
    
    /// Update application context with workout and timer state.
    /// This persists even when the Watch is unreachable and syncs when it wakes.
    ///
    /// The snapshot is self-describing and timestamp-independent: the timer is
    /// conveyed as an absolute `timerEndDate` (epoch seconds) plus the full
    /// `timerDuration`, so a Watch that wakes minutes later can compute the correct
    /// remaining time locally rather than trusting a stale, un-timestamped count.
    /// `updateApplicationContext` replaces the whole context each call, so every
    /// call re-includes `healthKitEnabled` from `lastHealthKitEnabled`.
    private func updateWorkoutContext(
        workoutActive: Bool,
        timerActive: Bool = false,
        timerEndDate: Date? = nil,
        timerDuration: Int = 0,
        timerRemaining: Int = 0,
        timerPaused: Bool = false,
        exerciseName: String = "",
        nextSetInfo: String? = nil
    ) {
        guard let session = session else { return }

        var context: [String: Any] = [
            "workoutActive": workoutActive,
            "healthKitEnabled": lastHealthKitEnabled,
            "timerActive": timerActive,
            "timerDuration": timerDuration,
            // Legacy fallback for a Watch build that doesn't understand endDate yet.
            "timerRemaining": timerRemaining,
            "timerPaused": timerPaused,
            "timerExerciseName": exerciseName
        ]
        if let timerEndDate = timerEndDate {
            context["timerEndDate"] = timerEndDate.timeIntervalSince1970
        }
        if let nextSetInfo = nextSetInfo {
            context["timerNextSetInfo"] = nextSetInfo
        }

        do {
            try session.updateApplicationContext(context)
        } catch {
            Logger.error("Failed to update application context: \(error.localizedDescription)", category: .general)
        }
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
    
    /// Send the authoritative, endDate-based rest-timer state to the Watch.
    ///
    /// This is the endDate-based replacement for the per-second `sendRestTimerUpdate`
    /// tick. Call it ONCE when the timer starts, and again ONLY when the timeline
    /// changes: on pause, resume, and ±15s adjust (and it's harmless to call on
    /// end, though `sendRestTimerEnded()` is preferred there). The Watch renders the
    /// countdown locally from `endDate` and schedules its own completion haptic, so
    /// no per-second traffic is needed and the countdown keeps running while the
    /// phone is backgrounded/locked.
    ///
    /// - Parameters:
    ///   - endDate: absolute time the timer fires (running) or `nil` when paused.
    ///   - duration: full planned duration in seconds (drives the progress ring).
    ///   - remaining: authoritative remaining seconds — used to render/freeze the
    ///     countdown while paused, and as a fallback if `endDate` is nil.
    ///   - isPaused: whether the timer is currently paused.
    ///   - exerciseName: current exercise name (for the Watch label).
    ///   - nextSetInfo: e.g. "Next: Set 3 of 5" (preserved across context restores).
    public func sendRestTimerState(
        endDate: Date?,
        duration: Int,
        remaining: Int,
        isPaused: Bool,
        exerciseName: String,
        nextSetInfo: String? = nil
    ) {
        guard let session = session,
              session.activationState == .activated else {
            return
        }

        // Always persist a self-describing snapshot (survives Watch sleep / unreachable).
        updateWorkoutContext(
            workoutActive: true,
            timerActive: true,
            timerEndDate: endDate,
            timerDuration: duration,
            timerRemaining: remaining,
            timerPaused: isPaused,
            exerciseName: exerciseName,
            nextSetInfo: nextSetInfo
        )

        // Send an immediate live message if reachable.
        if session.isReachable {
            var message: [String: Any] = [
                "type": "restTimerState",
                "duration": duration,
                "remaining": remaining,
                "isPaused": isPaused,
                "exerciseName": exerciseName
            ]
            if let endDate = endDate {
                message["endDate"] = endDate.timeIntervalSince1970
            }
            if let nextSetInfo = nextSetInfo {
                message["nextSetInfo"] = nextSetInfo
            }
            session.sendMessage(message, replyHandler: nil) { _ in
                // Silently fail - Watch will still recover from application context.
            }
        }
    }

    /// Legacy per-second rest-timer tick.
    ///
    /// Retained so existing call sites keep compiling and the Watch keeps working
    /// until the views are rewired to the endDate-based `sendRestTimerState(...)`.
    /// A modern Watch build derives its own end date from `remaining` (and renders
    /// locally); the application context is still only refreshed every ~5s to avoid
    /// hammering `updateApplicationContext`. Once the views adopt
    /// `sendRestTimerState`, remove the tick-loop calls to this method entirely.
    public func sendRestTimerUpdate(remaining: Int, duration: Int, exerciseName: String) {
        guard let session = session,
              session.activationState == .activated else {
            return
        }

        // Refresh the self-describing snapshot periodically so a waking Watch can
        // still recover. Derive an endDate so the snapshot stays endDate-based.
        if remaining % 5 == 0 || remaining <= 5 {
            updateWorkoutContext(
                workoutActive: true,
                timerActive: true,
                timerEndDate: remaining > 0 ? Date().addingTimeInterval(TimeInterval(remaining)) : nil,
                timerDuration: duration,
                timerRemaining: remaining,
                timerPaused: false,
                exerciseName: exerciseName
            )
        }

        // Send an immediate legacy message if reachable.
        if session.isReachable {
            session.sendMessage([
                "type": "restTimerUpdate",
                "remaining": remaining,
                "duration": duration,
                "exerciseName": exerciseName
            ], replyHandler: nil) { _ in
                // Silently fail
            }
        }
    }

    /// Send rest timer ended / cancelled notification to Watch
    public func sendRestTimerEnded() {
        guard let session = session,
              session.activationState == .activated else {
            return
        }

        // Always update application context (works even when unreachable)
        updateWorkoutContext(workoutActive: true, timerActive: false)

        // Also try to send immediate message if reachable
        if session.isReachable {
            session.sendMessage(["type": "restTimerEnded"], replyHandler: nil) { _ in
                // Silently fail
            }
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
            case "watchWorkoutSession":
                // The Watch reports whether it is running its own HealthKit-saving
                // workout, so the phone can skip writing a duplicate HK workout.
                if let active = message["active"] as? Bool {
                    self.isWatchWorkoutSessionActive = active
                }
            case "setCompleted":
                // Watch requested set completion - notify listener.
                // exerciseIndex/setNumber identify which set the Watch was showing
                // (absent on older Watch builds); the listener drops stale requests.
                let reps = message["reps"] as? Int
                let exerciseIndex = message["exerciseIndex"] as? Int
                let setNumber = message["setNumber"] as? Int
                Logger.debug("Received set completion request from Watch (reps: \(reps?.description ?? "nil"), exercise: \(exerciseIndex?.description ?? "nil"), set: \(setNumber?.description ?? "nil"))", category: .general)
                self.onSetCompletedFromWatch?(reps, exerciseIndex, setNumber)
            default:
                break
            }
        }
    }
}
