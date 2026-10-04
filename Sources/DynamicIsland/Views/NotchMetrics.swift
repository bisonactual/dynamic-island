import SwiftUI

/// Geometry of the physical notch (or the synthetic pill on notch-less screens),
/// plus the size the island grows to when expanded.
struct NotchMetrics {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    var collapsedSidePadding: CGFloat { 30 }   // content peeking on each side of the notch when playing
    var collapsedWidth: CGFloat { notchWidth + collapsedSidePadding * 2 }
    var collapsedCornerRadius: CGFloat { 11 }  // roughly matches the notch's own corners
    var bottomExtension: CGFloat { 1 }         // extra px so the pill's bottom lines up with the notch
    var restHeight: CGFloat { notchHeight + bottomExtension }

    /// The fixed canvas the panel uses. It's larger than the collapsed pop-out so
    /// there's always room around it; click-through keeps the extra area from
    /// blocking anything, so the panel never resizes.
    private var canvasWidth: CGFloat { 412 + glowMargin * 2 }
    private var canvasHeight: CGFloat { 146 + glowMargin + 18 }

    /// Extra room around the pop-out so nothing is clipped.
    var glowMargin: CGFloat { 45 }

    /// The size the hosting view (and panel) is built at.
    var maxWindowSize: CGSize { CGSize(width: canvasWidth, height: canvasHeight) }
}
