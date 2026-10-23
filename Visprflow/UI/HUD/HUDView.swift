import SwiftUI

/// Which job the overlay is doing. Shown as a labelled chip, never colour alone.
enum HUDMode: String, Equatable, Sendable {
    case dictate
    case paste
    case fix
    case edit

    var label: String {
        switch self {
        case .dictate: "Dictate"
        case .paste: "Smart paste"
        case .fix: "Fix screenshot"
        case .edit: "Edit selection"
        }
    }

    var icon: String {
        switch self {
        case .dictate: "mic.fill"
        case .paste: "doc.on.clipboard"
        case .fix: "ladybug"
        case .edit: "pencil.line"
        }
    }

    var tint: Color {
        switch self {
        case .dictate: .blue
        case .paste: .green
        case .fix: .orange
        case .edit: .purple
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
    /// The text landed. `pasted` for a Smart Paste; `landing` says whether ⌘Z can undo it.
    case inserted(into: String, pasted: Bool = false, landing: Landing = .undoable)
    /// The user cancelled. Not a failure, so no warning colour.
    case cancelled
    case failed(message: String)
}

struct HUDView: View {
    let state: HUDState
    var context = HUDContext()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The capsule is always the anchor. A card drops from it only when there is something
        // to decide: a preview to accept or an error to read.
        VStack(spacing: 6) {
            if let capsule = CapsuleModel.make(state, context: context) {
                CapsuleView(model: capsule, reduceMotion: reduceMotion)
            }
            if HUDLayout.showsCard(state) {
                card
                    .transition(HUDLayout.cardArrivesByCrossfade(reduceMotion: reduceMotion)
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: HUDLayout.dropDuration, dampingFraction: 0.85),
                   value: HUDLayout.showsCard(state))
    }

    @ViewBuilder
    private var card: some View {
        Group {
            switch state {
            case let .preview(model):
                preview(model)
            case let .failed(message):
                // The capsule above carries the warning glyph; the card is the cause and the
                // way out, and gets the room.
                Text(message)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            default:
                EmptyView()
            }
        }
        .frame(width: HUDLayout.cardWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Pieces

    private func preview(_ model: PreviewHUD) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mode and destination are on the capsule above; the card adds the level and what
            // was heard.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.label.uppercased())
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
                if let heard = model.heard, !heard.isEmpty {
                    Text("You said: “\(heard)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            PreviewText(text: model.text, scrollLine: model.scrollLine)
                .opacity(model.isStale ? 0.45 : 1)
            ForEach(model.notes, id: \.self) { note in
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // What left the Mac on its own line, then the keys: each readable in one glance.
            Text(model.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.hints)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
            with: NSSize(width: HUDLayout.cardWidth - 28, height: CGFloat.greatestFiniteMagnitude),
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

/// The capsule: mode, destination, meter or pulse, time, status. 36 pt tall, 280 to 460 pt
/// wide, and a line of live words under it when there are any.
private struct CapsuleView: View {
    let model: CapsuleModel
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                glyph
                if let destination = model.destination {
                    Text(destination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let meter = model.meter {
                    CapsuleMeter(level: meter, animated: !reduceMotion)
                        .accessibilityElement()
                        .accessibilityLabel("Input level")
                        .accessibilityValue("\(Int(min(1, max(0, meter * 6)) * 100)) percent")
                } else if model.working {
                    WorkingPulse(animated: !reduceMotion)
                }
                if let timer = model.timer {
                    Text(timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                // Right-aligned beside the live parts; straight after the glyph when there are none.
                if model.destination != nil || model.meter != nil || model.working || model.timer != nil {
                    Spacer(minLength: 8)
                }
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(height: CapsuleModel.height - 12)
            if let words = model.liveWords {
                // Newest words, one line: provisional text stays in our own surface, never in
                // the app being typed into, where it could not be reliably taken back.
                Text(words)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minWidth: CapsuleModel.minimumWidth, maxWidth: model.liveWords == nil ? nil : CapsuleModel.maximumWidth, alignment: .leading)
        .fixedSize(horizontal: model.liveWords == nil, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CapsuleModel.height / 2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CapsuleModel.height / 2, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var glyph: some View {
        switch model.glyph {
        case let .mode(mode):
            ModeChip(mode: mode)
        case .inserted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
        case .cancelled:
            Image(systemName: "xmark.circle").foregroundStyle(.secondary).accessibilityHidden(true)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
        }
    }
}

/// Fourteen bars driven by the current peak.
private struct CapsuleMeter: View {
    let level: Float
    var animated = true
    private let barCount = 14

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(lit(index) ? Color.red : Color.secondary.opacity(0.35))
                    .frame(width: 2.5, height: height(index))
            }
        }
        .frame(height: 16)
        .animation(animated ? .easeOut(duration: 0.08) : nil, value: level)
    }

    private func lit(_ index: Int) -> Bool {
        min(1, max(0, level * 6)) > Float(index) / Float(barCount)
    }

    private func height(_ index: Int) -> CGFloat {
        // Taller in the middle, so it reads as a voice rather than a progress bar.
        let centre = 1 - abs(CGFloat(index) / CGFloat(barCount) - 0.5) * 1.2
        return lit(index) ? max(3, 16 * centre) : 3
    }
}

/// Three dots that pulse while it works; still under Reduce Motion.
private struct WorkingPulse: View {
    let animated: Bool
    @State private var phase = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 4, height: 4)
                    .opacity(animated ? (phase ? 1 : 0.3) : 0.6)
                    .animation(animated ? .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2) : nil, value: phase)
            }
        }
        .foregroundStyle(.secondary)
        .onAppear { phase = true }
        .accessibilityHidden(true)
    }
}
