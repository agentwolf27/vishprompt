import AppKit
import XCTest
@testable import Visprflow

/// Every ending that does not insert says what happened and what to do, and leaves the text
/// where the user can get it.
@MainActor
final class HUDCopyTests: XCTestCase {
    func testFocusMovedSaysWhereTheTextIs() {
        XCTAssertTrue(HUDCopy.focusMoved(to: "Slack", isPaste: false).contains("⌘V"))
        XCTAssertTrue(HUDCopy.focusMoved(to: "Slack", isPaste: false).contains("Slack"))
        XCTAssertTrue(HUDCopy.focusMoved(to: "Slack", isPaste: true).contains("clip is still on the clipboard"))
    }

    func testPreviewExpiredSaysWhereTheTextIs() {
        XCTAssertTrue(HUDCopy.previewExpired(isPaste: false).contains("⌘V"))
        XCTAssertTrue(HUDCopy.previewExpired(isPaste: true).contains("still on the clipboard"))
    }

    func testFailuresNameTheCauseAndTheWayOut() {
        let message = HUDCopy.failedWithWordsCopied("Anthropic returned 529: overloaded.")
        XCTAssertTrue(message.hasPrefix("Anthropic returned 529: overloaded"))
        XCTAssertTrue(message.contains("⌘V"))
        XCTAssertFalse(message.contains(".."))
    }

    func testEmptyClipboardOffersTheNextStep() {
        XCTAssertTrue(HUDCopy.emptyClipboard.contains("Copy something"))
    }

    func testSourceLineIsHonestAboutWhereWordsWent() {
        XCTAssertEqual(HUDCopy.source(for: .local), "Stayed on this Mac.")
        XCTAssertEqual(HUDCopy.source(for: nil), "Stayed on this Mac.")
        XCTAssertEqual(HUDCopy.source(for: .subscription), "Sent your words to your Claude subscription.")
        XCTAssertTrue(HUDCopy.source(for: .apiKey, escalated: true).contains("corrected yourself"))
        XCTAssertEqual(HUDCopy.pasteSource(for: .apiKey, rewritten: false), "Stayed on this Mac.")
        XCTAssertTrue(HUDCopy.pasteSource(for: .apiKey, rewritten: true).contains("secret shapes removed"))
    }

    func testRescueCopiesTheText() {
        let board = NSPasteboard(name: NSPasteboard.Name("visprflow.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        TextRescue.copy("the prompt I nearly lost", to: board)
        XCTAssertEqual(board.string(forType: .string), "the prompt I nearly lost")
    }

    func testRescueNeverEmptiesTheClipboardForNothing() {
        let board = NSPasteboard(name: NSPasteboard.Name("visprflow.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("keep", forType: .string)
        TextRescue.copy("  \n", to: board)
        XCTAssertEqual(board.string(forType: .string), "keep")
    }

    func testRoutingNamesTheEscalation() {
        let policy = ProviderPolicy(fastPath: .local, compilePath: .subscription)
        XCTAssertEqual(RoutingGenerator.choice(policy: policy, level: .light, transcript: "send the link"), .init(provider: .local, escalated: false))
        XCTAssertEqual(RoutingGenerator.choice(policy: policy, level: .light, transcript: "at nine no wait eleven"), .init(provider: .subscription, escalated: true))
        XCTAssertEqual(RoutingGenerator.choice(policy: policy, level: .full, transcript: "anything"), .init(provider: .subscription, escalated: false))
        XCTAssertEqual(RoutingGenerator.choice(policy: .offline, level: .light, transcript: "no wait"), .init(provider: .local, escalated: false))
    }
}
