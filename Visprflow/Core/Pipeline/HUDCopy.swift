import AppKit
import Foundation

/// The words the overlay uses when something does not go to plan.
///
/// Every message names what happened and what to do next, and every ending that does not
/// insert leaves the text somewhere the user can get it: a dictation that vanished after two
/// seconds is lost work, and the history database is not something anyone can see yet.
enum HUDCopy {
    /// How long a message that carries rescued text stays up.
    static let rescueDuration: TimeInterval = 4.0

    static func focusMoved(to destination: String, isPaste: Bool) -> String {
        isPaste
            ? "\(destination) isn't in front any more, so nothing was pasted. Your clip is still on the clipboard."
            : "\(destination) isn't in front any more, so nothing was inserted. Copied: press ⌘V where you want it."
    }

    static func previewExpired(isPaste: Bool) -> String {
        isPaste
            ? "The preview closed after 90 seconds unanswered. Your clip is still on the clipboard."
            : "The preview closed after 90 seconds unanswered. Copied: press ⌘V where you want it."
    }

    /// A failure after the words were transcribed. The raw transcript has been copied.
    static func failedWithWordsCopied(_ reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "\(trimmed). Your words are copied: press ⌘V, or hold the key to try again."
    }

    static let emptyClipboard = "Nothing to paste: your clipboard holds no text right now. Copy something, then hold fn and press V again."

    static func providerFailed(_ provider: ProviderChoice, reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "Couldn't reach \(provider.displayName) (\(trimmed)). Return pastes the clip unchanged."
    }

    /// Where the words went, for the line under a preview.
    static func source(for provider: ProviderChoice?, escalated: Bool = false) -> String {
        guard let provider, provider != .local else { return "Stayed on this Mac." }
        let line = "Sent your words to \(provider.destinationPhrase)."
        return escalated ? line + " You corrected yourself, so a model resolved it." : line
    }

    static func pasteSource(for provider: ProviderChoice?, rewritten: Bool) -> String {
        guard rewritten, let provider, provider != .local else { return "Stayed on this Mac." }
        return "Sent the copied text, with known secret shapes removed, and your instruction to \(provider.destinationPhrase)."
    }
}

extension ProviderChoice {
    /// "your Claude subscription", for sentences about where text went.
    var destinationPhrase: String {
        switch self {
        case .local: "this Mac"
        case .subscription: "your Claude subscription"
        case .apiKey: "the Anthropic API"
        }
    }
}

/// Puts text where the user can get it back after an ending that did not insert.
enum TextRescue {
    @MainActor
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
