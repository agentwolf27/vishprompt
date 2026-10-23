import AppKit
import XCTest
@testable import VishPrompt

/// UI v2.6: the menu bar icon shows recording, working, paused and needs-setup.
final class MenuBarIconTests: XCTestCase {
    private func icon(granted: Bool = true, failed: Bool = false, paused: Bool = false, hud: HUDState? = .hidden) -> MenuBarIconState {
        MenuBarIconState.make(permissionsGranted: granted, startupFailed: failed, isPaused: paused, phase: hud.map(HUDPhase.init))
    }

    private let preview = HUDState.preview(PreviewHUD(text: "x", mode: .dictate, destination: "Claude Code", label: "Compiled",
                                                      source: "Stayed on this Mac.", hints: "", isStale: false))

    func testEachMomentOfADictationShowsInTheIcon() {
        XCTAssertEqual(icon(), .ready)
        XCTAssertEqual(icon(hud: nil), .ready, "before the controller exists")
        XCTAssertEqual(icon(hud: .listening(level: 0.4, seconds: 2, locked: false)), .recording)
        XCTAssertEqual(icon(hud: .transcribing), .working)
        XCTAssertEqual(icon(hud: .compiling(partial: "", provider: nil)), .working)
        XCTAssertEqual(icon(hud: preview), .working, "a preview waits on the user, so the app is not idle")
        XCTAssertEqual(icon(hud: .failed(message: "x")), .ready)
        XCTAssertEqual(icon(hud: .cancelled), .ready)
    }

    func testTheMeterMovingIsNotAChangeOfPhase() {
        XCTAssertEqual(HUDPhase(.listening(level: 0.1, seconds: 1, locked: false)),
                       HUDPhase(.listening(level: 0.9, seconds: 2, locked: false, partial: "fix the")))
        XCTAssertEqual(HUDPhase(.compiling(partial: "a", provider: nil)), HUDPhase(.compiling(partial: "ab", provider: nil)))
    }

    func testSetupAndPauseOutrankWhatTheOverlayLastShowed() {
        let listening = HUDState.listening(level: 0.4, seconds: 2, locked: false)
        XCTAssertEqual(icon(granted: false, paused: true, hud: listening), .needsSetup)
        XCTAssertEqual(icon(failed: true, hud: listening), .couldNotStart)
        XCTAssertEqual(icon(paused: true, hud: listening), .paused, "a paused app never shows a recording")
    }

    func testEveryStateHasADistinctRealSymbolAndSaysItsName() {
        let all: [MenuBarIconState] = [.ready, .recording, .working, .paused, .needsSetup, .couldNotStart]
        for state in all {
            XCTAssertNotNil(NSImage(systemSymbolName: state.symbol, accessibilityDescription: nil),
                            "\(state.symbol) must exist in SF Symbols on macOS 15, or the menu bar goes blank")
            XCTAssertTrue(state.accessibilityLabel.hasPrefix("VishPrompt, "))
        }
        let glanceable: [MenuBarIconState] = [.ready, .recording, .working, .paused, .needsSetup]
        XCTAssertEqual(Set(glanceable.map(\.symbol)).count, glanceable.count, "each of the five must look different")
    }
}
