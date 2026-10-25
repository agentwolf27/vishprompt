import GRDB
import XCTest
@testable import VishPrompt

/// Home 2: each saved dictation is a card with its time, app, mode and where the words went,
/// Copy, what you said, pin and delete; History searches and groups by day.
@MainActor
final class HistoryCardTests: XCTestCase {
    private let size = CGSize(width: 1120, height: 760)
    private var calendar: Calendar { .current }

    private func record(_ id: String, level: String = "full", mode: DictationMode? = nil, provider: String? = "local",
                        app: String? = nil, said: String = "said", out: String? = "out", ago: TimeInterval = 0,
                        now: Date = HomeSnapshot.morning) -> DictationRecord {
        DictationRecord(id: id, createdAt: now.addingTimeInterval(-ago), destination: "message", level: level,
                        rawTranscript: said, compiledText: out, requestJSON: nil, status: .inserted,
                        provider: provider, app: app, mode: mode?.rawValue)
    }

    func testTheModeIsStoredOrReadFromAnOldRowsLevel() {
        XCTAssertEqual(DictationMode.of(record("a", mode: .screenshotFix)), .screenshotFix)
        XCTAssertEqual(DictationMode.of(record("a", level: "paste")), .smartPaste)
        XCTAssertEqual(DictationMode.of(record("a", level: "paste_as_copied")), .smartPaste)
        XCTAssertEqual(DictationMode.of(record("a", level: "edit")), .edit)
        XCTAssertEqual(DictationMode.of(record("a", level: "light")), .dictate)
        XCTAssertEqual(DictationMode.allCases.map(\.title), ["Dictate", "Smart paste", "Edit by voice", "Screenshot fix"])
    }

    func testThePillSaysWhereTheWordsWentFromTheStoredProvider() {
        XCTAssertEqual(WhereItWent(record("a", provider: "local")).label, "Stayed on this Mac")
        XCTAssertEqual(WhereItWent(record("a", provider: "subscription")).label, "Sent to Claude")
        XCTAssertEqual(WhereItWent(record("a", provider: "apiKey")).label, "Sent to Claude")
        XCTAssertEqual(WhereItWent(record("a", provider: nil)).label, "Not recorded", "an old row is not guessed")
    }

    func testTheCardNamesTheAppOrForOldRowsTheDestination() {
        XCTAssertEqual(HistoryFormat.appName(record("a", app: "Slack")), "Slack")
        XCTAssertEqual(HistoryFormat.appName(record("a")), "Message")
    }

    func testOldRowsMigrateUnpinnedWithNoAppOrMode() throws {
        let queue = try DatabaseQueue()
        var migrator = Database.migrator
        try migrator.migrate(queue, upTo: "v2-provider")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO dictation (id, createdAt, destination, level, rawTranscript, compiledText, requestJSON, status, provider) VALUES ('old', ?, 'message', 'paste', 'hi', 'hi', NULL, 'inserted', 'local')", arguments: [Date()])
        }
        try migrator.migrate(queue)
        let row = try XCTUnwrap(try HistoryStore.recent(in: queue).first?.record)
        XCTAssertFalse(row.pinned)
        XCTAssertNil(row.app)
        XCTAssertNil(row.mode)
        XCTAssertEqual(DictationMode.of(row), .smartPaste)
    }

    func testPinPersistsAndPinnedCardsComeFirst() throws {
        let now = HomeSnapshot.morning
        let queue = try HomeSnapshot.sampleQueue(now: now)
        let library = HomeLibrary(queue: { queue })
        library.reload()
        let older = try XCTUnwrap(library.entries.first { $0.id == "a3" })
        library.setPinned(true, older)
        XCTAssertTrue(try XCTUnwrap(library.entries.first { $0.id == "a3" }).record.pinned, "saved, read back")
        let groups = library.historyGroups(now: now)
        XCTAssertEqual(groups.first?.label, "Pinned")
        XCTAssertEqual(groups.first?.entries.map(\.id), ["a3"])
        XCTAssertFalse(groups.dropFirst().flatMap(\.entries).contains { $0.id == "a3" }, "shown once")
        XCTAssertEqual(library.recentToday(now: now).first?.id, "a3", "Home floats it first too")
        library.setPinned(false, try XCTUnwrap(library.entries.first { $0.id == "a3" }))
        XCTAssertNotEqual(library.historyGroups(now: now).first?.label, "Pinned")
    }

    func testDeleteRemovesTheRowAndItsTimingsAndUndoPutsThemBack() throws {
        let now = HomeSnapshot.morning
        let queue = try HomeSnapshot.sampleQueue(now: now)
        var trace = Trace()
        trace.mark(.keyDown)
        trace.mark(.keyUp)
        try queue.write { db in for var row in StageTimingRecord.rows(for: trace, dictationId: "a1") { try row.insert(db) } }
        let library = HomeLibrary(queue: { queue })
        library.reload()
        let entry = try XCTUnwrap(library.entries.first { $0.id == "a1" })
        library.delete(entry)
        XCTAssertNil(library.entries.first { $0.id == "a1" })
        XCTAssertEqual(try queue.read { try StageTimingRecord.filter(Column("dictationId") == "a1").fetchCount($0) }, 0)
        library.undoDelete()
        let back = try XCTUnwrap(library.entries.first { $0.id == "a1" })
        XCTAssertEqual(back.record, entry.record)
        XCTAssertEqual(back.timings.map(\.stage), entry.timings.map(\.stage))
        XCTAssertNil(library.lastDeleted)
    }

    func testSearchCoversTextWhatWasSaidAppAndMode() {
        let r = record("a", mode: .smartPaste, app: "Slack", said: "as bullet points", out: "• Churn: 3.1%")
        XCTAssertTrue(HistoryFormat.matches(r, query: "churn"))
        XCTAssertTrue(HistoryFormat.matches(r, query: "BULLET"))
        XCTAssertTrue(HistoryFormat.matches(r, query: "slack"))
        XCTAssertTrue(HistoryFormat.matches(r, query: "smart paste"))
        XCTAssertTrue(HistoryFormat.matches(r, query: "  "))
        XCTAssertFalse(HistoryFormat.matches(r, query: "figma"))
        XCTAssertEqual(HistoryFormat.noMatch(" figma "), "Nothing matches “figma”. Try an app name, like Slack.")
    }

    func testHistoryGroupsTodayYesterdayAndDates() {
        let now = HomeSnapshot.morning
        let entries = [record("t", ago: 60), record("y", ago: 24 * 3600), record("old", ago: 5 * 24 * 3600)]
            .map { HistoryEntry(record: $0, timings: []) }
        let groups = HistoryFormat.groups(entries, now: now)
        XCTAssertEqual(groups.map(\.label).prefix(2), ["Today", "Yesterday"])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[2].entries.map(\.id), ["old"])
        XCTAssertFalse(["Today", "Yesterday", "Pinned"].contains(groups[2].label))
    }

    func testArrowKeysMoveTheSelectionThatReturnPastes() throws {
        let now = HomeSnapshot.morning
        let queue = try HomeSnapshot.sampleQueue(now: now)
        let library = HomeLibrary(queue: { queue })
        library.reload()
        library.moveSelection(by: 1, now: now)
        XCTAssertEqual(library.selection, "a1")
        library.moveSelection(by: 1, now: now)
        XCTAssertEqual(library.selection, "a2")
        XCTAssertEqual(library.selectedText, try XCTUnwrap(library.entries.first { $0.id == "a2" }?.record.compiledText))
        library.moveSelection(by: -5, now: now)
        XCTAssertEqual(library.selection, "a1", "stops at the top")
        library.query = "pricing"
        library.selection = nil
        library.moveSelection(by: 1, now: now)
        XCTAssertEqual(library.selection, "a4", "moves through what the search shows")
    }

    func testCopiedShowsForAboutASecondAndAHalf() {
        XCTAssertEqual(CopyButton.copiedFor, .milliseconds(1400))
    }

    func testHistoryRendersInBothThemes() throws {
        let now = HomeSnapshot.morning
        let queue = try HomeSnapshot.sampleQueue(now: now)
        try HistoryStore.setPinned(true, id: "a3", in: queue)
        for dark in [false, true] {
            let library = HomeLibrary(queue: { queue }, defaults: UserDefaults(suiteName: "HistoryCardTests-\(UUID())")!)
            library.page = .history
            library.expanded = ["a2"]
            library.selection = "a1"
            let view = HomeView(library: library, reuse: HistoryReuse(), now: { now })
            let bitmap = try XCTUnwrap(HomeSnapshot.capture(view, size: size, dark: dark, name: "history"))
            let theme = dark ? HomeTheme.dark : HomeTheme.light
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 8, y: 400, viewSize: size), theme.sidebar))
        }
        for dark in [false, true] {
            let library = HomeLibrary(queue: { queue }, defaults: UserDefaults(suiteName: "HistoryCardTests-\(UUID())")!)
            library.page = .history
            library.query = "figma"
            HomeSnapshot.capture(HomeView(library: library, reuse: HistoryReuse(), now: { now }), size: size, dark: dark, name: "history-empty")
        }
    }
}
