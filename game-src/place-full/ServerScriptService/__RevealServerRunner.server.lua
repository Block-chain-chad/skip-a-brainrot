-- __RevealServerRunner -- STUDIO-ONLY. The MCP exec thread cannot require() modules,
-- so this real Script performs a small, named set of test operations on request:
-- ServerStorage attribute ServerRequest = JSON { op = ..., ... }; result in ServerLog.
--   baseline            -> brainrot count, maxUid, cash, BrainrotsCaught for player 1
--   forceSize   {size}  -> ServerStorage.ForceNextSize = size
--   forceCatch  {name}  -> ServerStorage.ForceNextCatch = name
--   grantsSince {maxUid}-> entries with Uid > maxUid (what the test granted)
--   revertUids  {uids}  -> remove those entries by exact Uid, restore BrainrotsCaught by
--                          the count removed, Save + PushUpdate
-- Returns immediately outside Studio. Never touches any other player's data.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local PDM = require(game.ServerScriptService.Modules.PlayerDataManager)

local function player1()
	return Players:GetPlayers()[1]
end

local function maxUidOf(data)
	local m = 0
	for _, e in ipairs(data.Brainrots or {}) do
		local n = tonumber(e.Uid) or 0
		if n > m then m = n end
	end
	return m
end

local ops = {}

function ops.baseline()
	local p = player1()
	if not p then return "no player" end
	local data = PDM.Get(p)
	if not data then return "no data" end
	return HttpService:JSONEncode({ brainrots = #data.Brainrots, maxUid = maxUidOf(data), cash = data.Cash, caught = data.BrainrotsCaught })
end

function ops.forceSize(req)
	ServerStorage:SetAttribute("ForceNextSize", req.size)
	return "ForceNextSize=" .. tostring(req.size)
end

function ops.forceCatch(req)
	ServerStorage:SetAttribute("ForceNextCatch", req.name)
	return "ForceNextCatch=" .. tostring(req.name)
end

function ops.grantsSince(req)
	local p = player1()
	local data = p and PDM.Get(p)
	if not data then return "no data" end
	local out = {}
	for _, e in ipairs(data.Brainrots) do
		if (tonumber(e.Uid) or 0) > (tonumber(req.maxUid) or 0) then
			table.insert(out, { Uid = e.Uid, Name = e.Name, Mutation = e.Mutation, Size = e.Size, PadIndex = e.PadIndex })
		end
	end
	return HttpService:JSONEncode(out)
end

function ops.revertUids(req)
	local p = player1()
	local data = p and PDM.Get(p)
	if not data then return "no data" end
	local want = {}
	for _, u in ipairs(req.uids or {}) do want[tostring(u)] = true end
	local removed = 0
	for i = #data.Brainrots, 1, -1 do
		local e = data.Brainrots[i]
		if want[tostring(e.Uid)] then
			if e.PadIndex then
				return "REFUSED: uid " .. tostring(e.Uid) .. " is placed on a pad; unplace first"
			end
			table.remove(data.Brainrots, i)
			removed += 1
		end
	end
	if removed > 0 then
		data.BrainrotsCaught = math.max((data.BrainrotsCaught or 0) - removed, 0)
		pcall(PDM.Save, p)
		pcall(PDM.PushUpdate, p)
	end
	return "removed " .. removed .. "; now " .. #data.Brainrots .. " brainrots"
end

local busy = false
ServerStorage:GetAttributeChangedSignal("ServerRequest"):Connect(function()
	local req = ServerStorage:GetAttribute("ServerRequest")
	if type(req) ~= "string" or req == "" or busy then return end
	ServerStorage:SetAttribute("ServerRequest", "")
	busy = true
	local ok, res = pcall(function()
		local spec = HttpService:JSONDecode(req)
		local fn = ops[spec.op]
		assert(fn, "unknown op " .. tostring(spec.op))
		return fn(spec)
	end)
	ServerStorage:SetAttribute("ServerLog", ok and tostring(res) or ("ERROR " .. tostring(res)))
	busy = false
end)
print("[__RevealServerRunner] armed")
