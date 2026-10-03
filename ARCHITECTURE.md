# Dynamic Island for macOS — Technical Handoff

> Context document for an AI model taking over this project. It describes what the
> app does, how it is built, every non-obvious technical decision, and the known
> hard limits. Read it top to bottom before editing.

## 1. What the app is

A native macOS menu-bar app (no Dock icon, no main window) that draws a small
"Dynamic Island"–style widget around the MacBook notch — modeled on
dynamiclake.com. It is a SwiftPM **executable** (not an Xcode project); it is
built and bundled by `./build_app.sh` into `DynamicIsland.app`, then ad-hoc
signed.

Core behaviors:

- **Now-playing pop-out.** When audio plays in *any* app (Spotify, Apple Music,
  or a browser playing YouTube/SoundCloud/etc.), the island grows wider than the
  notch: album art peeks out to the **left** of the notch, an audio-visualizer
  equalizer to the **right**. Nothing is ever drawn *over* the physical notch.
- **Idle = exactly notch-sized.** With no activity it matches the notch and is
  invisible (black on black).
- **Slide-reveal animation.** Icons appear to slide out from *behind* the notch
  (achieved by clipping content to the island shape as it widens — not a fade).
- **Pause behavior.** When a real app player (Spotify/Music) pauses, the art
  shrinks *in place* and dims, the equalizer stays the same size but dims, and
  both linger ~5s then disappear; resuming within 5s springs them back. Browser
  media does **not** linger (see §7, "leave-video" fix).
- **Track-change flip.** When the song changes, the collapsed album thumb does a
  coin/card flip (Y-axis 3D rotation) and reveals the new cover on the back half.
- **Click to switch.** Clicking the music pop-out activates (brings to front) the
  app that owns the current track. There is **no hover-to-expand** anymore.
- **Frontmost suppression.** The island hides while the app that owns the track
  is already frontmost (you don't need it when you're looking at Spotify). It
  shows only when a *different* app is frontmost.
- **Fullscreen hide.** When an app is fullscreen on the notched screen (notch not
  visible), the whole window is ordered out.
- **Charging flourish.** Plugging in power shows a brief ⚡ + battery% for ~3s.
  There is deliberately no low-battery warning (macOS already shows one).
- **Lock detection exists but cannot be shown on the lock screen** (see §8).

Design constraints the user cares about:
- Keep RAM low (target < 50 MB; currently ~41–46 MB).
- Do **not** duplicate anything macOS already shows (privacy dots, screen-record
  indicator, AirPods, volume HUD). All of those were explicitly rejected.
- Should work when shared with others without special setup.

The user communicates in Norwegian; UI strings are Norwegian ("Ingen avspilling",
"Lader", "Avslutt").

## 2. Project layout

```
Package.swift                      swift-tools 6.0, macOS v14, .v5 language mode
builder/                           Rust build tool (replaces the old build_app.sh):
                                   swift build → compile dylib → assemble + ad-hoc
                                   sign .app → prompt to install/open
Helpers/mrhelper.c                 C bridge to the private MediaRemote framework
Sources/DynamicIsland/
  App/
    main.swift                     entry point
    AppDelegate.swift              NSApplication delegate; menu-bar item + menu
    Log.swift                      debug logger → /tmp/dynamicisland.log (removable)
  Media/
    SystemNowPlaying.swift         persistent python3+dylib streaming helper
    MediaFallback.swift            Spotify/Music + browser via AppleScript
    MediaKeys.swift                synthesize media keys (last-resort transport)
    PowerMonitor.swift             IOKit.ps charging detection
  Models/
    NowPlayingInfo.swift           the shared now-playing snapshot struct
    NowPlayingModel.swift          @MainActor ObservableObject; the app's brain
  Views/                           one component per file:
    IslandView.swift               the main island that composes the pieces
    NotchShape.swift               the concave-top Dynamic Island shape
    EqualizerView.swift            audio visualizer bars
    FlippingArtwork.swift          coin-flip album art on track change
    ChargingRing.swift             circular battery gauge + battery-color logic
    LockIslandView.swift           static lock-screen lock icon
    NotchMetrics.swift             notch geometry
    IslandState.swift              shared UI state (ObservableObject)
  Window/
    NotchController.swift          core: panels + stored state + init; the rest is
                                   split into extensions, one concern each:
    NotchController+Windows.swift      builds the main + lock panels
    NotchController+Geometry.swift     screen/notch math, positioning, display changes
    NotchController+ClickThrough.swift mouse tracking → OS-level click-through
    NotchController+Activation.swift   click-to-switch + frontmost suppression
    NotchController+Charging.swift     the plug-in battery flourish
    NotchController+Visibility.swift   hide in fullscreen, lock-screen lock icon
    SkyLightSpace.swift            private SkyLight bridge for the lock screen
```

`NowPlayingInfo` is the single metadata struct everything converges on:
`title, artist, album, artwork (NSImage?), artworkURL (String?), duration,
elapsed, isPlaying (Bool?), sourceApp (String?), pid (Int?)`. (It was previously
nested in a `MediaRemoteBridge` class whose in-process bridge was dead code — Apple
blocks MediaRemote for the app itself — so that class was removed and the struct
promoted to its own file.)

## 3. The window (NotchController.swift)

- `NotchPanel: NSPanel` with `canBecomeKey = canBecomeMain = false`, styleMask
  `[.borderless, .nonactivatingPanel]`, clear background, no shadow.
- Level = `CGWindowLevelForKey(.statusWindow)` so it floats above the menu bar.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary,
  .ignoresCycle]`.
- The window is a **fixed large size** (`maxWindowSize`, big enough for the
  dead/legacy expanded panel + glow) and never moves — it stays centered on the
  notch, top-aligned. Content inside sizes itself; the window does not resize per
  state anymore.
- Hosts a single SwiftUI `IslandView` via `NSHostingView`.

### Notch geometry
`targetScreen()` prefers the built-in display whose `safeAreaInsets.top > 0`
(the notched one). `metrics(for:)` derives `notchWidth` from
`screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`
and `notchHeight` from the top safe-area inset. On a notch-less Mac it synthesizes
a ~190×32 floating pill. Re-derived on `didChangeScreenParametersNotification`.

### Click-through (important, subtle)
The panel must not steal clicks meant for apps underneath it (menu-bar icons next
to the notch, the dead area where an old expanded panel used to be). Approach:
- `panel.ignoresMouseEvents` starts `true` (fully click-through).
- A **global** + **local** `NSEvent` mouse monitor (`mouseMoved`,
  `leftMouseDragged`) calls `updateForPointer()`.
- `updateForPointer()` sets `ignoresMouseEvents = false` **only** while the pop-out
  is shown *and* the pointer is within the notch rect (`insetBy -4`). Everything
  else passes through at the OS level.

This OS-level toggle replaced an earlier `hitTest` approach, which was unreliable
for click-through to *other* apps.

### Visibility / suppression state (three independent signals)
- `hiddenForFullscreen` — fullscreen on the notched screen → `panel.orderOut`.
- `suppressedForFrontmost` — the playing app is frontmost → don't show the pop-out
  (but window stays ordered-in).
- `state.locked` — screen locked (detected, but see §8).

`popoutShown` (controls click capture) = not fullscreen, and (locked, or
(not suppressed and (isPlaying or pausedLingering))).

### Fullscreen detection (non-obvious)
`isNotchScreenFullscreen()` uses `CGWindowListCopyWindowInfo`. The reliable signal
is **not** menu-bar absence (the menu bar persists). Instead: a fullscreen app
creates its *own* auto-hiding menu-bar overlay — a window owned by the app, at or
above `CGWindowLevelForKey(.mainMenuWindow)`, full screen width, < 50px tall, at
`origin.y <= 1`. Its presence ⇒ fullscreen. (Window Server / Dock / our own
window are skipped.)

### Click-to-activate
`state.onTapIsland` = `activatePlayingApp()` →
`NSRunningApplication(pid).activate([.activateAllWindows])`, where `pid` is
`model.playingPID`.

### Frontmost matching
`isPlayerFrontmost()` compares the frontmost app's PID to `playingPID`. Browsers
register now-playing from a **helper** process, so it also matches by bundle-id
prefix (`pb.hasPrefix(fb) || fb.hasPrefix(pb)`). It gates on `model.hasMedia`
(not `isPlaying`), so suppression holds through the pause-linger too.

## 4. Now-playing data flow — the hard part

### The MediaRemote problem
The system-wide now-playing info (what Control Center shows, covering *every* app
including browsers) lives in the private **MediaRemote** framework. On macOS
15.4+/26 Apple **blocks** MediaRemote for third-party-signed processes. The gate
is on the **process signature**, not an entitlement — so an ad-hoc-signed app
simply gets nothing back. (See the user memory note: "MediaRemote is
entitlement-gated for our app.")

### The workaround (SystemNowPlaying.swift + Helpers/mrhelper.c)
Load a tiny C dylib **inside an Apple-signed host** — `/usr/bin/python3` — via
ctypes. Apple-signed processes are *not* gated, so MediaRemote works there.

Key gotcha discovered the hard way: the dylib exports **ordinary functions**
(`mr_stream`, `mr_get_artwork`, `mr_command`) and is driven by calling them. Do
**not** use `__attribute__((constructor))` — that runs during `dlopen`, before the
runtime/run-loop is ready, and the async MediaRemote callbacks never fire. The
functions set up on `dispatch_get_main_queue()` and call `CFRunLoopRun()`.

`mrhelper.c` responsibilities:
- `mr_stream()` — persistent streamer. Registers
  `MRMediaRemoteRegisterForNowPlayingNotifications`, adds **local** CFNotification
  observers for play/pause + info + queue-change so it emits *immediately* on
  change, plus a 1s dispatch-timer heartbeat (keeps `elapsed` in sync, catches
  missed events). Each tick prints one JSON line (no artwork):
  `{"title","artist","album","id","duration","elapsed","isPlaying","pid"}`.
- `mr_get_artwork()` — one-off; prints base64 artwork (heavy, so only on track
  change). 3s timeout safety.
- `mr_command(int)` — transport: 0 play, 1 pause, 2 toggle, 4 next, 5 prev. Needs
  `CFRunLoopRunInMode(..., 0.5, false)` so the XPC command actually gets delivered
  before the process exits.

`SystemNowPlaying` (Swift side):
- `start(onUpdate:)` spawns **one long-lived** `python3 -c "...mr_stream()"`
  process and parses stdout line-by-line into `Info` (sourceApp = `"system"`).
  Respawns on unexpected termination.
- `fetchArtwork()` and `sendCommand()` are one-off `python3` invocations.
- **RAM lesson:** an earlier design spawned a python3 *per second*. That leaked
  zombie processes and pushed RAM to ~76 MB. The single persistent streamer fixed
  it (~41–46 MB).

### The AppleScript fallback (MediaFallback.swift)
Two reasons it exists:
1. If `python3`/the dylib is unavailable, it's the only source (polled 1/s).
2. Even when MediaRemote works, its `GetNowPlayingApplicationIsPlaying` **lags
   ~1.2s** on Spotify pause. Spotify/Music expose instant `player state` via
   AppleScript, so we reconcile (below).

`MediaFallback` can read:
- **Spotify / Apple Music** via AppleScript (`appFetch()`). Spotify duration is ms
  (÷1000); Music is seconds. Spotify exposes an artwork URL; Music does not. Sets
  `pid` from the running app. Locale note: numbers may use a comma decimal
  separator → normalized before `Double()`.
- **Browsers** (`browserFetch()`): Chrome/Canary/Brave/Edge/Arc/Vivaldi/Opera/
  Helium use `execute javascript`; Safari uses `do JavaScript`. The injected JS
  reads `navigator.mediaSession.metadata` + the first playing `<video>/<audio>`
  element → `isPlaying|title|artist|artworkURL|currentTime|duration`. Returns only
  when something is actually playing. (The live app currently gets browser media
  via the MediaRemote stream, sourceApp `"system"`, not via `browserFetch` —
  `handleStreamUpdate` only calls `appFetch()`.)

First AppleScript call to each app triggers the standard macOS Automation
permission prompt. Historical bug: a control-char separator caused AppleScript
error `-2741`; now uses a `|||` string separator.

### Reconciliation (NowPlayingModel.handleStreamUpdate / reconcile)
Each stream snapshot is reconciled with `appFetch()` (Spotify/Music only):
- If no app info → use the system snapshot (e.g. a browser).
- If system & app describe the **same track** (by normalized title) → trust the
  **app** state (instant + authoritative; fixes the pause lag).
- Otherwise prefer whichever is actually `isPlaying`.

`reconcile` and `sameTrack` are `nonisolated static` (run off-main on
`fallbackQueue`); results are applied back on `@MainActor`.

## 5. The model (NowPlayingModel.swift)

`@MainActor final class NowPlayingModel: ObservableObject`. Published: `title,
artist, album, artwork, artworkToken, isPlaying, duration, elapsed, hasMedia,
playingPID, accent (Color), pausedLingering`.

`artworkToken` is an Int bumped by `artwork`'s `didSet` — it changes exactly when
the cover image actually changes (which lands a beat *after* the title, since art
loads async). The view keys the track-change art animation on this, not the title,
so the flip fires when the new image is ready rather than showing the old art
flipping in and then blinking to the new one.

- `start()` picks the streaming helper if available, else the 1s poll timer. A
  separate 0.5s `tickTimer` advances `elapsed` locally between real updates so the
  scrubber is smooth.
- `apply(info)` updates fields, decides the pause-linger (§7), and loads artwork:
  embedded image → use directly; `artworkURL` (Spotify) → fetch once per track;
  `sourceApp == "system"` → `loadSystemArtwork` via the helper, keyed on
  `title|album` so it isn't refetched every tick.
- `accent` = dominant artwork color: downscale the image to 1×1 px, read the
  pixel, brighten in HSB so it reads on dark chrome. Used to tint the equalizer.
- `clear()` resets everything and cancels the linger.
- Transport: `togglePlayPause/next/previous` → `control(...)` routes to whatever
  is *actually* playing: system source → `mr_command` (targets the real now-
  playing app — this is why pausing a YouTube tab no longer accidentally starts
  Spotify); browser source → `browserCommand` JS; Spotify/Music → AppleScript;
  else synthesize a media key. `togglePlayPause` toggles `isPlaying` optimistically
  for instant UI feedback, corrected by the next stream snapshot.

## 6. The view (IslandView.swift)

- `NotchShape(topRadius, bottomRadius)` — bottom corners convex, top corners
  **concave** (scooped inward) so the island looks like it flares out of the
  screen edge. Collapsed uses `topRadius: 0` (flush with the notch).
- The black shape's size is driven *only* by `currentWidth/currentHeight`. Content
  lives in an `.overlay` and is `.clipShape(islandShape)` — so as the pill widens,
  content is **revealed** from behind the notch (the slide effect). The glow/
  shadow is applied *outside* the clip.
- `Activity` enum with priority **locked > charging > music > none**. `popKey`
  animates transitions between activity categories (spring).
- Collapsed layout: `HStack { collapsedLeft (width = sidePadding) | Spacer(minLength:
  notchWidth) | collapsedRight (width = sidePadding) }` — left/right peek past the
  notch, nothing covers the notch. `.onTapGesture` → `onTapIsland` when music.
  - `collapsedLeft`: locked → `lock.fill`; music → artwork thumb
    (`scaleEffect 0.65` + `opacity 0.5` when `musicDimmed`); charging → green
    `bolt.fill`.
  - `collapsedRight`: locked → empty; music → `EqualizerView` (dims but does **not**
    scale when paused); charging → `"\(level)%"`.
- `EqualizerView` — 5 capsule bars via `TimelineView(.animation(minimumInterval:
  1/24, paused: !active))`, so it costs nothing when idle. Heights come from two
  detuned sine waves per bar + smoothstep for organic motion.
- `FlippingArtwork` — the collapsed-left album thumb. On track change (keyed on
  `model.artworkToken`) it does a coin/card flip: `rotation3DEffect` around the Y
  axis rotates the cover edge-on (0→90°), swaps the image at 90° while it has zero
  width (so no mirrored back shows), then rotates the new cover back (−90→0°).
  ~0.3s per half (~0.6s total). It holds its own `shown` image in `@State` and
  reacts via `onChange(of: token)`; the midpoint swap is an `asyncAfter`. (Earlier
  attempts — a scale+cross-dissolve, then a pure opacity dissolve — were replaced
  because scaling two different covers that overlap reads as an *accidental* flip;
  the user wanted a deliberate flip instead.)
- There is a full **expanded** panel (`musicExpanded`, `chargingExpanded`) with
  artwork, title/artist, scrubber and transport buttons. `state.expanded` is
  **always false** now (hover-expand was removed) — this is **dead code** kept
  around; a cleanup could remove it along with `expandedWidth/Height`,
  `windowSize(...)`, the buttons rect in `regions()`, etc.

## 7. "Leaving a video" vs "pausing" (recent fix)

Problem: leaving a browser video (closing the tab / navigating away) made
MediaRemote report a stale `isPlaying:false` frame for the *same* track, which
looked like a pause and triggered the 5s linger pop-out.

Fix in `apply()`: only start the pause-linger for real app players —
`info.sourceApp == "Spotify" || "Music"`. For browser/system sources, going
not-playing hides immediately (no linger). Spotify/Music pause still lingers 5s
as before.

```swift
let pauseLingers = info.sourceApp == "Spotify" || info.sourceApp == "Music"
if wasPlaying && !isPlaying && !newTitle.isEmpty && pauseLingers {
    startPauseLinger()
} else if isPlaying || (wasPlaying && !isPlaying) {
    cancelPauseLinger()
}
```

## 8. Lock screen — a static lock icon via a SkyLight space (implemented)

Lock/unlock *detection*: `DistributedNotificationCenter` observers for
`com.apple.screenIsLocked` / `screenIsUnlocked` fire reliably (confirmed via
`/tmp/dynamicisland.log`). They call `NotchController.setLocked(_:)`.

**Drawing on the lock screen IS possible** — but *not* by raising a window's
level (that stays behind loginwindow's curtain). The working technique is to put
the window in a **custom SkyLight space whose absolute level sits above
loginwindow**, and let the window render before login.

Implementation:
- `Window/SkyLightSpace.swift` — a runtime bridge to private SkyLight symbols,
  `dlopen`'d from `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`,
  each symbol `dlsym`'d and `unsafeBitCast` to a `@convention(c)` type. Fails
  silently (singleton is `nil`) if SkyLight or any symbol is missing, so a future
  macOS that drops them just no-ops the lock icon. Symbols used:
  - `SLSMainConnectionID() -> Int32`
  - `SLSSpaceCreate(conn, 1, 0) -> Int32`
  - `SLSSpaceSetAbsoluteLevel(conn, space, 400)`
  - `SLSShowSpaces(conn, [space] as CFArray)`
  - `SLSSpaceAddWindowsAndRemoveFromSpaces(conn, space, [windowNumber] as CFArray, 7)`

  The space is created **once** in the initializer (create → set level 400 →
  show). `add(window:)` calls `SLSSpaceAddWindowsAndRemoveFromSpaces` and must be
  called **every time** the window is shown — the assignment doesn't survive
  `orderOut`.
- A **separate** lock-only panel (`NotchController.lockPanel`), distinct from the
  main panel so lock behaviour never touches normal click-through / now-playing:
  - `ignoresMouseEvents = true` (static, non-clickable),
  - `canBecomeVisibleWithoutLogin = true` (renders while locked),
  - same frame as the main panel, hosting `LockIslandView` — just a notch-sized
    black island with `lock.fill` peeking to the left of the notch.
  - Starts ordered out. On **lock**: re-center, `orderFrontRegardless()`, then
    `SkyLightSpace.shared?.add(window: lockPanel)`. On **unlock**: `orderOut`.
- The old per-activity lock UI was removed from `IslandView`/`IslandState`
  (`Activity.locked`, the `lock.fill` cases, `IslandState.locked`), and
  `state.locked` was dropped from `popoutShown` / `regions()` — the lock screen is
  now entirely the separate panel's job.

Ruled out alternatives (for the record): plain higher window levels /
`CGShieldingWindowLevel` (behind the curtain); `ScreenSaver.framework`
(full-screen, user-activated, Apple's engine process). Note the SkyLight symbols
are private and may change across macOS releases — hence the fail-silently design.

## 9. Other components

- `AppDelegate.swift` — creates the menu-bar `NSStatusItem` (SF Symbol
  `capsule.fill`), menu = "Dynamic Island" + "Avslutt"; owns the model +
  `NotchController`; starts the model. (A timer feature was added then **removed**
  entirely at the user's request — don't reintroduce it.)
- `PowerMonitor.swift` — IOKit.ps; `onPlugChange(Bool)` callback + `level` (battery
  %). An `initialized` flag suppresses the first reading so the flourish doesn't
  fire at launch.
- `Log.swift` — appends to `/tmp/dynamicisland.log`. Debug-only; safe to delete.
- `MediaKeys.swift` — synthesizes NX media keys as the last-resort transport.

## 10. Build & run

```bash
cd builder && cargo run        # build + assemble + ad-hoc sign DynamicIsland.app,
                               # then prompts: move to /Applications? open now?
open DynamicIsland.app         # run (if you answered no to the open prompt)
pkill -f DynamicIsland.app     # quit
```

The build tool is a small Rust program (`builder/src/main.rs`) that replaced the
old `build_app.sh`. It `cd`s to the project root (via `CARGO_MANIFEST_DIR`'s
parent), runs `swift build -c release`, compiles `Helpers/mrhelper.c` →
`.build/mrhelper.dylib` (`clang -dynamiclib -framework CoreFoundation -O2`),
ad-hoc signs the dylib, assembles the `.app` (binary → `Contents/MacOS/`, dylib →
`Contents/Resources/` where `SystemNowPlaying.dylibPath` looks first, writes
`Info.plist`), and ad-hoc signs the bundle (`codesign --force --deep --sign -`).
It then interactively offers to `ditto` the app to `/Applications/` and to open
it. Needs Rust ≥ 1.85 (Cargo edition 2024).

Ad-hoc signing is *why* MediaRemote is blocked for the app itself — hence the
python3 host workaround. `Info.plist` sets `LSUIElement` (agent app, no Dock icon)
and `NSAppleEventsUsageDescription` (the Automation prompt for Spotify/Music).

## 11. Gotchas / lessons for an editor

- Don't gate the stream on `GetNowPlayingApplicationIsPlaying` — its callback can
  block delivery; derive `isPlaying` from `PlaybackRate` in `fillFrom`, and only
  fall back to `GetPlaying` when rate is unknown.
- Don't spawn a process per poll (RAM/zombies). Keep the single streamer.
- Transport must go through `mr_command` for system/browser sources, or it targets
  the wrong app.
- Keep content in an overlay clipped to the shape; never let content drive the
  black shape's size, or the slide-reveal breaks and the pill mis-sizes.
- Concurrency: stream parsing is off-main; UI mutations hop to `@MainActor`.
  `reconcile`/`sameTrack` are `nonisolated static`; Task closures capture
  `[weak self]`.
- The expanded-panel path is dead (hover removed) but still compiled — treat as
  removable, but check `regions()`/`NotchMetrics`/`windowSize` references first.
```
