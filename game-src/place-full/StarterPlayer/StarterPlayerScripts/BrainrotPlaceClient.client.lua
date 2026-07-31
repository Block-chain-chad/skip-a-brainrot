-- Choose-your-spot placement. While a brainrot Tool is equipped, every empty pad
-- on your own base lights up; clicking one places the brainrot there. The server
-- re-validates the pad, so this is presentation + aim only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local FREE = Color3.fromRGB(120, 255, 150)
local AIM  = Color3.fromRGB(255, 226, 120)

local held           -- the equipped brainrot Tool
local highlights = {} -- [padPart] = SelectionBox
local aimed          -- pad currently under the cursor

local function padIndexOf(part)
	if not part then return nil end
	local n = part.Name:match("^Pad(%d+)$")
	return n and tonumber(n) or nil
end

-- our own base = the plot whose Pads hold models we own, else the nearest plot.
-- Ownership is enforced server-side; this only decides what to light up.
local function myPlot()
	local bases = workspace:FindFirstChild("PlayerBases")
	if not bases then return nil end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local best, bestD
	for _, plot in ipairs(bases:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then return plot end
		local ok, cf = pcall(function() return plot:GetPivot() end)
		if ok then
			local d = (cf.Position - hrp.Position).Magnitude
			if not bestD or d < bestD then best, bestD = plot, d end
		end
	end
	return (bestD and bestD < 90) and best or nil
end

local function clearHighlights()
	for _, box in pairs(highlights) do box:Destroy() end
	table.clear(highlights)
	aimed = nil
end

local function refreshHighlights()
	clearHighlights()
	local plot = myPlot()
	local pads = plot and plot:FindFirstChild("Pads")
	if not pads then return end

	-- a pad is taken if a placed brainrot model sits on it
	local taken = {}
	for _, m in ipairs(pads:GetChildren()) do
		if m:GetAttribute("Uid") then
			local idx = m:GetAttribute("PadIndex") or padIndexOf(m)
			if idx then taken[idx] = true end
			-- models are usually parented at the pad's position; match by proximity too
			for _, p in ipairs(pads:GetChildren()) do
				local pi = padIndexOf(p)
				if pi and p:IsA("BasePart") then
					local ok, cf = pcall(function() return m:GetPivot() end)
					if ok and (Vector3.new(cf.Position.X, 0, cf.Position.Z)
						- Vector3.new(p.Position.X, 0, p.Position.Z)).Magnitude < 3 then
						taken[pi] = true
					end
				end
			end
		end
	end

	for _, p in ipairs(pads:GetChildren()) do
		local idx = padIndexOf(p)
		if idx and p:IsA("BasePart") and not taken[idx] then
			local box = Instance.new("SelectionBox")
			box.Adornee = p
			box.LineThickness = 0.06
			box.Color3 = FREE
			box.SurfaceColor3 = FREE
			box.SurfaceTransparency = 0.78
			box.Transparency = 0.25
			box.Parent = p
			highlights[p] = box
		end
	end
end

local function setAim(part)
	if aimed == part then return end
	if aimed and highlights[aimed] then
		highlights[aimed].Color3 = FREE
		highlights[aimed].SurfaceColor3 = FREE
		highlights[aimed].SurfaceTransparency = 0.78
	end
	aimed = (part and highlights[part]) and part or nil
	if aimed then
		highlights[aimed].Color3 = AIM
		highlights[aimed].SurfaceColor3 = AIM
		highlights[aimed].SurfaceTransparency = 0.45
	end
end

local function onActivated()
	if not held then return end
	local uid = held:GetAttribute("Uid")
	if not uid then return end
	local target = aimed or mouse.Target
	local idx = padIndexOf(target)
	remotes.PlaceBrainrot:FireServer(uid, idx)   -- idx nil -> server picks a free pad
end

local function bind(tool)
	held = tool
	refreshHighlights()
	tool.Activated:Connect(onActivated)
	tool.Unequipped:Once(function()
		if held == tool then held = nil end
		clearHighlights()
	end)
end

local function watch(char)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") and c:GetAttribute("BrainrotTool") then bind(c) end
	end)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") and c:GetAttribute("BrainrotTool") then bind(c) end
	end
end
if player.Character then watch(player.Character) end
player.CharacterAdded:Connect(function(c) held = nil; clearHighlights(); watch(c) end)

-- keep the aim highlight following the cursor
RunService.RenderStepped:Connect(function()
	if held then setAim(mouse.Target) end
end)

-- a successful placement frees/consumes a pad, so re-light the base
remotes.DataUpdated.OnClientEvent:Connect(function()
	if held then task.defer(refreshHighlights) end
end)
