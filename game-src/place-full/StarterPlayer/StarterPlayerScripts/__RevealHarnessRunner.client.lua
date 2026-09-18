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
print("[__RevealHarnessRunner] armed")
