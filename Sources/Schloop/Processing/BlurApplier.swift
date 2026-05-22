import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Applies Gaussian blur to specific pixel-space rectangles on a CGImage.
/// Pads each rect slightly so the blur edge isn't right at the text boundary (cleaner look).
enum BlurApplier {

    enum Failure: Error { case renderFailed }

    /// Blurs the given pixel-space rectangles on the source image. Returns the new CGImage.
    /// Rectangles use top-left origin in pixel units (matching CGImage / TextRecognizer output).
    /// `radius` is the Gaussian blur radius in pixels at full resolution.
    static func blur(cgImage: CGImage, rects: [CGRect], radius: Double = 18, padding: CGFloat = 4) throws -> CGImage {
        guard !rects.isEmpty else { return cgImage }

        let ci = CIContext(options: [.useSoftwareRenderer: false])
        let baseImage = CIImage(cgImage: cgImage)

        // Blur the whole image once.
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = baseImage.clampedToExtent()  // avoid transparent fringe at edges
        blurFilter.radius = Float(radius)
        guard let blurredFull = blurFilter.outputImage?.cropped(to: baseImage.extent) else {
            throw Failure.renderFailed
        }

        // Build a mask: black background, white rectangles at the sensitive regions.
        // CI coordinate space is bottom-left origin, so flip Y.
        let maskExtent = baseImage.extent
        let maskColorSpace = CGColorSpaceCreateDeviceGray()
        let format: CIFormat = .L8
        let width = Int(maskExtent.width)
        let height = Int(maskExtent.height)
        let bytesPerRow = width
        var maskBytes = [UInt8](repeating: 0, count: width * height)

        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        for var rect in rects {
            rect = rect.insetBy(dx: -padding, dy: -padding).intersection(imageBounds)
            if rect.isEmpty { continue }

            let x0 = max(0, Int(rect.minX.rounded(.down)))
            let y0 = max(0, Int(rect.minY.rounded(.down)))
            let x1 = min(width, Int(rect.maxX.rounded(.up)))
            let y1 = min(height, Int(rect.maxY.rounded(.up)))

            for y in y0..<y1 {
                let row = y * bytesPerRow
                for x in x0..<x1 {
                    maskBytes[row + x] = 255
                }
            }
        }

        let maskData = Data(maskBytes)
        let maskCIImage = CIImage(
            bitmapData: maskData,
            bytesPerRow: bytesPerRow,
            size: CGSize(width: width, height: height),
            format: format,
            colorSpace: maskColorSpace
        )

        // Our mask is top-left origin (rows 0..height map to TOP rows of the image).
        // CIImage coordinate space is bottom-left, so the mask reads inverted vs. what we want.
        // Flip it vertically before blending.
        let flippedMask = maskCIImage.transformed(by:
            CGAffineTransform(translationX: 0, y: maskExtent.height)
                .scaledBy(x: 1, y: -1)
        )

        let blend = CIFilter.blendWithMask()
        blend.inputImage = blurredFull              // foreground (blurred)
        blend.backgroundImage = baseImage           // background (sharp)
        blend.maskImage = flippedMask
        guard let composited = blend.outputImage?.cropped(to: baseImage.extent) else {
            throw Failure.renderFailed
        }

        guard let result = ci.createCGImage(composited, from: composited.extent) else {
            throw Failure.renderFailed
        }
        return result
    }
}
