import Foundation

/// What started a dictation. Kept on every row and logged at the start, so a session nobody
/// meant to start can be traced to its cause. Vish, 2026-10-26: "why app fires up
/// automatically when im not even doing anything im not even touching it", and nothing in the
/// history said what had started those sessions.
enum StartSource: String, CaseIterable, Codable, Sendable {
    case fnHold
    case fnDoubleTap
    case palmDouble, palmTriple, palmLeft, palmRight

    init(palm gesture: PalmGesture) {
        switch gesture {
        case .double: self = .palmDouble
        case .triple: self = .palmTriple
        case .doubleLeft: self = .palmLeft
        case .doubleRight: self = .palmRight
        }
    }

    /// Started by a tap on the palm rest, not by a key.
    var isPalm: Bool {
        switch self {
        case .fnHold, .fnDoubleTap: false
        case .palmDouble, .palmTriple, .palmLeft, .palmRight: true
        }
    }

    var title: String {
        switch self {
        case .fnHold: "held the trigger key"
        case .fnDoubleTap: "double-tapped the trigger key"
        case .palmDouble: "double-tapped the palm rest"
        case .palmTriple: "triple-tapped the palm rest"
        case .palmLeft: "double-tapped the palm rest, left"
        case .palmRight: "double-tapped the palm rest, right"
        }
    }
}
