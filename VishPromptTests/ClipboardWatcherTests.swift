import AppKit
import XCTest
@testable import VishPrompt

@MainActor
final class ClipboardWatcherTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("vishprompt.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private let png = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!.representation(using: .png, properties: [:])!

    func testWhatWasThereAtLaunchIsNotFresh() {
        pasteboard.setData(png, forType: .png)
        let watcher = ClipboardWatcher(pasteboard: pasteboard)
        XCTAssertNil(watcher.imageAge())
    }

    func testANewScreenshotHasAnAge() {
        let watcher = ClipboardWatcher(pasteboard: pasteboard)
        let copied = Date()
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        watcher.poll(now: copied)
        let age = watcher.imageAge(now: copied.addingTimeInterval(30))
        XCTAssertEqual(age ?? -1, 30, accuracy: 0.001)
    }

    func testTextIsNotAScreenshot() {
        let watcher = ClipboardWatcher(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        XCTAssertNil(watcher.imageAge())
    }

    func testOurOwnWritesDoNotLookFresh() {
        let watcher = ClipboardWatcher(pasteboard: pasteboard)
        watcher.start()
        defer { watcher.stop() }
        // A paste's restore puts an old screenshot back; that is not a new copy.
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        NotificationCenter.default.post(name: .vishpromptWroteClipboard, object: nil)
        XCTAssertNil(watcher.imageAge())
    }
}
