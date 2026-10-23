import AppKit
import XCTest
@testable import VishPrompt

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
        let board = NSPasteboard(name: NSPasteboard.Name("vishprompt.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        TextRescue.copy("the prompt I nearly lost", to: board)
        XCTAssertEqual(board.string(forType: .string), "the prompt I nearly lost")
    }

    func testRescueNeverEmptiesTheClipboardForNothing() {
        let board = NSPasteboard(name: NSPasteboard.Name("vishprompt.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("keep", forType: .string)
        TextRescue.copy("  \n", to: board)
        XCTAssertEqual(board.string(forType: .string), "keep")
    }

    func testRoutingNamesTheEscalation() {
        let policy = ProviderPolicy(fastPath: .local, compilePath: .subscription)
        XCTAssertEqual(RoutingGenerator.choice(policy: policy, level: .light, transcript: "send the link", apiKeyAvailable: false), .init(provider: .local, escalated: false))
        XCTAssertEqual(RoutingGenerator.choice(policy: policy, level: .light, transcript: "at nine no wait eleven", apiKeyAvailable: false), .init(provider: .subscription, escalated: true))
        XCTAssertEqual(RoutingGenerator.choice(policy: policy, level: .full, transcript: "anything", apiKeyAvailable: false), .init(provider: .subscription, escalated: false))
        XCTAssertEqual(RoutingGenerator.choice(policy: .offline, level: .light, transcript: "no wait", apiKeyAvailable: true), .init(provider: .local, escalated: false))
    }

    // MARK: Q1, raw errors become a cause and a next step

    func testProviderErrorsNameACauseNotARawBody() {
        let body = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        for status in [401, 403, 429, 500, 502, 503, 529, 418] {
            let text = GenerationError.http(status: status, message: body).localizedDescription
            XCTAssertFalse(text.contains("overloaded_error"), "raw body reached the overlay: \(text)")
            XCTAssertTrue(text.contains("\(status)"), "the status is kept for searching: \(text)")
        }
        XCTAssertTrue(GenerationError.http(status: 401, message: body).localizedDescription.contains("Setup"))
        XCTAssertTrue(GenerationError.missingAPIKey.localizedDescription.contains("Setup"))
    }

    func testInsertionErrorsSayWhatToDo() {
        XCTAssertTrue(InsertionError.notTrusted.localizedDescription.contains("Setup"))
        XCTAssertTrue(InsertionError.secureInputActive.localizedDescription.contains("⌘V"))
        XCTAssertTrue(HUDCopy.insertFailed(InsertionError.eventCreationFailed.localizedDescription, isPaste: false).contains("⌘V"))
        XCTAssertTrue(HUDCopy.insertFailed("x", isPaste: true).contains("clip is still on the clipboard"))
    }

    func testEveryMessageEndsAsASentence() {
        XCTAssertEqual(HUDCopy.sentence("No Anthropic API key is set"), "No Anthropic API key is set.")
        XCTAssertEqual(HUDCopy.sentence("Done!"), "Done!")
        XCTAssertTrue(HUDCopy.failedWithWordsCopied(GenerationError.emptyResponse.localizedDescription)
            .hasPrefix("The rewrite came back empty. Your words are copied"))
    }

    func testLongRecordingsAreKeptWhenCancelled() {
        XCTAssertFalse(HUDCopy.keepsCancelled(seconds: 29.9))
        XCTAssertTrue(HUDCopy.keepsCancelled(seconds: 30))
        XCTAssertTrue(HUDCopy.cancelledKept.contains("History"))
        XCTAssertTrue(HUDCopy.cancelledKept.contains("⌘V"))
    }
}
