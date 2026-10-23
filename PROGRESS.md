# Progress

## 2026-10-23 — Claude (session for Vish)

Renamed the repo from Visprflow to VishPrompt, keeping the runtime identity (see DECISIONS.md D1).
Folders, files, Xcode project/targets/scheme/module, `.app` name, Makefile, `TEST_RUNNER_VISHPROMPT_*`
switches, scripts, tests, docs and the GitHub description now say VishPrompt. Bundle identifiers,
the history path, the Keychain service, the defaults keys and the `Visprflow Dev` certificate are
unchanged. The remaining `Visprflow` strings in tracked files are those identifiers plus the
"formerly Visprflow" notes.

Evidence: `gh repo view agentwolf27/vishprompt --json description -q .description`
```
VishPrompt — a macOS dictation pipeline: speech to structured prompts, routed to coding agents
```

Evidence: `make test`
```
Executed 393 tests, with 20 tests skipped and 0 failures (0 unexpected) in 12.041 (12.675) seconds
** TEST SUCCEEDED **
```

Evidence: `make verify-stt`
```
STT latency: 219ms for 14.1s of audio (64x realtime)
Executed 6 tests, with 0 failures (0 unexpected) in 8.096 (8.103) seconds
** TEST SUCCEEDED **
```

Evidence: `make verify-test-can-fail` (exit 0; the inner `make test` with the canary set fails as it should)
```
** TEST FAILED **
make[1]: *** [test] Error 65
```

Evidence: `make verify-ocr` and `make release`
```
test-class: ScreenshotOCRTests passed (Executed 5 tests, with 0 failures)
** BUILD SUCCEEDED **
build/Build/Products/Release/VishPrompt.app
```

Not re-run here: `make verify-memory`, `make verify-latency` and the per-class `make test-class`
outcomes (all are subsets of the passing `make test`, or unchanged in substance). The outcome
`ls ~/Applications/VishPrompt.app` fails until `make install` is run after this merges; the
installed app is still `~/Applications/Visprflow.app`.

## 2026-10-23 — Claude (session for Vish) — correction

Corrects the entry above: `dev` moved by four commits (a3711bd, 501cb14, 4f2b560, 7fe867e) while
PR #23 was open, so the rename was redone on top of 7fe867e, then rebased onto 316fdca , onto d76efd6, 36789ce and 43589be (each time the new files moved into the renamed folders). The four new files landed in the
renamed folders. Same decision (D1), same scope.

Evidence: `make test`
```
Executed 450 tests, with 20 tests skipped and 0 failures (0 unexpected) in 16.127 (16.353) seconds
** TEST SUCCEEDED **
```

Evidence: `make verify-stt`
```
Executed 6 tests, with 0 failures (0 unexpected) in 53.008 (53.014) seconds
** TEST SUCCEEDED **
```

Evidence: `make verify-test-can-fail` — inner run `** TEST FAILED **`, target exit 0.

Evidence: `make release`
```
** BUILD SUCCEEDED **
build/Build/Products/Release/VishPrompt.app
```
