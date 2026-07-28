-- CatchReveal: the catch moment.
--
-- When you catch a brainrot, the brainrot ITSELF appears on screen and spins
-- slowly. Four bands over the eight tiers, each adding a NEW KIND of thing
-- rather than more of the last -- the rule that makes the RarityFX and
-- MutationFX ladders readable at a glance:
--
--   1  Common/Uncommon   small viewport, no backdrop
--   2  Rare/Epic         bigger + a coloured halo
--   3  Legendary/Mythic  large + shimmer + sparkles, screen darkened
--   4  Secret/God        a REAL world model, camera locked, full MutationFX
--
-- Why band 4 is not a viewport: ParticleEmitters and Highlight DO NOT RENDER
-- inside a ViewportFrame (BrainrotThumb says as much in its own header), and
-- MutationFX is built entirely from those two. A viewport reveal structurally
-- cannot show a mutation. Secret and God are exactly the catches where a
-- mutation is most worth seeing, so those two get a real model instead.
--
-- This module knows nothing about remotes and nothing about Robux. It is given
-- a catch and it shows it. CatchRevealClient decides whether to call it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local MutationFX = require(ReplicatedStorage.Modules.MutationFX)

-- "None" and "" both mean no mutation in this codebase; normalise once.
local function mutationOf(info)
	local m = info.Mutation
	if type(m) ~= "string" or m == "" or m == "None" then return nil end
	return m
end

local M = {}

local CF = UITheme.Camp
local player = Players.LocalPlayer

local BAND_OF = {
	Common = 1, Uncommon = 1,
	Rare = 2, Epic = 2,
	Legendary = 3, Mythic = 3,
	Secret = 4, God = 4,
}

-- size    viewport square in px
-- hold    seconds fully on screen, excluding the fades
-- dark    how black the backdrop goes, as OPACITY (0 = no backdrop). For band
--         4 this is the WORLD backdrop Part only -- see fallbackDark below.
-- halo    coloured ring behind the model
-- shimmer seconds per shine sweep, or false
-- sparkle how many twinkles
local SPEC = {
	{ size = 180, hold = 1.4, dark = 0.00, halo = false, shimmer = false, sparkle = 0 },
	{ size = 280, hold = 2.0, dark = 0.15, halo = true,  shimmer = false, sparkle = 0 },
	{ size = 380, hold = 2.8, dark = 0.60, halo = true,  shimmer = 2.4,   sparkle = 4 },
	-- Band 4 always tries the world path first (buildWorld, below); this row's
	-- size/hold apply to BOTH paths, but dark and fallbackDark are deliberately
	-- separate numbers for two different mechanisms:
	--   dark         the WORLD backdrop, a lit 3D Part (buildWorld, below).
	--   fallbackDark the UI dim Frame used only when the world path is
	--                blocked and this falls back to a viewport instead -- a
	--                flat 2D overlay at the SAME opacity as a lit 3D Part
	--                reads far heavier (verified live: dark's own 0.92 value,
	--                reused for the fallback, nearly erased the persistent
	--                HUD -- the hotbar and top buttons -- which the world
	--                backdrop never touches at all since it only affects the
	--                3D scene), so the fallback earns its own, lower number.
	-- halo/shimmer/sparkle here are unused placeholders -- M.play borrows band
	-- 3's instead, so a fallen-back Secret never reads sparser than a Mythic.
	{ size = 380, hold = 3.8, dark = 0.92, fallbackDark = 0.75, halo = false, shimmer = false, sparkle = 0 },
}

local SPIN = 70     -- degrees per second, identical in every band
local FADE = 0.22   -- seconds, in and out
local FOV  = 30     -- viewport camera, matches BrainrotThumb

-- fixed sparkle spots so a reveal looks composed rather than random
local SPARKLE_AT = {
	Vector2.new(0.14, 0.22), Vector2.new(0.85, 0.28), Vector2.new(0.24, 0.74),
	Vector2.new(0.78, 0.70), Vector2.new(0.50, 0.10),
}

local gui             -- ScreenGui, built on first use
local live            -- the running reveal's record, or nil
local token = 0

local function ensureGui()
	if gui and gui.Parent then return gui end
	gui = Instance.new("ScreenGui")
	gui.Name = "CatchRevealUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- above the rare-catch banner (8) and every panel (9)
	gui.DisplayOrder = 12
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

-- Safe to call twice, and safe after a natural finish. Everything that can
-- outlive the reveal is torn down here and nowhere else, so there is exactly
-- one path out.
local function teardown(rec)
	if not rec or rec.dead then return end
	rec.dead = true
	if rec.conn then rec.conn:Disconnect(); rec.conn = nil end
	if rec.restore then pcall(rec.restore) end
	if rec.root then rec.root:Destroy(); rec.root = nil end
	if live == rec then live = nil end
end

-- The model, framed and spinning. Returns the per-frame updater, or nil when
-- there is no model for that name (caller falls back to text only).
local function buildViewport(rec, spec, info, parent)
	local master = BrainrotThumb.master(info.Name)
	if not master then return nil end

	local vp = Instance.new("ViewportFrame")
	vp.Name = "Model"
	vp.AnchorPoint = Vector2.new(0.5, 0)
	vp.Position = UDim2.fromScale(0.5, 0)
	vp.Size = UDim2.fromOffset(spec.size, spec.size)
	vp.BackgroundTransparency = 1
	vp.ZIndex = 3
	vp.Parent = parent

	local m = master:Clone()
	m.Parent = vp

	-- Frame from the REAL bounding box: these models run from under 5 studs to
	-- over 30, so one fixed distance would crop the big ones and shrink the
	-- small ones to a dot. Shared with BrainrotThumb.add so the grids and the
	-- reveal cannot disagree about how a model is framed.
	local centre, dist = BrainrotThumb.framing(m, FOV)

	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam

	rec.viewport = vp

	-- Spin the CAMERA around the model, not the model. Rotating the model would
	-- need its pivot moved to the bounding-box centre first, because on these
	-- packs the PrimaryPart is an arbitrary limb sitting anywhere inside the
	-- body -- it would wobble around an off-centre point. Orbiting the camera
	-- is identical on screen and cannot disturb the model at all.
	local base = BrainrotThumb.DEFAULT_DIR
	return function(t)
		local dir = CFrame.Angles(0, math.rad(SPIN) * t, 0) * base
		cam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	end
end

-- === Band 4: a real model in the world ===
--
-- The camera does NOT move -- it only stops taking input. Moving it risks
-- landing inside terrain or a building, and a reveal that ruins your view is
-- worse than one that is merely close. A black backdrop part behind the model
-- does the darkening, because a full-screen UI dim would darken the model too:
-- UI always renders above the 3D world.
-- Task 5 Step 1b: INVERTED from the original design. The model used to sit
-- BEYOND the character (character distance + clearance), which put the
-- player's own avatar -- and whatever it's wearing -- between the camera and
-- the reveal. Measured on this account: a 7.99x4.77x7.74 Tarantula accessory
-- covered the model's middle, and the backdrop (behind the model) darkened
-- nothing nearer than that, so the takeover never read as a takeover.
--
-- Both the model and the backdrop now sit IN FRONT OF the character instead,
-- each derived from where the character actually is (not a fixed camera-
-- relative offset) for the same reason the original code measured the
-- character rather than hardcoding a distance -- a player who has scrolled
-- their zoom in or out still gets numbers that make sense for where they are:
--   dist         = charDist - MODEL_CLEARANCE     (nearer than the character)
--   backdropDist = charDist - BACKDROP_CLEARANCE  (also nearer, but further
--                  out than the model, so ONE panel hides the avatar and
--                  everything past it at once)
-- MODEL_CLEARANCE > BACKDROP_CLEARANCE by construction, so backdropDist is
-- always further from the camera than dist is -- camera < model < backdrop <
-- character holds for any charDist, not just the default one.
local CHAR_DIST_FALLBACK = 13   -- assumed camera->character distance when there is no character to measure from -- Roblox's default third-person shoulder distance
local MODEL_CLEARANCE    = 7    -- studs the model sits in front of the character (~6 studs from the camera at the default distance)
local BACKDROP_CLEARANCE = 3    -- studs the backdrop sits in front of the character -- less than MODEL_CLEARANCE so it always lands BEHIND the model (~10 studs from the camera at the default distance)
local MIN_MODEL_DIST     = 3    -- floor so the model can never land behind or inside the camera's near plane at a tight zoom
local WORLD_HEIGHT       = 5    -- studs tall when dist == CHAR_DIST_FALLBACK - MODEL_CLEARANCE (6, the default-zoom case); scaled proportionally at other distances so the reveal reads the same size regardless of zoom. Lower than the old 7 because the model is now ~4x closer to the camera than before (6 studs vs ~23), so the same physical height reads much bigger on screen -- verified live: 7 filled the frame edge-to-edge and cropped the creature's own silhouette.
local BACKDROP_SIZE      = 400  -- studs square; raised from 260 after a live screenshot showed sky peeking past the top-right corner at the closer ~10-stud backdrop distance -- the corner of a wide viewport reaches slightly further than a naive half-FOV estimate suggests

-- Task 5 final fix wave -- CRITICAL: the model below used to be normalised by
-- HEIGHT ALONE, but it spins continuously about world Y, so its real reach is
-- the horizontal HALF-DIAGONAL of its footprint (0.5*sqrt(X^2+Z^2)) at every
-- instant, not either axis extent alone. That distinction doesn't matter for
-- a static display -- BrainrotSpawner and InventoryHandler both clamp
-- min(height factor, width factor) and that is correct for THEM, because
-- their models never turn -- but nothing here bounded the ROTATING reach at
-- all: the same maths run over every Secret/God model found 6 of 12 sweeping
-- past the backdrop, two of them (Tralalero Tralala and Los Tralaleritos --
-- the tier's two heaviest catch weights) sweeping clean through the camera,
-- at every zoom. These constants are the safety margin added on top of the
-- two hard constraints (sweep < dist; dist + sweep < backdropAt).
local SWEEP_CAM_GAP      = 0.5  -- studs the model's sweep must stay short of the camera
local SWEEP_BACKDROP_GAP = 0.5  -- studs the model's sweep must stay short of the backdrop
local MIN_SWEEP_BUDGET   = 1    -- studs; below this the world path isn't worth it -- bail to viewport (see the charDist guard below)

local function stripScripts(model)
	-- ReplicatedStorage.BrainrotModels is verified 0 scripts today, but this
	-- pack has carried embedded free-model scripts before and they only run
	-- OUTSIDE Studio, so they can never be caught by testing here.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then d:Destroy() end
	end
end

-- Rotation-only CFrame that points world -Z at `worldDir`, flattened to the
-- horizontal plane first (Y dropped, then re-normalised). Every rotation
-- buildWorld hands to PivotTo is composed from CFrames built by this
-- function, so every one of them is a pure yaw about world Y -- which is
-- what fixes BOTH the facing bug and the spin-axis bug below: neither the
-- camera's pitch nor its roll can ever enter the model's rotation.
local function flatYawCFrame(worldDir)
	local flat = Vector3.new(worldDir.X, 0, worldDir.Z)
	if flat.Magnitude < 1e-4 then flat = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(Vector3.new(), flat.Unit)
end

-- BrainrotThumb's own front-quarter offset, flattened to a pure yaw (its
-- Y=0.45 "slightly above" component is dropped: this model has to stay
-- UPRIGHT -- see the spin-axis fix below -- so only the horizontal twist can
-- carry over). Computed once at require-time since DEFAULT_DIR never changes.
local DEFAULT_YAW = flatYawCFrame(BrainrotThumb.DEFAULT_DIR)

local function buildWorld(rec, spec, info, fades)
	local cam = workspace.CurrentCamera
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local src = folder and folder:FindFirstChild(info.Name)
	if not cam or not src then return nil end

	local origin = cam.CFrame

	-- Nearer the camera than the character now, not farther -- see the header
	-- comment above (Task 5 Step 1b). charDist assumes CHAR_DIST_FALLBACK when
	-- there is no character to measure, so the same formula covers both cases.
	local charRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local charDist = charRoot and (charRoot.Position - origin.Position).Magnitude or CHAR_DIST_FALLBACK

	-- Clamped two ways: never closer to the camera than MIN_MODEL_DIST (the
	-- near-plane floor), and never further out than the character itself even
	-- at an extremely tight zoom -- "nearer than the character" must hold
	-- REGARDLESS of charDist, not just at the default distance.
	-- MIN_MODEL_DIST used to be a floor in name only: math.min(charDist - 1, ...)
	-- was the OUTER call, so whenever charDist - 1 fell below MIN_MODEL_DIST
	-- (charDist < 4) that ceiling silently overrode the floor -- live-recorded
	-- at charDist ~1.8 (Roblox's own camera collision pulling the camera in),
	-- which drove dist, and worldHeight below, both non-positive. Once the
	-- character is this close there is no valid gap left to put a model in at
	-- all, so that regime bails to nil instead of computing a nonsense
	-- distance -- M.play already falls back to the viewport whenever
	-- buildWorld returns nil, the same as a blocked sightline.
	if charDist - 1 < MIN_MODEL_DIST then return nil end
	local dist = math.clamp(charDist - MODEL_CLEARANCE, MIN_MODEL_DIST, charDist - 1)

	-- A second, narrower bail: even once dist clears the floor above, the
	-- backdrop's OWN ceiling (charDist - 0.5, so it never reaches the
	-- character) can end up almost flush against dist, leaving no room for a
	-- sweep budget worth animating -- verified charDist == 4 exactly crushes
	-- every model in the roster to zero height even though neither hard
	-- constraint below is technically violated. Below this, fall back too.
	if (charDist - 0.5) - dist < SWEEP_BACKDROP_GAP + MIN_SWEEP_BUDGET then return nil end

	local spot = origin * CFrame.new(0, 0, -dist)

	-- Facing + spin axis (Task 5 final fix wave -- two review findings fixed
	-- together since both live in this same rotation).
	--   FACING: a bare `spot` inherits the CAMERA's rotation, and the models
	--   are authored facing -Z, so at t=0 the model's front used to point the
	--   same way the camera looks -- directly AWAY from the camera it's
	--   sitting in front of (measured dot(front, toCamera) == -1.000).
	--   dueCamera is the pure-yaw rotation that faces the model dead at the
	--   camera instead; composing DEFAULT_YAW on top reproduces the SAME
	--   front-quarter angle BrainrotThumb's orbiting camera opens bands 1-3
	--   on (both are pure-Y rotations, so they commute -- only the SUM of the
	--   two yaws matters, not the order).
	--   SPIN AXIS: dueCamera, DEFAULT_YAW and the per-frame spin in poseAt
	--   below are ALL built from flatYawCFrame, i.e. all pure yaw about world
	--   Y -- never the camera's own up vector, which tilts with camera pitch
	--   (measured 5.7 degrees of wobble at 10 degrees of pitch, worse
	--   steeper) and is what the old `spot`-inherited rotation actually spun
	--   the model around.
	local dueCamera = flatYawCFrame(-origin.LookVector)
	local baseRot = dueCamera * DEFAULT_YAW
	local function poseAt(t)
		return CFrame.new(spot.Position) * CFrame.Angles(0, math.rad(SPIN) * t, 0) * baseRot
	end

	-- If real, VISIBLE geometry sits between the camera and the reveal spot the
	-- model would be hidden behind it. Rather than shove the camera somewhere it
	-- might not fit, fall back to the viewport path -- a Secret that looks like
	-- a Legendary beats a Secret you cannot see. But in this engine build,
	-- CanCollide=true overrides CanQuery=false for workspace:Raycast, so the
	-- lake's invisible collision walls (CanQuery=false, CanCollide=true, fully
	-- transparent) register as hits despite being nothing a player can see --
	-- measured 37/84 clear across the dock's real stance spots before this
	-- loop, 84/84 after. A fully-transparent hit is not a visual obstruction:
	-- exclude it and cast again, bounded so a stack of invisible parts can't
	-- spin forever. `blocked` starts true and only clears on a genuine no-hit
	-- cast -- measured a maximum of 4 consecutive transparent hits across 168
	-- real casts (cap is 6, so there is headroom), but exhausting the cap
	-- without ever reaching a clean cast must still fail SAFE: an unresolved
	-- line of sight is exactly the kind of obstruction nobody verified, so it
	-- falls back rather than assuming clear.
	local exclude = { player.Character }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local blocked = true
	for _ = 1, 6 do
		local hit = workspace:Raycast(origin.Position, (spot.Position - origin.Position), params)
		if not hit then
			blocked = false
			break
		elseif hit.Instance:IsA("BasePart") and hit.Instance.Transparency >= 1 then
			table.insert(exclude, hit.Instance)
			params.FilterDescendantsInstances = exclude
		else
			break
		end
	end
	if blocked then return nil end

	-- Capture savedType and assign rec.restore BEFORE anything is parented or
	-- the camera is touched. If a throw happens anywhere below -- cloning,
	-- scaling, parenting, or the camera assignment itself -- M.play's pcall
	-- calls teardown(rec), which calls rec.restore if one is SET. Assigning it
	-- this early, with rec.worldModel/rec.backdrop nil-checked inside it so it
	-- is safe to call before either exists, closes the window where a throw
	-- could leave the model or backdrop stranded outside rec.root's tree (so
	-- teardown's rec.root:Destroy() can't reach them) or the camera stuck
	-- Scriptable with nothing left to undo it -- unrecoverable without
	-- rejoining.
	local savedType = cam.CameraType
	rec.restore = function()
		if rec.worldModel then rec.worldModel:Destroy(); rec.worldModel = nil end
		if rec.backdrop then rec.backdrop:Destroy(); rec.backdrop = nil end
		local c = workspace.CurrentCamera
		if c then c.CameraType = savedType end
	end

	local m = src:Clone()
	stripScripts(m)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
		end
	end

	-- Pivot about the bounding-box centre BEFORE scaling, not after: ScaleTo
	-- scales around the model's CURRENT pivot, and on these packs the
	-- PrimaryPart is an arbitrary limb sitting anywhere inside the body.
	-- Scaling around that off-centre point drags the bounding-box centre along
	-- with it (measured a 3.75-stud shift on a real model) -- pivoting here
	-- first means there is nothing off-centre left to scale around. One
	-- GetBoundingBox call covers both the centre (for the pivot) and the
	-- Y-extent (for the scale factor) since nothing between them moves a part.
	m.PrimaryPart = nil
	local preScale, ext = m:GetBoundingBox()
	m.WorldPivot = CFrame.new(preScale.Position)

	-- WORLD_HEIGHT was tuned to read right when dist is CHAR_DIST_FALLBACK -
	-- MODEL_CLEARANCE (the default-zoom case); scale proportionally at other
	-- distances so the reveal is the same apparent size regardless of zoom.
	local worldHeight = WORLD_HEIGHT * (dist / (CHAR_DIST_FALLBACK - MODEL_CLEARANCE))
	-- Between the model and the character at every distance: always a little
	-- further out than the model, always a little short of the character, so
	-- one panel hides the avatar and the world beyond it at once. Overridden
	-- below, once the model's real footprint is known, if its sweep needs more
	-- room than this default gives it.
	local backdropAt = math.min(charDist - 0.5, math.max(dist + 2, charDist - BACKDROP_CLEARANCE))

	-- ScaleTo is ABSOLUTE. Re-measuring an already-scaled model and calling it
	-- again resets to authored size, so always multiply the CURRENT scale.
	-- `factor` starts as the naive, HEIGHT-ONLY value -- the critical bug, on
	-- its own -- and the sweep clamp below corrects it before it is ever
	-- applied to the model.
	if ext.Y > 0 then
		local factor = worldHeight / ext.Y

		-- The model's real reach while it spins: the half-diagonal of its
		-- horizontal footprint at whatever scale `factor` currently is. A
		-- rotating rectangle's farthest point from its own centre is always its
		-- corner, at every angle, so this bounds the sweep regardless of where
		-- in the spin the model happens to be at any given instant.
		local halfDiag = 0.5 * math.sqrt(ext.X * ext.X + ext.Z * ext.Z)
		local sweep = halfDiag * factor

		-- Reviewer's suggested order, because it costs far less height than
		-- clamping the scale first: PUSH THE BACKDROP OUT to cover this sweep
		-- before touching the scale at all -- ADDING a term to the existing
		-- floor above rather than replacing it, so a model whose sweep already
		-- fits (every "clean" Secret/God at the shipped defaults) gets the exact
		-- same backdropAt as before. Still capped at charDist - 0.5 so the
		-- backdrop can never reach or pass the character.
		backdropAt = math.min(charDist - 0.5, math.max(dist + 2, charDist - BACKDROP_CLEARANCE, dist + sweep + SWEEP_BACKDROP_GAP))

		-- Only NOW clamp the scale, and only if pushing the backdrop out
		-- couldn't fully absorb the sweep (backdropAt hit its charDist - 0.5
		-- ceiling short of what was needed) or the sweep alone already reaches
		-- the camera regardless of the backdrop. maxSweep is always positive
		-- here: dist >= MIN_MODEL_DIST and backdropAt >= dist + 2 by
		-- construction, and the MIN_SWEEP_BUDGET guard above already turned away
		-- the charDist range where that would leave no room at all.
		local maxSweep = math.min(dist - SWEEP_CAM_GAP, backdropAt - dist - SWEEP_BACKDROP_GAP)
		if sweep > maxSweep and halfDiag > 0 then
			factor = math.min(factor, maxSweep / halfDiag)
		end

		m:ScaleTo(m:GetScale() * factor)
	end

	-- Re-measure rather than assume the centre held: cheap, and the per-frame
	-- PivotTo below must be exact. This one CANNOT fold into the call above --
	-- ScaleTo has genuinely moved the parts in between.
	local postScale = m:GetBoundingBox()
	m.WorldPivot = CFrame.new(postScale.Position)

	-- Pose it correctly BEFORE parenting: the spin function returned below
	-- only runs on the next RenderStepped, so without this the clone would
	-- render for one frame at whatever coordinates it was authored at in
	-- BrainrotModels.
	m:PivotTo(poseAt(0))
	m.Parent = workspace          -- client-created: never replicates
	rec.worldModel = m

	-- The payoff for the hybrid. pcall because a bad mutation must never cost
	-- the player the reveal -- showing the creature matters more than tinting it.
	local mut = mutationOf(info)
	if mut then pcall(MutationFX.apply, m, mut) end

	local backdrop = Instance.new("Part")
	backdrop.Name = "CatchRevealBackdrop"
	backdrop.Size = Vector3.new(BACKDROP_SIZE, BACKDROP_SIZE, 1)
	backdrop.CFrame = origin * CFrame.new(0, 0, -backdropAt)
	backdrop.Anchored = true
	backdrop.CanCollide = false
	backdrop.CanQuery = false
	backdrop.CanTouch = false
	backdrop.CastShadow = false
	backdrop.Material = Enum.Material.SmoothPlastic
	backdrop.Color = Color3.new(0, 0, 0)
	backdrop.Transparency = 1
	backdrop.Parent = workspace
	rec.backdrop = backdrop
	-- Fades in alongside everything else (M.play's own fade-in loop, right
	-- after this function returns) and back OUT the same way at teardown --
	-- this used to be tweened in directly, right here, and never registered in
	-- `fades`, so nothing ever tweened it back out: the backdrop (and the
	-- model behind it) snapped to gone in a single frame while the labels were
	-- still mid-fade.
	table.insert(fades, { backdrop, "Transparency", 1 - spec.dark })

	-- Freeze the camera where it already is. rec.restore (above) already knows
	-- how to undo this.
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = origin

	-- A camera left Scriptable is unrecoverable without rejoining, so it gets a
	-- second, independent guard on top of teardown -- the same belt-and-braces
	-- as ThrowHandler's flight watchdog.
	task.delay(FADE * 2 + spec.hold + 3, function()
		if not rec.dead then teardown(rec) end
	end)

	return function(t)
		if rec.worldModel and rec.worldModel.Parent then
			rec.worldModel:PivotTo(poseAt(t))
		end
	end
end

function M.isPlaying()
	return live ~= nil and not live.dead
end

-- info = { Name, Rarity, RarityColor, Mutation }
-- Returns a handle with :skip(), or nil if nothing could be shown.
function M.play(info)
	if type(info) ~= "table" or type(info.Name) ~= "string" then return nil end

	-- newest wins, matching the resultToken behaviour the old card had
	if live then teardown(live) end
	token += 1
	local myToken = token

	local band = BAND_OF[info.Rarity] or 1
	local spec = SPEC[band]
	local accent = typeof(info.RarityColor) == "Color3" and info.RarityColor
		or Color3.fromRGB(190, 190, 190)

	-- Bands 1-3 are viewports, where ParticleEmitters and Highlight render
	-- nothing, so MutationFX cannot appear. The mutation is carried by the halo
	-- colour and the name prefix instead.
	local mut = mutationOf(info)
	local haloColour = accent
	if mut then
		-- Guarded the same way as MutationFX.apply below: an unknown name or a
		-- future throw inside MutationConfig must never escape M.play's pcall --
		-- the reveal must never be able to block the catch that triggered it.
		local ok, mc = pcall(Mutations.Color, mut)
		if ok and typeof(mc) == "Color3" then haloColour = mc end
	end

	local rec = { dead = false, token = myToken }

	-- Everything below touches live Instances and third-party modules
	-- (BrainrotThumb, UITheme). It all runs inside ONE pcall: rec is reachable
	-- from the instant root is parented below, so no matter how far
	-- construction gets before something throws, teardown(rec) can still find
	-- and destroy whatever was built. Reveal must never be able to break the
	-- catch that triggered it.
	local ok, err = pcall(function()
		local root = Instance.new("Frame")
		root.Name = "Reveal"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.ZIndex = 1
		root.Parent = ensureGui()
		rec.root = root

		local fades = {}   -- {inst, prop, to}

		-- Decide the render path FIRST, before any UI flair is built. A world
		-- reveal draws its own backdrop and (Task 3) its own MutationFX, so it
		-- must carry none of the dim/halo/shimmer/sparkle -- and a fallback must
		-- carry band 3's flair, not band 4's own empty placeholders, so a
		-- fallen-back Secret is never sparser than a Mythic. Building the UI
		-- AFTER this decision (rather than building flair, then discovering band
		-- 4 didn't want it) is what makes that possible.
		local spin
		if band == 4 then
			spin = buildWorld(rec, spec, info, fades)
		end

		-- effective is what the REST of this function actually builds from.
		-- World path (spin already set): nothing but the labels. Band-4
		-- fallback: band 4's own size/hold/dark, but band 3's halo/shimmer/
		-- sparkle. Bands 1-3: spec, unchanged.
		local effective = spec
		if spin then
			effective = { size = spec.size, hold = spec.hold, dark = 0,
				halo = false, shimmer = false, sparkle = 0 }
		elseif band == 4 then
			effective = { size = spec.size, hold = spec.hold, dark = spec.fallbackDark,
				halo = SPEC[3].halo, shimmer = SPEC[3].shimmer, sparkle = SPEC[3].sparkle }
		end

		-- backdrop. Stated as OPACITY in SPEC, so invert it here -- "dark 0.8" read
		-- as a transparency would mean the opposite of what is intended.
		if effective.dark > 0 then
			local dim = Instance.new("Frame")
			dim.Name = "Dim"
			dim.Size = UDim2.fromScale(1, 1)
			dim.BackgroundColor3 = Color3.new(0, 0, 0)
			dim.BackgroundTransparency = 1
			dim.BorderSizePixel = 0
			dim.ZIndex = 1
			dim.Parent = root
			table.insert(fades, { dim, "BackgroundTransparency", 1 - effective.dark })
		end

		local holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.42)   -- above centre, clear of the hotbar
		holder.Size = UDim2.fromOffset(effective.size, effective.size + 92)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 2
		holder.Parent = root

		-- halo: an oversized ring behind the model carrying a coloured stroke
		local haloStroke
		if effective.halo then
			local halo = Instance.new("Frame")
			halo.Name = "Halo"
			halo.AnchorPoint = Vector2.new(0.5, 0.5)
			halo.Position = UDim2.new(0.5, 0, 0, effective.size / 2)
			halo.Size = UDim2.fromOffset(effective.size * 0.86, effective.size * 0.86)
			halo.BackgroundTransparency = 1
			halo.ZIndex = 2
			halo.Parent = holder
			local hc = Instance.new("UICorner")
			hc.CornerRadius = UDim.new(1, 0)
			hc.Parent = halo
			haloStroke = Instance.new("UIStroke")
			haloStroke.Color = haloColour
			haloStroke.Thickness = 6
			haloStroke.Transparency = 1
			haloStroke.LineJoinMode = Enum.LineJoinMode.Round
			haloStroke.Parent = halo
			table.insert(fades, { haloStroke, "Transparency", 0.35 })
		end

		if not spin then
			spin = buildViewport(rec, effective, info, holder)
		end
		if rec.viewport then
			rec.viewport.ImageTransparency = 1
			table.insert(fades, { rec.viewport, "ImageTransparency", 0 })
		end

		-- shimmer lives on its OWN empty frame, never on anything holding text: a
		-- UIGradient tints its parent's glyphs too, which has bitten this codebase.
		local shimmerGrad
		if effective.shimmer then
			local shim = Instance.new("Frame")
			shim.Name = "Shimmer"
			shim.Size = UDim2.fromOffset(effective.size, effective.size)
			shim.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			shim.BackgroundTransparency = 0
			shim.BorderSizePixel = 0
			shim.ZIndex = 4
			shim.Parent = holder
			shimmerGrad = Instance.new("UIGradient")
			shimmerGrad.Rotation = 24
			shimmerGrad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.44, 1),
				NumberSequenceKeypoint.new(0.50, 0.62),
				NumberSequenceKeypoint.new(0.56, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
			shimmerGrad.Parent = shim
		end

		local sparkles = {}
		for i = 1, effective.sparkle do
			local at = SPARKLE_AT[i] or SPARKLE_AT[1]
			local s = Instance.new("TextLabel")
			s.Name = "Sparkle"
			s.AnchorPoint = Vector2.new(0.5, 0.5)
			s.Position = UDim2.new(at.X, 0, 0, at.Y * effective.size)
			s.Size = UDim2.fromOffset(40, 40)
			s.BackgroundTransparency = 1
			s.Font = UITheme.GlyphFont
			s.Text = "\u{2726}"
			s.TextColor3 = Color3.fromRGB(255, 255, 255)
			s.TextSize = 26
			s.TextTransparency = 1
			s.ZIndex = 5
			s.Parent = holder
			sparkles[i] = s
		end

		-- name, then rarity. No panel behind either -- that is the whole point.
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "BrainrotName"
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.Position = UDim2.new(0.5, 0, 0, effective.size + 6)
		nameLabel.Size = UDim2.fromOffset(effective.size + 160, 40)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = UITheme.Font
		nameLabel.TextSize = 30
		nameLabel.TextColor3 = CF.onDark
		nameLabel.TextScaled = false
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = mut and (mut .. " " .. info.Name) or info.Name
		nameLabel.TextTransparency = 1
		nameLabel.ZIndex = 6
		nameLabel.Parent = holder
		local nameInk = UITheme.inkText(nameLabel, 3)
		nameInk.Transparency = 1

		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "Rarity"
		rarityLabel.AnchorPoint = Vector2.new(0.5, 0)
		rarityLabel.Position = UDim2.new(0.5, 0, 0, effective.size + 48)
		rarityLabel.Size = UDim2.fromOffset(effective.size + 160, 32)
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Font = UITheme.Font
		rarityLabel.TextSize = 23
		rarityLabel.TextColor3 = accent
		rarityLabel.Text = string.upper(tostring(info.Rarity or "?"))
		rarityLabel.TextTransparency = 1
		rarityLabel.ZIndex = 6
		rarityLabel.Parent = holder
		local rarityInk = UITheme.inkText(rarityLabel, 2.6)
		rarityInk.Transparency = 1

		table.insert(fades, { nameLabel, "TextTransparency", 0 })
		table.insert(fades, { rarityLabel, "TextTransparency", 0 })
		table.insert(fades, { nameInk, "Transparency", 0 })
		table.insert(fades, { rarityInk, "Transparency", 0 })

		-- fade in
		for _, f in ipairs(fades) do
			TweenService:Create(f[1], TweenInfo.new(FADE), { [f[2]] = f[3] }):Play()
		end

		-- One driver for this reveal, disconnected in teardown. Nothing per-frame
		-- survives the reveal.
		local t = 0
		rec.conn = RunService.RenderStepped:Connect(function(dt)
			t += dt
			if spin then spin(t) end
			-- Guarded to [FADE, FADE+hold]: outside that window a TWEEN owns
			-- Transparency (the fade-in below FADE, the fade-out above hold) and
			-- this per-frame set would win the race every single frame, which is
			-- why the halo used to SNAP in instead of fading (known since Task 1).
			-- The phase is shifted so the oscillation's own start (sin = -1, its
			-- trough) lands exactly on 0.35 -- the value the fade-in tween was
			-- already headed to -- so handing off from tween to handler at t=FADE
			-- is seamless instead of jumping to the oscillation's t=0 value.
			if haloStroke and t >= FADE and t <= FADE + effective.hold then
				haloStroke.Transparency = 0.35 + 0.22 * (0.5 + 0.5 * math.sin((t - FADE) * 2.1 - math.pi / 2))
			end
			if shimmerGrad then
				shimmerGrad.Offset = Vector2.new(((t / effective.shimmer) % 1) * 2.6 - 1.3, 0)
			end
			for i = 1, #sparkles do
				local k = 0.5 + 0.5 * math.sin(t * 3.1 + i * 1.9)
				sparkles[i].TextTransparency = 1 - k
				sparkles[i].TextSize = 14 + 14 * k
			end

			-- Band 4's rainbow. There is no card or border in a world reveal for a
			-- cycling colour to live on, so the rarity label carries it -- the same
			-- one-property technique RarityFX uses on Secret/God tiles.
			if band == 4 then
				rarityLabel.TextColor3 = Color3.fromHSV((t * 0.3) % 1, 0.82, 1)
			end
		end)

		live = rec

		-- hold, fade out, tear down
		task.delay(FADE + effective.hold, function()
			if rec.dead or rec.token ~= token then return end
			for _, f in ipairs(fades) do
				local back = (f[2] == "ImageTransparency" or f[2] == "TextTransparency"
					or f[2] == "Transparency" or f[2] == "BackgroundTransparency") and 1 or 0
				TweenService:Create(f[1], TweenInfo.new(FADE), { [f[2]] = back }):Play()
			end
			task.delay(FADE, function()
				if rec.token == token then teardown(rec) end
			end)
		end)
	end)

	if not ok then
		warn(("[CatchReveal] M.play failed while building the reveal -- tearing down: %s"):format(tostring(err)))
		teardown(rec)
		return nil
	end

	return {
		skip = function()
			teardown(rec)
		end,
	}
end

return M
