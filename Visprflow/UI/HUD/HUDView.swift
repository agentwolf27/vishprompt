import SwiftUI

/// Which job the overlay is doing. Shown as a labelled chip, never colour alone.
enum HUDMode: String, Equatable, Sendable {
    case dictate
    case paste
    case fix

    var label: String {
        switch self {
        case .dictate: "Dictate"
        case .paste: "Smart paste"
        case .fix: "Fix screenshot"
        }
    }

    var icon: String {
        switch self {
        case .dictate: "mic.fill"
        case .paste: "doc.on.clipboard"
        case .fix: "ladybug"
        }
    }

    var tint: Color {
        switch self {
        case .dictate: .blue
        case .paste: .green
        case .fix: .orange
        }
    }
}

/// Everything a preview shows: what will land, where, and what left the Mac to make it.
struct PreviewHUD: Equatable, Sendable {
    var text: String
    var mode: HUDMode
    var destination: String
    /// The level or form on screen: "Compiled", "Rewritten", "As copied".
    var label: String
    /// What the user said, when it changes the result: a mishearing is visible before it lands.
    var heard: String?
    /// Plain lines: secrets removed, numbers checked, why a fallback happened.
    var notes: [String] = []
    /// Where the words went: "Stayed on this Mac." or "Sent your words to …".
    var source: String
    var hints: String
    /// True while a different level is being compiled: the old text stays, dimmed.
    var isStale = false
    /// First line shown, moved by ↑ and ↓.
    var scrollLine = 0
}

/// What the overlay is showing right now.
enum HUDState: Equatable, Sendable {
    case hidden
    /// Recording. `locked` means hands-free, so the key is not being held.
    case listening(level: Float, seconds: TimeInterval, locked: Bool, partial: String = "", mode: HUDMode = .dictate, app: String? = nil)
    case transcribing
    /// The compiler is streaming its result in. Phase 2 fills this with real text.
    /// `provider` says where it is running: "via your Claude subscription".
    case compiling(partial: String, provider: String? = nil)
    /// Waiting for the user to press Return to insert.
    case preview(PreviewHUD)
    /// The text landed. `pasted` for a Smart Paste.
    case inserted(into: String, pasted: Bool = false)
    /// The user cancelled. Not a failure, so no warning colour.
    case cancelled
    case failed(message: String)
}

struct HUDView: View {
    let state: HUDState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch state {
            case .hidden:
                EmptyView()
            case let .listening(level, seconds, locked, partial, mode, app):
                listening(level: level, seconds: seconds, locked: locked, partial: partial, mode: mode, app: app)
            case .transcribing:
                row(icon: "waveform", tint: .secondary) {
                    Text("Transcribing…").foregroundStyle(.secondary)
                }
            case let .compiling(partial, provider):
                row(icon: "sparkles", tint: .accentColor) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let provider {
                            Text("Rewriting \(provider)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        // The newest words, not the first three lines: a long prompt that
                        // only ever shows its opening reads as stalled.
                        Text(partial.isEmpty ? (provider == nil ? "Working…" : "Waiting for the first words…") : partial)
                            .lineLimit(3)
                            .truncationMode(.head)
                    }
                }
            case let .preview(model):
                preview(model)
            case let .inserted(destination, pasted):
                row(icon: "checkmark.circle.fill", tint: .green) {
                    Text(UICopy.inserted(into: destination, pasted: pasted)).foregroundStyle(.secondary)
                }
            case .cancelled:
                row(icon: "xmark.circle", tint: .secondary) {
                    Text("Cancelled").foregroundStyle(.secondary)
                }
            case let .failed(message):
                row(icon: "exclamationmark.triangle.fill", tint: .orange) {
                    // Messages now carry the cause and the way out, so they get the room.
                    Text(message)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(width: 460, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Pieces

    private func listening(
        level: Float,
        seconds: TimeInterval,
        locked: Bool,
        partial: String,
        mode: HUDMode,
        app: String?
    ) -> some View {
        row(icon: locked ? "lock.fill" : mode.icon, tint: .red) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ModeChip(mode: mode)
                    Text(locked ? "Hands-free" : "Listening")
                        .font(.callout.weight(.medium))
                    if let app {
                        Text("into \(app)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(Self.elapsed(seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(mode == .paste ? "say how to paste it, or just release · esc" : locked ? "tap to stop · esc" : "release to compile · esc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LevelMeter(level: level, animated: !reduceMotion)
                    .accessibilityElement()
                    .accessibilityLabel("Input level")
                    .accessibilityValue("\(Int(min(1, max(0, level * 6)) * 100)) percent")
                // Words appear here as they are recognised, so a long dictation shows progress
                // rather than an anonymous meter. Deliberately in our own overlay: provisional
                // text cannot be reliably retracted from the app being typed into.
                if !partial.isEmpty {
                    Text(partial)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
        }
    }

    private func preview(_ model: PreviewHUD) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ModeChip(mode: model.mode)
                Text("into \(model.destination)")
                    .font(.caption.weight(.medium))
                Text(model.label.uppercased())
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
                Spacer()
            }
            if let heard = model.heard, !heard.isEmpty {
                Text("You said: “\(heard)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            PreviewText(text: model.text, scrollLine: model.scrollLine)
                .opacity(model.isStale ? 0.45 : 1)
            ForEach(model.notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(model.hints)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private func row<Content: View>(
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
                // Decorative: the text beside it says the same thing.
                .accessibilityHidden(true)
            content()
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private static func elapsed(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// The whole preview, scrollable. A compiled prompt is often longer than five lines, and
/// Return should never insert text nobody could read. Grows to about 40% of the screen, then
/// scrolls: with the pointer, or with ↑ and ↓, which the overlay owns while a preview is up.
private struct PreviewText: View {
    let text: String
    let scrollLine: Int

    private var lines: [String] {
        text.components(separatedBy: "\n")
    }

    private static var maximumHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) * 0.4
    }

    /// Measured rather than left to SwiftUI: a ScrollView in a self-sizing panel has no ideal
    /// height of its own, and would either collapse or take the whole screen.
    private var contentHeight: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .callout)
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: 432, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(bounds.height) + 4
    }

    var body: some View {
        let height = min(contentHeight, Self.maximumHeight)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(index)
                    }
                }
                .textSelection(.enabled)
            }
            .frame(height: height)
            .onChange(of: scrollLine) { _, line in
                proxy.scrollTo(min(max(0, line), max(0, lines.count - 1)), anchor: .top)
            }
        }
        if contentHeight > Self.maximumHeight {
            Text("\(lines.count) lines · ↑↓ to scroll")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The mode, as a labelled capsule: the text carries the meaning, the colour only helps.
private struct ModeChip: View {
    let mode: HUDMode

    var body: some View {
        Text(mode.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(mode.tint.opacity(0.25), in: Capsule())
            .accessibilityLabel("\(mode.label) mode")
    }
}

/// Twenty bars driven by the current peak, with a little decay so it reads as a voice
/// rather than a flickering number.
private struct LevelMeter: View {
    let level: Float
    /// Off under Reduce Motion: the bars jump to the level instead of easing.
    var animated = true
    private let barCount = 28

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(colour(for: index))
                        .frame(width: 3, height: height(for: index, in: geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 18)
        .animation(animated ? .easeOut(duration: 0.08) : nil, value: level)
    }

    private func normalised(_ index: Int) -> Float {
        // A log-ish curve, so quiet speech still moves the meter.
        let scaled = min(1, max(0, level * 6))
        let position = Float(index) / Float(barCount)
        return scaled > position ? 1 : 0.12
    }

    private func height(for index: Int, in available: CGFloat) -> CGFloat {
        let base = CGFloat(normalised(index))
        // Taller in the middle so it reads as a waveform rather than a progress bar.
        let centre = 1 - abs(CGFloat(index) / CGFloat(barCount) - 0.5) * 1.2
        return max(3, available * base * centre)
    }

    private func colour(for index: Int) -> Color {
        normalised(index) > 0.5 ? .red : .secondary.opacity(0.4)
    }
}
