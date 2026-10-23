import GRDB
import XCTest
@testable import VishPrompt

/// Editing the selection runs Smart Paste's pipeline, with an edit's own refusals.
final class SelectionEditTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let key = ["sk-ant-", "api03-", "FAKEfakeFAKEfake1234567890abcdEFGH"].joined()

    override func setUp() {
        suiteName = "vishprompt.tests.edit.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func paster(_ generator: RecordingGenerator, consented: Bool = true) -> SmartPaster {
        let consent = SmartPasteConsent(defaults: defaults)
        if consented {
            _ = consent.requestPermission(for: .apiKey)
            _ = consent.requestPermission(for: .apiKey)
        }
        return SmartPaster(provider: .apiKey, generator: generator, consent: consent)
    }

    private func edit(_ selection: String, _ instruction: String, in destination: Destination = .email) -> SmartPasteRequest {
        SmartPasteRequest(clip: selection, instruction: instruction, destination: destination, purpose: .edit)
    }

    func testSilenceIsRefusedWithANextStepAndSendsNothing() async {
        let generator = RecordingGenerator()
        do {
            _ = try await paster(generator).paste(edit("a long paragraph", ""))
            XCTFail("expected editNeedsInstruction")
        } catch {
            XCTAssertEqual(error as? SmartPasteError, .editNeedsInstruction)
            XCTAssertTrue(error.localizedDescription.contains("shorter"))
        }
        XCTAssertEqual(generator.requests.count, 0)
    }

    func testTerminalsAreRefused() async {
        let generator = RecordingGenerator()
        do {
            _ = try await paster(generator).paste(edit("ls -la", "add a flag", in: .shell))
            XCTFail("expected editNotInTerminal")
        } catch {
            XCTAssertEqual(error as? SmartPasteError, .editNotInTerminal)
        }
        XCTAssertEqual(generator.requests.count, 0)
    }

    func testAnOversizedSelectionIsRefused() async {
        let generator = RecordingGenerator()
        do {
            _ = try await paster(generator).paste(edit(String(repeating: "x", count: 20_001), "shorter"))
            XCTFail("expected selectionTooLong")
        } catch {
            XCTAssertEqual(error as? SmartPasteError, .selectionTooLong(20_001))
        }
        XCTAssertEqual(generator.requests.count, 0)
    }

    func testConsentAppliesToEditsToo() async {
        let generator = RecordingGenerator { _ in "Shorter." }
        do {
            _ = try await paster(generator, consented: false).paste(edit("A longer sentence.", "shorter"))
            XCTFail("expected needsConsent")
        } catch {
            XCTAssertEqual(error as? SmartPasteError, .needsConsent(.apiKey))
        }
        XCTAssertEqual(generator.requests.count, 0)
    }

    func testARewriteReplacesTheSelectionAndTheModelIsToldSo() async throws {
        let generator = RecordingGenerator { _ in "No, thank you, I can't make it on Friday." }
        let result = try await paster(generator).paste(edit("ugh no I can't do friday", "reply no politely"))
        XCTAssertEqual(result.outcome, .rewritten)
        XCTAssertEqual(result.insertText, "No, thank you, I can't make it on Friday.")
        XCTAssertEqual(result.asCopiedText, "ugh no I can't do friday", "Tab shows the original")
        let sent = try XCTUnwrap(generator.requests.first)
        XCTAssertTrue(sent.user.contains("Your output replaces it in place"))
        XCTAssertTrue(sent.user.contains("<instruction>reply no politely</instruction>"))
    }

    func testSecretsAreRedactedAndNumbersChecked() async throws {
        let echo = RecordingGenerator(reply: RecordingGenerator.clipEcho)
        _ = try await paster(echo).paste(edit("use key=\(key) for 3 servers", "tidy"))
        XCTAssertFalse(try XCTUnwrap(echo.requests.first).user.contains(key))

        let changed = RecordingGenerator { _ in "Use the key for 5 servers." }
        let result = try await paster(changed).paste(edit("use the key for 3 servers", "tidy"))
        guard case .fellBack = result.outcome else { return XCTFail("an added number must fall back") }
    }

    func testHistoryMarksItAsAnEditAndKeepsTheRedactedForm() async throws {
        let echo = RecordingGenerator(reply: RecordingGenerator.clipEcho)
        let result = try await paster(echo).paste(edit("the key is: \(key)", "tidy"))
        let record = result.record(id: "e1", instruction: "tidy", destination: .email, status: .inserted, purpose: .edit)
        XCTAssertEqual(record.level, "edit")
        XCTAssertEqual(record.provider, "apiKey")
        for text in try storedText(of: record) {
            XCTAssertFalse(text.contains(key), "history kept the key: \(text)")
        }
    }

    /// Every text column of the row as the database returns it.
    private func storedText(of record: DictationRecord) throws -> [String] {
        let queue = try Database.makeQueue(path: nil)
        try queue.write { db in try record.insert(db) }
        return try queue.read { db in
            let row = try XCTUnwrap(try Row.fetchOne(db, sql: "SELECT * FROM dictation WHERE id = ?", arguments: [record.id]))
            return row.columnNames.compactMap { row[$0] as String? }
        }
    }

    func testTheSourceLineSaysSelected() {
        XCTAssertTrue(HUDCopy.pasteSource(for: .apiKey, rewritten: true, isEdit: true).contains("selected text"))
        XCTAssertTrue(HUDCopy.editProviderFailed(.apiKey, reason: "offline").contains("selection is unchanged"))
        XCTAssertTrue(SelectionContent.none.message?.contains("press R") ?? false)
    }
}
