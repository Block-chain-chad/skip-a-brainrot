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

-- Rarity for the EggResult payload (drives the hatch reveal's tier lighting).
-- Sourced from PetConfig since 2026-08-01: the egg tables name PETS now, and a
-- pet name has no BrainrotConfig row, so the old BrainrotConfig lookup would
-- have handed the client a nil Rarity for every hatch.
local function rarityOf(name)
	local id = PetConfig.IdFor(name)
	local def = id and PetConfig.Pets[id]
	return def and def.Rarity
end

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

	remotes.EggBuy.OnServerEvent:Connect(function(player, worldId, eggId, qty)
		if typeof(worldId) ~= "string" or typeof(eggId) ~= "string" then return end
		-- qty is the shop's x1/x3/x10 picker (egg-shop handoff). WHITELISTED, never
		-- clamped: any other value did not come from our UI, so it is dropped the
		-- same way a malformed eggId is.
		if qty == nil then qty = 1 end
		if qty ~= 1 and qty ~= 3 and qty ~= 10 then return end
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

		-- ATOMIC COMMIT: no yields from here to the last Give. The whole batch is
		-- debited up front (one TrySpend, price x qty), then rolled and granted in a
		-- yield-free loop -- so a mid-batch disconnect can never observe a state where
		-- some opens are paid for but unresolved.
		-- Bundle price, NOT Price x qty: x3 and x10 are discounted and the shop card
		-- advertises the discounted subtotal. EggConfig.BundleCost is the one place
		-- that maths lives, so the number debited here is byte-for-byte the number the
		-- player was shown. Returns nil for a qty off the picker -- already whitelisted
		-- above, so this is belt-and-braces rather than the real guard.
		local cost = EggConfig.BundleCost(egg, qty)
		if not cost then return end
		if not DarrelService.TrySpend(player, cost, "egg:" .. eggId .. ":x" .. qty) then
			return refuse(player, ("Not enough Gems (need %d)."):format(cost))
		end

		-- Eggs hatch into PETS, not placeable brainrots. The creature lands in data.Pets
		-- (bag -> Pets tab) and never goes onto a plot, so pets have no unique cap and
		-- are not backpack items.
		--
		-- A rolled name IS a pet name (EggConfig.Validate asserts every row resolves
		-- through PetConfig.IdFor at boot), so the petId guard below is for a roster
		-- edited live in Studio between boot and purchase. On any failure the REST of
		-- the batch (the failed open included) is refunded and whatever already hatched
		-- is delivered -- granted pets are in data.Pets and cannot be un-granted.
		local results = {}
		for i = 1, qty do
			local name = M.RollFor(egg)
			local petId = PetConfig.IdFor(name)
			local ok2, granted, uid = false, false, nil
			if petId then
				ok2, granted, uid = pcall(PetHandler.Grant, player, petId)
			end
			if not (petId and ok2 and granted) then
				-- Refund what the REMAINING opens actually cost, prorated out of the
				-- bundle. Refunding egg.Price per remaining open would pay back MORE
				-- than was taken on any discounted bundle -- at x10 that is list price
				-- against the 12%-off price the player really paid, i.e. a profit for
				-- failing to hatch.
				local left = qty - i + 1
				DarrelService.Award(player, math.floor(cost * left / qty + 0.5), "refund:" .. eggId)
				warn(("[EggHandler] hatch failed, refunded %d open(s): %s uid=%d egg=%s rolled=%s err=%s")
					:format(qty - i + 1, player.Name, player.UserId, eggId, tostring(name), tostring(granted)))
				if #results == 0 then
					return refuse(player, "Hatch failed \u{2014} Gems refunded.")
				end
				break
			end
			-- Hatch = discovery. Same name-keyed map ThrowHandler writes for catches,
			-- so the shop's odds tiles (and the Index) can drop their "?" cover the
			-- moment the pet first comes out of a shell.
			data.Discovered = data.Discovered or {}
			data.Discovered[name] = true
			results[#results + 1] = { Name = name, Rarity = rarityOf(name), PetUid = uid, PetId = petId }
		end

		data.EggsOpened[eggId] = (data.EggsOpened[eggId] or 0) + #results
		PDM.PushUpdate(player)
		-- Results drives the multi-open reveal; the top-level single-hatch fields are
		-- kept mirroring Results[1] so the one-egg path is byte-for-byte what it was.
		remotes.EggResult:FireClient(player, {
			Ok = true, EggId = eggId,
			Name = results[1].Name, Rarity = results[1].Rarity,
			PetUid = results[1].PetUid, PetId = results[1].PetId,
			Results = results,
		})

		local saved = PDM.Save(player)  -- after commit; audit on failure (trade-hardening pattern)
		if not saved then
			warn(("[EggHandler] SAVE FAILED after hatch: %s uid=%d egg=%s opened=%d")
				:format(player.Name, player.UserId, eggId, #results))
		end
	end)
	Players.PlayerRemoving:Connect(function(p) lastBuy[p] = nil end)
end

return M
