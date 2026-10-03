import SwiftUI

/// The classic Dynamic Island shape: bottom corners are convex (normal rounding),
/// while the top corners are *concave* — scooped inward toward the screen — so the
/// island looks like it flares out of the display edge. A `topRadius` of 0 gives a
/// flush, square top (used for the collapsed pill that merges with the notch).
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, min(rect.width, rect.height) / 2)
        let b = min(bottomRadius, min(rect.width, rect.height) / 2)
        var p = Path()

        // Full-width top edge — the black reaches the screen corners.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Top-right: concave flare inward from the corner to the (inset) body side.
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.minY + t),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        // Right body side down.
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b))
        // Bottom-right convex corner.
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        // Bottom edge.
        p.addLine(to: CGPoint(x: rect.minX + t + b, y: rect.maxY))
        // Bottom-left convex corner.
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.maxY - b),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        // Left body side up.
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.minY + t))
        // Top-left: concave flare back out to the corner.
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
