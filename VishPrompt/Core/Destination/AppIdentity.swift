import Foundation

/// Which app, or which site in a browser, a dictation went to.
///
/// Finer than a destination: Slack and Messages are both `message`, claude.ai and ChatGPT are
/// both `chat`. The destination stays the formatting family the prompt is shaped for; this is
/// what per-app settings and stats group by (PLAN.md, "Step 0").
struct AppIdentity: Equatable, Hashable, Sendable {
    /// The focused app's bundle identifier.
    var bundleID: String?
    /// The front tab's host, only when the app is a browser.
    var host: String?

    /// What per-app settings and stats group by: the site in a browser, the app elsewhere.
    var key: String? { host ?? bundleID }

    static let unknown = AppIdentity()

    /// The identity of a focused window. The host is kept only for browsers, where it is what
    /// tells claude.ai from ChatGPT; a native app's URL would mean nothing.
    static func make(_ context: FocusContext) -> AppIdentity {
        guard let bundle = context.bundleIdentifier else { return .unknown }
        let host = DestinationResolver.browserBundles.contains(bundle) ? DestinationResolver.host(of: context.browserURL) : nil
        return AppIdentity(bundleID: bundle, host: host)
    }

    /// A readable name for a key: a known app or site by its own name, an unknown site by its
    /// host, and an unknown app by `fallback` (the name macOS gives it), never a bundle id.
    static func displayName(key: String?, fallback: String?) -> String? {
        guard let key else { return fallback }
        if let known = knownNames[key] { return known }
        if key.contains(".") && !key.hasPrefix("com.") && !key.hasPrefix("org.") && !key.hasPrefix("net.") && !key.hasPrefix("dev.") && !key.hasPrefix("io.") {
            // A host such as "notion.so": readable as it is.
            return key.hasPrefix("www.") ? String(key.dropFirst(4)) : key
        }
        return fallback
    }

    /// Names for the apps and sites the resolver knows, so a row reads "Slack" or "claude.ai"
    /// rather than "Google Chrome".
    static let knownNames: [String: String] = [
        // Messaging
        "com.tinyspeck.slackmacgap": "Slack", "app.slack.com": "Slack", "slack.com": "Slack",
        "com.apple.MobileSMS": "Messages",
        "net.whatsapp.WhatsApp": "WhatsApp", "web.whatsapp.com": "WhatsApp",
        "com.hnc.Discord": "Discord", "discord.com": "Discord",
        "ru.keepcoder.Telegram": "Telegram",
        "com.microsoft.teams2": "Teams", "teams.microsoft.com": "Teams",
        "com.linear": "Linear", "linear.app": "Linear",
        "github.com": "GitHub",
        // Chat assistants
        "claude.ai": "claude.ai",
        "chatgpt.com": "ChatGPT", "chat.openai.com": "ChatGPT",
        "gemini.google.com": "Gemini",
        "perplexity.ai": "Perplexity", "www.perplexity.ai": "Perplexity",
        "poe.com": "Poe", "grok.com": "Grok", "x.ai": "Grok",
        // Email
        "com.apple.mail": "Mail", "mail.google.com": "Gmail",
        "com.readdle.smartemail-Mac": "Spark", "com.superhuman.electron": "Superhuman",
        "com.microsoft.Outlook": "Outlook", "outlook.office.com": "Outlook", "outlook.live.com": "Outlook",
        "com.missiveapp.missive": "Missive", "mail.proton.me": "Proton Mail",
        // Terminals and editors
        "com.apple.Terminal": "Terminal", "com.googlecode.iterm2": "iTerm",
        "dev.warp.Warp-Stable": "Warp", "com.mitchellh.ghostty": "Ghostty", "net.kovidgoyal.kitty": "kitty",
        "org.alacritty": "Alacritty", "io.alacritty": "Alacritty", "co.zeit.hyper": "Hyper",
        "com.github.wez.wezterm": "WezTerm", "com.tabby.app": "Tabby",
        "com.todesktop.230313mzl4w4u92": "Cursor", "com.microsoft.VSCode": "VS Code",
        "com.microsoft.VSCodeInsiders": "VS Code Insiders", "com.visualstudio.code.oss": "VS Code",
        "dev.zed.Zed": "Zed", "com.exafunction.windsurf": "Windsurf",
        // Apple
        "com.apple.Notes": "Notes", "com.apple.TextEdit": "TextEdit", "com.apple.Safari": "Safari",
        "com.google.Chrome": "Chrome", "com.apple.iWork.Pages": "Pages",
    ]
}
