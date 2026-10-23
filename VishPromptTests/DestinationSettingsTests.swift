import XCTest
@testable import VishPrompt

/// UI/UX Q6: edits save as they are made and survive switching rows.
@MainActor
final class DestinationSettingsTests: XCTestCase {
    private var suiteName = ""
    private var settings: DestinationSettings!

    override func setUp() async throws {
        suiteName = "vishprompt.tests.destinations.\(UUID().uuidString)"
        settings = DestinationSettings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func testAnEditIsSavedWithoutASaveButton() {
        let editor = DestinationEditor(settings: settings, selection: "message")
        editor.update { $0.instructions = "keep it lowercase" }
        XCTAssertEqual(settings.override(for: "message")?.instructions, "keep it lowercase")
    }

    func testSwitchingRowsKeepsTheEdit() {
        let editor = DestinationEditor(settings: settings, selection: "message")
        editor.update { $0.defaultLevel = .medium }
        editor.select("email")
        XCTAssertNil(editor.current.defaultLevel, "email has its own settings")
        editor.select("message")
        XCTAssertEqual(editor.current.defaultLevel, .medium, "the message edit survived the switch")
    }

    func testANewEditorSeesSavedEdits() {
        DestinationEditor(settings: settings, selection: "claude_code").update { $0.requiresPreview = false }
        let reopened = DestinationEditor(settings: settings, selection: "claude_code")
        XCTAssertEqual(reopened.current.requiresPreview, false)
        XCTAssertFalse(settings.apply(to: .claudeCode).requiresPreview)
    }

    func testBlankInstructionsAreNotKept() {
        let editor = DestinationEditor(settings: settings, selection: "message")
        editor.update { $0.instructions = "   " }
        XCTAssertNil(settings.override(for: "message"), "an override with nothing in it is removed")
    }

    func testResetRemovesTheOverride() {
        let editor = DestinationEditor(settings: settings, selection: "message")
        editor.update { $0.strategy = .typing }
        editor.reset()
        XCTAssertNil(settings.override(for: "message"))
        XCTAssertEqual(editor.current, DestinationOverride())
    }
}
