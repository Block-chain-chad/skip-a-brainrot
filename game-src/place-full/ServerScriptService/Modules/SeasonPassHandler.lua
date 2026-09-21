-- SeasonPassHandler: daily quests feed Season XP; XP unlocks a 25-tier reward track.
-- Other handlers report events via SeasonPassHandler.Notify / NotifyCatch (additive hooks).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local SeasonConfig = require(ReplicatedStorage.Modules.SeasonConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
-- Tier rewards are no longer cash-only, so this needs the other grant paths.
-- None of these require SeasonPassHandler back (checked), so no cycle.
local EmeraldService = require(ServerScriptService.Modules.EmeraldService)
local PetHandler = require(ServerScriptService.Modules.PetHandler)
local EggHandler = require(ServerScriptService.Modules.EggHandler)
local GamepassService = require(ServerScriptService.Modules.GamepassService)
local EggConfig = require(ReplicatedStorage.Modules.EggConfig)
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)
-- Pet bag capacity. An Egg reward puts a PET in the bag, so every reward path
-- that can hatch one has to answer to it -- see PetSpaceNeeded below.
local BagConfig = require(ReplicatedStorage.Modules.BagConfig)

local SEASON_PASS_KEY = "SeasonPass"   -- GamepassConfig key gating the paid track

-- Rarity for the EggResult payload -- it drives the hatch reveal's tier lighting.
-- Same PetConfig lookup EggHandler uses: the egg tables name PETS, and a pet name
-- has no BrainrotConfig row.
local function rarityOf(name)
	local id = PetConfig.IdFor(name)
	local def = id and PetConfig.Pets[id]
	return def and def.Rarity
end

-- Hatches `egg` once and grants the pet, i.e. exactly what buying it does.
--
-- Returns the RESULT ROW on success (nil on failure) rather than a bare true: the
-- caller feeds these straight into remotes.EggResult so a reward hatch plays the
-- shop's reveal, and that payload needs the name/rarity/uid. Shaped identically to
-- EggHandler's own `results` rows so the client cannot tell the two apart.
local function hatchOne(player, egg)
	local name = EggHandler.RollFor(egg)
	local petId = name and PetConfig.IdFor(name)
	if not petId then return nil end
	local ok, granted, uid = pcall(PetHandler.Grant, player, petId)
	if not (ok and granted) then return nil end
	local data = PlayerDataManager.Get(player)
	if data then
		-- hatching is discovery, same as the shop path
		data.Discovered = data.Discovered or {}
		data.Discovered[name] = true
	end
	return { Name = name, Rarity = rarityOf(name), PetUid = uid, PetId = petId }
end

-- A uniform pick from a world's egg list, for Egg rewards that say Random rather
-- than naming an Id. UNIFORM ON PURPOSE: weighting by price would make "3 random
-- eggs" almost always three Mossy Eggs, which is not a weekly payoff.
local function randomEgg(world)
	local w = EggConfig.WORLDS and EggConfig.WORLDS[world]
	local list = w and (w.Eggs or w)
	if type(list) ~= "table" then return nil end
	local pool = {}
	for _, e in ipairs(list) do
		if type(e) == "table" and e.Id then pool[#pool + 1] = e end
	end
	if #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

local remotes = ReplicatedStorage.Remotes

-- ToastClient renders { Success, Message } off PurchaseResult -- the game's one
-- notification channel; see StealService's note on reusing it.
local function tell(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok and true or false, Message = msg }) end
end

local rarityIndexByName = {}
for i, tier in ipairs(RarityConfig) do rarityIndexByName[tier.Name] = i end

local SeasonPassHandler = {}

-- Publishes the worn tag as a Player ATTRIBUTE. Attributes replicate to every
-- client automatically and re-replicate to late joiners, which is what lets
-- other players see your title with no remote and no join handshake -- the same
-- reasoning PetHandler gives for its follow loadout.
--
-- Must live BELOW `local SeasonPassHandler = {}`: defined above it this indexes
-- a nil upvalue at require time, which takes down every module that requires
-- this one, and with it the whole server boot chain.
function SeasonPassHandler.PublishTag(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local id = data.EquippedTag
	local def = id and SeasonConfig.TAGS[id]
	player:SetAttribute("EquippedTag", def and def.Label or nil)
end

--[[ THE VIP TITLE (2026-08-09). Bought, not earned, so it is granted from pass
OWNERSHIP rather than claimed from a track -- but it lands in exactly the same place
a tier tag does (data.Tags), which is what lets the backpack's wardrobe treat it like
any other title and lets the player switch away from it without losing it.

Idempotent by the same rule the track relies on: data.Tags[id] = true is a set, so
running this on every join costs nothing after the first.

It only auto-WEARS when nothing else is on. Someone who has chosen a title should not
have it swapped out from under them by a pass they have owned for weeks.
]]
local VIP_TAG_ID = "VIPPass"

function SeasonPassHandler.SyncPassTags(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if not GamepassService.Owns(player, "VIP") then return end
	data.Tags = data.Tags or {}
	if data.Tags[VIP_TAG_ID] then return end
	data.Tags[VIP_TAG_ID] = true
	if not data.EquippedTag then data.EquippedTag = VIP_TAG_ID end
	SeasonPassHandler.PublishTag(player)
	PlayerDataManager.PushUpdate(player)
end

local function currentDay()
	return math.floor(os.time() / 86400)
end

-- reset quest progress when the UTC day rolls over
local function ensureDay(data)
	local today = currentDay()
	if data.SeasonQuestDay ~= today then
		data.SeasonQuestDay = today
		data.SeasonQuests = {}
	end
	return today
end

function SeasonPassHandler.SendState(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local today = ensureDay(data)
	local questIds, progress = {}, {}
	for _, def in ipairs(SeasonConfig.QuestsForDay(today)) do
		table.insert(questIds, def.Id)
		local q = data.SeasonQuests[def.Id]
		progress[def.Id] = { P = q and q.P or 0, D = q and q.D or false }
	end
	remotes.SeasonState:FireClient(player, {
		XP = data.SeasonXP or 0,
		Claimed = data.SeasonClaimed or {},
		-- paid track: its own claim map, plus whether this player may use it at all.
		-- The client uses PassOwned to decide between the buy CTA and live cards;
		-- the server re-checks ownership on every claim regardless.
		PassClaimed = data.SeasonPassClaimed or {},
		PassOwned = GamepassService.Owns(player, SEASON_PASS_KEY) == true,
		QuestIds = questIds,
		Progress = progress,
		Day = today,
	})
end

function SeasonPassHandler.Notify(player, event, n)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local today = ensureDay(data)
	local changed = false
	for _, def in ipairs(SeasonConfig.QuestsForDay(today)) do
		if def.Event == event then
			local q = data.SeasonQuests[def.Id]
			if not q then q = { P = 0, D = false }; data.SeasonQuests[def.Id] = q end
			if not q.D then
				q.P = math.min(q.P + (n or 1), def.Target)
				if q.P >= def.Target then
					q.D = true
					data.SeasonXP = (data.SeasonXP or 0) + def.XP
				end
				changed = true
			end
		end
	end
	if changed then
		SeasonPassHandler.SendState(player)
	end
end

-- XP FROM OUTSIDE THE SEASON QUEST POOL. The weekly emerald quests pay season XP as
-- well as emeralds (EmeraldService.Notify), and data.SeasonXP is THIS module's field:
-- written from over there it would have two owners, and the client -- which learns
-- its XP only from SendState -- would not hear about half the writes. So this is
-- the one door in, and it pushes state on the way out like every other writer here.
--
-- EmeraldService requires this module lazily for exactly this call; see the note on
-- its `season()` helper for why that direction has to be deferred.
function SeasonPassHandler.AwardXP(player, xp, reason)
	local data = PlayerDataManager.Get(player)
	if not data then return false end
	xp = math.floor(tonumber(xp) or 0)
	if xp < 1 or xp ~= xp or xp == math.huge then return false end
	data.SeasonXP = (data.SeasonXP or 0) + xp
	print(("[SeasonXP] +%d -> %s %s (%s)"):format(xp, tostring(data.SeasonXP), player.Name, tostring(reason)))
	PlayerDataManager.PushUpdate(player)
	SeasonPassHandler.SendState(player)
	return true
end

-- Rare = index 3+, Epic = index 4+ (both quests can progress from one catch)
function SeasonPassHandler.NotifyCatch(player, tierName)
	local idx = rarityIndexByName[tierName]
	if not idx then return end
	if idx >= 3 then SeasonPassHandler.Notify(player, "RareCatch", 1) end
	if idx >= 4 then SeasonPassHandler.Notify(player, "EpicCatch", 1) end
end

-- THE ONE REWARD GRANTER. The season track and the daily calendar both route
-- every payout through this, so each Kind is implemented ONCE. SeasonConfig's own
-- header warns that a Kind with no matching branch is a SILENT DUD -- two copies
-- of this switch drifting apart is precisely how that happens.
--
-- The CALLER HAS ALREADY COMMITTED THE CLAIM by the time this runs, so every
-- branch must either succeed or fall back to cash: a reward that silently grants
-- nothing is unrecoverable for that player.
--
--   r             the reward table, { Kind = ..., ... }
--   fallbackCash  paid whenever a branch cannot deliver what it was asked for
--   label         names the caller in warnings: "free tier 13", "daily day 5"
--   reason        audit string handed to EmeraldService.Award
-- HOW MANY PET-BAG SLOTS THIS REWARD WOULD EAT. Zero for every Kind except Egg,
-- because an egg is the only reward that hatches into data.Pets.
--
-- THE POINT OF SPLITTING THIS OUT: GrantReward runs AFTER its caller has already
-- committed the claim, so it can only park an undeliverable egg (see the Egg
-- branch). A caller that can still back out cheaply asks this FIRST and refuses
-- before stamping anything, which is what the owner asked for: a full bag must
-- not be able to claim eggs at all. The tier stays claimable, and the player
-- gets it the moment they make room.
--
-- "CHEAPLY" MEANS THE CLAIM IS STILL THERE TOMORROW -- and that is a property of
-- the SURFACE, not of the reward. claimTier qualifies: the Goals panel reopens
-- whenever the player likes. THE DAILY CALENDAR DOES NOT, and stopped calling
-- this on 2026-08-26. Its rail tile was removed on 2026-08-07, so a refused day
-- could not be claimed later at all -- it was lost, and took the login streak
-- with it. It parks instead. See the long note in DailyRewardHandler.claim.
--
-- EggSet is deliberately NOT counted: WheelHandler expands it into one Egg row
-- per egg in the world at spin time, and each of those rows comes back through
-- here on its own. Counting the set as well would double-count it.
function SeasonPassHandler.PetSpaceNeeded(r)
	if type(r) ~= "table" then return 0 end
	if r.Kind ~= "Egg" then return 0 end
	return math.max(1, tonumber(r.Qty) or 1)
end

function SeasonPassHandler.GrantReward(player, data, r, fallbackCash, label, reason)
	r = r or { Kind = "Cash", Amount = fallbackCash or 0 }
	fallbackCash = fallbackCash or 0
	label = label or "reward"
	reason = reason or "reward"

	if r.Kind == "Emeralds" then
		EmeraldService.Award(player, r.Amount, reason)

	elseif r.Kind == "Boost" then
		-- EXTEND, never replace -- granting a boost while one is already running must
		-- not shorten it. Same rule (and the same data.Boosts field) WheelHandler
		-- uses, so these stack with wheel boosts rather than fighting them.
		data.Boosts = data.Boosts or {}
		local now = os.time()
		local current = tonumber(data.Boosts[r.Stat]) or 0
		data.Boosts[r.Stat] = math.max(current, now) + (r.Minutes or 30) * 60

	elseif r.Kind == "Tag" then
		local tagDef = SeasonConfig.TAGS[r.Id]
		if tagDef and tagDef.Exclusive then
			-- belt and braces: no track lists an exclusive tag, and if one ever did by
			-- mistake this refuses rather than handing out the admin title
			warn(("[Reward] %s tried to grant EXCLUSIVE tag %q -- refused, paying cash")
				:format(label, tostring(r.Id)))
			PlayerDataManager.GrantCash(data, fallbackCash)
		elseif not tagDef then
			warn(("[Reward] %s names unknown tag %q -- paying cash instead")
				:format(label, tostring(r.Id)))
			PlayerDataManager.GrantCash(data, fallbackCash)
		elseif data.Tags and data.Tags[r.Id] then
			-- ALREADY OWNED. data.Tags[Id] = true is idempotent, so re-granting pays
			-- nothing. That is survivable on a 50-tier track you walk once, but the
			-- daily calendar's week REPEATS -- without this the same day would be an
			-- empty card every week forever.
			PlayerDataManager.GrantCash(data, fallbackCash)
		else
			data.Tags = data.Tags or {}
			data.Tags[r.Id] = true
			-- wear the newest one straight away: a title you cannot see is not a
			-- reward, and there is no wardrobe UI to pick from yet
			data.EquippedTag = r.Id
			SeasonPassHandler.PublishTag(player)
		end

	elseif r.Kind == "Egg" then
		-- Qty hatches. With Random set EACH hatch rolls its own egg, so "3 random
		-- eggs" is three independent draws rather than three of whichever one egg
		-- happened to be picked first.
		local world = r.World or "Forest"
		local results, firstEggId = {}, nil
		-- A FULL PET BAG PARKS THE EGG, it does not lose it (2026-08-20).
		-- A caller that can refuse BEFORE committing does so -- claimTier calls
		-- PetSpaceNeeded above and bails without stamping the claim. TWO reach
		-- here anyway.
		--
		-- The WHEEL: the 1% crate has already been rolled, the spin already
		-- spent, and the player has already been shown a chest. Throwing its eggs
		-- away because their bag is full would delete a jackpot.
		--
		-- The DAILY CALENDAR (2026-08-26): it has no second entrance, so refusing
		-- it up front did not defer the reward, it destroyed the day and reset the
		-- streak. See the long note in DailyRewardHandler.claim.
		--
		-- Either way the eggs go into data.PendingEggs and
		-- PetHandler.FlushPendingEggs hands them over the moment room appears (a
		-- sale, a rejoin, or the Bag's claim button).
		local parked = 0
		for _ = 1, math.max(1, r.Qty or 1) do
			local egg = r.Random and randomEgg(world) or EggConfig.GetEgg(world, r.Id)
			if not egg then
				warn(("[Reward] %s names unknown egg %q in world %q -- paying cash instead")
					:format(label, tostring(r.Id), tostring(world)))
				PlayerDataManager.GrantCash(data, fallbackCash)
			elseif not BagConfig.HasPetSpace(data, 1) then
				firstEggId = firstEggId or egg.Id
				-- COUNT THIS CALL'S parks, not the list's length: ParkEgg returns how
				-- many are now waiting in TOTAL, and a player who already had two
				-- parked would be told this one reward owed them three.
				PetHandler.ParkEgg(data, world, egg.Id)
				parked += 1
			else
				firstEggId = firstEggId or egg.Id
				local row = hatchOne(player, egg)
				if row then
					results[#results + 1] = row
				else
					-- a failed hatch refunds the egg's EMERALD price, matching what the
					-- shop does on a failed open -- never left with nothing
					warn(("[Reward] %s hatch of %s failed -- refunding %d emeralds")
						:format(label, tostring(egg.Id), egg.Price))
					EmeraldService.Award(player, egg.Price, reason .. ":hatchfail")
				end
			end
		end

		-- TELL THEM. A parked egg that says nothing is indistinguishable from a
		-- reward that vanished -- which is exactly the failure the owner called
		-- out for the wheel's 1%: "the game will tell the player to claim reward
		-- after making space for eggs".
		--
		-- NoParkToast SUPPRESSES IT for a caller that pays several eggs one call at
		-- a time and wants to say it once: the wheel's crate is exactly that, five
		-- separate Qty=1 grants for one wedge, which would otherwise stack five
		-- identical warnings on top of a chest that is still opening. Absent (the
		-- default) nothing changes. The count is returned below either way.
		if parked > 0 and not r.NoParkToast then
			tell(player, false, ("%d reward egg%s waiting \u{2014} your pet bag is full (%d/%d). Sell a pet or buy space from Enzo, then claim %s in your Bag.")
				:format(parked, parked == 1 and "" or "s",
					BagConfig.PetCount(data), BagConfig.PetCap(data.Upgrades),
					parked == 1 and "it" or "them"))
		end

		-- SHOW IT. Reward eggs used to hatch in silence -- the pet appeared in the bag
		-- and nothing else happened, which reads as the reward vanishing. This is the
		-- SAME remote and the SAME payload shape EggHandler fires after a purchase, so
		-- the shop's own reveal plays, and one call carrying every row means three eggs
		-- open together exactly like an x3 bundle rather than three times in a row.
		--
		-- Source marks it as NOT a purchase: EggShopClient uses that to keep the shop
		-- panel shut and to skip the receipt, neither of which makes sense here.
		-- NoReveal SUPPRESSES THAT, for a caller that shows the hatch itself. The
		-- wheel's loot crate is the one that does: it pays one of every egg in the
		-- world, so the shop's ceremony would run five times back to back over a
		-- wheel that is still turning. Absent (the default) nothing changes.
		if #results > 0 and not r.NoReveal then
			local eggResult = remotes:FindFirstChild("EggResult")
			if eggResult then
				eggResult:FireClient(player, {
					Ok = true,
					EggId = firstEggId,
					Name = results[1].Name,
					Rarity = results[1].Rarity,
					PetUid = results[1].PetUid,
					PetId = results[1].PetId,
					Results = results,
					Source = "reward",
				})
			end
		end

		-- THE HATCH ROWS GO BACK TO THE CALLER, so one that suppressed the reveal
		-- above still knows what it just handed out -- the pets are rolled here and
		-- exist nowhere else. Every other branch returns nil and every existing call
		-- site ignores the result, so this costs them nothing.
		--
		-- Second return: how many were PARKED for a full bag rather than hatched.
		-- Only the crate reads it (to write one summary line instead of five), and
		-- an extra return value is invisible to every caller that does not.
		return results, parked

	else
		PlayerDataManager.GrantCash(data, r.Amount or 0)
	end
end

-- `track` is "free" (default) or "pass". The two tracks claim INDEPENDENTLY --
-- separate claim maps -- so owning the gamepass adds a second column of rewards
-- rather than replacing the free one.
local function claimTier(player, tier, track)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if typeof(tier) ~= "number" or tier ~= math.floor(tier) then return end
	track = (track == "pass") and "pass" or "free"

	-- The paid column is gated SERVER-SIDE. The client hides it too, but that is
	-- cosmetic: this check is the one that matters, and with GamepassId still 0
	-- Owns() is false for everyone so the column simply cannot be claimed yet.
	if track == "pass" and not GamepassService.Owns(player, SEASON_PASS_KEY) then return end

	local def = SeasonConfig.TierFor(track, tier)
	if not def then return end

	local claimField = (track == "pass") and "SeasonPassClaimed" or "SeasonClaimed"
	data[claimField] = data[claimField] or {}
	local claimed = data[claimField]
	local key = tostring(tier) -- datastore-safe key
	if claimed[key] then return end
	if (data.SeasonXP or 0) < SeasonConfig.ThresholdFor(tier) then return end

	-- === A FULL PET BAG BLOCKS THE CLAIM RATHER THAN CONSUMING IT (2026-08-20) ==
	-- Checked HERE, above the commit, precisely because everything below this
	-- line is irreversible: once claimed[key] is set the tier is spent forever,
	-- and GrantReward's contract is that it must then deliver something. Refusing
	-- up front leaves the tier exactly as it was, so the reward is still sitting
	-- there after the player sells a pet.
	local reward = def.Reward or { Kind = "Cash", Amount = def.Cash or 0 }
	local need = SeasonPassHandler.PetSpaceNeeded(reward)
	if need > 0 and not BagConfig.HasPetSpace(data, need) then
		tell(player, false, BagConfig.PetFullMessage(data))
		return
	end

	claimed[key] = true

	-- Claim is already committed above, so the grant must either succeed or fall
	-- back to cash -- a tier that silently granted nothing would be unrecoverable
	-- for that player, the claim flag having already been set. GrantReward holds
	-- that contract for every Kind; see it for the per-branch reasoning.
	SeasonPassHandler.GrantReward(player, data, reward, def.Cash or 0,
		("%s tier %d"):format(track, tier), "season:tier" .. tier)

	PlayerDataManager.PushUpdate(player)
	SeasonPassHandler.SendState(player)
end

function SeasonPassHandler.Init()
	-- (player, tier, track) -- track is optional and defaults to the free column,
	-- so an older client that only sends a tier keeps working unchanged.
	remotes.SeasonClaim.OnServerEvent:Connect(claimTier)
	-- client asks for state once its UI is listening
	remotes.SeasonState.OnServerEvent:Connect(function(player)
		SeasonPassHandler.SendState(player)
	end)

	-- Wardrobe: the backpack's Tags tab asks to wear one. Self-healing create so
	-- a missing instance never blocks Init (EmeraldService's EmeraldState pattern).
	local equip = remotes:FindFirstChild("SeasonTagEquip")
	if not equip then
		equip = Instance.new("RemoteEvent")
		equip.Name = "SeasonTagEquip"
		equip.Parent = remotes
	end
	equip.OnServerEvent:Connect(function(player, tagId)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		-- nil clears the tag; anything else must be a tag this player may wear
		if tagId ~= nil then
			if type(tagId) ~= "string" then return end
			local tagDef = SeasonConfig.TAGS[tagId]
			if not tagDef then return end
			if tagDef.Exclusive then
				-- Exclusive tags are NOT ownership-based: they are recomputed from the
				-- creator allowlist here, every time. That is what makes them
				-- unobtainable -- data.Tags is never consulted, so nothing written
				-- into a save can ever satisfy this branch.
				if not SeasonConfig.IsCreator(player.UserId) then return end
			elseif not (data.Tags and data.Tags[tagId]) then
				return
			end
		end
		data.EquippedTag = tagId
		SeasonPassHandler.PublishTag(player)
		PlayerDataManager.PushUpdate(player)
	end)

	-- Re-publish the worn tag on join. The attribute lives on the Player, not the
	-- save, so it has to be restored every session or a returning player's title
	-- silently disappears until they claim another tag tier.
	local function onJoin(player)
		task.defer(function()
			SeasonPassHandler.PublishTag(player)
		end)
		-- GamepassService checks ownership asynchronously on join, so the deferred pass
		-- above can legitimately answer "not owned". One retry once that has settled --
		-- the same 3s ScooterService waits for the same reason.
		task.delay(3, function()
			if not player.Parent then return end
			SeasonPassHandler.SyncPassTags(player)
			-- AND PUBLISH AGAIN, unconditionally (2026-08-09). The deferred call above
			-- races the DataStore: PublishTag returns silently when the profile has not
			-- loaded yet, and nothing retried it -- so a returning player's title stayed
			-- invisible for the entire session, which is exactly what the join hook was
			-- added to prevent. Measured live: a player wearing Admin had
			-- data.EquippedTag = "Admin" and the replicated attribute still nil.
			--
			-- SyncPassTags cannot cover this on its own -- it early-returns for a tag
			-- already owned, which is every session after the one that granted it.
			SeasonPassHandler.PublishTag(player)
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in ipairs(Players:GetPlayers()) do onJoin(player) end

	-- Bought mid-session: hand the title over now rather than at the next rejoin.
	game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(player, _, wasPurchased)
		if not wasPurchased then return end
		task.defer(function()   -- after GamepassService's own cache update
			if player.Parent then SeasonPassHandler.SyncPassTags(player) end
		end)
	end)
	print("SeasonPassHandler online")
end

return SeasonPassHandler
