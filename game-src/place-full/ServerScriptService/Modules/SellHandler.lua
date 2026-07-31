local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local MintRegistry = require(ServerScriptService.Modules.MintRegistry)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)

local SELL_MULTIPLIER = 40

local cashPerSecondByName = {}
local rarityByName = {}
for _, entry in ipairs(BrainrotConfig) do
	cashPerSecondByName[entry.Name] = entry.CashPerSecond
	rarityByName[entry.Name] = entry.Rarity
end

local remotes = ReplicatedStorage.Remotes

local SellHandler = {}

function SellHandler.Init()
	remotes.SellBrainrot.OnServerEvent:Connect(function(player, payload)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		if typeof(payload) ~= "table" or typeof(payload.Name) ~= "string" then return end

		local cashPerSecond = cashPerSecondByName[payload.Name]
		if not cashPerSecond then
			remotes.SellResult:FireClient(player, { Success = false, Message = "Unknown brainrot." })
			return
		end

		local sellValueEach = cashPerSecond * SELL_MULTIPLIER
		local mode = payload.Mode == "All" and "All" or "One"

		-- Only brainrots sitting in the inventory can be sold. A placed one is
		-- earning on the base and must be picked up first (hold E on it), which
		-- is what clears its PadIndex. This also means selling never has to tear
		-- down a pad model -- if it is sellable, there is no model to remove.
		--
		-- WHICH copies sell:
		--   One: the LEAST valuable unplaced copy (smallest Mutations.Mult) - the
		--        same rule BrainrotMover.Take uses, so selling a plain copy can
		--        never silently eat your Golden one.
		--   All: every unplaced PLAIN copy; mutated copies are skipped unless the
		--        client explicitly opts in with payload.IncludeMutated == true.
		local sellIndex = {}
		if mode == "All" then
			local includeMutated = payload.IncludeMutated == true
			for i, entry in ipairs(data.Brainrots) do
				if entry.Name == payload.Name and entry.PadIndex == nil
					and (includeMutated or entry.Mutation == nil) then
					sellIndex[i] = true
				end
			end
		else
			local bestIndex, bestMult
			for i, entry in ipairs(data.Brainrots) do
				if entry.Name == payload.Name and entry.PadIndex == nil then
					local mult = Mutations.Mult(entry.Mutation)
					if not bestMult or mult < bestMult then
						bestIndex, bestMult = i, mult
					end
				end
			end
			if bestIndex then sellIndex[bestIndex] = true end
		end

		local totalSold, placedSkipped = 0, 0
		local remaining = {}
		for i, entry in ipairs(data.Brainrots) do
			if sellIndex[i] then
				totalSold += 1
				PlayerDataManager.DrainPending(player, entry, data)
				-- sold copies are destroyed for good: record the burn so the
				-- registry's live "exists" counts stay honest (gated on IsTracked,
				-- the same rule the mint side uses).
				if MintRegistry.IsTracked(rarityByName[entry.Name], entry.Mutation) then
					pcall(MintRegistry.Burn, entry.Name, entry.Mutation, 1)
				end
			else
				if entry.Name == payload.Name and entry.PadIndex then placedSkipped += 1 end
				table.insert(remaining, entry)
			end
		end
		data.Brainrots = remaining

		if totalSold == 0 then
			local msg = placedSkipped > 0
				and ("That " .. payload.Name .. " is on your base \u{2014} pick it up first (hold E on it).")
				or ("You don't own any " .. payload.Name .. ".")
			remotes.SellResult:FireClient(player, { Success = false, Message = msg })
			return
		end

		local totalValue = totalSold * sellValueEach
		PlayerDataManager.GrantCash(data, totalValue)

		remotes.SellResult:FireClient(player, {
			Success = true,
			Message = "Sold " .. totalSold .. "x " .. payload.Name .. " for $" .. totalValue,
			Amount = totalValue,
		})

		-- the sold entries are gone from data; rebuild the Backpack so their Tools
		-- go with them. Without this the tool lingers and the brainrot still looks
		-- like it is in the inventory.
		InventoryHandler.SyncBackpack(player)
		PlayerDataManager.PushUpdate(player)
	end)
end

return SellHandler
