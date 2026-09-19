--[[ PetAbilityHelp -- the Bag's "WHAT ABILITIES DO" reference sheet.
------------------------------------------------------------------------------
Every pet carries ONE signature ability (PetConfig.ABILITY_KINDS), and an
ability a player cannot look up is a stat they will not use. This is the
lookup: all six kinds, in PetConfig.ABILITY_ORDER, each with its one-line
plain-English Detail and the pets that carry it.

THE COPY LIVES IN PetConfig, NOT HERE. Label/Detail are read straight off
ABILITY_KINDS and the carrier list is derived from PetConfig.Pets, so adding a
pet or retuning an ability updates this screen with no edit to this file.

EVERYTHING IS AutomaticSize.Y (2026-08-22 fix). The first cut gave every row a
fixed 104px and every label a fixed height, so the moment a description or a
carrier list wrapped to a second line it overflowed its row and collided with
the next one -- and the intro was clipped against the top edge. Fixed heights
cannot work here: the text length depends on how many pets carry a kind, which
changes whenever the roster does. Every label sizes to its own wrapped text and
every row sizes to its labels, so the sheet is correct at any roster size.
For that to hold, each label MUST keep a fixed X and a zero Y
(Size = UDim2.new(1, 0, 0, 0)) with TextWrapped on -- give one a fixed height
again and it clips exactly like before.

WHY THIS IS A SEPARATE MODULE: BackpackPanel is past the 200,000-character
ceiling on Source writes, so it can only be edited in small surgical patches.
It takes its UI kit through `opts` rather than requiring anything itself.

Build(opts) -> Frame (already parented). opts:
  parent      the pet well to cover
  UI, T, S    the panel's own UIKit builders, tokens and spec theme
  PetConfig   ReplicatedStorage.Modules.PetConfig
  trimNum     the panel's number formatter
  pad         well padding, so the sheet insets like the grid does
]]

local PetAbilityHelp = {}

-- Drawn as an OPAQUE sheet over the grid rather than replacing it: the caller
-- keeps building its tiles underneath, which costs one wasted layout pass and
-- buys not having to wrap ~90 lines of tile building in a conditional. ZIndex
-- 30+ clears the pet tiles, which top out at 21.
local Z = 30

function PetAbilityHelp.Build(opts)
	local parent = opts.parent
	local UI, T, S = opts.UI, opts.T, opts.S
	local PetConfig = opts.PetConfig
	local trimNum = opts.trimNum or function(v) return string.format("%.2f", v) end

	local sheet = Instance.new("Frame")
	sheet.Name = "AbilityHelp"
	sheet.Size = UDim2.fromScale(1, 1)
	sheet.BackgroundColor3 = Color3.fromHex("EEF2F8")
	sheet.BorderSizePixel = 0
	sheet.ZIndex = Z
	sheet.Parent = parent
	UI.corner(sheet, 16)

	local list = Instance.new("ScrollingFrame")
	list.Name = "HelpList"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 10
	list.ScrollBarImageColor3 = Color3.fromHex("3A4356")
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ElasticBehavior = Enum.ElasticBehavior.Never
	list.ZIndex = Z + 1
	list.Parent = sheet

	-- 16 all round, and 18 at the top: the intro used to start hard against the
	-- sheet's edge and read as cut off (owner screenshot, 2026-08-22).
	local lp = Instance.new("UIPadding")
	lp.PaddingTop = UDim.new(0, 18)
	lp.PaddingBottom = UDim.new(0, 16)
	lp.PaddingLeft = UDim.new(0, 16)
	-- right pad clears the scrollbar as well as the edge
	lp.PaddingRight = UDim.new(0, 16 + 10)
	lp.Parent = list

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Fixed X, zero Y, wrapped, AutomaticSize.Y -- see the header note.
	local function label(host, name, text, size, colour, order)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Font = S.Font.Shout
		t.TextSize = size
		t.TextColor3 = colour
		t.Text = text
		t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextYAlignment = Enum.TextYAlignment.Top
		t.Size = UDim2.new(1, 0, 0, 0)
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.LayoutOrder = order or 0
		t.ZIndex = Z + 3
		-- NoPolish: UIPolish repaints unflagged labels, and this sheet picks its
		-- own ink against the light well
		t:SetAttribute("NoPolish", true)
		t.Parent = host
		return t
	end

	-- THE STACKING RULE IS THE HEADLINE: it is the one thing not visible on a
	-- single pet's card, and it is what makes equipping five of one pet a real
	-- strategy rather than a mistake.
	label(list, "Intro",
		"Every pet has ONE ability. Equipped pets add their abilities together, " ..
		"and equipping several copies of the same pet adds it again each time.",
		16, T.color.textOnLight, 0)

	for i, kindKey in ipairs(PetConfig.ABILITY_ORDER) do
		local kd = PetConfig.ABILITY_KINDS[kindKey]
		if kd then
			-- WHO CARRIES IT, strongest first -- the sheet has to answer "which pet
			-- do I need for this", not just "what does the word mean". Names and
			-- amounts only: the first cut also printed each pet's ability NAME here
			-- and that doubled the length of every one of these lines for nothing
			-- (the name is on the pet's own card).
			local carriers = {}
			for _, d in pairs(PetConfig.Pets) do
				local ab = d.Ability
				-- `Hidden` skips unobtainable pets (TestAcorn). RETIRED pets are NOT
				-- skipped: players still own them, so they still need to look up what
				-- the thing in their bag actually does.
				if ab and ab.Kind == kindKey and not d.Hidden then
					carriers[#carriers + 1] = { name = d.Name, amt = tonumber(ab.Amount) or 0 }
				end
			end
			table.sort(carriers, function(x, y)
				if x.amt ~= y.amt then return x.amt > y.amt end
				return tostring(x.name) < tostring(y.name)
			end)
			local names = {}
			for _, c in ipairs(carriers) do
				names[#names + 1] = ("%s +%s"):format(c.name, trimNum(c.amt))
			end

			local row = Instance.new("Frame")
			row.Name = "Help" .. kindKey
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, 0)
			row.AutomaticSize = Enum.AutomaticSize.Y
			row.BackgroundColor3 = Color3.fromHex("E4EAF2")
			row.BorderSizePixel = 0
			row.ZIndex = Z + 2
			row.Parent = list
			UI.corner(row, 12)

			local rp = Instance.new("UIPadding")
			rp.PaddingLeft = UDim.new(0, 14)
			rp.PaddingRight = UDim.new(0, 14)
			rp.PaddingTop = UDim.new(0, 12)
			rp.PaddingBottom = UDim.new(0, 12)
			rp.Parent = row

			local rl = Instance.new("UIListLayout")
			rl.Padding = UDim.new(0, 6)
			rl.SortOrder = Enum.SortOrder.LayoutOrder
			rl.Parent = row

			label(row, "Kind", string.upper(kd.Label), 19, T.color.textOnLight, 1)
			label(row, "Detail", kd.Detail or kd.Blurb or "", 15, T.color.textOnLight, 2)
			label(row, "Carriers", "PETS: " .. table.concat(names, "   \u{2022}   "), 13,
				T.color.textMuted, 3)
		end
	end

	return sheet
end

return PetAbilityHelp
