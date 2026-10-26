import XCTest
@testable import VishPrompt

/// A hands-free session ends the way Settings says: after a pause of the chosen length, or only
/// when you tap again, whatever started it. The five-minute ceiling holds either way.
final class HandsFreeStopTests: XCTestCase {
    private func settings() -> HandsFreeSettings {
        HandsFreeSettings(defaults: UserDefaults(suiteName: "HandsFreeStopTests-\(UUID())")!)
    }

    func testTheDefaultIsWhatTheAppAlwaysDid() {
        let s = settings()
        XCTAssertEqual(s.mode, .whenIStopTalking)
        XCTAssertEqual(s.pause, .short)
        XCTAssertEqual(s.silenceLimit, 1.2)
    }

    func testChoicesAreSavedAndTapAgainHasNoSilenceStop() {
        let defaults = UserDefaults(suiteName: "HandsFreeStopTests-\(UUID())")!
        let s = HandsFreeSettings(defaults: defaults)
        s.pause = .long
        XCTAssertEqual(HandsFreeSettings(defaults: defaults).silenceLimit, 5)
        s.mode = .whenITapAgain
        XCTAssertNil(HandsFreeSettings(defaults: defaults).silenceLimit, "no silence stop at all")
        s.mode = .whenIStopTalking
        XCTAssertEqual(HandsFreeSettings(defaults: defaults).pause, .long, "the pause is remembered across a switch")
        XCTAssertEqual(HandsFreePause.allCases.map(\.title), ["1.2 s", "3 s", "5 s"])
        XCTAssertEqual(HandsFreeStopMode.allCases.map(\.title), ["When I stop talking", "When I tap again"])
    }

    func testThePauseLengthIsHonoured() {
        XCTAssertFalse(HandsFreeSettings.shouldStop(locked: true, silenceSeconds: 1.1, limit: 1.2))
        XCTAssertTrue(HandsFreeSettings.shouldStop(locked: true, silenceSeconds: 1.2, limit: 1.2))
        XCTAssertFalse(HandsFreeSettings.shouldStop(locked: true, silenceSeconds: 2.9, limit: 3))
        XCTAssertTrue(HandsFreeSettings.shouldStop(locked: true, silenceSeconds: 5.1, limit: 5))
        XCTAssertFalse(HandsFreeSettings.shouldStop(locked: true, silenceSeconds: 60, limit: nil), "tap again: a minute of quiet changes nothing")
        XCTAssertFalse(HandsFreeSettings.shouldStop(locked: false, silenceSeconds: 10, limit: 1.2), "a held key never stops for silence")
    }

    // MARK: Both modes, from each start

    private func fnDoubleTap(_ g: inout HotkeyGesture) {
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.1, modifiers: .none))
        _ = g.handle(.triggerDown(at: 0.3, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.4, modifiers: .none)), .lockedOn)
    }

    func testWhenIStopTalkingEndsOnSilenceFromEitherStart() {
        var fromKey = HotkeyGesture()
        fnDoubleTap(&fromKey)
        XCTAssertEqual(fromKey.handle(.silenceTimeout), .finishCapture(modifiers: .none, locked: true))
        var fromTap = HotkeyGesture()
        _ = fromTap.chassisTap(at: 1)
        XCTAssertEqual(fromTap.handle(.silenceTimeout), .finishCapture(modifiers: .none, locked: true))
    }

    func testWhenITapAgainEndsOnlyOnATapTheTriggerOrEscape() {
        // In this mode the controller never sends silenceTimeout; each of these still ends it.
        var byTap = HotkeyGesture()
        _ = byTap.chassisTap(at: 1)
        XCTAssertEqual(byTap.chassisTap(at: 40), [.finishCapture(modifiers: .none, locked: true)])

        var byKey = HotkeyGesture()
        _ = byKey.chassisTap(at: 1)
        _ = byKey.handle(.triggerDown(at: 40, modifiers: .none))
        XCTAssertEqual(byKey.handle(.triggerUp(at: 40.1, modifiers: .none)), .finishCapture(modifiers: .none, locked: true))

        var byEscape = HotkeyGesture()
        fnDoubleTap(&byEscape)
        XCTAssertEqual(byEscape.handle(.escape), .discardCapture(reason: .escape))

        var byTapAfterKeyStart = HotkeyGesture()
        fnDoubleTap(&byTapAfterKeyStart)
        XCTAssertEqual(byTapAfterKeyStart.chassisTap(at: 40), [.finishCapture(modifiers: .none, locked: true)])
    }

    func testTheCeilingStillEndsATapAgainSession() {
        var fromTap = HotkeyGesture()
        _ = fromTap.chassisTap(at: 1)
        XCTAssertEqual(fromTap.handle(.holdTimeout(at: 301)), .finishCapture(modifiers: .none, locked: true), "a forgotten session cannot record forever")
        XCTAssertFalse(fromTap.isRecording)
        var fromKey = HotkeyGesture()
        fnDoubleTap(&fromKey)
        XCTAssertEqual(fromKey.handle(.holdTimeout(at: 301)), .finishCapture(modifiers: .none, locked: true))
    }

    // MARK: The capsule says how it ends

    func testTheCapsuleSaysHowThisSessionEnds() throws {
        let listening = HUDState.listening(level: 0.3, seconds: 2, locked: true)
        func status(tap: Bool, pause: Bool) throws -> String {
            try XCTUnwrap(CapsuleModel.make(listening, context: HUDContext(triggerName: "fn", startedByTap: tap, stopsOnPause: pause))).status
        }
        XCTAssertEqual(try status(tap: true, pause: false), "Started by a tap · double-tap again to stop · esc")
        XCTAssertEqual(try status(tap: true, pause: true), "Started by a tap · stops when you pause · esc")
        XCTAssertEqual(try status(tap: false, pause: false), "Hands-free · tap fn to stop · esc")
        XCTAssertEqual(try status(tap: false, pause: true), "Hands-free · stops when you pause · esc")
    }

    @MainActor
    func testTheSettingsCardDrivesTheRealSetting() {
        let defaults = UserDefaults(suiteName: "HandsFreeStopTests-\(UUID())")!
        let library = HomeLibrary(queue: { nil }, defaults: defaults)
        XCTAssertEqual(library.handsFreeStopMode, .whenIStopTalking)
        library.handsFreeStopMode = .whenITapAgain
        library.handsFreePause = .medium
        XCTAssertNil(HandsFreeSettings(defaults: defaults).silenceLimit)
        XCTAssertEqual(HandsFreeSettings(defaults: defaults).pause, .medium)
        XCTAssertEqual(HomeLibrary(queue: { nil }, defaults: defaults).handsFreeStopMode, .whenITapAgain, "read back on the next open")
    }
}
