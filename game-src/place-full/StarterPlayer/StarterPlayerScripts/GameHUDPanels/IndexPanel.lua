--!strict
-- IndexPanel: kit README §3.5 Index panel -- a GameHUDPanels consumer module
-- (StarterPlayer.StarterPlayerScripts.GameHUDPanels.IndexPanel).
--
-- Contract (same as GoalsPanel/BackpackPanel/DailyPanel/PassPanel): return
--   { Id = "index", Build = function(ctx) -> Frame }
-- Build is called ONCE lazily on first open; the shell (GameHUDClient) parents
-- the returned Frame into ctx.host and owns Visible toggling on every
-- open/close after that -- this module never sets its own Parent or drives
-- its own open/close animation.
--
-- 2026-08-04 1d/1e SWEEP RESTYLE (SUPERSEDED, see below): blue header, cream
-- body (hand-built 16px T.pad.panel padding -- NOT DailyPanel's panelWide 18,
-- because every body measurement below is computed against T.pad.panel),
-- white grid tiles / filter chips with a soft tan border and brown ink text,
-- tier-colour washes KEPT, tide chip ported to DailyPanel's dark timer-pill
-- colours, per-panel backdrop BlurEffect ("IndexPanelBlur").
--
-- STYLE REPLACEMENT (2026-08-04, Pet-Sim guide) REPLACES THE CREAM ABOVE:
-- the guide's window body is light gray (#A9A9A9), its header bar is RED
-- (#F96B57 -> #C84535 -- this panel's assigned blue is gone along with every
-- other per-panel accent), and every card / slot / row is a DARK gray slot
-- (#4A4A4A -> #363636) inside the 4px #202020 ink outline. Concretely here:
-- body surface kind "cream" -> "window" (same colours after the shared token
-- swap, honest name), header gradient -> T.gradient.header, grid tiles ->
-- kind "slot", filter chips and the 100%-reward chip -> the same dark slot
-- with the kit's own ink stroke, every ink-on-cream label back to white.
-- Note the shape of the diff: the per-file gradient/stroke OVERRIDES are
-- DELETED rather than retargeted -- T.gradient.slot/tab and UI.stroke's
-- default #202020 already carry the guide, so the tiles and chips inherit it
-- and this file no longer owns a chrome colour at all. CREAM_INK (#4a3416)
-- and CARD_BORDER (#e5d3ac) are therefore gone, not repointed.
--
-- The ONE place the guide cannot be taken literally is the silhouette: an
-- undiscovered entry renders its model pure BLACK, and black on a dark slot
-- is nothing at all. Undiscovered tiles therefore keep a near-WHITE art plate
-- inside their dark frame (SILHOUETTE_PLATE_MIX below) -- which is precisely
-- what the cream build already put on screen (tier.Color at 0.86 over a white
-- tile resolves to ~12% rarity tint on white), so the silhouette's own pixels
-- are unchanged and only its surround went dark. Discovered tiles keep their
-- tier wash verbatim; rarity/tier colour is data, and the guide never touches
-- data. ALL data wiring -- discovery, seen/NEW lifecycle, supply snapshot,
-- viewport virtualisation, filters, the RarityWord/NoPolish pair -- is
-- byte-identical to the pre-sweep version; recolor/re-surface only.
--
-- ============================================================================
-- DATA (StarterPlayer.StarterPlayerScripts.IndexClient read FULLY, live,
-- before writing anything below -- it carries TWO waves of badge work that
-- must keep working here; see task-9-report.md for the full trace). Every
-- derivation this module ports is cited against IndexClient's own line
-- numbers (live read at authoring time):
--
--   discovered (line 35, 886) -- [name]=true, replaced WHOLESALE from
--     remotes.GetInitialData / remotes.DataUpdated's `Discovered` field
--     (ServerScriptService.Modules.PlayerDataManager.Snapshot). NEVER
--     written per-key anywhere else in this module -- the ONE assignment
--     site is `discovered = snap.Discovered` in applyDiscovered below
--     (probed: "zero local mutation of discovery data").
--
--   ordered / TOTAL_COUNT (lines 57-129) -- the full roster flattened once
--     in RarityConfig order (BrainrotConfig grouped by .Rarity, iterated in
--     RarityConfig's own tier order). Ported as flattenRoster(config,
--     rarityConfig), a pure function taking both arrays as explicit
--     parameters (IndexClient closed over its module-top-level requires
--     instead) so it is independently probeable on fabricated data --
--     exposed as IndexPanel._flattenRoster (probed: "tile count == config
--     count on fabricated data"). tierTotal/tierLive (lines 62, 121-122)
--     are NOT ported: read the live script closely -- they are computed but
--     never displayed anywhere in the whole file (a pre-existing dead
--     computation), so there is nothing to preserve.
--
--   AV_LIVE/AV_SOON/AV_VAULTED + availabilityOf(name) (lines 64-83) --
--     verbatim port, including the QUEST_ONLY precedence (added in a LATER
--     wave than VAULTED/FORCE_ON -- Waves.QUEST_ONLY holds BrainrotConfig
--     QuestOnly=true names, e.g. Maxwell/Chim, live-confirmed via
--     ReplicatedStorage.Modules.BrainrotWaves). Precedence preserved exactly:
--     QUEST_ONLY > VAULTED > FORCE_ON > SupplySchedule.StatusOf.
--
--   deltaText(ts) (lines 88-96) -- verbatim port ("Xd Xh"/"Xh Xm"/"Xm",
--     workspace:GetServerTimeNow()-based, never weekday names).
--
--   orderedLive / LIVE_COUNT / refreshAvailability (lines 131-152) --
--     verbatim port, drives the new "Catchable" filter chip (IndexClient's
--     own single catchableOnly toggle, see FILTER note below).
--
--   supplySnap / refreshSupplySnap (lines 98-111) -- verbatim port. Fetched
--     lazily on open, throttled to 60s via os.clock(), via
--     remotes.GetSupplySnapshot (a RemoteFunction created at Play/live time
--     by ServerScriptService.Main -- absent in Edit-mode Studio, which is
--     why this call stays pcall-guarded exactly like IndexClient's own).
--
--   isEggSourced = e.Source == "ForestEgg" (line 686) + the badge-skip guard
--     "if avTs and not isEggSourced" (line 772) -- egg-sourced creatures
--     carry no tide state and NEVER show a tide badge, full stop, even if
--     SupplySchedule.StatusOf would otherwise return one for their rarity.
--     Preserved exactly inside ribbonFor below.
--
--   MINTED chip (lines 818-836) -- supplySnap[name] with numeric
--     minted+cap only; snapshot nil until the server answers, minted nil
--     while MintRegistry is cold -- both render nothing rather than invent
--     a count. Repositioned bottom-right per task-9-brief (was top-of-thumb
--     in IndexClient); the SOURCE CONDITION is unchanged.
--
--   tide countdown (line 668) -- "TIDE CHANGES IN " .. deltaText(
--     SupplySchedule.NextChange()) -- refreshed once per render() (open /
--     filter change / data push), NOT a running per-second ticker:
--     IndexClient itself never ticks this between renders, so this module
--     doesn't add a timer that wasn't there. Moved into the header's meta
--     slot per task-9-brief (was a standalone label in IndexClient's body).
--
-- ============================================================================
-- SPEC EXTENSIONS (task-9-brief, not present in IndexClient -- kit README
-- §3.5 + states.md "Index entry" state machine):
--   * NEW ribbon: "HIDDEN -> (discovered) NEW -> (panel opened & seen) FOUND".
--     IndexClient has no seen-tracking at all (it never distinguished a
--     freshly-discovered entry from a long-known one). This module adds a
--     client-local `seen` set (ctx.state.index.seen, this panel's own
--     sub-table -- doesn't ripple into any other panel's state shape) marked
--     wholesale from `discovered` the instant the panel CLOSES, so a name
--     discovered while the panel was shut renders NEW on the next open and
--     stops being NEW the next time the panel closes. On the very first
--     data load ever (ctx.state.index.seenSeeded), `seen` is seeded from
--     whatever is ALREADY discovered so pre-existing collections don't
--     flood the grid with NEW ribbons on this feature's rollout -- a
--     one-time migration guard, not a per-open reseed.
--   * Ribbon slot priority (ONE ribbon slot now, unlike IndexClient's two
--     independent slots -- AvailBadge top-strip + EggSourceBadge
--     bottom-left): NEW (red, kit-native RIBBON_VARIANT) > LAST CHANCE
--     (gold) > BACK IN (muted) > FOREST EGG (gold). See ribbonFor below,
--     unit-probed with 5 synthetic entries (one per state) per the brief.
--   * Filter chips: kit's own capture (captures/index.png) shows a plain
--     single-select chip row (All/Units/Vehicles/Buildings -- a different
--     game's placeholder categories). task-9-brief asks for "All / Catchable
--     + tier filters (mirror IndexClient's current filter set)" -- read
--     literally, IndexClient's *current* filter set is just the one
--     catchableOnly toggle (there are no tier filters in the live script at
--     all), so "+ tier filters" is additive, mirrored from BackpackPanel's
--     own C-R/E-L/M+ tier buckets (task-8, same RarityConfig rank table,
--     ranks 1-3/4-5/6-8) rather than invented fresh. Single-select, same as
--     BackpackPanel's tierFilter.
--   * Undiscovered tiles render NO thumbnail at all (kit: overlay + "?",
--     nothing about a silhouette) -- a deliberate divergence from
--     IndexClient's own silhouette treatment (all-black-tinted real model,
--     addThumb(..., silhouette=true)), which the kit's own reference never
--     asks for. Not rendering the shape at all is strictly MORE secretive
--     than a tinted silhouette, so this is a safe reading of "never show its
--     colours" taken one step further, not a data loss -- the model is still
--     fetched and rendered the instant the entry becomes discovered.
--   * Viewport virtualisation (IndexClient lines 494-648, own header
--     comment: "150 live ViewportFrames is not [cheap]... VIEWPORTS ARE
--     VIRTUALISED") is ported, simplified: this panel's grid is a FIXED
--     6-column, 940-wide layout (never resized), so there is no
--     recompute-columns-on-resize listener -- only fillTile/clearTile/
--     updateVisible driven by the grid's CanvasPosition, gated to known
--     (thumbnail-bearing) tiles only, since undiscovered tiles carry no
--     viewport to begin with.
-- ============================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting") -- 1d/1e sweep (2026-08-04): the backdrop BlurEffect lives in Lighting (see setBlur in Build)
local modules = ReplicatedStorage:WaitForChild("Modules")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local BrainrotConfig = require(modules:WaitForChild("BrainrotConfig"))
local RarityConfig = require(modules:WaitForChild("RarityConfig"))
local Waves = require(modules:WaitForChild("BrainrotWaves"))
local SupplySchedule = require(modules:WaitForChild("SupplySchedule"))
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))
-- WORLD TABS (2026-08-13): the Index now shows one tab per world with its own
-- catch pool. WorldProgression is the game's single per-world roster authority
-- (ThrowHandler rolls from it), so the Index enumerating it can never drift
-- from what is actually catchable where.
local WorldProgression = require(modules:WaitForChild("WorldProgression"))

-- Id is "indexInner", NOT "index": since 2026-08-07 the Index is a TAB inside the
-- Bag rather than a rail destination of its own. Nothing opens this id; the Bag
-- builds it directly. (Same arrangement as GoalsPanel/PassPanel inside
-- ProgressPanel -- the registry is keyed by Id, so a shared one would have two
-- modules silently overwrite each other.)
local IndexPanel = { Id = "indexInner" }

----------------------------------------------------------- palette (style replacement 2026-08-04, Pet-Sim guide)
-- The per-panel accent palette is GONE. The guide gives every panel the same
-- red header and the same gray window, so this module no longer owns a header
-- colour (T.gradient.header, applied in Build where Tokens is in scope), no
-- card border (UI.stroke's own #202020 ink is the guide's outline) and no body
-- ink (nothing in this panel's chrome ends up on the light window -- every
-- label here lands on a dark slot, so they are all plain white; T.color.
-- textOnWindow is deliberately unused rather than sprinkled). HEADER_TOP/
-- HEADER_BOT (blue), CREAM_INK (#4a3416) and CARD_BORDER (#e5d3ac) are deleted.
-- What survives below is what the guide has no opinion about: the silhouette
-- treatment and the tide pill.

-- SILHOUETTE INDEX (user reference video, 2026-08-04): an undiscovered entry
-- shows the REAL model rendered pure black -- shape visible, identity hidden --
-- instead of the kit's flat "?" cover. Two mechanisms together, because either
-- alone leaks (probed live at 4x on a real model):
--   1. every BasePart recoloured black  -> kills self-illuminating Neon parts,
--      which ignore scene lighting entirely (the fallback cube is Neon)
--   2. the viewport's own light switched OFF -> kills Decals/Textures/
--      SurfaceAppearance, which survive a Color change and rendered as white
--      eyes and teeth on the colour-only variant
local SILHOUETTE_INK = Color3.fromRGB(12, 10, 18)
local NO_LIGHT = Color3.new(0, 0, 0)

-- Style replacement (2026-08-04, Pet-Sim guide) SILHOUETTE CARVE-OUT: the
-- guide's tile is a dark slot, and SILHOUETTE_INK on a dark slot is invisible.
-- The undiscovered art plate stays LIGHT -- tier.Color mixed this far toward
-- white, painted near-opaque so it no longer borrows the tile behind it. The
-- mix is picked to reproduce the cream build's own effective plate (tier.Color
-- at BackgroundTransparency 0.86 over a white tile == ~12% tint on white), so
-- the silhouette reads exactly as it did before the tile went dark.
local PLATE_WHITE = Color3.new(1, 1, 1)
local SILHOUETTE_PLATE_MIX = 0.88

-- Tide pill: DailyPanel's warm #281608 was a cream-era brown and goes muddy
-- against the guide's red header -- the pill keeps its dark-pill ROLE at the
-- PS99 cool dark row navy instead (restyled 2026-08-16). The gold
-- countdown value stays: a value accent, not chrome.
local TIDE_BG = Color3.fromHex("#2A3543") -- PS99 cool: dark row navy
local TIDE_GOLD = Color3.fromHex("#ffd23e") -- DailyPanel's TIMER_GOLD countdown value

----------------------------------------------------------- availability (IndexClient lines 64-83, verbatim)
local AV_LIVE, AV_SOON, AV_VAULTED = 1, 2, 3

-- usesSupply: false for worlds whose roster is NOT on the Vault & Tide
-- rotation (WorldProgression's own UsesSupplySchedule flag -- the Tundra).
-- SupplySchedule.StatusOf answers "unreleased" for any name it does not know,
-- which would mark EVERY entry of such a world as SOON -- so those worlds
-- short-circuit to LIVE after the QUEST_ONLY/VAULTED checks, mirroring
-- RarityRoll's own treatment (WorldProgression's comment: "QUEST_ONLY and
-- VAULTED are still honoured"). Omitting the argument keeps the old
-- one-argument behaviour, so the _availabilityOf probe hook is unchanged.
local function availabilityOf(name: string, usesSupply: boolean?): (number, string?, number?)
	if Waves.QUEST_ONLY and Waves.QUEST_ONLY[name] then
		return AV_VAULTED, "quest", nil
	end
	if Waves.VAULTED and Waves.VAULTED[name] then
		return AV_VAULTED, "vaulted", nil
	end
	if usesSupply == false then
		return AV_LIVE, "live", nil
	end
	if Waves.FORCE_ON and Waves.FORCE_ON[name] then
		return AV_LIVE, (SupplySchedule.CAPPED[name] and "capped" or "live"), nil
	end
	local status, ts = SupplySchedule.StatusOf(name)
	if status == "vaulted" then
		return AV_VAULTED, status, ts
	end
	if status == "away" or status == "unreleased" then
		return AV_SOON, status, ts
	end
	return AV_LIVE, status or "live", ts
end

----------------------------------------------------------- deltaText (IndexClient lines 88-96, verbatim)
local function deltaText(ts: number): string
	local left = math.max(0, math.floor(ts - workspace:GetServerTimeNow()))
	local d = math.floor(left / 86400)
	local h = math.floor(left % 86400 / 3600)
	if d > 0 then
		return d .. "d " .. h .. "h"
	end
	local m = math.floor(left % 3600 / 60)
	if h > 0 then
		return h .. "h " .. m .. "m"
	end
	return m .. "m"
end

----------------------------------------------------------- roster flatten (IndexClient lines 57-129, ported as a pure fn)
-- Pure: takes BOTH arrays explicitly instead of closing over the module's
-- own requires, so a probe can hand it a small fabricated config + rarity
-- list and check `#result == #fabConfig` without touching the real
-- 213-entry roster (probed: "tile count == config count on fabricated
-- data"). This IS the function that produces the real `ordered` list below
-- -- not a parallel duplicate of its logic.
local function flattenRoster(config: { any }, rarityConfig: { any }): { any }
	local out = {}
	local byRarity = {}
	for _, e in ipairs(config) do
		byRarity[e.Rarity] = byRarity[e.Rarity] or {}
		table.insert(byRarity[e.Rarity], e)
	end
	for _, tier in ipairs(rarityConfig) do
		local entries = byRarity[tier.Name]
		if entries then
			for _, e in ipairs(entries) do
				out[#out + 1] = { E = e, Tier = tier }
			end
		end
	end
	return out
end

----------------------------------------------------------- per-world rosters (WORLD TABS, 2026-08-13)
-- One record per world that owns a pool (aliases like Trading/Gardens are
-- skipped -- they resolve to another world's roster and would duplicate its
-- tab). Default world first, the rest sorted by name -- the same ordering
-- convention WorldProgression's own indexRocks documents. Each record carries
-- what used to be the module-level singletons (ordered/TOTAL_COUNT/tierRank/
-- orderedLive/lastPeriodKey), per world. BrainrotConfig/RarityConfig are no
-- longer read directly here: Valley's record IS them, via WorldProgression.
local WORLD_TABS = {}
do
	local names = { WorldProgression.Default }
	local rest = {}
	for name, w in pairs(WorldProgression.Worlds) do
		if name ~= WorldProgression.Default and not w.Alias then
			rest[#rest + 1] = name
		end
	end
	table.sort(rest)
	for _, n in ipairs(rest) do
		names[#names + 1] = n
	end
	for _, name in ipairs(names) do
		local w = WorldProgression.Worlds[name]
		local ordered = flattenRoster(w.Pool, w.Rarities)
		local tierRank = {}
		for i, t in ipairs(w.Rarities) do
			tierRank[t.Name] = i
		end
		WORLD_TABS[#WORLD_TABS + 1] = {
			Id = name,
			Label = w.Label or name,
			Ordered = ordered,
			Total = #ordered,
			TierRank = tierRank,
			UsesSupply = w.UsesSupplySchedule == true,
			OrderedLive = {},
			LastPeriodKey = nil,
		}
	end
end

local function worldTab(id)
	for _, rec in ipairs(WORLD_TABS) do
		if rec.Id == id then
			return rec
		end
	end
	return WORLD_TABS[1]
end

----------------------------------------------------------- catchable-only availability (IndexClient lines 131-152, per-world since the world tabs)
-- LIVE_COUNT (Waves.Counts()) is gone with the split: it was assigned and
-- never read anywhere in this module -- the same class of dead computation
-- as IndexClient's own tierTotal/tierLive, documented in the header.
local function refreshAvailability(w)
	local key = SupplySchedule.PeriodKey() .. "#" .. Waves.OverrideKey()
	if key == w.LastPeriodKey then
		return
	end
	w.LastPeriodKey = key
	table.clear(w.OrderedLive)
	for _, rec in ipairs(w.Ordered) do
		-- A ZERO THROW WEIGHT IS NOT CATCHABLE (2026-08-23). availabilityOf answers
		-- "is this vaulted / away / live on the supply schedule", and for a world with
		-- UsesSupplySchedule = false it returns AV_LIVE for EVERY entry -- so the 23
		-- ice-fishing catches, which have Weight = 0 and can only be pulled through a
		-- fishing hole, were listed under "Catchable" beside brainrots you can actually
		-- hit with a rock. Measured: the 87 throwable tundra entries carry 800,000 of
		-- roll weight between them and the 23 fish carry 0.
		-- This is not a new rule, it is the existing one finally applied evenly.
		-- The Valley has four zero-weight entries; TWO of them (Maxwell, Pippo
		-- Olivardino) were already held out of this list by the QUEST_ONLY branch in
		-- availabilityOf, and the other two (Secret Pete, Chim) were leaking through
		-- exactly like the fish and are now correctly excluded as well -- verified
		-- against Waves.QUEST_ONLY live, not assumed.
		-- They stay in "All" and keep their own ICE FISHING ribbon -- hidden from a
		-- filter, never hidden from the index.
		local throwable = (rec.E.Weight or 0) > 0
		if throwable and availabilityOf(rec.E.Name, w.UsesSupply) == AV_LIVE then
			w.OrderedLive[#w.OrderedLive + 1] = rec
		end
	end
end
refreshAvailability(WORLD_TABS[1])

----------------------------------------------------------- ribbon priority (task-9-brief spec extension)
-- Pure. vm: { Known: boolean, JustSeen: boolean, AvStatus: string?,
-- AvTs: number?, IsEggSourced: boolean }. Returns (text, kind) or (nil, nil)
-- when no ribbon applies. `kind` selects the visual treatment the tile
-- builder uses: "new" goes through UI.ribbon's kit-native NEW=red variant;
-- the other three have no kit-defined ribbon colour (kit's own §3.5 ribbon
-- vocabulary is "NEW" only) so the tile builder hand-builds them from the
-- nearest token family per task-9-brief's colours (gold/muted/gold).
--
-- Priority, exactly per task-9-brief: NEW > LAST CHANCE > BACK IN >
-- FOREST EGG, with ICE FISHING added last (2026-08-23) on the same footing as
-- FOREST EGG: both name a source that is NOT the throw loop, which is the one
-- thing a player cannot work out from the tile itself.
-- The AvTs-and-not-IsEggSourced guard and the "retiring"/"away"
-- text are IndexClient lines 772-778, verbatim; the isEggSourced short
-- circuit is IndexClient line 686+772's "and not isEggSourced" carried
-- through so egg-sourced creatures never read a tide status at all, exactly
-- as before.
local function ribbonFor(vm): (string?, string?)
	if vm.Known and not vm.JustSeen then
		return "NEW", "new"
	end
	-- a tide status is meaningless for anything the supply schedule does not
	-- govern, so egg- and fishing-sourced entries both short-circuit it
	if vm.AvTs and not vm.IsEggSourced and not vm.IsFishSourced then
		if vm.AvStatus == "retiring" then
			return "LAST CHANCE " .. deltaText(vm.AvTs), "lastchance"
		elseif vm.AvStatus == "away" then
			return "BACK IN " .. deltaText(vm.AvTs), "backin"
		end
	end
	if vm.IsEggSourced then
		return "FOREST EGG", "forestegg"
	end
	if vm.IsFishSourced then
		return "ICE FISHING", "icefishing"
	end
	return nil, nil
end

----------------------------------------------------------- discovery data (require-time wiring, correctly outside Build)
-- `discovered` is the ONLY piece of server-confirmed state this module needs
-- before the panel has ever been opened (for the NEW-ribbon seen/seed logic
-- to have real data to seed from -- see Build below), so it alone is wired
-- at true module top-level / require time, matching GameHUDPanels' own
-- documented contract ("required at startup"). `onDiscoveredChanged` is
-- forward-declared and assigned inside Build once ctx/wrapper exist -- same
-- forward-declare-then-assign idiom GameHUDClient itself uses for
-- openPanel/closePanel (see GameHUDClient.lua "assigned below, exposed via
-- ctx"). This is deliberately NOT the same shape as BackpackPanel's own
-- "module-top-level capture race fix" comment, which describes this exact
-- pattern but (checked against the live script) actually wires its listener
-- INSIDE Build -- i.e. it only takes effect after first open regardless, the
-- same as if it had never tried. That mismatch is out of scope to fix here
-- (BackpackPanel is a different task's file); this module just implements
-- the intent correctly.
local discovered = {}
local onDiscoveredChanged: (() -> ())? = nil

local function applyDiscovered(snap)
	if typeof(snap) ~= "table" or typeof(snap.Discovered) ~= "table" then
		return
	end
	discovered = snap.Discovered -- wholesale replace ONLY -- see probe "zero local mutation of discovery data"
	if onDiscoveredChanged then
		onDiscoveredChanged()
	end
end

remotes.DataUpdated.OnClientEvent:Connect(applyDiscovered)
task.spawn(function()
	local ok, snap = pcall(function()
		return remotes.GetInitialData:InvokeServer()
	end)
	if ok then
		applyDiscovered(snap)
	end
end)

----------------------------------------------------------- Build
-- opts.embedded  built inside another panel: hides its own header and starts the
--                body at the top, so the host supplies the one header/close.
-- opts.width     render to a different width than the standalone 940. EVERY
--                measurement below derives from PANEL_W -- grid cell size, the five
--                filter chips, the discovery bar -- so a narrower panel reflows
--                rather than clipping. That is what makes the Index embeddable
--                where the Charm Codex was not (see BackpackPanel's switchTab: at
--                1120 the Codex has to stay a doorway).
function IndexPanel.Build(ctx, opts)
	local EMBEDDED = (type(opts) == "table" and opts.embedded == true)
	local WIDTH_OVERRIDE = (type(opts) == "table") and tonumber(opts.width) or nil
	local T = ctx.Tokens
	local UI = ctx.Builders

	-- STYLE REPLACEMENT REPAIR (2026-08-04): see the note in PassPanel -- the
	-- cream constants were deleted but several call sites survived, turning
	-- into nil globals that crashed Build behind openPanel's pcall (the panel
	-- just never opened). Re-declared as their guide successors:
	--   borders -> the guide's 4px #202020 outline. NOTE the tile-stroke site
	--     lerps tier.Color TOWARD this, so unknown tiles now mute toward the
	--     dark outline instead of toward tan -- which is what the guide's dark
	--     chrome wants anyway.
	--   ink     -> white, because these chips/tiles are dark slots now
	local CARD_BORDER = T.color.outline
	local CREAM_INK = T.color.white

	----------------------------------------------------------- geometry (kit README §3.5, exact where tokenised)
	local PANEL_W = WIDTH_OVERRIDE or T.size.panelWidth.index -- 940 standalone
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = EMBEDDED and 0 or (HEADER_H + 12)
	local BODY_INNER_W = PANEL_W - T.pad.panel * 2 -- 908

	local DISC_H = 48 -- kit "Discovery bar height 48"
	local CHIP100_W, CHIP100_H = 210, 48 -- kit gives no width for the 100%-reward chip; ad hoc, same class of gap other panels document
	local SECTION_GAP = T.pad.gap -- 12; kit gives no explicit gap between the discovery row / filter row / grid, reusing the general spacing-scale token (same convention GoalsPanel's TABS_TO_ROWS_GAP documents)
	local DISC_BAR_W = BODY_INNER_W - CHIP100_W - SECTION_GAP

	local FILTER_H = 44 -- kit "Filter chips height 44"
	local FILTER_GAP = 9 -- kit "gap 9"
	-- USER (2026-08-04): the initials were unreadable -- "C-R / E-L / M+" asks
	-- the player to decode a key that is nowhere on screen. Spelled out; the
	-- chips are BODY_INNER_W/5 ~= 174px wide, which fits the longest of these
	-- with room to spare. The `id`s are untouched: sourceFor() and the saved
	-- ctx.state.index.filter both key off them, so renaming ids would silently
	-- reset every player's remembered filter.
	local FILTER_DEFS = {
		{ id = "All", label = "All" },
		{ id = "Catchable", label = "Catchable" },
		{ id = "CR", label = "Common-Rare" },
		{ id = "EL", label = "Epic-Legendary" },
		{ id = "Mplus", label = "Mythic+" },
	}
	local FILTER_W = (BODY_INNER_W - FILTER_GAP * (#FILTER_DEFS - 1)) / #FILTER_DEFS

	-- WORLD TABS row height is STOLEN from the grid viewport rather than added:
	-- BODY_H must not change, because the Bag embeds this panel into a host
	-- sized for the old geometry (BackpackPanel's renderIndex) and a taller
	-- body would overflow it. The grid scrolls, so it only costs visible rows.
	local WTAB_H = 40
	local GRID_VIEWPORT_H = 392 - WTAB_H - SECTION_GAP -- kit "Viewport height 392, scroll-y" minus the world tab row
	local CELL_H = 122 -- kit "tile height 122"
	local GRID_GAP = T.pad.gridGap -- 11, kit "gap 11"
	local GRID_COLS = 6 -- kit "6 columns"
	local SLOT_W = (BODY_INNER_W - GRID_GAP * (GRID_COLS - 1)) / GRID_COLS
	local ROW_H = CELL_H + GRID_GAP

	local BODY_CONTENT_H = DISC_H + SECTION_GAP + WTAB_H + SECTION_GAP + FILTER_H + SECTION_GAP + GRID_VIEWPORT_H
	local BODY_H = T.pad.panel * 2 + BODY_CONTENT_H
	local GROUP_H = BODY_TOP + BODY_H

	local NAME_H = 22 -- kit gives only the font size (14) for the tile name, not a row height; ad hoc, documented gap
	local TILE_PAD = 6

	----------------------------------------------------------- module-local state (server-confirmed data, ephemeral UI selection)
	local activeFilter = ctx.state.index.filter or "All"
	local activeWorld = worldTab(ctx.state.index.world)
	if ctx.state.index.seen == nil then
		ctx.state.index.seen = {}
	end
	local seen = ctx.state.index.seen
	local supplySnap, supplySnapAt = nil, 0

	----------------------------------------------------------- root
	local wrapper = Instance.new("Frame")
	wrapper.Name = "IndexPanel"
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = 10

	local panelCol = Instance.new("Frame")
	panelCol.Name = "PanelColumn"
	panelCol.AnchorPoint = Vector2.new(0.5, 0.5)
	panelCol.Position = UDim2.fromScale(0.5, 0.5)
	panelCol.Size = UDim2.fromOffset(PANEL_W, GROUP_H)
	panelCol.BackgroundTransparency = 1
	panelCol.ZIndex = 10
	panelCol.Parent = wrapper

	----------------------------------------------------------- header (common shell, kit README §3 -- default gold)
	local header = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, HEADER_H), "gold", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 12
	-- Built either way and merely HIDDEN when embedded: several hundred lines below
	-- refer to `header` and its children, so skipping the build would mean auditing
	-- all of them for nil. With BODY_TOP at 0 the body simply draws over it.
	header.Visible = not EMBEDDED
	-- Style replacement (2026-08-04, Pet-Sim guide): every panel header is the
	-- guide's RED bar now -- Index's blue, Daily's purple, Pass's gold and
	-- Goals' green all collapse into T.gradient.header. Still recoloured IN
	-- PLACE off the "gold" base surface (UI.surface has no header kind), same
	-- one-line pattern as before. Shell, gloss, shadow, icon, title and close
	-- button are untouched.
	local headerGrad = header:FindFirstChildOfClass("UIGradient")
	if headerGrad then
		headerGrad.Color = T.gradient.header
	end
	UI.gloss(header, T.radius.panel)
	UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)

	local headerIcon = UI.artSlot(header, UDim2.fromOffset(T.size.headerIcon, T.size.headerIcon), T.icons.index)
	headerIcon.Name = "SectionIcon"
	headerIcon.AnchorPoint = Vector2.new(0, 0.5)
	headerIcon.Position = UDim2.new(0, 12, 0.5, 0)
	headerIcon.ZIndex = header.ZIndex + 1

	local headerTitle = UI.label(header, "Index", "panelTitle", T.color.white)
	headerTitle.Name = "Title"
	headerTitle.AnchorPoint = Vector2.new(0, 0.5)
	headerTitle.Position = UDim2.new(0, 12 + T.size.headerIcon + 14, 0.5, 0)
	headerTitle.ZIndex = header.ZIndex + 2

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.ZIndex = header.ZIndex + 2

	-- tide countdown, header meta slot (task-9-brief spec extension; geometry
	-- + colours reused from DailyPanel's own "RESETS IN" chip -- kit §3.4,
	-- the nearest kit-specified chip -- since kit §3.5 defines no header meta
	-- slot of its own for Index; same documented-gap-reuse convention other
	-- panels use for their own untokenised header add-ons).
	local TIDE_W, TIDE_H = 220, 58
	local tideChip = Instance.new("Frame")
	tideChip.Name = "TideChip"
	tideChip.AnchorPoint = Vector2.new(1, 0.5)
	tideChip.Position = UDim2.new(1, -12 - T.size.closeButton.X - 14, 0.5, 0)
	tideChip.Size = UDim2.fromOffset(TIDE_W, TIDE_H)
	-- Dark pill: solid TIDE_BG at .9 alpha plus a 2.5px white(.9) ring instead
	-- of an ink stroke. The style replacement (2026-08-04, Pet-Sim guide) keeps
	-- that ring deliberately -- it IS the guide's 1-2px #FFFFFF inner keyline,
	-- and it is the only thing separating the pill from the red bar behind it
	-- (see TIDE_BG for the brown -> neutral move). Static, never tweened.
	tideChip.BackgroundColor3 = TIDE_BG
	tideChip.BackgroundTransparency = 0.1
	tideChip.BorderSizePixel = 0
	tideChip.ZIndex = header.ZIndex + 2
	tideChip.Parent = header
	UI.corner(tideChip, T.radius.inner)
	local tideStroke = Instance.new("UIStroke")
	tideStroke.Thickness = 2.5
	tideStroke.Color = Color3.fromRGB(255, 255, 255)
	tideStroke.Transparency = 0.1
	tideStroke.Parent = tideChip

	-- caption goes white-75% (DailyPanel's timerLabel treatment) -- textMuted
	-- was a green-tinted pick that read off against the header accent; white
	-- is still right on the guide's red bar (style replacement 2026-08-04)
	local tideLabel = UI.label(tideChip, "TIDE CHANGES IN", "meta", T.color.white)
	tideLabel.Name = "TideLabel"
	tideLabel.AnchorPoint = Vector2.new(0, 0.5)
	tideLabel.Position = UDim2.new(0, 12, 0.5, -12)
	tideLabel.Size = UDim2.new(1, -24, 0, 16)
	tideLabel.AutomaticSize = Enum.AutomaticSize.None
	tideLabel.TextXAlignment = Enum.TextXAlignment.Left
	tideLabel.TextTransparency = 0.25 -- mock white-75%
	tideLabel.ZIndex = tideChip.ZIndex + 1

	local tideValue = UI.label(tideChip, "--", "cardLabel", TIDE_GOLD) -- gold countdown value, matching Daily's pill
	tideValue.Name = "TideValue"
	tideValue.AnchorPoint = Vector2.new(0, 0.5)
	tideValue.Position = UDim2.new(0, 12, 0.5, 12)
	tideValue.Size = UDim2.new(1, -24, 0, 22)
	tideValue.AutomaticSize = Enum.AutomaticSize.None
	tideValue.TextXAlignment = Enum.TextXAlignment.Left
	tideValue.ZIndex = tideChip.ZIndex + 1

	----------------------------------------------------------- body (1d/1e sweep 2026-08-04: cream, was the kit's dark UI.panel)
	-- UI.panel bundled THREE things -- the dark "panel" surface, the hard
	-- shadow, and a UIPadding of T.pad.panel on all four sides -- and ALL the
	-- body geometry above (BODY_INNER_W = PANEL_W - T.pad.panel * 2, BODY_H =
	-- T.pad.panel * 2 + BODY_CONTENT_H) is measured against that padding. The
	-- cream swap reproduces shadow + padding by hand, and the padding MUST
	-- stay T.pad.panel (16) -- NOT DailyPanel's panelWide 18 -- or
	-- DISC_BAR_W/FILTER_W/SLOT_W all silently desync. The cream body keeps
	-- the ink panel outline and carries no gloss (DailyPanel precedent).
	local body = UI.surface(panelCol, UDim2.fromOffset(PANEL_W, BODY_H), "cream", T.radius.panel, T.stroke.panel)
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, BODY_TOP)
	body.ZIndex = 12
	UI.hardShadow(body, T.shadowOffset.panel, T.radius.panel)
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, T.pad.panel)
	bodyPad.PaddingBottom = UDim.new(0, T.pad.panel)
	bodyPad.PaddingLeft = UDim.new(0, T.pad.panel)
	bodyPad.PaddingRight = UDim.new(0, T.pad.panel)
	bodyPad.Parent = body

	----------------------------------------------------------- discovery bar + 100%-reward chip
	local discRow = Instance.new("Frame")
	discRow.Name = "DiscoveryRow"
	discRow.Position = UDim2.fromOffset(0, 0)
	discRow.Size = UDim2.new(1, 0, 0, DISC_H)
	discRow.BackgroundTransparency = 1
	discRow.ZIndex = 14
	discRow.Parent = body

	local discTrack, discFill = UI.track(discRow, UDim2.fromOffset(DISC_BAR_W, DISC_H), "blue", T.radius.inner)
	discTrack.Name = "DiscoveryTrack"
	discTrack.Position = UDim2.fromOffset(0, 0)
	discTrack.ZIndex = 14

	local discLabel = Instance.new("TextLabel")
	discLabel.Name = "DiscoveryLabel"
	discLabel.BackgroundTransparency = 1
	discLabel.FontFace = T.font.display
	discLabel.TextSize = 22 -- kit §3.5 "centred label ... at 22"
	discLabel.TextColor3 = T.color.white
	discLabel.Text = "0 / 0 discovered"
	discLabel.Size = UDim2.fromScale(1, 1)
	discLabel.TextXAlignment = Enum.TextXAlignment.Center
	discLabel.TextYAlignment = Enum.TextYAlignment.Center
	discLabel.ZIndex = discTrack.ZIndex + 3
	discLabel.Parent = discTrack
	local discLabelStroke = Instance.new("UIStroke")
	discLabelStroke.Thickness = 3
	discLabelStroke.Color = T.color.outline
	discLabelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	discLabelStroke.Parent = discLabel

	-- 100%-reward chip: task-9-brief "'?' label placeholder per spec" -- there
	-- is no authored 100%-completion reward anywhere in the codebase to name
	-- or illustrate, so both the art slot and the label render the same
	-- honest "?" placeholder rather than inventing a fake reward (same
	-- honesty discipline IndexClient's own header comment states for
	-- availability/supply/price).
	local rewardChip = Instance.new("Frame")
	rewardChip.Name = "FullRewardChip"
	rewardChip.Position = UDim2.fromOffset(DISC_BAR_W + SECTION_GAP, 0)
	rewardChip.Size = UDim2.fromOffset(CHIP100_W, CHIP100_H)
	rewardChip.BackgroundColor3 = T.color.white
	rewardChip.BorderSizePixel = 0
	rewardChip.ZIndex = 14
	rewardChip.Parent = discRow
	UI.corner(rewardChip, T.radius.small)
	-- 1d/1e sweep (2026-08-04): the dark-green gradient is gone -- the chip
	-- is a white card on the cream body now (BackgroundColor3 above already
	-- IS white), bordered with the soft tan instead of ink. ONE stroke only
	-- (this replaces the old ink UI.stroke call, it doesn't stack on it).
	local rewardStroke = UI.stroke(rewardChip, 3)
	rewardStroke.Color = CARD_BORDER

	-- rewardArt keeps the Builders dark-slot placeholder look on the white
	-- chip -- it reads as the intentional empty "mystery socket" for an
	-- unauthored reward (1d/1e sweep judgment call), not a restyle miss.
	local rewardArt = UI.artSlot(rewardChip, UDim2.fromOffset(30, 30), nil)
	rewardArt.Name = "RewardArt"
	rewardArt.AnchorPoint = Vector2.new(0, 0.5)
	rewardArt.Position = UDim2.new(0, 10, 0.5, 0)
	rewardArt.ZIndex = rewardChip.ZIndex + 1

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.FontFace = T.font.ui
	rewardLabel.TextSize = 13 -- kit "Nunito 13 label"
	rewardLabel.TextColor3 = T.color.textOnLight -- PS99 cool (2026-08-16): CREAM_INK is white here and vanished on the white chip; dark ink instead
	rewardLabel.Text = "100% REWARD: ?"
	rewardLabel.Size = UDim2.new(1, -(10 + 30 + 10 + 10), 1, 0)
	rewardLabel.Position = UDim2.new(0, 10 + 30 + 10, 0, 0)
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.TextWrapped = true
	rewardLabel.ZIndex = rewardChip.ZIndex + 1
	rewardLabel.Parent = rewardChip

	----------------------------------------------------------- world tab row (WORLD TABS, 2026-08-13)
	local worldRow = Instance.new("Frame")
	worldRow.Name = "WorldRow"
	worldRow.Position = UDim2.fromOffset(0, DISC_H + SECTION_GAP)
	worldRow.Size = UDim2.new(1, 0, 0, WTAB_H)
	worldRow.BackgroundTransparency = 1
	worldRow.ZIndex = 14
	worldRow.Parent = body

	local WTAB_W = (BODY_INNER_W - FILTER_GAP * (#WORLD_TABS - 1)) / #WORLD_TABS
	local worldFrames: { [string]: Frame } = {}
	local worldRings: { [string]: Frame } = {}

	----------------------------------------------------------- filter chips
	local filterRow = Instance.new("Frame")
	filterRow.Name = "FilterRow"
	filterRow.Position = UDim2.fromOffset(0, DISC_H + SECTION_GAP + WTAB_H + SECTION_GAP)
	filterRow.Size = UDim2.new(1, 0, 0, FILTER_H)
	filterRow.BackgroundTransparency = 1
	filterRow.ZIndex = 14
	filterRow.Parent = body

	local filterFrames: { [string]: Frame } = {}
	local filterRings: { [string]: Frame } = {}

	-- =========================================================================
	-- RARITY JUICE (2026-08-10): the Index wears the same dark-card language
	-- as the Bag's juiced grid. Discovered entries earn the shine (foil from
	-- Epic, holo band for the Mythic+ family); undiscovered ones stay quiet
	-- on an opaque LIGHT silhouette plate (black-on-dark is nothing at all --
	-- see the module header). One Heartbeat drives every animated piece and
	-- prunes recycled/destroyed tiles (this grid rebuilds wholesale on every
	-- render), standing down whenever the panel is hidden or the lists empty.
	local SPEC_S = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("UIKit"):WaitForChild("SpecTheme"))
	local JX_RUN = game:GetService("RunService")
	local JX_RAINBOW = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromHex("FF2D6F")),
		ColorSequenceKeypoint.new(0.17, Color3.fromHex("FF9B2F")),
		ColorSequenceKeypoint.new(0.33, Color3.fromHex("F5F24A")),
		ColorSequenceKeypoint.new(0.50, Color3.fromHex("58F06A")),
		ColorSequenceKeypoint.new(0.67, Color3.fromHex("3FE0FF")),
		ColorSequenceKeypoint.new(0.83, Color3.fromHex("C93AFF")),
		ColorSequenceKeypoint.new(1.00, Color3.fromHex("FF2D6F")),
	})
	local JX_LEVEL_OF = { Common = "common", Uncommon = "common", Rare = "rare",
		Epic = "epic", Legendary = "legend", Mythic = "rainbow", Secret = "rainbow", God = "rainbow" }
	local JX = {
		common  = { pips = 1 },
		rare    = { pips = 2 },
		epic    = { pips = 3, foil = 0.88 },
		legend  = { pips = 4, foil = 0.82 },
		rainbow = { pips = 5, foil = 0.72, holo = true },
	}
	local jxFx = { drift = {} }
	local jxConn = nil
	local function jxStop()
		if jxConn then jxConn:Disconnect() jxConn = nil end
		table.clear(jxFx.drift)
	end
	local function jxEnsure()
		if jxConn then return end
		local clock = 0
		jxConn = JX_RUN.Heartbeat:Connect(function(dt)
			if not wrapper.Visible then jxStop() return end
			clock += dt
			local slow = (clock * 0.10) % 2 - 1
			local fast = (clock * 0.30) % 2 - 1
			for i2 = #jxFx.drift, 1, -1 do
				local e = jxFx.drift[i2]
				if not e.g.Parent then table.remove(jxFx.drift, i2)
				else e.g.Offset = Vector2.new(e.fast and fast or slow, 0) end
			end
			if #jxFx.drift == 0 then jxStop() end
		end)
	end

	local function updateWorldVisuals()
		-- same gold-active / neutral-rest treatment as the filter chips below
		for id, ring in pairs(worldRings) do
			ring.Visible = (id == activeWorld.Id)
			local chip = worldFrames[id]
			if chip then
				local on = (id == activeWorld.Id)
				local c = on and SPEC_S.Action.Go or SPEC_S.Action.Neutral -- delta 7: active = green
				chip.BackgroundColor3 = c[1]
				local g = chip:FindFirstChildOfClass("UIGradient")
				if g then g.Color = ColorSequence.new(c[1], c[2]) end
				-- pale Neutral is too light for white bubble text: dark ink +
				-- white contextual stroke at rest, white + ink stroke on the
				-- active green (label is NoPolish'd at build so this sticks)
				local label = chip:FindFirstChildOfClass("TextLabel")
				if label then
					label.TextColor3 = on and T.color.white or T.color.textOnLight
					for _, s in ipairs(label:GetChildren()) do
						if s:IsA("UIStroke") then
							s.Color = on and T.color.outline or T.color.white
						end
					end
				end
			end
		end
	end

	local function updateFilterVisuals()
		-- 2026-08-11 polish: the chips take the Bag's exact treatment -- gold
		-- active / neutral rest (they were white cards, the one chip row in the
		-- game still on the retired cream language). BackgroundColor3 moves
		-- WITH the gradient: UIGradient MULTIPLIES the background colour.
		for id, ring in pairs(filterRings) do
			ring.Visible = (id == activeFilter)
			local chip = filterFrames[id]
			if chip then
				local on = (id == activeFilter)
				local c = on and SPEC_S.Action.Go or SPEC_S.Action.Neutral -- delta 7: active = green
				chip.BackgroundColor3 = c[1]
				local g = chip:FindFirstChildOfClass("UIGradient")
				if g then g.Color = ColorSequence.new(c[1], c[2]) end
				-- pale Neutral is too light for white bubble text: dark ink +
				-- white contextual stroke at rest, white + ink stroke on the
				-- active green (label is NoPolish'd at build so this sticks)
				local label = chip:FindFirstChildOfClass("TextLabel")
				if label then
					label.TextColor3 = on and T.color.white or T.color.textOnLight
					for _, s in ipairs(label:GetChildren()) do
						if s:IsA("UIStroke") then
							s.Color = on and T.color.outline or T.color.white
						end
					end
				end
			end
		end
	end

	----------------------------------------------------------- grid viewport (scroll-y, kit "Viewport height 392")
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(0, DISC_H + SECTION_GAP + WTAB_H + SECTION_GAP + FILTER_H + SECTION_GAP)
	grid.Size = UDim2.new(1, 0, 0, GRID_VIEWPORT_H)
	-- 2026-08-10 rarity-juice: the grid IS the dark card well
	grid.BackgroundColor3 = Color3.fromHex("11151D")
	grid.BackgroundTransparency = 0
	grid.BorderSizePixel = 0
	do
		local wc = Instance.new("UICorner")
		wc.CornerRadius = UDim.new(0, 14)
		wc.Parent = grid
	end
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 5
	grid.ScrollBarImageColor3 = Color3.fromHex("#2F394A") -- 1d/1e sweep (2026-08-04): scrollThumb's sage was tuned for the dark panel; a darker sibling of the card-border tan reads right on cream
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ElasticBehavior = Enum.ElasticBehavior.Never
	grid.ZIndex = 14
	grid.Parent = body

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(SLOT_W, CELL_H)
	gridLayout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	----------------------------------------------------------- custom ribbon builder (kit only defines NEW=red; the other 3 kinds are task-9-brief spec extensions)
	local RIBBON_GRADIENT = {
		lastchance = "goldSmall",
		backin = "row", -- "muted" per task-9-brief -- PS99 cool (2026-08-16): T.gradient.row is the dark navy row family, so the ribbon's white text reads
		forestegg = "goldSmall",
		-- deliberately NOT goldSmall: gold already means "forest egg" on this grid,
		-- and the cold navy row family reads as ice while keeping white text legible
		icefishing = "row",
	}

	local function buildCustomRibbon(parent: Frame, text: string, kind: string): Frame
		local r = Instance.new("Frame")
		r.Name = "Ribbon"
		r.AutomaticSize = Enum.AutomaticSize.X
		r.Size = UDim2.fromOffset(0, 24)
		r.BackgroundColor3 = T.color.white
		r.BorderSizePixel = 0
		r.Parent = parent
		UI.corner(r, T.radius.chip)
		UI.gradient(r, T.gradient[RIBBON_GRADIENT[kind] or "tab"])
		UI.stroke(r, T.stroke.chip)

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = r

		local l = UI.label(r, text, "chip", T.color.white)
		-- RIBBON TEXT WAS TRUNCATING (fixed 2026-08-23). The frame is
		-- AutomaticSize.X, so a child sized fromScale(1, 1) made the pair circular:
		-- a scale-sized child measures as nothing, the frame collapsed to just its
		-- 10+10 padding, and the label then took 100% of THAT. Measured live on a
		-- real tile: TextBounds 50px inside a 36px label, TextTruncate = None, so
		-- "ICE FISHING" drew as "CE FISHING".
		-- This hit EVERY custom kind -- FOREST EGG and LAST CHANCE were clipping
		-- too; it only stayed invisible while the strings were short enough to
		-- almost fit. Auto-size the LABEL on X and let the frame follow it, which
		-- is the direction AutomaticSize actually measures.
		l.Size = UDim2.fromOffset(0, 24)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.TextXAlignment = Enum.TextXAlignment.Center
		return r
	end

	----------------------------------------------------------- MINTED chip (capped names, server snapshot only, bottom-right per task-9-brief)
	local function buildMintChip(tile: Frame, minted: number, cap: number)
		local chip = Instance.new("Frame")
		chip.Name = "MintChip"
		chip.AnchorPoint = Vector2.new(1, 1)
		chip.Position = UDim2.new(1, -6, 1, -6)
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.fromOffset(0, 16)
		chip.BackgroundColor3 = T.color.outline
		chip.BackgroundTransparency = 0.15
		chip.BorderSizePixel = 0
		chip.ZIndex = tile.ZIndex + 4
		chip.Parent = tile
		UI.corner(chip, 6)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.Parent = chip

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Value"
		lbl.BackgroundTransparency = 1
		lbl.FontFace = T.font.ui
		lbl.TextSize = 11
		lbl.TextColor3 = T.color.textAccentOnDark -- PS99 cool (2026-08-16): gold that reads on the dark chip over a dark tile
		lbl.Text = string.format("%d/%d MINTED", minted, cap)
		lbl.Size = UDim2.fromOffset(0, 16)
		lbl.AutomaticSize = Enum.AutomaticSize.X
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.ZIndex = chip.ZIndex + 1
		lbl.Parent = chip
	end

	----------------------------------------------------------- tile grid (virtualised viewports, IndexClient lines 494-648 simplified for a fixed 6-col layout)
	local VIS_MARGIN = 0.6
	local tiles: { any } = {} -- [i] = { holder: Frame?, name: string, live: boolean }

	local function fillTile(t)
		if t.live or not t.holder then
			return
		end
		local opts = {
			size = UDim2.fromScale(1, 1),
			position = UDim2.fromScale(0, 0),
			zIndex = t.holder.ZIndex + 1,
		}
		-- undiscovered tiles render the same master model, blacked out (see the
		-- SILHOUETTE_INK note): the virtualiser treats both states identically,
		-- so scrolling costs the same either way
		if t.silhouette then
			opts.silhouette = SILHOUETTE_INK
		end
		local vp = BrainrotThumb.add(t.holder, t.name, opts)
		if vp then
			if t.silhouette then
				vp.Ambient = NO_LIGHT
				vp.LightColor = NO_LIGHT
			end
			t.live = true
		end
	end

	local function clearTile(t)
		if not t.live then
			return
		end
		for _, c in ipairs(t.holder:GetChildren()) do
			if c:IsA("ViewportFrame") then
				c:Destroy()
			end
		end
		t.live = false
	end

	local function updateVisible()
		local viewH = grid.AbsoluteSize.Y
		if viewH <= 0 then
			return
		end
		-- Decide visibility from each tile's REAL on-screen position rather than a
		-- computed row*ROW_H window. The old row-math left every row past the first
		-- visible one blank once you scrolled (the higher rarities, which sit lower in
		-- the grid, never rendered their silhouette). Position math can't drift from
		-- the layout, and `pairs` (not ipairs) means a missing index can never cut the
		-- sweep short. fillTile/clearTile stay idempotent, so this is still cheap.
		local gridTop = grid.AbsolutePosition.Y
		local margin = viewH * VIS_MARGIN
		for _, t in pairs(tiles) do
			local h = t.holder
			if h then
				local rel = h.AbsolutePosition.Y - gridTop
				if rel < viewH + margin and rel + h.AbsoluteSize.Y > -margin then
					fillTile(t)
				else
					clearTile(t)
				end
			end
		end
	end
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(updateVisible)

	local function buildTile(parent: Instance, order: number, rec)
		local e, tier = rec.E, rec.Tier
		local known = discovered[e.Name] == true

		local tile = UI.surface(parent, UDim2.fromOffset(SLOT_W, CELL_H), "subPanel", T.radius.inner, T.stroke.control)
		tile.Name = "Tile" .. order
		tile.LayoutOrder = order
		tile.ClipsDescendants = true
		tile.ZIndex = 15
		-- 1d/1e sweep (2026-08-04): tiles are white cards with the soft tan
		-- border on the cream body -- recolor the surface's OWN gradient and
		-- stroke in place (never a second UI.stroke; the surface's children
		-- are exactly one UICorner/UIGradient/UIStroke so FindFirstChildOfClass
		-- is unambiguous). The old per-tile hardShadow is DROPPED, not just
		-- restyled: Daily's cream cards are shadowless, and tiles rebuild
		-- wholesale every render() -- the shadow churned up to ~42 extra
		-- Frames plus three property connections each per paint.
		local tileGrad = tile:FindFirstChildOfClass("UIGradient")
		if tileGrad then
			-- 2026-08-10 rarity-juice: dark card, matching the Bag's grid well
			tileGrad.Color = ColorSequence.new(Color3.fromHex("252E3D"), Color3.fromHex("171D27"))
		end
		-- SILHOUETTE INDEX: the border carries the RARITY colour (reference
		-- video) rather than the flat tan -- it is what makes a wall of unknown
		-- black shapes still readable as a rarity ladder at a glance. Unknown
		-- entries wear it muted so the discovered ones still pop.
		local tileStroke = tile:FindFirstChildOfClass("UIStroke")
		if tileStroke then
			tileStroke.Color = known and tier.Color or tier.Color:Lerp(CARD_BORDER, 0.55)
			tileStroke.Thickness = 3
		end

		local reg = { holder = nil, name = e.Name, live = false, silhouette = not known }

		do
			local artHolder = Instance.new("Frame")
			artHolder.Name = "Art"
			artHolder.Position = UDim2.fromOffset(TILE_PAD, TILE_PAD)
			artHolder.Size = UDim2.new(1, -TILE_PAD * 2, 0, CELL_H - NAME_H - TILE_PAD * 2)
			artHolder.BackgroundColor3 = tier.Color -- tier-tinted backdrop doubles as the fallback swatch when no model/off-screen (IndexClient's own "wash" convention)
			-- Discovered keeps the readable tier wash; an unknown entry's wash is
			-- pushed almost to white so the BLACK silhouette on top has maximum
			-- contrast (the reference video silhouettes sit on a dark tile and
			-- rely on near-black-on-dark; on our cream cards the same shape reads
			-- far better as ink-on-paper, which is the pokedex language anyway)
			-- on the dark card an unknown's black silhouette needs an opaque
			-- LIGHT plate; discovered keeps a translucent tier wash
			if known then
				artHolder.BackgroundTransparency = 0.55
			else
				artHolder.BackgroundColor3 = tier.Color:Lerp(Color3.new(1, 1, 1), 0.85)
				artHolder.BackgroundTransparency = 0
			end
			artHolder.BorderSizePixel = 0
			artHolder.ClipsDescendants = true
			artHolder.ZIndex = tile.ZIndex + 1
			artHolder.Parent = tile
			UI.corner(artHolder, T.radius.art)

			-- Known -> the creature's NAME. Unknown -> its RARITY word in the
			-- rarity colour (reference video): the one fact the index is willing
			-- to give away about something you have never caught, and what makes
			-- an unknown tile still worth reading.
			-- NoPolish is REQUIRED here, not decoration: the game-wide UIPolish
			-- sweep forces every unopted TextLabel to pure white, and its own
			-- header names "rarity tiers and similar colour-coded text" as the
			-- intended users of this escape hatch. Without it the rarity word
			-- rendered white (verified live) and the 1d/1e sweep's dark tile-name
			-- ink was being silently overridden too. Colours are therefore stated
			-- explicitly for both states rather than assumed:
			--   known   -> WHITE + ink stroke, which is also what the reference
			--              video does, and what reads on the tier wash
			--   unknown -> the RARITY colour, the whole point of the label
			local jxLevel = JX[JX_LEVEL_OF[tier.Name] or "common"] or JX.common
			local band = Instance.new("Frame")
			band.Name = "Band"
			band.AnchorPoint = Vector2.new(0, 1)
			band.Position = UDim2.fromScale(0, 1)
			band.Size = UDim2.new(1, 0, 0, NAME_H + TILE_PAD * 2)
			band.BorderSizePixel = 0
			band.ZIndex = tile.ZIndex + 1
			band.Parent = tile
			if known and jxLevel.holo then
				band.BackgroundColor3 = Color3.new(1, 1, 1)
				local bg2 = Instance.new("UIGradient")
				bg2.Color = JX_RAINBOW
				bg2.Parent = band
				table.insert(jxFx.drift, { g = bg2, fast = true })
				jxEnsure()
			else
				band.BackgroundColor3 = tier.Color
				band.BackgroundTransparency = known and 0.35 or 0.82
			end

			-- tier pips, top-left, same 5-level energy scale as the Bag
			local pips = Instance.new("Frame")
			pips.Name = "Pips"
			pips.Position = UDim2.fromOffset(6, 6)
			pips.Size = UDim2.fromOffset(52, 7)
			pips.BackgroundTransparency = 1
			pips.ZIndex = tile.ZIndex + 3
			pips.Parent = tile
			for i2 = 1, 5 do
				local pip = Instance.new("Frame")
				pip.Size = UDim2.fromOffset(5, 5)
				pip.Position = UDim2.fromOffset((i2 - 1) * 10, 1)
				pip.Rotation = 45
				pip.BorderSizePixel = 0
				pip.ZIndex = tile.ZIndex + 3
				pip.BackgroundColor3 = (i2 <= jxLevel.pips) and tier.Color or Color3.fromHex("39414F")
				pip.BackgroundTransparency = known and 0 or 0.45
				pip.Parent = pips
			end

			-- discovered Epic+ earns the drifting foil, under the model art
			if known and jxLevel.foil then
				local foil = Instance.new("Frame")
				foil.Name = "Foil"
				foil.Size = UDim2.fromScale(1, 1)
				foil.BackgroundColor3 = Color3.new(1, 1, 1)
				foil.BackgroundTransparency = jxLevel.foil
				foil.BorderSizePixel = 0
				foil.ZIndex = artHolder.ZIndex
				foil.Parent = artHolder
				local fg2 = Instance.new("UIGradient")
				fg2.Rotation = 25
				fg2.Color = JX_RAINBOW
				fg2.Parent = foil
				table.insert(jxFx.drift, { g = fg2, fast = false })
				jxEnsure()
			end

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = known and "Name" or "RarityWord"
			nameLbl:SetAttribute("NoPolish", true)
			nameLbl.BackgroundTransparency = 1
			nameLbl.FontFace = T.font.display
			nameLbl.TextSize = 14 -- kit "name 14"
			nameLbl.TextColor3 = known and T.color.white or tier.Color
			nameLbl.Text = known and e.Name or string.upper(tier.Name)
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.Position = UDim2.new(0, TILE_PAD, 1, -TILE_PAD - NAME_H)
			nameLbl.Size = UDim2.new(1, -TILE_PAD * 2, 0, NAME_H)
			nameLbl.TextXAlignment = Enum.TextXAlignment.Center
			nameLbl.ZIndex = tile.ZIndex + 2
			nameLbl.Parent = tile
			local nameStroke = Instance.new("UIStroke")
			nameStroke.Thickness = 2.5
			nameStroke.Color = T.color.outline
			nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			nameStroke.Parent = nameLbl

			reg.holder = artHolder
		end
		-- RETIRED 2026-08-04 (user reference video): the kit's flat "?" cover
		-- (a rgba(8,12,5,.72) overlay + a 40px "?") lived here. Undiscovered
		-- entries now render the REAL model as a black silhouette instead --
		-- the treatment the legacy IndexClient always used and the kit-faithful
		-- rebuild had deliberately dropped. Both states now share ONE art path
		-- (the `do` block above), which is why the branch is gone rather than
		-- rewritten: the only differences are the wash, the label and the
		-- silhouette flag.

		-- ribbon slot: NEW > LAST CHANCE > BACK IN > FOREST EGG (see ribbonFor)
		local _, avStatus, avTs = availabilityOf(e.Name, activeWorld.UsesSupply)
		local isEggSourced = e.Source == "ForestEgg"
		-- the ice-fishing catches were authored with Origin rather than Source
		-- (BrainrotConfigTundra); accept either so neither field name is a trap
		local isFishSourced = (e.Source == "IceFishing") or (e.Origin == "IceFishing")
		local justSeen = seen[e.Name] == true
		local rtext, rkind = ribbonFor({
			Known = known,
			JustSeen = justSeen,
			AvStatus = avStatus,
			AvTs = avTs,
			IsEggSourced = isEggSourced,
			IsFishSourced = isFishSourced,
		})
		if rtext and rkind then
			local rb
			if rkind == "new" then
				rb = UI.ribbon(tile, rtext, "NEW")
			else
				rb = buildCustomRibbon(tile, rtext, rkind)
			end
			rb.AnchorPoint = Vector2.new(0, 0)
			rb.Position = UDim2.new(0, -6, 0, -8) -- kit §3.5 "top -8 / left -6"
			rb.ZIndex = tile.ZIndex + 5
		end

		-- MINTED chip, independent of the ribbon slot (server snapshot only)
		local snapRow = supplySnap and supplySnap[e.Name]
		if snapRow and type(snapRow.minted) == "number" and type(snapRow.cap) == "number" then
			buildMintChip(tile, snapRow.minted, snapRow.cap)
		end

		tiles[order] = reg
	end

	----------------------------------------------------------- filter -> source list
	local function sourceFor(filter: string)
		local w = activeWorld
		if filter == "Catchable" then
			refreshAvailability(w)
			return w.OrderedLive
		end
		if filter == "CR" or filter == "EL" or filter == "Mplus" then
			local out = {}
			for _, rec in ipairs(w.Ordered) do
				local rank = w.TierRank[rec.Tier.Name] or 0
				local pass = (filter == "CR" and rank >= 1 and rank <= 3)
					or (filter == "EL" and rank >= 4 and rank <= 5)
					or (filter == "Mplus" and rank >= 6)
				if pass then
					out[#out + 1] = rec
				end
			end
			return out
		end
		return w.Ordered -- "All"
	end

	----------------------------------------------------------- seen/NEW bookkeeping (task-9-brief spec extension, see module header note)
	local function ensureSeenSeeded()
		if ctx.state.index.seenSeeded then
			return
		end
		ctx.state.index.seenSeeded = true
		for name, v in pairs(discovered) do
			if v then
				seen[name] = true
			end
		end
	end

	local function markAllSeen()
		for name, v in pairs(discovered) do
			if v then
				seen[name] = true
			end
		end
	end

	----------------------------------------------------------- render
	local function render()
		ensureSeenSeeded()
		refreshAvailability(activeWorld)

		for _, c in ipairs(grid:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		tiles = {}

		-- discovery bar counts the ACTIVE WORLD's roster (the bar sits above the
		-- world tabs, but per-world is the honest read: a full valley bar should
		-- not deflate the day a second world's roster ships)
		local found = 0
		for _, rec in ipairs(activeWorld.Ordered) do
			if discovered[rec.E.Name] then
				found += 1
			end
		end
		discLabel.Text = string.format("%d / %d discovered", found, activeWorld.Total)
		UI.setFill(discFill, activeWorld.Total > 0 and found / activeWorld.Total or 0, false)

		-- the tide is a Vault & Tide (valley) concept; a world off the rotation
		-- has no tide to count down to
		tideChip.Visible = activeWorld.UsesSupply
		if activeWorld.UsesSupply then
			tideValue.Text = deltaText(SupplySchedule.NextChange())
		end

		updateWorldVisuals()
		updateFilterVisuals()

		local source = sourceFor(activeFilter)
		for i, rec in ipairs(source) do
			buildTile(grid, i, rec)
		end

		grid.CanvasPosition = Vector2.new(0, 0) -- CanvasPosition reset gotcha (also done on open below)
		task.defer(updateVisible)
	end

	----------------------------------------------------------- filter chip wiring
	for i, def in ipairs(FILTER_DEFS) do
		local chip = UI.surface(filterRow, UDim2.fromOffset(FILTER_W, FILTER_H), "tab", T.radius.small, T.stroke.control)
		chip.Name = "Filter" .. def.id
		chip.Position = UDim2.fromOffset((i - 1) * (FILTER_W + FILTER_GAP), 0)
		chip.ZIndex = 14
		chip.Parent = filterRow
		-- 2026-08-11 polish: white-card chips retired -- updateFilterVisuals
		-- paints gold/neutral (the Bag's treatment) over the "tab" base at
		-- build time and on every filter change. Only the stroke stays local.
		local chipStroke = chip:FindFirstChildOfClass("UIStroke")
		if chipStroke then
			chipStroke.Color = CARD_BORDER
			chipStroke.Thickness = 3
		end

		-- kit "label 18" -- no exact token, documented gap (matches BackpackPanel precedent)
		-- 1d/1e sweep: label sits on a white chip now -> brown body ink (the
		-- cardLabel style's contextual ink text-stroke stays, Daily precedent)
		local label = UI.label(chip, def.label, "cardLabel", CREAM_INK)
		-- pale-Neutral sweep: updateFilterVisuals now flips this ink dark on
		-- the light Neutral fill. UIPolish re-asserts WHITE on every
		-- TextColor3 change of an unexempted label, so exempt it here or the
		-- flip reverts the same frame. Font/size are unchanged by the exemption
		-- (UI.label's FontFace is already FredokaOne, UIPolish's own FONT).
		label:SetAttribute("NoPolish", true)
		label.Size = UDim2.fromScale(1, 1)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = chip.ZIndex + 1

		-- kit §3.5 "active = #FFD84D ring inset -4"
		local ring = Instance.new("Frame")
		ring.Name = "ActiveRing"
		ring.Size = UDim2.new(1, 8, 1, 8)
		ring.Position = UDim2.fromOffset(-4, -4)
		ring.BackgroundTransparency = 1
		ring.Visible = false
		ring.ZIndex = chip.ZIndex + 2
		ring.Parent = chip
		UI.corner(ring, T.radius.small + 3)
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Thickness = 4
		ringStroke.Color = T.color.activeRing
		ringStroke.Parent = ring

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.ZIndex = chip.ZIndex + 3
		hit.Parent = chip
		hit.MouseButton1Click:Connect(function()
			activeFilter = def.id
			ctx.state.index.filter = def.id
			render()
		end)

		filterFrames[def.id] = chip
		filterRings[def.id] = ring
	end
	updateFilterVisuals()

	----------------------------------------------------------- world tab wiring (WORLD TABS, 2026-08-13)
	-- Deliberately the filter chips' own construction, verbatim, at WTAB_W --
	-- a second visual language for a second chip row would read as noise.
	for i, rec in ipairs(WORLD_TABS) do
		local chip = UI.surface(worldRow, UDim2.fromOffset(WTAB_W, WTAB_H), "tab", T.radius.small, T.stroke.control)
		chip.Name = "World" .. rec.Id
		chip.Position = UDim2.fromOffset((i - 1) * (WTAB_W + FILTER_GAP), 0)
		chip.ZIndex = 14
		chip.Parent = worldRow
		local chipStroke = chip:FindFirstChildOfClass("UIStroke")
		if chipStroke then
			chipStroke.Color = CARD_BORDER
			chipStroke.Thickness = 3
		end

		local label = UI.label(chip, rec.Label, "cardLabel", CREAM_INK)
		-- pale-Neutral sweep: updateWorldVisuals now flips this ink dark on
		-- the light Neutral fill. UIPolish re-asserts WHITE on every
		-- TextColor3 change of an unexempted label, so exempt it here or the
		-- flip reverts the same frame. Font/size are unchanged by the exemption
		-- (UI.label's FontFace is already FredokaOne, UIPolish's own FONT).
		label:SetAttribute("NoPolish", true)
		label.Size = UDim2.fromScale(1, 1)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = chip.ZIndex + 1

		local ring = Instance.new("Frame")
		ring.Name = "ActiveRing"
		ring.Size = UDim2.new(1, 8, 1, 8)
		ring.Position = UDim2.fromOffset(-4, -4)
		ring.BackgroundTransparency = 1
		ring.Visible = false
		ring.ZIndex = chip.ZIndex + 2
		ring.Parent = chip
		UI.corner(ring, T.radius.small + 3)
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Thickness = 4
		ringStroke.Color = T.color.activeRing
		ringStroke.Parent = ring

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.ZIndex = chip.ZIndex + 3
		hit.Parent = chip
		hit.MouseButton1Click:Connect(function()
			if activeWorld ~= rec then
				activeWorld = rec
				ctx.state.index.world = rec.Id
				render()
			end
		end)

		worldFrames[rec.Id] = chip
		worldRings[rec.Id] = ring
	end
	updateWorldVisuals()

	----------------------------------------------------------- supply snapshot (IndexClient lines 98-111, verbatim throttle)
	local function refreshSupplySnap()
		if os.clock() - supplySnapAt < 60 then
			return
		end
		supplySnapAt = os.clock()
		task.spawn(function()
			local ok, snap = pcall(function()
				return remotes.GetSupplySnapshot:InvokeServer()
			end)
			if ok and type(snap) == "table" then
				supplySnap = snap
				if wrapper.Visible then
					render() -- MINTED badges pick up the first-arrival answer without waiting for the next open
				end
			end
		end)
	end

	----------------------------------------------------------- backdrop blur (1d/1e sweep 2026-08-04: dim + blur behind the panel)
	-- The shell owns the dim scrim; the blur is per-panel, created/destroyed
	-- on Visible. The name is UNIQUE per panel (panels can transition into
	-- each other, and setBlur finds by name -- a shared name would let one
	-- panel's close destroy another's live blur). Size is SET, not tweened --
	-- BlurEffect.Size is not on the proven tween whitelist here (DailyPanel's
	-- own note; TweenService is GuiObject-only in this place).
	local BLUR_NAME = "IndexPanelBlur"
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

	----------------------------------------------------------- wiring
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)

	onDiscoveredChanged = function()
		if wrapper.Visible then
			render()
		end
	end

	-- 1d/1e sweep (2026-08-04): setBlur wired ADDITIVELY into the existing
	-- watcher -- the open-time refresh trio (refreshSupplySnap/render/
	-- CanvasPosition reset) and the close-time markAllSeen() are the panel's
	-- data contract (the NEW-ribbon lifecycle depends on markAllSeen firing
	-- on close) and survive untouched.
	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			refreshSupplySnap()
			render()
			grid.CanvasPosition = Vector2.new(0, 0) -- CanvasPosition reset gotcha
			setBlur(true)
		else
			setBlur(false)
			markAllSeen()
		end
	end)

	-- Belt-and-braces blur teardown (ported from DailyPanel's review catch):
	-- any path that hides the HOST while this wrapper stays Visible (legacy
	-- single-open force-closes, future shell changes) must still kill the
	-- global BlurEffect -- it post-processes the whole screen regardless of
	-- GUI visibility.
	ctx.host:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ctx.host.Visible then
			setBlur(false)
		elseif wrapper.Visible then
			setBlur(true)
		end
	end)

	render() -- initial paint (zero/stale state) before the first server response lands

	return wrapper
end

----------------------------------------------------------- test hooks (probes)
-- Private, non-contractual exports -- same convention BackpackPanel's
-- _groupBrainrots / GoalsPanel's nextMidnightRemaining document: lets a probe
-- call the exact functions this module renders from, on fabricated inputs,
-- without needing a live player/character/UI context.
IndexPanel._ribbonFor = ribbonFor
IndexPanel._flattenRoster = flattenRoster
IndexPanel._deltaText = deltaText
IndexPanel._availabilityOf = availabilityOf

return IndexPanel
