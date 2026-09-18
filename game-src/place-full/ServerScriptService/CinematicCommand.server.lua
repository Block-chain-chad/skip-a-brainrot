-- CinematicCommand: Studio-only debug control for the reward reveal cuts (2026-09-17
-- build; originally the Massive Catch Cinematic's task-8 demo command). One chat
-- command, Studio-only:
--
--   /cinematic [name words...] [mythic|secret|god|huge|massive|massivegod] [spectator]
--       Fabricates a CatchCinematic payload for the named cut (default massive) and
--       FireClients it to ONLY the requesting player (or, for "spectator", with
--       UserId=0 so THEIR OWN client takes the spectator branch instead of the
--       thrower branch). GRANTS NOTHING. Touches no PlayerDataManager data, no
--       inventory, no currency -- this is a visual-only remote fire, exactly the one
--       ThrowHandler already fires for a real throw. Unknown brainrot name ->
--       warn(), nothing fired.
--
-- The payload sets __cutOverride so the demo forces the named cut regardless of the
-- roster's real rarity, and __debugNoBridge: a fabricated payload has no real
-- ThrowResult behind it, and without this the Takeover would arm the Bridge, wait
-- out Config.CANCEL_TIMEOUT for a grant that will never come, and cancel the run a
-- few seconds in -- exactly the failure a demo command must not have. Both fields
-- are Studio-only no-ops outside Studio (see CinematicClient), by design.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local modules = ReplicatedStorage:WaitForChild("Modules")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local cinematicRemote = remotes:WaitForChild("CatchCinematic")

local BrainrotConfig = require(modules:WaitForChild("BrainrotConfig"))
local BrainrotConfigTundra = require(modules:WaitForChild("BrainrotConfigTundra"))
local RarityConfig = require(modules:WaitForChild("RarityConfig"))
local RarityConfigTundra = require(modules:WaitForChild("RarityConfigTundra"))

-- ============================== name -> rarity/colour ==============================
-- BrainrotConfig (hub) and BrainrotConfigTundra (World 2) each carry a plain
-- Rarity STRING per entry (no shared Tier object), so the colour has to come
-- from whichever world's own RarityConfig the name was found in. Built once at
-- module load -- this list only changes with a publish, never mid-session.
local rarityByName: { [string]: { rarity: string, world: string } } = {}
for _, e in ipairs(BrainrotConfig) do
	rarityByName[e.Name] = { rarity = e.Rarity, world = "hub" }
end
for _, e in ipairs(BrainrotConfigTundra) do
	-- Tundra wins on a name collision (57 W1 crossovers per the tundra-crossover
	-- build): a name reachable in both worlds shows its Tundra rarity here,
	-- which is almost always the rarer/more "plausible" one for a MASSIVE demo.
	rarityByName[e.Name] = { rarity = e.Rarity, world = "tundra" }
end

local colorByRarity = { hub = {}, tundra = {} }
for _, t in ipairs(RarityConfig) do
	colorByRarity.hub[t.Name] = t.Color
end
for _, t in ipairs(RarityConfigTundra) do
	colorByRarity.tundra[t.Name] = t.Color
end

local FALLBACK_RARITY = "Rare"
local FALLBACK_COLOR = Color3.fromRGB(255, 255, 255)

local function rarityAndColorFor(name: string): (string, Color3)
	local info = rarityByName[name]
	if not info then
		return FALLBACK_RARITY, FALLBACK_COLOR
	end
	local color = colorByRarity[info.world][info.rarity] or FALLBACK_COLOR
	return info.rarity, color
end

-- ============================== end pos / surface Y ==============================
-- Same recipe as ServerScriptService.Modules.ThrowHandler's surfaceYOf/
-- throwZoneOf: any BasePart named ThrowZone under Workspace.GameWorld, tested
-- by CFrame:PointToObjectSpace against the zone's own half-size (+6 on Y,
-- matching the throw code's generous stance allowance). Walked fresh per
-- command rather than cached against GameWorld.DescendantAdded/Removing like
-- ThrowHandler does -- this runs on a chat message, not a per-throw hot path.
local DEFAULT_SURFACE_Y = 1.5

local function surfaceYForCharacter(character: Model?): number
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return DEFAULT_SURFACE_Y
	end
	local gw = Workspace:FindFirstChild("GameWorld")
	if not gw then
		return DEFAULT_SURFACE_Y
	end
	for _, d in ipairs(gw:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "ThrowZone" then
			local rel = d.CFrame:PointToObjectSpace((hrp :: BasePart).Position)
			local half = d.Size / 2
			if math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and math.abs(rel.Y) <= half.Y + 6 then
				local sy = d:GetAttribute("SurfaceY")
				return (type(sy) == "number") and sy or DEFAULT_SURFACE_Y
			end
		end
	end
	return DEFAULT_SURFACE_Y
end

-- HRP + lookVector * 60, flattened and snapped to the standing zone's surface
-- (or the hub default). Returns nil only when the player has no character at
-- all (dead/loading) -- the command simply declines rather than throwing.
local function endPosFor(player: Player): (Vector3?, number?)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil, nil
	end
	local look = (hrp :: BasePart).CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, 1)
	else
		flat = flat.Unit
	end
	local raw = (hrp :: BasePart).Position + flat * 60
	local surfaceY = surfaceYForCharacter(character)
	return Vector3.new(raw.X, surfaceY, raw.Z), surfaceY
end

-- ============================== /cinematic ==============================

local DEFAULT_NAME = "Kraken Congelato"
-- /cinematic [name words...] [mythic|secret|god|huge|massive|massivegod] [spectator]
-- The last token(s) pick the cut (default massive) and whether the caller watches as a
-- spectator. Rarity/Size on the payload follow the cut so Config.CUT_FOR agrees with
-- __cutOverride on the client; the roster's real rarity is used for pop-tier names.
local CUTS = { mythic = "Mythic", secret = "Secret", god = "God", huge = "Huge", massive = "Massive", massivegod = "MassiveGod" }

-- Pebble: RockConfig's own cheapest/first rock, MaxDistance 25, Color (140,140,140).
local ROCK_ID = "Pebble"
local ROCK_COLOR = Color3.fromRGB(140, 140, 140)

local function fireCinematic(player: Player, name: string, cut: string, spectator: boolean)
	local endPos, surfaceY = endPosFor(player)
	if not endPos then
		warn("[CinematicCommand] " .. player.Name .. ": no character to throw from, nothing fired")
		return
	end

	local rosterRarity, color = rarityAndColorFor(name)
	-- Rarity/Size the cut implies (so CUT_FOR on the client agrees with the override).
	local rarity = (cut == "God" or cut == "MassiveGod") and "God"
		or (cut == "Secret") and "Secret" or (cut == "Mythic") and "Mythic" or rosterRarity
	local size = (cut == "Massive" or cut == "MassiveGod") and "Massive" or (cut == "Huge") and "Huge" or nil

	local payload: { [string]: any } = {
		UserId = spectator and 0 or player.UserId,
		BrainrotName = name,
		Rarity = rarity,
		RarityColor = color,
		Mutation = nil,
		Size = size,
		Cut = cut,
		RockId = ROCK_ID,
		RockColor = ROCK_COLOR,
		Seed = math.random(1, 2 ^ 30),
		EndPos = endPos,
		SurfaceY = surfaceY,
		TotalTime = 0.1, -- near-immediate bonk, per task-8-brief
		NContacts = 1,
		SegTime = 0.1,
		-- Studio-only debug seams CinematicClient reads -- see that file and this
		-- module's own header comment. Never meaningful outside Studio.
		__debugNoBridge = true,
		__cutOverride = cut,
	}

	cinematicRemote:FireClient(player, payload)
end

local function parseCinematic(player: Player, body: string)
	local tokens = {}
	for w in body:gmatch("%S+") do
		table.insert(tokens, w)
	end

	local spectator = false
	if #tokens > 0 and string.lower(tokens[#tokens]) == "spectator" then
		spectator = true
		table.remove(tokens)
	end
	local cut = "Massive"
	if #tokens > 0 then
		local lastLower = string.lower(tokens[#tokens])
		if CUTS[lastLower] then
			cut = CUTS[lastLower]
			table.remove(tokens)
		end
	end

	local name = (#tokens > 0) and table.concat(tokens, " ") or DEFAULT_NAME

	local models = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if not (models and models:FindFirstChild(name)) then
		warn("[CinematicCommand] " .. player.Name .. ": unknown brainrot '" .. name .. "' -- nothing fired")
		return
	end

	fireCinematic(player, name, cut, spectator)
end


-- ============================== chat wiring ==============================
-- Same shape as AdminAnnouncements.parseCommand: "<command> " prefix -> body,
-- bare "<command>" -> empty body, anything else -> nil (not this command).
local function stripCommand(message: string, command: string): string?
	local prefix = command .. " "
	if message:sub(1, #prefix) == prefix then
		return message:sub(#prefix + 1)
	elseif message == command then
		return ""
	end
	return nil
end

local function onPlayerChatted(player: Player, message: string)
	local cinBody = stripCommand(message, "/cinematic")
	if cinBody then
		-- SPLIT GATE (review fix, task 8): /cinematic is Studio-only, full stop --
		-- deliberately NOT an isAllowed() allowlist branch. Every seam this command
		-- depends on to be USEFUL (__cutOverride and __debugNoBridge, both read in
		-- CinematicClient) is itself gated on RunService:IsStudio(), so a live-server
		-- admin invocation could only ever produce a degraded run: the override would
		-- silently no-op and the payload would arm the
		-- REAL Bridge (skipBridge never engages outside Studio) and hard-cancel
		-- ~3s in waiting for a ThrowResult that will never come. Worse than merely
		-- degraded: arming the real Bridge on a live server opens a genuine
		-- cross-contamination window -- if that SAME admin has a real Massive
		-- catch in flight when they run this, its authentic ThrowResult can adopt
		-- into this demo's armed generation, and the real catch's reveal plays out
		-- through the fabricated payload's leftover cosmetic fields (name/rarity/
		-- colour). Non-data-corrupting (no grant, no currency, nothing written),
		-- but a real and entirely avoidable failure mode for a command that cannot
		-- do anything useful outside Studio anyway. So: Studio only, no allowlist
		-- fallback -- unreachable on a published server even for an admin.
		if RunService:IsStudio() then
			parseCinematic(player, cinBody)
		end
		return
	end
end

local function onPlayerAdded(player: Player)
	player.Chatted:Connect(function(message)
		onPlayerChatted(player, message)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
