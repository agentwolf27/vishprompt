import Synchronization
import XCTest
@testable import VishPrompt

/// Speed S1a: one connection for every API request, and no Keychain trip per request.
final class ClaudeGeneratorSessionTests: XCTestCase {
    func testEveryGeneratorSharesOneSession() {
        XCTAssertTrue(ClaudeGenerator().session === ClaudeGenerator().session)
        XCTAssertTrue(ClaudeGenerator().session === ClaudeGenerator.sharedSession)
    }

    func testTheKeyIsReadOnceThenFromMemory() {
        let reads = Mutex(0)
        let cache = APIKeyCache { reads.withLock { $0 += 1 }; return "sk-ant-test" }
        XCTAssertEqual(cache.value(), "sk-ant-test")
        XCTAssertEqual(cache.value(), "sk-ant-test")
        XCTAssertTrue(cache.hasKey)
        XCTAssertEqual(reads.withLock { $0 }, 1, "one Keychain read, not one per request")
    }

    func testSavingOrRemovingAKeyIsSeenImmediately() {
        let stored = Mutex<String?>(nil)
        let cache = APIKeyCache { stored.withLock { $0 } }
        XCTAssertNil(cache.value())
        stored.withLock { $0 = "sk-ant-new" }
        XCTAssertNil(cache.value(), "still cached")
        cache.invalidate()
        XCTAssertEqual(cache.value(), "sk-ant-new")
    }

    func testAnEmptyKeyIsNoKey() {
        XCTAssertFalse(APIKeyCache { "" }.hasKey)
    }

    func testPrewarmOnlyWhenTheAPIMayBeUsedAndAKeyExists() {
        let base = ContinuousClock.now.advanced(by: .seconds(10_000))
        XCTAssertFalse(ClaudeGenerator.shouldPrewarm(policy: .default, hasKey: true, now: base), "the default sends nothing to the API")
        XCTAssertFalse(ClaudeGenerator.shouldPrewarm(policy: .allAPI, hasKey: false, now: base))
        XCTAssertTrue(ClaudeGenerator.shouldPrewarm(policy: .allAPI, hasKey: true, now: base))
        XCTAssertFalse(ClaudeGenerator.shouldPrewarm(policy: .allAPI, hasKey: true, now: base.advanced(by: .seconds(10))),
                       "a burst of dictations opens the connection once")
        XCTAssertTrue(ClaudeGenerator.shouldPrewarm(policy: .allAPI, hasKey: true, now: base.advanced(by: .seconds(31))))
    }

    func testThePrewarmRequestCostsNothingAndSendsNothingButTheKey() {
        let request = ClaudeGenerator.prewarmRequest(key: "sk-ant-test")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.host, "api.anthropic.com", "the same host every rewrite goes to")
        XCTAssertEqual(request.url?.path, "/v1/models")
        XCTAssertNil(request.httpBody, "no dictation content")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
    }
}
