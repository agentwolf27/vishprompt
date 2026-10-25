import SwiftUI

/// Settings as four cards: how you start talking, where the rewrite runs, what can leave this
/// Mac, and appearance. Each is wired to the setting the app already uses; "More settings…"
/// opens the full window for destinations, the API key and consent.
struct SettingsPageView: View {
    @Environment(\.homeTheme) private var theme
    @Bindable var library: HomeLibrary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(.system(size: 26, weight: .semibold))
                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow(alignment: .top) {
                        startCard
                        rewriteCard
                    }
                    GridRow {
                        PalmRestCard(library: library).gridCellColumns(2)
                    }
                    GridRow(alignment: .top) {
                        leavesCard
                        appearanceCard
                    }
                }
                Button("More settings…") { library.onShowMoreSettings() }
                    .buttonStyle(.link)
                    .foregroundStyle(theme.accent.color)
            }
            .padding(.horizontal, 36).padding(.top, 40).padding(.bottom, 28)
        }
        .scrollContentBackground(.hidden)
    }

    private var startCard: some View {
        SettingsCard(title: "How you start talking") {
            SettingsRow {
                RowText(title: "Hold to talk", note: "Release to finish. Double-tap \(library.triggerName) for hands-free.")
            } trailing: {
                KeyCap(label: library.triggerName).scaleEffect(1.1)
            }
            if let hint = library.fnHint {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hint).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Button("Open Keyboard Settings…") { library.onOpenKeyboardSettings() }
                        .buttonStyle(.link).font(.system(size: 12)).foregroundStyle(theme.accent.color)
                }
                .padding(.top, 8)
            }
            SettingsRow {
                RowText(title: "Tap the palm rest", note: "Choose what each tap does in the Palm rest card below.")
            } trailing: {
                Text(library.palmRestEnabled ? "On" : "Off").font(.system(size: 13)).foregroundStyle(theme.muted.color)
            }
        }
    }

    private var rewriteCard: some View {
        SettingsCard(title: "Where the rewrite runs") {
            VStack(spacing: 8) {
                ForEach(RewriteChoice.options, id: \.self) { choice in
                    let on = RewriteChoice.selected(in: library.providerPolicy) == choice
                    Button { library.chooseRewrite(choice) } label: {
                        HStack(spacing: 12) {
                            RowText(title: RewriteChoice.title(choice), note: RewriteChoice.note(choice, hasKey: library.hasAPIKey), weight: .medium)
                            Spacer(minLength: 8)
                            Circle()
                                .strokeBorder(on ? theme.accent.color : theme.line.color, lineWidth: on ? 6 : 2)
                                .frame(width: 18, height: 18)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 12).fill(on ? theme.accentWash.color : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? theme.accent.color : theme.line.color))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var leavesCard: some View {
        SettingsCard(title: "What can leave this Mac") {
            SettingsRow { Text("Your audio").font(.system(size: 14)) } trailing: { NeverPill() }
            SettingsRow { Text("Screenshot images").font(.system(size: 14)) } trailing: { NeverPill() }
            SettingsRow {
                Text("Your words and instruction").font(.system(size: 14))
            } trailing: {
                Text(RewriteChoice.wordsLeave(library.providerPolicy))
                    .font(.system(size: 13)).foregroundStyle(theme.muted.color)
            }
        }
    }

    private var appearanceCard: some View {
        SettingsCard(title: "Appearance") {
            ChoiceRow(options: AppearanceChoice.allCases, selection: $library.appearance, title: \.title)
            VStack(alignment: .leading, spacing: 8) {
                RowText(title: "Keep history for", note: library.retention.note)
                ChoiceRow(options: RetentionPeriod.allCases, selection: Binding(
                    get: { library.retention },
                    set: { library.requestRetention($0) }
                ), title: \.title)
                if let size = library.databaseSize {
                    Text(size).font(.system(size: 12)).foregroundStyle(theme.muted.color)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { theme.line.color.frame(height: 1) }
        }
        .alert(
            "Remove older history?",
            isPresented: Binding(get: { library.pendingRetention != nil }, set: { if !$0 { library.cancelRetention() } }),
            presenting: library.pendingRetention
        ) { pending in
            Button("Remove \(pending.count.formatted())", role: .destructive) { library.confirmRetention() }
            Button("Cancel", role: .cancel) { library.cancelRetention() }
        } message: { pending in
            Text(HistoryRetention.confirmation(count: pending.count, period: pending.period))
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        // Cards in a row share its height, as in the mockup's grid.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .homeCard(radius: 14)
    }
}

struct SettingsRow<Leading: View, Trailing: View>: View {
    @Environment(\.homeTheme) private var theme
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading()
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 44)
        .padding(.top, 10)
        .overlay(alignment: .top) { theme.line.color.frame(height: 1) }
    }
}

struct RowText: View {
    @Environment(\.homeTheme) private var theme
    let title: String
    let note: String
    var weight: Font.Weight = .regular

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: weight)).foregroundStyle(theme.ink.color)
            Text(note).font(.system(size: 12)).foregroundStyle(theme.muted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
    }
}

private struct NeverPill: View {
    @Environment(\.homeTheme) private var theme

    var body: some View {
        Pill(text: "Never", fill: theme.stayedFill, ink: theme.stayedInk)
    }
}
