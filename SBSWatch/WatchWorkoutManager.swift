import Foundation
import HealthKit
import Combine

/// Manages workout sessions on Apple Watch with full HKWorkoutSession support
@MainActor
class WatchWorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    
    // Heart rate query for continuous monitoring
    private var heartRateQuery: HKAnchoredObjectQuery?
    
    // Published state
    @Published var isWorkoutActive = false
    @Published var isAuthorized = false
    @Published var currentHeartRate: Double?
    @Published var workoutDuration: TimeInterval = 0
    /// True when a workout was requested with HealthKit saving but authorization
    /// failed and we fell back to tracking without HealthKit. Drives an inline
    /// "Allow Health access on your watch" hint in the UI.
    @Published var healthKitError = false

    /// Whether an HealthKit-saving workout session is currently running on the
    /// Watch (i.e. a workout will be written to HealthKit on finish).
    var isSavingToHealthKit: Bool { session != nil }
    
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
    
    /// Start a workout on the Watch.
    ///
    /// - Parameter saveToHealthKit: when `true` the Watch runs an
    ///   `HKLiveWorkoutSession` and writes its own workout (plus heart rate) to
    ///   HealthKit. When `false`, the Watch tracks the workout for display only and
    ///   does NOT touch HealthKit — this honors the phone's HealthKit setting and
    ///   avoids duplicate HealthKit workouts.
    ///
    /// This method handles its own errors and never throws: if HealthKit isn't
    /// available or authorization fails, it falls back to non-HealthKit tracking so
    /// the workout UI stays usable (and sets `healthKitError` so the UI can hint).
    func startWorkout(saveToHealthKit: Bool) async {
        // Don't stack sessions: bail if a workout is already active or an HK session
        // is still finishing (guarding on `session` covers the forceInactive() case
        // where isWorkoutActive was cleared but the HK session hasn't ended yet).
        guard !isWorkoutActive, session == nil else { return }

        healthKitError = false

        // Non-HealthKit path: either the phone's HealthKit setting is off, or
        // HealthKit isn't available on this device.
        guard saveToHealthKit, HKHealthStore.isHealthDataAvailable() else {
            startWorkoutWithoutHealthKit()
            return
        }

        do {
            // Request authorization if needed
            if !isAuthorized {
                try await requestAuthorization()
            }

            // Configure workout
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor

            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self

            // Set up data source for live data
            let dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            builder?.dataSource = dataSource

            // Explicitly enable heart rate collection for more frequent updates
            let heartRateType = HKQuantityType(.heartRate)
            dataSource.enableCollection(for: heartRateType, predicate: nil)

            // Start the session and builder
            let startDate = Date()
            session?.startActivity(with: startDate)
            try await builder?.beginCollection(at: startDate)

            workoutStartDate = startDate
            isWorkoutActive = true
            startDurationTimer()

            // Start continuous heart rate monitoring query
            startHeartRateQuery(from: startDate)

        } catch {
            // HealthKit failed (e.g. user declined auth). Don't get stuck — fall
            // back to non-HealthKit tracking so the workout UI is still usable, and
            // surface a hint.
            Logger.error("Watch HealthKit workout start failed, tracking without HealthKit: \(error)", category: .healthKit)
            session = nil
            builder = nil
            healthKitError = true
            startWorkoutWithoutHealthKit()
        }
    }

    /// Track a workout without HealthKit: no HK session, no saved workout, no heart
    /// rate. The UI still shows duration and lets the user drive the workout.
    private func startWorkoutWithoutHealthKit() {
        let startDate = Date()
        workoutStartDate = startDate
        isWorkoutActive = true
        currentHeartRate = nil
        startDurationTimer()
    }
    
    // MARK: - Heart Rate Query
    
    /// Start an anchored object query for continuous heart rate monitoring
    /// This provides more frequent updates than relying solely on the workout builder
    private func startHeartRateQuery(from startDate: Date) {
        let heartRateType = HKQuantityType(.heartRate)
        
        // Create predicate to only get samples from this workout
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: nil,
            options: .strictStartDate
        )
        
        // Create anchored query that will receive updates as new samples arrive
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }
        
        // Set up the update handler for continuous monitoring
        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.processHeartRateSamples(samples)
        }
        
        heartRateQuery = query
        healthStore.execute(query)
    }
    
    /// Stop the heart rate query
    private func stopHeartRateQuery() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
    }
    
    /// Process heart rate samples from the query
    private nonisolated func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let heartRateSamples = samples as? [HKQuantitySample],
              let mostRecent = heartRateSamples.last else { return }
        
        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
        let value = mostRecent.quantity.doubleValue(for: heartRateUnit)
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.currentHeartRate = value
            self.onHeartRateUpdate?(value)
        }
    }
    
    func endWorkout() async throws {
        // Only check if session exists - don't check isWorkoutActive since forceInactive() may have cleared it
        guard let session = session, let builder = builder else { return }
        
        let endDate = Date()
        
        // Stop heart rate monitoring
        stopHeartRateQuery()
        
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
    
    /// Immediately mark the workout as inactive (for UI purposes)
    /// Called when iPhone signals workout ended, before async cleanup completes
    func forceInactive() {
        isWorkoutActive = false
        currentHeartRate = nil
        healthKitError = false
        durationTimer?.invalidate()
        durationTimer = nil
        workoutDuration = 0
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
            stopHeartRateQuery()
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

