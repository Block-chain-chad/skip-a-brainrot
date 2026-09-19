--[[ =========================================================================
CrateCeremony -- the daily wheel's 1% loot crate, opened on screen.
---------------------------------------------------------------------------
The wheel lands on the crate and, instead of a one-line toast, a chest drops
onto the screen, rattles until you tap it, bursts open, and hands you its
contents ONE AT A TIME -- each prize flying out big, holding, then settling
into a row along the bottom so the whole haul is still there at the end.

WHAT THIS MODULE DECIDES: nothing. It is handed a manifest and it draws it.
WheelHandler builds that manifest as it grants, on the server, and ships it on
the per-player WheelState payload. That matters more here than on a normal
wedge: the crate pays one of every egg in the world it was spun in, and those
eggs HATCH -- so the real prize is a list of PETS that does not exist until
the server rolls it. Deriving the contents client-side from WheelConfig would
show five eggs and never be able to name what came out of them.

WHY THE EGG SHOP'S OWN HATCH DOES NOT PLAY HERE. Every reward egg normally
fires remotes.EggResult so the shop's ceremony runs. Five of those back to
back, over a wheel that is still spinning, is a pile-up rather than a jackpot
-- so the crate asks GrantReward for NoReveal and parades the pets through
this chest instead. One ceremony, in one place, in a fixed order.

THE CHEST IS A REAL 3D RENDER, and this is the one surface in the game where
that is the right call. IconForge's own note says its viewport models need a
surface big enough to earn them: they were pulled OFF the wheel's 50px icon
chips for exactly that reason, a multi-part model at that size being coloured
mush. At 360px, with a lid swinging on a real hinge, it is earned.

HINGE MATHS, because it is the one thing here that is easy to get backwards.
Every lid part is stored as an offset from a hinge CFrame sitting on the
chest's back-top edge, so opening is ONE rotation applied to all of them:
    part.CFrame = HINGE * CFrame.Angles(-theta, 0, 0) * offset
A rotation about +X carries +Y toward +Z, which would drop the lid FORWARD
into the camera; the angle is negated so it tips back and away instead.
========================================================================= ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
-- Egg shell colours, keyed by the same model name the manifest carries, so an egg
-- card is tinted with the colour of the egg it is actually showing.
local EggPalettes = require(ReplicatedStorage.Modules.EggPalettes)

-- pcall'd, exactly like every other IconArt caller: the drawn icons are the
-- decoration on this screen, not the substance, and a kit that fails to load
-- must not take the whole ceremony down with it -- the glyph fallback covers it.
local okIconArt, IconArt = pcall(function()
	return require(ReplicatedStorage.Modules.UIKit.IconArt)
end)
if not okIconArt then IconArt = nil end

local M = {}

local CANDY = UITheme.Candy
local INK = CANDY.ink
local FONT = CANDY.font

local tierByName = {}
for _, t in ipairs(RarityConfig) do tierByName[t.Name] = t end

--================================ helpers ==================================--
local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

-- Returns the UIStroke, not the label: the parade fades these out as a card
-- shrinks into the tray, and a stroke left at full opacity around 12px of
-- invisible text reads as a smudge on the chip.
local function stroke(o, thickness, colour)
	return new("UIStroke", {
		Color = colour or INK, Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, o)
end

-- FULL digits, deliberately. NumberFormat.Cash abbreviates ($2.50M), which is
-- right for a HUD pill that has to fit and wrong for the one screen whose whole
-- job is to make the number feel big.
local function comma(n)
	local s = tostring(math.floor(math.abs(tonumber(n) or 0)))
	local k
	repeat
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

-- Headline and sub-line for one manifest row. Built HERE rather than shipped
-- from the server: the manifest carries data (kind, amount, name, rarity) and
-- this file owns how it reads, so wording changes never need a server touch.
local function describe(row)
	if row.Kind == "Cash" then
		return "$" .. comma(row.Amount), "CASH"
	elseif row.Kind == "Emeralds" then
		return "+" .. comma(row.Amount), (tonumber(row.Amount) == 1) and "GEM" or "GEMS" -- player-facing: Gems (2026-09-18)
	elseif row.Kind == "Egg" then
		return tostring(row.Name or "EGG"), "EGG"
	elseif row.Kind == "Pet" then
		return tostring(row.Name or "PET"), string.upper(tostring(row.Rarity or "PET"))
	end
	return tostring(row.Label or "PRIZE"), tostring(row.Sub or "")
end

-- The card's accent: a pet takes its RARITY colour (the same tier colours the
-- catch reveal and the backpack use, so a Legendary looks Legendary here too),
-- and the two currencies take their own.
local CASH_ACCENT = Color3.fromRGB(88, 214, 62)
local GEM_ACCENT = Color3.fromRGB(52, 214, 132)
local EGG_ACCENT = Color3.fromRGB(196, 214, 140)
local function accentFor(row)
	if row.Kind == "Cash" then return CASH_ACCENT end
	if row.Kind == "Emeralds" then return GEM_ACCENT end
	if row.Kind == "Egg" then
		-- The egg's OWN shell colour, so the five cards are visibly five different
		-- eggs and each one matches what turns up on the hatch screen after.
		-- Pushed up in saturation first: shell colours are deliberately muted (sage,
		-- tan, dusty red) and the card tints 74% toward white, which would wash a
		-- muted base out to nearly nothing.
		--
		-- THE FLOOR IS THE IMPORTANT HALF, and multiplying alone missed it: the
		-- Hollow Egg's shell is a near-grey lilac (S = 0.07), and 1.55x of nearly no
		-- saturation is still nearly no saturation. Its card came out white, and a
		-- pale egg rendered on a white card is invisible -- which is exactly what
		-- shipped for one beat before a screenshot caught it. Flooring S keeps every
		-- shell's HUE (so the cards stay five distinguishable eggs) while
		-- guaranteeing the model has something to sit against.
		local pal = row.Model and EggPalettes[row.Model]
		if pal and typeof(pal.base) == "Color3" then
			local h, s, v = Color3.toHSV(pal.base)
			return Color3.fromHSV(h, math.clamp(s * 1.55, 0.42, 1), math.max(v, 0.82))
		end
		return EGG_ACCENT
	end
	local tier = row.Rarity and tierByName[row.Rarity]
	return (tier and tier.Color) or Color3.fromRGB(255, 199, 44)
end

--=============================== the chest =================================--
-- Palette lifted from IconForge's own crate builder, so the chest that opens
-- here is recognisably the chest painted on the wheel's wedge.
local WOOD1 = Color3.fromRGB(178, 122, 66)
local WOOD2 = Color3.fromRGB(132, 86, 44)
local GOLD1 = Color3.fromRGB(255, 199, 44)
local GOLD2 = Color3.fromRGB(226, 158, 22)
local CREAM = Color3.fromRGB(248, 240, 218)

-- The back-top edge of the base box. See the hinge note in the header.
local HINGE = CFrame.new(0, 0.13, -0.68)

local function block(parent, size, cf, colour)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A cylinder's axis is its X, natively -- which is already the axis a chest lid
-- wants -- so unlike IconForge's helper this one needs no re-orientation.
local function cyl(parent, dia, len, cf, colour)
	local p = block(parent, Vector3.new(len, dia, dia), cf, colour)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Returns the model plus the lid's parts, each paired with its offset from
-- HINGE. Called TWICE per ceremony -- once for the ink pass, once for the
-- colour pass -- so both viewports can be driven from one angle.
local function buildChest()
	local model = Instance.new("Model")
	model.Name = "LootChest"

	----------------------------------------------------------------- the base
	block(model, Vector3.new(2.20, 1.25, 1.35), CFrame.new(0, -0.50, 0), WOOD1)
	-- a recessed front panel, so the box has a face rather than being a slab
	block(model, Vector3.new(1.46, 0.76, 0.08), CFrame.new(0, -0.54, 0.69), WOOD2)
	block(model, Vector3.new(2.26, 0.16, 1.42), CFrame.new(0, -1.05, 0), GOLD2)
	for _, s in ipairs({ -1, 1 }) do
		block(model, Vector3.new(0.22, 1.31, 1.41), CFrame.new(s * 0.86, -0.50, 0), GOLD2)
	end
	-- THE LOCK STAYS ON THE BASE. It is the lid lifting away from a clasp that
	-- is still sitting there that reads as the chest coming unlocked; a lock
	-- carried up with the lid just looks like a sticker.
	block(model, Vector3.new(0.44, 0.52, 0.10), CFrame.new(0, -0.06, 0.70), GOLD1)
	block(model, Vector3.new(0.13, 0.17, 0.10), CFrame.new(0, -0.10, 0.76), INK)

	------------------------------------------------------------------ the lid
	local lid = {}
	local function hinged(p)
		lid[#lid + 1] = { p = p, rel = HINGE:Inverse() * p.CFrame }
		return p
	end
	-- lip first, then the dome sitting on it, then the bands wrapping both
	hinged(block(model, Vector3.new(2.26, 0.22, 1.44), CFrame.new(0, 0.24, 0), WOOD2))
	hinged(cyl(model, 1.36, 2.20, CFrame.new(0, 0.35, 0), WOOD1))
	for _, s in ipairs({ -1, 1 }) do
		hinged(cyl(model, 1.39, 0.24, CFrame.new(s * 0.86, 0.35, 0), GOLD2))
	end
	-- A shine streak laid along the dome's upper-left, angled to sit tangent to
	-- it. Rides the lid, so it swings away with everything else.
	hinged(block(model, Vector3.new(0.66, 0.09, 0.13),
		CFrame.new(-0.44, 0.89, 0.33) * CFrame.Angles(math.rad(-56), 0, 0), CREAM))

	return model, lid
end

--=============================== mounting ==================================--
-- Front-quarter, slightly above: the same family of angle IconForge frames its
-- icons at. FIT is generous on purpose -- the lid swings up and BACK through an
-- arc a box-tight fit would crop the instant it opened.
local CAM_DIR = Vector3.new(0.36, 0.42, 1).Unit
local FOV = 30
local FIT = 1.46

-- Mounts the chest into `parent` and returns a setter taking the lid angle in
-- radians. Both viewports get their own model and both are driven by that one
-- setter, so the ink silhouette can never fall out of step with the chest it is
-- outlining.
local function mountChest(parent, zBase)
	local colourModel, colourLid = buildChest()
	local inkModel, inkLid = buildChest()

	local cf, ext = colourModel:GetBoundingBox()
	-- look slightly ABOVE the closed chest's centre: with the lid open the mass
	-- of the thing sits higher than it does shut
	local centre = cf.Position + Vector3.new(0, 0.30, 0)
	local dist = (ext.Magnitude * 0.5) / math.sin(math.rad(FOV) * 0.5) * FIT

	local function viewport(model, z, d, tint)
		local vp = new("ViewportFrame", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z,
			Ambient = Color3.fromRGB(188, 184, 176),
			LightColor = Color3.fromRGB(255, 250, 236),
			LightDirection = Vector3.new(-0.4, -0.7, -0.5),
		}, parent)
		if tint then vp.ImageColor3 = tint end
		model.Parent = vp
		local cam = Instance.new("Camera")
		cam.FieldOfView = FOV
		cam.CFrame = CFrame.lookAt(centre + CAM_DIR * d, centre)
		cam.Parent = vp
		vp.CurrentCamera = cam
		return vp
	end

	-- The ink pass is the same render pulled 6% closer and flooded with ink, so
	-- a slightly larger black silhouette shows around the chest: the chunky
	-- cartoon outline the rest of this HUD is drawn with. 1.06 is IconForge's
	-- own settled figure -- wider than that and the gaps BETWEEN parts start
	-- showing ink through, which reads as the chest coming apart.
	viewport(inkModel, zBase, dist / 1.06, INK)
	viewport(colourModel, zBase + 1, dist, nil)

	local sets = { colourLid, inkLid }
	return function(theta)
		local turn = CFrame.Angles(-theta, 0, 0)
		for _, set in ipairs(sets) do
			for _, entry in ipairs(set) do
				if entry.p.Parent then
					entry.p.CFrame = HINGE * turn * entry.rel
				end
			end
		end
	end
end

--============================== prize cards ================================--
local CARD_W, CARD_H = 270, 316
local ICON_BOX = 178
local TRAY_PX = 96

-- One prize, as a card. The SAME instance is later shrunk into the tray rather
-- than being replaced by a separate chip: a pet card carries a live
-- ViewportFrame, and building a second one to throw the first away would render
-- the model twice for no visible gain.
local function buildCard(parent, row, z)
	local accent = accentFor(row)
	local headline, subline = describe(row)

	local card = new("Frame", {
		Name = "Prize", AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = z,
	}, parent)
	UITheme.candyPanel(card, 22)
	-- Tinted toward the accent rather than painted in it: a fully saturated card
	-- leaves the white outlined type with nothing to sit against, which is the
	-- readability rule the rest of this game's panels are built on.
	UITheme.setColors(card,
		accent:Lerp(Color3.new(1, 1, 1), 0.74),
		accent:Lerp(Color3.new(0, 0, 0), 0.06))
	local scale = new("UIScale", { Scale = 1 }, card)

	-- CLIPPED, which is what lets the pet viewport below overflow its box safely:
	-- anything that would spill lands on the headline instead, and a name with a
	-- pet's feet through it is worse than a pet cropped at the margin.
	local iconBox = new("Frame", {
		Name = "IconBox", AnchorPoint = Vector2.new(0.5, 0), ClipsDescendants = true,
		Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(ICON_BOX, ICON_BOX),
		BackgroundTransparency = 1, ZIndex = z + 1,
	}, card)

	local drew = false
	if row.Kind == "Pet" then
		-- The real pet model, framed by the shared helper -- the same render the
		-- backpack and the hatch reveal show, so the thing that comes out of the
		-- chest is visibly the thing that lands in your bag. Relit: a viewport's
		-- stock lighting renders these as brown blobs (see BrainrotThumb's note).
		-- OVERSIZED BY 18%, deliberately. BrainrotThumb frames a model's bounding
		-- SPHERE -- the one radius that holds at every angle, which is what its
		-- spinning callers need -- and a sphere around a roughly cubic pet is about
		-- 15% wider than the pet, on top of its own 10% margin. Correct framing, but
		-- on a hero card it leaves the pet floating in space. Scaling the viewport
		-- past its holder spends exactly that slack; the clip above catches the rest.
		drew = BrainrotThumb.addPet(iconBox, row.Model, row.Name, {
			size = UDim2.fromScale(1.18, 1.18), position = UDim2.fromScale(-0.09, -0.09),
			zIndex = z + 2, fov = 30,
			ambient = Color3.fromRGB(190, 190, 190),
			lightColor = Color3.fromRGB(255, 250, 238),
			lightDirection = Vector3.new(-0.35, -0.7, -0.45),
		}) ~= nil
	elseif row.Kind == "Egg" then
		-- The real egg model, the same one the shop and the hatch screen show. Eggs
		-- are near enough spherical that the bounding-sphere framing wastes less
		-- room on them than it does on a pet, so this takes a smaller push (1.10).
		drew = BrainrotThumb.addMaster(iconBox,
			BrainrotThumb.eggMaster(row.Model, row.World or "Forest"), {
				size = UDim2.fromScale(1.10, 1.10), position = UDim2.fromScale(-0.05, -0.05),
				zIndex = z + 2, fov = 30,
				ambient = Color3.fromRGB(190, 190, 190),
				lightColor = Color3.fromRGB(255, 250, 238),
				lightDirection = Vector3.new(-0.35, -0.7, -0.45),
			}) ~= nil
	elseif IconArt then
		-- The game's own drawn currency art, NOT an emoji: the emerald here is the
		-- same stone the HUD pill and every price row draw.
		local key = (row.Kind == "Emeralds" and "emerald")
			or (row.Kind == "Cash" and "coin")
			or nil
		if key and IconArt.has(key) then
			local art = IconArt.draw(iconBox, key, ICON_BOX - 12, z + 2)
			if art then
				-- draw() bakes its shapes at a fixed pixel size and parks the root at
				-- the parent's top-left; re-anchoring the root centres the whole
				-- drawing without disturbing anything inside it.
				art.AnchorPoint = Vector2.new(0.5, 0.5)
				art.Position = UDim2.fromScale(0.5, 0.5)
				drew = true
			end
		end
	end
	if not drew then
		-- Last resort only: no pet model, or IconArt failed to load.
		local glyph = new("TextLabel", {
			Name = "Glyph", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Text = (row.Kind == "Emeralds" and "\u{1F48E}")
				or (row.Kind == "Cash" and "\u{1F4B0}")
				or (row.Kind == "Egg" and "\u{1F95A}") or "\u{1F381}",
			Font = FONT, TextScaled = true, ZIndex = z + 2,
		}, iconBox)
		-- emoji: never recoloured or outlined, a UIStroke on a colour glyph
		-- renders as a smear
		glyph:SetAttribute("NoPolish", true)
	end

	local name = new("TextLabel", {
		Name = "Headline", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 198), Size = UDim2.new(1, -26, 0, 52),
		BackgroundTransparency = 1, Text = headline, Font = FONT, TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = z + 3,
	}, card)
	new("UITextSizeConstraint", { MaxTextSize = 40 }, name)
	local nameStroke = stroke(name, 3.5)

	local sub = new("TextLabel", {
		Name = "Sub", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 254), Size = UDim2.new(1, -26, 0, 32),
		BackgroundTransparency = 1, Text = subline, Font = FONT, TextScaled = true,
		TextColor3 = accent, ZIndex = z + 3,
	}, card)
	new("UITextSizeConstraint", { MaxTextSize = 26 }, sub)
	local subStroke = stroke(sub, 3)
	-- The rarity name IS the colour here -- it is information, not decoration --
	-- so it opts out of UIPolish's white-everything pass the same way the wheel's
	-- own tiered labels do. Tier colours are bright, so the readability floor
	-- leaves them alone rather than overriding them back to white.
	sub:SetAttribute("NoPolish", true)

	-- Fades the lettering as the card shrinks into the tray: 26px of type poured
	-- into a 96px chip is unreadable anyway, and the stroke around it reads as a
	-- smudge. The icon carries the chip on its own.
	local function fadeText(dur)
		local ti = TweenInfo.new(dur)
		TweenService:Create(name, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(sub, ti, { TextTransparency = 1 }):Play()
		TweenService:Create(nameStroke, ti, { Transparency = 1 }):Play()
		TweenService:Create(subStroke, ti, { Transparency = 1 }):Play()
	end

	return { card = card, scale = scale, fadeText = fadeText, accent = accent, headline = headline }
end

--============================== the ceremony ===============================--
-- DisplayOrder 70 clears every surface that can legitimately be on screen when
-- a crate lands -- the wheel (12), the egg shop (40) and the toast rail (60) --
-- and stays under the teleport fade (10000), which must always win.
local DISPLAY_ORDER = 70

local function ensureGui()
	local plr = Players.LocalPlayer
	local pg = plr and plr:FindFirstChildOfClass("PlayerGui")
	if not pg then return nil end
	local gui = pg:FindFirstChild("LootCrateCeremony")
	if not gui then
		gui = new("ScreenGui", {
			Name = "LootCrateCeremony", ResetOnSpawn = false, IgnoreGuiInset = true,
			DisplayOrder = DISPLAY_ORDER, Enabled = false,
		}, pg)
	end
	return gui
end

local RATTLE_WAIT = 9     -- seconds the chest waits to be tapped before opening itself
local OPEN_T, OPEN_DEG = 0.52, 112
local CARD_IN_T, CARD_HOLD, CARD_OUT_T = 0.42, 1.15, 0.34
local END_WAIT = 5
-- Where a prize is presented, and where it parks afterwards. Both in scale so the
-- stack holds on a short screen: the tray sits high enough to leave room for the
-- CAPTIONS under it (see the parade) and for the hint under those, and the
-- presentation slot sits high enough to clear the tray's top edge.
local CARD_Y, TRAY_Y = 0.47, 0.80

-- PHASE ONE: build the screen, drop the chest in, and wait for the tap. Split
-- from the parade below because this half ends on an open-ended wait for the
-- player and that half is a fixed sequence -- one function doing both was a
-- hundred lines with a nine-second pause in the middle of it.
-- Returns the scene the parade needs to carry on with.
local function stage(gui, payload)
	for _, c in ipairs(gui:GetChildren()) do c:Destroy() end
	gui.Enabled = true

	local rows = payload.Rows
	local n = #rows
	local cam = workspace.CurrentCamera
	local vw, vh = 1280, 720
	if cam and cam.ViewportSize.Y > 1 then
		vw, vh = cam.ViewportSize.X, cam.ViewportSize.Y
	end
	-- SIZED OFF THE VIEWPORT, not a constant. A fixed 360px chest is a third of
	-- the screen on a phone held short-side up, and it collided with the counter
	-- above it -- everything below is laid out in scale, so the one pixel-sized
	-- object has to follow suit.
	local chestPx = math.clamp(vh * 0.42, 170, 380)

	--------------------------------------------------------------- the backdrop
	local scrim = new("Frame", {
		Name = "Scrim", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(8, 7, 14), BackgroundTransparency = 1, ZIndex = 1,
	}, gui)
	TweenService:Create(scrim, TweenInfo.new(0.35), { BackgroundTransparency = 0.25 }):Play()

	-- ONE button owns every tap in the ceremony -- opening the chest, hurrying a
	-- prize along, dismissing at the end -- because the alternative is three
	-- overlapping hit targets arguing about which one the player meant. It sits
	-- at the bottom of the stack and still gets every click: a Frame, TextLabel
	-- or ViewportFrame does not consume input unless it is Active, and none of
	-- the artwork above is.
	local taps = 0
	local tap = new("TextButton", {
		Name = "Tap", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, ZIndex = 2,
	}, gui)
	tap.Activated:Connect(function() taps += 1 end)
	-- Returns true if a tap arrived, false if it timed out. Every wait in this
	-- ceremony is bounded: a player who walks away must still get their screen
	-- back, and the prizes are already banked server-side regardless.
	local function waitForTap(timeout)
		local mark, t0 = taps, os.clock()
		while taps == mark and os.clock() - t0 < timeout do
			task.wait(0.05)
		end
		return taps ~= mark
	end

	----------------------------------------------------------------- lettering
	local title = new("TextLabel", {
		Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.07, 0),
		Size = UDim2.fromOffset(math.min(vw - 40, 640), 60), BackgroundTransparency = 1,
		Text = payload.Title or "LOOT CRATE", Font = FONT, TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 20,
	}, gui)
	new("UITextSizeConstraint", { MaxTextSize = 52 }, title)
	stroke(title, 4)
	local titleScale = new("UIScale", { Scale = 0.55 }, title)
	TweenService:Create(titleScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()

	local counter = new("TextLabel", {
		Name = "Counter", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.155, 0),
		Size = UDim2.fromOffset(240, 34), BackgroundTransparency = 1, Text = "",
		Font = FONT, TextScaled = true, TextColor3 = Color3.fromRGB(255, 226, 130), ZIndex = 20,
	}, gui)
	new("UITextSizeConstraint", { MaxTextSize = 28 }, counter)
	stroke(counter, 3)
	counter:SetAttribute("NoPolish", true)

	local hint = new("TextLabel", {
		Name = "Hint", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.68, 0),
		Size = UDim2.fromOffset(360, 38), BackgroundTransparency = 1, Text = "TAP TO OPEN",
		Font = FONT, TextScaled = true, TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 20,
	}, gui)
	new("UITextSizeConstraint", { MaxTextSize = 30 }, hint)
	stroke(hint, 3)
	-- a slow breath on the prompt, so it reads as waiting for you rather than as
	-- a caption that happens to be there
	local hintScale = new("UIScale", { Scale = 1 }, hint)
	local pulsing = true
	task.spawn(function()
		while pulsing do
			hintScale.Scale = 1 + math.sin(os.clock() * 4.2) * 0.055
			RunService.RenderStepped:Wait()
		end
		hintScale.Scale = 1
	end)

	------------------------------------------------------------------ the chest
	local chest = new("Frame", {
		Name = "Chest", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.20, 0),
		Size = UDim2.fromOffset(chestPx, chestPx), BackgroundTransparency = 1, ZIndex = 10,
	}, gui)
	local chestScale = new("UIScale", { Scale = 0.25 }, chest)
	local glow = new("Frame", {
		Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.12, 0.12), BackgroundColor3 = Color3.fromRGB(255, 214, 96),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 9,
	}, chest)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
	local setLid = mountChest(chest, 11)
	setLid(0)

	-- drop it in and land it
	TweenService:Create(chest, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, 0, 0.42, 0) }):Play()
	TweenService:Create(chestScale, TweenInfo.new(0.46, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	task.wait(0.42)
	SoundKit.play("place", nil, { volume = 0.45 })

	-- Something is alive in there: a short shudder and a knock, on a beat, until
	-- it is tapped. A continuous shake for nine seconds reads as a broken tween.
	local rattling = true
	task.spawn(function()
		while rattling do
			for _ = 1, 9 do
				if not rattling then break end
				chest.Rotation = (math.random() - 0.5) * 4.5
				task.wait(0.03)
			end
			chest.Rotation = 0
			if rattling then SoundKit.play("eggCrack1", nil, { volume = 0.16 }) end
			local t0 = os.clock()
			while rattling and os.clock() - t0 < 0.95 do task.wait(0.05) end
		end
		chest.Rotation = 0
	end)

	waitForTap(RATTLE_WAIT)
	rattling = false
	task.wait(0.06)
	chest.Rotation = 0
	pulsing = false
	hint.Text = ""
	return {
		gui = gui, rows = rows, n = n, chest = chest, chestScale = chestScale,
		glow = glow, setLid = setLid, hint = hint, counter = counter,
		waitForTap = waitForTap, vw = vw, vh = vh,
	}
end

-- PHASE TWO: burst it open and hand over the contents, one prize at a time.
local function run(gui, payload)
	local s = stage(gui, payload)
	local n, rows = s.n, s.rows

	------------------------------------------------------------------ the lid
	SoundKit.play("eggSplit", nil, { volume = 0.50 })
	SoundKit.play("wheelJackpotHit", nil, { volume = 0.42 })
	TweenService:Create(s.glow, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1.9, 1.9), BackgroundTransparency = 0.42 }):Play()

	-- Driven per frame rather than by a tween, because what is being animated is
	-- an ANGLE that nine parts are derived from, not a property on one instance.
	-- Back-out on that angle so the lid overshoots and settles instead of
	-- stopping dead at the top of its arc.
	local t0 = os.clock()
	while true do
		local a = math.clamp((os.clock() - t0) / OPEN_T, 0, 1)
		s.setLid(math.rad(OPEN_DEG)
			* TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		if a >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	TweenService:Create(s.glow, TweenInfo.new(0.85), { BackgroundTransparency = 1 }):Play()

	--========================= the parade's layout =========================--
	-- Worked out BEFORE the chest pulls back, because the hint moves as part of
	-- that same tween and has to know where it is going.
	--
	-- LAYOUT SCALE. Every pixel size in this file is authored against a ~900px
	-- viewport. Below that the stack -- presented card, tray of chips, captions
	-- under the chips, hint under those -- stops fitting, and from around 640px
	-- down the pieces overlap. Driving the card's OWN UIScale is the whole fix: it
	-- shrinks a card and everything inside it together, so nothing in buildCard
	-- has to know the viewport exists.
	local k = math.clamp(s.vh / 900, 0.45, 1)
	-- The tray has to fit ACROSS as well: seven prizes on a phone is what decides
	-- this, and without the clamp the last chip walks off the side.
	local pitch = math.clamp((s.vw * 0.86) / math.max(n, 1), 58, 112)
	local trayScale = (TRAY_PX / CARD_W) * k
	local chipH = CARD_H * trayScale        -- a settled chip's height
	local capH = math.floor(30 * k)         -- and its caption's
	local capGap = 6
	-- STACKED DOWN FROM THE TRAY rather than pinned to the bottom of the screen.
	-- The hint sat at a fixed 0.965, which is fine on a desktop and lands
	-- underneath the captions on anything shorter.
	local hintY = TRAY_Y + (chipH * 0.5 + capGap + capH + 10 + 19 * k) / s.vh

	-- The chest steps back and up to become the SOURCE the prizes come out of,
	-- clearing the middle of the screen for them.
	local back = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(s.chest, back, { Position = UDim2.new(0.5, 0, 0.20, 0) }):Play()
	TweenService:Create(s.chestScale, back, { Scale = 0.60 }):Play()
	s.hint.Size = UDim2.fromOffset(360, math.max(math.floor(38 * k), 16))
	TweenService:Create(s.hint, back, { Position = UDim2.new(0.5, 0, hintY, 0) }):Play()
	task.wait(0.38)

	---------------------------------------------------------------- the parade
	s.hint.Text = "TAP TO SKIP"
	for i, row in ipairs(rows) do
		local h = buildCard(gui, row, 30)
		h.card.Position = UDim2.new(0.5, 0, 0.20, 0)
		h.scale.Scale = 0.2 * k
		s.counter.Text = ("%d / %d"):format(i, n)

		local out = TweenInfo.new(CARD_IN_T, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(h.card, out, { Position = UDim2.new(0.5, 0, CARD_Y, 0) }):Play()
		TweenService:Create(h.scale, out, { Scale = k }):Play()
		SoundKit.play("catchSparkle", nil, { volume = 0.34 })
		if row.Kind == "Cash" then SoundKit.play("cash", nil, { volume = 0.28 }) end
		task.wait(CARD_IN_T)

		-- a tap here hurries THIS prize into the tray; it never skips one unseen
		s.waitForTap(CARD_HOLD)

		local slotX = (i - (n + 1) / 2) * pitch
		local settle = TweenInfo.new(CARD_OUT_T, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(h.card, settle, { Position = UDim2.new(0.5, slotX, TRAY_Y, 0) }):Play()
		TweenService:Create(h.scale, settle, { Scale = trayScale }):Play()
		h.fadeText(0.18)

		-- THE CHIP KEEPS ITS NAME. The card's own lettering is faded out as it
		-- shrinks -- 40px type poured into a 96px chip scales down to nothing and its
		-- stroke reads as a smudge -- so the name is re-set BESIDE the chip at full
		-- pixel size instead. Parented to the gui rather than to the card, because a
		-- caption inside the card would be shrunk by the very UIScale that made the
		-- original unreadable.
		--
		-- TextScaled UNDER a size cap, not a fixed size: the tray pitch collapses to
		-- 58px on a narrow screen with seven prizes in it, and "Heartwood Egg" has to
		-- shrink to fit rather than spill into its neighbours.
		local caption = new("TextLabel", {
			Name = "Caption" .. i, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, slotX, TRAY_Y, math.floor(chipH * 0.5) + capGap),
			Size = UDim2.fromOffset(pitch - 4, capH), BackgroundTransparency = 1,
			Text = h.headline, Font = FONT, TextScaled = true, TextWrapped = true,
			TextColor3 = Color3.fromRGB(255, 255, 255), TextTransparency = 1, ZIndex = 29,
		}, gui)
		new("UITextSizeConstraint", { MaxTextSize = math.max(math.floor(14 * k), 8) }, caption)
		local capStroke = stroke(caption, 2)
		capStroke.Transparency = 1
		-- fades in as the card lands, so the name arrives with the chip
		TweenService:Create(caption, TweenInfo.new(0.26), { TextTransparency = 0 }):Play()
		TweenService:Create(capStroke, TweenInfo.new(0.26), { Transparency = 0 }):Play()

		task.wait(0.16)
	end

	----------------------------------------------------------------- the close
	-- SAY WHAT HAPPENS NEXT. A crate pays eggs, and the eggs get opened on the
	-- hatch screen straight after this one -- so the last thing on the chest is a
	-- pointer at that, not a dead end. Derived from the rows rather than passed in,
	-- so a crate that ever pays no eggs simply closes instead of promising a screen
	-- that will not come.
	local hasEggs = false
	for _, row in ipairs(rows) do
		if row.Kind == "Egg" then hasEggs = true end
	end
	s.counter.Text = ""
	s.hint.Text = hasEggs and "TAP TO OPEN YOUR EGGS" or "TAP TO CLOSE"
	SoundKit.play("catchBigHit", nil, { volume = 0.30 })
	s.waitForTap(END_WAIT)

	-- Faded by walking the tree rather than through a CanvasGroup: a CanvasGroup
	-- rasterises its children, and the chest and every pet card in the tray are
	-- live ViewportFrames.
	local ti = TweenInfo.new(0.4)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("ViewportFrame") then
			TweenService:Create(d, ti, { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
		elseif d:IsA("TextLabel") or d:IsA("TextButton") then
			TweenService:Create(d, ti, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, ti, { Transparency = 1 }):Play()
		elseif d:IsA("GuiObject") then
			TweenService:Create(d, ti, { BackgroundTransparency = 1 }):Play()
		end
	end
	task.wait(0.45)
	gui.Enabled = false
	for _, c in ipairs(gui:GetChildren()) do c:Destroy() end

	-- Handed over only once the screen is actually clear. This is what releases the
	-- crate's eggs to the hatch ceremony, and that ceremony draws its own
	-- full-screen overlay -- fire it any earlier and the two would be up together.
	if type(payload.OnFinished) == "function" then
		task.spawn(payload.OnFinished)
	end
end

--=================================== api ===================================--
--[[ Plays the crate opening. `payload`:
       Rows   ordered list of prizes, each { Kind = "Cash" | "Emeralds" | "Pet",
              Amount = n            (Cash / Emeralds)
              Name, Rarity, Model   (Pet -- Model is PetConfig's .Model field) }
       Title  optional headline, defaulting to LOOT CRATE
       OnFinished  optional callback, run once the chest has torn itself down.
              The wheel uses it to tell the server the chest is finished with, so
              the crate's eggs can be released to the hatch screen.
Returns true if the ceremony was started. Nothing is granted, refused or
retried here -- by the time this runs the prizes are already banked server-side,
which is why every wait inside is bounded and why a failure just tears the
screen down rather than trying to recover. ]]
local running = false
function M.play(payload)
	if running then return false end
	if type(payload) ~= "table" or type(payload.Rows) ~= "table" or #payload.Rows == 0 then
		return false
	end
	local gui = ensureGui()
	if not gui then return false end

	running = true
	task.spawn(function()
		local ok, err = pcall(run, gui, payload)
		running = false
		if not ok then
			-- Loud, and then get off the screen: a half-built ceremony left up with
			-- a full-screen scrim over it would lock the player out of the game.
			warn("[CrateCeremony] " .. tostring(err))
			pcall(function()
				gui.Enabled = false
				for _, c in ipairs(gui:GetChildren()) do c:Destroy() end
			end)
		end
	end)
	return true
end

function M.isPlaying(): boolean
	return running
end

return M
