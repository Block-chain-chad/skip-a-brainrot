-- WorldTravelService -- records which worlds a player has actually been to, and
-- tells the client which ones the Worlds tab may offer.
--
-- UNLOCKING IS OBSERVED, NOT AWARDED. Nothing calls "unlock the tundra"; this
-- samples PlayerDataManager.PlayerWorld -- the same BoundsGuard region name the
-- rest of the game uses for "where are you" -- and writes down whatever it finds.
-- That means a world unlocks however the player got there: the portal, a quest
-- teleport, a dev command, or fast travel itself. There is no arrival path to
-- forget to hook, which is exactly the bug a list of explicit unlock calls would
-- eventually grow.
--
-- The actual travelling is NOT here. TeleportService owns every arrival point and
-- the streaming wait that makes an 8,000-stud hop bearable; it asks this module
-- whether a destination is allowed and does the rest itself.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local Config = require(ReplicatedStorage.Modules.WorldTravelConfig)
-- A rock is only usable in the world that sells it, so crossing a border changes what you
-- are holding. This module is where "which region is each player in" is already answered
-- on a timer, so it is where that swap is driven from rather than a second sampler.
-- No cycle: ShopHandler requires PlayerDataManager and WorldProgression, never this.
local ShopHandler = require(ServerScriptService.Modules.ShopHandler)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local WorldTravelService = {}
local inited = false

-- The world we last TOLD each client they were standing in.
--
-- This exists because of a real bug: state was originally pushed only when a NEW
-- world was discovered. Moving between worlds you had already been to changes
-- nothing about the visited set, so nothing went out, so the panel went on showing
-- YOU ARE HERE against the world you had just LEFT -- and a row in that state has
-- no TRAVEL button on it. The symptom was "I can't fast travel back to the world I
-- was just in". Where you ARE has to be pushed as well as what you have unlocked.
local lastHere = {}

-- Sampled rather than event-driven for the reason in the header. 2s is well under
-- how long it takes to walk anywhere meaningful, and the write is skipped unless
-- the region is new, so the steady-state cost is one table lookup per player.
local SAMPLE_EVERY = 2

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = remotes
	end
	return r
end
local stateRemote = getRemote("WorldTravelState", "RemoteEvent")

local function visitedSet(data)
	if type(data.WorldsVisited) ~= "table" then data.WorldsVisited = {} end
	-- Home is implicit everywhere else, but stamping it keeps the saved set
	-- self-describing rather than "empty means you have at least been home".
	data.WorldsVisited[Config.Home] = true
	return data.WorldsVisited
end
WorldTravelService.Visited = visitedSet

function WorldTravelService.SendState(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local visited = visitedSet(data)
	local unlocked = {}
	for _, d in ipairs(Config.Destinations) do
		unlocked[d.Id] = Config.IsUnlocked(visited, d.Id)
	end
	stateRemote:FireClient(player, {
		Unlocked = unlocked,
		Here = PlayerDataManager.PlayerWorld(player),
	})
end

-- The one gate. TeleportService calls this; the panel greys out the same answer
-- through Config.IsUnlocked, so what is shown and what is allowed cannot drift.
function WorldTravelService.CanTravel(player, id): (boolean, string?)
	local d = Config.ById[id]
	if not d then return false, "Nowhere like that to travel to." end
	local data = PlayerDataManager.Get(player)
	if not data then return false, "Your profile has not loaded yet." end
	-- Held back before "have you been there": a player who HAS been there would
	-- otherwise get the discovery message, which reads as the game forgetting.
	if Config.IsComingSoon(id) then
		return false, ("%s is coming soon!"):format(d.Label)
	end
	if not Config.IsUnlocked(visitedSet(data), id) then
		return false, ("Find %s on foot first!"):format(d.Label)
	end
	return true, nil
end

-- Pushes immediately rather than waiting out the sampler. Called straight after a
-- fast travel, which is exactly when the player is most likely to reopen the board
-- -- a couple of seconds of stale rows there reads as the feature being broken.
function WorldTravelService.Refresh(player)
	WorldTravelService.NoteWhereTheyAre(player)
	-- Immediately, not on the next sample: arriving in a world and seeing the wrong rock
	-- on your back for two seconds is exactly when a player is looking at it.
	ShopHandler.SyncRockToWorld(player)
	lastHere[player] = PlayerDataManager.PlayerWorld(player)
	WorldTravelService.SendState(player)
end

-- Marks the region the player is standing in. Returns true if this was the first
-- time, so the caller can push state and congratulate them.
function WorldTravelService.NoteWhereTheyAre(player): boolean
	local data = PlayerDataManager.Get(player)
	if not data then return false end
	local region = PlayerDataManager.PlayerWorld(player)
	if type(region) ~= "string" or region == "" then return false end
	local visited = visitedSet(data)
	if visited[region] then return false end
	visited[region] = true
	PlayerDataManager.PushUpdate(player)
	return true
end

function WorldTravelService.Init()
	if inited then return end
	inited = true

	local function onJoin(player)
		task.spawn(function()
			local tries = 0
			while not PlayerDataManager.Get(player) and tries < 60 do task.wait(0.1); tries += 1 end
			if PlayerDataManager.Get(player) then
				WorldTravelService.NoteWhereTheyAre(player)
				task.wait(1)   -- let the client build its UI, same as the other state pushes
				lastHere[player] = PlayerDataManager.PlayerWorld(player)
				WorldTravelService.SendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

	task.spawn(function()
		while true do
			task.wait(SAMPLE_EVERY)
			for _, player in ipairs(Players:GetPlayers()) do
				-- BOTH halves matter -- see the note on lastHere. A discovery changes what
				-- is unlocked; simply walking through a portal changes which row says YOU
				-- ARE HERE, and that one is just as visible to the player.
				local discovered = WorldTravelService.NoteWhereTheyAre(player)
				-- Unconditional and idempotent -- it compares before it writes. Doing this on
				-- the CHANGE branch below instead would miss a player who joined straight into
				-- the tundra, since lastHere is seeded on join and never "changes" for them.
				ShopHandler.SyncRockToWorld(player)
				local here = PlayerDataManager.PlayerWorld(player)
				if discovered or lastHere[player] ~= here then
					lastHere[player] = here
					WorldTravelService.SendState(player)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p) lastHere[p] = nil end)

	print(("WorldTravelService online (%d destinations, unlocked by visiting)")
		:format(#Config.Destinations))
end

return WorldTravelService
