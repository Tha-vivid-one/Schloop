import SwiftUI
import Combine
import CoreGraphics
import AppKit

struct LastEvent: Equatable {
    enum Source: String { case file, clipboard }
    var source: Source
    var label: String
    var beforeDim: CGSize
    var afterDim: CGSize
    var didResize: Bool
    var blurredCount: Int
    var at: Date
}

struct Stats: Equatable {
    var resizedFile: Int = 0
    var resizedClipboard: Int = 0
    var blurredImages: Int = 0
    var blurredItems: Int = 0
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
        fileWatcher?.stop()
        let folder = watchedFolder
        let fw = ScreenshotWatcher(folder: folder) { [weak self] url in
            Task { @MainActor in self?.handleNewScreenshotFile(url: url) }
        }
        fw.start()
        fileWatcher = fw

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

        do {
            let result = try Pipeline.processFile(url: url, settings: settings)
            recordResult(result, source: .file, label: url.lastPathComponent)
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

        guard let outcome = Pipeline.processClipboardImage(image, settings: settings) else {
            return
        }

        stats.totalSeen += 1

        let pb = NSPasteboard.general
        pb.clearContents()
        if let resizedImage = NSImage(data: outcome.data) {
            pb.writeObjects([resizedImage])
        } else {
            pb.setData(outcome.data, forType: .png)
        }
        clipboardWatcher?.acknowledgeOurWrite()

        recordResult(outcome.result, source: .clipboard, label: "clipboard image")
    }

    // MARK: - Stats

    private func recordResult(_ result: ProcessResult, source: LastEvent.Source, label: String) {
        if result.didResize {
            switch source {
            case .file: stats.resizedFile += 1
            case .clipboard: stats.resizedClipboard += 1
            }
        } else if result.blurredCount == 0 {
            stats.skipped += 1
        }
        if result.blurredCount > 0 {
            stats.blurredImages += 1
            stats.blurredItems += result.blurredCount
        }
        last = LastEvent(
            source: source,
            label: label,
            beforeDim: result.beforeDim,
            afterDim: result.afterDim,
            didResize: result.didResize,
            blurredCount: result.blurredCount,
            at: Date()
        )
    }

    // MARK: - Settings mutations

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

    func setBlurEnabled(_ enabled: Bool) {
        var s = settings
        s.blur.enabled = enabled
        applySettings(s)
    }

    func setRuleEnabled(_ ruleId: String, enabled: Bool) {
        var s = settings
        if let idx = s.blur.rules.firstIndex(where: { $0.id == ruleId }) {
            s.blur.rules[idx].enabled = enabled
            applySettings(s)
        }
    }

    func pause(minutes: Int) {
        pauseUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func resume() { pauseUntil = nil }
}
