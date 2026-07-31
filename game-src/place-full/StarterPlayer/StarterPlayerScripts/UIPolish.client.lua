--[[ ==========================================================================
UIPolish -- game-wide typography pass
---------------------------------------------------------------------------
The UI grew across ~24 client scripts, each picking its own font and text
colour: a survey found FOUR fonts in play (GothamMedium 23x, FredokaOne 18x,
GothamBlack 9x, GothamBold 6x) and 63 distinct text colours. That mixture is
what read as "choppy" -- no amount of per-screen tweaking fixes it, because
the next screen re-introduces the drift.

So instead of editing 24 scripts, this one enforces the rule centrally:

	EVERY TextLabel / TextButton / TextBox under PlayerGui gets
	FredokaOne, pure white, and a dark outline so it reads on any
	background.

WHY THE PROPERTY WATCHERS: most UI here is built as
`Instance.new("TextLabel", parent)` and *then* configured, so DescendantAdded
fires BEFORE the owning script assigns its font/colour. Polishing once on add
would simply be overwritten a line later. We therefore also watch FontFace and
TextColor3 per label and re-assert. No infinite loop: we compare before we
write, and assigning an unchanged value raises no signal.

OPTING OUT: set the attribute `NoPolish = true` on a label, or on any ancestor
(useful for a whole panel). Rarity tiers and similar colour-coded text are the
intended users of this escape hatch.
========================================================================== ]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT       = Enum.Font.FredokaOne
local WHITE      = Color3.fromRGB(255, 255, 255)
local INK        = Color3.fromRGB(38, 28, 22)   -- outline that makes white legible
local STROKE_TAG = "UIPolishStroke"

local function isText(o)
	return o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")
end

-- honours NoPolish on the label itself or on anything above it
local function optedOut(o)
	local node = o
	while node and node ~= playerGui do
		if node:GetAttribute("NoPolish") then return true end
		node = node.Parent
	end
	return false
end

local function strokeFor(o)
	if o.TextScaled then return 2.2 end
	local ts = o.TextSize or 14
	return math.clamp(ts / 9, 1.4, 3)
end

local function apply(o)
	if optedOut(o) then return end

	if o.Font ~= FONT then o.Font = FONT end
	if o.TextColor3 ~= WHITE then o.TextColor3 = WHITE end

	-- the legacy TextStroke* pair renders muddier than a UIStroke; retire it
	if o.TextStrokeTransparency ~= 1 then o.TextStrokeTransparency = 1 end

	if o:IsA("TextBox") then
		local ph = Color3.fromRGB(225, 222, 235)
		if o.PlaceholderColor3 ~= ph then o.PlaceholderColor3 = ph end
	end

	-- One outline, ours, named so we never fight another module's UIStroke.
	-- UIStyle already adds "UIStyleStrokeText" to its own labels -- if that is
	-- present we leave it alone rather than double-stroking the glyphs.
	if not o:FindFirstChild("UIStyleStrokeText") then
		local st = o:FindFirstChild(STROKE_TAG)
		if not st then
			st = Instance.new("UIStroke")
			st.Name = STROKE_TAG
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			st.LineJoinMode = Enum.LineJoinMode.Round
			st.Color = INK
			st.Parent = o
		end
		local want = strokeFor(o)
		if math.abs(st.Thickness - want) > 0.05 then st.Thickness = want end
	end
end

local wired = setmetatable({}, { __mode = "k" })   -- weak: destroyed labels drop out

local function watch(o)
	if wired[o] then return end
	wired[o] = true
	apply(o)
	-- re-assert whenever the owning script sets its own font/colour afterwards
	o:GetPropertyChangedSignal("FontFace"):Connect(function() apply(o) end)
	o:GetPropertyChangedSignal("TextColor3"):Connect(function() apply(o) end)
	o:GetPropertyChangedSignal("TextSize"):Connect(function() apply(o) end)
end

for _, d in ipairs(playerGui:GetDescendants()) do
	if isText(d) then watch(d) end
end

playerGui.DescendantAdded:Connect(function(d)
	if isText(d) then
		watch(d)
		-- second pass next frame: catches scripts that parent first and
		-- configure across a yield
		task.defer(function()
			if d.Parent then apply(d) end
		end)
	end
end)
