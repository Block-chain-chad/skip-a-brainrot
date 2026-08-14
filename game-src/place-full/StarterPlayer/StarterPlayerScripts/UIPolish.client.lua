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

OUTLINES ARE ONE-PER-LABEL: we only draw one if nothing else already has. See
the comment at the stroke block below -- adding a second one is what the
"choppy" complaint was actually made of.
========================================================================== ]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 2026-08-04 STYLE REPLACEMENT ("Roblox Simulator UI Style Guide" .docx):
-- GothamBold everywhere. This constant is the REAL font switch for the whole
-- game -- the loop below force-sets the legacy .Font property on every label,
-- which overrides any FontFace a panel sets, so UIKit.Tokens' T.font and this
-- line must always move together (changing Tokens alone is a silent no-op).
-- 2026-08-10 SPEC SWEEP: FredokaOne is the HUD-upgrade sheet's READ face --
-- moved in lockstep with UIKit.Tokens' T.font (see its header; changing one
-- without the other is a silent no-op). Ink follows the sheet's #071323.
local FONT       = Enum.Font.FredokaOne
-- 2026-08-13 LEMONPOP: the DEFAULT ground is now the lemon-cream window, so
-- the default text treatment flips from "white + ink stroke" to the theme's
-- dark UNSTROKED ink (LemonPop rule: dark ink on light surfaces, stroked
-- white type only on dark/saturated ones). Dark surfaces opt IN via the
-- PolishOnDark attribute -- honoured on the label or any ancestor, exactly
-- like NoPolish -- which UIKit.Builders sets centrally on row/track/tab
-- surfaces and action buttons. NoPolish still bypasses everything.
local WHITE      = Color3.fromRGB(255, 255, 255)
local INKTEXT    = Color3.fromRGB(51, 38, 26)  -- LemonPop textOnWindow #33261A, the default fill
local INK        = Color3.fromRGB(36, 31, 20)  -- LemonPop outline #241F14 (was slate #071323), strokes PolishOnDark text
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

-- LemonPop: honours PolishOnDark the same way -- a dark surface tags itself
-- once and every label inside it inherits the on-dark treatment
local function onDark(o)
	local node = o
	while node and node ~= playerGui do
		if node:GetAttribute("PolishOnDark") then return true end
		node = node.Parent
	end
	return false
end

local function strokeFor(o)
	-- 2026-08-10 spec sweep: the cards are LIGHT now, so the white fill only
	-- reads if the ink stroke genuinely carries it -- the old weights were
	-- tuned for white-on-dark, and 14px text at 1.56 ink rendered as a ghost
	-- on the new white detail plates (user capture: the Charm Codex prompt).
	-- Bubble-text weights: text/7, floor 2.2.
	if o.TextScaled then return 2.6 end
	local ts = o.TextSize or 14
	return math.clamp(ts / 7, 2.2, 3.6)
end

-- Any outline that is ALREADY doing this label's job.
--
-- ApplyStrokeMode is the thing that decides: on a text object, Contextual
-- strokes the GLYPHS and Border strokes the rectangle. So a Border stroke on a
-- TextButton is that button's rim and has nothing to do with us, but a
-- Contextual one is a text outline -- somebody else's -- and adding ours next
-- to it means the glyphs carry two.
local function foreignTextStroke(o)
	for _, k in ipairs(o:GetChildren()) do
		if k:IsA("UIStroke")
			and k.Name ~= STROKE_TAG
			and k.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Border
		then
			return k
		end
	end
	return nil
end

local function apply(o)
	if optedOut(o) then return end

	local dark = onDark(o)
	local want = if dark then WHITE else INKTEXT

	if o.Font ~= FONT then o.Font = FONT end
	if o.TextColor3 ~= want then o.TextColor3 = want end

	-- the legacy TextStroke* pair renders muddier than a UIStroke; retire it
	if o.TextStrokeTransparency ~= 1 then o.TextStrokeTransparency = 1 end

	if o:IsA("TextBox") then
		-- LemonPop: boxes sit on light wells, placeholder = warm taupe (was lavender #E1DEEB)
		local ph = Color3.fromRGB(167, 154, 124)
		if o.PlaceholderColor3 ~= ph then o.PlaceholderColor3 = ph end
	end

	-- LemonPop: dark ink on a light ground carries itself -- NO outline. Only
	-- PolishOnDark labels (white type on dark/saturated grounds) keep the
	-- stroked bubble treatment below. Every contextual stroke goes, not just
	-- our own: an unexempted label just had its fill forced to dark ink, so a
	-- leftover glyph outline (UI.label mints one per style spec) would render
	-- dark-on-dark fuzz. Deliberate outlined text belongs under NoPolish.
	if not dark then
		for _, k in ipairs(o:GetChildren()) do
			if k:IsA("UIStroke") and k.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Border then
				k:Destroy()
			end
		end
		return
	end

	-- ONE outline per label. This used to check only for "UIStyleStrokeText",
	-- UIStyle's own named text stroke -- but most panels here never go through
	-- UIStyle.bubbleText, they hang a bare Instance.new("UIStroke") straight off
	-- the label. That is still a text outline, so we cheerfully added a second
	-- one on top at a slightly different weight: a live count found 1032 of 3560
	-- labels carrying two (2.4+2.2, 2.6+1.7, 2.0+1.4 were the common pairs).
	-- Two near-identical outlines do not sit on top of each other cleanly -- they
	-- render as one fat, faintly lumpy edge, which is most of what read as the UI
	-- being "choppy". Whoever drew first owns the outline; they picked its colour
	-- to suit their panel, so leave it be and take ours back out.
	local foreign = foreignTextStroke(o)
	if foreign then
		local mine = o:FindFirstChild(STROKE_TAG)
		if mine then mine:Destroy() end
	else
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
