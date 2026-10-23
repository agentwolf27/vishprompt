import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Text read from an image, on this Mac.
struct ScreenshotText: Equatable, Sendable {
    /// The recognised lines, top to bottom, joined by newlines.
    var text: String
    var lineCount: Int

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum ScreenshotOCRError: Error, LocalizedError, Equatable {
    case unreadableImage

    var errorDescription: String? {
        "The clipboard holds an image Visprflow could not open. Copy the screenshot again."
    }
}

/// Reads the text in a screenshot with Apple's Vision framework, on this Mac.
///
/// The image never leaves the machine; only the text can, and only once the redactor has seen
/// it. Language correction is off on purpose: it "fixes" identifiers, paths and stack frames
/// into dictionary words, which is exactly the text a bug report needs left alone.
enum ScreenshotOCR {
    static func read(_ data: Data) async throws -> ScreenshotText {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ScreenshotOCRError.unreadableImage }
        return try await read(image)
    }

    static func read(_ image: CGImage) async throws -> ScreenshotText {
        // Vision blocks while it works, so it runs off the caller's executor.
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []
            // Vision's origin is bottom-left: higher maxY means higher on screen.
            let ordered = observations.sorted { lhs, rhs in
                let dy = lhs.boundingBox.midY - rhs.boundingBox.midY
                if abs(dy) > 0.01 { return dy > 0 }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            let lines = ordered.compactMap { $0.topCandidates(1).first?.string }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return ScreenshotText(text: lines.joined(separator: "\n"), lineCount: lines.count)
        }.value
    }
}
