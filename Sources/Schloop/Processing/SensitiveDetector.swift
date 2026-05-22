import Foundation
import CoreGraphics

/// Built-in regex rules that detect sensitive strings in OCR'd text.
/// Each rule can be enabled/disabled in Settings.
struct BlurRule: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let pattern: String
    /// If true, the match must have a relevant keyword (key|token|secret|api|auth|bearer|credential|password)
    /// within the same observation text — used to keep the generic-32-char rule from false-positiving.
    let requiresKeyword: Bool
    var enabled: Bool
}

extension BlurRule {
    /// v0.2 defaults — high-precision rules ship enabled; generic-keyword also on per user pick.
    static let builtIn: [BlurRule] = [
        // Cloud provider keys
        BlurRule(id: "aws-key",       name: "AWS access key",       pattern: "AKIA[A-Z0-9]{16}",                                 requiresKeyword: false, enabled: true),
        BlurRule(id: "openai-key",    name: "OpenAI API key",       pattern: "sk-[A-Za-z0-9_-]{20,}",                            requiresKeyword: false, enabled: true),
        BlurRule(id: "anthropic-key", name: "Anthropic API key",    pattern: "sk-ant-[A-Za-z0-9_-]+",                            requiresKeyword: false, enabled: true),
        BlurRule(id: "stripe-key",    name: "Stripe key",           pattern: "sk_(live|test)_[A-Za-z0-9]{24,}",                  requiresKeyword: false, enabled: true),
        // Developer tokens
        BlurRule(id: "github-pat",    name: "GitHub PAT",           pattern: "gh[ps]_[A-Za-z0-9]{36,}",                          requiresKeyword: false, enabled: true),
        BlurRule(id: "jwt",           name: "JWT",                  pattern: "eyJ[A-Za-z0-9_-]+\\.eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+", requiresKeyword: false, enabled: true),
        // Generic
        BlurRule(id: "generic-32",    name: "Generic 32+ char hex/base64 with keyword",
                 pattern: "[A-Za-z0-9+/=_-]{32,}",
                 requiresKeyword: true, enabled: true),
    ]

    private static let keywords: Set<String> = [
        "key", "keys", "apikey", "api_key", "token", "tokens", "secret",
        "secrets", "api", "auth", "bearer", "credential", "credentials", "password"
    ]

    static func containsKeyword(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return keywords.contains { lowered.contains($0) }
    }
}

enum SensitiveDetector {
    struct Match: Equatable {
        let ruleId: String
        let ruleName: String
        let matchedText: String
        let rect: CGRect    // pixel-space, origin top-left
    }

    /// Scans every OCR observation, returns sensitive-string matches with pixel-space bounding boxes.
    static func scan(observations: [TextRecognizer.Observation], rules: [BlurRule]) -> [Match] {
        var matches: [Match] = []
        let activeRules = rules.filter { $0.enabled }

        for observation in observations {
            let text = observation.text
            let nsText = text as NSString
            let textRange = NSRange(location: 0, length: nsText.length)

            for rule in activeRules {
                if rule.requiresKeyword && !BlurRule.containsKeyword(text) { continue }
                guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }

                let results = regex.matches(in: text, range: textRange)
                for result in results {
                    let matchedSubstring = nsText.substring(with: result.range)
                    guard let swiftRange = Range(result.range, in: text),
                          let pixelRect = observation.pixelRect(swiftRange) else { continue }
                    matches.append(Match(
                        ruleId: rule.id,
                        ruleName: rule.name,
                        matchedText: matchedSubstring,
                        rect: pixelRect
                    ))
                }
            }
        }

        return matches
    }
}
