-- RebirthClient: the Rebirth button + prestige panel (with a wipe confirmation).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function fmt(n)
	n = math.floor(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.0fK", n / 1e3) end
	return tostring(n)
end
local function pct(mult) return ("+%d%%"):format(math.floor((mult - 1) * 100 + 0.5)) end
local function new(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local gui = new("ScreenGui", { Name = "RebirthUI", ResetOnSpawn = false, DisplayOrder = 9 }, player:WaitForChild("PlayerGui"))

local SideRail = require(ReplicatedStorage.Modules.SideRail)
local tile = SideRail.MakeTile({
	name = "Rebirth", iconKind = "star", layoutOrder = 4,
	hueTop = Color3.fromRGB(199, 123, 240), hueBottom = Color3.fromRGB(154, 46, 214),
	accent = Color3.fromRGB(178, 75, 232),
})
local btn = tile.button

local UITheme = require(ReplicatedStorage.Modules.UITheme)
local CF = UITheme.Camp
local FONT = UITheme.Font
local BLACK = Color3.fromRGB(0, 0, 0)

local function blackRim(o, thick)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = BLACK; s.Thickness = thick or 3; s.Transparency = 0
		end
	end
end

-- square icon tile: radial sunburst backdrop + emoji glyph, heavy black rim
local function iconTile(parent, accent, size, pos, glyph)
	local tf = Instance.new("Frame")
	tf.Size = UDim2.fromOffset(size, size)
	tf.Position = pos
	tf.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tf.BorderSizePixel = 0
	tf.ClipsDescendants = true
	tf.ZIndex = (parent.ZIndex or 1) + 1
	tf.Parent = parent
	UITheme.corner(tf, 10)
	UITheme.sunburst(tf, accent, 12)
	UITheme.ink(tf, 3)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = FONT,
		TextSize = math.floor(size * 0.56), Text = glyph, ZIndex = tf.ZIndex + 3,
	}, tf)
	return tf
end

---------------------------------------------------------------- panel (campfire style)
local panel = new("Frame", {
	Name = "RebirthPanel", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(440, 368), ZIndex = 10,
}, gui)
UITheme.campPanel(panel)
SideRail.registerPanel(panel)   -- only one rail panel open at a time
local panelRim = panel:FindFirstChildOfClass("UIStroke")

-- carved-wood banner that overhangs the panel top
UITheme.ribbon(panel, "REBIRTH", 0.6)
local closeBtn = new("TextButton", {}, panel)
UITheme.styleClose(closeBtn)
closeBtn.ZIndex = 20
closeBtn.TextSize = 18
blackRim(closeBtn, 3)

---------------------------------------------------------------- current standing strip
local strip, stripOuter = UITheme.accentCard(panel, CF.berry1, 12)
stripOuter.Position = UDim2.new(0, 21, 0, 48)
stripOuter.Size = UDim2.fromOffset(398, 58)
stripOuter.ZIndex = 11
strip.ZIndex = 12
iconTile(strip, CF.berry1, 40, UDim2.new(0, 7, 0, 5), "\u{2B50}")

local stripTitle = new("TextLabel", {
	Position = UDim2.new(0, 56, 0, 5), Size = UDim2.new(1, -66, 0, 16), BackgroundTransparency = 1,
	Text = "REBIRTHS", Font = FONT, TextSize = 14, TextColor3 = CF.berry1,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = strip.ZIndex + 2,
}, strip)
UITheme.inkText(stripTitle, 2.4)

local curLabel = new("TextLabel", {
	Position = UDim2.new(0, 56, 0, 23), Size = UDim2.new(1, -66, 0, 24), BackgroundTransparency = 1,
	Text = "", Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = CF.cream,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = strip.ZIndex + 2,
}, strip)
UITheme.inkText(curLabel, 2)

---------------------------------------------------------------- stat readouts
-- one accent per card, carried through the border, the title colour and the sunburst
local function statCard(x, accent, glyph, titleText, subText)
	local card, outer = UITheme.accentCard(panel, accent, 12)
	outer.Position = UDim2.new(0, x, 0, 118)
	outer.Size = UDim2.fromOffset(126, 112)
	outer.ZIndex = 11
	card.ZIndex = 12
	iconTile(card, accent, 44, UDim2.new(0.5, -22, 0, 6), glyph)

	local t = new("TextLabel", {
		Position = UDim2.new(0, 4, 0, 54), Size = UDim2.new(1, -8, 0, 15), BackgroundTransparency = 1,
		Text = titleText, Font = FONT, TextSize = 13, TextColor3 = accent, ZIndex = card.ZIndex + 2,
	}, card)
	UITheme.inkText(t, 2.2)

	local v = new("TextLabel", {
		Position = UDim2.new(0, 4, 0, 69), Size = UDim2.new(1, -8, 0, 22), BackgroundTransparency = 1,
		Text = "", Font = FONT, TextSize = 19, TextColor3 = CF.cream, ZIndex = card.ZIndex + 2,
	}, card)
	UITheme.inkText(v, 2.6)

	local s = new("TextLabel", {
		Position = UDim2.new(0, 4, 0, 89), Size = UDim2.new(1, -8, 0, 14), BackgroundTransparency = 1,
		Text = subText or "", Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = CF.muted,
		ZIndex = card.ZIndex + 2,
	}, card)
	UITheme.inkText(s, 1.6)
	return v, s
end

local costLabel = statCard(21, CF.amber1, "\u{1F4B0}", "COST", "cash needed")
local incLabel, incSub = statCard(157, CF.pine1, "\u{1F4C8}", "INCOME", "")
local luckLabel, luckSub = statCard(293, CF.lake1, "\u{1F340}", "LUCK", "")

---------------------------------------------------------------- danger strip + action
local warnCard, warnOuter = UITheme.accentCard(panel, CF.ember1, 10)
warnOuter.Position = UDim2.new(0, 21, 0, 242)
warnOuter.Size = UDim2.fromOffset(398, 46)
warnOuter.ZIndex = 11
warnCard.ZIndex = 12
local warnLabel = new("TextLabel", {
	Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -20, 1, 0), BackgroundTransparency = 1,
	Text = "\u{26A0}\u{FE0F} Resets your cash & rocks (back to Pebble) \u{2014} brainrots stay", Font = Enum.Font.GothamMedium,
	TextSize = 13, TextColor3 = CF.muted, TextWrapped = true, ZIndex = warnCard.ZIndex + 2,
}, warnCard)
UITheme.inkText(warnLabel, 1.8)

local rebirthBtn = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(380, 52),
	Text = "REBIRTH", TextSize = 22, ZIndex = 12,
}, panel)
UITheme.campButton(rebirthBtn, CF.amber1, CF.amber2)

local state = {}
local confirming = false
local confirmToken = 0
local function render()
	curLabel.Text = ("%d   \u{2022}   now %s income / %s luck"):format(state.Rebirths or 0, pct(state.IncomeMult or 1), pct(state.LuckMult or 1))
	costLabel.Text = "$" .. fmt(state.Cost or 0)
	incLabel.Text = pct(state.NextIncomeMult or 1)
	incSub.Text = "now " .. pct(state.IncomeMult or 1)
	luckLabel.Text = pct(state.NextLuckMult or 1)
	luckSub.Text = "now " .. pct(state.LuckMult or 1)
	tile.setReady(state.CanAfford == true)
	tile.setBadge(state.CanAfford and "alert" or "none")
	if confirming then
		-- destructive step: ember button, ember danger strip, ember panel rim
		rebirthBtn.Text = "CONFIRM \u{2014} WIPES PROGRESS"
		rebirthBtn.TextSize = 20
		UITheme.setColors(rebirthBtn, CF.ember1, CF.ember2)
		warnOuter.BackgroundColor3 = CF.ember1
		UITheme.setColors(warnCard, Color3.fromRGB(128, 44, 26), Color3.fromRGB(74, 24, 15))
		warnLabel.Font = FONT
		warnLabel.TextSize = 15
		warnLabel.TextColor3 = CF.ember1
		warnLabel.Text = "\u{1F525} WIPES YOUR CASH & ROCKS \u{2014} BRAINROTS STAY \u{1F525}"
		if panelRim then panelRim.Color = CF.ember2; panelRim.Thickness = 5 end
	else
		rebirthBtn.TextSize = 22
		warnOuter.BackgroundColor3 = CF.wood1
		UITheme.setColors(warnCard, CF.cardTop, CF.cardBot)
		warnLabel.Font = Enum.Font.GothamMedium
		warnLabel.TextSize = 13
		warnLabel.TextColor3 = CF.muted
		warnLabel.Text = "\u{26A0}\u{FE0F} Resets your cash & rocks (back to Pebble) \u{2014} brainrots stay"
		if panelRim then panelRim.Color = CF.ink; panelRim.Thickness = 4 end
		if state.CanAfford then
			rebirthBtn.Text = "REBIRTH"
			UITheme.setColors(rebirthBtn, CF.amber1, CF.amber2)
		else
			rebirthBtn.Text = "NEED $" .. fmt(state.Cost or 0)
			UITheme.setColors(rebirthBtn, CF.panelTop, CF.panelBot)
		end
	end
	rebirthBtn.AutoButtonColor = state.CanAfford == true
end

remotes.RebirthState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	state = s
	confirming = false
	render()
end)

btn.MouseButton1Click:Connect(function() panel.Visible = not panel.Visible; confirming = false; render() end)
closeBtn.MouseButton1Click:Connect(function() panel.Visible = false; confirming = false end)
rebirthBtn.MouseButton1Click:Connect(function()
	if not state.CanAfford then return end
	if not confirming then
		confirming = true
		render()
		confirmToken += 1
		local myToken = confirmToken
		task.delay(3, function() if myToken == confirmToken then confirming = false; render() end end)
	else
		confirming = false
		remotes.RebirthRequest:FireServer()
	end
end)
