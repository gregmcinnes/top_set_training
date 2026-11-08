import SwiftUI

// MARK: - Top Set design system, Watch edition
//
// The Watch side of the design system. Colours are the app's tokens with the same
// names (Color.ink, Color.orangeFill, ...), and the Watch only ever uses ink, orange
// and chalk. watchOS is always dark and actool drops dark appearances for it, so
// WatchTokens.xcassets holds each token's Iron value, generated from
// Shared/Tokens.xcassets by scripts/make_watch_tokens.py.
//
// Deviations from the phone, for a 40-49mm screen:
// - System fonts only (SF Compact). The working weight and the timer use the
//   condensed width as the stand-in for Barlow Condensed.
// - No hard shadow, no 2px rule and no knurl: at this size the rule eats the
//   screen and the knurl turns to noise. Edges are 1px hairlines on radiusSm.
// - The screen is the system black, not Color.bg, so the content doesn't sit in
//   a lighter rectangle inside the black bezel.

enum WatchLayout {
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12

    static let radiusSm: CGFloat = 2
    static let hairline: CGFloat = 1
    /// Height of the rest progress bar.
    static let progressHeight: CGFloat = 4
    static let buttonHeight: CGFloat = 40
}

enum WatchFonts {
    /// The hero numeral (working weight, timer, logged reps): condensed, bold,
    /// tabular. The size comes from the caller's @ScaledMetric so it follows Dynamic Type.
    static func hero(size: CGFloat) -> Font {
        Font.system(size: size, weight: .bold).width(.condensed).monospacedDigit()
    }

    /// The unit beside a hero numeral, and other small numbers.
    static func number() -> Font {
        Font.system(.body, design: .monospaced, weight: .semibold).monospacedDigit()
    }

    static func numberSmall() -> Font {
        Font.system(.footnote, design: .monospaced, weight: .medium).monospacedDigit()
    }

    static func eyebrow() -> Font {
        Font.system(.caption2, weight: .bold).width(.condensed)
    }

    static func button() -> Font {
        Font.system(.footnote, weight: .heavy)
    }
}

// MARK: - Pieces

/// An uppercase eyebrow that reads as written to VoiceOver ("Set 2 of 5", not "SET 2 OF 5").
struct WatchEyebrow: View {
    let text: String
    var systemImage: String? = nil

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: WatchLayout.space1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(WatchFonts.eyebrow())
                    .accessibilityHidden(true)
            }
            Text(text.uppercased())
                .font(WatchFonts.eyebrow())
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(text)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The hero numeral with an optional unit. The numeral never wraps: the unit sits
/// beside it when both fit on one line, else under it; only then does the numeral
/// scale down.
struct WatchHeroNumber: View {
    let value: String
    var unit: String? = nil
    var color: Color = .ink
    var baseSize: CGFloat = 52

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    /// The hero is already the largest text on the screen; past this it only
    /// pushes the action below the fold on a 40mm watch.
    private static let maxScale: CGFloat = 1.2

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                numeral.fixedSize()
                unitText
            }
            VStack(alignment: .leading, spacing: 0) {
                numeral
                unitText
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var numeral: some View {
        Text(value)
            .font(WatchFonts.hero(size: baseSize * min(scale, Self.maxScale)))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }

    @ViewBuilder
    private var unitText: some View {
        if let unit {
            Text(unit)
                .font(WatchFonts.number())
                .foregroundStyle(Color.inkSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Orange progress on a hairline track: square ends, no ring (the brand's shapes are rectangles).
struct WatchProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.hairline)
                Rectangle()
                    .fill(Color.orangeFill)
                    .frame(width: geo.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: WatchLayout.progressHeight)
        .clipShape(RoundedRectangle(cornerRadius: WatchLayout.radiusSm))
        .accessibilityHidden(true)
    }
}

/// A 1px hairline rule between groups.
struct WatchHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: WatchLayout.hairline)
            .accessibilityHidden(true)
    }
}

// MARK: - Button styles

/// A button title in capitals that VoiceOver reads as written. Use inside the Watch button styles.
struct WatchButtonLabel: View {
    let title: String
    var systemImage: String? = nil

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: WatchLayout.space1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title.uppercased())
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, WatchLayout.space2)
    }
}

/// The one action per screen: orange fill, orange-ink label, radiusSm.
struct WatchPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WatchButtonBody(
            configuration: configuration,
            foreground: .orangeInk,
            fill: .orangeFill,
            edge: .clear
        )
    }
}

/// Surface fill, ink label, hairline edge.
struct WatchSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WatchButtonBody(
            configuration: configuration,
            foreground: .ink,
            fill: configuration.isPressed ? .surfaceRaised : .surface,
            edge: .hairline
        )
    }
}

private struct WatchButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let foreground: Color
    let fill: Color
    let edge: Color

    var body: some View {
        configuration.label
            .font(WatchFonts.button())
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: WatchLayout.buttonHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: WatchLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: WatchLayout.radiusSm)
                    .strokeBorder(edge, lineWidth: WatchLayout.hairline)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}
