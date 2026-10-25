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

## 2026-10-23 — Claude (chassis tap, step 3: the gesture, the setting, the power rules)

A palm-rest double tap is a `chassisTap` event in `HotkeyGesture` (a toggle press plus its
release), delivered by `HotkeyMonitor.reportChassisTap()` on the main thread. `ChassisTapTrigger`
owns the sensor, samples only when `ChassisTapPower.shouldSample` holds, and drops a double tap
within 0.4 s of a key press or click, read from the window server's last-input ages (a grant-less
app reads the same ages as the shell: no permission). Off by default; the Settings toggle is
hidden without the sensor; the capsule says "Started by a tap · double-tap again to stop · esc".

**Correction to step 1.** `make verify-sensor` reported idle at 99 Hz, but that was timing luck:
logging the rate every 0.5 s shows the driver goes back to 800 Hz about a second after each
change to 100 Hz (`98 100 472 796 798 796 …`). The HID event system is also a client of the
driver; setting the rate through it is refused (the service is motion-restricted). The watchdog
now checks every 0.1 s and pulls the rate down again, and caches the driver instead of searching
the registry each time. Idle now averages 129 Hz, and the check allows up to 400.

Evidence: `make verify-tap-cpu`, six runs (the first three before the driver was cached)
```
PROBE tap cpu: 0.94% of one core sampling, 0.05% without, 0.89% for the trigger
PROBE tap cpu: 0.94% of one core sampling, 0.06% without, 0.88% for the trigger
PROBE tap cpu: 0.83% of one core sampling, 0.05% without, 0.78% for the trigger
PROBE tap cpu: 0.78% of one core sampling, 0.05% without, 0.73% for the trigger
PROBE tap cpu: 0.81% of one core sampling, 0.04% without, 0.76% for the trigger
PROBE tap cpu: 0.83% of one core sampling, 0.03% without, 0.81% for the trigger
```
At a steady 800 Hz it was 1.97%. Under the 1% target, without much room.

Evidence: `make verify-sensor` — `PROBE sensor: active 795 Hz, idle 129 Hz, median 0.994 g`.

Evidence: `make test-class C=ChassisTapGestureTests` passed (12 tests); `TapPipelineTests` passed (2);
`make test` — `Executed 494 tests, with 22 tests skipped and 0 failures`; `make release` — `** BUILD SUCCEEDED **`.

## 2026-10-24 — Claude (Home window, step 1: the window, sidebar and theme)

One VishPrompt window replaces the History window. The menu's "Open VishPrompt…" and ⌘Y open it.
It has a sidebar (Home, History, Dictionary, Settings, and the "To talk" footer) and the warm
light and dark themes from the mockup, following the Mac unless Settings → Appearance picks one.
Home shows the greeting and today's counts from real rows, with today's four most recent as
read-only cards. History is still the step-4 list until the next step. Dictionary shows the
current repo's words, read-only, because there is no user-editable word list. Settings has
Appearance and "More settings…", which opens the existing window.

Evidence: `make test-class C=HomeWindowTests` — `test-class: HomeWindowTests passed` (7 tests).
The snapshot checks read the rendered pixels: light background 250,248,245 (#FAF8F5), dark
background 26,25,24 (#1A1918), dark sidebar 21,20,19 (#151413).

Evidence: `make test` — `Executed 501 tests, with 22 tests skipped and 0 failures`; `make release` — `** BUILD SUCCEEDED **`.

## 2026-10-24 — Claude (Home window, step 2: the cards)

Every saved dictation on Home and History is now a card showing:
- the time, the app (the app in front at key-down; for older rows, the destination) and the
  mode (Dictate, Smart paste, Edit by voice, Screenshot fix; older rows read theirs from the
  level);
- "Stayed on this Mac" or "Sent to Claude" from the stored provider, or "Not recorded" for rows
  from before it was stored;
- Copy, which says Copied for 1.4 s; "What you said" with its own Copy; pin; and delete, with
  Undo.

Migration v3 adds `app`, `mode` and `pinned`. History searches the text, what was said, the app
and the mode, and groups Pinned, Today, Yesterday and dates. The arrow keys move the selection,
Return pastes the selection again and ⌘C copies it. The old History view is removed.

Correction: `SmartPasteHistoryTests` and `SelectionEditTests` cast every column of a row to
String, which traps on the new integer `pinned` column. They now collect text values only, as
their doc comments say.

Evidence: `make test-class C=HistoryCardTests` — `test-class: HistoryCardTests passed` (11 tests).

Evidence: `make test` — `Executed 512 tests, with 22 tests skipped and 0 failures`; `make release` — `** BUILD SUCCEEDED **`.

## 2026-10-24 — Claude (Home window, step 3: the Settings cards)

Settings in the window is now four cards, each wired to a setting that already existed:
- How you start talking: the trigger's key cap, and the palm-rest switch, which drives
  `AppState.setChassisTapEnabled` and on a Mac without the sensor says so and is disabled.
- Where the rewrite runs: three rows that set `ProviderPolicy.compilePath`. "On this Mac" sets
  the offline policy; a quick-cleanup path set elsewhere is kept.
- What can leave this Mac: audio and screenshot images are Never; your words say "Nothing leaves"
  only under the offline policy.
- Appearance.

Dictionary shipped in step 1 (the repo's words, read-only, saying there is no list of your own
yet). The sidebar footer offers the palm rest only when it is on and the sensor is present.

Evidence: `make test-class C=SettingsCardTests` — `test-class: SettingsCardTests passed` (7 tests).

Evidence: `make test` — `Executed 519 tests, with 22 tests skipped and 0 failures`; `make release` — `** BUILD SUCCEEDED **`.

