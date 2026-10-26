import Foundation

/// How the trigger key behaves.
enum HotkeyMode: String, Codable, Sendable, CaseIterable {
    /// Hold to talk, release to compile. A double-tap locks hands-free.
    case hybrid
    /// Hold to talk only; a double-tap does nothing special.
    case pushToTalk
    /// Every press toggles recording on or off.
    case toggle
}

/// Modifiers held alongside the trigger key, read at the moment the gesture ends.
struct GestureModifiers: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let shift = GestureModifiers(rawValue: 1 << 0)
    static let control = GestureModifiers(rawValue: 1 << 1)
    static let option = GestureModifiers(rawValue: 1 << 2)
    static let command = GestureModifiers(rawValue: 1 << 3)
    static let none: GestureModifiers = []
}

/// Input events, deliberately free of AppKit so the machine can be driven by a fake clock.
enum HotkeyEvent: Equatable, Sendable {
    case triggerDown(at: TimeInterval, modifiers: GestureModifiers)
    case triggerUp(at: TimeInterval, modifiers: GestureModifiers)
    case escape
    /// Silence ran long enough to end a hands-free session.
    case silenceTimeout
    /// A tap-started session heard nothing in its first seconds: drop it silently.
    case quietStart
    /// The trigger has been held past the safety ceiling; finish what was captured.
    case holdTimeout(at: TimeInterval)
    /// The event tap was disabled and re-enabled; any in-flight gesture is unreliable.
    case resynchronise
    /// The paste key (V) went down while the trigger was held: a Smart Paste request.
    case pasteKey(at: TimeInterval)
    /// The edit key (R) went down while the trigger was held: edit the selection by voice.
    case editKey(at: TimeInterval)
    /// Any other key went down while the trigger was held. `shortcutTrigger` is true for Right
    /// Command and Right Option, the modifiers other keys are typed with.
    case otherKey(at: TimeInterval, shortcutTrigger: Bool)
    /// A double tap on the palm rest. Behaves like a toggle-mode press of the trigger, whatever
    /// the trigger's own mode: it starts hands-free recording, or ends it. Use `chassisTap(at:)`,
    /// which also sends the release.
    case chassisTap(at: TimeInterval)
}

/// Keys the overlay responds to while a compiled prompt is waiting for approval.
enum PreviewKey: String, Equatable, Sendable {
    case insert      // Return
    case cycleLevel  // Tab
    case cycleBack   // ⇧Tab
    case cancel      // Escape
    case rerecord    // R
    case scrollUp    // ↑ or Page Up
    case scrollDown  // ↓ or Page Down
    case levelVerbatim, levelLight, levelMedium, levelFull  // 1 to 4
}

/// What the pipeline should do next.
enum HotkeyAction: Equatable, Sendable {
    case none
    /// Begin capturing audio. Capture always starts on key-down so no speech is lost.
    case startCapture
    /// Stop capturing and compile what was captured.
    case finishCapture(modifiers: GestureModifiers, locked: Bool)
    /// Stop capturing and throw the audio away.
    case discardCapture(reason: DiscardReason)
    /// Recording continues with the key released.
    case lockedOn
    /// A key pressed while the overlay is showing a preview.
    case preview(PreviewKey)
    /// The capture in progress is a Smart Paste: the clipboard is the content and whatever is
    /// said is the instruction. Sent once, when V goes down; the capture continues.
    case smartPaste
    /// The capture in progress edits the selection: the selected text is the content and
    /// whatever is said is the instruction. Sent once, when R goes down.
    case editSelection
}

enum DiscardReason: String, Equatable, Sendable {
    case tooShort
    case escape
    case resynchronise
    /// The key was held past the safety ceiling, so the key-up was probably never delivered.
    case tooLong
    /// Another key was pressed right after the trigger: a shortcut such as ⌘C or fn+Delete, not
    /// a dictation. Nothing is shown; the key goes through to the app.
    case shortcut
    /// A tap-started session heard nothing: probably a false tap. Nothing is shown.
    case noSpeech
}

/// Push-to-talk with double-tap-to-lock for the trigger key.
///
/// Rules, matching the plan:
/// - Capture starts on key-down, so the first word is never clipped.
/// - A press shorter than `minimumPress` is an accidental tap and its audio is discarded.
/// - Two short taps inside `doubleTapWindow` lock hands-free recording; the next press,
///   or a silence timeout, ends it.
/// - Escape cancels from any recording state. A mouse click does not.
struct HotkeyGesture: Sendable {
    struct Config: Sendable, Equatable {
        var mode: HotkeyMode = .hybrid
        /// Presses shorter than this are treated as accidental taps.
        var minimumPress: TimeInterval = 0.3
        /// Two taps closer together than this lock hands-free mode.
        var doubleTapWindow: TimeInterval = 0.4
        /// V turns a hold into a Smart Paste only this soon after the trigger went down. Fn+V
        /// is a chord; a V seconds into a dictation is the user typing, not asking to paste.
        var pasteWindow: TimeInterval = 1.0
        /// Another key this soon after the trigger makes the press a shortcut, whatever the
        /// trigger is: fn+Delete is forward delete, F13+anything is a macro.
        var shortcutWindow: TimeInterval = 0.15
        static let `default` = Config()
    }

    enum State: Equatable, Sendable {
        /// Not recording.
        case idle
        /// Key held, capturing. Releasing compiles (or discards if too short).
        case holding(since: TimeInterval)
        /// Second tap of a double-tap is held; releasing it starts hands-free.
        case lockArming
        /// Capturing hands-free with the key released.
        case locked
        /// Key held again during hands-free; releasing it compiles.
        case lockStopping
    }

    let config: Config
    private(set) var state: State = .idle
    /// End time of the last press too short to count, for double-tap detection.
    private var lastShortTapEnded: TimeInterval?
    /// A key pressed with the trigger that changes what the hold does. One per hold: V then R
    /// is still a paste.
    enum Chord: Equatable, Sendable { case paste, edit }

    /// Set when V or R converted the current hold.
    private(set) var chord: Chord?

    /// True when the recording in progress was started by a tap on the palm rest.
    private(set) var startedByTap = false

    /// True when V converted the current hold into a Smart Paste.
    var pasteRequested: Bool { chord == .paste }

    init(config: Config = .default) {
        self.config = config
    }

    var isRecording: Bool {
        state != .idle
    }

    /// The trigger is held, hands-free not engaged.
    var isHolding: Bool {
        if case .holding = state { return true }
        return false
    }

    var isLocked: Bool {
        switch state {
        case .locked, .lockStopping, .lockArming: true
        case .idle, .holding: false
        }
    }

    mutating func handle(_ event: HotkeyEvent) -> HotkeyAction {
        switch event {
        case let .triggerDown(at, _):
            handleDown(at: at)
        case let .triggerUp(at, modifiers):
            handleUp(at: at, modifiers: modifiers)
        case .escape:
            cancel(reason: .escape)
        case .silenceTimeout:
            handleSilence()
        case .quietStart:
            handleQuietStart()
        case let .holdTimeout(at):
            handleHoldTimeout(at: at)
        case .resynchronise:
            cancel(reason: .resynchronise)
        case let .pasteKey(at):
            handleChordKey(.paste, at: at)
        case let .editKey(at):
            handleChordKey(.edit, at: at)
        case let .otherKey(at, shortcutTrigger):
            handleOtherKey(at: at, shortcutTrigger: shortcutTrigger)
        case .chassisTap:
            handleTap()
        }
    }

    /// A palm-rest tap is a whole press, down and up at once. From idle it starts a hands-free
    /// recording; while hands-free it ends one. While the trigger is held, or half-way through
    /// its own double-tap, it does nothing, so a tap can never cut a held dictation short.
    mutating func chassisTap(at time: TimeInterval, chord requested: Chord? = nil) -> [HotkeyAction] {
        var actions = [handle(.chassisTap(at: time))]
        // A gesture assigned to Smart Paste or an edit starts the same hands-free capture, then
        // sends the same action fn+V or fn+R would, before the overlay says what it is doing.
        if let requested, state == .lockArming, startedByTap {
            chord = requested
            actions.append(requested == .paste ? .smartPaste : .editSelection)
        }
        if state == .lockArming || state == .lockStopping {
            actions.append(handle(.triggerUp(at: time, modifiers: .none)))
        }
        return actions.filter { $0 != .none }
    }

    // MARK: Private

    /// Only a held key counts, never hands-free: in hands-free mode the user's hands are free
    /// to type, so a V there is a letter. A second V after the first is swallowed by the
    /// monitor but changes nothing.
    private mutating func handleChordKey(_ requested: Chord, at time: TimeInterval) -> HotkeyAction {
        guard case let .holding(since) = state, chord == nil else { return .none }
        guard time - since <= config.pasteWindow else { return .none }
        chord = requested
        return requested == .paste ? .smartPaste : .editSelection
    }

    /// Another key while the trigger is held. Within `shortcutWindow` of the press it is a
    /// shortcut, not a dictation, whatever the trigger. With Right Command or Right Option it is
    /// one at any time: nobody types mid-dictation with the modifier other keys are typed with.
    /// Hands-free is left alone, since the hands are free to type. A hold already turned into a
    /// Smart Paste or an edit by V or R is left alone too.
    private mutating func handleOtherKey(at time: TimeInterval, shortcutTrigger: Bool) -> HotkeyAction {
        guard case let .holding(since) = state, chord == nil else { return .none }
        guard shortcutTrigger || time - since <= config.shortcutWindow else { return .none }
        state = .idle
        lastShortTapEnded = nil
        return .discardCapture(reason: .shortcut)
    }

    /// The trigger has been held past the ceiling, which in practice means the key-up was never
    /// delivered. Finish with what was captured rather than discarding it: the user did speak,
    /// and throwing away five minutes of audio to punish a missed event helps nobody.
    private mutating func handleHoldTimeout(at _: TimeInterval) -> HotkeyAction {
        switch state {
        case .idle, .lockArming:
            return .none
        case .holding:
            state = .idle
            lastShortTapEnded = nil
            chord = nil
            return .finishCapture(modifiers: .none, locked: false)
        case .locked, .lockStopping:
            state = .idle
            lastShortTapEnded = nil
            return .finishCapture(modifiers: .none, locked: true)
        }
    }

    private mutating func handleTap() -> HotkeyAction {
        switch state {
        case .idle:
            lastShortTapEnded = nil
            chord = nil
            startedByTap = true
            state = .lockArming
            return .startCapture
        case .locked:
            state = .lockStopping
            return .none
        case .holding, .lockArming, .lockStopping:
            return .none
        }
    }

    private mutating func handleDown(at time: TimeInterval) -> HotkeyAction {
        switch state {
        case .idle:
            startedByTap = false
            if config.mode == .toggle {
                state = .lockArming
                return .startCapture
            }
            if config.mode == .hybrid,
               let previous = lastShortTapEnded,
               time - previous <= config.doubleTapWindow {
                lastShortTapEnded = nil
                state = .lockArming
                return .startCapture
            }
            state = .holding(since: time)
            return .startCapture

        case .locked:
            // Pressing again while hands-free ends the session on release.
            state = .lockStopping
            return .none

        case .holding, .lockArming, .lockStopping:
            // Auto-repeat, or a key-down we already accounted for.
            return .none
        }
    }

    private mutating func handleUp(at time: TimeInterval, modifiers: GestureModifiers) -> HotkeyAction {
        switch state {
        case .idle, .locked:
            // A key-up with no matching key-down. Nothing to do.
            return .none

        case let .holding(since):
            state = .idle
            let held = time - since
            // A quick fn+V tap is a complete request: paste the clip as copied. Without this
            // it would be discarded as an accidental tap.
            if chord != nil {
                chord = nil
                lastShortTapEnded = nil
                return .finishCapture(modifiers: modifiers, locked: false)
            }
            if held < config.minimumPress {
                lastShortTapEnded = time
                return .discardCapture(reason: .tooShort)
            }
            lastShortTapEnded = nil
            return .finishCapture(modifiers: modifiers, locked: false)

        case .lockArming:
            state = .locked
            return .lockedOn

        case .lockStopping:
            state = .idle
            lastShortTapEnded = nil
            chord = nil
            return .finishCapture(modifiers: modifiers, locked: true)
        }
    }

    /// Only a hands-free session, and only one a tap started: a held key is the user's hand.
    private mutating func handleQuietStart() -> HotkeyAction {
        guard startedByTap, state == .locked || state == .lockArming else { return .none }
        state = .idle
        lastShortTapEnded = nil
        chord = nil
        return .discardCapture(reason: .noSpeech)
    }

    private mutating func handleSilence() -> HotkeyAction {
        guard state == .locked else { return .none }
        state = .idle
        chord = nil
        return .finishCapture(modifiers: .none, locked: true)
    }

    private mutating func cancel(reason: DiscardReason) -> HotkeyAction {
        guard isRecording else { return .none }
        state = .idle
        lastShortTapEnded = nil
        chord = nil
        return .discardCapture(reason: reason)
    }
}
