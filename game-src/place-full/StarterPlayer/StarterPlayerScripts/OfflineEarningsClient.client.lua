-- "While you were away" popup: asks the server for any pending offline payout once ready
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local offlineRemote = remotes:WaitForChild("OfflineEarnings")
local SoundKit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundKit")) -- SFX2

-- PS99 white-chrome small-modal palette (2026-08-18 restyle; campfire pack retired here)
local WHITE = Color3.fromRGB(255, 255, 255)
local EDGE = Color3.fromRGB(216, 224, 234) -- #D8E0EA soft grey-blue keyline
-- (the CYAN_TOP/CYAN_BOT header-band pair retired 2026-08-26 with the band --
-- see the title block in showPopup)
local INK = Color3.fromRGB(51, 65, 79) -- #33414F dark ink (reward amount)
local NAVY = Color3.fromRGB(49, 61, 79) -- #313D4F bubble-text stroke
local MUTED = Color3.fromRGB(124, 140, 160) -- #7C8CA0 secondary line
local GREEN_TOP = Color3.fromRGB(99, 222, 67) -- #63DE43 candy button top
local GREEN_BOT = Color3.fromRGB(49, 168, 36) -- #31A824 candy button bottom
local GREEN_EDGE = Color3.fromRGB(36, 122, 24) -- darker candy rim
local BUBBLE = Enum.Font.LuckiestGuy -- the spec "Shout" face (same as GameHUDClient)
local BODY = Enum.Font.GothamMedium

-- canonical abbreviator, K through Qi -- see Modules.NumberFormat
local formatNumber = require(ReplicatedStorage.Modules.NumberFormat).Short
local SideRail = require(ReplicatedStorage.Modules.SideRail) -- single-open coordination

local function formatDuration(sec)
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	if h > 0 then return ("%dh %dm"):format(h, m) end
	if m > 0 then return ("%dm"):format(m) end
	return ("%ds"):format(sec)
end

local gui = Instance.new("ScreenGui")
gui.Name = "OfflineEarningsUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

-- === BACKDROP BLUR (2026-08-26) ==============================================
-- BLUR, NEVER DIM -- the house rule since the 2026-08-17 polish loop, and this
-- card was the last surface still without one. It floated over a fully vivid
-- world and, at join, over the still-open daily calendar, with nothing at all
-- separating the three layers.
--
-- Same recipe every other surface clones from GameHUDClient's HUDPanelBlur:
-- create at Size 10 on open, :Destroy() on close. NEVER TWEEN A BlurEffect
-- PROPERTY -- TweenService silently no-ops on non-GuiObjects in this place.
-- Its OWN name, so it can never fight the shared HUDPanelBlur or another
-- surface's layer.
local BLUR_NAME = "OfflineEarningsBlur"
local function setBlur(on)
	local Lighting = game:GetService("Lighting")
	local existing = Lighting:FindFirstChild(BLUR_NAME)
	if on and not existing then
		local blur = Instance.new("BlurEffect")
		blur.Name = BLUR_NAME
		blur.Size = 10
		blur.Parent = Lighting
	elseif not on and existing then
		existing:Destroy()
	end
end

local function showPopup(payload)
	-- 400x208 fixed is phone-safe as-is: 400px sits inside a 667px landscape
	-- viewport with ~130px of margin a side, so no Platform-aware shrink --
	-- phones want bigger type, not a smaller card. (236 until the 64px header
	-- band came off on 2026-08-26 -- see the title block below.)
	local REST_POS = UDim2.new(0.5, 0, 0.42, 0)

	local card = Instance.new("Frame")
	card.Name = "OfflineCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = REST_POS + UDim2.fromOffset(0, 24) -- entrance start; tweened to REST_POS below
	card.Size = UDim2.new(0, 400, 0, 208)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.ZIndex = 10
	-- ONE NoPolish on the root, set before any label exists: this card paints
	-- dark ink on a white ground, which UIPolish would force-whiten into
	-- white-on-white. (UIPolish honours the attribute on any ancestor.)
	card:SetAttribute("NoPolish", true)
	card.Parent = gui

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 18)
	cardCorner.Parent = card
	local cardEdge = Instance.new("UIStroke")
	cardEdge.Color = EDGE
	cardEdge.Thickness = 2.5
	cardEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cardEdge.LineJoinMode = Enum.LineJoinMode.Round
	cardEdge.Parent = card
	-- Single-open, so opening anything puts this away instead of leaving it
	-- floating over the top. Costs the player nothing: the server has ALREADY
	-- banked the payout by the time it sends the message this popup is built
	-- from -- COLLECT only plays a sound and dismisses the card.
	SideRail.registerPanel(card)
	setBlur(true)

	-- SideRail's close() HIDES rather than destroys, and it can fire without
	-- dismiss() ever running -- so the blur has to come off the card's own
	-- Visible, not only off the dismiss path, or it outlives the card it was
	-- separating. (Exactly the leak shape that stranded the quest tracker; see
	-- SideRail.register's AncestryChanged note.)
	card:GetPropertyChangedSignal("Visible"):Connect(function()
		if not card.Visible then setBlur(false) end
	end)

	-- ENTRANCE: a Position rise. The old UIScale tween was a proven silent
	-- no-op in this place (the card snapped); GuiObject Position tweens are on
	-- the proven path.
	TweenService:Create(card, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = REST_POS }):Play()

	-- === TITLE: THE HOUSE TREATMENT, NOT A COLOURED SLAB (2026-08-26) =========
	-- This card used to wear a full-bleed cyan header band (plus a square-off
	-- patch to kill the band's own bottom rounding). Beside the daily calendar it
	-- stacks over at join, that slab was the one thing that read as a DIFFERENT
	-- GAME: everything else in the PS99 chrome is a white shell with colour used
	-- as an accent, never as a full-width field.
	--
	-- PanelChrome.shell's own field-study note is the pattern being matched here,
	-- scaled to a small modal: "titles are WHITE bubble text with the dark
	-- outline, sitting ON the shell's top border -- no band, no coloured ink.
	-- Identity lives in the corner sticker." So: sticker top-left, overhanging
	-- and tilted like the nav rail's, and the title straddling the card's edge.
	-- Losing the 64px band is what took the card from 236 to 208.
	local STICKER_W = 56
	local sticker = Instance.new("TextLabel")
	sticker.Name = "Sticker"
	sticker.BackgroundTransparency = 1
	sticker.AnchorPoint = Vector2.new(0, 0.5)
	sticker.Position = UDim2.new(0, 6, 0, 2)   -- straddles the top edge with the title
	sticker.Size = UDim2.fromOffset(STICKER_W, STICKER_W)
	sticker.Font = BUBBLE
	sticker.TextScaled = true
	sticker.Text = "\u{1F4B0}"                 -- moneybag: the card pays CASH
	sticker.Rotation = -8                      -- nav-rail sticker tilt
	sticker.ZIndex = 12
	-- Colour emoji ignore UIStroke, legacy TextStroke AND the game-wide UIPolish
	-- sweep (all three probed as no-ops), so it rides bare with its own art.
	sticker:SetAttribute("NoPolish", true)
	sticker.Parent = card

	local hx = 6 + STICKER_W + 10
	local header = Instance.new("TextLabel")
	header.Name = "Title"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -(hx + 14), 0, 56)
	header.Position = UDim2.new(0, hx, 0, -26)  -- baseline straddles the shell edge
	header.Font = BUBBLE
	header.TextSize = 24
	header.TextColor3 = WHITE
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = "WHILE YOU WERE AWAY"
	header.ZIndex = 12
	header.Parent = card
	-- The stroke is doing real work now: white bubble text over the card's edge
	-- is half on white and half on the blurred world behind it.
	local headerStroke = Instance.new("UIStroke")
	headerStroke.Color = NAVY
	headerStroke.Thickness = 2.5
	headerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	headerStroke.LineJoinMode = Enum.LineJoinMode.Round
	headerStroke.Parent = header

	-- AMOUNT: big dark ink, not gold. Gold is reserved for Robux game-wide
	-- (2026-08-17 polish loop) and cash counts went white -- but white on this
	-- white card would vanish, so the reward reads as ink on the light ground.
	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 1
	amount.Size = UDim2.new(1, -32, 0, 52)
	amount.Position = UDim2.new(0, 16, 0, 28)
	amount.Font = BUBBLE
	amount.TextSize = 42
	amount.TextColor3 = INK
	amount.Text = "+$" .. formatNumber(payload.Payout)
	amount.ZIndex = 12
	amount.Parent = card

	local detail = Instance.new("TextLabel")
	detail.BackgroundTransparency = 1
	detail.Size = UDim2.new(1, -40, 0, 44)
	detail.Position = UDim2.new(0, 20, 0, 86)
	detail.Font = BODY
	detail.TextSize = 13
	detail.TextColor3 = MUTED
	detail.TextWrapped = true
	local txt = ("Your camp earned cash for %s."):format(formatDuration(payload.Seconds))
	if payload.Capped then
		txt ..= " (Cap reached \u{2014} upgrade Camp Keeper at Enzo's to earn longer!)"
	end
	detail.Text = txt
	detail.ZIndex = 12
	detail.Parent = card

	-- COLLECT: hand-built candy-green pill (PanelChrome's look without the
	-- import). GOTCHA (2026-08-14): a UIGradient on a TextButton multiplies its
	-- GLYPHS too, so the gradient lives on the button and the label is a child.
	local ok = Instance.new("TextButton")
	ok.Name = "Collect"
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.new(0.5, 0, 1, -14)
	ok.Size = UDim2.new(0, 176, 0, 46)
	ok.Text = ""
	ok.AutoButtonColor = false
	ok.BackgroundColor3 = GREEN_TOP
	ok.BorderSizePixel = 0
	ok.ZIndex = 12
	ok.Parent = card
	local okCorner = Instance.new("UICorner")
	okCorner.CornerRadius = UDim.new(0, 23) -- full pill on a 46px-tall button
	okCorner.Parent = ok
	local okGrad = Instance.new("UIGradient")
	okGrad.Color = ColorSequence.new(GREEN_TOP, GREEN_BOT)
	okGrad.Rotation = 90
	okGrad.Parent = ok
	local okEdge = Instance.new("UIStroke")
	okEdge.Color = GREEN_EDGE
	okEdge.Thickness = 2
	okEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	okEdge.LineJoinMode = Enum.LineJoinMode.Round
	okEdge.Parent = ok

	local okLabel = Instance.new("TextLabel")
	okLabel.Name = "Label"
	okLabel.BackgroundTransparency = 1
	okLabel.Size = UDim2.new(1, -12, 1, 0)
	okLabel.Position = UDim2.new(0, 6, 0, 0)
	okLabel.Font = BUBBLE
	okLabel.TextSize = 19
	okLabel.TextColor3 = WHITE
	okLabel.Text = "COLLECT!"
	okLabel.ZIndex = 13
	okLabel.Parent = ok
	local okLabelStroke = Instance.new("UIStroke")
	okLabelStroke.Color = NAVY
	okLabelStroke.Thickness = 2
	okLabelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	okLabelStroke.LineJoinMode = Enum.LineJoinMode.Round
	okLabelStroke.Parent = okLabel

	-- === AUTO-DISMISS ==========================================================
	-- The card closes itself after AUTO_SECONDS; COLLECT closes it at once. It is a
	-- receipt, not a decision -- the server banked the payout before it ever sent the
	-- message this card is built from, so nothing is lost by it going away on its own,
	-- and it used to sit over the top of whatever the player did next (it was on screen
	-- underneath an NPC dialogue box).
	--
	-- Guarded by `closed` because THREE things can end this card and any two can race:
	-- the button, the timer, and SideRail putting it away when another panel opens.
	local AUTO_SECONDS = 5
	local closed = false

	local function dismiss(withSound)
		if closed then return end
		closed = true
		-- BEFORE the card.Parent bail below: SideRail may already have taken the
		-- card, and the blur must come off on every route out, not just the two
		-- that reach the tween.
		setBlur(false)
		if withSound then SoundKit.play("cash", nil, { volume = 0.25 }) end -- SFX2
		if not card.Parent then return end   -- SideRail already took it
		-- Position drop, not a UIScale shrink: UIScale tweens are silent no-ops
		-- in this place, and Completed on one is not a wait worth trusting
		local tw = TweenService:Create(card,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = REST_POS + UDim2.fromOffset(0, 20) })
		tw:Play()
		tw.Completed:Wait()
		card:Destroy()
	end

	ok.MouseButton1Click:Connect(function() dismiss(true) end)

	-- The countdown is ON the button rather than a separate label: a card that vanishes
	-- with no warning reads as a glitch, and this way the only new text sits where the
	-- player is already looking for the thing to press.
	task.spawn(function()
		for left = AUTO_SECONDS, 1, -1 do
			if closed or not card.Parent then return end
			okLabel.Text = ("COLLECT!  (%d)"):format(left)
			task.wait(1)
		end
		dismiss(false)   -- timed out: no flourish, it was not a decision
	end)
end

offlineRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.Payout) ~= "number" then return end
	SoundKit.play("panelOpen", nil, { volume = 0.15 }) -- SFX2
	showPopup(payload)
end)

-- tell the server we're ready to receive the pending payout (if any)
--
-- The 2s is unchanged and still load-bearing: OfflineEarningsHandler.OnJoin has
-- to have PARKED the payload before this asks for it, or the request finds
-- nothing and the card never shows.
task.wait(2)

-- SEQUENCED BEHIND THE DAILY CALENDAR (2026-08-07 user decision). The daily
-- reward is now the first thing on screen at join, and this receipt follows it
-- instead of landing on top of it -- these two used to race, and SideRail's
-- single-open meant whichever lost simply vanished.
--
-- GameHUDClient sets IntroDailyDone once the calendar is finished with, by any
-- route: claimed, dismissed (it auto-claims), or skipped entirely because there
-- was nothing to claim today. An ATTRIBUTE rather than an event so arriving late
-- is not a lost handoff -- if it is already set we simply do not wait.
--
-- THE TIMEOUT IS THE IMPORTANT PART. If GameHUDClient never reports in, the
-- player still gets their card; waiting forever on a UI handshake is not worth a
-- payout receipt. (The money itself was banked at join either way -- see the
-- note by showPopup.)
local INTRO_ATTR = "IntroDailyDone"
local INTRO_TIMEOUT = 30

local waited = 0
while not player:GetAttribute(INTRO_ATTR) and waited < INTRO_TIMEOUT do
	task.wait(0.2)
	waited += 0.2
end

-- a beat, so the calendar closing and this card popping read as a sequence
-- rather than one surface swapping for another mid-animation
task.wait(0.4)
offlineRemote:FireServer()
