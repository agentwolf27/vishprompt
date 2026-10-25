import simd
import XCTest
@testable import VishPrompt

/// Gestures 2: left and right unlock only when a calibration run separates this Mac's sides at
/// 95% or better; an inseparable run keeps the one either-side row and says why.
final class SideCalibrationTests: XCTestCase {
    /// The shapes of the knocks the detector hears in a recording.
    private func shapes(_ name: String) throws -> [KnockShape] {
        var detector = TapDetector()
        for s in try TapDetectorTests.load(name) { _ = detector.process(t: s.t, s.a) }
        return detector.heardShapes
    }

    private func calibrate(_ session: String, taps: Int) throws -> SideCalibration {
        let left = Array(try shapes("\(session)/double-left").prefix(taps))
        let right = Array(try shapes("\(session)/double-right").prefix(taps))
        let calibration = try XCTUnwrap(SideCalibration.measure(left: left, right: right, model: "Mac14,7"))
        print(String(format: "PROBE %@ with %d taps a side (%d left, %d right heard): %.0f%% → %@", session, taps, left.count, right.count,
                     calibration.accuracy * 100, calibration.unlocked ? "unlocked" : "locked"))
        return calibration
    }

    func testTheInseparableFirstBedSessionKeepsTheSideRowsLocked() throws {
        XCTAssertFalse(try calibrate("bed1", taps: SideCalibration.tapsPerSide).unlocked, "ten taps a side, as the calibration asks")
        XCTAssertFalse(try calibrate("bed1", taps: 99).unlocked, "every knock in the files")
        // Why ten and not five: five a side from this inseparable session scores 100% by chance.
        _ = try calibrate("bed1", taps: 5)
    }

    func testTheSecondBedSessionIsMeasuredTheSameWay() throws {
        // Measured and printed: whether it unlocks is the data's call, and either answer is honest.
        _ = try calibrate("bed2", taps: SideCalibration.tapsPerSide)
        _ = try calibrate("bed2", taps: 99)
    }

    private func shape(_ x: Float, _ y: Float, _ z: Float) -> KnockShape {
        let d = SIMD3<Float>(x, y, z)
        return KnockShape(direction: d / simd_length(d), energy: (d * d) / simd_length_squared(d), early: SIMD3(x == 0 ? 0 : (x < 0 ? -1 : 1), 1, 1))
    }

    func testCleanlySeparatedSidesUnlockAndPlaceEachDouble() throws {
        let left = (0..<10).map { i in shape(-0.4 - Float(i) * 0.01, 0.1, 0.9) }
        let right = (0..<10).map { i in shape(0.4 + Float(i) * 0.01, 0.1, 0.9) }
        let calibration = try XCTUnwrap(SideCalibration.measure(left: left, right: right, model: "Mac14,7"))
        XCTAssertEqual(calibration.accuracy, 1.0)
        XCTAssertTrue(calibration.unlocked)
        XCTAssertEqual(calibration.side(of: [shape(-0.42, 0.1, 0.9), shape(-0.41, 0.1, 0.9)]), .left)
        XCTAssertEqual(calibration.side(of: [shape(0.42, 0.1, 0.9), shape(0.41, 0.1, 0.9)]), .right)
        XCTAssertNil(calibration.side(of: [shape(-0.42, 0.1, 0.9), shape(0.42, 0.1, 0.9)]), "knocks that disagree: not run")
        XCTAssertNil(calibration.side(of: [shape(0.0, 0.1, 0.9), shape(0.0, 0.1, 0.9)]), "in the middle: not guessed")
    }

    func testTwoMisplacedTapsOfTwentyAreNotEnough() throws {
        var left = (0..<10).map { _ in shape(-0.4, 0.1, 0.9) }
        let right = (0..<10).map { _ in shape(0.4, 0.1, 0.9) }
        left[2] = shape(0.4, 0.1, 0.9)  // two left taps that look like right ones
        left[7] = shape(0.4, 0.1, 0.9)
        let calibration = try XCTUnwrap(SideCalibration.measure(left: left, right: right, model: "Mac14,7"))
        XCTAssertLessThan(calibration.accuracy, 0.95)
        XCTAssertFalse(calibration.unlocked)
        XCTAssertNil(calibration.side(of: [shape(-0.4, 0.1, 0.9)]), "a locked calibration places nothing")
    }

    func testTooFewTapsAreNotJudged() {
        XCTAssertNil(SideCalibration.measure(left: [shape(1, 0, 0)], right: [shape(-1, 0, 0)]))
    }

    func testItIsStoredPerMacAndCanBeForgotten() throws {
        let defaults = UserDefaults(suiteName: "SideCalibrationTests-\(UUID())")!
        let left = (0..<5).map { _ in shape(-0.4, 0.1, 0.9) }
        let right = (0..<5).map { _ in shape(0.4, 0.1, 0.9) }
        try XCTUnwrap(SideCalibration.measure(left: left, right: right, model: "Mac14,7")).save(in: defaults)
        XCTAssertNotNil(SideCalibration.saved(in: defaults, model: "Mac14,7"))
        XCTAssertNil(SideCalibration.saved(in: defaults, model: "Mac15,3"), "copied to another Mac: not carried over")
        SideCalibration.forget(in: defaults)
        XCTAssertNil(SideCalibration.saved(in: defaults, model: "Mac14,7"))
        XCTAssertEqual(SideCalibration.lockedReason, "This Mac can't tell your left and right taps apart on this surface; try calibrating at a desk.")
    }

    func testSideGesturesRunTheirOwnActions() {
        let settings = PalmGestureSettings(defaults: UserDefaults(suiteName: "SideCalibrationTests-\(UUID())")!)
        settings.set(.smartPaste, for: .doubleLeft)
        settings.set(.dictate, for: .doubleRight)
        XCTAssertEqual(PalmDispatch.resolve(.doubleLeft, settings: settings, recording: false) { false }, .start(.paste))
        XCTAssertEqual(PalmDispatch.resolve(.doubleRight, settings: settings, recording: false) { false }, .start(nil))
    }

    func testAnUnlockedCalibrationNeverPlacesADoubleOnTheWrongSide() throws {
        let calibration = try calibrate("bed2", taps: SideCalibration.tapsPerSide)
        guard calibration.unlocked else { return }
        for (file, truth) in [("bed2/double-left", SideCalibration.Side.left), ("bed2/double-right", .right)] {
            var detector = TapDetector()
            var placed: [SideCalibration.Side?] = []
            for s in try TapDetectorTests.load(file) {
                if case .doubleTap? = detector.process(t: s.t, s.a) { placed.append(calibration.side(of: detector.lastGestureShapes)) }
            }
            let right = placed.filter { $0 == truth }.count
            let wrong = placed.filter { $0 != nil && $0 != truth }.count
            print("PROBE \(file): \(placed.count) doubles, \(right) placed \(truth.rawValue), \(wrong) on the wrong side, \(placed.count - right - wrong) not placed")
            XCTAssertEqual(wrong, 0, "a side is never guessed wrong; an unsure one is not run")
        }
    }
}
