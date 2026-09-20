-- Slowly spins + bobs any decor part tagged with the "Spin" attribute
-- (the Trading Plaza centerpiece gem).
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local gems = {}
local gameWorld = Workspace:FindFirstChild("GameWorld")
local container = gameWorld and gameWorld:FindFirstChild("TradingWorld")
if container then
	for _, part in ipairs(container:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("Spin") then
			table.insert(gems, { part = part, base = part.Position })
		end
	end
end

local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	for _, g in ipairs(gems) do
		if g.part.Parent then
			local bob = math.sin(t * 1.5) * 1.2
			g.part.CFrame = CFrame.new(g.base + Vector3.new(0, bob, 0))
				* CFrame.Angles(math.rad(45), t * 0.9, math.rad(45))
		end
	end
end)
