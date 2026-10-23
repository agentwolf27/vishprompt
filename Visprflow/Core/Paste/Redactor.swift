import Foundation

/// Text with its known secret shapes swapped for placeholders, and the way back.
///
/// Placeholders carry a nonce chosen per request, so a clip cannot contain one in advance and a
/// model cannot invent one that will be honoured. Restoring is strict: a placeholder that was
/// never issued, or one that appears twice, means the output cannot be trusted, and the caller
/// falls back to the clip as copied. A placeholder the model dropped is allowed, because
/// "make this shorter" may legitimately leave a value out.
struct Redaction: Equatable, Sendable {
    /// The text with every caught secret replaced by a placeholder. This is what may leave.
    var text: String
    /// Placeholder to original value.
    var secrets: [String: String]
    /// Placeholder to the kind of secret, for "[redacted API key]".
    var kinds: [String: String]
    var nonce: String

    var isEmpty: Bool { secrets.isEmpty }

    /// Puts the original values back, locally, for a destination a person reads.
    /// Returns nil when the placeholders in `output` do not match what was issued.
    func restore(_ output: String) -> String? {
        substitute(output) { secrets[$0] }
    }

    /// Replaces each placeholder with a readable label, for destinations that are themselves
    /// a model (Claude Code, Cursor, a chat window): the secret stays out of every model, not
    /// only ours. Returns nil on a placeholder mismatch.
    func display(_ output: String) -> String? {
        substitute(output) { kinds[$0].map { "[redacted \($0)]" } }
    }

    private func substitute(_ output: String, value: (String) -> String?) -> String? {
        let tokens = Self.placeholders(in: output)
        var seen = Set<String>()
        for token in tokens {
            guard secrets[token] != nil, seen.insert(token).inserted else { return nil }
        }
        var result = output
        for token in tokens {
            guard let replacement = value(token) else { return nil }
            result = result.replacingOccurrences(of: token, with: replacement)
        }
        return result
    }

    /// Every ⟦…⟧ in the text, issued or not.
    static func placeholders(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "⟦[^⟧\\n]{0,64}⟧")
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

/// Finds known secret shapes on this Mac before anything is sent to a model.
///
/// "Known shapes" is the honest claim. Regular expressions catch prefixed keys, tokens, key
/// blocks, credentials in URLs and headers, and `password = …` assignments; an entropy rule
/// catches long random strings. They miss a password written in a sentence, short unprefixed
/// keys, and anything that looks like ordinary text. `Fixtures/secrets/known-misses.json` lists
/// the misses on purpose, and a test fails if that list stops being accurate.
enum Redactor {
    struct Rule: Sendable {
        var kind: String
        var pattern: NSRegularExpression
        /// The capture group holding the secret. Zero means the whole match.
        var group: Int = 0
        /// A last look at the value, for rules whose pattern alone is too broad.
        var accepts: @Sendable (String) -> Bool = { _ in true }
    }

    static let rules: [Rule] = {
        func rule(
            _ kind: String,
            _ pattern: String,
            group: Int = 0,
            caseInsensitive: Bool = false,
            accepts: @escaping @Sendable (String) -> Bool = { _ in true }
        ) -> Rule {
            let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
            return Rule(
                kind: kind,
                pattern: try! NSRegularExpression(pattern: pattern, options: options),
                group: group,
                accepts: accepts
            )
        }
        return [
            // Whole key blocks first, so nothing inside them is matched piecemeal.
            rule("private key", "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----"),
            rule("token", "\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}"),
            rule("API key", "\\bsk-ant-[A-Za-z0-9_-]{20,}"),
            rule("API key", "\\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}"),
            rule("API key", "\\b[rs]k_(?:live|test)_[0-9A-Za-z]{16,}"),
            rule("API key", "\\bAIza[0-9A-Za-z_-]{35}"),
            rule("access key", "\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b"),
            rule("token", "\\bgh[pousr]_[A-Za-z0-9]{30,}"),
            rule("token", "\\bgithub_pat_[A-Za-z0-9_]{40,}"),
            rule("token", "\\bxox[abposr]-[A-Za-z0-9-]{10,}"),
            // postgres://user:password@host — only the password goes.
            rule("password", "://[^/\\s:@]+:([^/\\s@]+)@", group: 1),
            // ?token=…, &api_key=…
            rule("token", "[?&](?:access_token|refresh_token|id_token|token|api_key|apikey|key|secret|password|sig|signature|auth)=([^&\\s#\"']+)", group: 1, caseInsensitive: true),
            rule("credential", "\\bAuthorization:\\s*(?:Bearer|Basic|Token)\\s+([A-Za-z0-9._~+/=-]{8,})", group: 1, caseInsensitive: true),
            rule("token", "\\bBearer\\s+([A-Za-z0-9._~+/=-]{16,})", group: 1),
            // password: hunter22, API_KEY="…", "client_secret": "…". A value with no letter in
            // it is a number ("max_tokens": 4000, "total_tokens": 1234567), not a secret, unless
            // it is long enough to be a numeric key.
            rule(
                "secret",
                "\\b[A-Za-z0-9_.-]*(?:api[_-]?key|secret|token|passw(?:or)?d|pwd|private[_-]?key|access[_-]?key)[A-Za-z0-9_.-]*[\"']?\\s*[:=]\\s*[\"']?([^\\s\"',;]{6,})",
                group: 1,
                caseInsensitive: true,
                accepts: { value in value.contains(where: \.isLetter) || value.count >= 12 }
            ),
        ]
    }()

    /// Long random-looking runs that no rule named.
    private static let candidateRun = try! NSRegularExpression(pattern: "[A-Za-z0-9+/_=-]{32,}")
    private static let uuid = try! NSRegularExpression(pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

    /// - Parameters:
    ///   - exempt: strings never to redact, such as the repository's own vocabulary, so an agent
    ///     prompt keeps the identifiers it needs.
    ///   - nonce: fixed only by tests; real calls get a fresh random one.
    static func redact(_ text: String, exempt: Set<String> = [], nonce: String = makeNonce()) -> Redaction {
        var working = text
        var secrets: [String: String] = [:]
        var kinds: [String: String] = [:]
        var counter = 0

        func placeholder(for value: String, kind: String) -> String {
            // The same secret twice gets the same placeholder, so restoring is consistent.
            if let existing = secrets.first(where: { $0.value == value })?.key { return existing }
            counter += 1
            let token = "⟦vf-\(nonce)-\(counter)⟧"
            secrets[token] = value
            kinds[token] = kind
            return token
        }

        for rule in rules {
            let range = NSRange(working.startIndex..., in: working)
            // Replace from the end so earlier ranges stay valid.
            for match in rule.pattern.matches(in: working, range: range).reversed() {
                let target = match.range(at: rule.group)
                guard target.location != NSNotFound, let swiftRange = Range(target, in: working) else { continue }
                let value = String(working[swiftRange])
                if value.hasPrefix("⟦vf-") || exempt.contains(value) || !rule.accepts(value) { continue }
                working.replaceSubrange(swiftRange, with: placeholder(for: value, kind: rule.kind))
            }
        }

        let range = NSRange(working.startIndex..., in: working)
        for match in candidateRun.matches(in: working, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: working) else { continue }
            let value = String(working[swiftRange])
            guard looksRandom(value), !exempt.contains(value) else { continue }
            working.replaceSubrange(swiftRange, with: placeholder(for: value, kind: "secret"))
        }

        return Redaction(text: working, secrets: secrets, kinds: kinds, nonce: nonce)
    }

    /// Conservative on purpose: a false positive mangles an identifier the user needs, so this
    /// demands mixed case, digits and high entropy, and never fires on hex (git SHAs, hashes),
    /// UUIDs or anything path-like.
    static func looksRandom(_ value: String) -> Bool {
        if uuid.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil { return false }
        if value.allSatisfy(\.isHexDigit) { return false }
        if value.contains("//") || value.filter({ $0 == "/" }).count > 2 { return false }
        let digits = value.filter(\.isNumber).count
        let upper = value.filter(\.isUppercase).count
        let lower = value.filter(\.isLowercase).count
        guard digits >= 2, upper >= 2, lower >= 2 else { return false }
        return shannonEntropy(value) >= 4.2
    }

    static func shannonEntropy(_ value: String) -> Double {
        guard !value.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for character in value { counts[character, default: 0] += 1 }
        let length = Double(value.count)
        return counts.values.reduce(0) { total, count in
            let p = Double(count) / length
            return total - p * log2(p)
        }
    }

    static func makeNonce() -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }
}
