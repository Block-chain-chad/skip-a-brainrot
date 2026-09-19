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
-- 6x6 rather than 7x7, paired with BACK_FROM_BOARD below. A brainrot pad is 5x5,
-- so edge-to-edge needs 5.5 studs of centre separation; at 7x7 and 6 studs back,
-- Tundra plots 7 and 12 measured 5.6 and 5.7 and the pad would have clipped its
-- neighbour. These two numbers are a PAIR -- change one and re-measure clearance
-- on all twelve, the tightest plots are the tundra ones.
local PAD_SIZE = Vector3.new(6, 0.4, 6)
-- how far back from the board, along the line to the campfire. Both 5 and 7 were
-- measured to find ground on all twelve plots; 5 is used because it sits FURTHER
-- from the pad ring, which is what buys the clearance above.
local BACK_FROM_BOARD = 5
local PAD_COLOR = Color3.fromRGB(88, 190, 92)
local PAD_RIM = Color3.fromRGB(23, 26, 20)

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
	local hx, hz = PAD_SIZE.X / 2, PAD_SIZE.Z / 2
	local worst, who = 0, nil
	for _, d in ipairs(plot:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= PAD_NAME and d.Transparency < 0.95 then
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
-- 2026-08-14: the pad now sits ON THE PLATFORM, in a clear gap between the brainrot
-- pads on the walk-in side -- not out past the sign. The old placement dropped it just
-- outside the PlotBoard (30+ studs out), which read as a random spot floating off the
-- base; the ask was to have it among the pad ring where the player actually stands.
--
-- HOW: sweep the platform in polar rings (radius x angle) around the campfire and keep
-- only spots that (a) land on the Platform surface and (b) clear the pad ring and props
-- (worstOverlapAt == 0), then pick a gap OFF TO THE SIDE -- roughly perpendicular to the
-- board direction, so the pad is not underfoot the instant you walk in (owner ask,
-- 2026-08-14) -- with the most elbow room. The
-- two dense pad rings (~13 and ~20 out) leave room for a 6x6 only in the angular gaps
-- near the outer ring (~19 out), which is exactly "between the brainrot spots". Falls
-- back to the old out-past-the-board spot only if a plot has no clear interior gap.
local function padCFrame(plot)
	local fire = plot:FindFirstChild("Campfire")
	local platform = plot:FindFirstChild("Platform")
	local board = plot:FindFirstChild("PlotBoard")
	if not (fire and platform) then return nil end
	local centre = fire.Position

	-- direction from the campfire toward the sign = the way the player walks in
	local entranceDir = Vector3.new(0, 0, 1)
	if board then
		local b = board:GetPivot().Position
		local flat = Vector3.new(b.X - centre.X, 0, b.Z - centre.Z)
		if flat.Magnitude > 1 then entranceDir = flat.Unit end
	end

	-- brainrot-pad centres, for ranking how roomy a clear spot is
	local padPos = {}
	for _, d in ipairs(plot:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:match("^Pad%d") then table.insert(padPos, d.Position) end
	end
	local function roomAt(x, z)
		local best = math.huge
		for _, p in ipairs(padPos) do
			local dd = (x - p.X) * (x - p.X) + (z - p.Z) * (z - p.Z)
			if dd < best then best = dd end
		end
		return math.sqrt(best)
	end

	-- (x,z) inside the platform's own footprint, with room for the pad? This uses the
	-- Platform PART's transform, NOT "did the ray hit the Platform part": on the elevated
	-- plots the walkable surface is TERRAIN laid over the platform, so the hit-test failed
	-- there and forced every one of them to the out-past-the-board fallback.
	-- A plain horizontal radius from the platform centre -- orientation-independent (the
	-- slab is rotated so a local-axis test is fragile), and correct whether the surface is
	-- the Platform part (valley) or terrain laid over it (elevated plots). The short side
	-- minus a pad-and-margin is a safe radius for our r<=19 candidates.
	local platCentre = platform.Position
	local dims = { platform.Size.X, platform.Size.Y, platform.Size.Z }
	table.sort(dims)                      -- dims[1] = thickness, dims[2] = short side
	local footR = dims[2] / 2 - 3
	local function onPlatform(x, z)
		local dx, dz = x - platCentre.X, z - platCentre.Z
		return dx * dx + dz * dz <= footR * footR
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { plot:FindFirstChild(PAD_NAME) }

	local bestAt, bestScore
	for r = 20, 12, -1 do
		for a = 0, 355, 5 do
			local rad = math.rad(a)
			local spot = centre + Vector3.new(math.cos(rad) * r, 0, math.sin(rad) * r)
			local hit = Workspace:Raycast(spot + Vector3.new(0, 14, 0), Vector3.new(0, -50, 0), params)
			-- on the plot's own ground (near campfire level) and inside the footprint
			if hit and math.abs(hit.Position.Y - centre.Y) < 4 and onPlatform(spot.X, spot.Z) then
				local y = hit.Position.Y
				local at = Vector3.new(spot.X, y + PAD_SIZE.Y / 2, spot.Z)
				if worstOverlapAt(plot, at, y + PAD_SIZE.Y) <= 0 then
					local cand = Vector3.new(spot.X - centre.X, 0, spot.Z - centre.Z).Unit
					-- favour a SIDE gap (perpendicular to the entrance, |dot|~0) so it is not
					-- right on the walk-in line, then the roomiest such gap
					local score = -math.abs(cand:Dot(entranceDir)) * 4 + roomAt(spot.X, spot.Z) * 0.4
					if not bestScore or score > bestScore then bestScore, bestAt = score, at end
				end
			end
		end
	end

	if bestAt then
		return CFrame.lookAt(bestAt, Vector3.new(centre.X, bestAt.Y, centre.Z))
	end

	-- FALLBACK: no clear interior gap -> the old out-past-the-board spot.
	if not board then return nil end
	local b = board:GetPivot().Position
	local y = platform.Position.Y
	local spot = b - entranceDir * BACK_FROM_BOARD
	return CFrame.lookAt(Vector3.new(spot.X, y + PAD_SIZE.Y / 2, spot.Z),
		Vector3.new(centre.X, y + PAD_SIZE.Y / 2, centre.Z))
end

-- === BUILD ====================================================================
local function buildLabel(pad)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(210, 54)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 70
	gui.Parent = pad

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "AUTO-PLACE"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Parent = gui
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = PAD_RIM
	st.Parent = title

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.Text = "step on to place your best"
	sub.TextColor3 = Color3.fromRGB(226, 240, 224)
	sub.Parent = gui
	local st2 = Instance.new("UIStroke")
	st2.Thickness = 2
	st2.Color = PAD_RIM
	st2.Parent = sub
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
		buildLabel(pad)
	end
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

	if not pad:FindFirstChildOfClass("SpecialMesh") then
		local rim = Instance.new("SelectionBox")
		rim.Name = "Rim"
		rim.Adornee = pad
		rim.Color3 = PAD_RIM
		rim.LineThickness = 0.06
		rim.Transparency = 0.15
		rim.Parent = pad
	end
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
