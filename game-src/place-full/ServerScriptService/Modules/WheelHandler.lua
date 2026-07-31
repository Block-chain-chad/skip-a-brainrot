-- WheelHandler: the free daily spin.
--
-- The server owns the roll and the clock. The client asks to spin, the server decides
-- whether it may, picks the slot, pays out, and replies with the winning index -- the
-- client's only job is to animate to that index. Nothing about the outcome is ever taken
-- from the client, and the cooldown is re-checked here rather than trusted from the UI.
--
-- Cooldown is a ROLLING 24 hours from the last spin (os.time based), not calendar
-- midnight. That is the literal reading of "resets every 24 hours", and it avoids the
-- timezone question entirely -- but it does mean the free spin drifts later each day if
-- a player always claims it immediately.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local WheelConfig = require(ReplicatedStorage.Modules.WheelConfig)
local WheelBoard = require(ServerScriptService.Modules.WheelBoard)

local M = {}
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Per-player RNG seeded off the server's own clock. math.random's global state is shared
-- with every other system on this server; a dedicated stream keeps the wheel's odds
-- independent of how many throws or mutations happened to roll first.
local rng = Random.new()

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local spinRemote  = getRemote("WheelSpin")
local stateRemote = getRemote("WheelState")
-- Broadcast, not FireClient. The wheel is shared scenery standing in the world, so
-- everyone nearby should watch it turn -- not just whoever pressed E.
local spunRemote  = getRemote("WheelSpun")

-- seconds until this player may spin again; 0 means ready now
local function cooldownLeft(data)
	local last = tonumber(data.LastSpinAt) or 0
	if last <= 0 then return 0 end
	return math.max(0, (last + WheelConfig.COOLDOWN) - os.time())
end

local function stateFor(player, data, extra)
	data = data or PlayerDataManager.Get(player)
	if not data then return nil end
	local payload = {
		Cooldown = cooldownLeft(data),
		LuckLeft = PlayerDataManager.BoostRemaining(data, "Luck"),
		PowerLeft = PlayerDataManager.BoostRemaining(data, "Power"),
	}
	if extra then
		for k, v in pairs(extra) do payload[k] = v end
	end
	return payload
end

function M.SendState(player, extra)
	local payload = stateFor(player, nil, extra)
	if payload then stateRemote:FireClient(player, payload) end
end

-- Headline text on the wheel's sign. Shows the shortest cooldown among players currently
-- online, so someone walking past sees "ready" whenever it is ready for anyone. Per-player
-- truth still comes from the state remote; this is only the sign.
local function refreshSign()
	local best
	for _, plr in ipairs(Players:GetPlayers()) do
		local d = PlayerDataManager.Get(plr)
		if d then
			local left = cooldownLeft(d)
			if not best or left < best then best = left end
		end
	end
	if not best then
		WheelBoard.SetState("walk up and press E")
	elseif best <= 0 then
		WheelBoard.SetState("FREE SPIN READY")
	else
		WheelBoard.SetState(("next free spin in %dh %02dm")
			:format(math.floor(best / 3600), math.floor((best % 3600) / 60)))
	end
end

-- Applies one slot's reward. Returns a short description for the client toast.
local function award(player, data, slot)
	if slot.Kind == "Cash" then
		-- through GrantCash so it lands in LifetimeEarned and counts on the leaderboard,
		-- the same way daily rewards and quest payouts do
		PlayerDataManager.GrantCash(data, slot.Amount)
		return slot.Label
	end

	if slot.Kind == "Boost" then
		data.Boosts = data.Boosts or {}
		local now = os.time()
		local current = tonumber(data.Boosts[slot.Stat]) or 0
		-- EXTEND rather than replace: winning a boost while one is already running should
		-- never shorten it, which is what a flat "now + duration" would do.
		local base = math.max(current, now)
		data.Boosts[slot.Stat] = base + WheelConfig.BOOST_TIME
		return slot.Label
	end

	return slot.Label
end

-- The one place a spin can happen. Both entry points -- the in-world prompt and the
-- remote -- funnel through here, so the cooldown and payout cannot diverge between them.
function M.TrySpin(player)
	local data = PlayerDataManager.Get(player)
	if not data then return false end

	-- read-only sessions happen when the DataStore load failed; letting them spin
	-- would hand out a prize that is discarded at logout
	if data.__noSave then
		M.SendState(player, { Error = "Your save could not be loaded. Try rejoining." })
		return false
	end

	if cooldownLeft(data) > 0 then
		-- the UI and the prompt both hide themselves on cooldown, so reaching here means
		-- a stale client or someone firing the remote directly; just resend the truth
		M.SendState(player)
		return false
	end

	local index, slot = WheelConfig.Roll(rng)
	data.LastSpinAt = os.time()
	local text = award(player, data, slot)

	PlayerDataManager.PushUpdate(player)
	M.SendState(player, {
		Result = index,        -- the slot the client must land the wheel on
		ResultId = slot.Id,
		ResultText = text,
	})
	spunRemote:FireAllClients(index, player.Name, text)
	refreshSign()
	return true
end

function M.Init()
	spinRemote.OnServerEvent:Connect(function(player)
		M.TrySpin(player)
	end)

	-- clients ask for state on open, and once on join
	stateRemote.OnServerEvent:Connect(function(player)
		M.SendState(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			if player.Parent then
				M.SendState(player)
				-- refresh here too: the sign otherwise reads "walk up and press E" until the
				-- next 20s tick, because at join time no profile had loaded yet
				pcall(refreshSign)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function() pcall(refreshSign) end)
	end)

	-- the physical wheel: walking up and pressing E runs the same path as the remote
	local model = WheelBoard.Build()
	local board = WheelBoard.Get()
	if board then
		board.Prompt.Triggered:Connect(function(player)
			M.TrySpin(player)
		end)
	end

	task.spawn(function()
		while true do
			pcall(refreshSign)
			task.wait(20)
		end
	end)

	print(("WheelHandler online (%d slots, %dh cooldown, wheel %s)")
		:format(#WheelConfig.SLOTS, WheelConfig.COOLDOWN / 3600,
			model and "in world" or "MISSING"))
end

return M
