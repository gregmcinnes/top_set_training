import XCTest
@testable import SBSApp

/// Tests for WeightAdjustments and rep-based training max adjustments
final class WeightAdjustmentTests: XCTestCase {
    
    // MARK: - Default Values Tests
    
    func testDefaultWeightAdjustments() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.belowBy2Plus, -0.05)
        XCTAssertEqual(adjustments.belowBy1, -0.02)
        XCTAssertEqual(adjustments.hitTarget, 0.0)
        XCTAssertEqual(adjustments.beatBy1, 0.005)
        XCTAssertEqual(adjustments.beatBy2, 0.01)
        XCTAssertEqual(adjustments.beatBy3, 0.015)
        XCTAssertEqual(adjustments.beatBy4, 0.02)
        XCTAssertEqual(adjustments.beatBy5Plus, 0.03)
    }
    
    // MARK: - Adjustment For Rep Difference Tests
    
    func testAdjustmentBelowBy5Reps() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.adjustment(for: -5), -0.05)
        XCTAssertEqual(adjustments.adjustment(for: -10), -0.05)
    }
    
    func testAdjustmentBelowBy2Reps() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.adjustment(for: -2), -0.05)
    }
    
    func testAdjustmentBelowBy1Rep() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.adjustment(for: -1), -0.02)
    }
    
    func testAdjustmentHitTarget() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.adjustment(for: 0), 0.0)
    }
    
    func testAdjustmentBeatBy1Rep() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.adjustment(for: 1), 0.005)
    }
    
    func testAdjustmentBeatBy2Reps() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.adjustment(for: 2), 0.01)
    }
    
    func testAdjustmentBeatBy3Reps() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.adjustment(for: 3), 0.015)
    }
    
    func testAdjustmentBeatBy4Reps() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.adjustment(for: 4), 0.02)
    }
    
    func testAdjustmentBeatBy5PlusReps() {
        let adjustments = WeightAdjustments.default
        
        XCTAssertEqual(adjustments.adjustment(for: 5), 0.03)
        XCTAssertEqual(adjustments.adjustment(for: 6), 0.03)
        XCTAssertEqual(adjustments.adjustment(for: 10), 0.03)
        XCTAssertEqual(adjustments.adjustment(for: 20), 0.03)
    }
    
    // MARK: - Custom Adjustments Tests
    
    func testCustomAdjustments() {
        let custom = WeightAdjustments(
            belowBy2Plus: -0.10,
            belowBy1: -0.05,
            hitTarget: 0.0,
            beatBy1: 0.01,
            beatBy2: 0.02,
            beatBy3: 0.03,
            beatBy4: 0.04,
            beatBy5Plus: 0.05
        )
        
        XCTAssertEqual(custom.adjustment(for: -3), -0.10)
        XCTAssertEqual(custom.adjustment(for: -1), -0.05)
        XCTAssertEqual(custom.adjustment(for: 0), 0.0)
        XCTAssertEqual(custom.adjustment(for: 1), 0.01)
        XCTAssertEqual(custom.adjustment(for: 5), 0.05)
    }
    
    func testAggressiveProgression() {
        let aggressive = WeightAdjustments(
            belowBy2Plus: -0.03,
            belowBy1: -0.01,
            hitTarget: 0.01,
            beatBy1: 0.02,
            beatBy2: 0.03,
            beatBy3: 0.04,
            beatBy4: 0.05,
            beatBy5Plus: 0.075
        )
        
        // Even hitting target gives progress
        XCTAssertEqual(aggressive.adjustment(for: 0), 0.01)
        
        // Strong AMRAP gives big bump
        XCTAssertEqual(aggressive.adjustment(for: 6), 0.075)
    }
    
    func testConservativeProgression() {
        let conservative = WeightAdjustments(
            belowBy2Plus: -0.075,
            belowBy1: -0.05,
            hitTarget: -0.01,
            beatBy1: 0.0,
            beatBy2: 0.005,
            beatBy3: 0.01,
            beatBy4: 0.015,
            beatBy5Plus: 0.02
        )
        
        // Hitting target still reduces (conservative)
        XCTAssertEqual(conservative.adjustment(for: 0), -0.01)
        
        // Need +1 rep just to maintain
        XCTAssertEqual(conservative.adjustment(for: 1), 0.0)
    }
    
    // MARK: - Format Percent Tests
    
    func testFormatPercentPositive() {
        XCTAssertEqual(WeightAdjustments.formatPercent(0.03), "+3.0%")
        XCTAssertEqual(WeightAdjustments.formatPercent(0.015), "+1.5%")
        XCTAssertEqual(WeightAdjustments.formatPercent(0.005), "+0.5%")
    }
    
    func testFormatPercentNegative() {
        XCTAssertEqual(WeightAdjustments.formatPercent(-0.05), "-5.0%")
        XCTAssertEqual(WeightAdjustments.formatPercent(-0.02), "-2.0%")
    }
    
    func testFormatPercentZero() {
        XCTAssertEqual(WeightAdjustments.formatPercent(0.0), "+0.0%")
    }
    
    func testFormatPercentDecimalPrecision() {
        XCTAssertEqual(WeightAdjustments.formatPercent(0.0333), "+3.3%")
        XCTAssertEqual(WeightAdjustments.formatPercent(0.0167), "+1.7%")
    }
    
    // MARK: - Codable Tests
    
    func testWeightAdjustmentsCodable() throws {
        let original = WeightAdjustments(
            belowBy2Plus: -0.08,
            belowBy1: -0.04,
            hitTarget: 0.0,
            beatBy1: 0.01,
            beatBy2: 0.02,
            beatBy3: 0.03,
            beatBy4: 0.04,
            beatBy5Plus: 0.05
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WeightAdjustments.self, from: data)
        
        XCTAssertEqual(decoded.belowBy2Plus, original.belowBy2Plus)
        XCTAssertEqual(decoded.belowBy1, original.belowBy1)
        XCTAssertEqual(decoded.hitTarget, original.hitTarget)
        XCTAssertEqual(decoded.beatBy1, original.beatBy1)
        XCTAssertEqual(decoded.beatBy2, original.beatBy2)
        XCTAssertEqual(decoded.beatBy3, original.beatBy3)
        XCTAssertEqual(decoded.beatBy4, original.beatBy4)
        XCTAssertEqual(decoded.beatBy5Plus, original.beatBy5Plus)
    }
    
    // MARK: - Equatable Tests
    
    func testWeightAdjustmentsEquatable() {
        let adjustments1 = WeightAdjustments.default
        let adjustments2 = WeightAdjustments()
        
        XCTAssertEqual(adjustments1, adjustments2)
    }
    
    func testWeightAdjustmentsNotEqual() {
        let adjustments1 = WeightAdjustments.default
        let adjustments2 = WeightAdjustments(belowBy2Plus: -0.10)
        
        XCTAssertNotEqual(adjustments1, adjustments2)
    }
    
    // MARK: - Integration with ProgramEngine Tests
    
    func testEngineUsesDefaultAdjustments() {
        let engine = ProgramEngine()
        
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: 0), 0.0)
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: 3), 0.015)
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: -2), -0.05)
    }
    
    func testEngineUsesCustomAdjustments() {
        let engine = ProgramEngine(weightAdjustments: WeightAdjustments(
            belowBy2Plus: -0.10,
            belowBy1: -0.05,
            hitTarget: 0.01,
            beatBy1: 0.02,
            beatBy2: 0.03,
            beatBy3: 0.04,
            beatBy4: 0.05,
            beatBy5Plus: 0.06
        ))
        
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: 0), 0.01)
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: 3), 0.04)
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: -2), -0.10)
    }
    
    func testEngineAdjustmentsCanBeChanged() {
        let engine = ProgramEngine()
        
        // Start with default
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: 5), 0.03)
        
        // Change to custom
        engine.weightAdjustments = WeightAdjustments(beatBy5Plus: 0.10)
        XCTAssertEqual(engine.perWeekAdjustment(diffReps: 5), 0.10)
    }
    
    // MARK: - Real World Scenario Tests
    
    func testTMProgressionWithHitTarget() {
        let adjustments = WeightAdjustments.default
        var tm: Double = 300.0
        
        // 4 weeks of hitting target exactly
        for _ in 1...4 {
            tm *= (1.0 + adjustments.adjustment(for: 0))
        }
        
        // TM should stay the same
        XCTAssertEqual(tm, 300.0)
    }
    
    func testTMProgressionWithConsistentBeat() {
        let adjustments = WeightAdjustments.default
        var tm: Double = 300.0
        
        // 4 weeks of beating target by 2 reps
        for _ in 1...4 {
            tm *= (1.0 + adjustments.adjustment(for: 2))
        }
        
        // TM should increase by about 4% (1% per week compounded)
        XCTAssertEqual(tm, 300.0 * pow(1.01, 4), accuracy: 0.1)
    }
    
    func testTMProgressionWithMissedReps() {
        let adjustments = WeightAdjustments.default
        var tm: Double = 300.0
        
        // 2 weeks of missing by 2+ reps
        for _ in 1...2 {
            tm *= (1.0 + adjustments.adjustment(for: -3))
        }
        
        // TM should decrease by about 10% (5% per week compounded)
        XCTAssertEqual(tm, 300.0 * pow(0.95, 2), accuracy: 0.1)
    }
    
    func testTMProgressionMixed() {
        let adjustments = WeightAdjustments.default
        var tm: Double = 300.0
        
        // Realistic progression: good, ok, miss, recover
        tm *= (1.0 + adjustments.adjustment(for: 3))   // +1.5% -> 304.5
        tm *= (1.0 + adjustments.adjustment(for: 0))   // +0% -> 304.5
        tm *= (1.0 + adjustments.adjustment(for: -1))  // -2% -> 298.41
        tm *= (1.0 + adjustments.adjustment(for: 4))   // +2% -> 304.38
        
        // Should end up slightly higher than start
        XCTAssertGreaterThan(tm, 300.0)
        XCTAssertEqual(tm, 304.38, accuracy: 0.1)
    }
    
    // MARK: - Boundary Tests
    
    func testExtremePositiveDiff() {
        let adjustments = WeightAdjustments.default
        
        // Very high rep differences should cap at beatBy5Plus
        XCTAssertEqual(adjustments.adjustment(for: 100), adjustments.beatBy5Plus)
    }
    
    func testExtremeNegativeDiff() {
        let adjustments = WeightAdjustments.default
        
        // Very negative rep differences should cap at belowBy2Plus
        XCTAssertEqual(adjustments.adjustment(for: -100), adjustments.belowBy2Plus)
    }
}

