import Foundation

struct Settings: Codable, Equatable {
    var quietMode: QuietMode = QuietMode()
    var blur: BlurSettings = BlurSettings()

    struct QuietMode: Codable, Equatable {
        var enabled: Bool = true
        var maxDimension: Int = 1568
        var customScreenshotFolder: String? = nil
        var clipboardEnabled: Bool = true
    }

    struct BlurSettings: Codable, Equatable {
        /// Auto-blur is OFF by default — opt-in. v0.3 will add a "share-only" mode (requires F5 share picker).
        var enabled: Bool = false
        var rules: [BlurRule] = BlurRule.builtIn
        var blurRadius: Double = 18
    }

    static func load() -> Settings {
        guard let url = settingsURL,
              let data = try? Data(contentsOf: url) else {
            return Settings()
        }
        // Tolerant decode: if blur settings aren't in the JSON yet (older versions), fall back to defaults
        // for those fields rather than dropping the whole settings file.
        if let settings = try? JSONDecoder().decode(Settings.self, from: data) {
            return Settings.withMissingRulesFilledIn(settings)
        }
        // Backward-compat: try decoding just the v0.1.x shape (no blur key).
        if let legacy = try? JSONDecoder().decode(LegacyV01.self, from: data) {
            return Settings(quietMode: legacy.quietMode, blur: BlurSettings())
        }
        return Settings()
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

    /// If new built-in rules were added in this version, merge them into the user's stored rules (preserving
    /// any per-rule enable/disable state the user had set).
    private static func withMissingRulesFilledIn(_ stored: Settings) -> Settings {
        var s = stored
        let storedIds = Set(s.blur.rules.map { $0.id })
        for builtin in BlurRule.builtIn where !storedIds.contains(builtin.id) {
            s.blur.rules.append(builtin)
        }
        return s
    }

    private struct LegacyV01: Codable {
        var quietMode: QuietMode
    }
}
