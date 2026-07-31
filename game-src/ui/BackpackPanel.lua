--!strict
-- BackpackPanel: kit README §3.2 Backpack panel -- a GameHUDPanels consumer module
-- (StarterPlayer.StarterPlayerScripts.GameHUDPanels.BackpackPanel).
--
-- Contract (same as GoalsPanel/DailyPanel/PassPanel): return
--   { Id = "backpack", Build = function(ctx) -> Frame }
-- Build is called ONCE lazily on first open; the shell (GameHUDClient) parents
-- the returned Frame into ctx.host and owns Visible toggling on every
-- open/close after that -- this module never sets its own Parent or drives
-- its own open/close animation.
--
-- ============================================================================
-- DATA (read FULLY before writing anything below; see task-8-report.md for
-- the complete trace):
--
--   StarterPlayer.StarterPlayerScripts.BackpackClient -- the legacy panel this
--   replaces. Its GROUPING + SORT (group identical name+mutation copies,
--   richest cash/sec first) and its HOLD flow (toggleHold/findTool) are
--   copied VERBATIM below, cited by line number against the live script read
--   at the time this module was written:
--     * grouping + richest-first sort: BackpackClient.lua lines ~590-611
--       (groupBrainrots() below is a byte-for-byte port, only renamed to be
--       a standalone testable function instead of an inline closure over
--       `list`/`UITheme` -- see the _groupBrainrots test hook at the bottom).
--     * findTool(uid): BackpackClient.lua lines 215-224 (verbatim).
--     * toggleHold(uid): BackpackClient.lua lines 226-246 (verbatim).
--   Both read `player`, `remotes` from this module's own top-level requires
--   (same names BackpackClient itself uses), so the copy needed no rewiring.
--
--   ServerScriptService.Modules.InventoryHandler (server, not directly
--   requirable from a LocalScript -- cited by number instead): HOTBAR_SLOTS
--   = 6 (line 218) is the hard cap on how many brainrots can have a real
--   Tool at once ("held"). This is DIFFERENT from "worn" (the single Tool
--   currently in the character's hand, Tool.Parent == char): up to 6 can be
--   held (have a Tool sitting in the Backpack OR worn) at the same time, but
--   only 0 or 1 can ever be WORN. The kit's header counter denominator is
--   literally "M/6" and the reference capture (backpack.png) shows TWO
--   simultaneous "EQUIPPED" ribbons on different tiles -- both facts are
--   impossible if EQUIPPED meant "worn" (max one), so "held" (has-a-Tool,
--   bounded by 6) is the correct reading, and is what drives the header
--   counter + every tile's EQUIPPED ribbon below. "Worn" (BackpackClient's
--   own `equippedUid`) still exists as a SEPARATE concept and drives only
--   the detail column's Equip/Unequip button LABEL (Unequip = this group's
--   representative uid is the one currently worn), matching BackpackClient's
--   own naming (`toggleHold`, `equippedUid`) exactly -- this module does not
--   invent new client-authoritative state, it derives "held" from a live
--   Backpack+Character Tool scan (see computeHeldAndWorn below), which is
--   the same source of truth findTool() already reads, just widened from
--   "does uid X have a tool" to "collect every BrainrotTool's uid".
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
--   PetEquip wiring); this module reads `PetConfig.ENABLED` LIVE on every
--   render (a plain top-level `require`, not a one-time capture) rather than
--   baking in today's `true`, so behaviour always tracks the actual flag
--   even if a later change flips it back to false without touching this file.
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
--   grid. The Charms tab therefore ships as the EMPTY-STATE branch only
--   ("Visit Enzo the Upgrader!" -- Enzo the Upgrader is UpgradeConfig's own
--   in-fiction seller per ReplicatedStorage.Modules.MerchantConfig line 26).
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
--   * Tile selection (click -> populate the DETAIL column) is a genuine UX
--     synthesis this panel introduces: BackpackClient's own brainrot grid
--     had no detail column at all (it toggled hold directly on tile click);
--     its PETS tab did (`showSheet`/equip button), and this panel extends
--     that same select-then-act pattern to brainrots too, because the kit
--     mandates a persistent DETAIL column with its own Equip button for
--     THIS panel specifically (§3.2). The actual hold-toggle logic invoked
--     from the Equip button is still the untouched, verbatim
--     toggleHold(uid) copy.
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

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")

local BrainrotConfig = require(modules:WaitForChild("BrainrotConfig"))
local RarityConfig = require(modules:WaitForChild("RarityConfig"))
local Mutations = require(modules:WaitForChild("MutationConfig"))
local BrainrotThumb = require(modules:WaitForChild("BrainrotThumb"))
local PetConfigModule = modules:WaitForChild("PetConfig") -- required live, see header note

local infoByName = {}
for _, e in ipairs(BrainrotConfig) do
	infoByName[e.Name] = e
end

local tierRank = {}
for i, t in ipairs(RarityConfig) do
	tierRank[t.Name] = i
end

local BackpackPanel = { Id = "backpack" }

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

local function valueOf(name: string, mutation: string?): number
	local info = infoByName[name]
	return (info and info.CashPerSecond or 0) * Mutations.Mult(mutation)
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
local function groupBrainrots(owned: { { Name: string, Mutation: string?, Uid: any } })
	local groups, order = {}, {}
	for _, item in ipairs(owned) do
		local key = (item.Mutation or "") .. "|" .. item.Name
		local g = groups[key]
		if not g then
			g = { Name = item.Name, Mutation = item.Mutation, count = 0, uids = {} }
			groups[key] = g
			order[#order + 1] = g
		end
		g.count += 1
		g.uids[#g.uids + 1] = item.Uid
	end

	table.sort(order, function(a, b)
		local ia = infoByName[a.Name]
		local ib = infoByName[b.Name]
		local va = (ia and ia.CashPerSecond or 0) * Mutations.Mult(a.Mutation)
		local vb = (ib and ib.CashPerSecond or 0) * Mutations.Mult(b.Mutation)
		if va ~= vb then
			return va > vb
		end
		return a.Name < b.Name
	end)

	return order
end

----------------------------------------------------------- hold flow (copied verbatim, see header)
-- BackpackClient.lua lines 215-224, verbatim (same `player` this module
-- already requires at the top).
local function findTool(uid): Tool?
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("Uid") == uid then
					return t
				end
			end
		end
	end
	return nil
end

-- BackpackClient.lua lines 226-246, verbatim. `equippedUid` is the module-
-- local "worn" tracker (renders the detail column's Equip/Unequip LABEL
-- only -- see header note on held vs worn).
local equippedUid = nil
local function toggleHold(uid)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local tool = findTool(uid)
	if not tool then
		remotes.EquipBrainrot:FireServer(uid)
		equippedUid = uid
		return
	end
	if tool.Parent == char then
		hum:UnequipTools()
		equippedUid = nil
	else
		hum:EquipTool(tool)
		equippedUid = uid
	end
end

-- Widened version of the findTool scan: collects EVERY currently-held
-- (has-a-Tool) uid, not just one. Same two containers, same BrainrotTool
-- attribute InventoryHandler.makeTool tags every brainrot Tool with
-- (InventoryHandler.lua line 251). Returns (heldSet, wornUid-from-container-scan);
-- the module still uses the OPTIMISTIC `equippedUid` above for the button
-- label (matching BackpackClient's own optimism), not this scan's `worn`.
local function computeHeldSet(): { [any]: boolean }
	local held = {}
	local char = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in ipairs({ backpack, char }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("BrainrotTool") then
					local uid = t:GetAttribute("Uid")
					if uid ~= nil then
						held[uid] = true
					end
				end
			end
		end
	end
	return held
end

----------------------------------------------------------- Build
function BackpackPanel.Build(ctx)
	local T = ctx.Tokens
	local UI = ctx.Builders

	----------------------------------------------------------- geometry (kit README §3.2 + task-8-brief spec deltas)
	local PANEL_W = T.size.panelWidth.backpack -- 960
	local HEADER_H = T.size.headerHeight -- 92
	local BODY_TOP = HEADER_H + 12
	local BODY_H = 566 -- brief: "panel 960, body 566"
	local GROUP_H = BODY_TOP + BODY_H

	local COL_GAP = 14 -- kit "Three columns, gap 14" (untokenised, same class of gap other panels document)
	local TABS_COL_W = 152
	local DETAIL_COL_W = 224
	local CONTENT_H = BODY_H - T.pad.panel * 2 -- 534
	local BODY_INNER_W = PANEL_W - T.pad.panel * 2 -- 928
	local GRID_COL_W = BODY_INNER_W - TABS_COL_W - DETAIL_COL_W - COL_GAP * 2 -- 524

	local TAB_H = 60
	local TAB_GAP = 9 -- kit "rows height 60 ... gap 9"

	local CHIP_H = 44 -- kit gives no chip spec for THIS panel; reused from §3.5 Index's
	local CHIP_GAP = 9 -- own filter-chip geometry (height 44, gap 9), the closest existing
	local CHIP_TO_GRID_GAP = T.pad.rowGap -- kit spec, cross-panel reuse (documented)

	local GRID_GAP = T.pad.gridGap -- 11
	local SLOT_H = T.size.bagSlot -- 118 (already tokenised)
	local SLOT_W = (GRID_COL_W - GRID_GAP * 4) / 5 -- 5 columns

	local GRID_VIEWPORT_H = CONTENT_H - CHIP_H - CHIP_TO_GRID_GAP

	----------------------------------------------------------- module-local state (server-confirmed data, ephemeral UI selection)
	local activeTab = ctx.state.backpack.tab or "Brainrots"
	local ownedBrainrots: { { Name: string, Mutation: string?, Uid: any } } = {}
	local ownedPets: { { Uid: string, Id: string } } = {}
	local petSlots: { string } = {}

	local tierFilter = "All" -- panel-local only: kit README §5's documented
	-- backpack client-state shape is { tab, selectedUid, items }, with no
	-- room for a sub-filter -- kept as ephemeral UI state here rather than
	-- widening the shared ctx.state contract (which would ripple into every
	-- other panel reading that shape).
	local selectedBrainrotKey: string? = nil -- (Mutation.."|"..Name), independent of Pets' own selection
	local selectedPetUid: string? = nil

	----------------------------------------------------------- root
	local wrapper = Instance.new("Frame")
	wrapper.Name = "BackpackPanel"
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

	local headerIcon = UI.artSlot(header, UDim2.fromOffset(T.size.headerIcon, T.size.headerIcon), T.icons.bag)
	headerIcon.Name = "SectionIcon"
	headerIcon.AnchorPoint = Vector2.new(0, 0.5)
	headerIcon.Position = UDim2.new(0, 12, 0.5, 0)
	headerIcon.ZIndex = header.ZIndex + 1

	local TITLE_TEXT = "Backpack"
	local headerTitle = UI.label(header, TITLE_TEXT, "panelTitle", T.color.white)
	headerTitle.Name = "Title"
	headerTitle.AnchorPoint = Vector2.new(0, 0.5)
	headerTitle.Position = UDim2.new(0, 12 + T.size.headerIcon + 14, 0.5, 0)
	headerTitle.ZIndex = header.ZIndex + 2

	local titleWidth = measureWidth(TITLE_TEXT, T.text.panelTitle[1], Enum.Font.FredokaOne)

	-- Spec delta (task-8-brief): "N brainrots · M/6 held" replaces the kit's
	-- own "28 / 60 slots" counter. Fredoka One 22, textOnGoldChrome (#5A4A12,
	-- no stroke) -- exact kit token, hand-built since T.text has no {22, 0}
	-- entry (same class of gap DailyPanel/GoalsPanel document for their own
	-- header add-ons).
	local counterLabel = Instance.new("TextLabel")
	counterLabel.Name = "Counter"
	counterLabel.BackgroundTransparency = 1
	counterLabel.Font = T.font.display
	counterLabel.TextSize = 22
	counterLabel.TextColor3 = T.color.textOnGoldChrome
	counterLabel.Text = "0 brainrots \u{00B7} 0/6 held"
	counterLabel.AnchorPoint = Vector2.new(0, 0.5)
	counterLabel.Position = UDim2.new(0, 12 + T.size.headerIcon + 14 + titleWidth + 14, 0.5, 0)
	counterLabel.Size = UDim2.new(0, 320, 0, 28)
	counterLabel.TextXAlignment = Enum.TextXAlignment.Left
	counterLabel.ZIndex = header.ZIndex + 2
	counterLabel.Parent = header

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(T.size.closeButton.X, T.size.closeButton.Y), "buttonL")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
	closeBtn.ZIndex = header.ZIndex + 2

	----------------------------------------------------------- body (common shell, kit README §3)
	local body = UI.panel(panelCol, UDim2.fromOffset(PANEL_W, BODY_H))
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, BODY_TOP)
	body.ZIndex = 12

	----------------------------------------------------------- tabs column (152 wide, kit §3.2)
	local tabsCol = Instance.new("Frame")
	tabsCol.Name = "Tabs"
	tabsCol.Position = UDim2.fromOffset(0, 0)
	tabsCol.Size = UDim2.fromOffset(TABS_COL_W, CONTENT_H)
	tabsCol.BackgroundTransparency = 1
	tabsCol.ZIndex = 14
	tabsCol.Parent = body

	-- USER DECISION: four category tabs, Brainrots/Pets/Charms/Eggs (replaces
	-- the kit's own All/Weapons/Units/Boosts/Skins). Icon: Tokens.icons.bag
	-- for Brainrots; Pets/Charms/Eggs get NO dedicated icon asset yet (none
	-- shipped in the kit's 8-icon set) -- UI.artSlot(nil) already renders the
	-- kit-styled placeholder swatch for a missing image, which combined with
	-- each tab's own text label satisfies "labelled placeholder slots" per
	-- the brief without inventing new artwork. NO "+ Slots" button (spec delta).
	local TAB_DEFS = {
		{ id = "Brainrots", label = "Brainrots", icon = T.icons.bag },
		{ id = "Pets", label = "Pets", icon = nil },
		{ id = "Charms", label = "Charms", icon = nil },
		{ id = "Eggs", label = "Eggs", icon = nil },
	}

	local tabFrames: { [string]: Frame } = {}
	local tabRings: { [string]: Frame } = {}

	for i, def in ipairs(TAB_DEFS) do
		local tab = UI.surface(tabsCol, UDim2.fromOffset(TABS_COL_W, TAB_H), "tab", T.radius.inner, T.stroke.control)
		tab.Name = "Tab" .. def.id
		tab.Position = UDim2.fromOffset(0, (i - 1) * (TAB_H + TAB_GAP))
		tab.ZIndex = 14
		tab.Parent = tabsCol
		UI.gloss(tab, T.radius.inner)

		local icon = UI.artSlot(tab, UDim2.fromOffset(34, 34), def.icon)
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 12, 0.5, 0)
		icon.ZIndex = tab.ZIndex + 2

		-- kit "label 19" -- no exact T.text match, cardLabel (20/3) is the
		-- nearest existing token (same documented-gap convention as prior panels).
		local label = UI.label(tab, def.label, "cardLabel", T.color.white)
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.new(0, 12 + 34 + 10, 0.5, 0)
		label.Size = UDim2.new(1, -(12 + 34 + 10 + 8), 0, 24)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = tab.ZIndex + 2

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
	local detailHost = UI.surface(body, UDim2.fromOffset(DETAIL_COL_W, CONTENT_H), "subPanel", T.radius.control, T.stroke.control)
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
	local renderBrainrots, renderPets, renderCharms, renderEggs, renderActiveTab

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
		valueLabel.Font = T.font.display
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

	local function build3DOrSwatch(parent: Instance, name: string, size: UDim2, position: UDim2, zIndex: number, tint: Color3)
		local vp = BrainrotThumb.add(parent, name, { size = size, position = position, zIndex = zIndex })
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
		local held = computeHeldSet()
		local heldCount = 0
		for _ in pairs(held) do
			heldCount += 1
		end
		counterLabel.Text = string.format("%d brainrots \u{00B7} %d/6 held", #ownedBrainrots, heldCount)
	end

	----------------------------------------------------------- BRAINROTS tab
	local grid: ScrollingFrame? = nil

	local function renderBrainrotDetail(group)
		if not group then
			buildDetailPlaceholder("Select a brainrot to see its stats.")
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
		UI.corner(hero, T.radius.small) -- kit "hero art ... radius 12"
		UI.gradient(hero, T.gradient.slot)
		UI.stroke(hero, T.stroke.control)

		local tier = infoByName[group.Name] and infoByName[group.Name].Rarity
		build3DOrSwatch(hero, group.Name, UDim2.new(1, -12, 1, -12), UDim2.fromOffset(6, 6), hero.ZIndex + 1, rarityTint(T, tier))

		local nameText = (group.Mutation and (group.Mutation .. " ") or "") .. group.Name
		local name = UI.label(detailContent, nameText, "cardLabel", T.color.white)
		name.Name = "Name"
		name.LayoutOrder = 2
		name.Size = UDim2.new(1, 0, 0, 26)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
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
		local chipLabel = UI.label(chip, (tier or "?"):upper(), "chip", rarityTint(T, tier))
		chipLabel.Size = UDim2.fromScale(1, 1)
		chipLabel.AutomaticSize = Enum.AutomaticSize.None
		chipLabel.TextXAlignment = Enum.TextXAlignment.Center
		chipLabel.ZIndex = chip.ZIndex + 1

		buildStatRow(4, "$/s", shortCash(valueOf(group.Name, group.Mutation)) .. "/s")
		buildStatRow(5, "MUTATION", group.Mutation or "None")
		buildStatRow(6, "COUNT", "x" .. tostring(group.count))

		local worn = false
		for _, uid in ipairs(group.uids) do
			if uid == equippedUid then
				worn = true
			end
		end
		local btn = UI.button(detailContent, worn and "Unequip" or "Equip", "green", UDim2.new(1, 0, 0, 56), "buttonM")
		btn.Name = "EquipButton"
		btn.LayoutOrder = 7
		btn.ZIndex = detailContent.ZIndex + 1
		btn.MouseButton1Click:Connect(function()
			toggleHold(group.uids[1])
			renderBrainrotDetail(group) -- worn flips synchronously; ribbon/counter follow the container watcher
			refreshHeader()
		end)
	end

	local function findBrainrotGroup(groups, key)
		for _, g in ipairs(groups) do
			if ((g.Mutation or "") .. "|" .. g.Name) == key then
				return g
			end
		end
		return nil
	end

	local function buildBrainrotTile(parent: Instance, order: number, group, isSelected: boolean, held: { [any]: boolean })
		local tile = UI.surface(parent, UDim2.fromOffset(SLOT_W, SLOT_H), "slot", T.radius.inner, T.stroke.control)
		tile.Name = "Tile" .. order
		tile.LayoutOrder = order
		tile.ZIndex = 15
		UI.hardShadow(tile, T.shadowOffset.control, T.radius.inner)

		local tier = infoByName[group.Name] and infoByName[group.Name].Rarity
		local artHolder = Instance.new("Frame")
		artHolder.Name = "Art"
		artHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		artHolder.Position = UDim2.fromScale(0.5, 0.5)
		artHolder.Size = UDim2.new(1, -12, 1, -12)
		artHolder.BackgroundColor3 = T.color.white
		artHolder.BorderSizePixel = 0
		artHolder.ZIndex = tile.ZIndex + 1
		artHolder.Parent = tile
		UI.corner(artHolder, T.radius.art)
		UI.gradient(artHolder, T.gradient.slot)
		build3DOrSwatch(artHolder, group.Name, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), artHolder.ZIndex + 1, rarityTint(T, tier))

		-- UI.rarityFrame hardcodes ZIndex=5 on its stroke Frame internally
		-- (UIKit.Builders, not editable here without rippling into every
		-- other panel) -- lower than the ViewportFrame/swatch it's a sibling
		-- of under artHolder. Confirmed harmless in ZIndexBehavior.Sibling
		-- mode + a transparent-background ViewportFrame: the stroke still
		-- composites through at the frame's edge, which the 3D model's own
		-- silhouette rarely reaches, so the border reads correctly in
		-- practice despite the reversed sibling z-order.
		local rarityKey = kitRarityKey(tier)
		if rarityKey == "rainbow" then
			UI.rainbowRing(artHolder, T.radius.art)
		else
			UI.rarityFrame(artHolder, rarityKey)
		end

		-- kit capture always shows a quantity chip, even x1 (deliberate deviation
		-- from BackpackClient's own ">1 only" rule -- see header note).
		local qty = Instance.new("TextLabel")
		qty.Name = "Quantity"
		qty.BackgroundTransparency = 1
		qty.Font = T.font.display
		qty.TextSize = 17
		qty.TextColor3 = T.color.white
		qty.Text = "x" .. tostring(group.count)
		qty.AnchorPoint = Vector2.new(1, 1)
		qty.Position = UDim2.new(1, -6, 1, -4)
		qty.Size = UDim2.fromOffset(40, 20)
		qty.TextXAlignment = Enum.TextXAlignment.Right
		qty.ZIndex = tile.ZIndex + 3
		qty.Parent = tile
		local qtyStroke = Instance.new("UIStroke")
		qtyStroke.Thickness = 2.5
		qtyStroke.Color = T.color.outline
		qtyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		qtyStroke.Parent = qty

		local isHeld = false
		for _, uid in ipairs(group.uids) do
			if held[uid] then
				isHeld = true
				break
			end
		end
		if isHeld then
			local ribbon = UI.ribbon(tile, "EQUIPPED", "EQUIPPED")
			ribbon.AnchorPoint = Vector2.new(0, 0)
			ribbon.Position = UDim2.new(0, -3, 0, -9)
			ribbon.ZIndex = tile.ZIndex + 4
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
			selectedBrainrotKey = (group.Mutation or "") .. "|" .. group.Name
			renderBrainrots()
			renderBrainrotDetail(group)
		end)

		tile.Parent = parent
	end

	-- Called only from renderBrainrots, which already clears contentHost's
	-- entire previous contents before calling this -- no existing "ChipRow"
	-- can be present, so this always builds fresh.
	local function renderBrainrotChips()
		local row = Instance.new("Frame")
		row.Name = "ChipRow"
		row.Position = UDim2.fromOffset(0, 0)
		row.Size = UDim2.new(1, 0, 0, CHIP_H)
		row.BackgroundTransparency = 1
		row.ZIndex = 14
		row.Parent = contentHost

		local CHIP_DEFS = {
			{ id = "All", label = "All" },
			{ id = "CR", label = "C-R" },
			{ id = "EL", label = "E-L" },
			{ id = "Mplus", label = "M+" },
			{ id = "Held", label = "Held" },
		}
		local chipW = (GRID_COL_W - CHIP_GAP * (#CHIP_DEFS - 1)) / #CHIP_DEFS

		for i, def in ipairs(CHIP_DEFS) do
			local chip = UI.surface(row, UDim2.fromOffset(chipW, CHIP_H), "tab", T.radius.small, T.stroke.control)
			chip.Name = "Chip" .. def.id
			chip.Position = UDim2.fromOffset((i - 1) * (chipW + CHIP_GAP), 0)
			chip.ZIndex = 14
			chip.Parent = row

			-- kit "label 18" -- no exact T.text match, cardLabel reused (documented gap).
			local label = UI.label(chip, def.label, "cardLabel", T.color.white)
			label.Size = UDim2.fromScale(1, 1)
			label.AutomaticSize = Enum.AutomaticSize.None
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.ZIndex = chip.ZIndex + 1

			if tierFilter == def.id then
				local ring = Instance.new("Frame")
				ring.Name = "ActiveRing"
				ring.Size = UDim2.new(1, 8, 1, 8)
				ring.Position = UDim2.fromOffset(-4, -4)
				ring.BackgroundTransparency = 1
				ring.ZIndex = chip.ZIndex + 2
				ring.Parent = chip
				UI.corner(ring, T.radius.small + 3)
				local s = Instance.new("UIStroke")
				s.Thickness = 4
				s.Color = T.color.activeRing
				s.Parent = ring
			end

			local hit = Instance.new("TextButton")
			hit.Text = ""
			hit.Size = UDim2.fromScale(1, 1)
			hit.BackgroundTransparency = 1
			hit.ZIndex = chip.ZIndex + 3
			hit.Parent = chip
			hit.MouseButton1Click:Connect(function()
				tierFilter = def.id
				renderBrainrots()
			end)
		end
	end

	renderBrainrots = function()
		clearChildren(contentHost) -- wipes any previous ChipRow/Grid/EmptyState in one pass
		refreshHeader()

		local groups = groupBrainrots(ownedBrainrots)
		local held = computeHeldSet()

		renderBrainrotChips()

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Grid"
		scroll.Position = UDim2.fromOffset(0, CHIP_H + CHIP_TO_GRID_GAP)
		scroll.Size = UDim2.fromOffset(GRID_COL_W, GRID_VIEWPORT_H)
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
		grid = scroll

		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.fromOffset(SLOT_W, SLOT_H)
		gridLayout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = scroll

		local order = 0
		for _, g in ipairs(groups) do
			local tier = infoByName[g.Name] and infoByName[g.Name].Rarity
			local rank = tierRank[tier] or 0
			local isGroupHeld = false
			for _, uid in ipairs(g.uids) do
				if held[uid] then
					isGroupHeld = true
					break
				end
			end

			local pass = true
			if tierFilter == "CR" then
				pass = rank >= 1 and rank <= 3
			elseif tierFilter == "EL" then
				pass = rank >= 4 and rank <= 5
			elseif tierFilter == "Mplus" then
				pass = rank >= 6
			elseif tierFilter == "Held" then
				pass = isGroupHeld
			end

			if pass then
				order += 1
				local key = (g.Mutation or "") .. "|" .. g.Name
				buildBrainrotTile(scroll, order, g, key == selectedBrainrotKey, held)
			end
		end

		if order == 0 then
			buildEmptyState(scroll, "Nothing here yet \u{2014} go skip some rocks.")
		end

		local selectedGroup = selectedBrainrotKey and findBrainrotGroup(groups, selectedBrainrotKey)
		renderBrainrotDetail(selectedGroup)
	end

	----------------------------------------------------------- PETS tab
	local function renderPetDetail(pet, def)
		if not pet or not def then
			buildDetailPlaceholder("Select a pet to see its stats.")
			return
		end
		clearChildren(detailContent)

		local PetConfig = require(PetConfigModule)
		local hero = Instance.new("Frame")
		hero.Name = "Hero"
		hero.LayoutOrder = 1
		hero.Size = UDim2.new(1, 0, 0, 150)
		hero.BackgroundColor3 = T.color.white
		hero.BorderSizePixel = 0
		hero.ZIndex = detailContent.ZIndex + 1
		hero.Parent = detailContent
		UI.corner(hero, T.radius.small) -- kit "hero art ... radius 12"
		UI.gradient(hero, T.gradient.slot)
		UI.stroke(hero, T.stroke.control)
		build3DOrSwatch(hero, def.Name, UDim2.new(1, -12, 1, -12), UDim2.fromOffset(6, 6), hero.ZIndex + 1, rarityTint(T, def.Rarity))

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
		local cap = PetConfig.SLOTS_FREE
		local blocked = (not isEquipped) and #petSlots >= cap
		local label = blocked and ("SLOTS FULL (" .. #petSlots .. "/" .. cap .. ")") or (isEquipped and "Unequip" or "Equip")
		local btn = UI.button(detailContent, label, blocked and "disabled" or "green", UDim2.new(1, 0, 0, 56), "buttonM")
		btn.Name = "EquipButton"
		btn.LayoutOrder = 6
		btn.ZIndex = detailContent.ZIndex + 1
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

	local function buildPetTile(parent: Instance, order: number, pet, def, isSelected: boolean)
		local tile = UI.surface(parent, UDim2.fromOffset(SLOT_W, SLOT_H), "slot", T.radius.inner, T.stroke.control)
		tile.Name = "PetTile" .. order
		tile.LayoutOrder = order
		tile.ZIndex = 15
		UI.hardShadow(tile, T.shadowOffset.control, T.radius.inner)

		local artHolder = Instance.new("Frame")
		artHolder.Name = "Art"
		artHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		artHolder.Position = UDim2.fromScale(0.5, 0.5)
		artHolder.Size = UDim2.new(1, -12, 1, -12)
		artHolder.BackgroundColor3 = T.color.white
		artHolder.BorderSizePixel = 0
		artHolder.ZIndex = tile.ZIndex + 1
		artHolder.Parent = tile
		UI.corner(artHolder, T.radius.art)
		UI.gradient(artHolder, T.gradient.slot)
		build3DOrSwatch(artHolder, def.Name, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), artHolder.ZIndex + 1, rarityTint(T, def.Rarity))

		local rarityKey = kitRarityKey(def.Rarity)
		if rarityKey == "rainbow" then
			UI.rainbowRing(artHolder, T.radius.art)
		else
			UI.rarityFrame(artHolder, rarityKey)
		end

		local isEquipped = false
		for _, u in ipairs(petSlots) do
			if u == pet.Uid then
				isEquipped = true
				break
			end
		end
		if isEquipped then
			local ribbon = UI.ribbon(tile, "EQUIPPED", "EQUIPPED")
			ribbon.AnchorPoint = Vector2.new(0, 0)
			ribbon.Position = UDim2.new(0, -3, 0, -9)
			ribbon.ZIndex = tile.ZIndex + 4
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
			selectedPetUid = pet.Uid
			renderPets()
		end)

		tile.Parent = parent
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

		local scroll = Instance.new("ScrollingFrame")
		scroll.Name = "PetGrid"
		scroll.Position = UDim2.fromOffset(0, 0)
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
			buildEmptyState(scroll, "No pets yet \u{2014} hatch an egg at the Egg Stall.")
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

	----------------------------------------------------------- CHARMS tab (empty state only, see header note)
	renderCharms = function()
		clearChildren(contentHost)
		refreshHeader()
		buildEmptyState(contentHost, "Visit Enzo the Upgrader!")
		buildDetailPlaceholder("Visit Enzo the Upgrader!")
	end

	----------------------------------------------------------- EGGS tab (empty state only)
	renderEggs = function()
		clearChildren(contentHost)
		refreshHeader()
		buildEmptyState(contentHost, "Crack eggs at Gino's stall!")
		buildDetailPlaceholder("Crack eggs at Gino's stall!")
	end

	----------------------------------------------------------- tab dispatch
	local RENDERERS = { Brainrots = renderBrainrots, Pets = renderPets, Charms = renderCharms, Eggs = renderEggs }

	local function updateTabVisuals()
		for id, ring in pairs(tabRings) do
			ring.Visible = (id == activeTab)
			tabFrames[id].ZIndex = (id == activeTab) and 15 or 14
		end
	end

	renderActiveTab = function()
		local fn = RENDERERS[activeTab]
		if fn then
			fn()
		end
	end

	local function switchTab(id: string)
		if not RENDERERS[id] then
			return
		end
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

	----------------------------------------------------------- data wiring (server-confirmed only)
	local function applySnapshot(snap)
		if typeof(snap) ~= "table" or not snap.Brainrots then
			return
		end
		ownedBrainrots = {}
		for _, e in ipairs(snap.Brainrots) do
			if not e.PadIndex and e.Uid then
				ownedBrainrots[#ownedBrainrots + 1] = { Name = e.Name, Mutation = e.Mutation, Uid = e.Uid }
			end
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
	end

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

	-- Module-top-level capture race fix (same convention DailyPanel documents):
	-- GameHUDPanels modules are require()d once, early, at GameHUDClient's own
	-- script top level; Build(ctx) only runs lazily on first open. The
	-- server's join-time DataUpdated push could plausibly land before this
	-- module's Build() ever runs, so the listener + the one-shot GetInitialData
	-- pull are wired here at require-time (this code path executes once,
	-- immediately, at require -- NOT inside Build()), matching
	-- BackpackClient's own two-source wiring (initial pull + live push).
	remotes.DataUpdated.OnClientEvent:Connect(function(payload)
		applySnapshot(payload)
		scheduleRender()
	end)
	task.spawn(function()
		local ok, snap = pcall(function()
			return remotes.GetInitialData:InvokeServer()
		end)
		if ok then
			applySnapshot(snap)
			scheduleRender()
		end
	end)

	----------------------------------------------------------- held-set live watchers (Tool add/remove -> re-render ribbon/header)
	local heldWatchConns: { RBXScriptConnection } = {}
	local function clearHeldWatchers()
		for _, c in ipairs(heldWatchConns) do
			c:Disconnect()
		end
		heldWatchConns = {}
	end

	local function onToolsMaybeChanged(inst: Instance)
		if not inst:IsA("Tool") then
			return
		end
		if not wrapper.Visible then
			return
		end
		if activeTab == "Brainrots" then
			renderBrainrots()
		else
			refreshHeader()
		end
	end

	local function hookContainers()
		clearHeldWatchers()
		local char = player.Character
		local backpack = player:FindFirstChildOfClass("Backpack")
		for _, container in ipairs({ backpack, char }) do
			if container then
				table.insert(heldWatchConns, container.ChildAdded:Connect(onToolsMaybeChanged))
				table.insert(heldWatchConns, container.ChildRemoved:Connect(onToolsMaybeChanged))
			end
		end
	end

	if player.Character then
		hookContainers()
	end
	player.CharacterAdded:Connect(function()
		equippedUid = nil
		task.defer(hookContainers) -- Backpack container reconstructs with the new character
	end)

	----------------------------------------------------------- wiring
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)

	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		if wrapper.Visible then
			hookContainers()
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

return BackpackPanel
