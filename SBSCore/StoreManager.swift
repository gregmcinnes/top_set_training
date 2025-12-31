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
    
    // MARK: - State
    
    /// Available products from the App Store
    private(set) public var products: [Product] = []
    
    /// Set of purchased product IDs
    private(set) public var purchasedProductIDs: Set<String> = []
    
    /// Whether products are currently loading
    private(set) public var isLoading = false
    
    /// Last error that occurred
    private(set) public var lastError: Error?
    
    /// Task for listening to transaction updates
    private var updateListenerTask: Task<Void, Error>?
    
    // MARK: - Computed Properties
    
    /// Whether the user has purchased premium
    public var isPremium: Bool {
        purchasedProductIDs.contains(Self.premiumProductID)
    }
    
    /// The premium product (if loaded)
    public var premiumProduct: Product? {
        products.first { $0.id == Self.premiumProductID }
    }
    
    /// Formatted price string for the premium product
    public var premiumPriceString: String {
        premiumProduct?.displayPrice ?? "$9.99"
    }
    
    // MARK: - Initialization
    
    private init() {
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
            let productIDs = [Self.premiumProductID]
            products = try await Product.products(for: productIDs)
            isLoading = false
        } catch {
            lastError = error
            isLoading = false
            print("Failed to load products: \(error)")
        }
    }
    
    /// Purchase the premium product
    /// - Returns: The transaction if successful, nil if cancelled
    @MainActor
    public func purchasePremium() async throws -> Transaction? {
        guard let product = premiumProduct else {
            // If product not loaded, try loading first
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
            print("Failed to restore purchases: \(error)")
        }
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
                    _ = await MainActor.run {
                        self.purchasedProductIDs.insert(transaction.productID)
                    }
                    
                    // Always finish transactions
                    await transaction.finish()
                } catch {
                    print("Transaction verification failed: \(error)")
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
                
                // For non-consumables, if not revoked, user has access
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                }
            } catch {
                print("Failed to verify transaction: \(error)")
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

