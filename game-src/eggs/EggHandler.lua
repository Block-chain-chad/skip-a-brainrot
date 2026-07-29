-- EggHandler (Forest Egg Shop) -- server-authoritative buy -> roll -> grant.
-- Spend and grant happen back-to-back with no yields in EggHandler's own code in
-- between: TrySpend commits the Darrel deduction, then the roll and the Give must
-- land before anything else can observe the player's state, or a mid-purchase
-- disconnect could pay without delivering (or deliver without paying, if reversed).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PDM = require(script.Parent.PlayerDataManager)
local DarrelService = require(script.Parent.DarrelService)
local BrainrotMover = require(script.Parent.BrainrotMover)
local EggConfig = require(RS.Modules.EggConfig)
local BrainrotConfig = require(RS.Modules.BrainrotConfig)
local remotes = RS:WaitForChild("Remotes")

local M = {}
local rng = Random.new()
local lastBuy = {}  -- [player] = clock, 0.5s debounce

local rarityByName = {}
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do rarityByName[e.Name] = e.Rarity end

-- Pure; exposed for the Task 12 odds simulation. Weights sum to 100 (EggConfig.Validate).
function M.RollFor(egg, r)
	local roll = (r or rng):NextInteger(1, 100)
	local acc = 0
	for _, row in ipairs(egg.Table) do
		acc += row[2]
		if roll <= acc then return row[1] end
	end
	return egg.Table[#egg.Table][1]
end

local function refuse(player, msg)
	remotes.EggResult:FireClient(player, { Ok = false, Message = msg })
end

function M.Init()
	EggConfig.Validate()  -- fail loudly at boot, not at first purchase
	remotes.EggBuy.OnServerEvent:Connect(function(player, worldId, eggId)
		if typeof(worldId) ~= "string" or typeof(eggId) ~= "string" then return end
		local now = os.clock()
		if lastBuy[player] and now - lastBuy[player] < 0.5 then return end
		lastBuy[player] = now

		local data = PDM.Get(player)
		if not data then return refuse(player, "Profile not loaded yet.") end
		if data.__noSave then return refuse(player, "Your profile did not load \u{2014} rejoin before buying eggs.") end
		local egg, world = EggConfig.GetEgg(worldId, eggId)
		if not egg or not world.Active then return refuse(player, "That egg is not available.") end

		-- ATOMIC COMMIT: no yields from here to the Give.
		if not DarrelService.TrySpend(player, egg.Price, "egg:" .. eggId) then
			return refuse(player, ("Not enough Darrels (need %d)."):format(egg.Price))
		end
		local name = M.RollFor(egg)

		-- BrainrotMover.Give deliberately does NOT enforce the unique cap (a P2P transfer's
		-- Take() has already mutated the giver by the time Give could refuse -- see Give's
		-- own header comment). Every grant path is required to pre-check
		-- BrainrotMover.WithinUniqueCap itself; GianlucaQuest/MaxwellQuest/TradeHandler/
		-- BoothHandler all do the same pre-flight, so EggHandler does too. None of the
		-- current forest-egg names are flagged Unique in BrainrotConfig, so this cannot
		-- fire today -- it exists so a future Unique creature added to an egg table fails
		-- safe (refund) instead of silently duplicating a one-of-a-kind item.
		if not BrainrotMover.WithinUniqueCap(name, BrainrotMover.CountOwned(data, name), 0, 1) then
			DarrelService.Award(player, egg.Price, "refund:" .. eggId)
			return refuse(player, ("You already own the one-of-a-kind %s \u{2014} Darrels refunded."):format(name))
		end

		-- Give's REAL signature is (receiver, receiverData, record) and it is VOID -- no
		-- ok/err return; it unconditionally inserts. (The brief assumed a 2-arg
		-- (data, record) -> ok, err shape; adapted here after reading BrainrotMover live,
		-- per task instructions.)
		BrainrotMover.Give(player, data, { Name = name })

		data.EggsOpened[eggId] = (data.EggsOpened[eggId] or 0) + 1
		PDM.PushUpdate(player)
		remotes.EggResult:FireClient(player, { Ok = true, EggId = eggId, Name = name, Rarity = rarityByName[name] })

		local saved = PDM.Save(player)  -- after commit; audit on failure (trade-hardening pattern)
		if not saved then
			warn(("[EggHandler] SAVE FAILED after hatch: %s uid=%d egg=%s got=%s")
				:format(player.Name, player.UserId, eggId, name))
		end
	end)
	Players.PlayerRemoving:Connect(function(p) lastBuy[p] = nil end)
end

return M
