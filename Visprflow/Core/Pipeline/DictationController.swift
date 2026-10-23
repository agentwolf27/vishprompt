import AppKit
import Observation
import SwiftUI

/// Drives one dictation from key-down to inserted text, and owns the overlay's state.
///
/// The order here is what the latency budget depends on: the focused window is sampled on
/// key-down while the user's app still owns focus, capture starts immediately, the transcript
/// is produced the moment the key comes up, and the compiled text streams into the overlay
/// while its tail is still being generated.
@MainActor
@Observable
final class DictationController {
    private(set) var hud: HUDState = .hidden
    /// Mode, destination and take length, for the capsule's copy.
    private(set) var hudContext = HUDContext()
    private(set) var lastError: String?
    /// Progress while the speech model downloads, for the setup window.
    private(set) var modelProgress: Double?
    /// Why the speech model failed to download or load, for the setup window's Retry row.
    private(set) var modelFailure: String?
    /// The project words the last dictation used, for the Vocabulary pane.
    private(set) var lastVocabulary: VocabularySnapshot?

    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private let transcriber: any Transcriber
    @ObservationIgnored private let compiler: any PromptCompiling
    @ObservationIgnored private let inserter: Inserter
    @ObservationIgnored private let monitor: HotkeyMonitor
    @ObservationIgnored private let settings: DestinationSettings
    @ObservationIgnored private var panel: HUDPanel?
    /// Weak handle to self, shared by the hotkey callback and the overlay's root view.
    @ObservationIgnored private let selfBox: ControllerBox

    @ObservationIgnored private var trace = Trace()
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var activeWork: Task<Void, Never>?
    @ObservationIgnored private var previewTimeout: Task<Void, Never>?
    @ObservationIgnored private var contextTask: Task<FocusContext, Never>?
    @ObservationIgnored private var capturedContext = FocusContext.unknown
    @ObservationIgnored private let vocabulary = VocabularyCache()
    @ObservationIgnored private let streaming = StreamingTranscriber()
    /// Live transcript from the streaming model, shown in the overlay while the user speaks.
    @ObservationIgnored private var livePartial = ""
    @ObservationIgnored private var triggerHealth = TriggerHealth()
    @ObservationIgnored private var currentTrigger: TriggerKey
    /// Set when the trigger looks like it is firing while the user types, for the setup window.
    private(set) var triggerWarning: String?
    /// The dictation waiting for the user to press Return.
    @ObservationIgnored private var pending: Pending?
    /// Set when V turned this capture into a Smart Paste: reads the clipboard as it was then.
    @ObservationIgnored private var pasteRead: Task<ClipContent, Never>?
    /// Set when R turned this capture into an edit of the selection: reads it as it was then.
    @ObservationIgnored private var editRead: Task<SelectionContent, Never>?
    /// Builds the paster per request, so a provider changed in Settings applies immediately.
    @ObservationIgnored private let makePaster: @Sendable () -> SmartPaster

    private struct Pending {
        var transcript: Transcript
        var compiled: CompiledPrompt
        var destination: Destination
        /// The app this text was compiled for, so it is never pasted somewhere else.
        var bundleIdentifier: String?
        /// Present when this preview is a Smart Paste rather than a dictation.
        var paste: PastePreview?
        /// Present when this preview is a screenshot turned into a prompt.
        var fix: FixPreview?
        /// The level the user asked for, which a guardrail may have lowered in `compiled`.
        var requestedLevel: EditLevel = .verbatim
        /// Every level compiled so far, so moving back is instant.
        var levels = PreviewLevels()
    }

    /// The preview on screen, so ↑ and ↓ can redraw it scrolled.
    @ObservationIgnored private var lastPreview: PreviewHUD?
    /// The app in front at key-down, named while listening so the user sees where it will go.
    @ObservationIgnored private var listeningApp: String?

    /// A screenshot prompt waiting in the preview. Tab drops or restores the screenshot text.
    private struct FixPreview {
        var result: ScreenshotPromptResult
        var showingWithout: Bool
        var heard: String

        var text: String { showingWithout ? result.withoutScreenshot : result.text }
    }

    /// Notices when a screenshot was just copied, so "fix this" can pick it up.
    @ObservationIgnored private let clipboardWatcher = ClipboardWatcher()
    /// A screenshot copied longer ago than this is not picked up by an ordinary dictation:
    /// "fix this" should never fix last hour's error.
    private static let freshScreenshot: TimeInterval = 120

    /// A Smart Paste waiting in the preview. Tab flips between the two forms.
    private struct PastePreview {
        var result: SmartPasteResult
        var showingAsCopied: Bool
        /// An edit of the selection rather than a paste of the clipboard.
        var purpose: SmartPasteRequest.Purpose = .paste
        var isEdit: Bool { purpose == .edit }

        /// What history should keep for whichever form is on screen. Never a restored secret.
        var historyResult: SmartPasteResult { result.showing(asCopied: showingAsCopied) }
    }

    /// How long hands-free recording tolerates silence before stopping on its own.
    private let silenceStopAfter: TimeInterval = 1.2

    /// A hold longer than this finishes the dictation by itself.
    ///
    /// A key-up can genuinely go missing: Secure Event Input suppresses key events entirely, so
    /// releasing a non-modifier trigger while a password field has focus is never seen. Without
    /// a ceiling the gesture stays held forever, audio accumulates at roughly 64 MB an hour, and
    /// Escape cannot rescue it because Escape is suppressed too. Five minutes is well past any
    /// real dictation.
    private let maximumHold: TimeInterval = 300

    init(
        transcriber: any Transcriber = ParakeetTranscriber(),
        compiler: any PromptCompiling = Compiler(policySource: ProviderSettings.live),
        inserter: Inserter = Inserter(),
        settings: DestinationSettings = DestinationSettings(),
        trigger: TriggerKey = .fn,
        makePaster: (@Sendable () -> SmartPaster)? = nil
    ) {
        self.transcriber = transcriber
        self.compiler = compiler
        self.inserter = inserter
        self.settings = settings
        self.currentTrigger = trigger
        // Optional rather than a closure default: Swift 6.1 crashes in SILGen on a closure
        // default argument reached through AppDelegate's lazy property.
        self.makePaster = makePaster ?? { SmartPaster(policy: ProviderSettings.live()) }

        // The monitor needs a callback at construction, but that callback needs the controller.
        // A box breaks the cycle without leaving either side optional for the rest of its life.
        let box = ControllerBox()
        self.monitor = HotkeyMonitor(trigger: trigger) { action in
            // The tap's run loop source is on the main run loop, so this already runs on the
            // main thread. Asserting that preserves event order, which a Task hop would not.
            MainActor.assumeIsolated {
                box.controller?.handle(action)
            }
        }
        self.selfBox = box
        box.controller = self
    }

    // MARK: Lifecycle

    func start() throws {
        Log.app.info("DictationController.start: preparing audio")
        capture.prepare()
        capture.observeDeviceChanges()
        clipboardWatcher.start()
        Log.app.info("DictationController.start: audio prepared, starting monitor")
        try monitor.start()
    }

    func stop() {
        monitor.stop()
        clipboardWatcher.stop()
        capture.shutdown()
        meterTimer?.invalidate()
        panel?.dismiss()
    }

    /// Captures the next key press and reports it, for the setup window's key recorder.
    func recordNextKey(_ handler: @escaping @Sendable (TriggerKey) -> Void) {
        monitor.recordNextKey(handler)
    }

    func cancelKeyRecording() {
        monitor.cancelRecording()
    }

    func setTrigger(_ key: TriggerKey) {
        currentTrigger = key
        triggerHealth.reset()
        triggerWarning = nil
        monitor.setTrigger(key)
    }

    /// Watches for the trigger firing because the user is typing rather than dictating.
    private func noteCaptureLength(_ seconds: TimeInterval) {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        guard triggerHealth.record(duration: seconds, at: now) else { return }
        let message = triggerHealth.message(for: currentTrigger)
        triggerWarning = message
        Log.hotkey.error("\(message, privacy: .public)")
        show(.failed(message: message))
        hide(after: 4)
    }

    /// Downloads and loads the speech model, reporting progress for the setup window.
    func warmUp() async {
        modelFailure = nil
        do {
            try await transcriber.prepare { [weak self] fraction in
                Task { @MainActor in self?.modelProgress = fraction }
            }
            modelProgress = nil
            Log.stt.info("Speech model ready")
        } catch {
            modelProgress = nil
            lastError = error.localizedDescription
            modelFailure = error.localizedDescription
            Log.stt.error("Speech model failed to prepare: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Gesture handling

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .none:
            break

        case .startCapture:
            beginCapture()

        case .lockedOn:
            show(.listening(
                level: capture.currentLevel,
                seconds: elapsed,
                locked: true,
                partial: livePartial,
                mode: pasteRead != nil ? .paste : editRead != nil ? .edit : .dictate,
                app: listeningApp
            ))

        case .smartPaste:
            // Read now, while the user's copy is certainly still there: by key-up a paste or
            // another copy could have replaced it. But not inside this callback: an app that
            // promised its data lazily is asked for it on read, which can take long enough
            // for macOS to disable the tap. The task runs as soon as the callback returns.
            pasteRead = Task { @MainActor in ClipboardReader.read() }
            hudContext.mode = .paste
            Log.app.info("Smart Paste requested")
            prespawnForChord()

        case .editSelection:
            // Read the selection now, while it is certainly still selected. Off the callback,
            // like the clipboard: an Accessibility read or a ⌘C can take a moment.
            editRead = Task { @MainActor in await SelectionReader().read() }
            hudContext.mode = .edit
            Log.app.info("Edit selection requested")
            prespawnForChord()

        case let .finishCapture(modifiers, _):
            trace.mark(.keyUp)
            // The take's length stays on screen, frozen, while it transcribes and rewrites.
            hudContext.takeSeconds = elapsed
            stopMeter()
            // Show "Transcribing" straight away: the post-roll below is a real wait, and an
            // overlay still saying "Listening" after the key is up reads as a hang.
            show(.transcribing)
            // The last fraction of a second has been spoken but not yet delivered by the tap,
            // so stopping on the key-up alone truncates the final word.
            Task { [weak self] in
                guard let self else { return }
                let samples = await capture.stopAfterPostRoll()
                trace.mark(.postRollDone)
                finish(samples: samples, modifiers: modifiers)
            }

        case let .discardCapture(reason):
            CLIPrespawner.shared.discard()
            // A long recording cancelled by Escape is kept: transcribed, saved, copied.
            let heldFor = elapsed
            if reason == .escape, HUDCopy.keepsCancelled(seconds: heldFor) {
                let samples = capture.stop()
                stopMeter()
                livePartial = ""
                Task { [streaming] in await streaming.cancel() }
                clearPending()
                pasteRead = nil
                editRead = nil
                keepCancelled(samples)
                Log.app.info("Long dictation cancelled after \(Int(heldFor), privacy: .public)s; keeping the transcript")
                return
            }
            capture.discard()
            stopMeter()
            livePartial = ""
            Task { [streaming] in await streaming.cancel() }
            clearPending()
            switch reason {
            case .tooShort:
                noteCaptureLength(0)
                hide(after: 0)
            case .escape, .resynchronise:
                pasteRead = nil
                editRead = nil
                show(.cancelled)
                hide(after: 0.8)
            case .tooLong:
                show(.failed(message: "Stopped after \(Int(maximumHold / 60)) minutes"))
                hide(after: 2.5)
            }
            Log.app.info("Dictation discarded: \(reason.rawValue, privacy: .public)")

        case let .preview(key):
            handlePreview(key)
        }
    }

    private func beginCapture() {
        dismissTask?.cancel()
        // Starting a new dictation abandons the previous one. Without this the old one runs
        // to completion and inserts its text while this one is still recording.
        activeWork?.cancel()
        activeWork = nil
        clearPending()
        trace = Trace()
        trace.mark(.keyDown)
        startedAt = Date()
        lastError = nil
        pasteRead = nil
        editRead = nil
        // Only the cheap half here: this runs inside the event-tap callback, and a slow
        // callback makes macOS disable the tap, which loses the key-up and the dictation.
        let frontmost = FocusContextProvider.frontmost()
        capturedContext = frontmost
        listeningApp = NSWorkspace.shared.frontmostApplication?.localizedName
        hudContext = HUDContext(mode: .dictate, app: listeningApp, takeSeconds: nil, triggerName: currentTrigger.displayName)
        // Open the API connection while the user talks, if a rewrite may go there. Detached:
        // this runs inside the event-tap callback, and the first key read goes to the Keychain.
        let frontmostBundle = frontmost.bundleIdentifier
        Task.detached(priority: .utility) {
            let policy = ProviderSettings.live()
            ClaudeGenerator.prewarm(policy: policy)
            // Start the claude command now, if a compiled prompt through the subscription is
            // likely, so its second of start-up happens while the user talks.
            if let key = CLIPrespawner.keyDownGuess(policy: policy, frontmost: frontmostBundle, executable: ClaudeCLIGenerator.resolvedExecutable) {
                CLIPrespawner.shared.prepare(key)
            }
        }
        // The expensive half (ps, lsof, git, AppleScript) runs while the user is still
        // speaking and is joined only when the transcript is ready.
        contextTask?.cancel()
        contextTask = Task.detached(priority: .userInitiated) {
            FocusContextProvider.enrich(frontmost)
        }

        do {
            try capture.start()
            trace.mark(.captureStarted)
            livePartial = ""
            show(.listening(level: 0, seconds: 0, locked: false, app: listeningApp))
            startMeter()
            // Transcribe while the user is still talking, so the words are already decoded when
            // the key comes up rather than the whole utterance waiting until then.
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await streaming.begin(draining: capture) { partial in
                        Task { @MainActor [weak self] in self?.livePartial = partial }
                    }
                } catch {
                    // The batch transcriber still runs at key-up, so this only costs the live
                    // preview.
                    Log.stt.error("Streaming session failed to start: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            lastError = error.localizedDescription
            show(.failed(message: error.localizedDescription))
            hide(after: 2.5)
            Log.audio.error("Capture failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func finish(samples: [Float], modifiers: GestureModifiers) {
        guard !samples.isEmpty else {
            hide(after: 0)
            return
        }
        show(.transcribing)

        activeWork?.cancel()
        activeWork = Task { [weak self] in
            guard let self else { return }
            await self.run(samples: samples, modifiers: modifiers)
        }
    }

    private func run(samples: [Float], modifiers: GestureModifiers) async {
        // Snapshot both before the first suspension. `contextTask` and `capturedContext` are
        // replaced by the next key-down, so reading them after transcription can hand this
        // dictation the workspace of the one that superseded it.
        let contextForThisRun = contextTask
        let fallbackContext = capturedContext
        let pasteForThisRun = pasteRead
        pasteRead = nil
        let editForThisRun = editRead
        editRead = nil
        // Whatever this dictation did not use is ended, so no claude process outlives it.
        defer { CLIPrespawner.shared.discard() }
        // Whatever was transcribed, kept so a failure after this point can still hand it back.
        var spokenForThisRun = ""
        do {
            // The streaming model runs alongside the capture purely to show words as they are
            // spoken. The final transcript comes from the batch model, deliberately.
            //
            // Measured here rather than assumed: the batch model needs about 80 ms for ten
            // seconds of audio, so using the streamed text would save a saving nobody can
            // perceive — and it is measurably less accurate, turning "parser" into "passer" in
            // the integration tests. FluidAudio's own documentation says the offline model has
            // better long-form recall. Accuracy wins a trade that costs 80 ms.
            let transcript: Transcript
            do {
                transcript = try await KeyUpPath.transcribe(samples: samples, streaming: streaming, transcriber: transcriber) { stage in
                    trace.mark(stage)
                }
            } catch TranscriberError.audioTooShort where pasteForThisRun != nil || editForThisRun != nil {
                // A quick fn+V tap is a complete request with nothing said.
                transcript = Transcript(text: "", confidence: 1, audioDuration: 0, processingTime: 0)
            }
            trace.mark(.transcriptReady)
            spokenForThisRun = transcript.text
            let context = await contextForThisRun?.value ?? fallbackContext
            let destination = settings.apply(to: DestinationResolver.resolve(context))
            // From here the capsule names the destination ("into Claude Code"), not the app.
            hudContext.app = destination.displayName

            if let editForThisRun {
                let selection = await editForThisRun.value
                guard case let .text(selected) = selection else {
                    show(.failed(message: selection.message ?? "Nothing is selected."))
                    hide(after: HUDCopy.rescueDuration)
                    return
                }
                try await runSmartPaste(
                    clip: .text(selected),
                    transcript: transcript,
                    destination: destination,
                    context: context,
                    purpose: .edit
                )
                return
            }

            if let pasteForThisRun {
                try await runSmartPaste(
                    clip: await pasteForThisRun.value,
                    transcript: transcript,
                    destination: destination,
                    context: context
                )
                return
            }

            guard !transcript.isEmpty else {
                show(.failed(message: "Nothing was said"))
                hide(after: 1.5)
                return
            }

            // Said to a coding agent moments after copying a screenshot: the screenshot is
            // what "this" means. Holding Shift for verbatim opts out.
            if !modifiers.contains(.shift),
               SmartPaster.agentDestinations.contains(destination.id),
               let age = clipboardWatcher.imageAge(), age <= Self.freshScreenshot,
               case let .image(data) = ClipboardReader.read() {
                try await runFix(image: data, transcript: transcript, destination: destination, context: context, modifiers: modifiers)
                return
            }

            var (compiled, attempted) = try await compile(
                transcript: transcript.text,
                destination: destination,
                context: context,
                modifiers: modifiers
            )
            trace.mark(.compileDone)
            compiled.sentTo = Self.sentTo(attempted: attempted, transcript: transcript.text)

            if destination.requiresPreview {
                var levels = PreviewLevels()
                levels.store(compiled, requested: attempted)
                pending = Pending(
                    transcript: transcript,
                    compiled: compiled,
                    destination: destination,
                    bundleIdentifier: context.bundleIdentifier,
                    requestedLevel: attempted,
                    levels: levels
                )
                monitor.setPreviewMode(true)
                startPreviewTimeout()
                trace.mark(.previewShown)
                showPreview(dictationPreview(compiled, destination: destination, attempted: attempted, transcript: transcript.text))
                Log.timing.info("Preview ready: \(self.trace.summary(), privacy: .public)")
            } else {
                try await insert(
                    compiled,
                    transcript: transcript,
                    destination: destination,
                    intendedFor: context.bundleIdentifier
                )
            }

        } catch where Self.isCancellation(error) {
            // Superseded by a newer dictation, which now owns the overlay. Touching it here
            // would hide the overlay of the recording that is still in progress.
        } catch {
            // The words were heard; a provider failing must not lose them.
            report(error, rescuing: pasteForThisRun == nil ? spokenForThisRun : nil)
        }
    }

    /// Transcribes a long recording the user cancelled, saves it as cancelled and copies it.
    private func keepCancelled(_ samples: [Float]) {
        show(.transcribing)
        activeWork?.cancel()
        activeWork = Task { [weak self] in
            guard let self else { return }
            do {
                let transcript = try await self.transcriber.transcribe(samples: samples, hints: .none)
                guard !transcript.isEmpty else {
                    self.show(.cancelled)
                    self.hide(after: 0.8)
                    return
                }
                TextRescue.copy(transcript.text)
                self.record(
                    transcript: transcript,
                    compiled: CompiledPrompt(text: transcript.text, level: .verbatim),
                    destination: .document,
                    status: .cancelled
                )
                self.show(.failed(message: HUDCopy.cancelledKept))
                self.hide(after: HUDCopy.rescueDuration)
            } catch where Self.isCancellation(error) {
            } catch {
                self.show(.cancelled)
                self.hide(after: 0.8)
            }
        }
    }

    /// Where a compile at `attempted` sent the words, by the same rule the router uses. Nil
    /// when nothing left the Mac.
    static func sentTo(attempted: EditLevel, transcript: String) -> ProviderChoice? {
        guard attempted != .verbatim else { return nil }
        let choice = RoutingGenerator.choice(policy: ProviderSettings.live(), level: attempted, transcript: transcript)
        return choice.provider == .local ? nil : choice.provider
    }

    private func noteVocabulary(_ terms: [String], workspace: WorkspaceContext) {
        guard !terms.isEmpty, let directory = workspace.directory else { return }
        lastVocabulary = VocabularySnapshot(repository: directory.lastPathComponent, branch: workspace.gitBranch, terms: terms)
    }

    /// A chord means the paste prompt, not the dictation one: swap the pre-started process.
    private func prespawnForChord() {
        Task.detached(priority: .utility) {
            if let key = CLIPrespawner.chordGuess(policy: ProviderSettings.live(), executable: ClaudeCLIGenerator.resolvedExecutable) {
                CLIPrespawner.shared.prepare(key)
            }
        }
    }

    // MARK: Fix screenshot

    /// A screenshot read on this Mac, turned into a prompt for a coding agent. The rewrite model
    /// sees only what was said; the screenshot text is appended locally, redacted.
    private func runFix(
        image: Data,
        transcript: Transcript,
        destination: Destination,
        context: FocusContext,
        modifiers: GestureModifiers
    ) async throws {
        hudContext.mode = .fix
        show(.compiling(partial: "Reading the screenshot on this Mac…"))
        let read = try await ScreenshotOCR.read(image)
        guard !read.isEmpty || !transcript.isEmpty else {
            show(.failed(message: HUDCopy.noTextInImage))
            hide(after: HUDCopy.rescueDuration)
            return
        }

        let override: EditLevel? = modifiers.contains(.control) ? .full : nil
        let decision = LevelHeuristic.decide(transcript: transcript.text, destination: destination, override: override)
        let fixProvider = transcript.isEmpty || decision.level == .verbatim
            ? nil
            : HUDCopy.providerLabel(RoutingGenerator.choice(policy: ProviderSettings.live(), level: decision.level, transcript: decision.transcript))
        show(.compiling(partial: transcript.isEmpty ? "" : "Writing the prompt…", provider: fixProvider))
        let prompter = ScreenshotPrompter(compiler: compiler)
        let result = try await prompter.build(
            ask: decision.transcript,
            screenshot: read,
            destination: destination,
            level: decision.level,
            vocabulary: vocabulary.terms(for: context.workspace)
        ) { [weak self] partial in
            Task { @MainActor in
                guard let self, case let .compiling(_, provider) = self.hud else { return }
                self.hud = .compiling(partial: partial, provider: provider)
            }
        }
        trace.mark(.compileDone)

        let fix = FixPreview(result: result, showingWithout: false, heard: transcript.text)
        pending = Pending(
            transcript: transcript,
            compiled: CompiledPrompt(
                text: fix.text,
                level: result.level,
                requestJSON: result.requestJSON,
                sentTo: result.requestJSON == nil ? nil : Self.sentTo(attempted: decision.level, transcript: decision.transcript)
            ),
            destination: destination,
            bundleIdentifier: context.bundleIdentifier,
            fix: fix
        )
        monitor.setPreviewMode(true)
        startPreviewTimeout()
        trace.mark(.previewShown)
        showFix(fix, destination: destination, attempted: decision.level)
    }

    private func showFix(_ fix: FixPreview, destination: Destination, attempted: EditLevel) {
        var notes: [String] = []
        if fix.result.lineCount == 0 {
            notes.append(HUDCopy.noTextUsedWords)
        } else if fix.showingWithout {
            notes.append("Without the screenshot text. Tab puts it back.")
        } else {
            notes.append(HUDCopy.readLines(fix.result.lineCount))
        }
        if let secrets = fix.result.secretsNote, !fix.showingWithout { notes.append(secrets) }

        var source = HUDCopy.source(for: nil)
        if fix.result.requestJSON != nil {
            let choice = RoutingGenerator.choice(policy: ProviderSettings.live(), level: attempted, transcript: fix.heard)
            source = HUDCopy.source(for: choice.provider, escalated: choice.escalated) + " The screenshot text was not sent."
        }
        showPreview(PreviewHUD(
            text: fix.text,
            mode: .fix,
            destination: destination.displayName,
            label: fix.result.level.displayName,
            heard: fix.heard.isEmpty ? nil : fix.heard,
            notes: notes,
            source: source,
            hints: fix.result.lineCount > 0
                ? (fix.showingWithout ? "⏎ insert · ⇥ with screenshot · esc" : "⏎ insert · ⇥ without screenshot · esc")
                : "⏎ insert · esc"
        ))
    }

    /// Tab in a screenshot preview: with ⇄ without the screenshot text. Nothing is re-run.
    private func flipFix(_ pending: Pending) {
        guard var fix = pending.fix, fix.result.lineCount > 0 else { return }
        fix.showingWithout.toggle()
        var updated = pending
        updated.fix = fix
        updated.compiled.text = fix.text
        self.pending = updated
        startPreviewTimeout()
        showFix(fix, destination: pending.destination, attempted: fix.result.level)
    }

    // MARK: Smart Paste

    /// The clipboard is the content and what was said is the instruction. Always previews:
    /// the text was not typed by the user, so they see it before it lands.
    private func runSmartPaste(
        clip: ClipContent,
        transcript: Transcript,
        destination: Destination,
        context: FocusContext,
        purpose: SmartPasteRequest.Purpose = .paste
    ) async throws {
        let text: String
        switch clip {
        case let .text(value):
            text = value
        case let .image(data):
            // A screenshot into a coding agent becomes a bug prompt. Anywhere else, its text
            // is the clip.
            if SmartPaster.agentDestinations.contains(destination.id) {
                try await runFix(image: data, transcript: transcript, destination: destination, context: context, modifiers: [])
                return
            }
            show(.compiling(partial: "Reading the screenshot on this Mac…"))
            let read = try await ScreenshotOCR.read(data)
            guard !read.isEmpty else {
                show(.failed(message: HUDCopy.noTextInImage))
                hide(after: HUDCopy.rescueDuration)
                return
            }
            text = read.text
        case .empty:
            show(.failed(message: HUDCopy.emptyClipboard))
            hide(after: HUDCopy.rescueDuration)
            return
        case let .refused(reason):
            show(.failed(message: reason.message))
            hide(after: HUDCopy.rescueDuration)
            return
        }

        let pasteProvider = transcript.isEmpty ? nil : HUDCopy.providerLabel(.init(provider: makePaster().provider, escalated: false))
        show(.compiling(partial: "", provider: pasteProvider))
        let request = SmartPasteRequest(
            clip: text,
            instruction: transcript.text,
            destination: destination,
            vocabulary: vocabulary.terms(for: context.workspace),
            purpose: purpose
        )
        let result: SmartPasteResult
        do {
            result = try await makePaster().paste(request) { [weak self] partial in
                Task { @MainActor in
                    guard let self, case let .compiling(_, provider) = self.hud else { return }
                    self.hud = .compiling(partial: partial, provider: provider)
                }
            }
        } catch let error as SmartPasteError {
            show(.failed(message: error.localizedDescription))
            hide(after: HUDCopy.rescueDuration)
            return
        } catch where Self.isCancellation(error) {
            throw error
        } catch {
            let paster = makePaster()
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // An edit that cannot be rewritten leaves the selection exactly as it was.
            if purpose == .edit {
                show(.failed(message: HUDCopy.editProviderFailed(paster.provider, reason: reason)))
                hide(after: HUDCopy.rescueDuration)
                return
            }
            // The provider failed or could not be reached. Offer the clip unchanged rather
            // than a blank or a vanished overlay.
            result = paster.unchanged(request, note: HUDCopy.providerFailed(paster.provider, reason: reason))
        }
        trace.mark(.compileDone)

        let paste = PastePreview(result: result, showingAsCopied: false, purpose: purpose)
        pending = Pending(
            transcript: transcript,
            compiled: CompiledPrompt(text: result.insertText, level: .medium, requestJSON: result.requestJSON),
            destination: destination,
            bundleIdentifier: context.bundleIdentifier,
            paste: paste
        )
        monitor.setPreviewMode(true)
        startPreviewTimeout()
        trace.mark(.previewShown)
        showPaste(paste, destination: destination, heard: transcript.text)
    }

    private func showPaste(_ paste: PastePreview, destination: Destination, heard: String) {
        let result = paste.result
        let flippable = result.asCopiedText != result.insertText
        let rewritten = !paste.showingAsCopied && result.outcome == .rewritten
        var notes: [String] = []
        if let note = result.note { notes.append(note) }
        if rewritten, let numbers = result.numberSummary { notes.append(numbers) }
        let edit = paste.isEdit
        let verb = edit ? "replace" : "paste"
        showPreview(PreviewHUD(
            text: paste.showingAsCopied ? result.asCopiedText : result.insertText,
            mode: edit ? .edit : .paste,
            destination: destination.displayName,
            label: rewritten ? "Rewritten" : (edit ? "Original" : "As copied"),
            heard: heard,
            notes: notes,
            // Honest about the request even when the original is on screen: the clip was sent.
            source: HUDCopy.pasteSource(for: result.sentTo, rewritten: result.sentTo != nil, isEdit: edit),
            hints: flippable
                ? (paste.showingAsCopied ? "⏎ \(verb) · ⇥ rewritten · esc" : (edit ? "⏎ replace · ⇥ original · esc" : "⏎ paste · ⇥ paste original · esc"))
                : "⏎ \(verb) · esc"
        ))
    }

    /// Tab in a Smart Paste preview: as copied ⇄ rewritten. Nothing is sent again.
    private func flipPaste(_ pending: Pending) {
        guard var paste = pending.paste, paste.result.asCopiedText != paste.result.insertText else { return }
        paste.showingAsCopied.toggle()
        var updated = pending
        updated.paste = paste
        updated.compiled.text = paste.showingAsCopied ? paste.result.asCopiedText : paste.result.insertText
        self.pending = updated
        startPreviewTimeout()
        showPaste(paste, destination: pending.destination, heard: pending.transcript.text)
    }

    /// Runs the compiler, streaming partial text into the overlay as it arrives.
    private func compile(
        transcript: String,
        destination: Destination,
        context: FocusContext,
        modifiers: GestureModifiers
    ) async throws -> (CompiledPrompt, attempted: EditLevel) {
        // Shift with the trigger means "insert exactly what I said"; Control forces a full
        // compile even for a short utterance.
        let override: EditLevel? = modifiers.contains(.shift) ? .verbatim
            : modifiers.contains(.control) ? .full
            : nil
        let decision = LevelHeuristic.decide(
            transcript: transcript,
            destination: destination,
            override: override
        )
        Log.compile.info("Level \(decision.level.rawValue, privacy: .public) for \(destination.id, privacy: .public): \(decision.reason, privacy: .public)")

        guard decision.level != .verbatim else {
            return (CompiledPrompt(text: decision.transcript, level: .verbatim), .verbatim)
        }

        let choice = RoutingGenerator.choice(policy: ProviderSettings.live(), level: decision.level, transcript: decision.transcript)
        show(.compiling(partial: "", provider: HUDCopy.providerLabel(choice)))
        let compiled = try await runCompiler(
            transcript: decision.transcript,
            level: decision.level,
            destination: destination,
            workspace: context.workspace
        )
        return (compiled, decision.level)
    }

    /// The preview for a dictation, with the line that says where the words went. Worked out
    /// with the same routing rule that sent them, from the level that was attempted: a
    /// guardrail fallback still sent the words, even though the raw transcript is shown.
    private func dictationPreview(
        _ compiled: CompiledPrompt,
        destination: Destination,
        attempted: EditLevel,
        transcript: String
    ) -> PreviewHUD {
        let source: String
        if attempted == .verbatim {
            source = HUDCopy.source(for: nil)
        } else {
            let choice = RoutingGenerator.choice(policy: ProviderSettings.live(), level: attempted, transcript: transcript)
            source = HUDCopy.source(for: choice.provider, escalated: choice.escalated)
        }
        var notes: [String] = []
        if compiled.usedRawFallback {
            notes.append("The rewrite failed a check, so this is exactly what you said.")
        }
        return PreviewHUD(
            text: compiled.text,
            mode: .dictate,
            destination: destination.displayName,
            label: compiled.level.displayName,
            notes: notes,
            source: source,
            hints: "⏎ insert · ⇥ ⇧⇥ or 1–4 level · R start over · esc"
        )
    }

    /// One compiler call with its deltas wired to the overlay.
    private func runCompiler(
        transcript: String,
        level: EditLevel,
        destination: Destination,
        workspace: WorkspaceContext
    ) async throws -> CompiledPrompt {
        // The project's own words, so "aut midway" can come back as "auth middleware".
        // Spelling authority only: the compiler is told never to introduce a term from here
        // that the speaker did not say.
        let terms = vocabulary.terms(for: workspace)
        noteVocabulary(terms, workspace: workspace)
        return try await compiler.compile(
            CompileRequest(
                transcript: transcript,
                level: level,
                destination: destination.id,
                instructions: destination.instructions,
                vocabulary: terms
            )
        ) { [weak self] partial in
            Task { @MainActor in
                guard let self, case let .compiling(_, provider) = self.hud else { return }
                self.hud = .compiling(partial: partial, provider: provider)
                if self.trace.offset(of: .compileFirstToken) == nil {
                    self.trace.mark(.compileFirstToken)
                }
            }
        }
    }

    private func insert(
        _ compiled: CompiledPrompt,
        transcript: Transcript,
        destination: Destination,
        intendedFor bundleIdentifier: String? = nil,
        paste: PastePreview? = nil
    ) async throws {
        // The text was shaped for one particular app. A compile takes seconds, and the user is
        // free to switch windows while it runs, so paste only where the dictation was aimed.
        // Without this, dictating into Slack and then switching to a terminal put the message
        // into the shell.
        if let intended = bundleIdentifier,
           let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           front != intended {
            Log.insert.info("Focus moved from \(intended, privacy: .public) to \(front, privacy: .public); not inserting")
            // A dictation is handed back on the clipboard. A Smart Paste is not: the user's
            // own clip is still there, and replacing it would lose the thing they copied.
            // A dictation or an edit hands its text back. A Smart Paste leaves the user's clip.
            let keepsClip = paste.map { !$0.isEdit } ?? false
            if !keepsClip { TextRescue.copy(compiled.text) }
            show(.failed(message: HUDCopy.focusMoved(to: destination.displayName, isPaste: keepsClip)))
            hide(after: HUDCopy.rescueDuration)
            record(
                transcript: transcript,
                compiled: compiled,
                destination: destination,
                status: .cancelled,
                paste: paste
            )
            return
        }
        inserter.onChordPosted = { [weak self] in self?.trace.mark(.pasted) }
        do {
            try await inserter.insert(compiled.text, strategy: destination.strategy)
        } catch let error as InsertionError {
            if case .secureInputActive = error { throw error }
            // The paste itself failed. Hand the text back rather than losing it.
            let keepsClip = paste.map { !$0.isEdit } ?? false
            if !keepsClip { TextRescue.copy(compiled.text) }
            show(.failed(message: HUDCopy.insertFailed(error.localizedDescription, isPaste: keepsClip)))
            hide(after: HUDCopy.rescueDuration)
            record(transcript: transcript, compiled: compiled, destination: destination, status: .failed, paste: paste)
            return
        }
        trace.mark(.inserted)
        show(.inserted(into: destination.displayName, pasted: paste.map { !$0.isEdit } ?? false, landing: Landing(destinationID: destination.id)))
        hide(after: 1.0)
        record(transcript: transcript, compiled: compiled, destination: destination, status: .inserted, paste: paste)
        Log.timing.info("Dictation timings: \(self.trace.summary(), privacy: .public)")
    }

    // MARK: Preview keys

    private func handlePreview(_ key: PreviewKey) {
        guard let pending else {
            monitor.setPreviewMode(false)
            return
        }
        switch key {
        case .insert:
            clearPending()
            // The compiled text was shaped for a particular app, and the preview may have sat
            // there while the user switched windows. `insert` re-checks the frontmost app
            // immediately before pasting — a narrower window than checking here — and records
            // the abandoned prompt in history rather than dropping it silently.
            //
            // Deliberately not held in `activeWork`. Insertion is chunked and sleeps between
            // chunks, so those sleeps are cancellation points: letting the next dictation
            // cancel this would leave half a prompt in the editor and the clipboard
            // unrestored. Once a paste has started it must be allowed to finish.
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.insert(
                        pending.compiled,
                        transcript: pending.transcript,
                        destination: pending.destination,
                        intendedFor: pending.bundleIdentifier,
                        paste: pending.paste
                    )
                } catch {
                    self.report(error)
                }
            }

        case .cycleLevel, .cycleBack:
            if pending.paste != nil {
                flipPaste(pending)
            } else if pending.fix != nil {
                flipFix(pending)
            } else {
                let target = key == .cycleLevel
                    ? pending.requestedLevel.cycled
                    : PreviewLevels.previous(before: pending.requestedLevel)
                recompile(pending, at: target)
            }

        case .levelVerbatim, .levelLight, .levelMedium, .levelFull:
            guard pending.paste == nil, pending.fix == nil else { return }
            let number = [PreviewKey.levelVerbatim, .levelLight, .levelMedium, .levelFull].firstIndex(of: key)! + 1
            if let target = PreviewLevels.level(forNumber: number), target != pending.requestedLevel {
                recompile(pending, at: target)
            }

        case .scrollUp, .scrollDown:
            guard var model = lastPreview else { return }
            let step = key == .scrollUp ? -PreviewLevels.scrollStep : PreviewLevels.scrollStep
            let lines = model.text.components(separatedBy: "\n").count
            model.scrollLine = min(max(0, model.scrollLine + step), max(0, lines - 1))
            startPreviewTimeout()
            showPreview(model)

        case .cancel:
            clearPending()
            record(
                transcript: pending.transcript,
                compiled: pending.compiled,
                destination: pending.destination,
                status: .cancelled,
                paste: pending.paste
            )
            show(.cancelled)
            hide(after: 0.6)

        case .rerecord:
            clearPending()
            hide(after: 0)
        }
    }

    /// Recompiles the same transcript at a different level, so a wrong guess costs one key
    /// rather than another recording.
    private func recompile(_ pending: Pending, at level: EditLevel) {
        // Already compiled at this level: instant, nothing sent again.
        if let cached = pending.levels.cached(level) {
            var updated = pending
            updated.compiled = cached
            updated.requestedLevel = level
            self.pending = updated
            startPreviewTimeout()
            showPreview(dictationPreview(cached, destination: pending.destination, attempted: level, transcript: pending.transcript.text))
            return
        }
        // Keep the current text up, dimmed, rather than blanking it for the 6 to 10 seconds a
        // subscription compile can take.
        if var stale = lastPreview {
            stale.isStale = true
            stale.notes = ["Rewriting at \(level.displayName)…"]
            showPreview(stale)
        } else {
            show(.compiling(partial: ""))
        }
        activeWork?.cancel()
        activeWork = Task { [weak self] in
            guard let self else { return }
            do {
                var compiled: CompiledPrompt
                if level == .verbatim {
                    compiled = CompiledPrompt(text: pending.transcript.text, level: .verbatim)
                } else {
                    compiled = try await self.runCompiler(
                        transcript: pending.transcript.text,
                        level: level,
                        destination: pending.destination,
                        workspace: self.capturedContext.workspace
                    )
                }
                compiled.sentTo = Self.sentTo(attempted: level, transcript: pending.transcript.text)
                var updated = pending
                updated.compiled = compiled
                updated.requestedLevel = level
                updated.levels.store(compiled, requested: level)
                self.pending = updated
                // The preview is being used, so give it a fresh 90 s. Otherwise a few level
                // changes run the original deadline out mid-decision and the prompt vanishes.
                self.startPreviewTimeout()
                self.showPreview(self.dictationPreview(
                    compiled,
                    destination: pending.destination,
                    attempted: level,
                    transcript: pending.transcript.text
                ))
            } catch where Self.isCancellation(error) {
                // Superseded by another key press.
            } catch {
                self.report(error, rescuing: pending.transcript.text)
            }
        }
    }

    private func clearPending() {
        pending = nil
        previewTimeout?.cancel()
        previewTimeout = nil
        monitor.setPreviewMode(false)
    }

    /// A preview that is never answered releases itself, so the preview keys cannot be held
    /// hostage by a window the user walked away from.
    private func startPreviewTimeout() {
        previewTimeout?.cancel()
        previewTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.previewLifetime))
            guard !Task.isCancelled, let self, let pending = self.pending else { return }
            Log.app.info("Preview expired without an answer; releasing the preview keys")
            self.clearPending()
            let keepsClip = pending.paste.map { !$0.isEdit } ?? false
            if !keepsClip { TextRescue.copy(pending.compiled.text) }
            self.show(.failed(message: HUDCopy.previewExpired(isPaste: keepsClip)))
            self.hide(after: HUDCopy.rescueDuration)
        }
    }

    /// How long a compiled prompt waits for Return before releasing the keyboard.
    private static let previewLifetime: TimeInterval = 90

    // MARK: Errors and history

    /// Cancellation reaches here in two shapes: Swift's own `CancellationError`, and
    /// `GenerationError.cancelled`, which `Compiler` and `ClaudeCLIGenerator` throw in its place.
    /// Treating the second as a real failure is what let an abandoned dictation clear the
    /// overlay belonging to the dictation that replaced it, and dismiss it 2.5 s later.
    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if case GenerationError.cancelled = error { return true }
        return false
    }

    private func report(_ error: any Error, rescuing words: String? = nil) {
        var message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = message
        if let words, !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !(error is InsertionError) {
            TextRescue.copy(words)
            message = HUDCopy.failedWithWordsCopied(message)
        } else {
            message = HUDCopy.sentence(message)
        }
        // Critical: an error while a preview is up must release the preview keys. Leaving
        // them captured swallows Return, Tab, Escape and R across every app, with no visible
        // overlay explaining why, and the user's natural recovery (pressing Return) would
        // paste stale text into whatever is focused now.
        clearPending()
        show(.failed(message: message))
        // Secure input leaves the transcript on the clipboard, so that message needs longer.
        hide(after: HUDCopy.rescueDuration)
        Log.app.error("Dictation failed: \(message, privacy: .public)")
    }

    private func record(
        transcript: Transcript,
        compiled: CompiledPrompt,
        destination: Destination,
        status: DictationRecord.Status,
        paste: PastePreview? = nil
    ) {
        guard let queue = Database.queue else { return }
        // A Smart Paste writes its own row: what went into the field may hold a secret the
        // user copied, put back on this Mac, and history must never keep that.
        let record = paste?.historyResult.record(
            id: trace.id.uuidString,
            instruction: transcript.text,
            destination: destination,
            status: status,
            purpose: paste?.purpose ?? .paste
        ) ?? DictationRecord(
            id: trace.id.uuidString,
            createdAt: Date(),
            destination: destination.id,
            level: compiled.level.rawValue,
            rawTranscript: transcript.text,
            compiledText: compiled.text,
            requestJSON: compiled.requestJSON,
            status: compiled.usedRawFallback ? .rawFallback : status,
            provider: compiled.sentTo?.rawValue ?? "local"
        )
        let timings = StageTimingRecord.rows(for: trace, dictationId: record.id)
        Task.detached {
            do {
                try await queue.write { db in
                    try record.insert(db)
                    for var row in timings { try row.insert(db) }
                }
            } catch {
                Log.db.error("Could not save dictation: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Overlay

    private var elapsed: TimeInterval {
        startedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    private func showPreview(_ model: PreviewHUD) {
        lastPreview = model
        show(.preview(model))
    }

    private func show(_ state: HUDState) {
        if let words = HUDAnnouncement.text(for: state, previous: hud) {
            HUDAnnouncement.post(words)
        }
        hud = state
        if panel == nil {
            panel = HUDPanel { [selfBox] in
                HUDHost(box: selfBox)
            }
        }
        panel?.present()
    }

    /// Hides the overlay. Always releases the preview keys first: an invisible overlay must
    /// never still be capturing Return, Tab, Escape and R.
    private func hide(after delay: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let self else { return }
            self.clearPending()
            self.hud = .hidden
            self.panel?.dismiss()
        }
    }

    private func startMeter() {
        meterTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let locked = self.monitor.isLocked
                self.hud = .listening(
                    level: self.capture.currentLevel,
                    seconds: self.elapsed,
                    locked: locked,
                    partial: self.livePartial,
                    mode: self.pasteRead != nil ? .paste : self.editRead != nil ? .edit : .dictate,
                    app: self.listeningApp
                )
                // Hands-free stops itself once the room goes quiet.
                if locked, self.capture.silenceSeconds >= self.silenceStopAfter {
                    self.monitor.reportSilenceTimeout()
                }
                // A key-up that never arrives would otherwise record forever. Escape cannot
                // rescue that under Secure Input, where key events are suppressed, so the
                // ceiling is the only way out.
                if self.elapsed >= self.maximumHold {
                    Log.hotkey.error("Trigger held past \(self.maximumHold, privacy: .public)s; finishing")
                    self.monitor.reportHoldTimeout()
                }
            }
        }
        // Common modes, not the default one. While a menu is open or a window is being
        // dragged the main run loop is in tracking mode and a default-mode timer stops firing
        // — which would freeze the meter, and, far worse, suspend the silence detector and
        // the hold ceiling: the two things that end a dictation nobody is watching.
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
    }
}

/// Weak holder that lets the hotkey callback reach the controller owning the monitor.
private final class ControllerBox: @unchecked Sendable {
    weak var controller: DictationController?
}

/// Bridges the observable controller into the panel's SwiftUI content.
///
/// The reference is weak, through the box, and has to be. The controller owns the panel, the
/// panel's hosting view owns this root view: a strong reference here closes that loop and
/// neither object is ever released, taking the audio engine and the event tap with them.
/// Observation is unaffected, because `hud` is read inside `body`, which is exactly where
/// `@Observable` registers the dependency.
private struct HUDHost: View {
    let box: ControllerBox

    var body: some View {
        HUDView(state: box.controller?.hud ?? .hidden, context: box.controller?.hudContext ?? HUDContext())
    }
}

/// The project words a dictation used, as the Vocabulary pane shows them.
struct VocabularySnapshot: Equatable, Sendable {
    var repository: String
    var branch: String?
    var terms: [String]
}
