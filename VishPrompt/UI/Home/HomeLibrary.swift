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
    var page: HomePage = .home {
        // Leaving Settings ends a tap test or calibration, so taps go back to doing their job.
        didSet { if page != .settings { leavePalmRest() } }
    }

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

    // MARK: Settings

    /// Whether this Mac has the palm-rest sensor. Without it the switch says so and is off.
    var palmRestAvailable = false
    var palmRestEnabled = false {
        didSet {
            guard palmRestEnabled != oldValue else { return }
            onSetPalmRest(palmRestEnabled)
            if !palmRestEnabled { leavePalmRest() }
        }
    }
    @ObservationIgnored var onSetPalmRest: (Bool) -> Void = { _ in }

    /// How a hands-free session ends, and after how long a pause. Read by the controller at the
    /// next key-down, so no wiring is needed.
    var handsFreeStopMode: HandsFreeStopMode {
        didSet { HandsFreeSettings(defaults: defaults).mode = handsFreeStopMode }
    }
    var handsFreePause: HandsFreePause {
        didSet { HandsFreeSettings(defaults: defaults).pause = handsFreePause }
    }
    var tapStartSound: Bool {
        didSet { HandsFreeSettings(defaults: defaults).tapStartSound = tapStartSound }
    }

    // MARK: Writing rules per app

    /// An app or site dictated into, with the family its text is shaped for.
    struct DictatedApp: Identifiable, Equatable {
        var key: String
        var name: String
        var family: String
        var count: Int
        var id: String { key }
    }

    /// The apps and sites with an identity on their rows, most used first.
    var dictatedApps: [DictatedApp] {
        var byKey: [String: DictatedApp] = [:]
        for entry in entries {
            guard let key = entry.record.identity.key else { continue }
            if var app = byKey[key] {
                app.count += 1
                byKey[key] = app
            } else {
                byKey[key] = DictatedApp(key: key, name: HistoryFormat.appName(entry.record), family: entry.record.destination, count: 1)
            }
        }
        return byKey.values.sorted { ($0.count, $0.name) > ($1.count, $1.name) }
    }

    private(set) var appRulesVersion = 0

    func appRule(for key: String) -> String {
        _ = appRulesVersion
        return AppRules(defaults: defaults).all()[key] ?? ""
    }

    func setAppRule(_ text: String, for key: String) {
        AppRules(defaults: defaults).set(text, for: key)
        appRulesVersion += 1
    }

    /// The family's own rule, which an app without one falls back to.
    func familyRule(for family: String) -> String? {
        let base = Destination.all.first { $0.id == family } ?? .document
        return DestinationSettings(defaults: defaults).apply(to: base).instructions?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shown on Home once, after a saved trigger had to be replaced at launch.
    var triggerNote: String?
    @ObservationIgnored var onDismissTriggerNote: () -> Void = {}
    /// What macOS does with fn that competes with it as the trigger, or nil.
    var fnHint: String?
    @ObservationIgnored var onOpenKeyboardSettings: () -> Void = {}

    // MARK: Palm-rest gestures

    var palmSensitivity: PalmSensitivity {
        didSet {
            guard palmSensitivity != oldValue else { return }
            palmSensitivity.save(in: defaults)
            onPalmGesturesChanged()
        }
    }
    /// Called when a gesture's action or the sensitivity changes, so the sensor picks it up.
    @ObservationIgnored var onPalmGesturesChanged: () -> Void = {}
    /// Bumped when an action changes, so views that read the settings redraw.
    private(set) var palmGesturesVersion = 0

    func palmAction(for gesture: PalmGesture) -> PalmAction {
        _ = palmGesturesVersion
        return PalmGestureSettings(defaults: defaults).action(for: gesture)
    }

    func setPalmAction(_ action: PalmAction, for gesture: PalmGesture) {
        PalmGestureSettings(defaults: defaults).set(action, for: gesture)
        palmGesturesVersion += 1
        onPalmGesturesChanged()
    }

    /// The saved calibration for this Mac, if any.
    var sideCalibration: SideCalibration?

    /// The rows the card shows: left and right only once a calibration told them apart.
    var visiblePalmGestures: [PalmGesture] {
        sideCalibration?.unlocked == true ? [.doubleLeft, .doubleRight, .triple] : [.double, .triple]
    }

    var palmCalibrationStatus: String {
        sideCalibration?.statusText ?? SideCalibration.notCalibrated
    }

    // The Test area: gestures light up here and run nothing.
    private(set) var palmTesting = false
    private(set) var palmHeard: PalmTestResult?
    @ObservationIgnored var onSetPalmTesting: (Bool) -> Void = { _ in }
    @ObservationIgnored private var heardGeneration = 0

    func startPalmTest() {
        cancelCalibration()
        palmHeard = nil
        palmTesting = true
        onSetPalmTesting(true)
    }

    func stopPalmTest() {
        guard palmTesting else { return }
        palmTesting = false
        palmHeard = nil
        onSetPalmTesting(false)
    }

    func palmTestHeard(_ result: PalmTestResult) {
        palmHeard = result
        heardGeneration += 1
        let generation = heardGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, heardGeneration == generation else { return }
            palmHeard = nil
        }
    }

    // A calibration run.
    private(set) var calibrationRun: SideCalibrationRun?
    /// What the last run concluded, shown until the next one starts.
    private(set) var calibrationNote: String?
    @ObservationIgnored var onSetCalibrating: (Bool) -> Void = { _ in }

    func startCalibration() {
        stopPalmTest()
        calibrationNote = nil
        calibrationRun = SideCalibrationRun()
        onSetCalibrating(true)
    }

    func cancelCalibration() {
        guard calibrationRun != nil else { return }
        calibrationRun = nil
        onSetCalibrating(false)
    }

    /// One double tap's knocks during a run. When both sides are in, the result is saved either
    /// way: a failed run is the truth about this surface.
    func calibrationHeard(_ shapes: [KnockShape], model: String = SideCalibration.hardwareModel, date: Date = Date()) {
        guard var run = calibrationRun else { return }
        let result = run.add(shapes, model: model, date: date)
        calibrationRun = run
        guard run.phase == .done else { return }
        calibrationRun = nil
        onSetCalibrating(false)
        guard let result else {
            calibrationNote = "Too few taps were heard to judge. Try again, tapping firmly."
            return
        }
        applyCalibration(result)
    }

    /// On a first unlock, both side rows start with what the either-side row did, so a working
    /// gesture is not lost.
    func applyCalibration(_ result: SideCalibration) {
        result.save(in: defaults)
        let wasUnlocked = sideCalibration?.unlocked == true
        sideCalibration = result
        calibrationNote = result.statusText
        if result.unlocked, !wasUnlocked {
            let settings = PalmGestureSettings(defaults: defaults)
            if settings.action(for: .doubleLeft) == .off, settings.action(for: .doubleRight) == .off {
                let either = settings.action(for: .double)
                settings.set(either, for: .doubleLeft)
                settings.set(either, for: .doubleRight)
            }
            palmGesturesVersion += 1
        }
        onPalmGesturesChanged()
    }

    /// Ends a test or a calibration, so taps go back to running their actions.
    func leavePalmRest() {
        stopPalmTest()
        cancelCalibration()
    }

    var providerPolicy: ProviderPolicy {
        didSet { ProviderSettings(defaults: defaults).save(providerPolicy) }
    }
    /// Whether an Anthropic key is saved, so the API row can say what it needs.
    var hasAPIKey = false

    // MARK: Retention

    /// Read lazily: the first read decides the default for this install.
    var retention: RetentionPeriod = .forever
    /// A shorter period waiting for the user to confirm the real count it removes.
    private(set) var pendingRetention: (period: RetentionPeriod, count: Int)?
    private(set) var databaseSize: String?

    func refreshRetention(fileURL: URL? = Database.fileURL) {
        retention = HistoryRetention.period(in: defaults, queue: queue())
        databaseSize = HistoryRetention.databaseSize(at: fileURL)
    }

    /// A longer period, or one that removes nothing, applies at once; one that would remove
    /// something waits for confirmation with the real count.
    func requestRetention(_ period: RetentionPeriod, now: Date = Date()) {
        guard period != retention else { return }
        let count = queue().flatMap { try? HistoryRetention.count(removedBy: period, now: now, in: $0) } ?? 0
        if count > 0 {
            pendingRetention = (period, count)
        } else {
            applyRetention(period, now: now)
        }
    }

    func confirmRetention(now: Date = Date()) {
        guard let pending = pendingRetention else { return }
        pendingRetention = nil
        applyRetention(pending.period, now: now)
    }

    func cancelRetention() {
        pendingRetention = nil
    }

    private func applyRetention(_ period: RetentionPeriod, now: Date) {
        defaults.set(period.rawValue, forKey: RetentionPeriod.key)
        retention = period
        if let queue = queue() {
            do {
                try HistoryRetention.prune(period, now: now, in: queue)
            } catch {
                loadError = "Older history couldn't be removed. It's still on this Mac; try again."
                Log.db.error("Retention prune failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        reload()
        databaseSize = HistoryRetention.databaseSize(at: Database.fileURL)
    }

    func chooseRewrite(_ choice: ProviderChoice) {
        providerPolicy = RewriteChoice.policy(selecting: choice, from: providerPolicy)
    }

    @ObservationIgnored var onAppearanceChange: (AppearanceChoice) -> Void = { _ in }
    @ObservationIgnored var onShowMoreSettings: () -> Void = {}

    @ObservationIgnored private let queue: () -> DatabaseQueue?
    @ObservationIgnored private let defaults: UserDefaults
    /// The same defaults, for the extensions in this file.
    var libraryDefaults: UserDefaults { defaults }

    init(queue: @escaping () -> DatabaseQueue? = { Database.queue }, defaults: UserDefaults = .standard) {
        self.queue = queue
        self.defaults = defaults
        appearance = AppearanceChoice.saved(in: defaults)
        palmSensitivity = PalmSensitivity.saved(in: defaults)
        handsFreeStopMode = HandsFreeSettings(defaults: defaults).mode
        handsFreePause = HandsFreeSettings(defaults: defaults).pause
        tapStartSound = HandsFreeSettings(defaults: defaults).tapStartSound
        sideCalibration = SideCalibration.saved(in: defaults)
        providerPolicy = ProviderSettings(defaults: defaults).policy()
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

/// Settings → "Where the rewrite runs": one choice over the provider policy's two paths.
/// The row picks where prompts are compiled; "On this Mac" keeps quick cleanup there too, so
/// nothing leaves at all.
enum RewriteChoice {
    static let options: [ProviderChoice] = [.local, .subscription, .apiKey]

    static func selected(in policy: ProviderPolicy) -> ProviderChoice {
        policy.compilePath
    }

    static func policy(selecting choice: ProviderChoice, from policy: ProviderPolicy) -> ProviderPolicy {
        choice == .local ? .offline : ProviderPolicy(fastPath: policy.fastPath, compilePath: choice)
    }

    static func title(_ choice: ProviderChoice) -> String {
        switch choice {
        case .local: "On this Mac"
        case .subscription: "Your Claude subscription"
        case .apiKey: "Anthropic API key"
        }
    }

    static func note(_ choice: ProviderChoice, hasKey: Bool) -> String {
        switch choice {
        case .local: "Instant and free. Cleans up fillers and punctuation."
        case .subscription: "Best rewrites. Included in your plan."
        case .apiKey: hasKey ? "Fastest model rewrite. About $0.002 a dictation." : "Fastest model rewrite. Add your key in More settings first."
        }
    }

    /// "What can leave this Mac" → your words.
    static func wordsLeave(_ policy: ProviderPolicy) -> String {
        policy.fastPath == .local && policy.compilePath == .local ? "Nothing leaves" : "Only when a rewrite needs it"
    }
}

/// "How each app is going": per app, the dictations in the last seven days and the share
/// accepted as-is. Real rows only; an app with fewer than ten is not shown, because a share of
/// three is not a share.
struct AppWeekStats: Equatable, Sendable, Identifiable {
    var key: String
    var name: String
    var dictations: Int
    var acceptedAsIs: Int

    var id: String { key }

    /// The share, as a whole percent, or nil when there is nothing to divide by.
    var acceptedShare: Int? {
        dictations > 0 ? Int((Double(acceptedAsIs) / Double(dictations) * 100).rounded()) : nil
    }

    static let minimumDictations = 10
    static let days = 7

    /// Grouped by the app or site (`AppIdentity.key`); rows from before identities were stored
    /// group by the app's name. Newest-heavy first.
    static func compute(_ records: [DictationRecord], now: Date = Date(), calendar: Calendar = .current) -> [AppWeekStats] {
        guard let since = calendar.date(byAdding: .day, value: -days, to: now) else { return [] }
        var byKey: [String: AppWeekStats] = [:]
        for record in records where record.createdAt >= since && record.createdAt <= now {
            guard let key = record.identity.key ?? record.app ?? Optional(record.destination) else { continue }
            var stats = byKey[key] ?? AppWeekStats(key: key, name: HistoryFormat.appName(record), dictations: 0, acceptedAsIs: 0)
            stats.dictations += 1
            if record.acceptedAsIs { stats.acceptedAsIs += 1 }
            byKey[key] = stats
        }
        return byKey.values
            .filter { $0.dictations >= minimumDictations }
            .sorted { ($0.dictations, $0.name) > ($1.dictations, $1.name) }
    }
}

extension HomeLibrary {
    func appStats(now: Date = Date()) -> [AppWeekStats] {
        AppWeekStats.compute(entries.map(\.record), now: now)
    }

    /// Short Escape cancels in the last seven days: dictations abandoned before they were worth
    /// keeping. Shown beside the apps so the week is not flattered.
    func shortCancelsThisWeek(now: Date = Date()) -> Int {
        ShortCancelCounter(defaults: libraryDefaults).lastWeek(ending: now)
    }
}
