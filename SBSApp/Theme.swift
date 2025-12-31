import SwiftUI

// MARK: - Color Theme

enum SBSColors {
    // Primary palette - Deep slate with warm accents
    static let background = Color("Background", bundle: nil)
    static let surface = Color("Surface", bundle: nil)
    static let surfaceElevated = Color("SurfaceElevated", bundle: nil)
    
    // Accent colors
    static let accent = Color("Accent", bundle: nil)
    static let accentSecondary = Color("AccentSecondary", bundle: nil)
    
    // Text
    static let textPrimary = Color("TextPrimary", bundle: nil)
    static let textSecondary = Color("TextSecondary", bundle: nil)
    static let textTertiary = Color("TextTertiary", bundle: nil)
    
    // Semantic colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    
    // Fallback colors (when asset catalog colors aren't set up)
    static let backgroundFallback = Color(light: .init(white: 0.96), dark: .init(white: 0.08))
    static let surfaceFallback = Color(light: .white, dark: .init(white: 0.12))
    static let surfaceElevatedFallback = Color(light: .white, dark: .init(white: 0.16))
    static let accentFallback = Color(light: .init(red: 0.95, green: 0.5, blue: 0.2), dark: .init(red: 1.0, green: 0.6, blue: 0.3))
    static let accentSecondaryFallback = Color(light: .init(red: 0.2, green: 0.4, blue: 0.8), dark: .init(red: 0.4, green: 0.6, blue: 1.0))
    static let textPrimaryFallback = Color(light: .init(white: 0.1), dark: .init(white: 0.95))
    static let textSecondaryFallback = Color(light: .init(white: 0.4), dark: .init(white: 0.6))
    static let textTertiaryFallback = Color(light: .init(white: 0.6), dark: .init(white: 0.4))
}

// MARK: - Typography

enum SBSFonts {
    // Large titles
    static func largeTitle() -> Font {
        .system(size: 34, weight: .bold, design: .rounded)
    }
    
    // Section headers
    static func title() -> Font {
        .system(size: 22, weight: .bold, design: .rounded)
    }
    
    static func title2() -> Font {
        .system(size: 20, weight: .semibold, design: .rounded)
    }
    
    static func title3() -> Font {
        .system(size: 18, weight: .semibold, design: .rounded)
    }
    
    // Body text
    static func body() -> Font {
        .system(size: 17, weight: .regular, design: .default)
    }
    
    static func bodyBold() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
    
    // Weight/number display - monospaced for alignment
    static func weight() -> Font {
        .system(size: 24, weight: .bold, design: .monospaced)
    }
    
    static func weightLarge() -> Font {
        .system(size: 32, weight: .bold, design: .monospaced)
    }
    
    static func number() -> Font {
        .system(size: 20, weight: .semibold, design: .monospaced)
    }
    
    // Small text
    static func caption() -> Font {
        .system(size: 13, weight: .medium, design: .default)
    }
    
    static func captionBold() -> Font {
        .system(size: 13, weight: .semibold, design: .default)
    }
    
    // Button text
    static func button() -> Font {
        .system(size: 17, weight: .semibold, design: .rounded)
    }
}

// MARK: - Spacing & Layout

enum SBSLayout {
    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24
    static let paddingXLarge: CGFloat = 32
    
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    
    static let cardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 24
    
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 4
}

// MARK: - View Extensions

extension View {
    func sbsCard() -> some View {
        self
            .background(SBSColors.surfaceFallback)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
            .shadow(color: .black.opacity(0.1), radius: SBSLayout.shadowRadius, x: 0, y: SBSLayout.shadowY)
    }
    
    func sbsCardElevated() -> some View {
        self
            .background(SBSColors.surfaceElevatedFallback)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
            .shadow(color: .black.opacity(0.15), radius: SBSLayout.shadowRadius, x: 0, y: SBSLayout.shadowY)
    }
    
    func sbsBackground() -> some View {
        self
            .background(SBSColors.backgroundFallback.ignoresSafeArea())
    }
}

// MARK: - Button Styles

struct SBSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SBSFonts.button())
            .foregroundStyle(.white)
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.vertical, SBSLayout.paddingMedium)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .fill(isEnabled ? SBSColors.accentFallback : SBSColors.textTertiaryFallback)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SBSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SBSFonts.button())
            .foregroundStyle(SBSColors.accentFallback)
            .padding(.horizontal, SBSLayout.paddingLarge)
            .padding(.vertical, SBSLayout.paddingMedium)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .strokeBorder(SBSColors.accentFallback, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SBSNumberPadButtonStyle: ButtonStyle {
    let isHighlighted: Bool
    
    init(isHighlighted: Bool = false) {
        self.isHighlighted = isHighlighted
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SBSFonts.number())
            .foregroundStyle(isHighlighted ? .white : SBSColors.textPrimaryFallback)
            .frame(width: 64, height: 64)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(isHighlighted ? SBSColors.accentFallback : SBSColors.surfaceFallback)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Color Extension for Light/Dark

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Weight Formatting

extension Double {
    func formattedWeight(useMetric: Bool = false) -> String {
        let value = useMetric ? self * 0.453592 : self
        let unit = useMetric ? "kg" : "lb"
        
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value)) \(unit)"
        } else {
            return String(format: "%.1f \(unit)", value)
        }
    }
    
    func formattedWeightShort(useMetric: Bool = false) -> String {
        let value = useMetric ? self * 0.453592 : self
        
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        } else {
            return String(format: "%.1f", value)
        }
    }
}

