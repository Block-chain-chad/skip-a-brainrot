-- Brainrot inventory is PANEL-DRIVEN (2026-08-12 rework, owner-approved).
-- Everything happens in the Bag: click an unequipped brainrot to place it on the
-- first free spot, click an equipped one (card or plot-rack slot) to store it,
-- swap through the replace picker when the plot is full. There are NO Tools, no
-- hold-E StorePrompt and no choose-your-pad aiming any more -- the old Tool/
-- hotbar/held-display system was retired with the rework (its scripts are
-- tombstoned in ServerStorage.AuditBackups.*_pre_invrework).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotSpawner = require(ServerScriptService.Modules.BrainrotSpawner)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local remotes = ReplicatedStorage.Remotes

-- EVERY WORLD'S ROSTER, not just the valley's.
--
-- This was built from BrainrotConfig alone. That is correct TODAY only by accident:
-- BrainrotConfigTundra is deliberately empty (the placeholder roster was wiped on
-- 2026-08-06 pending real content), so World 2 currently contributes no names. The
-- moment it is repopulated, every tundra brainrot would resolve to nil here and
-- valueOf() would price it at $0 -- ranking the game's most valuable tier below the
-- cheapest common in EquipBest and the Bag's income maths alike.
--
-- Read through WorldProgression rather than requiring each config directly, because
-- that module is the single place a new world is registered -- so refilling the
-- tundra roster needs no edit here. Pools come in two shapes (a bare array, or a
-- table with .List), which is the same `Pool.List or Pool` dance TungQuest does.
--
-- NOTE: a profile can still hold brainrots from the WIPED roster (a test profile had
-- 19 of 94). Those price at $0, which is right -- they earn nothing -- so EquipBest
-- correctly ranks them last and leaves them in the bag.
local infoByName = {}
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	local pool = world and world.Pool
	if pool then
		for _, e in ipairs(pool.List or pool) do
			-- first world wins on a duplicate name, so the valley keeps its own entry
			if e.Name and not infoByName[e.Name] then infoByName[e.Name] = e end
		end
	end
end
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do
	if e.Name and not infoByName[e.Name] then infoByName[e.Name] = e end
end

local InventoryHandler = {}

-- What a brainrot is WORTH: its base rate times its mutation multiplier. Defined up
-- here, above its first use -- EquipBest sorts on it and swap/place read it too.
-- (It used to sit below the placement functions, which meant EquipBest resolved it as
-- a nil global and died on its first sort.)
local function valueOf(entry)
	local info = infoByName[entry.Name]
	-- Size is a SECOND mutation axis and multiplies on top of the colour one, so it has to
	-- count here too -- this drives EquipBest's ranking, and without it a Massive would
	-- be ranked as though it were an ordinary one.
	return (info and info.CashPerSecond or 0) * Mutations.Mult(entry.Mutation) * Sizes.Mult(entry.Size)
end

local function notify(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

local function findByUid(data, uid)
	for _, e in ipairs(data.Brainrots) do
		if e.Uid == uid then return e end
	end
	return nil
end

-- padIndex is the spot the player picked. Nil falls back to the first free pad,
-- which is only used if the client could not resolve what they were aiming at.
--
-- `batch` is for EquipBest, which can move sixteen brainrots in one press. It skips
-- the per-item sound, backpack rebuild and data push -- sixteen thuds at once is a
-- wall of noise, and sixteen SyncBackpack passes is sixteen full backpack rebuilds
-- for one action. The caller does all three exactly once at the end.
local function place(player, uid, padIndex, batch)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local entry = findByUid(data, uid)
	if not entry or entry.PadIndex then return end

	-- A player owns one camp per world and both render the same collection, so a place
	-- has to land on all of them. The sound below still fires once, off the first.
	local plots = PlayerDataManager.GetPlots(player)
	if #plots == 0 then notify(player, false, "Claim a base first!") return end

	if padIndex then
		-- never trust the client: the spot must be unlocked and genuinely empty
		local limit = math.min(data.UnlockedSpots or 12, 16)
		if padIndex < 1 or padIndex > limit then
			notify(player, false, "That spot is locked \u{2014} unlock it first.")
			return
		end
		for _, e in ipairs(data.Brainrots) do
			if e.PadIndex == padIndex then
				notify(player, false, "That spot is taken \u{2014} pick an empty one.")
				return
			end
		end
	else
		padIndex = PlayerDataManager.FindFreePad(data)
		if not padIndex then notify(player, false, "No free spots! Unlock more or store one.") return end
	end

	entry.PadIndex = padIndex
	local placed
	for _, plot in ipairs(plots) do
		local m = BrainrotSpawner.Spawn(plot, entry.Name, padIndex, entry.Mutation, entry.Uid, entry.Size)
		placed = placed or m
	end

	-- Positional, so it is heard by whoever is standing on the base rather than
	-- fired flat at everyone. Deliberately here in place() and NOT in Spawner.Spawn:
	-- Spawn also runs to restore every brainrot when a base is claimed, which
	-- would fire a wall of thuds on join.
	if placed and not batch then
		local at = placed:IsA("BasePart") and placed
			or (placed:IsA("Model") and placed.PrimaryPart)
		if at then
			SoundKit.play("place", at, { volume = 0.4, range = 70 })
		end
	end

	if not batch then
		InventoryHandler.SyncBackpack(player)
		PlayerDataManager.PushUpdate(player)
	end
	return placed
end

local function store(player, uid, batch)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local entry = findByUid(data, uid)
	if not entry or not entry.PadIndex then return end

	for _, plot in ipairs(PlayerDataManager.GetPlots(player)) do
		local pads = plot:FindFirstChild("Pads")
		if pads then
			for _, m in ipairs(pads:GetChildren()) do
				if m:GetAttribute("Uid") == uid then m:Destroy() end
			end
		end
	end
	PlayerDataManager.DrainPending(player, entry, data)
	entry.PadIndex = nil
	if not batch then
		InventoryHandler.SyncBackpack(player)
		PlayerDataManager.PushUpdate(player)
	end
end

-- ============================== EQUIP BEST ==============================
-- Fill every unlocked pad with the highest-earning brainrots the player owns,
-- counting what is ALREADY on the base as well as what is in the bag.
--
-- "Best" is the same valueOf() the Bag and Tung's picker use -- the entry's
-- CashPerSecond times its mutation multiplier -- so a Rainbow common can outrank a
-- plain legendary, which is exactly how the income actually works. Ranking on raw
-- rarity instead would quietly leave money on the table.
--
-- Anything already down AND still in the top N is LEFT WHERE IT IS. Only the
-- difference moves: that keeps a player's arrangement intact, avoids destroying and
-- respawning models that were already correct, and means pressing the button twice
-- does nothing the second time.
function InventoryHandler.EquipBest(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	if #PlayerDataManager.GetPlots(player) == 0 then
		notify(player, false, "Claim a base first!")
		return
	end

	-- Same ceiling place() enforces, so this can never fill a pad the player has not
	-- unlocked (16 is the hard cap on pads that exist).
	local limit = math.min(data.UnlockedSpots or 12, 16)

	local ranked = {}
	for _, e in ipairs(data.Brainrots) do
		if e.Uid then ranked[#ranked + 1] = e end
	end
	if #ranked == 0 then
		notify(player, false, "No brainrots to place yet \u{2014} go and catch some!")
		return
	end
	table.sort(ranked, function(a, b)
		local va, vb = valueOf(a), valueOf(b)
		-- Uid breaks ties so the order is STABLE: without it two identical brainrots
		-- can swap places between presses and churn their pad models for no reason.
		if va == vb then return (a.Uid or 0) < (b.Uid or 0) end
		return va > vb
	end)

	local keep, wanted = {}, math.min(limit, #ranked)
	for i = 1, wanted do keep[ranked[i].Uid] = true end

	-- 1. Pull down anything placed that did not make the cut. This has to happen
	--    FIRST or there would be no free pad for the ones coming in.
	local pulled = 0
	for _, e in ipairs(data.Brainrots) do
		if e.PadIndex and not keep[e.Uid] then
			store(player, e.Uid, true)
			pulled += 1
		end
	end

	-- 2. Put down the ones that made the cut and are not already out.
	local placedCount, lastModel = 0, nil
	for i = 1, wanted do
		local e = ranked[i]
		if not e.PadIndex then
			local m = place(player, e.Uid, nil, true)
			if e.PadIndex then
				placedCount += 1
				lastModel = m or lastModel
			end
		end
	end

	InventoryHandler.SyncBackpack(player)
	PlayerDataManager.PushUpdate(player)

	if placedCount == 0 and pulled == 0 then
		notify(player, true, "Your best brainrots are already out.")
		return
	end

	-- one sound for the whole operation, positioned on the last thing placed
	if lastModel then
		local at = lastModel:IsA("BasePart") and lastModel
			or (lastModel:IsA("Model") and lastModel.PrimaryPart)
		if at then SoundKit.play("place", at, { volume = 0.5, range = 70 }) end
	end

	local total = 0
	for _, e in ipairs(data.Brainrots) do
		if e.PadIndex then total += valueOf(e) end
	end
	notify(player, true, ("\u{2B50} Placed %d, stored %d \u{2014} %d/%d spots earning $%s/s")
		:format(placedCount, pulled, math.min(wanted, limit), limit, NumberFormat.Short(total)))
end

--=============================== swap ==============================--
-- The replace picker's one server action: uidOut comes OFF the plot and uidIn
-- takes its exact pad, atomically from the player's point of view. Both halves
-- run in batch mode so the backpack rebuild, data push and sound happen exactly
-- once, and a failed second half rolls the first back rather than leaving the
-- pad empty -- the picker promised a swap, not a maybe.
local function swap(player, uidOut, uidIn)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	-- No plots claimed -> place() cannot run, and neither can the ROLLBACK if the
	-- second half fails -- store would succeed, place would refuse, and the "swap"
	-- would silently degrade into an unequip. Refuse the whole thing up front.
	if #PlayerDataManager.GetPlots(player) == 0 then
		notify(player, false, "Claim a base first!")
		return
	end
	local entryOut = findByUid(data, uidOut)
	local entryIn = findByUid(data, uidIn)
	if not entryOut or not entryOut.PadIndex then return end   -- must be on the plot
	if not entryIn or entryIn.PadIndex then return end         -- must be in the bag

	local padIndex = entryOut.PadIndex
	store(player, uidOut, true)
	local placed = place(player, uidIn, padIndex, true)
	if not entryIn.PadIndex then
		-- second half refused (should not happen -- the pad was just freed and
		-- place() re-validates everything) -- put the original back
		place(player, uidOut, padIndex, true)
	end

	InventoryHandler.SyncBackpack(player)
	PlayerDataManager.PushUpdate(player)

	if placed then
		local at = placed:IsA("BasePart") and placed
			or (placed:IsA("Model") and placed.PrimaryPart)
		if at then SoundKit.play("place", at, { volume = 0.4, range = 70 }) end
	end
end

-- Tools are gone (2026-08-12 rework). This now exists only to CLEAN UP: any
-- BrainrotTool a live session still carries from the old system, and the
-- KeyTools an even earlier pass created, are destroyed on sight. Callers all
-- over the codebase (catches, trades, plot claims) still call this after a
-- data change, which stays correct -- there is simply nothing to rebuild.
function InventoryHandler.SyncBackpack(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in ipairs({ backpack, player.Character }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and (t:GetAttribute("BrainrotTool") or t:GetAttribute("KeyTool")) then
					t:Destroy()
				end
			end
		end
	end
end

function InventoryHandler.Init()
	-- client resolves which pad the player clicked and sends it here
	remotes.PlaceBrainrot.OnServerEvent:Connect(function(player, uid, padIndex)
		if typeof(uid) ~= "number" then return end
		if padIndex ~= nil and typeof(padIndex) ~= "number" then return end
		-- NaN sails through range checks (NaN < 1 and NaN > limit are both false) and
		-- then corrupts the profile as a table key: unsellable item, dead income tick,
		-- unserialisable save. `% 1 ~= 0` also rejects inf (inf % 1 is NaN) and
		-- fractional indexes in one stroke.
		if padIndex ~= nil and (padIndex ~= padIndex or padIndex % 1 ~= 0) then return end
		place(player, uid, padIndex and math.floor(padIndex) or nil)
	end)

	-- the Bag asks to store an equipped brainrot. Ownership is validated against
	-- the DATA, not the world: the uid must be in YOUR profile with a PadIndex.
	-- (The Tool-era check scanned pad MODELS instead -- which deadlocked any entry
	-- that was placed in a loaded profile before its plot restore spawned models:
	-- placed in data, no model, so the scan said "not yours" and it could never be
	-- stored. store() itself destroys whatever models DO exist, so data-truth
	-- handles both the normal case and that half-restored one. Proven live in the
	-- 2026-08-12 rework verification.)
	remotes.StoreBrainrot.OnServerEvent:Connect(function(player, uid)
		if typeof(uid) ~= "number" then return end
		local data = PlayerDataManager.Get(player)
		if not data then return end
		local entry = findByUid(data, uid)
		if not entry or not entry.PadIndex then return end
		store(player, uid)
	end)

	-- "equip" now means PUT IT ON THE PLOT: the Bag fires this for a click on an
	-- unequipped card and the server picks the first free unlocked spot. Same
	-- remote name as the old bring-to-hand flow on purpose -- any stale caller
	-- from the Tool era now does the closest sensible thing instead of erroring.
	remotes.EquipBrainrot.OnServerEvent:Connect(function(player, uid)
		if typeof(uid) ~= "number" then return end
		place(player, uid, nil)
	end)

	-- The replace picker: uidOut off the plot, uidIn onto its exact pad. Guarded
	-- like EquipBest -- a swap tears down and respawns plot models on every camp.
	local swapRemote = remotes:FindFirstChild("SwapBrainrot")
	if not swapRemote then
		swapRemote = Instance.new("RemoteEvent")
		swapRemote.Name = "SwapBrainrot"
		swapRemote.Parent = remotes
	end
	local lastSwap = {}
	swapRemote.OnServerEvent:Connect(function(player, uidOut, uidIn)
		if typeof(uidOut) ~= "number" or typeof(uidIn) ~= "number" then return end
		if uidOut == uidIn then return end
		local now = os.clock()
		if now - (lastSwap[player] or 0) < 0.5 then return end
		lastSwap[player] = now
		local ok, err = pcall(swap, player, uidOut, uidIn)
		if not ok then
			warn("[InventoryHandler] swap failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(p) lastSwap[p] = nil end)

	-- Favorite = "never sell this copy". A flag on the ENTRY (not a side list), so
	-- it rides every existing save/trade/gift path for free; false is stored as nil
	-- to keep serialized profiles exactly as small as before the field existed.
	local favRemote = remotes:FindFirstChild("ToggleFavorite")
	if not favRemote then
		favRemote = Instance.new("RemoteEvent")
		favRemote.Name = "ToggleFavorite"
		favRemote.Parent = remotes
	end
	-- Accepts one uid or a table of them: the Bag stacks identical copies into a
	-- single card, and its padlock has to flip the WHOLE stack in one remote --
	-- per-copy fires would be 264 round-trips on a big stack. Capped defensively;
	-- every uid is still validated against the profile individually.
	favRemote.OnServerEvent:Connect(function(player, uids)
		if typeof(uids) == "number" then uids = { uids } end
		if typeof(uids) ~= "table" or #uids == 0 or #uids > 512 then return end
		local data = PlayerDataManager.Get(player)
		if not data then return end
		local touched = false
		for _, uid in ipairs(uids) do
			if typeof(uid) == "number" then
				local entry = findByUid(data, uid)
				if entry then
					entry.Fav = not entry.Fav or nil
					touched = true
				end
			end
		end
		if touched then PlayerDataManager.PushUpdate(player) end
	end)

	-- The Bag's unlock modal. TryBuySpot does its own wallet check, spot ceiling,
	-- plot refresh and push -- this is just a UI doorway to the same code the
	-- walk-up prompt on the locked pad has always called.
	local buySpotRemote = remotes:FindFirstChild("BuyPlotSpot")
	if not buySpotRemote then
		buySpotRemote = Instance.new("RemoteEvent")
		buySpotRemote.Name = "BuyPlotSpot"
		buySpotRemote.Parent = remotes
	end
	buySpotRemote.OnServerEvent:Connect(function(player)
		PlayerDataManager.TryBuySpot(player)
	end)

	-- "Equip Best" in the Bag. Created here rather than assumed to exist so the
	-- feature works on a place file that has not had the remote added by hand.
	local equipBest = remotes:FindFirstChild("EquipBest")
	if not equipBest then
		equipBest = Instance.new("RemoteEvent")
		equipBest.Name = "EquipBest"
		equipBest.Parent = remotes
	end
	-- One press per second per player: it rewrites up to sixteen pads and respawns
	-- their models, so a held-down button would be a genuine load.
	local lastEquipBest = {}
	equipBest.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if now - (lastEquipBest[player] or 0) < 1 then return end
		lastEquipBest[player] = now
		local ok, err = pcall(InventoryHandler.EquipBest, player)
		if not ok then
			warn("[InventoryHandler] EquipBest failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(p) lastEquipBest[p] = nil end)

	-- migration sweep: a session that joined during the Tool era (or a profile
	-- mid-teleport across the deploy) can still carry BrainrotTools -- purge on
	-- every spawn until the old system is fully out of the wild
	local function hook(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.6)
			InventoryHandler.SyncBackpack(player)
		end)
		if player.Character then
			task.delay(0.6, function() InventoryHandler.SyncBackpack(player) end)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end

	PlayerDataManager.OnPlotClaimed = function(player)
		task.defer(function() InventoryHandler.SyncBackpack(player) end)
	end

	print("InventoryHandler online")
end

return InventoryHandler
