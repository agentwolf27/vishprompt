import Foundation

/// A gesture on the palm rest. The side rows exist only once a calibration has shown this Mac
/// can tell the sides apart (PLAN.md, "Palm-rest gestures you choose").
enum PalmGesture: String, CaseIterable, Codable, Sendable {
    case double, triple, doubleLeft, doubleRight

    var title: String {
        switch self {
        case .double: "Double-tap (either side)"
        case .triple: "Triple-tap (either side)"
        case .doubleLeft: "Double-tap left"
        case .doubleRight: "Double-tap right"
        }
    }

    var note: String {
        switch self {
        case .double: "Two quick taps beside the trackpad, either side."
        case .triple: "Three quick taps beside the trackpad."
        case .doubleLeft: "Two quick taps left of the trackpad."
        case .doubleRight: "Two quick taps right of the trackpad."
        }
    }
}

/// What a gesture does. Each is an entry point the app already has, nothing new inside it.
enum PalmAction: String, CaseIterable, Codable, Sendable {
    case off, dictate, smartPaste, editSelection, fixScreenshot

    var title: String {
        switch self {
        case .off: "Off"
        case .dictate: "Dictate (hands-free)"
        case .smartPaste: "Smart paste"
        case .editSelection: "Edit selection by voice"
        case .fixScreenshot: "Fix screenshot"
        }
    }
}

/// Which action each gesture runs, saved on this Mac. Everything is Off until the palm rest is
/// first turned on; then "Double-tap (either side)" becomes Dictate, once.
struct PalmGestureSettings: @unchecked Sendable {
    static let key = "palmGestures"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var stored: [String: String]? {
        defaults.dictionary(forKey: Self.key) as? [String: String]
    }

    func action(for gesture: PalmGesture) -> PalmAction {
        stored?[gesture.rawValue].flatMap(PalmAction.init(rawValue:)) ?? .off
    }

    func set(_ action: PalmAction, for gesture: PalmGesture) {
        var map = stored ?? [:]
        map[gesture.rawValue] = action.rawValue
        defaults.set(map, forKey: Self.key)
    }

    /// Called when the palm rest is turned on. Only the very first time does it choose anything.
    func applyFirstTimeDefaults() {
        guard stored == nil else { return }
        set(.dictate, for: .double)
    }

    /// Whether any gesture needs triple taps told apart from doubles, which makes a double wait
    /// a little longer to be sure no third tap is coming.
    var listensForTriples: Bool {
        action(for: .triple) != .off
    }
}

/// What the app does when a gesture is heard.
enum PalmDispatch: Equatable, Sendable {
    /// The gesture is Off: nothing happens.
    case ignore
    /// A hands-free recording is running, and any assigned gesture ends it.
    case stop
    /// Starts a hands-free recording, as a dictation, a Smart Paste or an edit.
    case start(HotkeyGesture.Chord?)
    /// Fix screenshot with no image on the clipboard: say so, start nothing.
    case needsScreenshot

    static func resolve(_ gesture: PalmGesture, settings: PalmGestureSettings, recording: Bool, clipboardHasImage: () -> Bool) -> PalmDispatch {
        let action = settings.action(for: gesture)
        guard action != .off else { return .ignore }
        if recording { return .stop }
        switch action {
        case .off: return .ignore
        case .dictate: return .start(nil)
        case .smartPaste: return .start(.paste)
        case .editSelection: return .start(.edit)
        // The screenshot path is Smart Paste with an image clip (fn+V with a screenshot), which
        // turns it into a bug prompt in a coding agent and reads its text anywhere else.
        case .fixScreenshot: return clipboardHasImage() ? .start(.paste) : .needsScreenshot
        }
    }

    static let noScreenshot = "No screenshot on the clipboard. Copy one with ⌘⌃⇧4, then tap again."
}

/// How firm a tap has to be. Normal is what every tap test was tuned on; the others move only
/// the onset thresholds, so the rest of the detector behaves the same.
enum PalmSensitivity: String, CaseIterable, Identifiable, Sendable {
    case light, normal, firm

    static let key = "palmSensitivity"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .normal: "Normal"
        case .firm: "Firm"
        }
    }

    var note: String {
        switch self {
        case .light: "Catches softer taps. On a soft surface, expect more false starts."
        case .normal: "A fingertip tap, as the detector was tuned."
        case .firm: "Only a firm knock, 30 mg or more. Typing and clicks never reach it."
        }
    }

    /// The thresholds this level sets on the detector's tuning.
    func apply(to tuning: inout TapDetector.Tuning) {
        switch self {
        case .light:
            tuning.minimumPeak = 0.004
            tuning.noiseMultiple = 4.5
        case .normal:
            break
        case .firm:
            tuning.minimumPeak = 0.03
            tuning.noiseMultiple = 8
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> PalmSensitivity {
        defaults.string(forKey: key).flatMap(PalmSensitivity.init(rawValue:)) ?? .normal
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }

    /// The detector tuning for the saved settings: this level, and whether triples are listened for.
    static func tuning(in defaults: UserDefaults = .standard) -> TapDetector.Tuning {
        var tuning = TapDetector.Tuning()
        saved(in: defaults).apply(to: &tuning)
        tuning.listensForTriples = PalmGestureSettings(defaults: defaults).listensForTriples
        return tuning
    }
}

/// What a heard gesture becomes, decided in one place so the Test area and calibration can be
/// checked without the sensor.
enum PalmRoute: Equatable, Sendable {
    /// A key, click or trackpad touch came near it: typing or clicking, not a tap.
    case nearInput
    /// A calibration run is collecting double taps: these knocks go to it, and nothing runs.
    case calibrate([KnockShape])
    /// The sides are calibrated but this double's knocks could not be placed. Never guessed.
    case sideUnclear
    /// The Test area is on: show the gesture, run nothing.
    case test(PalmGesture)
    case run(PalmGesture)

    static func resolve(_ event: TapEvent, shapes: [KnockShape], calibration: SideCalibration?,
                        nearInput: Bool, testing: Bool, calibrating: Bool) -> PalmRoute {
        if nearInput { return .nearInput }
        let gesture: PalmGesture
        switch event {
        case .tripleTap:
            gesture = .triple
        case .doubleTap:
            if calibrating { return .calibrate(shapes) }
            if let calibration, calibration.unlocked {
                guard let side = calibration.side(of: shapes) else { return .sideUnclear }
                gesture = side == .left ? .doubleLeft : .doubleRight
            } else {
                gesture = .double
            }
        }
        return testing ? .test(gesture) : .run(gesture)
    }
}

/// What the Test area shows after a tap.
enum PalmTestResult: Equatable, Sendable {
    case heard(PalmGesture)
    case nearInput
    case sideUnclear

    var text: String {
        switch self {
        case let .heard(gesture): "Heard: \(gesture.title)"
        case .nearInput: "Heard a tap, but you were typing or clicking, so it wouldn't count."
        case .sideUnclear: "Heard a double-tap, but couldn't tell which side. It wouldn't run."
        }
    }
}
