# Schloop — Claude Code project notes

A native SwiftUI menu bar app for macOS. Post-processes screenshots: resize → rename → route → blur → share. v0.1 ships F1 (resize) only.

---

## ⚡ Finding the logs (read this first)

Schloop writes a persistent file log. **Don't ask the user where logs are — just read this file:**

```
~/Library/Logs/Schloop/schloop.log
```

### Quick commands

```bash
# Live tail (most useful when debugging)
tail -f ~/Library/Logs/Schloop/schloop.log

# Read everything
cat ~/Library/Logs/Schloop/schloop.log

# Last 100 lines
tail -100 ~/Library/Logs/Schloop/schloop.log

# Grep for errors
grep -E "\[ERROR\]" ~/Library/Logs/Schloop/schloop.log

# Find the most recent session
grep -n "session start" ~/Library/Logs/Schloop/schloop.log | tail -3
```

### What's in the log

- **Format:** `YYYY-MM-DD HH:MM:SS.mmm [LEVEL] [File:Line] message`
- **Levels:** `INFO` `ERROR` `DEBUG`
- **Session markers:** `=== Schloop session start · pid N · vX ===` and `=== Schloop session end ===` — use these to scope to one run.
- **Rotation:** at 5 MB → `schloop.log.1` → `.2` → `.3` → dropped. Total cap ~20 MB.
- **Mirror:** every line is also written to OSLog (subsystem `com.schloop.app`, category `main`) for Console.app users — but the file is canonical, agents should use it.

### Don't use Console.app for log inspection

Console.app is fine to read individual files but expensive when streaming. Always prefer `tail` / `cat` / `grep` on the file. The user explicitly opted into file logs to avoid Console.app CPU overhead.

### Running the app to reproduce

```bash
cd "/Users/jarretttruett/Documents/01 Projects/Tools/Schloop"
DEVELOPER_DIR=/Library/Developer/CommandLineTools swift run Schloop
```

The `DEVELOPER_DIR` override is required because `/Applications/Xcode.app` on this machine has an arm64/arm64e mismatch in `libxcrun.dylib`. The Command Line Tools toolchain works fine. Don't try to fix Xcode unless the user asks.

---

## Stack

- Swift 5.9+, macOS 13+
- SwiftUI `MenuBarExtra`, AppKit interop for FSEventStream and NSWorkspace
- Vision framework (for OCR — used in F4)
- Core Image (for blur — used in F4)
- Core Graphics + ImageIO (resize + PNG encode — used in F1)
- **No Python, no Node, no LLM, no external models, no cloud calls.** Single binary.
- Distribution path during dev: Swift Package Manager. `.xcodeproj` migration deferred until we need entitlements (notifications, hotkey accessibility, code signing).

## Module conventions

- `App/` — entry point, `AppState` ObservableObject
- `Capture/` — anything that watches the filesystem or system state
- `Processing/` — image-level work (resize, OCR, blur, rename)
- `Editor/` — manual blur editor (F4)
- `Share/` — share picker, native bridges, custom destinations (F5)
- `UI/` — SwiftUI views
- `Support/` — Settings, Logger, Permissions

Every module is `internal` by default; no public ABI to maintain.

## Code style

- Pragmatic. Comments only where the "why" isn't obvious from the code.
- Self-documenting names over comments.
- Use `Log.info` / `Log.error` / `Log.debug` (in `Support/Logger.swift`), never `print`. File logger writes to `~/Library/Logs/Schloop/schloop.log` with auto-rotation. Also mirrors to OSLog. Always-on, persists across crashes — no need to leave Console.app running.
- `@MainActor` on UI state; hop with `Task { @MainActor in ... }` from FSEvents callback.
- Codable for persistence. JSON at `~/Library/Application Support/Schloop/`.

## What NOT to add

- AI/LLM dependencies. Vision OCR ≠ AI marketing. Keep the brand AI-free in UI strings.
- Cloud roundtrips for the local pipeline. Even error reporting stays local.
- Heavy native modules (no sharp/ffmpeg/etc — Core Graphics handles everything we need).
- Capture features. Schloop is post-processing only. Use macOS's built-in screenshot.

## Running

```bash
swift run Schloop          # from project root
open Package.swift         # opens in Xcode
```

Menu bar icon top-right. Take a screenshot to test F1.

## Where to look first when something's off

- **Screenshots not getting resized?** Check `Log` output via Console.app (subsystem `com.schloop.app`). Likely the file pattern didn't match — see `ScreenshotWatcher.handleEvents`.
- **Folder not being watched?** Check `ScreencaptureLocation.current()` returned what you expect. macOS users can change the location via `Cmd+Shift+5 → Options → Save to`.
- **Resize quality bad?** `ImageResizer.resize` uses `.high` interpolation. Bump or experiment.

## v1 status tracker

| Feature | File entry points | Status |
|---------|-------------------|--------|
| F1 Resize | `Pipeline.swift`, `ImageResizer.swift` | ✅ v0.1 |
| F2 Rename | `Processing/Renamer.swift` (TBD) | ⏳ |
| F3 Route | `Processing/Router.swift` + `Capture/FrontmostAppTracker.swift` (TBD) | ⏳ |
| F4 Blur (auto + manual) | `Processing/TextRecognizer.swift`, `SensitiveDetector.swift`, `BlurApplier.swift`, `Editor/ManualBlurEditor.swift` (TBD) | ⏳ |
| F5 Share | `Share/SharePickerWindow.swift`, `NativeShareBridge.swift`, `CustomDestinations.swift`, `ShareCoordinator.swift` (TBD) | ⏳ |

## Companion docs

- `SPEC.md` — full product spec, all five features, architecture, open questions
- `README.md` — user-facing setup & status

## Session provenance

Per user's global rules (see `~/.claude/CLAUDE.md`), when writing new files or commits, read `~/.claude/.current-session` for SESSION_ID + CWD, and tag accordingly. This project lives under `01 Projects/Tools/Schloop`.
