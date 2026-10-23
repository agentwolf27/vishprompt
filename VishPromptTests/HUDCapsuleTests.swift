import AppKit
import SwiftUI
import XCTest
@testable import VishPrompt

/// UI v2.1: the capsule's copy for every state, from Concept A in
/// docs/research/ui-concepts-2026-10-23.md.
@MainActor
final class HUDCapsuleTests: XCTestCase {
    private let slack = HUDContext(mode: .dictate, app: "Slack", takeSeconds: 7.4, triggerName: "fn")

    func testRecording() throws {
        let model = try XCTUnwrap(CapsuleModel.make(.listening(level: 0.2, seconds: 7.9, locked: false, app: "Slack"), context: slack))
        XCTAssertEqual(model.glyph, .mode(.dictate))
        XCTAssertEqual(model.destination, "into Slack")
        XCTAssertEqual(model.timer, "0:07", "whole seconds, no fake precision")
        XCTAssertEqual(model.status, "release to send · esc")
        XCTAssertNotNil(model.meter)
        XCTAssertFalse(model.working)
    }

    func testHandsFreeNamesTheKey() throws {
        let model = try XCTUnwrap(CapsuleModel.make(.listening(level: 0, seconds: 3, locked: true), context: slack))
        XCTAssertEqual(model.status, "Hands-free · tap fn to stop · esc")
    }

    func testPasteAndEditSayWhatToSay() throws {
        XCTAssertEqual(CapsuleModel.make(.listening(level: 0, seconds: 1, locked: false, mode: .paste), context: slack)?.status,
                       "say how, or just release · esc")
        XCTAssertEqual(CapsuleModel.make(.listening(level: 0, seconds: 1, locked: false, mode: .edit), context: slack)?.status,
                       "say how to change it · esc")
    }

    func testWorkingFreezesTheTakeAndNamesTheProvider() throws {
        let transcribing = try XCTUnwrap(CapsuleModel.make(.transcribing, context: slack))
        XCTAssertTrue(transcribing.working)
        XCTAssertNil(transcribing.meter)
        XCTAssertEqual(transcribing.timer, "0:07", "the take's length, frozen")
        XCTAssertEqual(transcribing.status, "Transcribing on this Mac")

        let rewriting = try XCTUnwrap(CapsuleModel.make(.compiling(partial: "Users are getting", provider: "via your Claude subscription"), context: slack))
        XCTAssertEqual(rewriting.status, "Rewriting via your Claude subscription")
        XCTAssertEqual(rewriting.liveWords, "Users are getting")
    }

    func testUndoIsNamedOnlyWhereItWorks() throws {
        XCTAssertEqual(CapsuleModel.make(.inserted(into: "Slack", landing: .undoable), context: slack)?.status, "Inserted into Slack · ⌘Z undoes")
        XCTAssertEqual(CapsuleModel.make(.inserted(into: "Shell", landing: .notUndoable), context: slack)?.status, "Inserted into Shell")
        XCTAssertEqual(CapsuleModel.make(.inserted(into: "Claude Code", landing: .agentNotSent), context: slack)?.status,
                       "In Claude Code, not sent. Review it, then press Return there")
        XCTAssertEqual(Landing(destinationID: "claude_code"), .agentNotSent)
        XCTAssertEqual(Landing(destinationID: "shell"), .notUndoable)
        XCTAssertEqual(Landing(destinationID: "message"), .undoable)
    }

    func testOnlyHiddenHasNoCapsule() {
        XCTAssertNil(CapsuleModel.make(.hidden, context: slack))
        XCTAssertEqual(CapsuleModel.make(.cancelled, context: slack)?.status, "Cancelled")
    }

    func testTheSizesAreTheConcepts() {
        XCTAssertEqual(CapsuleModel.height, 36)
        XCTAssertEqual(CapsuleModel.minimumWidth, 280)
        XCTAssertEqual(CapsuleModel.maximumWidth, 460)
        XCTAssertEqual(HUDPanel.gapBelowMenuBar, 8)
    }

    /// Renders each state to build/ui-snapshots so it can be looked at. Materials draw flat
    /// outside a window, so this checks layout and copy, not the blur.
    func testRenderSnapshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["VISHPROMPT_SNAPSHOTS"] else { return }
        let states: [(String, HUDState, HUDContext)] = [
            ("1-recording", .listening(level: 0.12, seconds: 7, locked: false, app: "Slack"), slack),
            ("2-live-words", .listening(level: 0.1, seconds: 12, locked: false, partial: "hey can you send me the figma link for the onboarding", app: "Slack"), slack),
            ("3-paste", .listening(level: 0.08, seconds: 2, locked: false, mode: .paste, app: "Slack"), slack),
            ("4-rewriting", .compiling(partial: "", provider: "via your Claude subscription"), HUDContext(mode: .dictate, app: "Claude Code", takeSeconds: 14, triggerName: "fn")),
            ("5-inserted", .inserted(into: "Slack", landing: .undoable), slack),
            ("6-agent", .inserted(into: "Claude Code", landing: .agentNotSent), slack),
        ]
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for (name, state, context) in states {
            try HUDSnapshot.write(HUDView(state: state, context: context), to: URL(filePath: directory).appending(path: "\(name).png"))
        }
    }
}
