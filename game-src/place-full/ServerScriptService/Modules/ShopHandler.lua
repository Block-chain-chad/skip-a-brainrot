local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)

-- PER WORLD. Rocco keeps a stall in each world and they stock different shelves, so
-- both the "is this rock real" and the sequential-unlock checks are world-scoped.
-- Ladder position is per shelf: the tundra ladder is self-contained, so its first
-- rock needs no valley rock first (reaching world 2 is the gate).
local indexIn = {}     -- [world] = { [rockId] = ladder position on that shelf }
for _, world in ipairs(WorldProgression.List()) do
	local map = {}
	for i, rock in ipairs(WorldProgression.ShelfFor(world)) do map[rock.Id] = i end
	indexIn[world] = map
end

local remotes = ReplicatedStorage.Remotes

local ShopHandler = {}

-- ============================ ONE WORLD, ONE SHELF ============================
-- A rock is only usable in the world that sells it (see WorldProgression's ROCKS note),
-- so "what am I holding" changes as you cross a portal. Called off WorldTravelService's
-- region sampler, which already runs every 2s for every player. Two jobs, both idempotent
-- so being called forever costs a table lookup:
--
--   1. FIRST ARRIVAL grants that world's starter -- the free rock at the bottom of its
--      shelf (Pebble in the valley, GlacierShard in the tundra). Without it a player
--      walking into world 2 owns nothing that world stocks and has nothing to throw.
--   2. EQUIPS the best rock they own on THIS world's shelf, so the HUD, the luck panel
--      and the stone on their back all agree with what ThrowHandler will actually throw.
--
-- Nothing is lost crossing back: their valley rock is still owned, and step 2 re-equips
-- it the moment they are standing in the valley again. Rebirth wiping the collection is
-- fine here too -- a tundra player simply gets GlacierShard back, which is the point of
-- it being that world's Pebble.
function ShopHandler.SyncRockToWorld(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local here = PlayerDataManager.PlayerWorld(player)
	if not here then return end          -- no character yet; the next sample gets them
	local world = WorldProgression.NameFor(here)

	local changed = false
	local starter = WorldProgression.StarterRock(world)
	if starter and not data.OwnedRocks[starter.Id] then
		data.OwnedRocks[starter.Id] = true
		changed = true
	end
	local best = WorldProgression.BestOwnedIn(world, data.OwnedRocks)
	if best and data.EquippedRock ~= best.Id then
		data.EquippedRock = best.Id
		changed = true
	end
	if changed then PlayerDataManager.PushUpdate(player) end
end

function ShopHandler.Init()
	remotes.BuyRock.OnServerEvent:Connect(function(player, rockId)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		local rock = WorldProgression.RockById(rockId)
		if not rock then
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "Unknown rock." })
			return
		end

		-- WHICH SHELF THE BUYER IS STANDING AT, decided from their actual region rather
		-- than anything the client sent. Without this, firing BuyRock from the valley
		-- would happily sell a tundra rock.
		local world = WorldProgression.NameFor(PlayerDataManager.PlayerWorld(player))
		local shelf = WorldProgression.ShelfFor(world)
		local idx = indexIn[world] and indexIn[world][rockId]
		if not idx then
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "That rock isn't sold here." })
			return
		end
		if data.OwnedRocks[rockId] then
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "Already owned." })
			return
		end
		-- SEQUENTIAL UNLOCK: you must own the previous rock in the ladder before buying this
		-- one. Authoritative here; MerchantClient also greys out locked rocks for clarity.
		if idx > 1 then
			local prev = shelf[idx - 1]
			if not data.OwnedRocks[prev.Id] then
				remotes.PurchaseResult:FireClient(player, { Success = false, Message = "Unlock the " .. prev.Id .. " first!" })
				return
			end
		end
		if data.Cash < rock.Price then
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "Not enough Cash." })
			return
		end

		data.Cash -= rock.Price
		data.OwnedRocks[rockId] = true
		data.EquippedRock = rockId

		remotes.PurchaseResult:FireClient(player, { Success = true, Message = "Bought and equipped " .. rockId .. "!" })
		PlayerDataManager.PushUpdate(player)
	end)

	remotes.EquipRock.OnServerEvent:Connect(function(player, rockId)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		if not data.OwnedRocks[rockId] then
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "You don't own that rock." })
			return
		end
		-- OWNING IT IS NOT ENOUGH: a rock is only usable in the world that sells it, so
		-- equipping is scoped to the shelf the player is standing at. ThrowHandler refuses
		-- the same rock anyway; saying so here is what stops it looking like a silent bug.
		local at = WorldProgression.NameFor(PlayerDataManager.PlayerWorld(player))
		if not WorldProgression.StocksRock(at, rockId) then
			local label = WorldProgression.Resolve(at).Label or at
			remotes.PurchaseResult:FireClient(player, { Success = false, Message = "You can't skip that one in " .. label .. " -- see what Rocco stocks here!" })
			return
		end
		data.EquippedRock = rockId
		remotes.PurchaseResult:FireClient(player, { Success = true, Message = "Equipped " .. rockId .. "!" })
		PlayerDataManager.PushUpdate(player)
	end)
end

return ShopHandler
