-- EggHandler (Forest Egg Shop) -- server-authoritative buy -> roll -> grant.
-- Spend and grant happen back-to-back with no yields in EggHandler's own code in
-- between: TrySpend commits the Emerald deduction, then the roll and the Give must
-- land before anything else can observe the player's state, or a mid-purchase
-- disconnect could pay without delivering (or deliver without paying, if reversed).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PDM = require(script.Parent.PlayerDataManager)
local EmeraldService = require(script.Parent.EmeraldService)
local BrainrotMover = require(script.Parent.BrainrotMover)
local InventoryHandler = require(script.Parent.InventoryHandler)
local EggConfig = require(RS.Modules.EggConfig)
local BrainrotConfig = require(RS.Modules.BrainrotConfig)
local PetConfig = require(RS.Modules.PetConfig)
local BagConfig = require(RS.Modules.BagConfig)
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

	-- EVERY egg stall, gated on its own world's Active flag (2026-08-23).
	--
	-- This was a single hard-coded lookup that force-enabled the FOREST prompt only
	-- ("the prompt was found disabled once; server asserts it on every boot"). The
	-- other two stalls stayed enabled from Studio while their worlds had no EggConfig
	-- data at all, and the shop shell of the day bound its world at load -- so walking
	-- up to the Frozen Tundra stall opened WORLD 1's catalogue. Verified live at the
	-- time: it offered Mossy / Reedwater / Bramble / Hollow / Heartwood and rendered
	-- ForestEgg1..5, standing in front of five Frost egg displays. (EggShopClient has
	-- since been taught to hold a set of cards per world and swap between them, so
	-- that half of the fault is gone; this half -- the prompt -- still lives here.)
	--
	-- The world is now the authority. A world that is both Active and ShopReady gets
	-- its prompt asserted ON and labelled with its own keeper; anything else is
	-- relabelled so the stall reads as a storefront that has not opened yet, and
	-- EggShopClient refuses to open the shop for it. Opening one is then a single flag
	-- flip in EggConfig -- no code change here.
	--
	-- Left ENABLED rather than disabled on purpose: a disabled prompt renders nothing
	-- at all, so the player gets no explanation for a shop they can plainly see. An
	-- enabled prompt carrying "Coming Soon" is the message.
	local STALL_WORLDS = { EggStall = "Forest", TundraEggStall = "Tundra", GardensEggStall = "Gardens" }
	local gameWorld = workspace:FindFirstChild("GameWorld")
	for stallName, worldId in pairs(STALL_WORLDS) do
		local stall = gameWorld and gameWorld:FindFirstChild(stallName)
		local promptPart = stall and stall:FindFirstChild("PromptPart")
		local stallPrompt = promptPart and promptPart:FindFirstChild("EggPrompt")
		if stallPrompt then
			local w = EggConfig.GetWorld(worldId)
			-- BOTH flags, deliberately. Active says the server will sell this world;
			-- ShopReady says EggShopClient can actually DISPLAY it. Gating on Active
			-- alone would let a prompt promise "Open Eggs" and then open nothing, which
			-- is worse than saying so.
			--
			-- THE COPY IS WRITTEN ON BOTH PATHS, which it did not used to be: only the
			-- "Coming Soon" branch set the text, so the moment the Tundra world opened
			-- its stall fell back to whatever was authored on the prompt in Studio --
			-- which was the Forest's, and the Frozen Tundra stall greeted the player as
			-- "Gino the Egg Keeper". Naming the world's own keeper here means the stall
			-- and the world it sells can never disagree again. A closed stall names the
			-- WORLD rather than its keeper, so the player can see which shop is coming.
			local open = (w and w.Active and w.ShopReady ~= false) or false
			local worldName = (w and w.DisplayName) or worldId
			stallPrompt.Enabled = true
			stallPrompt.ObjectText = (open and w.Keeper) or (worldName .. " Eggs")
			stallPrompt.ActionText = open and "Open Eggs" or "Coming Soon"
		end
	end

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
		-- === PET BAG SPACE, CHECKED BEFORE A SINGLE EMERALD MOVES (2026-08-20) ===
		-- Owner spec: a full pet bag must not be able to buy eggs at all. This has
		-- to sit ABOVE TrySpend, not inside the grant loop: PetHandler.Grant now
		-- refuses a 26th pet, and reaching that with the emeralds already debited
		-- would turn a full bag into the refund path -- an x10 that charges, hatches
		-- nothing and pays itself back, which reads to a player as the shop being
		-- broken rather than as their bag being full.
		--
		-- THE WHOLE BUNDLE MUST FIT. Partially filling an x10 would leave the player
		-- to work out which of their ten hatched; the message names how many do fit
		-- so the fix is obvious (buy the smaller bundle, or go sell something).
		if not BagConfig.HasPetSpace(data, qty) then
			local room = BagConfig.PetSpace(data)
			if room <= 0 then
				return refuse(player, BagConfig.PetFullMessage(data))
			end
			return refuse(player, ("Only room for %d more pet%s \u{2014} sell some in your Bag, or buy space from Enzo.")
				:format(room, room == 1 and "" or "s"))
		end

		local cost = EggConfig.BundleCost(egg, qty)
		if not cost then return end
		if not EmeraldService.TrySpend(player, cost, "egg:" .. eggId .. ":x" .. qty) then
			return refuse(player, ("Not enough Emeralds (need %d)."):format(cost))
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
				EmeraldService.Award(player, math.floor(cost * left / qty + 0.5), "refund:" .. eggId)
				warn(("[EggHandler] hatch failed, refunded %d open(s): %s uid=%d egg=%s rolled=%s err=%s")
					:format(qty - i + 1, player.Name, player.UserId, eggId, tostring(name), tostring(granted)))
				if #results == 0 then
					return refuse(player, "Hatch failed \u{2014} Emeralds refunded.")
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
