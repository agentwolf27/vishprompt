import AppKit
import SwiftUI

/// The menu bar menu. A real menu rather than a window built to look like one, as the HIG asks:
/// keyboard navigation, VoiceOver and ⌘ shortcuts come for free.
struct MenuBarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // Status lines are disabled items: they inform, they do not act.
        Text("VishPrompt: \(state.statusSummary)")
        ForEach(MenuModel.permissionLines(state.permissions), id: \.self) { line in
            Text(line)
        }
        if let error = state.startupError {
            Text(error)
        }
        if state.isListening {
            Text("Hold \(state.triggerKey.displayName) to dictate, add V for Smart Paste")
        }

        Divider()

        Button("Open VishPrompt…") { state.showHistory() }
            .keyboardShortcut("y", modifiers: .command)
        Menu("Last dictation") {
            Button("Copy") { MenuModel.copyLastDictation() }
            Button("Paste again") { MenuModel.pasteLastDictation() }
        }

        Toggle("Pause dictation", isOn: Binding(
            get: { state.isPaused },
            set: { state.setPaused($0) }
        ))

        Divider()

        Button("Settings…") { state.showSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button(state.permissions.allGranted ? "Setup…" : "Finish setup…") { state.showSetup() }

        Divider()

        Button("Quit VishPrompt") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

/// What the menu shows and does, apart from the view so it can be tested.
@MainActor
enum MenuModel {
    /// One line per required permission, in words: a tick image alone says nothing to
    /// VoiceOver, and a menu item cannot hold a coloured icon reliably.
    static func permissionLines(_ status: PermissionStatus) -> [String] {
        Permission.allCases.filter(\.isRequired).map { permission in
            "\(permission.title): \(status.isGranted(permission) ? "granted" : "not granted")"
        }
    }

    /// The last dictation's text, from history.
    static func lastDictation() -> String? {
        guard let queue = Database.queue else { return nil }
        return try? Database.lastDictationText(in: queue)
    }

    static func copyLastDictation() {
        guard let text = lastDictation() else { return }
        TextRescue.copy(text)
    }

    /// Pastes into whatever was in front before the menu opened. The menu has to close and
    /// focus return first, so wait a moment.
    static func pasteLastDictation() {
        guard let text = lastDictation() else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            try? await Inserter().insert(text, strategy: .paste)
        }
    }
}
