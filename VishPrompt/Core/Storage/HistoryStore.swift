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

    /// Key-up to the last thing that happened, the figure that matters to the user.
    static func total(_ timings: [StageTimingRecord]) -> String? {
        guard let keyUp = timings.first(where: { $0.stage == Stage.keyUp.rawValue }),
              let last = timings.max(by: { $0.offsetMs < $1.offsetMs }),
              last.offsetMs > keyUp.offsetMs
        else { return nil }
        return duration(ms: last.offsetMs - keyUp.offsetMs)
    }
}
