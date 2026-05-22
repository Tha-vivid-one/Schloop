# Schloop

A post-processor for macOS screenshots. Quiet menu bar app. Watches your screenshot folder, resizes anything bigger than your chosen tier in place. F2-F5 (rename, route, blur, share) coming.

## v0.1 status

| Feature | Status |
|---------|--------|
| F1 Auto-resize to quality tier | ✅ working |
| F2 Auto-rename from content | ⏳ next |
| F3 Auto-route to folders | ⏳ next |
| F4 Blur (auto + manual) | ⏳ next |
| F5 Custom share picker | ⏳ next |

## Run it

Requires macOS 13+ and a recent Xcode / command-line tools.

```bash
cd "/Users/jarretttruett/Documents/01 Projects/Tools/Schloop"
swift run Schloop
```

The menu bar icon (✅ on a picture) appears top-right. Take a screenshot. Watch it shrink.

To stop: click the icon → Quit Schloop. (Or `Ctrl+C` in the terminal.)

## Open in Xcode

```bash
open Package.swift
```

Xcode opens the SPM package as a workspace. Run from there for debugging / breakpoints.

## How it works

1. On launch, reads your macOS screenshot save location via `defaults read com.apple.screencapture location` (falls back to `~/Desktop`).
2. Sets up an `FSEventStream` on that folder.
3. When a new file matching `Screenshot*.png` or `Screen Shot*.png` lands, waits 300ms for the write to settle, then:
   - Loads via `CGImageSource`
   - If longest edge > tier (default 1568px), resizes preserving aspect ratio via `CGContext` with `.high` interpolation
   - Writes back to the same path via `CGImageDestination` (PNG)
4. Menu bar header updates with last result.

No daemon, no Python, no external models, no AI. Vision OCR + regex blur lands in F4. No cloud round-trips ever for the local pipeline.

## Quality tiers (default = Good 1568px)

| Tier | Max edge |
|------|----------|
| Small | 1024 px |
| **Good** | **1568 px** (default) |
| Standard | 2000 px |
| Large | 2560 px |
| Original | off |

## Settings persistence

JSON at `~/Library/Application Support/Schloop/settings.json`. Edit by hand if you want, app reads on launch.

## Logs

Persistent file logs at `~/Library/Logs/Schloop/schloop.log`. Survives crashes and restarts. Auto-rotates at 5 MB (keeps `.1` / `.2` / `.3` historical files, ~20 MB total cap).

Easy ways to tail without burning CPU on Console.app:

```bash
tail -f ~/Library/Logs/Schloop/schloop.log
```

Or from the menu bar: **Logs → Reveal in Finder** (also: open in Console.app, copy path).

Each line is `YYYY-MM-DD HH:MM:SS.mmm [LEVEL] [File:Line] message`. Session boundaries marked with `=== Schloop session start · pid N · vX ===`.

## Project structure

```
Sources/Schloop/
├── App/
│   ├── SchloopApp.swift          @main + AppDelegate (sets .accessory activation)
│   └── AppState.swift            ObservableObject — settings, stats, pause, watcher lifecycle
├── Capture/
│   ├── ScreencaptureLocation.swift   reads `defaults` for screenshot folder
│   └── ScreenshotWatcher.swift       FSEventStream wrapper
├── Processing/
│   ├── Pipeline.swift            orchestrator (currently F1 only)
│   └── ImageResizer.swift        CGImageSource + CGContext resize + PNG encode
├── UI/
│   └── MenuBarView.swift         MenuBarExtra content
└── Support/
    ├── Settings.swift            Codable JSON in App Support
    └── Logger.swift              OSLog wrapper
```

## Known v0.1 limitations

- **No notifications yet.** SPM executables don't ship with a proper `.app` bundle / `Info.plist`, so `UNUserNotificationCenter` won't authorize. v0.2 turns this into an Xcode project and notifications come back. For now, last-event status is in the menu bar dropdown.
- **No quit-from-keyboard hotkey.** Standard macOS only — `Cmd+Q` from the menu only works when the menu is open.
- **Filename pattern is strict.** Only catches files literally starting with `Screenshot` or `Screen Shot`. Tools like CleanShot, Shottr, etc. don't match — by design. v2 can opt in.
- **No paused-state visual on the menu bar icon yet.** The icon stays the same; you have to open the menu to see paused status.

## Next milestones

- **Week 1 ✅** F1 working (this).
- **Week 2** F4 blur (Vision OCR + regex + Core Image compositing). The demo moment.
- **Week 3** F2 rename + F3 route. Pipeline grows; UI gets a Settings window.
- **Week 4** F5 custom share picker. Internal alpha DMG.

See [SPEC.md](./SPEC.md) for the full product spec.

## License

TBD.
