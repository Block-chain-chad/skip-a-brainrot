local RunService = game:GetService("RunService")
local buoys = script.Parent:WaitForChild("Buoys")
local rng = Random.new()
local data = {}
local function register(model)
	if not model:IsA("Model") or not model.PrimaryPart then return end
	data[model] = {
		base = model:GetPivot(),
		amp = 0.18 + rng:NextNumber()*0.18,
		speed = 1.0 + rng:NextNumber()*0.9,
		phase = rng:NextNumber()*math.pi*2,
		roll = math.rad(1.2 + rng:NextNumber()*2.2),
	}
end
for _, m in ipairs(buoys:GetChildren()) do register(m) end
buoys.ChildAdded:Connect(function(m) task.wait(); register(m) end)
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for model, d in pairs(data) do
		if model.Parent then
			local y = math.sin(t*d.speed + d.phase) * d.amp
			local r = math.sin(t*d.speed*0.7 + d.phase) * d.roll
			model:PivotTo(d.base * CFrame.new(0, y, 0) * CFrame.Angles(r, 0, r*0.4))
		else data[model] = nil end
	end
end)
