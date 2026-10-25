import simd
import XCTest
@testable import VishPrompt

/// Gestures 3: the Palm rest card (gesture rows, sensitivity, a Test area that lights up the
/// gesture it heard, and left/right calibration) renders in light and dark, and each control
/// drives the real setting.
@MainActor
final class PalmRestCardTests: XCTestCase {
    /// Taller than the other pages: Settings has five cards now.
    private let size = CGSize(width: 1120, height: 1000)

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "PalmRestCardTests-\(UUID())")!
    }

    private func library(_ store: UserDefaults? = nil) -> HomeLibrary {
        let library = HomeLibrary(queue: { nil }, defaults: store ?? defaults())
        library.page = .settings
        library.palmRestAvailable = true
        library.palmRestEnabled = true
        return library
    }

    private func shape(_ x: Float, _ y: Float, _ z: Float) -> KnockShape {
        let d = SIMD3<Float>(x, y, z)
        return KnockShape(direction: d / simd_length(d), energy: (d * d) / simd_length_squared(d), early: SIMD3(x == 0 ? 0 : (x < 0 ? -1 : 1), 1, 1))
    }

    /// A calibration that separates cleanly, for this Mac, so it reads back from the defaults.
    private func unlockedCalibration() throws -> SideCalibration {
        let left = (0..<10).map { i in shape(-0.4 - Float(i) * 0.01, 0.1, 0.9) }
        let right = (0..<10).map { i in shape(0.4 + Float(i) * 0.01, 0.1, 0.9) }
        return try XCTUnwrap(SideCalibration.measure(left: left, right: right, model: SideCalibration.hardwareModel))
    }

    /// The shapes of the knocks the detector hears in a recording.
    private func shapes(_ name: String) throws -> [KnockShape] {
        var detector = TapDetector()
        for s in try TapDetectorTests.load(name) { _ = detector.process(t: s.t, s.a) }
        return detector.heardShapes
    }

    /// Feeds a recording's knocks to a calibration run two at a time, as double taps arrive.
    private func feed(_ library: HomeLibrary, _ knocks: [KnockShape], until phase: SideCalibrationRun.Phase) {
        var rest = knocks[...]
        while library.calibrationRun?.phase == phase, rest.count >= 2 {
            library.calibrationHeard(Array(rest.prefix(2)), model: SideCalibration.hardwareModel)
            rest = rest.dropFirst(2)
        }
    }

    // MARK: Sensitivity

    func testNormalIsTheTunedDefaultAndTheOthersMoveOnlyTheOnsetThresholds() {
        var normal = TapDetector.Tuning()
        PalmSensitivity.normal.apply(to: &normal)
        XCTAssertEqual(normal, TapDetector.Tuning(), "every tap test was tuned on Normal")
        var light = TapDetector.Tuning()
        PalmSensitivity.light.apply(to: &light)
        var firm = TapDetector.Tuning()
        PalmSensitivity.firm.apply(to: &firm)
        XCTAssertLessThan(light.minimumPeak, normal.minimumPeak)
        XCTAssertLessThan(normal.minimumPeak, firm.minimumPeak)
        XCTAssertLessThan(light.noiseMultiple, normal.noiseMultiple)
        XCTAssertLessThan(normal.noiseMultiple, firm.noiseMultiple)
        XCTAssertGreaterThan(firm.minimumPeak, 0.017, "Firm is above Vish's trackpad clicks (8-17 mg)")
        firm.minimumPeak = normal.minimumPeak
        firm.noiseMultiple = normal.noiseMultiple
        XCTAssertEqual(firm, normal, "nothing else changes")
    }

    func testSensitivityIsSavedAndRestartsTheSensorOncePerChange() {
        let store = defaults()
        let library = library(store)
        var restarts = 0
        library.onPalmGesturesChanged = { restarts += 1 }
        library.palmSensitivity = .firm
        library.palmSensitivity = .firm
        XCTAssertEqual(restarts, 1)
        XCTAssertEqual(PalmSensitivity.saved(in: store), .firm)
        XCTAssertEqual(PalmSensitivity.tuning(in: store).minimumPeak, 0.03)
        XCTAssertEqual(HomeLibrary(queue: { nil }, defaults: store).palmSensitivity, .firm, "read back on the next open")
    }

    func testFirmStillHearsVishsDoublesAndNothingFromHisClicks() throws {
        var tuning = TapDetector.Tuning()
        PalmSensitivity.firm.apply(to: &tuning)
        for (name, atLeast) in [("bed2/double-left", 5), ("bed2/double-right", 3)] {
            let result = TapDetectorTests.run(try TapDetectorTests.load(name), tuning: tuning)
            print("PROBE firm \(name): \(result.taps.count) doubles")
            XCTAssertGreaterThanOrEqual(result.taps.count, atLeast, name)
        }
        for name in ["bed1/clicks", "bed2/clicks", "bed1/typing", "bed2/single"] {
            XCTAssertEqual(TapDetectorTests.run(try TapDetectorTests.load(name), tuning: tuning).taps, [], name)
        }
    }

    // MARK: Rows and actions

    func testTheRowsFollowTheCalibration() throws {
        let library = library()
        XCTAssertEqual(library.visiblePalmGestures, [.double, .triple])
        XCTAssertEqual(library.palmCalibrationStatus, SideCalibration.notCalibrated)
        library.applyCalibration(try unlockedCalibration())
        XCTAssertEqual(library.visiblePalmGestures, [.doubleLeft, .doubleRight, .triple])
        XCTAssertTrue(library.palmCalibrationStatus.contains("told your sides apart"))
    }

    func testAPickerWritesTheRealSettingAndRestartsTheSensor() {
        let store = defaults()
        let library = library(store)
        var restarts = 0
        library.onPalmGesturesChanged = { restarts += 1 }
        library.setPalmAction(.editSelection, for: .triple)
        XCTAssertEqual(PalmGestureSettings(defaults: store).action(for: .triple), .editSelection)
        XCTAssertEqual(library.palmAction(for: .triple), .editSelection)
        XCTAssertEqual(restarts, 1)
    }

    func testAFirstUnlockGivesBothSidesTheEitherSideActionAndARecalibrationKeepsChoices() throws {
        let library = library()
        library.setPalmAction(.smartPaste, for: .double)
        library.applyCalibration(try unlockedCalibration())
        XCTAssertEqual(library.palmAction(for: .doubleLeft), .smartPaste)
        XCTAssertEqual(library.palmAction(for: .doubleRight), .smartPaste)
        library.setPalmAction(.dictate, for: .doubleRight)
        library.applyCalibration(try unlockedCalibration())
        XCTAssertEqual(library.palmAction(for: .doubleRight), .dictate, "a recalibration never overwrites a choice")
        XCTAssertEqual(library.palmAction(for: .doubleLeft), .smartPaste)
    }

    // MARK: Calibration runs

    func testTheRunCountsDownFiveDoublesASide() {
        var run = SideCalibrationRun()
        XCTAssertEqual(run.phase, .left)
        XCTAssertEqual(run.remainingDoubles, 5)
        XCTAssertEqual(run.instruction, "Double-tap the palm rest left of the trackpad: 5 more.")
        XCTAssertNil(run.add([shape(-1, 0, 1), shape(-1, 0, 1)], model: "Mac14,7"))
        XCTAssertEqual(run.remainingDoubles, 4)
        for _ in 0..<4 { _ = run.add([shape(-1, 0, 1), shape(-1, 0, 1)], model: "Mac14,7") }
        XCTAssertEqual(run.phase, .right)
        XCTAssertEqual(run.instruction, "Now the right side: 5 more.")
        for _ in 0..<4 { XCTAssertNil(run.add([shape(1, 0, 1), shape(1, 0, 1)], model: "Mac14,7")) }
        let result = run.add([shape(1, 0, 1), shape(1, 0, 1)], model: "Mac14,7")
        XCTAssertEqual(run.phase, .done)
        XCTAssertEqual(result?.taps, 20)
        XCTAssertEqual(result?.unlocked, true)
    }

    func testAnInseparableRunKeepsTheEitherSideRowAndSaysWhy() throws {
        let store = defaults()
        let library = library(store)
        var calibrating: [Bool] = []
        library.onSetCalibrating = { calibrating.append($0) }
        library.startCalibration()
        XCTAssertEqual(library.calibrationRun?.phase, .left)
        feed(library, try shapes("bed1/double-left"), until: .left)
        XCTAssertEqual(library.calibrationRun?.phase, .right)
        feed(library, try shapes("bed1/double-right"), until: .right)
        XCTAssertNil(library.calibrationRun, "the run ended on its own")
        XCTAssertEqual(calibrating, [true, false])
        XCTAssertEqual(library.visiblePalmGestures, [.double, .triple], "the side rows stay locked")
        XCTAssertTrue(library.calibrationNote?.contains(SideCalibration.lockedReason) == true, String(describing: library.calibrationNote))
        let saved = try XCTUnwrap(SideCalibration.saved(in: store), "a failed run is kept: it is the truth about this surface")
        XCTAssertFalse(saved.unlocked)
        XCTAssertEqual(library.palmAction(for: .doubleLeft), .off, "no side action was invented")
    }

    func testASeparableRunUnlocksTheSideRows() throws {
        let store = defaults()
        let library = library(store)
        library.setPalmAction(.dictate, for: .double)
        library.startCalibration()
        feed(library, try shapes("bed2/double-left"), until: .left)
        feed(library, try shapes("bed2/double-right"), until: .right)
        XCTAssertNil(library.calibrationRun)
        print("PROBE bed2 run: \(library.calibrationNote ?? "no note")")
        XCTAssertEqual(library.visiblePalmGestures, [.doubleLeft, .doubleRight, .triple])
        XCTAssertEqual(library.palmAction(for: .doubleLeft), .dictate)
        XCTAssertEqual(try XCTUnwrap(SideCalibration.saved(in: store)).unlocked, true)
    }

    // MARK: Routing while testing or calibrating

    func testTestModeShowsTheGestureAndRunsNothing() throws {
        let double = TapEvent.doubleTap(first: 1, at: 1.3)
        let triple = TapEvent.tripleTap(first: 1, at: 1.6)
        XCTAssertEqual(PalmRoute.resolve(double, shapes: [], calibration: nil, nearInput: false, testing: false, calibrating: false), .run(.double))
        XCTAssertEqual(PalmRoute.resolve(double, shapes: [], calibration: nil, nearInput: false, testing: true, calibrating: false), .test(.double))
        XCTAssertEqual(PalmRoute.resolve(triple, shapes: [], calibration: nil, nearInput: false, testing: true, calibrating: false), .test(.triple))
        XCTAssertEqual(PalmRoute.resolve(double, shapes: [], calibration: nil, nearInput: true, testing: true, calibrating: false), .nearInput, "the Test area says so too")
        let knocks = [shape(-0.4, 0.1, 0.9), shape(-0.4, 0.1, 0.9)]
        XCTAssertEqual(PalmRoute.resolve(double, shapes: knocks, calibration: nil, nearInput: false, testing: false, calibrating: true), .calibrate(knocks))
        XCTAssertEqual(PalmRoute.resolve(triple, shapes: knocks, calibration: nil, nearInput: false, testing: false, calibrating: true), .run(.triple), "calibration takes doubles only")
        let calibration = try unlockedCalibration()
        XCTAssertEqual(PalmRoute.resolve(double, shapes: knocks, calibration: calibration, nearInput: false, testing: true, calibrating: false), .test(.doubleLeft))
        XCTAssertEqual(PalmRoute.resolve(double, shapes: [shape(0, 0.1, 0.9)], calibration: calibration, nearInput: false, testing: false, calibrating: false), .sideUnclear)
        XCTAssertEqual(PalmTestResult.heard(.doubleLeft).text, "Heard: Double-tap left")
    }

    func testTheLibraryTellsTheSensorWhenTestingAndCalibratingStartAndStop() {
        let library = library()
        var testing: [Bool] = []
        var calibrating: [Bool] = []
        library.onSetPalmTesting = { testing.append($0) }
        library.onSetCalibrating = { calibrating.append($0) }
        library.startPalmTest()
        library.palmTestHeard(.heard(.double))
        XCTAssertEqual(library.palmHeard, .heard(.double))
        library.startCalibration()
        XCTAssertEqual(testing, [true, false], "a calibration takes over from a test")
        XCTAssertEqual(calibrating, [true])
        library.page = .history
        XCTAssertEqual(calibrating, [true, false], "leaving Settings ends it")
        library.page = .settings
        library.startPalmTest()
        library.palmRestEnabled = false
        XCTAssertEqual(testing, [true, false, true, false], "turning the palm rest off ends it")
        XCTAssertNil(library.palmHeard)
    }

    // MARK: Snapshots

    func testTheCardRendersInBothThemes() throws {
        for dark in [false, true] {
            let library = library()
            if dark {
                // Calibrated, but this surface can't tell the sides apart; a new run is under way.
                var locked = try unlockedCalibration()
                locked.accuracy = 0.65
                library.applyCalibration(locked)
                library.startCalibration()
                for _ in 0..<3 { library.calibrationHeard([shape(-1, 0, 1), shape(-1, 0, 1)], model: SideCalibration.hardwareModel) }
                library.palmSensitivity = .firm
            } else {
                // Calibrated and unlocked, with the Test area lit by a left double-tap.
                library.applyCalibration(try unlockedCalibration())
                library.setPalmAction(.smartPaste, for: .doubleRight)
                library.setPalmAction(.fixScreenshot, for: .triple)
                library.startPalmTest()
                library.palmTestHeard(.heard(.doubleLeft))
            }
            let bitmap = try XCTUnwrap(HomeSnapshot.capture(HomeView(library: library, reuse: HistoryReuse()), size: size, dark: dark, name: "settings-palm"))
            let theme = dark ? HomeTheme.dark : HomeTheme.light
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 1100, y: 990, viewSize: size), theme.background), "\(dark ? "dark" : "light") background")
            XCTAssertTrue(HomeSnapshot.matches(HomeSnapshot.pixel(bitmap, x: 8, y: 500, viewSize: size), theme.sidebar), "\(dark ? "dark" : "light") sidebar")
        }
    }
}
