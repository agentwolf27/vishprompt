import AppKit
import GRDB
import Observation

/// Today's numbers on Home, from real rows only. Nothing estimated, nothing carried over.
struct HomeStats: Equatable, Sendable {
    var dictations = 0
    var words = 0
    var stayedOnThisMac = 0

    /// Counts the rows from `now`'s day that put text somewhere. A cancelled or failed
    /// dictation is in History, but it isn't something you said that landed.
    static func today(_ records: [DictationRecord], now: Date = Date(), calendar: Calendar = .current) -> HomeStats {
        var stats = HomeStats()
        for record in records where calendar.isDate(record.createdAt, inSameDayAs: now) {
            guard record.status == .inserted || record.status == .rawFallback else { continue }
            stats.dictations += 1
            stats.words += HistoryFormat.reusableText(record).map(wordCount) ?? 0
            if record.provider == "local" { stats.stayedOnThisMac += 1 }
        }
        return stats
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// "Good morning, Vish". The name is the first word of the Mac account's full name, and left
/// out when there isn't one rather than guessed.
enum HomeGreeting {
    static func text(hour: Int, fullName: String) -> String {
        let part = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
        guard let first = fullName.split(separator: " ").first, !first.isEmpty else { return part }
        return "\(part), \(first)"
    }
}

/// The sections of the Home window.
enum HomePage: String, CaseIterable, Identifiable, Sendable {
    case home, history, dictionary, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .settings: "Settings"
        }
    }
}

/// What the Home window shows, read from the local history database.
@MainActor
@Observable
final class HomeLibrary {
    private(set) var entries: [HistoryEntry] = []
    private(set) var loadError: String?
    var page: HomePage = .home

    /// The trigger's name, for the sidebar's key cap.
    var triggerName = "fn"
    /// Words VishPrompt spells your way: today, the current repo's words, read-only.
    var dictionaryWords: [String] = []
    /// Where those words came from, such as "VishPrompt on main".
    var dictionarySource: String?

    var appearance: AppearanceChoice {
        didSet {
            defaults.set(appearance.rawValue, forKey: AppearanceChoice.key)
            onAppearanceChange(appearance)
        }
    }

    @ObservationIgnored var onAppearanceChange: (AppearanceChoice) -> Void = { _ in }
    @ObservationIgnored var onShowMoreSettings: () -> Void = {}

    @ObservationIgnored private let queue: () -> DatabaseQueue?
    @ObservationIgnored private let defaults: UserDefaults

    init(queue: @escaping () -> DatabaseQueue? = { Database.queue }, defaults: UserDefaults = .standard) {
        self.queue = queue
        self.defaults = defaults
        appearance = AppearanceChoice.saved(in: defaults)
    }

    func stats(now: Date = Date()) -> HomeStats {
        HomeStats.today(entries.map(\.record), now: now)
    }

    /// Today's four most recent dictations for Home, pinned ones first.
    func recentToday(limit: Int = 4, now: Date = Date(), calendar: Calendar = .current) -> [HistoryEntry] {
        let today = entries.filter { calendar.isDate($0.record.createdAt, inSameDayAs: now) }
        return Array((today.filter(\.record.pinned) + today.filter { !$0.record.pinned }).prefix(limit))
    }

    // MARK: History

    var query = ""
    /// The card Return pastes again and ⌘C copies.
    var selection: String?
    /// A row deleted a moment ago, for Undo.
    private(set) var lastDeleted: HistoryEntry?
    /// Which cards show "What you said".
    var expanded: Set<String> = []

    /// History's cards for the current search, in groups.
    func historyGroups(now: Date = Date()) -> [(label: String, entries: [HistoryEntry])] {
        HistoryFormat.groups(entries.filter { HistoryFormat.matches($0.record, query: query) }, now: now)
    }

    /// The cards in the order they are shown, for moving the selection with the arrow keys.
    func historyOrder(now: Date = Date()) -> [String] {
        historyGroups(now: now).flatMap(\.entries).map(\.id)
    }

    func moveSelection(by step: Int, now: Date = Date()) {
        let order = historyOrder(now: now)
        guard !order.isEmpty else { return }
        guard let current = selection, let index = order.firstIndex(of: current) else {
            selection = step >= 0 ? order.first : order.last
            return
        }
        selection = order[min(max(index + step, 0), order.count - 1)]
    }

    var selectedText: String? {
        entries.first { $0.id == selection }.flatMap { HistoryFormat.reusableText($0.record) }
    }

    func setPinned(_ pinned: Bool, _ entry: HistoryEntry) {
        guard let queue = queue() else { return }
        do {
            try HistoryStore.setPinned(pinned, id: entry.id, in: queue)
            reload()
        } catch {
            loadError = "That couldn't be pinned. Try again."
            Log.db.error("Pin failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(_ entry: HistoryEntry) {
        guard let queue = queue() else { return }
        do {
            try HistoryStore.delete(id: entry.id, in: queue)
            lastDeleted = entry
            if selection == entry.id { selection = nil }
            reload()
        } catch {
            loadError = "That couldn't be deleted. Try again."
            Log.db.error("Delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func undoDelete() {
        guard let queue = queue(), let entry = lastDeleted else { return }
        do {
            try HistoryStore.restore(entry, in: queue)
            lastDeleted = nil
            reload()
        } catch {
            Log.db.error("Undo delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dismissUndo() { lastDeleted = nil }

    func reload() {
        guard let queue = queue() else {
            loadError = "History isn't open yet. It opens once VishPrompt has started."
            return
        }
        do {
            // Enough for search to cover what a person keeps; the window is not paged.
            entries = try HistoryStore.recent(in: queue, limit: 5000)
            loadError = nil
        } catch {
            loadError = "History couldn't be read. Close this window and open it again."
            Log.db.error("Home read failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
