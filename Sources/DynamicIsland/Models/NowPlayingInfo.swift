import AppKit

/// A single snapshot of now-playing state, produced by any source (the system
/// `MediaRemote` stream, or the Spotify/Music/browser AppleScript fallbacks) and
/// consumed by `NowPlayingModel`. All fields are optional so each source can fill
/// in only what it knows.
struct NowPlayingInfo {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: NSImage?
    var artworkURL: String?
    var duration: Double?
    var elapsed: Double?
    var isPlaying: Bool?
    /// Which app this came from ("Spotify", "Music", a browser name, or "system"),
    /// so playback controls know where to send commands.
    var sourceApp: String?
    /// PID of the app actually playing (to switch to it / detect frontmost).
    var pid: Int?
}
