import AppKit
import XCTest
@testable import Visprflow

/// Times the real key-up path: post-roll, streaming stop, batch Parakeet, local compile, paste.
/// Run with `make verify-latency`, which builds Release.
///
/// What it measures: everything this app does between the key coming up and the paste
/// keystroke, on speech synthesised with `say` and fed to the streaming model at the pace it
/// would be spoken. What it does not: the microphone, the hotkey, or sound travelling from a
/// speaker to a microphone. That needs the installed app and its permissions, and is the
/// by-hand benchmark in scripts/latency-bench.md.
@MainActor
final class LatencyHarnessTests: XCTestCase {
    nonisolated private static let isEnabled = ProcessInfo.processInfo.environment["VISPRFLOW_LATENCY"] == "1"
    private static let trials = 20
    /// `VISPRFLOW_LATENCY_STREAMING=0` runs without the live preview model, to see what it costs.
    nonisolated private static let withStreaming = ProcessInfo.processInfo.environment["VISPRFLOW_LATENCY_STREAMING"] != "0"
    /// Fails the run if the median goes past this. Generous: it catches a regression of the
    /// 1.2 GB kind, not noise.
    private static let medianCeilingMs = 1_500.0

    override func setUpWithError() throws {
        try XCTSkipUnless(Self.isEnabled, "set VISPRFLOW_LATENCY=1 (make verify-latency) to run the latency harness")
    }

    private func synthesise(_ text: String) throws -> [Float] {
        let output = URL(filePath: NSTemporaryDirectory()).appending(path: "visprflow-latency-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/say")
        process.arguments = ["-r", "175", "-o", output.path, text]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw XCTSkip("`say` produced no audio") }
        return try AudioFileLoader.samples(at: output)
    }

    nonisolated static var previewLabel: String { withStreaming ? "on" : "off" }

    func testKeyUpToPasted() async throws {
        let phrase = "hey can you send me the figma link for the onboarding screens when you get a moment"
        let samples = try synthesise(phrase)
        let seconds = Double(samples.count) / AudioCapture.sampleRate

        let transcriber = ParakeetTranscriber()
        try await transcriber.prepare { _ in }
        let streaming = StreamingTranscriber()
        try await streaming.prepare()
        let compiler = Compiler(policy: .offline)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("visprflow.latency.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        // With VISPRFLOW_LATENCY_COMPARE=preview, runs alternate between the live preview on and
        // off, so whatever else the Mac is doing lands on both equally. Runs taken minutes apart
        // are not comparable on a machine with other work going on.
        let compare = ProcessInfo.processInfo.environment["VISPRFLOW_LATENCY_COMPARE"] == "preview"
        var rows: [Row] = []
        var offRows: [Row] = []
        let total = compare ? Self.trials * 2 : Self.trials
        // One untimed run first: the first inference pays Core ML and Neural Engine set-up.
        for trial in 0...total {
            let preview = compare ? trial % 2 == 1 : Self.withStreaming
            let feeder = SampleFeeder(samples)
            if preview {
                try await streaming.begin(drainingSamples: { feeder.drain() }, onPartial: { _ in })
            }
            try await Task.sleep(for: .seconds(seconds))

            let keyUp = ContinuousClock.now
            var marks: [Stage: ContinuousClock.Instant] = [:]
            try? await Task.sleep(for: .seconds(AudioCapture.postRollDuration))
            marks[.postRollDone] = .now
            let transcript = try await KeyUpPath.transcribe(samples: samples, streaming: streaming, transcriber: transcriber) { stage in
                marks[stage] = .now
            }
            marks[.transcriptReady] = .now
            let compiled = try await compiler.compile(CompileRequest(transcript: transcript.text, level: .light, destination: "message"))
            marks[.compileDone] = .now
            let poster = NoopPoster()
            let inserter = Inserter(
                policy: PasteRestorePolicy(receiptTimeout: 0.02, quietPeriod: 0.01, maximumWait: 0.05),
                pasteboard: pasteboard, poster: poster, isTrusted: { true }, isSecureInput: { false }
            )
            inserter.onChordPosted = { marks[.pasted] = .now }
            try await inserter.insert(compiled.text, strategy: .paste)

            guard trial > 0 else { continue }
            func ms(_ from: ContinuousClock.Instant, _ to: Stage) -> Double {
                Trace.milliseconds(marks[to]! - from)
            }
            let row = Row(
                postRoll: ms(keyUp, .postRollDone),
                streamStop: Trace.milliseconds(marks[.streamStopped]! - marks[.postRollDone]!),
                transcribe: Trace.milliseconds(marks[.transcriptReady]! - marks[.streamStopped]!),
                compile: Trace.milliseconds(marks[.compileDone]! - marks[.transcriptReady]!),
                paste: Trace.milliseconds(marks[.pasted]! - marks[.compileDone]!),
                total: ms(keyUp, .pasted)
            )
            if compare, !preview { offRows.append(row) } else { rows.append(row) }
        }
        if compare {
            for line in Report(rows: offRows, audioSeconds: seconds, label: "live preview off, interleaved").lines {
                print("LATENCY \(line)")
            }
        }

        let report = Report(rows: rows, audioSeconds: seconds, label: compare ? "live preview on, interleaved" : "live preview \(Self.previewLabel)")
        for line in report.lines { print("LATENCY \(line)") }
        if let path = ProcessInfo.processInfo.environment["VISPRFLOW_LATENCY_CSV"] {
            try report.csv.write(toFile: path, atomically: true, encoding: .utf8)
            print("LATENCY raw rows written to \(path)")
        }
        XCTAssertEqual(rows.count, Self.trials)
        XCTAssertLessThan(report.median(\.total), Self.medianCeilingMs, "key-up to pasted regressed")
    }
}

private struct Row {
    var postRoll, streamStop, transcribe, compile, paste, total: Double
}

private struct Report {
    let rows: [Row]
    let audioSeconds: Double
    let label: String

    func median(_ path: KeyPath<Row, Double>) -> Double { percentile(path, 0.5) }

    /// Nearest-rank percentile: with 20 runs, p90 is the 18th fastest. No interpolation, which
    /// would invent a value nobody measured.
    func percentile(_ path: KeyPath<Row, Double>, _ p: Double) -> Double {
        let sorted = rows.map { $0[keyPath: path] }.sorted()
        let rank = max(1, Int((p * Double(sorted.count)).rounded(.up)))
        return sorted[rank - 1]
    }

    var lines: [String] {
        let stages: [(String, KeyPath<Row, Double>)] = [
            ("post-roll", \.postRoll), ("streaming stop", \.streamStop), ("batch transcribe", \.transcribe),
            ("local compile", \.compile), ("paste", \.paste), ("key-up to pasted", \.total),
        ]
        var out = ["\(rows.count) runs of \(String(format: "%.1f", audioSeconds)) s of speech, Release build, this Mac, \(label)"]
        for (name, path) in stages {
            out.append("\(name): median \(HistoryFormat.duration(ms: median(path))), p90 \(HistoryFormat.duration(ms: percentile(path, 0.9))), n=\(rows.count)")
        }
        return out
    }

    var csv: String {
        "post_roll_ms,stream_stop_ms,transcribe_ms,compile_ms,paste_ms,total_ms\n" + rows.map {
            String(format: "%.1f,%.1f,%.1f,%.1f,%.1f,%.1f", $0.postRoll, $0.streamStop, $0.transcribe, $0.compile, $0.paste, $0.total)
        }.joined(separator: "\n") + "\n"
    }
}

/// Releases samples at the pace they would be spoken, so the streaming model works during the
/// "speech" exactly as it does live.
private final class SampleFeeder: @unchecked Sendable {
    private let samples: [Float]
    private let started = ContinuousClock.now
    private var cursor = 0
    private let lock = NSLock()

    init(_ samples: [Float]) { self.samples = samples }

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let elapsed = Trace.milliseconds(ContinuousClock.now - started) / 1000
        let end = min(samples.count, Int(elapsed * AudioCapture.sampleRate))
        guard end > cursor else { return [] }
        defer { cursor = end }
        return Array(samples[cursor..<end])
    }
}

@MainActor
private final class NoopPoster: KeyEventPosting {
    func postChord(key: CGKeyCode, flags: CGEventFlags) async throws {}
}
