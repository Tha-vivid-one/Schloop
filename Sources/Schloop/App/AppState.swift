import SwiftUI
import Combine
import CoreGraphics
import AppKit

struct LastEvent: Equatable {
    enum Source: String { case file, clipboard }
    var source: Source
    var label: String          // "Screenshot ...png" or "clipboard image"
    var beforeDim: CGSize
    var afterDim: CGSize
    var didResize: Bool
    var at: Date
}

struct Stats: Equatable {
    var resizedFile: Int = 0
    var resizedClipboard: Int = 0
    var skipped: Int = 0
    var totalSeen: Int = 0
    var resized: Int { resizedFile + resizedClipboard }
}

@MainActor
final class AppState: ObservableObject {
    @Published var settings: Settings
    @Published var stats: Stats = Stats()
    @Published var last: LastEvent? = nil
    @Published var pauseUntil: Date? = nil

    private var fileWatcher: ScreenshotWatcher?
    private var clipboardWatcher: ClipboardWatcher?

    init() {
        self.settings = Settings.load()
        startWatching()
    }

    var isPaused: Bool {
        guard let until = pauseUntil else { return false }
        return until > Date()
    }

    var watchedFolder: URL {
        if let custom = settings.quietMode.customScreenshotFolder, !custom.isEmpty {
            return URL(fileURLWithPath: NSString(string: custom).expandingTildeInPath)
        }
        return ScreencaptureLocation.current()
    }

    func startWatching() {
        // File watcher
        fileWatcher?.stop()
        let folder = watchedFolder
        let fw = ScreenshotWatcher(folder: folder) { [weak self] url in
            Task { @MainActor in self?.handleNewScreenshotFile(url: url) }
        }
        fw.start()
        fileWatcher = fw

        // Clipboard watcher
        clipboardWatcher?.stop()
        let cw = ClipboardWatcher { [weak self] image in
            self?.handleClipboardImage(image)
        }
        cw.start()
        clipboardWatcher = cw
    }

    // MARK: - File path

    private func handleNewScreenshotFile(url: URL) {
        stats.totalSeen += 1

        if isPaused {
            stats.skipped += 1
            Log.info("Paused — skipping file \(url.lastPathComponent)")
            return
        }

        guard settings.quietMode.enabled else {
            stats.skipped += 1
            return
        }

        do {
            let result = try Pipeline.processFile(url: url, settings: settings)
            if result.didResize { stats.resizedFile += 1 } else { stats.skipped += 1 }
            last = LastEvent(
                source: .file,
                label: url.lastPathComponent,
                beforeDim: result.beforeDim,
                afterDim: result.afterDim,
                didResize: result.didResize,
                at: Date()
            )
        } catch {
            Log.error("File pipeline failed for \(url.lastPathComponent): \(error)")
        }
    }

    // MARK: - Clipboard path

    private func handleClipboardImage(_ image: NSImage) {
        guard settings.quietMode.clipboardEnabled else { return }

        if isPaused {
            stats.skipped += 1
            Log.info("Paused — skipping clipboard image")
            return
        }

        guard let result = Pipeline.processClipboardImage(image, settings: settings) else {
            // No-op: either disabled, image not large enough, or encoding failed.
            return
        }

        stats.totalSeen += 1

        // Write the resized image back. Use writeObjects so NSImage advertises the right types.
        let pb = NSPasteboard.general
        pb.clearContents()
        if let resizedImage = NSImage(data: result.data) {
            pb.writeObjects([resizedImage])
        } else {
            // Fallback: write PNG bytes directly.
            pb.setData(result.data, forType: .png)
        }

        // Sync our baseline to the post-write count. Any subsequent change is by definition not ours.
        clipboardWatcher?.acknowledgeOurWrite()

        stats.resizedClipboard += 1
        last = LastEvent(
            source: .clipboard,
            label: "clipboard image",
            beforeDim: result.before,
            afterDim: result.after,
            didResize: true,
            at: Date()
        )
    }

    // MARK: - Settings

    func applySettings(_ newSettings: Settings) {
        let folderChanged = newSettings.quietMode.customScreenshotFolder
            != settings.quietMode.customScreenshotFolder
        settings = newSettings
        settings.save()
        if folderChanged { startWatching() }
    }

    func setMaxDimension(_ dim: Int) {
        var s = settings
        s.quietMode.maxDimension = dim
        s.quietMode.enabled = true
        applySettings(s)
    }

    func setEnabled(_ enabled: Bool) {
        var s = settings
        s.quietMode.enabled = enabled
        applySettings(s)
    }

    func setClipboardEnabled(_ enabled: Bool) {
        var s = settings
        s.quietMode.clipboardEnabled = enabled
        applySettings(s)
    }

    func pause(minutes: Int) {
        pauseUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func resume() { pauseUntil = nil }
}
