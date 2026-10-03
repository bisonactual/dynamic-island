import SwiftUI
import AppKit

/// Album art that does a coin/card flip on track change: the current cover
/// rotates edge-on around the vertical axis, the image is swapped at 90° (while
/// it has zero width, so no mirrored back is ever seen), then the new cover
/// springs out from the center behind a white glint that fades as it's revealed.
struct FlippingArtwork: View {
    let image: NSImage?
    let token: Int
    /// true = advanced a song (flip toward the right), false = went back (left).
    let forward: Bool
    let size: CGFloat
    let corner: CGFloat

    @State private var shown: NSImage?
    @State private var angle: Double = 0
    @State private var started = false
    @State private var revealScale: CGFloat = 1   // new cover grows from the center
    @State private var flash: Double = 0          // white glint over it, fading out

    /// Seconds per half-flip. The full track-change swap takes twice this
    /// (`flipDuration`), which other features (e.g. the charging ring) sync to.
    static let halfFlip = 0.55
    static var flipDuration: Double { halfFlip * 2 }
    private var half: Double { Self.halfFlip }

    var body: some View {
        thumb
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .onAppear { if !started { shown = image; started = true } }
            .onChange(of: token) { _, _ in flip() }
    }

    private func flip() {
        let s: Double = forward ? 1 : -1                        // direction of spin
        withAnimation(.easeIn(duration: half)) { angle = 90 * s }   // turn edge-on
        DispatchQueue.main.asyncAfter(deadline: .now() + half) {
            shown = image                                        // swap while invisible
            angle = -90 * s
            // Reveal: the flipped face starts as a white glint, and the new cover
            // springs out from the center as the white fades — before it's fully shown.
            revealScale = 0.2
            flash = 0.95
            withAnimation(.easeOut(duration: half)) { angle = 0 }
            withAnimation(.spring(response: half + 0.1, dampingFraction: 0.7)) { revealScale = 1 }
            withAnimation(.easeOut(duration: half * 0.9)) { flash = 0 }
        }
    }

    @ViewBuilder private var thumb: some View {
        Group {
            if let art = shown {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(revealScale)                       // grows out from the center
        .overlay(Color.white.opacity(flash))            // white glint on top, fading
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}
