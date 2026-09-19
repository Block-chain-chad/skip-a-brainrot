-- TradeHandler (Trading Center section)
-- Pet Simulator-style trading: request -> both players build an offer ->
-- both confirm -> short countdown -> server swaps the items.
-- EVERY rule is enforced here on the server. The client UI can only ask.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotMover = require(ServerScriptService.Modules.BrainrotMover)
-- no require cycle: InventoryHandler only requires PlayerDataManager/BrainrotSpawner
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
-- Brainrot bag capacity. A trade is a transfer path, so it takes the same
-- PRE-FLIGHT treatment the unique cap already gets here -- see below.
local BagConfig = require(ReplicatedStorage.Modules.BagConfig)

local remotes = ReplicatedStorage.Remotes

local REQUEST_TIMEOUT = 20 -- seconds a trade invite stays valid
local COUNTDOWN_SECONDS = 3 -- final "last chance to cancel" timer

-- Both traders share ONE session table, indexed here under each user id.
local sessions = {} -- [userId] = session
local pendingRequests = {} -- [targetUserId] = { fromUserId = ..., at = os.clock() }

local TradeHandler = {}

-- === Trading Center zone check (same pattern as the throw zone) ===

local function isInTradeZone(character)
	local gameWorld = Workspace:FindFirstChild("GameWorld")
	local center = gameWorld and gameWorld:FindFirstChild("TradingCenter")
	local zone = center and center:FindFirstChild("TradeZone")
	if not zone then return false end
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local rel = zone.CFrame:PointToObjectSpace(hrp.Position)
	local s = zone.Size / 2
	return math.abs(rel.X) <= s.X and math.abs(rel.Z) <= s.Z and math.abs(rel.Y) <= s.Y + 6
end

-- === small helpers ===

local function otherPlayer(session, player)
	if session.players[1] == player then return session.players[2] end
	return session.players[1]
end

-- Offers are name-based, so what an offer line REALLY hands over depends on
-- which copy Take() will select. Resolve it the same way Take does (the
-- least-Mutations.Mult match, READ-ONLY - nothing here mutates data) so the
-- payload can carry the winning copy's Mutation + Serial and the other side
-- sees "Golden Tim Cheese #12" instead of a bare name taken on faith.
local function resolveOffered(data, name)
	local best, bestMult
	for _, entry in ipairs(data.Brainrots) do
		if entry.Name == name then
			local mult = Mutations.Mult(entry.Mutation)
			if not bestMult or mult < bestMult then
				best, bestMult = entry, mult
			end
		end
	end
	return best
end

local function offerDetails(player, offer)
	local details = {}
	local data = PlayerDataManager.Get(player)
	if data then
		for name in pairs(offer.Items) do
			local entry = resolveOffered(data, name)
			if entry then
				details[name] = { Mutation = entry.Mutation, Serial = entry.Serial }
			end
		end
	end
	return details
end

-- Send both players their view of the trade ("You" vs "Them").
local function pushState(session, phase, extra)
	local details = {}
	for _, p in ipairs(session.players) do
		details[p.UserId] = offerDetails(p, session.offers[p.UserId])
	end
	for _, p in ipairs(session.players) do
		local other = otherPlayer(session, p)
		local state = {
			Phase = phase,
			OtherName = other.DisplayName,
			You = {
				Items = session.offers[p.UserId].Items,
				Details = details[p.UserId],   -- [name] = { Mutation, Serial } of the copy Take() will pick
				Cash = session.offers[p.UserId].Cash,
				Confirmed = session.confirmed[p.UserId] == true,
			},
			Them = {
				Items = session.offers[other.UserId].Items,
				Details = details[other.UserId],
				Cash = session.offers[other.UserId].Cash,
				Confirmed = session.confirmed[other.UserId] == true,
			},
		}
		if extra then
			for k, v in pairs(extra) do state[k] = v end
		end
		remotes.TradeState:FireClient(p, state)
	end
end

local function closeSession(session, message)
	if session.closed then return end
	session.closed = true
	session.countdownToken += 1
	for _, p in ipairs(session.players) do
		sessions[p.UserId] = nil
		if p.Parent then
			remotes.TradeState:FireClient(p, { Phase = "Closed", Message = message })
		end
	end
end

-- Any change to an offer un-confirms BOTH sides and stops any countdown.
-- This is the core anti-scam rule.
local function resetConfirmations(session)
	session.confirmed = {}
	session.countdownToken += 1
end

local function createSession(playerA, playerB)
	-- __noSave = the DataStore read failed for that profile, so NOTHING this
	-- session does can persist. Items traded OUT of it come back on rejoin (a
	-- dupe) and items traded INTO it evaporate. Refuse to open the session.
	for _, p in ipairs({ playerA, playerB }) do
		local d = PlayerDataManager.Get(p)
		if not d or d.__noSave then
			remotes.TradeState:FireClient(p, { Phase = "Error", Message = "Your profile did not load - rejoin before trading." })
			local other = (p == playerA) and playerB or playerA
			remotes.TradeState:FireClient(other, { Phase = "Error", Message = p.DisplayName .. "'s profile did not load, so this trade can't start." })
			return
		end
	end
	local session = {
		players = { playerA, playerB },
		offers = {
			[playerA.UserId] = { Items = {}, Cash = 0 },
			[playerB.UserId] = { Items = {}, Cash = 0 },
		},
		confirmed = {},
		countdownToken = 0,
		closed = false,
	}
	sessions[playerA.UserId] = session
	sessions[playerB.UserId] = session
	pushState(session, "Active")
end

-- === the actual swap ===

local function transferItems(giver, giverData, receiver, receiverData, offer)
	local moved = {}
	for name, count in pairs(offer.Items) do
		for _ = 1, count do
			-- hand over the RECORD that was actually taken, so the mutation travels
			-- with the item instead of being silently dropped
			local record = BrainrotMover.Take(giver, giverData, name)
			if record then
				BrainrotMover.Give(receiver, receiverData, record)
				table.insert(moved, record)
			end
		end
	end
	return moved
end

-- "Golden Tim Cheese #12, Pete" - enough detail in one audit line to
-- reconstruct a failed-save trade by hand.
local function describeRecords(records)
	local parts = {}
	for _, r in ipairs(records) do
		local s = r.Name
		if r.Mutation then s = r.Mutation .. " " .. s end
		if r.Serial then s = s .. " #" .. tostring(r.Serial) end
		table.insert(parts, s)
	end
	if #parts == 0 then return "none" end
	return table.concat(parts, ", ")
end

-- The swap has already committed in memory; it must eventually land on disk
-- for BOTH sides or one side dupes and the other loses. Save() retries 3x
-- internally - if it still failed, keep retrying in the background. NEVER
-- roll back the in-memory state: the other half may already be saved.
local function retrySave(player, tag)
	task.spawn(function()
		while true do
			task.wait(30)
			if player.Parent == nil then return end -- left; the PlayerRemoving save path owns it now
			local data = PlayerDataManager.Get(player)
			if not data or data.__noSave then return end
			if PlayerDataManager.Save(player) then
				warn(("[TradeAudit] %s: retry save SUCCEEDED for user %d"):format(tag, player.UserId))
				return
			end
			warn(("[TradeAudit] %s: retry save still failing for user %d"):format(tag, player.UserId))
		end
	end)
end

local function executeTrade(session)
	local a, b = session.players[1], session.players[2]
	local dataA, dataB = PlayerDataManager.Get(a), PlayerDataManager.Get(b)
	if not dataA or not dataB then return false, "Player data missing." end
	local offerA, offerB = session.offers[a.UserId], session.offers[b.UserId]

	-- Final ownership check, right before the swap. If anything changed
	-- since the offers were built (sold a brainrot, spent cash), fail safely.
	for _, side in ipairs({ { data = dataA, offer = offerA }, { data = dataB, offer = offerB } }) do
		if side.data.Cash < side.offer.Cash then
			return false, "A player no longer has the offered cash."
		end
		for name, count in pairs(side.offer.Items) do
			if not BrainrotMover.InfoByName[name] then return false, "Unknown brainrot in offer." end
			if BrainrotMover.CountOwned(side.data, name) < count then
				return false, "A player no longer owns the offered brainrots."
			end
		end
	end

	-- UNIQUE cap. Must be checked HERE, not in BrainrotMover.Give: Take() mutates the
	-- giver first, so a refusal inside Give would destroy the item mid-transfer. Failing
	-- in this block is safe because nothing has moved yet.
	-- Each side's incoming count is netted against what it is simultaneously giving
	-- away, so trading a unique item FOR the same unique item still works.
	for _, dir in ipairs({
		{ recvData = dataB, incoming = offerA, outgoing = offerB },
		{ recvData = dataA, incoming = offerB, outgoing = offerA },
	}) do
		for name, count in pairs(dir.incoming.Items) do
			if not BrainrotMover.WithinUniqueCap(name,
				BrainrotMover.CountOwned(dir.recvData, name),
				dir.outgoing.Items[name] or 0, count) then
				return false, ("%s is one-per-player \u{2014} a player would end up with more than one."):format(name)
			end
		end
	end

	-- BAG SPACE, netted exactly like the unique cap above (2026-08-20). Same
	-- pre-flight rule and the same reason: Take() has mutated the giver by the
	-- time Give runs, so refusing later would destroy items mid-swap.
	--
	-- `incoming > outgoing` is what makes an even swap always legal. A player at
	-- exactly 150/150 can still trade one brainrot for another all day -- only a
	-- trade that would leave them holding MORE than they started with has to fit.
	for _, dir in ipairs({
		{ recvData = dataB, incoming = offerA, outgoing = offerB },
		{ recvData = dataA, incoming = offerB, outgoing = offerA },
	}) do
		local incoming, outgoing = 0, 0
		for _, count in pairs(dir.incoming.Items) do incoming += count end
		for _, count in pairs(dir.outgoing.Items) do outgoing += count end
		if incoming > outgoing then
			local after = BagConfig.BrainrotCount(dir.recvData) - outgoing + incoming
			if after > BagConfig.BrainrotCap(dir.recvData.Upgrades, dir.recvData.BagX2) then
				return false, "A player has no room left in their bag for this trade."
			end
		end
	end

	local movedA = transferItems(a, dataA, b, dataB, offerA)
	local movedB = transferItems(b, dataB, a, dataA, offerB)

	-- the swap moved entries that may back Tools in either player's Backpack;
	-- rebuild both so no Tool is left pointing at a brainrot that changed owners
	InventoryHandler.SyncBackpack(a)
	InventoryHandler.SyncBackpack(b)

	dataA.Cash = dataA.Cash - offerA.Cash + offerB.Cash
	dataB.Cash = dataB.Cash - offerB.Cash + offerA.Cash

	PlayerDataManager.PushUpdate(a)
	PlayerDataManager.PushUpdate(b)
	-- Save() returning false after a committed swap = one side of the trade is
	-- now only real in memory. Log a durable audit line with everything needed
	-- to hand-restore it, then keep retrying. Never roll back in-memory state.
	local savedA = PlayerDataManager.Save(a)
	local savedB = PlayerDataManager.Save(b)
	if not (savedA and savedB) then
		warn(("[TradeAudit] SAVE FAILED after trade %d <-> %d | savedA=%s savedB=%s | %d gave: %s + $%d cash | %d gave: %s + $%d cash"):format(
			a.UserId, b.UserId, tostring(savedA), tostring(savedB),
			a.UserId, describeRecords(movedA), offerA.Cash,
			b.UserId, describeRecords(movedB), offerB.Cash))
		if not savedA then retrySave(a, "trade " .. a.UserId .. "<->" .. b.UserId) end
		if not savedB then retrySave(b, "trade " .. a.UserId .. "<->" .. b.UserId) end
	end
	return true
end

local function tryStartCountdown(session)
	local a, b = session.players[1], session.players[2]
	if not (session.confirmed[a.UserId] and session.confirmed[b.UserId]) then return end

	session.countdownToken += 1
	local token = session.countdownToken
	pushState(session, "Countdown", { Seconds = COUNTDOWN_SECONDS })

	task.delay(COUNTDOWN_SECONDS, function()
		-- token changed = someone cancelled/unconfirmed/changed the offer
		if session.closed or token ~= session.countdownToken then return end
		if not (session.confirmed[a.UserId] and session.confirmed[b.UserId]) then return end

		-- Close the session BEFORE executeTrade runs. executeTrade yields inside
		-- PlayerDataManager.Save (DataStore write) AFTER the swap has committed;
		-- if the session were still live during that yield, a Confirm fired in
		-- the gap could schedule a second countdown and run the swap twice.
		-- Closing first makes any concurrent TradeAction hit the closed guard.
		session.closed = true
		session.countdownToken += 1
		sessions[a.UserId] = nil
		sessions[b.UserId] = nil

		local ok, err = executeTrade(session)
		local finalPhase = ok and "Completed" or "Closed"
		for _, p in ipairs(session.players) do
			if p.Parent then
				remotes.TradeState:FireClient(p, { Phase = finalPhase, Message = not ok and (err or "Trade failed.") or nil })
			end
		end
	end)
end

-- === remote handlers ===

function TradeHandler.Init()
	remotes.TradeRequest.OnServerEvent:Connect(function(player, targetUserId)
		if typeof(targetUserId) ~= "number" then return end
		-- reject NaN / infinity / fractional ids before they reach GetPlayerByUserId
		if targetUserId ~= targetUserId or targetUserId == math.huge or targetUserId == -math.huge then return end
		targetUserId = math.floor(targetUserId)
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target or target == player then return end
		if sessions[player.UserId] or sessions[target.UserId] then return end
		if not (isInTradeZone(player.Character) and isInTradeZone(target.Character)) then
			remotes.TradeState:FireClient(player, { Phase = "Error", Message = "Both players must be in the Trading Center." })
			return
		end
		-- profiles whose DataStore read failed can never persist a trade - block
		-- at the invite, not after both players have built an offer
		local pdata = PlayerDataManager.Get(player)
		if not pdata or pdata.__noSave then
			remotes.TradeState:FireClient(player, { Phase = "Error", Message = "Your profile did not load - rejoin before trading." })
			return
		end
		local tdata = PlayerDataManager.Get(target)
		if not tdata or tdata.__noSave then
			remotes.TradeState:FireClient(player, { Phase = "Error", Message = target.DisplayName .. "'s profile did not load - they can't trade right now." })
			return
		end

		-- If they already invited US, treat this as an instant accept.
		local mutual = pendingRequests[player.UserId]
		if mutual and mutual.fromUserId == target.UserId and os.clock() - mutual.at <= REQUEST_TIMEOUT then
			pendingRequests[player.UserId] = nil
			createSession(target, player)
			return
		end

		-- Tell any earlier requester for this target that they were superseded,
		-- so they aren't left waiting on a request that can never be accepted.
		local existing = pendingRequests[target.UserId]
		if existing and existing.fromUserId ~= player.UserId then
			local prev = Players:GetPlayerByUserId(existing.fromUserId)
			if prev then
				remotes.TradeState:FireClient(prev, { Phase = "Error", Message = target.DisplayName .. " got another trade request first." })
			end
		end

		pendingRequests[target.UserId] = { fromUserId = player.UserId, at = os.clock() }
		remotes.TradeState:FireClient(target, { Phase = "Incoming", FromUserId = player.UserId, FromName = player.DisplayName, Timeout = REQUEST_TIMEOUT })
		remotes.TradeState:FireClient(player, { Phase = "Sent", ToName = target.DisplayName })
	end)

	remotes.TradeRespond.OnServerEvent:Connect(function(player, accept, fromUserId)
		local request = pendingRequests[player.UserId]
		if not request then return end
		-- The client echoes back who the popup showed. If a newer request
		-- overwrote this slot after the popup rendered, the ids won't match and
		-- we ignore the stale accept rather than pairing the wrong two players.
		if typeof(fromUserId) == "number" and math.floor(fromUserId) ~= request.fromUserId then return end
		pendingRequests[player.UserId] = nil

		local from = Players:GetPlayerByUserId(request.fromUserId)
		if accept ~= true then
			if from then
				remotes.TradeState:FireClient(from, { Phase = "Error", Message = player.DisplayName .. " declined the trade." })
			end
			return
		end
		if os.clock() - request.at > REQUEST_TIMEOUT then return end
		if not from or not from.Parent then return end
		if sessions[player.UserId] or sessions[from.UserId] then return end
		-- profiles whose DataStore read failed can never persist a trade
		local pdata = PlayerDataManager.Get(player)
		if not pdata or pdata.__noSave then
			remotes.TradeState:FireClient(player, { Phase = "Error", Message = "Your profile did not load - rejoin before trading." })
			return
		end
		local fdata = PlayerDataManager.Get(from)
		if not fdata or fdata.__noSave then
			remotes.TradeState:FireClient(player, { Phase = "Error", Message = from.DisplayName .. "'s profile did not load - they can't trade right now." })
			return
		end
		createSession(from, player)
	end)

	remotes.TradeAction.OnServerEvent:Connect(function(player, action)
		if typeof(action) ~= "table" or typeof(action.Type) ~= "string" then return end
		local session = sessions[player.UserId]
		if not session or session.closed then return end
		local data = PlayerDataManager.Get(player)
		if not data then return end
		local offer = session.offers[player.UserId]

		if action.Type == "AddItem" then
			local name = action.Name
			if typeof(name) ~= "string" or not BrainrotMover.InfoByName[name] then return end
			local offered = offer.Items[name] or 0
			if BrainrotMover.CountOwned(data, name) <= offered then return end -- can't offer more than you own
			offer.Items[name] = offered + 1
			resetConfirmations(session)
			pushState(session, "Active")

		elseif action.Type == "RemoveItem" then
			local name = action.Name
			if typeof(name) ~= "string" then return end
			local offered = offer.Items[name] or 0
			if offered <= 0 then return end
			offer.Items[name] = offered > 1 and offered - 1 or nil
			resetConfirmations(session)
			pushState(session, "Active")

		elseif action.Type == "SetCash" then
			local amount = tonumber(action.Amount)
			if not amount then return end
			amount = math.floor(amount)
			if amount ~= amount or amount == math.huge then return end -- reject NaN / inf
			amount = math.clamp(amount, 0, data.Cash)
			offer.Cash = amount
			resetConfirmations(session)
			pushState(session, "Active")

		elseif action.Type == "Confirm" then
			session.confirmed[player.UserId] = true
			pushState(session, "Active")
			tryStartCountdown(session)

		elseif action.Type == "Unconfirm" then
			session.confirmed[player.UserId] = nil
			session.countdownToken += 1
			pushState(session, "Active")

		elseif action.Type == "Cancel" then
			closeSession(session, player.DisplayName .. " cancelled the trade.")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		pendingRequests[player.UserId] = nil
		for targetId, request in pairs(pendingRequests) do
			if request.fromUserId == player.UserId then
				pendingRequests[targetId] = nil
			end
		end
		local session = sessions[player.UserId]
		if session then
			closeSession(session, player.DisplayName .. " left the game.")
		end
	end)

	print("TradeHandler online")
end

return TradeHandler
