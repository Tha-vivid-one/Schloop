import Foundation
import Vision
import CoreGraphics

/// Wrapper around `VNRecognizeTextRequest`. On-device ML, no network, no model bundle.
/// Returns per-observation top text candidates plus a closure that can resolve precise
/// pixel-space bounding boxes for any sub-range of that text.
enum TextRecognizer {

    struct Observation {
        let text: String
        /// Resolves a `Range<String.Index>` within `text` to a pixel-space CGRect on the source image.
        /// Origin is top-left, units are pixels.
        let pixelRect: (Range<String.Index>) -> CGRect?
    }

    enum Failure: Error { case requestFailed(Error) }

    /// Synchronous OCR pass. Safe to call from background queues — the FSEvents callback and the
    /// clipboard timer are both off the main thread.
    static func recognize(cgImage: CGImage, accurate: Bool = true) throws -> [Observation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = false   // sensitive strings are NOT english words; correction can mangle them
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure.requestFailed(error)
        }

        guard let results = request.results else { return [] }

        let imgWidth = CGFloat(cgImage.width)
        let imgHeight = CGFloat(cgImage.height)

        return results.compactMap { observation -> Observation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            return Observation(text: text) { range in
                // Vision returns VNRectangleObservation? AND throws. Flatten the double optional.
                guard let box = (try? candidate.boundingBox(for: range)) ?? nil else { return nil }
                let visionRect = box.boundingBox  // normalized, origin bottom-left
                let x = visionRect.origin.x * imgWidth
                let y = (1.0 - visionRect.origin.y - visionRect.height) * imgHeight
                let w = visionRect.width * imgWidth
                let h = visionRect.height * imgHeight
                return CGRect(x: x, y: y, width: w, height: h)
            }
        }
    }
}
