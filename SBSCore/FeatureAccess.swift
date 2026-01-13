import Foundation

// MARK: - Premium Features

/// Features that require a premium purchase
public enum PremiumFeature: String, CaseIterable {
    /// Access to all programs (beyond the free ones)
    case allPrograms
    
    /// Full workout history across all cycles
    case fullHistory
    
    /// Unlimited saved custom templates
    case unlimitedTemplates
    
    /// Visual plate calculator
    case plateCalculator
    
    /// Estimated one-rep max chart
    case e1rmChart
    
    /// Superset accessories during rest periods
    case supersets
    
    /// Live Activity on lock screen and Dynamic Island
    case liveActivity
    
    /// Apple Watch companion app integration
    case watchApp
    
    /// Apple Fitness / HealthKit workout sync
    case appleFitness
    
    /// Display name for the feature
    public var displayName: String {
        switch self {
        case .allPrograms:
            return "All Training Programs"
        case .fullHistory:
            return "Full Workout History"
        case .unlimitedTemplates:
            return "Unlimited Templates"
        case .plateCalculator:
            return "Plate Calculator"
        case .e1rmChart:
            return "E1RM Progress Chart"
        case .supersets:
            return "Superset Accessories"
        case .liveActivity:
            return "Lock Screen Timer"
        case .watchApp:
            return "Apple Watch App"
        case .appleFitness:
            return "Apple Fitness Sync"
        }
    }
    
    /// Description of the feature
    public var featureDescription: String {
        switch self {
        case .allPrograms:
            return "Access 10+ programs based on popular lifting programs"
        case .fullHistory:
            return "View your complete workout history across all training cycles"
        case .unlimitedTemplates:
            return "Save unlimited custom workout templates"
        case .plateCalculator:
            return "Visual barbell display showing which plates to load"
        case .e1rmChart:
            return "Track your estimated one-rep max progress over time"
        case .supersets:
            return "Do accessory exercises during rest periods to save time"
        case .liveActivity:
            return "See your rest timer on the lock screen and Dynamic Island"
        case .watchApp:
            return "Heart rate tracking during workouts via Apple Watch"
        case .appleFitness:
            return "Automatically log workouts to Apple Fitness with calories and duration"
        }
    }
    
    /// SF Symbol icon for the feature
    public var iconName: String {
        switch self {
        case .allPrograms:
            return "doc.text.fill"
        case .fullHistory:
            return "clock.arrow.circlepath"
        case .unlimitedTemplates:
            return "square.stack.3d.up.fill"
        case .plateCalculator:
            return "circle.grid.2x1.fill"
        case .e1rmChart:
            return "chart.line.uptrend.xyaxis"
        case .supersets:
            return "arrow.triangle.2.circlepath"
        case .liveActivity:
            return "timer"
        case .watchApp:
            return "applewatch"
        case .appleFitness:
            return "heart.fill"
        }
    }
}

// MARK: - Feature Access Extension

extension StoreManager {
    
    // MARK: - Free Programs
    
    /// Program IDs that are available for free
    /// Beginner programs + select intermediate options
    public static let freePrograms: Set<String> = [
        "stronglifts_5x5_12week",
        "starting_strength_12week",
        "greyskull_lp_12week",
        "531_bbb_12week",
        "nsuns_5day_12week"
    ]
    
    /// Check if a premium feature is accessible
    /// - Parameter feature: The feature to check
    /// - Returns: True if the user has access (either premium or feature is free)
    public func canAccess(_ feature: PremiumFeature) -> Bool {
        // All premium features are unlocked with the single purchase
        return isPremium
    }
    
    /// Check if a program is accessible
    /// - Parameter programId: The program ID to check
    /// - Returns: True if the user has access (either premium or program is free)
    public func canAccessProgram(_ programId: String) -> Bool {
        return isPremium || Self.freePrograms.contains(programId)
    }
    
    /// Check if a program is free
    /// - Parameter programId: The program ID to check
    /// - Returns: True if the program is free
    public static func isProgramFree(_ programId: String) -> Bool {
        return freePrograms.contains(programId)
    }
    
    /// Get the list of locked features for display
    /// - Returns: Array of premium features the user doesn't have access to
    public func lockedFeatures() -> [PremiumFeature] {
        if isPremium {
            return []
        }
        return PremiumFeature.allCases
    }
    
    /// Check if the user can create a new template based on their current count
    /// - Parameter currentTemplateCount: The number of templates the user currently has
    /// - Returns: True if the user can create another template
    public func canCreateTemplate(currentTemplateCount: Int) -> Bool {
        if isPremium {
            return true  // Premium users get unlimited templates
        }
        return currentTemplateCount < FreeTierLimits.maxSavedTemplates
    }
    
    /// Get the remaining template slots for free users
    /// - Parameter currentTemplateCount: The number of templates the user currently has
    /// - Returns: Number of templates the user can still create (0 if at limit or premium with unlimited)
    public func remainingTemplateSlots(currentTemplateCount: Int) -> Int? {
        if isPremium {
            return nil  // Unlimited for premium
        }
        return max(0, FreeTierLimits.maxSavedTemplates - currentTemplateCount)
    }
}

// MARK: - Free Tier Limits

/// Constants defining the free tier limits
public enum FreeTierLimits {
    /// Number of saved templates allowed for free users
    public static let maxSavedTemplates = 1
    
    /// Number of past cycles visible to free users (most recent)
    public static let visiblePastCycles = 0
    
    /// Whether E1RM chart is available in free tier
    public static let e1rmChartEnabled = false
    
    /// Whether plate calculator is available in free tier
    public static let plateCalculatorEnabled = false
}

