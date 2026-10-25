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
