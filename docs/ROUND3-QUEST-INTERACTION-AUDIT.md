# Round 3 — quests + world interaction: audit

Branch `ui-foundation` @ `4c2eb46` · audited against the **live Studio place** on 2026-09-19 (the
disk mirror is stale for most of these files — see §7). Nothing was changed for this document.

## 1. Current quest systems

Every NPC questline is its own server module with its own pair of remotes; the client tracker reads
them all through one shape. Goals (the daily/weekly/lifetime board) is a different system.

| Questline | Server module | Remotes | Stored state | Payload the client gets |
|---|---|---|---|---|
| **Gianluca** — find the Secret Chim | `GianlucaQuest` | `GianlucaTalk` (client→server: nil = start, `"handover"`), `GianlucaState` | `data.ChimQuest` 0 none · 1 searching · 2 holding the Chim · 3 handed over (Key paid, Chim retired) | `{ State, Note }` — Note ∈ `found`, `key`, `hint`. **No Step/Of**: the tracker's own table supplies 1/2 · 2/2 |
| **Maxwell** — the cat's secret line | `MaxwellQuest` | `MaxwellTalk` (`"accept"`, `"claim"`), `MaxwellState` | `data.MaxwellQuest` 0 locked/offered (Rebirth ≥ 3) · 1 collect every Secret · 2 reach Rebirth 25 · 3 reward ready · 4 done | `{ State, Step, Of, Secrets, SecretsNeeded, Rebirths, RebirthsNeeded, Unlock, Note }` |
| **Elder Tung (valley)** — hand over 5 Epic / 5 Legendary / 2 Mythic | `TungQuest` | `TungTalk` (action, payload = picker uids), `TungState` | `data.TungQuest` 0 · 1 collecting · **2 derived** (everything still owed is in hand) · 3 done; `data.TungGiven` per tier | `{ State, Tiers = {Epic/Legendary/Mythic = {Have, Need, Left, Held, Placed}}, Step, Of = 12, Ready, Done, Unlocked, Keys, Note }` — Note ∈ `quota` (edge), `key` |
| **Elder Tung (tundra)** — trials + the drill | `TundraQuest` + `TundraQuestConfig` | `TundraTalk`, `TundraState` | `data.TundraQuest` = stage index 0..6, 7 = DONE; counters in `TundraProgress` / `TundraParts` | `{ State, Step, Of, StageId, Kind (count/gather/talk), Title, Track, Met, Parts, Stages, Done, Unlocked, Note, Cleared }` — Note ∈ `advance`, `cutscene:<id>` |
| **Michael** (code: Michel) — 5 mutated Sahurs | `MichelQuest` + `MichelQuestConfig` | `MichelTalk`, `MichelState` | `data.MichelQuest` 0 · 1 collecting · **2 derived** ready · 3 done | `{ State, Step, Of, Have, Need, Left, Held, Placed, Ready, Done, Darrels, Note }` — Note ∈ `quota`, `reward` |
| **Goals board** | `QuestHandler` | `QuestState` (list), `QuestClaim` | per-goal `Claimed`, live `Cur` | `[{ Id, Desc, Cur, Target, Met, Claimed, Reward, RewardKind }]`, refreshed every ~3 s |

Every `*State` remote re-sends on join (after the profile loads) and on every transition, so a
client that only listens still gets the whole picture. Server-side truth per stage:

- **Progress** — `Step / Of` on every questline except Gianluca (fixed per stage). Tung's real
  shape is three per-tier counts (`Tiers`), Tundra's "gather" stage is three part counts (`Parts`).
- **Return / turn-in** — Gianluca `State == 2` (bring the Chim back), Maxwell `State == 3` (claim),
  Tung `State == 2` / `Ready` (everything owed is in hand → one more visit), Michael `State == 2` /
  `Ready`, Tundra any stage with `Kind == "talk"` or a `count` stage with `Met == true` (the
  server advances the counter stages itself, so a Met count stage only shows when a quota was
  lowered under a live save).
- **Claimable** — only Maxwell 3 → 4 is a manual claim (`MaxwellTalk "claim"`); Goals claim from
  the Goals panel (`QuestClaim`). Every other reward pays on the hand-over / stage advance.
- **Complete** — every questline: `State` above its top stage (`GianlucaQuest 3`, `Maxwell 4`,
  `Tung 3`, `Tundra 7`, `Michel 3`). Nothing is "complete" until that state arrives.

## 2. The tracker today (`QuestTrackerClient`, live 59 KB, 1367 lines)

- A **"QUEST LOG"**: outlined white text floating straight on the world (the PS99 "naked text"
  pass of 2026-08-16 removed every plate), TRACKED / ALL / DONE tabs, a header counter ("3 ENTRIES"),
  a footer ("J · TOGGLE", "2 COMPLETED"), cards with a 2 px green/red accent bar, a title, a step
  line ("Collect every Secret 10/12") and a **3 px cyan progress line** with "10/12" beside it.
  Collapsed it becomes a vertical letter-ladder rail ("Q U E S T") on the right edge.
- Anchored top-right at y 264, 348 wide, `Platform.Widget() × 0.85`; clamps itself above the
  bottom-right cluster with `BOTTOM_RESERVE_PX = 274`; DisplayOrder 4 (12 while expanded on phone).
- **Table-driven**: `QUESTS = { Id, Npc, Remote, Kind, Steps[state] = {Title, Step, Of}, Objective(payload) }`
  with Tundra's steps generated from `TundraQuestConfig.Stages`. Adding an NPC is one entry.
  This is the strength to keep.
- Completion: the moment `State > TopStage` the entry flips to the DONE tab (no feedback beat).
  Progress changes repaint the text and snap the fill (no animation, no acknowledgement).
- Phone: boots collapsed, the rail is hidden on short phones, expanded goes to DisplayOrder 12.
- Persisted `questsHidden` (SettingsService) is shared with `HudToggleClient`, whose own quest
  button is built hidden; the toggle also slides `QuestBarUI` off. SideRail flips
  `QuestTrackerUI.Enabled` while any registered panel is open. Keyboard `J` toggles.
- The mirror on disk (13.7 KB) is the **old flat log** (dark translucent 286×72 rows, GAP 0) — the
  version the brief describes. Live is two rebuilds later. The pre-questlog file is in
  `ServerStorage.AuditBackups.QuestTrackerClient_pre_questlog`.

Screenshots of the current state are taken in the same sitting as the after-shots (the old
scripts are kept as `ServerStorage.AuditBackups.PreUIRound3_2026_09_19` and run once for the
"before" column of `round3-quest-interaction.html`).

## 3. The Goals bar today (`QuestBarClient`, live 19.8 KB)

One right-edge "nearest to complete" nudge for the Goals board: naked white text, a thin cyan
3 px track, `n/m` or a pulsing green READY!, a pink × to dismiss, `TOP_OFFSET = 165`, Widget scale,
yields to HUD panels and (round 2.5) to legacy shops on phone. It picks the best goal itself
(met and unclaimed first, then the highest fraction). Semantically separate from the NPC tracker
and it stays that way — it will share the card language, not the system.

## 4. World interaction prompts today

- **42 ProximityPrompts** in the world, **all `Style = Default`** (Roblox's own UI): 21 stall /
  NPC prompts across the three world copies (valley, Gardens, Tundra), 6 market stands, 12 plot
  LikePrompts (disabled until a plot is claimed), the Secret Chim pickup, the Cellar padlock, two
  Daily Wheels, Maxwell's PetPrompt. Keyboard `E`, gamepad `ButtonX`, `OnePerButton`, no line of
  sight, `HoldDuration` 0 for shops/menus, 0.3 for wheel/stand/like/Tung, 0.5 for Gianluca and
  Maxwell, 0.6 for the Chim. Distances 8–18.
- Runtime prompts: plot pads (`EquipPadPrompt` remote path), `StealService` raid prompts,
  `PlotFavoriteService`'s **FavPrompt** — the only `Custom` prompt in the game, drawn by
  `PlotFavoriteClient` (pink pill, key `F`).
- `StallPrompt.Bind(stall, promptName, onBound)` re-binds prompts across streaming; every stall
  client uses it. `NpcFocusClient` puts one white `Highlight` on the NPC (child model "NPC" or
  the rigged model) on `PromptShown` / off on `PromptHidden`.
- What the player sees: the stock Roblox prompt — grey rounded box, key glyph, "Talk" / "Open
  Shop" / "Browse" in the default font — over a world whose HUD is now bubble-type kit chrome.
  Action wording is inconsistent ("Open Shop" / "Browse" / "Open Sell Menu" / "Sell" / "Open" for
  the same stall type across worlds).

## 5. NPC dialogue today (`MerchantDialog`, live 35 KB)

- **One shared shell**, and every talking NPC already goes through it: Gianluca, Maxwell
  (`CatDialogueClient`), Elder Tung valley (`TungQuestClient`), Elder Tung tundra
  (`TundraQuestClient`), Michael (`MichelQuestClient`), Marco (`ClientMain`), Rocco / Enzo /
  Lil Miss / Gino (`MerchantClient`). Signature `Show(npcName, lines, accent, onDone, anchor,
  finalLabel, opts)` with `opts.DeclineLabel / OnDecline / RichText`.
- Good bones: a live **portrait** (the NPC's own model cloned into a ViewportFrame, posed from
  the world model every frame, framed on the rig's root), a name ribbon tinted by the caller's
  accent pair, a typewriter with a `wheelTick` blip, buttons that only appear once the line has
  finished, click-anywhere to finish typing, walk-away (> 24 studs) dismiss, HUD stand-down +
  blur + colour grade while talking, failsafes (death, respawn, 180 s).
- The shell is the **pre-round-2** kit: `UI.surface(... "panel")` box, `UI.button "green" /
  "tab"` choices, Gotham body copy. It reads as a different toolkit next to the Bag / shops.
  Position: bottom-centre, 640×150 + choices below, NPC stays visible.
- The quest pickers (Tung, Michael) are their own ScreenGuis at DisplayOrder 13 opened from the
  dialogue's primary button; out of scope beyond checking they still layer correctly.

## 6. Reusable architecture proposal

1. **`UIKit.QuestCard`** — one presentation component built from a plain table:
   `{ npc = { name, initial, accent = {c1,c2}, icon? }, title, blurb?, objective, current, required,
   state = "active" | "return" | "claim" | "complete", returnTo? }`. Kit plate (white shell,
   thick outline, soft depth), an NPC identity badge (accent plate + initial + an IconArt motif
   where one exists: `keyGianluca`, `crown`, `keyCellar`, `bolt`, `tag` — no invented asset ids),
   quest name, ONE objective line, a chunky `PanelChrome.bar`-style track with an animated fill
   and `n / m`, state chips (`RETURN TO …`, `CLAIM`, `✓ COMPLETE`). Expand/collapse: collapsed =
   objective + bar only. Event-driven; the only animation is a 0.35 s fill tween and a short pop.
2. **`QuestTrackerClient`** keeps its table and remote wiring; each entry gains an `Npc` identity
   block and a per-stage `Kind` (`objective` / `return` / `claim`), the per-questline `Objective()`
   composers stay. New behaviour: completion beat (bar settles → ✓ COMPLETE chip → dismiss after
   ~1.2 s, only after the server state says so), progress acknowledgement (fill tween + number pop
   + `wheelTick`), desktop shows up to 3 cards then a "+N more" chip, phone shows one primary card
   with a tap-to-cycle chip. `questsHidden`, `J`, the `Tracker` frame name and the SideRail /
   HudToggle contracts are preserved.
3. **`UIKit.InteractionPrompt`** + `InteractionPromptClient` — a custom presentation for every
   Default-style prompt: the client flips `Style` to `Custom` locally (a local-only property; the
   server's `HoldDuration`, distances, keys, `Enabled` and `Triggered` are untouched) and draws
   one kit pill per shown prompt: object name above, `[E] TALK` (key glyph from
   `KeyboardKeyCode` / `GamepadKeyCode`, a tappable button on touch), hold progress from
   `PromptButtonHoldBegan/Ended` over `HoldDuration`, a success flash on `Triggered`. Optional
   prompt attributes (`PromptState = "locked"`, `PromptHint`) for locked / unavailable states.
   `FavPrompt` (already custom) is skipped. Wording normalised from `ActionText` via a small
   verb map (`Open Shop` → `SHOP`, `Open Sell Menu` → `SELL`, `Browse` by stall → `SHOP` /
   `UPGRADE` / `CHARMS`, `Open Eggs` → `OPEN`).
4. **`MerchantDialog` restyle only**: the same API, staging and portrait; the box becomes a kit
   white shell (`PanelChrome.plate`), the name ribbon a kit accent plate, the choices
   `PanelChrome.button` (positive primary, secondary Leave), body copy in the kit read face.
   Per-NPC identity stays the accent pair (+ the portrait); nothing per-NPC is added.

## 7. Discrepancies (mirror vs live)

| File | Mirror | Live | Note |
|---|---|---|---|
| `QuestTrackerClient` | 13,675 B (old flat log) | 59,456 B (quest log) | two rebuilds newer live |
| `MerchantDialog` | 5,435 B | 35,270 B | live has the portrait / staging rebuild |
| `QuestHandler` | 5,562 B | 13,948 B | |
| `TungQuest` / `TungQuestConfig` | 5,234 / 1,437 B | 17,553 / 3,565 B | |
| `GianlucaQuest` | 8,901 B | 9,551 B | |
| `MichelQuest`, `TundraQuest`, `TundraQuestConfig`, `StallPrompt`, `NpcFocusClient`, `TundraQuestClient`, `TungQuestClient` | missing | present | never mirrored |

Studio is the source of truth; every file this round touches is re-synced to disk before editing.

## 8. Risks

- **Custom prompt style**: flipping `Style` locally must skip prompts other scripts already draw
  (`FavPrompt`) and must not touch `Enabled`; the stock UI is what handles gamepad/touch today, so
  the custom one has to reproduce the touch tap (`InputHoldBegin/End`) and the gamepad glyph.
- **Streaming**: prompts stream in and out (StallPrompt exists for that reason); the prompt UI must
  be created per `PromptShown` and torn down on `PromptHidden` *and* on the prompt being destroyed.
- **Dialogue staging** hides every other ScreenGui; the tracker's completion beat may land while a
  dialogue is up (a Tundra talk stage completes from inside the conversation) — the beat must
  survive being hidden and still dismiss.
- **Phone**: the right edge is already the control column; the tracker must keep its bottom
  reserve and the collapsed state, and the prompt pill must not sit under the thumb controls.
- **HudLayout**: `QuestTrackerUI` and `QuestBarUI` share the Tracker layer (10); the tracker is not
  a HudLayout stack member (deliberately), so its own clamp is what keeps it clear of the corner.
- Performance rules from the brief: no per-quest RenderStepped, no per-card Heartbeat, no endless
  tweens, no viewports in cards, no per-frame world scans.
