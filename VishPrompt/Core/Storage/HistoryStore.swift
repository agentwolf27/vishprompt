import Foundation
import GRDB

/// One dictation as History shows it: the row and its stage timings.
struct HistoryEntry: Identifiable, Equatable, Sendable {
    var record: DictationRecord
    var timings: [StageTimingRecord]
    var id: String { record.id }
}

/// Reads history for the History window.
enum HistoryStore {
    /// The most recent dictations, newest first, optionally filtered by what was said or what
    /// came out.
    static func recent(in queue: DatabaseQueue, matching search: String = "", limit: Int = 200) throws -> [HistoryEntry] {
        try queue.read { db in
            var request = DictationRecord.order(Column("createdAt").desc).limit(limit)
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let pattern = "%\(query)%"
                request = request.filter(Column("rawTranscript").like(pattern) || Column("compiledText").like(pattern))
            }
            let records = try request.fetchAll(db)
            let ids = records.map(\.id)
            let timings = try StageTimingRecord
                .filter(ids.contains(Column("dictationId")))
                .order(Column("offsetMs"))
                .fetchAll(db)
            let grouped = Dictionary(grouping: timings, by: \.dictationId)
            return records.map { HistoryEntry(record: $0, timings: grouped[$0.id] ?? []) }
        }
    }
}

/// How History words things. No fake precision: durations below a second get two
/// significant figures, above a second one decimal, and nothing pretends to be a statistic.
enum HistoryFormat {
    static func duration(ms: Double) -> String {
        guard ms > 0 else { return "0 ms" }
        if ms >= 1000 { return String(format: "%.1f s", ms / 1000) }
        let magnitude = floor(log10(ms))
        let factor = pow(10, magnitude - 1)
        let rounded = (ms / factor).rounded() * factor
        if rounded >= 1000 { return String(format: "%.1f s", rounded / 1000) }
        return rounded >= 10 ? "\(Int(rounded)) ms" : String(format: "%.1f ms", rounded)
    }

    /// Where the words went, as the Privacy pane promises History will show.
    static func sentLine(_ record: DictationRecord) -> String {
        switch record.provider {
        case nil:
            "Not recorded: this dictation is from before VishPrompt kept track"
        case "local":
            "Stayed on this Mac"
        case let raw?:
            "Sent to \(ProviderChoice(rawValue: raw)?.destinationPhrase ?? raw)"
        }
    }

    /// The exact message the model received, from the stored request.
    static func sentMessage(_ record: DictationRecord) -> String? {
        guard record.provider != "local", let object = requestObject(record.requestJSON) else { return nil }
        return object["user"] as? String
    }

    static func model(_ record: DictationRecord) -> String? {
        guard record.provider != "local" else { return nil }
        return requestObject(record.requestJSON)?["model"] as? String
    }

    private static func requestObject(_ json: String?) -> [String: Any]? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func status(_ status: DictationRecord.Status) -> String {
        switch status {
        case .inserted: "Inserted"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        case .rawFallback: "Inserted as said (the rewrite failed a check)"
        }
    }

    /// The list title: the first line of what was said.
    static func title(_ record: DictationRecord) -> String {
        let first = record.rawTranscript
            .split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if first.isEmpty { return record.level.hasPrefix("paste") ? "(Smart Paste, nothing said)" : "(nothing said)" }
        return first.count > 80 ? String(first.prefix(79)) + "…" : first
    }

    /// The second line of a row: where it went, when, and what left the Mac.
    /// "→ Claude Code · 2 min ago · stayed on this Mac". An ending other than an insert is
    /// named last, so a cancelled row never reads as if it landed.
    static func rowLine(_ record: DictationRecord, now: Date = Date(), calendar: Calendar = .current) -> String {
        var parts = ["→ \(destinationName(record.destination))", when(record.createdAt, now: now, calendar: calendar), left(record)]
        if record.status != .inserted { parts.append(status(record.status).lowercased()) }
        return parts.joined(separator: " · ")
    }

    /// A destination id as the user named it in Settings, or the id itself for one since removed.
    static func destinationName(_ id: String) -> String {
        Destination.all.first(where: { $0.id == id })?.displayName ?? id
    }

    /// Roughly when, the way a person says it. Exact time is in the detail pane.
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600)) h ago" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// `sentLine`, short enough for a row.
    static func left(_ record: DictationRecord) -> String {
        switch record.provider {
        case nil: "not recorded"
        case "local": "stayed on this Mac"
        case let raw?: "sent to \(ProviderChoice(rawValue: raw)?.destinationPhrase ?? raw)"
        }
    }

    /// What Return pastes and ⌘C copies: what came out, or what was said when nothing did.
    static func reusableText(_ record: DictationRecord) -> String? {
        for text in [record.compiledText, record.rawTranscript] {
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return nil
    }

    /// History keeps a secret as "[redacted API key]", never the value, so reusing a row
    /// pastes the label. Said beside the result rather than discovered in the target app.
    static func redactionNote(_ text: String) -> String? {
        guard text.range(of: #"\[redacted [^\]\n]{1,40}\]"#, options: .regularExpression) != nil else { return nil }
        return "A secret was removed before this was saved, so it pastes as “[redacted …]”. Put the value back by hand."
    }

    /// Key-up to the last thing that happened, the figure that matters to the user.
    static func total(_ timings: [StageTimingRecord]) -> String? {
        guard let keyUp = timings.first(where: { $0.stage == Stage.keyUp.rawValue }),
              let last = timings.max(by: { $0.offsetMs < $1.offsetMs }),
              last.offsetMs > keyUp.offsetMs
        else { return nil }
        return duration(ms: last.offsetMs - keyUp.offsetMs)
    }
}

/// How a dictation was made, as the Home window's cards name it.
enum DictationMode: String, CaseIterable, Sendable {
    case dictate, smartPaste, edit, screenshotFix

    var title: String {
        switch self {
        case .dictate: "Dictate"
        case .smartPaste: "Smart paste"
        case .edit: "Edit by voice"
        case .screenshotFix: "Screenshot fix"
        }
    }

    /// The stored mode, or for rows from before it was stored, what the level says: Smart Paste
    /// and edits wrote "paste…" and "edit…" levels. An old screenshot fix reads as a dictation,
    /// because nothing in the row told them apart.
    static func of(_ record: DictationRecord) -> DictationMode {
        if let stored = record.mode.flatMap(DictationMode.init(rawValue:)) { return stored }
        if record.level.hasPrefix("edit") { return .edit }
        if record.level.hasPrefix("paste") { return .smartPaste }
        return .dictate
    }
}

/// Where the words went, as a card's pill says it.
enum WhereItWent: Equatable, Sendable {
    case stayedOnThisMac
    case sentToClaude
    /// Rows from before the provider was recorded. Said plainly rather than guessed.
    case notRecorded

    init(_ record: DictationRecord) {
        switch record.provider {
        case nil: self = .notRecorded
        case "local": self = .stayedOnThisMac
        default: self = .sentToClaude
        }
    }

    var label: String {
        switch self {
        case .stayedOnThisMac: "Stayed on this Mac"
        case .sentToClaude: "Sent to Claude"
        case .notRecorded: "Not recorded"
        }
    }
}

extension HistoryFormat {
    /// The app a card names: the app in front at the time, or for older rows, the destination.
    static func appName(_ record: DictationRecord) -> String {
        record.app ?? destinationName(record.destination)
    }

    /// Whether a row matches a History search: what came out, what was said, the app or the mode.
    static func matches(_ record: DictationRecord, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let haystack = [record.compiledText ?? "", record.rawTranscript, appName(record), DictationMode.of(record).title]
        return haystack.contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    /// "Nothing matches “x”. Try an app name, like Slack."
    static func noMatch(_ query: String) -> String {
        "Nothing matches “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”. Try an app name, like Slack."
    }

    /// History's groups: Pinned first, then Today, Yesterday and each earlier date, newest first.
    static func groups(_ entries: [HistoryEntry], now: Date = Date(), calendar: Calendar = .current) -> [(label: String, entries: [HistoryEntry])] {
        var groups: [(label: String, entries: [HistoryEntry])] = []
        let pinned = entries.filter(\.record.pinned)
        if !pinned.isEmpty { groups.append(("Pinned", pinned)) }
        for entry in entries where !entry.record.pinned {
            let label = dayLabel(entry.record.createdAt, now: now, calendar: calendar)
            if groups.last?.label == label, groups.last?.label != "Pinned" {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((label, [entry]))
            }
        }
        return groups
    }

    static func dayLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return date.formatted(sameYear ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                                       : .dateTime.day().month(.abbreviated).year())
    }
}

extension HistoryStore {
    static func setPinned(_ pinned: Bool, id: String, in queue: DatabaseQueue) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE dictation SET pinned = ? WHERE id = ?", arguments: [pinned, id])
        }
    }

    /// Deletes a row and, through the foreign key, its timings. Local SQLite only.
    static func delete(id: String, in queue: DatabaseQueue) throws {
        try queue.write { db in
            _ = try DictationRecord.deleteOne(db, key: id)
        }
    }

    /// Puts back a row deleted a moment ago, timings included, for Undo.
    static func restore(_ entry: HistoryEntry, in queue: DatabaseQueue) throws {
        try queue.write { db in
            try entry.record.insert(db)
            for var timing in entry.timings {
                timing.id = nil
                try timing.insert(db)
            }
        }
    }
}
