-- Brainrot name billboards show ONLY while you're standing inside a plot's circle.
-- Otherwise their BillboardGuis render through walls and clutter the hub / punch through
-- the leaderboard. Purely client-side + per-player: we toggle BillboardGui.Enabled locally.
-- The server (IncomeLoop.updateBillboard) only writes the billboard TEXT, never .Enabled,
-- so this never fights it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local RADIUS = 30                 -- studs from a plot's centre; covers the 44x44 platform,
local RADIUS2 = RADIUS * RADIUS   -- excludes the leaderboard (~36 away) & neighbours (~67 apart)
local INTERVAL = 0.15             -- seconds between visibility passes

local function setPlotBillboards(plot, enabled)
	local pads = plot:FindFirstChild("Pads")
	if not pads then return end
	for _, model in ipairs(pads:GetChildren()) do
		local bg = model:FindFirstChildOfClass("BillboardGui")
		if bg and bg.Enabled ~= enabled then
			bg.Enabled = enabled
		end
	end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < INTERVAL then return end
	acc = 0

	local bases = workspace:FindFirstChild("PlayerBases")
	if not bases then return end

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local pos = hrp and hrp.Position   -- nil (dead/loading) -> everything hides

	for _, plot in ipairs(bases:GetChildren()) do
		local inside = false
		if pos then
			local ok, cf = pcall(function() return plot:GetPivot() end)
			if ok then
				local dx = pos.X - cf.Position.X
				local dz = pos.Z - cf.Position.Z
				inside = (dx * dx + dz * dz) <= RADIUS2
			end
		end
		setPlotBillboards(plot, inside)
	end
end)
