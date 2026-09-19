local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local SessionLock = require(ServerScriptService.Modules.SessionLock)
-- The Worlds tab. Its destinations are portal Dests, so fast travel lands exactly
-- where walking through would -- see travelToWorld near the portal setup below.
local WorldTravelConfig = require(ReplicatedStorage.Modules.WorldTravelConfig)
local WorldTravelService = require(ServerScriptService.Modules.WorldTravelService)
-- Roblox's own service, not this module. Named RbxTeleport because a local called
-- TeleportService inside a script called TeleportService is a trap waiting to happen.
local RbxTeleport = game:GetService("TeleportService")
local remotes = ReplicatedStorage.Remotes

-- Fixed destinations (position, look direction)
local THROW_POS = Vector3.new(0, 6, 22)
local SHOPS_POS = Vector3.new(0, 9.53, -260) -- middle of the lodge interior (on PlazaFloor, among the stalls)
local TRADE_POS = Vector3.new(8000, 2006, 7905) -- island entrance (foot of the boardwalk, by the return portal)
local HUB_POS = Vector3.new(24, 6, -16) -- back in the hub, just west of the trade portal
-- The Frozen Tundra: snowfield at (-8000, 2000, -8000), surface y = 2002, reached from
-- the locked portal on the dungeon's south wall. BoundsGuard has a matching "Tundra"
-- region -- without it a player would be rubber-banded back to spawn about half a
-- second after arriving.
-- Centre of the arrival disc. It used to be -8000, which is now the mouth of the shop's
-- tunnel -- arriving players would have materialised in the doorway.
local TUNDRA_POS = Vector3.new(-8000, 2006, -7975)
local DUNGEON_POS = Vector3.new(-146, -19, 62) -- dungeon floor, a few studs north of the portal
-- The Lush Gardens: World 3, an underground realm at (8000, 1000, -8000), reached
-- from the root-and-stone gate standing in the valley meadow at (160, 4, 60).
-- Arrivals land in the chamber at the far end of the entry gorge and walk north
-- through the slot, which opens into the Verdant Court. BoundsGuard has a matching
-- "Gardens" region -- without it players are rubber-banded home on arrival.
local GARDENS_POS = Vector3.new(8000, 1031, -6676)
local FORWARD = Vector3.new(0, 0, 1)
local TO_SHOPS = Vector3.new(0, 0, -1) -- face -Z toward the back shop counters (ShopStall / SellStall)
local TO_HUB = Vector3.new(-1, 0, 0) -- face back toward spawn when returning

--=================== THE NAV BUTTONS ARE PER-WORLD ====================--
-- Skip / Shops / Plot used to be three fixed valley coordinates, so pressing any of them
-- in the Frozen Tundra silently threw the player 8000 studs back to World 1 -- which read
-- as the tundra ejecting you rather than as a teleport working.
--
-- Keyed on BoundsGuard's region names (via PlayerDataManager.PlayerWorld) so there is one
-- definition of where each world is. A world with no entry for a destination falls back
-- to the valley's, which is what the trading island wants: it has no dock or stalls of
-- its own, and "Skip" there should mean "take me somewhere I can skip".
local NAV = {
	Valley = {
		Throw = { pos = THROW_POS, look = FORWARD },
		Shops = { pos = SHOPS_POS, look = TO_SHOPS },
	},
	Tundra = {
		-- on the ice dock, facing up the lake past the SKIP HERE sign
		Throw = { pos = Vector3.new(-8000, 2004, -7800), look = FORWARD },
		-- middle of the ice hall, facing the back counters the same way the lodge does
		Shops = { pos = Vector3.new(-8000, 2005, -8090), look = TO_SHOPS },
	},
}

local function navTarget(player, destination)
	local world = PlayerDataManager.PlayerWorld(player)
	local here = world and NAV[world]
	return (here and here[destination]) or NAV.Valley[destination]
end

-- Which world's CAMP the player should be dealing with. Only two worlds have plots, so
-- the trading island resolves to the valley -- pressing Plot out there has always meant
-- "take me home", and it still should.
local function campWorld(player)
	return PlayerDataManager.PlayerWorld(player) == "Tundra" and "Tundra" or "Valley"
end

-- 2026-08-05 glitch pass: this place runs with workspace.StreamingEnabled =
-- true, and every teleport here was a bare PivotTo. That drops the character
-- into a region the client has not been sent yet, so the player watches the
-- world pop in around them for a second after arriving -- worst on the
-- valley <-> tundra hop, which is 8000 studs and guarantees a cold region.
--
-- RequestStreamAroundAsync asks the client to page that area in FIRST. It
-- yields, so it is pcall'd with a short timeout: a slow client should arrive
-- to a half-loaded world (what happened before) rather than not arrive at all.
-- Every call site is already inside its own event thread, so the yield costs
-- nothing else.
local STREAM_WAIT = 3

local function teleportCharacter(player, pos, lookDir)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	pcall(function()
		player:RequestStreamAroundAsync(pos, STREAM_WAIT)
	end)

	-- Re-check: the yield above means the character can have died, respawned or
	-- the player left while we waited.
	character = player.Character
	if not character or character ~= hrp.Parent then return end

	character:PivotTo(CFrame.lookAt(pos, pos + lookDir))
	-- Carried momentum survives a PivotTo, so a player who was sprinting or
	-- falling arrives still moving and skids off the pad.
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- Base-less player: drop them onto the first open plot. Touching it claims the base
-- (PlayerDataManager binds Touched on each plot's Platform).
--
-- Extracted into a function because it is needed from TWO destinations. The "Plot" tab
-- used to `if plot then ... end` with no else, so pressing it with no base did NOTHING --
-- no teleport, no message, no error. The open-plot logic existed but only "OpenPlot"
-- reached it, and only the throw button ever sends that.
-- IN THE WORLD THEY ARE STANDING IN. A camp is per-world now, so sending a tundra player
-- to a free valley plot would both teleport them out of the world they were in and use up
-- the wrong one of their two claims.
local function teleportToOpenPlot(player)
	local world = campWorld(player)
	if PlayerDataManager.GetPlot(player, world) then return false end   -- already has one here
	local plotsFolder = workspace:FindFirstChild("PlayerBases")
	local target
	if plotsFolder then
		-- iterate the folder rather than Plot1..Plot6 by name: the count is not guaranteed
		-- and a renamed or added plot would be silently skipped by a hardcoded range.
		for _, plot in ipairs(plotsFolder:GetChildren()) do
			if plot:IsA("Model") and not plot:GetAttribute("Claimed")
				and plot:GetAttribute("World") == world then
				target = plot
				break
			end
		end
	end
	if target then
		-- Land OFF-CENTRE. The plot pivot sits directly above the Campfire, so the old
		-- `pivot + (0,6,0)` dropped the player onto the fire and they never contacted the
		-- Platform at all -- which is what the claim listens to. Verified by raycast:
		-- offset 0 hits Campfire, -10 hits Pad1, -14 hits Platform cleanly.
		local pivot = target:GetPivot().Position
		teleportCharacter(player, pivot + Vector3.new(0, 6, -14), FORWARD)
		-- Then claim it OUTRIGHT rather than waiting for Platform.Touched to fire. A
		-- teleport is not a reliable touch -- the character can settle on a pad, a pit
		-- stone or the campfire and silently never claim, which is exactly the dead end
		-- this button had. Walking on still works via Touched; this just makes the
		-- button deterministic. ClaimPlotFor already refuses if the plot is taken or the
		-- player owns one, so it cannot double-claim.
		PlayerDataManager.ClaimPlotFor(player, target)
		return true
	end
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = false, Message = "All camps in this world are taken right now!" }) end
	return false
end

-- Assigned further down, once portalDests AND notify both exist. Forward-declared
-- here because the handler below is written before either of them.
local travelToWorld

remotes.TeleportTo.OnServerEvent:Connect(function(player, destination)
	if typeof(destination) ~= "string" then return end

	if destination == "Throw" or destination == "Shops" then
		local t = navTarget(player, destination)
		teleportCharacter(player, t.pos, t.look)
	elseif destination == "Trade" then
		teleportCharacter(player, TRADE_POS, FORWARD)
	elseif destination == "Plot" then
		-- THE CAMP IN THIS WORLD, explicitly. GetPlot with no world falls back to any camp
		-- they own, which is right for proximity checks and wrong here: in the tundra with
		-- only a valley camp, that fallback would fling them out of the world they are in
		-- instead of handing them a tundra camp.
		local plot = PlayerDataManager.GetPlot(player, campWorld(player))
		if plot then
			local pivot = plot:GetPivot()
			-- stand near the front edge of the plot, looking across the pads
			local pos = pivot.Position + Vector3.new(0, 6, -22)
			teleportCharacter(player, pos, FORWARD)
		else
			-- THE FIX: no base yet, so send them somewhere they can get one rather than
			-- doing nothing. This is the whole point of the button for a new player.
			teleportToOpenPlot(player)
		end
	elseif destination == "OpenPlot" then
		teleportToOpenPlot(player)
	elseif travelToWorld then
		-- WORLD FAST TRAVEL (the Worlds tab). Anything not matched above is treated as
		-- a world id and validated in there: an id that is not on the board, or a world
		-- this player has never stood in, is refused. So reaching this branch cannot
		-- become a way to name arbitrary coordinates.
		travelToWorld(player, destination)
	end
end)

-- === Walk-through portals (Pet Sim style) ===
-- A player who touches a portal's PortalTouch part is teleported to the
-- destination named in its Dest attribute.
local portalDests = {
	Trade = { pos = TRADE_POS, look = FORWARD },
	Hub = { pos = HUB_POS, look = TO_HUB },
	Tundra = { pos = TUNDRA_POS, look = FORWARD },
	Dungeon = { pos = DUNGEON_POS, look = FORWARD },
	-- facing -Z, up the gorge toward the hub
	Gardens = { pos = GARDENS_POS, look = Vector3.new(0, 0, -1) },
}

--=================== CROSS-PLACE PORTALS ===================--
-- World 2 runs on its own Place in this universe so tundra servers are separate from
-- valley servers. Same universe means the same DataStore, so profiles carry for free --
-- but two servers can then hold one profile, which is what SessionLock exists to stop.
--
-- TUNDRA_PLACE_ID = 0 means "not split out yet": every portal falls back to the in-place
-- jump below and nothing changes. Fill it in once the Place exists and the portals
-- become real teleports with no other edit.
local MAIN_PLACE_ID = 78783087742939
local TUNDRA_PLACE_ID = 0

-- Resolved per place, so ONE script is correct in both.
--
-- WHY BOTH PLACES CONTAIN BOTH WORLDS. 22 scripts reach for valley-only objects and 5
-- of them use a bare WaitForChild -- ClientMain waits on ShopStall at line ~423, so in a
-- tundra-only place the core client would hang there and never finish initialising.
-- Rather than guard 22 files (and every future one), the tundra Place is a full copy of
-- this one. The valley geometry simply goes unvisited there.
--
-- That leaves one hazard: the valley is still physically present on a tundra server, so
-- every portal that leads INTO the valley has to become a cross-place teleport, or the
-- population quietly splits across two copies of the same world.
local PLACE_IDS = {}
if TUNDRA_PLACE_ID > 0 then
	if game.PlaceId == MAIN_PLACE_ID then
		PLACE_IDS.Tundra = TUNDRA_PLACE_ID          -- leaving for World 2
	elseif game.PlaceId == TUNDRA_PLACE_ID then
		-- On a tundra server EVERY valley-bound portal goes home to the main place.
		PLACE_IDS.Dungeon = MAIN_PLACE_ID
		PLACE_IDS.Hub = MAIN_PLACE_ID
		PLACE_IDS.Trade = MAIN_PLACE_ID
	end
end

local teleporting = {}   -- [player] = true; a second touch must not fire a second teleport

local function sendToPlace(player, placeId, destName)
	if teleporting[player] then return end
	teleporting[player] = true

	-- Release BEFORE leaving, and await it. The destination server claims the SAME
	-- profile key; if our lock is still held it refuses and the player lands in a
	-- read-only session, losing everything they do there.
	local data = PlayerDataManager.Get(player)
	if data then data.LastSeen = os.time() end
	SessionLock.Release(player.UserId, data)

	local opts = Instance.new("TeleportOptions")
	opts:SetTeleportData({ fromPlace = game.PlaceId, dest = destName })

	local ok, err = pcall(function()
		RbxTeleport:TeleportAsync(placeId, { player }, opts)
	end)
	if not ok then
		-- We already gave up the lock, so take it back or this session saves nothing.
		SessionLock.Claim(player.UserId)
		teleporting[player] = nil
		notify(player, "Could not reach that world right now \u{2014} try again in a moment.")
		warn(("[TeleportService] TeleportAsync failed for %s -> place %d: %s")
			:format(player.Name, placeId, tostring(err)))
	end
end

-- Roblox fires this when the teleport itself fails after being accepted. Same recovery:
-- reclaim the profile, because the player is still on this server.
RbxTeleport.TeleportInitFailed:Connect(function(player, result, message)
	SessionLock.Claim(player.UserId)
	teleporting[player] = nil
	notify(player, "That world is not reachable at the moment. Please try again.")
	warn(("[TeleportService] TeleportInitFailed %s: %s (%s)")
		:format(player.Name, tostring(result), tostring(message)))
end)

-- LOCKED PORTALS. A portal whose PortalTouch carries a RequiresKey attribute costs that
-- many of Gianluca's keys (data.Keys -- the same counter GianlucaQuest and TungQuest pay
-- out) the FIRST time it is used. After that the UnlockFlag is stamped on the profile and
-- it is free forever: the key buys the destination, it is not a toll on every trip.
--
-- Declared as attributes on the part rather than a table in here, so adding a locked
-- portal later is a build-time change with no script edit.
local function notify(player, message)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = false, Message = message }) end
end

-- Returns true if the player may pass. Consumes the key on the unlocking trip.
local function passesLock(player, touchPart)
	local cost = touchPart:GetAttribute("RequiresKey")
	if not cost or cost <= 0 then return true end

	local flag = touchPart:GetAttribute("UnlockFlag")
	local place = touchPart:GetAttribute("PlaceName") or "this place"
	local data = PlayerDataManager.Get(player)
	if not data then return false end

	if flag and data[flag] then return true end -- already paid, walk straight through

	local held = tonumber(data.Keys) or 0
	if held < cost then
		notify(player, ("\u{1F512} The way to %s is locked \u{2014} you need %d of Gianluca's keys (you have %d).")
			:format(place, cost, held))
		return false
	end

	data.Keys = held - cost
	if flag then data[flag] = true end
	PlayerDataManager.PushUpdate(player)
	notify(player, ("\u{1F513} You unlocked %s with Gianluca's key!"):format(place))
	return true
end

-- Fills the forward declaration above. Deliberately down here: it needs both
-- portalDests (the arrival points) and notify (the refusal toast).
--
-- REUSES THE PORTAL'S OWN ARRIVAL POINT rather than carrying coordinates of its
-- own, so the Worlds tab and the walk-through portal can never disagree about
-- where a world begins -- and fast travel inherits teleportCharacter's
-- RequestStreamAroundAsync wait, which is what stops an 8,000-stud hop dropping
-- the player into a world that has not been sent to them yet.
travelToWorld = function(player, id)
	local dest = WorldTravelConfig.ById[id]
	if not dest then return end   -- not a world id at all; silently ignore

	local ok, why = WorldTravelService.CanTravel(player, id)
	if not ok then
		notify(player, why or "You cannot travel there yet.")
		return
	end

	local target = portalDests[dest.Dest]
	if not target then
		warn(("[TeleportService] world %q names portal dest %q, which does not exist")
			:format(id, tostring(dest.Dest)))
		return
	end
	teleportCharacter(player, target.pos, target.look)
	-- teleportCharacter yields until the character has actually moved, so by here the
	-- player IS in the new world -- refresh rather than waiting out the sampler, or
	-- reopening the board straight after arriving shows the world you just left as
	-- YOU ARE HERE.
	pcall(WorldTravelService.Refresh, player)
end

local lastPortalUse = {} -- [player] = os.clock(); debounce so one pass = one teleport

-- Walking through a portal is the OTHER way to change world, and the board has to
-- follow it just as closely as it follows fast travel -- a portal is in fact how a
-- world gets discovered in the first place.
local function refreshTravelBoard(player)
	task.spawn(function()
		task.wait(0.35)   -- let the arrival settle before reading the region back
		pcall(WorldTravelService.Refresh, player)
	end)
end

local function setupPortal(touchPart)
	local dest = touchPart:GetAttribute("Dest")
	local target = dest and portalDests[dest]
	if not target then return end
	touchPart.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then return end
		local now = os.clock()
		if lastPortalUse[player] and now - lastPortalUse[player] < 1.5 then return end
		-- debounce BEFORE the lock check too, or a player standing in a locked portal
		-- gets the "you need a key" message every physics frame
		lastPortalUse[player] = now
		if not passesLock(player, touchPart) then return end
		-- A destination with a Place behind it leaves this server entirely; everything
		-- else is the in-place jump this game has always used.
		local placeId = PLACE_IDS[dest]
		if placeId and placeId > 0 then
			sendToPlace(player, placeId, dest)
		else
			teleportCharacter(player, target.pos, target.look)
			-- a portal is how a world gets DISCOVERED, so the board has to hear about
			-- this arrival as promptly as it hears about a fast travel
			refreshTravelBoard(player)
		end
	end)
end

task.spawn(function()
	local portals = workspace:WaitForChild("GameWorld"):WaitForChild("Portals")
	for _, model in ipairs(portals:GetChildren()) do
		local touch = model:FindFirstChild("PortalTouch")
		if touch then setupPortal(touch) end
	end
	portals.ChildAdded:Connect(function(model)
		local touch = model:FindFirstChild("PortalTouch") or model:WaitForChild("PortalTouch", 5)
		if touch then setupPortal(touch) end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastPortalUse[player] = nil
	teleporting[player] = nil
end)

print(("TeleportService online (place %d; cross-place portals %s)")
	:format(game.PlaceId, TUNDRA_PLACE_ID > 0 and "ENABLED" or "off -- TUNDRA_PLACE_ID not set"))
