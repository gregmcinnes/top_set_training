import XCTest
@testable import SBSApp

/// Tests for free-tier program gating.
///
/// The free tier is beginner linear-progression programs only; intermediate
/// programs (nSuns, 5/3/1, ...) are the premium upgrade. Custom templates are
/// never gated at selection — their limit is enforced at creation time.
final class FeatureAccessTests: XCTestCase {

    // MARK: - Free program set

    func testFreeTierIsBeginnerProgramsOnly() {
        XCTAssertEqual(
            StoreManager.freePrograms,
            [
                "stronglifts_5x5_12week",
                "starting_strength_12week",
                "greyskull_lp_12week"
            ]
        )
    }

    func testGraduationProgramsAreNotFree() {
        // These two were free before 2026-07-15; they are the programs users
        // graduate to from a beginner LP, i.e. the premium upgrade moment.
        XCTAssertFalse(StoreManager.isProgramFree("nsuns_5day_12week"))
        XCTAssertFalse(StoreManager.isProgramFree("531_bbb_12week"))
    }

    func testBeginnerProgramsAreFree() {
        XCTAssertTrue(StoreManager.isProgramFree("stronglifts_5x5_12week"))
        XCTAssertTrue(StoreManager.isProgramFree("starting_strength_12week"))
        XCTAssertTrue(StoreManager.isProgramFree("greyskull_lp_12week"))
    }

    // MARK: - Program access

    @MainActor
    func testFreeUserCanAccessFreeProgramsOnly() {
        let store = StoreManager.shared
        guard !store.isPremium else {
            // Unit-test environment should have no entitlements; if it somehow
            // does, this test can't exercise the free path.
            return
        }
        XCTAssertTrue(store.canAccessProgram("stronglifts_5x5_12week"))
        XCTAssertFalse(store.canAccessProgram("nsuns_5day_12week"))
        XCTAssertFalse(store.canAccessProgram("531_bbb_12week"))
        XCTAssertFalse(store.canAccessProgram("sbs_program_config"))
    }

    @MainActor
    func testCustomTemplatesAreAlwaysAccessible() {
        let store = StoreManager.shared
        let templateProgramId = UserData.programId(for: UUID())
        XCTAssertTrue(UserData.isCustomTemplate(programId: templateProgramId))
        XCTAssertTrue(store.canAccessProgram(templateProgramId))
    }

    // MARK: - Catalog consistency

    func testCatalogHasNoIndependentFreeFlag() {
        // The FREE badge must derive from StoreManager.freePrograms. Every free
        // program should exist in the catalog metadata, and the badge helper
        // must agree with the gating source of truth.
        for programId in StoreManager.freePrograms {
            XCTAssertNotNil(
                ProgramCatalog.metadata[programId],
                "Free program \(programId) missing from ProgramCatalog"
            )
            XCTAssertTrue(
                ProgramCatalog.showsFreeBadge(programId: programId, isLocked: false, isPremiumUser: false)
            )
        }
        XCTAssertFalse(
            ProgramCatalog.showsFreeBadge(programId: "nsuns_5day_12week", isLocked: true, isPremiumUser: false)
        )
        XCTAssertFalse(
            ProgramCatalog.showsFreeBadge(programId: "531_bbb_12week", isLocked: true, isPremiumUser: false)
        )
    }
}
