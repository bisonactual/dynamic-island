import AppKit

extension NotchController {

    func startMouseTracking() {
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

    func updateForPointer() {
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
}
