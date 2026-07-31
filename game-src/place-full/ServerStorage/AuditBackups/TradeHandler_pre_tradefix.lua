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

-- Send both players their view of the trade ("You" vs "Them").
local function pushState(session, phase, extra)
	for _, p in ipairs(session.players) do
		local other = otherPlayer(session, p)
		local state = {
			Phase = phase,
			OtherName = other.DisplayName,
			You = {
				Items = session.offers[p.UserId].Items,
				Cash = session.offers[p.UserId].Cash,
				Confirmed = session.confirmed[p.UserId] == true,
			},
			Them = {
				Items = session.offers[other.UserId].Items,
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
	for name, count in pairs(offer.Items) do
		for _ = 1, count do
			-- hand over the RECORD that was actually taken, so the mutation travels
			-- with the item instead of being silently dropped
			local record = BrainrotMover.Take(giver, giverData, name)
			if record then
				BrainrotMover.Give(receiver, receiverData, record)
			end
		end
	end
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

	transferItems(a, dataA, b, dataB, offerA)
	transferItems(b, dataB, a, dataA, offerB)

	dataA.Cash = dataA.Cash - offerA.Cash + offerB.Cash
	dataB.Cash = dataB.Cash - offerB.Cash + offerA.Cash

	PlayerDataManager.PushUpdate(a)
	PlayerDataManager.PushUpdate(b)
	PlayerDataManager.Save(a)
	PlayerDataManager.Save(b)
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
