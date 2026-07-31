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
local InventoryHandler = require(script.Parent.InventoryHandler)
local EggConfig = require(RS.Modules.EggConfig)
local BrainrotConfig = require(RS.Modules.BrainrotConfig)
local PetConfig = require(RS.Modules.PetConfig)
local PetHandler = require(script.Parent.PetHandler)
local remotes = RS:WaitForChild("Remotes")

local M = {}
local rng = Random.new()
local lastBuy = {}  -- [player] = clock, 0.5s debounce

local rarityByName = {}
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do rarityByName[e.Name] = e.Rarity end

-- Pure; exposed for the Task 12 odds simulation. Weights sum to 100 (EggConfig.Validate).
function M.RollFor(egg, r)
	if #egg.Table == 0 then return nil end
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

	-- Self-heal for unsnapshotted Studio state: the prompt was found disabled once;
	-- server asserts it on every boot.
	local prompt = workspace:FindFirstChild("GameWorld") and workspace.GameWorld:FindFirstChild("EggStall") and workspace.GameWorld.EggStall:FindFirstChild("PromptPart") and workspace.GameWorld.EggStall.PromptPart:FindFirstChild("EggPrompt")
	if prompt then prompt.Enabled = true end

	remotes.EggBuy.OnServerEvent:Connect(function(player, worldId, eggId)
		if typeof(worldId) ~= "string" or typeof(eggId) ~= "string" then return end
		local now = os.clock()
		if lastBuy[player] and now - lastBuy[player] < 0.5 then return end
		lastBuy[player] = now

		local data = PDM.Get(player)
		if not data then return refuse(player, "Profile not loaded yet.") end
		if data.__noSave then return refuse(player, "Your profile did not load \u{2014} rejoin before buying eggs.") end
		-- Relies on `or` short-circuiting: GetEgg returns a single nil (not nil, nil) when
		-- the egg isn't found, so `world` is nil too -- checking `not egg` first keeps
		-- `not world.Active` from ever indexing a nil `world`.
		local egg, world = EggConfig.GetEgg(worldId, eggId)
		if not egg or not world.Active then return refuse(player, "That egg is not available.") end

		-- ATOMIC COMMIT: no yields from here to the Give.
		if not DarrelService.TrySpend(player, egg.Price, "egg:" .. eggId) then
			return refuse(player, ("Not enough Darrels (need %d)."):format(egg.Price))
		end
		local name = M.RollFor(egg)

		-- Eggs hatch into PETS, not placeable brainrots. The creature lands in data.Pets
		-- (bag -> Pets tab) and never goes onto a plot, so the BrainrotMover unique-cap
		-- pre-check and InventoryHandler.SyncBackpack that used to sit here are gone with it:
		-- pets have no unique cap and are not backpack items.
		--
		-- The creature still resolves through BrainrotConfig for its name and rarity, which
		-- is why EggConfig.Validate's "references unknown creature" assert still protects
		-- these tables.
		local petId = PetConfig.IdFor(name)
		if not petId then
			DarrelService.Award(player, egg.Price, "refund:" .. eggId)
			warn(("[EggHandler] %s rolled %s with no PetConfig entry, refunded")
				:format(player.Name, tostring(name)))
			return refuse(player, "That creature is not available yet \u{2014} Darrels refunded.")
		end

		-- Error boundary: anything throwing between the spend and the EggResult fire would
		-- otherwise leave the player charged with no reply. Grant returns false rather than
		-- throwing on a bad id, so both failure shapes refund.
		local ok2, granted, uid = pcall(PetHandler.Grant, player, petId)
		if not ok2 or not granted then
			DarrelService.Award(player, egg.Price, "refund:" .. eggId)
			warn(("[EggHandler] hatch failed, refunded: %s uid=%d egg=%s rolled=%s err=%s")
				:format(player.Name, player.UserId, eggId, name, tostring(granted)))
			return refuse(player, "Hatch failed \u{2014} Darrels refunded.")
		end

		data.EggsOpened[eggId] = (data.EggsOpened[eggId] or 0) + 1
		PDM.PushUpdate(player)
		remotes.EggResult:FireClient(player, {
			Ok = true, EggId = eggId, Name = name, Rarity = rarityByName[name],
			PetUid = uid, PetId = petId,
		})

		local saved = PDM.Save(player)  -- after commit; audit on failure (trade-hardening pattern)
		if not saved then
			warn(("[EggHandler] SAVE FAILED after hatch: %s uid=%d egg=%s got=%s")
				:format(player.Name, player.UserId, eggId, name))
		end
	end)
	Players.PlayerRemoving:Connect(function(p) lastBuy[p] = nil end)
end

return M
