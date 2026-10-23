import Foundation
import Synchronization
import XCTest
@testable import VishPrompt

/// Speed S2a: the claude command started at key-down, hooks off. A fake `claude` script stands
/// in for the real one, so this spends no quota and needs no sign-in.
final class ClaudeCLIPrespawnTests: XCTestCase {
    private var scratch: URL!
    private var fake: String!

    override func setUpWithError() throws {
        scratch = URL(filePath: NSTemporaryDirectory()).appending(path: "vishprompt-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        // Answers on stdin when started with --input-format, from its arguments otherwise, so a
        // test can tell which path was used. FAKE_CLAUDE_DIE makes it exit at once.
        let script = """
        #!/bin/bash
        [ -n "$FAKE_CLAUDE_DIE" ] && exit 3
        source="args"
        for a in "$@"; do [ "$a" = "--input-format" ] && source="stdin"; done
        if [ "$source" = "stdin" ]; then read -r line; fi
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"from '"$source"'"}}}'
        echo '{"type":"result","subtype":"success","is_error":false}'
        """
        let url = scratch.appending(path: "claude")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        fake = url.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func request(_ system: String = SystemPrompt.core, model: ModelChoice = .sonnet) -> GenerationRequest {
        GenerationRequest(system: system, user: "<transcript>fix it</transcript>", model: model, maxTokens: 100)
    }

    func testHooksAreOffOnBothPaths() {
        let cold = ClaudeCLIGenerator.arguments(prompt: "p", system: "s", model: "m")
        let warm = ClaudeCLIGenerator.streamingArguments(system: "s", model: "m")
        for args in [cold, warm] {
            let index = try! XCTUnwrap(args.firstIndex(of: "--settings"))
            XCTAssertEqual(args[index + 1], #"{"disableAllHooks": true}"#)
        }
        XCTAssertEqual(cold[1], "p", "the prompt stays right after -p")
        XCTAssertTrue(warm.contains("--input-format"))
        XCTAssertFalse(warm.contains("p"), "a pre-started process has no prompt yet")
    }

    func testTheStreamMessageCarriesThePrompt() throws {
        let line = ClaudeCLIGenerator.streamMessage("hello \"world\"")
        XCTAssertTrue(line.hasSuffix("\n"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "user")
        XCTAssertEqual((object["message"] as? [String: Any])?["content"] as? String, "hello \"world\"")
    }

    func testAPrestartedProcessAnswersTheMatchingRequest() async throws {
        let prespawner = CLIPrespawner()
        prespawner.prepare(.init(executable: fake, system: SystemPrompt.core, model: ModelChoice.sonnet.identifier))
        XCTAssertTrue(prespawner.hasWaitingProcess)
        let generator = ClaudeCLIGenerator(executable: fake, workingDirectory: scratch, prespawner: prespawner)
        let text = try await generator.generate(request()) { _ in }
        XCTAssertEqual(text, "from stdin")
        XCTAssertFalse(prespawner.hasWaitingProcess, "used once, then gone")
    }

    func testAMismatchIsEndedAndServedCold() async throws {
        let prespawner = CLIPrespawner()
        prespawner.prepare(.init(executable: fake, system: SystemPrompt.core, model: ModelChoice.haiku.identifier))
        let generator = ClaudeCLIGenerator(executable: fake, workingDirectory: scratch, prespawner: prespawner)
        let text = try await generator.generate(request(model: .sonnet)) { _ in }
        XCTAssertEqual(text, "from args", "a process started for another model must never answer")
        XCTAssertFalse(prespawner.hasWaitingProcess)
    }

    func testPreparingTheSameKeyTwiceStartsOneProcess() {
        let launches = Mutex(0)
        let prespawner = CLIPrespawner { key in
            launches.withLock { $0 += 1 }
            return CLIPrespawner.launchCLI(key)
        }
        let key = CLIPrespawner.Key(executable: fake, system: "s", model: "m")
        prespawner.prepare(key)
        prespawner.prepare(key)
        XCTAssertEqual(launches.withLock { $0 }, 1)
        prespawner.discard()
        XCTAssertFalse(prespawner.hasWaitingProcess)
    }

    func testAProcessThatDiedEarlyFailsFastInsteadOfHanging() async throws {
        setenv("FAKE_CLAUDE_DIE", "1", 1)
        defer { unsetenv("FAKE_CLAUDE_DIE") }
        let prespawner = CLIPrespawner()
        prespawner.prepare(.init(executable: fake, system: SystemPrompt.core, model: ModelChoice.sonnet.identifier))
        try await Task.sleep(for: .milliseconds(300))
        let generator = ClaudeCLIGenerator(executable: fake, workingDirectory: scratch, prespawner: prespawner)
        let started = ContinuousClock.now
        do {
            _ = try await generator.generate(request()) { _ in }
            XCTFail("expected a failure")
        } catch {}
        XCTAssertLessThan(Trace.milliseconds(ContinuousClock.now - started), 10_000, "must not wait out the 60 s ceiling")
    }

    func testKeyDownOnlyGuessesWhereACompileIsLikely() {
        let subscription = ProviderPolicy(fastPath: .local, compilePath: .subscription)
        let terminal = CLIPrespawner.keyDownGuess(policy: subscription, frontmost: "com.apple.Terminal", executable: fake)
        XCTAssertEqual(terminal?.model, ModelChoice.sonnet.identifier)
        XCTAssertEqual(terminal?.system, SystemPrompt.core)
        XCTAssertNil(CLIPrespawner.keyDownGuess(policy: subscription, frontmost: "com.tinyspeck.slackmacgap", executable: fake),
                     "a Slack message is cleaned up on this Mac; no process for nothing")
        XCTAssertNil(CLIPrespawner.keyDownGuess(policy: .allAPI, frontmost: "com.apple.Terminal", executable: fake))
        XCTAssertNil(CLIPrespawner.keyDownGuess(policy: subscription, frontmost: "com.apple.Terminal", executable: nil))
        XCTAssertEqual(CLIPrespawner.chordGuess(policy: subscription, executable: fake)?.system, SystemPrompt.paste)
    }
}
