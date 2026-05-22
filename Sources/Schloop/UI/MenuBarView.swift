import SwiftUI
import AppKit

struct QualityTier: Identifiable, Hashable {
    let name: String
    let maxDimension: Int
    let blurb: String
    var id: Int { maxDimension }

    static let all: [QualityTier] = [
        QualityTier(name: "Small", maxDimension: 1024, blurb: "Tiny files"),
        QualityTier(name: "Good", maxDimension: 1568, blurb: "Recommended"),
        QualityTier(name: "Standard", maxDimension: 2000, blurb: "Balanced"),
        QualityTier(name: "Large", maxDimension: 2560, blurb: "High detail"),
    ]

    static func match(_ dim: Int) -> QualityTier? {
        all.first { $0.maxDimension == dim }
    }
}

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let tier = QualityTier.match(appState.settings.quietMode.maxDimension)

        // Header
        if appState.isPaused, let until = appState.pauseUntil {
            Text("Paused until \(until, style: .time)")
            Button("Resume now") { appState.resume() }
            Divider()
        } else if !appState.settings.quietMode.enabled {
            Text("Quiet Mode: Off")
            Divider()
        } else {
            Text("Quality: \(tier?.name ?? "Custom") (\(appState.settings.quietMode.maxDimension)px)")
            Divider()
        }

        // Last event
        if let last = appState.last {
            let sourceTag = last.source == .clipboard ? "📋" : "🗂"
            if last.didResize {
                Text("\(sourceTag) \(last.label) — \(Int(last.beforeDim.width))×\(Int(last.beforeDim.height)) → \(Int(last.afterDim.width))×\(Int(last.afterDim.height))")
            } else {
                Text("\(sourceTag) \(last.label) (skipped — already small)")
            }
            Divider()
        }

        // Quality picker
        Menu("Quality") {
            ForEach(QualityTier.all) { t in
                Button {
                    appState.setMaxDimension(t.maxDimension)
                } label: {
                    HStack {
                        if appState.settings.quietMode.enabled
                            && appState.settings.quietMode.maxDimension == t.maxDimension {
                            Image(systemName: "checkmark")
                        }
                        Text("\(t.name) — \(t.maxDimension)px  ·  \(t.blurb)")
                    }
                }
            }
            Divider()
            Button {
                appState.setEnabled(false)
            } label: {
                HStack {
                    if !appState.settings.quietMode.enabled { Image(systemName: "checkmark") }
                    Text("Original — never resize")
                }
            }
        }

        // Sources toggle (file watch always on; clipboard can be turned off)
        Menu("Sources") {
            Button {
                // File watch is non-negotiable in v0.1 (only clipboard is toggleable).
            } label: {
                HStack {
                    Image(systemName: "checkmark")
                    Text("Watch screenshot folder (always on)")
                }
            }
            .disabled(true)

            Button {
                appState.setClipboardEnabled(!appState.settings.quietMode.clipboardEnabled)
            } label: {
                HStack {
                    if appState.settings.quietMode.clipboardEnabled {
                        Image(systemName: "checkmark")
                    }
                    Text("Watch clipboard (preview → Copy to Clipboard)")
                }
            }
        }

        // Pause submenu
        if !appState.isPaused {
            Menu("Pause") {
                Button("30 minutes") { appState.pause(minutes: 30) }
                Button("1 hour") { appState.pause(minutes: 60) }
                Button("4 hours") { appState.pause(minutes: 240) }
            }
        }

        Divider()

        // Stats
        Text("Resized: \(appState.stats.resized)  (file \(appState.stats.resizedFile), clipboard \(appState.stats.resizedClipboard))  ·  Skipped: \(appState.stats.skipped)")
            .font(.caption)

        Divider()

        Button("Reveal screenshot folder") {
            NSWorkspace.shared.activateFileViewerSelecting([appState.watchedFolder])
        }

        Menu("Logs") {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
            }
            Button("Open log in Console.app") {
                NSWorkspace.shared.open(Log.fileURL)
            }
            Button("Copy log path") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(Log.fileURL.path, forType: .string)
            }
        }

        Button("Quit Schloop") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
