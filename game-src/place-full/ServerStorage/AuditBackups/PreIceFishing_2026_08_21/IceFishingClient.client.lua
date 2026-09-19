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
--   { Catch=descriptor, Rarity, RockId=id }       hooked it -- placeholder reveal for now
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
local Cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("IceFishingConfig"))

local ICE_DARK  = Color3.fromRGB(16, 30, 52)
local ICE_EDGE  = Color3.fromRGB(120, 200, 255)
local ICE_TEXT  = Color3.fromRGB(212, 238, 255)

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

-- ===== the offer, in the dock's throw-button slot ============================
-- Same anchor, same 340x72 footprint and the same HUD-button styling as ThrowFrame, so
-- the tundra reads as one control that changes job when the lake freezes. ThrowFrame is
-- already hidden here: ClientMain treats the tundra dock as "not a zone" while
-- IceFishingActive is set, so the slot is free.
-- THERE IS NO CAST BUTTON. Walking up to a hole is the whole interaction: the Heartbeat
-- below fires the cast for you after CAST_DWELL, and the only input in the loop is the
-- click that hooks the fish. This frame is just the standing-at-a-hole label -- it shows
-- in the gap between one fish resolving and the line going back out, so the loop reads as
-- deliberate rather than as the UI having forgotten about you.
local offer = Instance.new("Frame")
offer.Name = "FishOffer"
offer.AnchorPoint = Vector2.new(0.5, 1)
offer.Position = UDim2.new(0.5, 0, 1, -110)
offer.Size = UDim2.fromOffset(340, 46)
offer.BackgroundColor3 = ICE_DARK
offer.BackgroundTransparency = 0.12
offer.Visible = false
offer.Parent = gui
rounded(offer, 12)
stroke(offer, ICE_EDGE, 2)

-- fills left->right as you wind up the cast; the hint text sits on top of it
local chargeFill = Instance.new("Frame")
chargeFill.Name = "ChargeFill"
chargeFill.AnchorPoint = Vector2.new(0, 0.5)
chargeFill.Position = UDim2.new(0, 0, 0.5, 0)
chargeFill.Size = UDim2.new(0, 0, 1, 0)
chargeFill.BackgroundColor3 = Color3.fromRGB(90, 200, 255)
chargeFill.BackgroundTransparency = 0.25
chargeFill.BorderSizePixel = 0
chargeFill.ZIndex = 1
chargeFill.Visible = false
chargeFill.Parent = offer
rounded(chargeFill, 12)

-- the PERFECT-cast sweet spot: release the charge with the fill inside this gold band for a
-- 2x-luck cast, the ice-fishing cousin of the skip-rock perfect throw. The SERVER decides
-- where it sits (IceFishingSweetSpot) and we only draw it -- a client cannot pick its own.
local perfectBand = Instance.new("Frame")
perfectBand.Name = "PerfectBand"
perfectBand.AnchorPoint = Vector2.new(0, 0.5)
perfectBand.Position = UDim2.new(0.6, 0, 0.5, 0)
perfectBand.Size = UDim2.new(0.1, 0, 1, 0)
perfectBand.BackgroundColor3 = Color3.fromRGB(255, 214, 96)
perfectBand.BackgroundTransparency = 0.3
perfectBand.BorderSizePixel = 0
perfectBand.ZIndex = 2
perfectBand.Visible = false
perfectBand.Parent = offer
rounded(perfectBand, 6)
do
	local ps = Instance.new("UIStroke")
	ps.Color = Color3.fromRGB(255, 238, 176)
	ps.Thickness = 1.5
	ps.Transparency = 0.1
	ps.Parent = perfectBand
end

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.BackgroundTransparency = 1
hint.Position = UDim2.new(0, 0, 0, 0)
hint.Size = UDim2.new(1, 0, 1, 0)
hint.Font = Enum.Font.GothamBold
hint.TextSize = 16
hint.TextColor3 = Color3.fromRGB(226, 244, 255)
hint.ZIndex = 3
hint.Text = "\u{1F3A3} hold to cast"
hint.Parent = offer
-- the line sits over open ice, which is nearly white: without the dark outline it
-- disappears completely the moment you step off the dock
do
	local hs = Instance.new("UIStroke")
	hs.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	hs.Color = Color3.fromRGB(14, 26, 44)
	hs.Thickness = 2
	hs.Parent = hint
end

-- ===== cast bar (same slot as the offer; only ever one of them is up) ========
local cast = Instance.new("Frame")
cast.Name = "Cast"
cast.AnchorPoint = Vector2.new(0.5, 1)
cast.Position = UDim2.new(0.5, 0, 1, -110)
cast.Size = UDim2.fromOffset(340, 68)
cast.BackgroundColor3 = ICE_DARK
cast.BackgroundTransparency = 0.08
cast.Visible = false
cast.Parent = gui
rounded(cast, 12)
stroke(cast, ICE_EDGE, 2)

local castLabel = Instance.new("TextLabel")
castLabel.BackgroundTransparency = 1
castLabel.Position = UDim2.new(0, 0, 0, 10)
castLabel.Size = UDim2.new(1, 0, 0, 22)
castLabel.Font = Enum.Font.FredokaOne
castLabel.TextSize = 17
castLabel.TextColor3 = ICE_TEXT
castLabel.Text = "Casting\u{2026}"
castLabel.Parent = cast

local track = Instance.new("Frame")
track.AnchorPoint = Vector2.new(0.5, 0)
track.Position = UDim2.new(0.5, 0, 0, 38)
track.Size = UDim2.fromOffset(300, 14)
track.BackgroundColor3 = Color3.fromRGB(8, 16, 30)
track.Parent = cast
rounded(track, 7)

-- the green BITE zone (the server tells us where) and the sweeping marker you click on
local green = Instance.new("Frame")
green.Name = "Green"
green.BackgroundColor3 = Color3.fromRGB(78, 216, 116)
green.Position = UDim2.new(0.4, 0, 0, 0)
green.Size = UDim2.new(0.2, 0, 1, 0)
green.Visible = false
green.Parent = track
rounded(green, 7)

-- THE WAY OUT. Being planted at the hole is deliberate, but without this the only exit
-- from a cast was to wait out the full 7-second hook timeout -- and then the walk-up loop
-- re-cast at you before you could take two steps. A GuiButton rather than a key alone so
-- it works on touch and, more importantly, so the exit is VISIBLE: a lock you cannot see
-- a way out of reads as a bug.
local leaveButton = Instance.new("TextButton")
leaveButton.Name = "LeaveButton"
leaveButton.AnchorPoint = Vector2.new(1, 0)
leaveButton.Position = UDim2.new(1, -8, 0, 7)
leaveButton.Size = UDim2.fromOffset(96, 24)
leaveButton.Text = "\u{2715} LEAVE (Q)"
leaveButton.TextSize = 13
leaveButton.Font = Enum.Font.GothamBold
leaveButton.TextColor3 = Color3.fromRGB(236, 246, 255)
leaveButton.BackgroundColor3 = Color3.fromRGB(46, 66, 96)
leaveButton.BackgroundTransparency = 0.15
leaveButton.AutoButtonColor = true
leaveButton.Visible = false
leaveButton.ZIndex = 4
leaveButton.Parent = cast
rounded(leaveButton, 8)
stroke(leaveButton, ICE_EDGE, 1.5)

local marker = Instance.new("Frame")
marker.Name = "Marker"
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Position = UDim2.new(0.5, 0, 0.5, 0)
marker.Size = UDim2.new(0, 6, 1.8, 0)   -- overhangs the track top and bottom
marker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
marker.ZIndex = 3
marker.Visible = false
marker.Parent = track
rounded(marker, 3)
stroke(marker, ICE_DARK, 1.5)

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
	chargeFill.Visible = true
	local t0 = os.clock()
	if chargeConn then chargeConn:Disconnect() end
	chargeConn = RunService.RenderStepped:Connect(function()
		if not charging then return end
		castPower = math.clamp((os.clock() - t0) / (Cfg.CAST_CHARGE_TIME or 0.85), 0, 1)
		chargeFill.Size = UDim2.new(castPower, 0, 1, 0)
	end)
end

local function releaseCast()
	if not charging then return end
	local power = castPower
	stopCharge()
	if power >= (Cfg.MIN_CAST_POWER or 0.15) and nearHole and not casting and eventActive then
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
		castLabel.Text = "\u{2728} PERFECT CAST \u{2014} 2\u{00D7} LUCK!"
		castLabel.TextColor3 = Color3.fromRGB(255, 224, 120)
	else
		castLabel.Text = "Casting\u{2026}"
		castLabel.TextColor3 = ICE_TEXT
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
		castLabel.Text = ("REEL  %d / %d  \u{2014}  click the GREEN!"):format(step or 1, steps)
	else
		castLabel.Text = "Click when the marker hits GREEN!"
	end
	castLabel.TextColor3 = ICE_TEXT
	green.Position = UDim2.new(greenMin, 0, 0, 0)
	green.Size = UDim2.new(math.max(0.02, greenMax - greenMin), 0, 1, 0)
	green.Visible = true
	marker.Visible = true

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
	castLabel.TextColor3 = ICE_TEXT
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

local function showCatch(rarity)
	-- STUB reveal: the exclusive fishing brainrots are not wired yet.
	local who = rarity and (" a " .. rarity) or " one"
	flashAndHide("\u{1F41F} Hooked" .. who .. "! (exclusive catch coming soon)", Color3.fromRGB(255, 226, 120))
end

local function showGotAway()
	flashAndHide("\u{1F41F}\u{1F4A8} It got away\u{2026}", Color3.fromRGB(255, 150, 150))
end

local function endCast()
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
		showCatch(p.Rarity)
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
