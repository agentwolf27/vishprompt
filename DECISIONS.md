# Decisions

## D1 — Rename the repo to VishPrompt, keep the runtime identity · accepted · Vish + Claude · 2026-10-23

Everything that names the project is now VishPrompt: the folders (`VishPrompt/`, `VishPromptTests/`),
the Xcode project, targets, scheme and module, `VishPromptApp.swift`, the entitlements and bridging
header, the `.app` (`~/Applications/VishPrompt.app`), the Makefile, the `TEST_RUNNER_VISHPROMPT_*`
switches, the scripts, the tests, the docs and the GitHub description.

Kept on purpose, as in commit 1b5daea: the bundle identifiers `com.vish.visprflow` and
`com.vish.visprflow.tests`, the names built from them (log subsystem, Keychain service, pasteboard
type, notification name, ObjC error domain), the history store at
`~/Library/Application Support/Visprflow/visprflow.sqlite`, the defaults keys, and the signing
certificate `Visprflow Dev`. macOS ties the Microphone and Accessibility grants to the identifier
and the certificate, and the history and API key live under those names. `AppIdentityTests` pins
both the visible name and the identifier.

Rejected: renaming the identifier and the data paths too. It would make macOS ask for every
permission again and lose the history and the saved API key unless a migration was written, for
no gain a user can see.

Risk accepted: the `.app` file name changes. The grants are keyed on the identifier and the
certificate, not the path, so they should survive `make install`; if they do not, they are two
clicks to grant again.

## D2 — Turn on the palm-rest accelerometer by writing its driver's properties · accepted · Vish · 2026-10-23

The chassis tap trigger reads the undocumented motion sensor behind `AppleSPUHIDDevice`. Opened
on its own it sends nothing; the driver (`AppleSPUHIDDriver`, usage 3) must be set to report,
powered and given an interval, through `IORegistryEntrySetCFProperty`. These run as the user,
need no admin password and no new permission, and touch only the accelerometer's driver, which
resets itself when the app closes the device. Vish allowed it in chat: "allow the sensor property
writes, run the probe, then build".

Rejected: the microphone for knock detection, which would break the promise that it records only
while you dictate; and leaving the feature out, which is what declining the writes would mean.

Risk accepted: an undocumented device can change in a macOS update. The feature is off by
default, hidden where the device is absent, and fails to "unavailable", never to a crash.

