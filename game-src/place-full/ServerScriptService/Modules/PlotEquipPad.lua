-- PlotEquipPad -- the walk-over pad that offers to put your best brainrots out.
--
-- Stepping on it asks the CLIENT to confirm; saying yes fires the EquipBest remote
-- that InventoryHandler already owns. No new placement logic exists here and none
-- should: EquipBest already ranks by cash/sec x mutation, respects UnlockedSpots,
-- pulls down anything that no longer makes the cut and leaves correct pads alone.
-- This module is a door onto it, nothing more.
--
-- WHERE THE PAD GOES, and why it is computed rather than placed by hand: twelve
-- plots across two worlds, and the obvious spot -- out past the pad ring on the
-- side you walk in from -- does not exist on six of them. The pads sit in a RING
-- reaching 23 studs from the campfire, and while a Valley platform runs 32-51
-- studs that way, a Tundra platform (46x59, not 57x57) runs as little as 23. So
-- there is no room on the platform at all on Tundra plots 7, 8, 11 and 12.
--
-- What IS consistent is the PlotBoard: every plot has one, 31-34 studs out, and
-- it marks the way in. Measured on all twelve, there is solid ground a few studs
-- inside it -- Terrain or Platform in the Valley, OuterApron/TrailPatch/Platform
-- in the Tundra -- so the pad is dropped THERE, ground found by a downward ray at
-- build time rather than assumed. That also keeps it clear of the pad ring by a
-- wide margin (31 out against a 23-stud reach) on every plot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlotBoardHandler = require(ServerScriptService.Modules.PlotBoardHandler)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local PlotEquipPad = {}
local inited = false

local PAD_NAME = "EquipBestPad"
-- 5x5, matching a brainrot pad exactly. Measured at the fixed spot padCFrame now
-- uses, 6x6 clears the sign's PostL on Plot7 by only 0.45 studs; 5x5 clears it by
-- 0.95. (BACK_FROM_BOARD retired with the old search -- the spot is a plot-local
-- polar coordinate now, see padCFrame.)
local PAD_SIZE = Vector3.new(5, 0.4, 5)
-- daylight required around the pad before a spot is accepted
local PAD_MARGIN = 0.4

-- Token values MIRRORED, not required: UIKit is never required server-side
-- (UIKit.Builders' own header says so). Keep these in lockstep with UIKit.Tokens
-- gradient.green and color.outline.
local PAD_COLOR  = Color3.fromRGB(79, 180, 46)   -- Tokens gradient.green bottom #4FB42E
local PAD_HILITE = Color3.fromRGB(131, 227, 74)  -- Tokens gradient.green top    #83E34A
local PAD_RIM    = Color3.fromRGB(49, 61, 79)    -- Tokens color.outline         #313D4F

-- One prompt per player per this many seconds. Touched fires many times a second
-- while a character stands on a part, and the confirm is a screen-covering panel.
local PROMPT_COOLDOWN = 2.5
local lastPrompt = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = remotes
	end
	return r
end
-- server -> client: "you stepped on your pad, ask them"
local promptRemote = getRemote("EquipPadPrompt", "RemoteEvent")

-- === GEOMETRY =================================================================
-- Returns the world CFrame the pad should sit at, or nil if this plot has nothing
-- to measure against.
-- Half-extents in world axes, for a part at any rotation.
local function halvesOf(d)
	local cf, s = d.CFrame, d.Size
	return 0.5*(math.abs(cf.RightVector.X)*s.X + math.abs(cf.UpVector.X)*s.Y + math.abs(cf.LookVector.X)*s.Z),
	       0.5*(math.abs(cf.RightVector.Y)*s.X + math.abs(cf.UpVector.Y)*s.Y + math.abs(cf.LookVector.Y)*s.Z),
	       0.5*(math.abs(cf.RightVector.Z)*s.X + math.abs(cf.UpVector.Z)*s.Y + math.abs(cf.LookVector.Z)*s.Z)
end

-- Is a 6x6 pad centred here fouling anything?
--
-- Ground is NOT an obstacle -- the pad is meant to rest on the platform, the apron or the
-- terrain. So the only things that count are parts whose top rises ABOVE the pad's own
-- surface (the fence logs, the board posts, props) plus the brainrot pad ring, which is
-- flat and would otherwise pass this test while still being a place the pad must not sit.
-- 1.2 rather than 0.5: at 0.5 the chosen spot still grazed the sign's Board/Brace/PostR
-- by a few tenths of a stud, which reads as the pad tucked under the sign. 1.2 pushes it
-- to a spot that visibly clears the whole board.
-- WORST OVERLAP at a candidate spot: 0 means nothing is in the way. Only things a
-- walking player would hit count -- parts occupying the band from just above the pad
-- surface to body height, plus the brainrot pad ring (flat, but reserved ground).
-- The sign's Cap and SignLamp hang above that band and are correctly ignored.
local BODY_H = 5.0
local function worstOverlapAt(plot, centre, topY)
	local hx, hz = PAD_SIZE.X / 2 + PAD_MARGIN, PAD_SIZE.Z / 2 + PAD_MARGIN
	local ownPad = plot:FindFirstChild(PAD_NAME)
	local worst, who = 0, nil
	for _, d in ipairs(plot:GetDescendants()) do
		-- Exclude our own pad BY ANCESTRY, not by name: the pad now has a PadRim child
		-- part, and every brainrot pad also has a child called "Rim" which IS a real
		-- obstacle -- so a name test would exclude the wrong ones.
		local mine = ownPad ~= nil and (d == ownPad or d:IsDescendantOf(ownPad))
		if d:IsA("BasePart") and not mine and d.Transparency < 0.95 then
			local dx = math.abs(centre.X - d.Position.X)
			local dz = math.abs(centre.Z - d.Position.Z)
			if dx < 18 and dz < 18 then
				local bhx, bhy, bhz = halvesOf(d)
				local bTop, bBot = d.Position.Y + bhy, d.Position.Y - bhy
				local inBand = bTop > topY + 0.35 and bBot < topY + BODY_H
				if inBand or d.Name:match("^Pad%d") then
					local ov = math.min((hx + bhx) - dx, (hz + bhz) - dz)
					if ov > worst then worst = ov who = d end
				end
			end
		end
	end
	return worst, who
end

-- Returns the world CFrame the pad should sit at, or nil if this plot has nothing
-- to measure against.
--
-- WHERE THE PAD GOES (2026-08-19 rewrite). ONE fixed plot-local polar coordinate,
-- not a search.
--
-- SUPERSEDES the 2026-08-14 direction that put the pad in among the brainrot ring
-- "where the player actually stands". That version swept WORLD-axis angles and
-- ranked survivors with a soft score whose two terms were the same magnitude, so
-- the winner was decided by whichever candidate the world-aligned 5-degree grid
-- happened to drop into a gap in that plot's camp dressing. Replayed against the
-- live plots it settled at +94 deg on Plot3, -62 on Plot1, +115 on Plot2, +132 on
-- Plot9 and -132 on Plot10 -- a 194-degree spread across twelve plots with
-- IDENTICAL local layouts. That is the "weird spot on some plots" report, and it
-- is why the ring placement had to go: measurement says "in among the ring" and
-- "the same place on every plot" cannot both be true.
--
-- WHY 30 STUDS AND NOT AMONG THE RING: no interior spot is clear on every plot.
-- The brainrot ring reaches 23 studs (centres 20.5 + 2.5 half) and the VALLEY
-- plots are fenced at exactly 27.0, leaving a 4-stud annulus a 5x5 pad cannot sit
-- in; the tundra plots have no fence at all. 30 studs out puts it just outside the
-- fence, beside the sign, on the approach -- clear on all 18 plots.
--
-- WHY -20 AND NOT -90: +/-90 is blocked by the fence logs on every valley plot.
-- -20 is the only bearing family clear everywhere, and it is LEFT of the walk-in
-- line on purpose -- the valley gate posts sit at +3..+48 degrees, so the right
-- side is the gate mouth.
local PAD_BEARING = -20                        -- degrees off the campfire->sign line
local PAD_RADII   = { 30, 31, 29, 32, 28 }     -- tried in this order

local function padCFrame(plot)
	local fire  = plot:FindFirstChild("Campfire")
	local board = plot:FindFirstChild("PlotBoard")
	if not (fire and board) then return nil end
	local centre = fire.Position

	-- The plot's OWN forward: campfire -> sign, i.e. the way the player walks in.
	-- Everything below is expressed in this frame, so the spot rotates WITH the plot
	-- instead of being sampled off world X/Z.
	local b = board:GetPivot().Position
	local flat = Vector3.new(b.X - centre.X, 0, b.Z - centre.Z)
	if flat.Magnitude < 1 then return nil end
	local fwd = flat.Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { plot:FindFirstChild(PAD_NAME) }

	local function tryAt(bearing, r)
		local a = math.rad(bearing)
		local dir = Vector3.new(fwd.X * math.cos(a) + fwd.Z * math.sin(a), 0,
		                        -fwd.X * math.sin(a) + fwd.Z * math.cos(a))
		local spot = centre + dir * r
		-- Ground is RAYCAST, never assumed: the platform floats over terrain by a
		-- different amount per plot, and the tundra plots land on OuterApron, not
		-- Platform. No footprint test -- the ray IS the test. (The old onPlatform
		-- approximated the slab as a circle of the SHORT side, which threw away the
		-- entire 59-stud long axis of every 46x59 tundra platform.)
		local hit = Workspace:Raycast(spot + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), params)
		if not hit or math.abs(hit.Position.Y - centre.Y) > 4 then return nil end
		local y = hit.Position.Y
		local at = Vector3.new(spot.X, y + PAD_SIZE.Y / 2, spot.Z)
		if worstOverlapAt(plot, at, y + PAD_SIZE.Y) > 0 then return nil end
		return at
	end

	-- Preferred bearing first, then out in fixed 5-degree steps (0, +5, -5, +10, ...).
	-- Deterministic and BOUNDED -- it can never jump to the far side of the camp the
	-- way the old score could. Measured: every live plot (1-12) takes deviation 0.
	for dev = 0, 60, 5 do
		local signs = (dev == 0) and { 1 } or { 1, -1 }
		for _, s in ipairs(signs) do
			for _, r in ipairs(PAD_RADII) do
				local at = tryAt(PAD_BEARING + s * dev, r)
				if at then
					return CFrame.lookAt(at, Vector3.new(centre.X, at.Y, centre.Z))
				end
			end
		end
	end
	return nil
end

-- === BUILD ====================================================================
-- PS99 white chrome, mirrored from UIKit BY HAND -- UIKit is never required
-- server-side, and UIPolish only walks PlayerGui, so a Workspace billboard is the
-- one label family in the game that gets nothing for free and must carry its own
-- styling. Shape follows UI.button / PanelChrome.plate: corner + gradient +
-- outline stroke + gloss + hard offset shadow. CHROME, not naked text, because the
-- pad is interactive -- under the house grammar naked floating text reads as a
-- read-only sign, which is exactly the "no design" report.
local function chromePlate(parent, name, size, pos, anchor, top, bottom, radius, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	f.BackgroundColor3 = top
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, radius); c.Parent = f
	local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(top, bottom); g.Rotation = 90; g.Parent = f
	local s = Instance.new("UIStroke")
	s.Thickness = 4                       -- Tokens.stroke.control
	s.Color = PAD_RIM                     -- Tokens.color.outline #313D4F
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- Border, not Contextual: must not eat the glyphs
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = f
	return f
end

local function buildLabel(pad)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(232, 98)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.0, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	-- Start hidden: EquipPadClient turns it on for the OWNER only. Without this,
	-- every plot's label is visible from replication until that first pass runs.
	gui.Enabled = false
	gui.Parent = pad

	-- hard offset shadow (Tokens.shadowOffset.control = 5), the kit's only shadow
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = PAD_RIM
	shadow.BackgroundTransparency = 0.45
	shadow.BorderSizePixel = 0
	shadow.Position = UDim2.fromOffset(0, 5)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.ZIndex = 1
	shadow.Parent = gui
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 18); sc.Parent = shadow

	-- white shell (Tokens.gradient.panel #FFFFFF -> #EFF3F9, Tokens.radius.control 18)
	local shell = chromePlate(gui, "Shell", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), Vector2.new(0, 0),
		Color3.fromRGB(255, 255, 255), Color3.fromRGB(239, 243, 249), 18, 2)

	-- top gloss, the kit's one-light-source highlight
	local hi = Instance.new("Frame")
	hi.Name = "Highlight"
	hi.BackgroundColor3 = Color3.new(1, 1, 1)
	hi.BackgroundTransparency = 0.58
	hi.BorderSizePixel = 0
	hi.Size = UDim2.new(1, 0, 0, 4)
	hi.ZIndex = 3
	hi.Parent = shell
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 18); hc.Parent = hi

	-- coloured bubble title (Tokens.gradient.green, Tokens.radius.chip 12)
	local bubble = chromePlate(shell, "Bubble", UDim2.new(1, -16, 0, 46), UDim2.new(0.5, 0, 0, 8),
		Vector2.new(0.5, 0), PAD_HILITE, PAD_COLOR, 12, 4)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.FredokaOne          -- Tokens.font.display
	title.TextScaled = true
	title.Text = "AUTO-PLACE"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.ZIndex = 6
	title.Parent = bubble
	local ts = Instance.new("UIStroke")
	ts.Thickness = 2.5
	ts.Color = PAD_RIM
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ts.LineJoinMode = Enum.LineJoinMode.Round
	ts.Parent = title

	-- dark ink on the light shell, UNSTROKED: the house rule for light surfaces.
	-- All caps to match the kit voice (was sentence case, the only one in the game).
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 1)
	sub.Position = UDim2.new(0.5, 0, 1, -8)
	sub.Size = UDim2.new(1, -22, 0, 30)
	sub.Font = Enum.Font.FredokaOne            -- was GothamBold: the kit is one face here
	sub.TextScaled = true
	sub.Text = "STEP ON TO PLACE YOUR BEST"
	sub.TextColor3 = Color3.fromRGB(51, 65, 79) -- Tokens.color.textOnLight #33414F
	sub.ZIndex = 3
	sub.Parent = shell
end

-- Idempotent: re-running BuildAll re-seats an existing pad rather than stacking a
-- second one, which is what lets Init be safe to call twice.
function PlotEquipPad.BuildPad(plot)
	local cf = padCFrame(plot)
	if not cf then return nil end

	local pad = plot:FindFirstChild(PAD_NAME)
	if not pad then
		pad = Instance.new("Part")
		pad.Name = PAD_NAME
		pad.Parent = plot
	end
	-- Rebuilt every pass, not just on create: BuildAll is public and idempotent, and
	-- a restyle has to land on an already-built pad too (buildLabel used to run only
	-- inside the `not pad` branch, so re-running BuildAll never restyled anything).
	local staleLabel = pad:FindFirstChild("Label")
	if staleLabel then staleLabel:Destroy() end
	buildLabel(pad)
	pad.Anchored = true
	-- CanCollide FALSE so it is walked OVER, not stepped up onto -- a 0.4-stud lip
	-- in a doorway is exactly the sort of thing players get stuck on. CanTouch is
	-- what actually drives it.
	pad.CanCollide = false
	pad.CanTouch = true
	pad.CanQuery = false
	pad.Size = PAD_SIZE
	pad.CFrame = cf
	pad.Material = Enum.Material.SmoothPlastic
	pad.Color = PAD_COLOR
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth

	-- The house outline as REAL GEOMETRY. The old rim was a SelectionBox -- a Studio
	-- SELECTION adornment used as game art: an unlit 0.06 wireframe in the retired
	-- olive. Worse, its guard tested for a SpecialMesh that is never created, so
	-- every single re-run of BuildPad stacked ANOTHER SelectionBox on the pad.
	-- Clean up any that already accumulated, then keep exactly one real rim part.
	for _, d in ipairs(pad:GetChildren()) do
		if d:IsA("SelectionBox") then d:Destroy() end
	end
	local rim = pad:FindFirstChild("PadRim")
	if rim and not rim:IsA("BasePart") then rim:Destroy(); rim = nil end
	if not rim then
		-- PadRim, not "Rim": every brainrot pad already has a child called Rim, and
		-- worstOverlapAt has to be able to tell them apart.
		rim = Instance.new("Part")
		rim.Name = "PadRim"
		rim.Parent = pad
	end
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanTouch = false   -- must stay false or it double-fires the pad's Touched handler
	rim.CanQuery = false
	rim.CastShadow = false
	rim.Locked = true
	rim.Material = Enum.Material.SmoothPlastic
	rim.Color = PAD_RIM
	rim.TopSurface = Enum.SurfaceType.Smooth
	rim.BottomSurface = Enum.SurfaceType.Smooth
	rim.Size = PAD_SIZE + Vector3.new(0.9, -0.12, 0.9)
	rim.CFrame = cf * CFrame.new(0, -0.06, 0)
	return pad
end

function PlotEquipPad.BuildAll()
	local n = 0
	for _, plot in ipairs(PlotBoardHandler.Targets()) do
		if PlotEquipPad.BuildPad(plot) then n += 1 end
	end
	return n
end

-- === TRIGGER ==================================================================
-- OWNER ONLY. EquipBest acts on the player's OWN base wherever they are standing,
-- so letting someone set it off from a stranger's pad would rearrange a plot they
-- cannot see. Silent for everyone else -- a refusal toast on a pad you only walked
-- across would fire constantly.
local function onTouched(plot, hit)
	local character = hit and hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then return end
	if plot:GetAttribute("Claimed") ~= true then return end
	if plot:GetAttribute("OwnerUserId") ~= player.UserId then return end

	local now = os.clock()
	if now - (lastPrompt[player] or 0) < PROMPT_COOLDOWN then return end
	lastPrompt[player] = now

	promptRemote:FireClient(player)
end

function PlotEquipPad.Init()
	if inited then return end
	inited = true

	local built = PlotEquipPad.BuildAll()

	for _, plot in ipairs(PlotBoardHandler.Targets()) do
		local pad = plot:FindFirstChild(PAD_NAME)
		if pad then
			pad.Touched:Connect(function(hit) onTouched(plot, hit) end)
		end
	end

	Players.PlayerRemoving:Connect(function(p) lastPrompt[p] = nil end)

	print(("PlotEquipPad online (%d pads, owner-only, %.1fs cooldown)"):format(built, PROMPT_COOLDOWN))
end

return PlotEquipPad
