import Foundation
import Observation

// MARK: - Workout Exercise Model

/// Codable so a session survives an app kill. `id` is stored, not regenerated:
/// `completedSets` and `failedSets` are keyed by it.
struct WorkoutExercise: Identifiable, Codable, Equatable {
    var id = UUID()
    let name: String
    let lift: String?
    var weight: Double
    let totalSets: Int
    let repsPerSet: Int
    let repOutTarget: Int
    let isAccessory: Bool  // True if this is an accessory exercise
    let isStructured: Bool  // True if this is a structured exercise
    var structuredSetInfo: [StructuredSetInfo]?  // Set details for structured exercises (mutable so weight overrides can scale per-set weights)
    let isLinear: Bool  // True if this is a linear progression exercise
    let linearInfo: LinearExerciseInfo?  // Linear progression info
    let intensity: Double?  // Percentage of training max (0.0-1.0)
    let calculatedWeight: Double?  // Original calculated weight (before any override)
    var lastWasEasy: Bool? = nil  // For accessories: did the user mark the previous session as easy?
    var markedEasy: Bool = false  // For accessories: did the user mark this current session as easy?

    /// What custom bars are assigned against: the lift, or the name for accessories
    var barKeySource: String { lift ?? name }

    /// Given a set number (1-indexed), is it a rep-out? Volume exercises finish on one,
    /// structured exercises say per set, and linear and accessory work has none.
    func isRepOutSet(_ setNumber: Int) -> Bool {
        if isStructured {
            guard let sets = structuredSetInfo, setNumber > 0, setNumber <= sets.count else { return false }
            return sets[setNumber - 1].isAMRAP
        }
        if isLinear || isAccessory { return false }
        return setNumber == totalSets
    }

    /// For volume exercises, the last set is the rep-out
    static func fromVolumeItem(name: String, lift: String, weight: Double, sets: Int, repsPerSet: Int, repOutTarget: Int, intensity: Double, calculatedWeight: Double? = nil) -> WorkoutExercise {
        WorkoutExercise(
            name: name,
            lift: lift,
            weight: weight,
            totalSets: sets,
            repsPerSet: repsPerSet,
            repOutTarget: repOutTarget,
            isAccessory: false,
            isStructured: false,
            structuredSetInfo: nil,
            isLinear: false,
            linearInfo: nil,
            intensity: intensity,
            calculatedWeight: calculatedWeight ?? weight
        )
    }
    
    /// For accessory exercises (no rep-out)
    static func fromAccessory(name: String, sets: Int, reps: Int, lastLogWeight: Double?, lastWasEasy: Bool? = nil) -> WorkoutExercise {
        var ex = WorkoutExercise(
            name: name,
            lift: nil,
            weight: lastLogWeight ?? 0,
            totalSets: sets,
            repsPerSet: reps,
            repOutTarget: 0,
            isAccessory: true,
            isStructured: false,
            structuredSetInfo: nil,
            isLinear: false,
            linearInfo: nil,
            intensity: nil,
            calculatedWeight: nil
        )
        ex.lastWasEasy = lastWasEasy
        return ex
    }
    
    /// For nSuns exercises with varying sets
    static func fromStructured(name: String, lift: String, sets: [StructuredSetInfo]) -> WorkoutExercise {
        // Find the heaviest weight as the display weight
        let heaviestWeight = sets.max(by: { $0.weight < $1.weight })?.weight ?? 0
        // Find the target reps for display (use the 1+ set if available)
        let primarySet = sets.first { $0.isAMRAP && $0.targetReps == 1 } ?? sets.first { $0.isAMRAP }
        let repOutTarget = primarySet?.targetReps ?? 1
        
        return WorkoutExercise(
            name: name,
            lift: lift,
            weight: heaviestWeight,
            totalSets: sets.count,
            repsPerSet: 0,  // Not used for structured
            repOutTarget: repOutTarget,
            isAccessory: false,
            isStructured: true,
            structuredSetInfo: sets,
            isLinear: false,
            linearInfo: nil,
            intensity: nil,  // Structured exercises have per-set intensity
            // Pre-override weight, so the override sheet still shows the prescribed load
            calculatedWeight: sets.max(by: { $0.calculatedWeight < $1.calculatedWeight })?.calculatedWeight ?? heaviestWeight
        )
    }
    
    /// For linear progression exercises (StrongLifts, Starting Strength style)
    static func fromLinear(name: String, info: LinearExerciseInfo) -> WorkoutExercise {
        WorkoutExercise(
            name: name,
            lift: info.lift,
            weight: info.weight,
            totalSets: info.sets,
            repsPerSet: info.reps,
            repOutTarget: info.reps,  // Target is to complete all reps
            isAccessory: false,
            isStructured: false,
            structuredSetInfo: nil,
            isLinear: true,
            linearInfo: info,
            intensity: 1.0,  // Linear progression is always at 100% working weight
            calculatedWeight: info.calculatedWeight ?? info.weight
        )
    }
}

// MARK: - Superset Accessory Data

struct SupersetAccessoryData: Codable, Equatable {
    let name: String
    let sets: Int
    let reps: Int
    let weight: Double?  // from lastLog if available
    var lastWasEasy: Bool? = nil
}

extension SupersetAccessoryData {
    /// A standalone accessory becoming a pair
    init(accessory exercise: WorkoutExercise) {
        self.init(
            name: exercise.name,
            sets: exercise.totalSets,
            reps: exercise.repsPerSet,
            weight: exercise.weight > 0 ? exercise.weight : nil,
            lastWasEasy: exercise.lastWasEasy
        )
    }
}

// MARK: - Superset Pairing

/// Which accessory goes with which main lift. A day the lifter hasn't chosen for pairs
/// in order; a chosen day pairs only what was chosen, by name.
enum SupersetPairing {
    /// Main-lift index -> accessory index. Names that no longer exist are skipped, and an
    /// accessory pairs at most once (the first lift to claim it keeps it).
    static func resolve(lifts: [String], accessories: [String], saved: [String: String]?) -> [Int: Int] {
        guard let saved else {
            return Dictionary(uniqueKeysWithValues: (0..<min(lifts.count, accessories.count)).map { ($0, $0) })
        }
        var result: [Int: Int] = [:]
        var used = Set<Int>()
        for (liftIndex, lift) in lifts.enumerated() {
            guard let name = saved[lift],
                  let accessoryIndex = accessories.indices.first(where: { accessories[$0] == name && !used.contains($0) })
            else { continue }
            result[liftIndex] = accessoryIndex
            used.insert(accessoryIndex)
        }
        return result
    }

    /// The same pairs as names, the form they're remembered in
    static func names(lifts: [String], accessories: [String], pairs: [Int: Int]) -> [String: String] {
        var result: [String: String] = [:]
        for (lift, accessory) in pairs where lifts.indices.contains(lift) && accessories.indices.contains(accessory) {
            result[lifts[lift]] = accessories[accessory]
        }
        return result
    }
}

// MARK: - Performed Accessory

/// An accessory actually done in a session, as it gets logged when the session finishes
struct PerformedAccessory: Equatable {
    let name: String
    let weight: Double
    let sets: Int
    let reps: Int
    let wasEasy: Bool?
}

// MARK: - Workout PR Record

/// Record of a PR achieved during a workout
struct WorkoutPRRecord: Identifiable, Equatable, Codable {
    var id = UUID()
    let liftName: String
    let weight: Double
    let reps: Int
    let newE1RM: Double
    let previousE1RM: Double?
}

// MARK: - AMRAP Result

/// A lift's strongest AMRAP result this session (for E1RM on the share card)
struct WorkoutAMRAPResult: Codable, Equatable {
    var weight: Double
    var reps: Int
    var e1rm: Double
}

// MARK: - Set Undo

/// What a completed set changed, so undoing it can put things back. A redo replaces
/// the day's earlier results as it logs, so "put back" isn't always "clear".
struct SetUndoInfo: Codable, Equatable {
    /// This set finished a linear lift, which logged its result
    var finishedLinearLift = false
    var previousLinearEntry: LinearLogEntry?
    var previousTrainingMax: Double?
    /// Reps an AMRAP log on this set replaced
    var previousReps: Int?
    /// This set created the day's empty "done" log for a structured lift with no AMRAP
    var createdStructuredLog = false
}

/// One completed set, in the order they were done
struct CompletedSetRecord: Codable, Equatable {
    let exerciseId: UUID
    let setNumber: Int
    var undo: SetUndoInfo
}

// MARK: - Next Workout

enum NextWorkout {
    /// The first day with nothing logged, from `week` onward. A day ended early counts
    /// as visited, so it doesn't send the lifter back to repeat what they already did.
    /// Nil when no day is left: nothing advances past the end of the cycle.
    static func find(
        fromWeek week: Int,
        weeks: [Int],
        visibleDays: (Int) -> [Int],
        isNotStarted: (_ week: Int, _ day: Int) -> Bool
    ) -> (week: Int, day: Int)? {
        for candidate in weeks.sorted() where candidate >= week {
            if let day = visibleDays(candidate).first(where: { isNotStarted(candidate, $0) }) {
                return (candidate, day)
            }
        }
        return nil
    }
}

// MARK: - Workout State

@Observable
final class WorkoutState {
    var exercises: [WorkoutExercise] = []
    var currentExerciseIndex: Int = 0
    var currentSetNumber: Int = 1  // 1-indexed
    var completedSets: [UUID: Set<Int>] = [:]  // exercise.id -> set of completed set numbers
    var repOutLogs: [String: Int] = [:]  // lift name -> reps logged
    
    // Linear progression tracking
    var failedSets: [UUID: Set<Int>] = [:]  // exercise.id -> set of failed set numbers (for linear progression)
    var linearExerciseCompleted: [UUID: Bool] = [:]  // exercise.id -> was exercise fully completed (no failures)?
    
    // Accessories paired with exercises (by exercise index)
    var supersetAccessories: [Int: SupersetAccessoryData] = [:]
    
    // PRs achieved during this workout
    var prsAchieved: [WorkoutPRRecord] = []
    
    // AMRAP results for exercises (for E1RM calculation in share card)
    var amrapResults: [String: WorkoutAMRAPResult] = [:]  // lift name -> result

    // Reps logged this session on structured AMRAP sets: exercise.id -> set index -> reps
    var structuredLoggedReps: [UUID: [Int: Int]] = [:]

    /// Completed sets in order, for undo
    var completionHistory: [CompletedSetRecord] = []

    /// The lifter chose to finish with work left
    var finishedEarly = false

    /// A ±15s change, kept for the rest of that exercise in this session
    var restOverrides: [UUID: Int] = [:]

    /// The exercise whose set started the current rest. `currentExercise` has already
    /// moved on when that was its last set.
    var restingExerciseId: UUID?
    
    // Timer state
    var timerRemaining: Int = 0
    var timerDuration: Int = 120
    var timerIsRunning: Bool = false
    var timerIsPaused: Bool = false
    var showingTimer: Bool = false
    var timerEndDate: Date?  // When the timer should end (for resuming after navigation)
    var timerPausedRemaining: Int?  // Remaining seconds when paused (for accurate resume)
    
    /// Which exercise's pair is showing. During a rest that's the exercise being rested
    /// from: after its last set `currentExerciseIndex` has already moved on, and the
    /// accessory's own last set still happens in that rest.
    private var supersetExerciseIndex: Int {
        if showingTimer, let restingExerciseId,
           let index = exercises.firstIndex(where: { $0.id == restingExerciseId }) {
            return index
        }
        return currentExerciseIndex
    }

    /// Get the accessory to superset with the current exercise (if any)
    var currentSupersetAccessory: SupersetAccessoryData? {
        supersetAccessories[supersetExerciseIndex]
    }

    /// Change the showing pair's weight for this session
    func setCurrentSupersetAccessoryWeight(_ weight: Double) {
        guard let accessory = currentSupersetAccessory else { return }
        supersetAccessories[supersetExerciseIndex] = SupersetAccessoryData(
            name: accessory.name,
            sets: accessory.sets,
            reps: accessory.reps,
            weight: weight,
            lastWasEasy: accessory.lastWasEasy
        )
    }
    
    /// Supersets turned off mid-workout: a pair whose lift hasn't started becomes its own
    /// exercise at the end. Pairs already under way stay paired, so the sets done
    /// alongside their lift still count. Returns whether anything moved.
    @discardableResult
    func unpairUnstartedSupersets() -> Bool {
        guard !isFinished else { return false }
        let unstarted = supersetAccessories.keys.sorted().filter { completedSetsForExercise(at: $0) == 0 }
        for index in unstarted {
            guard let pair = supersetAccessories.removeValue(forKey: index) else { continue }
            exercises.append(.fromAccessory(
                name: pair.name,
                sets: pair.sets,
                reps: pair.reps,
                lastLogWeight: pair.weight,
                lastWasEasy: pair.lastWasEasy
            ))
        }
        return !unstarted.isEmpty
    }

    /// A lift's pair can change until its first set: after that, sets have been done
    /// alongside it and moving the accessory would lose them.
    func canChangeSuperset(forExerciseAt index: Int) -> Bool {
        guard !isFinished, exercises.indices.contains(index), !exercises[index].isAccessory else { return false }
        return completedSetsForExercise(at: index) == 0
    }

    /// Accessories a lift could take: its own pair, unstarted standalone accessories, and
    /// pairs of other lifts not yet started (choosing one moves it)
    func availableSupersetAccessories(forExerciseAt index: Int) -> [SupersetAccessoryData] {
        var result: [SupersetAccessoryData] = []
        for key in supersetAccessories.keys.sorted() where key == index || canChangeSuperset(forExerciseAt: key) {
            if let pair = supersetAccessories[key] { result.append(pair) }
        }
        for exercise in exercises where exercise.isAccessory && (completedSets[exercise.id]?.isEmpty ?? true) {
            result.append(SupersetAccessoryData(accessory: exercise))
        }
        return result
    }

    /// This session's pairs by name (main-lift name -> accessory name), to remember them
    var supersetPairNames: [String: String] {
        var result: [String: String] = [:]
        for (index, pair) in supersetAccessories where exercises.indices.contains(index) {
            result[exercises[index].name] = pair.name
        }
        return result
    }

    /// The lift an accessory is paired with right now, if any
    func supersetLiftIndex(forAccessory name: String) -> Int? {
        supersetAccessories.first { $0.value.name == name }?.key
    }

    /// Pair a lift with an accessory, or with nil unpair it. The old pair goes to the end
    /// as its own exercise; a standalone accessory taken leaves the list, and one taken
    /// from another lift leaves that lift without a pair.
    @discardableResult
    func setSuperset(_ accessoryName: String?, forExerciseAt index: Int) -> Bool {
        guard canChangeSuperset(forExerciseAt: index) else { return false }
        guard accessoryName != supersetAccessories[index]?.name else { return false }

        var incoming: SupersetAccessoryData?
        if let accessoryName {
            if let otherLift = supersetLiftIndex(forAccessory: accessoryName) {
                guard canChangeSuperset(forExerciseAt: otherLift) else { return false }
                incoming = supersetAccessories.removeValue(forKey: otherLift)
            } else if let standalone = exercises.firstIndex(where: {
                $0.isAccessory && $0.name == accessoryName && (completedSets[$0.id]?.isEmpty ?? true)
            }) {
                let exercise = exercises[standalone]
                incoming = SupersetAccessoryData(accessory: exercise)
                removeExercise(at: standalone)
            } else {
                return false
            }
        }

        if let old = supersetAccessories.removeValue(forKey: index) {
            exercises.append(.fromAccessory(
                name: old.name,
                sets: old.sets,
                reps: old.reps,
                lastLogWeight: old.weight,
                lastWasEasy: old.lastWasEasy
            ))
        }
        if let incoming {
            supersetAccessories[index] = incoming
        }
        return true
    }

    /// Take an unstarted exercise out, keeping the current position and the pairs (which
    /// are keyed by index) on the same exercises
    private func removeExercise(at removed: Int) {
        let currentId = currentExercise?.id
        exercises.remove(at: removed)
        var shifted: [Int: SupersetAccessoryData] = [:]
        for (key, pair) in supersetAccessories {
            shifted[key > removed ? key - 1 : key] = pair
        }
        supersetAccessories = shifted
        if let currentId, let index = exercises.firstIndex(where: { $0.id == currentId }) {
            currentExerciseIndex = index
        } else {
            currentExerciseIndex = min(currentExerciseIndex, max(0, exercises.count - 1))
            if let exercise = currentExercise, let set = firstIncompleteSet(of: exercise) {
                currentSetNumber = set
            } else {
                currentSetNumber = 1
            }
        }
    }

    var currentExercise: WorkoutExercise? {
        guard currentExerciseIndex < exercises.count else { return nil }
        return exercises[currentExerciseIndex]
    }
    
    var isCurrentSetRepOut: Bool {
        currentExercise?.isRepOutSet(currentSetNumber) ?? false
    }
    
    var isCurrentExerciseAccessory: Bool {
        currentExercise?.isAccessory ?? false
    }
    
    /// Every set of every exercise is done
    var isWorkoutComplete: Bool {
        exercises.allSatisfy { firstIncompleteSet(of: $0) == nil }
    }

    /// Time for the summary: everything is done, or the lifter chose to stop
    var isFinished: Bool {
        isWorkoutComplete || finishedEarly
    }

    /// The first exercise with sets left, if any
    var firstOpenExerciseIndex: Int? {
        exercises.firstIndex { firstIncompleteSet(of: $0) != nil }
    }

    /// Nothing is left from here on, but earlier exercises are still open: the lifter
    /// jumped ahead and needs to choose between going back and finishing.
    var reachedEndWithOpenExercises: Bool {
        guard !finishedEarly, firstOpenExerciseIndex != nil else { return false }
        return !exercises.indices.contains { index in
            index >= currentExerciseIndex && firstIncompleteSet(of: exercises[index]) != nil
        }
    }

    /// Accessories with at least one set done, in workout order, at the session's weight
    /// and with the sets actually completed. A superset accessory has no sets of its own:
    /// it rides along with its main lift, one for one, up to its own set count.
    var performedAccessories: [PerformedAccessory] {
        exercises.indices.compactMap { index in
            let exercise = exercises[index]
            let setsDone = completedSets[exercise.id]?.count ?? 0
            guard setsDone > 0 else { return nil }
            if exercise.isAccessory {
                return PerformedAccessory(
                    name: exercise.name,
                    weight: exercise.weight,
                    sets: setsDone,
                    reps: exercise.repsPerSet,
                    wasEasy: exercise.markedEasy ? true : nil
                )
            }
            guard let paired = supersetAccessories[index] else { return nil }
            return PerformedAccessory(
                name: paired.name,
                weight: paired.weight ?? 0,
                sets: min(setsDone, paired.sets),
                reps: paired.reps,
                wasEasy: nil
            )
        }
    }

    /// Sets not yet done, across the whole workout
    var remainingSetsCount: Int {
        exercises.reduce(0) { $0 + max(0, $1.totalSets - (completedSets[$1.id]?.count ?? 0)) }
    }
    
    var currentSetCompletedCount: Int {
        guard let exercise = currentExercise else { return 0 }
        return completedSets[exercise.id]?.count ?? 0
    }
    
    /// Total number of sets completed across all exercises
    var completedSetsCount: Int {
        completedSets.values.reduce(0) { $0 + $1.count }
    }
    
    var progress: Double {
        let totalSets = exercises.reduce(0) { $0 + $1.totalSets }
        guard totalSets > 0 else { return 0 }
        let completedCount = completedSets.values.reduce(0) { $0 + $1.count }
        return Double(completedCount) / Double(totalSets)
    }
    
    func markSetComplete(undo: SetUndoInfo = SetUndoInfo()) {
        guard let exercise = currentExercise else { return }

        if completedSets[exercise.id, default: []].insert(currentSetNumber).inserted {
            completionHistory.append(CompletedSetRecord(exerciseId: exercise.id, setNumber: currentSetNumber, undo: undo))
        }
        advanceToNextIncompleteSet()
    }

    /// Whether every set of an exercise is done
    func isExerciseFinished(_ exercise: WorkoutExercise) -> Bool {
        firstIncompleteSet(of: exercise) == nil
    }

    /// Reopen a completed set and put the lifter back on it. The caller reverses
    /// anything the set logged, using the record this returns.
    @discardableResult
    func reopenSet(exerciseId: UUID, setNumber: Int) -> CompletedSetRecord? {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseId }) else { return nil }
        completedSets[exerciseId]?.remove(setNumber)
        failedSets[exerciseId]?.remove(setNumber)
        finishedEarly = false
        currentExerciseIndex = index
        currentSetNumber = setNumber
        guard let recordIndex = completionHistory.lastIndex(where: { $0.exerciseId == exerciseId && $0.setNumber == setNumber }) else { return nil }
        return completionHistory.remove(at: recordIndex)
    }

    /// Take the "this set finished the lift" note off an exercise's records and return
    /// it. Reopening any set of a finished lift un-finishes it, not only its last set.
    func takeLinearFinish(exerciseId: UUID) -> SetUndoInfo? {
        guard let index = completionHistory.lastIndex(where: { $0.exerciseId == exerciseId && $0.undo.finishedLinearLift }) else { return nil }
        let undo = completionHistory[index].undo
        completionHistory[index].undo.finishedLinearLift = false
        completionHistory[index].undo.previousLinearEntry = nil
        completionHistory[index].undo.previousTrainingMax = nil
        return undo
    }

    /// Same as `takeLinearFinish`, for the empty log of a structured lift with no AMRAP
    func takeStructuredLogCreation(exerciseId: UUID) -> Bool {
        guard let index = completionHistory.lastIndex(where: { $0.exerciseId == exerciseId && $0.undo.createdStructuredLog }) else { return false }
        completionHistory[index].undo.createdStructuredLog = false
        return true
    }

    /// Rebuild a lift's strongest AMRAP from what's still logged this session
    func recomputeAMRAPResult(lift: String, e1rm: (_ weight: Double, _ reps: Int) -> Double) {
        var best: WorkoutAMRAPResult?
        func consider(weight: Double, reps: Int) {
            let value = e1rm(weight, reps)
            if value > (best?.e1rm ?? 0) {
                best = WorkoutAMRAPResult(weight: weight, reps: reps, e1rm: value)
            }
        }
        for exercise in exercises where exercise.lift == lift {
            if let sets = exercise.structuredSetInfo {
                for (setIndex, reps) in structuredLoggedReps[exercise.id] ?? [:] {
                    if let set = sets.first(where: { $0.setIndex == setIndex }) {
                        consider(weight: set.weight, reps: reps)
                    }
                }
            } else if let reps = repOutLogs[lift] {
                consider(weight: exercise.weight, reps: reps)
            }
        }
        amrapResults[lift] = best
    }

    /// First set of an exercise not yet completed, if any
    private func firstIncompleteSet(of exercise: WorkoutExercise) -> Int? {
        let completed = completedSets[exercise.id] ?? []
        return (0..<exercise.totalSets).lazy.map { $0 + 1 }.first { !completed.contains($0) }
    }

    /// Move to the next set still to do, skipping exercises already finished (the user
    /// may have jumped around via the exercise list). With nothing left ahead, land on
    /// the last exercise so `isWorkoutComplete` can trigger.
    private func advanceToNextIncompleteSet() {
        guard let exercise = currentExercise else { return }
        if let nextSet = firstIncompleteSet(of: exercise) {
            currentSetNumber = nextSet
            return
        }
        for index in exercises.indices where index > currentExerciseIndex {
            if let nextSet = firstIncompleteSet(of: exercises[index]) {
                currentExerciseIndex = index
                currentSetNumber = nextSet
                return
            }
        }
        if currentExerciseIndex < exercises.count - 1 {
            currentExerciseIndex = exercises.count - 1
            currentSetNumber = exercises[currentExerciseIndex].totalSets
        }
    }
    
    func isSetCompleted(_ setNumber: Int) -> Bool {
        guard let exercise = currentExercise else { return false }
        return completedSets[exercise.id]?.contains(setNumber) ?? false
    }
    
    func isSetFailed(_ setNumber: Int) -> Bool {
        guard let exercise = currentExercise else { return false }
        return failedSets[exercise.id]?.contains(setNumber) ?? false
    }
    
    /// Mark a set as failed (for linear progression)
    func markSetFailed(undo: SetUndoInfo = SetUndoInfo()) {
        guard let exercise = currentExercise else { return }
        failedSets[exercise.id, default: []].insert(currentSetNumber)
        // Also counts as "completed" for progress purposes
        markSetComplete(undo: undo)
    }
    
    /// Check if a linear exercise had any failed sets
    func hasFailedSets(for exerciseId: UUID) -> Bool {
        !(failedSets[exerciseId]?.isEmpty ?? true)
    }
    
    /// Check if current linear exercise is fully completed with no failures
    var isCurrentLinearExerciseSuccessful: Bool {
        guard let exercise = currentExercise, exercise.isLinear else { return false }
        let completed = completedSets[exercise.id]?.count ?? 0
        let failed = failedSets[exercise.id]?.count ?? 0
        return completed >= exercise.totalSets && failed == 0
    }
    
    /// Jump to a specific exercise by index
    func jumpToExercise(_ index: Int) {
        guard index >= 0 && index < exercises.count else { return }
        
        // Stop any running timer
        timerIsRunning = false
        timerIsPaused = false
        showingTimer = false
        timerRemaining = 0
        RestTimerStatus.shared.timerCleared()

        currentExerciseIndex = index
        
        // First incomplete set for this exercise; set 1 if all are complete
        currentSetNumber = firstIncompleteSet(of: exercises[index]) ?? 1
    }
    
    /// Check how many sets are completed for a given exercise index
    func completedSetsForExercise(at index: Int) -> Int {
        guard exercises.indices.contains(index) else { return 0 }
        return completedSets[exercises[index].id]?.count ?? 0
    }
    
    /// How long to rest after a set of this exercise: its ±15s change if it has one
    func restDuration(for exercise: WorkoutExercise, default defaultDuration: Int) -> Int {
        restOverrides[exercise.id] ?? defaultDuration
    }

    func startTimer(duration: Int, forExercise exerciseId: UUID? = nil) {
        restingExerciseId = exerciseId
        timerDuration = duration
        timerRemaining = duration
        timerIsRunning = true
        timerIsPaused = false
        showingTimer = true
        let endDate = Date().addingTimeInterval(TimeInterval(duration))
        timerEndDate = endDate
        timerPausedRemaining = nil
        RestTimerStatus.shared.timerStarted(endDate: endDate)
    }

    func pauseTimer() {
        timerIsPaused = true
        timerIsRunning = false
        timerPausedRemaining = timerRemaining
        timerEndDate = nil
        RestTimerStatus.shared.timerPaused(remaining: timerRemaining)
    }

    func resumeTimer() {
        timerIsPaused = false
        timerIsRunning = true
        // Restore end date based on remaining time
        if let pausedRemaining = timerPausedRemaining {
            let endDate = Date().addingTimeInterval(TimeInterval(pausedRemaining))
            timerEndDate = endDate
            RestTimerStatus.shared.timerStarted(endDate: endDate)
        }
        timerPausedRemaining = nil
    }

    func skipTimer() {
        timerIsRunning = false
        timerIsPaused = false
        showingTimer = false
        timerRemaining = 0
        timerEndDate = nil
        timerPausedRemaining = nil
        restingExerciseId = nil
        RestTimerStatus.shared.timerCleared()
    }

    /// Adjust the running rest timer by `delta` seconds, continuing from the elapsed time.
    /// Example: 60s timer with 12s elapsed (48s remaining) + 15s → 75s timer with 63s remaining.
    /// Returns the new effective `timerDuration` (clamped to `minimumDuration`).
    @discardableResult
    func adjustTimer(by delta: Int, minimumDuration: Int = 15) -> Int {
        let newDuration = max(minimumDuration, timerDuration + delta)
        let appliedDelta = newDuration - timerDuration
        timerDuration = newDuration
        if let restingExerciseId {
            restOverrides[restingExerciseId] = newDuration
        }

        if timerIsRunning, let endDate = timerEndDate {
            let shifted = endDate.addingTimeInterval(TimeInterval(appliedDelta))
            timerEndDate = shifted
            timerRemaining = max(0, Int(ceil(shifted.timeIntervalSinceNow)))
            RestTimerStatus.shared.timerStarted(endDate: shifted)
        } else if timerIsPaused, let paused = timerPausedRemaining {
            let newRemaining = max(0, paused + appliedDelta)
            timerPausedRemaining = newRemaining
            timerRemaining = newRemaining
            RestTimerStatus.shared.timerPaused(remaining: newRemaining)
        } else {
            // Timer hasn't started yet — only the planned duration changes.
            timerRemaining = max(0, timerRemaining + appliedDelta)
        }
        return newDuration
    }
    
    func timerTick() {
        if timerIsRunning, let endDate = timerEndDate {
            // Calculate remaining time from end date for accuracy
            let remaining = Int(ceil(endDate.timeIntervalSinceNow))
            timerRemaining = max(0, remaining)
        }
    }
    
    /// Check if timer should still be running and recalculate remaining time
    func recalculateTimerIfNeeded() {
        if timerIsRunning, let endDate = timerEndDate {
            let remaining = Int(ceil(endDate.timeIntervalSinceNow))
            if remaining > 0 {
                timerRemaining = remaining
            } else {
                // Timer has expired while view was away
                timerRemaining = 0
            }
        }
    }

    // MARK: - Snapshot

    init() {}

    /// Everything needed to resume this session. `timerRemaining` is left out because
    /// it derives from `timerEndDate`, so a tick doesn't count as a change to save.
    var snapshot: WorkoutStateSnapshot {
        WorkoutStateSnapshot(
            exercises: exercises,
            currentExerciseIndex: currentExerciseIndex,
            currentSetNumber: currentSetNumber,
            completedSets: completedSets,
            repOutLogs: repOutLogs,
            failedSets: failedSets,
            linearExerciseCompleted: linearExerciseCompleted,
            supersetAccessories: supersetAccessories,
            prsAchieved: prsAchieved,
            amrapResults: amrapResults,
            structuredLoggedReps: structuredLoggedReps,
            completionHistory: completionHistory,
            finishedEarly: finishedEarly,
            restOverrides: restOverrides,
            restingExerciseId: restingExerciseId,
            timerDuration: timerDuration,
            timerIsRunning: timerIsRunning,
            timerIsPaused: timerIsPaused,
            showingTimer: showingTimer,
            timerEndDate: timerEndDate,
            timerPausedRemaining: timerPausedRemaining
        )
    }

    /// Rebuild a saved session. A rest that ended while the app was dead is cleared
    /// without any feedback: its notification already alerted the user.
    convenience init(snapshot: WorkoutStateSnapshot, now: Date = Date()) {
        self.init()
        exercises = snapshot.exercises
        currentExerciseIndex = snapshot.currentExerciseIndex
        currentSetNumber = snapshot.currentSetNumber
        completedSets = snapshot.completedSets
        repOutLogs = snapshot.repOutLogs
        failedSets = snapshot.failedSets
        linearExerciseCompleted = snapshot.linearExerciseCompleted
        supersetAccessories = snapshot.supersetAccessories
        prsAchieved = snapshot.prsAchieved
        amrapResults = snapshot.amrapResults
        structuredLoggedReps = snapshot.structuredLoggedReps
        completionHistory = snapshot.completionHistory ?? []
        finishedEarly = snapshot.finishedEarly ?? false
        restOverrides = snapshot.restOverrides ?? [:]
        restingExerciseId = snapshot.restingExerciseId
        timerDuration = snapshot.timerDuration

        if snapshot.timerIsPaused, let paused = snapshot.timerPausedRemaining {
            timerIsPaused = true
            showingTimer = true
            timerPausedRemaining = paused
            timerRemaining = paused
            RestTimerStatus.shared.timerPaused(remaining: paused)
        } else if snapshot.timerIsRunning, let endDate = snapshot.timerEndDate, endDate > now {
            timerIsRunning = true
            showingTimer = true
            timerEndDate = endDate
            timerRemaining = Int(ceil(endDate.timeIntervalSince(now)))
            RestTimerStatus.shared.timerStarted(endDate: endDate)
        } else {
            RestTimerStatus.shared.timerCleared()
        }
    }
}

// MARK: - Saved Session

/// The saved form of `WorkoutState`
struct WorkoutStateSnapshot: Codable, Equatable {
    var exercises: [WorkoutExercise]
    var currentExerciseIndex: Int
    var currentSetNumber: Int
    var completedSets: [UUID: Set<Int>]
    var repOutLogs: [String: Int]
    var failedSets: [UUID: Set<Int>]
    var linearExerciseCompleted: [UUID: Bool]
    var supersetAccessories: [Int: SupersetAccessoryData]
    var prsAchieved: [WorkoutPRRecord]
    var amrapResults: [String: WorkoutAMRAPResult]
    var structuredLoggedReps: [UUID: [Int: Int]]
    // Optional: sessions saved by earlier builds don't have these
    var completionHistory: [CompletedSetRecord]?
    var finishedEarly: Bool?
    var restOverrides: [UUID: Int]?
    var restingExerciseId: UUID?
    var timerDuration: Int
    var timerIsRunning: Bool
    var timerIsPaused: Bool
    var showingTimer: Bool
    var timerEndDate: Date?
    var timerPausedRemaining: Int?
}

/// A workout in progress, saved on every change so it survives an app kill. Weights are
/// a snapshot from session start, so progression changes can't shift a resumed session.
/// Kept apart from `UserData`: a bad saved session must never put user data at risk.
struct PersistedWorkoutSession: Codable, Equatable {
    static let currentVersion = 1

    /// A session untouched for this long gets a resume-or-discard question on launch.
    static let staleInterval: TimeInterval = 12 * 60 * 60

    var version = PersistedWorkoutSession.currentVersion
    var id: UUID
    var week: Int
    var day: Int
    var programId: String?
    var cycleStartDate: Date
    var startedAt: Date
    var lastUpdatedAt: Date
    /// The Watch's id for this workout, so a relaunch continues its session
    var watchWorkoutId: String?
    var state: WorkoutStateSnapshot
    /// Lifts an earlier build left awaiting a result on its question sheet. Results now
    /// log as the lift finishes, so these are only read, to log them on restore.
    var pendingLinearExercise: WorkoutExercise?
    var queuedLinearExercises: [WorkoutExercise]?

    /// Nil for anything unreadable or from another format version. Never throws:
    /// a bad saved session is dropped rather than blocking launch.
    static func decode(_ data: Data) -> PersistedWorkoutSession? {
        do {
            let session = try JSONDecoder().decode(PersistedWorkoutSession.self, from: data)
            guard session.version == currentVersion else {
                Logger.error("Dropping saved workout with unknown version \(session.version)", category: .general)
                return nil
            }
            return session
        } catch {
            Logger.error("Dropping unreadable saved workout: \(error)", category: .general)
            return nil
        }
    }

    /// Whether this session still fits the current program and cycle and points at a
    /// real set. A cycle or program change clears the session, but a kill at the wrong
    /// moment could leave one behind.
    func isResumable(programId currentProgramId: String?, cycleStartDate currentCycleStart: Date) -> Bool {
        guard programId == currentProgramId,
              abs(cycleStartDate.timeIntervalSince(currentCycleStart)) < 1,
              state.exercises.indices.contains(state.currentExerciseIndex) else { return false }
        let totalSets = state.exercises[state.currentExerciseIndex].totalSets
        return (1...max(1, totalSets)).contains(state.currentSetNumber)
    }

    func isStale(now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastUpdatedAt) > Self.staleInterval
    }

    /// When a Fitness workout rebuilt after a relaunch should start. HKWorkoutBuilder
    /// doesn't survive a kill, but the saved workout only holds its dates and totals,
    /// so backdating to the real start gives the same result. A session resumed long
    /// after it began starts from now, or Fitness would show a half-day workout.
    func fitnessStartDate(now: Date = Date()) -> Date {
        now.timeIntervalSince(startedAt) > Self.staleInterval ? now : startedAt
    }
}
