import Foundation
import HealthKit

/// Manages HealthKit integration for workout tracking
/// Automatically starts/ends strength training workouts and syncs to Apple Fitness
@MainActor
public final class HealthKitManager: ObservableObject {
    public static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    private var workoutBuilder: HKWorkoutBuilder?
    private var workoutStartDate: Date?
    
    @Published public private(set) var isWorkoutActive = false
    @Published public private(set) var isAuthorized = false
    @Published public private(set) var authorizationError: String?
    
    // MARK: - Calorie Estimation Constants
    
    /// METs (Metabolic Equivalent of Task) for strength training
    /// Traditional strength training is typically 3.5-6 METs
    /// We use 5 METs for moderate-to-vigorous strength training
    private let strengthTrainingMETs: Double = 5.0
    
    /// Calories burned per minute for strength training (fallback if no body weight)
    /// Based on average 70kg person doing moderate strength training
    private let defaultCaloriesPerMinute: Double = 5.0
    
    private init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    /// Check if HealthKit is available on this device
    public var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    /// Check current authorization status
    public func checkAuthorizationStatus() {
        guard isHealthKitAvailable else {
            isAuthorized = false
            return
        }
        
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        isAuthorized = status == .sharingAuthorized
    }
    
    /// Request authorization to write workouts to HealthKit
    public func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }
        
        // Types we want to write
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned)
        ]
        
        // Types we want to read (body mass for more accurate calorie calculation)
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.bodyMass)
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            checkAuthorizationStatus()
            Logger.debug("✅ HealthKit authorization granted", category: .healthKit)
        } catch {
            authorizationError = error.localizedDescription
            Logger.error("❌ HealthKit authorization failed: \(error)", category: .healthKit)
            throw HealthKitError.authorizationFailed(error)
        }
    }
    
    // MARK: - Body Weight
    
    /// Get the user's most recent body weight from HealthKit (in kg)
    public func getUserBodyWeight() async -> Double? {
        let bodyMassType = HKQuantityType(.bodyMass)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: bodyMassType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, _ in
            // This will be handled by the continuation below
        }
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMassType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let sample = samples?.first as? HKQuantitySample {
                    let weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    continuation.resume(returning: weightKg)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }
    
    /// Estimate calories burned during strength training
    /// Uses METs formula if body weight is available, otherwise uses a default rate
    private func estimateCaloriesBurned(durationMinutes: Double, bodyWeightKg: Double?) -> Double {
        if let weight = bodyWeightKg {
            // Calories = METs × weight(kg) × duration(hours)
            let durationHours = durationMinutes / 60.0
            return strengthTrainingMETs * weight * durationHours
        } else {
            // Fallback: use average calories per minute
            return defaultCaloriesPerMinute * durationMinutes
        }
    }
    
    // MARK: - Workout Session Management
    
    /// Start a new strength training workout
    /// - Parameter workoutName: Optional name for the workout (e.g., "Week 1, Day 1 - Upper Body")
    public func startWorkout(name: String? = nil) async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }
        
        if !isAuthorized {
            // Try to request authorization first
            try await requestAuthorization()
            guard isAuthorized else {
                throw HealthKitError.notAuthorized
            }
        }
        
        // Don't start a new workout if one is already active
        guard !isWorkoutActive else {
            Logger.debug("⚠️ Workout already active, not starting new one", category: .healthKit)
            return
        }
        
        // Configure the workout
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        
        // Create the workout builder
        workoutBuilder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )
        
        // Begin data collection
        workoutStartDate = Date()
        
        do {
            try await workoutBuilder?.beginCollection(at: workoutStartDate!)
            isWorkoutActive = true
            Logger.debug("🏋️ HealthKit workout started: \(name ?? "Strength Training")", category: .healthKit)
        } catch {
            workoutBuilder = nil
            workoutStartDate = nil
            Logger.error("❌ Failed to start HealthKit workout: \(error)", category: .healthKit)
            throw HealthKitError.workoutStartFailed(error)
        }
    }
    
    /// End the current workout and save it to HealthKit
    /// - Parameters:
    ///   - totalVolume: Optional total volume (weight × reps) during the workout (in lbs)
    ///   - setCount: Optional number of sets completed
    ///   - repCount: Optional total number of reps completed
    /// - Returns: The saved workout, or nil if no workout was active
    @discardableResult
    public func endWorkout(totalVolume: Double? = nil, setCount: Int? = nil, repCount: Int? = nil) async throws -> HKWorkout? {
        guard let builder = workoutBuilder, let startDate = workoutStartDate else {
            Logger.debug("⚠️ No active workout to end", category: .healthKit)
            return nil
        }
        
        let endDate = Date()
        let duration = endDate.timeIntervalSince(startDate)
        let durationMinutes = duration / 60.0
        
        do {
            // Get user's body weight for more accurate calorie calculation
            let bodyWeight = await getUserBodyWeight()
            
            // Calculate calories burned
            let caloriesBurned = estimateCaloriesBurned(durationMinutes: durationMinutes, bodyWeightKg: bodyWeight)
            
            // Create active energy sample
            let energyType = HKQuantityType(.activeEnergyBurned)
            let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: caloriesBurned)
            let energySample = HKQuantitySample(
                type: energyType,
                quantity: energyQuantity,
                start: startDate,
                end: endDate
            )
            
            // Add energy sample to workout
            try await builder.addSamples([energySample])
            
            // End data collection
            try await builder.endCollection(at: endDate)
            
            // Build metadata
            var metadata: [String: Any] = [
                HKMetadataKeyWorkoutBrandName: "Top Set Training"
            ]
            
            if let volume = totalVolume {
                // Convert lbs to kg for HealthKit (standard unit)
                let volumeInKg = volume * 0.453592
                metadata["TotalVolumeLbs"] = volume
                metadata["TotalVolumeKg"] = volumeInKg
            }
            
            if let sets = setCount {
                metadata["TotalSets"] = sets
            }
            
            if let reps = repCount {
                metadata["TotalReps"] = reps
            }
            
            if let weight = bodyWeight {
                metadata["UserBodyWeightKg"] = weight
            }
            
            try await builder.addMetadata(metadata)
            
            // Finish and save the workout
            let workout = try await builder.finishWorkout()
            
            // Clean up
            workoutBuilder = nil
            workoutStartDate = nil
            isWorkoutActive = false
            
            let minutes = Int(durationMinutes)
            let calories = Int(caloriesBurned)
            Logger.debug("✅ HealthKit workout saved: \(minutes) min, \(calories) kcal, \(setCount ?? 0) sets", category: .healthKit)
            
            return workout
        } catch {
            // Clean up even on failure
            workoutBuilder = nil
            workoutStartDate = nil
            isWorkoutActive = false
            
            Logger.error("❌ Failed to save HealthKit workout: \(error)", category: .healthKit)
            throw HealthKitError.workoutSaveFailed(error)
        }
    }
    
    /// Discard the current workout without saving
    public func discardWorkout() {
        guard workoutBuilder != nil else { return }
        
        workoutBuilder?.discardWorkout()
        workoutBuilder = nil
        workoutStartDate = nil
        isWorkoutActive = false
        
        Logger.debug("🗑️ HealthKit workout discarded", category: .healthKit)
    }
    
    /// Get the current workout duration in seconds
    public var currentWorkoutDuration: TimeInterval {
        guard let startDate = workoutStartDate else { return 0 }
        return Date().timeIntervalSince(startDate)
    }
}

// MARK: - Errors

public enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case authorizationFailed(Error)
    case workoutStartFailed(Error)
    case workoutSaveFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access not authorized. Please enable in Settings."
        case .authorizationFailed(let error):
            return "HealthKit authorization failed: \(error.localizedDescription)"
        case .workoutStartFailed(let error):
            return "Failed to start workout: \(error.localizedDescription)"
        case .workoutSaveFailed(let error):
            return "Failed to save workout: \(error.localizedDescription)"
        }
    }
}


