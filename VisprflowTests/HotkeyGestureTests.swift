import XCTest
@testable import Visprflow

final class HotkeyGestureTests: XCTestCase {
    private func makeGesture(mode: HotkeyMode = .hybrid) -> HotkeyGesture {
        HotkeyGesture(config: .init(mode: mode, minimumPress: 0.3, doubleTapWindow: 0.4))
    }

    // MARK: Hold to talk

    func testHoldLongEnoughCapturesAndFinishes() {
        var g = makeGesture()
        XCTAssertEqual(g.handle(.triggerDown(at: 0, modifiers: .none)), .startCapture)
        XCTAssertTrue(g.isRecording)
        XCTAssertEqual(g.handle(.triggerUp(at: 1.2, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: false))
        XCTAssertFalse(g.isRecording)
    }

    func testShortTapIsDiscarded() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.1, modifiers: .none)),
                       .discardCapture(reason: .tooShort))
        XCTAssertFalse(g.isRecording)
    }

    func testPressExactlyAtThresholdCounts() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.3, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: false))
    }

    func testModifiersAreReportedAtRelease() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        // Shift was added after the key went down; the release is what counts.
        XCTAssertEqual(g.handle(.triggerUp(at: 1, modifiers: .shift)),
                       .finishCapture(modifiers: .shift, locked: false))
    }

    func testAutoRepeatDownsAreIgnored() {
        var g = makeGesture()
        XCTAssertEqual(g.handle(.triggerDown(at: 0, modifiers: .none)), .startCapture)
        XCTAssertEqual(g.handle(.triggerDown(at: 0.1, modifiers: .none)), .none)
        XCTAssertEqual(g.handle(.triggerDown(at: 0.2, modifiers: .none)), .none)
        XCTAssertEqual(g.handle(.triggerUp(at: 1, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: false))
    }

    func testStrayKeyUpWhenIdleDoesNothing() {
        var g = makeGesture()
        XCTAssertEqual(g.handle(.triggerUp(at: 1, modifiers: .none)), .none)
        XCTAssertFalse(g.isRecording)
    }

    // MARK: Double-tap to lock

    func testDoubleTapLocksHandsFreeAndNextPressFinishes() {
        var g = makeGesture()
        // First tap: too short, discarded, but it arms the double-tap window.
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.1, modifiers: .none)),
                       .discardCapture(reason: .tooShort))
        // Second tap inside the window: starts capture and locks on release.
        XCTAssertEqual(g.handle(.triggerDown(at: 0.3, modifiers: .none)), .startCapture)
        XCTAssertEqual(g.handle(.triggerUp(at: 0.35, modifiers: .none)), .lockedOn)
        XCTAssertTrue(g.isRecording)
        XCTAssertTrue(g.isLocked)
        // A later press ends the session on release.
        XCTAssertEqual(g.handle(.triggerDown(at: 5, modifiers: .none)), .none)
        XCTAssertTrue(g.isRecording, "still recording until the key comes back up")
        XCTAssertEqual(g.handle(.triggerUp(at: 5.05, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: true))
        XCTAssertFalse(g.isRecording)
    }

    func testSecondTapOutsideWindowIsJustAnotherHold() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.1, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerDown(at: 0.9, modifiers: .none)), .startCapture)
        XCTAssertFalse(g.isLocked)
        XCTAssertEqual(g.handle(.triggerUp(at: 2.0, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: false))
    }

    func testLongPressDoesNotArmDoubleTap() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 1.0, modifiers: .none))
        // A press right after a *long* press is a normal hold, not a lock.
        XCTAssertEqual(g.handle(.triggerDown(at: 1.1, modifiers: .none)), .startCapture)
        XCTAssertFalse(g.isLocked)
    }

    func testThreeShortTapsDoNotDoubleLock() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.1, modifiers: .none))
        _ = g.handle(.triggerDown(at: 0.2, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.25, modifiers: .none)), .lockedOn)
        // The third tap stops the locked session rather than re-locking.
        _ = g.handle(.triggerDown(at: 0.4, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.45, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: true))
        XCTAssertFalse(g.isRecording)
    }

    func testSilenceTimeoutEndsLockedSession() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.1, modifiers: .none))
        _ = g.handle(.triggerDown(at: 0.3, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.35, modifiers: .none))
        XCTAssertEqual(g.handle(.silenceTimeout), .finishCapture(modifiers: .none, locked: true))
        XCTAssertFalse(g.isRecording)
    }

    func testSilenceTimeoutIgnoredWhenNotLocked() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.silenceTimeout), .none, "holding the key means the user decides when to stop")
        XCTAssertTrue(g.isRecording)
    }

    // MARK: Cancelling

    func testEscapeCancelsWhileHolding() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.escape), .discardCapture(reason: .escape))
        XCTAssertFalse(g.isRecording)
    }

    func testEscapeCancelsWhileLocked() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.1, modifiers: .none))
        _ = g.handle(.triggerDown(at: 0.3, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.35, modifiers: .none))
        XCTAssertEqual(g.handle(.escape), .discardCapture(reason: .escape))
        XCTAssertFalse(g.isRecording)
    }

    func testEscapeWhenIdleDoesNothing() {
        var g = makeGesture()
        XCTAssertEqual(g.handle(.escape), .none)
    }

    func testEscapeClearsDoubleTapArming() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.1, modifiers: .none))  // arms the window
        _ = g.handle(.triggerDown(at: 0.2, modifiers: .none))
        _ = g.handle(.escape)
        // After a cancel, the next press is a plain hold rather than a lock.
        XCTAssertEqual(g.handle(.triggerDown(at: 0.3, modifiers: .none)), .startCapture)
        XCTAssertFalse(g.isLocked)
    }

    func testResynchroniseDiscardsInFlightGesture() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.resynchronise), .discardCapture(reason: .resynchronise))
        XCTAssertFalse(g.isRecording)
        XCTAssertEqual(g.handle(.resynchronise), .none, "nothing to discard when idle")
    }

    // MARK: Modes

    func testPushToTalkModeNeverLocks() {
        var g = makeGesture(mode: .pushToTalk)
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.1, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerDown(at: 0.2, modifiers: .none)), .startCapture)
        XCTAssertFalse(g.isLocked, "push-to-talk ignores the double-tap window")
    }

    func testToggleModeStartsAndStopsOnAlternatePresses() {
        var g = makeGesture(mode: .toggle)
        XCTAssertEqual(g.handle(.triggerDown(at: 0, modifiers: .none)), .startCapture)
        XCTAssertEqual(g.handle(.triggerUp(at: 0.05, modifiers: .none)), .lockedOn)
        XCTAssertTrue(g.isRecording, "a toggle keeps recording after the key is released")
        XCTAssertEqual(g.handle(.triggerDown(at: 3, modifiers: .none)), .none)
        XCTAssertEqual(g.handle(.triggerUp(at: 3.05, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: true))
        XCTAssertFalse(g.isRecording)
    }

    // MARK: Sequences

    func testTwoConsecutiveDictations() {
        var g = makeGesture()
        for start in [0.0, 10.0] {
            XCTAssertEqual(g.handle(.triggerDown(at: start, modifiers: .none)), .startCapture)
            XCTAssertEqual(g.handle(.triggerUp(at: start + 2, modifiers: .none)),
                           .finishCapture(modifiers: .none, locked: false))
        }
        XCTAssertFalse(g.isRecording)
    }

    // MARK: Smart Paste

    func testVSoonAfterTriggerDownConvertsTheHold() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.pasteKey(at: 0.2)), .smartPaste)
        XCTAssertTrue(g.pasteRequested)
        XCTAssertEqual(g.handle(.triggerUp(at: 2.0, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: false))
        XCTAssertFalse(g.pasteRequested, "the request belongs to one hold only")
    }

    func testQuickTapWithVFinishesInsteadOfBeingDiscarded() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.pasteKey(at: 0.05))
        // 0.15 s is under the 0.3 s minimum press that discards a bare tap.
        XCTAssertEqual(g.handle(.triggerUp(at: 0.15, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: false))
    }

    func testBareShortTapIsStillDiscarded() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.15, modifiers: .none)),
                       .discardCapture(reason: .tooShort))
    }

    func testLateVIsIgnored() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.pasteKey(at: 1.5)), .none)
        XCTAssertFalse(g.pasteRequested)
        XCTAssertEqual(g.handle(.triggerUp(at: 3, modifiers: .none)),
                       .finishCapture(modifiers: .none, locked: false))
    }

    func testVAtTheEdgeOfTheWindowCounts() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.pasteKey(at: 1.0)), .smartPaste)
    }

    func testVDuringHandsFreeIsIgnored() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.1, modifiers: .none))
        _ = g.handle(.triggerDown(at: 0.3, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.4, modifiers: .none)), .lockedOn)
        XCTAssertEqual(g.handle(.pasteKey(at: 0.6)), .none)
        XCTAssertFalse(g.pasteRequested)
    }

    func testVWhileIdleIsIgnored() {
        var g = makeGesture()
        XCTAssertEqual(g.handle(.pasteKey(at: 0)), .none)
    }

    func testSecondVChangesNothing() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.pasteKey(at: 0.1)), .smartPaste)
        XCTAssertEqual(g.handle(.pasteKey(at: 0.2)), .none)
        XCTAssertTrue(g.pasteRequested)
    }

    func testEscapeClearsTheRequest() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.pasteKey(at: 0.1))
        XCTAssertEqual(g.handle(.escape), .discardCapture(reason: .escape))
        XCTAssertFalse(g.pasteRequested)
        // The next bare tap is an ordinary accidental tap again.
        _ = g.handle(.triggerDown(at: 5, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 5.1, modifiers: .none)),
                       .discardCapture(reason: .tooShort))
    }

    // MARK: Which key presses are the paste key

    private let v = KeycodeResolver.qwertyV

    func testPlainVCountsWithFn() {
        XCTAssertTrue(HotkeyMonitor.isPasteKey(keyCode: v, flags: .maskSecondaryFn, trigger: .fn, pasteKeyCode: v))
    }

    func testVCountsWithRightOptionDespiteOptionFlag() {
        XCTAssertTrue(HotkeyMonitor.isPasteKey(keyCode: v, flags: .maskAlternate, trigger: .rightOption, pasteKeyCode: v))
    }

    func testVCountsWithRightCommandDespiteCommandFlag() {
        XCTAssertTrue(HotkeyMonitor.isPasteKey(keyCode: v, flags: .maskCommand, trigger: .rightCommand, pasteKeyCode: v))
    }

    func testShiftDoesNotBlockIt() {
        XCTAssertTrue(HotkeyMonitor.isPasteKey(keyCode: v, flags: [.maskSecondaryFn, .maskShift], trigger: .fn, pasteKeyCode: v))
    }

    func testCommandVWithFnIsAnOrdinaryPaste() {
        XCTAssertFalse(HotkeyMonitor.isPasteKey(keyCode: v, flags: [.maskSecondaryFn, .maskCommand], trigger: .fn, pasteKeyCode: v))
    }

    func testControlVWithRightOptionIsLeftAlone() {
        XCTAssertFalse(HotkeyMonitor.isPasteKey(keyCode: v, flags: [.maskAlternate, .maskControl], trigger: .rightOption, pasteKeyCode: v))
    }

    func testControlStillBlocksWithRightCommand() {
        XCTAssertFalse(HotkeyMonitor.isPasteKey(keyCode: v, flags: [.maskCommand, .maskControl], trigger: .rightCommand, pasteKeyCode: v))
    }

    func testOtherLettersAreNotThePasteKey() {
        XCTAssertFalse(HotkeyMonitor.isPasteKey(keyCode: 0x08, flags: .maskSecondaryFn, trigger: .fn, pasteKeyCode: v))
    }

    func testTheResolvedLayoutKeyIsUsed() {
        // On Dvorak "v" is a different keycode; the monitor passes whatever the layout says.
        let dvorakV: CGKeyCode = 0x2F
        XCTAssertTrue(HotkeyMonitor.isPasteKey(keyCode: dvorakV, flags: .maskSecondaryFn, trigger: .fn, pasteKeyCode: dvorakV))
        XCTAssertFalse(HotkeyMonitor.isPasteKey(keyCode: v, flags: .maskSecondaryFn, trigger: .fn, pasteKeyCode: dvorakV))
    }

    // MARK: Edit selection (R)

    func testRSoonAfterTriggerDownEditsTheSelection() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.editKey(at: 0.2)), .editSelection)
        XCTAssertEqual(g.chord, .edit)
        XCTAssertFalse(g.pasteRequested)
        XCTAssertEqual(g.handle(.triggerUp(at: 2.0, modifiers: .none)), .finishCapture(modifiers: .none, locked: false))
        XCTAssertNil(g.chord)
    }

    func testOneChordPerHold() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.pasteKey(at: 0.1)), .smartPaste)
        XCTAssertEqual(g.handle(.editKey(at: 0.2)), .none, "V then R is still a paste")
        XCTAssertEqual(g.chord, .paste)

        var h = makeGesture()
        _ = h.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(h.handle(.editKey(at: 0.1)), .editSelection)
        XCTAssertEqual(h.handle(.pasteKey(at: 0.2)), .none, "R then V is still an edit")
    }

    func testQuickTapWithRFinishes() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.editKey(at: 0.05))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.15, modifiers: .none)), .finishCapture(modifiers: .none, locked: false))
    }

    func testLateRIsIgnored() {
        var g = makeGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.editKey(at: 1.4)), .none)
    }

    func testRIsAChordKeyOnlyWithoutCommandOrControl() {
        let r = KeycodeResolver.qwertyR
        XCTAssertTrue(HotkeyMonitor.isChordKey(keyCode: r, flags: .maskSecondaryFn, trigger: .fn, chordKeyCode: r))
        XCTAssertFalse(HotkeyMonitor.isChordKey(keyCode: r, flags: [.maskSecondaryFn, .maskCommand], trigger: .fn, chordKeyCode: r))
        XCTAssertTrue(HotkeyMonitor.isChordKey(keyCode: r, flags: .maskAlternate, trigger: .rightOption, chordKeyCode: r))
    }
}
