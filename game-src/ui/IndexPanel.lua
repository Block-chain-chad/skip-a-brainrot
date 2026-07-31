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
-- ============================================================================
-- DATA (StarterPlayer.StarterPlayerScripts.IndexClient read FULLY, live,
-- before writing anything below -- it carries TWO waves of badge work that
-- must keep working here; see task-9-report.md for the full trace). Every
-- derivation this module ports is cited against IndexClient's own line
-- numbers (live read at authoring time):
--
--   discovered (line 35, 808) -- [name]=true, replaced WHOLESALE from
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
local modules = ReplicatedStorage:WaitForChild("Modules")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local BrainrotConfig = require(modules:WaitForChild("BrainrotConfig"))
local RarityConfig = require(modules:WaitForChild("RarityConfig"))
local Waves = require(modules:WaitForChild("BrainrotWaves"))
local SupplySchedule = require(modules:WaitForChild("SupplySchedule"))
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))

local IndexPanel = { Id = "index" }

----------------------------------------------------------- availability (IndexClient lines 64-83, verbatim)
local AV_LIVE, AV_SOON, AV_VAULTED = 1, 2, 3

local function availabilityOf(name: string): (number, string?, number?)
	if Waves.QUEST_ONLY and Waves.QUEST_ONLY[name] then
		return AV_VAULTED, "quest", nil
	end
	if Waves.VAULTED and Waves.VAULTED[name] then
		return AV_VAULTED, "vaulted", nil
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

local ordered = flattenRoster(BrainrotConfig, RarityConfig)
local TOTAL_COUNT = #ordered

local tierRank = {}
for i, t in ipairs(RarityConfig) do
	tierRank[t.Name] = i
end

----------------------------------------------------------- catchable-only availability (IndexClient lines 131-152, verbatim)
local orderedLive = {}
local LIVE_COUNT = 0
local lastPeriodKey = nil
local function refreshAvailability()
	local key = SupplySchedule.PeriodKey() .. "#" .. Waves.OverrideKey()
	if key == lastPeriodKey then
		return
	end
	lastPeriodKey = key
	table.clear(orderedLive)
	for _, rec in ipairs(ordered) do
		if availabilityOf(rec.E.Name) == AV_LIVE then
			orderedLive[#orderedLive + 1] = rec
		end
	end
	LIVE_COUNT = Waves.Counts()
end
refreshAvailability()

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
-- FOREST EGG. The AvTs-and-not-IsEggSourced guard and the "retiring"/"away"
-- text are IndexClient lines 772-778, verbatim; the isEggSourced short
-- circuit is IndexClient line 686+772's "and not isEggSourced" carried
-- through so egg-sourced creatures never read a tide status at all, exactly
-- as before.
local function ribbonFor(vm): (string?, string?)
	if vm.Known and not vm.JustSeen then
		return "NEW", "new"
	end
	if vm.AvTs and not vm.IsEggSourced then
		if vm.AvStatus == "retiring" then
			return "LAST CHANCE " .. deltaText(vm.AvTs), "lastchance"
		elseif vm.AvStatus == "away" then
			return "BACK IN " .. deltaText(vm.AvTs), "backin"
		end
	end
	if vm.IsEggSourced then
		return "FOREST EGG", "forestegg"
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
function IndexPanel.Build(ctx)
	local T = ctx.Tokens
	local UI = ctx.Builders

	----------------------------------------------------------- geometry (kit README §3.5, exact where tokenised)
	local PANEL_W = T.size.panelWidth.index -- 940
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = HEADER_H + 12
	local BODY_INNER_W = PANEL_W - T.pad.panel * 2 -- 908

	local DISC_H = 48 -- kit "Discovery bar height 48"
	local CHIP100_W, CHIP100_H = 210, 48 -- kit gives no width for the 100%-reward chip; ad hoc, same class of gap other panels document
	local SECTION_GAP = T.pad.gap -- 12; kit gives no explicit gap between the discovery row / filter row / grid, reusing the general spacing-scale token (same convention GoalsPanel's TABS_TO_ROWS_GAP documents)
	local DISC_BAR_W = BODY_INNER_W - CHIP100_W - SECTION_GAP

	local FILTER_H = 44 -- kit "Filter chips height 44"
	local FILTER_GAP = 9 -- kit "gap 9"
	local FILTER_DEFS = {
		{ id = "All", label = "All" },
		{ id = "Catchable", label = "Catchable" },
		{ id = "CR", label = "C-R" },
		{ id = "EL", label = "E-L" },
		{ id = "Mplus", label = "M+" },
	}
	local FILTER_W = (BODY_INNER_W - FILTER_GAP * (#FILTER_DEFS - 1)) / #FILTER_DEFS

	local GRID_VIEWPORT_H = 392 -- kit "Viewport height 392, scroll-y"
	local CELL_H = 122 -- kit "tile height 122"
	local GRID_GAP = T.pad.gridGap -- 11, kit "gap 11"
	local GRID_COLS = 6 -- kit "6 columns"
	local SLOT_W = (BODY_INNER_W - GRID_GAP * (GRID_COLS - 1)) / GRID_COLS
	local ROW_H = CELL_H + GRID_GAP

	local BODY_CONTENT_H = DISC_H + SECTION_GAP + FILTER_H + SECTION_GAP + GRID_VIEWPORT_H
	local BODY_H = T.pad.panel * 2 + BODY_CONTENT_H
	local GROUP_H = BODY_TOP + BODY_H

	local NAME_H = 22 -- kit gives only the font size (14) for the tile name, not a row height; ad hoc, documented gap
	local TILE_PAD = 6

	----------------------------------------------------------- module-local state (server-confirmed data, ephemeral UI selection)
	local activeFilter = ctx.state.index.filter or "All"
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
	tideChip.BackgroundColor3 = T.color.white
	tideChip.BorderSizePixel = 0
	tideChip.ZIndex = header.ZIndex + 2
	tideChip.Parent = header
	UI.corner(tideChip, T.radius.inner)
	local tideGradient = Instance.new("UIGradient")
	tideGradient.Rotation = 90
	tideGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, T.hex("#3B4731")),
		ColorSequenceKeypoint.new(1, T.hex("#26301F")),
	})
	tideGradient.Parent = tideChip
	UI.stroke(tideChip, T.stroke.control)

	local tideLabel = UI.label(tideChip, "TIDE CHANGES IN", "meta", T.color.textMuted)
	tideLabel.Name = "TideLabel"
	tideLabel.AnchorPoint = Vector2.new(0, 0.5)
	tideLabel.Position = UDim2.new(0, 12, 0.5, -12)
	tideLabel.Size = UDim2.new(1, -24, 0, 16)
	tideLabel.AutomaticSize = Enum.AutomaticSize.None
	tideLabel.TextXAlignment = Enum.TextXAlignment.Left
	tideLabel.ZIndex = tideChip.ZIndex + 1

	local tideValue = UI.label(tideChip, "--", "cardLabel", T.color.white)
	tideValue.Name = "TideValue"
	tideValue.AnchorPoint = Vector2.new(0, 0.5)
	tideValue.Position = UDim2.new(0, 12, 0.5, 12)
	tideValue.Size = UDim2.new(1, -24, 0, 22)
	tideValue.AutomaticSize = Enum.AutomaticSize.None
	tideValue.TextXAlignment = Enum.TextXAlignment.Left
	tideValue.ZIndex = tideChip.ZIndex + 1

	----------------------------------------------------------- body (common shell, kit README §3)
	local body = UI.panel(panelCol, UDim2.fromOffset(PANEL_W, BODY_H))
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, BODY_TOP)
	body.ZIndex = 12

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
	local rewardGradient = Instance.new("UIGradient")
	rewardGradient.Rotation = 90
	rewardGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, T.hex("#3B4731")),
		ColorSequenceKeypoint.new(1, T.hex("#26301F")),
	})
	rewardGradient.Parent = rewardChip
	UI.stroke(rewardChip, T.stroke.control)

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
	rewardLabel.TextColor3 = T.color.textAccent
	rewardLabel.Text = "100% REWARD: ?"
	rewardLabel.Size = UDim2.new(1, -(10 + 30 + 10 + 10), 1, 0)
	rewardLabel.Position = UDim2.new(0, 10 + 30 + 10, 0, 0)
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.TextWrapped = true
	rewardLabel.ZIndex = rewardChip.ZIndex + 1
	rewardLabel.Parent = rewardChip

	----------------------------------------------------------- filter chips
	local filterRow = Instance.new("Frame")
	filterRow.Name = "FilterRow"
	filterRow.Position = UDim2.fromOffset(0, DISC_H + SECTION_GAP)
	filterRow.Size = UDim2.new(1, 0, 0, FILTER_H)
	filterRow.BackgroundTransparency = 1
	filterRow.ZIndex = 14
	filterRow.Parent = body

	local filterFrames: { [string]: Frame } = {}
	local filterRings: { [string]: Frame } = {}

	local function updateFilterVisuals()
		for id, ring in pairs(filterRings) do
			ring.Visible = (id == activeFilter)
		end
	end

	----------------------------------------------------------- grid viewport (scroll-y, kit "Viewport height 392")
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(0, DISC_H + SECTION_GAP + FILTER_H + SECTION_GAP)
	grid.Size = UDim2.new(1, 0, 0, GRID_VIEWPORT_H)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 10
	grid.ScrollBarImageColor3 = T.color.scrollThumb
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
		backin = "tab", -- "muted" per task-9-brief -- T.gradient.tab is the tabTop/tabBottom family, the nearest muted token
		forestegg = "goldSmall",
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
		l.Size = UDim2.fromScale(1, 1)
		l.AutomaticSize = Enum.AutomaticSize.None
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
		lbl.TextColor3 = T.color.textAccent
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
		local vp = BrainrotThumb.add(t.holder, t.name, {
			size = UDim2.fromScale(1, 1),
			position = UDim2.fromScale(0, 0),
			zIndex = t.holder.ZIndex + 1,
		})
		if vp then
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
		if #tiles == 0 then
			return
		end
		local viewH = grid.AbsoluteSize.Y
		if viewH <= 0 then
			return
		end
		local top = grid.CanvasPosition.Y - viewH * VIS_MARGIN
		local bottom = grid.CanvasPosition.Y + viewH * (1 + VIS_MARGIN)
		for i, t in ipairs(tiles) do
			local row = math.floor((i - 1) / GRID_COLS)
			local y0 = row * ROW_H
			if y0 + CELL_H >= top and y0 <= bottom then
				fillTile(t)
			else
				clearTile(t)
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
		UI.hardShadow(tile, T.shadowOffset.control, T.radius.inner)

		local reg = { holder = nil, name = e.Name, live = false }

		if known then
			local artHolder = Instance.new("Frame")
			artHolder.Name = "Art"
			artHolder.Position = UDim2.fromOffset(TILE_PAD, TILE_PAD)
			artHolder.Size = UDim2.new(1, -TILE_PAD * 2, 0, CELL_H - NAME_H - TILE_PAD * 2)
			artHolder.BackgroundColor3 = tier.Color -- tier-tinted backdrop doubles as the fallback swatch when no model/off-screen (IndexClient's own "wash" convention)
			artHolder.BackgroundTransparency = 0.55
			artHolder.BorderSizePixel = 0
			artHolder.ClipsDescendants = true
			artHolder.ZIndex = tile.ZIndex + 1
			artHolder.Parent = tile
			UI.corner(artHolder, T.radius.art)

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Name = "Name"
			nameLbl.BackgroundTransparency = 1
			nameLbl.FontFace = T.font.display
			nameLbl.TextSize = 14 -- kit "name 14"
			nameLbl.TextColor3 = T.color.white
			nameLbl.Text = e.Name
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
		else
			-- kit §3.5 "Undiscovered = overlay rgba(8,12,5,.72) + '?' 40px in
			-- #7A8A66" -- NO thumbnail is fetched or rendered at all here (see
			-- module header note); #7A8A66 is T.color.tabTop verbatim.
			local overlay = Instance.new("Frame")
			overlay.Name = "UndiscoveredOverlay"
			overlay.Size = UDim2.fromScale(1, 1)
			overlay.BackgroundColor3 = Color3.fromRGB(8, 12, 5)
			overlay.BackgroundTransparency = 0.28 -- 1 - .72
			overlay.BorderSizePixel = 0
			overlay.ZIndex = tile.ZIndex + 1
			overlay.Parent = tile
			UI.corner(overlay, T.radius.inner)

			local q = Instance.new("TextLabel")
			q.Name = "QuestionMark"
			q.BackgroundTransparency = 1
			q.FontFace = T.font.display
			q.TextSize = 40 -- kit "'?' 40px"
			q.TextColor3 = T.color.tabTop
			q.Text = "?"
			q.Size = UDim2.fromScale(1, 1)
			q.TextXAlignment = Enum.TextXAlignment.Center
			q.TextYAlignment = Enum.TextYAlignment.Center
			q.ZIndex = overlay.ZIndex + 1
			q.Parent = overlay
		end

		-- ribbon slot: NEW > LAST CHANCE > BACK IN > FOREST EGG (see ribbonFor)
		local _, avStatus, avTs = availabilityOf(e.Name)
		local isEggSourced = e.Source == "ForestEgg"
		local justSeen = seen[e.Name] == true
		local rtext, rkind = ribbonFor({
			Known = known,
			JustSeen = justSeen,
			AvStatus = avStatus,
			AvTs = avTs,
			IsEggSourced = isEggSourced,
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
		if filter == "Catchable" then
			refreshAvailability()
			return orderedLive
		end
		if filter == "CR" or filter == "EL" or filter == "Mplus" then
			local out = {}
			for _, rec in ipairs(ordered) do
				local rank = tierRank[rec.Tier.Name] or 0
				local pass = (filter == "CR" and rank >= 1 and rank <= 3)
					or (filter == "EL" and rank >= 4 and rank <= 5)
					or (filter == "Mplus" and rank >= 6)
				if pass then
					out[#out + 1] = rec
				end
			end
			return out
		end
		return ordered -- "All"
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
		refreshAvailability()

		for _, c in ipairs(grid:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		tiles = {}

		local found = 0
		for _, rec in ipairs(ordered) do
			if discovered[rec.E.Name] then
				found += 1
			end
		end
		discLabel.Text = string.format("%d / %d discovered", found, TOTAL_COUNT)
		UI.setFill(discFill, TOTAL_COUNT > 0 and found / TOTAL_COUNT or 0, false)

		tideValue.Text = deltaText(SupplySchedule.NextChange())

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
		UI.hardShadow(chip, T.shadowOffset.control, T.radius.small)

		local label = UI.label(chip, def.label, "cardLabel", T.color.white)
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

	----------------------------------------------------------- wiring
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)

	onDiscoveredChanged = function()
		if wrapper.Visible then
			render()
		end
	end

	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			refreshSupplySnap()
			render()
			grid.CanvasPosition = Vector2.new(0, 0) -- CanvasPosition reset gotcha
		else
			markAllSeen()
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
