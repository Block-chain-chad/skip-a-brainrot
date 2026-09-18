-- IceFishingClient -- banner, walk-up prompt and cast feedback for the World-2 TUNDRA
-- event (Cfg.EVENT_NAME is what the banner says; the internal names stay IceFishing*).
--
-- The server (IceFishingEvent) owns the freeze, the holes and the catch. This owns the
-- OFFER: stand near a hole and a FISH HERE button appears in the same slot the dock's
-- throw button uses, and ONE press casts. There is no hold and no ProximityPrompt --
-- walking up is the whole interaction, exactly like walking onto the dock.
--
-- Payload shapes it handles on IceFishingState:
--   { Warning=true, StartsAt=epoch, Seconds=n }   blizzard incoming countdown
--   { Active=true,  EndsAt=epoch }                lake frozen, show the window timer
--   { Active=false }                              thawed, clear everything
--   { Casting=true, Lead=n }                      the cast is in the air, nothing to click yet
--   { Minigame=true, GreenMin, GreenMax, MarkerPeriod, Step, Steps, Rarity }  one reel step
--   { Catch=descriptor, Rarity, RockId=id }       hooked it -- card + full reveal chain
--   { GotAway=true }                              missed the green / timed out -- it escaped
--   { Cancelled=true }                            walked away / out of range / event ended
-- It fires IceFishingCast (no args) to CAST the line, then IceFishingReel(markerFrac) when
-- you click to hook. The server picks the nearest hole, owns the green and judges the
-- click, so a spoofed payload buys nothing.
--
-- NoPolish is set on the root so the game-wide UIPolish pass does not repaint the icy
-- text white (the documented escape hatch for colour-coded UI).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = remotes:WaitForChild("IceFishingState")
local castRemote = remotes:WaitForChild("IceFishingCast")
local reelRemote = remotes:WaitForChild("IceFishingReel")
local cancelRemote = remotes:WaitForChild("IceFishingCancel")
-- Issues the PERFECT-cast sweet-spot band. WaitForChild with a timeout, not forever: the
-- server only creates it in IceFishingEvent.Init, and if it is somehow absent the charge
-- simply never offers a perfect rather than the whole script yielding here at load.
local sweetRemote = remotes:WaitForChild("IceFishingSweetSpot", 10)

-- CATCH FEEDBACK (2026-09-17): the burst, the per-tier sting, the pop and the cuts for a
-- landed fish all run in StarterPlayerScripts.RevealRouter, off this same IceFishingState
-- remote, so a fish and a thrown catch can never drift apart. This client keeps the
-- minigame and the corner card only. (It used to call CatchCue + MassiveEmergence +
-- PullCeremony itself; those two ceremony modules are retired.)
local Cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("IceFishingConfig"))
local SoundKit = require(ReplicatedStorage.Modules:WaitForChild("SoundKit"))

-- ===== CAST AUDIO, LIFTED FROM THE ROCK THROW ================================
-- Fishing shipped completely silent apart from the catch sting, which is why the loop
-- felt dead next to skipping a rock. These are ClientMain's OWN four cues and its own
-- levels, not new ones picked by ear -- a cast is the same gesture as a throw, so it
-- should sound like one:
--   charge   throwCharge, a sustained bed pitched up as the meter fills
--   release  wheelWind, the commit -- its own voice, louder than the bed
--   perfect  catchBigHit + catchSparkle, the same stack a perfect throw pops
-- The splash and the bite live in RodFxClient instead, because those are world events
-- everyone at the hole should hear, not private UI feedback.
--
-- Do not retune these in isolation: ClientMain's comment block records why the bed is
-- 0.12 against a 0.38 release and why the ramp is 0.90-1.42 rather than wider. If one
-- moves, both should.
local CHARGE_PITCH_LO, CHARGE_PITCH_HI = 0.90, 1.42
local CHARGE_VOL, RELEASE_VOL, CHARGE_FADE = 0.12, 0.38, 0.12
local chargeLoop = nil
local function stopChargeLoop()
	if chargeLoop then
		chargeLoop:stop(CHARGE_FADE)
		chargeLoop = nil
	end
end


-- 2026-08-14 OLIVE REVERT (owner: colours back to the olive/army palette for
-- shops, passes and event warnings). The EVENT ANNOUNCEMENT banner goes olive.
--
-- Deliberately its OWN constants rather than a retint of ICE_* above: those
-- three still dress the cast panel, the bite offer and the hole markers, which
-- are ice-fishing GAMEPLAY UI and have to keep reading as ice. Only the
-- "BLIZZARD INCOMING / ICE FISHING OPEN" chrome is an event warning.
local EV_GROUND = Color3.fromRGB(27, 33, 20)    -- #1B2114 olive track (was ICE_DARK)
local EV_EDGE   = Color3.fromRGB(122, 138, 102) -- #7A8A66 olive tab (was ICE_EDGE icy blue)
local EV_TEXT   = Color3.fromRGB(255, 255, 255) -- white title (was ICE_TEXT 212,238,255)
local EV_SUB    = Color3.fromRGB(201, 214, 180) -- #C9D6B4 olive muted (was ICE_EDGE)

local gui = Instance.new("ScreenGui")
gui.Name = "IceFishingUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui:SetAttribute("NoPolish", true)
gui.Parent = player:WaitForChild("PlayerGui")

local function rounded(obj, px)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, px); c.Parent = obj
end
local function stroke(obj, col, th)
	local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th; s.Parent = obj
end

-- ===== top banner ============================================================
local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 14)
banner.Size = UDim2.fromOffset(440, 62)
banner.BackgroundColor3 = EV_GROUND
banner.BackgroundTransparency = 0.08
banner.Visible = false
banner.Parent = gui
rounded(banner, 14)
stroke(banner, EV_EDGE, 2)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 0, 0, 8)
title.Size = UDim2.new(1, 0, 0, 26)
title.Font = Enum.Font.FredokaOne
title.TextSize = 22
title.TextColor3 = EV_TEXT
title.Text = ""
title.Parent = banner

local sub = Instance.new("TextLabel")
sub.BackgroundTransparency = 1
sub.Position = UDim2.new(0, 0, 0, 34)
sub.Size = UDim2.new(1, 0, 0, 22)
sub.Font = Enum.Font.GothamMedium
sub.TextSize = 15
sub.TextColor3 = EV_SUB
sub.Text = ""
sub.Parent = banner

-- ===== chrome: THE SAME LANGUAGE AS THE ROCK-SKIPPING BAR ====================
-- These two panels used to be bespoke frosted-ice boxes, which made ice fishing look
-- like a different game's HUD sitting in the same screen corner as the throw bar. They
-- are now built from the SAME parts as ThrowFrame, through the SAME module: UIStyle
-- corners and Border-mode keylines, the brown panel gradient, the dark inset track, the
-- gold fill, the green band and the gloss strip across the top. Values below are read
-- off the authored ThrowFrame so the two are literally the same colours, not a match by
-- eye -- see ClientMain's "Sticker pass" for the keyline recipe this mirrors.
local UIStyle = require(ReplicatedStorage.Modules:WaitForChild("UIStyle"))
local C3 = Color3.fromRGB
local WHITE    = C3(255, 255, 255)
local PANEL_A  = { light = C3(205, 132, 58), dark = C3(178, 104, 40), outline = C3(62, 34, 19) }
local TRACK_A  = { light = C3(58, 39, 26),   dark = C3(30, 20, 13),   outline = C3(62, 34, 19) }
local BAND_A   = { light = C3(146, 214, 122), dark = C3(54, 140, 76), outline = C3(62, 34, 19) }
local LEAVE_A  = { light = C3(255, 120, 105), dark = C3(220, 60, 55), outline = C3(130, 25, 20) }
local GOLD     = C3(255, 200, 60)
local DARK_RIM = C3(62, 34, 19)

-- the authored gloss: a white strip over the top 42%, fading 0.86 -> fully clear
local function gloss(parent, radius)
	local g = Instance.new("Frame")
	g.Name = "Gloss"
	g.AnchorPoint = Vector2.new(0.5, 0)
	g.Position = UDim2.new(0.5, 0, 0, 3)
	g.Size = UDim2.new(1, -10, 0.42, 0)
	g.BackgroundColor3 = WHITE
	g.BorderSizePixel = 0
	g.ZIndex = 1
	g.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = g
	local gg = Instance.new("UIGradient")
	gg.Name = "GlossGrad"
	gg.Rotation = 90
	gg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1),
	})
	gg.Parent = g
	return g
end

-- ClientMain's keyline, verbatim in spirit: one corner and one white Border stroke that
-- we own by name, so nothing else can quietly win the radius.
local function keyline(o, thickness, radius)
	if radius then UIStyle.corner(o, radius) else UIStyle.pill(o) end
	UIStyle.stroke(o, WHITE, thickness)
end

local function panel(name, w, h, parent)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 1, -110)   -- ThrowFrame's own slot
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = WHITE                -- the gradient supplies the colour
	f.Visible = false
	f.Parent = parent
	UIStyle.gradient(f, PANEL_A)
	keyline(f, 3.5, 20)
	gloss(f, 20)
	return f
end

-- the dark inset the fill/marker runs in: a pill, exactly like BarBackground
local function inset(parent, w, h, y)
	local t = Instance.new("Frame")
	t.Name = "Track"
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, y)
	t.Size = UDim2.fromOffset(w, h)
	t.BackgroundColor3 = WHITE
	t.BorderSizePixel = 0
	t.ZIndex = 2
	t.Parent = parent
	UIStyle.gradient(t, TRACK_A)
	keyline(t, 2.5)
	return t
end

-- chunky white FredokaOne with the house outline, the way every other title is set
local function panelTitle(parent, y, text)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 0, 0, y)
	l.Size = UDim2.new(1, 0, 0, 24)
	l.Font = Enum.Font.FredokaOne
	l.TextSize = 18
	l.TextColor3 = WHITE
	l.ZIndex = 3
	l.Text = text
	l.Parent = parent
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = DARK_RIM
	s.Thickness = 2.5
	s.Parent = l
	return l
end

-- ===== the offer / charge bar, in the dock's throw-button slot ===============
-- 340 x 72, the same footprint as ThrowFrame, because it stands in the same slot and
-- does the same job: hold to wind up, release to commit.
local offer = panel("FishOffer", 340, 72, gui)
local hint = panelTitle(offer, 8, "\u{1F3A3} HOLD TO CAST")
local chargeTrack = inset(offer, 300, 18, 40)

-- gold fill, the same gold the throw's power bar uses
local chargeFill = Instance.new("Frame")
chargeFill.Name = "ChargeFill"
chargeFill.AnchorPoint = Vector2.new(0, 0.5)
chargeFill.Position = UDim2.new(0, 0, 0.5, 0)
chargeFill.Size = UDim2.new(0, 0, 1, 0)
chargeFill.BackgroundColor3 = GOLD
chargeFill.BorderSizePixel = 0
chargeFill.ZIndex = 3
chargeFill.Visible = false
chargeFill.Parent = chargeTrack
UIStyle.pill(chargeFill)
gloss(chargeFill, 9)

-- the PERFECT-cast sweet spot. GREEN, not gold -- the throw's perfect band is green and
-- its fill is gold, and swapping those round here is exactly the kind of near-miss that
-- makes two screens feel like two games. The SERVER decides where it sits
-- (IceFishingSweetSpot); the client only draws it.
local perfectBand = Instance.new("Frame")
perfectBand.Name = "PerfectBand"
perfectBand.AnchorPoint = Vector2.new(0, 0.5)
perfectBand.Position = UDim2.new(0.6, 0, 0.5, 0)
perfectBand.Size = UDim2.new(0.1, 0, 1, 0)
perfectBand.BackgroundColor3 = WHITE
perfectBand.BorderSizePixel = 0
perfectBand.ZIndex = 4
perfectBand.Visible = false
perfectBand.Parent = chargeTrack
UIStyle.gradient(perfectBand, BAND_A)
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = perfectBand
	local s = Instance.new("UIStroke"); s.Color = DARK_RIM; s.Thickness = 2; s.Parent = perfectBand
end

-- ===== cast bar (same slot as the offer; only ever one of them is up) ========
local cast = panel("Cast", 420, 112, gui)
local castLabel = panelTitle(cast, 10, "Casting\u{2026}")
local track = inset(cast, 380, 26, 44)

-- the BITE zone, in the throw band's green so "the good window" is one colour across
-- both games' bars. The core is the exact centre, which is what you aim at once the
-- zone starts shrinking on the later reel steps.
local green = Instance.new("Frame")
green.Name = "Green"
green.BackgroundColor3 = WHITE
green.Position = UDim2.new(0.4, 0, 0, 0)
green.Size = UDim2.new(0.2, 0, 1, 0)
green.BorderSizePixel = 0
green.ZIndex = 3
green.Visible = false
green.Parent = track
UIStyle.gradient(green, BAND_A)
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = green
	local s = Instance.new("UIStroke"); s.Color = DARK_RIM; s.Thickness = 2; s.Parent = green
end

local greenCore = Instance.new("Frame")
greenCore.Name = "Core"
greenCore.AnchorPoint = Vector2.new(0.5, 0.5)
greenCore.Position = UDim2.new(0.5, 0, 0.5, 0)
greenCore.Size = UDim2.new(0, 2, 0.6, 0)
greenCore.BackgroundColor3 = C3(232, 255, 236)
greenCore.BackgroundTransparency = 0.35
greenCore.BorderSizePixel = 0
greenCore.ZIndex = 4
greenCore.Parent = green
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 1); c.Parent = greenCore end

-- a white wash over the track, flashed on a good pull so a hit is FELT
local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = WHITE
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 7
flash.Parent = track
UIStyle.pill(flash)

-- THE WAY OUT. Without this the only exit from a cast was to wait out the full 7-second
-- hook timeout -- and then the walk-up loop re-cast at you before you could take two
-- steps. A GuiButton rather than a key alone so it works on touch and, more importantly,
-- so the exit is VISIBLE: a lock you cannot see a way out of reads as a bug. Red, which
-- is the house accent for anything that cancels.
local leaveButton = Instance.new("TextButton")
leaveButton.Name = "LeaveButton"
leaveButton.AnchorPoint = Vector2.new(1, 0)
leaveButton.Position = UDim2.new(1, -12, 0, 78)
leaveButton.Size = UDim2.fromOffset(104, 26)
leaveButton.Text = "\u{2715} LEAVE (Q)"
leaveButton.TextSize = 14
leaveButton.Font = Enum.Font.FredokaOne
leaveButton.TextColor3 = WHITE
leaveButton.BackgroundColor3 = WHITE
leaveButton.AutoButtonColor = false
leaveButton.Visible = false
leaveButton.ZIndex = 5
leaveButton.Parent = cast
UIStyle.gradient(leaveButton, LEAVE_A)
keyline(leaveButton, 2.5, 12)
do
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = LEAVE_A.outline
	s.Thickness = 2
	s.Parent = leaveButton
end
pcall(UIStyle.attachHoverPress, leaveButton, true)

-- REEL PIPS: one per click the fish needs, filled as you land them. A multi-step fish
-- used to announce itself only as "REEL 2 / 3" in the label, which is the kind of thing
-- you read once and stop seeing; pips stay legible while you are watching the marker.
local pips = Instance.new("Frame")
pips.Name = "Pips"
pips.AnchorPoint = Vector2.new(0, 0)
pips.Position = UDim2.new(0, 20, 0, 80)
pips.Size = UDim2.fromOffset(200, 12)
pips.BackgroundTransparency = 1
pips.ZIndex = 3
pips.Visible = false
pips.Parent = cast
do
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Left
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.Padding = UDim.new(0, 6)
	lay.Parent = pips
end

-- the sweeping marker: a white needle with a head, so the hit point is a thin bright
-- line and not a slab whose edges are all equally plausible
local marker = Instance.new("Frame")
marker.Name = "Marker"
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Position = UDim2.new(0.5, 0, 0.5, 0)
marker.Size = UDim2.new(0, 4, 1.75, 0)
marker.BackgroundColor3 = WHITE
marker.BorderSizePixel = 0
marker.ZIndex = 6
marker.Visible = false
marker.Parent = track
UIStyle.pill(marker)
do local s = Instance.new("UIStroke"); s.Color = DARK_RIM; s.Thickness = 1.5; s.Parent = marker end
local markerHead = Instance.new("Frame")
markerHead.Name = "Head"
markerHead.AnchorPoint = Vector2.new(0.5, 1)
markerHead.Position = UDim2.new(0.5, 0, 0, -2)
markerHead.Size = UDim2.fromOffset(12, 12)
markerHead.BackgroundColor3 = GOLD
markerHead.BorderSizePixel = 0
markerHead.Rotation = 45
markerHead.ZIndex = 6
markerHead.Parent = marker
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 3); c.Parent = markerHead
	local s = Instance.new("UIStroke"); s.Color = DARK_RIM; s.Thickness = 1.5; s.Parent = markerHead
end

-- Flash the track white and let it fall off. Tweened on the CLIENT, so it runs at render
-- rate regardless of what the server is doing.
local function flashTrack()
	flash.BackgroundTransparency = 0.35
	TweenService:Create(flash, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
end

-- Reel pips: one per click the fish needs, filled as you land them. A multi-step fish
-- used to announce itself only as "REEL 2 / 3" in the label, which is the kind of thing
-- you read once and then stop seeing; pips stay legible in peripheral vision while you
-- are actually watching the marker. Hidden for a one-click fish -- a single lonely pip
-- says nothing the bar does not already say.
local pipList = {}
local function setPips(step, steps)
	steps = steps or 1
	step = step or 1
	if steps <= 1 then pips.Visible = false; return end
	if #pipList ~= steps then
		for _, d in ipairs(pipList) do d:Destroy() end
		pipList = {}
		for i = 1, steps do
			local d = Instance.new("Frame")
			d.Name = "Pip" .. i
			d.Size = UDim2.fromOffset(10, 10)
			d.BorderSizePixel = 0
			d.BackgroundColor3 = C3(30, 20, 13)
			d.LayoutOrder = i
			d.Parent = pips
			rounded(d, 5)
			stroke(d, DARK_RIM, 1.5)
			pipList[i] = d
		end
	end
	for i, d in ipairs(pipList) do
		if i < step then
			d.BackgroundColor3 = C3(146, 214, 122)     -- landed
		elseif i == step then
			d.BackgroundColor3 = GOLD     -- the live target
		else
			d.BackgroundColor3 = Color3.fromRGB(18, 34, 56)       -- still to come
		end
	end
	pips.Visible = true
end

-- ===== state =================================================================
local eventActive = false
local casting = false
local nearHole = false
local lastCastAt = 0
-- Set when the player BACKS OUT by hand. While it is set the walk-up loop will not cast
-- at them again, so leaving actually means leaving instead of being re-hooked on the spot.
-- Cleared the moment they step out of range, so walking back up fishes normally again --
-- and Q re-arms it without moving, for someone who changed their mind.
local declined = false
-- charge-to-cast state: the meter fills while you hold, and releasing casts the line
local charging = false
-- PERFECT-cast band drawn from the server-issued sweet spot: { min, max } or nil while we
-- have not fetched one (bandPending guards against firing the request every frame).
local sweetBand = nil
local bandPending = false

-- hook-minigame state: the marker sweep, whether a click currently counts as a reel, and
-- where the marker was last frame (the fraction we report on a reel).
local castToken = 0
local sweepConn
local minigameArmed = false
local markerFrac = 0.5
local function stopSweep()
	if sweepConn then sweepConn:Disconnect(); sweepConn = nil end
	minigameArmed = false
end

local countdownConn
local function stopCountdown()
	if countdownConn then countdownConn:Disconnect(); countdownConn = nil end
end

local function mmss(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- ===== casting ===============================================================
-- Fired by the walk-up loop, never by a button. resolvedAt is stamped whenever a fish is
-- landed or lost so the next cast waits RECAST_WAIT rather than snapping straight back
-- out on the same frame the reveal appears.
local resolvedAt = 0

local function tryCast(power)
	if not eventActive or casting or not nearHole then return end
	-- a takeover cut is playing (Takeover sets RevealActive for the catcher; spec S11)
	if player:GetAttribute("RevealActive") == true then return end
	if os.clock() - lastCastAt < 0.6 then return end
	if os.clock() - resolvedAt < Cfg.RECAST_WAIT then return end
	declined = false
	lastCastAt = os.clock()
	castRemote:FireServer(power)   -- power carried for future use; the server ignores it for now
end

-- Back out of a cast: line in, rod away, movement back. The server does the actual
-- unlocking (it owns the Fishing attribute), so this only asks and marks the intent --
-- `declined` is what stops the walk-up loop simply re-casting on the next frame.
local function leaveFishing()
	if not casting then return end
	declined = true
	resolvedAt = os.clock()
	cancelRemote:FireServer()
end

-- Q / LEAVE backs out of a cast in flight. With charge-to-cast there is nothing to "opt
-- back into" -- you just hold to cast again -- so this only leaves; it never casts.
local function toggleFishing()
	if casting then leaveFishing() end
end

leaveButton.MouseButton1Click:Connect(leaveFishing)
ContextActionService:BindAction("IceFishLeave", function(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if not eventActive or not nearHole then return Enum.ContextActionResult.Pass end
	toggleFishing()
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)

-- ===== charge-to-cast ========================================================
-- Hold (E / R2 / mouse / touch) to wind up -- ChargeFill fills over CAST_CHARGE_TIME --
-- and release to cast the line. A mis-tap released under MIN_CAST_POWER does not cast.
local castPower = 0
local chargeConn
local function stopCharge()
	if chargeConn then chargeConn:Disconnect(); chargeConn = nil end
	stopChargeLoop()
	charging = false
	castPower = 0
	chargeFill.Visible = false
	chargeFill.Size = UDim2.new(0, 0, 1, 0)
end

-- Ask the server for this charge's sweet-spot band and draw it on the meter. Fetched once
-- per cast cycle -- cleared when a cast fires (showCasting) or when you leave the hole -- and
-- the server rolls a fresh single-use band each time, so a stale or replayed band is simply
-- not judged perfect. A pcall so a mid-event teardown of the RemoteFunction never errors here.
local function drawBand()
	if not sweetBand then return end
	perfectBand.Position = UDim2.new(sweetBand.min, 0, 0.5, 0)
	perfectBand.Size = UDim2.new(math.max(0.02, sweetBand.max - sweetBand.min), 0, 1, 0)
end
local function requestBand()
	if sweetBand or bandPending or not sweetRemote then return end
	bandPending = true
	task.spawn(function()
		local ok, res = pcall(function() return sweetRemote:InvokeServer() end)
		bandPending = false
		if ok and type(res) == "table" and tonumber(res.min) and tonumber(res.max) then
			sweetBand = { min = res.min, max = res.max }
			drawBand()
		end
	end)
end
local function clearBand()
	sweetBand = nil
	perfectBand.Visible = false
end

local function startCharge()
	if charging or casting or not eventActive or not nearHole then return end
	if os.clock() - resolvedAt < Cfg.RECAST_WAIT then return end   -- a fish just resolved
	if os.clock() - lastCastAt < 0.5 then return end
	charging = true
	castPower = 0
	stopChargeLoop()   -- never stack two beds if a charge somehow re-enters
	chargeLoop = SoundKit.loop("throwCharge", { volume = CHARGE_VOL, speed = CHARGE_PITCH_LO })
	chargeFill.Visible = true
	local t0 = os.clock()
	if chargeConn then chargeConn:Disconnect() end
	chargeConn = RunService.RenderStepped:Connect(function()
		if not charging then return end
		castPower = math.clamp((os.clock() - t0) / (Cfg.CAST_CHARGE_TIME or 0.85), 0, 1)
		chargeFill.Size = UDim2.new(castPower, 0, 1, 0)
		-- same geometric ramp as the throw, so the ear reads the fill the same way
		if chargeLoop then
			chargeLoop:setSpeed(CHARGE_PITCH_LO * (CHARGE_PITCH_HI / CHARGE_PITCH_LO) ^ castPower)
		end
	end)
end

local function releaseCast()
	if not charging then return end
	local power = castPower
	stopCharge()
	if power >= (Cfg.MIN_CAST_POWER or 0.15) and nearHole and not casting and eventActive then
		-- a cast is a commitment with no cancel, same as a throw, so it gets the same voice
		SoundKit.play("wheelWind", nil, { volume = RELEASE_VOL })
		tryCast(power)   -- server runs the cast-lead beat, then opens the hook minigame
	end
end

-- E / R2 are bound only while standing at a hole (see the Heartbeat), so they do nothing
-- elsewhere; mouse and touch are gated on nearHole here instead.
local chargeBound = false
local function setChargeBound(on)
	if on == chargeBound then return end
	chargeBound = on
	if on then
		ContextActionService:BindAction("IceFishCharge", function(_, state)
			if state == Enum.UserInputState.Begin then startCharge()
			elseif state == Enum.UserInputState.End then releaseCast() end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonR2)
	else
		ContextActionService:UnbindAction("IceFishCharge")
		if charging then stopCharge() end
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if nearHole and not casting then startCharge() end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		releaseCast()
	end
end)

-- ===== finding the holes =====================================================
-- The rig is server-built and replicates, so the pools are simply parts named
-- FishingHole under SkipArea.IceFishing. The list is rebuilt on a slow timer rather
-- than cached once: StreamingEnabled means holes stream in and out as you cross the
-- lake, and a list captured at freeze time would go stale the first time one unloaded.
local holes = {}
local function rigFolder()
	local gw = workspace:FindFirstChild("GameWorld")
	local ft = gw and gw:FindFirstChild("FrozenTundra")
	local sa = ft and ft:FindFirstChild("SkipArea")
	return sa and sa:FindFirstChild(Cfg.RIG_FOLDER)
end

local function refreshHoles()
	holes = {}
	local folder = rigFolder()
	if not folder then return end
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("BasePart") and c.Name == "FishingHole" then
			table.insert(holes, c)
		end
	end
end

task.spawn(function()
	while true do
		if eventActive then refreshHoles() end
		task.wait(1)
	end
end)

-- Flat distance: the pool part's origin is the middle of a column that runs under the
-- waterline, so a 3D distance reads several studs long for someone stood on the rim.
local function nearestDistance(pos)
	local best = math.huge
	for _, h in ipairs(holes) do
		if h.Parent then
			local d = h.Position - pos
			local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
			if flat < best then best = flat end
		end
	end
	return best
end

-- WALK UP AND YOU ARE FISHING. `dwell` is how long you have been continuously in range:
-- casting on the first frame in range would fire at everyone who merely sprints past a
-- hole, and then immediately cancel when they left. A third of a second of standing there
-- is the difference between arriving and passing through.
local dwell = 0
RunService.Heartbeat:Connect(function(dt)
	local want = false
	if eventActive then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and #holes > 0 then
			want = nearestDistance(hrp.Position) <= Cfg.HOLE_REACH
		end
	end
	nearHole = want
	dwell = want and (dwell + dt) or 0

	-- STEPPING AWAY IS WHAT RE-ARMS IT. Clearing `declined` here rather than on a timer is
	-- what makes backing out mean something: stay at the hole and it leaves you alone, walk
	-- off and come back and it fishes normally again.
	--
	-- Gated on actually KNOWING where the holes are, and on a margin past HOLE_REACH. `want`
	-- also goes false whenever the hole list is momentarily empty -- StreamingEnabled churns
	-- it, and the list is only rebuilt once a second -- so clearing on a bare `not want`
	-- silently un-declined a player who had not moved an inch, and the loop would re-hook
	-- them. Measured: standing still for five seconds after backing out was enough to see it.
	if #holes > 0 and not want then
		local hrp2 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp2 and nearestDistance(hrp2.Position) > Cfg.HOLE_REACH + 6 then
			declined = false
			clearBand()   -- drop the stale band; a fresh one is fetched when you walk back up
		end
	end

	-- the label only fills the gap between casts; while one is running the cast panel
	-- occupies the same slot and says something more useful
	local showLabel = want and not casting
	if offer.Visible ~= showLabel then offer.Visible = showLabel end
	if showLabel then
		requestBand()   -- prefetch this charge's sweet spot so it is drawn before you release
		local inBand = charging and sweetBand ~= nil
			and castPower >= sweetBand.min and castPower <= sweetBand.max
		local txt
		if charging then
			txt = inBand and "\u{1F3A3} NOW \u{2014} release!" or "\u{1F3A3} winding up\u{2026} release to cast!"
		else
			txt = "\u{1F3A3} hold to cast"
		end
		if hint.Text ~= txt then hint.Text = txt end
		local col = inBand and Color3.fromRGB(255, 224, 120) or Color3.fromRGB(226, 244, 255)
		if hint.TextColor3 ~= col then hint.TextColor3 = col end
	end
	perfectBand.Visible = showLabel and (sweetBand ~= nil)

	-- charge is only holdable while standing at a hole and not already in a cast
	setChargeBound(want and not casting)
end)

-- ===== banner / cast feedback ================================================
local function showActive(endsAt)
	stopCountdown()
	banner.Visible = true
	title.Text = "\u{2744}\u{FE0F} " .. Cfg.EVENT_NAME .. " \u{2014} ICE FISHING OPEN"
	countdownConn = RunService.Heartbeat:Connect(function()
		local left = endsAt - os.time()
		if left <= 0 then sub.Text = "the lake is thawing\u{2026}"
		else sub.Text = "walk onto the lake \u{2022} " .. mmss(left) .. " left" end
	end)
end

local function showWarning(startsAt)
	stopCountdown()
	banner.Visible = true
	title.Text = "\u{2744}\u{FE0F} " .. Cfg.EVENT_NAME .. " INCOMING"
	countdownConn = RunService.Heartbeat:Connect(function()
		local left = startsAt - os.time()
		if left <= 0 then
			sub.Text = "the lake is freezing over\u{2026}"
		else
			sub.Text = "the lake freezes over in " .. mmss(left)
		end
	end)
end

local function hideAll()
	stopCountdown()
	stopSweep()
	stopCharge()
	clearBand()
	setChargeBound(false)
	banner.Visible = false
	cast.Visible = false
	green.Visible = false
	marker.Visible = false
	offer.Visible = false
	leaveButton.Visible = false
	nearHole = false
	casting = false
	declined = false
	dwell = 0
	holes = {}
end

-- CAST_LEAD's worth of dead air between the press and the float landing: ClientMain is
-- posing the reach, wind-back and flick, and there is nothing to click yet. Holding the
-- panel here is also what stops a second press starting a second cast -- `casting` does
-- not go true until the minigame arrives otherwise.
local function showCasting(perfect)
	pips.Visible = false
	castToken += 1
	casting = true
	stopSweep()
	clearBand()                     -- this cast consumed the band; re-fetch when you re-arm
	offer.Visible = false
	green.Visible = false
	marker.Visible = false
	cast.Visible = true
	leaveButton.Visible = true      -- the exit is offered from the very first frame
	if perfect then
		-- the throw's own perfect stack (ClientMain showPerfectPop): an impact to land it
		-- plus a bright sparkle over the top, and deliberately louder than the release
		SoundKit.play("catchBigHit", nil, { volume = 0.5 })
		SoundKit.play("catchSparkle", nil, { volume = 0.42, speed = 1.12 })
		castLabel.Text = "\u{2728} PERFECT CAST \u{2014} 2\u{00D7} LUCK!"
		castLabel.TextColor3 = C3(176, 240, 150)
	else
		castLabel.Text = "Casting\u{2026}"
		castLabel.TextColor3 = WHITE
	end
end

-- Marker sweeps 0 -> 1 -> 0 over MARKER_PERIOD; click when it is over the green to hook.
local function beginMinigame(greenMin, greenMax, period, step, steps, rarity)
	castToken += 1
	local mine = castToken
	casting = true
	offer.Visible = false
	cast.Visible = true
	leaveButton.Visible = true
	-- multi-step fish (higher rarity) show a REEL counter; a single-click fish keeps it simple
	if steps and steps > 1 then
		castLabel.Text = ("REEL  %d / %d"):format(step or 1, steps)
	else
		castLabel.Text = "HIT THE GREEN!"
	end
	castLabel.TextColor3 = WHITE
	green.Position = UDim2.new(greenMin, 0, 0, 0)
	green.Size = UDim2.new(math.max(0.02, greenMax - greenMin), 0, 1, 0)
	green.Visible = true
	marker.Visible = true
	setPips(step, steps)
	-- A step past the first only happens because the PREVIOUS pull landed, so this is the
	-- confirmation for that pull. Without it the only feedback for a good click is the green
	-- shrinking under you, which reads as the target getting harder rather than as a win.
	if (step or 1) > 1 then flashTrack() end

	period = period or 1.5
	local startClock = os.clock() - math.random() * period   -- random start phase
	stopSweep()
	sweepConn = RunService.RenderStepped:Connect(function()
		if castToken ~= mine then return end
		local ph = ((os.clock() - startClock) % period) / period
		markerFrac = (ph < 0.5) and (ph * 2) or (2 - ph * 2)
		marker.Position = UDim2.new(markerFrac, 0, 0.5, 0)
	end)
	-- arm the click a beat later, so the same press that cast the line can't reel instantly
	task.delay(0.18, function()
		if castToken == mine then minigameArmed = true end
	end)
end

local function reel()
	if not minigameArmed then return end
	minigameArmed = false
	stopSweep()
	marker.Visible = false
	-- committed the moment you strike; there is nothing left to back out of
	leaveButton.Visible = false
	castLabel.Text = "Reeling\u{2026}"
	castLabel.TextColor3 = WHITE
	reelRemote:FireServer(markerFrac)   -- the server judges it against the green it set
end

local function flashAndHide(text, colour)
	castToken += 1
	local mine = castToken
	stopSweep()
	green.Visible = false
	marker.Visible = false
	leaveButton.Visible = false     -- never sits over the reveal
	cast.Visible = true
	castLabel.Text = text
	castLabel.TextColor3 = colour
	-- this fish is done with; the walk-up loop waits RECAST_WAIT from here before it
	-- sends the line back out
	resolvedAt = os.clock()
	task.delay(2.4, function()
		if castToken == mine then cast.Visible = false; casting = false end
	end)
end

-- REAL reveal (2026-08-21). The exclusive fishing brainrots are wired, so this names
-- the fish instead of promising it. `catch` is the roster entry the server rolled --
-- { Name, Rarity, CashPerSecond, Mutation, Size } -- and the mutation/size prefixes
-- read the same way the rest of the game writes them ("Golden Massive <name>").
--
-- A FULL BAG sends Catch = nil alongside GotAway = true, so the dispatcher below
-- routes that to showGotAway and never reaches here; the nil branch is a belt-and-
-- braces fallback for a payload that somehow arrives without an entry.

local function showCatch(catch, rarity)
	rarity = (catch and catch.Rarity) or rarity
	-- Required HERE rather than at chunk level: this runs once per landed fish and
	-- require is memoised, so it costs a table lookup and keeps the chunk's local
	-- count where it was.
	--
	-- THE TUNDRA'S LADDER, not the valley's. This read RarityConfig -- World 1's -- and
	-- because both ladders carry the same tier NAMES it resolved happily and returned the
	-- wrong world's colour for every fish. That colour now also drives the burst and the
	-- ceremony, so it is no longer only the corner card that was getting it wrong.
	local colour = Color3.fromRGB(255, 226, 120)
	local okR, RarityConfigTundra = pcall(function()
		return require(ReplicatedStorage.Modules.RarityConfigTundra)
	end)
	if okR and type(RarityConfigTundra) == "table" then
		for _, t in ipairs(RarityConfigTundra) do
			if t.Name == rarity and t.Color then colour = t.Color break end
		end
	end

	if not (catch and catch.Name) then
		flashAndHide("\u{1F41F} Hooked" .. (rarity and (" a " .. rarity) or " one") .. "!", colour)
		return
	end

	local label = catch.Name
	if catch.Mutation then label = catch.Mutation .. " " .. label end
	if catch.Size then label = catch.Size .. " " .. label end
	flashAndHide(("\u{1F41F} %s\u{2003}\u{2014}\u{2003}%s"):format(label, tostring(rarity or "?")), colour)
	-- the reveal itself (burst, sting, pop or cut) is RevealRouter's, off this same remote
end

local function showGotAway()
	flashAndHide("\u{1F41F}\u{1F4A8} It got away\u{2026}", Color3.fromRGB(255, 150, 150))
end

local function endCast()
	pips.Visible = false
	castToken += 1
	stopSweep()
	green.Visible = false
	marker.Visible = false
	leaveButton.Visible = false
	cast.Visible = false
	casting = false
	resolvedAt = os.clock()
end



-- Reel input: a fresh click/tap on the world (not a HUD button) or Space/E, while armed.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not minigameArmed then return end
	local t = input.UserInputType
	if (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) and not gameProcessed then
		reel()
	elseif t == Enum.UserInputType.Keyboard
		and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E) then
		reel()
	end
end)

remote.OnClientEvent:Connect(function(p)
	if type(p) ~= "table" then return end
	if p.Warning then
		showWarning(p.StartsAt)
	elseif p.Active == true then
		eventActive = true
		refreshHoles()
		showActive(p.EndsAt)
	elseif p.Active == false then
		eventActive = false
		hideAll()
	elseif p.Casting then
		showCasting(p.Perfect)
	elseif p.Minigame then
		beginMinigame(p.GreenMin or 0.4, p.GreenMax or 0.6, p.MarkerPeriod, p.Step, p.Steps, p.Rarity)
	elseif p.Catch then
		showCatch(p.Catch, p.Rarity)
	elseif p.GotAway then
		showGotAway()
	elseif p.Cancelled then
		endCast()
	end
end)

-- A player who joins mid-blizzard never sees the Active broadcast, so pick the state up
-- from the shared attribute too.
if ReplicatedStorage:GetAttribute("IceFishingActive") == true then
	eventActive = true
	refreshHoles()
end
ReplicatedStorage:GetAttributeChangedSignal("IceFishingActive"):Connect(function()
	local on = ReplicatedStorage:GetAttribute("IceFishingActive") == true
	eventActive = on
	if on then refreshHoles() else hideAll() end
end)
