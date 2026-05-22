import Foundation
import OSLog

/// File-backed logger. Writes to `~/Library/Logs/Schloop/schloop.log`.
/// Persists across crashes / restarts. Rotates at 5 MB; keeps 3 historical files.
/// Also mirrors to OSLog for Console.app users who want it.
enum Log {
    private static let osLogger = os.Logger(subsystem: "com.schloop.app", category: "main")
    private static let writer = FileLogWriter()

    static func info(_ message: String, file: String = #fileID, line: Int = #line) {
        osLogger.info("\(message, privacy: .public)")
        writer.write(level: "INFO", message: message, file: file, line: line)
    }

    static func error(_ message: String, file: String = #fileID, line: Int = #line) {
        osLogger.error("\(message, privacy: .public)")
        writer.write(level: "ERROR", message: message, file: file, line: line)
    }

    static func debug(_ message: String, file: String = #fileID, line: Int = #line) {
        osLogger.debug("\(message, privacy: .public)")
        writer.write(level: "DEBUG", message: message, file: file, line: line)
    }

    /// URL of the active log file. Surfaced in the menu bar so users can reveal it.
    static var fileURL: URL { writer.activeURL }

    /// Directory holding active + rotated logs. Useful for "reveal in Finder."
    static var directoryURL: URL { writer.directoryURL }

    /// Called once at app launch to write a session marker.
    static func sessionStart() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        writer.write(level: "INFO", message: "=== Schloop session start · pid \(pid) · v\(version) ===", file: "Logger", line: 0)
    }
}

private final class FileLogWriter {
    let directoryURL: URL
    let activeURL: URL
    private let queue = DispatchQueue(label: "com.schloop.logwriter", qos: .utility)
    private let dateFormatter: DateFormatter
    private let maxBytes: Int = 5 * 1024 * 1024  // 5 MB
    private let maxRotations: Int = 3

    init() {
        let logsRoot = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("Schloop")
        try? FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)

        self.directoryURL = logsRoot
        self.activeURL = logsRoot.appendingPathComponent("schloop.log")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter = formatter

        // Make sure the file exists so `tail -f` from the start works.
        if !FileManager.default.fileExists(atPath: activeURL.path) {
            FileManager.default.createFile(atPath: activeURL.path, contents: nil)
        }
    }

    func write(level: String, message: String, file: String, line: Int) {
        let timestamp = dateFormatter.string(from: Date())
        let origin: String = {
            let trimmed = (file as NSString).lastPathComponent
                .replacingOccurrences(of: ".swift", with: "")
            return line > 0 ? "\(trimmed):\(line)" : trimmed
        }()
        let logLine = "\(timestamp) [\(level)] [\(origin)] \(message)\n"

        queue.async { [weak self] in
            guard let self = self else { return }
            self.rotateIfNeeded()
            self.append(logLine)
        }
    }

    private func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: activeURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            // File missing — recreate and write
            try? data.write(to: activeURL)
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: activeURL.path),
              let size = attrs[.size] as? Int,
              size >= maxBytes else { return }

        let fm = FileManager.default
        // Drop the oldest, shift the rest: .3 ← gone, .2 → .3, .1 → .2, active → .1
        let oldest = activeURL.appendingPathExtension("\(maxRotations)")
        try? fm.removeItem(at: oldest)

        for i in stride(from: maxRotations - 1, through: 1, by: -1) {
            let src = activeURL.appendingPathExtension("\(i)")
            let dst = activeURL.appendingPathExtension("\(i + 1)")
            if fm.fileExists(atPath: src.path) {
                try? fm.moveItem(at: src, to: dst)
            }
        }

        let firstRotation = activeURL.appendingPathExtension("1")
        try? fm.moveItem(at: activeURL, to: firstRotation)
        fm.createFile(atPath: activeURL.path, contents: nil)
    }
}
