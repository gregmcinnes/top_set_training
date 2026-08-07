import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Lightweight wrapper around the system haptic feedback generators.
///
/// UIKit's feedback generators aren't available on every platform (e.g. the
/// watch target has no UIKit), so all calls compile to no-ops where UIKit is
/// absent. Generators are created per call, which is fine for occasional
/// feedback and avoids holding onto shared state.
public enum Haptics {

    /// A light impact — good for minor UI ticks (e.g. a value stepping).
    public static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// A medium impact — good for confirming a discrete action.
    public static func medium() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    /// A success notification — e.g. a set logged or a PR achieved.
    public static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// A warning notification — e.g. an invalid or destructive action.
    public static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// A selection change — e.g. moving between picker options.
    public static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
