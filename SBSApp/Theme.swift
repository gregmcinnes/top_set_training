import SwiftUI

// MARK: - Color Theme

enum SBSColors {
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
    // All tokens are relative to a system text style so they scale with the
    // user's Dynamic Type setting. Each token maps to the nearest text style by
    // its original point size while preserving its original weight and design.
    //
    // Reference (text style -> default point size):
    // largeTitle 34, title 28, title2 22, title3 20, headline/body 17,
    // callout 16, subheadline 15, footnote 13, caption 12, caption2 11.

    // Large titles
    static func largeTitle() -> Font {
        // Was 34pt bold rounded -> .largeTitle
        .system(.largeTitle, design: .rounded, weight: .bold)
    }

    // Section headers
    static func title() -> Font {
        // Was 22pt bold rounded -> .title2
        .system(.title2, design: .rounded, weight: .bold)
    }

    static func title2() -> Font {
        // Was 20pt semibold rounded -> .title3
        .system(.title3, design: .rounded, weight: .semibold)
    }

    static func title3() -> Font {
        // Was 18pt semibold rounded -> nearest is .headline (17)
        .system(.headline, design: .rounded, weight: .semibold)
    }

    // Body text
    static func body() -> Font {
        // Was 17pt regular default -> .body
        .system(.body, design: .default, weight: .regular)
    }

    static func bodyBold() -> Font {
        // Was 17pt semibold default -> .body
        .system(.body, design: .default, weight: .semibold)
    }

    // Weight/number display - monospaced for alignment
    static func weight() -> Font {
        // Was 24pt bold monospaced -> nearest is .title2 (22)
        .system(.title2, design: .monospaced, weight: .bold)
    }

    static func weightLarge() -> Font {
        // Was 32pt bold monospaced -> nearest is .largeTitle (34)
        .system(.largeTitle, design: .monospaced, weight: .bold)
    }

    static func number() -> Font {
        // Was 20pt semibold monospaced -> .title3
        .system(.title3, design: .monospaced, weight: .semibold)
    }

    // Small text
    static func caption() -> Font {
        // Was 13pt medium default -> .footnote (13)
        .system(.footnote, design: .default, weight: .medium)
    }

    static func captionBold() -> Font {
        // Was 13pt semibold default -> .footnote (13)
        .system(.footnote, design: .default, weight: .semibold)
    }

    static func caption2() -> Font {
        // ~11pt smaller caption -> .caption2 (11)
        .system(.caption2, design: .default, weight: .medium)
    }

    static func label() -> Font {
        // ~10pt smallest UI captions -> relative to .caption2 (no smaller style
        // exists); semibold to keep tiny labels legible.
        .system(.caption2, design: .default, weight: .semibold)
    }

    // Very large numeral displays (timers, weight readouts). No text style is
    // as large as the original 48-56pt, so these map to .largeTitle and scale
    // from there with Dynamic Type.
    static func display() -> Font {
        .system(.largeTitle, design: .rounded, weight: .bold)
    }

    static func displayMono() -> Font {
        .system(.largeTitle, design: .monospaced, weight: .bold)
    }

    // Button text
    static func button() -> Font {
        // Was 17pt semibold rounded -> .body
        .system(.body, design: .rounded, weight: .semibold)
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
            // Shadows read as elevation in light mode but vanish on dark
            // surfaces; add a subtle top-edge stroke to convey elevation in dark.
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .strokeBorder(Color(light: .clear, dark: .white.opacity(0.08)), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: SBSLayout.shadowRadius, x: 0, y: SBSLayout.shadowY)
    }

    func sbsCardElevated() -> some View {
        self
            .background(SBSColors.surfaceElevatedFallback)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusMedium)
                    .strokeBorder(Color(light: .clear, dark: .white.opacity(0.10)), lineWidth: 1)
            )
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

// MARK: - Bar Weight Options

struct BarWeightOption: Identifiable, Hashable {
    let value: Double   // stored value, always lb
    let label: String   // display label ("45 lb" or "20 kg")
    var id: Double { value }
}

enum BarWeightOptions {
    static let lbPerKg = 1.0 / 0.45359237

    static func options(useMetric: Bool) -> [BarWeightOption] {
        if useMetric {
            return [
                BarWeightOption(value: 15 * lbPerKg, label: "15 kg"),
                BarWeightOption(value: 20 * lbPerKg, label: "20 kg"),
                BarWeightOption(value: 25 * lbPerKg, label: "25 kg"),
            ]
        } else {
            return [
                BarWeightOption(value: 35, label: "35 lb"),
                BarWeightOption(value: 45, label: "45 lb"),
                BarWeightOption(value: 55, label: "55 lb"),
            ]
        }
    }

    /// Nearest option value for a stored weight (within tolerance), else nil.
    static func selection(for current: Double, useMetric: Bool) -> Double? {
        options(useMetric: useMetric)
            .min { abs($0.value - current) < abs($1.value - current) }
            .flatMap { abs($0.value - current) <= 1.0 ? $0.value : nil }
    }
}

// MARK: - Weight Formatting

private let lbToKg = 0.45359237

extension Double {
    func formattedWeight(useMetric: Bool = false) -> String {
        let unit = useMetric ? "kg" : "lb"
        let value = useMetric ? (self * lbToKg * 10).rounded() / 10 : self

        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value)) \(unit)"
        } else {
            return String(format: "%.1f \(unit)", value)
        }
    }

    func formattedWeightShort(useMetric: Bool = false) -> String {
        let value = useMetric ? (self * lbToKg * 10).rounded() / 10 : self

        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        } else {
            return String(format: "%.1f", value)
        }
    }
}

