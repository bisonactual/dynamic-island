import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = NowPlayingModel()
    private var controller: NotchController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activation policy (.accessory — agent app, no Dock icon) is set in main.swift
        // before the app launches.
        controller = NotchController(model: model)
        model.start()
        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "capsule.fill",
                                   accessibilityDescription: "Dynamic Island")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Dynamic Island", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Avslutt", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
