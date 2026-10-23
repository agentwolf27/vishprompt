import Foundation

/// What the overlay knows beyond its state: the mode, where the text is going, how long the
/// take was, and the trigger's name for the copy.
struct HUDContext: Equatable, Sendable {
    var mode: HUDMode = .dictate
    var app: String?
    /// Frozen at key-up, so the take's length stays on screen while it works.
    var takeSeconds: TimeInterval?
    var triggerName: String = "fn"
    /// Set on a notched built-in display: the capsule splits into lobes beside the housing.
    var notch: NotchLayout?
}

/// How the text landed, for the inserted state: whether ⌘Z can take it back.
enum Landing: Equatable, Sendable {
    /// A text field or document: ⌘Z undoes the paste.
    case undoable
    /// A shell prompt: there is no undo there.
    case notUndoable
    /// A coding agent's input: inserted but not sent, and the user still has to press Return.
    case agentNotSent

    init(destinationID: String) {
        switch destinationID {
        case "claude_code", "cursor", "codex": self = .agentNotSent
        case "shell": self = .notUndoable
        default: self = .undoable
        }
    }
}

/// The capsule: what the overlay shows while listening, transcribing, rewriting, and for the
/// moment after. Everything here is the concept's copy (docs/research/ui-concepts-2026-10-23.md,
/// §3, Concept A), worked out from the state so it can be tested without drawing anything.
struct CapsuleModel: Equatable, Sendable {
    enum Glyph: Equatable, Sendable {
        /// The mode chip, while recording or working.
        case mode(HUDMode)
        case inserted
        case cancelled
        /// Something did not land; the card under the capsule says why.
        case failed
    }

    var glyph: Glyph
    /// "into Slack", when known.
    var destination: String?
    /// The level meter while recording; nil while working or done.
    var meter: Float?
    /// True while transcribing or rewriting: a slow pulse instead of the meter.
    var working: Bool
    /// "0:07". While working it is the take's length, frozen.
    var timer: String?
    /// The words on the right: what is happening, or what to do.
    var status: String
    /// The newest live words, one line under the capsule.
    var liveWords: String?

    /// Sizes from the concept: a capsule 36 pt tall, 280 pt at least, 460 pt with live words.
    static let height: Double = 36
    static let minimumWidth: Double = 280
    static let maximumWidth: Double = 460

    /// The capsule for a state, or nil when nothing is shown. A preview or an error also gets
    /// a card under the capsule (`HUDLayout.showsCard`).
    static func make(_ state: HUDState, context: HUDContext) -> CapsuleModel? {
        let into = context.app.map { "into \($0)" }
        switch state {
        case .hidden:
            return nil

        case let .preview(model):
            let ready: String
            switch model.mode {
            case .paste: ready = "Ready to paste"
            case .edit: ready = "Ready to replace"
            case .dictate, .fix: ready = "Ready to insert"
            }
            return CapsuleModel(
                glyph: .mode(model.mode),
                destination: "into \(model.destination)",
                meter: nil,
                working: model.isStale,
                timer: context.takeSeconds.map(clock),
                status: model.isStale ? "Rewriting at a different level" : ready,
                liveWords: nil
            )

        case .failed:
            return CapsuleModel(glyph: .failed, destination: into, meter: nil, working: false, timer: nil, status: "Didn't land", liveWords: nil)

        case let .listening(level, seconds, locked, partial, mode, app):
            let status: String
            if locked {
                status = "Hands-free · tap \(context.triggerName) to stop · esc"
            } else {
                switch mode {
                case .paste: status = "say how, or just release · esc"
                case .edit: status = "say how to change it · esc"
                case .dictate, .fix: status = "release to send · esc"
                }
            }
            return CapsuleModel(
                glyph: .mode(mode),
                destination: (app ?? context.app).map { "into \($0)" },
                meter: level,
                working: false,
                timer: clock(seconds),
                status: status,
                liveWords: partial.isEmpty ? nil : partial
            )

        case .transcribing:
            return CapsuleModel(
                glyph: .mode(context.mode),
                destination: into,
                meter: nil,
                working: true,
                timer: context.takeSeconds.map(clock),
                status: "Transcribing on this Mac",
                liveWords: nil
            )

        case let .compiling(partial, provider):
            return CapsuleModel(
                glyph: .mode(context.mode),
                destination: into,
                meter: nil,
                working: true,
                timer: context.takeSeconds.map(clock),
                status: provider.map { "Rewriting \($0)" } ?? "Working on this Mac",
                liveWords: partial.isEmpty ? nil : partial
            )

        case let .inserted(destination, pasted, landing):
            return CapsuleModel(
                glyph: .inserted,
                destination: nil,
                meter: nil,
                working: false,
                timer: nil,
                status: UICopy.inserted(into: destination, pasted: pasted, landing: landing),
                liveWords: nil
            )

        case .cancelled:
            return CapsuleModel(glyph: .cancelled, destination: nil, meter: nil, working: false, timer: nil, status: "Cancelled", liveWords: nil)
        }
    }

    /// m:ss. Whole seconds only: a dictation's length to the tenth is precision nobody uses.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// Which surfaces a state uses, and how the card arrives.
enum HUDLayout {
    /// The card is for decisions: a preview to accept, or an error to read.
    static func showsCard(_ state: HUDState) -> Bool {
        switch state {
        case .preview, .failed: true
        default: false
        }
    }

    /// From the concept: 480 pt wide, dropping from the capsule.
    static let cardWidth: Double = 480
    /// The drop is a 180 ms spring; under Reduce Motion a plain crossfade.
    static let dropDuration: Double = 0.18

    static func cardArrivesByCrossfade(reduceMotion: Bool) -> Bool { reduceMotion }
}
