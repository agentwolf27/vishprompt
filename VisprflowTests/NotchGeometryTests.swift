import AppKit
import SwiftUI
import XCTest
@testable import Visprflow

/// UI v2.3: lobes beside a real notch, a free capsule everywhere else, never a drawn notch.
/// Geometry is synthetic (a 14-inch MacBook Pro's): this Mac's display has no notch.
@MainActor
final class NotchGeometryTests: XCTestCase {
    private let macBook = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let left = CGRect(x: 0, y: 950, width: 663, height: 32)
    private let right = CGRect(x: 849, y: 950, width: 663, height: 32)

    func testANotchedDisplayGetsLobesAroundTheHousing() throws {
        let notch = try XCTUnwrap(NotchGeometry.layout(screenFrame: macBook, auxiliaryTopLeft: left, auxiliaryTopRight: right, safeAreaTop: 32))
        XCTAssertEqual(notch.notchWidth, 186)
        XCTAssertEqual(notch.notchMidX, 756)
        XCTAssertEqual(notch.barHeight, 32)
        XCTAssertEqual(notch.totalWidth, 180 * 2 + 186)
        let origin = NotchGeometry.origin(panelSize: CGSize(width: notch.totalWidth, height: 80), screenFrame: macBook,
                                          visibleFrame: macBook, notch: notch, gapBelowMenuBar: 8)
        XCTAssertEqual(origin.x + notch.totalWidth / 2, 756, "centred on the housing")
        XCTAssertEqual(origin.y + 80, 982, "the lobes start at the top of the screen, in the menu bar strip")
    }

    func testAnExternalDisplayGetsTheFreeCapsuleAndNoNotch() {
        let display = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        XCTAssertNil(NotchGeometry.layout(screenFrame: display, auxiliaryTopLeft: nil, auxiliaryTopRight: nil, safeAreaTop: 0))
        let visible = CGRect(x: 1512, y: 0, width: 2560, height: 1415)
        let origin = NotchGeometry.origin(panelSize: CGSize(width: 300, height: 36), screenFrame: display, visibleFrame: visible, notch: nil, gapBelowMenuBar: 8)
        XCTAssertEqual(origin.x, 1512 + 1280 - 150)
        XCTAssertEqual(origin.y, 1415 - 36 - 8, "8 pt under the menu bar")
    }

    func testHalfAnAnswerIsNoNotch() {
        XCTAssertNil(NotchGeometry.layout(screenFrame: macBook, auxiliaryTopLeft: left, auxiliaryTopRight: right, safeAreaTop: 0),
                     "no safe-area inset, no notch, whatever else is reported")
        XCTAssertNil(NotchGeometry.layout(screenFrame: macBook, auxiliaryTopLeft: left, auxiliaryTopRight: nil, safeAreaTop: 32))
        XCTAssertNil(NotchGeometry.layout(screenFrame: macBook, auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 100, height: 32),
                                          auxiliaryTopRight: right, safeAreaTop: 32), "no room for a lobe")
    }

    func testAFullScreenAppPutsTheCapsuleAtTheTopEdge() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NotchGeometry.origin(panelSize: CGSize(width: 300, height: 36), screenFrame: display, visibleFrame: display, notch: nil, gapBelowMenuBar: 8)
        XCTAssertEqual(origin.y, 900 - 36 - 8)
    }

    func testRenderLobesSnapshot() throws {
        guard let directory = ProcessInfo.processInfo.environment["VISPRFLOW_SNAPSHOTS"] else { return }
        let notch = try XCTUnwrap(NotchGeometry.layout(screenFrame: macBook, auxiliaryTopLeft: left, auxiliaryTopRight: right, safeAreaTop: 32))
        let context = HUDContext(mode: .dictate, app: "Slack", takeSeconds: nil, triggerName: "fn", notch: notch)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try HUDSnapshot.write(HUDView(state: .listening(level: 0.12, seconds: 7, locked: false, partial: "hey can you send me the figma link", app: "Slack"), context: context),
                              to: URL(filePath: directory).appending(path: "notch-1-listening.png"))
        try HUDSnapshot.write(HUDView(state: .compiling(partial: "", provider: "via your Claude subscription"),
                                      context: HUDContext(mode: .dictate, app: "Claude Code", takeSeconds: 14, triggerName: "fn", notch: notch)),
                              to: URL(filePath: directory).appending(path: "notch-2-rewriting.png"))
    }
}
