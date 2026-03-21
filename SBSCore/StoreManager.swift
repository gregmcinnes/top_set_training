import Foundation
import StoreKit

/// Manages StoreKit 2 purchases for premium features
@Observable
public final class StoreManager {
    // MARK: - Singleton

    public static let shared = StoreManager()

    // MARK: - Product IDs

    /// The product ID for the premium unlock (one-time purchase)
    public static let premiumProductID = "com.gregorymcinnes.topsettraining.premium"

    /// The product ID for the weekly subscription
    public static let weeklyProductID = "com.gregorymcinnes.topsettraining.premium.weekly"

    /// The product ID for the monthly subscription
    public static let monthlyProductID = "com.gregorymcinnes.topsettraining.premium.monthly"

    /// All product IDs
    public static let allProductIDs: Set<String> = [
        premiumProductID,
        weeklyProductID,
        monthlyProductID
    ]

    /// Subscription product IDs
    public static let subscriptionProductIDs: Set<String> = [
        weeklyProductID,
        monthlyProductID
    ]

    // MARK: - Reviewer Unlock

    /// UserDefaults key for reviewer unlock
    private static let reviewerUnlockKey = "com.gregorymcinnes.topsettraining.reviewerUnlock"

    /// Whether the app is unlocked for Apple reviewers
    private(set) public var isReviewerUnlocked: Bool = false {
        didSet {
            UserDefaults.standard.set(isReviewerUnlocked, forKey: Self.reviewerUnlockKey)
        }
    }

    // MARK: - State

    /// Available products from the App Store
    private(set) public var products: [Product] = []

    /// Set of purchased product IDs (lifetime + active subscriptions)
    private(set) public var purchasedProductIDs: Set<String> = []

    /// Whether products are currently loading
    private(set) public var isLoading = false

    /// Last error that occurred
    private(set) public var lastError: Error?

    /// Task for listening to transaction updates
    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Computed Properties

    /// Whether the user has premium access (lifetime purchase, active subscription, or reviewer)
    public var isPremium: Bool {
        isReviewerUnlocked || purchasedProductIDs.contains(where: { Self.allProductIDs.contains($0) })
    }

    /// Whether premium access is via a subscription (not lifetime)
    public var isSubscribed: Bool {
        purchasedProductIDs.contains(where: { Self.subscriptionProductIDs.contains($0) })
    }

    /// Whether the user owns the lifetime unlock
    public var hasLifetime: Bool {
        purchasedProductIDs.contains(Self.premiumProductID)
    }

    /// The lifetime product (if loaded)
    public var premiumProduct: Product? {
        products.first { $0.id == Self.premiumProductID }
    }

    /// The weekly subscription product (if loaded)
    public var weeklyProduct: Product? {
        products.first { $0.id == Self.weeklyProductID }
    }

    /// The monthly subscription product (if loaded)
    public var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    /// Formatted price string for the premium product
    public var premiumPriceString: String {
        premiumProduct?.displayPrice ?? "$14.99"
    }

    /// Formatted price string for the weekly subscription
    public var weeklyPriceString: String {
        weeklyProduct?.displayPrice ?? "$0.99"
    }

    /// Formatted price string for the monthly subscription
    public var monthlyPriceString: String {
        monthlyProduct?.displayPrice ?? "$2.99"
    }

    // MARK: - Initialization

    private init() {
        // Load reviewer unlock state
        isReviewerUnlocked = UserDefaults.standard.bool(forKey: Self.reviewerUnlockKey)

        // Start listening for transactions immediately
        updateListenerTask = listenForTransactions()

        // Load products and check existing purchases
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Public Methods

    /// Load available products from the App Store
    @MainActor
    public func loadProducts() async {
        isLoading = true
        lastError = nil

        do {
            products = try await Product.products(for: Self.allProductIDs)
            isLoading = false
        } catch {
            lastError = error
            isLoading = false
            Logger.error("Failed to load products: \(error)", category: .store)
        }
    }

    /// Purchase the lifetime premium product
    /// - Returns: The transaction if successful, nil if cancelled
    @MainActor
    public func purchasePremium() async throws -> Transaction? {
        guard let product = premiumProduct else {
            await loadProducts()
            guard let product = premiumProduct else {
                throw StoreError.productNotFound
            }
            return try await purchase(product)
        }
        return try await purchase(product)
    }

    /// Purchase a specific product
    /// - Parameter product: The product to purchase
    /// - Returns: The transaction if successful, nil if cancelled
    @MainActor
    public func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // Check whether the transaction is verified
            let transaction = try checkVerified(verification)

            // Update the purchased products
            await updatePurchasedProducts()

            // Finish the transaction
            await transaction.finish()

            return transaction

        case .userCancelled:
            return nil

        case .pending:
            // Transaction is pending (e.g., Ask to Buy)
            return nil

        @unknown default:
            return nil
        }
    }

    /// Restore previous purchases
    @MainActor
    public func restorePurchases() async {
        do {
            // This will trigger the transaction listener for any restored purchases
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            lastError = error
            Logger.error("Failed to restore purchases: \(error)", category: .store)
        }
    }

    /// Toggle reviewer unlock (for Apple reviewers to test premium features)
    @MainActor
    public func toggleReviewerUnlock() {
        isReviewerUnlocked.toggle()
        Logger.info("Reviewer unlock toggled: \(isReviewerUnlocked)", category: .store)
    }

    // MARK: - Private Methods

    /// Listen for transaction updates (purchases, restores, etc.)
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through any transactions that haven't been finished
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    // Update the purchased products on the main actor
                    await MainActor.run {
                        Task {
                            await self.updatePurchasedProducts()
                        }
                    }

                    // Always finish transactions
                    await transaction.finish()
                } catch {
                    Logger.error("Transaction verification failed: \(error)", category: .store)
                }
            }
        }
    }

    /// Update the set of purchased product IDs
    @MainActor
    private func updatePurchasedProducts() async {
        var purchased = Set<String>()

        // Iterate through all current entitlements
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                if transaction.revocationDate == nil {
                    // For subscriptions, also check expiration
                    if let expirationDate = transaction.expirationDate {
                        if expirationDate > Date() {
                            purchased.insert(transaction.productID)
                        }
                    } else {
                        // Non-consumable (lifetime) — no expiration
                        purchased.insert(transaction.productID)
                    }
                }
            } catch {
                Logger.error("Failed to verify transaction: \(error)", category: .store)
            }
        }

        self.purchasedProductIDs = purchased
    }

    /// Verify that a transaction result is valid
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw StoreError.verificationFailed(error)
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Store Errors

public enum StoreError: LocalizedError {
    case productNotFound
    case verificationFailed(Error)
    case purchaseFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "The product could not be found."
        case .verificationFailed(let error):
            return "Transaction verification failed: \(error.localizedDescription)"
        case .purchaseFailed(let error):
            return "Purchase failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension StoreManager {
    /// Force premium status for testing (DEBUG only)
    @MainActor
    public func setDebugPremium(_ isPremium: Bool) {
        if isPremium {
            purchasedProductIDs.insert(Self.premiumProductID)
        } else {
            purchasedProductIDs.remove(Self.premiumProductID)
        }
    }
}
#endif
