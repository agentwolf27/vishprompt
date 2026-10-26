# Tasks

## In progress

| # | Task | Owner | VERIFY |
|---|---|---|---|
| 2 | Chassis tap: the detector; waiting on task 5 for real taps before it is done | Claude | `make test-class C=TapDetectorTests` |

## Queued

| # | Task | Owner | VERIFY |
|---|---|---|---|
| 23 | Unwanted sessions: false-rate gate on long idle recordings, card warning | Claude | `make test-class C=TapFalseTriggerTests` |
| 5 | Record at a table (all scenarios, SURFACE=desk), and the trackpad scenario (hold, Force Touch, scroll); there is no desk data yet | Vish | a person tapping a MacBook; no command can do it |

## Done

| # | Task | Owner | VERIFY |
|---|---|---|---|
| 1 | Chassis tap: the sensor | Claude | `make verify-sensor` |
| 3 | Chassis tap: gesture, setting and power rules | Claude | `make test-class C=ChassisTapGestureTests` |
| 6 | Home window: window, sidebar, theme | Claude | `make test-class C=HomeWindowTests` |
| 7 | Home window: cards, copy, pin, delete, search | Claude | `make test-class C=HistoryCardTests` |
| 8 | Home window: Dictionary and Settings cards | Claude | `make test-class C=SettingsCardTests` |
| 9 | Home window: history retention | Claude | `make test-class C=RetentionTests` |
| 10 | Chassis tap: detector tuned on two bed sessions | Claude | `make test-class C=TapRecordingTests` |
| 11 | Palm-rest gestures: mapping, triple vs double | Claude | `make test-class C=PalmGestureTests` |
| 12 | Palm-rest gestures: side calibration gate | Claude | `make test-class C=SideCalibrationTests` |
| 13 | Palm-rest gestures: the Palm rest card and Test area | Claude | `make test-class C=PalmRestCardTests` |
| 14 | Trigger safety: shortcut modifiers refused, shortcuts pass through, overlap audit | Claude | `make test-class C=TriggerSafetyTests` |
| 15 | Hands-free stop: when I stop talking (pause length) or when I tap again | Claude | `make test-class C=HandsFreeStopTests` |
| 16 | Step 0: app identity on each row, migration v4 | Claude | `make test-class C=AppIdentityTests` |
| 17 | Step 0: outcome signals on each row | Claude | `make test-class C=OutcomeSignalTests` |
| 18 | Step 0: "How each app is going" on Home | Claude | `make test-class C=AppStatsTests` |
| 19 | Step 0: per-app writing rules in Settings | Claude | `make test-class C=AppRulesTests` |
| 4 | Chassis tap: README section, after the LinkedIn post (2026-10-24 10:00 PT) | Claude | `grep -q "palm rest" README.md` |
| 20 | Unwanted sessions: start source on every row, gesture logging | Claude | `make test-class C=StartSourceTests` |
| 21 | Unwanted sessions: a tap-started session always previews | Claude | `make test-class C=TapSessionPreviewTests` |
| 22 | Unwanted sessions: no-speech cancel, 60 s end in tap-again mode, start sound | Claude | `make test-class C=TapSessionGuardTests` |
