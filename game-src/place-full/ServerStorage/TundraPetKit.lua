-- TundraPetKit -- build-time only. Mirrors the handoff's pets.js helper API 1:1 so the
-- fifteen builder functions port across as a straight transliteration rather than a
-- reinterpretation. Nothing here runs at game time; PetBuildTundra calls it once and
-- the resulting Models are what ship.
--
-- WHY A SCENE GRAPH: pets.js nests Groups (studs() makes one with its own position and
-- y-rotation), so a flat "make a Part now" port would silently drop those transforms.
-- Nodes accumulate a local CFrame and realise() composes down the tree, exactly as
-- three.js does.
--
-- UNITS: the handoff authors in METRES (1 unit = 3.571 studs). Everything below stays
-- in the handoff's numbers and realise() applies STUDS_PER_UNIT once at the end, so a
-- builder can be compared line-for-line against its JS source.
local K = {}

K.STUDS_PER_UNIT = 3.571

local function C(hex) return Color3.fromHex(hex) end
-- the sixteen materials, verbatim from the handoff's token table
K.M = {
	snow     = { c = C("F3F7FB"), mat = Enum.Material.SmoothPlastic },
	frost    = { c = C("CDE6F4"), mat = Enum.Material.SmoothPlastic },
	ice      = { c = C("8FCDEC"), mat = Enum.Material.Glass,        transparency = 0.15 },
	iceDeep  = { c = C("4A93CC"), mat = Enum.Material.Ice },
	ink      = { c = C("23272B"), mat = Enum.Material.SmoothPlastic },
	white    = { c = C("FFFFFF"), mat = Enum.Material.SmoothPlastic },
	amber    = { c = C("F2A03D"), mat = Enum.Material.Plastic },
	blush    = { c = C("EDA0AB"), mat = Enum.Material.Plastic },
	fur      = { c = C("8A6039"), mat = Enum.Material.Fabric },
	furDark  = { c = C("4B331F"), mat = Enum.Material.Fabric },
	slate    = { c = C("8D99A6"), mat = Enum.Material.SmoothPlastic },
	bone     = { c = C("EBE1C6"), mat = Enum.Material.SmoothPlastic },
	aurora   = { c = C("A46BEF"), mat = Enum.Material.Neon },
	gold     = { c = C("FFB200"), mat = Enum.Material.Metal },
	berry    = { c = C("E04B45"), mat = Enum.Material.Plastic },
	charcoal = { c = C("3D4650"), mat = Enum.Material.Fabric },
}

-- ---- scene graph -------------------------------------------------------
function K.group(name)
	return { kind = "group", name = name or "group", cf = CFrame.new(), children = {} }
end

local function node(kind, size, mat, name, extra)
	local n = { kind = kind, size = size, mat = mat, name = name or kind, cf = CFrame.new() }
	if extra then for k, v in pairs(extra) do n[k] = v end end
	return n
end

-- sphere: r = radius, s = {sx,sy,sz} non-uniform scale (three.js mesh.scale)
function K.sph(r, mat, name, s)
	s = s or { 1, 1, 1 }
	return node("ball", Vector3.new(2*r*s[1], 2*r*s[2], 2*r*s[3]), mat, name)
end

function K.box(w, h, d, mat, name)
	return node("block", Vector3.new(w, h, d), mat, name)
end

-- three.js cylinders run along +Y. A Roblox Cylinder part runs along X, so realise()
-- bakes the 90-degree turn; builders keep the handoff's axis convention.
-- rt ~= rb (a taper) has no Roblox primitive, so it becomes a short stack -- same path
-- the cone uses.
function K.cyl(rt, rb, h, mat, name, seg)
	if math.abs(rt - rb) < 1e-4 then
		return node("cyl", Vector3.new(h, 2*rt, 2*rt), mat, name)
	end
	return node("taper", Vector3.new(h, 2*math.max(rt,rb), 2*math.max(rt,rb)), mat, name,
		{ rt = rt, rb = rb, h = h, segs = 5 })
end

-- no cone primitive in Roblox: a five-step stack of shrinking cylinders, which also
-- happens to suit the chunky/blocky read the rest of the game uses.
function K.cone(r, h, mat, name)
	return node("taper", Vector3.new(h, 2*r, 2*r), mat, name, { rt = 0.02*r, rb = r, h = h, segs = 5 })
end

-- no torus either: a ring of small spheres on the XY plane (three.js torus orientation),
-- `arc` in radians (math.pi = the half ring the smile uses).
function K.tor(r, t, mat, name, arc, seg)
	return node("torus", Vector3.new(2*t, 2*t, 2*t), mat, name,
		{ major = r, tube = t, arc = arc or (2*math.pi), segs = seg or 14 })
end

function K.at(g, n, x, y, z, rx, ry, rz)
	n.cf = CFrame.new(x or 0, y or 0, z or 0) * CFrame.Angles(rx or 0, ry or 0, rz or 0)
	table.insert(g.children, n)
	return n
end

-- mirrored pair -- x, ry and rz all sign-flip, exactly as pets.js does
function K.pair(g, make, x, y, z, rx, ry, rz)
	for _, s in ipairs({ -1, 1 }) do
		K.at(g, make(s), s * (x or 0), y or 0, z or 0, rx or 0, s * (ry or 0), s * (rz or 0))
	end
end

-- classic stud caps on a flat top face
function K.studs(g, mat, o)
	local nx, nz = o.nx or 2, o.nz or 2
	local r, h = o.r or 0.058, o.h or 0.042
	local w, d = o.w or 0, o.d or 0
	local grp = K.group("studs")
	grp.cf = CFrame.new(o.x or 0, 0, o.z or 0) * CFrame.Angles(0, o.ry or 0, 0)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			K.at(grp, K.cyl(r, r, h, mat, "stud"),
				(nx == 1) and 0 or ((i/(nx-1)) - 0.5) * w,
				(o.y or 0) + h/2 - 0.004,
				(nz == 1) and 0 or ((j/(nz-1)) - 0.5) * d)
		end
	end
	table.insert(g.children, grp)
end

-- stud caps sunk into a curved top, y solved from the host ellipsoid so they sit flush
function K.studDome(g, mat, o)
	local nx, nz = o.nx or 2, o.nz or 1
	local sx, sz = o.sx or 0.4, o.sz or 0.4
	local ox, oz = o.ox or 0, o.oz or 0
	local size, h = o.size or 0.085, o.h or 0.056
	local c, r = o.c, o.r
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local dx = ((nx == 1) and 0 or (((i/(nx-1)) - 0.5) * 2)) * sx * r[1] + ox
			local dz = ((nz == 1) and 0 or (((j/(nz-1)) - 0.5) * 2)) * sz * r[3] + oz
			local k = 1 - (dx/r[1])^2 - (dz/r[3])^2
			if k > 0.05 then
				local y = c[2] + r[2] * math.sqrt(k)
				K.at(g, K.cyl(size, size, h, mat, "stud"), c[1] + dx, y + h/2 - 0.026, c[3] + dz)
			end
		end
	end
end

-- the shared face kit -- identical on all fifteen so the set reads as one family
function K.eyes(g, y, z, spread, r)
	r = r or 0.065
	K.pair(g, function() return K.sph(r, K.M.ink, "eye", {1, 1.2, 0.7}) end, spread, y, z)
	K.pair(g, function() return K.sph(r*0.36, K.M.white, "eyeGlint") end,
		spread + r*0.22, y + r*0.45, z + r*0.5)
end

function K.smile(g, y, z, r)
	r = r or 0.075
	K.at(g, K.tor(r, 0.016, K.M.ink, "mouth", math.pi), 0, y, z, 0, 0, math.pi)
end

-- ---- realise -----------------------------------------------------------
local function emit(model, n, world, scale)
	if n.kind == "group" then
		for _, c in ipairs(n.children) do emit(model, c, world * n.cf, scale) end
		return
	end
	local cf = world * n.cf
	local function part(size, pcf, shape)
		local p = Instance.new("Part")
		p.Name = n.name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Massless = true
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Material = n.mat.mat
		p.Color = n.mat.c
		if n.mat.transparency then p.Transparency = n.mat.transparency end
		p.Shape = shape
		p.Size = size * scale
		p.CFrame = CFrame.new(pcf.Position * scale) * (pcf - pcf.Position)
		p.Parent = model
		return p
	end
	if n.kind == "ball" then
		part(n.size, cf, Enum.PartType.Ball)
	elseif n.kind == "block" then
		part(n.size, cf, Enum.PartType.Block)
	elseif n.kind == "cyl" then
		-- Roblox cylinders run along X; the handoff's run along Y
		part(n.size, cf * CFrame.Angles(0, 0, math.pi/2), Enum.PartType.Cylinder)
	elseif n.kind == "taper" then
		local segs = n.segs or 5
		for i = 0, segs - 1 do
			local t0, t1 = i/segs, (i+1)/segs
			local rr = n.rb + (n.rt - n.rb) * ((t0 + t1) / 2)
			local segH = n.h / segs * 1.06            -- slight overrun so joints never gap
			local yc = -n.h/2 + n.h * ((t0 + t1) / 2)
			part(Vector3.new(segH, 2*rr, 2*rr),
				cf * CFrame.new(0, yc, 0) * CFrame.Angles(0, 0, math.pi/2), Enum.PartType.Cylinder)
		end
	elseif n.kind == "torus" then
		local segs = n.segs
		for i = 0, segs - 1 do
			local a = (i / math.max(segs - 1, 1)) * n.arc
			part(Vector3.new(2*n.tube, 2*n.tube, 2*n.tube),
				cf * CFrame.new(math.cos(a) * n.major, math.sin(a) * n.major, 0), Enum.PartType.Ball)
		end
	end
end

-- Build a Model from a root group. Centres on x/z and rests the lowest point on y=0,
-- matching buildPet()'s final framing step in pets.js.
function K.realise(root, name)
	local model = Instance.new("Model")
	model.Name = name
	emit(model, root, CFrame.new(), K.STUDS_PER_UNIT)
	local parts = model:GetChildren()
	if #parts == 0 then return model end
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = -mn
	for _, p in ipairs(parts) do
		local c, s = p.CFrame, p.Size/2
		for i = -1, 1, 2 do for j = -1, 1, 2 do for k = -1, 1, 2 do
			local q = c * Vector3.new(s.X*i, s.Y*j, s.Z*k)
			mn = Vector3.new(math.min(mn.X,q.X), math.min(mn.Y,q.Y), math.min(mn.Z,q.Z))
			mx = Vector3.new(math.max(mx.X,q.X), math.max(mx.Y,q.Y), math.max(mx.Z,q.Z))
		end end end
	end
	local centre = (mn + mx) / 2
	local shift = Vector3.new(-centre.X, -mn.Y, -centre.Z)
	for _, p in ipairs(parts) do p.CFrame = p.CFrame + shift end
	model.PrimaryPart = parts[1]
	return model
end

return K
