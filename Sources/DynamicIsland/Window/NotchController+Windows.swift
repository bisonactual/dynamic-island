import SwiftUI
import AppKit

extension NotchController {

    func buildWindow() {
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
    func buildLockWindow() {
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
}
