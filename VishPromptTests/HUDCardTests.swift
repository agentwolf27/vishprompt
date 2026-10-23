import AppKit
import SwiftUI
import XCTest
@testable import VishPrompt

/// UI v2.2: a card under the capsule only when there is a decision.
@MainActor
final class HUDCardTests: XCTestCase {
    private let context = HUDContext(mode: .dictate, app: "Claude Code", takeSeconds: 14, triggerName: "fn")
    private func preview(_ mode: HUDMode = .dictate, stale: Bool = false) -> PreviewHUD {
        PreviewHUD(text: "Users are getting logged out after their token expires.", mode: mode, destination: "Claude Code",
                   label: "Compiled", heard: "fix the logout bug", source: "Sent your words to your Claude subscription.",
                   hints: "⏎ insert · ⇥ ⇧⇥ or 1–4 level · R start over · esc", isStale: stale)
    }

    func testOnlyDecisionsGetACard() {
        XCTAssertTrue(HUDLayout.showsCard(.preview(preview())))
        XCTAssertTrue(HUDLayout.showsCard(.failed(message: "x")))
        for state: HUDState in [.hidden, .transcribing, .compiling(partial: ""), .cancelled, .inserted(into: "Slack"),
                                .listening(level: 0, seconds: 1, locked: false)] {
            XCTAssertFalse(HUDLayout.showsCard(state), "no card for \(state)")
        }
    }

    func testTheCapsuleStaysAboveTheCard() throws {
        let ready = try XCTUnwrap(CapsuleModel.make(.preview(preview()), context: context))
        XCTAssertEqual(ready.glyph, .mode(.dictate))
        XCTAssertEqual(ready.destination, "into Claude Code")
        XCTAssertEqual(ready.status, "Ready to insert")
        XCTAssertEqual(ready.timer, "0:14")
        XCTAssertEqual(CapsuleModel.make(.preview(preview(.paste)), context: context)?.status, "Ready to paste")
        XCTAssertEqual(CapsuleModel.make(.preview(preview(.edit)), context: context)?.status, "Ready to replace")

        let rewriting = try XCTUnwrap(CapsuleModel.make(.preview(preview(stale: true)), context: context))
        XCTAssertTrue(rewriting.working, "a level change pulses while the old text stays dimmed in the card")

        let failed = try XCTUnwrap(CapsuleModel.make(.failed(message: "x"), context: context))
        XCTAssertEqual(failed.glyph, .failed)
        XCTAssertEqual(failed.status, "Didn't land")
    }

    func testTheCardIsTheConcepts() {
        XCTAssertEqual(HUDLayout.cardWidth, 480)
        XCTAssertEqual(HUDLayout.dropDuration, 0.18)
        XCTAssertTrue(HUDLayout.cardArrivesByCrossfade(reduceMotion: true))
        XCTAssertFalse(HUDLayout.cardArrivesByCrossfade(reduceMotion: false))
    }

    func testErrorsStaySixSeconds() {
        XCTAssertEqual(HUDCopy.rescueDuration, 6)
    }

    func testRenderSnapshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["VISHPROMPT_SNAPSHOTS"] else { return }
        let states: [(String, HUDState)] = [
            ("card-1-preview", .preview(preview())),
            ("card-2-rewriting-level", .preview(preview(stale: true))),
            ("card-3-error", .failed(message: "Claude Code isn't in front any more, so nothing was inserted. Copied: press ⌘V where you want it.")),
        ]
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for (name, state) in states {
            try HUDSnapshot.write(HUDView(state: state, context: context), to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }
}
