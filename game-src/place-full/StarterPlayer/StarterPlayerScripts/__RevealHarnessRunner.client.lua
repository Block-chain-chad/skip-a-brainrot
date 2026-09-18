-- __RevealHarnessRunner -- STUDIO-ONLY. Runs CatchCinematic.Harness on request.
-- The MCP exec thread cannot require() modules, so it sets workspace attribute
-- HarnessRequest to a JSON spec { fn = "matrix"|"run"|..., args = {...} } and this
-- real LocalScript (full capabilities) performs the call, writing the result to
-- HarnessLog / HarnessStatus. Delete before publishing? Harmless if left: it returns
-- immediately outside Studio.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function summarise(result)
	if type(result) ~= "table" then return tostring(result) end
	local lines = {}
	if result.cut and result.mode then result = { result } end
	for _, r in ipairs(result) do
		if type(r) == "table" and r.cut then
			table.insert(lines, string.format("%s/%s %s %.2fs %s", r.cut, r.mode, r.ok and "OK" or "FAIL", r.seconds or 0, table.concat(r.failures or {}, " | ")))
		else
			table.insert(lines, tostring(r))
		end
	end
	if #lines == 0 then return "(empty)" end
	return table.concat(lines, "\n")
end

local busy = false
workspace:GetAttributeChangedSignal("HarnessRequest"):Connect(function()
	local req = workspace:GetAttribute("HarnessRequest")
	if type(req) ~= "string" or req == "" or busy then return end
	workspace:SetAttribute("HarnessRequest", "")
	busy = true
	workspace:SetAttribute("HarnessStatus", "running")
	workspace:SetAttribute("HarnessLog", "")
	task.spawn(function()
		local ok, err = pcall(function()
			local spec = HttpService:JSONDecode(req)
			local H = require(ReplicatedStorage.Modules.CatchCinematic.Harness)
			local lines = {}
			for _, call in ipairs(spec.calls or { spec }) do
				local fn = H[call.fn]
				assert(type(fn) == "function", "no Harness." .. tostring(call.fn))
				local result = fn(table.unpack(call.args or {}))
				table.insert(lines, summarise(result))
				workspace:SetAttribute("HarnessLog", table.concat(lines, "\n"))
			end
		end)
		if not ok then
			workspace:SetAttribute("HarnessLog", tostring(workspace:GetAttribute("HarnessLog")) .. "\nERROR " .. tostring(err))
		end
		workspace:SetAttribute("HarnessStatus", "done")
		busy = false
	end)
end)
-- 10 Hz state feed for timed screen captures: HarnessState = Takeover.debugState() JSON
-- (or "" when idle), plus the camera position, so a capture can be attributed to a beat.
task.spawn(function()
	local okT, Takeover = pcall(function() return require(ReplicatedStorage.Modules.CatchCinematic.Takeover) end)
	if not okT then return end
	while true do
		local st = Takeover.debugState()
		if st then
			local cam = workspace.CurrentCamera
			st.camPos = cam and tostring(cam.CFrame.Position) or nil
			workspace:SetAttribute("HarnessState", HttpService:JSONEncode(st))
		elseif workspace:GetAttribute("HarnessState") ~= "" then
			workspace:SetAttribute("HarnessState", "")
		end
		task.wait(0.1)
	end
end)
-- AUTO-FISH (Studio only): while workspace attribute HarnessAutoFish is true, answer every
-- ice-fishing Minigame step with a reel at the middle of the green band, so a landed fish
-- can be produced without hand-timed clicks. The server trusts the reported fraction.
do
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local state = remotes:WaitForChild("IceFishingState", 10)
	local reel = remotes:WaitForChild("IceFishingReel", 10)
	if state and reel then
		-- FISH TRACE: every IceFishingState payload, one line each, appended to HarnessFishLog
		-- (cleared by setting it to ""), so a run can be read back without a screen.
		state.OnClientEvent:Connect(function(p)
			if type(p) ~= "table" then return end
			local keys = {}
			for k, v in pairs(p) do
				local s
				if type(v) == "table" then
					s = "{" .. tostring(v.Name) .. "/" .. tostring(v.Rarity) .. "/" .. tostring(v.Mutation) .. "/" .. tostring(v.Size) .. "}"
				else
					s = tostring(v)
				end
				table.insert(keys, tostring(k) .. "=" .. s)
			end
			table.sort(keys)
			local prev = workspace:GetAttribute("HarnessFishLog")
			workspace:SetAttribute("HarnessFishLog", (type(prev) == "string" and prev or "")
				.. string.format("%.2f ", os.clock() % 1000) .. table.concat(keys, " ") .. "\n")
		end)
		-- REMOTE FIRE: HarnessRemote = JSON { name = "IceFishingCast", args = { 0.8 } } fires
		-- Remotes[name]:FireServer(args...) from this real LocalScript (the exec thread cannot).
		workspace:GetAttributeChangedSignal("HarnessRemote"):Connect(function()
			local req = workspace:GetAttribute("HarnessRemote")
			if type(req) ~= "string" or req == "" then return end
			workspace:SetAttribute("HarnessRemote", "")
			local ok, err = pcall(function()
				local spec = HttpService:JSONDecode(req)
				local r = remotes:FindFirstChild(spec.name)
				assert(r and r:IsA("RemoteEvent"), "no RemoteEvent " .. tostring(spec.name))
				r:FireServer(table.unpack(spec.args or {}))
			end)
			workspace:SetAttribute("HarnessRemoteLog", (ok and "fired " or "ERROR ") .. tostring(ok and req or err))
		end)
		state.OnClientEvent:Connect(function(p)
			if type(p) ~= "table" or not p.Minigame then return end
			if workspace:GetAttribute("HarnessAutoFish") ~= true then return end
			local mid = ((p.GreenMin or 0.4) + (p.GreenMax or 0.6)) / 2
			task.delay(0.35, function()
				if workspace:GetAttribute("HarnessAutoFish") == true then
					reel:FireServer(mid)
				end
			end)
		end)
	end
end
print("[__RevealHarnessRunner] armed")
