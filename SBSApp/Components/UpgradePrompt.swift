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
            HStack(spacing: SBSLayout.space1) {
                Image(systemName: "lock.fill")
                    .font(SBSFonts.caption().weight(.semibold))
                    .accessibilityHidden(true)

                Text("Premium")
                    .font(SBSFonts.caption().weight(.semibold))
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, SBSLayout.space3)
            .frame(minHeight: 32)
            .selectionCell(false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unlock \(feature.displayName) with Premium")
    }

    // MARK: - Card Style

    private var cardPrompt: some View {
        HStack(spacing: SBSLayout.space3) {
            Image(systemName: feature.iconName)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            SBSAdaptiveStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.displayName)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)

                    Text("Available with Premium")
                        .font(SBSFonts.caption())
                        .foregroundStyle(Color.inkSecondary)
                }
                .layoutPriority(1)

                Spacer(minLength: SBSLayout.space2)

                // Unlock: an orange block with orange-ink text, without the primary
                // button's rule and shadow (that belongs to a screen's main action)
                Button {
                    onUpgrade?()
                } label: {
                    UpgradeUnlockLabel()
                }
                .buttonStyle(.plain)
            }

            if isDismissible {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, SBSLayout.space3)
        .padding(.leading, SBSLayout.space4)
        .padding(.trailing, isDismissible ? SBSLayout.space1 : SBSLayout.space4)
        .card()
    }

    // MARK: - Banner Style

    private var bannerPrompt: some View {
        Button {
            onUpgrade?()
        } label: {
            SBSListRow("Upgrade to Premium", showsChevron: true) {
                Image(systemName: "crown.fill")
                    .font(SBSFonts.bodyStrong())
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            } subtitle: {
                Text("Unlock \(feature.displayName.lowercased()) and more")
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
            } trailing: {
                SBSBadge(text: "Pro", variant: .pro)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

/// The unlock action inside a prompt: orange fill, orange-ink label, square.
private struct UpgradeUnlockLabel: View {
    var body: some View {
        HStack(spacing: SBSLayout.space1) {
            Image(systemName: "lock.open.fill")
                .font(SBSFonts.caption().weight(.bold))
                .accessibilityHidden(true)
            SBSButtonTitle("Unlock")
                .font(SBSFonts.caption().weight(.heavy))
                .tracking(1.0)
        }
        .foregroundStyle(Color.orangeInk)
        .padding(.horizontal, SBSLayout.space3)
        .frame(minHeight: 36)
        .fixedSize()
        .background(Color.orangeFill, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
        .contentShape(Rectangle())
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
            if blurBackground {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }

            VStack(spacing: SBSLayout.space3) {
                Image(systemName: "lock.fill")
                    .font(SBSFonts.heading())
                    .foregroundStyle(Color.ink)
                    .frame(width: 48, height: 48)
                    .selectionCell(false)
                    .accessibilityHidden(true)

                VStack(spacing: SBSLayout.space1) {
                    SBSEyebrow("Premium feature")
                        .foregroundStyle(Color.inkSecondary)

                    Text(feature.displayName)
                        .font(SBSFonts.bodyStrong())
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                }

                Button {
                    onTap?()
                } label: {
                    UpgradeUnlockLabel()
                }
                .buttonStyle(.plain)
            }
            .padding()
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
                .fill(Color.orangeSoft)
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
    .card()
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
            .font(SBSFonts.title())
            .frame(width: 300, height: 200)
            .card()

        PremiumLockOverlay(
            feature: .plateCalculator,
            onTap: { Logger.debug("Unlock tapped", category: .ui) }
        )
    }
}
