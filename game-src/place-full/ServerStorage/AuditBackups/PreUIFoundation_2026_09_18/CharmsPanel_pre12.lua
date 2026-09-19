--!strict
--[[ ==========================================================================
CharmsPanel -- the CHARM CODEX shell. GameHUDPanels consumer module
(StarterPlayer.StarterPlayerScripts.GameHUDPanels.CharmsPanel).

Tasks 2 + 3 + 4 of 5. Task 2 built the shell: window, header, stacking-rule
box, slot row and the two columns. Task 3 filled LeftColumn with the filter
tab row and the data-driven charm grid. Task 4 filled RightColumn with the
detail column -- sigil figure, tag row, identity block, the GAIN / TRADE /
CONFIG / SOURCE / HOOK rows, the note box and the EQUIP call to action.
Task 5 only wires the Bag entry point.
---------------------------------------------------------------------------
THE EQUIP BUTTON IS DELIBERATELY UNWIRED. LEAVE IT THAT WAY UNTIL A CHARM
SYSTEM EXISTS.

There is no ownership, no equipping, no server resolution, no save data and
no remote anywhere in this game for charms -- CharmConfig's own header says
so in capitals. The button renders, it is harmless to press, and it answers
with a toast. That is EXACTLY the precedent EggShopClient's BUY EMERALDS
button set on 2026-08-06, and for the same stated reason: an unwired button
that also fails SILENTLY is indistinguishable from a broken one during QA.

So if you are reading this because the button "does nothing": it is doing
precisely what it was built to do. When equipping exists, replace the toast
handler in buildDetailColumn with the real call. Do not delete the button,
and do not make it silent.

A LOCKED charm's EQUIP is DISABLED rather than merely inert -- a different
state, drawn with the kit's own "disabled" button variant (no hover, no
click sound, no handler at all), because "not yet earnable" and "not yet
built" must not look the same.
---------------------------------------------------------------------------
CONTRACT (identical to every other panel in this family -- see GoalsPanel /
SettingsPanel, and the header of GameHUDClient which defines it):

    return { Id = "charms", Build = function(ctx) -> Frame }

Build is called ONCE, lazily, on first open. The shell (GameHUDClient) parents
the returned Frame into ctx.host, adds the open/close UIScale and owns Visible
from then on. This module never sets its own Parent, never toggles its own
Visible, and never drives its own open/close animation.

A module in this folder with no Build/Id, or whose require() errors, is
SKIPPED SILENTLY at startup -- it does not warn, it simply never registers.

---------------------------------------------------------------------------
THE pcall TRAP -- read before adding anything to Build

GameHUDClient.openPanel wraps Build in a pcall:

    local ok, built = pcall(mod.Build, ctx)
    if not ok or typeof(built) ~= "Instance" then return end

So a Build that throws does NOT surface an error to the player. It returns
early, AFTER openPanel has already played the open sound and hidden every
other panel, but BEFORE it sets host.Visible / shows the scrim. Two different
things the player sees, both bad, neither of them an error message:

  * nothing was open  -> the click is a dead no-op. Sound plays, no panel.
  * something WAS open -> that panel is hidden and nothing replaces it, while
    host and the scrim stay up from the previous open: a dimmed screen with
    an empty panel area and no X to click. ESC is the only way out.

That second case is how a stray black rectangle shipped here before. Two
rules follow, and both are load-bearing:

  1. NEVER parent anything into ctx.host from inside Build. Build the whole
     tree detached and return the root -- then a throw halfway through leaves
     nothing orphaned on screen. (This is also why `wrapper` below has no
     Parent line.)
  2. Anything that could throw per-charm (a nil field, a bad id, a missing
     asset) belongs in its own pcall inside the loop, so one bad roster entry
     costs one tile instead of the whole panel.

---------------------------------------------------------------------------
EVERYTHING RENDERS FROM CharmConfig

The roster is placeholder and the user will replace it. There is no charm
name, no roster count, no slot count, no label and no derived number written
into this file. Counts come from `#CharmConfig.Slots`, chrome strings from
`CharmConfig.Display`, composed lines from the helpers (KickerLine,
LoadoutLine). CharmConfig's helpers read their tables at CALL time, so a
roster swap propagates without touching this file.

SIX exceptions, documented rather than hidden. Every one of them is chrome
CharmConfig.Display has no key for; NONE of them is a charm name, a count or
a derived number. If Display ever grows the keys, each is a single call site.

  1. the slot card's eyebrow reads `("SLOT %02d"):format(slot.Index)`. The
     NUMBER is data; the word "SLOT" is the only piece of chrome the video
     shows that CharmConfig.Display has no key for. If a Display.SlotPrefix is
     ever added, this is the single call site.
  2. ALL_KEY = "ALL" below. That string is CharmConfig.Filter's own sentinel
     for "everything", not a category name, and it is used only as a FALLBACK
     -- CharmConfig ships an ALL pseudo-category and the tab row uses that
     entry when it is present.
  3. EQUIP_FMT = "EQUIP TO SLOT %02d". Same SLOT prefix as (1); the number is
     slot.Index, chosen by equipTargetIndex().
  4. ID_LINE_FMT -- the connective `\u{00B7} was \u{201C}%s\u{201D}` under the
     charm name. Both operands (Id, WasCalled) are data; the word "was" is
     not. Format transcribed from the design video.
  5. EMPTY_PROMPT -- the empty-state line, shown when nothing is selected.
     The video never shows an unselected column, so this line is ours.
  6. EQUIP_TOAST -- what the inert EQUIP button says. Deliberately phrased
     like EggShopClient's "Emerald packs are coming soon!", so the two unwired
     controls in this game answer in the same voice.

NOT an exception, but worth the same warning: the sigil figure's caption is
charm.Id. The design video captions that plate with a MOCK ASSET FILENAME
("GOLDEN_YOLK_SIGIL.PNG"). That was NOT reproduced, for two reasons: it is
the same Industry motif family as the striped plate the user rejected, and
no such file exists -- the sigils are drawn from GUI primitives with no
asset id at all (see drawSigil), so printing a filename would send the next
reader looking for art that was never uploaded.

---------------------------------------------------------------------------
TREE AS BUILT -- the names Tasks 3-5 need

  CharmsPanel                (returned Frame, scale 1x1, NoPolish=true)
    HardShadow               (UI.panel's sibling shadow -- see trap 2 below)
    PanelWindow              (UI.panel, 1120x700, centred, 16px UIPadding)
      Header                 (red bar, full inner width x 92)
        HardShadow
        Kicker               CharmConfig.KickerLine()
        Title                CharmConfig.Display.Title
        LoadoutLabel         CharmConfig.Display.LoadoutLabel
        LoadoutValue         CharmConfig.LoadoutLine()
        CloseButton          44x44, calls ctx.closePanel()
          HardShadow
      StackingRule           dark slot, pinned top-RIGHT of the body
        HardShadow
        Label / Formula / Note   verbatim Display.Stacking*
      SlotRow                transparent, horizontal UIListLayout
        Slot<n>              plain wrapper frame == the list item
          Card               dark slot ("track" gradient when Locked)
            HardShadow
            Eyebrow / Occupant / Unlock
      LeftColumn             Task 3 -- filter tabs + charm grid (~55%)
        TabRow               transparent; tabs are POSITIONED, not laid out
          HardShadow         one per tab (safe: no layout in this container)
          Tab<KEY>           one per CharmConfig.Categories entry, ALL first
            Label / ActiveRing / Hit
          ShownStatus        CharmConfig.ShownLine(), right-aligned
        Grid                 ScrollingFrame + UIGridLayout, canvas from rows
          Cell_<CHARM_ID>    plain wrapper frame == the grid item (trap 2)
            HardShadow
            Card             BOXED plate ("track" when Locked, else "slot")
                             ROUND-6 RULING: charm cards STAY BOXED -- they
                             are dense text surfaces and clickable state
                             tiles, and PS99's own enchant lists are boxed
                             rows. The 2026-08-18 splash de-box was applied
                             in error over that ruling and has been
                             reverted; do not de-box these again.
              Sigil          drawn from charm.Sigil
              CharmName / Effect / SelectedRing / Hit
      RightColumn            Task 4 -- the detail column (~45%)
        HardShadow           sibling of Detail (safe: no layout in this frame)
        Detail               dark slot; the whole reading area
          Body               ScrollingFrame; children POSITIONED, not laid out
            FigureSlot       plain wrapper == the shadow's container (trap 2)
              HardShadow
              Figure         darker `track` plate
                Sigil        rebuilt per selection from charm.Sigil
                Caption      charm.Id -- see the note under the exceptions
            TagRow           CategoryTag + State + Index (all POSITIONED)
              CategoryTag / HardShadow / State / Index
            CharmName / IdLine / Flavour
            Row_Gain / Row_Trade / Row_Config / Row_Source / Row_Hook
              Label / Value ( + Proposed, on Row_Trade only)
            NoteSlot         plain wrapper; hidden whole when Note is nil
              HardShadow
              NoteBox        accent-stroked `track` + Bullet + Text
          Empty              the empty state; sibling of Body
        EquipSlot            plain wrapper; holds BOTH buttons and the shadow
          Equip / HardShadow / EquipLocked

Local names inside Build, which Tasks 3-5 extend rather than rebuild:
  wrapper, panelWindow, header, closeBtn, stackBox, slotRow, slotCards,
  leftColumn, rightColumn, charmGrid, showToast, charmDetail
and the geometry block PANEL_W / PANEL_H / PAD / GAP / HEADER_H / INNER_W /
INNER_H / BODY_TOP / ROW_H / STACK_W / SLOTROW_W / COL_TOP / COL_H /
LEFT_W / RIGHT_W.

`slotCards[i]` is the per-slot Card frame, kept so Task 5 can repaint an
occupant without re-walking the tree.

`ctx.state.charms` is created here (empty) so Tasks 3-5 have a stable place
for filter / selection state -- GameHUDClient's `state` table predates this
panel and has no charms key of its own.

---------------------------------------------------------------------------
TASK 3 -> TASK 4 CONTRACT

Published on ctx.state.charms by Build, and returned by buildCharmGrid as the
local `charmGrid`. Both routes hand back the SAME table, so Task 4 can take
whichever is closer to hand.

  charms.cards[charmId] = {
      root   = the grid CELL frame -- the UIGridLayout item. Its Visible IS
               the filter flag: false means the active filter hides it.
      sigil  = the Sigil frame inside the card
      ring   = the accent selection ring
      card   = the card plate (BOXED -- round-6 ruling, see the tree above)
      name / effect = the two labels        hit  = the click target
      charm  = the CharmConfig entry        locked = charm.Locked == true
      shown  = mirror of root.Visible
  }
  charms.setSelected(id: string?) -> boolean
      Drives the ring, exactly one card at a time. Returns FALSE and changes
      NOTHING for an unknown id, a LOCKED charm, or a charm the active filter
      is hiding. setSelected(nil) always succeeds and clears.
  charms.setFilter(key: string) -> boolean   (false for a key with no tab)
  charms.getSelected() / charms.getFilter()
  charms.metrics() -> { columns, rows, cellW, cellH, gap, shown, total,
                        canvasH, viewportH, usableW, filter }
      Every field SOLVED at build/filter time. Nothing in it is a constant.
  charms.drawSigil(ctx, parent, kind, size, zIndex, color) -> Frame
      The glyph function the cards use, so the detail column can render a big
      sigil without a second implementation.
  charms.onSelect = function(charm, id) ... end
      Assign it. The grid pcalls it on every selection CHANGE, with (nil, nil)
      on a clear. It is never called for a refused selection.

---------------------------------------------------------------------------
TASK 4 -> TASK 5 CONTRACT

Task 4 CONSUMES the above: it assigns charms.onSelect and does nothing else
to the grid. It publishes one more entry on ctx.state.charms:

  charms.detail.render(charm: Charm?)  -- repaint the column; nil = empty state
  charms.detail.root / body / equip / equipLocked / rows / metrics()
  charms.detail.metrics() -> { contentH, viewH, scrolls, labelW, valueW,
                               rowsShown, equipSlot, ... }  all SOLVED

render() is idempotent and rebuilds NO instance except the sigil glyph (whose
shape depends on the charm), so selecting all 16 charms in a row leaves the
descendant count exactly where it started. Task 5 does not need any of this;
it is here so the column can be driven and measured without a mouse.

THE ONE THING TASK 5 MUST NOT UNDO: showToast's pill and EVERY hard shadow in
this column are hidden by hiding their WRAPPER, never by hiding the surface
and leaving the shadow up. UI.hardShadow does not mirror Visible -- an
orphaned shadow is a solid #202020 rectangle floating over the UI, which is
how a "big black square" shipped here once already.

---------------------------------------------------------------------------
STYLE -- Pet-Sim HUD only (standing user ruling from the egg shop rebuild)

Window T.gradient.panel, ONE red header bar (T.gradient.header), dark slots
T.gradient.slot, T.font.display, radius 8, stroke 4, padding 16. EVERY
Industry motif from the design video is deliberately dropped: no square
corners, no 1px hairlines, no blueprint "+" registration marks, no striped
plates. Do not reintroduce them in Tasks 3-5.

Note this panel constructs its header with UI.surface(..., "header", ...)
directly. The older panels seed "gold" and then swap the UIGradient in place;
that was a migration artifact -- T.gradient.header exists, so there is nothing
to swap.

---------------------------------------------------------------------------
TRAPS ALREADY PAID FOR IN THIS PROJECT -- all four apply to Tasks 3-5 too

  1. UIPolish force-whitens every TextLabel under PlayerGui and RE-ASSERTS on
     TextColor3 change, on a deferred second pass. ONE NoPolish attribute on
     the ROOT, set before a single label exists, covers every descendant --
     UIPolish walks ancestors. Do not remove it; the muted / disabled text
     below is coloured and would go white.
  2. UI.button and UI.panel parent their hard shadow as a SIBLING of the
     control, into the control's own parent. A control dropped straight into
     a UIListLayout/UIGridLayout therefore turns its shadow into a phantom
     cell. Every slot card here sits in its own plain wrapper Frame, and the
     wrapper is the list item. Task 3's grid must do the same.
  3. Layouts own their children's Position -- wrap anything you animate.
  4. `x and nil or y` is always y in Lua. The locked-slot branch below uses
     an if-else expression for exactly this reason.

Luau allows 200 locals per function. This file is a thin assembler on
purpose: the two builders are module-level functions, and Build itself holds
around 35 locals. Tasks 3 and 4 add substantially more -- put the grid and
the detail column in their OWN module-level functions rather than inlining
them into Build, or the ceiling that bit the egg shop rebuild comes back.
========================================================================== ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local modules = ReplicatedStorage:WaitForChild("Modules")

-- 2026-08-11 spec restyle: the filter chips take the HUD-upgrade sheet's
-- gold-active / neutral-rest treatment (same as the Bag's chips), so the
-- embedded Codex reads as one system with the tab body around it.
local SpecS = require(modules:WaitForChild("UIKit"):WaitForChild("SpecTheme"))

-- Task 1's data contract. See the block above: nothing this panel shows is
-- authored here. A failure to load is warned about rather than swallowed,
-- because GameHUDClient's registration pcall would otherwise drop this whole
-- panel without a word.
local okConfig, CharmConfig = pcall(function()
	return require(modules:WaitForChild("CharmConfig", 10))
end)
if not okConfig then
	warn("[CharmsPanel] CharmConfig failed to load -- panel will not register: " .. tostring(CharmConfig))
	CharmConfig = nil
end

local CharmsPanel = { Id = "charms" }

local TextService = game:GetService("TextService")

-- CharmConfig.Filter's sentinel for "everything". See the TWO EXCEPTIONS note
-- in the header: this is a fallback only.
local ALL_KEY = "ALL"

---------------------------------------------------------------- grid inputs
-- NONE of these is a grid dimension, and that distinction is the whole point
-- of Task 3. They are the INPUTS the layout is SOLVED from: a minimum legible
-- card width and the paddings. COLUMNS come out of the width actually
-- available and CARD_MIN_W. ROWS are math.ceil(shown / columns). The scroll
-- canvas follows the rows. Replace CharmConfig.Charms with 8 entries or 24 and
-- all three re-solve with no edit here.
--
-- If you ever find yourself typing a column count, a roster size or a
-- combination count into this file, the number belongs in CharmConfig and you
-- should reach it through one of its helpers instead.
local CARD_MIN_W = 132   -- narrowest card that still holds an effect label + padding
local CARD_PAD = 10
local SIGIL_SIZE = 26
local SIGIL_STROKE = 3
local SIGIL_GAP = 8
local NAME_LINES = 2     -- names are author-supplied; two lines absorbs a long one
local NAME_GAP = 4
local TAB_PAD_X = 10
local TAB_PAD_Y = 6
local TAB_GAP = 8
local SCROLL_W = 5                    -- ScrollBarThickness (2026-08-17: soft thin thumb, house-wide)
local SCROLL_RESERVE = SCROLL_W + 2   -- gutter, so the thumb never sits on a card

------------------------------------------------------- detail column inputs
-- Same rule as the grid inputs above, and for the same reason: NOT ONE OF
-- THESE IS A HEIGHT. They are paddings, glyph sizes and gaps. Every block in
-- the detail column is SOLVED from the charm's own text through wrapHeight()
-- below, so a longer Gain, a three-line Flavour or a 300-character Note grows
-- its own block instead of clipping -- which matters more here than anywhere
-- else in the panel, because the detail column is nothing BUT author copy and
-- the copy is placeholder. Nothing here knows how many rows there are.
local DET_PAD = 12           -- inset from the detail surface's edge
local DET_GAP = 10           -- between blocks
local FIG_SIGIL = 56         -- the big sigil, ~2x the grid card's
local FIG_PAD = 10
local FIG_CAPTION_GAP = 6
local DET_TAG_PAD_X = 10
local DET_TAG_PAD_Y = 4
local DET_TAG_GAP = 8
local ROW_PAD_Y = 5          -- above and below each spec row's tallest line
local ROW_LABEL_GAP = 14     -- between the label column and the value column
local NOTE_PAD = 12
local NOTE_BULLET = 10
local NOTE_BULLET_GAP = 10
local EQUIP_H = 46
local TOAST_W, TOAST_H, TOAST_Y = 460, 54, 132
local TOAST_HOLD = 2.6       -- ToastClient's own HOLD, so the two agree

-- The five chrome strings this file owns. See the SIX EXCEPTIONS block in the
-- header before adding a sixth -- each of these is chrome CharmConfig.Display
-- has no key for, and none is a name, a count or a derived number.
local EQUIP_FMT = "EQUIP TO SLOT %02d"
local ID_LINE_FMT = "%s \u{00B7} was \u{201C}%s\u{201D}"
local EMPTY_PROMPT = "Select a charm on the left."
local EQUIP_TOAST = "Charm slots are coming soon!"

-- Comfortable leading for wrapped body copy. Roblox advances exactly TextSize
-- per line by default, which is unreadably tight for the Flavour / Gain / Note
-- paragraphs; lineH() already assumes 1.25, so this is what makes the measured
-- height and the rendered height the same number. pcall'd because a property
-- that does not exist would throw INSIDE Build, and a Build that throws costs
-- the whole panel (see the pcall trap in the header). If it ever fails the
-- text renders TIGHTER than the space reserved for it -- slack, never a clip.
local LINE_HEIGHT = 1.25
local function setLeading(label: TextLabel)
	pcall(function() label.LineHeight = LINE_HEIGHT end)
end

-- One rendered line of `textSize` type. Used so the card height comes out of
-- T.text rather than being measured off a screenshot.
local function lineH(textSize: number): number
	return math.ceil(textSize * 1.25)
end

-- Card geometry, derived from the type tokens. Two callers (the grid solves the
-- cell height, the card lays itself out inside that cell), so it lives in one
-- place and cannot drift.
local function cardMetrics(T)
	local nameH = lineH(T.text.cardLabel[1]) * NAME_LINES
	local effectH = lineH(T.text.chip[1])
	return {
		pad = CARD_PAD,
		sigil = SIGIL_SIZE,
		sigilGap = SIGIL_GAP,
		nameH = nameH,
		nameGap = NAME_GAP,
		effectH = effectH,
		height = CARD_PAD * 2 + SIGIL_SIZE + SIGIL_GAP + nameH + NAME_GAP + effectH,
	}
end

-- Width of `text` as it will actually render. TextService:GetTextSize takes the
-- LEGACY Enum.Font, not T.font.display's Font object -- GothamBold is both what
-- T.font.display resolves to and what UIPolish force-sets game-wide, so the
-- measurement matches the pixels on either path. pcall'd with a crude fallback
-- because this runs inside Build, where a throw costs the whole panel.
local function measureText(text: string, size: number): number
	local ok, w = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.GothamBold, Vector2.new(9999, 100)).X
	end)
	if ok and type(w) == "number" then return w end
	return #text * size * 0.6
end

-- How many lines `text` takes when wrapped into `width`, and that many lines'
-- worth of height. GetTextSize reports whole lines at exactly `size` each, so
-- the division is exact; lineH() then converts to the leading setLeading()
-- applies. This is what makes every block in the detail column measured rather
-- than guessed -- Task 3 found a name silently eaten by TextTruncate that no
-- screenshot showed, and the detail column carries far more text than a card.
local function wrapLines(text: string, size: number, width: number): number
	local ok, sz = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.GothamBold,
			Vector2.new(math.max(width, 1), 1000000))
	end)
	if ok and typeof(sz) == "Vector2" and sz.Y > 0 then
		return math.max(1, math.ceil(sz.Y / size - 0.01))
	end
	return math.max(1, math.ceil((#text * size * 0.6) / math.max(width, 1)))
end

local function wrapHeight(text: string, size: number, width: number): number
	return wrapLines(text, size, width) * lineH(size)
end

---------------------------------------------------------------- sigil glyphs
-- The grid's charm glyph, drawn from GUI primitives (no asset ids -- the same
-- convention UIKit.IconArt uses). `kind` is read straight off charm.Sigil.
--
-- In the current data Sigil is a pure function of Category (square = WORLD,
-- diamond = MILESTONE, circle = QUEST, ring = SEASON; CharmConfig records that
-- as M.SigilForCategory) -- but this READS the charm's own field rather than
-- re-deriving it from the category, exactly as CharmConfig's header asks, so a
-- roster that wants an exception gets one. An unrecognised kind falls through
-- to the square instead of throwing: a wrong glyph is a blemish, a throw is a
-- dead panel.
--
-- Exposed on ctx.state.charms.drawSigil for Task 4.
local function drawSigil(ctx, parent: GuiObject, kind: string, size: number, zIndex: number, color: Color3): Frame
	local UI = ctx.Builders

	local holder = Instance.new("Frame")
	holder.Name = "Sigil"
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = zIndex
	holder.Parent = parent

	local function shape(name: string, inset: number, radius: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(size - inset * 2, size - inset * 2)
		f.BackgroundTransparency = 1
		f.ZIndex = zIndex
		f.Parent = holder
		UI.corner(f, radius)
		local s = UI.stroke(f, SIGIL_STROKE)
		s.Color = color
		return f
	end

	if kind == "diamond" then
		-- A square turned 45 degrees needs its side cut to 1/sqrt(2) of the box
		-- or its corners hang outside the holder; 0.15 of the size off each edge
		-- is that, rounded up.
		local d = shape("Diamond", math.ceil(size * 0.15), 2)
		d.Rotation = 45
	elseif kind == "circle" then
		shape("Circle", 1, 999)
	elseif kind == "ring" then
		shape("Outer", 1, 999)
		shape("Inner", math.ceil(size * 0.28), 999)
	else
		shape("Square", 2, 3)
	end

	return holder
end

---------------------------------------------------------------- stacking rule
-- The STACKING RULE box. Rendered VERBATIM from CharmConfig.Display: this is
-- a real invariant of the charm layer (charms are additive within their own
-- layer and applied once -- they never chain), not decoration. Do not reword
-- it, and do not let a later task "tidy" the formula.
--
-- Position is set by the CALLER, after this returns -- UI.hardShadow follows
-- its frame's Position, so the usual two-step construct-then-place pattern is
-- safe here.
local function buildStackingRule(ctx, parent: Instance, w: number, h: number): Frame
	local T, UI = ctx.Tokens, ctx.Builders
	local D = CharmConfig.Display

	local box = UI.surface(parent, UDim2.fromOffset(w, h), "slot", T.radius.slot, T.stroke.panel)
	box.Name = "StackingRule"
	box.AnchorPoint = Vector2.new(1, 0)
	box.ZIndex = 14
	UI.hardShadow(box, T.shadowOffset.chip, T.radius.slot)

	local label = UI.label(box, D.StackingLabel, "chip", T.color.textMuted)
	label.Name = "Label"
	label.Position = UDim2.fromOffset(12, 12)
	label.ZIndex = 15

	local formula = UI.label(box, D.StackingFormula, "cardLabel", T.color.textOnLight)
	formula.Name = "Formula"
	formula.Position = UDim2.fromOffset(12, 34)
	formula.ZIndex = 15

	-- Fixed height + TextWrapped, so AutomaticSize is turned back OFF: UI.label
	-- ships XY, and XY plus wrapping is a contradiction the label resolves by
	-- never wrapping.
	local note = UI.label(box, D.StackingNote, "meta", T.color.textMuted)
	note.Name = "Note"
	note.AutomaticSize = Enum.AutomaticSize.None
	note.AnchorPoint = Vector2.new(0, 1)
	note.Position = UDim2.new(0, 12, 1, -12)
	note.Size = UDim2.new(1, -24, 0, 38)
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Bottom
	note.ZIndex = 15

	return box
end

---------------------------------------------------------------- slot card
-- One card per CharmConfig.Slots entry. `slot` is the ONLY source of the
-- number, the occupant word and the unlock condition -- see the file header.
--
-- Returns the plain wrapper Frame, which is the UIListLayout item. The card
-- lives INSIDE it because UI.hardShadow parents the shadow as a sibling of
-- the card: with the card as the list item, its shadow would become a phantom
-- cell and shove every later card sideways (trap 2).
local function buildSlotCard(ctx, parent: Instance, slot, i: number, w: number, h: number): Frame
	local T, UI = ctx.Tokens, ctx.Builders
	local D = CharmConfig.Display
	local n = slot.Index or i
	local locked = slot.Locked == true

	local holder = Instance.new("Frame")
	holder.Name = "Slot" .. tostring(n)
	holder.Size = UDim2.fromOffset(w, h)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = i
	holder.ZIndex = 14
	holder.Parent = parent

	-- 2026-08-17 delta-8 conformance: BOTH locked slots here are
	-- gamepass-PURCHASABLE, and purchasable = the GOLD tile (same treatment as
	-- the bay's next plot slot and the pet slot row). The old dark `track`
	-- slabs were the two darkest boxes on the tab.
	local card = UI.surface(holder, UDim2.fromScale(1, 1), "slot", T.radius.slot, T.stroke.panel)
	card.Name = "Card"
	card.ZIndex = 15
	UI.hardShadow(card, T.shadowOffset.chip, T.radius.slot)
	if locked then
		card.BackgroundColor3 = Color3.fromHex("FFE9A8") -- multiply trap: base moves WITH the gradient
		local g = card:FindFirstChildOfClass("UIGradient")
		if g then g.Color = ColorSequence.new(Color3.fromHex("FFE9A8"), Color3.fromHex("FFC53D")) end
		local st = card:FindFirstChildOfClass("UIStroke")
		if st then st.Color = Color3.fromHex("8A6510") end
	end

	-- spec sweep 2026-08-10: a LOCKED card keeps the dark `track` surface, so
	-- its small text must stay light there; unlocked cards are white now and
	-- take the ink family.
	local eyebrow = UI.label(card, ("SLOT %02d"):format(n), "chip",
		if locked then Color3.fromHex("8A6510") else T.color.textMuted) -- dark gold-brown ink on the gold tile
	eyebrow.Name = "Eyebrow"
	eyebrow.Position = UDim2.fromOffset(12, 12)
	eyebrow.ZIndex = 16

	-- "Empty" / "Locked" both come from Display; the locked one drops to the
	-- disabled ink so the card reads as unavailable at a glance rather than
	-- only on reading the word.
	local occupant = UI.label(card,
		if locked then D.SlotLocked else D.SlotEmpty,
		"buttonM",
		if locked then Color3.fromHex("3A2A05") else T.color.textOnLight) -- bay rule: dark ink on gold
	occupant.Name = "Occupant"
	occupant.Position = UDim2.fromOffset(12, 34)
	occupant.ZIndex = 16

	local unlock = UI.label(card, slot.Unlock or "", "meta",
		if locked then Color3.fromHex("3A2A05") else T.color.textMuted)
	unlock.Name = "Unlock"
	unlock.AutomaticSize = Enum.AutomaticSize.None
	unlock.AnchorPoint = Vector2.new(0, 1)
	unlock.Position = UDim2.new(0, 12, 1, -10)
	unlock.Size = UDim2.new(1, -24, 0, 36)
	unlock.TextWrapped = true
	unlock.TextYAlignment = Enum.TextYAlignment.Bottom
	unlock.ZIndex = 16

	return holder
end

---------------------------------------------------------------- charm card
-- One card per roster entry. EVERYTHING on it comes off `charm`: the glyph is
-- charm.Sigil, the title is charm.Name, the small line is charm.Effect. No name
-- and no count is written here.
--
-- Returns a record whose `root` is the plain wrapper Frame. The wrapper is the
-- UIGridLayout item and the card lives INSIDE it, because UI.hardShadow parents
-- the shadow as a SIBLING of the card -- a card dropped straight into the grid
-- would turn its own shadow into a phantom cell and shove every later card
-- along (trap 2).
local function buildCharmCard(ctx, parent: GuiObject, charm, order: number, cellW: number, cellH: number)
	local T, UI = ctx.Tokens, ctx.Builders
	local m = cardMetrics(T)
	local locked = charm.Locked == true
	local z = parent.ZIndex + 1

	local cell = Instance.new("Frame")
	cell.Name = "Cell_" .. tostring(charm.Id)
	cell.Size = UDim2.fromOffset(cellW, cellH)   -- UIGridLayout re-asserts this
	cell.BackgroundTransparency = 1
	cell.LayoutOrder = order
	cell.ZIndex = z
	cell.Parent = parent

	-- BOXED card plate -- round-6 ruling (2026-08-18): charm cards STAY boxed.
	-- They are dense text surfaces and clickable state tiles, and PS99's own
	-- enchant lists are boxed rows; the splash de-box tried the same day was
	-- applied in error over that ruling and has been reverted. A LOCKED charm
	-- keeps the same geometry and takes the darker "track" surface (plate +
	-- disabled ink) -- "present but unavailable", and NOT hidden: the design
	-- shows all four.
	-- if-else EXPRESSION, not `locked and "track" or "slot"` (trap 4).
	local card = UI.surface(cell, UDim2.fromScale(1, 1),
		if locked then "track" else "slot", T.radius.slot, T.stroke.panel)
	card.Name = "Card"
	card.ZIndex = z
	UI.hardShadow(card, T.shadowOffset.chip, T.radius.slot)

	local ink = if locked then T.color.textDisabled else T.color.textOnLight
	local sub = if locked then T.color.textClaimed else T.color.textMuted

	local sigil = drawSigil(ctx, card, charm.Sigil, m.sigil, z + 1, ink)
	sigil.Position = UDim2.fromOffset(m.pad, m.pad)

	-- Wrapped over NAME_LINES lines rather than one: the roster is placeholder
	-- and the real names are unwritten, so a fixed single line would clip the
	-- first long one. AutomaticSize is turned back OFF because UI.label ships XY
	-- and XY plus wrapping is a contradiction the label resolves by never
	-- wrapping (same fix as the stacking note).
	local name = UI.label(card, tostring(charm.Name), "cardLabel", ink)
	name.Name = "CharmName"
	name.AutomaticSize = Enum.AutomaticSize.None
	name.Position = UDim2.fromOffset(m.pad, m.pad + m.sigil + m.sigilGap)
	name.Size = UDim2.new(1, -m.pad * 2, 0, m.nameH)
	name.TextWrapped = true
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.ZIndex = z + 1
	name.TextColor3 = ink   -- re-asserted AFTER UI.label returned (trap 1)

	-- TextScaled under a MaxTextSize CAP, not a fixed size. Caught by measuring
	-- rather than by looking: at a fixed 17px in a 118px card, "The Prospector's
	-- Eye" wrapped to three lines inside a two-line box and TextTruncate ate its
	-- last word (TextFits reported false, 1 of 16). The card width is SOLVED from
	-- the column and the names are author-supplied, so NO fixed size can be safe
	-- for a roster nobody has written yet. The cap means short names still render
	-- at exactly T.text.cardLabel and only a long one shrinks -- the same
	-- treatment BackpackPanel gives its "Epic-Legendary" chip and GameHUDClient
	-- gives its rail captions. TextTruncate stays as the last resort below
	-- MinTextSize.
	local nameFit = Instance.new("UITextSizeConstraint")
	nameFit.MaxTextSize = T.text.cardLabel[1]
	nameFit.MinTextSize = 11
	nameFit.Parent = name
	name.TextScaled = true

	local effect = UI.label(card, tostring(charm.Effect), "chip", sub)
	effect.Name = "Effect"
	effect.AutomaticSize = Enum.AutomaticSize.None
	effect.AnchorPoint = Vector2.new(0, 1)
	effect.Position = UDim2.new(0, m.pad, 1, -m.pad)
	effect.Size = UDim2.new(1, -m.pad * 2, 0, m.effectH)
	effect.TextTruncate = Enum.TextTruncate.AtEnd
	effect.TextYAlignment = Enum.TextYAlignment.Bottom
	effect.ZIndex = z + 1
	effect.TextColor3 = sub

	-- Same cap, same reason: today's longest effect label clears its box by 9px,
	-- which is not a margin worth betting an unwritten roster on.
	local effectFit = Instance.new("UITextSizeConstraint")
	effectFit.MaxTextSize = T.text.chip[1]
	effectFit.MinTextSize = 9
	effectFit.Parent = effect
	effect.TextScaled = true

	-- The accent selection ring. Built hidden; setSelected owns Visible and
	-- shows exactly one at a time.
	local ring = Instance.new("Frame")
	ring.Name = "SelectedRing"
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.ZIndex = z + 2
	ring.Parent = card
	UI.corner(ring, T.radius.slot)
	local ringStroke = UI.stroke(ring, T.stroke.panel)
	ringStroke.Color = T.color.activeRing

	-- A locked card KEEPS its hit box on purpose. The click is refused by the
	-- handler (and refused again by setSelected) rather than being silently
	-- unhittable, so "cannot be selected" is a code path that can be exercised
	-- instead of an absence that can only be assumed.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.ZIndex = z + 3
	hit.Parent = card

	return {
		root = cell, card = card, sigil = sigil, ring = ring,
		name = name, effect = effect, hit = hit,
		charm = charm, locked = locked, shown = true, order = order,
	}
end

---------------------------------------------------------------- filter tabs
-- One tab per def, left to right at their MEASURED widths, so the row fits
-- whatever the categories turn out to be called. Positions are set by hand (no
-- UIListLayout), which is precisely what makes it safe to hang each tab's
-- sibling hard shadow straight off it -- trap 2 only bites inside a layout.
-- Same reasoning BackpackPanel writes into its own Tabs / ChipRow loops.
--
-- If the natural row will not fit the space the status line leaves, every tab
-- falls back to an equal share and its label shrinks to fit rather than
-- overflowing (the TextScaled + UITextSizeConstraint treatment BackpackPanel
-- gives its "Epic-Legendary" chip). That branch is dead for today's five
-- categories and exists for the roster that has not been written yet.
local function buildFilterTabs(ctx, parent: GuiObject, defs, avail: number, tabH: number, onPick)
	local T, UI = ctx.Tokens, ctx.Builders
	local chipSize = T.text.chip[1]
	local n = #defs

	local widths = {}
	local natural = TAB_GAP * math.max(n - 1, 0)
	for i, def in ipairs(defs) do
		widths[i] = math.ceil(measureText(tostring(def.Label), chipSize)) + TAB_PAD_X * 2
		natural += widths[i]
	end

	local squeezed = natural > avail
	if squeezed then
		local each = math.floor((avail - TAB_GAP * math.max(n - 1, 0)) / math.max(n, 1))
		for i = 1, n do
			widths[i] = math.max(each, 1)
		end
	end

	local out = {}
	local x = 0
	for i, def in ipairs(defs) do
		local tab = UI.surface(parent, UDim2.fromOffset(widths[i], tabH), "tab", T.radius.small, T.stroke.chip)
		tab.Name = "Tab" .. tostring(def.Key)
		tab.Position = UDim2.fromOffset(x, 0)
		tab.ZIndex = parent.ZIndex + 1
		-- spec chips: neutral at rest (setFilter paints the active one gold).
		-- BackgroundColor3 moves WITH the gradient -- UIGradient multiplies it.
		tab.BackgroundColor3 = SpecS.Action.Neutral[1]
		local tabGrad = tab:FindFirstChildOfClass("UIGradient")
		if tabGrad then
			tabGrad.Color = ColorSequence.new(SpecS.Action.Neutral[1], SpecS.Action.Neutral[2])
		end
		-- Position first, shadow second: UI.hardShadow captures Position at
		-- creation (and then follows it), so this ordering is the safe one.
		UI.hardShadow(tab, T.shadowOffset.chip, T.radius.small)

		-- pale-Neutral rest state: dark ink + white contextual stroke (white
		-- bubble text vanishes on the lightened Neutral); setFilter repaints
		-- the active tab white + ink when it lays the green on. Root is
		-- NoPolish, so these colours are final. NOTE: built with DARK ink,
		-- UI.label adds no auto-stroke of its own (it only strokes light
		-- fills), so labelStroke below is the label's ONE stroke.
		local label = UI.label(tab, tostring(def.Label), "chip", T.color.textOnLight)
		label.Name = "Label"
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.fromScale(1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.ZIndex = tab.ZIndex + 1
		local labelStroke = UI.stroke(label, 2)
		labelStroke.Color = T.color.white
		labelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		if squeezed then
			label.TextScaled = true
			local cap = Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = chipSize
			cap.MinTextSize = 8
			cap.Parent = label
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 4)
			pad.PaddingRight = UDim.new(0, 4)
			pad.Parent = label
		end

		-- The kit's accent treatment for an active tab: a 4px #FFD84D ring flush
		-- with the tab's own edge, exactly as BackpackPanel's tab column and
		-- GoalsPanel's segments do it. setFilter owns Visible.
		local ring = Instance.new("Frame")
		ring.Name = "ActiveRing"
		ring.Size = UDim2.fromScale(1, 1)
		ring.BackgroundTransparency = 1
		ring.Visible = false
		ring.ZIndex = tab.ZIndex + 2
		ring.Parent = tab
		UI.corner(ring, T.radius.small)
		local ringStroke = UI.stroke(ring, T.stroke.panel)
		ringStroke.Color = T.color.activeRing

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.ZIndex = tab.ZIndex + 3
		hit.Parent = tab
		hit.MouseButton1Click:Connect(function()
			onPick(def.Key)
		end)

		out[def.Key] = { frame = tab, label = label, ring = ring, hit = hit, def = def, order = i }
		x += widths[i] + TAB_GAP
	end

	return out
end

---------------------------------------------------------------- charm grid
-- Fills LeftColumn: the filter tab row (with the status line) and the
-- scrolling card grid. Returns the Task 4 contract documented in the header.
--
-- THE RULE THIS FUNCTION EXISTS TO KEEP: nothing about the SHAPE of the grid is
-- written down. Columns are solved from the width actually available and
-- CARD_MIN_W; rows are math.ceil(shown / columns); the canvas height follows
-- the rows. Filtering re-flows by toggling each cell's Visible -- UIGridLayout
-- skips invisible children -- so no card is ever rebuilt to change a filter.
local function buildCharmGrid(ctx, host: GuiObject, w: number, h: number)
	local T, UI = ctx.Tokens, ctx.Builders
	local GAP = T.pad.gap
	local GRID_GAP = T.pad.gridGap
	local state = ctx.state.charms

	------------------------------------------------------------- tab defs
	-- One tab per CharmConfig.Categories entry with the ALL pseudo-category
	-- FIRST. CharmConfig already ships ALL as Categories[1] (Key = "ALL",
	-- All = true); this hoists whatever carries the All flag rather than
	-- assuming its position, and synthesises one only if a future roster drops
	-- it -- so the row can never lose its "everything" tab, and can never grow
	-- a duplicate one either. The category names themselves are never spelled.
	local defs = {}
	for _, cat in ipairs(CharmConfig.Categories) do
		if cat.All then table.insert(defs, cat) end
	end
	if #defs == 0 then
		table.insert(defs, { Key = ALL_KEY, Label = ALL_KEY, All = true })
	end
	for _, cat in ipairs(CharmConfig.Categories) do
		if not cat.All then table.insert(defs, cat) end
	end

	-- What setFilter will accept. Deliberately NOT CharmConfig.HasCategory:
	-- a synthesised ALL is not in M.Categories, so HasCategory would reject the
	-- tab this function had just drawn.
	local validKeys = {}
	for _, d in ipairs(defs) do validKeys[d.Key] = true end

	------------------------------------------------------------- tab row
	local chipSize = T.text.chip[1]
	local tabH = TAB_PAD_Y * 2 + lineH(chipSize)

	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.Size = UDim2.fromOffset(w, tabH)
	tabRow.BackgroundTransparency = 1
	tabRow.ZIndex = host.ZIndex + 1
	tabRow.Parent = host

	-- Step 2: the shown count and the slots-used count, both composed by
	-- CharmConfig. The width reserved for it is the WIDEST line this roster can
	-- produce (everything shown, every earnable slot used), measured rather
	-- than guessed, so the tabs get the real remainder and the two never
	-- collide as the count changes.
	local statusW = math.ceil(measureText(
		CharmConfig.ShownLine(CharmConfig.Count(), CharmConfig.UnlockableSlotCount()), chipSize))

	local statusLabel = UI.label(tabRow, "", "chip", T.color.textMuted)
	statusLabel.Name = "ShownStatus"
	statusLabel.AnchorPoint = Vector2.new(1, 0.5)
	statusLabel.Position = UDim2.new(1, 0, 0.5, 0)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.ZIndex = tabRow.ZIndex + 1

	-- Forward slot for setFilter: the tab Hit buttons are wired below, before
	-- the real implementation exists, and a nil upvalue would need a nil test at
	-- every call site. The stub is replaced further down inside this same call,
	-- long before any click can land.
	local setFilter = function(_key: string): boolean return false end

	-- 2026-08-11 embed reflow: at the Bag tab body's width the status line's
	-- reservation squeezed five chips to ~30px of unreadable wrap. When the
	-- chips' NATURAL width no longer fits beside the status, the status line
	-- yields (hidden) and the chips take the whole row -- readable filters
	-- beat a redundant count (the slot cards sit right above this row).
	local chipsNatural = TAB_GAP * math.max(#defs - 1, 0)
	for _, d in ipairs(defs) do
		chipsNatural += math.ceil(measureText(tostring(d.Label), chipSize)) + TAB_PAD_X * 2
	end
	local tabsAvail = w - statusW - GAP
	if chipsNatural > tabsAvail then
		statusLabel.Visible = false
		tabsAvail = w
	end

	local tabs = buildFilterTabs(ctx, tabRow, defs, math.max(tabsAvail, 1), tabH,
		function(key) setFilter(key) end)

	------------------------------------------------------------- grid frame
	local m = cardMetrics(T)
	local usableW = w - SCROLL_RESERVE
	-- SOLVED, not typed: how many CARD_MIN_W cards plus their gaps fit the width
	-- available, and then the real card width is that width shared out.
	local columns = math.max(1, math.floor((usableW + GRID_GAP) / (CARD_MIN_W + GRID_GAP)))
	local cellW = math.max(1, math.floor((usableW - GRID_GAP * (columns - 1)) / columns))
	local cellH = m.height

	local gridTop = tabH + GAP
	local gridH = math.max(h - gridTop, 1)

	-- A ScrollingFrame, not a plain Frame: a bigger roster must SCROLL rather
	-- than overflow its column.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Position = UDim2.fromOffset(0, gridTop)
	scroll.Size = UDim2.fromOffset(w, gridH)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = SCROLL_W
	scroll.ScrollBarImageColor3 = T.color.outline -- same call PassPanel makes: the kit's ink is the highest-contrast thumb on the gray window
	scroll.CanvasSize = UDim2.new()
	scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	scroll.ZIndex = host.ZIndex + 1
	scroll.Parent = host

	-- The gutter the thumb lives in. Taken off the LAYOUT width above too (see
	-- usableW), so a card is never half-buried under the scrollbar.
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingRight = UDim.new(0, SCROLL_RESERVE)
	scrollPad.Parent = scroll

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(cellW, cellH)
	gridLayout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
	gridLayout.FillDirectionMaxCells = columns
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = scroll

	------------------------------------------------------------- cards
	-- Built ONCE, one per roster entry, in roster order. Filtering never
	-- rebuilds them (see setFilter).
	local cards = {}
	for i, charm in ipairs(CharmConfig.Charms) do
		-- pcall per card, same reason as the slot loop: one malformed roster
		-- entry costs one card instead of the whole panel.
		local ok, rec = pcall(buildCharmCard, ctx, scroll, charm, i, cellW, cellH)
		if ok then
			cards[charm.Id] = rec
		else
			warn("[CharmsPanel] charm card " .. tostring(charm and charm.Id) .. " failed: " .. tostring(rec))
		end
	end

	------------------------------------------------------------- selection
	local selectedId = nil

	-- ONE ring at a time. Returns false and changes NOTHING when the id cannot
	-- legally hold the selection: unknown, LOCKED, or hidden by the active
	-- filter. A ring on a filtered-out card -- or an id pointing at one -- is
	-- exactly the stranded state step 6 forbids, so it is refused at the door
	-- as well as cleared on the way out.
	local function setSelected(id): boolean
		if id ~= nil then
			local rec = cards[id]
			if rec == nil then return false end
			if rec.locked then return false end
			if not rec.shown then return false end
		end
		if selectedId == id then return true end

		if selectedId ~= nil and cards[selectedId] ~= nil then
			cards[selectedId].ring.Visible = false
		end
		selectedId = id
		state.selectedId = id
		if id ~= nil and cards[id] ~= nil then
			cards[id].ring.Visible = true
		end

		local cb = state.onSelect
		if type(cb) == "function" then
			local charm = nil
			if id ~= nil then charm = CharmConfig.CharmById(id) end
			pcall(cb, charm, id)
		end
		return true
	end

	for id, rec in pairs(cards) do
		rec.hit.MouseButton1Click:Connect(function()
			-- Refused here AND in setSelected. Deliberate belt and braces: this
			-- branch is what makes a locked card a visible no-op rather than a
			-- missing button, and setSelected is what protects the same rule from
			-- any other caller (Task 4 included).
			if rec.locked then return end
			setSelected(id)
		end)
	end

	------------------------------------------------------------- filtering
	local activeKey = nil
	local lastShown, lastRows = 0, 0

	-- Derived, never typed. There is no equip data anywhere in the game yet, so
	-- this is 0 today -- but it is COUNTED, so it follows on its own the moment
	-- a later task puts anything in ctx.state.charms.equipped.
	local function slotsUsed(): number
		local n = 0
		local eq = state.equipped
		if type(eq) == "table" then
			for _, slot in ipairs(CharmConfig.Slots) do
				if eq[slot.Index] ~= nil then n += 1 end
			end
		end
		return n
	end

	setFilter = function(key: string): boolean
		if not validKeys[key] then return false end
		activeKey = key
		state.filter = key

		for k, tab in pairs(tabs) do
			local on = (k == key)
			tab.ring.Visible = on
			-- spec repaint (2026-08-11): gold active / neutral rest; the base
			-- colour moves WITH the gradient (UIGradient multiplies it -- the
			-- old gradient-only repaint is what rendered olive elsewhere).
			-- Pale-Neutral sweep: the label ink flips WITH the fill -- dark ink
			-- + white stroke on the light Neutral, white + ink stroke on the
			-- active green (root is NoPolish, so these colours are final).
			local c = if on then SpecS.Action.Go else SpecS.Action.Neutral -- delta 7: active = green
			tab.frame.BackgroundColor3 = c[1]
			local g = tab.frame:FindFirstChildOfClass("UIGradient")
			if g then g.Color = ColorSequence.new(c[1], c[2]) end
			tab.label.TextColor3 = if on then T.color.white else T.color.textOnLight
			for _, s in ipairs(tab.label:GetChildren()) do
				if s:IsA("UIStroke") then
					s.Color = if on then T.color.outline else T.color.white
				end
			end
		end

		-- CharmConfig.Filter is the single source of what is shown. This panel
		-- never re-implements the predicate, so the counts cannot disagree.
		local shownSet = {}
		for _, c in ipairs(CharmConfig.Filter(key)) do shownSet[c.Id] = true end

		local shown = 0
		for id, rec in pairs(cards) do
			local vis = shownSet[id] == true
			rec.shown = vis
			rec.root.Visible = vis        -- UIGridLayout skips invisible children,
			if vis then shown += 1 end    -- so this RE-FLOWS without rebuilding
		end

		-- Step 6: never leave a ring on a hidden card or a dangling id.
		if selectedId ~= nil and shownSet[selectedId] ~= true then
			setSelected(nil)
		end

		-- The rows, and therefore the canvas, are SOLVED from what is showing.
		-- `shown` is counted off the cards actually visible rather than taken
		-- from #Filter(key), so a card that failed to build cannot leave the
		-- canvas claiming a row that is not there.
		local rows = math.ceil(shown / columns)
		scroll.CanvasSize = UDim2.fromOffset(0, rows * cellH + math.max(rows - 1, 0) * GRID_GAP)
		scroll.CanvasPosition = Vector2.new(0, 0)

		statusLabel.Text = CharmConfig.ShownLine(shown, slotsUsed())
		statusLabel.TextColor3 = T.color.textMuted

		lastShown, lastRows = shown, rows
		return true
	end

	------------------------------------------------------------- first paint
	-- Default filter = the first tab, i.e. the ALL pseudo-category. Task 2 left
	-- ctx.state.charms empty on purpose so this choice lives here.
	state.selectedId = nil
	setFilter(defs[1].Key)

	local function metrics()
		return {
			columns = columns,
			rows = lastRows,
			cellW = cellW,
			cellH = cellH,
			gap = GRID_GAP,
			shown = lastShown,
			total = CharmConfig.Count(),
			canvasH = scroll.CanvasSize.Y.Offset,
			viewportH = gridH,
			usableW = usableW,
			filter = activeKey,
		}
	end

	return {
		root = host,
		tabRow = tabRow,
		grid = scroll,
		status = statusLabel,
		tabs = tabs,
		cards = cards,
		setSelected = setSelected,
		getSelected = function() return selectedId end,
		setFilter = setFilter,
		getFilter = function() return activeKey end,
		metrics = metrics,
		drawSigil = drawSigil,
	}
end

---------------------------------------------------------------- flavour face
-- The design video sets the Flavour line in ITALIC, and it is the only italic
-- anywhere in the panel. T.font.display is GothamSSm, which SHIPS NO ITALIC
-- FACE -- measured, not assumed. The same string at TextSize 14 renders to
-- exactly the same width with FontStyle.Normal and FontStyle.Italic, while
-- FontFace.Style still reads back Italic: setting the style there is a silent
-- no-op, which is the failure mode this project keeps paying for.
--
-- Families probed the same way (same string, bold width / regular width):
--   GothamSSm        248.0 / 248.0   231.0 / 231.0   NO italic face
--   Montserrat       248.0 / 248.0   231.0 / 234.0   italic at REGULAR only
--   SourceSansPro    202.0 / 195.0   185.0 / 181.0   italic
--   Merriweather     233.0 / 209.0   226.0 / 207.0   italic (serif)
--   AccanthisADFStd, Nunito, Arimo                   NO italic face
--
-- Montserrat is the geometric sans Gotham is routinely substituted with, so
-- its Regular Italic is the closest TRUE italic to the kit's own face. Exactly
-- one line in the whole panel uses it. UIPolish would overwrite it with the
-- legacy .Font enum (which replaces FontFace outright), but the root's
-- NoPolish attribute stops that -- verified after its deferred pass.
local FLAVOUR_FONT = Font.new("rbxasset://fonts/families/Montserrat.json",
	Enum.FontWeight.Regular, Enum.FontStyle.Italic)

---------------------------------------------------------------- toast
-- A local toast pill, built the way TradeClient and BoothClient build theirs
-- (UIKit `row` surface, top centre, token-guarded auto-hide). Deliberately NOT
-- the game's ToastClient: that is the renderer for {Success, Message} SERVER
-- replies, and there is no server involved here to reply.
--
-- Parented to the panel WRAPPER rather than into a column, so it draws over
-- the whole window (the HUD ScreenGui is ZIndexBehavior.Sibling, so a sibling
-- of PanelWindow at a higher ZIndex wins) and dies with the panel.
--
-- The pill and its hard shadow BOTH live in a holder, and the HOLDER is what
-- toggles. UI.hardShadow does not mirror Visible: hiding the pill alone would
-- leave a solid #202020 rectangle parked over the panel forever -- which is
-- exactly the "big black square" this project has already shipped once.
local function buildToast(ctx, parent: GuiObject)
	local T, UI = ctx.Tokens, ctx.Builders

	local holder = Instance.new("Frame")
	holder.Name = "ToastHolder"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.ZIndex = 60
	holder.Parent = parent

	local pill = UI.surface(holder, UDim2.fromOffset(TOAST_W, TOAST_H), "row", T.radius.control, T.stroke.control)
	pill.Name = "Toast"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, TOAST_Y)
	pill.ZIndex = holder.ZIndex + 1
	-- Position first, shadow second: UI.hardShadow captures Position at creation
	-- and then follows it, so this ordering is the safe one.
	UI.hardShadow(pill, T.shadowOffset.control, T.radius.control)

	local label = UI.label(pill, "", "buttonM", T.color.white)
	label.Name = "Message"
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Position = UDim2.fromOffset(12, 0)
	label.Size = UDim2.new(1, -24, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextScaled = true
	label.ZIndex = pill.ZIndex + 1
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = T.text.buttonM[1]
	cap.MinTextSize = 10
	cap.Parent = label

	local token = 0
	local function show(message: string)
		token += 1
		local mine = token
		label.Text = tostring(message)
		holder.Visible = true
		-- token-guarded, so a second press re-arms the timer instead of the first
		-- press's timer hiding the second press's message
		task.delay(TOAST_HOLD, function()
			if mine == token then holder.Visible = false end
		end)
	end

	return show, holder
end

---------------------------------------------------------------- detail column
-- Fills RightColumn: sigil figure, tag row, identity block, the five spec
-- rows, the note box and the EQUIP call to action.
--
-- THE RULE THIS FUNCTION EXISTS TO KEEP, and it is the same one the grid
-- keeps: no block's height is written down. Every one is wrapHeight() over the
-- charm's OWN text at the width actually available, so the roster the user has
-- not written yet cannot clip. That matters more here than anywhere else in
-- the panel -- the column is nothing but author copy, and today's Notes
-- already run to 300+ characters.
--
-- Children of `body` are POSITIONED at a running Y rather than laid out. Two
-- reasons: their heights change per charm (so a layout would have to be
-- re-solved anyway), and it makes every hard shadow in here safe -- trap 2
-- only bites inside a UIListLayout/UIGridLayout. The blocks whose SIZE changes
-- still keep their shadow in a wrapper, because UI.hardShadow follows Position
-- but NOT Size or Visible.
--
-- ONE surface for the whole reading area, dark `slot`, exactly like the
-- stacking-rule box. That is not decoration: T.color.textMuted is documented
-- as reading on the dark slots, and this panel's window is the LIGHT gray
-- (#D6D6D6 -> #A9A9A9), on which muted white is invisible -- the trap
-- EggShopClient's spec strip already paid for.
local function buildDetailColumn(ctx, host: GuiObject, w: number, h: number, showToast)
	local T, UI = ctx.Tokens, ctx.Builders
	local D = CharmConfig.Display
	local z = host.ZIndex
	local chipSize = T.text.chip[1]
	local metaSize = T.text.meta[1]
	local nameSize = T.text.buttonL[1]

	-- Is there anywhere to equip TO? Derived from the roster. A roster whose
	-- every slot is Locked has no legal target, and rather than print a slot
	-- number that does not exist the CTA is not built at all and the reading
	-- area takes the height back.
	local hasSlot = CharmConfig.UnlockableSlotCount() > 0
	local surfH = h
	if hasSlot then surfH = h - EQUIP_H - DET_GAP end
	surfH = math.max(surfH, 1)

	-- host (RightColumn) has NO layout, so this sibling shadow is safe where a
	-- shadow inside the grid would have become a phantom cell.
	local surface = UI.surface(host, UDim2.fromOffset(w, surfH), "slot", T.radius.slot, T.stroke.panel)
	surface.Name = "Detail"
	surface.ZIndex = z + 1
	UI.hardShadow(surface, T.shadowOffset.chip, T.radius.slot)

	------------------------------------------------------------- empty state
	-- Step 7. The design video NEVER shows an unselected column -- every frame
	-- has a charm picked -- so this line is ours (exception 5 in the header).
	-- The panel opens with nothing selected (Task 3 sets selectedId = nil on
	-- first paint), so this is the FIRST thing a player sees in this column,
	-- and a blank half-panel would read as the panel having failed to load.
	local empty = Instance.new("Frame")
	empty.Name = "Empty"
	empty.Size = UDim2.fromScale(1, 1)
	empty.BackgroundTransparency = 1
	empty.ZIndex = surface.ZIndex + 1
	empty.Parent = surface

	-- 2026-08-18 fix: the height was a FIXED two lines, so at narrow widths
	-- the wrapped prompt rendered squished. Now SOLVED from the prompt's own
	-- text at the real width (floored at two lines), in the standard ReadSub
	-- ink so it reads on the light plate at every width.
	local emptyW = math.max(w - DET_PAD * 4, 1)
	local emptyH = math.max(wrapHeight(EMPTY_PROMPT, T.text.cardLabel[1], emptyW),
		lineH(T.text.cardLabel[1]) * 2)
	local emptyLabel = UI.label(empty, EMPTY_PROMPT, "cardLabel", SpecS.Surface.ReadSub)
	emptyLabel.Name = "Prompt"
	emptyLabel.AutomaticSize = Enum.AutomaticSize.None
	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	emptyLabel.Position = UDim2.fromScale(0.5, 0.5)
	emptyLabel.Size = UDim2.fromOffset(emptyW, emptyH)
	emptyLabel.TextWrapped = true
	emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
	emptyLabel.TextYAlignment = Enum.TextYAlignment.Center
	emptyLabel.ZIndex = empty.ZIndex + 1
	emptyLabel.TextColor3 = SpecS.Surface.ReadSub   -- re-asserted after UI.label (trap 1)
	-- visual pass 2026-08-10: exempt from UIPolish so the prompt reads as
	-- INK on the white detail plate instead of ghost white bubble text
	emptyLabel:SetAttribute("NoPolish", true)
	setLeading(emptyLabel)

	------------------------------------------------------------- body
	-- A ScrollingFrame, and it is NOT optional. Measured at the shipped
	-- geometry the tallest charm's content exceeds this column by well over
	-- 100px, and the copy is placeholder -- see the report. The EQUIP CTA sits
	-- OUTSIDE the scroll so the call to action is reachable without scrolling.
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(DET_PAD, DET_PAD)
	body.Size = UDim2.fromOffset(math.max(w - DET_PAD * 2, 1), math.max(surfH - DET_PAD * 2, 1))
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.ScrollBarThickness = SCROLL_W
	body.ScrollBarImageColor3 = T.color.outline
	body.CanvasSize = UDim2.new()
	body.ElasticBehavior = Enum.ElasticBehavior.Never
	body.Visible = false
	body.ZIndex = surface.ZIndex + 1
	body.Parent = surface

	-- Same gutter the grid reserves, and taken off contentW below too, so no
	-- text ever sits under the thumb.
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingRight = UDim.new(0, SCROLL_RESERVE)
	bodyPad.Parent = body

	local contentW = math.max(w - DET_PAD * 2 - SCROLL_RESERVE, 1)
	local bz = body.ZIndex + 1

	------------------------------------------------------------- figure
	-- Step 1. The video's plate is a diagonal-striped Industry motif; the user
	-- rejected that whole family, so it is the kit's darker `track` here. The
	-- glyph is drawSigil -- Task 3's, reused, not a second implementation --
	-- rebuilt per selection because its SHAPE comes from charm.Sigil.
	local figH = FIG_PAD * 2 + FIG_SIGIL + FIG_CAPTION_GAP + lineH(metaSize)

	local figSlot = Instance.new("Frame")
	figSlot.Name = "FigureSlot"
	figSlot.Size = UDim2.fromOffset(contentW, figH)
	figSlot.BackgroundTransparency = 1
	figSlot.ZIndex = bz
	figSlot.Parent = body

	local figure = UI.surface(figSlot, UDim2.fromOffset(contentW, figH), "track", T.radius.slot, T.stroke.chip)
	figure.Name = "Figure"
	figure.ZIndex = bz
	UI.hardShadow(figure, T.shadowOffset.chip, T.radius.slot)

	-- The video captions this plate with a MOCK ASSET FILENAME. This prints the
	-- charm's real Id instead -- see the note under the header's exception list:
	-- there is no such file, and there never will be, because the sigils are
	-- drawn from GUI primitives with no asset id at all.
	local caption = UI.label(figure, "", "meta", T.color.textMutedOnDark)
	caption.Name = "Caption"
	caption.AutomaticSize = Enum.AutomaticSize.None
	caption.AnchorPoint = Vector2.new(0, 1)
	caption.Position = UDim2.new(0, FIG_PAD, 1, -FIG_PAD)
	caption.Size = UDim2.new(1, -FIG_PAD * 2, 0, lineH(metaSize))
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.TextYAlignment = Enum.TextYAlignment.Bottom
	caption.ZIndex = bz + 1
	caption.TextColor3 = T.color.textMutedOnDark   -- dark `track` plate

	------------------------------------------------------------- tag row
	-- Step 2. Category tag, state, index. All three POSITIONED (no layout), so
	-- the tag's sibling shadow is safe and the tag can be re-measured per charm.
	local tagH = DET_TAG_PAD_Y * 2 + lineH(chipSize)

	local tagRow = Instance.new("Frame")
	tagRow.Name = "TagRow"
	tagRow.Size = UDim2.fromOffset(contentW, tagH)
	tagRow.BackgroundTransparency = 1
	tagRow.ZIndex = bz
	tagRow.Parent = body

	local catTag = UI.surface(tagRow, UDim2.fromOffset(1, tagH), "tab", T.radius.small, T.stroke.chip)
	catTag.Name = "CategoryTag"
	catTag.ZIndex = bz + 1
	-- olive purge 2026-08-18: the raw `tab` ramp rendered this tag as the one
	-- muddy chip left on the panel. It now takes the SAME grey-blue Neutral
	-- rest fill as the filter pills (base moves WITH the gradient --
	-- UIGradient multiplies it), with dark ink below.
	catTag.BackgroundColor3 = SpecS.Action.Neutral[1]
	local catGrad = catTag:FindFirstChildOfClass("UIGradient")
	if catGrad then
		catGrad.Color = ColorSequence.new(SpecS.Action.Neutral[1], SpecS.Action.Neutral[2])
	end
	local catShadow = UI.hardShadow(catTag, T.shadowOffset.chip, T.radius.small)

	-- dark ink on the pale Neutral chip (textOnWindow IS the ink family now)
	local catLabel = UI.label(catTag, "", "chip", T.color.textOnWindow)
	catLabel.Name = "Label"
	catLabel.AutomaticSize = Enum.AutomaticSize.None
	catLabel.Size = UDim2.fromScale(1, 1)
	catLabel.TextXAlignment = Enum.TextXAlignment.Center
	catLabel.TextYAlignment = Enum.TextYAlignment.Center
	catLabel.ZIndex = catTag.ZIndex + 1
	catLabel.TextColor3 = T.color.textOnWindow

	local stateLabel = UI.label(tagRow, "", "chip", T.color.textMuted)
	stateLabel.Name = "State"
	stateLabel.AutomaticSize = Enum.AutomaticSize.X
	stateLabel.Size = UDim2.fromOffset(0, tagH)
	stateLabel.TextYAlignment = Enum.TextYAlignment.Center
	stateLabel.ZIndex = bz + 1

	local indexLabel = UI.label(tagRow, "", "chip", T.color.textMuted)
	indexLabel.Name = "Index"
	indexLabel.AutomaticSize = Enum.AutomaticSize.X
	indexLabel.Size = UDim2.fromOffset(0, tagH)
	indexLabel.AnchorPoint = Vector2.new(1, 0)
	indexLabel.Position = UDim2.new(1, 0, 0, 0)
	indexLabel.TextXAlignment = Enum.TextXAlignment.Right
	indexLabel.TextYAlignment = Enum.TextYAlignment.Center
	indexLabel.ZIndex = bz + 1

	------------------------------------------------------------- identity
	-- Step 3. Name, the id line, then the italic flavour.
	local nameLabel = UI.label(body, "", "buttonL", T.color.textOnLight)
	nameLabel.Name = "CharmName"
	nameLabel.AutomaticSize = Enum.AutomaticSize.None
	nameLabel.Size = UDim2.fromOffset(contentW, lineH(nameSize))
	nameLabel.TextWrapped = true
	nameLabel.TextYAlignment = Enum.TextYAlignment.Top
	nameLabel.ZIndex = bz
	setLeading(nameLabel)

	local idLabel = UI.label(body, "", "meta", T.color.textMuted)
	idLabel.Name = "IdLine"
	idLabel.AutomaticSize = Enum.AutomaticSize.None
	idLabel.Size = UDim2.fromOffset(contentW, lineH(metaSize))
	idLabel.TextTruncate = Enum.TextTruncate.AtEnd
	idLabel.TextYAlignment = Enum.TextYAlignment.Top
	idLabel.ZIndex = bz

	local flavour = UI.label(body, "", "meta", T.color.textMuted)
	flavour.Name = "Flavour"
	flavour.AutomaticSize = Enum.AutomaticSize.None
	flavour.Size = UDim2.fromOffset(contentW, lineH(metaSize))
	flavour.TextWrapped = true
	flavour.TextYAlignment = Enum.TextYAlignment.Top
	flavour.FontFace = FLAVOUR_FONT   -- see the measurement block above
	flavour.ZIndex = bz
	setLeading(flavour)

	------------------------------------------------------------- spec rows
	-- Step 4. The row SET is a table, not five copies of the same code: `key`
	-- is the charm FIELD and `label` is the Display string, so a sixth row is
	-- one line here plus one key in CharmConfig.
	local rowDefs = {
		{ key = "Gain",   label = D.RowGain },
		{ key = "Trade",  label = D.RowTrade },
		{ key = "Config", label = D.RowConfig },
		{ key = "Source", label = D.RowSource },
		{ key = "Hook",   label = D.RowHook },
	}

	-- The label column is as wide as the WIDEST label actually in the set,
	-- measured -- never typed, and never per-row: the values have to line up
	-- with each other or the block stops reading as a table.
	local labelW = 0
	for _, def in ipairs(rowDefs) do
		labelW = math.max(labelW, math.ceil(measureText(tostring(def.label), chipSize)))
	end
	labelW += ROW_LABEL_GAP
	local valueW = math.max(contentW - labelW, 1)
	local proposedW = math.ceil(measureText(tostring(D.ProposedTag), chipSize))

	local rows = {}
	for i, def in ipairs(rowDefs) do
		local frame = Instance.new("Frame")
		frame.Name = "Row_" .. tostring(def.key)
		frame.Size = UDim2.fromOffset(contentW, lineH(chipSize) + ROW_PAD_Y * 2)
		frame.BackgroundTransparency = 1
		frame.ZIndex = bz
		frame.Parent = body

		local label = UI.label(frame, tostring(def.label), "chip", T.color.textMuted)
		label.Name = "Label"
		label.Position = UDim2.fromOffset(0, ROW_PAD_Y)
		label.ZIndex = bz + 1
		label.TextColor3 = T.color.textMuted

		local value = UI.label(frame, "", "meta", T.color.textOnLight)
		value.Name = "Value"
		value.AutomaticSize = Enum.AutomaticSize.None
		value.Position = UDim2.fromOffset(labelW, ROW_PAD_Y)
		value.Size = UDim2.fromOffset(valueW, lineH(metaSize))
		value.TextWrapped = true
		value.TextYAlignment = Enum.TextYAlignment.Top
		value.ZIndex = bz + 1
		setLeading(value)

		local proposed = nil
		if def.key == "Trade" then
			-- Task 1 made TradeProposed THREE-valued on purpose: nil = no downside
			-- at all, true = the design PROPOSED one, false = the spec SETTLED on
			-- one. Collapsing that to a boolean would let an unconfirmed downside
			-- print as though it were final, which is the single thing
			-- CharmConfig.Verify exists to catch. render() below preserves it.
			proposed = UI.label(frame, tostring(D.ProposedTag), "chip", T.color.textAccent)
			proposed.Name = "Proposed"
			proposed.AnchorPoint = Vector2.new(1, 0)
			proposed.Position = UDim2.new(1, 0, 0, ROW_PAD_Y)
			proposed.Visible = false
			proposed.ZIndex = bz + 1
			proposed.TextColor3 = T.color.textAccent
		end

		rows[i] = { def = def, frame = frame, label = label, value = value, proposed = proposed }
	end

	------------------------------------------------------------- note box
	-- Step 5. The kit's accent (#FFD84D) -- the same ink the selection ring and
	-- the active filter tab use, so "read this" reads the same way everywhere.
	-- The box and its shadow share a WRAPPER: hiding the wrapper takes both, and
	-- the box RESIZES per charm, which UI.hardShadow does not follow (it follows
	-- Position only), so the shadow is resized by hand in render().
	local noteSlot = Instance.new("Frame")
	noteSlot.Name = "NoteSlot"
	noteSlot.Size = UDim2.fromOffset(contentW, 1)
	noteSlot.BackgroundTransparency = 1
	noteSlot.Visible = false
	noteSlot.ZIndex = bz
	noteSlot.Parent = body

	local noteBox = UI.surface(noteSlot, UDim2.fromOffset(contentW, 1), "track", T.radius.slot, T.stroke.chip)
	noteBox.Name = "NoteBox"
	noteBox.ZIndex = bz
	local noteShadow = UI.hardShadow(noteBox, T.shadowOffset.chip, T.radius.slot)
	local noteStroke = noteBox:FindFirstChildOfClass("UIStroke")
	if noteStroke then noteStroke.Color = T.color.activeRing end

	local bullet = Instance.new("Frame")
	bullet.Name = "Bullet"
	bullet.Size = UDim2.fromOffset(NOTE_BULLET, NOTE_BULLET)
	bullet.Position = UDim2.fromOffset(NOTE_PAD, NOTE_PAD + 3)
	bullet.BackgroundColor3 = T.color.activeRing
	bullet.BorderSizePixel = 0
	bullet.Rotation = 45
	bullet.ZIndex = bz + 1
	bullet.Parent = noteBox
	UI.corner(bullet, 2)

	local noteTextW = math.max(contentW - NOTE_PAD * 2 - NOTE_BULLET - NOTE_BULLET_GAP, 1)
	local noteText = UI.label(noteBox, "", "meta", T.color.textMutedOnDark)
	noteText.Name = "Text"
	noteText.AutomaticSize = Enum.AutomaticSize.None
	noteText.Position = UDim2.fromOffset(NOTE_PAD + NOTE_BULLET + NOTE_BULLET_GAP, NOTE_PAD)
	noteText.Size = UDim2.fromOffset(noteTextW, lineH(metaSize))
	noteText.TextWrapped = true
	noteText.TextYAlignment = Enum.TextYAlignment.Top
	noteText.ZIndex = bz + 1
	noteText.TextColor3 = T.color.textMutedOnDark   -- dark `track` ground
	setLeading(noteText)

	------------------------------------------------------------- equip CTA
	-- Step 6. READ THE HEADER BEFORE CHANGING THIS: the button is deliberately
	-- unwired, and it answers with a toast on purpose.
	--
	-- TWO buttons, not one repainted: the kit's "disabled" variant genuinely
	-- differs (Active = false, no gloss, no hard shadow, no hover tween and --
	-- the point -- no wireClick, so a locked charm's CTA cannot even make a
	-- click SOUND). Repainting one button could never reproduce that, and
	-- rebuilding per selection would churn instances on every click.
	local equipSlot, equip, equipLabel, equipShadow, equipOff, equipOffLabel
	if hasSlot then
		equipSlot = Instance.new("Frame")
		equipSlot.Name = "EquipSlot"
		equipSlot.AnchorPoint = Vector2.new(0, 1)
		equipSlot.Position = UDim2.new(0, 0, 1, 0)
		equipSlot.Size = UDim2.fromOffset(w, EQUIP_H)
		equipSlot.BackgroundTransparency = 1
		equipSlot.Visible = false
		equipSlot.ZIndex = z + 1
		equipSlot.Parent = host

		equip = UI.button(equipSlot, "", "blue", UDim2.fromOffset(w, EQUIP_H), "buttonM")
		equip.Name = "Equip"
		equip.ZIndex = equipSlot.ZIndex + 1
		equipLabel = equip:FindFirstChildOfClass("TextLabel")
		equipShadow = equipSlot:FindFirstChild("HardShadow")
		if equipShadow then equipShadow.ZIndex = equip.ZIndex - 1 end
		-- DELIBERATELY INERT. There is no charm system to call. See the header.
		equip.Activated:Connect(function()
			showToast(EQUIP_TOAST)
		end)

		equipOff = UI.button(equipSlot, "", "disabled", UDim2.fromOffset(w, EQUIP_H), "buttonM")
		equipOff.Name = "EquipLocked"
		equipOff.ZIndex = equipSlot.ZIndex + 1
		equipOff.Visible = false
		equipOffLabel = equipOff:FindFirstChildOfClass("TextLabel")
	end

	-- The first EARNABLE slot with nothing in it. Counted off CharmConfig.Slots
	-- and ctx.state.charms.equipped rather than typed, so it follows the moment
	-- anything ever populates that key -- there is no equip data in this game
	-- today, so it is slot 1 for every charm. If every earnable slot is full it
	-- falls back to the FIRST earnable one: with a full loadout, equipping means
	-- replacing, and naming the slot you would replace beats naming none.
	local function equipTargetIndex(): number?
		local eq = ctx.state.charms.equipped
		local first = nil
		for _, s in ipairs(CharmConfig.Slots) do
			if not s.Locked then
				if first == nil then first = s.Index end
				if type(eq) ~= "table" or eq[s.Index] == nil then return s.Index end
			end
		end
		return first
	end

	-- The tab LABEL for the charm's category, not the raw key -- the same string
	-- the filter tabs render. Falls back to the key for a charm whose category
	-- has no Categories entry (CharmConfig.Verify flags that, but the tag must
	-- not go blank over it).
	local function categoryLabel(charm): string
		for _, cat in ipairs(CharmConfig.Categories) do
			if cat.Key == charm.Category then return tostring(cat.Label) end
		end
		return tostring(charm.Category)
	end

	-- if-else EXPRESSION and an explicit nil test, never `was and a or b` --
	-- trap 4. Every charm in today's roster HAS a WasCalled, so the short branch
	-- is dead against live data and was tested against a stub instead.
	local function idLine(charm): string
		local id = tostring(charm.Id)
		if charm.WasCalled == nil or tostring(charm.WasCalled) == "" then
			return id
		end
		return string.format(ID_LINE_FMT, id, tostring(charm.WasCalled))
	end

	------------------------------------------------------------- render
	local lastId, lastContentH, lastRows, lastScrolls = nil, 0, 0, false
	local tight = math.floor(DET_GAP / 2)

	-- Repaints the column for `charm`, or shows the empty state for nil.
	-- Idempotent, and creates NO instance except the sigil glyph (whose shape
	-- comes from the charm), so cycling all 16 leaves the descendant count where
	-- it started.
	local function render(charm)
		if charm == nil then
			lastId, lastContentH, lastRows, lastScrolls = nil, 0, 0, false
			body.Visible = false
			empty.Visible = true
			if equipSlot then equipSlot.Visible = false end
			return
		end

		lastId = charm.Id
		empty.Visible = false
		body.Visible = true

		-- if-else EXPRESSIONS (trap 4). Same three-way treatment the locked slot
		-- card and the locked charm card already use, so "present but
		-- unavailable" reads identically in all three places.
		local locked = charm.Locked == true
		local ink = if locked then T.color.textDisabled else T.color.white
		local sub = if locked then T.color.textClaimed else T.color.textMuted

		local y = 0

		-- figure -----------------------------------------------------------
		local oldSigil = figure:FindFirstChild("Sigil")
		if oldSigil then oldSigil:Destroy() end
		local sigil = drawSigil(ctx, figure, charm.Sigil, FIG_SIGIL, bz + 1, ink)
		sigil.AnchorPoint = Vector2.new(0.5, 0)
		sigil.Position = UDim2.new(0.5, 0, 0, FIG_PAD)
		caption.Text = tostring(charm.Id)
		-- dark `track` plate: `sub` is the light-plate family, so override here
		caption.TextColor3 = if locked then T.color.textClaimed else T.color.textMutedOnDark
		figSlot.Position = UDim2.fromOffset(0, y)
		y += figH + DET_GAP

		-- tag row -----------------------------------------------------------
		catLabel.Text = categoryLabel(charm)
		local catW = math.ceil(measureText(catLabel.Text, chipSize)) + DET_TAG_PAD_X * 2
		catTag.Size = UDim2.fromOffset(catW, tagH)
		if catShadow then catShadow.Size = catTag.Size end   -- hardShadow follows Position, not Size
		catLabel.TextColor3 = T.color.textOnWindow
		-- StatusLabel, not a literal: CharmConfig owns whether a charm reads LIVE
		-- or BLOCKED, and its own comment says the detail panel's status chip must
		-- not claim a locked charm is live.
		stateLabel.Text = CharmConfig.StatusLabel(charm)
		stateLabel.Position = UDim2.fromOffset(catW + DET_TAG_GAP, 0)
		stateLabel.TextColor3 = if locked then T.color.textDisabled else T.color.textMuted
		-- Derived, NEVER a literal "/16".
		indexLabel.Text = CharmConfig.IndexLabel(charm.Id)
		indexLabel.TextColor3 = T.color.textMuted
		tagRow.Position = UDim2.fromOffset(0, y)
		y += tagH + DET_GAP

		-- identity ----------------------------------------------------------
		nameLabel.Text = tostring(charm.Name)
		local nameH = wrapHeight(nameLabel.Text, nameSize, contentW)
		nameLabel.Size = UDim2.fromOffset(contentW, nameH)
		nameLabel.Position = UDim2.fromOffset(0, y)
		nameLabel.TextColor3 = if locked then T.color.textDisabled else T.color.textOnLight   -- light plate; `ink` stays for the dark Figure sigil
		y += nameH + tight

		idLabel.Text = idLine(charm)
		idLabel.Position = UDim2.fromOffset(0, y)
		idLabel.TextColor3 = sub
		y += lineH(metaSize) + DET_GAP

		flavour.Text = tostring(charm.Flavour)
		local flavH = wrapHeight(flavour.Text, metaSize, contentW)
		flavour.Size = UDim2.fromOffset(contentW, flavH)
		flavour.Position = UDim2.fromOffset(0, y)
		flavour.TextColor3 = sub
		y += flavH + DET_GAP

		-- spec rows ---------------------------------------------------------
		local shownRows = 0
		for _, r in ipairs(rows) do
			local raw = charm[r.def.key]
			-- The ONLY omittable row. Half of today's roster has no downside, and
			-- an empty TRADE row (or a dash) would read as "downside: none decided"
			-- rather than "no downside".
			if r.def.key == "Trade" and raw == nil then
				r.frame.Visible = false
				-- and the marker with it. It lives INSIDE the hidden row so it
				-- cannot render either way, but leaving it flagged from the
				-- PREVIOUS charm makes the tree lie to anything that inspects it --
				-- which a verification pass caught it doing.
				if r.proposed then r.proposed.Visible = false end
			else
				r.frame.Visible = true
				shownRows += 1
				local text = tostring(raw or "")
				local vw = valueW
				if r.proposed then
					-- ~= false, not == true: a Trade with the flag MISSING is an
					-- unconfirmed downside too (CharmConfig.Verify calls a missing
					-- flag the failure it exists to catch), and the safe direction is
					-- to mark it rather than let it pass as settled. Identical to
					-- == true against today's data; tested both ways with a stub.
					local mark = charm.TradeProposed ~= false
					r.proposed.Visible = mark
					if mark then vw = math.max(valueW - proposedW - DET_TAG_GAP, 1) end
				end
				r.value.Text = text
				local vh = wrapHeight(text, metaSize, vw)
				r.value.Size = UDim2.fromOffset(vw, vh)
				r.value.TextColor3 = if locked then T.color.textDisabled else T.color.textOnLight   -- light plate ink
				r.label.TextColor3 = sub
				local rh = math.max(lineH(chipSize), vh) + ROW_PAD_Y * 2
				r.frame.Size = UDim2.fromOffset(contentW, rh)
				r.frame.Position = UDim2.fromOffset(0, y)
				y += rh
			end
		end
		y += DET_GAP

		-- note --------------------------------------------------------------
		local note = charm.Note
		if note ~= nil and tostring(note) ~= "" then
			noteText.Text = tostring(note)
			local nth = wrapHeight(noteText.Text, metaSize, noteTextW)
			noteText.Size = UDim2.fromOffset(noteTextW, nth)
			local nh = nth + NOTE_PAD * 2
			noteBox.Size = UDim2.fromOffset(contentW, nh)
			if noteShadow then noteShadow.Size = noteBox.Size end
			noteSlot.Size = UDim2.fromOffset(contentW, nh)
			noteSlot.Position = UDim2.fromOffset(0, y)
			noteSlot.Visible = true
			y += nh + DET_GAP
		else
			-- the WRAPPER, so the note's hard shadow goes with it
			noteSlot.Visible = false
		end

		y = math.max(y - DET_GAP, 0)   -- drop the trailing gap
		body.CanvasSize = UDim2.fromOffset(0, y)
		body.CanvasPosition = Vector2.new(0, 0)

		-- equip -------------------------------------------------------------
		if equipSlot then
			equipSlot.Visible = true
			local n = equipTargetIndex()
			local txt = ""
			if n ~= nil then txt = EQUIP_FMT:format(n) end
			if equipLabel then equipLabel.Text = txt end
			if equipOffLabel then equipOffLabel.Text = txt end
			equip.Visible = not locked
			-- UI.hardShadow does NOT mirror Visible. Without this line a locked
			-- charm leaves the live button's shadow on screen as a solid #202020
			-- bar under the disabled one.
			if equipShadow then equipShadow.Visible = not locked end
			equipOff.Visible = locked
		end

		-- Compared PRE-SCALE against the viewport, not against AbsoluteSize:
		-- everything above is in design px and the canvas is too, so mixing in a
		-- UIScale-multiplied number here would make `scrolls` wrong by ~2%.
		lastContentH, lastRows = y, shownRows
		lastScrolls = y > (surfH - DET_PAD * 2)
	end

	return {
		root = host,
		surface = surface,
		body = body,
		empty = empty,
		figure = figure,
		caption = caption,
		tagRow = tagRow,
		categoryTag = catTag,
		state = stateLabel,
		index = indexLabel,
		name = nameLabel,
		id = idLabel,
		flavour = flavour,
		rows = rows,
		noteSlot = noteSlot,
		noteBox = noteBox,
		noteText = noteText,
		equipSlot = equipSlot,
		equip = equip,
		equipLocked = equipOff,
		render = render,
		-- Exposed so the toast can be exercised without a mouse, and so Task 5
		-- (or whoever wires equipping) has the panel's own message channel rather
		-- than building a second pill.
		toast = showToast,
		metrics = function()
			return {
				surfaceW = w,
				surfaceH = surfH,
				contentW = contentW,
				labelW = labelW,
				valueW = valueW,
				proposedW = proposedW,
				figureH = figH,
				tagH = tagH,
				viewportH = surfH - DET_PAD * 2,
				contentH = lastContentH,
				rowsShown = lastRows,
				scrolls = lastScrolls,
				equipH = if hasSlot then EQUIP_H else 0,
				equipSlotIndex = equipTargetIndex(),
				selected = lastId,
			}
		end,
	}
end

---------------------------------------------------------------- Build
function CharmsPanel.Build(ctx, opts)
	local T = ctx.Tokens
	local UI = ctx.Builders
	local D = CharmConfig.Display

	-- 2026-08-11 Bag embed (user request: the Codex doorway dumped you out of
	-- the Bag's tabs). IndexPanel's exact pattern: the whole layout below is
	-- SOLVED from PANEL_W/PANEL_H, so the Bag hands its tab-body box in and
	-- everything reflows. Embedded also strips this panel's own window chrome
	-- and header -- the Bag's spec shell is the window now -- and skips the
	-- stacking-rule box so the slot row gets the full width.
	local EMBEDDED = (type(opts) == "table") and opts.embedded == true
	local WIDTH_OVERRIDE = (type(opts) == "table") and tonumber(opts.width) or nil
	local HEIGHT_OVERRIDE = (type(opts) == "table") and tonumber(opts.height) or nil

	------------------------------------------------------------- geometry
	-- PANEL_H is the one raw dimension in this file. Everything else derives
	-- from it, from PANEL_W, or from a token -- so the body regions stay
	-- consistent if the panel is ever resized.
	--   16 pad + 92 header + 12 + 108 row + 12 + 444 columns + 16 pad = 700
	local PANEL_W = WIDTH_OVERRIDE or T.size.panelWidth.charms
	local PANEL_H = HEIGHT_OVERRIDE or 700
	local PAD = T.pad.panel        -- 16, baked into UI.panel
	local GAP = T.pad.gap          -- 12
	local HEADER_H = T.size.headerHeight -- 92
	local CLOSE = 44

	local INNER_W = PANEL_W - PAD * 2
	local INNER_H = PANEL_H - PAD * 2
	local BODY_TOP = if EMBEDDED then 0 else (HEADER_H + GAP)
	local ROW_H = 108              -- slot cards AND the stacking box, so they align
	local STACK_W = 400
	-- embedded: no stacking box, the slot row takes the full inner width
	local SLOTROW_W = if EMBEDDED then INNER_W else (INNER_W - STACK_W - GAP)
	local COL_TOP = BODY_TOP + ROW_H + GAP
	local COL_H = INNER_H - COL_TOP
	local LEFT_W = math.floor((INNER_W - GAP) * 0.55)
	local RIGHT_W = INNER_W - GAP - LEFT_W

	-- Stable home for Tasks 3-5's filter / selection state. GameHUDClient's
	-- `state` table predates this panel, so the key has to be created here.
	if ctx.state.charms == nil then
		ctx.state.charms = {}
	end

	------------------------------------------------------------- root
	-- No Parent, deliberately: openPanel parents the returned Frame itself, so
	-- a throw further down leaves nothing stranded in ctx.host (file header).
	local wrapper = Instance.new("Frame")
	wrapper.Name = "CharmsPanel"
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = 10
	-- ONE NoPolish, on the ROOT, before a single label exists. UIPolish walks
	-- ancestors, so this covers the whole subtree for good -- including labels
	-- Tasks 3-5 add later, and including UIPolish's deferred second pass.
	wrapper:SetAttribute("NoPolish", true)

	local panelWindow = UI.panel(wrapper, UDim2.fromOffset(PANEL_W, PANEL_H))
	panelWindow.Name = "PanelWindow"
	panelWindow.AnchorPoint = Vector2.new(0.5, 0.5)
	panelWindow.Position = UDim2.fromScale(0.5, 0.5)
	panelWindow.ZIndex = 12
	if EMBEDDED then
		-- the Bag's spec shell is the window: strip this panel's own chrome
		-- (surface, gradient, outline, and UI.panel's sibling hard shadow --
		-- which must go WITH the surface, never linger; see the "big black
		-- square" note in the file header)
		panelWindow.BackgroundTransparency = 1
		local wg = panelWindow:FindFirstChildOfClass("UIGradient")
		if wg then wg.Enabled = false end
		local ws = panelWindow:FindFirstChildOfClass("UIStroke")
		if ws then ws.Enabled = false end
		for _, sib in ipairs(wrapper:GetChildren()) do
			if sib.Name == "HardShadow" then sib.Visible = false end
		end
	end

	------------------------------------------------------------- header
	local header = UI.surface(panelWindow, UDim2.new(1, 0, 0, HEADER_H), "header", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	header.ZIndex = 14
	local headerShadow = UI.hardShadow(header, T.shadowOffset.panel, T.radius.panel)
	-- Embedded: built anyway (labels below are referenced by name later) but
	-- never shown -- BODY_TOP is 0 so the body draws where it stood. Same
	-- build-and-hide trick IndexPanel documents for its own header.
	if EMBEDDED then
		header.Visible = false
		if headerShadow then headerShadow.Visible = false end
	end

	local kicker = UI.label(header, CharmConfig.KickerLine(), "chip", T.color.textMutedOnDark)
	kicker.Name = "Kicker"
	kicker.Position = UDim2.fromOffset(16, 16)
	kicker.ZIndex = 16

	local title = UI.label(header, D.Title, "panelTitle", T.color.white)
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 1)
	title.Position = UDim2.new(0, 16, 0, HEADER_H - 16)
	title.ZIndex = 16

	-- Right half of the header mirrors the left: LOADOUT over the composed
	-- combination line. Both come from CharmConfig, so they re-render at any
	-- roster or slot count.
	local loadoutX = -(16 + CLOSE + 16)

	-- spec sweep 2026-08-10: textMuted is dark ink now -- on this panel's dark
	-- navy header it must be white (same flip the visual pass will make on any
	-- other muted-on-dark header text it finds)
	local loadoutLabel = UI.label(header, D.LoadoutLabel, "chip", T.color.white)
	loadoutLabel.Name = "LoadoutLabel"
	loadoutLabel.AnchorPoint = Vector2.new(1, 0)
	loadoutLabel.Position = UDim2.new(1, loadoutX, 0, 16)
	loadoutLabel.TextXAlignment = Enum.TextXAlignment.Right
	loadoutLabel.ZIndex = 16

	local loadoutValue = UI.label(header, CharmConfig.LoadoutLine(), "cardLabel", T.color.white)
	loadoutValue.Name = "LoadoutValue"
	loadoutValue.AnchorPoint = Vector2.new(1, 1)
	loadoutValue.Position = UDim2.new(1, loadoutX, 0, HEADER_H - 16)
	loadoutValue.TextXAlignment = Enum.TextXAlignment.Right
	loadoutValue.ZIndex = 16

	local closeBtn = UI.button(header, "X", "red", UDim2.fromOffset(CLOSE, CLOSE), "buttonM")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -16, 0.5, 0)
	closeBtn.ZIndex = 16
	closeBtn.MouseButton1Click:Connect(function()
		ctx.closePanel()
	end)

	------------------------------------------------------------- stacking rule
	if not EMBEDDED then
		local stackBox = buildStackingRule(ctx, panelWindow, STACK_W, ROW_H)
		stackBox.Position = UDim2.new(1, 0, 0, BODY_TOP)
	end

	------------------------------------------------------------- slot row
	local slotRow = Instance.new("Frame")
	slotRow.Name = "SlotRow"
	slotRow.Position = UDim2.fromOffset(0, BODY_TOP)
	slotRow.Size = UDim2.fromOffset(SLOTROW_W, ROW_H)
	slotRow.BackgroundTransparency = 1
	slotRow.ZIndex = 14
	slotRow.Parent = panelWindow

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	rowLayout.Padding = UDim.new(0, GAP)
	rowLayout.Parent = slotRow

	-- ITERATE THE ARRAY. Never `4`: the roster is placeholder, and the card
	-- width is solved from the count so adding or removing a slot re-fits the
	-- row instead of overflowing it.
	local slotCount = #CharmConfig.Slots
	local cardW = math.floor((SLOTROW_W - GAP * math.max(slotCount - 1, 0)) / math.max(slotCount, 1))
	local slotCards = {}
	for i, slot in ipairs(CharmConfig.Slots) do
		-- pcall per card: one malformed slot entry costs one card, not the panel
		-- (see the pcall trap in the file header).
		local ok, holder = pcall(buildSlotCard, ctx, slotRow, slot, i, cardW, ROW_H)
		if ok then
			slotCards[i] = holder:FindFirstChild("Card")
		else
			warn("[CharmsPanel] slot card " .. tostring(i) .. " failed: " .. tostring(holder))
		end
	end

	------------------------------------------------------------- columns
	-- Task 3 fills LeftColumn (filter tabs + charm grid). RightColumn is still
	-- empty ON PURPOSE -- it is Task 4's detail column.
	local leftColumn = Instance.new("Frame")
	leftColumn.Name = "LeftColumn"
	leftColumn.Position = UDim2.fromOffset(0, COL_TOP)
	leftColumn.Size = UDim2.fromOffset(LEFT_W, COL_H)
	leftColumn.BackgroundTransparency = 1
	leftColumn.ZIndex = 14
	leftColumn.Parent = panelWindow

	-- pcall'd for the same reason the slot loop is: a malformed roster must
	-- cost the grid, not the whole panel (openPanel swallows a Build throw and
	-- can leave a scrim with nothing under it -- see the file header). On
	-- failure the Task 4 contract is still published, as inert stubs, so the
	-- detail column gets `false` and `{}` rather than a nil-index crash.
	local okGrid, charmGrid = pcall(buildCharmGrid, ctx, leftColumn, LEFT_W, COL_H)
	if not okGrid then
		warn("[CharmsPanel] charm grid failed to build: " .. tostring(charmGrid))
		charmGrid = {
			cards = {},
			setSelected = function() return false end,
			setFilter = function() return false end,
			getSelected = function() return nil end,
			getFilter = function() return nil end,
			metrics = function() return {} end,
		}
	end

	-- Published so Task 4 never has to reach into this function's locals.
	-- Same table both ways -- see the contract block in the file header.
	local charms = ctx.state.charms
	charms.cards = charmGrid.cards
	charms.setSelected = charmGrid.setSelected
	charms.setFilter = charmGrid.setFilter
	charms.getSelected = charmGrid.getSelected
	charms.getFilter = charmGrid.getFilter
	charms.metrics = charmGrid.metrics
	charms.drawSigil = drawSigil
	charms.grid = charmGrid

	local rightColumn = Instance.new("Frame")
	rightColumn.Name = "RightColumn"
	rightColumn.AnchorPoint = Vector2.new(1, 0)
	rightColumn.Position = UDim2.new(1, 0, 0, COL_TOP)
	rightColumn.Size = UDim2.fromOffset(RIGHT_W, COL_H)
	rightColumn.BackgroundTransparency = 1
	rightColumn.ZIndex = 14
	rightColumn.Parent = panelWindow

	------------------------------------------------------------- detail column
	-- The toast lives on the WRAPPER, not in a column, so it draws over the
	-- whole window. Built before the column because the column's EQUIP button
	-- closes over it.
	local okToast, showToast = pcall(buildToast, ctx, wrapper)
	if not okToast then
		warn("[CharmsPanel] toast failed to build: " .. tostring(showToast))
		showToast = function() end   -- inert, so the EQUIP handler can never throw
	end

	-- pcall'd for the same reason the grid is: a malformed roster must cost the
	-- detail column, not the whole panel (openPanel swallows a Build throw and
	-- can leave a scrim with nothing under it -- see the file header). On
	-- failure the contract is still published as an inert stub.
	local okDetail, charmDetail = pcall(buildDetailColumn, ctx, rightColumn, RIGHT_W, COL_H, showToast)
	if not okDetail then
		warn("[CharmsPanel] detail column failed to build: " .. tostring(charmDetail))
		charmDetail = {
			render = function() end,
			metrics = function() return {} end,
			rows = {},
		}
	end
	charms.detail = charmDetail

	-- The ONE line that connects the two columns. The grid pcalls this on every
	-- selection CHANGE and never on a refusal, so a locked or filtered-out card
	-- cannot drive the detail column, and a filter that hides the selection
	-- arrives here as (nil, nil) -- i.e. back to the empty state.
	charms.onSelect = function(charm, _id)
		charmDetail.render(charm)
	end

	-- First paint. Task 3 starts with nothing selected, so this is the empty
	-- state -- but it is READ from the grid rather than assumed, so a future
	-- task that seeds a selection gets a populated column with no edit here.
	local seeded = nil
	if type(charms.getSelected) == "function" then
		local okSel, id = pcall(charms.getSelected)
		if okSel and type(id) == "string" then seeded = CharmConfig.CharmById(id) end
	end
	pcall(charmDetail.render, seeded)

	return wrapper
end

return CharmsPanel
