import AppKit

/// Bridge to private SkyLight *space* APIs. Raising an ordinary window's level
/// cannot put it over the lock screen, but parking the window in a custom space
/// whose **absolute level** sits above loginwindow can. All symbols are resolved
/// at runtime and the whole thing fails silently if any are missing — so a macOS
/// build that drops or renames them just turns the lock icon into a no-op.
final class SkyLightSpace {
    /// Nil if SkyLight or any symbol is unavailable, or the space can't be made.
    static let shared = SkyLightSpace()

    private typealias MainConnFn    = @convention(c) () -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevelFn    = @convention(c) (Int32, Int32, Int32) -> Void
    private typealias ShowSpacesFn  = @convention(c) (Int32, CFArray) -> Void
    private typealias AddWindowsFn  = @convention(c) (Int32, Int32, CFArray, Int32) -> Void

    private let conn: Int32
    private let space: Int32
    private let addWindowsFn: AddWindowsFn

    private init?() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let h = dlopen(path, RTLD_NOW),
              let mainSym   = dlsym(h, "SLSMainConnectionID"),
              let createSym = dlsym(h, "SLSSpaceCreate"),
              let levelSym  = dlsym(h, "SLSSpaceSetAbsoluteLevel"),
              let showSym   = dlsym(h, "SLSShowSpaces"),
              let addSym    = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }

        let mainConn    = unsafeBitCast(mainSym,   to: MainConnFn.self)
        let spaceCreate = unsafeBitCast(createSym, to: SpaceCreateFn.self)
        let setLevel    = unsafeBitCast(levelSym,  to: SetLevelFn.self)
        let showSpaces  = unsafeBitCast(showSym,   to: ShowSpacesFn.self)
        self.addWindowsFn = unsafeBitCast(addSym,  to: AddWindowsFn.self)

        // Create the above-loginwindow space once: create → set level → show.
        let c = mainConn()
        let s = spaceCreate(c, 1, 0)
        guard s != 0 else { return nil }
        setLevel(c, s, 400)
        showSpaces(c, [NSNumber(value: s)] as CFArray)
        self.conn = c
        self.space = s
    }

    /// Move the window into our space (and out of every other). Must be called
    /// *each time* the window is shown on the lock screen — the assignment doesn't
    /// survive being ordered out.
    func add(window: NSWindow) {
        addWindowsFn(conn, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }
}
