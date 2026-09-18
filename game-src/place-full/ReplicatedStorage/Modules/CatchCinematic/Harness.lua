--!strict
-- CatchCinematic.Harness -- STUDIO-ONLY structural harness for the reveal cuts.
-- Plays a fabricated payload (no grant, no Bridge unless asked) through a conductor
-- and asserts that every exit path restores the client: stage gone, PlayerGui
-- Enabled flags identical, camera restored, Lighting untouched, RevealActive nil.
-- Returns a report table; never throws (a harness that throws hides the failure).
-- Driven by StarterPlayerScripts.__RevealHarnessRunner (the MCP exec thread cannot
-- require modules, so a real LocalScript runs it on the HarnessRequest attribute).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Harness = {}

export type Report = { ok: boolean, cut: string, mode: string, seconds: number, failures: { string } }

local HUB_SURFACE_Y = 1.5

local function snapshot(): { [string]: any }
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	local guis: { [string]: boolean } = {}
	if pg then
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") then
				guis[g.Name] = g.Enabled
			end
		end
	end
	local cam = Workspace.CurrentCamera
	local lightNames = {}
	for _, c in ipairs(Lighting:GetChildren()) do
		table.insert(lightNames, c.Name)
	end
	table.sort(lightNames)
	return {
		guis = guis,
		cameraType = cam and cam.CameraType or nil,
		cameraSubject = cam and cam.CameraSubject or nil,
		fov = cam and cam.FieldOfView or nil,
		lightChildren = table.concat(lightNames, ","),
		ambient = Lighting.Ambient,
		brightness = Lighting.Brightness,
		waveSize = Workspace.Terrain.WaterWaveSize,
		waveSpeed = Workspace.Terrain.WaterWaveSpeed,
	}
end

local function diff(before: { [string]: any }, after: { [string]: any }, failures: { string })
	for name, enabled in pairs(before.guis) do
		if after.guis[name] ~= nil and after.guis[name] ~= enabled then
			table.insert(failures, "ScreenGui " .. name .. " Enabled " .. tostring(enabled) .. " -> " .. tostring(after.guis[name]))
		end
	end
	for _, k in ipairs({ "cameraType", "cameraSubject", "fov", "lightChildren", "ambient", "brightness", "waveSize", "waveSpeed" }) do
		if before[k] ~= after[k] then
			-- A death-mode run respawns the character, so the subject is legitimately a NEW
			-- Humanoid afterwards: the invariant is "the camera follows the live character",
			-- not "the same Instance".
			local char = Players.LocalPlayer.Character
			local respawned = k == "cameraSubject" and typeof(after[k]) == "Instance" and after[k]:IsA("Humanoid")
				and char ~= nil and after[k].Parent == char
				and typeof(before[k]) == "Instance" and before[k]:IsA("Humanoid") and before[k].Parent ~= char
			if not respawned then
				table.insert(failures, k .. " changed: " .. tostring(before[k]) .. " -> " .. tostring(after[k]))
			end
		end
	end
end

-- opts.endPos / opts.surfaceY override the hub defaults; opts.brainrot picks the model.
-- opts.spectator plays the world-only variant. opts.bridge = true arms the Bridge and
-- never adopts a result, which exercises the cancel path.
-- opts.skipAfter (real seconds) holds the skip input from that moment.
-- opts.killAfter (real seconds) sets Humanoid.Health = 0 (respawn follows -- Studio only).
function Harness.run(conductorName: string, cutName: string, mode: string, opts: { [string]: any }?): Report
	local o = opts or {}
	local report: Report = { ok = false, cut = cutName, mode = mode, seconds = 0, failures = {} }
	if not RunService:IsStudio() then
		table.insert(report.failures, "not Studio")
		return report
	end
	local player = Players.LocalPlayer
	local folder = ReplicatedStorage.Modules.CatchCinematic
	local okC, conductor = pcall(require, folder:FindFirstChild(conductorName))
	if not okC then
		table.insert(report.failures, "conductor require failed: " .. tostring(conductor))
		return report
	end
	local Bridge = require(folder.Bridge)

	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local endPos: Vector3 = o.endPos
		or (hrp and (hrp :: BasePart).Position + (hrp :: BasePart).CFrame.LookVector * 45)
		or Vector3.new(0, HUB_SURFACE_Y, 60)
	local surfaceY: number = o.surfaceY or HUB_SURFACE_Y
	endPos = Vector3.new(endPos.X, surfaceY, endPos.Z)

	local size: string? = (cutName == "Massive" or cutName == "MassiveGod") and "Massive"
		or (cutName == "Huge") and "Huge" or nil
	local rarity: string = (cutName == "God" or cutName == "MassiveGod") and "God"
		or (cutName == "Secret") and "Secret" or (cutName == "Mythic") and "Mythic" or "Epic"
	local payload: { [string]: any } = {
		UserId = o.spectator and -1 or player.UserId,
		BrainrotName = o.brainrot or "Kraken Congelato",
		Rarity = rarity,
		RarityColor = Color3.fromRGB(255, 226, 120),
		Mutation = o.mutation,
		Size = size,
		Cut = cutName,
		RockId = "stone", RockColor = Color3.fromRGB(105, 100, 96),
		Seed = 7,
		EndPos = endPos, SurfaceY = surfaceY,
		TotalTime = 0, NContacts = 2, SegTime = 0.5,
		__debugNoBridge = not o.bridge,
	}

	local bridgeGen: number? = nil
	if o.bridge then
		bridgeGen = Bridge.arm(payload, 30)
	end

	local before = snapshot()
	local t0 = os.clock()
	local committed = false
	local returned: boolean? = nil
	task.spawn(function()
		local okP, res = pcall(function()
			-- Sequencer.play(payload, opts) vs Takeover.play(cut, payload, opts)
			if conductorName == "Sequencer" then
				return conductor.play(payload, {
					spectator = o.spectator == true,
					variant = (cutName == "Huge") and "trimmed" or "full",
					bridgeGen = bridgeGen,
					onCommit = function() committed = true end,
				})
			end
			local Registry = require(folder.Cuts.Registry)
			local cut = Registry.get(cutName)
			assert(cut, "no cut " .. cutName)
			return conductor.play(cut, payload, {
				spectator = o.spectator == true,
				bridgeGen = bridgeGen,
				onCommit = function() committed = true end,
			})
		end)
		if not okP then
			table.insert(report.failures, "play errored: " .. tostring(res))
			returned = false
		else
			returned = res
		end
	end)

	if o.skipAfter then
		task.delay(o.skipAfter, function()
			if conductor.debugHold then conductor.debugHold(true) end
		end)
	end
	if o.killAfter then
		task.delay(o.killAfter, function()
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.Health = 0 end
		end)
	end

	local deadline = os.clock() + (o.timeout or 90)
	while returned == nil and os.clock() < deadline do
		task.wait(0.1)
	end
	if returned == nil then
		table.insert(report.failures, "play did not return within timeout")
	end
	if o.skipAfter and conductor.debugHold then conductor.debugHold(false) end
	report.seconds = os.clock() - t0

	task.wait(o.settle or 4) -- SoundKit's Debris anchors live up to 3.5s
	local after = snapshot()
	diff(before, after, report.failures)
	if Workspace:FindFirstChild("CatchCinematicStage") then
		table.insert(report.failures, "stage folder leaked")
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg and (pg:FindFirstChild("CatchCinematicUI") or pg:FindFirstChild("CatchCinematicFade")) then
		table.insert(report.failures, "cinematic gui leaked")
	end
	if player:GetAttribute("RevealActive") ~= nil then
		table.insert(report.failures, "RevealActive not cleared")
	end
	if conductor.isActive and conductor.isActive() then
		table.insert(report.failures, "conductor still active")
	end
	if mode == "normal" and returned ~= true and not o.spectator then
		table.insert(report.failures, "expected play() == true, got " .. tostring(returned))
	end
	if o.bridge then Bridge.reset() end
	report.ok = #report.failures == 0
	return report
end

-- Runs the standard matrix for one cut and prints one line per mode.
function Harness.matrix(conductorName: string, cutName: string, opts: { [string]: any }?): { Report }
	local base = opts or {}
	local function with(extra: { [string]: any }): { [string]: any }
		local t = {}
		for k, v in pairs(base) do t[k] = v end
		for k, v in pairs(extra) do t[k] = v end
		return t
	end
	local reports = {
		Harness.run(conductorName, cutName, "normal", with({})),
		Harness.run(conductorName, cutName, "spectator", with({ spectator = true })),
		Harness.run(conductorName, cutName, "skip", with({ skipAfter = 1.6 })),
		Harness.run(conductorName, cutName, "cancel", with({ bridge = true })),
	}
	for _, r in ipairs(reports) do
		print(string.format("[Harness] %s/%s %s %.1fs %s", r.cut, r.mode, r.ok and "OK" or "FAIL", r.seconds, table.concat(r.failures, " | ")))
	end
	return reports
end

-- Asserts a cut's beat table is contiguous, starts at 0, and ends within [lo, hi].
function Harness.checkBeats(cutName: string, lo: number, hi: number): { string }
	local Registry = require(ReplicatedStorage.Modules.CatchCinematic.Cuts.Registry)
	local cut = Registry.get(cutName)
	local f: { string } = {}
	if not cut then
		table.insert(f, "no cut")
		return f
	end
	local beats = cut.beats
	if beats[1].t0 ~= 0 then table.insert(f, "does not start at 0") end
	for i = 1, #beats - 1 do
		if math.abs(beats[i].t1 - beats[i + 1].t0) > 1e-6 then
			table.insert(f, "gap between " .. beats[i].name .. " and " .. beats[i + 1].name)
		end
	end
	local total = beats[#beats].t1
	if total < lo or total > hi then table.insert(f, "total " .. total .. " outside [" .. lo .. "," .. hi .. "]") end
	for _, b in ipairs(beats) do
		if not cut.handlers[b.name] then table.insert(f, "no handler for beat " .. b.name) end
	end
	if not cut.handlers[cut.revealBeat] then table.insert(f, "revealBeat missing") end
	if cut.skippable and not (cut.skipTo and cut.handlers[cut.skipTo]) then table.insert(f, "skipTo missing") end
	if #f == 0 then table.insert(f, "beats OK (" .. cutName .. " " .. total .. "s)") end
	return f
end

-- Spec S4, locked. Every cell must match; mutation must never change the answer.
function Harness.routingMatrix(): { string }
	local Config = require(ReplicatedStorage.Modules.CatchCinematic.Config)
	local f: { string } = {}
	local tiers = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "God" }
	local sizes = { nil, "Huge", "Massive" }
	local expect = function(r: string, s: string?): string?
		if s == "Massive" and r == "God" then return "MassiveGod" end
		if s == "Massive" then return "Massive" end
		if s == "Huge" then return "Huge" end
		if r == "God" then return "God" end
		if r == "Secret" then return "Secret" end
		if r == "Mythic" then return "Mythic" end
		return nil
	end
	local fn = (Config :: any).CUT_FOR
	if type(fn) ~= "function" then
		table.insert(f, "Config.CUT_FOR missing")
		return f
	end
	for _, r in ipairs(tiers) do
		for si = 1, 3 do
			local s = sizes[si]
			local got = fn(r, s)
			if got ~= expect(r, s) then
				table.insert(f, r .. "/" .. tostring(s) .. " -> " .. tostring(got) .. " expected " .. tostring(expect(r, s)))
			end
		end
	end
	if fn(nil, nil) ~= nil then table.insert(f, "nil/nil must be nil") end
	if fn("Bogus", "Massive") ~= "Massive" then table.insert(f, "unknown rarity + Massive must still be Massive") end
	if #f == 0 then table.insert(f, "routing OK (24 cells + 2 edges)") end
	return f
end


-- One pop on demand (mutation-representation captures): Harness.pop("Epic", "Diamond", name?).
-- Blocks for the pop's length; returns CatchPop.play's result.
function Harness.pop(rarity: string, mutation: string?, name: string?): boolean
	local CatchPop = require(ReplicatedStorage.Modules.CatchPop)
	local colours = { Common = Color3.fromRGB(190,190,190), Uncommon = Color3.fromRGB(80,220,90), Rare = Color3.fromRGB(60,140,255), Epic = Color3.fromRGB(180,60,255), Legendary = Color3.fromRGB(255,170,30) }
	return CatchPop.play({
		Name = name or "Kraken Congelato", Rarity = rarity, RarityColor = colours[rarity] or Color3.new(1, 1, 1),
		Mutation = mutation, IsNew = true, Serial = 47, Exists = 12, OddsN = 1200,
	})
end

-- Pops never touch the camera or Lighting and leave nothing behind.
function Harness.popMatrix(): { string }
	local CatchPop = require(ReplicatedStorage.Modules.CatchPop)
	local f: { string } = {}
	local tiers = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
	local colours = { Color3.fromRGB(190,190,190), Color3.fromRGB(80,220,90), Color3.fromRGB(60,140,255), Color3.fromRGB(180,60,255), Color3.fromRGB(255,170,30) }
	local before = snapshot()
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local guiBefore = pg and #pg:GetDescendants() or 0
	local t0 = os.clock()
	for i, tier in ipairs(tiers) do
		for _, mut in ipairs({ false, "Golden", "Diamond" }) do
			local ok, err = pcall(CatchPop.play, {
				Name = "Kraken Congelato", Rarity = tier, RarityColor = colours[i],
				Mutation = mut or nil, IsNew = (i % 2 == 0), Serial = 47, Exists = 12, OddsN = 1200,
			})
			if not ok then table.insert(f, tier .. "/" .. tostring(mut) .. " errored: " .. tostring(err)) end
		end
	end
	local elapsed = os.clock() - t0
	if elapsed > 15 * 1.6 then table.insert(f, "15 pops took " .. elapsed .. "s (> 1.6s each)") end
	task.wait(0.5)
	diff(before, snapshot(), f)
	local guiAfter = pg and #pg:GetDescendants() or 0
	if guiAfter > guiBefore + 2 then table.insert(f, "PlayerGui grew by " .. (guiAfter - guiBefore)) end
	if #f == 0 then table.insert(f, string.format("pops OK (15 in %.1fs)", elapsed)) end
	return f
end
return Harness
