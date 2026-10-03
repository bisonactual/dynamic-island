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

/// UI state shared with the window controller (so it can resize the window when
/// the island expands).
@MainActor
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var metrics: NotchMetrics

    /// Battery %, shown briefly as a "charging" flourish after plugging in.
    @Published var chargingFlourish: Int?

    /// Hide the music pop-out while the playing app is already frontmost.
    @Published var suppressedForFrontmost = false

    /// Clicking the music pop-out switches to the playing app.
    var onTapIsland: (() -> Void)?

    /// Whether a non-music activity currently wants the island popped out.
    var hasCollapsedActivity: Bool { chargingFlourish != nil }

    init(metrics: NotchMetrics) { self.metrics = metrics }
}

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

/// Static, non-interactive island shown on the lock screen: a notch-sized black
/// pill with a lock icon peeking to the left of the notch. Lives in its own panel
/// (see `NotchController.buildLockWindow`), so it carries no live state.
struct LockIslandView: View {
    let metrics: NotchMetrics

    private var shape: NotchShape {
        NotchShape(topRadius: 0, bottomRadius: metrics.collapsedCornerRadius)
    }

    var body: some View {
        shape
            .fill(Color.black)
            .frame(width: metrics.collapsedWidth, height: metrics.restHeight)
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: metrics.collapsedSidePadding, alignment: .center)
                    Spacer(minLength: metrics.notchWidth)
                    Color.clear.frame(width: metrics.collapsedSidePadding)
                }
                .frame(width: metrics.collapsedWidth, height: metrics.restHeight)
            }
            .clipShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Album art that does a coin/card flip on track change: the current cover
/// rotates edge-on around the vertical axis, the image is swapped at 90° (while
/// it has zero width, so no mirrored back is ever seen), then the new cover
/// rotates back to face front.
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

    private let half = 0.55   // seconds per half-flip (~1.1s total)

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

struct IslandView: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var state: IslandState

    private var m: NotchMetrics { state.metrics }

    var body: some View {
        // The island sizes itself (currentWidth/currentHeight); the window is
        // resized to fit it tightly, and the island is pinned to the top-center.
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        Group {
            // The black shape's size is driven ONLY by currentWidth/currentHeight.
            // Content lives in an overlay so it can never inflate the shape.
            islandShape
                .fill(Color.black)
                .frame(width: currentWidth, height: currentHeight)
                .overlay(alignment: .top) {
                    if state.expanded {
                        expandedContent.transition(.opacity)
                    } else if hasActivity {
                        collapsedContent
                    }
                }
                // Clip the content to the shape so it's *revealed* as the pill grows —
                // the icons slide out from behind the notch instead of fading in.
                .clipShape(islandShape)
                .overlay(
                    islandShape
                        .stroke(Color.white.opacity(state.expanded ? 0.10 : 0), lineWidth: 1)
                )
                // Soft black glow / halo around the island (outside the clip).
                .shadow(color: .black.opacity(glowStrength), radius: state.expanded ? 22 : 12)
                .shadow(color: .black.opacity(glowStrength * 0.7), radius: state.expanded ? 38 : 18)
                .contentShape(islandShape)
                // Expansion is driven by NotchController's mouse monitor, which also
                // controls click-through — so the panel never traps clicks meant for
                // content underneath it.
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: popKey)
                .animation(.spring(response: 0.42, dampingFraction: 0.8), value: state.expanded)
        }
    }

    /// How strongly the accent-colored glow shows: brightest when expanded,
    /// gentle while playing collapsed, off when idle.
    private var glowStrength: Double {
        state.expanded ? 0.7 : 0
    }

    private var islandShape: NotchShape {
        state.expanded
            ? NotchShape(topRadius: m.expandedTopRadius, bottomRadius: m.expandedCornerRadius)
            : NotchShape(topRadius: 0, bottomRadius: m.collapsedCornerRadius)
    }

    /// Music is shown unless the playing app is already frontmost.
    private var showMusic: Bool {
        (model.isPlaying || model.pausedLingering) && !state.suppressedForFrontmost
    }

    // What the island is currently showing, by priority.
    enum Activity { case charging(Int), music, none }
    private var activity: Activity {
        if let level = state.chargingFlourish { return .charging(level) }
        if showMusic { return .music }
        return .none
    }
    private var hasActivity: Bool { if case .none = activity { return false }; return true }

    /// Music is paused but still lingering — the art shrinks in place before it hides.
    private var musicDimmed: Bool { model.pausedLingering && !model.isPlaying }

    /// Which activity category is showing — used to animate pop-out changes.
    private var popKey: Int {
        if state.chargingFlourish != nil { return 1 }
        if showMusic { return 3 }
        return 0
    }

    private var currentWidth: CGFloat {
        // Idle: exactly the notch. Any activity: pops out on both sides. Hover: full panel.
        if state.expanded { return m.expandedWidth }
        return hasActivity ? m.collapsedWidth : m.notchWidth
    }
    private var currentHeight: CGFloat {
        state.expanded ? m.expandedHeight : m.restHeight
    }

    // MARK: Collapsed

    private var collapsedContent: some View {
        // Something peeks to the LEFT of the notch and something to the RIGHT.
        // Nothing is ever drawn over the notch itself.
        HStack(spacing: 0) {
            collapsedLeft
                .frame(width: m.collapsedSidePadding, alignment: .center)
            Spacer(minLength: m.notchWidth)
            collapsedRight
                .frame(width: m.collapsedSidePadding, alignment: .center)
        }
        .frame(width: m.collapsedWidth, height: m.restHeight)
        // Clicking the music pop-out switches to the playing app.
        .contentShape(Rectangle())
        .onTapGesture { if case .music = activity { state.onTapIsland?() } }
    }

    @ViewBuilder private var collapsedLeft: some View {
        switch activity {
        case .music:
            // Album art does a coin flip on track change; when paused it shrinks in
            // place and dims before hiding.
            FlippingArtwork(image: model.artwork, token: model.artworkToken,
                            forward: model.flipForward,
                            size: m.notchHeight - 10, corner: 5)
                .scaleEffect(musicDimmed ? 0.65 : 1)
                .opacity(musicDimmed ? 0.5 : 1)
                .animation(.easeOut(duration: 0.3), value: musicDimmed)
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var collapsedRight: some View {
        switch activity {
        case .music:
            // The visualizer keeps its size; it just dims while paused.
            EqualizerView(color: model.accent, active: model.isPlaying)
                .opacity(musicDimmed ? 0.5 : 1)
                .animation(.easeOut(duration: 0.3), value: musicDimmed)
        case .charging(let level):
            Text("\(level)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        case .none:
            EmptyView()
        }
    }

    // MARK: Expanded

    @ViewBuilder private var expandedContent: some View {
        switch activity {
        case .charging(let l): chargingExpanded(l)
        default:               musicExpanded
        }
    }

    private func chargingExpanded(_ level: Int) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 26))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(level)%")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("Lader")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, m.expandedTopInset)
        .padding(.bottom, 12)
        .frame(width: m.expandedWidth, height: m.expandedHeight, alignment: .top)
    }

    private var musicExpanded: some View {
        VStack(spacing: 6) {
            // Now-playing header: art, title/artist, waveform on the right.
            HStack(spacing: 11) {
                artworkThumb(size: 40, corner: 10)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.hasMedia ? model.title : "Ingen avspilling")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(model.hasMedia ? model.artist : "Start musikk i en app")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                EqualizerView(color: model.accent, active: model.isPlaying)
                    .frame(width: 22)
                    .opacity(model.hasMedia ? 1 : 0)
            }

            // Scrubber with the times flanking the bar.
            HStack(spacing: 10) {
                Text(NowPlayingModel.time(model.elapsed))
                    .frame(width: 34, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule().fill(.white)
                            .frame(width: max(0, geo.size.width * model.progress))
                    }
                }
                .frame(height: 5)
                Text(NowPlayingModel.time(model.duration))
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .opacity(model.hasMedia ? 1 : 0.25)

            // Transport controls
            HStack(spacing: 40) {
                controlButton("backward.fill", size: 17) { model.previous() }
                controlButton(model.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                    model.togglePlayPause()
                }
                controlButton("forward.fill", size: 17) { model.next() }
            }
            .disabled(!model.hasMedia)
            .opacity(model.hasMedia ? 1 : 0.35)
        }
        .padding(.horizontal, 38)
        .padding(.top, m.expandedTopInset)
        .padding(.bottom, 10)
        .frame(width: m.expandedWidth, height: m.expandedHeight, alignment: .top)
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func artworkThumb(size: CGFloat, corner: CGFloat) -> some View {
        Group {
            if let art = model.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}
