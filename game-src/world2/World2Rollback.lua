--!nocheck
--[[
World2Rollback -- one-step undo of the World 2 greybox blockout (BEAST, 2026-09-19).

Installed at ServerStorage.World2Backups_2026_09_19.Rollback, beside the backups it restores from.
Run in Edit mode:

    loadstring(game:GetService("ServerStorage").World2Backups_2026_09_19.Rollback.Source)().Restore()

Restores: GameWorld.FrozenTundra (from FrozenTundra_Original), the five Tundra stall prompt models,
DailyWheelTundra, LeaderboardsTundra, Portals.TundraReturnPortal and Portals.DepthsPortal,
PlayerBases.Plot7-12, the Tundra terrain (clears everything the generator can write, then pastes the
saved TundraTerrain region back), and the script sources saved in
ServerStorage.AuditBackups.PreWorld2Blockout_2026_09_19.

CHECK FIRST: the scripts are restored to their 2026-09-19 sources. If anyone has edited TeleportService,
IceFishingEvent, WheelBoard, LeaderboardBoards, TundraWeatherFX or SnowFootprints since, their edits
would be overwritten -- restore those by hand instead.
]]

local M = {}

local function find(path)
	local node = game
	for name in path:gmatch("[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

function M.Restore()
	local SS = game:GetService("ServerStorage")
	local CHS = game:GetService("ChangeHistoryService")
	local bk = SS:FindFirstChild("World2Backups_2026_09_19")
	assert(bk, "World2Backups_2026_09_19 is missing -- nothing to restore from")
	local gw = workspace.GameWorld
	local log = {}
	CHS:SetWaypoint("World2 rollback: before")

	local cur = gw:FindFirstChild("FrozenTundra")
	if cur then cur:Destroy() end
	local ft = bk.FrozenTundra_Original:Clone()
	ft.Name = "FrozenTundra"
	ft.Parent = gw
	table.insert(log, "FrozenTundra restored")

	for _, m in ipairs(bk.GameWorldObjects:GetChildren()) do
		local c = gw:FindFirstChild(m.Name)
		if c then c:Destroy() end
		m:Clone().Parent = gw
	end
	for _, m in ipairs(bk.Portals:GetChildren()) do
		local c = gw.Portals:FindFirstChild(m.Name)
		if c then c:Destroy() end
		m:Clone().Parent = gw.Portals
	end
	for _, m in ipairs(bk.Plots:GetChildren()) do
		local c = workspace.PlayerBases:FindFirstChild(m.Name)
		if c then c:Destroy() end
		m:Clone().Parent = workspace.PlayerBases
	end
	table.insert(log, "stall prompts, wheel, leaderboards, portals and plots 7-12 restored")

	local folder = SS:FindFirstChild("World2Blockout")
	local gen = folder and folder:FindFirstChild("Generator")
	if gen then
		loadstring(gen.Source)().ClearAll()
		table.insert(log, "generator terrain cleared")
	end
	local tr = bk.TundraTerrain
	workspace.Terrain:PasteRegion(tr,
		Vector3int16.new(tr:GetAttribute("CornerX"), tr:GetAttribute("CornerY"), tr:GetAttribute("CornerZ")), true)
	table.insert(log, "Tundra terrain pasted back")

	local ab = SS:FindFirstChild("AuditBackups")
	local sb = ab and ab:FindFirstChild("PreWorld2Blockout_2026_09_19")
	if sb then
		for _, s in ipairs(sb:GetChildren()) do
			local live = find(s:GetAttribute("OriginalPath") or "")
			if live then
				live.Source = s.Source
				table.insert(log, "script restored: " .. live:GetFullName())
			end
		end
	end
	CHS:SetWaypoint("World2 rollback: after")
	return log
end

return M
