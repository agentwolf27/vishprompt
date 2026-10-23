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

## 2026-10-23 — Claude (chassis tap probe)

Does reading the palm-rest accelerometer need Input Monitoring? No. A throwaway app
(`com.vish.visprflow.tapprobe`, hardened runtime, signed "Visprflow Dev", no grants), launched
with `open` so it is its own responsible process, opened the usage-3 device and read it after
writing the driver's three properties. Run from the shell, the same binary inherits the parent
app's grants, so only the `open` run counts.

Evidence: the probe's output, `open -W -n TapProbe.app`
```
{"accessibility":false,"device":"present","driverPropertyWrites":{"ReportInterval":0,"SensorPropertyPowerState":0,"SensorPropertyReportingState":0},"firstSampleG":[0.0863037109375,-0.5131988525390625,-0.857666015625],"inputMonitoringPreflight":false,"openStatus":"0x00000000","reportsIn3s":2395,"zRangeG":[-0.85833740234375,-0.8457794189453125]}
```

Evidence: the same probe before the driver writes (matched by a `Product` name this macOS doesn't set): `"openStatus":"0x00000000","reportsIn3s":0`. Opening alone streams nothing.

## 2026-10-23 — Claude (chassis tap, step 1: the sensor)

`SPUAccelerometer` reads the palm-rest accelerometer in the app: found by vendor page 0xFF00,
usage 3 and a 22-byte report; the driver matched by usage 3; 800 Hz active, 100 Hz idle; a
watchdog re-arms the driver if the rate sags below half. Not wired to anything yet.

Evidence: `make verify-sensor`
```
PROBE sensor: active 796 Hz, idle 99 Hz, median 1.002 g
	 Executed 1 test, with 0 failures (0 unexpected) in 6.342 (6.344) seconds
```

Evidence: `make test-class C=SPUAccelerometerTests` — `test-class: SPUAccelerometerTests passed` (3 tests).

Evidence: `make test` — `Executed 467 tests, with 21 tests skipped and 0 failures`; `make release` — `** BUILD SUCCEEDED **`.

## 2026-10-23 — Claude (chassis tap, step 2: the detector, first half)

`TapDetector` is pure (no IOKit, no clock): high-pass, adaptive floor, echo guard, handling and
tilt rejection, double-tap window, burst guard, and key/click suppression. `make record-taps`
is a guided recorder. Only the idle recording is real so far (10 s, this Mac, 7,959 samples,
high-passed noise median 1.2 mg, max 5.2 mg); the tap cases are synthetic knocks laid over it.
The plan line for Tap 2 stays unticked until Vish's real taps are recorded and pass.

Evidence: `make test-class C=TapDetectorTests` — `Executed 12 tests, with 0 failures`.

Evidence: `make test` — `Executed 479 tests, with 21 tests skipped and 0 failures`; `make release` — `** BUILD SUCCEEDED **`.

