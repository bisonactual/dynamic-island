import SwiftUI
import AppKit
import Combine

/// A borderless, non-activating panel that floats above the menu bar so it can
/// draw over the notch.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}


/// Owns the notch window: computes the notch geometry for the active screen,
/// positions the panel over it, hosts the SwiftUI island, and resizes the window
/// as the island expands so it never blocks clicks it shouldn't.
@MainActor
final class NotchController {
    private let model: NowPlayingModel
    private var state: IslandState
    private var panel: NotchPanel!
    /// Separate panel used only on the lock screen (parked in a SkyLight space
    /// above loginwindow). Kept apart from the main panel so lock behaviour can't
    /// interfere with normal click-through / now-playing.
    private var lockPanel: NotchPanel!
    private var mouseMonitors: [Any] = []
    private var visibilityTimer: Timer?
    private var hiddenForFullscreen = false

    let power = PowerMonitor()
    private var chargingClearWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

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

    // MARK: Click → switch to the playing app; hide while that app is frontmost

    private func setupActivation() {
        state.onTapIsland = { [weak self] in self?.activatePlayingApp() }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateSuppressed() } }

        // Re-evaluate when what's playing changes.
        model.$playingPID.removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.updateSuppressed() } }
            .store(in: &cancellables)
        model.$isPlaying.removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.updateSuppressed() } }
            .store(in: &cancellables)
        model.$hasMedia.removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.updateSuppressed() } }
            .store(in: &cancellables)

        updateSuppressed()
    }

    private func updateSuppressed() {
        state.suppressedForFrontmost = isPlayerFrontmost()
        updateForPointer()
    }

    /// True when the app that owns the current track is already the frontmost app —
    /// then there's no point showing the island (including during the pause linger).
    private func isPlayerFrontmost() -> Bool {
        guard model.hasMedia, let pid = model.playingPID,
              let front = NSWorkspace.shared.frontmostApplication else { return false }
        if Int(front.processIdentifier) == pid { return true }
        // Browsers register now-playing from a helper process — match the app family.
        if let playing = NSRunningApplication(processIdentifier: pid_t(pid)),
           let pb = playing.bundleIdentifier, let fb = front.bundleIdentifier {
            return pb == fb || pb.hasPrefix(fb) || fb.hasPrefix(pb)
        }
        return false
    }

    private func activatePlayingApp() {
        guard let pid = model.playingPID,
              let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return }
        app.activate(options: [.activateAllWindows])
    }

    // MARK: Charging flourish

    private func setupCharging() {
        power.onPlugChange = { [weak self] pluggedIn in
            guard let self else { return }
            self.chargingClearWork?.cancel()
            if pluggedIn {
                self.state.chargingFlourish = self.power.level
                // Auto-dismiss the flourish after a few seconds.
                let work = DispatchWorkItem { [weak self] in self?.state.chargingFlourish = nil }
                self.chargingClearWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
            } else {
                self.state.chargingFlourish = nil
            }
        }
        power.start()
    }

    // MARK: Screen / notch geometry

    private static func targetScreen() -> NSScreen? {
        // Prefer the built-in display that actually has a notch.
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.main
    }

    private static func metrics(for screen: NSScreen?) -> NotchMetrics {
        guard let screen else {
            return NotchMetrics(notchWidth: 200, notchHeight: 32, hasNotch: false)
        }
        let topInset = screen.safeAreaInsets.top

        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - left.width - right.width
            return NotchMetrics(notchWidth: max(notchWidth, 120),
                                notchHeight: topInset,
                                hasNotch: true)
        }
        // No notch: synthesize a floating pill.
        return NotchMetrics(notchWidth: 190, notchHeight: 32, hasNotch: false)
    }

    // MARK: Window

    private func buildWindow() {
        let m = state.metrics
        let maxSize = m.maxWindowSize
        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: maxSize.width, height: maxSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Start fully click-through; the mouse monitor turns this off only while
        // the pointer is over the transport buttons.
        panel.ignoresMouseEvents = true

        let root = IslandView(model: model, state: state)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: maxSize.width, height: maxSize.height)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        positionWindow()
        panel.orderFrontRegardless()
    }

    /// Build the lock-screen-only panel: a static, non-clickable notch-sized
    /// island with a lock icon peeking to the left. It stays ordered out until the
    /// screen locks, and is placed in the SkyLight above-loginwindow space then.
    private func buildLockWindow() {
        let size = state.metrics.maxWindowSize
        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Allow the panel to render while no user is logged in / the screen is locked.
        panel.canBecomeVisibleWithoutLogin = true
        panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: LockIslandView(metrics: state.metrics))
        hosting.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.lockPanel = panel
        positionWindow()   // positions both panels; lockPanel stays ordered out
    }

    // MARK: Mouse tracking → expand / collapse / click-through

    /// The island's regions in global screen coordinates.
    private func regions() -> (notch: CGRect, panel: CGRect, buttons: CGRect)? {
        guard let screen = Self.targetScreen() else { return nil }
        let m = state.metrics
        let top = screen.frame.maxY
        let cx = screen.frame.midX

        let poppedOut = model.isPlaying || model.pausedLingering || state.hasCollapsedActivity
        let collapsedW = poppedOut ? m.collapsedWidth : m.notchWidth
        let notch = CGRect(x: cx - collapsedW / 2, y: top - m.restHeight,
                           width: collapsedW, height: m.restHeight)
        let panelRect = CGRect(x: cx - m.expandedWidth / 2, y: top - m.expandedHeight,
                               width: m.expandedWidth, height: m.expandedHeight)
        // Transport buttons live along the visual bottom of the expanded panel.
        let bW: CGFloat = 250, bH: CGFloat = 60
        let buttons = CGRect(x: cx - bW / 2, y: top - m.expandedHeight, width: bW, height: bH)
        return (notch, panelRect, buttons)
    }

    private func startMouseTracking() {
        // Local monitor fires while the pointer is over our (clickable) window;
        // global monitor fires while it's anywhere else.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.updateForPointer()
        })
        let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.updateForPointer()
            return event
        })
        if let global { mouseMonitors.append(global) }
        if let local { mouseMonitors.append(local) }
        updateForPointer()
    }

    private func updateForPointer() {
        guard !hiddenForFullscreen, popoutShown, let r = regions() else {
            panel.ignoresMouseEvents = true
            return
        }
        // Capture clicks only while the pointer is over the visible pop-out, so a
        // click can switch to the playing app. Everything else passes through.
        let p = NSEvent.mouseLocation
        panel.ignoresMouseEvents = !r.notch.insetBy(dx: -4, dy: -4).contains(p)
    }

    /// Whether the clickable pop-out is currently on screen.
    private var popoutShown: Bool {
        guard !hiddenForFullscreen else { return false }
        guard !state.suppressedForFrontmost else { return false }
        return model.isPlaying || model.pausedLingering
    }

    /// The window is a fixed size (large enough for the expanded panel plus glow)
    /// and never moves — it stays centered on the notch. Click-through is handled
    /// by `PassthroughHostingView`, so the fixed size blocks nothing around it.
    private func positionWindow() {
        guard let screen = Self.targetScreen() else { return }
        let size = state.metrics.maxWindowSize
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height   // top-aligned
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        lockPanel?.setFrame(frame, display: false)
    }

    // MARK: React to display changes

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state.metrics = Self.metrics(for: Self.targetScreen())
                self.positionWindow()
            }
        }
    }

    // MARK: Hide while fullscreen (notch not visible) or the screen is locked

    private func observeFullscreen() {
        // A fullscreen app lives in its own Space, so this fires on enter/exit.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        }
        // Lock / unlock the screen → show / hide a lock icon on the island.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in Log.write("screenIsLocked"); self?.setLocked(true) }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in Log.write("screenIsUnlocked"); self?.setLocked(false) }
        }
        // Safety net for cases the notifications don't cover.
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        }
        updateVisibility()
    }

    private func setLocked(_ locked: Bool) {
        guard lockPanel != nil else { return }
        if locked {
            positionWindow()                       // re-center in case the display changed
            lockPanel.orderFrontRegardless()
            // Must re-add every time it's shown — the space assignment doesn't
            // survive orderOut. No-op if SkyLight is unavailable.
            SkyLightSpace.shared?.add(window: lockPanel)
        } else {
            lockPanel.orderOut(nil)
        }
    }

    private func updateVisibility() {
        // Hide the whole window only in fullscreen (the notch isn't visible then).
        // The lock screen gets a lock icon instead.
        let shouldHide = isNotchScreenFullscreen()
        guard shouldHide != hiddenForFullscreen else { return }
        hiddenForFullscreen = shouldHide
        if shouldHide {
            panel.orderOut(nil)
        } else {
            positionWindow()
            panel.orderFrontRegardless()
        }
    }

    /// True when an app is in fullscreen on the notched screen.
    ///
    /// A fullscreen app gets its **own** auto-hiding menu-bar overlay above the
    /// system one (a full-width, menu-bar-height window at the very top, owned by
    /// the app, at a level above the normal menu bar). That overlay exists only in
    /// fullscreen, so its presence is a reliable signal — unlike the system menu
    /// bar, which stays put, and window size, which can't tell fullscreen-below-the
    /// -notch from a maximized window apart.
    private func isNotchScreenFullscreen() -> Bool {
        guard let screen = Self.targetScreen() else { return false }
        let sw = screen.frame.width
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        for window in list {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            // Skip the system chrome and our own window.
            if owner == "Window Server" || owner == "Dock" || owner == "DynamicIsland" { continue }
            let layer = (window[kCGWindowLayer as String] as? Int) ?? 0
            guard layer >= menuLevel else { continue }   // at/above the menu-bar level
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            // A full-width, menu-bar-height strip at the very top → the fullscreen
            // app's own menu-bar overlay.
            if b.origin.y <= 1 && b.width >= sw - 1 && b.height < 50 {
                return true
            }
        }
        return false
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
}
