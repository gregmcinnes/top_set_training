import SwiftUI

// MARK: - Color Theme

enum SBSColors {
    // Legacy names, now aliases for the Top Set tokens (Assets.xcassets/Colors).
    // Views move to the tokens directly; delete this enum when nothing uses it.
    static let success = Color.success
    static let warning = Color.warning
    static let error = Color.danger

    static let backgroundFallback = Color.bg
    static let surfaceFallback = Color.surface
    static let surfaceElevatedFallback = Color.surfaceRaised
    /// Orange as a fill. Text or icons on it are Color.orangeInk; orange text
    /// on bg/surface is Color.orangeText.
    static let accentFallback = Color.orangeFill
    /// No token: the blue is retired once History's charts move to ink and
    /// orange (open decision), so this keeps its old literal until then.
    static let accentSecondaryFallback = Color(light: .init(red: 0.2, green: 0.4, blue: 0.8), dark: .init(red: 0.4, green: 0.6, blue: 1.0))
    static let textPrimaryFallback = Color.ink
    static let textSecondaryFallback = Color.inkSecondary
    static let textTertiaryFallback = Color.inkTertiary
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
    static func legacyTitle() -> Font {
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
    static func legacyBody() -> Font {
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

    static func legacyNumber() -> Font {
        // Was 20pt semibold monospaced -> .title3
        .system(.title3, design: .monospaced, weight: .semibold)
    }

    // Small text
    static func legacyCaption() -> Font {
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
    static func legacyButton() -> Font {
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
    /// Legacy alias for .card().
    func sbsCard() -> some View {
        card()
    }

    /// Legacy alias. Deliberately a hairline card, never .signatureCard():
    /// the signature treatment is reserved for the live set card.
    func sbsCardElevated() -> some View {
        background(Color.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
    }

    func sbsBackground() -> some View {
        self
            .background(Color.bg.ignoresSafeArea())
    }
}

// MARK: - Button Styles

struct SBSLegacyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SBSFonts.legacyButton())
            // Never white on orange: orange-ink when enabled; bg on the grey disabled fill.
            .foregroundStyle(isEnabled ? Color.orangeInk : Color.bg)
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

struct SBSLegacySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SBSFonts.legacyButton())
            .foregroundStyle(Color.orangeText)
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

struct SBSLegacyNumberPadButtonStyle: ButtonStyle {
    let isHighlighted: Bool
    
    init(isHighlighted: Bool = false) {
        self.isHighlighted = isHighlighted
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SBSFonts.legacyNumber())
            .foregroundStyle(isHighlighted ? Color.orangeInk : SBSColors.textPrimaryFallback)
            .frame(width: 64, height: 64)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.cornerRadiusSmall)
                    .fill(isHighlighted ? SBSColors.accentFallback : SBSColors.surfaceFallback)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Top Set design system
//
// The SwiftUI side of the Top Set design system (tokens.json + SwiftUI.md in
// the design-system artifact). Colours come from Assets.xcassets/Colors as
// generated symbols (Color.ink, Color.surfaceRaised, Color.orangeFill, ...).
// The base orange token is `orangeFill` because `Color.orange` is SwiftUI's.
//
// The 2px rule, square corners and hard shadow (signatureCard, hardShadow,
// Color.rule, SBSPrimaryButtonStyle) belong on exactly three surfaces: the
// live set card, the primary button and the tab bar's top edge.

/// PostScript names of the bundled fonts (Resources/Fonts, UIAppFonts).
enum SBSFontName {
    static let archivoRegular = "Archivo-Regular"
    static let archivoMedium = "Archivo-Medium"
    static let archivoSemiBold = "Archivo-SemiBold"
    static let archivoBold = "Archivo-Bold"
    static let archivoExtraBold = "Archivo-ExtraBold"
    /// Width 112.5 instance for title-large.
    static let archivoSemiExpandedBlack = "ArchivoSemiExpanded-Black"
    /// Width 87.5 instance for eyebrows and tab labels.
    static let archivoSemiCondensedBold = "ArchivoSemiCondensed-Bold"
    static let barlowCondensedBold = "BarlowCondensed-Bold"
    static let plexMonoMedium = "IBMPlexMono-Medium"
    static let plexMonoSemiBold = "IBMPlexMono-SemiBold"
    static let plexMonoBold = "IBMPlexMono-Bold"

    static let all = [
        archivoRegular, archivoMedium, archivoSemiBold, archivoBold, archivoExtraBold,
        archivoSemiExpandedBlack, archivoSemiCondensedBold, barlowCondensedBold,
        plexMonoMedium, plexMonoSemiBold, plexMonoBold,
    ]
}

extension SBSFonts {
    // Numerals: Barlow Condensed, read from the floor. Nowhere else.
    static func workingWeight() -> Font {
        .custom(SBSFontName.barlowCondensedBold, size: 68, relativeTo: .largeTitle).monospacedDigit()
    }

    static func timer() -> Font {
        .custom(SBSFontName.barlowCondensedBold, size: 56, relativeTo: .largeTitle).monospacedDigit()
    }

    // Display: Archivo. Uppercase styles pair with the companion modifiers below.
    static func titleLarge() -> Font {
        .custom(SBSFontName.archivoSemiExpandedBlack, size: 34, relativeTo: .largeTitle)
    }

    static func title() -> Font {
        .custom(SBSFontName.archivoExtraBold, size: 24, relativeTo: .title2)
    }

    static func heading() -> Font {
        .custom(SBSFontName.archivoBold, size: 20, relativeTo: .title3)
    }

    static func body() -> Font {
        .custom(SBSFontName.archivoRegular, size: 17, relativeTo: .body)
    }

    static func bodyStrong() -> Font {
        .custom(SBSFontName.archivoSemiBold, size: 17, relativeTo: .body)
    }

    static func caption() -> Font {
        .custom(SBSFontName.archivoMedium, size: 13, relativeTo: .footnote)
    }

    static func eyebrow() -> Font {
        .custom(SBSFontName.archivoSemiCondensedBold, size: 11, relativeTo: .caption2)
    }

    static func button() -> Font {
        .custom(SBSFontName.archivoExtraBold, size: 15, relativeTo: .body)
    }

    static func tab() -> Font {
        .custom(SBSFontName.archivoSemiCondensedBold, size: 10, relativeTo: .caption2)
    }

    // Data: IBM Plex Mono for every other number. Always tabular.
    static func numberLarge() -> Font {
        .custom(SBSFontName.plexMonoBold, size: 28, relativeTo: .title2).monospacedDigit()
    }

    static func number() -> Font {
        .custom(SBSFontName.plexMonoSemiBold, size: 20, relativeTo: .title3).monospacedDigit()
    }

    static func numberSmall() -> Font {
        .custom(SBSFontName.plexMonoMedium, size: 13, relativeTo: .footnote).monospacedDigit()
    }

    static func numberUnit() -> Font {
        .custom(SBSFontName.plexMonoSemiBold, size: 16, relativeTo: .callout).monospacedDigit()
    }
}

extension SBSLayout {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    static let radiusNone: CGFloat = 0
    static let radiusSm: CGFloat = 2
    static let radiusMd: CGFloat = 4

    static let strokeRule: CGFloat = 2
    static let strokeHairline: CGFloat = 1

    static let hardShadowOffset: CGFloat = 4
    static let pressedOffset: CGFloat = 2
}

extension View {
    // Companion modifiers for the uppercase styles: font, tracking and case
    // live here so call sites pass sentence case and never set tracking.
    func titleLargeText() -> some View {
        font(SBSFonts.titleLarge()).tracking(-0.34).textCase(.uppercase)
    }

    func eyebrowText() -> some View {
        font(SBSFonts.eyebrow()).tracking(1.1).textCase(.uppercase)
    }

    func buttonText() -> some View {
        font(SBSFonts.button()).tracking(1.2).textCase(.uppercase)
    }

    func tabText() -> some View {
        font(SBSFonts.tab()).tracking(0.6).textCase(.uppercase)
    }

    /// Default card: surface, 2pt corners, 1px hairline, no shadow.
    func card() -> some View {
        background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
    }

    /// The live set card only: square, 2px rule, hard shadow. One per screen.
    func signatureCard() -> some View {
        background(Color.surface)
            .overlay(Rectangle().strokeBorder(Color.rule, lineWidth: SBSLayout.strokeRule))
            .hardShadow()
    }

    /// Hard offset shadow in ink, no blur. Live set card and primary button only.
    func hardShadow(_ isVisible: Bool = true) -> some View {
        background(
            Rectangle()
                .fill(Color.rule)
                .offset(x: SBSLayout.hardShadowOffset, y: SBSLayout.hardShadowOffset)
                .opacity(isVisible ? 1 : 0)
        )
    }
}

/// Orange fill, orange-ink label, 2px rule and hard shadow. One per screen.
/// Pressed drops the shadow and sits 2pt down and right.
struct SBSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .buttonText()
            .foregroundStyle(isEnabled ? Color.orangeInk : Color.inkTertiary)
            .padding(.horizontal, SBSLayout.space6)
            .frame(minHeight: 48)
            .background(isEnabled ? Color.orangeFill : Color.surface)
            .overlay(
                Rectangle().strokeBorder(
                    isEnabled ? Color.rule : Color.hairline,
                    lineWidth: isEnabled ? SBSLayout.strokeRule : SBSLayout.strokeHairline
                )
            )
            .hardShadow(isEnabled && !pressed)
            .offset(x: pressed ? SBSLayout.pressedOffset : 0, y: pressed ? SBSLayout.pressedOffset : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Surface fill, ink label, hairline edge.
struct SBSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SBSHairlineButtonBody(configuration: configuration, tint: .ink, edge: .hairline)
    }
}

/// Secondary with danger for label and edge. End workout, delete cycle.
struct SBSDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SBSHairlineButtonBody(configuration: configuration, tint: .danger, edge: .danger)
    }
}

private struct SBSHairlineButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let edge: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .buttonText()
            .foregroundStyle(isEnabled ? tint : Color.inkTertiary)
            .padding(.horizontal, SBSLayout.space6)
            .frame(minHeight: 48)
            .background(configuration.isPressed ? Color.surfaceRaised : Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(isEnabled ? edge : Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Number pad key: surface-raised, 2pt corners, number style. The highlighted
/// key is orange with orange-ink and no shadow.
struct SBSNumberPadButtonStyle: ButtonStyle {
    let isHighlighted: Bool

    init(isHighlighted: Bool = false) {
        self.isHighlighted = isHighlighted
    }

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let lit = isHighlighted && isEnabled
        configuration.label
            .font(SBSFonts.number())
            .foregroundStyle(lit ? Color.orangeInk : (isEnabled ? Color.ink : Color.inkTertiary))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .fill(lit ? Color.orangeFill : (configuration.isPressed ? Color.surfaceRaised : Color.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(lit ? Color.clear : Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
            .opacity(lit && configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Button Title

/// A button title for the uppercase button styles. `.textCase(.uppercase)` also
/// uppercases the accessibility label ("COMPLETE SET"), so this shows the capitals
/// itself and keeps the words as written for VoiceOver, Voice Control and UI tests.
struct SBSButtonTitle: View {
    let title: String
    var accessibilityText: String? = nil

    init(_ title: String, accessibilityLabel: String? = nil) {
        self.title = title
        self.accessibilityText = accessibilityLabel
    }

    var body: some View {
        Text(title.uppercased())
            // A button title shrinks before it wraps ("PAUS / E")
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(accessibilityText ?? title)
            // Inside the style's uppercase environment: keep the label as written
            .textCase(nil)
    }
}

/// An eyebrow label that reads as written to VoiceOver and UI tests, for the same
/// reason as SBSButtonTitle. Colour is the caller's.
struct SBSEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(SBSFonts.eyebrow())
            .tracking(1.1)
            .accessibilityLabel(text)
            .textCase(nil)
    }
}

// MARK: - Badges

/// Small uppercase tag naming a state or category. The word does the work;
/// colour only reinforces it.
struct SBSBadge: View {
    enum Variant {
        /// Surface, ink text, hairline edge (program badges: 5/3/1, AMRAP, Accessory).
        case standard
        /// The one filled badge: orange with orange-ink and a 1pt ink edge.
        case pr
        /// Surface fill, text and edge in a status colour, with a glyph where one exists.
        case status(Color)
        /// Ink fill, bg text, for paywalled features.
        case pro
    }

    let text: String
    var variant: Variant = .standard
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: SBSLayout.space1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(SBSFonts.eyebrow().weight(.bold))
            }
            Text(text)
                .eyebrowText()
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, SBSLayout.space2)
        .padding(.vertical, 3)
        .background(background, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                .strokeBorder(edge, lineWidth: SBSLayout.strokeHairline)
        )
    }

    private var foreground: Color {
        switch variant {
        case .standard: .ink
        case .pr: .orangeInk
        case .status(let color): color
        case .pro: .bg
        }
    }

    private var background: Color {
        switch variant {
        case .standard, .status: .surface
        case .pr: .orangeFill
        case .pro: .ink
        }
    }

    private var edge: Color {
        switch variant {
        case .standard: .hairline
        case .pr, .pro: .ink
        case .status(let color): color
        }
    }
}

// MARK: - Knurl

/// The diagonal knurl stripe: 1px knurl lines at 135°, 6pt pitch. Texture only,
/// never meaning. Behind the rest timer and home-screen section headers.
struct KnurlPattern: View {
    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 6
            var path = Path()
            // Lines running from bottom-left to top-right, stepped along x.
            var x = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += pitch
            }
            context.stroke(path, with: .color(.knurl), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Selected state for a choice: orange-soft fill, 1px orange-text edge,
    /// 2pt corners. Unselected is surface with a hairline.
    func selectionCell(_ isSelected: Bool) -> some View {
        background(isSelected ? Color.orangeSoft : Color.surface, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(isSelected ? Color.orangeText : Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
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

    /// Move rounding and bar weight onto the new unit's grid when the unit changes:
    /// 2.5 kg rounding and a 20 kg bar, or 5 lb rounding and a 45 lb bar. Values already
    /// exact for that unit are kept, so restoring saved settings (cancelling the cycle
    /// builder) doesn't overwrite them.
    static func applyUnitDefaults(to settings: inout UserSettings, useMetric: Bool) {
        let roundings = useMetric ? [1, 2.5, 5].map { $0 * lbPerKg } : [2.5, 5, 10]
        if !roundings.contains(where: { abs($0 - settings.roundingIncrement) < 0.05 }) {
            settings.roundingIncrement = useMetric ? 2.5 * lbPerKg : 5
        }
        if !options(useMetric: useMetric).contains(where: { abs($0.value - settings.barWeight) < 0.05 }) {
            settings.barWeight = useMetric ? 20 * lbPerKg : 45
        }
    }

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

let lbToKg = 0.45359237

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

