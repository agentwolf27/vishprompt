import Foundation
import GRDB
import Synchronization

/// Local history store. Lives in ~/Library/Application Support/Visprflow/visprflow.sqlite.
/// Every dictation row carries the exact request that left the machine, so the privacy
/// contract in the plan is inspectable rather than promised.
enum Database {
    /// `DatabaseQueue` is already thread-safe and Sendable. Holding it off the main actor keeps
    /// history writes from the audio and compile pipeline off the latency path.
    private static let storage = Mutex<DatabaseQueue?>(nil)

    static var queue: DatabaseQueue? {
        storage.withLock { $0 }
    }

    /// Where the history file lives, for "Show in Finder". Nil until the app has opened it.
    static var fileURL: URL? {
        guard queue != nil,
              let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        return support.appending(path: "Visprflow/visprflow.sqlite")
    }

    /// The text of the most recent dictation that produced any, for the menu's "last
    /// dictation". What history stores: never a restored secret.
    static func lastDictationText(in queue: DatabaseQueue) throws -> String? {
        try queue.read { db in
            try String.fetchOne(db, sql: """
                SELECT compiledText FROM dictation
                WHERE compiledText IS NOT NULL AND compiledText != ''
                ORDER BY createdAt DESC LIMIT 1
                """)
        }
    }

    static func open() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appending(path: "Visprflow", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "visprflow.sqlite")
        let opened = try makeQueue(path: file.path)
        storage.withLock { existing in
            existing = opened
        }
        Log.db.info("Database opened at \(file.path, privacy: .public)")
    }

    /// Opens (or creates) a migrated database. Pass nil for an in-memory database in tests.
    static func makeQueue(path: String?) throws -> DatabaseQueue {
        let queue = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        try migrator.migrate(queue)
        return queue
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-dictation-and-timing") { db in
            try db.create(table: "dictation") { t in
                t.primaryKey("id", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("destination", .text).notNull()
                t.column("level", .text).notNull()
                t.column("rawTranscript", .text).notNull()
                t.column("compiledText", .text)
                t.column("requestJSON", .text)
                t.column("status", .text).notNull()
            }
            try db.create(table: "stageTiming") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("dictationId", .text).notNull()
                    .references("dictation", onDelete: .cascade)
                t.column("stage", .text).notNull()
                t.column("offsetMs", .double).notNull()
                t.column("sinceLastMs", .double).notNull()
            }
            // Unique so a retried write updates rather than silently duplicating timings.
            try db.create(
                index: "stageTiming_dictation_stage",
                on: "stageTiming",
                columns: ["dictationId", "stage"],
                unique: true
            )
        }
        // Which provider a dictation was sent to, so History can say "Stayed on this Mac"
        // and be right. The request alone cannot tell: a local cleanup records one too.
        // Null on rows from before this migration, which History says plainly.
        migrator.registerMigration("v2-provider") { db in
            try db.alter(table: "dictation") { t in
                t.add(column: "provider", .text)
            }
        }
        // For the Home window's cards: the app the words went to, how they were made, and
        // whether the user pinned them. Old rows keep null app and mode, which the cards read
        // from the destination and the level instead.
        migrator.registerMigration("v3-app-mode-pinned") { db in
            try db.alter(table: "dictation") { t in
                t.add(column: "app", .text)
                t.add(column: "mode", .text)
                t.add(column: "pinned", .boolean).notNull().defaults(to: false)
            }
        }
        // Which app or site each dictation went to, finer than the destination: the bundle id,
        // and for a browser the front tab's host, so Slack is told from Messages and claude.ai
        // from ChatGPT. Null on older rows. Deleted with the row, like everything else.
        migrator.registerMigration("v4-app-identity") { db in
            try db.alter(table: "dictation") { t in
                t.add(column: "bundleId", .text)
                t.add(column: "urlHost", .text)
            }
        }
        // What happened after: the first key on the preview, the levels tried and the one
        // inserted, ⌘Z within 30 s, copies and paste-again from History, and where the text
        // came from. Measurement only (PLAN.md, "Step 0"). Deleted with the row.
        migrator.registerMigration("v5-outcome-signals") { db in
            try db.alter(table: "dictation") { t in
                t.add(column: "firstAction", .text)
                t.add(column: "levelsTried", .text)
                t.add(column: "insertedLevel", .text)
                t.add(column: "undoWithin30s", .boolean).notNull().defaults(to: false)
                t.add(column: "copiedOutput", .integer).notNull().defaults(to: 0)
                t.add(column: "copiedSaid", .integer).notNull().defaults(to: 0)
                t.add(column: "pastedAgain", .integer).notNull().defaults(to: 0)
                t.add(column: "provenance", .text)
            }
        }
        return migrator
    }
}

struct DictationRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "dictation"

    enum Status: String, Codable {
        case inserted
        case cancelled
        case failed
        case rawFallback
    }

    var id: String
    var createdAt: Date
    var destination: String
    var level: String
    var rawTranscript: String
    var compiledText: String?
    var requestJSON: String?
    var status: Status
    /// The provider the words were sent to, or "local" when nothing left the Mac. Nil on rows
    /// recorded before the provider was.
    var provider: String? = nil
    /// The app in front when the dictation started, by name. Nil on older rows.
    var app: String? = nil
    /// A `DictationMode` raw value. Nil on older rows, which the level tells apart.
    var mode: String? = nil
    /// Pinned rows come first in History and are never pruned.
    var pinned: Bool = false
    /// The focused app's bundle identifier, and for a browser the front tab's host. Nil on
    /// rows from before they were stored.
    var bundleId: String? = nil
    var urlHost: String? = nil

    /// Which app or site this went to, for per-app settings and stats.
    var identity: AppIdentity { AppIdentity(bundleID: bundleId, host: urlHost) }

    // Outcome signals (v5). Nil or zero on rows from before they were recorded.
    /// The first key on the preview: insert, cycleLevel, cycleBack, rerecord, cancel or level.
    var firstAction: String? = nil
    /// Every level tried, in order, comma-separated.
    var levelsTried: String? = nil
    var insertedLevel: String? = nil
    var undoWithin30s: Bool = false
    var copiedOutput: Int = 0
    var copiedSaid: Int = 0
    var pastedAgain: Int = 0
    /// Where the text came from: spoken, clip, selection or screenshot.
    var provenance: String? = nil

    /// Accepted as-is: inserted, Return as the first key (or no preview at all), one level, no
    /// undo. What Home's "How each app is going" counts.
    var acceptedAsIs: Bool {
        guard status == .inserted || status == .rawFallback, !undoWithin30s else { return false }
        guard firstAction == nil || firstAction == "insert" else { return false }
        return (levelsTried ?? "").split(separator: ",").count <= 1
    }

    static func provenance(isEdit: Bool, isPaste: Bool, isScreenshot: Bool) -> String {
        if isEdit { return "selection" }
        if isPaste { return "clip" }
        return isScreenshot ? "screenshot" : "spoken"
    }
}

struct StageTimingRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "stageTiming"

    var id: Int64?
    var dictationId: String
    var stage: String
    var offsetMs: Double
    var sinceLastMs: Double

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Rows for every mark in a trace, ready to insert alongside its dictation.
    static func rows(for trace: Trace, dictationId: String) -> [StageTimingRecord] {
        trace.stageDurations().map { item in
            StageTimingRecord(
                id: nil,
                dictationId: dictationId,
                stage: item.stage.rawValue,
                offsetMs: Trace.milliseconds(item.offset),
                sinceLastMs: Trace.milliseconds(item.sinceLast)
            )
        }
    }
}
