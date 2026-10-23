import Foundation

/// Compares the numbers in a clip with the numbers in its rewrite.
///
/// A rewrite that changes "1240" to "1420" reads perfectly and is wrong, and nobody proofreads
/// a number they did not type. So every number is checked: one the model added is grounds to
/// reject the rewrite; one it left out is only reported, because "make this shorter" may drop a
/// figure on purpose.
struct NumberCheck: Equatable, Sendable {
    /// Numbers in the clip.
    var source: Int
    /// Numbers in the result that are not in the clip or the instruction.
    var added: [String]
    /// Numbers in the clip that are missing from the result.
    var dropped: [String]

    var passed: Bool { added.isEmpty }

    /// One plain line for the preview, or nil when the clip has no numbers.
    var summary: String? {
        guard source > 0 else { return nil }
        if !added.isEmpty {
            return "The rewrite added \(added.count == 1 ? "a number" : "numbers") not in your clip: \(added.joined(separator: ", "))"
        }
        if dropped.isEmpty {
            return source == 1
                ? "Numbers checked: the one in your clip is in the result, none added."
                : "Numbers checked: all \(source) from your clip are in the result, none added."
        }
        return "Numbers checked: none added, but \(dropped.count) from your clip \(dropped.count == 1 ? "is" : "are") not in the result: \(dropped.joined(separator: ", "))."
    }

    static func compare(clip: String, instruction: String = "", output: String) -> NumberCheck {
        let inClip = numbers(in: clip)
        // Anything that appears as digits anywhere in the clip may appear in the result:
        // "2026-10-23" in the clip makes "23 October" a reformat, not an invention.
        let allowed = Set(inClip)
            .union(digitRuns(in: clip))
            .union(numbers(in: instruction))
            .union(digitRuns(in: instruction))
        let inOutput = numbers(in: output)
        let outputSet = Set(inOutput)
        let added = unique(inOutput.filter { !allowed.contains($0) })
        let dropped = unique(inClip.filter { !outputSet.contains($0) })
        return NumberCheck(source: Set(inClip).count, added: added, dropped: dropped)
    }

    /// Numbers in their canonical form: "1,240" and "1240" are the same number, and so are
    /// "3.10" and "3.1". Placeholders for redacted secrets are skipped, as are digits that are
    /// part of a word ("Q3", "v2", "sk-…").
    static func numbers(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "(?<![\\p{L}\\d_.⟦-])\\d{1,3}(?:,\\d{3})+(?:\\.\\d+)?(?![\\p{L}\\d_])|(?<![\\p{L}\\d_.⟦-])\\d+(?:\\.\\d+)?(?![\\p{L}\\d_])")
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return canonical(String(text[swiftRange]))
        }
    }

    /// Every run of digits, however it is embedded.
    static func digitRuns(in text: String) -> Set<String> {
        let pattern = try! NSRegularExpression(pattern: "\\d+(?:\\.\\d+)?")
        let range = NSRange(text.startIndex..., in: text)
        return Set(pattern.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { canonical(String(text[$0])) }
        })
    }

    static func canonical(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: ",", with: "")
        if value.contains(".") {
            while value.hasSuffix("0") { value.removeLast() }
            if value.hasSuffix(".") { value.removeLast() }
        }
        while value.count > 1, value.hasPrefix("0"), !value.hasPrefix("0.") { value.removeFirst() }
        return value
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
