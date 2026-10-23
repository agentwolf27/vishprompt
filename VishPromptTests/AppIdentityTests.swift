import XCTest
@testable import VishPrompt

/// The app is called VishPrompt, but its identity must not move: macOS ties the Microphone
/// and Accessibility grants to the bundle identifier, and history, Keychain and settings live
/// under the old internal name. Changing either without a migration would silently reset all
/// of them.
final class AppIdentityTests: XCTestCase {
    func testTheVisibleNameIsVishPrompt() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "VishPrompt")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "VishPrompt")
        let microphone = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        XCTAssertTrue(microphone?.hasPrefix("VishPrompt") ?? false)
    }

    func testTheIdentityIsUnchanged() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.vish.visprflow", "changing this makes macOS ask for every permission again")
    }
}
