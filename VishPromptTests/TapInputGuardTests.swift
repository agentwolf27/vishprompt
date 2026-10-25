import XCTest
@testable import VishPrompt

/// A trackpad tap, hold, scroll or Force Touch press near the knocks stops a double tap, as key
/// presses and clicks already did. Vish: "the palm rest tap works on the mouse pad when i double
/// tap and hold it".
final class TapInputGuardTests: XCTestCase {
    func testTrackpadTouchForceTouchAndScrollOpenTheWindowAlongsideKeysAndClicks() {
        let watched = Set(TapInputGuard.eventTypes.map(\.raw))
        XCTAssertTrue(watched.isSuperset(of: [10, 1, 3, 25]), "keys and clicks, as before")
        XCTAssertTrue(watched.contains(29), "trackpad touch (gesture): a tap or hold raises no click")
        XCTAssertTrue(watched.contains(34), "Force Touch pressure: its Taptic Engine is a clean knock")
        XCTAssertTrue(watched.contains(22), "scroll")
        XCTAssertTrue(watched.isSuperset(of: [2, 4]), "a click's release thumps too")
        XCTAssertFalse(watched.contains(5), "moving an external mouse does not shake the palm rest")
    }

    func testTheMostRecentOfAnyWatchedInputCounts() {
        let onlyTouch: (UInt32) -> Double = { $0 == 29 ? 0.05 : 300 }
        XCTAssertEqual(TapInputGuard.lastInputAge(onlyTouch), 0.05, "a finger resting on the trackpad alone is enough")
        let onlyPressure: (UInt32) -> Double = { $0 == 34 ? 0.2 : 300 }
        XCTAssertEqual(TapInputGuard.lastInputAge(onlyPressure), 0.2)
        XCTAssertEqual(TapInputGuard.lastInputAge { _ in 300 }, 300)
    }

    func testTheWindowRunsFromJustBeforeTheFirstKnockUntilNow() {
        XCTAssertTrue(TapInputGuard.touched(lastInput: 10.0 - 0.39, firstKnock: 10.0), "0.39 s before")
        XCTAssertFalse(TapInputGuard.touched(lastInput: 10.0 - 0.41, firstKnock: 10.0), "0.41 s before is too early to be the cause")
        XCTAssertTrue(TapInputGuard.touched(lastInput: 10.3, firstKnock: 10.0), "between the knocks, or after")
    }

    func testTheSystemAnswersForTheTouchAndPressureTypes() {
        for type in [UInt32(29), 34] {
            let age = TapInputGuard.systemAge(type)
            XCTAssertTrue(age.isFinite && age >= 0, "type \(type): \(age)")
        }
    }
}
