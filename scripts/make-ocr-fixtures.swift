// Renders the OCR fixtures in Fixtures/ocr. Run once, by hand, and commit the output:
//
//     swift scripts/make-ocr-fixtures.swift Fixtures/ocr
//
// `make verify-ocr` reads only the committed PNGs and never regenerates them, so a change to
// this script cannot quietly make the fixtures easier. The images are rendered rather than
// captured (capturing needs Screen Recording permission), but at the size and style a real
// Terminal screenshot has: 11 pt Menlo, light text on a dark background, at 2x.
import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Fixtures/ocr")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// Split so that secret scanners do not flag this script; the joined value is fake.
let fakeKey = ["sk-ant-", "api03-", "Z0oO0oFAKE0o0OfakeO0o0"].joined()

let terminalError = """
$ npm test
FAIL src/auth/refreshToken.test.ts
  ● refreshToken › retries after a 401
    TypeError: Cannot read properties of undefined (reading 'expiresAt')
      at refreshToken (src/auth/refreshToken.ts:42:18)
      at processTicksAndRejections (node:internal/process/task_queues:95:5)
ANTHROPIC_API_KEY=\(fakeKey)
Tests: 1 failed, 23 passed, 24 total
"""

func render(_ text: String, width: Int, background: NSColor, foreground: NSColor, size: CGFloat) -> NSBitmapImageRep {
    let scale: CGFloat = 2
    let font = NSFont(name: "Menlo", size: size * scale) ?? .monospacedSystemFont(ofSize: size * scale, weight: .regular)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
    let string = NSAttributedString(string: text, attributes: attributes)
    let lines = max(1, text.components(separatedBy: "\n").count)
    let height = Int(CGFloat(lines) * size * scale * 1.35 + 40 * scale)
    let pixelsWide = Int(CGFloat(width) * scale)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    background.setFill()
    NSRect(x: 0, y: 0, width: pixelsWide, height: height).fill()
    string.draw(in: NSRect(x: 20 * scale, y: 0, width: CGFloat(pixelsWide) - 40 * scale, height: CGFloat(height) - 20 * scale))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dark = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let light = NSColor(calibratedWhite: 0.88, alpha: 1)

let terminal = render(terminalError, width: 760, background: dark, foreground: light, size: 11)
try terminal.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("terminal-error.png"))

// The same screenshot after a round trip through JPEG at the quality chat apps use.
let jpeg = terminal.representation(using: .jpeg, properties: [.compressionFactor: 0.55])!
let degraded = NSBitmapImageRep(data: jpeg)!
try degraded.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("terminal-error-jpeg.png"))

let blank = render("", width: 400, background: dark, foreground: light, size: 11)
try blank.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("blank.png"))

print("Wrote fixtures to \(output.path)")
