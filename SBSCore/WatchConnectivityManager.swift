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
    /// The active workout session sets this, so it fires while minimized too
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

    /// Identity of the workout currently running on the phone (nil when idle).
    /// Set once per workout, so a repeat `sendWorkoutStarted` is a no-op; also sent
    /// to the Watch so it can tell a new workout from a replay of the current one.
    private var currentWorkoutId: String?

    /// Latest rest-timer state. `updateApplicationContext` replaces the whole
    /// context, so every write re-includes this rather than implicitly clearing
    /// the Watch's running timer.
    private struct TimerSnapshot {
        var endDate: Date?
        var duration: Int
        var remaining: Int
        var isPaused: Bool
        var exerciseName: String
        var nextSetInfo: String?
    }
    private var timerSnapshot: TimerSnapshot?

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

        // Idempotent for a running workout: returning to the workout tab must not
        // restart anything on the Watch or disturb its rest timer.
        if currentWorkoutId != nil {
            updateWorkoutContext(workoutActive: true)
            return
        }

        currentWorkoutId = UUID().uuidString
        isWatchWorkoutSessionActive = false
        timerSnapshot = nil
        deliverWorkoutStart()
    }

    /// The id of the workout running on the phone, saved with the session so a
    /// relaunch can continue it with `resumeWorkout`.
    public var activeWorkoutId: String? { currentWorkoutId }

    /// Continue a workout from before an app kill. Using the same id means the Watch
    /// treats this as a replay of the workout it's already running, and carries on.
    public func resumeWorkout(id: String, healthKitEnabled: Bool) {
        lastHealthKitEnabled = healthKitEnabled
        currentWorkoutId = id
        deliverWorkoutStart()
        recoverWatchSessionState()
    }

    /// The Watch reported whether it owns the HealthKit workout to the process that was
    /// killed. Its last report stays in the received context, so read it from there.
    private func recoverWatchSessionState() {
        guard let context = session?.receivedApplicationContext,
              let active = context["watchSessionActive"] as? Bool else { return }
        applyWatchSessionState(
            active: active,
            watchSaved: context["watchSaved"] as? Bool ?? false,
            workoutId: context["workoutId"] as? String
        )
    }

    /// Tell the Watch a workout from a killed process is over, unless one is running
    /// now. Runs at launch once any saved session has been resolved.
    public func endAbandonedWorkoutIfIdle() {
        guard currentWorkoutId == nil,
              let session = session,
              session.activationState == .activated,
              session.applicationContext["workoutActive"] as? Bool == true else { return }
        Logger.debug("Clearing stale active workout left in Watch context", category: .general)
        updateWorkoutContext(workoutActive: false, abandoned: true)
    }

    /// Push the current workout's start to the Watch. Also runs from activation
    /// when the workout began before WCSession finished activating.
    private func deliverWorkoutStart() {
        guard let session = session,
              session.activationState == .activated else {
            Logger.debug("Watch session not active yet, workout start will send on activation", category: .general)
            return
        }

        // Always update application context (works even when unreachable)
        updateWorkoutContext(workoutActive: true)

        // Also try to send immediate message if reachable
        if session.isReachable {
            var message: [String: Any] = ["type": "workoutStarted", "healthKitEnabled": lastHealthKitEnabled]
            if let currentWorkoutId = currentWorkoutId {
                message["workoutId"] = currentWorkoutId
            }
            session.sendMessage(message, replyHandler: nil) { error in
                Logger.error("Failed to send workout start to Watch: \(error.localizedDescription)", category: .general)
            }
            Logger.debug("Sent workout start to Watch (healthKitEnabled: \(lastHealthKitEnabled))", category: .general)
        } else {
            Logger.debug("Watch not reachable, workout start saved to context", category: .general)
        }
    }
    
    /// Notify Watch to end the workout session
    /// - Parameter saveWorkout: `false` means the Watch discards its HealthKit
    ///   workout instead of saving it (e.g. the user chose "Don't Save").
    public func sendWorkoutEnded(saveWorkout: Bool = true) {
        // Who saves is decided here: if the phone never learned the Watch owns the
        // workout (a lost or late session-state message) it will save its own
        // builder, so tell the Watch to discard rather than write a duplicate.
        let phoneWillSave = saveWorkout && !isWatchWorkoutSessionActive && HealthKitManager.shared.isWorkoutActive

        // Clear heart rate when workout ends
        currentHeartRate = nil
        isWatchWorkoutSessionActive = false
        currentWorkoutId = nil
        timerSnapshot = nil

        guard let session = session,
              session.activationState == .activated else {
            Logger.debug("Watch session not active, cannot send workout end", category: .general)
            return
        }

        // Always update application context (works even when unreachable)
        updateWorkoutContext(workoutActive: false, saveWorkout: saveWorkout, phoneWillSave: phoneWillSave)
        
        // Also try to send immediate message if reachable
        if session.isReachable {
            let message: [String: Any] = ["type": "workoutEnded", "saveWorkout": saveWorkout, "phoneWillSave": phoneWillSave]
            session.sendMessage(message, replyHandler: nil) { error in
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
    /// call re-includes `healthKitEnabled` and the current `timerSnapshot`.
    private func updateWorkoutContext(
        workoutActive: Bool,
        saveWorkout: Bool = true,
        phoneWillSave: Bool = false,
        abandoned: Bool = false
    ) {
        guard let session = session else { return }

        let timer = timerSnapshot
        var context: [String: Any] = [
            "workoutActive": workoutActive,
            "healthKitEnabled": lastHealthKitEnabled,
            "saveWorkout": saveWorkout,
            "phoneWillSave": phoneWillSave,
            "abandoned": abandoned,
            "timerActive": timer != nil,
            "timerDuration": timer?.duration ?? 0,
            // Legacy fallback for a Watch build that doesn't understand endDate yet.
            "timerRemaining": timer?.remaining ?? 0,
            "timerPaused": timer?.isPaused ?? false,
            "timerExerciseName": timer?.exerciseName ?? ""
        ]
        if let currentWorkoutId = currentWorkoutId {
            context["workoutId"] = currentWorkoutId
        }
        if let timerEndDate = timer?.endDate {
            context["timerEndDate"] = timerEndDate.timeIntervalSince1970
        }
        if let nextSetInfo = timer?.nextSetInfo {
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
        timerSnapshot = TimerSnapshot(
            endDate: endDate,
            duration: duration,
            remaining: remaining,
            isPaused: isPaused,
            exerciseName: exerciseName,
            nextSetInfo: nextSetInfo
        )

        guard let session = session,
              session.activationState == .activated else {
            return
        }

        // Always persist a self-describing snapshot (survives Watch sleep / unreachable).
        updateWorkoutContext(workoutActive: true)

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
        // Derive an endDate so the snapshot stays endDate-based.
        timerSnapshot = TimerSnapshot(
            endDate: remaining > 0 ? Date().addingTimeInterval(TimeInterval(remaining)) : nil,
            duration: duration,
            remaining: remaining,
            isPaused: false,
            exerciseName: exerciseName,
            nextSetInfo: nil
        )

        guard let session = session,
              session.activationState == .activated else {
            return
        }

        // Refresh the self-describing snapshot periodically so a waking Watch can
        // still recover.
        if remaining % 5 == 0 || remaining <= 5 {
            updateWorkoutContext(workoutActive: true)
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
        timerSnapshot = nil

        guard let session = session,
              session.activationState == .activated else {
            return
        }

        // Always update application context (works even when unreachable)
        updateWorkoutContext(workoutActive: true)

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
                self.reconcileAfterActivation(session)
            }
        }
    }

    /// Runs once WCSession is usable. Sends a start that was requested before
    /// activation; otherwise, if the persisted context still says a workout is
    /// running, this process has none (the app was killed mid-workout) — tell the
    /// Watch so its session doesn't run on with nothing to stop it. Not if there's a
    /// saved session, though: that workout is about to resume with the same id.
    private func reconcileAfterActivation(_ session: WCSession) {
        if currentWorkoutId != nil {
            deliverWorkoutStart()
            recoverWatchSessionState()
        } else if ProgramPersistence().loadActiveWorkoutSession() == nil {
            endAbandonedWorkoutIfIdle()
        }
    }

    /// Apply the Watch's report of whether it owns the HealthKit workout.
    /// A report for another workout (or none running) is stale and ignored; older
    /// Watch builds send no id. `watchSaved` means the Watch was ended from its own
    /// End button and already saved, so it stays the owner and the phone must not
    /// write a second, overlapping workout.
    private func applyWatchSessionState(active: Bool, watchSaved: Bool, workoutId: String?) {
        guard currentWorkoutId != nil else { return }
        if let workoutId = workoutId, workoutId != currentWorkoutId { return }
        isWatchWorkoutSessionActive = active || watchSaved
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
                    self.applyWatchSessionState(
                        active: active,
                        watchSaved: message["watchSaved"] as? Bool ?? false,
                        workoutId: message["workoutId"] as? String
                    )
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

    // Same state as the "watchWorkoutSession" message, but delivered even when the
    // Watch and phone aren't mutually reachable at that moment.
    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            guard let active = applicationContext["watchSessionActive"] as? Bool else { return }
            self.applyWatchSessionState(
                active: active,
                watchSaved: applicationContext["watchSaved"] as? Bool ?? false,
                workoutId: applicationContext["workoutId"] as? String
            )
        }
    }
}
