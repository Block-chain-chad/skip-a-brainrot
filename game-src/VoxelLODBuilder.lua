--[[
	VoxelLODBuilder — coarsens an authored voxel brainrot without destroying its
	silhouette.

	WHY THIS EXISTS: the previous resampler (ServerStorage.PlotLODBuilder, since
	lost — it only ever existed as a one-off run inside Studio) used MAJORITY
	FILL: a coarse cell survives only if more than half its sub-voxels are solid.
	Fins, antlers, tails, ears and legs are always a minority inside their cell,
	so they erode first. Alcione Trombettone came back as 8-9 boxes — a floating
	slab. The owner's verdict on that whole direction, 2026-08-25, was
	"keep the authored, now I can't even tell what the hell it is."

	THE FIX: majority fill decides the interior, then a SILHOUETTE REPAIR pass
	decides the outline. Project the source and the coarse set from all three
	axes; wherever the source covers a pixel and the coarse set does not, the
	outline has a hole, so add back the densest candidate cell behind it. Repeat
	until the outline stops changing. Measured on Alcione at 3x:
	majority alone 18 cells -> repaired 133 cells -> 73 greedy-meshed boxes,
	and the antlers and all four legs survive.

	Colour uses a RARE-BIASED vote (see [[roblox-plot-lod-models]] fault 1): a
	colour covering 1% of a creature — a face, an eye, a gold band — must be able
	to beat the 70% body colour, or small accents silently vanish while every
	numeric gate still passes.

	STILL TO PORT from the old builder before this ships anywhere real:
	  - neon parts must be copied VERBATIM, never coarsened (fault 2)
	  - MAX_SHARE 0.60: refuse a rebuild that isn't meaningfully smaller (fault 3)
	  - TONE_SHIFT 30: volume-weighted mean-colour distance gate (fault 4)
	  - copy HeightScale / WidthScale attributes onto the rebuild
	  - eligibility: 150+ parts, axis-aligned Blocks only, clean lattice fit
	And per that same note: NO METRIC CAUGHT ANY OF THOSE FOUR. Render every
	rebuild and look at it.
]]

local VoxelLODBuilder = {}

local KEY_Y = 4096
local KEY_Z = 4096 * 4096

local function packCell(cx, cy, cz)
	return cx + cy * KEY_Y + cz * KEY_Z
end

local function unpackCell(ck)
	local cz = math.floor(ck / KEY_Z)
	local rem = ck - cz * KEY_Z
	local cy = math.floor(rem / KEY_Y)
	return rem - cy * KEY_Y, cy, cz
end

-- Authored bodies sit on a lattice whose unit is the smallest part dimension.
function VoxelLODBuilder.voxelise(model)
	local parts = {}
	local unit = math.huge
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			unit = math.min(unit, p.Size.X, p.Size.Y, p.Size.Z)
			lo = lo:Min(p.Position - p.Size / 2)
			hi = hi:Max(p.Position + p.Size / 2)
		end
	end
	local W = math.ceil((hi.X - lo.X) / unit + 0.5) + 2
	local H = math.ceil((hi.Y - lo.Y) / unit + 0.5) + 2
	local occ, col, n = {}, {}, 0
	for _, p in ipairs(parts) do
		local a = (p.Position - p.Size / 2 - lo) / unit
		local b = (p.Position + p.Size / 2 - lo) / unit
		-- the 0.25 nudge samples cell CENTRES, not edges: sampling edges flips
		-- boundary cells whenever part order changes (see the verifier bug in
		-- [[roblox-plot-lod-models]]).
		for x = math.floor(a.X + 0.25), math.ceil(b.X - 0.25) - 1 do
			for y = math.floor(a.Y + 0.25), math.ceil(b.Y - 0.25) - 1 do
				for z = math.floor(a.Z + 0.25), math.ceil(b.Z - 0.25) - 1 do
					local k = x + y * W + z * W * H
					if not occ[k] then n = n + 1 end
					occ[k] = true
					col[k] = p.Color
				end
			end
		end
	end
	return { occ = occ, col = col, n = n, unit = unit, lo = lo, W = W, H = H }
end

-- F is the coarsening factor: each coarse cell spans F x F x F source voxels.
function VoxelLODBuilder.decimate(model, F)
	local v = VoxelLODBuilder.voxelise(model)
	local W, H = v.W, v.H

	local bucket = {}
	for k in pairs(v.occ) do
		local z = math.floor(k / (W * H))
		local r = k - z * W * H
		local y = math.floor(r / W)
		local x = r - y * W
		local ck = packCell(math.floor(x / F), math.floor(y / F), math.floor(z / F))
		local b = bucket[ck]
		if not b then
			b = { cx = math.floor(x / F), cy = math.floor(y / F), cz = math.floor(z / F), n = 0, cols = {} }
			bucket[ck] = b
		end
		b.n = b.n + 1
		local c = v.col[k]
		local key = string.format("%d,%d,%d", c.R * 255, c.G * 255, c.B * 255)
		b.cols[key] = (b.cols[key] or 0) + 1
	end

	-- 1. INTERIOR: majority fill.
	local keep, majority = {}, 0
	local half = (F * F * F) / 2
	for ck, b in pairs(bucket) do
		if b.n > half then
			keep[ck] = true
			majority = majority + 1
		end
	end

	-- 2. OUTLINE: silhouette repair. This is the whole point of the module.
	local added = 0
	for _ = 1, 4 do
		local changed = 0
		for axis = 1, 3 do
			local srcPix, coarsePix, byPix = {}, {}, {}
			for ck, b in pairs(bucket) do
				local a, c
				if axis == 1 then a, c = b.cy, b.cz
				elseif axis == 2 then a, c = b.cx, b.cz
				else a, c = b.cx, b.cy end
				local pk = a + c * KEY_Y
				srcPix[pk] = true
				local cand = byPix[pk]
				if (not cand) or b.n > bucket[cand].n then byPix[pk] = ck end
				if keep[ck] then coarsePix[pk] = true end
			end
			for pk in pairs(srcPix) do
				if not coarsePix[pk] then
					local ck = byPix[pk]
					if ck and not keep[ck] then
						keep[ck] = true
						added = added + 1
						changed = changed + 1
					end
				end
			end
		end
		if changed == 0 then break end
	end

	-- 3. COLOUR: rare-biased vote so small accents can win their cell.
	local globalShare, total = {}, 0
	for _, b in pairs(bucket) do
		for c, n in pairs(b.cols) do
			globalShare[c] = (globalShare[c] or 0) + n
			total = total + n
		end
	end
	local cellColour = {}
	for ck in pairs(keep) do
		local best, bestScore = nil, -1
		for c, n in pairs(bucket[ck].cols) do
			local score = n / ((globalShare[c] / total) ^ 0.5)
			if score > bestScore then best, bestScore = c, score end
		end
		cellColour[ck] = best
	end

	return { v = v, bucket = bucket, keep = keep, cellColour = cellColour, F = F,
		majority = majority, repaired = added, final = majority + added }
end

-- Greedy-mesh the kept cells into as few boxes as possible.
function VoxelLODBuilder.build(res, keepSet, name)
	local F, v = res.F, res.v
	local size = F * v.unit
	local cells = {}
	for ck in pairs(keepSet) do
		local cx, cy, cz = unpackCell(ck)
		cells[ck] = { cx = cx, cy = cy, cz = cz, c = res.cellColour[ck] }
	end
	local used = {}
	local function free(x, y, z, colour)
		local n = cells[packCell(x, y, z)]
		return n and not used[packCell(x, y, z)] and n.c == colour
	end

	local model = Instance.new("Model")
	model.Name = name
	local keys = {}
	for ck in pairs(cells) do table.insert(keys, ck) end
	table.sort(keys)

	local boxes = 0
	for _, ck in ipairs(keys) do
		if not used[ck] then
			local c0 = cells[ck]
			local colour = c0.c
			local sx, sy, sz = 1, 1, 1
			while free(c0.cx + sx, c0.cy, c0.cz, colour) do sx = sx + 1 end
			local grow = true
			while grow do
				for i = 0, sx - 1 do
					if not free(c0.cx + i, c0.cy + sy, c0.cz, colour) then grow = false break end
				end
				if grow then sy = sy + 1 end
			end
			grow = true
			while grow do
				for i = 0, sx - 1 do
					for j = 0, sy - 1 do
						if not free(c0.cx + i, c0.cy + j, c0.cz + sz, colour) then grow = false break end
					end
					if not grow then break end
				end
				if grow then sz = sz + 1 end
			end
			for i = 0, sx - 1 do
				for j = 0, sy - 1 do
					for k = 0, sz - 1 do
						used[packCell(c0.cx + i, c0.cy + j, c0.cz + k)] = true
					end
				end
			end

			local r, g, b = string.match(colour, "(%d+),(%d+),(%d+)")
			local p = Instance.new("Part")
			p.Name = "V"
			p.Anchored = true
			p.CanCollide = false
			p.CastShadow = false
			p.CanQuery = false
			p.CanTouch = false
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Size = Vector3.new(sx * size, sy * size, sz * size)
			p.Position = v.lo + Vector3.new(
				(c0.cx * F + sx * F / 2) * v.unit,
				(c0.cy * F + sy * F / 2) * v.unit,
				(c0.cz * F + sz * F / 2) * v.unit)
			p.Color = Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))
			p.Material = Enum.Material.SmoothPlastic
			p.Parent = model
			boxes = boxes + 1
		end
	end
	return model, boxes
end

return VoxelLODBuilder
