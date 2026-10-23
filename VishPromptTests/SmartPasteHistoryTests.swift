import GRDB
import XCTest
@testable import VishPrompt

/// History must never keep a secret that was put back for the user. Driven through the paster
/// and the real database, because the database stores whatever it is given: the leak, if there
/// were one, would be upstream of it.
final class SmartPasteHistoryTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let secret = ["sk-ant-", "api03-", "FAKEfakeFAKEfake1234567890abcdEFGH"].joined()
    private let password = ["s3cret", "Passw0rd"].joined()

    override func setUp() {
        suiteName = "vishprompt.tests.history.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func consentedPaster(_ generator: RecordingGenerator) -> SmartPaster {
        let consent = SmartPasteConsent(defaults: defaults)
        _ = consent.requestPermission(for: .apiKey)
        _ = consent.requestPermission(for: .apiKey)
        return SmartPaster(provider: .apiKey, generator: generator, consent: consent)
    }

    /// Writes the row the controller would write, reads it back, and returns every text column.
    private func storedColumns(of result: SmartPasteResult, instruction: String, destination: Destination) throws -> [String] {
        let queue = try Database.makeQueue(path: nil)
        let record = result.record(id: UUID().uuidString, instruction: instruction, destination: destination, status: .inserted)
        try queue.write { db in try record.insert(db) }
        return try queue.read { db in
            let row = try XCTUnwrap(try Row.fetchOne(db, sql: "SELECT * FROM dictation WHERE id = ?", arguments: [record.id]))
            return row.columnNames.compactMap { row[$0] as String? }
        }
    }

    private var clip: String {
        "API_KEY=\(secret)\nDATABASE_URL=postgres://admin:\(password)@db.internal:5432/app"
    }

    func testARewrittenPasteToAPersonKeepsNoSecret() async throws {
        let generator = RecordingGenerator(reply: RecordingGenerator.clipEcho)
        let result = try await consentedPaster(generator).paste(.init(clip: clip, instruction: "send this to Sam", destination: .message))
        XCTAssertEqual(result.outcome, .rewritten)
        XCTAssertTrue(result.insertText.contains(secret), "the precondition: the field gets the real value")

        let columns = try storedColumns(of: result, instruction: "send this to Sam", destination: .message)
        XCTAssertGreaterThanOrEqual(columns.count, 5)
        for column in columns {
            XCTAssertFalse(column.contains(secret), "history kept the API key: \(column)")
            XCTAssertFalse(column.contains(password), "history kept the password: \(column)")
        }
    }

    func testFlippingToAsCopiedKeepsNoSecret() async throws {
        let generator = RecordingGenerator(reply: RecordingGenerator.clipEcho)
        let result = try await consentedPaster(generator).paste(.init(clip: clip, instruction: "tidy", destination: .email))
        let flipped = result.showing(asCopied: true)
        XCTAssertEqual(flipped.insertText, clip)

        for column in try storedColumns(of: flipped, instruction: "tidy", destination: .email) {
            XCTAssertFalse(column.contains(secret), "history kept the API key: \(column)")
            XCTAssertFalse(column.contains(password), "history kept the password: \(column)")
        }
    }

    func testASilentPasteKeepsNoSecret() async throws {
        let generator = RecordingGenerator()
        let result = try await consentedPaster(generator).paste(.init(clip: clip, instruction: "", destination: .document))
        XCTAssertEqual(result.insertText, clip)
        for column in try storedColumns(of: result, instruction: "", destination: .document) {
            XCTAssertFalse(column.contains(secret))
            XCTAssertFalse(column.contains(password))
        }
    }

    func testAFallbackKeepsNoSecret() async throws {
        let generator = RecordingGenerator { _ in "Sure! Here you go." }
        let result = try await consentedPaster(generator).paste(.init(clip: clip, instruction: "shorter", destination: .message))
        guard case .fellBack = result.outcome else { return XCTFail("expected a fallback") }
        for column in try storedColumns(of: result, instruction: "shorter", destination: .message) {
            XCTAssertFalse(column.contains(secret))
            XCTAssertFalse(column.contains(password))
        }
    }
}
