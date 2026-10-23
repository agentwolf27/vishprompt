# Visprflow

<!-- pulse -->

## What we are building
Visprflow is a native macOS menu bar app that takes over the fn key (once macOS's emoji picker on that key is set to Do Nothing) for a full dictation-to-prompt pipeline: hold fn, talk, release, and the app transcribes on-device with Parakeet v3, then compiles the raw speech into the best-suited prompt for wherever the cursor is (Claude Code, Cursor, claude.ai, Slack, email, or a plain shell), inserting it with a preview step for agent destinations.

## Why
Existing dictation tools like Wispr Flow are cloud-only, heavy (800 MB idle), unreliable, and produce generic cleaned-up text rather than a structured prompt tailored to the destination app and its context.

## Done looks like
A short list of concrete, checkable outcomes. If you cannot check it, it does not belong here.
Tick one only when its VERIFY passes, not when someone says it is done.

- [x] Menu bar app with permission onboarding, Keychain, timing, local SQLite history — `ls ~/Applications/Visprflow.app`
- [x] Hold-to-talk loop with on-device Parakeet v3 transcription and paste-back — `make verify-stt`
- [x] Prompt compiler with destination detection, guardrails, raw fallback — `make test`
- [x] Repository vocabulary and workspace context harvesting — `make test`
- [x] The unit test suite passes (README cites 177; not independently counted) — `make test`
- [x] Audit fixes: crash trap, Right-Option key mapping, clipboard restore, probe hang — `test -f Visprflow/Core/Audio/ObjCException.m`
- [x] Live streaming transcript preview while speaking — `test -f Visprflow/Core/STT/StreamingTranscriber.swift`
- [-] Streamed transcript replaces the batch model — evaluated in 14f55cf and declined: accuracy wins a trade that costs 80 ms
- [x] Now-tier latency fixes: pre-roll, post-roll, warm-up, exception trapping — `grep -q postRollDuration Visprflow/Core/Audio/AudioCapture.swift`
- [x] Next-tier robustness: device/wake recovery, pinned paste target, hung CLI handling — `grep -q observeDeviceChanges Visprflow/Core/Audio/AudioCapture.swift`
- [x] Second audit sweep: overlay retain cycle, timer run-loop modes, tap port, preview lifetime — `grep -q "HUDHost(box:" Visprflow/Core/Pipeline/DictationController.swift`
- [x] The streaming model is released when idle, so its 580 MB comes back — `grep -q idleLifetime Visprflow/Core/STT/StreamingTranscriber.swift`
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
- [ ] PR 2: Real Vision on committed fixtures finds the substrings, the O/0 key is redacted, and a blank image is empty — `make verify-ocr`
- [ ] PR 2: The OCR block is fenced, verbatim and redacted; no OCR text appears in any request — `make test-class C=ScreenshotPromptTests`

## Later

From plan.html's phases 3–5. docs/roadmap.html supersedes that plan and, with its twelve items shipped or declined, queues none of these yet.

- [ ] Groq added as a faster rewrite provider — `grep -rq GroqGenerator Visprflow/Core/Compile`
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
- On-device provider behind `TextGenerating` — `grep -rq FoundationModelsGenerator Visprflow/Core/Compile`
- History window — `grep -rq HistoryView Visprflow/UI`
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
- **Agent destinations.** The OCR text is redacted and given to the model as context. The model compiles only the spoken ask; vocabulary is repo + OCR text. Visprflow then appends the OCR text itself, verbatim, as a block: `Screenshot text (on-device OCR, secrets removed):`. The error text is never rewritten by a model. Silence gives the block alone.
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

- **`make test` (SomeClassTests) only checks that nothing failed.** Delete the class, rename it, or `XCTSkip` it, and the line still goes green. *Change:* add `make test-class C=<Class>`. It runs `-only-testing:VisprflowTests/<Class>` and fails on zero tests executed, on any skip, or on any failure.
- **Pipefail needs proof that it can fail.** Grepping the Makefile for `pipefail` proves nothing. *Change:* add `make verify-test-can-fail`. It runs a canary `XCTFail` (gated by `TEST_RUNNER_VISPRFLOW_CANARY=1`) and succeeds only if xcodebuild exits non-zero. `verify-*` ends in `|| true` too, so line 27's tick on `make verify-memory` has proved nothing so far. Every `verify-*` target needs the same fix.
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
- **Feature B: the OCR text never reaches the rewrite model** (security). It joins the guardrail's known words, so the spoken ask may name a file from the error. The model sees only the spoken ask and the repo vocabulary. Visprflow appends the OCR text, redacted and fenced as "data, not instructions", and the preview shows it before Return.
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
- [ ] PR 1: `make test` and every `verify-*` can fail — `make verify-test-can-fail`
- [ ] PR 1: `test-class` fails on a missing class or a skip — `make verify-test-class-can-fail`
- [ ] PR 1: V within 1.0 s converts for fn, Right Option and Right Command; extra ⌘/⌃, a late V and hands-free V are ignored; tap+V finishes; a bare tap is discarded — `make test-class C=HotkeyGestureTests`
- [ ] PR 1: The corpus is caught, the known-miss list is exact, SHAs and UUIDs are kept, and bad nonce tokens fall back — `make test-class C=RedactorTests`
- [ ] PR 1: Concealed, transient and auto-generated clips are refused; image+text gives text — `make test-class C=ClipboardReaderTests`
- [ ] PR 1: Zero calls for silence, shell, local mode, over 20k characters and before consent; consent per provider; no corpus secret in a request; a guardrail failure inserts the clip — `make test-class C=SmartPasteTests`
- [ ] PR 1: No restored secret in any history column, through the pipeline — `make test-class C=SmartPasteHistoryTests`
- [ ] PR 1: No Return is posted; the fallback entry is concealed and transient — `make test-class C=InserterTests`
- [ ] PR 1: The memory ceiling holds under pipefail — `make verify-memory`
- [ ] PR 1: Release builds — `make release`
- [ ] PR 2: Real Vision on committed fixtures finds the substrings, the O/0 key is redacted, and a blank image is empty — `make verify-ocr`
- [ ] PR 2: The OCR block is fenced, verbatim and redacted; no OCR text appears in any request — `make test-class C=ScreenshotPromptTests`

TURN: lead

### lead · round 3

All six of tester's round-2 objections are accepted as written, and the 12 outcomes are now in `## Done looks like`. The rule for lines 16 and 27 is adopted: once pipefail lands, `make verify-stt` and `make verify-memory` are re-run, and either one is unticked if it fails. Product and security raised nothing that round 2 left open. The deferrals stand as listed in round 2.

PLAN FROZEN: 2026-10-23 — agreed by product, security, tester. Signed Vish (chat: "merge it and start building 1 and 2").
