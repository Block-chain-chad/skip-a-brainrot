-- GiftService -- hand the brainrot you are holding to another player.
--
-- Hold E on someone while holding a brainrot; they get a popup and it only moves
-- if they say yes. A one-way, one-item trade, so it reuses TradeHandler's
-- machinery rather than inventing a second way to move a brainrot:
-- BrainrotMover for the transfer, the same unique-cap pre-flight, the same
-- SyncBackpack-both-sides afterwards, and the same never-roll-back save audit.
--
-- THE CLIENT IS NEVER BELIEVED ABOUT WHAT IT IS HOLDING. The offer carries a Uid,
-- and the server checks that a Tool with that Uid is genuinely in the giver's
-- character before anything else happens. Otherwise "gift" would be a remote that
-- moves any item out of your own inventory by id -- which is only self-harm, but
-- it would also let a client gift a brainrot it had already placed on a pad.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotMover = require(ServerScriptService.Modules.BrainrotMover)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
-- Brainrot bag capacity, re-checked on accept like everything else in validate().
local BagConfig = require(game:GetService("ReplicatedStorage").Modules.BagConfig)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local GiftService = {}
local inited = false

-- Generous against the prompt's own reach: the prompt is client-side so this is
-- the authoritative check, and it only has to stop a gift being flung across the
-- map, not police a step backwards while the popup is up.
local MAX_DISTANCE = 40
-- How long the receiver has to answer before the offer lapses. Long enough to read
-- it, short enough that a forgotten popup does not pin the giver's item forever.
local OFFER_TIMEOUT = 25
local OFFER_COOLDOWN = 2

local pending = {}      -- [receiver] = { from, uid, name, mutation, at, token }
local lastOffer = {}    -- [giver] = os.clock()
local tokenSeq = 0

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = remotes
	end
	return r
end
local offerRemote = getRemote("GiftOffer", "RemoteEvent")     -- giver -> server
local promptRemote = getRemote("GiftPrompt", "RemoteEvent")   -- server -> receiver
local respondRemote = getRemote("GiftRespond", "RemoteEvent") -- receiver -> server

local function notify(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

-- The one true answer to "is this player holding that brainrot right now".
-- Mirrors InventoryHandler's own equippedUidOf, which is a local there.
local function heldUid(player)
	local char = player.Character
	if not char then return nil end
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") and t:GetAttribute("BrainrotTool") then
			return t:GetAttribute("Uid")
		end
	end
	return nil
end

local function entryByUid(data, uid)
	for _, e in ipairs(data.Brainrots or {}) do
		if e.Uid == uid then return e end
	end
	return nil
end

local function apart(a, b)
	local ca, cb = a.Character, b.Character
	local ha = ca and ca:FindFirstChild("HumanoidRootPart")
	local hb = cb and cb:FindFirstChild("HumanoidRootPart")
	if not (ha and hb) then return math.huge end
	return (ha.Position - hb.Position).Magnitude
end

-- Everything that must be true both when the offer is MADE and again when it is
-- ACCEPTED. Re-running it on accept is the point: the popup sits on someone's
-- screen for up to 25 seconds, and in that time the giver can walk off, place the
-- item, sell it, or the receiver can catch a second copy of a one-per-player.
local function validate(giver, receiver, uid)
	if not (giver and receiver) then return false, "That player has gone." end
	if giver == receiver then return false, "You cannot gift to yourself." end
	if giver.Parent == nil or receiver.Parent == nil then return false, "That player has gone." end

	local giverData = PlayerDataManager.Get(giver)
	local recvData = PlayerDataManager.Get(receiver)
	if not (giverData and recvData) then return false, "A profile has not loaded yet." end
	if giverData.__noSave or recvData.__noSave then
		return false, "A profile did not load properly \u{2014} rejoin before gifting."
	end

	if heldUid(giver) ~= uid then return false, "You are not holding that brainrot." end

	local entry = entryByUid(giverData, uid)
	if not entry then return false, "You no longer own that brainrot." end

	if apart(giver, receiver) > MAX_DISTANCE then return false, "You are too far apart." end

	-- UNIQUE CAP, pre-flight. BrainrotMover.Give is deliberately total -- Take has
	-- already mutated the giver by then, so a refusal inside Give would destroy the
	-- item mid-transfer. Failing here is safe: nothing has moved.
	if not BrainrotMover.WithinUniqueCap(entry.Name,
		BrainrotMover.CountOwned(recvData, entry.Name), 0, 1) then
		return false, ("%s is one-per-player and they already have one."):format(entry.Name)
	end

	-- BAG SPACE (2026-08-20). Belongs in validate() rather than at the accept
	-- site precisely because this function runs TWICE -- the receiver can fill
	-- their last slot in the 25 seconds the popup is on their screen.
	if not BagConfig.HasBrainrotSpace(recvData, 1) then
		return false, "Their bag is full \u{2014} they need to sell something first."
	end

	return true, nil, entry, giverData, recvData
end

local function retrySave(player, tag)
	task.spawn(function()
		while true do
			task.wait(30)
			if player.Parent == nil then return end   -- PlayerRemoving owns the save now
			local data = PlayerDataManager.Get(player)
			if not data or data.__noSave then return end
			if PlayerDataManager.Save(player) then
				warn(("[GiftAudit] %s: retry save SUCCEEDED for user %d"):format(tag, player.UserId))
				return
			end
			warn(("[GiftAudit] %s: retry save still failing for user %d"):format(tag, player.UserId))
		end
	end)
end

local function clearPending(receiver)
	pending[receiver] = nil
end

function GiftService.Init()
	if inited then return end
	inited = true

	offerRemote.OnServerEvent:Connect(function(giver, receiver, uid)
		if typeof(receiver) ~= "Instance" or not receiver:IsA("Player") then return end
		if typeof(uid) ~= "number" then return end

		local now = os.clock()
		if now - (lastOffer[giver] or 0) < OFFER_COOLDOWN then return end
		lastOffer[giver] = now

		-- One live offer per receiver: a second popup landing on top of the first
		-- would let one click answer an offer the player never read.
		local live = pending[receiver]
		if live and (now - live.at) < OFFER_TIMEOUT then
			notify(giver, false, receiver.DisplayName .. " already has a gift waiting.")
			return
		end

		local ok, why, entry = validate(giver, receiver, uid)
		if not ok then
			notify(giver, false, why)
			return
		end

		tokenSeq += 1
		pending[receiver] = {
			from = giver, uid = uid, at = now, token = tokenSeq,
			name = entry.Name, mutation = entry.Mutation,
		}
		local myToken = tokenSeq

		promptRemote:FireClient(receiver, {
			From = giver.DisplayName,
			Name = entry.Name,
			Mutation = entry.Mutation,
			Seconds = OFFER_TIMEOUT,
		})
		notify(giver, true, ("Offered %s to %s."):format(entry.Name, receiver.DisplayName))

		-- lapse it rather than leave the giver's item spoken for forever
		task.delay(OFFER_TIMEOUT, function()
			local p = pending[receiver]
			if p and p.token == myToken then
				clearPending(receiver)
				if receiver.Parent then promptRemote:FireClient(receiver, { Expired = true }) end
			end
		end)
	end)

	respondRemote.OnServerEvent:Connect(function(receiver, accept)
		local p = pending[receiver]
		if not p then return end
		clearPending(receiver)

		local giver = p.from
		if accept ~= true then
			if giver and giver.Parent then
				notify(giver, false, receiver.DisplayName .. " declined your gift.")
			end
			return
		end

		-- RE-VALIDATED, not trusted from the offer: see validate()'s note.
		local ok, why, _, giverData, recvData = validate(giver, receiver, p.uid)
		if not ok then
			notify(receiver, false, why)
			if giver and giver.Parent then notify(giver, false, "That gift could not be completed: " .. tostring(why)) end
			return
		end

		-- BY UID, not by name: the giver is holding one specific copy and that is the
		-- one that has to move. See BrainrotMover.TakeByUid.
		local record = BrainrotMover.TakeByUid(giver, giverData, p.uid)
		if not record then
			notify(receiver, false, "That brainrot is gone.")
			return
		end
		BrainrotMover.Give(receiver, recvData, record)

		-- Both sides: the giver was literally holding a Tool backed by the entry that
		-- just changed owners, and the receiver has a new one to show.
		InventoryHandler.SyncBackpack(giver)
		InventoryHandler.SyncBackpack(receiver)
		PlayerDataManager.PushUpdate(giver)
		PlayerDataManager.PushUpdate(receiver)

		local label = record.Mutation and (record.Mutation .. " " .. record.Name) or record.Name
		notify(giver, true, ("\u{1F381} You gave %s to %s!"):format(label, receiver.DisplayName))
		notify(receiver, true, ("\u{1F381} %s gave you %s!"):format(giver.DisplayName, label))

		-- An item has changed hands. A failed save means one side of that is only real
		-- in memory, so log everything needed to restore it by hand and keep retrying.
		-- NEVER roll back: the same rule TradeHandler's audit documents.
		local savedG = PlayerDataManager.Save(giver)
		local savedR = PlayerDataManager.Save(receiver)
		if not (savedG and savedR) then
			warn(("[GiftAudit] SAVE FAILED after gift %d -> %d | savedGiver=%s savedReceiver=%s | item=%s%s")
				:format(giver.UserId, receiver.UserId, tostring(savedG), tostring(savedR),
					record.Mutation and (record.Mutation .. " ") or "", record.Name))
			local tag = ("gift %d->%d"):format(giver.UserId, receiver.UserId)
			if not savedG then retrySave(giver, tag) end
			if not savedR then retrySave(receiver, tag) end
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		lastOffer[p] = nil
		clearPending(p)
		-- and any offer this player had made to someone else
		for receiver, offer in pairs(pending) do
			if offer.from == p then clearPending(receiver) end
		end
	end)

	print(("GiftService online (hold-E, %d stud range, %ds to answer)")
		:format(MAX_DISTANCE, OFFER_TIMEOUT))
end

return GiftService
