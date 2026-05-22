import Foundation
import AppKit

/// Watches the system pasteboard for new image content (e.g. macOS screenshot preview → Copy to Clipboard,
/// or CleanShot X / Shottr / any other tool that copies an image).
///
/// macOS has no pasteboard-change notification; polling `changeCount` is the standard pattern.
@MainActor
final class ClipboardWatcher {
    private let pasteboard = NSPasteboard.general
    private let pollInterval: TimeInterval
    private let onNewImage: (NSImage) -> Void

    /// Last changeCount we've inspected. After we write to the pasteboard ourselves we update this
    /// to the post-write count so we don't re-process our own output.
    private var lastChangeCount: Int

    private var timer: Timer?

    init(pollInterval: TimeInterval = 0.5, onNewImage: @escaping (NSImage) -> Void) {
        self.pollInterval = pollInterval
        self.onNewImage = onNewImage
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.info("Clipboard watcher started (poll \(pollInterval)s, initial changeCount=\(lastChangeCount))")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call AFTER you've written to the pasteboard. Sets our baseline to the current count so the
    /// next real user-driven change is what we react to.
    func acknowledgeOurWrite() {
        lastChangeCount = pasteboard.changeCount
        Log.debug("Acknowledged our write, lastChangeCount=\(lastChangeCount)")
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }

        let previous = lastChangeCount
        lastChangeCount = current

        let types = (pasteboard.types ?? []).map { $0.rawValue }
        let hasImage = pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
        Log.info("Clipboard changed: \(previous) → \(current), types=\(types), hasImage=\(hasImage)")

        guard hasImage, let image = NSImage(pasteboard: pasteboard) else {
            Log.debug("Clipboard change ignored — no image content")
            return
        }

        onNewImage(image)
    }

    deinit { timer?.invalidate() }
}
