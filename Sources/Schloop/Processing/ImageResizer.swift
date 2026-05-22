import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

enum ImageResizer {
    enum Failure: Error, LocalizedError {
        case cannotReadImage
        case cannotCreateContext
        case cannotEncode

        var errorDescription: String? {
            switch self {
            case .cannotReadImage: return "Could not read the image."
            case .cannotCreateContext: return "Could not create graphics context."
            case .cannotEncode: return "Could not encode the resized image."
            }
        }
    }

    /// Loads a CGImage from a PNG/JPEG file on disk.
    static func loadCGImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure.cannotReadImage
        }
        return image
    }

    /// Resizes preserving aspect ratio so the longest edge equals `maxDimension`.
    /// Returns the original image if already <= maxDimension.
    static func resize(cgImage: CGImage, maxDimension: Int) throws -> CGImage {
        let width = cgImage.width
        let height = cgImage.height
        let longest = max(width, height)
        guard longest > maxDimension else { return cgImage }

        let scale = Double(maxDimension) / Double(longest)
        let newWidth = Int((Double(width) * scale).rounded())
        let newHeight = Int((Double(height) * scale).rounded())

        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Failure.cannotCreateContext
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resized = context.makeImage() else { throw Failure.cannotCreateContext }
        return resized
    }

    /// Writes a CGImage as PNG to the given URL, replacing any existing file.
    static func writePNG(cgImage: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw Failure.cannotEncode
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.cannotEncode }
    }
}
