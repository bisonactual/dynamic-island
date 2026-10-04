import SwiftUI

/// The main island view: the black notch pill plus whatever activity is currently
/// showing (music, charging). Individual pieces live in their own files:
/// `NotchShape`, `EqualizerView`, `FlippingArtwork`, `ChargingRing`,
/// `LockIslandView`, `NotchMetrics`, `IslandState`.
///
/// There is no hover/expanded state — a click switches to the playing app (handled
/// by `NotchController`); the island only ever shows its collapsed pop-out.
struct IslandView: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var state: IslandState

    private var m: NotchMetrics { state.metrics }

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        // The black shape's size is driven only by currentWidth/currentHeight;
        // content lives in an overlay so it can never inflate the shape, and is
        // clipped to the shape so it's *revealed* as the pill grows (icons slide
        // out from behind the notch instead of fading in).
        islandShape
            .fill(Color.black)
            .frame(width: currentWidth, height: currentHeight)
            .overlay(alignment: .top) {
                if hasActivity { collapsedContent }
            }
            .clipShape(islandShape)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: popKey)
    }

    private var islandShape: NotchShape {
        NotchShape(topRadius: 0, bottomRadius: m.collapsedCornerRadius)
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
        // Idle: exactly the notch. Any activity: pops out on both sides.
        hasActivity ? m.collapsedWidth : m.notchWidth
    }
    private var currentHeight: CGFloat { m.restHeight }

    // MARK: Collapsed content

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
}
