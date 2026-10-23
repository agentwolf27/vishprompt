import Foundation

/// Starts the `claude` command line tool at key-down, so its start-up runs while the user is
/// still speaking.
///
/// Measured on this Mac: a cold `claude -p` takes about 0.95 s before it does anything useful.
/// Started with `--input-format stream-json`, it does that work and then waits, printing
/// nothing, until a message arrives on stdin; from there it finished in 0.08–0.09 s. The system
/// prompt and model are fixed when it starts, so one process is kept for one guess, and a
/// request that does not match it is served the old way, cold.
final class CLIPrespawner: @unchecked Sendable {
    static let shared = CLIPrespawner()

    /// What a pre-started process can serve.
    struct Key: Equatable, Sendable {
        var executable: String
        var system: String
        var model: String
    }

    /// A started process, its pipes, and what it was started for.
    final class Spawned: @unchecked Sendable {
        let process: Process
        let input: Pipe
        let output: Pipe
        let errors: Pipe
        let key: Key

        init(process: Process, input: Pipe, output: Pipe, errors: Pipe, key: Key) {
            self.process = process
            self.input = input
            self.output = output
            self.errors = errors
            self.key = key
        }
    }

    /// An unused process is ended after this, so an abandoned dictation leaves nothing behind.
    static let idleLifetime: Duration = .seconds(90)

    private let lock = NSLock()
    private var ready: Spawned?
    private var reaper: Task<Void, Never>?
    private let launch: (Key) -> Spawned?

    init(launch: @escaping (Key) -> Spawned? = CLIPrespawner.launchCLI) {
        self.launch = launch
    }

    /// Starts a process for `key` unless one is already waiting for it.
    func prepare(_ key: Key) {
        lock.lock()
        if let ready, ready.key == key, ready.process.isRunning {
            lock.unlock()
            return
        }
        let stale = ready
        ready = nil
        lock.unlock()
        stale?.process.terminate()

        guard let spawned = launch(key) else { return }
        lock.lock()
        ready = spawned
        reaper?.cancel()
        reaper = Task { [weak self] in
            try? await Task.sleep(for: Self.idleLifetime)
            guard !Task.isCancelled else { return }
            self?.discard()
        }
        lock.unlock()
    }

    /// The waiting process if it was started for exactly `key`. Anything else ends it: a
    /// process started with the wrong system prompt or model must never answer a request.
    func take(_ key: Key) -> Spawned? {
        lock.lock()
        let current = ready
        ready = nil
        reaper?.cancel()
        reaper = nil
        lock.unlock()
        guard let current else { return nil }
        guard current.key == key, current.process.isRunning else {
            current.process.terminate()
            return nil
        }
        return current
    }

    /// Ends any waiting process. Called when a dictation is cancelled or did not need it.
    func discard() {
        lock.lock()
        let current = ready
        ready = nil
        reaper?.cancel()
        reaper = nil
        lock.unlock()
        current?.process.terminate()
    }

    var hasWaitingProcess: Bool {
        lock.lock(); defer { lock.unlock() }
        return ready?.process.isRunning == true
    }

    /// The model a key-down should guess: terminals and code editors are where full compiles
    /// happen, which use Sonnet; anywhere else a compile is usually organising, on Haiku.
    static func likelyModel(forFrontmost bundle: String?) -> ModelChoice {
        guard let bundle else { return .haiku }
        let coding = DestinationResolver.terminalBundles.union(DestinationResolver.editorBundles)
        return coding.contains(bundle) ? .sonnet : .haiku
    }

    /// What a key-down should pre-start, if anything. Only on the subscription path, and only in
    /// a terminal or code editor, where a compiled prompt is likely: everywhere else a dictation
    /// is usually cleaned up on this Mac, and starting a process it will not use costs a second
    /// of CPU for nothing.
    static func keyDownGuess(policy: ProviderPolicy, frontmost bundle: String?, executable: String?) -> Key? {
        guard policy.compilePath == .subscription, let executable, let bundle else { return nil }
        let coding = DestinationResolver.terminalBundles.union(DestinationResolver.editorBundles)
        guard coding.contains(bundle) else { return nil }
        return Key(executable: executable, system: SystemPrompt.core, model: likelyModel(forFrontmost: bundle).identifier)
    }

    /// What fn+V or fn+R should pre-start instead: the paste prompt, on Haiku, from the compile path.
    static func chordGuess(policy: ProviderPolicy, executable: String?) -> Key? {
        guard policy.compilePath == .subscription, let executable else { return nil }
        return Key(executable: executable, system: SystemPrompt.paste, model: ModelChoice.haiku.identifier)
    }

    static func launchCLI(_ key: Key) -> Spawned? {
        guard FileManager.default.isExecutableFile(atPath: key.executable) else { return nil }
        let process = Process()
        process.executableURL = URL(filePath: key.executable)
        process.arguments = ClaudeCLIGenerator.streamingArguments(system: key.system, model: key.model)
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            Log.compile.error("Could not pre-start the claude command: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return Spawned(process: process, input: input, output: output, errors: errors, key: key)
    }
}
