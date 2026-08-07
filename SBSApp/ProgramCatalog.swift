import SwiftUI

// MARK: - Program Metadata

/// Metadata for each program (used for filtering and display).
/// Free/premium status is NOT stored here — `StoreManager.freePrograms` is the
/// single source of truth; see `showsFreeBadge(programId:...)`.
struct ProgramMeta {
    let family: String
    let level: ProgramLevel
    let focus: ProgramFocus
    let shortDescription: String
}

// MARK: - Program Catalog

/// Single source of truth for program metadata, family ordering, and free-badge rules.
/// Both the onboarding `ProgramSelector` and the `ProgramsView` browser read from here.
enum ProgramCatalog {
    static let metadata: [String: ProgramMeta] = [
        "stronglifts_5x5_12week": ProgramMeta(
            family: "Strong Lifts",
            level: .beginner,
            focus: .strength,
            shortDescription: "Classic 5×5. Simple and effective."
        ),
        "starting_strength_12week": ProgramMeta(
            family: "Starting Strength",
            level: .beginner,
            focus: .strength,
            shortDescription: "The foundational barbell program."
        ),
        "greyskull_lp_12week": ProgramMeta(
            family: "Beginner AMRAP",
            level: .beginner,
            focus: .balanced,
            shortDescription: "LP with AMRAP sets for faster progress."
        ),
        "gzclp_12week": ProgramMeta(
            family: "GZCL",
            level: .intermediate,
            focus: .balanced,
            shortDescription: "4-day tiered system: heavy, moderate, light."
        ),
        "gzclp_3day_12week": ProgramMeta(
            family: "GZCL",
            level: .intermediate,
            focus: .balanced,
            shortDescription: "3-day rotating tiered system."
        ),
        "531_triumvirate_12week": ProgramMeta(
            family: "5/3/1",
            level: .intermediate,
            focus: .strength,
            shortDescription: "Simple strength with assistance work."
        ),
        "531_bbb_12week": ProgramMeta(
            family: "5/3/1",
            level: .intermediate,
            focus: .balanced,
            shortDescription: "Strength + 5×10 volume for size."
        ),
        "531_fsl_12week": ProgramMeta(
            family: "5/3/1",
            level: .intermediate,
            focus: .strength,
            shortDescription: "Strength + 5×5 at first set weight."
        ),
        "nsuns_4day_12week": ProgramMeta(
            family: "nSuns",
            level: .intermediate,
            focus: .strength,
            shortDescription: "High volume, 4 days per week."
        ),
        "nsuns_5day_12week": ProgramMeta(
            family: "nSuns",
            level: .intermediate,
            focus: .strength,
            shortDescription: "Maximum volume, 5 days per week."
        ),
        "nsuns_6day_squat_12week": ProgramMeta(
            family: "nSuns",
            level: .intermediate,
            focus: .strength,
            shortDescription: "5-day plus extra squat volume day."
        ),
        "nsuns_6day_deadlift_12week": ProgramMeta(
            family: "nSuns",
            level: .intermediate,
            focus: .strength,
            shortDescription: "5-day plus extra deadlift volume day."
        ),
        "phul_12week": ProgramMeta(
            family: "PHUL",
            level: .intermediate,
            focus: .balanced,
            shortDescription: "4-day power & hypertrophy upper/lower split."
        ),
        "reddit_ppl_12week": ProgramMeta(
            family: "PPL",
            level: .intermediate,
            focus: .hypertrophy,
            shortDescription: "Push/Pull/Legs split, twice per week."
        ),
        "basic_ppl_12week": ProgramMeta(
            family: "PPL",
            level: .beginner,
            focus: .hypertrophy,
            shortDescription: "Simple 3-day Push/Pull/Legs with progression."
        ),
        "back_friendly_hypertrophy_12week": ProgramMeta(
            family: "Back-Friendly",
            level: .intermediate,
            focus: .hypertrophy,
            shortDescription: "5-day hypertrophy split with low spinal loading."
        ),
        "sbs_program_config": ProgramMeta(
            family: "SBS",
            level: .advanced,
            focus: .hypertrophy,
            shortDescription: "20-week auto-regulated hypertrophy."
        )
    ]

    /// Display order for program families.
    static let familyOrder: [String] = [
        "Strong Lifts", "Starting Strength", "Beginner AMRAP", "GZCL",
        "5/3/1", "nSuns", "PHUL", "PPL", "Back-Friendly", "SBS"
    ]

    /// Sort index for a family name (unknown families sort last).
    static func familySortIndex(_ family: String) -> Int {
        familyOrder.firstIndex(of: family) ?? 99
    }

    /// Whether the FREE badge should be shown. Only surfaced to non-premium users.
    /// Reads `StoreManager.freePrograms` so the badge can never disagree with gating.
    static func showsFreeBadge(programId: String, isLocked: Bool, isPremiumUser: Bool) -> Bool {
        StoreManager.isProgramFree(programId) && !isLocked && !isPremiumUser
    }
}
