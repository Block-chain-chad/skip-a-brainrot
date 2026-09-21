-- SkipLoop — the "Eternal Skip": a glowing stone perpetually skipping around the
-- trading cove's water ring (r68 around island centre 8000,8000), splash rings on
-- every touchdown. Lives in Workspace.GameWorld.TradingWorld.EternalSkip alongside
-- parts Stone + Ring1-3. Server Script; animates only in Play.
local model = script.Parent
local stone = model:WaitForChild("Stone")
local rings = { model:WaitForChild("Ring1"), model:WaitForChild("Ring2"), model:WaitForChild("Ring3") }
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CX, CZ, R = 8150, 7878, 40
local WATER_Y = 2000.0
local SPEED = math.rad(26)      -- degrees per second around the ring
local HOP = math.rad(11)        -- arc length of one skip
local PEAK = 2.3
local angle, ringIdx = 0, 0
local function splash(x, z)
	ringIdx = ringIdx % 3 + 1
	local ring = rings[ringIdx]
	ring.Size = Vector3.new(0.12, 2, 2)
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(x, WATER_Y + 0.03, z) * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, 9, 9), Transparency = 1,
	}):Play()
end
RunService.Heartbeat:Connect(function(dt)
	local prevPhase = (angle % HOP) / HOP
	angle += SPEED * dt
	local phase = (angle % HOP) / HOP
	local x = CX + R * math.cos(angle)
	local z = CZ + R * math.sin(angle)
	local y = WATER_Y + 0.35 + PEAK * 4 * phase * (1 - phase)
	stone.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, -angle, math.rad(90 + 12))
	if phase < prevPhase then splash(x, z) end
end)
