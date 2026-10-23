# VishPrompt speed plan — 2026-10-23

Read-only review of `dev` at e181842 (2026-09-08); nothing built, run or edited in the repo.
Sources: code (file:line on `dev`), repo docs, the app's history DB (read-only, timing rows only),
web research (URLs inline). **M** measured, **E** estimate with basis, **UNVERIFIED** no source.

## Summary (one screen)

- **The local path is about 0.5 s from key-up to inserted (M, n=3).** Superwhisper's median is
  216 ms and VoiceInk's is 324 ms. Roughly 60% of our 0.5 s is the step from key-up to transcript:
  the in-app runs measured 244–475 ms for 1–3 s of audio. The test harness predicts about 30 ms of
  model time for clips that short, so about 0.2–0.3 s goes on overhead nobody has measured yet.
  A fixed 120 ms post-roll adds another quarter.
- **The subscription path is where the seconds go:** 3 s to the first word and 6–10 s in total
  (README, measured by the builder). It starts a fresh `claude` process for every dictation, and
  that process boots only after the key comes up. A third-party report puts headless CLI
  first-output at about 1.5–2.2 s.
- **Ordinary speech gets pushed onto that 6–10 s path with no preview.** Saying "i mean" in a Slack
  message is enough. So is a 25-word claude.ai question, or an 80-word email.
- **A cold mic start blocks the main thread inside the keyboard tap:** 0–448 ms (M, median ~250 ms,
  n=14). The tap is an active filter, so any key event system-wide waits that long, and speech in
  that window is not recorded. **The API path** opens a new HTTPS connection and reads the
  Keychain on every request. **Possible bug:** the clipboard may never be restored (see below).

## Stage-by-stage time budget

Real dictations: 14 rows in the history DB, 2026-09-04 to 09-18, all destination `document` and
nearly all LIGHT/local. Rows from before the 09-08 fix (the encoder was on the GPU) took 7–17 s to
transcribe and are excluded below. **The DB has no subscription or API dictations, so every
network figure is the builder's measurement or an estimate.**

| Stage | Time | Kind / basis |
|---|---|---|
| Hotkey detect (tap → keyDown mark) | ~1 ms | M, DB keyDown offset 0–4 ms |
| Mic start, key-down → captureStarted | 0–450 ms, median ~250 ms | M, DB n=14. Cold `AVAudioEngine.start()` after the 6 s linger, on the main thread inside the tap callback |
| Context enrich (ps, lsof, 2–3 git calls, osascript for browsers) | 0.05–0.5 s (timeouts 1–1.5 s each) | E, UNVERIFIED. Runs during speech; on the critical path only for short dictations |
| Post-roll after key-up | 120 ms | Code constant, AudioCapture.swift:210 |
| streaming.stop() + batch Parakeet + actor hops | 125–355 ms for ~1–3 s of audio | M (DB key-up → transcriptReady 244–475 ms, n=4, minus the 120 ms post-roll) |
| Parakeet v3 model time alone | 208 ms / 14.1 s; 143 ms / 4.9 s | M, test harness (build-report, roadmap). Vendor: RTFx 156–210 on an M4 Pro (docs.fluidinference.com/reference/benchmarks.md) |
| Destination resolve + level heuristic | <1 ms | E, pure lookups (DestinationResolver.swift:99) |
| Prompt compilation (build the strings) | <1 ms | E. System prompt is 6,070 chars ≈ 1.4k tokens; vocabulary up to 300 terms |
| Rewrite, local | 0–11 ms | M, DB compileDone |
| Rewrite, subscription CLI | ~3 s first word, 6–10 s total; 8.7 s for the login example | M by the builder (README, build-report). Tab recompile 6–10 s (UI review) |
| Rewrite, API (Haiku 4.5) | ~0.7 s first word, 1–2 s total | Documented, but "never exercised for real" (build-report). AA: 0.49 s TTFT, 86.5 tok/s at 10k-token input |
| Guardrails | <1 ms | E, string scans (Guardrails.swift:25) |
| Insert, compileDone → inserted mark | 45–60 ms (recent), up to 0.46 s | M, DB n=13. See the clipboard note below |
| HUD | first show builds the NSPanel lazily; 30 Hz re-render while recording | UNVERIFIED cost (DictationController.swift:611) |
| **Key-up → inserted, local path** | **0.49 / 0.52 / 0.55 s** | **M, n=3** (plan target: verbatim p50 300 ms) |
| App launch → model ready | not recorded anywhere | UNVERIFIED. FluidAudio quotes encoder load 3.4 s cold vs 0.16 s warm, on iPhone |
| Memory, idle | 40 MB footprint, peak 74 MB | M, 2026-09-08 (roadmap) |
| Memory, during a dictation | streaming model "~580 MB on disk and roughly that resident" in the ANE region; up to 19 MB capture reserve; separate `claude` process | Code comment (StreamingTranscriber.swift:28), AudioCapture.swift:177; the CLI's RSS is UNVERIFIED |

**Clipboard note (verify first).** `clearContents()` returns a change count, and then
`declareTypes` bumps it again (Inserter.swift:116–117). So `changeCount != ourChangeCount` is
already true at the first 50 ms poll, and the code takes `.abandon`, leaving our text on the
clipboard (Inserter.swift:136–150). The recent 45–60 ms insert times fit that path exactly: one
poll, then abandon. Fixing it adds the receipt wait plus the 200 ms quiet period to the
`inserted` mark, so first add a separate `pasted` mark at chord time (Phase 0). UNVERIFIED until
someone copies text, dictates, then presses ⌘V.

## Ranked speedups

Gains are per affected dictation. "Felt" means the user would notice it.

1. **Pre-spawn the `claude` CLI at key-down, then write the prompt at key-up.**
   - Run `-p --input-format stream-json --output-format stream-json` (documented long-lived mode,
     code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode), one fresh process per dictation,
     plus `--tools ""` and `MCP_CONNECTION_NONBLOCKING=true`. An idle process spends no quota.
     `--bare` is out: it cannot use the subscription.
   - Gain: E −1 to −2 s on the first word. Basis: headless first-output of about 1.5–2.2 s vs
     0.1 s for `--version` (claudeissues.com/issue/87652). Here, warm `claude --version` took
     0.06–0.2 s and the first cold run 2.7 s (M, today).
   - Effort M. Risk: orphan processes (kill on cancel or quit), and it is UNVERIFIED that startup
     happens before stdin input. ClaudeCLIGenerator.swift:60–160, DictationController.swift:210–258.
2. **Stop silent escalations to the 6–10 s path.**
   - What happens now: a LIGHT/local transcript containing "i mean", "no wait" and similar goes
     to the subscription (ProviderChoice.swift:102–107, LocalCleanup.swift:23–26).
   - Chat at 25+ words goes to MEDIUM and email at 80+ words to FULL. Both auto-insert with no
     preview (LevelHeuristic.swift, Destination.swift chat/email).
   - Fix: send escalations to the API when a key exists. Otherwise, show the preview whenever the
     provider is the subscription, and drop "i mean" from the trigger list.
   - Gain: M-based, 6–10 s → under 0.1 s for those dictations. How often it happens is
     UNVERIFIED; count it with the Phase 0 query.
   - Effort S. Risk: an unresolved self-correction could reach the field.
3. **One shared `URLSession`, a pre-opened connection at key-down, and the key cached in
   memory.**
   - Now: `ClaudeGenerator()` is rebuilt for every attempt through `RoutingGenerator`'s default
     arguments (ProviderChoice.swift:82–84, Compiler.swift:59). Each rebuild makes a new session
     (ClaudeGenerator.swift:12–17) and does a Keychain read (:19, :27).
   - Prewarm with a GET to `/v1/models` on key-down when the predicted path is the API.
   - Gain: E −0.1 to −0.45 s on the first word (one TCP+TLS setup; Apple DTS advises one session
     for TLS reuse, developer.apple.com/forums/thread/838823; one example puts a full handshake at
     ~450 ms). Measure with curl (below).
   Effort S. Risk low.
4. **Find and remove the 0.2–0.3 s of key-up STT overhead.**
   - `await streaming.stop()` runs before the batch model starts (DictationController.swift:289).
     It awaits `manager.reset()`, which can queue behind an in-flight ANE chunk. Cancel without
     awaiting instead.
   - After 10 minutes idle, the streaming model reloads during the first dictation and competes
     with the batch model (StreamingTranscriber.swift:34, 86). Loading it at launch is the fix.
   - Fire a 0.3 s silence inference at key-down to wake the ANE. Side bug: stop() during begin()'s
     `prepare()` leaves a drain loop running (StreamingTranscriber.swift:86–97).
   - Gain: E −100 to −300 ms. Basis: the measured gap between in-app and harness times. The cause
     is UNVERIFIED, so add the marks first. Effort S–M. Risk low.
5. **Replace the fixed 120 ms post-roll with "wait for the first tap buffer stamped after key-up"**
   (AudioCapture.swift:210–217; 1024 frames at 48 kHz is 21 ms per buffer).
   - Gain: E −75 to −95 ms on every dictation. Effort S. Risk: clipping the last word; guard it
     with StreamingIntegrationTests' tail test and verify-stt.
6. **Get the main thread out of the input path.**
   - Now: an active `.defaultTap` for keyDown, keyUp and flagsChanged on the main run loop
     (HotkeyMonitor.swift:62–80). The cold engine start happens inside that callback
     (DictationController.swift:233 → AudioCapture.swift:254–303).
   - Move the tap to its own thread, and start the engine off the callback. Optionally lengthen the
     6 s linger (AudioCapture.swift:48): the trade-off is a longer orange mic indicator.
   - Gain: M-based — up to ~250 ms (max 450) sooner listening HUD, no system-wide typing stall,
     and no first-word loss on cold starts (the ring is cleared then, :275).
   Effort M. Risk: AVAudioEngine thread confinement.
7. **Cache Tab recompiles per level, and precompute the next level when the preview opens.**
   - Now: cycling back to FULL recompiles from scratch (DictationController.swift:487–521; cycle
     order at EditLevel.swift:61).
   - Gain: revisit 6–10 s → 0 (S); precompute hides 6–10 s for quota (M).
8. **Make probes in-process and cache them per pid.**
   - Replace `ps`, `lsof` and git spawns with libproc (`proc_listchildpids`, `proc_pidinfo`
     PROC_PIDVNODEPATHINFO) (ProcessTree.swift:77, WorkspaceProbe.swift:21–55).
   - Drop the AX window-title read: nothing uses `windowTitle` (FocusContextProvider.swift:46).
   - Gain: E 0–0.5 s on short terminal or browser dictations, UNVERIFIED until a contextReady mark
     exists. Effort M. Risk low.
9. **Move off the legacy Haiku 4.5 and evaluate Haiku 5.5 with effort low.**
   - Haiku 5.5 is "Fastest", 238 tok/s vs 86.5 (artificialanalysis.ai). Its cache minimum is
     512 tokens, so the ~1.4k-token system prompt would cache. On Haiku 4.5 the minimum is 4,096
     and caching never engages (platform.claude.com/docs/en/build-with-claude/prompt-caching).
   - Also try Haiku 5.5 for FULL in place of Sonnet 5.
   - Gain: E about 2× faster generation (300 output tokens: about 3.5 s → about 1.3 s). Effort S in
     code (ModelChoice.swift:16–56) and M to evaluate. Risk: quality, with only 8 golden fixtures.
     Adaptive thinking defaults to medium and must be turned down.
10. **On a guardrail rejection, retry with local cleanup instead of a second model call**
    (Compiler.swift:48–94). Gain: saves one full call (1–10 s) on rejections, which are rare: DB
    rawFallback = 0. Effort S.
11. **Show the tail of the streamed rewrite.** The compiling HUD shows only the first 3 lines
    (HUDView.swift:33–34), so a long prompt reads as stalled. Felt, not timed. Effort S.
12. **Phase 3 options:** Groq/Cerebras for LIGHT/MEDIUM (first chunk 0.35–0.97 s at 10k inputs,
    AA; new egress). Foundation Models + `prewarm` for short self-corrections (~30 tok/s on iPhone
    15 Pro, 4,096-token context). Batch-transcribe finished VAD segments during pauses (E −0.3 to
    −0.8 s on 60 s dictations, linear-RTF basis, UNVERIFIED). Parakeet EOU (80–160 ms) for the
    hands-free stop instead of the 1.2 s amplitude timer (DictationController.swift:57).

**Rejected:** speculative compile on partials (withdrawn in roadmap item 11; streamed text
differs from batch, still true); streamed transcript as final ("passer" for "parser"); raw-first
insertion (breaks in terminals and Electron); padding to 4,096 tokens for Haiku 4.5 caching
(OpenAI's cookbook: only 7% TTFT at ~1k tokens); Predicted Outputs (OpenAI only); faster paste
(VoiceInk alone waits a fixed 200 ms before ⌘V).

## Measurement plan (before and after every change, on the installed Release build)

**Rule:** 20 dictations per condition; median and p90 with n, by provider and destination, same
Mac, mains power. **Phase 0 instrumentation:**
Add to `Stage` (Trace.swift:5–14): `engineStarted`, `postRollDone`, `streamStopped`, `sttDone`,
`contextReady`, `requestSent`, `firstByte`, `pasted` (Inserter.swift:130), `clipboardRestored`;
and a v2 migration adding `provider`, `model`, `audioSeconds` to `dictation` (Database.swift:43).

**Read the timings from the history DB (read-only, no transcript text):**
```
sqlite3 -readonly -header -column ~/Library/Application\ Support/Visprflow/visprflow.sqlite "select d.destination, d.level, s.stage, count(*) n, round(avg(s.sinceLastMs)) avg_ms, round(max(s.sinceLastMs)) max_ms from dictation d join stageTiming s on s.dictationId=d.id where d.createdAt > '2026-10-23' group by 1,2,3 order by 1,2,avg(s.offsetMs);"
```
Proposed `scripts/latency-report.py` does the same and adds p50/p90, which sqlite cannot compute.

**Live per-stage lines while dictating:**
```
make logs | grep -E "Dictation timings|Preview ready|Transcribed|Warm-up|Parakeet ready|Streaming model ready|Capture started|Pasteboard changed"
```

**Launch → model ready:** `make logs`, then `open ~/Applications/VishPrompt.app`; read the gap from
"VishPrompt launched" to "Speech model ready".

**CLI startup, cold vs pre-spawned (spends a little quota):**
```
/usr/bin/time -p claude -p "Reply with OK" --model claude-haiku-4-5 --output-format stream-json --verbose --include-partial-messages --no-session-persistence --strict-mcp-config --settings '{}' --tools ""
```
Proposed `scripts/time-cli.py` timestamps spawn, the first `stream_event` and exit, for (a) a
fresh spawn and (b) a process spawned 3 s earlier, fed through stdin with `--input-format
stream-json`.

**API connection cost (GET /v1/models is free):**
```
curl -sS -o /dev/null -w 'dns=%{time_namelookup} tcp=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer}\n' https://api.anthropic.com/v1/models -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01"
```
(`tls` = what item 3 buys back.)

**Main-thread stalls and the input lag from item 6:**
```
xcrun xctrace record --template 'Time Profiler' --attach VishPrompt --time-limit 30s --output /tmp/vf.trace
```
Dictate 5 times after >6 s idle each; check main-thread Hangs.

**Memory:** `footprint -p VishPrompt` idle and mid-dictation; `make verify-memory`;
`ps -o rss= -p $(pgrep -n claude)` during a subscription compile. **STT regression:**
`make verify-stt` and `make verify-streaming` around items 4 and 5 (tail test = last word).

**End-to-end harness:** feature/smart-paste's frozen PLAN already queues `make verify-latency`
(R3: "End-of-speech → field latency, 20 trials"). Build items 4–6 against it rather than a second
harness. Method: speaker playback, as in github.com/tornikegomareli/talkify-latency-bench, so the
numbers compare with Superwhisper (216 ms) and Wispr Flow (587 ms).

## Phased plan

- **Phase 0, measure (½ day):** new marks, DB columns, latency-report script; confirm or rule out
  the clipboard bug; baselines for local, subscription and API, 20 each.
- **Phase 1, quick wins (1–2 days, each S, each verified alone):** items 3, 5, 4, 2, 7 (cache
  only), 10, 11; drop `windowTitle`; build the HUD panel in `start()`. Target: local key-up →
  inserted from ~0.5 s to ~0.3 s (plan.html's verbatim p50).
- **Phase 2, structural (2–4 days):** item 1 (subscription first word ~3 s → ~1–1.5 s), item 6,
  item 8, item 9 against a golden set grown toward 40 cases.
- **Phase 3, bigger bets:** Groq/Cerebras behind a privacy note, Foundation Models tier,
  segment-batch STT, EOU for hands-free, opt-in speculative next-level precompute (7b).

**Coordination:** `feature/smart-paste` (another session) reworks `Inserter` and adds
`verify-latency`. Land items 3–5 on their own branch from `dev`; add the `pasted` mark after
Smart Paste merges.
