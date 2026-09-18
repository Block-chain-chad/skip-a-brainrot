-- BrainrotThumb: shared 3D thumbnail helper.
--
-- Renders a real brainrot model into a ViewportFrame, the way Pet Simulator
-- shows its pets. Two grids need this (the Index and the Backpack) and each was
-- about to grow its own copy of the camera maths, so it lives here once.
--
-- Masters are built ONCE per name and kept UNPARENTED; every viewport gets a
-- CLONE, because a tile dies with its rebuild and would take a shared master
-- down with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}

local modelFolder = ReplicatedStorage:FindFirstChild("BrainrotModels")
local cache = {}   -- [name] = master Model, or false for "nothing to render"

-- PETS LIVE IN A DIFFERENT FOLDER, keyed differently. BrainrotModels children are named
-- after the creature's DISPLAY name ("Tung Tung"); PetModels children are named after the
-- .glb basename PetConfig calls Model ("pet_01_mosslarva"). Looking a pet up by its
-- display name in BrainrotModels therefore misses twice over -- wrong folder AND wrong
-- key -- which is why every pet in the bag rendered as a flat swatch.
local petFolder = ReplicatedStorage:FindFirstChild("PetModels")
local petCache = {}

-- ---------------------------------------------------------------------------
-- MeshPart.RenderFidelity CARRIES THE `Plugin` CAPABILITY: Studio may write it,
-- A LIVE CLIENT MAY NOT. Writing it from the shipped game raises
--     The current thread cannot write 'RenderFidelity' (lacking capability Plugin)
-- which is a THROW, not a warning.
--
-- This is why it matters here (live, 2026-08-24): addMaster forced Precise on
-- every MeshPart of every clone. In Studio that is silently permitted, so every
-- test passed. In the real game it threw on the first MeshPart of the first
-- card -- and because GameHUDPanels wraps each panel build in a pcall, the
-- failure was swallowed whole and the BAG and the SELL panel simply never
-- opened. Clicking them did nothing, with no error a player could see.
--
-- Probed ONCE and cached, rather than pcall-per-part: the answer is a property
-- of the runtime, not of the part, and this runs for every part of every card.
-- Where the write is allowed nothing changes; where it is not, the model still
-- renders on Automatic -- which is how the pack ships anyway. Never make this
-- write unconditional again, however tempting Studio makes it look.
local fidelityWritable   -- nil = not yet probed, then true/false for the session
local function forcePrecise(part)
	if fidelityWritable == false then return end
	if fidelityWritable == nil then
		fidelityWritable = pcall(function()
			part.RenderFidelity = Enum.RenderFidelity.Precise
		end)
		return
	end
	part.RenderFidelity = Enum.RenderFidelity.Precise
end
M.ForcePrecise = forcePrecise   -- shared, so no other module re-invents the trap

-- Viewports only draw BaseParts, but a real model also carries emitters,
-- prompts, billboards, sounds and scripts. Those render nothing and make every
-- clone heavier, so the master is stripped once and all clones inherit it.
local function strip(model)
	for _, d in ipairs(model:GetDescendants()) do
		local keep = d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder")
			or d:IsA("SpecialMesh") or d:IsA("Texture") or d:IsA("Decal")
		if not keep then d:Destroy() end
	end
	return model
end

function M.master(name)
	if cache[name] == nil then
		local real = modelFolder and modelFolder:FindFirstChild(name)
		-- false, not nil: a name with no model must not re-run the lookup on
		-- every rebuild
		cache[name] = real and strip(real:Clone()) or false
	end
	return cache[name] or nil
end

-- Master for a PET. modelName is PetConfig's Model field (the .glb basename), displayName
-- its human name. Falls through to the brainrot lookup on the display name, which is what
-- keeps the ten RETIRED stand-in pets (they are brainrots, and have no PetModels entry)
-- rendering for anyone who still owns one.
function M.petMaster(modelName, displayName)
	local key = modelName or displayName
	if not key then return nil end
	if petCache[key] == nil then
		local real = petFolder and ((modelName and petFolder:FindFirstChild(modelName))
			or (displayName and petFolder:FindFirstChild(displayName)))
		petCache[key] = real and strip(real:Clone()) or false
	end
	local master = petCache[key]
	if master then return master end
	return displayName and M.master(displayName) or nil
end

-- Master for an EGG. Same contract as master()/petMaster(): stripped, cached,
-- kept unparented, cloned per viewport. Eggs live in their own folder
-- (ReplicatedStorage.EggModels.<World>) keyed by EggConfig's Model field, which
-- is why neither of the lookups above finds them.
local eggCache = {}
function M.eggMaster(modelName, worldId)
	if not modelName then return nil end
	local key = (worldId or "Forest") .. "/" .. modelName
	if eggCache[key] == nil then
		local root = game:GetService("ReplicatedStorage"):FindFirstChild("EggModels")
		local world = root and root:FindFirstChild(worldId or "Forest")
		local real = world and world:FindFirstChild(modelName)
		eggCache[key] = real and strip(real:Clone()) or false
	end
	return eggCache[key] or nil
end

-- HOW BRIGHT IS THIS MODEL? Volume-weighted mean luminance of its parts (Rec. 709),
-- cached per master under WEAK keys so a discarded master is still collectable.
--
-- Why any caller needs this (2026-08-25): the card surfaces went WHITE in the PS99
-- restyle on 2026-08-16, and every thumbnail here is lit from within ~10 degrees of
-- the camera axis (callers pass a light direction that is very nearly -DEFAULT_DIR).
-- A frontal light means each visible face computes
--     albedo * (ambient + NdotL)
-- which CLIPS TO 1.0 for anything pale. So a pale model does not render dim, it
-- renders as a white silhouette on a white card: invisible.
--
-- Measured: 14 of the 30 pets and 21 of the 215 brainrots sit at or above
-- PALE_LUMINANCE, and the entire Tundra snow set is AT card-white (Snowpuff 0.960,
-- Orso Frigorifero 0.965, against a 0.96 card).
--
-- This exists to darken whatever sits BEHIND the art. It is deliberately NOT a
-- lighting fix: dropping the ambient and swinging the key light to the side was
-- built and captured side by side, and it still lost the palest models while
-- turning the dark ones muddy.
local lumCache = setmetatable({}, { __mode = "k" })
M.PALE_LUMINANCE = 0.72
function M.meanLuminance(master)
	if not master then return nil end
	local hit = lumCache[master]
	if hit ~= nil then return hit end
	local vol, sum = 0, 0
	for _, d in ipairs(master:GetDescendants()) do
		if d:IsA("BasePart") then
			-- Weighted by VOLUME, not part count: a model reads as its mass. Spirit
			-- Fawn is 119 parts, but 95.4% of its volume is one cream (#E8E4D4), and
			-- counting parts would let 20 tiny motes outvote the whole body.
			local v = d.Size.X * d.Size.Y * d.Size.Z
			local c = d.Color
			vol += v
			sum += (0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B) * v
		end
	end
	local lum = if vol > 0 then sum / vol else 0.5
	lumCache[master] = lum
	return lum
end

-- "Is this art pale enough to need a darker backdrop?" A nil master (no model at
-- all) answers false -- a missing-art placeholder has its own treatment.
function M.isPale(master)
	local lum = M.meanLuminance(master)
	return lum ~= nil and lum >= M.PALE_LUMINANCE
end

-- front-quarter, slightly above; bodies stand on Y=0 facing -Z
local DEFAULT_DIR = Vector3.new(0.9, 0.45, -1).Unit
M.DEFAULT_DIR = DEFAULT_DIR

-- PER-MODEL FACING OVERRIDE (name -> extra yaw in degrees, applied on top of the
-- pivot-relative aim in addMaster). The pivot aim fixes models rotated as a whole,
-- but a handful are MODELLED with their face on the pivot's BACK (e.g. a camel
-- whose neck curls back over its spine), which no automatic rule can detect. List
-- those here; 180 shows the opposite side, 90/270 a side. Add a name, reload, done.
M.FACING = {
	-- ["Frigo Camelo"] = 180,
}

-- THE ICE-FISHING PACK IS MODELLED TO A DIFFERENT CONVENTION (2026-08-23). Everything
-- above assumes front = pivot-local -Z, which holds for all 162 valley models and for the
-- land tundra ones -- including the ~90 whose pivot is yawed 180, because the aim is taken
-- through the pivot. The 23 Origin = "IceFishing" fish are the exception: they are built
-- lengthwise along Z with the HEAD at +Z, so DEFAULT_DIR lands the camera behind the tail
-- and the card shows a narrow sliver of fish arse. Verified by photographing the models at
-- identity rotation from each axis.
--
-- 180: a straight about-face, so the head comes round to the camera. This was briefly 135,
-- which swings the view to a broadside -- correct for a field-guide plate, but the owner
-- wants these facing FORWARD like every other card, so the extra 45 is gone.
--
-- Derived from the roster rather than listed by name so a new fish inherits it for free.
-- `or` so an explicit per-model entry above still wins.
do
	local okT, Tundra = pcall(function()
		return require(game:GetService("ReplicatedStorage").Modules.BrainrotConfigTundra)
	end)
	if okT and type(Tundra) == "table" then
		for _, e in ipairs(Tundra) do
			if e.Origin == "IceFishing" and e.Name then
				M.FACING[e.Name] = M.FACING[e.Name] or 180
			end
		end
	end
end

-- Where to put a camera so a model of any size fills the frame: the point it
-- looks at, and how far back to stand. Extracted so CatchReveal can ORBIT the
-- camera using the same numbers add() uses to place it once -- two copies of
-- this calculation would drift.
-- Frames the model's BOUNDING SPHERE, not its largest axis.
--
-- The old form used max(ext.X, ext.Y, ext.Z), which is only correct when the camera
-- looks straight down an axis. Every caller here looks from DEFAULT_DIR, a front-quarter
-- diagonal, and the hatch reveal SPINS the model through every angle -- across a diagonal
-- a chunky model's silhouette is its space diagonal, far wider than any single axis. A
-- roughly-cubic pet therefore overflowed its card by about a third and got cropped at the
-- edges. The bounding sphere is the one radius that holds at every rotation, which is
-- exactly what a spinning reveal needs.
--
-- radius / sin(fov/2) puts the sphere exactly tangent to the frustum; MARGIN pushes the
-- camera back a little further so the silhouette never grazes the frame edge. It must be
-- >= 1 -- a value below 1 moves the camera CLOSER and reintroduces the cropping.
local MARGIN = 1.10
function M.framing(model, fov)
	fov = fov or 30
	local cf, ext = model:GetBoundingBox()
	local radius = ext.Magnitude * 0.5
	local dist = radius / math.sin(math.rad(fov * 0.5)) * MARGIN
	return cf.Position, dist
end

-- Returns the ViewportFrame, or nil when there is no model for that name, so
-- the caller can fall back to a flat swatch.
function M.add(parent, name, opts)
	opts = opts or {}
	if opts.faceYaw == nil then opts.faceYaw = M.FACING[name] end
	return M.addMaster(parent, M.master(name), opts)
end

-- Same viewport for a pet: resolves PetModels first, then the brainrot fallback.
function M.addPet(parent, modelName, displayName, opts)
	return M.addMaster(parent, M.petMaster(modelName, displayName), opts)
end

-- The viewport builder itself, taking an already-resolved master so the brainrot and pet
-- lookups can share it rather than growing a second copy of the camera maths -- the exact
-- duplication this module was created to prevent.
function M.addMaster(parent, master, opts)
	if not master then return nil end
	opts = opts or {}

	local vp = Instance.new("ViewportFrame")
	vp.Size = opts.size or UDim2.fromScale(1, 1)
	vp.Position = opts.position or UDim2.fromScale(0, 0)
	vp.BackgroundTransparency = 1
	vp.ZIndex = opts.zIndex or 1
	vp.Parent = parent

	-- OPTIONAL RELIGHTING (2026-08-11). A ViewportFrame's stock lighting is a
	-- dim grey ambient with its key light pointing away from the default camera,
	-- so a model renders flat and muddy -- tolerable against the old dark slots,
	-- but the pets read as brown blobs (user: "make the pet card art look
	-- better"). Side-by-side captures with the pet values below are markedly
	-- cleaner, and lighting -- not layout -- was the bulk of that difference.
	--
	-- OPT-IN, nil by default: every existing caller keeps the exact render it
	-- was approved with, and only the sites that pass values are relit.
	if opts.ambient then vp.Ambient = opts.ambient end
	if opts.lightColor then vp.LightColor = opts.lightColor end
	if opts.lightDirection then vp.LightDirection = opts.lightDirection end

	local m = master:Clone()
	-- Same reason as PullCeremony's reveal: the pack ships every MeshPart on
	-- RenderFidelity.Automatic, which drops detail with camera distance, and a card
	-- frames the model from far enough out that the busier ones render mushy. A clone,
	-- so the source asset is untouched.
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("MeshPart") then
			forcePrecise(d)   -- guarded: see the capability note at the top
		end
	end
	if opts.silhouette then
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then p.Color = opts.silhouette end
		end
	end
	m.Parent = vp

	-- Frame from the REAL bounding box rather than a constant distance: these
	-- models range from under 5 studs to over 30, so one fixed distance would
	-- crop the big ones and shrink the small ones to a dot.
	local fov = opts.fov or 30
	local centre, dist = M.framing(m, fov)
	-- Aim RELATIVE TO THE MODEL'S PIVOT, not world axes. The pack models share one
	-- local convention (front = local -Z), but a chunk of them were imported with
	-- their pivot yawed 180 (Frigo Camelo, Gattatino Nyanino, ... all have a 180 spin
	-- in WorldPivot.Rotation), so a fixed world DEFAULT_DIR showed their BACKS on the
	-- card. Viewing from the pivot's own front-quarter faces every model the same way.
	-- Identity-pivot models -- the ones that already looked right -- transform to the
	-- exact same direction, so this cannot regress them.
	local dir = m:GetPivot():VectorToWorldSpace(opts.dir or DEFAULT_DIR)
	-- Per-model straggler flip (M.FACING): spin the view direction about world Y so
	-- an oddly-modelled face turns to the camera. Models stand upright, so a world-Y
	-- spin is the whole correction. No-op for the common (0/nil) case.
	if opts.faceYaw and opts.faceYaw ~= 0 then
		dir = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(opts.faceYaw)) * dir
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	cam.Parent = vp
	vp.CurrentCamera = cam

	return vp
end

return M
