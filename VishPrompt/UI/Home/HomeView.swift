import AppKit
import SwiftUI

/// The VishPrompt window: a sidebar with Home, History, Dictionary and Settings, in the warm
/// light or dark theme. Opens from the menu and ⌘Y.
struct HomeView: View {
    @Bindable var library: HomeLibrary
    let reuse: HistoryReuse
    /// Injected so snapshots show a fixed morning; the window uses the clock.
    var now: () -> Date = Date.init

    static let minimumSize = CGSize(width: 1040, height: 700)

    var body: some View {
        HomeThemed {
            HomeLayout(library: library, reuse: reuse, now: now)
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .onAppear { library.reload() }
    }
}

private struct HomeLayout: View {
    @Environment(\.homeTheme) private var theme
    @Bindable var library: HomeLibrary
    let reuse: HistoryReuse
    let now: () -> Date

    var body: some View {
        HStack(spacing: 0) {
            HomeSidebar(library: library)
                .frame(width: 220)
                .background(theme.sidebar.color)
                .overlay(alignment: .trailing) { theme.line.color.frame(width: 1) }
            Group {
                switch library.page {
                case .home: HomePageView(library: library, reuse: reuse, now: now())
                case .history: HistoryPageView(library: library, reuse: reuse, now: now())
                case .dictionary: DictionaryPageView(library: library)
                case .settings: SettingsPageView(library: library)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(theme.ink.color)
        .background(theme.background.color)
        .ignoresSafeArea()
    }
}

// MARK: Sidebar

private struct HomeSidebar: View {
    @Environment(\.homeTheme) private var theme
    @Bindable var library: HomeLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.accent.color)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "waveform").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
                Text("VishPrompt").font(.system(size: 16, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)
            .accessibilityElement(children: .combine)

            ForEach(HomePage.allCases) { page in
                let selected = library.page == page
                Button { library.page = page } label: {
                    Text(page.title)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? theme.ink.color : theme.muted.color)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(theme.card.color)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("To talk").font(.system(size: 12)).foregroundStyle(theme.muted.color)
                HStack(spacing: 6) {
                    KeyCap(label: library.triggerName)
                    // Only offers the palm rest when it would actually work.
                    Text(library.palmRestAvailable && library.palmRestEnabled ? "hold, or double-tap the palm rest" : "hold to talk")
                        .font(.system(size: 13))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeCard(radius: 12)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 14)
        .padding(.top, 46)   // clear of the window's traffic lights
        .padding(.bottom, 18)
    }
}

// MARK: Home

private struct HomePageView: View {
    @Environment(\.homeTheme) private var theme
    let library: HomeLibrary
    let reuse: HistoryReuse
    let now: Date

    var body: some View {
        let stats = library.stats(now: now)
        let recent = library.recentToday(now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HomeGreeting.text(hour: Calendar.current.component(.hour, from: now), fullName: NSFullUserName()))
                            .font(.system(size: 26, weight: .semibold))
                        Text("Everything you said today, ready to copy again.")
                            .font(.system(size: 14)).foregroundStyle(theme.muted.color)
                    }
                    Spacer()
                    StatTile(value: stats.dictations, label: "today")
                    StatTile(value: stats.words, label: stats.words == 1 ? "word" : "words")
                    StatTile(value: stats.stayedOnThisMac, label: "stayed on this Mac")
                }
                if let note = library.triggerNote {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "keyboard").foregroundStyle(theme.accent.color).padding(.top, 2)
                        Text(note).font(.system(size: 13)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Dismiss") {
                            library.onDismissTriggerNote()
                            library.triggerNote = nil
                        }
                        .buttonStyle(.link)
                        .foregroundStyle(theme.accent.color)
                    }
                    .padding(14)
                    .homeCard(radius: 12, border: theme.accent)
                    .accessibilityElement(children: .combine)
                }
                if let error = library.loadError {
                    EmptyNote(text: error)
                } else if recent.isEmpty {
                    EmptyNote(text: "Nothing yet today. Hold \(library.triggerName) and say something; it shows up here.")
                } else {
                    SectionLabel(text: "Recent")
                    ForEach(recent) { entry in
                        DictationCard(entry: entry, library: library, reuse: reuse)
                    }
                    if library.lastDeleted != nil {
                        HStack(spacing: 10) {
                            Text("Deleted from this Mac.").foregroundStyle(theme.muted.color)
                            Button("Undo") { library.undoDelete() }.buttonStyle(.link).foregroundStyle(theme.accent.color)
                        }
                        .font(.system(size: 13))
                    }
                }
                AppsSection(stats: library.appStats(now: now), shortCancels: library.shortCancelsThisWeek(now: now))
            }
            .padding(.horizontal, 36).padding(.top, 40).padding(.bottom, 28)
        }
        .scrollContentBackground(.hidden)
    }
}

/// "How each app is going": the last seven days, per app with ten or more dictations.
private struct AppsSection: View {
    @Environment(\.homeTheme) private var theme
    let stats: [AppWeekStats]
    let shortCancels: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "How each app is going")
            if stats.isEmpty {
                EmptyNote(text: "Shows an app once it has ten dictations in a week: how many, and how many you took as they came.")
            } else {
                VStack(spacing: 0) {
                    ForEach(stats) { app in
                        HStack(spacing: 12) {
                            Text(app.name).font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text("\(app.dictations) this week").font(.system(size: 13)).foregroundStyle(theme.muted.color)
                            Text(app.acceptedShare.map { "\($0)% as they came" } ?? "")
                                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                .frame(width: 150, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        if app.id != stats.last?.id {
                            theme.line.color.frame(height: 1).padding(.horizontal, 16)
                        }
                    }
                }
                .homeCard(radius: 14)
                Text(footer)
                    .font(.system(size: 12)).foregroundStyle(theme.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    private var footer: String {
        var text = "Taken as it came: Return first, one level, no undo within 30 seconds."
        if shortCancels > 0 {
            text += " \(shortCancels) \(shortCancels == 1 ? "dictation was" : "dictations were") cancelled before they were worth keeping."
        }
        return text
    }
}

// MARK: Dictionary

private struct DictionaryPageView: View {
    @Environment(\.homeTheme) private var theme
    let library: HomeLibrary

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dictionary").font(.system(size: 26, weight: .semibold))
                Text("Words VishPrompt should always spell your way.")
                    .font(.system(size: 14)).foregroundStyle(theme.muted.color)
            }
            if library.dictionaryWords.isEmpty {
                EmptyNote(text: "No words yet. Dictate into a terminal running Claude Code or Codex, and that project's file names and identifiers appear here.")
            } else {
                ChipFlow(words: library.dictionaryWords)
            }
            Text(library.dictionarySource.map { "From \($0), for this session. Words from the git repo you are working in are added on their own; there is no list of your own words yet." }
                 ?? "Words from the git repo you are working in are added for that session on their own; there is no list of your own words yet.")
                .font(.system(size: 13)).foregroundStyle(theme.muted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 36).padding(.top, 40).padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}

/// Word chips that wrap onto as many lines as they need.
private struct ChipFlow: View {
    @Environment(\.homeTheme) private var theme
    let words: [String]

    var body: some View {
        FlowLayout(spacing: 10) {
                ForEach(Array(words.prefix(300).enumerated()), id: \.offset) { _, word in
                    Text(word)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(theme.card.color))
                        .overlay(Capsule().strokeBorder(theme.line.color))
                        .fixedSize()
            }
        }
    }
}

/// Lays children left to right, wrapping at the proposed width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

// MARK: Settings

/// A row of equal buttons, one selected: Appearance, and later history retention.
struct ChoiceRow<Option: Hashable>: View {
    @Environment(\.homeTheme) private var theme
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    init(options: [Option], selection: Binding<Option>, title: @escaping (Option) -> String) {
        self.options = options
        _selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? theme.accentWash.color : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? theme.accent.color : theme.line.color))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: Pieces

struct KeyCap: View {
    @Environment(\.homeTheme) private var theme
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 6)
            .frame(minWidth: 26, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.background.color))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.line.color))
            .shadow(color: theme.line.color, radius: 0, y: 1)
            .accessibilityLabel("\(label) key")
    }
}

private struct StatTile: View {
    @Environment(\.homeTheme) private var theme
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted()).font(.system(size: 20, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 12)).foregroundStyle(theme.muted.color)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minWidth: 92, alignment: .leading)
        .homeCard(radius: 12)
        .accessibilityElement(children: .combine)
    }
}

struct SectionLabel: View {
    @Environment(\.homeTheme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(theme.muted.color)
            .padding(.top, 6).padding(.horizontal, 2)
    }
}

struct EmptyNote: View {
    @Environment(\.homeTheme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(theme.muted.color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(40)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.line.color, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

extension View {
    /// A card: the theme's card fill, a hairline in the theme's line colour.
    func homeCard(radius: CGFloat, border: RGB? = nil) -> some View {
        modifier(HomeCard(radius: radius, border: border))
    }
}

private struct HomeCard: ViewModifier {
    @Environment(\.homeTheme) private var theme
    let radius: CGFloat
    let border: RGB?

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.card.color))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder((border ?? theme.line).color))
    }
}
