-- First-join onboarding (rewritten 2026-09-21, "first 10 minutes" round). Shows
-- once ever (TutorialDone saves with player data). ONE card at a time, bottom-left,
-- a beacon + ground chevrons on the current target, and every step gated on a real
-- event or on the profile SNAPSHOT -- never on a timer, never on standing near a
-- thing, and never on something a fresh profile with Pebble cannot do. There is no
-- "Skip This Step" any more: the step that used to need it (a 12,000 rock against
-- ~1,700 in hand) was repriced instead. "Skip Tutorial" ends the whole ladder.
--
-- The ladder, and what each step is FOR:
--   1 SKIP YOUR FIRST ROCK    the core action, first
--   2 IT'S IN YOUR BAG        where a catch goes + distance -> rarity, then repeat x5
--   3 GOAL COMPLETE           the Goals board pays (own5), and the player sees it
--   4 OPEN YOUR BAG           "my brainrots are collected here"
--   5 PUT THEM ON YOUR BASE   the walk-over pad; placed brainrots earn
--   6 COLLECT YOUR CASH       the campfire
--   7 BUY A BETTER ROCK       Rivertumble, 2,000 -- affordable from the goal reward
--   (0 CLAIM A BASE           only when the server could not auto-claim one at join)
--
-- REJOIN RESUMES. Steps read durable facts where they exist (brainrot count, PadIndex,
-- OwnedRocks, TotalEarned, the goal's Claimed flag), so a player who leaves mid-ladder
-- comes back to the first step that is actually open, not to the start.
--
-- CALENDAR HANDSHAKE. The player attribute OnboardingActive is true while this runs
-- and false the moment it ends (finish or skip); GameHUDClient's join sequence holds
-- the Daily Calendar's auto-open on it (and decides the hold from the join snapshot
-- itself, so a late start here cannot lose the race).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UITheme = require(Modules.UITheme)
local SoundKit = require(Modules.SoundKit)
local Platform = require(Modules.Platform)
local RarityConfig = require(Modules.RarityConfig)
local RockConfig = require(Modules.RockConfig)

local ONBOARDING_ATTR = "OnboardingActive"
local GOAL_ID = "own5"          -- QuestHandler's "Own 5 brainrots" -- the first goal
local GOAL_COUNT = 5

-- The game's panel entrance is a HAND-LERPED glide, not a tween: see
-- GameHUDClient.glidePanel (its openPanel drives every HUD panel through it)
-- and its header note that TweenService entrances on a panel wrapper proved
-- unreliable in this place. glidePanel is a local there, so this is the same
-- pattern inlined, with a local generation counter instead of closeGen.
-- PANEL_OPEN is UIKit.Tokens' T.tween.panelOpen, value-for-value.
local PANEL_OPEN = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local cardGen = 0
local function glideCard(fr, from, to, info, gen)
	fr.Position = from
	task.spawn(function()
		RunService.RenderStepped:Wait()   -- let the first paint land before the clock starts
		if cardGen ~= gen or not fr.Visible then return end
		local t0 = os.clock()
		while true do
			RunService.RenderStepped:Wait()
			if cardGen ~= gen then return end
			local a = math.clamp((os.clock() - t0) / info.Time, 0, 1)
			fr.Position = from:Lerp(to, TweenService:GetValue(a, info.EasingStyle, info.EasingDirection))
			if a >= 1 then return end
		end
	end)
end

-- os.clock() of the last step completion; drives the beacon's victory flare.
local beaconHitAt = -99

-- Forward declarations: finish() tears the listeners down, and the listener block
-- assigns into this further down.
local stopListening

local BLACK = Color3.fromRGB(0, 0, 0)
local GOLD1, GOLD2 = Color3.fromRGB(255, 220, 100), Color3.fromRGB(240, 150, 24)
local FONT = UITheme.Font

-- FACTS: everything a step can be gated on. Durable ones come from the join
-- snapshot and every DataUpdated after it; session ones from events this client
-- sees. A step's Done() reads these and nothing else.
local facts = {
	-- session
	threw = false, revealed = false, collected = false, bagOpened = false,
	lastDistance = nil, lastRarity = nil,
	-- durable (snapshot)
	brainrots = 0, placed = false, secondRock = false, totalEarned = 0, unlockedSpots = 12,
	-- the brainrot count on the JOIN snapshot only: the first step's durable proxy.
	-- A live first catch must advance through `revealed` (after the pop), never
	-- through the DataUpdated that lands a frame after ThrowResult.
	startBrainrots = 0,
	-- Goals board (QuestState)
	goalKnown = false, goalMet = false, goalClaimed = false, goalReward = 2400,
}
-- os.clock() of the last ThrowResult: nothing may change the card while that
-- catch is still being revealed (the pop is top-centre, the card bottom-left,
-- but a card that flips mid-pop reads as the game talking over its own reward).
local lastResultAt = -99
-- HOW LONG A REVEAL TAKES is not a constant. The reward-loop pacing build
-- publishes two player attributes: ThrowCamBusy (true from StoneThrown until the
-- stone camera is back on the player -- long throws dwell on the splash) and
-- RevealPopActive (true while a CatchPop is on screen). The rule agreed with that
-- lane (2026-09-21): after ThrowResult wait while ThrowCamBusy, then for
-- RevealPopActive to come and go, bounded. Where neither attribute exists (the
-- build before it, Quick Throw on, a reveal the player switched off) the fixed
-- grace below covers the Common pop (0.90 s + fade).
local POP_GRACE = 1.2
local POP_WAIT_MAX = 3.5
local function waitForPopEnd(t0)
	while player:GetAttribute("ThrowCamBusy") == true and os.clock() - t0 < POP_WAIT_MAX do
		task.wait(0.05)
	end
	local sawPop = false
	while os.clock() - t0 < POP_WAIT_MAX do
		if player:GetAttribute("RevealPopActive") == true then
			sawPop = true
		elseif sawPop then
			break                                       -- the pop came and went
		elseif os.clock() - t0 >= POP_GRACE then
			break                                       -- no pop signal: fixed grace
		end
		task.wait(0.05)
	end
end
local active, stepIndex = false, 1

local function readSnapshot(snap)
	if type(snap) ~= "table" then return end
	if type(snap.Brainrots) == "table" then
		facts.brainrots = #snap.Brainrots
		local placed = false
		for _, e in ipairs(snap.Brainrots) do
			if type(e) == "table" and e.PadIndex ~= nil then placed = true break end
		end
		facts.placed = placed
	end
	if type(snap.OwnedRocks) == "table" then
		local second = false
		for id in pairs(snap.OwnedRocks) do
			if id ~= "Pebble" then second = true break end
		end
		facts.secondRock = second
	end
	if type(snap.TotalEarned) == "number" then facts.totalEarned = snap.TotalEarned end
	if type(snap.UnlockedSpots) == "number" then facts.unlockedSpots = snap.UnlockedSpots end
end

local function blackRim(o, t)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = BLACK; s.Thickness = t or 3; s.Transparency = 0
		end
	end
end
local function inkText(o, t)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Color = BLACK; st.Thickness = t or 2; st.Transparency = 0.05; st.Parent = o
	return st
end
local function withCommas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

---------------------------------------------------------------- beacon
local beacon = Instance.new("Model")
beacon.Name = "TutorialBeacon"

local function bpart(props)
	local p = Instance.new(props.Class or "Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = props.Color or GOLD1
	p.Size = props.Size
	p.Transparency = props.Transparency or 0
	p.Parent = beacon
	return p
end

-- ground pillar of light
local pillar = bpart({ Size = Vector3.new(46, 6, 6), Transparency = 0.86 })
pillar.Shape = Enum.PartType.Cylinder
-- arrow: shaft + downward point (two mirrored wedges)
local shaft = bpart({ Size = Vector3.new(0.85, 3.2, 0.85) })
local headA = bpart({ Class = "WedgePart", Size = Vector3.new(2.8, 2.1, 1.35) })
local headB = bpart({ Class = "WedgePart", Size = Vector3.new(2.8, 2.1, 1.35) })

local glow = Instance.new("PointLight")
glow.Color = GOLD1; glow.Range = 26; glow.Brightness = 3
glow.Parent = shaft

local tagGui = Instance.new("BillboardGui")
tagGui.Size = UDim2.fromOffset(190, 42)
tagGui.StudsOffset = Vector3.new(0, 4.2, 0)
tagGui.AlwaysOnTop = true
-- Deliberately the most generous cap in the game (everything else is 90-160). This is
-- a wayfinding beacon whose whole job is to be seen from far enough away to walk
-- toward, so capping it like a sign would defeat it. It only exists during the
-- first-join tutorial and only one is ever active.
tagGui.MaxDistance = 400
tagGui.Parent = shaft
local tag = Instance.new("TextLabel")
tag.Size = UDim2.fromScale(1, 1)
tag.BackgroundTransparency = 1
tag.Font = FONT
tag.TextScaled = true
tag.TextColor3 = Color3.fromRGB(255, 236, 160)
tag.Text = ""
tag.Parent = tagGui
inkText(tag, 2.5)

local function setBeacon(pos, label)
	if not pos then
		beacon.Parent = nil
		return
	end
	beacon.Parent = Workspace
	tag.Text = label or ""
	beacon:SetAttribute("BaseX", pos.X)
	beacon:SetAttribute("BaseY", pos.Y)
	beacon:SetAttribute("BaseZ", pos.Z)
end

---------------------------------------------------------------- rail ring
-- Some steps point at a HUD tile rather than a place in the world: a gold ring
-- pulsing around the Bag or Goals tile on the nav rail. Found by name
-- (GameHUD -> NavRail -> <id>Item, see GameHUDClient's RAIL_ORDER loop); if the
-- tile is not there within 5 s the ring is simply skipped -- the copy names the
-- tile anyway.
local ring = Instance.new("Frame")
ring.Name = "TutorialRing"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.fromScale(1.34, 1.34)
ring.BackgroundTransparency = 1
ring.ZIndex = 60
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(0, 22)
ringCorner.Parent = ring
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = GOLD1
ringStroke.Thickness = 4
ringStroke.Transparency = 0
ringStroke.Parent = ring
local ringGen = 0
local function setRing(tileId)
	ringGen += 1
	ring.Parent = nil
	if not tileId then return end
	local gen = ringGen
	task.spawn(function()
		local hud = playerGui:WaitForChild("GameHUD", 5)
		local rail = hud and hud:FindFirstChild("NavRail", true)
		local item = rail and rail:FindFirstChild(tileId .. "Item")
		if gen ~= ringGen or not item then return end
		ring.Parent = item
	end)
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	if ring.Parent then
		local pulse = (math.sin(t * 5.0) + 1) * 0.5
		ringStroke.Thickness = 3 + pulse * 3
		ringStroke.Transparency = 0.05 + pulse * 0.35
	end
	if beacon.Parent == nil then return end
	local bx = beacon:GetAttribute("BaseX")
	if not bx then return end
	local base = Vector3.new(bx, beacon:GetAttribute("BaseY"), beacon:GetAttribute("BaseZ"))
	local bob = math.sin(t * 2.2) * 0.8
	local spin = t * 1.6
	local tip = base + Vector3.new(0, 7.5 + bob, 0)

	-- BEAT. Same 2.2 rad/s as the bob, so the flare lands at the top of every rise.
	local pulse = (math.sin(t * 2.2) + 1) * 0.5              -- 0..1
	glow.Brightness = 2.2 + pulse * 2.6
	pillar.Transparency = 0.90 - pulse * 0.10
	-- victory flare: the beacon itself acknowledges the step you just finished
	local flare = math.max(0, 1 - (os.clock() - beaconHitAt) / 0.45)
	if flare > 0 then
		glow.Brightness += flare * 9
		pillar.Transparency = math.max(0.35, pillar.Transparency - flare * 0.45)
	end

	pillar.CFrame = CFrame.new(base + Vector3.new(0, 23, 0)) * CFrame.Angles(0, 0, math.rad(90))
	shaft.CFrame = CFrame.new(tip + Vector3.new(0, 3.4, 0)) * CFrame.Angles(0, spin, 0)
	local headCF = CFrame.new(tip + Vector3.new(0, 1.05, 0)) * CFrame.Angles(0, spin, 0)
	headA.CFrame = headCF * CFrame.new(0, 0, 0.675) * CFrame.Angles(math.rad(180), 0, 0)
	headB.CFrame = headCF * CFrame.new(0, 0, -0.675) * CFrame.Angles(math.rad(180), math.rad(180), 0)
end)

---------------------------------------------------------------- guide chevrons
-- The beacon marks WHERE the step is. This marks the WAY there: a run of chevrons laid on
-- the ground from the player toward that beacon, flowing outward so it reads as "follow
-- me" rather than as scenery. It reads the beacon's own BaseX/Y/Z attributes, so there is
-- exactly one definition of where the current step is (no beacon = no chevrons).
local GUIDE_N     = 7      -- chevrons in the run
local GUIDE_STEP  = 5.0    -- studs between them
local GUIDE_START = 6.0    -- studs ahead of the player the run begins
local GUIDE_NEAR  = 16     -- inside this, the beacon is plainly visible; stop leading

local guide = Instance.new("Model")
guide.Name = "TutorialGuide"
local chevrons = {}
for i = 1, GUIDE_N do
	local pair = {}
	for k = 1, 2 do
		local b = Instance.new("Part")
		b.Name = ("Chevron%d_%d"):format(i, k)
		b.Size = Vector3.new(0.42, 0.42, 2.6)
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Material = Enum.Material.Neon
		b.Color = GOLD1
		b.Transparency = 1
		b.TopSurface = Enum.SurfaceType.Smooth
		b.BottomSurface = Enum.SurfaceType.Smooth
		b.Parent = guide
		pair[k] = b
	end
	chevrons[i] = pair
end

local guideParams = RaycastParams.new()
guideParams.IgnoreWater = true
guideParams.FilterType = Enum.RaycastFilterType.Exclude

local function hideGuide()
	if guide.Parent then guide.Parent = nil end
end

RunService.RenderStepped:Connect(function()
	local bx = beacon.Parent and beacon:GetAttribute("BaseX")
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (bx and hrp) then hideGuide() return end

	local target = Vector3.new(bx, beacon:GetAttribute("BaseY"), beacon:GetAttribute("BaseZ"))
	local flat = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
	local dist = flat.Magnitude
	if dist < GUIDE_NEAR then hideGuide() return end

	guide.Parent = Workspace
	local dir = flat.Unit
	guideParams.FilterDescendantsInstances = { char, guide, beacon }
	local t = os.clock()
	for i, pair in ipairs(chevrons) do
		local along = GUIDE_START + (i - 1) * GUIDE_STEP
		if along > dist - 5 then
			pair[1].Transparency = 1
			pair[2].Transparency = 1
		else
			local p = hrp.Position + dir * along
			-- sit on whatever is actually underfoot: the valley floor, a plot deck, the dock
			local hit = Workspace:Raycast(p + Vector3.new(0, 14, 0), Vector3.new(0, -70, 0), guideParams)
			local y = hit and (hit.Position.Y + 0.35) or (hrp.Position.Y - 2.6)
			local at = Vector3.new(p.X, y, p.Z)
			local face = CFrame.lookAt(at, at + dir)
			pair[1].CFrame = face * CFrame.Angles(0, math.rad(34), 0) * CFrame.new(0, 0, -1.15)
			pair[2].CFrame = face * CFrame.Angles(0, math.rad(-34), 0) * CFrame.new(0, 0, -1.15)
			-- a pulse travelling outward along the run, so the eye is pulled toward the goal
			local phase = (t * 1.5 - (i - 1) * 0.16) % 1
			local a = 0.18 + math.abs(phase - 0.5) * 1.25
			pair[1].Transparency = a
			pair[2].Transparency = a
		end
	end
end)

---------------------------------------------------------------- card UI
-- DESKTOP: 340x184 bottom-left, x 92 clears the nav rail column (13..77) with a
-- 15px gap (measured 2026-08-20). PHONE: a 300x120 card with smaller type, parked
-- top-left under the currency cluster -- the only lane on a handset that is clear
-- of the rail row, the throw cluster (bottom-centre) and the catch pop (top-centre,
-- x from ~40% of the width). Sizes below are the desktop set; layoutCard() swaps.
local card = Instance.new("Frame")
card.Name = "TutorialCard"
card.AnchorPoint = Vector2.new(0, 1)
card.Position = UDim2.new(0, 92, 1, -16)
card.Size = UDim2.fromOffset(340, 184)
card.Visible = false
card.ZIndex = 9
card.Parent = gui
UITheme.stylePanel(card)
UITheme.corner(card, 16)
blackRim(card, 3)
-- UIPolish sweeps every TextLabel under PlayerGui and force-sets Font =
-- FredokaOne + TextColor3 = white on anything not opted out (see its apply()).
-- NoPolish on the card covers every descendant (UIPolish walks ancestors), so the
-- three text tiers read as three tiers. bodyLbl gets its own ink stroke below
-- because an exempt label no longer receives UIPolish's.
card:SetAttribute("NoPolish", true)

local stepLbl = Instance.new("TextLabel")
stepLbl.Size = UDim2.new(1, -20, 0, 20)
stepLbl.Position = UDim2.new(0, 14, 0, 10)
stepLbl.BackgroundTransparency = 1
stepLbl.Font = FONT
stepLbl.TextSize = 14
stepLbl.TextXAlignment = Enum.TextXAlignment.Left
stepLbl.TextColor3 = Color3.fromRGB(255, 220, 110)
stepLbl.ZIndex = 10
stepLbl.Parent = card
inkText(stepLbl, 1.8)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -20, 0, 26)
titleLbl.Position = UDim2.new(0, 14, 0, 30)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = FONT
titleLbl.TextSize = 20
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLbl.ZIndex = 10
titleLbl.Parent = card
inkText(titleLbl, 2.2)

local bodyLbl = Instance.new("TextLabel")
bodyLbl.Size = UDim2.new(1, -24, 0, 44)
bodyLbl.Position = UDim2.new(0, 14, 0, 58)
bodyLbl.BackgroundTransparency = 1
bodyLbl.Font = Enum.Font.GothamMedium
bodyLbl.TextSize = 13
bodyLbl.TextWrapped = true
bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
bodyLbl.TextYAlignment = Enum.TextYAlignment.Top
bodyLbl.TextColor3 = Color3.fromRGB(196, 206, 226)
bodyLbl.ZIndex = 10
bodyLbl.Parent = card
inkText(bodyLbl, 1.6)

-- CUE LINE: names the thing the tutorial is waiting for, or the last skip's
-- distance -> rarity. Without it a gated step is indistinguishable from a frozen one.
local cueLbl = Instance.new("TextLabel")
cueLbl.Name = "Cue"
cueLbl.AnchorPoint = Vector2.new(0, 1)
cueLbl.Position = UDim2.new(0, 14, 1, -60)
cueLbl.Size = UDim2.new(1, -28, 0, 16)
cueLbl.BackgroundTransparency = 1
cueLbl.Font = Enum.Font.GothamMedium
cueLbl.TextSize = 12
cueLbl.TextXAlignment = Enum.TextXAlignment.Left
cueLbl.TextColor3 = Color3.fromRGB(150, 162, 186)
cueLbl.Text = ""
cueLbl.ZIndex = 10
cueLbl.Parent = card
inkText(cueLbl, 1.4)

-- PROGRESS: fills per finished step.
local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0, 1)
track.Position = UDim2.new(0, 14, 1, -46)
track.Size = UDim2.new(1, -28, 0, 8)
track.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
track.BorderSizePixel = 0
track.ZIndex = 10
track.Parent = card
UITheme.corner(track, 4)
UITheme.stroke(track, BLACK, 2)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = GOLD1
fill.BorderSizePixel = 0
fill.ZIndex = 11
fill.Parent = track
UITheme.corner(fill, 4)
UITheme.gradient(fill, GOLD1, GOLD2, 90)

-- Hand-lerped for the same reason glideCard is (GameHUDClient.glidePanel header).
local fillGen = 0
local function setProgress(done, total)
	fillGen += 1
	local gen = fillGen
	local from = fill.Size
	local to = UDim2.fromScale(math.clamp(done / math.max(total, 1), 0, 1), 1)
	local dur = 0.35
	task.spawn(function()
		local t0 = os.clock()
		while true do
			RunService.RenderStepped:Wait()
			if fillGen ~= gen then return end
			local a = math.clamp((os.clock() - t0) / dur, 0, 1)
			fill.Size = from:Lerp(to, TweenService:GetValue(a, Enum.EasingStyle.Quart, Enum.EasingDirection.Out))
			if a >= 1 then return end
		end
	end)
end

local skipBtn = Instance.new("TextButton")
skipBtn.Name = "SkipBtn"
skipBtn.Size = UDim2.fromOffset(126, 32)
skipBtn.Position = UDim2.new(1, -138, 1, -40)
skipBtn.Text = "Skip Tutorial"
skipBtn.ZIndex = 10
skipBtn.Parent = card
UITheme.styleHudButton(skipBtn, Color3.fromRGB(150, 156, 170), Color3.fromRGB(94, 100, 114), 10)
skipBtn.TextSize = 13
blackRim(skipBtn, 2.5)

-- Where the card rests, per platform.
--
-- PHONE, measured in the iPhone 16 simulator (733x371 viewport, 58px top inset, so
-- MainUI's canvas runs y -58..313 in screen terms): the currency cluster owns
-- y 10..48, the 2x3 nav rail x 10..152 / y 65..172, the throw cluster x 196..536
-- from y 241 at the dock, the catch pop and skip counter the top centre, the Goals
-- bar the right edge. The one lane clear of all of them is bottom-left UNDER the
-- rail and LEFT of the throw cluster: 176 wide, from the rail's foot to the bottom
-- edge. PlatformClient's auto-fitter would halve a frame this size (it did: 0.49),
-- so the card declares itself managed and is sized by hand.
local CARD_REST = UDim2.new(0, 92, 1, -16)
local function layoutCard()
	if Platform.IsPhone then
		card:SetAttribute("HudLayoutManaged", true)
		local fit = card:FindFirstChild("PlatformFitScale")
		if fit then fit.Scale = 1 end
		card.AnchorPoint = Vector2.new(0, 1)
		CARD_REST = UDim2.new(0, 8, 1, -8)
		card.Size = UDim2.fromOffset(176, 124)
		stepLbl.TextSize = 10; stepLbl.Position = UDim2.new(0, 8, 0, 4); stepLbl.Size = UDim2.new(1, -12, 0, 12)
		titleLbl.TextSize = 13; titleLbl.Position = UDim2.new(0, 8, 0, 15); titleLbl.Size = UDim2.new(1, -12, 0, 16)
		bodyLbl.TextSize = 10; bodyLbl.Position = UDim2.new(0, 8, 0, 32); bodyLbl.Size = UDim2.new(1, -14, 0, 60)
		-- the cue ("3 / 5 caught . last skip 20m -> COMMON") needs the whole width, so on
		-- a phone Skip Tutorial moves up beside the short step label instead
		cueLbl.TextSize = 9; cueLbl.Position = UDim2.new(0, 8, 1, -24); cueLbl.Size = UDim2.new(1, -16, 0, 11)
		track.Position = UDim2.new(0, 8, 1, -12); track.Size = UDim2.new(1, -16, 0, 5)
		skipBtn.Size = UDim2.fromOffset(76, 16); skipBtn.Position = UDim2.new(1, -82, 0, 3); skipBtn.TextSize = 10
	else
		card.AnchorPoint = Vector2.new(0, 1)
		CARD_REST = UDim2.new(0, 92, 1, -16)
		card.Size = UDim2.fromOffset(340, 184)
		stepLbl.TextSize = 14; stepLbl.Position = UDim2.new(0, 14, 0, 10); stepLbl.Size = UDim2.new(1, -20, 0, 20)
		titleLbl.TextSize = 20; titleLbl.Position = UDim2.new(0, 14, 0, 30); titleLbl.Size = UDim2.new(1, -20, 0, 26)
		bodyLbl.TextSize = 13; bodyLbl.Position = UDim2.new(0, 14, 0, 58); bodyLbl.Size = UDim2.new(1, -24, 0, 44)
		cueLbl.TextSize = 12; cueLbl.Position = UDim2.new(0, 14, 1, -60); cueLbl.Size = UDim2.new(1, -28, 0, 16)
		track.Position = UDim2.new(0, 14, 1, -46); track.Size = UDim2.new(1, -28, 0, 8)
		skipBtn.Size = UDim2.fromOffset(126, 32); skipBtn.Position = UDim2.new(1, -138, 1, -40); skipBtn.TextSize = 13
	end
	card.Position = CARD_REST
end
layoutCard()
Platform.Watch(function() layoutCard() end)

---------------------------------------------------------------- helpers
local gw = Workspace:WaitForChild("GameWorld")
local plots = Workspace:WaitForChild("PlayerBases")

local function myPlot()
	for _, p in ipairs(plots:GetChildren()) do
		if p:GetAttribute("OwnerUserId") == player.UserId then return p end
	end
	return nil
end
local function nearestFreePlot()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local best, bestD
	for _, p in ipairs(plots:GetChildren()) do
		if p:IsA("Model") and not p:GetAttribute("Claimed") and p:GetAttribute("World") == "Valley" and p.PrimaryPart then
			local d = hrp and (p.PrimaryPart.Position - hrp.Position).Magnitude or 0
			if not bestD or d < bestD then best, bestD = p, d end
		end
	end
	return best
end
local function stallPos(name)
	local stall = gw:FindFirstChild(name)
	local part = stall and stall:FindFirstChild("PromptPart")
	return part and part.Position
end
-- a named part/model inside my plot (EquipBestPad, Campfire), else the plot itself
local function plotPos(childName)
	local p = myPlot()
	if not p then return nil end
	local c = childName and p:FindFirstChild(childName, true)
	if c and c:IsA("BasePart") then return c.Position end
	if c and c:IsA("Model") then return c:GetPivot().Position end
	return p.PrimaryPart and p.PrimaryPart.Position or p:GetPivot().Position
end
local function dockPos()
	local z = gw:FindFirstChild("ThrowZone")
	return z and z.Position
end

local uncommonAt = (RarityConfig[2] and RarityConfig[2].MinDistance) or 100
local firstRock = RockConfig[2] or { Name = "Rivertumble", Price = 2000, MaxDistance = 70 }
local starterReach = (RockConfig[1] and RockConfig[1].MaxDistance) or 25
local reachMult = math.max(2, math.floor(firstRock.MaxDistance / math.max(starterReach, 1) + 0.5))

---------------------------------------------------------------- steps
-- Title / Body / Tag (beacon label) / Cue (string or function) / Target (world
-- position or nil) / Ring (rail tile id or nil) / Done. Every Done reads `facts`.
local steps = {
	{
		Id = "skip",
		Title = "SKIP YOUR FIRST ROCK",
		Body = "Follow the arrows to the dock. HOLD the button, let go to skip.",
		Tag = "SKIP HERE",
		Cue = "Waiting for your first skip...",
		Target = dockPos,
		Done = function() return facts.revealed or facts.startBrainrots >= 1 end,
	},
	{
		Id = "bag",
		Title = "IT'S IN YOUR BAG",
		Body = ("Every catch goes to your Bag. Farther skips find rarer brainrots -- Uncommon from %dm. Catch %d!"):format(uncommonAt, GOAL_COUNT),
		Tag = "SKIP AGAIN",
		Cue = function()
			local n = math.min(facts.brainrots, GOAL_COUNT)
			if facts.lastDistance then
				-- the phone cue line is 160 px at 9 px: the same facts, fewer words
				if Platform.IsPhone then
					return ("%d/%d caught  \u{2022}  %dm \u{2192} %s"):format(n, GOAL_COUNT, facts.lastDistance, string.upper(facts.lastRarity or "Common"))
				end
				return ("%d / %d caught  \u{2022}  last skip %dm \u{2192} %s"):format(n, GOAL_COUNT, facts.lastDistance, string.upper(facts.lastRarity or "Common"))
			end
			return ("%d / %d caught"):format(n, GOAL_COUNT)
		end,
		Target = dockPos,
		Ring = "bag",
		RingFor = 4,
		Done = function() return facts.brainrots >= GOAL_COUNT end,
	},
	{
		Id = "goal",
		Title = "GOAL COMPLETE!",
		Body = function() return ("Open GOALS on the left and claim your $%s."):format(withCommas(facts.goalReward)) end,
		Cue = "Waiting for you to claim it...",
		Target = function() return nil end,
		Ring = "goals",
		Done = function() return facts.goalClaimed end,
	},
	{
		Id = "openbag",
		Title = "OPEN YOUR BAG",
		Body = "Your brainrots are collected here. Take a look.",
		Cue = "Waiting for you to open the Bag...",
		Target = function() return nil end,
		Ring = "bag",
		Done = function() return facts.bagOpened end,
	},
	{
		Id = "place",
		Title = "PUT THEM ON YOUR BASE",
		Body = "Walk onto the green pad at your camp and confirm. Placed brainrots earn cash while you play.",
		Tag = "YOUR BASE",
		Cue = "Waiting for a brainrot on a pad...",
		Target = function() return plotPos("EquipBestPad") end,
		Done = function() return facts.placed end,
	},
	{
		Id = "collect",
		Title = "COLLECT YOUR CASH",
		Body = "Stand in the campfire to collect what they've earned.",
		Tag = "COLLECT",
		Cue = "Waiting for a collect...",
		Target = function() return plotPos("Campfire") end,
		Done = function() return facts.collected or facts.totalEarned > 0 end,
	},
	{
		Id = "rock",
		Title = "BUY A BETTER ROCK",
		Body = ("Rocco's %s skips %dx farther than your pebble. $%s -- you've earned it."):format(firstRock.Name or "Rivertumble", reachMult, withCommas(firstRock.Price)),
		Tag = "ROCCO - ROCKS",
		Cue = "Waiting for a rock purchase...",
		Target = function() return stallPos("ShopStall") end,
		Done = function() return facts.secondRock end,
	},
}
-- Only when the server could not auto-claim a camp at join (a full server).
local CLAIM_STEP = {
	Id = "claim",
	Title = "CLAIM A BASE",
	Body = "Walk onto a free camp. It's yours.",
	Tag = "CLAIM HERE",
	Cue = "Waiting for you to step onto a camp...",
	Target = function()
		local p = nearestFreePlot()
		return p and p.PrimaryPart and p.PrimaryPart.Position
	end,
	Done = function() return myPlot() ~= nil end,
}

local function textOf(v)
	if type(v) == "function" then
		local ok, res = pcall(v)
		return ok and tostring(res or "") or ""
	end
	return v or ""
end

local function showStep(i)
	local s = steps[i]
	if not s then return end
	stepLbl.Text = ("STEP %d / %d"):format(i, #steps)
	titleLbl.Text = s.Title
	bodyLbl.Text = textOf(s.Body)
	cueLbl.Text = textOf(s.Cue)
	skipBtn.Visible = true
	setProgress(i - 1, #steps)
	setBeacon(s.Target(), s.Tag)
	setRing(s.Ring)
	if s.Ring and s.RingFor then
		local gen = ringGen
		task.delay(s.RingFor, function() if ringGen == gen then setRing(nil) end end)
	end
	-- MOTION: a new step ARRIVES. Same 26px rise + Back/Out curve that every HUD
	-- panel opens with (GameHUDClient openPanel -> glidePanel).
	cardGen += 1
	glideCard(card, CARD_REST + UDim2.fromOffset(0, 26), CARD_REST, PANEL_OPEN, cardGen)
	pcall(SoundKit.play, "panelOpen", nil, { volume = 0.14 })
end

local function refreshCue()
	if not active then return end
	local s = steps[stepIndex]
	if s and type(s.Cue) == "function" then cueLbl.Text = textOf(s.Cue) end
end

local FINISH_HOLD = 6
local function finish(completed)
	if not active then return end
	active = false
	setBeacon(nil)
	setRing(nil)
	hideGuide()
	if stopListening then stopListening() end
	if completed then
		-- The ladder ends ON SCREEN, and says what comes next.
		cardGen += 1
		stepLbl.Text = "COMPLETE"
		titleLbl.Text = "YOU'RE SET"
		bodyLbl.Text = ("Skip, catch, place, collect -- that's the loop. Next: fill all %d pads, sell spares to Marco, and save for Sevenskip -- it reaches UNCOMMON."):format(facts.unlockedSpots)
		cueLbl.Text = "Tap SKIP at the top to jump back to the dock."
		skipBtn.Visible = false
		setProgress(1, 1)
		beaconHitAt = os.clock()
		-- The kit already layers these two for a top-tier catch (see SoundKit.Ids
		-- catchBigHit / catchSparkle): impact to land it, shimmer over the top.
		pcall(SoundKit.play, "catchBigHit", nil, { volume = 0.32 })
		pcall(SoundKit.play, "catchSparkle", nil, { volume = 0.30 })
		card.Visible = true
		glideCard(card, CARD_REST + UDim2.fromOffset(0, 26), CARD_REST, PANEL_OPEN, cardGen)
		task.delay(FINISH_HOLD, function()
			card.Visible = false
			-- the calendar (held by GameHUDClient) comes AFTER the finish beat, not over it
			player:SetAttribute(ONBOARDING_ATTR, false)
		end)
	else
		pcall(SoundKit.play, "panelClose", nil, { volume = 0.12 })
		card.Visible = false
		player:SetAttribute(ONBOARDING_ATTR, false)
	end
	-- the boolean is what gates the completion reward server-side
	remotes.TutorialComplete:FireServer(completed == true)
end

skipBtn.Activated:Connect(function() finish(false) end)

-- Completion is EVENT-shaped: every listener calls this, and the 0.4 s poll only
-- catches what the listeners did not see. Advances through every already-done step
-- in one go (rejoin resume, or a fact that satisfies two steps at once).
local function tryAdvance()
	if not active then return end
	local advanced = false
	while true do
		local s = steps[stepIndex]
		if not s or not s.Done() then break end
		advanced = true
		stepIndex += 1
		if stepIndex > #steps then finish(true) return end
	end
	if advanced then
		beaconHitAt = os.clock()                                      -- beacon flares
		pcall(SoundKit.play, "catchSparkle", nil, { volume = 0.26 })   -- step-complete ping
		showStep(stepIndex)
	else
		refreshCue()
	end
end

local function start()
	if active then return end
	active = true
	-- fast-forward: the first step that is genuinely open
	stepIndex = 1
	while steps[stepIndex] and steps[stepIndex].Done() do stepIndex += 1 end
	if stepIndex > #steps then
		-- everything the ladder teaches is already on the profile: just close it out
		finish(true)
		return
	end
	card.Visible = true
	showStep(stepIndex)
	-- first appearance comes in from further away. Bumping the gen supersedes the
	-- 26px glide showStep just started.
	cardGen += 1
	local from = Platform.IsPhone and UDim2.new(0, 8, 1, 60) or UDim2.new(0, 92, 1, 60)
	glideCard(card, from, CARD_REST, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), cardGen)
end

---------------------------------------------------------------- listeners
-- Every listener this file opens goes in here, so a player who has finished -- or
-- skipped, or who arrived with TutorialDone already set -- is not signing snapshot
-- tables for the rest of the session.
local conns = {}
local function listen(signal, fn) conns[#conns + 1] = signal:Connect(fn) end
stopListening = function()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
end

-- StoneThrown fires for EVERY throw; ThrowResult only when a catch is revealed.
-- The first step waits for the REVEAL to finish (waitForPopEnd), not for the throw.
listen(remotes.StoneThrown.OnClientEvent, function() facts.threw = true end)
-- Advance, but not over a catch pop: anything that lands while the last catch is
-- still being revealed waits for the reveal to end first.
local function advanceAfterPop()
	local t0 = lastResultAt
	if os.clock() - t0 < POP_WAIT_MAX then
		task.spawn(function() waitForPopEnd(t0); tryAdvance() end)
	else
		tryAdvance()
	end
end
listen(remotes.ThrowResult.OnClientEvent, function(res)
	local t0 = os.clock()
	lastResultAt = t0
	if type(res) == "table" then
		if type(res.Distance) == "number" then facts.lastDistance = res.Distance end
		if type(res.Rarity) == "string" then facts.lastRarity = res.Rarity end
	end
	task.spawn(function()
		waitForPopEnd(t0)
		facts.revealed = true
		tryAdvance()
	end)
end)
listen(remotes.CampfireCollected.OnClientEvent, function() facts.collected = true; tryAdvance() end)
listen(remotes.DataUpdated.OnClientEvent, function(snap)
	readSnapshot(snap)
	advanceAfterPop()
end)
-- The Goals board: QuestHandler pushes the whole list every 3 s and on every claim.
listen(remotes.QuestState.OnClientEvent, function(list)
	if type(list) ~= "table" then return end
	local found = nil
	for _, q in ipairs(list) do
		if type(q) == "table" and q.Id == GOAL_ID then found = q break end
	end
	facts.goalKnown = true
	if found then
		facts.goalReward = tonumber(found.Reward) or facts.goalReward
		facts.goalMet = (found.Met == true)
		if found.Claimed == true then facts.goalClaimed = true end
	else
		-- the board no longer carries this goal: nothing to claim, the step stands down
		facts.goalClaimed = true
	end
	tryAdvance()
end)
-- "Open your Bag" means opening it: GameHUDClient mirrors the open panel's id here.
listen(player:GetAttributeChangedSignal("HudOpenPanel"), function()
	if player:GetAttribute("HudOpenPanel") == "bag" then
		facts.bagOpened = true
		tryAdvance()
	end
end)

-- The poll does not own advance: it keeps the beacon parked on a live target (a stall
-- can stream in late, a plot can change hands) and catches any Done() whose event
-- this file did not see.
task.spawn(function()
	while true do
		task.wait(0.4)
		if active then
			local s = steps[stepIndex]
			if s then
				if s.Done() then
					tryAdvance()
				else
					setBeacon(s.Target(), s.Tag)
				end
			end
		end
	end
end)

---------------------------------------------------------------- post-tutorial hint
-- ONE hint, once per session, after a completed ladder: the first snapshot that
-- shows every unlocked pad filled AND a spare in the bag. Selling is the early
-- game's real income (a Common sells for ~15 minutes of its own earnings) and
-- nothing else in the game says so at the moment it first matters.
local function armSpareHint()
	local Toast = require(Modules.UIKit.Toast)
	local conn
	conn = remotes.DataUpdated.OnClientEvent:Connect(function(snap)
		if type(snap) ~= "table" or type(snap.Brainrots) ~= "table" then return end
		local placed, spare = 0, 0
		for _, e in ipairs(snap.Brainrots) do
			if type(e) == "table" then
				if e.PadIndex ~= nil then placed += 1 else spare += 1 end
			end
		end
		local spots = tonumber(snap.UnlockedSpots) or facts.unlockedSpots
		if placed >= spots and spare >= 1 then
			conn:Disconnect()
			pcall(Toast.show, { text = "Base full -- spare brainrots sell for cash at Marco's stall (SHOPS)", tone = "info", hold = 5 })
		end
	end)
end

---------------------------------------------------------------- boot
task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok and type(snap) == "table" and not snap.TutorialDone then
		player:SetAttribute(ONBOARDING_ATTR, true)
		readSnapshot(snap)
		facts.startBrainrots = facts.brainrots
		-- The server auto-claims a valley camp for a first-join profile (Main). Give
		-- that attribute a moment to replicate; if nothing arrives, lead with CLAIM.
		local waited = 0
		while not myPlot() and waited < 3 do
			task.wait(0.25); waited += 0.25
		end
		if not myPlot() then table.insert(steps, 1, CLAIM_STEP) end
		task.wait(1.0)
		start()
		-- the hint only makes sense after a ladder that taught placing; a skipped one
		-- is the player saying "I know", and the toast would be noise
		local watch
		watch = player:GetAttributeChangedSignal(ONBOARDING_ATTR):Connect(function()
			if player:GetAttribute(ONBOARDING_ATTR) == false then
				watch:Disconnect()
				if stepIndex > #steps then armSpareHint() end
			end
		end)
	else
		-- already done (or the fetch failed): nothing will ever read these flags
		stopListening()
	end
end)
