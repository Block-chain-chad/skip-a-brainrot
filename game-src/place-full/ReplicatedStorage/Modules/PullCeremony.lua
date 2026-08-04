-- PullCeremony: the "no way mom" layer that runs IN FRONT of CatchReveal for
-- Epic-and-up catches. Beats (approved storyboard 2026-08-03):
--   TAKEOVER  screen fades to black, a tier-coloured star pulses in the void,
--             drifting dust; hold scales with rarity (Sol's RNG energy)
--   CLIMB     giant gold "1 / N" odds counter ticks UP live; honest odds -- N
--             comes from the roster weights (within-tier), never invented
--   BURST     white flash + radial shards, per-tier catch sound + big-hit
--             layer, black fades out revealing the world again
--   HANDOFF   CatchReveal.play() shows the model as before (bands, mutations,
--             real world model for Secret/God -- untouched)
--   STAMP     name slam + rarity chip + "#serial · ONLY n EXIST" + odds line,
--             tap anywhere to dismiss early
-- This module knows nothing about remotes; CatchRevealClient routes into it.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local CatchReveal = require(Modules:WaitForChild("CatchReveal"))
local SoundKit = require(Modules:WaitForChild("SoundKit"))

local M = {}

-- per-tier drama numbers: hold = black-void seconds, climb = counter seconds
local TIERS = {
	Epic      = { hold = 0.9,  climb = 1.0, shards = 10, drama = false },
	Legendary = { hold = 1.3,  climb = 1.2, shards = 12, drama = true },
	Mythic    = { hold = 1.8,  climb = 1.5, shards = 14, drama = true },
	Secret    = { hold = 2.4,  climb = 1.8, shards = 16, drama = true },
	God       = { hold = 2.8,  climb = 2.0, shards = 18, drama = true },
}
local CATCH_SOUND = {
	Epic = "catchEpic", Legendary = "catchLegend", Mythic = "catchMythic",
	Secret = "catchSecret", God = "catchGod",
}

local player = Players.LocalPlayer
local gui, activeToken = nil, 0

local function comma(n)
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,")
	s = s:reverse():gsub("^,", "")
	return s
end

local function ensureGui()
	if gui and gui.Parent then return gui end
	gui = Instance.new("ScreenGui")
	gui.Name = "PullCeremonyUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function clear()
	if gui then
		for _, c in ipairs(gui:GetChildren()) do c:Destroy() end
	end
end

local function label(parent, text, size, color, strokeT)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Parent = parent
	local s = Instance.new("UIStroke")
	s.Thickness = strokeT or math.max(3, size / 14)
	s.Color = Color3.fromRGB(20, 16, 8)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	return l
end

-- 8-point star built from rotated bars, because no image assets are needed
local function makeStar(parent, color)
	local star = Instance.new("Frame")
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.fromScale(0.5, 0.44)
	star.Size = UDim2.fromOffset(10, 10)
	star.BackgroundTransparency = 1
	star.Parent = parent
	for i = 0, 3 do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(i % 2 == 0 and 150 or 96, i % 2 == 0 and 7 or 5)
		bar.Rotation = i * 45
		bar.BackgroundColor3 = color
		bar.BorderSizePixel = 0
		bar.Parent = star
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = bar
	end
	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromOffset(26, 26)
	core.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	core.BorderSizePixel = 0
	core.Parent = star
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(1, 0)
	cc.Parent = core
	local scale = Instance.new("UIScale")
	scale.Parent = star
	return star, scale
end

-- result: {Name, Rarity, RarityColor, Mutation, Serial, Exists, OddsN}
function M.play(result)
	local cfg = TIERS[result.Rarity]
	if not cfg then
		-- not a ceremony tier; plain reveal
		pcall(CatchReveal.play, result)
		return
	end
	activeToken += 1
	local token = activeToken
	local color = result.RarityColor or Color3.fromRGB(255, 216, 77)

	task.spawn(function()
		local g = ensureGui()
		clear()

		-- ===== TAKEOVER =====
		local black = Instance.new("Frame")
		black.Size = UDim2.fromScale(1, 1)
		black.BackgroundColor3 = Color3.fromRGB(4, 4, 8)
		black.BackgroundTransparency = 1
		black.BorderSizePixel = 0
		black.Parent = g
		TweenService:Create(black, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
		if cfg.drama then SoundKit.play("catchDrama") end
		task.wait(0.38)
		if token ~= activeToken then return end

		local star, starScale = makeStar(black, color)
		starScale.Scale = 0.1
		TweenService:Create(starScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		-- slow pulse + spin while the void holds
		task.spawn(function()
			local t0 = os.clock()
			while token == activeToken and star.Parent do
				local dt = os.clock() - t0
				star.Rotation = dt * 24
				starScale.Scale = 1 + 0.08 * math.sin(dt * 3)
				task.wait()
			end
		end)
		-- drifting dust
		for i = 1, 10 do
			local d = Instance.new("Frame")
			d.Size = UDim2.fromOffset(3, 3)
			d.Position = UDim2.fromScale(0.08 + (i * 0.09) % 0.85, 1.05)
			d.BackgroundColor3 = color
			d.BackgroundTransparency = 0.45
			d.BorderSizePixel = 0
			d.Parent = black
			TweenService:Create(d, TweenInfo.new(3 + (i % 3), Enum.EasingStyle.Linear), {
				Position = UDim2.fromScale(0.08 + (i * 0.09) % 0.85, -0.1),
				BackgroundTransparency = 1,
			}):Play()
		end
		SoundKit.play("catchSparkle")
		task.wait(cfg.hold)
		if token ~= activeToken then return end

		-- ===== CLIMB =====
		local counter = label(black, "1 / 2", 96, Color3.fromRGB(255, 216, 77), 8)
		counter.AnchorPoint = Vector2.new(0.5, 0.5)
		counter.Position = UDim2.fromScale(0.5, 0.72)
		local cScale = Instance.new("UIScale")
		cScale.Parent = counter
		local target = math.max(2, result.OddsN or 100)
		local steps = 6
		for s = 1, steps do
			if token ~= activeToken then return end
			-- exponential approach so the last ticks are the big jumps
			local v = math.max(2, math.floor(target ^ (s / steps)))
			counter.Text = "1 / " .. comma(v)
			cScale.Scale = 1.25
			TweenService:Create(cScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			SoundKit.play("catchSparkle")
			task.wait(cfg.climb / steps)
		end
		counter.Text = "1 / " .. comma(target)
		task.wait(0.25)
		if token ~= activeToken then return end

		-- ===== BURST =====
		SoundKit.play(CATCH_SOUND[result.Rarity] or "catchLegend")
		SoundKit.play("catchBigHit")
		local flash = Instance.new("Frame")
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		flash.BorderSizePixel = 0
		flash.Parent = g
		for i = 1, cfg.shards do
			local sh = Instance.new("Frame")
			sh.AnchorPoint = Vector2.new(0.5, 0.5)
			sh.Position = UDim2.fromScale(0.5, 0.5)
			sh.Size = UDim2.fromOffset(8, 60)
			sh.Rotation = i * (360 / cfg.shards)
			sh.BackgroundColor3 = color
			sh.BorderSizePixel = 0
			sh.ZIndex = 3
			sh.Parent = g
			local a = math.rad(sh.Rotation - 90)
			TweenService:Create(sh, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5 + 0.75 * math.cos(a), 0, 0.5 + 0.75 * math.sin(a), 0),
				Size = UDim2.fromOffset(4, 160),
				BackgroundTransparency = 1,
			}):Play()
		end
		TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(black, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.42)
		if token ~= activeToken then return end
		clear()

		-- ===== HANDOFF: the existing reveal shows the model =====
		pcall(CatchReveal.play, result)

		-- ===== STAMP overlay =====
		local stamp = Instance.new("Frame")
		stamp.AnchorPoint = Vector2.new(0.5, 0)
		stamp.Position = UDim2.fromScale(0.5, 0.06)
		stamp.Size = UDim2.fromOffset(10, 10)
		stamp.AutomaticSize = Enum.AutomaticSize.XY
		stamp.BackgroundTransparency = 1
		stamp.Parent = g
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Padding = UDim.new(0, 2)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = stamp
		local nameL = label(stamp, string.upper(result.Name or "?"), 58, Color3.fromRGB(255, 255, 255), 6)
		nameL.LayoutOrder = 1
		local tierL = label(stamp, string.upper(result.Rarity or ""), 30, color, 4)
		tierL.LayoutOrder = 2
		if result.Serial then
			local ex = result.Exists and (" · ONLY " .. tostring(result.Exists) .. " EXIST") or ""
			label(stamp, "#" .. tostring(result.Serial) .. ex, 24, Color3.fromRGB(255, 216, 77), 3).LayoutOrder = 3
		end
		if result.OddsN then
			label(stamp, "1 in " .. tostring(result.OddsN) .. " of its tier", 18, Color3.fromRGB(200, 208, 200), 2.5).LayoutOrder = 4
		end
		local sScale = Instance.new("UIScale")
		sScale.Scale = 2.6
		sScale.Parent = stamp
		TweenService:Create(sScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

		-- tap to dismiss early, else auto-fade
		local dismissed = false
		local conn
		conn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dismissed = true
			end
		end)
		local held = 0
		while held < 3.2 and not dismissed and token == activeToken do
			task.wait(0.1)
			held += 0.1
		end
		conn:Disconnect()
		if token ~= activeToken then return end
		for _, d in ipairs(stamp:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.32)
		if token == activeToken then clear() end
	end)
end

return M
