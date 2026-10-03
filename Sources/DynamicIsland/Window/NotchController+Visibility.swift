import AppKit

extension NotchController {

    func observeFullscreen() {
        // A fullscreen app lives in its own Space, so this fires on enter/exit.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        }
        // Lock / unlock the screen → show / hide the lock-screen lock icon.
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
}
