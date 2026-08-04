-- VoxelFace: bolts a blocky face onto an AI-generated voxel body.
--
-- WHY THIS EXISTS: Studio's mesh generator reliably produces good voxel BODIES
-- and reliably refuses to put faces on them (verified over ~8 generations, zero
-- faces). Faces are the one thing the hand-built path always did well, so the
-- pipeline splits the work: AI makes the body, this makes the face.
--
-- THREE RULES LEARNED THE HARD WAY, all visible at close range and invisible at
-- gameplay distance -- inspect zoomed before believing a face is done:
--   1. CUBE eyes, never spheres. A smooth ball on a voxel body is the single
--      biggest style mismatch; it reads as a toy, not a brick character.
--   2. RECESS them. Eyes pinned to the bounding-box front float ~half a voxel
--      proud and read as stickers stuck on. The reference pack bakes faces into
--      the mesh, so ours must sink in: raycast the REAL surface (a round voxel
--      body curves away from its box) and let only the front third clear it.
--   3. Size off the HEAD, not the model. Scaling eyes off total width made them
--      swallow a broccoli whose head is only its top third.
--
-- USAGE: VoxelFace.Apply(model, { up = 0.16, unit = 0.055 })
--   up   -- eye height as a fraction of model height, from the centre
--   unit -- one face "voxel" as a fraction of model width (~0.05-0.06)
-- Both default sensibly; tune per body when the head sits high or low.

local VoxelFace = {}

local WHITE = Color3.fromRGB(252, 252, 252)
local BLACK = Color3.fromRGB(16, 14, 20)
local RED = Color3.fromRGB(206, 42, 48)

local function cube(parent, name, size, cf, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- The model's own front surface at (x, y). Falls back to the bounding-box face
-- when the ray misses, which happens at the silhouette edges.
local function surfaceZ(model, x, y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	local cf, size = model:GetBoundingBox()
	local hit = workspace:Raycast(
		Vector3.new(x, y, cf.Position.Z - size.Z),
		Vector3.new(0, 0, size.Z * 1.5),
		params)
	return hit and hit.Position.Z or (cf.Position.Z - size.Z / 2)
end

-- Idempotent: re-applying replaces the previous face rather than stacking one.
function VoxelFace.Apply(model, opts)
	opts = opts or {}
	for _, d in ipairs(model:GetChildren()) do
		if d.Name == "Eye" or d.Name == "Pupil" or d.Name == "Mouth" then
			d:Destroy()
		end
	end

	local cf, size = model:GetBoundingBox()
	local c = cf.Position
	local u = size.X * (opts.unit or 0.055)
	local up = c.Y + size.Y * (opts.up or 0.16)

	for _, side in ipairs({ -1, 1 }) do
		local ex = c.X + side * u * 2.3
		local z = surfaceZ(model, ex, up)
		cube(model, "Eye", Vector3.new(u * 2.0, u * 2.3, u * 1.3),
			CFrame.new(ex, up, z + u * 0.4), WHITE)
		cube(model, "Pupil", Vector3.new(u * 1.1, u * 1.45, u * 1.3),
			CFrame.new(ex + side * u * 0.22, up - u * 0.12, z + u * 0.26), BLACK)
	end

	local my = up - u * 2.6
	cube(model, "Mouth", Vector3.new(u * 2.4, u * 0.7, u * 1.1),
		CFrame.new(c.X, my, surfaceZ(model, c.X, my) + u * 0.35), RED)
end

return VoxelFace
