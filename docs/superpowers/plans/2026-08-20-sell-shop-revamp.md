# Sell Shop Revamp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Marco's flat 104-row sell list with a tabbed panel (brainrots + pets) that leads with one safe bulk action and drills down to individually-priced copies, with a single shared pricing module that makes advertised-price/paid-price disagreement structurally impossible.

**Architecture:** A new `ReplicatedStorage.Modules.SellValue` becomes the only definition of a sell price; server (`SellHandler`, `PetHandler`) and client (`SellPanel`) both consume it. The panel moves out of `ClientMain` — which is at Luau's 200-local ceiling and cannot host it — into `GameHUDPanels.SellPanel`, gaining the modern shell, blur and phone handling for free. `GameHUDClient` gets a small attribute-driven external open hook so a ProximityPrompt can open a rail-less panel.

**Tech Stack:** Roblox Luau. `ReplicatedStorage.Modules.UIKit` (`PanelChrome`, `Builders`, `Tokens`, `SpecTheme`). All edits land in Roblox Studio through the `roblox-studio` MCP (`multi_edit`, `execute_luau`). There is no local build, no package manager, and no test runner.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-08-20-sell-shop-revamp-design.md`. Read it before Task 1.
- **Studio, not disk.** Every code change is a `multi_edit` against a Studio instance path. Get `studio_id` from `list_roblox_studios` first. `multi_edit` requires `datamodel_type: "Edit"` — Studio must be in Edit mode, not Play.
- **Nothing is saved.** The owner saves the place; never attempt to. All work is unsaved until they do.
- **Backup before editing any script.** Clone it into `ServerStorage.AuditBackups.PreSellShop_2026_08_20` before the first edit to that script.
- **Compile-gate every edited script** with `loadstring(script.Source)` in Edit mode. This is the only thing that catches the 200-local ceiling error, which reports a misleading unrelated variable name.
- **`ClientMain` is at Luau's 200-local-per-function ceiling.** Never add a chunk-level `local` to it. Use a `do ... end` block (registers free at `end`) or put the local inside the one function that uses it.
- **Pricing formula is fixed:** `floor(base × Mutations.Mult(Mutation) × Sizes.Mult(Size) × 40)`. Player-level multipliers (rebirth, upgrades, pets, gamepass) are excluded deliberately.
- **Bulk rule (owner decision, 2026-08-20):** every bulk path holds back any copy that is favourited, placed, mutated, **or sized**. Only the `Uids` form may sell a mutated or sized copy.
- **Copy rule:** held-back wording is "mutated or oversized", never "mutated".
- **Test harness:** there is no test runner. A "test" is a Luau assertion block run via `execute_luau` with `datamodel_type: "Edit"`, printing `PASS`/`FAIL` per case and a final count. Tests assert on **pure functions only** — never on live player data.

---

### Task 1: `SellValue` — the single pricing definition

**Files:**
- Create: `ReplicatedStorage.Modules.SellValue` (ModuleScript)

**Interfaces:**
- Consumes: `ReplicatedStorage.Modules.BrainrotConfig`, `WorldProgression`, `MutationConfig`, `SizeConfig`, `PetConfig`
- Produces:
  - `SellValue.MULTIPLIER: number` (40)
  - `SellValue.BaseRate(name: string): number?`
  - `SellValue.OfBrainrot(entry: {Name: string, Mutation: string?, Size: string?}): number?`
  - `SellValue.OfPet(petId: string): number`
  - `SellValue.IsBulkEligible(entry): boolean`

- [ ] **Step 1: Write the failing test**

Run via `execute_luau`, `datamodel_type: "Edit"`:

```lua
local SV = require(game.ReplicatedStorage.Modules.SellValue)
local out, fails = {}, 0
local function check(label, got, want)
  local ok = tostring(got) == tostring(want)
  if not ok then fails += 1 end
  out[#out+1] = ("%-58s %s (got %s want %s)"):format(label, ok and "PASS" or "FAIL", tostring(got), tostring(want))
end
local E = function(m, s) return { Name = "Antonio", Mutation = m, Size = s } end
check("MULTIPLIER is 40", SV.MULTIPLIER, 40)
check("Antonio base rate", SV.BaseRate("Antonio"), 0.9)
check("unknown name has no base rate", SV.BaseRate("Not A Brainrot"), nil)
check("plain Antonio", SV.OfBrainrot(E(nil, nil)), 36)
check("Golden = 2x", SV.OfBrainrot(E("Golden", nil)), 72)
check("Massive = 8x", SV.OfBrainrot(E(nil, "Massive")), 288)
check("Golden Massive = 16x", SV.OfBrainrot(E("Golden", "Massive")), 576)
check("Angel Massive = 760x", SV.OfBrainrot(E("Angel", "Massive")), 27360)
check("unpriceable copy is nil", SV.OfBrainrot({ Name = "Gelatini Renna" }), nil)
check("bulk eligible: plain", SV.IsBulkEligible(E(nil, nil)), true)
check("bulk NOT eligible: mutated", SV.IsBulkEligible(E("Golden", nil)), false)
check("bulk NOT eligible: sized", SV.IsBulkEligible(E(nil, "Huge")), false)
check("bulk NOT eligible: favourited", SV.IsBulkEligible({ Name = "Antonio", Fav = true }), false)
check("bulk NOT eligible: placed", SV.IsBulkEligible({ Name = "Antonio", PadIndex = 3 }), false)
check("bulk NOT eligible: unpriceable", SV.IsBulkEligible({ Name = "Gelatini Renna" }), false)
out[#out+1] = fails == 0 and "ALL PASS" or (fails .. " FAILURES")
return table.concat(out, "\n")
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: an error, because `SellValue` does not exist yet.

- [ ] **Step 3: Create the module**

`multi_edit` with `file_path: "game.ReplicatedStorage.Modules.SellValue"`, `className: "ModuleScript"`, first edit `old_string: ""`:

```lua
--!strict
-- SellValue: the ONE definition of what a thing is worth when sold.
--
-- Before this module the formula lived in SellHandler AND in ClientMain, and the
-- two drifted -- the sell row advertised a species base price while the server
-- paid a per-copy price. Any future consumer must call this rather than
-- recompute; that is the whole point of the file.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)

local SellValue = {}

SellValue.MULTIPLIER = 40

-- EVERY WORLD. Built from BrainrotConfig alone this covers World 1 only, which
-- priced the tundra/gardens exclusives at nil. Valley first so a shared name
-- keeps its World 1 rate.
local rateByName: { [string]: number } = {}
for _, entry in ipairs(BrainrotConfig) do
	rateByName[entry.Name] = entry.CashPerSecond
end
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	for _, e in ipairs((world and world.Pool) or {}) do
		if rateByName[e.Name] == nil then
			rateByName[e.Name] = e.CashPerSecond
		end
	end
end

function SellValue.BaseRate(name: string): number?
	return rateByName[name]
end

-- Intrinsic value of ONE copy. Mutation and size are the two axes that belong to
-- the item; IncomeLoop's rebirth/upgrade/pet/pass multipliers belong to the
-- PLAYER and are excluded on purpose -- folding them in would make one brainrot
-- worth different amounts to different sellers.
-- Floors per COPY so a summed total is an exact integer (see the 2026-08-19
-- float-dust note in GrantCash).
function SellValue.OfBrainrot(entry): number?
	local base = rateByName[entry.Name]
	if base == nil then return nil end
	return math.floor(base
		* Mutations.Mult(entry.Mutation)
		* Sizes.Mult(entry.Size)
		* SellValue.MULTIPLIER)
end

function SellValue.OfPet(petId: string): number
	return PetConfig.SellValue(petId)
end

-- The bulk-safety predicate, in ONE place so the quick-sell bar, per-species
-- SELL ALL and the server agree by construction.
-- Sized copies are held back as well as mutated ones (owner decision
-- 2026-08-20): a plain Massive is 8x, and no bulk button should ever take that.
function SellValue.IsBulkEligible(entry): boolean
	if entry.Fav then return false end
	if entry.PadIndex ~= nil then return false end
	if entry.Mutation ~= nil then return false end
	if entry.Size ~= nil then return false end
	return rateByName[entry.Name] ~= nil
end

return SellValue
```

- [ ] **Step 4: Run the test again and confirm every case passes**

Expected: `ALL PASS`. If `Antonio base rate` fails, the roster changed — read the real value from `BrainrotConfig` and update the expectation rather than the module.

- [ ] **Step 5: Compile-gate**

```lua
local s = game.ReplicatedStorage.Modules.SellValue
local fn, err = loadstring(s.Source)
return fn and ("OK " .. #s.Source .. " chars") or ("FAIL " .. tostring(err))
```

---

### Task 2: `SellHandler` consumes `SellValue`, gains the guard and the new payload forms

**Files:**
- Modify: `game.ServerScriptService.Modules.SellHandler`
- Backup first into `ServerStorage.AuditBackups.PreSellShop_2026_08_20`

**Interfaces:**
- Consumes: `SellValue.OfBrainrot`, `SellValue.IsBulkEligible` (Task 1)
- Produces: `SellBrainrot` accepting `{Name, Mode="One"}`, `{Name, Mode="All"}`, `{Uids={...}}`, `{Mode="Duplicates"}`

- [ ] **Step 1: Write the failing test for the selection sets**

The handler body is a closure and cannot be called directly, so test the *selection rules* as pure functions first. Add them to `SellValue` in Step 3 and assert here:

```lua
local SV = require(game.ReplicatedStorage.Modules.SellValue)
local out, fails = {}, 0
local function check(l, g, w)
  local ok = tostring(g) == tostring(w); if not ok then fails += 1 end
  out[#out+1] = ("%-52s %s (got %s want %s)"):format(l, ok and "PASS" or "FAIL", tostring(g), tostring(w))
end
local inv = {
  { Uid = "1", Name = "Antonio" },
  { Uid = "2", Name = "Antonio", Mutation = "Golden" },
  { Uid = "3", Name = "Antonio", Size = "Massive" },
  { Uid = "4", Name = "Antonio", Fav = true },
  { Uid = "5", Name = "Antonio", PadIndex = 2 },
  { Uid = "6", Name = "Carloo" },
  { Uid = "7", Name = "Gelatini Renna" },
}
local sel, held = SV.SelectBulk(inv, nil)
check("Duplicates picks only plain sellable", #sel, 2)
-- 5, not 3: uid2 mutated, uid3 sized, uid4 favourited, uid5 placed, uid7 unpriceable.
-- (Corrected 2026-08-20 during execution — the original expectation was an arithmetic slip.)
check("Duplicates held-back count", held, 5)
local sel2 = SV.SelectBulk(inv, "Antonio")
check("All(Antonio) picks 1", #sel2, 1)
check("All(Antonio) picks uid 1", sel2[1].Uid, "1")
local one = SV.SelectCheapest(inv, "Antonio")
check("One(Antonio) takes the plain copy", one and one.Uid, "1")
local inv2 = { { Uid = "a", Name = "Antonio", Mutation = "Golden", Size = "Massive" }, { Uid = "b", Name = "Antonio", Mutation = "Golden" } }
check("One is not size-blind", SV.SelectCheapest(inv2, "Antonio").Uid, "b")
out[#out+1] = fails == 0 and "ALL PASS" or (fails .. " FAILURES")
return table.concat(out, "\n")
```

- [ ] **Step 2: Run it and confirm it fails**

Expected: `attempt to call a nil value (field 'SelectBulk')`.

- [ ] **Step 3: Add the selection helpers to `SellValue`**

Insert above `return SellValue`:

```lua
-- Selection rules live here, not in the handler, so the client can show exactly
-- what the server will take without duplicating the logic.
-- `name` nil = every species (the quick-sell set); a name = that species only.
-- Returns the chosen entries plus how many were held back for being favourited,
-- placed, mutated, oversized or unpriceable.
function SellValue.SelectBulk(entries, name: string?)
	local chosen, held = {}, 0
	for _, e in ipairs(entries) do
		if name == nil or e.Name == name then
			if SellValue.IsBulkEligible(e) then
				chosen[#chosen + 1] = e
			else
				held += 1
			end
		end
	end
	return chosen, held
end

-- The least valuable UNFAVOURITED, UNPLACED copy of one species, ranked by full
-- value. Ranking by Mutations.Mult alone was size-blind and could hand over the
-- Massive instead of the plain copy.
function SellValue.SelectCheapest(entries, name: string)
	local best, bestValue
	for _, e in ipairs(entries) do
		if e.Name == name and e.PadIndex == nil and not e.Fav then
			local v = SellValue.OfBrainrot(e)
			if v ~= nil and (bestValue == nil or v < bestValue) then
				best, bestValue = e, v
			end
		end
	end
	return best
end
```

- [ ] **Step 4: Run the test and confirm every case passes**

Expected: `ALL PASS`.

- [ ] **Step 5: Rewrite the handler body to use them**

Replace the whole `remotes.SellBrainrot.OnServerEvent:Connect(function(player, payload)` body. The new shape:

```lua
	remotes.SellBrainrot.OnServerEvent:Connect(function(player, payload)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		if typeof(payload) ~= "table" then return end

		-- READ-ONLY SESSION GUARD. A failed DataStore load serves a DEFAULT
		-- profile and every write is discarded at logout, so selling here would
		-- destroy the brainrot and hand back cash that never persists.
		-- PetHandler.Sell has always guarded this; this path did not.
		if data.__noSave then
			remotes.SellResult:FireClient(player, { Success = false,
				Message = "Your profile did not load \u{2014} rejoin before selling." })
			return
		end

		local mode = payload.Mode
		local chosen, held = {}, 0
		if type(payload.Uids) == "table" then
			local want = {}
			for _, u in ipairs(payload.Uids) do want[u] = true end
			for _, e in ipairs(data.Brainrots) do
				if want[e.Uid] and e.PadIndex == nil and not e.Fav
					and SellValue.OfBrainrot(e) ~= nil then
					chosen[#chosen + 1] = e
				end
			end
		elseif mode == "Duplicates" then
			chosen, held = SellValue.SelectBulk(data.Brainrots, nil)
		elseif mode == "All" then
			if typeof(payload.Name) ~= "string" then return end
			chosen, held = SellValue.SelectBulk(data.Brainrots, payload.Name)
		else
			if typeof(payload.Name) ~= "string" then return end
			local one = SellValue.SelectCheapest(data.Brainrots, payload.Name)
			if one then chosen[1] = one end
		end

		if #chosen == 0 then
			remotes.SellResult:FireClient(player, { Success = false,
				Message = held > 0
					and ("Nothing there to bulk sell \u{2014} %d copies are mutated, oversized or locked. Sell those one at a time."):format(held)
					or "You don't own anything sellable there." })
			return
		end

		local sellSet = {}
		for _, e in ipairs(chosen) do sellSet[e] = true end
		local totalValue, totalSold = 0, 0
		local remaining = {}
		for _, entry in ipairs(data.Brainrots) do
			if sellSet[entry] then
				totalSold += 1
				totalValue += (SellValue.OfBrainrot(entry) or 0)
				PlayerDataManager.DrainPending(player, entry, data)
				if MintRegistry.IsTracked(rarityByName[entry.Name], entry.Mutation) then
					pcall(MintRegistry.Burn, entry.Name, entry.Mutation, 1)
				end
			else
				remaining[#remaining + 1] = entry
			end
		end
		data.Brainrots = remaining
		PlayerDataManager.GrantCash(data, totalValue)

		remotes.SellResult:FireClient(player, {
			Success = true,
			Message = ("Sold %d for %s%s"):format(totalSold, NumberFormat.Cash(totalValue),
				held > 0 and (" (" .. held .. " mutated or oversized kept)") or ""),
			Amount = totalValue,
		})
		InventoryHandler.SyncBackpack(player)
		PlayerDataManager.PushUpdate(player)
	end)
```

Add `local SellValue = require(ReplicatedStorage.Modules.SellValue)` to the requires, and delete the now-unused `cashPerSecondByName` table and the old `Mutations`/`Sizes` requires if nothing else uses them (`rarityByName` is still needed by the MintRegistry call).

- [ ] **Step 6: Compile-gate and byte-scan**

```lua
local s = game.ServerScriptService.Modules.SellHandler
local src = s.Source
local fn, err = loadstring(src)
local marks = { "SellValue.SelectBulk", "SellValue.SelectCheapest", "data.__noSave",
  "mutated or oversized kept", "SellValue.OfBrainrot" }
local miss = {}
for _, m in ipairs(marks) do if not src:find(m, 1, true) then miss[#miss+1] = m end end
return ("compile=%s  missing=%s  sellValueEach=%d"):format(
  fn and "OK" or tostring(err), #miss == 0 and "none" or table.concat(miss, ","),
  select(2, src:gsub("sellValueEach", "")))
```

Expected: `compile=OK  missing=none  sellValueEach=0`.

---

### Task 3: `PetHandler.SellMany`

**Files:**
- Modify: `game.ServerScriptService.Modules.PetHandler` (back up first)

**Interfaces:**
- Consumes: existing `PetHandler.Sell(player, uid) -> boolean`
- Produces: `PetHandler.SellMany(player, uids: {string}) -> number, number` (sold count, total cash)

- [ ] **Step 1: Add `SellMany` above the `return PetHandler` line**

```lua
-- Bulk sell for the sell counter's pets tab. Deliberately loops the single-uid
-- path rather than reimplementing it, so the equipped-pet refusal and the
-- __noSave guard cannot drift between the two.
function PetHandler.SellMany(player, uids)
	if type(uids) ~= "table" then return 0, 0 end
	local sold, total = 0, 0
	for _, uid in ipairs(uids) do
		local data = PlayerDataManager.Get(player)
		local before = data and data.Cash or 0
		if PetHandler.Sell(player, uid) then
			sold += 1
			local after = (PlayerDataManager.Get(player) or {}).Cash or before
			total += (after - before)
		end
	end
	return sold, total
end
```

- [ ] **Step 2: Wire the remote**

Beside the existing `sellPetRemote.OnServerEvent` connection, accept a table:

```lua
	sellPetRemote.OnServerEvent:Connect(function(player, uidOrList)
		if type(uidOrList) == "table" then
			PetHandler.SellMany(player, uidOrList)
		else
			PetHandler.Sell(player, uidOrList)
		end
	end)
```

- [ ] **Step 3: Compile-gate**

```lua
local s = game.ServerScriptService.Modules.PetHandler
local fn, err = loadstring(s.Source)
return ("compile=%s SellMany=%s"):format(fn and "OK" or tostring(err),
  tostring(s.Source:find("function PetHandler.SellMany", 1, true) ~= nil))
```

Expected: `compile=OK SellMany=true`.

---

### Task 4: External panel-open hook in `GameHUDClient`

**Files:**
- Modify: `game.StarterPlayer.StarterPlayerScripts.GameHUDClient` (back up first)

**Interfaces:**
- Produces: setting player attribute `HudPanelRequest = "<panelId>"` opens that panel from any LocalScript.

`openPanel` is a local in `GameHUDClient`, so `ClientMain` cannot call it. A player ATTRIBUTE is this codebase's documented idiom for cross-LocalScript handoff (see the `IntroDailyDone` note) because a listener that connects late still sees a value already set. `panelModules` is populated from the `GameHUDPanels` folder rather than `RAIL_ORDER`, so a panel with no rail tile opens fine.

- [ ] **Step 1: Insert the watcher immediately after `openPanel`'s definition ends**

```lua
-- EXTERNAL OPEN HOOK. Panels are normally opened by their rail tile, but the
-- sell counter is opened by a ProximityPrompt in ClientMain, which cannot see
-- this local. An attribute rather than a BindableEvent for the reason recorded
-- at the join sequence below: a late listener still sees a value already set.
-- Cleared immediately so the same id can be requested twice in a row.
player:GetAttributeChangedSignal("HudPanelRequest"):Connect(function()
	local id = player:GetAttribute("HudPanelRequest")
	if type(id) ~= "string" or id == "" then return end
	player:SetAttribute("HudPanelRequest", "")
	openPanel(id)
end)
```

- [ ] **Step 2: Compile-gate**

```lua
local s = game.StarterPlayer.StarterPlayerScripts.GameHUDClient
local fn, err = loadstring(s.Source)
return ("compile=%s hook=%s"):format(fn and "OK" or tostring(err),
  tostring(s.Source:find("HudPanelRequest", 1, true) ~= nil))
```

Expected: `compile=OK hook=true`. A `FAIL` mentioning local registers means the watcher added chunk-level locals — move them inside the callback.

---

### Task 5: `SellPanel` shell, tabs and quick-sell bar

**Files:**
- Create: `game.StarterPlayer.StarterPlayerScripts.GameHUDPanels.SellPanel` (ModuleScript)

**Interfaces:**
- Consumes: `PanelChrome.shell`, `PanelChrome.pill`, `PanelChrome.sectionHead`, `SellValue.SelectBulk`, `SellValue.OfBrainrot`
- Produces: module table `{ Id = "sell", Build = function(ctx) -> Frame }`

The `GameHUDPanels` contract (copied from `BackpackPanel`'s header): return `{ Id = ..., Build = function(ctx) -> Frame }`. `Build` is called ONCE lazily on first open. The shell parents the returned Frame into `ctx.host` and owns `Visible` — this module must never set its own `Parent` or drive its own open/close animation.

- [ ] **Step 1: Create the module skeleton with the contract and a live state snapshot**

```lua
--!strict
-- SellPanel: Marco's counter. A GameHUDPanels consumer module.
-- Contract: { Id = "sell", Build = function(ctx) -> Frame }. Build runs ONCE on
-- first open; GameHUDClient parents the frame and owns Visible. Never set
-- Parent here and never animate open/close here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PanelChrome = require(ReplicatedStorage.Modules.UIKit.PanelChrome)
local SellValue = require(ReplicatedStorage.Modules.SellValue)
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local SellPanel = { Id = "sell" }

local state = { Brainrots = {}, Pets = {} }
local refresh   -- forward declaration; assigned in Build

remotes.DataUpdated.OnClientEvent:Connect(function(snap)
	if typeof(snap) ~= "table" then return end
	state.Brainrots = snap.Brainrots or state.Brainrots
	state.Pets = snap.Pets or state.Pets
	if refresh then refresh() end
end)

function SellPanel.Build(ctx)
	-- PanelChrome.shell returns the shell API TABLE, not a Frame:
	-- `shellApi = { root = root, header = header, body = body, close = ... }`.
	-- Build's contract is to return a Frame, so return `shell.root`.
	-- (Corrected 2026-08-20 during execution — the original skeleton returned the
	-- API table, which would not have satisfied the GameHUDPanels contract.)
	local shell = PanelChrome.shell({
		name = "SellPanel", title = "MARCO THE BUYER", key = "shop",
		scroll = false,
	})
	return shell.root
end

return SellPanel
```

- [ ] **Step 2: Verify it registers and opens**

In Play, set the attribute and read back what mounted:

```lua
game.Players.LocalPlayer:SetAttribute("HudPanelRequest", "sell")
task.wait(1)
local host = game.Players.LocalPlayer.PlayerGui:FindFirstChild("GameHUD")
local found
for _, d in ipairs(host:GetDescendants()) do
  if d.Name == "SellPanel" then found = d end
end
return found and ("mounted %dx%d visible=%s"):format(found.AbsoluteSize.X, found.AbsoluteSize.Y, tostring(found.Visible))
  or "SellPanel NOT mounted"
```

Expected: a non-zero size and `visible=true`.

- [ ] **Step 3: Add the tab bar**

Use `shellApi.addHeaderTabs({ {text="BRAINROTS", width=140}, {text="PETS", width=110} }, 1, onChanged)` returned by `PanelChrome.shell`. Store the selected index in a local and have `onChanged` set it then call `refresh()`.

- [ ] **Step 4: Add the quick-sell bar**

A `PanelChrome.plate` holding a `PanelChrome.read` label and a `PanelChrome.pill`. Recompute on every `refresh()`:

```lua
	local chosen, held = SellValue.SelectBulk(state.Brainrots, nil)
	local total = 0
	for _, e in ipairs(chosen) do total += (SellValue.OfBrainrot(e) or 0) end
	quickLabel.Text = ("Sell %d duplicates \u{2014} %s"):format(#chosen, NumberFormat.Cash(total))
	quickNote.Text = ("%d held back \u{2014} mutated, oversized, placed or locked"):format(held)
	quickPill.Visible = #chosen > 0
```

- [ ] **Step 5: Add the confirm dialog before firing**

The bulk action is irreversible, so the pill opens a confirm plate with the same count and total and a CONFIRM / CANCEL pair. CONFIRM fires `remotes.SellBrainrot:FireServer({ Mode = "Duplicates" })`.

- [ ] **Step 6: Compile-gate**

```lua
local s = game.StarterPlayer.StarterPlayerScripts.GameHUDPanels.SellPanel
local fn, err = loadstring(s.Source)
return fn and ("OK " .. #s.Source) or ("FAIL " .. tostring(err))
```

---

### Task 6: Species grid and search

**Files:**
- Modify: `GameHUDPanels.SellPanel`

**Interfaces:**
- Consumes: `SellValue.OfBrainrot`, `SellValue.BaseRate`, `BrainrotThumb.add`
- Produces: `openSpecies(name)` called by a tile click (Task 7 implements the drill-down it opens)

- [ ] **Step 1: Group the snapshot into species**

```lua
	local counts, copies, order = {}, {}, {}
	for _, e in ipairs(state.Brainrots) do
		if e.PadIndex == nil then
			if counts[e.Name] == nil then
				counts[e.Name] = 0; copies[e.Name] = {}; order[#order + 1] = e.Name
			end
			counts[e.Name] += 1
			table.insert(copies[e.Name], e)
		end
	end
```

- [ ] **Step 2: Render one tile per species into a `UIGridLayout`**

Each tile: `BrainrotThumb.add` for the art, a count badge, and a violet star (`Color3.fromRGB(193, 76, 255)`) when any copy in `copies[name]` has a non-nil `Mutation`. Tile click calls `openSpecies(name)`.

- [ ] **Step 3: Render unpriceable species greyed and unclickable**

```lua
		if SellValue.BaseRate(name) == nil then
			tile.BackgroundTransparency = 0.5
			label.Text = "can't be sold"
			hit.Active = false
		end
```

This is what makes the two ghost entries visible instead of silently absent.

- [ ] **Step 4: Add the search box**

A `TextBox` above the grid; on `:GetPropertyChangedSignal("Text")` set a `filter` local to the lowercased text and call `refresh()`. In the tile loop skip any name whose lowercased form lacks the filter substring.

- [ ] **Step 5: Verify against the live save**

In Play with the panel open:

```lua
local sp -- find SellPanel frame as in Task 5 Step 2
local tiles = 0
for _, d in ipairs(sp:GetDescendants()) do if d.Name == "SpeciesTile" then tiles += 1 end end
return ("tiles=%d (expect 104 for the reference save)"):format(tiles)
```

---

### Task 7: Drill-down with multi-select

**Files:**
- Modify: `GameHUDPanels.SellPanel`

**Interfaces:**
- Consumes: `SellValue.OfBrainrot`
- Produces: fires `remotes.SellBrainrot:FireServer({ Uids = {...} })`

- [ ] **Step 1: Build the copy list for one species**

One row per entry in `copies[name]`, each showing its mutation and size labels and `SellValue.OfBrainrot(entry)`. Favourited and placed copies render with the reason and are not selectable.

- [ ] **Step 2: Add selection state and a running total**

```lua
	local selected = {}   -- uid -> true
	local function totalSelected()
		local n, sum = 0, 0
		for _, e in ipairs(copies[currentName]) do
			if selected[e.Uid] then n += 1; sum += (SellValue.OfBrainrot(e) or 0) end
		end
		return n, sum
	end
```

The footer pill reads `("Sell %d \u{2014} %s"):format(n, NumberFormat.Cash(sum))` and is hidden when `n == 0`.

- [ ] **Step 3: Fire the sale**

```lua
		local uids = {}
		for _, e in ipairs(copies[currentName]) do
			if selected[e.Uid] then uids[#uids + 1] = e.Uid end
		end
		remotes.SellBrainrot:FireServer({ Uids = uids })
		selected = {}
```

- [ ] **Step 4: Verify advertised equals paid for the drill-down**

Assert in Edit mode that the footer sum equals what the server would pay for the same uids, using `SellValue.OfBrainrot` on both sides over a constructed inventory of every mutation × size combination.

---

### Task 8: Pets tab

**Files:**
- Modify: `GameHUDPanels.SellPanel`

**Interfaces:**
- Consumes: `SellValue.OfPet`, `PetConfig.Pets`
- Produces: fires `remotes.SellPet:FireServer(uids)` (table form added in Task 3)

- [ ] **Step 1: Render a grid of owned pets**

One tile per entry in `state.Pets`, showing the pet name and `SellValue.OfPet(pet.Id)`. Equipped pets (uid present in `state.PetSlots`) render greyed with "equipped" and are not selectable.

- [ ] **Step 2: Reuse the same multi-select and footer**

Pets have no mutation or size axis, so there is no drill-down — selection happens directly on the grid.

- [ ] **Step 3: Fire the sale**

```lua
		remotes.SellPet:FireServer(uids)
```

- [ ] **Step 4: Compile-gate**

---

### Task 9: Retire the old `SellFrame` from `ClientMain`

**Files:**
- Modify: `game.StarterPlayer.StarterPlayerScripts.ClientMain` (back up first)

**Interfaces:**
- Consumes: the `HudPanelRequest` attribute (Task 4)

- [ ] **Step 1: Delete `buildSellList` and the `SellFrame` wiring**

Remove `buildSellList` entirely, the `sellFrame`/`sellList`/`sellCloseButton`/`sellEmptyLabel` locals, the `SideRail.registerPanel(sellFrame)` call, the sell entry in the frame-config list, the `sellCloseButton` handler, and the `buildSellList()` call inside `applySnapshot`. This frees several chunk-level locals, which matters given the 200-local ceiling.

- [ ] **Step 2: Point `openSell` at the new panel**

```lua
local function openSell(part)
	SoundKit.play("shopCoins", nil, { volume = 0.4 })
	MerchantDialog.Show("Marco the Buyer", {
		"Brainrots to sell? I pay top dollar!",
	}, { CF.amber1, CF.amber2 }, function()
		player:SetAttribute("HudPanelRequest", "sell")
	end, part)
end
```

- [ ] **Step 3: Remove the walk-away auto-close for `sellFrame`**

The Heartbeat block referencing `sellFrame.Visible` must go; the panel is now closed by the shell's own close button like every other panel.

- [ ] **Step 4: Compile-gate and confirm the old symbols are gone**

```lua
local s = game.StarterPlayer.StarterPlayerScripts.ClientMain
local src = s.Source
local fn, err = loadstring(src)
return ("compile=%s sellFrame=%d buildSellList=%d SELL_MULTIPLIER=%d"):format(
  fn and "OK" or tostring(err),
  select(2, src:gsub("sellFrame", "")),
  select(2, src:gsub("buildSellList", "")),
  select(2, src:gsub("SELL_MULTIPLIER", "")))
```

Expected: `compile=OK sellFrame=0 buildSellList=0 SELL_MULTIPLIER=0`.

---

### Task 10: Whole-inventory advertised-equals-paid sweep

**Files:**
- No production changes. Verification only.

- [ ] **Step 1: Run the randomised agreement sweep in Edit mode**

Build 4,000 randomised inventories across every mutation × size × several base rates. For each, assert that what the panel would display equals what the handler would pay, for all four payload forms. Both sides must call `SellValue`; if either recomputes a price locally, that is the bug this task exists to catch.

- [ ] **Step 2: Confirm zero mismatches**

Expected: `SELL 1 mismatches 0`, `SELL ALL mismatches 0`, `Duplicates mismatches 0`, `Uids mismatches 0`.

- [ ] **Step 3: Live check in Play**

Open the panel via `HudPanelRequest`, confirm the tile count matches the number of distinct unplaced species with a price, confirm the quick-sell bar's count equals `#SellValue.SelectBulk(snapshot.Brainrots, nil)`, and confirm the console is clean.

- [ ] **Step 4: Report what is unsaved**

Every change is unsaved. List the touched scripts and the backup folder so the owner can decide when to save.

---

## Self-Review

**Spec coverage:** Tabs (T5), quick-sell bar with confirm (T5), species grid (T6), search (T6), drill-down multi-select (T7), pets tab (T8), unsellable shown not hidden (T6 S3), `SellValue` module (T1), `Uids`/`Duplicates` forms (T2), `PetHandler.SellMany` (T3), `__noSave` guard (T2 S5), bulk holds back sized copies (T1 `IsBulkEligible`), advertised-equals-paid (T10), panel moved out of ClientMain (T5, T9). `IncludeMutated` retirement is covered by T2 S5 replacing the whole handler body.

**Known gap:** the spec's "partial failure in a multi-select" edge case is only partly handled — the `Uids` path silently drops uids that are favourited, placed or unpriceable rather than naming them. Task 7 Step 3 should be extended to report the dropped count if the owner wants it surfaced; left as-is it fails safe.

**Type consistency:** `SellValue.OfBrainrot` returns `number?` everywhere and every call site coerces with `or 0` before summing. `SelectBulk` returns `(entries, heldCount)` in T2 S3 and is destructured that way in T2 S5 and T5 S4. `SellMany` returns `(sold, total)` and no caller currently uses the return.
