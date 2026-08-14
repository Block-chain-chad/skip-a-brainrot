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
--   * The kit's original "+ Slots" button and "slots" capacity concept are
--     REMOVED per the task brief's explicit spec delta (header counter is
--     "N brainrots · M/6 held", not "28/60 slots"); the kit's dashed
--     unowned-capacity placeholder tiles are dropped along with it -- there
--     is no fixed capacity to draw empty slots for.
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
local SeasonConfig = require(modules:WaitForChild("SeasonConfig")) -- Tags tab: TAGS labels
-- The Index is a TAB in this panel now, not its own rail destination. Required
-- from the sibling module rather than duplicated -- see renderIndex below.
local IndexPanel = require(script.Parent:WaitForChild("IndexPanel"))
-- 2026-08-11: the Charm Codex embeds as a real tab now (same pattern as the
-- Index) instead of the openPanel("charms") doorway that closed the Bag.
local CharmsPanel = require(script.Parent:WaitForChild("CharmsPanel"))
local PetConfigModule = modules:WaitForChild("PetConfig") -- required live, see header note

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
-- Fav joins the grouping key (2026-08-12 rework): a favorited copy is padlocked
-- against selling, and folding it into the same stack as loose copies would make
-- one padlock icon lie about half its stack. Favorited copies form their own card.
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
			local copy = { Name = e.Name, Mutation = e.Mutation, Size = e.Size, Uid = e.Uid, PadIndex = e.PadIndex, Fav = e.Fav or false }
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
	local TABS_COL_W = 64
	local DETAIL_COL_W = 224
	local CONTENT_H = BODY_H -- shell.body already carries its own padding
	local BODY_INNER_W = 1000 -- 1080 - shell pad 36 - body pad 44
	local GRID_COL_W = BODY_INNER_W - TABS_COL_W - DETAIL_COL_W - COL_GAP * 2 -- 524
	-- The WIDE tab body (grid + detail columns as one span): Index and, since
	-- 2026-08-11, the embedded Charm Codex. Declared here, not at the Index
	-- section, because renderCharms above that section closes over it.
	local INDEX_W = GRID_COL_W + COL_GAP + DETAIL_COL_W

	local TAB_H = 62 -- icon-over-label tiles now (see the PS99 sizing pass note)
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
	local PET_SLOTROW_H = 108
	local PET_SLOTROW_GAP = 12

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
		size = S.ShellFor.backpack,
		scroll = false,
		listLayout = false,
	})
	local wrapper = shell.root
	local header = shell.header
	local body = shell.body
	local shellZ = shell.z

	-- Spec delta (task-8-brief): "N brainrots . M/6 held". Tracks the title
	-- via TextBounds -- the shell title is a fixed-size frame, so its
	-- AbsoluteSize never moves; its TextBounds does.
	local counterLabel = Instance.new("TextLabel")
	counterLabel.Name = "Counter"
	counterLabel.BackgroundTransparency = 1
	counterLabel.Font = S.Font.Read
	counterLabel.TextSize = 24
	counterLabel.TextColor3 = Color3.fromHex("E4FFE9")
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
		st.Color = S.Outline
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		st.LineJoinMode = Enum.LineJoinMode.Round
		st.Parent = counterLabel
	end

	local COUNTER_GAP = 32 -- visual pass 2026-08-10: 18 sat inside the title's ink stroke
	local TITLE_LEFT = S.Chrome.HeaderPadding
	local function layoutCounter()
		counterLabel.Position = UDim2.new(0, TITLE_LEFT + shell.titleLabel.TextBounds.X + COUNTER_GAP, 0.5, 0)
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

	for i, def in ipairs(TAB_DEFS) do
		local tab = UI.surface(tabsCol, UDim2.fromOffset(TABS_COL_W, TAB_H), "tab", T.radius.inner, T.stroke.control)
		tab.Name = "Tab" .. def.id
		tab.Position = UDim2.fromOffset(0, (i - 1) * (TAB_H + TAB_GAP))
		tab.ZIndex = 14
		tab.Parent = tabsCol
		-- 2026-08-10 inner restyle: neutral spec plate on the light ground;
		-- updateTabVisuals paints the active one gold
		local tabGrad = tab:FindFirstChildOfClass("UIGradient")
		if tabGrad then tabGrad.Color = ColorSequence.new(S.Action.Neutral[1], S.Action.Neutral[2]) end
		UI.gloss(tab, T.radius.inner)
		-- tabsCol has no UIListLayout (each tab's Position is set manually
		-- above), so UI.hardShadow's sibling-parented shadow Frame is safe to
		-- add directly here -- no wrapper slot needed (see GoalsPanel/PassPanel's
		-- HardShadow-in-UIListLayout trap note; this container doesn't have it).
		UI.hardShadow(tab, T.shadowOffset.control, T.radius.inner)

		-- Slim rail tiles (PS99 sizing pass): icon on top, small label under it.
		-- Vector art where IconArt has a shape, the uploaded asset where one
		-- exists; IconArt.draw parents and sizes its own root, hence the holder.
		local icon: GuiObject
		if def.art and IconArt.has(def.art) then
			icon = Instance.new("Frame")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromOffset(28, 28)
			icon.Parent = tab
			IconArt.draw(icon, def.art, 28, tab.ZIndex + 2)
		else
			icon = UI.artSlot(tab, UDim2.fromOffset(28, 28), def.icon)
		end
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 7)
		icon.ZIndex = tab.ZIndex + 2

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Font = S.Font.Shout
		label.TextColor3 = T.color.white
		label.Text = def.label
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -4)
		label.Size = UDim2.new(1, -6, 0, 12)
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

		-- kit: "active = 4px #FFD84D INNER ring inset 0, radius 10" -- flush
		-- with the tab's own edge (unlike GoalsPanel's OUTER +8/-4 tab ring).
		local ring = Instance.new("Frame")
		ring.Name = "ActiveRing"
		ring.Size = UDim2.fromScale(1, 1)
		ring.BackgroundTransparency = 1
		ring.Visible = false
		ring.ZIndex = tab.ZIndex + 3
		ring.Parent = tab
		UI.corner(ring, 10)
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Thickness = 4
		ringStroke.Color = T.color.activeRing
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
		-- 2026-08-10 inner restyle: the detail column keeps WHITE text
		-- everywhere (three renderers write it), so it wears the spec's slate
		-- Inert ramp rather than a white row plate
		local dg = detailHost:FindFirstChildOfClass("UIGradient")
		if dg then dg.Color = ColorSequence.new(S.Action.Inert[1], S.Action.Inert[2]) end
	end
	detailHost.Name = "Detail"
	detailHost.Position = UDim2.fromOffset(TABS_COL_W + COL_GAP + GRID_COL_W + COL_GAP, 0)
	detailHost.ZIndex = 14

	local detailContent = Instance.new("Frame")
	detailContent.Name = "DetailContent"
	detailContent.Size = UDim2.fromScale(1, 1)
	detailContent.BackgroundTransparency = 1
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

		local label = UI.label(wrap, message, "buttonM", T.color.textMuted)
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
		local label = UI.label(detailContent, message, "cardLabel", T.color.textMuted)
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
		row.BackgroundColor3 = Color3.new(0, 0, 0)
		row.BackgroundTransparency = 0.7 -- rgba(0,0,0,.3)
		row.BorderSizePixel = 0
		row.ZIndex = detailContent.ZIndex + 1
		row.Parent = detailContent
		UI.corner(row, T.radius.slot)

		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 10)
		rowPad.PaddingRight = UDim.new(0, 10)
		rowPad.Parent = row

		local keyLabel = UI.label(row, key, "meta", T.color.textMuted)
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
		valueLabel.TextColor3 = T.color.white
		valueLabel.Text = value
		valueLabel.AnchorPoint = Vector2.new(1, 0.5)
		valueLabel.Position = UDim2.new(1, 0, 0.5, 0)
		valueLabel.Size = UDim2.new(0.5, 0, 1, 0)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.ZIndex = row.ZIndex + 1
		valueLabel.Parent = row
	end

	local function buildSwatch(parent: Instance, size: UDim2, position: UDim2, zIndex: number, tint: Color3)
		local sw = Instance.new("Frame")
		sw.Name = "Swatch"
		sw.Size = size
		sw.Position = position
		sw.BackgroundColor3 = tint
		sw.BackgroundTransparency = 0.5
		sw.BorderSizePixel = 0
		sw.ZIndex = zIndex
		sw.Parent = parent
		UI.corner(sw, T.radius.art)
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
	local function build3DOrSwatch(parent: Instance, name: string, size: UDim2, position: UDim2, zIndex: number, tint: Color3)
		local vp = BrainrotThumb.add(parent, name, { size = size, position = position, zIndex = zIndex, dir = BAG_ART_DIR })
		if not vp then
			local sw = Instance.new("Frame")
			sw.Name = "Swatch"
			sw.Size = size
			sw.Position = position
			sw.BackgroundColor3 = tint
			sw.BackgroundTransparency = 0.5
			sw.BorderSizePixel = 0
			sw.ZIndex = zIndex
			sw.Parent = parent
			UI.corner(sw, T.radius.art)
		end
		return vp
	end

	----------------------------------------------------------- header counter refresh
	local function refreshHeader()
		local placed = 0
		for _, e in ipairs(allBrainrots) do
			if e.PadIndex then placed += 1 end
		end
		counterLabel.Text = string.format("%d brainrots \u{00B7} %d/%d on plot", #allBrainrots, placed, plotState.Unlocked)
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
	local SORT_MODES = { "value", "rarity", "count", "az" }
	local SORT_LABEL = { value = "VALUE", rarity = "RARITY", count = "COUNT", az = "A-Z" }
	local sortMode = "value"
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
		local cardGrad = Instance.new("UIGradient")
		cardGrad.Rotation = 90
		cardGrad.Color = ColorSequence.new(Color3.fromHex("252E3D"), Color3.fromHex("171D27"))
		cardGrad.Parent = card

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
		if not level.holo then
			local bst = Instance.new("UIStroke")
			bst.Thickness = 1.6
			bst.Color = Color3.fromHex("071323")
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

	----------------------------------------------------------- hover tooltip (2026-08-12 rework)
	-- One reusable frame, PC-only (no hover on touch). Replaces the retired
	-- detail column: name, tier, income, stack size and what a click will do.
	local cardTip: Frame? = nil
	local tipName, tipMeta, tipCta
	local function ensureTip()
		if cardTip then return end
		local tip = Instance.new("Frame")
		tip.Name = "CardTip"
		tip.Size = UDim2.fromOffset(240, 92)
		tip.BackgroundColor3 = Color3.fromHex("171D27")
		tip.BorderSizePixel = 0
		tip.Visible = false
		tip.ZIndex = shellZ + 45
		tip.Parent = wrapper
		UI.corner(tip, 12)
		local st = Instance.new("UIStroke")
		st.Thickness = 3
		st.Color = S.Outline
		st.Parent = tip

		tipName = Instance.new("TextLabel")
		tipName.BackgroundTransparency = 1
		tipName.Font = S.Font.Shout
		tipName.TextSize = 17
		tipName.TextColor3 = Color3.new(1, 1, 1)
		tipName.TextXAlignment = Enum.TextXAlignment.Left
		tipName.TextTruncate = Enum.TextTruncate.AtEnd
		tipName.Position = UDim2.fromOffset(12, 8)
		tipName.Size = UDim2.new(1, -24, 0, 22)
		tipName.ZIndex = tip.ZIndex + 1
		tipName:SetAttribute("NoPolish", true)
		tipName.Parent = tip

		tipMeta = Instance.new("TextLabel")
		tipMeta.BackgroundTransparency = 1
		tipMeta.Font = S.Font.Read
		tipMeta.TextSize = 14
		tipMeta.TextColor3 = Color3.fromHex("9AA6B8")
		tipMeta.TextXAlignment = Enum.TextXAlignment.Left
		tipMeta.Position = UDim2.fromOffset(12, 34)
		tipMeta.Size = UDim2.new(1, -24, 0, 18)
		tipMeta.ZIndex = tip.ZIndex + 1
		tipMeta:SetAttribute("NoPolish", true)
		tipMeta.Parent = tip

		tipCta = Instance.new("TextLabel")
		tipCta.BackgroundTransparency = 1
		tipCta.Font = S.Font.Shout
		tipCta.TextSize = 13
		tipCta.TextXAlignment = Enum.TextXAlignment.Left
		tipCta.Position = UDim2.fromOffset(12, 60)
		tipCta.Size = UDim2.new(1, -24, 0, 18)
		tipCta.ZIndex = tip.ZIndex + 1
		tipCta:SetAttribute("NoPolish", true)
		tipCta.Parent = tip
		cardTip = tip
	end

	hideCardTip = function()
		if cardTip then cardTip.Visible = false end
	end

	showCardTip = function(group, anchor: GuiObject)
		if not game:GetService("UserInputService").MouseEnabled then return end
		ensureTip()
		local tip = cardTip :: Frame
		local tier = infoByName[group.Name] and infoByName[group.Name].Rarity or "?"
		tipName.Text = Sizes.Label(group.Mutation, group.Size, group.Name)
		tipMeta.Text = tier .. " \u{00B7} " .. shortCash(valueOf(group.Name, group.Mutation, group.Size)) .. "/s"
			.. (group.count > 1 and (" \u{00B7} x" .. group.count) or "")
			.. (group.Fav and " \u{00B7} LOCKED" or "")
		if group.PadIndex then
			tipCta.Text = "Click to take it off your plot"
			tipCta.TextColor3 = Color3.fromHex("FF6B6B")
		elseif countPlaced() < plotState.Unlocked then
			tipCta.Text = "Click to place it on your plot"
			tipCta.TextColor3 = Color3.fromHex("7CE04A")
		else
			tipCta.Text = "Plot full \u{2014} click to pick a swap"
			tipCta.TextColor3 = Color3.fromHex("FFC531")
		end
		-- anchor-relative, clamped inside the panel
		local wPos = wrapper.AbsolutePosition
		local aPos, aSize = anchor.AbsolutePosition, anchor.AbsoluteSize
		local x = (aPos.X - wPos.X) + aSize.X * 0.5 - 120
		local y = (aPos.Y - wPos.Y) - 100
		x = math.clamp(x, 8, math.max(8, wrapper.AbsoluteSize.X - 248))
		if y < 8 then y = (aPos.Y - wPos.Y) + aSize.Y + 8 end
		tip.Position = UDim2.fromOffset(x, y)
		tip.Visible = true
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
		scrim.BackgroundColor3 = T.scrim
		scrim.BackgroundTransparency = T.scrimAlpha
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
		body.TextColor3 = Color3.fromHex("55605A")
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
		local amount = UI.label(chip, shortCash(price), "value", T.color.textAccent)
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
		body.TextColor3 = Color3.fromHex("55605A")
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

		-- lowest earner gets the gold callout -- the obvious drop
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
		gridHost.ScrollBarThickness = 8
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
			opt.BackgroundColor3 = isLowest and Color3.fromHex("FFF3D1") or Color3.fromHex("F2F4FA")
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
			slot.BackgroundColor3 = Color3.fromHex("1D2A1C")
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
			inc.TextColor3 = Color3.fromHex("7CE04A")
			inc.Text = shortCash(valueOf(entry.Name, entry.Mutation, entry.Size)) .. "/s"
			inc.AnchorPoint = Vector2.new(0.5, 1)
			inc.Position = UDim2.new(0.5, 0, 1, -3)
			inc.Size = UDim2.new(1, -6, 0, 14)
			inc.ZIndex = zBase + 3
			inc:SetAttribute("NoPolish", true)
			inc.Parent = slot

			local tipGroup = { Name = entry.Name, Mutation = entry.Mutation, Size = entry.Size,
				Fav = entry.Fav, count = 1, uids = { entry.Uid }, PadIndex = entry.PadIndex }
			slot.MouseEnter:Connect(function()
				if showCardTip then showCardTip(tipGroup, slot) end
			end)
			slot.MouseLeave:Connect(function()
				if hideCardTip then hideCardTip() end
			end)
			slot.MouseButton1Click:Connect(function()
				if hideCardTip then hideCardTip() end
				remotes.StoreBrainrot:FireServer(entry.Uid)
			end)
		elseif unlocked then
			slot.BackgroundColor3 = Color3.fromHex("161C26")
			stroke.Color = Color3.fromHex("2A3242")
			local open = Instance.new("TextLabel")
			open.BackgroundTransparency = 1
			open.Font = S.Font.Read
			open.TextSize = 12
			open.Text = "OPEN"
			open.TextColor3 = Color3.fromHex("46536B")
			open.AnchorPoint = Vector2.new(0.5, 0.5)
			open.Position = UDim2.fromScale(0.5, 0.5)
			open.Size = UDim2.fromScale(1, 0.4)
			open.ZIndex = zBase + 1
			open:SetAttribute("NoPolish", true)
			open.Parent = slot
		else
			local price = plotState.Prices[spot]
			slot.BackgroundColor3 = Color3.fromHex("12161E")
			stroke.Color = isNext and T.color.activeRing or Color3.fromHex("222A38")
			stroke.Thickness = isNext and 3 or 2.5
			local lockHolder = Instance.new("Frame")
			lockHolder.BackgroundTransparency = 1
			lockHolder.AnchorPoint = Vector2.new(0.5, 0)
			lockHolder.Position = UDim2.new(0.5, 0, 0, 14)
			lockHolder.Size = UDim2.fromOffset(20, 20)
			lockHolder.ZIndex = zBase + 1
			lockHolder.Parent = slot
			buildPadlock(lockHolder, 18, isNext and T.color.activeRing or Color3.fromHex("46536B"), zBase + 1)
			local pr = Instance.new("TextLabel")
			pr.BackgroundTransparency = 1
			pr.Font = S.Font.Shout
			pr.TextSize = 12
			pr.TextColor3 = isNext and T.color.textAccent or Color3.fromHex("46536B")
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
		-- KEEP THE PLAYER'S PLACE (2026-08-13, user recording): every equip/store
		-- pushes a snapshot, which lands here as a full rebuild -- snapping the
		-- collection back to the top mid-browse, so equipping ten benched
		-- brainrots meant ten scroll-back-downs. `grid` still points at the
		-- PREVIOUS render's scroller at this point: alive means this is a
		-- re-render of a tab the player is already looking at, so its offset is
		-- carried over; destroyed (another tab rendered since, or first open)
		-- means arriving fresh, which SHOULD start at the top -- exactly the
		-- distinction the open/switch CanvasPosition resets rely on.
		local keepScroll = (grid and grid.Parent) and grid.CanvasPosition or nil
		clearChildren(contentHost)
		refreshHeader()
		hideCardTip()

		local placedByPad: { [number]: any } = {}
		local placedEntries = {}
		for _, e in ipairs(allBrainrots) do
			if e.PadIndex then
				placedByPad[e.PadIndex] = e
				placedEntries[#placedEntries + 1] = e
			end
		end
		table.sort(placedEntries, function(x, y) return (x.PadIndex or 0) < (y.PadIndex or 0) end)

		----------------------------------------------------- plot label row
		local labelRow = Instance.new("Frame")
		labelRow.Name = "PlotLabelRow"
		labelRow.Size = UDim2.new(0, BR_W, 0, LABEL_H)
		labelRow.BackgroundTransparency = 1
		labelRow.ZIndex = 14
		labelRow.Parent = contentHost

		local plotIncome = 0
		for _, e in ipairs(placedEntries) do
			plotIncome += valueOf(e.Name, e.Mutation, e.Size)
		end
		local pill = Instance.new("Frame")
		pill.Name = "IncomePill"
		pill.BackgroundColor3 = Color3.fromHex("1D2A1C")
		pill.BorderSizePixel = 0
		pill.Size = UDim2.fromOffset(200, 30)
		pill.Position = UDim2.fromOffset(0, 2)
		pill.ZIndex = 15
		pill.Parent = labelRow
		UI.corner(pill, 10)
		local pst = Instance.new("UIStroke")
		pst.Thickness = 2.5
		pst.Color = Color3.fromHex("3DDC84")
		pst.Parent = pill
		local pillText = Instance.new("TextLabel")
		pillText.BackgroundTransparency = 1
		pillText.Font = S.Font.Shout
		pillText.TextSize = 15
		pillText.TextColor3 = Color3.fromHex("7CE04A")
		pillText.Text = "PLOT INCOME  " .. shortCash(plotIncome) .. "/s"
		pillText.Size = UDim2.fromScale(1, 1)
		pillText.ZIndex = 16
		pillText:SetAttribute("NoPolish", true)
		pillText.Parent = pill

		local plotCount = Instance.new("TextLabel")
		plotCount.BackgroundTransparency = 1
		plotCount.Font = S.Font.Shout
		plotCount.TextSize = 20
		plotCount.TextColor3 = S.Surface.ReadInk
		plotCount.Text = "Your Plot  " .. #placedEntries .. "/" .. plotState.Unlocked
		plotCount.AnchorPoint = Vector2.new(1, 0)
		plotCount.Position = UDim2.new(0, BR_W, 0, 4)
		plotCount.Size = UDim2.fromOffset(200, 26)
		plotCount.TextXAlignment = Enum.TextXAlignment.Right
		plotCount.ZIndex = 15
		plotCount:SetAttribute("NoPolish", true)
		plotCount.Parent = labelRow

		-- search + sort live IN this row now (the size pass reclaimed their old row)
		local SORT_W = 108
		local sortBtn = Instance.new("TextButton")
		sortBtn.Name = "SortButton"
		sortBtn.AnchorPoint = Vector2.new(1, 0)
		sortBtn.Position = UDim2.new(0, BR_W - 200 - 8, 0, 2)
		sortBtn.Size = UDim2.fromOffset(SORT_W, 30)
		sortBtn.BackgroundColor3 = Color3.fromHex("1A2130")
		sortBtn.BorderSizePixel = 0
		sortBtn.Text = "\u{2195} " .. (SORT_LABEL[sortMode] or "VALUE")
		sortBtn.TextColor3 = Color3.new(1, 1, 1)
		sortBtn.Font = S.Font.Shout
		sortBtn.TextSize = 14
		sortBtn.AutoButtonColor = true
		sortBtn.ZIndex = 15
		sortBtn:SetAttribute("NoPolish", true)
		sortBtn.Parent = labelRow
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 10)
			c.Parent = sortBtn
			local st = Instance.new("UIStroke")
			st.Thickness = 2
			st.Color = Color3.fromHex("2C3444")
			st.Parent = sortBtn
		end

		local box = Instance.new("TextBox")
		box.Name = "SearchBox"
		box.Position = UDim2.fromOffset(208, 2)
		box.Size = UDim2.fromOffset(BR_W - 208 - 200 - 8 - SORT_W - 8 - 8, 30)
		box.BackgroundColor3 = Color3.fromHex("1A2130")
		box.BorderSizePixel = 0
		box.Text = searchQuery
		box.PlaceholderText = "Search\u{2026}"
		box.PlaceholderColor3 = Color3.fromHex("5D6878")
		box.TextColor3 = Color3.new(1, 1, 1)
		box.Font = S.Font.Read
		box.TextSize = 16
		box.ClearTextOnFocus = false
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = 15
		box:SetAttribute("NoPolish", true)
		box.Parent = labelRow
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 10)
			c.Parent = box
			local st = Instance.new("UIStroke")
			st.Thickness = 2
			st.Color = Color3.fromHex("2C3444")
			st.Parent = box
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 10)
			pad.PaddingRight = UDim.new(0, 10)
			pad.Parent = box
		end

		----------------------------------------------------- rack tray
		local tray = Instance.new("Frame")
		tray.Name = "PlotRack"
		tray.Position = UDim2.fromOffset(math.floor((BR_W - TRAY_W) / 2), LABEL_H + 8)
		tray.Size = UDim2.fromOffset(TRAY_W, TRAY_H)
		tray.BackgroundColor3 = Color3.fromHex("11151D")
		tray.BorderSizePixel = 0
		tray.ZIndex = 13
		tray.Parent = contentHost
		UI.corner(tray, 16)
		local tst = Instance.new("UIStroke")
		tst.Thickness = 2
		tst.Color = Color3.fromHex("2A3242")
		tst.Parent = tray

		for spot = 1, 16 do
			buildRackSlot(tray, spot, placedByPad[spot], 14)
		end

		----------------------------------------------------- collection well
		-- (search + sort moved up into the plot label row -- see above)
		local wellY = LABEL_H + 8 + TRAY_H + 8
		local well = Instance.new("Frame")
		well.Name = "GridWell"
		well.Position = UDim2.fromOffset(0, wellY)
		well.Size = UDim2.new(0, BR_W, 0, CONTENT_H - wellY)
		well.BackgroundColor3 = Color3.fromHex("11151D")
		well.BorderSizePixel = 0
		well.ZIndex = 13
		well.Parent = contentHost
		UI.corner(well, 16)
		local wstroke = Instance.new("UIStroke")
		wstroke.Thickness = 2
		wstroke.Color = Color3.fromHex("2A3242")
		wstroke.Parent = well

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Grid"
		scroll.Position = UDim2.fromOffset(8, 8)
		scroll.Size = UDim2.new(1, -16, 1, -16)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 8
		scroll.ScrollBarImageColor3 = Color3.fromHex("2F394A")
		scroll.CanvasSize = UDim2.new()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.ElasticBehavior = Enum.ElasticBehavior.Never
		scroll.ZIndex = 14
		scroll.Parent = well
		grid = scroll

		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 10)
		list.Parent = scroll

		local function sectionHeader(order: number, text: string, n: number, tint: Color3)
			local h = Instance.new("Frame")
			h.Name = "Header" .. order
			h.LayoutOrder = order
			h.Size = UDim2.new(1, -12, 0, 20)
			h.BackgroundTransparency = 1
			h.ZIndex = 15
			h.Parent = scroll
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(12, 12)
			dot.Position = UDim2.fromOffset(2, 4)
			dot.BackgroundColor3 = tint
			dot.BorderSizePixel = 0
			dot.ZIndex = 16
			dot.Parent = h
			UI.corner(dot, 999)
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.Font = S.Font.Shout
			lbl.TextSize = 14
			lbl.TextColor3 = tint
			lbl.Text = text .. "  (" .. n .. ")"
			lbl.Position = UDim2.fromOffset(22, 0)
			lbl.Size = UDim2.new(1, -22, 1, 0)
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.ZIndex = 16
			lbl:SetAttribute("NoPolish", true)
			lbl.Parent = h
			return h
		end

		local function sectionGrid(order: number): Frame
			local gf = Instance.new("Frame")
			gf.Name = "Section" .. order
			gf.LayoutOrder = order
			gf.Size = UDim2.new(1, -12, 0, 0)
			gf.AutomaticSize = Enum.AutomaticSize.Y
			gf.BackgroundTransparency = 1
			gf.ZIndex = 14
			gf.Parent = scroll
			local gl2 = Instance.new("UIGridLayout")
			gl2.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
			gl2.CellPadding = UDim2.fromOffset(8, 8)
			gl2.SortOrder = Enum.SortOrder.LayoutOrder
			gl2.Parent = gf
			return gf
		end

		-- fillSections rebuilds only the section contents, so live search typing
		-- never rebuilds the TextBox out from under the keyboard focus
		local function fillSections()
			for _, c in ipairs(scroll:GetChildren()) do
				if c:IsA("GuiObject") then c:Destroy() end
			end

			local q = searchQuery:lower():gsub("^%s+", ""):gsub("%s+$", "")
			local function matches(name, mutation, size)
				if q == "" then return true end
				return name:lower():find(q, 1, true) ~= nil
					or (mutation and mutation:lower():find(q, 1, true) ~= nil)
					or (size and size:lower():find(q, 1, true) ~= nil)
			end

			-- equipped section: one card per placed copy, rack order
			local shownPlaced = {}
			for _, e in ipairs(placedEntries) do
				if matches(e.Name, e.Mutation, e.Size) then
					shownPlaced[#shownPlaced + 1] = e
				end
			end
			sectionHeader(1, "ON YOUR PLOT", #shownPlaced, Color3.fromHex("7CE04A"))
			local placedGrid = sectionGrid(2)
			local placedSet = {}
			if #shownPlaced == 0 then
				local none = Instance.new("TextLabel")
				none.BackgroundTransparency = 1
				none.Font = S.Font.Read
				none.TextSize = 14
				none.TextColor3 = Color3.fromHex("5D6878")
				none.Text = #placedEntries == 0
					and "Nothing on your plot yet \u{2014} click a brainrot below, or hit EQUIP BEST."
					or "No equipped brainrot matches your search."
				none.LayoutOrder = 2
				none.Size = UDim2.new(1, -12, 0, 26)
				none.ZIndex = 15
				none:SetAttribute("NoPolish", true)
				none.Parent = scroll
				placedGrid:Destroy()
			else
				for i, e in ipairs(shownPlaced) do
					placedSet[e.Uid] = e.PadIndex
					local g = { Name = e.Name, Mutation = e.Mutation, Size = e.Size, Fav = e.Fav,
						count = 1, uids = { e.Uid }, PadIndex = e.PadIndex }
					buildJuiceTile(placedGrid, i, g, false, placedSet)
				end
			end

			-- bench section: stacked groups, current sort mode
			local groups = groupBrainrots(ownedBrainrots)
			local bench = {}
			for _, g in ipairs(groups) do
				if matches(g.Name, g.Mutation, g.Size) then
					bench[#bench + 1] = g
				end
			end
			local function rankOf(g)
				local tier = infoByName[g.Name] and infoByName[g.Name].Rarity
				return tierRank[tier] or 0
			end
			if sortMode == "rarity" then
				table.sort(bench, function(x, y)
					local rx, ry = rankOf(x), rankOf(y)
					if rx ~= ry then return rx > ry end
					return valueOf(x.Name, x.Mutation, x.Size) > valueOf(y.Name, y.Mutation, y.Size)
				end)
			elseif sortMode == "count" then
				table.sort(bench, function(x, y)
					if x.count ~= y.count then return x.count > y.count end
					return valueOf(x.Name, x.Mutation, x.Size) > valueOf(y.Name, y.Mutation, y.Size)
				end)
			elseif sortMode == "az" then
				table.sort(bench, function(x, y)
					if x.Name ~= y.Name then return x.Name < y.Name end
					return valueOf(x.Name, x.Mutation, x.Size) > valueOf(y.Name, y.Mutation, y.Size)
				end)
			end

			sectionHeader(3, "NOT EQUIPPED", #bench, Color3.fromHex("8B93A8"))
			if #bench == 0 then
				local none = Instance.new("TextLabel")
				none.BackgroundTransparency = 1
				none.Font = S.Font.Read
				none.TextSize = 14
				none.TextColor3 = Color3.fromHex("5D6878")
				none.Text = #ownedBrainrots == 0
					and "Nothing in the bag \u{2014} go skip some rocks!"
					or "No benched brainrot matches your search."
				none.LayoutOrder = 4
				none.Size = UDim2.new(1, -12, 0, 26)
				none.ZIndex = 15
				none:SetAttribute("NoPolish", true)
				none.Parent = scroll
			else
				local benchGrid = sectionGrid(4)
				for i, g in ipairs(bench) do
					buildJuiceTile(benchGrid, i, g, false, {})
				end
			end
		end

		fillSections()

		if keepScroll then
			-- AutomaticCanvasSize settles a frame after the cells land, and a
			-- restore set before that clamps to 0 -- assert after the defer, then
			-- once more a beat later so it survives the canvas resize. (Search
			-- typing and sort clicks deliberately DON'T restore: a reordered or
			-- filtered list starting at the top is what those actions mean.)
			local s = scroll
			task.defer(function()
				if s.Parent then s.CanvasPosition = keepScroll end
			end)
			task.delay(0.06, function()
				if s.Parent then s.CanvasPosition = keepScroll end
			end)
		end

		box:GetPropertyChangedSignal("Text"):Connect(function()
			searchQuery = box.Text
			fillSections()
		end)
		sortBtn.MouseButton1Click:Connect(function()
			for i, mode in ipairs(SORT_MODES) do
				if mode == sortMode then
					sortMode = SORT_MODES[(i % #SORT_MODES) + 1]
					break
				end
			end
			sortBtn.Text = "\u{2195} " .. (SORT_LABEL[sortMode] or "VALUE")
			fillSections()
		end)
	end

	----------------------------------------------------------- PETS tab
	local function renderPetDetail(pet, def)
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
		hero.BackgroundColor3 = Color3.fromHex("252E3D")
		hero.BorderSizePixel = 0
		hero.ZIndex = detailContent.ZIndex + 1
		hero.Parent = detailContent
		UI.corner(hero, T.radius.small) -- kit "hero art ... radius 12"
		-- dark card + rarity edge, matching the grid tiles below it
		UI.gradient(hero, ColorSequence.new(Color3.fromHex("252E3D"), Color3.fromHex("171D27")))
		local heroStroke = UI.stroke(hero, T.stroke.control)
		if heroStroke then heroStroke.Color = heroRamp[2] end
		-- BUG (fixed 2026-08-11): this called build3DOrSwatch(def.Name) -- the
		-- BRAINROT lookup, which misses on BOTH folder and key for the 15-pet
		-- roster (see build3DPetOrSwatch's own header) and fell through to a flat
		-- swatch. The pet detail hero has been a blank tan box since pets shipped;
		-- only the ten retired brainrot stand-ins ever rendered here.
		build3DPetOrSwatch(hero, def, UDim2.new(1, -12, 1, -12), UDim2.fromOffset(6, 6), hero.ZIndex + 1, rarityTint(T, def.Rarity))

		local name = UI.label(detailContent, def.Name, "cardLabel", T.color.white)
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
		UI.gradient(chip, T.gradient.row)
		UI.stroke(chip, T.stroke.hairline)
		local chipLabel = UI.label(chip, def.Rarity:upper(), "chip", rarityTint(T, def.Rarity))
		chipLabel.Size = UDim2.fromScale(1, 1)
		chipLabel.AutomaticSize = Enum.AutomaticSize.None
		chipLabel.TextXAlignment = Enum.TextXAlignment.Center
		chipLabel.ZIndex = chip.ZIndex + 1

		local luck, income = PetConfig.BoostsFor(pet.Id)
		buildStatRow(4, "LUCK", trimNum(luck) .. "x")
		buildStatRow(5, "MONEY", trimNum(income) .. "x")

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
		-- FIX F1: same EquipSlot wrapper as renderBrainrotDetail's EquipButton
		-- above -- detailContent is UIListLayout-managed; see that comment for
		-- why the raw UI.button(detailContent, ...) call used to strand a
		-- phantom HardShadow list item.
		local equipSlot = Instance.new("Frame")
		equipSlot.Name = "EquipSlot"
		equipSlot.LayoutOrder = 6
		equipSlot.Size = UDim2.new(1, 0, 0, 56)
		equipSlot.BackgroundTransparency = 1
		equipSlot.ZIndex = detailContent.ZIndex + 1
		equipSlot.Parent = detailContent

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
	end

	local function findPet(uid)
		for _, p in ipairs(ownedPets) do
			if p.Uid == uid then
				return p
			end
		end
		return nil
	end

	-- PET TILES ARE JUICED CARDS (2026-08-11, user: "make the pet card art look
	-- better"). The brainrot grid's language -- dark card, rarity outline, pips,
	-- bottom band -- with three deliberate differences, each A/B'd on screen
	-- against the old white plate before any of it was written:
	--
	--   * SOFTER FX. foil 0.92/0.88/0.84 and aura 0.5, well above the brainrot
	--     tiles' 0.87/0.80/0.70 and 0.35. At tile size those numbers buried the
	--     model under a colour wash and read WORSE than the plain plate did --
	--     the top two tiers were the whole reason to look again.
	--   * The band carries the PET'S NAME, not its tier. A pet is an individual,
	--     and its tier is already the outline, the pips and the band's colour;
	--     the old tile named the pet nowhere at all.
	--   * A LUCK PILL instead of the brainrots' xN count -- pet records are
	--     unique (no stacking), and the multiplier is what you choose one by.
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
		local cardGrad = Instance.new("UIGradient")
		cardGrad.Rotation = 90
		cardGrad.Color = ColorSequence.new(Color3.fromHex("252E3D"), Color3.fromHex("171D27"))
		cardGrad.Parent = card

		if level.aura then
			local aura = Instance.new("Frame")
			aura.Name = "Aura"
			aura.AnchorPoint = Vector2.new(0, 1)
			aura.Position = UDim2.new(0, 0, 1, -PET_BAND_H)
			aura.Size = UDim2.new(1, 0, 0.42, 0)
			aura.BackgroundColor3 = ramp[2]
			aura.BorderSizePixel = 0
			aura.ZIndex = 15
			aura.Parent = card
			local ag = Instance.new("UIGradient")
			ag.Rotation = -90
			ag.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			})
			ag.Parent = aura
			table.insert(fx.pulseBg, { f = aura, lo = 0.4, hi = 0.72 })
		end

		if level.foil then
			local foil = Instance.new("Frame")
			foil.Name = "Foil"
			foil.Size = UDim2.new(1, 0, 1, -PET_BAND_H)
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
		pill.Size = UDim2.fromOffset(38, 18)
		pill.BackgroundColor3 = Color3.fromHex("0E1420")
		pill.BackgroundTransparency = 0.15
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
		pl.TextSize = 12
		pl.Text = trimNum(luck) .. "x"
		pl.TextColor3 = ramp[1]
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
		if level.holo then
			band.BackgroundColor3 = Color3.new(1, 1, 1)
			local bg = Instance.new("UIGradient")
			bg.Color = RAINBOW
			bg.Parent = band
			table.insert(fx.drift, { g = bg, fast = true })
		else
			band.BackgroundColor3 = ramp[2]
			band.BackgroundTransparency = 0.25
		end
		local bname = Instance.new("TextLabel")
		bname.Name = "PetName"
		bname.BackgroundTransparency = 1
		bname.Font = S.Font.Shout
		bname.TextSize = 15
		bname.TextTruncate = Enum.TextTruncate.AtEnd
		bname.TextColor3 = level.holo and Color3.fromHex("12060C") or Color3.new(1, 1, 1)
		bname.Text = string.upper(def.Name or "?")
		bname.TextXAlignment = Enum.TextXAlignment.Center
		bname.Position = UDim2.fromOffset(5, 0)
		bname.Size = UDim2.new(1, -10, 1, 0)
		bname.ZIndex = 19
		bname:SetAttribute("NoPolish", true)
		bname.Parent = band
		if not level.holo then
			local bst = Instance.new("UIStroke")
			bst.Thickness = 1.6
			bst.Color = Color3.fromHex("071323")
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
		hit.MouseEnter:Connect(function()
			cell.ZIndex = 30
			game:GetService("TweenService"):Create(card, PET_HOVER, { Size = UDim2.new(1, 8, 1, 8) }):Play()
		end)
		hit.MouseLeave:Connect(function()
			cell.ZIndex = 15
			game:GetService("TweenService"):Create(card, PET_HOVER, { Size = UDim2.fromScale(1, 1) }):Play()
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
		-- the Codex's 108-tall cards. Five cards: 3 free, slots 4-5 ride the
		-- pet-slots gamepass. The REAL cap comes from the server ("PetSlotCap"
		-- attribute, PetHandler.publishLoadout); the client cannot ask
		-- MarketplaceService about pass ownership itself, and falling back to
		-- SLOTS_FREE just draws 4-5 locked until it lands.
		-- AN OCCUPIED CARD IS A BUTTON: click = unequip that pet (the recording
		-- showed the user clicking the cards and nothing answering -- and with
		-- every slot full there was no visible road to a different loadout).
		-- Rebuilt on every render: petSlots and the cap both arrive via
		-- DataUpdated -> scheduleRender, so the row can never show stale slots.
		local petCap = tonumber(player:GetAttribute("PetSlotCap")) or PetConfig.SLOTS_FREE
		local totalSlots = math.max(PetConfig.SLOTS_PREMIUM, petCap)
		local petsByUid = {}
		for _, p in ipairs(ownedPets) do petsByUid[p.Uid] = p end

		local slotRow = Instance.new("Frame")
		slotRow.Name = "PetSlotRow"
		slotRow.Size = UDim2.fromOffset(INDEX_W, PET_SLOTROW_H)
		slotRow.BackgroundTransparency = 1
		slotRow.ZIndex = 14
		slotRow.Parent = contentHost

		local slotCardGap = 12
		local slotCardW = math.floor((INDEX_W - slotCardGap * (totalSlots - 1)) / totalSlots)
		for i = 1, totalSlots do
			local slotLocked = i > petCap
			local occupant = petSlots[i] and petsByUid[petSlots[i]]
			local occDef = occupant and PetConfig.Pets[occupant.Id]
			-- same card language as the Codex's slot row: white spec card when
			-- usable, dark Inert slab when gamepass-locked
			local card = PC.plate({
				name = "PetSlot" .. i,
				size = UDim2.fromOffset(slotCardW, PET_SLOTROW_H),
				position = UDim2.fromOffset((i - 1) * (slotCardW + slotCardGap), 0),
				colors = if slotLocked
					then { Color3.fromHex("4A4030"), Color3.fromHex("302A1F") } -- LemonPop warm dark (was slate 2A3B4F/1D2C3E)
					else { S.Surface.RowTop, S.Surface.RowBottom },
				radius = 16,
				outline = 5,
				zIndex = 15,
				parent = slotRow,
				gloss = false,
			})
			PC.read({
				name = "Eyebrow", text = ("SLOT %02d"):format(i), size = 14,
				color = if slotLocked then Color3.fromHex("A79A7C") else S.Surface.ReadSub, -- LemonPop disabled taupe (was slate 8FA2B6)
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
				local artPlate = PC.plate({
					name = "ArtPlate",
					size = UDim2.fromOffset(56, 56),
					position = UDim2.fromOffset(12, 30),
					colors = { Color3.fromHex("2A3446"), Color3.fromHex("151B24") },
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
				local occLabel = PC.read({
					name = "Occupant",
					text = if slotLocked then "Locked" else "Empty",
					size = 22,
					color = if slotLocked then Color3.fromHex("C3CEDA") else S.Surface.ReadSub,
					frameSize = UDim2.new(1, -24, 0, 26),
					position = UDim2.new(0, 12, 0, 34),
					zIndex = 16, parent = card,
				})
				occLabel.TextScaled = true
				local occFit = Instance.new("UITextSizeConstraint")
				occFit.MaxTextSize = 22
				occFit.MinTextSize = 10
				occFit.Parent = occLabel
				local caption = PC.read({
					name = "Caption",
					text = if slotLocked then "GAMEPASS \u{00B7} +2 SLOTS" else "EQUIP A PET BELOW",
					size = 12,
					color = if slotLocked then Color3.fromHex("FFC53D") else S.Surface.ReadSub,
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
			end
		end

		-- Dark card well, same as the brainrot grid: the juiced pet cards are dark
		-- now and floated oddly straight on the light body.
		local petWell = Instance.new("Frame")
		petWell.Name = "PetWell"
		petWell.Position = UDim2.fromOffset(0, PET_SLOTROW_H + PET_SLOTROW_GAP)
		petWell.Size = UDim2.fromOffset(GRID_COL_W, CONTENT_H - PET_SLOTROW_H - PET_SLOTROW_GAP)
		petWell.BackgroundColor3 = Color3.fromHex("11151D")
		petWell.BorderSizePixel = 0
		petWell.ZIndex = 13
		petWell.Parent = contentHost
		UI.corner(petWell, 16)
		local pwStroke = Instance.new("UIStroke")
		pwStroke.Thickness = 2
		pwStroke.Color = Color3.fromHex("2A3242")
		pwStroke.Parent = petWell

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "PetGrid"
		scroll.Position = UDim2.fromOffset(PET_WELL_PAD, PET_WELL_PAD)
		scroll.Size = UDim2.new(1, -PET_WELL_PAD * 2, 1, -PET_WELL_PAD * 2)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		scroll.ScrollBarThickness = 8
		scroll.ScrollBarImageColor3 = Color3.fromHex("2F394A")
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
	local charmsFrame = nil
	renderCharms = function()
		if charmsFrame then
			local okDetach = pcall(function() charmsFrame.Parent = nil end)
			if not okDetach then charmsFrame = nil end
		end
		clearChildren(contentHost)
		refreshHeader()
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
				tint = T.color.textAccent,
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
		UI.gradient(holder, ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("FFF4D9"))) -- LemonPop slot family (was slate F2F7FC/DCE6F0)

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
		caption.TextColor3 = T.color.white
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
		capStroke.Color = T.color.outline
		capStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		capStroke.Parent = caption

		if def.qty then
			local qty = Instance.new("TextLabel")
			qty.Name = "Quantity"
			qty.BackgroundTransparency = 1
			qty.Font = S.Font.Shout
			qty:SetAttribute("NoPolish", true)
			qty.TextSize = 20
			qty.TextColor3 = T.color.white
			qty.Text = "x" .. tostring(def.qty)
			qty.AnchorPoint = Vector2.new(1, 0)
			qty.Position = UDim2.new(1, -6, 0, 4)
			qty.Size = UDim2.fromOffset(40, 20)
			qty.TextXAlignment = Enum.TextXAlignment.Right
			qty.ZIndex = tile.ZIndex + 3
			qty.Parent = tile
			local qtyStroke = Instance.new("UIStroke")
			qtyStroke.Thickness = 2.5
			qtyStroke.Color = T.color.outline
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

		local name = UI.label(detailContent, def.name, "cardLabel", T.color.white)
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

		local status = UI.label(detailContent, def.status, "meta", T.color.claimRing)
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
				colors = worn and S.Action.Gold or { S.Surface.RowTop, S.Surface.RowBottom },
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
				worn and "green" or "gold", UDim2.fromOffset(110, 38), "buttonM")
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
		-- sheet: selected = gold, unselected = neutral; the ring retires.
		-- BackgroundColor3 moves WITH the gradient (2026-08-11): UIGradient
		-- MULTIPLIES the background, so gold-gradient-over-neutral-base was
		-- rendering the selected tab olive.
		for id, ring in pairs(tabRings) do
			ring.Visible = false
			local tabF = tabFrames[id]
			local g = tabF and tabF:FindFirstChildOfClass("UIGradient")
			local c = (id == activeTab) and S.Action.Gold or S.Action.Neutral
			tabF.BackgroundColor3 = c[1]
			if g then g.Color = ColorSequence.new(c[1], c[2]) end
			tabF.ZIndex = (id == activeTab) and 15 or 14
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
			detailHost.Position = UDim2.fromOffset(TABS_COL_W + COL_GAP + GRID_COL_W + COL_GAP, PET_SLOTROW_H + PET_SLOTROW_GAP)
			detailHost.Size = UDim2.fromOffset(DETAIL_COL_W, CONTENT_H - PET_SLOTROW_H - PET_SLOTROW_GAP)
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

	for id, tab in pairs(tabFrames) do
		local hit = tab:FindFirstChild("Hit")
		if hit then
			hit.MouseButton1Click:Connect(function()
				switchTab(id)
			end)
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

	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			renderActiveTab()
			local g = contentHost:FindFirstChildWhichIsA("ScrollingFrame")
			if g then
				g.CanvasPosition = Vector2.new(0, 0) -- CanvasPosition reset gotcha
			end
		end
	end)

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
