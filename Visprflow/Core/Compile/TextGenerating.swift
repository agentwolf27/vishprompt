import Foundation

/// A single call to a language model.
struct GenerationRequest: Sendable, Equatable {
    var system: String
    var user: String
    var model: ModelChoice
    var maxTokens: Int

    /// A compact record of what was sent, stored in history so the user can see exactly what
    /// left the machine. The system prompt is summarised by length rather than repeated.
    func auditJSON() -> String {
        let payload: [String: Any] = [
            "model": model.identifier,
            "max_tokens": maxTokens,
            "system_characters": system.count,
            "user": user,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// Anything that can turn a prompt into text, with streamed deltas for the overlay.
protocol TextGenerating: Sendable {
    /// - Parameter onDelta: called with each chunk of text as it arrives.
    /// - Returns: the complete text.
    func generate(
        _ request: GenerationRequest,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

enum GenerationError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case http(status: Int, message: String)
    case emptyResponse
    case cancelled
    case transport(String)

    /// What happened, in words someone can act on. The raw status and body stay in the log;
    /// the overlay gets the cause and, from the caller, the way out.
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No Anthropic API key is set. Add one in Setup, or send rewrites to your subscription"
        case let .http(status, message):
            Self.describe(status: status, message: message)
        case .emptyResponse:
            "The rewrite came back empty"
        case .cancelled:
            "Cancelled"
        case let .transport(message):
            message
        }
    }

    static func describe(status: Int, message: String) -> String {
        switch status {
        case 401, 403: "Anthropic rejected the API key (\(status)). Check it in Setup"
        case 429: "Anthropic is limiting requests on this key right now (429)"
        case 500, 502, 503, 529: "Claude is overloaded or unavailable right now (Anthropic \(status))"
        case 200: "The rewrite stopped before it finished (\(message))"
        default: "Anthropic returned an error (\(status))"
        }
    }
}

/// A deterministic generator for tests: no network, no key, no cost.
///
/// This exists so the compiler, the guardrails and the golden set are all exercised offline.
/// It also means the app has a working, testable pipeline before any key is configured.
struct MockGenerator: TextGenerating {
    /// Maps a user prompt to a canned reply. The first matching predicate wins.
    var responses: [@Sendable (GenerationRequest) -> String?] = []
    /// Used when nothing matches.
    var fallback: @Sendable (GenerationRequest) -> String = { _ in "" }
    /// Set to throw instead of answering.
    var failure: GenerationError?
    /// Emit the answer in chunks, as the real client does.
    var streamInChunks = true

    func generate(
        _ request: GenerationRequest,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if let failure { throw failure }
        let answer = responses.lazy.compactMap { $0(request) }.first ?? fallback(request)
        if streamInChunks {
            for chunk in answer.split(separator: " ", omittingEmptySubsequences: false) {
                onDelta(String(chunk) + " ")
            }
        } else {
            onDelta(answer)
        }
        return answer
    }
}
