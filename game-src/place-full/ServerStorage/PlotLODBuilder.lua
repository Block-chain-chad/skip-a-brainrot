-- Plot-LOD builder. Resamples a voxel-built brainrot onto a coarser lattice and
-- greedy-meshes it, for the PLOT COPY ONLY. The authored model is never touched:
-- BrainrotThumb, PullCeremony and the Index keep full fidelity.
local M = {}
M.FACTOR = 3          -- coarsen by this many voxels per axis
M.MIN_PARTS = 150     -- below this a model is already cheap; leave it alone
M.NEON_MAX_CELLS = 1  -- longest run a neon box may span (see the note in Build)
-- How hard a RARE colour is favoured when a coarse cell votes on its look.
-- 0 = plain majority. See the salience note in Build for why majority is wrong.
M.RARE_BIAS = 0.5
-- A rebuild has to EARN its place: it must come back at most this fraction of the
-- authored part count. Protecting neon can make a glow-heavy model BIGGER than the
-- original -- Aurora Serpentina is 679 neon parts of 693, and every coarse cell
-- touching neon is force-filled, so it rebuilt at 940 parts. That is not a LOD, it
-- is a regression wearing one, and without this gate it would have shipped.
M.MAX_SHARE = 0.60
-- Largest allowed shift in the model's volume-weighted MEAN COLOUR, in 0-255 RGB.
-- Resampling can keep every colour in the palette and still change which ones the
-- eye SEES, by moving how much surface each one covers: Pinguinotto Frappuccino
-- kept its whites and still came back navy instead of pale blue. Nothing else in
-- this file could catch that -- IoU sees shape, the palette audit sees presence,
-- and both were happy. Set at 30: the two obvious offenders sat at 57-60, Regina
-- Brinata's 2x fallback lands right on 35 (and does visibly lighten), and the next
-- worst genuine pass is 24 -- so 30 refuses the two that look wrong and keeps the
-- rest untouched.
M.TONE_SHIFT = 30

local function partsOf(model)
	local t = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then t[#t+1] = d end
	end
	return t
end

-- eligible = axis-aligned blocks only, sitting on a clean lattice whose unit is
-- the smallest part dimension. Anything else (rotated, spheres, meshes, a posed
-- fish) is refused rather than approximated.
function M.Inspect(model)
	local parts = partsOf(model)
	if #parts < M.MIN_PARTS then return nil, "small" end
	local u = math.huge
	for _, p in ipairs(parts) do u = math.min(u, p.Size.X, p.Size.Y, p.Size.Z) end
	if u < 1e-4 then return nil, "degenerate" end
	for _, p in ipairs(parts) do
		if not (p:IsA("Part") and p.Shape == Enum.PartType.Block) then return nil, "shape" end
		local rx, ry, rz = (p.CFrame - p.CFrame.Position):ToOrientation()
		if math.abs(rx) + math.abs(ry) + math.abs(rz) > 1e-3 then return nil, "rotated" end
	end
	local mnx, mny, mnz = math.huge, math.huge, math.huge
	for _, p in ipairs(parts) do
		local s = p.Size/2
		mnx = math.min(mnx, p.Position.X-s.X); mny = math.min(mny, p.Position.Y-s.Y); mnz = math.min(mnz, p.Position.Z-s.Z)
	end
	local worst = 0
	for _, p in ipairs(parts) do
		local s = p.Size/2
		for _, v in ipairs({(p.Position.X-s.X-mnx)/u,(p.Position.Y-s.Y-mny)/u,(p.Position.Z-s.Z-mnz)/u,
		                    p.Size.X/u, p.Size.Y/u, p.Size.Z/u}) do
			worst = math.max(worst, math.abs(v - math.floor(v+0.5)))
		end
	end
	if worst > 0.02 then return nil, "lattice" end
	return { parts = parts, unit = u, origin = Vector3.new(mnx, mny, mnz), fit = worst }
end

function M.Build(model, factor)
	local info, why = M.Inspect(model)
	if not info then return nil, why end
	local u, o = info.unit, info.origin
	local F = factor or M.FACTOR
	-- voxelise at the authored unit
	-- === NEON IS NOT COARSENED AT ALL, it is carried over verbatim ==========
	-- Three attempts to fold neon into the voting all failed, each visibly:
	--   1. plain majority        -> Muschione Cornaluna's glowing face vanished
	--   2. neon force-fills cell -> Slittino Bombardino's glow inflated 1.2%->3.5%,
	--                               and Aurora Serpentina rebuilt BIGGER than source
	--   3. neon wins the vote    -> face vanished again: its voxels never reach the
	--                               fill threshold, so the cell is never made at all
	-- The honest answer is that a glowing accent is not body geometry and should not
	-- be resampled with it. Neon parts are copied across EXACTLY, so the glow keeps
	-- its authored size, colour and position. It is cheap: neon is 1,738 parts across
	-- all 215 models, and the one model that is mostly neon (Aurora, 679 of 693) is
	-- refused by MAX_SHARE for exactly the right reason.
	local neonParts = {}
	local vox, meta = {}, {}
	for _, p in ipairs(info.parts) do
		if p.Material == Enum.Material.Neon then
			neonParts[#neonParts + 1] = p
			continue
		end
		local s = p.Size/2
		local key = tostring(p.Color) .. "|" .. tostring(p.Material) .. "|" .. string.format("%.2f", p.Transparency)
		if not meta[key] then
			meta[key] = { color = p.Color, mat = p.Material, tr = p.Transparency,
			              neon = (p.Material == Enum.Material.Neon) }
		end
		local x0 = math.floor((p.Position.X-s.X-o.X)/u + 0.5)
		local y0 = math.floor((p.Position.Y-s.Y-o.Y)/u + 0.5)
		local z0 = math.floor((p.Position.Z-s.Z-o.Z)/u + 0.5)
		for x = x0, x0 + math.max(1, math.floor(p.Size.X/u + 0.5)) - 1 do
			for y = y0, y0 + math.max(1, math.floor(p.Size.Y/u + 0.5)) - 1 do
				for z = z0, z0 + math.max(1, math.floor(p.Size.Z/u + 0.5)) - 1 do
					vox[x .. "," .. y .. "," .. z] = key
				end end end
	end
	-- coarsen: a coarse cell survives if at least half its fine cells are solid,
	-- and takes the look most of them wore
	local cells = {}
	for k, look in pairs(vox) do
		local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
		local ck = math.floor(tonumber(x)/F) .. "," .. math.floor(tonumber(y)/F) .. "," .. math.floor(tonumber(z)/F)
		local c = cells[ck]
		if not c then c = { n = 0, looks = {} }; cells[ck] = c end
		c.n += 1
		c.looks[look] = (c.looks[look] or 0) + 1
	end
	-- === RARE COLOURS WIN THE VOTE (salience, not volume) ===================
	-- Every fault below was found by RENDERING a build and LOOKING at it. Plain
	-- majority voting quietly deleted:
	--   Muschione Cornaluna's glowing yellow face  (0.5% of the model's volume)
	--   Trono Ghiacciato's gold band
	--   Pinguino Trombettino's black body -- it came back cream
	--   Tricheco Sommozzatore's detail -- it came back a white block
	-- and it flipped Pinguinotto Frappuccino from light blue to dark navy by moving
	-- the light/dark balance a few percent.
	--
	-- ⚠️ SILHOUETTE IoU CANNOT SEE ANY OF THIS. Pinguino and Tricheco both scored a
	-- healthy 0.83-0.84 while looking plainly wrong, because IoU measures SHAPE and
	-- their shape WAS fine. Never let it be the only gate.
	--
	-- The fix: weight each candidate by how RARE it is in the model as a whole. A
	-- colour covering 1% of a creature is nearly always the accent the eye reads it
	-- by -- a face, a band, an eye -- while the 70% colour is just body. Dividing by
	-- share^RARE_BIAS lets an accent beat a body colour that outnumbers it, without
	-- letting a single stray voxel win outright.
	--
	-- This also subsumes the neon special-case that used to live here: neon accents
	-- are rare by construction, so they now win on their own merits. The old version
	-- force-FILLED any cell touching neon, which inflated Slittino Bombardino's glow
	-- from 1.2% to 3.5% of its volume and swallowed the black detail beside it.
	local share = {}
	do
		local tot = 0
		for _, look in pairs(vox) do
			share[look] = (share[look] or 0) + 1
			tot += 1
		end
		for l, v in pairs(share) do share[l] = v / math.max(tot, 1) end
	end
	-- NEON OUTRANKS THE VOTE ENTIRELY. Rare-weighting alone was still not enough for
	-- Muschione Cornaluna: its glowing face is 0.54% of the model, so even at
	-- RARE_BIAS 0.5 a couple of face voxels lose to twenty body voxels and the face
	-- vanished a second time. A neon part is the single highest-salience thing on a
	-- creature -- it emits light -- so where any neon lands in a solid cell it simply
	-- takes the cell.
	-- It does NOT make the cell solid, and that distinction is the whole reason this
	-- is safe: force-filling was what inflated Slittino Bombardino's glow to 3x its
	-- authored share and made Aurora Serpentina rebuild BIGGER than its original.
	local set, cap = {}, F*F*F
	for ck, c in pairs(cells) do
		if c.n * 2 >= cap then
			local best, bs = nil, -1
			for l, n in pairs(c.looks) do
				if meta[l] and meta[l].neon then best = l break end
				local s = n / (math.max(share[l] or 1e-4, 1e-4) ^ M.RARE_BIAS)
				if s > bs then bs, best = s, l end
			end
			set[ck] = best
		end
	end
	-- greedy mesh the coarse set
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for k in pairs(set) do
		local x, y, z = k:match("(-?%d+),(-?%d+),(-?%d+)")
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		lo[1]=math.min(lo[1],x); hi[1]=math.max(hi[1],x)
		lo[2]=math.min(lo[2],y); hi[2]=math.max(hi[2],y)
		lo[3]=math.min(lo[3],z); hi[3]=math.max(hi[3],z)
	end
	local used = {}
	local function free(x,y,z,l) local k=x..","..y..","..z return set[k]==l and not used[k] end
	local out = Instance.new("Model")
	out.Name = model.Name
	local cell = u * F
	local n = 0
	for x = lo[1], hi[1] do for y = lo[2], hi[2] do for z = lo[3], hi[3] do
		local k = x..","..y..","..z
		local look = set[k]
		if look and not used[k] then
			-- NEON DOES NOT MERGE FAR. A neon part's glow scales with its FACE, so
			-- fusing a run of small glowing voxels into one long slab does not read as
			-- the same material -- it blooms much harder and washes out to white. That
			-- is what turned Aurora Serpentina from pink to white while its palette
			-- stayed identical (79% green / 20% purple before AND after), which is why
			-- no colour metric caught it either. Capping the run keeps each glowing bit
			-- the size the artist drew it.
			local lim = (meta[look] and meta[look].neon) and M.NEON_MAX_CELLS or math.huge
			local dz=1 while dz < lim and free(x,y,z+dz,look) do dz+=1 end
			local dy=1
			while dy < lim do local ok=true
				for q=z,z+dz-1 do if not free(x,y+dy,q,look) then ok=false break end end
				if not ok then break end dy+=1 end
			local dx=1
			while dx < lim do local ok=true
				for p2=y,y+dy-1 do for q=z,z+dz-1 do if not free(x+dx,p2,q,look) then ok=false break end end
					if not ok then break end end
				if not ok then break end dx+=1 end
			for a=x,x+dx-1 do for b=y,y+dy-1 do for c2=z,z+dz-1 do used[a..","..b..","..c2]=true end end end
			local mt = meta[look]
			local part = Instance.new("Part")
			part.Anchored = true; part.CanCollide = false; part.CanQuery = false
			part.CanTouch = false; part.CastShadow = false
			part.TopSurface = Enum.SurfaceType.Smooth; part.BottomSurface = Enum.SurfaceType.Smooth
			part.Size = Vector3.new(dx*cell, dy*cell, dz*cell)
			part.Position = Vector3.new(o.X + (x + dx/2)*cell, o.Y + (y + dy/2)*cell, o.Z + (z + dz/2)*cell)
			part.Color = mt.color; part.Material = mt.mat; part.Transparency = mt.tr
			part.Parent = out
			n += 1
		end
	end end end
	-- carry the glow over untouched
	for _, p in ipairs(neonParts) do
		local c = p:Clone()
		c.Anchored = true; c.CanCollide = false; c.CanQuery = false
		c.CanTouch = false; c.CastShadow = false
		for _, ch in ipairs(c:GetChildren()) do ch:Destroy() end
		c.Parent = out
		n += 1
	end
	if n == 0 then out:Destroy() return nil, "empty" end
	out.PrimaryPart = out:FindFirstChildWhichIsA("BasePart")
	-- ATTRIBUTES ARE LOAD-BEARING: BrainrotSpawner reads HeightScale / WidthScale
	-- off the template to fit it to a pad. Losing them silently resizes the roster.
	for k, v in pairs(model:GetAttributes()) do out:SetAttribute(k, v) end
	return out, nil, n
end

-- === QUALITY GATE ==========================================================
-- A part count is not a result. Coarsening uses majority-fill, so a spindly
-- model (a thin limb, a trombone, an antler) can lose more than half its solid
-- and still report a lovely reduction -- Alcione Trombettone came back at 350
-- -> 9 parts having kept 22% of its volume and lost a fifth of its DEPTH. That
-- is not a cheaper model, it is a broken one.
--
-- So every candidate is measured against the authored original and refused if
-- it did not survive: VOL_KEEP guards the mass, BBOX_KEEP guards the
-- silhouette (checked on the WORST axis, because collapse shows up in one).
M.VOL_KEEP = 0.70
M.BBOX_KEEP = 0.88
-- SILHOUETTE IoU is the gate that actually corresponds to "does it still read as
-- the creature". Calibrated against the one model the owner approved by eye:
-- Valanga Ruggente at 3x scores 0.91 on its worst axis, so anything appreciably
-- below that is a bigger visual change than was signed off. 0.75 is the floor.
M.IOU_KEEP = 0.75
M.IOU_RES = 56

local function mask(model, refPos, refSize, axis)
	local m = {}
	local a1, a2 = axis % 3 + 1, (axis + 1) % 3 + 1
	local R = M.IOU_RES
	local function c(v, i) return (i == 1 and v.X) or (i == 2 and v.Y) or v.Z end
	local o = refPos - refSize/2
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local p, s = d.Position, d.Size/2
			local lo1 = (c(p,a1)-c(s,a1)-c(o,a1)) / c(refSize,a1) * R
			local hi1 = (c(p,a1)+c(s,a1)-c(o,a1)) / c(refSize,a1) * R
			local lo2 = (c(p,a2)-c(s,a2)-c(o,a2)) / c(refSize,a2) * R
			local hi2 = (c(p,a2)+c(s,a2)-c(o,a2)) / c(refSize,a2) * R
			for i = math.max(0, math.floor(lo1)), math.min(R-1, math.ceil(hi1)-1) do
				for j = math.max(0, math.floor(lo2)), math.min(R-1, math.ceil(hi2)-1) do
					m[i*R + j] = true
				end end
		end
	end
	return m
end

function M.SilhouetteIoU(orig, lod)
	local cf, ext = orig:GetBoundingBox()
	local worst = 1
	for ax = 1, 3 do
		local a, b = mask(orig, cf.Position, ext, ax), mask(lod, cf.Position, ext, ax)
		local seen, inter, uni = {}, 0, 0
		for k in pairs(a) do seen[k] = true end
		for k in pairs(b) do seen[k] = true end
		for k in pairs(seen) do
			uni += 1
			if a[k] and b[k] then inter += 1 end
		end
		local v = uni > 0 and inter/uni or 0
		if v < worst then worst = v end
	end
	return worst
end

local function meanColour(model)
	local r, g, b, t = 0, 0, 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			r += d.Color.R * 255 * v; g += d.Color.G * 255 * v; b += d.Color.B * 255 * v; t += v
		end
	end
	if t == 0 then return 0, 0, 0 end
	return r/t, g/t, b/t
end

function M.ToneShift(orig, lod)
	local r1, g1, b1 = meanColour(orig)
	local r2, g2, b2 = meanColour(lod)
	return math.sqrt((r1-r2)^2 + (g1-g2)^2 + (b1-b2)^2)
end

local function volumeOf(model)
	local v = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then v += d.Size.X * d.Size.Y * d.Size.Z end
	end
	return v
end

function M.Quality(orig, lod)
	local _, e1 = orig:GetBoundingBox()
	local _, e2 = lod:GetBoundingBox()
	local bbox = math.min(e2.X/math.max(e1.X,1e-6), e2.Y/math.max(e1.Y,1e-6), e2.Z/math.max(e1.Z,1e-6))
	local v1 = volumeOf(orig)
	local vol = v1 > 0 and volumeOf(lod)/v1 or 0
	local sil = M.SilhouetteIoU(orig, lod)
	local tone = M.ToneShift(orig, lod)
	return vol, bbox,
		(vol >= M.VOL_KEEP and bbox >= M.BBOX_KEEP and sil >= M.IOU_KEEP and tone <= M.TONE_SHIFT),
		sil, tone
end

-- Try the requested coarseness first and FALL BACK a step rather than giving up:
-- a model that cannot take 3x can usually take 2x, and a gentler reduction beats
-- no reduction. Anything that fails both keeps its authored model on the plot.
function M.BuildBest(model, factors)
	factors = factors or { M.FACTOR, 2 }
	local lastWhy
	for _, F in ipairs(factors) do
		local lod, why, n = M.Build(model, F)
		if lod then
			local before = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then before += 1 end
			end
			local vol, bbox, ok, sil, tone = M.Quality(model, lod)
			if n > before * M.MAX_SHARE then
				lod:Destroy()
				lastWhy = ("%dx came back %d parts of %d -- not a reduction"):format(F, n, before)
			elseif ok then
				return lod, F, n, vol, bbox, nil, sil
			else
				lod:Destroy()
				lastWhy = ("%dx vol %.0f%% bbox %.0f%% IoU %.2f tone %.0f")
					:format(F, vol*100, bbox*100, sil, tone)
			end
		else
			lastWhy = why
		end
	end
	return nil, nil, nil, nil, nil, lastWhy
end

return M
