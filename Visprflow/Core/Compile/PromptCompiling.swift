import Foundation

/// Everything the compiler knows about where the text is going.
struct CompileRequest: Sendable, Equatable {
    var transcript: String
    var level: EditLevel
    /// Identifier of the destination profile, such as `claude_code` or `message`.
    var destination: String
    /// The user's free-text instruction for this destination.
    var instructions: String?
    /// Terms that must be spelled the way the project spells them.
    var vocabulary: [String] = []
    /// Words the output may use without the speaker saying them, checked by the guardrails but
    /// never sent to the model: text read from a screenshot, which must stay on this Mac.
    var guardrailTerms: [String] = []

    init(
        transcript: String,
        level: EditLevel,
        destination: String = "document",
        instructions: String? = nil,
        vocabulary: [String] = [],
        guardrailTerms: [String] = []
    ) {
        self.transcript = transcript
        self.level = level
        self.destination = destination
        self.instructions = instructions
        self.vocabulary = vocabulary
        self.guardrailTerms = guardrailTerms
    }
}

/// The compiler's answer.
struct CompiledPrompt: Sendable, Equatable {
    var text: String
    /// The level actually applied, which may be lower than requested if a guardrail fired.
    var level: EditLevel
    /// True when every attempt was rejected and the raw transcript is being used instead.
    var usedRawFallback: Bool = false
    /// Why the first attempt was rejected, if it was.
    var guardrailReason: String?
    /// Exactly what was sent to the model, stored in history so the user can inspect it.
    var requestJSON: String?
    /// Where the request went. Nil when nothing left the Mac.
    var sentTo: ProviderChoice?
}

/// Turns a transcript into the text that will be inserted.
protocol PromptCompiling: Sendable {
    /// - Parameter onPartial: the text produced *so far by the current attempt*, cumulative.
    ///   When a guardrail rejects an attempt and the compiler retries, this restarts from the
    ///   new attempt's first token rather than appending to the discarded one.
    func compile(
        _ request: CompileRequest,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> CompiledPrompt
}

extension PromptCompiling {
    func compile(_ request: CompileRequest) async throws -> CompiledPrompt {
        try await compile(request, onPartial: { _ in })
    }
}

/// Hands the transcript straight through. Used for VERBATIM, and as the whole compiler in
/// phase 1 before any model was involved.
struct PassthroughCompiler: PromptCompiling {
    func compile(
        _ request: CompileRequest,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> CompiledPrompt {
        onPartial(request.transcript)
        return CompiledPrompt(text: request.transcript, level: .verbatim)
    }
}
