import SwiftUI

/// Where rewrites go, and the API key when one is needed. Moved out of first-run setup:
/// the defaults work without touching it, and it is something people change later.
struct ProvidersPane: View {
    @State private var apiKeyDraft = ""
    @State private var hasStoredKey = false
    @State private var keyMessage: String?

    @State private var policy = ProviderSettings().policy()
    private let providerSettings = ProviderSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                providers
                if policy.fastPath == .apiKey || policy.compilePath == .apiKey {
                    apiKey
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { loadKeyState() }
    }

    private var providers: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Where rewrites go", badge: nil)
            Text("Cleaning up a message and compiling a prompt are different jobs, so they can use different providers.")
                .font(.callout)
                .foregroundStyle(.secondary)

            providerPicker(
                title: "Quick cleanup",
                subtitle: "Fillers, punctuation, capitalisation. Happens constantly, so it should feel instant.",
                selection: Binding(
                    get: { policy.fastPath },
                    set: { policy.fastPath = $0; providerSettings.save(policy) }
                )
            )
            providerPicker(
                title: "Compiled prompts",
                subtitle: "Restructuring a rambling request. Rarer, and you see a preview while it works.",
                selection: Binding(
                    get: { policy.compilePath },
                    set: { policy.compilePath = $0; providerSettings.save(policy) }
                )
            )

            if policy.fastPath == .subscription {
                calloutRow(
                    icon: "clock.fill",
                    tint: .orange,
                    text: "Quick cleanup through the subscription takes 6 to 10 seconds, because it starts a new Claude Code session each time. On this Mac it is worth leaving on “On this Mac”.",
                    button: "Use this Mac"
                ) {
                    policy.fastPath = .local
                    providerSettings.save(policy)
                }
            }
            if !ClaudeCLIGenerator.isAvailable,
               policy.fastPath == .subscription || policy.compilePath == .subscription {
                calloutRow(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    text: "The claude command line tool was not found. Install Claude Code, or pick another provider.",
                    button: "Use an API key"
                ) {
                    policy.compilePath = .apiKey
                    providerSettings.save(policy)
                }
            }
        }
    }

    private func providerPicker(
        title: String,
        subtitle: String,
        selection: Binding<ProviderChoice>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.body.weight(.medium))
                Spacer()
                Text(selection.wrappedValue.latencyNote)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(ProviderChoice.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(selection.wrappedValue.summary)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var apiKey: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Anthropic API key", badge: hasStoredKey ? "Stored in Keychain" : nil)
            Text("Needed because you picked the API above. Switching back to your Claude subscription removes the need for a key entirely.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                SecureField("sk-ant-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Button(hasStoredKey ? "Replace" : "Save") { saveKey() }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasStoredKey {
                    Button("Remove", role: .destructive) { removeKey() }
                }
            }
            if let keyMessage {
                Text(keyMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private func loadKeyState() {
        do {
            hasStoredKey = try Keychain.get(.anthropicAPIKey) != nil
        } catch {
            keyMessage = UICopy.keychainFailure(.read)
            Log.app.error("Keychain read failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func saveKey() {
        do {
            try Keychain.set(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: .anthropicAPIKey)
            apiKeyDraft = ""
            hasStoredKey = true
            keyMessage = "Saved."
        } catch {
            keyMessage = UICopy.keychainFailure(.save)
            Log.app.error("Keychain save failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func removeKey() {
        do {
            try Keychain.delete(.anthropicAPIKey)
            hasStoredKey = false
            keyMessage = "Removed."
        } catch {
            keyMessage = UICopy.keychainFailure(.remove)
            Log.app.error("Keychain remove failed: \(String(describing: error), privacy: .public)")
        }
    }
}
