-- First-join onboarding. Shows once ever (TutorialDone saves with player data).
-- Each step parks a glowing beacon + bobbing arrow over the target until it's done.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)

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

-- Forward declaration. finish() is defined above the listener block but has to be
-- able to tear those listeners down, so the block below assigns into this.
local stopListening

local BLACK = Color3.fromRGB(0, 0, 0)
local GOLD1, GOLD2 = Color3.fromRGB(255, 220, 100), Color3.fromRGB(240, 150, 24)
local FONT = UITheme.Font

-- One flag per REAL action. Every one is set from an event the server or the
-- world actually fires, so no step can be satisfied by standing near something.
local flags = {
	introAck = false, threw = false, caught = false, placed = false,
	collected = false, sold = false, bought = false, upgraded = false, talked = false,
}
local active, stepIndex = false, 1

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

RunService.RenderStepped:Connect(function()
	if beacon.Parent == nil then return end
	local bx = beacon:GetAttribute("BaseX")
	if not bx then return end
	local base = Vector3.new(bx, beacon:GetAttribute("BaseY"), beacon:GetAttribute("BaseZ"))
	local t = os.clock()
	local bob = math.sin(t * 2.2) * 0.8
	local spin = t * 1.6
	local tip = base + Vector3.new(0, 7.5 + bob, 0)

	-- BEAT. glow.Brightness and pillar.Transparency were authored as constants
	-- (3 and 0.86), so the beacon moved but never PULSED -- it read as scenery
	-- from any distance where the bob was too small to see. Same 2.2 rad/s as
	-- the bob, so the flare lands at the top of every rise.
	local pulse = (math.sin(t * 2.2) + 1) * 0.5              -- 0..1
	glow.Brightness = 2.2 + pulse * 2.6                      -- was constant 3
	pillar.Transparency = 0.90 - pulse * 0.10                -- was constant 0.86
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
-- me" rather than as scenery.
--
-- It reads the beacon's own BaseX/Y/Z attributes rather than taking a target of its own,
-- so there is exactly one definition of where the current step is -- and it inherits the
-- intro's no-target case for free (no beacon parented = no chevrons).
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
local card = Instance.new("Frame")
card.Name = "TutorialCard"
card.AnchorPoint = Vector2.new(0, 1)
-- Measured live: the always-on left rail is GameHUD.NavRail (x 13..73, y 10..448) with
-- SideRailUI's Goals/Rebirth/Index/Season slots stacked in the same 19..77 column. At the
-- old x=16 the card sat straight on top of them. 92 clears the widest of those (77) with
-- a 15px gap and still reads as bottom-left.
card.Position = UDim2.new(0, 92, 1, -16)
card.Size = UDim2.fromOffset(340, 152)
card.Visible = false
card.ZIndex = 9
card.Parent = gui
UITheme.stylePanel(card)
UITheme.corner(card, 16)
blackRim(card, 3)
-- UIPolish sweeps every TextLabel under PlayerGui and force-sets Font =
-- FredokaOne + TextColor3 = white on anything not opted out (see its apply()).
-- That was flattening this card to three identical white lines: the gold step
-- counter, the white title and the muted-blue body all rendered the same.
-- NoPolish on the card covers every descendant (UIPolish walks ancestors), so
-- the three tiers read as three tiers again. bodyLbl gets its own ink stroke
-- below because an exempt label no longer receives UIPolish's.
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
inkText(bodyLbl, 1.6)   -- NoPolish means UIPolish no longer strokes this one

-- CUE LINE: names the thing the tutorial is waiting for. Without it a
-- gated-on-action step is indistinguishable from a frozen tutorial.
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

-- PROGRESS: the old card's only progress signal was the STEP n / m string,
-- which does not move. This one fills.
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

-- Hand-lerped for the same reason glideCard is: this codebase does not trust
-- TweenService for entrance-shaped UI motion (GameHUDClient.glidePanel header).
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
skipBtn.Size = UDim2.fromOffset(126, 32)
skipBtn.Position = UDim2.new(1, -138, 1, -40)
skipBtn.Text = "Skip Tutorial"
skipBtn.ZIndex = 10
skipBtn.Parent = card
UITheme.styleHudButton(skipBtn, Color3.fromRGB(150, 156, 170), Color3.fromRGB(94, 100, 114), 10)
skipBtn.TextSize = 13
blackRim(skipBtn, 2.5)

-- The intro used to advance on a 9-second timer, with the reasoning (see the
-- steps-table comment) that "a card you must work out how to close is the wrong
-- first thing to hand a new player". That is right about a CLOSE button and
-- wrong about a FORWARD button: one ends the tutorial, the other starts it, and
-- a green LET'S GO is the least ambiguous control on the card. The 20s ceiling
-- below keeps an AFK first-joiner from being stranded.
local goBtn = Instance.new("TextButton")
goBtn.Name = "GoBtn"
goBtn.Size = UDim2.fromOffset(126, 32)
goBtn.Position = UDim2.new(1, -138, 1, -40)
goBtn.Text = "LET'S GO"
goBtn.Visible = false
goBtn.ZIndex = 11
goBtn.Parent = card
UITheme.styleHudButton(goBtn, Color3.fromRGB(126, 238, 156), Color3.fromRGB(36, 172, 86), 10)
goBtn.TextSize = 14
blackRim(goBtn, 2.5)

-- Gating a step on a real PURCHASE can strand a player with no cash. After 90s
-- the card offers a per-step bail. Distinct from Skip Tutorial on purpose: this
-- advances ONE step, that one ends the whole ladder.
local nextBtn = Instance.new("TextButton")
nextBtn.Name = "NextBtn"
nextBtn.Size = UDim2.fromOffset(126, 32)
nextBtn.Position = UDim2.new(1, -272, 1, -40)
nextBtn.Text = "Skip This Step"
nextBtn.Visible = false
nextBtn.ZIndex = 11
nextBtn.Parent = card
UITheme.styleHudButton(nextBtn, Color3.fromRGB(150, 156, 170), Color3.fromRGB(94, 100, 114), 10)
nextBtn.TextSize = 12
blackRim(nextBtn, 2.5)

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
		if p:IsA("Model") and not p:GetAttribute("Claimed") and p.PrimaryPart then
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
local function nearPos(pos, dist)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and pos) then return false end
	return (hrp.Position - pos).Magnitude <= dist
end

---------------------------------------------------------------- steps
local stepShownAt = 0

-- ONE intro card, then five things to DO, then Elder Tung.
--   * The intro is index 1 and is the only entry with no Target, so it shows no beacon --
--     there is nowhere to walk yet. It advances on a timer rather than a dismiss button:
--     a card you must work out how to close is the wrong first thing to hand a new player.
--   * Elder Tung is LAST (owner, 2026-08-12) so the tutorial hands straight over to the
--     questline. By then the player has a base, a catch, cash and upgrades -- exactly what
--     he asks them to spend.
local steps = {
	{
		Intro = true,
		Title = "WELCOME TO SKIP A BRAINROT",
		Body = "Skip rocks across the lake to catch brainrots. The farther a rock flies, the rarer the catch.\n\nPut brainrots on your base and they earn you cash while you play. Spend it on better rocks, then skip even farther.",
		Target = function() return nil end,
		-- pressed LET'S GO, or 20s as an AFK ceiling (was a hard 9s wait)
		Done = function() return flags.introAck or (os.clock() - stepShownAt > 20) end,
	},
	{
		Title = "CLAIM YOUR BASE",
		Body = "Walk onto a free plot to claim it as yours.",
		Tag = "CLAIM HERE",
		Cue = "Waiting for you to step onto a plot...",
		Target = function()
			local p = nearestFreePlot()
			return p and p.PrimaryPart and p.PrimaryPart.Position
		end,
		Done = function() return myPlot() ~= nil end,
	},
	{
		Title = "SKIP A ROCK",
		Body = "Go to the dock, HOLD to charge, release to throw.",
		Tag = "SKIP HERE",
		Cue = "Waiting for your first skip...",
		Target = function()
			local z = gw:FindFirstChild("ThrowZone")
			return z and z.Position
		end,
		-- StoneThrown, not ThrowResult: the server fires StoneThrown for EVERY
		-- throw and ThrowResult only from revealCatch, so the old gate silently
		-- demanded a catch while the copy asked for a throw.
		Done = function() return flags.threw end,
	},
	{
		Title = "CATCH A BRAINROT",
		Body = "Keep skipping. The farther the rock flies, the rarer what comes back.",
		Tag = "SKIP AGAIN",
		Cue = "Waiting for a catch...",
		Target = function()
			local z = gw:FindFirstChild("ThrowZone")
			return z and z.Position
		end,
		Done = function() return flags.caught end,
	},
	{
		Title = "PUT IT ON YOUR BASE",
		Body = "Open your Bag and tap the brainrot to stand it on a pad. Placed brainrots earn cash while you play.",
		Tag = "YOUR BASE",
		Cue = "Waiting for a brainrot on a pad...",
		Target = function()
			local p = myPlot()
			return p and p.PrimaryPart and p.PrimaryPart.Position
		end,
		Done = function() return flags.placed end,
	},
	{
		Title = "COLLECT YOUR CASH",
		Body = "Your brainrots bank cash at the campfire. Walk into the ring to take it.",
		Tag = "COLLECT",
		Cue = "Waiting for a collect...",
		Target = function()
			local p = myPlot()
			return p and p.PrimaryPart and p.PrimaryPart.Position
		end,
		Done = function() return flags.collected end,
	},
	{
		Title = "SELL YOUR BRAINROTS",
		Body = "Spare brainrots turn into cash at Marco's stall. Sell one.",
		Tag = "MARCO - SELL",
		Cue = "Waiting for a sale...",
		Target = function() return stallPos("SellStall") end,
		Done = function() return flags.sold end,
	},
	{
		Title = "BUY BETTER ROCKS",
		Body = "Rocco's rocks skip farther and roll luckier. Buy one.",
		Tag = "ROCCO - ROCKS",
		Cue = "Waiting for a rock purchase...",
		Target = function() return stallPos("ShopStall") end,
		Done = function() return flags.bought end,
	},
	{
		-- NOT gated on a purchase, unlike the rock step above. Enzo's cheapest
		-- upgrade is 3,000 (UpgradeConfig: Strong Arm / Campfire Keeper) and a
		-- freshly-placed Common earns 0.9/s, so a real-purchase gate here is ~56
		-- minutes of income for a first-join player -- every one of them would hit
		-- the 90s bail instead, which is worse than no step at all. Opening the
		-- stall is still a deliberate act (an E press at the right place, not
		-- walking past), and the completion reward below is sized to buy exactly
		-- this. A real upgrade purchase also sets the flag, via DataUpdated.
		Title = "GRAB UPGRADES",
		Body = "Enzo sells permanent boosts to luck, skip power and income. Open his stall and see what is worth saving for.",
		Tag = "ENZO - UPGRADES",
		Cue = "Waiting for you to open Enzo's stall...",
		Target = function() return stallPos("UpgradeStall") end,
		Done = function() return flags.upgraded end,
	},
	{
		Title = "TALK TO ELDER TUNG",
		Body = "He waits by the lake with your first quest. Press E to talk to him.",
		Tag = "ELDER TUNG - QUEST",
		Cue = "Waiting for you to press E...",
		Target = function() return stallPos("ElderTung") end,
		Done = function() return flags.talked end,
	},
}
local CARD_REST = UDim2.new(0, 92, 1, -16)

local function showStep(i)
	local s = steps[i]
	if not s then return end
	stepShownAt = os.clock()
	-- the intro is not a numbered step, so the rest count from 1
	stepLbl.Text = s.Intro and "WELCOME" or ("STEP %d / %d"):format(i - 1, #steps - 1)
	titleLbl.Text = s.Title
	bodyLbl.Text = s.Body
	cueLbl.Text = s.Cue or ""
	goBtn.Visible = (s.Intro == true)
	skipBtn.Visible = not s.Intro
	nextBtn.Visible = false
	setProgress(i - 1, #steps - 1)
	-- the intro says considerably more than a one-line instruction, and bodyLbl at 44px
	-- only holds about three lines. Grow the card for it -- it is anchored bottom-left,
	-- so the extra height goes UPWARD and the button row stays where it was.
	-- (184/240 rather than 152/208: the progress track and the cue line took 32px.)
	local tall = s.Intro == true
	card.Size = UDim2.fromOffset(340, tall and 240 or 184)
	bodyLbl.Size = UDim2.new(1, -24, 0, tall and 100 or 44)
	setBeacon(s.Target(), s.Tag)
	-- MOTION: a new step now ARRIVES. Same 26px rise + Back/Out curve that every
	-- HUD panel opens with (GameHUDClient openPanel -> glidePanel).
	cardGen += 1
	glideCard(card, CARD_REST + UDim2.fromOffset(0, 26), CARD_REST, PANEL_OPEN, cardGen)
	pcall(SoundKit.play, "panelOpen", nil, { volume = 0.14 })
end
local function finish(completed)
	if not active then return end
	active = false
	setBeacon(nil)
	hideGuide()
	if stopListening then stopListening() end
	if completed then
		-- The ladder ends ON SCREEN. Before this, the last step's card simply
		-- disappeared and the server set a boolean: nothing marked the finish.
		cardGen += 1
		stepLbl.Text = "COMPLETE"
		titleLbl.Text = "YOU'RE SET"
		bodyLbl.Text = "Skip, catch, place, collect -- that is the whole loop. Elder Tung has your first quest."
		cueLbl.Text = ""
		goBtn.Visible = false
		skipBtn.Visible = false
		nextBtn.Visible = false
		setProgress(1, 1)
		beaconHitAt = os.clock()
		-- The kit already layers these two for a top-tier catch (see SoundKit.Ids
		-- catchBigHit / catchSparkle): impact to land it, shimmer over the top.
		pcall(SoundKit.play, "catchBigHit", nil, { volume = 0.32 })
		pcall(SoundKit.play, "catchSparkle", nil, { volume = 0.30 })
		glideCard(card, CARD_REST + UDim2.fromOffset(0, 26), CARD_REST, PANEL_OPEN, cardGen)
		task.delay(3.4, function() card.Visible = false end)
	else
		pcall(SoundKit.play, "panelClose", nil, { volume = 0.12 })
		card.Visible = false
	end
	-- the boolean is what gates the completion reward server-side
	remotes.TutorialComplete:FireServer(completed == true)
end

skipBtn.Activated:Connect(function() finish(false) end)
goBtn.Activated:Connect(function() flags.introAck = true end)
nextBtn.Activated:Connect(function()
	nextBtn.Visible = false
	stepIndex += 1
	if stepIndex > #steps then finish(true) else showStep(stepIndex) end
end)

local function start()
	if active then return end
	active = true
	stepIndex = 1
	card.Visible = true
	showStep(1)
	-- first appearance comes in from further, off the bottom edge. Bumping the
	-- gen supersedes the 26px glide showStep just started.
	cardGen += 1
	glideCard(card, UDim2.new(0, 92, 1, 60), CARD_REST,
		TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), cardGen)
end

-- Completion is EVENT-shaped now. The old 0.4s poll meant every real action was
-- acknowledged up to 400ms after the player performed it, which is most of why
-- the two genuine steps also felt inert.
local function tryAdvance()
	if not active then return end
	local s = steps[stepIndex]
	if not (s and s.Done()) then return end
	beaconHitAt = os.clock()                                      -- beacon flares
	pcall(SoundKit.play, "catchSparkle", nil, { volume = 0.26 })   -- step-complete ping
	stepIndex += 1
	if stepIndex > #steps then finish(true) else showStep(stepIndex) end
end

-- Every listener this file opens goes in here, so a player who has finished --
-- or skipped, or who arrived with TutorialDone already set -- is not signing
-- snapshot tables for the rest of the session. Assigns into the forward
-- declaration at the top because finish() is defined above this block.
local conns = {}
local function listen(signal, fn) conns[#conns + 1] = signal:Connect(fn) end
stopListening = function()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
end

-- StoneThrown fires for EVERY throw; ThrowResult only from revealCatch. Two
-- signals, two steps.
listen(remotes.StoneThrown.OnClientEvent, function() flags.threw = true; tryAdvance() end)
listen(remotes.ThrowResult.OnClientEvent, function()
	flags.threw = true; flags.caught = true; tryAdvance()
end)
listen(remotes.SellResult.OnClientEvent, function(res)
	if type(res) == "table" and res.Success == false then return end
	flags.sold = true; tryAdvance()
end)
listen(remotes.CampfireCollected.OnClientEvent, function() flags.collected = true; tryAdvance() end)

-- Rock purchases and upgrades are read off the SNAPSHOT rather than off
-- PurchaseResult's message string: the message is prose and would break the
-- moment anyone reworded it, whereas OwnedRocks/Upgrades changing IS the fact.
-- Shape-agnostic on purpose -- neither table's layout is re-derived here.
local function sig(t)
	if type(t) ~= "table" then return "" end
	local parts = {}
	for k, v in pairs(t) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
	table.sort(parts)
	return table.concat(parts, ",")
end
local baseRockSig, baseUpgSig = nil, nil
listen(remotes.DataUpdated.OnClientEvent, function(snap)
	if type(snap) ~= "table" then return end
	if baseRockSig == nil then baseRockSig, baseUpgSig = sig(snap.OwnedRocks), sig(snap.Upgrades) end
	if sig(snap.OwnedRocks) ~= baseRockSig then flags.bought = true end
	if sig(snap.Upgrades) ~= baseUpgSig then flags.upgraded = true end
	if type(snap.Brainrots) == "table" then
		for _, e in ipairs(snap.Brainrots) do
			if e.PadIndex ~= nil then flags.placed = true break end
		end
	end
	tryAdvance()
end)

-- "Press E to talk to him" now actually means pressing E -- and "open Enzo's
-- stall" means opening it. Every merchant already owns a named ProximityPrompt
-- (TungTalkPrompt / UpgradePrompt, same ones TungQuestClient hangs dialogue
-- off), so one watcher covers both gates and neither costs the player cash.
local PROMPT_FLAG = { TungTalkPrompt = "talked", UpgradePrompt = "upgraded" }
task.spawn(function()
	local hooked, count = {}, 0
	for _ = 1, 60 do
		for _, d in ipairs(Workspace:GetDescendants()) do
			local key = d:IsA("ProximityPrompt") and PROMPT_FLAG[d.Name]
			if key and not hooked[d] then
				hooked[d] = true
				count += 1
				listen(d.Triggered, function(who)
					if who == player then flags[key] = true; tryAdvance() end
				end)
			end
		end
		if count >= 2 then return end
		task.wait(0.5)
	end
end)

-- The poll no longer OWNS advance -- it keeps the beacon parked on a live target
-- (a plot can be claimed out from under you, a stall can stream in late), runs
-- the intro's 20s ceiling and the 90s per-step bail, and catches any Done()
-- whose event this file does not see.
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
					nextBtn.Visible = (not s.Intro) and (os.clock() - stepShownAt > 90)
				end
			end
		end
	end
end)

task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok and snap and not snap.TutorialDone then
		-- seed the purchase/upgrade baselines from the JOIN snapshot, not from the
		-- first DataUpdated -- that one can arrive after a purchase and would
		-- baseline the change away
		baseRockSig, baseUpgSig = sig(snap.OwnedRocks), sig(snap.Upgrades)
		task.wait(1.5)
		start()
	else
		-- already done (or the fetch failed): nothing will ever read these flags
		stopListening()
	end
end)
