import AppKit

extension NotchController {

    func setupActivation() {
        state.onTapIsland = { [weak self] in self?.activatePlayingApp() }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateSuppressed() } }

        // Re-evaluate when what's playing changes.
        model.$playingPID.removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.updateSuppressed() } }
            .store(in: &cancellables)
        model.$isPlaying.removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.updateSuppressed() } }
            .store(in: &cancellables)
        model.$hasMedia.removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.updateSuppressed() } }
            .store(in: &cancellables)

        updateSuppressed()
    }

    private func updateSuppressed() {
        state.suppressedForFrontmost = isPlayerFrontmost()
        updateForPointer()
    }

    /// True when the app that owns the current track is already the frontmost app —
    /// then there's no point showing the island (including during the pause linger).
    private func isPlayerFrontmost() -> Bool {
        guard model.hasMedia, let pid = model.playingPID,
              let front = NSWorkspace.shared.frontmostApplication else { return false }
        if Int(front.processIdentifier) == pid { return true }
        // Browsers register now-playing from a helper process — match the app family.
        if let playing = NSRunningApplication(processIdentifier: pid_t(pid)),
           let pb = playing.bundleIdentifier, let fb = front.bundleIdentifier {
            return pb == fb || pb.hasPrefix(fb) || fb.hasPrefix(pb)
        }
        return false
    }

    private func activatePlayingApp() {
        guard let pid = model.playingPID,
              let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return }
        app.activate(options: [.activateAllWindows])
    }
}
