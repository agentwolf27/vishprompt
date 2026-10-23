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
