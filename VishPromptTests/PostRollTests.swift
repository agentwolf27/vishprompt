import AVFoundation
import XCTest
@testable import VishPrompt

/// Speed S1b: the post-roll ends when the audio has arrived, not after a fixed 120 ms.
final class PostRollTests: XCTestCase {
    private let keyUp: UInt64 = 1_000_000_000
    private func ticks(_ seconds: TimeInterval) -> UInt64 { AVAudioTime.hostTime(forSeconds: seconds) }

    func testItWaitsUntilAudioPastKeyUpHasArrived() {
        // The newest buffer ends before key-up: the last word is still in flight.
        XCTAssertFalse(AudioCapture.postRollComplete(lastBufferEnd: keyUp - ticks(0.01), keyUp: keyUp, waited: 0.01))
        // It covers key-up but not the tail yet.
        XCTAssertFalse(AudioCapture.postRollComplete(lastBufferEnd: keyUp + ticks(0.02), keyUp: keyUp, waited: 0.02))
        // It covers key-up plus the 40 ms tail.
        XCTAssertTrue(AudioCapture.postRollComplete(lastBufferEnd: keyUp + ticks(0.045), keyUp: keyUp, waited: 0.03))
    }

    func testTheCeilingStillHoldsWithoutTimestamps() {
        XCTAssertFalse(AudioCapture.postRollComplete(lastBufferEnd: nil, keyUp: keyUp, waited: 0.05))
        XCTAssertTrue(AudioCapture.postRollComplete(lastBufferEnd: nil, keyUp: keyUp, waited: AudioCapture.postRollDuration))
    }

    func testAStalledEngineCannotHoldTheDictation() {
        XCTAssertTrue(AudioCapture.postRollComplete(lastBufferEnd: keyUp - ticks(1), keyUp: keyUp, waited: 0.121))
    }

    func testTheExpectedWaitIsWellUnderTheOldFixedOne() {
        XCTAssertLessThan(AudioCapture.expectedPostRoll, AudioCapture.postRollDuration)
        XCTAssertGreaterThanOrEqual(AudioCapture.expectedPostRoll, AudioCapture.postRollTail)
    }
}
