# Schloop

**Working name. Easy to rename.**

A post-processor for macOS screenshots. Runs after every screenshot and quietly makes the output better — resized, renamed, routed, blurred where it needs to be, shareable in one keystroke. Doesn't replace `Cmd+Shift+3/4/5`. Doesn't capture. Just makes the file that lands actually shippable.

**Pitch:** Your screenshots, automatically shippable. *Schloop.*

---

## Why this exists

Five recurring screenshot pains that no single Mac tool solves cleanly:

1. **Dimension breaks uploads.** Big screenshots crash Claude conversations, bounce from email, look ugly in Slack.
2. **Useless filenames.** 400 `Screenshot 2026-05-19 at 8.42.13 PM.png` files. Impossible to find anything.
3. **Desktop pollution.** Screenshots pile up on Desktop because nothing routes them anywhere semantic.
4. **Sensitive content leaks.** Pasting a terminal screenshot that has your API key visible is a once-a-month moment for every developer alive.
5. **Share is manual.** Drag → upload dialog → wait → paste. Should be one keystroke.

Existing tools play in the *capture* lane (Shottr, CleanShot, Skitch) or the *file-size compression* lane (Clop). Nobody owns the *post-process / make-shippable* lane. That's the gap.

---

## Non-goals

- Capture. macOS already does it well; don't fight muscle memory.
- Annotation suite. Maybe a tiny one in v2 (arrow + blur + box). Not Skitch.
- Continuous screen recording / Rewind-style memory. Different product.
- Windows / Linux. macOS-only at v1.
- AI-first marketing. AI may power some features under the hood. Never in the copy.

---

## v1 feature suite (ship this version)

### F1 — Auto-resize to quality tier
Watch the macOS screenshot folder. When a new screenshot exceeds the chosen max dimension, resize in place. Preserve aspect ratio. Tiers:

| Tier | Max edge | Use case |
|------|----------|----------|
| Small | 1024 px | Tiny files, casual sharing |
| **Good** | **1568 px** | **Default — clean balance** |
| Standard | 2000 px | High-detail sharing |
| Large | 2560 px | Design hand-off, screenshots-as-evidence |
| Original | — | Off |

### F2 — Auto-rename from content
OCR the screenshot (Vision framework, on-device, no model dependency). Take the most-salient phrase from the recognized text — largest text, or top-ranked text candidate. Slugify. Replace the default filename:

`Screenshot 2026-05-19 at 8.42.13 PM.png` → `2026-05-19-stripe-dashboard-overview.png`

Date prefix preserved (sortable). If OCR finds nothing meaningful, fall back to the source app name: `2026-05-19-figma.png`. User can disable per-folder or globally.

### F3 — Auto-route by source app
At screenshot time, capture the frontmost app (NSWorkspace). Route the file to a folder named after that app, under a user-chosen root:

```
~/Pictures/Screenshots/
├── Figma/
├── VSCode/
├── Slack/
├── Chrome/
│   └── (or by domain via Chrome AppleScript later)
└── _other/
```

Folder creation lazy. User can override per-app ("never route Slack screenshots — leave them on Desktop").

### F4 — Blur (auto + manual)
Two ways to blur, one settings model.

**Auto-blur (pattern detection)** — after OCR pass, run regex against recognized text for known sensitive patterns:

- AWS access keys: `AKIA[A-Z0-9]{16}`
- OpenAI keys: `sk-[A-Za-z0-9]{20,}`
- Anthropic keys: `sk-ant-[A-Za-z0-9_-]+`
- GitHub tokens: `ghp_[A-Za-z0-9]{36}`
- JWTs: `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`
- Stripe keys: `sk_(live|test)_[A-Za-z0-9]{24,}`
- Generic API key heuristic (keyword + 32+ char hex/base64 nearby)
- Email addresses (optional, user toggle)
- Phone numbers (optional, user toggle)

For each match, get the bounding box from VNRecognizedText. Apply CIGaussianBlur over those regions only. **No AI / no LLM / no cloud — Vision OCR is on-device ML built into macOS, regex is regex.**

**When does auto-blur fire?** Three modes (user setting):

| Mode | What happens |
|------|--------------|
| **Off** | No auto-blur. Manual editor still available. |
| **On share only** (recommended default) | Original screenshot saved untouched. Blur is applied only to the copy that goes through the share picker. You keep the full file on disk; recipients get the safe version. |
| **Always on save** | Blur applied before the file is written. Original is gone. Destructive — for paranoid mode. |

**Manual blur editor** — accessible from menu bar ("Edit screenshot…") or by right-clicking any image in Finder (via Quick Action / Services menu). Opens a small native window with:

- Click-and-drag to draw blur rectangles
- Adjustable blur intensity slider
- Optional solid black instead of blur
- "Detect sensitive" button (runs the same OCR + regex pass, auto-fills rectangles)
- Save / Save a Copy / Share

User-configurable rules in Settings; ships with sensible defaults. Sensitive notification on auto-blur events ("Blurred 1 item — reveal in Finder").

### F5 — Quick share via custom picker
Global hotkey (default `Cmd+Shift+S` — fallback `Cmd+Option+S` if taken). Triggers a small branded popover with all share destinations in one place.

**Native Mac targets** (via `NSSharingService` under the hood — pixel-native behavior, just our picker UI):

- Messages
- Mail
- AirDrop
- Notes
- Reminders
- Any installed app that registered a share extension (Slack, Telegram, Things, Bear, Photos, Notion, etc. — whatever the user has)

**Plus Schloop-specific destinations:**

- Copy to clipboard (image or file path)
- Save to a custom folder
- Custom destinations list — user-defined entries in Settings:
  - Custom S3 bucket (BYOK)
  - Custom webhook URL (POST the image as multipart)
  - Custom `scp` / `rsync` template
  - File path "drop zone"

If "Blur on share" is enabled, blur applies to the copy that goes through the picker — original untouched on disk.

**Why a custom picker, not Apple's stock share popover?** Apple's popover can't be restyled or extended — custom destinations would have to live in a separate menu, two clicks deep. Building our own picker means native targets + custom destinations sit in the same surface. Same row. One click. Branded and tight.

---

## v2 features (post-launch)

- OCR extract — global hotkey to grab text out of any image / screen region
- Screenshot history search — last 100 screenshots, search by content
- Profiles — different settings for design vs coding vs Slacking, hotkey-swappable
- Light annotation — arrow + box + blur. Three tools, no more.
- iOS companion — AirDrop screenshot from phone, lands processed on Mac
- LLM-assisted rename (when heuristic produces garbage)
- Team blur rules (B2B unlock — central policy, audit log)

---

## Architecture

### Stack
- **SwiftUI** + AppKit interop (for menu bar, FSEventStream, NSWorkspace observers)
- **Vision framework** for OCR
- **Core Image** for blur compositing
- **Core Graphics** for resize
- **HotKey** library (Swift package) for global shortcuts
- **No Python, no Node, no external models, no daemons.** Single binary.

### Module map

```
Shipshape/
├── App/
│   ├── ShipshapeApp.swift           # @main, MenuBarExtra
│   └── AppState.swift               # ObservableObject, settings + stats
├── Capture/
│   ├── ScreenshotWatcher.swift      # FSEventStream on screencapture folder
│   ├── ScreencaptureLocation.swift  # `defaults read com.apple.screencapture`
│   └── FrontmostAppTracker.swift    # NSWorkspace observer, app-at-time-of-capture
├── Processing/
│   ├── Pipeline.swift               # orchestrates stages: resize → rename → route → (blur deferred to share if mode=share-only)
│   ├── ImageResizer.swift           # CGImage resize, preserve aspect
│   ├── TextRecognizer.swift         # VNRecognizeTextRequest wrapper
│   ├── SensitiveDetector.swift      # regex rules + match → bounding boxes
│   ├── BlurApplier.swift            # CIGaussianBlur on bounding boxes (used by auto + manual)
│   ├── Renamer.swift                # OCR → slug → new name
│   └── Router.swift                 # move file to per-app folder
├── Editor/
│   ├── ManualBlurEditor.swift       # window: draw rectangles, intensity slider, detect-sensitive button
│   └── EditorCanvas.swift           # the drawing surface (NSView wrapped in SwiftUI)
├── Share/
│   ├── ShareHotkey.swift            # global hotkey via HotKey package
│   ├── SharePickerWindow.swift      # custom branded popover (lists native + custom)
│   ├── NativeShareBridge.swift      # NSSharingService wrappers (Messages, AirDrop, Mail, etc.)
│   ├── CustomDestinations.swift     # user-defined S3/webhook/scp/folder entries
│   └── ShareCoordinator.swift       # apply blur-on-share, route to chosen destination
├── UI/
│   ├── MenuBarView.swift            # MenuBarExtra content (status, pause, recent)
│   ├── SettingsWindow.swift         # full settings (tiers, blur rules, share dest, hotkeys)
│   ├── OnboardingWindow.swift       # first-launch permission walkthrough
│   └── Notifications.swift          # UNUserNotification wrapper
└── Support/
    ├── Settings.swift               # @AppStorage / Codable persistence
    ├── Logger.swift                 # OSLog wrapper
    └── Permissions.swift            # request + check Files/Notifications/Accessibility
```

### Processing pipeline order

```
new file detected
    │
    ▼
1. OCR (one Vision pass, reused by next 2 stages)
    │
    ├──► 2. Sensitive detection → bounding boxes → blur in place
    │
    ├──► 3. Resize to tier max
    │
    ├──► 4. Rename from OCR + app context
    │
    └──► 5. Route to per-app folder
    │
    ▼
notification (one combined toast, e.g. "Resized, blurred 1 key, moved to Figma/")
```

Single OCR pass shared across blur + rename. Stages skippable per settings.

### Permissions needed

- **Files & Folders** — to write to the screenshot location
- **Notifications** — for status toasts
- **Accessibility** — for the global share hotkey
- **No Screen Recording needed** (we process files, not screen pixels — big UX win over capture tools)

### Performance budgets

- File detected → first stage starts: < 50ms
- OCR + blur + resize + rename + route for a 5K screenshot: < 1s
- Memory at idle: < 50 MB
- No background CPU when nothing is happening (FSEvents is event-driven)

---

## UX principles

- **Invisible by default.** App lives in menu bar. Doesn't interrupt. Notifications are subtle and dismissible.
- **One-tier picker for resize.** Not a slider. Named tiers, descriptive labels. No raw pixel jargon in the default surface.
- **Reveal-in-Finder on every notification.** Trust = "show me what you did to my file."
- **Pause is one click.** Tray menu: Pause 30 min / 1 hour / Resume now.
- **No AI marketing.** Anywhere. Ever. Features are described by what they do.

---

## Design language

- Native SwiftUI. Match the polish of ArgusMenuBar / Kokoro-Reader (sibling tools in this folder).
- Menu bar icon: SF Symbol `square.arrowtriangle.4.outward` or `photo.badge.checkmark` (decide during design pass).
- Accent color: TBD. Lean warm/neutral — not blue (overused). Maybe a soft coral or sage.
- Settings window uses macOS standard SwiftUI Settings scene — feels native, free Cmd+, support.

---

## v1 milestones

| Week | Milestone |
|------|-----------|
| 1 | Folder watch + resize working. Manual run, no UI. Solves Jarrett's Claude bug today. |
| 2 | OCR + sensitive detection + blur. Demo-able. |
| 3 | Rename + route + frontmost-app tracker. Full pipeline. |
| 4 | Menu bar UI, Settings, onboarding, share (imgur). Polish pass. Internal alpha. |

---

## Open questions

1. **Name.** Schloop is working. Final brand TBD before any public release.
2. **Default for blur mode.** Recommended default: **"Blur on share only"** — non-destructive (original preserved), still catches the demo moment when user actually shares. "Always on save" is opt-in for paranoid mode. Confirm before alpha.
3. **Per-folder rules vs global.** Power users want per-folder. v1 lean: global only, per-folder is v2.
4. **What about screenshots NOT taken via macOS?** (e.g. saved from a browser, dragged in). v1 only processes files matching the macOS screenshot pattern in the watched folder. v2 could let users drag any image to the menu bar icon.
5. **Custom share destination types — order of priority.** Webhook (POST) is most universal. S3 needs SDK. `scp` template is for power users. Lean: ship webhook + custom folder in v1, defer S3 and `scp` to v2.
6. **Pricing/distribution.** Deferred. Build first, decide later.

---

## Risks

- **Frontmost-app detection is racy.** macOS doesn't tag screenshots with source app. We poll NSWorkspace and timestamp; if the user takes a screenshot then switches apps within ~100ms, we may attribute wrong. Mitigation: cache last 3 frontmost apps with timestamps, match closest to file creation time.
- **Vision OCR latency on 5K+ screenshots.** Could be 800ms+. Mitigation: run on background queue; don't block the UI. Acceptable since user has already moved on.
- **Regex false positives for blur.** A 32-char string isn't always a secret. Mitigation: require keyword proximity for the generic heuristic; ship only high-precision rules by default; user can add/remove rules.
- **First-launch permission gauntlet.** Files + Notifications + Accessibility = 3 prompts. Mitigation: onboarding window walks user through each with copy explaining why.
- **App Sandbox vs FSEvents.** FSEvents on arbitrary folders typically needs the user to grant the folder via NSOpenPanel. Mitigation: onboarding asks user to pick their screenshot folder via standard open dialog — Apple-blessed pattern.

---

## What "done" looks like for v1

- Jarrett uses it daily for 2 weeks and stops thinking about screenshot dimensions
- One blur demo gets a real reaction from someone else
- 5 friends/colleagues have it installed and at least 3 keep it
- Project folder has a working DMG build + a one-page README + a 30-second demo video
- Decision point: ship publicly (GitHub release / Gumroad / App Store) or keep iterating
