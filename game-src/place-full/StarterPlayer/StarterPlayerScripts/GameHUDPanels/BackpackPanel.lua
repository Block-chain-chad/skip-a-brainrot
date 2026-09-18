--!strict
-- BackpackPanel: kit README §3.2 Backpack panel -- a GameHUDPanels consumer module
-- (StarterPlayer.StarterPlayerScripts.GameHUDPanels.BackpackPanel).
--
-- Contract (same as GoalsPanel/DailyPanel/PassPanel): return
--   { Id = "bag", Build = function(ctx) -> Frame }
-- NOTE: Id must match GameHUDClient's RAIL_ORDER rail-item id ("bag"), not the
-- module/instance name ("backpack") -- the registration loop keys panelModules
-- by mod.Id, and openPanel(cfg.id) looks it up by the rail's id scheme.
-- Build is called ONCE lazily on first open; the shell (GameHUDClient) parents
-- the returned Frame into ctx.host and owns Visible toggling on every
-- open/close after that -- this module never sets its own Parent or drives
-- its own open/close animation.
--
-- ============================================================================
-- DATA (read FULLY before writing anything below; see task-8-report.md for
-- the complete trace):
--
--   2026-08-12 MECHANICS REWORK (owner-approved, from the "Roblox inventory
--   UI layout" design handoff): the Tool/hold-E system is GONE. The Brainrots
--   tab is now the whole pickup/placement mechanic -- a 2x8 PLOT RACK (16
--   spots: 12 base, 13-16 purchasable, mirroring PlayerDataManager's
--   BASE_SPOTS/MAX_SPOTS/SPOT_PRICES), an "on your plot" section and a
--   "not equipped" section. Click a bench card -> EquipBrainrot (server
--   places on the first free unlocked pad); click an equipped card or its
--   rack slot -> StoreBrainrot; bench click with the plot full -> the
--   replace picker -> SwapBrainrot(uidOut, uidIn); the next locked rack
--   slot -> unlock modal -> BuyPlotSpot (server TryBuySpot). "Equipped"
--   means PLACED (entry.PadIndex ~= nil), straight from the snapshot --
--   this module keeps NO client-authoritative inventory state and watches
--   no Tool containers. groupBrainrots below is still BackpackClient's
--   grouping (identical name+mutation+size copies stack, richest first),
--   extended with entry.Fav in the key so padlocked copies stack apart.
--
--   ReplicatedStorage.Modules.BrainrotConfig -- array of
--   { Name, Rarity (tier NAME string, e.g. "Legendary"), CashPerSecond,
--   Weight }. Rarity is already the tier name, so no RarityConfig lookup is
--   needed to know which tier an item is in.
--
--   ReplicatedStorage.Modules.RarityConfig -- ordered array of
--   { Name, MinDistance, MaxDistance, Color }, 8 tiers Common..God. Used
--   ONLY to build a rank table (ipairs index) for the tier sub-filter chips'
--   C-R / E-L / M+ buckets (ranks 1-3 / 4-5 / 6-8) -- NOT for colour, since
--   the kit rarity frame uses its own fixed 4-colour + rainbow palette
--   (T.color.rarityCommon/Rare/Epic/Legend + UI.rainbowRing), not
--   RarityConfig's per-tier RGB values.
--
--   ReplicatedStorage.Modules.MutationConfig (Mutations) -- Mutations.Mult(name)
--   multiplies CashPerSecond; used identically to BackpackClient's own sort key.
--
--   ReplicatedStorage.Modules.BrainrotThumb -- BrainrotThumb.add(parent, name,
--   opts) -> ViewportFrame?, the shared 3D-render helper (masters cached by
--   name, every call gets a fresh Clone). Returns nil when no model exists
--   for that name; every call site below falls back to a flat rarity-tinted
--   swatch, same convention BackpackClient/IndexClient use.
--
--   ReplicatedStorage.Modules.PetConfig -- PetConfig.ENABLED gates the Pets
--   tab. A FRESH-CLONE require (bypassing the require-cache-by-Instance trap
--   documented in task-4/7-report.md) confirmed ENABLED == true live in this
--   session, which CONTRADICTS PetHandler.lua's own header comment ("pets,
--   shipped disabled") and Main.lua's comment ("shipped disabled
--   (PetConfig.ENABLED=false)") -- both comments are stale. Per the brief,
--   BOTH branches are built (empty-state AND the real data.Pets grid +
--   PetEquip wiring); this module reads `PetConfig.ENABLED` via a plain
--   top-level `require` rather than a one-time-captured local -- but that is
--   NOT the same as "live": require() caches by Instance (not Source), so
--   every call in this session returns the SAME cached table, and the flag's
--   effective value is SESSION-STATIC from this module's point of view. If
--   the flag is changed later, this panel will only pick that up after a
--   client restart (a fresh require on a fresh Instance) -- not on its own.
--   PetConfig.RARITY_ORDER/RARITY_COLOUR/BoostsFor/Pets are read the same
--   way BackpackClient's own Pets tab reads them.
--
--   ServerScriptService.Modules.UpgradeHandler + ReplicatedStorage.Modules.
--   UpgradeConfig -- read in full. There is NO discrete "owned charm" data
--   shape anywhere: `data.Upgrades` is `[upgradeId] = level` (a plain
--   integer level per one of 4 fixed upgrade ids: Luck/Power/Income/
--   Offline -- "Lucky Charm" is only upgrade #1's DISPLAY NAME, not a
--   collectible item), and UpgradeHandler.Init only wires a BuyUpgrade
--   remote that raises that level. There is nothing ownable to put in a
--   grid. The Charms tab therefore SHIPPED as the EMPTY-STATE branch only.
--
--   2026-08-07 -- that is no longer true. ReplicatedStorage.Modules.
--   CharmConfig now exists (a 16-charm roster with slots, categories and all
--   the copy), and GameHUDPanels.CharmsPanel renders it as its own 1120x700
--   "CHARM CODEX" panel registered under id "charms". The Charms TAB is now a
--   DOORWAY to that panel rather than a tab body: switchTab hands off to
--   ctx.openPanel("charms") -- see the guard there for why the handoff sits
--   in switchTab and NOT in renderCharms. renderCharms below is kept as the
--   fall-through for a ctx with no openPanel; it is not reached in normal play.
--
-- ============================================================================
-- SCOPE decisions (documented, not silent):
--   * Gianluca's Key (a DISPLAY-ONLY profile counter BackpackClient renders
--     as a pinned tile) has no kit slot and is not mentioned in the task
--     brief -- omitted here entirely, same "kit + brief only" discipline
--     other panels' reports document for their own legacy-feature cuts.
--   * SUPERSEDED 2026-08-20 -- see the paragraph below this one. The kit's
--     original "+ Slots" button and "slots" capacity concept were
--     REMOVED per the task brief's explicit spec delta (header counter is
--     "N brainrots · M/6 held", not "28/60 slots"); the kit's dashed
--     unowned-capacity placeholder tiles are dropped along with it -- there
--     is no fixed capacity to draw empty slots for.
--   * (2026-08-20) CAPACITY IS BACK, but only as a NUMBER. Both bags have a
--     real cap now (BagConfig: 25 pets / 150 brainrots, both bought up at
--     Enzo), so the header counter leads with it -- "N/150 brainrots",
--     "N/25 pets" -- and turns red at the line. The kit's dashed placeholder
--     TILES stay dropped: at 150 slots that is a wall of empty boxes, and one
--     counter line says the same thing. The pet FOLLOW-slot row is the sole
--     place empty slots are still drawn as cards -- there are at most eight,
--     and the locked ones double as the shop for buying more.
--   * Brainrot tiles show NO name/price text (kit's own capture renders
--     item_NN.png filling nearly the whole 96x118 tile with only a qty chip
--     and an occasional ribbon -- no label) -- that information lives in the
--     DETAIL column instead, which the kit itself only specifies for this
--     panel (no other panel's grid tiles carry a name either, e.g. Index's
--     idx_NN tiles).
--   * Kit's capture shows a quantity chip on EVERY tile, including "x1"
--     entries -- unlike BackpackClient's own ">1 only" convention, this
--     module always renders the quantity chip, matching the reference
--     image literally.
--   * (2026-08-12) The Brainrots tab has NO detail column and NO tile
--     selection any more -- clicking a card IS the action (equip/store/
--     swap), per the rework handoff. The hover tooltip carries what the
--     detail column used to show. Pets/Keys keep their detail column.
--   * Pets tab mirrors BackpackClient's OWN documented discipline for pets:
--     "Pets are server-authoritative: both the roster and what is equipped
--     come straight from the snapshot" (BackpackClient.lua ~line 783) -- the
--     Pets detail button fires PetEquip and writes NOTHING locally; the tile
--     only shows equipped once a DataUpdated snapshot confirms it. This is
--     the OPPOSITE of the Brainrots branch's local-Tool-mirroring toggleHold,
--     and that split is intentional: it matches what BackpackClient itself
--     does per-domain, not a new invented rule.
--
-- ============================================================================
-- Gotchas carried forward from earlier tasks (see progress.md):
--   * CanvasPosition reset on open: the brainrot/pet grid's
--     AutomaticCanvasSize retains scroll offset across a close/reopen cycle
--     since the ScrollingFrame instance is never destroyed (panelInstances
--     caches Build()'s result) -- CanvasPosition is force-reset to (0,0)
--     every time the wrapper becomes Visible AND on every tab switch.
--   * require() caches by Instance, not Source -- the PetConfig.ENABLED
--     probe (see above) used a fresh Clone() rather than trusting any
--     previously-required copy.
--   * DataUpdated-triggered rebuilds are debounced 0.25s (one pending
--     task.delay at a time, coalescing bursts) -- see scheduleRender below.
--   * Exactly one Heartbeat driver is used for animation (UIKit.Builders'
--     own shared rainbow-ring driver, via UI.rainbowRing) -- no bespoke
--     per-tile animation loop is added anywhere in this module.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService") -- rarity-juice FX driver
local Lighting = game:GetService("Lighting") -- backdrop blur (see setBlur near the wiring)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local BrainrotConfig = require(modules:WaitForChild("BrainrotConfig"))
local RarityConfig = require(modules:WaitForChild("RarityConfig"))
local Mutations = require(modules:WaitForChild("MutationConfig"))
-- SIZE is a second, independent mutation axis that STACKS with the colour one, so a
-- brainrot is grouped, valued and labelled by BOTH -- see SizeConfig's header.
local Sizes = require(modules:WaitForChild("SizeConfig"))
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))
-- The key artwork lives in the kit's own vector icon module, the same place the
-- nav-rail icons come from, so the keys are drawn in the game's style rather than
-- being emoji in a text label.
local IconArt = require(modules:WaitForChild("UIKit"):WaitForChild("IconArt"))
-- 2026-08-09 HUD upgrade: the sheet's shell + parts (see UIKit.SpecTheme)
local PC = require(modules:WaitForChild("UIKit"):WaitForChild("PanelChrome"))
local S = require(modules:WaitForChild("UIKit"):WaitForChild("SpecTheme"))
-- 2026-08-19: device class, for the touch-only card affordances in wireCardHit
-- (long-press to inspect, always-visible fav badge -- a phone has no hover).
local Platform = require(modules:WaitForChild("Platform"))
local SeasonConfig = require(modules:WaitForChild("SeasonConfig")) -- Tags tab: TAGS labels
-- The Index is a TAB in this panel now, not its own rail destination. Required
-- from the sibling module rather than duplicated -- see renderIndex below.
local IndexPanel = require(script.Parent:WaitForChild("IndexPanel"))
-- 2026-08-11: the Charm Codex embeds as a real tab now (same pattern as the
-- Index) instead of the openPanel("charms") doorway that closed the Bag.
local CharmsPanel = require(script.Parent:WaitForChild("CharmsPanel"))
local PetConfigModule = modules:WaitForChild("PetConfig") -- required live, see header note
-- Bag capacity (2026-08-20). The SAME module the server refuses on, so the
-- "17 / 25" this panel prints and the number that blocks an egg purchase are
-- one rule in one file -- see BagConfig's own header on why it is shared.
local BagConfig = require(modules:WaitForChild("BagConfig"))
-- abbreviates $100,000,000 to $100M for the slot cards' price pills
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

-- EVERY WORLD (fixed 2026-08-07). Built from BrainrotConfig alone, this left the 30
-- tundra-exclusive brainrots unknown to the Bag -- $0/s, no rarity tint, sorted last.
-- Valley first so a shared name keeps its World 1 entry.
local WorldProgression = require(modules:WaitForChild("WorldProgression"))
local infoByName = {}
for _, e in ipairs(BrainrotConfig) do
	infoByName[e.Name] = e
end
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	for _, e in ipairs((world and world.Pool) or {}) do
		if not infoByName[e.Name] then infoByName[e.Name] = e end
	end
end

local tierRank = {}
for i, t in ipairs(RarityConfig) do
	tierRank[t.Name] = i
end

local BackpackPanel = { Id = "bag" }

----------------------------------------------------------- shared helpers
local function measureWidth(text: string, sizePx: number, font: Enum.Font): number
	return TextService:GetTextSize(text, sizePx, font, Vector2.new(2000, sizePx + 30)).X
end

-- kit rarity band for a tier NAME (BrainrotConfig.Rarity or PetConfig def.Rarity):
-- Common/Uncommon -> common, Rare -> rare, Epic -> epic, Legendary -> legendary,
-- everything else (Mythic/Secret/God) -> the rainbow ring. Per task-8-brief
-- Step 2 mapping table, verbatim.
local function kitRarityKey(tierName: string?): string
	if tierName == "Common" or tierName == "Uncommon" then
		return "common"
	elseif tierName == "Rare" then
		return "rare"
	elseif tierName == "Epic" then
		return "epic"
	elseif tierName == "Legendary" then
		return "legend" -- UI.rarityFrame's map key, not "legendary"
	end
	return "rainbow" -- Mythic / Secret / God (and pets' own Secret tier)
end

-- Text tint for the detail column's rarity chip. Reuses the exact 4 kit
-- rarity tokens where they exist; for the rainbow band there is no matching
-- T.color entry (the kit only defines a RING treatment for that band, not a
-- flat text colour) so this reuses the rainbow ring's own first gradient
-- stop (#FF5252, see UIKit.Builders.rainbowRing) rather than inventing an
-- unrelated colour -- same "documented kit-token gap" class other panels'
-- reports record for their own off-spec colours.
local function rarityTint(T, tierName: string?): Color3
	local key = kitRarityKey(tierName)
	if key == "common" then
		return T.color.rarityCommon
	elseif key == "rare" then
		return T.color.rarityRare
	elseif key == "epic" then
		return T.color.rarityEpic
	elseif key == "legend" then
		return T.color.rarityLegend
	end
	return T.hex("#FF5252")
end

local function valueOf(name: string, mutation: string?, size: string?): number
	local info = infoByName[name]
	return (info and info.CashPerSecond or 0) * Mutations.Mult(mutation) * Sizes.Mult(size)
end

local function shortCash(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then
		return string.format("$%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("$%.2fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("$%.2fK", n / 1e3)
	end
	return "$" .. tostring(n)
end

local function trimNum(v: number): string
	-- BackpackClient.lua's own trimNum (~line 388): format to 2dp first so
	-- "10" never gets eaten down to "1" by a naive trailing-zero strip.
	local s = string.format("%.2f", v)
	s = s:gsub("0+$", "")
	s = s:gsub("%.$", "")
	return s
end

----------------------------------------------------------- grouping (copied verbatim, see header)
-- Byte-for-byte port of BackpackClient.lua lines ~590-611, only lifted out
-- of buildBrainrots()'s closure into a standalone pure function so it is
-- independently testable (see _groupBrainrots at the bottom of this file).
-- Size joins the grouping key: a Massive Kraken is a DIFFERENT stack from a plain one,
-- the same way a Golden one already is. Without this they would merge and the count
-- would lie about what you actually own.
-- Fav joins the grouping key: a favorited copy (2026-08-22: the raid LOCK, PlotFav,
-- sourced into `Fav` in applySnapshot) is padlocked against raids AND selling, and
-- folding it into a stack of loose copies would make one padlock icon lie about half
-- the stack. Favorited/locked copies form their own card.
local function groupBrainrots(owned: { { Name: string, Mutation: string?, Size: string?, Uid: any, Fav: boolean? } })
	local groups, order = {}, {}
	for _, item in ipairs(owned) do
		local key = (item.Fav and "F|" or "|") .. (item.Mutation or "") .. "|" .. (item.Size or "") .. "|" .. item.Name
		local g = groups[key]
		if not g then
			g = { Name = item.Name, Mutation = item.Mutation, Size = item.Size, Fav = item.Fav or false, count = 0, uids = {} }
			groups[key] = g
			order[#order + 1] = g
		end
		g.count += 1
		g.uids[#g.uids + 1] = item.Uid
	end

	table.sort(order, function(a, b)
		local ia = infoByName[a.Name]
		local ib = infoByName[b.Name]
		local va = (ia and ia.CashPerSecond or 0) * Mutations.Mult(a.Mutation) * Sizes.Mult(a.Size)
		local vb = (ib and ib.CashPerSecond or 0) * Mutations.Mult(b.Mutation) * Sizes.Mult(b.Size)
		if va ~= vb then
			return va > vb
		end
		return a.Name < b.Name
	end)

	return order
end

----------------------------------------------------------- hold flow: RETIRED (2026-08-12 rework)
-- The Tool/hotbar system is gone -- there is no findTool/toggleHold/
-- computeHeldSet any more. "Equipped" now means PLACED ON THE PLOT
-- (entry.PadIndex ~= nil), which arrives in the snapshot like everything
-- else, so this panel no longer watches Backpack/Character containers at all.

----------------------------------------------------------- server-confirmed data (require-time wiring, correctly outside Build)
-- Real "module-top-level capture race fix" this time (the comment that
-- used to sit inside Build claimed this same thing, but traced indentation
-- showed the listener was actually wired ONE LEVEL INSIDE Build -- i.e. it
-- only started listening after the panel's first open, guaranteeing a
-- stale/empty first paint every session; see IndexPanel's own header note
-- on this exact mismatch, which is what this fix now matches).
-- GameHUDPanels modules are require()d once, early, at GameHUDClient's own
-- script top level; Build(ctx) only runs lazily on first open. The
-- server's join-time DataUpdated push (or the one-shot GetInitialData pull
-- below) can land well before this module's Build() ever runs, so
-- `ownedBrainrots`/`ownedPets`/`petSlots` + the listener that fills them
-- are wired here at TRUE module top-level (this code runs once,
-- immediately, at require -- NOT inside Build()), matching BackpackClient's
-- own two-source wiring (initial pull + live push) and mirroring
-- IndexPanel's `discovered` capture exactly. Build() below renders from
-- whatever this capture already holds instead of racing it.
-- `onSnapshotChanged` is forward-declared here and assigned inside Build
-- once `scheduleRender` exists (same forward-declare-then-assign idiom
-- IndexPanel uses for `onDiscoveredChanged`, and GameHUDClient itself uses
-- for openPanel/closePanel) -- scheduleRender needs `wrapper`/
-- `renderActiveTab`, both of which only exist once Build() has actually run.
local ownedBrainrots: { { Name: string, Mutation: string?, Uid: any } } = {} -- UNPLACED only (bench)
-- 2026-08-12 rework: the Brainrots tab renders the WHOLE collection now --
-- equipped entries (PadIndex set) drive the plot rack and the "on your plot"
-- section, so the full list is captured alongside the bench-only view above.
local allBrainrots: { { Name: string, Mutation: string?, Size: string?, Uid: any, PadIndex: number?, Fav: boolean? } } = {}
-- Plot economy for the rack: how many spots are open, what the locked ones
-- cost, and the wallet the unlock modal checks affordability against.
local plotState = { Unlocked = 12, Prices = {} :: { [any]: number }, Cash = 0 }
local ownedPets: { { Uid: string, Id: string } } = {}
local petSlots: { string } = {}
-- Keys tab state. Gianluca's keys are a spendable COUNT (data.Keys); Elder Tung's
-- cellar key is a one-off flag, not a currency -- so the tab renders two different
-- kinds of thing and needs both shapes. The unlock booleans are what let a key read
-- as "already spent, and permanently" instead of just vanishing from the count.
local keyState = { Gianluca = 0, Cellar = false, CellarPaid = false }
-- Season-pass name-plate titles: which ones are owned, and which is worn.
local tagState = { Owned = {}, Equipped = nil }
-- Bag capacity + follow-slot purchases (2026-08-20). Upgrades is carried whole
-- rather than pre-reduced to a number because BagConfig is what turns it into a
-- cap -- keeping the raw table here means this panel never owns a copy of that
-- arithmetic. PendingEggs is only ever needed as a COUNT (the Pets tab's claim
-- button), so it is flattened on the way in.
local bagState = { Upgrades = {}, PetSlotsBought = 0, PetSlotsRobux = 0, PendingEggs = 0, BagX2 = false }
local onSnapshotChanged: (() -> ())? = nil
-- 2026-08-10 rarity-juice pass: uids that arrived AFTER the first snapshot of
-- this session wear a NEW badge until their tile is clicked. Client-only --
-- no save-shape change; a rejoin simply starts the diff over.
local knownUids: { [any]: boolean }? = nil
local newUids: { [any]: boolean } = {}

local function applySnapshot(snap)
	if typeof(snap) ~= "table" or not snap.Brainrots then
		return
	end
	ownedBrainrots = {}
	allBrainrots = {}
	for _, e in ipairs(snap.Brainrots) do
		if e.Uid then
			-- UNIFIED FAVORITE (2026-08-22): the bag's single "favorite" IS the raid
			-- LOCK now (PlotFav) -- capacity-gated, plot-synced, and never-sell. Every
			-- bag surface reads `Fav` (grouping key, badge, stack-apart), so sourcing it
			-- from PlotFav here unifies the whole panel with no other display change. The
			-- old never-sell `e.Fav` is retired (selling now gates on PlotFav too).
			local copy = { Name = e.Name, Mutation = e.Mutation, Size = e.Size, Uid = e.Uid, PadIndex = e.PadIndex, Fav = e.PlotFav or false }
			allBrainrots[#allBrainrots + 1] = copy
			if not e.PadIndex then
				ownedBrainrots[#ownedBrainrots + 1] = copy
			end
		end
	end
	plotState.Unlocked = math.min(tonumber(snap.UnlockedSpots) or 12, 16)
	if typeof(snap.SpotPrices) == "table" then
		-- JSON round-trips turn numeric keys into strings; normalise both ways
		local prices = {}
		for k, v in pairs(snap.SpotPrices) do
			local nk = tonumber(k)
			if nk and tonumber(v) then prices[nk] = tonumber(v) end
		end
		plotState.Prices = prices
	end
	plotState.Cash = tonumber(snap.Cash) or 0
	do
		local current = {}
		for _, e in ipairs(ownedBrainrots) do current[e.Uid] = true end
		if knownUids then
			for uid in pairs(current) do
				if not knownUids[uid] then newUids[uid] = true end
			end
			for uid in pairs(newUids) do
				if not current[uid] then newUids[uid] = nil end
			end
		end
		knownUids = current
	end
	ownedPets = {}
	for _, p in ipairs(snap.Pets or {}) do
		if p.Uid and p.Id then
			ownedPets[#ownedPets + 1] = { Uid = p.Uid, Id = p.Id }
		end
	end
	petSlots = {}
	for _, u in ipairs(snap.PetSlots or {}) do
		petSlots[#petSlots + 1] = u
	end
	keyState = {
		Gianluca = tonumber(snap.Keys) or 0,
		Cellar = snap.TungPortalUnlocked and true or false,
		CellarPaid = snap.CellarUnlocked and true or false,
	}
	tagState = {
		Owned = (typeof(snap.Tags) == "table") and snap.Tags or {},
		Equipped = snap.EquippedTag,
	}
	bagState = {
		Upgrades = (typeof(snap.Upgrades) == "table") and snap.Upgrades or {},
		PetSlotsBought = tonumber(snap.PetSlotsBought) or 0,
		PetSlotsRobux = tonumber(snap.PetSlotsRobux) or 0,
		PendingEggs = (typeof(snap.PendingEggs) == "table") and #snap.PendingEggs or 0,
		-- owns the 2x Backpack gamepass -> BagConfig.BrainrotCap doubles the shown cap
		BagX2 = snap.BagX2 == true,
	}
end

remotes.DataUpdated.OnClientEvent:Connect(function(payload)
	applySnapshot(payload)
	if onSnapshotChanged then
		onSnapshotChanged()
	end
end)
task.spawn(function()
	local ok, snap = pcall(function()
		return remotes.GetInitialData:InvokeServer()
	end)
	if ok then
		applySnapshot(snap)
		if onSnapshotChanged then
			onSnapshotChanged()
		end
	end
end)

function BackpackPanel.Build(ctx)
	local T = ctx.Tokens
	local UI = ctx.Builders

	----------------------------------------------------------- geometry (kit README §3.2 + task-8-brief spec deltas)
	-- 2026-08-09 HUD upgrade: the panel is the sheet's 1080x720 shell; the
	-- body box below is the shell body's INNER space (its padding is baked
	-- into PC.shell), so the three columns keep their absolute layout.
	local PANEL_W = T.size.panelWidth.backpack -- 1080
	local BODY_H = 512 -- 720 - shell pad 36 - header 112 - gap 16 - body pad 44

	local COL_GAP = 14 -- kit "Three columns, gap 14" (untokenised, same class of gap other panels document)
	-- 2026-08-13 PS99 sizing pass (user recording: "the sizing in pet sim is
	-- good, how big everything is"): the 152px labelled tab column becomes a
	-- slim icon rail -- PS99's own category rail is exactly this -- and every
	-- freed pixel goes to the content. 88px wider grids across ALL tabs.
	-- 2026-08-15 readability pass item 3: 100 -> 80. The rail is static chrome --
	-- six tiles that never change -- and at 100 wide it was spending more panel
	-- area than the inventory viewport it sits next to. Every pixel taken off it
	-- flows through GRID_COL_W into INDEX_W/BR_W, so all six tabs get it, and the
	-- 40px icon over a TextScaled label still sits comfortably at 80.
	local TABS_COL_W = 80 -- 2026-08-13 mock restyle: labelled tab tiles (was the 64px icon rail)
	local DETAIL_COL_W = 224
	local CONTENT_H = BODY_H -- shell.body already carries its own padding
	local BODY_INNER_W = 1000 -- 1080 - shell pad 36 - body pad 44
	local GRID_COL_W = BODY_INNER_W - TABS_COL_W - DETAIL_COL_W - COL_GAP * 2 -- 524
	-- The WIDE tab body (grid + detail columns as one span): Index and, since
	-- 2026-08-11, the embedded Charm Codex. Declared here, not at the Index
	-- section, because renderCharms above that section closes over it.
	local INDEX_W = GRID_COL_W + COL_GAP + DETAIL_COL_W

	local TAB_H = 74 -- mock restyle: bigger icon-over-label tiles (62 before; 6x74+5x9 = 489 fits the 512 column)
	local TAB_GAP = 9

	local CHIP_H = 44 -- kit gives no chip spec for THIS panel; reused from §3.5 Index's
	local CHIP_GAP = 9 -- own filter-chip geometry (height 44, gap 9), the closest existing
	local CHIP_TO_GRID_GAP = T.pad.rowGap -- kit spec, cross-panel reuse (documented)

	local GRID_GAP = T.pad.gridGap -- 11
	local SLOT_H = T.size.bagSlot -- 118 (already tokenised)
	local SLOT_W = (GRID_COL_W - GRID_GAP * 4) / 5 -- 5 columns

	local GRID_VIEWPORT_H = CONTENT_H - CHIP_H - CHIP_TO_GRID_GAP

	-- Pets tab slot row (2026-08-11, reworked same day from user recording:
	-- the first cut was 84 tall and grid-column wide, visibly SMALLER than the
	-- Charm Codex's cards it was supposed to mirror). Charms parity: 108 tall
	-- -- the Codex's ROW_H -- and the row spans the FULL wide tab body, so the
	-- five cards land at the same size as the Codex's. renderActiveTab also
	-- reads these: for Pets it keeps the shared detail column visible but
	-- drops it BELOW the slot row.
	local PET_SLOTROW_H = 108 -- ONE card's height; the block below may be 2 of them
	local PET_SLOTROW_GAP = 12
	-- EIGHT SLOTS SINCE 2026-08-20 (3 free + 2 for cash + 3 for Robux), and eight
	-- do not fit one row of the 762px tab body: the cards would come out 84px wide
	-- and the occupant card alone spends 68 of those on its art plate, leaving
	-- nothing for a name. Two rows of four instead -- which makes the cards WIDER
	-- than the five-across row they replace (181 vs 142), so this is a gain for
	-- the equipped-pet card as well as the only way the new slots fit at all.
	-- Every layout that used to size off PET_SLOTROW_H now uses the BLOCK height.
	local PET_SLOT_COLS = 4
	local PET_SLOT_ROWS = 2
	local PET_SLOTROW_VGAP = 10
	local PET_SLOTROW_BLOCK_H = PET_SLOTROW_H * PET_SLOT_ROWS + PET_SLOTROW_VGAP * (PET_SLOT_ROWS - 1)

	-- Pet grid: FOUR columns, not the brainrot grid's five (2026-08-11). A/B'd
	-- on screen at both sizes -- the bigger cell is most of "make the pet card
	-- art look better", because the card is mostly a 3D model and 26 more px of
	-- width is 26 more px of pet. It also lets the name band hold real names
	-- ("Bramble Bear" fits at 4 columns, truncates at 5). Derived, not typed, so
	-- the well padding and gap stay honest if any of them move.
	local PET_COLS = 4
	local PET_WELL_PAD = 8
	local PET_SLOT_W = math.floor((GRID_COL_W - PET_WELL_PAD * 2 - GRID_GAP * (PET_COLS - 1)) / PET_COLS)
	local PET_SLOT_H = math.floor(PET_SLOT_W * 1.07)

	-- COLLAPSIBLE PET SLOT ROW (owner, 2026-08-22) -- the same fold the brainrot bay
	-- has. The 2x4 slot grid is 226px of the tab body, and folding it hands every
	-- one of those pixels to the pet grid below: one visible row of pets becomes
	-- three. A 34px header strip ALWAYS survives the fold, because a collapse with
	-- nothing left to click is a one-way door (the bay keeps its own header for the
	-- same reason).
	--
	-- The flag lives on ctx.state.backpack, not a local, so the choice survives
	-- closing the panel exactly like the selected tab and the bay's own fold do.
	-- Every layout that positions off the slot row -- the row itself, the pet well
	-- and the detail column in renderActiveTab -- reads petSlotBlockH(), so there is
	-- ONE number to keep them in step instead of three copies to forget.
	local PET_SLOTROW_HEAD_H = 34
	local function petSlotsCollapsed(): boolean
		return ctx.state.backpack.petSlotsCollapsed == true
	end
	-- The slot grid ALSO folds while the abilities sheet is open. That sheet is a
	-- reading surface, and against an expanded slot row it gets 231px -- about two
	-- abilities at a time, which is what made it hard to read (owner, 2026-08-22).
	-- Folded it gets 464px. This deliberately does NOT touch the player's own fold
	-- preference: close the sheet and the slots come back exactly as they were,
	-- which is why this is a separate function from petSlotsCollapsed() rather than
	-- a write to that flag.
	local function petSlotsFolded(): boolean
		return petSlotsCollapsed() or ctx.state.backpack.petAbilityHelp == true
	end
	local function petSlotBlockH(): number
		if petSlotsFolded() then return PET_SLOTROW_HEAD_H end
		return PET_SLOTROW_HEAD_H + 8 + PET_SLOTROW_BLOCK_H
	end

	----------------------------------------------------------- module-local state (ephemeral UI selection only; server-confirmed ownedBrainrots/ownedPets/petSlots now live at module top-level, see applySnapshot above)
	local activeTab = ctx.state.backpack.tab or "Brainrots"
	-- Eggs stopped being a tab on 2026-08-06. ctx.state.backpack.tab persists the
	-- last selection, so anyone who was sitting on Eggs would come back to a
	-- renderer with no tab to light up -- content with no visible selection.
	if activeTab == "Eggs" then activeTab = "Brainrots" end

	local tierFilter = "All" -- panel-local only: kit README §5's documented
	-- backpack client-state shape is { tab, selectedUid, items }, with no
	-- room for a sub-filter -- kept as ephemeral UI state here rather than
	-- widening the shared ctx.state contract (which would ripple into every
	-- other panel reading that shape).
	local selectedBrainrotKey: string? = nil -- (Mutation.."|"..Name), independent of Pets' own selection
	local selectedPetUid: string? = nil
	local selectedKeyId: string? = nil

	----------------------------------------------------------- root (2026-08-09 HUD upgrade)
	-- The sheet's PanelChrome shell: 1080x720, GREEN header (the Bag button's
	-- plate colour), close in the header. Everything that used to hang off
	-- the old gold header -- the held counter and EQUIP BEST -- moves onto
	-- the new one; the three-column body is unchanged inside shell.body.
	local shell = PC.shell({
		name = "BackpackPanel",
		title = "BAG",
		key = "bag",
		icon = S.Art.bag, -- PS99 restyle: the rail's own sticker floats in the header
		size = S.ShellFor.backpack,
		scroll = false,
		listLayout = false,
	})
	local wrapper = shell.root
	local header = shell.header
	local body = shell.body
	local shellZ = shell.z

	-- 2026-08-16 PS99 RESTYLE: the Bag is a WHITE panel like the rest of the
	-- HUD now -- white rim, pale cool body, dark outline on the rim and a
	-- soft interior edge on the body. Contained to this panel; no
	-- shared-theme edits.
	wrapper.BackgroundColor3 = Color3.fromHex("FFFFFF")
	body.BackgroundColor3 = Color3.fromHex("F5F8FC")
	do
		local ws = wrapper:FindFirstChildOfClass("UIStroke")
		if ws then ws.Color = Color3.fromHex("313D4F") end
		local bs = body:FindFirstChildOfClass("UIStroke")
		if bs then bs.Color = Color3.fromHex("D8E0EA") end
	end

	-- Spec delta (task-8-brief): "N brainrots . M/6 held". Tracks the title
	-- via TextBounds -- the shell title is a fixed-size frame, so its
	-- AbsoluteSize never moves; its TextBounds does.
	local counterLabel = Instance.new("TextLabel")
	counterLabel.Name = "Counter"
	counterLabel.BackgroundTransparency = 1
	counterLabel.Font = S.Font.Read
	counterLabel.TextSize = 24
	counterLabel.TextColor3 = Color3.fromHex("33414F") -- ink on the white header plate
	counterLabel.Text = "0 brainrots \u{00B7} 0/12 on plot"
	counterLabel.AnchorPoint = Vector2.new(0, 0.5)
	counterLabel.Size = UDim2.new(0, 380, 0, 30)
	counterLabel.TextXAlignment = Enum.TextXAlignment.Left
	counterLabel.ZIndex = shellZ + 3
	counterLabel:SetAttribute("NoPolish", true)
	counterLabel.Parent = header
	do
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = Color3.new(1, 1, 1) -- white halo so the ink counter reads on the plate
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		st.LineJoinMode = Enum.LineJoinMode.Round
		st.Parent = counterLabel
	end

	local COUNTER_GAP = 32 -- visual pass 2026-08-10: 18 sat inside the title's ink stroke
	local TITLE_LEFT = S.Chrome.HeaderPadding + 126 + 18 -- header sticker + gap (PC.shell icon shifts the title right)
	local function layoutCounter()
		-- PS99 restyle fix: TextBounds reads STALE (tiny) while the panel is
		-- hidden, which parked the counter inside the big title. "BAG" at the
		-- 52px title face is ~108px wide -- floor the measurement so a stale
		-- bounds can never tuck the counter under the glyphs.
		counterLabel.Position = UDim2.new(0, TITLE_LEFT + math.max(shell.titleLabel.TextBounds.X, 108) + COUNTER_GAP, 0.5, 0)
	end
	shell.titleLabel:GetPropertyChangedSignal("TextBounds"):Connect(layoutCounter)
	layoutCounter()

	local closeBtn = shell.close

	----------------------------------------------------------- Equip Best
	-- Fills every UNLOCKED pad with the highest-earning brainrots the player
	-- owns. Lives in the HEADER: it acts on the whole bag, and the header is
	-- the only place visible from every tab. The button only ASKS -- ranking,
	-- the unlocked-spot ceiling and every placement is decided by
	-- InventoryHandler.EquipBest on the server.
	local equipBestBtn = PC.pill({
		name = "EquipBestButton",
		text = "EQUIP BEST",
		colors = S.Action.Go,
		size = UDim2.fromOffset(230, 64),
		position = UDim2.new(1, -(S.Chrome.HeaderPadding + S.Chrome.CloseSize + 16), 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		textSize = 24,
		zIndex = shellZ + 3,
		parent = header,
	})
	local equipCaption = equipBestBtn:FindFirstChild("Label")

	-- Matches the server's own 1s guard. Without it a held button queues
	-- presses that the server drops, and the panel would look broken rather
	-- than rate-limited.
	local equipBusy = false
	equipBestBtn.Activated:Connect(function()
		if equipBusy then return end
		-- Resolved at click time: the remote is created by InventoryHandler.Init,
		-- which can land after this panel has already been built.
		local r = remotes:FindFirstChild("EquipBest")
		if not r then return end
		equipBusy = true
		r:FireServer()
		if equipCaption then equipCaption.Text = "PLACING..." end
		task.delay(1.05, function()
			equipBusy = false
			if equipCaption then equipCaption.Text = "EQUIP BEST" end
		end)
	end)

	----------------------------------------------------------- tabs column (152 wide, kit §3.2)
	local tabsCol = Instance.new("Frame")
	tabsCol.Name = "Tabs"
	tabsCol.Position = UDim2.fromOffset(0, 0)
	tabsCol.Size = UDim2.fromOffset(TABS_COL_W, CONTENT_H)
	tabsCol.BackgroundTransparency = 1
	tabsCol.ZIndex = 14
	tabsCol.Parent = body

	-- Category tabs (replaces the kit's own All/Weapons/Units/Boosts/Skins).
	-- NO "+ Slots" button (spec delta).
	--
	-- 2026-08-06, user: EGGS REMOVED. It never held anything -- eggs are cracked
	-- at Gino's stall and hatch straight into the Pets tab, so the tab existed
	-- only to show a "go somewhere else" note. Its renderer is left defined below
	-- (just unreferenced) in case it earns a tab back.
	--
	-- Same pass: every tab now has real art. `icon` is an uploaded asset id and
	-- `art` is an IconArt shape name; the kit only ever shipped 8 icon assets, so
	-- everything outside that set is drawn as vectors rather than left as the grey
	-- UI.artSlot placeholder, which is what the column looked like before.
	local TAB_DEFS = {
		{ id = "Brainrots", label = "Brainrots", icon = T.icons.bag },
		{ id = "Pets", label = "Pets", art = "pet" },
		{ id = "Charms", label = "Charms", art = "charm" },
		-- Keys are not brainrots and were previously invisible: Gianluca's showed only
		-- as a number in the legacy panel and the cellar key was a bare player attribute
		-- with no representation at all.
		{ id = "Keys", label = "Keys", art = "keyGianluca" },
		-- Name-plate titles earned from the season pass. Five tabs fit the 534px
		-- column comfortably (5 x 60 + 4 x 9 = 336).
		{ id = "Tags", label = "Tags", art = "tag" },
		-- The brainrot Index, 2026-08-07: it lost its own rail tile and lives here.
		-- Six rows is 6 x 60 + 5 x 9 = 405, still inside the 534px column.
		{ id = "Index", label = "Index", icon = T.icons.index },
	}

	local tabFrames: { [string]: Frame } = {}
	local tabRings: { [string]: Frame } = {}
	local tabIcons: { [string]: GuiObject } = {}
	-- PS99 sticker pass 2026-08-16: the rail's sticker language, brought inside.
	-- Glyphs go 40 -> 54 (~35% up), the ACTIVE tab's glyph sits ~15% larger
	-- again (set in updateTabVisuals so it survives re-renders), and each glyph
	-- gets an alternating tilt. Tiles/rings/labels stay square.
	local TAB_ICON = 54
	local TAB_ICON_ACTIVE = 62

	for i, def in ipairs(TAB_DEFS) do
		local tab = UI.surface(tabsCol, UDim2.fromOffset(TABS_COL_W, TAB_H), "tab", T.radius.inner, T.stroke.control)
		tab.Name = "Tab" .. def.id
		tab.Position = UDim2.fromOffset(0, (i - 1) * (TAB_H + TAB_GAP))
		tab.ZIndex = 14
		tab.Parent = tabsCol
		-- 2026-08-13 mock restyle: flat dark navy tiles (no gloss/shadow);
		-- updateTabVisuals paints the active one green
		local tabGrad = tab:FindFirstChildOfClass("UIGradient")
		if tabGrad then tabGrad.Color = ColorSequence.new(Color3.fromHex("161C28"), Color3.fromHex("10151F")) end
		do
			local ts = tab:FindFirstChildOfClass("UIStroke")
			if ts then
				ts.Color = Color3.fromHex("2A3242")
				ts.Thickness = 2
			end
		end

		local icon: GuiObject
		if def.art and IconArt.has(def.art) then
			icon = Instance.new("Frame")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromOffset(TAB_ICON, TAB_ICON)
			icon.Parent = tab
			local artRoot = IconArt.draw(icon, def.art, TAB_ICON, tab.ZIndex + 2)
			-- IconArt draws in OFFSET pixels, so resizing this container alone
			-- would not scale the art -- and TweenService in this place only
			-- animates GuiObject properties (a UIScale tween is a silent no-op).
			-- Bridge: the hover/active code tweens or sets the container's Size
			-- (legal), and this binding mirrors it into a UIScale by plain
			-- property SET (also legal), so vector glyphs scale in lockstep.
			-- The container renders nothing, so its own doubled-up bounds are
			-- invisible; centring the art root keeps growth symmetric.
			if artRoot then
				artRoot.AnchorPoint = Vector2.new(0.5, 0.5)
				artRoot.Position = UDim2.fromScale(0.5, 0.5)
			end
			local scaler = Instance.new("UIScale")
			scaler.Parent = icon
			icon:GetPropertyChangedSignal("Size"):Connect(function()
				scaler.Scale = icon.Size.X.Offset / TAB_ICON
			end)
		else
			icon = UI.artSlot(tab, UDim2.fromOffset(TAB_ICON, TAB_ICON), def.icon)
			icon.BackgroundTransparency = 1
		end
		icon.Name = "Icon"
		-- Centre-anchored so the size pop grows from the middle instead of
		-- shoving downward into the label (old geometry: 40px at top y=8,
		-- visual centre y=28; new 54px centred at y=31 tucks ~4px behind the
		-- word, which draws above it -- later sibling wins the ZIndex tie).
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0, 31)
		-- Sticker tilt, alternating down the rail. Glyph ONLY -- never the
		-- tile. Nothing here clips (UI.surface leaves ClipsDescendants false).
		icon.Rotation = (i % 2 == 0) and -6 or 5
		icon.ZIndex = tab.ZIndex + 2

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Font = S.Font.Shout
		label.TextColor3 = T.color.white
		label.Text = string.upper(def.label)
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -6)
		label.Size = UDim2.new(1, -6, 0, 14)
		label.TextScaled = true
		label.ZIndex = tab.ZIndex + 2
		label:SetAttribute("NoPolish", true)
		label.Parent = tab
		do
			local cap = Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = 11
			cap.Parent = label
			local st = Instance.new("UIStroke")
			st.Thickness = 1.4
			st.Color = S.Outline
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			st.LineJoinMode = Enum.LineJoinMode.Round
			st.Parent = label
		end

		local ring = Instance.new("Frame")
		ring.Name = "ActiveRing"
		ring.Size = UDim2.fromScale(1, 1)
		ring.BackgroundTransparency = 1
		ring.Visible = false
		ring.ZIndex = tab.ZIndex + 3
		ring.Parent = tab
		UI.corner(ring, 10)
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Thickness = 3
		ringStroke.Color = Color3.fromHex("7CE04A")
		ringStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ringStroke.Parent = ring

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.ZIndex = tab.ZIndex + 4
		hit.Parent = tab

		tabFrames[def.id] = tab
		tabRings[def.id] = ring
		tabIcons[def.id] = icon
	end

	----------------------------------------------------------- content column (flex, 524 wide)
	local contentHost = Instance.new("Frame")
	contentHost.Name = "Content"
	contentHost.Position = UDim2.fromOffset(TABS_COL_W + COL_GAP, 0)
	contentHost.Size = UDim2.fromOffset(GRID_COL_W, CONTENT_H)
	contentHost.BackgroundTransparency = 1
	contentHost.ZIndex = 14
	contentHost.Parent = body

	----------------------------------------------------------- detail column (224 wide, kit §3.2)
	local detailHost = UI.surface(body, UDim2.fromOffset(DETAIL_COL_W, CONTENT_H), "subPanel", T.radius.control, T.stroke.control)	do
		-- 2026-08-16 PS99 white chrome: the dark-navy detail slab was the last
		-- dark ground inside the white shell. It goes LIGHT (white -> pale cool),
		-- and every renderer that writes into it now carries dark ink
		-- (textMuted / textOnLight + NoPolish) instead of the OnDark family.
		local dg = detailHost:FindFirstChildOfClass("UIGradient")
		if dg then dg.Color = ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("F5F8FC")) end
		local ds = detailHost:FindFirstChildOfClass("UIStroke")
		if ds then ds.Color = Color3.fromHex("D8E0EA") end -- soft interior edge, same family as the body's
	end
	detailHost.Name = "Detail"
	detailHost.Position = UDim2.fromOffset(TABS_COL_W + COL_GAP + GRID_COL_W + COL_GAP, 0)
	detailHost.ZIndex = 14

	-- SCROLLING, not a plain Frame (owner, 2026-08-22: "the option to equip and
	-- unequip pets gets cut off").
	--
	-- This column is a fixed-height clipped box, and the pet detail stacks hero 150
	-- + name 26 + rarity chip 28 + stat rows + a 56 button, which is ~450px. With
	-- the pet slot row EXPANDED the column is only 231px tall, so everything past
	-- the stats fell off the bottom -- and the thing that fell off was the Equip
	-- button, i.e. the only control in the column. That was already true before the
	-- ability rows were added; they made it worse rather than caused it.
	--
	-- A ScrollingFrame fixes it for EVERY renderer that writes here (the brainrot
	-- detail has the same stack), instead of each one having to budget its own
	-- height. AutomaticCanvasSize means the UIListLayout's own measurement drives
	-- the canvas, so nothing has to be totted up by hand.
	local detailContent = Instance.new("ScrollingFrame")
	detailContent.Name = "DetailContent"
	detailContent.Size = UDim2.fromScale(1, 1)
	detailContent.BackgroundTransparency = 1
	detailContent.BorderSizePixel = 0
	detailContent.ScrollingDirection = Enum.ScrollingDirection.Y
	detailContent.ScrollBarThickness = 6
	detailContent.ScrollBarImageColor3 = Color3.fromHex("3A4356")
	detailContent.ScrollBarImageTransparency = 0.35
	detailContent.CanvasSize = UDim2.new()
	detailContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailContent.ElasticBehavior = Enum.ElasticBehavior.Never
	detailContent.ZIndex = detailHost.ZIndex + 1
	detailContent.Parent = detailHost
	local detailPad = Instance.new("UIPadding")
	detailPad.PaddingTop = UDim.new(0, 12)
	detailPad.PaddingBottom = UDim.new(0, 12)
	detailPad.PaddingLeft = UDim.new(0, 12)
	detailPad.PaddingRight = UDim.new(0, 12)
	detailPad.Parent = detailContent
	local detailList = Instance.new("UIListLayout")
	detailList.FillDirection = Enum.FillDirection.Vertical
	detailList.SortOrder = Enum.SortOrder.LayoutOrder
	detailList.Padding = UDim.new(0, T.pad.rowGap)
	detailList.Parent = detailContent

	----------------------------------------------------------- forward decls
	-- All five are mutually referenced from inside click handlers defined
	-- BEFORE their own assignment below (e.g. a grid tile's Hit button calls
	-- renderBrainrots() well before the `renderBrainrots = function() ... end`
	-- line executes) -- forward-declaring the locals here (assigned later via
	-- plain `name = function()`, never `local function name()` again) is what
	-- makes that legal: the upvalue slot exists from this point on, closures
	-- created below capture THIS slot by reference, and by the time any of
	-- them actually fires (a real user click) every assignment below has
	-- already run once, synchronously, during this same Build() call.
	local renderBrainrots, renderPets, renderCharms, renderEggs, renderKeys, renderTags, renderActiveTab

	----------------------------------------------------------- shared build blocks
	local function clearChildren(parent: Instance)
		for _, c in ipairs(parent:GetChildren()) do
			if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
				c:Destroy()
			end
		end
	end

	local function buildEmptyState(parent: Instance, message: string)
		local wrap = Instance.new("Frame")
		wrap.Name = "EmptyState"
		wrap.Size = UDim2.fromScale(1, 1)
		wrap.BackgroundTransparency = 1
		wrap.ZIndex = parent.ZIndex + 1
		wrap.Parent = parent

		local slot = UI.artSlot(wrap, UDim2.fromOffset(120, 120), nil)
		slot.Name = "ArtSlot"
		slot.AnchorPoint = Vector2.new(0.5, 0.5)
		slot.Position = UDim2.new(0.5, 0, 0.5, -30)
		slot.ZIndex = wrap.ZIndex + 1

		-- light grounds now (pale body / light wells): muted INK, with NoPolish
		-- so UIPolish cannot force it back to white
		local label = UI.label(wrap, message, "buttonM", T.color.textMuted)
		label:SetAttribute("NoPolish", true)
		label.Name = "Message"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5, 50)
		label.Size = UDim2.new(1, -40, 0, 30)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = wrap.ZIndex + 1
	end

	local function buildDetailPlaceholder(message: string)
		clearChildren(detailContent)
		local label = UI.label(detailContent, message, "cardLabel", T.color.textMuted) -- muted ink on the light detail ground
		label:SetAttribute("NoPolish", true)
		label.Name = "Placeholder"
		label.LayoutOrder = 1
		label.Size = UDim2.new(1, 0, 0, 60)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = true
		label.ZIndex = detailContent.ZIndex + 1
	end

	-- One shared row builder for the detail column's 3 stat rows (kit §3.2:
	-- "stat rows height 34, radius 10, rgba(0,0,0,.3), key Nunito 14
	-- #C9D6B4 / value 18"). No exact T.text entry for "value 18" (nearest,
	-- cardLabel, is 20/3 with a stroke the kit doesn't ask for here) so the
	-- value label is hand-built, same documented-gap convention as elsewhere.
	local function buildStatRow(order: number, key: string, value: string)
		local row = Instance.new("Frame")
		row.Name = "Stat" .. key
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 34)
		-- PS99: light tile row on the light detail column (was rgba(0,0,0,.3)
		-- on the retired dark slab)
		row.BackgroundColor3 = Color3.fromHex("E4EAF2")
		row.BackgroundTransparency = 0
		row.BorderSizePixel = 0
		row.ZIndex = detailContent.ZIndex + 1
		row.Parent = detailContent
		UI.corner(row, T.radius.slot)

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 10)
		rowPad.PaddingRight = UDim.new(0, 10)
		rowPad.Parent = row

		local keyLabel = UI.label(row, key, "meta", T.color.textMuted) -- muted ink on the light tile
		keyLabel:SetAttribute("NoPolish", true)
		keyLabel.Name = "Key"
		keyLabel.AnchorPoint = Vector2.new(0, 0.5)
		keyLabel.Position = UDim2.new(0, 0, 0.5, 0)
		keyLabel.Size = UDim2.new(0.5, 0, 1, 0)
		keyLabel.AutomaticSize = Enum.AutomaticSize.None
		keyLabel.TextXAlignment = Enum.TextXAlignment.Left
		keyLabel.ZIndex = row.ZIndex + 1

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "Value"
		valueLabel.BackgroundTransparency = 1
		valueLabel.FontFace = T.font.display
		valueLabel.TextSize = 18
		valueLabel.TextColor3 = T.color.textOnLight -- dark ink on the light tile
		valueLabel:SetAttribute("NoPolish", true)
		valueLabel.Text = value
		valueLabel.AnchorPoint = Vector2.new(1, 0.5)
		valueLabel.Position = UDim2.new(1, 0, 0.5, 0)
		valueLabel.Size = UDim2.new(0.5, 0, 1, 0)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.ZIndex = row.ZIndex + 1
		valueLabel.Parent = row
	end

	-- MISSING-ART PLACEHOLDER (2026-08-16 fix). This was a bare half-transparent
	-- tinted plate -- and for an owned item whose Name the config no longer
	-- knows, rarityTint() falls through to the rainbow band's #FF5252, which is
	-- exactly the "flat salmon squares with $0/s" seen in the inventory grid
	-- (entries with no BrainrotConfig/world-pool row and no model in
	-- ReplicatedStorage.BrainrotModels). A missing model now reads as an honest
	-- unknown: a large dark-ink '?' floating over the card's splash, no plate.
	-- `tint` stays in the signature (every call site passes it) but no longer
	-- paints anything.
	local function buildSwatch(parent: Instance, size: UDim2, position: UDim2, zIndex: number, tint: Color3)
		local _ = tint
		local sw = Instance.new("Frame")
		sw.Name = "Swatch"
		sw.Size = size
		sw.Position = position
		sw.BackgroundTransparency = 1
		sw.BorderSizePixel = 0
		sw.ZIndex = zIndex
		sw.Parent = parent
		local q = Instance.new("TextLabel")
		q.Name = "MissingArt"
		q.BackgroundTransparency = 1
		q.Font = S.Font.Shout
		q.TextScaled = true
		q.Text = "?"
		q.TextColor3 = Color3.fromHex("33414F") -- dark ink, house light-surface rule
		q.AnchorPoint = Vector2.new(0.5, 0.5)
		q.Position = UDim2.fromScale(0.5, 0.5)
		q.Size = UDim2.fromScale(0.55, 0.72)
		q.ZIndex = zIndex + 1
		q:SetAttribute("NoPolish", true)
		q.Parent = sw
		local qs = Instance.new("UIStroke")
		qs.Thickness = 2.5
		qs.Color = Color3.new(1, 1, 1) -- white halo so the ink reads on any splash
		qs.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		qs.Parent = q
		return sw
	end

	-- PETS RESOLVE THROUGH A DIFFERENT FOLDER AND A DIFFERENT KEY than brainrots: the
	-- art lives in ReplicatedStorage.PetModels under PetConfig's Model field (the .glb
	-- basename), not in BrainrotModels under the display name. Calling the brainrot path
	-- with a pet's display name misses on both counts, which is why every pet in this
	-- tab used to render as a flat coloured square regardless of the art being present.
	-- RELIT (2026-08-11). A ViewportFrame's stock lighting is a dim grey ambient
	-- with its key light pointing away from the default camera, so every pet
	-- rendered as a flat brown blob -- that, not the layout, was the bulk of
	-- why the pet cards looked bad (proven with side-by-side captures). The opts
	-- are opt-in in BrainrotThumb, so this brightens the PET path only and every
	-- other thumbnail in the game keeps the render it was approved with.
	local PET_ART_AMBIENT = Color3.fromRGB(205, 210, 220)
	local PET_ART_LIGHT = Color3.fromRGB(255, 248, 232)
	local PET_ART_DIR = Vector3.new(-0.8, -0.65, 1) -- from the camera's side, not behind the model
	local function build3DPetOrSwatch(parent: Instance, def, size: UDim2, position: UDim2, zIndex: number, tint: Color3)
		local vp = BrainrotThumb.addPet(parent, def and def.Model, def and def.Name,
			{ size = size, position = position, zIndex = zIndex,
			  ambient = PET_ART_AMBIENT, lightColor = PET_ART_LIGHT, lightDirection = PET_ART_DIR })
		if not vp then
			buildSwatch(parent, size, position, zIndex, tint)
		end
		return vp
	end

	-- Bag art faces the PLAYER (2026-08-12, user: "make all the brainrots facing
	-- toward the players"). The shared DEFAULT_DIR is a 42-degree three-quarter
	-- turn -- fine at hero sizes, reads as a side profile on small cards. Models
	-- front -Z (proven by MassiveEmergence's owner-approved faces-camera yaw:
	-- +1.25pi onto an authored-zero yaw lands exactly on its 45-degree camera
	-- diagonal), so a nearly straight -Z camera with a whisper of turn and lift
	-- is a head-on portrait. Applied here, not in BrainrotThumb: the Index and
	-- egg shop keep the renders they were approved with.
	local BAG_ART_DIR = Vector3.new(0.18, 0.32, -1).Unit
	-- RELIT (2026-08-17), the same treatment the PET path got on 08-11: the
	-- stock viewport rig lit these from BEHIND the head-on portrait camera
	-- (measured live: LightColor 140 grey travelling (-1,-1,-1) against a -Z
	-- camera), so every dark-bodied brainrot rendered as a silhouette blob in
	-- the bay and the grid. Key light now travels FROM the camera's side, warm
	-- and bright; opts are opt-in in BrainrotThumb so the Index and egg shop
	-- keep the renders they were approved with.
	local BAG_ART_AMBIENT = Color3.fromRGB(205, 210, 220)
	local BAG_ART_LIGHT = Color3.fromRGB(255, 248, 232)
	local BAG_ART_LIGHT_DIR = Vector3.new(-0.18, -0.32, 1) -- ~= -BAG_ART_DIR: from the camera, not behind the model
	local function build3DOrSwatch(parent: Instance, name: string, size: UDim2, position: UDim2, zIndex: number, tint: Color3)
		local vp = BrainrotThumb.add(parent, name, { size = size, position = position, zIndex = zIndex, dir = BAG_ART_DIR,
			ambient = BAG_ART_AMBIENT, lightColor = BAG_ART_LIGHT, lightDirection = BAG_ART_LIGHT_DIR })
		if not vp then
			-- same missing-art '?' the pet path uses (see buildSwatch's header:
			-- the old tinted plate here WAS the salmon-square bug)
			buildSwatch(parent, size, position, zIndex, tint)
		end
		return vp
	end

	----------------------------------------------------------- header counter refresh
	-- 2026-08-20: the counter now leads with CAPACITY, and answers for whichever
	-- bag you are looking at. Both bags have a hard ceiling as of this pass, and a
	-- bare "117 brainrots" gave a player no way to see they were two catches from
	-- the wall -- which is where the cap first announces itself, mid-throw.
	-- Numbers come from BagConfig, the same module the server refuses on, so this
	-- line cannot disagree with what actually happens.
	local COUNTER_INK = Color3.fromHex("33414F")
	local COUNTER_FULL = Color3.fromHex("C43B3B") -- reads on the white header plate
	local function refreshHeader()
		if activeTab == "Pets" then
			local PetConfig = require(PetConfigModule)
			local cap = BagConfig.PetCap(bagState.Upgrades)
			local slotCap = tonumber(player:GetAttribute("PetSlotCap")) or PetConfig.SLOTS_FREE
			counterLabel.Text = string.format("%d/%d pets \u{00B7} %d/%d equipped",
				#ownedPets, cap, #petSlots, slotCap)
			counterLabel.TextColor3 = (#ownedPets >= cap) and COUNTER_FULL or COUNTER_INK
			return
		end
		local placed = 0
		for _, e in ipairs(allBrainrots) do
			if e.PadIndex then placed += 1 end
		end
		local cap = BagConfig.BrainrotCap(bagState.Upgrades, bagState.BagX2)
		counterLabel.Text = string.format("%d/%d brainrots \u{00B7} %d/%d on plot",
			#allBrainrots, cap, placed, plotState.Unlocked)
		counterLabel.TextColor3 = (#allBrainrots >= cap) and COUNTER_FULL or COUNTER_INK
	end

	----------------------------------------------------------- BRAINROTS tab
	local grid: ScrollingFrame? = nil

	-- (renderBrainrotDetail + findBrainrotGroup retired 2026-08-12: the detail
	-- column does not exist on the reworked Brainrots tab -- hover tooltips and
	-- the cards themselves carry that information now.)

	-- CELL WRAPPER, and it is not optional. UI.hardShadow parents the shadow as a SIBLING
	-- of the tile (UIKit.Builders: `sh.Parent = frame.Parent`), so dropping tiles straight
	-- into the UIGridLayout gave the layout TWO cells per item -- and because a shadow
	-- carries no LayoutOrder it sorts as 0, ahead of every real tile. With 117 brainrots
	-- that put 117 phantom cells first and pushed the first real tile ~3200px down, far
	-- outside the grid's clipped window: the whole bag rendered as a field of empty dark
	-- rectangles, which were the shadows themselves. Wrapping keeps each shadow inside its
	-- own cell. This is the codebase-wide pattern for exactly this trap -- the same one
	-- EquipSlot above and the egg shop's qty segments already use.
	local function buildTileCell(parent: Instance, name: string, order: number): Frame
		local cell = Instance.new("Frame")
		cell.Name = name
		cell.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = order
		cell.ZIndex = 15
		cell.Parent = parent
		return cell
	end

	-- =========================================================================
	-- PS99 FIELD-STUDY DELTA 4 (2026-08-16, user-approved): grid items lose
	-- their cell boxes. Bare art floats on the panel ground, each item sitting
	-- on a pastel crayon-scribble splash. Applied at the card FACTORIES so
	-- every re-render keeps the treatment: the inventory grid's buildCard
	-- (via its splashKey arg -- the equipped bay omits it and stays boxed;
	-- boxes encode STATE there) and the pets grid's buildPetTile. Keys/tags
	-- tabs and the rack slots are untouched this round.
	local SPLASH_PASTELS = {
		Color3.fromHex("F8C8DC"), -- pink
		Color3.fromHex("C0EAF8"), -- cyan
		Color3.fromHex("FFD9B0"), -- peach
		Color3.fromHex("C8EFB0"), -- mint
		Color3.fromHex("D8C8F5"), -- lavender
	}
	-- Secret-family tiers keep their special border colour as a pastel splash
	-- tint (white:Lerp(border, 0.35)) instead of the 5-hue cycle, so that
	-- identity survives the hidden card stroke. Ordinary tiers cycle by a
	-- stable hash of the item key -- NOT the grid index -- so a search/sort
	-- re-render never reshuffles an item's hue.
	local SPLASH_SPECIAL_TIER: { [string]: boolean } = { Secret = true, God = true }
	local function splashTint(tierName: string?, key: string, borderColour: Color3): Color3
		if tierName and SPLASH_SPECIAL_TIER[tierName] then
			return Color3.new(1, 1, 1):Lerp(borderColour, 0.35)
		end
		local h = 0
		for i2 = 1, #key do
			h = (h * 31 + (string.byte(key, i2) or 0)) % 977
		end
		return SPLASH_PASTELS[(h % #SPLASH_PASTELS) + 1]
	end
	-- A DEEP splash for PALE art (2026-08-25). These cards have no plate -- delta 4
	-- above made them transparent and floats the art on this blob -- so the splash IS
	-- the only backdrop the art gets. Measured, it was nowhere near strong enough:
	-- blended over Surface.Body #F5F8FC at 0.25 transparency the five pastels land at
	-- luminance 0.851-0.908, and a pale model's thumbnail CLIPS TO WHITE (see
	-- BrainrotThumb.meanLuminance), so the contrast was only 0.09-0.15. Snowpuff
	-- (0.960) on the cyan splash (0.908) was a white shape on a near-white shape --
	-- the whole Tundra snow set, pets and brainrots alike, was invisible in this bag.
	--
	-- Deepening the SAME hue keeps the card's colour identity and the crayon-blob
	-- language: only the VALUE changes, and only for art that needs it. The pastels
	-- land at 0.595-0.637, i.e. contrast 0.36-0.41 -- matching the SellPanel art mat
	-- (#96A6C0, 0.645) so the two panels stay in step. Dark art still separates
	-- easily: Bramble Bear renders around 0.24-0.53 against a 0.60 splash.
	local SPLASH_DEEP_INK = Color3.fromRGB(70, 86, 110)
	local SPLASH_DEEP_MIX = 0.45
	local function addSplash(card: GuiObject, colour: Color3, selected: boolean?, deep: boolean?): ImageLabel
		local splash = Instance.new("ImageLabel")
		splash.Name = "Splash"
		splash.BackgroundTransparency = 1
		splash.Image = "rbxassetid://111764682902637" -- white crayon blob, transparent bg
		splash.ScaleType = Enum.ScaleType.Fit
		splash.AnchorPoint = Vector2.new(0.5, 0.5)
		splash.Position = UDim2.fromScale(0.5, 0.5)
		splash.Size = UDim2.new(1.15, 0, 1.15, 0)
		splash.ImageColor3 = if deep then colour:Lerp(SPLASH_DEEP_INK, SPLASH_DEEP_MIX) else colour
		-- a SELECTED card reads stronger (PS99 boxes encode state; where a
		-- selection ring exists it still appears separately, unchanged).
		-- A deep splash also goes (near) opaque -- blending it back toward the
		-- white well is what flattened the pastels in the first place.
		splash.ImageTransparency = if deep
			then (if selected then 0 else 0.05)
			else (if selected then 0.05 else 0.25)
		-- just above the now-invisible plate (card = 15), below all art and
		-- labels (16+); also the FIRST child so equal-Z siblings render above
		splash.ZIndex = 15
		splash.Parent = card
		return splash
	end

	-- =========================================================================
	-- RARITY JUICE (2026-08-10, backpack-mockup.html "implement it but make it
	-- better"): the brainrot grid becomes a dark card well and each tile's
	-- visual energy escalates with tier -- pips, rarity band, holo foil from
	-- Epic, pulsing floor aura from Legendary, animated rainbow band for the
	-- Mythic+ family. Better than the mock: the REAL 8-tier ladder names the
	-- band and colours the outline (the mock had 5 generic tiers), the foil
	-- sits UNDER the 3D model so the art is never recoloured (the mock had to
	-- mask around it), and every animated piece runs off ONE Heartbeat that
	-- stands down when the panel closes or its tiles despawn.
	local RAINBOW = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromHex("FF2D6F")),
		ColorSequenceKeypoint.new(0.17, Color3.fromHex("FF9B2F")),
		ColorSequenceKeypoint.new(0.33, Color3.fromHex("F5F24A")),
		ColorSequenceKeypoint.new(0.50, Color3.fromHex("58F06A")),
		ColorSequenceKeypoint.new(0.67, Color3.fromHex("3FE0FF")),
		ColorSequenceKeypoint.new(0.83, Color3.fromHex("C93AFF")),
		ColorSequenceKeypoint.new(1.00, Color3.fromHex("FF2D6F")),
	})
	local JUICE = {
		common  = { pips = 1, foil = nil,  aura = false, holo = false },
		rare    = { pips = 2, foil = nil,  aura = false, holo = false },
		epic    = { pips = 3, foil = 0.87, aura = false, holo = false },
		legend  = { pips = 4, foil = 0.80, aura = true,  holo = false },
		rainbow = { pips = 5, foil = 0.70, aura = true,  holo = true  },
	}
	local RARITY_RAMP_KEY2 = { Common = "COM", Uncommon = "UNC", Rare = "RARE", Epic = "EPIC",
		Legendary = "LEG", Mythic = "MYTH", Secret = "SEC", God = "GOD" }

	local fx = { drift = {}, pulseBg = {}, pulseStroke = {} }
	local fxConn = nil
	local function stopFx()
		if fxConn then fxConn:Disconnect() fxConn = nil end
		table.clear(fx.drift); table.clear(fx.pulseBg); table.clear(fx.pulseStroke)
	end
	local function ensureFx()
		if fxConn then return end
		local clock = 0
		fxConn = RunService.Heartbeat:Connect(function(dt)
			if not wrapper.Visible then stopFx() return end
			clock += dt
			local slow = (clock * 0.10) % 2 - 1   -- foil drift
			local fast = (clock * 0.30) % 2 - 1   -- holo band sweep
			for i2 = #fx.drift, 1, -1 do
				local e = fx.drift[i2]
				if not e.g.Parent then table.remove(fx.drift, i2)
				else e.g.Offset = Vector2.new(e.fast and fast or slow, 0) end
			end
			local pulse = 0.5 + 0.5 * math.sin(clock * 1.9)
			for i2 = #fx.pulseBg, 1, -1 do
				local e = fx.pulseBg[i2]
				if not e.f.Parent then table.remove(fx.pulseBg, i2)
				else e.f.BackgroundTransparency = e.lo + (e.hi - e.lo) * pulse end
			end
			for i2 = #fx.pulseStroke, 1, -1 do
				local e = fx.pulseStroke[i2]
				if not e.st.Parent then table.remove(fx.pulseStroke, i2)
				else e.st.Transparency = e.lo + (e.hi - e.lo) * pulse end
			end
			if #fx.drift == 0 and #fx.pulseBg == 0 and #fx.pulseStroke == 0 then
				stopFx()
			end
		end)
	end

	-- brainrot-tab view state (search + sort, mock parity). The tier-filter
	-- chips retired with the 2026-08-12 rework -- the equipped/bench split plus
	-- search does their job in less vertical space than the chip row cost.
	local searchQuery = ""
	-- "Backpack Layout" handoff (2026-08-13): three sorts, RARITY default
	local SORT_MODES = { "rarity", "newest", "az" }
	local SORT_LABEL = { rarity = "RARITY", newest = "NEWEST", az = "A\u{2013}Z" }
	local sortMode = "rarity"
	-- Forward decls for the rework's overlays (assigned below buildJuiceTile,
	-- used inside it -- same forward-declare-then-assign idiom as the renderers).
	local openReplacePicker: ((group: any) -> ())? = nil
	local showCardTip: ((group: any, anchor: GuiObject) -> ())? = nil
	local hideCardTip: (() -> ())? = nil
	local countPlaced = function(): number
		local n = 0
		for _, e in ipairs(allBrainrots) do
			if e.PadIndex then n += 1 end
		end
		return n
	end

	local BAND_H = 26 -- PS99 sizing pass: was 24; text inside stepped up with it
	-- Retires buildBrainrotTile below (left in place, no longer called).
	local function buildJuiceTile(parent: Instance, order: number, group, isSelected: boolean, held: { [any]: boolean })
		local cell = buildTileCell(parent, "TileCell" .. order, order)
		local tierName = infoByName[group.Name] and infoByName[group.Name].Rarity
		local ramp = S.Rarity[RARITY_RAMP_KEY2[tierName] or "COM"] or S.Rarity.COM
		local level = JUICE[kitRarityKey(tierName)] or JUICE.common

		local card = Instance.new("Frame")
		card.Name = "Tile" .. order
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = Color3.fromHex("252E3D")
		card.BorderSizePixel = 0
		card.ClipsDescendants = true
		card.ZIndex = 15
		card.Parent = cell
		UI.corner(card, 14)
		local edge = Instance.new("UIStroke")
		edge.Thickness = 3
		edge.Color = ramp[2]
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.LineJoinMode = Enum.LineJoinMode.Round
		edge.Parent = card
		-- (the old dark-navy card gradient is gone with the plate: a gradient on
		-- a fully transparent background painted nothing, and could only come
		-- back as a dark box if the transparency ever regressed)

		if level.aura then
			local aura = Instance.new("Frame")
			aura.Name = "Aura"
			aura.AnchorPoint = Vector2.new(0, 1)
			aura.Position = UDim2.new(0, 0, 1, -BAND_H)
			aura.Size = UDim2.new(1, 0, 0.45, 0)
			aura.BackgroundColor3 = ramp[2]
			aura.BorderSizePixel = 0
			aura.ZIndex = 15
			aura.Parent = card
			local ag = Instance.new("UIGradient")
			ag.Rotation = -90
			ag.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			})
			ag.Parent = aura
			table.insert(fx.pulseBg, { f = aura, lo = 0.25, hi = 0.65 })
		end

		if level.foil then
			local foil = Instance.new("Frame")
			foil.Name = "Foil"
			foil.Size = UDim2.new(1, 0, 1, -BAND_H)
			foil.BackgroundColor3 = Color3.new(1, 1, 1)
			foil.BackgroundTransparency = level.foil
			foil.BorderSizePixel = 0
			foil.ZIndex = 16
			foil.Parent = card
			local fg = Instance.new("UIGradient")
			fg.Rotation = 25
			fg.Color = RAINBOW
			fg.Parent = foil
			table.insert(fx.drift, { g = fg, fast = false })
		end

		local shadowOval = Instance.new("Frame")
		shadowOval.Name = "ContactShadow"
		shadowOval.AnchorPoint = Vector2.new(0.5, 1)
		shadowOval.Position = UDim2.new(0.5, 0, 1, -(BAND_H + 4))
		shadowOval.Size = UDim2.new(0.5, 0, 0, 8)
		shadowOval.BackgroundColor3 = Color3.new(0, 0, 0)
		shadowOval.BackgroundTransparency = 0.55
		shadowOval.BorderSizePixel = 0
		shadowOval.ZIndex = 16
		shadowOval.Parent = card
		UI.corner(shadowOval, 999)

		-- art pushed to the cell edges (PS99 sizing pass): 4px breathing room
		-- instead of 6, and only 8 over the band instead of 12
		local artHolder = Instance.new("Frame")
		artHolder.Name = "Art"
		artHolder.Position = UDim2.new(0, 4, 0, 4)
		artHolder.Size = UDim2.new(1, -8, 1, -(BAND_H + 8))
		artHolder.BackgroundTransparency = 1
		artHolder.ZIndex = 17
		artHolder.Parent = card
		build3DOrSwatch(artHolder, group.Name, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), artHolder.ZIndex + 1, rarityTint(T, tierName))
		if level.holo then
			UI.rainbowRing(artHolder, 12)
		end

		local pips = Instance.new("Frame")
		pips.Name = "Pips"
		pips.Position = UDim2.fromOffset(8, 8)
		pips.Size = UDim2.fromOffset(68, 9)
		pips.BackgroundTransparency = 1
		pips.ZIndex = 19
		pips.Parent = card
		for i2 = 1, 5 do
			local pip = Instance.new("Frame")
			pip.Size = UDim2.fromOffset(7, 7)
			pip.Position = UDim2.fromOffset((i2 - 1) * 12, 1)
			pip.Rotation = 45
			pip.BorderSizePixel = 0
			pip.ZIndex = 19
			pip.BackgroundColor3 = (i2 <= level.pips) and ramp[1] or Color3.fromHex("39414F")
			pip.Parent = pips
		end

		local band = Instance.new("Frame")
		band.Name = "Band"
		band.AnchorPoint = Vector2.new(0, 1)
		band.Position = UDim2.fromScale(0, 1)
		band.Size = UDim2.new(1, 0, 0, BAND_H)
		band.BorderSizePixel = 0
		band.ZIndex = 18
		band.Parent = card
		if level.holo then
			band.BackgroundColor3 = Color3.new(1, 1, 1)
			local bg = Instance.new("UIGradient")
			bg.Color = RAINBOW
			bg.Parent = band
			table.insert(fx.drift, { g = bg, fast = true })
		else
			band.BackgroundColor3 = ramp[2]
			band.BackgroundTransparency = (kitRarityKey(tierName) == "common") and 0.75 or 0.35
		end
		local bname = Instance.new("TextLabel")
		bname.Name = "TierName"
		bname.BackgroundTransparency = 1
		bname.Font = S.Font.Shout
		bname.TextSize = 12
		bname.TextColor3 = level.holo and Color3.fromHex("12060C") or Color3.new(1, 1, 1)
		bname.Text = string.upper(tierName or "?")
		bname.TextXAlignment = Enum.TextXAlignment.Left
		bname.Position = UDim2.fromOffset(8, 0)
		bname.Size = UDim2.new(1, -52, 1, 0)
		bname.ZIndex = 19
		bname:SetAttribute("NoPolish", true)
		bname.Parent = band
		do
			local bst = Instance.new("UIStroke")
			bst.Thickness = 2.4
			bst.Color = Color3.new(1, 1, 1) -- white halo so the ink reads over any splash
			bst.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			bst.Parent = bname
		end
		local bcount = Instance.new("TextLabel")
		bcount.Name = "Count"
		bcount.BackgroundTransparency = 1
		bcount.Font = S.Font.Shout
		bcount.TextSize = 16
		bcount.TextColor3 = level.holo and Color3.fromHex("12060C") or Color3.new(1, 1, 1)
		bcount.Text = group.count > 1 and ("x" .. tostring(group.count)) or ""
		bcount.TextXAlignment = Enum.TextXAlignment.Right
		bcount.AnchorPoint = Vector2.new(1, 0)
		bcount.Position = UDim2.new(1, -8, 0, 0)
		bcount.Size = UDim2.fromOffset(44, BAND_H)
		bcount.ZIndex = 19
		bcount:SetAttribute("NoPolish", true)
		bcount.Parent = band

		-- "held" is the PLACED set now (uid -> padIndex): the green treatment marks
		-- a brainrot that is out on the plot earning, not a Tool in a hand.
		local isHeld, heldPad = false, nil
		for _, uid in ipairs(group.uids) do
			if held[uid] then
				isHeld = true
				heldPad = held[uid]
				break
			end
		end
		local isNew = false
		for _, uid in ipairs(group.uids) do
			if newUids[uid] then isNew = true break end
		end
		local bx = -6
		if isHeld then
			-- the badge carries the SLOT NUMBER now, so a card in the "on your
			-- plot" section answers "where?" without hunting the rack
			local beq = Instance.new("Frame")
			beq.Name = "EquippedBadge"
			beq.AnchorPoint = Vector2.new(1, 0)
			beq.Position = UDim2.new(1, bx, 0, 6)
			beq.Size = UDim2.fromOffset(heldPad and 34 or 22, 22)
			beq.BackgroundColor3 = Color3.fromHex("3DDC84")
			beq.BorderSizePixel = 0
			beq.ZIndex = 19
			beq.Parent = card
			UI.corner(beq, 6)
			local ck = Instance.new("TextLabel")
			ck.BackgroundTransparency = 1
			ck.Size = UDim2.fromScale(1, 1)
			ck.Font = S.Font.Shout
			ck.TextSize = 14
			ck.Text = heldPad and ("\u{2713}" .. tostring(heldPad)) or "\u{2713}"
			ck.TextColor3 = Color3.fromHex("06301B")
			ck.ZIndex = 20
			ck:SetAttribute("NoPolish", true)
			ck.Parent = beq
			bx -= (heldPad and 41 or 29)
			local ring = Instance.new("UIStroke")
			ring.Thickness = 2
			ring.Color = Color3.fromHex("3DDC84")
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ring.Parent = card
			table.insert(fx.pulseStroke, { st = ring, lo = 0.25, hi = 0.75 })
		end
		if isNew then
			local bnew = Instance.new("TextLabel")
			bnew.Name = "NewBadge"
			bnew.AnchorPoint = Vector2.new(1, 0)
			bnew.Position = UDim2.new(1, bx, 0, 6)
			bnew.Size = UDim2.fromOffset(38, 19)
			bnew.BackgroundColor3 = Color3.fromHex("FF3D6E")
			bnew.Font = S.Font.Shout
			bnew.TextSize = 10
			bnew.Text = "NEW"
			bnew.TextColor3 = Color3.new(1, 1, 1)
			bnew.ZIndex = 19
			bnew:SetAttribute("NoPolish", true)
			bnew.Parent = card
			UI.corner(bnew, 5)
		end

		if isSelected then
			local sel = Instance.new("Frame")
			sel.Name = "SelectedRing"
			sel.Size = UDim2.fromScale(1, 1)
			sel.BackgroundTransparency = 1
			sel.ZIndex = 20
			sel.Parent = card
			UI.corner(sel, 14)
			local selStroke = Instance.new("UIStroke")
			selStroke.Thickness = 3
			selStroke.Color = T.color.activeRing
			selStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			selStroke.Parent = sel
		end

		-- favorite padlock (2026-08-12 rework): gold = padlocked against selling.
		-- A real button ABOVE the card's own hit so clicking it can never also
		-- equip -- the Roblox equivalent of the spec's stopPropagation demand.
		local fav = Instance.new("TextButton")
		fav.Name = "FavLock"
		fav.AnchorPoint = Vector2.new(1, 1)
		fav.Position = UDim2.new(1, -5, 1, -(BAND_H + 5))
		fav.Size = UDim2.fromOffset(24, 24)
		fav.Text = ""
		fav.AutoButtonColor = false
		fav.BorderSizePixel = 0
		fav.BackgroundColor3 = group.Fav and Color3.fromHex("F0B312") or Color3.fromHex("1A2130")
		fav.BackgroundTransparency = group.Fav and 0 or 0.25
		fav.ZIndex = 22
		fav.Parent = card
		UI.corner(fav, 7)
		do
			local fs = Instance.new("UIStroke")
			fs.Thickness = 2
			fs.Color = group.Fav and Color3.fromHex("8A6510") or Color3.fromHex("2C3444")
			fs.Parent = fav
			-- vector padlock: the lock emoji is one of the glyphs Roblox fonts
			-- drop on some platforms (same gotcha as the icon-art pass)
			local ink = group.Fav and Color3.fromHex("3A2A00") or Color3.fromHex("5D6878")
			local lockBody = Instance.new("Frame")
			lockBody.AnchorPoint = Vector2.new(0.5, 1)
			lockBody.Position = UDim2.new(0.5, 0, 1, -4)
			lockBody.Size = UDim2.fromOffset(10, 7)
			lockBody.BackgroundColor3 = ink
			lockBody.BorderSizePixel = 0
			lockBody.ZIndex = 23
			lockBody.Parent = fav
			UI.corner(lockBody, 2)
			local shackle = Instance.new("Frame")
			shackle.AnchorPoint = Vector2.new(0.5, 1)
			shackle.Position = UDim2.new(0.5, 0, 1, -10)
			shackle.Size = UDim2.fromOffset(7, 5)
			shackle.BackgroundTransparency = 1
			shackle.ZIndex = 23
			shackle.Parent = fav
			UI.corner(shackle, 999)
			local ss = Instance.new("UIStroke")
			ss.Thickness = 2
			ss.Color = ink
			ss.Parent = shackle
		end
		fav.MouseButton1Click:Connect(function()
			local r = remotes:FindFirstChild("ToggleFavorite")
			if r then r:FireServer(group.uids) end
			-- no local rerender: the snapshot push confirms and redraws
		end)

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.ZIndex = 21
		hit.Parent = card
		local HOVER_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		hit.MouseEnter:Connect(function()
			cell.ZIndex = 30
			game:GetService("TweenService"):Create(card, HOVER_INFO, { Size = UDim2.new(1, 8, 1, 8) }):Play()
			if showCardTip then showCardTip(group, card) end
		end)
		hit.MouseLeave:Connect(function()
			cell.ZIndex = 15
			game:GetService("TweenService"):Create(card, HOVER_INFO, { Size = UDim2.fromScale(1, 1) }):Play()
			if hideCardTip then hideCardTip() end
		end)
		hit.MouseButton1Click:Connect(function()
			for _, uid in ipairs(group.uids) do newUids[uid] = nil end
			if hideCardTip then hideCardTip() end
			if group.PadIndex then
				-- on the plot -> take it off (server validates the uid is really out)
				remotes.StoreBrainrot:FireServer(group.uids[1])
			elseif countPlaced() < plotState.Unlocked then
				-- bench + a free spot -> server places it on the first free pad
				remotes.EquipBrainrot:FireServer(group.uids[1])
			elseif openReplacePicker then
				-- bench + plot full -> pick who comes off
				openReplacePicker(group)
			end
		end)

		if level.aura or level.foil or level.holo or isHeld then
			ensureFx()
		end
	end

	----------------------------------------------------------- hover tooltip (2026-08-12 rework; PS99 delta 10 2026-08-16)
	-- ONE shared PanelChrome tooltip now (PC.tooltip: the white shadowed card,
	-- self-positioning beside its anchor with scale-relative math -- immune by
	-- construction to the ~0.72 cumulative-UIScale offset trap the old bespoke
	-- CardTip had to hand-correct). Created once at Build time on the shell
	-- root; PC-only (no hover on touch). Carries what the retired detail
	-- column used to show -- name, tier, income, stack size -- with the old
	-- CTA line mapped into `desc` and stack count / fav padlock into `meta`.
	local cardTip = PC.tooltip({ parent = wrapper, zIndex = shellZ + 45 })

	hideCardTip = function()
		cardTip.hide()
	end

	showCardTip = function(group, anchor: GuiObject)
		-- 2026-08-19 TOUCH FIX. This used to `return` outright when there was no
		-- mouse, which -- combined with the tip being triggered from MouseEnter
		-- (a signal touch never fires) -- meant PHONE PLAYERS COULD NOT READ ITEM
		-- NAMES AT ALL: the 2026-08-14 pass moved names off the cards INTO this
		-- tooltip, so the card shows art/rate/count/star and nothing else. Touch
		-- now reaches it by long-press (see wireCardHit), so the gate is gone.
		local tierName = infoByName[group.Name] and infoByName[group.Name].Rarity
		local ramp = S.Rarity[RARITY_RAMP_KEY2[tierName] or "COM"] or S.Rarity.COM
		-- the old tip's CTA line rides in `desc` so no information is dropped
		local desc
		if group.PadIndex then
			desc = "Click to take it off your plot"
		elseif countPlaced() < plotState.Unlocked then
			desc = "Click to place it on your plot"
		else
			desc = "Plot full \u{2014} unlock another slot"
		end
		local meta: string? = nil
		if group.count and group.count > 1 then
			meta = "x" .. tostring(group.count)
		end
		if group.Fav then
			meta = (meta and (meta .. " \u{00B7} ") or "") .. "LOCKED"
		end
		cardTip.show(anchor, {
			name = Sizes.Label(group.Mutation, group.Size, group.Name),
			rarity = tierName or "?",
			rarityColor = ramp[2],
			-- top-family tiers retint the whole card, PC.tooltip's own signal
			tintCard = tierName == "Secret" or tierName == "God",
			desc = desc,
			meta = meta,
			price = shortCash(valueOf(group.Name, group.Mutation, group.Size)) .. "/s",
		})
	end

	----------------------------------------------------------- modals (2026-08-12 rework)
	-- Scrim + window dialog, both parented to the shell root so they cover the
	-- whole panel. One modal at a time; the scrim click always cancels.
	local activeModal: Frame? = nil
	local function closeModal()
		if activeModal then
			activeModal:Destroy()
			activeModal = nil
		end
	end

	local function openModalScrim(): (TextButton, number)
		closeModal()
		hideCardTip()
		local scrim = Instance.new("TextButton")
		scrim.Name = "BagModal"
		scrim.Text = ""
		scrim.AutoButtonColor = false
		scrim.Size = UDim2.fromScale(1, 1)
		-- WHITE WASH, not a dark dim (2026-08-17 round-9): this scrim sits over
		-- the panel's own GUI content, which a Lighting BlurEffect cannot blur,
		-- so the dim-to-blur recipe does not apply here. On the light PS99 shell
		-- the light-UI sheet treatment reads right: a white wash recedes the
		-- panel behind the dialog without going dark. Click-to-cancel unchanged.
		scrim.BackgroundColor3 = Color3.new(1, 1, 1)
		scrim.BackgroundTransparency = 0.3
		scrim.BorderSizePixel = 0
		scrim.ZIndex = shellZ + 30
		scrim.Parent = wrapper
		scrim.MouseButton1Click:Connect(closeModal)
		activeModal = scrim
		return scrim, scrim.ZIndex
	end

	-- small vector padlock -- emoji glyphs are unreliable in Roblox fonts
	local function buildPadlock(parent: Instance, px: number, tint: Color3, zIndex: number)
		local body = Instance.new("Frame")
		body.AnchorPoint = Vector2.new(0.5, 1)
		body.Position = UDim2.new(0.5, 0, 1, 0)
		body.Size = UDim2.fromOffset(px, math.floor(px * 0.72))
		body.BackgroundColor3 = tint
		body.BorderSizePixel = 0
		body.ZIndex = zIndex
		body.Parent = parent
		UI.corner(body, math.max(3, math.floor(px * 0.2)))
		local shackle = Instance.new("Frame")
		shackle.AnchorPoint = Vector2.new(0.5, 1)
		shackle.Position = UDim2.new(0.5, 0, 0, math.floor(px * 0.1))
		shackle.Size = UDim2.fromOffset(math.floor(px * 0.62), math.floor(px * 0.42))
		shackle.BackgroundTransparency = 1
		shackle.ZIndex = zIndex
		shackle.Parent = parent
		UI.corner(shackle, 999)
		local ss = Instance.new("UIStroke")
		ss.Thickness = math.max(2, math.floor(px * 0.14))
		ss.Color = tint
		ss.Parent = shackle
		return body
	end

	local function openUnlockModal(spot: number, price: number)
		local scrim, z = openModalScrim()

		local dlg = UI.surface(scrim, UDim2.fromOffset(400, 264), "panel", T.radius.panel, T.stroke.panel)
		dlg.Name = "UnlockDialog"
		dlg.AnchorPoint = Vector2.new(0.5, 0.5)
		dlg.Position = UDim2.fromScale(0.5, 0.5)
		dlg.ZIndex = z + 1
		dlg.Active = true -- eat clicks so the scrim-cancel under it does not fire

		local lockHolder = Instance.new("Frame")
		lockHolder.BackgroundTransparency = 1
		lockHolder.AnchorPoint = Vector2.new(0.5, 0)
		lockHolder.Position = UDim2.new(0.5, 0, 0, 14)
		lockHolder.Size = UDim2.fromOffset(34, 34)
		lockHolder.ZIndex = z + 2
		lockHolder.Parent = dlg
		buildPadlock(lockHolder, 26, T.color.outline, z + 2)

		local title = UI.label(dlg, "Unlock spot " .. spot .. "?", "buttonL", T.color.textOnWindow)
		title.AnchorPoint = Vector2.new(0.5, 0)
		title.Position = UDim2.new(0.5, 0, 0, 52)
		title.AutomaticSize = Enum.AutomaticSize.XY
		title.TextXAlignment = Enum.TextXAlignment.Center
		title.ZIndex = z + 2

		local body = Instance.new("TextLabel")
		body.BackgroundTransparency = 1
		body.Font = S.Font.Read
		body.TextSize = 15
		body.TextColor3 = Color3.fromHex("5D6B7A")
		body.TextWrapped = true
		body.Text = "Adds a permanent spot to your plot, in every world your camp exists in."
		body.AnchorPoint = Vector2.new(0.5, 0)
		body.Position = UDim2.new(0.5, 0, 0, 88)
		body.Size = UDim2.new(1, -60, 0, 40)
		body.ZIndex = z + 2
		body:SetAttribute("NoPolish", true)
		body.Parent = dlg

		local chip = UI.surface(dlg, UDim2.fromOffset(190, 44), "row", T.radius.inner, T.stroke.control)
		chip.AnchorPoint = Vector2.new(0.5, 0)
		chip.Position = UDim2.new(0.5, 0, 0, 134)
		chip.ZIndex = z + 2
		local coin = Instance.new("ImageLabel")
		coin.BackgroundTransparency = 1
		coin.Image = T.icons.coin
		coin.Size = UDim2.fromOffset(28, 28)
		coin.AnchorPoint = Vector2.new(0, 0.5)
		coin.Position = UDim2.new(0, 10, 0.5, 0)
		coin.ZIndex = z + 3
		coin.Parent = chip
		local amount = UI.label(chip, shortCash(price), "value", T.color.textAccentOnDark)
		amount.AnchorPoint = Vector2.new(0, 0.5)
		amount.Position = UDim2.new(0, 46, 0.5, 0)
		amount.ZIndex = z + 3

		local canAfford = plotState.Cash >= price
		local cancelBtn = UI.button(dlg, "CANCEL", "tab", UDim2.fromOffset(140, 48), "buttonM")
		cancelBtn.AnchorPoint = Vector2.new(1, 1)
		cancelBtn.Position = UDim2.new(0.5, -8, 1, -16)
		cancelBtn.ZIndex = z + 2
		cancelBtn.MouseButton1Click:Connect(closeModal)

		local okBtn = UI.button(dlg, canAfford and "UNLOCK" or "NEED " .. shortCash(price),
			canAfford and "green" or "disabled", UDim2.fromOffset(150, 48), "buttonM")
		okBtn.AnchorPoint = Vector2.new(0, 1)
		okBtn.Position = UDim2.new(0.5, 8, 1, -16)
		okBtn.ZIndex = z + 2
		if canAfford then
			okBtn.MouseButton1Click:Connect(function()
				local r = remotes:FindFirstChild("BuyPlotSpot")
				if r then r:FireServer() end
				closeModal()
			end)
		end
	end

	openReplacePicker = function(incoming)
		local scrim, z = openModalScrim()

		local placedEntries = {}
		for _, e in ipairs(allBrainrots) do
			if e.PadIndex then placedEntries[#placedEntries + 1] = e end
		end
		table.sort(placedEntries, function(x, y) return (x.PadIndex or 0) < (y.PadIndex or 0) end)
		if #placedEntries == 0 then closeModal() return end

		local COLS = 4
		local CELL_W, CELL_H, GAPX = 136, 118, 10
		local rows = math.ceil(#placedEntries / COLS)
		local gridH = rows * CELL_H + (rows - 1) * 8
		local dlgH = math.min(150 + gridH + 74, 560)

		local dlg = UI.surface(scrim, UDim2.fromOffset(620, dlgH), "panel", T.radius.panel, T.stroke.panel)
		dlg.Name = "ReplaceDialog"
		dlg.AnchorPoint = Vector2.new(0.5, 0.5)
		dlg.Position = UDim2.fromScale(0.5, 0.5)
		dlg.ZIndex = z + 1
		dlg.Active = true

		local title = UI.label(dlg, "Your plot is full", "buttonL", T.color.textOnWindow)
		title.AnchorPoint = Vector2.new(0.5, 0)
		title.Position = UDim2.new(0.5, 0, 0, 16)
		title.AutomaticSize = Enum.AutomaticSize.XY
		title.ZIndex = z + 2

		local incomingValue = valueOf(incoming.Name, incoming.Mutation, incoming.Size)
		local body = Instance.new("TextLabel")
		body.BackgroundTransparency = 1
		body.Font = S.Font.Read
		body.TextSize = 15
		body.TextColor3 = Color3.fromHex("5D6B7A")
		body.TextWrapped = true
		body.Text = "All " .. plotState.Unlocked .. " spots are taken. Pick who "
			.. Sizes.Label(incoming.Mutation, incoming.Size, incoming.Name)
			.. " (" .. shortCash(incomingValue) .. "/s) should replace."
		body.AnchorPoint = Vector2.new(0.5, 0)
		body.Position = UDim2.new(0.5, 0, 0, 52)
		body.Size = UDim2.new(1, -48, 0, 40)
		body.ZIndex = z + 2
		body:SetAttribute("NoPolish", true)
		body.Parent = dlg

		-- lowest earner gets the highlighted callout -- the obvious drop
		local lowestUid, lowestV = nil, math.huge
		for _, e in ipairs(placedEntries) do
			local v = valueOf(e.Name, e.Mutation, e.Size)
			if v < lowestV then lowestV, lowestUid = v, e.Uid end
		end

		local gridHost = Instance.new("ScrollingFrame")
		gridHost.BackgroundTransparency = 1
		gridHost.BorderSizePixel = 0
		gridHost.Position = UDim2.fromOffset(24, 100)
		gridHost.Size = UDim2.new(1, -48, 1, -174)
		gridHost.CanvasSize = UDim2.new()
		gridHost.AutomaticCanvasSize = Enum.AutomaticSize.Y
		gridHost.ScrollBarThickness = 5
		gridHost.ScrollingDirection = Enum.ScrollingDirection.Y
		gridHost.ElasticBehavior = Enum.ElasticBehavior.Never
		gridHost.ZIndex = z + 2
		gridHost.Parent = dlg
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(CELL_W, CELL_H)
		gl.CellPadding = UDim2.fromOffset(GAPX, 8)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = gridHost

		for i, e in ipairs(placedEntries) do
			local isLowest = (e.Uid == lowestUid)
			local v = valueOf(e.Name, e.Mutation, e.Size)

			local opt = Instance.new("TextButton")
			opt.Name = "Swap" .. tostring(e.Uid)
			opt.Text = ""
			opt.AutoButtonColor = false
			opt.LayoutOrder = i
			opt.BackgroundColor3 = isLowest and Color3.fromHex("E4EDFB") or Color3.fromHex("F2F4FA")
			opt.BorderSizePixel = 0
			opt.ZIndex = z + 3
			opt.Parent = gridHost
			UI.corner(opt, T.radius.inner)
			local ost = Instance.new("UIStroke")
			ost.Thickness = 3
			ost.Color = isLowest and T.color.activeRing or Color3.fromHex("C9CFDD")
			ost.Parent = opt

			local slotNo = Instance.new("TextLabel")
			slotNo.BackgroundTransparency = 1
			slotNo.Font = S.Font.Shout
			slotNo.TextSize = 11
			slotNo.TextColor3 = Color3.fromHex("8B93A8")
			slotNo.Text = "#" .. tostring(e.PadIndex)
			slotNo.Position = UDim2.fromOffset(7, 4)
			slotNo.Size = UDim2.fromOffset(30, 12)
			slotNo.TextXAlignment = Enum.TextXAlignment.Left
			slotNo.ZIndex = z + 4
			slotNo:SetAttribute("NoPolish", true)
			slotNo.Parent = opt

			local art = Instance.new("Frame")
			art.BackgroundTransparency = 1
			art.AnchorPoint = Vector2.new(0.5, 0)
			art.Position = UDim2.new(0.5, 0, 0, 14)
			art.Size = UDim2.fromOffset(52, 52)
			art.ZIndex = z + 4
			art.Parent = opt
			local tier2 = infoByName[e.Name] and infoByName[e.Name].Rarity
			build3DOrSwatch(art, e.Name, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), z + 4, rarityTint(T, tier2))

			local nm = Instance.new("TextLabel")
			nm.BackgroundTransparency = 1
			nm.Font = S.Font.Read
			nm.TextSize = 13
			nm.TextColor3 = Color3.fromHex("3A3A45")
			nm.TextTruncate = Enum.TextTruncate.AtEnd
			nm.Text = Sizes.Label(e.Mutation, e.Size, e.Name)
			nm.AnchorPoint = Vector2.new(0.5, 0)
			nm.Position = UDim2.new(0.5, 0, 0, 70)
			nm.Size = UDim2.new(1, -12, 0, 16)
			nm.ZIndex = z + 4
			nm:SetAttribute("NoPolish", true)
			nm.Parent = opt

			local inc = Instance.new("TextLabel")
			inc.BackgroundTransparency = 1
			inc.Font = S.Font.Shout
			inc.TextSize = 13
			-- red = the incoming one out-earns this: a good one to drop
			inc.TextColor3 = (incomingValue > v) and Color3.fromHex("E0424F") or Color3.fromHex("3F8A17")
			inc.Text = shortCash(v) .. "/s"
			inc.AnchorPoint = Vector2.new(0.5, 0)
			inc.Position = UDim2.new(0.5, 0, 0, 90)
			inc.Size = UDim2.new(1, -12, 0, 16)
			inc.ZIndex = z + 4
			inc:SetAttribute("NoPolish", true)
			inc.Parent = opt

			if isLowest then
				local tag = Instance.new("TextLabel")
				tag.Font = S.Font.Shout
				tag.TextSize = 11
				tag.Text = "LOWEST"
				tag.TextColor3 = Color3.fromHex("3A2A00")
				tag.BackgroundColor3 = T.color.activeRing
				tag.BorderSizePixel = 0
				tag.AnchorPoint = Vector2.new(1, 0)
				tag.Position = UDim2.new(1, 6, 0, -6)
				tag.Size = UDim2.fromOffset(54, 18)
				tag.ZIndex = z + 5
				tag:SetAttribute("NoPolish", true)
				tag.Parent = opt
				UI.corner(tag, 6)
			end

			opt.MouseButton1Click:Connect(function()
				local r = remotes:FindFirstChild("SwapBrainrot")
				if r then r:FireServer(e.Uid, incoming.uids[1]) end
				closeModal()
			end)
		end

		local keepBtn = UI.button(dlg, "KEEP WHAT I HAVE", "tab", UDim2.fromOffset(220, 46), "buttonM")
		keepBtn.AnchorPoint = Vector2.new(0.5, 1)
		keepBtn.Position = UDim2.new(0.5, 0, 1, -14)
		keepBtn.ZIndex = z + 2
		keepBtn.MouseButton1Click:Connect(closeModal)
	end

	----------------------------------------------------------- BRAINROTS render (2026-08-12 rework)
	-- The tab is WIDE now (rack needs 8 columns): plot label row, the 2x8 rack
	-- tray, search + sort, then the two-section collection well.
	local BR_W = INDEX_W -- 762
	-- 2026-08-12 size pass (user: "needs to be bigger, hard to see"): rack slots
	-- 74 -> 86 (the tray now spans the full wide body), cards 80x98 -> 112x130 in
	-- SIX columns instead of eight, and search/sort moved up INTO the plot label
	-- row so the taller tray and taller cards cost no collection-scroll space.
	-- PS99 sizing pass: the icon rail freed 88px, all of it spent here --
	-- rack 86 -> 96, cards 112x130 -> 140x162 (art within them pushed to the
	-- edges, PS99's art-IS-the-cell read), grid gap tightened 10 -> 8.
	local RACK_SLOT = 96
	local RACK_GAP = 6
	local RACK_PAD = 10
	local TRAY_W = 8 * RACK_SLOT + 7 * RACK_GAP + RACK_PAD * 2
	local TRAY_H = 2 * RACK_SLOT + RACK_GAP + RACK_PAD * 2
	local LABEL_H = 34
	local CARD_W, CARD_H = 140, 162

	-- (no live call sites since the 2026-08-13 mock restyle replaced the tray
	-- with buildBaySlot; kept -- and normalized to the delta-8 state
	-- vocabulary below -- in case the rack tray earns its spot back)
	local function buildRackSlot(tray, spot: number, entry, zBase: number)
		local x = RACK_PAD + ((spot - 1) % 8) * (RACK_SLOT + RACK_GAP)
		local y = RACK_PAD + math.floor((spot - 1) / 8) * (RACK_SLOT + RACK_GAP)

		local slot = Instance.new("TextButton")
		slot.Name = "RackSlot" .. spot
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Position = UDim2.fromOffset(x, y)
		slot.Size = UDim2.fromOffset(RACK_SLOT, RACK_SLOT)
		slot.BorderSizePixel = 0
		slot.ZIndex = zBase
		slot.Parent = tray
		UI.corner(slot, 12)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Parent = slot

		local no = Instance.new("TextLabel")
		no.BackgroundTransparency = 1
		no.Font = S.Font.Shout
		no.TextSize = 11
		no.Text = tostring(spot)
		no.TextColor3 = Color3.fromHex("6B7689")
		no.Position = UDim2.fromOffset(5, 3)
		no.Size = UDim2.fromOffset(24, 12)
		no.TextXAlignment = Enum.TextXAlignment.Left
		no.ZIndex = zBase + 3
		no:SetAttribute("NoPolish", true)
		no.Parent = slot

		local unlocked = spot <= plotState.Unlocked
		local isNext = (spot == plotState.Unlocked + 1)
		if entry then
			-- delta 8 FILLED: white tile + item art (green ring = placed)
			slot.BackgroundColor3 = Color3.fromHex("FFFFFF")
			stroke.Color = Color3.fromHex("3DDC84")
			local art = Instance.new("Frame")
			art.BackgroundTransparency = 1
			art.Position = UDim2.fromOffset(8, 6)
			art.Size = UDim2.new(1, -16, 1, -26)
			art.ZIndex = zBase + 1
			art.Parent = slot
			local tier = infoByName[entry.Name] and infoByName[entry.Name].Rarity
			build3DOrSwatch(art, entry.Name, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), zBase + 2, rarityTint(T, tier))
			local inc = Instance.new("TextLabel")
			inc.BackgroundTransparency = 1
			inc.Font = S.Font.Shout
			inc.TextSize = 12
			inc.TextColor3 = Color3.fromHex("3E8E1F") -- readable green ink on the white tile
			inc.Text = shortCash(valueOf(entry.Name, entry.Mutation, entry.Size)) .. "/s"
			inc.AnchorPoint = Vector2.new(0.5, 1)
			inc.Position = UDim2.new(0.5, 0, 1, -3)
			inc.Size = UDim2.new(1, -6, 0, 14)
			inc.ZIndex = zBase + 3
			inc:SetAttribute("NoPolish", true)
			inc.Parent = slot

			local tipGroup = { Name = entry.Name, Mutation = entry.Mutation, Size = entry.Size,
				Fav = entry.Fav, count = 1, uids = { entry.Uid }, PadIndex = entry.PadIndex }
			-- TOUCH (2026-08-25): this equipped-rack slot offered its stats ONLY on
			-- MouseEnter, so on a phone -- which has no hover -- the value, mutation
			-- and size of an already-placed brainrot were unreachable; the single
			-- thing a tap could do was store it, sight unseen. Same contract the bag
			-- cards got in wireCardHit: tap = the action, long-press = inspect, and
			-- the release that ends an inspect is swallowed so looking at a brainrot
			-- never also un-places it. Written inline because wireCardHit's locals
			-- are declared further down this file and are not in scope here.
			local slotTouch = Platform.IsTouch
			local SLOT_LONG_PRESS = 0.35
			local slotToken = 0
			local slotSuppress = false
			slot.MouseEnter:Connect(function()
				if showCardTip and not slotTouch then showCardTip(tipGroup, slot) end
			end)
			slot.MouseLeave:Connect(function()
				if hideCardTip and not slotTouch then hideCardTip() end
			end)
			slot.MouseButton1Down:Connect(function()
				if not slotTouch then return end
				-- reset on the way IN: MouseButton1Up/Click only fire when the release
				-- lands ON the button, so a finger that slides off mid-press would
				-- leave slotSuppress latched and swallow the NEXT genuine tap
				slotSuppress = false
				slotToken += 1
				local myToken = slotToken
				if hideCardTip then hideCardTip() end
				task.delay(SLOT_LONG_PRESS, function()
					if myToken ~= slotToken or not slot.Parent then return end
					slotSuppress = true
					if showCardTip then showCardTip(tipGroup, slot) end
				end)
			end)
			slot.MouseButton1Up:Connect(function()
				if slotTouch then
					slotToken += 1 -- cancel any long-press that has not fired yet
				end
			end)
			slot.MouseButton1Click:Connect(function()
				if slotSuppress then
					-- this release ended an inspect long-press: leave the tip up and
					-- do NOT store the brainrot
					slotSuppress = false
					return
				end
				if hideCardTip then hideCardTip() end
				remotes.StoreBrainrot:FireServer(entry.Uid)
			end)
		elseif unlocked then
			-- delta 8 EMPTY: white tile + one large charcoal '+' (the shared
			-- empty-equip glyph; the "OPEN" word retired with it)
			slot.BackgroundColor3 = Color3.fromHex("FFFFFF")
			stroke.Color = Color3.fromHex("D3DCE7")
			local open = Instance.new("TextLabel")
			open.Name = "Plus"
			open.BackgroundTransparency = 1
			open.Font = S.Font.Shout
			open.TextSize = 53 -- ~55% of the 96px rack slot
			open.Text = "+"
			open.TextColor3 = Color3.fromHex("33414F")
			open.AnchorPoint = Vector2.new(0.5, 0.5)
			open.Position = UDim2.fromScale(0.5, 0.5)
			open.Size = UDim2.fromScale(1, 1)
			open.ZIndex = zBase + 1
			open:SetAttribute("NoPolish", true)
			open.Parent = slot
		else
			local price = plotState.Prices[spot]
			-- delta 8: the NEXT slot is PURCHASABLE -- a gold tile (gold =
			-- money); the rest are LOCKED -- charcoal-grey. White base so the
			-- gradient's colours land exactly (UIGradient multiplies).
			slot.BackgroundColor3 = Color3.new(1, 1, 1)
			UI.gradient(slot, if isNext
				then ColorSequence.new(S.Action.Gold[1], S.Action.Gold[2])
				else ColorSequence.new(Color3.fromHex("4A5666"), Color3.fromHex("39434F")))
			no.TextColor3 = isNext and Color3.fromHex("3A2A05") or Color3.new(1, 1, 1) -- rank ink follows the tile
			stroke.Color = isNext and T.color.activeRing or Color3.fromHex("222A38")
			stroke.Thickness = isNext and 3 or 2.5
			local lockHolder = Instance.new("Frame")
			lockHolder.BackgroundTransparency = 1
			lockHolder.AnchorPoint = Vector2.new(0.5, 0)
			lockHolder.Position = UDim2.new(0.5, 0, 0, 14)
			lockHolder.Size = UDim2.fromOffset(20, 20)
			lockHolder.ZIndex = zBase + 1
			lockHolder.Parent = slot
			buildPadlock(lockHolder, 18, isNext and Color3.fromHex("3A2A05") or Color3.new(1, 1, 1), zBase + 1) -- dark ink on gold, white on charcoal
			local pr = Instance.new("TextLabel")
			pr.BackgroundTransparency = 1
			pr.Font = S.Font.Shout
			pr.TextSize = 12
			pr.TextColor3 = isNext and Color3.fromHex("3A2A05") or Color3.new(1, 1, 1)
			pr.Text = price and shortCash(price) or "???"
			pr.AnchorPoint = Vector2.new(0.5, 1)
			pr.Position = UDim2.new(0.5, 0, 1, -5)
			pr.Size = UDim2.new(1, -6, 0, 14)
			pr.ZIndex = zBase + 1
			pr:SetAttribute("NoPolish", true)
			pr.Parent = slot
			if isNext and price then
				slot.MouseButton1Click:Connect(function()
					openUnlockModal(spot, price)
				end)
			end
		end
	end

	renderBrainrots = function()
		-- KEEP THE PLAYER'S PLACE: carry the inventory scroll over when `grid`
		-- is still alive (same-tab re-render); destroyed = fresh arrival, top.
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

		-- ================================================================
		-- 2026-08-13 MOCK RESTYLE (user reference image, "sizing and
		-- everything"): dark navy sections on the dark body; EQUIPPED bay =
		-- 8x2 grid of ~100x126 CARDS (art on top, name, tier chip pill below,
		-- gold star = mutated, gold padlock = favorited) over an INVENTORY
		-- section (title + owned count, wide SEARCH pill, RARITY/NEWEST/A-Z
		-- pills, scroll grid of the same cards). Green = EQUIPPED chip,
		-- active sort, "N / M" count. Bay = the 16 plot spots; click a bay
		-- card to store, a bag card to equip; full plot flashes the toast.
		local CARD_GAP = 8
		local WELL_PAD = 12
		local CARD_W = math.floor((BR_W - WELL_PAD * 2 - CARD_GAP * 7) / 8) -- ~100
		-- 132, up from 126, and the extra 6px all goes to artwork -- see buildCard:
		-- the tier chip that used to eat the bottom 25px is gone, so the art well
		-- grows from CARD_H-56 (70px) to CARD_H-30 (102px), a ~46% bigger pet in a
		-- card only 5% taller. Measured against the reference: its artwork fills
		-- ~85% of a tile where ours filled barely a third.
		local CARD_H = 132
		local GRIDW = CARD_W * 8 + CARD_GAP * 7
		local HEAD_H = 40
		-- THE EQUIPPED BAY GETS ITS OWN, SHORTER CARD. Measured before this change:
		-- the 16-slot bay held 264px of grid while the 166-item INVENTORY got a 113px
		-- scroll viewport -- SHORTER THAN ONE 130px TILE -- so no inventory row was
		-- ever fully visible at any scroll position and every card was sheared
		-- through its bottom. 16.5px of height per equipped item against 0.68px per
		-- inventory item is a 24:1 inversion, and it is the single biggest reason
		-- this panel is hard to navigate. The bay is a glance-and-go strip, so its
		-- cards go art-only at 84px (hover still names them), handing ~96px back.
		local EQ_H = 84
		-- COLLAPSE STATE. Folding the bay is deliberately NOT the "one grid" merge
		-- the readability audit asked for. That merge would have deleted the bay
		-- outright and marked equipped items with a corner dot -- but this bay is
		-- the PLOT: buildBaySlot gates each of the 16 cells on plotState.Unlocked,
		-- prices the locked ones from plotState.Prices[spot] and highlights the next
		-- one to buy. Deleting it would have taken a progression and purchase
		-- surface with it. Folding gives back the same height on demand and leaves
		-- the plot untouched when open. Collapsed keeps the header strip (EQUIPPED
		-- chip, slot count, TOTAL $/s, UNEQUIP ALL) and drops only the 2x8 pad grid.
		local bayCollapsed = ctx.state.backpack.bayCollapsed == true
		local BAY_H = if bayCollapsed
			then WELL_PAD + HEAD_H + WELL_PAD                               -- 64
			else WELL_PAD + HEAD_H + 8 + EQ_H * 2 + CARD_GAP + WELL_PAD     -- 248
		local SECTION_GAP = 10
		local INV_HEAD_H = 38
		local TweenService = game:GetService("TweenService")
		local HOVER_INFO = TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		-- LIGHT SURFACES (user, 2026-08-14: "ours is so dark and trash", holding up
		-- Pet Simulator's inventory as the standard). The reference puts its pet art
		-- on a near-WHITE field, and that single choice does most of the "easier to
		-- see" work -- our brainrots are dark, saturated models, and on a near-black
		-- card they had almost no separation from it. The wells and cards go light
		-- (2026-08-16: the shell is white now too), so the grid reads as a bright
		-- sheet inset in the frame (which is the reference's own arrangement) and
		-- every caption sitting OUTSIDE a well keeps its light-on-dark treatment.
		local C_WELL = Color3.fromHex("EEF2F8")
		local C_WELL_STROKE = Color3.fromHex("D3DCE7")
		local C_CARD = Color3.fromHex("FFFFFF")
		local C_CARD2 = Color3.fromHex("F2F5FA")
		local C_TILE = Color3.fromHex("E4EAF2")
		local C_SUB = Color3.fromHex("7C8CA0")   -- cool muted ink for light surfaces
		local C_GREEN1, C_GREEN2 = Color3.fromHex("7DE86A"), Color3.fromHex("28B93C")
		local C_GREENTEXT = Color3.fromHex("3E8E1F")   -- neon green died on cream
		local C_GOLD = Color3.fromHex("FFD84D")
		local C_PLACE = Color3.fromHex("9AA8B9")
		local C_INK = Color3.fromHex("0B1018")

		local placedByPad: { [number]: any } = {}
		local placedEntries = {}
		for _, e in ipairs(allBrainrots) do
			if e.PadIndex then
				placedByPad[e.PadIndex] = e
				placedEntries[#placedEntries + 1] = e
			end
		end
		table.sort(placedEntries, function(x, y) return (x.PadIndex or 0) < (y.PadIndex or 0) end)
		local plotIncome = 0
		for _, e in ipairs(placedEntries) do
			plotIncome += valueOf(e.Name, e.Mutation, e.Size)
		end
		local lockedCount = 16 - plotState.Unlocked

		-------------------------------------------------- toast
		local function ensureToast(): Frame
			local existing = wrapper:FindFirstChild("BagToast")
			if existing and existing:IsA("Frame") then
				return existing
			end
			local tf = Instance.new("Frame")
			tf.Name = "BagToast"
			tf.AnchorPoint = Vector2.new(0.5, 0)
			tf.AutomaticSize = Enum.AutomaticSize.X
			tf.Size = UDim2.fromOffset(0, 52)
			tf.BackgroundColor3 = C_GREEN1
			tf.BorderSizePixel = 0
			tf.Visible = false
			tf.ZIndex = shellZ + 45
			tf:SetAttribute("PolishOnDark", true)
			tf.Parent = wrapper
			UI.corner(tf, 14)
			UI.gradient(tf, ColorSequence.new(C_GREEN1, C_GREEN2))
			do
				local st = Instance.new("UIStroke")
				st.Thickness = 3
				st.Color = C_INK
				st.Parent = tf
			end
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 18)
			pad.PaddingRight = UDim.new(0, 18)
			pad.Parent = tf
			local lay = Instance.new("UIListLayout")
			lay.FillDirection = Enum.FillDirection.Horizontal
			lay.VerticalAlignment = Enum.VerticalAlignment.Center
			lay.Padding = UDim.new(0, 8)
			lay.SortOrder = Enum.SortOrder.LayoutOrder
			lay.Parent = tf
			local ic = Instance.new("ImageLabel")
			ic.Name = "Icon"
			ic.BackgroundTransparency = 1
			ic.Image = T.icons.bag
			ic.Size = UDim2.fromOffset(26, 26)
			ic.LayoutOrder = 1
			ic.ZIndex = tf.ZIndex + 1
			ic.Parent = tf
			local l = Instance.new("TextLabel")
			l.Name = "Text"
			l.BackgroundTransparency = 1
			l.Font = S.Font.Shout
			l.TextSize = 18
			l.TextColor3 = Color3.new(1, 1, 1)
			l.AutomaticSize = Enum.AutomaticSize.X
			l.Size = UDim2.new(0, 0, 1, 0)
			l.LayoutOrder = 2
			l.ZIndex = tf.ZIndex + 1
			l:SetAttribute("NoPolish", true)
			l.Parent = tf
			do
				local st = Instance.new("UIStroke")
				st.Thickness = 2
				st.Color = C_INK
				st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
				st.Parent = l
			end
			return tf
		end

		local function flash(text: string, tone: string)
			local tf = ensureToast()
			local g = tf:FindFirstChildOfClass("UIGradient")
			if g then
				if tone == "error" then
					g.Color = ColorSequence.new(Color3.fromHex("FF6B6B"), Color3.fromHex("D83E3E"))
				elseif tone == "warn" then
					g.Color = ColorSequence.new(Color3.fromHex("FFE066"), Color3.fromHex("E8930F"))
				else
					g.Color = ColorSequence.new(C_GREEN1, C_GREEN2)
				end
			end
			local l = tf:FindFirstChild("Text")
			if l and l:IsA("TextLabel") then
				l.Text = text
			end
			local gen = (tonumber(tf:GetAttribute("Gen")) or 0) + 1
			tf:SetAttribute("Gen", gen)
			tf.Visible = true
			tf.Position = UDim2.new(0.5, 0, 0, -60)
			TweenService:Create(tf, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 0, 16) }):Play()
			task.delay(2.4, function()
				if tf.Parent and tf:GetAttribute("Gen") == gen then
					tf.Visible = false
				end
			end)
		end

		-------------------------------------------------- card pieces
		local function lum(c: Color3): number
			return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
		end

		-- 8-point sparkle badge (mutated marker). VIOLET, not gold (2026-08-17):
		-- gold means real money in the PS99 grammar, and a gold star on most of a
		-- rarity-sorted page read as 30 coin icons; violet is the game's
		-- "special" family (emeralds, epics).
		local function buildStarBadge(card: Frame, xOff: number)
			local h = Instance.new("Frame")
			h.Name = "StarBadge"
			h.AnchorPoint = Vector2.new(1, 0)
			h.Position = UDim2.new(1, xOff, 0, 4)
			h.Size = UDim2.fromOffset(22, 22)
			h.BackgroundTransparency = 1
			h.ZIndex = 20
			h.Parent = card
			for _, r in ipairs({ 0, 45 }) do
				local part = Instance.new("Frame")
				part.AnchorPoint = Vector2.new(0.5, 0.5)
				part.Position = UDim2.fromScale(0.5, 0.5)
				part.Size = UDim2.fromOffset(13, 13)
				part.Rotation = r
				part.BackgroundColor3 = Color3.fromHex("C14CFF")
				part.BorderSizePixel = 0
				part.ZIndex = 20
				part.Parent = h
				UI.corner(part, 3)
				local ps = Instance.new("UIStroke")
				ps.Thickness = 1.5
				ps.Color = Color3.fromHex("5E0FB8")
				ps.Parent = part
			end
		end

		-- pink padlock badge = the raid LOCK (2026-08-22 unified favorite). A real
		-- button above the card hit; solid PINK when locked (matching the plot's pink
		-- glow), revealed dim on card hover otherwise so favoriting stays reachable.
		-- Click toggles the lock (ToggleLock, capacity-gated) -- same as right-click.
		local function buildFavBadge(card: Frame, fav: boolean, uids: any, xOff: number): TextButton
			local b = Instance.new("TextButton")
			b.Name = "FavBadge"
			b.Text = ""
			b.AutoButtonColor = false
			b.AnchorPoint = Vector2.new(1, 0)
			b.Position = UDim2.new(1, xOff, 0, 4)
			b.Size = UDim2.fromOffset(22, 22)
			b.BackgroundColor3 = fav and Color3.fromHex("FF78C8") or Color3.fromHex("10141C")
			b.BackgroundTransparency = fav and 0 or 0.35
			b.BorderSizePixel = 0
			b.Visible = fav
			b:SetAttribute("Fav", fav)
			b.ZIndex = 22
			b.Parent = card
			-- DELIBERATELY SHORT OF 44 (2026-08-25). This badge rendered 16x16 on a
			-- phone, the worst target in the game -- but the full 44px floor is the
			-- WRONG fix here and is not applied. Reaching 44 on screen means ~60 design
			-- px, most of the card's own width, and on touch every badge is permanently
			-- visible (wireCardHit reveals them, there being no hover to reveal them
			-- with) -- so a grid of 129 of them would blanket the cards and eat the taps
			-- meant to PLACE a brainrot, trading a bad target for a broken one. 30px
			-- roughly doubles it and leaves the card the tappable thing on the tile.
			-- Reaching the real minimum needs the lock moved off the tile entirely
			-- (into the long-press tooltip); logged, not done here.
			--
			-- MUST come after `b.Parent` above: touchMin measures what rendered, so on
			-- an unparented instance it has nothing to measure and returns silently.
			UI.touchMin(b, 30)
			UI.corner(b, 7)
			do
				local bs = Instance.new("UIStroke")
				bs.Thickness = 2
				bs.Color = fav and Color3.fromHex("C74C93") or Color3.fromHex("2C3444")
				bs.Parent = b
				local ink = fav and Color3.fromHex("5A1E3F") or C_PLACE
				local lockBody = Instance.new("Frame")
				lockBody.AnchorPoint = Vector2.new(0.5, 1)
				lockBody.Position = UDim2.new(0.5, 0, 1, -4)
				lockBody.Size = UDim2.fromOffset(10, 7)
				lockBody.BackgroundColor3 = ink
				lockBody.BorderSizePixel = 0
				lockBody.ZIndex = 23
				lockBody.Parent = b
				UI.corner(lockBody, 2)
				local shackle = Instance.new("Frame")
				shackle.AnchorPoint = Vector2.new(0.5, 1)
				shackle.Position = UDim2.new(0.5, 0, 1, -10)
				shackle.Size = UDim2.fromOffset(7, 5)
				shackle.BackgroundTransparency = 1
				shackle.ZIndex = 23
				shackle.Parent = b
				UI.corner(shackle, 999)
				local ss = Instance.new("UIStroke")
				ss.Thickness = 2
				ss.Color = ink
				ss.Parent = shackle
			end
			b.MouseButton1Click:Connect(function()
				-- 2026-08-22: the bag favorite IS the raid lock now -- toggle it through
				-- ToggleLock (capacity-gated, plot-synced), not the retired ToggleFavorite.
				local r = remotes:FindFirstChild("ToggleLock")
				if r then r:FireServer(uids) end
			end)
			return b
		end

		-- The mock card: dark navy, 3px tier-coloured border, art on top,
		-- name, tier chip pill. Count stacks get a small x-chip top-left.
		-- `cardH` lets the equipped bay ask for its shorter, art-only card; the
		-- inventory grid omits it and gets the full-height card with its name.
		local function buildCard(cell: Frame, name: string, mutation: string?, size: string?, count: number, cardH: number?, splashKey: string?): Frame
			local H = cardH or CARD_H
			local compact = H < CARD_H
			local tierName = infoByName[name] and infoByName[name].Rarity
			local ramp = S.Rarity[RARITY_RAMP_KEY2[tierName] or "COM"] or S.Rarity.COM
			local card = Instance.new("Frame")
			card.Name = "Card"
			card.Size = UDim2.fromScale(1, 1)
			card.BackgroundColor3 = C_CARD
			card.BorderSizePixel = 0
			card.ZIndex = 15
			card.Parent = cell
			UI.corner(card, 14)
			-- PS99 delta 4 (2026-08-16): an inventory-grid card (splashKey ~= nil)
			-- loses the cell box -- plate invisible, art floats on a pastel splash
			-- inserted FIRST so every existing child renders above it. The
			-- equipped bay passes no splashKey and keeps its boxed look (state).
			if splashKey then
				card.BackgroundTransparency = 1
				-- 21 of the 215 brainrots are pale enough to vanish into a pastel
				-- splash (Orso Frigorifero 0.965, Inverno Eterno 0.953, Ombra
				-- Bianca 0.953, Balena Polare 0.940 -- the tundra set). Resolving
				-- the master here is free: BrainrotThumb caches it, and the art
				-- call a few lines below would have built it anyway.
				addSplash(card, splashTint(tierName, splashKey, ramp[2]), nil,
					BrainrotThumb.isPale(BrainrotThumb.master(name)))
			end
			do
				local g = Instance.new("UIGradient")
				g.Rotation = 90
				g.Color = ColorSequence.new(C_CARD, C_CARD2)
				g.Parent = card
				local st = Instance.new("UIStroke")
				-- 2px, not 3: on the old near-black card the ring was the only thing
				-- holding the tile together, so it had to shout. Against a light card
				-- a saturated 2px ramp reads stronger and stops a rarity-sorted row
				-- from looking like a fence of identical neon bars.
				st.Thickness = 2
				st.Color = ramp[2]
				st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				st.LineJoinMode = Enum.LineJoinMode.Round
				st.Parent = card
				if splashKey then
					-- delta 4: border hidden, object kept. No hover/selection code
					-- re-enables this stroke on the inventory grid (clicking IS the
					-- action; there is no selected state on this tab) -- rarity now
					-- lives in the hover tooltip, and Secret-family tiers keep it
					-- via their splash tint.
					st.Transparency = 1
					st.Enabled = false
				end
			end

			local art = Instance.new("Frame")
			art.Name = "Art"
			art.Position = UDim2.fromOffset(4, 4)
			-- FULL-BLEED ART (2026-08-15). The name row used to reserve the bottom 22px
			-- of every inventory card for text that truncated 90% of the time -- and
			-- truncated from the RIGHT, while our names are mutation-first, so it
			-- dropped the distinguishing half and left rows of "Diamond...". The art
			-- now takes the whole card in both modes: 102 -> 124px on an inventory
			-- card. The full name lives on hover, where it has room to wrap.
			art.Size = UDim2.new(1, -8, 0, H - 8)
			art.BackgroundTransparency = 1
			art.ZIndex = 16
			art.Parent = card
			build3DOrSwatch(art, name, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 17, rarityTint(T, tierName))

			-- ...AND THE NUMBER YOU ACTUALLY DECIDE WITH GOES ON TOP OF IT. Sorting,
			-- equipping and selling are all $/s decisions; the name only tells you
			-- which meme it is. White glyphs under a heavy dark stroke (the
			-- reference's trick) stay legible over ANY artwork -- a pale brainrot, a
			-- near-black one, or the bare card while a model is still streaming in.
			-- Bottom-centre, clear of the count chip (top-left) and fav lock (top-right).
			local rate = Instance.new("TextLabel")
			rate.Name = "Rate"
			rate.BackgroundTransparency = 1
			rate.Font = S.Font.Shout
			rate.TextSize = compact and 13 or 15
			rate.TextColor3 = Color3.new(1, 1, 1)
			rate.Text = shortCash(valueOf(name, mutation, size)) .. "/s"
			rate.AnchorPoint = Vector2.new(0.5, 1)
			rate.Position = UDim2.new(0.5, 0, 1, -3)
			rate.Size = UDim2.new(1, -8, 0, compact and 15 or 17)
			rate.ZIndex = 19
			rate:SetAttribute("NoPolish", true)
			rate.Parent = card
			do
				local rs = Instance.new("UIStroke")
				rs.Thickness = 2.5
				rs.Color = Color3.fromHex("10141C")
				rs.Parent = rate
			end

			-- NO TIER CHIP. It restated, in 10px text, exactly what the card's own 3px
			-- tier-coloured border already says -- and it cost 25px of the card, which
			-- is the single biggest reason our artwork was a third the size of the
			-- reference's. The border reads far better now that the card behind it is
			-- light, and the hover tooltip still spells the tier out in words.

			if count > 1 then
				local cc = Instance.new("TextLabel")
				cc.Name = "CountChip"
				cc.BackgroundColor3 = Color3.fromHex("10141C")
				cc.BackgroundTransparency = 0.2
				cc.Font = S.Font.Read
				cc.TextSize = 11
				cc.TextColor3 = Color3.new(1, 1, 1)
				cc.Text = "x" .. count
				cc.Position = UDim2.fromOffset(4, 4)
				cc.AutomaticSize = Enum.AutomaticSize.X
				cc.Size = UDim2.fromOffset(0, 18)
				cc.BorderSizePixel = 0
				cc.ZIndex = 20
				cc:SetAttribute("NoPolish", true)
				cc.Parent = card
				UI.corner(cc, 6)
				local ccp = Instance.new("UIPadding")
				ccp.PaddingLeft = UDim.new(0, 6)
				ccp.PaddingRight = UDim.new(0, 6)
				ccp.Parent = cc
			end

			return card
		end

		-- hover lift + tooltip + click + hover-revealed fav toggle
		-- TOUCH RELEASE-ANYWHERE GUARD (2026-08-19). MouseButton1Up/Click fire
		-- only when the release lands OVER the button, so on a phone a finger that
		-- slides off a card before lifting -- the ordinary scroll gesture on this
		-- grid -- leaves that card sunk at Position(0,1) forever. ONE shared
		-- UserInputService connection watches every release instead of paying for
		-- a connection per card (this grid can hold hundreds).
		local pressedCard: Frame? = nil
		local function setPressedCard(c: Frame?)
			pressedCard = c
		end
		do
			local UIS = game:GetService("UserInputService")
			UIS.InputEnded:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.Touch
					and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				local c = pressedCard
				pressedCard = nil
				if c and c.Parent then
					TweenService:Create(c, HOVER_INFO, { Position = UDim2.fromOffset(0, 0) }):Play()
				end
			end)
		end

		local function wireCardHit(cell: Frame, card: Frame, tipGroup: any, favBadge: TextButton?, onClick: () -> ())
			local hit = Instance.new("TextButton")
			hit.Name = "Hit"
			hit.Text = ""
			hit.Size = UDim2.fromScale(1, 1)
			hit.BackgroundTransparency = 1
			hit.ZIndex = 21
			hit.Parent = cell
			-- press feedback (2026-08-17): the cards answered hover but not the
			-- click itself -- a 1px sink on Down, released to whichever state the
			-- cursor is in, same contract the rail buttons keep
			local hovered = false
			-- TOUCH (2026-08-19): a phone has no hover, so everything this card
			-- revealed on MouseEnter was unreachable -- the info tooltip AND the
			-- favourite button. Touch gets: long-press to inspect (below), and a
			-- permanently visible fav badge (there is no hover to reveal it).
			local isTouch = Platform.IsTouch
			local LONG_PRESS = 0.35
			local pressToken = 0
			local suppressClick = false
			if isTouch and favBadge and not favBadge:GetAttribute("Fav") then
				favBadge.Visible = true
			end
			hit.MouseEnter:Connect(function()
				hovered = true
				cell.ZIndex = 30
				TweenService:Create(card, HOVER_INFO, { Position = UDim2.fromOffset(0, -3) }):Play()
				if favBadge and not favBadge:GetAttribute("Fav") then
					favBadge.Visible = true
				end
				if tipGroup and showCardTip and not isTouch then
					showCardTip(tipGroup, card)
				end
			end)
			hit.MouseLeave:Connect(function()
				hovered = false
				cell.ZIndex = 15
				TweenService:Create(card, HOVER_INFO, { Position = UDim2.fromOffset(0, 0) }):Play()
				if favBadge and not favBadge:GetAttribute("Fav") and not isTouch then
					favBadge.Visible = false
				end
				if hideCardTip and not isTouch then
					hideCardTip()
				end
			end)
			hit.MouseButton1Down:Connect(function()
				TweenService:Create(card, HOVER_INFO, { Position = UDim2.fromOffset(0, 1) }):Play()
				if not isTouch then return end
				-- long-press = inspect. Held past LONG_PRESS the tip opens and the
				-- release is swallowed, so inspecting never also places the item.
				--
				-- EVERY press starts from a clean slate. MouseButton1Up/Click only
				-- fire when the release happens OVER the button, so a finger that
				-- slides off mid-press -- i.e. the ordinary scroll gesture on this
				-- grid -- never clears state set here. Left latched, `suppressClick`
				-- would swallow the NEXT genuine tap. Reset on the way in, and let
				-- the release-anywhere guard below un-sink the card.
				suppressClick = false
				pressToken += 1
				local myToken = pressToken
				if hideCardTip then hideCardTip() end
				setPressedCard(card)
				task.delay(LONG_PRESS, function()
					if myToken ~= pressToken or not card.Parent then return end
					suppressClick = true
					-- the press has been consumed by the inspect: settle the card back
					-- to rest so it does not sit sunk while the tip is up
					TweenService:Create(card, HOVER_INFO, { Position = UDim2.fromOffset(0, 0) }):Play()
					if tipGroup and showCardTip then showCardTip(tipGroup, card) end
				end)
			end)
			hit.MouseButton1Up:Connect(function()
				TweenService:Create(card, HOVER_INFO, { Position = UDim2.fromOffset(0, hovered and -3 or 0) }):Play()
				if isTouch then
					pressToken += 1 -- cancel any pending long-press
					setPressedCard(nil)
				end
			end)
			hit.MouseButton1Click:Connect(function()
				if suppressClick then
					-- this release ended an inspect long-press: leave the tip up and
					-- do NOT run the card's action
					suppressClick = false
					return
				end
				if hideCardTip then
					hideCardTip()
				end
				onClick()
			end)
			-- RIGHT-CLICK = toggle the RAID LOCK (2026-08-20). Fires ToggleLock with the
			-- whole stack's uids; the server caps it against the Padlock upgrade, pink-
			-- glows the placed copies and re-pushes so the bag repaints.
			hit.MouseButton2Click:Connect(function()
				if hideCardTip then hideCardTip() end
				local r = remotes:FindFirstChild("ToggleLock")
				if r and tipGroup and tipGroup.uids then
					r:FireServer(tipGroup.uids)
				end
			end)
		end

		local function buildWell(y: number, h: number): Frame
			local w = Instance.new("Frame")
			w.BackgroundColor3 = C_WELL
			w.BorderSizePixel = 0
			w.Position = UDim2.fromOffset(0, y)
			w.Size = UDim2.fromOffset(BR_W, h)
			w.ZIndex = 13
			w.Parent = contentHost
			UI.corner(w, 16)
			local st = Instance.new("UIStroke")
			st.Thickness = 2
			st.Color = C_WELL_STROKE
			st.Parent = w
			return w
		end

		local function darkPill(parent: Instance, h: number): Frame
			local f = Instance.new("Frame")
			f.BackgroundColor3 = C_TILE
			f.BorderSizePixel = 0
			f.AutomaticSize = Enum.AutomaticSize.X
			f.Size = UDim2.fromOffset(0, h)
			f.ZIndex = 15
			f.Parent = parent
			UI.corner(f, 999)
			local st = Instance.new("UIStroke")
			st.Thickness = 2
			st.Color = C_WELL_STROKE
			st.Parent = f
			return f
		end

		local function flatButton(parent: Instance, text: string, w: number, h: number, active: boolean, danger: boolean?): TextButton
			local b = Instance.new("TextButton")
			b.Name = text
			b.Text = ""
			b.AutoButtonColor = true
			b.BackgroundColor3 = if danger then Color3.fromHex("FF6B6B") elseif active then C_GREEN1 else C_TILE
			b.BorderSizePixel = 0
			b.Size = UDim2.fromOffset(w, h)
			b.ZIndex = 15
			b.Parent = parent
			UI.corner(b, 12)
			do
				local g = Instance.new("UIGradient")
				g.Rotation = 90
				if danger then
					g.Color = ColorSequence.new(Color3.fromHex("FF6B6B"), Color3.fromHex("D83E3E"))
				elseif active then
					g.Color = ColorSequence.new(C_GREEN1, C_GREEN2)
				else
					g.Color = ColorSequence.new(C_TILE, Color3.fromHex("10151F"))
				end
				g.Parent = b
				local st = Instance.new("UIStroke")
				st.Thickness = 2
				st.Color = if danger then Color3.fromHex("6E1414") elseif active then Color3.fromHex("1E5C12") else C_WELL_STROKE
				st.Parent = b
			end
			local l = Instance.new("TextLabel")
			l.Name = "Label"
			l.BackgroundTransparency = 1
			l.Font = S.Font.Shout
			l.TextSize = 15
			-- an inactive button sits on C_TILE, which is light now, so its resting
			-- label has to be ink; active/danger keep white on their green/red fill
			l.TextColor3 = if (active or danger) then Color3.new(1, 1, 1) else Color3.fromHex("33414F")
			l.Text = text
			l.Size = UDim2.fromScale(1, 1)
			l.ZIndex = 16
			l:SetAttribute("NoPolish", true)
			l.Parent = b
			if active or danger then
				local ls = Instance.new("UIStroke")
				ls.Thickness = 2
				ls.Color = C_INK
				ls.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
				ls.Parent = l
			end
			-- TOUCH FLOOR: KNOWN SHORT, DELIBERATELY NOT PATCHED HERE (2026-08-25).
			-- Measured on a phone-classed client these pills render 71x27 (the three
			-- sort tabs), 97x27 (UNEQUIP ALL) and 83x24 (the plot fold) -- all under
			-- Roblox's 44px minimum on the short axis.
			--
			-- UI.touchMin was applied here and then REVERTED: it does not fail safely
			-- in this panel. 44 screen px is ~59 DESIGN px at the scale the bag runs
			-- at, and both bands these pills live in are shorter than that (bay header
			-- 40, inventory header 38). Measured with the floor on: the plot fold broke
			-- its band by 7.4px and ended up 1.5px INTO the equipped grid, and UNEQUIP
			-- ALL broke it by 16.4px and overlapped the first row of cards outright.
			-- Growing the bands instead pushes the whole inventory down by about a card
			-- row -- and the smaller the screen, the LARGER that push gets, because the
			-- design size required is 44/panelScale.
			--
			-- Which makes this a panel-density decision, not a per-control one: the bag
			-- is authored at a size that gets scaled to roughly half on a handset, and
			-- no amount of inflating individual pills fixes that without wrecking the
			-- composition. Left short and on the record rather than silently broken.
			return b
		end

		-- One bay slot: card / empty / locked
		local function buildBaySlot(holder: Frame, spot: number, entry: any)
			local cell = Instance.new("Frame")
			cell.Name = "BaySlot" .. spot
			cell.BackgroundTransparency = 1
			cell.LayoutOrder = spot
			cell.ZIndex = 15
			cell.Parent = holder

			local unlocked = spot <= plotState.Unlocked
			if entry then
				local card = buildCard(cell, entry.Name, entry.Mutation, entry.Size, 1, EQ_H)
				local xOff = -4
				local favB = buildFavBadge(card, entry.Fav == true, { entry.Uid }, xOff)
				xOff -= 26
				if entry.Mutation then
					buildStarBadge(card, xOff)
				end
				local tipGroup = { Name = entry.Name, Mutation = entry.Mutation, Size = entry.Size,
					Fav = entry.Fav, count = 1, uids = { entry.Uid }, PadIndex = entry.PadIndex }
				wireCardHit(cell, card, tipGroup, favB, function()
					remotes.StoreBrainrot:FireServer(entry.Uid)
				end)
			elseif unlocked then
				-- delta 8 (2026-08-16): EMPTY equip slot = white tile + one
				-- large charcoal '+' -- the shared empty-equip glyph (the
				-- dashed inset and faint plus placeholder retired with it)
				local card = Instance.new("Frame")
				card.Name = "Empty"
				card.Size = UDim2.fromScale(1, 1)
				card.BackgroundColor3 = C_CARD
				card.BorderSizePixel = 0
				card.ZIndex = 15
				card.Parent = cell
				UI.corner(card, 14)
				do
					local st = Instance.new("UIStroke")
					st.Thickness = 2
					st.Color = C_WELL_STROKE
					st.Parent = card
				end
				local plus = Instance.new("TextLabel")
				plus.Name = "Plus"
				plus.BackgroundTransparency = 1
				plus.Font = S.Font.Shout
				plus.TextSize = 46 -- ~55% of the 84px bay card
				plus.TextColor3 = Color3.fromHex("33414F")
				plus.Text = "+"
				plus.Size = UDim2.fromScale(1, 1)
				plus.ZIndex = 17
				plus:SetAttribute("NoPolish", true)
				plus.Parent = card
			else
				local price = plotState.Prices[spot]
				local isNext = (spot == plotState.Unlocked + 1)
				local card = Instance.new("Frame")
				card.Name = "Locked"
				card.Size = UDim2.fromScale(1, 1)
				-- delta 8 state fills: the NEXT slot is PURCHASABLE -- a gold
				-- tile (gold = money); the rest are LOCKED -- charcoal-grey.
				-- White base so the gradient's colours land exactly.
				card.BackgroundColor3 = Color3.new(1, 1, 1)
				card.BorderSizePixel = 0
				card.ZIndex = 15
				card.Parent = cell
				UI.corner(card, 14)
				UI.gradient(card, if isNext
					then ColorSequence.new(S.Action.Gold[1], S.Action.Gold[2])
					else ColorSequence.new(Color3.fromHex("4A5666"), Color3.fromHex("39434F")))
				do
					local st = Instance.new("UIStroke")
					st.Thickness = 2
					st.Color = isNext and Color3.fromHex("8A6510") or C_WELL_STROKE
					st.Parent = card
				end
				local lockHolder = Instance.new("Frame")
				lockHolder.Name = "Lock"
				lockHolder.BackgroundTransparency = 1
				lockHolder.AnchorPoint = Vector2.new(0.5, 0)
				lockHolder.Position = UDim2.new(0.5, 0, 0, 18)
				lockHolder.Size = UDim2.fromOffset(27, 27)
				lockHolder.ZIndex = 17
				lockHolder.Parent = card
				buildPadlock(lockHolder, 20, isNext and Color3.fromHex("3A2A05") or Color3.new(1, 1, 1), 17) -- dark ink on gold, white on charcoal

				local pill = Instance.new("Frame")
				pill.Name = "PricePill"
				pill.AnchorPoint = Vector2.new(0.5, 0)
				pill.AutomaticSize = Enum.AutomaticSize.X
				pill.Size = UDim2.fromOffset(0, 24)
				pill.Position = UDim2.new(0.5, 0, 0, -11)
				-- delta 8: gold pill only on the PURCHASABLE (next) slot;
				-- plain LOCKED slots price themselves in white on charcoal
				pill.BackgroundColor3 = Color3.new(1, 1, 1)
				pill.BorderSizePixel = 0
				pill.ZIndex = 24
				pill.Parent = cell
				UI.corner(pill, 999)
				UI.gradient(pill, if isNext
					then ColorSequence.new(Color3.fromHex("FFE066"), Color3.fromHex("E8930F"))
					else ColorSequence.new(Color3.fromHex("4A5666"), Color3.fromHex("39434F")))
				do
					local st = Instance.new("UIStroke")
					st.Thickness = 2
					st.Color = C_INK
					st.Parent = pill
					local ppad = Instance.new("UIPadding")
					ppad.PaddingLeft = UDim.new(0, 6)
					ppad.PaddingRight = UDim.new(0, 9)
					ppad.Parent = pill
					local plist = Instance.new("UIListLayout")
					plist.FillDirection = Enum.FillDirection.Horizontal
					plist.VerticalAlignment = Enum.VerticalAlignment.Center
					plist.Padding = UDim.new(0, 4)
					plist.SortOrder = Enum.SortOrder.LayoutOrder
					plist.Parent = pill
					local pcoin = Instance.new("ImageLabel")
					pcoin.Name = "Coin"
					pcoin.BackgroundTransparency = 1
					pcoin.Image = T.icons.coin
					pcoin.Size = UDim2.fromOffset(16, 16)
					pcoin.LayoutOrder = 1
					pcoin.ZIndex = 25
					pcoin.Parent = pill
					local pl = Instance.new("TextLabel")
					pl.Name = "Price"
					pl.BackgroundTransparency = 1
					pl.Font = S.Font.Read
					pl.TextSize = 13
					pl.TextColor3 = if isNext then Color3.fromHex("3A2A05") else Color3.new(1, 1, 1)
					pl.Text = if price then shortCash(price) else "???"
					pl.AutomaticSize = Enum.AutomaticSize.X
					pl.Size = UDim2.fromOffset(0, 24)
					pl.LayoutOrder = 2
					pl.ZIndex = 25
					pl:SetAttribute("NoPolish", true)
					pl.Parent = pill
				end

				local afford = price ~= nil and plotState.Cash >= price
				local enabled = isNext and afford
				local btn = Instance.new("TextButton")
				btn.Name = "UnlockButton"
				btn.Text = ""
				btn.AutoButtonColor = enabled
				btn.Active = enabled
				btn.BackgroundColor3 = if enabled then C_GOLD else Color3.fromHex("232B3A")
				btn.BorderSizePixel = 0
				btn.AnchorPoint = Vector2.new(0.5, 1)
				btn.Position = UDim2.new(0.5, 0, 1, -6)
				btn.Size = UDim2.new(1, -12, 0, 36)
				btn.ZIndex = 18
				btn.Parent = card
				UI.corner(btn, 10)
				do
					local g = Instance.new("UIGradient")
					g.Rotation = 90
					g.Color = if enabled
						then ColorSequence.new(Color3.fromHex("FFE066"), Color3.fromHex("E8930F"))
						else ColorSequence.new(Color3.fromHex("232B3A"), Color3.fromHex("1A2130"))
					g.Parent = btn
					local st = Instance.new("UIStroke")
					st.Thickness = 2
					st.Color = if enabled then Color3.fromHex("8A6510") else C_WELL_STROKE
					st.Parent = btn
					local l = Instance.new("TextLabel")
					l.Name = "Label"
					l.BackgroundTransparency = 1
					l.Font = S.Font.Shout
					l.TextSize = 14
					l.TextColor3 = if enabled then Color3.fromHex("3A2A05") else C_PLACE
					l.Text = "UNLOCK"
					l.Size = UDim2.fromScale(1, 1)
					l.ZIndex = 19
					l:SetAttribute("NoPolish", true)
					l.Parent = btn
				end
				if enabled and price then
					btn.MouseButton1Click:Connect(function()
						if plotState.Cash < price then
							flash("NOT ENOUGH COINS", "error")
							return
						end
						local r = remotes:FindFirstChild("BuyPlotSpot")
						if r then
							r:FireServer()
							flash("SLOT UNLOCKED", "success")
						end
					end)
				end
			end
		end

		-------------------------------------------------- EQUIPPED BAY
		local bay = buildWell(0, BAY_H)
		bay.Name = "EquippedBay"

		local bayHead = Instance.new("Frame")
		bayHead.Name = "BayHeader"
		bayHead.Position = UDim2.fromOffset(WELL_PAD, WELL_PAD)
		bayHead.Size = UDim2.new(1, -WELL_PAD * 2, 0, HEAD_H)
		bayHead.BackgroundTransparency = 1
		bayHead.ZIndex = 15
		bayHead.Parent = bay

		local headLeft = Instance.new("Frame")
		headLeft.Name = "Left"
		headLeft.BackgroundTransparency = 1
		headLeft.AutomaticSize = Enum.AutomaticSize.X
		headLeft.Size = UDim2.new(0, 0, 1, 0)
		headLeft.ZIndex = 15
		headLeft.Parent = bayHead
		do
			local ll = Instance.new("UIListLayout")
			ll.FillDirection = Enum.FillDirection.Horizontal
			ll.VerticalAlignment = Enum.VerticalAlignment.Center
			ll.Padding = UDim.new(0, 12)
			ll.SortOrder = Enum.SortOrder.LayoutOrder
			ll.Parent = headLeft
		end

		local chip = Instance.new("Frame")
		chip.Name = "EquippedChip"
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.fromOffset(0, 32)
		chip.LayoutOrder = 1
		chip.BackgroundColor3 = C_GREEN1
		chip.BorderSizePixel = 0
		chip.ZIndex = 16
		chip.Parent = headLeft
		UI.corner(chip, 10)
		do
			local g = Instance.new("UIGradient")
			g.Rotation = 90
			g.Color = ColorSequence.new(C_GREEN1, C_GREEN2)
			g.Parent = chip
			local st = Instance.new("UIStroke")
			st.Thickness = 2
			st.Color = Color3.fromHex("1E5C12")
			st.Parent = chip
			local cp = Instance.new("UIPadding")
			cp.PaddingLeft = UDim.new(0, 14)
			cp.PaddingRight = UDim.new(0, 14)
			cp.Parent = chip
			local cl = Instance.new("TextLabel")
			cl.Name = "Label"
			cl.BackgroundTransparency = 1
			cl.Font = S.Font.Shout
			cl.TextSize = 15
			cl.TextColor3 = Color3.new(1, 1, 1)
			cl.Text = "EQUIPPED"
			cl.AutomaticSize = Enum.AutomaticSize.X
			cl.Size = UDim2.new(0, 0, 1, 0)
			cl.ZIndex = 17
			cl:SetAttribute("NoPolish", true)
			cl.Parent = chip
			local cs = Instance.new("UIStroke")
			cs.Thickness = 2
			cs.Color = C_INK
			cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			cs.Parent = cl
		end

		local filledWrap = Instance.new("Frame")
		filledWrap.Name = "Filled"
		filledWrap.BackgroundTransparency = 1
		filledWrap.AutomaticSize = Enum.AutomaticSize.X
		filledWrap.Size = UDim2.new(0, 0, 1, 0)
		filledWrap.LayoutOrder = 2
		filledWrap.ZIndex = 15
		filledWrap.Parent = headLeft
		do
			local fl = Instance.new("UIListLayout")
			fl.FillDirection = Enum.FillDirection.Horizontal
			fl.VerticalAlignment = Enum.VerticalAlignment.Center
			fl.Padding = UDim.new(0, 8)
			fl.SortOrder = Enum.SortOrder.LayoutOrder
			fl.Parent = filledWrap
			local cnt = Instance.new("TextLabel")
			cnt.Name = "Count"
			cnt.BackgroundTransparency = 1
			cnt.Font = S.Font.Read
			cnt.TextSize = 20
			cnt.TextColor3 = C_GREENTEXT
			cnt.Text = #placedEntries .. " / " .. plotState.Unlocked
			cnt.AutomaticSize = Enum.AutomaticSize.X
			cnt.Size = UDim2.new(0, 0, 1, 0)
			cnt.LayoutOrder = 1
			cnt.ZIndex = 16
			cnt:SetAttribute("NoPolish", true)
			cnt.Parent = filledWrap
			local cap = Instance.new("TextLabel")
			cap.Name = "Caption"
			cap.BackgroundTransparency = 1
			cap.Font = S.Font.Read
			cap.TextSize = 13
			cap.TextColor3 = C_SUB
			cap.Text = "SLOTS FILLED"
			cap.AutomaticSize = Enum.AutomaticSize.X
			cap.Size = UDim2.new(0, 0, 1, 0)
			cap.LayoutOrder = 2
			cap.ZIndex = 16
			cap:SetAttribute("NoPolish", true)
			cap.Parent = filledWrap
		end

		if lockedCount > 0 then
			local lockPill = darkPill(headLeft, 26)
			lockPill.Name = "LockedPill"
			lockPill.LayoutOrder = 3
			do
				local st = lockPill:FindFirstChildOfClass("UIStroke")
				if st then
					st.Color = C_GOLD
					st.Transparency = 0.5
				end
				local lp = Instance.new("UIPadding")
				lp.PaddingLeft = UDim.new(0, 10)
				lp.PaddingRight = UDim.new(0, 10)
				lp.Parent = lockPill
				local ll = Instance.new("TextLabel")
				ll.Name = "Label"
				ll.BackgroundTransparency = 1
				ll.Font = S.Font.Read
				ll.TextSize = 12
				ll.TextColor3 = C_GOLD
				ll.Text = lockedCount .. " LOCKED"
				ll.AutomaticSize = Enum.AutomaticSize.X
				ll.Size = UDim2.new(0, 0, 1, 0)
				ll.ZIndex = 16
				ll:SetAttribute("NoPolish", true)
				ll.Parent = lockPill
			end
		end

		local headRight = Instance.new("Frame")
		headRight.Name = "Right"
		headRight.BackgroundTransparency = 1
		headRight.AnchorPoint = Vector2.new(1, 0)
		headRight.Position = UDim2.new(1, 0, 0, 0)
		headRight.AutomaticSize = Enum.AutomaticSize.X
		headRight.Size = UDim2.new(0, 0, 1, 0)
		headRight.ZIndex = 15
		headRight.Parent = bayHead
		do
			local rl = Instance.new("UIListLayout")
			rl.FillDirection = Enum.FillDirection.Horizontal
			rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
			rl.VerticalAlignment = Enum.VerticalAlignment.Center
			rl.Padding = UDim.new(0, 12)
			rl.SortOrder = Enum.SortOrder.LayoutOrder
			rl.Parent = headRight
		end

		local totalPill = darkPill(headRight, 36)
		totalPill.Name = "TotalPill"
		totalPill.LayoutOrder = 1
		do
			local tp = Instance.new("UIPadding")
			tp.PaddingLeft = UDim.new(0, 8)
			tp.PaddingRight = UDim.new(0, 14)
			tp.Parent = totalPill
			local tl = Instance.new("UIListLayout")
			tl.FillDirection = Enum.FillDirection.Horizontal
			tl.VerticalAlignment = Enum.VerticalAlignment.Center
			tl.Padding = UDim.new(0, 8)
			tl.SortOrder = Enum.SortOrder.LayoutOrder
			tl.Parent = totalPill
			local tcoin = Instance.new("ImageLabel")
			tcoin.Name = "Coin"
			tcoin.BackgroundTransparency = 1
			tcoin.Image = T.icons.coin
			tcoin.Size = UDim2.fromOffset(24, 24)
			tcoin.LayoutOrder = 1
			tcoin.ZIndex = 16
			tcoin.Parent = totalPill
			local tm = Instance.new("TextLabel")
			tm.Name = "Caption"
			tm.BackgroundTransparency = 1
			tm.Font = S.Font.Read
			tm.TextSize = 13
			tm.TextColor3 = C_SUB
			tm.Text = "TOTAL"
			tm.AutomaticSize = Enum.AutomaticSize.X
			tm.Size = UDim2.new(0, 0, 1, 0)
			tm.LayoutOrder = 2
			tm.ZIndex = 16
			tm:SetAttribute("NoPolish", true)
			tm.Parent = totalPill
			local tv = Instance.new("TextLabel")
			tv.Name = "Value"
			tv.BackgroundTransparency = 1
			tv.Font = S.Font.Read
			tv.TextSize = 18
			tv.TextColor3 = C_GOLD
			tv.Text = shortCash(plotIncome) .. "/s"
			tv.AutomaticSize = Enum.AutomaticSize.X
			tv.Size = UDim2.new(0, 0, 1, 0)
			tv.LayoutOrder = 3
			tv.ZIndex = 16
			tv:SetAttribute("NoPolish", true)
			tv.Parent = totalPill
		end

		local unequipSlot = Instance.new("Frame")
		unequipSlot.Name = "UnequipSlot"
		unequipSlot.BackgroundTransparency = 1
		unequipSlot.Size = UDim2.fromOffset(130, 36)
		unequipSlot.LayoutOrder = 2
		unequipSlot.ZIndex = 15
		unequipSlot.Parent = headRight
		local unequipBtn = flatButton(unequipSlot, "UNEQUIP ALL", 130, 36, false, true)
		unequipBtn.Name = "UnequipAll"
		unequipBtn.MouseButton1Click:Connect(function()
			for _, e in ipairs(placedEntries) do
				remotes.StoreBrainrot:FireServer(e.Uid)
			end
		end)

		-- The fold control sits in the bay header; LayoutOrder 0 puts it left of the
		-- EQUIPPED chip, and it reuses flatButton so it matches every other pill in
		-- the panel. Collapsing hands 184px straight to the inventory, taking its
		-- scroll viewport from 1.3 rows to 2.6 -- 8 fully visible tiles to 16.
		-- renderBrainrots() is the same self-re-render the sort pills already use,
		-- and the flag lives on ctx.state.backpack so the choice survives closing
		-- the panel, exactly like the selected tab does.
		do
			local tog = flatButton(headLeft, if bayCollapsed then "SHOW PLOT" else "HIDE PLOT", 112, 32, false)
			tog.Name = "BayToggle"
			tog.LayoutOrder = 0
			tog.MouseButton1Click:Connect(function()
				ctx.state.backpack.bayCollapsed = not bayCollapsed
				renderBrainrots()
			end)
		end

		if not bayCollapsed then
			local bayGrid = Instance.new("Frame")
			bayGrid.Name = "BayGrid"
			bayGrid.AnchorPoint = Vector2.new(0.5, 0)
			bayGrid.Position = UDim2.new(0.5, 0, 0, WELL_PAD + HEAD_H + 8)
			bayGrid.Size = UDim2.fromOffset(GRIDW, EQ_H * 2 + CARD_GAP)
			bayGrid.BackgroundTransparency = 1
			bayGrid.ZIndex = 15
			bayGrid.Parent = bay
			do
				local bgl = Instance.new("UIGridLayout")
				bgl.CellSize = UDim2.fromOffset(CARD_W, EQ_H)
				bgl.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
				bgl.SortOrder = Enum.SortOrder.LayoutOrder
				bgl.Parent = bayGrid
			end
			for spot = 1, 16 do
				buildBaySlot(bayGrid, spot, placedByPad[spot])
			end
		end

		-------------------------------------------------- INVENTORY
		local invHead = Instance.new("Frame")
		invHead.Name = "InventoryHeader"
		invHead.Position = UDim2.fromOffset(0, BAY_H + SECTION_GAP)
		invHead.Size = UDim2.fromOffset(BR_W, INV_HEAD_H)
		invHead.BackgroundTransparency = 1
		invHead.ZIndex = 14
		invHead.Parent = contentHost

		local invLeft = Instance.new("Frame")
		invLeft.Name = "Left"
		invLeft.BackgroundTransparency = 1
		invLeft.AutomaticSize = Enum.AutomaticSize.X
		invLeft.Size = UDim2.new(0, 0, 1, 0)
		invLeft.ZIndex = 14
		invLeft.Parent = invHead
		do
			local il = Instance.new("UIListLayout")
			il.FillDirection = Enum.FillDirection.Horizontal
			il.VerticalAlignment = Enum.VerticalAlignment.Center
			il.Padding = UDim.new(0, 12)
			il.SortOrder = Enum.SortOrder.LayoutOrder
			il.Parent = invLeft
			local title = Instance.new("TextLabel")
			title.Name = "Title"
			title.BackgroundTransparency = 1
			title.Font = S.Font.Shout
			title.TextSize = 22
			-- INVENTORY sits on the panel BODY, which SpecTheme now paints pale cool
		-- (#F5F8FC) -- white here was invisible the moment the wells went light.
		title.TextColor3 = Color3.fromHex("33414F")
			title.Text = "INVENTORY"
			title.AutomaticSize = Enum.AutomaticSize.X
			title.Size = UDim2.new(0, 0, 1, 0)
			title.LayoutOrder = 1
			title.ZIndex = 15
			title:SetAttribute("NoPolish", true)
			title.Parent = invLeft
			local ts = Instance.new("UIStroke")
			ts.Thickness = 2
			ts.Color = C_INK
			ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			ts.Parent = title
		end
		local bagCount = Instance.new("TextLabel")
		bagCount.Name = "OwnedCount"
		bagCount.BackgroundTransparency = 1
		bagCount.Font = S.Font.Read
		bagCount.TextSize = 14
		bagCount.TextColor3 = C_SUB
		bagCount.Text = ""
		bagCount.AutomaticSize = Enum.AutomaticSize.X
		bagCount.Size = UDim2.new(0, 0, 1, 0)
		bagCount.LayoutOrder = 2
		bagCount.ZIndex = 15
		bagCount:SetAttribute("NoPolish", true)
		bagCount.Parent = invLeft

		local SORT_W, SORT_GAP2 = 96, 8
		local sorts = Instance.new("Frame")
		sorts.Name = "SortButtons"
		sorts.AnchorPoint = Vector2.new(1, 0.5)
		sorts.Position = UDim2.new(1, 0, 0.5, 0)
		sorts.Size = UDim2.fromOffset(3 * SORT_W + 2 * SORT_GAP2, 36)
		sorts.BackgroundTransparency = 1
		sorts.ZIndex = 14
		sorts.Parent = invHead
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

		-- SEARCH LIVES IN THE TOP ROW (user, 2026-08-14: "move the search to the top
		-- like theirs"). The reference parks it top-right beside the close button,
		-- above everything; ours was buried in the middle of the panel, in the
		-- INVENTORY header between the equipped bay and the grid, which is the last
		-- place you look. headRight is the bay header's right-aligned list, so
		-- LayoutOrder 0 puts search leftmost in that group -- ahead of TOTAL and
		-- UNEQUIP ALL -- and it costs ZERO extra height because that row already
		-- exists. It also survives collapsing the plot, since the header stays.
		local SEARCH_W = 220   -- 280 crowded TOTAL and UNEQUIP ALL out of the row
		-- 2026-09-18 UI foundation: the kit's SearchBar (same 36px row, same
		-- headRight slot, same searchQuery). fillBag is defined below, so the
		-- handler reaches it through gridUi.fill (assigned once fillBag exists).
		local search = SearchBar.new({
			placeholder = "SEARCH...", width = SEARCH_W, height = 36, parent = headRight, zIndex = 15, layoutOrder = 0,
			onChanged = function(q)
				if q == searchQuery then return end -- set() re-emits the same query on every re-render
				searchQuery = q
				if gridUi.fill then gridUi.fill() end
			end,
		})
		search.set(searchQuery)

		local subY = BAY_H + SECTION_GAP + INV_HEAD_H + SECTION_GAP
		local sub = buildWell(subY, CONTENT_H - subY)
		sub.Name = "InventoryWell"

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Grid"
		scroll.Position = UDim2.fromOffset(10, 10)
		scroll.Size = UDim2.new(1, -20, 1, -20)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 8
		scroll.ScrollBarImageColor3 = Color3.fromHex("3A4356")
		scroll.CanvasSize = UDim2.new()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ElasticBehavior = Enum.ElasticBehavior.Never
		scroll.ZIndex = 14
		scroll.Parent = sub
		grid = scroll
		do
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, math.max(0, math.floor((BR_W - 20 - GRIDW) / 2)))
			pad.Parent = scroll
			local gl = Instance.new("UIGridLayout")
			gl.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
			gl.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
			gl.SortOrder = Enum.SortOrder.LayoutOrder
			gl.Parent = scroll
		end

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
					if hideCardTip then hideCardTip() end -- a tap (touch) must not leave another card's tooltip up
					newUids[e.Uid] = nil
					card.setState({ new = false }) -- clear the NEW badge locally, plot-full branch included
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

		fillBag()

		if keepScroll then
			-- restore after AutomaticCanvasSize settles (defer + a beat later)
			local s = scroll
			task.defer(function()
				if s.Parent then
					s.CanvasPosition = keepScroll
				end
			end)
			task.delay(0.06, function()
				if s.Parent then
					s.CanvasPosition = keepScroll
				end
			end)
		end

	end

	----------------------------------------------------------- PETS tab
	-- Drops any pinned Equip footer and gives the scroll area its full height back.
	-- Called at the top of every path that repaints this column so the footer can
	-- never outlive the pet it belongs to -- including the no-selection path below,
	-- which returns early.
	local function clearDetailFooter()
		local pinned = detailHost:FindFirstChild("DetailFooter")
		if pinned then pinned:Destroy() end
		detailContent.Size = UDim2.fromScale(1, 1)
	end

	local function renderPetDetail(pet, def)
		clearDetailFooter()
		if not pet or not def then
			buildDetailPlaceholder("Select a pet to see its stats.")
			return
		end
		clearChildren(detailContent)

		local PetConfig = require(PetConfigModule)
		local heroRamp = S.Rarity[RARITY_RAMP_KEY2[def.Rarity] or "COM"] or S.Rarity.COM
		local hero = Instance.new("Frame")
		hero.Name = "Hero"
		hero.LayoutOrder = 1
		hero.Size = UDim2.new(1, 0, 0, 150)
		hero.BackgroundColor3 = Color3.fromHex("FFFFFF")
		hero.BorderSizePixel = 0
		hero.ZIndex = detailContent.ZIndex + 1
		hero.Parent = detailContent
		UI.corner(hero, T.radius.small) -- kit "hero art ... radius 12"
		-- PS99: light art well + rarity edge (the dark card family left with the
		-- dark detail slab)
		UI.gradient(hero, ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("EEF2F8")))
		local heroStroke = UI.stroke(hero, T.stroke.control)
		if heroStroke then heroStroke.Color = heroRamp[2] end
		-- BUG (fixed 2026-08-11): this called build3DOrSwatch(def.Name) -- the
		-- BRAINROT lookup, which misses on BOTH folder and key for the 15-pet
		-- roster (see build3DPetOrSwatch's own header) and fell through to a flat
		-- swatch. The pet detail hero has been a blank tan box since pets shipped;
		-- only the ten retired brainrot stand-ins ever rendered here.
		build3DPetOrSwatch(hero, def, UDim2.new(1, -12, 1, -12), UDim2.fromOffset(6, 6), hero.ZIndex + 1, rarityTint(T, def.Rarity))

		local name = UI.label(detailContent, def.Name, "cardLabel", T.color.textOnLight) -- ink on the light column
		name:SetAttribute("NoPolish", true)
		name.Name = "Name"
		name.LayoutOrder = 2
		name.Size = UDim2.new(1, 0, 0, 26)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = detailContent.ZIndex + 1

		local chip = Instance.new("Frame")
		chip.Name = "RarityChip"
		chip.LayoutOrder = 3
		chip.Size = UDim2.new(1, 0, 0, 28)
		chip.BackgroundColor3 = T.color.white
		chip.BorderSizePixel = 0
		chip.ZIndex = detailContent.ZIndex + 1
		chip.Parent = detailContent
		UI.corner(chip, T.radius.small)
		-- PS99: the chip rode T.gradient.row (dark navy). Flipped to the light
		-- slot ramp; the rarity colour moves to the chip's EDGE so the word
		-- itself stays readable ink (pale tiers died as text colour on white).
		UI.gradient(chip, T.gradient.slot)
		local chipStroke = UI.stroke(chip, T.stroke.hairline)
		if chipStroke then chipStroke.Color = rarityTint(T, def.Rarity) end
		local chipLabel = UI.label(chip, def.Rarity:upper(), "chip", T.color.textOnLight)
		chipLabel.Size = UDim2.fromScale(1, 1)
		chipLabel.AutomaticSize = Enum.AutomaticSize.None
		chipLabel.TextXAlignment = Enum.TextXAlignment.Center
		chipLabel.ZIndex = chip.ZIndex + 1
		chipLabel:SetAttribute("NoPolish", true)

		local luck, income = PetConfig.BoostsFor(pet.Id)
		buildStatRow(4, "LUCK", trimNum(luck) .. "x")
		buildStatRow(5, "MONEY", trimNum(income) .. "x")

		-- THE SIGNATURE ABILITY (2026-08-22). Two ordinary stat rows rather than a
		-- bespoke card: this column is a stack of identical tiles, and an ability drawn
		-- to look different would read as a separate feature instead of as the pet's
		-- third number. First row names it, second states the seam and the bonus, so
		-- two pets can be compared on it directly.
		-- Both rows are SKIPPED for a pet with no ability rather than drawn empty.
		-- Nothing in the shipped roster hits that branch (PetConfig.Audit proves it).
		-- ONE row, not two (2026-08-22). Two rows spent 68px of a 231px column on a
		-- single stat and pushed the Equip button further out of view; this says the
		-- same three things -- which stat, what it is called, how much -- in one.
		local ability = PetConfig.AbilityFor(pet.Id)
		if ability then
			local kind = PetConfig.ABILITY_KINDS[ability.Kind]
			buildStatRow(6, string.upper(kind.Label),
				("%s +%s"):format(ability.Name or kind.Label, trimNum(ability.Amount or 0)))
		end

		local isEquipped = false
		for _, u in ipairs(petSlots) do
			if u == pet.Uid then
				isEquipped = true
				break
			end
		end
		-- real cap from the server ("PetSlotCap", see renderPets' slot row) --
		-- SLOTS_FREE was a lie for a pass holder, whose 4th equip is legal
		local cap = tonumber(player:GetAttribute("PetSlotCap")) or PetConfig.SLOTS_FREE
		local blocked = (not isEquipped) and #petSlots >= cap
		-- blocked no longer a dead end: the slot cards above unequip on click,
		-- so the label points there instead of just stating the number
		local label = blocked and "FULL \u{2014} CLICK A SLOT" or (isEquipped and "Unequip" or "Equip")
		-- (The old FIX F1 note lived here -- it explained why this button needed a
		-- wrapper Frame rather than being parented straight to the UIListLayout-managed
		-- detailContent. Still true of renderBrainrotDetail's button, no longer true of
		-- this one: it is not in the list at all any more.)
		--
		-- A PINNED FOOTER, not the last row of the list (owner, 2026-08-22: "the
		-- option to equip and unequip pets gets cut off").
		--
		-- With the pet slot row expanded this column is 231px tall and one pet's
		-- stats are ~440px of canvas, so an Equip button at the END of the list is
		-- always below the fold. Making the column scroll (see detailContent) made it
		-- reachable, but the only control in the column should not have to be hunted
		-- for. It lives on detailHost OUTSIDE the scrolling content, and
		-- detailContent gives up a matching strip at its bottom so no stat row can
		-- scroll underneath it. clearDetailFooter() undoes both.
		local FOOTER_H = 56
		detailContent.Size = UDim2.new(1, 0, 1, -(FOOTER_H + 12))
		local equipSlot = Instance.new("Frame")
		equipSlot.Name = "DetailFooter"
		equipSlot.AnchorPoint = Vector2.new(0.5, 1)
		equipSlot.Position = UDim2.new(0.5, 0, 1, -12)
		equipSlot.Size = UDim2.new(1, -24, 0, FOOTER_H)
		equipSlot.BackgroundTransparency = 1
		equipSlot.ZIndex = detailHost.ZIndex + 3
		equipSlot.Parent = detailHost

		local btn = UI.button(equipSlot, label, blocked and "disabled" or "green", UDim2.fromScale(1, 1), "buttonM")
		btn.Name = "EquipButton"
		btn.ZIndex = equipSlot.ZIndex
		if not blocked then
			btn.MouseButton1Click:Connect(function()
				-- Server-authoritative (BackpackClient's own documented rule for
				-- pets, see header note): no local write. The tile/detail only
				-- update once DataUpdated confirms the new PetSlots.
				remotes.PetEquip:FireServer(pet.Uid, not isEquipped)
			end)
		end

		-- === SELL: MOVED OUT OF THE BAG (2026-08-21, owner call) ==============
		-- Pets are sold at MARCO'S STALL ONLY. The two-step SELL pill that used
		-- to sit here under Equip is gone: a permanent action should not be one
		-- stray click away inside the menu players open to equip. SellPanel's
		-- pet tab is the single drain now, and its multi-select + confirm is
		-- the guard the in-place arm/disarm was standing in for.
		-- remotes.SellPet is untouched -- SellPanel is simply its only caller.
	end

	local function findPet(uid)
		for _, p in ipairs(ownedPets) do
			if p.Uid == uid then
				return p
			end
		end
		return nil
	end

	-- PET GRID TILES (2026-08-11 juiced cards; 2026-08-16 ported to the PS99
	-- house grid language). What survives from the juiced pass: the pips, the
	-- holo art ring, the LUCK PILL (pet records are unique -- no stacking --
	-- and the multiplier is what you choose one by) and the band frame that
	-- carries the PET'S NAME. What changed 2026-08-16: the dark plate, the
	-- ramp-coloured banner and the aura/foil washes are gone -- art floats on
	-- a pastel splash over the LIGHT well, the name is naked dark ink with a
	-- white halo, and Secret/God identity rides the splash tint
	-- (SPLASH_SPECIAL_TIER).
	-- (foil/aura fields are legacy after the 2026-08-16 port -- only pips and
	-- holo still draw; the fields stay so the ensureFx gate reads unchanged)
	local PET_JUICE = {
		common  = { pips = 1, foil = nil,  aura = false, holo = false },
		rare    = { pips = 2, foil = nil,  aura = false, holo = false },
		epic    = { pips = 3, foil = 0.92, aura = false, holo = false },
		legend  = { pips = 4, foil = 0.88, aura = true,  holo = false },
		rainbow = { pips = 5, foil = 0.84, aura = true,  holo = true  },
	}
	local function buildPetTile(parent: Instance, order: number, pet, def, isSelected: boolean)
		-- see buildTileCell: without this wrapper the hard shadows become phantom grid
		-- cells and shove every pet out of the visible scroll window
		local cell = buildTileCell(parent, "PetCell" .. order, order)
		local PetConfig = require(PetConfigModule)
		local ramp = S.Rarity[RARITY_RAMP_KEY2[def.Rarity] or "COM"] or S.Rarity.COM
		local level = PET_JUICE[kitRarityKey(def.Rarity)] or PET_JUICE.common
		local PET_BAND_H = 26

		local card = Instance.new("Frame")
		card.Name = "PetTile" .. order
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.5)
		card.Size = UDim2.fromScale(1, 1)
		card.BackgroundColor3 = Color3.fromHex("252E3D")
		-- PS99 delta 4 (2026-08-16): pet grid cards lose the cell box -- plate
		-- invisible, art floats on a pastel splash. Clipping off so the 1.15x
		-- splash is not rect-cut at the card edge (ClipsDescendants ignores
		-- UICorner, so nothing else relied on it visually -- band/aura/foil all
		-- sit inside the rect).
		card.BackgroundTransparency = 1
		card.BorderSizePixel = 0
		card.ClipsDescendants = false
		card.ZIndex = 15
		card.Parent = cell
		UI.corner(card, 14)
		-- splash FIRST so every existing child keeps rendering above it; a
		-- selected pet gets the stronger splash on top of its SelectedRing
		addSplash(card, splashTint(def.Rarity, tostring(def.Name), ramp[2]), isSelected,
			BrainrotThumb.isPale(BrainrotThumb.petMaster(def.Model, def.Name)))
		local edge = Instance.new("UIStroke")
		edge.Thickness = 3
		edge.Color = ramp[2]
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.LineJoinMode = Enum.LineJoinMode.Round
		-- delta 4: border hidden, object kept. Selection is the separate
		-- SelectedRing below and the equipped pulse is its own UIStroke --
		-- nothing re-enables this one, so it hides fully.
		edge.Transparency = 1
		edge.Enabled = false
		edge.Parent = card
		-- (the old dark-navy card gradient is gone with the plate: a gradient on
		-- a fully transparent background painted nothing, and could only come
		-- back as a dark box if the transparency ever regressed)

		-- PS99 port (2026-08-16): the aura wash and rainbow foil rectangles are
		-- gone. They were dark-card juice, and on the light well they re-drew
		-- exactly the boxy plate the splash treatment removes. Top-tier identity
		-- now rides the splash tint (SPLASH_SPECIAL_TIER), the pips and the holo
		-- ring on the art.

		local shadowOval = Instance.new("Frame")
		shadowOval.Name = "ContactShadow"
		shadowOval.AnchorPoint = Vector2.new(0.5, 1)
		shadowOval.Position = UDim2.new(0.5, 0, 1, -(PET_BAND_H + 4))
		shadowOval.Size = UDim2.new(0.5, 0, 0, 8)
		shadowOval.BackgroundColor3 = Color3.new(0, 0, 0)
		shadowOval.BackgroundTransparency = 0.55
		shadowOval.BorderSizePixel = 0
		shadowOval.ZIndex = 16
		shadowOval.Parent = card
		UI.corner(shadowOval, 999)

		local artHolder = Instance.new("Frame")
		artHolder.Name = "Art"
		artHolder.Position = UDim2.new(0, 6, 0, 6)
		artHolder.Size = UDim2.new(1, -12, 1, -(PET_BAND_H + 12))
		artHolder.BackgroundTransparency = 1
		artHolder.ZIndex = 17
		artHolder.Parent = card
		build3DPetOrSwatch(artHolder, def, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), artHolder.ZIndex + 1, rarityTint(T, def.Rarity))
		if level.holo then
			UI.rainbowRing(artHolder, 12)
		end

		local pips = Instance.new("Frame")
		pips.Name = "Pips"
		pips.Position = UDim2.fromOffset(7, 7)
		pips.Size = UDim2.fromOffset(60, 8)
		pips.BackgroundTransparency = 1
		pips.ZIndex = 19
		pips.Parent = card
		for i2 = 1, 5 do
			local pip = Instance.new("Frame")
			pip.Size = UDim2.fromOffset(6, 6)
			pip.Position = UDim2.fromOffset((i2 - 1) * 11, 1)
			pip.Rotation = 45
			pip.BorderSizePixel = 0
			pip.ZIndex = 19
			pip.BackgroundColor3 = (i2 <= level.pips) and ramp[1] or Color3.fromHex("39414F")
			pip.Parent = pips
		end

		local isEquipped = false
		for _, u in ipairs(petSlots) do
			if u == pet.Uid then
				isEquipped = true
				break
			end
		end

		-- top-right stack: equipped tick first, then the luck pill shifted left of
		-- it (same bx walk the brainrot tile's badges use)
		local bx = -6
		if isEquipped then
			local beq = Instance.new("Frame")
			beq.Name = "EquippedBadge"
			beq.AnchorPoint = Vector2.new(1, 0)
			beq.Position = UDim2.new(1, bx, 0, 6)
			beq.Size = UDim2.fromOffset(19, 19)
			beq.BackgroundColor3 = Color3.fromHex("3DDC84")
			beq.BorderSizePixel = 0
			beq.ZIndex = 19
			beq.Parent = card
			UI.corner(beq, 6)
			local ck = Instance.new("TextLabel")
			ck.BackgroundTransparency = 1
			ck.Size = UDim2.fromScale(1, 1)
			ck.Font = S.Font.Shout
			ck.TextSize = 13
			ck.Text = "\u{2713}"
			ck.TextColor3 = Color3.fromHex("06301B")
			ck.ZIndex = 20
			ck:SetAttribute("NoPolish", true)
			ck.Parent = beq
			bx -= 24
			local ring = Instance.new("UIStroke")
			ring.Thickness = 2
			ring.Color = Color3.fromHex("3DDC84")
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ring.Parent = card
			table.insert(fx.pulseStroke, { st = ring, lo = 0.25, hi = 0.75 })
		end

		local luck = PetConfig.BoostsFor(pet.Id)
		local pill = Instance.new("Frame")
		pill.Name = "LuckPill"
		pill.AnchorPoint = Vector2.new(1, 0)
		pill.Position = UDim2.new(1, bx, 0, 6)
		-- 60, not 38: the pill used to read just "5x", which on a tile that can have
		-- several identical neighbours looks exactly like a STACK COUNT (owner read it
		-- as "5 of this pet", 2026-08-22). Pets are listed one tile per pet and never
		-- stacked, so the number needed a noun on it.
		pill.Size = UDim2.fromOffset(60, 18)
		-- PS99: light pill, dark ink (was a near-black chip from the dark skin)
		pill.BackgroundColor3 = Color3.fromHex("FFFFFF")
		pill.BackgroundTransparency = 0.1
		pill.BorderSizePixel = 0
		pill.ZIndex = 19
		pill.Parent = card
		UI.corner(pill, 999)
		local ps = Instance.new("UIStroke")
		ps.Thickness = 1.5
		ps.Color = ramp[2]
		ps.Transparency = 0.2
		ps.Parent = pill
		local pl = Instance.new("TextLabel")
		pl.Name = "Luck"
		pl.BackgroundTransparency = 1
		pl.Size = UDim2.fromScale(1, 1)
		pl.Font = S.Font.Shout
		pl.TextSize = 11
		pl.Text = trimNum(luck) .. "x LUCK"
		pl.TextColor3 = Color3.fromHex("33414F") -- ink; the pill's ramp stroke keeps the rarity accent
		pl.ZIndex = 20
		pl:SetAttribute("NoPolish", true)
		pl.Parent = pill

		-- NAME BAND. FIXED TextSize + TextTruncate, never TextScaled: TextScaled
		-- forces TextWrapped, which stacked "Bramble Bear" onto two overlapping
		-- lines inside a 26px band (caught in the first on-screen A/B).
		local band = Instance.new("Frame")
		band.Name = "Band"
		band.AnchorPoint = Vector2.new(0, 1)
		band.Position = UDim2.fromScale(0, 1)
		band.Size = UDim2.new(1, 0, 0, PET_BAND_H)
		band.BorderSizePixel = 0
		band.ZIndex = 18
		band.Parent = card
		-- PS99 port (2026-08-16): the ramp-coloured banner (hot magenta on the
		-- top tiers) and its holo rainbow strip are gone. The band frame stays
		-- for layout (art/shadow maths anchor to PET_BAND_H) but paints nothing;
		-- the name goes naked dark ink with a white halo -- the house light-grid
		-- treatment, same as the key tiles' captions.
		band.BackgroundTransparency = 1
		local bname = Instance.new("TextLabel")
		bname.Name = "PetName"
		bname.BackgroundTransparency = 1
		bname.Font = S.Font.Shout
		bname.TextSize = 15
		bname.TextTruncate = Enum.TextTruncate.AtEnd
		bname.TextColor3 = Color3.fromHex("33414F") -- dark ink on the light well
		bname.Text = string.upper(def.Name or "?")
		bname.TextXAlignment = Enum.TextXAlignment.Center
		bname.Position = UDim2.fromOffset(5, 0)
		bname.Size = UDim2.new(1, -10, 1, 0)
		bname.ZIndex = 19
		bname:SetAttribute("NoPolish", true)
		bname.Parent = band
		do -- every tier gets the halo now (holo used to skip it for its rainbow strip)
			local bst = Instance.new("UIStroke")
			bst.Thickness = 2.4
			bst.Color = Color3.new(1, 1, 1) -- white halo so the ink reads over any splash
			bst.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			bst.Parent = bname
		end

		if isSelected then
			local sel = Instance.new("Frame")
			sel.Name = "SelectedRing"
			sel.Size = UDim2.fromScale(1, 1)
			sel.BackgroundTransparency = 1
			sel.ZIndex = 20
			sel.Parent = card
			UI.corner(sel, 14)
			local selStroke = Instance.new("UIStroke")
			selStroke.Thickness = 3
			selStroke.Color = T.color.activeRing
			selStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			selStroke.Parent = sel
		end

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.ZIndex = 21
		hit.Parent = card
		local PET_HOVER = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		-- TweenService is NOT a local in this module (buildJuiceTile calls it
		-- inline for the same reason) -- a bare `TweenService` here is nil and
		-- would throw on the first hover.
		-- press feedback (2026-08-17): same Down-sink/Up-release the brainrot
		-- cards got -- a tile that answers hover but not the click reads dead
		local petHovered = false
		hit.MouseEnter:Connect(function()
			petHovered = true
			cell.ZIndex = 30
			game:GetService("TweenService"):Create(card, PET_HOVER, { Size = UDim2.new(1, 8, 1, 8) }):Play()
		end)
		hit.MouseLeave:Connect(function()
			petHovered = false
			cell.ZIndex = 15
			game:GetService("TweenService"):Create(card, PET_HOVER, { Size = UDim2.fromScale(1, 1) }):Play()
		end)
		hit.MouseButton1Down:Connect(function()
			game:GetService("TweenService"):Create(card, PET_HOVER, { Size = UDim2.new(1, -4, 1, -4) }):Play()
		end)
		hit.MouseButton1Up:Connect(function()
			game:GetService("TweenService"):Create(card, PET_HOVER,
				{ Size = petHovered and UDim2.new(1, 8, 1, 8) or UDim2.fromScale(1, 1) }):Play()
		end)
		hit.MouseButton1Click:Connect(function()
			selectedPetUid = pet.Uid
			renderPets()
		end)

		if level.aura or level.foil or level.holo or isEquipped then
			ensureFx()
		end
	end

	renderPets = function()
		clearChildren(contentHost)
		refreshHeader()

		local PetConfig = require(PetConfigModule) -- live read every render, see header note
		if not PetConfig.ENABLED then
			buildEmptyState(contentHost, "Pets hatch soon!")
			buildDetailPlaceholder("Pets hatch soon!")
			return
		end

		-- 2026-08-11 (user request, reworked same day from the recording): the
		-- SAME slot row the Charm Codex tab leads with -- full tab-body width,
		-- the Codex's 108-tall cards. EIGHT cards since 2026-08-20, in two rows of
		-- four: 3 free, 4-5 for cash, 6-8 for Robux (PetConfig.SLOT_PRICES /
		-- SLOT_ROBUX, which is also where the "gamepass adds two" model this row
		-- used to draw was retired). The REAL cap still comes from the server
		-- ("PetSlotCap" attribute, PetHandler.PublishLoadout) rather than being
		-- recomputed here: it folds in the legacy gamepass floor, which the client
		-- cannot ask MarketplaceService about itself. Falling back to SLOTS_FREE
		-- just draws 4-8 locked until the attribute lands.
		-- AN OCCUPIED CARD IS A BUTTON: click = unequip that pet (the recording
		-- showed the user clicking the cards and nothing answering -- and with
		-- every slot full there was no visible road to a different loadout).
		-- Rebuilt on every render: petSlots and the cap both arrive via
		-- DataUpdated -> scheduleRender, so the row can never show stale slots.
		local petCap = tonumber(player:GetAttribute("PetSlotCap")) or PetConfig.SLOTS_FREE
		-- ALWAYS DRAW ALL EIGHT (2026-08-20). The row used to stop at the premium
		-- cap, so slots you could buy simply did not exist on screen -- and a slot
		-- nobody can see is a slot nobody buys. Locked cards now state their own
		-- price, which makes the row the shop for them.
		-- ZERO WHEN FOLDED is how the fold is implemented: the card loop below simply
		-- does not run. Wrapping the loop in a conditional would have been the same
		-- thing with an extra level of indentation over ~200 lines of card building.
		local totalSlots = if petSlotsFolded() then 0 else math.max(PetConfig.SLOTS_MAX, petCap)
		local petsByUid = {}
		for _, p in ipairs(ownedPets) do petsByUid[p.Uid] = p end

		local slotRow = Instance.new("Frame")
		slotRow.Name = "PetSlotRow"
		slotRow.Size = UDim2.fromOffset(INDEX_W, petSlotBlockH())
		slotRow.BackgroundTransparency = 1
		slotRow.ZIndex = 14
		slotRow.Parent = contentHost

		-- HEADER STRIP. Always drawn, folded or not -- it is what you click to get the
		-- slots back, and it carries the abilities help toggle too. Both controls flip
		-- a ctx.state.backpack flag and re-run renderPets(), the same self-re-render
		-- the sort pills and the bay's fold already use.
		do
			local head = Instance.new("Frame")
			head.Name = "SlotHead"
			head.Size = UDim2.fromOffset(INDEX_W, PET_SLOTROW_HEAD_H)
			head.BackgroundTransparency = 1
			head.ZIndex = 15
			head.Parent = slotRow

			local cap = UI.label(head, ("PET SLOTS  %d / %d"):format(#petSlots, petCap), "meta", T.color.textOnLight)
			cap.Name = "SlotCount"
			cap:SetAttribute("NoPolish", true)
			cap.AnchorPoint = Vector2.new(0, 0.5)
			cap.Position = UDim2.new(0, 2, 0.5, 0)
			cap.Size = UDim2.fromOffset(240, PET_SLOTROW_HEAD_H)
			cap.AutomaticSize = Enum.AutomaticSize.None
			cap.TextXAlignment = Enum.TextXAlignment.Left
			cap.ZIndex = 16

			-- UI.button, NOT flatButton: flatButton is declared INSIDE renderBrainrots
			-- and is not in scope here (calling it from this tab is a nil-call that
			-- kills the whole pet render -- caught on screen 2026-08-22). UI.button is
			-- the panel-wide builder and is what the equip button here already uses.
			local tog = UI.button(head, if petSlotsCollapsed() then "SHOW SLOTS" else "HIDE SLOTS", "blue", UDim2.fromOffset(118, 30), "buttonM")
			tog.Name = "PetSlotToggle"
			tog.AnchorPoint = Vector2.new(1, 0.5)
			tog.Position = UDim2.new(1, 0, 0.5, 0)
			tog.ZIndex = 16
			tog.MouseButton1Click:Connect(function()
				ctx.state.backpack.petSlotsCollapsed = not petSlotsCollapsed()
				-- renderActiveTab(), NOT renderPets(): the DETAIL COLUMN's position and
				-- height are set in renderActiveTab, and it is the thing that then calls
				-- renderPets. Re-rendering the pets alone moved the well and left the
				-- detail column stranded at the expanded offset with a 233px gap above
				-- it (measured on screen 2026-08-22). No recursion: this path only runs
				-- on a click.
				renderActiveTab()
			end)

			local helpOn = ctx.state.backpack.petAbilityHelp == true
			local help = UI.button(head, if helpOn then "BACK TO PETS" else "WHAT ABILITIES DO", if helpOn then "green" else "purple", UDim2.fromOffset(176, 30), "buttonM")
			help.Name = "AbilityHelpToggle"
			help.AnchorPoint = Vector2.new(1, 0.5)
			help.Position = UDim2.new(1, -126, 0.5, 0)
			help.ZIndex = 16
			help.MouseButton1Click:Connect(function()
				ctx.state.backpack.petAbilityHelp = not helpOn
				renderActiveTab()
			end)
		end

		local slotCardGap = 12
		local slotCardW = math.floor((INDEX_W - slotCardGap * (PET_SLOT_COLS - 1)) / PET_SLOT_COLS)
		for i = 1, totalSlots do
			local slotLocked = i > petCap
			-- How this particular slot opens: free / cash / Robux. PetConfig owns
			-- that mapping so the card can print its own price without the panel
			-- knowing which slots cost what.
			local unlock = PetConfig.SlotUnlock(i)
			-- Only the NEXT locked slot is buyable -- they open in order, and the
			-- server refuses anything else. Drawing slot 5 as buyable while 4 is
			-- shut would be the panel offering a sale the server declines.
			local isNextSlot = slotLocked and (i == petCap + 1)
			local occupant = petSlots[i] and petsByUid[petSlots[i]]
			local occDef = occupant and PetConfig.Pets[occupant.Id]
			-- same card language as the Codex's slot row: white spec card when
			-- usable. 2026-08-17: a gamepass-locked slot is delta 8's PURCHASABLE
			-- state, not its dead-LOCKED state -- real money opens it, so it
			-- wears the same gold tile the bay's next plot slot does (the old
			-- charcoal slabs were the two darkest boxes on the whole panel).
			local card = PC.plate({
				name = "PetSlot" .. i,
				size = UDim2.fromOffset(slotCardW, PET_SLOTROW_H),
				position = UDim2.fromOffset(
					((i - 1) % PET_SLOT_COLS) * (slotCardW + slotCardGap),
					-- cards start BELOW the header strip that carries the fold control
					PET_SLOTROW_HEAD_H + 8
						+ math.floor((i - 1) / PET_SLOT_COLS) * (PET_SLOTROW_H + PET_SLOTROW_VGAP)),
				colors = if slotLocked
					then { S.Action.Gold[1], S.Action.Gold[2] } -- delta 8 PURCHASABLE gold
					else { S.Surface.RowTop, S.Surface.RowBottom },
				radius = 16,
				outline = 5,
				zIndex = 15,
				parent = slotRow,
				gloss = false,
			})
			if slotLocked then
				local cs = card:FindFirstChildOfClass("UIStroke")
				if cs then cs.Color = Color3.fromHex("8A6510") end -- bay purchasable-slot edge
			end
			PC.read({
				name = "Eyebrow", text = ("SLOT %02d"):format(i), size = 14,
				color = if slotLocked then Color3.fromHex("3A2A05") else S.Surface.ReadSub, -- dark ink on gold (bay rule)
				frameSize = UDim2.new(1, -24, 0, 18),
				position = UDim2.new(0, 12, 0, 10),
				zIndex = 16, parent = card,
			})
			if occDef then
				-- AN OCCUPIED SLOT SHOWS THE PET (2026-08-11). The card keeps the
				-- Codex's light slot-card shell -- the row has to stay the same
				-- component the Charms tab uses -- and gains a dark art plate with
				-- the real model and a rarity-coloured edge, which is also the only
				-- place the rarity is stated now (the text line it replaced cost the
				-- name so much width that "Bramble Bear" truncated).
				local slotRamp = S.Rarity[RARITY_RAMP_KEY2[occDef.Rarity] or "COM"] or S.Rarity.COM
				-- 2026-08-17: LIGHT art well (renderPetDetail's hero treatment) --
				-- the dark navy plate was a pre-PS99 leftover and rendered every
				-- equipped pet as a near-black square at 56px
				local artPlate = PC.plate({
					name = "ArtPlate",
					size = UDim2.fromOffset(56, 56),
					position = UDim2.fromOffset(12, 30),
					colors = { Color3.fromHex("FFFFFF"), Color3.fromHex("EEF2F8") },
					radius = 12,
					outline = 3,
					zIndex = 16,
					parent = card,
					gloss = false,
				})
				local apStroke = artPlate:FindFirstChildOfClass("UIStroke")
				if apStroke then apStroke.Color = slotRamp[2] end
				build3DPetOrSwatch(artPlate, occDef, UDim2.new(1, -6, 1, -6),
					UDim2.fromOffset(3, 3), 18, rarityTint(T, occDef.Rarity))

				-- WRAPPED, not truncated or TextScaled: the column left of the art
				-- plate is ~71px, and the on-screen A/B showed truncation eating
				-- every name past 8 characters while two wrapped lines fit
				-- "Heartwood Guardian" whole.
				local nameL = PC.read({
					name = "Occupant", text = occDef.Name, size = 14,
					color = S.Surface.ReadInk,
					frameSize = UDim2.new(1, -82, 0, 46),
					position = UDim2.new(0, 76, 0, 30),
					zIndex = 16, parent = card,
				})
				nameL.TextWrapped = true
				nameL.TextYAlignment = Enum.TextYAlignment.Top

				PC.read({
					name = "Caption", text = "CLICK TO UNEQUIP", size = 11,
					color = S.Surface.ReadSub,
					frameSize = UDim2.new(1, -24, 0, 14),
					position = UDim2.new(0, 12, 1, -21),
					zIndex = 16, parent = card,
				})
			else
				-- delta 8 state glyphs: a LOCKED slot wears a white padlock on
				-- its charcoal slab (the "Locked" word retired -- the eyebrow
				-- ranks the slot and the gold caption below carries the
				-- gamepass note; gold stays because gamepass = real money);
				-- an EMPTY slot wears the shared large charcoal '+'.
				if slotLocked then
					local lockHolder = Instance.new("Frame")
					lockHolder.Name = "Occupant"
					lockHolder.BackgroundTransparency = 1
					lockHolder.AnchorPoint = Vector2.new(0.5, 0)
					lockHolder.Position = UDim2.new(0.5, 0, 0, 32)
					lockHolder.Size = UDim2.fromOffset(26, 26)
					lockHolder.ZIndex = 16
					lockHolder.Parent = card
					buildPadlock(lockHolder, 22, Color3.fromHex("3A2A05"), 16) -- dark ink on gold, same as the bay's purchasable padlock
				else
					local plus = Instance.new("TextLabel")
					plus.Name = "Occupant"
					plus.BackgroundTransparency = 1
					plus.Font = S.Font.Shout
					plus.TextSize = 59 -- ~55% of the 108px slot card
					plus.TextColor3 = Color3.fromHex("33414F")
					plus.Text = "+"
					plus.Size = UDim2.fromScale(1, 1)
					plus.ZIndex = 16
					plus:SetAttribute("NoPolish", true)
					plus.Parent = card
				end
				-- WHAT OPENS THIS SLOT, printed on the card (2026-08-20). The old
				-- single "GAMEPASS . +2 SLOTS" line was true of a model that no
				-- longer exists: slots 4-5 are cash now and 6-8 are Robux, so the
				-- caption has to say WHICH and HOW MUCH or the row is just five
				-- padlocks. Only the next one in line reads as a call to action --
				-- see isNextSlot -- because that is the only one the server sells.
				local captionText
				if not slotLocked then
					captionText = "EQUIP A PET BELOW"
				elseif unlock.Kind == "cash" then
					captionText = isNextSlot
						and ("BUY \u{00B7} " .. NumberFormat.Cash(unlock.Price))
						or NumberFormat.Cash(unlock.Price)
				elseif unlock.Kind == "gamepass" then
					-- Live is false while the product id is the 0 sentinel, which is
					-- every one of them today -- so the card advertises the price it
					-- WILL be and says plainly that it is not on sale yet, rather
					-- than offering a purchase that cannot complete.
					captionText = unlock.Live
						and ("R$" .. tostring(unlock.Robux))
						or ("R$" .. tostring(unlock.Robux) .. " \u{00B7} SOON")
				else
					captionText = "LOCKED"
				end
				local caption = PC.read({
					name = "Caption",
					text = captionText,
					size = 12,
					-- dark ink now that the slab itself is gold (gold-on-charcoal retired)
					color = if slotLocked then Color3.fromHex("3A2A05") else S.Surface.ReadSub,
					frameSize = UDim2.new(1, -24, 0, 16),
					position = UDim2.new(0, 12, 1, -24),
					zIndex = 16, parent = card,
				})
				caption.TextScaled = true
				local capFit = Instance.new("UITextSizeConstraint")
				capFit.MaxTextSize = 12
				capFit.MinTextSize = 8
				capFit.Parent = caption
			end

			-- click an occupied slot = unequip that pet. Server-authoritative:
			-- no local write; the row rebuilds off DataUpdated like everything
			-- else. Empty and locked cards stay inert.
			if occupant then
				local hit = Instance.new("TextButton")
				hit.Name = "Hit"
				hit.Text = ""
				hit.Size = UDim2.fromScale(1, 1)
				hit.BackgroundTransparency = 1
				hit.ZIndex = 17
				hit.Parent = card
				local uidToDrop = occupant.Uid
				hit.MouseButton1Click:Connect(function()
					remotes.PetEquip:FireServer(uidToDrop, false)
				end)
			elseif isNextSlot and unlock.Kind == "gamepass" and unlock.Live then
				-- Slots 6-8 are GAME PASSES (2026-08-19). The click still goes through
				-- BuyPetSlot rather than prompting from here: the server re-derives which
				-- slot is actually next and opens the prompt itself, so a stale panel can
				-- never put the wrong pass in front of someone.
				local hit = Instance.new("TextButton")
				hit.Name = "Hit"
				hit.Text = ""
				hit.Size = UDim2.fromScale(1, 1)
				hit.BackgroundTransparency = 1
				hit.ZIndex = 17
				hit.Parent = card
				local passSlot = i
				hit.MouseButton1Click:Connect(function()
					remotes.BuyPetSlot:FireServer(passSlot)
				end)
			elseif isNextSlot and unlock.Kind == "cash" then
				-- CLICK THE NEXT LOCKED SLOT TO BUY IT. Server-authoritative like
				-- every other control on this panel: the slot number is all that
				-- goes over, and PetHandler re-derives which slot is actually owed
				-- and what it costs. A stale panel can therefore ask for the wrong
				-- slot but never buy one at the wrong price.
				--
				-- No confirm step: this spends cash rather than destroying
				-- anything, the price is printed on the card being clicked, and
				-- the server refuses outright when the player cannot afford it.
				local hit = Instance.new("TextButton")
				hit.Name = "Hit"
				hit.Text = ""
				hit.Size = UDim2.fromScale(1, 1)
				hit.BackgroundTransparency = 1
				hit.ZIndex = 17
				hit.Parent = card
				local slotToBuy = i
				hit.MouseButton1Click:Connect(function()
					remotes.BuyPetSlot:FireServer(slotToBuy)
				end)
			end
		end

		-- PS99 (2026-08-16): LIGHT sheet well, the same treatment as the brainrot
		-- inventory well. The old dark #11151D slab was the pre-restyle skin and
		-- read as a black photo-box block inside the white shell.
		local petWell = Instance.new("Frame")
		petWell.Name = "PetWell"
		petWell.Position = UDim2.fromOffset(0, petSlotBlockH() + PET_SLOTROW_GAP)
		petWell.Size = UDim2.fromOffset(GRID_COL_W, CONTENT_H - petSlotBlockH() - PET_SLOTROW_GAP)
		petWell.BackgroundColor3 = Color3.fromHex("EEF2F8")
		petWell.BorderSizePixel = 0
		petWell.ZIndex = 13
		petWell.Parent = contentHost
		UI.corner(petWell, 16)
		local pwStroke = Instance.new("UIStroke")
		pwStroke.Thickness = 2
		pwStroke.Color = Color3.fromHex("D3DCE7")
		pwStroke.Parent = petWell

		-- "WHAT ABILITIES DO" reference sheet, toggled from the slot-row header.
		-- Built in its own module (GameHUDPanels.PetAbilityHelp) because this file is
		-- past the 200,000-char Source-write ceiling and can only take small patches.
		-- It covers the grid rather than replacing it -- see that module's header.
		if ctx.state.backpack.petAbilityHelp == true then
			local okHelp, errHelp = pcall(function()
				require(script.Parent:WaitForChild("PetAbilityHelp")).Build({
					parent = petWell, UI = UI, T = T, S = S,
					PetConfig = PetConfig, trimNum = trimNum, pad = PET_WELL_PAD,
				})
			end)
			-- A broken help sheet must not take the Pets tab with it: fall through to
			-- the normal grid, which is built below either way.
			if not okHelp then
				warn("[BackpackPanel] PetAbilityHelp failed: " .. tostring(errHelp))
			end
		end

		-- === REWARD EGGS WAITING ON BAG SPACE (2026-08-20) ====================
		-- A wheel crate (or any reward that cannot refuse) hatched into a full pet
		-- bag parks its eggs on the profile instead of losing them -- see
		-- SeasonPassHandler's Egg branch. This banner is where the player gets
		-- them back, and it is the reason the parked state is visible at all: a
		-- jackpot the player was told about once, in a toast, over a spinning
		-- wheel, is a jackpot they will not remember they are owed.
		--
		-- Lives INSIDE the pet well and pushes the grid down, so it costs nothing
		-- when it is absent (the overwhelmingly common case) and the whole tab's
		-- geometry stays as it was.
		local CLAIM_H = 46
		local claimOffset = 0
		if bagState.PendingEggs > 0 then
			local n = bagState.PendingEggs
			local banner = PC.plate({
				name = "PendingEggs",
				size = UDim2.new(1, -PET_WELL_PAD * 2, 0, CLAIM_H),
				position = UDim2.fromOffset(PET_WELL_PAD, PET_WELL_PAD),
				colors = { S.Action.Gold[1], S.Action.Gold[2] },
				radius = 12,
				outline = 3,
				zIndex = 15,
				parent = petWell,
				gloss = false,
			})
			PC.read({
				name = "Copy",
				text = ("%d reward egg%s waiting \u{2014} make room to hatch %s")
					:format(n, n == 1 and "" or "s", n == 1 and "it" or "them"),
				size = 15,
				color = Color3.fromHex("3A2A05"), -- dark ink on gold, the bay's rule
				frameSize = UDim2.new(1, -160, 1, 0),
				position = UDim2.new(0, 14, 0, 0),
				zIndex = 16, parent = banner,
			})
			local claimBtn = UI.button(banner, "CLAIM", "green", UDim2.fromOffset(120, 32), "buttonM")
			claimBtn.Name = "ClaimEggs"
			claimBtn.AnchorPoint = Vector2.new(1, 0.5)
			claimBtn.Position = UDim2.new(1, -10, 0.5, 0)
			claimBtn.ZIndex = 17
			claimBtn.MouseButton1Click:Connect(function()
				-- Grants nothing that was not already won and already paid for, so a
				-- double click gets one reveal and then nothing. If there is still
				-- no room the server answers with the bag-full line.
				remotes.ClaimPendingEggs:FireServer()
			end)
			claimOffset = CLAIM_H + PET_WELL_PAD
		end

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "PetGrid"
		scroll.Position = UDim2.fromOffset(PET_WELL_PAD, PET_WELL_PAD + claimOffset)
		scroll.Size = UDim2.new(1, -PET_WELL_PAD * 2, 1, -PET_WELL_PAD * 2 - claimOffset)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 8
		scroll.ScrollBarImageColor3 = Color3.fromHex("3A4356") -- dark thumb on the light well, brainrot-grid parity
		scroll.CanvasSize = UDim2.new()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ElasticBehavior = Enum.ElasticBehavior.Never
		scroll.ZIndex = 14
		scroll.Parent = petWell

		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.fromOffset(PET_SLOT_W, PET_SLOT_H)
		gridLayout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = scroll

		-- rarest-first, same rank table BackpackClient's own Pets tab uses (RARITY_ORDER)
		local rank = {}
		for i, r in ipairs(PetConfig.RARITY_ORDER) do
			rank[r] = i
		end
		local order = table.clone(ownedPets)
		table.sort(order, function(a, b)
			local da, db = PetConfig.Pets[a.Id], PetConfig.Pets[b.Id]
			local ra = da and rank[da.Rarity] or 99
			local rb = db and rank[db.Rarity] or 99
			if ra ~= rb then
				return ra < rb
			end
			-- RARITY, THEN A-Z BY NAME (owner, 2026-08-22). It used to fall straight
			-- through to the Uid, which is a random GUID -- so within a rarity the
			-- grid was in no order at all and the copies of one pet were scattered
			-- across the whole tier. Sorting by name groups every duplicate together
			-- as a side effect, which is what makes a bag of 19 Moss Larvas readable.
			local na = (da and da.Name) or tostring(a.Id)
			local nb = (db and db.Name) or tostring(b.Id)
			if na ~= nb then
				return na < nb
			end
			-- Uid last, purely so the sort is STABLE: two copies of one pet are equal
			-- on both keys above, and an unstable comparator would let them swap
			-- places between renders and make the selection ring appear to jump.
			return tostring(a.Uid) < tostring(b.Uid)
		end)

		if #order == 0 then
			-- into the WELL, not the scroll: a UIGridLayout squashes the empty
			-- state into one cell (same trap the brainrot grid documents)
			buildEmptyState(petWell, "No pets yet \u{2014} hatch an egg at the Egg Stall.")
		else
			for i, p in ipairs(order) do
				local def = PetConfig.Pets[p.Id]
				if def then
					buildPetTile(scroll, i, p, def, p.Uid == selectedPetUid)
				end
			end
		end

		local selected = selectedPetUid and findPet(selectedPetUid)
		local def = selected and PetConfig.Pets[selected.Id]
		renderPetDetail(selected, def)
	end

	----------------------------------------------------------- CHARMS tab (embedded Codex, 2026-08-11)
	-- The Codex used to be a DOORWAY (switchTab called ctx.openPanel("charms"))
	-- which closed the Bag and stranded the player outside its tabs (user
	-- report). It embeds now, exactly like the Index below: built ONCE with
	-- the tab body's box, cached, detached before any clearChildren pass can
	-- destroy it, pcall self-heal on a dead cache.
	--[[ CHARMS ARE NOT SHIPPING YET (2026-08-19, owner). Every charm surface in
	the game answers the same way now -- this tab, and Lil Miss's three stalls via
	MerchantConfig.ComingSoon. It is not arbitrary: CharmConfig's own header says
	the real charms do not exist and every name and number in it is a stand-in,
	and there is no charm remote anywhere in the game, so nothing in the Codex
	could be equipped even though it renders.

	THE CODEX IS LEFT INTACT below rather than deleted -- it is a working 1120x700
	panel and re-authoring it later would be the real cost. Flip CHARMS_READY to
	true and the tab comes back exactly as it was, with no other edit here. ]]
	local CHARMS_READY = false
	local charmsFrame = nil
	renderCharms = function()
		if charmsFrame then
			local okDetach = pcall(function() charmsFrame.Parent = nil end)
			if not okDetach then charmsFrame = nil end
		end
		clearChildren(contentHost)
		refreshHeader()
		if not CHARMS_READY then
			buildEmptyState(contentHost, "Coming soon!")
			return
		end
		if not charmsFrame then
			local ok, built = pcall(CharmsPanel.Build, ctx, { embedded = true, width = INDEX_W, height = CONTENT_H })
			if ok and typeof(built) == "Instance" then
				charmsFrame = built
			else
				warn("[BackpackPanel] CharmsPanel.Build failed: " .. tostring(built))
				buildEmptyState(contentHost, "The Charm Codex could not be opened.")
				return
			end
		end
		charmsFrame.Parent = contentHost
		charmsFrame.Visible = true
	end

	----------------------------------------------------------- EGGS tab (empty state only)
	renderEggs = function()
		clearChildren(contentHost)
		refreshHeader()
		buildEmptyState(contentHost, "Crack eggs at Gino's stall!")
		buildDetailPlaceholder("Crack eggs at Gino's stall!")
	end

	----------------------------------------------------------- KEYS tab
	-- ONLY KEYS YOU ACTUALLY HAVE are listed. The first cut showed both as greyed
	-- "not earned yet" rows so a new player could see where each comes from; that
	-- turned the tab into a to-do list and read as clutter next to the other tabs,
	-- which never show what you do not own either. An unearned key is simply absent
	-- and the empty state carries the hint.
	--
	-- Two quite different things share the tab, which is why each tile is captioned:
	--   * Stupid Gianluca's Key is a COUNT, and it is SPENT. Opening Elder Tung's cellar
	--     hatch consumes one (ServerScriptService.CellarDoor) and stamps
	--     data.CellarUnlocked, after which the way down is free FOREVER for that player.
	--     The hatch takes BOTH keys -- his and Tung's -- which is the whole gate to the
	--     dungeon and the Frozen Tundra past it. The tundra portal itself is not locked.
	--   * Elder Tung's Cellar Key is not a currency at all. Finishing his list sets
	--     TungPortalUnlocked plus the HasCellarKey attribute, and the hatch is drawn
	--     per-client (StarterPlayerScripts.CellarDoorClient), so it opens for the
	--     holder alone -- a keyholder cannot walk a friend down the ladder.
	local function keyDefs()
		local defs = {}
		if keyState.Cellar then
			defs[#defs + 1] = {
				id = "Cellar",
				caption = "Cellar",
				name = "Elder Tung's Cellar Key",
				art = "keyCellar",
				tint = Color3.fromRGB(198, 150, 96), -- Tung's own wood-brown
				qty = nil,                            -- not a currency: you have it or you don't
				from = "Elder Tung",
				-- buildStatRow splits its 204px row 50/50 and the value is 18px display type,
				-- so anything past ~14 characters overflows leftwards and paints over its own
				-- key label. Keep these short; the full sentence belongs in `status`.
				opens = "Cellar hatch",
				status = "Opens for you alone, forever \u{2014} you cannot let a friend in on it.",
			}
		end
		-- A SPENT key still belongs here. Dropping the tile at count 0 would make the
		-- thing it bought look like it never existed, and the unlock is the whole point.
		if keyState.Gianluca > 0 or keyState.CellarPaid then
			defs[#defs + 1] = {
				id = "Gianluca",
				caption = "Gianluca",
				name = "Stupid Gianluca's Key",
				art = "keyGianluca",
				tint = Color3.fromHex("E8B23A"), -- gold key (textAccent is BLUE in the PS99 palette)
				qty = keyState.Gianluca,
				from = "Gianluca",
				opens = "Cellar hatch",   -- see the length note on the cellar key above
				status = keyState.CellarPaid
					and "Cellar unlocked, forever \u{2014} going down costs nothing now."
					or "Spend one at Elder Tung's hatch, with his key, to open it for good.",
			}
		end
		return defs
	end

	-- The kit's vector key art on the same slot plate a brainrot tile uses, so the two
	-- tabs read as one grid. IconArt.draw sizes and parents its own root, so the centring
	-- has to be applied afterwards.
	local function buildKeyArt(parent: Instance, def, artSize: number, zIndex: number): Frame
		local holder = Instance.new("Frame")
		holder.Name = "Art"
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.new(1, -12, 1, -12)
		holder.BackgroundColor3 = T.color.white
		holder.BorderSizePixel = 0
		holder.ZIndex = zIndex
		holder.Parent = parent
		UI.corner(holder, T.radius.art)
		UI.gradient(holder, ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("EEF2F8"))) -- PS99 cool slot family

		local art = IconArt.draw(holder, def.art, artSize, zIndex + 1)
		if art then
			art.AnchorPoint = Vector2.new(0.5, 0.5)
			art.Position = UDim2.fromScale(0.5, 0.5)
		end
		return holder
	end

	local function buildKeyTile(parent: Instance, order: number, def, isSelected: boolean)
		local cell = buildTileCell(parent, "KeyCell" .. def.id, order)
		-- 2026-08-10 inner restyle: white slot whose outline wears the key's
		-- own colour -- the role rarity plays on the other grids
		local tile = PC.plate({
			name = "Key" .. def.id,
			size = UDim2.fromScale(1, 1),
			colors = { S.Surface.RowTop, S.Surface.RowBottom },
			radius = 20,
			outline = 5,
			zIndex = 15,
			parent = cell,
			gloss = false,
		})
		local keyStroke = tile:FindFirstChildOfClass("UIStroke")
		if keyStroke then keyStroke.Color = def.tint end

		-- art sits in the upper part of the tile; the caption strip owns the bottom 22px
		local holder = buildKeyArt(tile, def, math.floor(SLOT_W * 0.62), tile.ZIndex + 1)
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, 6)
		holder.Size = UDim2.new(1, -12, 1, -30)
		-- the key's own colour as a keyline, the role rarityFrame plays on a brainrot tile
		local ring = UI.stroke(holder, T.stroke.chip)
		ring.Color = def.tint

		-- Captioned, unlike the brainrot tiles: two keys are two similar silhouettes and
		-- a creature is recognisable where a key is not.
		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.BackgroundTransparency = 1
		caption.FontFace = T.font.display
		caption.TextSize = 14
		caption.TextColor3 = Color3.fromHex("33414F") -- ink on the light key tile
		caption.Text = def.caption
		caption.AnchorPoint = Vector2.new(0.5, 1)
		caption.Position = UDim2.new(0.5, 0, 1, -5)
		caption.Size = UDim2.new(1, -8, 0, 18)
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.TextTruncate = Enum.TextTruncate.AtEnd
		caption.ZIndex = tile.ZIndex + 3
		caption.Parent = tile
		local capStroke = Instance.new("UIStroke")
		capStroke.Thickness = 2.5
		capStroke.Color = Color3.new(1, 1, 1) -- white halo behind ink text
		capStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		capStroke.Parent = caption

		if def.qty then
			local qty = Instance.new("TextLabel")
			qty.Name = "Quantity"
			qty.BackgroundTransparency = 1
			qty.Font = S.Font.Shout
			qty:SetAttribute("NoPolish", true)
			qty.TextSize = 20
			qty.TextColor3 = Color3.fromHex("33414F") -- ink on the light key tile
			qty.Text = "x" .. tostring(def.qty)
			qty.AnchorPoint = Vector2.new(1, 0)
			qty.Position = UDim2.new(1, -6, 0, 4)
			qty.Size = UDim2.fromOffset(40, 20)
			qty.TextXAlignment = Enum.TextXAlignment.Right
			qty.ZIndex = tile.ZIndex + 3
			qty.Parent = tile
			local qtyStroke = Instance.new("UIStroke")
			qtyStroke.Thickness = 2.5
			qtyStroke.Color = Color3.new(1, 1, 1) -- white halo behind ink text
			qtyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			qtyStroke.Parent = qty
		end

		if isSelected then
			local sel = Instance.new("Frame")
			sel.Name = "SelectedRing"
			sel.Size = UDim2.fromScale(1, 1)
			sel.BackgroundTransparency = 1
			sel.ZIndex = tile.ZIndex + 5
			sel.Parent = tile
			UI.corner(sel, T.radius.inner)
			local selStroke = Instance.new("UIStroke")
			selStroke.Thickness = 3
			selStroke.Color = T.color.activeRing
			selStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			selStroke.Parent = sel
		end

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.ZIndex = tile.ZIndex + 6
		hit.Parent = tile
		hit.MouseButton1Click:Connect(function()
			selectedKeyId = def.id
			renderKeys()
		end)
	end

	local function renderKeyDetail(def)
		if not def then
			buildDetailPlaceholder("Keys you earn show up here.")
			return
		end
		clearChildren(detailContent)

		local hero = Instance.new("Frame")
		hero.Name = "Hero"
		hero.LayoutOrder = 1
		hero.Size = UDim2.new(1, 0, 0, 150)
		hero.BackgroundColor3 = T.color.white
		hero.BorderSizePixel = 0
		hero.ZIndex = detailContent.ZIndex + 1
		hero.Parent = detailContent
		UI.corner(hero, T.radius.small)
		UI.gradient(hero, T.gradient.slot)
		UI.stroke(hero, T.stroke.control)
		buildKeyArt(hero, def, 118, hero.ZIndex + 1)

		local name = UI.label(detailContent, def.name, "cardLabel", T.color.textOnLight) -- ink on the light column
		name:SetAttribute("NoPolish", true)
		name.Name = "KeyName"
		name.LayoutOrder = 2
		name.Size = UDim2.new(1, 0, 0, 48)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.TextXAlignment = Enum.TextXAlignment.Center
		name.TextWrapped = true
		name.ZIndex = detailContent.ZIndex + 1

		buildStatRow(3, "From", def.from)
		buildStatRow(4, "Opens", def.opens)
		if def.qty then
			buildStatRow(5, "Held", tostring(def.qty))
		end

		local status = UI.label(detailContent, def.status, "meta", Color3.fromHex("3E8E1F")) -- readable green ink; claimRing neon died on the light column
		status:SetAttribute("NoPolish", true)
		status.Name = "Status"
		status.LayoutOrder = 6
		status.Size = UDim2.new(1, 0, 0, 76)
		status.AutomaticSize = Enum.AutomaticSize.None
		status.TextXAlignment = Enum.TextXAlignment.Left
		status.TextYAlignment = Enum.TextYAlignment.Top
		status.TextWrapped = true
		status.ZIndex = detailContent.ZIndex + 1
	end

	renderKeys = function()
		clearChildren(contentHost)
		refreshHeader()

		local defs = keyDefs()
		if #defs == 0 then
			buildEmptyState(contentHost, "No keys yet \u{2014} quests hand them out.")
			buildDetailPlaceholder("Keys you earn show up here.")
			return
		end

		-- Nothing selected (or the selection is gone) falls to the first key, so the
		-- detail column is never a blank slab next to a single tile.
		local chosen
		for _, def in ipairs(defs) do
			if def.id == selectedKeyId then chosen = def end
		end
		if not chosen then
			chosen = defs[1]
			selectedKeyId = chosen.id
		end

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "KeyGrid"
		scroll.Size = UDim2.fromOffset(GRID_COL_W, CONTENT_H)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 10
		scroll.ScrollBarImageColor3 = T.color.scrollThumb
		scroll.CanvasSize = UDim2.new()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ElasticBehavior = Enum.ElasticBehavior.Never
		scroll.ZIndex = 14
		scroll.Parent = contentHost

		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.fromOffset(SLOT_W, SLOT_H)
		gridLayout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = scroll

		for i, def in ipairs(defs) do
			buildKeyTile(scroll, i, def, def.id == chosen.id)
		end

		renderKeyDetail(chosen)
	end

	----------------------------------------------------------- TAGS tab
	-- Titles you have earned from the season pass. Click one to wear it; click the
	-- worn one again to take it off. The server re-checks ownership, so this only
	-- has to be honest about what it draws.
	renderTags = function()
		clearChildren(contentHost)
		refreshHeader()

		local owned = tagState.Owned
		local equipped = tagState.Equipped

		local defs = {}
		for id, def in pairs(SeasonConfig.TAGS) do
			-- Exclusive tags are never in `owned` (they are never written to a save);
			-- eligibility is the allowlist. Drawing the row for a non-creator would
			-- change nothing anyway -- the server refuses the equip -- but there is
			-- no reason to advertise it.
			local show = def.Exclusive and SeasonConfig.IsCreator(player.UserId) or (not def.Exclusive and owned[id])
			if show then
				defs[#defs + 1] = { id = id, label = def.Label, exclusive = def.Exclusive == true }
			end
		end
		-- exclusive first, then alphabetical
		table.sort(defs, function(a, b)
			if a.exclusive ~= b.exclusive then return a.exclusive end
			return a.label < b.label
		end)

		if #defs == 0 then
			buildEmptyState(contentHost, "No titles yet \u{2014} the season pass hands them out.")
			buildDetailPlaceholder("Titles show above your head and in chat.")
			return
		end

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "TagList"
		scroll.Size = UDim2.fromOffset(GRID_COL_W, CONTENT_H)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 10
		scroll.ScrollBarImageColor3 = T.color.scrollThumb
		scroll.CanvasSize = UDim2.new()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ElasticBehavior = Enum.ElasticBehavior.Never
		scroll.ZIndex = 14
		scroll.Parent = contentHost

		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, GRID_GAP)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = scroll

		for i, def in ipairs(defs) do
			local worn = (def.id == equipped)
			-- 2026-08-10 inner restyle: white spec row; the worn one is gold
			local row = PC.plate({
				name = "Tag" .. def.id,
				size = UDim2.fromOffset(GRID_COL_W - 14, 62),
				colors = worn and S.Action.Go or { S.Surface.RowTop, S.Surface.RowBottom }, -- delta 7: equipped = green
				radius = 20,
				outline = 5,
				zIndex = 15,
				parent = scroll,
				gloss = false,
			})
			row.LayoutOrder = i

			local name = UI.label(row, def.label, "cardLabel", S.Surface.ReadInk)
			name.AnchorPoint = Vector2.new(0, 0.5)
			name.Position = UDim2.new(0, 14, 0.5, 0)
			name.Size = UDim2.new(1, -140, 0, 24)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.ZIndex = row.ZIndex + 2

			local btn = UI.button(row, worn and "WEARING" or "WEAR",
				-- 2026-08-17 round-10 catch: WEAR was the last gold act button --
				-- titles cost nothing, and act = green game-wide (the worn ROW
				-- fill carries the state; both buttons stay green)
				"green", UDim2.fromOffset(110, 38), "buttonM")
			btn.Name = "WearButton"
			btn.AnchorPoint = Vector2.new(1, 0.5)
			btn.Position = UDim2.new(1, -12, 0.5, 0)
			btn.ZIndex = row.ZIndex + 3
			btn.MouseButton1Click:Connect(function()
				-- clicking the worn one takes it off. FindFirstChild, not index: the
				-- remote is created by SeasonPassHandler.Init and a panel built before
				-- that would otherwise throw rather than simply doing nothing.
				local rem = ctx.remotes:FindFirstChild("SeasonTagEquip")
				if rem then rem:FireServer(worn and nil or def.id) end
			end)
		end

		buildDetailPlaceholder("Your title shows above your head and in chat.")
	end

	----------------------------------------------------------- tab dispatch
	-- No Eggs entry: the tab was removed 2026-08-06. renderEggs stays defined
	-- above so putting the tab back is a two-line change, but nothing dispatches
	-- to it, and switchTab's `if not RENDERERS[id]` guard makes that safe.
	----------------------------------------------------------- Index tab
	-- UNLIKE CHARMS, THE INDEX EMBEDS. The Codex stays a doorway because it is
	-- 1120px wide and could not fit a tab body (see switchTab below); the Index is
	-- 940 and, crucially, computes every measurement it has from its PANEL_W -- grid
	-- cells, filter chips, the discovery bar. Handed a narrower width it reflows, so
	-- it can live in here properly rather than bouncing the player to another panel.
	--
	-- It gets the grid AND detail columns (524 + 14 + 224 = 762): a detail column
	-- means nothing for the Index, and 762 keeps the tiles close to their natural
	-- size rather than crushing them into 524.
	-- (INDEX_W itself is declared up in the geometry block -- renderCharms
	-- closes over it too, and a local declared after a function body is not
	-- in that function's scope.)

	-- BUILT ONCE AND PARKED, never rebuilt. IndexPanel.Build subscribes to remotes;
	-- rebuilding it on every tab switch would stack a fresh set of listeners each
	-- time. Parenting to nil keeps it alive (this upvalue is the reference) and out
	-- of reach of the other renderers, every one of which starts by clearing
	-- contentHost's children.
	local indexFrame = nil
	local function renderIndex()
		-- Detach the cached Index BEFORE the wipe (2026-08-10): clearChildren
		-- used to destroy a mounted indexFrame -- the first re-render while
		-- SITTING on the Index tab (any DataUpdated does it) killed the cache,
		-- and every later mount threw "Parent property locked" on the dead
		-- reference. This was the permanently-empty Index tab in the user's
		-- 2026-08-10 capture. The pcall is the self-heal: a reference that was
		-- destroyed anyway (Destroy locks Parent) rebuilds instead of erroring.
		if indexFrame then
			local okDetach = pcall(function() indexFrame.Parent = nil end)
			if not okDetach then indexFrame = nil end
		end
		clearChildren(contentHost)
		if not indexFrame then
			local ok, built = pcall(IndexPanel.Build, ctx, { embedded = true, width = INDEX_W })
			if ok and built then
				indexFrame = built
			else
				warn("[BackpackPanel] IndexPanel.Build failed: " .. tostring(built))
				buildEmptyState(contentHost, "The Index could not be opened.")
				return
			end
		end
		indexFrame.Parent = contentHost
		indexFrame.Visible = true
	end

	local RENDERERS = { Brainrots = renderBrainrots, Pets = renderPets, Charms = renderCharms, Keys = renderKeys, Tags = renderTags, Index = renderIndex }

	local function updateTabVisuals()
		-- mock restyle: selected = green plate + green ring; unselected = dark
		-- tile. BackgroundColor3 moves WITH the gradient (UIGradient MULTIPLIES
		-- the background -- the 2026-08-11 olive-tab lesson).
		for id, ring in pairs(tabRings) do
			local tabF = tabFrames[id]
			local g = tabF and tabF:FindFirstChildOfClass("UIGradient")
			local active = (id == activeTab)
			-- The rail was the last dark surface in the panel: a 105px near-black
			-- column running its full height beside a now-light body. Inactive tiles
			-- go light, and their label has to flip with them (below) or it vanishes.
			local c1 = active and Color3.fromHex("7DE86A") or Color3.fromHex("EEF2F8")
			local c2 = active and Color3.fromHex("28B93C") or Color3.fromHex("DDE3EC")
			tabF.BackgroundColor3 = c1
			if g then g.Color = ColorSequence.new(c1, c2) end
			local st = tabF:FindFirstChildOfClass("UIStroke")
			if st then st.Color = active and Color3.fromHex("1E5C12") or Color3.fromHex("C9D4E0") end
			-- (fix 2026-08-16) the tab label is named "Label", not "Text" -- the old
			-- lookup never found it, so the inactive ink below never applied
			local lbl = tabF:FindFirstChild("Label", true)
			if lbl and lbl:IsA("TextLabel") then
				lbl.TextColor3 = if active then Color3.new(1, 1, 1) else Color3.fromHex("33414F")
			end
			-- sticker pass: the active tab's glyph sits ~15% larger. SET, not
			-- tweened, so it survives every re-render path through here (the
			-- IconArt UIScale binding follows the Size property either way).
			local ic = tabIcons[id]
			if ic then
				local s = active and TAB_ICON_ACTIVE or TAB_ICON
				ic.Size = UDim2.fromOffset(s, s)
			end
			ring.Visible = active
			tabF.ZIndex = active and 15 or 14
		end
	end

	renderActiveTab = function()
		-- THE COLUMN SWAP LIVES HERE, in the one place every render goes through, so
		-- no individual renderer has to remember to put the layout back. The Index
		-- spans both columns; everything else gets the normal grid + detail split.
		local wide = (activeTab == "Index") or (activeTab == "Charms") or (activeTab == "Pets") or (activeTab == "Brainrots")
		contentHost.Size = UDim2.fromOffset(wide and INDEX_W or GRID_COL_W, CONTENT_H)
		-- Pets is wide for its full-width slot row but KEEPS the shared detail
		-- column -- moved down under the row (Charms/Index bring their own and
		-- hide it). Geometry restored for every other tab.
		if activeTab == "Pets" then
			detailHost.Visible = true
			-- petSlotBlockH(), not the raw block: the detail column has to move with the
			-- slot row's fold or it strands a 226px gap above itself when folded
			detailHost.Position = UDim2.fromOffset(TABS_COL_W + COL_GAP + GRID_COL_W + COL_GAP, petSlotBlockH() + PET_SLOTROW_GAP)
			detailHost.Size = UDim2.fromOffset(DETAIL_COL_W, CONTENT_H - petSlotBlockH() - PET_SLOTROW_GAP)
		else
			detailHost.Visible = not wide
			detailHost.Position = UDim2.fromOffset(TABS_COL_W + COL_GAP + GRID_COL_W + COL_GAP, 0)
			detailHost.Size = UDim2.fromOffset(DETAIL_COL_W, CONTENT_H)
		end
		-- Detach any cached wide frame that is not the one being shown: every
		-- other renderer opens with clearChildren(contentHost), which would
		-- destroy the cache.
		if indexFrame and activeTab ~= "Index" then
			indexFrame.Parent = nil
		end
		if charmsFrame and activeTab ~= "Charms" then
			charmsFrame.Parent = nil
		end

		-- A pinned detail footer belongs to the PETS tab alone; drop it before any
		-- other tab paints into this column, or it would hang over their content.
		clearDetailFooter()

		local fn = RENDERERS[activeTab]
		if fn then
			fn()
		end
	end

	local function switchTab(id: string)
		if not RENDERERS[id] then
			return
		end
		-- (2026-08-11: the Charms DOORWAY that lived here since 2026-08-07 --
		-- ctx.openPanel("charms"), which closed the Bag -- is gone. renderCharms
		-- mounts the embedded Codex like any other tab body now.)
		activeTab = id
		ctx.state.backpack.tab = id
		updateTabVisuals()
		renderActiveTab()
		-- CanvasPosition reset gotcha: a cached ScrollingFrame from a
		-- previous render of this same tab (or the one just built) must not
		-- carry over a stale scroll offset.
		local g = contentHost:FindFirstChildWhichIsA("ScrollingFrame")
		if g then
			g.CanvasPosition = Vector2.new(0, 0)
		end
	end

	local tabTween = game:GetService("TweenService")
	for id, tab in pairs(tabFrames) do
		local hit = tab:FindFirstChild("Hit")
		if hit then
			hit.MouseButton1Click:Connect(function()
				switchTab(id)
			end)
			-- sticker pass 2026-08-16: hover pops the GLYPH only, never the
			-- tile (rings/labels/geometry stay put). Wired once here alongside
			-- the click hookup -- this loop runs once per Build, so the
			-- connections never stack. Base size respects the active bump.
			local ic = tabIcons[id]
			if ic then
				hit.MouseEnter:Connect(function()
					local base = (id == activeTab) and TAB_ICON_ACTIVE or TAB_ICON
					local s = math.floor(base * 1.12 + 0.5)
					tabTween:Create(ic, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Size = UDim2.fromOffset(s, s) }):Play()
				end)
				hit.MouseLeave:Connect(function()
					local base = (id == activeTab) and TAB_ICON_ACTIVE or TAB_ICON
					tabTween:Create(ic, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Size = UDim2.fromOffset(base, base) }):Play()
				end)
			end
		end
	end
	updateTabVisuals()

	----------------------------------------------------------- debounced rebuild (0.25s, one pending at a time)
	local pendingRender = false
	local function scheduleRender()
		if pendingRender then
			return
		end
		pendingRender = true
		task.delay(0.25, function()
			pendingRender = false
			if wrapper.Visible then
				renderActiveTab()
			end
		end)
	end

	-- Wire the render-trigger half of the top-level capture (see
	-- `onSnapshotChanged` / applySnapshot / the DataUpdated listener at true
	-- module top-level, above BackpackPanel.Build) now that scheduleRender
	-- actually exists -- scheduleRender itself checks wrapper.Visible, so no
	-- extra wrapper closure is needed here, same as IndexPanel's
	-- onDiscoveredChanged assignment.
	onSnapshotChanged = scheduleRender

	-- (held-set Tool watchers retired 2026-08-12: equipped state comes from the
	-- snapshot now, so DataUpdated -> scheduleRender is the only refresh path.)

	----------------------------------------------------------- wiring
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)

	----------------------------------------------------------- backdrop blur (mirrors SettingsPanel's recipe)
	local BLUR_NAME = "BackpackPanelBlur"
	local function setBlur(on: boolean)
		-- centralised 2026-08-17: GameHUDClient owns the one shared HUDPanelBlur
		-- (blur-never-dim); a second per-panel BlurEffect only stacked on top
		do return end
		local existing = Lighting:FindFirstChild(BLUR_NAME)
		if on and not existing then
			local blur = Instance.new("BlurEffect")
			blur.Name = BLUR_NAME
			blur.Size = 8
			blur.Parent = Lighting
		elseif not on and existing then
			existing:Destroy()
		end
	end

	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		setBlur(wrapper.Visible)
		if not wrapper.Visible then
			-- 2026-09-18: a hidden Bag holds no live viewports and no culler
			-- connections; reopening re-renders the tab and re-attaches. A search
			-- debounce landing after close must not rebuild a hidden grid either.
			gridUi.fill = nil
			if gridUi.culler then
				gridUi.culler.detach()
				gridUi.culler = nil
			end
		end
		if wrapper.Visible then
			renderActiveTab()
			local g = contentHost:FindFirstChildWhichIsA("ScrollingFrame")
			if g then
				g.CanvasPosition = Vector2.new(0, 0) -- CanvasPosition reset gotcha
			end
		end
	end)

	-- any path that hides the HOST while this wrapper stays Visible must
	-- still kill the global BlurEffect; restore it when the host returns
	ctx.host:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ctx.host.Visible then
			setBlur(false)
		elseif wrapper.Visible then
			setBlur(true)
		end
	end)

	setBlur(wrapper.Visible) -- sync once so a pre-wired Visible state still gets its blur
	renderActiveTab() -- initial paint (zero/stale state) before the first server response lands

	return wrapper
end

----------------------------------------------------------- test hook (probes)
-- Private, non-contractual export: lets a probe call the exact same grouping
-- function this module renders from, on a fabricated inventory, without
-- needing a live player/character/UI context. Same spirit as GoalsPanel's
-- pure nextMidnightRemaining() -- kept as a plain local there since it took
-- no closure state; groupBrainrots needs infoByName/Mutations, which are
-- this module's own top-level requires, so it is exposed here instead of
-- re-derived standalone in the probe.
BackpackPanel._groupBrainrots = groupBrainrots

-- Same spirit, for the module-top-level snapshot capture (fix round 1):
-- lets a probe drive a fabricated inventory through the REAL applySnapshot
-- function (populating the real ownedBrainrots/ownedPets/petSlots upvalues)
-- before calling Build(ctx), instead of Build() only ever seeing the
-- zero/empty state Edit-mode leaves it in (no live server to answer
-- GetInitialData/push DataUpdated here).
BackpackPanel._applySnapshot = applySnapshot

return BackpackPanel
