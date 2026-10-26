import XCTest
@testable import VishPrompt

/// Unwanted sessions 4: the false double-tap rate is measured on recordings of the Mac left
/// alone, the detector passes only under one an hour over at least two hours of them, and until
/// then the Palm rest card warns in numbers and the setting is off by default.
final class TapFalseTriggerTests: XCTestCase {
    /// Every `idle*.csv` under Fixtures/taps, as "<surface>/<name>" or "<name>", sorted.
    private func idleFixtures() throws -> [String] {
        let root = try XCTUnwrap(Bundle(for: TapDetectorTests.self).resourceURL).appending(path: "Fixtures/taps")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        return files
            .filter { $0.pathExtension == "csv" && $0.deletingPathExtension().lastPathComponent.hasPrefix("idle") }
            .map { String($0.deletingPathExtension().path.dropFirst(root.path.count + 1)) }
            .sorted()
    }

    /// The gate's numbers, from the files: replayed as the app samples it, with its input veto.
    private func measure() throws -> PalmRestGate.Measurement {
        var seconds = 0.0
        var fired = 0
        var names: [String] = []
        for name in try idleFixtures() {
            let samples = try TapDetectorTests.load(name)
            guard let first = samples.first?.t, let last = samples.last?.t else { continue }
            names.append(name)
            seconds += last - first
            fired += TapRecordingTests.liveAfterVeto(samples).count
        }
        return PalmRestGate.Measurement(fixtures: names, seconds: seconds, falseDoubles: fired)
    }

    func testThePinnedMeasurementMatchesTheRecordings() throws {
        let now = try measure()
        print(String(format: "PROBE idle recordings: %@, %.1f s, %d false double taps", now.fixtures.joined(separator: " "), now.seconds, now.falseDoubles))
        XCTAssertEqual(now.fixtures, PalmRestGate.measured.fixtures, "the recordings changed: update PalmRestGate.measured")
        XCTAssertEqual(now.falseDoubles, PalmRestGate.measured.falseDoubles, "the detector or the recordings changed: update PalmRestGate.measured")
        XCTAssertEqual(now.seconds, PalmRestGate.measured.seconds, accuracy: 2, "update PalmRestGate.measured.seconds")
    }

    func testTheGatePassesOnlyUnderOneAnHourOverAtLeastTwoHours() {
        func passes(seconds: Double, fired: Int) -> Bool {
            let hours = seconds / 3600
            return hours >= PalmRestGate.requiredHours && Double(fired) / hours < PalmRestGate.maximumPerHour
        }
        XCTAssertFalse(passes(seconds: 20, fired: 0), "twenty seconds proves nothing, even clean")
        XCTAssertFalse(passes(seconds: 2 * 3600, fired: 2), "one an hour is not under one an hour")
        XCTAssertTrue(passes(seconds: 2 * 3600, fired: 1))
        XCTAssertTrue(passes(seconds: 3 * 3600, fired: 0))
        XCTAssertFalse(passes(seconds: 1.9 * 3600, fired: 0), "not long enough yet")
    }

    func testTodayTheGateFailsAndTheCardSaysSoInNumbers() throws {
        XCTAssertFalse(PalmRestGate.passed, "twenty seconds of recordings with a real double knock in them")
        let warning = try XCTUnwrap(PalmRestGate.warning)
        XCTAssertTrue(warning.contains("0 minutes") || warning.contains("1 minute"), warning)
        XCTAssertTrue(warning.contains("happened 1 time"), warning)
        XCTAssertTrue(warning.contains("under 1 an hour over at least 2 hours"), warning)
        XCTAssertTrue(warning.contains("waits in the preview card"), warning)
    }

    @MainActor
    func testThePalmRestStaysOffByDefault() {
        let defaults = UserDefaults(suiteName: "TapFalseTriggerTests-\(UUID())")!
        XCTAssertFalse(defaults.bool(forKey: ChassisTapTrigger.enabledKey))
        XCTAssertEqual(PalmGestureSettings(defaults: defaults).action(for: .double), .off, "and nothing is assigned until it is turned on")
    }
}
