-- PetHandler (Forest Egg Shop, Task 11) -- pets. LIVE as of 2026-07-31.
--
-- PetConfig.ENABLED is ON. LuckMult/IncomeMult are read by ThrowHandler and IncomeLoop on
-- every throw/tick respectively and now return REAL multipliers; they still short-circuit
-- to a neutral 1 if the flag is ever turned back off.
--
-- Grant/PetEquip/the follow rig are NOT gated behind ENABLED and never were -- which is
-- why players could already own pets from the egg shop while the flag was off; they simply
-- had no UI to see or equip them. TestAcorn (PetConfig.Pets) exists purely so Grant/equip/
-- the mult seams can be exercised from the command bar.
--
-- THE PET'S BODY IS NOT HERE ANY MORE (2026-08-03). This module used to clone the
-- model, weld it, drag it behind the player on an AlignPosition and bob it from a
-- Heartbeat -- and that is exactly why equipped pets read as luggage: a server rig
-- can only afford to move the root, so a pet could never take a step or turn its
-- head. All of it lives in StarterPlayerScripts.PetVisualsClient now. This module's
-- entire remaining contribution to the visual is publishLoadout: one Player
-- attribute naming what is equipped, which replicates to every client for free.
-- Nothing about a pet's body was ever server-authoritative -- pets have no
-- collision, no hitbox and no gameplay reach (the multipliers below read the
-- profile, never the rig), so there is nothing here for a client to cheat at.
--
-- STACKING LIVES IN PetConfig.StackedMult, not here: LuckHUDClient has to show the same
-- number this returns, and a client-side copy of the rule is how the HUD and the server
-- drift apart.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)
-- The pet BAG's capacity (how many you may own), as opposed to PetConfig's
-- follow slots (how many may walk behind you). Shared with the client so the
-- Bag prints the same "17 / 25" this file refuses on.
local BagConfig = require(ReplicatedStorage.Modules.BagConfig)
-- canonical abbreviator, K through Sp -- see Modules.NumberFormat
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local PetHandler = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local petEquipRemote = getRemote("PetEquip")
-- New in the 2026-08-20 bag pass. Self-healing creates, same as PetEquip above,
-- so a place file that predates them still boots -- but they are also saved as
-- real Instances under ReplicatedStorage.Remotes, because the Bag panel indexes
-- `remotes.SellPet` directly and would error on a remote that only appears once
-- the server's Init has run.
local sellPetRemote = getRemote("SellPet")
local buySlotRemote = getRemote("BuyPetSlot")
local claimEggsRemote = getRemote("ClaimPendingEggs")

-- ToastClient renders { Success, Message } off PurchaseResult -- reuse it rather
-- than inventing a second notification channel (StealService's note, same rule).
local function tell(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok and true or false, Message = msg }) end
end

-- Where each slot walks now lives in PetConfig.FOLLOW_SLOTS, next to the gaits, because
-- the client is what places a pet. It is no longer a fixed offset from the player's
-- facing either: a slot is a distance BACK ALONG THE PATH the player walked, which is
-- what makes a line of pets round a corner instead of swinging through the wall.

-- === Gamepass: premium slot cap ===============================================
-- [player] = bool, cached for the session so the cap check never blocks on
-- MarketplaceService more than once per player. Cleared on PlayerRemoving so a
-- rejoin re-checks rather than trusting a stale table keyed by a live Player object.
local premiumCache = {}

-- id == 0 means no gamepass is configured yet -- UserOwnsGamePassAsync is never called
-- with a bogus id; the premium path just stays inert and everyone gets SLOTS_FREE.
local function ownsPremiumSlots(player)
	local id = PetConfig.PET_SLOTS_GAMEPASS_ID
	if id == 0 then return false end
	if premiumCache[player] ~= nil then return premiumCache[player] end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	local result = (ok and owns) and true or false
	premiumCache[player] = result
	return result
end

-- THE PLAYER'S REAL FOLLOW-SLOT CAP. Since 2026-08-20 this is overwhelmingly a
-- profile read -- 3 free plus whatever they have bought (PetConfig.CapFor) --
-- with the legacy gamepass kept only as a FLOOR. Taking the larger of the two
-- means configuring the pass later can only ever hand a player more slots; it
-- can never take away a slot they paid cash for.
local function slotCap(player)
	local cap = PetConfig.CapFor(PlayerDataManager.Get(player))
	if ownsPremiumSlots(player) then
		cap = math.max(cap, PetConfig.SLOTS_PREMIUM)
	end
	return cap
end

-- === Boost math =================================================================
-- 1 + sum of equipped pets' matching Boost.Amount. Neutral (1) instantly when the
-- feature is off, or when the player/data/pets can't be resolved -- callers on the hot
-- throw/income paths must never be able to turn a lookup failure into a multiplier of 0.
-- A pet now carries BOTH a luck and an income multiplier (a Secret is 5x luck AND 10x
-- money), which the old single Boost.Type shape could not express.
--
-- Boosts are looked up from PetConfig by Id at READ time, not read off the owned record.
-- That is deliberate: a rebalance in PetConfig then reaches pets players already own,
-- instead of leaving every existing pet frozen at whatever the numbers were on the day it
-- hatched. The stored record's Boost field is still honoured as a fallback so any pet
-- granted under the old shape keeps working.
-- Boost resolution and the additive stacking rule both live in PetConfig.StackedMult now
-- (ReplicatedStorage), so the luck HUD can compute the identical number client-side.
-- The legacy single-type record fallback moved there with it.

-- Stacking is ADDITIVE on the bonus portion: one 5x Secret gives 5x, two give 9x, not 25x.
-- Multiplying would make a third Secret worth more than the first two combined and put
-- luck somewhere no clamp could sensibly follow.
local function boostMult(player, boostType)
	if not PetConfig.ENABLED then return 1 end
	local data = PlayerDataManager.Get(player)
	if not data then return 1 end
	return PetConfig.StackedMult(data.Pets, data.PetSlots, boostType)
end

function PetHandler.LuckMult(player)
	if not PetConfig.ENABLED then return 1 end
	return boostMult(player, "Luck")
end

function PetHandler.IncomeMult(player)
	if not PetConfig.ENABLED then return 1 end
	return boostMult(player, "Income")
end

-- Validates petId against PetConfig.Pets and appends a new owned-pet record. Does NOT
-- equip it -- PetEquip (client-driven) is the only path into data.PetSlots.
--
-- The record stores Uid + Id ONLY. Boosts are resolved from PetConfig on read (see
-- boostsFor) so rebalances apply retroactively; baking them in here is what would
-- freeze every owned pet at its hatch-day numbers.
--
-- THE BAG CAP IS ENFORCED HERE, and here is the LAST line of defence rather than
-- the first (2026-08-20). Every caller that can still refuse cleanly checks
-- BagConfig.HasPetSpace BEFORE it commits anything -- the egg shop before it
-- spends emeralds, a season tier before it stamps the claim, the wheel by
-- parking the egg instead. This check exists so that a path nobody updated
-- cannot quietly push a 26th pet into a 25-slot bag; it returns false + a reason
-- rather than erroring, which is the shape every existing caller already tests.
function PetHandler.Grant(player, petId)
	local def = PetConfig.Pets[petId]
	if not def then return false, "unknown" end
	local data = PlayerDataManager.Get(player)
	if not data then return false, "noprofile" end
	data.Pets = data.Pets or {}
	if not BagConfig.HasPetSpace(data, 1) then return false, "full" end

	local uid = HttpService:GenerateGUID(false)
	table.insert(data.Pets, { Uid = uid, Id = petId })
	PlayerDataManager.PushUpdate(player)
	return true, uid
end

-- === Selling a pet ============================================================
-- The pet bag's only drain (owner, 2026-08-20). Eggs come in ten at a time and
-- nothing took pets back out, so a 25-slot bag would simply have jammed.
--
-- AN EQUIPPED PET IS REFUSED, not silently unequipped. Selling is irreversible
-- and a loadout slot is the one place a player has deliberately put a pet, so
-- "unequip it first" is one extra click against permanently deleting the pet
-- somebody's whole luck multiplier was riding on. The Bag says exactly that.
--
-- Price comes from PetConfig.SellValue (rarity base x the pet's own income
-- multiplier), never from anything the client sends -- the remote carries a uid
-- and nothing else.
function PetHandler.Sell(player, uid)
	if typeof(uid) ~= "string" then return false end
	local data = PlayerDataManager.Get(player)
	if not data or type(data.Pets) ~= "table" then return false end
	-- A read-only session discards every write at logout, so selling in one would
	-- destroy the pet and hand back cash that never persists (see gotcha: a failed
	-- DataStore load serves a DEFAULT profile). Same guard the egg shop uses.
	if data.__noSave then
		tell(player, false, "Your profile did not load \u{2014} rejoin before selling pets.")
		return false
	end

	local index
	for i, pet in ipairs(data.Pets) do
		if pet.Uid == uid then index = i break end
	end
	if not index then
		tell(player, false, "You don't own that pet.")
		return false
	end

	for _, u in ipairs(data.PetSlots or {}) do
		if u == uid then
			tell(player, false, "That pet is equipped \u{2014} unequip it in your Bag first.")
			return false
		end
	end

	local pet = data.Pets[index]
	local def = PetConfig.Pets[pet.Id]
	local value = PetConfig.SellValue(pet.Id)
	table.remove(data.Pets, index)
	PlayerDataManager.GrantCash(data, value)

	remotes.SellResult:FireClient(player, {
		Success = true,
		-- NumberFormat.Cash adds the "$" and abbreviates the way every other sell
		-- toast in the game does; a bare number here is what printed float dust on
		-- the brainrot path (see SellHandler's note).
		Message = "Sold " .. ((def and def.Name) or "pet") .. " for " .. NumberFormat.Cash(value),
		Amount = value,
	})
	PlayerDataManager.PushUpdate(player)
	-- SPACE JUST OPENED. If a reward egg was parked waiting for exactly this, hand
	-- it over now rather than making the player find a claim button.
	PetHandler.FlushPendingEggs(player)
	return true
end

-- === Buying a follow slot =====================================================
-- Slots 4-5 are cash, 6-8 are Robux placeholders (PetConfig.SLOT_ROBUX, every
-- ProductId still the 0 sentinel). The client sends WHICH slot it thinks it is
-- buying and the server checks that against the next one actually owed, so a
-- stale panel cannot buy slot 5 for slot 4's price or skip 6 to reach 8.
local function onBuyPetSlot(player, slot)
	slot = tonumber(slot)
	if not slot or slot ~= math.floor(slot) then return end
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if data.__noSave then
		tell(player, false, "Your profile did not load \u{2014} rejoin before buying slots.")
		return
	end

	local unlock = PetConfig.SlotUnlock(slot)
	if unlock.Kind == "free" then return end

	if unlock.Kind == "cash" then
		-- IN ORDER, no gaps: the profile stores a COUNT of bought slots, so buying
		-- out of order would be unrepresentable rather than merely odd.
		local owned = math.clamp(tonumber(data.PetSlotsBought) or 0, 0, PetConfig.CASH_SLOTS)
		local nextSlot = PetConfig.SLOTS_FREE + owned + 1
		if slot ~= nextSlot then
			if slot < nextSlot then
				tell(player, false, ("Slot %d is already unlocked."):format(slot))
			else
				tell(player, false, ("Buy slot %d first."):format(nextSlot))
			end
			return
		end
		local price = unlock.Price
		if (tonumber(data.Cash) or 0) < price then
			tell(player, false, ("Slot %d costs %s \u{2014} keep skipping!"):format(slot, NumberFormat.Cash(price)))
			return
		end
		data.Cash -= price
		data.PetSlotsBought = owned + 1
		tell(player, true, ("Pet slot %d unlocked!"):format(slot))
		PlayerDataManager.PushUpdate(player)
		-- Republish: the cap is a Player ATTRIBUTE, and the Bag's slot row draws
		-- from it. Without this the new slot stays locked on screen until the next
		-- equip or rejoin.
		PetHandler.PublishLoadout(player)
		return
	end

	if unlock.Kind == "robux" then
		-- PLACEHOLDER. Nothing is charged and nothing is granted while the product
		-- id is 0 -- see PetConfig.SLOT_ROBUX's >>> TO ACTIVATE <<< block. When the
		-- products exist, this becomes a MarketplaceService:PromptProductPurchase
		-- and the GRANT moves into ProductRegistry's ProcessReceipt, which is the
		-- only place a Robux purchase may be honoured (a receipt, never a client
		-- claim). Do not grant the slot here.
		if not unlock.Live then
			tell(player, false, ("Pet slot %d is coming soon!"):format(slot))
			return
		end
		tell(player, false, "Robux pet slots are not wired up yet.")
		return
	end
end

-- === Reward eggs parked by a full bag =========================================
-- Hands over as many parked eggs as there is now room for, oldest first, and
-- plays the egg shop's own reveal for the batch. Safe to call at any time: it
-- no-ops on an empty list or a full bag.
--
-- ENTRIES ARE POPPED BEFORE THE GRANT, not after. GrantReward's Egg branch
-- re-parks anything it cannot deliver, so granting first would let the same egg
-- be counted twice -- once in the list it came from and once in the re-park.
-- Taking at most PetSpace() of them means the grants below always fit.
function PetHandler.FlushPendingEggs(player)
	local data = PlayerDataManager.Get(player)
	if not data or type(data.PendingEggs) ~= "table" then return 0 end
	if #data.PendingEggs == 0 then return 0 end
	local room = BagConfig.PetSpace(data)
	if room <= 0 then return 0 end

	local batch = {}
	for _ = 1, math.min(room, #data.PendingEggs) do
		batch[#batch + 1] = table.remove(data.PendingEggs, 1)
	end

	-- Lazy require: SeasonPassHandler requires THIS module at load, so a
	-- top-level require here would close the cycle and take the boot chain down
	-- with it (the same reason WheelHandler defers its own).
	local SeasonPassHandler = require(ServerScriptService.Modules.SeasonPassHandler)
	local rows, firstEggId = {}, nil
	for _, e in ipairs(batch) do
		firstEggId = firstEggId or e.Id
		local got = SeasonPassHandler.GrantReward(player, data,
			{ Kind = "Egg", World = e.World, Id = e.Id, Qty = 1, NoReveal = true },
			0, "pending egg", "pending:egg")
		for _, row in ipairs(got or {}) do rows[#rows + 1] = row end
	end

	PlayerDataManager.PushUpdate(player)
	if #rows == 0 then return 0 end

	-- ONE reveal for the whole batch -- the same remote and payload shape
	-- EggHandler fires after a purchase, so the shop's ceremony opens them
	-- together like an x3 bundle rather than once per egg.
	local eggResult = remotes:FindFirstChild("EggResult")
	if eggResult then
		eggResult:FireClient(player, {
			Ok = true, EggId = firstEggId,
			Name = rows[1].Name, Rarity = rows[1].Rarity,
			PetUid = rows[1].PetUid, PetId = rows[1].PetId,
			Results = rows, Source = "reward",
		})
	end
	local left = #data.PendingEggs
	if left > 0 then
		tell(player, true, ("%d more reward egg%s waiting \u{2014} make room and claim again.")
			:format(left, left == 1 and "" or "s"))
	end
	return #rows
end

-- Parks a reward egg the player has already won but cannot hold. Called by
-- SeasonPassHandler's Egg branch, which is the one grant path that cannot
-- refuse -- by the time it runs, a wheel wedge has been rolled and a claim
-- stamped. Returns how many are now waiting, for the caller's toast.
function PetHandler.ParkEgg(data, world, eggId)
	if type(data) ~= "table" then return 0 end
	data.PendingEggs = data.PendingEggs or {}
	table.insert(data.PendingEggs, { World = world, Id = eggId })
	return #data.PendingEggs
end

-- Read by the bag UI so it never has to duplicate the rarity/boost lookup.
function PetHandler.Describe(petId)
	local def = PetConfig.Pets[petId]
	if not def then return nil end
	local luck, income = PetConfig.BoostsFor(petId)
	return { Id = petId, Name = def.Name, Rarity = def.Rarity, Luck = luck, Income = income }
end

-- === Follow loadout ============================================================
-- The ONE thing the client needs in order to build a pet: which pet Ids are in
-- which slot, in slot order. Published as a Player attribute rather than pushed
-- down a remote because attributes replicate to EVERY client automatically -- that
-- is what keeps other players' pets visible to you without this module knowing or
-- caring who is watching, and it re-replicates to late joiners with no join
-- handshake to get wrong.
--
-- Written on every equip/unequip and once per join (after the profile lands). The
-- attribute lives on the Player, not the Character, so it survives respawns and a
-- rebuild after death costs nothing.
-- PUBLIC since 2026-08-20 (was a file-local). The slot-purchase path has to
-- republish the cap the moment a slot is bought, or the Bag's slot row keeps
-- drawing the new slot as locked until the next equip or rejoin.
function PetHandler.PublishLoadout(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end

	local owned = {}
	for _, pet in ipairs(data.Pets or {}) do
		owned[pet.Uid] = pet
	end

	-- Ids, not Uids: the client only ever needs to know WHICH creature to build, and
	-- a Uid would leak a player's inventory keys to every other client for nothing.
	local ids = {}
	for _, uid in ipairs(data.PetSlots or {}) do
		local pet = owned[uid]
		if pet and pet.Id then
			table.insert(ids, pet.Id)
		end
	end

	player:SetAttribute(PetConfig.LOADOUT_ATTR, table.concat(ids, "|"))

	-- 2026-08-11: the bag UI draws a slot row (3 free / 5 with the gamepass)
	-- and needs the player's REAL cap -- the client cannot ask
	-- MarketplaceService about gamepass ownership itself. Published beside the
	-- loadout so it exists from the same moment (join) and refreshes with
	-- every equip; a mid-session pass purchase lands on the next equip touch
	-- or rejoin (premiumCache is session-scoped, same as before).
	player:SetAttribute("PetSlotCap", slotCap(player))
end

-- === PetEquip remote: uid must be an owned pet, and equipping is capped at slotCap ===
local function onPetEquip(player, uid, equip)
	if typeof(uid) ~= "string" then return end
	equip = equip and true or false

	local data = PlayerDataManager.Get(player)
	if not data or type(data.Pets) ~= "table" then return end

	local owned = false
	for _, pet in ipairs(data.Pets) do
		if pet.Uid == uid then owned = true break end
	end
	if not owned then return end

	data.PetSlots = data.PetSlots or {}
	local idx
	for i, u in ipairs(data.PetSlots) do
		if u == uid then idx = i break end
	end

	if equip then
		if idx then return end -- already equipped: no-op, not an error
		if #data.PetSlots >= slotCap(player) then return end
		table.insert(data.PetSlots, uid)
	else
		if not idx then return end
		table.remove(data.PetSlots, idx)
	end

	PlayerDataManager.PushUpdate(player)
	PetHandler.PublishLoadout(player)
end

local function hookCharacter(player, character)
	-- WAIT FOR THE PROFILE. publishLoadout reads data.PetSlots and returns silently when
	-- PlayerDataManager.Get is still nil, and on a JOIN the character beats the DataStore
	-- load -- so a returning player with pets equipped spawned with nothing following
	-- them, and nothing ever re-ran the rig. They had to respawn or re-toggle equip to
	-- see their own pets. Bounded at ~10s so a profile that never loads cannot leak a
	-- spinning task; the character check keeps a stale wait from publishing onto a
	-- player who has already left.
	--
	-- No Died hook any more: the attribute describes the player, not the body, so it
	-- stays correct through death and respawn. The client drops a rig when the
	-- character goes and rebuilds it when the next one arrives.
	task.spawn(function()
		for _ = 1, 100 do
			if PlayerDataManager.Get(player) then break end
			task.wait(0.1)
		end
		if player.Parent and player.Character == character then
			PetHandler.PublishLoadout(player)
			-- A reward egg parked by a full bag on a previous session is handed over
			-- as soon as there is room -- including room made by selling pets and
			-- logging off. Costs nothing when the list is empty, which is almost
			-- always.
			pcall(PetHandler.FlushPendingEggs, player)
		end
	end)
end

-- Bulk sell for the sell counter's pets tab. Deliberately loops the single-uid
-- path rather than reimplementing it, so the equipped-pet refusal and the
-- __noSave guard cannot drift between the two.
function PetHandler.SellMany(player, uids)
	if type(uids) ~= "table" then return 0, 0 end
	local data = PlayerDataManager.Get(player)
	local sold, total = 0, 0
	for _, uid in ipairs(uids) do
		-- Read the pet's value BEFORE selling it, from the same source Sell uses
		-- (PetConfig.SellValue). This makes the total independent of any cash mutations
		-- (e.g. IncomeLoop ticks) that might occur during the Sell call.
		local value = 0
		if data and type(data.Pets) == "table" then
			for _, pet in ipairs(data.Pets) do
				if pet.Uid == uid then
					value = PetConfig.SellValue(pet.Id)
					break
				end
			end
		end
		if PetHandler.Sell(player, uid) then
			sold += 1
			total += value
		end
	end
	return sold, total
end

function PetHandler.Init()
	petEquipRemote.OnServerEvent:Connect(onPetEquip)
	-- The Bag's pet detail column. Carries a uid and nothing else -- the price,
	-- the equipped check and the cash are all decided in PetHandler.Sell.
	sellPetRemote.OnServerEvent:Connect(function(player, uidOrList)
		if type(uidOrList) == "table" then
			PetHandler.SellMany(player, uidOrList)
		else
			PetHandler.Sell(player, uidOrList)
		end
	end)
	buySlotRemote.OnServerEvent:Connect(onBuyPetSlot)
	-- "I made room, give me my eggs." Grants nothing that was not already won and
	-- already paid for, so spamming it yields one reveal and then nothing.
	claimEggsRemote.OnServerEvent:Connect(function(player)
		local n = PetHandler.FlushPendingEggs(player)
		if n == 0 then
			local data = PlayerDataManager.Get(player)
			if data and type(data.PendingEggs) == "table" and #data.PendingEggs > 0 then
				tell(player, false, BagConfig.PetFullMessage(data))
			end
		end
	end)

	-- Sweep up the old server-side rig container if a place file still carries one.
	-- Nothing writes to it any more, so anything left inside is a frozen pet from
	-- before the client took the rig over.
	local stale = game:GetService("Workspace"):FindFirstChild("PetRigs")
	if stale then stale:Destroy() end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end)

	-- Handle players already in-game (Studio test start) the same way Main does.
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		if player.Character then
			hookCharacter(player, player.Character)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		premiumCache[player] = nil
	end)
end

return PetHandler
