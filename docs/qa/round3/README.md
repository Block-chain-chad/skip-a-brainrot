# Round 3 QA — quests + world interaction

Branch `ui-foundation`, code at `b4f8334` + `d874708` (+ the post-approval fix commit), verified
2026-09-19 in Studio Play on the owner's profile (Team Create place 78783087742939). **Approved by
Balkan** with two final decisions: the phone card stays at 300 authored px, and the tracker chevron
is decoupled from the Goals bar (see "Post-approval fix"). The report is `round3-quest-interaction.html`
(open it from disk; the images are relative). The audit that preceded the build is
`docs/ROUND3-QUEST-INTERACTION-AUDIT.md`.

## What shipped

| Surface | Script(s) | Change |
|---|---|---|
| Quest card | `ReplicatedStorage.Modules.UIKit.QuestCard` (new) | one NPC quest from a plain table; badge + motif, title, one objective, bar with numbers, RETURN / CLAIM / COMPLETE chips, compact mode, fill tween + count pop, completion beat, `measure()` |
| Tracker | `StarterPlayerScripts.QuestTrackerClient` (rewritten) | same QUESTS table and remotes; whole-card fit (`QuestCard.measure`), `+N MORE` / `1 / 3 ▶` header pill, chevron + J, card tap, phone lane under the Goals bar, throw-cluster yield, short-phone hide |
| Prompts | `UIKit.InteractionPrompt` + `StarterPlayerScripts.InteractionPromptClient` (new) | every Default ProximityPrompt drawn as a kit board; Style flipped to Custom on the client only; keyboard / gamepad / touch glyphs; hold sweep; locked; success; boards stand down with the HUD; rig boards float above the head |
| Dialogue | `ReplicatedStorage.Modules.MerchantDialog` | kit plate + edge, shout-face ribbon (per-NPC accent kept), read-face copy, kit LEAVE / OK; nothing else |
| Goals bar | `StarterPlayerScripts.QuestBarClient` | painted on the kit with an orange GOAL chip; touch: right edge inside the jump band |

Backups of the pre-round-3 scripts: `ServerStorage.AuditBackups.PreUIRound3_2026_09_19`
(`QuestTrackerClient_pre`, `MerchantDialog_pre`, `QuestBarClient_pre`, disabled copies). They were
swapped in once for the "before" captures and swapped back from the staged sources.

## Captures

Desktop = Studio viewport 1891×785 (window parked at 1936×1040 on monitor 2, PrintWindow, never
activated). Phone = iPhone 16 device sim, 733×371 logical, screen crop 1230×624 of the window.

| File | What |
|---|---|
| `before-01-tracker-desktop.jpg` / `zoom-before-tracker.png` | Quest Log + naked Goals text |
| `after-01-tracker-desktop.jpg` / `zoom-after-tracker.png` | card stack, `+2 MORE`, Goals bar on the kit |
| `after-09-tracker-claim.jpg` / `zoom-after-claim.png` | Maxwell State 3 → CLAIM FROM MAXWELL |
| `after-10-tracker-compact-chips.jpg` / `zoom-after-compact-chips.png` | collapsed: two compact chip cards |
| `after-11-tracker-showall.jpg` | SHOW ALL (scrolling list) |
| `strip-progress.png` | 10 → 11 / 12: fill tween + count pop (120 ms burst, frames 9 / 10 / 11 / 14) |
| `strip-completion.png` | CLAIM → ✓ COMPLETE → dismissed → next card (250 ms burst, frames 3 / 6 / 7 / 8) |
| `before-02-talk-prompt.jpg` / `zoom-before-prompt.png` | stock prompt at Gianluca |
| `after-02-talk-prompt.jpg` / `zoom-after-prompt.png` | kit board, above the head |
| `strip-hold.png` | hold sweep at 150 ms (idle / mid-sweep / settled) |
| `after-08-shop-prompt.jpg` / `zoom-after-shop-prompt.png` | Rocco's SHOP board |
| `before-03-dialogue.jpg` / `zoom-before-dialogue.png` | old shell |
| `after-03-dialogue.jpg` / `zoom-after-dialogue.png` | kit shell, boards hidden |
| `before-04-phone.jpg` / `zoom-before-phone-column.png` | letter rail + naked goals under the jump button |
| `after-04-phone-compact.jpg` / `zoom-after-phone-column.png` | phone column: Goals bar + compact card |
| `after-05-phone-expanded.jpg` / `zoom-after-phone-card.png` | expanded phone card |
| `after-06-phone-tap-prompt.jpg` | TAP · TALK board (module rendered with the Touch input type) |
| `after-07-phone-dialogue.jpg` | dialogue at the phone fit |

## Post-approval fix (chevron ≠ Goals bar)

`QuestTrackerClient` only. The chevron (and a card tap) now drive a session-local `cardsCompact`
(phone boots compact; the chevron's first press takes over from the device default). J and the
persisted `questsHidden` drive `setHidden`: the stack slides off the right edge (0.22 s out, 0.28 s
Back-ease in; a server-driven value on join snaps) and HudToggleClient folds the Goals bar on the
same setting, unchanged. HIDE UI (navHidden: rail + tab bar) untouched. Re-test:

| Size | Chevron | J | J again | HIDE UI | HudAudit | Overlap |
|---|---|---|---|---|---|---|
| Desktop 929×771 / 1891×785 | cards 117 → 67, Goals bar stays at 611,165 | tracker right edge 1269 vs 929, Goals bar folded (gui disabled) | back at 611,264; Goals bar back | rail + tabs fold, tracker + Goals bar untouched | 0 problems | 0 hits |
| Laptop 1366×766 | — | right edge 1706 vs 1366, Goals bar folded | back at 1048,264; Goals bar back | — | 0 problems | — |
| iPhone 16 733×371 | boots compact (44px card) | right edge 1073 vs 733, Goals bar folded | back at 401,211; Goals bar back | — | footprint lines only (accepted) | 0 hits |

Console: zero new errors or warnings. `questsHidden` left `false` (two J presses per size).
Capture: `after-12-compact-goals-stay.jpg` / `zoom-after-compact-goals-stay.png`.

## Numbers

Tracker geometry (authored px; the phone wears `Platform.Widget()` = 0.598):

- Card heads 44 (desktop) / 52 (phone, `max(44, sz16+sz22)`); objective measured with
  `TextService:GetTextSize` at the card's inner width (276) — agrees with the live AutomaticSize
  label to the pixel (15 = 15); bar 22; chip 26; pads 12; gaps 6. Full card 117, +4 with a chip,
  +15 per extra objective line; compact 67 (bar) / 71 (chip); phone compact floor 74 (44px on the
  glass).
- Desktop room = (viewH − 274) − max(264, …) − 36. 1891×785 → 153 → 1 full card or 2 compact;
  1366×766 → 1 card (bottom 419, HIDE UI at 446); 1080p (951 usable) → 3 cards (403 of 413).
- Phone lane = 211 → 305 of 313 (Goals bar bottom 203 + 8; bottom pad 8). Compact stack 211–278,
  expanded 211–309. Yields while `MainUI.ThrowFrame` is visible; hidden when
  `Platform.IsShortPhone()`.
- Progress update sampled at 30 ms: fill 0.92 → 0.94 → 0.96 → 0.98 → 0.99 → 1.00 over 0.35 s,
  count Position −2 → −3 → 0; `wheelTick` at 0.19 (0.25 × the SFX slider).
- Completion sampled at 50 ms: chip +0.30 s, dismiss starts +1.5 s (holder x 31 → 125 → 282),
  gone +1.75 s, header 3 → 2 ACTIVE, `wheelWin` once.
- Hold sweep (Gianluca, 0.5 s) sampled at 100 ms: fill 0.14 / 0.40 / 0.67 / 0.90 then 0 / 0 after
  Triggered.

Prompt glyph table, rendered by `InteractionPrompt.attach` for the same prompts:

| Prompt | Keyboard | Gamepad | Touch | Verb | Object |
|---|---|---|---|---|---|
| TalkPrompt (hold 0.5, dist 11) | E | X | TAP | TALK | Gianluca |
| ChimPrompt (hold 0.6, dist 12) | E | X | TAP | TAKE | ✨ Secret Chim |
| ShopPrompt (dist 15) | E | X | TAP | SHOP | Rocco the Rock Dealer |
| SpinPrompt (hold 0.3, dist 14) | E | X | TAP | SPIN | Daily Wheel |
| CellarPrompt (dist 12) | E | X | TAP | UNLOCK | Cellar |

Board `MaxDistance = max(MaxActivationDistance + 6, 12)`; locked pill fill #B9C2CC. No prompt
property was written except `Style` (client-side).

## Audits

`HudAudit.Measure()` at native sizes (position + overlap + under-control + footprint + touch):

- Desktop 929×784 and 1891×785: 3 problems, all pre-existing (MainUI tabs "under topbar").
- Laptop 1366×766: tracker overlap scan 0 hits; HudAudit lines for the changed surfaces: none.
- Phone 733×371: before the round the Goals bar sat 56–83% under the jump control (4 lines);
  after: 0 under-control hits, 0 overlaps, 0 small targets. Remaining lines for these surfaces are
  FOOTPRINT width only (Goals bar plate 24%, tracker card 24%; cap 18%) — deliberate, see the
  report's "Known and deliberate".
- `HudAudit.Run()` size checks on Phone short / small / tall, Tablet, Tablet 4:3, Laptop 768p,
  Desktop: only the same width footprint lines on the touch profiles; short phone shows no
  tracker (hidden by design); laptop and desktop clean.

Painted-leaf overlap scan (every visible TextLabel / Image / painted Frame in every other
ScreenGui against the tracker rect, full-screen backdrops excluded): 0 hits on desktop, laptop and
phone, compact and expanded.

Console: zero new errors or warnings from the six changed scripts across every session; the one
warning present is the pre-existing `[UIKit] panel module PetAbilityHelp did not return { Id, Build }`.

## Repro notes

- Progress / state tests come from a **Server** `execute_luau` that `FireClient`s the real remote
  with the real payload shape (`MaxwellState { State, Step, Of, Secrets, … }`, `TungState { State,
  Ready, Tiers, … }`, `MichelState { State, Ready, … }`); nothing is written to the profile. The
  server's next real push restores the true state.
- Clicks on the desktop viewport: `user_mouse_input` by instance path (`…Header.More.MoreHit`,
  `…Header.Collapse.CollapseHit`, `…List.MaxwellHolder.MaxwellCard`, `…Choices.LeaveSlot.Leave`);
  `user_keyboard_input` J toggles the fold. The device sim does not take mouse input — phone
  interactions were driven with `ReplicatedStorage:SetAttribute("PlatformOverride", "Phone")` on
  the desktop viewport, then cleared.
- Prompt lifecycle: two client-side Parts with prompts on E and F five studs ahead of the
  character (both boards), destroy one (board gone), disable the other (board gone).
- `questsHidden` was left `false`, the value it had on join (the chevron / J tests toggled it an
  even number of times).
- Captures: `r3win.ps1 show` = `ShowWindow(SW_SHOWNOACTIVATE)` + `SetWindowPos(after the Claude
  window, 1912,-59 1936×1040, SWP_NOACTIVATE)`; `r3cap.ps1` crops the 3D viewport at
  (11,175 1891×785) or the sim screen at (334,240 1230×624) — both measured by a magenta corner
  marker ScreenGui; `r3win.ps1 restore` puts the window back to 1936,-51 974×1026 and
  `SW_SHOWMINNOACTIVE`. The owner was in a fullscreen game the whole time; foreground never changed
  to Studio.
