import XCTest
@testable import VishPrompt

/// Home 3: Dictionary shows the words VishPrompt spells your way; Settings is cards wired to the
/// real trigger, palm-rest, provider and appearance settings.
@MainActor
final class SettingsCardTests: XCTestCase {
    private let size = CGSize(width: 1120, height: 760)

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsCardTests-\(UUID())")!
    }

    func testTheRewriteRowsSetTheRealProviderPolicy() {
        let store = defaults()
        let library = HomeLibrary(queue: { nil }, defaults: store)
        XCTAssertEqual(RewriteChoice.selected(in: library.providerPolicy), .subscription, "the shipped default")

        library.chooseRewrite(.local)
        XCTAssertEqual(ProviderSettings(defaults: store).policy(), .offline, "On this Mac keeps quick cleanup local too")
        library.chooseRewrite(.apiKey)
        XCTAssertEqual(ProviderSettings(defaults: store).policy(), ProviderPolicy(fastPath: .local, compilePath: .apiKey))
        library.chooseRewrite(.subscription)
        XCTAssertEqual(ProviderSettings(defaults: store).policy(), .default)
        XCTAssertEqual(RewriteChoice.options.map(RewriteChoice.title), ["On this Mac", "Your Claude subscription", "Anthropic API key"])
    }

    func testAFastPathTheUserSetElsewhereIsKept() {
        XCTAssertEqual(RewriteChoice.policy(selecting: .subscription, from: .allAPI),
                       ProviderPolicy(fastPath: .apiKey, compilePath: .subscription))
    }

    func testWhatCanLeaveIsSaidFromThePolicy() {
        XCTAssertEqual(RewriteChoice.wordsLeave(.offline), "Nothing leaves")
        XCTAssertEqual(RewriteChoice.wordsLeave(.default), "Only when a rewrite needs it")
        XCTAssertEqual(RewriteChoice.wordsLeave(ProviderPolicy(fastPath: .apiKey, compilePath: .local)), "Only when a rewrite needs it")
    }

    func testTheAPIRowSaysWhatItNeedsWithoutAKey() {
        XCTAssertTrue(RewriteChoice.note(.apiKey, hasKey: false).contains("Add your key"))
        XCTAssertFalse(RewriteChoice.note(.apiKey, hasKey: true).contains("Add your key"))
    }

    func testThePalmRestSwitchDrivesTheRealSetting() {
        let library = HomeLibrary(queue: { nil }, defaults: defaults())
        var set: [Bool] = []
        library.onSetPalmRest = { set.append($0) }
        library.palmRestEnabled = true
        library.palmRestEnabled = true
        library.palmRestEnabled = false
        XCTAssertEqual(set, [true, false], "once per change")
    }

    func testSettingsRendersInBothThemesWithAndWithoutThePalmRest() throws {
        for dark in [false, true] {
            let library = HomeLibrary(queue: { nil }, defaults: defaults())
            library.page = .settings
            library.palmRestAvailable = !dark
            library.palmRestEnabled = !dark
            let bitmap = try XCTUnwrap(HomeSnapshot.capture(HomeView(library: library, reuse: HistoryReuse()), size: size, dark: dark, name: "settings"))
            let theme = dark ? HomeTheme.dark : HomeTheme.light
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 1100, y: 740, viewSize: size), theme.background))
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 8, y: 400, viewSize: size), theme.sidebar))
        }
    }

    func testDictionaryShowsTheRepoWordsOrSaysThereAreNone() throws {
        for dark in [false, true] {
            let library = HomeLibrary(queue: { nil }, defaults: defaults())
            library.page = .dictionary
            library.dictionaryWords = dark ? [] : ["VishPrompt", "FluidAudio", "Parakeet", "HotkeyGesture"]
            let bitmap = try XCTUnwrap(HomeSnapshot.capture(HomeView(library: library, reuse: HistoryReuse()), size: size, dark: dark, name: "dictionary"))
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 1100, y: 740, viewSize: size), dark ? HomeTheme.dark.background : HomeTheme.light.background))
        }
    }
}
