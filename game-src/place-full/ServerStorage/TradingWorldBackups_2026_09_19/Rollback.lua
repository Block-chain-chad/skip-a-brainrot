--!nocheck
--[[
TradingWorldRollback -- one-step undo of the TW-01 Grand Exchange staging work (2026-09-19).

Installed at ServerStorage.TradingWorldBackups_2026_09_19.Rollback, beside the backups it restores from:
  TradingWorld_Original, TradingCenter_Original, HubPortal_Original (clones without the two island
  scripts), SnapshotJSON (contract record), and the script sources in
  ServerStorage.AuditBackups.PreGrandExchange_2026_09_19 (SkipLoop, CoveDriver, CenterpieceSpinner,
  TeleportService, BoundsGuard, WorldTravelConfig -- disabled stubs holding the live sources).

Run in Edit mode (command bar or the Studio MCP):

    local R = loadstring(game:GetService("ServerStorage").TradingWorldBackups_2026_09_19.Rollback.Source)()
    R.Verify()          -- reports: staging containers present?, live originals still match the backup?
    R.Restore()         -- destroys every staging container; restores TradingWorld / TradingCenter /
                        -- Portals.HubPortal from the backup ONLY where the live one is missing
    R.Restore({ force = true })   -- also replaces a live container whose fingerprint differs
    R.Drill()           -- safe rehearsal: restores into ServerStorage.RollbackDrill (never Workspace),
                        -- checks fingerprints + script re-creation, then deletes the drill folder

NEVER touches: Terrain, Lighting, PlayerBases, the valley TradePortal, any other world folder, any
script outside the two island scripts. Scripts under ServerScriptService / ReplicatedStorage are NOT
restored automatically -- their pre-round sources are in the AuditBackups folder for a by-hand restore
(TW-01 does not edit them; if someone else has edited them since, restoring would overwrite that work).
]]

local SS = game:GetService("ServerStorage")
local CHS = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")

local BK_NAME = "TradingWorldBackups_2026_09_19"
local STAGING = { "TradingWorld_GE", "TradingCenter_GE" }
local STAGING_PORTALS = { "HubPortalVault" }
local RESTORES = {
	{ backup = "TradingWorld_Original", live = "TradingWorld", parentPath = "GameWorld" },
	{ backup = "TradingCenter_Original", live = "TradingCenter", parentPath = "GameWorld" },
	{ backup = "HubPortal_Original", live = "HubPortal", parentPath = "GameWorld.Portals" },
}
-- the two scripts the clone could not carry: stub name -> path (relative to TradingWorld) of the parent
local SCRIPTS = {
	{ stub = "SkipLoop", class = "Script", parentRel = "EternalSkip" },
	{ stub = "CoveDriver", class = "Script", parentRel = "CoveDressing" },
}

local M = {}

local function find(root, path)
	local node = root
	for seg in string.gmatch(path, "[^%.]+") do node = node and node:FindFirstChild(seg) end
	return node
end

local function fingerprint(inst)
	local n, h = 0, 5381
	local rows = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if not d:IsA("LuaSourceContainer") then
			n += 1
			local s = d.Name .. "|" .. d.ClassName
			if d:IsA("BasePart") then
				local p = d.Position
				s = s .. string.format("|%.1f,%.1f,%.1f|%.1f,%.1f,%.1f", p.X, p.Y, p.Z, d.Size.X, d.Size.Y, d.Size.Z)
			end
			table.insert(rows, s)
		end
	end
	table.sort(rows)
	for _, s in ipairs(rows) do
		for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 4294967296 end
	end
	return n, string.format("%08x", h)
end
M.Fingerprint = fingerprint

local function backupFolder()
	local bk = SS:FindFirstChild(BK_NAME)
	assert(bk, BK_NAME .. " is missing -- nothing to restore from")
	return bk
end

-- Re-create the two island scripts inside a restored TradingWorld from the source stubs.
local function restoreScripts(tradingWorld, log)
	local stubs = find(SS, "AuditBackups.PreGrandExchange_2026_09_19")
	if not stubs then table.insert(log, "WARN no AuditBackups.PreGrandExchange_2026_09_19 -- island scripts not restored"); return end
	for _, s in ipairs(SCRIPTS) do
		local parent = find(tradingWorld, s.parentRel)
		local stub = stubs:FindFirstChild(s.stub)
		if not parent then
			table.insert(log, "WARN parent " .. s.parentRel .. " missing for " .. s.stub)
		elseif parent:FindFirstChild(s.stub) then
			table.insert(log, "ok " .. s.stub .. " already present")
		elseif not stub then
			table.insert(log, "WARN stub " .. s.stub .. " missing")
		else
			local ok, err = pcall(function()
				local inst = Instance.new(s.class)
				inst.Name = s.stub
				inst.Source = stub.Source
				inst.Enabled = true
				inst.Parent = parent
			end)
			table.insert(log, (ok and "ok re-created " or "FAILED to re-create ") .. s.stub .. (ok and "" or (" -- do it by hand from the stub: " .. tostring(err))))
		end
	end
end

function M.Verify()
	local bk = backupFolder()
	local gw = workspace:FindFirstChild("GameWorld")
	local report = { staging = {}, live = {} }
	for _, name in ipairs(STAGING) do report.staging[name] = gw and gw:FindFirstChild(name) ~= nil or false end
	for _, name in ipairs(STAGING_PORTALS) do report.staging["Portals." .. name] = gw and find(gw, "Portals." .. name) ~= nil or false end
	for _, r in ipairs(RESTORES) do
		local parent = find(workspace, r.parentPath)
		local live = parent and parent:FindFirstChild(r.live)
		local b = bk:FindFirstChild(r.backup)
		local e = { livePresent = live ~= nil, backupPresent = b ~= nil }
		if live and b then
			local n1, h1 = fingerprint(live); local n2, h2 = fingerprint(b)
			e.liveDesc, e.backupDesc, e.liveHash, e.backupHash, e.match = n1, n2, h1, h2, (n1 == n2 and h1 == h2)
		end
		report.live[r.live] = e
	end
	return report
end

-- opts: { force = bool, targetParent = Instance (drill only) }
function M.Restore(opts)
	opts = opts or {}
	local bk = backupFolder()
	local gw = workspace:FindFirstChild("GameWorld")
	local log = {}
	CHS:SetWaypoint("TradingWorld rollback: before")
	-- 1. staging containers
	if gw then
		for _, name in ipairs(STAGING) do
			local s = gw:FindFirstChild(name)
			if s then s:Destroy(); table.insert(log, "destroyed GameWorld." .. name) end
		end
		for _, name in ipairs(STAGING_PORTALS) do
			local s = find(gw, "Portals." .. name)
			if s then s:Destroy(); table.insert(log, "destroyed GameWorld.Portals." .. name) end
		end
	end
	-- 2/3. live originals
	for _, r in ipairs(RESTORES) do
		local parent = opts.targetParent or find(workspace, r.parentPath)
		local b = bk:FindFirstChild(r.backup)
		if not b then
			table.insert(log, "WARN backup " .. r.backup .. " missing")
		elseif not parent then
			table.insert(log, "WARN parent " .. r.parentPath .. " missing")
		else
			local live = parent:FindFirstChild(r.live)
			local needs = live == nil
			if live and opts.force then
				local n1, h1 = fingerprint(live); local n2, h2 = fingerprint(b)
				if n1 ~= n2 or h1 ~= h2 then live:Destroy(); needs = true; table.insert(log, "force: replaced differing live " .. r.live) end
			end
			if needs then
				local c = b:Clone()
				c.Name = r.live
				c.Parent = parent
				table.insert(log, "restored " .. r.live .. " from " .. r.backup)
				if r.live == "TradingWorld" then restoreScripts(c, log) end
			else
				table.insert(log, "kept live " .. r.live .. (opts.force and " (fingerprint matched)" or " (present; not replaced -- pass force=true to compare and replace)"))
			end
		end
	end
	CHS:SetWaypoint("TradingWorld rollback: after")
	for _, l in ipairs(log) do print("[TradingWorldRollback] " .. l) end
	return log
end

-- Safe rehearsal: exercises the restore-from-backup path (incl. script re-creation) into
-- ServerStorage.RollbackDrill, verifies fingerprints against the backup, then deletes the drill folder.
function M.Drill()
	local bk = backupFolder()
	local drill = SS:FindFirstChild("RollbackDrill")
	if drill then drill:Destroy() end
	drill = Instance.new("Folder"); drill.Name = "RollbackDrill"; drill.Parent = SS
	local portals = Instance.new("Folder"); portals.Name = "Portals"; portals.Parent = drill
	local result = { log = {}, checks = {} }
	for _, r in ipairs(RESTORES) do
		local b = bk:FindFirstChild(r.backup)
		local parent = (r.parentPath == "GameWorld.Portals") and portals or drill
		local c = b:Clone(); c.Name = r.live; c.Parent = parent
		if r.live == "TradingWorld" then restoreScripts(c, result.log) end
		local n1, h1 = fingerprint(c); local n2, h2 = fingerprint(b)
		local scripts = 0
		for _, d in ipairs(c:GetDescendants()) do if d:IsA("LuaSourceContainer") then scripts += 1 end end
		result.checks[r.live] = { desc = n1, backupDesc = n2, match = (n1 == n2 and h1 == h2), scriptsRecreated = scripts }
	end
	drill:Destroy()
	result.drillFolderDeleted = SS:FindFirstChild("RollbackDrill") == nil
	return result
end

return M
