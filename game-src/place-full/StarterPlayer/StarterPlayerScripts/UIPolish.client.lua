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
-- 2026-08-14 READABILITY REVERT (owner: "change all text to white so its
-- readable, right now its hard to read things"). The 2026-08-13 LemonPop pass
-- flipped the default from "white + ink stroke" to dark UNSTROKED ink on the
-- assumption that dark ink on a lemon-cream ground carries itself. In practice
-- it did not -- and because that branch also DESTROYED every contextual stroke,
-- there was no outline left to rescue it.
--
-- The rule is back to what this module's header always described: white fill +
-- dark outline on EVERY unexempted label, which is legible on light cream, on
-- the dark rows, and on the red headers alike -- one treatment, no per-surface
-- bookkeeping. PolishOnDark is no longer read here -- UIKit.Builders may go on
-- setting it harmlessly, but there is only ONE treatment now, so the reader was
-- deleted rather than left as dead code. NoPolish still bypasses everything, so
-- colour-coded text (rarity tiers, emoji) is untouched.
local WHITE      = Color3.fromRGB(255, 255, 255)
local INK        = Color3.fromRGB(49, 61, 79)  -- PS99 cool navy #313D4F (was LemonPop #241F14); strokes every polished label -- moves in lockstep with UIKit.Tokens outline
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

-- EMOJI TEST (kept from the original floor). A 4-byte UTF-8 lead byte is every
-- modern emoji (U+1F300 and up), while the 3-byte bullets and middots that
-- ordinary labels are full of still pass through. A UIStroke on a colour glyph
-- renders as a smear, so an emoji label is never recoloured or outlined.
local function hasEmoji(s)
	return typeof(s) == "string" and s:find("[\240-\244]") ~= nil
end

local function apply(o)
	local exempt = optedOut(o)

	-- READABILITY FLOOR (2026-08-14, same owner note as the revert above).
	-- NoPolish still means "do not restyle me" -- an exempt label keeps its own
	-- font, size and colour. What it must NOT mean any more is "stay
	-- unreadable": a survey of the live UI found 48 opted-out labels sitting at
	-- LemonPop's dark inks (#33261A, #7A6A52, #4A2E00...) on light cream cards
	-- with no outline at all -- 39 of them in the egg shop alone. So an exempt
	-- label whose fill is DARK gets the same white + ink outline as everything
	-- else, and an exempt label that is already light is left completely alone
	-- (that is what protects deliberately colour-coded text: rarity tiers and
	-- the like are bright, so they never reach this branch).
	--
	-- EMOJI ARE SKIPPED OUTRIGHT. PassPanel tags its glyphs NoPolish with the
	-- note "emoji must not be recoloured/outlined", and it is right -- a stroke
	-- on a colour glyph renders as a smear. The test is a 4-byte UTF-8 lead
	-- byte (\240-\244), which is every modern emoji (U+1F300 and up) while
	-- still letting through the 3-byte bullets and middots that ordinary
	-- labels are full of.
	-- 2026-08-16 PS99 RESTYLE: the readability floor above is RETIRED -- exempt
	-- means exempt again. The floor existed because LemonPop's dark inks sat
	-- strokeless on mid-value cream/gold grounds; the PS99 theme's light
	-- surfaces are true white/near-white, where solid dark ink (#33414F) is the
	-- MOST readable treatment -- and force-whitening it would white-out every
	-- deliberate dark label on the new white panels. Unexempted labels keep the
	-- white + ink-stroke bubble treatment for dark rows and saturated fills.
	--
	-- 2026-08-21 THE FLOOR IS BACK (owner: "the text in the bag is grey again
	-- make it white like i told u too earlier"). Retiring it turned `exempt` into
	-- a hard return, and the BAG is the panel that shows why that was wrong:
	-- BackpackPanel opts 47 labels out for the express purpose of keeping muted
	-- ink on its pale grounds (its own comment: "NoPolish so UIPolish cannot force
	-- it back to white"), so every one of them went grey the moment this returned
	-- early. No amount of editing that panel fixes it while this line stands.
	--
	-- The 08-16 objection was correct as far as it went -- a blanket whitening
	-- also wipes deliberate colour-coded dark text -- so the floor returns with the
	-- guard it never had: SATURATION, not value alone. A neutral ink is chrome and
	-- gets rescued; a saturated fill is somebody's colour CODE and is left alone.
	--   whiten  #7C8CA0 S.23  #33414F S.35  #5D6B7A S.24  #8B93A8 S.17  #6B7689 S.22
	--   keep    #3E8E1F S.78  #06301B S.88  #3A2A05 S.91  #E0424F S.71  #12060C S.67
	-- Measured off the live bag, those two groups sit either side of a 0.35 -> 0.67
	-- gap, so the 0.50 line is nowhere near anything it has to judge. The V < 0.75
	-- half keeps already-light text (textMutedOnDark #DCE6F2, plain white) untouched:
	-- it needs no rescue, and restroking it would only add weight.
	--
	-- An exempt label that DOES fall through keeps its own font and size -- it gets
	-- the white fill and the ink outline, nothing else. That is the whole point of
	-- the escape hatch surviving alongside the floor.
	if exempt then
		if hasEmoji(o.Text) then return end
		local _, sat, val = o.TextColor3:ToHSV()
		if sat >= 0.50 or val >= 0.75 then return end
	end

	-- every polished label is white now, on any ground -- the outline below is
	-- what makes that safe (see the READABILITY REVERT note at the top)
	if not exempt and o.Font ~= FONT then o.Font = FONT end
	if o.TextColor3 ~= WHITE then o.TextColor3 = WHITE end

	-- the legacy TextStroke* pair renders muddier than a UIStroke; retire it
	if o.TextStrokeTransparency ~= 1 then o.TextStrokeTransparency = 1 end

	if not exempt and o:IsA("TextBox") then
		-- PS99: boxes sit on light wells, placeholder = cool grey-blue (was warm taupe #A79A7C)
		local ph = Color3.fromRGB(169, 182, 198)
		if o.PlaceholderColor3 ~= ph then o.PlaceholderColor3 = ph end
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
		-- AN OUTLINE THE COLOUR OF THE FILL IS NOT AN OUTLINE (2026-08-21).
		-- The PS99 tiles draw dark ink with a WHITE HALO -- exactly right for dark
		-- type, and completely useless the moment the floor above turns that type
		-- white. Restoring the floor without this left 66 labels as white glyphs
		-- with a white halo on a white panel: the bag's header counter and every
		-- pet tile name, invisible rather than merely low-contrast, and a contrast
		-- audit still PASSES them because it can see an outline is present.
		--
		-- Whoever drew first still owns the outline -- the one-stroke-per-label rule
		-- below is untouched. We correct only its COLOUR, and only when it has
		-- stopped separating the glyphs from anything: light stroke under light fill.
		local _, fillSat, fillVal = o.TextColor3:ToHSV()
		local _, strokeSat, strokeVal = foreign.Color:ToHSV()
		if fillVal >= 0.9 and fillSat < 0.2
			and strokeVal >= 0.75 and strokeSat < 0.5
			and foreign.Color ~= INK
		then
			foreign.Color = INK
		end
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
	elseif d:IsA("UIStroke") and d.Parent and isText(d.Parent) then
		-- A STROKE ARRIVING AFTER ITS LABEL is the normal order here: panels do
		-- Instance.new("TextLabel") first and hang the outline off it a few lines
		-- later, which is AFTER both passes above have already run. Nothing in the
		-- property watchers fires for a new child, so without this the fill-coloured
		-- halo correction in apply() would simply never see the stroke it exists to
		-- fix -- and it would fail silently, on exactly the tiles that need it.
		local label = d.Parent
		task.defer(function()
			if label.Parent and d.Parent == label then apply(label) end
		end)
	end
end)
