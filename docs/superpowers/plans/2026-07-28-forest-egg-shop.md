# Forest Egg Shop + Darrels + Pets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the EggStall into a live feature: 5 darrel-priced gacha eggs hatching 10 forest-exclusive brainrots, plus the darrel currency (quests/Robux) and a disabled-until-content pet system.

**Architecture:** Approach B from the spec — a self-contained subsystem (`EggConfig`, `EggHandler`, `DarrelService`, `ProductRegistry`, `PetConfig`, `PetHandler`, `EggShopClient`) with narrow seams: +10 `Weight = 0` entries in BrainrotConfig, grants via `BrainrotMover.Give`, 3 one-line quest-event mirrors beside existing `SeasonPassHandler.Notify` calls, and 2 one-line pet-boost multipliers.

**Tech Stack:** Roblox Studio via MCP (`execute_luau` Edit datamodel, `script_read`/`multi_edit`), Luau, existing UITheme (Camp tokens) + BrainrotThumb + RarityFX.

## Global Constraints

- Spec: `docs/specs/2026-07-28-forest-egg-shop-design.md`. Its numbers (odds, prices, CPS) are copied verbatim below — if a discrepancy appears, the spec wins.
- ALL Studio work through MCP. `execute_luau` ALWAYS `datamodel_type: "Edit"` except the Play-verification task. NEVER `start_stop_play` outside Task 12. NEVER save to cloud or publish — the user owns that.
- Before editing any EXISTING script: `script_read` the region immediately before the edit, anchor on exact strings (grep line numbers ≠ read line numbers), and clone the script to `ServerStorage.AuditBackups.<Name>_pre_eggs` first. New scripts need no backup.
- The MCP bridge VM's `require()` cache persists across calls and across agents. To verify a module fresh, require a CLONE parented beside the original, then destroy it.
- Never touch: `UIStyle` (collaborator's), ThrowHandler rock-skin code, TradingCenter booths, plot `Platform` parts. ThrowHandler/IncomeLoop/FusionHandler get ONLY the exact one-line insertions specified in Tasks 3 and 11.
- Schema additions require BOTH a `defaultData` field AND a nil-migration line in `PlayerDataManager.Load` (follow the existing DailyStreak/SeasonXP migration pattern found in that file).
- "Probe" = an `execute_luau` assertion snippet. TDD cycle here: run probe (expect FAIL) → implement → run probe (expect PASS).
- After each task: dump each created/edited script's `.Source` to `game-src/eggs/<Name>.lua` (Write tool) and `git commit` with the message given in the task.
- New world instances: Anchored = true, CanCollide = false, CanQuery = false, Massless where unanchored parts are required (pet rigs).
- Player-facing text: `UITheme.Font`, cafe tokens — ink rgb(62,34,19), cream rgb(247,235,216), card cream rgb(245,220,192), gold rgb(255,216,107), green confirm, never black.

---

### Task 1: BrainrotConfig — the 10 forest entries

**Files:**
- Modify: `game.ReplicatedStorage.Modules.BrainrotConfig` (append entries near the Chim/Maxwell zero-weight block)
- Snapshot: `game-src/eggs/BrainrotConfig.lua`

**Interfaces:**
- Produces: 10 config entries `{ Name, Rarity, CashPerSecond, Weight = 0, Source = "ForestEgg" }` — every later task refers to creatures ONLY by these exact names.

- [ ] **Step 1: Failing probe** — run in execute_luau (Edit):

```lua
local cfgSrc = game.ReplicatedStorage.Modules.BrainrotConfig
local clone = cfgSrc:Clone(); clone.Parent = cfgSrc.Parent
local cfg = require(clone)
local want = { ["Cervolino Antlerino"]=true, ["Fanghetto Palunko"]=true, ["Strigolino Hootini"]=true,
  ["Rospino Bavaglio"]=true, ["Corvacchio Beccarino"]=true, ["Ceppone Zampalunga"]=true,
  ["Alcione Trombettone"]=true, ["Lucciolone Pantanini"]=true, ["Gufocervo Stiltini"]=true,
  ["Muschione Cornaluna"]=true }
local found = 0
for _, e in ipairs(cfg.List or cfg) do if want[e.Name] then found += 1 end end
clone:Destroy()
return "forest entries found: " .. found .. " (want 10)"
```

Expected: `forest entries found: 0`.

- [ ] **Step 2: Pre-flight collision check** (MUST pass before writing anything):

```lua
-- (a) none of the 10 names is already a live config key
-- (b) none of the 10 names appears as a KEY or VALUE in PlayerDataManager RENAMES
local src = game.ServerScriptService.Modules.PlayerDataManager.Source
local names = { "Cervolino Antlerino","Fanghetto Palunko","Strigolino Hootini","Rospino Bavaglio",
  "Corvacchio Beccarino","Ceppone Zampalunga","Alcione Trombettone","Lucciolone Pantanini",
  "Gufocervo Stiltini","Muschione Cornaluna" }
local hits = {}
for _, n in ipairs(names) do if src:find(n, 1, true) then table.insert(hits, n) end end
return #hits == 0 and "CLEAN" or ("COLLISIONS: " .. table.concat(hits, ", "))
```

Expected: `CLEAN`. If not, STOP and report — do not rename silently.

- [ ] **Step 3: Implement** — read BrainrotConfig's entry format (`script_read` the Maxwell/Chim block), back up the script, then append after that block, matching its exact table style:

```lua
	-- ══ FOREST EGG EXCLUSIVES (World 1) ═══════════════════════════════════
	-- Weight = 0 IS LOAD-BEARING (same pattern as Chim/Secret Pete/Maxwell):
	-- throws can NEVER roll these. They enter the game only via EggHandler ->
	-- BrainrotMover.Give. Source tag drives the Index "FOREST EGG" badge.
	{ Name = "Cervolino Antlerino", Rarity = "Epic",      CashPerSecond = 800,   Weight = 0, Source = "ForestEgg" },
	{ Name = "Fanghetto Palunko",   Rarity = "Epic",      CashPerSecond = 870,   Weight = 0, Source = "ForestEgg" },
	{ Name = "Strigolino Hootini",  Rarity = "Epic",      CashPerSecond = 950,   Weight = 0, Source = "ForestEgg" },
	{ Name = "Rospino Bavaglio",    Rarity = "Legendary", CashPerSecond = 4800,  Weight = 0, Source = "ForestEgg" },
	{ Name = "Corvacchio Beccarino",Rarity = "Legendary", CashPerSecond = 5400,  Weight = 0, Source = "ForestEgg" },
	{ Name = "Ceppone Zampalunga",  Rarity = "Legendary", CashPerSecond = 6000,  Weight = 0, Source = "ForestEgg" },
	{ Name = "Alcione Trombettone", Rarity = "Mythic",    CashPerSecond = 25000, Weight = 0, Source = "ForestEgg" },
	{ Name = "Lucciolone Pantanini",Rarity = "Mythic",    CashPerSecond = 29000, Weight = 0, Source = "ForestEgg" },
	{ Name = "Gufocervo Stiltini",  Rarity = "Mythic",    CashPerSecond = 33000, Weight = 0, Source = "ForestEgg" },
	{ Name = "Muschione Cornaluna", Rarity = "Secret",    CashPerSecond = 60000, Weight = 0, Source = "ForestEgg" },
```

Also update the header comment `151 authored entries` → `161 authored entries`.

- [ ] **Step 4: Probe passes** — rerun Step 1, expect `found: 10`. Also assert per-tier weight sums are UNCHANGED (all zero-weight adds): rerun the weight-sum check from the economy audit — Common..Secret each still sum exactly 100000.

- [ ] **Step 5: Snapshot + commit**

```bash
git add game-src/eggs/BrainrotConfig.lua
git commit -m "eggs(1): 10 forest exclusives in BrainrotConfig, Weight=0, Source=ForestEgg"
```

---

### Task 2: The 10 creature models

**Files:**
- Create: 10 Models under `game.ReplicatedStorage.BrainrotModels` (exact config names)
- Reference: `docs/design-handoff/forest-eggs/forest-brainrots-sprite.png` (5×2 grid; row 1 L→R = creatures 1–5, row 2 L→R = 6–10)
- Snapshot: `game-src/eggs/models-build-log.md` (part counts + screenshots taken)

**Interfaces:**
- Consumes: names from Task 1.
- Produces: renderable Models, 1:1 with config (restores the models==config invariant broken by Task 1 until this completes). Each: all parts Anchored, CanCollide=false, SmoothPlastic, a `PrimaryPart` torso part, 0 scripts, height 3–8 studs at authored scale, ≤ 90 parts.

Build voxel-style from Parts on a sky staging platform at `(0, 500, 0)` (create `Workspace._EggStaging` Part 80×1×80, Anchored; DELETE at task end). Per-creature body plans from the sprite:

| # | Name | Body plan (voxel cubes) | Palette (approx RGB) |
|---|---|---|---|
| 1 | Cervolino Antlerino | deer: 2×3×4 torso, 4 legs, small head, branching antlers (6–10 thin cubes each) | brown 128,84,48; cream face 224,214,186; antler tan 190,166,120 |
| 2 | Fanghetto Palunko | bog blob: 5×4×5 rounded green mound, one huge white eye offset-left, moss cap w/ red bud | swamp green 74,104,58; eye white 232,228,214; bud red 178,58,48 |
| 3 | Strigolino Hootini | hooded owl: 3×4×3 dark cloak body, big round pale face, black shades, orange beak nub | near-black 44,44,46; face 226,220,200; beak 226,140,50 |
| 4 | Rospino Bavaglio | frog: wide 6×3×5 flat body, two bulging eyes on top, pink tongue tab, front feet | frog green 78,110,66; eye white 230,226,208; tongue 196,92,92 |
| 5 | Corvacchio Beccarino | crow: 3×3×3 black round body, big orange flat beak, 2 orange legs | black 38,38,40; beak/legs 226,140,40 |
| 6 | Ceppone Zampalunga | walking log: horizontal 5×3×3 log w/ pale cut ends, 4 LONG thin legs (1×5×1), 3 pink mushrooms on top | bark 96,62,38; cut face 214,196,160; mushroom 196,110,110 |
| 7 | Alcione Trombettone | trumpet moose: deer body as #1 but bulkier, broad flat antlers, orange trumpet disc at mouth | brown 118,78,44; antler 178,152,108; trumpet 222,148,58 |
| 8 | Lucciolone Pantanini | firefly: 3×2×4 green-vest body, pale wings, 2 antennae ending in GLOW cubes (Neon 198,232,90), 6 thin dark legs | body 92,110,62; wings 216,208,184; glow Neon 198,232,90 |
| 9 | Gufocervo Stiltini | stilt owl: small dark owl body from #3, tiny antler nubs, 2 VERY long thin legs (1×7×1) | dark 52,52,50; face 216,208,186; legs 172,156,120 |
| 10 | Muschione Cornaluna | moss wraith: mossy 3×4×3 torso, pale owl face w/ green shades, 2 huge CRESCENT horns (curved from 8–10 cubes) meeting above head, thin arms | moss 86,98,60; face 210,204,180; horn 186,164,122 |

- [ ] **Step 1: Failing probe**

```lua
local folder = game.ReplicatedStorage.BrainrotModels
local names = { "Cervolino Antlerino","Fanghetto Palunko","Strigolino Hootini","Rospino Bavaglio",
  "Corvacchio Beccarino","Ceppone Zampalunga","Alcione Trombettone","Lucciolone Pantanini",
  "Gufocervo Stiltini","Muschione Cornaluna" }
local have = 0
for _, n in ipairs(names) do if folder:FindFirstChild(n) then have += 1 end end
return "models present: " .. have .. "/10"
```

Expected: `0/10`.

- [ ] **Step 2: Build each creature** on the staging platform (one `execute_luau` per creature, a `cube(model, size, cf, color)` helper making Anchored SmoothPlastic parts). After each: `screen_capture` from `(12, 506, 12)` looking at the model, compare against the sprite cell, iterate until the silhouette + palette read as the same character. Log part count per creature.

- [ ] **Step 3: Finalize each** — set `PrimaryPart` = torso, verify `#model:GetDescendants()` has 0 Scripts, `Model.Name` = exact config name, `PivotTo` origin, parent to `ReplicatedStorage.BrainrotModels`.

- [ ] **Step 4: Probe passes** (`10/10`) plus render + fit checks:

```lua
local Thumb = require(game.ReplicatedStorage.Modules.BrainrotThumb:Clone_ParentedBesideOriginal_SeeGlobalConstraints)
-- for each name: Thumb.master(name) returns a stripped clone (not nil);
-- bbox height 3..8, width/height ratio 0.3..4.0 (BrainrotSpawner box-fit range)
```

Also spawn ONE (Cervolino) through the real `BrainrotSpawner.Spawn` on a free pad, screenshot, remove — proves the placed path end-to-end (the roster-swap session set this precedent).

- [ ] **Step 5: Delete `Workspace._EggStaging`**, write `game-src/eggs/models-build-log.md`, commit:

```bash
git add game-src/eggs/models-build-log.md
git commit -m "eggs(2): 10 forest creature models built and render-verified"
```

---

### Task 3: DarrelService + schema + quest-event mirrors

**Files:**
- Create: `game.ServerScriptService.Modules.DarrelService` (ModuleScript)
- Modify: `game.ServerScriptService.Modules.PlayerDataManager` (schema), `game.ServerScriptService.Main` (Init), ThrowHandler + IncomeLoop (one-line mirrors — exact anchors below)
- Create: `game.ReplicatedStorage.Remotes.DarrelUpdate` (RemoteEvent)
- Snapshot: `game-src/eggs/DarrelService.lua`

**Interfaces:**
- Produces: `DarrelService.Get(player) -> number`, `DarrelService.Award(player, n, reason) -> ()`,
  `DarrelService.TrySpend(player, n, reason) -> boolean` (NO YIELDS), `DarrelService.Notify(player, kind, n)`
  with kinds `"Throw" | "Catch" | "Collect"`, `DarrelService.GetDailyState(player) -> { Day, Quests = {3}, Progress, Claimed }`.
- Consumes: `PlayerDataManager.Get/PushUpdate/Save`.

- [ ] **Step 1: Failing probe** — `game.ServerScriptService.Modules:FindFirstChild("DarrelService")` → nil; `PlayerDataManager.Source:find("Darrels = 0")` → nil.

- [ ] **Step 2: Schema.** Back up PlayerDataManager. In `defaultData` add (match the file's exact formatting):

```lua
	Darrels = 0,
	DarrelDaily = {},   -- { Day = utcDay, Progress = {kind counters}, Claimed = {questId=true} }
	EggsOpened = {},    -- { [eggId] = count }
	ReceiptLog = {},    -- last 50 Robux PurchaseIds (ProductRegistry dedupe)
	Pets = {},          -- { {Uid, Id, Boost={Type,Amount}} } — Task 11
	PetSlots = {},      -- equipped pet Uids — Task 11
```

And in `Load`'s nil-migration block, one line per field following the existing pattern, e.g. `if data.Darrels == nil then data.Darrels = 0 end` (and table fields `= data.X or {}`).

- [ ] **Step 3: Implement DarrelService** (full module):

```lua
-- DarrelService — the ONLY authority on darrel balance. Award/TrySpend never yield.
local Players = game:GetService("Players")
local PDM = require(script.Parent.PlayerDataManager)
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")

local M = {}

local QUEST_POOL = {
	{ Id = "throw25",   Kind = "Throw",   Target = 25,    Reward = 3, Text = "Skip 25 rocks" },
	{ Id = "throw60",   Kind = "Throw",   Target = 60,    Reward = 5, Text = "Skip 60 rocks" },
	{ Id = "catchEpic", Kind = "Catch",   Target = 1,     Reward = 4, Text = "Catch an Epic or better" },
	{ Id = "catch3",    Kind = "Catch",   Target = 3,     Reward = 5, Text = "Catch 3 Epic+ brainrots" },
	{ Id = "collect50k",Kind = "Collect", Target = 50000, Reward = 3, Text = "Collect $50k from the campfire" },
	{ Id = "collect250k",Kind = "Collect",Target = 250000,Reward = 5, Text = "Collect $250k from the campfire" },
}

local function utcDay() return math.floor(os.time() / 86400) end

-- 3 deterministic picks per UTC day (same slate for everyone; no Math.random at module scope)
local function slateFor(day)
	local rng = Random.new(day * 7919)
	local pool = table.clone(QUEST_POOL)
	local picks = {}
	for _ = 1, 3 do table.insert(picks, table.remove(pool, rng:NextInteger(1, #pool))) end
	return picks
end

local function daily(data)
	local d = utcDay()
	if not data.DarrelDaily or data.DarrelDaily.Day ~= d then
		data.DarrelDaily = { Day = d, Progress = {}, Claimed = {} }
	end
	return data.DarrelDaily
end

local function push(player, data)
	remotes.DarrelUpdate:FireClient(player, { Darrels = data.Darrels, Daily = M.GetDailyState(player) })
end

function M.Get(player)
	local data = PDM.Get(player); return data and data.Darrels or 0
end

function M.Award(player, n, reason)
	local data = PDM.Get(player); if not data then return end
	n = math.floor(n); if n <= 0 then return end
	data.Darrels += n
	print(("[Darrels] +%d -> %d %s (%s)"):format(n, data.Darrels, player.Name, reason))
	push(player, data); PDM.PushUpdate(player)
end

function M.TrySpend(player, n, reason)  -- NO YIELDS between check and deduct
	local data = PDM.Get(player); if not data then return false end
	n = math.floor(n)
	if n <= 0 or n ~= n or data.Darrels < n then return false end
	data.Darrels -= n
	print(("[Darrels] -%d -> %d %s (%s)"):format(n, data.Darrels, player.Name, reason))
	push(player, data); PDM.PushUpdate(player)
	return true
end

function M.Notify(player, kind, n)  -- mirrored beside SeasonPassHandler.Notify call sites
	local data = PDM.Get(player); if not data or data.__noSave then return end
	local dd = daily(data)
	dd.Progress[kind] = (dd.Progress[kind] or 0) + (n or 1)
	for _, q in ipairs(slateFor(dd.Day)) do
		if q.Kind == kind and not dd.Claimed[q.Id] and (dd.Progress[kind] or 0) >= q.Target then
			dd.Claimed[q.Id] = true
			M.Award(player, q.Reward, "daily:" .. q.Id)
		end
	end
end

function M.GetDailyState(player)
	local data = PDM.Get(player); if not data then return nil end
	local dd = daily(data)
	local out = { Day = dd.Day, Quests = {} }
	for _, q in ipairs(slateFor(dd.Day)) do
		table.insert(out.Quests, { Id = q.Id, Text = q.Text, Reward = q.Reward, Target = q.Target,
			Progress = math.min(dd.Progress[q.Kind] or 0, q.Target), Claimed = dd.Claimed[q.Id] == true })
	end
	return out
end

function M.Init()
	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			local data = PDM.Get(player)
			if data then push(player, data) end
		end)
	end)
end

return M
```

- [ ] **Step 4: Create the `DarrelUpdate` RemoteEvent** under `ReplicatedStorage.Remotes`; add `DarrelService.Init()` in `Main` beside the other `.Init()` calls (read Main first, back it up).

- [ ] **Step 5: Quest-event mirrors** — three one-line insertions, each DIRECTLY below an existing anchor (back up each file; read the exact current line first):
  - ThrowHandler, anchor `SeasonPassHandler.Notify(player, "Throw", 1)` → insert `DarrelService.Notify(player, "Throw", 1)` (plus the `local DarrelService = require(...)` beside ThrowHandler's other requires).
  - ThrowHandler, anchor `SeasonPassHandler.NotifyCatch(player, tier.Name)` → insert `if (tierIndexByName and tierIndexByName >= 4) then end` — NO. Instead: insert `DarrelService.Notify(player, "Catch", 1)` guarded exactly as the season EpicCatch guard on that line's surrounding block: read the surrounding code; the catch mirror must count only Epic-or-better (the existing code already computes the tier index for `EpicCatch idx>=4` — reuse that same condition variable verbatim).
  - IncomeLoop, at its campfire-collect grant site (the block that fires `CampfireCollected`) → insert `DarrelService.Notify(player, "Collect", amount)` using that block's actual local amount variable name (read first).

- [ ] **Step 6: Probe passes**

```lua
-- fresh-clone require DarrelService: slateFor determinism (same Day -> same 3 ids, all distinct);
-- PlayerDataManager.Source contains "Darrels = 0" and the migration line;
-- Remotes.DarrelUpdate exists; Main.Source contains "DarrelService.Init()"
-- grep count: exactly 3 "DarrelService.Notify(" call sites across ThrowHandler + IncomeLoop
```

- [ ] **Step 7: Snapshot + commit** — `eggs(3): DarrelService, schema, daily slate, 3 quest mirrors`

---

### Task 4: EggConfig

**Files:**
- Create: `game.ReplicatedStorage.Modules.EggConfig` (ModuleScript — client-readable: the shop UI derives its odds display from THIS table)
- Snapshot: `game-src/eggs/EggConfig.lua`

**Interfaces:**
- Produces: `EggConfig.WORLDS`, `EggConfig.GetWorld(id)`, `EggConfig.GetEgg(worldId, eggId)`, `EggConfig.Validate() -> true|error` (asserts every table's weights sum to 100 and every name exists in BrainrotConfig).

- [ ] **Step 1: Failing probe** — module absent.

- [ ] **Step 2: Implement** (data verbatim from the spec — creature stats live ONLY in BrainrotConfig; EggConfig holds egg definitions):

```lua
-- EggConfig — single source of truth for eggs. The server ROLLS from these
-- tables and the client DISPLAYS them, so shown odds can never drift from
-- real odds (Roblox requires published odds for paid random items).
local BrainrotConfig = require(script.Parent.BrainrotConfig)

local M = {}

M.WORLDS = {
	Forest = {
		Active = true,
		DisplayName = "Forest",
		Eggs = {
			{ Id = "ForestShard",  Name = "Shard Egg",  Price = 60,  Model = "ForestEgg1",
			  Table = { { "Cervolino Antlerino", 50 }, { "Fanghetto Palunko", 32 }, { "Strigolino Hootini", 18 } } },
			{ Id = "ForestDrip",   Name = "Drip Egg",   Price = 85,  Model = "ForestEgg2",
			  Table = { { "Fanghetto Palunko", 34 }, { "Strigolino Hootini", 36 }, { "Rospino Bavaglio", 30 } } },
			{ Id = "ForestHorned", Name = "Horned Egg", Price = 115, Model = "ForestEgg3",
			  Table = { { "Rospino Bavaglio", 45 }, { "Corvacchio Beccarino", 35 }, { "Ceppone Zampalunga", 20 } } },
			{ Id = "ForestRune",   Name = "Rune Egg",   Price = 160, Model = "ForestEgg4",
			  Table = { { "Ceppone Zampalunga", 40 }, { "Alcione Trombettone", 30 }, { "Lucciolone Pantanini", 20 }, { "Gufocervo Stiltini", 10 } } },
			{ Id = "ForestCrown",  Name = "Crown Egg",  Price = 220, Model = "ForestEgg5",
			  Table = { { "Alcione Trombettone", 34 }, { "Lucciolone Pantanini", 30 }, { "Gufocervo Stiltini", 30 }, { "Muschione Cornaluna", 6 } } },
		},
	},
}

function M.GetWorld(worldId) return M.WORLDS[worldId] end

function M.GetEgg(worldId, eggId)
	local w = M.WORLDS[worldId]
	if not w then return nil end
	for _, egg in ipairs(w.Eggs) do
		if egg.Id == eggId then return egg, w end
	end
	return nil
end

function M.Validate()
	local live = {}
	for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do live[e.Name] = true end
	for worldId, w in pairs(M.WORLDS) do
		for _, egg in ipairs(w.Eggs) do
			local sum = 0
			for _, row in ipairs(egg.Table) do
				assert(live[row[1]], egg.Id .. " references unknown creature: " .. tostring(row[1]))
				sum += row[2]
			end
			assert(sum == 100, egg.Id .. " weights sum to " .. sum .. ", want 100")
		end
	end
	return true
end

return M
```

(NOTE for implementer: read how BrainrotConfig exposes its entries — `.List` vs array root — and use its real shape in `Validate`; Task 1's probe established it.)

- [ ] **Step 3: Probe passes** — fresh-clone require; `Validate()` returns true; `GetEgg("Forest","ForestCrown").Price == 220`.

- [ ] **Step 4: Snapshot + commit** — `eggs(4): EggConfig world registry, validated odds`

---

### Task 5: EggHandler — buy/roll/grant

**Files:**
- Create: `game.ServerScriptService.Modules.EggHandler`, remotes `EggBuy` (RemoteEvent), `EggResult` (RemoteEvent)
- Modify: `Main` (`EggHandler.Init()`)
- Snapshot: `game-src/eggs/EggHandler.lua`

**Interfaces:**
- Consumes: `DarrelService.TrySpend/Award`, `EggConfig.GetEgg`, `BrainrotMover.Give` (READ ITS REAL SIGNATURE FIRST — the trade hardening extended it; grant with a record table `{ Name = name }`), `PlayerDataManager.Get/PushUpdate/Save`.
- Produces: client contract — `EggBuy:FireServer(worldId, eggId)`; server replies `EggResult:FireClient(player, { Ok, EggId, Name, Rarity, Message })`. Exposes `EggHandler.RollFor(egg, rng) -> name` (pure, for the Task 12 simulation).

- [ ] **Step 1: Failing probe** — module + remotes absent.

- [ ] **Step 2: Implement**:

```lua
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PDM = require(script.Parent.PlayerDataManager)
local DarrelService = require(script.Parent.DarrelService)
local BrainrotMover = require(script.Parent.BrainrotMover)
local EggConfig = require(RS.Modules.EggConfig)
local BrainrotConfig = require(RS.Modules.BrainrotConfig)
local remotes = RS:WaitForChild("Remotes")

local M = {}
local rng = Random.new()
local lastBuy = {}  -- [player] = clock, 0.5s debounce

local rarityByName = {}
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do rarityByName[e.Name] = e.Rarity end

function M.RollFor(egg, r)  -- pure; weights sum to 100 (EggConfig.Validate)
	local roll = (r or rng):NextInteger(1, 100)
	local acc = 0
	for _, row in ipairs(egg.Table) do
		acc += row[2]
		if roll <= acc then return row[1] end
	end
	return egg.Table[#egg.Table][1]
end

local function refuse(player, msg)
	remotes.EggResult:FireClient(player, { Ok = false, Message = msg })
end

function M.Init()
	EggConfig.Validate()  -- fail loudly at boot, not at first purchase
	remotes.EggBuy.OnServerEvent:Connect(function(player, worldId, eggId)
		if typeof(worldId) ~= "string" or typeof(eggId) ~= "string" then return end
		local now = os.clock()
		if lastBuy[player] and now - lastBuy[player] < 0.5 then return end
		lastBuy[player] = now

		local data = PDM.Get(player)
		if not data then return refuse(player, "Profile not loaded yet.") end
		if data.__noSave then return refuse(player, "Your profile did not load — rejoin before buying eggs.") end
		local egg, world = EggConfig.GetEgg(worldId, eggId)
		if not egg or not world.Active then return refuse(player, "That egg is not available.") end

		-- ATOMIC COMMIT: no yields from here to the Give.
		if not DarrelService.TrySpend(player, egg.Price, "egg:" .. eggId) then
			return refuse(player, ("Not enough Darrels (need %d)."):format(egg.Price))
		end
		local name = M.RollFor(egg)
		local ok, err = BrainrotMover.Give(data, { Name = name })
		if not ok then
			DarrelService.Award(player, egg.Price, "refund:" .. eggId)
			return refuse(player, err or "Hatch failed — Darrels refunded.")
		end
		data.EggsOpened[eggId] = (data.EggsOpened[eggId] or 0) + 1
		PDM.PushUpdate(player)
		remotes.EggResult:FireClient(player, { Ok = true, EggId = eggId, Name = name, Rarity = rarityByName[name] })

		local saved = PDM.Save(player)  -- after commit; audit on failure (trade-hardening pattern)
		if not saved then
			warn(("[EggHandler] SAVE FAILED after hatch: %s uid=%d egg=%s got=%s")
				:format(player.Name, player.UserId, eggId, name))
		end
	end)
	Players.PlayerRemoving:Connect(function(p) lastBuy[p] = nil end)
end

return M
```

(Implementer: `script_read` BrainrotMover.Give FIRST — confirm `(data, record) -> ok, err` and that a `{ Name = name }` record grants an unplaced copy. If Give's uniqueness cap refuses, its error string is what players see — check it reads acceptably.)

- [ ] **Step 3: Create remotes, wire `EggHandler.Init()` into Main** (after DarrelService's Init — require order matters).

- [ ] **Step 4: Probe passes** — fresh-clone require; `RollFor` over a fake egg `{Table={{"A",100}}}` returns "A" 100/100 times; 10k rolls on the real Crown table land Muschione within 4.5–7.5% (loose band here; the tight ±1.5pp gate is Task 12's).

- [ ] **Step 5: Snapshot + commit** — `eggs(5): EggHandler atomic buy->roll->Give with refund path`

---

### Task 6: Egg meshes — import + stall display

**Files:**
- Create: `game.ReplicatedStorage.EggModels.Forest.ForestEgg1..5` (Models), 5 display clones on the EggStall counter
- Source: `docs/design-handoff/forest-eggs/eggs_forest_set.obj` + `.mtl`

**Interfaces:**
- Produces: `ForestEgg1..5` (Shard/Drip/Horned/Rune/Crown — OBJ eggs #6–10 in file order), each with decoration sub-parts preserved (`shard_*`, `drip_*`, etc. keep their names — the Task 8 hatch animation tweens them).

- [ ] **Step 1: USER STEP (blocking, coordinate in chat):** In Studio: **File → Import 3D** → select `docs/design-handoff/forest-eggs/eggs_forest_set.obj` → keep default options, ensure the `.mtl` sits beside it (it does, vendored) → Import. Result lands in Workspace.

- [ ] **Step 2: Identify the 10 eggs** in the imported hierarchy by decoration signature (from the OBJ group audit): #6 = stripes+studs+5 shards · #7 = 12 drips+tape+4 shards · #8 = 5 stripes+7 spikes+2 horns+5 shards · #9 = 7 stripes+7 rune rings/bars+ring+6 shards · #10 = cap+13 drips+8 runes+7-point crown+halo+32 chain links+8 shards. Take those FIVE; delete the rest of the import from Workspace.

- [ ] **Step 3: Normalize** — for each: `Model.Name = "ForestEgg<n>"` (1=Shard #6 … 5=Crown #10), scale so height ≈ 2.4 studs (`ScaleTo` — ABSOLUTE, use `GetScale()*f`), every BasePart Anchored + CanCollide=false + CanQuery=false, PrimaryPart = the shell_body mesh, parent under new Folder `ReplicatedStorage.EggModels.Forest`.

- [ ] **Step 4: Stall display** — clone the 5 onto the EggStall CounterTop (`Workspace.GameWorld.EggStall.CounterTop`, top surface y≈8.4, spread across its 22-stud length at ~4-stud spacing, facing +X toward shoppers). Keep the 15 `EggGood` shelf cubes as ambient decor. Add a small floating BillboardGui price tag above each (`<Name>\n<Price>💎` — cream text, ink outline, `UITheme.Font`).

- [ ] **Step 5: Probe** — `EggModels.Forest` has exactly 5 Models named ForestEgg1..5, each 0 scripts, heights 2.2–2.6, all anchored; screenshot the stall from `(-45, 10, -260)` look `(-62, 8, -260)` — five distinct eggs on the counter with tags.

- [ ] **Step 6: Commit** — `eggs(6): five forest egg meshes imported, normalized, on the stall` (log import in `game-src/eggs/models-build-log.md`).

---

### Task 7: EggShopClient — panel + odds

**Files:**
- Create: `game.StarterPlayer.StarterPlayerScripts.EggShopClient` (LocalScript)
- Snapshot: `game-src/eggs/EggShopClient.lua`

**Interfaces:**
- Consumes: `EggConfig` (direct require — odds display), `UITheme` (campPanel/campButton/closeGlyph/Font/ribbon), `BrainrotThumb.add` (egg + creature viewports), remotes `EggBuy/EggResult/DarrelUpdate`, `SideRail.registerPanel`.
- Produces: ScreenGui `EggShopUI` (DisplayOrder 9, IgnoreGuiInset false), panel opened by the stall prompt; hatch overlay consumed by Task 8 (`playReveal(result)` function defined here, stub in this task).

- [ ] **Step 1: Failing probe** — script absent.

- [ ] **Step 2: Implement.** Structure (follow BackpackClient's panel conventions — read it first for the setOpen/registerPanel/CanvasPosition-reset patterns):

```lua
-- EggShopClient — Egg Shop panel + darrel chip + hatch reveal host.
-- Opens via ProximityPromptService.PromptTriggered on the EggStall prompt.
-- ODDS ARE ALWAYS VISIBLE: rows render straight from EggConfig (single source).
local prompt = workspace:WaitForChild("GameWorld"):WaitForChild("EggStall"):WaitForChild("PromptPart"):WaitForChild("EggPrompt")
-- Panel: UITheme.campPanel frame 640x520 center; title "FOREST EGGS" via ribbon;
-- left: 5 egg rows (viewport of ReplicatedStorage.EggModels.Forest[egg.Model],
--   name, price "N💎", campButton "OPEN"), selected row expands an odds list:
--   one line per Table row: "<creature name> — <pct>%", tier-colored via RarityConfig.
-- top-right: darrel chip (💎 N) fed by remotes.DarrelUpdate + initial GetInitialData;
--   also a "DAILY QUESTS" mini-list from DarrelUpdate payload .Daily (3 rows, progress bars).
-- OPEN button -> remotes.EggBuy:FireServer("Forest", egg.Id); disable buttons 0.6s.
-- remotes.EggResult.OnClientEvent -> if not Ok: UITheme toast pattern w/ Message;
--   if Ok: playReveal(result)  -- Task 8; THIS task stubs it as:
--   local function playReveal(result) print("[EggShop] hatched:", result.Name) end
-- SideRail.registerPanel(panel) so it participates in single-open.
-- ProximityPromptService.PromptTriggered:Connect(function(p) if p == prompt then setOpen(true) end end)
```

Write the full ~250-line implementation following those comments — every element listed must exist; odds text MUST be generated by iterating `egg.Table`, never hard-coded.

- [ ] **Step 3: Probe passes (structural, Edit)** — fresh-clone `loadstring(source)` compiles; grep own source: contains `PromptTriggered`, `registerPanel`, `EggConfig`, zero literal odds percentages (search for `50` next to `Cervolino` must find nothing — display is data-driven).

- [ ] **Step 4: Snapshot + commit** — `eggs(7): egg shop panel, data-driven odds, darrel chip`

---

### Task 8: Hatch reveal

**Files:**
- Modify: `EggShopClient` (replace the `playReveal` stub)
- Snapshot: `game-src/eggs/EggShopClient.lua` (updated)

**Interfaces:**
- Consumes: `EggResult` payload `{ EggId, Name, Rarity }`, `EggModels.Forest`, `BrainrotThumb.add`, `RarityFX` (tier ladder on the reveal tile), `SoundKit.play("panelOpen")` at crack (id swappable later).

- [ ] **Step 1: Implement** — full-screen dim Frame (BackgroundTransparency tween to 0.35), centered 320×320 ViewportFrame:
  1. Egg model clone in the viewport, 1.2 s shake (CFrame jitter ±4° at 20 Hz via RenderStepped accumulator — REMEMBER: verify animation by screenshot, never by property read).
  2. Crack: tween every part whose name matches `^shard|^drip|^spike|^horn|^crown|^link` outward from the shell centroid (0.4 s, quad-out) while shell transparency → 1.
  3. Creature: swap viewport content to `BrainrotThumb`-style master clone of `result.Name`, slow spin (2 s/rev), `RarityFX` band per `result.Rarity`, name + tier label under (`UITheme.Font`, tier color).
  4. Click anywhere OR 3.5 s → fade out, restore shop panel. Skippable at any phase (one `skip()` closure, same shape as CatchReveal's handle).

- [ ] **Step 2: Verify structurally** in Edit (compiles; grep for `RenderStepped` disconnect on close — the connection MUST be stored and disconnected in `skip()`), then visually in Task 12.

- [ ] **Step 3: Snapshot + commit** — `eggs(8): hatch reveal (shake, shard burst, tier-lit creature spin)`

---

### Task 9: ProductRegistry — the single ProcessReceipt

**Files:**
- Create: `game.ServerScriptService.Modules.ProductRegistry`
- Modify: `Main` (Init — MUST be the only place `ProcessReceipt` is assigned, ever)
- Snapshot: `game-src/eggs/ProductRegistry.lua`

**Interfaces:**
- Produces: `ProductRegistry.Register(productId, def)` (`def = { Type = "Darrels", Amount = n }`), the assigned `MarketplaceService.ProcessReceipt`. Darrel packs pre-registered with `PLACEHOLDER_IDS = { 0, 0, 0, 0 }` for amounts `{ 80, 180, 400, 1000 }` — id 0 = inert. Wheel paid-spins can `Register` later.

- [ ] **Step 1: Failing probe** — module absent; `script_grep "ProcessReceipt"` across the game returns 0 assignment sites (confirming we're first — if it returns any, STOP and report).

- [ ] **Step 2: Implement**:

```lua
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PDM = require(script.Parent.PlayerDataManager)
local DarrelService = require(script.Parent.DarrelService)

local M = {}
local PRODUCTS = {}  -- [productId] = { Type, Amount }

function M.Register(productId, def)
	if productId == 0 then return end  -- placeholder: inert until the user creates real ids
	assert(PRODUCTS[productId] == nil, "duplicate product id " .. productId)
	PRODUCTS[productId] = def
end

local function grant(player, data, def)
	if def.Type == "Darrels" then
		DarrelService.Award(player, def.Amount, "robux:" .. def.Amount)
		return true
	end
	return false
end

function M.Init()
	-- Roblox allows exactly ONE ProcessReceipt per game. This is it. Add new
	-- purchasables via M.Register, never a second assignment.
	MarketplaceService.ProcessReceipt = function(info)
		local player = Players:GetPlayerByUserId(info.PlayerId)
		if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
		local data = PDM.Get(player)
		if not data or data.__noSave then return Enum.ProductPurchaseDecision.NotProcessedYet end

		local key = tostring(info.PurchaseId)
		if table.find(data.ReceiptLog, key) then
			return Enum.ProductPurchaseDecision.PurchaseGranted  -- already delivered
		end
		local def = PRODUCTS[info.ProductId]
		if not def then
			warn("[ProductRegistry] unknown product id " .. tostring(info.ProductId))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if not grant(player, data, def) then return Enum.ProductPurchaseDecision.NotProcessedYet end
		table.insert(data.ReceiptLog, key)
		if #data.ReceiptLog > 50 then table.remove(data.ReceiptLog, 1) end
		local saved = PDM.Save(player)
		if not saved then
			-- Grant + log are in-memory only. If this session never saves, both the
			-- darrels AND the log entry vanish together — a Roblox retry next session
			-- re-grants correctly. So NotProcessedYet is safe AND self-consistent.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Darrel packs (user creates dev products on roblox.com, then replaces these zeros):
	local PACK_IDS = { 0, 0, 0, 0 }           -- <- fill with real dev product ids
	local PACK_AMOUNTS = { 80, 180, 400, 1000 }
	for i, id in ipairs(PACK_IDS) do
		M.Register(id, { Type = "Darrels", Amount = PACK_AMOUNTS[i] })
	end
end

return M
```

- [ ] **Step 3: Wire `ProductRegistry.Init()`** into Main (after DarrelService).

- [ ] **Step 4: Probe passes** — fresh-clone require; simulate the receipt path with a fake info table against a mock data table (pure-Lua test of the dedupe: same PurchaseId twice → second call short-circuits `PurchaseGranted` without double-award — assert award counter == 1).

- [ ] **Step 5: Snapshot + commit** — `eggs(9): ProductRegistry, the game's single idempotent ProcessReceipt`

---

### Task 10: Index badge — FOREST EGG

**Files:**
- Modify: `game.StarterPlayer.StarterPlayerScripts.IndexClient` (additive; this file just gained vault badges — anchor carefully, back up first)
- Snapshot: `game-src/eggs/IndexClient.lua`

- [ ] **Step 1:** `script_read` the tile-builder region (anchor `local av = availabilityOf(e.Name)` from the vault-badge work). Insert, additively: when the config entry has `Source == "ForestEgg"`, render a small badge label `FOREST EGG` (gold rgb(255,216,107) text, ink outline, `UITheme.Font`, bottom-left of tile, ZIndex above the render) and SKIP the availability badge for these entries (they are egg-sourced; tide states don't apply).

- [ ] **Step 2: Probe** — compiles fresh; grep exactly one `ForestEgg` literal in IndexClient.

- [ ] **Step 3: Snapshot + commit** — `eggs(10): Index FOREST EGG source badge`

---

### Task 11: Pet system (shipped disabled)

**Files:**
- Create: `game.ReplicatedStorage.Modules.PetConfig`, `game.ServerScriptService.Modules.PetHandler`, remote `PetEquip` (RemoteEvent)
- Modify: `Main` (Init), ThrowHandler (ONE line), IncomeLoop (ONE line)
- Snapshot: `game-src/eggs/PetConfig.lua`, `game-src/eggs/PetHandler.lua`

**Interfaces:**
- Produces: `PetHandler.LuckMult(player) -> number` (≥1), `PetHandler.IncomeMult(player) -> number` (≥1), `PetHandler.Grant(player, petId)`, `PetEquip:FireServer(uid, equip)`.
- `PetConfig`: `ENABLED = false`, `SLOTS_FREE = 3`, `SLOTS_PREMIUM = 6`, `PET_SLOTS_GAMEPASS_ID = 0`, `Pets = { TestAcorn = { Name = "Test Acorn", Boost = { Type = "Luck", Amount = 0.10 } } }` (test-only placeholder, never shown in any shop).

- [ ] **Step 1: Failing probes** — modules absent; ThrowHandler/IncomeLoop contain no `PetHandler`.

- [ ] **Step 2: PetConfig** — the table above verbatim, plus a header comment: `ENABLED=false hides ALL pet UI and purchases. Flip only when the user's pet chart lands.`

- [ ] **Step 3: PetHandler** — implement:

```lua
-- Slots: math.min(#equipped) capped at SLOTS_FREE, or SLOTS_PREMIUM when the
-- gamepass is owned. id == 0 -> premium path inert (pcall UserOwnsGamePassAsync
-- ONLY when id ~= 0; cache per player-session in a table cleared on PlayerRemoving).
-- LuckMult/IncomeMult: 1 + sum of equipped pets' matching Boost.Amount; return 1
-- instantly when PetConfig.ENABLED == false (the seams stay live but neutral).
-- Grant(player, petId): validate petId in PetConfig.Pets, append
-- { Uid = HttpService:GenerateGUID(false), Id = petId, Boost = table.clone(def.Boost) }
-- to data.Pets, PushUpdate.
-- PetEquip handler: validate uid ∈ data.Pets, toggle membership in data.PetSlots
-- under the cap, rebuild follow rigs.
-- Follow rig (buildRig(player)): for each equipped pet, an 8-part placeholder
-- acorn (2 stud ball + cap cubes, Massless, CanCollide=false), Attachment on the
-- pet root + Attachment on HumanoidRootPart offset to slot i of
-- { Vector3.new(-2.5,1,2.5), Vector3.new(2.5,1,2.5), Vector3.new(-3.5,1.5,4),
--   Vector3.new(3.5,1.5,4), Vector3.new(-1.5,2,5), Vector3.new(1.5,2,5) },
-- AlignPosition (Responsiveness 15, MaxForce 4e4) + AlignOrientation to face
-- the character's LookVector. Destroy rigs on unequip/death/leave; rebuild on
-- CharacterAdded.
```

Write the full module from that contract — every named behavior implemented, no extras.

- [ ] **Step 4: The two seams** (back up both files; read anchors first):
  - ThrowHandler: find the rollDistance line that already multiplies `RebirthConfig.LuckMult(...)` (anchor from the feature memory) and multiply in `* PetHandler.LuckMult(player)` on that same expression. Add the require beside ThrowHandler's others.
  - IncomeLoop: find the per-player payout expression that multiplies `RebirthConfig.IncomeMult(...)` and multiply in `* PetHandler.IncomeMult(player)`. Add the require.

- [ ] **Step 5: Probe passes**:

```lua
-- fresh-clone PetHandler with a mock data table:
--  ENABLED=false -> LuckMult==1 and IncomeMult==1 even with pets equipped
--  flip clone's PetConfig.ENABLED=true (VM-local) -> TestAcorn equipped => LuckMult==1.10
-- grep: exactly one "PetHandler.LuckMult" in ThrowHandler, one "PetHandler.IncomeMult" in IncomeLoop
```

- [ ] **Step 6: Snapshot + commit** — `eggs(11): pet system behind ENABLED=false, neutral seams live`

---

### Task 12: Play-mode verification + cleanup

**Files:**
- Create (temporary): `game.ServerScriptService._EggTestGrant` (Script) — granted-darrels test hook, DELETED at the end:

```lua
-- TEMP TEST HOOK — Studio only, delete after egg verification.
if not game:GetService("RunService"):IsStudio() then return end
task.wait(5)
local DarrelService = require(script.Parent.Modules.DarrelService)
for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
	DarrelService.Award(p, 2000, "test-grant")
end
```

- [ ] **Step 1: Odds simulation (Edit, before Play)** — fresh-clone EggHandler; per egg run `RollFor` 10,000× with `Random.new(20260728)`; assert every creature's observed share within ±1.5 pp of its published odds. Record the table in the report.

- [ ] **Step 2: Enter Play** (this task owns `start_stop_play`). Console must show DarrelService/EggHandler/ProductRegistry boot with zero red errors.

- [ ] **Step 3: Buy cycle** — via execute_luau on the **Client** datamodel: `remotes.EggBuy:FireServer("Forest", "ForestShard")`. Verify: darrels 2000→1940 on the chip, EggResult received, reveal plays (screenshot mid-reveal — shake and shard-burst are RenderStepped work, only a screenshot proves them), creature lands in backpack data (`Remotes.GetInitialData` from the Client VM), places on a pad, earns its exact $/s (two reads 5 s apart), sells at standard multiplier, FOREST EGG badge shows in the Index.
- [ ] **Step 4: Refusals** — spend down below 60, buy → refusal toast, balance unchanged. Fire `EggBuy` with garbage (`FireServer(1, {})`, unknown egg id) → silently ignored / clean refusal, no errors.
- [ ] **Step 5: Daily quests** — throw 25 rocks in the throw zone (character_navigation + the throw remote pattern from prior sessions; remember: claimed plot + stand inside ThrowZone or ThrowRequest is silently refused) → `throw25` auto-claims +3💎 exactly once; second threshold cross same day does not re-award.
- [ ] **Step 6: Receipt idempotence (Server VM)** — call the assigned `MarketplaceService.ProcessReceipt` twice with the same fake info `{ PlayerId = <you>, PurchaseId = "TEST-1", ProductId = <a registered id or temporarily-registered 999 test id> }` → darrels +80 exactly once; second call returns PurchaseGranted with no award. Unregister the test id.
- [ ] **Step 7: Pets neutral** — with `ENABLED=false`: no pet UI anywhere; a throw and an income tick behave identically to pre-task values. Then VM-flip test from Task 11 Step 5 already covers the enabled path — do NOT flip the real module.
- [ ] **Step 8: Stop Play. Delete `_EggTestGrant`.** Verify it's gone. Zero red errors across the whole session (the `Workspace.SFX` false-positive class was cleaned 2026-07-28; anything new is real).
- [ ] **Step 9: Final snapshot of every touched script to `game-src/eggs/`, write `.superpowers/sdd/2026-07-28-forest-egg-shop/progress.md`** (per-task outcomes + deviations), commit:

```bash
git add game-src/eggs/ .superpowers/sdd/2026-07-28-forest-egg-shop/
git commit -m "eggs(12): full Play verification — odds sim, buy cycle, quests, receipts, pets-neutral"
```

- [ ] **Step 10: Report to user** — proof screenshots (stall, shop panel with odds, reveal, badge), the odds-sim table, reminder list: create gamepass + 4 dev products when ready; pet chart pending; save-to-cloud is theirs.

---

## Self-review (done at write time)

- **Spec coverage:** §1 shop/odds/reveal → Tasks 6–8; §2 economy numbers → Tasks 1, 4 (verbatim tables), faucet → Task 3, packs → Task 9; §3 modules/seams → Tasks 3–5, 9, 11; §4 pets → Task 11; §5 safety → Tasks 5 (atomic+refund+__noSave), 9 (idempotence+NotProcessedYet), 1 (collision check), 12 (acceptance 1–8 mapped: sim=S1, refusal=S4, creature-lifecycle=S3, odds-display=S3, quests=S5, receipts=S6, pets=S7, zero-errors=S8). Index badge → Task 10. No gaps found.
- **Placeholders:** the only intentional zeros are gamepass/product ids — spec-mandated placeholders, inert by design. No TBDs elsewhere.
- **Type consistency:** `DarrelService.Notify(player, kind, n)` used identically in Tasks 3/5/12; `EggConfig.GetEgg -> egg, world` matches EggHandler's two-value destructure; `RollFor(egg, rng)` matches Task 12's sim; `PetHandler.LuckMult/IncomeMult` names match Task 11 seams and probes; remote names consistent (`EggBuy/EggResult/DarrelUpdate/PetEquip`).
