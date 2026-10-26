import XCTest
@testable import VishPrompt

/// Step 0, part 3: Home shows, per app with ten or more dictations this week, how many and the
/// share accepted as-is, from real rows only.
@MainActor
final class AppStatsTests: XCTestCase {
    private let now = HomeSnapshot.morning

    private func row(_ id: String, key: String, name: String, daysAgo: Double, accepted: Bool, status: DictationRecord.Status = .inserted) -> DictationRecord {
        var r = DictationRecord(id: id, createdAt: now.addingTimeInterval(-daysAgo * 86400), destination: "message", level: "light",
                                rawTranscript: "x", compiledText: "y", requestJSON: nil, status: status, provider: "local", app: name)
        r.bundleId = key
        r.firstAction = accepted ? "insert" : "cycleLevel"
        r.levelsTried = accepted ? "light" : "light,medium"
        return r
    }

    private func many(_ key: String, name: String, count: Int, accepted: Int, daysAgo: Double = 1) -> [DictationRecord] {
        (0..<count).map { i in row("\(key)-\(i)", key: key, name: name, daysAgo: daysAgo, accepted: i < accepted) }
    }

    func testPerAppCountsAndSharesFromTheLastSevenDays() {
        let rows = many("com.tinyspeck.slackmacgap", name: "Slack", count: 12, accepted: 9)
            + many("claude.ai", name: "claude.ai", count: 10, accepted: 10)
            + many("com.apple.MobileSMS", name: "Messages", count: 10, accepted: 2, daysAgo: 8)  // last week
        let stats = AppWeekStats.compute(rows, now: now)
        XCTAssertEqual(stats.map(\.name), ["Slack", "claude.ai"], "most used first; last week's rows don't count")
        XCTAssertEqual(stats[0].dictations, 12)
        XCTAssertEqual(stats[0].acceptedShare, 75)
        XCTAssertEqual(stats[1].acceptedShare, 100)
    }

    func testAnAppWithFewerThanTenIsNotShown() {
        let rows = many("com.apple.Notes", name: "Notes", count: 9, accepted: 9) + many("claude.ai", name: "claude.ai", count: 10, accepted: 5)
        XCTAssertEqual(AppWeekStats.compute(rows, now: now).map(\.name), ["claude.ai"])
        XCTAssertEqual(AppWeekStats.compute([], now: now), [])
    }

    func testCancelledAndUndoneRowsCountAsDictationsButNotAsAccepted() {
        var rows = many("claude.ai", name: "claude.ai", count: 10, accepted: 10)
        rows[0].status = .cancelled
        rows[1].undoWithin30s = true
        let stats = AppWeekStats.compute(rows, now: now)
        XCTAssertEqual(stats.first?.dictations, 10)
        XCTAssertEqual(stats.first?.acceptedAsIs, 8)
        XCTAssertEqual(stats.first?.acceptedShare, 80)
    }

    func testOlderRowsWithNoIdentityGroupByTheAppsName() {
        var rows = many("x", name: "Slack", count: 10, accepted: 10)
        for i in rows.indices { rows[i].bundleId = nil }
        let stats = AppWeekStats.compute(rows, now: now)
        XCTAssertEqual(stats.map(\.key), ["Slack"])
        XCTAssertEqual(stats.first?.name, "Slack")
    }

    func testTheSiteSplitsFromTheBrowser() {
        var chrome = many("com.google.Chrome", name: "Google Chrome", count: 10, accepted: 10)
        for i in 0..<5 { chrome[i].urlHost = "claude.ai" }
        for i in 5..<10 { chrome[i].urlHost = "chatgpt.com" }
        XCTAssertEqual(AppWeekStats.compute(chrome + many("com.google.Chrome", name: "Google Chrome", count: 10, accepted: 3).map { r in var r = r; r.urlHost = "claude.ai"; r.id += "b"; return r }, now: now).map(\.name), ["claude.ai"],
                       "ChatGPT has five, below the minimum; claude.ai has fifteen")
    }

    func testHomeRendersTheSectionInBothThemesAndSaysWhyWhenEmpty() throws {
        let queue = try HomeSnapshot.sampleQueue(now: now)
        try queue.write { db in
            for r in many("com.tinyspeck.slackmacgap", name: "Slack", count: 14, accepted: 11)
                + many("claude.ai", name: "claude.ai", count: 10, accepted: 7) { try r.insert(db) }
        }
        let size = CGSize(width: 1120, height: 1000)
        for dark in [false, true] {
            let defaults = UserDefaults(suiteName: "AppStatsTests-\(UUID())")!
            ShortCancelCounter(defaults: defaults).increment(on: now)
            ShortCancelCounter(defaults: defaults).increment(on: now)
            let library = HomeLibrary(queue: { dark ? nil : queue }, defaults: defaults)
            library.palmRestAvailable = true
            let bitmap = try XCTUnwrap(HomeSnapshot.capture(HomeView(library: library, reuse: HistoryReuse(), now: { [now] in now }), size: size, dark: dark, name: "home-apps"))
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 8, y: 500, viewSize: size), dark ? HomeTheme.dark.sidebar : HomeTheme.light.sidebar))
            if !dark {
                XCTAssertEqual(library.appStats(now: now).map(\.name), ["Slack", "claude.ai"])
                XCTAssertEqual(library.shortCancelsThisWeek(now: now), 2)
            }
        }
    }
}
