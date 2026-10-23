import SwiftUI

/// Per-destination settings: the free-text instruction, the default edit level, and whether
/// a compiled prompt waits for Return.
///
/// This is the control Wispr Flow does not offer. It ships four fixed tones chosen by app
/// category, English only, with no way to say "in Slack keep it lowercase" or "for Claude Code
/// always ask for a plan when more than one file changes".
struct DestinationSettingsView: View {
    /// Saves every change as it is made: no Save button, and nothing lost by switching rows.
    @State private var editor = DestinationEditor()

    private var destination: Destination {
        Destination.named(editor.selection) ?? .document
    }

    private var draft: DestinationOverride { editor.current }

    var body: some View {
        HSplitView {
            list
            detail
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    private var list: some View {
        List(Destination.all, id: \.id, selection: Binding(
            get: { editor.selection },
            set: { if let id = $0 { editor.select(id) } }
        )) { item in
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.body)
                Text(summary(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(item.id)
            .padding(.vertical, 2)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination.displayName).font(.title2.weight(.semibold))
                    Text(defaultsDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your instructions").font(.headline)
                    Text("Added to the compiler's rules for this destination only. Written the way you would tell a colleague.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { draft.instructions ?? "" },
                        set: { value in editor.update { $0.instructions = value } }
                    ))
                    .font(.body.monospaced())
                    .frame(minHeight: 110)
                    .padding(6)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                    Text(placeholder(for: destination))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Behaviour").font(.headline)

                    Picker("Edit level", selection: Binding(
                        get: { draft.defaultLevel ?? destination.defaultLevel },
                        set: { value in editor.update { $0.defaultLevel = value } }
                    )) {
                        ForEach(EditLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    Text(( draft.defaultLevel ?? destination.defaultLevel ).summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Show a preview before inserting", isOn: Binding(
                        get: { draft.requiresPreview ?? destination.requiresPreview },
                        set: { value in editor.update { $0.requiresPreview = value } }
                    ))
                    Text("Worth the keystroke where a wrong prompt costs more than a wrong message.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Insertion", selection: Binding(
                        get: { draft.strategy ?? destination.strategy },
                        set: { value in editor.update { $0.strategy = value } }
                    )) {
                        ForEach(InsertionStrategy.allCases, id: \.self) { strategy in
                            Text(UICopy.insertionLabel(strategy)).tag(strategy)
                        }
                    }
                }

                HStack {
                    Button("Reset to defaults") { editor.reset() }
                    Spacer()
                    Text("Changes save as you make them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Helpers

    private var defaultsDescription: String {
        let level = destination.defaultLevel.displayName.lowercased()
        let preview = destination.requiresPreview ? "shows a preview first" : "inserts straight away"
        return "By default: \(level) editing, \(preview)."
    }

    private func summary(for item: Destination) -> String {
        // The selected row reads the editor, which SwiftUI observes, so its subtitle follows
        // each edit; the others read what is saved.
        UICopy.destinationSubtitle(item, override: item.id == editor.selection ? editor.current : editor.override(for: item.id))
    }

    private func placeholder(for destination: Destination) -> String {
        switch destination.id {
        case "claude_code", "cursor", "codex":
            "For example: always ask for a plan first when more than one file changes."
        case "message":
            "For example: keep it lowercase, no greetings."
        case "email":
            "For example: sign off with my first name only."
        default:
            "For example: keep sentences short."
        }
    }
}
