import AppKit
import XCTest
@testable import Visprflow

/// Reading the selection without losing the user's clipboard. A private pasteboard stands in
/// for the real one, and a poster that "is the app" answers the ⌘C.
@MainActor
final class SelectionReaderTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("visprflow.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("the user's own clipboard", forType: .string)
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    /// Posts nothing real; when asked for ⌘C, writes `copies` to the pasteboard like an app would.
    @MainActor
    final class FakeApp: KeyEventPosting {
        let pasteboard: NSPasteboard
        let copies: String?
        var concealed = false
        var chords: [(CGKeyCode, CGEventFlags)] = []
        init(pasteboard: NSPasteboard, copies: String?) { self.pasteboard = pasteboard; self.copies = copies }
        func postChord(key: CGKeyCode, flags: CGEventFlags) async throws {
            chords.append((key, flags))
            guard let copies else { return }
            pasteboard.clearContents()
            if concealed {
                pasteboard.declareTypes([.string, ClipboardReader.concealedType], owner: nil)
                pasteboard.setString("", forType: ClipboardReader.concealedType)
            }
            pasteboard.setString(copies, forType: .string)
        }
    }

    private func reader(app: FakeApp, accessibility: String? = nil, secure: Bool = false) -> SelectionReader {
        SelectionReader(pasteboard: pasteboard, poster: app, isSecureInput: { secure },
                        accessibilitySelection: { accessibility }, copyTimeout: .milliseconds(100))
    }

    func testAccessibilityIsReadWithoutTouchingTheClipboard() async {
        let app = FakeApp(pasteboard: pasteboard, copies: "should not be used")
        let result = await reader(app: app, accessibility: "selected via AX").read()
        XCTAssertEqual(result, .text("selected via AX"))
        XCTAssertTrue(app.chords.isEmpty, "no ⌘C when Accessibility answers")
        XCTAssertEqual(pasteboard.string(forType: .string), "the user's own clipboard")
    }

    func testTheCopyFallbackPutsTheClipboardBack() async {
        let app = FakeApp(pasteboard: pasteboard, copies: "selected via copy")
        let result = await reader(app: app).read()
        XCTAssertEqual(result, .text("selected via copy"))
        XCTAssertEqual(app.chords.count, 1)
        XCTAssertEqual(app.chords.first?.1, .maskCommand)
        XCTAssertEqual(pasteboard.string(forType: .string), "the user's own clipboard", "the clipboard is restored")
    }

    func testNothingSelectedIsNone() async {
        let app = FakeApp(pasteboard: pasteboard, copies: nil)
        let result = await reader(app: app).read()
        XCTAssertEqual(result, .none)
        XCTAssertNotNil(result.message)
        XCTAssertEqual(pasteboard.string(forType: .string), "the user's own clipboard")
    }

    func testSecureInputIsNeverRead() async {
        let app = FakeApp(pasteboard: pasteboard, copies: "password")
        let result = await reader(app: app, accessibility: "password", secure: true).read()
        XCTAssertEqual(result, .secure)
        XCTAssertTrue(app.chords.isEmpty)
    }

    func testAConcealedCopyIsRefused() async {
        let app = FakeApp(pasteboard: pasteboard, copies: "hunter2")
        app.concealed = true
        let result = await reader(app: app).read()
        XCTAssertEqual(result, .concealed)
        XCTAssertEqual(pasteboard.string(forType: .string), "the user's own clipboard")
    }

    func testWhitespaceFromAccessibilityFallsBackToCopy() async {
        let app = FakeApp(pasteboard: pasteboard, copies: "real selection")
        let result = await reader(app: app, accessibility: "   ").read()
        XCTAssertEqual(result, .text("real selection"))
    }
}
