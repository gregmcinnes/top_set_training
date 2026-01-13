import Foundation
import WatchConnectivity
import WatchKit

// MARK: - Watch Session Manager

/// Manages Watch Connectivity on the Watch side
/// Listens for workout start/end signals from iPhone to trigger heart rate collection
@MainActor
class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    @Published var isPhoneReachable = false
    @Published var isWorkoutActive = false
    
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
                print("Failed to start workout: \(error)")
            }
        }
    }
    
    private func endWorkoutFromPhone() {
        isWorkoutActive = false
        Task {
            do {
                try await workoutManager?.endWorkout()
                WKInterfaceDevice.current().play(.success)
            } catch {
                print("Failed to end workout: \(error)")
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
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
            
        default:
            break
        }
    }
}
