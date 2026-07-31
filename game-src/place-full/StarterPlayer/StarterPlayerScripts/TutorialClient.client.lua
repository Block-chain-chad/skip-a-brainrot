-- First-join onboarding. Shows once ever (TutorialDone saves with player data).
-- Each step parks a glowing beacon + bobbing arrow over the target until it's done.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local BLACK = Color3.fromRGB(0, 0, 0)
local GOLD1, GOLD2 = Color3.fromRGB(255, 220, 100), Color3.fromRGB(240, 150, 24)
local FONT = UITheme.Font

local flags = { threw = false, sold = false }
local active, stepIndex = false, 1

local function blackRim(o, t)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = BLACK; s.Thickness = t or 3; s.Transparency = 0
		end
	end
end
local function inkText(o, t)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Color = BLACK; st.Thickness = t or 2; st.Transparency = 0.05; st.Parent = o
	return st
end

---------------------------------------------------------------- beacon
local beacon = Instance.new("Model")
beacon.Name = "TutorialBeacon"

local function bpart(props)
	local p = Instance.new(props.Class or "Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = props.Color or GOLD1
	p.Size = props.Size
	p.Transparency = props.Transparency or 0
	p.Parent = beacon
	return p
end

-- ground pillar of light
local pillar = bpart({ Size = Vector3.new(46, 6, 6), Transparency = 0.86 })
pillar.Shape = Enum.PartType.Cylinder
-- arrow: shaft + downward point (two mirrored wedges)
local shaft = bpart({ Size = Vector3.new(0.85, 3.2, 0.85) })
local headA = bpart({ Class = "WedgePart", Size = Vector3.new(2.8, 2.1, 1.35) })
local headB = bpart({ Class = "WedgePart", Size = Vector3.new(2.8, 2.1, 1.35) })

local glow = Instance.new("PointLight")
glow.Color = GOLD1; glow.Range = 26; glow.Brightness = 3
glow.Parent = shaft

local tagGui = Instance.new("BillboardGui")
tagGui.Size = UDim2.fromOffset(190, 42)
tagGui.StudsOffset = Vector3.new(0, 4.2, 0)
tagGui.AlwaysOnTop = true
-- Deliberately the most generous cap in the game (everything else is 90-160). This is
-- a wayfinding beacon whose whole job is to be seen from far enough away to walk
-- toward, so capping it like a sign would defeat it. It only exists during the
-- first-join tutorial and only one is ever active.
tagGui.MaxDistance = 400
tagGui.Parent = shaft
local tag = Instance.new("TextLabel")
tag.Size = UDim2.fromScale(1, 1)
tag.BackgroundTransparency = 1
tag.Font = FONT
tag.TextScaled = true
tag.TextColor3 = Color3.fromRGB(255, 236, 160)
tag.Text = ""
tag.Parent = tagGui
inkText(tag, 2.5)

local function setBeacon(pos, label)
	if not pos then
		beacon.Parent = nil
		return
	end
	beacon.Parent = Workspace
	tag.Text = label or ""
	beacon:SetAttribute("BaseX", pos.X)
	beacon:SetAttribute("BaseY", pos.Y)
	beacon:SetAttribute("BaseZ", pos.Z)
end

RunService.RenderStepped:Connect(function()
	if beacon.Parent == nil then return end
	local bx = beacon:GetAttribute("BaseX")
	if not bx then return end
	local base = Vector3.new(bx, beacon:GetAttribute("BaseY"), beacon:GetAttribute("BaseZ"))
	local t = os.clock()
	local bob = math.sin(t * 2.2) * 0.8
	local spin = t * 1.6
	local tip = base + Vector3.new(0, 7.5 + bob, 0)

	pillar.CFrame = CFrame.new(base + Vector3.new(0, 23, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shaft.CFrame = CFrame.new(tip + Vector3.new(0, 3.4, 0)) * CFrame.Angles(0, spin, 0)
	local headCF = CFrame.new(tip + Vector3.new(0, 1.05, 0)) * CFrame.Angles(0, spin, 0)
	headA.CFrame = headCF * CFrame.new(0, 0, 0.675) * CFrame.Angles(math.rad(180), 0, 0)
	headB.CFrame = headCF * CFrame.new(0, 0, -0.675) * CFrame.Angles(math.rad(180), math.rad(180), 0)
end)

---------------------------------------------------------------- card UI
local card = Instance.new("Frame")
card.Name = "TutorialCard"
card.AnchorPoint = Vector2.new(0, 1)
card.Position = UDim2.new(0, 16, 1, -16)
card.Size = UDim2.fromOffset(340, 152)
card.Visible = false
card.ZIndex = 9
card.Parent = gui
UITheme.stylePanel(card)
UITheme.corner(card, 16)
blackRim(card, 3)

local stepLbl = Instance.new("TextLabel")
stepLbl.Size = UDim2.new(1, -20, 0, 20)
stepLbl.Position = UDim2.new(0, 14, 0, 10)
stepLbl.BackgroundTransparency = 1
stepLbl.Font = FONT
stepLbl.TextSize = 14
stepLbl.TextXAlignment = Enum.TextXAlignment.Left
stepLbl.TextColor3 = Color3.fromRGB(255, 220, 110)
stepLbl.ZIndex = 10
stepLbl.Parent = card
inkText(stepLbl, 1.8)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -20, 0, 26)
titleLbl.Position = UDim2.new(0, 14, 0, 30)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = FONT
titleLbl.TextSize = 20
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLbl.ZIndex = 10
titleLbl.Parent = card
inkText(titleLbl, 2.2)

local bodyLbl = Instance.new("TextLabel")
bodyLbl.Size = UDim2.new(1, -24, 0, 44)
bodyLbl.Position = UDim2.new(0, 14, 0, 58)
bodyLbl.BackgroundTransparency = 1
bodyLbl.Font = Enum.Font.GothamMedium
bodyLbl.TextSize = 13
bodyLbl.TextWrapped = true
bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
bodyLbl.TextYAlignment = Enum.TextYAlignment.Top
bodyLbl.TextColor3 = Color3.fromRGB(196, 206, 226)
bodyLbl.ZIndex = 10
bodyLbl.Parent = card

local skipBtn = Instance.new("TextButton")
skipBtn.Size = UDim2.fromOffset(126, 32)
skipBtn.Position = UDim2.new(1, -138, 1, -40)
skipBtn.Text = "Skip Tutorial"
skipBtn.ZIndex = 10
skipBtn.Parent = card
UITheme.styleHudButton(skipBtn, Color3.fromRGB(150, 156, 170), Color3.fromRGB(94, 100, 114), 10)
skipBtn.TextSize = 13
blackRim(skipBtn, 2.5)

---------------------------------------------------------------- helpers
local gw = Workspace:WaitForChild("GameWorld")
local plots = Workspace:WaitForChild("PlayerBases")

local function myPlot()
	for _, p in ipairs(plots:GetChildren()) do
		if p:GetAttribute("OwnerUserId") == player.UserId then return p end
	end
	return nil
end
local function nearestFreePlot()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local best, bestD
	for _, p in ipairs(plots:GetChildren()) do
		if p:IsA("Model") and not p:GetAttribute("Claimed") and p.PrimaryPart then
			local d = hrp and (p.PrimaryPart.Position - hrp.Position).Magnitude or 0
			if not bestD or d < bestD then best, bestD = p, d end
		end
	end
	return best
end
local function stallPos(name)
	local stall = gw:FindFirstChild(name)
	local part = stall and stall:FindFirstChild("PromptPart")
	return part and part.Position
end
local function nearPos(pos, dist)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and pos) then return false end
	return (hrp.Position - pos).Magnitude <= dist
end

---------------------------------------------------------------- steps
local steps = {
	{
		Title = "CLAIM YOUR BASE",
		Body = "Every player needs a base. Walk onto a free plot to claim it as your own.",
		Tag = "CLAIM HERE",
		Target = function()
			local p = nearestFreePlot()
			return p and p.PrimaryPart and p.PrimaryPart.Position
		end,
		Done = function() return myPlot() ~= nil end,
	},
	{
		Title = "SKIP A ROCK",
		Body = "Head to the dock and hold to skip. The farther you skip, the rarer the brainrot!",
		Tag = "SKIP HERE",
		Target = function()
			local z = gw:FindFirstChild("ThrowZone")
			return z and z.Position
		end,
		Done = function() return flags.threw end,
	},
	{
		Title = "SELL YOUR BRAINROTS",
		Body = "Brainrots earn cash on your base. Sell spares to Marco for a quick payout.",
		Tag = "MARCO - SELL",
		Target = function() return stallPos("SellStall") end,
		Done = function() return flags.sold or nearPos(stallPos("SellStall"), 13) end,
	},
	{
		Title = "BUY BETTER ROCKS",
		Body = "Rocco sells rocks that skip farther and roll luckier. Press E to browse.",
		Tag = "ROCCO - ROCKS",
		Target = function() return stallPos("ShopStall") end,
		Done = function() return nearPos(stallPos("ShopStall"), 13) end,
	},
	{
		Title = "GRAB UPGRADES",
		Body = "Enzo sells permanent boosts to luck, skip power and income. You're all set!",
		Tag = "ENZO - UPGRADES",
		Target = function() return stallPos("UpgradeStall") end,
		Done = function() return nearPos(stallPos("UpgradeStall"), 13) end,
	},
}

local function showStep(i)
	local s = steps[i]
	if not s then return end
	stepLbl.Text = ("STEP %d / %d"):format(i, #steps)
	titleLbl.Text = s.Title
	bodyLbl.Text = s.Body
	setBeacon(s.Target(), s.Tag)
end

local function finish()
	active = false
	card.Visible = false
	setBeacon(nil)
	remotes.TutorialComplete:FireServer()
end

skipBtn.Activated:Connect(finish)

local function start()
	if active then return end
	active = true
	stepIndex = 1
	card.Visible = true
	showStep(1)
end

remotes.ThrowResult.OnClientEvent:Connect(function() flags.threw = true end)
remotes.SellResult.OnClientEvent:Connect(function() flags.sold = true end)

-- advance / keep the beacon parked on the live target
task.spawn(function()
	while true do
		task.wait(0.4)
		if active then
			local s = steps[stepIndex]
			if s then
				if s.Done() then
					stepIndex += 1
					if stepIndex > #steps then
						finish()
					else
						showStep(stepIndex)
					end
				else
					setBeacon(s.Target(), s.Tag)
				end
			end
		end
	end
end)

task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok and snap and not snap.TutorialDone then
		task.wait(1.5)
		start()
	end
end)
