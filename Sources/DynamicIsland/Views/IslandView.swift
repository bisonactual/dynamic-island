import SwiftUI
import AppKit

/// The main island view: the black notch pill plus whatever activity is currently
/// showing (music, charging). Individual pieces live in their own files:
/// `NotchShape`, `EqualizerView`, `FlippingArtwork`, `ChargingRing`,
/// `LockIslandView`, `NotchMetrics`, `IslandState`.
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
        case .charging(let level):
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ChargingRing.color(for: level))
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
            ChargingRing(level: level, color: ChargingRing.color(for: level),
                         size: m.notchHeight - 6)
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
                .foregroundStyle(ChargingRing.color(for: level))
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
