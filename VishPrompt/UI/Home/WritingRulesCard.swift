import SwiftUI

/// Writing rules per app: the apps and sites dictated into, each with its own free-text rule
/// that is sent with every rewrite for that app. Empty means the family's rule applies.
struct WritingRulesCard: View {
    @Environment(\.homeTheme) private var theme
    @Bindable var library: HomeLibrary

    var body: some View {
        SettingsCard(title: "Writing rules per app") {
            Text("Your own words, sent with each rewrite for that app: “no greetings, lowercase is fine”. An app with no rule uses its family's, set under More settings → Destinations. Nothing here changes on its own.")
                .font(.system(size: 12)).foregroundStyle(theme.muted.color)
                .fixedSize(horizontal: false, vertical: true)
            let apps = library.dictatedApps
            if apps.isEmpty {
                Text("The apps you dictate into appear here once a dictation has been saved with its app.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted.color)
                    .padding(.top, 6)
            } else {
                ForEach(apps) { app in
                    SettingsRow {
                        RowText(title: app.name, note: "\(app.count) \(app.count == 1 ? "dictation" : "dictations") · \(HistoryFormat.destinationName(app.family)) family")
                            .frame(width: 220, alignment: .leading)
                    } trailing: {
                        RuleField(library: library, app: app)
                    }
                }
            }
        }
    }
}

private struct RuleField: View {
    @Environment(\.homeTheme) private var theme
    let library: HomeLibrary
    let app: HomeLibrary.DictatedApp

    private var placeholder: String {
        if let family = library.familyRule(for: app.family), !family.isEmpty {
            return "Uses \(HistoryFormat.destinationName(app.family))'s rule: \(family)"
        }
        return "No rule yet. Say how \(app.name) should read."
    }

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { library.appRule(for: app.key) },
            set: { library.setAppRule($0, for: app.key) }
        ), axis: .vertical)
        .lineLimit(1...4)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.sunk.color))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.line.color))
        .accessibilityLabel("Writing rule for \(app.name)")
    }
}
