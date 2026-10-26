import XCTest
@testable import VishPrompt

/// Tap 3: a palm-rest double tap starts hands-free recording through the gesture machine, and a
/// second one, the trigger, Escape or silence ends it. Off by default, sampled only when it may.
final class ChassisTapGestureTests: XCTestCase {
    func testADoubleTapStartsHandsFreeAndASecondEndsIt() {
        var g = HotkeyGesture()
        XCTAssertEqual(g.chassisTap(at: 1), [.startCapture, .lockedOn])
        XCTAssertTrue(g.isLocked)
        XCTAssertTrue(g.startedByTap)
        XCTAssertEqual(g.chassisTap(at: 5), [.finishCapture(modifiers: .none, locked: true)])
        XCTAssertFalse(g.isRecording)
    }

    func testItWorksWhateverTheTriggersOwnMode() {
        for mode in HotkeyMode.allCases {
            var g = HotkeyGesture(config: .init(mode: mode))
            XCTAssertEqual(g.chassisTap(at: 1), [.startCapture, .lockedOn], "\(mode)")
            XCTAssertEqual(g.chassisTap(at: 3), [.finishCapture(modifiers: .none, locked: true)], "\(mode)")
        }
    }

    func testATapNeverCutsAHeldDictationShort() {
        var g = HotkeyGesture()
        XCTAssertEqual(g.handle(.triggerDown(at: 0, modifiers: .none)), .startCapture)
        XCTAssertEqual(g.chassisTap(at: 1), [], "the hold is the user's; a tap during it is a bump")
        XCTAssertEqual(g.handle(.triggerUp(at: 2, modifiers: .none)), .finishCapture(modifiers: .none, locked: false))
        XCTAssertFalse(g.startedByTap)
    }

    func testTheTriggerKeyAlsoEndsATapSession() {
        var g = HotkeyGesture()
        _ = g.chassisTap(at: 1)
        XCTAssertEqual(g.handle(.triggerDown(at: 4, modifiers: .none)), .none)
        XCTAssertEqual(g.handle(.triggerUp(at: 4.1, modifiers: .none)), .finishCapture(modifiers: .none, locked: true))
    }

    func testSilenceAndEscapeEndATapSession() {
        var g = HotkeyGesture()
        _ = g.chassisTap(at: 1)
        XCTAssertEqual(g.handle(.silenceTimeout), .finishCapture(modifiers: .none, locked: true))
        _ = g.chassisTap(at: 10)
        XCTAssertEqual(g.handle(.escape), .discardCapture(reason: .escape))
    }

    func testADoubleTapEndsAHandsFreeSessionTheKeyStarted() {
        var g = HotkeyGesture()
        _ = g.handle(.triggerDown(at: 0, modifiers: .none))
        _ = g.handle(.triggerUp(at: 0.1, modifiers: .none))
        _ = g.handle(.triggerDown(at: 0.3, modifiers: .none))
        XCTAssertEqual(g.handle(.triggerUp(at: 0.4, modifiers: .none)), .lockedOn)
        XCTAssertFalse(g.startedByTap)
        XCTAssertEqual(g.chassisTap(at: 3), [.finishCapture(modifiers: .none, locked: true)])
    }

    func testTheNextKeyDictationIsNotMarkedAsATap() {
        var g = HotkeyGesture()
        _ = g.chassisTap(at: 1)
        _ = g.chassisTap(at: 2)
        _ = g.handle(.triggerDown(at: 5, modifiers: .none))
        XCTAssertFalse(g.startedByTap)
    }

    // MARK: The capsule

    func testTheCapsuleSaysATapStartedItAndHowToStop() throws {
        let state = HUDState.listening(level: 0.3, seconds: 2, locked: true)
        let tap = try XCTUnwrap(CapsuleModel.make(state, context: HUDContext(triggerName: "fn", startedByTap: true)))
        XCTAssertEqual(tap.status, "Started by a tap · stops when you pause · esc")
        let key = try XCTUnwrap(CapsuleModel.make(state, context: HUDContext(triggerName: "fn")))
        XCTAssertEqual(key.status, "Hands-free · stops when you pause · esc")
    }

    // MARK: When the sensor is sampled

    private let on = ChassisTapPower(sensorPresent: true, enabled: true, dictationRunning: true, batteryPercent: 80, onBattery: true)

    func testItSamplesOnlyWhenPresentEnabledAndRunning() {
        XCTAssertTrue(on.shouldSample)
        for change in [{ (p: inout ChassisTapPower) in p.sensorPresent = false },
                       { $0.enabled = false },
                       { $0.dictationRunning = false }] {
            var p = on
            change(&p)
            XCTAssertFalse(p.shouldSample, p.reason)
        }
    }

    func testItStopsOnLockDisplaySleepSystemSleepAndLowBattery() {
        let stops: [(String, (inout ChassisTapPower) -> Void)] = [
            ("screen locked", { $0.screenLocked = true }),
            ("display asleep", { $0.displayAsleep = true }),
            ("Mac asleep", { $0.systemAsleep = true }),
            ("battery under 10%", { $0.batteryPercent = 9 }),
        ]
        for (reason, change) in stops {
            var p = on
            change(&p)
            XCTAssertFalse(p.shouldSample)
            XCTAssertEqual(p.reason, reason)
        }
    }

    func testLowBatteryOnThePowerAdapterStillSamples() {
        var p = on
        p.batteryPercent = 5
        p.onBattery = false
        XCTAssertTrue(p.shouldSample)
        p.batteryPercent = nil
        p.onBattery = true
        XCTAssertTrue(p.shouldSample, "a Mac that reports no charge is not treated as flat")
        p.batteryPercent = 10
        XCTAssertTrue(p.shouldSample, "the floor is under 10%, not at it")
    }

    @MainActor
    func testItIsOffByDefault() {
        let defaults = UserDefaults(suiteName: "ChassisTapGestureTests-\(UUID())")!
        let trigger = ChassisTapTrigger(defaults: defaults) { _ in }
        trigger.setDictationRunning(true)
        XCTAssertFalse(trigger.isSampling, "nothing is read until the user turns it on")
        XCTAssertFalse(defaults.bool(forKey: ChassisTapTrigger.enabledKey))
        trigger.setDictationRunning(false)
    }
}
