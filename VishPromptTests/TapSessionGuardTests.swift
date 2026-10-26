import XCTest
@testable import VishPrompt

/// Unwanted sessions 3: a tap-started session that hears nothing in its first 3 s cancels
/// silently; in "When I tap again" it still ends after 60 s without new words; a tap start
/// makes a sound unless turned off.
final class TapSessionGuardTests: XCTestCase {
    func testHearingIsReadFromTheSilenceClock() {
        XCTAssertFalse(TapSessionGuard.heardSpeech(elapsed: 2.0, silenceSeconds: 2.0), "quiet since the start")
        XCTAssertFalse(TapSessionGuard.heardSpeech(elapsed: 2.0, silenceSeconds: 1.8), "within the clock's slack")
        XCTAssertTrue(TapSessionGuard.heardSpeech(elapsed: 2.0, silenceSeconds: 0.5), "sound reset the clock")
    }

    func testAQuietTapStartIsDroppedAtThreeSecondsAndNotBefore() {
        XCTAssertEqual(TapSessionGuard.verdict(startedByTap: true, elapsed: 2.9, silenceSeconds: 2.9, heardSpeech: false, silenceLimit: nil), .keep)
        XCTAssertEqual(TapSessionGuard.verdict(startedByTap: true, elapsed: 3.0, silenceSeconds: 3.0, heardSpeech: false, silenceLimit: nil), .cancelQuietStart)
        XCTAssertEqual(TapSessionGuard.verdict(startedByTap: true, elapsed: 3.0, silenceSeconds: 3.0, heardSpeech: false, silenceLimit: 1.2), .cancelQuietStart, "in either stop mode")
        XCTAssertEqual(TapSessionGuard.verdict(startedByTap: true, elapsed: 10, silenceSeconds: 1, heardSpeech: true, silenceLimit: nil), .keep, "it heard something")
    }

    func testATapAgainSessionEndsAfterAMinuteWithoutNewWords() {
        XCTAssertEqual(TapSessionGuard.verdict(startedByTap: true, elapsed: 120, silenceSeconds: 59, heardSpeech: true, silenceLimit: nil), .keep)
        XCTAssertEqual(TapSessionGuard.verdict(startedByTap: true, elapsed: 120, silenceSeconds: 60, heardSpeech: true, silenceLimit: nil), .endIdle)
        XCTAssertEqual(TapSessionGuard.verdict(startedByTap: true, elapsed: 120, silenceSeconds: 60, heardSpeech: true, silenceLimit: 5), .keep, "with a pause length set, the ordinary silence stop ended it long before")
    }

    func testAKeyStartedSessionIsNeverTouched() {
        XCTAssertEqual(TapSessionGuard.verdict(startedByTap: false, elapsed: 10, silenceSeconds: 10, heardSpeech: false, silenceLimit: nil), .keep)
        XCTAssertEqual(TapSessionGuard.verdict(startedByTap: false, elapsed: 300, silenceSeconds: 290, heardSpeech: true, silenceLimit: nil), .keep)
    }

    func testTheGestureMachineDropsOnlyATapStartedHandsFreeSession() {
        var fromTap = HotkeyGesture()
        _ = fromTap.chassisTap(at: 1)
        XCTAssertEqual(fromTap.handle(.quietStart), .discardCapture(reason: .noSpeech))
        XCTAssertFalse(fromTap.isRecording)
        XCTAssertEqual(fromTap.chassisTap(at: 10), [.startCapture, .lockedOn], "the next tap starts clean")

        var held = HotkeyGesture()
        _ = held.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(held.handle(.quietStart), .none, "a held key is the user's hand")
        XCTAssertTrue(held.isRecording)

        var fromKey = HotkeyGesture()
        _ = fromKey.handle(.triggerDown(at: 0, modifiers: .none))
        _ = fromKey.handle(.triggerUp(at: 0.1, modifiers: .none))
        _ = fromKey.handle(.triggerDown(at: 0.3, modifiers: .none))
        _ = fromKey.handle(.triggerUp(at: 0.4, modifiers: .none))
        XCTAssertEqual(fromKey.handle(.quietStart), .none, "hands-free from the key is not a tap")
    }

    func testTheStartSoundIsOnUnlessTurnedOff() {
        let defaults = UserDefaults(suiteName: "TapSessionGuardTests-\(UUID())")!
        let settings = HandsFreeSettings(defaults: defaults)
        XCTAssertTrue(settings.tapStartSound)
        settings.tapStartSound = false
        XCTAssertFalse(HandsFreeSettings(defaults: defaults).tapStartSound)
    }

    @MainActor
    func testTheCardsSwitchDrivesTheSetting() {
        let defaults = UserDefaults(suiteName: "TapSessionGuardTests-\(UUID())")!
        let library = HomeLibrary(queue: { nil }, defaults: defaults)
        XCTAssertTrue(library.tapStartSound)
        library.tapStartSound = false
        XCTAssertFalse(HandsFreeSettings(defaults: defaults).tapStartSound)
        XCTAssertFalse(HomeLibrary(queue: { nil }, defaults: defaults).tapStartSound)
    }
}
