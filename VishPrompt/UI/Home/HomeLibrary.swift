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

    /// Today's most recent dictations, for Home.
    func recentToday(limit: Int = 4, now: Date = Date(), calendar: Calendar = .current) -> [HistoryEntry] {
        Array(entries.filter { calendar.isDate($0.record.createdAt, inSameDayAs: now) }.prefix(limit))
    }

    func reload() {
        guard let queue = queue() else {
            loadError = "History isn't open yet. It opens once VishPrompt has started."
            return
        }
        do {
            entries = try HistoryStore.recent(in: queue, limit: 2000)
            loadError = nil
        } catch {
            loadError = "History couldn't be read. Close this window and open it again."
            Log.db.error("Home read failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
