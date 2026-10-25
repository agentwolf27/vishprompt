import XCTest
@testable import VishPrompt

/// The tap trigger's running cost on the real sensor, and that it stops when it should. Run with
/// `make verify-tap-cpu` on an M2-or-later MacBook.
final class ChassisTapCPUTests: XCTestCase {
    private static let isEnabled = ProcessInfo.processInfo.environment["VISHPROMPT_TAP_CPU"] == "1"

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.isEnabled, "set VISHPROMPT_TAP_CPU=1 (make verify-tap-cpu) to measure the real sensor")
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Percent of one core the whole process used over `seconds`.
    private func measure(seconds: Double) -> Double {
        let cpu0 = cpuSeconds(), wall0 = Date()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
        return (cpuSeconds() - cpu0) / Date().timeIntervalSince(wall0) * 100
    }

    @MainActor
    func testIdleSamplingCostsUnderOnePercentOfACoreAndStopsOnLock() throws {
        let defaults = UserDefaults(suiteName: "ChassisTapCPUTests-\(UUID())")!
        defaults.set(true, forKey: ChassisTapTrigger.enabledKey)
        let trigger = ChassisTapTrigger(defaults: defaults) { _ in }

        // The same process with the sensor off, then on: the difference is the trigger's cost.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
        let baseline = measure(seconds: 8)
        trigger.setDictationRunning(true)
        XCTAssertTrue(trigger.isSampling)
        defer { trigger.setDictationRunning(false) }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
        let sampling = measure(seconds: 8)
        let cost = sampling - baseline
        print(String(format: "PROBE tap cpu: %.2f%% of one core sampling, %.2f%% without, %.2f%% for the trigger", sampling, baseline, cost))
        XCTAssertLessThan(cost, 1.0)

        trigger.update { $0.screenLocked = true }
        XCTAssertFalse(trigger.isSampling, "a locked screen stops the sensor")
        trigger.update { $0.screenLocked = false }
        XCTAssertTrue(trigger.isSampling, "and unlocking starts it again")
        trigger.update { $0.batteryPercent = 5; $0.onBattery = true }
        XCTAssertFalse(trigger.isSampling, "low battery stops it")
    }
}
