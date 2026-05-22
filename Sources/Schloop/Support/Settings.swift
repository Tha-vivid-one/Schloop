import Foundation

struct Settings: Codable, Equatable {
    var quietMode: QuietMode = QuietMode()

    struct QuietMode: Codable, Equatable {
        var enabled: Bool = true
        var maxDimension: Int = 1568
        var customScreenshotFolder: String? = nil

        /// Watch the system pasteboard for new image content (e.g. screenshot preview → Copy to Clipboard).
        /// When enabled and a clipboard image exceeds maxDimension, replace it in-place with the resized version.
        var clipboardEnabled: Bool = true
    }

    static func load() -> Settings {
        guard let url = settingsURL,
              let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return settings
    }

    func save() {
        guard let url = Settings.settingsURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url)
        }
    }

    static var settingsURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Schloop")
            .appendingPathComponent("settings.json")
    }
}
