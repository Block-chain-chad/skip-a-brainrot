--!strict
-- Toast -- the ONE notification stack (spec 2026-09-18 UI foundation §6.7). Every
-- toast in the game renders here; ToastClient is remote wiring only. Geometry is
-- ToastClient's measured recipe (2026-08-17): the stack's bottom pinned at
-- (0.5, 0, 0.78, -140) clears the throw cluster at every aspect, lines grow upward,
-- width capped at 640 so phones wrap. Plateless shout text with a dark contextual
-- stroke (PS99 field study delta 9); tone = ink colour per the handoff grammar.
-- Fades are hand-lerped on FxDriver (TweenService cannot animate transparency here).
local Players = game:GetService("Players")
local S = require(script.Parent.SpecTheme)
local FxDriver = require(script.Parent.FxDriver)

export type Props = { text: string, tone: string?, icon: string?, hold: number? }

local MAX_LINES = 3
local HOLD = 3.2
local FADE = 0.3
local FADE_IN = 0.12
local LINE_W, LINE_H = 640, 34
local TONE: { [string]: Color3 } = {
	info = Color3.new(1, 1, 1),
	success = S.Role.Positive[1],
	error = S.Role.Destructive[1],
	reward = S.Role.Gold[1],
}

local Toast = {}

type Entry = { line: TextLabel, stroke: UIStroke, dismissed: boolean, fx: number? }

local host: ScreenGui? = nil
local stack: Frame? = nil
local live: { Entry } = {}
local seq = 0

function Toast.setHost(gui: ScreenGui?)
	host = gui
	stack = nil
end

local function ensureStack(): Frame
	if stack and stack.Parent then return stack :: Frame end
	if not (host and host.Parent) then
		local player = Players.LocalPlayer
		local pg = player and player:FindFirstChildOfClass("PlayerGui")
		local sg = Instance.new("ScreenGui")
		sg.Name = "UIKitToast"
		sg.DisplayOrder = 60
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = false
		sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		sg.Parent = pg
		host = sg
	end
	local st = Instance.new("Frame")
	st.Name = "Stack"
	st.AnchorPoint = Vector2.new(0.5, 1)
	st.Position = UDim2.new(0.5, 0, 0.78, -140)
	st.Size = UDim2.new(1, -32, 0, 0)
	st.BackgroundTransparency = 1
	st.AutomaticSize = Enum.AutomaticSize.Y
	st.Parent = host
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(LINE_W, math.huge)
	cap.Parent = st
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = st
	stack = st
	return st
end

local function lerpAlpha(entry: Entry, from: number, to: number, secs: number, onDone: (() -> ())?)
	if entry.fx then FxDriver.unregister(entry.fx) entry.fx = nil end
	local t0: number? = nil
	local id: number? = nil
	id = FxDriver.register(entry.line, function(t)
		t0 = t0 or t
		local a = math.clamp((t - t0) / secs, 0, 1)
		local v = from + (to - from) * a
		entry.line.TextTransparency = v
		entry.stroke.Transparency = v
		if a >= 1 then
			FxDriver.unregister(id)
			if entry.fx == id then entry.fx = nil end
			if onDone then onDone() end
		end
	end)
	entry.fx = id
	-- a hidden line is skipped by the driver; settle it anyway so nothing lingers
	task.delay(secs + 0.1, function()
		if entry.fx == id then
			FxDriver.unregister(id)
			entry.fx = nil
			entry.line.TextTransparency = to
			entry.stroke.Transparency = to
			if onDone then onDone() end
		end
	end)
end

local function dismiss(entry: Entry, instant: boolean?)
	if entry.dismissed then return end
	entry.dismissed = true
	for i, e in ipairs(live) do
		if e == entry then table.remove(live, i) break end
	end
	if instant or not entry.line.Parent then
		if entry.fx then FxDriver.unregister(entry.fx) entry.fx = nil end
		entry.line:Destroy()
		return
	end
	lerpAlpha(entry, entry.line.TextTransparency, 1, FADE, function()
		entry.line:Destroy()
	end)
end

function Toast.show(props: Props)
	if type(props) ~= "table" or type(props.text) ~= "string" then
		warn(("[UIKit] Toast.show: bad props (%s)"):format(typeof(props)))
		return
	end
	local st = ensureStack()
	while #live >= MAX_LINES do
		dismiss(live[1], true) -- REPLACE, not scroll (PS99 f028/f029)
	end
	seq += 1
	local line = Instance.new("TextLabel")
	line.Name = "Toast" .. seq
	line.Size = UDim2.new(1, 0, 0, LINE_H)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.BackgroundTransparency = 1
	line.BorderSizePixel = 0
	line.Font = S.Font.Shout
	line.TextSize = 26
	line.TextColor3 = TONE[props.tone or "info"] or TONE.info
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.TextTruncate = Enum.TextTruncate.None -- never truncate a message (owner, 2026-08-24)
	line.TextWrapped = true
	line.Text = props.text
	line.LayoutOrder = seq
	line:SetAttribute("NoPolish", true)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = S.Outline
	stroke.Thickness = 2.8
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = line
	line.TextTransparency = 1
	stroke.Transparency = 1
	line.Parent = st
	if props.icon and props.icon ~= "" then
		local ic = Instance.new("ImageLabel")
		ic.Name = "Icon"
		ic.Image = props.icon
		ic.BackgroundTransparency = 1
		ic.ScaleType = Enum.ScaleType.Fit
		ic.AnchorPoint = Vector2.new(1, 0.5)
		ic.Size = UDim2.fromOffset(28, 28)
		ic.Position = UDim2.new(0.5, -8, 0.5, 0)
		ic.Parent = line
		task.defer(function()
			if line.Parent then
				ic.Position = UDim2.new(0.5, -math.ceil(line.TextBounds.X * 0.5) - 8, 0.5, 0)
			end
		end)
	end
	local entry: Entry = { line = line, stroke = stroke, dismissed = false, fx = nil }
	table.insert(live, entry)
	lerpAlpha(entry, 1, 0, FADE_IN)
	task.delay(props.hold or HOLD, function() dismiss(entry) end)
end

function Toast.clear()
	for i = #live, 1, -1 do
		dismiss(live[i], true)
	end
end

function Toast.count(): number
	return #live
end

return Toast
