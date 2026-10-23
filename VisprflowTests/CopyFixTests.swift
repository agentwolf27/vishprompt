import XCTest
@testable import Visprflow

/// UI/UX Q5: no jargon, no raw errors, counts that match what is shown.
final class CopyFixTests: XCTestCase {
    func testThePermissionCountMatchesTheList() {
        let required = Permission.allCases.filter(\.isRequired).count
        let headline = UICopy.permissionsHeadline(trigger: "fn (Globe)", requiredCount: required)
        XCTAssertTrue(headline.contains("\(UICopy.numberWord(required)) permission"), headline)
        XCTAssertEqual(required, 2)
        XCTAssertTrue(headline.contains("Two permissions make that work"))
        XCTAssertEqual(UICopy.permissionsHeadline(trigger: "fn", requiredCount: 1), "Hold fn, talk, release. One permission makes that work in every app.")
    }

    func testKeychainFailuresGiveAStepNotAnErrorCode() {
        for action in [UICopy.KeychainAction.read, .save, .remove] {
            let text = UICopy.keychainFailure(action)
            XCTAssertTrue(text.contains("Keychain Access"), text)
            XCTAssertFalse(text.contains("OSStatus"))
            XCTAssertFalse(text.contains("Error Domain"))
        }
    }

    func testAModelDownloadFailureOffersRetry() {
        XCTAssertTrue(UICopy.modelDownloadFailed("The network connection was lost.").hasSuffix("Retry."))
    }

    func testInsertionLabelsCarryNoJargon() {
        for strategy in InsertionStrategy.allCases {
            let label = UICopy.insertionLabel(strategy)
            XCTAssertFalse(label.contains("Electron"), label)
            XCTAssertFalse(label.contains("⇧Insert"), label)
        }
        XCTAssertEqual(Set(InsertionStrategy.allCases.map(UICopy.insertionLabel)).count, InsertionStrategy.allCases.count)
    }

    func testTheDestinationListShowsTheEffectiveLevel() {
        XCTAssertEqual(UICopy.destinationSubtitle(.message, override: nil), "Light")
        var override = DestinationOverride()
        override.defaultLevel = .full
        XCTAssertEqual(UICopy.destinationSubtitle(.message, override: override), "Compiled · custom level")
        override.instructions = "keep it lowercase"
        XCTAssertEqual(UICopy.destinationSubtitle(.message, override: override), "Compiled · custom level, instructions")
        // Setting a value to what it already was is not a customisation.
        var same = DestinationOverride()
        same.defaultLevel = Destination.message.defaultLevel
        XCTAssertEqual(UICopy.destinationSubtitle(.message, override: same), "Light")
    }

    func testProviderSpeedsUseOneFormat() {
        XCTAssertEqual(ProviderChoice.subscription.latencyNote, "first words ≈3 s · done in 6–10 s")
        XCTAssertEqual(ProviderChoice.apiKey.latencyNote, "first words ≈1 s · done in 1–2 s")
        for choice in ProviderChoice.allCases {
            XCTAssertFalse(choice.summary.contains("seconds"), "speeds live in the speed line: \(choice.summary)")
        }
    }

    func testTheOverlaySaysWhereNotHowMany() {
        XCTAssertEqual(UICopy.inserted(into: "Slack", pasted: false), "Inserted into Slack")
        XCTAssertEqual(UICopy.inserted(into: "Slack", pasted: true), "Pasted into Slack")
    }
}
