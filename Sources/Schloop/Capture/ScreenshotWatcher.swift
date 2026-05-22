import Foundation
import CoreServices

/// Watches a folder via FSEventStream for new files matching the macOS screenshot pattern.
final class ScreenshotWatcher {
    private let folder: URL
    private let onNewScreenshot: (URL) -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.schloop.fsevents", qos: .utility)

    init(folder: URL, onNewScreenshot: @escaping (URL) -> Void) {
        self.folder = folder
        self.onNewScreenshot = onNewScreenshot
    }

    func start() {
        let info = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [folder.path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, eventFlags, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = unsafeBitCast(paths, to: CFArray.self)
            let pathStrings = (cfPaths as? [String]) ?? []
            watcher.handleEvents(paths: pathStrings, flags: eventFlags, count: count)
        }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            Log.error("FSEventStreamCreate failed for \(folder.path)")
            return
        }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        Log.info("Watching: \(folder.path)")
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleEvents(
        paths: [String],
        flags: UnsafePointer<FSEventStreamEventFlags>,
        count: Int
    ) {
        for i in 0..<count {
            guard i < paths.count else { continue }
            let path = paths[i]
            let url = URL(fileURLWithPath: path)
            let filename = url.lastPathComponent.lowercased()

            // macOS screenshot patterns:
            //   "Screenshot 2026-05-19 at 8.42.13 PM.png"
            //   "Screen Shot 2024-01-01 at 1.23.45 PM.png" (older macOS)
            //   "CleanShot 2026-..." etc are NOT auto-handled (they're not from system).
            guard filename.hasPrefix("screenshot") || filename.hasPrefix("screen shot") else { continue }
            guard filename.hasSuffix(".png") else { continue }

            let flag = flags[i]
            let isCreated = (flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)) != 0
            let isRenamed = (flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)) != 0
            guard isCreated || isRenamed else { continue }

            // Brief delay — macOS writes the file then renames; let it settle.
            queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                self?.onNewScreenshot(url)
            }
        }
    }

    deinit { stop() }
}
