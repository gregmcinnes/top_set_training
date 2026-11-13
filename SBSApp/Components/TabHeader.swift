import SwiftUI

// MARK: - Tab Header

/// The title at the top of a tab's root screen, drawn in the content instead of the
/// system navigation bar. The system large-title bar keeps an empty toolbar row above
/// the title (taller still on iOS 26); this puts the title right under the status bar,
/// with the tab's actions on the same line. It scrolls away with the content.
///
/// Pair it with `sbsTabRoot(_:)` on the same screen, which hides the system bar.
struct SBSTabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: SBSLayout.space3) {
            Text(title)
                .font(SBSFonts.titleLarge())
                .tracking(-0.34)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            trailing
                .font(.system(size: 22))
                .foregroundStyle(Color.orangeText)
                .frame(minWidth: 44, minHeight: 44)
        }
        // The gap under the status bar lives here so every tab matches;
        // screens add no top padding of their own above the header.
        .padding(.top, Self.topSpace)
    }

    static var topSpace: CGFloat { SBSLayout.space4 }
}

extension View {
    /// A tab's root screen: hides the system navigation bar (the screen draws an
    /// SBSTabHeader instead) and backs the status bar with Color.bg so scrolled content
    /// doesn't run under the clock. The title still names the screen for the back
    /// button of anything pushed from it.
    func sbsTabRoot(_ title: String) -> some View {
        navigationTitle(title)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background(Color.bg)
            }
    }
}
