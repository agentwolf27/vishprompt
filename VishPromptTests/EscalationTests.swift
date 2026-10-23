import XCTest
@testable import VishPrompt

/// Speed S1d: a quick message with a self-correction should not wait 6 to 10 seconds.
final class EscalationTests: XCTestCase {
    private let policy = ProviderPolicy(fastPath: .local, compilePath: .subscription)

    func testWithAKeyAnEscalationGoesToTheAPI() {
        let choice = RoutingGenerator.choice(policy: policy, level: .light, transcript: "the call is at nine no wait ten", apiKeyAvailable: true)
        XCTAssertEqual(choice, .init(provider: .apiKey, escalated: true))
    }

    func testWithoutAKeyItGoesToTheCompilePathAndSaysSo() {
        let choice = RoutingGenerator.choice(policy: policy, level: .light, transcript: "the call is at nine no wait ten", apiKeyAvailable: false)
        XCTAssertEqual(choice, .init(provider: .subscription, escalated: true))
        XCTAssertTrue(HUDCopy.providerLabel(choice).contains("because you corrected yourself"))
    }

    func testAFillerIMeanStaysOnThisMac() {
        for transcript in ["I mean, it's fine, ship it", "i mean the build looks good", "Sounds good. I mean, let's do Friday"] {
            XCTAssertFalse(LocalCleanup.needsModel(transcript), "filler escalated: \(transcript)")
            XCTAssertEqual(RoutingGenerator.choice(policy: policy, level: .light, transcript: transcript, apiKeyAvailable: false).provider, .local)
        }
    }

    func testACorrectingIMeanStillEscalates() {
        XCTAssertTrue(LocalCleanup.needsModel("use the session refresh, I mean the token refresh"))
        XCTAssertTrue(LocalCleanup.needsModel("send it to Priya I mean Sam"))
    }

    func testWordsContainingTheLettersAreNotIMean() {
        XCTAssertFalse(LocalCleanup.needsModel("the semi meaning of it"))
    }

    func testCompiledPromptsAreUnaffected() {
        XCTAssertEqual(RoutingGenerator.choice(policy: policy, level: .full, transcript: "no wait", apiKeyAvailable: true),
                       .init(provider: .subscription, escalated: false), "a compile already uses the chosen provider")
    }

    func testOfflineNeverEscalates() {
        XCTAssertEqual(RoutingGenerator.choice(policy: .offline, level: .light, transcript: "no wait", apiKeyAvailable: true).provider, .local)
    }
}
