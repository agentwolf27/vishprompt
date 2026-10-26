import Foundation

/// Ends a palm-rest session nobody is attending. A tap can be a false one on a soft surface
/// (Vish, 2026-10-26), so a tap-started session that hears nothing in its first seconds is
/// dropped silently, and one left open in "When I tap again" still ends after a minute without
/// new words. A session the key started is never touched by this.
enum TapSessionGuard {
    /// Seconds a tap-started session may run without hearing anything.
    static let quietStart: TimeInterval = 3
    /// Seconds without new words after which a tap-started session ends, even in tap-again mode.
    static let idleEnd: TimeInterval = 60

    enum Verdict: Equatable, Sendable {
        case keep
        /// Nothing was heard since the tap: drop it, say nothing.
        case cancelQuietStart
        /// Words were heard, then nothing for a minute: finish, through the preview card.
        case endIdle
    }

    /// Whether anything above the silence threshold has been heard since the capture began:
    /// `silenceSeconds` counts up from the start and resets on any sound.
    static func heardSpeech(elapsed: TimeInterval, silenceSeconds: TimeInterval) -> Bool {
        silenceSeconds + 0.3 < elapsed
    }

    static func verdict(startedByTap: Bool, elapsed: TimeInterval, silenceSeconds: TimeInterval, heardSpeech: Bool, silenceLimit: TimeInterval?) -> Verdict {
        guard startedByTap else { return .keep }
        if !heardSpeech { return elapsed >= quietStart ? .cancelQuietStart : .keep }
        // With a pause length set, the ordinary silence stop ends it sooner; this is the floor
        // for tap-again mode, where there is otherwise no silence stop at all.
        if silenceLimit == nil, silenceSeconds >= idleEnd { return .endIdle }
        return .keep
    }
}
