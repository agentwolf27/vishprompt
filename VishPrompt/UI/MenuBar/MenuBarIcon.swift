import SwiftUI

/// The overlay's state as the menu bar icon needs it: three values, not one per meter level.
enum HUDPhase: Equatable, Sendable {
    case idle
    case recording
    /// Transcribing, rewriting, or a preview waiting for Return.
    case working

    init(_ hud: HUDState) {
        switch hud {
        case .listening: self = .recording
        case .transcribing, .compiling, .preview: self = .working
        case .hidden, .inserted, .cancelled, .failed: self = .idle
        }
    }
}

/// What the menu bar glyph says at a glance. The menu says why; the glyph only says which.
enum MenuBarIconState: Equatable, Sendable {
    case ready
    case recording
    /// Transcribing, rewriting, or a preview waiting for Return.
    case working
    case paused
    case needsSetup
    /// Permissions are granted but the keyboard watch or the model failed to start.
    case couldNotStart

    /// Setup outranks pause, and pause outranks whatever the overlay last showed, so the icon
    /// never claims a recording the app is not in a position to make.
    static func make(permissionsGranted: Bool, startupFailed: Bool, isPaused: Bool, phase: HUDPhase?) -> MenuBarIconState {
        if !permissionsGranted { return .needsSetup }
        if startupFailed { return .couldNotStart }
        if isPaused { return .paused }
        switch phase {
        case .recording?: return .recording
        case .working?: return .working
        case .idle?, nil: return .ready
        }
    }

    var symbol: String {
        switch self {
        case .ready: "mic.fill"
        case .recording: "waveform"
        case .working: "ellipsis.circle.fill"
        case .paused: "pause.circle"
        case .needsSetup, .couldNotStart: "exclamationmark.triangle.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .ready: "VishPrompt, ready"
        case .recording: "VishPrompt, recording"
        case .working: "VishPrompt, working"
        case .paused: "VishPrompt, paused"
        case .needsSetup: "VishPrompt, setup needed"
        case .couldNotStart: "VishPrompt, couldn't start. Open the menu for why"
        }
    }
}

/// The menu bar glyph. A View, so `@Observable` tracking applies and the icon follows
/// permission and recording changes instead of freezing at its launch value.
struct MenuBarIcon: View {
    let state: AppState

    var body: some View {
        let icon = MenuBarIconState.make(
            permissionsGranted: state.permissions.allGranted,
            startupFailed: state.startupError != nil,
            isPaused: state.isPaused,
            phase: state.dictation?.hudPhase
        )
        Image(systemName: icon.symbol)
            .accessibilityLabel(icon.accessibilityLabel)
    }
}
