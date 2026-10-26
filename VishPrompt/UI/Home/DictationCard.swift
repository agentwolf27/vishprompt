import AppKit
import SwiftUI

/// One saved dictation: when, where, how, whether the words left the Mac, the text, and
/// Copy, "What you said", pin and delete.
struct DictationCard: View {
    @Environment(\.homeTheme) private var theme
    let entry: HistoryEntry
    let library: HomeLibrary
    let reuse: HistoryReuse
    var selected = false

    private var record: DictationRecord { entry.record }

    var body: some View {
        let text = HistoryFormat.reusableText(record)
        let showSaid = library.expanded.contains(entry.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, design: .monospaced))
                (Text("→ ") + Text(HistoryFormat.appName(record)).foregroundColor(theme.ink.color).fontWeight(.medium))
                    .font(.system(size: 12))
                Pill(text: DictationMode.of(record).title, fill: nil, ink: theme.muted, border: theme.line)
                WherePill(where: WhereItWent(record))
                if record.status != .inserted {
                    Text(HistoryFormat.status(record.status)).font(.system(size: 12))
                }
                if record.pinned {
                    Text("Pinned").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accent.color)
                }
            }
            .foregroundStyle(theme.muted.color)
            .lineLimit(1)

            HStack(alignment: .top, spacing: 16) {
                Text(text ?? "Nothing was said.")
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(text == nil ? theme.muted.color : theme.ink.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if let text {
                        CopyButton(text: text, prominent: true, reuse: reuse, id: entry.id)
                    }
                    IconButton(symbol: record.pinned ? "pin.slash" : "pin", label: record.pinned ? "Unpin" : "Pin to top") {
                        library.setPinned(!record.pinned, entry)
                    }
                    IconButton(symbol: "trash", label: "Delete") { library.delete(entry) }
                }
            }

            if !record.rawTranscript.isEmpty {
                Button(showSaid ? "Hide what you said" : "What you said") {
                    if showSaid { library.expanded.remove(entry.id) } else { library.expanded.insert(entry.id) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.muted.color)
                .frame(minHeight: 28)

                if showSaid {
                    HStack(alignment: .top, spacing: 12) {
                        Text("“\(record.rawTranscript)”")
                            .font(.system(size: 13).italic())
                            .lineSpacing(3)
                            .foregroundStyle(theme.muted.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        CopyButton(text: record.rawTranscript, prominent: false, reuse: reuse, id: entry.id, said: true)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(theme.sunk.color))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .homeCard(radius: 14, border: record.pinned || selected ? theme.accent : nil)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.accent.color, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(HistoryFormat.appName(record)), \(record.createdAt.formatted(date: .omitted, time: .shortened)), \(DictationMode.of(record).title), \(WhereItWent(record).label)")
    }
}

/// Copy, which says "Copied" for a moment so you know it worked.
struct CopyButton: View {
    @Environment(\.homeTheme) private var theme
    let text: String
    let prominent: Bool
    let reuse: HistoryReuse
    /// The row this text belongs to, so the copy is counted on it.
    var id: String? = nil
    var said = false
    @State private var copied = false

    static let copiedFor: Duration = .milliseconds(1400)

    var body: some View {
        Button {
            reuse.copy(text, id: id, ofWhatWasSaid: said)
            copied = true
            Task {
                try? await Task.sleep(for: Self.copiedFor)
                copied = false
            }
        } label: {
            Text(copied ? "Copied" : "Copy")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .frame(minWidth: 72, minHeight: 36)
                .foregroundStyle(prominent && !copied ? .white : copied ? theme.accent.color : theme.ink.color)
                .background(RoundedRectangle(cornerRadius: 9).fill(prominent && !copied ? theme.accent.color : copied ? .clear : theme.card.color))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(copied ? theme.accent.color : prominent ? .clear : theme.line.color))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : "Copy")
    }
}

struct IconButton: View {
    @Environment(\.homeTheme) private var theme
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 36, height: 36)
                .foregroundStyle(theme.muted.color)
                .background(RoundedRectangle(cornerRadius: 9).fill(theme.card.color))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.line.color))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct Pill: View {
    let text: String
    let fill: RGB?
    let ink: RGB
    var border: RGB?

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: fill == nil ? .regular : .medium))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(ink.color)
            .background(Capsule().fill(fill?.color ?? .clear))
            .overlay(Capsule().strokeBorder(border?.color ?? .clear))
    }
}

struct WherePill: View {
    @Environment(\.homeTheme) private var theme
    let `where`: WhereItWent

    var body: some View {
        switch self.where {
        case .stayedOnThisMac: Pill(text: self.where.label, fill: theme.stayedFill, ink: theme.stayedInk)
        case .sentToClaude: Pill(text: self.where.label, fill: theme.sentFill, ink: theme.sentInk)
        case .notRecorded: Pill(text: self.where.label, fill: nil, ink: theme.muted, border: theme.line)
        }
    }
}

// MARK: History

struct HistoryPageView: View {
    @Environment(\.homeTheme) private var theme
    @Bindable var library: HomeLibrary
    let reuse: HistoryReuse
    let now: Date
    @FocusState private var listFocused: Bool

    var body: some View {
        let groups = library.historyGroups(now: now)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Text("History").font(.system(size: 26, weight: .semibold))
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.muted.color)
                    TextField("Search what you said, or an app", text: $library.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .accessibilityLabel("Search history")
                }
                .padding(.horizontal, 12)
                .frame(width: 340, height: 40)
                .homeCard(radius: 10)
            }
            .padding(.horizontal, 36).padding(.top, 40)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let error = library.loadError {
                            EmptyNote(text: error)
                        } else if groups.isEmpty {
                            EmptyNote(text: library.query.trimmingCharacters(in: .whitespaces).isEmpty
                                      ? "Nothing yet. Hold \(library.triggerName) and say something; it shows up here."
                                      : HistoryFormat.noMatch(library.query))
                        }
                        ForEach(groups, id: \.label) { group in
                            SectionLabel(text: group.label)
                            ForEach(group.entries) { entry in
                                DictationCard(entry: entry, library: library, reuse: reuse, selected: library.selection == entry.id)
                                    .id(entry.id)
                                    .onTapGesture {
                                        library.selection = entry.id
                                        listFocused = true
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 36).padding(.bottom, 28)
                }
                .scrollContentBackground(.hidden)
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                // Return pastes the selected card again into the app you came from (v2 step 4).
                .onKeyPress(.return) {
                    guard let text = library.selectedText else { return .ignored }
                    reuse.pasteAgain(text, id: library.selection)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    library.moveSelection(by: 1, now: now)
                    if let id = library.selection { proxy.scrollTo(id) }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    library.moveSelection(by: -1, now: now)
                    if let id = library.selection { proxy.scrollTo(id) }
                    return .handled
                }
                .onCopyCommand {
                    if let text = library.selectedText { reuse.copy(text, id: library.selection) }
                    return []
                }
            }

            HistoryFooter(library: library, reuse: reuse)
        }
    }
}

/// The line under History: what just happened, Undo for a delete, or how the keys work.
private struct HistoryFooter: View {
    @Environment(\.homeTheme) private var theme
    let library: HomeLibrary
    let reuse: HistoryReuse

    var body: some View {
        HStack(spacing: 12) {
            if library.lastDeleted != nil {
                Text("Deleted from this Mac.")
                Button("Undo") { library.undoDelete() }
                    .buttonStyle(.link)
                    .foregroundStyle(theme.accent.color)
                    .task {
                        try? await Task.sleep(for: .seconds(8))
                        library.dismissUndo()
                    }
            } else {
                Text(reuse.message ?? HistoryReuse.hint(target: reuse.targetName).replacingOccurrences(of: "Return pastes it", with: "Select a card; Return pastes it"))
            }
            Spacer()
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.muted.color)
        .padding(.horizontal, 36).padding(.vertical, 10)
        .background(theme.sidebar.color)
        .overlay(alignment: .top) { theme.line.color.frame(height: 1) }
    }
}
