import XCTest
@testable import VishPrompt

/// Tap fix 2: the detector against Vish's own recordings, made on 2026-10-25 with
/// `make record-taps` on his 13-inch M2 MacBook Pro, sitting on a bed under a blanket.
///
/// The five negative files must fire nothing. The bed is the hard case: a soft, rocking surface
/// damps a fingertip tap to the size of the resting noise and makes a bump ring for most of a
/// second, so what the two positive files yield is measured and printed, not yet required.
/// Desk recordings come next (PLAN.md, "Tap fix 2").
final class TapRecordingTests: XCTestCase {
    private func taps(_ name: String) throws -> (taps: [Double], detector: TapDetector) {
        TapDetectorTests.run(try TapDetectorTests.load(name))
    }

    func testNothingFiresWhenNobodyTapsThePalmRest() throws {
        for name in ["bed/idle", "bed/single", "bed/typing", "bed/clicks", "bed/handling"] {
            let result = try taps(name)
            let reasons = Dictionary(grouping: result.detector.rejected, by: \.reason).mapValues(\.count)
            print("PROBE \(name): \(result.taps.count) fired; rejected \(reasons)")
            XCTAssertEqual(result.taps, [], "\(name) must not start dictation")
        }
    }

    func testWhatTheBedYieldsIsMeasured() throws {
        for name in ["bed/double-left", "bed/double-right"] {
            let result = try taps(name)
            let reasons = Dictionary(grouping: result.detector.rejected, by: \.reason).mapValues(\.count)
            print("PROBE \(name): \(result.taps.count) fired at \(result.taps.map { String(format: "%.2f", $0) }); rejected \(reasons)")
        }
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

    func testNothingFiresAtTheLiveSampleRateEither() throws {
        for name in ["bed/idle", "bed/single", "bed/typing", "bed/clicks", "bed/handling"] {
            let samples = try TapDetectorTests.load(name)
            print("PROBE live \(name): \(Self.replayLive(samples).count) before the input veto, \(Self.liveAfterVeto(samples).count) after")
            XCTAssertEqual(Self.liveAfterVeto(samples), [], "\(name), as the app samples it")
        }
        for name in ["bed/double-left", "bed/double-right"] {
            print("PROBE live \(name): \(Self.liveAfterVeto(try TapDetectorTests.load(name)).count) fired")
        }
    }

    func testTheClickRecordingProvesClicksNeverReachedTheOldCheck() throws {
        // 20 s of trackpad clicks with the left-click age polled every 5 ms: not one mark. The
        // same poll caught 101 key presses in the typing file.
        XCTAssertEqual(try TapDetectorTests.load("bed/clicks").filter(\.input).count, 0)
        XCTAssertGreaterThan(try TapDetectorTests.load("bed/typing").filter(\.input).count, 50)
    }
}
