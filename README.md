# Dynamic Island for Mac

Ts vibecoeded as hell but free so who cares 🤑

## functions

- **Overlays the notch** on the main display (geometry is automatically retrieved via
  `safeAreaInsets` + `auxiliaryTopLeft/RightArea`). On displays without a notch, a floating pill is drawn.
- **Compact state:** when music is playing, album art peeks out on the left and a live equalizer on the right.
  Idle = exactly notch-sized (invisible).
- **Track-change flip:** the album art does a coin flip and reveals the new cover when the song changes.
- **Click to switch:** clicking the island jumps to whatever app owns the current track. It hides itself while
  that app is already frontmost, and while anything is fullscreen (no more hover-to-expand).
- **Lock screen:** a lock icon shows to the left of the notch while the screen is locked (drawn via a private
  SkyLight space above loginwindow).
- **Charging flourish:** a quick ⚡ + battery% when you plug in power.
- **Now Playing source:** the system-wide source (same one Control Center uses — covers *every* app, browsers
  included). `MediaRemote` is blocked for ad-hoc-signed apps, so a tiny helper dylib is loaded inside Apple-signed
  `/usr/bin/python3`. **Spotify / Apple Music / browsers** are also read via AppleScript for instant play/pause.
- **Playback control:** routed through `MediaRemote` (or AppleScript for Spotify/Music/browsers) so it always hits
  the app that's actually playing.
- **Agent app:** no Dock icon, just a small icon in the menu bar.

Stays light on RAM (~45 MB) via a single long-lived helper process — no per-second spawning.

## build and run

fast under deving:

```bash
swift run
```

Build a real `.app` that you can double-click, move to `/Applications`, or add to Login Items:

```bash
cd builder
cargo run
```

if you wan to open the app later do

```bash
open DynamicIsland.app
```
if u r a lazy bum build the bash script with

```bash
chmod +x build.sh
```
then do

```bash
./build.sh
```

## Misc

if you want to continue vibecoding ts you can use `ARCHITECTURE.md` to get the correct context about the cb(slang for code base)
