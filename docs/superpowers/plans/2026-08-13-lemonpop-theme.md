# LemonPop Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **HARD CONSTRAINT for this plan:** all edits happen in the **live Roblox Studio session** via the `roblox-studio` MCP tools (`script_read`, `multi_edit`, `script_grep`, `start_stop_play`, `screen_capture`, `get_console_output`). The Studio MCP is **single-instance** — a second concurrent session gets zero Studio tools. Run tasks **inline/sequentially, never in parallel sessions**.

**Goal:** Replace the Pet-Sim gray palette with the LemonPop palette across all Tokens-driven UI and every shop (Bazaar, Cafe Merchant, Robux Shop, Egg Shop, Cove booths), per the approved spec `docs/superpowers/specs/2026-08-13-lemonpop-theme-design.md`.

**Architecture:** In-place rewrite of the colour half of `ReplicatedStorage.Modules.UIKit.Tokens` (token names unchanged, old hexes recorded inline), plus an on-light/on-dark text-token split applied through Builders/panel call sites, an in-place retint of the Studio-only `UITheme.Bazaar` palette, and an additive `M.Lemon` pack in UITheme that only MerchantClient opts into.

**Tech Stack:** Roblox Luau, live Studio via roblox-studio MCP, disk mirror at `game-src/place-full/` (git).

## Global Constraints

- **Studio is authoritative; mirrors have drifted before.** Diff Studio source against the disk mirror before editing any file; re-sync the mirror **byte-exact** after each task and commit.
- **NOTHING IS SAVED OR PUBLISHED by this plan.** Studio holds other unsaved work (inventory rework, mutation fixes); saving is the owner's/user's call.
- **Fonts untouched.** `T.font` and `StarterPlayerScripts.UIPolish`'s FONT constant move in lockstep; this plan changes neither.
- **Geometry, radii, stroke widths, shadows, padding, motion, zindex, icon asset ids: unchanged.** Colours only, plus text-stroke *presence* where the spec's on-light rule requires it.
- One red surface per panel (the header). Mutations keep their rainbow ring — never a recoloured frame.
- Studio Play tests write the **real datastore** — view panels, don't claim/spend/sell beyond what viewing requires.
- Captures need Studio **foregrounded** (backgrounded = render-throttled/wrong-app frames). If a capture poses the camera, restore `CameraType` afterwards — never leave `Scriptable`.
- `execute_luau` runs in a server sandbox and does not see client module state — verify visuals with captures and real clicks, not Luau probes alone.
- `openPanel` pcall-wraps panel builds and **silently hides broken panels** — after any panel edit, check `get_console_output` AND visually confirm the panel opened.
- `multi_edit` can fail silently — re-read the edited range after every `multi_edit` and confirm the change landed.
- Editing a ModuleScript's Source does not invalidate an already-running Play session's require cache — **stop Play before editing, restart after**.
- Share capture files with the user at each visual milestone, not end-of-turn.

**Legend used below:** "mirror" = `game-src/place-full/...` on disk; paths inside Studio use dot notation. Mirror-sync = copy Studio Source to the mirror file byte-exact, `git add` + commit.

---

### Task 1: Preflight — Studio connection and drift reconciliation

**Files:**
- Read (Studio): `ReplicatedStorage.Modules.UIKit.Tokens`, `ReplicatedStorage.Modules.UITheme`
- Read (mirror): `game-src/place-full/ReplicatedStorage/Modules/UIKit/Tokens.lua`, `game-src/place-full/ReplicatedStorage/Modules/UITheme.lua`
- Possibly modify: the two mirror files (reconciliation only)

**Interfaces:**
- Produces: confirmed-current Studio sources for Tokens and UITheme; the **actual key list of `UITheme.Bazaar`** (exists only in Studio — the mirror predates it), written into the task notes for Task 6; reconciled mirrors so later byte-exact syncs are clean diffs.

- [ ] **Step 1:** `get_studio_state` — confirm the game is open and which place. If no Studio session, STOP and tell the user to open Studio.
- [ ] **Step 2:** `script_read` Studio's `ReplicatedStorage.Modules.UIKit.Tokens` in full. Diff against the mirror file. Expected: identical or near-identical to the mirror (238 lines, gray palette).
- [ ] **Step 3:** `script_read` Studio's `ReplicatedStorage.Modules.UITheme` in full. Diff against the mirror. Expected: Studio has a `M.Bazaar` section the mirror lacks. Record the full Bazaar palette (key names + current values) — Task 6 needs them.
- [ ] **Step 4:** If either mirror differs from Studio beyond the known Bazaar gap: copy Studio Source over the mirror file(s) verbatim and commit as `chore: reconcile game-src mirror with Studio before LemonPop` — reconciliation only, no theme changes in this commit.
- [ ] **Step 5:** Confirm Play is **stopped** (`get_studio_state`).

---

### Task 2: Tokens.lua colour swap

**Files:**
- Modify (Studio): `ReplicatedStorage.Modules.UIKit.Tokens` — `T.color` block (~lines 34–74) and `T.gradient` block (~lines 81–114) only
- Modify (mirror after): `game-src/place-full/ReplicatedStorage/Modules/UIKit/Tokens.lua`

**Interfaces:**
- Produces: all existing token names with LemonPop values, plus **two NEW tokens** consumed by Tasks 3–5: `T.color.textMutedOnDark` (`#E8DCBE`) and `T.color.textAccentOnDark` (`#FFD84D`). Everything else keeps its exact current name.

- [ ] **Step 1:** With Play stopped, replace the body of `T.color` with the block below (a dated banner comment goes above it, mirroring the 2026-08-04 banner pattern already in the file):

```lua
-- ============================================================================
-- 2026-08-13 STYLE REPLACEMENT -- "LemonPop" (Downloads/LemonPop-Theme.lua):
-- warm lemon-cream windows, gold furniture, warm near-black outlines. This
-- REPLACES the 2026-08-04 Pet-Sim gray guide. Token names unchanged; old
-- hexes inline so any surface can be walked back. Light surfaces now carry
-- dark UNSTROKED ink; dark surfaces keep white stroked type (see the
-- textMutedOnDark/textAccentOnDark split).
-- ============================================================================
T.color = {
	outline        = hex("#241F14"), -- warm near-black (was #202020)
	innerKeyline   = hex("#FFFFFF"),

	panelTop       = hex("#FFFBE2"), -- (was #D6D6D6)
	panelBottom    = hex("#FFD977"), -- (was #A9A9A9)
	subPanelTop    = hex("#FFF6CF"), -- (was #C4C4C4)
	subPanelBottom = hex("#F7C95C"), -- (was #9C9C9C)
	rowTop         = hex("#4A4030"), -- stays dark, warm-tinted (was #4A4A4A)
	rowBottom      = hex("#302A1F"), -- (was #363636)
	tabTop         = hex("#C2A878"), -- (was #BEBEBE)
	tabBottom      = hex("#8A7350"), -- (was #9C9C9C)
	trackTop       = hex("#302A1F"), -- (was #2E2E2E)
	trackBottom    = hex("#3D3527"), -- (was #3A3A3A)
	slotTop        = hex("#FFFFFF"), -- LIGHT FLIP: art wells go light so renders read (was #4A4A4A)
	slotBottom     = hex("#FFF4D9"), -- (was #363636)
	headerTop      = hex("#FF6B5C"), -- (was #F96B57)
	headerBottom   = hex("#D8342C"), -- (was #C84535)

	white          = hex("#FFFFFF"),
	textMuted      = hex("#7A6A52"), -- LIGHT surfaces ONLY now (was #D8D8D8 on both; dark surfaces take textMutedOnDark)
	textMutedOnDark = hex("#E8DCBE"), -- NEW: muted text on row/track/dark pills
	textAccent     = hex("#C2410C"), -- LIGHT surfaces ONLY now (was #FFD84D on both; dark surfaces take textAccentOnDark)
	textAccentOnDark = hex("#FFD84D"), -- NEW: the old yellow, for values on dark surfaces
	textOnLight    = hex("#33261A"), -- dark ink, NO text stroke on light surfaces (was #2A2A2A)
	textOnWindow   = hex("#33261A"), -- explicit alias for the above, for new code
	textOnGoldCard = hex("#3A2A05"),
	textOnGoldChrome = hex("#5A4A12"),
	textDisabled   = hex("#A79A7C"), -- warm taupe (was olive #B8C4A4)
	textClaimed    = hex("#9C8F6E"), -- (was sage #9FAE8B)

	claimRing      = hex("#7CE04A"),
	activeRing     = hex("#FFD84D"),
	activeGlow     = hex("#FFE87A"),
	scrollThumb    = hex("#C2A878"), -- tab tan (was sage #9FAE8B)

	rarityCommon   = hex("#C9CCC2"),
	rarityRare     = hex("#3FA9F5"),
	rarityEpic     = hex("#A855F7"),
	rarityLegend   = hex("#FFB200"),
}
```

- [ ] **Step 2:** Replace the changed entries of `T.gradient` (unchanged entries — `goldSmall`, `green`, `red`, `blue`, `purple`, `gem`, `passCard`, `lockBadge`→see below, `knob`, `passLabel` — keep `lockBadge` OUT of this "unchanged" list, it changes):

```lua
	gold      = seq({ { pos = 0, hex = "#FFF08A" }, { pos = 0.55, hex = "#FFC531" }, { pos = 1, hex = "#E08A0C" } }), -- top stop was #FFE87A
	-- goldSmall / green / red / blue / purple / gem: UNCHANGED

	panel     = seq({ { pos = 0, hex = "#FFFBE2" }, { pos = 1, hex = "#FFD977" } }), -- was #D6D6D6 -> #A9A9A9
	subPanel  = seq({ { pos = 0, hex = "#FFF6CF" }, { pos = 1, hex = "#F7C95C" } }), -- was #C4C4C4 -> #9C9C9C
	row       = seq({ { pos = 0, hex = "#4A4030" }, { pos = 1, hex = "#302A1F" } }), -- was #4A4A4A -> #363636
	tab       = seq({ { pos = 0, hex = "#C2A878" }, { pos = 1, hex = "#8A7350" } }), -- was #BEBEBE -> #9C9C9C
	track     = seq({ { pos = 0, hex = "#302A1F" }, { pos = 1, hex = "#3D3527" } }), -- was #2E2E2E -> #3A3A3A
	slot      = seq({ { pos = 0, hex = "#FFFFFF" }, { pos = 1, hex = "#FFF4D9" } }), -- LIGHT FLIP, was #4A4A4A -> #363636
	header    = seq({ { pos = 0, hex = "#FF6B5C" }, { pos = 1, hex = "#D8342C" } }), -- was #F96B57 -> #C84535
	window    = seq({ { pos = 0, hex = "#FFFBE2" }, { pos = 1, hex = "#FFD977" } }),
	cream     = seq({ { pos = 0, hex = "#FFFBE2" }, { pos = 1, hex = "#FFD977" } }), -- LEGACY ALIAS, tracks window

	freeCard  = seq({ { pos = 0, hex = "#FFFDEE" }, { pos = 0.55, hex = "#F5E7C0" }, { pos = 1, hex = "#D9BC82" } }), -- was gray-whites #F7F7F1/#DEDED4/#B2B4A8
	lockBadge = seq({ { pos = 0, hex = "#FFF6DC" }, { pos = 1, hex = "#D8C494" } }), -- was #F2F2EC -> #C2C4B8
	disabled  = seq({ { pos = 0, hex = "#8A7C5E" }, { pos = 1, hex = "#5C5138" } }), -- warm taupe, was olive #6A7757 -> #454F33
	ownedCta  = seq({ { pos = 0, hex = "#A98F5C" }, { pos = 1, hex = "#6E5A34" } }), -- was olive #8FA378 -> #54643C
	freeLabel = seq({ { pos = 0, hex = "#B89B5E" }, { pos = 1, hex = "#7C6438" } }), -- was olive #7A8A66 -> #55643F
	-- passCard / knob / passLabel: UNCHANGED (already warm gold)
```

- [ ] **Step 3:** `script_read` the edited ranges back. Confirm every hex above landed and no syntax damage (balanced braces, `seq(` calls intact). `multi_edit` fails silently — this read is the gate.
- [ ] **Step 4:** Start Play (`start_stop_play`). `get_console_output` — expected: zero new errors mentioning Tokens/UIKit/Builders.
- [ ] **Step 5:** Foreground Studio, `screen_capture` the HUD, then click the rail's Bag and Goals buttons and capture each panel. Expected: lemon-cream windows, red headers, gold furniture. Text on light surfaces will still show old stroke behaviour and some pale-on-pale text — that is Task 3's job, note but don't fix here.
- [ ] **Step 6:** Send the captures to the user (visual milestone). Stop Play.
- [ ] **Step 7:** Mirror-sync Tokens.lua byte-exact; commit `feat: LemonPop colour swap in UIKit Tokens`.

---

### Task 3: Text split — Builders and shared helpers

**Files:**
- Read/Modify (Studio): `ReplicatedStorage.Modules.UIKit.Builders` (and any shared text-style helper it exposes)
- Modify (mirror after): `game-src/place-full/ReplicatedStorage/Modules/UIKit/Builders.lua` (path confirmed in Step 1)

**Interfaces:**
- Consumes: `T.color.textMutedOnDark`, `T.color.textAccentOnDark`, `T.color.textOnWindow` from Task 2.
- Produces: Builders whose text helpers apply the LemonPop rule — **light surface ⇒ dark ink, `TextStrokeTransparency = 1` (no stroke) / dark surface ⇒ white or on-dark variant, stroke kept**. Panel tasks (4, 5) rely on these helpers being correct.

- [ ] **Step 1:** `script_grep` the UIKit folder for consumers: patterns `textMuted`, `textAccent`, `textOnLight`, `textOnWindow`, `TextStrokeTransparency`, `textStroke`. Build a call-site table: file, line, which token, which *surface* the text sits on (panel/subPanel/slot/freeCard = LIGHT; row/track/header/gold/action-gradient = DARK-or-saturated).
- [ ] **Step 2:** For each LIGHT-surface site in Builders: switch colour to `textOnWindow`/`textMuted`/`textAccent` as appropriate and remove the text stroke (set `TextStrokeTransparency = 1`, or skip the contextual `UIStroke`, matching however that helper applies strokes). For each DARK-surface site: keep the stroke; switch `textMuted` → `textMutedOnDark` and `textAccent` → `textAccentOnDark`. Headers keep white stroked type.
- [ ] **Step 3:** `script_read` every edited range back; confirm edits landed.
- [ ] **Step 4:** Start Play. `get_console_output` — zero new errors. Open Bag, Goals, Pass via real rail clicks. Expected: captions/values on the cream window are dark and unstroked; values on currency pills/dark rows are still yellow (`textAccentOnDark`) and legible.
- [ ] **Step 5:** `screen_capture` each of the three panels, foregrounded. Send to user. Stop Play.
- [ ] **Step 6:** Mirror-sync Builders; commit `feat: LemonPop on-light/on-dark text split in UIKit Builders`.

---

### Task 4: Panel audit sweep — core UIKit panels

**Files:**
- Read/Modify (Studio): panel scripts as found — `GameHUDClient` + `GameHUDPanels/*` (Bag, Goals, Pass, Daily, Index, Settings, ShopPanel), `EggShopClient`, `IndexClient`, `BackpackPanel`, pets/keys/tags tiles, Charm Codex client, `WheelClient`, rebirth UI, hotbar, toasts, quest bar, currency pills, nav rail
- Modify (mirror after): each edited script's mirror twin

**Interfaces:**
- Consumes: Task 2 tokens, Task 3 helper behaviour.
- Produces: every panel visually LemonPop with no gray-era hardcodes; the audit-findings list (file:line → fix) appended to this plan file as it goes.

For **each** panel in this order — Bag (plot-rack inventory), Goals, Pass, Daily, Index (+ discovery silhouettes), Robux Shop, Egg Shop (+ discovery covers, x1/x3/x10 chips), Pets, Keys, Tags, Settings, Charm Codex, Wheel, Rebirth, hotbar, HUD chrome (currency pills, quest bar, nav rail + IconArt), toasts:

- [ ] **Step A:** In Play, open the panel via its real entry point (rail click, keybind, or world prompt). `openPanel`'s pcall hides breakage — confirm it *visibly opened* and check `get_console_output` for swallowed errors.
- [ ] **Step B:** Eyeball against the LemonPop rules: (1) no gray-era surfaces (`#D6D6D6`/`#A9A9A9`/`#C4C4C4`/`#4A4A4A`/`#363636`/`#2E2E2E`/`#BEBEBE` families); (2) text follows the light/dark rule from Task 3; (3) exactly one red surface (the header); (4) slot light-flip contrast — pale art (discovery silhouettes, white pets) must still read on the now-light wells. If a silhouette disappears, darken that *silhouette tint at its call site* (e.g. to `T.color.textOnWindow`), never re-darken the slot token.
- [ ] **Step C:** For each miss: stop Play, `script_grep` that panel's script for the offending hardcoded hex, repoint it at the matching token (never introduce a new literal), `script_read` to confirm, restart Play, re-open the panel, re-check.
- [ ] **Step D:** `screen_capture` the finished panel, foregrounded. Batch-send captures to the user every 3–4 panels.
- [ ] **Final step:** Stop Play. Mirror-sync every script edited in this task; commit `feat: LemonPop audit sweep over UIKit panels` (one commit; the findings list in the message body).

---

### Task 5: Bazaar shop + sell retint

**Files:**
- Modify (Studio): `ReplicatedStorage.Modules.UITheme` — the `M.Bazaar` section only (keys recorded in Task 1)
- Read (Studio): `StarterPlayer.StarterPlayerScripts.ClientMain` ("Bazaar menu chrome (shop / sell)", `local BZ = UITheme.Bazaar`, price/action pill styling ~line 157)
- Modify (mirror after): `game-src/place-full/ReplicatedStorage/Modules/UITheme.lua` (this sync **adds the Bazaar section to the mirror for the first time**), plus ClientMain's mirror if edited

**Interfaces:**
- Consumes: the Task 1 record of `UITheme.Bazaar`'s actual keys/values.
- Produces: LemonPop-valued `UITheme.Bazaar`; ClientMain untouched unless it carries hardcoded hexes alongside BZ reads.

- [ ] **Step 1:** With Play stopped, retint `M.Bazaar` in place, old values inline. Mapping (apply to whatever keys Task 1 found; do not invent keys): window/panel surfaces → `#FFFBE2`→`#FFD977`; section/sub surfaces → `#FFF6CF`→`#F7C95C`; header/title accent → `#FF6B5C`→`#D8342C` (the ONE red); outlines → `#241F14`; price/buy pills (the "green->yellow" pills per ClientMain's comment) → green `#83E34A`→`#4FB42E` and gold `#FFF08A`→`#FFC531`→`#E08A0C`; sell/destructive → `#FF6B6B`→`#D83E3E`; muted text on light → `#7A6A52`; ink on light → `#33261A`; light text on dark/saturated → `#FFFFFF`.
- [ ] **Step 2:** `script_grep` ClientMain's Bazaar chrome region for hardcoded `Color3` literals that bypass BZ; repoint any at the retinted BZ keys.
- [ ] **Step 3:** `script_read` edited ranges back; confirm.
- [ ] **Step 4:** Start Play, walk to the Bazaar, open the **shop** menu and the **sell** menu (browse only — sell nothing). Console check. Verify the bzShadow drop-shadow still tracks panel visibility (regression watch: the 2026-08-06 "big black square" fix).
- [ ] **Step 5:** `screen_capture` both menus, foregrounded; send to user. Stop Play.
- [ ] **Step 6:** Mirror-sync UITheme (+ClientMain if touched); commit `feat: LemonPop Bazaar retint (mirror gains Bazaar section)`.

---

### Task 6: `M.Lemon` pack + Cafe Merchant repoint

**Files:**
- Modify (Studio): `ReplicatedStorage.Modules.UITheme` — append additive `M.Lemon` after the Candy pack
- Modify (Studio): `StarterPlayer.StarterPlayerScripts.MerchantClient`
- Modify (mirror after): both mirror twins

**Interfaces:**
- Consumes: nothing new.
- Produces: `M.Lemon` palette table (below). **Only MerchantClient reads it.** Camp (`CF`) and its ~58 call sites across 12 scripts are untouched — the egg shop's Camp-styled toasts are handled in Task 4's audit, still via their own call sites.

- [ ] **Step 1:** Append to UITheme (additive; nothing changes on screen until something opts in — the Candy-pack precedent):

```lua
-- ===================================================================
-- LEMON style pack (2026-08-13). LemonPop shop palette. ADDITIVE like
-- Candy: no caller changes until a script opts in. Today only
-- MerchantClient reads it (spec 2026-08-13-lemonpop-theme-design.md §3b).
-- ===================================================================
local LEMON = {
	outline   = Color3.fromHex("241F14"),
	keyline   = Color3.fromHex("FFFFFF"),
	panelTop  = Color3.fromHex("FFFBE2"), panelBot  = Color3.fromHex("FFD977"),
	subTop    = Color3.fromHex("FFF6CF"), subBot    = Color3.fromHex("F7C95C"),
	headerTop = Color3.fromHex("FF6B5C"), headerBot = Color3.fromHex("D8342C"), -- the ONE red surface
	slotTop   = Color3.fromHex("FFFFFF"), slotBot   = Color3.fromHex("FFF4D9"),
	rowTop    = Color3.fromHex("4A4030"), rowBot    = Color3.fromHex("302A1F"),
	tabTop    = Color3.fromHex("C2A878"), tabBot    = Color3.fromHex("8A7350"),
	ink       = Color3.fromHex("33261A"), -- dark unstroked text on light surfaces
	muted     = Color3.fromHex("7A6A52"),
	accent    = Color3.fromHex("C2410C"),
	onDark    = Color3.fromHex("FFFFFF"), -- stroked, on header/rows/saturated buttons
	mutedOnDark = Color3.fromHex("E8DCBE"),
	gold1     = Color3.fromHex("FFF08A"), gold2 = Color3.fromHex("FFC531"), gold3 = Color3.fromHex("E08A0C"),
	green1    = Color3.fromHex("83E34A"), green2 = Color3.fromHex("4FB42E"),
	red1      = Color3.fromHex("FF6B6B"), red2  = Color3.fromHex("D83E3E"),
	disabled1 = Color3.fromHex("8A7C5E"), disabled2 = Color3.fromHex("5C5138"),
}
M.Lemon = LEMON
```

- [ ] **Step 2:** `script_grep` MerchantClient for every `CF.` read and every `UITheme.Camp` / `wood` / hardcoded-hex reference. Build the repoint table.
- [ ] **Step 3:** Repoint MerchantClient: `CF.panelTop/panelBot` → `LEMON.panelTop/panelBot`; card creams → `LEMON.subTop/subBot`; `CF.wood1/wood2` header → `LEMON.headerTop/headerBot` (deliberate vibe change, spec §3b); `CF.ink` outlines → `LEMON.outline`; `CF.cream`(text)/`CF.muted` → `LEMON.ink`/`LEMON.muted`; `CF.onDark` → `LEMON.onDark`; locked/disabled fills → `LEMON.disabled1/2`; buy buttons → LEMON gold/green. **Font stays `UITheme.Font` (Cartoon).** Keep `campButton`'s luminance-based label logic working by passing LEMON colours through it, not by editing the shared helper.
- [ ] **Step 4:** `script_read` edited ranges; confirm.
- [ ] **Step 5:** Start Play, walk to the cafe merchant, open the shop. Console check; browse, buy nothing. Expected: lemon panel, red header, Cartoon font intact, buy pills gold/green with legible outlined labels.
- [ ] **Step 6:** `screen_capture`, foregrounded; send to user. Stop Play.
- [ ] **Step 7:** Mirror-sync UITheme + MerchantClient; commit `feat: additive M.Lemon pack; Cafe Merchant opts in`.

---

### Task 7: Full-pass verification and handoff

**Files:**
- No new edits expected; fix-forward anything found (same fix cycle as Task 4 Step C, then re-sync that file's mirror and amend nothing — new commit `fix: LemonPop final-pass fixes`).

- [ ] **Step 1:** Fresh Play session. Sweep every surface in the Task 4 list plus the three shops (Bazaar, Merchant, Egg Shop) end to end. For each: opens visibly, console clean, light/dark text rule holds, one red header, no gray-era remnants, slot-contrast OK.
- [ ] **Step 2:** Capture a final roll (foregrounded): HUD + each panel + each shop. Send all to the user.
- [ ] **Step 3:** Stop Play. Confirm CameraType is not left `Scriptable` anywhere the sweep posed a camera.
- [ ] **Step 4:** `git status` the repo — every edited Studio script has a byte-exact mirror commit; working tree clean of theme files.
- [ ] **Step 5:** Report to the user: what changed, capture roll, explicit reminder that **everything is UNSAVED in Studio** alongside the other pending unsaved work, and that saving is their/the owner's call (coordinate with Team Create collaborators first). Update memory (`roblox-icon-redesign.md` current-style note + a new LemonPop entry) so the next session knows LemonPop replaced the Pet-Sim gray guide.

---

## Execution log (2026-08-13)

**Status: all code tasks COMPLETE in Studio; LIVE VERIFICATION DEFERRED at user request** (Studio Play kept being stopped externally — 3 graceful shutdowns — user chose "skip live checks, one big Play pass later"). Everything below still needs the Task 7 visual pass before it can be called done.

**Findings that changed the plan (all handled):**
1. **Studio ≠ mirror, massively.** Studio held an unsaved 2026-08-10 "spec sweep" (HUD-upgrade sheet): slate/light-blue palette, WHITE row cards, slate header (no red), FredokaOne, new `UIKit.SpecTheme` module, `PanelChrome`, reworked UIPolish. The plan's "was" values were rewritten against the real slate values; reconcile commit `f989a68` first.
2. **UIPolish forces white+stroke on ALL unexempted labels** (re-asserting on colour writes). Task 3 became: flip UIPolish's DEFAULT to dark unstroked LemonPop ink; new `PolishOnDark` attribute (ancestor-honoured, like NoPolish) restores stroked white. Builders tags dark surfaces centrally — `UI.surface` for every non-light kind (incl. "header"/"gold"/"purple" header bars), `UI.button`, `UI.badge`, `UI.ribbon`. `UI.label` strokes only light fills (luminance rule).
3. **`UIKit.SpecTheme` (Studio-only) is a SECOND palette** feeding the spec-shell panels (worlds/shop/goals/settings/backpack/rebirth). Retinted: slate families → warm (Outline/Neutral/Inert/Danger/Surface/inks); identity colours (plates, 8-tier rarity, premium violet) untouched. Mirror file created.
4. **MerchantClient was already Bazaar-pack styled** (2026-08-06 restyle, mirror predates it) — so the M.Lemon pack was NOT needed. Retinting `UITheme.Bazaar` covers rock shop + sell + merchant + egg-shop accents at once. Bazaar text builders now set NoPolish and follow the light/dark rule; per-shop header identities (bronze/green/pink) collapse into the ONE red header (deliberate). Merchant extras: warm locked-state taupe, light viewport wells.
5. ClientMain EQUIP pill rode `BZ.header1/2` (was cyan, now red = destructive-looking) → moved to `P.blue1/2` (LemonPop equip-blue).
6. Panel hardcode fixes: PassPanel (2 slate card gradients, 1 slate locked colour), BackpackPanel (2x slate stroke #071323, slate dark fill, slate locked colour, slate slot gradient), RebirthClient (slate card gradient), EggShopClient (header PolishOnDark for the red BZ gradient).

**Commits:** `f989a68` reconcile, `cd671ea` Tasks 2–3, `2c47fa9` Tasks 4–6. Mirror re-sync of ClientMain / MerchantClient / EggShopClient / PassPanel / BackpackPanel / RebirthClient ran as a follow-up transcription (pre-sweep mirrors replaced wholesale).

**Task 7 (pending, needs user):** one continuous Play session — every panel + Bazaar shop/sell + Merchant + Egg Shop opened via real clicks, console checks, capture roll, camera restore check. Known watch-items: slot light-flip contrast on discovery silhouettes; dark-row text sites that used `textMuted`/`textAccent` (need the OnDark variants); QuestTrackerClient's own white palette (NoPolish, unaffected but verify); SessionLock — leave ≥90s between Play cycles.

## Self-Review

**Spec coverage:** §1 direct adoptions → Task 2. §2 text split → Tasks 3–4. §3 derived extras → Task 2. §3b shops → Tasks 4 (UIKit shops), 5 (Bazaar), 6 (Merchant). §4 audit → Task 4 (+7). §5 verification → every task's Play steps + Task 7. §6 boundaries + §7 risks → Global Constraints. ui-web mirror sync: explicitly a follow-up, not in this plan. No gaps found.

**Placeholder scan:** Bazaar mapping (Task 5) names target values but not final key names — unavoidable, the keys exist only in Studio; Task 1 Step 3 closes that gap before Task 5 runs. Builders/panel edits (Tasks 3–4) are procedure + decision-table rather than literal diffs for the same reason (live grep drives them); the decision rule and exact token names are fully specified.

**Type consistency:** `textMutedOnDark`/`textAccentOnDark` defined in Task 2, consumed in Tasks 3–4. `M.Lemon`/`LEMON` keys defined in Task 6 Step 1 match the repoints in Step 3. Mirror paths consistent throughout.
