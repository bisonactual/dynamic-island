import AppKit

extension NotchController {

    static func targetScreen() -> NSScreen? {
        // Prefer the built-in display that actually has a notch.
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        return NSScreen.main
    }

    static func metrics(for screen: NSScreen?) -> NotchMetrics {
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

    /// The island's regions in global screen coordinates.
    func regions() -> (notch: CGRect, panel: CGRect, buttons: CGRect)? {
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

    /// The window is a fixed size (large enough for the expanded panel plus glow)
    /// and never moves — it stays centered on the notch. Click-through handles the
    /// rest, so the fixed size blocks nothing around it.
    func positionWindow() {
        guard let screen = Self.targetScreen() else { return }
        let size = state.metrics.maxWindowSize
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height   // top-aligned
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        lockPanel?.setFrame(frame, display: false)
    }

    func observeScreenChanges() {
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
}
