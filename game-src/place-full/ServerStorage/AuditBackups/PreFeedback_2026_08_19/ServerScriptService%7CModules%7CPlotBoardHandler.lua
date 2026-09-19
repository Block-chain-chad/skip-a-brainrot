-- PlotBoardHandler -- Camp Board + like authority (BUILD SPEC v2, 2026-07-24)
--
-- Owns the PHYSICAL camp board: geometry, CampStand, CampNook, the LikePrompt,
-- the three RemoteEvents, and every like decision. The CLIENT owns every pixel
-- (see StarterPlayerScripts.PlotSignClient) -- this module never builds a Gui.
--
-- Dependency direction is one-way: PlotBoardHandler -> PlayerDataManager.
-- PlayerDataManager must never require this file (no circular require).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)

local PlotBoardHandler = {}

-- USER DECISION U4: build the three CampNook props in the old tent footprint.
local BUILD_CAMP_NOOK = false   -- replaced by CampBed (sleeping bag + lantern); see CampBed builder

-- ===== remotes: idempotent self-heal so a fresh clone of the place works =====
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local function ensureRemote(name)
	local r = remotes:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = remotes end
	return r
end
local likeRemote   = ensureRemote("LikePlot")
local likeResult   = ensureRemote("LikeResult")
local collectedCue = ensureRemote("CampfireCollected")

-- ===== canonical local frame (spec 0.3) =====
-- NEVER build from Platform.CFrame directly: the cylinder is rolled 90 deg and its
-- RightVector is (0,1,0).
local function plotFrame(plot)
	local plat = plot:FindFirstChild("Platform")
	if not plat then return nil end
	local lv    = plat.CFrame.LookVector
	local fwd   = Vector3.new(-lv.X, 0, -lv.Z).Unit          -- plot-local +Z
	local right = Vector3.new(fwd.Z, 0, -fwd.X)              -- plot-local +X
	local y0    = plat.Position.Y + 0.5                      -- platform TOP
	local origin = Vector3.new(plat.Position.X, y0, plat.Position.Z)
	return CFrame.fromMatrix(origin, right, Vector3.yAxis, fwd), y0, plat
end
PlotBoardHandler.PlotFrame = plotFrame

-- ===== per-plot board placement (spec 1.2.1) =====
-- Bearing (deg, plot-local) + radius per plot. Chosen so the board sits at the plot's
-- trail entrance and FACES down the trail at the approaching player.
-- RE-MEASURED 2026-08-06: the old bearings were paired/uniform (25/25, 170/170, 97/97)
-- and no longer lined up with the trails, so the boards faced off into the grass. These
-- are each plot's actual nearest-trail bearing (the baked PlotBoard models were also
-- re-aimed to match). Plots 1-3 face east toward the central trail, 4-6 face west.
local BOARD = {
	Plot1 = {  89, 24.0 }, Plot2 = {  91, 24.0 },
	Plot3 = {  66, 26.5 }, Plot4 = { 296, 26.5 },
	Plot5 = { 174, 24.0 }, Plot6 = { 179, 24.0 },
	-- WORLD 2 (2026-08-06). The tundra plots used to carry a placeholder: a bare Part
	-- named PlotBoard with a "CAMP n" label on it. buildBoardModel early-returns when a
	-- PlotBoard already exists, so that placeholder is precisely why world 2 never got
	-- a real camp board -- no nameplate, no like plaque, no prompt. Placeholder removed,
	-- and these bearings aim each board back at the middle of the camp cluster, which is
	-- where the return portal puts an arriving player.
	Plot7  = {  76, 24.0 }, Plot8  = {  93, 24.0 },
	Plot9  = { 132, 24.0 }, Plot10 = { 228, 24.0 },
	Plot11 = { 266, 24.0 }, Plot12 = { 283, 24.0 },
	BaseTemplate = { 25, 24.0 },
}
PlotBoardHandler.BOARD = BOARD

-- Ground-referenced board base (spec 1.2.2). The platform floats 1.18-2.71 studs
-- above terrain at the sign spots, so the board references TERRAIN, not the platform,
-- or the posts leave a floating stub.
-- NOTE: this is a terrain READ (raycast) only. This build performs zero terrain writes.
local function boardBase(model)
	local F, y0, plat = plotFrame(model)
	if not F then return nil end
	local cfg  = BOARD[model.Name] or BOARD.BaseTemplate
	local a    = math.rad(cfg[1])
	local anch = F * CFrame.new(math.sin(a) * cfg[2], 0, math.cos(a) * cfg[2])
	local out  = (Vector3.new(anch.X, 0, anch.Z) - Vector3.new(plat.Position.X, 0, plat.Position.Z)).Unit
	local right = Vector3.new(out.Z, 0, -out.X)

	local groundY
	if model.Name == "BaseTemplate" then
		groundY = y0 - 2.50            -- no raycast: BaseTemplate sits over GameWorld.ThrowDeck.Deck
	else
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { Workspace.Terrain }
		groundY = math.huge
		for _, dx in ipairs({ -6.4, 0, 6.4 }) do
			local sp = Vector3.new(anch.X, 0, anch.Z) + right * dx
			local hit = Workspace:Raycast(Vector3.new(sp.X, y0 + 50, sp.Z), Vector3.new(0, -140, 0), rp)
			if hit then groundY = math.min(groundY, hit.Position.Y) end
		end
		if groundY == math.huge then groundY = y0 - 2.50 end     -- fallback
		groundY = math.clamp(groundY, y0 - 6.0, y0 + 2.0)        -- sanity clamp
	end

	local o = Vector3.new(anch.X, groundY, anch.Z)
	-- G.LookVector == out, origin at GROUND. Enum.NormalId.Front is the -Z face, so
	-- Face = Front points AT the approaching player. In G, +x is the VIEWER'S LEFT.
	return CFrame.lookAt(o, o + out), groundY, y0
end
PlotBoardHandler.BoardBase = boardBase

-- ===== part table (spec 1.2.3) =====
local C = Color3.fromRGB
local BOARD_PARTS = {
	{ n = "Board",      s = Vector3.new(11, 6, 0.4),      c = CFrame.new(0, 6.00, 0),      m = Enum.Material.WoodPlanks,    col = C(112, 76, 46), coll = true },
	{ n = "PostL",      s = Vector3.new(0.7, 10, 0.7),    c = CFrame.new(5.7, 4.00, 0.25), m = Enum.Material.Wood,          col = C(78, 52, 34),  coll = true },
	{ n = "PostR",      s = Vector3.new(0.7, 10, 0.7),    c = CFrame.new(-5.7, 4.00, 0.25),m = Enum.Material.Wood,          col = C(78, 52, 34),  coll = true },
	{ n = "Cap",        s = Vector3.new(12.6, 0.7, 2.2),  c = CFrame.new(0, 9.35, -0.60),  m = Enum.Material.Wood,          col = C(64, 42, 28),  coll = false },
	{ n = "Brace",      s = Vector3.new(11.8, 0.5, 0.5),  c = CFrame.new(0, 2.75, 0.10),   m = Enum.Material.Wood,          col = C(78, 52, 34),  coll = false },
	{ n = "LikePlaque", s = Vector3.new(3.4, 3.4, 0.5),   c = CFrame.new(-3.55, 5.35, -0.40), m = Enum.Material.SmoothPlastic, col = C(88, 58, 38), coll = false, query = true },
	{ n = "SignLamp",   s = Vector3.new(0.45, 0.45, 0.45),c = CFrame.new(0, 8.70, -1.35),  m = Enum.Material.Neon,          col = C(255, 214, 150), coll = false, noShadow = true },
}

local function buildBoardModel(model)
	if model:FindFirstChild("PlotBoard") then return model.PlotBoard end
	local G = boardBase(model)
	if not G then return nil end

	local board = Instance.new("Model")
	board.Name = "PlotBoard"

	local primary
	for _, d in ipairs(BOARD_PARTS) do
		local part = Instance.new("Part")
		part.Name = d.n
		part.Size = d.s
		part.CFrame = G * d.c
		part.Material = d.m
		part.Color = d.col
		part.Anchored = true
		part.Locked = false
		part.CanCollide = d.coll
		part.CastShadow = not d.noShadow
		if d.query ~= nil then part.CanQuery = d.query end
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = board
		if d.n == "Board" then primary = part end
		if d.n == "SignLamp" then
			local pl = Instance.new("PointLight")
			pl.Color = C(255, 198, 138)
			pl.Range = 14
			pl.Brightness = 1.4
			pl.Shadows = false
			pl.Parent = part
		end
	end

	board.PrimaryPart = primary
	board.Parent = model            -- parented INTO the plot Model so a Studio drag carries it
	return board
end

-- Invisible collidable step-up disc so the player stands ON the fire pit instead of
-- sinking 0.65 studs into CampDirt. r 5.60 == CAMPFIRE_RADIUS == CollectRing radius.
local function buildCampStand(model)
	if model:FindFirstChild("CampStand") then return model.CampStand end
	local campfire = model:FindFirstChild("Campfire")
	if not campfire then return nil end
	local cf = campfire.Position

	local stand = Instance.new("Part")
	stand.Name = "CampStand"
	stand.Shape = Enum.PartType.Cylinder
	stand.Size = Vector3.new(0.40, 11.20, 11.20)              -- r = 5.60
	stand.CFrame = CFrame.new(cf.X, cf.Y - 0.95, cf.Z) * CFrame.Angles(0, 0, math.rad(90))
	stand.Anchored = true
	stand.CanCollide = true
	stand.Transparency = 1
	stand.CanQuery = false      -- must not eat the verification raycast nor a future mouse target query
	stand.CanTouch = false      -- load-bearing: the plot-claim trigger is Platform.Touched
	stand.CastShadow = false
	stand.Material = Enum.Material.SmoothPlastic
	stand.Locked = false
	stand.Parent = model
	return stand
end

-- USER DECISION U4: three low, CanCollide=false props where the tents used to be.
-- Keeps the warm silhouette at distance without reintroducing a wall.
local NOOK_PARTS = {
	{ n = "Bedroll",  s = Vector3.new(3.2, 0.5, 6.4), bearing = -176, r = 17.0,  y = 0.25, shape = nil,
	  post = CFrame.Angles(0, math.rad(-176), 0), m = Enum.Material.Fabric, col = C(214, 128, 62) },
	{ n = "LogBench", s = Vector3.new(6.0, 1.0, 1.0), bearing = 168,  r = 18.0,  y = 0.5,  shape = Enum.PartType.Cylinder,
	  post = CFrame.Angles(0, math.rad(78), math.rad(90)), m = Enum.Material.Wood, col = C(104, 72, 44) },
	{ n = "Stump",    s = Vector3.new(1.6, 1.4, 1.6), bearing = -165, r = 19.5,  y = 0.7,  shape = Enum.PartType.Cylinder,
	  post = CFrame.Angles(0, 0, math.rad(90)), m = Enum.Material.Wood, col = C(88, 62, 38) },
}

local function buildCampNook(model)
	if not BUILD_CAMP_NOOK then return nil end
	if model:FindFirstChild("CampNook") then return model.CampNook end
	local F = plotFrame(model)
	if not F then return nil end

	local nook = Instance.new("Model")
	nook.Name = "CampNook"
	for _, d in ipairs(NOOK_PARTS) do
		local a = math.rad(d.bearing)
		local part = Instance.new("Part")
		part.Name = d.n
		if d.shape then part.Shape = d.shape end
		part.Size = d.s
		part.CFrame = F * CFrame.new(math.sin(a) * d.r, d.y, math.cos(a) * d.r) * d.post
		part.Material = d.m
		part.Color = d.col
		part.Anchored = true
		part.CanCollide = false        -- never a wall, never blocks the entrance
		part.CastShadow = true
		part.Locked = false
		part.Parent = nook
	end
	nook.Parent = model
	return nook
end

local function ensureLikePrompt(model)
	local board = model:FindFirstChild("PlotBoard")
	local plaque = board and board:FindFirstChild("LikePlaque")
	if not plaque then return nil end
	local prompt = plaque:FindFirstChild("LikePrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LikePrompt"
		prompt.Parent = plaque
	end
	prompt.ActionText = "Like"
	prompt.ObjectText = ""
	prompt.HoldDuration = 0.35
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 16     -- reachable from behind the board too
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, -20)
	prompt.Enabled = (model:GetAttribute("Claimed") == true)
	return prompt
end

-- Idempotent. model = any plot Model or ServerStorage.BaseTemplate (needs .Platform).
-- FindFirstChild throughout, never dot-indexing (plot.PlotBoard errors when absent).
function PlotBoardHandler.BuildBoard(model)
	if not model or not model:FindFirstChild("Platform") then return end
	local needNook = BUILD_CAMP_NOOK and not model:FindFirstChild("CampNook")
	if model:FindFirstChild("PlotBoard") and model:FindFirstChild("CampStand") and not needNook then
		ensureLikePrompt(model)
		return
	end
	buildBoardModel(model)
	buildCampStand(model)
	buildCampNook(model)
	ensureLikePrompt(model)
end

function PlotBoardHandler.Targets()
	local t = {}
	local bases = Workspace:FindFirstChild("PlayerBases")
	if bases then
		for _, m in ipairs(bases:GetChildren()) do
			if m:IsA("Model") and m:FindFirstChild("Platform") then table.insert(t, m) end
		end
	end
	local bt = ServerStorage:FindFirstChild("BaseTemplate")
	if bt and bt:FindFirstChild("Platform") then table.insert(t, bt) end
	return t
end

function PlotBoardHandler.BuildAll()
	local n = 0
	for _, m in ipairs(PlotBoardHandler.Targets()) do
		PlotBoardHandler.BuildBoard(m)
		n += 1
	end
	return n
end

-- ===== likes =====
local likeCooldown = {}   -- [Player] = os.clock()

function PlotBoardHandler.TryLike(player, plot)
	if not plot or not player then return false, "Something went wrong." end
	local now = os.clock()
	local last = likeCooldown[player]
	if last and (now - last) < 1.0 then return false, "Slow down!" end          -- (5) debounce
	likeCooldown[player] = now                                                 -- stamped BEFORE validation

	if plot:GetAttribute("Claimed") ~= true then return false, "Nobody lives here yet." end   -- (2)
	local ownerId = plot:GetAttribute("OwnerUserId")
	if type(ownerId) ~= "number" or ownerId == 0 then return false, "Nobody lives here yet." end
	if ownerId == player.UserId then return false, "You can't like your own camp!" end        -- (1)

	local owner = Players:GetPlayerByUserId(ownerId)
	if not owner or owner.Parent == nil then return false, "That camper just left." end       -- (6)

	local board  = plot:FindFirstChild("PlotBoard")
	local plaque = board and board:FindFirstChild("LikePlaque")
	local prompt = plaque and plaque:FindFirstChildOfClass("ProximityPrompt")
	local char   = player.Character
	local hrp    = char and char:FindFirstChild("HumanoidRootPart")
	if not (plaque and hrp) then return false, "Stand closer to the sign." end
	local slack = (prompt and prompt.MaxActivationDistance or 16) + 8
	if (plaque.Position - hrp.Position).Magnitude > slack then                                -- (4)
		return false, "Stand closer to the sign."
	end

	local likerData = PlayerDataManager.Get(player)
	local ownerData = PlayerDataManager.Get(owner)
	if not likerData or not ownerData then return false, "Something went wrong." end
	likerData.LikedPlayers = likerData.LikedPlayers or {}
	local key = tostring(ownerId)                                                             -- (3)
	if likerData.LikedPlayers[key] then return false, "You already liked this camp!" end

	likerData.LikedPlayers[key] = true
	ownerData.PlotLikes = (ownerData.PlotLikes or 0) + 1
	plot:SetAttribute("PlotLikes", ownerData.PlotLikes)
	PlayerDataManager.PushUpdate(player)
	PlayerDataManager.PushUpdate(owner)
	likeResult:FireClient(owner, {
		Success = true,
		Message = player.DisplayName .. " liked your camp!",
		PlotIndex = plot:GetAttribute("PlotIndex"),
	})
	return true, "Liked " .. (plot:GetAttribute("OwnerName") or "camp") .. "!"
end

local function replyLike(who, plot, ok, reason)
	likeResult:FireClient(who, {
		Success = ok == true,
		Message = reason or (ok and "Liked!" or "Can't like that camp."),
		PlotIndex = plot and plot:GetAttribute("PlotIndex"),
	})
end

local function plotByIndex(idx)
	local bases = Workspace:FindFirstChild("PlayerBases")
	if not bases then return nil end
	for _, plot in ipairs(bases:GetChildren()) do
		if plot:GetAttribute("PlotIndex") == idx then return plot end
	end
	return nil
end

local inited = false
function PlotBoardHandler.Init()
	if inited then return end
	inited = true

	PlotBoardHandler.BuildAll()

	local bases = Workspace:FindFirstChild("PlayerBases")
	if bases then
		for _, plot in ipairs(bases:GetChildren()) do
			if plot:IsA("Model") and plot:FindFirstChild("Platform") then
				local prompt = ensureLikePrompt(plot)
				if prompt then
					prompt.Triggered:Connect(function(who)
						local ok, reason = PlotBoardHandler.TryLike(who, plot)
						replyLike(who, plot, ok, reason)
					end)
					-- GetAttributeChangedSignal fires with ZERO arguments: re-read the attribute.
					plot:GetAttributeChangedSignal("Claimed"):Connect(function()
						prompt.Enabled = (plot:GetAttribute("Claimed") == true)
					end)
					prompt.Enabled = (plot:GetAttribute("Claimed") == true)   -- initial state
				end
			end
		end
	end

	-- Secondary input: a mouse click on the plaque. Payload is a NUMBER only; the plot is
	-- resolved by its PlotIndex attribute. Never accept a client-supplied plot reference.
	likeRemote.OnServerEvent:Connect(function(player, idx)
		if typeof(idx) ~= "number" or idx ~= idx then return end
		local plot = plotByIndex(idx)
		if not plot then
			replyLike(player, nil, false, "Can't like that camp.")
			return
		end
		local ok, reason = PlotBoardHandler.TryLike(player, plot)
		replyLike(player, plot, ok, reason)
	end)

	Players.PlayerRemoving:Connect(function(p)
		likeCooldown[p] = nil
	end)
end

return PlotBoardHandler
