import AppKit

/// Fallback now-playing source that talks to Spotify and Apple Music directly
/// via AppleScript. Used when MediaRemote returns nothing (e.g. Apple has
/// restricted the private framework). Only queries an app if it is running,
/// and the first query triggers the standard macOS Automation permission prompt.
enum MediaFallback {

    private static let sources = [
        (bundle: "com.spotify.client", app: "Spotify"),
        (bundle: "com.apple.Music", app: "Music")
    ]

    static func fetch() -> NowPlayingInfo? {
        let app = appFetch()
        if app?.isPlaying == true { return app }
        if let browser = browserFetch() { return browser }   // only returns when playing
        return app
    }

    /// Spotify/Music only (no browser) via AppleScript — fast and authoritative,
    /// used to correct MediaRemote's laggy play/pause for those apps.
    static func appFetch() -> NowPlayingInfo? {
        var pausedTrack: NowPlayingInfo?
        for s in sources {
            if let info = query(bundleID: s.bundle, app: s.app) {
                if info.isPlaying == true { return info }
                if pausedTrack == nil { pausedTrack = info }
            }
        }
        return pausedTrack
    }

    /// The player app that currently has a track loaded (playing or paused).
    static func activeApp() -> String? {
        for s in sources where isRunning(s.bundle) {
            let src = """
            tell application "\(s.app)"
                if it is running then return player state as text
                return "stopped"
            end tell
            """
            guard let script = NSAppleScript(source: src) else { continue }
            var error: NSDictionary?
            let state = script.executeAndReturnError(&error).stringValue ?? ""
            if error == nil, state != "stopped", !state.isEmpty { return s.app }
        }
        return nil
    }

    /// Send a transport command (e.g. "playpause", "next track", "previous track")
    /// to the given app. Returns true on success.
    @discardableResult
    static func send(_ command: String, to app: String) -> Bool {
        let src = "tell application \"\(app)\" to \(command)"
        guard let script = NSAppleScript(source: src) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func query(bundleID: String, app: String) -> NowPlayingInfo? {
        guard isRunning(bundleID) else { return nil }

        let sep = "|||"
        // Spotify exposes an artwork URL; Music does not, so only ask Spotify.
        let artLine = app == "Spotify"
            ? "set artURL to artwork url of current track"
            : "set artURL to \"\""
        let source = """
        tell application "\(app)"
            if it is running then
                if player state is stopped then return "STOPPED"
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDur to duration of current track
                set trackPos to player position
                set playState to player state as text
                \(artLine)
                return trackName & "\(sep)" & trackArtist & "\(sep)" & trackAlbum & "\(sep)" & trackDur & "\(sep)" & trackPos & "\(sep)" & playState & "\(sep)" & artURL
            else
                return "STOPPED"
            end if
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        guard let raw = result.stringValue, raw != "STOPPED" else { return nil }

        let parts = raw.components(separatedBy: sep)
        guard parts.count >= 6 else { return nil }

        var info = NowPlayingInfo()
        info.title = parts[0].isEmpty ? nil : parts[0]
        info.artist = parts[1].isEmpty ? nil : parts[1]
        info.album = parts[2].isEmpty ? nil : parts[2]

        // Numbers can use a comma decimal separator under some locales.
        func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

        // Spotify reports duration in milliseconds; Music in seconds.
        if let d = number(parts[3]) {
            info.duration = (app == "Spotify") ? d / 1000.0 : d
        }
        info.elapsed = number(parts[4])
        info.isPlaying = parts[5].lowercased().contains("playing")
        if parts.count >= 7, !parts[6].isEmpty { info.artworkURL = parts[6] }
        info.sourceApp = app
        if let proc = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            info.pid = Int(proc.processIdentifier)
        }
        return info
    }

    // MARK: Browser support (YouTube, SoundCloud, web players, …)

    /// Browsers we know how to script. Chromium-based ones use `execute javascript`;
    /// Safari uses `do JavaScript`. Add more freely — matching is by app name.
    private static let browsers: [(name: String, chromium: Bool)] = [
        ("Google Chrome", true), ("Google Chrome Canary", true),
        ("Brave Browser", true), ("Microsoft Edge", true),
        ("Arc", true), ("Vivaldi", true), ("Opera", true), ("Helium", true),
        ("Safari", false)
    ]

    /// Read the current media from the active tab of any running, scriptable
    /// browser via the page's Media Session metadata.
    static func browserFetch() -> NowPlayingInfo? {
        for b in browsers where isRunningByName(b.name) {
            if let info = browserQuery(name: b.name, chromium: b.chromium) { return info }
        }
        return nil
    }

    /// JavaScript run inside the page: returns
    /// "isPlaying|||title|||artist|||artworkURL|||currentTime|||duration".
    private static let mediaJS = """
    (function(){var m=navigator.mediaSession&&navigator.mediaSession.metadata;\
    var t=(m&&m.title)||'';var a=(m&&m.artist)||'';\
    var art=(m&&m.artwork&&m.artwork.length)?m.artwork[m.artwork.length-1].src:'';\
    var els=document.querySelectorAll('video,audio');var p=false,cur=0,dur=0;\
    for(var i=0;i<els.length;i++){if(!els[i].paused&&!els[i].ended){p=true;cur=els[i].currentTime||0;dur=els[i].duration||0;break;}}\
    if(!t&&p){t=document.title;}return (p?'1':'0')+'|||'+t+'|||'+a+'|||'+art+'|||'+cur+'|||'+dur;})()
    """

    private static func browserQuery(name: String, chromium: Bool) -> NowPlayingInfo? {
        let js = mediaJS.replacingOccurrences(of: "\"", with: "\\\"")
        let command = chromium
            ? "tell application \"\(name)\" to execute front window's active tab javascript \"\(js)\""
            : "tell application \"\(name)\" to do JavaScript \"\(js)\" in current tab of front window"

        guard let script = NSAppleScript(source: command) else { return nil }
        var error: NSDictionary?
        let raw = script.executeAndReturnError(&error).stringValue ?? ""
        if error != nil { return nil }

        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 2 else { return nil }
        let playing = parts[0] == "1"
        let title = parts[1]
        // Nothing meaningful playing in this browser.
        guard playing, !title.isEmpty else { return nil }

        var info = NowPlayingInfo()
        info.title = title
        info.artist = parts.count > 2 ? parts[2] : ""
        info.isPlaying = true
        if parts.count > 3, !parts[3].isEmpty { info.artworkURL = parts[3] }
        if parts.count > 4 { info.elapsed = Double(parts[4].replacingOccurrences(of: ",", with: ".")) }
        if parts.count > 5, let d = Double(parts[5].replacingOccurrences(of: ",", with: ".")), d.isFinite { info.duration = d }
        info.sourceApp = name
        return info
    }

    /// Toggle play/pause (or next/prev) in a browser's active tab via JavaScript.
    @discardableResult
    static func browserCommand(_ command: BrowserCommand, in name: String, chromium: Bool) -> Bool {
        let js: String
        switch command {
        case .playPause:
            js = "var v=document.querySelector('video,audio');if(v){v.paused?v.play():v.pause();}"
        case .next:
            js = "var b=document.querySelector('.ytp-next-button,[aria-label*=Next],[title*=Next]');if(b)b.click();"
        case .previous:
            js = "var b=document.querySelector('.ytp-prev-button,[aria-label*=Previous],[title*=Previous]');if(b)b.click();"
        }
        let escaped = js.replacingOccurrences(of: "\"", with: "\\\"")
        let source = chromium
            ? "tell application \"\(name)\" to execute front window's active tab javascript \"\(escaped)\""
            : "tell application \"\(name)\" to do JavaScript \"\(escaped)\" in current tab of front window"
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    enum BrowserCommand { case playPause, next, previous }

    static func isBrowser(_ app: String) -> Bool { browsers.contains { $0.name == app } }
    static func isChromium(_ app: String) -> Bool { browsers.first { $0.name == app }?.chromium ?? true }

    private static func isRunningByName(_ name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == name }
    }
}
