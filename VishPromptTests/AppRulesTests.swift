import XCTest
@testable import VishPrompt

/// Step 0, part 4: Settings lists the apps dictated into, each with its own writing rule, which
/// reaches the prompt for that app and falls back to the family's.
@MainActor
final class AppRulesTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "AppRulesTests-\(UUID())")!
    }

    func testARuleIsSavedTrimmedAndEmptyRemovesIt() {
        let rules = AppRules(defaults: defaults())
        rules.set("  no greetings, lowercase is fine  ", for: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(rules.rule(for: "com.tinyspeck.slackmacgap"), "no greetings, lowercase is fine")
        XCTAssertNil(rules.rule(for: "claude.ai"))
        XCTAssertNil(rules.rule(for: nil))
        rules.set("   ", for: "com.tinyspeck.slackmacgap")
        XCTAssertNil(rules.rule(for: "com.tinyspeck.slackmacgap"), "blank removes it")
        XCTAssertTrue(rules.all().isEmpty)
    }

    func testAnAppsRuleReplacesTheFamilysAndNothingElse() {
        let store = defaults()
        DestinationSettings(defaults: store).setOverride(DestinationOverride(instructions: "short lines"), for: "message")
        let family = DestinationSettings(defaults: store).apply(to: .message)
        XCTAssertEqual(family.instructions, "short lines")
        let rules = AppRules(defaults: store)
        let slack = AppIdentity(bundleID: "com.tinyspeck.slackmacgap", host: nil)
        XCTAssertEqual(rules.apply(to: family, for: slack).instructions, "short lines", "no rule of its own: the family's")
        rules.set("no greetings", for: "com.tinyspeck.slackmacgap")
        let applied = rules.apply(to: family, for: slack)
        XCTAssertEqual(applied.instructions, "no greetings")
        XCTAssertEqual(applied.id, family.id)
        XCTAssertEqual(applied.defaultLevel, family.defaultLevel)
        XCTAssertEqual(applied.strategy, family.strategy)
        XCTAssertEqual(rules.apply(to: family, for: AppIdentity(bundleID: "com.apple.MobileSMS", host: nil)).instructions, "short lines", "Messages keeps the family's")
    }

    func testTheRuleReachesTheRewriteAndTheSmartPaste() {
        let store = defaults()
        AppRules(defaults: store).set("no greetings", for: "claude.ai")
        let destination = AppRules(defaults: store).apply(to: .chat, for: AppIdentity(bundleID: "com.google.Chrome", host: "claude.ai"))
        let message = SystemPrompt.userMessage(for: CompileRequest(transcript: "hi there", level: .medium, destination: destination.id,
                                                                    instructions: destination.instructions, vocabulary: []))
        XCTAssertTrue(message.contains("<instructions>no greetings</instructions>"), message)
        let paste = SystemPrompt.pasteMessage(clip: "text", instruction: "shorter", destination: destination.id,
                                              destinationInstructions: destination.instructions, vocabulary: [])
        XCTAssertTrue(paste.contains("<destination_instructions>no greetings</destination_instructions>"), paste)
        let without = SystemPrompt.userMessage(for: CompileRequest(transcript: "hi there", level: .medium, destination: "chat", instructions: nil, vocabulary: []))
        XCTAssertFalse(without.contains("<instructions>"))
    }

    // MARK: The card's data

    private func seeded(now: Date) throws -> HomeLibrary {
        let queue = try HomeSnapshot.sampleQueue(now: now)
        try queue.write { db in
            for (i, key) in ["com.tinyspeck.slackmacgap", "com.tinyspeck.slackmacgap", "com.tinyspeck.slackmacgap", "claude.ai", "claude.ai"].enumerated() {
                var r = DictationRecord(id: "s\(i)", createdAt: now.addingTimeInterval(-Double(i) * 60), destination: key == "claude.ai" ? "chat" : "message",
                                        level: "light", rawTranscript: "x", compiledText: "y", requestJSON: nil, status: .inserted, provider: "local",
                                        app: key == "claude.ai" ? "Google Chrome" : "Slack")
                r.bundleId = key == "claude.ai" ? "com.google.Chrome" : key
                r.urlHost = key == "claude.ai" ? "claude.ai" : nil
                try r.insert(db)
            }
        }
        let library = HomeLibrary(queue: { queue }, defaults: defaults())
        library.page = .settings
        library.reload()
        return library
    }

    func testTheAppsDictatedIntoAreListedMostUsedFirstWithTheirFamilies() throws {
        let library = try seeded(now: HomeSnapshot.morning)
        let apps = library.dictatedApps
        XCTAssertEqual(apps.map(\.name), ["Slack", "claude.ai"], "the sample rows have no identity and are left out")
        XCTAssertEqual(apps.map(\.family), ["message", "chat"])
        XCTAssertEqual(apps.first?.count, 3)
        XCTAssertEqual(library.appRule(for: "claude.ai"), "")
        library.setAppRule("ask for a plan first", for: "claude.ai")
        XCTAssertEqual(library.appRule(for: "claude.ai"), "ask for a plan first")
        XCTAssertEqual(AppRules(defaults: library.libraryDefaults).rule(for: "claude.ai"), "ask for a plan first", "saved where the run reads it")
        XCTAssertNil(library.familyRule(for: "chat"))
        DestinationSettings(defaults: library.libraryDefaults).setOverride(DestinationOverride(instructions: "short"), for: "message")
        XCTAssertEqual(library.familyRule(for: "message"), "short")
    }

    func testTheCardRendersInBothThemes() throws {
        let size = CGSize(width: 1120, height: 1500)
        for dark in [false, true] {
            let library = try seeded(now: HomeSnapshot.morning)
            library.palmRestAvailable = true
            library.setAppRule("no greetings, lowercase is fine", for: "com.tinyspeck.slackmacgap")
            DestinationSettings(defaults: library.libraryDefaults).setOverride(DestinationOverride(instructions: "one clear ask"), for: "chat")
            let bitmap = try XCTUnwrap(HomeSnapshot.capture(HomeView(library: library, reuse: HistoryReuse()), size: size, dark: dark, name: "settings-rules"))
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 8, y: 700, viewSize: size), dark ? HomeTheme.dark.sidebar : HomeTheme.light.sidebar))
        }
    }
}
