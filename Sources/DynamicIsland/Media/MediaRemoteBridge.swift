import Foundation
import AppKit

/// Thin bridge over the private MediaRemote framework. It is used read-only:
/// we ask the system for the current "now playing" info and subscribe to its
/// change notifications. Playback control is done through `MediaKeys` instead,
/// which is more robust across macOS versions.
///
/// If the framework cannot be loaded (or Apple locks it down), every call
/// degrades gracefully to a no-op and the app keeps working with the
/// ScriptingBridge fallback.
final class MediaRemoteBridge {

    struct Info {
        var title: String?
        var artist: String?
        var album: String?
        var artwork: NSImage?
        var artworkURL: String?
        var duration: Double?
        var elapsed: Double?
        var isPlaying: Bool?
        /// Which app this came from ("Spotify", "Music", or a browser name), so
        /// playback controls know where to send commands.
        var sourceApp: String?
        /// PID of the app actually playing (to switch to it / detect frontmost).
        var pid: Int?
    }

    typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    typealias GetIsPlaying      = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    typealias RegisterForNotify = @convention(c) (DispatchQueue) -> Void

    private var getNowPlayingInfo: GetNowPlayingInfo?
    private var getIsPlaying: GetIsPlaying?
    private var registerForNotifications: RegisterForNotify?

    let available: Bool

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            available = false
            return
        }

        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        getNowPlayingInfo = sym("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfo.self)
        getIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlaying.self)
        registerForNotifications = sym("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterForNotify.self)

        available = getNowPlayingInfo != nil
    }

    /// Ask MediaRemote to start delivering change notifications to the given queue.
    func startListening() {
        registerForNotifications?(.main)
    }

    /// Fetch a snapshot of the current now-playing state.
    ///
    /// The now-playing dictionary is delivered directly to `completion`; we never
    /// gate delivery on the separate "is playing" query, which does not reliably
    /// call back. The play/pause flag is refreshed independently via `refreshIsPlaying`.
    func fetch(_ completion: @escaping (Info?) -> Void) {
        guard let getNowPlayingInfo else { completion(nil); return }

        getNowPlayingInfo(.main) { dict in
            var info = Info()
            info.title    = dict["kMRMediaRemoteNowPlayingInfoTitle"]  as? String
            info.artist   = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String
            info.album    = dict["kMRMediaRemoteNowPlayingInfoAlbum"]  as? String
            info.duration = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue
            info.elapsed  = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue

            if let rate = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue {
                info.isPlaying = rate > 0
            }
            if let data = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                info.artwork = NSImage(data: data)
            }

            // When there's no title at all, treat it as "nothing playing".
            if info.title == nil && info.artist == nil && info.artwork == nil {
                completion(nil)
                return
            }
            completion(info)
        }
    }

    /// Independently query whether playback is active. Best-effort: if the query
    /// never calls back, the handler simply isn't invoked.
    func refreshIsPlaying(_ handler: @escaping (Bool) -> Void) {
        getIsPlaying?(.main) { handler($0) }
    }

    // MARK: Change notifications

    /// Subscribe to MediaRemote's Darwin notifications by name.
    static func observeChanges(_ handler: @escaping () -> Void) -> [NSObjectProtocol] {
        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRNowPlayingPlaybackQueueChangedNotification",
            "kMRPlaybackQueueContentItemsChangedNotification"
        ]
        return names.map { name in
            NotificationCenter.default.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { _ in handler() }
        }
    }
}
