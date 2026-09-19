-- SUPERSEDED 2026-08-07 and DISABLED. The modern surface is
-- GameHUDPanels.DailyPanel, opened automatically at join by GameHUDClient's
-- join sequence; the Daily rail tile is gone. GameHUDClient already retires
-- this script's DailyUI ScreenGui at runtime, but the script itself kept
-- listening to DailyState and threw on every push once daily rewards became
-- TYPED tables (it formats them as plain numbers). Kept, disabled, for the
-- promo-code box in case that is wanted back somewhere.
-- DailyRewardClient: the Daily button + 30-day login calendar panel + promo code box.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local CF = UITheme.Camp

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
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end
-- remove the heavy black glyph outline so white text actually reads as white
local function stripTextStroke(o)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then s:Destroy() end
	end
end
-- give an element a solid fill (a UIGradient tints the text too, hiding white
-- text against a same-colour button) so its white text renders truly white
local function solidify(o, color)
	local g = o:FindFirstChildOfClass("UIGradient")
	if g then g:Destroy() end
	o.BackgroundColor3 = color
end

local gui = new("ScreenGui", { Name = "DailyUI", ResetOnSpawn = false, DisplayOrder = 9 }, player:WaitForChild("PlayerGui"))

local SideRail = require(ReplicatedStorage.Modules.SideRail)
local tile = SideRail.MakeTile({
	name = "Daily", iconKind = "gift", layoutOrder = 1,
	hueTop = Color3.fromRGB(255, 216, 107), hueBottom = Color3.fromRGB(240, 150, 30),
	accent = Color3.fromRGB(255, 165, 30),
})
local btn = tile.button

local panel = new("Frame", {
	Name = "DailyPanel", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 600, 0, 420), ZIndex = 10,
}, gui)
UITheme.campPanel(panel)
SideRail.registerPanel(panel)   -- only one rail panel open at a time

-- carved-wood banner that overhangs the panel top
local _, dailyTitle = UITheme.ribbon(panel, "DAILY REWARDS", 0.6)
dailyTitle.TextColor3 = Color3.fromRGB(255, 255, 255)

local streakLabel = new("TextLabel", { Position = UDim2.new(0, 0, 0, 42), Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 12 }, panel)
UITheme.inkText(streakLabel, 1.8)

local closeBtn = new("TextButton", {}, panel)
UITheme.styleClose(closeBtn)
closeBtn.ZIndex = 18
closeBtn.TextSize = 18
for _, s in ipairs(closeBtn:GetChildren()) do
	if s:IsA("UIStroke") then s.Color = CF.ink; s.Thickness = 3 end
end
UITheme.inkText(closeBtn, 2.4)

local grid = new("Frame", { Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 570, 0, 214), BackgroundTransparency = 1, ZIndex = 11 }, panel)
new("UIGridLayout", {
	CellSize = UDim2.new(0, 51, 0, 66), CellPadding = UDim2.new(0, 6, 0, 6),
	HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)
-- day-box surface colours per state (gradient top/bot pairs)
local DAY_NEXT_TOP, DAY_NEXT_BOT = Color3.fromRGB(255, 176, 58), Color3.fromRGB(198, 108, 24)
local DAY_DONE_TOP, DAY_DONE_BOT = Color3.fromRGB(58, 76, 50), Color3.fromRGB(34, 48, 31)
local DAY_DONE_TEXT = Color3.fromRGB(122, 178, 128)
-- milestone (day 7/14/21/30) reward boxes glow gold so they read as special
local DAY_MILE_TOP, DAY_MILE_BOT = Color3.fromRGB(150, 104, 40), Color3.fromRGB(92, 60, 22)
-- idle (future, non-milestone) day-box rim: a soft green that blends into the
-- forest-green panel instead of the old brown rim
local DAY_IDLE_BORDER = Color3.fromRGB(52, 74, 54)
local MILESTONES = { [7] = true, [14] = true, [21] = true, [30] = true }
local dayBoxes = {}
for i = 1, 30 do
	local box, outer = UITheme.accentCard(grid, DAY_IDLE_BORDER, 9)
	outer.Name = "Day" .. i
	outer.LayoutOrder = i
	outer.ZIndex = 11
	box.ZIndex = 12
	local strokeO = outer:FindFirstChildOfClass("UIStroke")
	local numL = new("TextLabel", { Position = UDim2.new(0, 0, 0, 4), Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, Text = (MILESTONES[i] and "\u{2B50}" or "") .. i, Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = Color3.fromRGB(255, 255, 255), ZIndex = 13 }, box)
	UITheme.inkText(numL, 2)
	local amountL = new("TextLabel", { Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, 0, 1, -26), BackgroundTransparency = 1, Text = "", Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = Color3.fromRGB(255, 255, 255), TextWrapped = true, ZIndex = 13 }, box)
	UITheme.inkText(amountL, 2)
	dayBoxes[i] = { frame = box, outer = outer, stroke = strokeO, amount = amountL, num = numL }
end

local claimBtn = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -64), Size = UDim2.new(0, 260, 0, 46), Text = "CLAIM", TextSize = 18, ZIndex = 12 }, panel)
UITheme.campButton(claimBtn, CF.pine1, CF.pine2)
stripTextStroke(claimBtn)

-- promo code row
local codeBox = new("TextBox", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, -150, 1, -14), Size = UDim2.new(0, 220, 0, 36),
	BackgroundColor3 = Color3.fromRGB(30, 44, 33), PlaceholderText = "Enter code\u{2026}", Text = "",
	Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = Color3.fromRGB(255, 255, 255),
	PlaceholderColor3 = Color3.fromRGB(255, 255, 255), ClearTextOnFocus = false, BorderSizePixel = 0, ZIndex = 12,
}, panel)
corner(codeBox, 9)
UITheme.ink(codeBox, 3)
stripTextStroke(codeBox)
local codeBtn = new("TextButton", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 80, 1, -14), Size = UDim2.new(0, 110, 0, 36),
	Text = "REDEEM", TextSize = 15, ZIndex = 12,
}, panel)
UITheme.campButton(codeBtn, CF.lake1, CF.lake2)
codeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stripTextStroke(codeBtn)
solidify(codeBtn, CF.lake2)
local codeMsg = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -160, 1, -14), Size = UDim2.new(0, 130, 0, 36),
	BackgroundTransparency = 1, Text = "", Font = Enum.Font.FredokaOne, TextSize = 13,
	TextColor3 = Color3.fromRGB(255, 255, 255), TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = true, ZIndex = 12,
}, panel)
UITheme.inkText(codeMsg, 2)

local state = { Claimable = false, NextDay = 1, Rewards = {}, Streak = 0, FreezeAvailable = false }
local function render()
	local freezeTxt = state.FreezeAvailable and "  \u{2744} streak shield ready" or ""
	streakLabel.Text = "Login streak: " .. state.Streak .. " day" .. (state.Streak == 1 and "" or "s") .. freezeTxt
	local cycleDone = state.Streak > 0 and ((state.Streak - 1) % 30) + 1 or 0
	if state.Claimable then cycleDone = state.NextDay - 1 end
	for i, box in ipairs(dayBoxes) do
		local amt = state.Rewards[i]
		box.amount.Text = amt and ("$" .. fmt(amt)) or ""
		local isNext = (i == state.NextDay)
		local claimed = i <= cycleDone and not isNext
		local mile = MILESTONES[i] and not isNext and not claimed   -- gold future reward day
		box.outer.BackgroundColor3 = isNext and CF.amber1
			or (claimed and CF.pine2 or (mile and CF.amber2 or DAY_IDLE_BORDER))
		box.stroke.Thickness = (isNext or mile) and 3.5 or 2.5
		UITheme.setColors(box.frame,
			isNext and DAY_NEXT_TOP or (claimed and DAY_DONE_TOP or (mile and DAY_MILE_TOP or CF.panelTop)),
			isNext and DAY_NEXT_BOT or (claimed and DAY_DONE_BOT or (mile and DAY_MILE_BOT or CF.panelBot)))
		box.frame.BackgroundTransparency = claimed and 0.12 or 0
		box.num.TextColor3 = Color3.fromRGB(255, 255, 255)
		box.amount.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
	tile.setReady(state.Claimable)
	tile.setBadge(state.Claimable and "dot" or "none")
	claimBtn.Text = state.Claimable and "CLAIM" or "COME BACK TOMORROW"
	local cg = claimBtn:FindFirstChildOfClass("UIGradient")
	if cg then cg:Destroy() end
	claimBtn.BackgroundColor3 = state.Claimable and CF.pine2 or Color3.fromRGB(40, 62, 42)
	claimBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	claimBtn.AutoButtonColor = state.Claimable
end

remotes.DailyState.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	state.Claimable = s.Claimable
	state.NextDay = s.NextDay or 1
	state.Rewards = s.Rewards or state.Rewards
	state.Streak = s.Streak or 0
	state.FreezeAvailable = s.FreezeAvailable == true
	render()
	if s.JustClaimed then
		local extra = s.UsedFreeze and "  \u{2744} streak shield saved your streak!" or ""
		streakLabel.Text = "+ $" .. fmt(s.JustClaimed) .. "  claimed!  (streak " .. state.Streak .. ")" .. extra
	end
end)

remotes.RedeemCode.OnClientEvent:Connect(function(r)
	if typeof(r) ~= "table" then return end
	codeMsg.Text = r.Message or ""
	codeMsg.TextColor3 = Color3.fromRGB(255, 255, 255)
	if r.Success then codeBox.Text = "" end
	task.delay(4, function() codeMsg.Text = "" end)
end)

local function submitCode()
	local code = codeBox.Text
	if #code:gsub("%s", "") == 0 then return end
	remotes.RedeemCode:FireServer(code)
end
codeBtn.MouseButton1Click:Connect(submitCode)
codeBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then submitCode() end
end)

btn.MouseButton1Click:Connect(function() panel.Visible = not panel.Visible; render() end)
closeBtn.MouseButton1Click:Connect(function() panel.Visible = false end)
claimBtn.MouseButton1Click:Connect(function()
	if state.Claimable then remotes.DailyClaim:FireServer() end
end)
