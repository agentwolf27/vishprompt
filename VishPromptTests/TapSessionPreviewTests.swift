import XCTest
@testable import VishPrompt

/// Unwanted sessions 2: a tap-started session always ends in the preview card; nothing it heard
/// is typed into an app without Return.
final class TapSessionPreviewTests: XCTestCase {
    func testATapStartedSessionAlwaysPreviewsAndAKeyStartedOneFollowsTheDestination() {
        XCTAssertTrue(DictationController.needsPreview(destinationRequires: false, startedByTap: true), "Safari, from a tap: the card")
        XCTAssertTrue(DictationController.needsPreview(destinationRequires: true, startedByTap: true))
        XCTAssertTrue(DictationController.needsPreview(destinationRequires: true, startedByTap: false), "Claude Code, from fn: the card, as before")
        XCTAssertFalse(DictationController.needsPreview(destinationRequires: false, startedByTap: false), "Safari, from fn: inserted straight away, as before")
    }

    func testEveryPalmStartCountsAsATapStartAndNoKeyStartDoes() {
        for source in StartSource.allCases {
            XCTAssertEqual(DictationController.needsPreview(destinationRequires: false, startedByTap: source.isPalm), source.isPalm, source.rawValue)
        }
    }

    func testTheDestinationsThatInsertStraightAwayAreTheOnesATapMustNotReachUnseen() {
        // These are the destinations Vish's unwanted sessions landed in without a card.
        XCTAssertFalse(Destination.document.requiresPreview)
        XCTAssertFalse(Destination.chat.requiresPreview)
        XCTAssertFalse(Destination.message.requiresPreview)
        XCTAssertTrue(Destination.claudeCode.requiresPreview)
    }

    func testAnUnansweredCardSaysItWasNotInsertedAndTheTextWasKept() {
        for isPaste in [false, true] {
            let message = HUDCopy.previewExpired(isPaste: isPaste)
            XCTAssertFalse(message.lowercased().contains("inserted into"), message)
            XCTAssertTrue(message.lowercased().contains("copied") || message.lowercased().contains("clipboard") || message.lowercased().contains("history") || isPaste, message)
        }
    }
}
