import AppKit

/// Sends system media keys (play/pause, next, previous) the same way the
/// physical keys on the keyboard do. Works system-wide against whatever app is
/// currently playing audio, and needs no special entitlements.
enum MediaKey: Int32 {
    case playPause = 16   // NX_KEYTYPE_PLAY
    case next      = 17   // NX_KEYTYPE_NEXT
    case previous  = 18   // NX_KEYTYPE_PREVIOUS
    case fast      = 19   // NX_KEYTYPE_FAST
    case rewind    = 20   // NX_KEYTYPE_REWIND
}

enum MediaKeys {
    static func post(_ key: MediaKey) {
        press(key, down: true)
        press(key, down: false)
    }

    private static func press(_ key: MediaKey, down: Bool) {
        let flags: NSEvent.ModifierFlags = down ? NSEvent.ModifierFlags(rawValue: 0xA00)
                                                 : NSEvent.ModifierFlags(rawValue: 0xB00)
        let data1 = (Int(key.rawValue) << 16) | (down ? 0xA00 : 0xB00)

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
