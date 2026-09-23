--!nocheck
--[[
TradingWorldBuild.SettlementGenerator -- BUILD-TIME ONLY generator for the Riverside Trading Settlement
(TW-02). Installed at ServerStorage.TradingWorldBuild.SettlementGenerator. Nothing in the game requires it.
Run from the command bar or the Studio MCP, in Edit mode:

    local G = loadstring(game:GetService("ServerStorage").TradingWorldBuild.SettlementGenerator.Source)()
    G.RetireLegacy()     -- ONCE: moves the old cove island out of GameWorld.TradingWorld / TradingCenter
                         --       into ServerStorage.TradingWorldBackups_2026_09_20.Legacy_* (a move, not a delete)
    G.ClearAll()         -- removes only the sections this generator built (attribute TW2 = true)
    G.DETAIL = true      -- true = Phase 5 architecture renderer; false = the approved Phase 2 greybox (same numbers)
    G.BuildAll()         -- every section, each pcall-guarded, in place around TRADE_POS
    print(G.Contracts()) -- booth / zone / index / ground / portal self-check -> "OK 18/18 stalls ..."
    print(G.Stats())     -- part / light / script counts + bounding box vs the BoundsGuard box
    G.CounterGuards()    -- (v15) only the invisible counter guards; safe to re-run on its own

IN PLACE. The settlement is generated around the existing arrival point: design origin O = the ground
under TeleportService.TRADE_POS = (8000, 2002.4, 7818). Design axes: x = WEST (world +X, the player LEFT
on arrival), z = NORTH (world +Z, ahead on arrival), y = height above the Lower Market datum P = 2002.4.
Terrain water surface is y 2000 (design -2.4) everywhere in the BoundsGuard "Trading" box; land is parts.

Levels (walkable tops, design y): DOCK +0.4 . L0 0 (Lower Market) . QUAY -0.8 (Waterfront) .
UP +12 (Upper Market; back terrace +14) . CWY +8 (causeway, bridge deck, abutment square) . ROW -1.4.

Contracts kept exactly (BoothHandler / TradeHandler / TradeClient / TeleportService read these):
GameWorld.TradingCenter (Folder) > Booths (Folder) > Booth<N> (Model, attr BoothIndex 1..N CONTIGUOUS)
> Counter (+ Counter.StandPrompt), Display1/2/3 (level), SignBoard > SurfaceGui > TextLabel;
GameWorld.TradingCenter.TradeZone (ONE BasePart, direct child); GameWorld.TradingWorld (Folder);
walkable ground under TRADE_POS; GameWorld.Portals.HubPortal re-pivoted only (attributes untouched).

TWO RENDERERS, ONE SET OF NUMBERS. G.BUILDINGS / G.STALLS / G.NPC_SPOTS and the section functions hold
the approved layout (Phase 2, greybox v3). With G.DETAIL = false every building is a box + roof mass and
every stall a niche; with G.DETAIL = true the same footprints get the architecture pass: plinths, timber
frames, windows, doors, shutters, eaves, chimneys, dormers, balconies, the stone bridge and tower, quay
walls, real stair treads, and the six stall-shell families. The currency never appears anywhere here.
]]

local G = {}
G.VERSION = 15
G.DETAIL = true
G.O = Vector3.new(8000, 2002.4, 7818)          -- design origin (ground under TRADE_POS)
G.ROOT_WORLD = "TradingWorld"
G.ROOT_CENTER = "TradingCenter"
G.BACKUP = "TradingWorldBackups_2026_09_20"
G.STALL_COUNT = 18
local UP = 12                                   -- Upper Market terrace level

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local CHS = game:GetService("ChangeHistoryService")

-- ============================================================ palettes
local C3 = Color3.fromRGB
-- greybox
local PAL = {
	ground = C3(170, 162, 148), road = C3(112, 108, 102), quay = C3(142, 138, 130), square = C3(126, 122, 116),
	wood = C3(124, 90, 58), woodDark = C3(94, 68, 42), plank = C3(140, 104, 66),
	wall = C3(198, 190, 174), wall2 = C3(184, 172, 152), wall3 = C3(208, 202, 188), wall4 = C3(176, 168, 158),
	roof = C3(98, 88, 82), roof2 = C3(114, 98, 86), roof3 = C3(86, 82, 84),
	stone = C3(152, 148, 142), stoneDark = C3(120, 116, 110), bridge = C3(134, 128, 120),
	cliff = C3(86, 82, 80), cliff2 = C3(98, 92, 88), niche = C3(58, 52, 46), sign = C3(238, 228, 200),
	green = C3(96, 132, 72), npc = C3(64, 200, 190), relic = C3(120, 124, 112), water = C3(70, 140, 170),
}
-- architecture: natural materials only; colour comes from merchandise, gems and cloth accents later
local M = {
	plaster = Enum.Material.Concrete, stone = Enum.Material.Cobblestone, stone2 = Enum.Material.Limestone,
	slate = Enum.Material.Slate, wood = Enum.Material.Wood, plank = Enum.Material.WoodPlanks,
	cloth = Enum.Material.Fabric, metal = Enum.Material.Metal, glass = Enum.Material.SmoothPlastic,
	grass = Enum.Material.Grass, brick = Enum.Material.Brick, sp = Enum.Material.SmoothPlastic,
}
local PLASTER = { C3(202, 186, 158), C3(188, 160, 116), C3(172, 174, 150), C3(190, 166, 144), C3(206, 196, 176), C3(178, 150, 100), C3(194, 182, 154), C3(164, 156, 136) }
local ROOFS = { { C3(74, 70, 72), M.slate }, { C3(98, 74, 58), M.plank }, { C3(70, 78, 68), M.slate }, { C3(86, 80, 78), M.slate }, { C3(122, 80, 62), M.slate }, { C3(108, 88, 64), M.plank }, { C3(64, 62, 66), M.slate } }
local CLOTHS = { C3(146, 72, 62), C3(96, 118, 86), C3(78, 90, 116), C3(176, 138, 82), C3(206, 196, 176), C3(120, 84, 96) }
local TIMBER, TIMBER2, PLANK, PLANKDARK = C3(84, 60, 38), C3(108, 80, 50), C3(134, 100, 64), C3(104, 76, 48)
local STONE, STONE2, STONEDARK, COBBLE, LIME = C3(138, 128, 112), C3(156, 146, 128), C3(110, 100, 88), C3(124, 114, 100), C3(184, 172, 148)
local GLASS, IRON, CLIFF, CLIFF2 = C3(52, 64, 78), C3(58, 56, 56), C3(86, 82, 80), C3(100, 94, 88)
local SIGN, INK, ROPE = C3(226, 214, 184), C3(56, 46, 36), C3(178, 160, 122)

local SP = Enum.Material.SmoothPlastic
local CONCRETE = Enum.Material.Concrete
local WOODP = Enum.Material.WoodPlanks
local SLATE = Enum.Material.Slate

-- deterministic variation (never even spacing, never the same building twice)
local function hashName(s)
	local h = 5381
	for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
	return h
end
local function rng(seed)
	local st = (seed or 1) % 2147483647
	if st == 0 then st = 7 end
	return function()
		st = (st * 48271) % 2147483647
		return st / 2147483647
	end
end
local function pick(r, list) return list[1 + math.floor(r() * #list)] end

-- ============================================================ frame helpers (design -> world)
local function W(x, y, z) return G.O + Vector3.new(x, y, z) end
local function at(x, y, z) return CFrame.new(W(x, y, z)) end

local counts = { parts = 0 }
-- decoration nobody walks on or against: collision off (exact names; ground, steps, parapets and props stay solid)
local DECO = {}
for _, n in ipairs({ "WindowFrame", "WindowGlass", "Sill", "Shutter", "DoorFrame", "Door", "Lintel", "Post", "FloorBeam", "Stud", "Brace", "JettyBeam", "JettyBracket", "BeamEnd", "Ridge", "Eave", "Chimney", "ChimneyCap", "Dormer", "DormerGlass", "DormerFrame", "Coping", "Parapet", "RoofDeck", "Rail", "Baluster", "Awning", "AwningPost", "AwningBeam", "SideCloth", "BackBoard", "Shelf", "SignBoard", "SignBracket", "SignChain", "Niche", "Jamb", "Hood", "HoodStrut", "Canopy", "CanopyBeam", "Valance", "HoistBeam", "HoistStrut", "HoistRope", "DoorLeaf", "Strap", "Drape", "Hook", "Cage", "Rope", "Net", "Line", "HungCloth", "OpenBeam", "TowerBeam", "TowerStud", "TowerBrace", "TowerWindow", "TowerWindowFrame", "TowerRidge", "CupolaPost", "LanternCage", "OverlookBracket", "PlanterBush", "TreeCanopy", "Quoin", "BargeBoard", "GateSign", "GateSignArm", "RelicEye", "RelicMoss", "KneeBrace", "OuterBrace", "BraceStrap", "LanternArm", "LanternArmBrace", "TieBeam", "Bolt", "Keystone", "StringCourse", "TabletRim", "GateTablet", "GateRidge", "EaveBeam", "Patch", "ColumnCap", "WellBeam", "WellPost", "RowRope", "RackRail", "Tarp" }) do DECO[n] = true end
local function mk(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	if DECO[name] or name:find("Roof") then p.CanCollide = false end
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Color = color or PAL.wall
	p.Material = material or SP
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then for k, v in pairs(props) do p[k] = v end end
	p.Parent = parent
	counts.parts += 1
	return p
end
local function box(parent, name, x1, x2, z1, z2, y1, y2, color, material, props)
	local size = Vector3.new(x2 - x1, y2 - y1, z2 - z1)
	return mk(parent, name, size, at((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, material, props)
end
local function slab(parent, name, x1, x2, z1, z2, yTop, thick, color, material, props)
	return box(parent, name, x1, x2, z1, z2, yTop - thick, yTop, color, material, props)
end
-- tilted slab whose TOP runs from design point a to design point b, width w across
local function ramp(parent, name, a, b, w, thick, color, material, props)
	thick = thick or 1.0
	local mid = (a + b) / 2
	local len = (b - a).Magnitude + 0.3
	local cf = CFrame.lookAt(W(mid.X, mid.Y, mid.Z), W(b.X, b.Y, b.Z)) * CFrame.new(0, -thick / 2, 0)
	return mk(parent, name, Vector3.new(w, thick, len), cf, color or PAL.stone, material or SP, props)
end
local function cyl(parent, name, diameter, height, cf, color, material, props)
	local p = mk(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
-- horizontal cylinder from design point a to b (ropes, beams)
local function rod(parent, name, a, b, diameter, color, material)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(W(mid.X, mid.Y, mid.Z), W(b.X, b.Y, b.Z)) * CFrame.Angles(0, math.rad(90), 0)
	local p = mk(parent, name, Vector3.new(len, diameter, diameter), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end
local function ball(parent, name, diameter, cf, color, material)
	local p = mk(parent, name, Vector3.new(diameter, diameter, diameter), cf, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end
local function model(parent, name)
	local m = Instance.new("Model"); m.Name = name; m.Parent = parent; return m
end
local function folder(parent, name)
	local f = Instance.new("Folder"); f.Name = name; f.Parent = parent; return f
end
-- SurfaceGui text plate on a part face (the server rewrites the FIRST TextLabel of every SurfaceGui on SignBoard)
local function plate(part, text, face, textColor, bgColor, bgTransparency, font, pps)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps or 40
	gui.LightInfluence = 0.6
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = bgColor or SIGN
	label.BackgroundTransparency = bgTransparency == nil and 1 or bgTransparency
	label.BorderSizePixel = 0
	label.Font = font or Enum.Font.Antique
	label.Text = text
	label.TextColor3 = textColor or INK
	label.TextScaled = true
	label.TextStrokeTransparency = 1
	label.Parent = gui
	return gui, label
end
-- semicircular arch of n blocks; base = CFrame at the span centre at spring height; local X along the span
local function arch(parent, name, base, radius, n, thick, depth, color, material)
	local seglen = 2 * radius * math.sin(math.pi / (2 * n)) * 1.12
	for i = 0, n - 1 do
		local th = (i + 0.5) * math.pi / n
		local cf = base * CFrame.new(radius * math.cos(th), radius * math.sin(th), 0) * CFrame.Angles(0, 0, th + math.pi / 2)
		mk(parent, name, Vector3.new(seglen, thick, depth), cf, color, material or M.stone)
	end
end
-- real treads between two design points (walkable: rise per step <= 0.8)
local function steps(parent, name, a, b, w, color, material)
	local rise = math.abs(b.Y - a.Y)
	local n = math.max(2, math.ceil(rise / 0.75))
	local run = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = run.Magnitude
	local dir = run.Unit
	local tread = len / n
	local yaw = math.atan2(dir.X, dir.Z)
	for i = 0, n - 1 do
		local yTop = a.Y + (b.Y - a.Y) * (i + 1) / n
		local yLow = math.min(a.Y, b.Y) - 0.6
		local c = a + dir * (tread * (i + 0.5))
		local cf = CFrame.new(W(c.X, (yTop + yLow) / 2, c.Z)) * CFrame.Angles(0, yaw, 0)
		mk(parent, name, Vector3.new(w, yTop - yLow, tread + 0.05), cf, color or STONE, material or M.stone)
	end
end

-- ============================================================ roots / sections
local function gameWorld() return Workspace:WaitForChild("GameWorld") end
local function root(name, class)
	local gw = gameWorld()
	local r = gw:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "Folder"); r.Name = name; r.Parent = gw
	end
	return r
end
local function rootWorld() return root(G.ROOT_WORLD, "Folder") end
local function rootCenter() return root(G.ROOT_CENTER, "Folder") end
local function section(name, parent)
	parent = parent or rootWorld()
	local old = parent:FindFirstChild(name)
	if old and old:GetAttribute("TW2") then old:Destroy() end
	local m = model(parent, name)
	m:SetAttribute("TW2", true)
	m:SetAttribute("GeneratorVersion", G.VERSION)
	return m
end

-- ============================================================ greybox building kit (Phase 2, unchanged output)
local ROOF_TONES = { PAL.roof, PAL.roof2, PAL.roof3 }
local roofTone = 0
local function greyRoofColor() roofTone += 1; return ROOF_TONES[(roofTone - 1) % #ROOF_TONES + 1] end
-- gable: ridge parallel to Z (alongZ) or X; ov = overhang beyond the walls
local function gable(parent, name, x1, x2, z1, z2, top, rise, alongZ, color, material, ov)
	ov = ov or 0
	material = material or SP
	if alongZ then
		local span = (x2 - x1) + 2 * ov
		local half = span / 2
		local th = math.atan(rise, half)
		local len = math.sqrt(half * half + rise * rise) + 0.5
		local zc, depth = (z1 + z2) / 2, (z2 - z1) + 1.2 + 2 * ov
		local lo = x1 - ov
		mk(parent, name .. "RoofA", Vector3.new(len, 0.6, depth), at(lo + half / 2, top + rise / 2, zc) * CFrame.Angles(0, 0, th), color, material)
		mk(parent, name .. "RoofB", Vector3.new(len, 0.6, depth), at(lo + span - half / 2, top + rise / 2, zc) * CFrame.Angles(0, 0, -th), color, material)
	else
		local span = (z2 - z1) + 2 * ov
		local half = span / 2
		local th = math.atan(rise, half)
		local len = math.sqrt(half * half + rise * rise) + 0.5
		local xc, width = (x1 + x2) / 2, (x2 - x1) + 1.2 + 2 * ov
		local lo = z1 - ov
		mk(parent, name .. "RoofA", Vector3.new(width, 0.6, len), at(xc, top + rise / 2, lo + half / 2) * CFrame.Angles(-th, 0, 0), color, material)
		mk(parent, name .. "RoofB", Vector3.new(width, 0.6, len), at(xc, top + rise / 2, lo + span - half / 2) * CFrame.Angles(th, 0, 0), color, material)
	end
end
local function shedRoof(parent, name, x1, x2, z1, z2, top, r, hi, color, material, ov)
	ov = ov or 0
	material = material or SP
	if hi == "E" or hi == "W" then
		local span = (x2 - x1) + 2 * ov
		local th = math.atan(r, span)
		local len = math.sqrt(span * span + r * r) + 0.5
		local sgn = (hi == "W") and 1 or -1
		mk(parent, name .. "Roof", Vector3.new(len, 0.6, (z2 - z1) + 1.2 + 2 * ov), at((x1 + x2) / 2, top + r / 2, (z1 + z2) / 2) * CFrame.Angles(0, 0, sgn * th), color, material)
	else
		local span = (z2 - z1) + 2 * ov
		local th = math.atan(r, span)
		local len = math.sqrt(span * span + r * r) + 0.5
		local sgn = (hi == "N") and -1 or 1
		mk(parent, name .. "Roof", Vector3.new((x2 - x1) + 1.2 + 2 * ov, 0.6, len), at((x1 + x2) / 2, top + r / 2, (z1 + z2) / 2) * CFrame.Angles(sgn * th, 0, 0), color, material)
	end
end
local function greyBuilding(parent, s)
	local base = s.base or 0
	local bodyTop = base + s.h
	local top = bodyTop
	if s.upper then top = math.max(top, base + s.upper.y2) end
	local tone = s.tone or PAL.wall
	local m = model(parent, s.name)
	if s.open then
		local t = 0.8
		if s.open ~= "N" then box(m, "WallN", s.x1, s.x2, s.z2 - t, s.z2, base, bodyTop, tone, SP) end
		if s.open ~= "S" then box(m, "WallS", s.x1, s.x2, s.z1, s.z1 + t, base, bodyTop, tone, SP) end
		if s.open ~= "W" then box(m, "WallW", s.x2 - t, s.x2, s.z1, s.z2, base, bodyTop, tone, SP) end
		if s.open ~= "E" then box(m, "WallE", s.x1, s.x1 + t, s.z1, s.z2, base, bodyTop, tone, SP) end
		slab(m, "Floor", s.x1, s.x2, s.z1, s.z2, base + 0.2, 0.4, PAL.plank, WOODP)
	else
		box(m, "Body", s.x1, s.x2, s.z1, s.z2, base, bodyTop, tone, SP)
	end
	if s.upper then
		local u = s.upper
		box(m, "Upper", u.x1, u.x2, u.z1, u.z2, base + u.y1, base + u.y2, s.upperTone or tone, SP)
	end
	local rx1, rx2, rz1, rz2 = s.x1, s.x2, s.z1, s.z2
	if s.upper then rx1, rx2, rz1, rz2 = math.min(rx1, s.upper.x1), math.max(rx2, s.upper.x2), math.min(rz1, s.upper.z1), math.max(rz2, s.upper.z2) end
	local roof = s.roof or "gableZ"
	local rise = s.rise or math.min(8, math.max(3, (roof == "gableX" and (rz2 - rz1) or (rx2 - rx1)) * 0.3))
	if roof == "gableZ" then gable(m, s.name, rx1, rx2, rz1, rz2, top, rise, true, s.roofColor or greyRoofColor())
	elseif roof == "gableX" then gable(m, s.name, rx1, rx2, rz1, rz2, top, rise, false, s.roofColor or greyRoofColor())
	elseif roof == "hip" then
		local c = s.roofColor or greyRoofColor()
		box(m, s.name .. "Hip1", rx1 + 0.8, rx2 - 0.8, rz1 + 0.8, rz2 - 0.8, top, top + rise * 0.55, c, SP)
		box(m, s.name .. "Hip2", rx1 + 3.2, rx2 - 3.2, rz1 + 3.2, rz2 - 3.2, top + rise * 0.55, top + rise, c, SP)
	elseif roof == "flat" then box(m, s.name .. "Parapet", rx1 - 0.3, rx2 + 0.3, rz1 - 0.3, rz2 + 0.3, top, top + 1.2, s.roofColor or PAL.stoneDark, SP)
	elseif roof == "shed" then shedRoof(m, s.name, rx1, rx2, rz1, rz2, top, math.min(rise, 5), s.shedHigh or "E", s.roofColor or greyRoofColor())
	end
	if s.balcony then
		local b = s.balcony
		slab(m, "Balcony", b.x1, b.x2, b.z1, b.z2, base + b.y, 0.7, PAL.woodDark, WOODP)
		for _, corner in ipairs(b.posts or {}) do
			box(m, "Post", corner[1] - 0.35, corner[1] + 0.35, corner[2] - 0.35, corner[2] + 0.35, base, base + b.y - 0.7, PAL.woodDark, WOODP)
		end
	end
	return m
end

-- ============================================================ architecture building kit (Phase 5)
-- Facade frame. side: "E" = the face at x1 (outward -x) . "W" = x2 (+x) . "S" = z1 (-z) . "N" = z2 (+z).
-- u runs along the face from its low corner (z1 for E/W, x1 for N/S); v is height above the base; d is proud of the wall.
local function faceOf(s, side, ext)
	local x1, x2, z1, z2 = s.x1, s.x2, s.z1, s.z2
	if ext then x1, x2, z1, z2 = ext.x1, ext.x2, ext.z1, ext.z2 end
	local f = { side = side }
	if side == "E" then f.len = z2 - z1; f.pos = function(u, v, d) return x1 - d, v, z1 + u end; f.along = "z"
	elseif side == "W" then f.len = z2 - z1; f.pos = function(u, v, d) return x2 + d, v, z1 + u end; f.along = "z"
	elseif side == "S" then f.len = x2 - x1; f.pos = function(u, v, d) return x1 + u, v, z1 - d end; f.along = "x"
	else f.len = x2 - x1; f.pos = function(u, v, d) return x1 + u, v, z2 + d end; f.along = "x" end
	return f
end
-- a box on a face: w along the face, h up, t proud (centred at depth d); optional yaw (about Y) or roll (about the face normal)
local function faceBox(parent, name, f, base, u, v, d, w, h, t, color, material, yaw, roll, props, pitch)
	local x, y, z = f.pos(u, base + v, d)
	local cf = at(x, y, z)
	local size
	if f.along == "z" then
		size = Vector3.new(t, h, w)
		if roll then cf = cf * CFrame.Angles(roll, 0, 0) end
		if pitch then cf = cf * CFrame.Angles(0, 0, pitch) end
	else
		size = Vector3.new(w, h, t)
		if roll then cf = cf * CFrame.Angles(0, 0, roll) end
		if pitch then cf = cf * CFrame.Angles(pitch, 0, 0) end
	end
	if yaw then cf = cf * CFrame.Angles(0, yaw, 0) end
	return mk(parent, name, size, cf, color, material, props)
end

local function window(parent, f, base, u, v, w, h, r, opts)
	opts = opts or {}
	faceBox(parent, "WindowFrame", f, base, u, v, 0.12, w + 0.5, h + 0.5, 0.35, opts.frame or TIMBER, M.wood)
	if opts.lit then
		faceBox(parent, "WindowGlass", f, base, u, v, 0.02, w, h, 0.18, C3(255, 206, 146), M.glass, nil, nil, { Reflectance = 0.06, Transparency = 0.3 })
	else
		faceBox(parent, "WindowGlass", f, base, u, v, 0.02, w, h, 0.18, GLASS, M.glass, nil, nil, { Reflectance = 0.14 })
	end
	faceBox(parent, "Sill", f, base, u, v - h / 2 - 0.15, 0.35, w + 0.9, 0.35, 0.8, opts.sill or STONE2, M.stone2)
	if opts.shutters then
		local a = (r() < 0.7) and math.rad(22) or 0
		local sw = w / 2 + 0.2
		for _, sgn in ipairs({ -1, 1 }) do
			if r() < 0.85 then
				local hingeU = u + sgn * (w / 2 + 0.3)
				local cu = hingeU + sgn * (sw / 2) * math.cos(a)
				local cd = 0.25 + (sw / 2) * math.sin(a)
				-- open shutters swing out from the wall; the yaw sign depends on which way the face looks
				local yaw = sgn * a
				if f.side == "E" or f.side == "N" then yaw = -yaw end
				faceBox(parent, "Shutter", f, base, cu, v, cd, sw, h + 0.2, 0.2, opts.shutterColor or PLANKDARK, M.plank, yaw)
			end
		end
	end
end
local function door(parent, f, base, u, r, opts)
	opts = opts or {}
	local w, h = opts.w or 3.0, opts.h or 7.2
	faceBox(parent, "DoorFrame", f, base, u, h / 2, 0.15, w + 0.7, h + 0.4, 0.4, TIMBER, M.wood)
	faceBox(parent, "Door", f, base, u, h / 2, 0.05, w, h, 0.25, opts.color or PLANKDARK, M.plank)
	faceBox(parent, "DoorStep", f, base, u, -0.05, 0.7, w + 1.2, 0.5, 1.4, STONE2, M.stone2)
	if opts.lintel ~= false then faceBox(parent, "Lintel", f, base, u, h + 0.55, 0.35, w + 1.4, 0.55, 0.7, TIMBER2, M.wood) end
end

-- ============================================================ detail kit (Phase 5b) + lanterns (Phase 6)
-- barge boards along a gable end (the roof edge you see from the street)
local function bargeBoards(m, name, x1, x2, z1, z2, top, rise, alongZ, ov, atLow)
	local t = top - 0.25
	if alongZ then
		local zEnd = atLow and (z1 - ov - 0.15) or (z2 + ov + 0.15)
		local xc = (x1 + x2) / 2
		ramp(m, "BargeBoard", Vector3.new(x1 - ov - 0.3, t, zEnd), Vector3.new(xc, t + rise, zEnd), 0.45, 0.55, TIMBER, M.wood)
		ramp(m, "BargeBoard", Vector3.new(xc, t + rise, zEnd), Vector3.new(x2 + ov + 0.3, t, zEnd), 0.45, 0.55, TIMBER, M.wood)
	else
		local xEnd = atLow and (x1 - ov - 0.15) or (x2 + ov + 0.15)
		local zc = (z1 + z2) / 2
		ramp(m, "BargeBoard", Vector3.new(xEnd, t, z1 - ov - 0.3), Vector3.new(xEnd, t + rise, zc), 0.45, 0.55, TIMBER, M.wood)
		ramp(m, "BargeBoard", Vector3.new(xEnd, t + rise, zc), Vector3.new(xEnd, t, z2 + ov + 0.3), 0.45, 0.55, TIMBER, M.wood)
	end
end
-- limestone quoins up both corners of a face: alternating long and short blocks, never a straight column
local function quoins(m, f, base, h, r)
	local y = 0.9
	local i = 0
	while y < h - 1.0 do
		local long = (i % 2 == 0)
		for _, edge in ipairs({ 0, f.len }) do
			local w = long and 1.5 or 0.9
			local u = (edge == 0) and (w / 2 - 0.05) or (f.len - w / 2 + 0.05)
			faceBox(m, "Quoin", f, base, u, y, 0.08, w, 1.0 + (r() - 0.5) * 0.1, 0.5, LIME, M.stone2)
		end
		y += 2.4 + r() * 0.8
		i += 1
	end
end
-- joist ends showing through a jetty beam
local function beamEnds(m, f, base, y, o, r)
	local n = math.max(3, math.floor(f.len / 6))
	for i = 1, n do
		local u = f.len * (i - 0.5 + (r() - 0.5) * 0.25) / n
		faceBox(m, "BeamEnd", f, base, u, y, (-o + 0.6) / 2 - 0.1, 0.55, 0.55, o + 0.3, C3(70, 50, 32), M.wood)
	end
end
-- a hanging trade sign on an iron arm: board perpendicular to the wall, text on both faces
local function tradeSign(parent, name, text, f, base, u, v)
	local ax, ay, az = f.pos(u, base + v + 1.05, 2.2)
	local bx, by, bz = f.pos(u, base + v, 2.6)
	local arm, board
	if f.along == "z" then
		arm = mk(parent, name .. "Arm", Vector3.new(4.6, 0.26, 0.26), at(ax, ay, az), IRON, M.metal, { CanCollide = false })
		board = mk(parent, name, Vector3.new(4.0, 1.4, 0.26), at(bx, by, bz), SIGN, M.plank, { CanCollide = false })
		plate(board, text, Enum.NormalId.Front, INK, SIGN, 1, Enum.Font.Antique, 40)
		plate(board, text, Enum.NormalId.Back, INK, SIGN, 1, Enum.Font.Antique, 40)
	else
		arm = mk(parent, name .. "Arm", Vector3.new(0.26, 0.26, 4.6), at(ax, ay, az), IRON, M.metal, { CanCollide = false })
		board = mk(parent, name, Vector3.new(0.26, 1.4, 4.0), at(bx, by, bz), SIGN, M.plank, { CanCollide = false })
		plate(board, text, Enum.NormalId.Left, INK, SIGN, 1, Enum.Font.Antique, 40)
		plate(board, text, Enum.NormalId.Right, INK, SIGN, 1, Enum.Font.Antique, 40)
	end
	for _, d in ipairs({ 1.0, 4.2 }) do
		local cx, cy, cz = f.pos(u, base + v + 0.85, d)
		mk(parent, name .. "Chain", Vector3.new(0.1, 0.5, 0.1), at(cx, cy, cz), IRON, M.metal, { CanCollide = false })
	end
	return board
end
-- warm lantern: a lit core in an open iron cage (cap, base, two bars) with one PointLight. kind = "hang" | "post" | "bare"
local LAMP_WARM = C3(255, 198, 128)
local function lantern(parent, name, cf, kind, opts)
	opts = opts or {}
	local m = model(parent, name)
	m:SetAttribute("Lantern", true)
	local core = mk(m, "LanternGlass", Vector3.new(0.8, 1.1, 0.8), cf, opts.glass or C3(255, 196, 118), Enum.Material.Neon, { CanCollide = false })
	mk(m, "LanternCap", Vector3.new(1.15, 0.24, 1.15), cf * CFrame.new(0, 0.7, 0), IRON, M.metal, { CanCollide = false })
	mk(m, "LanternBase", Vector3.new(1.0, 0.18, 1.0), cf * CFrame.new(0, -0.65, 0), IRON, M.metal, { CanCollide = false })
	mk(m, "LanternBar", Vector3.new(0.12, 1.3, 0.12), cf * CFrame.new(0.46, 0, 0.46), IRON, M.metal, { CanCollide = false })
	mk(m, "LanternBar", Vector3.new(0.12, 1.3, 0.12), cf * CFrame.new(-0.46, 0, -0.46), IRON, M.metal, { CanCollide = false })
	if kind == "hang" then
		mk(m, "LanternArm", Vector3.new(0.26, 0.26, opts.arm or 1.6), cf * CFrame.new(0, 1.25, (opts.arm or 1.6) / 2 - 0.2), IRON, M.metal, { CanCollide = false })
		mk(m, "LanternHook", Vector3.new(0.14, 0.6, 0.14), cf * CFrame.new(0, 1.0, 0), IRON, M.metal, { CanCollide = false })
	elseif kind == "post" then
		local h = opts.post or 6.5
		mk(m, "LanternPost", Vector3.new(0.5, h, 0.5), cf * CFrame.new(0, -h / 2 - 0.7, 0), opts.postColor or TIMBER, opts.postMat or M.wood)
		mk(m, "LanternArm", Vector3.new(0.26, 0.26, 1.2), cf * CFrame.new(0, 1.15, -0.3), IRON, M.metal, { CanCollide = false })
	end
	local light = Instance.new("PointLight")
	light.Color = opts.color or LAMP_WARM
	light.Brightness = opts.brightness or 1.5
	light.Range = opts.range or 18
	light.Shadows = opts.shadows == true
	light.Parent = core
	return m
end

-- the detailed building
local function archBuilding(parent, s)
	local base = s.base or 0
	local bodyTop = base + s.h
	local top = bodyTop
	if s.upper then top = math.max(top, base + s.upper.y2) end
	local r = rng(hashName(s.name))
	local style = s.style or "mixed"
	local m = model(parent, s.name)
	m:SetAttribute("Style", style)
	local plaster = s.plaster or pick(r, PLASTER)
	local wallColor, wallMat
	if style == "stone" then wallColor, wallMat = pick(r, { STONE, STONE2, COBBLE }), M.stone
	elseif style == "timber" then wallColor, wallMat = pick(r, { PLANK, PLANKDARK, TIMBER2 }), M.plank
	elseif style == "stoneMixed" then wallColor, wallMat = pick(r, { STONE, COBBLE }), M.stone
	else wallColor, wallMat = plaster, M.plaster end
	local upperColor, upperMat = wallColor, wallMat
	if style == "mixed" or style == "stoneMixed" then upperColor, upperMat = plaster, M.plaster end

	-- body
	if s.open then
		local t = 0.8
		local c, mat = pick(r, { PLANK, PLANKDARK }), M.plank
		if s.open ~= "N" then box(m, "WallN", s.x1, s.x2, s.z2 - t, s.z2, base, bodyTop, c, mat) end
		if s.open ~= "S" then box(m, "WallS", s.x1, s.x2, s.z1, s.z1 + t, base, bodyTop, c, mat) end
		if s.open ~= "W" then box(m, "WallW", s.x2 - t, s.x2, s.z1, s.z2, base, bodyTop, c, mat) end
		if s.open ~= "E" then box(m, "WallE", s.x1, s.x1 + t, s.z1, s.z2, base, bodyTop, c, mat) end
		slab(m, "Floor", s.x1, s.x2, s.z1, s.z2, base + 0.2, 0.4, PLANK, M.plank)
		local f = faceOf(s, s.open)
		faceBox(m, "OpenBeam", f, base, f.len / 2, bodyTop - base - 0.5, 0.3, f.len, 0.8, 0.8, TIMBER, M.wood)
		faceBox(m, "OpenPost", f, base, 0.6, (bodyTop - base) / 2, 0.3, 0.8, bodyTop - base, 0.8, TIMBER, M.wood)
		faceBox(m, "OpenPost", f, base, f.len - 0.6, (bodyTop - base) / 2, 0.3, 0.8, bodyTop - base, 0.8, TIMBER, M.wood)
	else
		box(m, "Body", s.x1, s.x2, s.z1, s.z2, base, bodyTop, wallColor, wallMat)
	end
	if s.upper then
		local u = s.upper
		box(m, "Upper", u.x1, u.x2, u.z1, u.z2, base + u.y1, base + u.y2, upperColor, upperMat)
		-- jetty: a timber sill beam under every overhanging edge, plus brackets
		local ov = { E = s.x1 - u.x1, W = u.x2 - s.x2, S = s.z1 - u.z1, N = u.z2 - s.z2 }
		for side, o in pairs(ov) do
			if o > 0.5 then
				local f = faceOf(s, side, u)
				faceBox(m, "JettyBeam", f, base, f.len / 2, u.y1 - 0.35, 0.2, f.len, 0.7, 0.7, TIMBER, M.wood)
				local n = math.max(2, math.floor(f.len / 9))
				local drop = 3.25
				local reach = o - 0.5
				local blen = math.sqrt(reach * reach + drop * drop)
				local pitch = math.atan(reach, drop) * ((side == "E" or side == "N") and 1 or -1)
				for i = 1, n do
					local bu = f.len * (i - 0.5 + (r() - 0.5) * 0.3) / n
					faceBox(m, "JettyBracket", f, base, bu, u.y1 - 0.35 - drop / 2, (-o + 0.2 - 0.3) / 2, 0.6, blen, 0.6, TIMBER, M.wood, nil, nil, nil, pitch)
				end
				beamEnds(m, f, base, u.y1 + 0.35, o, r)
			end
		end
	end
	-- plinth: the stone course every plastered wall stands on
	if (style == "mixed" or style == "plaster") and not s.open and not s.noPlinth then
		box(m, "Plinth", s.x1 - 0.25, s.x2 + 0.25, s.z1 - 0.25, s.z2 + 0.25, base - 0.2, base + (s.plinth or 2.2), pick(r, { STONE, STONEDARK, COBBLE }), M.stone)
	end

	-- roof
	local rx1, rx2, rz1, rz2 = s.x1, s.x2, s.z1, s.z2
	if s.upper then rx1, rx2, rz1, rz2 = math.min(rx1, s.upper.x1), math.max(rx2, s.upper.x2), math.min(rz1, s.upper.z1), math.max(rz2, s.upper.z2) end
	local roof = s.roof or "gableZ"
	local rise = s.rise or math.min(8, math.max(3, (roof == "gableX" and (rz2 - rz1) or (rx2 - rx1)) * 0.3))
	local rc = s.roofSet or pick(r, ROOFS)
	local roofColor, roofMat = rc[1], rc[2]
	local ov = s.eave or 1.3
	if roof == "gableZ" or roof == "gableX" then
		gable(m, s.name, rx1, rx2, rz1, rz2, top, rise, roof == "gableZ", roofColor, roofMat, ov)
		if roof == "gableZ" then
			box(m, "Ridge", (rx1 + rx2) / 2 - 0.4, (rx1 + rx2) / 2 + 0.4, rz1 - ov - 0.2, rz2 + ov + 0.2, top + rise - 0.1, top + rise + 0.6, TIMBER, M.wood)
			box(m, "Eave", rx1 - ov - 0.3, rx1 - ov + 0.2, rz1 - ov, rz2 + ov, top - 0.9, top - 0.1, TIMBER2, M.wood)
			box(m, "Eave", rx2 + ov - 0.2, rx2 + ov + 0.3, rz1 - ov, rz2 + ov, top - 0.9, top - 0.1, TIMBER2, M.wood)
		else
			box(m, "Ridge", rx1 - ov - 0.2, rx2 + ov + 0.2, (rz1 + rz2) / 2 - 0.4, (rz1 + rz2) / 2 + 0.4, top + rise - 0.1, top + rise + 0.6, TIMBER, M.wood)
			box(m, "Eave", rx1 - ov, rx2 + ov, rz1 - ov - 0.3, rz1 - ov + 0.2, top - 0.9, top - 0.1, TIMBER2, M.wood)
			box(m, "Eave", rx1 - ov, rx2 + ov, rz2 + ov - 0.2, rz2 + ov + 0.3, top - 0.9, top - 0.1, TIMBER2, M.wood)
		end
	elseif roof == "hip" then
		local alongZ = (rx2 - rx1) <= (rz2 - rz1)
		if alongZ then
			gable(m, s.name, rx1, rx2, rz1 + rise, rz2 - rise, top, rise, true, roofColor, roofMat, ov)
			local half = (rx2 - rx1) / 2 + ov
			local xc = (rx1 + rx2) / 2
			for _, e in ipairs({ { rz1 - ov, rz1 + rise + 0.4, -1 }, { rz2 - rise - 0.4, rz2 + ov, 1 } }) do
				local span = math.abs(e[2] - e[1])
				local th = math.atan(rise, span)
				local len = math.sqrt(span * span + rise * rise) + 0.4
				mk(m, s.name .. "HipEnd", Vector3.new(half * 2 - rise * 0.4, 0.6, len), at(xc, top + rise / 2, (e[1] + e[2]) / 2) * CFrame.Angles(e[3] * th, 0, 0), roofColor, roofMat)
			end
		else
			gable(m, s.name, rx1 + rise, rx2 - rise, rz1, rz2, top, rise, false, roofColor, roofMat, ov)
			local half = (rz2 - rz1) / 2 + ov
			local zc = (rz1 + rz2) / 2
			for _, e in ipairs({ { rx1 - ov, rx1 + rise + 0.4, 1 }, { rx2 - rise - 0.4, rx2 + ov, -1 } }) do
				local span = math.abs(e[2] - e[1])
				local th = math.atan(rise, span)
				local len = math.sqrt(span * span + rise * rise) + 0.4
				mk(m, s.name .. "HipEnd", Vector3.new(len, 0.6, half * 2 - rise * 0.4), at((e[1] + e[2]) / 2, top + rise / 2, zc) * CFrame.Angles(0, 0, e[3] * th), roofColor, roofMat)
			end
		end
	elseif roof == "flat" then
		box(m, "Coping", rx1 - 0.35, rx2 + 0.35, rz1 - 0.35, rz2 + 0.35, top + 0.6, top + 1.3, LIME, M.stone2)
		box(m, "Parapet", rx1 - 0.15, rx2 + 0.15, rz1 - 0.15, rz2 + 0.15, top, top + 0.7, wallColor, wallMat)
		slab(m, "RoofDeck", rx1 + 0.3, rx2 - 0.3, rz1 + 0.3, rz2 - 0.3, top + 0.3, 0.4, STONEDARK, M.slate)
	elseif roof == "shed" then
		shedRoof(m, s.name, rx1, rx2, rz1, rz2, top, math.min(rise, 5), s.shedHigh or "E", roofColor, roofMat, ov)
	end
	if s.chimney then
		local cx = (s.chimney == "W") and (rx2 - 2.6) or (rx1 + 1.4)
		local cz = s.chimneyZ or (rz1 + 3 + r() * math.max(1, rz2 - rz1 - 6))
		local ctop = top + rise + 2.2 + r() * 1.5
		box(m, "Chimney", cx, cx + 1.8, cz, cz + 1.8, top - 2, ctop, pick(r, { STONEDARK, C3(120, 84, 70) }), pick(r, { M.stone, M.brick }))
		box(m, "ChimneyCap", cx - 0.2, cx + 2.0, cz - 0.2, cz + 2.0, ctop, ctop + 0.4, STONE2, M.stone2)
	end
	if s.dormer and (roof == "gableZ" or roof == "gableX") then
		local dsz = 3.2
		local dx, dz
		if roof == "gableZ" then
			dx = (s.dormer == "W") and (rx2 - (rx2 - rx1) * 0.28) or (rx1 + (rx2 - rx1) * 0.28)
			dz = rz1 + (rz2 - rz1) * (0.35 + r() * 0.3)
		else
			dx = rx1 + (rx2 - rx1) * (0.35 + r() * 0.3)
			dz = (s.dormer == "N") and (rz2 - (rz2 - rz1) * 0.28) or (rz1 + (rz2 - rz1) * 0.28)
		end
		local dy = top + rise * 0.5
		box(m, "Dormer", dx - dsz / 2, dx + dsz / 2, dz - dsz / 2, dz + dsz / 2, dy - 1.2, dy + 2.4, upperColor, upperMat)
		gable(m, s.name .. "Dormer", dx - dsz / 2, dx + dsz / 2, dz - dsz / 2, dz + dsz / 2, dy + 2.4, 1.6, roof ~= "gableZ", roofColor, roofMat, 0.4)
		local ds = (roof == "gableZ") and ((s.dormer == "W") and "W" or "E") or ((s.dormer == "N") and "N" or "S")
		local f = faceOf({ x1 = dx - dsz / 2, x2 = dx + dsz / 2, z1 = dz - dsz / 2, z2 = dz + dsz / 2 }, ds)
		faceBox(m, "DormerGlass", f, dy - 1.2, dsz / 2, 1.9, 0.05, 1.8, 2.0, 0.2, GLASS, M.glass, nil, nil, { Reflectance = 0.14 })
		faceBox(m, "DormerFrame", f, dy - 1.2, dsz / 2, 1.9, 0.12, 2.3, 2.5, 0.3, TIMBER, M.wood)
	end

	-- facades: the front and any other side the player can see
	local faces = {}
	if s.front then table.insert(faces, { side = s.front, front = true }) end
	for _, sd in ipairs(s.sides or {}) do table.insert(faces, { side = sd }) end
	local floors = s.floors or math.max(1, math.floor(s.h / 9 + 0.5))
	if s.upper then floors = math.max(floors, math.floor(s.upper.y2 / 9 + 0.5)) end
	local visible = {}
	for _, fc in ipairs(faces) do visible[fc.side] = true end
	if (roof == "gableZ" or roof == "gableX") and s.barge ~= false then
		local ends = (roof == "gableZ") and { { "S", true }, { "N", false } } or { { "E", true }, { "W", false } }
		for _, e in ipairs(ends) do
			if visible[e[1]] then bargeBoards(m, s.name, rx1, rx2, rz1, rz2, top, rise, roof == "gableZ", ov, e[2]) end
		end
	end
	for _, fc in ipairs(faces) do
		local f = faceOf(s, fc.side)
		local fU = s.upper and faceOf(s, fc.side, s.upper) or f
		if fc.front and (style == "stone" or style == "stoneMixed") and not s.open then quoins(m, f, base, (style == "stoneMixed") and 9 or s.h, r) end     -- the jetty plane, where the upper storey really is
		local jettyY = s.upper and s.upper.y1 or math.huge
		local groundOpen = s.groundOpen and fc.front
		local faceBase = s.faceBase or 0        -- e.g. 8 when the ground floor is buried behind a wall
		-- timber frame on mixed/timber styles: corner posts, floor beams, studs, one brace
		if style == "mixed" or style == "timber" or style == "stoneMixed" then
			local y0 = faceBase
			if style == "mixed" then y0 = math.max(faceBase, s.upper and s.upper.y1 or 2.2) end
			if style == "stoneMixed" then y0 = math.max(faceBase, s.upper and s.upper.y1 or 9) end
			local yTop = top - base
			local fh = yTop - y0
			local ff = (y0 >= jettyY - 0.01) and fU or f
			if fh > 2 then
				faceBox(m, "Post", ff, base, 0.45, y0 + fh / 2, 0.22, 0.7, fh, 0.55, TIMBER, M.wood)
				faceBox(m, "Post", ff, base, ff.len - 0.45, y0 + fh / 2, 0.22, 0.7, fh, 0.55, TIMBER, M.wood)
				for k = 1, floors - 1 do
					local by = 9 * k
					if by > y0 + 1 and by < yTop - 1 then
						faceBox(m, "FloorBeam", ff, base, ff.len / 2, by, 0.2, ff.len, 0.6, 0.5, TIMBER, M.wood)
					end
				end
				local nStud = math.max(1, math.floor(ff.len / 7))
				for i = 1, nStud do
					local su = ff.len * (i - 0.3 - r() * 0.4) / nStud
					if r() < 0.75 then
						local sh = (fh > 11) and (fh - 9) or (fh * 0.5)
						faceBox(m, "Stud", ff, base, su, yTop - sh / 2 - 0.3, 0.18, 0.5, sh, 0.42, TIMBER, M.wood)
					end
				end
				local bu = ff.len * (0.25 + r() * 0.5)
				local bh = math.min(fh - 0.5, 6.5)
				faceBox(m, "Brace", ff, base, bu, y0 + fh - bh / 2 - 0.4, 0.16, 0.45, bh, 0.4, TIMBER, M.wood, nil, (r() < 0.5 and 1 or -1) * math.rad(32))
			end
		end
		-- windows: a few per floor, never evenly spaced, some missing
		local nWin = fc.front and (s.winFront or math.max(1, math.min(4, math.floor(f.len / 8)))) or (s.winSide or math.max(1, math.min(3, math.floor(f.len / 11))))
		local avoid = fc.front and s.shopU or nil
		for k = 1, floors do
			local v = (k == 1) and 4.6 or math.min((k - 1) * 9 + 5.2, (top - base) - 2.8)
			if v > faceBase + 1 and v < (top - base) - 1.5 and (k == 1 or v > (k - 2) * 9 + 9.4) then
				local isGround = (k == 1)
				if not (isGround and (groundOpen or (fc.front and s.groundBlank))) then
					local count = nWin
					if isGround and fc.front then count = math.max(0, count - 1) end
					if isGround and fc.front and s.shopU then count = math.max(0, count - 1) end
					local slotW = f.len / math.max(1, count)
					for i = 1, count do
						local u = slotW * (i - 0.5) + (r() - 0.5) * slotW * 0.35
						u = math.max(2.2, math.min(f.len - 2.2, u))
						local clash = avoid and isGround and math.abs(u - avoid) < 7
						local doorClash = fc.front and isGround and s.doorU and math.abs(u - s.doorU) < 3.5
						if not clash and not doorClash and r() < 0.9 then
							local ww, wh = isGround and 3.2 or 2.6, isGround and 3.6 or 3.2
							window(m, (v >= jettyY) and fU or f, base, u, v, ww, wh, r, { shutters = (s.shutters ~= false) and (not isGround) and r() < 0.65, frame = (style == "stone") and STONE2 or TIMBER, lit = (not isGround) and r() < 0.3 })
						end
					end
				end
			end
		end
		-- the door on the front (unless a shop opening takes the whole ground floor)
		if fc.front and s.door ~= false and not groundOpen and faceBase < 1 then
			local du = s.doorU
			if not du then
				du = f.len * (0.2 + r() * 0.6)
				if s.shopU and math.abs(du - s.shopU) < 7.5 then du = (s.shopU > f.len / 2) and math.max(2.4, s.shopU - 8.5) or math.min(f.len - 2.4, s.shopU + 8.5) end
			end
			door(m, f, base, du, r, { color = pick(r, { PLANKDARK, TIMBER, C3(70, 52, 40) }) })
		end
	end
	-- balcony: plank deck on posts with a rail
	if s.balcony then
		local b = s.balcony
		slab(m, "Balcony", b.x1, b.x2, b.z1, b.z2, base + b.y, 0.5, PLANKDARK, M.plank)
		local alongZ = (b.x2 - b.x1) < (b.z2 - b.z1)
		if alongZ then
			local outerX = (b.x1 < s.x1) and b.x1 or b.x2
			box(m, "Rail", outerX - 0.15, outerX + 0.15, b.z1, b.z2, base + b.y + 2.6, base + b.y + 2.9, TIMBER, M.wood)
			for _, z in ipairs({ b.z1 + 0.3, (b.z1 + b.z2) / 2, b.z2 - 0.3 }) do
				box(m, "Baluster", outerX - 0.2, outerX + 0.2, z - 0.2, z + 0.2, base + b.y, base + b.y + 2.7, TIMBER, M.wood)
			end
		else
			local outerZ = (b.z1 < s.z1) and b.z1 or b.z2
			box(m, "Rail", b.x1, b.x2, outerZ - 0.15, outerZ + 0.15, base + b.y + 2.6, base + b.y + 2.9, TIMBER, M.wood)
		end
		for _, corner in ipairs(b.posts or {}) do
			box(m, "Post", corner[1] - 0.35, corner[1] + 0.35, corner[2] - 0.35, corner[2] + 0.35, base, base + b.y, TIMBER, M.wood)
		end
	end
	return m
end

local function renderBuilding(parent, s)
	if G.DETAIL then return archBuilding(parent, s) else return greyBuilding(parent, s) end
end

-- ============================================================ stall module + shell families
-- Contract parts are identical in every family; only the shell differs. Nothing here knows what a price is.
local function stallContract(b, L)
	local counter = mk(b, "Counter", Vector3.new(8, 3, 2.4), L(0, 1.5, 0), G.DETAIL and PLANKDARK or PAL.woodDark, M.plank)
	if G.DETAIL then mk(b, "CounterTop", Vector3.new(8.5, 0.28, 2.9), L(0, 3.12, 0), PLANK, M.plank) end
	for i, x in ipairs({ -2.6, 0, 2.6 }) do
		mk(b, "Display" .. i, Vector3.new(1.6, 0.4, 1.6), L(x, 3.45, -0.2), G.DETAIL and TIMBER2 or PAL.plank, M.plank)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StandPrompt"
	prompt.ActionText = "Claim Stand"        -- the server rewrites this ("Claim Stand" / "Manage Stand")
	prompt.ObjectText = "Market Stand"
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration = 0.3
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = counter
	b.PrimaryPart = counter
	return counter
end
-- the sign is the contract SignBoard: a BasePart with SurfaceGui > TextLabel the server rewrites
local function stallSign(b, L, kind, signY, roll)
	local sign
	if kind == "fascia" then
		sign = mk(b, "SignBoard", Vector3.new(6.2, 1.3, 0.3), L(0, signY, 0.9), SIGN, M.plank)
	elseif kind == "plaque" then
		sign = mk(b, "SignBoard", Vector3.new(3.6, 1.4, 0.25), L(0, signY, 1.2), LIME, M.stone2)
	else
		local cf = L(0, signY, -0.9)
		if roll then cf = cf * CFrame.Angles(0, 0, roll) end
		sign = mk(b, "SignBoard", Vector3.new(4.4, 1.5, 0.28), cf, SIGN, M.plank)
		mk(b, "SignBracket", Vector3.new(0.28, 0.28, 2.4), L(0, signY + 0.95, 0.3), IRON, M.metal)
		mk(b, "SignChain", Vector3.new(0.12, 0.6, 0.12), L(-1.6, signY + 0.95, -0.9), IRON, M.metal)
		mk(b, "SignChain", Vector3.new(0.12, 0.6, 0.12), L(1.6, signY + 0.95, -0.9), IRON, M.metal)
	end
	plate(sign, "CLAIM STALL", Enum.NormalId.Front, INK, SIGN, (kind == "plaque") and 1 or 0, Enum.Font.Antique, 40)
	return sign
end
local function dpos(cf) return cf.Position - G.O end   -- world CFrame -> design Vector3
local function stall(parent, s)
	local b = model(parent, "Booth" .. s.idx)
	b:SetAttribute("BoothIndex", s.idx)
	b:SetAttribute("District", s.district or "")
	b:SetAttribute("Shell", s.shell or "counter")
	b:SetAttribute("Family", s.family or "")
	local pos = W(s.x, s.y, s.z)
	local origin = CFrame.lookAt(pos, pos + s.dir)         -- local -Z = toward the customer / street
	local function L(x, y, z) return origin * CFrame.new(x, y, z) end
	local r = rng(hashName("stall" .. s.idx))
	if not G.DETAIL then
		mk(b, "Niche", Vector3.new(9.6, 8.2, 0.6), L(0, 4.1, 1.6), PAL.niche, SP)
		stallContract(b, L)
		local signY = s.signY or 7
		local sign = mk(b, "SignBoard", Vector3.new(4.6, 1.5, 0.3), L(0, signY, -0.9), PAL.sign, SP)
		plate(sign, "CLAIM STALL", Enum.NormalId.Front, PAL.niche, PAL.sign, 0, Enum.Font.GothamBold, 40)
		mk(b, "SignBracket", Vector3.new(0.3, 0.3, 2.2), L(0, signY + 0.9, 0.4), PAL.woodDark, WOODP)
		if s.shell == "awning" or s.shell == "dock" then
			mk(b, "Awning", Vector3.new(10, 0.4, 5), L(0, 7.6, -2.0), PAL.wood, WOODP)
			for _, x in ipairs({ -4.6, 4.6 }) do mk(b, "AwningPost", Vector3.new(0.5, 7.4, 0.5), L(x, 3.7, -4.2), PAL.woodDark, WOODP) end
		elseif s.shell == "window" then
			mk(b, "Lintel", Vector3.new(10.4, 1.4, 1.2), L(0, 8.9, 1.3), PAL.woodDark, WOODP)
			for _, x in ipairs({ -5.0, 5.0 }) do mk(b, "Jamb", Vector3.new(0.6, 8.2, 1.2), L(x, 4.1, 1.3), PAL.woodDark, WOODP) end
		end
		return b
	end
	local fam = s.family or "storefront"
	local cloth = pick(r, CLOTHS)
	if fam == "storefront" then
		-- a shop opening in the wall: dark interior, timber jambs + lintel, fascia sign, folding shutters, a stone step
		mk(b, "Niche", Vector3.new(9.6, 8.2, 0.8), L(0, 4.1, 1.7), C3(44, 38, 32), M.plank)
		mk(b, "Lintel", Vector3.new(10.8, 1.2, 1.0), L(0, 8.7, 1.25), TIMBER, M.wood)
		for _, x in ipairs({ -5.1, 5.1 }) do mk(b, "Jamb", Vector3.new(0.7, 8.2, 1.0), L(x, 4.1, 1.25), TIMBER, M.wood) end
		mk(b, "Step", Vector3.new(9.4, 0.4, 1.6), L(0, 0.2, -1.9), STONE2, M.stone2)
		for _, sgn in ipairs({ -1, 1 }) do
			local lock = L(sgn * 6.9, 4.4, 0.9) * CFrame.Angles(0, sgn * math.rad(14), 0)
			mk(b, "Shutter", Vector3.new(0.22, 7.6, 3.6), lock, PLANKDARK, M.plank)
			for _, dy in ipairs({ -2.4, 2.4 }) do mk(b, "Strap", Vector3.new(0.3, 0.5, 3.0), lock * CFrame.new(-0.05, dy, 0), IRON, M.metal) end
		end
		if r() < 0.6 then ramp(b, "Awning", dpos(L(0, 9.2, 0.6)), dpos(L(0, 8.1, -3.2)), 10.4, 0.22, cloth, M.cloth) end
		stallContract(b, L)
		stallSign(b, L, "fascia", 9.95)
	elseif fam == "covered" then
		-- a timber street stall built against the wall: posts, sloped cloth, shelf board, hanging sign
		stallContract(b, L)
		if s.roofed ~= false then
			for _, x in ipairs({ -4.7, 4.7 }) do mk(b, "AwningPost", Vector3.new(0.55, 7.8, 0.55), L(x, 3.9, -4.3), TIMBER, M.wood) end
			mk(b, "AwningBeam", Vector3.new(10.2, 0.5, 0.5), L(0, 7.6, -4.3), TIMBER, M.wood)
			ramp(b, "Awning", dpos(L(0, 8.6, 0.4)), dpos(L(0, 7.9, -4.6)), 10.6, 0.22, cloth, M.cloth)
			mk(b, "SideCloth", Vector3.new(0.18, 3.0, 4.6), L(4.9 * (r() < 0.5 and 1 or -1), 6.0, -2.2), cloth, M.cloth)
		end
		mk(b, "BackBoard", Vector3.new(8.6, 4.0, 0.3), L(0, 5.2, 1.3), PLANKDARK, M.plank)
		mk(b, "Shelf", Vector3.new(8.2, 0.3, 1.2), L(0, 5.4, 0.9), PLANK, M.plank)
		mk(b, "Crate", Vector3.new(2.0, 1.8, 2.0), L(5.4, 0.9, -0.6) * CFrame.Angles(0, math.rad(-9), 0), PLANK, M.plank)
		stallSign(b, L, "hanging", s.signY or 7.0)
	elseif fam == "dock" then
		-- waterside: plank counter, rope, a crate, a lean-to plank roof where nothing else covers it
		stallContract(b, L)
		if s.roofed ~= false then
			for _, x in ipairs({ -4.6, 4.6 }) do mk(b, "RoofPost", Vector3.new(0.6, 7.2, 0.6), L(x, 3.6, -4.0), TIMBER2, M.wood) end
			ramp(b, "LeanTo", dpos(L(0, 8.4, 0.4)), dpos(L(0, 7.0, -4.4)), 10.6, 0.3, PLANKDARK, M.plank)
			rod(b, "Rope", dpos(L(-4.6, 2.9, -4.0)), dpos(L(4.6, 2.9, -4.0)), 0.16, ROPE, M.cloth)
		end
		mk(b, "Crate", Vector3.new(2.2, 2.0, 2.2), L(-5.6, 1.0, -1.2) * CFrame.Angles(0, math.rad(12), 0), PLANK, M.plank)
		mk(b, "Basket", Vector3.new(1.6, 1.2, 1.6), L(5.4, 0.6, -0.8), C3(150, 122, 82), M.cloth)
		stallSign(b, L, "hanging", s.signY or 6.6)
	elseif fam == "terrace" then
		-- stone-surrounded opening: piers and an arch of blocks over the counter, a carved plaque
		mk(b, "Niche", Vector3.new(9.6, 8.6, 0.8), L(0, 4.3, 1.7), C3(48, 42, 38), M.stone)
		for _, x in ipairs({ -5.3, 5.3 }) do mk(b, "Pier", Vector3.new(1.1, 6.0, 1.2), L(x, 3.0, 1.2), STONE2, M.stone2) end
		arch(b, "Arch", L(0, 6.0, 1.2), 5.3, 7, 1.1, 1.2, STONE2, M.stone2)
		mk(b, "Step", Vector3.new(10.4, 0.4, 1.4), L(0, 0.2, -1.9), STONE, M.stone)
		stallContract(b, L)
		stallSign(b, L, "plaque", 10.2)
	elseif fam == "canopy" then
		-- arcade / open-terrace stand: four posts and a big cloth
		stallContract(b, L)
		for _, p in ipairs({ { -5.4, -4.4 }, { 5.4, -4.4 }, { -5.4, 1.6 }, { 5.4, 1.6 } }) do
			mk(b, "CanopyPost", Vector3.new(0.6, 8.2, 0.6), L(p[1], 4.1, p[2]), TIMBER, M.wood)
		end
		mk(b, "CanopyBeam", Vector3.new(11.6, 0.5, 0.5), L(0, 8.2, -4.4), TIMBER, M.wood)
		mk(b, "CanopyBeam", Vector3.new(11.6, 0.5, 0.5), L(0, 8.2, 1.6), TIMBER, M.wood)
		ramp(b, "Canopy", dpos(L(0, 8.9, 1.9)), dpos(L(0, 8.0, -4.9)), 12.2, 0.22, cloth, M.cloth)
		mk(b, "Valance", Vector3.new(12.2, 1.1, 0.16), L(0, 7.5, -4.9), cloth, M.cloth)
		stallSign(b, L, "hanging", 6.8)
	elseif fam == "loading" then
		-- an upper loading door with a hoist beam over the counter (the warehouse front on the causeway)
		mk(b, "Niche", Vector3.new(7.6, 8.4, 0.8), L(0, 4.2, 1.7), C3(44, 38, 32), M.plank)
		for _, x in ipairs({ -4.1, 4.1 }) do mk(b, "Jamb", Vector3.new(0.8, 8.4, 1.0), L(x, 4.2, 1.25), TIMBER, M.wood) end
		mk(b, "Lintel", Vector3.new(9.0, 1.0, 1.0), L(0, 8.9, 1.25), TIMBER, M.wood)
		mk(b, "HoistBeam", Vector3.new(0.6, 0.6, 6.0), L(0, 11.2, -1.6), TIMBER, M.wood)
		mk(b, "HoistStrut", Vector3.new(0.5, 4.2, 0.5), L(0, 9.6, -3.4) * CFrame.Angles(math.rad(-38), 0, 0), TIMBER, M.wood)
		rod(b, "HoistRope", dpos(L(0, 11.0, -4.3)), dpos(L(0, 5.5, -4.3)), 0.14, ROPE, M.cloth)
		mk(b, "DoorLeaf", Vector3.new(3.4, 7.6, 0.24), L(-5.6, 4.0, 0.7) * CFrame.Angles(0, math.rad(-30), 0), PLANKDARK, M.plank)
		stallContract(b, L)
		stallSign(b, L, "hanging", s.signY or 7.2)
	elseif fam == "bridge" then
		-- the cabin hatch on the deck side: a plank hood propped on struts, jambs, sign off the eave
		mk(b, "Niche", Vector3.new(8.6, 6.4, 0.8), L(0, 4.4, 1.7), C3(40, 34, 30), M.plank)
		for _, x in ipairs({ -4.6, 4.6 }) do mk(b, "Jamb", Vector3.new(0.6, 6.6, 0.9), L(x, 4.4, 1.3), TIMBER, M.wood) end
		mk(b, "Hood", Vector3.new(9.6, 0.24, 3.6), L(0, 8.3, -0.6) * CFrame.Angles(math.rad(-24), 0, 0), PLANKDARK, M.plank)
		mk(b, "HoodStrut", Vector3.new(0.3, 0.3, 2.8), L(-3.9, 7.1, -1.4) * CFrame.Angles(math.rad(35), 0, 0), TIMBER, M.wood)
		mk(b, "HoodStrut", Vector3.new(0.3, 0.3, 2.8), L(3.9, 7.1, -1.4) * CFrame.Angles(math.rad(35), 0, 0), TIMBER, M.wood)
		stallContract(b, L)
		stallSign(b, L, "hanging", s.signY or 6.4)
	elseif fam == "collector" then
		-- the strange one: heavy black timber, iron straps, a dark drape, a cage on a hook, a crooked sign
		mk(b, "Niche", Vector3.new(9.8, 8.6, 1.0), L(0, 4.3, 1.8), C3(28, 24, 22), M.wood)
		for _, x in ipairs({ -5.3, 5.3 }) do mk(b, "Jamb", Vector3.new(1.0, 8.6, 1.2), L(x, 4.3, 1.3), C3(48, 36, 28), M.wood) end
		mk(b, "Lintel", Vector3.new(11.6, 1.4, 1.2), L(0, 9.3, 1.3), C3(48, 36, 28), M.wood)
		for _, x in ipairs({ -3.6, 0.4, 4.2 }) do mk(b, "Strap", Vector3.new(0.7, 1.7, 0.1), L(x, 9.3, 0.66), IRON, M.metal) end
		mk(b, "Drape", Vector3.new(2.6, 7.4, 0.18), L(-3.4, 4.6, 0.9) * CFrame.Angles(0, math.rad(8), math.rad(3)), C3(52, 40, 56), M.cloth)
		mk(b, "Hook", Vector3.new(0.14, 1.6, 0.14), L(3.0, 7.6, -0.4), IRON, M.metal)
		mk(b, "Cage", Vector3.new(1.2, 1.5, 1.2), L(3.0, 6.3, -0.4), IRON, M.metal, { Transparency = 0.35 })
		stallContract(b, L)
		stallSign(b, L, "hanging", s.signY or 7.0, math.rad(7))
	else
		mk(b, "Niche", Vector3.new(9.6, 8.2, 0.6), L(0, 4.1, 1.6), C3(44, 38, 32), M.plank)
		stallContract(b, L)
		stallSign(b, L, "hanging", s.signY or 7)
	end
	return b
end

-- ============================================================ THE NUMBERS (design frame: x west+, z north+)
local E, Wd, N, S = Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)

G.STALLS = {
	-- Lower Market Street (7): 4 integrated storefronts + 3 covered street stalls
	{ idx = 1,  x = -8.6,  z = 40,  y = 0,    dir = Wd, shell = "awning",  family = "covered",    district = "LowerMarket", note = "covered stall against the Customs House by the gate" },
	{ idx = 2,  x = 6.6,   z = 81,  y = 0,    dir = E,  shell = "window",  family = "storefront", district = "LowerMarket", note = "B2 storefront" },
	{ idx = 3,  x = 10.6,  z = 172, y = 0,    dir = E,  shell = "balcony", family = "covered", roofed = false, district = "LowerMarket", note = "covered stall beneath B4 balcony" },
	{ idx = 4,  x = 4.0,   z = 215, y = 0,    dir = E,  shell = "understair", family = "covered", roofed = false, signY = 5, district = "LowerMarket", note = "covered stall under B5 external stair" },
	{ idx = 5,  x = -4.6,  z = 110, y = 0,    dir = Wd, shell = "window",  family = "storefront", district = "LowerMarket", note = "B8 storefront" },
	{ idx = 6,  x = -60,   z = 158.6, y = 0,  dir = S,  shell = "window",  family = "storefront", district = "LowerMarket", note = "CY_N storefront on the courtyard" },
	{ idx = 7,  x = -2.6,  z = 190, y = 0,    dir = Wd, shell = "opening", family = "storefront", district = "LowerMarket", note = "B10 storefront" },
	-- Upper Market (4): terrace shops
	{ idx = 8,  x = -68.6, z = 281, y = UP,   dir = Wd, shell = "opening", family = "terrace",    district = "UpperMarket", note = "U1: stone-arched opening on the edge street" },
	{ idx = 9,  x = -73.4, z = 346, y = UP,   dir = Wd, shell = "arcade",  family = "canopy",     district = "UpperMarket", note = "inside the Curio House arcade, under a cloth" },
	{ idx = 10, x = -118.6, z = 300, y = UP + 2, dir = Wd, shell = "awning", family = "canopy",   district = "UpperMarket", note = "back terrace, under a big cloth" },
	{ idx = 11, x = -45,   z = 371.4, y = 8,  dir = N,  shell = "window",  family = "loading",    district = "UpperMarket", note = "WH1 upper loading door on the causeway" },
	-- Waterfront (4): dock / waterside
	{ idx = 12, x = 50,    z = 42,  y = 0.2,  dir = Wd, shell = "dock",    family = "dock", roofed = false, district = "Waterfront", note = "bench inside the open boat shed" },
	{ idx = 13, x = 71.4,  z = 127, y = -0.8, dir = Wd, shell = "dock",    family = "dock",       district = "Waterfront", note = "lean-to against S3 on the quay" },
	{ idx = 14, x = 71.4,  z = 171, y = -0.8, dir = Wd, shell = "balcony", family = "dock", roofed = false, district = "Waterfront", note = "beneath S4 balcony over the quay" },
	{ idx = 15, x = 71.4,  z = 284, y = -0.8, dir = Wd, shell = "window",  family = "dock",       district = "Waterfront", note = "S6 water-side hatch" },
	-- Old Bridge (2): bridge-integrated
	{ idx = 16, x = 5.4,   z = 413, y = 8,    dir = Wd, shell = "bridge",  family = "bridge",     district = "OldBridge", note = "east cabin hatch, counter on the deck" },
	{ idx = 17, x = 16.6,  z = 429, y = 8,    dir = E,  shell = "bridge",  family = "bridge",     district = "OldBridge", note = "west cabin hatch" },
	-- Collector's Row (1): unique
	{ idx = 18, x = -14,   z = 471.6, y = -1.4, dir = S, shell = "opening", family = "collector", district = "CollectorsRow", note = "the collector opening onto the sunken lane" },
}

G.NPC_SPOTS = {
	{ role = "Harbourmaster", tier = 1, x = 8.5, z = 44, y = 0, dir = E, note = "porch of the Harbourmaster house by the gate; greets arrivals (ExchangeHost)" },
	{ role = "Ferryman", tier = 3, x = -18, z = 20, y = 0, dir = Wd, note = "the boathouse porch beside the way home" },
	{ role = "GemBroker", tier = 1, x = -20.5, z = 217, y = 0, dir = Wd, note = "stone kiosk on the Lower Market before the Fork" },
	{ role = "AttendantFork", tier = 2, x = -14, z = 246, y = 0, dir = S, note = "by the Fork Square well" },
	{ role = "TraderA", tier = 3, x = -30, z = 268, y = 0, dir = Wd, note = "Guild House arcade, haggling pair" },
	{ role = "TraderB", tier = 3, x = -22, z = 268, y = 0, dir = E, note = "Guild House arcade, haggling pair" },
	{ role = "Curator", tier = 2, x = -73, z = 364, y = UP, dir = Wd, note = "Curio House arcade, Upper Market (rare Brainrot curator)" },
	{ role = "AttendantBridge", tier = 2, x = 20, z = 380, y = 8, dir = N, note = "the Bridge Steps square" },
	{ role = "Angler", tier = 3, x = -62, z = 393, y = -0.8, dir = N, note = "fishing pocket under the causeway, end of the river quay" },
	{ role = "BridgeWarden", tier = 3, x = 17, z = 448, y = 8, dir = E, note = "doorway in the gate tower passage" },
	{ role = "Collector", tier = 3, x = -36, z = 472.5, y = -1.4, dir = S, note = "RN3 doorway on Collector's Row" },
}

-- Buildings by district. Footprints/heights/roofs are the approved greybox v3. Phase 5 fields: style, front, sides,
-- shopU (the stall position along the front face, studs from the face low corner), doorU, chimney, dormer, winFront/winSide.
G.BUILDINGS = {
	ArrivalDock = {
		{ name = "Boathouse", x1 = -44, x2 = -20, z1 = 4, z2 = 20, h = 12, roof = "shed", shedHigh = "E", open = "W", style = "timber", roofSet = ROOFS[2] },
	},
	MarketEntrance = {
		{ name = "Harbourmaster", x1 = 10, x2 = 42, z1 = 24, z2 = 62, h = 11, roof = "gableZ", rise = 7, style = "mixed", plaster = PLASTER[1],
			upper = { x1 = 7, x2 = 42, z1 = 21, z2 = 62, y1 = 11, y2 = 24 }, front = "E", sides = { "S" }, doorU = 28, chimney = "W", dormer = "E", winFront = 3, roofSet = ROOFS[1] },
		{ name = "CustomsHouse", x1 = -46, x2 = -10, z1 = 22, z2 = 56, h = 18, roof = "hip", rise = 6, style = "stone", front = "W", sides = { "S" }, shopU = 18, doorU = 30, chimney = "E", winFront = 2 },
	},
	LowerMarket = {
		{ name = "B2", x1 = 8, x2 = 40, z1 = 66, z2 = 96, h = 15, roof = "flat", style = "plaster", plaster = PLASTER[6], front = "E", shopU = 15, doorU = 26, winFront = 3 },
		{ name = "B3", x1 = 20, x2 = 54, z1 = 104, z2 = 146, h = 10, roof = "gableX", rise = 8, style = "mixed", plaster = PLASTER[3],
			upper = { x1 = 20, x2 = 54, z1 = 104, z2 = 153, y1 = 10, y2 = 28 }, front = "E", doorU = 14, chimney = "E", winFront = 3, dormer = "E", roofSet = ROOFS[7] },
		{ name = "B4", x1 = 12, x2 = 46, z1 = 153, z2 = 190, h = 20, roof = "hip", rise = 7, style = "plaster", plaster = PLASTER[4], front = "E", shopU = 19, doorU = 8, chimney = "W",
			balcony = { x1 = 9, x2 = 12.2, z1 = 160, z2 = 184, y = 9, posts = { { 9.5, 161 }, { 9.5, 183 } } } },
		{ name = "B5", x1 = 6, x2 = 40, z1 = 194, z2 = 248, h = 18, roof = "gableZ", rise = 6, style = "mixed", plaster = PLASTER[2], front = "E", shopU = 21, doorU = 44, chimney = "W", winFront = 4, roofSet = ROOFS[5] },
		{ name = "B12", x1 = 6, x2 = 48, z1 = 264, z2 = 300, h = 18, roof = "gableX", rise = 6, style = "stone", front = "S", sides = { "E" }, doorU = 24, winFront = 3, roofSet = ROOFS[4] },
		{ name = "B13", x1 = 4, x2 = 40, z1 = 336, z2 = 364, h = 14, roof = "gableZ", rise = 6, style = "mixed", plaster = PLASTER[7], front = "S", doorU = 10, chimney = "E", roofSet = ROOFS[2] },
		{ name = "WH2", x1 = -32, x2 = 0, z1 = 334, z2 = 370, h = 16, roof = "flat", style = "stone", front = "S", doorU = 12, winFront = 2 },
		{ name = "WH1", x1 = -54, x2 = -36, z1 = 336, z2 = 370, h = 18, roof = "gableX", rise = 6, style = "timber", front = "N", faceBase = 8, shopU = 9, door = false, winFront = 1, roofSet = ROOFS[6] },
		{ name = "B7", x1 = -44, x2 = -8, z1 = 60, z2 = 92, h = 26, roof = "gableZ", rise = 8, style = "mixed", plaster = PLASTER[5], front = "W", doorU = 10, chimney = "E", winFront = 3, dormer = "W", roofSet = ROOFS[1] },
		{ name = "B8", x1 = -40, x2 = -6, z1 = 96, z2 = 122, h = 14, roof = "shed", shedHigh = "E", style = "plaster", plaster = PLASTER[2], front = "W", shopU = 14, doorU = 5, winFront = 2, roofSet = ROOFS[6] },
		{ name = "B9", x1 = -40, x2 = -4, z1 = 130, z2 = 172, h = 22, roof = "gableX", rise = 7, style = "mixed", plaster = PLASTER[1], front = "W", doorU = 30, chimney = "E", winFront = 4, roofSet = ROOFS[3] },
		{ name = "B10", x1 = -38, x2 = -4, z1 = 176, z2 = 204, h = 18, roof = "hip", rise = 6, style = "plaster", plaster = PLASTER[8], front = "W", shopU = 14, doorU = 24, winFront = 3 },
		{ name = "B14", x1 = -70, x2 = -36, z1 = 208, z2 = 232, h = 16, roof = "flat", style = "stone", front = "N", sides = { "W" }, doorU = 10, winFront = 2 },
		{ name = "CY_S", x1 = -80, x2 = -46, z1 = 60, z2 = 116, h = 14, roof = "gableZ", rise = 6, style = "plaster", plaster = PLASTER[3], front = "N", doorU = 26, winFront = 2, roofSet = ROOFS[4] },
		{ name = "CY_E", x1 = -112, x2 = -80, z1 = 118, z2 = 160, h = 20, roof = "hip", rise = 6, style = "mixed", plaster = PLASTER[6], front = "W", doorU = 12, chimney = "E", winFront = 3 },
		{ name = "CY_N", x1 = -80, x2 = -42, z1 = 160, z2 = 204, h = 16, roof = "gableZ", rise = 6, style = "plaster", plaster = PLASTER[1], front = "S", shopU = 20, doorU = 8, winFront = 3, roofSet = ROOFS[2] },
		{ name = "CY_NN", x1 = -112, x2 = -72, z1 = 206, z2 = 228, h = 18, roof = "gableX", rise = 6, style = "mixed", plaster = PLASTER[4], front = "S", doorU = 30, chimney = "E", winFront = 3 },
		{ name = "BrokerKiosk", x1 = -30, x2 = -22, z1 = 212, z2 = 222, h = 8, roof = "hip", rise = 3, style = "stone", front = "W", door = false, winFront = 1, floors = 1 },
		{ name = "GuildHouse", x1 = -44, x2 = 4, z1 = 276, z2 = 300, h = 22, roof = "gableX", rise = 6, style = "mixed", plaster = PLASTER[5],
			upper = { x1 = -44, x2 = 4, z1 = 262, z2 = 276, y1 = 9, y2 = 22 }, front = "S", groundOpen = true, sides = { "W" }, chimney = "E", winFront = 4, dormer = "S", roofSet = ROOFS[7] },
		{ name = "TY_E", x1 = -44, x2 = -4, z1 = 304, z2 = 330, h = 10, roof = "flat", style = "stone", front = "W", doorU = 12, winFront = 2, floors = 1 },
	},
	Waterfront = {
		{ name = "S1", x1 = 46, x2 = 70, z1 = 28, z2 = 56, h = 12, roof = "shed", shedHigh = "E", open = "W", style = "timber", roofSet = ROOFS[6] },
		{ name = "S2", x1 = 50, x2 = 70, z1 = 66, z2 = 92, h = 14, roof = "gableX", rise = 5, style = "timber", front = "W", doorU = 8, winFront = 2, roofSet = ROOFS[2] },
		{ name = "S3", x1 = 54, x2 = 70, z1 = 108, z2 = 146, h = 10, roof = "flat", style = "stone", front = "W", shopU = 19, doorU = 6, winFront = 2, floors = 1 },
		{ name = "S4", x1 = 52, x2 = 70, z1 = 156, z2 = 190, h = 16, roof = "gableZ", rise = 6, style = "mixed", plaster = PLASTER[7], front = "W", shopU = 15, doorU = 4, winFront = 3, chimney = "E",
			balcony = { x1 = 70, x2 = 73.2, z1 = 162, z2 = 180, y = 9, posts = { { 72.6, 163 }, { 72.6, 179 } } } },
		{ name = "S5", x1 = 44, x2 = 70, z1 = 196, z2 = 234, h = 18, roof = "hip", rise = 6, style = "mixed", plaster = PLASTER[3], front = "W", doorU = 20, chimney = "E", winFront = 3 },
		{ name = "S6", x1 = 48, x2 = 70, z1 = 268, z2 = 300, h = 14, roof = "gableX", rise = 5, style = "timber", front = "W", shopU = 16, doorU = 5, winFront = 2, roofSet = ROOFS[4] },
		{ name = "S7", x1 = 44, x2 = 70, z1 = 314, z2 = 364, h = 16, roof = "gableZ", rise = 6, style = "stone", front = "W", doorU = 14, winFront = 3, roofSet = ROOFS[1] },
	},
	UpperMarket = {
		{ name = "U6", x1 = -112, x2 = -74, z1 = 234, z2 = 258, h = 18, base = UP, roof = "hip", rise = 6, style = "mixed", plaster = PLASTER[2], front = "W", doorU = 8, chimney = "E", winFront = 2 },
		{ name = "U1", x1 = -100, x2 = -70, z1 = 268, z2 = 294, h = 20, base = UP, roof = "gableX", rise = 7, style = "plaster", plaster = PLASTER[5], front = "W", shopU = 13, doorU = 22, winFront = 2, roofSet = ROOFS[3] },
		{ name = "U2", x1 = -104, x2 = -70, z1 = 302, z2 = 330, h = 16, base = UP, roof = "hip", rise = 6, style = "mixed", plaster = PLASTER[1], front = "W", doorU = 6, chimney = "E", winFront = 3,
			balcony = { x1 = -70, x2 = -66, z1 = 308, z2 = 324, y = 8.5, posts = { { -66.6, 309 }, { -66.6, 323 } } } },
		{ name = "CurioHouse", x1 = -110, x2 = -76, z1 = 334, z2 = 372, h = 26, base = UP, roof = "gableZ", rise = 9, style = "stoneMixed", plaster = PLASTER[4],
			upper = { x1 = -76, x2 = -70, z1 = 334, z2 = 372, y1 = 9, y2 = 26 }, front = "W", groundOpen = true, chimney = "E", winFront = 3, dormer = "W", roofSet = ROOFS[7] },
		{ name = "U4", x1 = -140, x2 = -120, z1 = 276, z2 = 322, h = 18, base = UP + 2, roof = "gableX", rise = 6, style = "timber", front = "W", shopU = 24, doorU = 8, winFront = 3, roofSet = ROOFS[2] },
		{ name = "U5", x1 = -140, x2 = -112, z1 = 336, z2 = 362, h = 14, base = UP, roof = "flat", style = "plaster", plaster = PLASTER[8], front = "S", doorU = 14, winFront = 2 },
	},
	OldBridge = {
		{ name = "CabinE", x1 = -6, x2 = 3.4, z1 = 406, z2 = 420, h = 10, base = 8, roof = "gableX", rise = 4, style = "timber", front = "W", shopU = 7, door = false, winFront = 0, sides = { "E" }, winSide = 1, roofSet = ROOFS[2], eave = 0.9, noPlinth = true },
		{ name = "CabinW", x1 = 18.6, x2 = 30, z1 = 422, z2 = 436, h = 12, base = 8, roof = "gableX", rise = 5, style = "timber", front = "E", shopU = 7, door = false, winFront = 0, sides = { "W" }, winSide = 1, chimney = "W", roofSet = ROOFS[4], eave = 0.9, noPlinth = true },
	},
	CollectorsRow = {
		{ name = "RN1", x1 = 26, x2 = 44, z1 = 480, z2 = 500, h = 18, base = -1.4, roof = "gableZ", rise = 6, style = "mixed", plaster = PLASTER[8], front = "S", doorU = 6, chimney = "W", winFront = 2, roofSet = ROOFS[3] },
		{ name = "RN2", x1 = -24, x2 = -4, z1 = 473, z2 = 496, h = 14, base = -1.4, roof = "hip", rise = 5, style = "timber", front = "S", shopU = 10, door = false, winFront = 1, roofSet = ROOFS[7] },
		{ name = "RN3", x1 = -44, x2 = -28, z1 = 473, z2 = 504, h = 22, base = -1.4, roof = "gableZ", rise = 7, style = "stone", front = "S", doorU = 8, winFront = 1, chimney = "E", roofSet = ROOFS[1] },
		{ name = "RN4", x1 = -60, x2 = -48, z1 = 473, z2 = 500, h = 16, base = -1.4, roof = "flat", style = "plaster", plaster = PLASTER[3], front = "S", doorU = 6, winFront = 1 },
		{ name = "RS1", x1 = -24, x2 = -4, z1 = 446, z2 = 460, h = 10, base = -1.4, roof = "flat", style = "stone", front = "N", door = false, winFront = 2, floors = 1 },
		{ name = "RS2", x1 = -56, x2 = -28, z1 = 446, z2 = 460, h = 12, base = -1.4, roof = "shed", shedHigh = "S", style = "timber", front = "N", doorU = 8, winFront = 2, roofSet = ROOFS[6] },
	},
}

-- ============================================================ sections
function G.Land()
	local s = section("Land")
	local D = G.DETAIL
	local gCol, gMat = D and C3(150, 140, 122) or PAL.ground, D and M.stone2 or CONCRETE
	local qCol, qMat = D and COBBLE or PAL.quay, D and M.stone or CONCRETE
	local tCol, tMat = D and STONE or PAL.stone, D and M.stone or CONCRETE
	local bCol, bMat = D and STONE2 or PAL.bridge, D and M.stone or CONCRETE
	box(s, "TownSlab", -112, 70, 24, 386, -6, 0, gCol, gMat)
	box(s, "ShoreApron", -80, 16, 17, 24, -6, 0, gCol, gMat)
	box(s, "QuayA", 70, 92, 24, 210, -6, -0.8, qCol, qMat)
	box(s, "QuayB", 70, 86, 210, 400, -6, -0.8, qCol, qMat)
	box(s, "QuayCorner", 40, 70, 386, 400, -6, -0.8, qCol, qMat)
	box(s, "RiverQuayE", -72, -4, 386, 400, -6, -0.8, qCol, qMat)
	box(s, "UpperTerraceS", -142, -70, 230, 262, 0, UP, tCol, tMat)
	box(s, "UpperTerraceN", -142, -68, 262, 372, 0, UP, tCol, tMat)
	box(s, "UpperTerraceEdge", -68, -54, 262, 362, 0, UP, tCol, tMat)
	box(s, "UpperTerraceRampBase", -68, -54, 362, 372, 0, 8, tCol, tMat)
	box(s, "BackTerrace", -140, -104, 270, 330, UP, UP + 2, D and STONEDARK or PAL.stoneDark, tMat)
	box(s, "CausewayWall", -70, -4, 372, 386, 0, 8, bCol, bMat)
	box(s, "AbutmentSquare", -4, 40, 366, 400, -6, 8, bCol, bMat)
	box(s, "StepsLandingPillar", 40, 48, 366, 372, 0, 8, bCol, bMat)
	box(s, "NorthBankA", -60, 50, 444, 476, -6, -1.4, gCol, gMat)
	box(s, "NorthBankB", -60, 44, 476, 520, -6, -1.4, gCol, gMat)
	box(s, "NorthAbutment", -4, 26, 438, 456, -6, 8, bCol, bMat)
	if D then
		box(s, "QuayCopingA", 91.4, 92.6, 24, 210, -1.0, -0.4, LIME, M.stone2)
		box(s, "QuayCopingB", 85.4, 86.6, 210, 400, -1.0, -0.4, LIME, M.stone2)
		box(s, "TerraceCoping", -70.6, -69.4, 230, 262, UP - 0.2, UP + 0.4, LIME, M.stone2)
		box(s, "TerraceCoping", -54.6, -53.4, 262, 362, UP - 0.2, UP + 0.4, LIME, M.stone2)
		for _, z in ipairs({ 234, 254 }) do box(s, "Buttress", -73, -70, z, z + 3, 0, UP - 3, STONEDARK, M.stone) end
		slab(s, "ForkSquare", -30, 6, 236, 262, 0.1, 0.3, C3(126, 118, 108), M.stone)
		slab(s, "Courtyard", -80, -40, 118, 160, 0.1, 0.3, C3(138, 128, 112), M.stone)
		slab(s, "TannersYard", -4, 40, 304, 332, 0.1, 0.3, C3(120, 108, 92), M.stone)
	else
		slab(s, "ForkSquare", -30, 6, 236, 262, 0.1, 0.3, PAL.square, CONCRETE)
		slab(s, "Courtyard", -80, -40, 118, 160, 0.1, 0.3, PAL.square, CONCRETE)
		slab(s, "TannersYard", -4, 40, 304, 332, 0.1, 0.3, PAL.square, CONCRETE)
	end
	return s
end

-- Cliffs: rock masses; detailed = a few leaning slate blocks per run so no face is a flat plane
local function rockRun(s, name, x1, x2, z1, z2, y1, y2, seed)
	if not G.DETAIL then return box(s, name, x1, x2, z1, z2, y1, y2, PAL.cliff, SLATE) end
	local r = rng(seed)
	box(s, name, x1, x2, z1, z2, y1, y2 - 3, CLIFF, M.slate)
	local n = math.max(2, math.floor(math.max(x2 - x1, z2 - z1) / 22))
	local alongX = (x2 - x1) > (z2 - z1)
	for i = 1, n do
		local t = (i - 0.5) / n
		local cx = alongX and (x1 + (x2 - x1) * t) or (x1 + x2) / 2
		local cz = alongX and (z1 + z2) / 2 or (z1 + (z2 - z1) * t)
		local sx = alongX and (x2 - x1) / n * (0.8 + r() * 0.5) or (x2 - x1) * (0.8 + r() * 0.5)
		local sz = alongX and (z2 - z1) * (0.8 + r() * 0.5) or (z2 - z1) / n * (0.8 + r() * 0.5)
		local h = (y2 - y1) * (0.75 + r() * 0.45)
		local cf = at(cx, y1 + h / 2, cz) * CFrame.Angles(math.rad((r() - 0.5) * 10), math.rad((r() - 0.5) * 24), math.rad((r() - 0.5) * 10))
		mk(s, name .. "Rock", Vector3.new(sx, h, sz), cf, pick(r, { CLIFF, CLIFF2, C3(74, 70, 68) }), M.slate)
	end
end
function G.Cliffs()
	local s = section("Cliffs")
	rockRun(s, "EastCliffA", -134, -112, 17, 80, -6, 26, 11)
	rockRun(s, "EastCliffB", -138, -112, 80, 150, -6, 32, 12)
	rockRun(s, "EastCliffC", -132, -112, 150, 230, -6, 28, 13)
	rockRun(s, "UpperCliffA", -166, -142, 230, 300, -6, 40, 14)
	rockRun(s, "UpperCliffB", -170, -142, 300, 372, -6, 46, 15)
	rockRun(s, "ShoreRock", -112, -80, 17, 60, -6, 22, 16)
	box(s, "ShoreWall", -80, -46, 17, 20, -6, 4, G.DETAIL and STONEDARK or PAL.stoneDark, G.DETAIL and M.stone or CONCRETE)
	rockRun(s, "GorgeS", -112, -72, 372, 400, -6, 30, 17)
	rockRun(s, "GorgeN", -112, -60, 444, 520, -6, 34, 18)
	rockRun(s, "GorgeEnd", -122, -100, 396, 448, -6, 36, 19)
	rockRun(s, "NorthCliffA", -60, 0, 520, 544, -6, 34, 20)
	rockRun(s, "NorthCliffB", 0, 54, 520, 540, -6, 30, 21)
	box(s, "NorthCliffC", 50, 58, 444, 476, -6, 6, G.DETAIL and CLIFF2 or PAL.cliff2, SLATE)
	box(s, "NorthCliffD", 44, 52, 476, 520, -6, 8, G.DETAIL and CLIFF2 or PAL.cliff2, SLATE)
	return s
end

-- Arrival Dock
function G.ArrivalDock()
	local s = section("ArrivalDock")
	local D = G.DETAIL
	slab(s, "DockDeck", -14, 14, -12, 18, 0.4, 1.2, D and PLANK or PAL.plank, M.plank)
	for _, c in ipairs({ { -13, 0 }, { 13, 6 }, { -13, 16 }, { 13, 17 } }) do
		box(s, "DockPost", c[1] - 0.5, c[1] + 0.5, c[2] - 0.5, c[2] + 0.5, -4, 2.4, D and TIMBER or PAL.woodDark, M.wood)
	end
	slab(s, "Jetty", 14, 40, 4, 12, 0.4, 1.0, D and PLANKDARK or PAL.plank, M.plank)
	box(s, "JettyPost", 38, 39, 3, 4, -4, 2.2, D and TIMBER or PAL.woodDark, M.wood)
	slab(s, "BoathousePlank", -22, -14, 8, 16, 0.4, 1.0, D and PLANK or PAL.plank, M.plank)
	for _, b in ipairs(G.BUILDINGS.ArrivalDock) do renderBuilding(s, b) end
	slab(s, "Boardwalk", 14, 70, 12, 24, 0.2, 1.0, D and PLANKDARK or PAL.plank, M.plank)
	if D then
		for _, c in ipairs({ { -13, -10 }, { -13, -2 }, { 13, -10 }, { 13, -2 } }) do
			box(s, "RailPost", c[1] - 0.25, c[1] + 0.25, c[2] - 0.25, c[2] + 0.25, 0.4, 3.4, TIMBER2, M.wood)
		end
		rod(s, "Rope", Vector3.new(-13, 3.1, -10), Vector3.new(-13, 3.1, -2), 0.16, ROPE, M.cloth)
		rod(s, "Rope", Vector3.new(13, 3.1, -10), Vector3.new(13, 3.1, -2), 0.16, ROPE, M.cloth)
		for _, x in ipairs({ 22, 38, 54, 68 }) do box(s, "WalkPost", x - 0.4, x + 0.4, 11.5, 12.3, -4, 1.4, TIMBER, M.wood) end
		box(s, "BoatHull", 20, 26, -6, 6, -1.6, 0.9, C3(96, 70, 46), M.plank)
		mk(s, "BoatBow", Vector3.new(4.3, 2.5, 4.3), at(23, -0.35, 7.2) * CFrame.Angles(0, math.rad(45), 0), C3(96, 70, 46), M.plank)
		box(s, "Gunwale", 19.7, 20.4, -6, 6, 0.9, 1.4, TIMBER, M.wood)
		box(s, "Gunwale", 25.6, 26.3, -6, 6, 0.9, 1.4, TIMBER, M.wood)
		box(s, "Thwart", 20, 26, -0.5, 0.5, 0.4, 0.8, PLANK, M.plank)
		for _, c in ipairs({ { -15.4, -9 }, { 11, 15 } }) do cyl(s, "Bollard", 1.2, 2.2, at(c[1], 1.5, c[2]), IRON, M.metal) end
	else
		box(s, "Boat", 20, 26, -8, 6, -1.6, 1.2, PAL.wood, WOODP)
	end
	return s
end

-- Market Entrance
function G.MarketEntrance()
	local s = section("MarketEntrance")
	for _, b in ipairs(G.BUILDINGS.MarketEntrance) do renderBuilding(s, b) end
	if G.DETAIL then
		box(s, "GateSignArm", 4.4, 7.4, 40.0, 40.4, 10.6, 10.9, IRON, M.metal)
		local sign = box(s, "GateSign", 4.6, 6.8, 39.85, 40.55, 8.4, 10.3, SIGN, M.plank)
		plate(sign, "RIVERSIDE MARKET", Enum.NormalId.Back, INK, SIGN, 1, Enum.Font.Antique, 40)
		plate(sign, "RIVERSIDE MARKET", Enum.NormalId.Front, INK, SIGN, 1, Enum.Font.Antique, 40)
		box(s, "GatePost", -10.8, -9.2, 36, 37.6, 0, 6.5, STONE2, M.stone2)
		box(s, "GatePostCap", -11.1, -8.9, 35.7, 37.9, 6.5, 7.1, LIME, M.stone2)
	else
		box(s, "GateSign", 4.5, 7, 40, 40.4, 8, 10.4, PAL.sign, SP)
		box(s, "GateSignArm", 4.5, 7.2, 40.1, 40.3, 10.4, 10.7, PAL.woodDark, WOODP)
	end
	return s
end

-- Lower Market Street
function G.LowerMarket()
	local s = section("LowerMarket")
	local D = G.DETAIL
	for _, b in ipairs(G.BUILDINGS.LowerMarket) do renderBuilding(s, b) end
	-- B5 external stair up its street face (stall 4 sits beneath its high half)
	if D then
		steps(s, "B5Stair", Vector3.new(4, 0, 196), Vector3.new(4, 9, 218), 4, PLANKDARK, M.plank)
		slab(s, "B5Landing", 2, 6, 218, 224, 9, 0.6, PLANKDARK, M.plank)
		for _, z in ipairs({ 197, 205, 213, 223 }) do box(s, "B5Baluster", 1.75, 2.25, z - 0.25, z + 0.25, 0, 9.7, TIMBER, M.wood) end
		mk(s, "B5RailSlope", Vector3.new(0.35, 0.35, 24), at(2, 6.5, 207) * CFrame.Angles(math.atan(9, 22), 0, 0), TIMBER, M.wood)
		box(s, "B5LandingRail", 1.8, 2.2, 218, 224, 9.6, 9.9, TIMBER, M.wood)
	else
		ramp(s, "B5Stair", Vector3.new(4, 0, 196), Vector3.new(4, 9, 218), 4, 1.0, PAL.woodDark, SP)
		slab(s, "B5Landing", 2, 6, 218, 224, 9, 0.8, PAL.woodDark, WOODP)
	end
	for _, x in ipairs({ -40, -27, -14, 0 }) do
		if D then
			box(s, "ArcadeColumn", x - 0.9, x + 0.9, 262.5, 264.3, 0, 9, STONE2, M.stone2)
			box(s, "ColumnCap", x - 1.2, x + 1.2, 262.2, 264.6, 8.4, 9.0, LIME, M.stone2)
			box(s, "ColumnBase", x - 1.2, x + 1.2, 262.2, 264.6, 0, 0.8, STONEDARK, M.stone)
		else
			box(s, "ArcadeColumn", x - 0.9, x + 0.9, 262.5, 264.3, 0, 9, PAL.stone, SP)
		end
	end
	box(s, "YardWall", 40, 48, 311, 332, 0, 6, D and STONEDARK or PAL.stoneDark, D and M.stone or CONCRETE)
	if D then
		cyl(s, "Well", 5, 3, at(-14, 1.5, 250), STONE, M.stone)
		cyl(s, "WellRim", 5.4, 0.5, at(-14, 3.1, 250), LIME, M.stone2)
		for _, dx in ipairs({ -2.2, 2.2 }) do box(s, "WellPost", -14 + dx - 0.25, -14 + dx + 0.25, 249.75, 250.25, 3, 8, TIMBER, M.wood) end
		gable(s, "Well", -17.2, -10.8, 248, 252, 8, 1.8, true, ROOFS[2][1], ROOFS[2][2], 0.3)
		box(s, "WellBeam", -16.4, -11.6, 249.8, 250.2, 7.6, 8.1, TIMBER, M.wood)
		for _, t in ipairs({ { -62, 138, 2.4, 10, 15 }, { 20, 318, 2.0, 9, 13 } }) do
			cyl(s, "TreeTrunk", t[3], t[4], at(t[1], t[4] / 2, t[2]), C3(72, 54, 38), M.wood)
			ball(s, "TreeCanopy", t[5], at(t[1] + 1.5, t[4] + 3, t[2] - 1), C3(84, 118, 62), M.grass)
			ball(s, "TreeCanopy", t[5] * 0.8, at(t[1] - 2.5, t[4] + 5, t[2] + 2.5), C3(96, 132, 70), M.grass)
			ball(s, "TreeCanopy", t[5] * 0.7, at(t[1] + 1, t[4] + 7.5, t[2] + 1.5), C3(78, 110, 58), M.grass)
		end
	else
		cyl(s, "Well", 5, 3, at(-14, 1.5, 250), PAL.stoneDark, CONCRETE)
		cyl(s, "CourtyardTree", 2.4, 10, at(-62, 5, 138), PAL.woodDark, WOODP)
		box(s, "CourtyardCanopy", -70, -54, 130, 146, 9, 17, PAL.green, SP)
		cyl(s, "YardTree", 2, 9, at(20, 4.5, 318), PAL.woodDark, WOODP)
		box(s, "YardCanopy", 13, 27, 311, 325, 8, 15, PAL.green, SP)
	end
	return s
end

-- Waterfront
function G.Waterfront()
	local s = section("Waterfront")
	local D = G.DETAIL
	for _, b in ipairs(G.BUILDINGS.Waterfront) do renderBuilding(s, b) end
	box(s, "HoistBeam", 70, 76, 338, 340, 15.5, 16.5, D and TIMBER or PAL.woodDark, M.wood)
	local ac, am = D and STONE2 or PAL.stone, D and M.stone2 or CONCRETE
	box(s, "LaneArchPierS", 44, 48, 248, 250, 0, 9, ac, am)
	box(s, "LaneArchPierN", 44, 48, 262, 264, 0, 9, ac, am)
	if D then
		arch(s, "LaneArch", at(46, 5.6, 256) * CFrame.Angles(0, math.rad(90), 0), 6.4, 9, 1.4, 4, STONE2, M.stone2)
	else
		box(s, "LaneArchLintel", 44, 48, 248, 264, 9, 11, PAL.stone, CONCRETE)
	end
	slab(s, "Pier", 92, 114, 116, 122, -0.6, 1.0, D and PLANKDARK or PAL.plank, M.plank)
	slab(s, "MouthPier", 86, 104, 378, 384, -0.6, 1.0, D and PLANKDARK or PAL.plank, M.plank)
	if D then
		for _, x in ipairs({ 96, 106, 113 }) do
			box(s, "PierPost", x - 0.45, x + 0.45, 115.3, 116.2, -5, 1.6, TIMBER, M.wood)
			box(s, "PierPost", x - 0.45, x + 0.45, 121.8, 122.7, -5, 1.6, TIMBER, M.wood)
		end
		for _, x in ipairs({ 90, 98, 103 }) do box(s, "PierPost", x - 0.45, x + 0.45, 383.8, 384.7, -5, 1.6, TIMBER, M.wood) end
		rod(s, "Rope", Vector3.new(96, 1.4, 115.7), Vector3.new(113, 1.4, 115.7), 0.16, ROPE, M.cloth)
		box(s, "BoatHull", 94, 100, 124, 138, -1.6, 0.9, C3(88, 66, 44), M.plank)
		mk(s, "BoatBow", Vector3.new(4.3, 2.5, 4.3), at(97, -0.35, 139.2) * CFrame.Angles(0, math.rad(45), 0), C3(88, 66, 44), M.plank)
		box(s, "Gunwale", 93.7, 94.4, 124, 138, 0.9, 1.4, TIMBER, M.wood)
		box(s, "Gunwale", 99.6, 100.3, 124, 138, 0.9, 1.4, TIMBER, M.wood)
		box(s, "BoatHull", 88, 93, 360, 372, -1.6, 0.7, C3(108, 84, 58), M.plank)
		mk(s, "BoatBow", Vector3.new(3.6, 2.2, 3.6), at(90.5, -0.45, 373) * CFrame.Angles(0, math.rad(45), 0), C3(108, 84, 58), M.plank)
		for _, z in ipairs({ 44, 96, 150, 188, 236, 262, 318, 356 }) do
			local x = (z < 210) and 90.6 or 84.6
			cyl(s, "Bollard", 1.1, 2.0, at(x, 0.2, z), IRON, M.metal)
		end
		for _, z in ipairs({ 70, 132, 214, 292, 346 }) do
			local x = (z < 210) and 89.5 or 83.5
			cyl(s, "Barrel", 2.2, 2.6, at(x, 0.5, z), C3(100, 74, 48), M.plank)
		end
		steps(s, "WaterStairA", Vector3.new(88, -0.8, 80), Vector3.new(92.5, -3.2, 80), 8, STONE, M.stone)
		steps(s, "WaterStairB", Vector3.new(82, -0.8, 300), Vector3.new(86.5, -3.2, 300), 8, STONE, M.stone)
		steps(s, "WaterStairC", Vector3.new(78, -0.8, 392), Vector3.new(86.5, -3.4, 392), 6, STONE, M.stone)
		mk(s, "Net", Vector3.new(0.3, 5.2, 7.0), at(70.4, 5.0, 60) * CFrame.Angles(0, 0, math.rad(6)), C3(120, 112, 90), M.cloth, { Transparency = 0.35 })
		mk(s, "Net", Vector3.new(6.0, 0.25, 3.4), at(78, -0.6, 150) * CFrame.Angles(0, math.rad(20), 0), C3(120, 112, 90), M.cloth, { Transparency = 0.3 })
	else
		box(s, "PierPost", 113, 114, 115, 116, -5, 1.4, PAL.woodDark, WOODP)
		box(s, "PierBoat", 94, 100, 124, 138, -1.6, 1.0, PAL.wood, WOODP)
		ramp(s, "WaterStairA", Vector3.new(88, -0.8, 80), Vector3.new(92, -3, 80), 8)
		ramp(s, "WaterStairB", Vector3.new(82, -0.8, 300), Vector3.new(86, -3, 300), 8)
		ramp(s, "WaterStairC", Vector3.new(78, -0.8, 392), Vector3.new(86, -3.2, 392), 6)
	end
	return s
end

-- Upper Market
function G.UpperMarket()
	local s = section("UpperMarket")
	local D = G.DETAIL
	for _, b in ipairs(G.BUILDINGS.UpperMarket) do renderBuilding(s, b) end
	for _, z in ipairs({ 336, 348, 360, 370 }) do
		if D then
			box(s, "ArcadeColumn", -71.8, -70, z - 0.9, z + 0.9, UP, UP + 9, STONE2, M.stone2)
			box(s, "ColumnCap", -72.1, -69.7, z - 1.2, z + 1.2, UP + 8.4, UP + 9, LIME, M.stone2)
		else
			box(s, "ArcadeColumn", -71.8, -70, z - 0.9, z + 0.9, UP, UP + 9, PAL.stone, SP)
		end
	end
	local pc, pm = D and LIME or PAL.stoneDark, D and M.stone2 or CONCRETE
	box(s, "ParapetW", -55, -54, 266, 306, UP, UP + 1.2, pc, pm)
	box(s, "ParapetW2", -55, -54, 330, 362, UP, UP + 1.2, pc, pm)
	box(s, "ParapetS", -70, -62, 262, 263, UP, UP + 1.2, pc, pm)
	box(s, "ParapetSW", -71, -70, 230, 262, UP, UP + 1.2, pc, pm)
	slab(s, "Overlook", -54, -46, 306, 330, UP, 1.2, D and STONE or PAL.stone, D and M.stone or CONCRETE)
	box(s, "OverlookRail", -47, -46, 306, 330, UP, UP + 1.2, pc, pm)
	if D then
		for _, z in ipairs({ 309, 318, 327 }) do mk(s, "OverlookBracket", Vector3.new(6.2, 0.7, 0.7), at(-50, UP - 2.6, z) * CFrame.Angles(0, 0, math.rad(40)), STONEDARK, M.stone) end
		box(s, "Bench", -52.6, -47.4, 314, 315.4, UP + 1.0, UP + 1.5, PLANKDARK, M.plank)
		box(s, "BenchLeg", -52.2, -51.4, 314.2, 315.2, UP, UP + 1.0, TIMBER, M.wood)
		box(s, "BenchLeg", -48.6, -47.8, 314.2, 315.2, UP, UP + 1.0, TIMBER, M.wood)
		for _, z in ipairs({ 280, 344 }) do
			box(s, "Planter", -55.6, -53.4, z, z + 3.2, UP + 1.2, UP + 2.4, C3(126, 84, 62), M.brick)
			ball(s, "PlanterBush", 2.8, at(-54.5, UP + 3.3, z + 1.6), C3(90, 124, 66), M.grass)
		end
		slab(s, "EdgeStreet", -68, -54, 266, 362, UP + 0.12, 0.24, COBBLE, M.stone)
		slab(s, "UpperLane", -104, -70, 294, 302, UP + 0.12, 0.24, COBBLE, M.stone)
	else
		slab(s, "EdgeStreet", -68, -54, 266, 362, UP + 0.12, 0.24, PAL.road, CONCRETE)
		slab(s, "UpperLane", -104, -70, 294, 302, UP + 0.12, 0.24, PAL.road, CONCRETE)
	end
	return s
end

-- Old Bridge
function G.OldBridge()
	local s = section("OldBridge")
	local D = G.DETAIL
	local bc, bm = D and STONE2 or PAL.bridge, D and M.stone or CONCRETE
	local dc, dm = D and STONEDARK or PAL.stoneDark, D and M.stone or CONCRETE
	slab(s, "Deck", 4, 18, 400, 440, 8, 2, D and COBBLE or PAL.bridge, D and M.stone or CONCRETE)
	box(s, "Pier", 3, 19, 416, 424, -6, 6, dc, dm)
	if D then
		mk(s, "Cutwater", Vector3.new(6, 10, 6), at(0.6, -1, 420) * CFrame.Angles(0, math.rad(45), 0), STONEDARK, M.stone)
		mk(s, "Cutwater", Vector3.new(6, 10, 6), at(21.4, -1, 420) * CFrame.Angles(0, math.rad(45), 0), STONEDARK, M.stone)
		arch(s, "ArchS", at(11, -2.2, 408) * CFrame.Angles(0, math.rad(90), 0), 7.6, 9, 1.4, 14.4, STONE2, M.stone)
		arch(s, "ArchN", at(11, -2.2, 432) * CFrame.Angles(0, math.rad(90), 0), 7.6, 9, 1.4, 14.4, STONE2, M.stone)
		box(s, "SpandrelS", 3.6, 18.4, 400, 404, 0, 6, STONE, M.stone)
		box(s, "SpandrelSp", 3.6, 18.4, 412.5, 416, 0, 6, STONE, M.stone)
		box(s, "SpandrelNp", 3.6, 18.4, 424, 427.5, 0, 6, STONE, M.stone)
		box(s, "SpandrelN", 3.6, 18.4, 436, 440, 0, 6, STONE, M.stone)
		box(s, "ParapetE1", 4, 5.2, 400, 406, 8, 9.3, STONE, M.stone); box(s, "CopingE1", 3.8, 5.4, 400, 406, 9.3, 9.7, LIME, M.stone2)
		box(s, "ParapetE2", 4, 5.2, 420, 440, 8, 9.3, STONE, M.stone); box(s, "CopingE2", 3.8, 5.4, 420, 440, 9.3, 9.7, LIME, M.stone2)
		box(s, "ParapetW1", 16.8, 18, 400, 422, 8, 9.3, STONE, M.stone); box(s, "CopingW1", 16.6, 18.2, 400, 422, 9.3, 9.7, LIME, M.stone2)
		box(s, "ParapetW2", 16.8, 18, 436, 440, 8, 9.3, STONE, M.stone); box(s, "CopingW2", 16.6, 18.2, 436, 440, 9.3, 9.7, LIME, M.stone2)
		for _, p in ipairs({ { 4.6, 403 }, { 17.4, 438 }, { 4.6, 438 } }) do box(s, "LampPost", p[1] - 0.3, p[1] + 0.3, p[2] - 0.3, p[2] + 0.3, 9.6, 14.6, IRON, M.metal) end
	else
		box(s, "Cutwater", 3, 19, 424, 428, -6, 4, PAL.stoneDark, CONCRETE)
		box(s, "ParapetE1", 4, 5.2, 400, 406, 8, 9.3, PAL.stone, CONCRETE)
		box(s, "ParapetE2", 4, 5.2, 420, 440, 8, 9.3, PAL.stone, CONCRETE)
		box(s, "ParapetW1", 16.8, 18, 400, 422, 8, 9.3, PAL.stone, CONCRETE)
		box(s, "ParapetW2", 16.8, 18, 436, 440, 8, 9.3, PAL.stone, CONCRETE)
	end
	slab(s, "CabinEBracket", -6, 4, 406, 420, 8, 2, D and PLANKDARK or PAL.woodDark, M.plank)
	slab(s, "CabinWBracket", 18, 30, 422, 436, 8, 2, D and PLANKDARK or PAL.woodDark, M.plank)
	if D then
		for _, z in ipairs({ 408, 413, 418 }) do mk(s, "Strut", Vector3.new(0.7, 0.7, 7.2), at(-2.6, 3.6, z) * CFrame.Angles(0, 0, math.rad(-52)), TIMBER, M.wood) end
		for _, z in ipairs({ 424, 429, 434 }) do mk(s, "Strut", Vector3.new(0.7, 0.7, 7.2), at(24.6, 3.6, z) * CFrame.Angles(0, 0, math.rad(52)), TIMBER, M.wood) end
	end
	for _, b in ipairs(G.BUILDINGS.OldBridge) do renderBuilding(s, b) end
	box(s, "SquareParapetN1", -4, 4, 399, 400, 8, 9.3, bc, bm)
	box(s, "SquareParapetN2", 18, 40, 399, 400, 8, 9.3, bc, bm)
	box(s, "SquareParapetW", 39, 40, 372, 400, 8, 9.3, bc, bm)
	slab(s, "StepsLanding", 40, 48, 366, 372, 8.12, 0.24, D and COBBLE or PAL.square, D and M.stone or CONCRETE)
	box(s, "CausewayParapetA", -70, -33, 385, 386, 8, 9.3, bc, bm)
	box(s, "CausewayParapetB", -27, -4, 385, 386, 8, 9.3, bc, bm)   -- the gap is exactly the stair head
	-- gate tower: stone base, jettied timber upper storey, cap, lantern cupola; road passage vaulted
	if D then
		box(s, "TowerE", -2, 4, 440, 456, 8, 30, STONE, M.stone)
		box(s, "TowerW", 18, 24, 440, 456, 8, 30, STONE, M.stone)
		box(s, "TowerTop", -2, 24, 440, 456, 20, 30, STONE, M.stone)
		box(s, "TowerUpper", -3, 25, 439, 457, 30, 54, PLASTER[7], M.plaster)
		for _, zf in ipairs({ 438.8, 457.2 }) do
			box(s, "TowerBeam", -3.2, 25.2, zf - 0.3, zf + 0.3, 30, 30.7, TIMBER, M.wood)
			box(s, "TowerBeam", -3.2, 25.2, zf - 0.3, zf + 0.3, 42, 42.6, TIMBER, M.wood)
			for _, x in ipairs({ -2.6, 4.2, 10.4, 17.8, 24.6 }) do box(s, "TowerStud", x - 0.3, x + 0.3, zf - 0.3, zf + 0.3, 30, 54, TIMBER, M.wood) end
			mk(s, "TowerBrace", Vector3.new(0.45, 7, 0.45), at(7.2, 35.4, zf) * CFrame.Angles(0, 0, math.rad(36)), TIMBER, M.wood)
			mk(s, "TowerBrace", Vector3.new(0.45, 7, 0.45), at(14.8, 48.4, zf) * CFrame.Angles(0, 0, math.rad(-36)), TIMBER, M.wood)
		end
		for _, x in ipairs({ 3, 19 }) do
			box(s, "TowerWindow", x - 1.2, x + 1.2, 438.6, 439.0, 45.5, 48.7, GLASS, M.glass, { Reflectance = 0.14 })
			box(s, "TowerWindowFrame", x - 1.5, x + 1.5, 438.5, 438.85, 45.2, 49.0, TIMBER, M.wood)
		end
		box(s, "TowerCap", -4, 26, 438, 458, 54, 56, STONEDARK, M.stone)
		gable(s, "Tower", -3, 25, 439, 457, 56, 8, false, ROOFS[7][1], ROOFS[7][2], 1.4)
		box(s, "TowerRidge", -4.6, 26.6, 447.6, 448.4, 63.8, 64.6, TIMBER, M.wood)
		for _, p in ipairs({ { 8.2, 445.2 }, { 13.8, 445.2 }, { 8.2, 450.8 }, { 13.8, 450.8 } }) do box(s, "CupolaPost", p[1] - 0.35, p[1] + 0.35, p[2] - 0.35, p[2] + 0.35, 64, 70, TIMBER, M.wood) end
		box(s, "CupolaFloor", 7.4, 14.6, 444.4, 451.6, 63.6, 64.2, PLANKDARK, M.plank)
		gable(s, "Cupola", 7.4, 14.6, 444.4, 451.6, 70, 3.6, true, ROOFS[7][1], ROOFS[7][2], 0.8)
		box(s, "LanternCage", 9.8, 12.2, 446.8, 449.2, 65.2, 68.2, IRON, M.metal, { Transparency = 0.4 })
		arch(s, "PassageArchS", at(11, 8 + 5.2, 440.6), 7.2, 9, 1.3, 1.4, STONE2, M.stone2)   -- spring 5.2 above the DECK
		arch(s, "PassageArchN", at(11, 8 + 5.2, 455.4), 7.2, 9, 1.3, 1.4, STONE2, M.stone2)
		box(s, "PassageWall", 3.6, 4.4, 440, 456, 8, 20, STONEDARK, M.stone)
		box(s, "PassageWall", 17.6, 18.4, 440, 456, 8, 20, STONEDARK, M.stone)
		box(s, "WardenDoor", 17.9, 18.15, 445.5, 448.5, 8, 14.2, PLANKDARK, M.plank)
		box(s, "WardenDoorFrame", 17.7, 18.0, 445.1, 448.9, 8, 14.6, TIMBER, M.wood)
	else
		box(s, "TowerE", -2, 4, 440, 456, 8, 62, PAL.bridge, CONCRETE)
		box(s, "TowerW", 18, 24, 440, 456, 8, 62, PAL.bridge, CONCRETE)
		box(s, "TowerTop", -2, 24, 440, 456, 20, 62, PAL.bridge, CONCRETE)
		box(s, "TowerCap", -3, 25, 439, 457, 62, 64, PAL.stoneDark, CONCRETE)
		box(s, "Lantern", 7, 15, 443, 453, 64, 76, PAL.stone, CONCRETE)
	end
	-- north stub: embankment, the vault Collector's Row passes through, the ramp down, the closed gate
	box(s, "EmbankA", -2, 24, 456, 462, -1.4, 8, bc, bm)
	slab(s, "VaultRoad", -2, 24, 462, 470, 8, 2, bc, bm)
	box(s, "EmbankB", -2, 24, 470, 490, -1.4, 2, bc, bm)
	box(s, "EmbankB1", -2, 24, 470, 477, 2, 6.6, bc, bm)
	box(s, "EmbankB2", -2, 24, 477, 484, 2, 4.5, bc, bm)
	box(s, "EmbankB3", -2, 24, 484, 490, 2, 2.6, bc, bm)
	ramp(s, "StubRamp", Vector3.new(11, 8, 470), Vector3.new(11, 2, 490), 26, 1.0, D and COBBLE or PAL.bridge, D and M.stone or SP)
	if D then
		box(s, "ClosedGateArchL", -4, 1, 490, 494, -1.4, 12, STONE, M.stone)
		box(s, "ClosedGateArchR", 21, 26, 490, 494, -1.4, 12, STONE, M.stone)
		box(s, "ClosedGateHead", -4, 26, 490, 494, 12, 16, STONE, M.stone)
		box(s, "ClosedGateDoor", 1, 21, 491.2, 492.4, 2, 12, C3(62, 46, 34), M.plank)
		for _, y in ipairs({ 4.2, 7.4, 10.4 }) do box(s, "GateStrap", 1, 21, 491.0, 491.25, y, y + 0.5, IRON, M.metal) end
		box(s, "GateBeam", -4, 26, 488, 490, 12, 14, TIMBER, M.wood)
		box(s, "StubParapet", -2, -1, 456, 490, 8, 9.2, STONE, M.stone)
		box(s, "StubParapet", 23, 24, 456, 462, 8, 9.2, STONE, M.stone)
	else
		box(s, "ClosedGate", -4, 26, 490, 494, -1.4, 16, PAL.stoneDark, CONCRETE)
		box(s, "ClosedGateBeam", -4, 26, 488, 490, 12, 14, PAL.woodDark, WOODP)
	end
	return s
end

-- Collector's Row
function G.CollectorsRow()
	local s = section("CollectorsRow")
	local D = G.DETAIL
	for _, b in ipairs(G.BUILDINGS.CollectorsRow) do renderBuilding(s, b) end
	box(s, "EndOverhang", -60, -44, 458, 474, 8, 9, D and C3(58, 44, 32) or PAL.woodDark, M.plank)
	if D then
		for _, x in ipairs({ -58, -46 }) do box(s, "OverhangPost", x - 0.4, x + 0.4, 461.5, 462.3, -1.4, 8, C3(58, 44, 32), M.wood) end
		mk(s, "RelicHead", Vector3.new(11, 9, 9), at(-52, -2.5, 465) * CFrame.Angles(math.rad(18), math.rad(-25), math.rad(12)), C3(112, 118, 106), M.stone2)
		mk(s, "RelicEye", Vector3.new(2.2, 1.4, 0.6), at(-49.2, 0.6, 461.4) * CFrame.Angles(math.rad(18), math.rad(-25), math.rad(12)), C3(72, 76, 70), M.stone)
		mk(s, "RelicMoss", Vector3.new(6, 0.5, 5), at(-53, 1.6, 466) * CFrame.Angles(math.rad(14), math.rad(-25), math.rad(8)), C3(88, 112, 62), M.grass)
		-- a washing line of odd cloths across the lane
		rod(s, "Line", Vector3.new(-6, 5.6, 472.6), Vector3.new(-16, 5.2, 461.2), 0.1, ROPE, M.cloth)
		local cr = rng(hashName("rowcloth"))
		for _, t in ipairs({ 0.25, 0.5, 0.75 }) do
			local x, z = -6 - 10 * t, 472.6 - 11.4 * t
			mk(s, "HungCloth", Vector3.new(1.4, 2.2, 0.15), at(x, 4.3, z) * CFrame.Angles(0, math.rad(-49), 0), pick(cr, CLOTHS), M.cloth)
		end
		box(s, "RowRail", 24, 48, 460.4, 461.4, -1.4, 0.2, TIMBER, M.wood)
		for _, x in ipairs({ 25, 36, 47 }) do box(s, "RowRailPost", x - 0.25, x + 0.25, 460.5, 461.3, -1.4, 1.6, TIMBER, M.wood) end
		rod(s, "RowRope", Vector3.new(25, 1.4, 460.9), Vector3.new(47, 1.4, 460.9), 0.14, ROPE, M.cloth)
		box(s, "RowEndRail", 47.6, 48.4, 461, 470, -1.4, 1.6, TIMBER, M.wood)   -- the lane dead-ends at the bank edge
		slab(s, "RowLane", -56, 48, 462, 471, -1.28, 0.24, C3(96, 90, 84), M.stone)
	else
		mk(s, "RelicHead", Vector3.new(11, 9, 9), at(-52, -2.5, 465) * CFrame.Angles(math.rad(18), math.rad(-25), math.rad(12)), PAL.relic, SLATE)
		box(s, "RowRail", 24, 48, 460.4, 461.4, -1.4, 0.2, PAL.woodDark, WOODP)
		slab(s, "RowLane", -56, 48, 462, 471, -1.28, 0.24, PAL.road, CONCRETE)
	end
	return s
end

-- Stairs: real treads in detail mode, tilted slabs in the greybox
function G.Stairs()
	local s = section("Stairs")
	local D = G.DETAIL
	local flights = {
		{ "ForkStairA", Vector3.new(-30, 0, 246), Vector3.new(-54, 7, 246), 6 },
		{ "ForkStairB", Vector3.new(-58, 7, 250), Vector3.new(-58, UP, 262), 6 },
		{ "UpperToCauseway", Vector3.new(-61, UP, 362), Vector3.new(-61, 8, 372), 8 },
		{ "BridgeSteps", Vector3.new(44, -0.8, 396), Vector3.new(44, 8, 372), 8 },
		{ "PocketStair", Vector3.new(-28, 8, 388), Vector3.new(-54, -0.8, 388), 4 },
		{ "StubToRow", Vector3.new(24, 6.8, 474), Vector3.new(40, -1.4, 474), 8 },   -- north of the lane: the Row is a walk-in, walk-out loop
		{ "BackTerraceStep", Vector3.new(-104, UP, 298), Vector3.new(-108, UP + 2, 298), 8 },
	}
	for _, fl in ipairs(flights) do
		if D then steps(s, fl[1], fl[2], fl[3], fl[4], STONE, M.stone) else ramp(s, fl[1], fl[2], fl[3], fl[4], 1.0, PAL.stone, SP) end
	end
	slab(s, "ForkLanding", -62, -54, 242, 250, 7, 1.0, D and STONE or PAL.stone, D and M.stone or CONCRETE)
	if D then
		-- low sloped parapets that follow the treads (never a wall: the flights stay enterable from their feet)
		ramp(s, "ForkRail", Vector3.new(-30, 1.2, 242.7), Vector3.new(-54, 8.2, 242.7), 0.6, 1.6, STONEDARK, M.stone)
		ramp(s, "BridgeStepsRail", Vector3.new(47.7, 0.4, 396), Vector3.new(47.7, 9.2, 372), 0.6, 1.6, STONEDARK, M.stone)
		ramp(s, "StubRail", Vector3.new(24, 8.0, 470.2), Vector3.new(40, -0.2, 470.2), 0.6, 1.6, STONEDARK, M.stone)
		ramp(s, "StubRoadRail", Vector3.new(23.5, 9.2, 478), Vector3.new(23.5, 3.2, 490), 0.6, 1.6, STONE, M.stone)
		ramp(s, "PocketRail", Vector3.new(-28, 9.2, 390.3), Vector3.new(-54, 0.4, 390.3), 0.6, 1.6, STONEDARK, M.stone)
	end
	return s
end

-- Roads
function G.Roads()
	local s = section("Roads")
	local D = G.DETAIL
	local rc, rm = D and C3(108, 100, 92) or PAL.road, D and M.stone or CONCRETE
	local pts = { { 0, 38, 20 }, { 2, 70, 14 }, { 12, 110, 16 }, { 10, 150, 12 }, { 4, 190, 16 }, { -10, 226, 18 }, { -12, 250, 24 } }
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local p, q = Vector3.new(a[1], 0.12, a[2]), Vector3.new(b[1], 0.12, b[2])
		local w = (a[3] + b[3]) / 2
		ramp(s, "Street", p, q, w, 0.24, rc, rm)
		cyl(s, "StreetJoint", w, 0.24, at(b[1], 0.12, b[2]), rc, rm)
	end
	slab(s, "GatePath", -10, 10, 17, 40, 0.12, 0.24, rc, rm)
	slab(s, "AlleyA1", 8, 70, 96, 104, 0.12, 0.24, rc, rm)
	slab(s, "AlleyA2", 20, 70, 146, 153, 0.12, 0.24, rc, rm)
	slab(s, "AlleyA3", 40, 70, 304, 311, 0.12, 0.24, rc, rm)
	slab(s, "AlleyA4", -40, -6, 122, 130, 0.12, 0.24, rc, rm)
	slab(s, "LaneL1", 6, 70, 250, 262, 0.12, 0.24, rc, rm)
	slab(s, "Causeway", -70, -4, 372, 385, 8.12, 0.24, D and COBBLE or PAL.road, rm)
	slab(s, "SquareTop", -4, 39, 366, 399, 8.12, 0.24, D and COBBLE or PAL.square, rm)
	slab(s, "StubRoad", 4, 18, 456, 462, 8.12, 0.24, D and COBBLE or PAL.road, rm)
	if D then
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			ramp(s, "Gutter", Vector3.new(a[1], 0.14, a[2]), Vector3.new(b[1], 0.14, b[2]), 1.2, 0.2, C3(84, 78, 72), M.stone)
		end
	end
	return s
end

function G.Barrier()
	local s = section("Barrier")
	local props = { Transparency = 1, CanCollide = true, CastShadow = false }
	box(s, "BarrierWest", 134, 136, -70, 540, -4, 40, PAL.stone, SP, props)
	box(s, "BarrierSouth", -140, 136, -72, -70, -4, 40, PAL.stone, SP, props)
	box(s, "BarrierEastShore", -140, -138, -70, 20, -4, 40, PAL.stone, SP, props)
	return s
end

function G.NpcSpots()
	local s = section("NpcSpots")
	for _, n in ipairs(G.NPC_SPOTS) do
		local pos = W(n.x, n.y + 2, n.z)
		local p = mk(s, "NpcSpot_" .. n.role, Vector3.new(1, 4, 1), CFrame.lookAt(pos, pos + n.dir), PAL.npc, SP, { Transparency = G.DETAIL and 1 or 0.35, CanCollide = false })   -- invisible markers in the detail render; NPC-01 reads the attributes
		p:SetAttribute("Role", n.role)
		p:SetAttribute("Tier", n.tier)
		p:SetAttribute("Note", n.note)
	end
	return s
end

function G.Booths()
	local rc = rootCenter()
	local old = rc:FindFirstChild("Booths")
	if old and old:GetAttribute("TW2") then old:Destroy() end
	local f = folder(rc, "Booths")
	f:SetAttribute("TW2", true)
	for _, sp in ipairs(G.STALLS) do stall(f, sp) end
	return f
end

function G.TradeZone()
	local rc = rootCenter()
	local old = rc:FindFirstChild("TradeZone")
	if old and old:GetAttribute("TW2") then old:Destroy() end
	local z = mk(rc, "TradeZone", Vector3.new(52, 22, 46), at(-18, 6, 255), PAL.water, SP, { Transparency = 1, CanCollide = false, CastShadow = false })
	z:SetAttribute("TW2", true)
	return z
end

-- ============================================================ counter guards (v15, TRADE queue Item 2)
-- One invisible collider over each CounterTop so nobody can stand on a counter. Its own section, NOT inside
-- the Booth models: NpcFocusClient outlines the whole booth model when a StandPrompt shows. The footprint is
-- the CounterTop's (8.5 x 2.9) and never more, so customers stand where they did (a tall avatar's head just can't
-- lean over the top any more, ~0.4 studs); Counter.Position (BoothHandler's BUY_RADIUS centre) and both prompts
-- are untouched, and both prompts skip line of sight.
-- `top` is design studs above the counter's foot (the CounterTop surface is +3.26). An R15 root part rides
-- HipHeight above the feet and the legs don't collide, so a jump clears a ledge at standing height + HipHeight
-- + 7.2 (a 10-stud guard was mounted from the street in the Item 2 play test). Sized for HipHeight up to 3.5 and
-- a sprint (33.8) jump arc from every standable prop or walkway near the stall, + 0.8. Building masses under
-- the non-collidable roofs are left out: rooftop parkour is its own problem. Where a solid balcony, lean-to,
-- landing or arcade floor covers the counter the guard is sealed to its underside instead: no top to stand on.
G.GUARD_TOP = 14                                       -- the street and the 2.2 plinths: 2.2 + 3.5 + 7.2 + 0.8 = 13.7
G.COUNTER_GUARDS = {
	[1] = { top = 16.5 },                              -- the Gateway open post (12 high, 18 studs off); the gate-post cap is boxed in by this guard + the Customs House
	[3] = { top = 8.55 },                              -- sealed under the B4 balcony (underside 8.5)
	[4] = { top = 8.45, x1 = -4.25, x2 = -3.05 },      -- sealed under the B5 landing; the stair's solid treads bury the rest of this counter
	[6] = { top = 15 },                                -- tree trunk 10 high, 18 studs off
	[7] = { top = 22 },                                -- the B5 stair's balusters (9.7) and landing (9.0) in front of it
	[8] = { top = 23.5 },                              -- the stone arch over it is walkable from the piers (crown 11.9)
	[9] = { top = 9.05 },                              -- sealed under the Curio House arcade floor (9.0)
	[10] = { top = 20 },                               -- canopy post tops 8.2
	[11] = { top = 17 },                               -- causeway parapet 5.2, 9 studs off
	[13] = { top = 7.6, split = 0.4, backTop = 20 },   -- front sealed under the lean-to (7.6); behind it, clear of the lean-to roof (8.4)
	[14] = { top = 9.35 },                             -- sealed under the S4 balcony (underside 9.3)
	[15] = { top = 7.6, split = 0.4, backTop = 20 },
	[16] = { top = 18.5 },                             -- lamp post 6.6, 5.5 studs off
	[17] = { top = 18.5 },                             -- lamp post 6.6, 4.5 studs off
	[18] = { top = 23 },                               -- the north stub ramp (9.4) and its parapet (10.6), 8 studs off
}
local GUARD_FOOT = 3.2                                 -- 0.06 into the CounterTop: no seam to catch a foot
function G.CounterGuards()
	local s = section("CounterGuards")
	local props = { Transparency = 1, CanCollide = true, CanTouch = false, CastShadow = false, Locked = true }
	local n = 0
	for _, st in ipairs(G.STALLS) do
		local g = G.COUNTER_GUARDS[st.idx] or {}
		local pos = W(st.x, st.y, st.z)
		local origin = CFrame.lookAt(pos, pos + st.dir)   -- the stall's own frame: local -Z = toward the customer
		local x1, x2 = g.x1 or -4.25, g.x2 or 4.25
		local function guard(name, z1, z2, top)
			local p = mk(s, name, Vector3.new(x2 - x1, top - GUARD_FOOT, z2 - z1),
				origin * CFrame.new((x1 + x2) / 2, (GUARD_FOOT + top) / 2, (z1 + z2) / 2), PAL.npc, SP, props)
			p:SetAttribute("BoothIndex", st.idx)
			n += 1
		end
		if g.split then
			guard("CounterGuard" .. st.idx, -1.45, g.split, g.top)
			guard("CounterGuard" .. st.idx .. "Back", g.split, 1.45, g.backTop)
		else
			guard("CounterGuard" .. st.idx, -1.45, 1.45, g.top or G.GUARD_TOP)
		end
	end
	return string.format("%d counter guards over %d stalls", n, #G.STALLS)
end

function G.PlacePortal()
	local portals = gameWorld():FindFirstChild("Portals")
	local hub = portals and portals:FindFirstChild("HubPortal")
	local touch = hub and hub:FindFirstChild("PortalTouch", true)
	if not (hub and touch) then return "HubPortal/PortalTouch not found" end
	if not hub:GetAttribute("TW2_OriginalPivot") then hub:SetAttribute("TW2_OriginalPivot", hub:GetPivot()) end
	local pos = W(0, 0.4 + 5.6, -21.0)
	local target = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))   -- inside the gateway chamber, thin axis across the arch
	local rel = touch.CFrame:ToObjectSpace(hub:GetPivot())
	hub:PivotTo(target * rel)
	return string.format("HubPortal pivoted; PortalTouch at (%.1f, %.1f, %.1f)", touch.Position.X, touch.Position.Y, touch.Position.Z)
end

function G.RetargetSkip()
	local rw = rootWorld()
	local es = rw:FindFirstChild("EternalSkip")
	local loop = es and es:FindFirstChild("SkipLoop")
	if not loop then return "EternalSkip/SkipLoop not under TradingWorld" end
	local src = loop.Source
	local new = src:gsub("local CX, CZ, R = 8000, 8000, 68", "local CX, CZ, R = 8150, 7878, 40", 1)
	new = new:gsub("local WATER_Y = 2002%.0", "local WATER_Y = 2000.0", 1)
	if new ~= src then loop.Source = new end
	for _, n in ipairs({ "Stone", "Ring1", "Ring2", "Ring3" }) do
		local p = es:FindFirstChild(n)
		if p and p:IsA("BasePart") then p.CFrame = CFrame.new(8190, 2000.4, 7878) end
	end
	return (new ~= src) and "SkipLoop retargeted (CX 8150, CZ 7878, R 40, WATER_Y 2000)" or "SkipLoop already retargeted"
end

-- Gateway: the Old Riverside Market Gateway at the south end of the dock -- the way home, built as if it had
-- stood there for generations. The functional portal (Portals.HubPortal.PortalTouch) is only re-pivoted
-- into its chamber; its legacy neon decor is moved to the backup folder by RetirePortalDecor().
local DARKTIMBER = C3(70, 50, 32)
function G.Gateway()
	local s = section("Gateway")
	local D = G.DETAIL
	box(s, "GateBase", -17, 17, -26, -12, -6, 0.4, D and COBBLE or PAL.stone, D and M.stone or CONCRETE)
	if not D then
		box(s, "GateMass", -12, 12, -20, -15, 0.4, 22, PAL.stone, CONCRETE)
		return s
	end
	local r = rng(hashName("gateway"))
	-- the landing: copings on the water edges, a worn threshold where the planks stop
	box(s, "BaseCoping", -17.4, 17.4, -26.4, -25.6, 0.4, 0.95, LIME, M.stone2)
	box(s, "BaseCoping", -17.4, -16.6, -26.4, -12, 0.4, 0.95, LIME, M.stone2)
	box(s, "BaseCoping", 16.6, 17.4, -26.4, -12, 0.4, 0.95, LIME, M.stone2)
	box(s, "Threshold", -14, 14, -12.6, -11.4, 0.4, 0.62, LIME, M.stone2)
	box(s, "WornFlag", -3.2, 2.6, -14.8, -12.8, 0.4, 0.52, C3(112, 104, 92), M.stone)
	-- piers: the west one heavier with a buttress (nobody built this symmetrical)
	box(s, "PierE", -11, -7, -20, -15, 0.4, 12.5, STONE, M.stone)
	box(s, "PierW", 7, 12, -20, -15, 0.4, 12.5, STONE, M.stone)
	box(s, "PierCap", -11.4, -6.6, -20.4, -14.6, 12.5, 13.2, LIME, M.stone2)
	box(s, "PierCap", 6.6, 12.4, -20.4, -14.6, 12.5, 13.2, LIME, M.stone2)
	box(s, "Buttress", 12, 14.6, -20, -15, 0.4, 7.5, STONEDARK, M.stone)
	ramp(s, "ButtressTop", Vector3.new(12, 9.2, -17.5), Vector3.new(14.8, 7.5, -17.5), 5.2, 0.8, LIME, M.stone2)
	quoins(s, faceOf({ x1 = -11, x2 = -7, z1 = -20, z2 = -15 }, "N"), 0.4, 12, r)
	quoins(s, faceOf({ x1 = 7, x2 = 12, z1 = -20, z2 = -15 }, "N"), 0.4, 12, r)
	box(s, "Patch", -10.2, -8.1, -14.95, -14.75, 4.2, 5.6, LIME, M.stone2)
	box(s, "Patch", 8.4, 9.6, -14.95, -14.75, 7.8, 8.7, LIME, M.stone2)
	-- two-ring masonry arch with a keystone, spandrel wall, string course, and the carved tablet
	arch(s, "ArchOuter", at(0, 12.5, -17.5), 7.6, 11, 1.7, 4.4, LIME, M.stone2)
	arch(s, "ArchInner", at(0, 12.5, -18.0), 6.1, 9, 1.4, 2.8, STONEDARK, M.stone)
	box(s, "Keystone", -1.0, 1.0, -19.9, -15.1, 19.2, 21.6, LIME, M.stone2)
	box(s, "Spandrel", -12, -6.4, -18.8, -15.8, 12.5, 22.0, STONE, M.stone)
	box(s, "Spandrel", 6.4, 12, -18.8, -15.8, 12.5, 22.0, STONE, M.stone)
	box(s, "Spandrel", -6.4, 6.4, -18.8, -15.8, 19.4, 22.0, STONE, M.stone)
	box(s, "StringCourse", -12.6, 12.6, -19.2, -15.4, 22.0, 22.6, LIME, M.stone2)
	box(s, "TabletBand", -12.4, 12.4, -19.0, -15.6, 22.6, 25.6, STONE, M.stone)
	box(s, "TabletRim", -5.5, 5.5, -15.6, -15.15, 22.7, 25.5, C3(150, 140, 120), M.stone2)
	local tablet = box(s, "GateTablet", -5.0, 5.0, -15.6, -14.95, 23.0, 25.2, LIME, M.stone2)
	plate(tablet, "TRADING WORLD", Enum.NormalId.Back, C3(66, 56, 44), LIME, 1, Enum.Font.Antique, 40)
	-- heavy timber tie beam across the front at the spring line, strapped and bolted
	box(s, "TieBeam", -12.4, 12.4, -15.85, -14.9, 12.7, 13.7, DARKTIMBER, M.wood)
	for _, x in ipairs({ -9.6, -0.4, 9.2 }) do
		box(s, "Strap", x - 0.5, x + 0.5, -14.95, -14.8, 12.55, 13.85, IRON, M.metal)
		for _, dy in ipairs({ -0.35, 0.35 }) do
			cyl(s, "Bolt", 0.3, 0.16, at(x, 13.2 + dy, -14.78) * CFrame.Angles(0, math.rad(90), 0), IRON, M.metal)
		end
	end
	-- timber canopy: slate hood on dark beams, barge boards both ends, joist ends under the north eave, knee braces
	gable(s, "Gate", -13.5, 13.5, -20, -15, 25.6, 4.4, false, ROOFS[7][1], ROOFS[7][2], 1.7)
	box(s, "GateRidge", -15.6, 15.6, -17.9, -17.1, 29.8, 30.5, DARKTIMBER, M.wood)
	box(s, "EaveBeam", -15.2, 15.2, -21.9, -21.1, 24.7, 25.6, DARKTIMBER, M.wood)
	box(s, "EaveBeam", -15.2, 15.2, -13.9, -13.1, 24.7, 25.6, DARKTIMBER, M.wood)
	bargeBoards(s, "Gate", -13.5, 13.5, -20, -15, 25.6, 4.4, false, 1.7, true)
	bargeBoards(s, "Gate", -13.5, 13.5, -20, -15, 25.6, 4.4, false, 1.7, false)
	for _, x in ipairs({ -11.2, -6.5, -2.4, 1.8, 6.0, 10.6 }) do box(s, "BeamEnd", x - 0.3, x + 0.3, -14.4, -12.9, 24.6, 25.2, DARKTIMBER, M.wood) end
	for _, x in ipairs({ -10.2, 10.4 }) do
		mk(s, "KneeBrace", Vector3.new(0.7, 3.4, 0.7), at(x, 23.2, -14.6) * CFrame.Angles(math.rad(-40), 0, 0), DARKTIMBER, M.wood)
	end
	mk(s, "OuterBrace", Vector3.new(0.8, 6.6, 0.8), at(13.4, 10.2, -15.0) * CFrame.Angles(0, 0, math.rad(-24)), DARKTIMBER, M.wood)
	mk(s, "BraceStrap", Vector3.new(1.0, 0.5, 1.0), at(12.4, 12.9, -15.0), IRON, M.metal)
	for _, x in ipairs({ -9, 9.5 }) do
		box(s, "LanternArm", x - 0.15, x + 0.15, -15.2, -13.2, 9.1, 9.4, IRON, M.metal)
		mk(s, "LanternArmBrace", Vector3.new(0.22, 1.6, 0.22), at(x, 8.5, -14.0) * CFrame.Angles(math.rad(-45), 0, 0), IRON, M.metal)
	end
	-- the chamber behind the arch: stone walls, back wall, ceiling at the spring line, worn flags
	box(s, "ChamberWallE", -12, -9, -26, -20, 0.4, 20.6, STONE, M.stone)
	box(s, "ChamberWallW", 9, 12, -26, -20, 0.4, 20.6, STONE, M.stone)
	box(s, "ChamberBack", -12, 12, -26, -24.6, 0.4, 21.6, STONEDARK, M.stone)
	box(s, "ChamberRoof", -12, 12, -24.6, -18.8, 19.6, 20.6, STONEDARK, M.stone)
	box(s, "ChamberFloor", -9, 9, -24.6, -20, 0.4, 0.55, C3(70, 66, 62), M.stone)
	-- the supernatural part, contained by the old stone: depth, a glass sheen, a faint veil, slow motes, thin mist, one cool light
	mk(s, "PortalDepth", Vector3.new(14.0, 19.0, 0.4), at(0, 10.0, -23.6), C3(14, 18, 34), M.sp, { CanCollide = false })
	mk(s, "PortalSheen", Vector3.new(13.4, 18.6, 0.24), at(0, 9.9, -22.4), C3(36, 58, 92), M.glass, { Transparency = 0.5, Reflectance = 0.06, CanCollide = false })
	local veil = mk(s, "PortalVeil", Vector3.new(12.6, 18.0, 0.12), at(0, 9.8, -21.6), C3(110, 150, 196), M.sp, { Transparency = 0.9, CanCollide = false })
	local motes = mk(s, "PortalMotes", Vector3.new(10.4, 0.4, 2.0), at(0, 1.0, -22.2), C3(0, 0, 0), M.sp, { Transparency = 1, CanCollide = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Motes"
	pe.Rate = 5
	pe.Lifetime = NumberRange.new(3, 5)
	pe.Speed = NumberRange.new(0.4, 0.9)
	pe.SpreadAngle = Vector2.new(20, 20)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.7, 0.75), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(C3(196, 214, 240))
	pe.LightEmission = 0.35
	pe.RotSpeed = NumberRange.new(-20, 20)
	pe.Parent = motes
	local mist = pe:Clone()
	mist.Name = "Mist"
	mist.Rate = 1.5
	mist.Lifetime = NumberRange.new(5, 7)
	mist.Speed = NumberRange.new(0.15, 0.3)
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.8), NumberSequenceKeypoint.new(1, 5.5) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.93), NumberSequenceKeypoint.new(1, 1) })
	mist.Color = ColorSequence.new(C3(150, 165, 190))
	mist.LightEmission = 0
	mist.Parent = motes
	local pl = Instance.new("PointLight")
	pl.Color = C3(150, 178, 220)
	pl.Brightness = 0.75
	pl.Range = 15
	pl.Shadows = false
	pl.Parent = veil
	return s
end

-- ONCE: the legacy neon arch, pillars, swirl and label leave the portal model (to the backup folder); only PortalTouch stays
function G.RetirePortalDecor()
	local portals = gameWorld():FindFirstChild("Portals")
	local hub = portals and portals:FindFirstChild("HubPortal")
	if not hub then return "no HubPortal" end
	local bk = ServerStorage:FindFirstChild(G.BACKUP) or folder(ServerStorage, G.BACKUP)
	local store = bk:FindFirstChild("HubPortal_LegacyDecor") or folder(bk, "HubPortal_LegacyDecor")
	local moved = 0
	for _, ch in ipairs(hub:GetChildren()) do
		if ch.Name ~= "PortalTouch" then ch.Parent = store; moved += 1 end
	end
	return string.format("HubPortal legacy decor: %d moved this call, %d stored", moved, #store:GetChildren())
end

-- Dressing (Phase 5b): kerbs, drains, dock ironwork, three trade signs, and a few things people left where they used them
local function specOf(district, name)
	for _, b in ipairs(G.BUILDINGS[district]) do if b.name == name then return b end end
end
function G.Dressing()
	local s = section("Dressing")
	if not G.DETAIL then return s end
	local r = rng(hashName("dressing"))
	-- limestone kerbs along both edges of the Lower Market street
	local pts = { { 0, 38, 20 }, { 2, 70, 14 }, { 12, 110, 16 }, { 10, 150, 12 }, { 4, 190, 16 }, { -10, 226, 18 }, { -12, 250, 24 } }
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		local nx, nz = -dz / len, dx / len
		local w = (a[3] + b[3]) / 2
		for _, sgn in ipairs({ -1, 1 }) do
			local off = sgn * (w / 2 + 0.3)
			ramp(s, "Kerb", Vector3.new(a[1] + nx * off, 0.32, a[2] + nz * off), Vector3.new(b[1] + nx * off, 0.32, b[2] + nz * off), 0.6, 0.36, LIME, M.stone2)
		end
	end
	-- drains where the street bends, and one on the quay
	for _, p in ipairs({ { 2, 70 }, { 10, 150 }, { -12, 250 } }) do
		box(s, "Drain", p[1] - 0.8, p[1] + 0.8, p[2] - 0.8, p[2] + 0.8, 0.12, 0.26, C3(48, 46, 44), M.metal)
	end
	box(s, "Scupper", 90.2, 92, 96, 97.2, -1.4, -0.9, C3(40, 38, 36), M.metal)
	-- dock ironwork: cleats, mooring rings, a coiled line
	for _, p in ipairs({ { -12, 2 }, { 12, 10 }, { 36, 6 }, { 100, 120 } }) do
		box(s, "Cleat", p[1] - 0.6, p[1] + 0.6, p[2] - 0.22, p[2] + 0.22, (p[1] > 90) and -0.6 or 0.4, ((p[1] > 90) and -0.6 or 0.4) + 0.42, IRON, M.metal)
	end
	for _, z in ipairs({ 60, 172 }) do
		local ring = mk(s, "MooringRing", Vector3.new(0.14, 1.0, 1.0), at(92.05, -1.6, z), IRON, M.metal, { CanCollide = false })
		ring.Shape = Enum.PartType.Cylinder
	end
	cyl(s, "RopeCoil", 2.2, 0.5, at(-8, 0.65, 8), ROPE, M.cloth)
	-- crates under a tarp by the hoist warehouse; an upturned boat on the boardwalk; a fish rack on the pier
	for _, c in ipairs({ { 75, 344, 0 }, { 77.4, 346.6, 14 }, { 75.6, 346.2, 2.1 } }) do
		mk(s, "Crate", Vector3.new(2.2, 2.0, 2.2), at(c[1], -0.8 + 1.0 + (c[3] > 2 and 2.0 or 0), c[2]) * CFrame.Angles(0, math.rad(c[3] > 2 and 0 or c[3]), 0), PLANK, M.plank)
	end
	mk(s, "Tarp", Vector3.new(5.6, 0.25, 5.2), at(76.2, -0.8 + 3.3, 345.4) * CFrame.Angles(math.rad(6), math.rad(-8), math.rad(-9)), CLOTHS[5], M.cloth, { CanCollide = false })
	mk(s, "BoatHullUp", Vector3.new(5.8, 1.5, 3.0), at(30, 0.95, 20.4) * CFrame.Angles(0, math.rad(-6), 0), C3(96, 70, 46), M.plank)
	mk(s, "Keel", Vector3.new(5.4, 0.3, 0.4), at(30, 1.85, 20.4) * CFrame.Angles(0, math.rad(-6), 0), TIMBER, M.wood, { CanCollide = false })
	for _, x in ipairs({ 100, 108 }) do box(s, "RackPost", x - 0.25, x + 0.25, 116.6, 117.1, -0.6, 4.4, TIMBER2, M.wood, { CanCollide = false }) end
	rod(s, "RackRail", Vector3.new(100, 4.2, 116.85), Vector3.new(108, 4.2, 116.85), 0.22, TIMBER, M.wood)
	for _, x in ipairs({ 101.6, 104.1, 106.4 }) do
		mk(s, "DryingFish", Vector3.new(0.35, 1.5, 0.7), at(x, 3.35, 116.85) * CFrame.Angles(0, 0, math.rad((r() - 0.5) * 16)), C3(176, 168, 150), M.sp, { CanCollide = false })
	end
	-- a hand cart in the yard, a wheel left against the courtyard wall, barrels by the broker
	box(s, "CartBed", 11.5, 16.5, 319, 322.4, 1.6, 2.0, PLANKDARK, M.plank)
	for _, x in ipairs({ 11.2, 16.8 }) do mk(s, "CartWheel", Vector3.new(0.3, 2.4, 2.4), at(x, 1.2, 320.7), TIMBER, M.wood, { CanCollide = false }).Shape = Enum.PartType.Cylinder end
	for _, x in ipairs({ 12.2, 15.8 }) do mk(s, "CartHandle", Vector3.new(0.3, 0.3, 3.6), at(x, 1.2, 324.6) * CFrame.Angles(math.rad(22), 0, 0), TIMBER, M.wood, { CanCollide = false }) end
	mk(s, "LeaningWheel", Vector3.new(0.3, 2.6, 2.6), at(-78.6, 1.3, 140) * CFrame.Angles(0, 0, math.rad(12)), TIMBER, M.wood, { CanCollide = false }).Shape = Enum.PartType.Cylinder
	cyl(s, "Barrel", 2.2, 2.6, at(-19.5, 1.3, 210.6), C3(100, 74, 48), M.plank)
	cyl(s, "Barrel", 2.0, 2.4, at(-17.4, 1.2, 208.8), C3(112, 84, 54), M.plank)
	-- a bench facing the well, a notice board by the gate, a bucket and rod at the fishing pocket
	box(s, "Bench", -26.6, -21.4, 253, 254.4, 1.3, 1.75, PLANKDARK, M.plank)
	box(s, "BenchLeg", -26.2, -25.4, 253.2, 254.2, 0, 1.3, TIMBER, M.wood)
	box(s, "BenchLeg", -22.6, -21.8, 253.2, 254.2, 0, 1.3, TIMBER, M.wood)
	for _, x in ipairs({ -13.6, -9.8 }) do box(s, "BoardPost", x - 0.25, x + 0.25, 30, 30.5, 0, 6.2, TIMBER, M.wood, { CanCollide = false }) end
	box(s, "NoticeBoard", -14.2, -9.2, 30.05, 30.45, 2.6, 5.8, PLANKDARK, M.plank, { CanCollide = false })
	box(s, "Notice", -13.4, -12.1, 30.44, 30.5, 3.4, 5.2, C3(222, 214, 190), M.sp, { CanCollide = false })
	mk(s, "Notice", Vector3.new(1.1, 1.5, 0.06), at(-10.6, 4.1, 30.47) * CFrame.Angles(0, 0, math.rad(7)), C3(214, 204, 176), M.sp, { CanCollide = false })
	cyl(s, "Bucket", 1.4, 1.3, at(-60, -0.15, 396), IRON, M.metal)
	mk(s, "FishingRod", Vector3.new(0.12, 7.0, 0.12), at(-63, 2.2, 397.6) * CFrame.Angles(math.rad(-30), 0, math.rad(15)), TIMBER2, M.wood, { CanCollide = false })
	-- trade signs: the broker, the curio house, the boat shed; a carved tablet on the guild house
	local kiosk, curio, shed, guild = specOf("LowerMarket", "BrokerKiosk"), specOf("UpperMarket", "CurioHouse"), specOf("Waterfront", "S1"), specOf("LowerMarket", "GuildHouse")
	tradeSign(s, "SignBroker", "BROKER", faceOf(kiosk, "W"), 0, 5, 6.2)
	tradeSign(s, "SignCurios", "CURIOS", faceOf(curio, "W", curio.upper), UP, 12, 11.2)
	tradeSign(s, "SignBoats", "BOATS", faceOf(shed, "W"), 0, 14, 9.6)
	local gf = faceOf(guild, "S", guild.upper)
	faceBox(s, "GuildTabletRim", gf, 0, 24, 15.6, 0.3, 8.4, 2.8, 0.5, C3(150, 140, 120), M.stone2, nil, nil, { CanCollide = false })
	local gt = faceBox(s, "GuildTablet", gf, 0, 24, 15.6, 0.45, 7.8, 2.2, 0.5, LIME, M.stone2, nil, nil, { CanCollide = false })
	plate(gt, "GUILD HOUSE", Enum.NormalId.Front, C3(66, 56, 44), LIME, 1, Enum.Font.Antique, 40)
	return s
end

-- Lanterns (Phase 6): warm pools where people stand, trade, and cross water. One PointLight each, no shadows,
-- range 14-18; the gateway portal and the tower beacon are the only lights that are not warm iron lanterns.
G.LANTERNS = {
	-- gateway piers (hanging from the iron arms) and the dock corners (posts)
	{ x = -9, y = 8.4, z = -13.5, kind = "hang", away = Vector3.new(0, 0, 1), arm = 0.6 },
	{ x = 9.5, y = 8.4, z = -13.5, kind = "hang", away = Vector3.new(0, 0, 1), arm = 0.6 },
	{ x = -13, y = 7.6, z = 15, kind = "post" },
	{ x = 13, y = 7.6, z = 16, kind = "post" },
	-- entrance and the Lower Market: over the stalls and at the corners people turn
	{ x = 8.4, y = 9.6, z = 60, kind = "hang", away = Vector3.new(-1, 0, 0) },
	{ x = -8.4, y = 9.0, z = 48, kind = "hang", away = Vector3.new(1, 0, 0) },
	{ x = 6.6, y = 10.3, z = 90, kind = "hang", away = Vector3.new(-1, 0, 0) },
	{ x = 18.6, y = 9.4, z = 128, kind = "hang", away = Vector3.new(-1, 0, 0) },
	{ x = 10.6, y = 7.7, z = 176, kind = "hook" },
	{ x = 4, y = 7.4, z = 222, kind = "hook" },
	{ x = -6.6, y = 10.4, z = 84, kind = "hang", away = Vector3.new(1, 0, 0) },
	{ x = -4.4, y = 10.4, z = 118, kind = "hang", away = Vector3.new(1, 0, 0) },
	{ x = -2.4, y = 10.4, z = 198, kind = "hang", away = Vector3.new(1, 0, 0) },
	{ x = -52, y = 10.0, z = 158.4, kind = "hang", away = Vector3.new(0, 0, -1) },
	{ x = -20.6, y = 7.2, z = 221, kind = "hang", away = Vector3.new(1, 0, 0) },
	{ x = -4, y = 7.6, z = 240, kind = "post" },
	{ x = -30, y = 8.0, z = 268, kind = "hook" },
	{ x = 46, y = 10.2, z = 256, kind = "hook" },
	-- waterfront
	{ x = 68.6, y = 10.6, z = 50, kind = "hook" },
	{ x = 72.2, y = 6.1, z = 134, kind = "hook" },
	{ x = 72, y = 7.7, z = 176, kind = "hook" },
	{ x = 71.4, y = 10.2, z = 292, kind = "hang", away = Vector3.new(1, 0, 0) },
	{ x = 74, y = 14.5, z = 339, kind = "hook" },
	-- upper market and the causeway
	{ x = -68.4, y = 21.4, z = 288, kind = "hang", away = Vector3.new(1, 0, 0) },
	{ x = -116, y = 21.4, z = 300, kind = "hook" },
	{ x = -48.5, y = 19.6, z = 326, kind = "post" },
	{ x = -45, y = 18.0, z = 372.2, kind = "hang", away = Vector3.new(0, 0, 1) },
	-- bridge: the iron posts get their heads; the cupola gets the beacon; the passage a hook
	{ x = 4.6, y = 15.3, z = 403, kind = "bare" },
	{ x = 17.4, y = 15.3, z = 438, kind = "bare" },
	{ x = 4.6, y = 15.3, z = 438, kind = "bare" },
	{ x = 11, y = 18.0, z = 448, kind = "hook" },
	{ x = 11, y = 66.6, z = 448, kind = "bare", range = 34, brightness = 1.3 },
	-- collector's row and the fishing pocket
	{ x = -9.5, y = 6.2, z = 470.4, kind = "hang", away = Vector3.new(0, 0, -1) },
	{ x = 18, y = 5.2, z = 468, kind = "hook" },
	{ x = -66, y = 6.6, z = 396, kind = "post", post = 5.5 },
}
function G.Lanterns()
	local s = section("Lanterns")
	if not G.DETAIL then return s end
	for i, l in ipairs(G.LANTERNS) do
		local pos = W(l.x, l.y, l.z)
		local cf = l.away and CFrame.lookAt(pos, pos + l.away) or CFrame.new(pos)
		local kind = l.kind
		local m = lantern(s, "Lantern" .. i, cf, (kind == "hook" or kind == "bare") and "bare" or kind, { arm = l.arm, range = l.range, brightness = l.brightness, post = l.post })
		if kind == "hook" then mk(m, "LanternHook", Vector3.new(0.14, 0.7, 0.14), cf * CFrame.new(0, 1.1, 0), IRON, M.metal, { CanCollide = false }) end
	end
	return s
end

-- A private colour grade for the trading world (Tundra pattern): disabled at rest, faded in by
-- StarterPlayerScripts.TradingAtmosphere while the player is inside the BoundsGuard box. Never touches
-- Lighting globals, ExposureCompensation or the Atmosphere.
function G.TradingGrade()
	local L = game:GetService("Lighting")
	local g = L:FindFirstChild("TradingGrade")
	if not g then
		g = Instance.new("ColorCorrectionEffect")
		g.Name = "TradingGrade"
		g.Parent = L
	end
	g.Enabled = false
	g.Brightness = 0
	g.Contrast = 0
	g.Saturation = 0
	g.TintColor = Color3.new(1, 1, 1)
	return "Lighting.TradingGrade ready (disabled at rest)"
end

-- ============================================================ operations
function G.RetireLegacy()
	local bk = ServerStorage:FindFirstChild(G.BACKUP)
	if not bk then bk = folder(ServerStorage, G.BACKUP) end
	local moved = { world = 0, center = 0 }
	local lw = bk:FindFirstChild("Legacy_TradingWorld") or folder(bk, "Legacy_TradingWorld")
	local lc = bk:FindFirstChild("Legacy_TradingCenter") or folder(bk, "Legacy_TradingCenter")
	for _, ch in ipairs(rootWorld():GetChildren()) do
		if not ch:GetAttribute("TW2") and ch.Name ~= "EternalSkip" then ch.Parent = lw; moved.world += 1 end
	end
	for _, ch in ipairs(rootCenter():GetChildren()) do
		if not ch:GetAttribute("TW2") then ch.Parent = lc; moved.center += 1 end
	end
	return string.format("legacy moved to ServerStorage.%s: %d from TradingWorld, %d from TradingCenter (EternalSkip kept)", G.BACKUP, moved.world, moved.center)
end

function G.ClearAll()
	local n = 0
	for _, r in ipairs({ rootWorld(), rootCenter() }) do
		for _, ch in ipairs(r:GetChildren()) do
			if ch:GetAttribute("TW2") then ch:Destroy(); n += 1 end
		end
	end
	counts.parts = 0
	return "cleared " .. n .. " generated sections"
end

local SECTIONS = { "Land", "Cliffs", "ArrivalDock", "Gateway", "MarketEntrance", "LowerMarket", "Waterfront", "UpperMarket", "OldBridge", "CollectorsRow", "Stairs", "Roads", "Barrier", "NpcSpots", "Booths", "CounterGuards", "TradeZone", "Dressing", "Lanterns" }
function G.BuildAll(opts)
	if opts and opts.detail ~= nil then G.DETAIL = opts.detail end
	roofTone = 0
	CHS:SetWaypoint("TW2 settlement: before build")
	local log = { "renderer: " .. (G.DETAIL and "ARCHITECTURE (Phase 5)" or "GREYBOX (Phase 2)") }
	for _, name in ipairs(SECTIONS) do
		local ok, err = pcall(G[name])
		table.insert(log, (ok and "ok   " or "FAIL ") .. name .. (ok and "" or (" -- " .. tostring(err))))
	end
	local ok, msg = pcall(G.RetirePortalDecor); table.insert(log, (ok and "ok   PortalDecor -- " or "FAIL PortalDecor -- ") .. tostring(msg))
	ok, msg = pcall(G.PlacePortal); table.insert(log, (ok and "ok   Portal -- " or "FAIL Portal -- ") .. tostring(msg))
	ok, msg = pcall(G.TradingGrade); table.insert(log, (ok and "ok   Grade -- " or "FAIL Grade -- ") .. tostring(msg))
	ok, msg = pcall(G.RetargetSkip); table.insert(log, (ok and "ok   Skip -- " or "FAIL Skip -- ") .. tostring(msg))
	CHS:SetWaypoint("TW2 settlement: after build")
	return table.concat(log, "\n")
end

-- ============================================================ checks
function G.Contracts()
	local rc = gameWorld():FindFirstChild(G.ROOT_CENTER)
	if not rc then return "no " .. G.ROOT_CENTER end
	local problems, ok, seen = {}, 0, {}
	local bf = rc:FindFirstChild("Booths")
	if not (bf and bf:IsA("Folder")) then table.insert(problems, "Booths folder missing") end
	local zones = 0
	for _, ch in ipairs(rc:GetChildren()) do if ch.Name == "TradeZone" and ch:IsA("BasePart") then zones += 1 end end
	if zones ~= 1 then table.insert(problems, "TradeZone count " .. zones) end
	local maxIdx = 0
	for _, b in ipairs(bf and bf:GetChildren() or {}) do
		local idx = b:GetAttribute("BoothIndex")
		local bad = {}
		if type(idx) ~= "number" then table.insert(bad, "BoothIndex") elseif seen[idx] then table.insert(bad, "duplicate index " .. idx) else seen[idx] = true; maxIdx = math.max(maxIdx, idx) end
		local counter = b:FindFirstChild("Counter")
		if not (counter and counter:IsA("BasePart")) then table.insert(bad, "Counter") end
		local sp = counter and counter:FindFirstChild("StandPrompt")
		if not (sp and sp:IsA("ProximityPrompt")) then table.insert(bad, "StandPrompt") end
		for i = 1, 3 do
			local d = b:FindFirstChild("Display" .. i)
			if not (d and d:IsA("BasePart")) then table.insert(bad, "Display" .. i)
			elseif (d.CFrame.UpVector - Vector3.new(0, 1, 0)).Magnitude > 0.01 then table.insert(bad, "Display" .. i .. " not level") end
		end
		local sign = b:FindFirstChild("SignBoard")
		local gui = sign and sign:FindFirstChildWhichIsA("SurfaceGui")
		local lbl = gui and gui:FindFirstChildOfClass("TextLabel")
		if not (sign and sign:IsA("BasePart") and gui and lbl) then table.insert(bad, "SignBoard/SurfaceGui/TextLabel") end
		if counter then
			local front = counter.CFrame * CFrame.new(0, 2, -4)
			local hit = Workspace:Raycast(front.Position, Vector3.new(0, -8, 0))
			if not hit then table.insert(bad, "no ground in front") end
		end
		if #bad == 0 then ok += 1 else table.insert(problems, b.Name .. ": " .. table.concat(bad, ", ")) end
	end
	local total = bf and #bf:GetChildren() or 0
	for i = 1, maxIdx do if not seen[i] then table.insert(problems, "BoothIndex gap at " .. i) end end
	local tradePos = Vector3.new(8000, 2004.6, 7818)
	local hit = Workspace:Raycast(tradePos, Vector3.new(0, -6, 0))
	if not hit then table.insert(problems, "no ground under TRADE_POS") else table.insert(problems, string.format("(ground under TRADE_POS: %s at y %.1f)", hit.Instance.Name, hit.Position.Y)) end
	local portals = gameWorld():FindFirstChild("Portals")
	local touch = portals and portals:FindFirstChild("HubPortal") and portals.HubPortal:FindFirstChild("PortalTouch", true)
	if touch then
		local d = (Vector3.new(touch.Position.X, 0, touch.Position.Z) - Vector3.new(tradePos.X, 0, tradePos.Z)).Magnitude
		if d < 15 then table.insert(problems, string.format("HubPortal only %.1f studs from TRADE_POS", d)) else table.insert(problems, string.format("(HubPortal %.1f studs from TRADE_POS)", d)) end
	end
	return string.format("OK %d/%d stalls; notes: %s", ok, total, table.concat(problems, "; "))
end

function G.Stats()
	local gw = gameWorld()
	local c = { BasePart = 0, WedgePart = 0, Light = 0, ParticleEmitter = 0, Script = 0, SurfaceGui = 0, BillboardGui = 0, Neon = 0, Model = 0, Total = 0 }
	local minv, maxv = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local bySection = {}
	for _, n in ipairs({ G.ROOT_WORLD, G.ROOT_CENTER }) do
		local m = gw:FindFirstChild(n)
		if m then
			for _, d in ipairs(m:GetDescendants()) do
				c.Total += 1
				if d:IsA("BasePart") then
					c.BasePart += 1
					if d.Material == Enum.Material.Neon then c.Neon += 1 end
					local sec = d
					while sec.Parent and sec.Parent ~= m do sec = sec.Parent end
					bySection[sec.Name] = (bySection[sec.Name] or 0) + 1
					if d.Name ~= "BarrierWest" and d.Name ~= "BarrierSouth" and d.Name ~= "BarrierEastShore" then
						local p, s = d.Position, d.Size
						minv = Vector3.new(math.min(minv.X, p.X - s.X / 2), math.min(minv.Y, p.Y - s.Y / 2), math.min(minv.Z, p.Z - s.Z / 2))
						maxv = Vector3.new(math.max(maxv.X, p.X + s.X / 2), math.max(maxv.Y, p.Y + s.Y / 2), math.max(maxv.Z, p.Z + s.Z / 2))
					end
				end
				if d:IsA("WedgePart") then c.WedgePart += 1 end
				if d:IsA("Light") then c.Light += 1 end
				if d:IsA("ParticleEmitter") then c.ParticleEmitter += 1 end
				if d:IsA("LuaSourceContainer") then c.Script += 1 end
				if d:IsA("SurfaceGui") then c.SurfaceGui += 1 end
				if d:IsA("BillboardGui") then c.BillboardGui += 1 end
				if d:IsA("Model") then c.Model += 1 end
			end
		end
	end
	local parts = {}
	for k, v in pairs(c) do table.insert(parts, k .. "=" .. v) end
	table.sort(parts)
	local secs = {}
	for k, v in pairs(bySection) do table.insert(secs, k .. "=" .. v) end
	table.sort(secs)
	local margin = string.format("bbox X %.0f..%.0f Y %.0f..%.0f Z %.0f..%.0f | BoundsGuard margins W %.0f E %.0f N %.0f S %.0f top %.0f",
		minv.X, maxv.X, minv.Y, maxv.Y, minv.Z, maxv.Z, 8790 - maxv.X, minv.X - 7300, 8725 - maxv.Z, minv.Z - 7375, 2110 - maxv.Y)
	return table.concat(parts, " ") .. "\nparts by section: " .. table.concat(secs, " ") .. "\n" .. margin
end

return G
