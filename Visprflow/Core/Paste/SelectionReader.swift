import AppKit
import ApplicationServices
import Foundation

/// What was selected when the user asked to edit it.
enum SelectionContent: Equatable, Sendable {
    case text(String)
    /// Nothing is selected, or the app would not say.
    case none
    /// A password field or Secure Keyboard Entry: never read.
    case secure
    /// The copy came back marked concealed, as a password manager marks a secret.
    case concealed

    var message: String? {
        switch self {
        case .text: nil
        case .none: "Nothing is selected. Select the text you want to change, then hold the key, press R, and say how."
        case .secure: "This field has secure input on, so its text cannot be read or changed."
        case .concealed: "The selection is marked as a secret, so VishPrompt will not read it."
        }
    }
}

/// Reads the selected text in the focused app.
///
/// Accessibility first: it reads the selection without touching anything. Many apps (most
/// Electron views, some web text areas) do not expose it, so the fallback is the one every app
/// supports: send ⌘C, read what lands on the clipboard, and put the user's clipboard back.
@MainActor
struct SelectionReader {
    var pasteboard: NSPasteboard = .general
    var poster: any KeyEventPosting = SystemKeyPoster()
    var isSecureInput: () -> Bool = { SecureInput.isActive }
    /// Accessibility's selected text for the focused element, or nil if the app will not say.
    var accessibilitySelection: () -> String? = { SelectionReader.focusedSelectedText() }
    /// How long to wait for the ⌘C to land before deciding nothing was selected.
    var copyTimeout: Duration = .milliseconds(250)

    func read() async -> SelectionContent {
        if isSecureInput() { return .secure }
        if let selected = accessibilitySelection(), !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(selected)
        }
        return await readByCopying()
    }

    /// ⌘C, read, restore. The clipboard is put back whatever happens, and Visprflow's own
    /// clipboard watcher is told so it does not mistake the restore for a new copy.
    private func readByCopying() async -> SelectionContent {
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let before = pasteboard.changeCount
        defer {
            snapshot.restore(to: pasteboard)
            NotificationCenter.default.post(name: .visprflowWroteClipboard, object: nil)
        }
        let key = KeycodeResolver.keyCode(for: "c") ?? KeycodeResolver.qwertyC
        do {
            try await poster.postChord(key: key, flags: .maskCommand)
        } catch {
            return .none
        }
        let deadline = ContinuousClock.now.advanced(by: copyTimeout)
        while pasteboard.changeCount == before, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard pasteboard.changeCount != before else { return .none }
        switch ClipboardReader.read(from: pasteboard) {
        case let .text(text): return .text(text)
        case .refused(.concealed): return .concealed
        default: return .none
        }
    }

    /// The focused element's selected text through Accessibility, with a short timeout so a
    /// beachballing app cannot stall the dictation.
    static func focusedSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused as! AXUIElement?
        else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success else {
            return nil
        }
        return selected as? String
    }
}
