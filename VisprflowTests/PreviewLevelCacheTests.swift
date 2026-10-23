import Carbon.HIToolbox
import XCTest
@testable import Visprflow

final class PreviewLevelCacheTests: XCTestCase {
    func testAStoredLevelComesBackWithoutRecompiling() {
        var levels = PreviewLevels()
        let full = CompiledPrompt(text: "Compiled prompt", level: .full)
        levels.store(full, requested: .full)
        XCTAssertEqual(levels.cached(.full), full)
        XCTAssertNil(levels.cached(.medium))
    }

    func testTheRequestedLevelIsTheKeyEvenWhenAGuardrailLoweredIt() {
        var levels = PreviewLevels()
        // Asked for FULL, guardrail stepped it down to MEDIUM: Tab back to FULL must not
        // recompile what was already tried.
        levels.store(CompiledPrompt(text: "organised", level: .medium), requested: .full)
        XCTAssertEqual(levels.cached(.full)?.text, "organised")
    }

    func testShiftTabGoesBackAndWraps() {
        XCTAssertEqual(PreviewLevels.previous(before: .full), .medium)
        XCTAssertEqual(PreviewLevels.previous(before: .medium), .light)
        XCTAssertEqual(PreviewLevels.previous(before: .light), .verbatim)
        XCTAssertEqual(PreviewLevels.previous(before: .verbatim), .full)
        for level in EditLevel.allCases {
            XCTAssertEqual(PreviewLevels.previous(before: level.cycled), level, "⇧Tab undoes Tab")
        }
    }

    func testNumberKeysJumpToLevels() {
        XCTAssertEqual(PreviewLevels.level(forNumber: 1), .verbatim)
        XCTAssertEqual(PreviewLevels.level(forNumber: 4), .full)
        XCTAssertNil(PreviewLevels.level(forNumber: 5))
    }

    func testPreviewKeysMap() {
        func key(_ code: Int, _ flags: CGEventFlags = []) -> PreviewKey? {
            HotkeyMonitor.previewKey(for: CGKeyCode(code), flags: flags)
        }
        XCTAssertEqual(key(kVK_Tab), .cycleLevel)
        XCTAssertEqual(key(kVK_Tab, .maskShift), .cycleBack)
        XCTAssertEqual(key(kVK_UpArrow), .scrollUp)
        XCTAssertEqual(key(kVK_PageDown), .scrollDown)
        XCTAssertEqual(key(kVK_ANSI_3), .levelMedium)
        XCTAssertEqual(key(kVK_ANSI_R), .rerecord)
        // Shortcuts in the app behind the overlay keep working.
        XCTAssertNil(key(kVK_ANSI_3, .maskCommand))
        XCTAssertNil(key(kVK_UpArrow, .maskControl))
        XCTAssertNil(key(kVK_ANSI_5))
    }
}
