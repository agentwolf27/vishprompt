import Foundation
import XCTest
@testable import VishPrompt

/// Speed S2b: process facts read in-process instead of launching ps and lsof.
final class ProcessProbeTests: XCTestCase {
    private var scratch: URL!
    private var children: [Process] = []

    override func setUpWithError() throws {
        scratch = URL(filePath: NSTemporaryDirectory()).appending(path: "vishprompt-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for child in children where child.isRunning { child.terminate() }
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Starts a child in `scratch`, so its working directory is known.
    private func spawn(_ executable: String, _ arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = scratch
        try process.run()
        children.append(process)
        Thread.sleep(forTimeInterval: 0.2)
        return process
    }

    func testArgumentsAreTheFullCommandLine() throws {
        let child = try spawn("/bin/sleep", ["30"])
        XCTAssertEqual(ProcessInspector.arguments(of: child.processIdentifier), "/bin/sleep 30")
    }

    func testWorkingDirectoryMatchesLsof() throws {
        let child = try spawn("/bin/sleep", ["30"])
        let direct = try XCTUnwrap(ProcessInspector.workingDirectory(of: child.processIdentifier))
        let viaLsof = try XCTUnwrap(WorkspaceProbe.workingDirectoryViaLsof(of: child.processIdentifier))
        XCTAssertEqual(direct.resolvingSymlinksInPath().path, viaLsof.resolvingSymlinksInPath().path)
        XCTAssertEqual(direct.resolvingSymlinksInPath().path, scratch.resolvingSymlinksInPath().path)
    }

    func testChildrenAreFound() throws {
        let child = try spawn("/bin/sleep", ["30"])
        XCTAssertTrue(ProcessInspector.children(of: getpid()).contains(child.processIdentifier))
    }

    /// The case the whole thing exists for: an agent running under a shell under the terminal.
    func testAnAgentUnderAShellIsFoundWithoutPs() throws {
        let agent = scratch.appending(path: "claude")
        try FileManager.default.createSymbolicLink(at: agent, withDestinationURL: URL(filePath: "/bin/sleep"))
        let shell = try spawn("/bin/sh", ["-c", "\(agent.path) 30; true"])
        let entries = ProcessInspector.descendants(of: shell.processIdentifier)
        XCTAssertFalse(entries.isEmpty)
        let found = try XCTUnwrap(ProcessTree.foreground(under: getpid()))
        XCTAssertTrue(found.isAgent, "found \(found)")
        XCTAssertEqual(found.command, "claude")
    }

    func testAGoneProcessIsNil() {
        XCTAssertNil(ProcessInspector.arguments(of: 999_999))
        XCTAssertNil(ProcessInspector.workingDirectory(of: 999_999))
        XCTAssertTrue(ProcessInspector.children(of: 999_999).isEmpty)
    }

    /// Interleaved timing of the old and new probe for the same question, 20 runs each.
    func testInProcessIsFasterThanLaunchingTools() throws {
        let child = try spawn("/bin/sleep", ["30"])
        let pid = child.processIdentifier
        var old: [Double] = []
        var new: [Double] = []
        for _ in 0..<20 {
            var start = ContinuousClock.now
            _ = ProcessTree.snapshot()
            _ = WorkspaceProbe.workingDirectoryViaLsof(of: pid)
            old.append(Trace.milliseconds(ContinuousClock.now - start))
            start = ContinuousClock.now
            _ = ProcessInspector.descendants(of: getpid())
            _ = ProcessInspector.workingDirectory(of: pid)
            new.append(Trace.milliseconds(ContinuousClock.now - start))
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        func p90(_ values: [Double]) -> Double { values.sorted()[Int((0.9 * Double(values.count)).rounded(.up)) - 1] }
        print("PROBE ps+lsof: median \(HistoryFormat.duration(ms: median(old))), p90 \(HistoryFormat.duration(ms: p90(old))), n=20")
        print("PROBE in-process: median \(HistoryFormat.duration(ms: median(new))), p90 \(HistoryFormat.duration(ms: p90(new))), n=20")
        XCTAssertLessThan(median(new), median(old))
    }
}
