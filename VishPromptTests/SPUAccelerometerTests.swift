import XCTest
@testable import VishPrompt

/// Tap 1: the accelerometer's reports parse to g, and nothing else parses at all.
final class SPUAccelerometerTests: XCTestCase {
    private func report(x: Int32, y: Int32, z: Int32, length: Int = AccelReport.length) -> [UInt8] {
        var bytes = [UInt8](repeating: 0xAA, count: length)
        for (offset, value) in [(6, x), (10, y), (14, z)] where offset + 4 <= length {
            withUnsafeBytes(of: value.littleEndian) { for i in 0..<4 { bytes[offset + i] = $0[i] } }
        }
        return bytes
    }

    func testAReportParsesToG() throws {
        let bytes = report(x: 65536 / 4, y: -65536 / 2, z: -65536)
        let g = try XCTUnwrap(bytes.withUnsafeBytes { AccelReport.parse($0) })
        XCTAssertEqual(g, SIMD3<Float>(0.25, -0.5, -1))
    }

    func testOnlyA22ByteReportCounts() {
        XCTAssertNil(report(x: 1, y: 1, z: 1, length: 21).withUnsafeBytes { AccelReport.parse($0) })
        XCTAssertNil(report(x: 1, y: 1, z: 1, length: 23).withUnsafeBytes { AccelReport.parse($0) })
        XCTAssertNil([UInt8]().withUnsafeBytes { AccelReport.parse($0) })
    }

    func testTheTwoRatesAskTheDriverForTheRightInterval() {
        XCTAssertEqual(SPUAccelerometer.Rate.active.intervalMicroseconds, 1250, "800 Hz")
        XCTAssertEqual(SPUAccelerometer.Rate.idle.intervalMicroseconds, 10_000, "100 Hz")
    }

}
