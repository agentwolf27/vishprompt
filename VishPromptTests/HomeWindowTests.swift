import AppKit
import XCTest
@testable import VishPrompt

/// Home 1: one window with a sidebar, in a warm light and a warm dark theme that follow the Mac
/// unless Settings says otherwise.
@MainActor
final class HomeWindowTests: XCTestCase {
    private let size = CGSize(width: 1120, height: 760)

    func testTheTokensAreTheMockupsExactly() {
        XCTAssertEqual(HomeTheme.light.background.hex, 0xFAF8F5)
        XCTAssertEqual(HomeTheme.light.sidebar.hex, 0xF3F0EA)
        XCTAssertEqual(HomeTheme.light.card.hex, 0xFFFFFF)
        XCTAssertEqual(HomeTheme.light.line.hex, 0xE7E2DA)
        XCTAssertEqual(HomeTheme.light.ink.hex, 0x1C1B1A)
        XCTAssertEqual(HomeTheme.light.muted.hex, 0x6B6660)
        XCTAssertEqual(HomeTheme.dark.background.hex, 0x1A1918)
        XCTAssertEqual(HomeTheme.dark.sidebar.hex, 0x151413)
        XCTAssertEqual(HomeTheme.dark.card.hex, 0x242322)
        XCTAssertEqual(HomeTheme.dark.line.hex, 0x34322F)
        XCTAssertEqual(HomeTheme.dark.ink.hex, 0xF2F0ED)
        XCTAssertEqual(HomeTheme.dark.muted.hex, 0xA8A39C)
        XCTAssertEqual(HomeTheme.light.accent.hex, 0x4B5BDC)
        XCTAssertEqual(HomeTheme.dark.accent.hex, 0x4B5BDC, "one accent in both themes")
        for color in [HomeTheme.dark.background, HomeTheme.dark.sidebar, HomeTheme.dark.card] {
            XCTAssertNotEqual(color.hex, 0x000000, "warm charcoal, never pure black")
        }
    }

    func testAppearanceFollowsTheMacUntilChosen() {
        let defaults = UserDefaults(suiteName: "HomeWindowTests-\(UUID())")!
        XCTAssertEqual(AppearanceChoice.saved(in: defaults), .system)
        XCTAssertNil(AppearanceChoice.system.appearance)
        XCTAssertEqual(AppearanceChoice.light.appearance?.name, .aqua)
        XCTAssertEqual(AppearanceChoice.dark.appearance?.name, .darkAqua)

        let library = HomeLibrary(queue: { nil }, defaults: defaults)
        var applied: [AppearanceChoice] = []
        library.onAppearanceChange = { applied.append($0) }
        library.appearance = .dark
        XCTAssertEqual(applied, [.dark])
        XCTAssertEqual(AppearanceChoice.saved(in: defaults), .dark, "remembered")
        XCTAssertEqual(AppearanceChoice.allCases.map(\.title), ["Match the Mac", "Light", "Dark"])
    }

    func testTheWindowIsAtLeast1040By700AndCarriesTheChosenAppearance() throws {
        let defaults = UserDefaults(suiteName: "HomeWindowTests-\(UUID())")!
        let library = HomeLibrary(queue: { nil }, defaults: defaults)
        library.appearance = .dark
        let controller = HomeWindowController(library: library)
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.contentMinSize, CGSize(width: 1040, height: 700))
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        library.appearance = .light
        XCTAssertEqual(window.appearance?.name, .aqua, "switching applies at once")
        library.appearance = .system
        XCTAssertNil(window.appearance)
        XCTAssertEqual(HomePage.allCases.map(\.title), ["Home", "History", "Dictionary", "Settings"])
    }

    func testTodaysCountsComeFromRealRowsOnly() throws {
        let now = HomeSnapshot.morning
        let queue = try HomeSnapshot.sampleQueue(now: now)
        try queue.write { db in
            try DictationRecord(id: "cancelled", createdAt: now.addingTimeInterval(-60), destination: "message", level: "light",
                                rawTranscript: "never mind", compiledText: nil, requestJSON: nil, status: .cancelled, provider: "local").insert(db)
        }
        let library = HomeLibrary(queue: { queue })
        library.reload()
        let stats = library.stats(now: now)
        XCTAssertEqual(stats.dictations, 4, "four landed today; yesterday's and the cancelled one don't count")
        XCTAssertEqual(stats.stayedOnThisMac, 3)
        let words = ["a1", "a2", "a3", "a4"].compactMap { id in library.entries.first { $0.id == id } }
            .map { HomeStats.wordCount(HistoryFormat.reusableText($0.record)!) }.reduce(0, +)
        XCTAssertEqual(stats.words, words)
        XCTAssertEqual(library.recentToday(now: now).map(\.id), ["cancelled", "a1", "a2", "a3"], "newest first, four at most")
        XCTAssertEqual(HomeStats.today([], now: now), HomeStats())
    }

    func testTheGreetingNamesThePartOfDayAndTheFirstName() {
        XCTAssertEqual(HomeGreeting.text(hour: 9, fullName: "Vishrut Malhotra"), "Good morning, Vishrut")
        XCTAssertEqual(HomeGreeting.text(hour: 13, fullName: "Vish"), "Good afternoon, Vish")
        XCTAssertEqual(HomeGreeting.text(hour: 21, fullName: ""), "Good evening", "no name is better than a guess")
    }

    func testHomeRendersInBothThemesWithTheRightPaper() throws {
        let now = HomeSnapshot.morning
        let queue = try HomeSnapshot.sampleQueue(now: now)
        for dark in [false, true] {
            let library = HomeLibrary(queue: { queue }, defaults: UserDefaults(suiteName: "HomeWindowTests-\(UUID())")!)
            let view = HomeView(library: library, reuse: HistoryReuse(), now: { now })
            let bitmap = try XCTUnwrap(HomeSnapshot.capture(view, size: size, dark: dark, name: "home"))
            let theme = dark ? HomeTheme.dark : HomeTheme.light
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 1100, y: 740, viewSize: size), theme.background),
                          "\(dark ? "dark" : "light") background: \(String(describing: HomeSnapshot.pixel(bitmap, x: 1100, y: 740, viewSize: size)))")
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 8, y: 400, viewSize: size), theme.sidebar),
                          "\(dark ? "dark" : "light") sidebar: \(String(describing: HomeSnapshot.pixel(bitmap, x: 8, y: 400, viewSize: size)))")
        }
    }

    func testDictionaryAndSettingsRenderInBothThemes() throws {
        for page in [HomePage.dictionary, .settings] {
            for dark in [false, true] {
                let library = HomeLibrary(queue: { nil }, defaults: UserDefaults(suiteName: "HomeWindowTests-\(UUID())")!)
                library.page = page
                library.dictionaryWords = ["VishPrompt", "FluidAudio", "Parakeet", "Claude Code", "Neural Engine", "HotkeyGesture"]
                library.dictionarySource = "VishPrompt on dev"
                let bitmap = try XCTUnwrap(HomeSnapshot.capture(HomeView(library: library, reuse: HistoryReuse()), size: size, dark: dark, name: page.rawValue))
                let theme = dark ? HomeTheme.dark : HomeTheme.light
                XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 1100, y: 740, viewSize: size), theme.background))
            }
        }
    }
}
