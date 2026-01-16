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
    var useMetric: Bool = false
    var nextSetInfo: String?
    var isRepOutSet: Bool = false
    
    init(
        exerciseName: String = "",
        currentSet: Int = 0,
        totalSets: Int = 0,
        weight: Double = 0,
        targetReps: Int = 0,
        isRestTimerActive: Bool = false,
        restTimerRemaining: Int = 0,
        restTimerDuration: Int = 0,
        useMetric: Bool = false,
        nextSetInfo: String? = nil,
        isRepOutSet: Bool = false
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
    
    /// Formatted timer string (MM:SS)
    var formattedTimerRemaining: String {
        let minutes = restTimerRemaining / 60
        let seconds = restTimerRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Timer progress (0.0 to 1.0)
    var timerProgress: Double {
        guard restTimerDuration > 0 else { return 0 }
        return Double(restTimerDuration - restTimerRemaining) / Double(restTimerDuration)
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
    
    /// Reference to WatchWorkoutManager for starting/ending workouts
    var workoutManager: WatchWorkoutManager? {
        didSet {
            setupHeartRateCallback()
            // Process any pending workout start that arrived before connection
            if pendingWorkoutStart {
                pendingWorkoutStart = false
                startWorkoutFromPhone()
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
    
    private func startWorkoutFromPhone() {
        isWorkoutActive = true
        Task {
            do {
                try await workoutManager?.startWorkout()
                WKInterfaceDevice.current().play(.start)
            } catch {
                Logger.error("Failed to start workout: \(error)", category: .healthKit)
            }
        }
    }
    
    private func endWorkoutFromPhone() {
        isWorkoutActive = false
        workoutState = WatchWorkoutStateData()  // Reset workout state
        
        // Also immediately tell the workout manager to mark itself inactive
        // (in case the async endWorkout() takes time or fails)
        workoutManager?.forceInactive()
        
        Task {
            do {
                try await workoutManager?.endWorkout()
                WKInterfaceDevice.current().play(.success)
            } catch {
                Logger.error("Failed to end workout: \(error)", category: .healthKit)
                // Still play a sound even if HealthKit fails
                WKInterfaceDevice.current().play(.success)
            }
        }
    }
    
    private func updateWorkoutState(from dict: [String: Any]) {
        // Replace the entire struct to ensure SwiftUI detects the change
        workoutState = WatchWorkoutStateData(
            exerciseName: dict["exerciseName"] as? String ?? "",
            currentSet: dict["currentSet"] as? Int ?? 0,
            totalSets: dict["totalSets"] as? Int ?? 0,
            weight: dict["weight"] as? Double ?? 0,
            targetReps: dict["targetReps"] as? Int ?? 0,
            isRestTimerActive: dict["isRestTimerActive"] as? Bool ?? false,
            restTimerRemaining: dict["restTimerRemaining"] as? Int ?? 0,
            restTimerDuration: dict["restTimerDuration"] as? Int ?? 0,
            useMetric: dict["useMetric"] as? Bool ?? false,
            nextSetInfo: dict["nextSetInfo"] as? String,
            isRepOutSet: dict["isRepOutSet"] as? Bool ?? false
        )
    }
    
    private func updateRestTimer(remaining: Int, duration: Int, exerciseName: String) {
        workoutState.restTimerRemaining = remaining
        workoutState.restTimerDuration = duration
        workoutState.isRestTimerActive = remaining > 0
        if !exerciseName.isEmpty {
            workoutState.exerciseName = exerciseName
        }
    }
    
    private func handleRestTimerEnded() {
        workoutState.isRestTimerActive = false
        workoutState.restTimerRemaining = 0
        WKInterfaceDevice.current().play(.notification)  // Haptic when timer ends
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
            if workoutActive && !isWorkoutActive {
                // Workout started while we were unreachable - start now
                if workoutManager != nil {
                    startWorkoutFromPhone()
                } else {
                    pendingWorkoutStart = true
                }
            } else if !workoutActive && isWorkoutActive {
                // Workout ended while we were unreachable - end now
                endWorkoutFromPhone()
            }
        }
        
        // Handle timer state (sync when Watch wakes up)
        if let timerActive = context["timerActive"] as? Bool {
            if timerActive {
                let remaining = context["timerRemaining"] as? Int ?? 0
                let duration = context["timerDuration"] as? Int ?? 0
                workoutState = WatchWorkoutStateData(
                    exerciseName: workoutState.exerciseName,
                    currentSet: workoutState.currentSet,
                    totalSets: workoutState.totalSets,
                    weight: workoutState.weight,
                    targetReps: workoutState.targetReps,
                    isRestTimerActive: true,
                    restTimerRemaining: remaining,
                    restTimerDuration: duration
                )
            } else if workoutState.isRestTimerActive {
                // Timer ended while we were unreachable
                workoutState = WatchWorkoutStateData(
                    exerciseName: workoutState.exerciseName,
                    currentSet: workoutState.currentSet,
                    totalSets: workoutState.totalSets,
                    weight: workoutState.weight,
                    targetReps: workoutState.targetReps,
                    isRestTimerActive: false,
                    restTimerRemaining: 0,
                    restTimerDuration: 0
                )
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
            if workoutManager != nil {
                startWorkoutFromPhone()
            } else {
                // Manager not connected yet, queue the start for when it connects
                pendingWorkoutStart = true
            }
            
        case "workoutEnded":
            // End workout session on Watch
            pendingWorkoutStart = false  // Cancel any pending start
            endWorkoutFromPhone()
            
        case "workoutState":
            // Update workout state from iPhone
            if let stateDict = message["state"] as? [String: Any] {
                updateWorkoutState(from: stateDict)
            }
            
        case "restTimerUpdate":
            // Update rest timer
            let remaining = message["remaining"] as? Int ?? 0
            let duration = message["duration"] as? Int ?? 0
            let exerciseName = message["exerciseName"] as? String ?? ""
            updateRestTimer(remaining: remaining, duration: duration, exerciseName: exerciseName)
            
        case "restTimerEnded":
            // Timer finished - play haptic
            handleRestTimerEnded()
            
        default:
            break
        }
    }
}
