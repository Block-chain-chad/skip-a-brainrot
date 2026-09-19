local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local MintRegistry = require(ServerScriptService.Modules.MintRegistry)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
-- canonical abbreviator, K through Sp -- see Modules.NumberFormat
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local SellValue = require(ReplicatedStorage.Modules.SellValue)
-- for the "Sell Value" pet ability. PetConfig rather than PetHandler on purpose:
-- StackedMult is pure, already checks PetConfig.ENABLED itself, and lives in
-- ReplicatedStorage -- so this adds no server-module dependency and no require cycle.
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)

-- EVERY WORLD (fixed 2026-08-07). Built from BrainrotConfig alone, this priced the 30
-- tundra-exclusive brainrots at nil -- they would have sold for nothing.
-- Valley first so a shared name keeps its World 1 rarity.
-- Pricing itself now lives entirely in SellValue (2026-08-20, sell shop revamp);
-- rarityByName survives here ONLY because MintRegistry.Burn still needs a rarity
-- to gate its tracked-mint check on.
local rarityByName = {}
for _, entry in ipairs(BrainrotConfig) do
	rarityByName[entry.Name] = entry.Rarity
end
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	for _, e in ipairs((world and world.Pool) or {}) do
		if rarityByName[e.Name] == nil then
			rarityByName[e.Name] = e.Rarity
		end
	end
end

local remotes = ReplicatedStorage.Remotes

local SellHandler = {}

-- Finding 3 (2026-08-20 final fix wave): payload.Uids is fully
-- attacker-controlled. 1000 is 2x BagConfig's own absolute brainrot-bag
-- ceiling (BRAINROT_BASE 150 + MaxLevel 14 x BRAINROT_PER_LEVEL 25 = 500 --
-- see that module's header), comfortably above any real bag while still
-- bounding a malicious payload's cost. The whole payload is rejected on the
-- first oversized-or-wrong-type element rather than partially processed --
-- same shape PetHandler.SellMany uses for its own uid list.
local MAX_SELL_UIDS = 1000

function SellHandler.Init()
	remotes.SellBrainrot.OnServerEvent:Connect(function(player, payload)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		if typeof(payload) ~= "table" then return end

		-- READ-ONLY SESSION GUARD. A failed DataStore load serves a DEFAULT
		-- profile and every write is discarded at logout, so selling here would
		-- destroy the brainrot and hand back cash that never persists.
		-- PetHandler.Sell has always guarded this; this path did not.
		if data.__noSave then
			remotes.SellResult:FireClient(player, { Success = false,
				Message = "Your profile did not load \u{2014} rejoin before selling." })
			return
		end

		local mode = payload.Mode
		local chosen, held = {}, 0
		if type(payload.Uids) == "table" then
			local want, count = {}, 0
			for _, u in ipairs(payload.Uids) do
				count += 1
				-- Reject the WHOLE payload, not just the bad element: an oversized
				-- list must cost O(cap) here, never O(n).
				if count > MAX_SELL_UIDS then
					return
				end
				-- BRAINROT UIDS ARE NUMBERS, NOT STRINGS (2026-08-26).
				-- This gate read `typeof(u) ~= "string"`, lifted from
				-- PetHandler.SellMany -- where it is correct, because pet uids are
				-- HttpService:GenerateGUID(false) strings. Brainrot uids are not:
				-- they come from PlayerDataManager.TakeUid, which returns an
				-- incrementing NUMBER. So this rejected every genuine payload and
				-- did it through the SILENT return above -- no sale, no cash, no
				-- refusal toast, no error in the log. Selecting worked, the confirm
				-- dialog worked, the button worked, and nothing happened: exactly
				-- the "it does not sell them" report. Verified on a live server by
				-- probing the remote: uid[1] typeof=number value=194.
				--
				-- Strings stay accepted so any legacy or migrated entry keyed by one
				-- still matches; both are safe table keys. What the original
				-- hardening actually had to stop is a NaN key (0/0), which THROWS on
				-- assignment -- so NaN and the infinities are rejected by value here
				-- rather than by banning the whole numeric type.
				local t = typeof(u)
				if t == "number" then
					if u ~= u or u == math.huge or u == -math.huge then
						return
					end
				elseif t ~= "string" then
					return
				end
				want[u] = true
			end
			for _, e in ipairs(data.Brainrots) do
				-- 2026-08-22: never-sell now = the raid LOCK (PlotFav), the unified favorite.
				if want[e.Uid] and e.PadIndex == nil and not e.PlotFav
					and SellValue.OfBrainrot(e) ~= nil then
					chosen[#chosen + 1] = e
				end
			end
		elseif mode == "Duplicates" then
			chosen, held = SellValue.SelectBulk(data.Brainrots, nil)
		elseif mode == "All" then
			if typeof(payload.Name) ~= "string" then return end
			chosen, held = SellValue.SelectBulk(data.Brainrots, payload.Name)
		else
			if typeof(payload.Name) ~= "string" then return end
			-- 2026-08-20 (task 10): SelectCheapest itself now refuses a mutated or
			-- oversized copy (only Uids/the drill-down may sell those); its second
			-- return tells apart "every copy is protected" from "nothing owned at
			-- all", so this branch can send a refusal instead of silently selling
			-- one.
			local one, mutatedOrOversizedHeld = SellValue.SelectCheapest(data.Brainrots, payload.Name)
			if one then
				chosen[1] = one
			elseif mutatedOrOversizedHeld > 0 then
				remotes.SellResult:FireClient(player, { Success = false,
					Message = "Nothing sellable there \u{2014} every copy is mutated or oversized. Open its tile and sell those one at a time." })
				return
			end
		end

		if #chosen == 0 then
			remotes.SellResult:FireClient(player, { Success = false,
				Message = held > 0
					and ("Nothing there to bulk sell \u{2014} %d copies are mutated, oversized or locked. Sell those one at a time."):format(held)
					or "You don't own anything sellable there." })
			return
		end

		local sellSet = {}
		for _, e in ipairs(chosen) do sellSet[e] = true end
		local totalValue, totalSold = 0, 0
		local remaining = {}
		for _, entry in ipairs(data.Brainrots) do
			if sellSet[entry] then
				totalSold += 1
				totalValue += (SellValue.OfBrainrot(entry) or 0)
				PlayerDataManager.DrainPending(player, entry, data)
				if MintRegistry.IsTracked(rarityByName[entry.Name], entry.Mutation) then
					pcall(MintRegistry.Burn, entry.Name, entry.Mutation, 1)
				end
			else
				remaining[#remaining + 1] = entry
			end
		end
		data.Brainrots = remaining

		-- THE "SELL VALUE" PET ABILITY (2026-08-22): Cheek Hoard, Antler Barter,
		-- Old Growth. Applied to the TOTAL rather than per entry so the rounding
		-- happens once -- per-entry flooring would quietly eat the bonus on a bulk
		-- sell of many cheap brainrots. Guarded to >= 1 so a broken loadout can
		-- only ever fail to a normal-price sale, never to a discount.
		local sellMult = math.max(1, PetConfig.StackedMult(data.Pets, data.PetSlots, "SellBonus"))
		totalValue = math.floor(totalValue * sellMult)

		PlayerDataManager.GrantCash(data, totalValue)

		remotes.SellResult:FireClient(player, {
			Success = true,
			Message = ("Sold %d for %s%s"):format(totalSold, NumberFormat.Cash(totalValue),
				held > 0 and (" (" .. held .. " mutated or oversized kept)") or ""),
			Amount = totalValue,
		})
		InventoryHandler.SyncBackpack(player)
		PlayerDataManager.PushUpdate(player)
	end)
end

return SellHandler
