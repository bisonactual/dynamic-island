import SwiftUI

/// A circular battery gauge: a ring filled to the charge level with the percent
/// in the center, tinted by level. The fill animates up once when it appears.
struct ChargingRing: View {
    let level: Int
    let color: Color
    let size: CGFloat

    @State private var fill: CGFloat = 0

    private var lineWidth: CGFloat { max(2, size * 0.11) }

    /// Apple's battery semantics: red when low, orange mid, green when healthy.
    static func color(for level: Int) -> Color {
        if level < 20 { return .red }
        if level < 80 { return .orange }
        return .green
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))   // start at 12 o'clock
            Text("\(level)")
                .font(.system(size: size * 0.34, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .onAppear {
            // The ring draws itself around to the battery level, over the same time
            // the album cover takes to flip on a track change.
            withAnimation(.easeOut(duration: FlippingArtwork.flipDuration)) {
                fill = CGFloat(level) / 100
            }
        }
    }
}
