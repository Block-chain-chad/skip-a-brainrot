-- CinematicCommand: Studio/admin debug controls for the Massive Catch Cinematic
-- build (task-8-brief). Two chat commands, both gated identically to
-- ServerScriptService.AdminAnnouncements (RunService:IsStudio() OR the same
-- ALLOWED_USER_IDS allowlist, copied as-is):
--
--   /cinematic [name words...] [massive|huge|hugeold|spectator]
--       Fabricates a MassiveCinematic payload and FireClients it to ONLY the
--       requesting player (or, for "spectator", with UserId=0 so THEIR OWN
--       client takes the spectator branch instead of the thrower branch).
--       GRANTS NOTHING. Touches no PlayerDataManager data, no inventory, no
--       currency -- this is a visual-only remote fire, exactly the one
--       ThrowHandler already fires for a real throw. Unknown brainrot name ->
--       warn(), nothing fired.
--
--   /cinceremony on|off
--       Sets the workspace attribute CinematicCeremonyAfter (boolean), which
--       CatchRevealClient already reads as a live override for
--       Config.RUN_PULL_CEREMONY_AFTER (see that file's ThrowResult handler).
--       Workspace-attribute rather than per-player so it persists across a
--       respawn within the same demo session.
--
-- "massive"/"huge"/"spectator" all set payload.__variantOverride so the demo
-- forces a specific cut regardless of Config.SIZES' CURRENT tuning (Huge is
-- "none" today, pending the owner's side-by-side pick) -- see CinematicClient's
-- own Studio debug seam for why. "hugeold" instead routes to the OLD
-- MassiveEmergence cutscene, bypassing the Takeover entirely, for the direct
-- comparison. Every payload also sets __debugNoBridge: a fabricated payload has
-- no real ThrowResult behind it, and without this the Takeover would arm the
-- Bridge, wait out Config.CANCEL_TIMEOUT for a grant that will never come, and
-- cancel the run a few seconds in -- exactly the failure a demo command must
-- not have. Both fields are Studio-only no-ops outside Studio (see
-- CinematicClient), by design: none of this is meant to run on a published
-- server, matching every other test seam in this build.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local modules = ReplicatedStorage:WaitForChild("Modules")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local cinematicRemote = remotes:WaitForChild("MassiveCinematic")

local BrainrotConfig = require(modules:WaitForChild("BrainrotConfig"))
local BrainrotConfigTundra = require(modules:WaitForChild("BrainrotConfigTundra"))
local RarityConfig = require(modules:WaitForChild("RarityConfig"))
local RarityConfigTundra = require(modules:WaitForChild("RarityConfigTundra"))

-- Same allowlist as AdminAnnouncements -- copied as-is, not re-derived, so the
-- two commands never drift out of sync on who counts as an admin.
local ALLOWED_USER_IDS = { 71510820 }

local function isAllowed(player: Player): boolean
	return table.find(ALLOWED_USER_IDS, player.UserId) ~= nil
end

local function canUse(player: Player): boolean
	return RunService:IsStudio() or isAllowed(player)
end

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
local VARIANTS = { massive = true, huge = true, hugeold = true, spectator = true }

-- Pebble: RockConfig's own cheapest/first rock, MaxDistance 25, Color (140,140,140).
local ROCK_ID = "Pebble"
local ROCK_COLOR = Color3.fromRGB(140, 140, 140)

local function fireCinematic(player: Player, name: string, variant: string)
	local endPos, surfaceY = endPosFor(player)
	if not endPos then
		warn("[CinematicCommand] " .. player.Name .. ": no character to throw from, nothing fired")
		return
	end

	local rarity, color = rarityAndColorFor(name)

	local payload: { [string]: any } = {
		UserId = (variant == "spectator") and 0 or player.UserId,
		BrainrotName = name,
		Rarity = rarity,
		RarityColor = color,
		Mutation = nil,
		Size = "Massive",
		RockId = ROCK_ID,
		RockColor = ROCK_COLOR,
		Seed = math.random(1, 2 ^ 30),
		EndPos = endPos,
		SurfaceY = surfaceY,
		TotalTime = 0.1, -- near-immediate bonk, per task-8-brief
		NContacts = 1,
		SegTime = 0.1,
		-- Studio-only debug seam CinematicClient reads -- see that file and this
		-- module's own header comment. Never meaningful outside Studio.
		__debugNoBridge = true,
	}

	if variant == "huge" then
		payload.Size = "Huge"
		payload.__variantOverride = "trimmed"
	elseif variant == "hugeold" then
		payload.Size = "Huge"
		payload.__variantOverride = "hugeold"
	else
		-- "massive" and "spectator" both want the full cut, forced regardless of
		-- Config.SIZES.Massive's current value (today "full" anyway, but the demo
		-- command should not go quiet the moment the owner starts flipping that
		-- tunable while comparing variants).
		payload.__variantOverride = "full"
	end

	cinematicRemote:FireClient(player, payload)
end

local function parseCinematic(player: Player, body: string)
	local tokens = {}
	for w in body:gmatch("%S+") do
		table.insert(tokens, w)
	end

	local variant = "massive"
	if #tokens > 0 then
		local lastLower = string.lower(tokens[#tokens])
		if VARIANTS[lastLower] then
			variant = lastLower
			table.remove(tokens)
		end
	end

	local name = (#tokens > 0) and table.concat(tokens, " ") or DEFAULT_NAME

	local models = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if not (models and models:FindFirstChild(name)) then
		warn("[CinematicCommand] " .. player.Name .. ": unknown brainrot '" .. name .. "' -- nothing fired")
		return
	end

	fireCinematic(player, name, variant)
end

-- ============================== /cinceremony ==============================

local function parseCinCeremony(player: Player, body: string)
	local arg = string.lower(string.match(body, "%S+") or "")
	if arg == "on" then
		Workspace:SetAttribute("CinematicCeremonyAfter", true)
	elseif arg == "off" then
		Workspace:SetAttribute("CinematicCeremonyAfter", false)
	else
		warn("[CinematicCommand] " .. player.Name .. ": /cinceremony expects 'on' or 'off'")
	end
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
		-- deliberately NOT the isAllowed() allowlist branch canUse() gives
		-- /cinceremony below. Every seam this command depends on to be USEFUL
		-- (__variantOverride and __debugNoBridge, both read in CinematicClient) is
		-- itself gated on RunService:IsStudio(), so a live-server admin invocation
		-- could only ever produce a degraded run: huge/hugeold silently no-op
		-- (Config.SIZES.Huge is "none" today) and massive/spectator would arm the
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

	local ceremonyBody = stripCommand(message, "/cinceremony")
	if ceremonyBody then
		-- /cinceremony only ever flips the cosmetic workspace attribute
		-- CinematicCeremonyAfter, which the REAL catch pipeline's
		-- CatchRevealClient reads -- no MassiveCinematic fire, no Bridge contact,
		-- so the live-server admin allowlist (canUse -- IsStudio() OR isAllowed())
		-- stays safe to keep here.
		if canUse(player) then
			parseCinCeremony(player, ceremonyBody)
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
