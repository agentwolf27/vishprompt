import GRDB
import XCTest
@testable import VishPrompt

/// Step 0, part 2: each row keeps the outcome signals the app already sees. Measurement only.
final class OutcomeSignalTests: XCTestCase {
    private func record(_ id: String, status: DictationRecord.Status = .inserted) -> DictationRecord {
        DictationRecord(id: id, createdAt: Date(), destination: "message", level: "light", rawTranscript: "x",
                        compiledText: "y", requestJSON: nil, status: status, provider: "local")
    }

    // MARK: The preview

    func testTheFirstDecisiveKeyIsKeptAndScrollingIsNot() {
        var s = PreviewSignals(levelsTried: [.full])
        s.noteKey(.scrollDown)
        XCTAssertNil(s.firstAction)
        s.noteKey(.cycleLevel)
        s.noteKey(.insert)
        XCTAssertEqual(s.firstAction, "cycleLevel", "only the first")
        var levelKey = PreviewSignals()
        levelKey.noteKey(.levelMedium)
        XCTAssertEqual(levelKey.firstAction, "level")
        var back = PreviewSignals()
        back.noteKey(.cycleBack)
        XCTAssertEqual(back.firstAction, "cycleBack")
    }

    func testEveryLevelTriedIsKeptOnceInOrder() {
        var s = PreviewSignals(levelsTried: [.full])
        s.noteLevel(.medium)
        s.noteLevel(.full)
        s.noteLevel(.light)
        XCTAssertEqual(s.levelsTried, [.full, .medium, .light])
        XCTAssertEqual(s.levelsText(including: .light), "full,medium,light")
        XCTAssertEqual(PreviewSignals().levelsText(including: .light), "light", "no preview: the one level inserted")
    }

    func testProvenance() {
        XCTAssertEqual(DictationRecord.provenance(isEdit: false, isPaste: false, isScreenshot: false), "spoken")
        XCTAssertEqual(DictationRecord.provenance(isEdit: false, isPaste: true, isScreenshot: false), "clip")
        XCTAssertEqual(DictationRecord.provenance(isEdit: true, isPaste: true, isScreenshot: false), "selection")
        XCTAssertEqual(DictationRecord.provenance(isEdit: false, isPaste: false, isScreenshot: true), "screenshot")
    }

    func testAcceptedAsIsMeansReturnFirstOneLevelNoUndo() {
        var r = record("a")
        r.firstAction = "insert"
        r.levelsTried = "full"
        XCTAssertTrue(r.acceptedAsIs)
        r.levelsTried = "full,medium"
        XCTAssertFalse(r.acceptedAsIs, "a level was tried")
        r.levelsTried = "full"
        r.firstAction = "cycleLevel"
        XCTAssertFalse(r.acceptedAsIs, "Tab came first")
        r.firstAction = nil
        XCTAssertTrue(r.acceptedAsIs, "no preview: inserted straight away")
        r.undoWithin30s = true
        XCTAssertFalse(r.acceptedAsIs)
        XCTAssertFalse(record("b", status: .cancelled).acceptedAsIs)
    }

    // MARK: ⌘Z

    func testUndoCountsOnlyWithinThirtySecondsInTheSameApp() {
        let t = Date()
        XCTAssertTrue(UndoWindow.counts(insertedAt: t, now: t.addingTimeInterval(29), insertedInto: "com.apple.Notes", frontmost: "com.apple.Notes"))
        XCTAssertFalse(UndoWindow.counts(insertedAt: t, now: t.addingTimeInterval(31), insertedInto: "com.apple.Notes", frontmost: "com.apple.Notes"))
        XCTAssertFalse(UndoWindow.counts(insertedAt: t, now: t.addingTimeInterval(5), insertedInto: "com.apple.Notes", frontmost: "com.apple.mail"), "an undo in another app is that app's")
        XCTAssertTrue(UndoWindow.counts(insertedAt: t, now: t.addingTimeInterval(5), insertedInto: nil, frontmost: "com.apple.mail"), "an insert that could not name its app")
    }

    // MARK: The store

    func testSignalsAreCountedOnTheirRowAndUndoIsMarkedOnce() async throws {
        let queue = try Database.makeQueue(path: nil)
        let row = record("a")
        try await queue.write { db in try row.insert(db) }
        try await HistoryStore.bump(.copiedOutput(id: "a"), in: queue)
        try await HistoryStore.bump(.copiedOutput(id: "a"), in: queue)
        try await HistoryStore.bump(.copiedSaid(id: "a"), in: queue)
        try await HistoryStore.bump(.pastedAgain(id: "a"), in: queue)
        try await HistoryStore.bump(.undo(id: "a"), in: queue)
        try await HistoryStore.bump(.undo(id: "a"), in: queue)
        let saved = try await queue.read { try DictationRecord.fetchOne($0, key: "a") }
        XCTAssertEqual(saved?.copiedOutput, 2)
        XCTAssertEqual(saved?.copiedSaid, 1)
        XCTAssertEqual(saved?.pastedAgain, 1)
        XCTAssertEqual(saved?.undoWithin30s, true)
        let missing = try await queue.read { try DictationRecord.fetchOne($0, key: "missing") }
        XCTAssertNil(missing)
    }

    func testAV4RowMigratesWithNoSignalsAndRetentionTakesThemWithTheRow() throws {
        let queue = try DatabaseQueue()
        var migrator = Database.migrator
        try migrator.migrate(queue, upTo: "v4-app-identity")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO dictation (id, createdAt, destination, level, rawTranscript, compiledText, requestJSON, status, provider, app, mode, pinned, bundleId, urlHost) VALUES ('old', ?, 'message', 'light', 'hi', 'hi', NULL, 'inserted', 'local', 'Slack', 'dictate', 0, 'com.tinyspeck.slackmacgap', NULL)", arguments: [Date().addingTimeInterval(-100 * 86400)])
        }
        try migrator.migrate(queue)
        let old = try XCTUnwrap(try queue.read { try DictationRecord.fetchOne($0, key: "old") })
        XCTAssertNil(old.firstAction)
        XCTAssertEqual(old.copiedOutput, 0)
        XCTAssertFalse(old.undoWithin30s)
        XCTAssertTrue(old.acceptedAsIs, "an old inserted row with nothing against it")
        XCTAssertEqual(try HistoryRetention.prune(.days30, in: queue), 1)
    }

    // MARK: Short cancels

    func testShortCancelsAreCountedPerDay() throws {
        let defaults = UserDefaults(suiteName: "OutcomeSignalTests-\(UUID())")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let counter = ShortCancelCounter(defaults: defaults, calendar: calendar)
        let today = Date(timeIntervalSince1970: 1_792_767_600)
        // Counted in the order they happen: the app only ever counts "now".
        counter.increment(on: today.addingTimeInterval(-100 * 86400))
        counter.increment(on: today.addingTimeInterval(-10 * 86400))
        counter.increment(on: today.addingTimeInterval(-3 * 86400))
        counter.increment(on: today)
        counter.increment(on: today)
        XCTAssertEqual(counter.count(on: today), 2)
        XCTAssertEqual(counter.lastWeek(ending: today), 3)
        XCTAssertEqual((defaults.dictionary(forKey: ShortCancelCounter.key) as? [String: Int])?.count, 3, "older than ninety days is dropped at the next count")
    }

    // MARK: Copies and paste-again

    @MainActor
    func testACopyFromACardNamesItsRow() {
        let reuse = HistoryReuse()
        var seen: [OutcomeSignal] = []
        reuse.onSignal = { seen.append($0) }
        reuse.copy("out", id: "a")
        reuse.copy("said", id: "a", ofWhatWasSaid: true)
        reuse.copy("anything")
        XCTAssertEqual(seen, [.copiedOutput(id: "a"), .copiedSaid(id: "a")], "a copy with no row is not counted")
    }
}
