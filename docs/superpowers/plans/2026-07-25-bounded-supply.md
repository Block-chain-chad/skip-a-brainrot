# Vault & Tide (Bounded Supply) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make brainrot supply bounded and time-varying per the approved spec (`docs/specs/2026-07-25-bounded-supply-design.md`): Rare/Epic rotate weekly, Legendary/Mythic retire in seasonal batches, Secrets carry hard mint caps.

**Architecture:** One new shared clock-pure module (`SupplySchedule`) is the single source of truth for time-based availability; `BrainrotWaves` becomes a thin adapter over it so its two callers keep their imports; `RarityRoll` gains period-keyed pool rebuilding; `LimitedStock` gains the Secret cap ladder (config only — ThrowHandler's reveal-time `TryClaim` + fallback already generalizes); the Index gains status badges fed by the schedule plus one snapshot RemoteFunction for sold-out counts.

**Tech Stack:** Roblox Luau, live Studio place via roblox-studio MCP (`multi_edit` for patches, `execute_luau` for install/verify), repo mirrors in `game-src/`.

## Global Constraints

- Never delete a name from `BrainrotConfig` (saves reference names forever).
- `SupplySchedule` must be clock-pure and identical on client and server: `os.time()` UTC only; no DataStore, no RunService state, no `math.random` at module scope — the tide shuffle uses a seeded LCG.
- The roll path must never yield: `LimitedStock.SoldOut` (stale-tolerant) is the only sold-out check allowed there; `TryClaim` stays confined to `revealCatch`.
- Ownership is never gated: vault/tide/caps affect *catching* only. Placed brainrots, saves, trades, booths must work unchanged for retired names.
- `BrainrotWaves` keeps its public API (`IsObtainable`, `Counts`, `FORCE_ON`, `VAULTED`) — its two call sites (`RarityRoll`, `IndexClient`) must not change imports.
- **Pre-launch dormancy (user decision 2026-07-25: game is not public yet):** before `SEASONS[1].Starts`, `StatusOf` returns `capped` for capped names and `live` for everything else (after the `unreleased` check — future debuts stay hidden), `PeriodKey()` returns the constant `"pre"`, and `NextChange()` returns `SEASONS[1].Starts`. Season 1's `Starts` is authored as **1798761600** (2027-01-01 00:00 UTC — a deliberate placeholder with a `-- SET THIS WHEN YOU LAUNCH: the real go-live Monday 00:00 UTC` comment). Season 2 stays authored **exactly 8 weeks after Season 1** — when the launch date is set, move both (S2 = S1 + 4838400). The Task 1/Task 3 clock tests keep testing active-schedule behavior by injecting times past the placeholder.
- Season-1 retire batch (leaves when Season 2 starts): `Sovrano Pancetta`, `Console Grattugia`, `Idolo Cappelletto`.
- Secret caps ladder (spec table): Il Papa Meteorite 500, Il Tiranno Eclissi 400, La Sentinella Vuoto 320, Sua Altezza Galassia 250, Il Verdetto Supernova 200, La Cattedrale Cometa 150, Il Colosso Equinozio 120, Il Firmamento Ribollente 90, L'Ammiraglio Nebulosa 65, La Genesi Corazzata 45, Sua Grazia Abisso 25. Secret Pete stays 5, untouched.
- Status precedence: `unreleased > vaulted > retiring > away > capped > live`.
- Testing is Studio-side: `execute_luau` scripts with `SupplySchedule.SetClock` (Studio-only injection). There is no test framework; each task's test step is a script whose printed assertions must all read `OK`.
- Studio may be in Play mode (owner plays regularly): all `multi_edit`/Edit installs require Edit mode — stop Play only with a heads-up, never silently.

---

### Task 1: SupplySchedule module

**Files:**
- Create: `ReplicatedStorage.Modules.SupplySchedule` (ModuleScript)
- Mirror: `game-src/SupplySchedule.lua`

**Interfaces:**
- Consumes: `ReplicatedStorage.Modules.BrainrotConfig` (array of `{ Name, Rarity, ... }`).
- Produces (relied on by Tasks 2, 3, 6):
  - `M.IsObtainable(name: string) -> boolean`
  - `M.StatusOf(name: string) -> status: string?, timestamp: number?` — status ∈ `"live"|"capped"|"retiring"|"away"|"vaulted"|"unreleased"`, nil for unknown names; timestamp = when that status changes (retiring→season end, away→next flip, unreleased→debut), nil otherwise.
  - `M.NextChange() -> number` (unix time of next tide flip or season boundary)
  - `M.PeriodKey() -> string` (changes exactly when availability can change)
  - `M.SetClock(fn: (() -> number)?)` (Studio only; nil restores `os.time`)
  - `M.CAPPED: { [name]: true }` (the 12 capped names, for UI)
  - `M.SEASONS` (authored table, read-only by convention)

- [ ] **Step 1: Write the module** (full source; install as Source via `multi_edit` with `className = "ModuleScript"`):

```lua
-- SupplySchedule: the single source of truth for WHEN each brainrot is catchable.
-- Clock-pure: everything derives from UTC time + this authored config, so every
-- server and every client independently agrees with no DataStore and no publish.
--   Common/Uncommon: always live.
--   Rare/Epic:       "the Tide" -- a per-season split into set A and set B;
--                    even week-index -> A live, odd -> B. Every name is live at
--                    least every other week, and players can plan around it.
--   Legendary/Mythic: "the Vault" -- seasons retire authored batches forever
--                    (a season's Retire list leaves when the NEXT season starts,
--                    so the whole season is the last-chance countdown window).
--   Secret:          always live but hard-capped (LimitedStock owns the counts;
--                    CAPPED below only tells the UI which names to badge).
-- Ownership is NEVER gated here: this module answers "can it be CAUGHT now",
-- nothing else.

local RunService = game:GetService("RunService")
local BrainrotConfig = require(script.Parent.BrainrotConfig)

local M = {}

local WEEK = 604800

-- Explicit UTC instants, authored ~8 weeks apart. A season's Debut names become
-- catchable when it STARTS; its Retire names stop when it ENDS (= next season's
-- Starts). Past the last authored season the schedule holds its final state:
-- the tide keeps alternating, nothing further retires or debuts.
M.SEASONS = {
	{
		-- SET THIS WHEN YOU LAUNCH: the real go-live Monday 00:00 UTC. Until
		-- then it is a far-future placeholder and the whole schedule is DORMANT
		-- (everything catchable, no tide, no countdowns) -- the game is not
		-- public yet, and nothing may retire before the public could catch it.
		Starts = 1798761600, -- PLACEHOLDER: 2027-01-01 00:00 UTC
		Retire = { "Sovrano Pancetta", "Console Grattugia", "Idolo Cappelletto" },
		Debut = {},
	},
	{
		-- keep exactly 8 weeks (4838400s) after Season 1 when moving the date
		Starts = 1803600000, -- PLACEHOLDER: Season 1 + 8 weeks
		Retire = {},
		Debut = {},
	},
}

-- Names with a hard mint cap (LimitedStock.MAX must list exactly these).
-- Duplicated here as a name SET only, because this module is shared and the
-- counts live server-side.
M.CAPPED = {
	["Secret Pete"] = true,
	["Il Papa Meteorite"] = true, ["Il Tiranno Eclissi"] = true,
	["La Sentinella Vuoto"] = true, ["Sua Altezza Galassia"] = true,
	["Il Verdetto Supernova"] = true, ["La Cattedrale Cometa"] = true,
	["Il Colosso Equinozio"] = true, ["Il Firmamento Ribollente"] = true,
	["L'Ammiraglio Nebulosa"] = true, ["La Genesi Corazzata"] = true,
	["Sua Grazia Abisso"] = true,
}

local TIDE = { Rare = true, Epic = true }

--============================ injectable clock ==============================--
local now = os.time
-- Studio-only: tests step the clock across week and season boundaries instead
-- of waiting eight weeks. A nil fn restores the real clock.
function M.SetClock(fn)
	if RunService:IsStudio() then
		now = fn or os.time
	end
end

--=============================== authored maps ==============================--
local entryByName = {}
local tideNamesByTier = {}   -- [tierName] = { name, ... } in authored config order
for _, e in ipairs(BrainrotConfig) do
	entryByName[e.Name] = e
	if TIDE[e.Rarity] then
		local t = tideNamesByTier[e.Rarity]
		if not t then t = {}; tideNamesByTier[e.Rarity] = t end
		t[#t + 1] = e.Name
	end
end

local debutSeasonOf = {}   -- [name] = season index it debuts in
local retireSeasonOf = {}  -- [name] = season index whose END retires it
for k, season in ipairs(M.SEASONS) do
	for _, n in ipairs(season.Debut) do debutSeasonOf[n] = k end
	for _, n in ipairs(season.Retire) do retireSeasonOf[n] = k end
end

--============================== time helpers ================================--
local function seasonIndexAt(t)
	-- Before Season 1 starts this returns 1: pre-launch behaves as "season 1 in
	-- progress" (its retires have not happened; nothing has debuted).
	local idx = 1
	for k, season in ipairs(M.SEASONS) do
		if t >= season.Starts then idx = k end
	end
	return idx
end

-- A season "has ended" only when a NEXT season exists and has started; the
-- final authored season never ends (spec: schedule holds its final state).
local function seasonEndedAt(k, t)
	local nextSeason = M.SEASONS[k + 1]
	return nextSeason ~= nil and t >= nextSeason.Starts
end

local function weekIndexAt(t)
	return math.max(0, math.floor((t - M.SEASONS[1].Starts) / WEEK))
end

--================================ the tide ==================================--
-- Deterministic split per (tier, season): an LCG-seeded Fisher-Yates over the
-- authored name order. Same inputs -> same sets on every machine, forever.
-- Odd-size tiers put the extra name in A (so A-weeks run one name richer).
local function splitForSeason(tierName, seasonIdx)
	local names = tideNamesByTier[tierName]
	local a = table.clone(names)
	local s = seasonIdx * 2654435761 % 2147483647
	for i = #a, 2, -1 do
		s = (s * 1103515245 + 12345) % 2147483648
		local j = s % i + 1
		a[i], a[j] = a[j], a[i]
	end
	local inA = {}
	for i = 1, math.ceil(#a / 2) do inA[a[i]] = true end
	return inA
end

local splitCache = {}   -- [tierName .. seasonIdx] = inA set
local function inSetA(tierName, name, seasonIdx)
	local key = tierName .. seasonIdx
	local set = splitCache[key]
	if not set then
		set = splitForSeason(tierName, seasonIdx)
		splitCache[key] = set
	end
	return set[name] == true
end

--================================ public API ================================--

-- status, changeAt. Precedence: unreleased > vaulted > retiring > away >
-- capped > live. Sold-out is deliberately NOT a status here: this module is
-- clock-pure and shared; sold-out truth lives server-side in LimitedStock.
function M.StatusOf(name)
	local entry = entryByName[name]
	if not entry then return nil, nil end
	local t = now()
	local curIdx = seasonIndexAt(t)

	local debutIdx = debutSeasonOf[name]
	if debutIdx and t < M.SEASONS[debutIdx].Starts then
		return "unreleased", M.SEASONS[debutIdx].Starts
	end

	-- Pre-launch dormancy: until Season 1's authored start, the schedule is
	-- inert -- no tide, no countdowns, everything catchable (caps still shown).
	-- Sits AFTER the unreleased check so future debuts stay hidden pre-launch.
	if t < M.SEASONS[1].Starts then
		return M.CAPPED[name] and "capped" or "live", nil
	end

	local retireIdx = retireSeasonOf[name]
	if retireIdx then
		if seasonEndedAt(retireIdx, t) then
			return "vaulted", M.SEASONS[retireIdx + 1].Starts
		end
		-- retiring only while its season is CURRENT and an end actually exists
		if retireIdx == curIdx and M.SEASONS[curIdx + 1] then
			return "retiring", M.SEASONS[curIdx + 1].Starts
		end
	end

	if TIDE[entry.Rarity] then
		local wk = weekIndexAt(t)
		local wantA = (wk % 2 == 0)
		if inSetA(entry.Rarity, name, curIdx) ~= wantA then
			return "away", M.SEASONS[1].Starts + (wk + 1) * WEEK
		end
	end

	if M.CAPPED[name] then
		return "capped", nil
	end
	return "live", nil
end

function M.IsObtainable(name)
	local status = M.StatusOf(name)
	return status == "live" or status == "capped" or status == "retiring"
end

-- Unix time of the next instant ANY availability can change: the sooner of the
-- next tide flip and the next season boundary. For countdown UI.
function M.NextChange()
	local t = now()
	local nextFlip = M.SEASONS[1].Starts + (weekIndexAt(t) + 1) * WEEK
	for _, season in ipairs(M.SEASONS) do
		if season.Starts > t and season.Starts < nextFlip then
			nextFlip = season.Starts
		end
	end
	return nextFlip
end

-- Changes exactly when the answer of IsObtainable can change. RarityRoll keys
-- its pool cache on this so pools rebuild at boundaries and never in between.
function M.PeriodKey()
	local t = now()
	if t < M.SEASONS[1].Starts then return "pre" end
	return seasonIndexAt(t) .. ":" .. weekIndexAt(t) % 2
end

-- live, total -- for the Index header.
function M.Counts()
	local live = 0
	for _, e in ipairs(BrainrotConfig) do
		if M.IsObtainable(e.Name) then live += 1 end
	end
	return live, #BrainrotConfig
end

return M
```

- [ ] **Step 2: Run the clock-stepping test** (`execute_luau`, Edit datamodel). Every line must print `OK`:

```lua
local S = require(game.ReplicatedStorage.Modules.SupplySchedule)
local S1, S2 = 1798761600, 1803600000
local function check(label, got, want)
	print((got == want and "OK  " or "FAIL") .. " " .. label .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end
local t
S.SetClock(function() return t end)

-- pre-launch DORMANCY: nothing rotates, nothing counts down, caps still shown
t = S1 - 3600
check("pre-launch Common live", S.StatusOf("Broccolo Torpedo"), "live")
check("pre-launch retire batch NOT retiring yet", S.StatusOf("Sovrano Pancetta"), "live")
check("pre-launch Rare never away", S.StatusOf("Pizzarino Volante"), "live")
check("pre-launch capped Secret", S.StatusOf("Sua Grazia Abisso"), "capped")
check("Secret obtainable", S.IsObtainable("Sua Grazia Abisso"), true)
check("pre-launch PeriodKey constant", S.PeriodKey(), "pre")
check("pre-launch NextChange is launch instant", S.NextChange(), S1)

-- the moment the schedule wakes: retiring countdown begins at launch
t = S1 + 1
check("at launch retire batch shows retiring", S.StatusOf("Sovrano Pancetta"), "retiring")

-- week parity flips exactly at the boundary
t = S1 + 1
local w0 = S.StatusOf("Pizzarino Volante")
t = S1 + 604800 + 1
local w1 = S.StatusOf("Pizzarino Volante")
check("tide flips across week boundary", (w0 == "live" or w0 == "away") and w0 ~= w1 or (w0 == "away" and w1 ~= "away"), true)

-- every tide name is live at least every other week
t = S1 + 1
local away0 = {}
for _, e in ipairs(require(game.ReplicatedStorage.Modules.BrainrotConfig)) do
	if (e.Rarity == "Rare" or e.Rarity == "Epic") and S.StatusOf(e.Name) == "away" then away0[e.Name] = true end
end
t = S1 + 604800 + 1
local stillAway = 0
for n in pairs(away0) do if S.StatusOf(n) == "away" then stillAway += 1 end end
check("no tide name away two weeks running", stillAway, 0)

-- retirement happens exactly at Season 2 start
t = S2 - 1
check("retiring until the last second", S.StatusOf("Console Grattugia"), "retiring")
check("retiring still obtainable", S.IsObtainable("Console Grattugia"), true)
t = S2 + 1
check("vaulted after season end", S.StatusOf("Idolo Cappelletto"), "vaulted")
check("vaulted not obtainable", S.IsObtainable("Idolo Cappelletto"), false)

-- PeriodKey changes at boundaries only
t = S1 + 100 ; local k1 = S.PeriodKey()
t = S1 + 200 ; check("PeriodKey stable inside week", S.PeriodKey(), k1)
t = S1 + 604801 ; check("PeriodKey changes at flip", S.PeriodKey() ~= k1, true)

S.SetClock(nil)
print("done")
```

- [ ] **Step 3: Mirror to `game-src/SupplySchedule.lua`, commit** (`git add game-src/SupplySchedule.lua && git commit -m "feat: SupplySchedule (Vault & Tide clock-pure availability)"`).

---

### Task 2: BrainrotWaves becomes an adapter

**Files:**
- Modify: `ReplicatedStorage.Modules.BrainrotWaves` (full Source replacement)
- Mirror: `game-src/BrainrotWaves.lua`

**Interfaces:**
- Consumes: `SupplySchedule.IsObtainable`, `SupplySchedule.Counts` (Task 1).
- Produces: unchanged public API — `M.IsObtainable(name) -> boolean`, `M.Counts() -> live, total`, `M.FORCE_ON`, `M.VAULTED` — so `RarityRoll` and `IndexClient` need no import changes.

- [ ] **Step 1: Replace the module Source** with:

```lua
-- BrainrotWaves: catchability gate. Since 2026-07-25 this is a thin adapter
-- over SupplySchedule (the Vault & Tide clock) -- kept so its two callers
-- (RarityRoll, IndexClient) never had to change imports, and so the two manual
-- override tables survive as the levers of last resort:
--   FORCE_ON[name] -- always catchable, beats the schedule (never quota-gated)
--   VAULTED[name]  -- never catchable again, beats EVERYTHING incl. FORCE_ON
-- The old quota/spread wave machinery is gone: time-based scheduling replaced
-- it (see docs/specs/2026-07-25-bounded-supply-design.md in the repo).

local SupplySchedule = require(script.Parent.SupplySchedule)
local BrainrotConfig = require(script.Parent.BrainrotConfig)

local M = {}

M.FORCE_ON = {
	["Secret Pete"] = true,   -- fixed-odds apex; his gate is LimitedStock's cap
}
M.VAULTED = {}

function M.IsObtainable(name)
	if M.VAULTED[name] then return false end
	if M.FORCE_ON[name] then return true end
	return SupplySchedule.IsObtainable(name)
end

-- for the Index UI: currently catchable vs total authored
function M.Counts()
	local live = 0
	for _, e in ipairs(BrainrotConfig) do
		if M.IsObtainable(e.Name) then live += 1 end
	end
	return live, #BrainrotConfig
end

return M
```

- [ ] **Step 2: Test** (`execute_luau`, Edit): with `SupplySchedule.SetClock` at `S2+1`, check `Waves.IsObtainable("Idolo Cappelletto") == false`; add `Waves.FORCE_ON["Idolo Cappelletto"] = true` at runtime and check it flips to `true`; set `Waves.VAULTED["Idolo Cappelletto"] = true` and check `false` again (precedence). Restore both tables and `SetClock(nil)` before finishing. All prints `OK`.

- [ ] **Step 3: Mirror + commit** (`git commit -m "feat: BrainrotWaves adapter over SupplySchedule"`).

---

### Task 3: RarityRoll period-keyed pools + sold-out exclusion

**Files:**
- Modify: `ServerScriptService.Modules.RarityRoll`
- Mirror: `game-src/RarityRoll.lua`

**Interfaces:**
- Consumes: `SupplySchedule.PeriodKey` (Task 1), `Waves.IsObtainable` (Task 2), existing `LimitedStock.SoldOut/MAX`.
- Produces: unchanged public API (`TierForDistance`, `TierIndexForDistance`, `PickInTier`, `RollForDistance`) — ThrowHandler keeps working untouched.

**Why:** pools are currently built ONCE at require time (comment in file: "Pools are built ONCE at require time"). With time-varying availability a server crossing a week/season boundary would keep rolling retired/away names forever.

- [ ] **Step 1: Apply the edit.** Replace the block from `local poolsByTier, totalByTier = {}, {}` through the end of the pool-building `for` loop with:

```lua
local SupplySchedule = require(ReplicatedStorage.Modules.SupplySchedule)

-- Pools are cached, not static: availability now changes over time (weekly tide
-- flips, seasonal retirements) and when a capped name sells out. The cache key
-- captures exactly those inputs, so pools rebuild at boundaries and never in
-- between -- a per-throw scan over 214 entries stays off the hot path.
local poolsByTier, totalByTier, fixedByTier
local currentKey = nil

local function poolKey()
	local key = SupplySchedule.PeriodKey()
	-- SoldOut is stale-tolerant (<=60s) and never yields, so folding it into the
	-- key costs a dozen table lookups. TryClaim at reveal time stays the authority.
	for name in pairs(LimitedStock.MAX) do
		if LimitedStock.SoldOut(name) then
			key = key .. "|" .. name
		end
	end
	return key
end

local function rebuildPools()
	poolsByTier, totalByTier, fixedByTier = {}, {}, {}
	for _, entry in ipairs(BrainrotConfig) do
		if Waves.IsObtainable(entry.Name) and not LimitedStock.SoldOut(entry.Name) then
			if entry.FixedChance then
				local f = fixedByTier[entry.Rarity]
				if not f then f = {}; fixedByTier[entry.Rarity] = f end
				f[#f + 1] = entry
			else
				local p = poolsByTier[entry.Rarity]
				if not p then p = {}; poolsByTier[entry.Rarity] = p end
				p[#p + 1] = entry
				totalByTier[entry.Rarity] = (totalByTier[entry.Rarity] or 0) + entry.Weight
			end
		end
	end
end

local function ensurePools()
	local key = poolKey()
	if key ~= currentKey then
		currentKey = key
		rebuildPools()
	end
end
ensurePools()
```

Then add `ensurePools()` as the first line of `RarityRoll.PickInTier` (before the `math.clamp`). `rollFixed` keeps its existing per-roll `SoldOut` guard (harmless belt-and-braces on top of the pool exclusion).

- [ ] **Step 2: Test** (`execute_luau`, Edit): inject clock at `S2+1` (post-retirement), call `RarityRoll.PickInTier` 800 times across tier indexes 5–7 and assert none of the three retired names nor any `StatusOf == "away"` name is returned; step the clock one week and assert the away-set actually changed pools (compare 200-draw name sets differ). `SetClock(nil)` after. All prints `OK`. (Sold-out exclusion can't be forced without a DataStore write; it is covered by the same `rebuildPools` branch the retired-name assertions exercise, plus reveal-time `TryClaim` already verified in production for Secret Pete.)

- [ ] **Step 3: Mirror + commit** (`git commit -m "feat: RarityRoll period-keyed pools; exclude away/vaulted/sold-out"`).

---

### Task 4: LimitedStock cap ladder

**Files:**
- Modify: `ServerScriptService.Modules.LimitedStock` (the `MAX` table only)
- Mirror: `game-src/LimitedStock.lua`

**Interfaces:**
- Consumes: nothing new. Produces: `MAX` now lists 12 names; `SoldOut/Remaining/TryClaim` behavior unchanged.
- **NOTE:** this file is believed to be the collaborator's; the change is config-only and the user has been told to flag it to them.

- [ ] **Step 1: Replace the MAX table** with:

```lua
-- [config entry Name] = how many may EVER be granted, across every server, forever.
-- Ladder tracks the Secret tier's internal power ladder: the weakest Secret is
-- the most common trophy, the strongest is nearly one-of-a-kind. Once a cap is
-- hit the name is trade-only forever -- that is the point.
local MAX = {
	["Il Papa Meteorite"] = 500,
	["Il Tiranno Eclissi"] = 400,
	["La Sentinella Vuoto"] = 320,
	["Sua Altezza Galassia"] = 250,
	["Il Verdetto Supernova"] = 200,
	["La Cattedrale Cometa"] = 150,
	["Il Colosso Equinozio"] = 120,
	["Il Firmamento Ribollente"] = 90,
	["L'Ammiraglio Nebulosa"] = 65,
	["La Genesi Corazzata"] = 45,
	["Sua Grazia Abisso"] = 25,
	["Secret Pete"] = 5,
}
```

- [ ] **Step 2: Test** (`execute_luau`, Edit): `require` LimitedStock; assert `IsLimited` true for all 12 and false for `Broccolo Torpedo`; assert the set equals `SupplySchedule.CAPPED` exactly (both directions — a drift here silently breaks the UI badges). All prints `OK`.

- [ ] **Step 3: Verify claim generalization by READING ThrowHandler** (no edit): confirm `revealCatch` gates on `LimitedStock.IsLimited(brainrotEntry.Name)` → `TryClaim` → `PickInTier(baseTier + promotions, true)` fallback (it does today — this step is the regression tripwire in case that code moved).

- [ ] **Step 4: Mirror + commit** (`git commit -m "feat: hard mint caps for all 11 Secrets"`).

---

### Task 5: GetSupplySnapshot remote

**Files:**
- Modify: `ServerScriptService.Main` (wiring, next to the existing `remotes.GetInitialData.OnServerInvoke` block)
- Mirror note in `game-src/README.md`

**Interfaces:**
- Produces (relied on by Task 6): RemoteFunction `ReplicatedStorage.Remotes.GetSupplySnapshot` returning `{ [name] = { cap: number, minted: number? } }` for every name in `LimitedStock.MAX` (`minted` nil while the 60s refresher hasn't read the key yet — UI shows the badge without a count).

- [ ] **Step 1: Create the remote + handler.** In Main, immediately after the `GetInitialData` handler block, insert:

```lua
-- Sold-out truth for the Index badges. Server-side because LimitedStock is;
-- the schedule half of supply status is computed client-side (SupplySchedule
-- is shared and clock-pure). Cheap: 12 table reads, no DataStore touch --
-- LimitedStock's own 60s refresher keeps the counts warm.
local supplyRemote = Instance.new("RemoteFunction")
supplyRemote.Name = "GetSupplySnapshot"
supplyRemote.Parent = remotes
supplyRemote.OnServerInvoke = function()
	local out = {}
	for name, cap in pairs(LimitedStock.MAX) do
		local remaining = LimitedStock.Remaining(name)
		out[name] = { cap = cap, minted = remaining and (cap - remaining) or nil }
	end
	return out
end
```

- [ ] **Step 2: Test** (Play mode, Client `execute_luau`): `InvokeServer` and assert 12 keys, each with numeric `cap`, and `cap == 5` for `Secret Pete`. All prints `OK`.

- [ ] **Step 3: Commit** (`git commit -m "feat: GetSupplySnapshot remote for cap badges"` — Main is not mirrored; note the wiring in game-src/README.md).

---

### Task 6: Index supply badges

**Files:**
- Modify: `StarterPlayer.StarterPlayerScripts.IndexClient`
- Mirror: append patch description to `game-src/IndexPatch.txt`

**Interfaces:**
- Consumes: `SupplySchedule.StatusOf/NextChange/CAPPED` (Task 1), `GetSupplySnapshot` (Task 5). The file already requires `Waves`; add `local SupplySchedule = require(ReplicatedStorage.Modules.SupplySchedule)` next to it.

**Current shape (anchors, post-thumbnail-patch):** availability is computed near the top ("BrainrotWaves.IsObtainable answers false for BOTH ..." comment; `if Waves.IsObtainable(name) then return AV_LIVE end`), and card copy is chosen in `buildList` around the `subText, glyph, pillText = "UNDISCOVERED \u{00B7} CATCHABLE NOW", ...` block with `AV_LIVE / AV_SOON / AV_VAULTED`-style states.

- [ ] **Step 1: Extend availability + copy.** Keep the three AV buckets (their glyph semantics are load-bearing per the file's own comments) but derive them from `SupplySchedule.StatusOf`, and enrich the card sub-text:
  - `live` → existing behavior.
  - `capped` → AV_LIVE + sub-text `"N OF CAP LEFT"` (from a session-cached `GetSupplySnapshot` invoked lazily on first Index open, refreshed on open at most every 60s), flipping to `"SOLD OUT — CAP EXIST"` when `minted >= cap`; count omitted while `minted` is nil.
  - `retiring` → AV_LIVE + sub-text `"LEAVES <D>d <H>h"` from the returned timestamp (compute `os.time()` delta; clamp at `0d 0h`).
  - `away` → AV_SOON glyph (hourglass) + `"RETURNS <weekday>"` from the timestamp (`os.date("!%a", ts)`).
  - `unreleased` → AV_SOON + `"DEBUTS <ts as !%b %d>"`.
  - `vaulted` → AV_VAULTED (cross glyph) + `"VAULTED"` — owned copies still render color thumbnails and stats exactly as before (ownership never gated).

- [ ] **Step 2: Play-mode verify** (Client `execute_luau` + screenshot): open the Index via a real rebuild (never bare `frame.Visible = true` — that reads stale labels; trigger `setOpen` via the rail button or force a `DataUpdated` while visible). With `SetClock` stepped to mid-Season-1 on the CLIENT copy of SupplySchedule, assert: the 3 retire-batch cards show `LEAVES`, at least one Rare shows `RETURNS`, all 11 Secrets show a cap badge. Screenshot for the user. `SetClock(nil)` after.

- [ ] **Step 3: Commit** (`git commit -m "feat: Index supply badges (leaves/returns/caps/vaulted)"`).

---

### Task 7: Full regression + ship

- [ ] **Step 1: Real-clock Play test** (no injected clock; today is pre-Season-1 so everything must be live except sold-out): throw a rock, catch, confirm normal; Index header shows `214 CATCHABLE` (nothing retired yet) and the retire batch shows `retiring` countdowns to 2026-09-21? — **no**: pre-S1, `retiring` countdown targets S2 = correct per module (S1 batch is "retiring" from day 0; its whole season IS the window). Confirm placed/owned brainrots unaffected; trades/store prompts fine.
- [ ] **Step 2: Boundary smoke** (Edit, injected clock): rerun Task 1 Step 2 and Task 3 Step 2 scripts one final time on the installed modules.
- [ ] **Step 3: Update memory + remind the user to save/publish** (publish blocked on the account that owns the place — the owner must do it).

## Self-Review Notes

- Spec coverage: SEASONS/tide/API/SetClock (T1), adapter+overrides (T2), roll integration incl. the reveal-time race (T3+T4 Step 3 — already generalized in ThrowHandler, verified not rebuilt), caps (T4), snapshot remote (T5), badges incl. silhouette/ownership rules (T6), regression (T7). Guest debuts: schema supported (Debut lists), Season 1 authored empty per spec.
- Type consistency: `StatusOf -> (string?, number?)`; `PeriodKey -> string`; snapshot `{ [name] = { cap, minted? } }` used identically in T5/T6.
- Known deliberate gaps: sold-out cannot be force-tested without a DataStore write (documented in T3); `RollForDistance` (legacy, ignores waves entirely) left untouched — it is dead code for the catch path (ThrowHandler uses `PickInTier`) and out of scope.
