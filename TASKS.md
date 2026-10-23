# Tasks

## In progress

| # | Task | Owner | VERIFY |
|---|---|---|---|
| 2 | Chassis tap: the detector; waiting on task 5 for real taps before it is done | Claude | `make test-class C=TapDetectorTests` |
| 3 | Chassis tap: gesture, setting and power rules | Claude | `make test-class C=ChassisTapGestureTests` |

## Queued

| # | Task | Owner | VERIFY |
|---|---|---|---|
| 4 | Chassis tap: README section, after the LinkedIn post (2026-10-24 10:00 PT) | Claude | `grep -q "palm rest" README.md` |
| 5 | Record real taps on the palm rest for the detector's tests | Vish | a person tapping a MacBook; no command can do it |

## Done

| # | Task | Owner | VERIFY |
|---|---|---|---|
| 1 | Chassis tap: the sensor | Claude | `make verify-sensor` |
