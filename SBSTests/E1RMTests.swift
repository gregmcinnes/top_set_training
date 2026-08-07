import XCTest
@testable import SBSApp

/// Tests for the shared E1RM (Epley) utility and the AMRAP "new 1RM" hint threshold
final class E1RMTests: XCTestCase {

    // MARK: - epley

    func testEpleyKnownValues() {
        XCTAssertEqual(E1RM.epley(weight: 300, reps: 5), 350, accuracy: 0.0001)
        XCTAssertEqual(E1RM.epley(weight: 100, reps: 10), 100 * (1 + 10.0 / 30.0), accuracy: 0.0001)
    }

    func testEpleySingleRep() {
        // epley(w, 1) = w * 31/30 (known Epley quirk, matches all existing call sites)
        XCTAssertEqual(E1RM.epley(weight: 300, reps: 1), 300 * 31.0 / 30.0, accuracy: 0.0001)
    }

    func testEpleyInvalidInputs() {
        XCTAssertEqual(E1RM.epley(weight: 0, reps: 5), 0)
        XCTAssertEqual(E1RM.epley(weight: -100, reps: 5), 0)
        XCTAssertEqual(E1RM.epley(weight: 100, reps: 0), 0)
        XCTAssertEqual(E1RM.epley(weight: 100, reps: -1), 0)
    }

    // MARK: - repsNeeded

    func testRepsNeededStrictInequalityAtTie() {
        // epley(300, 5) == 350 exactly - a tie is not a PR, so 6 reps are needed
        XCTAssertEqual(E1RM.repsNeeded(toExceed: 350, atWeight: 300), 6)
    }

    func testRepsNeededClampsToOne() {
        // Weight alone already exceeds the target E1RM
        XCTAssertEqual(E1RM.repsNeeded(toExceed: 100, atWeight: 200), 1)
    }

    func testRepsNeededInvalidWeight() {
        XCTAssertNil(E1RM.repsNeeded(toExceed: 350, atWeight: 0))
        XCTAssertNil(E1RM.repsNeeded(toExceed: 350, atWeight: -10))
    }

    func testRepsNeededBoundarySweep() {
        // For any (w, n): beating exactly epley(w, n) requires n + 1 reps
        let cases: [(Double, Int)] = [(300, 5), (225, 1), (135, 12), (405, 3), (62.5, 8), (100, 30)]
        for (weight, reps) in cases {
            let e1rm = E1RM.epley(weight: weight, reps: reps)
            XCTAssertEqual(E1RM.repsNeeded(toExceed: e1rm, atWeight: weight), reps + 1,
                           "weight \(weight), reps \(reps)")
        }
    }

    func testRepsNeededResultActuallyExceedsTarget() {
        let targets: [(Double, Double)] = [(350, 300), (500, 315), (180.4, 152.5), (100, 99.9)]
        for (target, weight) in targets {
            guard let n = E1RM.repsNeeded(toExceed: target, atWeight: weight) else {
                XCTFail("Expected reps for target \(target) at weight \(weight)")
                continue
            }
            XCTAssertGreaterThan(E1RM.epley(weight: weight, reps: n), target)
            if n > 1 {
                XCTAssertLessThanOrEqual(E1RM.epley(weight: weight, reps: n - 1), target)
            }
        }
    }

    // MARK: - newPRRepThreshold

    func testThresholdShownWithinWindow() {
        // Best 350 at weight 300, target 5+: needs 6 reps; 6 <= 5 + 5 so shown
        XCTAssertEqual(E1RM.newPRRepThreshold(weight: 300, targetReps: 5, bestE1RM: 350), 6)
    }

    func testThresholdWindowEdges() {
        // needed == target + window -> shown; needed == target + window + 1 -> hidden
        // epley(100, 13) = 143.33; target 8: 13 == 8 + 5 -> shown
        let bestAt13 = E1RM.epley(weight: 100, reps: 12)  // needs 13 to beat
        XCTAssertEqual(E1RM.newPRRepThreshold(weight: 100, targetReps: 8, bestE1RM: bestAt13), 13)
        // needs 14 to beat -> 14 > 8 + 5 -> hidden
        let bestAt14 = E1RM.epley(weight: 100, reps: 13)
        XCTAssertNil(E1RM.newPRRepThreshold(weight: 100, targetReps: 8, bestE1RM: bestAt14))
    }

    func testThresholdHeavySingle() {
        // 1+ set: needed 6 -> shown (6 <= 1 + 5); needed 7 -> hidden
        let bestAt6 = E1RM.epley(weight: 300, reps: 5)
        XCTAssertEqual(E1RM.newPRRepThreshold(weight: 300, targetReps: 1, bestE1RM: bestAt6), 6)
        let bestAt7 = E1RM.epley(weight: 300, reps: 6)
        XCTAssertNil(E1RM.newPRRepThreshold(weight: 300, targetReps: 1, bestE1RM: bestAt7))
    }

    func testThresholdNoExistingPR() {
        XCTAssertNil(E1RM.newPRRepThreshold(weight: 300, targetReps: 5, bestE1RM: nil))
        XCTAssertNil(E1RM.newPRRepThreshold(weight: 300, targetReps: 5, bestE1RM: 0))
    }

    func testThresholdInvalidWeight() {
        XCTAssertNil(E1RM.newPRRepThreshold(weight: 0, targetReps: 5, bestE1RM: 350))
    }

    func testThresholdAlreadyBeatenAtOneRep() {
        // PR far below the bar weight: a single rep is a PR
        XCTAssertEqual(E1RM.newPRRepThreshold(weight: 300, targetReps: 1, bestE1RM: 200), 1)
    }
}
