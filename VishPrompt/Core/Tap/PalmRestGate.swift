import Foundation

/// How often the detector starts a session on its own: measured on long recordings of the Mac
/// left alone, on a bed and on a lap. The palm rest passes only when that is rare and the
/// recordings are long enough to say so. Until then the Palm rest card says it, in numbers.
enum PalmRestGate {
    struct Measurement: Equatable, Sendable {
        /// The idle recordings measured, as `Fixtures/taps/<name>.csv`.
        var fixtures: [String]
        /// Their total length.
        var seconds: Double
        /// Double taps the detector fired across them, replayed as the app samples.
        var falseDoubles: Int
    }

    /// Under one false start an hour, over at least two hours of recordings.
    static let maximumPerHour = 1.0
    static let requiredHours = 2.0

    /// The last measurement over the idle recordings in `Fixtures/taps`. `TapFalseTriggerTests`
    /// recomputes it from the files and fails if this is out of date, so the card never shows a
    /// stale number. 2026-10-26: two ten-second recordings, one of them holding a real double
    /// knock (Vish's first bed session, 5.6 s in).
    static let measured = Measurement(fixtures: ["bed1/idle", "idle-quiet"], seconds: 20, falseDoubles: 1)

    static var hours: Double { measured.seconds / 3600 }

    static var perHour: Double? {
        hours > 0 ? Double(measured.falseDoubles) / hours : nil
    }

    static var passed: Bool {
        guard hours >= requiredHours, let perHour else { return false }
        return perHour < maximumPerHour
    }

    /// What the Palm rest card says until the gate passes, with the numbers behind it.
    static var warning: String? {
        guard !passed else { return nil }
        let length = measured.seconds < 3600
            ? "\(Int((measured.seconds / 60).rounded())) \(Int((measured.seconds / 60).rounded()) == 1 ? "minute" : "minutes")"
            : String(format: "%.1f hours", hours)
        let fired = "\(measured.falseDoubles) \(measured.falseDoubles == 1 ? "time" : "times")"
        return "Not yet proven against false starts. On a soft surface a bump can read as a tap and start a session on its own; in \(length) of recordings of the Mac left alone it happened \(fired). It needs under \(Int(maximumPerHour)) an hour over at least \(Int(requiredHours)) hours of such recordings. A tap-started session always waits in the preview card, so nothing lands without Return."
    }
}
