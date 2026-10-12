-- RevealRouter: turns a CONFIRMED grant (throw or ice-fishing) into exactly one
-- reveal. Spec S5.3. Deliberately thin: presentation lives in CatchPop and in the
-- cuts; this only decides WHICH.
--
--   grant -> SkipReveal<Rarity> gamepass seam
--         -> Config.CUT_FOR(rarity, size)
--         -> cut?  Bridge.tryAdopt (the running Takeover owns it; onDone(false) falls back)
--         -> else  queue a pop
-- One reveal at a time (FIFO). Fail-soft end to end: a broken module costs a catch
-- nothing -- the grant already happened on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotConfig = require(Modules:WaitForChild("BrainrotConfig"))
-- CatchCue: the burst around the player + the per-tier sting -- ONE ladder shared with
-- IceFishingClient (extracted from CatchRevealClient 2026-08-23 for exactly that).
local CatchCue = require(Modules:WaitForChild("CatchCue"))
local CatchPop = require(Modules:WaitForChild("CatchPop"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Fail-soft cinematic stack (same shape as CinematicClient): nil means pops only.
local Config, Bridge, Takeover
do
	local ok, cfg, br, tk = pcall(function()
		local folder = Modules:WaitForChild("CatchCinematic", 5)
		return require(folder:WaitForChild("Config", 5)), require(folder:WaitForChild("Bridge", 5)), require(folder:WaitForChild("Takeover", 5))
	end)
	if ok then Config, Bridge, Takeover = cfg, br, tk
	else warn("[RevealRouter] CatchCinematic unavailable (" .. tostring(cfg) .. ") -- pops only") end
end

local weightByName, voiceByName = {}, {}
for _, e in ipairs(BrainrotConfig) do
	weightByName[e.Name] = e.Weight
	if type(e.VoiceId) == "string" and e.VoiceId ~= "" then voiceByName[e.Name] = e.VoiceId end
end

-- ============================== normalise ==============================
-- One grant record for both sources (spec S5.3).
local function fromThrow(r)
	return {
		Name = r.BrainrotName, Rarity = r.Rarity, RarityColor = r.RarityColor,
		Mutation = r.Mutation, Size = r.Size, Serial = r.Serial, Exists = r.Exists,
		IsNew = r.IsNew == true, Anchor = r.SplashPos, Source = "throw",
		CashPerSecond = r.CashPerSecond, Perfect = r.Perfect,
	}
end

local function ceremonyPayload(g, tierCuePlayed)
	local weight = weightByName[g.Name]
	return {
		Name = g.Name, Rarity = g.Rarity, RarityColor = g.RarityColor, Mutation = g.Mutation,
		Size = g.Size, SplashPos = g.Anchor, Serial = g.Serial, Exists = g.Exists, IsNew = g.IsNew,
		-- honest within-tier odds: the hub roster's weights sum to 100,000 per tier; a fish
		-- arrives with its own OddsN (1000 / FishWeight) already computed
		OddsN = g.OddsN or (weight and math.max(2, math.floor(100000 / weight + 0.5)) or nil),
		TierCuePlayed = tierCuePlayed == true, VoiceId = voiceByName[g.Name],
	}
end

-- ============================== queue ==============================
local queue = {}
local draining = false

local function playPop(g)
	-- Burst + tier sting first: they read as the catch LANDING (below the reveal gate,
	-- so they play even when the player has switched this tier's reveal off).
	local tierCuePlayed = CatchCue.Play({ Rarity = g.Rarity, Color = g.RarityColor, Mutation = g.Mutation })
	if player:GetAttribute("SkipReveal" .. tostring(g.Rarity)) == true then return end
	pcall(CatchPop.play, ceremonyPayload(g, tierCuePlayed)) -- BLOCKS for the pop's length
end

-- The stone camera's round trip is over when this clears (ThrowCam). A pop that opens
-- while the camera is still out over the water -- which is exactly when ThrowResult
-- lands -- reads as "abrupt result, then a snap"; waiting for the camera to be home
-- gives the spec's order: camera settles, short anticipation, the brainrot appears.
-- Bounded: the module has its own backstop, and a reveal must never be lost to a
-- flag that failed to clear.
local CAMERA_WAIT_MAX = 2.5
local function waitForCamera()
	local t0 = os.clock()
	while player:GetAttribute("ThrowCamBusy") == true and os.clock() - t0 < CAMERA_WAIT_MAX do
		task.wait(0.03)
	end
end

local function drainQueue()
	if draining then return end
	draining = true
	task.spawn(function()
		while #queue > 0 do
			-- never over a takeover (spec S11): wait for it, bounded by its own watchdog
			while Takeover and Takeover.isActive() do task.wait(0.1) end
			waitForCamera()
			local g = table.remove(queue, 1)
			local ok, err = pcall(playPop, g)
			if not ok then warn("[RevealRouter] pop failed: " .. tostring(err)) end
		end
		draining = false
	end)
end

local function enqueuePop(g)
	table.insert(queue, g)
	drainQueue()
end

-- ============================== route ==============================
local function route(raw, g)
	if type(g.Name) ~= "string" then return end
	local cutName = Config and Config.CUT_FOR(g.Rarity, g.Size) or nil
	if cutName and Bridge then
		-- The running Takeover owns this reveal. Adopt hands it the authoritative
		-- result (reveal-time fallback swaps); onDone(false) means the cinematic died,
		-- so the grant gets a pop after all. pcall'd end to end.
		local okAdopt, adopted = pcall(Bridge.tryAdopt, raw)
		if not okAdopt then warn("[RevealRouter] adopt errored: " .. tostring(adopted)) end
		if okAdopt and adopted == true then
			local okHook = pcall(Bridge.onDone, function(ok)
				if not ok then enqueuePop(g) end
			end)
			if okHook then return end
		end
	end
	enqueuePop(g)
end

remotes:WaitForChild("ThrowResult").OnClientEvent:Connect(function(result)
	if type(result) ~= "table" or type(result.BrainrotName) ~= "string" then return end
	route(result, fromThrow(result))
end)

-- ============================== ice fishing ==============================
-- The same IceFishingState remote IceFishingClient drives its HUD from. That client keeps
-- the corner card and the minigame; the REVEAL for a landed fish is routed here so a fish
-- and a thrown catch can never drift apart (it used to run its own PullCeremony chain).
-- `Casting` says which hole the line went into -- the anchor a cut stages at, lifted to
-- the pool surface (hole.Position is the middle of a column that runs under the ice).
local fishRemote = remotes:WaitForChild("IceFishingState", 10)
if fishRemote then
	local lastHolePos = nil
	local poolY = nil
	pcall(function()
		poolY = require(Modules:WaitForChild("IceFishingConfig", 5)).POOL_Y
	end)
	-- Tundra colours + honest within-tier odds (1000 / FishWeight), built on first use.
	local tundraColour, fishWeight = nil, nil
	local function fishMeta(name, rarity)
		if not tundraColour then
			tundraColour, fishWeight = {}, {}
			pcall(function()
				for _, t in ipairs(require(Modules.RarityConfigTundra)) do tundraColour[t.Name] = t.Color end
			end)
			pcall(function()
				for _, e in ipairs(require(Modules.BrainrotConfigTundra)) do
					if e.Origin == "IceFishing" and e.FishWeight then fishWeight[e.Name] = e.FishWeight end
				end
			end)
		end
		local w = fishWeight[name]
		return tundraColour[rarity] or Color3.fromRGB(255, 226, 120), (w and w > 0) and math.max(2, math.floor(1000 / w + 0.5)) or nil
	end
	fishRemote.OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then return end
		if p.Casting then
			if typeof(p.HolePos) == "Vector3" then lastHolePos = p.HolePos end
			return
		end
		local c = p.Catch
		if type(c) ~= "table" or type(c.Name) ~= "string" then return end
		local rarity = c.Rarity or p.Rarity
		local colour, oddsN = fishMeta(c.Name, rarity)
		local anchor = (typeof(p.Anchor) == "Vector3") and p.Anchor
			or (lastHolePos and poolY and Vector3.new(lastHolePos.X, poolY, lastHolePos.Z)) or lastHolePos
		local g = {
			Name = c.Name, Rarity = rarity, RarityColor = colour, Mutation = c.Mutation, Size = c.Size,
			Serial = p.Serial, Exists = p.Exists, IsNew = p.IsNew == true, Anchor = anchor, Source = "fish",
			CashPerSecond = c.CashPerSecond, OddsN = oddsN,
		}
		local raw = { BrainrotName = c.Name, Rarity = rarity, Size = c.Size, Mutation = c.Mutation }
		route(raw, g)
	end)
end
