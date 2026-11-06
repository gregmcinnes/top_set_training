import Foundation
import WatchConnectivity
import WatchKit

// MARK: - Watch Workout State (Mirror of iOS WatchWorkoutState)

/// Workout state received from iPhone
struct WatchWorkoutStateData {
    var exerciseName: String = ""
    var currentSet: Int = 0
    var totalSets: Int = 0
    var weight: Double = 0
    var targetReps: Int = 0
    var isRestTimerActive: Bool = false
    var restTimerRemaining: Int = 0
    var restTimerDuration: Int = 0
    /// Absolute time the rest timer fires. When set (and not paused), the Watch
    /// renders the countdown locally from this so it keeps ticking while the phone
    /// is backgrounded/locked. `nil` while paused or when only a legacy remaining
    /// value is available.
    var restTimerEndDate: Date?
    /// Whether the rest timer is currently paused (frozen at `restTimerRemaining`).
    var isPaused: Bool = false
    var useMetric: Bool = false
    var nextSetInfo: String?
    var isRepOutSet: Bool = false  // Volume program rep-out set
    var isAMRAPSet: Bool = false   // Any AMRAP set (volume or structured)
    var exerciseIndex: Int = 0     // Index of current exercise (for set-completion identity)

    init(
        exerciseName: String = "",
        currentSet: Int = 0,
        totalSets: Int = 0,
        weight: Double = 0,
        targetReps: Int = 0,
        isRestTimerActive: Bool = false,
        restTimerRemaining: Int = 0,
        restTimerDuration: Int = 0,
        restTimerEndDate: Date? = nil,
        isPaused: Bool = false,
        useMetric: Bool = false,
        nextSetInfo: String? = nil,
        isRepOutSet: Bool = false,
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
        self.restTimerEndDate = restTimerEndDate
        self.isPaused = isPaused
        self.useMetric = useMetric
        self.nextSetInfo = nextSetInfo
        self.isRepOutSet = isRepOutSet
        self.isAMRAPSet = isAMRAPSet
        self.exerciseIndex = exerciseIndex
    }
    
    /// Formatted weight string
    var formattedWeight: String {
        if useMetric {
            let kg = weight * 0.453592
            if kg.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(kg)) kg"
            }
            return String(format: "%.1f kg", kg)
        } else {
            if weight.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(weight)) lb"
            }
            return String(format: "%.1f lb", weight)
        }
    }
    
    /// Live remaining seconds at a given instant. When an `restTimerEndDate` is
    /// present and the timer isn't paused, this is computed locally from the end
    /// date so the countdown advances even while the phone is asleep; otherwise it
    /// falls back to the last pushed `restTimerRemaining` (paused / legacy).
    func remaining(at now: Date = Date()) -> Int {
        if let endDate = restTimerEndDate, !isPaused {
            return max(0, Int(ceil(endDate.timeIntervalSince(now))))
        }
        return restTimerRemaining
    }

    /// Formatted timer string (MM:SS) at a given instant.
    func formattedTimerRemaining(at now: Date = Date()) -> String {
        let value = remaining(at: now)
        let minutes = value / 60
        let seconds = value % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formatted timer string (MM:SS) — snapshot using the current time.
    var formattedTimerRemaining: String {
        formattedTimerRemaining(at: Date())
    }

    /// Timer progress (0.0 to 1.0) at a given instant.
    func timerProgress(at now: Date = Date()) -> Double {
        guard restTimerDuration > 0 else { return 0 }
        let value = remaining(at: now)
        return Double(restTimerDuration - value) / Double(restTimerDuration)
    }

    /// Timer progress (0.0 to 1.0) — snapshot using the current time.
    var timerProgress: Double {
        timerProgress(at: Date())
    }
}

// MARK: - Watch Session Manager

/// Manages Watch Connectivity on the Watch side
/// Listens for workout start/end signals from iPhone to trigger heart rate collection
@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    @Published var isPhoneReachable = false
    @Published var isWorkoutActive = false
    @Published var workoutState = WatchWorkoutStateData()
    
    private var session: WCSession?
    private var lastHeartRateSent: Double = 0
    private var pendingWorkoutStart = false  // Track if we received a start before manager was connected
    private var pendingHealthKitEnabled = false  // HealthKit flag captured with a pending start
    private var pendingWorkoutId: String?  // Workout id captured with a pending start

    /// Phone-assigned id of the workout running here (nil on older phone builds).
    private var currentWorkoutId: String?
    /// In-flight end of the previous workout; a following start waits for it.
    private var endWorkoutTask: Task<Void, Never>?

    /// Id of a workout the user ended from the Watch. The phone's context keeps
    /// saying that workout is active, and it replays on every wake, so this stops
    /// it from restarting. Persisted because the context outlives this process.
    private static let endedWorkoutIdKey = "watch.endedWorkoutId"
    /// Stands in for the id when an older phone build doesn't send one.
    private static let unidentifiedWorkoutId = "unidentified"

    /// Local task that fires the rest-timer completion haptic at the timer's end
    /// date, so the buzz arrives even when the phone is backgrounded/asleep.
    private var restEndHapticTask: Task<Void, Never>?
    /// Whether the local completion haptic already fired for the current timer, so a
    /// subsequent "restTimerEnded" from the phone doesn't double-buzz.
    private var restEndHapticFired = false
    
    /// Reference to WatchWorkoutManager for starting/ending workouts
    var workoutManager: WatchWorkoutManager? {
        didSet {
            setupHeartRateCallback()
            workoutManager?.onHealthKitSessionFailed = { [weak self] in
                self?.sendWatchWorkoutSessionState(active: false, watchSaved: false, workoutId: self?.currentWorkoutId)
            }
            // Process any pending workout start that arrived before connection
            if pendingWorkoutStart {
                pendingWorkoutStart = false
                startWorkoutFromPhone(healthKitEnabled: pendingHealthKitEnabled, workoutId: pendingWorkoutId)
            }
        }
    }
    
    private override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        guard WCSession.isSupported() else { return }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    private func setupHeartRateCallback() {
        workoutManager?.onHeartRateUpdate = { [weak self] heartRate in
            self?.sendHeartRateToPhone(heartRate)
        }
    }
    
    /// Send heart rate update to iPhone (throttled to avoid overwhelming connection)
    private func sendHeartRateToPhone(_ heartRate: Double) {
        // Only send if changed by at least 1 BPM to reduce message frequency
        guard abs(heartRate - lastHeartRateSent) >= 1.0 else { return }
        
        guard let session = session,
              session.activationState == .activated,
              session.isReachable else { return }
        
        lastHeartRateSent = heartRate
        
        session.sendMessage(
            ["type": "heartRateUpdate", "heartRate": heartRate],
            replyHandler: nil
        ) { error in
            // Silently fail - heart rate updates are best-effort
        }
    }
    
    /// Send set completed action to iPhone
    /// This triggers set completion on the iPhone, which then syncs updated state back
    /// - Parameter reps: Optional rep count for AMRAP sets. If nil, uses target reps.
    func sendSetCompleted(reps: Int?) {
        guard let session = session,
              session.activationState == .activated,
              session.isReachable else {
            // Haptic feedback to indicate the action couldn't be sent
            WKInterfaceDevice.current().play(.failure)
            return
        }
        
        var message: [String: Any] = ["type": "setCompleted"]
        if let reps = reps {
            message["reps"] = reps
        }
        // Stamp the set the Watch is showing so the phone can drop this request
        // if it has already advanced past it (prevents completing the wrong set).
        message["exerciseIndex"] = workoutState.exerciseIndex
        message["setNumber"] = workoutState.currentSet
        
        session.sendMessage(message, replyHandler: nil) { error in
            Task { @MainActor in
                // Play failure haptic if message couldn't be sent
                WKInterfaceDevice.current().play(.failure)
            }
        }
        
        // Play success haptic immediately (optimistic feedback)
        WKInterfaceDevice.current().play(.click)
    }
    
    /// Route a "workout is running" signal from the phone, from either the live
    /// message or the context (which also replays on wake). Starts the workout if
    /// it's new here; a repeat for the running workout changes nothing.
    private func handleWorkoutActive(healthKitEnabled: Bool, workoutId: String?) {
        if isWorkoutActive {
            // A different id means this one's end never reached us (the phone was
            // killed and relaunched, or the context coalesced). Don't merge them.
            guard let workoutId, let currentWorkoutId, workoutId != currentWorkoutId else { return }
            finishLocalWorkout(save: true, reportWatchSaved: false)
        }

        if UserDefaults.standard.string(forKey: Self.endedWorkoutIdKey) == (workoutId ?? Self.unidentifiedWorkoutId) {
            return  // The user already ended this one from the Watch.
        }

        if workoutManager != nil {
            startWorkoutFromPhone(healthKitEnabled: healthKitEnabled, workoutId: workoutId)
        } else {
            // Manager not connected yet, queue the start for when it connects
            pendingWorkoutStart = true
            pendingHealthKitEnabled = healthKitEnabled
            pendingWorkoutId = workoutId
        }
    }

    private func startWorkoutFromPhone(healthKitEnabled: Bool, workoutId: String?) {
        isWorkoutActive = true
        currentWorkoutId = workoutId
        let previousEnd = endWorkoutTask
        Task {
            // The manager refuses to start while the previous session is finishing.
            await previousEnd?.value

            // startWorkout(saveToHealthKit:) handles its own errors and always
            // leaves the workout usable (falling back to non-HealthKit tracking if
            // HealthKit auth fails), so the UI never gets stuck "Connecting…".
            await workoutManager?.startWorkout(saveToHealthKit: healthKitEnabled)

            // Ended while HealthKit was starting: nothing else will stop this session.
            guard isWorkoutActive else {
                _ = try? await workoutManager?.endWorkout(save: false)
                return
            }
            WKInterfaceDevice.current().play(.start)

            // Tell the phone whether the Watch is saving its own HealthKit workout,
            // so the phone can skip writing a duplicate.
            let saving = (workoutManager?.isSavingToHealthKit ?? false)
            sendWatchWorkoutSessionState(active: saving, watchSaved: false, workoutId: workoutId)
        }
    }

    /// Report to the phone whether the Watch owns the HealthKit workout. Uses the
    /// application context as well as a live message: the phone deciding who saves
    /// depends on this, so it can't rest on one message that needs reachability.
    private func sendWatchWorkoutSessionState(active: Bool, watchSaved: Bool, workoutId: String?) {
        guard let session = session,
              session.activationState == .activated else { return }

        var context: [String: Any] = ["watchSessionActive": active, "watchSaved": watchSaved]
        var message: [String: Any] = ["type": "watchWorkoutSession", "active": active, "watchSaved": watchSaved]
        if let workoutId = workoutId {
            context["workoutId"] = workoutId
            message["workoutId"] = workoutId
        }

        do {
            try session.updateApplicationContext(context)
        } catch {
            Logger.error("Failed to update Watch session context: \(error)", category: .general)
        }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                // The context above still delivers it.
            }
        }
    }

    /// The phone ended the workout.
    /// - Parameters:
    ///   - saveWorkout: false when the user chose not to save it.
    ///   - phoneWillSave: the phone is saving its own copy, so saving here too
    ///     would write a duplicate.
    ///   - abandoned: the phone app was killed mid-workout and only noticed on relaunch,
    ///     so the session may have run on for hours with nobody training.
    private func endWorkoutFromPhone(saveWorkout: Bool = true, phoneWillSave: Bool = false, abandoned: Bool = false) {
        finishLocalWorkout(save: saveWorkout && !phoneWillSave, reportWatchSaved: false, abandoned: abandoned)
    }

    /// End Workout button on the Watch: the only way out when the phone is gone,
    /// or for a session the phone has lost track of.
    func endWorkoutFromWatch(save: Bool) {
        UserDefaults.standard.set(currentWorkoutId ?? Self.unidentifiedWorkoutId, forKey: Self.endedWorkoutIdKey)
        finishLocalWorkout(save: save, reportWatchSaved: true)
    }

    private func finishLocalWorkout(save: Bool, reportWatchSaved: Bool, abandoned: Bool = false) {
        let workoutId = currentWorkoutId
        isWorkoutActive = false
        currentWorkoutId = nil
        cancelRestEndHaptic()
        workoutState = WatchWorkoutStateData()  // Reset workout state

        // Also immediately tell the workout manager to mark itself inactive
        // (in case the async endWorkout() takes time or fails)
        workoutManager?.forceInactive()

        let previousEnd = endWorkoutTask
        endWorkoutTask = Task {
            await previousEnd?.value
            var saved = false
            do {
                saved = try await workoutManager?.endWorkout(save: save, abandoned: abandoned) ?? false
            } catch {
                Logger.error("Failed to end workout: \(error)", category: .healthKit)
            }
            // Report only once the outcome is known: the phone discards its own copy
            // on watchSaved, so claiming a save that then failed would lose the workout.
            sendWatchWorkoutSessionState(active: false, watchSaved: reportWatchSaved && saved, workoutId: workoutId)
            // Still play a sound even if HealthKit fails
            WKInterfaceDevice.current().play(.success)
        }
    }
    
    private func updateWorkoutState(from dict: [String: Any]) {
        let isRestTimerActive = dict["isRestTimerActive"] as? Bool ?? false
        // The full-state message doesn't carry the timer's endDate/paused flag
        // (those are owned by the restTimerState messages). Preserve the locally
        // tracked endDate/paused while the timer is active so the local countdown
        // and scheduled haptic aren't clobbered by an interleaved state sync.
        var preservedEndDate = isRestTimerActive ? workoutState.restTimerEndDate : nil
        let preservedPaused = isRestTimerActive ? workoutState.isPaused : false
        let remainingFromPhone = dict["restTimerRemaining"] as? Int ?? 0

        // The phone reports a paused timer as not running in this message. Only the
        // restTimerState / restTimerEnded messages may clear a pause.
        let keepPausedTimer = !isRestTimerActive && workoutState.isRestTimerActive && workoutState.isPaused
        let pausedRemaining = workoutState.restTimerRemaining

        // Running on the phone but no end date here (this Watch joined mid-rest, or
        // the restTimerState message was missed): derive one so the countdown runs
        // rather than sitting frozen on the phone's number.
        let derivedEndDate = isRestTimerActive && !preservedPaused && preservedEndDate == nil && remainingFromPhone > 0
        if derivedEndDate {
            preservedEndDate = Date().addingTimeInterval(TimeInterval(remainingFromPhone))
        }

        // Replace the entire struct to ensure SwiftUI detects the change
        workoutState = WatchWorkoutStateData(
            exerciseName: dict["exerciseName"] as? String ?? "",
            currentSet: dict["currentSet"] as? Int ?? 0,
            totalSets: dict["totalSets"] as? Int ?? 0,
            weight: dict["weight"] as? Double ?? 0,
            targetReps: dict["targetReps"] as? Int ?? 0,
            isRestTimerActive: isRestTimerActive || keepPausedTimer,
            restTimerRemaining: keepPausedTimer ? pausedRemaining : remainingFromPhone,
            restTimerDuration: dict["restTimerDuration"] as? Int ?? 0,
            restTimerEndDate: preservedEndDate,
            isPaused: preservedPaused || keepPausedTimer,
            useMetric: dict["useMetric"] as? Bool ?? false,
            nextSetInfo: dict["nextSetInfo"] as? String,
            isRepOutSet: dict["isRepOutSet"] as? Bool ?? false,
            isAMRAPSet: dict["isAMRAPSet"] as? Bool ?? false,
            exerciseIndex: dict["exerciseIndex"] as? Int ?? 0
        )
        if !isRestTimerActive {
            cancelRestEndHaptic()
        } else if derivedEndDate, let endDate = preservedEndDate {
            scheduleRestEndHaptic(at: endDate)
        }
    }
    
    /// Apply an endDate-based rest-timer state. The Watch renders the countdown
    /// locally from `endDate` (see `WatchWorkoutStateData.remaining(at:)`) and
    /// schedules its own completion haptic, so it keeps ticking and buzzes on time
    /// even while the phone is backgrounded/locked.
    private func applyRestTimerState(
        endDate: Date?,
        duration: Int,
        remaining: Int,
        isPaused: Bool,
        exerciseName: String,
        nextSetInfo: String?
    ) {
        workoutState.restTimerEndDate = endDate
        workoutState.restTimerDuration = duration
        workoutState.restTimerRemaining = remaining
        workoutState.isPaused = isPaused
        // Active if paused with time on the clock, or running toward a future end /
        // a positive remaining fallback.
        workoutState.isRestTimerActive = isPaused ? remaining > 0 : (endDate != nil || remaining > 0)
        if !exerciseName.isEmpty {
            workoutState.exerciseName = exerciseName
        }
        if let nextSetInfo = nextSetInfo {
            workoutState.nextSetInfo = nextSetInfo
        }

        // Schedule / cancel the local completion haptic.
        if let endDate = endDate, !isPaused {
            scheduleRestEndHaptic(at: endDate)
        } else {
            cancelRestEndHaptic()
        }
    }

    /// Legacy per-second update (older phone builds). Derives an end date so the
    /// Watch still renders and buzzes locally.
    private func updateRestTimer(remaining: Int, duration: Int, exerciseName: String) {
        applyRestTimerState(
            endDate: remaining > 0 ? Date().addingTimeInterval(TimeInterval(remaining)) : nil,
            duration: duration,
            remaining: remaining,
            isPaused: false,
            exerciseName: exerciseName,
            nextSetInfo: nil
        )
    }

    private func handleRestTimerEnded() {
        // If the local haptic already fired at the end date, don't double-buzz;
        // otherwise (early skip, legacy path, or message beat the local timer) buzz
        // now. Either way clear the timer state and stop the pending local haptic.
        if !restEndHapticFired {
            WKInterfaceDevice.current().play(.notification)
        }
        cancelRestEndHaptic()
        workoutState.isRestTimerActive = false
        workoutState.isPaused = false
        workoutState.restTimerRemaining = 0
        workoutState.restTimerEndDate = nil
    }

    /// Schedule a local haptic to fire at `endDate`.
    private func scheduleRestEndHaptic(at endDate: Date) {
        cancelRestEndHaptic()
        restEndHapticFired = false

        let interval = endDate.timeIntervalSinceNow
        guard interval > 0 else {
            // Already expired — buzz immediately.
            restEndHapticFired = true
            WKInterfaceDevice.current().play(.notification)
            workoutState.isRestTimerActive = false
            workoutState.restTimerRemaining = 0
            return
        }

        restEndHapticTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = self else { return }
                self.restEndHapticFired = true
                WKInterfaceDevice.current().play(.notification)
                self.workoutState.isRestTimerActive = false
                self.workoutState.restTimerRemaining = 0
                self.workoutState.restTimerEndDate = nil
            }
        }
    }

    private func cancelRestEndHaptic() {
        restEndHapticTask?.cancel()
        restEndHapticTask = nil
    }
    
    /// Manually sync from current application context
    /// Called when app becomes active to ensure state is up to date
    func syncFromApplicationContext() {
        guard let session = session else { return }
        handleApplicationContext(session.receivedApplicationContext)
    }
    
    /// Handle application context received from iPhone
    /// This is used when the Watch wasn't reachable when state changed
    @MainActor
    private func handleApplicationContext(_ context: [String: Any]) {
        // Handle workout state
        if let workoutActive = context["workoutActive"] as? Bool {
            if workoutActive {
                // Workout started while we were unreachable - start now
                handleWorkoutActive(
                    healthKitEnabled: context["healthKitEnabled"] as? Bool ?? false,
                    workoutId: context["workoutId"] as? String
                )
            } else {
                pendingWorkoutStart = false  // Cancel any pending start
                UserDefaults.standard.removeObject(forKey: Self.endedWorkoutIdKey)
                if isWorkoutActive {
                    // Workout ended while we were unreachable - end now
                    endWorkoutFromPhone(
                        saveWorkout: context["saveWorkout"] as? Bool ?? true,
                        phoneWillSave: context["phoneWillSave"] as? Bool ?? false,
                        abandoned: context["abandoned"] as? Bool ?? false
                    )
                }
            }
        }

        // A workout the user ended from the Watch: its timer is no longer shown here.
        guard isWorkoutActive || pendingWorkoutStart else { return }

        // Handle timer state (sync when Watch wakes up). The snapshot is
        // self-describing: an absolute `timerEndDate` lets the Watch compute the
        // correct remaining time locally regardless of how long it slept.
        // nextSetInfo / isRepOutSet / isAMRAPSet on the existing state are preserved.
        if let timerActive = context["timerActive"] as? Bool {
            if timerActive {
                let duration = context["timerDuration"] as? Int ?? 0
                let isPaused = context["timerPaused"] as? Bool ?? false
                let endDate: Date? = {
                    guard let epoch = context["timerEndDate"] as? Double else { return nil }
                    return Date(timeIntervalSince1970: epoch)
                }()
                // Prefer the live endDate; fall back to the legacy remaining value.
                let remaining = context["timerRemaining"] as? Int ?? 0
                let exerciseName = context["timerExerciseName"] as? String ?? workoutState.exerciseName
                let nextSetInfo = context["timerNextSetInfo"] as? String ?? workoutState.nextSetInfo

                // This context replays every time the app wakes. A rest that already
                // finished gets cleared quietly: buzzing here would repeat on each
                // wake, and the local haptic has had its chance to fire on time.
                if !isPaused, let endDate = endDate, endDate <= Date() {
                    cancelRestEndHaptic()
                    workoutState.isRestTimerActive = false
                    workoutState.isPaused = false
                    workoutState.restTimerRemaining = 0
                    workoutState.restTimerEndDate = nil
                    return
                }

                // applyRestTimerState mutates workoutState in place, so the other
                // displayed fields (isRepOutSet / isAMRAPSet / set counts) survive.
                applyRestTimerState(
                    endDate: isPaused ? nil : endDate,
                    duration: duration,
                    remaining: remaining,
                    isPaused: isPaused,
                    exerciseName: exerciseName,
                    nextSetInfo: nextSetInfo
                )
            } else if workoutState.isRestTimerActive {
                // Timer ended while we were unreachable - clear silently (no late buzz).
                cancelRestEndHaptic()
                workoutState.isRestTimerActive = false
                workoutState.isPaused = false
                workoutState.restTimerRemaining = 0
                workoutState.restTimerEndDate = nil
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            // Check application context on activation (in case we missed messages while inactive)
            self.handleApplicationContext(session.receivedApplicationContext)
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            self.handleMessage(message)
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            self.handleApplicationContext(applicationContext)
        }
    }
    
    @MainActor
    private func handleMessage(_ message: [String: Any]) {
        
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "workoutStarted":
            // Start workout session on Watch for heart rate collection
            handleWorkoutActive(
                healthKitEnabled: message["healthKitEnabled"] as? Bool ?? false,
                workoutId: message["workoutId"] as? String
            )

        case "workoutEnded":
            // End workout session on Watch
            pendingWorkoutStart = false  // Cancel any pending start
            UserDefaults.standard.removeObject(forKey: Self.endedWorkoutIdKey)
            // The context carries the same signal, so this can arrive second.
            if isWorkoutActive {
                endWorkoutFromPhone(
                    saveWorkout: message["saveWorkout"] as? Bool ?? true,
                    phoneWillSave: message["phoneWillSave"] as? Bool ?? false
                )
            }

        case "workoutState":
            // Update workout state from iPhone
            if let stateDict = message["state"] as? [String: Any] {
                updateWorkoutState(from: stateDict)
            }

        case "restTimerState":
            // endDate-based rest timer state (start / pause / resume / adjust).
            let duration = message["duration"] as? Int ?? 0
            let remaining = message["remaining"] as? Int ?? 0
            let isPaused = message["isPaused"] as? Bool ?? false
            let exerciseName = message["exerciseName"] as? String ?? ""
            let nextSetInfo = message["nextSetInfo"] as? String
            let endDate: Date? = {
                guard let epoch = message["endDate"] as? Double else { return nil }
                return Date(timeIntervalSince1970: epoch)
            }()
            applyRestTimerState(
                endDate: isPaused ? nil : endDate,
                duration: duration,
                remaining: remaining,
                isPaused: isPaused,
                exerciseName: exerciseName,
                nextSetInfo: nextSetInfo
            )

        case "restTimerUpdate":
            // Legacy per-second update (older phone builds).
            let remaining = message["remaining"] as? Int ?? 0
            let duration = message["duration"] as? Int ?? 0
            let exerciseName = message["exerciseName"] as? String ?? ""
            updateRestTimer(remaining: remaining, duration: duration, exerciseName: exerciseName)

        case "restTimerEnded":
            // Timer finished / cancelled.
            handleRestTimerEnded()

        default:
            break
        }
    }
}
