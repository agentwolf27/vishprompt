import Foundation
import GRDB

/// How long History keeps dictations. Pinned ones are kept whatever this says, and Forever
/// never deletes anything.
enum RetentionPeriod: String, CaseIterable, Identifiable, Sendable {
    case days30, days60, days90, forever

    static let key = "historyRetention"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .days30: 30
        case .days60: 60
        case .days90: 90
        case .forever: nil
        }
    }

    var title: String {
        days.map { "\($0) days" } ?? "Forever"
    }

    var note: String {
        self == .forever
            ? "Kept on this Mac until you delete it. Pinned items are never removed."
            : "Stored only on this Mac. Older items are removed; pinned items stay."
    }
}

/// Prunes History on this Mac's SQLite file, and nowhere else.
enum HistoryRetention {
    /// The saved period. The first time it is read it is decided once and saved: an install
    /// that already has history keeps everything (nothing it has is deleted without being
    /// asked), and a new install keeps 90 days.
    static func period(in defaults: UserDefaults = .standard, queue: DatabaseQueue?) -> RetentionPeriod {
        if let saved = defaults.string(forKey: RetentionPeriod.key).flatMap(RetentionPeriod.init(rawValue:)) {
            return saved
        }
        let existing = (try? queue?.read { try DictationRecord.fetchCount($0) }) ?? 0
        let chosen: RetentionPeriod = existing > 0 ? .forever : .days90
        defaults.set(chosen.rawValue, forKey: RetentionPeriod.key)
        Log.db.info("History retention set to \(chosen.rawValue, privacy: .public) (\(existing, privacy: .public) rows already kept)")
        return chosen
    }

    /// Rows created before this are older than the period. Nil for Forever.
    static func cutoff(for period: RetentionPeriod, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        period.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }
    }

    /// How many rows a period would remove now: unpinned and older than its cutoff.
    static func count(removedBy period: RetentionPeriod, now: Date = Date(), in queue: DatabaseQueue) throws -> Int {
        guard let cutoff = cutoff(for: period, now: now) else { return 0 }
        return try queue.read { db in
            try DictationRecord.filter(Column("pinned") == false && Column("createdAt") < cutoff).fetchCount(db)
        }
    }

    /// Deletes what the period no longer keeps, timings included. Returns how many went.
    @discardableResult
    static func prune(_ period: RetentionPeriod, now: Date = Date(), in queue: DatabaseQueue) throws -> Int {
        guard let cutoff = cutoff(for: period, now: now) else { return 0 }
        let removed = try queue.write { db in
            try DictationRecord.filter(Column("pinned") == false && Column("createdAt") < cutoff).deleteAll(db)
        }
        if removed > 0 { Log.db.info("Pruned \(removed, privacy: .public) history rows older than \(period.title, privacy: .public)") }
        return removed
    }

    /// "This removes 212 items older than 30 days."
    static func confirmation(count: Int, period: RetentionPeriod) -> String {
        "This removes \(count.formatted()) \(count == 1 ? "item" : "items") older than \(period.title). Pinned items stay."
    }

    /// The history file's size on disk, write-ahead log included, so Forever is honest about it.
    static func databaseSize(at url: URL?) -> String? {
        guard let url else { return nil }
        let paths = [url.path, url.path + "-wal", url.path + "-shm"]
        let bytes = paths.compactMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? Int64 }.reduce(0, +)
        guard bytes > 0 else { return nil }
        return "History uses \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) on this Mac."
    }
}

/// Prunes at launch and once a day after that.
@MainActor
final class HistoryPruner {
    private var timer: Timer?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start() {
        runOnce()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runOnce() }
        }
    }

    func runOnce() {
        guard let queue = Database.queue else { return }
        let period = HistoryRetention.period(in: defaults, queue: queue)
        do {
            try HistoryRetention.prune(period, in: queue)
        } catch {
            Log.db.error("History prune failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
