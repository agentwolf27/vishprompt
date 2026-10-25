import CoreGraphics
import Foundation

/// Typing, clicking and touching the trackpad all shake the palm rest, so a double tap with any
/// of them nearby is dropped.
///
/// The ages come from the window server's per-type counters, which need no permission
/// (checked with a grant-less app on macOS 15.2). Key presses and clicks were not enough: a
/// trackpad tap or hold raises touch (gesture) events and no click, and a Force Touch press
/// fires the Taptic Engine, which the accelerometer feels as one clean knock. Vish found it:
/// "the palm rest tap works on the mouse pad when i double tap and hold it".
enum TapInputGuard {
    /// The event types that open the suppression window, by their CGEventType numbers.
    /// Gesture (29) and pressure (34) have no named CGEventType case; NSEvent.EventType uses the
    /// same numbers (`.gesture`, `.pressure`).
    static let eventTypes: [(name: String, raw: UInt32)] = [
        ("key down", 10),
        ("left click", 1),
        ("right click", 3),
        ("other click", 25),
        ("scroll", 22),
        ("trackpad touch", 29),
        ("Force Touch pressure", 34),
    ]

    /// Seconds since the most recent of those, from the window server.
    static func lastInputAge(_ age: (UInt32) -> Double = systemAge) -> Double {
        eventTypes.map { age($0.raw) }.min() ?? .infinity
    }

    static func systemAge(_ raw: UInt32) -> Double {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: unsafeBitCast(raw, to: CGEventType.self))
    }

    /// Whether input came close enough to a double tap to have caused it: any time from just
    /// before its first knock until now, when the double was decided.
    static func touched(lastInput: Double, firstKnock: Double, before: Double = TapDetector.Tuning().inputBefore) -> Bool {
        lastInput >= firstKnock - before
    }
}
