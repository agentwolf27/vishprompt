import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Visprflow

/// The inserter against a private pasteboard and a recording key poster, so no real keys are
/// sent and the user's clipboard is never touched.
@MainActor
final class InserterTests: XCTestCase {
    @MainActor
    final class RecordingPoster: KeyEventPosting {
        var chords: [(key: CGKeyCode, flags: CGEventFlags)] = []
        func postChord(key: CGKeyCode, flags: CGEventFlags) async throws {
            chords.append((key, flags))
        }
    }

    private var pasteboard: NSPasteboard!
    private var poster: RecordingPoster!
    private let fastRestore = PasteRestorePolicy(receiptTimeout: 0.05, quietPeriod: 0.01, maximumWait: 0.3)

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("visprflow.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        poster = RecordingPoster()
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private func inserter(secure: Bool = false, trusted: Bool = true) -> Inserter {
        Inserter(policy: fastRestore, pasteboard: pasteboard, poster: poster, isTrusted: { trusted }, isSecureInput: { secure })
    }

    private static let returnKeys: Set<CGKeyCode> = [CGKeyCode(kVK_Return), CGKeyCode(kVK_ANSI_KeypadEnter)]

    func testPastePostsOnlyCommandVAndNeverReturn() async throws {
        pasteboard.setString("the user's own copy", forType: .string)
        // Multi-line text is where a careless inserter would reach for Return.
        try await inserter().insert("line one\nline two\n", strategy: .paste)

        XCTAssertEqual(poster.chords.count, 1)
        let chord = try XCTUnwrap(poster.chords.first)
        XCTAssertEqual(chord.key, KeycodeResolver.keyCode(for: "v") ?? KeycodeResolver.qwertyV)
        XCTAssertEqual(chord.flags, .maskCommand)
        XCTAssertFalse(poster.chords.contains { Self.returnKeys.contains($0.key) }, "Return must never be posted")
        XCTAssertEqual(pasteboard.string(forType: .string), "the user's own copy", "the clipboard is put back")
    }

    func testShiftInsertAlsoNeverPostsReturn() async throws {
        try await inserter().insert("text\n", strategy: .pasteShiftInsert)
        XCTAssertEqual(poster.chords.map(\.key), [CGKeyCode(kVK_Help)])
        XCTAssertFalse(poster.chords.contains { Self.returnKeys.contains($0.key) })
    }

    func testSecureInputLeavesAMarkedEntryAndPostsNothing() async {
        do {
            try await inserter(secure: true).insert("a secret the user copied", strategy: .paste)
            XCTFail("expected secureInputActive")
        } catch {
            XCTAssertEqual((error as? InsertionError).map { "\($0)" }, "secureInputActive")
        }
        XCTAssertTrue(poster.chords.isEmpty)
        XCTAssertEqual(pasteboard.string(forType: .string), "a secret the user copied")
        let types = Set(pasteboard.types ?? [])
        XCTAssertTrue(types.contains(ClipboardReader.concealedType), "clipboard managers must skip it")
        XCTAssertTrue(types.contains(ClipboardReader.transientType))
        // And Smart Paste itself refuses to read it back.
        XCTAssertEqual(ClipboardReader.read(from: pasteboard), .refused(.concealed))
    }

    func testUntrustedPostsNothing() async {
        do {
            try await inserter(trusted: false).insert("hello", strategy: .paste)
            XCTFail("expected notTrusted")
        } catch {}
        XCTAssertTrue(poster.chords.isEmpty)
    }
}
