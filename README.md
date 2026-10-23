# VishPrompt

*Formerly Visprflow. The name changed because it read too much like Wispr Flow. The app bundle, its identifier, the history file and the saved settings keep the old internal name, so macOS keeps your permissions and your history stays.*

Hold `fn`, talk, release. The best possible prompt for wherever your cursor is lands in the
field. A prompt compiler for Claude Code, Cursor, claude.ai, Slack and email, running as a
native macOS menu bar app with on-device speech recognition.

The plan, the research behind it and the phase breakdown are in [docs/plan.html](docs/plan.html).

## Status

Phases 0 through 3 are built, plus most of the phase 4 and 5 polish. 177 tests pass. The app
is installed at `~/Applications/Visprflow.app`.

| Working | Not yet |
|---|---|
| Hold-to-talk, double-tap for hands-free, Escape to cancel | Streaming cloud speech recognition (phase 4) |
| On-device transcription with Parakeet v3 | Groq as a faster rewrite provider |
| Three rewrite providers: local, subscription, API key | |
| Destination detection and per-destination instructions | Selected text and screen OCR as context |
| Prompt compilation with guardrails and a raw fallback | Snippets and a prompt library |
| Preview with Return to insert, Tab to change level | Notarised distribution and Sparkle updates |
| Smart Paste: hold the trigger, press V, say how | |
| Screenshots read on this Mac into bug prompts | |
| Repository vocabulary from your git workspace | |

## What you have to do first

Two permissions, granted once, in the setup window that opens on first launch:

| Grant | Used for |
|---|---|
| Microphone | Recording while the key is held. Audio never leaves the Mac. |
| Accessibility | Pasting into the focused app and watching for the trigger key. |

Input Monitoring is not needed: Accessibility already lets the app see the trigger key.

Two more things worth doing in that window:

- **Set the fn key to "Do Nothing"** in System Settings, Keyboard. macOS handles the emoji
  picker before any app sees the key. The setup window detects this and links straight there.
  On an external keyboard, switch the trigger to Right Option instead: `fn` only reaches apps
  from the built-in keyboard.
- **Choose where rewrites go.** Three options, and the default mixes them:

  | Provider | Speed | Cost |
  |---|---|---|
  | On this Mac | instant | free |
  | Your Claude subscription | 3 s to first word, 6–10 s total | included in your plan |
  | Anthropic API key | 0.7 s to first word, 1–2 s total | roughly $0.002 per dictation |

  The default keeps quick cleanup local and sends compiled prompts to your subscription, so
  nothing costs extra and the common path stays instant. Local cleanup handles fillers,
  stutters, spoken punctuation and capitalisation. It does not attempt self-corrections, so
  a transcript containing "no wait" or "scratch that" is handed to a model automatically.

Launch from `~/Applications`, not from `build/`. Debug builds are ad-hoc signed, so macOS ties
the grants to the exact binary and every rebuild loses them.

## How it behaves

| Where your cursor is | What you get |
|---|---|
| Terminal running `claude` or `codex` | A structured prompt: goal, symptom, files you named, constraints, verification. Preview first, Return to insert. |
| Cursor, VS Code, Zed, Windsurf | The same, for the agent chat pane. |
| claude.ai, ChatGPT, Gemini, Perplexity | One clear ask with your context, inserted straight away. |
| Slack, iMessage, WhatsApp, Discord | Light cleanup that keeps your register, lowercase included. |
| Mail, Gmail, Superhuman | The ask in the first sentence, short paragraphs. |
| A shell prompt with no agent | Exactly what you said. Never capitalised, never punctuated. |
| A password field, or Terminal with Secure Keyboard Entry | Nothing is inserted. The overlay says so and the transcript goes to your clipboard. |

Hold `shift` with the trigger for verbatim, `control` for a full compile. Say "verbatim:" or
"prompt mode" to do the same with your voice.

## Smart Paste

Copy something, then hold the trigger and press `V` within a second. Say how you want it
pasted ("as bullet points", "shorter", "ask Claude why this fails"), or say nothing, and release.
The preview shows the result. Return pastes it, Tab flips between rewritten and as copied, and
Escape cancels. Your clipboard is put back afterwards, so what you copied never changes.

| What you do | What happens |
|---|---|
| Say nothing | The clip is pasted as copied. Nothing is sent anywhere. Into Claude Code, Cursor, Codex or a chat window, a multi-line clip is fenced and labelled as pasted data, and known secret shapes are replaced with `[redacted …]`. |
| Say an instruction | The clip goes to your compile-path provider with known secret shapes removed first. The first time for each provider, the overlay asks before sending anything. |
| Paste into a shell | Always exactly as copied, whatever you said. |
| Copy a password | A clip marked concealed by a password manager is never read. |
| Copy something huge | Over 20,000 characters is pasted as copied and never sent. |

With the compile path set to "On this Mac", an instruction cannot be followed and nothing is
sent. The overlay says so.

### Screenshots

Copy a screenshot of an error (⌘⌃⇧4 copies a selection), then in Claude Code, Cursor or Codex
hold the trigger and say "fix this". If the screenshot was copied in the last two minutes, its
text is read on this Mac with Apple's Vision framework and appended to the prompt, fenced and
labelled as data, with known secret shapes redacted. **The image never leaves the Mac, and the
screenshot text is never sent to the rewrite model**: the model only sees what you said, and
the text is added afterwards. Tab drops or restores the screenshot text; hold Shift to leave
it out. Fn+V with a screenshot does the same at any age. In any other app, fn+V pastes the
screenshot's text as a Smart Paste clip.

## Requirements

- macOS 15 or later, Apple Silicon
- Xcode 16.3 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build and run

```bash
make install              # Release build into ~/Applications (launch from there)
make test                 # unit tests, about a minute
make verify-stt           # speech tests against audio from `say`; needs no microphone
make verify-ocr           # Vision OCR against the committed screenshots in Fixtures/ocr
make verify-subscription  # drives the real `claude` CLI; spends subscription quota
make logs                 # stream the app's own log
```

`project.yml` is the source of truth; the `.xcodeproj` is generated and git-ignored.

## Layout

```
project.yml              XcodeGen definition
Visprflow/
  App/                   @main, app delegate, observable app state
  Core/Hotkey/           Gesture state machine, CGEventTap, secure input
  Core/Audio/            Capture, ring buffer, file loading
  Core/STT/              Transcriber protocol, Parakeet via FluidAudio
  Core/Compile/          Levels, system prompt, Claude client, guardrails
  Core/Destination/      Destination model, resolver, focus context, process tree
  Core/Context/          Workspace probe, repository vocabulary
  Core/Insert/           Paste with clipboard restore, keycode resolution
  Core/Paste/            Smart Paste and screenshots: clipboard, redactor, OCR, prompts
  Core/Pipeline/         DictationController, the orchestrator
  Core/Storage/          GRDB history and timings
  UI/                    Menu bar, setup window, overlay, destination settings
VisprflowTests/          XCTest target
Fixtures/golden/         Messy transcript to expected output cases
docs/plan.html           The plan
```

## Privacy

Audio never leaves the machine. The only thing sent anywhere is the transcript, the vocabulary
list, the destination name and your own instruction, and only when an edit level above verbatim
applies and the provider for that level is not local. Set both providers to "On this Mac" and
nothing leaves at all.

Smart Paste adds one thing to that list: **the clipboard text**, and only when you speak an
instruction. It goes to the compile-path provider after you have allowed it once for that
provider. Before it goes, known secret shapes are swapped for placeholders on this Mac: API
keys and tokens, JWTs, private key blocks, passwords in URLs and headers, `password = …`
assignments, and long random strings. For a message, email or document the real values are
put back locally once the model returns. For Claude Code, Cursor, Codex and chat windows they
stay redacted, because those destinations are models too. "Known shapes" is the claim: a
password written in a sentence is not caught, and
[Fixtures/secrets/known-misses.json](Fixtures/secrets/known-misses.json) lists what else is not.
History keeps only the redacted form. Every dictation is stored locally in
`~/Library/Application Support/Visprflow/visprflow.sqlite` together with the exact request that
was sent, so the claim is inspectable rather than promised.

## Licence

MIT. See [LICENSE](LICENSE).

## Git workflow

`main` receives only `dev`. Feature branches start from the latest `dev` and return to it by
pull request after a rebase. Branches are never deleted.
