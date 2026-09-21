-- SeasonClient: trophy rail tile + season pass panel (daily quests -> XP -> 25-tier track)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local seasonState = remotes:WaitForChild("SeasonState")
local seasonClaim = remotes:WaitForChild("SeasonClaim")
local modules = ReplicatedStorage:WaitForChild("Modules")
local SeasonConfig = require(modules:WaitForChild("SeasonConfig"))
local UIStyle = require(modules:WaitForChild("UIStyle"))
local UITheme = require(modules:WaitForChild("UITheme"))
local SideRail = require(modules:WaitForChild("SideRail"))
local PAL = UIStyle.Palette
local CF = UITheme.Camp
local FONT = UITheme.Font

local PINK1, PINK2 = Color3.fromRGB(255, 138, 205), Color3.fromRGB(214, 56, 150)

local function fmt(n)
	n = math.floor(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.0fK", n / 1e3) end
	return tostring(n)
end

local tile = SideRail.MakeTile({
	name = "Season", iconKind = "trophy", layoutOrder = 6,
	hueTop = PINK1, hueBottom = PINK2,
	accent = Color3.fromRGB(236, 88, 176),
})

local gui = Instance.new("ScreenGui")
gui.Name = "SeasonUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "SeasonPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.fromOffset(640, 478)
panel.ZIndex = 10
panel.Visible = false
panel.Parent = gui
UIStyle.stylePanel(panel, PAL.Season)   -- keeps the popIn/popOut base-scale attribute
UITheme.campPanel(panel)                -- warm brown campfire body over it
SideRail.registerPanel(panel)           -- only one rail panel open at a time
UIStyle.stroke(panel, CF.ink, 4)        -- fold the old purple rim into the black outline

-- carved-wood banner that overhangs the panel top
local ribbon, title = UITheme.ribbon(panel, "SEASON PASS", 0.58)

local closeBtn = Instance.new("TextButton")
closeBtn.Parent = panel
UIStyle.styleClose(closeBtn)
UIStyle.attachHoverPress(closeBtn)
UIStyle.stroke(closeBtn, CF.ink, 3)
UIStyle.bubbleText(closeBtn, CF.ink)
UITheme.setColors(closeBtn, CF.ember1, CF.ember2)
closeBtn.TextSize = 18
closeBtn.ZIndex = 20

local xpLabel = Instance.new("TextLabel")
xpLabel.BackgroundTransparency = 1
xpLabel.Size = UDim2.new(1, -32, 0, 22)
xpLabel.Position = UDim2.new(0, 16, 0, 46)
xpLabel.Font = FONT
xpLabel.TextSize = 16
xpLabel.TextColor3 = CF.cream
xpLabel.TextXAlignment = Enum.TextXAlignment.Left
xpLabel.Text = ""
xpLabel.ZIndex = 12
xpLabel.Parent = panel
UITheme.inkText(xpLabel, 2.4)

-- === daily quests ===
local questHeader = Instance.new("TextLabel")
questHeader.BackgroundTransparency = 1
questHeader.Size = UDim2.new(1, -32, 0, 16)
questHeader.Position = UDim2.new(0, 16, 0, 72)
questHeader.Font = FONT
questHeader.TextSize = 14
questHeader.TextColor3 = CF.amber1
questHeader.TextXAlignment = Enum.TextXAlignment.Left
questHeader.Text = "TODAY'S QUESTS  \u{2014}  new ones at midnight UTC"
questHeader.ZIndex = 12
questHeader.Parent = panel
UITheme.inkText(questHeader, 2.2)

local questFrame = Instance.new("Frame")
questFrame.BackgroundTransparency = 1
questFrame.Position = UDim2.new(0, 16, 0, 92)
questFrame.Size = UDim2.new(1, -32, 0, 184)
questFrame.ZIndex = 11
questFrame.Parent = panel
local ql = Instance.new("UIListLayout")
ql.Padding = UDim.new(0, 8)
ql.SortOrder = Enum.SortOrder.LayoutOrder
ql.Parent = questFrame

-- === track ===
local trackHeader = questHeader:Clone()
trackHeader.Position = UDim2.new(0, 16, 0, 286)
trackHeader.Text = "REWARD TRACK"
trackHeader.Parent = panel

local track = Instance.new("ScrollingFrame")
track.Position = UDim2.new(0, 16, 0, 306)
track.Size = UDim2.new(1, -32, 0, 160)
track.ZIndex = 11
track.BackgroundTransparency = 1
track.BorderSizePixel = 0
track.ScrollBarThickness = 6
track.ScrollingDirection = Enum.ScrollingDirection.X
track.CanvasSize = UDim2.new()
track.AutomaticCanvasSize = Enum.AutomaticSize.X
track.Parent = panel
local tl = Instance.new("UIListLayout")
tl.FillDirection = Enum.FillDirection.Horizontal
tl.Padding = UDim.new(0, 6)
tl.SortOrder = Enum.SortOrder.LayoutOrder
tl.Parent = track

local state = { XP = 0, Claimed = {}, QuestIds = {}, Progress = {} }

-- one accent per quest card, carried through the card border, the quest name
-- colour and the sunburst behind the icon (done quests go pine green)
local QUEST_ACCENTS = { CF.amber1, CF.lake1, CF.berry1 }

local function render()
	local tierNow = math.floor(state.XP / SeasonConfig.XP_PER_TIER)
	local intoTier = state.XP - tierNow * SeasonConfig.XP_PER_TIER
	xpLabel.Text = ("Season XP: %d   \u{2022}   Tier %d/%d   \u{2022}   %d/%d XP to next"):format(
		state.XP, math.min(tierNow, #SeasonConfig.Tiers), #SeasonConfig.Tiers, intoTier, SeasonConfig.XP_PER_TIER)

	-- quests
	for _, c in ipairs(questFrame:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	for i, qid in ipairs(state.QuestIds) do
		local def = SeasonConfig.PoolById[qid]
		if def then
			local pr = state.Progress[qid] or { P = 0, D = false }
			local acc = pr.D and CF.pine1 or QUEST_ACCENTS[((i - 1) % #QUEST_ACCENTS) + 1]
			local row, rowOuter = UITheme.accentCard(questFrame, acc, 12)
			rowOuter.Size = UDim2.new(1, 0, 0, 56)
			rowOuter.LayoutOrder = i
			rowOuter.ZIndex = 11
			row.ZIndex = 12
			if pr.D then row.BackgroundTransparency = 0.25 end

			-- sunburst icon tile
			local iconTile = Instance.new("Frame")
			iconTile.AnchorPoint = Vector2.new(0, 0.5)
			iconTile.Position = UDim2.new(0, 8, 0.5, 0)
			iconTile.Size = UDim2.fromOffset(40, 40)
			iconTile.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			iconTile.BorderSizePixel = 0
			iconTile.ClipsDescendants = true
			iconTile.ZIndex = row.ZIndex + 1
			iconTile.Parent = row
			UITheme.corner(iconTile, 9)
			UITheme.sunburst(iconTile, acc, 12)
			UITheme.ink(iconTile, 2.5)

			local icon = Instance.new("TextLabel")
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromScale(1, 1)
			icon.Font = FONT
			icon.TextSize = 22
			icon.Text = def.Icon
			icon.ZIndex = iconTile.ZIndex + 4
			icon.Parent = iconTile

			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Size = UDim2.new(1, -330, 1, 0)
			name.Position = UDim2.new(0, 58, 0, 0)
			name.Font = FONT
			name.TextSize = 16
			name.TextColor3 = acc
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Text = def.Name
			name.ZIndex = row.ZIndex + 2
			name.Parent = row
			UITheme.inkText(name, 2.6)

			-- progress bar: pine fill in a black-outlined dark trough
			local barBg = Instance.new("Frame")
			barBg.AnchorPoint = Vector2.new(1, 0.5)
			barBg.Position = UDim2.new(1, -128, 0.5, 0)
			barBg.Size = UDim2.new(0, 136, 0, 16)
			barBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			barBg.BorderSizePixel = 0
			barBg.ZIndex = row.ZIndex + 2
			barBg.Parent = row
			UIStyle.pill(barBg)
			UITheme.gradient(barBg, CF.panelBot, CF.ink, 90)
			UITheme.ink(barBg, 2.5)
			local fill = Instance.new("Frame")
			fill.Size = UDim2.new(math.clamp(pr.P / def.Target, 0, 1), 0, 1, 0)
			fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			fill.BorderSizePixel = 0
			fill.ZIndex = barBg.ZIndex + 1
			fill.Parent = barBg
			UIStyle.pill(fill)
			UITheme.gradient(fill, CF.pine1, CF.pine2, 90)

			local count = Instance.new("TextLabel")
			count.BackgroundTransparency = 1
			count.AnchorPoint = Vector2.new(1, 0.5)
			count.Position = UDim2.new(1, -10, 0.5, 0)
			count.Size = UDim2.new(0, 112, 1, 0)
			count.Font = Enum.Font.GothamMedium
			count.TextSize = 13
			count.TextColor3 = pr.D and CF.pine1 or CF.cream
			count.TextXAlignment = Enum.TextXAlignment.Right
			count.Text = pr.D and ("\u{2713} +%d XP"):format(def.XP) or ("%d/%d  +%d XP"):format(pr.P, def.Target, def.XP)
			count.ZIndex = row.ZIndex + 2
			count.Parent = row
			UITheme.inkText(count, 2)
		end
	end

	-- track
	for _, c in ipairs(track:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local claimableCount = 0
	for i, def in ipairs(SeasonConfig.Tiers) do
		local unlocked = state.XP >= SeasonConfig.ThresholdFor(i)
		local claimed = state.Claimed[tostring(i)] == true
		if unlocked and not claimed then claimableCount += 1 end

		-- accent trio: claimable = amber, claimed = pine, locked milestone = berry
		local accent = claimed and CF.pine1 or (unlocked and CF.amber1) or (def.Milestone and CF.berry1 or CF.wood1)
		local card, cardOuter = UITheme.accentCard(track, accent, 12)
		cardOuter.Size = UDim2.fromOffset(92, 150)
		cardOuter.LayoutOrder = i
		cardOuter.ZIndex = 11
		card.ZIndex = 12
		if claimed then card.BackgroundTransparency = 0.3 end

		local tn = Instance.new("TextLabel")
		tn.BackgroundTransparency = 1
		tn.Size = UDim2.new(1, 0, 0, 16)
		tn.Position = UDim2.new(0, 0, 0, 6)
		tn.Font = FONT
		tn.TextSize = 13
		tn.TextColor3 = accent
		tn.Text = (def.Milestone and "\u{2B50} " or "") .. "TIER " .. i
		tn.ZIndex = card.ZIndex + 2
		tn.Parent = card
		UITheme.inkText(tn, 2.4)

		local medal = Instance.new("Frame")
		medal.AnchorPoint = Vector2.new(0.5, 0)
		medal.Position = UDim2.new(0.5, 0, 0, 26)
		medal.Size = UDim2.fromOffset(42, 42)
		medal.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		medal.BorderSizePixel = 0
		medal.ClipsDescendants = true
		medal.ZIndex = card.ZIndex + 1
		medal.Parent = card
		UITheme.corner(medal, 9)
		UITheme.sunburst(medal, accent, 10)
		UITheme.ink(medal, 2.5)

		local emoji = Instance.new("TextLabel")
		emoji.BackgroundTransparency = 1
		emoji.Size = UDim2.fromScale(1, 1)
		emoji.Font = FONT
		emoji.TextSize = 24
		-- the badge now says WHAT the tier gives, not just whether it is a milestone
		local rw = SeasonConfig.DescribeReward(def)
		local kindGlyph = (rw.kind == "Emeralds" and "\u{1F48E}")
			or (rw.kind == "Egg" and "\u{1F95A}")
			or (def.Milestone and "\u{2B50}" or "\u{1F4B0}")
		emoji.Text = claimed and "\u{2705}" or kindGlyph
		emoji.ZIndex = medal.ZIndex + 4
		emoji.Parent = medal

		local cash = Instance.new("TextLabel")
		cash.AnchorPoint = Vector2.new(0.5, 0)
		cash.Position = UDim2.new(0.5, 0, 0, 74)
		cash.Size = UDim2.new(1, -14, 0, 22)
		cash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		cash.BorderSizePixel = 0
		cash.Font = FONT
		cash.TextSize = 14
		cash.TextColor3 = CF.cream
		-- cash keeps this client's own abbreviator; every other kind arrives
		-- display-ready from SeasonConfig so the two pass UIs cannot word it differently
		cash.Text = (rw.kind == "Cash") and ("$" .. fmt(rw.amount)) or rw.text
		cash.ZIndex = card.ZIndex + 2
		cash.Parent = card
		UITheme.corner(cash, 7)
		UITheme.gradient(cash, CF.amber1, CF.amber2, 90)
		UITheme.ink(cash, 2.5)
		UITheme.inkText(cash, 2.2)
		if claimed then
			cash.TextTransparency = 0.3
			cash.BackgroundTransparency = 0.45
		end

		local btn = Instance.new("TextButton")
		btn.AnchorPoint = Vector2.new(0.5, 1)
		btn.Position = UDim2.new(0.5, 0, 1, -8)
		btn.Size = UDim2.new(1, -14, 0, 32)
		btn.TextSize = 12
		btn.ZIndex = card.ZIndex + 2
		btn.Parent = card
		if claimed then
			btn.Text = "\u{2713} CLAIMED"
			UITheme.campButton(btn, CF.pine1, CF.pine2)
			UIStyle.attachHoverPress(btn, false)
			btn.AutoButtonColor = false
		elseif unlocked then
			btn.Text = "CLAIM!"
			UITheme.campButton(btn, CF.amber1, CF.amber2)
			UIStyle.attachHoverPress(btn)
			local tierIdx = i
			btn.MouseButton1Click:Connect(function()
				seasonClaim:FireServer(tierIdx)
			end)
		else
			btn.Text = "\u{1F512} " .. SeasonConfig.ThresholdFor(i) .. " XP"
			UITheme.campButton(btn, CF.panelTop, CF.panelBot)
			UIStyle.attachHoverPress(btn, false)
			btn.AutoButtonColor = false
		end
		btn.TextSize = 12
	end

	tile.setReady(claimableCount > 0)
	tile.setBadge(claimableCount > 0 and "count" or "none", claimableCount)
end

seasonState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	state.XP = s.XP or 0
	state.Claimed = s.Claimed or {}
	state.QuestIds = s.QuestIds or {}
	state.Progress = s.Progress or {}
	render()
end)

tile.button.MouseButton1Click:Connect(function()
	if panel.Visible then
		UIStyle.popOut(panel)
	else
		UIStyle.popIn(panel)
		seasonState:FireServer() -- refresh
	end
end)
closeBtn.MouseButton1Click:Connect(function()
	UIStyle.popOut(panel)
end)

-- initial state once the UI is ready
task.wait(1)
seasonState:FireServer()
