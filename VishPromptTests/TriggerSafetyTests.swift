import Carbon.HIToolbox
import XCTest
@testable import VishPrompt

/// Copy and paste must never be eaten by the trigger. Vish: "cant really copy and paste text due
/// to the vishprompt hotkeys". His saved trigger was Left Command, so every ⌘C held the trigger
/// and ⌘V read as the fn+V Smart Paste gesture.
final class TriggerSafetyTests: XCTestCase {
    private func key(_ code: Int) -> TriggerKey {
        TriggerKey.recognised(keyCode: CGKeyCode(code), flags: [])
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "TriggerSafetyTests-\(UUID())")!
    }

    // MARK: Refusal and migration

    func testTheShortcutModifiersAreRefusedWithTheReasonAndTheRestAllowed() {
        for code in [kVK_Command, kVK_Option, kVK_Control, kVK_RightControl, kVK_Shift, kVK_RightShift] {
            XCTAssertNotNil(key(code).refusalReason, TriggerKey.name(for: CGKeyCode(code)))
            XCTAssertFalse(key(code).isAllowed)
        }
        XCTAssertTrue(key(kVK_Command).refusalReason?.contains("⌘C, ⌘V and ⌘Z") == true)
        for allowed in [TriggerKey.fn, .rightOption, .rightCommand, key(kVK_F13), key(kVK_F19), key(kVK_F5)] {
            XCTAssertNil(allowed.refusalReason, allowed.displayName)
        }
    }

    func testASavedLeftCommandComesBackAsFnWithANoteUntilDismissed() throws {
        let store = TriggerStore(defaults: defaults())
        store.save(key(kVK_Command))
        XCTAssertEqual(store.load(), .fn)
        let note = try XCTUnwrap(store.migrationNote)
        XCTAssertTrue(note.contains("Left Command"), note)
        XCTAssertTrue(note.contains("⌘V"), note)
        XCTAssertEqual(store.load(), .fn, "the saved value was replaced, not just ignored")
        XCTAssertNotNil(store.migrationNote, "still there on the next launch")
        store.dismissMigrationNote()
        XCTAssertNil(store.migrationNote)
    }

    func testASavedAllowedTriggerIsKeptAndNothingIsSaidAboutIt() {
        let store = TriggerStore(defaults: defaults())
        store.save(.rightCommand)
        XCTAssertEqual(store.load(), .rightCommand)
        XCTAssertNil(store.migrationNote)
        XCTAssertEqual(TriggerStore(defaults: defaults()).load(), .fn, "nothing saved: fn")
    }

    func testOnlyFnAndOrdinaryKeysTakeTheVAndRChords() {
        XCTAssertTrue(TriggerKey.fn.allowsChords, "fn+V is the Smart Paste gesture")
        XCTAssertTrue(key(kVK_F13).allowsChords)
        XCTAssertFalse(TriggerKey.rightCommand.allowsChords, "with Right Command held, V is ⌘V and must paste")
        XCTAssertFalse(TriggerKey.rightOption.allowsChords)
        XCTAssertTrue(TriggerKey.rightCommand.isShortcutModifier)
        XCTAssertFalse(TriggerKey.fn.isShortcutModifier)
        XCTAssertFalse(key(kVK_F13).isShortcutModifier)
    }

    // MARK: Shortcuts pass through

    func testAKeyRightAfterTheTriggerIsAShortcutNotADictationWhateverTheTrigger() {
        var g = HotkeyGesture()
        XCTAssertEqual(g.handle(.triggerDown(at: 0, modifiers: .none)), .startCapture)
        XCTAssertEqual(g.handle(.otherKey(at: 0.05, shortcutTrigger: false)), .discardCapture(reason: .shortcut), "fn+Delete is forward delete")
        XCTAssertFalse(g.isRecording)
        XCTAssertEqual(g.handle(.triggerUp(at: 0.1, modifiers: .none)), .none, "the release has nothing left to end")
        XCTAssertEqual(g.handle(.triggerDown(at: 0.2, modifiers: .none)), .startCapture)
        XCTAssertTrue(g.isHolding, "a shortcut never arms the hands-free double-tap")
    }

    func testWithRightCommandAnyKeyDuringTheHoldIsAShortcut() {
        var g = HotkeyGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.otherKey(at: 0.8, shortcutTrigger: true)), .discardCapture(reason: .shortcut), "⌘C long after the ⌘ went down")
        XCTAssertFalse(g.isRecording)
    }

    func testWithFnALaterKeyDoesNotCancelADictation() {
        var g = HotkeyGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.otherKey(at: 0.8, shortcutTrigger: false)), .none)
        XCTAssertEqual(g.handle(.triggerUp(at: 2, modifiers: .none)), .finishCapture(modifiers: .none, locked: false))
    }

    func testHandsFreeTypingIsLeftAlone() {
        var g = HotkeyGesture()
        _ = g.chassisTap(at: 1)
        XCTAssertTrue(g.isLocked)
        XCTAssertEqual(g.handle(.otherKey(at: 2, shortcutTrigger: true)), .none)
        XCTAssertTrue(g.isLocked)
    }

    func testFnVStillMakesASmartPasteAndIsNotCancelledByTheNextKey() {
        var g = HotkeyGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.handle(.pasteKey(at: 0.1)), .smartPaste)
        XCTAssertEqual(g.handle(.otherKey(at: 0.12, shortcutTrigger: false)), .none, "the hold is already a Smart Paste")
        XCTAssertEqual(g.handle(.triggerUp(at: 0.2, modifiers: .none)), .finishCapture(modifiers: .none, locked: false))
    }

    func testTheChordKeyCheckStillAcceptsFnVAndRejectsCommandV() {
        let v = KeycodeResolver.qwertyV
        XCTAssertTrue(HotkeyMonitor.isChordKey(keyCode: v, flags: .maskSecondaryFn, trigger: .fn, chordKeyCode: v))
        XCTAssertFalse(HotkeyMonitor.isChordKey(keyCode: v, flags: [.maskSecondaryFn, .maskCommand], trigger: .fn, chordKeyCode: v), "fn+⌘V is a shortcut")
    }

    // MARK: The Globe key's system setting

    func testTheFnHintNamesWhatMacOSDoesAndOnlyForFn() {
        let emoji = FnKeyUsage.hint(for: .showEmojiPicker, appleDictation: false, trigger: .fn)
        XCTAssertTrue(emoji?.contains("Do Nothing") == true, String(describing: emoji))
        XCTAssertNil(FnKeyUsage.hint(for: .doNothing, appleDictation: false, trigger: .fn))
        XCTAssertNil(FnKeyUsage.hint(for: .showEmojiPicker, appleDictation: false, trigger: .rightCommand), "not fn: no conflict")
        let dictation = FnKeyUsage.hint(for: .doNothing, appleDictation: true, trigger: .fn)
        XCTAssertTrue(dictation?.contains("fn twice") == true, String(describing: dictation))
    }
}
