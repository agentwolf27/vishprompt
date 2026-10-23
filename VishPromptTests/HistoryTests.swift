import GRDB
import XCTest
@testable import VishPrompt

/// UI/UX L2: History shows what was said, what left the Mac, and what came out.
final class HistoryTests: XCTestCase {
    private func record(_ id: String, said: String, out: String?, provider: String?, ago: TimeInterval = 0, json: String? = nil) -> DictationRecord {
        DictationRecord(id: id, createdAt: Date(timeIntervalSinceNow: -ago), destination: "claude_code", level: "full",
                        rawTranscript: said, compiledText: out, requestJSON: json, status: .inserted, provider: provider)
    }

    func testDurationsCarryNoFakePrecision() {
        XCTAssertEqual(HistoryFormat.duration(ms: 210.4), "210 ms")
        XCTAssertEqual(HistoryFormat.duration(ms: 45.2), "45 ms")
        XCTAssertEqual(HistoryFormat.duration(ms: 8.73), "8.7 ms")
        XCTAssertEqual(HistoryFormat.duration(ms: 6_440), "6.4 s")
        XCTAssertEqual(HistoryFormat.duration(ms: 999.6), "1.0 s", "rounding must not print 1000 ms")
        XCTAssertEqual(HistoryFormat.duration(ms: 0), "0 ms")
    }

    func testWhatLeftTheMacIsStatedHonestly() {
        XCTAssertEqual(HistoryFormat.sentLine(record("a", said: "x", out: "y", provider: "local")), "Stayed on this Mac")
        XCTAssertEqual(HistoryFormat.sentLine(record("a", said: "x", out: "y", provider: "subscription")), "Sent to your Claude subscription")
        XCTAssertTrue(HistoryFormat.sentLine(record("a", said: "x", out: "y", provider: nil)).hasPrefix("Not recorded"),
                      "old rows must not claim anything")
    }

    func testTheExactMessageIsShownOnlyWhenSomethingWasSent() {
        let json = #"{"max_tokens":512,"model":"claude-haiku-4-5","system_characters":6070,"user":"<transcript>fix it</transcript>"}"#
        let sent = record("a", said: "fix it", out: "Fix it.", provider: "apiKey", json: json)
        XCTAssertEqual(HistoryFormat.sentMessage(sent), "<transcript>fix it</transcript>")
        XCTAssertEqual(HistoryFormat.model(sent), "claude-haiku-4-5")
        // A local cleanup also records a request shape, but nothing was sent.
        let local = record("b", said: "fix it", out: "Fix it.", provider: "local", json: json)
        XCTAssertNil(HistoryFormat.sentMessage(local))
        XCTAssertNil(HistoryFormat.model(local))
    }

    func testRecentIsNewestFirstWithTimingsAndSearch() throws {
        let queue = try Database.makeQueue(path: nil)
        var trace = Trace()
        trace.mark(.keyDown)
        trace.mark(.keyUp)
        trace.mark(.transcriptReady)
        try queue.write { db in
            try record("old", said: "the login bug", out: "Fix the login bug.", provider: "local", ago: 60).insert(db)
            try record("new", said: "send the figma link", out: "send the figma link?", provider: "subscription").insert(db)
            for var row in StageTimingRecord.rows(for: trace, dictationId: "new") { try row.insert(db) }
        }
        let all = try HistoryStore.recent(in: queue)
        XCTAssertEqual(all.map(\.id), ["new", "old"])
        XCTAssertEqual(all.first?.timings.map(\.stage), ["keyDown", "keyUp", "transcriptReady"])
        XCTAssertNotNil(HistoryFormat.total(all[0].timings))
        XCTAssertEqual(try HistoryStore.recent(in: queue, matching: "login").map(\.id), ["old"])
        XCTAssertEqual(try HistoryStore.recent(in: queue, matching: "figma link?").map(\.id), ["new"])
        XCTAssertTrue(try HistoryStore.recent(in: queue, matching: "nothing like this").isEmpty)
    }

    func testAMigratedRowWithoutAProviderReadsBackAsUnknown() throws {
        let queue = try Database.makeQueue(path: nil)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO dictation (id, createdAt, destination, level, rawTranscript, compiledText, requestJSON, status) VALUES ('legacy', ?, 'message', 'light', 'hi', 'hi', NULL, 'inserted')", arguments: [Date()])
        }
        let entry = try XCTUnwrap(try HistoryStore.recent(in: queue).first)
        XCTAssertNil(entry.record.provider)
    }

    func testSmartPasteRowsSayWhetherTheClipLeft() {
        let silent = SmartPasteResult(insertText: "x", historyText: "x", outcome: .asCopied, asCopiedText: "x", asCopiedHistoryText: "x")
        XCTAssertEqual(silent.record(id: "1", instruction: "", destination: .message, status: .inserted).provider, "local")
        var sent = silent
        sent.outcome = .rewritten
        sent.sentTo = .apiKey
        XCTAssertEqual(sent.record(id: "2", instruction: "shorter", destination: .message, status: .inserted).provider, "apiKey")
    }

    func testListTitles() {
        XCTAssertEqual(HistoryFormat.title(record("a", said: "first line\nsecond", out: nil, provider: "local")), "first line")
        XCTAssertEqual(HistoryFormat.title(record("a", said: "", out: nil, provider: "local")), "(nothing said)")
    }

    // MARK: UI v2.4 rows, paste again, copy

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 23 Oct 2026, 15:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_767_600)

    func testARowReadsWhereWhenAndWhatLeft() {
        let local = record("a", said: "fix the login bug", out: "Fix the login bug.", provider: "local", ago: 0)
        var row = local
        row.createdAt = now.addingTimeInterval(-130)
        XCTAssertEqual(HistoryFormat.rowLine(row, now: now, calendar: calendar), "→ Claude Code · 2 min ago · stayed on this Mac")

        var sent = record("b", said: "x", out: "y", provider: "subscription")
        sent.createdAt = now.addingTimeInterval(-3 * 3600)
        XCTAssertEqual(HistoryFormat.rowLine(sent, now: now, calendar: calendar), "→ Claude Code · 3 h ago · sent to your Claude subscription")

        var cancelled = row
        cancelled.status = .cancelled
        XCTAssertTrue(HistoryFormat.rowLine(cancelled, now: now, calendar: calendar).hasSuffix("· cancelled"),
                      "a row that never landed must not read as if it did")
    }

    func testWhenIsSaidTheWayAPersonWouldSayIt() {
        XCTAssertEqual(HistoryFormat.when(now.addingTimeInterval(-20), now: now, calendar: calendar), "just now")
        XCTAssertEqual(HistoryFormat.when(now.addingTimeInterval(-59 * 60), now: now, calendar: calendar), "59 min ago")
        XCTAssertEqual(HistoryFormat.when(now.addingTimeInterval(-14 * 3600), now: now, calendar: calendar), "14 h ago")
        XCTAssertEqual(HistoryFormat.when(now.addingTimeInterval(-20 * 3600), now: now, calendar: calendar), "yesterday")
        XCTAssertNotEqual(HistoryFormat.when(now.addingTimeInterval(-5 * 86400), now: now, calendar: calendar), "yesterday")
    }

    func testDestinationsAreNamedAsInSettings() {
        XCTAssertEqual(HistoryFormat.destinationName("claude_code"), "Claude Code")
        XCTAssertEqual(HistoryFormat.destinationName("gone_now"), "gone_now", "a removed destination keeps its id, not a guess")
    }

    func testReturnAndCopyReuseWhatCameOutOrElseWhatWasSaid() {
        XCTAssertEqual(HistoryFormat.reusableText(record("a", said: "fix it", out: "Fix it.", provider: "local")), "Fix it.")
        XCTAssertEqual(HistoryFormat.reusableText(record("a", said: "fix it", out: nil, provider: "local")), "fix it")
        XCTAssertEqual(HistoryFormat.reusableText(record("a", said: "fix it", out: "  ", provider: "local")), "fix it")
        XCTAssertNil(HistoryFormat.reusableText(record("a", said: "", out: nil, provider: "local")), "nothing to paste, so Return does nothing")
    }

    func testARedactedSecretIsSaidBeforeItIsPasted() {
        XCTAssertNotNil(HistoryFormat.redactionNote("curl -H 'x-api-key: [redacted API key]'"))
        XCTAssertNil(HistoryFormat.redactionNote("an array [0] and a link [here]"))
    }

    @MainActor
    func testEveryPasteAgainEndingNamesWhatHappened() {
        XCTAssertEqual(HistoryReuse.message(for: .pasted(app: "Notes")), "Pasted into Notes.")
        XCTAssertTrue(HistoryReuse.message(for: .copiedNoTarget).contains("press ⌘V"))
        let failed = HistoryReuse.message(for: .failed(app: "Notes", reason: "Accessibility is off."))
        XCTAssertEqual(failed, "Couldn't paste into Notes (Accessibility is off). It's copied, so press ⌘V there.")
        XCTAssertEqual(HistoryReuse.hint(target: "Slack"), "Return pastes it into Slack · ⌘C copies")
        XCTAssertTrue(HistoryReuse.hint(target: nil).contains("⌘C copies"))
    }
}
