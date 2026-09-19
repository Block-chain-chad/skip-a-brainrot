-- RockSlingService -- the rock sling every player wears, carrying the rock they
-- currently have equipped.
--
-- SERVER-SIDE so everyone sees everyone else's sling (and the rock in it). A
-- client-built sling would be invisible to every other player, which defeats the
-- point -- the sling is how you read someone's progression across the camp.
--
-- FITS EVERY RIG. Nothing here hardcodes a body part or a stud measurement:
--   R15 / Rthro  -> UpperTorso
--   R6           -> Torso
--   anything else-> HumanoidRootPart (always present)
-- and every offset and size below is expressed as a FRACTION of that part's own
-- Size, so a 3-stud-wide Rthro torso and a 2-stud R6 torso both get a sling in
-- proportion. Roblox avatar scaling (BodyWidthScale et al) changes the torso's
-- Size, so this follows it for free -- and Init re-runs the fit when that Size
-- changes, so a rig rescaled AFTER it spawned is refitted rather than left wearing
-- the shape it was born with.
--
-- IT WRAPS. The strap is a closed loop built around the torso's own cross-section,
-- not a panel stuck to the back -- see the block above the geometry for the curve.
--
-- THE ROCK IS THE REAL ROCK: built from RockDesign, the same call the shop preview
-- and the thrown stone use, so what is on your back is what you throw -- including
-- its Fx kit (aura, ring, shards, glow). Two deliberate edits to the worn copy:
--   * the Trail is REMOVED -- a flight wake looks wrong on a rock being carried,
--     and it would streak across the camp behind every walking player;
--   * particle Rate is halved, because a dozen players standing in the plaza each
--     emitting a full thrown-rock plume is a lot of overdraw for scenery;
--   * the PointLight is CAPPED. The end-game kits run brightness 5.0 at range 26,
--     which is right for a stone arcing over a dark lake and turns the wearer into
--     a walking spotlight when it is strapped to their back. Capped rather than
--     scaled so the dim rocks keep their glow and only the offenders come down.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local RockDesign = require(ReplicatedStorage.Modules.RockDesign)

local RockSlingService = {}

local SLING_NAME = "RockSling"
-- Ceilings for the light on a WORN rock. AbsoluteZero throws at 5.0/26; on a back
-- that lit the whole character and the ground around them.
local WORN_LIGHT_MAX_B = 1.1
local WORN_LIGHT_MAX_R = 9
local STRAP_COLOUR = Color3.fromRGB(72, 48, 32)
local BUCKLE_COLOUR = Color3.fromRGB(196, 158, 84)
local POUCH_COLOUR = Color3.fromRGB(94, 64, 42)

local worn = {}    -- [player] = rock id currently shown, so we only rebuild on change
-- [player] = true while something else owns the player's back. Only the ice-fishing
-- event uses it today: during a blizzard a tundra player wears a ROD instead of the
-- satchel, and the rod and the sling occupy the same spot. This has to gate `refresh`
-- rather than just call Remove, because the 1s poll below would rebuild the sling
-- within a second of it being taken off.
local hidden = {}

local function anchorPart(character)
	return character:FindFirstChild("UpperTorso")      -- R15 / Rthro
		or character:FindFirstChild("Torso")           -- R6
		or character:FindFirstChild("HumanoidRootPart") -- last resort, always there
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
	p.Massless = true          -- never change how the character walks or falls
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

function RockSlingService.Remove(character)
	if not character then return end
	local old = character:FindFirstChild(SLING_NAME)
	if old then old:Destroy() end
end

-- Build (or rebuild) the sling on `character` holding rock `rockId`.
function RockSlingService.Apply(character, rockId)
	if not character or not character.Parent then return end
	local torso = anchorPart(character)
	if not torso then return end

	RockSlingService.Remove(character)

	local rig = character:FindFirstChildOfClass("Humanoid")
	local S = torso.Size
	-- R6's Torso is both taller and wider than an R15 UpperTorso, so the strap is
	-- measured off the part rather than assumed.
	local w, h, d = S.X, S.Y, S.Z

	local sling = Instance.new("Model")
	sling.Name = SLING_NAME

	-- ===== THE STRAP: A CROSSBODY LOOP =========================================
	-- This was ONE box: 0.40 x 2.14 x 0.22 on an R15, floating 0.12 studs off the
	-- spine, overhanging the torso top and bottom, and never reaching the chest at
	-- all. A sling goes OVER one shoulder and UNDER the opposite arm, so it has to be
	-- a closed loop around the body -- a panel stuck to one face can never read as one.
	--
	-- The loop is a ring on an ellipse fitted to the torso's own cross-section, tilted
	-- so it rides high on one shoulder and low on the opposite hip:
	--
	--     x = a * cos(t)            a, b  from the torso's width and depth
	--     z = b * sin(t)            amp   how far it climbs, shoulder to hip
	--     y = midY + amp * cos(t)
	--
	-- t = 0 is the wearer's RIGHT (+X is a character's right), so the peak sits on the
	-- right shoulder and the trough under the left arm, while t = pi/2 and t = 3pi/2 --
	-- the back and the chest -- both cross at mid height. That is what makes the
	-- diagonal read as a diagonal from in front as well as from behind.
	--
	-- Every term is a fraction of the anchor part's own Size, so one set of numbers
	-- fits an R6 block, a slim R15 and a wide Rthro with no special cases.
	local TAU = math.pi * 2
	local a    = w * 0.54          -- a shade proud of the body, so it reads as lying ON it
	local b    = d * 0.70          -- torsos are shallow front-to-back; more clearance here
	local amp  = h * 0.46          -- the shoulder-to-hip climb
	local midY = -h * 0.03
	local thick = math.max(0.06, math.min(w, d) * 0.15)
	local band  = math.max(0.12, h * 0.17)

	local function loopPoint(t)
		return Vector3.new(a * math.cos(t), midY + amp * math.cos(t), b * math.sin(t))
	end
	-- outward normal of the ellipse, which is where the band's flat face has to point
	local function radialAt(t)
		return Vector3.new(math.cos(t) / a, 0, math.sin(t) / b).Unit
	end

	-- Frame at t: X radial-out, Y across the band, Z along it. Taken from the ellipse's
	-- own gradient so the band lies FLAT on the body the whole way round -- on a 2 x 1
	-- torso the surface normal swings 90 degrees between the flank and the chest, and a
	-- fixed orientation would leave the strap standing on edge over half its length.
	local function frameAt(t)
		local eps = 0.05
		local tangent = (loopPoint(t + eps) - loopPoint(t - eps)).Unit
		local radial = radialAt(t)
		radial = radial - tangent * radial:Dot(tangent)          -- re-orthogonalise
		radial = (radial.Magnitude > 1e-4) and radial.Unit or Vector3.yAxis
		return CFrame.fromMatrix(loopPoint(t), radial, radial:Cross(tangent))
	end

	-- 14 is the readable minimum on a torso-sized ellipse. It is a part count paid by
	-- every player on the server, so it buys smoothness rather than spending it.
	local SEGMENTS = 14
	for i = 0, SEGMENTS - 1 do
		local t1, t2 = (i / SEGMENTS) * TAU, ((i + 1) / SEGMENTS) * TAU
		local p1, p2 = loopPoint(t1), loopPoint(t2)
		local cf = frameAt((t1 + t2) * 0.5)
		-- 1.3 so consecutive segments overlap: butt-jointed boxes on a curve leave a
		-- visible notch at every joint
		piece(sling, "Strap", Vector3.new(thick, band, (p2 - p1).Magnitude * 1.3),
			torso.CFrame * ((cf - cf.Position) + (p1 + p2) * 0.5),
			STRAP_COLOUR, Enum.Material.Fabric)
	end

	-- pad over the shoulder, buckle on the chest crossing
	piece(sling, "ShoulderPad", Vector3.new(thick * 1.6, band * 1.9, math.max(w, h) * 0.30),
		torso.CFrame * frameAt(0), STRAP_COLOUR, Enum.Material.Fabric)
	piece(sling, "Buckle", Vector3.new(thick * 1.8, band * 1.25, band * 1.25),
		torso.CFrame * frameAt(TAU * 0.75), BUCKLE_COLOUR, Enum.Material.Metal)

	-- ===== THE POUCH ===========================================================
	-- On the LEFT HIP toward the back: the low end of the loop, and where a crossbody
	-- bag actually hangs. Behind the shoulder blade -- where this used to sit -- is a
	-- quiver, not a sling.
	--
	-- Framed against WORLD UP rather than the band's own frame: the band is steeply
	-- diagonal at this point, so inheriting its frame would hang the pouch on the tilt.
	local POUCH_T = math.pi * 0.86
	local pouchSize = Vector3.new(w * 0.44, h * 0.34, d * 0.52)
	local outward = radialAt(POUCH_T)
	local alongBody = Vector3.yAxis:Cross(outward).Unit
	local pouchLocal = CFrame.fromMatrix(loopPoint(POUCH_T), alongBody, Vector3.yAxis)
	local pouchCF = torso.CFrame * (pouchLocal + outward * (pouchSize.Z * 0.42))
	local pouch = piece(sling, "Pouch", pouchSize, pouchCF, POUCH_COLOUR, Enum.Material.Fabric)
	piece(sling, "PouchFlap",
		Vector3.new(pouchSize.X * 1.06, pouchSize.Y * 0.32, pouchSize.Z * 1.06),
		pouchCF * CFrame.new(0, pouchSize.Y * 0.46, 0), STRAP_COLOUR, Enum.Material.Fabric)

	for _, p in ipairs(sling:GetChildren()) do
		if p:IsA("BasePart") then weldTo(p, torso) end
	end

	-- ===== the rock itself =====
	local rock = WorldProgression.RockById(rockId) or WorldProgression.RockById("Pebble")
	if rock then
		local model = RockDesign.Build(rock.Id, rock.Color)
		-- Scale it to sit IN the pouch rather than dwarf the player: rocks are authored
		-- around 2 studs. Measured against the POUCH now rather than the torso, so it
		-- stays in proportion to the thing holding it on every rig. Extents covers the
		-- Fx decoration, not just the core.
		local ext = RockDesign.Extents(model)
		local biggest = math.max(ext.X, ext.Y, ext.Z)
		if biggest > 0 then
			local want = pouchSize.X * 1.15
			local okScale = pcall(function() model:ScaleTo(want / biggest) end)
			if not okScale then
				-- older engines: fall back to scaling the parts by hand
				local k = want / biggest
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then p.Size = p.Size * k end
				end
			end
		end

		-- Sit it ON the pouch rim, measured from the rock's OWN height rather than a
		-- fixed offset. Fixed offsets fail across the ladder: a cosmic rock's extent is
		-- inflated by its ring and shards while its visible core is small, so a lift
		-- that showed a plain stone perfectly buried AbsoluteZero inside the pouch.
		local after = RockDesign.Extents(model)
		local lift = pouchSize.Y * 0.42 + after.Y * 0.30
		model:PivotTo(pouchCF * CFrame.new(0, lift, 0))
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Massless = true
				weldTo(p, pouch)
			elseif p:IsA("Trail") then
				p:Destroy()                 -- a flight wake makes no sense on a worn rock
			elseif p:IsA("ParticleEmitter") then
				p.Rate = p.Rate * 0.5       -- scenery, not a thrown stone
			elseif p:IsA("Light") then
				-- worn, not thrown: see WORN_LIGHT_* above
				p.Brightness = math.min(p.Brightness * 0.35, WORN_LIGHT_MAX_B)
				p.Range = math.min(p.Range * 0.5, WORN_LIGHT_MAX_R)
				p.Shadows = false
			end
		end
		model.Name = "Rock"
		model.Parent = sling
	end

	sling.Parent = character
	return sling
end

local function equippedIdFor(player)
	local data = PlayerDataManager.Get(player)
	if not data then return nil end
	return data.EquippedRock or "Pebble"
end

local function refresh(player, force)
	local character = player.Character
	if not character or not character.Parent then return end
	if hidden[player] then
		-- clear `worn` too, so unhiding always rebuilds rather than deciding the sling
		-- it can no longer see is still up to date
		RockSlingService.Remove(character)
		worn[player] = nil
		return
	end
	local id = equippedIdFor(player)
	if not id then return end
	if not force and worn[player] == id and character:FindFirstChild(SLING_NAME) then return end
	worn[player] = id
	RockSlingService.Apply(character, id)
end

-- Take the satchel off (and keep it off) while something else is worn, or give it back.
-- Idempotent both ways; safe to call for a player who never had one.
function RockSlingService.SetHidden(player, on)
	if on then
		if hidden[player] then return end
		hidden[player] = true
		worn[player] = nil
		if player.Character then RockSlingService.Remove(player.Character) end
	else
		if not hidden[player] then return end
		hidden[player] = nil
		worn[player] = nil
		refresh(player, true)
	end
end

function RockSlingService.IsHidden(player)
	return hidden[player] == true
end

function RockSlingService.Init()
	local function hook(player)
		player.CharacterAdded:Connect(function(character)
			-- wait for the rig to finish assembling, or the weld lands on a part that is
			-- about to be replaced and the sling ends up floating where the player spawned
			character:WaitForChild("Humanoid", 10)
			if not character:FindFirstChild("UpperTorso") and not character:FindFirstChild("Torso") then
				character:WaitForChild("HumanoidRootPart", 10)
			end
			task.wait(0.35)
			worn[player] = nil
			refresh(player, true)

			-- RE-FIT ON RESIZE. Roblox avatar scaling -- BodyWidthScale and friends, a
			-- proportions change, or anything that swaps the HumanoidDescription while
			-- the player is standing there -- works by RESIZING the body parts, and every
			-- measurement in Apply is taken off the anchor's Size at build time. Without
			-- this the sling keeps the shape it was born with and a rescaled avatar wears
			-- the previous body's strap.
			local anchor = anchorPart(character)
			if anchor then
				local queued = false
				anchor:GetPropertyChangedSignal("Size"):Connect(function()
					-- One rebuild per burst: a scale change rewrites several parts in the
					-- same frame and each write fires this.
					if queued then return end
					queued = true
					task.delay(0.2, function()
						queued = false
						if character.Parent and player.Character == character then
							refresh(player, true)
						end
					end)
				end)
			end
		end)
		if player.Character then
			task.defer(function() worn[player] = nil; refresh(player, true) end)
		end
	end

	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	Players.PlayerRemoving:Connect(function(p) worn[p] = nil; hidden[p] = nil end)

	-- Poll rather than hook the shop: EquippedRock is written by ShopHandler's
	-- BuyRock AND EquipRock paths, and a rebirth or a data reload can change it too.
	-- One 1s comparison of a string per player is cheaper than keeping three call
	-- sites in sync, and it self-heals if anything else ever writes the field.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(refresh, p, false)
			end
		end
	end)

	print("RockSlingService online (worn sling, fitted per rig, shows the equipped rock)")
end

return RockSlingService
