local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local TAG = "DistanceScaledTitle"
local REF, MIN_S, MAX_S = 45, 0.22, 1.4   -- base size at 45 studs; grows closer, shrinks farther

RunService.RenderStepped:Connect(function()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	for _, bb in ipairs(CollectionService:GetTagged(TAG)) do
		if bb:IsA("BillboardGui") then
			local part = bb.Adornee or bb.Parent
			local bw, bh = bb:GetAttribute("BaseW"), bb:GetAttribute("BaseH")
			if part and part:IsA("BasePart") and bw and bh then
				local dist = (camPos - part.Position).Magnitude
				local s = math.clamp(REF / math.max(dist, 1), MIN_S, MAX_S)
				bb.Size = UDim2.fromOffset(bw * s, bh * s)
			end
		end
	end
end)
