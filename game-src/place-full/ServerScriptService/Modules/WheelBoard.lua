-- WheelBoard: the physical daily-spin wheel you walk up to.
--
-- Sits due east of the leaderboard arc at the same radius, facing back into it, so the
-- three boards and the wheel read as one ring you stand inside.
--
-- The wheel FACE is a fully transparent square part carrying a SurfaceGui. Drawing the
-- disc in the GUI rather than out of parts is what makes clean 60-degree wedges possible
-- at all -- a part-built pie either overlaps and z-fights or leaves gaps, which is
-- exactly the trap the old stone platform fell into. A SurfaceGui renders regardless of
-- its part's transparency, so the square never shows.
--
-- Spinning rotates the GUI's inner frame, not the part, so the rim, hub and pointer can
-- stay still without counter-rotating.
--
-- Built at runtime but ADOPTED if already present at the current LayoutVersion, the same
-- as the leaderboards: drag it anywhere in Studio and a server start will not move it.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WheelConfig = require(ReplicatedStorage.Modules.WheelConfig)

local M = {}
local C = Color3.fromRGB

-- Bumped to 5: the floating CallOut was scaled down. Build() early-returns when the
-- existing model's LayoutVersion matches, so a geometry change that does NOT bump this
-- silently never reaches the wheel already sitting in the place.
-- 6 (2026-08-18): the wheel's PRIZES changed (loot crate / 150 emeralds / the pro
-- wheel spinner title). This number is the only thing that reaches a wheel already
-- standing in the place -- buildSite adopts an existing model untouched when the
-- version matches, so without a bump the CHANCES plaque and the wheel face keep
-- advertising whatever WheelConfig said the day the model was first built. That is
-- exactly what happened: the sign was still listing $1,000 / $100,000 / $2,500,000
-- after the payouts had already changed underneath it.
--
-- 7 (2026-08-19): the wedge ICONS changed -- drawn IconArt instead of emoji, after
-- the emerald wedge was caught advertising a blue DIAMOND. Exactly the case this
-- number exists for, and the proof it was needed: the wheels standing in the place
-- were still built from a generation whose title wedge drew a LABEL glyph, two
-- config revisions stale, because nothing had bumped this since.
--
-- Bumping is safe for placement -- see the note in buildSite: the pivot is captured
-- and restored, so a wheel someone dragged in Studio stays where they put it.
M.LAYOUT_VERSION = 7

-- leaderboard arc centre + radius, so the wheel lands opposite the boards
local ARC = Vector2.new(-29.21, -28.75)
local ARC_R = 17.0
local GROUND_Y = 4.02

local FACE_D  = 8.0      -- wheel diameter in studs
local PPS     = 60       -- SurfaceGui pixels per stud -> 480px canvas

-- The wedge icons. pcall'd because this module is on the server boot chain: a
-- fault in a UI-art module must not be able to take the whole wheel -- and with
-- it Main's Init -- down. Nil here just means every wedge falls back to its glyph.
local okIconArt, IconArt = pcall(function()
	return require(game:GetService("ReplicatedStorage").Modules.UIKit.IconArt)
end)
if not okIconArt then
	warn("[WheelBoard] IconArt unavailable, wedges fall back to glyphs: " .. tostring(IconArt))
	IconArt = nil
end
local HUB_Y   = GROUND_Y + 7.2   -- centre height of the wheel

local WOOD_D = C(104, 66, 38)
local WOOD_M = C(170, 116, 68)
local INK    = C(12, 9, 7)
local CREAM  = C(255, 242, 219)
local AMBER  = C(255, 200, 96)

-- WHERE THE WHEEL STANDS. One row per world; adding a world is adding a row.
-- The valley row keeps the historical model name and the coordinates baked into
-- construct(), so nothing about world 1 moves. World 2 gets its own copy on the
-- walk from the return portal to the hub dome.
-- LookAt turns the built wheel so its FACE points at that spot -- construct()
-- orients everything to the valley arc, which means nothing out in the tundra.
M.SITES = {
	{ Name = "DailyWheel" },
	-- World 2 blockout (2026-09-19): the +X side of the Avenue's mouth, just north of
	-- the Warming Circle, facing the Avenue. The leaderboards sit opposite at -8045 (see
	-- LeaderboardBoards.TUNDRA_AT), so the two flank the walk up to the camps.
	{ Name = "DailyWheelTundra",
	  Pivot  = CFrame.new(-7955, 2001.8, -8128),
	  LookAt = Vector3.new(-8000, 2001.8, -8128) },
}

local built = nil     -- the valley wheel, for the single-wheel accessors
local builtAll = {}   -- every wheel in the place, in SITES order

local function part(parent, name, size, cf, colour, material, transparency)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf
	p.Color = colour or WOOD_D
	p.Material = material or Enum.Material.Wood
	p.Transparency = transparency or 0
	p.Anchored = true; p.CanCollide = true; p.CanQuery = true; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function label(parent, name, size, pos, text, colour, textSize, align)
	local l = Instance.new("TextLabel")
	l.Name = name; l.Size = size; l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text; l.TextColor3 = colour; l.TextSize = textSize
	l.Font = Enum.Font.FredokaOne
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.TextStrokeColor3 = INK; l.TextStrokeTransparency = 0.4
	l.RichText = false
	l.Parent = parent
	return l
end

--============================== the wheel face =============================--
-- Same fan-of-bars construction as the old panel, and the same gotcha applies:
-- GuiObject.Rotation pivots about an object's CENTRE, not its AnchorPoint, so each bar
-- is centred at half radius along its own ray.
local function drawWheel(gui, px)
	local R = px / 2
	local SLOTS, N = WheelConfig.SLOTS, #WheelConfig.SLOTS
	local SEG = 360 / N

	local mask = Instance.new("Frame")
	mask.Name = "Mask"
	mask.Size = UDim2.fromScale(1, 1)
	mask.BackgroundColor3 = C(26, 32, 26)
	mask.BorderSizePixel = 0
	mask.ClipsDescendants = true
	mask.Parent = gui
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0.5, 0)
	cr.Parent = mask

	local spinner = Instance.new("Frame")
	spinner.Name = "Spinner"
	spinner.Size = UDim2.fromScale(1, 1)
	spinner.BackgroundTransparency = 1
	spinner.Parent = mask

	local function radial(frame, angleDeg, len)
		local a = math.rad(angleDeg)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.new(0.5, math.sin(a) * len / 2, 0.5, -math.cos(a) * len / 2)
		frame.Rotation = angleDeg
	end

	local STEP = 2
	local barW = math.ceil(2 * R * math.sin(math.rad(STEP) / 2)) + 3
	for i, slot in ipairs(SLOTS) do
		for b = 0, math.floor(SEG / STEP) - 1 do
			local bar = Instance.new("Frame")
			bar.Name = ("S%dB%d"):format(i, b)
			bar.Size = UDim2.fromOffset(barW, R)
			bar.BackgroundColor3 = slot.Colour
			bar.BorderSizePixel = 0
			bar.Parent = spinner
			radial(bar, (i - 1) * SEG + b * STEP + STEP / 2, R)
		end
	end
	for i = 1, N do
		local sp = Instance.new("Frame")
		sp.Name = "Spoke" .. i
		sp.Size = UDim2.fromOffset(4, R)
		sp.BackgroundColor3 = INK
		sp.BackgroundTransparency = 0.3
		sp.BorderSizePixel = 0
		sp.ZIndex = 2
		sp.Parent = spinner
		radial(sp, (i - 1) * SEG, R)
	end
	--[[ DRAWN ART, NOT EMOJI (2026-08-19, owner: "there's a diamond icon when we
	use gems"). Every wedge used to print slot.Icon, and the emerald wedge's glyph
	is U+1F48E -- a blue DIAMOND. It was advertising the wrong currency on the one
	surface a player reads before deciding to spin.

	These are the same IconArt drawings the on-screen wheel and the rest of the HUD
	use, so the physical wheel and the panel now show one set of pictures rather
	than two. IconArt builds plain Frames, which a SurfaceGui renders exactly like
	any other GUI -- and being built on the server, they replicate with the model.

	The glyph stays as the fallback: a slot with no Art key, or an Art key IconArt
	does not know, still draws something rather than an empty wedge. ]]
	local ICON = 52
	for i, slot in ipairs(SLOTS) do
		local mid = math.rad((i - 1) * SEG + SEG / 2)
		local r = R * 0.62
		local holder = Instance.new("Frame")
		holder.Name = "L" .. i
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Size = UDim2.fromOffset(120, ICON + 36)
		holder.Position = UDim2.new(0.5, math.sin(mid) * r, 0.5, -math.cos(mid) * r)
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Rotation = (i - 1) * SEG + SEG / 2
		holder.ZIndex = 3
		holder.Parent = spinner

		local drew = false
		if IconArt and slot.Art and IconArt.has(slot.Art) then
			local box = Instance.new("Frame")
			box.Name = "Art"
			box.AnchorPoint = Vector2.new(0.5, 0)
			box.Position = UDim2.new(0.5, 0, 0, 0)
			box.Size = UDim2.fromOffset(ICON, ICON)
			box.BackgroundTransparency = 1
			box.BorderSizePixel = 0
			box.ZIndex = 3
			box.Parent = holder
			drew = IconArt.draw(box, slot.Art, ICON, 3) ~= nil
		end
		if not drew then
			label(holder, "Glyph", UDim2.fromOffset(120, ICON), UDim2.fromOffset(0, 0),
				slot.Icon, C(255, 255, 255), 34).ZIndex = 3
		end
		label(holder, "Text", UDim2.fromOffset(120, 32), UDim2.fromOffset(0, ICON + 2),
			slot.Short, C(255, 255, 255), 24).ZIndex = 3
	end
	return spinner
end

--=================================== build =================================--
local function construct(parent, name)
	local model = Instance.new("Model")
	model.Name = name or "DailyWheel"
	model.Parent = parent

	-- due east of the arc, turned to face back into it (LookVector -X => yaw +90)
	local pos0 = Vector3.new(ARC.X + ARC_R, 0, ARC.Y)
	local facing = CFrame.new(pos0) * CFrame.Angles(0, math.rad(90), 0)

	-- Two side posts, not one central one. A single post up the middle sat in FRONT of
	-- the face plane and covered the hub and the bottom two wedges; flanking posts hold
	-- the wheel at the hub the way a real carnival wheel is mounted and leave the face
	-- completely clear.
	local RIM_R = (FACE_D + 0.9) / 2
	local POST_X = RIM_R + 0.75
	local base = part(model, "Base", Vector3.new(POST_X * 2 + 1.6, 0.8, 4.0),
		facing * CFrame.new(0, GROUND_Y + 0.4, 0), WOOD_M)
	model.PrimaryPart = base
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "Post", Vector3.new(1.0, HUB_Y - GROUND_Y - 0.4, 1.0),
			facing * CFrame.new(sx * POST_X, (HUB_Y + GROUND_Y + 0.4) / 2, 0), WOOD_D)
	end
	-- stub axle bridging each post to the wheel, so it reads as mounted rather than floating
	for _, sx in ipairs({ -1, 1 }) do
		local axle = part(model, "Axle", Vector3.new(0.5, 0.5, POST_X - RIM_R + 0.6),
			facing * CFrame.new(sx * (RIM_R + (POST_X - RIM_R) / 2), HUB_Y, 0.28)
				* CFrame.Angles(0, math.rad(90), 0), WOOD_M)
		axle.Shape = Enum.PartType.Cylinder
		axle.CanCollide = false
	end

	-- backing disc, a touch larger than the face so it reads as a rim
	part(model, "Rim", Vector3.new(0.5, FACE_D + 0.9, FACE_D + 0.9),
		facing * CFrame.new(0, HUB_Y, 0.28) * CFrame.Angles(0, math.rad(90), 0),
		WOOD_D, Enum.Material.Wood).Shape = Enum.PartType.Cylinder

	-- the face itself: invisible, exists only to carry the SurfaceGui
	local face = part(model, "Face", Vector3.new(FACE_D, FACE_D, 0.2),
		facing * CFrame.new(0, HUB_Y, 0), CREAM, Enum.Material.SmoothPlastic, 1)
	face.CanCollide = false
	-- Invisible AND click-through. Unlike the leaderboards, this SurfaceGui has nothing
	-- interactive on it, so it needs no hit testing -- and an 8x8 invisible slab that
	-- swallows every viewport click in front of the wheel makes the thing miserable to
	-- edit in Studio. Locked keeps it out of click-selection but still in the Explorer.
	face.CanQuery = false
	face.Locked = true

	local gui = Instance.new("SurfaceGui")
	gui.Name = "WheelFace"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = face
	drawWheel(gui, FACE_D * PPS)

	local hub = part(model, "Hub", Vector3.new(0.45, 1.5, 1.5),
		facing * CFrame.new(0, HUB_Y, -0.28) * CFrame.Angles(0, math.rad(90), 0), WOOD_M)
	hub.Shape = Enum.PartType.Cylinder
	hub.CanCollide = false

	-- Pointer at 12 o'clock. A square turned 45 degrees in the wheel's own plane reads as
	-- a downward arrowhead, which a plain block did not. Its tip is sunk slightly into the
	-- rim so it looks fitted; that sits at a different depth from the rim, so no z-fight.
	local ptr = part(model, "Pointer", Vector3.new(1.15, 1.15, 0.35),
		facing * CFrame.new(0, HUB_Y + (FACE_D + 0.9) / 2 + 0.42, -0.45)
			* CFrame.Angles(0, 0, math.rad(45)), AMBER, Enum.Material.SmoothPlastic)
	ptr.CanCollide = false

	-- headboard: title + live state, on a SurfaceGui so it is readable from a distance
	local sign = part(model, "Sign", Vector3.new(7.6, 2.0, 0.4),
		facing * CFrame.new(0, HUB_Y + FACE_D / 2 + 2.1, 0), WOOD_M)
	local sgui = Instance.new("SurfaceGui")
	sgui.Name = "SignFace"
	sgui.Face = Enum.NormalId.Front
	sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sgui.PixelsPerStud = 60
	sgui.LightInfluence = 0
	sgui.Parent = sign
	local sbg = Instance.new("Frame")
	sbg.Size = UDim2.fromScale(1, 1)
	sbg.BackgroundColor3 = C(28, 44, 30)
	sbg.BorderSizePixel = 0
	sbg.Parent = sgui
	label(sbg, "Title", UDim2.new(1, 0, 0, 58), UDim2.new(0, 0, 0, 4), "DAILY SPIN", AMBER, 44)
	label(sbg, "State", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 62), "", CREAM, 28)

	-- odds plaque beside the wheel, so the in-world version still shows the chances
	-- clear of the new side post, which now occupies +/- POST_X
	local plaque = part(model, "Odds", Vector3.new(4.4, 5.6, 0.4),
		facing * CFrame.new(-(POST_X + 3.2), HUB_Y - 0.4, 0)
			* CFrame.Angles(0, math.rad(-24), 0), WOOD_M)
	local pgui = Instance.new("SurfaceGui")
	pgui.Name = "OddsFace"
	pgui.Face = Enum.NormalId.Front
	pgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	pgui.PixelsPerStud = 60
	pgui.LightInfluence = 0
	pgui.Parent = plaque
	local pbg = Instance.new("Frame")
	pbg.Size = UDim2.fromScale(1, 1)
	pbg.BackgroundColor3 = C(28, 44, 30)
	pbg.BorderSizePixel = 0
	pbg.Parent = pgui
	label(pbg, "Head", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 6), "CHANCES", AMBER, 30)

	-- Listed by odds, highest first. The WHEEL itself stays interleaved on purpose -- the
	-- two boosts sit opposite each other and the 1% jackpot between two commons, so the
	-- pointer is never parked beside two big prizes. Only the readout is sorted.
	local ordered = table.clone(WheelConfig.SLOTS)
	table.sort(ordered, function(a, b)
		if a.Weight ~= b.Weight then return a.Weight > b.Weight end
		-- Tie-break for the two 15% boosts. Was `a.Amount ~= nil and b.Amount == nil`,
		-- which stopped meaning anything when slots moved from a single Kind/Amount
		-- pair to a Grants list -- Amount is nil on every slot now, so it silently
		-- degraded to "equal". Id is stable and always present.
		return a.Id < b.Id
	end)

	for i, slot in ipairs(ordered) do
		local y = 50 + (i - 1) * 46
		local sw = Instance.new("Frame")
		sw.Size = UDim2.fromOffset(8, 34)
		sw.Position = UDim2.fromOffset(10, y)
		sw.BackgroundColor3 = slot.Colour
		sw.BorderSizePixel = 0
		sw.Parent = pbg
		label(pbg, "N" .. i, UDim2.fromOffset(150, 34), UDim2.fromOffset(26, y),
			slot.Label, CREAM, 21, Enum.TextXAlignment.Left)
		-- OddsShort, not OddsText: this column is 70px and OddsText appends "(1 in N)"
		-- for anything under 10%, which would overrun it. Derived either way -- not
		-- slot.Weight directly, which only reads as a percentage while the weights
		-- happen to total 100.
		label(pbg, "O" .. i, UDim2.fromOffset(70, 34), UDim2.fromOffset(186, y),
			WheelConfig.OddsShort(slot), AMBER, 21, Enum.TextXAlignment.Right)
	end

	-- the thing you actually walk up to
	local promptPart = part(model, "PromptPart", Vector3.new(3.0, 5.0, 3.0),
		facing * CFrame.new(0, GROUND_Y + 2.5, -2.2), CREAM, Enum.Material.SmoothPlastic, 1)
	promptPart.CanCollide = false
	-- ProximityPrompt fires on distance, not raycasts, so this needs no hit testing either
	promptPart.CanQuery = false
	promptPart.Locked = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SpinPrompt"
	prompt.ActionText = "Spin"
	prompt.ObjectText = "Daily Wheel"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart

	-- Orange ring on the ground marking the walk-in zone. Built from segments rather than
	-- one disc so it reads as an outline, and every segment is sized off the chord at its
	-- INNER radius, so neighbours meet without overlapping.
	local RING_R, RING_W, RING_N = 13.0, 0.75, 64
	local dRing = 2 * math.pi / RING_N
	local segLen = 2 * (RING_R - RING_W / 2) * math.sin(dRing / 2)
	for k = 1, RING_N do
		local a = (k - 0.5) * dRing
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local pos = Vector3.new(pos0.X, GROUND_Y + 0.06, pos0.Z) + dir * RING_R
		local seg = Instance.new("Part")
		seg.Name = "ZoneRing"
		seg.Size = Vector3.new(segLen + 0.04, 0.12, RING_W)
		seg.CFrame = CFrame.lookAt(pos, pos + dir)
		seg.Color = Color3.fromRGB(255, 146, 40)
		seg.Material = Enum.Material.Neon
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CastShadow = false
		seg.Locked = true          -- decoration; never steal a viewport click
		seg.Parent = model
	end

	-- Floating call-out above the wheel: a big SPIN and a live countdown.
	-- It used to be sized to be "readable from across the map" -- which is exactly the
	-- problem, since a screen-space billboard does not shrink with distance the way a
	-- SurfaceGui does. It is now capped (below) AND scaled to ~2/3, so it reads as a
	-- marker above the wheel instead of a HUD element pinned over the world.
	local callAnchor = part(model, "CallAnchor", Vector3.new(0.6, 0.6, 0.6),
		facing * CFrame.new(0, HUB_Y + FACE_D / 2 + 5.4, 0), CREAM, Enum.Material.SmoothPlastic, 1)
	callAnchor.CanCollide = false
	callAnchor.CanQuery = false
	callAnchor.Locked = true
	local bb = Instance.new("BillboardGui")
	bb.Name = "CallOut"
	bb.Size = UDim2.fromOffset(200, 80)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false
	-- 220 read as "always on" in practice -- the wheel sits in the plaza and the callout
	-- was legible from most of the camp. 140 keeps it a landmark you notice on approach.
	bb.MaxDistance = 140
	bb.Parent = callAnchor
	-- heights scaled with the frame; TextScaled means the glyphs follow automatically
	local big = label(bb, "Big", UDim2.new(1, 0, 0, 42), UDim2.new(0, 0, 0, 0),
		"SPIN", Color3.fromRGB(255, 158, 38), 36)
	big.TextScaled = true
	local sub = label(bb, "Sub", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 44),
		"", Color3.fromRGB(126, 255, 148), 20)
	sub.TextScaled = true

	model:SetAttribute("LayoutVersion", M.LAYOUT_VERSION)
	return model
end

local function bind(model)
	local face = model:FindFirstChild("Face")
	local gui = face and face:FindFirstChildOfClass("SurfaceGui")
	local mask = gui and gui:FindFirstChild("Mask")
	local spinner = mask and mask:FindFirstChild("Spinner")
	local sign = model:FindFirstChild("Sign")
	local sbg = sign and sign:FindFirstChildOfClass("SurfaceGui")
	local state = sbg and sbg:FindFirstChildOfClass("Frame") and sbg:FindFirstChildOfClass("Frame"):FindFirstChild("State")
	local prompt = model:FindFirstChild("PromptPart")
		and model.PromptPart:FindFirstChildOfClass("ProximityPrompt")
	local anchor = model:FindFirstChild("CallAnchor")
	local callOut = anchor and anchor:FindFirstChildOfClass("BillboardGui")
	local callSub = callOut and callOut:FindFirstChild("Sub")
	if not (spinner and state and prompt) then return nil end
	-- Applied on adopt as well as on build, so a wheel authored before this change stops
	-- swallowing viewport clicks without needing a LayoutVersion bump (which would drag
	-- it back to the coded coordinates and undo any repositioning).
	for _, n in ipairs({ "Face", "PromptPart" }) do
		local d = model:FindFirstChild(n)
		if d then d.CanQuery = false; d.Locked = true end
	end
	return { Model = model, Spinner = spinner, State = state, Prompt = prompt, CallSub = callSub }
end

-- Turn a freshly built wheel so its face looks at `lookAt`. construct() aims
-- everything at the valley arc, so a wheel pivoted into another world would
-- otherwise present its back to the path.
local function aim(model, lookAt)
	local face = model:FindFirstChild("Face")
	if not face then return end
	local pivot = model:GetPivot()
	local cur = face.CFrame.LookVector
	cur = Vector3.new(cur.X, 0, cur.Z)
	local want = Vector3.new(lookAt.X - pivot.X, 0, lookAt.Z - pivot.Z)
	if cur.Magnitude < 1e-3 or want.Magnitude < 1e-3 then return end
	cur, want = cur.Unit, want.Unit
	local yaw = math.atan2(want.X, want.Z) - math.atan2(cur.X, cur.Z)
	model:PivotTo(pivot * CFrame.Angles(0, yaw, 0))
end

-- Drop a model until its lowest point rests on whatever floor is under it. The
-- geometry is built around the valley's GROUND_Y, so a site pivot alone leaves the
-- wheel part-buried (measured: 0.4 studs into the tundra ice).
local function seat(model)
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Y - size.Y / 2
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local hit = Workspace:Raycast(Vector3.new(cf.X, bottom + 8, cf.Z), Vector3.new(0, -100, 0), params)
	if not hit then return end
	model:PivotTo(model:GetPivot() + Vector3.new(0, hit.Position.Y - bottom, 0))
end

local function buildSite(gw, site, force)
	local existing = gw:FindFirstChild(site.Name)
	if existing and not force and existing:GetAttribute("LayoutVersion") == M.LAYOUT_VERSION then
		local b = bind(existing)
		if b then return existing, b, "reused" end
	end
	-- PRESERVE THE PLACED POSITION ACROSS A REBUILD.
	-- LAYOUT_VERSION exists so a GEOMETRY change reaches a wheel already sitting in the
	-- place. But the rebuild also snapped it back to the hardcoded ARC spot, so bumping the
	-- version silently teleported a wheel someone had dragged in Studio -- measured as a
	-- 45.2 stud jump on X (33.00 -> -12.21) when a version-4 model met code wanting 5. That
	-- is what made the wheel "appear somewhere else in play mode" with nothing in the place
	-- to explain it. Capturing the pivot and restoring it means position now survives every
	-- future bump, while the adopt-if-current path above still skips the rebuild entirely.
	-- Note: with no PrimaryPart the pivot is the bounding-box centre, so a bump that changes
	-- the overall bounds can still shift it by a stud or so. Vastly better than 45.
	local keepPivot = existing and existing:GetPivot() or nil
	if existing then existing:Destroy() end
	local model = construct(gw, site.Name)
	-- A wheel already placed in the world always wins, exactly as before; a site
	-- pivot only ever positions a wheel being built for the first time.
	if keepPivot then
		model:PivotTo(keepPivot)
	elseif site.Pivot then
		model:PivotTo(site.Pivot)
		if site.LookAt then aim(model, site.LookAt) end
		seat(model)
	end
	return model, bind(model), "built"
end

function M.Build(force)
	local gw = Workspace:FindFirstChild("GameWorld") or Workspace
	table.clear(builtAll)
	local firstModel, firstHow
	for _, site in ipairs(M.SITES) do
		local model, handle, how = buildSite(gw, site, force)
		if handle then
			handle.Site = site
			table.insert(builtAll, handle)
		end
		firstModel = firstModel or model
		firstHow = firstHow or how
	end
	built = builtAll[1]
	return firstModel, firstHow or "built"
end

function M.Get() return built end

-- every wheel in the place; WheelHandler binds a prompt on each
function M.All() return builtAll end

-- sign text: ready, or how long until the next free spin. Fans out: both worlds'
-- wheels show the same countdown, because the cooldown is per PLAYER not per wheel.
function M.SetState(text)
	for _, b in ipairs(builtAll) do
		if b.State then b.State.Text = text end
		if b.CallSub then b.CallSub.Text = text end
	end
end

function M.SetPromptEnabled(on)
	for _, b in ipairs(builtAll) do
		if b.Prompt then b.Prompt.Enabled = on and true or false end
	end
end

return M
