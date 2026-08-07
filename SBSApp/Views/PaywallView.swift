import SwiftUI
import StoreKit

// MARK: - Plan Option

enum PlanOption: String, CaseIterable {
    case weekly
    case monthly
    case lifetime

    var label: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .lifetime: return "Lifetime"
        }
    }

    var subtitle: String {
        switch self {
        case .weekly: return "Billed weekly"
        case .monthly: return "Billed monthly"
        case .lifetime: return "One-time purchase"
        }
    }

    var badgeText: String? {
        switch self {
        case .monthly: return "Best Value"
        case .lifetime: return "Forever"
        case .weekly: return nil
        }
    }

    var periodLabel: String {
        switch self {
        case .weekly: return "/wk"
        case .monthly: return "/mo"
        case .lifetime: return ""
        }
    }

    func product(from store: StoreManager) -> Product? {
        switch self {
        case .weekly: return store.weeklyProduct
        case .monthly: return store.monthlyProduct
        case .lifetime: return store.premiumProduct
        }
    }
}

// MARK: - Paywall View

/// Full-screen upgrade view with feature comparison
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    let storeManager = StoreManager.shared

    @State private var selectedPlan: PlanOption = .monthly
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showInfo = false
    @State private var infoMessage = ""
    @State private var showRedeemSheet = false
    @State private var animateIn = false

    /// True while a purchase or restore is in flight — disables the action buttons.
    private var isBusy: Bool { isPurchasing || isRestoring }

    /// Optional: The specific feature that triggered this paywall
    var triggeredByFeature: PremiumFeature?

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    SBSColors.backgroundFallback,
                    SBSColors.backgroundFallback,
                    SBSColors.accentFallback.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: SBSLayout.paddingLarge) {
                    // Header
                    headerSection
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 20)

                    // Feature list
                    featuresSection
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 30)

                    // Plan selection
                    planSelectionSection
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 35)

                    // Purchase button
                    purchaseSection
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 40)

                    // Restore purchases & redeem code
                    restoreSection
                        .opacity(animateIn ? 1 : 0)

                    Spacer(minLength: 50)
                }
                .padding()
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(SBSColors.textTertiaryFallback)
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Purchases", isPresented: $showInfo) {
            Button("OK") { }
        } message: {
            Text(infoMessage)
        }
        .alert("Purchase Pending", isPresented: Binding(
            get: { storeManager.purchasePending },
            set: { if !$0 { storeManager.clearPurchasePending() } }
        )) {
            Button("OK") { storeManager.clearPurchasePending() }
        } message: {
            Text("Your purchase is awaiting approval. You'll get access once it's approved.")
        }
        .offerCodeRedemption(isPresented: $showRedeemSheet) { result in
            // Refresh entitlements after redemption; the transaction listener also
            // picks up a successful redeem. Cancellation is a no-op here.
            if case .failure(let error) = result {
                Logger.error("Offer code redemption failed: \(error)", category: .store)
            }
            Task { await storeManager.refreshEntitlements() }
        }
        .task {
            // Retry the product fetch if it hasn't succeeded yet (e.g. launched offline).
            if storeManager.products.isEmpty {
                await storeManager.loadProducts()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateIn = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            // Crown icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                SBSColors.accentFallback.opacity(0.2),
                                SBSColors.accentFallback.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "crown.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: SBSLayout.paddingSmall) {
                Text("Unlock Premium")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(SBSColors.textPrimaryFallback)

                Text("Get the most out of your training")
                    .font(SBSFonts.body())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .multilineTextAlignment(.center)
            }

            // If triggered by a specific feature, highlight it
            if let feature = triggeredByFeature {
                HStack(spacing: SBSLayout.paddingSmall) {
                    Image(systemName: feature.iconName)
                        .font(.system(size: 14))
                    Text(feature.displayName)
                        .font(SBSFonts.captionBold())
                }
                .foregroundStyle(SBSColors.accentFallback)
                .padding(.horizontal, SBSLayout.paddingMedium)
                .padding(.vertical, SBSLayout.paddingSmall)
                .background(
                    Capsule()
                        .fill(SBSColors.accentFallback.opacity(0.12))
                )
            }
        }
        .padding(.top, 60)
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            Text("What's Included")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: SBSLayout.paddingSmall) {
                ForEach(PremiumFeature.allCases, id: \.rawValue) { feature in
                    PremiumFeatureRow(feature: feature)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
        )
    }

    // MARK: - Plan Selection Section

    private var planSelectionSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            Text("Choose Your Plan")
                .font(SBSFonts.title3())
                .foregroundStyle(SBSColors.textPrimaryFallback)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: SBSLayout.paddingSmall) {
                ForEach(PlanOption.allCases, id: \.rawValue) { plan in
                    PlanOptionCard(
                        plan: plan,
                        product: plan.product(from: storeManager),
                        isSelected: selectedPlan == plan
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPlan = plan
                        }
                        Haptics.selection()
                    }
                }
            }

            // Inline retry if pricing failed to load (e.g. launched offline).
            if storeManager.loadState == .failed && storeManager.products.isEmpty {
                loadFailedRow
            }
        }
    }

    private var loadFailedRow: some View {
        HStack(spacing: SBSLayout.paddingSmall) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SBSColors.warning)
            Text("Couldn't load pricing.")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textSecondaryFallback)

            Spacer()

            Button {
                Task { await storeManager.loadProducts() }
            } label: {
                Text("Retry")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(SBSColors.accentFallback)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
        )
    }

    // MARK: - Purchase Section

    private var purchaseSection: some View {
        VStack(spacing: SBSLayout.paddingSmall) {
            // Purchase button — disabled until the selected product has actually
            // loaded, so we never let the user tap "buy" on a price we can't show.
            let selectedProduct = selectedPlan.product(from: storeManager)
            Button {
                Task {
                    await purchaseSelectedPlan()
                }
            } label: {
                HStack(spacing: SBSLayout.paddingSmall) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "crown.fill")
                        Text(selectedPlan == .lifetime ? "Unlock Forever" : "Subscribe Now")
                    }
                }
                .font(SBSFonts.button())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SBSLayout.paddingMedium + 4)
                .background(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusLarge)
                        .fill(
                            LinearGradient(
                                colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(selectedProduct == nil ? 0.5 : 1)
                )
            }
            .disabled(isBusy || selectedProduct == nil)

            if selectedPlan != .lifetime {
                Text("Cancel anytime. Subscription auto-renews.")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                    .multilineTextAlignment(.center)
            }

            Text("By purchasing, you agree to our [Terms of Use](https://gregorymcinnes.com/terms) and [Privacy Policy](https://gregorymcinnes.com/apps/top-set-training/).")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textTertiaryFallback)
                .multilineTextAlignment(.center)
                .tint(SBSColors.accentFallback)
        }
    }

    // MARK: - Restore Section

    private var restoreSection: some View {
        HStack(spacing: SBSLayout.paddingLarge) {
            Button {
                Task {
                    await restorePurchases()
                }
            } label: {
                HStack(spacing: 6) {
                    if isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Restore Purchases")
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.accentFallback)
                }
            }
            .disabled(isBusy)

            Button {
                showRedeemSheet = true
            } label: {
                Text("Redeem Code")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.accentFallback)
            }
            .disabled(isBusy)
        }
        .padding(.top, SBSLayout.paddingSmall)
    }

    // MARK: - Actions

    private func purchaseSelectedPlan() async {
        guard let product = selectedPlan.product(from: storeManager) else {
            // Try loading products first
            await storeManager.loadProducts()
            guard let product = selectedPlan.product(from: storeManager) else {
                errorMessage = "Product not available. Please try again."
                showError = true
                return
            }
            await doPurchase(product)
            return
        }
        await doPurchase(product)
    }

    private func doPurchase(_ product: Product) async {
        isPurchasing = true

        do {
            let transaction = try await storeManager.purchase(product)
            isPurchasing = false

            if transaction != nil {
                Haptics.success()
                dismiss()
            }
            // A `.pending` result surfaces via the storeManager.purchasePending
            // alert binding; `.userCancelled` intentionally does nothing.
        } catch {
            isPurchasing = false
            Haptics.warning()
            errorMessage = friendlyMessage(for: error)
            showError = true
        }
    }

    private func restorePurchases() async {
        isRestoring = true
        let result = await storeManager.restorePurchases()
        isRestoring = false

        switch result {
        case .restored:
            Haptics.success()
            dismiss()
        case .nothingToRestore:
            infoMessage = "No previous purchases were found for your Apple Account."
            showInfo = true
        case .failed(let error):
            Haptics.warning()
            errorMessage = friendlyMessage(for: error)
            showError = true
        }
    }

    /// Map common StoreKit errors to friendly copy, falling back to the raw
    /// description for anything unrecognized.
    private func friendlyMessage(for error: Error) -> String {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError:
                return "Couldn't reach the App Store. Check your connection and try again."
            case .userCancelled:
                return "The request was cancelled."
            case .notEntitled:
                return "This Apple Account isn't entitled to this purchase."
            case .notAvailableInStorefront:
                return "This purchase isn't available in your region's App Store."
            case .systemError:
                return "The App Store ran into a problem. Please try again in a moment."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

// MARK: - Plan Option Card

private struct PlanOptionCard: View {
    let plan: PlanOption
    let product: Product?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            // Radio indicator
            ZStack {
                Circle()
                    .stroke(isSelected ? SBSColors.accentFallback : SBSColors.textTertiaryFallback.opacity(0.4), lineWidth: 2)
                    .frame(width: 22, height: 22)

                if isSelected {
                    Circle()
                        .fill(SBSColors.accentFallback)
                        .frame(width: 14, height: 14)
                }
            }

            // Plan info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SBSLayout.paddingSmall) {
                    Text(plan.label)
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)

                    if let badge = plan.badgeText {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(SBSColors.accentFallback)
                            )
                    }
                }

                Text(plan.subtitle)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }

            Spacer()

            // Price — redacted placeholder until the real Product loads, so we
            // never render a fabricated fallback price.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if let product {
                    Text(product.displayPrice)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(SBSColors.textPrimaryFallback)

                    if !plan.periodLabel.isEmpty {
                        Text(plan.periodLabel)
                            .font(SBSFonts.caption())
                            .foregroundStyle(SBSColors.textSecondaryFallback)
                    }
                } else {
                    Text("$0.00")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                        .redacted(reason: .placeholder)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
                .overlay(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .stroke(isSelected ? SBSColors.accentFallback : Color.clear, lineWidth: 2)
                )
        )
    }
}

// MARK: - Feature Row

private struct PremiumFeatureRow: View {
    let feature: PremiumFeature

    var body: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            // Icon
            ZStack {
                Circle()
                    .fill(SBSColors.accentFallback.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: feature.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SBSColors.accentFallback)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)

                Text(feature.featureDescription)
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
                    .lineLimit(2)
            }

            Spacer()

            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(SBSColors.success)
        }
        .padding(.vertical, SBSLayout.paddingSmall)
    }
}

// MARK: - Free vs Premium Comparison (Alternative Layout)

struct FeatureComparisonRow: View {
    let feature: String
    let freeValue: String
    let premiumValue: String

    var body: some View {
        HStack {
            Text(feature)
                .font(SBSFonts.body())
                .foregroundStyle(SBSColors.textPrimaryFallback)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(freeValue)
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.textSecondaryFallback)
                .frame(width: 60)

            Text(premiumValue)
                .font(SBSFonts.captionBold())
                .foregroundStyle(SBSColors.accentFallback)
                .frame(width: 60)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
}

#Preview("Triggered by Feature") {
    PaywallView(triggeredByFeature: .plateCalculator)
}
