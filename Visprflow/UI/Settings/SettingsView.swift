import AppKit
import SwiftUI

/// The panes of the Settings window.
enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general, providers, destinations, vocabulary, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .providers: "Providers"
        case .destinations: "Destinations"
        case .vocabulary: "Vocabulary"
        case .privacy: "Privacy"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .providers: "sparkles"
        case .destinations: "app.badge"
        case .vocabulary: "character.book.closed"
        case .privacy: "hand.raised"
        }
    }
}

/// Remembers the last pane, so ⌘, opens where the user left off (HIG: restore the last pane).
struct SettingsPaneStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "settingsPane"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var last: SettingsPane {
        defaults.string(forKey: key).flatMap(SettingsPane.init(rawValue:)) ?? .general
    }

    func remember(_ pane: SettingsPane) {
        defaults.set(pane.rawValue, forKey: key)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var pane = SettingsPaneStore().last
    /// Lets the window controller put the pane's name in the title bar.
    var onPaneChange: (SettingsPane) -> Void = { _ in }

    var body: some View {
        TabView(selection: $pane) {
            GeneralPane()
                .tabItem { Label(SettingsPane.general.title, systemImage: SettingsPane.general.icon) }
                .tag(SettingsPane.general)
            ProvidersPane()
                .tabItem { Label(SettingsPane.providers.title, systemImage: SettingsPane.providers.icon) }
                .tag(SettingsPane.providers)
            DestinationSettingsView()
                .tabItem { Label(SettingsPane.destinations.title, systemImage: SettingsPane.destinations.icon) }
                .tag(SettingsPane.destinations)
            VocabularyPane()
                .tabItem { Label(SettingsPane.vocabulary.title, systemImage: SettingsPane.vocabulary.icon) }
                .tag(SettingsPane.vocabulary)
            PrivacyPane()
                .tabItem { Label(SettingsPane.privacy.title, systemImage: SettingsPane.privacy.icon) }
                .tag(SettingsPane.privacy)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { onPaneChange(pane) }
        .onChange(of: pane) { _, value in
            SettingsPaneStore().remember(value)
            onPaneChange(value)
        }
    }
}

// MARK: General

private struct GeneralPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section("Trigger key") {
                LabeledContent("Hold to dictate", value: state.triggerKey.displayName)
                HStack {
                    if state.isRecordingTrigger {
                        ProgressView().controlSize(.small)
                        Text("Press any key…")
                        Button("Cancel") { state.cancelTriggerRecording() }
                    } else {
                        Button("Set a different key…") { state.recordTriggerKey() }
                            .disabled(!state.isListening)
                        ForEach(TriggerKey.presets, id: \.self) { key in
                            Button(key.displayName) { state.setTriggerKey(key) }
                                .buttonStyle(.link)
                        }
                    }
                }
                if let reason = state.triggerKey.unsuitableReason {
                    Text("\(state.triggerKey.displayName) is a poor trigger. \(reason)")
                        .foregroundStyle(.orange)
                }
            }
            Section("Shortcuts") {
                LabeledContent("Dictate", value: "hold \(state.triggerKey.displayName)")
                LabeledContent("Hands-free", value: "double-tap \(state.triggerKey.displayName)")
                LabeledContent("Smart Paste", value: "hold \(state.triggerKey.displayName), press V")
                LabeledContent("Exactly as said", value: "hold Shift with the key")
                LabeledContent("Full prompt", value: "hold Control with the key")
            }
            Section {
                Button("Run setup again…") { state.showSetup() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Vocabulary

private struct VocabularyPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section {
                Text("When you dictate into a terminal running Claude Code or Codex, VishPrompt reads the project's file names and identifiers so they are spelled the way the code spells them. They are a spelling authority only: nothing is added that you did not say.")
                    .foregroundStyle(.secondary)
            }
            if let snapshot = state.dictation?.lastVocabulary, !snapshot.terms.isEmpty {
                Section("From \(snapshot.repository)\(snapshot.branch.map { " on \($0)" } ?? "") · \(snapshot.terms.count) words") {
                    Text(snapshot.terms.prefix(150).joined(separator: "  ·  "))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            } else {
                Section {
                    Text("No project yet. Dictate into a terminal running Claude Code or Codex, and its words appear here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Privacy

private struct PrivacyPane: View {
    @State private var policy = ProviderSettings().policy()
    @State private var consentVersion = 0
    private let consent = SmartPasteConsent()

    var body: some View {
        Form {
            Section("What leaves this Mac") {
                LabeledContent("Audio", value: "never")
                LabeledContent("Screenshots", value: "never; their text only if you insert the prompt")
                LabeledContent("Quick cleanup", value: Self.destination(policy.fastPath))
                LabeledContent("Compiled prompts", value: Self.destination(policy.compilePath))
                if policy.fastPath == .local, policy.compilePath == .local {
                    Text("Both are on this Mac, so nothing is sent anywhere.")
                        .foregroundStyle(.green)
                }
            }
            Section("Smart Paste") {
                Text("Your clipboard is sent only when you speak an instruction, with known secret shapes removed, and only to a provider you have allowed.")
                    .foregroundStyle(.secondary)
                ForEach(ProviderChoice.allCases.filter { $0 != .local }, id: \.self) { provider in
                    HStack {
                        Text(provider.displayName)
                        Spacer()
                        let allowed = consent.state(for: provider) == .granted
                        Text(allowed ? "allowed" : "not allowed")
                            .foregroundStyle(.secondary)
                        if allowed {
                            Button("Revoke") {
                                consent.revoke(provider)
                                consentVersion += 1
                            }
                        }
                    }
                    .id("\(provider.rawValue)-\(consentVersion)")
                }
            }
            Section("History") {
                Text("Every dictation is stored on this Mac with exactly what was sent, so the claims above can be checked.")
                    .foregroundStyle(.secondary)
                Button("Show the history file in Finder") {
                    if let url = Database.fileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { policy = ProviderSettings().policy() }
    }

    static func destination(_ provider: ProviderChoice) -> String {
        provider == .local ? "stays on this Mac" : "your words go to \(provider.destinationPhrase)"
    }
}
