import GRDB
import XCTest
@testable import VishPrompt

/// Step 0, part 1: every dictation row keeps which app or site it went to, finer than the
/// destination, and older databases migrate without losing a row.
final class AppIdentityTests: XCTestCase {
    private func context(bundle: String, url: String? = nil) -> FocusContext {
        var c = FocusContext()
        c.bundleIdentifier = bundle
        c.browserURL = url
        return c
    }

    func testABrowserKeepsTheSiteAndANativeAppDoesNot() {
        let claude = AppIdentity.make(context(bundle: "com.google.Chrome", url: "https://claude.ai/chat/abc"))
        XCTAssertEqual(claude.key, "claude.ai")
        XCTAssertEqual(AppIdentity.make(context(bundle: "com.google.Chrome", url: "https://chatgpt.com/c/1")).key, "chatgpt.com")
        XCTAssertEqual(AppIdentity.make(context(bundle: "com.tinyspeck.slackmacgap", url: "https://ignored.example")).key, "com.tinyspeck.slackmacgap", "a native app's URL means nothing")
        XCTAssertEqual(AppIdentity.make(context(bundle: "com.apple.MobileSMS")).key, "com.apple.MobileSMS")
        XCTAssertNil(AppIdentity.make(FocusContext()).key)
        XCTAssertEqual(AppIdentity.make(context(bundle: "com.apple.Safari")).key, "com.apple.Safari", "a browser with no readable tab is the browser")
    }

    func testTheSplitNamesSlackFromMessagesAndClaudeFromChatGPT() {
        XCTAssertEqual(AppIdentity.displayName(key: "com.tinyspeck.slackmacgap", fallback: "Slack"), "Slack")
        XCTAssertEqual(AppIdentity.displayName(key: "com.apple.MobileSMS", fallback: "Messages"), "Messages")
        XCTAssertEqual(AppIdentity.displayName(key: "claude.ai", fallback: "Google Chrome"), "claude.ai")
        XCTAssertEqual(AppIdentity.displayName(key: "chatgpt.com", fallback: "Google Chrome"), "ChatGPT")
        XCTAssertEqual(AppIdentity.displayName(key: "gemini.google.com", fallback: "Safari"), "Gemini")
        XCTAssertEqual(AppIdentity.displayName(key: "www.notion.so", fallback: "Safari"), "notion.so", "an unknown site by its host")
        XCTAssertEqual(AppIdentity.displayName(key: "com.example.unknownapp", fallback: "Unknown App"), "Unknown App", "an unknown app by its name, never its bundle id")
        XCTAssertEqual(AppIdentity.displayName(key: nil, fallback: "Notes"), "Notes")
    }

    func testTheDestinationStaysTheFormattingFamily() {
        // Slack and Messages are both `message`; claude.ai and ChatGPT are both `chat`.
        XCTAssertEqual(DestinationResolver.resolve(context(bundle: "com.tinyspeck.slackmacgap")).id, "message")
        XCTAssertEqual(DestinationResolver.resolve(context(bundle: "com.apple.MobileSMS")).id, "message")
        XCTAssertEqual(DestinationResolver.resolve(context(bundle: "com.google.Chrome", url: "https://claude.ai/")).id, "chat")
        XCTAssertEqual(DestinationResolver.resolve(context(bundle: "com.google.Chrome", url: "https://chatgpt.com/")).id, "chat")
    }

    func testACardNamesTheSiteNotTheBrowser() {
        var record = DictationRecord(id: "a", createdAt: Date(), destination: "chat", level: "full", rawTranscript: "x",
                                     compiledText: "y", requestJSON: nil, status: .inserted, provider: "local", app: "Google Chrome")
        XCTAssertEqual(HistoryFormat.appName(record), "Google Chrome", "an older row: the app's name")
        record.bundleId = "com.google.Chrome"
        record.urlHost = "claude.ai"
        XCTAssertEqual(HistoryFormat.appName(record), "claude.ai")
        record.urlHost = nil
        XCTAssertEqual(HistoryFormat.appName(record), "Chrome")
    }

    // MARK: Migration

    /// A database with the v3 schema and rows shaped like the real ones.
    private func v3Database() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        var migrator = Database.migrator
        try migrator.migrate(queue, upTo: "v3-app-mode-pinned")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO dictation (id, createdAt, destination, level, rawTranscript, compiledText, requestJSON, status, provider, app, mode, pinned)
                VALUES ('r1', ?, 'message', 'light', 'hey', 'Hey.', NULL, 'inserted', 'local', 'Slack', 'dictate', 1),
                       ('r2', ?, 'claude_code', 'full', 'fix it', 'Fix it.', '{"model":"x"}', 'inserted', 'subscription', 'Terminal', NULL, 0)
                """, arguments: [Date(), Date()])
            try db.execute(sql: "INSERT INTO stageTiming (dictationId, stage, offsetMs, sinceLastMs) VALUES ('r1', 'keyUp', 10, 10)")
        }
        return queue
    }

    func testAV3DatabaseMigratesKeepingEveryRowWithNoIdentityYet() throws {
        let queue = try v3Database()
        try Database.migrator.migrate(queue)
        let rows = try queue.read { try DictationRecord.order(Column("id")).fetchAll($0) }
        XCTAssertEqual(rows.map(\.id), ["r1", "r2"])
        XCTAssertTrue(rows.allSatisfy { $0.bundleId == nil && $0.urlHost == nil })
        XCTAssertTrue(rows[0].pinned, "nothing else changed")
        XCTAssertEqual(try queue.read { try StageTimingRecord.fetchCount($0) }, 1)
        // A new row with an identity round-trips.
        try queue.write { db in
            try DictationRecord(id: "r3", createdAt: Date(), destination: "chat", level: "full", rawTranscript: "x", compiledText: "y",
                                requestJSON: nil, status: .inserted, provider: "local", app: "Google Chrome",
                                bundleId: "com.google.Chrome", urlHost: "claude.ai").insert(db)
        }
        let r3 = try queue.read { try DictationRecord.fetchOne($0, key: "r3") }
        XCTAssertEqual(r3?.identity.key, "claude.ai")
    }

    func testACopyOfTheRealHistoryFileMigratesWhenThereIsOne() throws {
        // Vish's own file, copied to a temporary place and migrated there. When the file is not
        // on this Mac the check runs against a real-shaped database instead, so it never skips.
        let real = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Visprflow/visprflow.sqlite")
        let copy = FileManager.default.temporaryDirectory.appending(path: "migrate-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: copy) }
        let queue: DatabaseQueue
        let before: Int
        if FileManager.default.fileExists(atPath: real.path) {
            try FileManager.default.copyItem(at: real, to: copy)
            let raw = try DatabaseQueue(path: copy.path)
            before = try raw.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM dictation") ?? 0 }
            queue = try Database.makeQueue(path: copy.path)
            print("PROBE migrated a copy of the real history: \(before) rows")
        } else {
            queue = try v3Database()
            before = 2
            try Database.migrator.migrate(queue)
        }
        let after = try queue.read { try DictationRecord.fetchCount($0) }
        XCTAssertEqual(after, before, "no row lost")
        let columns = try queue.read { db in try db.columns(in: "dictation").map(\.name) }
        XCTAssertTrue(columns.contains("bundleId") && columns.contains("urlHost"))
    }

    func testRetentionDeletesTheIdentityWithTheRow() throws {
        let queue = try Database.makeQueue(path: nil)
        let old = Date().addingTimeInterval(-100 * 24 * 3600)
        try queue.write { db in
            try DictationRecord(id: "old", createdAt: old, destination: "message", level: "light", rawTranscript: "x", compiledText: "y",
                                requestJSON: nil, status: .inserted, provider: "local", bundleId: "com.apple.MobileSMS").insert(db)
        }
        XCTAssertEqual(try HistoryRetention.prune(.days30, in: queue), 1)
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM dictation WHERE bundleId IS NOT NULL") }, 0)
    }
}
