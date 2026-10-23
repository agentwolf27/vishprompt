import GRDB
import XCTest
@testable import Visprflow

/// UI/UX L1: a real Settings window, a real menu, and a three-step setup.
@MainActor
final class SettingsPaneTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "visprflow.tests.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testTheFivePanesInOrder() {
        XCTAssertEqual(SettingsPane.allCases.map(\.title), ["General", "Providers", "Destinations", "Vocabulary", "Privacy"])
        XCTAssertEqual(Set(SettingsPane.allCases.map(\.icon)).count, 5)
    }

    func testTheLastPaneIsRestored() {
        let store = SettingsPaneStore(defaults: defaults)
        XCTAssertEqual(store.last, .general, "first open lands on General")
        store.remember(.privacy)
        XCTAssertEqual(SettingsPaneStore(defaults: defaults).last, .privacy)
    }

    func testSetupIsThreeSteps() {
        XCTAssertEqual(SetupStep.allCases.count, 3)
        XCTAssertEqual(SetupStep.permissions.next, .triggerKey)
        XCTAssertEqual(SetupStep.triggerKey.next, .tryIt)
        XCTAssertNil(SetupStep.tryIt.next, "the last step finishes")
        XCTAssertNil(SetupStep.permissions.previous)
        XCTAssertEqual(SetupStep.triggerKey.position, "Step 2 of 3")
    }

    func testTheMenuSaysPermissionsInWords() {
        var status = PermissionStatus()
        status.microphone = true
        XCTAssertEqual(MenuModel.permissionLines(status), ["Microphone: granted", "Accessibility: not granted"])
    }

    func testLastDictationIsTheNewestWithText() throws {
        let queue = try Database.makeQueue(path: nil)
        let older = DictationRecord(id: "a", createdAt: Date(timeIntervalSinceNow: -60), destination: "message", level: "light", rawTranscript: "x", compiledText: "older", requestJSON: nil, status: .inserted)
        let newer = DictationRecord(id: "b", createdAt: Date(), destination: "message", level: "light", rawTranscript: "y", compiledText: "newer", requestJSON: nil, status: .inserted)
        let empty = DictationRecord(id: "c", createdAt: Date(timeIntervalSinceNow: 10), destination: "message", level: "light", rawTranscript: "z", compiledText: "", requestJSON: nil, status: .failed)
        try queue.write { db in
            try older.insert(db)
            try newer.insert(db)
            try empty.insert(db)
        }
        XCTAssertEqual(try Database.lastDictationText(in: queue), "newer")
        XCTAssertNil(try Database.lastDictationText(in: try Database.makeQueue(path: nil)))
    }

    func testRevokingSmartPasteConsentAsksAgain() {
        let consent = SmartPasteConsent(defaults: defaults)
        _ = consent.requestPermission(for: .apiKey)
        XCTAssertTrue(consent.requestPermission(for: .apiKey))
        consent.revoke(.apiKey)
        XCTAssertEqual(consent.state(for: .apiKey), .never)
        XCTAssertFalse(consent.requestPermission(for: .apiKey), "after revoking, the next clip is not sent")
    }

    func testPausedIsTheStatus() {
        let state = AppState()
        state.isListening = true
        state.isPaused = true
        XCTAssertEqual(state.statusSummary, "Paused")
    }
}
