import SwiftUI
import AppKit
import Combine

/// A borderless, non-activating panel that floats above the menu bar so it can
/// draw over the notch.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the notch window(s): computes the notch geometry for the active screen,
/// positions the panel over it, hosts the SwiftUI island, and manages click-through
/// and visibility. Behaviour is split across extensions, one concern each:
///
/// - `NotchController+Windows` — builds the main and lock panels.
/// - `NotchController+Geometry` — screen/notch math, positioning, display changes.
/// - `NotchController+ClickThrough` — mouse tracking → OS-level click-through.
/// - `NotchController+Activation` — click to switch apps + frontmost suppression.
/// - `NotchController+Charging` — the plug-in battery flourish.
/// - `NotchController+Visibility` — hide in fullscreen, lock-screen lock icon.
@MainActor
final class NotchController {
    let model: NowPlayingModel
    let state: IslandState
    var panel: NotchPanel!
    /// Separate panel used only on the lock screen (parked in a SkyLight space
    /// above loginwindow). Kept apart from the main panel so lock behaviour can't
    /// interfere with normal click-through / now-playing.
    var lockPanel: NotchPanel!
    var mouseMonitors: [Any] = []
    var visibilityTimer: Timer?
    var hiddenForFullscreen = false

    let power = PowerMonitor()
    var chargingClearWork: DispatchWorkItem?
    var cancellables = Set<AnyCancellable>()

    init(model: NowPlayingModel) {
        self.model = model
        self.state = IslandState(metrics: NotchController.metrics(for: Self.targetScreen()))
        buildWindow()
        buildLockWindow()
        startMouseTracking()
        observeScreenChanges()
        observeFullscreen()
        setupCharging()
        setupActivation()
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
}
