import Foundation

/// Shared estimated-1RM math (Epley formula).
public enum E1RM {
    /// Epley: weight * (1 + reps/30). Returns 0 for weight <= 0 or reps < 1.
    public static func epley(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps >= 1 else { return 0 }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    /// Smallest rep count n such that epley(weight, n) strictly exceeds targetE1RM.
    /// Returns nil if weight <= 0.
    public static func repsNeeded(toExceed targetE1RM: Double, atWeight weight: Double) -> Int? {
        guard weight > 0 else { return nil }
        var n = max(1, Int(ceil(30.0 * (targetE1RM / weight - 1.0))))
        // ceil can land exactly on (or, via float error, just under) the target;
        // PRs require strictly greater, so bump past any tie.
        var guardCount = 0
        while epley(weight: weight, reps: n) <= targetE1RM && guardCount < 2 {
            n += 1
            guardCount += 1
        }
        return n
    }

    /// Reps needed for a new PR on an AMRAP set, or nil if no hint should be shown.
    /// Shown only when a best E1RM exists, the weight is valid, and the PR is
    /// reachable within `window` reps past the AMRAP target.
    public static func newPRRepThreshold(weight: Double,
                                         targetReps: Int,
                                         bestE1RM: Double?,
                                         window: Int = 5) -> Int? {
        guard let best = bestE1RM, best > 0,
              let needed = repsNeeded(toExceed: best, atWeight: weight),
              needed <= targetReps + window else { return nil }
        return needed
    }
}
