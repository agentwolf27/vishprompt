import XCTest
@testable import Visprflow

/// The overlay can never be focused, so VoiceOver users depend entirely on these.
final class AccessibilityAnnouncementTests: XCTestCase {
    private func preview(_ text: String, mode: HUDMode = .dictate, stale: Bool = false) -> PreviewHUD {
        PreviewHUD(text: text, mode: mode, destination: "Claude Code", label: "Compiled", source: "Stayed on this Mac.", hints: "", isStale: stale)
    }

    func testEveryVisibleStateIsAnnounced() {
        let states: [HUDState] = [
            .listening(level: 0, seconds: 0, locked: false),
            .listening(level: 0, seconds: 0, locked: true),
            .listening(level: 0, seconds: 0, locked: false, mode: .paste),
            .transcribing,
            .compiling(partial: ""),
            .preview(preview("Fix the login bug.")),
            .inserted(into: "Slack"),
            .cancelled,
            .failed(message: "Nothing on the clipboard to paste."),
        ]
        for state in states {
            XCTAssertNotNil(HUDAnnouncement.text(for: state, previous: .hidden), "silent: \(state)")
        }
        XCTAssertNil(HUDAnnouncement.text(for: .hidden, previous: .transcribing))
    }

    func testMeterUpdatesAreNotReadOut() {
        let first = HUDState.listening(level: 0.1, seconds: 0.1, locked: false)
        let later = HUDState.listening(level: 0.4, seconds: 2.3, locked: false, partial: "add a retry")
        XCTAssertNil(HUDAnnouncement.text(for: later, previous: first))
        XCTAssertNotNil(HUDAnnouncement.text(for: .listening(level: 0, seconds: 3, locked: true), previous: first),
                        "switching to hands-free is news")
    }

    func testStreamingTextIsNotReadOutTokenByToken() {
        XCTAssertNil(HUDAnnouncement.text(for: .compiling(partial: "Users are"), previous: .compiling(partial: "Users")))
    }

    func testThePreviewSaysWhereItGoesWhatItSaysAndHowToAct() {
        let words = HUDAnnouncement.text(for: .preview(preview("Users are logged out after expiry. Write a failing test first.")), previous: .compiling(partial: ""))
        XCTAssertEqual(words, "Dictate preview for Claude Code, Compiled. Users are logged out after expiry. Return inserts, Escape cancels.")
        let paste = HUDAnnouncement.previewText(preview("• one", mode: .paste))
        XCTAssertTrue(paste.contains("Return pastes"))
    }

    func testALongFirstSentenceIsCapped() {
        let long = String(repeating: "word ", count: 80)
        XCTAssertLessThanOrEqual(HUDAnnouncement.firstSentence(of: long).count, 160)
    }

    func testScrollingIsNotReannouncedButAStaleRewriteIs() {
        var scrolled = preview("Same text.")
        let original = scrolled
        scrolled.scrollLine = 4
        XCTAssertNil(HUDAnnouncement.text(for: .preview(scrolled), previous: .preview(original)))
        XCTAssertNotNil(HUDAnnouncement.text(for: .preview(preview("Same text.", stale: true)), previous: .preview(original)))
    }
}
