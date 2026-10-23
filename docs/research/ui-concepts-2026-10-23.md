# VishPrompt UI research and concepts — 2026-10-23

Research only. Nothing in any repo was edited. Current screens read from `origin/dev` of /Users/vish/Visprflow (`HUDView.swift`, `MenuBarView.swift`) and from the 2026-10-23 review (`visprflow-uiux-plan-2026-10-23.md`). Web sources were read on 2026-10-23; each claim carries a tag that resolves in §6. Anything without a tag is marked UNVERIFIED.

## 0. One-screen summary

- **What exists today.** One 460 pt-wide `regularMaterial` card, radius 14, pinned top-centre of the pointer's screen, that changes content by state: listening (mode chip, "into Slack", m:ss, 28-bar red meter, live words), transcribing, compiling (provider line + newest words), preview (chips, "You said", scrollable text to 40% of screen, notes, source line, hints), inserted, cancelled, failed. The menu bar is now a real menu (History ⌘Y, Last dictation ▸ Copy/Paste again, Pause, Settings ⌘,). Most of the P0s from the earlier review are fixed on `dev`; what remains is that **every state is the same grey rectangle in the same place**, and that place is where every competitor's users say they do not want it.
- **What the market converged on.** A tiny *anchor* while you talk (Wispr's ~70 px bottom pill, Raycast's pill above the app, superwhisper's mini window, VoiceInk's notch bar, Monologue's edge-peeking "monophone") and a *separate* window for history/settings. Nobody shows a full card while you are still speaking. [WF-Pill][R-D][SW-Rec][VI-Gen][MO-C]
- **What users hate.** A bar that covers the Dock or a Send button (Wispr: 700+ complaints, drag-to-edge shipped 2026-07-09) [DT][WF-New]; a "big overlay window" (superwhisper feedback board, 19 votes) [VB-SW]; a notch drawn on screens that have none (NotchNook) [MS-NN]; settings that take 15–30 minutes (superwhisper) [VB-SW]; text that lands raw and is replaced seconds later [VB-SW]; a bar that is hidden by default so nobody knows the app is running (Wispr) [WF-Move].
- **What users praise.** Being able to read and edit before it lands (Aqua) [PH-AQ]; the active mode shown on the recorder (Monologue, superwhisper) [MO-C][SW-Rec]; "pasting into Messages" with the app icon before a Smart Paste (Pastely) [PA]; "gets out of the way" (Monologue) [AS-MO]; interrupted recordings kept and retryable from History (Wispr, Raycast, Aqua) [WF-New][R-D][PH-AQ].
- **Recommendation: Concept A, "Island and Card".** A capsule that lives at the top edge (hugging the notch on notched Macs, a free-floating pill elsewhere) while listening; a card drops from it only when there is something to decide (preview, error, Paste, Fix); a Spotlight-style History window (⌘Y) for everything that is not a 2-second dictation. Effort M. The reasons are in §4.

## 1. Competitor UI facts

| App | Where the UI lives | States shown | Preview style | Mode switching | Settings / history | Standout detail | Complaints |
|---|---|---|---|---|---|---|---|
| Wispr Flow [WF-Pill][WF-Move][WF-Hub][WF-Cmd][WF-New] | Dark pill, bottom-centre, ~70 px tall inside a ~440×300 transparent window, repositioned every ~400 ms; follows the pointer's display; above the Dock; flush to edge in full-screen; draggable to left/right edge since 2026-07-09; hidden by default until setup finishes | Idle condensed lozenge with dotted waveform; hover shows the shortcut; expands with a voice indicator while held; processing; error (blocks the right-click menu) | None. "Desktop dictation inserts the completed text after you stop." Auto Cleanup has an "Undo AI Edit" that reveals the raw transcript [SP-WF] | Mic switcher and language picker sit on the bar; a wand icon appears on the bar when text is selected (Transforms); Command Mode is Fn+Ctrl with no overlay, result pasted in place or shown as a notification | Hub window: Home = searchable history grouped by date with hover Copy/Flag and stats; Dictionary; Snippets; Style; Scratchpad (⌥S, floats like a sticky note); Settings General/System/Account/Data & Privacy; dark mode 2026-10-19 | Instant "mic picks up no sound" warning (2026-10-09); failed or interrupted dictations retried from History | Bar covered Gmail Send and the Dock, 700+ responses, a third-party PillFloat exists to move it [DT][PF]; "a big annoying black rectangle" (Trustpilot, profile since removed — UNVERIFIED) |
| superwhisper [SW-Rec][SW-Ess][VB-SW][SP-SW] | Main window or a mini window (resize toggle); mini can stay as a small idle indicator; "Recording window: None" exists | Waveform; mode name (Super Mode shows the app/site); stop; cancel (esc; >30 s asks to confirm); live words with realtime models; a context indicator lights when clipboard/selected text was captured | Words appear in the window while speaking; no post-rewrite preview | Click the mode name or ⌥⇧K, before or during dictation; per-mode shortcuts (v2.12.0, 2026-04); auto-switch per app | Settings has Configuration/Sound/Advanced; History via right-click on the mini window; "Close after transcription" | The context indicator: you know something was read from the screen | "Intrusive", "big overlay window" (19 votes); setup 15–30 min, "overwhelming"; clipboard overwrite (12 votes); raw text pasted then replaced seconds later |
| VoiceInk [VI-Gen][VI-Sh][VI-Ctx][VI-572][PN-36] | Recorder Style: Notch (top, hugs the camera housing) or Mini (floating); a fork adds Pill and Dot with left/centre/right slots (record · meter · timer) | Recording, processing (fork: dot pulses grey, timer freezes so the take length stays visible), live text toggle | Live text under the recorder, "fixed two-line area showing the newest words" | ⌥1–0 picks a mode; a mode can own its own shortcut | Quick History panel; Paste Last (Original/Enhanced); Retry Last copies to clipboard rather than pasting | Screen context is local Vision OCR, "the screenshot image itself is not the context payload"; History can hold the text that was sent | ~1 s between trigger sound and capture because the window is rebuilt each time; fix proposed: show a "starting" state immediately |
| Aqua Voice [AE-AQ][PH-AQ] | Floating text box on the desktop (screenshot: bottom of a Word window) | Live text as you speak | The box *is* the preview: edit, then a keypress pastes | Style instructions, dictionary; no mode UI described | Not described | Interrupted or stopped recordings are kept | "Does not get pasted correctly" for long text; "feels out of place" vs dictating in the app |
| Raycast [R-D][R-57] | Pill "floats above your current app" with waveform and timer | Recording; accept = hotkey again; Esc cancels; 20-min cap | None before paste; Styles + Auto Styling choose format per app | Styles; context-aware paste shows the receiving app's name and icon | Dictation History: Paste / Copy / Delete / Regenerate / Retry on failed; Get Last Transcription; Vocabulary (50 words); stats | Receiving app named before paste | Pill did not follow the active Space (beta fix); now Pro-only (2.0, 2026-08-21) |
| Monologue [MO-C][MS-MO][AS-MO][MO-Site] | Small "monophone" window that hides off the right screen edge and slides out on the shortcut; teal waveform; skeuomorphic "iOS 6" look | Recording; the active mode is printed on the mini screen ("Coding" in Cursor) | None; lists pasted as bullets | Modes tabs (Chatting/Email/Notes/Coding) with custom instruction lists | Recent transcripts on the main screen; full local log; dictionary "Add word" | The app "gets out of the way" | "A lot of settings"; dictionary entries "go away"; "does not work in all applications" |
| Pastely [PA] | Menu bar; ⌘⇧V opens a preview panel | Preview panel: "on clipboard" block, "result" block, cancel (Esc) / paste ↩ | Always previewed; clipboard untouched until confirmed | Type an instruction in the target field, then ⌘⇧V | ⌘⇧H history: "text → WhatsApp · just now", ↑↓ then Return pastes | Header "pasting into Messages" with the app icon | Free tier is 4 transforms |
| FluidVoice [FV] | Live-preview overlay, notch-aware on notched Macs, standard elsewhere; size setting compact pill → larger panel → minimal | Recording; muted-mic icon when Hold-Space-to-Mute | Live preview in the overlay | Per-app prompts; Command and Write modes | Audio history with budget; today-usage pill in the toolbar; light/dark toggle | Overlay size is a user choice | macOS 15+ only |
| Handy [HA-GH][HA] | Menu bar icon lights while recording; "Overlay Position" setting includes None; overlay off by default on Linux because it steals focus | Recording | None | — | History view; Debug panel with paste delay | Overlay is optional | Overlay can appear empty on some Linux compositors |
| OpenWhispr [OW] | Hotkey; assistant replies paste at the cursor or open a floating panel + clipboard when no writable cursor | Not documented | None | — | Notes, meetings | Fallback to a panel when there is nowhere to type | UI undocumented |
| Apple dictation [AP-Dict] | No window: the cursor "is highlighted and pulsing" | Inline text at the insertion point; ambiguous words underlined blue, click for alternatives; stops on Esc or 30 s of silence | Inline, in-place | — | System Settings only | Zero chrome | Can't rewrite per app; UNVERIFIED whether Tahoe changed the indicator |
| macOS 26 Spotlight [AP-26] | Centre panel with Applications / Files / Actions / Clipboard buttons beside the field; quick keys; clipboard history; 26.1 adds a tinted-vs-clear glass setting | — | — | Buttons are the mode switcher | — | Clipboard history inside the launcher | — |
| Typeless, Willow, Talkify | No usable description of the Mac overlay found in docs or reviews [TL][WV]; "Talkify" returned no matching Mac app | UNVERIFIED | UNVERIFIED | — | Typeless: on-device history; select-text-and-speak edits | — | Typeless: 6-minute session cap, cloud-only (reviewer claims) |

## 2. Design-pattern notes

- **Notch HUDs.** Boring Notch expands on hover and replaces volume/brightness HUDs, macOS 14+ [BN]. Alcove: macOS 15+, $13.99, live activities, "closest to Apple's own animation" per roundups [AL]. NotchNook draws a fake notch on external displays, which MacStories called jarring, and its Now Playing floats above full-screen video [MS-NN]. The VoiceInk fork's rule is the sane one: Notch style on a notched built-in display, Mini elsewhere, and the camera housing is never a slot [PN-36]. BuildBetter already ships a notch-mounted dictation UI with live text [BB].
- **Floating pills, done right.** Freestyle's reconstruction of the Wispr pill: a 260×90 transparent panel-level window, non-focusable, shown inactive so the editor never loses the caret, 14 bars with a fast attack (0.55) and slow decay (0.22) per frame [FS]. VishPrompt's `HUDPanel` already does the non-activating part.
- **Menu bar.** HIG: "display a menu, not a popover" [HIG-MB]; done on `dev`. The icon should still change while recording (`VisprflowApp.swift` does not yet).
- **Command palettes.** Raycast's pill and Spotlight's buttons show the same split: a *tiny* live indicator, and a *big* panel only for browsing and choosing [R-D][AP-26]. History and Paste/Fix belong in the big one.
- **Inline ghost text.** Only Apple does it, and only because it owns the text system [AP-Dict]. Every third-party app shows live words in its own surface; `HUDView.swift` says why: "provisional text cannot be reliably retracted from the app being typed into." Keep that rule.
- **Liquid Glass (macOS 26).** "Regular" and "Clear" are "never mixed"; glass is "best reserved for the navigation layer that floats above the content"; "always avoid glass on glass"; "Tinting should only be used to bring emphasis to primary elements"; Reduce Transparency "makes Liquid Glass frostier", Increase Contrast "makes elements predominantly black or white … with a contrasting border", Reduce Motion "disables any elastic properties", all automatic [LG-219]. A HUD *is* that floating layer, so glass fits. APIs: `glassEffect`, `GlassEffectContainer`, `glassEffectID` morphs, macOS 26+; fall back to `.ultraThinMaterial` below 26 (API summary from the SwiftUI docs page, exact signatures UNVERIFIED until built) [LG-API]. 26.1 users may have picked "tinted"; design for both [AP-26].
- **Accessibility and motion.** The panel can never be key, so VoiceOver gets `announcementRequested` posts, not focus (already in the plan) [HIG-A11y]. Reduce Motion: no spring, no morph, crossfade ≤120 ms or cut [HIG-Mo][LG-219]. Colour never carries meaning alone: the mode chip has a word.
- **Undo.** Paste strategy so one ⌘Z undoes; name the undo in the inserted state [HIG-Undo].
- **Vish's frontend rules.** No fake precision: "about 0.7 s" not "0.73 s", no OCR percentages. Every empty/failed state = state + cause + action. No jargon in the HUD; status codes go to History.

## 3. Three concepts

Shared vocabulary: **anchor** = what you see while holding the key; **card** = what appears when there is a decision; **window** = History/Settings. Type: SF Pro, 13 pt callout for text, 11 pt caption for hints, 11 pt mono for the level chip. All copy below is final-draft, not placeholder.

### Concept A — "Island and Card" (recommended)

```
 ┌──────────────────────── menu bar ────────────────────────┐
 │   [Dictate] into Slack ·  ▁▃▅▇▅▃  0:07 · release to send  │  ← capsule hugs the notch
 └───────────────────────────┬──────────────────────────────┘    (or floats top-centre)
                             ▼ on release, only if something to decide
        ┌─────────────────────────────────────────────┐
        │ Dictate → Claude Code · COMPILED · on this Mac│
        │ You said: "fix the auth test, it's flaky"     │
        │ ┌─────────────────────────────────────────┐   │
        │ │ Goal: make test_auth_refresh pass …     │ ↑ │
        │ │ Error: (from screenshot, 23 lines) …    │ ↓ │
        │ └─────────────────────────────────────────┘   │
        │ Removed before sending: 1 AWS key (…F3QA)     │
        │ ⏎ insert  ⇥ level  ⇧⇥ back  R redo  esc       │
        └─────────────────────────────────────────────┘
```

- **Anchor.** Capsule 36 pt tall, min 280 pt wide, growing to 460 pt when live words appear; on a notched built-in display it is two lobes either side of the housing (left: mode chip + "into Slack"; right: 14-bar meter + m:ss), exactly the Pnoe slot rule; on any other display a free capsule 8 pt below the menu bar, centred. Glass `.regular` on macOS 26, `.ultraThinMaterial` below. Never covers the Dock, never covers a Send button (they are at the bottom), never covers the menu bar's own items (it sits below the bar, except the notch lobes which sit *in* the bar area that already holds nothing).
- **Recording.** `Dictate · into Slack · ▁▃▅ · 0:07 · release to send · esc`. Hands-free: `Hands-free · tap fn to stop`. Live words: a single 13 pt line under the lobes, newest words, head-truncated. Paste mode: `Smart paste · into Slack · say how, or just release`. Fix mode: `Fix screenshot · into Claude Code · 32 pt thumbnail · copied 40 s ago`.
- **Working.** Capsule stays; meter becomes a slow 3-dot pulse (static "…" under Reduce Motion); text: `Rewriting on this Mac` / `Rewriting via Claude subscription` / `Reading screenshot on this Mac ✓ · checking for secrets ✓ · writing…` (a step shows only if it takes >300 ms). Timer freezes so the take length stays visible (VoiceInk fork's rule).
- **Preview card.** Drops from the capsule's bottom edge with a 180 ms spring (crossfade under Reduce Motion); 480 pt wide, max 40% of screen height, scrollable, ↑↓ scroll. Header = mode chip · "→ Claude Code" · level chip (mono) · provider. "You said" line whenever the result is not the user's own words. Notes in secondary 11 pt. Footer = source line left, keys right. The old text stays dimmed at 45% with a header `Rewriting at Organised…` while ⇥ recompiles; each level cached; ⇧⇥ goes back; 1–4 jump.
- **Smart Paste card.** `Smart paste → Slack` · `On clipboard: text, 3 lines, copied 20 s ago` · result · `You said: "as bullet points"` · `⏎ paste · ⇥ format · ⌥⏎ paste original · esc`. Clipboard untouched until ⏎ (Pastely's rule). Empty clipboard: capsule only, `Clipboard is empty — copy something, then hold fn+V`, 3 s.
- **Fix card.** Sections Goal / Error (folded to 6 lines, `+17`) / Where / Verify; footer `Sent: your words + 23 lines of screenshot text → Claude subscription. The image stays on this Mac`; `⌥⏎ insert without screenshot text`. No text found: `No text found in the screenshot — it looks like a picture, or the text is very small. ⏎ send your words alone · R redo with ⌘⇧⌃4 · esc`.
- **Inserted.** Capsule only, 1.2 s: `Inserted into Slack · ⌘Z undoes` (green check). Paste: `Pasted into Slack · ⌘Z undoes`. Fix: `In Claude Code — not sent. Review, then press Return there`.
- **Errors.** Card, orange triangle, stays until a key-down or 6 s: `Slack isn't in front any more. Your words are copied — ⌘V where you want them.` / `Claude is overloaded (Anthropic 529). Your words are copied — ⌘V, or hold fn to retry.` / `Couldn't reach Claude (offline). ⏎ inserts your words as transcribed · esc`.
- **Cancelled.** Capsule, grey ×, 0.6 s: `Cancelled` or `Cancelled · kept in History` (recordings over 30 s).
- **History window (⌘Y, from Concept C).** Spotlight-shaped, 640×420 pt, search field on top, rows `fix the auth test → Claude Code · 2 min ago · stayed on this Mac`; right pane shows said / sent / result / timings; ⏎ pastes again, ⌘C copies, ⌘R re-runs at a level, Retry on failed. Also the privacy ledger.
- **Borrowed:** notch lobes and slots (VoiceInk, Pnoe), context indicator (superwhisper), app-name-before-paste (Pastely, Raycast), timer freeze (Pnoe), hide-for-an-hour via right-click (Wispr). **New:** the card appears *only when there is a decision*; the source line; the ledger-grade History.
- **Effort M.** Capsule geometry + notch detection (S), card transition (S), History window (M), glass with fallback (S).
- **Risks.** Notch geometry is not a public API: read `NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea` (macOS 12+) and `safeAreaInsets`; on external and non-notch displays fall back to the free capsule, never draw a fake notch (NotchNook's mistake) [MS-NN]. Full-screen apps hide the menu bar: the capsule then sits at the top edge like Wispr's flush rule [WF-Move]. Glass morphs need macOS 26; below that the capsule and card are two material shapes that crossfade. VoiceOver cannot reach the card: announce each state. Windows with a toolbar at the very top lose ~44 pt behind the card; the card is dismissible and the position is remembered if dragged (opt-in).

### Concept B — "Flow Bar plus ghost text"

```
  ┌ app window ─────────────────────────────┐
  │ Hey team, the deploy is┆fix the auth…   │  ← ghost (grey) words at the caret
  └──────────────────────────────────────────┘
                 ( ● ▁▃▅▇  0:07  Slack )       ← 70 px capsule, bottom-centre, draggable to a side
```

- Bottom-centre capsule like Wispr's, draggable to the left or right edge, remembers its place; recording shows a waveform and the destination; working shows a spinner; preview opens *upward* from the capsule as a 460 pt card; errors as a red capsule that stays. History and Settings in a Hub window with a sidebar (Home · Dictionary · Destinations · Providers · Privacy).
- Ghost text: live words typed into the target field as provisional grey text, replaced on release. Borrowed from Apple's inline dictation [AP-Dict].
- **Effort L.** Ghost text needs per-app AX writes or marked-text hacks; terminals, Electron and web fields disagree; the code already notes it cannot be reliably retracted. Preview-up-from-bottom collides with the Dock and with every bottom-anchored Send button, which is the exact complaint Wispr spent 2026 fixing [DT][PF]. Not recommended.

### Concept C — "Spotlight panel"

```
        ┌──────────────────────────────────────────────┐
        │ [Dictate] [Smart paste] [Fix]        [History]│
        │ 🎤  fix the auth test, it's flaky…            │
        │ ─────────────────────────────────────────────│
        │ → Claude Code · Compiled · on this Mac        │
        │ Goal …  Error …  Where …  Verify …            │
        │ ⏎ insert  ⇥ level  ⌘Y history  esc            │
        └──────────────────────────────────────────────┘
```

- One centred panel, 640 pt wide, that appears on key-down: a mode row (like Spotlight's Applications/Files/Actions/Clipboard buttons [AP-26]), a live-text field, then the preview, then keys. History is a tab in the same panel with search and ↑↓. Settings open from a gear in the corner.
- Borrowed: macOS 26 Spotlight, Raycast, Pastely's history list. New: Paste and Fix as first-class tabs you can also pick with the mouse.
- **Effort M.** Risks: it is far too much chrome for "hold fn, say 'ok', release": a 640 pt panel over the middle of the screen for a two-word Slack reply is what the superwhisper board calls "a big overlay window" [VB-SW]. It also covers the text you are replying to. Good as the History/Settings window; wrong as the moment-to-moment HUD.

## 4. Recommendation

**Build Concept A.** In plain words: while you talk, show the smallest honest thing (what mode, where it is going, that the mic hears you, how long); when you let go, show a card only if you have to decide something; put everything else in a window you open on purpose. That is what every well-reviewed competitor does, it stays away from the Dock and the Send button that Wispr's users rioted about, it does not fake a notch on a monitor that has none, and it keeps the two things that make VishPrompt different, the preview and the "what left this Mac" line, visible at the exact moment they matter. B's ghost text is the one idea nobody has shipped because macOS does not let a third party retract typed text safely. C is the right History window and the wrong HUD.

**Order.** 1) Capsule anchor + state copy (replaces the listening/transcribing/compiling rows); 2) card drop with cached levels and ⇧⇥; 3) notch lobes with the Mini fallback; 4) History window ⌘Y; 5) glass on macOS 26 with the material fallback; 6) menu bar icon that changes while recording.

## 5. Screens to mock up

1. Capsule, notched display: listening (Dictate / Smart paste / Fix), hands-free, working, inserted, cancelled.
2. Capsule, external display: the same five.
3. Preview card: Dictate compiled (short), Dictate compiled (long, scrolling), level recompile with dimmed text.
4. Smart Paste card: text clip; image clip (OCR); empty clipboard; too-long clip.
5. Fix card: full; no text found; secrets removed; no screenshot.
6. Error card: focus moved; provider overloaded; offline; secure input.
7. History window: list + detail; a failed row with Retry; a "stayed on this Mac" row vs a "sent to Claude" row.
8. Menu bar menu with the recording icon state.
9. Each of 1, 3 and 7 under Reduce Transparency, Increase Contrast, dark mode, and macOS 15 (no glass).

## 6. Sources (all read 2026-10-23)

- [WF-Pill] Pill shape/behaviour: Podfeet, "Dictate with Wispr Flow", 2026-03 — https://www.podfeet.com/blog/2026/03/wispr-flow-scott-willsey/ (page 403 on fetch; description via search summary) · PillFloat (sizes, 400 ms reset) — https://github.com/OrangeAKA/pillfloat
- [WF-Move] Move and Dock the Flow Bar — https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop · Troubleshooting — https://docs.wisprflow.ai/articles/5002934560-why-is-the-wispr-bar-is-not-appearing-or-disappearing
- [WF-Hub] Navigating the app — https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android · What is Flow — https://docs.wisprflow.ai/articles/2772472373-what-is-flow
- [WF-Cmd] Command Mode — https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode
- [WF-New] What's new (dated entries) — https://wisprflow.ai/whats-new
- [SP-WF] Spokenly Wispr review (Undo AI Edit, onboarding "polished") — https://spokenly.app/blog/wispr-flow-review
- [DT] Digital Trends, 2026-07-29 — https://www.digitaltrends.com/computing/wispr-flow-asked-its-haters-what-was-wrong-and-more-than-700-people-answered/
- [PF] PillFloat on Product Hunt — https://www.producthunt.com/products/pillfloat
- [FS] Freestyle, "How we built Wispr Flow's floating pill", 2026-06-08 — https://freestylevoice.com/blog/floating-pill
- [SW-Rec] superwhisper Recording Window — https://superwhisper.com/docs/get-started/interface-rec-window
- [SW-Ess] superwhisper Essential settings — https://superwhisper.com/docs/get-started/essential-settings · Advanced — https://superwhisper.com/docs/get-started/settings-advanced
- [VB-SW] Voibe superwhisper review (competitor; feedback-board votes as of 2026-04, updated 2026-10-12) — https://www.getvoibe.com/resources/superwhisper-review/
- [SP-SW] Spokenly superwhisper review (competitor) — https://spokenly.app/blog/superwhisper-review
- [VI-Gen] VoiceInk General settings — https://tryvoiceink.com/docs/settings-general · [VI-Sh] Shortcuts — https://tryvoiceink.com/docs/shortcuts · [VI-Ctx] Context awareness — https://tryvoiceink.com/docs/context-awareness
- [VI-572] VoiceInk issue #572 — https://github.com/Beingpax/VoiceInk/issues/572
- [PN-36] Pnoe (VoiceInk fork) PR #36, merged 2026-10-19 — https://github.com/techneissa/Pnoe/pull/36
- [AE-AQ] Aestumanda Aqua Voice review, 2025-08-27 — https://www.aestumanda.com/reviews/2025/08/aqua-voice-delivers-what-apples-dictation-still-lacks/
- [PH-AQ] Aqua Voice Product Hunt reviews — https://www.producthunt.com/products/aqua/reviews
- [R-D] Raycast Dictation manual — https://manual.raycast.com/ai/dictation · [R-57] Raycast v0.57, 2026-05-08 — https://www.raycast.com/changelog/macos/0-57
- [MO-C] Cassinelli, Monologue, 2026-03-10 — https://matthewcassinelli.com/recommended-apps-monologue-mac-ios/ · [MS-MO] MacStories — https://www.macstories.net/notes/monologue-notes-cli/ · [AS-MO] App Store reviews — https://apps.apple.com/us/app/monologue-smart-dictation/id6755956193?see-all=reviews · [MO-Site] https://www.monologue.to/
- [PA] Pastely — https://www.pastely.click/
- [FV] FluidVoice — https://github.com/altic-dev/FluidVoice
- [HA-GH] Handy — https://github.com/cjpais/Handy · [HA] https://handy.computer/
- [OW] OpenWhispr — https://github.com/OpenWhispr/OpenWhispr · https://docs.openwhispr.com/
- [TL] Typeless — https://www.typeless.com/ · [WV] Willow — https://willowvoice.com/ (neither describes the overlay)
- [BB] BuildBetter dictation (notch-mounted UI) — https://buildbetter.ai/recorder/dictation
- [AP-Dict] Apple, Dictate messages and documents — https://support.apple.com/guide/mac-help/dictate-messages-and-documents-mh40584/mac
- [AP-26] Apple, What's new in macOS Tahoe 26 — https://support.apple.com/en-us/122868
- [LG-219] WWDC25 "Meet Liquid Glass" transcript — https://developer.apple.com/videos/play/wwdc2025/219/
- [LG-API] SwiftUI, Applying Liquid Glass to custom views (body did not render; API names from the tool's summary) — https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- [BN] Boring Notch — https://github.com/TheBoredTeam/boring.notch · [AL] Alcove — https://tryalcove.com/ · [MS-NN] MacStories NotchNook/MediaMate, 2024-08-05 — https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/
- [HIG-MB] https://developer.apple.com/design/human-interface-guidelines/the-menu-bar · [HIG-A11y] …/accessibility · [HIG-Mo] …/motion · [HIG-Undo] …/undo-and-redo
- Not found: Reddit and Hacker News threads on these UIs (reddit.com unreachable from the tool; HN Algolia search returned no UI comments). Reddit sentiment is therefore UNVERIFIED and absent above.
