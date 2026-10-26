import GRDB
import XCTest
@testable import VishPrompt

/// Unwanted sessions 1: every row and the log say what started a dictation, and every accepted
/// palm gesture is logged with its timing and knock strengths.
final class StartSourceTests: XCTestCase {
    func testEachPalmGestureHasItsOwnSourceAndTheKeysHaveTheirs() {
        XCTAssertEqual(StartSource(palm: .double), .palmDouble)
        XCTAssertEqual(StartSource(palm: .triple), .palmTriple)
        XCTAssertEqual(StartSource(palm: .doubleLeft), .palmLeft)
        XCTAssertEqual(StartSource(palm: .doubleRight), .palmRight)
        XCTAssertTrue(StartSource.allCases.filter(\.isPalm).count == 4)
        XCTAssertFalse(StartSource.fnHold.isPalm)
        XCTAssertFalse(StartSource.fnDoubleTap.isPalm)
        XCTAssertEqual(Set(StartSource.allCases.map(\.rawValue)).count, StartSource.allCases.count, "distinct stored values")
    }

    func testTheGestureMachineSaysWhetherATapStartedTheSession() {
        var byTap = HotkeyGesture()
        _ = byTap.chassisTap(at: 1)
        XCTAssertTrue(byTap.startedByTap)
        var byKey = HotkeyGesture()
        _ = byKey.handle(.triggerDown(at: 0, modifiers: .none))
        XCTAssertFalse(byKey.startedByTap)
        _ = byKey.handle(.triggerUp(at: 0.1, modifiers: .none))
        _ = byKey.handle(.triggerDown(at: 0.3, modifiers: .none))
        XCTAssertEqual(byKey.handle(.triggerUp(at: 0.4, modifiers: .none)), .lockedOn)
        XCTAssertFalse(byKey.startedByTap, "a double-tap of the key is still the key")
    }

    func testARowKeepsItsStartSourceAndOlderRowsHaveNone() throws {
        let queue = try DatabaseQueue()
        var migrator = Database.migrator
        try migrator.migrate(queue, upTo: "v5-outcome-signals")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO dictation (id, createdAt, destination, level, rawTranscript, compiledText, requestJSON, status, provider, pinned, undoWithin30s, copiedOutput, copiedSaid, pastedAgain) VALUES ('old', ?, 'chat', 'full', 'x', 'y', NULL, 'inserted', 'local', 0, 0, 0, 0, 0)", arguments: [Date()])
        }
        try migrator.migrate(queue)
        XCTAssertNil(try queue.read { try DictationRecord.fetchOne($0, key: "old") }?.startSource)
        try queue.write { db in
            try DictationRecord(id: "new", createdAt: Date(), destination: "chat", level: "full", rawTranscript: "x", compiledText: "y",
                                requestJSON: nil, status: .inserted, provider: "local", startSource: StartSource.palmDouble.rawValue).insert(db)
        }
        let row = try XCTUnwrap(try queue.read { try DictationRecord.fetchOne($0, key: "new") })
        XCTAssertEqual(row.startSource.flatMap(StartSource.init(rawValue:)), .palmDouble)
    }

    func testEveryAcceptedKnockCarriesItsStrengthForTheLog() throws {
        var detector = TapDetector()
        for s in try TapDetectorTests.load("bed2/double-left") { _ = detector.process(t: s.t, s.a) }
        XCTAssertFalse(detector.heardShapes.isEmpty)
        XCTAssertTrue(detector.heardShapes.allSatisfy { $0.peak > 0.005 }, "a knock the detector kept was at least the threshold")
        XCTAssertEqual(detector.heardShapes.count, detector.heard.count)
        for (shape, knock) in zip(detector.heardShapes, detector.heard) {
            XCTAssertEqual(shape.peak, knock.peak, accuracy: 0.0001, "the same number the detector measured")
        }
    }
}
