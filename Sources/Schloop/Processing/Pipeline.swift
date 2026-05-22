import Foundation
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ProcessResult: Equatable {
    var didResize: Bool
    var beforeDim: CGSize
    var afterDim: CGSize
    var blurredCount: Int = 0
    var blurredRules: [String] = []   // human-readable rule names of items blurred
}

enum Pipeline {

    // MARK: - File path

    static func processFile(url: URL, settings: Settings) throws -> ProcessResult {
        let original = try ImageResizer.loadCGImage(at: url)
        let outcome = try processImage(original, settings: settings)
        if outcome.changed {
            try ImageResizer.writePNG(cgImage: outcome.image, to: url)
        }
        Log.info("File \(url.lastPathComponent): \(outcome.result.summary())")
        return outcome.result
    }

    // MARK: - Clipboard path

    static func processClipboardImage(_ image: NSImage, settings: Settings) -> (data: Data, result: ProcessResult)? {
        guard settings.quietMode.enabled || settings.blur.enabled else { return nil }

        guard let original = bestCGImage(from: image) else {
            Log.error("Clipboard image had no usable CGImage representation")
            return nil
        }

        do {
            let outcome = try processImage(original, settings: settings)
            if !outcome.changed { return nil }
            guard let data = pngData(from: outcome.image) else {
                Log.error("Could not encode processed clipboard image to PNG")
                return nil
            }
            Log.info("Clipboard image: \(outcome.result.summary())")
            return (data, outcome.result)
        } catch {
            Log.error("Clipboard pipeline failed: \(error)")
            return nil
        }
    }

    // MARK: - Core pipeline

    private struct Outcome {
        let image: CGImage
        let result: ProcessResult
        let changed: Bool
    }

    /// Runs (optional) blur, then (optional) resize. Both stages may be skipped per settings.
    /// `changed` is true if either stage modified the image.
    private static func processImage(_ original: CGImage, settings: Settings) throws -> Outcome {
        let beforeDim = CGSize(width: original.width, height: original.height)

        // Stage 1: blur (before resize — OCR and bbox math are easier at full res)
        var current = original
        var blurredCount = 0
        var blurredRules: [String] = []

        if settings.blur.enabled {
            let observations = (try? TextRecognizer.recognize(cgImage: current)) ?? []
            let matches = SensitiveDetector.scan(observations: observations, rules: settings.blur.rules)
            if !matches.isEmpty {
                let rects = matches.map { $0.rect }
                do {
                    current = try BlurApplier.blur(
                        cgImage: current,
                        rects: rects,
                        radius: settings.blur.blurRadius
                    )
                    blurredCount = matches.count
                    blurredRules = matches.map { $0.ruleName }
                } catch {
                    Log.error("Blur step failed; keeping original: \(error)")
                }
            }
        }

        // Stage 2: resize
        var didResize = false
        if settings.quietMode.enabled {
            let longest = max(current.width, current.height)
            if longest > settings.quietMode.maxDimension {
                current = try ImageResizer.resize(
                    cgImage: current,
                    maxDimension: settings.quietMode.maxDimension
                )
                didResize = true
            }
        }

        let afterDim = CGSize(width: current.width, height: current.height)
        let result = ProcessResult(
            didResize: didResize,
            beforeDim: beforeDim,
            afterDim: afterDim,
            blurredCount: blurredCount,
            blurredRules: blurredRules
        )

        return Outcome(image: current, result: result, changed: didResize || blurredCount > 0)
    }

    // MARK: - NSImage helpers

    private static func bestCGImage(from image: NSImage) -> CGImage? {
        let reps = image.representations
        if let bitmap = reps.compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return bitmap.cgImage
        }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func pngData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }
}

private extension ProcessResult {
    func summary() -> String {
        var parts: [String] = []
        if didResize {
            parts.append("resized \(Int(beforeDim.width))×\(Int(beforeDim.height)) → \(Int(afterDim.width))×\(Int(afterDim.height))")
        } else {
            parts.append("kept at \(Int(beforeDim.width))×\(Int(beforeDim.height))")
        }
        if blurredCount > 0 {
            let unique = Array(Set(blurredRules)).sorted().joined(separator: ", ")
            parts.append("blurred \(blurredCount) item(s): \(unique)")
        }
        return parts.joined(separator: ", ")
    }
}
