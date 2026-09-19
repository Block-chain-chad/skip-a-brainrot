local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local MintRegistry = require(ServerScriptService.Modules.MintRegistry)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
-- Size is the SECOND intrinsic axis and multiplies on top of the colour mutation,
-- exactly as IncomeLoop treats it (see its header note and line ~158).
local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
-- canonical abbreviator, K through Sp -- see Modules.NumberFormat
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)

local SELL_MULTIPLIER = 40

-- EVERY WORLD (fixed 2026-08-07). Built from BrainrotConfig alone, this priced the 30
-- tundra-exclusive brainrots at nil -- they would have sold for nothing.
-- Valley first so a shared name keeps its World 1 price and rarity.
local cashPerSecondByName = {}
local rarityByName = {}
for _, entry in ipairs(BrainrotConfig) do
	cashPerSecondByName[entry.Name] = entry.CashPerSecond
	rarityByName[entry.Name] = entry.Rarity
end
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	for _, e in ipairs((world and world.Pool) or {}) do
		if cashPerSecondByName[e.Name] == nil then
			cashPerSecondByName[e.Name] = e.CashPerSecond
			rarityByName[e.Name] = e.Rarity
		end
	end
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

		-- FLOOR THE PRICE, HERE (2026-08-19). CashPerSecond values are 2-3-decimal
		-- literals (Salamino Penguino = 1.57) that are not exact in binary64, so
		-- cashPerSecond * 40 lands on 62.800000000000004 and every string and every
		-- balance downstream inherited the dust -- that is what printed the reported
		-- "sold for $42.400000000000006". Verified across all 192 names: the floor of
		-- the double equals the decimal-exact floor every time, so nothing underpays.
		-- Floor rather than round because the sell row already advertises the floored
		-- price (ClientMain -> formatNumber -> NumberFormat.Short, which floors below
		-- 1000).
		--
		-- PER COPY, NOT PER SPECIES (2026-08-20). This used to be one
		-- floor(cashPerSecond * SELL_MULTIPLIER) computed before the handler even knew
		-- WHICH copies were selling, so mutation and size were ignored outright: a
		-- Golden Massive -- which IncomeLoop rates at 2 * 8 = 16x -- sold for exactly
		-- what a plain copy did, and an Angel Massive (95 * 8 = 760x) did too.
		--
		-- The two factors below are the INTRINSIC ones, the same pair IncomeLoop
		-- multiplies in. Its other multipliers (rebirth, upgrades, pets, gamepass) are
		-- deliberately NOT here: those are properties of the PLAYER, and folding them
		-- in would make one brainrot worth different amounts to different sellers,
		-- which is exactly the intuition a trade economy needs to keep.
		--
		-- Mult(nil) is 1 on BOTH axes, so a plain copy prices identically to before --
		-- verified against 242 plain copies in a live save, 0 of them changed.
		-- Flooring PER COPY (rather than once) keeps totalValue an exact integer.
		local function copyValue(entry)
			return math.floor(cashPerSecond
				* Mutations.Mult(entry.Mutation)
				* Sizes.Mult(entry.Size)
				* SELL_MULTIPLIER)
		end
		local mode = payload.Mode == "All" and "All" or "One"

		-- Only brainrots sitting in the inventory can be sold. A placed one is
		-- earning on the base and must be unequipped in the Bag first, which
		-- is what clears its PadIndex. This also means selling never has to tear
		-- down a pad model -- if it is sellable, there is no model to remove.
		--
		-- FAVORITES never sell (2026-08-12 rework): entry.Fav is the Bag's padlock,
		-- and its whole meaning is "this copy is safe from every bulk action".
		-- Both modes skip favorited copies; if favorites were the ONLY copies,
		-- the player hears exactly why nothing sold rather than a generic failure.
		--
		-- WHICH copies sell:
		--   One: the LEAST valuable unplaced copy (smallest Mutations.Mult) - the
		--        same rule BrainrotMover.Take uses, so selling a plain copy can
		--        never silently eat your Golden one.
		--   All: every unplaced PLAIN copy; mutated copies are skipped unless the
		--        client explicitly opts in with payload.IncludeMutated == true.
		-- mutatedSkipped is COUNTED now rather than filtered away silently: with every
		-- copy of a name mutated, this loop selected nothing and the zero-sold branch
		-- below fell all the way through to "You don't own any X" -- which was simply
		-- false, and is the reported "I hit SELL ALL and the row is still there".
		local sellIndex = {}
		local favSkipped, mutatedSkipped = 0, 0
		if mode == "All" then
			local includeMutated = payload.IncludeMutated == true
			for i, entry in ipairs(data.Brainrots) do
				if entry.Name == payload.Name and entry.PadIndex == nil then
					if entry.Fav then
						favSkipped += 1
					elseif entry.Mutation ~= nil and not includeMutated then
						mutatedSkipped += 1
					else
						sellIndex[i] = true
					end
				end
			end
		else
			-- least valuable by FULL value, not by Mutations.Mult alone: that tie-break
			-- was size-blind, so among equally-mutated copies it could hand over the
			-- Massive (8x) instead of the plain one.
			local bestIndex, bestValue
			for i, entry in ipairs(data.Brainrots) do
				if entry.Name == payload.Name and entry.PadIndex == nil then
					if entry.Fav then
						favSkipped += 1
					else
						local value = copyValue(entry)
						if not bestValue or value < bestValue then
							bestIndex, bestValue = i, value
						end
					end
				end
			end
			if bestIndex then sellIndex[bestIndex] = true end
		end

		local totalSold, placedSkipped = 0, 0
		-- summed per copy, because copies of one name no longer share a price
		local totalValue = 0
		local remaining = {}
		for i, entry in ipairs(data.Brainrots) do
			if sellIndex[i] then
				totalSold += 1
				totalValue += copyValue(entry)
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
			local msg
			if favSkipped > 0 then
				msg = "That " .. payload.Name .. " is favorited \u{2014} unlock the padlock in your Bag to sell it."
			elseif mutatedSkipped > 0 then
				-- the honest version of what used to say "You don't own any X"
				msg = ("All %d of your %s are mutated \u{2014} Sell All keeps those. Use SELL 1 to sell them one at a time.")
					:format(mutatedSkipped, payload.Name)
			elseif placedSkipped > 0 then
				msg = "That " .. payload.Name .. " is on your base \u{2014} unequip it in your Bag first."
			else
				msg = "You don't own any " .. payload.Name .. "."
			end
			remotes.SellResult:FireClient(player, { Success = false, Message = msg })
			return
		end

		PlayerDataManager.GrantCash(data, totalValue)

		remotes.SellResult:FireClient(player, {
			Success = true,
			-- NumberFormat.Cash, never raw concatenation: a bare number here is what
			-- printed the float. The helper adds the "$" itself, and it abbreviates the
			-- same way the sell row the player just clicked does (ClientMain's
			-- formatNumber is NumberFormat.Short), so toast and row now agree.
			-- the tail is the answer to "why is that row still on my screen": Sell All
			-- holds mutated copies back on purpose, and never used to say so.
			Message = "Sold " .. totalSold .. "x " .. payload.Name .. " for " .. NumberFormat.Cash(totalValue)
				.. (mutatedSkipped > 0 and (" (" .. mutatedSkipped .. " mutated kept)") or ""),
			Amount = totalValue,   -- integer: copyValue floors every copy
		})

		-- SyncBackpack is a stray-Tool purge now (see its header) -- kept for the
		-- migration window, harmless after it.
		InventoryHandler.SyncBackpack(player)
		PlayerDataManager.PushUpdate(player)
	end)
end

return SellHandler
