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

## 2026-10-24 — Claude (Home window, step 4: history retention)

Settings → Appearance → "Keep history for": 30 days, 60 days, 90 days or Forever, with the
history file's size on disk (WAL included) under it.
- Pruning deletes unpinned rows older than the period, and their timings, from the local SQLite
  only. It runs at launch and every 24 hours, after the app's test-host guard, so a test run
  never touches the real file.
- Forever deletes nothing, and pinned rows are never pruned under any period.
- The first read decides the default and saves it: an install with history keeps Forever (this
  one), a new install keeps 90 days.
- A shorter period that would remove anything asks first, with the real count ("This removes 2
  items older than 30 days. Pinned items stay."). A longer one applies at once.

Evidence: `make test-class C=RetentionTests` — `test-class: RetentionTests passed` (10 tests).

Evidence: `make test` — `Executed 529 tests, with 22 tests skipped and 0 failures`; `make release` — `** BUILD SUCCEEDED **`.

## 2026-10-25 — Claude (chassis tap fix 1: the trackpad)

Vish: "the palm rest tap works on the mouse pad when i double tap and hold it not the sides of
the mouse where the mouse dont exist". Reproduced from the app's own log of his session:
`Double tap on the palm rest` eight times from 14:25 to 14:29, and only two `Double tap ignored`
(key or click 0.04 s and 0.27 s from the knock). The suppression read key presses and clicks
only. A trackpad tap or hold raises touch (gesture) events and no click, and a Force Touch
press fires the Taptic Engine, a clean knock to the accelerometer.

The window server's per-type ages answer for touch (29) and pressure (34) with no permission.
A grant-less probe read `gesture29 0.08 pressure34 0.08` while the trackpad was in use, and
`key 24.33`. `TapInputGuard` now watches keys, clicks, scrolls, trackpad touches and Force Touch
pressure. The sensor's clock matches uptime (`sensor t 32153.821  uptime 32154.131` after a
0.3 s wait), so the window is measured on one clock.

Evidence: `make test-class C=TapInputGuardTests` — `test-class: TapInputGuardTests passed` (4 tests).

## 2026-10-25 — Claude (chassis tap fix 2a: Vish's recordings, the click veto, handling)

Vish recorded all seven scenarios on his Mac14,7, sitting on a bed under a blanket. Measured
with a 13 Hz high-pass:
- Left-side taps: mostly 10–17 mg, the same size as the resting noise (idle reaches 8.6 mg),
  with three firm hits of 0.06–0.37 g that ring for 0.4–0.9 s.
- Right-side taps: 0.03–0.19 g, one at 0.54 g, ringing 0.2–0.6 s.
- Trackpad clicks: 0.016–0.055 g.

On the bed no band from 13 to 200 Hz separates the light taps from noise (the ratio of the
weakest tap to the idle maximum is 0.98–1.07). The clicks shake mostly sideways (z share
0.05–0.36), while firm palm-rest taps push down (z 0.69–0.96). An attack-based prototype
caught some doubles but also fired on a bump in idle and in handling, so it is not shipped
without desk data.

**Clicks:** `clicks.csv` holds 20 s of trackpad clicks with the left-click age polled every
5 ms, and has not one mark. The same poll caught 101 key presses in `typing.csv`. Trackpad
clicks never reached the hardware-level counter the old veto read. `TapInputGuard` now also reads
the session-level counters and watches mouse releases, on top of fix 1's touch and Force Touch
events. Whether a click now reaches the veto needs a recording made with the new recorder,
which marks touches.

**Handling:** the one false fire on the negative files ("handling", 10.2 s, live rate) was a
knock 1.2 s after the Mac was moved. The quiet period after handling goes from 0.8 s to 1.5 s.

The detector's synthetic tests now use the quiet desk idle (`idle-desk.csv`), because Vish's idle
has a bump in it.

Evidence: `make test-class C=TapRecordingTests` — `test-class: TapRecordingTests passed`:
```
PROBE live idle: 0 before the input veto, 0 after
PROBE live single: 0 before the input veto, 0 after
PROBE live typing: 1 before the input veto, 0 after
PROBE live clicks: 0 before the input veto, 0 after
PROBE live handling: 0 before the input veto, 0 after
PROBE live double-left: 0 fired
PROBE live double-right: 0 fired
```
The two positive files fire nothing on the bed. Tap fix 2 stays unticked until desk recordings
show doubles firing.

Evidence: `make test` — `Executed 537 tests, with 22 tests skipped and 0 failures`; `make release` — `** BUILD SUCCEEDED **`.

## 2026-10-25 — Claude (palm-rest gestures: planned, side separation measured)

The plan for user-chosen palm-rest gestures is frozen and queued behind the detector, which
waits for desk recordings. Measured on Vish's bed recordings, using the direction of each knock's
first push (the first 25 ms, high-passed at 13 Hz):

Evidence: `python3 -I side.py double-left.csv double-right.csv` (scratch script, recordings in Fixtures/taps)
```
knocks >0.012g: left 6, right 13 | x-sign rule 68% | nearest-centroid (leave-one-out) 42% | chance 68%
knocks >0.030g: left 5, right 16 | x-sign rule 71% | nearest-centroid (leave-one-out) 52% | chance 76%
```
Left and right are at chance on the bed, so the calibration gate would keep the side rows locked
there.

## 2026-10-25 — Claude (chassis tap fix 2b: the detector, tuned on desk recordings)

Vish recorded double-left, double-right, single and clicks at a desk.
- **Doubles:** a tap rises from about 5 mg to 0.1–0.5 g within 10 ms and dies down within about
  0.25 s, and the second tap lands 0.28–0.31 s after the first.
- **Clicks:** 8–17 mg, with 18 click marks this time; on the bed there were none.

What changed in `TapDetector`, each change from a case in the recordings:
1. **Tilt is judged at decision time.** A ~300 ms posture is compared against the gravity before
   the first knock, not a 30 ms average at the end of the knock: a firm tap swings the chassis
   without changing how it sits. Desk left went from 1 to 6 doubles. The limit is 0.08 g.
2. **A second tap inside the first one's ring starts its own knock:** a rise to 60% of the peak
   after the ring dipped below 35%.
3. **A real second tap is at least 40% of the first's peak.** A bounce in a bump's ring is weaker.
4. **Bug fix:** a pending first knock was thrown away while the second was still being measured,
   because a knock joins the list only when its capture ends. Desk right went from 2 to 4.
5. **The first tap must start from stillness:** the shaking just before it under 30% of its peak.
   This drops wobbles in a long settle on the bed.
6. **Handling is a change in posture.** Posture drifting more than 0.03 g from gravity, while no
   knock rings, opens the handling window. A long ring, or a knock inside the window, no longer
   extends it, which used to keep the detector deaf for seconds.

`bed/idle` holds one real double knock at 5.63 s (185 and 154 mg, 0.20 s apart), shaped exactly
like a double tap. The test pins it rather than pretending a detector can drop it.

Evidence: `make test-class C=TapRecordingTests` — passed:
```
PROBE desk/double-left: 6 at 800 Hz ["1.28", "4.64", "7.99", "11.18", "14.70", "18.09"], 6 live; rejected [:]
PROBE desk/double-right: 4 at 800 Hz ["1.14", "8.59", "14.89", "18.31"], 4 live; rejected ["right after handling": 3, "rang too long": 1]
PROBE desk/single: 0 at 800 Hz [], 0 live
PROBE desk/clicks: 0 at 800 Hz [], 0 live; rejected ["began in shaking": 1]
PROBE bed/single, bed/typing, bed/clicks, bed/handling: 0 at 800 Hz, 0 live
PROBE bed/idle: 1 at 800 Hz ["5.82"], 1 live
PROBE bed/double-left: 1 at 800 Hz ["8.73"], 1 live
PROBE bed/double-right: 4 at 800 Hz ["2.20", "2.87", "4.26", "18.74"], 3 live
```

Evidence: `make verify-tap-cpu` — `PROBE tap cpu: 0.40% of one core sampling, 0.02% without, 0.38% for the trigger`.
Evidence: `make verify-sensor` — `PROBE sensor: active 796 Hz, idle 99 Hz, median 0.997 g`.
Evidence: `make test` — `Executed 538 tests, with 22 tests skipped and 0 failures`; `make release` — `** BUILD SUCCEEDED **`.

Tap fix 2 stays unticked until a trackpad recording (hold, Force Touch, scroll) backs "nothing
fires from the trackpad".

