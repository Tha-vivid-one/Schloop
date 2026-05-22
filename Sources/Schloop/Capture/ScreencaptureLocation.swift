import Foundation

enum ScreencaptureLocation {
    /// Resolves the macOS screenshot save folder.
    /// Reads `defaults read com.apple.screencapture location`, falls back to `~/Desktop`.
    static func current() -> URL {
        let task = Process()
        task.launchPath = "/usr/bin/defaults"
        task.arguments = ["read", "com.apple.screencapture", "location"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                let expanded = NSString(string: output).expandingTildeInPath
                return URL(fileURLWithPath: expanded)
            }
        } catch {
            Log.error("Could not read screencapture location: \(error)")
        }

        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
    }
}
