# Chunky-Cartoon UI Overhaul (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the game's HUD and six core panels (Season Pass, Backpack, Settings, Daily, Index, Goals) with the chunky-cartoon design kit, wired to the existing server systems with zero new client authority.

**Architecture:** Kit modules installed as `ReplicatedStorage.Modules.UIKit.{Tokens,Builders}`; one `GameHUDClient` LocalScript owns the 1350×775 scaled canvas, currency cluster, right nav rail, scrim and panel host; each panel is a focused ModuleScript in `StarterPlayerScripts.GameHUDPanels` exporting `build(host, ctx)` / `refresh(state)`. Old surfaces retire by `Enabled=false` / `Visible=false` — never deleted. Single-open stays on the existing SideRail registry (visual rail hidden).

**Tech Stack:** Roblox Studio via MCP (execute_luau Edit, script_read/multi_edit), Luau, kit files at `docs/design-handoff/ui-kit/design_handoff_game_ui/` (VISUAL AUTHORITY), existing remotes (SeasonState/SeasonClaim, DailyState/DailyClaim, QuestState/QuestClaim, DataUpdated, EquipBrainrot, DarrelUpdate/DarrelState), BrainrotThumb for 3D art slots.

## Global Constraints

- Spec: `docs/specs/2026-07-30-ui-overhaul-design.md`. Kit README numbers are FINAL — reproduce exactly; only labelled art slots stay placeholder.
- ALL Studio work through MCP; execute_luau ALWAYS `"Edit"` except Tasks 4 and 11 (the only Play owners). NEVER save/publish. THREE collaborators may be live: script_read anchors immediately before every edit of an existing script; back up every edited existing script to `ServerStorage.AuditBackups.<Name>_pre_ui<task#>`.
- NEVER touch: UIStyle, TradeClient, BoothClient, ThrowHandler, ClientMain SOURCE (the cash pill is hidden via instance property from the new HUD, not by editing ClientMain), booth/plot world objects.
- Old panels retire via `.Enabled = false` on their ScreenGuis at GameHUD startup (runtime, reversible), and their LocalScripts get ONE guard line only where a script would error with its gui disabled — prefer zero edits.
- The bridge require() cache is contaminated: verify modules via fresh CLONE requires (clone beside original, require, destroy, verify destroyed).
- After ANY screen_capture: `workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed` (standing rule).
- Per task: dump created/edited Sources to `game-src/ui/<Name>.lua`, commit with the task's message. Fresh-clone compile probe (loadstring) for every new/edited script before commit.
- Text: never below 13px; touch targets never below 44px (kit rule).

---

### Task 1: Reference captures — pixel targets from the interactive kit

**Files:**
- Create: `docs/design-handoff/ui-kit/captures/{hud,pass,backpack,settings,daily,index,goals,stylekit}.png`

**Interfaces:** Produces the visual-target PNGs every later task's verification compares against.

- [ ] **Step 1:** Serve the kit folder: run in background `python -m http.server 8377 --directory "C:\Users\m\Coding\skip-a-brainrot\docs\design-handoff\ui-kit\design_handoff_game_ui"`.
- [ ] **Step 2:** Open the Browser pane at `http://localhost:8377/game-ui-reference.html`, resize to 1366×775-ish desktop. Screenshot the initial HUD state → save as `hud.png` (browser screenshot tool output saved via the scratchpad then copied into captures/).
- [ ] **Step 3:** Click each nav-rail item in turn (Bag, Pass, Daily, Goals, Index, Settings — use read_page to find them); screenshot each open panel → the six panel PNGs. Click "STYLE KIT ↗" → `stylekit.png`.
- [ ] **Step 4 — icon rasterization:** while the server runs, open each of the 8 SVGs at `http://localhost:8377/icons/<name>.svg` in the Browser pane, viewport sized so the icon renders ≥512px, screenshot, crop to the icon's square, save as `docs/design-handoff/ui-kit/captures/icons/<name>_512.png` (Python/Pillow crop; verify each PNG by Reading it — correct silhouette per README §6.1 table, transparent/white background noted).
- [ ] **Step 5:** Kill the server. Verify 8 panel PNGs + 8 icon PNGs exist and each shows the right content (Read each; name what's visible).
- [ ] **Step 6:** Commit — `git add docs/design-handoff/ui-kit/captures && git commit -m "ui(1): reference captures + rasterized icon set"`

### Task 2: Install UIKit modules

**Files:**
- Create: `game.ReplicatedStorage.Modules.UIKit` (Folder) › `Tokens` (ModuleScript), `Builders` (ModuleScript)
- Source: kit `tokens.lua` and `ui_builders.lua` VERBATIM, with only these adaptations:
  1. `Builders` line `local T = require(script.Parent.tokens)` → `require(script.Parent.Tokens)`.
  2. Append to Builders (README-specified, missing from the file): `UI.rainbowRing(card, radius)` — 5px ImageLabel ring frame using a generated rainbow UIGradient stroke fallback (no texture asset yet): Frame size (1,10,1,10) at (-5,-5), transparent bg, UIStroke Thickness 5 with a UIGradient on the stroke cycling `#FF5252→#FFB200→#7CE04A→#3FA9F5→#A855F7` (Rotation animated 0→360 over 6s via a single shared Heartbeat driver stored in the module — one connection total, registry cleaned when ring.Parent == nil, matching the RarityFX pattern); `UI.badge(parent, value)` — red notification pill min-width 30, height 30, stroke 3.5, text 16; `UI.ribbon(parent, text, variant)` — chip-height 24 ribbon (EQUIPPED/GRAND/NEW).
- Snapshot: `game-src/ui/UIKitTokens.lua`, `game-src/ui/UIKitBuilders.lua`

**Interfaces:** Produces `UIKit.Tokens` (T.color/gradient/stroke/radius/shadowOffset/gloss/pad/size/font/text/tween/zindex per the kit file) and `UIKit.Builders` (UI.corner/stroke/gradient/gloss/hardShadow/label/surface/panel/button/track/setFill/artSlot/rarityFrame/claimRing + the three additions). Every panel task builds ONLY through these.

- [ ] **Step 1 (failing probe):** `game.ReplicatedStorage.Modules:FindFirstChild("UIKit")` → nil.
- [ ] **Step 2:** Create the folder + both ModuleScripts; Sources = the two kit files (Read them from the handoff folder) with the listed adaptations. `Enum.Font.FredokaOne` exists in this Studio (font proof board precedent) — keep it.
- [ ] **Step 2b — icon upload PILOT:** attempt programmatic upload of ONE rasterized icon (coin_512.png) as a real image asset: read the PNG bytes → base64 chunks → execute_luau `AssetService:CreateEditableImage` + pixel writes → `AssetService:CreateAssetAsync(editableImage, Enum.AssetType.Image, ...)` (exact API signature: probe what this Studio exposes first — pcall everything, quote errors). SUCCESS → record the returned asset id in `game-src/ui/icon-assets.md`, upload the remaining 7, add `Tokens.icons = { coin = "rbxassetid://...", gem = ..., bag = ..., pass = ..., daily = ..., goals = ..., index = ..., settings = ... }`. FAILURE (API absent/permission denied) → write the fallback note in the report: USER STEP "Asset Manager → Bulk Import the 8 PNGs from captures/icons/", `Tokens.icons` ships with empty strings + labelled slots render as kit placeholders until ids arrive. Either way the panels consume `Tokens.icons[name]` and degrade gracefully to labelled slots on empty string.
- [ ] **Step 3 (probes):** fresh-clone require Tokens → `T.size.canvas == Vector2.new(1350,775)`, `T.text.panelTitle[1] == 44`; fresh-clone require Builders → all 16 functions present (list them); build a smoke instance tree in a throwaway Folder (button + track + label), assert child classes (UICorner/UIGradient/UIStroke counts), destroy.
- [ ] **Step 4:** Snapshot + commit — `ui(2): UIKit tokens + builders installed (kit-verbatim + 3 README builders)`

### Task 3: HUD shell — canvas, currency, rail, panel host, retirements

**Files:**
- Create: `game.StarterPlayer.StarterPlayerScripts.GameHUDClient` (LocalScript), `game.StarterPlayer.StarterPlayerScripts.GameHUDPanels` (Folder, empty)
- Modify: `game.StarterPlayer.StarterPlayerScripts.QuestTrackerClient` (holder reposition — exact edit below)
- Snapshot: `game-src/ui/GameHUDClient.lua`, `game-src/ui/QuestTrackerClient.lua`

**Interfaces:** Produces the `ctx` every panel module receives: `{ Tokens, Builders, remotes, host = <panel mount Frame>, openPanel(id), closePanel(), setBadge(id, n), state = <client state table per spec §5> }`. Panel registration: `GameHUDClient` requires each ModuleScript in GameHUDPanels at startup via `for _, m in GameHUDPanels:GetChildren()` — a panel module returns `{ Id = "pass", Build = function(ctx) -> Frame }`; missing panels are skipped silently (panels arrive in later tasks).

- [ ] **Step 1 (failing probe):** no GameHUDClient exists.
- [ ] **Step 2 — canvas + scrim + host:** ScreenGui `GameHUD` (IgnoreGuiInset=true, ResetOnSpawn=false, ZIndexBehavior=Sibling, DisplayOrder 7); root Frame 1350×775 centred with UIScale and the README `fit()` (recompute on `workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize")`). Scrim (full-canvas, T.scrim/scrimAlpha, ZIndex 25, Visible=false). Panel host Frame (ZIndex 26; kit layout: padding-right 132, padding-left 24).
- [ ] **Step 3 — currency cluster** (top 18/left 18, per kit §3.7): coin pill (goldSmall, 38px icon slot labelled `coin`, value from the same data ClientMain's cash label uses — connect `remotes.DataUpdated.OnClientEvent` payload `.Cash`, and seed from `remotes.GetInitialData:InvokeServer()` the way other clients do — read one for the exact call shape) + gem pill (T.gradient.gem, icon slot `gem`, darrels via `DarrelUpdate.OnClientEvent` + `DarrelState:InvokeServer()` seed in task.spawn+pcall). Number formatting: same abbreviation helper family as DarrelHUDClient used (read it; replicate locally). Pop tween on increase only (T.tween.pop).
- [ ] **Step 4 — nav rail** (right 16, centred, gap 10, order Bag·Pass·Daily·Goals·Index·Settings, item 98×88 goldSmall, icon slot + label 14, active ring, hover/press per kit §4): clicking toggles `openPanel(id)`/`closePanel()`. `openPanel`: scrim fade in (T.tween.scrim), panel scale 0.92→1 Back/Out, currency cluster hidden, rail stays (ZIndex 30 above scrim); close reverses (0.12 Quad/In). Wire ESC via `UserInputService.InputBegan` (Keycode.Escape → closePanel, gameProcessed-guarded).
- [ ] **Step 5 — single-open + legacy integration:** require SideRail; `SideRail.registerPanel(<the panel host frame>)` so legacy surfaces (wheel, egg shop, fusion, shop/sell...) and the new HUD close each other; ALSO hide SideRail's visual rail permanently: `script_read` SideRail for its rail-frame variable and set the rail's container `Visible = false` via a new exported no-op-safe call if one exists, else at GameHUD startup find `PlayerGui.SideRailUI.LeftRail` and set Visible=false + disconnect nothing (its tiles remain functional but invisible; panel opening now goes through the new rail only). Legacy panel guis retire at startup: for each of `DailyUI, QuestUI, SeasonUI, IndexUI` (+ the Backpack panel's gui — read BackpackClient for its ScreenGui name) set `.Enabled = false` after WaitForChild with 5s timeout + nil-guard. Old currency: `PlayerGui:WaitForChild("MainUI"):WaitForChild("CashFrame").Visible = false`; `PlayerGui:FindFirstChild("DarrelHUD")` → `.Enabled = false` (timeout-guarded).
- [ ] **Step 6 — quest tracker move:** in QuestTrackerClient, anchor on its holder Position line (right-edge `Position = UDim2.new(1, -14, 0.40, 0)` with `AnchorPoint (1, 0.5)` — read the real values first) → left edge below currency: `AnchorPoint = Vector2.new(0, 0.5)`, `Position = UDim2.new(0, 14, 0.42, 0)`. Back up first. One-line edit + matching comment.
- [ ] **Step 7 (probes):** fresh-clone loadstring compiles; grep own Source: exactly one UIScale fit connection, openPanel/closePanel/setBadge defined, zero references to UIKit internals beyond Tokens/Builders; QuestTrackerClient edit quoted before/after.
- [ ] **Step 8:** Snapshot + commit — `ui(3): GameHUD shell — canvas, currency cluster, nav rail, retirements, tracker moved left`

### Task 4: PLAY CHECKPOINT 1 — shell verification

**This task owns Play mode.** Enter Play (get_studio_state first; coordinate — user may be testing).

- [ ] **Step 1:** Console: zero red errors at boot; legacy guis report Enabled=false (Client VM reads); MainUI.CashFrame invisible; DarrelHUD disabled; SideRail LeftRail invisible.
- [ ] **Step 2:** Screenshot HUD idle vs `captures/hud.png` — currency pills top-left (values live: cash matches leaderstat-era value, gems = darrel balance), rail right with 6 items, labels legible. Measure rail item AbsoluteSize ≥ 44px at the live viewport.
- [ ] **Step 3:** Click each rail item (user_mouse_input at measured centres): host opens with scrim (panels are empty Frames this checkpoint — expected), currency hides, rail stays clickable above scrim, ESC closes, currency returns. Legacy check: walk to the egg stall, open the egg shop via prompt → new HUD host closes if open (registry works both ways) — verify with the wheel too (walk into ring).
- [ ] **Step 4:** Quest tracker renders on the LEFT below currency; no overlap with pills (measure rects). LuckChip/Sprint/BAG unchanged bottom.
- [ ] **Step 5:** Stop Play. Camera → Fixed. Report per-check verdicts + screenshots. Fix loop per SDD if failures.

### Task 5: Season Pass panel

**Files:** Create `GameHUDPanels.PassPanel` (ModuleScript) · Snapshot `game-src/ui/PassPanel.lua`
**Interfaces:** Consumes ctx (Task 3) + `remotes.SeasonState` (read SeasonClient first for the request/payload shape: tiers, xp, xpNeed, level, claimed) + `remotes.SeasonClaim(tier)` → server validates. Produces `{ Id = "pass", Build }`.

- [ ] **Step 1:** `script_read` SeasonClient fully — record the exact SeasonState payload fields and claim remote signature in the report; the panel is a NEW consumer of the SAME contract.
- [ ] **Step 2:** Build per kit §3.1 EXACTLY (widths/heights/gaps as written): header (gold, icon slot, title, purple Quests button → `ctx.openPanel("goals")`, close), progress row (ticket slot, XP track via UI.track/setFill, level badge, Skip button — **Skip HIDDEN**: `Visible=false` until a product id exists, per spec), label column with `Rotation = -90` track labels, horizontal ScrollingFrame (3 rows: free cards / tier badges / pass cards, 178-wide columns, ScrollBarThickness 10, ElasticBehavior Never), reward cards per kit spec with the three states (LOCKED lock badge / CLAIMABLE ring+pulse+CLAIM pill via UI.claimRing / CLAIMED overlay+✓) driven by the state machine in kit §5, bottom CTA = **disabled variant "COMING SOON"** (spec: no gamepass yet), side column (196, two rainbow-ring tier-50 previews via UI.rainbowRing).
- [ ] **Step 3:** Free-track claim: CLAIM pill → `SeasonClaim:FireServer(tier)`; re-render on next SeasonState/DataUpdated (server-confirmed only — NEVER flip state locally; kit §5 rule).
- [ ] **Step 4 (probes):** compile; grep: no local claimed-state mutation (`claimed[` writes absent client-side), Skip button Visible=false, CTA disabled variant; card count == tier count from a fresh SeasonConfig clone-require.
- [ ] **Step 5:** Snapshot + commit — `ui(5): Season Pass panel — kit-exact, server-confirmed claims, pass CTA gated`

### Task 6: Goals panel (consolidation)

**Files:** Create `GameHUDPanels.GoalsPanel` · Snapshot `game-src/ui/GoalsPanel.lua`
**Interfaces:** Consumes: Daily tab ← `DarrelUpdate/DarrelState` payload `.Daily.Quests` (`{Id,Text,Reward,Target,Progress,Claimed}`); Goals tab ← `QuestState/QuestClaim` (read QuestClient for shapes); Season tab ← SeasonState's quest slice (read SeasonClient; if the pass has no quest slice, the tab renders the season-pass XP sources as info rows — decide from what SeasonState actually carries and DOCUMENT which). Produces `{ Id = "goals", Build }`.

- [ ] **Step 1:** Read all three source clients; record the three payload shapes verbatim in the report.
- [ ] **Step 2:** Build per kit §3.6: purple header + refresh chip (Daily tab: darrel UTC rollover countdown — compute from `os.time()` next-UTC-midnight), three tabs (rename kit's Weekly → "Goals"), quest rows per spec. Daily rows: server auto-claims → no Claim button; render IN_PROGRESS bar or CLAIMED ✓ (+reward chip shows `+N 💎`). Goals rows: full Claim flow via QuestClaim, server-confirmed re-render. Season rows: claim via the pass panel (row action = "VIEW" button → `ctx.openPanel("pass")`) unless SeasonState exposes a direct quest-claim remote (use what exists; do not invent).
- [ ] **Step 3 (probes):** compile; tab content swaps instantly (kit §4); zero local claim mutations; countdown formula probe: at a mocked os.time the chip renders `HH:MM:SS` to next UTC midnight.
- [ ] **Step 4:** Snapshot + commit — `ui(6): Goals panel — three quest systems consolidated`

### Task 7: Daily Rewards panel

**Files:** Create `GameHUDPanels.DailyPanel` · Snapshot `game-src/ui/DailyPanel.lua`
**Interfaces:** Consumes `DailyState/DailyClaim` (read DailyRewardClient for payload: streak day, claimedToday, reward table {500,1k,2.5k,5k,10k,25k,100k}). Produces `{ Id = "daily", Build }`.

- [ ] **Step 1:** Read DailyRewardClient; record shapes.
- [ ] **Step 2:** Build per kit §3.4: header + RESETS IN chip (UTC-midnight countdown, 1s task.spawn loop gated on panel visible), streak row, 7 cards (day 7 flex 1.45 + rainbow ring + GRAND ribbon), states per kit §5 Daily; art slots show the reward amount as gold text (spec: until art exists). Claim → DailyClaim:FireServer, server-confirmed re-render, claim-resolve motion per kit §4 (✓ pop → coin flies to the coin pill position via ctx-provided pill anchor — expose `ctx.pillAnchor("coin"|"gem") -> Vector2` from Task 3's cluster; ADD it to GameHUDClient if not present, one function).
- [ ] **Step 3 (probes):** compile; countdown gated (no timer when panel hidden — grep the visible-gate); 7 cards, day7 ring present.
- [ ] **Step 4:** Snapshot + commit — `ui(7): Daily panel — kit-exact with claim fly-to-pill`

### Task 8: Backpack panel

**Files:** Create `GameHUDPanels.BackpackPanel` · Snapshot `game-src/ui/BackpackPanel.lua`
**Interfaces:** Consumes DataUpdated brainrot list (read BackpackClient: grouping by name+mutation, richest-first, held-uids, EquipBrainrot remote, BrainrotThumb.add for 3D tiles). Produces `{ Id = "backpack", Build }`.

- [ ] **Step 1:** Read BackpackClient fully; reuse its grouping/order logic verbatim (copy the functions, cite them).
- [ ] **Step 2:** Build per kit §3.2 with spec deltas: header counter "N brainrots · M/6 held" (not slots); category tabs (USER DECISION) = **Brainrots / Pets / Charms / Eggs** (152 wide, kit tab spec; icons: `Tokens.icons.bag` for Brainrots, labelled placeholder slots for the other three until the design tool delivers). Brainrots tab: tier sub-filter chips (All/C–R/E–L/M+/Held, kit filter-chip spec) above the 5-col × 118 grid; tile = kit slot + BrainrotThumb 3D render + rarity frame (Common/Uncommon→common, Rare→rare, Epic→epic, Legendary→legendary, Mythic/Secret/God→UI.rainbowRing) + ×N quantity + EQUIPPED ribbon; detail column (hero render, name, rarity chip, stat rows: $/s, mutation, count; Equip/Unequip via the exact toggleHold flow BackpackClient uses). Pets tab: if `PetConfig.ENABLED == false` (fresh-clone read) → kit-styled empty state ("Pets hatch soon!" + art slot), else data.Pets grid + PetEquip wiring (build the enabled path too — it ships dormant). Charms tab: `script_read` UpgradeHandler for owned-upgrade/charm data shape; grid of owned charms if a shape exists, else empty state "Visit Enzo the Upgrader!" — DOCUMENT which branch shipped. Eggs tab: empty state "Crack eggs at Gino's stall!" + art slot (eggs are not held items today).
- [ ] **Step 3 (probes):** compile; CanvasPosition reset on open (the stage-1 gotcha); one Heartbeat max (rainbow rings shared driver only); grid rebuild on DataUpdated debounced 0.25s.
- [ ] **Step 4:** Snapshot + commit — `ui(8): Backpack panel — 3D tiles, tier tabs, held mechanics`

### Task 9: Index panel

**Files:** Create `GameHUDPanels.IndexPanel` · Snapshot `game-src/ui/IndexPanel.lua`
**Interfaces:** Consumes IndexClient's data pipeline (read it: discovery flags, catchable filter, availabilityOf + vault badges, FOREST EGG source badge, MINTED counts, tide header). Produces `{ Id = "index", Build }`.

- [ ] **Step 1:** Read IndexClient fully; record its data derivations (this file carries two waves of badge work — every badge KEEPS working in the new tiles).
- [ ] **Step 2:** Build per kit §3.5 + spec extensions: discovery bar (blue fill, counts from the same source), 100%-chip placeholder ("?"), filter chips (All/Catchable + tier filters mirroring current filters), 6-col grid ×122 tiles: BrainrotThumb render, name, undiscovered "?" overlay per kit, ribbon slot priority: NEW > LAST CHANCE (gold) > BACK IN (muted) > FOREST EGG (gold, egg-sourced skip tide per current logic); MINTED chip bottom-right on capped tiles; tide countdown line in the header meta slot.
- [ ] **Step 3 (probes):** compile; badge-priority function unit-probed with 5 synthetic entries (one per state); zero local mutation of discovery data.
- [ ] **Step 4:** Snapshot + commit — `ui(9): Index panel — kit grid with vault/egg/mint badges preserved`

### Task 10: Settings panel + plumbing

**Files:** Create `GameHUDPanels.SettingsPanel`, `game.ServerScriptService.Modules.SettingsService` (ModuleScript), `game.ReplicatedStorage.Remotes.SettingsSave` (RemoteEvent) · Modify: PlayerDataManager (schema `Settings = {}` + migration), SoundKit (SetCategoryVolume), Main (SettingsService.Init after DarrelService) · Snapshot all touched.
**Interfaces:** Produces `{ Id = "settings", Build }`; `SoundKit.SetCategoryVolume(category: "music"|"sfx", v: 0..1)` scaling `play()` volume (sfx) and SoundService.Music children (music); `SettingsService` validating `SettingsSave:FireServer(table)` — whitelist keys {music, sfx, quality, fastSpin, hideOwnBanners}, clamp numbers 0..1, quality ∈ {"Low","Med","High"}, booleans typed — writes `data.Settings`, no other fields.

- [ ] **Step 1:** Schema: add `Settings = {}` to defaultData + `data.Settings = data.Settings or {}` migration (backup PDM first).
- [ ] **Step 2:** SoundKit: add category volume state (module-level `vol = { music = 0.7, sfx = 1 }`), `SetCategoryVolume`, and multiply into `play()`'s volume resolution (read play() first; tag edits `-- UIKIT`). Music folder children volumes scaled directly.
- [ ] **Step 3:** SettingsService per the interface (full whitelist validation code in-module; warn+drop on invalid). Wire into Main.
- [ ] **Step 4:** Build panel per kit §3.3 minus Reset Data: AUDIO sliders (drag + click-to-set per kit; live SetCategoryVolume, SettingsSave on release), GRAPHICS segmented (client-local Lighting toggles: Low = Bloom.Enabled=false + SunRays.Enabled=false, Med = Bloom on/SunRays off, High = both on — via Lighting children lookups, nil-guarded), GAMEPLAY toggles (fastSpin — read WheelClient for where Fast Spin pref lives and drive the same flag; hideOwnBanners — sets a BoolValue attribute on the player consumed by RareCatchClient? read RareCatchClient: if no cheap seam exists, ship the toggle DISABLED with "SOON" chip and document), footer = Redeem Code (blue; opens an input row; `SettingsSave` is NOT used for codes — create nothing server-side beyond a stub `RedeemCode` RemoteFunction in SettingsService returning `false, "Invalid code"` for everything; empty code table constant at top).
- [ ] **Step 5 (probes):** compile all touched; fresh-clone SettingsService: whitelist rejects `{Cash=999}` and accepts `{music=0.5}`; SoundKit clone: SetCategoryVolume(0.5) halves a play() volume resolution (probe the math path, not audio); settings persist round-trip shape into data.Settings on a mock table.
- [ ] **Step 6:** Snapshot + commit — `ui(10): Settings panel + audio/graphics/toggle plumbing, no reset`

### Task 11: PLAY CHECKPOINT 2 — full visual + functional pass

**This task owns Play mode.**

- [ ] **Step 1:** Boot clean (zero red errors). Open all six panels via rail; screenshot EACH vs its `captures/*.png` — per-panel verdict on geometry/palette/type (README numbers are the tiebreak).
- [ ] **Step 2:** Functional: Daily claim round-trip (if unclaimed today) with fly-to-pill; Goals tab swaps + one milestone claim if available; Pass free-tier claim if claimable; Backpack equip/unequip round-trip (hotbar Tool appears/disappears); Index filters + badges present (compare against pre-overhaul badge behavior); Settings sliders move SFX volume state + persist across rejoin (rejoin via stop/start Play, check DarrelState-style pull → data.Settings echo), quality toggles Lighting, redeem stub refuses.
- [ ] **Step 3:** HUD rect measurements at the live viewport: pills/rail/tracker/LuckChip/Sprint/TeleportBar pairwise disjoint; rail items ≥44px touch.
- [ ] **Step 4:** Legacy: egg shop, wheel, fusion, shop/sell all still open/close correctly and single-open against the new panels; old panel guis stay disabled; no orphaned visuals.
- [ ] **Step 5:** Stop Play, camera Fixed, full report with screenshots. SDD fix loop on failures.

### Task 12: Final whole-branch review + fix wave

Standard SDD finale: review package over the branch, most capable model, ledger deferred-minors triaged, ONE fix wave + scoped re-review, then report to the user (with the checkpoint-2 screenshot pack).

---

## Self-review

- **Spec coverage:** replacement map → T3 (retirements, currency, rail, tracker move) + T5–T10 (six panels); collisions → T3 S6 + T4/T11 measurements; Goals consolidation → T6; Backpack deltas → T8; Index extensions → T9; Settings incl. exclusions → T10; acceptance 1–6 → T4/T11/T12. Gamepass/tier-skip gating → T5. Single-open/legacy → T3 S5 + T4 S3 + T11 S4.
- **Placeholders:** kit art slots are spec-mandated placeholders; "COMING SOON"/"SOON"/redeem stub are spec decisions, not plan gaps. The hideOwnBanners toggle has an explicit investigate-then-ship-or-disable path (T10 S4) — bounded, documented.
- **Type consistency:** ctx contract defined once (T3) and consumed by T5–T10; panel module return shape `{Id, Build}` uniform; `ctx.pillAnchor` added in T7 flagged as a T3 amendment — implementer adds it to GameHUDClient with the panel that needs it.
