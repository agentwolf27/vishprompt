import XCTest
@testable import Visprflow

final class NumberCheckTests: XCTestCase {
    private let clip = "Q3 numbers: signups were 1240 this quarter vs 980 last quarter, churn ended at 3.1 percent, and we agreed to run the pricing test starting Monday"

    func testAFaithfulRewritePasses() {
        let check = NumberCheck.compare(clip: clip, output: "• Q3 signups: 1,240 (up from 980)\n• Churn: 3.1%\n• Next: pricing test starts Monday")
        XCTAssertTrue(check.passed)
        XCTAssertEqual(check.source, 3, "Q3 is a name, not a number")
        XCTAssertEqual(check.summary, "Numbers checked: all 3 from your clip are in the result, none added.")
    }

    func testAChangedNumberFails() {
        let check = NumberCheck.compare(clip: clip, output: "• Signups: 1,420 (up from 980)\n• Churn: 3.1%")
        XCTAssertFalse(check.passed)
        XCTAssertEqual(check.added, ["1420"])
        XCTAssertEqual(check.dropped, ["1240"])
    }

    func testADroppedNumberIsReportedNotRejected() {
        let check = NumberCheck.compare(clip: clip, output: "Signups hit 1,240 and churn was 3.1%.")
        XCTAssertTrue(check.passed)
        XCTAssertEqual(check.dropped, ["980"])
        XCTAssertTrue(check.summary?.contains("980") ?? false)
    }

    func testReformattedDatesAreNotInventions() {
        let check = NumberCheck.compare(clip: "ship on 2026-10-23", output: "Ship on 23 October 2026")
        XCTAssertTrue(check.passed, "every digit run in the clip may appear: \(check.added)")
    }

    func testNumbersFromTheInstructionAreAllowed() {
        let check = NumberCheck.compare(clip: "the meeting", instruction: "say it moved to 3", output: "The meeting moved to 3.")
        XCTAssertTrue(check.passed)
    }

    func testPlaceholdersAreNotNumbers() {
        XCTAssertEqual(NumberCheck.numbers(in: "key ⟦vf-ab2c-1⟧ and ⟦vf-ab2c-12⟧"), [])
    }

    func testCanonicalForms() {
        XCTAssertEqual(NumberCheck.canonical("1,240"), "1240")
        XCTAssertEqual(NumberCheck.canonical("3.10"), "3.1")
        XCTAssertEqual(NumberCheck.canonical("2.0"), "2")
        XCTAssertEqual(NumberCheck.canonical("007"), "7")
        XCTAssertEqual(NumberCheck.canonical("0.5"), "0.5")
    }

    func testNoNumbersMeansNoSummary() {
        XCTAssertNil(NumberCheck.compare(clip: "hello there", output: "Hello there.").summary)
    }
}
