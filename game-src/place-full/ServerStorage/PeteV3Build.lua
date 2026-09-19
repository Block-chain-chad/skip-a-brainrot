-- Secret Pete v3: turns PeteV3Pipeline's greedy-merged voxel boxes into a real
-- Roblox Model. BUILD-TIME ONLY -- nothing at runtime requires this.
--
-- WHY BOXES AND NOT A MESH. The v3 handoff's preferred route is "export GLB from
-- the viewer, run Studio's 3D Importer". That is a manual desktop step this
-- session cannot perform, and it would also make Pete the one brainrot whose
-- colours live in a mesh instead of on parts -- MutationFX recolours Parts, so a
-- MeshPart Pete would sit there un-mutated while everything else changed. The
-- pipeline's greedy merge collapses the 9,756 voxels to 195 axis-aligned boxes,
-- which is the SAME geometry (identical silhouette, identical baked face, every
-- voxel face in the same place) built out of the primitives the rest of the game
-- already understands. The README's "do not rebuild him as ~9,800 Parts" warning
-- is about the naive route; this is the merged one.
--
-- ORIENTATION. The spec authors Pete facing +z. Every model in this game faces
-- -z (checked against the v2 build: its apron sits at dz -1.965 from the skull
-- where the spec puts it at +0.68). Since every v3 box is axis-aligned, that 180
-- degree turn about Y is exactly "negate x and z" -- no CFrame rotation needed.
--
-- SCALE. 2.89x, which is not a guess: it is the exact authored scale of the v2
-- model this replaces (its skull was 5.6066 studs across a 1.94 spec skull), so
-- Pete's head, hands and sneakers stay the size the game was tuned around. Note
-- BrainrotSpawner re-fits every placed model to a box anyway, so this only sets
-- how he reads in ReplicatedStorage and in the Index viewport.
local Pipeline = require(script.Parent.PeteV3Pipeline)

local SCALE = 2.89

local PAL = {
	skin = "e6ab8c", skinShade = "d0977a", hair = "7a5a3a", glassFrame = "211f24",
	shirtBlack = "24222a", sneakerBlack = "1b1a20", sneakerSole = "e8e2d6",
	secretGold = "d9a838", rubberGloveYellow = "f2c33c", rubberGloveCuff = "d9a521",
	spongeYellow = "f6e07a", spongeGreen = "4f9e5c", sudsWhite = "f4f7f8",
	apronBlue = "3f6fa8", lensGlass = "f4f1ea", eyeWhite = "ffffff",
	pupilBlack = "171419", mouthLine = "8f5a49", foreheadCrease = "c48f74",
	nostril = "c9917a",
}

-- The handoff's Roblox mapping. Matches the v2 build's split exactly (42
-- SmoothPlastic / 2 Fabric / 4 Metal) so nothing about his surface read changes.
local MAT = {
	secretGold = Enum.Material.Metal,
	spongeYellow = Enum.Material.Fabric,
	spongeGreen = Enum.Material.Fabric,
}

local M = {}

-- Returns an unparented Model, feet on y = 0, centred on x/z, facing -z.
-- PrimaryPart is the box containing the spec's head centre, named "skull" so the
-- v2 name contract survives (the lineup models and the aura both hang off it).
function M.Build(scale)
	scale = scale or SCALE
	local P = Pipeline
	local VOX, OX, OY, OZ = P.VOX, P.OX, P.OY, P.OZ
	local mnx, mny, mnz, mxx, mxy, mxz = table.unpack(P.span)

	-- recentre exactly as the spec's viewer does: feet to y = 0, centred x/z
	local cx = (OX + mnx * VOX + OX + (mxx + 1) * VOX) / 2
	local cy = OY + mny * VOX
	local cz = (OZ + mnz * VOX + OZ + (mxz + 1) * VOX) / 2

	-- the voxel column holding the spec's head centre (0, HEAD_Y, 0)
	local hx = math.floor((0 - OX) / VOX)
	local hy = math.floor((P.HEAD_Y - OY) / VOX)
	local hz = math.floor((0 - OZ) / VOX)

	local model = Instance.new("Model")
	model.Name = "Secret Pete"
	local skull

	for i, b in ipairs(P.boxes) do
		local p = Instance.new("Part")
		p.Name = string.format("vox_%s_%d", b.mat, i)
		p.Size = Vector3.new(b.w * VOX * scale, b.h * VOX * scale, b.d * VOX * scale)
		local ax = OX + (b.x + b.w / 2) * VOX - cx
		local ay = OY + (b.y + b.h / 2) * VOX - cy
		local az = OZ + (b.z + b.d / 2) * VOX - cz
		-- 180 degrees about Y: negate x and z
		p.CFrame = CFrame.new(-ax * scale, ay * scale, -az * scale)
		p.Color = Color3.fromHex(PAL[b.mat] or "ff00ff")
		p.Material = MAT[b.mat] or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		if not skull
			and b.x <= hx and hx < b.x + b.w
			and b.y <= hy and hy < b.y + b.h
			and b.z <= hz and hz < b.z + b.d then
			skull = p
		end
	end

	skull = skull or model:FindFirstChildWhichIsA("BasePart")
	skull.Name = "skull"
	model.PrimaryPart = skull

	-- Spec: "set an explicit pivot at the head center, (0, 1.90, 0) pre-scale, so
	-- rotations swing the head rather than the feet." Written as PivotOffset, not
	-- Model.WorldPivot -- BrainrotSpawner's own note records that WorldPivot writes
	-- are a silent no-op on these models.
	local headWorld = Vector3.new(-(0 - cx) * scale, (P.HEAD_Y - cy) * scale, -(0 - cz) * scale)
	skull.PivotOffset = skull.CFrame:ToObjectSpace(CFrame.new(headWorld))

	model:SetAttribute("HeightScale", 1.5)
	return model
end

return M
