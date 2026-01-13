import SwiftUI

// MARK: - Upgrade Prompt Styles

/// Different styles for upgrade prompts
enum UpgradePromptStyle {
    /// Compact inline prompt - minimal space
    case compact
    /// Standard card prompt - for inline use in lists
    case card
    /// Banner style - full width
    case banner
}

// MARK: - Upgrade Prompt

/// A subtle, non-intrusive prompt to encourage upgrading to premium
struct UpgradePrompt: View {
    /// The feature this prompt is related to
    let feature: PremiumFeature
    
    /// Style of the prompt
    var style: UpgradePromptStyle = .card
    
    /// Called when the user taps to upgrade
    var onUpgrade: (() -> Void)?
    
    /// Called when the user dismisses (only for dismissible prompts)
    var onDismiss: (() -> Void)?
    
    /// Whether the prompt can be dismissed
    var isDismissible: Bool = false
    
    var body: some View {
        switch style {
        case .compact:
            compactPrompt
        case .card:
            cardPrompt
        case .banner:
            bannerPrompt
        }
    }
    
    // MARK: - Compact Style
    
    private var compactPrompt: some View {
        Button {
            onUpgrade?()
        } label: {
            HStack(spacing: SBSLayout.paddingSmall) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                
                Text("Premium")
                    .font(SBSFonts.captionBold())
            }
            .foregroundStyle(SBSColors.accentFallback)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(SBSColors.accentFallback.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Card Style
    
    private var cardPrompt: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            // Icon
            ZStack {
                Circle()
                    .fill(SBSColors.accentFallback.opacity(0.12))
                    .frame(width: 40, height: 40)
                
                Image(systemName: feature.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SBSColors.accentFallback)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Available with Premium")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            // Unlock button
            Button {
                onUpgrade?()
            } label: {
                Text("Unlock")
                    .font(SBSFonts.captionBold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(SBSColors.accentFallback)
                    )
            }
            .buttonStyle(.plain)
            
            // Dismiss button (if applicable)
            if isDismissible {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SBSColors.textTertiaryFallback)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(SBSColors.surfaceFallback)
                .overlay(
                    RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                        .strokeBorder(SBSColors.accentFallback.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Banner Style
    
    private var bannerPrompt: some View {
        HStack(spacing: SBSLayout.paddingMedium) {
            Image(systemName: "crown.fill")
                .font(.system(size: 20))
                .foregroundStyle(
                    LinearGradient(
                        colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Upgrade to Premium")
                    .font(SBSFonts.bodyBold())
                    .foregroundStyle(SBSColors.textPrimaryFallback)
                
                Text("Unlock \(feature.displayName.lowercased()) and more")
                    .font(SBSFonts.caption())
                    .foregroundStyle(SBSColors.textSecondaryFallback)
            }
            
            Spacer()
            
            Button {
                onUpgrade?()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SBSColors.accentFallback)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                .fill(
                    LinearGradient(
                        colors: [
                            SBSColors.accentFallback.opacity(0.08),
                            SBSColors.accentSecondaryFallback.opacity(0.05)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
    }
}

// MARK: - Premium Lock Overlay

/// An overlay to show on premium-only content
struct PremiumLockOverlay: View {
    let feature: PremiumFeature
    var onTap: (() -> Void)?
    
    /// Whether to blur the background content
    var blurBackground: Bool = true
    
    var body: some View {
        ZStack {
            // Blur effect (optional)
            if blurBackground {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
            
            // Lock content
            VStack(spacing: SBSLayout.paddingMedium) {
                ZStack {
                    Circle()
                        .fill(SBSColors.accentFallback.opacity(0.15))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(SBSColors.accentFallback)
                }
                
                VStack(spacing: 4) {
                    Text("Premium Feature")
                        .font(SBSFonts.bodyBold())
                        .foregroundStyle(SBSColors.textPrimaryFallback)
                    
                    Text(feature.displayName)
                        .font(SBSFonts.caption())
                        .foregroundStyle(SBSColors.textSecondaryFallback)
                }
                
                Button {
                    onTap?()
                } label: {
                    HStack(spacing: SBSLayout.paddingSmall) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12))
                        Text("Unlock")
                            .font(SBSFonts.captionBold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(SBSColors.accentFallback)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Premium Badge

/// A small badge to indicate premium content
struct PremiumBadge: View {
    var isCompact: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: isCompact ? 8 : 10))
            
            if !isCompact {
                Text("PRO")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(
            LinearGradient(
                colors: [SBSColors.accentFallback, SBSColors.accentSecondaryFallback],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .padding(.horizontal, isCompact ? 6 : 8)
        .padding(.vertical, isCompact ? 3 : 4)
        .background(
            Capsule()
                .fill(SBSColors.accentFallback.opacity(0.12))
        )
    }
}

// MARK: - View Modifier for Premium Gating

extension View {
    /// Apply a premium lock overlay if the user doesn't have access
    func premiumGated(
        feature: PremiumFeature,
        showPaywall: Binding<Bool>,
        blurBackground: Bool = true
    ) -> some View {
        self.overlay {
            if !StoreManager.shared.canAccess(feature) {
                PremiumLockOverlay(
                    feature: feature,
                    onTap: { showPaywall.wrappedValue = true },
                    blurBackground: blurBackground
                )
            }
        }
    }
}

// MARK: - Previews

#Preview("Card Style") {
    VStack(spacing: 20) {
        UpgradePrompt(
            feature: .plateCalculator,
            style: .card,
            onUpgrade: { Logger.debug("Upgrade tapped", category: .ui) }
        )
        
        UpgradePrompt(
            feature: .e1rmChart,
            style: .card,
            onUpgrade: { Logger.debug("Upgrade tapped", category: .ui) },
            isDismissible: true
        )
    }
    .padding()
    .sbsBackground()
}

#Preview("Compact Style") {
    HStack {
        Text("Plate Calculator")
        Spacer()
        UpgradePrompt(
            feature: .plateCalculator,
            style: .compact,
            onUpgrade: { Logger.debug("Upgrade tapped", category: .ui) }
        )
    }
    .padding()
    .sbsCard()
    .padding()
}

#Preview("Banner Style") {
    UpgradePrompt(
        feature: .fullHistory,
        style: .banner,
        onUpgrade: { print("Upgrade tapped") }
    )
    .padding()
}

#Preview("Lock Overlay") {
    ZStack {
        Text("Premium Content Here")
            .font(.largeTitle)
            .frame(width: 300, height: 200)
            .background(Color.blue.opacity(0.3))
        
        PremiumLockOverlay(
            feature: .plateCalculator,
            onTap: { Logger.debug("Unlock tapped", category: .ui) }
        )
    }
}

#Preview("Premium Badge") {
    HStack(spacing: 20) {
        PremiumBadge()
        PremiumBadge(isCompact: true)
    }
    .padding()
    .background(Color.black)
}


