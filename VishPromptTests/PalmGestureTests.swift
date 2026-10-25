import XCTest
@testable import VishPrompt

/// Gestures 1: each palm-rest gesture maps to an action, saved per Mac, through the existing
/// entry points; a triple never also fires the double.
final class PalmGestureTests: XCTestCase {
    private func settings() -> PalmGestureSettings {
        PalmGestureSettings(defaults: UserDefaults(suiteName: "PalmGestureTests-\(UUID())")!)
    }

    func testEverythingIsOffUntilThePalmRestIsFirstTurnedOn() {
        let s = settings()
        for gesture in PalmGesture.allCases { XCTAssertEqual(s.action(for: gesture), .off) }
        s.applyFirstTimeDefaults()
        XCTAssertEqual(s.action(for: .double), .dictate, "the first time: double-tap either side dictates")
        XCTAssertEqual(s.action(for: .triple), .off)
        s.set(.off, for: .double)
        s.applyFirstTimeDefaults()
        XCTAssertEqual(s.action(for: .double), .off, "only the first time: a choice is never overwritten")
    }

    @MainActor
    func testTurningThePalmRestOnAppliesTheFirstTimeDefault() {
        let defaults = UserDefaults(suiteName: "PalmGestureTests-\(UUID())")!
        let trigger = ChassisTapTrigger(defaults: defaults) { _ in }
        XCTAssertEqual(PalmGestureSettings(defaults: defaults).action(for: .double), .off)
        trigger.setEnabled(true)
        XCTAssertEqual(PalmGestureSettings(defaults: defaults).action(for: .double), .dictate)
        trigger.setEnabled(false)
    }

    func testChoicesAreSavedAndReadBack() {
        let defaults = UserDefaults(suiteName: "PalmGestureTests-\(UUID())")!
        PalmGestureSettings(defaults: defaults).set(.smartPaste, for: .triple)
        PalmGestureSettings(defaults: defaults).set(.editSelection, for: .double)
        let again = PalmGestureSettings(defaults: defaults)
        XCTAssertEqual(again.action(for: .triple), .smartPaste)
        XCTAssertEqual(again.action(for: .double), .editSelection)
        XCTAssertTrue(again.listensForTriples)
        XCTAssertFalse(settings().listensForTriples)
    }

    func testEachActionUsesAnExistingEntryPoint() {
        let s = settings()
        let cases: [(PalmAction, PalmDispatch)] = [(.dictate, .start(nil)), (.smartPaste, .start(.paste)), (.editSelection, .start(.edit)), (.off, .ignore)]
        for (action, expected) in cases {
            s.set(action, for: .double)
            XCTAssertEqual(PalmDispatch.resolve(.double, settings: s, recording: false) { false }, expected, "\(action)")
        }
        s.set(.fixScreenshot, for: .double)
        XCTAssertEqual(PalmDispatch.resolve(.double, settings: s, recording: false) { true }, .start(.paste), "a screenshot on the clipboard: fn+V's screenshot path")
        XCTAssertEqual(PalmDispatch.resolve(.double, settings: s, recording: false) { false }, .needsScreenshot, "no screenshot: say so, start nothing")
    }

    func testAnyAssignedGestureEndsARecordingAndAnOffOneDoesNot() {
        let s = settings()
        s.set(.smartPaste, for: .triple)
        XCTAssertEqual(PalmDispatch.resolve(.triple, settings: s, recording: true) { false }, .stop)
        XCTAssertEqual(PalmDispatch.resolve(.double, settings: s, recording: true) { false }, .ignore)
    }

    func testASmartPasteGestureStartsTheSameCaptureFnVWould() {
        var g = HotkeyGesture()
        XCTAssertEqual(g.chassisTap(at: 1, chord: .paste), [.startCapture, .smartPaste, .lockedOn])
        XCTAssertTrue(g.pasteRequested)
        XCTAssertEqual(g.chassisTap(at: 4, chord: .paste), [.finishCapture(modifiers: .none, locked: true)], "a second gesture ends it")
        XCTAssertFalse(g.pasteRequested, "and the next session starts clean")
        XCTAssertEqual(g.chassisTap(at: 6, chord: .edit), [.startCapture, .editSelection, .lockedOn])
        XCTAssertEqual(g.handle(.silenceTimeout), .finishCapture(modifiers: .none, locked: true))
        XCTAssertNil(g.chord)
    }

    func testAChordIsNeverAddedToAHeldDictation() {
        var g = HotkeyGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertEqual(g.chassisTap(at: 0.5, chord: .paste), [])
        XCTAssertNil(g.chord)
    }

    // MARK: Triple vs double, on the real quiet idle recording

    private func knock(_ s: inout [TapDetectorTests.Sample], at t0: Double, g: Float = 0.2) {
        for i in s.indices where s[i].t >= t0 && s[i].t < t0 + 0.12 {
            let dt = s[i].t - t0
            let wave = g * Float(exp(-dt / 0.015) * sin(2 * .pi * 120 * dt))
            s[i].a += SIMD3(0.1 * wave, 0.2 * wave, wave)
        }
    }

    private func events(_ s: [TapDetectorTests.Sample], triples: Bool) -> [TapEvent] {
        var tuning = TapDetector.Tuning()
        tuning.listensForTriples = triples
        var detector = TapDetector(tuning: tuning)
        return s.compactMap { sample in
            if sample.input { detector.noteInput(at: sample.t) }
            return detector.process(t: sample.t, sample.a)
        }
    }

    func testATripleIsOneTripleAndNeverAlsoADouble() throws {
        var s = try TapDetectorTests.load("idle-quiet")
        for t0 in [3.0, 3.25, 3.5] { knock(&s, at: t0) }
        let heard = events(s, triples: true)
        XCTAssertEqual(heard.count, 1)
        guard case .tripleTap? = heard.first else { return XCTFail("expected a triple, heard \(heard)") }
    }

    func testWithTriplesOffThreeKnocksAreABurstNotADouble() throws {
        var s = try TapDetectorTests.load("idle-quiet")
        for t0 in [3.0, 3.25, 3.5] { knock(&s, at: t0) }
        XCTAssertEqual(events(s, triples: false), [])
    }

    func testADoubleStillFiresWhenTriplesAreOnJustAMomentLater() throws {
        var s = try TapDetectorTests.load("idle-quiet")
        for t0 in [3.0, 3.25] { knock(&s, at: t0) }
        let heard = events(s, triples: true)
        XCTAssertEqual(heard.count, 1)
        guard case .doubleTap? = heard.first else { return XCTFail("expected a double, heard \(heard)") }
    }

    func testFourKnocksAreNothing() throws {
        var s = try TapDetectorTests.load("idle-quiet")
        for t0 in [3.0, 3.25, 3.5, 3.75] { knock(&s, at: t0) }
        XCTAssertEqual(events(s, triples: true), [])
    }

    func testTheRealRecordingsStillFireNothingWithTriplesOn() throws {
        // Turning triples on must not make anything fire that did not before.
        for name in ["bed1/single", "bed1/typing", "bed1/clicks", "bed1/handling", "bed2/single", "bed2/clicks"] {
            XCTAssertEqual(events(try TapDetectorTests.load(name), triples: true), [], name)
        }
    }
}
