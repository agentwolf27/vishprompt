// Records the palm-rest accelerometer for the chassis tap detector's tests.
//
// Built and run by `make record-taps`, which compiles this file together with the app's own
// SPUAccelerometer.swift and Log.swift, so the recording reads the sensor exactly as the app does.
// Each scenario is prompted on screen and written to Fixtures/taps/<scenario>.csv as
// "t,x,y,z,input": seconds from the start, acceleration in g, and 1 on the first sample after a
// key press, click, scroll, trackpad touch or Force Touch press (the same events TapInputGuard
// watches).

import CoreGraphics
import Foundation

struct Scenario {
    let name: String
    let seconds: Double
    let prompt: String
}

let scenarios = [
    Scenario(name: "idle", seconds: 10, prompt: "Hands off the Mac. Don't touch anything."),
    Scenario(name: "double-left", seconds: 20, prompt: "Double-tap the palm rest LEFT of the trackpad, about every 3 seconds."),
    Scenario(name: "double-right", seconds: 20, prompt: "Double-tap the palm rest RIGHT of the trackpad, about every 3 seconds."),
    Scenario(name: "single", seconds: 20, prompt: "Single taps only, either side, about every 2 seconds."),
    Scenario(name: "typing", seconds: 20, prompt: "Type quickly into this window: anything, keep going."),
    Scenario(name: "clicks", seconds: 20, prompt: "Click the trackpad, single and double clicks, every second or so."),
    Scenario(name: "trackpad", seconds: 20, prompt: "On the trackpad itself: double-tap and hold, press hard (Force Touch), scroll with two fingers. Repeat."),
    Scenario(name: "handling", seconds: 20, prompt: "Lift the front of the Mac an inch and set it down, then slide it, then nudge the lid. Repeat."),
]

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String] = []
    private var start: Double?
    private var inputPending = false

    func add(_ t: Double, _ a: SIMD3<Float>) {
        lock.withLock {
            let t0 = start ?? t
            start = t0
            let input = inputPending ? 1 : 0
            inputPending = false
            rows.append(String(format: "%.5f,%.5f,%.5f,%.5f,%d", t - t0, a.x, a.y, a.z, input))
        }
    }

    func markInput() { lock.withLock { inputPending = true } }

    func take() -> [String] {
        lock.withLock { defer { rows = []; start = nil }; return rows }
    }
}

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Fixtures/taps")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let only = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

guard SPUAccelerometer.isAvailable else {
    print("This Mac has no palm-rest accelerometer (it needs an M2-or-later MacBook).")
    exit(1)
}
let sensor = SPUAccelerometer()
let recorder = Recorder()
sensor.onSample = { recorder.add($0, $1) }
try sensor.start(rate: .active)

// The input TapInputGuard watches, polled every 5 ms from the window server's counters.
let input = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
final class Ages: @unchecked Sendable { var last = TapInputGuard.lastInputAge() }
let ages = Ages()
input.schedule(deadline: .now(), repeating: .milliseconds(5))
input.setEventHandler {
    let age = TapInputGuard.lastInputAge()
    if age < ages.last { recorder.markInput() }
    ages.last = age
}
input.resume()

for scenario in scenarios where only == nil || only == scenario.name {
    print("\n\(scenario.name): \(scenario.prompt)")
    print("  Press Return when ready.", terminator: " ")
    fflush(stdout)
    // Whatever was typed during the last scenario must not start this one.
    tcflush(STDIN_FILENO, TCIFLUSH)
    _ = readLine()
    for n in [3, 2, 1] {
        print("  \(n)…")
        Thread.sleep(forTimeInterval: 1)
    }
    _ = recorder.take()
    print("  GO (\(Int(scenario.seconds)) s)")
    Thread.sleep(forTimeInterval: scenario.seconds)
    let rows = recorder.take()
    let file = directory.appending(path: "\(scenario.name).csv")
    try ("t,x,y,z,input\n" + rows.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    tcflush(STDIN_FILENO, TCIFLUSH)
    print("  stop. \(rows.count) samples → \(file.path)")
}
sensor.stop()
print("\nDone.")
