import SwiftUI

/// Smooth, organic equalizer bars shown while audio plays.
///
/// Driven by `TimelineView(.animation)`, which advances only while `active` (it is
/// `paused` otherwise) — so it costs nothing when nothing is playing. Each bar has
/// its own frequency and phase so the motion looks lively rather than uniform.
struct EqualizerView: View {
    var color: Color
    var active: Bool

    private let barCount = 5
    private let barWidth: CGFloat = 2.5
    private let spacing: CGFloat = 2
    private let maxHeight: CGFloat = 16
    private let minHeight: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: height(bar: i, time: t))
                }
            }
            .frame(height: maxHeight)
            .animation(.easeOut(duration: 0.08), value: active)
        }
    }

    private func height(bar i: Int, time t: Double) -> CGFloat {
        guard active else { return minHeight }
        // Two detuned sine waves per bar → a fuller, less mechanical bounce.
        let freq = 5.0 + Double(i) * 1.6
        let phase = Double(i) * 0.8
        let a = sin(t * freq + phase)
        let b = sin(t * freq * 0.5 + phase * 1.7)
        let level = (a * 0.65 + b * 0.35 + 1) / 2          // 0…1
        let eased = level * level * (3 - 2 * level)         // smoothstep for softer peaks
        return minHeight + CGFloat(eased) * (maxHeight - minHeight)
    }
}
