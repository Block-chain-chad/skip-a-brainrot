-- QuestClient: the Goals button + goals/milestones panel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local CF = UITheme.Camp
local FONT = UITheme.Font

local function fmt(n)
	n = math.floor(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.0fK", n / 1e3) end
	return tostring(n)
end
local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
-- recolour an already-styled element's border stroke to the campfire black
local function blackRim(o, thick)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = CF.ink; s.Thickness = thick or 3; s.Transparency = 0
		end
	end
end

local gui = new("ScreenGui", { Name = "QuestUI", ResetOnSpawn = false, DisplayOrder = 9 }, player:WaitForChild("PlayerGui"))

local SideRail = require(ReplicatedStorage.Modules.SideRail)
local tile = SideRail.MakeTile({
	name = "Goals", iconKind = "target", layoutOrder = 2,
	hueTop = Color3.fromRGB(90, 180, 255), hueBottom = Color3.fromRGB(30, 127, 219),
	accent = Color3.fromRGB(46, 155, 255),
})
local btn = tile.button

local panel = new("Frame", {
	Name = "GoalsPanel", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 560, 0, 468), BackgroundColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 10,
}, gui)
UITheme.campPanel(panel)
SideRail.registerPanel(panel)   -- only one rail panel open at a time

-- carved-wood banner that overhangs the panel top
UITheme.ribbon(panel, "GOALS", 0.56)

local blurb = new("TextLabel", { Position = UDim2.new(0, 22, 0, 44), Size = UDim2.new(1, -44, 0, 20), BackgroundTransparency = 1,
	Text = "Hit a milestone, then claim your reward.", Font = FONT, TextSize = 14, TextColor3 = CF.muted,
	TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 }, panel)
UITheme.inkText(blurb, 1.8)

local closeBtn = new("TextButton", {}, panel)
UITheme.styleClose(closeBtn)
closeBtn.ZIndex = 18
closeBtn.TextSize = 18
blackRim(closeBtn, 3)

local list = new("ScrollingFrame", { Position = UDim2.new(0, 18, 0, 74), Size = UDim2.new(1, -36, 1, -92), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0), ZIndex = 11 }, panel)
new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)

local function clearList()
	for _, c in ipairs(list:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
end

-- each goal card gets its own accent, carried through the card border, the
-- title colour and the sunburst behind the icon -- that trio sells the style.
local ACCENTS = {
	{ CF.amber1, CF.amber2 },
	{ CF.pine1,  CF.pine2  },
	{ CF.lake1,  CF.lake2  },
	{ CF.ember1, CF.ember2 },
	{ CF.berry1, CF.berry2 },
}
local ICONS = { "\u{1F3AF}", "\u{1F3C6}", "\u{2B50}", "\u{1F525}", "\u{1F48E}" }

local function render(quests)
	clearList()
	local anyClaimable = false
	for i, q in ipairs(quests) do
		local claimable = q.Met and not q.Claimed
		if claimable then anyClaimable = true end
		local acc = ACCENTS[((i - 1) % #ACCENTS) + 1]
		local card, outer = UITheme.accentCard(list, acc[1], 14)
		outer.Size = UDim2.new(1, -6, 0, 92)
		outer.LayoutOrder = i
		outer.ZIndex = 11
		card.ZIndex = 12
		if not claimable then card.BackgroundTransparency = 0.18 end

		-- sunburst icon tile
		local icon = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(64, 64),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = card.ZIndex + 1 }, card)
		UITheme.corner(icon, 10)
		UITheme.sunburst(icon, acc[1], 12)
		UITheme.ink(icon, 3)
		new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT, TextSize = 34,
			Text = ICONS[((i - 1) % #ICONS) + 1], TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = icon.ZIndex + 4 }, icon)

		local n = new("TextLabel", { Position = UDim2.new(0, 88, 0, 14), Size = UDim2.new(1, -246, 0, 26), BackgroundTransparency = 1,
			Text = q.Desc, Font = FONT, TextSize = 17, TextColor3 = acc[1],
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = card.ZIndex + 2 }, card)
		UITheme.inkText(n, 2.8)

		local sub = "Reward  $" .. fmt(q.Reward)
		if q.Claimed then sub = sub .. "  \u{2022}  collected" end
		local d = new("TextLabel", { Position = UDim2.new(0, 88, 0, 44), Size = UDim2.new(1, -246, 0, 32), BackgroundTransparency = 1,
			Text = sub, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = CF.muted, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = card.ZIndex + 2 }, card)
		UITheme.inkText(d, 1.6)

		local b = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.new(0, 142, 0, 44),
			TextSize = 18, ZIndex = card.ZIndex + 2 }, card)
		if q.Claimed then
			UITheme.campButton(b, CF.pine2, CF.panelBot)
			b.Text = "\u{2713} CLAIMED"
			b.TextColor3 = CF.pine1
			b.AutoButtonColor = false
		elseif claimable then
			UITheme.campButton(b, CF.pine1, CF.pine2)
			b.Text = "CLAIM"
			b.MouseButton1Click:Connect(function() remotes.QuestClaim:FireServer(q.Id) end)
		else
			UITheme.campButton(b, CF.panelTop, CF.panelBot)
			b.Text = "LOCKED"
			b.TextColor3 = CF.muted
			b.AutoButtonColor = false
		end
	end
	tile.setReady(anyClaimable)
	tile.setBadge(anyClaimable and "dot" or "none")
end

remotes.QuestState.OnClientEvent:Connect(function(quests)
	if typeof(quests) ~= "table" then return end
	render(quests)
end)

btn.MouseButton1Click:Connect(function() panel.Visible = not panel.Visible end)
closeBtn.MouseButton1Click:Connect(function() panel.Visible = false end)
