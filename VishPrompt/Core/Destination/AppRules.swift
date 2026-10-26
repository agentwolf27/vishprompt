import Foundation

/// Your own writing rules per app or site ("Slack: no greetings, lowercase is fine"), in the
/// free-text instructions slot the prompt already has. Keyed by `AppIdentity.key`; an app with
/// no rule of its own uses its destination family's. Nothing automatic ever writes here.
struct AppRules: @unchecked Sendable {
    static let key = "appWritingRules"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    /// The rule for an app, trimmed, or nil when there is none worth sending.
    func rule(for key: String?) -> String? {
        guard let key, let text = all()[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Saves a rule. Empty removes it, so the family's rule applies again.
    func set(_ text: String?, for key: String) {
        var rules = all()
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rules[key] = text
        } else {
            rules.removeValue(forKey: key)
        }
        defaults.set(rules, forKey: Self.key)
    }

    /// The destination with this app's rule in place of the family's, when the app has one.
    /// Applied once, where the run picks its destination, so the compile and Smart Paste both
    /// see it; nothing else about the destination changes.
    func apply(to destination: Destination, for identity: AppIdentity) -> Destination {
        guard let rule = rule(for: identity.key) else { return destination }
        var result = destination
        result.instructions = rule
        return result
    }
}
