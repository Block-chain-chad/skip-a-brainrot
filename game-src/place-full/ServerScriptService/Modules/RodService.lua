-- RodService -- the worn FISHING ROD, the ice-fishing event's answer to the rock sling.
--
-- Built the same way as RockSlingService and for the same reason: SERVER-SIDE so every
-- player sees everyone else's rod, and RIG-AGNOSTIC -- every size is a fraction of the
-- wearer's own torso (UpperTorso / Torso / HumanoidRootPart), so an R6 block, a slim R15
-- and a wide Rthro all wear it in proportion.
--
-- TWO STANCES. "Slung" is the rod on your back, which is how it is carried for the length
-- of a blizzard. "Ready" re-welds it into the RIGHT HAND for a cast, which is what makes
-- the character read as pulling the rod out rather than owning a back ornament. The stance
-- is remembered per player, so the event's 3s rod maintainer and a respawn both rebuild
-- the stance the player is actually in rather than dropping them back to Slung mid-cast.
--
-- THE CAST LINE IS SERVER-SIDE TOO, and deliberately: the arm POSE is client-only (the
-- rig has no Motor6D, so ClientMain drives AnimationConstraint.Transform, which does not
-- replicate), but a Beam from the rod tip to an anchored bobber does replicate, so the
-- line, the float in the hole, the splash and the bite tug are visible to everyone even
-- though the arm swing is not.
--
-- Handed out by IceFishingEvent for the length of a blizzard and removed on thaw. Equip
-- remembers the intent per player, so a respawn mid-event re-slings the rod rather than
-- dropping it. This module never decides WHEN a rod is worn -- that is the event's call.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage.Modules.IceFishingConfig)

local RodService = {}

local ROD_NAME = "FishingRod"
local LINE_NAME = "CastLine"
local equipped = {}   -- [player] = true while the event wants this player to wear a rod
local stance = {}     -- [player] = "Slung" | "Ready"

-- Cosmetic FX channel: the server says WHEN a splash or a bite happens, every client
-- draws it locally at render rate. See RodService.Tug for why the motion cannot stay
-- here. Nothing on this remote is authoritative -- the catch is decided in
-- IceFishingEvent and a client that ignores this simply sees no splash.
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local fxRemote = remotesFolder:FindFirstChild("RodFx")
if not fxRemote then
	fxRemote = Instance.new("RemoteEvent")
	fxRemote.Name = "RodFx"
	fxRemote.Parent = remotesFolder
end

local function anchorPart(character)
	return character:FindFirstChild("UpperTorso")       -- R15 / Rthro
		or character:FindFirstChild("Torso")            -- R6
		or character:FindFirstChild("HumanoidRootPart") -- last resort, always there
end

local function handPart(character)
	return character:FindFirstChild("RightHand")        -- R15 / Rthro
		or character:FindFirstChild("Right Arm")        -- R6
		or anchorPart(character)
end

local function piece(parent, name, size, cf, colour, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weldTo(part, target)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part
	w.Part1 = target
	w.Parent = part
end

function RodService.Remove(character)
	if not character then return end
	local old = character:FindFirstChild(ROD_NAME)
	if old then old:Destroy() end
end

-- Build (or rebuild) the rod on `character` in the given stance.
function RodService.Apply(character, stanceName)
	if not character or not character.Parent then return end
	local torso = anchorPart(character)
	if not torso then return end
	stanceName = stanceName or "Slung"

	RodService.Remove(character)

	local S = torso.Size
	local w, h, d = S.X, S.Y, S.Z

	local rod = Instance.new("Model")
	rod.Name = ROD_NAME
	rod:SetAttribute("Stance", stanceName)

	-- Every dimension is a fraction of the wearer's own torso, so the rod stays in
	-- proportion on an R6 block, a slim R15 and a wide Rthro alike.
	local len   = h * 2.35                                    -- butt to tip
	local thick = math.max(0.13, math.min(w, d) * 0.115)      -- blank at the butt

	local mount, base
	if stanceName == "Ready" then
		-- IN THE HAND. Framed on the HumanoidRootPart's orientation rather than the hand's
		-- own, because a hand part's local axes differ between R6, R15 and Rthro and there
		-- is no rig-agnostic "which way is the palm". Positioned at the hand and welded to
		-- it, so once built it follows the hand wherever the animation takes it -- including
		-- the client-only cast pose, which moves the real limb locally.
		mount = handPart(character)
		local hrp = character:FindFirstChild("HumanoidRootPart") or torso
		local facing = hrp.CFrame - hrp.CFrame.Position
		-- -X about the body's right axis tips the butt down and the tip up and FORWARD:
		-- a rod held out over the water rather than shouldered like a rifle.
		base = CFrame.new(mount.Position) * facing
			* CFrame.Angles(math.rad(-58), 0, 0)
			* CFrame.new(0, len * 0.30, 0)
	else
		-- SLUNG. Local torso space: +X is the wearer's right, +Z is BEHIND them (matches
		-- the sling's ellipse, where the back crosses at +z). The rod lies flat against the
		-- back, offset out along +Z, tilted so the butt sits at the left hip and the tip
		-- clears the right shoulder -- a rod on a strap, not a pole down the spine.
		mount = torso
		base = torso.CFrame * CFrame.new(0, 0, d * 0.55) * CFrame.Angles(0, 0, math.rad(-32))
	end

	-- ===== THE BLANK, TAPERED ==================================================
	-- Four stacked segments rather than one box. A rod is the one prop where taper IS the
	-- silhouette -- a constant-width stick reads as a broom handle at any size -- and four
	-- is where the steps stop being visible against the snow. Each segment overlaps the
	-- one below by a hair so the joins do not show as notches.
	local SEGS = 4
	local segLen = len / SEGS
	local y = -len * 0.5
	for i = 1, SEGS do
		local t0 = (i - 1) / SEGS
		local tw = thick * (1 - 0.62 * t0)          -- 100% at the butt, 38% at the tip
		local col = (i >= SEGS) and Cfg.ROD_TIP_COLOR or Cfg.ROD_BLANK_COLOR
		piece(rod, (i >= SEGS) and "Tip" or "Blank", Vector3.new(tw, segLen * 1.04, tw),
			base * CFrame.new(0, y + segLen * 0.5, 0), col, Enum.Material.Wood)
		y += segLen
	end

	-- ===== GRIP, BUTT CAP, REEL SEAT ===========================================
	local gripLen = len * 0.20
	local grip = piece(rod, "Grip", Vector3.new(thick * 2.0, gripLen, thick * 2.0),
		base * CFrame.new(0, -len * 0.5 + gripLen * 0.55, 0),
		Cfg.ROD_GRIP_COLOR, Enum.Material.Fabric)
	Instance.new("CylinderMesh").Parent = grip
	local cap = piece(rod, "ButtCap", Vector3.new(thick * 2.2, thick * 0.9, thick * 2.2),
		base * CFrame.new(0, -len * 0.5 + thick * 0.3, 0),
		Cfg.ROD_METAL_COLOR, Enum.Material.Metal)
	Instance.new("CylinderMesh").Parent = cap

	local seatY = -len * 0.5 + gripLen * 1.22
	piece(rod, "ReelSeat", Vector3.new(thick * 1.5, thick * 2.4, thick * 1.5),
		base * CFrame.new(0, seatY, 0), Cfg.ROD_METAL_COLOR, Enum.Material.Metal)

	-- ===== THE REEL ============================================================
	-- A spinning reel hangs UNDER the rod, and its spool axis runs across the blank --
	-- so the cylinder is rolled 90 degrees about Z to lay its axis sideways rather than
	-- up the shaft.
	local reelDrop = thick * 2.6
	local spoolCF = base * CFrame.new(0, seatY, reelDrop) * CFrame.Angles(0, 0, math.rad(90))
	local spool = piece(rod, "Spool", Vector3.new(thick * 1.5, thick * 3.4, thick * 3.4),
		spoolCF, Cfg.ROD_REEL_COLOR, Enum.Material.Metal)
	Instance.new("CylinderMesh").Parent = spool
	local face = piece(rod, "SpoolFace", Vector3.new(thick * 0.5, thick * 3.7, thick * 3.7),
		spoolCF * CFrame.new(thick * 0.9, 0, 0), Cfg.ROD_LINE_COLOR, Enum.Material.SmoothPlastic)
	Instance.new("CylinderMesh").Parent = face
	piece(rod, "Crank", Vector3.new(thick * 0.5, thick * 0.5, thick * 2.4),
		spoolCF * CFrame.new(thick * 1.5, 0, thick * 1.0), Cfg.ROD_METAL_COLOR, Enum.Material.Metal)
	local knob = piece(rod, "Knob", Vector3.new(thick * 1.0, thick * 1.0, thick * 1.0),
		spoolCF * CFrame.new(thick * 1.5, 0, thick * 2.1), Cfg.ROD_GRIP_COLOR, Enum.Material.SmoothPlastic)
	knob.Shape = Enum.PartType.Ball

	-- ===== LINE GUIDES =========================================================
	-- Three rings up the blank, shrinking toward the tip. Small, but they are what stops
	-- the rod reading as a stick with a box glued to it.
	for i = 1, 3 do
		local t = 0.18 + i * 0.24
		local gs = thick * (2.1 - 0.45 * i)
		local g = piece(rod, "Guide", Vector3.new(thick * 0.34, gs, gs),
			base * CFrame.new(0, -len * 0.5 + len * t, thick * 0.55)
				* CFrame.Angles(0, 0, math.rad(90)),
			Cfg.ROD_METAL_COLOR, Enum.Material.Metal)
		Instance.new("CylinderMesh").Parent = g
	end

	if stanceName ~= "Ready" then
		-- Slung only: a short length of line and a little float, so a carried rod reads as
		-- rigged rather than a bare stick. A rod in the hand gets the REAL cast line
		-- instead, and having both would put two floats on one rod.
		local tipWorld = base * CFrame.new(0, len * 0.5, 0)
		piece(rod, "Line", Vector3.new(0.04, h * 0.7, 0.04),
			tipWorld * CFrame.new(0, -h * 0.35, thick * 1.2),
			Cfg.ROD_LINE_COLOR, Enum.Material.SmoothPlastic)
		piece(rod, "Float", Vector3.new(thick * 1.3, thick * 1.3, thick * 1.3),
			tipWorld * CFrame.new(0, -h * 0.7, thick * 1.2),
			Color3.fromRGB(226, 62, 54), Enum.Material.SmoothPlastic).Shape = Enum.PartType.Ball
	end


	for _, p in ipairs(rod:GetChildren()) do
		if p:IsA("BasePart") then weldTo(p, mount) end
	end

	rod.Parent = character
	return rod
end

local function reapply(player)
	local character = player.Character
	if character and character.Parent then
		RodService.Apply(character, stance[player])
	end
end

-- Start/keep a rod on this player (survives respawns until Unequip).
function RodService.Equip(player)
	equipped[player] = true
	stance[player] = stance[player] or "Slung"
	reapply(player)
end

function RodService.Unequip(player)
	equipped[player] = nil
	stance[player] = nil
	if player.Character then
		RodService.ClearLine(player.Character)
		RodService.Remove(player.Character)
	end
end

function RodService.IsEquipped(player)
	return equipped[player] == true
end

-- "Slung" (on the back) or "Ready" (in the hand). No-op if the rod is already like that,
-- so the event's maintainer can call it every tick without rebuilding the model.
function RodService.SetStance(player, stanceName)
	stanceName = stanceName or "Slung"
	if stance[player] == stanceName then return end
	stance[player] = stanceName
	if stanceName ~= "Ready" and player.Character then
		RodService.ClearLine(player.Character)
	end
	if equipped[player] then reapply(player) end
end

-- ===== the cast line ========================================================
function RodService.ClearLine(character)
	if not character then return end
	local old = character:FindFirstChild(LINE_NAME)
	if old then old:Destroy() end
end

-- A ring on the water that grows and fades: what the bobber landing and each bite tug
-- actually read as from standing height. Client-side for the reason set out on Tug below
-- -- a 1.2 -> 9 stud grow tweened server-side arrives as about fifteen visible steps.
local function ripple(character, pos)
	fxRemote:FireAllClients(character, "ripple", pos)
end

-- Hang a line from the rod tip to a bobber floating at `target`. Replicates, so every
-- player at the hole sees it even though the caster's arm swing does not.
function RodService.CastLine(character, target)
	if not character or not character.Parent then return end
	local rod = character:FindFirstChild(ROD_NAME)
	local tip = rod and rod:FindFirstChild("Tip")
	if not tip then return end
	RodService.ClearLine(character)

	local folder = Instance.new("Model")
	folder.Name = LINE_NAME

	local bob = Instance.new("Part")
	bob.Name = "Bobber"
	bob.Shape = Enum.PartType.Ball
	bob.Size = Vector3.new(0.85, 0.85, 0.85)
	bob.CFrame = CFrame.new(target)
	bob.Anchored = true
	bob.CanCollide = false; bob.CanQuery = false; bob.CanTouch = false
	bob.Color = Color3.fromRGB(226, 62, 54)
	bob.Material = Enum.Material.SmoothPlastic
	bob.Parent = folder

	local stem = Instance.new("Part")
	stem.Name = "BobberStem"
	stem.Size = Vector3.new(0.10, 0.7, 0.10)
	stem.CFrame = CFrame.new(target + Vector3.new(0, 0.55, 0))
	stem.Anchored = true
	stem.CanCollide = false; stem.CanQuery = false; stem.CanTouch = false
	stem.Color = Color3.fromRGB(246, 250, 255)
	stem.Material = Enum.Material.SmoothPlastic
	stem.Parent = folder

	local a0 = Instance.new("Attachment")
	a0.Name = "LineTop"
	a0.Position = Vector3.new(0, tip.Size.Y * 0.5, 0)
	a0.Parent = tip
	local a1 = Instance.new("Attachment")
	a1.Name = "LineEnd"
	a1.Position = Vector3.new(0, 0.35, 0)
	a1.Parent = stem

	local beam = Instance.new("Beam")
	beam.Name = "Line"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.05
	beam.Width1 = 0.05
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(Cfg.ROD_LINE_COLOR)
	beam.Transparency = NumberSequence.new(0.25)
	beam.LightInfluence = 1
	beam.Segments = 6
	beam.Parent = stem

	folder.Parent = character
	ripple(character, target)
	return folder
end

-- The bite: the float ducks under twice and the water rings. The SIGNAL is server-side so
-- everyone standing at the hole sees the fish take it -- but the MOTION is not.
--
-- WHY THIS FIRES A REMOTE INSTEAD OF TWEENING. TweenService on an ANCHORED server part
-- does not reach a client as a tween; it reaches it as a stream of CFrame writes at the
-- ~20Hz replication rate with no interpolation between them, so a 0.16s duck arrives as
-- about three steps and reads as a stutter. This is the same defect the thrown rock had
-- ("when i go to throw a rock its very chopped", 2026-08-10) and it takes the same fix
-- ClientMain used there: keep the authority on the server, run the MOTION on each client
-- at render rate. Every client tweens the bobber it already has replicated, so all of
-- them still see the take -- they just each draw it smoothly.
function RodService.Tug(character)
	local folder = character and character:FindFirstChild(LINE_NAME)
	if not folder or not folder:FindFirstChild("Bobber") then return end
	fxRemote:FireAllClients(character, "tug")
end

function RodService.Init()
	local function hook(player)
		player.CharacterAdded:Connect(function(character)
			-- same rig-assembly wait the sling uses, or the weld lands on a part about to
			-- be swapped and the rod floats where the player spawned
			character:WaitForChild("Humanoid", 10)
			if not character:FindFirstChild("UpperTorso") and not character:FindFirstChild("Torso") then
				character:WaitForChild("HumanoidRootPart", 10)
			end
			task.wait(0.35)
			-- a respawn always lands you back with the rod on your back: a cast cannot
			-- survive the character that was holding it
			if stance[player] == "Ready" then stance[player] = "Slung" end
			if equipped[player] then RodService.Apply(character, stance[player]) end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	Players.PlayerRemoving:Connect(function(p) equipped[p] = nil; stance[p] = nil end)
	print("RodService online (worn fishing rod, event-issued, slung/ready stances)")
end

return RodService
