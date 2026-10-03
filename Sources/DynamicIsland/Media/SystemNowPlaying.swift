import AppKit

/// Reads the system-wide "Now Playing" (the same source Control Center uses — it
/// covers **every** app, browsers included) through a tiny bundled helper.
///
/// Apple blocks the private MediaRemote framework for third-party-signed processes,
/// but not for Apple-signed ones. So the helper is a small dylib loaded inside
/// `/usr/bin/python3` (Apple-signed) via ctypes.
///
/// To stay light on RAM, metadata streams from a **single long-lived** helper
/// process (one JSON line/second — no per-second process spawning, no zombies).
/// Artwork and transport commands are occasional one-off calls.
final class SystemNowPlaying {
    static let shared = SystemNowPlaying()
    private init() {}

    /// Located once: the bundled `mrhelper.dylib`.
    static let dylibPath: String? = {
        let fm = FileManager.default
        if let res = Bundle.main.resourcePath {
            let p = res + "/mrhelper.dylib"
            if fm.fileExists(atPath: p) { return p }
        }
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let p = dir.appendingPathComponent("mrhelper.dylib").path
            if fm.fileExists(atPath: p) { return p }
        }
        return nil
    }()

    static var isAvailable: Bool { dylibPath != nil }

    private var streamProcess: Process?
    private var buffer = Data()
    private var onUpdate: ((MediaRemoteBridge.Info?) -> Void)?
    private var stopped = false

    /// Start streaming now-playing metadata. `onUpdate` is called (off the main
    /// thread) with each snapshot, or nil when nothing is playing.
    func start(onUpdate: @escaping (MediaRemoteBridge.Info?) -> Void) {
        guard Self.dylibPath != nil else { return }
        self.onUpdate = onUpdate
        launch()
    }

    func stop() {
        stopped = true
        streamProcess?.terminate()
        streamProcess = nil
    }

    private func launch() {
        guard !stopped, let dylib = Self.dylibPath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import ctypes; ctypes.CDLL(\(Self.pyString(dylib))).mr_stream()"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.consume(chunk)
        }
        process.terminationHandler = { [weak self] _ in
            guard let self, !self.stopped else { return }
            // Respawn if the helper ever dies.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.launch() }
        }
        do { try process.run() } catch { return }
        streamProcess = process
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            onUpdate?(Self.parse(Data(line)))
        }
        if buffer.count > 8192 { buffer.removeAll(keepingCapacity: true) } // safety
    }

    // MARK: One-off calls

    /// Fetch just the current artwork. Call only when the track changes.
    static func fetchArtwork() -> NSImage? {
        guard let dylib = dylibPath else { return nil }
        let code = "import ctypes; ctypes.CDLL(\(pyString(dylib))).mr_get_artwork()"
        guard let out = runPythonOnce(code)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !out.isEmpty, let data = Data(base64Encoded: out) else { return nil }
        return NSImage(data: data)
    }

    /// Send a MediaRemote transport command (0 play, 1 pause, 2 toggle, 4 next, 5 prev).
    static func sendCommand(_ command: Int) {
        guard let dylib = dylibPath else { return }
        _ = runPythonOnce("import ctypes; ctypes.CDLL(\(pyString(dylib))).mr_command(\(command))")
    }

    // MARK: Internals

    private static func pyString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func runPythonOnce(_ code: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", code]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private static func parse(_ data: Data) -> MediaRemoteBridge.Info? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = obj["title"] as? String, !title.isEmpty
        else { return nil }
        var info = MediaRemoteBridge.Info()
        info.title = title
        info.artist = (obj["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        info.album = (obj["album"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        info.duration = obj["duration"] as? Double
        info.elapsed = obj["elapsed"] as? Double
        info.isPlaying = obj["isPlaying"] as? Bool
        if let pid = obj["pid"] as? Int, pid > 0 { info.pid = pid }
        info.sourceApp = "system"
        return info
    }
}
