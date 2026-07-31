-- Campfire Offering: BURN one unplaced brainrot into the fire in exchange for a
-- small PERMANENT luck bonus (see ReplicatedStorage.Modules.OfferingConfig --
-- sqrt growth, +1% per sqrt(offering), hard-capped at +50%).
--
-- Why this sink exists: fusion cannot absorb the bulk of the faucet (it needs 5
-- identical name+mutation copies and dead-ends at Rainbow), so Commons pile up
-- forever. Offerings accept EVERY tier, and because the reward is sub-linear the
-- sink keeps eating supply without ever out-earning rocks and upgrades as a luck
-- source.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local OfferingConfig = require(ReplicatedStorage.Modules.OfferingConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)

local remotes = ReplicatedStorage.Remotes

local CAMPFIRE_RANGE = 16   -- identical reach to FusionHandler's campfire check
local BURN_COOLDOWN = 0.4   -- a double-click must never cost two brainrots

local validName = {}
for _, e in ipairs(BrainrotConfig) do validName[e.Name] = true end

local lastBurn = {}

local OfferingHandler = {}

local function label(name, mutation)
	if mutation and mutation ~= "" then return mutation .. " " .. name end
	return name
end

function OfferingHandler.Init()
	remotes.OfferBrainrot.OnServerEvent:Connect(function(player, name, mutation)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		if typeof(name) ~= "string" or not validName[name] then return end
		if mutation ~= nil and typeof(mutation) ~= "string" then return end

		local result = remotes:FindFirstChild("PurchaseResult")

		local now = os.clock()
		local prev = lastBurn[player.UserId]
		if prev and now - prev < BURN_COOLDOWN then return end

		-- must be at your OWN campfire (same check as FusionHandler)
		local plot = PlayerDataManager.GetPlot(player)
		if not plot then return end
		local campfire = plot:FindFirstChild("Campfire", true)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not campfire or not hrp or (campfire.Position - hrp.Position).Magnitude > CAMPFIRE_RANGE then
			if result then result:FireClient(player, { Success = false, Message = "Stand by your campfire to offer!" }) end
			return
		end

		-- a fresh player must not be able to click themselves down to nothing
		if #data.Brainrots <= 1 then
			if result then result:FireClient(player, { Success = false, Message = "You can't burn your last brainrot!" }) end
			return
		end

		-- Pick the LEAST valuable UNPLACED copy of this name -- the same rule
		-- BrainrotMover.Take uses. The client sends the mutation of the row that
		-- was clicked, but selection stays deliberately NAME-based: a burn must
		-- never be able to eat a better copy than the player has spare. The
		-- client shows the exact target in its confirm step so this is visible.
		local bestIndex, bestMult
		for i, e in ipairs(data.Brainrots) do
			if e.Name == name and e.PadIndex == nil then
				local mult = Mutations.Mult(e.Mutation)
				if not bestMult or mult < bestMult then
					bestIndex, bestMult = i, mult
				end
			end
		end
		if not bestIndex then
			if result then result:FireClient(player, { Success = false, Message = ("No spare %s to offer -- placed ones don't count!"):format(name) }) end
			return
		end

		local entry = data.Brainrots[bestIndex]
		local burned = label(entry.Name, entry.Mutation)
		lastBurn[player.UserId] = now

		-- banked cash on the entry is PAID OUT first; burning must not destroy money
		PlayerDataManager.DrainPending(player, entry, data)
		table.remove(data.Brainrots, bestIndex)
		data.Offerings = (data.Offerings or 0) + 1

		InventoryHandler.SyncBackpack(player)
		PlayerDataManager.PushUpdate(player)

		local luck = OfferingConfig.LuckMult(data.Offerings)
		if result then
			result:FireClient(player, {
				Success = true,
				Message = ("Offered %s - camp luck now x%.2f"):format(burned, luck),
			})
		end
		remotes.OfferBrainrot:FireClient(player, {
			Name = entry.Name,
			Mutation = entry.Mutation,
			Offerings = data.Offerings,
			LuckMult = luck,
		})
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastBurn[player.UserId] = nil
	end)

	print("OfferingHandler online")
end

return OfferingHandler
