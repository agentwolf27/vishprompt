import AppKit
import SwiftUI

/// First-run setup in three steps: the permissions and speech model, the trigger key, and a
/// paste test that exercises the real insertion path rather than a stand-in.
struct OnboardingView: View {
    @Environment(AppState.self) private var state

    @State private var pasteTarget = ""
    @State private var pasteMessage: String?
    @State private var pasteInFlight = false

    private static let pasteMarker = "VishPrompt test paste ✓"

    /// Setup is three short steps rather than one long page: grant, choose the key, try it.
    /// Where rewrites go has good defaults and lives in Settings.
    @State private var step: SetupStep = .permissions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    switch step {
                    case .permissions:
                        permissions
                        speechModel
                    case .triggerKey:
                        triggerKey
                    case .tryIt:
                        pasteTest
                        nextSteps
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if let previous = step.previous {
                    Button("Back") { step = previous }
                }
                Spacer()
                Text(step.position)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let next = step.next {
                    Button("Continue") { step = next }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { NSApp.keyWindow?.close() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 580, minHeight: 680)
        .task {
            while !Task.isCancelled {
                state.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// The last step: where to try it for real, and where the rest of the settings live.
    private var nextSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Now try it for real", badge: nil)
            Text("Open Slack or Notes, click into a message, hold \(state.triggerKey.displayName) and say something. Release, and it lands where the cursor is.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Quick cleanup runs on this Mac and compiled prompts go to your Claude subscription. Change that, add an API key, or set per-app instructions in Settings (⌘,).")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Settings…") { state.showSettings() }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.title)
                .font(.largeTitle.bold())
            Text(step == .permissions
                 ? UICopy.permissionsHeadline(trigger: state.triggerKey.displayName, requiredCount: Permission.allCases.filter(\.isRequired).count)
                 : step.subtitle)
                .foregroundStyle(.secondary)
            if let error = state.startupError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Permissions", badge: state.permissions.allGranted ? "All granted" : nil)
            ForEach(Permission.allCases.filter(\.isRequired)) { permission in
                PermissionRow(permission: permission, granted: state.permissions.isGranted(permission)) {
                    Task {
                        await PermissionsService.request(permission)
                        state.refreshPermissions()
                        // Accessibility and Input Monitoring cannot be granted from a dialog
                        // this app controls, so take the user straight to the box they tick.
                        if permission.needsSettingsPane, !state.permissions.isGranted(permission) {
                            try? await Task.sleep(for: .milliseconds(400))
                            PermissionsService.openSettings(for: permission)
                        }
                    }
                } openSettings: {
                    PermissionsService.openSettings(for: permission)
                }
            }
            Text("Accessibility opens System Settings, because macOS will not let an app grant it to itself. Find VishPrompt (listed as Visprflow on older installs) and tick it. The grant is tied to this exact copy of the app, so replacing the app means granting again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var triggerKey: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Trigger key", badge: state.isListening ? "Ready" : nil)
            Text("Press the key you want to hold while talking. Any key works, including ones on a third-party keyboard. A modifier such as Option or Command is the best choice, because it types nothing on its own.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current key").font(.caption).foregroundStyle(.secondary)
                    Text(state.triggerKey.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(state.isRecordingTrigger ? .secondary : .primary)
                }
                Spacer()
                if state.isRecordingTrigger {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Press any key…").font(.callout)
                        Button("Cancel") { state.cancelTriggerRecording() }
                    }
                } else {
                    Button("Set a different key…") { state.recordTriggerKey() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!state.isListening)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            if let refusal = state.triggerRefusal {
                Text(refusal)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !state.isListening {
                Text("Grant the permissions above first; the key can only be recorded once the app is watching the keyboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Raised by the runtime check when the key fires while the user is typing, which
            // catches keyboards the static rules cannot know about.
            if let warning = state.dictation?.triggerWarning {
                calloutRow(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    text: warning,
                    button: "Use Right Option"
                ) {
                    state.setTriggerKey(.rightOption)
                }
            }

            if let reason = state.triggerKey.unsuitableReason {
                calloutRow(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    text: "\(state.triggerKey.displayName) is a poor trigger. \(reason)",
                    button: "Use Right Option"
                ) {
                    state.setTriggerKey(.rightOption)
                }
            }

            HStack(spacing: 8) {
                Text("Or pick one:").font(.caption).foregroundStyle(.secondary)
                ForEach(TriggerKey.presets, id: \.self) { key in
                    Button(key.displayName) { state.setTriggerKey(key) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            if state.triggerKey == .fn, state.fnUsage.conflictsWithTrigger {
                calloutRow(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    text: "Your fn key currently \(state.fnUsage.description). macOS handles that before any app sees the key, so set it to “Do Nothing” for a clean trigger.",
                    button: "Open Keyboard Settings"
                ) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
            }
        }
    }

    private var speechModel: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Speech model", badge: nil)
            Text("Parakeet v3 runs on this Mac's Neural Engine. Roughly 600 MB on first run. Audio never leaves the machine.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let progress = state.dictation?.modelProgress {
                ProgressView(value: progress) {
                    Text("Downloading… \(Int(progress * 100))%").font(.caption)
                }
            } else if let failure = state.dictation?.modelFailure {
                HStack(alignment: .firstTextBaseline) {
                    Text(UICopy.modelDownloadFailed(failure))
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Retry") {
                        Task { await state.dictation?.warmUp() }
                    }
                }
            }
        }
    }

    private var pasteTest: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Test insertion", badge: nil)
            Text("Click into the field, then press the button. This runs the real insertion path: it writes the clipboard, synthesises the paste, and puts your clipboard back.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Paste lands here", text: $pasteTarget)
                    .textFieldStyle(.roundedBorder)
                Button("Test paste") { runPasteTest() }
                    .disabled(!state.permissions.accessibility || pasteInFlight)
            }
            if let pasteMessage {
                Text(pasteMessage).font(.caption).foregroundStyle(.secondary)
            }
            Text("The real test is holding your trigger key in another app. This one only proves the Accessibility grant works.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Pieces

    // MARK: Actions

    private func runPasteTest() {
        pasteTarget = ""
        pasteInFlight = true
        pasteMessage = "Pasting…"
        Task {
            defer { pasteInFlight = false }
            do {
                try await Inserter().insert(Self.pasteMarker, strategy: .paste)
                pasteMessage = pasteTarget.contains(Self.pasteMarker)
                    ? "Insertion works, and your clipboard was restored."
                    : "Nothing arrived. Give the field above focus, then try again."
            } catch {
                pasteMessage = error.localizedDescription
            }
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let granted: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(permission.title).font(.body.weight(.semibold))
                Text(permission.why).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if !granted {
                // One button: for a permission granted in System Settings, the request
                // itself opens the right pane, so a second "Open Settings" did the same thing.
                Button(permission.needsSettingsPane ? "Open System Settings" : "Allow", action: request)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The three steps of first-run setup.
enum SetupStep: Int, CaseIterable, Sendable {
    case permissions, triggerKey, tryIt

    var title: String {
        switch self {
        case .permissions: "Set up VishPrompt"
        case .triggerKey: "Choose your key"
        case .tryIt: "Try it"
        }
    }

    var subtitle: String {
        switch self {
        case .permissions: ""
        case .triggerKey: "The key you hold while you talk. Hold it now: the overlay appears near the top of the screen."
        case .tryIt: "One check that pasting works, then the real thing."
        }
    }

    var position: String { "Step \(rawValue + 1) of \(Self.allCases.count)" }
    var next: SetupStep? { SetupStep(rawValue: rawValue + 1) }
    var previous: SetupStep? { SetupStep(rawValue: rawValue - 1) }
}
