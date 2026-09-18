# UI Foundation v2 + BrainrotCard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the game one reusable UI component system — semantic colour grammar, spacing scale, shell slots, semantic buttons with disabled/busy states, TabBar/SearchBar/SortButton/Modal/Toast, the style-C `BrainrotCard` with rarity-first identity, projected-box preview framing and adaptive viewport culling — proven on a Studio-only Gallery panel and on the Bag's brainrot inventory grid, per `docs/superpowers/specs/2026-09-18-ui-foundation-design.md` (the spec).

**Architecture:** `ReplicatedStorage.Modules.UIKit` is extended in place (`SpecTheme` tokens, `PanelChrome` buttons + shell slots) and gains one new module per new component (`FxDriver`, `TabBar`, `SearchBar`, `SortButton`, `Modal`, `Toast`, `BrainrotCard`, `ViewportCuller`). `BrainrotThumb` learns projected-corner framing. A `GalleryPanel` renders every component in every state. `BackpackPanel.fillBag()` is the one production seam migrated onto `BrainrotCard` + `ViewportCuller`. Components are pure builders: data in, instances + a small API out; panels map raw entries and wire remotes.

**Tech Stack:** Roblox Luau (`--!strict` on new modules), Roblox Studio via the `roblox-studio` MCP (`list_roblox_studios`, `get_studio_state`, `script_read`, `multi_edit`, `execute_luau`, `start_stop_play`, `user_mouse_input`, `screen_capture`), existing modules `SpecTheme`, `PanelChrome`, `Builders`, `BrainrotThumb`, `Platform`, `SoundKit`, `NumberFormat`, `MutationConfig`. Git holds the mirror under `game-src/place-full/`.

## Global Constraints

- **Studio is the source of truth.** Every edit is made in Studio through the MCP. Call `list_roblox_studios` first (id at plan time: `af34f702-49e1-4789-8c00-a60145f10c6e`, place 78783087742939) and use the returned id for every call; if a call reports no instance, re-list. `script_read` the exact region immediately before every `multi_edit`; the place is Team Create and a second session may be editing. Anchor on lines you just read, never on the mirror.
- **Edit mode for writes.** `multi_edit` and `execute_luau` writes need `datamodel_type = "Edit"`. If `get_studio_state` says Play, the user is away for this round (their words: build it tonight), so `start_stop_play(false)` and continue. Reads work from `Server` during Play.
- **Two write styles only:** new modules are created with `multi_edit` (`className = "ModuleScript"`, first edit `old_string = ""`) or rewritten whole via `execute_luau` (`inst.Source = [==[ ... ]==]`) — never above 200k chars; existing scripts get small anchored `multi_edit` diffs. **After every write, compile-gate:** `execute_luau` (Edit) → `local f, e = loadstring(inst.Source); assert(f, e); return "compiles"`. A `multi_edit` can silently drop an edit while reporting success — byte-scan for each new_string with `Source:find(needle, 1, true)` after every multi-edit call.
- **Studio backups before every edit of an existing script:** the exec thread cannot `Clone()` a script into ServerStorage (Capabilities), so: (1) `multi_edit` creates the stub `game.ServerStorage.AuditBackups.PreUIFoundation_2026_09_18.<ScriptName>_pre<TaskN>` (`className` = the original's class, `old_string = ""`, `new_string = "-- backup stub"`); (2) `execute_luau` (Edit) copies the text: `stub.Source = live.Source; return #stub.Source == #live.Source` (must be `true`). If (1) is refused for that folder, use the sibling `PreUIFoundation_2026_09_18_Task<N>`. The git checkpoint (Task 1, commit 32e1701) plus each task's commit is the authoritative rollback source either way.
- **The `execute_luau` thread cannot `require` any ModuleScript and cannot parent script instances into CoreGui/ServerStorage** (script Capabilities; found in Task 2). Every Edit-mode test therefore starts with the loader preamble in `.superpowers/sdd/2026-09-18-ui-foundation/test-loader.lua` (`loadstring` of the LIVE source with `script` bound to the live instance and a recursive fake `require`; fresh every run, no clones, no stale cache) and calls `load(kit.X)` where the plan's test scripts say so. Non-script scratch (a `CoreGui.UIKitScratch` ScreenGui and Frames) is fine; tear it down with `.Parent = nil` — never `:Destroy()` inside a test script (the permission classifier blocks it). CoreGui is local to this Studio and never replicates — no `StarterGui`/`Workspace` scratch, ever. `loadstring` is Edit-only; Play-mode probes use the running game's own state (attributes, instance trees).
- **`--!strict` on every NEW module.** Do not add strict to existing files.
- **TweenService animates `GuiObject.Size`/`Position` only** in this place; transparency, `UIScale`, `UIGradient.Offset`, `NumberValue` tweens silently no-op. Every other continuous effect goes through `UIKit.FxDriver` (Task 3), the one Heartbeat for the whole client.
- **`NoPolish`:** every `TextLabel`/`TextButton`/`TextBox` the kit creates sets `SetAttribute("NoPolish", true)` (UIPolish restyles anything without it).
- No writes of `Plugin`-capability properties (`MeshPart.RenderFidelity` etc.) — `BrainrotThumb.ForcePrecise` is the only guarded site and is not touched.
- Never position from `AbsolutePosition` deltas (the HUD runs at ~0.72 cumulative `UIScale`); `ViewportCuller` compares `AbsolutePosition`s against each other, which is fine.
- `BackpackPanel`: new `require`s go at MODULE top level (after `local NumberFormat = require(...)` at ≈ line 191), never inside `BackpackPanel.Build` (Luau 200-local ceiling; a breach reads as a misleading "cannot allocate" error). The module already has a top-level `bagState`; this round's grid state table is named `gridUi`.
- **Logging (spec §11):** every `pcall` this round adds or touches reports failure as `warn(("[UIKit] %s: %s\n%s"):format(identity, tostring(err), debug.traceback()))`. No bare `pcall`.
- **Colour grammar (spec §5):** kit components read `S.Role.*`; `S.Action.*` aliases keep their current values; `S.Action.Neutral` stays grey. Active tab/filter = `S.Role.Neutral` (blue), inactive = `S.Role.Disabled` (grey).
- **Play verification writes the REAL datastore.** Allowed state changes during verification: one equip round-trip and one lock toggle round-trip on the Bag (both reversible), Gallery interactions (no game state). No purchases, sells, deletes, rebirths. Stop Play before finishing the round.
- **Play input + captures need Studio FOREGROUND and on its viewport tab** (Studio suspends rendering when backgrounded or when a script tab is active; `user_mouse_input`/`screen_capture` then time out — Task 2 hit exactly this). Before any Play verification step run the PowerShell helper `.superpowers/sdd/2026-09-18-ui-foundation/studio-focus.ps1` (it refuses if the user touched the machine in the last 60 s or a fullscreen game is foreground; otherwise it foregrounds Studio and presses Ctrl+Tab). Then confirm with `execute_luau` (Client): `local n=0 local c=game:GetService("RunService").RenderStepped:Connect(function() n+=1 end) task.wait(0.5) c:Disconnect() return n` → must be > 0 (re-run the helper until it is). The user has left for the night and allowed this. `user_mouse_input` can still wedge after 1–3 clicks per Play cycle: one action per call, and if it times out, stop Play, start Play, re-focus, retry once. Restore `CameraType` if a posed capture was taken.
- **Phone tests** use `ReplicatedStorage:SetAttribute("PlatformOverride", "Phone")` set in Edit; remove it and confirm nil afterwards (it ships if left).
- **Mirror + commit at the end of every task:** for each touched script, `script_read` its Source and write it byte-exact to the matching path under `game-src/place-full/` (`.lua` ModuleScript, `.client.lua` LocalScript; new modules get new files), LF endings, then `git add` those paths and commit with the task's message (use `git commit -F <file>` for multi-line messages; end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`). Never `git add -A` — the working tree carries unrelated modifications.
- **Owner is token-cost sensitive.** `script_grep`/line ranges over whole-file reads; don't re-verify what the previous step proved.

## File Structure

Studio paths (mirror path = `game-src/place-full/<Service>/...`):

| Studio instance | Status | Responsibility | Task |
|---|---|---|---|
| `ReplicatedStorage.Modules.UIKit.SpecTheme` | modify | `S.Role`, `S.Space`, `S.Card`, `S.Sound`, `S.Scale` | 2, 11 |
| `StarterPlayer.StarterPlayerScripts.GameHUDClient` | modify | warnings on the two panel pcalls; Gallery trigger | 2, 11 |
| `ReplicatedStorage.Modules.UIKit.FxDriver` | new | one Heartbeat for all kit animation | 3 |
| `ReplicatedStorage.Modules.UIKit.PanelChrome` | modify | `button`, `setEnabled`, `setBusy`, press-feedback guards + click sound, `pill.outline`, grammar sweep of `addHeaderTabs`/`segmented`, shell slots | 4, 5 |
| `ReplicatedStorage.Modules.UIKit.TabBar` | new | body tabs, both orientations | 6 |
| `ReplicatedStorage.Modules.UIKit.SearchBar` | new | search input | 6 |
| `ReplicatedStorage.Modules.UIKit.SortButton` | new | segmented sort group | 6 |
| `ReplicatedStorage.Modules.UIKit.Modal` | new | `Modal.confirm` | 7 |
| `ReplicatedStorage.Modules.UIKit.Toast` | new | the one toast stack | 7 |
| `StarterPlayer.StarterPlayerScripts.ToastClient` | modify | stack removed; `push` → `Toast.show` | 7 |
| `ReplicatedStorage.Modules.BrainrotThumb` | modify | `framingBox`, `framing(model, fov, opts)`, `fill`/`aspect` in `addMaster` | 8 |
| `ReplicatedStorage.Modules.UIKit.BrainrotCard` | new | the collectible card | 9 |
| `ReplicatedStorage.Modules.UIKit.ViewportCuller` | new | scroll-visibility mount/unmount, adaptive cap | 10 |
| `StarterPlayer.StarterPlayerScripts.GameHUDPanels.GalleryPanel` | new | Studio-only living style guide + stress test | 11 |
| `…GameHUDPanels.GoalsPanel`, `IndexPanel`, `CharmsPanel` | modify | active tab colour `Go` → `Role.Neutral` | 12 |
| `…GameHUDPanels.BackpackPanel` | modify | `fillBag` per UID on `BrainrotCard` + `ViewportCuller`; `SearchBar`; `SortButton`; `Toast` | 13 |
| `game-src/README.md`, memory | docs | round record | 14 |

---

### Task 1: Pre-round checkpoint (live sources → mirror → commit; Studio backup folder)

**Files:**
- Modify (mirror only): `game-src/place-full/ReplicatedStorage/Modules/UIKit/SpecTheme.lua`, `.../UIKit/PanelChrome.lua`, `game-src/place-full/ReplicatedStorage/Modules/BrainrotThumb.lua`, `game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/BackpackPanel.lua`, `.../GameHUDPanels/GoalsPanel.lua`, `.../GameHUDPanels/IndexPanel.lua`, `.../GameHUDPanels/CharmsPanel.lua` (new file — never mirrored), `game-src/place-full/StarterPlayer/StarterPlayerScripts/ToastClient.client.lua`, `.../StarterPlayerScripts/GameHUDClient.client.lua`
- Create (Studio): `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18` (Folder)

**Interfaces:**
- Produces: the git commit `checkpoint: pre UI-foundation round live sources` every later rollback restores from; the Studio backup folder every later task clones into.

- [ ] **Step 1: Confirm Studio and mode.** `list_roblox_studios` → note the id. `get_studio_state` → if Play, `start_stop_play(false)`.

- [ ] **Step 2: Dump the nine live sources to disk.** For each of the nine Studio paths above run `script_read` (entire file) and write the text byte-exact (strip the `LINE→` prefixes the tool adds — the line content only, LF line endings, no trailing newline added or removed beyond what the file has) to its mirror path. Use the Write tool per file. `CharmsPanel.lua` is a new mirror file.

- [ ] **Step 3: Verify byte counts match Studio.** `execute_luau` (Edit):

```lua
local RS, SPS = game:GetService("ReplicatedStorage"), game:GetService("StarterPlayer").StarterPlayerScripts
local list = {
	{ "SpecTheme", RS.Modules.UIKit.SpecTheme }, { "PanelChrome", RS.Modules.UIKit.PanelChrome },
	{ "BrainrotThumb", RS.Modules.BrainrotThumb }, { "BackpackPanel", SPS.GameHUDPanels.BackpackPanel },
	{ "GoalsPanel", SPS.GameHUDPanels.GoalsPanel }, { "IndexPanel", SPS.GameHUDPanels.IndexPanel },
	{ "CharmsPanel", SPS.GameHUDPanels.CharmsPanel }, { "ToastClient", SPS.ToastClient }, { "GameHUDClient", SPS.GameHUDClient },
}
local out = {}
for _, e in ipairs(list) do table.insert(out, e[1] .. " " .. #e[2].Source) end
return table.concat(out, "\n")
```

Compare with `wc -c` of each mirror file (Bash: `wc -c <files>`). Every pair must match exactly (the mirror files must be written with LF endings; if a count is off by the number of lines, the file was written with CRLF — rewrite it). Fix until all nine match.

- [ ] **Step 4: Create the Studio backup folder.** `execute_luau` (Edit):

```lua
local SS = game:GetService("ServerStorage")
local audits = SS:FindFirstChild("AuditBackups") or Instance.new("Folder")
audits.Name = "AuditBackups"; audits.Parent = SS
local f = audits:FindFirstChild("PreUIFoundation_2026_09_18") or Instance.new("Folder")
f.Name = "PreUIFoundation_2026_09_18"; f.Parent = audits
return f:GetFullName()
```

- [ ] **Step 5: Commit the checkpoint.** Bash, from the repo root:

```bash
git add game-src/place-full/ReplicatedStorage/Modules/UIKit/SpecTheme.lua game-src/place-full/ReplicatedStorage/Modules/UIKit/PanelChrome.lua game-src/place-full/ReplicatedStorage/Modules/BrainrotThumb.lua game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/BackpackPanel.lua game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/GoalsPanel.lua game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/IndexPanel.lua game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/CharmsPanel.lua game-src/place-full/StarterPlayer/StarterPlayerScripts/ToastClient.client.lua game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDClient.client.lua
git commit -F <msgfile>
```

Message: `checkpoint: pre UI-foundation round live sources` + one line per file with its byte count + the Co-Authored-By line.

---

### Task 2: Logging on the panel pcalls + the new tokens

**Files:**
- Modify: `StarterPlayer.StarterPlayerScripts.GameHUDClient` (≈ lines 2486–2487 and 2683–2686 — read live)
- Modify: `ReplicatedStorage.Modules.UIKit.SpecTheme` (append before `return S`; retune `S.Scale`)

**Interfaces:**
- Produces: `S.Role = { Positive, Destructive, Neutral, Gold, Purple, Disabled, DisabledButton }` (each `{ Color3, Color3 }`), `S.Role.Selection: Color3`, `S.Space = { micro, small, std, section, large }`, `S.Sound = { Click, PanelOpen, PanelClose }`, `S.Card` (geometry, `Light`, `Ladder`, `MaxLive`, `Variants`, `TIER_KEY`, `PIPS`), `S.Scale = { Hover = 1.03, Press = 0.97 }`. Every later task reads these.

- [ ] **Step 1: Back up both scripts.** `execute_luau` (Edit):

```lua
local SPS, RS = game:GetService("StarterPlayer").StarterPlayerScripts, game:GetService("ReplicatedStorage")
local f = game:GetService("ServerStorage").AuditBackups.PreUIFoundation_2026_09_18
for _, p in ipairs({ { SPS.GameHUDClient, "GameHUDClient_pre2" }, { RS.Modules.UIKit.SpecTheme, "SpecTheme_pre2" } }) do
	local c = p[1]:Clone(); c.Name = p[2]; c.Parent = f
end
return "ok"
```

- [ ] **Step 2: Add the warnings to GameHUDClient.** `script_read` lines 2480–2492 and 2678–2690 to confirm the anchors, then `multi_edit`:

Edit A — `old_string`:
```lua
			local ok, built = pcall(mod.Build, ctx)
			if not ok or typeof(built) ~= "Instance" then return end
```
`new_string`:
```lua
			local ok, built = pcall(mod.Build, ctx)
			if not ok then
				-- fail-soft stays (the game survives a broken panel) but never silent:
				-- spec 2026-09-18 UI foundation §11
				warn(("[UIKit] panel %q Build failed: %s\n%s"):format(tostring(id), tostring(built), debug.traceback()))
				return
			end
			if typeof(built) ~= "Instance" then
				warn(("[UIKit] panel %q Build returned %s, expected a Frame"):format(tostring(id), typeof(built)))
				return
			end
```

Edit B — `old_string`:
```lua
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" and type(mod.Build) == "function" and type(mod.Id) == "string" then
			panelModules[mod.Id] = mod
		end
```
`new_string`:
```lua
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" and type(mod.Build) == "function" and type(mod.Id) == "string" then
			panelModules[mod.Id] = mod
		elseif not ok then
			warn(("[UIKit] panel module %s failed to require: %s\n%s"):format(m.Name, tostring(mod), debug.traceback()))
		elseif type(mod) == "table" and next(mod) == nil then
			-- an empty table is the documented "not registered here" answer (GalleryPanel outside Studio)
		else
			warn(("[UIKit] panel module %s did not return { Id, Build } (got %s)"):format(m.Name, typeof(mod)))
		end
```

- [ ] **Step 3: Compile-gate + byte-scan GameHUDClient.** `execute_luau` (Edit):

```lua
local s = game:GetService("StarterPlayer").StarterPlayerScripts.GameHUDClient
local f, e = loadstring(s.Source); assert(f, e)
assert(s.Source:find('Build failed: %s', 1, true), "edit A missing")
assert(s.Source:find('failed to require', 1, true), "edit B missing")
return "compiles, both edits present"
```

- [ ] **Step 4: Add the tokens to SpecTheme.** `script_read` lines 186–190 and 226–231 (the `S.Scale` line and the tail). `multi_edit` with two edits:

Edit A — `old_string`: `S.Scale = { Hover = 1.06, Press = 0.94 } -- PS99 restyle: a touch livelier (was 1.05/0.95)`
`new_string`: `S.Scale = { Hover = 1.03, Press = 0.97 } -- 2026-09-18 UI foundation (handoff §12): subtle; was 1.06/0.94 (PS99 restyle), 1.05/0.95 before that`

Edit B — `old_string`:
```lua
return S
```
`new_string`:
```lua
-------------------------------------------------------------------- 2026-09-18
-- UI FOUNDATION ROUND 1 (spec docs/superpowers/specs/2026-09-18-ui-foundation-
-- design.md). Semantic colour grammar (handoff §4), spacing scale (§16), sound
-- names, and the BrainrotCard ladder (§5). S.Action.* keep their values as
-- aliases -- S.Action.Neutral stays the light grey because every existing
-- paint closure pairs it as the INACTIVE colour with S.Action.Go.
S.Role = {
	Positive       = S.Action.Go,                       -- equip / claim / confirm / teleport / buy with coins
	Destructive    = S.Action.Danger,                   -- delete / remove / close (one red)
	Neutral        = { hex("4AA8FF"), hex("1E7BE0") },  -- utility, filters, sort, ACTIVE tab (blue = navigation)
	Gold           = S.Action.Robux,                    -- coins, rewards, value, prices (Robux prices carry the Robux mark)
	Purple         = S.Action.Premium,                  -- gems, premium
	Disabled       = S.Action.Neutral,                  -- inactive tabs, secondary chips (dark ink)
	DisabledButton = { hex("B9C2CC"), hex("96A1AD") },  -- a disabled button's fill (label at 0.45 transparency)
	Selection      = hex("29C5FF"),                     -- selected ring (= Tokens.activeRing)
}
S.Space = { micro = 8, small = 12, std = 16, section = 24, large = 32 } -- spec px, same sheet as S.Chrome
S.Sound = { Click = "uiClick", PanelOpen = "panelOpen", PanelClose = "panelClose" } -- SoundKit ids
S.Card = {
	Plate     = { hex("3A4656"), hex("2A3543") },
	Radius    = 14,
	Edge      = 3,
	BandFrac  = 0.20,
	BandMin   = 24,
	ArtInset  = 4,
	Fill      = 0.70,           -- projected-box fill target (handoff §6: 65-75%)
	Pip       = 7,
	Badge     = 22,
	BadgeSmall = 14,
	MutationStar = 16,
	ArtWellAlpha = 0.90,        -- white radial behind the model (transparency at centre)
	MaxAnimatedLayers = 2,
	Light = {                   -- the Bag's relit rig (BackpackPanel build3DOrSwatch, 2026-08-17)
		Dir = Vector3.new(0.18, 0.32, -1).Unit,
		Ambient = Color3.fromRGB(205, 210, 220),
		LightColor = Color3.fromRGB(255, 248, 232),
		LightDirection = Vector3.new(-0.18, -0.32, 1),
	},
	-- PROVISIONAL (spec §8.3): the Gallery stress section replaces these numbers.
	MaxLive = { Desktop = 48, Tablet = 32, Phone = 20 },
	Variants = {
		grid    = { bandMin = 24, leftBadges = true,  rightCap = 2, title = false },
		compact = { bandMin = 20, leftBadges = false, rightCap = 1, title = false },
		hero    = { bandMin = 32, leftBadges = true,  rightCap = 3, title = true },
	},
	-- rarity tier name -> S.Rarity key
	TIER_KEY = { Common = "COM", Uncommon = "UNC", Rare = "RARE", Epic = "EPIC",
		Legendary = "LEG", Mythic = "MYTH", Secret = "SEC", God = "GOD" },
	-- spec §7.4: one table drives every layer. foil = white-sheet transparency or nil,
	-- aura = nil | "breathe" | "strong", band = "muted" | "solid" | "rainbow",
	-- animated = the continuously animated layers (max 2), holo/sparkles booleans.
	Ladder = {
		COM  = { pips = 1, band = "muted",   foil = nil,  aura = nil,       holo = false, sparkles = false, animated = {} },
		UNC  = { pips = 1, band = "solid",   foil = nil,  aura = nil,       holo = false, sparkles = false, animated = {} },
		RARE = { pips = 2, band = "solid",   foil = nil,  aura = nil,       holo = false, sparkles = false, animated = {} },
		EPIC = { pips = 3, band = "solid",   foil = 0.87, aura = nil,       holo = false, sparkles = false, animated = {} },
		LEG  = { pips = 4, band = "solid",   foil = 0.80, aura = "breathe", holo = false, sparkles = false, animated = { "aura" } },
		MYTH = { pips = 5, band = "rainbow", foil = 0.70, aura = "breathe", holo = true,  sparkles = false, animated = { "band", "aura" } },
		SEC  = { pips = 5, band = "rainbow", foil = 0.70, aura = "strong",  holo = true,  sparkles = true,  animated = { "band", "sparkles" } },
		GOD  = { pips = 5, band = "rainbow", foil = 0.70, aura = "strong",  holo = true,  sparkles = true,  animated = { "band", "sparkles" } },
	},
	Rainbow = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, hex("FF2D6F")), ColorSequenceKeypoint.new(0.17, hex("FF9B2F")),
		ColorSequenceKeypoint.new(0.33, hex("F5F24A")), ColorSequenceKeypoint.new(0.50, hex("58F06A")),
		ColorSequenceKeypoint.new(0.67, hex("3FE0FF")), ColorSequenceKeypoint.new(0.83, hex("C93AFF")),
		ColorSequenceKeypoint.new(1.00, hex("FF2D6F")),
	}),
}

return S
```

- [ ] **Step 5: Compile-gate + assert the tokens.** `execute_luau` (Edit):

```lua
local CoreGui = game:GetService("CoreGui")
local src = game:GetService("ReplicatedStorage").Modules.UIKit.SpecTheme
local f, e = loadstring(src.Source); assert(f, e)
local kit = game:GetService("ReplicatedStorage").Modules.UIKit:Clone(); kit.Name = "UIKitTest"; kit.Parent = CoreGui
local S = load(kit.SpecTheme)
assert(S.Role.Neutral[1] == Color3.fromHex("4AA8FF"), "Neutral blue")
assert(S.Role.Disabled == S.Action.Neutral and S.Action.Neutral[1] == Color3.fromHex("D3DCE6"), "Disabled = old grey Neutral")
assert(S.Role.Positive == S.Action.Go and S.Role.Destructive == S.Action.Danger, "aliases")
assert(S.Space.std == 16 and S.Space.large == 32, "space")
assert(S.Scale.Hover == 1.03 and S.Scale.Press == 0.97, "scale")
assert(S.Card.Ladder.GOD.sparkles == true and #S.Card.Ladder.MYTH.animated == 2, "ladder")
for k, l in pairs(S.Card.Ladder) do assert(#l.animated <= S.Card.MaxAnimatedLayers, k .. " animated cap") end
assert(S.Card.TIER_KEY.Legendary == "LEG", "tier key")
return "SpecTheme OK"
```

Expected: `SpecTheme OK`.

- [ ] **Step 6: Live sanity.** `start_stop_play(true)`; from `execute_luau` (Client) open the Bag: `game.Players.LocalPlayer:SetAttribute("HudOpenPanel", nil); local h = game.Players.LocalPlayer.PlayerGui.GameHUD.Chrome.NavRail:FindFirstChild("bagItem"); return h and h:GetFullName()` — then `user_mouse_input` click on `LocalPlayer.PlayerGui.GameHUD.Chrome.NavRail.bagItem.Hit`. Confirm via `get_console_output` that no `[UIKit]` warning fired and the Bag opened (`LocalPlayer:GetAttribute("HudOpenPanel") == "bag"`). `start_stop_play(false)`.

- [ ] **Step 7: Mirror + commit.** `script_read` both scripts → overwrite `game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDClient.client.lua` and `game-src/place-full/ReplicatedStorage/Modules/UIKit/SpecTheme.lua`; `git add` those two; commit `feat(ui): semantic colour roles, spacing, card ladder tokens; panel pcalls now warn`.

---

### Task 3: `FxDriver` — the one Heartbeat for kit animation

**Files:**
- Create: `ReplicatedStorage.Modules.UIKit.FxDriver` (ModuleScript)

**Interfaces:**
- Produces: `FxDriver.register(gui: GuiObject, step: (t: number, dt: number) -> ()): number`, `FxDriver.unregister(id: number?)`, `FxDriver.isRunning(): boolean`, `FxDriver.count(): number`, `FxDriver.clock(): number`. Used by `PanelChrome.setBusy` (Task 4), `Toast` (7), `BrainrotCard` (9), `GalleryPanel` (11).

- [ ] **Step 1: Create the module.** `multi_edit` with `file_path = "game.ReplicatedStorage.Modules.UIKit.FxDriver"`, `className = "ModuleScript"`, one edit with `old_string = ""` and this `new_string`:

```lua
--!strict
-- FxDriver -- the ONE Heartbeat for every kit animation (card auras, rainbow bands,
-- sparkles, busy dots, toast fades). TweenService cannot animate transparency or
-- gradient offsets in this place (probed live, see roblox-tweenservice-guiobject-only),
-- so every continuous decorative effect is a per-frame property write. One connection
-- for the whole client: it disconnects when the registry empties and reconnects on the
-- next register. Entries whose GuiObject is off screen are skipped, not removed, so a
-- hidden panel costs nothing per frame and resumes where it was.
-- Spec: docs/superpowers/specs/2026-09-18-ui-foundation-design.md §7.6, §12.
local RunService = game:GetService("RunService")

export type Step = (t: number, dt: number) -> ()
type Entry = { gui: GuiObject, step: Step }

local FxDriver = {}

local entries: { [number]: Entry } = {}
local count = 0
local nextId = 0
local conn: RBXScriptConnection? = nil
local clock = 0

-- "Is this gui actually being drawn?" Visible alone lies about hidden ancestors, so
-- walk up to the LayerCollector. Cheap: a card is ~10 levels deep.
local function isShown(gui: GuiObject): boolean
	if not gui.Parent then return false end
	local o: Instance? = gui
	while o and o:IsA("GuiObject") do
		if not (o :: GuiObject).Visible then return false end
		o = o.Parent
	end
	if o and o:IsA("LayerCollector") then return (o :: LayerCollector).Enabled end
	return o ~= nil
end

local function tick(dt: number)
	clock += dt
	for id, e in pairs(entries) do
		if isShown(e.gui) then
			local ok, err = pcall(e.step, clock, dt)
			if not ok then
				warn(("[UIKit] FxDriver entry %d threw and was removed: %s\n%s"):format(id, tostring(err), debug.traceback()))
				FxDriver.unregister(id)
			end
		end
	end
end

-- Published as attributes on this ModuleScript so a probe from another Lua VM
-- (execute_luau runs in its own) can read the driver's state during verification.
local function publish()
	script:SetAttribute("FxEntries", count)
	script:SetAttribute("FxRunning", conn ~= nil)
end

function FxDriver.register(gui: GuiObject, step: Step): number
	nextId += 1
	entries[nextId] = { gui = gui, step = step }
	count += 1
	if not conn then
		conn = RunService.Heartbeat:Connect(tick)
	end
	publish()
	return nextId
end

function FxDriver.unregister(id: number?)
	if id == nil or entries[id] == nil then return end
	entries[id] = nil
	count -= 1
	if count <= 0 then
		count = 0
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end
	publish()
end

function FxDriver.isRunning(): boolean
	return conn ~= nil
end

function FxDriver.count(): number
	return count
end

function FxDriver.clock(): number
	return clock
end

return FxDriver
```

- [ ] **Step 2: Compile-gate + behaviour test.** `execute_luau` (Edit):

```lua
-- [TEST LOADER PREAMBLE from .superpowers/sdd/2026-09-18-ui-foundation/test-loader.lua goes here]
local f, e = loadstring(RS.Modules.UIKit.FxDriver.Source); assert(f, e)
local Fx = load(kit.FxDriver)
local sg = Instance.new("ScreenGui"); sg.Name = "UIKitScratch"; sg.Parent = CoreGui
local a = Instance.new("Frame"); a.Parent = sg
local b = Instance.new("Frame"); b.Visible = false; b.Parent = sg
assert(not Fx.isRunning(), "idle at start")
local ca, cb = 0, 0
local ia = Fx.register(a, function() ca += 1 end)
local ib = Fx.register(b, function() cb += 1 end)
assert(Fx.isRunning() and Fx.count() == 2, "running with 2")
task.wait(0.3)
assert(ca > 0, "shown entry stepped")
assert(cb == 0, "hidden entry skipped")
local ic = Fx.register(a, function() error("boom") end)
task.wait(0.1)
assert(Fx.count() == 2, "throwing entry removed itself (count back to 2)")
Fx.unregister(ia); Fx.unregister(ib); Fx.unregister(ic)
assert(not Fx.isRunning() and Fx.count() == 0, "stands down when empty")
sg.Parent = nil
return ("FxDriver OK (a stepped %d times)"):format(ca)
```

Expected: `FxDriver OK (a stepped N times)` with N ≥ 1, and one `[UIKit] FxDriver entry … threw` warning in `get_console_output`.

- [ ] **Step 3: Mirror + commit.** `script_read` → `game-src/place-full/ReplicatedStorage/Modules/UIKit/FxDriver.lua`; commit `feat(ui): FxDriver, the one Heartbeat for kit animation`.

---

### Task 4: `PanelChrome` buttons — `button`, `setEnabled`, `setBusy`, press-feedback guards, click sound, `pill.outline`, header-tab/segmented grammar sweep

**Files:**
- Modify: `ReplicatedStorage.Modules.UIKit.PanelChrome` — top requires (≈ line 27), `bindPressFeedback` (≈ 176–212), `pill` (≈ 471–517), `addHeaderTabs` paint (≈ 419, 443), `segmented` (≈ 961–1015); new functions inserted after `pill`.

**Interfaces:**
- Consumes: `S.Role`, `S.Sound`, `S.Scale` (Task 2), `FxDriver` (Task 3).
- Produces: `PanelChrome.button(props: { kind: ("positive" | "neutral" | "destructive" | "gold" | "purple" | "secondary")?, text: string, size: (UDim2 | "small")?, icon: string?, enabled: boolean?, sound: boolean?, onActivated: (() -> ())?, parent: Instance?, zIndex: number?, layoutOrder: number?, name: string?, position: UDim2?, anchor: Vector2?, textSize: number?, radius: number?, outline: number? }): TextButton` (`secondary` = the grey `S.Role.Disabled` ramp with dark ink, for quiet options like Cancel); `PanelChrome.setEnabled(btn: GuiButton, on: boolean)`; `PanelChrome.setBusy(btn: GuiButton, on: boolean, opts: { timeout: number? }?)`; `pill` accepts `outline: number?`; `segmented` accepts `radius`, `outline`, `textSize`. Button attributes: `UIKind`, `UIRampTop`, `UIRampBottom`, `UIRestSize`, `UIEnabled` (false when disabled), `UIBusy` (true while busy), `SfxMuted`.

- [ ] **Step 1: Back up.** Clone `PanelChrome` into the backup folder as `PanelChrome_pre4` (same snippet shape as Task 2 Step 1).

- [ ] **Step 2: Requires.** `script_read` lines 20–30. `multi_edit` — `old_string`:
```lua
local Platform = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Platform"))
```
`new_string`:
```lua
local Platform = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Platform"))
-- 2026-09-18 UI foundation: click sound on every kit button (handoff §11) and the
-- shared Heartbeat driver for the busy indicator. SoundKit never requires UIKit.
local SoundKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundKit"))
local FxDriver = require(script.Parent:WaitForChild("FxDriver"))
local CLICK_VOLUME = 0.12 -- same level GameHUDClient.wireClick uses on the rail
```

- [ ] **Step 3: `bindPressFeedback` — remember rest size, honour disabled/busy, play the click.** `script_read` 176–212. `multi_edit` with three edits:

Edit A — `old_string`:
```lua
function PanelChrome.bindPressFeedback(button: GuiButton)
	local rest = button.Size
	local hovering = false
```
`new_string`:
```lua
function PanelChrome.bindPressFeedback(button: GuiButton)
	local rest = button.Size
	-- setEnabled/setBusy read this back to snap a hovered button to rest
	button:SetAttribute("UIRestSize", rest)
	local hovering = false
	-- disabled (UIEnabled == false) and busy (UIBusy == true) buttons give no feedback
	local function blocked(): boolean
		return button:GetAttribute("UIEnabled") == false or button:GetAttribute("UIBusy") == true
	end
```

Edit B — `old_string`:
```lua
	button.MouseEnter:Connect(function()
		if touchOnly then return end
		hovering = true
		to(S.Scale.Hover, S.Tween.HoverIn)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		to(1, S.Tween.HoverOut)
	end)
	button.MouseButton1Down:Connect(function() to(S.Scale.Press, S.Tween.Press) end)
	button.MouseButton1Up:Connect(function()
		if hovering then to(S.Scale.Hover, S.Tween.HoverIn) else to(1, S.Tween.HoverOut) end
	end)
end
```
`new_string`:
```lua
	button.MouseEnter:Connect(function()
		if touchOnly or blocked() then return end
		hovering = true
		to(S.Scale.Hover, S.Tween.HoverIn)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		if blocked() then return end
		to(1, S.Tween.HoverOut)
	end)
	button.MouseButton1Down:Connect(function()
		if blocked() then return end
		to(S.Scale.Press, S.Tween.Press)
	end)
	button.MouseButton1Up:Connect(function()
		if blocked() then return end
		if hovering then to(S.Scale.Hover, S.Tween.HoverIn) else to(1, S.Tween.HoverOut) end
	end)
	-- Click sound (handoff §11 "sound behavior" shared by all buttons). Same SfxWired
	-- attribute convention as GameHUDClient.wireClick, so a button wired there too
	-- can only ever carry one connection. SfxMuted opts a button out (the shell's
	-- close button: closePanel already plays panelClose).
	if not button:GetAttribute("SfxWired") then
		button:SetAttribute("SfxWired", true)
		button.MouseButton1Click:Connect(function()
			if blocked() or button:GetAttribute("SfxMuted") == true then return end
			pcall(SoundKit.play, S.Sound.Click, nil, { volume = CLICK_VOLUME })
		end)
	end
end
```

Edit C (the shell's close button must not double-sound) — `old_string`:
```lua
	PanelChrome.shout({ text = "X", size = 40, zIndex = z + 4, parent = close })
	PanelChrome.bindPressFeedback(close)
```
`new_string`:
```lua
	PanelChrome.shout({ text = "X", size = 40, zIndex = z + 4, parent = close })
	close:SetAttribute("SfxMuted", true) -- closePanel plays panelClose
	PanelChrome.bindPressFeedback(close)
```

- [ ] **Step 4: `pill` — `outline` prop, runtime disabled path.** `script_read` 471–517 (numbers shifted by Step 3; re-read). `multi_edit` with three edits:

Edit A — `old_string`:
```lua
	anchor: Vector2?, textSize: number?, parent: Instance?, enabled: boolean?,
	zIndex: number?, radius: number?, name: string?, layoutOrder: number?,
}): TextButton
	local C = S.Chrome
	local z = props.zIndex or (Z + 3)
	local b = Instance.new("TextButton")
	b.Name = props.name or "Pill"
```
`new_string`:
```lua
	anchor: Vector2?, textSize: number?, parent: Instance?, enabled: boolean?,
	zIndex: number?, radius: number?, name: string?, layoutOrder: number?,
	outline: number?, -- 2026-09-18: small controls (36px sort chips) need a thinner edge than CtaOutline
}): TextButton
	local C = S.Chrome
	local z = props.zIndex or (Z + 3)
	local b = Instance.new("TextButton")
	b.Name = props.name or "Pill"
```

Edit B — `old_string`:
```lua
	corner(b, props.radius or C.CtaRadius)
	stroke(b, C.CtaOutline)
	gradient(b, props.colors[1], props.colors[2])
	gloss(b, props.radius or C.CtaRadius, 0.22)
```
`new_string`:
```lua
	corner(b, props.radius or C.CtaRadius)
	stroke(b, props.outline or C.CtaOutline)
	gradient(b, props.colors[1], props.colors[2])
	gloss(b, props.radius or C.CtaRadius, 0.22)
```

Edit C — `old_string`:
```lua
	if props.enabled == false then
		b.Active = false
		b.BackgroundTransparency = 0.45
		for _, d in ipairs(b:GetDescendants()) do
			if d:IsA("TextLabel") then d.TextTransparency = 0.45 end
		end
	else
		PanelChrome.bindPressFeedback(b)
	end
	b.Parent = props.parent
	return b
end
```
`new_string`:
```lua
	-- ramp remembered for setEnabled/setBusy repaints (legacy pills included)
	b:SetAttribute("UIRampTop", props.colors[1])
	b:SetAttribute("UIRampBottom", props.colors[2])
	PanelChrome.bindPressFeedback(b)
	if props.enabled == false then
		-- 2026-09-18: the runtime disabled state (spec §6.2) replaces the old
		-- build-time-only transparency fade; callers can re-enable later
		PanelChrome.setEnabled(b, false)
	end
	b.Parent = props.parent
	return b
end

------------------------------------------------------------- semantic buttons
-- 2026-09-18 UI foundation (spec §6.2, handoff §11). kind -> S.Role ramp. Built ON
-- pill so geometry, gloss and the >0.82-luminance ink gate are shared. The ramp is
-- remembered on the button as attributes so the runtime states repaint without
-- guessing, and a disabled/busy button is Interactable = false so consumer-wired
-- Activated handlers cannot fire either.
-- "secondary" = the quiet grey option (Cancel, Hide Plot): handoff §4 "Gray = secondary"
local KIND_ROLE = { positive = "Positive", neutral = "Neutral", destructive = "Destructive", gold = "Gold", purple = "Purple", secondary = "Disabled" }
local BUSY_DOTS = "\u{00B7} \u{00B7} \u{00B7}"

local function inkFor(top: Color3): (Color3, Color3)
	local lum = top.R * 0.299 + top.G * 0.587 + top.B * 0.114
	if lum > 0.82 then return S.Surface.ReadInk, Color3.new(1, 1, 1) end
	return Color3.new(1, 1, 1), S.Outline
end

local function repaintLabel(btn: GuiButton, top: Color3)
	local label = btn:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		local ink, strokeC = inkFor(top)
		label.TextColor3 = ink
		local ls = label:FindFirstChildOfClass("UIStroke")
		if ls then ls.Color = strokeC end
	end
end

local function snapToRest(btn: GuiButton)
	local rest = btn:GetAttribute("UIRestSize")
	if typeof(rest) == "UDim2" then btn.Size = rest end
end

function PanelChrome.button(props: {
	kind: string?, text: string, size: (UDim2 | string)?, icon: string?, enabled: boolean?,
	sound: boolean?, onActivated: (() -> ())?, parent: Instance?, zIndex: number?,
	layoutOrder: number?, name: string?, position: UDim2?, anchor: Vector2?,
	textSize: number?, radius: number?, outline: number?,
}): TextButton
	local kindKey = props.kind or "positive"
	local roleName = KIND_ROLE[kindKey]
	if not roleName then
		warn(("[UIKit] button: unknown kind %q, using positive"):format(tostring(props.kind)))
		roleName = "Positive"
		kindKey = "positive"
	end
	local ramp = S.Role[roleName]
	local size: UDim2
	if typeof(props.size) == "UDim2" then
		size = props.size :: UDim2
	elseif props.size == "small" then
		size = UDim2.fromOffset(160, 64)
	else
		size = UDim2.fromOffset(S.Chrome.CtaSize.X, S.Chrome.CtaSize.Y)
	end
	local b = PanelChrome.pill({
		text = props.text, colors = ramp, size = size, position = props.position, anchor = props.anchor,
		textSize = props.textSize, zIndex = props.zIndex, radius = props.radius, outline = props.outline,
		name = props.name or ("Button_" .. kindKey), layoutOrder = props.layoutOrder,
	})
	b:SetAttribute("UIKind", kindKey)
	if props.sound == false then b:SetAttribute("SfxMuted", true) end
	if props.icon and props.icon ~= "" then
		local ic = Instance.new("ImageLabel")
		ic.Name = "Icon"
		ic.Image = props.icon
		ic.BackgroundTransparency = 1
		ic.ScaleType = Enum.ScaleType.Fit
		ic.AnchorPoint = Vector2.new(0, 0.5)
		ic.Position = UDim2.new(0, 14, 0.5, 0)
		ic.Size = UDim2.fromOffset(40, 40)
		ic.ZIndex = b.ZIndex + 2
		ic.Parent = b
		local label = b:FindFirstChild("Label")
		if label then
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 44)
			pad.Parent = label
		end
	end
	if props.onActivated then
		b.Activated:Connect(function()
			if b:GetAttribute("UIEnabled") == false or b:GetAttribute("UIBusy") == true then return end
			props.onActivated()
		end)
	end
	if props.enabled == false then PanelChrome.setEnabled(b, false) end
	b.Parent = props.parent
	return b
end

--- Runtime enable/disable. Disabled = grey ramp, dimmed label, no input, no feedback.
function PanelChrome.setEnabled(btn: GuiButton, on: boolean)
	local g = btn:FindFirstChildOfClass("UIGradient")
	local label = btn:FindFirstChild("Label")
	if on then
		btn:SetAttribute("UIEnabled", nil)
		if btn:GetAttribute("UIBusy") ~= true then
			btn.Interactable = true
			btn.Active = true
		end
		local top, bottom = btn:GetAttribute("UIRampTop"), btn:GetAttribute("UIRampBottom")
		if typeof(top) == "Color3" and typeof(bottom) == "Color3" then
			btn.BackgroundColor3 = top
			if g then g.Color = ColorSequence.new(top, bottom) end
			repaintLabel(btn, top)
		end
		btn.BackgroundTransparency = 0
		if label and label:IsA("TextLabel") then
			label.TextTransparency = if btn:GetAttribute("UIBusy") == true then 0.35 else 0
		end
	else
		if btn:GetAttribute("UIRampTop") == nil then
			-- a hand-built button: remember what it wore so re-enabling restores it
			btn:SetAttribute("UIRampTop", btn.BackgroundColor3)
			local bottom = btn.BackgroundColor3
			if g then
				local kps = g.Color.Keypoints
				bottom = kps[#kps].Value
			end
			btn:SetAttribute("UIRampBottom", bottom)
		end
		btn:SetAttribute("UIEnabled", false)
		btn.Interactable = false
		btn.Active = false
		snapToRest(btn)
		local d = S.Role.DisabledButton
		btn.BackgroundColor3 = d[1]
		if g then g.Color = ColorSequence.new(d[1], d[2]) end
		repaintLabel(btn, d[1])
		if label and label:IsA("TextLabel") then label.TextTransparency = 0.45 end
	end
end

--- Busy = "waiting on the server": keeps size and ramp, blocks input/feedback/sound,
--- dims the label and pulses three dots. Auto-clears after `timeout` (default 10s)
--- with a warning so a lost reply can never brick a button. Distinct from disabled.
function PanelChrome.setBusy(btn: GuiButton, on: boolean, opts: { timeout: number? }?)
	local label = btn:FindFirstChild("Label")
	if on then
		if btn:GetAttribute("UIBusy") == true then return end
		btn:SetAttribute("UIBusy", true)
		btn.Interactable = false
		btn.Active = false
		snapToRest(btn)
		if label and label:IsA("TextLabel") then label.TextTransparency = 0.35 end
		local dots = Instance.new("TextLabel")
		dots.Name = "BusyDots"
		dots.BackgroundTransparency = 1
		dots.Size = UDim2.fromScale(1, 1)
		dots.Font = S.Font.Shout
		dots.TextSize = 30
		dots.Text = BUSY_DOTS
		dots.TextColor3 = Color3.new(1, 1, 1)
		dots.TextXAlignment = Enum.TextXAlignment.Center
		dots.ZIndex = btn.ZIndex + 3
		dots:SetAttribute("NoPolish", true)
		local ds = Instance.new("UIStroke")
		ds.Thickness = 2
		ds.Color = S.Outline
		ds.Parent = dots
		dots.Parent = btn
		local fxId = FxDriver.register(btn, function(t)
			dots.TextTransparency = 0.15 + 0.55 * (0.5 + 0.5 * math.sin(t * 5))
		end)
		btn:SetAttribute("UIBusyFx", fxId)
		local gen = (tonumber(btn:GetAttribute("UIBusyGen")) or 0) + 1
		btn:SetAttribute("UIBusyGen", gen)
		local timeout = (opts and opts.timeout) or 10
		task.delay(timeout, function()
			if btn.Parent and btn:GetAttribute("UIBusy") == true and btn:GetAttribute("UIBusyGen") == gen then
				warn(("[UIKit] setBusy: %s still busy after %.1fs -- clearing (lost reply?)"):format(btn:GetFullName(), timeout))
				PanelChrome.setBusy(btn, false)
			end
		end)
	else
		if btn:GetAttribute("UIBusy") ~= true then return end
		btn:SetAttribute("UIBusy", nil)
		FxDriver.unregister(tonumber(btn:GetAttribute("UIBusyFx")))
		btn:SetAttribute("UIBusyFx", nil)
		local dots = btn:FindFirstChild("BusyDots")
		if dots then dots:Destroy() end
		local disabled = btn:GetAttribute("UIEnabled") == false
		if not disabled then
			btn.Interactable = true
			btn.Active = true
		end
		if label and label:IsA("TextLabel") then label.TextTransparency = if disabled then 0.45 else 0 end
	end
end
```

- [ ] **Step 5: Grammar sweep in `addHeaderTabs` and `segmented`.** `script_read` the `paint()` closures (search `delta 7: active = GREEN`). `multi_edit` with four edits:

Edit A — `old_string`:
```lua
			-- field study delta 7: active = GREEN (PS99 colour grammar; gold is
			-- reserved for real-money surfaces)
			local c = if i == current then S.Action.Go else S.Action.Neutral
```
`new_string`:
```lua
			-- 2026-09-18 UI foundation (handoff §4): blue = navigation, so the ACTIVE
			-- tab is S.Role.Neutral and the inactive one the grey S.Role.Disabled
			-- (was field-study delta 7: active = green)
			local c = if i == current then S.Role.Neutral else S.Role.Disabled
```

Edit B — `old_string`:
```lua
			local b = PanelChrome.pill({
				text = tab.text,
				colors = S.Action.Neutral,
				size = UDim2.fromOffset(tab.width, 72),
```
`new_string`:
```lua
			local b = PanelChrome.pill({
				text = tab.text,
				colors = S.Role.Disabled,
				size = UDim2.fromOffset(tab.width, 72),
```

Edit C — `old_string`:
```lua
function PanelChrome.segmented(props: {
	options: { string }, selected: number?, size: UDim2, position: UDim2?,
	parent: Instance?, zIndex: number?, onChanged: ((number, string) -> ())?,
})
```
`new_string`:
```lua
function PanelChrome.segmented(props: {
	options: { string }, selected: number?, size: UDim2, position: UDim2?,
	parent: Instance?, zIndex: number?, onChanged: ((number, string) -> ())?,
	radius: number?, outline: number?, textSize: number?, -- 2026-09-18: SortButton passes small-control geometry
})
```

Edit D — `old_string`:
```lua
			-- field study delta 7: active = GREEN, same rule as addHeaderTabs
			local c = if i == selected then S.Action.Go else S.Action.Neutral
```
`new_string`:
```lua
			-- 2026-09-18 UI foundation: active = blue (navigation), inactive = grey
			local c = if i == selected then S.Role.Neutral else S.Role.Disabled
```

Edit E — `old_string`:
```lua
		local b = PanelChrome.pill({
			text = opt,
			colors = S.Action.Neutral,
			size = UDim2.new(1 / #props.options, -math.ceil(12 * (#props.options - 1) / #props.options), 1, 0),
			zIndex = z + 1,
			parent = holder,
			radius = 24,
		})
```
`new_string`:
```lua
		local b = PanelChrome.pill({
			text = opt,
			colors = S.Role.Disabled,
			size = UDim2.new(1 / #props.options, -math.ceil(12 * (#props.options - 1) / #props.options), 1, 0),
			zIndex = z + 1,
			parent = holder,
			radius = props.radius or 24,
			outline = props.outline,
			textSize = props.textSize,
		})
```

- [ ] **Step 6: Compile-gate + byte-scan + behaviour test.** `execute_luau` (Edit):

```lua
-- [TEST LOADER PREAMBLE from .superpowers/sdd/2026-09-18-ui-foundation/test-loader.lua goes here]
local live = RS.Modules.UIKit.PanelChrome
local f, e = loadstring(live.Source); assert(f, e)
for _, needle in ipairs({ "function PanelChrome.button(", "function PanelChrome.setEnabled(", "function PanelChrome.setBusy(",
	"UIRestSize", "SfxMuted", "props.outline or C.CtaOutline", "S.Role.Neutral else S.Role.Disabled", "radius = props.radius or 24" }) do
	assert(live.Source:find(needle, 1, true), "missing: " .. needle)
end
local S, PC, Fx = load(kit.SpecTheme), load(kit.PanelChrome), load(kit.FxDriver)
local sg = Instance.new("ScreenGui"); sg.Name = "UIKitScratch"; sg.Parent = CoreGui
local report = {}
for _, kind in ipairs({ "positive", "neutral", "destructive", "gold", "purple" }) do
	local b = PC.button({ kind = kind, text = kind:upper(), parent = sg })
	assert(b:GetAttribute("UIKind") == kind, kind .. " kind attr")
	assert(b.BackgroundColor3 == S.Role[({ positive = "Positive", neutral = "Neutral", destructive = "Destructive", gold = "Gold", purple = "Purple" })[kind]][1], kind .. " ramp")
	assert(b:GetAttribute("SfxWired") == true and b:GetAttribute("UIRestSize") ~= nil, kind .. " wired")
end
-- unknown kind warns and falls back
local u = PC.button({ kind = "banana", text = "?", parent = sg }); assert(u:GetAttribute("UIKind") == "positive", "fallback kind")
-- small + icon
local sm = PC.button({ kind = "neutral", text = "SORT", size = "small", icon = "rbxassetid://135692251028443", parent = sg })
assert(sm.Size.Y.Offset == 64 and sm:FindFirstChild("Icon"), "small + icon")
-- disabled
local fired = 0
local d = PC.button({ kind = "positive", text = "GO", parent = sg, onActivated = function() fired += 1 end })
PC.setEnabled(d, false)
assert(d.Interactable == false and d:GetAttribute("UIEnabled") == false and d.BackgroundColor3 == S.Role.DisabledButton[1], "disabled state")
assert(math.abs(d.Label.TextTransparency - 0.45) < 1e-3, "disabled label dim") -- float32 property: compare with epsilon
PC.setEnabled(d, true)
assert(d.Interactable == true and d:GetAttribute("UIEnabled") == nil and d.BackgroundColor3 == S.Role.Positive[1], "re-enabled")
-- busy
PC.setBusy(d, true, { timeout = 0.4 })
assert(d:GetAttribute("UIBusy") == true and d:FindFirstChild("BusyDots") and Fx.isRunning(), "busy on")
assert(d.BackgroundColor3 == S.Role.Positive[1], "busy keeps ramp")
task.wait(0.7)
assert(d:GetAttribute("UIBusy") == nil and not d:FindFirstChild("BusyDots") and not Fx.isRunning(), "busy timed out + driver stood down")
PC.setBusy(d, true); PC.setEnabled(d, false); PC.setBusy(d, false)
assert(d.Interactable == false and math.abs(d.Label.TextTransparency - 0.45) < 1e-3, "busy cleared while disabled stays disabled")
PC.setEnabled(d, true)
-- legacy pill: disabled via enabled=false still has a ramp to restore
local p = PC.pill({ text = "OLD", colors = S.Action.Go, size = UDim2.fromOffset(200, 60), enabled = false, parent = sg })
assert(p.Interactable == false and typeof(p:GetAttribute("UIRampTop")) == "Color3", "pill enabled=false -> setEnabled")
PC.setEnabled(p, true); assert(p.BackgroundColor3 == S.Action.Go[1], "pill restored")
-- pill outline
local thin = PC.pill({ text = "T", colors = S.Role.Neutral, size = UDim2.fromOffset(96, 36), outline = 3, parent = sg })
assert(thin:FindFirstChildOfClass("UIStroke").Thickness == 3, "pill outline")
-- segmented + header tabs grammar
local seg = PC.segmented({ options = { "A", "B" }, selected = 2, size = UDim2.fromOffset(300, 64), parent = sg })
local segBtns = {}; for _, c in ipairs(seg.root:GetChildren()) do if c:IsA("TextButton") then table.insert(segBtns, c) end end
table.sort(segBtns, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
assert(segBtns[2].BackgroundColor3 == S.Role.Neutral[1] and segBtns[1].BackgroundColor3 == S.Role.Disabled[1], "segmented paint")
local shell = PC.shell({ name = "T", title = "T", key = "settings", parent = sg })
assert(shell.close:GetAttribute("SfxMuted") == true, "close muted")
local tabs = shell.addHeaderTabs({ { text = "ONE", width = 160 }, { text = "TWO", width = 160 } }, 1, function() end)
local hb = {}; for _, c in ipairs(shell.header.HeaderTabs:GetChildren()) do if c:IsA("TextButton") then hb[c.LayoutOrder] = c end end
assert(hb[1].BackgroundColor3 == S.Role.Neutral[1] and hb[2].BackgroundColor3 == S.Role.Disabled[1], "header tabs paint")
assert(hb[1].Label.TextColor3 == Color3.new(1, 1, 1) and hb[2].Label.TextColor3 == S.Surface.ReadInk, "header tab ink")
sg.Parent = nil
return "PanelChrome buttons OK"
```

Expected: `PanelChrome buttons OK`; console shows one `unknown kind "banana"` warning and one `setBusy … still busy after 0.4s` warning.

- [ ] **Step 7: Live regression (grammar sweep visible).** `start_stop_play(true)`, open the Progress panel (`user_mouse_input` click `LocalPlayer.PlayerGui.GameHUD.Chrome.NavRail.goalsItem.Hit`), `screen_capture` (foreground Studio first): the active header tab is blue with white text, the inactive one grey with dark text; hover a tab and confirm the pop is subtle. Console clean. `start_stop_play(false)`.

- [ ] **Step 8: Mirror + commit.** `script_read` → `game-src/place-full/ReplicatedStorage/Modules/UIKit/PanelChrome.lua`; commit `feat(ui): semantic buttons with disabled/busy states, click sound, blue active tabs`.

---

### Task 5: `PanelChrome.shell` slots — `stat`, `primaryAction`, `addFooter`

**Files:**
- Modify: `ReplicatedStorage.Modules.UIKit.PanelChrome` — `shell` (props type, after the close button, the `shellApi` table, before `root.Parent = props.parent`).

**Interfaces:**
- Consumes: `PanelChrome.button` (Task 4).
- Produces: `shell` props `stat: { text: string, icon: string? }?` and `primaryAction: { kind: string?, text: string, onActivated: (() -> ())? }?`; `shellApi.stat: TextLabel?`, `shellApi.setStat(text: string)`, `shellApi.primaryAction: TextButton?`, `shellApi.addFooter(spec: { left: { ButtonSpec }?, right: { ButtonSpec }? }): Frame` where `ButtonSpec = { kind: string?, text: string, size: (UDim2 | string)?, onActivated: (() -> ())?, name: string? }`; `shellApi.footer: Frame?`. Body and watermark shrink by `72 + S.Chrome.RowGap` when a footer exists. Rule (documented, not enforced): destructive actions go in `right`.

- [ ] **Step 1: Back up** `PanelChrome` as `PanelChrome_pre5`.

- [ ] **Step 2: Props + header slots.** `script_read` the `shell` header (search `function PanelChrome.shell(`) through `local body: GuiObject`. `multi_edit` with two edits:

Edit A — `old_string`:
```lua
function PanelChrome.shell(props: {
	name: string, title: string, key: string,
	size: Vector2?, parent: Instance?, scroll: boolean?, zIndex: number?,
	icon: string?, listLayout: boolean?,
})
```
`new_string`:
```lua
function PanelChrome.shell(props: {
	name: string, title: string, key: string,
	size: Vector2?, parent: Instance?, scroll: boolean?, zIndex: number?,
	icon: string?, listLayout: boolean?,
	-- 2026-09-18 UI foundation (handoff §2 header anatomy): optional summary stat
	-- under the title and one primary action beside the close. Both optional, so
	-- every existing caller is unchanged.
	stat: { text: string, icon: string? }?,
	primaryAction: { kind: string?, text: string, onActivated: (() -> ())? }?,
})
```

Edit B — `old_string`:
```lua
	UI.touchMin(close, 44, function(btn)
		local c = btn:FindFirstChildOfClass("UICorner")
		if c then c.CornerRadius = UDim.new(0, math.floor(btn.Size.X.Offset * 0.3)) end
	end)

	local body: GuiObject
```
`new_string`:
```lua
	UI.touchMin(close, 44, function(btn)
		local c = btn:FindFirstChildOfClass("UICorner")
		if c then c.CornerRadius = UDim.new(0, math.floor(btn.Size.X.Offset * 0.3)) end
	end)

	-- HEADER STAT (spec §6.1): one read-style line under the title -- the header
	-- band is 112 tall and the title straddles its top edge, so 56..100 is free.
	local statLabel: TextLabel? = nil
	if props.stat then
		local sx = hx
		if props.stat.icon and props.stat.icon ~= "" then
			local si = Instance.new("ImageLabel")
			si.Name = "StatIcon"
			si.Image = props.stat.icon
			si.BackgroundTransparency = 1
			si.ScaleType = Enum.ScaleType.Fit
			si.Size = UDim2.fromOffset(32, 32)
			si.Position = UDim2.new(0, sx, 0, 62)
			si.ZIndex = z + 4
			si.Parent = header
			sx = sx + 32 + 8
		end
		statLabel = PanelChrome.read({
			name = "Stat",
			text = props.stat.text,
			size = S.TextSize.RowSub,
			color = S.Surface.ReadInk,
			align = Enum.TextXAlignment.Left,
			frameSize = UDim2.new(0.5, 0, 0, 36),
			position = UDim2.new(0, sx, 0, 60),
			zIndex = z + 4,
			parent = header,
		})
	end

	-- PRIMARY ACTION (spec §6.1): one semantic button left of the close. A shell
	-- uses either primaryAction or addHeaderTabs in the header this round, not both.
	local primaryBtn: TextButton? = nil
	if props.primaryAction then
		primaryBtn = PanelChrome.button({
			kind = props.primaryAction.kind or "positive",
			text = props.primaryAction.text,
			name = "PrimaryAction",
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -(C.HeaderPadding + C.CloseSize + 22), 0.5, 0),
			zIndex = z + 3,
			onActivated = props.primaryAction.onActivated,
			parent = header,
		})
		-- the title must not run under it
		titleLabel.Size = UDim2.new(1, -(hx + C.CloseSize + 40 + C.CtaSize.X + 22), 0, C.HeaderHeight)
	end

	local body: GuiObject
```

- [ ] **Step 3: API table + `addFooter`.** `script_read` from `local shellApi = {` to the end of `shell`. `multi_edit` with two edits:

Edit A — `old_string`:
```lua
	local shellApi = {
		root = root, header = header, body = body, close = close,
		list = list, titleLabel = titleLabel, z = z,
	}
```
`new_string`:
```lua
	local shellApi = {
		root = root, header = header, body = body, close = close,
		list = list, titleLabel = titleLabel, z = z,
		stat = statLabel, primaryAction = primaryBtn, footer = nil :: Frame?,
	}

	function shellApi.setStat(text: string)
		if statLabel then statLabel.Text = text end
	end
```

Edit B — `old_string`:
```lua
	root.Parent = props.parent
	return shellApi
end
```
`new_string`:
```lua
	--- FOOTER / UTILITY BAND (spec §6.1, handoff §2): a 72px band under the body.
	--- `left` = secondary / advanced actions, `right` = destructive actions -- the
	--- handoff's "destructive actions visually separated" rule made structural. The
	--- API accepts any kind in either group; the placement is the rule.
	function shellApi.addFooter(spec: {
		left: { { kind: string?, text: string, size: (UDim2 | string)?, onActivated: (() -> ())?, name: string? } }?,
		right: { { kind: string?, text: string, size: (UDim2 | string)?, onActivated: (() -> ())?, name: string? } }?,
	}): Frame
		local FOOTER_H = 72
		local existing = root:FindFirstChild("Footer")
		if existing then existing:Destroy() end
		local footer = Instance.new("Frame")
		footer.Name = "Footer"
		footer.BackgroundTransparency = 1
		footer.AnchorPoint = Vector2.new(0, 1)
		footer.Position = UDim2.fromScale(0, 1)
		footer.Size = UDim2.new(1, 0, 0, FOOTER_H)
		footer.ZIndex = z + 1
		footer.Parent = root
		-- body and watermark give the band its room
		body.Size = UDim2.new(1, 0, 1, -(C.HeaderHeight + C.RowGap + FOOTER_H + C.RowGap))
		local wm = root:FindFirstChild("Watermark")
		if wm and wm:IsA("GuiObject") then
			wm.Size = UDim2.new(1, -8, 1, -(C.HeaderHeight + C.RowGap + 8 + FOOTER_H + C.RowGap))
		end
		local function group(name: string, alignRight: boolean, specs)
			local holder = Instance.new("Frame")
			holder.Name = name
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.new(0.5, -S.Space.micro, 1, 0)
			holder.Position = if alignRight then UDim2.new(0.5, S.Space.micro, 0, 0) else UDim2.fromOffset(0, 0)
			holder.ZIndex = z + 1
			holder.Parent = footer
			local hl = Instance.new("UIListLayout")
			hl.FillDirection = Enum.FillDirection.Horizontal
			hl.HorizontalAlignment = if alignRight then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left
			hl.VerticalAlignment = Enum.VerticalAlignment.Center
			hl.Padding = UDim.new(0, S.Space.std)
			hl.SortOrder = Enum.SortOrder.LayoutOrder
			hl.Parent = holder
			for i, bs in ipairs(specs or {}) do
				PanelChrome.button({
					kind = bs.kind or "neutral",
					text = bs.text,
					size = bs.size or "small",
					name = bs.name,
					onActivated = bs.onActivated,
					layoutOrder = i,
					zIndex = z + 3,
					parent = holder,
				})
			end
			return holder
		end
		group("Left", false, spec.left)
		group("Right", true, spec.right)
		shellApi.footer = footer
		return footer
	end

	root.Parent = props.parent
	return shellApi
end
```

- [ ] **Step 4: Compile-gate + byte-scan + test.** `execute_luau` (Edit):

```lua
-- [TEST LOADER PREAMBLE from .superpowers/sdd/2026-09-18-ui-foundation/test-loader.lua goes here]
local live = RS.Modules.UIKit.PanelChrome
local f, e = loadstring(live.Source); assert(f, e)
for _, needle in ipairs({ "function shellApi.addFooter(", "function shellApi.setStat(", "PrimaryAction", "StatIcon" }) do
	assert(live.Source:find(needle, 1, true), "missing: " .. needle)
end
local S, PC = load(kit.SpecTheme), load(kit.PanelChrome)
local sg = Instance.new("ScreenGui"); sg.Name = "UIKitScratch"; sg.Parent = CoreGui
local C = S.Chrome
-- plain shell unchanged
local plain = PC.shell({ name = "Plain", title = "PLAIN", key = "settings", parent = sg })
assert(plain.body.Size.Y.Offset == -(C.HeaderHeight + C.RowGap), "plain body offset")
assert(plain.stat == nil and plain.primaryAction == nil and plain.footer == nil, "no slots by default")
-- slots
local hits = 0
local sh = PC.shell({ name = "Slots", title = "BAG", key = "bag", parent = sg,
	stat = { text = "16/16 equipped", icon = S.Art.bag },
	primaryAction = { kind = "gold", text = "EQUIP BEST", onActivated = function() hits += 1 end } })
assert(sh.stat and sh.stat.Text == "16/16 equipped" and sh.header:FindFirstChild("StatIcon"), "stat + icon")
sh.setStat("$1.2M/s"); assert(sh.stat.Text == "$1.2M/s", "setStat")
assert(sh.primaryAction and sh.primaryAction:GetAttribute("UIKind") == "gold", "primary action kind")
assert(sh.titleLabel.Size.X.Offset < plain.titleLabel.Size.X.Offset, "title shortened for the action")
local footer = sh.addFooter({ left = { { text = "HIDE PLOT" }, { text = "LOCK ALL", kind = "neutral" } }, right = { { text = "DELETE", kind = "destructive" } } })
assert(sh.footer == footer and footer.Parent == sh.root, "footer parented")
assert(sh.body.Size.Y.Offset == -(C.HeaderHeight + C.RowGap + 72 + C.RowGap), "body shrank for footer")
local nl, nr = 0, 0
for _, c in ipairs(footer.Left:GetChildren()) do if c:IsA("TextButton") then nl += 1 end end
for _, c in ipairs(footer.Right:GetChildren()) do if c:IsA("TextButton") then nr += 1 end end
assert(nl == 2 and nr == 1, "footer groups")
assert(footer.Right:FindFirstChildWhichIsA("TextButton"):GetAttribute("UIKind") == "destructive", "right kind")
assert(footer.Left:FindFirstChildWhichIsA("TextButton"):GetAttribute("UIKind") == "neutral", "left default neutral")
-- calling addFooter twice replaces
sh.addFooter({ left = { { text = "ONE" } } })
local count = 0; for _, c in ipairs(sh.root:GetChildren()) do if c.Name == "Footer" then count += 1 end end
assert(count == 1, "single footer")
sg.Parent = nil
return "shell slots OK"
```

Expected: `shell slots OK`.

- [ ] **Step 5: Live regression.** Play; open Bag, Progress, Worlds, Shop, Settings from the rail (each one click); each opens and closes; console clean. Stop Play.

- [ ] **Step 6: Mirror + commit.** → `PanelChrome.lua`; commit `feat(ui): shell stat, primary action and footer slots`.

---

### Task 6: `TabBar`, `SearchBar`, `SortButton`

**Files:**
- Create: `ReplicatedStorage.Modules.UIKit.TabBar`, `ReplicatedStorage.Modules.UIKit.SearchBar`, `ReplicatedStorage.Modules.UIKit.SortButton` (ModuleScripts)

**Interfaces:**
- Consumes: `S.Role/Space/Sound/Surface/Font/Outline/OutlineSoft`, `PanelChrome.segmented` (with `radius/outline/textSize`), `PanelChrome.shout`, `UI.badge`, `UI.touchMin`, `SoundKit.play`.
- Produces:
  - `TabBar.new({ tabs: {{ id, text, icon? }}, selected?, onChanged(id), orientation = "horizontal" | "vertical", parent?, zIndex?, height?, width?, name?, textSize? }) → { root, set(id), get(), setBadge(id, n), destroy() }`
  - `SearchBar.new({ placeholder?, width?, height?, onChanged(query), parent?, zIndex?, name?, debounce?, layoutOrder?, textSize? }) → { root, box, get(), set(text), clear(), focus(), destroy() }`
  - `SortButton.new({ modes: {{ id, label }}, selected?, onChanged(id), parent?, zIndex?, width?, height?, name?, layoutOrder? }) → { root, set(id), get(), destroy() }`

- [ ] **Step 1: Create `TabBar`.** `multi_edit` (`className = "ModuleScript"`, `old_string = ""`):

```lua
--!strict
-- TabBar -- body-level tabs (spec 2026-09-18 UI foundation §6.3). One component, two
-- layouts: horizontal chips (Quests: MAIN / DAILY / EVENT) or a vertical rail of
-- icon-over-label tiles (the Bag's categories). Paint follows the handoff's grammar:
-- active = S.Role.Neutral (blue = navigation, white shout) + selection ring, inactive
-- = S.Role.Disabled (grey, dark ink). Hover pops the GLYPH only: the tiles are layout
-- children, and a Size tween on one re-flows the whole strip (2026-08-16 lesson).
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local S = require(script.Parent.SpecTheme)
local PC = require(script.Parent.PanelChrome)
local UI = require(script.Parent.Builders)
local SoundKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("SoundKit"))

export type Tab = { id: string, text: string, icon: string? }
export type Props = {
	tabs: { Tab }, selected: string?, onChanged: (id: string) -> (), orientation: string?,
	parent: Instance?, zIndex: number?, height: number?, width: number?, name: string?, textSize: number?,
}
export type Api = {
	root: Frame, set: (id: string) -> (), get: () -> string,
	setBadge: (id: string, n: number) -> (), destroy: () -> (),
}

local TabBar = {}

type Entry = { id: string, btn: TextButton, grad: UIGradient, label: TextLabel, labelStroke: UIStroke, ring: Frame, glyph: GuiObject, glyphRest: UDim2 }

local function corner(o: GuiObject, r: number)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o
end

local function paint(e: Entry, active: boolean)
	local ramp = if active then S.Role.Neutral else S.Role.Disabled
	e.btn.BackgroundColor3 = ramp[1]
	e.grad.Color = ColorSequence.new(ramp[1], ramp[2])
	e.label.TextColor3 = if active then Color3.new(1, 1, 1) else S.Surface.ReadInk
	e.labelStroke.Color = if active then S.Outline else Color3.new(1, 1, 1)
	e.ring.Visible = active
end

function TabBar.new(props: Props): Api
	local vertical = props.orientation == "vertical"
	local z = props.zIndex or (PC.zBase + 3)
	local h = props.height or (if vertical then 74 else 64)
	local textSize = props.textSize or math.clamp(math.floor(h * 0.36), 12, 26)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

	local root = Instance.new("Frame")
	root.Name = props.name or "TabBar"
	root.BackgroundTransparency = 1
	root.ZIndex = z
	if vertical then
		root.Size = UDim2.new(0, props.width or 120, 0, 0)
		root.AutomaticSize = Enum.AutomaticSize.Y
	else
		root.Size = UDim2.new(0, 0, 0, h)
		root.AutomaticSize = Enum.AutomaticSize.X
	end
	local list = Instance.new("UIListLayout")
	list.FillDirection = if vertical then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, S.Space.small)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = root

	local entries: { [string]: Entry } = {}
	local current = props.selected or (props.tabs[1] and props.tabs[1].id) or ""

	local function select(id: string, fire: boolean)
		if not entries[id] then return end
		local changed = id ~= current
		current = id
		for eid, e in pairs(entries) do paint(e, eid == id) end
		if changed and fire then props.onChanged(id) end
	end

	for i, tab in ipairs(props.tabs) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab" .. tab.id
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.LayoutOrder = i
		btn.ZIndex = z + 1
		btn.BackgroundColor3 = S.Role.Disabled[1]
		if vertical then
			btn.Size = UDim2.new(1, 0, 0, h)
		else
			local bounds = TextService:GetTextSize(tab.text, textSize, S.Font.Shout, Vector2.new(4096, h))
			local w = math.max(props.width or 120, math.ceil(bounds.X) + (if tab.icon then 32 + 12 else 0) + 40)
			btn.Size = UDim2.fromOffset(w, h)
		end
		local radius = math.floor(h * 0.3)
		corner(btn, radius)
		local edge = Instance.new("UIStroke")
		edge.Thickness = if h < 48 then 3 else 4
		edge.Color = S.Outline
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.LineJoinMode = Enum.LineJoinMode.Round
		edge.Parent = btn
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(S.Role.Disabled[1], S.Role.Disabled[2])
		grad.Parent = btn
		btn:SetAttribute("NoPolish", true)

		-- selection ring OUTSIDE the tile (never clipped: neither btn nor root clips)
		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.BackgroundTransparency = 1
		ring.Position = UDim2.fromOffset(-4, -4)
		ring.Size = UDim2.new(1, 8, 1, 8)
		ring.ZIndex = z
		ring.Visible = false
		corner(ring, radius + 4)
		local rs = Instance.new("UIStroke")
		rs.Thickness = 3
		rs.Color = S.Role.Selection
		rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rs.Parent = ring
		ring.Parent = btn

		local glyph: GuiObject
		local label: TextLabel
		if vertical then
			local iconH = if tab.icon then math.floor(h * 0.5) else 0
			if tab.icon then
				local ic = Instance.new("ImageLabel")
				ic.Name = "Icon"
				ic.Image = tab.icon
				ic.BackgroundTransparency = 1
				ic.ScaleType = Enum.ScaleType.Fit
				ic.AnchorPoint = Vector2.new(0.5, 0)
				ic.Position = UDim2.new(0.5, 0, 0, 4)
				ic.Size = UDim2.fromOffset(iconH, iconH)
				ic.ZIndex = z + 2
				ic.Parent = btn
				glyph = ic
			end
			label = PC.shout({
				name = "Label", text = tab.text, size = textSize, zIndex = z + 2, parent = btn, scaled = true,
				frameSize = UDim2.new(1, -8, 0, h - iconH - 8), position = UDim2.new(0, 4, 0, iconH + 4),
			})
			if not tab.icon then glyph = label end
		else
			local lx = 0
			if tab.icon then
				local ic = Instance.new("ImageLabel")
				ic.Name = "Icon"
				ic.Image = tab.icon
				ic.BackgroundTransparency = 1
				ic.ScaleType = Enum.ScaleType.Fit
				ic.AnchorPoint = Vector2.new(0, 0.5)
				ic.Position = UDim2.new(0, 12, 0.5, 0)
				ic.Size = UDim2.fromOffset(32, 32)
				ic.ZIndex = z + 2
				ic.Parent = btn
				glyph = ic
				lx = 32 + 12
			end
			label = PC.shout({
				name = "Label", text = tab.text, size = textSize, zIndex = z + 2, parent = btn, scaled = true,
				frameSize = UDim2.new(1, -(lx + 16), 1, 0), position = UDim2.new(0, lx + 8, 0, 0),
			})
			if not tab.icon then glyph = label end
		end
		local labelStroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke

		local entry: Entry = { id = tab.id, btn = btn, grad = grad, label = label, labelStroke = labelStroke, ring = ring, glyph = glyph, glyphRest = glyph.Size }
		entries[tab.id] = entry

		-- glyph-only hover pop (+12%), never the tile
		local function pop(mult: number)
			local rest = entry.glyphRest
			local target = if mult == 1 then rest else UDim2.new(rest.X.Scale * mult, math.round(rest.X.Offset * mult), rest.Y.Scale * mult, math.round(rest.Y.Offset * mult))
			TweenService:Create(glyph, S.Tween.HoverIn, { Size = target }):Play()
		end
		btn.MouseEnter:Connect(function() if not touchOnly then pop(1.12) end end)
		btn.MouseLeave:Connect(function() pop(1) end)
		btn.Activated:Connect(function()
			pcall(SoundKit.play, S.Sound.Click, nil, { volume = 0.12 })
			select(tab.id, true)
		end)
		btn:SetAttribute("SfxWired", true)
		UI.touchMin(btn, 44)
		btn.Parent = root
	end

	select(current, false)

	local api: Api = {
		root = root,
		set = function(id: string) select(id, false) end,
		get = function() return current end,
		setBadge = function(id: string, n: number)
			local e = entries[id]
			if not e then return end
			local old = e.btn:FindFirstChild("Badge")
			if old then old:Destroy() end
			if n and n > 0 then
				local b = UI.badge(e.btn, n)
				b.Name = "Badge"
				b.AnchorPoint = Vector2.new(0.5, 0.5)
				b.Position = UDim2.new(1, -2, 0, 2)
				b.ZIndex = z + 4
			end
		end,
		destroy = function() root:Destroy() end,
	}
	root.Parent = props.parent
	return api
end

return TabBar
```

- [ ] **Step 2: Create `SearchBar`.** `multi_edit` (`className = "ModuleScript"`, `old_string = ""`):

```lua
--!strict
-- SearchBar -- the kit's search input (spec 2026-09-18 UI foundation §6.4). White
-- well, soft edge, magnifier glyph, clear-x when non-empty, debounced onChanged.
local S = require(script.Parent.SpecTheme)
local PC = require(script.Parent.PanelChrome)

export type Props = {
	placeholder: string?, width: number?, height: number?, onChanged: (query: string) -> (),
	parent: Instance?, zIndex: number?, name: string?, debounce: number?, layoutOrder: number?, textSize: number?,
}
export type Api = {
	root: Frame, box: TextBox, get: () -> string, set: (text: string) -> (),
	clear: () -> (), focus: () -> (), destroy: () -> (),
}

local SearchBar = {}

function SearchBar.new(props: Props): Api
	local h = props.height or 64
	local w = props.width or 320
	local z = props.zIndex or (PC.zBase + 2)
	local textSize = props.textSize or math.clamp(math.floor(h * 0.4), 14, 26)

	local root = Instance.new("Frame")
	root.Name = props.name or "SearchBar"
	root.Size = UDim2.fromOffset(w, h)
	root.BackgroundColor3 = S.Surface.RowTop
	root.BorderSizePixel = 0
	root.ZIndex = z
	if props.layoutOrder then root.LayoutOrder = props.layoutOrder end
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 999); c.Parent = root
	local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = S.OutlineSoft; st.Parent = root
	local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(S.Surface.RowTop, S.Surface.RowBottom); g.Parent = root

	-- magnifier from primitives (the Bag's own recipe): lens ring + tilted handle
	local magSize = math.floor(h * 0.42)
	local mag = Instance.new("Frame")
	mag.Name = "Mag"
	mag.BackgroundTransparency = 1
	mag.AnchorPoint = Vector2.new(0, 0.5)
	mag.Position = UDim2.new(0, math.floor(h * 0.32), 0.5, 0)
	mag.Size = UDim2.fromOffset(magSize, magSize)
	mag.ZIndex = z + 1
	mag.Parent = root
	local lens = Instance.new("Frame")
	lens.Name = "Lens"
	lens.Position = UDim2.fromOffset(1, 1)
	lens.Size = UDim2.new(0.7, 0, 0.7, 0)
	lens.BackgroundTransparency = 1
	lens.ZIndex = z + 1
	lens.Parent = mag
	local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0, 999); lc.Parent = lens
	local ls = Instance.new("UIStroke"); ls.Thickness = math.max(2, magSize * 0.14); ls.Color = S.Surface.ReadSub; ls.Parent = lens
	local handle = Instance.new("Frame")
	handle.Name = "Handle"
	handle.AnchorPoint = Vector2.new(1, 1)
	handle.Position = UDim2.new(1, 0, 1, 0)
	handle.Size = UDim2.new(0.45, 0, 0.18, 0)
	handle.Rotation = 45
	handle.BackgroundColor3 = S.Surface.ReadSub
	handle.BorderSizePixel = 0
	handle.ZIndex = z + 1
	handle.Parent = mag
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 999); hc.Parent = handle

	local clearW = math.floor(h * 0.6)
	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.BackgroundTransparency = 1
	box.Position = UDim2.new(0, math.floor(h * 0.32) + magSize + 10, 0, 0)
	box.Size = UDim2.new(1, -(math.floor(h * 0.32) + magSize + 10 + clearW + 12), 1, 0)
	box.Text = ""
	box.PlaceholderText = props.placeholder or "SEARCH..."
	box.PlaceholderColor3 = S.Surface.ReadSub
	box.TextColor3 = S.Surface.ReadInk
	box.Font = S.Font.Read
	box.TextSize = textSize
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.ZIndex = z + 1
	box:SetAttribute("NoPolish", true)
	box.Parent = root

	local clearBtn = Instance.new("TextButton")
	clearBtn.Name = "Clear"
	clearBtn.Text = ""
	clearBtn.AutoButtonColor = false
	clearBtn.BorderSizePixel = 0
	clearBtn.AnchorPoint = Vector2.new(1, 0.5)
	clearBtn.Position = UDim2.new(1, -math.floor(h * 0.2), 0.5, 0)
	clearBtn.Size = UDim2.fromOffset(clearW, clearW)
	clearBtn.BackgroundColor3 = S.Role.Disabled[1]
	clearBtn.ZIndex = z + 1
	clearBtn.Visible = false
	clearBtn:SetAttribute("NoPolish", true)
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 999); cc.Parent = clearBtn
	PC.shout({ name = "Label", text = "\u{00D7}", size = math.floor(clearW * 0.8), color = S.Surface.ReadInk, strokeColor = Color3.new(1, 1, 1), zIndex = z + 2, parent = clearBtn })
	clearBtn.Parent = root

	-- debounce: a query fires props.debounce (80ms) after the last keystroke; an
	-- EMPTY query (clear) fires at once. Generation-guarded so a stale timer never
	-- fires a superseded value.
	local gen = 0
	local function emit(immediate: boolean)
		gen += 1
		local my = gen
		local function fire()
			if my == gen and root.Parent then props.onChanged(box.Text) end
		end
		if immediate then fire() else task.delay(props.debounce or 0.08, fire) end
	end
	box:GetPropertyChangedSignal("Text"):Connect(function()
		clearBtn.Visible = box.Text ~= ""
		emit(box.Text == "")
	end)
	clearBtn.Activated:Connect(function()
		box.Text = ""
		box:CaptureFocus()
	end)

	local api: Api = {
		root = root,
		box = box,
		get = function() return box.Text end,
		set = function(text: string) box.Text = text end,
		clear = function() box.Text = "" end,
		focus = function() box:CaptureFocus() end,
		destroy = function() root:Destroy() end,
	}
	root.Parent = props.parent
	return api
end

return SearchBar
```

- [ ] **Step 3: Create `SortButton`.** `multi_edit` (`className = "ModuleScript"`, `old_string = ""`):

```lua
--!strict
-- SortButton -- the handoff's Rarity / Newest / A-Z control (spec §6.5): a segmented
-- group of neutral chips, active = blue, others = grey. Thin wrapper over
-- PanelChrome.segmented so it shares the pill geometry and the grammar sweep.
local PC = require(script.Parent.PanelChrome)

export type Mode = { id: string, label: string }
export type Props = {
	modes: { Mode }, selected: string?, onChanged: (id: string) -> (),
	parent: Instance?, zIndex: number?, width: number?, height: number?, name: string?, layoutOrder: number?,
}
export type Api = { root: Frame, set: (id: string) -> (), get: () -> string, destroy: () -> () }

local SortButton = {}

function SortButton.new(props: Props): Api
	local h = props.height or 64
	local labels, index = {}, {}
	for i, m in ipairs(props.modes) do
		labels[i] = m.label
		index[m.id] = i
	end
	local seg = PC.segmented({
		options = labels,
		selected = index[props.selected or ""] or 1,
		size = UDim2.fromOffset(props.width or (#labels * 120 + (#labels - 1) * 12), h),
		parent = props.parent,
		zIndex = props.zIndex,
		radius = math.floor(h * 0.5),
		outline = if h < 48 then 3 else nil,
		textSize = if h < 48 then math.max(12, math.floor(h * 0.45)) else nil,
		onChanged = function(i: number)
			props.onChanged(props.modes[i].id)
		end,
	})
	seg.root.Name = props.name or "SortButton"
	if props.layoutOrder then seg.root.LayoutOrder = props.layoutOrder end
	return {
		root = seg.root,
		set = function(id: string)
			local i = index[id]
			if i then seg.set(i) end
		end,
		get = function() return props.modes[seg.get()].id end,
		destroy = function() seg.root:Destroy() end,
	}
end

return SortButton
```

- [ ] **Step 4: Compile-gate + test all three.** `execute_luau` (Edit):

```lua
-- [TEST LOADER PREAMBLE from .superpowers/sdd/2026-09-18-ui-foundation/test-loader.lua goes here]
for _, n in ipairs({ "TabBar", "SearchBar", "SortButton" }) do local f, e = loadstring(RS.Modules.UIKit[n].Source); assert(f, n .. ": " .. tostring(e)) end
local S = load(kit.SpecTheme)
local TabBar, SearchBar, SortButton = load(kit.TabBar), load(kit.SearchBar), load(kit.SortButton)
local sg = Instance.new("ScreenGui"); sg.Name = "UIKitScratch"; sg.Parent = CoreGui
-- TabBar horizontal
local got = {}
local hz = TabBar.new({ tabs = { { id = "main", text = "MAIN" }, { id = "daily", text = "DAILY" }, { id = "event", text = "EVENT", icon = S.Art.goals } }, selected = "daily", onChanged = function(id) table.insert(got, id) end, parent = sg })
assert(hz.get() == "daily", "initial selected")
assert(hz.root.Tabdaily.BackgroundColor3 == S.Role.Neutral[1] and hz.root.Tabmain.BackgroundColor3 == S.Role.Disabled[1], "hz paint")
assert(hz.root.Tabdaily.Ring.Visible == true and hz.root.Tabmain.Ring.Visible == false, "ring")
assert(hz.root.Tabevent:FindFirstChild("Icon"), "hz icon")
assert(hz.root:FindFirstChildOfClass("UIListLayout").FillDirection == Enum.FillDirection.Horizontal, "hz layout")
hz.set("main"); assert(hz.get() == "main" and #got == 0, "set() is silent")
hz.setBadge("event", 3); assert(hz.root.Tabevent:FindFirstChild("Badge"), "badge on")
hz.setBadge("event", 0); assert(not hz.root.Tabevent:FindFirstChild("Badge"), "badge off")
-- TabBar vertical
local vt = TabBar.new({ tabs = { { id = "brainrots", text = "BRAINROTS", icon = S.Art.bag }, { id = "pets", text = "PETS", icon = S.Art.bag } }, orientation = "vertical", width = 110, parent = sg, onChanged = function() end })
assert(vt.root:FindFirstChildOfClass("UIListLayout").FillDirection == Enum.FillDirection.Vertical, "vt layout")
assert(vt.root.Tabbrainrots.Size.Y.Offset == 74 and vt.root.Tabbrainrots.Icon.Position.Y.Offset == 4, "vt tile")
-- SearchBar
local queries = {}
local sb = SearchBar.new({ placeholder = "SEARCH...", width = 260, height = 36, parent = sg, onChanged = function(q) table.insert(queries, q) end })
assert(sb.root.Size.Y.Offset == 36 and sb.box.PlaceholderText == "SEARCH...", "search geometry")
sb.set("tung"); task.wait(0.2)
assert(queries[#queries] == "tung" and sb.root.Clear.Visible == true, "debounced query + clear visible")
sb.clear(); task.wait(0.05)
assert(queries[#queries] == "" and sb.root.Clear.Visible == false, "clear fires at once")
-- SortButton
local picked = {}
local sort = SortButton.new({ modes = { { id = "rarity", label = "RARITY" }, { id = "newest", label = "NEWEST" }, { id = "az", label = "A-Z" } }, selected = "rarity", height = 36, width = 3 * 96 + 2 * 12, parent = sg, onChanged = function(id) table.insert(picked, id) end })
assert(sort.get() == "rarity", "sort initial")
sort.set("az"); assert(sort.get() == "az" and #picked == 0, "sort set silent")
local btns = {}; for _, c in ipairs(sort.root:GetChildren()) do if c:IsA("TextButton") then btns[c.LayoutOrder] = c end end
assert(btns[3].BackgroundColor3 == S.Role.Neutral[1] and btns[1].BackgroundColor3 == S.Role.Disabled[1], "sort paint")
assert(btns[1]:FindFirstChildOfClass("UIStroke").Thickness == 3, "sort thin outline at 36px")
sg.Parent = nil
return "TabBar/SearchBar/SortButton OK"
```

Expected: `TabBar/SearchBar/SortButton OK`.

- [ ] **Step 5: Mirror + commit.** Three new mirror files under `game-src/place-full/ReplicatedStorage/Modules/UIKit/` (`TabBar.lua`, `SearchBar.lua`, `SortButton.lua`); commit `feat(ui): TabBar (both orientations), SearchBar, SortButton`.

---

### Task 7: `Modal`, `Toast`, and `ToastClient` becomes wiring only

**Files:**
- Create: `ReplicatedStorage.Modules.UIKit.Modal`, `ReplicatedStorage.Modules.UIKit.Toast`
- Modify: `StarterPlayer.StarterPlayerScripts.ToastClient` (requires ≈ line 26; lines ≈ 49–99 stack construction; `push` ≈ 101–166)

**Interfaces:**
- Consumes: `PanelChrome.plate/shout/read/button/zBase`, `S.Role/TitleInk/Surface/TextSize/Outline`, `FxDriver`.
- Produces: `Modal.confirm(props: { title, body, loss?, confirmText, confirmKind?, cancelText?, cancelable?, onConfirm, onCancel?, parent?, titleInk? }) → { close(), root }`, `Modal.isOpen()`, `Modal.closeCurrent()`, `Modal.setHost(gui?)`; `Toast.show({ text, tone = "info" | "success" | "error" | "reward", icon?, hold? })`, `Toast.clear()`, `Toast.count()`, `Toast.setHost(gui?)`. `ToastClient.push(success, message)` becomes a one-line adapter.

- [ ] **Step 1: Create `Modal`.** `multi_edit` (`className = "ModuleScript"`, `old_string = ""`):

```lua
--!strict
-- Modal -- the kit's confirmation dialog (spec 2026-09-18 UI foundation §6.6,
-- handoff §19). Dangerous actions ONLY; deliberately no generic alert. Singleton:
-- opening a second confirm cancels the first. Dark translucent scrim that swallows
-- every input (nothing behind is clickable); scrim click, ESC and gamepad B cancel
-- only when `cancelable`. World blur is NOT part of the modal -- a caller that wants
-- it uses GameHUDClient's HUDPanelBlur machinery.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local S = require(script.Parent.SpecTheme)
local PC = require(script.Parent.PanelChrome)

export type Props = {
	title: string, body: string, loss: string?, confirmText: string, confirmKind: string?,
	cancelText: string?, cancelable: boolean?, onConfirm: () -> (), onCancel: (() -> ())?,
	parent: Instance?, titleInk: Color3?,
}
export type Handle = { close: () -> (), root: TextButton }

local Modal = {}

local DISPLAY_ORDER = 90
local host: ScreenGui? = nil
local current: { root: TextButton, cancel: () -> () }? = nil

--- Tests (Edit mode has no PlayerGui) hand the modal a ScreenGui to live in.
function Modal.setHost(gui: ScreenGui?)
	host = gui
end

local function ensureHost(): ScreenGui
	if host and host.Parent then return host :: ScreenGui end
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	local sg = Instance.new("ScreenGui")
	sg.Name = "UIKitModal"
	sg.DisplayOrder = DISPLAY_ORDER
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = pg
	host = sg
	return sg
end

function Modal.isOpen(): boolean
	return current ~= nil
end

function Modal.closeCurrent()
	if current then current.cancel() end
end

function Modal.confirm(props: Props): Handle
	if current then current.cancel() end -- singleton
	local parent: Instance = props.parent or ensureHost()
	local z = PC.zBase + 60
	local cancelable = props.cancelable ~= false
	local conns: { RBXScriptConnection } = {}
	local closed = false

	local scrim = Instance.new("TextButton")
	scrim.Name = "ModalScrim"
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 0.45
	scrim.BorderSizePixel = 0
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Active = true -- swallows every input: nothing behind the modal is clickable
	scrim.ZIndex = z
	scrim:SetAttribute("NoPolish", true)
	scrim.Parent = parent

	local dialog = PC.plate({
		name = "Dialog", size = UDim2.fromOffset(560, 380),
		position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5),
		colors = { S.Surface.Shell, S.Surface.Body }, radius = 32, outline = 7,
		zIndex = z + 1, parent = scrim, gloss = false,
	})
	dialog.Active = true -- a click on the dialog itself must not reach the scrim

	PC.shout({
		name = "Title", text = props.title, size = 44,
		color = props.titleInk or S.TitleInk.default, strokeColor = Color3.new(1, 1, 1),
		frameSize = UDim2.new(1, -48, 0, 70), position = UDim2.fromOffset(24, 18),
		zIndex = z + 3, parent = dialog,
	})
	local body = PC.read({
		name = "Body", text = props.body, size = S.TextSize.RowSub, color = S.Surface.ReadInk,
		frameSize = UDim2.new(1, -64, 0, 120), position = UDim2.fromOffset(32, 96),
		zIndex = z + 3, parent = dialog, align = Enum.TextXAlignment.Center,
	})
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	if props.loss and props.loss ~= "" then
		local loss = PC.read({
			name = "Loss", text = props.loss, size = S.TextSize.RowSub, color = S.Role.Destructive[2],
			frameSize = UDim2.new(1, -64, 0, 44), position = UDim2.fromOffset(32, 222),
			zIndex = z + 3, parent = dialog, align = Enum.TextXAlignment.Center,
		})
		loss.TextWrapped = true
	end

	local function finish(fn: (() -> ())?)
		if closed then return end
		closed = true
		for _, c in ipairs(conns) do c:Disconnect() end
		if current and current.root == scrim then current = nil end
		if UserInputService.GamepadEnabled then GuiService.SelectedObject = nil end
		scrim:Destroy()
		if fn then
			local ok, err = pcall(fn)
			if not ok then
				warn(("[UIKit] Modal callback failed: %s\n%s"):format(tostring(err), debug.traceback()))
			end
		end
	end
	local function cancel() finish(props.onCancel) end
	local function confirm() finish(props.onConfirm) end

	local cancelBtn = PC.button({
		kind = "secondary", text = props.cancelText or "CANCEL", size = UDim2.fromOffset(220, 72),
		anchor = Vector2.new(0, 1), position = UDim2.new(0, 32, 1, -28), zIndex = z + 3,
		parent = dialog, onActivated = cancel, name = "Cancel",
	})
	PC.button({
		kind = props.confirmKind or "destructive", text = props.confirmText, size = UDim2.fromOffset(220, 72),
		anchor = Vector2.new(1, 1), position = UDim2.new(1, -32, 1, -28), zIndex = z + 3,
		parent = dialog, onActivated = confirm, name = "Confirm",
	})

	table.insert(conns, scrim.Activated:Connect(function()
		if cancelable then cancel() end
	end))
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if cancelable then cancel() end
		end
	end))
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = cancelBtn
	end

	current = { root = scrim, cancel = cancel }
	return { close = cancel, root = scrim }
end

return Modal
```

- [ ] **Step 2: Create `Toast`.** `multi_edit` (`className = "ModuleScript"`, `old_string = ""`):

```lua
--!strict
-- Toast -- the ONE notification stack (spec 2026-09-18 UI foundation §6.7). Every
-- toast in the game renders here; ToastClient is remote wiring only. Geometry is
-- ToastClient's measured recipe (2026-08-17): the stack's bottom pinned at
-- (0.5, 0, 0.78, -140) clears the throw cluster at every aspect, lines grow upward,
-- width capped at 640 so phones wrap. Plateless shout text with a dark contextual
-- stroke (PS99 field study delta 9); tone = ink colour per the handoff grammar.
-- Fades are hand-lerped on FxDriver (TweenService cannot animate transparency here).
local Players = game:GetService("Players")
local S = require(script.Parent.SpecTheme)
local FxDriver = require(script.Parent.FxDriver)

export type Props = { text: string, tone: string?, icon: string?, hold: number? }

local MAX_LINES = 3
local HOLD = 3.2
local FADE = 0.3
local FADE_IN = 0.12
local LINE_W, LINE_H = 640, 34
local TONE: { [string]: Color3 } = {
	info = Color3.new(1, 1, 1),
	success = S.Role.Positive[1],
	error = S.Role.Destructive[1],
	reward = S.Role.Gold[1],
}

local Toast = {}

type Entry = { line: TextLabel, stroke: UIStroke, dismissed: boolean, fx: number? }

local host: ScreenGui? = nil
local stack: Frame? = nil
local live: { Entry } = {}
local seq = 0

function Toast.setHost(gui: ScreenGui?)
	host = gui
	stack = nil
end

local function ensureStack(): Frame
	if stack and stack.Parent then return stack :: Frame end
	if not (host and host.Parent) then
		local player = Players.LocalPlayer
		local pg = player and player:FindFirstChildOfClass("PlayerGui")
		local sg = Instance.new("ScreenGui")
		sg.Name = "UIKitToast"
		sg.DisplayOrder = 60
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.Parent = pg
		host = sg
	end
	local st = Instance.new("Frame")
	st.Name = "Stack"
	st.AnchorPoint = Vector2.new(0.5, 1)
	st.Position = UDim2.new(0.5, 0, 0.78, -140)
	st.Size = UDim2.new(1, -32, 0, 0)
	st.BackgroundTransparency = 1
	st.AutomaticSize = Enum.AutomaticSize.Y
	st.Parent = host
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(LINE_W, math.huge)
	cap.Parent = st
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = st
	stack = st
	return st
end

local function lerpAlpha(entry: Entry, from: number, to: number, secs: number, onDone: (() -> ())?)
	if entry.fx then FxDriver.unregister(entry.fx) entry.fx = nil end
	local t0: number? = nil
	local id: number? = nil
	id = FxDriver.register(entry.line, function(t)
		t0 = t0 or t
		local a = math.clamp((t - t0) / secs, 0, 1)
		local v = from + (to - from) * a
		entry.line.TextTransparency = v
		entry.stroke.Transparency = v
		if a >= 1 then
			FxDriver.unregister(id)
			if entry.fx == id then entry.fx = nil end
			if onDone then onDone() end
		end
	end)
	entry.fx = id
	-- a hidden line is skipped by the driver; settle it anyway so nothing lingers
	task.delay(secs + 0.1, function()
		if entry.fx == id then
			FxDriver.unregister(id)
			entry.fx = nil
			entry.line.TextTransparency = to
			entry.stroke.Transparency = to
			if onDone then onDone() end
		end
	end)
end

local function dismiss(entry: Entry, instant: boolean?)
	if entry.dismissed then return end
	entry.dismissed = true
	for i, e in ipairs(live) do
		if e == entry then table.remove(live, i) break end
	end
	if instant or not entry.line.Parent then
		if entry.fx then FxDriver.unregister(entry.fx) entry.fx = nil end
		entry.line:Destroy()
		return
	end
	lerpAlpha(entry, entry.line.TextTransparency, 1, FADE, function()
		entry.line:Destroy()
	end)
end

function Toast.show(props: Props)
	if type(props) ~= "table" or type(props.text) ~= "string" then
		warn(("[UIKit] Toast.show: bad props (%s)"):format(typeof(props)))
		return
	end
	local st = ensureStack()
	while #live >= MAX_LINES do
		dismiss(live[1], true) -- REPLACE, not scroll (PS99 f028/f029)
	end
	seq += 1
	local line = Instance.new("TextLabel")
	line.Name = "Toast" .. seq
	line.Size = UDim2.new(1, 0, 0, LINE_H)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.BackgroundTransparency = 1
	line.BorderSizePixel = 0
	line.Font = S.Font.Shout
	line.TextSize = 26
	line.TextColor3 = TONE[props.tone or "info"] or TONE.info
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.TextTruncate = Enum.TextTruncate.None -- never truncate a message (owner, 2026-08-24)
	line.TextWrapped = true
	line.Text = props.text
	line.LayoutOrder = seq
	line:SetAttribute("NoPolish", true)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = S.Outline
	stroke.Thickness = 2.8
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = line
	line.TextTransparency = 1
	stroke.Transparency = 1
	line.Parent = st
	if props.icon and props.icon ~= "" then
		local ic = Instance.new("ImageLabel")
		ic.Name = "Icon"
		ic.Image = props.icon
		ic.BackgroundTransparency = 1
		ic.ScaleType = Enum.ScaleType.Fit
		ic.AnchorPoint = Vector2.new(1, 0.5)
		ic.Size = UDim2.fromOffset(28, 28)
		ic.Position = UDim2.new(0.5, -8, 0.5, 0)
		ic.Parent = line
		task.defer(function()
			if line.Parent then
				ic.Position = UDim2.new(0.5, -math.ceil(line.TextBounds.X * 0.5) - 8, 0.5, 0)
			end
		end)
	end
	local entry: Entry = { line = line, stroke = stroke, dismissed = false, fx = nil }
	table.insert(live, entry)
	lerpAlpha(entry, 1, 0, FADE_IN)
	task.delay(props.hold or HOLD, function() dismiss(entry) end)
end

function Toast.clear()
	for i = #live, 1, -1 do
		dismiss(live[i], true)
	end
end

function Toast.count(): number
	return #live
end

return Toast
```

- [ ] **Step 3: Compile-gate + test both (Edit mode, scratch host).** `execute_luau` (Edit):

```lua
-- [TEST LOADER PREAMBLE from .superpowers/sdd/2026-09-18-ui-foundation/test-loader.lua goes here]
for _, n in ipairs({ "Modal", "Toast" }) do local f, e = loadstring(RS.Modules.UIKit[n].Source); assert(f, n .. ": " .. tostring(e)) end
local S, Modal, Toast, Fx = load(kit.SpecTheme), load(kit.Modal), load(kit.Toast), load(kit.FxDriver)
local sg = Instance.new("ScreenGui"); sg.Name = "UIKitScratch"; sg.Parent = CoreGui
-- Modal: confirm path
local confirmed, cancelled = 0, 0
local h1 = Modal.confirm({ title = "DELETE 3 BRAINROTS?", body = "They go back into the wild.", loss = "You will lose $12.4K/s of income.",
	confirmText = "DELETE", onConfirm = function() confirmed += 1 end, onCancel = function() cancelled += 1 end, parent = sg })
assert(Modal.isOpen() and h1.root.Parent == sg and math.abs(h1.root.BackgroundTransparency - 0.45) < 1e-3 and h1.root.Active == true, "modal open, dark scrim, active")
local dlg = h1.root.Dialog
assert(dlg.Active == true and dlg:FindFirstChild("Loss") and dlg.Cancel:GetAttribute("UIKind") == "secondary" and dlg.Confirm:GetAttribute("UIKind") == "destructive", "dialog anatomy")
assert(dlg.Confirm.Position.X.Scale == 1 and dlg.Cancel.Position.X.Scale == 0, "destructive right, cancel left")
-- singleton: a second confirm cancels the first
local h2 = Modal.confirm({ title = "REBIRTH?", body = "b", confirmText = "REBIRTH", confirmKind = "positive", onConfirm = function() end, parent = sg })
assert(cancelled == 1 and h1.root.Parent == nil and Modal.isOpen(), "singleton replaced the first (its onCancel ran)")
assert(h2.root.Dialog.Confirm:GetAttribute("UIKind") == "positive", "confirmKind positive")
h2.close(); assert(not Modal.isOpen() and h2.root.Parent == nil, "close() tears down")
-- cancelable = false still closes through the handle
local h3 = Modal.confirm({ title = "WAIT", body = "b", confirmText = "OK", confirmKind = "positive", cancelable = false, onConfirm = function() end, parent = sg })
Modal.closeCurrent(); assert(not Modal.isOpen(), "closeCurrent")
-- Toast
Toast.setHost(sg)
for i = 1, 4 do Toast.show({ text = "LINE " .. i, tone = ({ "info", "success", "error", "reward" })[i], hold = 0.5 }) end
assert(Toast.count() == 3, "cap 3 (oldest replaced)")
local st = sg:FindFirstChild("Stack"); assert(st, "stack in host")
local lines = {}; for _, c in ipairs(st:GetChildren()) do if c:IsA("TextLabel") then table.insert(lines, c) end end
assert(#lines == 3, "3 lines")
table.sort(lines, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
assert(lines[1].Text == "LINE 2" and lines[3].TextColor3 == S.Role.Gold[1] and lines[2].TextColor3 == S.Role.Destructive[1], "tones + order")
assert(st.Position == UDim2.new(0.5, 0, 0.78, -140), "measured anchor kept")
task.wait(0.25); assert(lines[1].TextTransparency < 0.05, "faded in")
task.wait(1.0)
assert(Toast.count() == 0 and #st:GetChildren() == 2 and not Fx.isRunning(), "held, faded, destroyed; driver stood down")
Toast.show({ text = "X", hold = 5 }); Toast.clear(); assert(Toast.count() == 0, "clear")
sg.Parent = nil
return ("Modal/Toast OK (confirmed=%d cancelled=%d)"):format(confirmed, cancelled)
```

Expected: `Modal/Toast OK (confirmed=0 cancelled=1)` (the confirm button is never clicked in Edit mode; the Gallery exercises real clicks).

- [ ] **Step 4: Back up + rewire `ToastClient`.** Clone as `ToastClient_pre7`. `script_read` lines 19–30, 45–100 and 100–170 (numbers may differ — anchor on text). `multi_edit` with three edits:

Edit A — `old_string`:
```lua
local remotes = ReplicatedStorage:WaitForChild("Remotes")
```
`new_string`:
```lua
local remotes = ReplicatedStorage:WaitForChild("Remotes")
-- 2026-09-18 UI foundation (spec §6.7): the ONE toast renderer is UIKit.Toast.
-- This script is remote wiring only from here on.
local Toast = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIKit"):WaitForChild("Toast"))
```

Edit B — remove the stack. `old_string` is the exact live text from the comment line `-- lower-mid screen, grows UPWARD. The 0.78 scale anchor alone landed the lines ON the` down to and including the `end` that closes `local function dismiss(entry, instant)` (at plan time lines 49–99: the comment block, `local stack = Instance.new("Frame")` … `stack.Parent = screen`, the `widthCap` block, the `layout` block, `local live = {}`, `local seq = 0`, the `dismiss` function). Paste it from the live read. `new_string`:
```lua
-- 2026-09-18 UI foundation: the text stack lives in ReplicatedStorage.Modules.UIKit.Toast
-- (spec §6.7) -- ONE renderer for the whole game, never two stacks. `screen` stays for
-- the dormant item-tile builder below; `seq` is its tile counter.
local seq = 0
```

Edit C — `push` becomes the adapter. `old_string` is the exact live text from `local function push(success, message)` down to and including the `end` after `task.delay(HOLD, function() dismiss(entry) end)` (at plan time lines 101–166). `new_string`:
```lua
local function push(success, message)
	-- adapter only: success = green, failure = red (handoff §4), never truncated,
	-- wrapped, capped at 3 messages -- all inside UIKit.Toast
	Toast.show({ text = message, tone = success and "success" or "error" })
end
```

- [ ] **Step 5: Compile-gate + byte-scan + static checks.** `execute_luau` (Edit):

```lua
local s = game:GetService("StarterPlayer").StarterPlayerScripts.ToastClient
local f, e = loadstring(s.Source); assert(f, e)
assert(not s.Source:find('stack.Name = "Stack"', 1, true), "old stack still present")
assert(not s.Source:find("local function dismiss", 1, true), "old dismiss still present")
assert(s.Source:find("Toast.show({ text = message", 1, true), "adapter missing")
assert(s.Source:find("local seq = 0", 1, true) and s.Source:find("itemRow.Parent = screen", 1, true), "dormant item toast intact")
return "ToastClient compiles, single renderer"
```

- [ ] **Step 6: Live check.** Play. `execute_luau` (Client):
```lua
local RS = game:GetService("ReplicatedStorage")
local Toast = require(RS.Modules.UIKit.Toast)
Toast.show({ text = "UIKit toast test (success)", tone = "success" })
Toast.show({ text = "UIKit toast test (error)", tone = "error" })
task.wait(0.3)
local pg = game.Players.LocalPlayer.PlayerGui
local uk = pg:FindFirstChild("UIKitToast")
local tg = pg:FindFirstChild("ToastGui")
return ("UIKitToast lines=%d | ToastGui has Stack=%s"):format(uk and #uk.Stack:GetChildren() - 2 or -1, tostring(tg and tg:FindFirstChild("Stack") ~= nil))
```
Expected: `UIKitToast lines=2 | ToastGui has Stack=false`. Foreground Studio and `screen_capture` within 3 s of the exec: two shout lines, green then red, lower-mid screen above the throw cluster. Console clean. Stop Play.

- [ ] **Step 7: Mirror + commit.** New mirror files `Modal.lua`, `Toast.lua`; overwrite `ToastClient.client.lua`; commit `feat(ui): Modal.confirm and the single Toast stack; ToastClient is wiring only`.

---

### Task 8: `BrainrotThumb` — projected-corner framing (`framingBox`), `fill`/`aspect` in `addMaster`

**Files:**
- Modify: `ReplicatedStorage.Modules.BrainrotThumb` — `M.framing` (≈ lines 219–226) and the framing/aim block inside `addMaster` (≈ 288–303).

**Interfaces:**
- Produces: `M.framingSphere(model, fov) → (centre: Vector3, dist: number)` (the old behaviour, unchanged); `M.framingBox(model, fov, opts: { dir: Vector3, aspect: number, fill: number }) → (centre, dist)`; `M.framing(model, fov, opts?)` dispatches: `opts.fill` (and not `opts.spin`) → box, otherwise sphere — so every existing two-argument caller (Index, Sell, Egg shop, CatchReveal orbit) is byte-for-byte unchanged in behaviour. `addMaster`/`add`/`addPet` accept `opts.fill` and `opts.aspect`; when `fill` is given the camera is placed by the box fit against the viewport's real aspect.

- [ ] **Step 1: Back up** `BrainrotThumb` as `BrainrotThumb_pre8`.

- [ ] **Step 2: Replace `M.framing`.** `script_read` 200–227. `multi_edit` — `old_string`:
```lua
local MARGIN = 1.10
function M.framing(model, fov)
	fov = fov or 30
	local cf, ext = model:GetBoundingBox()
	local radius = ext.Magnitude * 0.5
	local dist = radius / math.sin(math.rad(fov * 0.5)) * MARGIN
	return cf.Position, dist
end
```
`new_string`:
```lua
local MARGIN = 1.10
function M.framingSphere(model, fov)
	fov = fov or 30
	local cf, ext = model:GetBoundingBox()
	local radius = ext.Magnitude * 0.5
	local dist = radius / math.sin(math.rad(fov * 0.5)) * MARGIN
	return cf.Position, dist
end

-- PROJECTED-CORNER FRAMING (2026-09-18 UI foundation, spec §8.1). The sphere fit above
-- is right for a SPINNING model, but a card looks from ONE fixed direction, and there
-- the sphere over-reserves: a tall narwhal, a wide hammerhead and a two-character group
-- all get different perceived sizes because only their space diagonals match. Framing
-- the eight bounding-box corners against the viewport's own aspect gives every
-- silhouette the same perceived fill. For each corner the distance that keeps it inside
-- `fill` of the frame on its axis is closed-form,
--     d = |lateral| / (fill * tan(halfAngle)) + along
-- (along = how far the corner sits toward the camera from the look-at), the camera
-- takes the max over all corners and both axes, then ONE re-centring pass shifts the
-- look-at so the projected extents are centred (optical centre, not box centre). The
-- Gallery's framing set prints the residual per model.
-- opts = { dir = world view direction (camera sits at centre + dir * dist),
--          aspect = viewport width / height, fill = 0..1 (0.70 for cards) }
local MIN_FILL, MAX_FILL = 0.3, 0.95
function M.framingBox(model, fov, opts)
	fov = fov or 30
	opts = opts or {}
	local cf, ext = model:GetBoundingBox()
	local dir = opts.dir or DEFAULT_DIR
	local aspect = math.max(0.2, opts.aspect or 1)
	local fill = math.clamp(opts.fill or 0.70, MIN_FILL, MAX_FILL)
	local look = -dir
	local right = look:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then right = Vector3.xAxis else right = right.Unit end
	local up = right:Cross(look).Unit
	local tanV = math.tan(math.rad(fov * 0.5))
	local tanH = tanV * aspect
	local hx, hy, hz = ext.X * 0.5, ext.Y * 0.5, ext.Z * 0.5
	local corners = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				table.insert(corners, cf:PointToWorldSpace(Vector3.new(sx * hx, sy * hy, sz * hz)))
			end
		end
	end
	local centre = cf.Position
	local function solve(c0)
		local dist = 0
		for _, q in ipairs(corners) do
			local w = q - c0
			local along = w:Dot(dir)
			local x, y = w:Dot(right), w:Dot(up)
			dist = math.max(dist, math.abs(x) / (fill * tanH) + along, math.abs(y) / (fill * tanV) + along)
		end
		return math.max(dist, ext.Magnitude * 0.25)
	end
	local dist = solve(centre)
	-- one re-centring pass on the projected extents
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, q in ipairs(corners) do
		local w = q - centre
		local depth = dist - w:Dot(dir)
		if depth > 1e-3 then
			local px, py = w:Dot(right) / depth, w:Dot(up) / depth
			minX, maxX = math.min(minX, px), math.max(maxX, px)
			minY, maxY = math.min(minY, py), math.max(maxY, py)
		end
	end
	if minX < maxX and minY < maxY then
		local midX, midY = (minX + maxX) * 0.5, (minY + maxY) * 0.5
		centre = centre + right * (midX * dist) + up * (midY * dist)
		dist = solve(centre)
	end
	return centre, dist
end

-- Dispatcher. `opts.fill` selects the box fit (cards); no opts (every pre-2026-09-18
-- caller) or `opts.spin` (an orbiting camera must fit every angle) keeps the sphere.
function M.framing(model, fov, opts)
	if type(opts) == "table" and opts.fill and not opts.spin then
		return M.framingBox(model, fov, opts)
	end
	return M.framingSphere(model, fov)
end
```

- [ ] **Step 3: Reorder the aim in `addMaster` and pass the fit.** `script_read` the block from `local fov = opts.fov or 30` to `vp.CurrentCamera = cam`. `multi_edit` — `old_string`:
```lua
	local fov = opts.fov or 30
	local centre, dist = M.framing(m, fov)
	-- Aim RELATIVE TO THE MODEL'S PIVOT, not world axes. The pack models share one
	-- local convention (front = local -Z), but a chunk of them were imported with
	-- their pivot yawed 180 (Frigo Camelo, Gattatino Nyanino, ... all have a 180 spin
	-- in WorldPivot.Rotation), so a fixed world DEFAULT_DIR showed their BACKS on the
	-- card. Viewing from the pivot's own front-quarter faces every model the same way.
	-- Identity-pivot models -- the ones that already looked right -- transform to the
	-- exact same direction, so this cannot regress them.
	local dir = m:GetPivot():VectorToWorldSpace(opts.dir or DEFAULT_DIR)
	-- Per-model straggler flip (M.FACING): spin the view direction about world Y so
	-- an oddly-modelled face turns to the camera. Models stand upright, so a world-Y
	-- spin is the whole correction. No-op for the common (0/nil) case.
	if opts.faceYaw and opts.faceYaw ~= 0 then
		dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(opts.faceYaw)) * dir
	end
```
`new_string`:
```lua
	local fov = opts.fov or 30
	-- Aim RELATIVE TO THE MODEL'S PIVOT, not world axes. The pack models share one
	-- local convention (front = local -Z), but a chunk of them were imported with
	-- their pivot yawed 180 (Frigo Camelo, Gattatino Nyanino, ... all have a 180 spin
	-- in WorldPivot.Rotation), so a fixed world DEFAULT_DIR showed their BACKS on the
	-- card. Viewing from the pivot's own front-quarter faces every model the same way.
	-- Identity-pivot models -- the ones that already looked right -- transform to the
	-- exact same direction, so this cannot regress them.
	local dir = m:GetPivot():VectorToWorldSpace(opts.dir or DEFAULT_DIR)
	-- Per-model straggler flip (M.FACING): spin the view direction about world Y so
	-- an oddly-modelled face turns to the camera. Models stand upright, so a world-Y
	-- spin is the whole correction. No-op for the common (0/nil) case.
	if opts.faceYaw and opts.faceYaw ~= 0 then
		dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(opts.faceYaw)) * dir
	end
	-- 2026-09-18: the aim is computed BEFORE framing now, because the box fit
	-- (opts.fill, cards) needs the real view direction and the viewport's aspect.
	-- Callers without opts.fill get the sphere fit exactly as before.
	local fitOpts = nil
	if opts.fill then
		local aspect = opts.aspect
		if not aspect then
			local abs = vp.AbsoluteSize
			aspect = if abs.Y > 0 then abs.X / abs.Y else 1
		end
		fitOpts = { dir = dir, aspect = aspect, fill = opts.fill }
	end
	local centre, dist = M.framing(m, fov, fitOpts)
```

- [ ] **Step 4: Compile-gate + numeric framing test over the roster's extremes.** `execute_luau` (Edit):

```lua
-- [TEST LOADER PREAMBLE from .superpowers/sdd/2026-09-18-ui-foundation/test-loader.lua goes here]
local f, e = loadstring(RS.Modules.BrainrotThumb.Source); assert(f, e)
assert(RS.Modules.BrainrotThumb.Source:find("function M.framingBox(", 1, true) and RS.Modules.BrainrotThumb.Source:find("fitOpts = { dir = dir", 1, true), "edits missing")
local BT = load(RS.Modules.BrainrotThumb)
-- sphere path unchanged for two-arg callers
local anyModel = RS.BrainrotModels:GetChildren()[1]
local c1, d1 = BT.framing(anyModel, 30); local c2, d2 = BT.framingSphere(anyModel, 30)
assert(c1 == c2 and d1 == d2, "two-arg framing == sphere")
-- extremes over the roster: tallest, widest, biggest, smallest by bounding box
local picks = {}
local best = { tall = -1, wide = -1, big = -1, small = math.huge }
for _, m in ipairs(RS.BrainrotModels:GetChildren()) do
	if m:IsA("Model") then
		local ok, _, ext = pcall(function() return m:GetBoundingBox() end)
		if ok and ext and ext.Magnitude > 0 then
			local tall = ext.Y / math.max(ext.X, ext.Z)
			local wide = math.max(ext.X, ext.Z) / ext.Y
			local vol = ext.X * ext.Y * ext.Z
			if tall > best.tall then best.tall = tall; picks.tall = m end
			if wide > best.wide then best.wide = wide; picks.wide = m end
			if vol > best.big then best.big = vol; picks.big = m end
			if vol < best.small then best.small = vol; picks.small = m end
		end
	end
end
local fov, fill, aspect = 30, 0.70, 92 / 100
local tanV = math.tan(math.rad(fov * 0.5)); local tanH = tanV * aspect
local out = {}
for key, m in pairs(picks) do
	local dir = m:GetPivot():VectorToWorldSpace(BT.DEFAULT_DIR)
	local centre, dist = BT.framingBox(m, fov, { dir = dir, aspect = aspect, fill = fill })
	local _, ds = BT.framingSphere(m, fov)
	local look = -dir; local right = look:Cross(Vector3.yAxis).Unit; local up = right:Cross(look).Unit
	local cf, ext = m:GetBoundingBox()
	local maxAbs, minX, maxX, minY, maxY = 0, math.huge, -math.huge, math.huge, -math.huge
	for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
		local q = cf:PointToWorldSpace(Vector3.new(sx * ext.X / 2, sy * ext.Y / 2, sz * ext.Z / 2))
		local w = q - centre
		local depth = dist - w:Dot(dir)
		local px, py = w:Dot(right) / depth / tanH, w:Dot(up) / depth / tanV
		maxAbs = math.max(maxAbs, math.abs(px), math.abs(py))
		minX, maxX, minY, maxY = math.min(minX, px), math.max(maxX, px), math.min(minY, py), math.max(maxY, py)
	end end end
	local midX, midY = (minX + maxX) / 2, (minY + maxY) / 2
	table.insert(out, ("%s=%s fill=%.3f mid=(%.3f,%.3f) box/sphere=%.2f"):format(key, m.Name, maxAbs, midX, midY, dist / ds))
	assert(maxAbs <= fill + 0.005, key .. " overflows the fill")
	assert(maxAbs >= fill - 0.03, key .. " under-fills")
	assert(math.abs(midX) <= 0.02 and math.abs(midY) <= 0.02, key .. " off-centre")
end
-- addMaster with fill builds a camera in a real viewport parent
local sg = Instance.new("ScreenGui"); sg.Name = "UIKitScratch"; sg.Parent = CoreGui
local holder = Instance.new("Frame"); holder.Size = UDim2.fromOffset(92, 100); holder.Parent = sg
local vp = BT.add(holder, picks.big.Name, { fill = 0.7 })
assert(vp and vp.CurrentCamera, "add() with fill produced a camera")
sg.Parent = nil
return table.concat(out, "\n")
```

Expected: four lines, each with `fill=0.700` (± 0.03), `mid` within ± 0.02, and `box/sphere` below 1 for the tall/wide picks (the sphere over-reserved them).

- [ ] **Step 5: Live regression.** Play; open the Bag (Brainrots tab) and the Index tab; both grids still render art exactly as before (two-arg callers). Console clean. Stop Play.

- [ ] **Step 6: Mirror + commit.** → `game-src/place-full/ReplicatedStorage/Modules/BrainrotThumb.lua`; commit `feat(preview): projected-corner framing with fill/aspect; sphere fit kept for spinning previews`.

---

### Task 9: `BrainrotCard`

**Files:**
- Create: `ReplicatedStorage.Modules.UIKit.BrainrotCard` (ModuleScript)

**Interfaces:**
- Consumes: `S.Card` (Task 2), `PanelChrome.shout`, `FxDriver` (3), `BrainrotThumb.master/petMaster/addMaster/FACING` with `fill` (8), `NumberFormat.Cash`.
- Produces: `BrainrotCard.new(props) → Card` where
  ```lua
  props = {
      kind = "brainrot" | "pet", name = string, model = string?,      -- model = PetConfig.Model for pets
      rarity = tier name, income = number?, mutation = string?, mutationColor = Color3?,
      sizeTag = string?, count = number?,
      state = { equipped = false | padIndex, locked = bool, selected = bool, new = bool }?,
      lock = { onToggle = function(nextLocked: boolean) }?,
      title = string?, variant = "grid" | "compact" | "hero",
      parent = Instance?, zIndex = number?, layoutOrder = number?, instanceName = string?,
  }
  Card = { root: Frame (CellRoot), visual: Frame, plate: Frame, art: Frame, data: props,
           set(patch), setState(patch), mount(), unmount(), isMounted(): boolean, destroy(),
           Activated: RBXScriptSignal, HoverStart: RBXScriptSignal, HoverEnd: RBXScriptSignal }
  ```
  `isMounted/mount/unmount/root` is exactly the `Cullable` shape `ViewportCuller` (Task 10) consumes.

- [ ] **Step 1: Create the module.** `multi_edit` (`className = "ModuleScript"`, `old_string = ""`):

```lua
--!strict
-- BrainrotCard -- the ONE collectible card (spec 2026-09-18 UI foundation §7).
-- Style C "dark well tile": RARITY is the card's identity (edge, band, pips, foil,
-- aura, holo ring and sparkles escalate by tier, from S.Card.Ladder); equipped /
-- locked / new / mutation / size are small corner badges that never recolour the
-- plate, edge, band or aura (decision 5).
--
-- Data in, instances out. This module never reads BrainrotConfig, RarityConfig,
-- remotes or save fields: the panel maps its entries -- and normalises its legacy
-- "Fav" flag to `locked` -- before calling new(). The lock control is a padlock
-- toggle; a favourite system, if ever added, is a separate state.
--
-- Structure (§7.2):
--   CellRoot   (transparent; owned by the consumer's UIGridLayout; never animated)
--   └─ VisualRoot (hover/press tween its Position; everything visible hangs off it)
--      ├─ Shadow, SelectionRing            (OUTSIDE the clipped plate)
--      └─ Plate (ClipsDescendants)         → Aura, Foil, ArtWell, ContactShadow,
--                                             ArtHolder (viewport mounts here), HoloRing,
--                                             Pips, Band, Rate, Sparkles,
--                                             BadgesRight, BadgesLeft, Hit
-- Animation only through FxDriver: registered on mount(), released on unmount(),
-- at most S.Card.MaxAnimatedLayers layers per card (the ladder names them).
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local S = require(script.Parent.SpecTheme)
local PC = require(script.Parent.PanelChrome)
local FxDriver = require(script.Parent.FxDriver)
local modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))
local NumberFormat = require(modules:WaitForChild("NumberFormat"))

export type State = { equipped: (boolean | number)?, locked: boolean?, selected: boolean?, new: boolean? }
export type Props = {
	kind: string?, name: string, model: string?, rarity: string, income: number?,
	mutation: string?, mutationColor: Color3?, sizeTag: string?, count: number?,
	state: State?, lock: { onToggle: (nextLocked: boolean) -> () }?,
	title: string?, variant: string?,
	parent: Instance?, zIndex: number?, layoutOrder: number?, instanceName: string?,
}
export type Card = {
	root: Frame, visual: Frame, plate: Frame, art: Frame, data: Props,
	set: (patch: { [string]: any }) -> (), setState: (patch: State) -> (),
	mount: () -> (), unmount: () -> (), isMounted: () -> boolean, destroy: () -> (),
	Activated: RBXScriptSignal, HoverStart: RBXScriptSignal, HoverEnd: RBXScriptSignal,
}

local BrainrotCard = {}

local UNLIT_PIP = Color3.fromHex("39414F")
local RAINBOW_INK = Color3.fromHex("12060C")
local NEW_RED = Color3.fromHex("FF3D6E")
local INK_DARK = Color3.fromHex("10141C")

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, msg: string)
	if warned[key] then return end
	warned[key] = true
	warn("[UIKit] BrainrotCard: " .. msg)
end

local function corner(o: GuiObject, r: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
	return c
end

local function stroke(o: GuiObject, thickness: number, color: Color3): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = o
	return s
end

local function frame(name: string, parent: Instance, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- padlock from two frames (shackle + body), like the Bag's buildPadlock
local function drawPadlock(parent: GuiObject, px: number, tint: Color3, z: number)
	local shackle = Instance.new("Frame")
	shackle.Name = "Shackle"
	shackle.BackgroundTransparency = 1
	shackle.AnchorPoint = Vector2.new(0.5, 0)
	shackle.Position = UDim2.new(0.5, 0, 0, math.floor(px * 0.12))
	shackle.Size = UDim2.fromOffset(math.floor(px * 0.44), math.floor(px * 0.42))
	shackle.ZIndex = z
	corner(shackle, 999)
	stroke(shackle, math.max(2, math.floor(px * 0.11)), tint)
	shackle.Parent = parent
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = tint
	body.BorderSizePixel = 0
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.new(0.5, 0, 1, -math.floor(px * 0.12))
	body.Size = UDim2.fromOffset(math.floor(px * 0.62), math.floor(px * 0.46))
	body.ZIndex = z + 1
	corner(body, math.max(2, math.floor(px * 0.14)))
	body.Parent = parent
end

-- ONE release-anywhere guard for every card (§7.6): a finger that slides off a card
-- before lifting -- the ordinary scroll gesture -- must still release that card.
local pressedRelease: (() -> ())? = nil
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	local r = pressedRelease
	pressedRelease = nil
	if r then r() end
end)

function BrainrotCard.new(props: Props): Card
	local C = S.Card
	local tierKey = C.TIER_KEY[props.rarity or ""]
	if not tierKey then
		warnOnce("rarity:" .. tostring(props.rarity), ("unknown rarity %q for %q -- using Common"):format(tostring(props.rarity), tostring(props.name)))
		tierKey = "COM"
	end
	local ladder = C.Ladder[tierKey]
	local ramp = S.Rarity[tierKey]
	local variantName = props.variant or "grid"
	local variant = C.Variants[variantName]
	if not variant then
		warnOnce("variant:" .. tostring(variantName), ("unknown variant %q -- using grid"):format(tostring(variantName)))
		variantName = "grid"
		variant = C.Variants.grid
	end
	local isHero, isCompact = variantName == "hero", variantName == "compact"
	local z = props.zIndex or 15
	local state: State = { equipped = false, locked = false, selected = false, new = false }
	if props.state then
		for k, v in pairs(props.state) do (state :: any)[k] = v end
	end
	local data: Props = props
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local radius = C.Radius
	local bandFrac = C.BandFrac
	local bandMin = variant.bandMin or C.BandMin

	---------------------------------------------------------------- roots
	local cell = Instance.new("Frame")
	cell.Name = props.instanceName or ("Card_" .. tostring(props.name))
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.Size = UDim2.fromScale(1, 1)
	cell.ZIndex = z
	if props.layoutOrder then cell.LayoutOrder = props.layoutOrder end
	cell:SetAttribute("BrainrotName", props.name)
	cell:SetAttribute("Rarity", props.rarity)

	local visual = frame("VisualRoot", cell, z)
	visual.AnchorPoint = Vector2.new(0.5, 0.5)
	visual.Position = UDim2.fromScale(0.5, 0.5)
	visual.Size = UDim2.fromScale(1, 1)

	local shadow = frame("Shadow", visual, z)
	shadow.BackgroundTransparency = 0.72
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.Position = UDim2.fromOffset(0, 4)
	shadow.Size = UDim2.fromScale(1, 1)
	corner(shadow, radius)

	local ring = frame("SelectionRing", visual, z + 1)
	ring.Position = UDim2.fromOffset(-4, -4)
	ring.Size = UDim2.new(1, 8, 1, 8)
	ring.Visible = state.selected == true
	corner(ring, radius + 4)
	stroke(ring, 3, S.Role.Selection)

	local plate = frame("Plate", visual, z + 1)
	plate.BackgroundTransparency = 0
	plate.BackgroundColor3 = C.Plate[1]
	plate.Size = UDim2.fromScale(1, 1)
	plate.ClipsDescendants = true
	corner(plate, radius)
	local plateGrad = Instance.new("UIGradient")
	plateGrad.Rotation = 90
	plateGrad.Color = ColorSequence.new(C.Plate[1], C.Plate[2])
	plateGrad.Parent = plate
	local edge = stroke(plate, C.Edge, ramp[2])
	edge.Name = "Edge"

	---------------------------------------------------------------- rarity layers
	local aura: Frame? = nil
	if ladder.aura then
		local a = frame("Aura", plate, z + 2)
		a.BackgroundTransparency = if ladder.aura == "strong" then 0.35 else 0.45
		a.BackgroundColor3 = ramp[2]
		a.AnchorPoint = Vector2.new(0, 1)
		a.Position = UDim2.new(0, 0, 1 - bandFrac, 0)
		a.Size = UDim2.new(1, 0, 0.45, 0)
		local ag = Instance.new("UIGradient")
		ag.Rotation = -90
		ag.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		ag.Parent = a
		aura = a
	end
	if ladder.foil then
		local foil = frame("Foil", plate, z + 2)
		foil.BackgroundTransparency = ladder.foil
		foil.BackgroundColor3 = Color3.new(1, 1, 1)
		foil.Size = UDim2.new(1, 0, 1 - bandFrac, 0)
		local fg = Instance.new("UIGradient")
		fg.Rotation = 25
		fg.Color = C.Rainbow -- static sheet: foil never drifts (decision 16)
		fg.Parent = foil
	end
	local well = frame("ArtWell", plate, z + 2)
	well.BackgroundTransparency = C.ArtWellAlpha
	well.BackgroundColor3 = Color3.new(1, 1, 1)
	well.AnchorPoint = Vector2.new(0.5, 0.5)
	well.Position = UDim2.new(0.5, 0, (1 - bandFrac) * 0.5, 0)
	well.Size = UDim2.new(0.8, 0, (1 - bandFrac) * 0.72, 0)
	corner(well, 999)
	local contact = frame("ContactShadow", plate, z + 3)
	contact.BackgroundTransparency = 0.55
	contact.BackgroundColor3 = Color3.new(0, 0, 0)
	contact.AnchorPoint = Vector2.new(0.5, 1)
	contact.Position = UDim2.new(0.5, 0, 1 - bandFrac, -4)
	contact.Size = UDim2.new(0.5, 0, 0, 8)
	corner(contact, 999)

	local art = frame("ArtHolder", plate, z + 3)
	art.Position = UDim2.fromOffset(C.ArtInset, C.ArtInset)
	art.Size = UDim2.new(1, -2 * C.ArtInset, 1 - bandFrac, -(C.ArtInset + 8))

	if ladder.holo then
		-- static rainbow ring around the art (a UIGradient on a UIStroke); the
		-- animated rainbow lives on the band only, so the cap holds
		local holo = frame("HoloRing", plate, z + 4)
		holo.AnchorPoint = Vector2.new(0.5, 0.5)
		holo.Position = UDim2.new(0.5, 0, (1 - bandFrac) * 0.5, 0)
		holo.Size = UDim2.new(1, -2, 1 - bandFrac, -2)
		corner(holo, radius - 2)
		local hs = stroke(holo, 3, Color3.new(1, 1, 1))
		local hg = Instance.new("UIGradient")
		hg.Color = C.Rainbow
		hg.Parent = hs
	end

	-- pips (top-left): lit count by tier
	local pips = frame("Pips", plate, z + 5)
	pips.Position = UDim2.fromOffset(8, 8)
	pips.Size = UDim2.fromOffset(5 * (C.Pip + 5), C.Pip + 2)
	for i = 1, 5 do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.Size = UDim2.fromOffset(C.Pip, C.Pip)
		pip.Position = UDim2.fromOffset((i - 1) * (C.Pip + 5), 1)
		pip.Rotation = 45
		pip.BorderSizePixel = 0
		pip.ZIndex = z + 5
		pip.BackgroundColor3 = if i <= ladder.pips then ramp[1] else UNLIT_PIP
		pip.Parent = pips
	end

	-- band (bottom): tier name + count
	local band = frame("Band", plate, z + 4)
	band.BackgroundTransparency = 0
	band.AnchorPoint = Vector2.new(0, 1)
	band.Position = UDim2.fromScale(0, 1)
	band.Size = UDim2.new(1, 0, bandFrac, 0)
	local bandFloor = Instance.new("UISizeConstraint")
	bandFloor.MinSize = Vector2.new(0, bandMin)
	bandFloor.Parent = band
	local bandGrad: UIGradient? = nil
	local bandInk, bandStroke = Color3.new(1, 1, 1), S.Outline
	if ladder.band == "rainbow" then
		band.BackgroundColor3 = Color3.new(1, 1, 1)
		local bg = Instance.new("UIGradient")
		bg.Color = C.Rainbow
		bg.Parent = band
		bandGrad = bg
		bandInk, bandStroke = RAINBOW_INK, Color3.new(1, 1, 1)
	else
		band.BackgroundColor3 = ramp[2]
		band.BackgroundTransparency = if ladder.band == "muted" then 0.75 else 0.35
	end
	local tierName = PC.shout({
		name = "TierName", text = string.upper(props.rarity or "?"), size = if isHero then 22 else 13,
		color = bandInk, strokeColor = bandStroke, align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -56, 1, 0), position = UDim2.fromOffset(8, 0), zIndex = z + 5, parent = band, scaled = true,
	})
	local countLabel = PC.shout({
		name = "Count", text = "", size = if isHero then 22 else 14, color = bandInk, strokeColor = bandStroke,
		align = Enum.TextXAlignment.Right, frameSize = UDim2.fromOffset(48, 0), position = UDim2.new(1, -8, 0, 0),
		anchor = Vector2.new(1, 0), zIndex = z + 5, parent = band, scaled = true,
	})
	countLabel.Size = UDim2.new(0, 48, 1, 0)

	-- rate pill above the band
	local rateH = if isHero then 30 elseif isCompact then 15 else 18
	local ratePill = frame("Rate", plate, z + 5)
	ratePill.BackgroundTransparency = 0.15
	ratePill.BackgroundColor3 = INK_DARK
	ratePill.AnchorPoint = Vector2.new(0.5, 1)
	ratePill.Position = UDim2.new(0.5, 0, 1 - bandFrac, -4)
	ratePill.Size = UDim2.fromOffset(0, rateH)
	ratePill.AutomaticSize = Enum.AutomaticSize.X
	corner(ratePill, 999)
	local ratePad = Instance.new("UIPadding")
	ratePad.PaddingLeft = UDim.new(0, 7)
	ratePad.PaddingRight = UDim.new(0, 7)
	ratePad.Parent = ratePill
	local rateLabel = PC.shout({
		name = "Label", text = "", size = math.floor(rateH * 0.8), zIndex = z + 6, parent = ratePill,
		frameSize = UDim2.new(0, 0, 1, 0),
	})
	rateLabel.AutomaticSize = Enum.AutomaticSize.X
	local function paintRate()
		local v = tonumber(data.income) or 0
		rateLabel.Text = NumberFormat.Cash(v) .. "/s"
		ratePill.Visible = data.income ~= nil
	end
	paintRate()

	-- sparkles (Secret, God)
	local sparkles: { TextLabel } = {}
	if ladder.sparkles then
		for i, pos in ipairs({ UDim2.new(0.12, 0, 0.12, 0), UDim2.new(0.84, 0, 0.09, 0), UDim2.new(0.8, 0, 0.5, 0) }) do
			local sp = PC.shout({ name = "Sparkle" .. i, text = "\u{2726}", size = if isHero then 22 else 13, color = ramp[1], strokeColor = S.Outline, zIndex = z + 5, parent = plate, frameSize = UDim2.fromOffset(18, 18), position = pos, anchor = Vector2.new(0.5, 0.5) })
			table.insert(sparkles, sp)
		end
	end

	-- hero title
	if variant.title and props.title then
		PC.shout({ name = "Title", text = props.title, size = 26, zIndex = z + 5, parent = plate, scaled = true,
			frameSize = UDim2.new(1, -16, 0, 34), position = UDim2.new(0, 8, 1 - bandFrac, -(rateH + 42)) })
	end

	---------------------------------------------------------------- badges
	local badgePx = C.Badge
	-- badges sit ABOVE the Hit button (z+6) so the lock toggle receives its click
	local rightStack = frame("BadgesRight", plate, z + 7)
	rightStack.AnchorPoint = Vector2.new(1, 0)
	rightStack.Position = UDim2.new(1, -4, 0, 4)
	rightStack.Size = UDim2.fromOffset(badgePx + 14, 0)
	rightStack.AutomaticSize = Enum.AutomaticSize.Y
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Vertical
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rl.Padding = UDim.new(0, 4)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = rightStack

	local leftRow: Frame? = nil
	if variant.leftBadges then
		local lr = frame("BadgesLeft", plate, z + 7)
		lr.Position = UDim2.fromOffset(8, 8 + C.Pip + 8)
		lr.Size = UDim2.fromOffset(0, C.MutationStar)
		lr.AutomaticSize = Enum.AutomaticSize.X
		local ll = Instance.new("UIListLayout")
		ll.FillDirection = Enum.FillDirection.Horizontal
		ll.VerticalAlignment = Enum.VerticalAlignment.Center
		ll.Padding = UDim.new(0, 4)
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Parent = lr
		leftRow = lr
	end

	local lockBtn: TextButton? = nil
	local hovering = false

	local function paintLeft()
		if not leftRow then return end
		for _, c in ipairs(leftRow:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		if data.mutation and data.mutation ~= "" then
			-- mutation gem: the mutation's OWN colour (decision 17), a rotated square
			-- with a dark edge so it never reads as a rarity pip
			local gemHolder = frame("MutationGem", leftRow, z + 6)
			gemHolder.LayoutOrder = 1
			gemHolder.Size = UDim2.fromOffset(C.MutationStar, C.MutationStar)
			local gem = Instance.new("Frame")
			gem.Name = "Gem"
			gem.AnchorPoint = Vector2.new(0.5, 0.5)
			gem.Position = UDim2.fromScale(0.5, 0.5)
			gem.Size = UDim2.fromOffset(math.floor(C.MutationStar * 0.68), math.floor(C.MutationStar * 0.68))
			gem.Rotation = 45
			gem.BorderSizePixel = 0
			gem.BackgroundColor3 = data.mutationColor or S.Role.Purple[1]
			gem.ZIndex = z + 7
			corner(gem, 2)
			stroke(gem, 2, INK_DARK)
			gem.Parent = gemHolder
		end
		if data.sizeTag and data.sizeTag ~= "" then
			-- size chip: ONE neutral secondary treatment, never red (decision 17)
			local chip = frame("SizeChip", leftRow, z + 6)
			chip.LayoutOrder = 2
			chip.BackgroundTransparency = 0
			chip.BackgroundColor3 = S.Surface.Track
			chip.Size = UDim2.fromOffset(0, C.BadgeSmall)
			chip.AutomaticSize = Enum.AutomaticSize.X
			corner(chip, 4)
			local cp = Instance.new("UIPadding")
			cp.PaddingLeft = UDim.new(0, 4)
			cp.PaddingRight = UDim.new(0, 4)
			cp.Parent = chip
			local l = PC.shout({ name = "Label", text = string.upper(data.sizeTag), size = C.BadgeSmall - 4, zIndex = z + 7, parent = chip, frameSize = UDim2.new(0, 0, 1, 0) })
			l.AutomaticSize = Enum.AutomaticSize.X
		end
	end

	local function paintRight()
		for _, c in ipairs(rightStack:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		lockBtn = nil
		local cap = variant.rightCap or 2
		local used = 0
		-- priority: Locked / lock toggle > Equipped > NEW (§7.5)
		if (state.locked == true or props.lock) and used < cap then
			used += 1
			local b = Instance.new("TextButton")
			b.Name = "Lock"
			b.Text = ""
			b.AutoButtonColor = false
			b.BorderSizePixel = 0
			b.LayoutOrder = 1
			b.Size = UDim2.fromOffset(badgePx, badgePx)
			b.BackgroundColor3 = S.Role.Disabled[1]
			b.ZIndex = z + 7
			b.Active = props.lock ~= nil
			b:SetAttribute("NoPolish", true)
			corner(b, 6)
			stroke(b, 2, Color3.new(1, 1, 1))
			drawPadlock(b, badgePx, S.Surface.ReadInk, z + 8)
			if state.locked == true then
				b.Visible = true
				b.BackgroundTransparency = 0
			elseif touchOnly then
				b.Visible = true -- always reachable on touch, drawn subdued
				b.BackgroundTransparency = 0.5
			else
				b.Visible = hovering -- desktop: revealed on hover
				b.BackgroundTransparency = 0.25
			end
			if props.lock then
				b.Activated:Connect(function()
					local fn = props.lock and props.lock.onToggle
					if fn then
						local ok, err = pcall(fn, not (state.locked == true))
						if not ok then warn(("[UIKit] BrainrotCard lock toggle failed: %s\n%s"):format(tostring(err), debug.traceback())) end
					end
				end)
			end
			b.Parent = rightStack
			lockBtn = b
		end
		if state.equipped and state.equipped ~= false and used < cap then
			used += 1
			local padText = if typeof(state.equipped) == "number" then ("\u{2713}%d"):format(state.equipped :: number) else "\u{2713}"
			local e = frame("Equipped", rightStack, z + 7)
			e.LayoutOrder = 2
			e.BackgroundTransparency = 0
			e.BackgroundColor3 = S.Role.Positive[1]
			e.Size = UDim2.fromOffset(if typeof(state.equipped) == "number" then badgePx + 12 else badgePx, badgePx)
			corner(e, 6)
			stroke(e, 2, Color3.new(1, 1, 1))
			PC.shout({ name = "Label", text = padText, size = badgePx - 8, color = Color3.fromHex("06301B"), strokeColor = Color3.new(1, 1, 1), zIndex = z + 8, parent = e })
		end
		if state.new == true and used < cap then
			used += 1
			local n = frame("New", rightStack, z + 7)
			n.LayoutOrder = 3
			n.BackgroundTransparency = 0
			n.BackgroundColor3 = NEW_RED
			n.Size = UDim2.fromOffset(30, C.BadgeSmall)
			corner(n, 4)
			PC.shout({ name = "Label", text = "NEW", size = C.BadgeSmall - 5, zIndex = z + 8, parent = n })
		end
	end

	paintLeft()
	paintRight()

	---------------------------------------------------------------- signals + feel
	local activatedEv = Instance.new("BindableEvent")
	activatedEv.Name = "ActivatedEvent"
	activatedEv.Parent = cell
	local hoverStartEv = Instance.new("BindableEvent")
	hoverStartEv.Name = "HoverStartEvent"
	hoverStartEv.Parent = cell
	local hoverEndEv = Instance.new("BindableEvent")
	hoverEndEv.Name = "HoverEndEvent"
	hoverEndEv.Parent = cell

	local REST = UDim2.fromScale(0.5, 0.5)
	local LIFT = UDim2.new(0.5, 0, 0.5, -3)
	local SINK = UDim2.new(0.5, 0, 0.5, 1)
	local function moveTo(pos: UDim2, info: TweenInfo)
		TweenService:Create(visual, info, { Position = pos }):Play()
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = z + 6 -- under the badges (z+7), over every layer
	hit:SetAttribute("NoPolish", true)
	hit.Parent = plate

	local isDown = false
	local function release()
		isDown = false
		if hovering then moveTo(LIFT, S.Tween.HoverIn) else moveTo(REST, S.Tween.HoverOut) end
	end
	hit.MouseEnter:Connect(function()
		if touchOnly then return end
		hovering = true
		if lockBtn and state.locked ~= true then lockBtn.Visible = true end
		moveTo(LIFT, S.Tween.HoverIn)
		hoverStartEv:Fire()
	end)
	hit.MouseLeave:Connect(function()
		hovering = false
		if lockBtn and state.locked ~= true and not touchOnly then lockBtn.Visible = false end
		if not isDown then moveTo(REST, S.Tween.HoverOut) end
		hoverEndEv:Fire()
	end)
	hit.MouseButton1Down:Connect(function()
		isDown = true
		pressedRelease = release
		moveTo(SINK, S.Tween.Press)
	end)
	hit.MouseButton1Up:Connect(function()
		if pressedRelease == release then pressedRelease = nil end
		release()
	end)
	hit.Activated:Connect(function()
		activatedEv:Fire()
	end)

	---------------------------------------------------------------- mount / unmount
	local mounted = false
	local vp: ViewportFrame? = nil
	local placeholder: TextLabel? = nil
	local fxIds: { number } = {}

	local function clearFx()
		for _, id in ipairs(fxIds) do FxDriver.unregister(id) end
		table.clear(fxIds)
	end
	local function registerFx()
		clearFx()
		local n = 0
		for _, layer in ipairs(ladder.animated) do
			if n >= C.MaxAnimatedLayers then break end
			if layer == "aura" and aura then
				local a = aura :: Frame
				table.insert(fxIds, FxDriver.register(plate, function(t)
					a.BackgroundTransparency = 0.25 + 0.40 * (0.5 + 0.5 * math.sin(t * 1.9))
				end))
				n += 1
			elseif layer == "band" and bandGrad then
				local g = bandGrad :: UIGradient
				table.insert(fxIds, FxDriver.register(plate, function(t)
					g.Offset = Vector2.new((t * 0.3) % 2 - 1, 0)
				end))
				n += 1
			elseif layer == "sparkles" and #sparkles > 0 then
				table.insert(fxIds, FxDriver.register(plate, function(t)
					for i, sp in ipairs(sparkles) do
						sp.TextTransparency = 0.3 + 0.6 * (0.5 + 0.5 * math.sin(t * 3.1 + i * 2.1))
					end
				end))
				n += 1
			end
		end
	end

	local function showPlaceholder()
		if placeholder then return end
		local q = PC.shout({ name = "MissingArt", text = "?", size = 40, color = S.Surface.ReadSub, strokeColor = INK_DARK, zIndex = z + 4, parent = art })
		placeholder = q
	end

	local function mount()
		if mounted then return end
		mounted = true
		local master = if data.kind == "pet"
			then BrainrotThumb.petMaster(data.model, data.name)
			else BrainrotThumb.master(data.name)
		if master then
			local ok, res = pcall(function()
				return BrainrotThumb.addMaster(art, master, {
					size = UDim2.fromScale(1, 1), zIndex = z + 4,
					dir = C.Light.Dir, ambient = C.Light.Ambient, lightColor = C.Light.LightColor, lightDirection = C.Light.LightDirection,
					fill = C.Fill,
					faceYaw = if data.kind == "pet" then nil else BrainrotThumb.FACING[data.name],
				})
			end)
			if ok and res then
				vp = res
				vp.Name = "Preview"
			else
				if not ok then
					warnOnce("clone:" .. tostring(data.name), ("viewport for %q failed: %s\n%s"):format(tostring(data.name), tostring(res), debug.traceback()))
				end
				showPlaceholder()
			end
		else
			showPlaceholder()
		end
		registerFx()
	end

	local function unmount()
		if not mounted then return end
		mounted = false
		clearFx()
		if vp then vp:Destroy() vp = nil end
		if placeholder then placeholder:Destroy() placeholder = nil end
	end

	---------------------------------------------------------------- api
	local card: Card
	card = {
		root = cell, visual = visual, plate = plate, art = art, data = data,
		setState = function(patch: State)
			for k, v in pairs(patch) do (state :: any)[k] = v end
			ring.Visible = state.selected == true
			paintRight()
		end,
		set = function(patch: { [string]: any })
			if patch.rarity ~= nil and patch.rarity ~= data.rarity then
				warnOnce("set-rarity", "set({ rarity }) is not supported -- destroy and rebuild the card")
			end
			for k, v in pairs(patch) do
				if k == "state" then
					card.setState(v)
				elseif k ~= "rarity" then
					(data :: any)[k] = v
				end
			end
			paintRate()
			countLabel.Text = if data.count and data.count > 1 then "x" .. tostring(data.count) else ""
			paintLeft()
		end,
		mount = mount,
		unmount = unmount,
		isMounted = function() return mounted end,
		destroy = function()
			unmount()
			if pressedRelease == release then pressedRelease = nil end
			cell:Destroy()
		end,
		Activated = activatedEv.Event,
		HoverStart = hoverStartEv.Event,
		HoverEnd = hoverEndEv.Event,
	}
	countLabel.Text = if data.count and data.count > 1 then "x" .. tostring(data.count) else ""
	cell.Parent = props.parent
	return card
end

return BrainrotCard
```

- [ ] **Step 2: Compile-gate + structural test across the ladder.** `execute_luau` (Edit):

```lua
-- [TEST LOADER PREAMBLE from .superpowers/sdd/2026-09-18-ui-foundation/test-loader.lua goes here]
local f, e = loadstring(RS.Modules.UIKit.BrainrotCard.Source); assert(f, e)
local S, Card, Fx = load(kit.SpecTheme), load(kit.BrainrotCard), load(kit.FxDriver)
local sg = Instance.new("ScreenGui"); sg.Name = "UIKitScratch"; sg.Parent = CoreGui
local grid = Instance.new("Frame"); grid.Size = UDim2.fromOffset(900, 300); grid.BackgroundTransparency = 1; grid.Parent = sg
local gl = Instance.new("UIGridLayout"); gl.CellSize = UDim2.fromOffset(100, 132); gl.CellPadding = UDim2.fromOffset(8, 8); gl.SortOrder = Enum.SortOrder.LayoutOrder; gl.Parent = grid
local realName = RS.BrainrotModels:GetChildren()[1].Name
local tiers = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "God" }
local cards = {}
for i, tier in ipairs(tiers) do
	cards[i] = Card.new({ kind = "brainrot", name = realName, rarity = tier, income = 1234 * i, mutation = (i % 2 == 0) and "Golden" or nil, mutationColor = Color3.fromRGB(255, 215, 60), sizeTag = (i == 3) and "Huge" or nil, variant = "grid", parent = grid, layoutOrder = i })
end
task.wait()
assert(cards[1].root.AbsoluteSize.X == 100, "layout owns CellRoot")
for i, tier in ipairs(tiers) do
	local c = cards[i]; local key = S.Card.TIER_KEY[tier]; local L = S.Card.Ladder[key]
	local p = c.plate
	assert(c.root.VisualRoot == c.visual and c.visual.Plate == p and c.visual:FindFirstChild("Shadow") and c.visual:FindFirstChild("SelectionRing"), tier .. " roots")
	assert(p.ClipsDescendants and not c.visual.ClipsDescendants and not c.root.ClipsDescendants, tier .. " only the plate clips")
	assert(p.Edge.Color == S.Rarity[key][2], tier .. " edge colour")
	assert((p:FindFirstChild("Aura") ~= nil) == (L.aura ~= nil), tier .. " aura")
	assert((p:FindFirstChild("Foil") ~= nil) == (L.foil ~= nil), tier .. " foil")
	assert((p:FindFirstChild("HoloRing") ~= nil) == L.holo, tier .. " holo")
	assert((p:FindFirstChild("Sparkle1") ~= nil) == L.sparkles, tier .. " sparkles")
	local lit = 0; for j = 1, 5 do if p.Pips["Pip" .. j].BackgroundColor3 == S.Rarity[key][1] then lit += 1 end end
	assert(lit == L.pips, tier .. " pips " .. lit)
	assert(p.Band.TierName.Text == tier:upper(), tier .. " band name")
	assert((p.Band:FindFirstChildOfClass("UIGradient") ~= nil) == (L.band == "rainbow"), tier .. " rainbow band")
	assert(p.Rate.Label.Text:sub(1, 1) == "$" and p.Rate.Label.Text:sub(-2) == "/s", tier .. " rate")
end
assert(cards[2].plate.BadgesLeft:FindFirstChild("MutationGem") and not cards[1].plate.BadgesLeft:FindFirstChild("MutationGem"), "mutation gem")
assert(cards[3].plate.BadgesLeft.SizeChip.Label.Text == "HUGE" and cards[3].plate.BadgesLeft.SizeChip.BackgroundColor3 == S.Surface.Track, "size chip neutral")
-- badge caps: grid = 2 (Lock > Equipped > NEW)
local toggles = {}
local full = Card.new({ kind = "brainrot", name = realName, rarity = "Rare", income = 5, state = { locked = true, equipped = 7, new = true }, lock = { onToggle = function(v) table.insert(toggles, v) end }, variant = "grid", parent = grid, layoutOrder = 20 })
local right = {}; for _, c in ipairs(full.plate.BadgesRight:GetChildren()) do if c:IsA("GuiObject") then table.insert(right, c.Name) end end
table.sort(right); assert(#right == 2 and right[1] == "Equipped" and right[2] == "Lock", "grid cap 2: " .. table.concat(right, ","))
assert(full.plate.BadgesRight.Equipped.Label.Text == "\u{2713}7", "pad number")
assert(full.plate.BadgesRight.Lock:IsA("TextButton") and full.plate.BadgesRight.Lock.Visible == true, "lock is a visible toggle when locked")
local hero = Card.new({ kind = "brainrot", name = realName, rarity = "Rare", income = 5, title = "Golden Huge Thing", state = { locked = true, equipped = true, new = true }, variant = "hero", parent = grid, layoutOrder = 21 })
local hr = 0; for _, c in ipairs(hero.plate.BadgesRight:GetChildren()) do if c:IsA("GuiObject") then hr += 1 end end
assert(hr == 3 and hero.plate:FindFirstChild("Title"), "hero cap 3 + title")
local compact = Card.new({ kind = "brainrot", name = realName, rarity = "Rare", mutation = "Golden", state = { equipped = true, new = true }, variant = "compact", parent = grid, layoutOrder = 22 })
local cr = 0; for _, c in ipairs(compact.plate.BadgesRight:GetChildren()) do if c:IsA("GuiObject") then cr += 1 end end
assert(cr == 1 and not compact.plate:FindFirstChild("BadgesLeft"), "compact cap 1, no left row")
-- unlocked + toggle on desktop: hidden until hover
local unlocked = Card.new({ kind = "brainrot", name = realName, rarity = "Rare", state = { locked = false }, lock = { onToggle = function() end }, variant = "grid", parent = grid, layoutOrder = 23 })
assert(unlocked.plate.BadgesRight.Lock.Visible == false, "desktop unlocked toggle hidden at rest")
-- selection + set/setState
full.setState({ selected = true }); assert(full.visual.SelectionRing.Visible == true, "ring on select")
full.setState({ selected = false, new = false, equipped = false }); assert(full.visual.SelectionRing.Visible == false and not full.plate.BadgesRight:FindFirstChild("Equipped"), "state repaint")
full.set({ income = 2500000, count = 3, sizeTag = "Massive" })
assert(full.plate.Rate.Label.Text == "$2.50M/s" and full.plate.Band.Count.Text == "x3" and full.plate.BadgesLeft.SizeChip.Label.Text == "MASSIVE", "set() repaint")
-- mount / unmount / fx cap
local before = Fx.count()
for _, c in ipairs(cards) do c.mount() end
task.wait()
for i, tier in ipairs(tiers) do assert(cards[i].isMounted() and cards[i].art:FindFirstChild("Preview"), tier .. " mounted a viewport") end
local expectedFx = 0; for _, tier in ipairs(tiers) do expectedFx += #S.Card.Ladder[S.Card.TIER_KEY[tier]].animated end
assert(Fx.count() - before == expectedFx and expectedFx == 7, "fx registrations = 1+2+2+2 = 7, got " .. (Fx.count() - before))
assert(Fx.isRunning(), "driver running")
for _, c in ipairs(cards) do c.unmount() end
assert(Fx.count() == before and not cards[6].art:FindFirstChild("Preview"), "unmount released viewports + fx")
-- missing art
local ghost = Card.new({ kind = "brainrot", name = "NoSuchBrainrot_XYZ", rarity = "Epic", income = 0, variant = "grid", parent = grid, layoutOrder = 24 })
ghost.mount(); assert(ghost.art:FindFirstChild("MissingArt") and ghost.plate.Edge.Color == S.Rarity.EPIC[2], "missing art keeps the rarity card")
-- unknown rarity falls back with a warning
local odd = Card.new({ kind = "brainrot", name = realName, rarity = "Divine", variant = "grid", parent = grid, layoutOrder = 25 })
assert(odd.plate.Edge.Color == S.Rarity.COM[2], "unknown rarity -> Common")
-- destroy
full.destroy(); assert(full.root.Parent == nil, "destroy")
sg.Parent = nil
assert(not Fx.isRunning(), "driver idle after teardown")
return "BrainrotCard OK"
```

Expected: `BrainrotCard OK`; console shows exactly one `unknown rarity "Divine"` warning.

- [ ] **Step 3: Mirror + commit.** → `game-src/place-full/ReplicatedStorage/Modules/UIKit/BrainrotCard.lua`; commit `feat(ui): BrainrotCard -- rarity-first dark well tile with badges, ladder fx and mount/unmount`.

---

### Task 10: `ViewportCuller`

**Files:**
- Create: `ReplicatedStorage.Modules.UIKit.ViewportCuller` (ModuleScript)

**Interfaces:**
- Consumes: `S.Card.MaxLive` (Task 2), `Platform.Class`, cards shaped `{ root: GuiObject, mount(), unmount(), isMounted(): boolean }` (Task 9).
- Produces: `ViewportCuller.attach(scroll: ScrollingFrame, cards, opts?: { margin?, maxLive?, budgetMs?, budgetFrames?, floor? }) → { refresh(), setCards(list), detach(), isDetached(), live(): number, cap(): number }`, `ViewportCuller.defaultCap(): number`, `ViewportCuller.planPass(rects, viewTop, viewH, margin, cap) → { mount: {i}, unmount: {i} }` (pure; unit-tested).

- [ ] **Step 1: Create the module.** `multi_edit` (`className = "ModuleScript"`, `old_string = ""`):

```lua
--!strict
-- ViewportCuller -- mounts only the cards inside a ScrollingFrame's viewport (spec
-- 2026-09-18 UI foundation §8.3, handoff §20 "only render visible cards"). Lifted from
-- IndexPanel.updateVisible: decide from each card's REAL on-screen rectangle against
-- the scroll's rectangle (± margin), never from row maths that can drift from the
-- layout. Nearest-to-centre first under a live cap that is per-platform
-- (S.Card.MaxLive, replaced by the Gallery stress test) and ADAPTIVE: if Heartbeat
-- stays over budget for budgetFrames consecutive frames while cards are mounted, the
-- cap steps down 25% (floor 12) and does not climb back within one attach.
local RunService = game:GetService("RunService")
local S = require(script.Parent.SpecTheme)
local Platform = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Platform"))

export type Cullable = { root: GuiObject, mount: () -> (), unmount: () -> (), isMounted: () -> boolean }
export type Options = { margin: number?, maxLive: number?, budgetMs: number?, budgetFrames: number?, floor: number? }
export type Rect = { y: number, h: number }
export type Handle = {
	refresh: () -> (), setCards: (cards: { Cullable }) -> (), detach: () -> (),
	isDetached: () -> boolean, live: () -> number, cap: () -> number,
}

local ViewportCuller = {}

function ViewportCuller.defaultCap(): number
	local caps = S.Card.MaxLive
	local class = Platform.Class
	if class == "Console" then class = "Desktop" end
	return caps[class] or caps.Desktop
end

--- Pure planning step: which indices to mount (nearest-to-centre first, up to cap)
--- and which to unmount. rects are card rectangles in the same space as viewTop.
function ViewportCuller.planPass(rects: { Rect }, viewTop: number, viewH: number, margin: number, cap: number): { mount: { number }, unmount: { number } }
	local m = viewH * margin
	local centre = viewTop + viewH * 0.5
	local wanted: { { i: number, d: number } } = {}
	local unmount: { number } = {}
	for i, r in ipairs(rects) do
		local rel = r.y - viewTop
		if rel < viewH + m and rel + r.h > -m then
			table.insert(wanted, { i = i, d = math.abs((r.y + r.h * 0.5) - centre) })
		else
			table.insert(unmount, i)
		end
	end
	table.sort(wanted, function(a, b) return a.d < b.d end)
	local mount: { number } = {}
	for k, w in ipairs(wanted) do
		if k <= cap then table.insert(mount, w.i) else table.insert(unmount, w.i) end
	end
	return { mount = mount, unmount = unmount }
end

function ViewportCuller.attach(scroll: ScrollingFrame, cards: { Cullable }, opts: Options?): Handle
	local o: Options = opts or {}
	local margin = o.margin or 0.5
	local budgetMs = o.budgetMs or 22
	local budgetFrames = o.budgetFrames or 30
	local floorCap = o.floor or 12
	local cap = o.maxLive or ViewportCuller.defaultCap()
	local items = cards
	local pending = false
	local detached = false
	local over = 0
	local mountedCount = 0
	local conns: { RBXScriptConnection } = {}

	local function pass()
		pending = false
		if detached then return end
		local viewH = scroll.AbsoluteSize.Y
		if viewH <= 0 then return end
		local top = scroll.AbsolutePosition.Y
		local rects: { Rect } = {}
		local alive: { Cullable } = {}
		for _, c in ipairs(items) do
			local r = c.root
			if r.Parent then
				table.insert(alive, c)
				table.insert(rects, { y = r.AbsolutePosition.Y, h = r.AbsoluteSize.Y })
			elseif c.isMounted() then
				c.unmount()
			end
		end
		local plan = ViewportCuller.planPass(rects, top, viewH, margin, cap)
		for _, i in ipairs(plan.unmount) do
			local c = alive[i]
			if c.isMounted() then c.unmount() end
		end
		local live = 0
		for _, i in ipairs(plan.mount) do
			local c = alive[i]
			if not c.isMounted() then
				local ok, err = pcall(c.mount)
				if not ok then
					warn(("[UIKit] ViewportCuller: mount failed for %s: %s\n%s"):format(c.root:GetFullName(), tostring(err), debug.traceback()))
				end
			end
			if c.isMounted() then live += 1 end
		end
		mountedCount = live
		-- published for cross-VM probes (execute_luau cannot reach this closure)
		scroll:SetAttribute("CullerLive", live)
		scroll:SetAttribute("CullerCap", cap)
	end

	local function schedule()
		if pending or detached then return end
		pending = true
		task.defer(pass) -- coalesce: one pass per frame however many signals fire
	end

	table.insert(conns, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(schedule))
	table.insert(conns, scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule))
	table.insert(conns, scroll:GetPropertyChangedSignal("AbsolutePosition"):Connect(schedule))
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if mountedCount == 0 then
			over = 0
			return
		end
		if dt * 1000 > budgetMs then
			over += 1
			if over >= budgetFrames then
				over = 0
				local newCap = math.max(floorCap, math.floor(cap * 0.75))
				if newCap < cap then
					warn(("[UIKit] ViewportCuller: %d frames over %dms with %d live viewports -- cap %d -> %d (last dt %.1fms)"):format(budgetFrames, budgetMs, mountedCount, cap, newCap, dt * 1000))
					cap = newCap
					schedule()
				end
			end
		else
			over = 0
		end
	end))
	schedule()

	local handle: Handle = {
		refresh = schedule,
		setCards = function(list: { Cullable })
			-- cards dropped from the working set must not stay mounted forever
			local keep: { [Cullable]: boolean } = {}
			for _, c in ipairs(list) do keep[c] = true end
			for _, c in ipairs(items) do
				if not keep[c] and c.isMounted() then c.unmount() end
			end
			items = list
			schedule()
		end,
		detach = function()
			if detached then return end
			detached = true
			for _, c in ipairs(conns) do c:Disconnect() end
			table.clear(conns)
			for _, c in ipairs(items) do
				if c.isMounted() then c.unmount() end
			end
			mountedCount = 0
			if scroll.Parent then
				scroll:SetAttribute("CullerLive", 0)
				scroll:SetAttribute("CullerDetached", true)
			end
		end,
		isDetached = function() return detached end,
		live = function() return mountedCount end,
		cap = function() return cap end,
	}
	return handle
end

return ViewportCuller
```

- [ ] **Step 2: Compile-gate + tests (pure planner, then a real scroll of 120 cards).** `execute_luau` (Edit):

```lua
-- [TEST LOADER PREAMBLE from .superpowers/sdd/2026-09-18-ui-foundation/test-loader.lua goes here]
local f, e = loadstring(RS.Modules.UIKit.ViewportCuller.Source); assert(f, e)
local S, VC, Card, Fx = load(kit.SpecTheme), load(kit.ViewportCuller), load(kit.BrainrotCard), load(kit.FxDriver)
-- pure planner
local rects = {}; for i = 1, 20 do rects[i] = { y = (i - 1) * 100, h = 100 } end
local plan = VC.planPass(rects, 300, 400, 0.5, 4)   -- viewport 300..700, margin 200 -> visible rows 2..9
assert(#plan.mount == 4, "cap respected: " .. #plan.mount)
assert(plan.mount[1] == 5 or plan.mount[1] == 6, "nearest-to-centre first (centre 500 -> rows 5/6)")
local unm = {}; for _, i in ipairs(plan.unmount) do unm[i] = true end
assert(unm[1] and unm[20] and unm[12], "far rows unmounted")
assert(#plan.mount + #plan.unmount == 20, "every card planned")
assert(VC.defaultCap() == S.Card.MaxLive.Desktop, "default cap from platform")
-- real scroll
local sg = Instance.new("ScreenGui"); sg.Name = "UIKitScratch"; sg.Parent = CoreGui
local scroll = Instance.new("ScrollingFrame"); scroll.Size = UDim2.fromOffset(880, 300); scroll.CanvasSize = UDim2.new(); scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scroll.Parent = sg
local gl = Instance.new("UIGridLayout"); gl.CellSize = UDim2.fromOffset(100, 132); gl.CellPadding = UDim2.fromOffset(8, 8); gl.SortOrder = Enum.SortOrder.LayoutOrder; gl.Parent = scroll
local realName = RS.BrainrotModels:GetChildren()[1].Name
local cards = {}
for i = 1, 120 do cards[i] = Card.new({ kind = "brainrot", name = realName, rarity = "Rare", income = i, variant = "grid", parent = scroll, layoutOrder = i }) end
local culler = VC.attach(scroll, cards, { maxLive = 24, margin = 0.5 })
task.wait(0.1)
local function mountedCount() local n = 0; for _, c in ipairs(cards) do if c.isMounted() then n += 1 end end return n end
assert(culler.live() == mountedCount() and culler.live() <= 24 and culler.live() > 0, "top: live=" .. culler.live())
assert(cards[1].isMounted() and not cards[120].isMounted(), "top rows mounted, bottom not")
scroll.CanvasPosition = Vector2.new(0, 99999)
task.wait(0.1)
assert(cards[120].isMounted() and not cards[1].isMounted() and culler.live() <= 24, "bottom after scroll, live=" .. culler.live())
scroll.CanvasPosition = Vector2.new(0, 0)
task.wait(0.1)
assert(cards[1].isMounted() and not cards[120].isMounted(), "back to top")
-- setCards swaps the working set
culler.setCards({ cards[1], cards[2] }); task.wait(0.1)
assert(mountedCount() == 2, "setCards unmounts the rest: " .. mountedCount())
culler.setCards(cards); task.wait(0.1)
culler.detach()
assert(culler.isDetached() and mountedCount() == 0 and culler.live() == 0, "detach unmounts everything")
scroll.CanvasPosition = Vector2.new(0, 500); task.wait(0.1)
assert(mountedCount() == 0, "detached culler ignores scroll")
for _, c in ipairs(cards) do c.destroy() end
sg.Parent = nil
assert(not Fx.isRunning(), "driver idle")
return "ViewportCuller OK"
```

Expected: `ViewportCuller OK`.

- [ ] **Step 3: Mirror + commit.** → `game-src/place-full/ReplicatedStorage/Modules/UIKit/ViewportCuller.lua`; commit `feat(ui): ViewportCuller -- scroll-visibility mount/unmount with per-platform adaptive cap`.

---

### Task 11: `GalleryPanel` (Studio-only living style guide) + trigger + stress test → `S.Card.MaxLive`

**Files:**
- Create: `StarterPlayer.StarterPlayerScripts.GameHUDPanels.GalleryPanel` (ModuleScript)
- Modify: `StarterPlayer.StarterPlayerScripts.GameHUDClient` (after the registration loop; `closePanel` and the host-Visible watcher)
- Modify: `ReplicatedStorage.Modules.UIKit.SpecTheme` (`S.Card.MaxLive` values, from measurements)

**Interfaces:**
- Consumes: everything from Tasks 2–10, `ctx = { host, openPanel, closePanel, ... }` from GameHUDClient, `BrainrotThumb.framingBox`.
- Produces: `GalleryPanel = { Id = "gallery", Build(ctx) → Frame }` in Studio, `{}` in the live game; trigger `Players.LocalPlayer:SetAttribute("HudGallery", true)`; measured `S.Card.MaxLive`.

- [ ] **Step 1: Create the module.** `multi_edit` (`file_path = "game.StarterPlayer.StarterPlayerScripts.GameHUDPanels.GalleryPanel"`, `className = "ModuleScript"`, `old_string = ""`):

```lua
--!strict
-- GalleryPanel -- STUDIO-ONLY living style guide (spec 2026-09-18 UI foundation
-- §10). Every kit component in every state, the BrainrotCard ladder, the framing
-- extremes with their measured fill, and a stress grid on the culler that SETS
-- S.Card.MaxLive per platform. Everything here is built from S + the components --
-- no bespoke styling -- so what the Gallery shows IS the design system.
-- Registration: outside Studio this module returns {} and GameHUDClient skips it
-- (documented "not registered here" answer). No rail button; trigger from the
-- client command bar:  game.Players.LocalPlayer:SetAttribute("HudGallery", true)
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return {}
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local modules = ReplicatedStorage:WaitForChild("Modules")
local UIKit = modules:WaitForChild("UIKit")
local S = require(UIKit:WaitForChild("SpecTheme"))
local PC = require(UIKit:WaitForChild("PanelChrome"))
local TabBar = require(UIKit:WaitForChild("TabBar"))
local SearchBar = require(UIKit:WaitForChild("SearchBar"))
local SortButton = require(UIKit:WaitForChild("SortButton"))
local Modal = require(UIKit:WaitForChild("Modal"))
local Toast = require(UIKit:WaitForChild("Toast"))
local BrainrotCard = require(UIKit:WaitForChild("BrainrotCard"))
local ViewportCuller = require(UIKit:WaitForChild("ViewportCuller"))
local FxDriver = require(UIKit:WaitForChild("FxDriver"))
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))
local Platform = require(modules:WaitForChild("Platform"))

local GalleryPanel = { Id = "gallery" }

local SECTIONS = {
	{ id = "tokens", text = "TOKENS" }, { id = "buttons", text = "BUTTONS" }, { id = "shell", text = "SHELL" },
	{ id = "tabs", text = "TABS" }, { id = "inputs", text = "INPUTS" }, { id = "modal", text = "MODAL+TOAST" },
	{ id = "cards", text = "CARDS" }, { id = "stress", text = "STRESS" }, { id = "legacy", text = "LEGACY" },
}
local TIERS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "God" }
local CARD_W, CARD_H = 140, 176

-- roster helpers -------------------------------------------------------------
local function rosterNames(n: number): { string }
	local names = {}
	for _, m in ipairs(ReplicatedStorage:WaitForChild("BrainrotModels"):GetChildren()) do
		if m:IsA("Model") then table.insert(names, m.Name) end
	end
	table.sort(names)
	local out = {}
	for i = 1, math.min(n, #names) do out[i] = names[i] end
	return out
end

-- the framing set: extremes picked by MEASUREMENT so the section never depends on
-- a hand-typed name (tallest, widest, biggest, smallest, palest, darkest)
local function framingSet(): { { label: string, name: string } }
	local best = { tall = -1, wide = -1, big = -1, small = math.huge, pale = -1, dark = math.huge }
	local pick: { [string]: string } = {}
	for _, m in ipairs(ReplicatedStorage.BrainrotModels:GetChildren()) do
		if m:IsA("Model") then
			local ok, _, ext = pcall(function() return m:GetBoundingBox() end)
			if ok and ext and ext.Magnitude > 0 then
				local tall, wide, vol = ext.Y / math.max(ext.X, ext.Z), math.max(ext.X, ext.Z) / ext.Y, ext.X * ext.Y * ext.Z
				if tall > best.tall then best.tall = tall; pick.tall = m.Name end
				if wide > best.wide then best.wide = wide; pick.wide = m.Name end
				if vol > best.big then best.big = vol; pick.big = m.Name end
				if vol < best.small then best.small = vol; pick.small = m.Name end
				local master = BrainrotThumb.master(m.Name)
				if master then
					local lum = BrainrotThumb.meanLuminance(master)
					if lum > best.pale then best.pale = lum; pick.pale = m.Name end
					if lum < best.dark then best.dark = lum; pick.dark = m.Name end
				end
			end
		end
	end
	local out = {}
	for _, key in ipairs({ "tall", "wide", "big", "small", "pale", "dark" }) do
		if pick[key] then table.insert(out, { label = key:upper(), name = pick[key] }) end
	end
	return out
end

-- measured fill + off-centre residual for a model at the card's aspect (Task 8 maths)
local function measureFill(name: string, aspect: number): (number, number, number)
	local master = BrainrotThumb.master(name)
	if not master then return 0, 0, 0 end
	local m = master
	local dir = m:GetPivot():VectorToWorldSpace(BrainrotThumb.DEFAULT_DIR)
	local yaw = BrainrotThumb.FACING[name]
	if yaw and yaw ~= 0 then dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(yaw)) * dir end
	local fov = 30
	local centre, dist = BrainrotThumb.framingBox(m, fov, { dir = dir, aspect = aspect, fill = S.Card.Fill })
	local look = -dir
	local right = look:Cross(Vector3.yAxis).Unit
	local up = right:Cross(look).Unit
	local tanV = math.tan(math.rad(fov * 0.5)); local tanH = tanV * aspect
	local cf, ext = m:GetBoundingBox()
	local maxAbs, minX, maxX, minY, maxY = 0, math.huge, -math.huge, math.huge, -math.huge
	for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
		local q = cf:PointToWorldSpace(Vector3.new(sx * ext.X / 2, sy * ext.Y / 2, sz * ext.Z / 2))
		local w = q - centre
		local depth = dist - w:Dot(dir)
		local px, py = w:Dot(right) / depth / tanH, w:Dot(up) / depth / tanV
		maxAbs = math.max(maxAbs, math.abs(px), math.abs(py))
		minX, maxX, minY, maxY = math.min(minX, px), math.max(maxX, px), math.min(minY, py), math.max(maxY, py)
	end end end
	return maxAbs, (minX + maxX) / 2, (minY + maxY) / 2
end

-- section helpers ------------------------------------------------------------
local function row(host: Instance, name: string, height: number?, order: number): Frame
	local r = Instance.new("Frame")
	r.Name = name
	r.BackgroundTransparency = 1
	r.Size = UDim2.new(1, 0, 0, height or 0)
	if not height then r.AutomaticSize = Enum.AutomaticSize.Y end
	r.LayoutOrder = order
	r.ZIndex = PC.zBase + 3
	r.Parent = host
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, S.Space.std)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Wraps = true
	l.Parent = r
	return r
end

local function heading(host: Instance, text: string, order: number)
	PC.sectionHead({ text = text, parent = host, zIndex = PC.zBase + 3, layoutOrder = order })
end

local function caption(parent: Instance, text: string, order: number?): TextLabel
	local l = PC.read({ text = text, size = S.TextSize.Meta, color = S.Surface.ReadSub, parent = parent, frameSize = UDim2.new(0, 0, 0, 28), zIndex = PC.zBase + 3 })
	l.AutomaticSize = Enum.AutomaticSize.X
	if order then l.LayoutOrder = order end
	return l
end

local function cardSlot(parent: Instance, order: number, label: string?): Frame
	-- a fixed cell so cards render at the Bag's proportions
	local holder = Instance.new("Frame")
	holder.Name = "Slot" .. order
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(CARD_W, CARD_H + (label and 26 or 0))
	holder.LayoutOrder = order
	holder.ZIndex = PC.zBase + 3
	holder.Parent = parent
	local cell = Instance.new("Frame")
	cell.Name = "Cell"
	cell.BackgroundTransparency = 1
	cell.Size = UDim2.fromOffset(CARD_W, CARD_H)
	cell.ZIndex = PC.zBase + 3
	cell.Parent = holder
	if label then
		local l = PC.read({ text = label, size = S.TextSize.Chip, color = S.Surface.ReadSub, parent = holder, frameSize = UDim2.new(1, 0, 0, 24), position = UDim2.fromOffset(0, CARD_H + 2), zIndex = PC.zBase + 3 })
		l.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return cell
end

------------------------------------------------------------------------ Build
function GalleryPanel.Build(ctx)
	local shell = PC.shell({
		name = "GalleryPanel", title = "UI GALLERY", key = "settings", size = Vector2.new(1600, 920),
		scroll = false, listLayout = false, icon = S.Art.settings,
		stat = { text = "Studio-only living style guide -- spec 2026-09-18-ui-foundation-design" },
	})
	shell.close.MouseButton1Click:Connect(function()
		if ctx.closePanel then ctx.closePanel() end
	end)
	local z = shell.z

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(200, 0)
	content.Size = UDim2.new(1, -200, 1, 0)
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 5
	content.ScrollBarImageColor3 = S.OutlineSoft
	content.ZIndex = z + 2
	content.Parent = shell.body

	-- per-section teardown: cards, cullers, driver entries, connections
	local live: { cards: { any }, cullers: { any }, conns: { RBXScriptConnection }, fx: { number } } = { cards = {}, cullers = {}, conns = {}, fx = {} }
	local function teardown()
		for _, c in ipairs(live.cullers) do c.detach() end
		for _, c in ipairs(live.cards) do c.destroy() end
		for _, c in ipairs(live.conns) do c:Disconnect() end
		for _, id in ipairs(live.fx) do FxDriver.unregister(id) end
		live = { cards = {}, cullers = {}, conns = {}, fx = {} }
		Modal.closeCurrent()
		for _, ch in ipairs(content:GetChildren()) do
			if ch:IsA("GuiObject") then ch:Destroy() end
		end
	end
	local function track(card) table.insert(live.cards, card) return card end

	local sections: { [string]: (host: Frame) -> () } = {}

	---------------------------------------------------------------- TOKENS
	sections.tokens = function(host)
		heading(host, "COLOUR ROLES (handoff §4)", 1)
		local r = row(host, "Roles", nil, 2)
		local roles = {
			{ "Positive", "equip / claim / confirm / teleport / buy with coins" }, { "Destructive", "delete / remove / close" },
			{ "Neutral", "utility, filters, sort, ACTIVE tab" }, { "Gold", "coins, rewards, value, prices" },
			{ "Purple", "gems, premium" }, { "Disabled", "inactive tabs, secondary chips" }, { "DisabledButton", "a disabled button" },
		}
		for i, spec in ipairs(roles) do
			local ramp = S.Role[spec[1]]
			local sw = PC.plate({ name = spec[1], size = UDim2.fromOffset(200, 110), colors = ramp, radius = 18, outline = 4, zIndex = z + 3, parent = r, layoutOrder = i })
			PC.shout({ text = spec[1]:upper(), size = 22, parent = sw, frameSize = UDim2.new(1, 0, 0, 40), zIndex = z + 5, scaled = true })
			local c = PC.read({ text = spec[2], size = 16, color = S.Surface.ReadInk, parent = sw, frameSize = UDim2.new(1, -12, 0, 56), position = UDim2.fromOffset(6, 44), zIndex = z + 5 })
			c.TextWrapped = true
			c.TextColor3 = Color3.new(1, 1, 1)
		end
		local selRow = row(host, "Selection", 40, 3)
		local sel = PC.plate({ name = "Selection", size = UDim2.fromOffset(200, 36), colors = { S.Role.Selection, S.Role.Selection }, radius = 12, outline = 3, zIndex = z + 3, parent = selRow, gloss = false })
		PC.shout({ text = "SELECTION RING", size = 18, parent = sel, zIndex = z + 5 })
		heading(host, "SPACING (handoff §16)", 4)
		local sp = row(host, "Spacing", 60, 5)
		for i, key in ipairs({ "micro", "small", "std", "section", "large" }) do
			local v = S.Space[key]
			local bar = PC.plate({ name = key, size = UDim2.fromOffset(v * 4, 40), colors = S.Role.Neutral, radius = 8, outline = 2, zIndex = z + 3, parent = sp, layoutOrder = i, gloss = false })
			PC.shout({ text = ("%s %d"):format(key, v), size = 16, parent = bar, zIndex = z + 5, scaled = true })
		end
		heading(host, "TYPE", 6)
		local ty = row(host, "Type", nil, 7)
		for i, key in ipairs({ "PanelTitle", "HeroAction", "SectionHead", "RowTitle", "Cta", "RowSub", "Meta", "Chip" }) do
			local sz = S.TextSize[key]
			local l = PC.shout({ text = ("%s %d"):format(key, sz), size = sz, color = S.Role.Neutral[2], strokeColor = Color3.new(1, 1, 1), parent = ty, frameSize = UDim2.fromOffset(0, sz + 12), zIndex = z + 3 })
			l.AutomaticSize = Enum.AutomaticSize.X
			l.LayoutOrder = i
		end
	end

	---------------------------------------------------------------- BUTTONS
	sections.buttons = function(host)
		local kinds = { "positive", "neutral", "destructive", "gold", "purple", "secondary" }
		heading(host, "KINDS -- normal / disabled / busy", 1)
		for i, kind in ipairs(kinds) do
			local r = row(host, kind, 90, 1 + i)
			PC.button({ kind = kind, text = kind:upper(), parent = r, zIndex = z + 3, layoutOrder = 1 })
			local d = PC.button({ kind = kind, text = "DISABLED", parent = r, zIndex = z + 3, layoutOrder = 2 })
			PC.setEnabled(d, false)
			local b = PC.button({ kind = kind, text = "BUSY", parent = r, zIndex = z + 3, layoutOrder = 3 })
			PC.setBusy(b, true, { timeout = 3600 })
			PC.button({ kind = kind, text = "SMALL", size = "small", parent = r, zIndex = z + 3, layoutOrder = 4 })
			PC.button({ kind = kind, text = "ICON", icon = S.Art.bag, parent = r, zIndex = z + 3, layoutOrder = 5 })
		end
		heading(host, "BUSY ROUND TRIP -- click to go busy for 2s (timeout 3s warns if a reply never came)", 10)
		local r = row(host, "BusyTrip", 90, 11)
		local trip: TextButton
		trip = PC.button({ kind = "positive", text = "EQUIP BEST", parent = r, zIndex = z + 3, onActivated = function()
			PC.setBusy(trip, true, { timeout = 3 })
			task.delay(2, function() PC.setBusy(trip, false) end)
		end })
		local lost: TextButton
		lost = PC.button({ kind = "gold", text = "LOST REPLY", parent = r, zIndex = z + 3, onActivated = function()
			PC.setBusy(lost, true, { timeout = 3 })
		end })
	end

	---------------------------------------------------------------- SHELL
	sections.shell = function(host)
		heading(host, "SHELL SLOTS -- stat, primary action, footer (destructive on the right)", 1)
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, 0, 0, 640)
		holder.LayoutOrder = 2
		holder.ZIndex = z + 3
		holder.Parent = host
		local mini = PC.shell({
			name = "MiniShell", title = "BAG", key = "bag", size = Vector2.new(1100, 600), parent = holder, zIndex = z + 4,
			icon = S.Art.bag, stat = { text = "16/16 equipped  ·  $1.2M/s", icon = S.Art.shop },
			primaryAction = { kind = "positive", text = "EQUIP BEST", onActivated = function() Toast.show({ text = "EQUIP BEST pressed", tone = "success" }) end },
		})
		mini.root.Position = UDim2.fromScale(0.5, 0.5)
		mini.close:SetAttribute("SfxMuted", true)
		mini.addFooter({
			left = { { text = "HIDE PLOT", kind = "secondary" }, { text = "LOCK ALL", kind = "neutral" }, { text = "MULTI-SELECT", kind = "neutral" } },
			right = { { text = "DELETE", kind = "destructive", onActivated = function()
				Modal.confirm({ title = "DELETE 3 BRAINROTS?", body = "They go back into the wild. This cannot be undone.", loss = "You will lose $12.4K/s of income.", confirmText = "DELETE",
					onConfirm = function() Toast.show({ text = "Deleted (demo)", tone = "error" }) end })
			end } },
		})
		for i = 1, 3 do
			PC.row({ title = "Row " .. i, subtitle = "a PanelChrome.row inside the body", parent = mini.body, zIndex = z + 5, layoutOrder = i })
		end
	end

	---------------------------------------------------------------- TABS
	sections.tabs = function(host)
		heading(host, "HORIZONTAL TABBAR (quests) -- with a badge", 1)
		local r1 = row(host, "Horizontal", 90, 2)
		local hz = TabBar.new({ tabs = { { id = "main", text = "MAIN" }, { id = "daily", text = "DAILY" }, { id = "event", text = "EVENT", icon = S.Art.goals }, { id = "done", text = "COMPLETED" } }, selected = "main", parent = r1, zIndex = z + 3, onChanged = function(id) Toast.show({ text = "tab: " .. id }) end })
		hz.setBadge("daily", 2)
		heading(host, "VERTICAL TABBAR (bag categories)", 3)
		local r2 = row(host, "Vertical", 480, 4)
		TabBar.new({ orientation = "vertical", width = 140, tabs = { { id = "brainrots", text = "BRAINROTS", icon = S.Art.bag }, { id = "pets", text = "PETS", icon = S.Art.rebirth }, { id = "charms", text = "CHARMS", icon = S.Art.goals }, { id = "keys", text = "KEYS", icon = S.Art.worlds }, { id = "tags", text = "TAGS", icon = S.Art.shop }, { id = "index", text = "INDEX", icon = S.Art.settings } }, selected = "brainrots", parent = r2, zIndex = z + 3, onChanged = function() end })
		heading(host, "HEADER TABS (senior level, PanelChrome.addHeaderTabs)", 5)
		local r3 = row(host, "Header", 100, 6)
		local mini = PC.shell({ name = "TabShell", title = "PROGRESS", key = "goals", size = Vector2.new(900, 90), parent = r3, zIndex = z + 4, scroll = false })
		mini.root.Position = UDim2.fromScale(0, 0)
		mini.root.AnchorPoint = Vector2.new(0, 0)
		mini.root.Size = UDim2.fromOffset(900, 90)
		mini.body.Visible = false
		mini.close:SetAttribute("SfxMuted", true)
		mini.addHeaderTabs({ { text = "GOALS", width = 180 }, { text = "SEASON PASS", width = 240 } }, 1, function() end)
	end

	---------------------------------------------------------------- INPUTS
	sections.inputs = function(host)
		heading(host, "SEARCH + SORT (bag sizes: 36px) and kit sizes (64px)", 1)
		local r1 = row(host, "Small", 60, 2)
		local echo = caption(r1, "query: (none)  sort: rarity", 3)
		local q, srt = "", "rarity"
		local function paintEcho() echo.Text = ("query: %s  sort: %s"):format(q == "" and "(none)" or q, srt) end
		SearchBar.new({ placeholder = "SEARCH...", width = 240, height = 36, parent = r1, zIndex = z + 3, layoutOrder = 1, onChanged = function(v) q = v; paintEcho() end })
		SortButton.new({ modes = { { id = "rarity", label = "RARITY" }, { id = "newest", label = "NEWEST" }, { id = "az", label = "A-Z" } }, selected = "rarity", height = 36, width = 3 * 96 + 24, parent = r1, zIndex = z + 3, layoutOrder = 2, onChanged = function(id) srt = id; paintEcho() end })
		local r2 = row(host, "Large", 90, 3)
		SearchBar.new({ placeholder = "SEARCH BRAINROTS...", width = 420, parent = r2, zIndex = z + 3, layoutOrder = 1, onChanged = function() end })
		SortButton.new({ modes = { { id = "rarity", label = "RARITY" }, { id = "newest", label = "NEWEST" }, { id = "az", label = "A-Z" } }, selected = "newest", parent = r2, zIndex = z + 3, layoutOrder = 2, onChanged = function() end })
		heading(host, "SEGMENTED / TOGGLE / SLIDER / BAR (existing PanelChrome parts)", 4)
		local r3 = row(host, "Parts", 100, 5)
		PC.segmented({ options = { "LOW", "MED", "HIGH" }, selected = 2, size = UDim2.fromOffset(420, 64), parent = r3, zIndex = z + 3 })
		PC.toggle({ parent = r3, zIndex = z + 3, on = true, onChanged = function() end })
		local r4 = row(host, "Slider", 100, 6)
		PC.slider({ size = UDim2.fromOffset(420, 60), parent = r4, zIndex = z + 3, value = 0.6, onChanged = function() end })
		local r5 = row(host, "Bar", 80, 7)
		local bar = PC.bar({ size = UDim2.fromOffset(420, S.Chrome.TrackHeight), parent = r5, zIndex = z + 3, label = "10 / 16" })
		bar.set(0.62)
	end

	---------------------------------------------------------------- MODAL + TOAST
	sections.modal = function(host)
		heading(host, "CONFIRMATION MODAL (dangerous actions only)", 1)
		local r = row(host, "Modals", 90, 2)
		PC.button({ kind = "destructive", text = "DELETE (cancelable)", parent = r, zIndex = z + 3, onActivated = function()
			Modal.confirm({ title = "DELETE 3 BRAINROTS?", body = "They go back into the wild. This cannot be undone.", loss = "You will lose $12.4K/s of income.", confirmText = "DELETE",
				onConfirm = function() Toast.show({ text = "Confirmed", tone = "error" }) end, onCancel = function() Toast.show({ text = "Cancelled" }) end })
		end })
		PC.button({ kind = "positive", text = "REBIRTH (not cancelable)", parent = r, zIndex = z + 3, onActivated = function()
			Modal.confirm({ title = "REBIRTH NOW?", body = "Cash resets. Brainrots stay. Multiplier +15%.", confirmText = "REBIRTH", confirmKind = "positive", cancelable = false,
				onConfirm = function() Toast.show({ text = "Reborn (demo)", tone = "reward" }) end })
		end })
		heading(host, "TOAST TONES", 3)
		local r2 = row(host, "Toasts", 90, 4)
		for i, tone in ipairs({ "info", "success", "error", "reward" }) do
			PC.button({ kind = if tone == "error" then "destructive" elseif tone == "reward" then "gold" elseif tone == "success" then "positive" else "neutral", text = tone:upper(), parent = r2, zIndex = z + 3, layoutOrder = i, onActivated = function()
				Toast.show({ text = ("A %s toast that is long enough to wrap on a phone, so the whole sentence still shows."):format(tone), tone = tone })
			end })
		end
	end

	---------------------------------------------------------------- CARDS
	sections.cards = function(host)
		local names = rosterNames(8)
		heading(host, "RARITY LADDER (grid variant)", 1)
		local r1 = row(host, "Ladder", nil, 2)
		for i, tier in ipairs(TIERS) do
			local cell = cardSlot(r1, i, tier)
			track(BrainrotCard.new({ kind = "brainrot", name = names[i] or names[1], rarity = tier, income = 10 ^ i, variant = "grid", parent = cell, zIndex = z + 3 })).mount()
		end
		heading(host, "STATES -- badges never overpower the rarity", 3)
		local r2 = row(host, "States", nil, 4)
		local n = names[3] or names[1]
		local states = {
			{ "locked", { locked = true } }, { "equipped #7", { equipped = 7 } }, { "new", { new = true } }, { "selected", { selected = true } },
			{ "all three (cap 2)", { locked = true, equipped = 3, new = true } },
		}
		for i, st in ipairs(states) do
			local cell = cardSlot(r2, i, st[1])
			track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Legendary", income = 9500, state = st[2], lock = { onToggle = function(v) Toast.show({ text = "lock -> " .. tostring(v) }) end }, variant = "grid", parent = cell, zIndex = z + 3 })).mount()
		end
		local cellM = cardSlot(r2, 6, "Golden Huge x3")
		track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Epic", income = 1800, mutation = "Golden", mutationColor = Color3.fromRGB(255, 215, 60), sizeTag = "Huge", count = 3, variant = "grid", parent = cellM, zIndex = z + 3 })).mount()
		local cellG = cardSlot(r2, 7, "missing art")
		track(BrainrotCard.new({ kind = "brainrot", name = "NoSuchBrainrot_Gallery", rarity = "Rare", income = 0, variant = "grid", parent = cellG, zIndex = z + 3 })).mount()
		heading(host, "VARIANTS -- compact / grid / hero", 5)
		local r3 = row(host, "Variants", nil, 6)
		local cc = Instance.new("Frame"); cc.BackgroundTransparency = 1; cc.Size = UDim2.fromOffset(100, 110); cc.LayoutOrder = 1; cc.Parent = r3
		track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Mythic", income = 62000, mutation = "Diamond", mutationColor = Color3.fromRGB(120, 230, 255), state = { equipped = true }, variant = "compact", parent = cc, zIndex = z + 3 })).mount()
		local cg = Instance.new("Frame"); cg.BackgroundTransparency = 1; cg.Size = UDim2.fromOffset(CARD_W, CARD_H); cg.LayoutOrder = 2; cg.Parent = r3
		track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Mythic", income = 62000, mutation = "Diamond", mutationColor = Color3.fromRGB(120, 230, 255), state = { equipped = true }, variant = "grid", parent = cg, zIndex = z + 3 })).mount()
		local ch = Instance.new("Frame"); ch.BackgroundTransparency = 1; ch.Size = UDim2.fromOffset(300, 380); ch.LayoutOrder = 3; ch.Parent = r3
		track(BrainrotCard.new({ kind = "brainrot", name = n, rarity = "Secret", income = 410000, title = "Diamond " .. n, mutation = "Diamond", mutationColor = Color3.fromRGB(120, 230, 255), state = { equipped = true, new = true }, variant = "hero", parent = ch, zIndex = z + 3 })).mount()
		heading(host, ("FRAMING SET -- projected fill target %.2f (spec §8.1); label = measured fill / off-centre"):format(S.Card.Fill), 7)
		local r4 = row(host, "Framing", nil, 8)
		local aspect = (CARD_W - 2 * S.Card.ArtInset) / (CARD_H * (1 - S.Card.BandFrac) - S.Card.ArtInset - 8)
		for i, pick in ipairs(framingSet()) do
			local fill, mx, my = measureFill(pick.name, aspect)
			local cell = cardSlot(r4, i, ("%s %s  fill %.2f  off (%.2f,%.2f)"):format(pick.label, pick.name, fill, mx, my))
			track(BrainrotCard.new({ kind = "brainrot", name = pick.name, rarity = "Rare", income = 100, variant = "grid", parent = cell, zIndex = z + 3 })).mount()
		end
	end

	---------------------------------------------------------------- STRESS
	sections.stress = function(host)
		heading(host, "STRESS -- N cards on ViewportCuller; readout sets S.Card.MaxLive per platform", 1)
		local controls = row(host, "Controls", 90, 2)
		local readout = caption(host, "not running", 3)
		readout.Size = UDim2.new(1, 0, 0, 28)
		local grid = Instance.new("ScrollingFrame")
		grid.Name = "StressGrid"
		grid.BackgroundColor3 = S.Surface.Body
		grid.BorderSizePixel = 0
		grid.Size = UDim2.new(1, 0, 0, 520)
		grid.LayoutOrder = 4
		grid.CanvasSize = UDim2.new()
		grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
		grid.ScrollBarThickness = 5
		grid.ZIndex = z + 3
		grid.Parent = host
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(100, 132)
		gl.CellPadding = UDim2.fromOffset(8, 8)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = grid
		local names = rosterNames(24)
		local count, cap = 100, ViewportCuller.defaultCap()
		local culler = nil
		local samples, sIdx = {}, 0
		local function rebuild()
			if culler then culler.detach() culler = nil end
			for _, c in ipairs(live.cards) do c.destroy() end
			live.cards = {}
			for i = 1, count do
				local card = BrainrotCard.new({ kind = "brainrot", name = names[(i - 1) % #names + 1], rarity = TIERS[(i - 1) % 8 + 1], income = i * 10, variant = "grid", parent = grid, zIndex = z + 3, layoutOrder = i })
				table.insert(live.cards, card)
			end
			culler = ViewportCuller.attach(grid, live.cards, { maxLive = cap })
			table.insert(live.cullers, culler)
		end
		for _, nOpt in ipairs({ 100, 250, 500 }) do
			PC.button({ kind = "neutral", text = "N=" .. nOpt, size = "small", parent = controls, zIndex = z + 3, onActivated = function() count = nOpt; rebuild() end })
		end
		for _, cOpt in ipairs({ 24, 48, 72, 96 }) do
			PC.button({ kind = "gold", text = "CAP " .. cOpt, size = "small", parent = controls, zIndex = z + 3, onActivated = function() cap = cOpt; rebuild() end })
		end
		PC.button({ kind = "secondary", text = "AUTO-SCROLL", size = "small", parent = controls, zIndex = z + 3, onActivated = function()
			task.spawn(function()
				local maxY = math.max(0, grid.AbsoluteCanvasSize.Y - grid.AbsoluteSize.Y)
				for step = 0, 40 do
					grid.CanvasPosition = Vector2.new(0, maxY * (step / 40))
					task.wait(0.05)
				end
				grid.CanvasPosition = Vector2.new(0, maxY * 0.5)
			end)
		end })
		table.insert(live.fx, FxDriver.register(readout, function(_, dt)
			sIdx = sIdx % 30 + 1
			samples[sIdx] = dt
			local sum, n = 0, 0
			for _, v in ipairs(samples) do sum += v; n += 1 end
			local avg = n > 0 and (sum / n) * 1000 or 0
			readout.Text = ("%s  N=%d  cap=%d  live=%d  avg dt=%.1fms  fx=%d  platform=%s"):format(culler and "running" or "idle", count, culler and culler.cap() or cap, culler and culler.live() or 0, avg, FxDriver.count(), Platform.Class)
		end))
		rebuild()
	end

	---------------------------------------------------------------- LEGACY
	sections.legacy = function(host)
		heading(host, "OLD vs NEW -- migration audit", 1)
		local r = row(host, "Buttons", 90, 2)
		PC.pill({ text = "OLD PILL (Go)", colors = S.Action.Go, size = UDim2.fromOffset(230, 76), parent = r, zIndex = z + 3 })
		PC.button({ kind = "positive", text = "NEW BUTTON", parent = r, zIndex = z + 3 })
		PC.pill({ text = "OLD NEUTRAL", colors = S.Action.Neutral, size = UDim2.fromOffset(230, 76), parent = r, zIndex = z + 3 })
		PC.button({ kind = "neutral", text = "NEW NEUTRAL", parent = r, zIndex = z + 3 })
		caption(host, "Old pills keep their values as aliases; kit consumers read S.Role.", 3)
	end

	---------------------------------------------------------------- navigation
	local currentSection = "tokens"
	local function showSection(id: string)
		teardown()
		currentSection = id
		local host = Instance.new("Frame")
		host.Name = "Section_" .. id
		host.BackgroundTransparency = 1
		host.Size = UDim2.new(1, -S.Space.std, 0, 0)
		host.AutomaticSize = Enum.AutomaticSize.Y
		host.ZIndex = z + 3
		host.Parent = content
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, S.Space.section)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = host
		content.CanvasPosition = Vector2.new(0, 0)
		local fn = sections[id]
		local ok, err = pcall(fn, host)
		if not ok then
			warn(("[UIKit] Gallery section %q failed: %s\n%s"):format(id, tostring(err), debug.traceback()))
			local tile = PC.plate({ name = "SectionError", size = UDim2.new(1, 0, 0, 160), colors = S.Role.Destructive, radius = 18, outline = 4, zIndex = z + 4, parent = host, gloss = false })
			local l = PC.read({ text = ("SECTION %s FAILED:\n%s"):format(id:upper(), tostring(err)), size = 18, color = Color3.new(1, 1, 1), parent = tile, frameSize = UDim2.new(1, -24, 1, -24), position = UDim2.fromOffset(12, 12), zIndex = z + 5 })
			l.TextWrapped = true
		end
	end

	local tabs = TabBar.new({ orientation = "vertical", width = 180, tabs = SECTIONS, selected = "tokens", parent = shell.body, zIndex = z + 3, onChanged = showSection })
	tabs.root.Position = UDim2.fromOffset(0, 0)

	-- panel hidden -> release everything (viewports, cullers, driver entries)
	shell.root:GetPropertyChangedSignal("Visible"):Connect(function()
		if shell.root.Visible then
			showSection(currentSection)
		else
			teardown()
		end
	end)
	showSection("tokens")
	return shell.root
end

return GalleryPanel
```

The existing-part calls above match the live signatures read at plan time: `PC.row{ title, subtitle, layoutOrder, parent, zIndex }`, `PC.toggle{ parent, zIndex, on, onChanged }`, `PC.slider{ size, parent, zIndex, value, onChanged }`, `PC.bar{ size, parent, zIndex, label } → { root, set }`, `PC.sectionHead{ text, parent, zIndex, layoutOrder }`, `PC.read{ …, wrap }`.

- [ ] **Step 2: Trigger + attribute clear in GameHUDClient.** Back up as `GameHUDClient_pre11`. `script_read` the registration loop tail (≈ 2680–2700), `closePanel` (≈ 2583–2600) and the host watcher (≈ 2718–2736). `multi_edit` with three edits:

Edit A — `old_string`:
```lua
			warn(("[UIKit] panel module %s did not return { Id, Build } (got %s)"):format(m.Name, typeof(mod)))
		end
	end
end
```
`new_string`:
```lua
			warn(("[UIKit] panel module %s did not return { Id, Build } (got %s)"):format(m.Name, typeof(mod)))
		end
	end
end

-- 2026-09-18 UI foundation (spec §10): the Studio-only Gallery has no rail button.
-- Trigger from the client command bar during Play:
--     game.Players.LocalPlayer:SetAttribute("HudGallery", true)
-- Player attributes never persist into the place file (unlike PlatformOverride).
player:GetAttributeChangedSignal("HudGallery"):Connect(function()
	if player:GetAttribute("HudGallery") ~= true then return end
	if panelModules["gallery"] then
		openPanel("gallery")
	else
		warn("[UIKit] gallery panel is not registered (Studio only)")
		player:SetAttribute("HudGallery", nil)
	end
end)
```

Edit B — `old_string`:
```lua
	state.screen = "none"
	currencyCluster.Visible = true
	if Platform.IsPhone then
```
`new_string`:
```lua
	state.screen = "none"
	player:SetAttribute("HudGallery", nil) -- re-arm the Studio-only Gallery trigger
	currencyCluster.Visible = true
	if Platform.IsPhone then
```

Edit C — `old_string`:
```lua
	currencyCluster.Visible = true
	updateActiveGlow()
end)
```
`new_string`:
```lua
	player:SetAttribute("HudGallery", nil)
	currencyCluster.Visible = true
	updateActiveGlow()
end)
```

- [ ] **Step 3: Compile-gate both.** `execute_luau` (Edit): `loadstring` on `GalleryPanel.Source` and `GameHUDClient.Source`; byte-scan for `HudGallery` (3 occurrences in GameHUDClient) and `sections.stress` in GalleryPanel. Also require the Gallery through a CoreGui clone of `GameHUDPanels` is NOT possible (it needs `ctx`); the live open is the test.

- [ ] **Step 4: Live open + every section.** `start_stop_play(true)`. `execute_luau` (Client): `game.Players.LocalPlayer:SetAttribute("HudGallery", true); task.wait(1); return game.Players.LocalPlayer:GetAttribute("HudOpenPanel")` → expected `gallery`. `get_console_output` → no `[UIKit]` warnings other than the intentional ones. Foreground Studio; for each section click `LocalPlayer.PlayerGui.GameHUD.<host path>.GalleryPanel.Body.TabBar.Tab<id>` via `user_mouse_input` (find the host path once with `execute_luau` Client: `return game.Players.LocalPlayer.PlayerGui:FindFirstChild("GalleryPanel", true):GetFullName()`), then `screen_capture` — nine captures, saved in the scratchpad with the section name. What to look for: Tokens (7 role swatches, blue Neutral, grey Disabled), Buttons (busy dots pulsing, disabled grey), Shell (stat line under BAG, EQUIP BEST left of the close, footer with DELETE alone on the right), Tabs (blue active, ring), Inputs, Modal (click DELETE → dark scrim, dialog, click CANCEL → toast "Cancelled"), Cards (8-tier ladder; badge caps; framing labels ≈ the current `S.Card.Fill` with off-centre ≤ 0.02; the pale and dark picks both visible on the navy plate), Stress (readout running), Legacy. Fix anything wrong in the Gallery or the component it exposes (component fixes re-run that task's test) before continuing.

- [ ] **Step 5: Stress measurements → `MaxLive`.** With the Gallery on the Stress section (desktop): for each cap in 24 / 48 / 72 / 96 at N=500, click the cap button, click AUTO-SCROLL, wait 3 s, read the readout (`execute_luau` Client: find the `Section_stress` frame's caption `TextLabel` whose text starts with `running` and return it). Record `avg dt` per cap. **Rule:** `MaxLive.Desktop` = the largest tested cap whose avg dt ≤ 16.7 ms (if even 24 exceeds it, 24 with a warning in the commit message). Then the phone: `start_stop_play(false)`, `execute_luau` (Edit) `game.ReplicatedStorage:SetAttribute("PlatformOverride", "Phone")`, `start_stop_play(true)`, open the Gallery, Stress, N=250, caps 12 / 24 / 32 / 48 (click CAP 24 / 48; for 12 and 32 use `execute_luau` Client to call the same rebuild through the buttons is not possible — instead read the adaptive step-down: with CAP 48 and AUTO-SCROLL, note whether the culler warned and where it settled). **Rule:** `MaxLive.Phone` = the largest cap with avg dt ≤ 22 ms; `MaxLive.Tablet` = the midpoint of Desktop and Phone rounded to 8. Stop Play, `execute_luau` (Edit) `game.ReplicatedStorage:SetAttribute("PlatformOverride", nil); return game.ReplicatedStorage:GetAttribute("PlatformOverride")` → expected `nil`.

- [ ] **Step 6: Write the measured caps and the card fill.** `script_read` the `MaxLive` and `Fill` lines in SpecTheme; `multi_edit` with two edits.

Edit A — `old_string`:
```lua
	-- PROVISIONAL (spec §8.3): the Gallery stress section replaces these numbers.
	MaxLive = { Desktop = 48, Tablet = 32, Phone = 20 },
```
`new_string` (with the measured numbers substituted):
```lua
	-- MEASURED 2026-09-18 in the Gallery stress section (N=500 desktop / N=250 phone
	-- via PlatformOverride, largest cap under 16.7ms / 22ms avg frame): see the
	-- round's commit message for the table.
	MaxLive = { Desktop = <D>, Tablet = <T>, Phone = <P> },
```

Edit B — the fill target is relative to the ART HOLDER (≈76 % of the card height once the band and insets are out), so the handoff's "65–75 % of the card" is a holder fill of ≈0.85–0.95; 0.70 of the holder read as small next to today's sphere-fit cards (Task 8 measured the box fit at 0.70 sitting the camera 14–29 % farther than the old sphere fit). `old_string`:
```lua
	Fill      = 0.70,           -- projected-box fill target (handoff §6: 65-75%)
```
`new_string`:
```lua
	Fill      = 0.88,           -- projected-box fill of the ART HOLDER (~76% of the card), i.e. ~67% of the card: handoff §6's 65-75%. 0.70 read small (Task 8/11, 2026-09-18)
```
Compile-gate. Re-open the Gallery's Cards section once more and confirm the framing labels now print ≈0.88 and the ladder row's models fill their cards without touching the edge.

- [ ] **Step 7: Mirror + commit.** New mirror file `game-src/place-full/StarterPlayer/StarterPlayerScripts/GameHUDPanels/GalleryPanel.lua`; overwrite `GameHUDClient.client.lua` and `SpecTheme.lua`; commit `feat(ui): Studio-only Gallery panel; MaxLive measured (desktop D / tablet T / phone P)` with the cap→dt table in the body.

---

### Task 12: Grammar sweep — Goals / Index / Charms active tabs go blue

**Files:**
- Modify: `GameHUDPanels.GoalsPanel` (≈ line 1242), `GameHUDPanels.IndexPanel` (≈ 831 and 861, identical lines), `GameHUDPanels.CharmsPanel` (≈ 1073)

**Interfaces:**
- Consumes: `S.Role.Neutral`, `S.Role.Disabled` (Task 2). The three panels already alias SpecTheme as `S`, `SPEC_S` and `SpecS` respectively.

- [ ] **Step 1: Back up** the three panels as `GoalsPanel_pre12`, `IndexPanel_pre12`, `CharmsPanel_pre12`.

- [ ] **Step 2: Three one-expression edits.** `script_read` each anchor first (search `delta 7: active = green`).

GoalsPanel `multi_edit` — `old_string`:
```lua
			local c = active and S.Action.Go or S.Action.Neutral -- delta 7: active = green
```
`new_string`:
```lua
			local c = active and S.Role.Neutral or S.Role.Disabled -- 2026-09-18 UI foundation: blue = navigation (was delta 7 green)
```

IndexPanel `multi_edit` with `replace_all = true` (the world and filter paints are the same line) — `old_string`:
```lua
				local c = on and SPEC_S.Action.Go or SPEC_S.Action.Neutral -- delta 7: active = green
```
`new_string`:
```lua
				local c = on and SPEC_S.Role.Neutral or SPEC_S.Role.Disabled -- 2026-09-18 UI foundation: blue = navigation (was delta 7 green)
```

CharmsPanel `multi_edit` — `old_string`:
```lua
			local c = if on then SpecS.Action.Go else SpecS.Action.Neutral -- delta 7: active = green
```
`new_string`:
```lua
			local c = if on then SpecS.Role.Neutral else SpecS.Role.Disabled -- 2026-09-18 UI foundation: blue = navigation (was delta 7 green)
```

- [ ] **Step 3: Compile-gate + byte-scan.** `execute_luau` (Edit): `loadstring` all three; assert `IndexPanel.Source` contains `SPEC_S.Role.Neutral` exactly twice (`select(2, src:gsub("SPEC_S%.Role%.Neutral", ""))`), and no `Action.Go or` remains in the three swept lines (`not src:find("delta 7: active = green", 1, true)` for each).

- [ ] **Step 4: Live opens + captures.** Play: open Progress (Goals tab strip: active blue, white ink); Bag → INDEX tab (`BackpackPanel.Body.Tabs.TabIndex.Hit` — path from a live `FindFirstChild("TabIndex", true)`): world chips + filter chips, active blue; Bag → CHARMS tab: filter chips active blue. Three captures. Console clean. Stop Play.

- [ ] **Step 5: Mirror + commit.** Overwrite the three mirror files; commit `feat(ui): active tabs and filter chips are blue (navigation) in Goals, Index, Charms`.

---

### Task 13: Bag brainrot inventory grid → `BrainrotCard` + `ViewportCuller` (+ `SearchBar`, `SortButton`, `Toast`)

**Files:**
- Modify: `GameHUDPanels.BackpackPanel` — module top (after `local NumberFormat = require(...)`, ≈ line 191), `renderBrainrots` start (≈ 2225–2228), the sort loop (≈ 3394–3410), the search block (≈ 3421–3486), `fillBag` (≈ 3518–3628), the old search wiring (≈ 3647–3650), the `wrapper` Visible handler (≈ 5218–5227).

**Interfaces:**
- Consumes: `BrainrotCard.new` (9), `ViewportCuller.attach` (10), `SearchBar.new`, `SortButton.new` (6), `Toast.show` (7), `Mutations.Color` (already required as `Mutations`), the panel's own `ownedBrainrots`, `infoByName`, `tierRank`, `valueOf`, `newUids`, `countPlaced`, `plotState`, `remotes`, `showCardTip`, `hideCardTip`, `bagCount`, `scroll`, `sub`, `searchQuery`, `sortMode`, `SORT_LABEL`, `SORT_W`, `SORT_GAP2`, `SEARCH_W`, `headRight`, `sorts`, `renderBrainrots`.
- Produces: the live Bag grid per UID on the kit; `gridUi = { culler, cards, fill }` at module top.

- [ ] **Step 1: Back up** `BackpackPanel` as `BackpackPanel_pre13`. `script_read` every anchor region listed above — line numbers here are from plan time; the text is what matters.

- [ ] **Step 2: Module-top requires + `gridUi`.** `multi_edit` — `old_string`:
```lua
local NumberFormat = require(modules:WaitForChild("NumberFormat"))
```
`new_string`:
```lua
local NumberFormat = require(modules:WaitForChild("NumberFormat"))
-- 2026-09-18 UI foundation round 1 (spec §9): the brainrot INVENTORY grid runs on the
-- kit's BrainrotCard + ViewportCuller, one card per UID; its controls are the kit's
-- SearchBar / SortButton; "no free slots" goes through the one Toast stack. Required
-- at MODULE top on purpose: Build() sits near Luau's 200-local ceiling.
local BrainrotCard = require(modules:WaitForChild("UIKit"):WaitForChild("BrainrotCard"))
local ViewportCuller = require(modules:WaitForChild("UIKit"):WaitForChild("ViewportCuller"))
local SearchBar = require(modules:WaitForChild("UIKit"):WaitForChild("SearchBar"))
local SortButton = require(modules:WaitForChild("UIKit"):WaitForChild("SortButton"))
local Toast = require(modules:WaitForChild("UIKit"):WaitForChild("Toast"))
-- grid state shared by renderBrainrots / fillBag / the hide handler. Not `bagState`
-- (that is the snapshot table below); a module-level table adds no Build() locals.
local gridUi = { culler = nil :: any, cards = {} :: { any }, fill = nil :: (() -> ())? }
```

- [ ] **Step 3: Release the previous grid at the top of `renderBrainrots`.** `multi_edit` — `old_string`:
```lua
		local keepScroll = (grid and grid.Parent) and grid.CanvasPosition or nil
		clearChildren(contentHost)
		refreshHeader()
		hideCardTip()
```
`new_string`:
```lua
		local keepScroll = (grid and grid.Parent) and grid.CanvasPosition or nil
		-- 2026-09-18: release the previous grid's viewports, driver entries and culler
		-- BEFORE contentHost is cleared, so nothing animates or mounts into a dead tree
		if gridUi.culler then gridUi.culler.detach() gridUi.culler = nil end
		for _, c in ipairs(gridUi.cards) do c.destroy() end
		gridUi.cards = {}
		gridUi.fill = nil
		clearChildren(contentHost)
		refreshHeader()
		hideCardTip()
```

- [ ] **Step 4: Sort chips → `SortButton`.** `multi_edit` — `old_string`:
```lua
		for i, mode in ipairs(SORT_MODES) do
			local slot = Instance.new("Frame")
			slot.Name = "Sort" .. mode
			slot.BackgroundTransparency = 1
			slot.Position = UDim2.fromOffset((i - 1) * (SORT_W + SORT_GAP2), 0)
			slot.Size = UDim2.fromOffset(SORT_W, 36)
			slot.ZIndex = 14
			slot.Parent = sorts
			local sb = flatButton(slot, SORT_LABEL[mode], SORT_W, 36, mode == sortMode, false)
			sb.Name = "Button"
			sb.MouseButton1Click:Connect(function()
				if sortMode ~= mode then
					sortMode = mode
					renderBrainrots()
				end
			end)
		end
```
`new_string`:
```lua
		-- 2026-09-18 UI foundation: the kit's SortButton (blue active / grey rest)
		-- at the row's 36px height; SORT_MODES/SORT_LABEL still name the modes.
		-- Inline table on purpose: no new local in this already-crowded scope.
		SortButton.new({
			modes = {
				{ id = SORT_MODES[1], label = SORT_LABEL[SORT_MODES[1]] },
				{ id = SORT_MODES[2], label = SORT_LABEL[SORT_MODES[2]] },
				{ id = SORT_MODES[3], label = SORT_LABEL[SORT_MODES[3]] },
			},
			selected = sortMode, height = 36,
			width = 3 * SORT_W + 2 * SORT_GAP2, parent = sorts, zIndex = 15,
			onChanged = function(id)
				if sortMode ~= id then
					sortMode = id
					renderBrainrots()
				end
			end,
		})
```

- [ ] **Step 5: Search box → `SearchBar`.** `multi_edit` — `old_string` is the exact live text from `		local searchHost = Instance.new("Frame")` through `		box.Parent = searchHost` (at plan time lines 3421–3486, including the magnifier `do … end` block and every `box.*` line). `new_string`:
```lua
		-- 2026-09-18 UI foundation: the kit's SearchBar (same 36px row, same
		-- headRight slot, same searchQuery). fillBag is defined below, so the
		-- handler reaches it through gridUi.fill (assigned once fillBag exists).
		local search = SearchBar.new({
			placeholder = "SEARCH...", width = SEARCH_W, height = 36, parent = headRight, zIndex = 15, layoutOrder = 0,
			onChanged = function(q)
				searchQuery = q
				if gridUi.fill then gridUi.fill() end
			end,
		})
		search.set(searchQuery)
```

- [ ] **Step 6: `fillBag` per UID on `BrainrotCard`.** `multi_edit` — `old_string` is the exact live text from `		-- fillBag rebuilds only the cells, so search typing keeps its focus` through the `end` that closes `fillBag` (the line before `		fillBag()`; at plan time lines 3517–3628). `new_string`:
```lua
		-- fillBag rebuilds only the cells, so search typing keeps its focus.
		-- 2026-09-18 UI foundation (spec §9): ONE BrainrotCard PER UID -- no stacking
		-- in the grid (mutation, size, lock and serial can all differ; the Sell panel
		-- keeps its own stacks) -- on a ViewportCuller so only the visible window
		-- holds live ViewportFrames. The legacy `Fav` save flag is normalised to the
		-- card's `locked` state here and nowhere else.
		local function fillBag()
			if gridUi.culler then gridUi.culler.detach() gridUi.culler = nil end
			for _, c in ipairs(gridUi.cards) do c.destroy() end
			gridUi.cards = {}
			for _, c in ipairs(scroll:GetChildren()) do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			local oldMsg = sub:FindFirstChild("EmptyMsg")
			if oldMsg then
				oldMsg:Destroy()
			end

			local q = searchQuery:lower():gsub("^%s+", ""):gsub("%s+$", "")
			local bag = {}
			for _, e in ipairs(ownedBrainrots) do
				if q == ""
					or e.Name:lower():find(q, 1, true) ~= nil
					or (e.Mutation ~= nil and e.Mutation:lower():find(q, 1, true) ~= nil)
					or (e.Size ~= nil and e.Size:lower():find(q, 1, true) ~= nil)
				then
					bag[#bag + 1] = e
				end
			end

			-- sorts: RARITY (tier then income), NEWEST (snapshot order), A-Z
			if sortMode == "rarity" then
				table.sort(bag, function(x, y)
					local rx = tierRank[infoByName[x.Name] and infoByName[x.Name].Rarity] or 0
					local ry = tierRank[infoByName[y.Name] and infoByName[y.Name].Rarity] or 0
					if rx ~= ry then
						return rx > ry
					end
					return valueOf(x.Name, x.Mutation, x.Size) > valueOf(y.Name, y.Mutation, y.Size)
				end)
			elseif sortMode == "newest" then
				local pos = {}
				for i, e in ipairs(ownedBrainrots) do
					pos[e.Uid] = i
				end
				table.sort(bag, function(x, y)
					return (pos[x.Uid] or 0) > (pos[y.Uid] or 0)
				end)
			else
				table.sort(bag, function(x, y)
					if x.Name ~= y.Name then
						return x.Name < y.Name
					end
					return valueOf(x.Name, x.Mutation, x.Size) > valueOf(y.Name, y.Mutation, y.Size)
				end)
			end

			bagCount.Text = #bag .. " shown / " .. #ownedBrainrots .. " owned"

			if #bag == 0 then
				local none = Instance.new("TextLabel")
				none.Name = "EmptyMsg"
				none.BackgroundTransparency = 1
				none.Font = S.Font.Read
				none.TextSize = 14
				none.TextColor3 = C_SUB
				none.Text = if #ownedBrainrots == 0
					then "Nothing in the bag \u{2014} go skip some rocks!"
					else "Nothing in the bag matches that search."
				none.Size = UDim2.fromScale(1, 1)
				none.ZIndex = 15
				none:SetAttribute("NoPolish", true)
				none.Parent = sub
				return
			end

			local cards = {}
			for i, e in ipairs(bag) do
				local info = infoByName[e.Name]
				local card = BrainrotCard.new({
					kind = "brainrot",
					name = e.Name,
					rarity = (info and info.Rarity) or "Common",
					income = valueOf(e.Name, e.Mutation, e.Size),
					mutation = e.Mutation,
					mutationColor = if e.Mutation then Mutations.Color(e.Mutation) else nil,
					sizeTag = e.Size,
					-- bench entries are never placed (ownedBrainrots excludes PadIndex);
					-- `Fav` IS the plot lock (PlotFav) -> the card's `locked`
					state = { equipped = false, locked = e.Fav == true, new = newUids[e.Uid] == true, selected = false },
					lock = { onToggle = function(_nextLocked)
						-- ToggleLock (capacity-gated, plot-synced) answers through
						-- DataUpdated, which rebuilds this grid with the new flag
						local r = remotes:FindFirstChild("ToggleLock")
						if r then r:FireServer({ e.Uid }) end
					end },
					variant = "grid",
					parent = scroll,
					zIndex = 15,
					layoutOrder = i,
					instanceName = "BagCell" .. i,
				})
				card.Activated:Connect(function()
					newUids[e.Uid] = nil
					if countPlaced() < plotState.Unlocked then
						remotes.EquipBrainrot:FireServer(e.Uid)
					else
						Toast.show({ text = "NO FREE SLOTS \u{2014} UNLOCK ONE", tone = "error" })
					end
				end)
				card.HoverStart:Connect(function()
					if showCardTip then showCardTip(e, card.root) end
				end)
				card.HoverEnd:Connect(function()
					if hideCardTip then hideCardTip() end
				end)
				cards[#cards + 1] = card
			end
			gridUi.cards = cards
			gridUi.culler = ViewportCuller.attach(scroll, cards)
		end
		gridUi.fill = fillBag
```

- [ ] **Step 7: Remove the old search wiring.** `multi_edit` — `old_string`:
```lua
		box:GetPropertyChangedSignal("Text"):Connect(function()
			searchQuery = box.Text
			fillBag()
		end)
	end
```
`new_string`:
```lua
	end
```

- [ ] **Step 8: Release on hide.** `multi_edit` — `old_string`:
```lua
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		setBlur(wrapper.Visible)
		if wrapper.Visible then
```
`new_string`:
```lua
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		setBlur(wrapper.Visible)
		if not wrapper.Visible and gridUi.culler then
			-- 2026-09-18: a hidden Bag holds no live viewports and no culler
			-- connections; reopening re-renders the tab and re-attaches
			gridUi.culler.detach()
			gridUi.culler = nil
		end
		if wrapper.Visible then
```

- [ ] **Step 9: Compile-gate + byte-scan + implicit-global scan.** `execute_luau` (Edit):

```lua
local s = game:GetService("StarterPlayer").StarterPlayerScripts.GameHUDPanels.BackpackPanel
local src = s.Source
local f, e = loadstring(src); assert(f, e)
for _, needle in ipairs({ "local gridUi = {", "gridUi.culler.detach()", "SortButton.new({", "SearchBar.new({", "BrainrotCard.new({", "ViewportCuller.attach(scroll, cards)", "gridUi.fill = fillBag", "Toast.show({ text = \"NO FREE SLOTS" }) do
	assert(src:find(needle, 1, true), "missing: " .. needle)
end
assert(not src:find("box:GetPropertyChangedSignal(\"Text\")", 1, true), "old search wiring still present")
assert(not src:find("local searchHost = Instance.new", 1, true), "old search host still present")
assert(not src:find("flatButton(slot, SORT_LABEL[mode]", 1, true), "old sort chips still present")
-- the deleted block must not have left `box`/`searchHost` referenced anywhere in the Brainrots tab
local n = 0; for _ in src:gmatch("searchHost") do n += 1 end
assert(n == 0, "searchHost references remain: " .. n)
return ("BackpackPanel compiles, %d bytes"):format(#src)
```

- [ ] **Step 10: Live verification on the real save (Play).** Foreground Studio for captures. `start_stop_play(true)`, open the Bag from the rail.
  1. **Per-UID counts:** `execute_luau` (Client): find the grid (`playerGui:FindFirstChild("BackpackPanel", true)` → descendant ScrollingFrame named `Grid`), count children with a `BrainrotName` attribute, read the counter label's text (`bagCount`, the TextLabel whose text ends with `owned`); assert cards == the "shown" number, and shown == owned with an empty search.
  2. **Culling:** count descendants named `Preview` (ViewportFrames) under the grid → `<= grid:GetAttribute("CullerCap")` and `== grid:GetAttribute("CullerLive")`; set `grid.CanvasPosition = Vector2.new(0, 1e6)`, `task.wait(0.3)`, re-count; back to the top, re-count. Capture the grid at top and bottom.
  3. **Hover + tooltip:** `user_mouse_input` `moveTo` `…Grid.BagCell1.VisualRoot.Plate.Hit`, wait 300 ms; `execute_luau` (Client): the tooltip (`wrapper:FindFirstChild("Tooltip", true)`, whichever GuiObject `PC.tooltip` builds — locate with `FindFirstChild("NameLine", true).Parent`) is Visible and its NameLine text equals the entry's label. Capture (hover lift + tooltip). Move away; tooltip hides.
  4. **Lock round trip:** hover `BagCell1` again → `…Plate.BadgesRight.Lock.Visible == true`; `user_mouse_input` click on it → wait 1 s → the rebuilt `BagCell1` (same UID: read `BrainrotName` before/after and confirm the entry's `Fav` flipped through the tooltip's `LOCKED` meta or the Lock badge being visible without hover). Click it again → unlocked. Console clean.
  5. **Equip round trip:** click `…BagCell1.VisualRoot.Plate.Hit` → wait 1 s → the "shown / owned" count dropped by one (the entry moved to the plot); `execute_luau` (Client) `remotes.StoreBrainrot:FireServer(<that uid>)` (the bay's own store path) → count restored. If the plot is full the click must instead show the "NO FREE SLOTS" toast (check `PlayerGui.UIKitToast.Stack` has a line) — either outcome is a pass; note which.
  6. **Search + sort:** `execute_luau` (Client): set the SearchBar's `Input.Text` to the first two letters of a known name → after 0.3 s the count label shows fewer cards; clear → all back. Click each `SortButton` chip (`…SortButtons.SortButton` children) via `user_mouse_input`; after each, read `BagCell1:GetAttribute("BrainrotName")`/`Rarity` and confirm the order changed as expected (rarity: highest tier first; az: alphabetical first).
  7. **Grammar:** capture the inventory header — SortButton active chip blue, SearchBar white well.
  8. `get_console_output`: no errors, no `[UIKit]` warnings (an adaptive-cap step-down warning is acceptable if the frame budget was exceeded — record it).
  9. **Phone pass:** `start_stop_play(false)`, `PlatformOverride = "Phone"` in Edit, Play, open the Bag, Brainrots tab renders, `CullerCap` equals `S.Card.MaxLive.Phone`, capture; stop Play; remove the override and confirm nil.

- [ ] **Step 11: Mirror + commit.** Overwrite `BackpackPanel.lua`; commit `feat(bag): brainrot inventory grid on BrainrotCard + ViewportCuller (per UID), SearchBar/SortButton controls, toast via UIKit`.

---

### Task 14: Repeated-cycle leak check, docs, memory, final sync

**Files:**
- Modify: `game-src/README.md` (new section at the top, matching the existing per-round style)
- Create: `C:\Users\m\.claude\projects\C--Users-m-Coding-skip-a-brainrot\memory\roblox-ui-foundation-round1.md` + its `MEMORY.md` line; one pointer line appended to `C:\Users\m\.claude\projects\C--Users-m-Coding\memory\MEMORY.md`
- Modify: `docs/superpowers/plans/2026-09-18-ui-foundation.md` (execution log appended)

- [ ] **Step 1: Leak cycles (Play).** `start_stop_play(true)`. Ten cycles of: `user_mouse_input` click the rail Bag hit → wait 0.6 s → `execute_luau` (Client) set the grid's `CanvasPosition` to bottom, wait 0.2, top, wait 0.2 → `user_keyboard_input` `Escape` (closePanel). Then ten cycles of: `execute_luau` (Client) `LocalPlayer:SetAttribute("HudGallery", true)` → wait 0.8 → click `Tabstress` → click `N=500` → wait 1 → `Escape`. After the last close, `execute_luau` (Client):

```lua
local pg = game.Players.LocalPlayer.PlayerGui
local RS = game:GetService("ReplicatedStorage")
local previews, total = 0, 0
for _, d in ipairs(pg:GetDescendants()) do
	total += 1
	if d:IsA("ViewportFrame") and d.Name == "Preview" then previews += 1 end
end
local fx = RS.Modules.UIKit.FxDriver
local grid = pg:FindFirstChild("Grid", true)
return ("previews=%d fxRunning=%s fxEntries=%s cullerDetached=%s cullerLive=%s totalInstances=%d modalOpen=%s"):format(
	previews, tostring(fx:GetAttribute("FxRunning")), tostring(fx:GetAttribute("FxEntries")),
	tostring(grid and grid:GetAttribute("CullerDetached")), tostring(grid and grid:GetAttribute("CullerLive")), total,
	tostring(pg:FindFirstChild("ModalScrim", true) ~= nil))
```

Expected: `previews=0 fxRunning=false fxEntries=0 cullerDetached=true cullerLive=0 … modalOpen=false`. Run the probe once after cycle 5 and once after cycle 10: `totalInstances` must be equal (± the panel's own one-time build — the Bag is built lazily once; the Gallery rebuilds its sections on every open but tears them down on close). A rising count is a leak: find it (section `teardown`, `gridUi` release, `Toast` lines) before continuing. `get_console_output` clean. `start_stop_play(false)`.

- [ ] **Step 2: `game-src/README.md`.** Prepend a section `## UI foundation round 1 (2026-09-18)` in the file's existing style: what shipped (modules, the Bag seam, the Gallery + trigger, the measured `MaxLive`), the spec/plan paths, the checkpoint commit hash, the `PreUIFoundation_2026_09_18` backup folder, and the two rules future rounds inherit (rarity-first cards; `[UIKit]` warnings never silent).

- [ ] **Step 3: Memory.** Write `roblox-ui-foundation-round1.md` (type `project`) with: what exists now and where, the colour grammar decision, the card decision (style C, per UID, badge caps, animation cap), the Gallery trigger, measured caps, and gotchas met during the build (each with **Why** / **How to apply**). Add its line to that folder's `MEMORY.md` (create the index if absent) and one pointer line under "Read these first" in `C--Users-m-Coding/memory/MEMORY.md`.

- [ ] **Step 4: Execution log + final commit.** Append `## Execution log (2026-09-18)` to this plan: per task, what was verified, every deviation from the plan and why, the cap→dt table, and any owner-gated leftovers (e.g., the bay still on the old card; other consumers pending). Re-sync every touched mirror file byte-exact (re-check the nine byte counts + the new modules), `git add` the plan, README, mirrors; commit `docs(ui): UI foundation round 1 execution log, README, mirror sync`. Confirm `git status` shows none of this round's files modified.

---

## Self-review (done while writing)

- **Spec coverage:** §4 modules → Tasks 2–11; §5.1 roles + sweep → 2, 4, 12; §5.2–5.4 → 2; §6.1 → 5; §6.2 → 4; §6.3–6.5 → 6; §6.6–6.7 → 7; §7 → 9 (+ 2 for the ladder table); §8.1–8.2 → 8, 9; §8.3 → 10, 11 (caps); §9 → 13; §10 → 11; §11 → 2 (GameHUDClient), every module's warn sites; §12 → 9, 10; §13 → each task's test + 11, 13, 14; §14 → 1 (checkpoint), every task's backup step; §16 risks → live opens after each task.
- **Placeholders:** none — every step has its code or its exact probe. The only values filled at execution time are the measured `MaxLive` numbers (Task 11 Step 6), by an explicit rule.
- **Type consistency:** `Cullable = { root, mount, unmount, isMounted }` (Task 10) is exactly what `BrainrotCard.new` returns (Task 9) and what `GalleryPanel`/`BackpackPanel` pass. `PanelChrome.button` kinds (`positive | neutral | destructive | gold | purple | secondary`) are the same set in Tasks 4, 5 (footer), 7 (Modal), 11. `SearchBar/SortButton/TabBar` `height` is used by Task 13 at 36. `S.Card.TIER_KEY/Ladder/Variants/MaxLive/Light/Fill` names match between Tasks 2, 9, 10, 11. `FxDriver` attribute names `FxEntries/FxRunning` and culler attributes `CullerLive/CullerCap/CullerDetached` match between Tasks 3, 10 and 14.

---

## Execution log (2026-09-18)

Round ledger with rulings: `.superpowers/sdd/2026-09-18-ui-foundation/progress.md`. Per-task reports with full numbers: `.superpowers/sdd/2026-09-18-ui-foundation/task-N-report.md`. HEAD at round close: `57f3e41`.

### Task 1 — Pre-round checkpoint
**Verified:** all nine live sources dumped byte-exact and matched Studio's `#inst.Source` 9/9 on the first pass; `ServerStorage.AuditBackups.PreUIFoundation_2026_09_18` created; checkpoint commit `32e1701`.
**Deviations:** `execute_luau` return values silently truncate to ~100,015 characters past that size (not just a loud token-limit refusal) — discovered mid-task on `GameHUDClient` (142 KB) and `BackpackPanel` (221 KB). Worked around by fetching both in newline-snapped `src:sub(a, b)` chunks sized to land safely under the ceiling, concatenated byte-for-byte outside the LLM path. This chunking approach became standard for every later task touching either file.

### Task 2 — Colour roles, spacing, card ladder tokens; panel pcalls warn
**Verified:** `GameHUDClient`'s two pcall sites now `warn()` on failure (panel Build, panel-module require); `SpecTheme` gained `S.Role/S.Space/S.Sound/S.Card` and the `S.Scale` retune; both mirrors byte-exact; commit `0d98a66`.
**Deviations:** born here, reused every task after — (1) the **backup-stub recipe**: the brief's literal `Clone()`-into-`AuditBackups` script is refused by script Capabilities (`cannot reparent ... LoadUnownedAsset`), replaced by a `multi_edit` stub + `stub.Source = live.Source` string copy; (2) discovery that `require()` of any ModuleScript is blocked for the exec thread in **both** Edit and Play, not just Play as first assumed — the brief's literal dynamic SpecTheme test could not run as written, which led directly to the **live-source loader preamble** (`test-loader.lua`: `loadstring` + a fake recursive `require`, `script` rebound to the live instance) used by every module test from Task 3 onward; (3) `user_mouse_input`/`screen_capture` timed out for the implementer's session outright (no interactive desktop) — the controller's own re-run worked once Studio was properly foregrounded, which is the origin of the **`studio-focus.ps1` focus helper** written into the global constraints. Also surfaced the pre-existing, harmless `PetAbilityHelp` panel-module warning that recurs in every later console check this round.

### Task 3 — `FxDriver`
**Verified:** the one-Heartbeat animation registry created, compile-gated, behaviour test `FxDriver OK`, mirror byte-exact, commit `7e8b019`.
**Deviations:** fix round 1 (plan-mandated, controller-ruled) — `tick()` iterated the `entries` table with `pairs()` while calling each step; a step that registers a new entry mid-tick (as `PanelChrome.setBusy`, `BrainrotCard`'s aura/band/sparkle steps, and Toast's fade all can) mutates `entries` mid-`pairs`-traversal, which is undefined under Luau's `next`. Fixed by snapshotting a sorted id list before iterating and re-fetching each entry from the live table. Commit `44f1f3d`. This is the **FxDriver snapshot** fix referenced by every later module that registers FX handlers.

### Task 4 — `PanelChrome` semantic buttons
**Verified:** `button`/`setEnabled`/`setBusy`, click sound, `pill.outline`, the green→blue/grey grammar sweep in `addHeaderTabs`/`segmented`; live Progress-panel tab colour confirmed by exact `Color3` equality; mirror byte-exact; commits `47ba880` then `17b8620`.
**Deviations:** the brief's own Step 6 test compared `TextTransparency == 0.45` by strict equality — Roblox stores `Transparency` properties as float32, so the literal `0.45` round-trips to `0.44999998807907104` and can never satisfy `==`. Diagnosed as a test-authoring defect (not a module bug), and — per instructions to stop rather than loosen a test unilaterally — reported BLOCKED until the coordinator approved an epsilon comparison (`< 1e-3`). This is the **float-epsilon rule** every later test with a Transparency/float assertion follows. Fix round 1 added the **sound warn-once** pattern (a `soundWarned` local; the click-sound `pcall` now logs only its first failure) reused verbatim by Task 6's TabBar. Also found, and left alone as out-of-scope: `UIPolish`'s pre-existing readability floor force-whitens `S.Surface.ReadInk` (and any other low-saturation "dark ink") label text on inactive tabs/chips game-wide — the background-colour grammar is correct and live-verified, only the ink colour is overridden by a different, unrelated system.

### Task 5 — `PanelChrome.shell` slots
**Verified:** `stat`/`primaryAction`/`addFooter` shell slots, test `shell slots OK`, five panels (bag/goals/worlds/shop/settings) opened live with no `[UIKit]` warnings, mirror byte-exact, commit `9f3d9a2`.
**Deviations:** none functional — all-new opt-in fields, confirmed a bare `shell()` call (no `stat`/`primaryAction`) keeps byte-identical geometry to pre-round. Plan-mandated minors deferred: footer groups always reserve half the band even with one side empty; `primaryAction` and `addHeaderTabs` share one header anchor (documented as not-both-this-round).

### Task 6 — `TabBar`, `SearchBar`, `SortButton`
**Verified:** all three created, compile-gated, behaviour test `TabBar/SearchBar/SortButton OK`, mirrors byte-exact, commit `28e124f`.
**Deviations:** fix round 1 — TabBar's click sound had the same silent-forever gap Task 4 found, fixed with the identical warn-once pattern; `Builders.lua`'s **mirror** had drifted stale (`UI.touchMin` was already live but never re-synced to disk) — re-synced with no Studio edit; `SortButton.get()` indexed `props.modes[seg.get()]` unguarded — added a nil-guard. Commit `f7c16b1`. `script_grep` line numbers were stale/unreliable again this task (a recurring, non-blocking finding across Tasks 4/5/6/8 — every anchor was re-read fresh via `script_read` instead, never trusted from grep or the mirror).

### Task 7 — `Modal`, `Toast`, `ToastClient` wiring-only
**Verified:** `Modal.confirm`/`Toast.show` created, Edit-mode behaviour test `Modal/Toast OK (confirmed=0 cancelled=1)`, `ToastClient` cut from a full renderer to a 4-line adapter (`push` → `Toast.show`), static check `ToastClient compiles, single renderer`, mirrors byte-exact, commit `03d77fe`.
**Deviations:** confirmed here, categorically, for the rest of the round — the exec thread cannot `require()`, `loadstring()` under Client, or `RemoteEvent:FireClient()` during Play, so **no exec-driven path can render a live Toast/Modal**; the brief's literal Step 6 live-render script cannot run in any session. Ruling: live rendering of both is proven instead through Task 11's Gallery (MODAL+TOAST section, real clicks) and Task 13's real "NO FREE SLOTS" production toast — this is the **"Play verification only through the real UI"** rule carried into the round's inherited rules. Fix round 1 removed five now-dead stack-geometry constants left behind by the Step 4 rewrite (careful substring check to avoid colliding with the unrelated, still-live `TILE_HOLD`). Commit `1850fad`.

### Task 8 — `BrainrotThumb.framingBox`
**Verified:** projected-corner box fit added alongside the renamed `framingSphere`; the 2-arg `framing()` dispatch is byte-identical to the old sphere-only behaviour (`c1==c2 and d1==d2` asserted); numeric test passed (4 picks, fill 0.700, mid ≤0.001); live Bag (49 viewports) and Index (30 viewports) rendered unchanged; mirror byte-exact; commit `6388f4a`.
**Deviations:** the brief's descriptive prose expected `box/sphere` distance ratio below 1 for tall/wide picks; measured ratios were 1.14–1.29 for all four test picks (the only coded assertions — fill range, mid range — both passed, so this was not a stop-and-report case). Root cause: the sphere fit's `MARGIN=1.10` back-solves to a much larger effective fill (~0.90) than the box fit's 0.70 target, so the box fit is uniformly tighter, not just for elongated shapes. Left untouched per "don't change the maths on a narrative mismatch." This directly motivated Task 11's `S.Card.Fill` retune (0.70 → 0.88) once the Gallery's framing-set section showed the box-fit art sitting smaller in the card than the handoff's 65–75 % intent — ruled in `progress.md` as "brief prose was wrong, maths right."

### Task 9 — `BrainrotCard`
**Verified:** the style-C rarity-first card created (25,081 B), pre-flight-checked against the live `S.Card` shape, compile-gated, structural test `BrainrotCard OK` across the full 8-tier ladder (aura/foil/holo/sparkles per tier, FX count 7 = 1+2+2+2, badge caps/priority, mount/unmount lifecycle, missing-art placeholder, unknown-rarity fallback), mirror byte-exact, commit `a5ad8b6`.
**Deviations:** fix round 1, 9 findings (2 Important + 7 minor) applied as one atomic edit: (1) **reserved lock slot** — a fixed-size `LockSlot` wrapper so the Lock badge's hover-visibility toggle no longer shifts the Equipped badge; (2) **seamless/doubled rainbow band** — the band gradient is now a doubled `ColorSequence` with a matching offset formula so it has no visible seam while animating; (3) `mount()`'s `pcall` widened to cover the `BrainrotThumb.master`/`petMaster` lookup itself; (4) `MouseLeave` gated on a captured `wasHovering` so touch (which never sets `hovering`) can't spuriously fire `HoverEnd`; (5) sparkle repositioning + stroke-fade; (6) `paintCount()` extracted so the tier-name label only reserves count-column width when a count is actually shown; (7) touch-unlocked padlock subdued (badge/stroke faded) when `touchOnly` and not locked; (8) `Platform.IsTouch` wired into `touchOnly`; (9) `set()` identity guard — `name`/`kind`/`model` can't be mutated post-construction, warns once and drops the keys (same pattern as the existing rarity guard). Commit `6ce8d69`. Three pre-existing test lines needed mechanical updates because `LockSlot` made `Lock` a grandchild rather than a direct child of `BadgesRight` — documented, not a loosening.

### Task 10 — `ViewportCuller`
**Verified:** scroll-visibility mount/unmount with a per-platform adaptive cap; pure-planner assertions (cap respected, nearest-to-centre first, deterministic) and real-scroll mount/unmount at both extremes all passed; final test `ViewportCuller OK`; mirror byte-exact; commit `10274ee`.
**Deviations:** the first pass found a **real defect**, not a timing flake — `culler.setCards({ cards[1], cards[2] })` left `mountedCount() == 24`, not `2`. Root cause: `pass()`/`setCards` only ever visit cards in the *current* `items` table, so cards mounted under a wider previous `items` list that are absent from a narrower new one are never revisited and stay mounted forever — a genuine leak class, directly the kind of defect this Task 14's leak check exists to catch. Per instructions, stopped and reported rather than patching beyond the brief; the controller supplied a patched `setCards` (diffs old vs. new `items`, unmounts the dropped cards before swapping) which was applied verbatim and re-tested clean. Fix round 1 (2 Important + 2 minor): **`safeUnmount()`** — a `pcall`-wrapped, traceback-warning helper replacing four bare `c.unmount()` call sites (a throwing unmount previously could abort a cleanup loop mid-way, including inside the just-fixed `setCards`); **`scroll.AncestryChanged` → `auto-detach()`** so an orphaned `ScrollingFrame` (destroyed/reparented without an explicit `detach()`) can no longer leak its `Heartbeat` connection forever; initial `CullerDetached`/`CullerLive`/`CullerCap` attributes set synchronously in `attach()`; deterministic index tie-break in `planPass`'s sort comparator. Commit `b132bee`. The **`setCards` diff-and-unmount fix** and the **`AncestryChanged` auto-detach** are exactly the two mechanisms Task 14's repeated-cycle leak check (below) verifies hold under real, repeated open/close/search/re-render load.

### Task 11 — `GalleryPanel` + trigger + stress test → `S.Card.MaxLive`
**Verified:** the Studio-only living style guide (all nine sections: Tokens/Buttons/Shell/Tabs/Inputs/Modal+Toast/Cards/Stress/Legacy) rendered clean on first live open with zero section failures; `GameHUDClient` trigger wired to `LocalPlayer:SetAttribute("HudGallery", true)`; `S.Card.Fill` retuned 0.70 → 0.88 and re-verified (all six framing-set extremes ≈0.88, off-centre ≤0.01); mirrors byte-exact; commit `caf217a`.
**Deviations:** the Desktop stress test never found a true ceiling — all four tested caps (24/48/72/96) landed at the same ~16.7 ms median, almost certainly this dev machine's vsync floor rather than a real cost curve, so the mechanically-correct `MaxLive.Desktop = 96` was "the largest button the Gallery offers," not a proven breaking point. Phone numbers came from `PlatformOverride` emulation only — the same desktop CPU/GPU, not real handset hardware. Fix round 1 (controller-ruled): replaced the measured-but-unvalidated 96/72/48 table with the **conservative shipped defaults `Desktop=64, Tablet=40, Phone=24`**; fixed a `rebuild()` culler-list leak (`table.insert` onto a growing list → single-culler replacement, since the prior culler is already detached two lines above); a bare `pcall(GetBoundingBox)` in `framingSet()` now warns with the model's identity on failure instead of failing silently; the AUTO-SCROLL thread is now tracked and `task.cancel()`-ed by `teardown()`. Commit `e5db1fd`. Live re-verification after the fix confirmed 0 stray `Preview` viewports and `FxEntries=0` after a full Stress→Tokens teardown cycle — the direct precedent for this task's own leak methodology.

### Task 12 — Goals/Index/Charms active tabs → blue
**Verified:** the one-line green→blue/grey grammar swap in all three panels (Index has two identical lines), compile gates, live pixel confirmation for Goals and Index (`4AA8FF` active / `D3DCE6` inactive, both programmatic `Color3` reads and screen captures), mirrors byte-exact (a one-space transcription slip in `CharmsPanel` caught by a 10-point checksum, not just a byte-count match, and corrected), commit `e67a9bf`.
**Deviations:** Charms' own tab could not be reached live — `BackpackPanel`'s pre-existing, deliberately documented `CHARMS_READY = false` feature flag shows "Coming soon!" instead of mounting `CharmsPanel`; unrelated to this round, not touched. Substituted a static proof that `CharmsPanel` reads the identical `S.Role` table cells already proven live by Goals and Index. Steps 1–2 (backups + edits) were found already applied by an earlier, unlogged attempt before this task's session started; independently re-derived and re-verified rather than trusted.

### Task 13 — Bag inventory grid on `BrainrotCard` + `ViewportCuller`
**Verified:** `BackpackPanel.fillBag` migrated to per-UID `BrainrotCard`s on a `ViewportCuller`, with `SearchBar`/`SortButton`/`Toast` replacing the old hand-rolled controls (7 anchored edits, each compile-gated); extensive live Play verification — per-UID counts, culling at both scroll extremes, hover+tooltip, a lock round trip, an equip round trip (plot was 16/16, so a real "NO FREE SLOTS — UNLOCK ONE" `Toast` fired), search+sort, grammar, and a phone pass confirming `CullerCap = S.Card.MaxLive.Phone = 24`; mirror byte-exact (verified with three independent hashes — length, FNV-1a, Adler-32 — since the 222 KB file exceeds a single round-trip); commit `d17a0b1`.
**Deviations:** the backup-stub recipe hit a new limit — `execute_luau`'s `Source` assignment is capped at 200,000 characters and `BackpackPanel` is 220,878 — used `ScriptEditorService:UpdateSourceAsync` instead of the usual `stub.Source = live.Source`. The culling assertion (`previews == CullerLive`) needed a `+ MissingArt` adjustment: `BrainrotCard.mount()` counts a missing-art placeholder as mounted even though it draws no `Preview` viewport (an expected consequence of Task 9's placeholder path, not a bug) — `previews + MissingArt == CullerLive` held stable at both scroll extremes. The lock round trip ran on an already-locked card instead of `BagCell1` as planned, because the save's padlock capacity (1) was already used — OFF is always free, so the same mechanism was proven in both directions on a different card. Fix round 1 (2 Important + 2 minor): **`SearchBar`'s `onChanged` guarded against re-firing on its own `set()`** (`if q == searchQuery then return end`) — without this, every re-render with an active search double-built the grid (proven live: `cellsBuilt` dropped from 2 to 1 on a close/reopen cycle); **`BrainrotCard` gained long-press-to-inspect on touch** (a `LONG_PRESS = 0.35 s` timer/state machine, plus a `MouseLeave` touch-guard flagged by the implementer as slightly beyond the letter of the fix instructions but necessary for correct real-device behaviour) since the grid variant's tooltip — the only place a card's name/rarity/price appears — was otherwise unreachable on phones; the NEW badge now clears locally on the plot-full branch too; the hide handler now nils `gridUi.fill` even when no culler was ever attached (the "closed on an empty search result" edge case) — this is exactly the guard this Task 14's leak probe depends on to keep a late debounced search callback from resurrecting a hidden grid. Commit `57f3e41`.

### Task 14 — Repeated-cycle leak check, docs, final mirror sync
See the Play-verification results, README section, and commit in `.superpowers/sdd/2026-09-18-ui-foundation/task-14-report.md`.

### Cap → dt table (Task 11 Gallery stress, `.superpowers/sdd/2026-09-18-ui-foundation/task-11-report.md`)

**Desktop, N=500** (median of 3 samples at 1 s spacing, 3 s AUTO-SCROLL settle):

| cap | live | median avg dt |
|-----|------|---------------|
| 24  | 24   | 16.7 ms |
| 48  | 48   | 16.7 ms |
| 72  | 72   | 16.7 ms |
| 96  | 96   | 16.7 ms |

All four caps median at the same ~16.7 ms (this dev machine's vsync floor) — no true ceiling found; rule ("largest tested cap under budget") mechanically gives 96, the largest button the Gallery offers.

**Phone, N=250** (`PlatformOverride = "Phone"`, same desktop CPU/GPU):

| cap | live | behaviour |
|-----|------|-----------|
| 24  | 24   | median 16.6 ms |
| 48  | 48   | ~16.9 ms across 8 samples, no drift, adaptive step-down never engaged |

Caps 12/32 have no Gallery button; the adaptive step-down never triggered at 48, so there was no lower value to read off. Rule gives `MaxLive.Phone = 48` (upper bound only); `MaxLive.Tablet` = midpoint(96, 48) rounded to 8 = 72.

**Shipped, post fix-round-1 (Task 11, controller-ruled conservative override):** `S.Card.MaxLive = { Desktop = 64, Tablet = 40, Phone = 24 }` — the measured 96/72/48 table above was never a proven ceiling (no cap actually broke budget on this hardware, and Phone was never validated on a real device), so the shipped defaults are deliberately lower than what was measured.

### Owner-gated leftovers

- **`MaxLive.Phone` (and the whole measured table) is unvalidated on real handset hardware.** `PlatformOverride` only flips client-side branching; the Play session still runs on this dev machine's desktop CPU/GPU. Recommend a real-device pass before raising any `MaxLive` value past the shipped conservative defaults.
- **Two ghost items in the live roster:** "Nevito Lupetto" and "Gelatini Renna" have no thumb model (render the kit's "?" placeholder) and are absent from `infoByName` (price $0/s, sorted last) — a pre-existing content/data gap surfaced by Task 13's live Bag pass, not introduced by this round. `docs/design-handoff/tundra-roster/` (untracked) suggests the content is in flight.
- **Pre-existing ~18.8 px header/search overlap** between the Bag's "SLOTS FILLED" label and the new `SearchBar` at a 1855×785 viewport (Task 13) — the new control has identical geometry to the old search box it replaced, so this is not a regression, but it's visible at that size and worth a header retune.
- **`UIPolish`'s pre-existing readability floor whitens the kit's dark ink** (`S.Surface.ReadInk` and similar low-saturation colours) on some `NoPolish`-exempt labels, including inactive tab/chip text (Task 4) — the background-colour grammar this round shipped is correct and live-verified; only the ink colour is overridden by a separate, unrelated system. Fixing it (if desired) needs either a `NoPolish` ancestor beyond the label itself or a higher-saturation ink colour, out of this round's scope.
- **`CharmsPanel` is still unreachable live** behind `BackpackPanel`'s pre-existing `CHARMS_READY = false` flag (Task 12) — this round's grammar sweep on it is proven statically (same shared `SpecTheme` table cells Goals/Index proved live), not with a screenshot.
- **The equipped plot bay still renders the old card**, untouched this round — only the Bag's Brainrots-tab inventory grid (`fillBag`) was migrated onto `BrainrotCard` + `ViewportCuller` (Task 13). On phones, this means the (new) inventory grid supports long-press-to-inspect but the (old, untouched) bay's own touch affordances are whatever they were before this round.
- **`IndexPanel` and any other roster-displaying consumer have not been migrated onto `BrainrotCard`.** Only `BackpackPanel`'s Brainrots tab was in scope for card migration this round (per the File Structure table); Index received only the Task 12 active-tab colour sweep, and still renders its own roster entries with pre-round code.

