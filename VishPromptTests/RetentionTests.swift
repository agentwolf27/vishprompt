import GRDB
import XCTest
@testable import VishPrompt

/// Home 4: history is kept for 30, 60 or 90 days or forever; pinned items are never pruned; this
/// install keeps everything and new installs keep 90 days; a shorter period confirms first.
@MainActor
final class RetentionTests: XCTestCase {
    private let now = HomeSnapshot.morning

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "RetentionTests-\(UUID())")!
    }

    private func queue(_ rows: [(id: String, age: TimeInterval, pinned: Bool)]) throws -> DatabaseQueue {
        let queue = try Database.makeQueue(path: nil)
        try queue.write { db in
            for row in rows {
                try DictationRecord(id: row.id, createdAt: now.addingTimeInterval(-row.age), destination: "message", level: "light",
                                    rawTranscript: "said", compiledText: "out", requestJSON: nil, status: .inserted,
                                    provider: "local", pinned: row.pinned).insert(db)
            }
        }
        return queue
    }

    private func ids(_ queue: DatabaseQueue) throws -> Set<String> {
        Set(try queue.read { try String.fetchAll($0, sql: "SELECT id FROM dictation") })
    }

    private let day: TimeInterval = 24 * 3600

    func testTheBoundaryDayKeepsWhatIsInsideIt() throws {
        let cutoff = try XCTUnwrap(HistoryRetention.cutoff(for: .days30, now: now))
        let inside = now.timeIntervalSince(cutoff) - 1
        let outside = now.timeIntervalSince(cutoff) + 1
        let q = try queue([("inside", inside, false), ("outside", outside, false), ("today", 60, false)])
        XCTAssertEqual(try HistoryRetention.count(removedBy: .days30, now: now, in: q), 1)
        XCTAssertEqual(try HistoryRetention.prune(.days30, now: now, in: q), 1)
        XCTAssertEqual(try ids(q), ["inside", "today"], "one second inside 30 days stays, one second past goes")
    }

    func testPinnedItemsSurviveEveryPeriod() throws {
        for period in RetentionPeriod.allCases {
            let q = try queue([("pinned-old", 400 * day, true), ("old", 400 * day, false)])
            try HistoryRetention.prune(period, now: now, in: q)
            XCTAssertTrue(try ids(q).contains("pinned-old"), "\(period)")
        }
    }

    func testForeverDeletesNothing() throws {
        let q = try queue([("ancient", 5000 * day, false), ("old", 400 * day, false), ("new", 60, false)])
        XCTAssertNil(HistoryRetention.cutoff(for: .forever, now: now))
        XCTAssertEqual(try HistoryRetention.count(removedBy: .forever, now: now, in: q), 0)
        XCTAssertEqual(try HistoryRetention.prune(.forever, now: now, in: q), 0)
        XCTAssertEqual(try ids(q).count, 3)
    }

    func testEachPeriodRemovesOnlyWhatIsOlderThanIt() throws {
        let q = try queue([("d20", 20 * day, false), ("d45", 45 * day, false), ("d75", 75 * day, false), ("d100", 100 * day, false)])
        XCTAssertEqual(try HistoryRetention.count(removedBy: .days90, now: now, in: q), 1)
        XCTAssertEqual(try HistoryRetention.count(removedBy: .days60, now: now, in: q), 2)
        XCTAssertEqual(try HistoryRetention.count(removedBy: .days30, now: now, in: q), 3)
    }

    func testPruningTakesTheTimingsWithIt() throws {
        let q = try queue([("old", 100 * day, false)])
        var trace = Trace()
        trace.mark(.keyDown)
        trace.mark(.keyUp)
        try q.write { db in for var row in StageTimingRecord.rows(for: trace, dictationId: "old") { try row.insert(db) } }
        try HistoryRetention.prune(.days30, now: now, in: q)
        XCTAssertEqual(try q.read { try StageTimingRecord.fetchCount($0) }, 0)
    }

    func testThisInstallKeepsEverythingAndANewOneKeeps90Days() throws {
        let existing = defaults()
        XCTAssertEqual(HistoryRetention.period(in: existing, queue: try queue([("mine", 400 * day, false)])), .forever,
                       "history already here is never deleted without being asked")
        XCTAssertEqual(existing.string(forKey: RetentionPeriod.key), "forever", "decided once and saved")

        let fresh = defaults()
        XCTAssertEqual(HistoryRetention.period(in: fresh, queue: try queue([])), .days90)

        let chosen = defaults()
        chosen.set("days30", forKey: RetentionPeriod.key)
        XCTAssertEqual(HistoryRetention.period(in: chosen, queue: try queue([("mine", 400 * day, false)])), .days30, "a choice is kept")
    }

    func testAShorterPeriodConfirmsWithTheRealCountFirst() throws {
        let store = defaults()
        let q = try queue([("d10", 10 * day, false), ("d40", 40 * day, false), ("d50", 50 * day, false), ("pinned", 50 * day, true)])
        let library = HomeLibrary(queue: { q }, defaults: store)
        library.refreshRetention(fileURL: nil)
        XCTAssertEqual(library.retention, .forever)

        library.requestRetention(.days30, now: now)
        XCTAssertEqual(library.pendingRetention?.count, 2, "pinned is not counted")
        XCTAssertEqual(library.retention, .forever, "nothing changes until confirmed")
        XCTAssertEqual(try ids(q).count, 4)

        library.cancelRetention()
        XCTAssertNil(library.pendingRetention)
        XCTAssertEqual(try ids(q).count, 4)
        XCTAssertEqual(store.string(forKey: RetentionPeriod.key), "forever")

        library.requestRetention(.days30, now: now)
        library.confirmRetention(now: now)
        XCTAssertEqual(library.retention, .days30)
        XCTAssertEqual(store.string(forKey: RetentionPeriod.key), "days30")
        XCTAssertEqual(try ids(q), ["d10", "pinned"])

        library.requestRetention(.days90, now: now)
        XCTAssertNil(library.pendingRetention, "a longer period removes nothing, so it needs no confirmation")
        XCTAssertEqual(library.retention, .days90)
    }

    func testTheConfirmationNamesTheCountAndThePeriod() {
        XCTAssertEqual(HistoryRetention.confirmation(count: 212, period: .days30), "This removes 212 items older than 30 days. Pinned items stay.")
        XCTAssertEqual(HistoryRetention.confirmation(count: 1, period: .days60), "This removes 1 item older than 60 days. Pinned items stay.")
        XCTAssertEqual(RetentionPeriod.allCases.map(\.title), ["30 days", "60 days", "90 days", "Forever"])
    }

    func testTheDatabaseSizeIsShownHonestly() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "retention-\(UUID()).sqlite")
        try Data(repeating: 1, count: 1_500_000).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let line = try XCTUnwrap(HistoryRetention.databaseSize(at: file))
        XCTAssertTrue(line.hasPrefix("History uses 1.5 MB"), line)
        XCTAssertNil(HistoryRetention.databaseSize(at: nil))
    }

    func testSettingsWithRetentionRendersInBothThemes() throws {
        let size = CGSize(width: 1120, height: 760)
        for dark in [false, true] {
            let library = HomeLibrary(queue: { nil }, defaults: defaults())
            library.page = .settings
            library.palmRestAvailable = true
            library.retention = .forever
            let bitmap = try XCTUnwrap(HomeSnapshot.capture(HomeView(library: library, reuse: HistoryReuse()), size: size, dark: dark, name: "settings"))
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 8, y: 400, viewSize: size), dark ? HomeTheme.dark.sidebar : HomeTheme.light.sidebar))
        }
    }
}
