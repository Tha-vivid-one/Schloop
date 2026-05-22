import Foundation
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ProcessResult: Equatable {
    var didResize: Bool
    var beforeDim: CGSize
    var afterDim: CGSize
}

enum Pipeline {
    /// File path: load image, resize if exceeds maxDimension, write back to the same path.
    static func processFile(url: URL, settings: Settings) throws -> ProcessResult {
        let cgImage = try ImageResizer.loadCGImage(at: url)
        let beforeDim = CGSize(width: cgImage.width, height: cgImage.height)

        guard settings.quietMode.enabled else {
            return ProcessResult(didResize: false, beforeDim: beforeDim, afterDim: beforeDim)
        }

        let longest = max(cgImage.width, cgImage.height)
        guard longest > settings.quietMode.maxDimension else {
            return ProcessResult(didResize: false, beforeDim: beforeDim, afterDim: beforeDim)
        }

        let resized = try ImageResizer.resize(
            cgImage: cgImage,
            maxDimension: settings.quietMode.maxDimension
        )
        try ImageResizer.writePNG(cgImage: resized, to: url)

        let afterDim = CGSize(width: resized.width, height: resized.height)
        Log.info("Resized file \(url.lastPathComponent): \(Int(beforeDim.width))×\(Int(beforeDim.height)) → \(Int(afterDim.width))×\(Int(afterDim.height))")
        return ProcessResult(didResize: true, beforeDim: beforeDim, afterDim: afterDim)
    }

    /// Clipboard path: takes the image found on pasteboard, returns a resized PNG `Data` + dimensions if it
    /// needed shrinking. Returns nil if already small enough (caller should leave clipboard alone).
    static func processClipboardImage(_ image: NSImage, settings: Settings) -> (data: Data, before: CGSize, after: CGSize)? {
        guard settings.quietMode.enabled else { return nil }

        // Pull a CGImage with TRUE pixel dimensions. NSImage.size is in points.
        guard let cgImage = bestCGImage(from: image) else {
            Log.error("Clipboard image had no usable CGImage representation")
            return nil
        }

        let beforeDim = CGSize(width: cgImage.width, height: cgImage.height)
        let longest = max(cgImage.width, cgImage.height)
        guard longest > settings.quietMode.maxDimension else { return nil }

        do {
            let resized = try ImageResizer.resize(cgImage: cgImage, maxDimension: settings.quietMode.maxDimension)
            guard let data = pngData(from: resized) else {
                Log.error("Could not encode resized clipboard image to PNG")
                return nil
            }
            let afterDim = CGSize(width: resized.width, height: resized.height)
            Log.info("Resized clipboard image: \(Int(beforeDim.width))×\(Int(beforeDim.height)) → \(Int(afterDim.width))×\(Int(afterDim.height))")
            return (data, beforeDim, afterDim)
        } catch {
            Log.error("Clipboard resize failed: \(error)")
            return nil
        }
    }

    /// Picks the largest pixel-dimension representation from an NSImage, then materializes a CGImage from it.
    private static func bestCGImage(from image: NSImage) -> CGImage? {
        // Try the bitmap reps first — those have true pixel dimensions.
        let reps = image.representations
        if let bitmap = reps.compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }) {
            return bitmap.cgImage
        }
        // Fall back to whatever NSImage gives us.
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
