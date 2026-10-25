import XCTest
@testable import VishPrompt

/// The detector against Vish's own recordings from his 13-inch M2 MacBook Pro (Mac14,7), made
/// with `make record-taps` on 2026-10-25: `bed/` on a bed under a blanket, `desk/` at a desk.
///
/// Every negative file fires nothing, except `bed/idle`, which holds one real double knock at
/// 5.63 s (two sharp hits 0.20 s apart, 185 and 154 mg) that is shaped exactly like a double tap;
/// no detector on this sensor can drop it without dropping real taps, so the test pins it.
/// Each check runs at 800 Hz and replayed at the app's live sample rate with its input veto.
final class TapRecordingTests: XCTestCase {
    private static func load(_ name: String) throws -> [TapDetectorTests.Sample] {
        try TapDetectorTests.load(name)
    }

    /// Replays a recording the way the app samples it: every eighth report (100 Hz) until the
    /// pipeline asks for full rate, then all of them, then slow again when it settles.
    static func replayLive(_ samples: [TapDetectorTests.Sample]) -> [Double] {
        final class Box: @unchecked Sendable { var fast = false; var taps: [Double] = [] }
        let box = Box()
        let pipeline = TapPipeline(setRate: { box.fast = $0 == .active }, onDoubleTap: { box.taps.append($0) })
        for (i, s) in samples.enumerated() where box.fast || i % 8 == 0 {
            pipeline.process(t: s.t, s.a)
        }
        return box.taps
    }

    /// The live replay, with the app's input veto applied from the recording's input marks.
    static func liveAfterVeto(_ samples: [TapDetectorTests.Sample]) -> [Double] {
        let inputs = samples.filter(\.input).map(\.t)
        return replayLive(samples).filter { first in
            // The app decides about 0.6 s after the first knock; any input from 0.4 s before it until then vetoes.
            !inputs.contains { TapInputGuard.touched(lastInput: $0, firstKnock: first) && $0 <= first + 0.6 }
        }
    }

    private func check(_ name: String) throws -> (full: [Double], live: [Double], detector: TapDetector) {
        let samples = try Self.load(name)
        let result = TapDetectorTests.run(samples)
        let live = Self.liveAfterVeto(samples)
        let reasons = Dictionary(grouping: result.detector.rejected, by: { $0.reason.hasPrefix("the Mac moved") ? "the Mac moved" : $0.reason }).mapValues(\.count)
        print("PROBE \(name): \(result.taps.count) at 800 Hz \(result.taps.map { String(format: "%.2f", $0) }), \(live.count) live; rejected \(reasons)")
        return (result.taps, live, result.detector)
    }

    func testNothingFiresWhenNobodyTapsThePalmRest() throws {
        for name in ["bed/single", "bed/typing", "bed/clicks", "bed/handling", "desk/single", "desk/clicks"] {
            let result = try check(name)
            XCTAssertEqual(result.full, [], "\(name) at 800 Hz")
            XCTAssertEqual(result.live, [], "\(name) as the app samples it")
        }
    }

    func testTheBedIdleFileHoldsOneRealDoubleKnockAndNothingElse() throws {
        let result = try check("bed/idle")
        XCTAssertEqual(result.full.count, 1)
        XCTAssertEqual(result.full.first ?? 0, 5.82, accuracy: 0.05, "the double knock at 5.63 s")
        XCTAssertEqual(result.live.count, 1)
    }

    func testDeskDoubleTapsFireOnBothSides() throws {
        let left = try check("desk/double-left")
        XCTAssertGreaterThanOrEqual(left.full.count, 6, "six doubles to the left of the trackpad")
        XCTAssertGreaterThanOrEqual(left.live.count, 6)
        let right = try check("desk/double-right")
        XCTAssertGreaterThanOrEqual(right.full.count, 4, "at least four of the six, lighter, doubles to the right")
        XCTAssertGreaterThanOrEqual(right.live.count, 4)
        XCTAssertLessThanOrEqual(left.full.count, 6, "and never more than were tapped")
        XCTAssertLessThanOrEqual(right.full.count, 6)
    }

    func testWhatTheBedYieldsIsMeasured() throws {
        // Recorded on a bed under a blanket: measured, not required. Light taps there are the size
        // of the resting noise.
        _ = try check("bed/double-left")
        _ = try check("bed/double-right")
    }

    func testClicksReachTheVetoAtADeskButNotOnTheBed() throws {
        // 20 s of trackpad clicks with the left-click age polled every 5 ms.
        XCTAssertEqual(try Self.load("bed/clicks").filter(\.input).count, 0, "on the bed: not one click mark")
        XCTAssertGreaterThan(try Self.load("desk/clicks").filter(\.input).count, 10, "at the desk: they arrive")
        XCTAssertGreaterThan(try Self.load("bed/typing").filter(\.input).count, 50, "keys always arrive")
    }
}
