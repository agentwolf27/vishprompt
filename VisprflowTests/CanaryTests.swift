import XCTest

/// Fails or skips on request, so the Makefile can prove its test targets are able to fail.
///
/// `make verify-test-can-fail` and `make verify-test-class-can-fail` set
/// `VISPRFLOW_CANARY` and expect the run to fail. Without the variable this passes, so it is
/// harmless in an ordinary `make test`.
final class CanaryTests: XCTestCase {
    func testCanary() throws {
        switch ProcessInfo.processInfo.environment["VISPRFLOW_CANARY"] {
        case "fail":
            XCTFail("canary asked to fail")
        case "skip":
            throw XCTSkip("canary asked to skip")
        default:
            break
        }
    }
}
