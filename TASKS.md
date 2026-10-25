# Tasks

## In progress

| # | Task | Owner | VERIFY |
|---|---|---|---|
| 2 | Chassis tap: the detector; waiting on task 5 for real taps before it is done | Claude | `make test-class C=TapDetectorTests` |

## Queued

| # | Task | Owner | VERIFY |
|---|---|---|---|
| 4 | Chassis tap: README section, after the LinkedIn post (2026-10-24 10:00 PT) | Claude | `grep -q "palm rest" README.md` |
| 5 | Re-record double-left and double-right at a desk, and clicks and trackpad with the new recorder (the bed set is in) | Vish | a person tapping a MacBook; no command can do it |

## Done

| # | Task | Owner | VERIFY |
|---|---|---|---|
| 1 | Chassis tap: the sensor | Claude | `make verify-sensor` |
| 3 | Chassis tap: gesture, setting and power rules | Claude | `make test-class C=ChassisTapGestureTests` |
| 6 | Home window: window, sidebar, theme | Claude | `make test-class C=HomeWindowTests` |
| 7 | Home window: cards, copy, pin, delete, search | Claude | `make test-class C=HistoryCardTests` |
| 8 | Home window: Dictionary and Settings cards | Claude | `make test-class C=SettingsCardTests` |
| 9 | Home window: history retention | Claude | `make test-class C=RetentionTests` |
