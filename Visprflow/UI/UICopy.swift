import Foundation

/// Words used across Setup, Destinations and the overlay, kept in one place so they can be
/// tested: no jargon, no raw errors, and counts that match what is on screen.
enum UICopy {
    static func numberWord(_ count: Int) -> String {
        switch count {
        case 1: "One"
        case 2: "Two"
        case 3: "Three"
        case 4: "Four"
        default: "\(count)"
        }
    }

    /// The setup headline. Counted from the list it introduces, so it can never say three
    /// when two are shown again.
    static func permissionsHeadline(trigger: String, requiredCount: Int) -> String {
        "Hold \(trigger), talk, release. \(numberWord(requiredCount)) permission\(requiredCount == 1 ? "" : "s") make\(requiredCount == 1 ? "s" : "") that work in every app."
    }

    enum KeychainAction { case read, save, remove }

    /// What went wrong with the Keychain and what to do, never the raw error.
    static func keychainFailure(_ action: KeychainAction) -> String {
        switch action {
        case .read: "Couldn't read the key from the Keychain. If your login keychain is locked, unlock it in Keychain Access, then reopen Setup."
        case .save: "Couldn't save the key to the Keychain. If your login keychain is locked, unlock it in Keychain Access, then Save again."
        case .remove: "Couldn't remove the key from the Keychain. If your login keychain is locked, unlock it in Keychain Access, then try again."
        }
    }

    static func modelDownloadFailed(_ reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "The speech model didn't finish downloading (\(trimmed)). Check your connection, then Retry."
    }

    /// Insertion methods in plain words.
    static func insertionLabel(_ strategy: InsertionStrategy) -> String {
        switch strategy {
        case .paste: "Paste (most apps)"
        case .pasteShiftInsert: "Paste for terminals that paste images by mistake"
        case .accessibility: "Replace the selection directly"
        case .typing: "Type it out (slow; for apps that block paste)"
        }
    }

    /// The list subtitle: the level that will actually be used, and whether it was changed.
    static func destinationSubtitle(_ destination: Destination, override: DestinationOverride?) -> String {
        let level = (override?.defaultLevel ?? destination.defaultLevel).displayName
        var custom: [String] = []
        if override?.defaultLevel != nil, override?.defaultLevel != destination.defaultLevel { custom.append("level") }
        if let instructions = override?.instructions, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            custom.append("instructions")
        }
        if override?.requiresPreview != nil, override?.requiresPreview != destination.requiresPreview { custom.append("preview") }
        if override?.strategy != nil, override?.strategy != destination.strategy { custom.append("insertion") }
        return custom.isEmpty ? level : "\(level) · custom \(custom.joined(separator: ", "))"
    }

    /// Where the text went, and how to take it back where that is possible. No character
    /// count: nobody acts on one, and History keeps it.
    static func inserted(into destination: String, pasted: Bool, landing: Landing = .undoable) -> String {
        switch landing {
        case .agentNotSent: "In \(destination), not sent. Review it, then press Return there"
        case .notUndoable: "\(pasted ? "Pasted" : "Inserted") into \(destination)"
        case .undoable: "\(pasted ? "Pasted" : "Inserted") into \(destination) · ⌘Z undoes"
        }
    }
}
