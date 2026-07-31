-- Transparent Luck HUD: shows total luck multiplier; tap to expand the source breakdown
-- + which rarities your current setup can reach at full power.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")
local RockConfig = require(modules:WaitForChild("RockConfig"))
local RarityConfig = require(modules:WaitForChild("RarityConfig"))
local UpgradeConfig = require(modules:WaitForChild("UpgradeConfig"))
local RebirthConfig = require(modules:WaitForChild("RebirthConfig"))
local OfferingConfig = require(modules:WaitForChild("OfferingConfig"))
local BrainrotConfig = require(modules:WaitForChild("BrainrotConfig"))
local RarityCurve = require(modules:WaitForChild("RarityCurve"))
local UITheme = require(modules:WaitForChild("UITheme"))
local P = UITheme.Palette
local CF = UITheme.Camp

local rockById = {}
for _, rock in ipairs(RockConfig) do rockById[rock.Id] = rock end

-- Pets that buff throw luck while PLACED (BrainrotConfig.LuckMult). Same rule as
-- ThrowHandler's petLuckByName -- keep the two in sync or this panel starts lying.
local petLuckByName = {}
for _, e in ipairs(BrainrotConfig) do
	if e.LuckMult then petLuckByName[e.Name] = e.LuckMult end
end

local state = { EquippedRock = "Pebble", Upgrades = {}, Rebirths = 0, Offerings = 0, Brainrots = {} }

-- =====================================================================
-- LUCK IS TWO SEPARATE SYSTEMS NOW (ServerScriptService.Modules.ThrowHandler).
-- This panel used to show one "TOTAL" that multiplied all four sources together,
-- which is no longer true of anything the server does:
--
--   RARITY luck  -- shifts WHICH BRAINROT you catch.
--     accessLuck = rock x Lucky Charm x Offerings x placed-pets x (perfect ? 1.075 : 1)
--     Distance UNLOCKS higher tiers and weights the odds; accessLuck shifts the
--     RarityCurve toward the top. Nothing is guaranteed. REBIRTH LUCK IS NOT IN THIS.
--
--   MUTATION luck -- decides whether it comes out Golden / Diamond.
--     boost = WeatherMut x clamp(rebirthLuck x weatherLuck, 1, 6)
--     passed straight into Mutations.Roll(boost, weatherName).
--
-- Rebirth luck moved from the first to the second. Showing it as "luck" next to
-- the rock would tell a player their rebirths buy tier access; they do not.
-- =====================================================================

-- Mirrors of ThrowHandler's constants. Duplicated rather than shared because a
-- LocalScript cannot require ServerScriptService -- if ThrowHandler retunes these,
-- this panel starts lying, so they are listed together and named identically.
local PERFECT_DISTANCE_MULT = 1.1
local PERFECT_LUCK_MULT = 1.075
local MAX_TOTAL_DISTANCE = 900
local PROMO_DIVISOR = 4.0     -- promoChance = clamp((accessLuck - 1) / this, 0, cap)
local PROMO_MAX = 0.90
local PROMO_DECAY = 0.45      -- each further promotion is this much likelier to fail
local MAX_PROMOTIONS = 3
local MUT_BOOST_CAP = 6       -- clamp(rebirthLuck * weatherLuck, 1, 6)

-- same descending scan as RarityRoll.TierIndexForDistance: the HIGHEST tier whose
-- MinDistance your raw throw clears. (Kept as a scan, not a table, so a retuned
-- RarityConfig needs no change here.)
local function tierIndexForDistance(distance)
	for i = #RarityConfig, 1, -1 do
		if distance >= RarityConfig[i].MinDistance then return i end
	end
	return 1
end

local gui = Instance.new("ScreenGui")
gui.Name = "LuckHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 7
gui.Parent = player:WaitForChild("PlayerGui")

-- collapsed chip (bottom-right, above the sprint button)
local chip = Instance.new("TextButton")
chip.Name = "LuckChip"
chip.AnchorPoint = Vector2.new(1, 1)
chip.Position = UDim2.new(1, -14, 1, -78)
-- NOTE: deliberately kept in the ORIGINAL dark-navy HUD colours (user preference);
-- do NOT convert this chip to the campfire palette like the rest of the UI.
chip.Size = UDim2.new(0, 128, 0, 34)
chip.BackgroundColor3 = P.white
chip.BorderSizePixel = 0
chip.Text = ""                      -- the text lives in a CHILD label; see below
chip.AutoButtonColor = true
chip.Parent = gui
UITheme.corner(chip, 10)
UITheme.gradient(chip, P.hudDark1, P.hudDark2, 90)
UITheme.stroke(chip, P.outline, 2)

-- A UIGradient tints the parent GuiObject's TEXT as well as its background, so a
-- dark gradient on a TextButton renders its own label dark-on-dark (the emoji goes
-- black too). Keeping the label as a CHILD means the gradient only paints the body.
local chipLabel = Instance.new("TextLabel")
chipLabel.Name = "Label"
chipLabel.Size = UDim2.fromScale(1, 1)
chipLabel.BackgroundTransparency = 1
chipLabel.Font = Enum.Font.GothamBold
chipLabel.TextSize = 15
chipLabel.TextColor3 = P.text
chipLabel.Text = "\u{1F340} Luck \u{00D7}1.00"
chipLabel.ZIndex = (chip.ZIndex or 1) + 1
chipLabel.Parent = chip

-- expanded breakdown panel
local panel = Instance.new("Frame")
panel.Name = "LuckPanel"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -260, 1, -118)   -- shifted left, clear of the quest tracker band
panel.Size = UDim2.new(0, 278, 0, 396)
panel.BackgroundColor3 = P.white
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
UITheme.campPanel(panel)
UITheme.corner(panel, 16)

-- small carved-wood ribbon overhanging the panel top
local ribbon, title = UITheme.ribbon(panel, "\u{1F340} YOUR LUCK", 0.84)
title.TextSize = 17

-- A ScrollingFrame rather than a plain Frame: the breakdown is now two sections
-- plus the rarity table, and the old fixed Frame silently CLIPPED anything past
-- its height. Scrolling means a future extra source, or a short phone screen,
-- hides nothing.
local listFrame = Instance.new("ScrollingFrame")
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.Position = UDim2.new(0, 12, 0, 44)
listFrame.Size = UDim2.new(1, -24, 1, -56)
listFrame.CanvasSize = UDim2.new()
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.ScrollBarThickness = 4
listFrame.ScrollBarImageColor3 = CF.wood1
listFrame.ZIndex = 2
listFrame.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

local rowCount = 0
local function addRow(leftText, rightText, leftColor, rightColor, bold)
	rowCount += 1
	local row = Instance.new("Frame")
	row.Name = "Row" .. rowCount
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 18)   -- 8px gutter so the scrollbar never sits on the numbers
	row.LayoutOrder = rowCount
	row.Parent = listFrame
	local l = Instance.new("TextLabel")
	l.Name = "L"
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(0.62, 0, 1, 0)
	l.Font = bold and Enum.Font.FredokaOne or Enum.Font.GothamMedium
	l.TextSize = 13
	l.TextColor3 = leftColor or CF.muted
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = leftText
	l.Parent = row
	local ls = Instance.new("UIStroke")
	ls.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ls.Color = CF.ink; ls.Thickness = 1.8; ls.Transparency = 0; ls.Parent = l
	local r = Instance.new("TextLabel")
	r.Name = "R"
	r.BackgroundTransparency = 1
	r.AnchorPoint = Vector2.new(1, 0)
	r.Position = UDim2.new(1, 0, 0, 0)
	r.Size = UDim2.new(0.38, 0, 1, 0)
	r.Font = bold and Enum.Font.FredokaOne or Enum.Font.GothamMedium
	r.TextSize = 13
	r.TextColor3 = rightColor or CF.cream
	r.TextXAlignment = Enum.TextXAlignment.Right
	r.Text = rightText
	r.Parent = row
	local rs = Instance.new("UIStroke")
	rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	rs.Color = CF.ink; rs.Thickness = 1.8; rs.Transparency = 0; rs.Parent = r
	return row
end

local function clearRows()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	rowCount = 0
end

local DIM = Color3.fromRGB(128, 110, 94)

local function spacerRow()
	local sp = addRow("", "")
	sp.Size = UDim2.new(1, -8, 0, 6)
	return sp
end

-- a short muted caption under a section heading
local function noteRow(text)
	local r = addRow(text, "", CF.muted, CF.muted)
	r.Size = UDim2.new(1, -8, 0, 15)
	return r
end

local function refresh()
	local rock = rockById[state.EquippedRock] or rockById["Pebble"]
	local upgradeLuck = UpgradeConfig.Mult(state.Upgrades, "Luck")
	local offeringLuck = OfferingConfig.LuckMult(state.Offerings or 0)
	local petLuck = 1
	for _, e in ipairs(state.Brainrots or {}) do
		if e.PadIndex and petLuckByName[e.Name] then petLuck *= petLuckByName[e.Name] end
	end
	local rebirthLuck = RebirthConfig.LuckMult(state.Rebirths or 0)
	local weatherLuck = ReplicatedStorage:GetAttribute("WeatherLuck") or 1
	local weatherMut = ReplicatedStorage:GetAttribute("WeatherMut") or 1

	-- RARITY luck == ThrowHandler's accessLuck, minus the perfect bonus (which is
	-- per-throw, so it gets its own row instead of being folded into the headline).
	local rarityLuck = rock.Luck * upgradeLuck * offeringLuck * petLuck
	-- MUTATION luck == the boost ThrowHandler hands Mutations.Roll.
	local rebirthWeather = math.clamp(rebirthLuck * weatherLuck, 1, MUT_BOOST_CAP)
	local mutBoost = weatherMut * rebirthWeather

	-- The chip shows RARITY luck: it is the number that decides what you catch, and
	-- multiplying it by the mutation boost would produce a figure the server never
	-- computes. (Chip styling is deliberately untouched -- see the note above.)
	chipLabel.Text = ("\u{1F340} Luck \u{00D7}%.2f"):format(rarityLuck)
	local boosted = rarityLuck > 1.0001 or mutBoost > 1.0001
	chipLabel.TextColor3 = boosted and P.cashText or P.text

	if not panel.Visible then return end
	clearRows()

	--=================== 1. what you catch ==============================--
	addRow("RARITY LUCK", ("\u{00D7}%.2f"):format(rarityLuck), CF.amber1, CF.amber1, true)
	noteRow("which brainrot you catch")
	addRow("Rock (" .. rock.Id .. ")", ("\u{00D7}%.2f"):format(rock.Luck))
	addRow("Lucky Charm upgrade", ("\u{00D7}%.2f"):format(upgradeLuck))
	addRow("Offerings (" .. tostring(math.floor(state.Offerings or 0)) .. ")",
		("\u{00D7}%.2f"):format(offeringLuck),
		offeringLuck > 1.0001 and CF.ember1 or nil,
		offeringLuck > 1.0001 and CF.ember1 or nil)
	if petLuck > 1.0001 then
		addRow("Pets on base", ("\u{00D7}%.2f"):format(petLuck), CF.pine1, CF.pine1)
	end
	addRow("Perfect throw", ("\u{00D7}%.3f"):format(PERFECT_LUCK_MULT), CF.muted, CF.muted)

	spacerRow()

	--=================== 2. what it comes out as ========================--
	addRow("MUTATION LUCK", ("\u{00D7}%.2f"):format(mutBoost), CF.berry1, CF.berry1, true)
	noteRow("golden / diamond odds")
	addRow("Rebirths (" .. tostring(math.floor(state.Rebirths or 0)) .. ")",
		("\u{00D7}%.2f"):format(rebirthLuck),
		rebirthLuck > 1.0001 and CF.berry1 or nil,
		rebirthLuck > 1.0001 and CF.berry1 or nil)
	local weatherName = ReplicatedStorage:GetAttribute("WeatherName")
	local wLabel = (weatherName and weatherName ~= "" and weatherName ~= "Clear") and ("Weather (" .. weatherName .. ")") or "Weather"
	addRow(wLabel, ("\u{00D7}%.2f"):format(weatherLuck), weatherLuck > 1 and CF.lake1 or nil, weatherLuck > 1 and CF.lake1 or nil)
	if weatherMut > 1.0001 then
		addRow("Event mutation", ("\u{00D7}%.2f"):format(weatherMut), CF.lake1, CF.lake1)
	end
	if rebirthLuck * weatherLuck > MUT_BOOST_CAP + 0.0001 then
		noteRow(("capped at \u{00D7}%d"):format(MUT_BOOST_CAP))
	end

	spacerRow()

	--=================== 3. your best throw's odds =====================--
	-- Distance = power x rock.MaxDistance x Power upgrade x rebirth power x (perfect 1.1),
	-- clamped to MAX_TOTAL_DISTANCE. At that best throw, RarityCurve turns distance + luck
	-- into a probability per tier -- the SAME curve the server rolls (RarityCurve).
	local bestDist = math.min(
		rock.MaxDistance
			* UpgradeConfig.Mult(state.Upgrades, "Power")
			* RebirthConfig.PowerMult(state.Rebirths or 0)
			* PERFECT_DISTANCE_MULT,
		MAX_TOTAL_DISTANCE)
	local bestLuck = rarityLuck * PERFECT_LUCK_MULT
	local probs = RarityCurve.Probabilities(bestDist, bestLuck)

	addRow("BEST THROW", ("%dm odds"):format(math.floor(bestDist)), CF.amber1, CF.amber1, true)
	noteRow("chance per catch at full power")
	for i, tier in ipairs(RarityConfig) do
		local pct = (probs[i] or 0) * 100
		local rightTxt, rightCol
		if tier.MaxDistance == math.huge then
			-- God is off the curve: Pete is an independent 1-in-a-million on top throws
			rightTxt, rightCol = "1 in a million", DIM
		elseif pct <= 0 then
			-- not unlocked yet -- you must throw at least this far for any chance
			rightTxt, rightCol = ("%dm \u{1F512}"):format(math.ceil(tier.MinDistance)), DIM
		elseif pct >= 1 then
			rightTxt, rightCol = ("%.1f%%"):format(pct), CF.pine1
		elseif pct >= 0.01 then
			rightTxt, rightCol = ("%.2f%%"):format(pct), CF.pine1
		else
			rightTxt, rightCol = "<0.01%", DIM
		end
		addRow(tier.Name, rightTxt, tier.Color, rightCol)
	end
end

chip.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
	refresh()
end)

remotes.DataUpdated.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.EquippedRock then state.EquippedRock = data.EquippedRock end
	if data.Upgrades then state.Upgrades = data.Upgrades end
	if data.Rebirths ~= nil then state.Rebirths = data.Rebirths end
	if data.Offerings ~= nil then state.Offerings = data.Offerings end
	if data.Brainrots then state.Brainrots = data.Brainrots end
	refresh()
end)

ReplicatedStorage:GetAttributeChangedSignal("WeatherLuck"):Connect(refresh)
ReplicatedStorage:GetAttributeChangedSignal("WeatherName"):Connect(refresh)
-- WeatherMut is the event's own mutation boost and moves independently of
-- WeatherLuck, so it needs its own listener or the MUTATION LUCK total goes stale.
ReplicatedStorage:GetAttributeChangedSignal("WeatherMut"):Connect(refresh)

task.spawn(function()
	local ok, snapshot = pcall(function()
		return remotes.GetInitialData:InvokeServer()
	end)
	if ok and typeof(snapshot) == "table" then
		state.EquippedRock = snapshot.EquippedRock or state.EquippedRock
		state.Upgrades = snapshot.Upgrades or state.Upgrades
		state.Rebirths = snapshot.Rebirths or state.Rebirths
		state.Offerings = snapshot.Offerings or state.Offerings
		state.Brainrots = snapshot.Brainrots or state.Brainrots
	end
	refresh()
end)
