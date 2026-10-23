import simd
import XCTest
@testable import VishPrompt

/// The real palm-rest accelerometer. Run with `make verify-sensor` on an M2-or-later MacBook.
///
/// Gated because it needs that hardware, and an ordinary `make test` runs on Macs without it.
final class SPUAccelerometerLiveTests: XCTestCase {
    private static let isEnabled = ProcessInfo.processInfo.environment["VISHPROMPT_SENSOR"] == "1"

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.isEnabled, "set VISHPROMPT_SENSOR=1 (make verify-sensor) to read the real sensor")
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [(Double, SIMD3<Float>)] = []
        func add(_ t: Double, _ a: SIMD3<Float>) { lock.withLock { samples.append((t, a)) } }
        func take() -> [(Double, SIMD3<Float>)] { lock.withLock { defer { samples = [] }; return samples } }
    }

    private func collect(_ sensor: SPUAccelerometer, _ collector: Collector, seconds: Double) -> [(Double, SIMD3<Float>)] {
        _ = collector.take()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
        return collector.take()
    }

    func testTheSensorStreamsAtBothRatesAndReadsAbout1GAtRest() throws {
        XCTAssertTrue(SPUAccelerometer.isAvailable, "this check needs an M2-or-later MacBook")
        let sensor = SPUAccelerometer()
        let collector = Collector()
        sensor.onSample = { collector.add($0, $1) }
        try sensor.start(rate: .active)
        defer { sensor.stop() }

        // The first half second lets the driver settle at the new rate.
        _ = collect(sensor, collector, seconds: 0.5)
        let active = collect(sensor, collector, seconds: 2)
        let activeRate = Double(active.count) / 2
        XCTAssertGreaterThan(activeRate, 500, "asked for 800 Hz")
        XCTAssertLessThan(activeRate, 1000)

        let magnitudes = active.map { Double(simd_length($0.1)) }.sorted()
        let median = magnitudes[magnitudes.count / 2]
        XCTAssertEqual(median, 1.0, accuracy: 0.1, "at rest the sensor feels gravity, 1 g")
        let times = active.map(\.0)
        XCTAssertEqual(times, times.sorted(), "timestamps only move forward")

        sensor.setRate(.idle)
        _ = collect(sensor, collector, seconds: 0.5)
        let idle = collect(sensor, collector, seconds: 3)
        let idleRate = Double(idle.count) / 3
        XCTAssertGreaterThan(idleRate, 50, "asked for 100 Hz; a parked sensor must be re-armed")
        XCTAssertLessThan(idleRate, 200)

        print("PROBE sensor: active \(Int(activeRate)) Hz, idle \(Int(idleRate)) Hz, median \(String(format: "%.3f", median)) g")
        sensor.stop()
        XCTAssertFalse(sensor.isRunning)
        XCTAssertTrue(collect(sensor, collector, seconds: 0.3).isEmpty, "nothing arrives after stop")
    }
}
