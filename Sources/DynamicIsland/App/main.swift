import AppKit

// Top-level code in an executable runs on the main thread at process start,
// so it is safe to assume main-actor isolation here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
