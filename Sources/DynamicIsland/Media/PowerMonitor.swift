import Foundation
import IOKit.ps

/// Watches the power source so the island can show a brief "charging" flourish
/// when the Mac is plugged in — something macOS itself never pops up.
@MainActor
final class PowerMonitor {
    private(set) var pluggedIn = false
    private(set) var level = 100

    /// Called when the plug state changes: `true` = just plugged in.
    var onPlugChange: ((Bool) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var initialized = false

    func start() {
        read()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.read() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, ctx)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        runLoopSource = nil
    }

    private func read() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? level
            let maximum = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            level = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current

            let was = pluggedIn
            pluggedIn = onAC
            // Don't fire the flourish for the initial reading (only real changes).
            if initialized, pluggedIn != was { onPlugChange?(pluggedIn) }
            initialized = true
            return   // internal battery is the first source
        }
    }
}
