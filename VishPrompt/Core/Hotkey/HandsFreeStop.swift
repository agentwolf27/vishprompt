import Foundation

/// How a hands-free session ends, whether the fn double-tap or a palm-rest gesture started it.
/// Vish: "Can we also add a customization where the user can choose whether it just stops right
/// after they stop talking or they have to double tap it again".
enum HandsFreeStopMode: String, CaseIterable, Identifiable, Sendable {
    /// The silence timeout ends it, after `HandsFreeSettings.pause`.
    case whenIStopTalking
    /// No silence stop at all: it ends on the stop gesture, the trigger key, Escape, or the
    /// five-minute ceiling.
    case whenITapAgain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whenIStopTalking: "When I stop talking"
        case .whenITapAgain: "When I tap again"
        }
    }

    var note: String {
        switch self {
        case .whenIStopTalking: "Ends on its own after a pause. Tapping again, the trigger key or Escape also end it."
        case .whenITapAgain: "Keeps listening through pauses until you tap again, press the trigger key, or press Escape. Never longer than five minutes."
        }
    }
}

/// A pause length for "When I stop talking". 1.2 s is what the app always did.
enum HandsFreePause: Double, CaseIterable, Identifiable, Sendable {
    case short = 1.2
    case medium = 3
    case long = 5

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .short: "1.2 s"
        case .medium: "3 s"
        case .long: "5 s"
        }
    }
}

struct HandsFreeSettings: @unchecked Sendable {
    static let modeKey = "handsFreeStopMode"
    static let pauseKey = "handsFreePause"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: HandsFreeStopMode {
        get { defaults.string(forKey: Self.modeKey).flatMap(HandsFreeStopMode.init(rawValue:)) ?? .whenIStopTalking }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.modeKey) }
    }

    var pause: HandsFreePause {
        get { HandsFreePause(rawValue: defaults.double(forKey: Self.pauseKey)) ?? .short }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.pauseKey) }
    }

    static let soundKey = "tapStartSound"

    /// Whether a palm-rest tap that starts a session plays a short sound, so a start nobody
    /// meant is noticed. On unless turned off.
    var tapStartSound: Bool {
        get { defaults.object(forKey: Self.soundKey) == nil ? true : defaults.bool(forKey: Self.soundKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.soundKey) }
    }

    /// Seconds of silence that end a hands-free session, or nil when only a tap does.
    var silenceLimit: TimeInterval? {
        mode == .whenIStopTalking ? pause.rawValue : nil
    }

    /// Whether the room has been quiet long enough to stop. Pure, so both modes are tested.
    static func shouldStop(locked: Bool, silenceSeconds: TimeInterval, limit: TimeInterval?) -> Bool {
        guard locked, let limit else { return false }
        return silenceSeconds >= limit
    }
}
