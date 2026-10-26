import Foundation
import GRDB

/// What happened to a dictation after it was made, recorded from what the app already sees.
/// Measurement only: nothing here changes a prompt, and nothing leaves the Mac.
enum OutcomeSignal: Equatable, Sendable {
    /// The output text was copied from a card.
    case copiedOutput(id: String)
    /// "What you said" was copied from a card.
    case copiedSaid(id: String)
    /// The output was pasted again from History.
    case pastedAgain(id: String)
    /// ⌘Z within 30 s of the insert, in the same app.
    case undo(id: String)

    var id: String {
        switch self {
        case let .copiedOutput(id), let .copiedSaid(id), let .pastedAgain(id), let .undo(id): id
        }
    }
}

/// What happened on the preview card: the first key that decided it, and every level tried.
struct PreviewSignals: Equatable, Sendable {
    /// The first of Return, Tab, ⇧Tab, R, Esc or a level number. Scrolling decides nothing.
    private(set) var firstAction: String?
    private(set) var levelsTried: [EditLevel] = []

    init(levelsTried: [EditLevel] = []) {
        self.levelsTried = levelsTried
    }

    mutating func noteKey(_ key: PreviewKey) {
        guard firstAction == nil else { return }
        switch key {
        case .scrollUp, .scrollDown: return
        case .levelVerbatim, .levelLight, .levelMedium, .levelFull: firstAction = "level"
        default: firstAction = key.rawValue
        }
    }

    mutating func noteLevel(_ level: EditLevel) {
        if !levelsTried.contains(level) { levelsTried.append(level) }
    }

    /// The levels as stored: in the order tried, comma-separated.
    func levelsText(including inserted: EditLevel) -> String {
        var levels = levelsTried
        if !levels.contains(inserted) { levels.append(inserted) }
        return levels.map(\.rawValue).joined(separator: ",")
    }
}

/// Whether a ⌘Z counts as undoing an insert: within 30 s, in the app the text went into (or an
/// app the insert could not name). The app cannot know the undo was of its paste.
enum UndoWindow {
    static let seconds: TimeInterval = 30

    static func counts(insertedAt: Date, now: Date, insertedInto bundle: String?, frontmost: String?) -> Bool {
        guard now.timeIntervalSince(insertedAt) <= seconds, now >= insertedAt else { return false }
        guard let bundle, let frontmost else { return true }
        return bundle == frontmost
    }
}

/// Short Escape cancels, which write no row: a dictation abandoned before it was worth keeping.
/// Counted per day, in the defaults, so Home can show them.
struct ShortCancelCounter: @unchecked Sendable {
    static let key = "shortCancelsByDay"
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func increment(on date: Date = Date()) {
        var counts = defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
        counts[dayKey(date), default: 0] += 1
        // Keep ninety days; older entries are no longer shown anywhere.
        if let cutoff = calendar.date(byAdding: .day, value: -90, to: date) {
            let floor = dayKey(cutoff)
            counts = counts.filter { $0.key >= floor }
        }
        defaults.set(counts, forKey: Self.key)
    }

    func count(on date: Date = Date()) -> Int {
        (defaults.dictionary(forKey: Self.key) as? [String: Int])?[dayKey(date)] ?? 0
    }

    /// The last seven days, today included.
    func lastWeek(ending date: Date = Date()) -> Int {
        let counts = defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: date) }
            .reduce(0) { $0 + (counts[dayKey($1)] ?? 0) }
    }
}

extension HistoryStore {
    /// Counts a signal on its row. Local SQLite only.
    static func bump(_ signal: OutcomeSignal, in queue: DatabaseQueue) async throws {
        let column: String
        switch signal {
        case .copiedOutput: column = "copiedOutput"
        case .copiedSaid: column = "copiedSaid"
        case .pastedAgain: column = "pastedAgain"
        case .undo:
            try await markUndo(id: signal.id, in: queue)
            return
        }
        try await queue.write { db in
            try db.execute(sql: "UPDATE dictation SET \(column) = \(column) + 1 WHERE id = ?", arguments: [signal.id])
        }
    }

    /// Marks the row as undone within 30 s. The row is written a moment after the insert, on
    /// another task, so a ⌘Z faster than that is tried once more.
    static func markUndo(id: String, in queue: DatabaseQueue) async throws {
        for attempt in 0..<2 {
            let changed = try await queue.write { db -> Int in
                try db.execute(sql: "UPDATE dictation SET undoWithin30s = 1 WHERE id = ?", arguments: [id])
                return db.changesCount
            }
            if changed > 0 || attempt == 1 { return }
            try await Task.sleep(for: .milliseconds(500))
        }
    }
}
