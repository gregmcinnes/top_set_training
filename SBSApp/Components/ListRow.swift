import SwiftUI

// The list side of the Top Set design system (ListRow guideline): where the
// brutalism stops. Hairline groups on radius-sm, no shadow, no 2px rule.

// MARK: - Section Eyebrow

/// An eyebrow section label in ink-secondary. On Home it sits on a strip of
/// knurl (texture only), the one place the guideline puts the stripe behind a title.
struct SBSSectionEyebrow<Trailing: View>: View {
    let text: String
    var knurled: Bool = false
    @ViewBuilder var trailing: Trailing

    @ScaledMetric(relativeTo: .caption2) private var knurlHeight: CGFloat = 10
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var label: some View {
        HStack(alignment: .center, spacing: SBSLayout.space2) {
            SBSEyebrow(text)
                .foregroundStyle(Color.inkSecondary)
                .accessibilityAddTraits(.isHeader)
                .layoutPriority(1)

            if knurled {
                KnurlPattern()
                    .frame(height: knurlHeight)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // A control beside the label would truncate to a word or two
            VStack(alignment: .leading, spacing: SBSLayout.space2) {
                label
                trailing
            }
        } else {
            HStack(alignment: .center, spacing: SBSLayout.space2) {
                label
                trailing
            }
        }
    }
}

extension SBSSectionEyebrow where Trailing == EmptyView {
    init(_ text: String, knurled: Bool = false) {
        self.text = text
        self.knurled = knurled
        self.trailing = EmptyView()
    }
}

extension SBSSectionEyebrow {
    init(_ text: String, knurled: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.knurled = knurled
        self.trailing = trailing()
    }
}

// MARK: - Group

/// A hairline group: an optional eyebrow, then rows on one surface card.
/// Put `SBSRowDivider()` between rows.
struct SBSListGroup<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SBSLayout.space2) {
            if let title {
                SBSSectionEyebrow(title)
            }
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            if let footer {
                Text(footer)
                    .font(SBSFonts.caption())
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The 1px separator between rows in a group, full width.
struct SBSRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: SBSLayout.strokeHairline)
            .accessibilityHidden(true)
    }
}

// MARK: - Adaptive Stack

/// A row's title and its trailing value side by side, or stacked at the
/// accessibility text sizes, where side by side squeezes the title to a
/// letter a line.
struct SBSAdaptiveStack<Content: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat = SBSLayout.space3
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: SBSLayout.space1) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - Row

/// Title in body-strong, an optional supporting line in number-small, and a
/// trailing value or control. Navigation rows end in an ink-tertiary chevron.
struct SBSListRow<Leading: View, Subtitle: View, Trailing: View>: View {
    let title: String
    var showsChevron: Bool = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SBSFonts.bodyStrong())
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.leading)
            subtitle
        }
    }

    var body: some View {
        HStack(spacing: SBSLayout.space3) {
            if dynamicTypeSize.isAccessibilitySize {
                // The value goes under the title rather than squeezing it
                VStack(alignment: .leading, spacing: SBSLayout.space2) {
                    HStack(spacing: SBSLayout.space3) {
                        leading
                        titleBlock
                    }
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                leading

                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                trailing
            }

            if showsChevron {
                SBSChevron()
            }
        }
        .padding(.vertical, SBSLayout.space3)
        .padding(.horizontal, SBSLayout.space4)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension SBSListRow where Leading == EmptyView {
    init(
        _ title: String,
        showsChevron: Bool = false,
        @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.showsChevron = showsChevron
        self.leading = EmptyView()
        self.subtitle = subtitle()
        self.trailing = trailing()
    }
}

extension SBSListRow where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String, showsChevron: Bool = false, @ViewBuilder subtitle: () -> Subtitle) {
        self.title = title
        self.showsChevron = showsChevron
        self.leading = EmptyView()
        self.subtitle = subtitle()
        self.trailing = EmptyView()
    }
}

/// A row's supporting line: number-small in ink-secondary.
struct SBSRowSubtitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(SBSFonts.numberSmall())
            .foregroundStyle(Color.inkSecondary)
            .multilineTextAlignment(.leading)
    }
}

/// The navigation chevron: the one use of ink-tertiary besides placeholders.
struct SBSChevron: View {
    var systemName: String = "chevron.right"

    var body: some View {
        Image(systemName: systemName)
            .font(SBSFonts.caption().weight(.semibold))
            .foregroundStyle(Color.inkTertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Change

/// A gain or loss: arrow glyph and a number-small value in success or danger,
/// so the direction never rests on colour alone.
struct SBSChangeLabel: View {
    let text: String
    let isUp: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                .font(SBSFonts.numberSmall().weight(.bold))
                .accessibilityHidden(true)
            Text(text)
                .font(SBSFonts.numberSmall())
        }
        .foregroundStyle(isUp ? Color.success : Color.danger)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUp ? "Up" : "Down") \(text)")
    }
}

// MARK: - Square Toggle

/// The ListRow guideline's square toggle: surface-raised track and ink knob
/// when off; orange track, ink edge and orange-ink knob when on. VoiceOver and
/// UI tests see a standard switch.
struct SBSToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SBSToggleBody(configuration: configuration)
    }
}

private struct SBSToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: SBSLayout.space3) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            SBSToggleSwitch(isOn: configuration.isOn)
                .opacity(isEnabled ? 1 : 0.4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                configuration.isOn.toggle()
            }
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
        }
    }
}

/// The track and knob alone.
struct SBSToggleSwitch: View {
    let isOn: Bool

    private let width: CGFloat = 44
    private let height: CGFloat = 26
    private let inset: CGFloat = 3

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                .fill(isOn ? Color.orangeFill : Color.surfaceRaised)
            RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                .strokeBorder(isOn ? Color.ink : Color.hairline, lineWidth: SBSLayout.strokeHairline)
            Rectangle()
                .fill(isOn ? Color.orangeInk : Color.ink)
                .frame(width: height - inset * 2, height: height - inset * 2)
                .padding(inset)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Segmented Control

/// A square segmented control: hairline cells, the selected one orange-soft with
/// an orange-text edge. Replaces the system's rounded segmented picker.
struct SBSSegmentedControl<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: SBSLayout.space1) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(SBSFonts.caption().weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, SBSLayout.space2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .selectionCell(isSelected)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Chip

/// A filter or choice chip: hairline cell, selected orange-soft with an
/// orange-text edge. Text stays ink.
struct SBSChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SBSLayout.space1) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(SBSFonts.caption().weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(SBSFonts.caption().weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, SBSLayout.space3)
            .frame(minHeight: 36)
            .selectionCell(isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Grouped List

extension View {
    /// A system List as square hairline groups: full-width surface rows with
    /// hairline separators on bg, eyebrow headers, square toggles. The inset
    /// style's rounded cards can't be squared, so this uses the grouped style.
    func sbsGroupedList() -> some View {
        listStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.bg.ignoresSafeArea())
            .listRowBackground(Color.surface)
            .listRowSeparatorTint(Color.hairline)
            .listSectionSeparatorTint(Color.hairline)
            .environment(\.defaultMinListRowHeight, 56)
            .toggleStyle(SBSToggleStyle())
            .font(SBSFonts.body())
            .foregroundStyle(Color.ink)
    }

    /// Row colours for one section of an sbsGroupedList (List doesn't pass them down).
    func sbsListRows() -> some View {
        listRowBackground(Color.surface)
            .listRowSeparatorTint(Color.hairline)
            .listSectionSeparatorTint(Color.hairline)
    }
}

extension View {
    /// A menu picker in a list row: the chosen value is ink-secondary, never orange.
    func sbsValuePicker() -> some View {
        tint(Color.inkSecondary)
    }
}

/// A List section header: the eyebrow, as written for VoiceOver.
struct SBSListHeader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        SBSEyebrow(text)
            .foregroundStyle(Color.inkSecondary)
            .textCase(nil)
    }
}

/// A List section footer in caption.
struct SBSListFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(SBSFonts.caption())
            .foregroundStyle(Color.inkSecondary)
            .textCase(nil)
    }
}

/// A text field on a hairline cell for list rows and forms.
extension View {
    func sbsFieldCell() -> some View {
        padding(.horizontal, SBSLayout.space3)
            .padding(.vertical, SBSLayout.space2)
            .background(Color.bg, in: RoundedRectangle(cornerRadius: SBSLayout.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: SBSLayout.radiusSm)
                    .strokeBorder(Color.hairline, lineWidth: SBSLayout.strokeHairline)
            )
    }
}

#Preview("List rows") {
    ScrollView {
        VStack(spacing: SBSLayout.space6) {
            SBSSectionEyebrow("This week", knurled: true)
            SBSListGroup(title: "Settings") {
                SBSListRow("Units", showsChevron: true) {
                    SBSRowSubtitle("Pounds · 45 lb bar")
                }
                SBSRowDivider()
                Toggle("Haptics", isOn: .constant(true))
                    .font(SBSFonts.bodyStrong())
                    .toggleStyle(SBSToggleStyle())
                    .padding(.horizontal, SBSLayout.space4)
                    .frame(minHeight: 56)
            }
            SBSSegmentedControl(options: ["Est. 1RM", "Training max"], selection: .constant("Est. 1RM")) { $0 }
        }
        .padding()
    }
    .background(Color.bg)
}
