-- WorldsPanel: the fast-travel board -- a GameHUDPanels consumer module.
--
-- One row per world. A world you have stood in gets a TRAVEL button; the one you
-- are standing in now says YOU ARE HERE; anywhere you have not been is greyed with
-- the reason. The board is authored in ReplicatedStorage.Modules.WorldTravelConfig
-- and the lock test is that module's own IsUnlocked, which is ALSO what the server
-- checks -- so a row can never offer a trip the server would then refuse.
--
-- TRAVEL fires remotes.TeleportTo with the world id. That remote already existed
-- for Skip/Shops/Plot; TeleportService validates the id and reuses the matching
-- portal's arrival point, so this panel carries no coordinates of its own.
--
-- MODULE-TOP-LEVEL CAPTURE, same race as DailyPanel: GameHUDPanels modules are
-- required once at startup but Build(ctx) only runs on first open, and
-- WorldTravelService pushes its one join-time state ~1s after the profile loads.
-- A listener registered inside Build would miss it, so the capture lives out here
-- and Build seeds from whatever already arrived.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WorldTravelConfig"))

local WorldsPanel = { Id = "worlds" }

local remotesTop = ReplicatedStorage:WaitForChild("Remotes")
local capturedState = nil
local liveCallbacks: { (any) -> () } = {}
do
	local r = remotesTop:WaitForChild("WorldTravelState", 30)
	if r then
		r.OnClientEvent:Connect(function(s)
			if typeof(s) ~= "table" then return end
			capturedState = s
			for _, cb in ipairs(liveCallbacks) do cb(s) end
		end)
	end
end

-- 2026-08-09 HUD upgrade (design_handoff_hud_upgrade): the board wears the
-- sheet's PanelChrome shell now -- 1080x660, blue header, 142-tall rows,
-- 96 icon tiles, 260x86 action plates. The reference panel: every other
-- panel is the same shape. Data, states and the TeleportTo wiring are
-- untouched from the pre-restyle version.
local UIKit = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIKit")
local PC = require(UIKit:WaitForChild("PanelChrome"))
local S = require(UIKit:WaitForChild("SpecTheme"))

-- sheet content: per-world icon tile colours (PS99 cool re-pick: deepened so
-- the tile tops don't vanish against the white rows; trading moved off warm-lemon)
local TILE_COLORS = {
	valley  = { Color3.fromHex("A8E28C"), Color3.fromHex("5FB34A") },
	tundra  = { Color3.fromHex("A9DFF7"), Color3.fromHex("5FB0DE") },
	trading = { Color3.fromHex("F7C75E"), Color3.fromHex("D89A2B") },
}

function WorldsPanel.Build(ctx)
	local ROW_H = 142       -- taller than the 112 default (sheet, WORLDS)
	local ROW_RADIUS = 26
	local ICON = 96
	local PLATE = Vector2.new(260, 86)

	local state = { Unlocked = {}, Here = Config.Home }

	local shell = PC.shell({
		name = "WorldsPanel",
		title = "WORLDS",
		key = "worlds",
		icon = S.Art.worlds, -- PS99 restyle: rail sticker in the header
		size = S.ShellFor.worlds,
		scroll = true, -- body scrolls; the header never does
	})

	shell.close.Activated:Connect(function()
		if ctx.closePanel then ctx.closePanel() end
	end)

	----------------------------------------------------------- rows
	local rows = {}   -- id -> { row, travel, plate, tile, glyph }

	for order, dest in ipairs(Config.Destinations) do
		local built = PC.row({
			title = dest.Label,
			subtitle = dest.Blurb,
			height = ROW_H,
			radius = ROW_RADIUS,
			iconSize = ICON,
			iconColors = TILE_COLORS[dest.Id] or nil,
			layoutOrder = order,
			parent = shell.body,
		})
		built.root.Name = dest.Id .. "Row"

		-- the current emoji icons become tiles in the same slot (sheet note);
		-- an illustrated tile can replace the glyph without touching the row

		-- SCROLL-MASK FIX (2026-08-18), same as ShopPanel's: the engine NEVER
		-- clips a rotated GuiObject, so the tilted glyphs drew over the panel's
		-- white title band when the list scrolled. The tilt now lives INSIDE
		-- this NON-rotated CanvasGroup: the rotation is rasterized into the
		-- group's own rect, which the body ScrollingFrame clips like any plain
		-- frame. Sized past the tile (96px at 1.3x is 124.8, and at ~6 degrees
		-- that needs ~138px) so the sticker overhang still shows -- but only
		-- inside the scroll area. Centred on the tile; 140 still fits the
		-- 142-tall row.
		local sticker = Instance.new("CanvasGroup")
		sticker.Name = "Sticker"
		sticker.BackgroundTransparency = 1
		sticker.BorderSizePixel = 0
		sticker.Size = UDim2.fromOffset(ICON + 44, ICON + 44)
		sticker.Position = UDim2.fromScale(0.5, 0.5)
		sticker.AnchorPoint = Vector2.new(0.5, 0.5)
		sticker.ZIndex = built.icon.ZIndex + 2 -- where the glyph sat
		sticker.Parent = built.icon

		local glyph = PC.shout({
			name = "Glyph",
			text = dest.Glyph,
			size = 56,
			parent = sticker,
			zIndex = built.icon.ZIndex + 2,
		})
		glyph.TextScaled = true

		-- PS99 sticker treatment: the glyph outgrows its tile a touch and tilts,
		-- bringing the nav rail's sticker language inside. TextScaled caps at
		-- 100px, so a static UIScale carries the extra size (setting Scale once
		-- is fine -- only TWEENING UIScale is the silent no-op in this place).
		-- Offset size, not shout's fill-the-parent default: the sticker canvas
		-- is wider than the tile, so filling IT would balloon the glyph past
		-- its old 96px footprint. Rotation and the StickerScale UIScale both
		-- ride the glyph, inside the group.
		glyph.Size = UDim2.fromOffset(ICON, ICON)
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Rotation = (order % 2 == 0) and -6 or 5
		local stickerScale = Instance.new("UIScale")
		stickerScale.Name = "StickerScale"
		stickerScale.Scale = 1.3
		stickerScale.Parent = glyph

		-- one slot, one occupant: a green TRAVEL pill OR one of two inert state plates
		local travel = PC.pill({
			name = "Travel",
			text = "TRAVEL",
			colors = S.Action.Go,
			size = UDim2.fromOffset(PLATE.X, PLATE.Y),
			position = UDim2.new(1, -22, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			zIndex = built.root.ZIndex + 1,
			parent = built.root,
		})
		travel.Activated:Connect(function()
			-- The SERVER decides. This is a request, and an unvisited world is
			-- refused there whatever the button happens to look like.
			local r = ctx.remotes:FindFirstChild("TeleportTo")
			if r then r:FireServer(dest.Id) end
			if ctx.closePanel then ctx.closePanel() end
		end)

		-- YOU ARE HERE: no colors, inherit statePlate's pale inert default
		-- (PS99 grammar -- the old slate Inert ramp read as a pressable pill)
		local herePlate = PC.statePlate({
			name = "State",
			text = "YOU ARE HERE",
			size = UDim2.fromOffset(PLATE.X, PLATE.Y),
			position = UDim2.new(1, -22, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			zIndex = built.root.ZIndex + 1,
			parent = built.root,
		})
		herePlate.Visible = false

		-- locked route: silver-grey Inert pair (grey/silver = idle/locked in
		-- the state palette; statePlate's luminance gate gives it the white
		-- shout). Never navy -- navy edges mean BUTTON and read clickable.
		local lockedPlate = PC.statePlate({
			name = "Locked",
			-- a held-back world is not undiscovered, it is not built yet for
			-- the player's purposes -- so it must not say "find it on foot"
			text = Config.IsComingSoon(dest.Id) and "COMING SOON!" or "FIND IT ON FOOT",
			colors = S.Action.Inert,
			size = UDim2.fromOffset(PLATE.X, PLATE.Y),
			position = UDim2.new(1, -22, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			zIndex = built.root.ZIndex + 1,
			parent = built.root,
		})
		lockedPlate.Visible = false

		rows[dest.Id] = {
			row = built, travel = travel,
			herePlate = herePlate, lockedPlate = lockedPlate,
			glyph = glyph,
		}
	end

	----------------------------------------------------------- paint
	local function render()
		for _, dest in ipairs(Config.Destinations) do
			local r = rows[dest.Id]
			if r then
				local unlocked = Config.IsUnlocked(nil, dest.Id) or state.Unlocked[dest.Id] == true
				local here = (state.Here == dest.Region)

				if here then
					-- pale inert plate, not a button: travel is the only green
					r.travel.Visible = false
					r.herePlate.Visible = true
					r.lockedPlate.Visible = false
				elseif unlocked then
					r.travel.Visible = true
					r.herePlate.Visible = false
					r.lockedPlate.Visible = false
				else
					-- silver-grey Inert plate: an undiscovered route reads idle
					r.travel.Visible = false
					r.herePlate.Visible = false
					r.lockedPlate.Visible = true
				end

				-- a world you have not found keeps its name but loses its ink
				local live = unlocked or here
				r.row.title.TextColor3 = live and S.Surface.ReadInk or S.Surface.ReadSub
				r.glyph.TextTransparency = live and 0 or 0.55
			end
		end
	end

	local function applyServerState(s2)
		if typeof(s2) ~= "table" then return end
		if typeof(s2.Unlocked) == "table" then state.Unlocked = s2.Unlocked end
		if typeof(s2.Here) == "string" then state.Here = s2.Here end
		render()
	end

	if capturedState then applyServerState(capturedState) end
	table.insert(liveCallbacks, applyServerState)

	render()   -- initial paint before openPanel shows the frame
	return shell.root
end

return WorldsPanel
