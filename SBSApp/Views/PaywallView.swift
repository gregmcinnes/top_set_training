import SwiftUI
import StoreKit

// MARK: - Paywall View

/// Full-screen upgrade view with feature comparison
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    
    let storeManager = StoreManager.shared
    
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var animateIn = false
    
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
                    
                    // Price and purchase
                    purchaseSection
                        .opacity(animateIn ? 1 : 0)
                        .offset(y: animateIn ? 0 : 40)
                    
                    // Restore purchases
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
    
    // MARK: - Purchase Section
    
    private var purchaseSection: some View {
        VStack(spacing: SBSLayout.paddingMedium) {
            // Price badge
            VStack(spacing: 4) {
                Text("One-Time Purchase")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textTertiaryFallback)
                
                Text(storeManager.premiumPriceString)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Unlock forever • No subscription")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            // Purchase button
            Button {
                Task {
                    await purchasePremium()
                }
            } label: {
                HStack(spacing: SBSLayout.paddingSmall) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "crown.fill")
                        Text("Upgrade Now")
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
                )
            }
            .disabled(isPurchasing)
        }
    }
    
    // MARK: - Restore Section
    
    private var restoreSection: some View {
        Button {
            Task {
                await restorePurchases()
            }
        } label: {
            Text("Restore Purchases")
                .font(SBSFonts.caption())
                .foregroundStyle(SBSColors.accentFallback)
        }
        .padding(.top, SBSLayout.paddingSmall)
    }
    
    // MARK: - Actions
    
    private func purchasePremium() async {
        isPurchasing = true
        
        do {
            let transaction = try await storeManager.purchasePremium()
            isPurchasing = false
            
            if transaction != nil {
                // Purchase successful - dismiss
                dismiss()
            }
            // If nil, user cancelled - stay on paywall
        } catch {
            isPurchasing = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func restorePurchases() async {
        isPurchasing = true
        await storeManager.restorePurchases()
        isPurchasing = false
        
        if storeManager.isPremium {
            dismiss()
        }
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

