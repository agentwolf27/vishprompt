# VishPrompt

<!-- pulse -->

## What we are building
VishPrompt (formerly Visprflow) is a native macOS menu bar app that takes over the fn key (once macOS's emoji picker on that key is set to Do Nothing) for a full dictation-to-prompt pipeline: hold fn, talk, release, and the app transcribes on-device with Parakeet v3, then compiles the raw speech into the best-suited prompt for wherever the cursor is (Claude Code, Cursor, claude.ai, Slack, email, or a plain shell), inserting it with a preview step for agent destinations.

## Why
Existing dictation tools like Wispr Flow are cloud-only, heavy (800 MB idle), unreliable, and produce generic cleaned-up text rather than a structured prompt tailored to the destination app and its context.

## Done looks like
A short list of concrete, checkable outcomes. If you cannot check it, it does not belong here.
Tick one only when its VERIFY passes, not when someone says it is done.

- [x] Menu bar app with permission onboarding, Keychain, timing, local SQLite history — `ls ~/Applications/VishPrompt.app`
- [x] Hold-to-talk loop with on-device Parakeet v3 transcription and paste-back — `make verify-stt`
- [x] Prompt compiler with destination detection, guardrails, raw fallback — `make test`
- [x] Repository vocabulary and workspace context harvesting — `make test`
- [x] The unit test suite passes (README cites 177; not independently counted) — `make test`
- [x] Audit fixes: crash trap, Right-Option key mapping, clipboard restore, probe hang — `test -f VishPrompt/Core/Audio/ObjCException.m`
- [x] Live streaming transcript preview while speaking — `test -f VishPrompt/Core/STT/StreamingTranscriber.swift`
- [-] Streamed transcript replaces the batch model — evaluated in 14f55cf and declined: accuracy wins a trade that costs 80 ms
- [x] Now-tier latency fixes: pre-roll, post-roll, warm-up, exception trapping — `grep -q postRollDuration VishPrompt/Core/Audio/AudioCapture.swift`
- [x] Next-tier robustness: device/wake recovery, pinned paste target, hung CLI handling — `grep -q observeDeviceChanges VishPrompt/Core/Audio/AudioCapture.swift`
- [x] Second audit sweep: overlay retain cycle, timer run-loop modes, tap port, preview lifetime — `grep -q "HUDHost(box:" VishPrompt/Core/Pipeline/DictationController.swift`
- [x] The streaming model is released when idle, so its 580 MB comes back — `grep -q idleLifetime VishPrompt/Core/STT/StreamingTranscriber.swift`
- [x] The speech model costs under 300 MB of our own heap, not 1.2 GB — `make verify-memory`
- [ ] The 40-item golden set exercised end to end (plan.html's phase-2 bar; 8 fixtures today) — `test "$(find Fixtures/golden -name '*.json' | wc -l)" -ge 40`

- [x] PR 1: `make test` and every `verify-*` can fail — `make verify-test-can-fail`
- [x] PR 1: `test-class` fails on a missing class or a skip — `make verify-test-class-can-fail`
- [x] PR 1: V within 1.0 s converts for fn, Right Option and Right Command; extra ⌘/⌃, a late V and hands-free V are ignored; tap+V finishes; a bare tap is discarded — `make test-class C=HotkeyGestureTests`
- [x] PR 1: The corpus is caught, the known-miss list is exact, SHAs and UUIDs are kept, and bad nonce tokens fall back — `make test-class C=RedactorTests`
- [x] PR 1: Concealed, transient and auto-generated clips are refused; image+text gives text — `make test-class C=ClipboardReaderTests`
- [x] PR 1: Zero calls for silence, shell, local mode, over 20k characters and before consent; consent per provider; no corpus secret in a request; a guardrail failure inserts the clip — `make test-class C=SmartPasteTests`
- [x] PR 1: No restored secret in any history column, through the pipeline — `make test-class C=SmartPasteHistoryTests`
- [x] PR 1: No Return is posted; the fallback entry is concealed and transient — `make test-class C=InserterTests`
- [x] PR 1: The memory ceiling holds under pipefail — `make verify-memory`
- [x] PR 1: Release builds — `make release`
- [x] PR 1: UI/UX item 1, never lose text: endings that don't insert copy the text and say so — `make test-class C=HUDCopyTests`
- [x] PR 1: Smart Paste numbers check: an added number falls back, a dropped one is reported — `make test-class C=NumberCheckTests`
- [x] PR 2: Real Vision on committed fixtures finds the substrings, the O/0 key is redacted, and a blank image is empty — `make verify-ocr`
- [x] PR 2: The OCR block is fenced, verbatim and redacted; no OCR text appears in any request — `make test-class C=ScreenshotPromptTests`
- [x] PR 2: A screenshot copied in the last 2 minutes is picked up by "fix this" in an agent; VishPrompt's own clipboard writes never look fresh — `make test-class C=ClipboardWatcherTests`

- [x] UI/UX Q1: every ending that doesn't insert names the cause and the next step, and keeps the text (copied, or in History for a long cancelled recording) — `make test-class C=HUDCopyTests`
- [x] UI/UX Q2: the preview scrolls to its end, each level's result is kept so Tab back is instant, ⇧Tab goes back, R is shown — `make test-class C=PreviewLevelCacheTests`
- [x] UI/UX Q3: every overlay state has a VoiceOver announcement and labels; Reduce Motion drops the animation — `make test-class C=AccessibilityAnnouncementTests`
- [x] UI/UX Q4: the compiling and preview headers name the provider, escalations included — `make test-class C=ProviderLabelTests`
- [x] UI/UX Q5: no jargon or raw errors in setup, destinations or the overlay; the permission count matches the list — `make test-class C=CopyFixTests`
- [x] UI/UX Q6: destination edits save as they are made and survive switching rows — `make test-class C=DestinationSettingsTests`
- [x] UI/UX L1: a real Settings window (⌘,) with panes, a real menu, and a three-step setup — `make test-class C=SettingsPaneTests`
- [x] UI/UX L2: a History window that shows what was said, exactly what was sent or "Stayed on this Mac", and the result — `make test-class C=HistoryTests`

- [x] Speed S0: a harness measures key-up → pasted on the Release build (20 trials, median and p90 with n, CSV kept), and a report reads real dictations from History — `make verify-latency`
- [x] Speed S1a: one shared API session, opened early, with the key cached in memory — `make test-class C=ClaudeGeneratorSessionTests`
- [x] Speed S1b: the post-roll ends on the first audio buffer after key-up, not after a fixed 120 ms, and the last word survives — `make verify-stt`
- [-] Speed S1c: key-up no longer waits for the streaming model to reset before the batch transcription starts — declined on measurement: the stop costs about 6 ms, and the live preview showed no cost interleaved (790 against 830 ms median, n=20 each); see docs/research/latency/README.md
- [x] Speed S1d: a self-correction in a quick message no longer escalates silently to the 6–10 s subscription path — `make test-class C=EscalationTests`
- [x] Speed S1e: a guardrail rejection retries on this Mac, not with a second model call — `make test-class C=CompilerTests`
- [x] Speed S2a: the claude CLI is started at key-down, so the subscription path's first words come sooner — `make test-class C=ClaudeCLIPrespawnTests`
- [x] Speed S2b: workspace probes read process info in-process instead of spawning ps and lsof — `make test-class C=ProcessProbeTests`

- [x] Edit selection: trigger + R within 1.0 s asks to edit the selection; it never collides with fn+V, and a quick tap with R finishes — `make test-class C=HotkeyGestureTests`
- [x] Edit selection: the selection is read through Accessibility, or by a ⌘C that puts the clipboard back; secure fields and concealed copies are refused — `make test-class C=SelectionReaderTests`
- [x] Edit selection: it reuses Smart Paste's consent, redaction and numbers check; silence and terminals are refused with a next step; History keeps the redacted form, marked as an edit — `make test-class C=SelectionEditTests`
- [x] Edit selection: release builds — `make release`

- [x] UI v2.1: a capsule anchor while listening, transcribing and rewriting, with the concept's copy for every state, the take time frozen while it works, and undo named only where ⌘Z works — `make test-class C=HUDCapsuleTests`
- [x] UI v2.2: a card drops from the capsule only when there is a decision (preview, error); errors stay until the next key-down or 6 s; crossfade under Reduce Motion — `make test-class C=HUDCardTests`
- [x] UI v2.3: on a notched built-in display the capsule splits into two lobes beside the camera housing, read from the screen's auxiliary areas; elsewhere a free capsule below the menu bar; never a drawn notch — `make test-class C=NotchGeometryTests`
- [x] UI v2.4: History rows read "what you said → where · when · what left the Mac", Return pastes again and ⌘C copies — `make test-class C=HistoryTests`
- [x] UI v2.5: the overlay's surface is one style choice: Liquid Glass on macOS 26 when built with its SDK, the thin material otherwise — `make test-class C=SurfaceStyleTests`
- [x] UI v2.6: the menu bar icon shows recording, working, paused and needs-setup — `make test-class C=MenuBarIconTests`

- [x] Tap 1: the palm-rest accelerometer is found only on Macs that have it, and its 22-byte reports parse to g — `make test-class C=SPUAccelerometerTests`
- [x] Tap 1: a live read on this Mac gets about 800 reports a second when active and about 100 when idle, near 1 g at rest — `make verify-sensor`
- [ ] Tap 2: on recorded samples a double tap fires once, and single taps, typing, trackpad clicks, setting the Mac down and lifting it fire nothing — `make test-class C=TapDetectorTests`
- [x] Tap 3: a double tap starts hands-free recording; a second double tap, the trigger key, Escape or silence ends it; off by default and hidden without the sensor; the capsule says a tap started it — `make test-class C=ChassisTapGestureTests`
- [x] Tap 3: sampling stops on screen lock, display sleep and battery under 10%, and idle sampling costs under 1% of a core — `make verify-tap-cpu`
- [ ] Tap 4: the README explains the tap trigger, held until the LinkedIn post is out — `grep -q "palm rest" README.md`

- [x] Home 1: one VishPrompt window (at least 1040×700) with Home, History, Dictionary and Settings in a sidebar opens from the menu and ⌘Y, in a warm light and a warm dark theme that follow the Mac unless Settings says otherwise — `make test-class C=HomeWindowTests`
- [x] Home 2: each saved dictation is a card with its time, app, mode and where the words went, a Copy that says Copied, what you said with its own Copy, pin and delete; Home counts today from real rows; History searches and groups by day; Return still pastes again — `make test-class C=HistoryCardTests`
- [x] Home 3: Dictionary shows the words VishPrompt spells your way; Settings is cards wired to the real trigger, palm-rest, provider and appearance settings — `make test-class C=SettingsCardTests`
- [ ] Home 4: history is kept for 30, 60 or 90 days or forever; pinned items are never pruned; this install keeps everything and new installs keep 90 days; a shorter period confirms with the real count first — `make test-class C=RetentionTests`

## Later

From plan.html's phases 3–5. docs/roadmap.html supersedes that plan and, with its twelve items shipped or declined, queues none of these yet.

- [ ] Groq added as a faster rewrite provider — `grep -rq GroqGenerator VishPrompt/Core/Compile`
- [ ] Selected text and screen OCR available as compiler context
- [ ] Notarised release with Sparkle auto-updates shipped — `grep -q Sparkle project.yml`

## Out of scope
- Uploading raw audio to any cloud service by default (on-device transcription is the default)
- Fixed-tone generic dictation cleanup like Wispr Flow's four tones
- Cross-platform support (Windows/Linux); macOS Apple Silicon only
- Snippets and a prompt library (deferred past phase 5)

## Constraints
- macOS 15+, Apple Silicon, native Swift, XcodeGen-generated project (project.yml is source of truth)
- On-device STT via Parakeet v3 through FluidAudio; FluidAudio 0.15.6 already pinned, no dependency bump needed for streaming
- Rewrite providers limited to local, Claude subscription, or Anthropic API key
- Must build with a stable signing identity so permission grants survive rebuilds
- Debug builds must not be distributed from ~/Applications; only Release install target is used
- git workflow: main only receives dev; feature branches rebase back into dev, never deleted

---

_Drafted by Pulse on 2026-09-04 from README, git log, docs and chat history. Evidence for ticked items:_
- Menu bar app with permission onboarding, Keychain, timing, local SQLite history — README status table; commit 'feat(phase-0): foundations'
- Hold-to-talk loop with on-device Parakeet v3 transcription and paste-back — commit 'feat(phase-1): the dictation loop'
- Prompt compiler with destination detection, guardrails, raw fallback — commit 'feat(phase-2,3): prompt compiler, destinations'
- Repository vocabulary and workspace context harvesting — README: 'Repository vocabulary from your git workspace'
- 177 unit tests pass and app installed at ~/Applications — README 'Status'; build-report.html '177 unit tests passing'
- Audit fixes: crash, key-mapping, clipboard, probe-hang bugs resolved — git log: 'fix: stop the app crashing...', 'fix: bound the shell probes and cap...'
- Now-tier latency fixes: pre-roll, post-roll, warm-up, exception trapping — commit 'feat: the "now" tier — first word, last word, first run, silent failures'
- Next-tier robustness: device/wake recovery, pinned paste target, hung CLI handling — commit 'feat: the "next" tier — device changes, wrong-window pastes, a hung CLI'

### Claude (research session) · round 1 · 2026-10-23 — proposal: what to build next

Proposed, not frozen. This is two to four weeks of work, so it gets argued here (plan-together) before anything is dispatched. Nothing above is ticked or changed by it. Research, sources and scoring: [docs/research/next-features-2026-10-23.md](docs/research/next-features-2026-10-23.md).

Top three:
- **R1 — Speak-to-transform and Smart Paste.** Read the selection and a local clipboard history at key-down. Speak an edit over the selection, or compile the clipboard for its destination. Secrets are redacted on-device before any provider call.
- **R2 — Nothing leaves, proven.** An on-device rewrite through Apple Foundation Models (macOS 26, opt-in). A history window showing the exact request sent. An egress test that fails on any outbound connection in local mode.
- **R3 — Public eval and latency harness.** 40 golden cases, per-provider metrics, and an independent re-run of the end-of-speech → text-in-field benchmark.

Proposed outcomes. None of these targets exist yet. Each would become a `Done looks like` line only once frozen.
- Licence file added — `test -f LICENSE`
- Golden set reaches 40 cases (already a line above)
- `make eval` writes per-provider metrics — `make eval`
- End-of-speech → field latency, 20 trials — `make verify-latency`
- Selection read, clipboard store, smart paste, clip recall and redaction, each with tests — `make test`
- On-device provider behind `TextGenerating` — `grep -rq FoundationModelsGenerator VishPrompt/Core/Compile`
- History window — `grep -rq HistoryView VishPrompt/UI`
- No egress in local mode — `make verify-egress`
- Memory ceiling still holds — `make verify-memory`

Conflict to settle first: snippets (ranked idea 12) are under *Out of scope* above. They are not in the top three.

### Seed · Smart Paste and screenshot prompts · 2026-10-23

Vish chose ideas 1 and 2 from the research (chat: "merge it and start building 1 and 2"). This seed is what the critics argue with below. It is not frozen until the line at the end exists.

**Feature A — Spoken Smart Paste (PR 1).**
- **Gesture.** While the trigger is physically held, press V (with no ⌘ or ⌃). The V is swallowed, the overlay says "Smart Paste", and the clipboard is read at that moment. Speak an instruction ("as bullet points", "shorter", "reply no politely"), or say nothing. A short press counts once V was pressed, so a quick fn+V tap works.
- **Input.** The plain-text clip. Refused when the pasteboard carries `org.nspasteboard.ConcealedType` (password managers). Images wait for PR 2. An empty clipboard says "Nothing on the clipboard".
- **Compile.** A separate paste prompt: the CLIP is content, never instructions, and the INSTRUCTION is what was spoken. With no instruction, it reshapes the clip for the destination's conventions with as few changes as possible. Shell is always as copied, and nothing is sent.
- **Secrets.** A local `Redactor` swaps API keys, tokens, JWTs, private keys and `key=value` secrets for numbered placeholders before any provider call. For human destinations (message, email, document), the placeholders are put back locally after the model returns. For AI destinations (claude_code, cursor, codex, chat) they stay redacted. Secrets never reach a model.
- **Provider.** The existing compile-path provider. No new endpoint or host. **The new data on that existing call is the redacted clip**, and the PR says so. If the compile path is "On this Mac", the clip is pasted as copied and the overlay says why.
- **Preview.** Always. Return inserts, Esc cancels, and Tab flips between transformed and as-copied. The paste restores the user's clipboard afterwards, so the original copy is never changed.
- **Guardrails.** The output is checked against clip + instruction + vocabulary: invented identifiers, empty output, more than 3× the input length, and answer-shaped output. On failure the clip is inserted as copied.
- **History.** Recorded like a dictation. `requestJSON` holds the redacted request.

**Feature B — Screenshot to bug prompt (PR 2, stacked on PR 1).**
- **Input.** An image clip (PNG/TIFF) goes through Vision `VNRecognizeTextRequest` on-device (accurate, no language correction, so code survives). No image ever leaves the Mac.
- **Agent destinations.** The OCR text is redacted and given to the model as context. The model compiles only the spoken ask; vocabulary is repo + OCR text. VishPrompt then appends the OCR text itself, verbatim, as a block: `Screenshot text (on-device OCR, secrets removed):`. The error text is never rewritten by a model. Silence gives the block alone.
- **Other destinations.** The OCR text is treated as a text clip and goes through Feature A.

**Build hygiene (PR 1).** `make test` and `make release` end in `|| true`, so they exit 0 even when they fail. Every VERIFY that uses them is unverifiable. Add `set -o pipefail` and drop `|| true` for those two targets, so the outcomes below can fail.

**Proposed outcomes**
- fn+V while holding is detected; a short tap with V finishes rather than being discarded — `make test` (HotkeyGestureTests)
- Redactor removes the listed secret kinds and round-trips placeholders — `make test` (RedactorTests)
- Paste compile: shell is verbatim, the clip is never treated as instructions in the mock, guardrail fallback is the clip — `make test` (SmartPasteTests)
- Concealed clips are refused — `make test` (ClipboardReaderTests)
- OCR reads text from an image rendered in the test, on-device — `make test` (ScreenshotOCRTests)
- Agent prompt appends the OCR block verbatim and redacted — `make test` (ScreenshotPromptTests)
- Release build passes — `make release`

TURN: product

### product · round 1

- **At 8 s, a silent fn+V loses to ⌘V.** With no instruction the seed makes a provider call for "as few changes as possible". On the subscription that is 6–10 s (`ProviderChoice.summary`) for a near-copy. *Change:* silence means local only. Run `LocalCleanup`, fence code for agent destinations, and make no model call. Only a spoken instruction goes to the model.
- **Make the preview useful while the model runs.** *Change:* open the preview at once with the as-copied clip, the clip's age ("copied 52 min ago") and its first line. Return inserts it immediately. The transformed text swaps in when it lands. Tab only flips once there is something to flip to. Tab currently means "recompile at the next level" (`DictationController` `.cycleLevel`), so the overlay must label the new meaning: "Tab: as copied ⇄ rewritten".
- **The default provider makes it look broken.** On "On this Mac" the seed pastes the clip as copied, so a stranger's first fn+V does nothing visible. *Change:* the first time, the overlay says "Smart Paste rewrites need a model. Choose one in Settings", with a button.
- **The trigger keys collide.** If Right Command is the trigger, "V with no ⌘" can never match. Either the feature is dead, or every right-hand ⌘V gets hijacked. If Right Option is the trigger, Option+V types a character (√ on US layouts, others elsewhere) and would be swallowed. *Change:* the gesture is fn-only in PR 1, and other triggers show "Smart Paste needs fn" in Settings. Add a test that macOS gives fn+V no Globe action on 15 and 26.
- **The gesture fires by accident mid-dictation.** If V is pressed after 3 s of speech, it is unclear whether that speech becomes the instruction. *Change:* V counts only within 600 ms of trigger-down. Later, it does not convert the dictation.
- **Clipboard edge cases need defined behaviour:**
  - Empty: keep the seed's message.
  - Enormous: over about 20k characters, show "Clip is 5 MB — using the last 200 lines", or refuse outright. Never send 5 MB. Redaction and guardrails have to scale too.
  - Stale: the age shown in the preview covers it.
  - Image-only in PR 1: "Images arrive in the next version", not a silent failure.
  - Image plus text (browser copies carry both): use the text.
- **Nobody will discover it.** *Change:* add a menu-bar item "Smart Paste (hold fn, press V)", an onboarding card, and an overlay hint the first three times a dictation starts within 30 s of a copy.
- **The demo.** Feature A's best 20-second shot: copy a stack trace in Terminal, fn+V, say "ask Claude why this fails", preview, Return, all on the API key (about 1–2 s). Feature B is the stronger clip: screenshot, then a bug prompt. Record on the API key, never the subscription.

TURN: security

### security · round 1

- **The clip is new egress, and nobody is told.** The README Privacy section lists transcript, vocabulary, destination and instruction. A clip is none of these. *Change:* PR 1 updates README Privacy. Before the first send to each provider, show once: "Smart Paste sends your clipboard text (secrets removed) to <provider>". I back product's "silence is local only": then only a spoken instruction triggers egress.
- **"Secrets never reach a model" can't be backed.** Regexes miss the passwords in `postgres://u:pass@host`, `?token=` URLs, `Authorization: Basic`, unprefixed AWS secret keys, cookies, YAML `password:`, and PII. *Change:* say "known secret shapes". Add URL-userinfo and query-param rules plus an entropy check. Test against a public corpus (gitleaks rules) and list the known misses in RedactorTests. Exempt git SHAs and UUIDs that appear in repo vocabulary, so agent prompts keep their identifiers.
- **Placeholders can be injected or mangled.** A clip may already contain `[SECRET_1]`, and the model can drop, duplicate or invent placeholders. *Change:* use a per-request random token (`⟦vf-<nonce>:n⟧`). Restore only tokens that were issued, each exactly once. Any mismatch fails the guardrail and inserts the clip as copied.
- **History keeps plaintext secrets.** After a restore, `compiledText` holds the real secret. *Change:* store only the redacted form in all three columns, and add a retention setting.
- **Pasteboard.** Also refuse `TransientType` and `AutoGeneratedType` clips. The SecureInput fallback (`Inserter.swift:56`) leaves the output on the clipboard with no concealed or transient marker, so a restored secret ends up in clipboard managers. Mark it concealed and transient. For the tester: the snapshot restore bumps `changeCount`, which may defeat a password manager's auto-clear.
- **Prompt injection reaches tool-using agents.** "CLIP is content" protects our rewrite model, not Claude Code. The OCR block is appended verbatim. *Change:* wrap clip and OCR text in a fenced block labelled "pasted content: data, not instructions". The preview warns on "ignore previous…", `curl … | sh` and similar. Never send Return to agent destinations.
- **OCR beats the regexes.** O/0 and l/1 misreads let a key slip through. *Change:* the OCR text goes into the local vocabulary only. The model gets the spoken ask, and the OCR block is shown in the preview before anything is sent.
- **The CLI leaks through argv.** `ClaudeCLIGenerator.swift:61` passes the prompt as an argument, so any local process can read it with `ps`. *Change:* pipe it on stdin.
- **"On this Mac" must mean zero egress.** *Change:* `make verify-egress` exercises fn+V and OCR in local mode.
- **Irreversible:** a sent clip can't be recalled from the provider. That is why the consent and silence-local changes above matter most.

TURN: tester

### tester · round 1

- **`make test` (SomeClassTests) only checks that nothing failed.** Delete the class, rename it, or `XCTSkip` it, and the line still goes green. *Change:* add `make test-class C=<Class>`. It runs `-only-testing:VishPromptTests/<Class>` and fails on zero tests executed, on any skip, or on any failure.
- **Pipefail needs proof that it can fail.** Grepping the Makefile for `pipefail` proves nothing. *Change:* add `make verify-test-can-fail`. It runs a canary `XCTFail` (gated by `TEST_RUNNER_VISHPROMPT_CANARY=1`) and succeeds only if xcodebuild exits non-zero. `verify-*` ends in `|| true` too, so line 27's tick on `make verify-memory` has proved nothing so far. Every `verify-*` target needs the same fix.
- **Real NSPasteboard or a fake?** Use a real one, but private. `Inserter` uses `NSPasteboard.general`, so a test of it would wipe Vish's clipboard. A protocol fake would never exercise `types`, so it could not catch a wrong concealed check. *Change:* the reader and the inserter take a pasteboard parameter, and tests use `NSPasteboard(name: .init(UUID().uuidString))`.
- **The Redactor would be fitted to its own examples.** *Change:* check in a corpus at `Fixtures/secrets/` (security's gitleaks shapes, fake values) plus a known-miss list that must match exactly. A new miss fails the test. So does a "miss" that is now caught, which keeps the list honest.
- **"Secrets never reach a model", "silence is local" and security's `verify-egress` are all claims about the provider seam.** A `RecordingGenerator` checks them: zero calls for silence, shell or "On this Mac", and no corpus secret in any captured request. That is checkable. No socket opening is not. URLProtocol stubs miss custom sessions and the `claude` subprocess. *Change:* name the outcome "no provider call in local mode". Packet-level egress is checked by hand. I cannot write a command for the egress security proposed.
- **Vision OCR.** It is deterministic on one OS build, but it drifts across macOS versions. Text rendered in the test at 40 pt is trivially easy, so it proves nothing about an 11 pt dark-mode Terminal capture. *Change:* make it a separate `make verify-ocr` that runs real Vision on checked-in screenshots in `Fixtures/ocr/`. It asserts expected substrings, an O/0-trap key that must still get redacted, and that a blank image returns empty, which defeats a stubbed recognizer. `ScreenshotPromptTests` injects the OCR text, and there a fake is correct.
- **Unverifiable as written:** product's "test that fn+V has no Globe action on 15 and 26". That is OS behaviour on a real key, so it is checked by hand on each OS.
- **Checked by hand** (plain words): the real event tap swallows V in Terminal, Cursor and Slack. A real paste lands in another app and the clipboard is restored. A password manager's auto-clear survives the restore. The preview opens at once. The first-run nudge appears. Real microphone.

**Corrected outcomes**
- `make test` can fail — `make verify-test-can-fail`
- V within 600 ms converts, tap+V finishes, a bare tap is still discarded, late V is ignored — `make test-class C=HotkeyGestureTests`
- Corpus redaction, the known-miss list is exact, forged/dropped/duplicated nonce tokens fall back — `make test-class C=RedactorTests`
- Silence, shell and local mode make zero calls, no secret is in a request, guardrail fallback — `make test-class C=SmartPasteTests`
- Concealed, transient and auto-generated clips refused; image+text gives text; truncation over 20k — `make test-class C=ClipboardReaderTests`
- No restored secret in any history column — `make test-class C=DatabaseTests`
- The CLI prompt goes on stdin, never argv (fake executable echoes both) — `make test-class C=ClaudeCLIGeneratorTests`
- Real OCR on fixture screenshots — `make verify-ocr`
- The OCR block is fenced and verbatim — `make test-class C=ScreenshotPromptTests`
- Release builds — `make release`

TURN: product

### lead · round 2 — resolution

What changes in the seed, from product, security and tester. What is deferred is said plainly.

**Accepted**
- **Silence is local; only a spoken instruction calls a model** (product, security). With no instruction, the clip is pasted as copied. For agent destinations, a multi-line clip is first fenced and labelled as pasted content. Shell is always as copied.
- **Gesture.** V counts only within 1.0 s of trigger-down (product's 600 ms is tight for a chord), and only with no ⌘ or ⌃ beyond the trigger's own modifier family. That makes Right Option and Right Command work instead of colliding. A late V is ignored, and so is V during hands-free. A short tap with V finishes.
- **Clipboard rules.**
  - Refused: concealed, transient and auto-generated types.
  - Image + text: the text is used.
  - Image-only in PR 1: "Images come in the next version".
  - Over 20,000 characters: pasted as copied, never sent, and the overlay says so.
- **Consent before first egress** (security). The first time a clip would go to a provider, the overlay says it sends your clipboard text, with known secret shapes removed, to that provider, and you press fn+V again to allow. Stored per provider. The README Privacy section is updated.
- **Local compile path with an instruction** (product). The overlay says "Rewrites need a model. Choose one in Settings". Nothing is sent.
- **Redactor, per security.**
  - Wording is "known secret shapes", never "secrets never leave".
  - Rules: prefixed keys, JWTs, PEM blocks, URL userinfo, `token=`-style query params, Basic and Bearer auth, `key: value` secrets, and a conservative entropy rule that exempts git SHAs and UUIDs.
  - Placeholders are per-request nonce tokens, restored only if issued and exactly once; any mismatch falls back to the clip as copied.
  - Restored only for human destinations.
  - Tested against `Fixtures/secrets/` with an exact known-miss list (tester).
- **History stores only the redacted form** in every column (security).
- **Smart Paste never presses Return** (security).
- **The secure-input clipboard fallback marks its entry concealed and transient** (security).
- **Feature B: the OCR text never reaches the rewrite model** (security). It joins the guardrail's known words, so the spoken ask may name a file from the error. The model sees only the spoken ask and the repo vocabulary. VishPrompt appends the OCR text, redacted and fenced as "data, not instructions", and the preview shows it before Return.
- **Tests, per tester.**
  - `make test-class C=<Class>`, which fails on zero tests, a skip, or a failure.
  - `make verify-test-can-fail` with a canary.
  - pipefail on `test`, `release` and every `verify-*`.
  - Private named pasteboards in tests.
  - A `RecordingGenerator` for "no provider call".
  - `make verify-ocr` on fixtures.

**Deferred, with reason**
- **The instant preview with the as-copied clip and its age** (product). It needs the preview to accept Return mid-compile, which is a change to the state machine in its own right. Silence-is-local already removes the 8 s wait for the common case. This is a follow-up.
- **CLI prompt on stdin instead of argv** (security). It is real, but it predates this work and affects every dictation. Its own PR.
- **Prompt-injection warning patterns in the preview, history retention, and onboarding card** (product, security). They are follow-ups. Fencing as data and never pressing Return cover the immediate risk.
- **Packet-level egress proof** (security). There is no command for it (tester). It is checked by hand with Little Snitch or `nettop` in local mode.
- **OCR fixtures are rendered, not captured.** Generating real screenshots needs Screen Recording permission this session cannot grant. The fixtures are rendered by a checked-in script at Terminal size (11 pt Menlo, dark, @2x, plus a JPEG-compressed variant). Real captures are checked by hand.

**Checked by hand** (no command can): the real tap swallows V in Terminal, Cursor and Slack; a real paste lands and the clipboard is restored; the consent notice appears once; a password manager's auto-clear survives; fn+V has no Globe action on this Mac's macOS.

TURN: tester

### tester · round 2

New objections. Each one is about a check the resolution added but did not give an outcome, or gave one that can be faked.
- **The consent gate is only checked by hand.** The part that matters is "no call before consent, asked again per provider", and a `RecordingGenerator` can check it. *Change:* move it into SmartPasteTests. Only the overlay copy stays a hand check.
- **`DatabaseTests` can pass on a fake.** The database stores whatever it is given, so the leak would be in the controller. *Change:* drive Smart Paste to a human destination with a restored secret, then read every history column.
- **"Never presses Return" and the concealed/transient fallback have no outcome.** *Change:* `Inserter` takes a key-event sink and a pasteboard, and InserterTests asserts both.
- **Nothing proves `test-class` can fail.** *Change:* add `make verify-test-class-can-fail`. It passes only if a missing class and a skipping canary both fail.
- **Generated OCR fixtures can be tuned to be easy.** *Change:* commit the PNGs. `verify-ocr` reads only the committed files and never regenerates them.
- **Lines 16 and 27 rest on `|| true`.** Once pipefail lands, re-run both and untick whichever fails.

**Done looks like**
- [x] PR 1: `make test` and every `verify-*` can fail — `make verify-test-can-fail`
- [x] PR 1: `test-class` fails on a missing class or a skip — `make verify-test-class-can-fail`
- [x] PR 1: V within 1.0 s converts for fn, Right Option and Right Command; extra ⌘/⌃, a late V and hands-free V are ignored; tap+V finishes; a bare tap is discarded — `make test-class C=HotkeyGestureTests`
- [x] PR 1: The corpus is caught, the known-miss list is exact, SHAs and UUIDs are kept, and bad nonce tokens fall back — `make test-class C=RedactorTests`
- [x] PR 1: Concealed, transient and auto-generated clips are refused; image+text gives text — `make test-class C=ClipboardReaderTests`
- [x] PR 1: Zero calls for silence, shell, local mode, over 20k characters and before consent; consent per provider; no corpus secret in a request; a guardrail failure inserts the clip — `make test-class C=SmartPasteTests`
- [x] PR 1: No restored secret in any history column, through the pipeline — `make test-class C=SmartPasteHistoryTests`
- [x] PR 1: No Return is posted; the fallback entry is concealed and transient — `make test-class C=InserterTests`
- [x] PR 1: The memory ceiling holds under pipefail — `make verify-memory`
- [x] PR 1: Release builds — `make release`
- [x] PR 2: Real Vision on committed fixtures finds the substrings, the O/0 key is redacted, and a blank image is empty — `make verify-ocr`
- [x] PR 2: The OCR block is fenced, verbatim and redacted; no OCR text appears in any request — `make test-class C=ScreenshotPromptTests`

TURN: lead

### lead · round 3

All six of tester's round-2 objections are accepted as written, and the 12 outcomes are now in `## Done looks like`. The rule for lines 16 and 27 is adopted: once pipefail lands, `make verify-stt` and `make verify-memory` are re-run, and either one is unticked if it fails. Product and security raised nothing that round 2 left open. The deferrals stand as listed in round 2.

PLAN FROZEN: 2026-10-23 — agreed by product, security, tester. Signed Vish (chat: "merge it and start building 1 and 2").

### UI/UX plan · 2026-10-23

The review is at [docs/research/uiux-plan-2026-10-23.md](docs/research/uiux-plan-2026-10-23.md): 29 findings, 6 quick wins (Q1–Q6) and 3 larger items (L1–L3). Its outcomes are the `UI/UX` lines in `## Done looks like`.

- **Already shipped.** L3 (mode chip, destination, the "what was sent" line, and the Smart Paste and screenshot states) landed with #5 and #6. So did the first half of Q1 (focus moved, preview expired and provider failures keep the text).
- **Order.** Q1 → Q6, then L1, then L2. Each is its own branch off the latest `dev` and its own PR.
- **Checks.** Each outcome has a test class that `make test-class` runs, failing on zero tests or a skip. The plan's grep checks are replaced, because a grep proves a word exists, not that the feature works.
- **Checked by hand, in plain words, by Vish:**
  - a VoiceOver pass over every overlay state;
  - a 20-line prompt read end to end in the preview;
  - destination edits surviving a row switch;
  - ⌘, opening the last pane;
  - History showing a Smart Paste with "Stayed on this Mac".
- **Open question carried over.** Which key clears a multi-line prompt in Claude Code's input. It is tested before the overlay names it, and not named until then.

PLAN FROZEN: 2026-10-23 — UI/UX section. Signed Vish (chat: "go").

### Decision · self-merge for the UI/UX and speed queues · accepted · Vish · 2026-10-23

Vish approved it in chat: "yes, self-merge". Each queued UI/UX and speed PR may be merged into `dev` by the session that built it, under these conditions:
- only after its tests and release build pass;
- by GitHub rebase merge;
- the branch is kept;
- never into `main`.

The rejected alternative was stacking each PR on the previous one until someone merged them by hand. The quick wins all touch the same overlay and controller files, so stacking six of them meant rebasing the whole stack after every merge, and any review comment early in the stack would ripple through the rest. Each stacked branch's tree was checked to be identical to the one that passed before it was merged.

### Speed plan · 2026-10-23

The review is at [docs/research/speed-plan-2026-10-23.md](docs/research/speed-plan-2026-10-23.md): 12 ranked speedups and a measurement plan. Its outcomes are the `Speed` lines in `## Done looks like`.

- **Measure first.** S0 lands before any speedup, with a "before" run of `make verify-latency` on the Release build. Every speedup PR then quotes before and after from the same harness: the median and p90, with how many runs.
- **What the harness measures, and what it does not.** It runs the real key-up path: post-roll, streaming stop, batch Parakeet, local compile and paste, on audio from `say`. It does not include the microphone, the hotkey or the speaker-to-microphone acoustic path. That end-to-end benchmark (`scripts/latency-bench.md`, after the Talkify method) needs the installed app and its permissions, so it is checked by hand by Vish.
- **Order.** S0, then S1a to S1e, then S2a and S2b. Each is its own branch off the latest `dev` and its own PR, self-merged per the decision above once its tests and release build pass. Speedups touching `Inserter.swift` or `DictationController.swift` go one after another, never in parallel.
- **Already done.** Item 11 (show the newest streamed words) landed in #11, and item 7's level cache in #9.
- **Not in this round.** Item 6 (the event tap off the main thread) touches AVAudioEngine's thread rules and needs its own investigation. Item 9 (Haiku 5.5) needs the 40-case golden set to judge quality. Item 12's bigger bets are left as written.

PLAN FROZEN: 2026-10-23 — speed section. Signed Vish (chat: "go ahead with the speedups too").

### Edit selection by voice · 2026-10-23

Research idea #1, "speak-to-transform the selection". Select text in any app, hold the trigger, press **R** within a second, and say what to do: "shorter", "make it a bug report", "reply no politely". The usual preview appears. Return replaces the selection, Escape leaves it untouched, and ⌘Z in the app restores it.

- **The gesture.** R, for rewrite, mirrors V for Smart Paste: the same one-second window, the same modifier rules, and only one per hold. Apple's shortcut list (support.apple.com/102650, read 2026-10-23) gives fn with A, C, D, E, H, N, Q and Shift-A, and no fn-R, so it does not collide with the system either. Holding Shift or Control with the trigger stays verbatim or full compile, so a modifier gesture would have collided with those.
- **Reading the selection.** Accessibility's selected text first. If an app does not expose it, a ⌘C is sent and the clipboard is put back afterwards. Secure input and concealed copies are refused.
- **The pipeline is Smart Paste's.** The selection is the clip, and what you said is the instruction. It shares consent per provider, on-device redaction of known secret shapes, the numbers check, "You said: …", the source line, History storing only the redacted form, and never losing text. Silence is refused with a next step, because an edit needs an instruction. Terminals are refused, because replacing a selection there is not reliable.
- **Checked by hand:** that Return replaces the selection and ⌘Z restores it in Notes, Slack and Mail; that an app without Accessibility selection (a browser text area) falls back to ⌘C and the clipboard comes back.

PLAN FROZEN: 2026-10-23 — edit selection section. Signed Vish (chat: "start both, alarm first then edit selected text by voice").

### UI v2, "Island and Card" · 2026-10-23

The spec is Concept A in [docs/research/ui-concepts-2026-10-23.md](docs/research/ui-concepts-2026-10-23.md): §3 gives the sizes, motion and copy, and §4 the build order. The mockup's v2 row is the visual reference Vish approved.

- **Order, one PR each:**
  1. the capsule and its state copy;
  2. the card, with cached levels and ⇧⇥ kept;
  3. notch lobes with the free-capsule fallback;
  4. History rows and keys;
  5. the glass surface with the material fallback;
  6. the menu bar icon.
- **Rules:**
  - no fake precision;
  - every empty or failed state names the cause and offers an action;
  - no jargon;
  - never a drawn notch. The notch is read from `NSScreen.auxiliaryTopLeftArea`, `auxiliaryTopRightArea` and `safeAreaInsets`, and a display without them gets the free capsule.
- **Limit of this Mac.** It runs macOS 15.2 with the macOS 15.4 SDK, so the Liquid Glass path (macOS 26 APIs) can be neither compiled nor seen here. Step 5 builds the fallback and gates the glass path on the compiler. The glass itself is checked by hand on a macOS 26 Mac.
- **Checked by hand:**
  - the capsule and the card on a notched MacBook and on an external display;
  - Reduce Motion, Reduce Transparency and Increase Contrast;
  - that nothing covers the Dock, a Send button or menu bar items.
- **Sequencing.** This follows the finished speed plan, so no speed work touches these files at the same time.

PLAN FROZEN: 2026-10-23 — UI v2 section. Signed Vish (chat: "self-merge and build the v2 UI").

### Chassis tap trigger · 2026-10-23

An optional second trigger: double-tap the palm rest beside the trackpad and recording starts hands-free. fn stays the main trigger. This one is off by default.

- **The sensor.** Apple Silicon MacBooks from the M2 on have a motion sensor behind `AppleSPUHIDDevice`: vendor page 0xFF00, usage 3, 22-byte reports with x/y/z as little-endian Int32 at offsets 6, 10 and 14, in 1/65536 g. It is undocumented, read with public IOKit calls.
- **The probe, on this Mac (Mac14,7, macOS 15.2).** A separate hardened app with no grants opened the device (`IOHIDDeviceOpen` returned 0). It read 2,395 reports in 3 s, about 1 g at rest, with Input Monitoring and Accessibility both off. **No new permission.** Opened alone, the device sends nothing; the driver must first be told to report, to power on and at what interval (`SensorPropertyReportingState`, `SensorPropertyPowerState`, `ReportInterval`), as every reference does. Those writes are what Vish allowed. On macOS 15.2 the drivers have no `Product` name, so the accelerometer's driver is matched by usage 3.
- **Steps, one PR each:**
  1. the sensor, gated on the device existing;
  2. the detector, with recorded samples and a recorder;
  3. the gesture, the setting and the power rules;
  4. the README section, held until the LinkedIn post is out (2026-10-24, 10:00 PT).
- **The gesture.** A double tap (two knocks 80–450 ms apart) is a new `chassisTap` event in `HotkeyGesture` that behaves like a toggle-mode press: from idle it starts a hands-free capture, and while hands-free it ends it. `DictationController` does not change how it records. Either side counts the same, because left and right are not reliably told apart. Stopping is a second double tap, the trigger key, Escape or the silence timeout. A single tap does nothing, because setting the Mac down looks like one.
- **False triggers.** A knock within 0.4 s of a key press or a click is ignored, using the event tap the app already runs. A knock that rings long, or that comes with a change in the direction of gravity, means the Mac was moved, and is ignored. So is a third knock close behind a double, which is a burst rather than a gesture.
- **Cost and power.** Sampling only while the setting is on and the app isn't paused; 100 Hz while quiet, 800 Hz for 2 s after movement; stopped on screen lock, display sleep and battery under 10%. Target under 1% of a core idle, measured.
- **Never the microphone.** The microphone is not used to detect knocks: it records only while you dictate.
- **Credit.** The approach follows MIT-licensed work: yu2001-s/TapTap (`SPUSensor.swift`) and mohammaddanyal/dott-tap (`KnockDetector.swift`: 13 Hz high-pass, adaptive floor, echo guard, idle rate). Credited in the file headers and NOTICE. The code is written here, not copied.
- **Checked by hand:** double taps on both sides of the palm rest start and stop; typing fast, clicking, closing the lid and setting the Mac down do not.

PLAN FROZEN: 2026-10-23 — chassis tap section. Signed Vish (chat: "allow the sensor property writes, run the probe, then build").

### Home window · 2026-10-24

Vish: "The UI still looks really basic… It's all black. There's no like actual UI. It like just looks like it's normal setting page." He wants a saved list in the style of Wispr Flow, where he can see what he just said and copy it easily. The mockup he approved ("go ahead") is https://claude.ai/artifact/M2Fp1D1r2sWYeq2TkF6U2t: two screens, light and dark.

- **One window.** Sidebar: Home, History, Dictionary, Settings, and a footer "fn hold, or double-tap the palm rest". At least 1040×700, resizable. It opens from the menu and ⌘Y, and replaces the History window.
- **Theme.** Follows the Mac unless Settings → Appearance says Light or Dark. The type is SF Pro; the mockup's Inter is for the web only. Never pure black.
  - Light: background #FAF8F5, sidebar #F3F0EA, cards #FFFFFF, lines #E7E2DA, ink #1C1B1A, muted #6B6660.
  - Dark: background #1A1918, sidebar #151413, cards #242322, lines #34322F, ink #F2F0ED, muted #A8A39C.
  - One accent: #4B5BDC.
- **Cards.** Each card shows:
  - the time, the app and the mode (Dictate, Smart paste, Edit by voice, Screenshot fix);
  - "Stayed on this Mac" (green) or "Sent to Claude" (blue), from the stored provider. Old rows that never recorded a provider say "Not recorded".
  - the polished text, and Copy, which says "Copied" for 1.4 s;
  - "What you said", with its own Copy;
  - pin (pinned cards come first, with an accent border) and delete.
- **New columns.** The app name, the mode and pinned: migration v3. Older rows get their mode from the stored level and their destination as their app.
- **Home and History.** Home counts today from real rows only (dictations, words, stayed on this Mac) and shows today's four most recent. History searches the text, what was said, the app and the mode, groups by Today, Yesterday and dates, and says "Nothing matches “x”. Try an app name, like Slack." when nothing matches. Return on a selected row still pastes again (v2 step 4).
- **Dictionary.** There is no list of words the user can edit today. Dictionary shows the words from the current repo, read-only, and says so; no store is invented.
- **Settings as cards:**
  - How you start talking: the trigger and the palm-rest switch.
  - Where the rewrite runs: three rows that set the existing provider policy's compile path. "On this Mac" sets both paths.
  - What can leave this Mac: audio never; screenshot images never; your words "Nothing leaves" when everything is on this Mac, otherwise "Only when a rewrite needs it".
  - Appearance and history retention.
  - "More settings…" opens the existing window, for destinations, API key and consent, which these cards don't replace.
- **Retention.** 30, 60 or 90 days, or Forever.
  - Pinned items are never pruned; Forever never deletes.
  - Pruning runs at launch and once a day, on the local SQLite only.
  - A shorter period confirms first with the real count ("This removes 212 items older than 30 days").
  - This install defaults to Forever, since it already has history; a new install defaults to 90 days.
  - The database's size is shown under the control.
- **Order, one PR each:** the window, sidebar and theme; the cards; Dictionary and the Settings cards; retention. Each screen gets light and dark snapshots. The README images wait for the LinkedIn post.

PLAN FROZEN: 2026-10-24 — Home window section. Signed Vish (chat, relayed by the leader session after he reviewed the mockup: "go ahead").

