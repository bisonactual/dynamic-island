import SwiftUI

/// Geometry of the physical notch (or the synthetic pill on notch-less screens),
/// plus the size the island grows to when expanded.
struct NotchMetrics {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    var collapsedSidePadding: CGFloat { 30 }   // content peeking on each side of the notch when playing
    var collapsedHeight: CGFloat { max(notchHeight, 24) }
    var collapsedWidth: CGFloat { notchWidth + collapsedSidePadding * 2 }
    var collapsedCornerRadius: CGFloat { 11 }  // roughly matches the notch's own corners
    var bottomExtension: CGFloat { 1 }         // extra px so the pill's bottom lines up with the notch
    var restHeight: CGFloat { notchHeight + bottomExtension }

    var expandedWidth: CGFloat { 412 }
    var expandedHeight: CGFloat { 146 }
    var expandedCornerRadius: CGFloat { 28 }   // bottom corners
    var expandedTopRadius: CGFloat { 22 }      // concave top flare (also insets the body)

    /// How far below the top the expanded content should start, so it clears the notch.
    var expandedTopInset: CGFloat { notchHeight + 4 }

    /// Extra room around the expanded panel so the glow isn't clipped.
    var glowMargin: CGFloat { 45 }

    /// The window is sized tightly to the current island state so it only ever
    /// intercepts clicks over (and just around) the island — never the menu-bar
    /// icons beside the notch, and never the dead area where it *would* expand.
    func windowSize(expanded: Bool, playing: Bool) -> CGSize {
        if expanded {
            return CGSize(width: expandedWidth + glowMargin * 2,
                          height: expandedHeight + glowMargin + 18)
        }
        let w = playing ? collapsedWidth : notchWidth
        return CGSize(width: w + 6, height: restHeight + 6)
    }

    /// The largest the window ever gets — the hosting view is built at this size.
    var maxWindowSize: CGSize {
        CGSize(width: expandedWidth + glowMargin * 2, height: expandedHeight + glowMargin + 18)
    }
}
