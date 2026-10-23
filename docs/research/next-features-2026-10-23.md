# Visprflow: what to build next (research and plan, 2026-10-23)

This is research and planning only: no app code was changed, and every web source was accessed on 2026-10-23. Anything without a source is marked **UNVERIFIED**. Facts about Visprflow come from this repository on `dev` (last commit e181842, 2026-09-08): README.md, PLAN.md, docs/plan.html, docs/roadmap.html, docs/build-report.html and the Swift sources. Many third-party pages are written by competing dictation vendors; those are tagged **[competitor]**. Reddit could not be read directly, so Reddit-derived points are secondhand.

**Spot-check, 2026-10-23.** Before saving, the following claims were rechecked against the repo and their cited sources. Two were corrected.
- **Confirmed:** 8 built-in destinations (`Destination.swift`); `kAXSelectedText` used only for inserting (`Inserter.swift:92`); `requestJSON` stored per dictation (`Database.swift:51`); no LICENSE file and `license: null` on GitHub; FluidAudio latest release v0.17.7 (2026-10-08); Handy 34.4k stars, MIT; Wispr Pro $15/mo or $12/mo annually with 2,000 free words/week on desktop [W5]; Command Mode is paid-only [W4].
- **Corrected:** the Talkify benchmark page names a MacBook Pro but not the chip, so "M4 Max" is removed. Its numbers include the speaker-to-microphone acoustic path [L1].
- **Corrected:** FluidAudio's vocabulary-boosting doc now shows the *batch* `AsrManager.transcribe(_:customVocabulary:)`, not only streaming managers [G4]. That removes the reason roadmap item 12 was declined. It is still UNVERIFIED that the shipped v0.17.7 tag includes it, until it is built against.
- **Added:** Wispr also has a Growth tier, $23/mo or $18/mo annually [W5]. Snippets (idea 12) are listed under *Out of scope* in `PLAN.md`, so building them needs that line revisited first.

---

## One-screen summary

**1. The field caught up on "context" in the six weeks since Visprflow's roadmap closed.**
- **Selection, clipboard and screen OCR context** are now standard in other apps: VoiceInk [V1], superwhisper [S1] and Raycast [R1][R2].
- **Speaking an edit over selected text** is offered by Wispr (Command Mode, Fn+Ctrl) [W4], Aqua (Edit Mode) [O4], VoiceInk [V1], Typeless [O6], FluidVoice [O1] and OpenWhispr [G1].
- **Coding agents:** superwhisper lets Claude Code or Codex ask you questions by voice [S4]. Monologue turns speech into coding-agent prompts [O5]. Claude Code ships its own `/voice`, but it streams audio to Anthropic and inserts the transcript verbatim [C1].
- **Funding:** Wispr Flow raised $280M at a $2B valuation in Aug 2026 and launched its own speech model, Canto [W1][W6].

**2. What only Visprflow has (no competitor found offers it):**
- **(a) Measured on-device speed.** Speech is transcribed on the Neural Engine at 40 MB idle; 14.1 s of speech takes 208 ms (repo-measured). Wispr is cloud-only [W7].
- **(b) Structured prompts for agents.** It compiles to a structured agent prompt using repo vocabulary, a preview, and guardrails that keep out anything you did not say.
- **(c) A record of what was sent.** Each request that left the Mac is stored per dictation. No competitor found offers (c).

**3. Pastly is Pastely, at pastely.click.** Vish confirmed the product on 2026-10-23 [PA0]. No Mac productivity tool is named exactly "Pastly".
- **Pastely ("AI Smart Paste"):** a menu-bar app. Copy as usual, press ⌘⇧V, and the clip is reformatted for the app, window and browser tab you are in, with no per-app setup. Text you type in the field first is taken as an instruction ("turn this into bullet points"). Return pastes the preview and Esc cancels. ⌘⇧H searches past transforms. It takes text and images (screenshots, receipts) and runs on macOS 13+, Apple silicon and Intel; Windows has a waitlist. Free gives 4 transforms; Pro is $9/mo for 500 transforms a month, or $49/yr. It needs a Google sign-in. The page does not say which model runs or whether processing is local, so treat it as **cloud, UNVERIFIED** [PA0].
- Other apps with similar names:
- **Pasly:** a local clipboard manager with no AI, $9.99 one-time [PA2].
- **Pastily:** an offline clipboard manager, $8.99–14.99 one-time [PA3].
- "Clipboard Manager – Pastely" is a sync clipboard app [PA3]. Two MIT-licensed GitHub clipboard managers are also called Pastely [PA6]. None of these is the one Vish saw.
- The earlier directory listing [PA1] had Pastely's Pro at $20/mo. Its own site says $9/mo, so the listing is superseded.

**4. Is Visprflow + Pastely a sharper product?** Not as a clipboard manager. That space is crowded:
- Maccy has 22k stars and is MIT-licensed [G1].
- Paste 7 adds an on-device "Intelligent Clipboard" and a clipboard MCP [PA4].
- Raycast has "Ask Clipboard" AI search [R3].
- Apple Spotlight clipboard history arrived in Tahoe [A1].

The sharp combination applies Visprflow's destination-aware compiler to the clipboard: **"paste it right"** (Pastely's idea, but on-device and repo-aware), plus a **clipboard history you can reference by voice**. One survey found no product that combines clipboard history with speaking a command to transform a past clip [F1]; superwhisper users have asked for something close to it [F2].

**5. Top 3 to build (2–4 weeks):**
- **R1 — Speak-to-transform and Smart Paste:** selection, clipboard memory, and destination-aware paste, with on-device secret redaction.
- **R2 — "Nothing leaves, proven":** an offline rewrite on Apple Foundation Models, a visible privacy ledger, and an egress test that fails the build.
- **R3 — Public eval and latency harness:** grow the golden set from 8 to 40, and re-run the Talkify-style latency benchmark independently [L1]. This is the strongest AI/FDE portfolio artefact.

**6. Housekeeping:**
- The public repo `agentwolf27/visprflow` had **no licence** (GitHub API: `license: null`, 0 stars, last push 2026-09-09). An MIT `LICENSE` was added in the same PR as this doc.
- FluidAudio is now at v0.17.7 with a CTC vocabulary-boosting path that pairs with Parakeet v2/v3 [G1]. Its current docs show it on the batch `AsrManager` [G4], which reopens roadmap item 12 (declined on 0.15.6 because only streaming managers had it). Whether the v0.17.7 tag ships the batch path is UNVERIFIED until built.
- The roadmap's competitor latency table *is* sourced, but the benchmark was run by Talkify's own developer [L1].

---

## 1. What Visprflow is today (from the repo, `dev`)

| Area | Built | Not built |
|---|---|---|
| Trigger | Hold fn or Right Option; double-tap for hands-free; Escape cancels; shift = verbatim, control = full compile; a bad-trigger-key guard | — |
| Speech | Parakeet v3 via FluidAudio 0.15.6 on the Neural Engine. 14.1 s of speech in 208 ms (~68× realtime). Live streaming preview in the overlay; the final text comes from the batch model. The streaming model unloads after 10 min idle | Acoustic vocabulary boosting (roadmap item 12, declined on 0.15.6) |
| Memory | Idle memory went from 1,251 MB to 40 MB after moving the encoder from the GPU to the Neural Engine. `make verify-memory` fails the build above 300 MB | — |
| Rewrite | Three providers. Local rules (`LocalCleanup.swift`). Claude subscription via the `claude` CLI: 3 s to the first word, 6–10 s total. Anthropic API key: 0.7 s / 1–2 s, about $0.002 each | Groq; an on-device LLM |
| Destinations | 8: Claude Code, Cursor, Codex, chat, message, email, document, shell. Each has a level, a preview flag, auto-submit, a free-text instruction and a word threshold (`Destination.swift`) | — |
| Levels | verbatim / light / organised / compiled; Tab cycles them in the preview | — |
| Context | Frontmost app; window title (AX); browser URL (osascript); terminal foreground process, cwd, git branch and changed files; up to 300 repo identifiers as vocabulary | **Selected text, clipboard and screen OCR are planned but not coded.** `kAXSelectedText` is only used for *inserting* (`Inserter.swift:92`) |
| Insert | AX set-selected-text where settable, otherwise paste with a read-receipt clipboard restore. The paste target is pinned at record start. Secure input is blocked and the text goes to the clipboard instead | — |
| Storage | GRDB SQLite: raw transcript, compiled text, the exact `requestJSON` sent, stage timings | **No history UI**, no snippets, no prompt library |
| Quality | 177 unit tests (README), `make verify-stt`, 8 golden fixtures (the target is 40) | A 40-case golden set |
| Distribution | Release build in ~/Applications; ad-hoc or self-signed | Notarisation, Sparkle, a licence |

---

## 2. Comparison table

Legend: Y = yes, N = no, P = partial.

| | **Visprflow** | **Wispr Flow** | **Pastely (AI)** | **superwhisper** | **VoiceInk** | **Raycast** | **Claude Code /voice** |
|---|---|---|---|---|---|---|---|
| Category | Dictation that compiles prompts | Cloud AI dictation | AI clipboard reformatter | Dictation with modes | Open-source dictation | Launcher + AI + dictation + clipboard | Built-in agent dictation |
| Where speech runs | On-device (Neural Engine) | Cloud only [W7] | n/a | Local Whisper or cloud; own S1 models (Aug 2026) [S2][S5] | Local (whisper.cpp, Parakeet) [V1] | Cloud per a competitor [R4] **[competitor]** | Cloud (Anthropic) [C1] |
| LLM rewrite | Local rules / Claude subscription / API | Yes, cloud | Yes; model and location not stated, Google sign-in required [PA0] | Yes, custom prompts per mode [S1] | Yes, Power Mode; Ollama keeps it offline [V1][V3] | Yes, Styles + custom instructions [R1] | No, verbatim [C1] |
| Per-app behaviour | 8 destinations, each with a free-text instruction | Styles (English, desktop only) [W2] | Reads app, window and browser tab; no per-app setup [PA0] | Modes switch per app [S2] | Power Mode per app or URL [V3] | Auto Styling [R1] | Claude Code only |
| Selected text as context | **N (planned)** | Y [W8] | n/a | Y [S1] | Y [V1] | Y [R2] | N |
| Clipboard as context | **N (planned)** | UNVERIFIED | Y, current clip, read only when the hotkey is pressed [PA0] | Current clip, copied ≤3 s before or during [S1] | Clip at start [V1] | History + "Ask Clipboard" [R3] | N |
| Screen context | **N (planned OCR)** | Accessibility text; "does not take screenshots" now; earlier screenshot controversy [W8][P1] | Screenshots in the clip, not the screen [PA0] | Window text [S1] | Window OCR (Vision) [V1] | Screen Awareness [R1] | N |
| Speak an edit over the selection | **N** | Y, paid only [W4] | Typed instruction in the target field [PA0] | Y [S1] | Y [V1] | AI Commands (typed) [R2] | N |
| Code / agent awareness | Y: cwd, branch, 300 repo identifiers, structured agent prompt | Cursor/Windsurf file tagging [W2] | Converts code to the file's language [PA0] | Agents ask you questions by voice [S4] | N | N | Project name + branch as hints [C1] |
| Dictionary / snippets | Repo vocabulary only | Y, learns from your corrections [W2] | n/a | Y | Y | Vocabulary [R1] | N |
| History UI | N (SQLite only) | Y, local [W9] | Y, transform history; synced across Macs on Pro [PA0] | UNVERIFIED | UNVERIFIED | Y [R1] | N |
| Shows what was sent | **Y, stored per dictation** | N | N | N | N | N | N |
| Platforms | macOS 15+, Apple Silicon | Mac, Windows, iOS, Android [W1] | macOS 13+, Apple silicon and Intel; Windows waitlist [PA0] | Mac | macOS 14.4+ [V1] | Mac, Windows | Any terminal [C1] |
| Price | Free (private build) | Free tier 2,000 words/week (desktop); Pro $15/mo or $12/mo billed annually; Growth $23/mo or $18/mo [W5] | 4 free transforms; Pro $9/mo (500/mo) or $49/yr [PA0] | Pro ~$8.49/mo [S3] **[competitor]**; lifetime price disputed | $25–49 lifetime, or build from source [V1] | Pro $10/mo [R5] | Included [C1] |
| Licence | MIT (added 2026-10-23) | Closed | Closed | Closed (S1-mini weights are open) [S5] | GPL-3.0 [G1] | Closed | Closed |

Other products and models worth knowing:

**Open source**
- **Handy:** 34.4k stars, MIT. Whisper + Parakeet V3, Silero VAD, history, "Reliable Paste" [G1][G2].
- **OpenWhispr:** 9.8k stars, MIT. Local Parakeet/Whisper plus llama.cpp; edits highlighted text in place; has an MCP server [G1].
- **FluidVoice:** 12.4k stars, GPL-3.0. Write Mode rewrites selected text [G1].

**Commercial apps**
- **Aqua Voice** (cloud Avalon model): Edit Mode; "Deep Context" takes one screenshot; `@file` tags; Pro $10/mo [O4].
- **Monologue** (Every): spoken descriptions become coding-agent prompts; MCP; Pro $15/mo [O5].
- **Spokenly:** agents can ask you for spoken answers; Local Only Mode [O3].
- **Typeless:** voice edits on a selection; 8,000 free words/week [O6].
- **TalkBoard** and **Pipit:** dictation plus clipboard history, but no voice transform of past clips [F1].

**Talkify**
- Uses SpeechAnalyzer and Apple's on-device model; macOS 26 [L1].
- Its own benchmark: Talkify 123 ms, Spokenly 189, superwhisper 216, VoiceInk 324, Wispr 587, Aqua 630, MacWhisper 1,149. Median of 20 trials on a MacBook Pro (chip not stated); audio is played through speakers into the mic, so the acoustic path is included [L1].

**Apple**
- Spotlight clipboard history; macOS 26.1 added 30 min / 8 h / 7 day retention [A1][A2].
- Writing Tools rewrite a selection system-wide [A6].
- SpeechAnalyzer: on-device speech-to-text API, macOS 26 [A3].
- Foundation Models: about 3B parameters (secondhand); a 4,096-token window shared between input and output, unchanged at WWDC26; guided generation; tool calling [A4][A5].

### What users say about Wispr Flow
- **Praise:**
  - App Store rating is 4.8 from about 18K ratings [W10].
  - HN commenters call it "magical" and say it helps people with mobility issues [H1].
  - The AI cleanup drops self-corrections [W2].
- **Price:** HN calls it "a bit pricey". A Show HN for the free alternative FreeFlow got 277 points [H1][H2].
- **Quality drift (Oct 2026):** HN commenters say it "has been degraded recently" and suspect cost-cutting on inference [H1]. Anecdotal.
- **Privacy:**
  - In 2025 it was reported to upload active-window screenshots. The user who raised it was reportedly banned, and the CTO later apologised [P1][P2] **[competitor]**. The original thread was not found, so the details are UNVERIFIED.
  - An April 2026 forensic write-up of the Mac app 1.4.752 [H3] found:
    - foreground app and URL logging;
    - Chrome accessibility-tree walks up to 214 elements deep;
    - a 694 MB local database;
    - hourly metadata uploads even with sharing off;
    - four analytics services.
  - Wikipedia says the app can read keystrokes [W1].
- **Weight:** about 800 MB RAM and 8% CPU on Windows Electron [P3] **[competitor]**, secondhand. Close to 1 GB during Notetaker recording [P4] **[competitor]**.
- **Reliability:**
  - It re-adds itself to login items [P5].
  - It freezes VS Code and Notepad++ on Windows [P6] **[competitor]**.
  - On mobile, the mic stays live and drains the battery [W10].
- **Over-editing or hallucination:** no sourced complaint found. UNVERIFIED as a theme.

---

## 3. Ranked idea list

Scores: Value and Differentiation are H, M or L. Effort: S ≤ 2 days, M ≤ 1 week, L > 1 week. Risk covers privacy, Apple APIs and licensing.

| # | Idea | Value | Diff. | Effort | Risk | Notes |
|---|---|---|---|---|---|---|
| 1 | **Speak-to-transform the selection**: select text, hold trigger + modifier, say "shorter", "bug report from this" or "reply no politely"; the result replaces the selection after the preview | H | L–M (6+ apps have it) | M | AX selection read fails in some Electron apps and terminals; fall back to ⌘C with restore | Table stakes, and it enables #2 and #3. Visprflow's edge is the preview plus Tab levels plus guardrails |
| 2 | **Smart Paste (Pastely-style, on-device)**: trigger + V, or "paste this as…", compiles the *clipboard* for the destination with the same Destination model (CSV → Slack table, stack trace → Claude Code bug prompt with repo vocabulary, URL → Markdown link) | H | **H**: Pastely needs a Google sign-in and a monthly quota, does not say where its model runs, has no voice and no repo awareness [PA0]; Pastr and apfel-clip are on-device but not destination-aware [G1][PA5] | S–M | Low: reuses the compiler and inserter | The cleanest "Visprflow + Pastely" mix, since the compiler already exists |
| 3 | **Clipboard memory you can reference by voice**: a local, encrypted history of the last 200 text clips that skips concealed and transient types. Speech can point at it: "the Figma link I copied", "my last three copies", "the error I copied" | H | **H**: no product found does voice transforms over clipboard *history* [F1][F2]; Raycast Ask Clipboard is a typed search [R3] | M | The clipboard holds secrets: honour `org.nspasteboard.ConcealedType`, exclude password managers, encrypt at rest, redact (#4) | The "memory" half of the mix |
| 4 | **On-device secret redaction** before any provider call (API keys, JWTs, AWS keys, high-entropy strings), shown in the preview and the ledger | M | H | S | False positives on identifiers; tune on the golden set | Makes #2, #3 and #8 safe; cheap |
| 5 | **Fully offline rewrite** with Apple Foundation Models (macOS 26) for light and organised; cloud stays opt-in for "compiled" | H | M (Talkify, apfel-clip and Blitztext use it [L1][G1]; VoiceInk can use Ollama) | M | Needs macOS 26 and Apple Intelligence turned on; 4,096-token window [A4]; quality vs Haiku unknown | An opt-in tier keeps the macOS 15 floor |
| 6 | **Privacy ledger UI + egress test**: a history window showing raw text → sent request → output → timings, plus `make verify-egress` that fails if any non-loopback host other than the chosen provider is contacted | M | **H**: directly answers the Wispr forensics [H3] | S–M | Low | The data is already in SQLite (`requestJSON`) |
| 7 | **Public eval + latency harness**: 40 golden cases; LLM-judge, guardrail and "unspoken content" metrics per level and provider; `say`-generated audio; end-of-speech → text-in-field timing, re-running Talkify's method [L1] | M (users) / **H (portfolio)** | H | M | Benchmarking ToS for competitors UNVERIFIED; publish the method and raw CSVs | Turns a vendor-run benchmark into an independent one |
| 8 | **Terminal scrollback as context**: "use the failing test output" pulls the last N lines from the Terminal or iTerm AX text into a Claude Code prompt | H for devs | H (no competitor found) | M | Secrets in scrollback, so it needs #4; AX text differs by terminal | Beats Claude Code `/voice` on its home turf |
| 9 | **Visprflow MCP server**: `history.search`, `clipboard.recall`, `ask_user_by_voice` | M | M (superwhisper, Spokenly, OpenWhispr, Aqua and Monologue have agent or MCP hooks [S4][O3][G1][O4][O5]) | M | Localhost only; auth | Good demo but not novel any more |
| 10 | **Acoustic vocabulary boosting** via FluidAudio ≥0.17's CTC word-spotter alongside Parakeet v3, fed by the existing repo vocabulary [G1][G4] | H for tech terms | M–H (per-repo acoustic boosting not found elsewhere) | M | Dependency bump; extra 97.5 MB CTC encoder, ~130 MB peak, ~26× realtime [G4]; must stay under `make verify-memory`'s 300 MB; accuracy vs today unknown | Reopens roadmap item 12, now that the batch engine has it per docs; needs #7 to judge |
| 11 | **Dictionary learned from preview edits only** (words changed before Return become vocabulary); no keystroke watching outside the preview | M | L | S–M | Avoids Wispr's keystroke issue by design [W1] | |
| 12 | **Snippets with spoken triggers and variables**, plus "save as snippet" from history | M | L | S | Low; but listed as out of scope in `PLAN.md` | Parity with Wispr, Raycast and the clipboard apps |
| 13 | **"Include the error / screen"**: on-demand window OCR via ScreenCaptureKit + Vision, text only | M | L (VoiceInk, Raycast and Aqua have it) | M | Screen Recording permission; periodic re-consent prompts UNVERIFIED | Planned in plan.html |
| 14 | **SpeechAnalyzer as a second engine**, A/B tested in the harness | L–M | L | M | macOS 26 only | Content for the harness, not a product feature |
| 15 | **Multilingual**: Parakeet v3 covers 25 European languages with auto-detect [G3]; add a per-destination language hint | M | L | S | Rewrite prompts are English-tuned | Cheap reach |
| 16 | **Licence (MIT, done 2026-10-23); notarisation + Sparkle later** | H for adoption | L | S / M | Developer ID costs about $99/yr (UNVERIFIED), against the $0 rule | The licence is free and urgent for a public portfolio repo |
| 17 | Meeting notes / iOS / Windows | L for this goal | L | L | Large surface | Out of scope per PLAN |

### Pastely, part by part

Almost every Pastely part already exists in Visprflow, built for speech rather than for the clipboard:

| Pastely [PA0] | Visprflow today |
|---|---|
| Reads the app, window and tab | `FocusContextProvider` and `DestinationResolver`, plus terminal process, cwd and git |
| Reformats for the destination | `Compiler` with per-destination level and instruction |
| Preview: Return pastes, Esc cancels | The same preview, plus Tab to change level |
| Transform history | `requestJSON` and output stored per dictation, with no UI yet |
| Instruction typed in the field | Instruction spoken, and never executed as a command |
| Google sign-in, quota, cloud (UNVERIFIED) | No account and no quota; local, subscription or API key |

Smart Paste is therefore mostly a new *input* (the clipboard) into a pipeline that already exists. That makes it small (S–M) and a direct, measurable comparison.

**Ideas sharpened by the confirmed product:**
- **Spoken Smart Paste.** Hold fn+V and say "as bullet points for Slack", or say nothing to get the destination default. It is Pastely's ⌘⇧V with a voice instead of typing into the field first.
- **Screenshot to agent prompt.** Copy a screenshot of an error, then in Claude Code say "fix this". On-device Vision OCR, then redaction, then a structured bug prompt with repo vocabulary. Pastely takes images but has no repo or agent awareness [PA0].
- **No account, no quota.** Pastely's free tier is 4 transforms [PA0]. Visprflow's local level costs nothing and needs no sign-in; the ledger and egress test (R2) show that nothing left.
- **Clipboard recall by voice.** "Paste the link I copied from Figma." Pastely only keeps a history of *transforms* [PA0], not of everything copied.

### On the Visprflow + Pastely combination
- **As a standalone clipboard product: no.** Maccy (free, MIT, 22k stars), Paste 7 (on-device Intelligent Clipboard, clipboard MCP), Raycast (Ask Clipboard, AI Commands, dictation), Apple Spotlight clipboard history, Pasly and Pastily all already exist [G1][PA4][R3][A1][PA2][PA3]. It would be the sixth or seventh of its kind.
- **As a capability inside Visprflow: yes, as ideas 2 + 3 + 4.**
  - Visprflow already knows the destination and has a compiler that adapts text to it. Pastely's whole pitch is "adapts to wherever you paste".
  - Pointing that compiler at the clipboard is mostly reuse.
  - Doing it on-device, with repo vocabulary and a ledger, is a version nobody ships.
  - Adding voice references into clipboard *history* is the gap the survey found [F1].
- **Product line:** "say it or paste it; it arrives right for where it is going, and you can see what left your Mac."

---

## 4. Top 3 recommendations

### R1 — Speak-to-transform and Smart Paste (ideas 1, 2, 3, 4)

**Context sources.** Add a `ContextSources` layer that runs at key-down:
- **Selection.** Read the AX selected text from the focused element. Fall back to ⌘C with a read-receipt restore, reusing `Inserter` (SelectedTextKit, MIT, is a reference [G1]).
- **ClipboardStore.** Keep the last 200 text clips, each with its source bundle id and a timestamp.
  - Fed by a `changeCount` poll.
  - Skips `org.nspasteboard.ConcealedType`, `TransientType` and `AutoGeneratedType`, plus user-excluded apps (password managers by default).
  - Kept in the existing GRDB file, encrypted with a Keychain-held key.

**Three new intents:**
- **transform**: trigger + Option, or a spoken lead such as "rewrite this". The input is the selection plus your instruction.
- **smart paste**: trigger + V, or "paste this as…". It compiles the current clip for the destination, using that destination's level, instruction and repo vocabulary. Claude Code gets a bug prompt built around a pasted stack trace. Slack gets a CSV as a table. A shell gets the clip verbatim, always.
- **recall**: spoken references to past clips.
  - They resolve **on-device** by recency ("last three"), source app ("from Figma", via bundle id) and type ("the link" or "the error", via regex classes).
  - Optional NLEmbedding matching; its quality is UNVERIFIED.

**Guardrails and privacy.**
- Only the referenced clips go to the provider, and only after the redaction pass.
- The ledger records which clip ids were sent.
- Guardrails are extended so the output may draw on the selection and clip text, but nothing else that was not spoken.
- Everything goes through the existing preview: Return inserts, Tab changes the level.
- Licence hygiene: borrow only from MIT or Apache sources (Maccy, Handy, OpenWhispr, Hex). VoiceInk, FluidVoice and MacParakeet are GPL, so use their ideas only [G1].

### R2 — "Nothing leaves, proven" (ideas 5, 6)

**On-device provider.**
- Add an **On-device model** provider behind `TextGenerating`.
- It uses Apple Foundation Models when the Mac has macOS 26 with Apple Intelligence on, and the current local rules otherwise, so the macOS 15 floor stays.
- Use it for the light and organised levels, and for smart paste on short clips.
- The window is 4,096 tokens shared between input and output [A4]. Keep the prompt tight, use guided generation to get a single `text` field, and drop the few-shot examples.

**History window.**
- SwiftUI over the existing `dictation` table.
- Per dictation it shows: raw transcript → the exact request sent (or "nothing left this Mac") → output → stage timings.
- Supports search and "re-run at a different level".

**Egress test.**
- `make verify-egress` runs the golden fixtures with local providers and fails on any non-loopback connection.
- Possible approaches: a URLProtocol spy in tests, plus an `lsof -i` or `nettop` check on the installed app. Which of these is reliable is UNVERIFIED.

**The pitch.** Against a competitor whose Mac client was publicly shown sending hourly metadata with sharing off [H3], "this app has a test that fails if it sends a byte" is a concrete, checkable difference.

### R3 — Public eval and latency harness (idea 7)

**Golden set.** Grow `Fixtures/golden` from 8 to 40 cases across the 8 destinations and 4 levels. Cover:
- self-corrections;
- technical vocabulary;
- shell commands that must survive verbatim;
- R1's transform and smart-paste cases.

Audio comes from `say` with several voices, as `verify-stt` already does, so no microphone is needed.

**Metrics:**
- word error rate per engine (Parakeet v3 batch, streaming, SpeechAnalyzer);
- guardrail pass rate;
- rate of unspoken content introduced;
- LLM-judge score against the expected output, per provider;
- cost per dictation.

**Latency rig.**
- It reproduces Talkify's method: end of recording → final text visible, median of 20, fixed phrase [L1].
- The target is a small test app whose NSTextView timestamps its first change, with key-up injected via CGEvent.
- Run it against Visprflow and whichever competitors are installed (free tiers only, per the $0 rule). Report median and p90, and publish the raw CSVs.

**Deliverables.**
- `make eval` and `docs/evals.html`.
- The roadmap's latency row switches from a vendor-run benchmark to independently measured numbers.
- For AI/FDE interviews this is the artefact that shows evals, measured trade-offs (batch vs streaming, ANE vs GPU) and honest corrections.

**Runners-up:**
- **Idea 8 (terminal scrollback as context).** It is the most novel developer feature left, but it depends on R1's redaction.
- **Idea 10 (acoustic vocabulary boosting).** It moved up after the spot-check: the batch engine appears to support it now [G4], and R3's harness can measure it.

---

## 5. Plan: 2–4 weeks (proposed; not frozen)

House rule: this is more than a day's work, so it should be argued through plan-together and frozen in ``PLAN.md`` before anything is dispatched. Each VERIFY below is one command, with no pipes or `;`. The new targets, tests and files do not exist yet.

**Days 1–2 — housekeeping (S)**
- MIT licence added to the public repo — `test -f LICENSE`
- Roadmap latency row cites the Talkify benchmark and its caveat — `grep -q talkify-latency-bench docs/roadmap.html`

**Week 1 — R3 foundation (it measures everything after)**
- Golden set reaches 40 cases — `test "$(find Fixtures/golden -name '*.json' | wc -l)" -ge 40` (already in PLAN.md)
- `make eval` writes per-provider metrics and exits 0 — `make eval`
- Latency rig: 20 trials of end-of-speech → field for Visprflow — `make verify-latency`

**Week 2 — R1 speak-to-transform and Smart Paste**
- Selection is read at key-down, with the ⌘C fallback restoring the clipboard — `make test` (new `SelectionReaderTests`)
- ClipboardStore skips concealed and transient types and excluded apps — `make test` (new `ClipboardStoreTests` with a ConcealedType fixture)
- Smart paste compiles a clip per destination, and the shell stays verbatim — `make test` (new `SmartPasteTests`)
- Spoken clip references resolve on-device — `make test` (new `ClipResolverTests`)
- Redaction strips keys and tokens before any provider call — `make test` (new `RedactorTests`)
- Transform and smart-paste golden cases pass — `make eval`

**Week 3 — R2 nothing-leaves**
- On-device provider behind `TextGenerating`, falling back below macOS 26 — `grep -rq FoundationModelsGenerator Visprflow/Core/Compile`
- History window shows each dictation's exact request — `grep -rq HistoryView Visprflow/UI`
- Egress test fails on any non-loopback connection in local mode — `make verify-egress`
- Memory ceiling still holds with ClipboardStore and the on-device model — `make verify-memory`

**Week 4 (optional) — publish and stretch**
- `docs/evals.html` with method, raw CSVs and competitor runs — `test -f docs/evals.html`
- Terminal scrollback context for Claude Code, redacted — `make test` (new `ScrollbackContextTests`)
- One LinkedIn post drafted from the eval page. Uncheckable by command: it goes through the linkedin-post-rules lint, and Vish posts it by hand.

---

## Sources (all accessed 2026-10-23)

**Wispr Flow**
- [W1] Wikipedia — https://en.wikipedia.org/wiki/Wispr_Flow
- [W2] Features — https://wisprflow.ai/features
- [W4] Command Mode help — https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode
- [W5] Pricing — https://wisprflow.ai/pricing
- [W6] Series B and Canto — https://www.outlookbusiness.com/deeptech/ai-voice-to-text-startup-wispr-flow-raises-280-mn-at-2-bn-valuation ; https://dealroom.co/news/145354-wispr-flow-raises-280m-at-2b-valuation-in-series-b/
- [W7] Security FAQ (cloud only) — https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq ; Baseten — https://baseten.co/customers/wispr-flow
- [W8] Context awareness — https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness
- [W9] Privacy — https://wisprflow.ai/privacy ; data controls — https://wisprflow.ai/data-controls
- [W10] App Store — https://apps.apple.com/us/app/wispr-flow-ai-voice-keyboard/id6497229487

**User sentiment and Wispr reviews**
- [H1] HN comments search — https://hn.algolia.com/api/v1/search_by_date?query=wispr%20flow&tags=comment (objectIDs 48896578, 50044186, 49746251, 50051742, 50046242, 50052237, 49747122)
- [H2] Show HN FreeFlow — https://news.ycombinator.com/item?id=47040375
- [H3] Forensic write-up — https://wensenwu.com/thoughts/wispr-flow-investigation ; HN — https://news.ycombinator.com/item?id=47781148
- [P1] Embertype [competitor] — https://embertype.com/blog/the-day-wispr-flow-banned-a-user/
- [P2] ModelPiper [competitor] — https://modelpiper.com/blog/wispr-flow-privacy-incident
- [P3] Spokenly review [competitor] — https://spokenly.app/blog/wispr-flow-review
- [P4] tl;dv [competitor] — https://tldv.io/uk/blog/wispr-flow-notetaker-review/
- [P5] BossAI — https://bossai.tech/blog/wispr-flow-review
- [P6] Voibe [competitor] — https://www.getvoibe.com/resources/best-wispr-flow-alternatives-windows/

**Claude Code**
- [C1] Voice dictation docs — https://code.claude.com/docs/en/voice-dictation ; TechCrunch — https://techcrunch.com/2026/03/03/claude-code-rolls-out-a-voice-mode-capability/

**Raycast**
- [R1] Changelog v0.57 — https://www.raycast.com/changelog/macos/0-57 ; macOS changelog — https://www.raycast.com/changelog/macos
- [R2] AI Commands — https://manual.raycast.com/ai/ai-commands ; v0.65 — https://www.raycast.com/changelog/macos%2F0-65
- [R3] Clipboard History — https://manual.raycast.com/clipboard-history
- [R4] Spokenly vs Raycast [competitor] — https://spokenly.app/comparison/raycast
- [R5] Pricing — https://www.raycast.com/pricing

**superwhisper**
- [S1] Context docs — https://superwhisper.com/docs/common-issues/context ; Super Mode — https://superwhisper.com/docs/modes/super
- [S2] Homepage — https://superwhisper.com/
- [S3] Voibe pricing [competitor] — https://www.getvoibe.com/resources/superwhisper-pricing/
- [S4] Claude Code integration — https://superwhisper.com/claude-code
- [S5] S1 models — https://superwhisper.com/blog/s1 ; https://huggingface.co/superwhisper/S1-mini

**VoiceInk**
- [V1] Context awareness — https://tryvoiceink.com/docs/context-awareness ; homepage — https://tryvoiceink.com/
- [V3] Power Mode — https://tryvoiceink.com/docs/power-mode

**Pastely, the other "Pastly" candidates, and clipboard tools**
- [PA0] Pastely, the product Vish saw — https://www.pastely.click/
- [PA1] Pastely directory listing, superseded by [PA0] — https://www.productcool.com/product/pastely-2
- [PA6] Pastely clipboard managers on GitHub, unrelated — https://github.com/amenophis1er/pastely ; https://github.com/claudeflaig/Pastely
- [PA2] Pasly — https://pasly.app/ ; https://www.producthunt.com/products/pasly-smart-clipboard-manager-for-mac
- [PA3] Pastily — https://www.pastily.app/ ; also Pasty https://getpasty.app/ , Pastely (sync) https://apps.apple.com/us/app/clipboard-manager-pastely/id6752802696 , pastly.in (web share) https://pastly.in/ , Pastly Lightroom presets https://play.google.com/store/apps/details?id=com.dom.paste.lightroom.preset
- [PA4] Paste updates — https://pasteapp.io/updates/rss.xml ; Paste MCP — https://pasteapp.io/mcp ; Paste 7 — https://www.producthunt.com/p/paste/paste-7 ; pricing — https://pasteapp.io/pricing
- [PA5] apfel-clip — https://apfel-clip.franzai.com/

**Apple**
- [A1] Newsroom, Tahoe — https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/ ; 9to5Mac — https://9to5mac.com/2025/06/18/spotlight-clipboard-manager-keyboard-maestro/
- [A2] Macworld, 26.1 retention — https://www.macworld.com/article/2962021/this-macos-tahoe-26-1-setting-will-eliminate-embarrassing-clipboard-mishaps.html
- [A3] SpeechAnalyzer — https://developer.apple.com/documentation/speech/speechanalyzer ; WWDC25 277 — https://developer.apple.com/videos/play/wwdc2025/277/
- [A4] Foundation Models context — https://developer.apple.com/forums/thread/831208 ; https://infoq.com/news/2026/03/apple-foundation-models-context
- [A5] Foundation Models docs — https://developer.apple.com/documentation/foundationmodels ; WWDC26 — https://developer.apple.com/videos/play/wwdc2026/241 , https://developer.apple.com/videos/play/wwdc2026/8121/
- [A6] Writing Tools — https://support.apple.com/guide/mac-help/mchldcd6c260/mac

**GitHub and models**
- [G1] GitHub API via `gh` (stars / last push / licence):
  - Dictation and speech: VoiceInk 6,905 / 2026-10-21 / GPL-3.0; Handy 34,394 / 2026-10-23 / MIT; FluidAudio 3,171 / 2026-10-21 / Apache-2.0 (v0.17.7, 2026-10-08; CTC vocabulary boosting); WhisperKit (argmax-oss-swift) 6,413 / MIT; whisper.cpp 54,579 / MIT; OpenWhispr 9,793 / 2026-10-23 / MIT; FluidVoice 12,406 / GPL-3.0; Hex (anomalyco/hex) 530 / MIT; parakeet-mlx 988 / Apache-2.0; Buzz 22,150 / MIT.
  - Clipboard and context: Maccy 22,036 / MIT; Clipy 8,933 / MIT; screenpipe 22,036 / commercial source-available licence; SelectedTextKit (tisfeng) / MIT.
  - Apple-model and paste tools: Pastr (iamngoni/Pastr) / MIT; Blitztext (cmagnussen/blitztext-app) / MIT.
  - Local LLM runtimes: mlx-swift / MIT; llama.cpp 132,077 / MIT.
- [G2] Handy README — https://github.com/cjpais/Handy
- [G3] Parakeet v3 model card — https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- [G4] FluidAudio custom vocabulary doc — https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/CustomVocabulary.md

**Other products and benchmarks**
- [O1] FluidVoice — https://github.com/altic-dev/FluidVoice ; review https://embertype.com/blog/fluidvoice-review/
- [O3] Spokenly — https://spokenly.app/
- [O4] Aqua Voice — https://aquavoice.com/llms.txt ; https://aquavoice.com/pricing
- [O5] Monologue — https://www.monologue.to/ ; https://every.to/on-every/introducing-monologue-effortless-voice-dictation
- [O6] Typeless — https://www.typeless.com/ ; https://www.typeless.com/pricing
- [F1] TalkBoard — https://gardnerscot.github.io/cola-pages/talkboard/ ; Pipit — https://alternativeto.net/software/pipit/about (the "no voice-transform-of-clipboard-history product" finding is a negative search result, not proof of absence)
- [F2] superwhisper feature request — https://superwhisper.userjot.com/board/p/text-replacement-from-clipboard
- [L1] Talkify latency benchmark (run by Talkify's developer) — https://github.com/tornikegomareli/talkify-latency-bench ; https://usetalkify.app/ ; conflicting Willow benchmark — https://willowvoice.com/blog/speech-to-text-latency-benchmark
