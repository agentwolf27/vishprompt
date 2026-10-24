import simd
import XCTest
@testable import VishPrompt

/// Tap 2: on recorded samples a double tap fires once, and single taps, typing, clicks and
/// handling fire nothing.
///
/// Two kinds of data. `Fixtures/taps/*.csv` are real recordings from the palm rest of a 13-inch
/// M2 MacBook Pro, made with `make record-taps`. The synthetic cases add knocks shaped like real
/// ones to the real idle recording, so the noise under them is the sensor's own.
final class TapDetectorTests: XCTestCase {
    struct Sample {
        var t: Double
        var a: SIMD3<Float>
        var input: Bool
    }

    static func load(_ name: String) throws -> [Sample] {
        let url = try XCTUnwrap(Bundle(for: TapDetectorTests.self).resourceURL).appending(path: "Fixtures/taps/\(name).csv")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").dropFirst().compactMap { line in
            let f = line.split(separator: ",").compactMap { Double($0) }
            guard f.count == 5 else { return nil }
            return Sample(t: f[0], a: SIMD3(Float(f[1]), Float(f[2]), Float(f[3])), input: f[4] == 1)
        }
    }

    static func run(_ samples: [Sample], tuning: TapDetector.Tuning = .init()) -> (taps: [Double], detector: TapDetector) {
        var detector = TapDetector(tuning: tuning)
        var taps: [Double] = []
        for s in samples {
            if s.input { detector.noteInput(at: s.t) }
            if case let .doubleTap(_, at)? = detector.process(t: s.t, s.a) { taps.append(at) }
        }
        return (taps, detector)
    }

    // MARK: Synthetic knocks on the real idle recording

    /// A knock as the palm rest rings: a decaying ~120 Hz oscillation, mostly vertical.
    private func knock(_ samples: inout [Sample], at t0: Double, g: Float, ring: Double = 0.015) {
        for i in samples.indices where samples[i].t >= t0 && samples[i].t < t0 + ring * 8 {
            let dt = samples[i].t - t0
            let wave = g * Float(exp(-dt / ring) * sin(2 * .pi * 120 * dt))
            samples[i].a += SIMD3(0.3 * wave, 0.2 * wave, wave)
        }
    }

    /// The Mac being lifted and set down: gravity swings by `degrees` and back, with a thud.
    private func handle(_ samples: inout [Sample], at t0: Double, degrees: Double) {
        for i in samples.indices where samples[i].t >= t0 && samples[i].t < t0 + 0.6 {
            let phase = (samples[i].t - t0) / 0.6
            let angle = Float(sin(.pi * phase) * degrees * .pi / 180)
            let a = samples[i].a
            samples[i].a = SIMD3(a.x, a.y * cos(angle) - a.z * sin(angle), a.y * sin(angle) + a.z * cos(angle))
        }
        knock(&samples, at: t0 + 0.6, g: 0.25, ring: 0.03)
    }

    private func markInput(_ samples: inout [Sample], at t: Double) {
        if let i = samples.firstIndex(where: { $0.t >= t }) { samples[i].input = true }
    }

    func testTheRealIdleRecordingFiresNothing() throws {
        let idle = try Self.load("idle")
        XCTAssertGreaterThan(idle.count, 7000, "10 s at about 800 Hz")
        XCTAssertEqual(Self.run(idle).taps, [])
    }

    func testADoubleTapFiresOnceAtItsSecondKnock() throws {
        var s = try Self.load("idle")
        knock(&s, at: 3.0, g: 0.03)
        knock(&s, at: 3.22, g: 0.03)
        let taps = Self.run(s).taps
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(taps.first ?? 0, 3.22, accuracy: 0.01)
    }

    func testAFaintDoubleTapStillCounts() throws {
        // The right side of the palm rest can read as little as 7–15 mg.
        var s = try Self.load("idle")
        knock(&s, at: 3.0, g: 0.012)
        knock(&s, at: 3.25, g: 0.012)
        XCTAssertEqual(Self.run(s).taps.count, 1)
    }

    func testTwoDoublesAFewSecondsApartFireTwice() throws {
        var s = try Self.load("idle")
        for t0 in [2.0, 6.0] {
            knock(&s, at: t0, g: 0.03)
            knock(&s, at: t0 + 0.2, g: 0.03)
        }
        XCTAssertEqual(Self.run(s).taps.count, 2)
    }

    func testSingleTapsFireNothing() throws {
        var s = try Self.load("idle")
        for t0 in stride(from: 1.0, to: 9.0, by: 1.5) { knock(&s, at: t0, g: 0.04) }
        XCTAssertEqual(Self.run(s).taps, [])
    }

    func testKnocksTooCloseOrTooFarApartFireNothing() throws {
        var s = try Self.load("idle")
        knock(&s, at: 2.0, g: 0.03)
        knock(&s, at: 2.0 + 0.7, g: 0.03)
        XCTAssertEqual(Self.run(s).taps, [], "0.7 s apart is two single taps")
    }

    func testABurstOfThreeIsNotADouble() throws {
        var s = try Self.load("idle")
        for k in 0..<3 { knock(&s, at: 3.0 + Double(k) * 0.15, g: 0.03) }
        XCTAssertEqual(Self.run(s).taps, [])
    }

    func testKnocksWithKeyPressesAreTyping() throws {
        var s = try Self.load("idle")
        for (k, t0) in [3.0, 3.2].enumerated() {
            knock(&s, at: t0, g: 0.05)
            // The key event is reported a little after the vibration, on the second knock only.
            if k == 1 { markInput(&s, at: t0 + 0.01) }
        }
        let result = Self.run(s)
        XCTAssertEqual(result.taps, [])
        XCTAssertTrue(result.detector.rejected.contains { $0.reason == "typing or clicking" })
    }

    func testAKeyPressJustBeforeTheKnocksAlsoCounts() throws {
        var s = try Self.load("idle")
        markInput(&s, at: 2.75)
        knock(&s, at: 3.0, g: 0.05)
        knock(&s, at: 3.2, g: 0.05)
        XCTAssertEqual(Self.run(s).taps, [])
    }

    func testLiftingAndSettingTheMacDownIsHandling() throws {
        var s = try Self.load("idle")
        handle(&s, at: 2.0, degrees: 6)
        // A knock right after setting it down, and one after: the pair must not count.
        knock(&s, at: 2.9, g: 0.03)
        let result = Self.run(s)
        XCTAssertEqual(result.taps, [])
        XCTAssertTrue(result.detector.rejected.contains { ["the Mac moved", "rang too long", "right after handling"].contains($0.reason) },
                      "rejected as handling, not by luck: \(result.detector.rejected)")
    }

    func testALongRingIsNotATap() throws {
        var s = try Self.load("idle")
        knock(&s, at: 3.0, g: 0.05, ring: 0.2)
        knock(&s, at: 3.25, g: 0.05, ring: 0.2)
        XCTAssertEqual(Self.run(s).taps, [])
    }

    func testAGapInTheStreamRestartsCleanly() throws {
        var s = try Self.load("idle")
        // A 2 s hole, as when sampling pauses for a locked screen.
        s.removeAll { $0.t > 4 && $0.t < 6 }
        knock(&s, at: 7.0, g: 0.03)
        knock(&s, at: 7.2, g: 0.03)
        XCTAssertEqual(Self.run(s).taps.count, 1)
    }
}

/// The two-speed sensor: the first knock lands at 100 Hz, the second at 800 Hz.
final class TapPipelineTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        var rates: [SPUAccelerometer.Rate] = []
        var taps: [Double] = []
    }

    func testAFirstKnockCaughtAt100HzStillMakesADoubleAndRaisesTheRate() throws {
        let idle = try TapDetectorTests.load("idle")
        // Every eighth sample is 100 Hz. The rate goes up as soon as the pipeline asks.
        let box = Box()
        let pipeline = TapPipeline(setRate: { box.rates.append($0) }, onDoubleTap: { box.taps.append($0) })
        var fast = false
        for (i, s) in idle.enumerated() {
            if !fast, i % 8 != 0 { continue }
            var a = s.a
            for (t0, g) in [(3.0, Float(0.03)), (3.22, 0.03)] where s.t >= t0 && s.t < t0 + 0.12 {
                let dt = s.t - t0
                let wave = g * Float(exp(-dt / 0.015) * sin(2 * .pi * 120 * dt))
                a += SIMD3(0.3 * wave, 0.2 * wave, wave)
            }
            pipeline.process(t: s.t, a)
            fast = box.rates.last == .active
        }
        XCTAssertEqual(box.rates.first, .active, "the first knock raised the rate")
        XCTAssertEqual(box.rates.last, .idle, "and it fell back after the palm rest went quiet")
        XCTAssertEqual(box.taps.count, 1)
        XCTAssertEqual(box.taps.first ?? 0, 3.0, accuracy: 0.02, "the first knock, caught at 100 Hz")
    }

    func testRealIdleStaysAt100Hz() throws {
        let box = Box()
        let pipeline = TapPipeline(setRate: { box.rates.append($0) }, onDoubleTap: { box.taps.append($0) })
        for (i, s) in try TapDetectorTests.load("idle").enumerated() where i % 8 == 0 { pipeline.process(t: s.t, s.a) }
        XCTAssertEqual(box.rates, [], "a still Mac never wakes the sensor to full rate")
        XCTAssertEqual(box.taps, [])
    }
}
