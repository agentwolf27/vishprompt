import XCTest
@testable import Visprflow

/// The redactor against a checked-in corpus rather than examples written next to the code, so
/// it cannot quietly be fitted to its own tests.
final class RedactorTests: XCTestCase {
    private struct Corpus: Decodable {
        struct Entry: Decodable {
            var name: String
            var template: String
            var parts: [String]
            var secret: String { parts.joined() }
            var text: String { template.replacingOccurrences(of: "{secret}", with: secret) }
        }
        var secrets: [Entry]
        var keep: [String]
    }

    private struct Misses: Decodable {
        struct Miss: Decodable {
            var text: String
            var why: String
        }
        var misses: [Miss]
    }

    private func fixture<T: Decodable>(_ name: String) throws -> T {
        let bundle = Bundle(for: RedactorTests.self)
        let url = try XCTUnwrap(bundle.resourceURL).appending(path: "Fixtures/secrets/\(name)")
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    // MARK: The corpus

    func testEverySecretInTheCorpusIsCaughtAndRestored() throws {
        let corpus: Corpus = try fixture("corpus.json")
        XCTAssertGreaterThanOrEqual(corpus.secrets.count, 15, "the corpus shrank")
        for entry in corpus.secrets {
            let redaction = Redactor.redact(entry.text)
            XCTAssertFalse(redaction.text.contains(entry.secret), "\(entry.name) leaked: \(redaction.text)")
            XCTAssertFalse(redaction.isEmpty, "\(entry.name) was not caught")
            XCTAssertEqual(redaction.restore(redaction.text), entry.text, "\(entry.name) did not round-trip")
        }
    }

    func testIdentifiersAgentsNeedAreKept() throws {
        let corpus: Corpus = try fixture("corpus.json")
        for text in corpus.keep {
            let redaction = Redactor.redact(text)
            XCTAssertEqual(redaction.text, text, "mangled an identifier: \(text)")
            XCTAssertTrue(redaction.isEmpty)
        }
    }

    /// Exact in both directions: a new miss fails, and so does a "miss" that is now caught,
    /// which means the list no longer describes the redactor and has to be updated.
    func testKnownMissesAreExactlyTheOnesListed() throws {
        let known: Misses = try fixture("known-misses.json")
        XCTAssertFalse(known.misses.isEmpty)
        for miss in known.misses {
            let redaction = Redactor.redact(miss.text)
            XCTAssertEqual(redaction.text, miss.text, "now caught, so move it to corpus.json: \(miss.text)")
        }
    }

    func testVocabularyIsExempt() {
        let token = "Q7xk2Lp9Zr4Tm8Wn3Vb6Hc1Jd5Fg0SaE"
        XCTAssertFalse(Redactor.redact("seed \(token)").isEmpty)
        XCTAssertTrue(Redactor.redact("seed \(token)", exempt: [token]).isEmpty)
    }

    func testTheSameSecretTwiceSharesOnePlaceholder() {
        let key = ["AKIA", "IOSFODNN7", "EXAMPLE"].joined()
        let redaction = Redactor.redact("first \(key) then \(key)", nonce: "abc")
        XCTAssertEqual(redaction.secrets.count, 1)
        XCTAssertEqual(redaction.text, "first ⟦vf-abc-1⟧ then ⟦vf-abc-1⟧")
    }

    // MARK: Placeholders that come back wrong

    private func sample() -> (Redaction, String) {
        let key = ["sk-ant-", "api03-", "FAKEfakeFAKEfake1234567890abcdEFGH"].joined()
        return (Redactor.redact("key=\(key)", nonce: "n0nce"), key)
    }

    func testRestorePutsTheSecretBackLocally() {
        let (redaction, key) = sample()
        XCTAssertEqual(redaction.restore("use ⟦vf-n0nce-1⟧ here"), "use \(key) here")
    }

    func testDisplayLabelsInsteadOfRestoring() {
        let (redaction, key) = sample()
        let shown = redaction.display("use ⟦vf-n0nce-1⟧ here")
        XCTAssertEqual(shown, "use [redacted API key] here")
        XCTAssertFalse(shown?.contains(key) ?? true)
    }

    func testAForgedPlaceholderFallsBack() {
        let (redaction, _) = sample()
        XCTAssertNil(redaction.restore("use ⟦vf-n0nce-2⟧"), "never issued")
        XCTAssertNil(redaction.display("use ⟦vf-n0nce-2⟧"))
    }

    func testAPlaceholderFromAnotherNonceFallsBack() {
        let (redaction, _) = sample()
        XCTAssertNil(redaction.restore("use ⟦vf-other-1⟧"))
    }

    func testADuplicatedPlaceholderFallsBack() {
        let (redaction, _) = sample()
        XCTAssertNil(redaction.restore("⟦vf-n0nce-1⟧ and again ⟦vf-n0nce-1⟧"))
    }

    func testADroppedPlaceholderIsAllowed() {
        // "Make this shorter" may leave the value out; that is not a forgery.
        let (redaction, _) = sample()
        XCTAssertEqual(redaction.restore("shorter now"), "shorter now")
    }

    func testAClipCannotPreloadAPlaceholder() {
        // Text that already looks like a placeholder is not one of ours, so it is never
        // restored into anything.
        let redaction = Redactor.redact("look ⟦vf-guess-1⟧", nonce: "real")
        XCTAssertTrue(redaction.isEmpty)
        XCTAssertNil(redaction.restore(redaction.text))
    }

    func testNoncesDiffer() {
        XCTAssertNotEqual(Redactor.makeNonce(), Redactor.makeNonce())
    }
}
