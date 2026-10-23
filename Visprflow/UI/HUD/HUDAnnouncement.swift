import AppKit
import Foundation

/// What VoiceOver says when the overlay changes.
///
/// The overlay can never become key, by design: it must not take the caret from the app being
/// dictated into. That also means VoiceOver can never land on it, so without announcements a
/// VoiceOver user hears nothing at all, including the preview they are asked to approve.
enum HUDAnnouncement {
    /// The words for a state, or nil when nothing new should be said. Listening updates arrive
    /// thirty times a second; only the first one of a recording is announced.
    static func text(for state: HUDState, previous: HUDState?) -> String? {
        switch state {
        case .hidden:
            return nil
        case let .listening(_, _, locked, _, mode, app):
            if case let .listening(_, _, wasLocked, _, wasMode, _) = previous, wasLocked == locked, wasMode == mode {
                return nil
            }
            if locked { return "Hands-free. Tap the key to stop, Escape cancels." }
            let into = app.map { ", into \($0)" } ?? ""
            return mode == .dictate ? "Listening\(into)." : "\(mode.label), listening\(into)."
        case .transcribing:
            if case .transcribing = previous { return nil }
            return "Transcribing."
        case let .compiling(_, provider):
            if case .compiling = previous { return nil }
            return provider.map { "Rewriting \($0)." } ?? "Rewriting."
        case let .preview(model):
            if model.isStale { return "Rewriting at a different level." }
            if case let .preview(old) = previous, old.text == model.text, old.label == model.label {
                return nil
            }
            return previewText(model)
        case let .inserted(destination, pasted):
            return UICopy.inserted(into: destination, pasted: pasted) + "."
        case .cancelled:
            return "Cancelled."
        case let .failed(message):
            return message
        }
    }

    /// "Preview for Claude Code, Compiled. Users are getting logged out… Return inserts, Escape cancels."
    static func previewText(_ model: PreviewHUD) -> String {
        let action = model.mode == .paste ? "Return pastes" : "Return inserts"
        return "\(model.mode.label) preview for \(model.destination), \(model.label). \(firstSentence(of: model.text)) \(action), Escape cancels."
    }

    /// The first sentence, capped, so a long prompt is not read out in full.
    static func firstSentence(of text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        var sentence = flat
        if let end = flat.firstIndex(where: { ".!?".contains($0) }) {
            sentence = String(flat[...end])
        }
        if sentence.count > 160 {
            sentence = String(sentence.prefix(157)) + "…"
        }
        return sentence
    }

    @MainActor
    static func post(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
