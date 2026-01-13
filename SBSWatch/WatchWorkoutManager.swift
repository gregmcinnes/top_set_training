import Foundation
import HealthKit
import Combine

/// Manages workout sessions on Apple Watch with full HKWorkoutSession support
@MainActor
class WatchWorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    
    // Published state
    @Published var isWorkoutActive = false
    @Published var isAuthorized = false
    @Published var currentHeartRate: Double?
    @Published var workoutDuration: TimeInterval = 0
    
    // Callback for heart rate updates (to send to iPhone)
    var onHeartRateUpdate: ((Double) -> Void)?
    
    // Timer for duration updates
    private var durationTimer: Timer?
    private var workoutStartDate: Date?
    
    var formattedDuration: String {
        let hours = Int(workoutDuration) / 3600
        let minutes = (Int(workoutDuration) % 3600) / 60
        let seconds = Int(workoutDuration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    override init() {
        super.init()
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    private func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            isAuthorized = false
            return
        }
        
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        isAuthorized = status == .sharingAuthorized
    }
    
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WatchWorkoutError.healthKitNotAvailable
        }
        
        // Types we want to share (write)
        // Must include heart rate and active energy for HKLiveWorkoutDataSource to save samples
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
        
        // Types we want to read
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
        
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        checkAuthorizationStatus()
    }
    
    // MARK: - Workout Session
    
    func startWorkout() async throws {
        guard !isWorkoutActive else { return }
        
        // Request authorization if needed
        if !isAuthorized {
            try await requestAuthorization()
        }
        
        // Configure workout
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        
        // Create and start session
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()
            
            session?.delegate = self
            builder?.delegate = self
            
            // Set up data source for live data
            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            
            // Start the session and builder
            let startDate = Date()
            session?.startActivity(with: startDate)
            try await builder?.beginCollection(at: startDate)
            
            workoutStartDate = startDate
            isWorkoutActive = true
            startDurationTimer()
            
        } catch {
            session = nil
            builder = nil
            throw WatchWorkoutError.workoutStartFailed(error)
        }
    }
    
    func endWorkout() async throws {
        guard isWorkoutActive, let session = session, let builder = builder else { return }
        
        let endDate = Date()
        
        session.end()
        
        try await builder.endCollection(at: endDate)
        try await builder.finishWorkout()
        
        stopDurationTimer()
        
        self.session = nil
        self.builder = nil
        self.isWorkoutActive = false
        self.currentHeartRate = nil
        self.workoutDuration = 0
        self.workoutStartDate = nil
    }
    
    func pauseWorkout() {
        session?.pause()
    }
    
    func resumeWorkout() {
        session?.resume()
    }
    
    // MARK: - Timer
    
    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startDate = self.workoutStartDate else { return }
                self.workoutDuration = Date().timeIntervalSince(startDate)
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                isWorkoutActive = true
            case .ended, .stopped:
                isWorkoutActive = false
            case .paused:
                break
            default:
                break
            }
        }
    }
    
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            isWorkoutActive = false
            session = nil
            builder = nil
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
    
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            // Extract heart rate from collected data
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType,
                      quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate) else { continue }
                
                let statistics = workoutBuilder.statistics(for: quantityType)
                let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
                
                if let value = statistics?.mostRecentQuantity()?.doubleValue(for: heartRateUnit) {
                    self.currentHeartRate = value
                    // Notify listener (to send to iPhone)
                    self.onHeartRateUpdate?(value)
                }
            }
        }
    }
}

// MARK: - Errors

enum WatchWorkoutError: LocalizedError {
    case healthKitNotAvailable
    case workoutStartFailed(Error)
    case workoutEndFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .healthKitNotAvailable:
            return "HealthKit is not available on this device"
        case .workoutStartFailed(let error):
            return "Failed to start workout: \(error.localizedDescription)"
        case .workoutEndFailed(let error):
            return "Failed to end workout: \(error.localizedDescription)"
        }
    }
}

