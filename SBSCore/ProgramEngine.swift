import Foundation

public enum ProgramEngineError: Error {
    case invalidWeek
    case unknownLift(String)
}

public final class ProgramEngine {
    /// Weight adjustments settings (used instead of per-week JSON values)
    public var weightAdjustments: WeightAdjustments
    
    public init(weightAdjustments: WeightAdjustments = .default) {
        self.weightAdjustments = weightAdjustments
    }

    private func roundTo(_ x: Double, increment: Double) -> Double {
        guard increment > 0 else { return x }
        return (x / increment).rounded() * increment
    }

    public func perWeekAdjustment(diffReps: Int) -> Double {
        return weightAdjustments.adjustment(for: diffReps)
    }

    // Returns [week: [lift: TM]]
    public func computeTrainingMaxes(state: ProgramState, upToWeek: Int) -> [Int: [String: Double]] {
        var tms: [Int: [String: Double]] = [:]
        // week 1 starts from initial maxes
        var current: [String: Double] = state.initialMaxes
        tms[1] = current
        
        // Helper to find any log entry for a lift/week (from any day)
        func findLogEntry(lift: String, week: Int) -> LogEntry? {
            guard let dayLogs = state.logs[lift]?[week] else { return nil }
            // Return the first entry found from any day
            for (_, entry) in dayLogs {
                return entry
            }
            return nil
        }
        
        // Check if week 1 has any weight overrides - if so, back-calculate the effective TM
        for liftName in state.lifts.keys.sorted() {
            if let logEntry = findLogEntry(lift: liftName, week: 1),
               let weightOverride = logEntry.weightOverride,
               let wkData = state.lifts[liftName]?[1],
               wkData.intensity > 0 {
                // Back-calculate TM from the override: TM = weight / intensity
                let effectiveTm = weightOverride / wkData.intensity
                current[liftName] = effectiveTm
            }
        }
        tms[1] = current
        
        for wk in state.weeks {
            if wk == 1 { continue }
            guard wk <= upToWeek else { break }
            let prev = tms[wk - 1] ?? current
            var updated = prev
            for liftName in state.lifts.keys.sorted() {
                let logEntry = findLogEntry(lift: liftName, week: wk - 1)
                let delta: Double
                if let reps = logEntry?.repsLastSet, let wkDataPrev = state.lifts[liftName]?[wk - 1] {
                    let target = wkDataPrev.repOutTarget
                    let diff = reps - target
                    delta = perWeekAdjustment(diffReps: diff)
                } else {
                    // No log entry: use hit target (0% adjustment)
                    delta = weightAdjustments.hitTarget
                }
                var newTm = (prev[liftName] ?? state.initialMaxes[liftName] ?? 0.0) * (1.0 + delta)
                
                // If the current week has a weight override, use that to derive the effective TM
                // This cascades to subsequent weeks
                if let currentLogEntry = findLogEntry(lift: liftName, week: wk),
                   let weightOverride = currentLogEntry.weightOverride,
                   let wkData = state.lifts[liftName]?[wk],
                   wkData.intensity > 0 {
                    // Back-calculate TM from the override: TM = weight / intensity
                    newTm = weightOverride / wkData.intensity
                }
                
                updated[liftName] = newTm
            }
            tms[wk] = updated
        }
        return tms
    }

    public func weekPlan(state: ProgramState, week: Int, accessoryLogs: [String: AccessoryLog] = [:]) throws -> [Int: [PlanItem]] {
        guard state.weeks.contains(week) else { throw ProgramEngineError.invalidWeek }
        
        // Compute SBS TMs
        let tmsByWeek = computeTrainingMaxes(state: state, upToWeek: week)
        let sbsTMs = tmsByWeek[week] ?? [:]
        
        // Compute structured TMs (with weekly adjustments based on 1+ set performance)
        let structuredLiftInfo = gatherStructuredLiftInfo(from: state)
        let structuredTMsByWeek = computeStructuredTrainingMaxes(state: state, upToWeek: week, structuredLiftInfo: structuredLiftInfo)
        let structuredTMs = structuredTMsByWeek[week] ?? [:]
        
        // Combine TMs (structured lifts that aren't in SBS)
        var tms = sbsTMs
        for (lift, tm) in structuredTMs {
            if tms[lift] == nil {
                tms[lift] = tm
            }
        }
        // Also add initial maxes for any lifts not yet computed
        for (lift, initialMax) in state.initialMaxes {
            if tms[lift] == nil {
                tms[lift] = initialMax
            }
        }
        
        var out: [Int: [PlanItem]] = [:]
        for (day, items) in state.days {
            // Check if this day should be visible for this week
            if let visibility = state.dayVisibility, let visibleWeeks = visibility[day] {
                if !visibleWeeks.contains(week) {
                    continue  // Skip this day - not visible for this week
                }
            }
            
            var dayItems: [PlanItem] = []
            for it in items {
                switch it.type {
                case .tm:
                    guard let lift = it.lift, let tm = tms[lift] else { continue }
                    let perc = state.singleAt8Percent[lift] ?? 0.9
                    let singleW = roundTo(tm * perc, increment: state.rounding)
                    dayItems.append(.tm(name: it.name, lift: lift, trainingMax: (tm * 100).rounded() / 100, topSingleAt8: (singleW * 100).rounded() / 100))
                case .volume:
                    guard let lift = it.lift, let wkdata = state.lifts[lift]?[week], let tm = tms[lift] else { continue }
                    let intensity = wkdata.intensity
                    let calculatedWeight = roundTo(tm * intensity, increment: state.rounding)
                    
                    // Check for weight override (day-specific)
                    var displayWeight = calculatedWeight
                    var isOverridden = false
                    if let logEntry = state.logs[lift]?[week]?[day], let override = logEntry.weightOverride {
                        displayWeight = override
                        isOverridden = true
                    }
                    
                    var logged: Int? = nil
                    var nextDelta: Double? = nil
                    if let logEntry = state.logs[lift]?[week]?[day], let reps = logEntry.repsLastSet {
                        let diff = reps - wkdata.repOutTarget
                        nextDelta = perWeekAdjustment(diffReps: diff)
                        logged = reps
                    }
                    dayItems.append(.volume(
                        name: it.name,
                        lift: lift,
                        weight: (displayWeight * 100).rounded() / 100,
                        intensity: intensity,
                        sets: wkdata.sets,
                        repsPerSet: wkdata.repsPerNormalSet,
                        repOutTarget: wkdata.repOutTarget,
                        loggedRepsLastSet: logged,
                        nextWeekTmDelta: nextDelta,
                        isWeightOverridden: isOverridden,
                        calculatedWeight: (calculatedWeight * 100).rounded() / 100
                    ))
                case .accessory:
                    // Use configured sets/reps or defaults (4x10)
                    let sets = it.defaultSets ?? 4
                    let reps = it.defaultReps ?? 10
                    let lastLog = accessoryLogs[it.name]
                    dayItems.append(.accessory(name: it.name, sets: sets, reps: reps, lastLog: lastLog))
                    
                case .structured:
                    guard let lift = it.lift, let tm = tms[lift] else { continue }
                    
                    // Get sets_detail - prefer week-specific if available, fall back to static
                    let setsDetail: [SetDetail]
                    if let weekBasedSets = it.setsDetailByWeek?[String(week)] {
                        setsDetail = weekBasedSets
                    } else if let staticSets = it.setsDetail {
                        setsDetail = staticSets
                    } else {
                        continue
                    }
                    
                    // Skip exercise if no sets for this week (e.g., deload week with no BBB)
                    guard !setsDetail.isEmpty else { continue }
                    
                    // Get logged AMRAP reps for this lift/week/day
                    let logEntry = state.structuredLogs[lift]?[week]?[day]
                    
                    // Build set info array with calculated weights
                    var setInfos: [StructuredSetInfo] = []
                    for (index, setDetail) in setsDetail.enumerated() {
                        let weight = roundTo(tm * setDetail.intensity, increment: state.rounding)
                        let loggedReps = setDetail.isAMRAP ? logEntry?.amrapReps[index] : nil
                        
                        setInfos.append(StructuredSetInfo(
                            setIndex: index,
                            intensity: setDetail.intensity,
                            targetReps: setDetail.reps,
                            isAMRAP: setDetail.isAMRAP,
                            weight: (weight * 100).rounded() / 100,
                            loggedReps: loggedReps
                        ))
                    }
                    
                    dayItems.append(.structured(
                        name: it.name,
                        lift: lift,
                        trainingMax: (tm * 100).rounded() / 100,
                        sets: setInfos,
                        logEntry: logEntry
                    ))
                    
                case .linear:
                    guard let lift = it.lift else { continue }
                    
                    // Compute linear progression weight for this specific session (week, day)
                    let (weight, consecutiveFailures) = computeLinearWeightForSession(
                        state: state,
                        lift: lift,
                        week: week,
                        day: day
                    )
                    
                    // Get log entry for this specific week/day
                    let logEntry = state.linearLogs[lift]?[week]?[day]
                    
                    // Get increment and deload info from config
                    let config = state.linearProgressionConfig ?? LinearProgressionConfig()
                    let increment = config.increment(for: lift)
                    let isDeloadPending = consecutiveFailures >= (config.failuresBeforeDeload - 1)
                    
                    let info = LinearExerciseInfo(
                        lift: lift,
                        weight: roundTo(weight, increment: state.rounding),
                        sets: it.sets ?? 5,
                        reps: it.reps ?? 5,
                        consecutiveFailures: consecutiveFailures,
                        increment: increment,
                        isDeloadPending: isDeloadPending,
                        logEntry: logEntry
                    )
                    
                    dayItems.append(.linear(name: it.name, info: info))
                }
            }
            out[day] = dayItems
        }
        return out
    }
    
    // MARK: - Structured Exercise Progression
    
    /// Gather info about all structured lifts and their primary (1+) AMRAP sets from program state
    public func gatherStructuredLiftInfo(from state: ProgramState) -> [String: (setIndex: Int, intensity: Double)] {
        var liftInfo: [String: (setIndex: Int, intensity: Double)] = [:]
        
        for (_, items) in state.days {
            for item in items {
                guard item.type == .structured,
                      let lift = item.lift,
                      liftInfo[lift] == nil else { continue }
                
                // Get sets_detail - prefer static, or use week 1 from week-based
                // Note: Must use explicit ["1"] key, not .values.first, because dictionaries are unordered
                // Using .values.first could return week 4 (deload) which has no AMRAP sets
                let setsDetail: [SetDetail]
                if let staticSets = item.setsDetail {
                    setsDetail = staticSets
                } else if let weekBasedSets = item.setsDetailByWeek?["1"] {
                    setsDetail = weekBasedSets
                } else {
                    continue
                }
                
                // Find the 1+ set (AMRAP with target of 1 rep)
                for (index, setDetail) in setsDetail.enumerated() {
                    if setDetail.isAMRAP && setDetail.reps == 1 {
                        liftInfo[lift] = (index, setDetail.intensity)
                        break
                    }
                }
                
                // Fallback: find any AMRAP set with highest intensity
                if liftInfo[lift] == nil {
                    let amrapSets = setsDetail.enumerated().filter { $0.element.isAMRAP }
                    if let primary = amrapSets.max(by: { $0.element.intensity < $1.element.intensity }) {
                        liftInfo[lift] = (primary.offset, primary.element.intensity)
                    }
                }
            }
        }
        
        return liftInfo
    }
    
    /// Determine if a lift is upper body based on its name
    public func isUpperBodyLift(_ liftName: String) -> Bool {
        let lowerBodyKeywords = ["squat", "deadlift", "leg", "lunge", "hip"]
        let lowercased = liftName.lowercased()
        return !lowerBodyKeywords.contains { lowercased.contains($0) }
    }
    
    /// Calculate TM adjustment for structured exercises based on the 1+ set performance
    /// Uses fixed weight increases (in lbs):
    /// Upper body: 0 reps = -5, 1 rep = 0, 2-3 reps = +5, 4+ reps = +10
    /// Lower body: 0 reps = 0, 1 rep = +5, 2-3 reps = +10, 4+ reps = +15
    public func structuredProgression(repsOnOnePlus: Int, isUpperBody: Bool, rounding: Double = 5.0) -> Double {
        let adjustment: Double
        
        if isUpperBody {
            switch repsOnOnePlus {
            case 0:
                adjustment = -5.0
            case 1:
                adjustment = 0.0
            case 2, 3:
                adjustment = 5.0
            default: // 4+
                adjustment = 10.0
            }
        } else {
            // Lower body - more aggressive progression
            switch repsOnOnePlus {
            case 0:
                adjustment = 0.0  // Don't reduce for lower body, just stall
            case 1:
                adjustment = 5.0
            case 2, 3:
                adjustment = 10.0
            default: // 4+
                adjustment = 15.0
            }
        }
        
        // Round to the configured increment
        return roundTo(adjustment, increment: rounding)
    }
    
    /// Compute training maxes for structured lifts
    /// Uses weekly TM adjustments based on 1+ set performance
    public func computeStructuredTrainingMaxes(
        state: ProgramState,
        upToWeek: Int,
        structuredLiftInfo: [String: (setIndex: Int, intensity: Double)]  // lift name -> 1+ set info
    ) -> [Int: [String: Double]] {
        var tms: [Int: [String: Double]] = [:]
        
        // Helper to find any structured log entry for a lift/week (from any day)
        func findStructuredLogEntry(lift: String, week: Int) -> StructuredLogEntry? {
            guard let dayLogs = state.structuredLogs[lift]?[week] else { return nil }
            // Return the first entry found from any day
            for (_, entry) in dayLogs {
                return entry
            }
            return nil
        }
        
        // Week 1 starts from initial maxes
        var current: [String: Double] = [:]
        for lift in structuredLiftInfo.keys {
            current[lift] = state.initialMaxes[lift] ?? 0
        }
        tms[1] = current
        
        for wk in state.weeks {
            if wk == 1 { continue }
            guard wk <= upToWeek else { break }
            
            let prev = tms[wk - 1] ?? current
            var updated = prev
            
            for (liftName, setInfo) in structuredLiftInfo {
                // Check if there's a logged 1+ set from the previous week (any day)
                if let logEntry = findStructuredLogEntry(lift: liftName, week: wk - 1),
                   let reps = logEntry.amrapReps[setInfo.setIndex] {
                    // Apply structured progression
                    let isUpper = isUpperBodyLift(liftName)
                    let adjustment = structuredProgression(repsOnOnePlus: reps, isUpperBody: isUpper, rounding: state.rounding)
                    updated[liftName] = (prev[liftName] ?? 0) + adjustment
                } else {
                    // No log: keep TM the same
                    updated[liftName] = prev[liftName] ?? state.initialMaxes[liftName] ?? 0
                }
            }
            
            tms[wk] = updated
        }
        
        return tms
    }
    
    // MARK: - Linear Progression (StrongLifts-style)
    
    /// Gather all lifts that use linear progression from the program state
    public func gatherLinearLifts(from state: ProgramState) -> Set<String> {
        var lifts: Set<String> = []
        for (_, items) in state.days {
            for item in items where item.type == .linear {
                if let lift = item.lift {
                    lifts.insert(lift)
                }
            }
        }
        return lifts
    }
    
    /// Compute the working weight and failure count for a linear progression lift at a specific session
    /// Session-based progression: finds the most recent logged session for this lift and calculates weight
    ///
    /// - Parameters:
    ///   - state: The program state containing logs and configuration
    ///   - lift: The lift name
    ///   - week: Current week
    ///   - day: Current day within the week
    /// - Returns: (weight, consecutiveFailures) for this session
    public func computeLinearWeightForSession(
        state: ProgramState,
        lift: String,
        week: Int,
        day: Int
    ) -> (weight: Double, consecutiveFailures: Int) {
        let config = state.linearProgressionConfig ?? LinearProgressionConfig()
        let initialWeight = state.initialMaxes[lift] ?? 0
        let increment = config.increment(for: lift)
        
        // Gather all logged sessions for this lift, sorted chronologically
        var allSessions: [(week: Int, day: Int, entry: LinearLogEntry)] = []
        if let liftLogs = state.linearLogs[lift] {
            for (logWeek, dayLogs) in liftLogs {
                for (logDay, entry) in dayLogs {
                    allSessions.append((logWeek, logDay, entry))
                }
            }
        }
        
        // Sort by (week, day) ascending - chronological order
        allSessions.sort { ($0.week, $0.day) < ($1.week, $1.day) }
        
        // Filter to only sessions BEFORE the current one
        let previousSessions = allSessions.filter { session in
            session.week < week || (session.week == week && session.day < day)
        }
        
        // If no previous sessions, return initial weight
        if previousSessions.isEmpty {
            return (initialWeight, 0)
        }
        
        // Process all previous sessions to compute current state
        var currentWeight = initialWeight
        var consecutiveFailures = 0
        
        for session in previousSessions {
            if session.entry.completed {
                // Success! Add weight and reset failure count
                currentWeight = roundTo(currentWeight + increment, increment: state.rounding)
                consecutiveFailures = 0
            } else {
                // Failure
                consecutiveFailures += 1
                
                if consecutiveFailures >= config.failuresBeforeDeload {
                    // Deload! Reduce weight by deload percentage, reset failures
                    currentWeight = roundTo(currentWeight * (1.0 - config.deloadPercentage), increment: state.rounding)
                    consecutiveFailures = 0
                }
                // If not enough failures for deload, weight stays the same
            }
        }
        
        return (currentWeight, consecutiveFailures)
    }
    
    /// Compute working weights for linear progression lifts (legacy week-based)
    /// Kept for backward compatibility with existing code
    /// Returns: [week: [lift: (weight: Double, consecutiveFailures: Int)]]
    public func computeLinearProgressionWeights(
        state: ProgramState,
        upToWeek: Int
    ) -> [Int: [String: (weight: Double, consecutiveFailures: Int)]] {
        // Note: This is a simplified version that doesn't account for per-day logging
        // For accurate per-session progression, use computeLinearWeightForSession instead
        guard state.linearProgressionConfig != nil else { return [:] }
        
        let linearLifts = gatherLinearLifts(from: state)
        guard !linearLifts.isEmpty else { return [:] }
        
        var result: [Int: [String: (weight: Double, consecutiveFailures: Int)]] = [:]
        
        for lift in linearLifts {
            // Get weight for the first day of each week as an approximation
            for week in 1...upToWeek {
                let (weight, failures) = computeLinearWeightForSession(state: state, lift: lift, week: week, day: 1)
                if result[week] == nil {
                    result[week] = [:]
                }
                result[week]?[lift] = (weight, failures)
            }
        }
        
        return result
    }
    
    /// Get the current failure count for a lift at a specific week
    public func getCurrentFailureCount(state: ProgramState, lift: String, week: Int) -> Int {
        let weights = computeLinearProgressionWeights(state: state, upToWeek: week)
        return weights[week]?[lift]?.consecutiveFailures ?? 0
    }
    
    /// Check if a deload will be triggered if the next session is a failure
    public func isDeloadPending(state: ProgramState, lift: String, week: Int) -> Bool {
        guard let config = state.linearProgressionConfig else { return false }
        let currentFailures = getCurrentFailureCount(state: state, lift: lift, week: week)
        return currentFailures >= (config.failuresBeforeDeload - 1)
    }
}



