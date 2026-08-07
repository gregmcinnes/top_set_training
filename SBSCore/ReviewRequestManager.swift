import Foundation
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// Manages the app store review request flow
/// Triggers review requests at strategic positive moments in the user experience
@MainActor
public final class ReviewRequestManager {
    
    public static let shared = ReviewRequestManager()
    
    // MARK: - Configuration
    
    /// Workout completion milestones that trigger review requests
    private let workoutMilestones: Set<Int> = [3, 10, 25, 50, 100]
    
    /// Minimum days between review requests
    private let minimumDaysBetweenRequests: Int = 30
    
    /// Minimum PRs needed before a PR can trigger a review
    private let minimumPRsBeforeReviewEligible: Int = 2
    
    // MARK: - Storage Keys
    
    private let lastReviewRequestDateKey = "sbs_last_review_request_date"
    private let completedWorkoutsCountKey = "sbs_completed_workouts_count"
    private let totalPRsAchievedKey = "sbs_total_prs_achieved"
    private let hasEverRequestedReviewKey = "sbs_has_ever_requested_review"
    
    // MARK: - Initialization

    private init() {}

    // MARK: - Deferred Presentation

    /// An eligible review request that has been recorded but not yet presented.
    ///
    /// Milestone triggers that fire during a workout-complete celebration or
    /// mid-session (workout / week / PR) must not present the rating prompt on
    /// top of that UI. Instead they stash the trigger reason here, and the
    /// workout views flush it via `presentPendingReviewRequestIfNeeded()` once
    /// the celebration/summary has been fully dismissed.
    private var pendingReviewReason: String?

    /// Whether a review request is queued to be presented after dismissal.
    public var hasPendingReviewRequest: Bool { pendingReviewReason != nil }

    // MARK: - Public API

    /// Call when a workout is completed
    /// Increments workout count and may queue a review request (presented later
    /// via `presentPendingReviewRequestIfNeeded()` once UI has settled)
    public func recordWorkoutCompleted() {
        incrementWorkoutCount()

        let count = completedWorkoutsCount

        // Check if this is a milestone workout
        if workoutMilestones.contains(count) {
            requestReviewIfEligible(reason: "workout_milestone_\(count)", deferPresentation: true)
        }
    }

    /// Call when a PR is achieved
    /// May queue a review request after the user has achieved enough PRs.
    /// The request is always deferred so it never lands on the PR celebration.
    public func recordPRAchieved() {
        incrementPRCount()

        let prCount = totalPRsAchieved

        // Only consider showing review after a few PRs (user is engaged and succeeding)
        if prCount >= minimumPRsBeforeReviewEligible {
            // Every 3 PRs after the minimum, consider showing review
            if (prCount - minimumPRsBeforeReviewEligible) % 3 == 0 {
                requestReviewIfEligible(reason: "pr_achieved_\(prCount)", deferPresentation: true)
            }
        }
    }

    /// Call when a training cycle is completed
    /// This is a strong positive moment
    public func recordCycleCompleted() {
        requestReviewIfEligible(reason: "cycle_completed")
    }

    /// Call when a training week is completed
    /// Consider showing review after completing 2+ full weeks
    public func recordWeekCompleted(weekNumber: Int) {
        // Only trigger on certain weeks to avoid being too aggressive
        if weekNumber == 2 || weekNumber == 4 || weekNumber == 8 {
            requestReviewIfEligible(reason: "week_\(weekNumber)_completed", deferPresentation: true)
        }
    }

    /// Present any queued review request, shortly after the caller has finished
    /// dismissing its celebration/summary UI so the prompt appears over a clean
    /// screen rather than on top of the celebration.
    ///
    /// Safe to call unconditionally on workout dismissal — it no-ops when
    /// nothing is queued.
    public func presentPendingReviewRequestIfNeeded() {
        guard let reason = pendingReviewReason else { return }
        pendingReviewReason = nil

        // Re-check eligibility at presentation time (e.g. still outside the
        // minimum window) before burning the request.
        guard canRequestReview() else {
            Logger.debug("Pending review request dropped - no longer eligible. Reason: \(reason)", category: .general)
            return
        }

        // Give the dismissing UI time to fully tear down before the system
        // rating prompt appears.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            Logger.debug("Presenting deferred app review. Trigger: \(reason)", category: .general)
            self.recordReviewRequest()
            self.requestReview()
        }
    }

    // MARK: - Review Request Logic

    private func requestReviewIfEligible(reason: String, deferPresentation: Bool = false) {
        guard canRequestReview() else {
            Logger.debug("Review request skipped - not eligible. Reason would have been: \(reason)", category: .general)
            return
        }

        if deferPresentation {
            // Queue it; the actual prompt is presented once the workout UI is
            // dismissed via presentPendingReviewRequestIfNeeded(). Do not record
            // the request yet so the eligibility window isn't burned if the
            // prompt is never flushed (e.g. app terminated first).
            Logger.debug("Queuing deferred app review. Trigger: \(reason)", category: .general)
            pendingReviewReason = reason
            return
        }

        Logger.debug("Requesting app review. Trigger: \(reason)", category: .general)

        // Record that we're making a request
        recordReviewRequest()

        // Request the review using modern API
        requestReview()
    }
    
    private func requestReview() {
        #if os(iOS)
        // Use the modern scene-based API for iOS 16+
        if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            AppStore.requestReview(in: windowScene)
        }
        #endif
    }
    
    private func canRequestReview() -> Bool {
        // Check if enough time has passed since last request
        if let lastRequestDate = lastReviewRequestDate {
            let daysSinceLastRequest = Calendar.current.dateComponents(
                [.day],
                from: lastRequestDate,
                to: Date()
            ).day ?? 0
            
            if daysSinceLastRequest < minimumDaysBetweenRequests {
                return false
            }
        }
        
        // If we've never requested a review, require at least 3 completed workouts
        // to ensure the user has actually used the app meaningfully
        if !hasEverRequestedReview && completedWorkoutsCount < 3 {
            return false
        }
        
        return true
    }
    
    // MARK: - Persistence
    
    private var completedWorkoutsCount: Int {
        get { UserDefaults.standard.integer(forKey: completedWorkoutsCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedWorkoutsCountKey) }
    }
    
    private var totalPRsAchieved: Int {
        get { UserDefaults.standard.integer(forKey: totalPRsAchievedKey) }
        set { UserDefaults.standard.set(newValue, forKey: totalPRsAchievedKey) }
    }
    
    private var lastReviewRequestDate: Date? {
        get { UserDefaults.standard.object(forKey: lastReviewRequestDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastReviewRequestDateKey) }
    }
    
    private var hasEverRequestedReview: Bool {
        get { UserDefaults.standard.bool(forKey: hasEverRequestedReviewKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasEverRequestedReviewKey) }
    }
    
    private func incrementWorkoutCount() {
        completedWorkoutsCount += 1
    }
    
    private func incrementPRCount() {
        totalPRsAchieved += 1
    }
    
    private func recordReviewRequest() {
        lastReviewRequestDate = Date()
        hasEverRequestedReview = true
    }
    
    // MARK: - Debug / Testing
    
    #if DEBUG
    /// Reset all review tracking data (for testing)
    public func resetAllData() {
        UserDefaults.standard.removeObject(forKey: completedWorkoutsCountKey)
        UserDefaults.standard.removeObject(forKey: totalPRsAchievedKey)
        UserDefaults.standard.removeObject(forKey: lastReviewRequestDateKey)
        UserDefaults.standard.removeObject(forKey: hasEverRequestedReviewKey)
    }
    
    /// Get current stats for debugging
    public var debugStats: String {
        """
        Completed Workouts: \(completedWorkoutsCount)
        Total PRs: \(totalPRsAchieved)
        Last Request: \(lastReviewRequestDate?.description ?? "Never")
        Has Ever Requested: \(hasEverRequestedReview)
        """
    }
    #endif
}

