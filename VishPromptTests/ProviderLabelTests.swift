import XCTest
@testable import VishPrompt

/// The header names where a rewrite runs, using the routing rule that sends it there.
final class ProviderLabelTests: XCTestCase {
    func testEachProviderIsNamed() {
        XCTAssertEqual(HUDCopy.providerLabel(.init(provider: .local, escalated: false)), "on this Mac")
        XCTAssertEqual(HUDCopy.providerLabel(.init(provider: .subscription, escalated: false)), "via your Claude subscription")
        XCTAssertEqual(HUDCopy.providerLabel(.init(provider: .apiKey, escalated: false)), "via the Anthropic API")
    }

    func testAnEscalationSaysWhy() {
        let policy = ProviderPolicy(fastPath: .local, compilePath: .subscription)
        let choice = RoutingGenerator.choice(policy: policy, level: .light, transcript: "meet at nine no wait ten", apiKeyAvailable: false)
        XCTAssertEqual(HUDCopy.providerLabel(choice), "via your Claude subscription, because you corrected yourself")
    }

    func testTheLabelMatchesWhereTheRequestActuallyGoes() async throws {
        // The label and the router read the same rule, so they cannot disagree.
        let local = RecordingGenerator { _ in "local" }
        let subscription = RecordingGenerator { _ in "subscription" }
        let api = RecordingGenerator { _ in "api" }
        let policy = ProviderPolicy(fastPath: .local, compilePath: .subscription)
        for transcript in ["send the figma link", "at nine no wait ten"] {
            var router = RoutingGenerator(policy: policy, level: .light, local: local, subscription: subscription, api: api)
            router.apiKeyAvailable = { false }
            let request = GenerationRequest(system: "", user: "<transcript>\(transcript)</transcript>", model: .haiku, maxTokens: 10)
            let went = try await router.generate(request) { _ in }
            let said = RoutingGenerator.choice(policy: policy, level: .light, transcript: transcript, apiKeyAvailable: false).provider
            XCTAssertEqual(went, said == .local ? "local" : "subscription", transcript)
        }
    }

    func testTheCompilingStateCarriesItAndVoiceOverSaysIt() {
        let state = HUDState.compiling(partial: "", provider: "via the Anthropic API")
        XCTAssertEqual(HUDAnnouncement.text(for: state, previous: .transcribing), "Rewriting via the Anthropic API.")
        XCTAssertEqual(HUDAnnouncement.text(for: .listening(level: 0, seconds: 0, locked: false, app: "Slack"), previous: .hidden), "Listening, into Slack.")
    }
}
