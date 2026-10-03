import SwiftUI
import Combine

/// Observable state for the island. Pulls now-playing info from MediaRemote
/// (with an AppleScript fallback), keeps the elapsed time ticking locally so the
/// scrubber moves smoothly, and drives playback via system media keys.
@MainActor
final class NowPlayingModel: ObservableObject {

    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var artwork: NSImage? { didSet { artworkToken &+= 1 } }
    /// Bumps whenever the artwork image actually changes — drives the Apple-style
    /// art swap animation on track change (keyed on this so the swap fires when the
    /// new image lands, not when the title updates a beat earlier).
    @Published var artworkToken: Int = 0
    /// Direction of the last track change: true = advanced a song (art flips to the
    /// right), false = went back (flips to the left). Inferred from track history,
    /// since changes usually come from the player app, not our own controls.
    @Published var flipForward: Bool = true
    @Published var isPlaying: Bool = false
    @Published var duration: Double = 0
    @Published var elapsed: Double = 0
    @Published var hasMedia: Bool = false

    /// PID of the app actually playing — used to switch to it and to hide the
    /// island while that app is already frontmost.
    @Published var playingPID: Int?

    /// Average color of the current artwork, used to tint the expanded island.
    @Published var accent: Color = .white

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var lastUpdate = Date()
    private var lastArtworkKey: String?
    private var currentSource: String?
    private var pauseLingerWork: DispatchWorkItem?
    private var trackKeyCurrent: String?
    private var trackKeyPrevious: String?

    /// True for a few seconds after pausing, so the pop-out can shrink + dim
    /// before it disappears.
    @Published var pausedLingering = false

    private func startPauseLinger() {
        pauseLingerWork?.cancel()
        pausedLingering = true
        let work = DispatchWorkItem { [weak self] in self?.pausedLingering = false }
        pauseLingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func cancelPauseLinger() {
        pauseLingerWork?.cancel()
        pausedLingering = false
    }

    private func loadArtwork(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            Task { @MainActor in
                guard let self, self.lastArtworkKey == urlString else { return }
                self.artwork = image
                self.accent = Self.accentColor(from: image)
            }
        }.resume()
    }

    /// Fetch the current system artwork off-main; apply only if still the same track.
    private func loadSystemArtwork(forToken token: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = SystemNowPlaying.fetchArtwork()
            Task { @MainActor in
                guard let self, self.title == token else { return }
                self.artwork = image
                self.accent = image.map { Self.accentColor(from: $0) } ?? .white
            }
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    private let fallbackQueue = DispatchQueue(label: "island.fallback")

    func start() {
        if SystemNowPlaying.isAvailable {
            // One long-lived helper streams metadata — no per-second process spawning.
            SystemNowPlaying.shared.start { [weak self] info in
                self?.handleStreamUpdate(info)
            }
        } else {
            // No helper (e.g. no python3): fall back to polling AppleScript sources.
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.fallbackQueue.async {
                    let info = MediaFallback.fetch()
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let info { self.apply(info) } else { self.clear() }
                    }
                }
            }
        }

        // Local clock: advance elapsed between real updates so the UI is smooth.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        SystemNowPlaying.shared.stop()
        pollTimer?.invalidate()
        tickTimer?.invalidate()
    }

    private func tick() {
        guard isPlaying, duration > 0 else { return }
        let now = Date()
        elapsed = min(elapsed + now.timeIntervalSince(lastUpdate), duration)
        lastUpdate = now
    }

    /// Handle one streamed system snapshot (called off the main thread).
    private func handleStreamUpdate(_ sysInfo: MediaRemoteBridge.Info?) {
        fallbackQueue.async { [weak self] in
            // Spotify/Music report play/pause instantly via AppleScript, while
            // MediaRemote lags ~1s. For the same track, trust the app's state. This
            // also covers a source still playing behind a paused browser tab.
            let app = MediaFallback.appFetch()
            let chosen = Self.reconcile(system: sysInfo, app: app)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let chosen { self.apply(chosen) } else { self.clear() }
            }
        }
    }

    nonisolated private static func reconcile(system: MediaRemoteBridge.Info?,
                                              app: MediaRemoteBridge.Info?) -> MediaRemoteBridge.Info? {
        guard let app else { return system }           // only the system source (e.g. a browser)
        if let sys = system, sameTrack(sys, app) {
            return app                                 // same track → app state is authoritative + instant
        }
        // Different tracks (or no system info): prefer whatever is actually playing.
        if app.isPlaying == true { return app }
        if system?.isPlaying == true { return system }
        return system ?? app
    }

    nonisolated private static func sameTrack(_ a: MediaRemoteBridge.Info, _ b: MediaRemoteBridge.Info) -> Bool {
        func norm(_ s: String?) -> String {
            (s ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        }
        let ta = norm(a.title)
        return !ta.isEmpty && ta == norm(b.title)
    }

    private func apply(_ info: MediaRemoteBridge.Info) {
        let newTitle = info.title ?? ""
        let trackChanged = newTitle != title || (info.album ?? "") != album
        let wasPlaying = isPlaying

        // Infer flip direction: if the new track is the one we had *before* the
        // current one, the user went back (flip left); otherwise forward (right).
        if trackChanged {
            let newKey = newTitle + "|" + (info.album ?? "")
            flipForward = (newKey != trackKeyPrevious)
            trackKeyPrevious = trackKeyCurrent
            trackKeyCurrent = newKey
        }

        title = newTitle
        artist = info.artist ?? ""
        album = info.album ?? ""
        if let d = info.duration { duration = d }
        if let e = info.elapsed { elapsed = e }
        if let p = info.isPlaying { isPlaying = p }
        lastUpdate = Date()

        // Linger briefly when playback pauses — but only for real app players
        // (Spotify/Music), where pausing means "I'll resume". For browser/system
        // sources, going not-playing usually means you left the video (closed the
        // tab, navigated away), and MediaRemote reports that as a stale "paused"
        // frame — so hide right away instead of lingering on it.
        let pauseLingers = info.sourceApp == "Spotify" || info.sourceApp == "Music"
        if wasPlaying && !isPlaying && !newTitle.isEmpty && pauseLingers {
            startPauseLinger()
        } else if isPlaying || (wasPlaying && !isPlaying) {
            // Resumed, or a non-lingering source stopped → drop any linger now.
            cancelPauseLinger()
        }

        if let art = info.artwork {
            if trackChanged || artwork == nil {
                artwork = art
                accent = Self.accentColor(from: art)
            }
        } else if let urlString = info.artworkURL {
            // Fallback source (Spotify): fetch the cover image by URL, once per track.
            if urlString != lastArtworkKey {
                lastArtworkKey = urlString
                loadArtwork(from: urlString)
            }
        } else if info.sourceApp == "system" {
            // System source: fetch the cover via the helper, but only when the
            // track changes (never every poll — that was churning RAM).
            let key = "sys:" + newTitle + "|" + album
            if key != lastArtworkKey {
                lastArtworkKey = key
                loadSystemArtwork(forToken: newTitle)
            }
        } else if trackChanged {
            artwork = nil
            accent = .white
            lastArtworkKey = nil
        }

        hasMedia = !title.isEmpty || artwork != nil
        currentSource = info.sourceApp
        playingPID = info.pid
    }

    private func clear() {
        guard hasMedia else { return }
        hasMedia = false
        isPlaying = false
        title = ""; artist = ""; album = ""
        artwork = nil
        duration = 0; elapsed = 0
        accent = .white
        lastArtworkKey = nil
        currentSource = nil
        playingPID = nil
        cancelPauseLinger()
    }

    // MARK: Controls

    func togglePlayPause() {
        control(appleScript: "playpause", mediaKey: .playPause)
        isPlaying.toggle()          // optimistic; corrected by the refresh below
        lastUpdate = Date()
    }

    func next() {
        control(appleScript: "next track", mediaKey: .next)
    }

    func previous() {
        control(appleScript: "previous track", mediaKey: .previous)
    }

    /// Route a control to whatever is *actually* playing. When the track comes
    /// from the system now-playing helper (the usual case — covers browsers, all
    /// apps), send a MediaRemote command, which targets the real now-playing app.
    /// Otherwise fall back to Spotify/Music AppleScript or the system media key.
    private func control(appleScript command: String, mediaKey: MediaKey) {
        if currentSource == "system", SystemNowPlaying.isAvailable {
            let cmd = command == "playpause" ? 2 : (command == "next track" ? 4 : 5)
            DispatchQueue.global(qos: .userInitiated).async { SystemNowPlaying.sendCommand(cmd) }
        } else if let source = currentSource, MediaFallback.isBrowser(source) {
            let browserCmd: MediaFallback.BrowserCommand =
                command == "playpause" ? .playPause : (command == "next track" ? .next : .previous)
            MediaFallback.browserCommand(browserCmd, in: source, chromium: MediaFallback.isChromium(source))
        } else if let app = MediaFallback.activeApp() {
            MediaFallback.send(command, to: app)
        } else {
            MediaKeys.post(mediaKey)
        }
        // The stream corrects the real state within ~1s; the optimistic toggle in
        // togglePlayPause() gives instant feedback in the meantime.
    }

    // MARK: Helpers

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Downscale the artwork to 1px and read the pixel to get a representative color.
    static func accentColor(from image: NSImage) -> Color {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let small = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 4, bitsPerPixel: 32)
        else { return .white }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
        NSGraphicsContext.current?.imageInterpolation = .high
        bitmap.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()

        guard let c = small.colorAt(x: 0, y: 0) else { return .white }

        // Brighten so it reads well as an accent on dark chrome.
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let bright = NSColor(hue: h, saturation: min(s * 1.1, 1), brightness: max(b, 0.65), alpha: 1)
        return Color(bright)
    }
}
