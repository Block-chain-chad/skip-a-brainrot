# Season Pass — Premium Track: Design + Patch Spec

Status: DESIGN ONLY — no game file has been edited. All paths are relative to
`game-src\place-full\`. Line numbers refer to the files as of 2026-08-04.

Goal: light up the gold "Season Pass" column that PassPanel already renders
(permanently LOCKED today) as a real second reward track, gated on a gamepass,
with retroactive unlock on mid-season purchase, migration-safe claim storage,
and **zero behavior change while the gamepass id is 0**.

---

## 1. Current state (verified)

| Piece | File | What it does today |
|---|---|---|
| Config | `ReplicatedStorage\Modules\SeasonConfig.lua` | 25 tiers, `{ XP, Cash, Milestone }`; header says premium needs a gamepass id |
| Server | `ServerScriptService\Modules\SeasonPassHandler.lua` | `SendState` pushes `{ XP, Claimed, QuestIds, Progress, Day }`; `claimTier(player, tier)` validates + grants `def.Cash` |
| Storage | `ServerScriptService\Modules\PlayerDataManager.lua:298` | `SeasonClaimed = {}` — flat `[tostring(tier)] = true`; sanitize at :571 |
| New UI | `StarterPlayer\StarterPlayerScripts\GameHUDPanels\PassPanel.lua` | Renders BOTH columns; gold column hard-coded always-LOCKED; CTA is a disabled "COMING SOON" |
| Legacy UI | `StarterPlayer\StarterPlayerScripts\SeasonClient.client.lua` | **Still running.** Its tile lives on the permanently-hidden legacy rail, but it still consumes `SeasonState`, pushes the rail claim badge from join+1s, and can fire `SeasonClaim:FireServer(tier)` (one arg) |
| Gamepass infra | `GamepassConfig.lua` + `GamepassService.lua` | Catalog + ownership cache. `GamepassId == 0` ⇒ pass skipped entirely; `HasFlag(player, flag)` scans boolean `Effects` of owned passes |

Claim-state readers (all point lookups, none iterate the table — this is what
makes the chosen data shape safe):

- `SeasonPassHandler.lua:91` — `data.SeasonClaimed[key]`
- `PassPanel.lua:516, :574` — `state.Claimed[tostring(tier)]`
- `SeasonClient.client.lua:236` — `state.Claimed[tostring(i)]`

---

## 2. Design decisions

### 2.1 Gamepass key: `SeasonPass`, gated via `HasFlag`

One new entry in `GamepassConfig.List` with `Effects = { SeasonPass = true }`.
The server gates the premium track on
`GamepassService.HasFlag(player, "SeasonPass")` rather than
`Owns(player, "SeasonPass")` — same accessor pattern as `AutoCollect`/`VIP`,
and it means a future bundle pass (e.g. "VIP+") can also grant the premium
track just by adding `SeasonPass = true` to its own `Effects`. The key string
lives once in `SeasonConfig.PASS_KEY` so server and client agree.

### 2.2 Premium rewards: `PassCash = 3x` free cash, same tier table

Each tier gains a `PassCash` field computed in the existing loop
(`cash * 3` — free cash is already a multiple of 100, so 3x stays clean;
milestone doubling carries through automatically). No second table, no new
config file. Sample values:

| Tier | Free `Cash` | Premium `PassCash` |
|---|---|---|
| 1 | $800 | $2,400 |
| 5 (milestone) | $5,400 | $16,200 |
| 10 (milestone) | $27,200 | $81,600 |
| 25 (milestone) | ~$3.6M | ~$10.9M |

Rewards stay scalar cash for v1 (PassPanel already renders `shortCash` +
an `x1` chip and its own comment says "revisit when itemized rewards exist").

### 2.3 Claim state: ONE flat table, prefix-namespaced string keys  ← the crux

`data.SeasonClaimed` keeps its exact current shape and meaning:

```
SeasonClaimed = {
  ["7"]  = true,   -- free  tier 7 claimed   (existing key format, untouched)
  ["p7"] = true,   -- PREMIUM tier 7 claimed (new key format)
}
```

Free track keeps `tostring(tier)`; premium uses `"p" .. tier`.

**Why this is migration-safe:**

1. **Zero-write migration.** Existing saves are already in the final shape.
   No load-time transformation exists to half-run, crash mid-way, or be
   missed by a code path. The sanitize line
   (`PlayerDataManager.lua:571 — if not data.SeasonClaimed then ... = {} end`)
   needs no change.
2. **Old readers can't see the new keys.** Every reader is a direct lookup by
   numeric-string key (verified list in §1); nothing iterates `SeasonClaimed`.
   `"p7"` is simply invisible to pre-patch code.
3. **Rollback-safe in both directions.** Revert the feature and premium claims
   sit dormant-but-intact; re-ship it and they're honored again. Free-track
   claims are never touched by any premium code path.
4. **Preserves the all-string-key invariant** the original author chose
   deliberately (`:90 -- datastore-safe key`). Mixed numeric/string keys are
   the classic DataStore JSON corruption trap; `"p"..tier` keeps every key a
   string.

**Rejected alternatives:**

- `SeasonClaimed = { Free = {...}, Pass = {...} }` (nested): requires an
  in-place migration write on load. Any call site that misses the migration
  reads "nothing claimed" → players re-claim the entire free track (cash
  duplication); a rollback after migration corrupts in the other direction
  (new shape looks empty to old code). Strictly worse.
- A second field `data.SeasonPassClaimed = {}` (parallel table): also safe,
  and the close runner-up. Loses on diff surface: needs its own default,
  its own sanitize line, a second payload field, and a second nil-guard in
  the claim path. The prefix scheme reuses every existing guard unchanged.

### 2.4 Retroactive unlock: derived, never stored

There is no "unlockedAt" or per-tier premium unlock record. Premium
claimability is computed live, per render / per claim:

```
premium tier N is claimable  ⇔  PassOwned  AND  XP ≥ ThresholdFor(N)  AND  not Claimed["pN"]
```

Since `SeasonXP` is already cumulative and never spent, buying the pass at
tier 14 makes premium tiers 1–14 claimable the instant the next `SendState`
lands — retroactivity is emergent, with nothing to migrate or reconcile.

The "next SendState" is guaranteed by a server-side
`PromptGamePassPurchaseFinished` listener in SeasonPassHandler (§4 patch C4)
that re-pushes state on purchase. It uses `task.defer` deliberately:
GamepassService's own listener on the same signal writes the ownership cache,
and cross-script connection order is not guaranteed — deferring runs
`SendState` after **all** listeners for that firing, so `ownsPass()` reads the
fresh cache. (No new remote is needed for buying either:
`MarketplaceService:PromptGamePassPurchase` is callable straight from the
client, and the server never trusts the client — ownership is re-checked
server-side on every claim.)

### 2.5 Payload / remote contract (additive only — legacy client keeps working)

- `SeasonState` server→client payload gains one field: `PassOwned: boolean`.
  Both existing consumers read fields defensively (`s.XP or 0` etc.), so the
  extra field is ignored by un-patched code.
- `SeasonClaim` client→server gains an optional second arg:
  `FireServer(tier, track)` where `track == "pass"` claims premium and
  **anything else — including the nil the legacy SeasonClient still sends —
  means free**. No existing caller breaks.

### 2.6 Fully inert while `GamepassId == 0`

| Layer | Guarantee at id 0 |
|---|---|
| GamepassService | Skips the pass in `refresh` (never queries a bogus id) → nobody ever owns it → `HasFlag` false for everyone |
| SeasonPassHandler | `PassOwned` always false in payload; `"pass"` claims hit two walls: `passConfigured()` false AND `HasFlag` false |
| PassPanel | `passConfigured` false → CTA renders the exact current disabled "COMING SOON"; premium cards LOCKED because `unlocked` now requires `state.PassOwned` (replacing the hard-coded `isPass ⇒ locked`, same visual) |
| Badges | Claimable count only adds premium tiers when `PassOwned` → no ghost badge counts |
| Config | `PassCash` + the new catalog entry are dormant data; SeasonClient ignores both |

Net: with id 0 the game is pixel-identical and byte-identical in behavior to
today.

---

## 3. Activation checklist (owner, later)

1. Creator Dashboard → this game → Monetization → Passes → create "Season
   Pass" (suggested 399 R$ — between FastCharge 99 and VIP 499).
2. Paste the id into `GamepassConfig.lua` (`Key = "SeasonPass"` row),
   replacing the `0`.
3. That's the whole switch. No other file changes.

---

## 4. Patches

### A. `ReplicatedStorage\Modules\GamepassConfig.lua`

**A1 — add the pass to the catalog (line 34, append after the VIP row):**

Before (lines 28–35):
```lua
M.List = {
	{ Key = "Cash2x",      GamepassId = 0, Name = "2x Cash",      Icon = "\u{1F4B0}", Desc = "Double all brainrot income",          RobuxPrice = 199, Effects = { CashMult = 2 } },
	{ Key = "Luck2x",      GamepassId = 0, Name = "2x Luck",      Icon = "\u{1F340}", Desc = "Double your rarity luck on throws",    RobuxPrice = 249, Effects = { LuckMult = 2 } },
	{ Key = "SuperArm",    GamepassId = 0, Name = "Super Arm",    Icon = "\u{1F4AA}", Desc = "Skip rocks much farther",             RobuxPrice = 149, Effects = { PowerMult = 2 } },
	{ Key = "FastCharge",  GamepassId = 0, Name = "Fast Charge",  Icon = "\u{26A1}",  Desc = "Charge your throw meter faster",      RobuxPrice = 99,  Effects = { ChargeMult = 1.75 } },
	{ Key = "AutoCollect", GamepassId = 0, Name = "Auto Collect", Icon = "\u{1F9F2}", Desc = "Automatically collect brainrot cash", RobuxPrice = 299, Effects = { AutoCollect = true } },
	{ Key = "VIP",         GamepassId = 0, Name = "VIP",          Icon = "\u{2B50}",  Desc = "1.5x cash & luck, plus a VIP tag",    RobuxPrice = 499, Effects = { CashMult = 1.5, LuckMult = 1.5, VIP = true } },
}
```

After:
```lua
M.List = {
	{ Key = "Cash2x",      GamepassId = 0, Name = "2x Cash",      Icon = "\u{1F4B0}", Desc = "Double all brainrot income",          RobuxPrice = 199, Effects = { CashMult = 2 } },
	{ Key = "Luck2x",      GamepassId = 0, Name = "2x Luck",      Icon = "\u{1F340}", Desc = "Double your rarity luck on throws",    RobuxPrice = 249, Effects = { LuckMult = 2 } },
	{ Key = "SuperArm",    GamepassId = 0, Name = "Super Arm",    Icon = "\u{1F4AA}", Desc = "Skip rocks much farther",             RobuxPrice = 149, Effects = { PowerMult = 2 } },
	{ Key = "FastCharge",  GamepassId = 0, Name = "Fast Charge",  Icon = "\u{26A1}",  Desc = "Charge your throw meter faster",      RobuxPrice = 99,  Effects = { ChargeMult = 1.75 } },
	{ Key = "AutoCollect", GamepassId = 0, Name = "Auto Collect", Icon = "\u{1F9F2}", Desc = "Automatically collect brainrot cash", RobuxPrice = 299, Effects = { AutoCollect = true } },
	{ Key = "VIP",         GamepassId = 0, Name = "VIP",          Icon = "\u{2B50}",  Desc = "1.5x cash & luck, plus a VIP tag",    RobuxPrice = 499, Effects = { CashMult = 1.5, LuckMult = 1.5, VIP = true } },
	-- SeasonPass is a boolean FLAG (like AutoCollect/VIP), not a multiplier:
	-- SeasonPassHandler gates the premium reward column on
	-- GamepassService.HasFlag(player, "SeasonPass"). A future bundle pass can
	-- also grant the premium track by adding SeasonPass = true to its Effects.
	{ Key = "SeasonPass",  GamepassId = 0, Name = "Season Pass",  Icon = "\u{1F3AB}", Desc = "Unlock the premium season reward track", RobuxPrice = 399, Effects = { SeasonPass = true } },
}
```

### B. `ReplicatedStorage\Modules\SeasonConfig.lua`

**B1 — header comment (line 3):**

Before:
```lua
-- 3 for every player. Free track only for now — premium track needs a gamepass id.
```
After:
```lua
-- 3 for every player. Premium track is gated on the GamepassConfig pass named
-- by M.PASS_KEY below; it stays dormant until that pass gets a real id.
```

**B2 — pass key + premium reward column (lines 31–38):**

Before:
```lua
-- 25 tiers, 250 XP each; cash escalates with milestone spikes every 5th tier
M.XP_PER_TIER = 250
M.Tiers = {}
for i = 1, 25 do
	local cash = math.floor(800 * (1.38 ^ (i - 1)) / 100 + 0.5) * 100
	if i % 5 == 0 then cash = cash * 2 end
	M.Tiers[i] = { XP = M.XP_PER_TIER, Cash = cash, Milestone = i % 5 == 0 }
end
```
After:
```lua
-- GamepassConfig.ByKey key that unlocks the premium column. Single source of
-- truth for SeasonPassHandler (HasFlag gate) and PassPanel (CTA + price).
M.PASS_KEY = "SeasonPass"

-- 25 tiers, 250 XP each; cash escalates with milestone spikes every 5th tier.
-- PassCash is the premium-column reward: 3x free (free cash is a multiple of
-- 100, so 3x stays clean; milestone doubling carries through automatically).
M.XP_PER_TIER = 250
M.Tiers = {}
for i = 1, 25 do
	local cash = math.floor(800 * (1.38 ^ (i - 1)) / 100 + 0.5) * 100
	if i % 5 == 0 then cash = cash * 2 end
	M.Tiers[i] = { XP = M.XP_PER_TIER, Cash = cash, PassCash = cash * 3, Milestone = i % 5 == 0 }
end
```

### C. `ServerScriptService\Modules\SeasonPassHandler.lua`

**C1 — requires + gate helpers (after line 9, `local RarityConfig = ...`):**

Before (lines 7–11):
```lua
local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local SeasonConfig = require(ReplicatedStorage.Modules.SeasonConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)

local remotes = ReplicatedStorage.Remotes
```
After:
```lua
local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local SeasonConfig = require(ReplicatedStorage.Modules.SeasonConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local GamepassConfig = require(ReplicatedStorage.Modules.GamepassConfig)
local GamepassService = require(ServerScriptService.Modules.GamepassService)

local remotes = ReplicatedStorage.Remotes

-- Premium-track gate. Two walls on purpose: passConfigured() keeps the whole
-- premium path inert while the id is still 0 (GamepassService would already
-- return false, but the explicit check documents intent and survives future
-- GamepassService edits); HasFlag (not Owns) means any pass whose Effects
-- carry SeasonPass = true grants the track.
local PASS_KEY = SeasonConfig.PASS_KEY

local function passConfigured()
	local g = GamepassConfig.ByKey[PASS_KEY]
	return g ~= nil and (g.GamepassId or 0) > 0
end

local function ownsPass(player)
	return passConfigured() and GamepassService.HasFlag(player, PASS_KEY)
end
```
(Require-cycle check: GamepassService requires only GamepassConfig — no cycle.
`Main.server.lua` requires both modules before calling any `Init`, and
`GamepassService.Init()` at Main:146 runs after `SeasonPassHandler.Init()` at
Main:112 — fine, because SeasonPassHandler only calls accessors at
player-event time, never at require time.)

**C2 — `SendState` payload (lines 42–48):**

Before:
```lua
	remotes.SeasonState:FireClient(player, {
		XP = data.SeasonXP or 0,
		Claimed = data.SeasonClaimed or {},
		QuestIds = questIds,
		Progress = progress,
		Day = today,
	})
```
After:
```lua
	remotes.SeasonState:FireClient(player, {
		XP = data.SeasonXP or 0,
		Claimed = data.SeasonClaimed or {},
		QuestIds = questIds,
		Progress = progress,
		Day = today,
		PassOwned = ownsPass(player), -- additive field; legacy SeasonClient ignores it
	})
```

**C3 — `claimTier` learns tracks (lines 83–97):**

Before:
```lua
local function claimTier(player, tier)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if typeof(tier) ~= "number" or tier ~= math.floor(tier) then return end
	local def = SeasonConfig.Tiers[tier]
	if not def then return end
	data.SeasonClaimed = data.SeasonClaimed or {}
	local key = tostring(tier) -- datastore-safe key
	if data.SeasonClaimed[key] then return end
	if (data.SeasonXP or 0) < SeasonConfig.ThresholdFor(tier) then return end
	data.SeasonClaimed[key] = true
	PlayerDataManager.GrantCash(data, def.Cash)
	PlayerDataManager.PushUpdate(player)
	SeasonPassHandler.SendState(player)
end
```
After:
```lua
-- track: "pass" claims the premium column; ANYTHING else (including the nil
-- the legacy SeasonClient still sends) means free — old callers keep working.
local function claimTier(player, tier, track)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if typeof(tier) ~= "number" or tier ~= math.floor(tier) then return end
	local def = SeasonConfig.Tiers[tier]
	if not def then return end
	local isPass = track == "pass"
	if isPass and not ownsPass(player) then return end
	data.SeasonClaimed = data.SeasonClaimed or {}
	-- datastore-safe STRING keys on both tracks: free = "7", premium = "p7".
	-- Prefixing keeps existing free-claim saves valid as-is (no migration) and
	-- invisible to any pre-premium reader, which only ever does numeric-string
	-- point lookups.
	local key = isPass and ("p" .. tier) or tostring(tier)
	if data.SeasonClaimed[key] then return end
	if (data.SeasonXP or 0) < SeasonConfig.ThresholdFor(tier) then return end
	data.SeasonClaimed[key] = true
	PlayerDataManager.GrantCash(data, isPass and (def.PassCash or def.Cash) or def.Cash)
	PlayerDataManager.PushUpdate(player)
	SeasonPassHandler.SendState(player)
end
```

**C4 — retroactive re-push on purchase (`Init`, lines 99–106):**

Before:
```lua
function SeasonPassHandler.Init()
	remotes.SeasonClaim.OnServerEvent:Connect(claimTier)
	-- client asks for state once its UI is listening
	remotes.SeasonState.OnServerEvent:Connect(function(player)
		SeasonPassHandler.SendState(player)
	end)
	print("SeasonPassHandler online")
end
```
After:
```lua
function SeasonPassHandler.Init()
	remotes.SeasonClaim.OnServerEvent:Connect(claimTier)
	-- client asks for state once its UI is listening
	remotes.SeasonState.OnServerEvent:Connect(function(player)
		SeasonPassHandler.SendState(player)
	end)

	-- Retroactive unlock: buying the pass mid-session re-pushes SeasonState so
	-- every already-reached premium tier flips to CLAIMABLE immediately (claim
	-- eligibility is derived from XP + ownership, never stored per tier).
	-- task.defer, NOT an inline call: GamepassService's own listener on this
	-- same signal writes the ownership cache, and cross-script connection
	-- order is not guaranteed — deferring runs SendState after ALL listeners
	-- for this firing, so ownsPass() reads the fresh cache.
	local MarketplaceService = game:GetService("MarketplaceService")
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
		if not wasPurchased then return end
		local g = GamepassConfig.ByKey[PASS_KEY]
		if g and (g.GamepassId or 0) > 0 and gamepassId == g.GamepassId then
			task.defer(SeasonPassHandler.SendState, player)
		end
	end)

	print("SeasonPassHandler online")
end
```

### D. `StarterPlayer\StarterPlayerScripts\GameHUDPanels\PassPanel.lua`

**D1 — header note (lines 29–46).** Replace the "why premium is dead"
paragraph ("IMPORTANT game-data note ... revisit when itemized rewards
exist.") with:

```lua
-- Premium column: gated on the GamepassConfig pass named by
-- SeasonConfig.PASS_KEY. The server's SeasonState payload carries
-- PassOwned: boolean (authoritative — HasFlag-checked per claim server-side).
-- While the pass id is 0 (not created yet) PassOwned is always false and
-- passConfigured below is false, so every gold card renders LOCKED and the
-- CTA stays the disabled "COMING SOON" — identical to the pre-premium build.
-- Claim keys: free = tostring(tier), premium = "p" .. tier (one flat
-- server-owned Claimed table; see SeasonPassHandler.claimTier).
--
-- SeasonConfig rewards are scalar cash (Cash / PassCash) -> quantity chip
-- renders x1; revisit when itemized rewards exist.
```

**D2 — requires (lines 48–50):**

Before:
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local modules = ReplicatedStorage:WaitForChild("Modules")
local SeasonConfig = require(modules:WaitForChild("SeasonConfig"))
```
After:
```lua
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local modules = ReplicatedStorage:WaitForChild("Modules")
local SeasonConfig = require(modules:WaitForChild("SeasonConfig"))
local GamepassConfig = require(modules:WaitForChild("GamepassConfig"))
```

**D3 — module-local state (line 91):**

Before:
```lua
	local state = { XP = 0, Claimed = {} }
```
After:
```lua
	local state = { XP = 0, Claimed = {}, PassOwned = false }
```

**D4 — bottom CTA becomes three-state (lines 383–389):**

Before:
```lua
	----------------------------------------------------------- bottom CTA (disabled -- no gamepass id yet, per spec)
	local CTA_W = 320
	local cta = UI.button(panelCol, "COMING SOON", "disabled", UDim2.fromOffset(CTA_W, CTA_H), "buttonL")
	cta.Name = "CTAButton"
	cta.AnchorPoint = Vector2.new(0.5, 0)
	cta.Position = UDim2.new(0.5, 0, 0, BODY_TOP + BODY_H - CTA_OVERLAP)
	cta.ZIndex = 16
```
After:
```lua
	----------------------------------------------------------- bottom CTA (three states, chosen by renderCTA)
	--   pass id == 0        -> ComingSoonCTA visible (disabled style; exact old look)
	--   id set, not owned   -> BuyCTA visible; prompts the Robux purchase
	--   owned               -> neither (the live gold column is the feedback)
	local CTA_W = 320
	local passDef = GamepassConfig.ByKey[SeasonConfig.PASS_KEY]
	local passConfigured = passDef ~= nil and (passDef.GamepassId or 0) > 0

	local cta = UI.button(panelCol, "COMING SOON", "disabled", UDim2.fromOffset(CTA_W, CTA_H), "buttonL")
	cta.Name = "CTAButton"
	cta.AnchorPoint = Vector2.new(0.5, 0)
	cta.Position = UDim2.new(0.5, 0, 0, BODY_TOP + BODY_H - CTA_OVERLAP)
	cta.ZIndex = 16

	-- The buy CTA lives in its own transparent holder so UI.button's
	-- auto-parented HardShadow sibling lands INSIDE the holder and toggles
	-- with it. Two reasons this can't be a bare child of panelCol: (1) the
	-- SkipButton gotcha above -- a HardShadow sibling does not inherit the
	-- button's Visible; (2) panelCol ALREADY holds HardShadow siblings for
	-- the header and body, so FindFirstChild("HardShadow") there would grab
	-- the wrong one. Same containment reasoning as buildRewardCard's slot
	-- wrapper.
	local buyHolder = Instance.new("Frame")
	buyHolder.Name = "BuyCTAHolder"
	buyHolder.AnchorPoint = Vector2.new(0.5, 0)
	buyHolder.Position = UDim2.new(0.5, 0, 0, BODY_TOP + BODY_H - CTA_OVERLAP)
	buyHolder.Size = UDim2.fromOffset(CTA_W, CTA_H)
	buyHolder.BackgroundTransparency = 1
	buyHolder.ZIndex = 16
	buyHolder.Visible = false
	buyHolder.Parent = panelCol

	local buyLabel = passDef and string.format("UNLOCK \u{2014} R$ %d", passDef.RobuxPrice or 0) or "UNLOCK"
	local buyBtn = UI.button(buyHolder, buyLabel, "green", UDim2.fromOffset(CTA_W, CTA_H), "buttonL")
	buyBtn.Name = "BuyCTAButton"
	buyBtn.ZIndex = 16
	-- PromptGamePassPurchase is client-callable; no new remote needed. The
	-- server never trusts this -- ownership is HasFlag-checked on every claim,
	-- and SeasonPassHandler's PromptGamePassPurchaseFinished listener pushes
	-- the fresh SeasonState (PassOwned = true) that re-renders this panel.
	buyBtn.MouseButton1Click:Connect(function()
		if passConfigured then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, passDef.GamepassId)
		end
	end)

	local function renderCTA()
		if not passConfigured then
			cta.Visible = true
			buyHolder.Visible = false
		else
			cta.Visible = false
			buyHolder.Visible = not state.PassOwned
		end
	end
```

**D5 — `buildClaimPill` learns tracks (lines 409–421):**

Before:
```lua
	local function buildClaimPill(card: Frame, tier: number)
		local pill = UI.button(card, "CLAIM", "green", UDim2.new(1, -16, 0, T.size.claimPill), "buttonM")
		pill.Name = "ClaimPill"
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, -8)
		pill.ZIndex = card.ZIndex + 6
		-- The ONE SeasonClaim:FireServer call site in this module. No local
		-- state mutation here -- the card only re-renders CLAIMED once the
		-- server pushes a fresh SeasonState with Claimed[tier] == true.
		pill.MouseButton1Click:Connect(function()
			ctx.remotes.SeasonClaim:FireServer(tier)
		end)
	end
```
After:
```lua
	local function buildClaimPill(card: Frame, tier: number, track: string)
		local pill = UI.button(card, "CLAIM", "green", UDim2.new(1, -16, 0, T.size.claimPill), "buttonM")
		pill.Name = "ClaimPill"
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, -8)
		pill.ZIndex = card.ZIndex + 6
		-- The ONE SeasonClaim:FireServer call site in this module. No local
		-- state mutation here -- the card only re-renders CLAIMED once the
		-- server pushes a fresh SeasonState whose Claimed table has this key.
		pill.MouseButton1Click:Connect(function()
			ctx.remotes.SeasonClaim:FireServer(tier, track)
		end)
	end
```

**D6 — `buildRewardCard` state machine + premium value (lines 482–526).**
Two edits in one function:

Reward value label — before (line 484):
```lua
		local name = UI.label(card, shortCash(def.Cash), "cardLabel", textColor)
```
After:
```lua
		local name = UI.label(card, shortCash(isPass and (def.PassCash or def.Cash) or def.Cash), "cardLabel", textColor)
```

State machine — before (lines 512–526):
```lua
		-- state machine (README §5): LOCKED / CLAIMABLE / CLAIMED. The pass
		-- (gold) column is always LOCKED -- see the module header note on why
		-- passOwned has no backing data in this build.
		local unlocked = (not isPass) and (state.XP >= SeasonConfig.ThresholdFor(tier))
		local claimed = (not isPass) and (state.Claimed[tostring(tier)] == true)

		if isPass or not unlocked then
			buildLockBadge(card)
		elseif not claimed then
			UI.claimRing(card)
			buildClaimPill(card, tier)
			qty.Visible = false -- CLAIMABLE: hide qty chip to give CLAIM pill room
		else
			buildClaimedOverlay(card)
		end
```
After:
```lua
		-- state machine (README §5): LOCKED / CLAIMABLE / CLAIMED, both
		-- columns. Premium adds one AND-term: state.PassOwned (server-sent;
		-- always false while the gamepass id is 0, which keeps the gold
		-- column permanently LOCKED exactly like the pre-premium build).
		-- Retroactivity is free: XP is cumulative, so flipping PassOwned
		-- true makes every already-reached premium tier CLAIMABLE at once.
		local key = isPass and ("p" .. tier) or tostring(tier)
		local unlocked = (state.XP >= SeasonConfig.ThresholdFor(tier))
			and (not isPass or state.PassOwned)
		local claimed = state.Claimed[key] == true

		if not unlocked then
			buildLockBadge(card)
		elseif not claimed then
			UI.claimRing(card)
			buildClaimPill(card, tier, isPass and "pass" or "free")
			qty.Visible = false -- CLAIMABLE: hide qty chip to give CLAIM pill room
		else
			buildClaimedOverlay(card)
		end
```

**D7 — `renderTrack` claimable count (lines 564–580):**

Before:
```lua
	local function renderTrack(): number
		clearRow(freeRow)
		clearRow(badgeRow)
		clearRow(passRow)
		local claimableCount = 0
		for tier, def in ipairs(SeasonConfig.Tiers) do
			buildRewardCard(freeRow, tier, def, "free")
			buildTierBadge(badgeRow, tier)
			buildRewardCard(passRow, tier, def, "pass")
			local unlocked = state.XP >= SeasonConfig.ThresholdFor(tier)
			local claimed = state.Claimed[tostring(tier)] == true
			if unlocked and not claimed then
				claimableCount += 1
			end
		end
		return claimableCount
	end
```
After:
```lua
	local function renderTrack(): number
		clearRow(freeRow)
		clearRow(badgeRow)
		clearRow(passRow)
		local claimableCount = 0
		for tier, def in ipairs(SeasonConfig.Tiers) do
			buildRewardCard(freeRow, tier, def, "free")
			buildTierBadge(badgeRow, tier)
			buildRewardCard(passRow, tier, def, "pass")
			local unlocked = state.XP >= SeasonConfig.ThresholdFor(tier)
			if unlocked and state.Claimed[tostring(tier)] ~= true then
				claimableCount += 1
			end
			-- premium claimables count only for owners: no ghost badge while
			-- the pass id is 0 or for non-buyers
			if state.PassOwned and unlocked and state.Claimed["p" .. tier] ~= true then
				claimableCount += 1
			end
		end
		return claimableCount
	end
```

**D8 — `render` drives the CTA + shares ownership (lines 599–609):**

Before:
```lua
		local claimableCount = renderTrack()

		-- Kit README §5 client state shape -- keep the shared ctx.state.pass
		-- table current for any other consumer (e.g. a future badge/summary).
		ctx.state.pass.level = tierNow
		ctx.state.pass.xp = intoTier
		ctx.state.pass.xpNeed = xpPerTier
		ctx.state.pass.claimedFree = state.Claimed
		if hasServerState then
			ctx.setBadge("pass", claimableCount)
		end
```
After:
```lua
		local claimableCount = renderTrack()
		renderCTA()

		-- Kit README §5 client state shape -- keep the shared ctx.state.pass
		-- table current for any other consumer (e.g. a future badge/summary).
		-- claimedFree keeps its name and shape (the raw server Claimed table;
		-- premium "p" keys ride along invisibly to numeric-key readers).
		ctx.state.pass.level = tierNow
		ctx.state.pass.xp = intoTier
		ctx.state.pass.xpNeed = xpPerTier
		ctx.state.pass.claimedFree = state.Claimed
		ctx.state.pass.passOwned = state.PassOwned
		if hasServerState then
			ctx.setBadge("pass", claimableCount)
		end
```

**D9 — SeasonState listener (lines 623–631):**

Before:
```lua
	ctx.remotes.SeasonState.OnClientEvent:Connect(function(s)
		if typeof(s) ~= "table" then
			return
		end
		hasServerState = true
		state.XP = s.XP or 0
		state.Claimed = s.Claimed or {}
		render()
	end)
```
After:
```lua
	ctx.remotes.SeasonState.OnClientEvent:Connect(function(s)
		if typeof(s) ~= "table" then
			return
		end
		hasServerState = true
		state.XP = s.XP or 0
		state.Claimed = s.Claimed or {}
		state.PassOwned = s.PassOwned == true
		render()
	end)
```

### E. RECOMMENDED — `StarterPlayer\StarterPlayerScripts\SeasonClient.client.lua`

The legacy client still pushes the rail claim badge from join+1s (PassPanel's
badge only takes over after its lazy first open, and its listener connects
later so it wins every subsequent push). Without this patch a pass owner's
badge undercounts premium claimables until they first open the pass panel.
Three one-liners:

Line 127 — before:
```lua
local state = { XP = 0, Claimed = {}, QuestIds = {}, Progress = {} }
```
After:
```lua
local state = { XP = 0, Claimed = {}, QuestIds = {}, Progress = {}, PassOwned = false }
```

Lines 233–237 — before:
```lua
	local claimableCount = 0
	for i, def in ipairs(SeasonConfig.Tiers) do
		local unlocked = state.XP >= SeasonConfig.ThresholdFor(i)
		local claimed = state.Claimed[tostring(i)] == true
		if unlocked and not claimed then claimableCount += 1 end
```
After:
```lua
	local claimableCount = 0
	for i, def in ipairs(SeasonConfig.Tiers) do
		local unlocked = state.XP >= SeasonConfig.ThresholdFor(i)
		local claimed = state.Claimed[tostring(i)] == true
		if unlocked and not claimed then claimableCount += 1 end
		-- premium claimables (badge parity with PassPanel.renderTrack)
		if state.PassOwned and unlocked and state.Claimed["p" .. i] ~= true then claimableCount += 1 end
```
(Note: this legacy panel's own cards still render/claim free-track only —
that is fine; its tile lives on the permanently-hidden legacy rail, so only
its badge reporting matters.)

Lines 336–343 — before:
```lua
seasonState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	state.XP = s.XP or 0
	state.Claimed = s.Claimed or {}
	state.QuestIds = s.QuestIds or {}
	state.Progress = s.Progress or {}
	render()
end)
```
After:
```lua
seasonState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	state.XP = s.XP or 0
	state.Claimed = s.Claimed or {}
	state.QuestIds = s.QuestIds or {}
	state.Progress = s.Progress or {}
	state.PassOwned = s.PassOwned == true
	render()
end)
```

---

## 5. Risks — existing flow and new

Found in the EXISTING claim flow (pre-premium):

1. **Two live SeasonState consumers / claim surfaces.** Legacy
   `SeasonClient.client.lua` still runs alongside PassPanel: same remote, two
   badge writers (last render wins), and its claim button fires
   `SeasonClaim:FireServer(tier)` with one argument. Any contract change MUST
   be additive — this design is (optional `track` arg, extra payload field).
   The badge undercount before PassPanel's first open is real; patch E fixes it.
2. **Join-time ownership race.** `GamepassService.refresh` runs async
   (`task.spawn` + pcall'd `UserOwnsGamePassAsync`); SeasonClient requests
   state at join+1s, which can beat the cache fill → a pass owner's first
   payload may say `PassOwned = false`. Self-healing: every panel open
   re-requests state, and mid-session purchases get the deferred re-push (C4).
   Accepted; do not "fix" by blocking SendState on the marketplace call.
3. **Re-render storm on retro-claim burst.** Each successful claim does
   `PushUpdate` + `SendState`, and each `SendState` makes BOTH clients destroy
   and rebuild the full 25x2 card track. A buyer at tier 25 clicking through
   25 premium claims = 25 full rebuilds. Works, but a "CLAIM ALL" server verb
   (loop tiers, one SendState at the end) is the obvious follow-up.
4. **No season identity.** `SeasonXP`/`SeasonClaimed` never reset; there is no
   season id anywhere. When season 2 ships new Tiers, old claims (free AND
   premium) carry over against the new rewards. Pre-existing issue the premium
   track inherits; the eventual fix is season-scoped keys or a reset-on-launch
   migration — out of scope here, flagged for the Vault & Tide launch work.
5. `claimTier` itself is sound: integer guard rejects NaN (`NaN ~= floor(NaN)`),
   `Tiers[tier]` lookup bounds the index (inf falls out as nil), and there is
   no yield between the claimed-check and the write, so no double-grant race.
   No rate limit on the remote, but every failure path is a cheap early return.

New with the premium track:

6. **Refunds/chargebacks:** ownership is re-checked per claim, but granted
   cash is never clawed back. Standard Roblox monetization posture; accepted.
7. **Purchase-signal dependence:** the retro re-push relies on
   `PromptGamePassPurchaseFinished` firing server-side. If a player buys the
   pass OFF-platform (website) mid-session, no signal fires — they see the
   unlock on next panel open (open always re-requests state, and a fresh
   session's `refresh` catches it). Acceptable degradation.
8. **`task.defer` ordering (C4)** is load-bearing: an inline `SendState` could
   read a stale ownership cache depending on listener connection order. The
   comment in the patch documents this so a future "simplify" pass doesn't
   remove it.

---

## 6. QA checklist (after patching, id still 0)

- [ ] Panel renders pixel-identical to today: gold column all LOCKED, CTA
      "COMING SOON" disabled, no HardShadow ghost near the CTA.
- [ ] Free claims still work; existing test save with claimed free tiers shows
      them CLAIMED (no reset, no re-claim).
- [ ] Firing `SeasonClaim:FireServer(3, "pass")` from the console grants
      nothing (two-wall rejection), no error in output.
- [ ] Rail badge counts unchanged for non-owners.

With a real id (Studio test purchase):

- [ ] Buy prompt opens from the CTA; on purchase the gold column flips every
      reached tier to CLAIMABLE in one push (retroactive), CTA disappears.
- [ ] Premium claim grants `PassCash` (3x), writes `"pN"` key, free `"N"` keys
      untouched (inspect the datastore/session table).
- [ ] Rejoin: pass still owned (cache refresh), claims persist.
- [ ] Badge = free claimables + premium claimables, consistent before and
      after first panel open (patch E).
