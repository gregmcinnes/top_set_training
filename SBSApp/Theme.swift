import SwiftUI

// MARK: - Namespaces

/// Top Set type styles (see the extension below). Every number uses a number style.
enum SBSFonts {}

/// Top Set spacing, radii and strokes (see the extension below).
enum SBSLayout {}

extension View {
    /// The screen background, edge to edge.
    func sbsBackground() -> some View {
        self
            .background(Color.bg.ignoresSafeArea())
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

    // Live workout: the phone is on the floor or a bench, an arm's length or more
    // away, so this one screen runs a size up from the rest of the app.
    static func liveWeight() -> Font {
        .custom(SBSFontName.barlowCondensedBold, size: 88, relativeTo: .largeTitle).monospacedDigit()
    }

    /// "× 5" beside the working weight: the other half of the set
    static func liveScheme() -> Font {
        .custom(SBSFontName.barlowCondensedBold, size: 48, relativeTo: .largeTitle).monospacedDigit()
    }

    static func liveTimer() -> Font {
        .custom(SBSFontName.barlowCondensedBold, size: 80, relativeTo: .largeTitle).monospacedDigit()
    }

    static func liveEyebrow() -> Font {
        .custom(SBSFontName.archivoSemiCondensedBold, size: 14, relativeTo: .footnote)
    }

    static func liveCaption() -> Font {
        .custom(SBSFontName.archivoMedium, size: 16, relativeTo: .callout)
    }

    static func liveNumberSmall() -> Font {
        .custom(SBSFontName.plexMonoMedium, size: 16, relativeTo: .callout).monospacedDigit()
    }

    static func liveUnit() -> Font {
        .custom(SBSFontName.plexMonoSemiBold, size: 20, relativeTo: .title3).monospacedDigit()
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

    /// The eyebrow on the live workout screen, a size up
    func liveEyebrowText() -> some View {
        font(SBSFonts.liveEyebrow()).tracking(1.2).textCase(.uppercase)
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
        // One line when it fits. A longer title at the accessibility sizes wraps
        // at a space rather than truncating ("I KNOW WHAT I W…"); a single word
        // still shrinks rather than breaking ("PAUS / E").
        ViewThatFits(in: .horizontal) {
            label.lineLimit(1).fixedSize()
            label
                .lineLimit(title.contains(" ") ? 2 : 1)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
        }
    }

    private var label: some View {
        Text(title.uppercased())
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
    /// The live workout screen's size
    var large: Bool = false

    var body: some View {
        HStack(spacing: SBSLayout.space1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font((large ? SBSFonts.liveEyebrow() : SBSFonts.eyebrow()).weight(.bold))
            }
            Group {
                if large {
                    Text(text).liveEyebrowText()
                } else {
                    Text(text).eyebrowText()
                }
            }
            .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, SBSLayout.space2)
        .padding(.vertical, large ? 4 : 3)
        .background(background, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                .strokeBorder(edge, lineWidth: SBSLayout.strokeHairline)
        )
        // Two words at most: a badge keeps its size rather than truncating to nothing
        .fixedSize()
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


// MARK: - Navigation bar

/// Restyles every system navigation bar (tab roots, pushed screens, sheets) in the
/// Top Set type and colours: large titles in title-large (Archivo SemiExpanded Black),
/// inline titles in Archivo ExtraBold, a transparent bar at rest (the screen's Color.bg
/// shows through) and an opaque Color.bg bar with a 1px hairline once content scrolls
/// under it. The at-rest bar must stay transparent: on iOS 26 an opaque scroll-edge
/// background hides the large title on every scrolling screen. Titles stay sentence case: UIKit can't
/// uppercase through attributes, and the strings double as back-button labels and
/// UI-test identifiers. Call once at launch, before the first bar is made.
enum SBSNavigationBarAppearance {
    @MainActor
    static func apply() {
        let ink = UIColor(named: "ink") ?? .label
        let bg = UIColor(named: "bg") ?? .systemBackground
        let hairline = UIColor(named: "hairline") ?? .separator

        let large = scaled(SBSFontName.archivoSemiExpandedBlack, size: 34, style: .largeTitle)
        let inline = scaled(SBSFontName.archivoExtraBold, size: 17, style: .headline)
        let button = scaled(SBSFontName.archivoSemiBold, size: 17, style: .body)

        func make(scrolled: Bool) -> UINavigationBarAppearance {
            let a = UINavigationBarAppearance()
            if scrolled {
                a.configureWithOpaqueBackground()
                a.backgroundColor = bg
                a.shadowColor = hairline
            } else {
                a.configureWithTransparentBackground()
            }
            a.largeTitleTextAttributes = [.font: large, .foregroundColor: ink, .kern: -0.34]
            a.titleTextAttributes = [.font: inline, .foregroundColor: ink, .kern: 0.2]

            let item = UIBarButtonItemAppearance(style: .plain)
            item.normal.titleTextAttributes = [.font: button]
            a.buttonAppearance = item
            a.backButtonAppearance = item
            let done = UIBarButtonItemAppearance(style: .done)
            done.normal.titleTextAttributes = [.font: scaled(SBSFontName.archivoBold, size: 17, style: .body)]
            a.doneButtonAppearance = done
            return a
        }

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = make(scrolled: true)
        bar.compactAppearance = make(scrolled: true)
        bar.scrollEdgeAppearance = make(scrolled: false)
        bar.compactScrollEdgeAppearance = make(scrolled: false)
    }

    private static func scaled(_ name: String, size: CGFloat, style: UIFont.TextStyle) -> UIFont {
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: .bold)
        // Large titles cap at the same 1.5x iOS uses for its own; inline titles stay small.
        let cap: CGFloat = style == .largeTitle ? size * 1.5 : size * 1.3
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base, maximumPointSize: cap)
    }
}
