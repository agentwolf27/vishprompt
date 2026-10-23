import Foundation

/// What happens between the key coming up and a transcript, in one place.
///
/// Shared by `DictationController` and the latency harness, so the harness times the code that
/// ships rather than a copy of it that could drift.
@MainActor
enum KeyUpPath {
    /// Stops the streaming preview, then transcribes the whole recording with the batch model.
    static func transcribe(
        samples: [Float],
        streaming: StreamingTranscriber,
        transcriber: any Transcriber,
        mark: (Stage) -> Void
    ) async throws -> Transcript {
        await streaming.stop()
        mark(.streamStopped)
        return try await transcriber.transcribe(samples: samples, hints: .none)
    }
}
