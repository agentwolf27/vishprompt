import XCTest
@testable import VishPrompt

/// UI v2.5: the overlay's surface is one choice, glass where it exists and the thin material
/// everywhere else.
final class SurfaceStyleTests: XCTestCase {
    func testGlassOnlyWithBothTheSDKAndMacOS26() {
        XCTAssertEqual(SurfaceStyle.resolve(osMajorVersion: 26, sdkHasGlass: true), .glass)
        XCTAssertEqual(SurfaceStyle.resolve(osMajorVersion: 27, sdkHasGlass: true), .glass)
        XCTAssertEqual(SurfaceStyle.resolve(osMajorVersion: 26, sdkHasGlass: false), .material,
                       "built with an older Xcode, macOS 26 still gets the material")
        XCTAssertEqual(SurfaceStyle.resolve(osMajorVersion: 15, sdkHasGlass: true), .material,
                       "a glass-capable build on macOS 15 falls back")
        XCTAssertEqual(SurfaceStyle.resolve(osMajorVersion: 15, sdkHasGlass: false), .material)
    }

    func testThisBuildDecidesFromTheRealSystemAndSDK() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        XCTAssertEqual(SurfaceStyle.current, SurfaceStyle.resolve(osMajorVersion: major, sdkHasGlass: SurfaceStyle.sdkHasGlass))
        if major < 26 {
            XCTAssertEqual(SurfaceStyle.current, .material, "below macOS 26 there is no glass to draw")
        }
    }

    func testIncreaseContrastGivesTheMaterialAVisibleEdge() {
        XCTAssertGreaterThan(SurfaceStyle.borderOpacity(increasedContrast: true),
                             SurfaceStyle.borderOpacity(increasedContrast: false) * 3)
    }
}
