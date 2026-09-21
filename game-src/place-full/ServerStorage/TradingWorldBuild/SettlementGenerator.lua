--!nocheck
--[[
TradingWorldBuild.SettlementGenerator -- BUILD-TIME ONLY greybox generator for the Riverside Trading
Settlement (TW-02, Phase 2 blockout). Installed at ServerStorage.TradingWorldBuild.SettlementGenerator.
Nothing in the game requires it. Run from the command bar or the Studio MCP, in Edit mode:

    local G = loadstring(game:GetService("ServerStorage").TradingWorldBuild.SettlementGenerator.Source)()
    G.RetireLegacy()     -- ONCE: moves the old cove island out of GameWorld.TradingWorld / TradingCenter
                         --       into ServerStorage.TradingWorldBackups_2026_09_20.Legacy_* (a move, not a delete)
    G.ClearAll()         -- removes only the sections this generator built (attribute TW2 = true)
    G.BuildAll()         -- every section, each pcall-guarded, in place around TRADE_POS
    print(G.Contracts()) -- booth / zone / index / ground / portal self-check -> "OK 18/18 stalls ..."
    print(G.Stats())     -- part / light / script counts + bounding box vs the BoundsGuard box

IN PLACE. The settlement is generated around the existing arrival point: design origin O = the ground
under TeleportService.TRADE_POS = (8000, 2002.4, 7818). Design axes: x = WEST (world +X, the player's LEFT
on arrival), z = NORTH (world +Z, ahead on arrival), y = height above the Lower Market datum P = 2002.4.
Terrain water surface is y 2000 (design -2.4) everywhere in the BoundsGuard "Trading" box; land is parts.

Levels (walkable tops, design y): DOCK +0.4 . L0 0 (Lower Market) . QUAY -0.8 (Waterfront) .
UP +12 (Upper Market; back terrace +14) . CWY +8 (causeway, bridge deck, abutment square) . ROW -1.4.

Contracts kept exactly (BoothHandler / TradeHandler / TradeClient / TeleportService read these):
GameWorld.TradingCenter (Folder) > Booths (Folder) > Booth<N> (Model, attr BoothIndex 1..N CONTIGUOUS)
> Counter (+ Counter.StandPrompt), Display1/2/3 (level), SignBoard > SurfaceGui > TextLabel;
GameWorld.TradingCenter.TradeZone (ONE BasePart, direct child); GameWorld.TradingWorld (Folder);
walkable ground under TRADE_POS; GameWorld.Portals.HubPortal re-pivoted only (attributes untouched).

GREYBOX RULES (owner brief, Phase 2): primitive materials, no decoration, no lights, no scripts beyond
the kept EternalSkip; the layout must read as streets / water / elevation / bridge -- never as a circle,
plaza or hub from the air.
]]

local G = {}
G.VERSION = 3
G.O = Vector3.new(8000, 2002.4, 7818)          -- design origin (ground under TRADE_POS)
G.ROOT_WORLD = "TradingWorld"
G.ROOT_CENTER = "TradingCenter"
G.BACKUP = "TradingWorldBackups_2026_09_20"
G.STALL_COUNT = 18
local UP = 12                                   -- Upper Market terrace level

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local CHS = game:GetService("ChangeHistoryService")

-- ============================================================ palette (greybox: muted naturals, levels readable)
local C3 = Color3.fromRGB
local PAL = {
	ground = C3(170, 162, 148), road = C3(112, 108, 102), quay = C3(142, 138, 130), square = C3(126, 122, 116),
	wood = C3(124, 90, 58), woodDark = C3(94, 68, 42), plank = C3(140, 104, 66),
	wall = C3(198, 190, 174), wall2 = C3(184, 172, 152), wall3 = C3(208, 202, 188), wall4 = C3(176, 168, 158),
	roof = C3(98, 88, 82), roof2 = C3(114, 98, 86), roof3 = C3(86, 82, 84),
	stone = C3(152, 148, 142), stoneDark = C3(120, 116, 110), bridge = C3(134, 128, 120),
	cliff = C3(86, 82, 80), cliff2 = C3(98, 92, 88), niche = C3(58, 52, 46), sign = C3(238, 228, 200),
	green = C3(96, 132, 72), npc = C3(64, 200, 190), relic = C3(120, 124, 112), water = C3(70, 140, 170),
}
local SP = Enum.Material.SmoothPlastic
local CONCRETE = Enum.Material.Concrete
local WOODP = Enum.Material.WoodPlanks
local SLATE = Enum.Material.Slate

-- ============================================================ frame helpers (design -> world)
local function W(x, y, z) return G.O + Vector3.new(x, y, z) end
local function at(x, y, z) return CFrame.new(W(x, y, z)) end

local counts = { parts = 0 }
local function mk(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
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
-- axis-aligned box from design extents (x1<x2, z1<z2, y1<y2)
local function box(parent, name, x1, x2, z1, z2, y1, y2, color, material, props)
	local size = Vector3.new(x2 - x1, y2 - y1, z2 - z1)
	return mk(parent, name, size, at((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2), color, material, props)
end
-- thin walkable surface with its TOP at yTop
local function slab(parent, name, x1, x2, z1, z2, yTop, thick, color, material, props)
	return box(parent, name, x1, x2, z1, z2, yTop - thick, yTop, color, material, props)
end
-- tilted slab whose TOP runs from design point a to design point b (Vector3 x,y,z), width w across
local function ramp(parent, name, a, b, w, thick, color, material)
	thick = thick or 1.0
	local mid = (a + b) / 2
	local len = (b - a).Magnitude + 0.3
	local cf = CFrame.lookAt(W(mid.X, mid.Y, mid.Z), W(b.X, b.Y, b.Z)) * CFrame.new(0, -thick / 2, 0)
	return mk(parent, name, Vector3.new(w, thick, len), cf, color or PAL.stone, material or SP)
end
-- vertical cylinder (Roblox cylinders point along local X)
local function cyl(parent, name, diameter, height, cf, color, material, props)
	local p = mk(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
	p.Shape = Enum.PartType.Cylinder
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
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = bgColor or PAL.sign
	label.BackgroundTransparency = bgTransparency == nil and 1 or bgTransparency
	label.BorderSizePixel = 0
	label.Font = font or Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = textColor or PAL.niche
	label.TextScaled = true
	label.TextStrokeTransparency = 1
	label.Parent = gui
	return gui, label
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

-- ============================================================ building kit
-- spec: { name, x1, x2, z1, z2, h, base=0, roof="gableX"|"gableZ"|"hip"|"flat"|"shed", rise, tone, shedHigh="N"|"S"|"E"|"W",
--         open="W"|"E"|"N"|"S" (open-front shed: 3 thin walls), upper={x1,x2,z1,z2,y1,y2} (an overhanging upper floor, y rel. base),
--         balcony={x1,x2,z1,z2,y,posts={{x,z},...}} }
local ROOF_TONES = { PAL.roof, PAL.roof2, PAL.roof3 }
local roofTone = 0
local function roofColor() roofTone += 1; return ROOF_TONES[(roofTone - 1) % #ROOF_TONES + 1] end
local function gable(parent, name, x1, x2, z1, z2, top, rise, alongZ, color)
	color = color or roofColor()
	if alongZ then
		-- ridge parallel to Z; slope across X
		local span = x2 - x1
		local half = span / 2
		local th = math.atan(rise, half)
		local len = math.sqrt(half * half + rise * rise) + 0.5
		local zc, depth = (z1 + z2) / 2, (z2 - z1) + 1.2
		mk(parent, name .. "RoofA", Vector3.new(len, 0.6, depth), at(x1 + half / 2, top + rise / 2, zc) * CFrame.Angles(0, 0, th), color, SP)
		mk(parent, name .. "RoofB", Vector3.new(len, 0.6, depth), at(x2 - half / 2, top + rise / 2, zc) * CFrame.Angles(0, 0, -th), color, SP)
	else
		-- ridge parallel to X; slope across Z
		local span = z2 - z1
		local half = span / 2
		local th = math.atan(rise, half)
		local len = math.sqrt(half * half + rise * rise) + 0.5
		local xc, width = (x1 + x2) / 2, (x2 - x1) + 1.2
		mk(parent, name .. "RoofA", Vector3.new(width, 0.6, len), at(xc, top + rise / 2, z1 + half / 2) * CFrame.Angles(-th, 0, 0), color, SP)
		mk(parent, name .. "RoofB", Vector3.new(width, 0.6, len), at(xc, top + rise / 2, z2 - half / 2) * CFrame.Angles(th, 0, 0), color, SP)
	end
end
local function building(parent, s)
	local base = s.base or 0
	local bodyTop = base + s.h
	local top = bodyTop
	if s.upper then top = math.max(top, base + s.upper.y2) end
	local tone = s.tone or PAL.wall
	local m = model(parent, s.name)
	if s.open then
		-- open-front shed: three thin walls + the roof
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
	if roof == "gableZ" then
		gable(m, s.name, rx1, rx2, rz1, rz2, top, rise, true, s.roofColor)
	elseif roof == "gableX" then
		gable(m, s.name, rx1, rx2, rz1, rz2, top, rise, false, s.roofColor)
	elseif roof == "hip" then
		local c = s.roofColor or roofColor()
		box(m, s.name .. "Hip1", rx1 + 0.8, rx2 - 0.8, rz1 + 0.8, rz2 - 0.8, top, top + rise * 0.55, c, SP)
		box(m, s.name .. "Hip2", rx1 + 3.2, rx2 - 3.2, rz1 + 3.2, rz2 - 3.2, top + rise * 0.55, top + rise, c, SP)
	elseif roof == "flat" then
		box(m, s.name .. "Parapet", rx1 - 0.3, rx2 + 0.3, rz1 - 0.3, rz2 + 0.3, top, top + 1.2, s.roofColor or PAL.stoneDark, SP)
	elseif roof == "shed" then
		-- one slope, high at the shedHigh side
		local c = s.roofColor or roofColor()
		local hi = s.shedHigh or "E"
		local r = math.min(rise, 5)
		if hi == "E" or hi == "W" then
			local span = rx2 - rx1
			local th = math.atan(r, span)
			local len = math.sqrt(span * span + r * r) + 0.5
			local sgn = (hi == "W") and 1 or -1  -- W = +x is high
			mk(m, s.name .. "Roof", Vector3.new(len, 0.6, (rz2 - rz1) + 1.2), at((rx1 + rx2) / 2, top + r / 2, (rz1 + rz2) / 2) * CFrame.Angles(0, 0, sgn * th), c, SP)
		else
			local span = rz2 - rz1
			local th = math.atan(r, span)
			local len = math.sqrt(span * span + r * r) + 0.5
			local sgn = (hi == "N") and -1 or 1  -- N = +z is high -> tilt +Z up = negative rotation about X
			mk(m, s.name .. "Roof", Vector3.new((rx2 - rx1) + 1.2, 0.6, len), at((rx1 + rx2) / 2, top + r / 2, (rz1 + rz2) / 2) * CFrame.Angles(sgn * th, 0, 0), c, SP)
		end
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
local function stair(parent, name, a, b, w, color)
	return ramp(parent, name, a, b, w, 1.0, color or PAL.stone, SP)
end

-- ============================================================ stall module (the ONE reusable contract module)
-- spec: { idx, x, z, y (level), dir (unit Vector3 toward the customer), shell, signY, district }
local function stall(parent, s)
	local b = model(parent, "Booth" .. s.idx)
	b:SetAttribute("BoothIndex", s.idx)
	b:SetAttribute("District", s.district or "")
	b:SetAttribute("Shell", s.shell or "counter")
	local pos = W(s.x, s.y, s.z)
	local origin = CFrame.lookAt(pos, pos + s.dir)         -- local -Z = toward the customer / street
	local function L(x, y, z) return origin * CFrame.new(x, y, z) end
	-- backdrop niche flush with the wall behind the counter (reads as an opening in the greybox)
	mk(b, "Niche", Vector3.new(9.6, 8.2, 0.6), L(0, 4.1, 1.6), PAL.niche, SP)
	local counter = mk(b, "Counter", Vector3.new(8, 3, 2.4), L(0, 1.5, 0), PAL.woodDark, WOODP)
	for i, x in ipairs({ -2.6, 0, 2.6 }) do
		mk(b, "Display" .. i, Vector3.new(1.6, 0.4, 1.6), L(x, 3.2, -0.2), PAL.plank, WOODP)
	end
	local signY = s.signY or 7
	local sign = mk(b, "SignBoard", Vector3.new(4.6, 1.5, 0.3), L(0, signY, -0.9), PAL.sign, SP)
	plate(sign, "CLAIM STALL", Enum.NormalId.Front, PAL.niche, PAL.sign, 0, Enum.Font.GothamBold, 40)
	mk(b, "SignBracket", Vector3.new(0.3, 0.3, 2.2), L(0, signY + 0.9, 0.4), PAL.woodDark, WOODP)
	if s.shell == "awning" or s.shell == "dock" then
		mk(b, "Awning", Vector3.new(10, 0.4, 5), L(0, 7.6, -2.0), PAL.wood, WOODP)
		for _, x in ipairs({ -4.6, 4.6 }) do
			mk(b, "AwningPost", Vector3.new(0.5, 7.4, 0.5), L(x, 3.7, -4.2), PAL.woodDark, WOODP)
		end
	elseif s.shell == "window" then
		mk(b, "Lintel", Vector3.new(10.4, 1.4, 1.2), L(0, 8.9, 1.3), PAL.woodDark, WOODP)
		for _, x in ipairs({ -5.0, 5.0 }) do
			mk(b, "Jamb", Vector3.new(0.6, 8.2, 1.2), L(x, 4.1, 1.3), PAL.woodDark, WOODP)
		end
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
	return b
end

-- ============================================================ THE NUMBERS (design frame: x west+, z north+)
local E, Wd, N, S = Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)

G.STALLS = {
	-- Lower Market Street (7)
	{ idx = 1,  x = -8.6,  z = 40,  y = 0,    dir = Wd, shell = "awning",    district = "LowerMarket", note = "Customs House awning, first thing past the gate" },
	{ idx = 2,  x = 6.6,   z = 81,  y = 0,    dir = E,  shell = "window",    district = "LowerMarket", note = "B2 storefront window" },
	{ idx = 3,  x = 10.6,  z = 172, y = 0,    dir = E,  shell = "balcony",   district = "LowerMarket", note = "beneath B4's balcony" },
	{ idx = 4,  x = 4.0,   z = 215, y = 0,    dir = E,  shell = "understair", signY = 5, district = "LowerMarket", note = "under B5's external stair" },
	{ idx = 5,  x = -4.6,  z = 110, y = 0,    dir = Wd, shell = "window",    district = "LowerMarket", note = "B8 storefront window" },
	{ idx = 6,  x = -60,   z = 158.6, y = 0,  dir = S,  shell = "awning",    district = "LowerMarket", note = "courtyard, north side" },
	{ idx = 7,  x = -2.6,  z = 190, y = 0,    dir = Wd, shell = "opening",   district = "LowerMarket", note = "B10 shop opening" },
	-- Upper Market (4)
	{ idx = 8,  x = -68.6, z = 281, y = UP,   dir = Wd, shell = "opening",   district = "UpperMarket", note = "U1 opening on the edge street" },
	{ idx = 9,  x = -73.4, z = 346, y = UP,   dir = Wd, shell = "arcade",    district = "UpperMarket", note = "inside the Curio House arcade" },
	{ idx = 10, x = -118.6, z = 300, y = UP + 2, dir = Wd, shell = "awning", district = "UpperMarket", note = "back terrace, under an awning" },
	{ idx = 11, x = -45,   z = 371.4, y = 8,  dir = N,  shell = "window",    district = "UpperMarket", note = "warehouse upper front on the causeway" },
	-- Waterfront (4)
	{ idx = 12, x = 50,    z = 42,  y = 0.2,  dir = Wd, shell = "dock",      district = "Waterfront", note = "deep inside the open boat shed" },
	{ idx = 13, x = 71.4,  z = 127, y = -0.8, dir = Wd, shell = "dock",      district = "Waterfront", note = "lean-to on the quay" },
	{ idx = 14, x = 71.4,  z = 171, y = -0.8, dir = Wd, shell = "balcony",   district = "Waterfront", note = "beneath S4's balcony over the quay" },
	{ idx = 15, x = 71.4,  z = 284, y = -0.8, dir = Wd, shell = "window",    district = "Waterfront", note = "S6 water-side window" },
	-- Old Bridge (2)
	{ idx = 16, x = 5.4,   z = 413, y = 8,    dir = Wd, shell = "bridge",    district = "OldBridge", note = "east cabin, counter opens onto the deck" },
	{ idx = 17, x = 16.6,  z = 429, y = 8,    dir = E,  shell = "bridge",    district = "OldBridge", note = "west cabin" },
	-- Collector's Row (1)
	{ idx = 18, x = -14,   z = 471.6, y = -1.4, dir = S, shell = "opening",  district = "CollectorsRow", note = "RN2's opening onto the sunken lane" },
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
	{ role = "Collector", tier = 3, x = -36, z = 472.5, y = -1.4, dir = S, note = "RN3's doorway on Collector's Row" },
}

-- ============================================================ sections
-- Land: every walkable slab (bottoms below the water at -6), the Upper terrace, causeway wall, abutments, north bank
function G.Land()
	local s = section("Land")
	box(s, "TownSlab", -112, 70, 24, 386, -6, 0, PAL.ground, CONCRETE)
	box(s, "ShoreApron", -80, 16, 17, 24, -6, 0, PAL.ground, CONCRETE)         -- the shore is only built out in front of the dock
	box(s, "QuayA", 70, 92, 24, 210, -6, -0.8, PAL.quay, CONCRETE)              -- the quay steps in halfway (two builders, two eras)
	box(s, "QuayB", 70, 86, 210, 400, -6, -0.8, PAL.quay, CONCRETE)
	box(s, "QuayCorner", 40, 70, 386, 400, -6, -0.8, PAL.quay, CONCRETE)
	box(s, "RiverQuayE", -72, -4, 386, 400, -6, -0.8, PAL.quay, CONCRETE)      -- the fishing pocket under the causeway
	box(s, "UpperTerraceS", -142, -70, 230, 262, 0, UP, PAL.stone, CONCRETE)
	box(s, "UpperTerraceN", -142, -68, 262, 372, 0, UP, PAL.stone, CONCRETE)
	box(s, "UpperTerraceEdge", -68, -54, 262, 362, 0, UP, PAL.stone, CONCRETE)
	box(s, "UpperTerraceRampBase", -68, -54, 362, 372, 0, 8, PAL.stone, CONCRETE)
	box(s, "BackTerrace", -140, -104, 270, 330, UP, UP + 2, PAL.stoneDark, CONCRETE)
	box(s, "CausewayWall", -70, -4, 372, 386, 0, 8, PAL.bridge, CONCRETE)        -- the raised road to the bridge
	box(s, "AbutmentSquare", -4, 40, 366, 400, -6, 8, PAL.bridge, CONCRETE)      -- south abutment + the Bridge Steps square
	box(s, "StepsLandingPillar", 40, 48, 366, 372, 0, 8, PAL.bridge, CONCRETE)
	box(s, "NorthBankA", -60, 50, 444, 476, -6, -1.4, PAL.ground, CONCRETE)      -- Collector's Row ground (stepped west edge)
	box(s, "NorthBankB", -60, 44, 476, 520, -6, -1.4, PAL.ground, CONCRETE)
	box(s, "NorthAbutment", -4, 26, 438, 456, -6, 8, PAL.bridge, CONCRETE)
	-- Fork Square / courtyard / yard floors (slightly different tone so the walk test reads them)
	slab(s, "ForkSquare", -30, 6, 236, 262, 0.1, 0.3, PAL.square, CONCRETE)
	slab(s, "Courtyard", -80, -40, 118, 160, 0.1, 0.3, PAL.square, CONCRETE)
	slab(s, "TannersYard", -4, 40, 304, 332, 0.1, 0.3, PAL.square, CONCRETE)
	return s
end

-- Cliffs: the world's hard edges (east, gorge, north) as rock masses; a few blocks of varied height each
function G.Cliffs()
	local s = section("Cliffs")
	-- east cliff behind the Lower Market's east block (z 17..230)
	box(s, "EastCliffA", -134, -112, 17, 80, -6, 26, PAL.cliff, SLATE)
	box(s, "EastCliffB", -138, -112, 80, 150, -6, 32, PAL.cliff2, SLATE)
	box(s, "EastCliffC", -132, -112, 150, 230, -6, 28, PAL.cliff, SLATE)
	-- upper-east cliff behind the Upper Market (from the terrace top)
	box(s, "UpperCliffA", -166, -142, 230, 300, -6, 40, PAL.cliff2, SLATE)
	box(s, "UpperCliffB", -170, -142, 300, 372, -6, 46, PAL.cliff, SLATE)
	-- south-east corner: rock coming down to the shore behind the Customs House
	box(s, "ShoreRock", -112, -80, 17, 60, -6, 22, PAL.cliff2, SLATE)
	box(s, "ShoreWall", -80, -46, 17, 20, -6, 4, PAL.stoneDark, CONCRETE)
	-- the gorge: the river comes out of rock to the east; a wall across it closes the view
	box(s, "GorgeS", -112, -72, 372, 400, -6, 30, PAL.cliff, SLATE)
	box(s, "GorgeN", -112, -60, 444, 520, -6, 34, PAL.cliff2, SLATE)
	box(s, "GorgeEnd", -122, -100, 396, 448, -6, 36, PAL.cliff, SLATE)
	-- north cliff closing Collector's Row
	box(s, "NorthCliffA", -60, 0, 520, 544, -6, 34, PAL.cliff, SLATE)
	box(s, "NorthCliffB", 0, 54, 520, 540, -6, 30, PAL.cliff2, SLATE)
	box(s, "NorthCliffC", 50, 58, 444, 476, -6, 6, PAL.cliff2, SLATE)              -- low rock lip on the bank's west edge
	box(s, "NorthCliffD", 44, 52, 476, 520, -6, 8, PAL.cliff2, SLATE)
	return s
end

-- Arrival Dock: the deck under TRADE_POS, a side jetty with a boat, the boathouse that holds the way home
function G.ArrivalDock()
	local s = section("ArrivalDock")
	slab(s, "DockDeck", -14, 14, -22, 18, 0.4, 1.2, PAL.plank, WOODP)
	for _, c in ipairs({ { -13, -21 }, { 13, -21 }, { -13, 0 }, { 13, 6 }, { -13, 16 }, { 13, 17 } }) do
		box(s, "DockPost", c[1] - 0.5, c[1] + 0.5, c[2] - 0.5, c[2] + 0.5, -4, 2.4, PAL.woodDark, WOODP)
	end
	slab(s, "Jetty", 14, 40, 4, 12, 0.4, 1.0, PAL.plank, WOODP)
	box(s, "JettyPost", 38, 39, 3, 4, -4, 2.2, PAL.woodDark, WOODP)
	box(s, "Boat", 20, 26, -8, 6, -1.6, 1.2, PAL.wood, WOODP)                    -- moored rowing boat (blockout mass)
	slab(s, "BoathousePlank", -22, -14, 8, 16, 0.4, 1.0, PAL.plank, WOODP)
	building(s, { name = "Boathouse", x1 = -44, x2 = -20, z1 = 4, z2 = 20, h = 12, roof = "shed", shedHigh = "E", open = "W", tone = PAL.wall4 })
	slab(s, "Boardwalk", 14, 70, 12, 24, 0.2, 1.0, PAL.plank, WOODP)                 -- Route B: west along the bay to the quay
	return s
end

-- Market Entrance: the Harbourmaster and the Customs House pinch the way north; no beam, the gap shows the tower
function G.MarketEntrance()
	local s = section("MarketEntrance")
	building(s, { name = "Harbourmaster", x1 = 10, x2 = 42, z1 = 24, z2 = 62, h = 11, roof = "gableZ", rise = 7, tone = PAL.wall2,
		upper = { x1 = 7, x2 = 42, z1 = 21, z2 = 62, y1 = 11, y2 = 24 }, upperTone = PAL.wall })
	building(s, { name = "CustomsHouse", x1 = -46, x2 = -10, z1 = 22, z2 = 56, h = 18, roof = "hip", rise = 6, tone = PAL.wall3 })
	-- a hanging sign on the Harbourmaster's street face (no gate beam: the bridge tower must stay visible)
	box(s, "GateSign", 4.5, 7, 40, 40.4, 8, 10.4, PAL.sign, SP)
	box(s, "GateSignArm", 4.5, 7.2, 40.1, 40.3, 10.4, 10.7, PAL.woodDark, WOODP)
	return s
end

-- Lower Market Street: the winding main street and its two building rows, the courtyard, the Fork Square, the Guild House
function G.LowerMarket()
	local s = section("LowerMarket")
	-- west row (fronts on the street's west edge, backs on the quay sheds)
	building(s, { name = "B2", x1 = 8, x2 = 40, z1 = 66, z2 = 96, h = 15, roof = "flat", tone = PAL.wall })
	building(s, { name = "B3", x1 = 20, x2 = 54, z1 = 104, z2 = 146, h = 10, roof = "gableX", rise = 8, tone = PAL.wall4,
		upper = { x1 = 20, x2 = 54, z1 = 104, z2 = 153, y1 = 10, y2 = 28 } })             -- upper floors span alley A2
	building(s, { name = "B4", x1 = 12, x2 = 46, z1 = 153, z2 = 190, h = 20, roof = "hip", rise = 7, tone = PAL.wall2,
		balcony = { x1 = 9, x2 = 12.2, z1 = 160, z2 = 184, y = 9, posts = { { 9.5, 161 }, { 9.5, 183 } } } })
	building(s, { name = "B5", x1 = 6, x2 = 40, z1 = 194, z2 = 248, h = 18, roof = "gableZ", rise = 6, tone = PAL.wall3 })
	-- B5's external stair up its street face (stall 4 sits beneath its high half)
	stair(s, "B5Stair", Vector3.new(4, 0, 196), Vector3.new(4, 9, 218), 4, PAL.woodDark)
	slab(s, "B5Landing", 2, 6, 218, 224, 9, 0.8, PAL.woodDark, WOODP)
	building(s, { name = "B12", x1 = 6, x2 = 48, z1 = 264, z2 = 300, h = 18, roof = "gableX", rise = 6, tone = PAL.wall })
	building(s, { name = "B13", x1 = 4, x2 = 40, z1 = 336, z2 = 364, h = 14, roof = "gableZ", rise = 6, tone = PAL.wall4 })
	building(s, { name = "WH2", x1 = -32, x2 = 0, z1 = 334, z2 = 370, h = 16, roof = "flat", tone = PAL.wall2 })
	building(s, { name = "WH1", x1 = -54, x2 = -36, z1 = 336, z2 = 370, h = 18, roof = "gableX", rise = 6, tone = PAL.wall })
	-- east row (fronts on the street's east edge, backs on the cliff / courtyard / terrace wall)
	building(s, { name = "B7", x1 = -44, x2 = -8, z1 = 60, z2 = 92, h = 26, roof = "gableZ", rise = 8, tone = PAL.wall })
	building(s, { name = "B8", x1 = -40, x2 = -6, z1 = 96, z2 = 122, h = 14, roof = "shed", shedHigh = "E", tone = PAL.wall3 })
	building(s, { name = "B9", x1 = -40, x2 = -4, z1 = 130, z2 = 172, h = 22, roof = "gableX", rise = 7, tone = PAL.wall2 })
	building(s, { name = "B10", x1 = -38, x2 = -4, z1 = 176, z2 = 204, h = 18, roof = "hip", rise = 6, tone = PAL.wall4 })
	building(s, { name = "B14", x1 = -70, x2 = -36, z1 = 208, z2 = 232, h = 16, roof = "flat", tone = PAL.wall })
	building(s, { name = "CY_S", x1 = -80, x2 = -46, z1 = 60, z2 = 116, h = 14, roof = "gableZ", rise = 6, tone = PAL.wall4 })
	building(s, { name = "CY_E", x1 = -112, x2 = -80, z1 = 118, z2 = 160, h = 20, roof = "hip", rise = 6, tone = PAL.wall2 })
	building(s, { name = "CY_N", x1 = -80, x2 = -42, z1 = 160, z2 = 204, h = 16, roof = "gableZ", rise = 6, tone = PAL.wall3 })
	building(s, { name = "CY_NN", x1 = -112, x2 = -72, z1 = 206, z2 = 228, h = 18, roof = "gableX", rise = 6, tone = PAL.wall })
	-- the Gem Broker's stone kiosk before the Fork (off the street, against B14's block)
	building(s, { name = "BrokerKiosk", x1 = -30, x2 = -22, z1 = 212, z2 = 222, h = 8, roof = "hip", rise = 3, tone = PAL.stone })
	-- Guild House: closes the Fork Square to the north; open arcade on its south face (covered market corner)
	building(s, { name = "GuildHouse", x1 = -44, x2 = 4, z1 = 276, z2 = 300, h = 22, roof = "gableX", rise = 6, tone = PAL.wall2,
		upper = { x1 = -44, x2 = 4, z1 = 262, z2 = 276, y1 = 9, y2 = 22 } })
	for _, x in ipairs({ -40, -27, -14, 0 }) do
		box(s, "ArcadeColumn", x - 0.9, x + 0.9, 262.5, 264.3, 0, 9, PAL.stone, SP)
	end
	-- Tanners' Yard enclosure (a hidden back yard reached from the quay)
	building(s, { name = "TY_E", x1 = -44, x2 = -4, z1 = 304, z2 = 330, h = 10, roof = "flat", tone = PAL.wall4 })
	box(s, "YardWall", 40, 48, 311, 332, 0, 6, PAL.stoneDark, CONCRETE)
	-- the Fork Square well and the courtyard / yard trees (layout masses, not decoration)
	cyl(s, "Well", 5, 3, at(-14, 1.5, 250), PAL.stoneDark, CONCRETE)
	cyl(s, "CourtyardTree", 2.4, 10, at(-62, 5, 138), PAL.woodDark, WOODP)
	box(s, "CourtyardCanopy", -70, -54, 130, 146, 9, 17, PAL.green, SP)
	cyl(s, "YardTree", 2, 9, at(20, 4.5, 318), PAL.woodDark, WOODP)
	box(s, "YardCanopy", 13, 27, 311, 325, 8, 15, PAL.green, SP)
	return s
end

-- Waterfront: the quay sheds (backs of the west block), the pier, water stairs, the river-mouth corner
function G.Waterfront()
	local s = section("Waterfront")
	building(s, { name = "S1", x1 = 46, x2 = 70, z1 = 28, z2 = 56, h = 12, roof = "shed", shedHigh = "E", open = "W", tone = PAL.wall4 })
	building(s, { name = "S2", x1 = 50, x2 = 70, z1 = 66, z2 = 92, h = 14, roof = "gableX", rise = 5, tone = PAL.wall })
	building(s, { name = "S3", x1 = 54, x2 = 70, z1 = 108, z2 = 146, h = 10, roof = "flat", tone = PAL.wall2 })
	building(s, { name = "S4", x1 = 52, x2 = 70, z1 = 156, z2 = 190, h = 16, roof = "gableZ", rise = 6, tone = PAL.wall3,
		balcony = { x1 = 70, x2 = 73.2, z1 = 162, z2 = 180, y = 9, posts = { { 72.6, 163 }, { 72.6, 179 } } } })
	building(s, { name = "S5", x1 = 44, x2 = 70, z1 = 196, z2 = 234, h = 18, roof = "hip", rise = 6, tone = PAL.wall })
	building(s, { name = "S6", x1 = 48, x2 = 70, z1 = 268, z2 = 300, h = 14, roof = "gableX", rise = 5, tone = PAL.wall4 })
	building(s, { name = "S7", x1 = 44, x2 = 70, z1 = 314, z2 = 364, h = 16, roof = "gableZ", rise = 6, tone = PAL.wall2 })
	box(s, "HoistBeam", 70, 76, 338, 340, 15.5, 16.5, PAL.woodDark, WOODP)
	-- lane L1 arch (the way from the Fork Square down to the quay passes under it)
	box(s, "LaneArchPierS", 44, 48, 248, 250, 0, 9, PAL.stone, CONCRETE)
	box(s, "LaneArchPierN", 44, 48, 262, 264, 0, 9, PAL.stone, CONCRETE)
	box(s, "LaneArchLintel", 44, 48, 248, 264, 9, 11, PAL.stone, CONCRETE)
	-- pier into the bay with a moored boat; second pier at the river-mouth corner
	slab(s, "Pier", 92, 114, 116, 122, -0.6, 1.0, PAL.plank, WOODP)
	box(s, "PierPost", 113, 114, 115, 116, -5, 1.4, PAL.woodDark, WOODP)
	box(s, "PierBoat", 94, 100, 124, 138, -1.6, 1.0, PAL.wood, WOODP)
	slab(s, "MouthPier", 86, 104, 378, 384, -0.6, 1.0, PAL.plank, WOODP)
	-- water stairs (into the bay / river)
	stair(s, "WaterStairA", Vector3.new(88, -0.8, 80), Vector3.new(92, -3, 80), 8)
	stair(s, "WaterStairB", Vector3.new(82, -0.8, 300), Vector3.new(86, -3, 300), 8)
	stair(s, "WaterStairC", Vector3.new(78, -0.8, 392), Vector3.new(86, -3.2, 392), 6)
	return s
end

-- Upper Market: the terrace's edge street, its buildings, the overlook, the back terrace lane
function G.UpperMarket()
	local s = section("UpperMarket")
	building(s, { name = "U6", x1 = -112, x2 = -74, z1 = 234, z2 = 258, h = 18, base = UP, roof = "hip", rise = 6, tone = PAL.wall })
	building(s, { name = "U1", x1 = -100, x2 = -70, z1 = 268, z2 = 294, h = 20, base = UP, roof = "gableX", rise = 7, tone = PAL.wall3 })
	building(s, { name = "U2", x1 = -104, x2 = -70, z1 = 302, z2 = 330, h = 16, base = UP, roof = "hip", rise = 6, tone = PAL.wall2,
		balcony = { x1 = -70, x2 = -66, z1 = 308, z2 = 324, y = 8.5, posts = { { -66.6, 309 }, { -66.6, 323 } } } })
	building(s, { name = "CurioHouse", x1 = -110, x2 = -76, z1 = 334, z2 = 372, h = 26, base = UP, roof = "gableZ", rise = 9, tone = PAL.wall4,
		upper = { x1 = -76, x2 = -70, z1 = 334, z2 = 372, y1 = 9, y2 = 26 } })
	for _, z in ipairs({ 336, 348, 360, 370 }) do
		box(s, "ArcadeColumn", -71.8, -70, z - 0.9, z + 0.9, UP, UP + 9, PAL.stone, SP)
	end
	building(s, { name = "U4", x1 = -140, x2 = -120, z1 = 276, z2 = 322, h = 18, base = UP + 2, roof = "gableX", rise = 6, tone = PAL.wall })
	building(s, { name = "U5", x1 = -140, x2 = -112, z1 = 336, z2 = 362, h = 14, base = UP, roof = "flat", tone = PAL.wall2 })
	-- parapets on the terrace edges (west face over the Lower Market, south face by the stair top)
	box(s, "ParapetW", -55, -54, 266, 306, UP, UP + 1.2, PAL.stoneDark, CONCRETE)
	box(s, "ParapetW2", -55, -54, 330, 362, UP, UP + 1.2, PAL.stoneDark, CONCRETE)
	box(s, "ParapetS", -70, -62, 262, 263, UP, UP + 1.2, PAL.stoneDark, CONCRETE)
	box(s, "ParapetSW", -71, -70, 230, 262, UP, UP + 1.2, PAL.stoneDark, CONCRETE)
	-- the overlook: a cantilevered balcony square on the edge street (view west over the yard to the water)
	slab(s, "Overlook", -54, -46, 306, 330, UP, 1.2, PAL.stone, CONCRETE)
	box(s, "OverlookRail", -47, -46, 306, 330, UP, UP + 1.2, PAL.stoneDark, CONCRETE)
	-- upper street + lane surfaces
	slab(s, "EdgeStreet", -68, -54, 266, 362, UP + 0.12, 0.24, PAL.road, CONCRETE)
	slab(s, "UpperLane", -104, -70, 294, 302, UP + 0.12, 0.24, PAL.road, CONCRETE)
	return s
end

-- Old Bridge: abutment square, deck on a pier, two shop cabins over the water, the gate tower, the closed road north
function G.OldBridge()
	local s = section("OldBridge")
	slab(s, "Deck", 4, 18, 400, 440, 8, 2, PAL.bridge, CONCRETE)
	box(s, "Pier", 3, 19, 416, 424, -6, 6, PAL.stoneDark, CONCRETE)
	box(s, "Cutwater", 3, 19, 424, 428, -6, 4, PAL.stoneDark, CONCRETE)
	-- parapets where there is no cabin
	box(s, "ParapetE1", 4, 5.2, 400, 406, 8, 9.3, PAL.stone, CONCRETE)
	box(s, "ParapetE2", 4, 5.2, 420, 440, 8, 9.3, PAL.stone, CONCRETE)
	box(s, "ParapetW1", 16.8, 18, 400, 422, 8, 9.3, PAL.stone, CONCRETE)
	box(s, "ParapetW2", 16.8, 18, 436, 440, 8, 9.3, PAL.stone, CONCRETE)
	-- the two cabins cantilevered over the river on timber brackets (their counters open onto the deck)
	slab(s, "CabinEBracket", -6, 4, 406, 420, 8, 2, PAL.woodDark, WOODP)
	building(s, { name = "CabinE", x1 = -6, x2 = 3.4, z1 = 406, z2 = 420, h = 10, base = 8, roof = "gableX", rise = 4, tone = PAL.wall4 })
	slab(s, "CabinWBracket", 18, 30, 422, 436, 8, 2, PAL.woodDark, WOODP)
	building(s, { name = "CabinW", x1 = 18.6, x2 = 30, z1 = 422, z2 = 436, h = 12, base = 8, roof = "gableX", rise = 5, tone = PAL.wall2 })
	-- square parapets (river side, west edge except where the Bridge Steps land) and the causeway's north parapet
	box(s, "SquareParapetN1", -4, 4, 399, 400, 8, 9.3, PAL.stone, CONCRETE)
	box(s, "SquareParapetN2", 18, 40, 399, 400, 8, 9.3, PAL.stone, CONCRETE)
	box(s, "SquareParapetW", 39, 40, 372, 400, 8, 9.3, PAL.stone, CONCRETE)
	slab(s, "StepsLanding", 40, 48, 366, 372, 8.12, 0.24, PAL.square, CONCRETE)
	box(s, "CausewayParapetA", -70, -34, 385, 386, 8, 9.3, PAL.stone, CONCRETE)
	box(s, "CausewayParapetB", -26, -4, 385, 386, 8, 9.3, PAL.stone, CONCRETE)
	-- gate tower on the north abutment, road passage through it, a lantern turret on top
	box(s, "TowerE", -2, 4, 440, 456, 8, 62, PAL.bridge, CONCRETE)
	box(s, "TowerW", 18, 24, 440, 456, 8, 62, PAL.bridge, CONCRETE)
	box(s, "TowerTop", -2, 24, 440, 456, 20, 62, PAL.bridge, CONCRETE)
	box(s, "TowerCap", -3, 25, 439, 457, 62, 64, PAL.stoneDark, CONCRETE)
	box(s, "Lantern", 7, 15, 443, 453, 64, 76, PAL.stone, CONCRETE)
	-- north stub: embankment, the vault Collector's Row passes through, the ramp down, the closed gate
	box(s, "EmbankA", -2, 24, 456, 462, -1.4, 8, PAL.bridge, CONCRETE)
	slab(s, "VaultRoad", -2, 24, 462, 470, 8, 2, PAL.bridge, CONCRETE)
	box(s, "EmbankB", -2, 24, 470, 490, -1.4, 2, PAL.bridge, CONCRETE)
	box(s, "EmbankB1", -2, 24, 470, 477, 2, 6.6, PAL.bridge, CONCRETE)          -- stepped fill under the ramp
	box(s, "EmbankB2", -2, 24, 477, 484, 2, 4.5, PAL.bridge, CONCRETE)
	box(s, "EmbankB3", -2, 24, 484, 490, 2, 2.6, PAL.bridge, CONCRETE)
	stair(s, "StubRamp", Vector3.new(11, 8, 470), Vector3.new(11, 2, 490), 26, PAL.bridge)
	box(s, "ClosedGate", -4, 26, 490, 494, -1.4, 16, PAL.stoneDark, CONCRETE)
	box(s, "ClosedGateBeam", -4, 26, 488, 490, 12, 14, PAL.woodDark, WOODP)
	return s
end

-- Collector's Row: the sunken lane under the bridge road, its old buildings, the relic at the dead end
function G.CollectorsRow()
	local s = section("CollectorsRow")
	building(s, { name = "RN1", x1 = 26, x2 = 44, z1 = 472, z2 = 500, h = 18, base = -1.4, roof = "gableZ", rise = 6, tone = PAL.wall4 })
	building(s, { name = "RN2", x1 = -24, x2 = -4, z1 = 473, z2 = 496, h = 14, base = -1.4, roof = "hip", rise = 5, tone = PAL.wall2 })
	building(s, { name = "RN3", x1 = -44, x2 = -28, z1 = 473, z2 = 504, h = 22, base = -1.4, roof = "gableZ", rise = 7, tone = PAL.wall })
	building(s, { name = "RN4", x1 = -60, x2 = -48, z1 = 473, z2 = 500, h = 16, base = -1.4, roof = "flat", tone = PAL.wall3 })
	building(s, { name = "RS1", x1 = -24, x2 = -4, z1 = 446, z2 = 460, h = 10, base = -1.4, roof = "flat", tone = PAL.wall4 })
	building(s, { name = "RS2", x1 = -56, x2 = -28, z1 = 446, z2 = 460, h = 12, base = -1.4, roof = "shed", shedHigh = "S", tone = PAL.wall2 })
	-- an old timber overhang closing the lane's east end above the relic
	box(s, "EndOverhang", -60, -44, 458, 474, 8, 9, PAL.woodDark, WOODP)
	-- the relic: a fallen colossus head half-buried where the lane dies (relic scale, the only survivor)
	mk(s, "RelicHead", Vector3.new(11, 9, 9), at(-52, -2.5, 465) * CFrame.Angles(math.rad(18), math.rad(-25), math.rad(12)), PAL.relic, SLATE)
	-- railing on the river side of the stair landing
	box(s, "RowRail", 24, 48, 460.4, 461.4, -1.4, 0.2, PAL.woodDark, WOODP)
	slab(s, "RowLane", -56, 48, 462, 471, -1.28, 0.24, PAL.road, CONCRETE)
	return s
end

-- Stairs: every level change (tilted slabs in the greybox; real treads at the architecture pass)
function G.Stairs()
	local s = section("Stairs")
	stair(s, "ForkStairA", Vector3.new(-30, 0, 246), Vector3.new(-54, 7, 246), 6)
	slab(s, "ForkLanding", -62, -54, 242, 250, 7, 1.0, PAL.stone, CONCRETE)
	stair(s, "ForkStairB", Vector3.new(-58, 7, 250), Vector3.new(-58, UP, 262), 6)
	stair(s, "UpperToCauseway", Vector3.new(-61, UP, 362), Vector3.new(-61, 8, 372), 8)
	stair(s, "BridgeSteps", Vector3.new(44, -0.8, 396), Vector3.new(44, 8, 372), 8)
	stair(s, "PocketStair", Vector3.new(-30, 8, 388), Vector3.new(-54, -0.8, 388), 4)
	stair(s, "StubToRow", Vector3.new(24, 8, 466), Vector3.new(48, -1.4, 466), 8)
	stair(s, "BackTerraceStep", Vector3.new(-104, UP, 298), Vector3.new(-108, UP + 2, 298), 8)
	return s
end

-- Roads: thin darker slabs on the ground so the walk test reads the routes (the street bends; no straight axis)
function G.Roads()
	local s = section("Roads")
	local pts = { -- Lower Market Street centreline: x, z, width
		{ 0, 38, 20 }, { 2, 70, 14 }, { 12, 110, 16 }, { 10, 150, 12 }, { 4, 190, 16 }, { -10, 226, 18 }, { -12, 250, 24 },
	}
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local p, q = Vector3.new(a[1], 0.12, a[2]), Vector3.new(b[1], 0.12, b[2])
		local w = (a[3] + b[3]) / 2
		ramp(s, "Street", p, q, w, 0.24, PAL.road, CONCRETE)
		cyl(s, "StreetJoint", w, 0.24, at(b[1], 0.12, b[2]), PAL.road, CONCRETE)
	end
	slab(s, "GatePath", -10, 10, 17, 40, 0.12, 0.24, PAL.road, CONCRETE)
	slab(s, "AlleyA1", 8, 70, 96, 104, 0.12, 0.24, PAL.road, CONCRETE)
	slab(s, "AlleyA2", 20, 70, 146, 153, 0.12, 0.24, PAL.road, CONCRETE)
	slab(s, "AlleyA3", 40, 70, 304, 311, 0.12, 0.24, PAL.road, CONCRETE)
	slab(s, "AlleyA4", -40, -6, 122, 130, 0.12, 0.24, PAL.road, CONCRETE)
	slab(s, "LaneL1", 6, 70, 250, 262, 0.12, 0.24, PAL.road, CONCRETE)
	slab(s, "Causeway", -70, -4, 372, 385, 8.12, 0.24, PAL.road, CONCRETE)
	slab(s, "SquareTop", -4, 39, 366, 399, 8.12, 0.24, PAL.square, CONCRETE)
	slab(s, "StubRoad", 4, 18, 456, 462, 8.12, 0.24, PAL.road, CONCRETE)
	return s
end

-- Barrier: invisible walls where the water would otherwise let a player leave the settlement
function G.Barrier()
	local s = section("Barrier")
	local props = { Transparency = 1, CanCollide = true, CastShadow = false }
	box(s, "BarrierWest", 134, 136, -70, 540, -4, 40, PAL.stone, SP, props)
	box(s, "BarrierSouth", -140, 136, -72, -70, -4, 40, PAL.stone, SP, props)
	box(s, "BarrierEastShore", -140, -138, -70, 20, -4, 40, PAL.stone, SP, props)
	return s
end

-- NPC spots: visible teal posts in the greybox (invisible anchors from Phase 4); NPC-01 places rigs on them
function G.NpcSpots()
	local s = section("NpcSpots")
	for _, n in ipairs(G.NPC_SPOTS) do
		local pos = W(n.x, n.y + 2, n.z)
		local p = mk(s, "NpcSpot_" .. n.role, Vector3.new(1, 4, 1), CFrame.lookAt(pos, pos + n.dir), PAL.npc, SP, { Transparency = 0.35, CanCollide = false })
		p:SetAttribute("Role", n.role)
		p:SetAttribute("Tier", n.tier)
		p:SetAttribute("Note", n.note)
	end
	return s
end

-- Booths: the 18 stall modules in their shells, BoothIndex 1..18 contiguous
function G.Booths()
	local rc = rootCenter()
	local old = rc:FindFirstChild("Booths")
	if old and old:GetAttribute("TW2") then old:Destroy() end
	local f = folder(rc, "Booths")
	f:SetAttribute("TW2", true)
	for _, sp in ipairs(G.STALLS) do stall(f, sp) end
	return f
end

-- TradeZone: ONE box over the Fork Square + the Guild House arcade (where traders naturally meet)
function G.TradeZone()
	local rc = rootCenter()
	local old = rc:FindFirstChild("TradeZone")
	if old and old:GetAttribute("TW2") then old:Destroy() end
	local z = mk(rc, "TradeZone", Vector3.new(52, 22, 46), at(-18, 6, 255), PAL.water, SP, { Transparency = 1, CanCollide = false, CastShadow = false })
	z:SetAttribute("TW2", true)
	return z
end

-- HubPortal: re-pivot the existing portal model so its PortalTouch stands in the boathouse's open west face
function G.PlacePortal()
	local portals = gameWorld():FindFirstChild("Portals")
	local hub = portals and portals:FindFirstChild("HubPortal")
	local touch = hub and hub:FindFirstChild("PortalTouch", true)
	if not (hub and touch) then return "HubPortal/PortalTouch not found" end
	if not hub:GetAttribute("TW2_OriginalPivot") then
		hub:SetAttribute("TW2_OriginalPivot", hub:GetPivot())
	end
	local pos = W(-21, 5.6, 12)
	-- the touch part's thin axis is its local Z; the player walks off the dock EAST (design -x) into the boathouse
	local target = CFrame.lookAt(pos, pos + Vector3.new(-1, 0, 0))
	local rel = touch.CFrame:ToObjectSpace(hub:GetPivot())      -- pivot expressed in the touch part's frame
	hub:PivotTo(target * rel)
	return string.format("HubPortal pivoted; PortalTouch at (%.1f, %.1f, %.1f)", touch.Position.X, touch.Position.Y, touch.Position.Z)
end

-- EternalSkip: keep the kept island script, retarget its orbit into the bay west of the dock (one-time source edit)
function G.RetargetSkip()
	local rw = rootWorld()
	local es = rw:FindFirstChild("EternalSkip")
	local loop = es and es:FindFirstChild("SkipLoop")
	if not loop then return "EternalSkip/SkipLoop not under TradingWorld" end
	local src = loop.Source
	local new = src:gsub("local CX, CZ, R = 8000, 8000, 68", "local CX, CZ, R = 8150, 7878, 40", 1)
	new = new:gsub("local WATER_Y = 2002%.0", "local WATER_Y = 2000.0", 1)
	if new ~= src then loop.Source = new end
	-- park the static parts in the bay so they are not left inside the town in Edit mode
	for _, n in ipairs({ "Stone", "Ring1", "Ring2", "Ring3" }) do
		local p = es:FindFirstChild(n)
		if p and p:IsA("BasePart") then p.CFrame = CFrame.new(8190, 2000.4, 7878) end
	end
	return (new ~= src) and "SkipLoop retargeted (CX 8150, CZ 7878, R 40, WATER_Y 2000)" or "SkipLoop already retargeted"
end

-- ============================================================ operations
-- ONCE: move the old cove island out of the two live folders into ServerStorage (a move, not a delete).
function G.RetireLegacy()
	local bk = ServerStorage:FindFirstChild(G.BACKUP)
	if not bk then bk = folder(ServerStorage, G.BACKUP) end
	local moved = { world = 0, center = 0 }
	local lw = bk:FindFirstChild("Legacy_TradingWorld") or folder(bk, "Legacy_TradingWorld")
	local lc = bk:FindFirstChild("Legacy_TradingCenter") or folder(bk, "Legacy_TradingCenter")
	for _, ch in ipairs(rootWorld():GetChildren()) do
		if not ch:GetAttribute("TW2") and ch.Name ~= "EternalSkip" then
			ch.Parent = lw; moved.world += 1
		end
	end
	for _, ch in ipairs(rootCenter():GetChildren()) do
		if not ch:GetAttribute("TW2") then
			ch.Parent = lc; moved.center += 1
		end
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

local SECTIONS = { "Land", "Cliffs", "ArrivalDock", "MarketEntrance", "LowerMarket", "Waterfront", "UpperMarket", "OldBridge", "CollectorsRow", "Stairs", "Roads", "Barrier", "NpcSpots", "Booths", "TradeZone" }
function G.BuildAll()
	CHS:SetWaypoint("TW2 settlement: before build")
	local log = {}
	for _, name in ipairs(SECTIONS) do
		local ok, err = pcall(G[name])
		table.insert(log, (ok and "ok   " or "FAIL ") .. name .. (ok and "" or (" -- " .. tostring(err))))
	end
	local ok, msg = pcall(G.PlacePortal); table.insert(log, (ok and "ok   Portal -- " or "FAIL Portal -- ") .. tostring(msg))
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
		-- ground under the customer's feet in front of the counter (a stall nobody can reach is a dead stall)
		if counter then
			local front = counter.CFrame * CFrame.new(0, 2, -4)
			local hit = Workspace:Raycast(front.Position, Vector3.new(0, -8, 0))
			if not hit then table.insert(bad, "no ground in front") end
		end
		if #bad == 0 then ok += 1 else table.insert(problems, b.Name .. ": " .. table.concat(bad, ", ")) end
	end
	local total = bf and #bf:GetChildren() or 0
	for i = 1, maxIdx do if not seen[i] then table.insert(problems, "BoothIndex gap at " .. i) end end
	-- ground under TRADE_POS and the way home off-axis
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
	for _, n in ipairs({ G.ROOT_WORLD, G.ROOT_CENTER }) do
		local m = gw:FindFirstChild(n)
		if m then
			for _, d in ipairs(m:GetDescendants()) do
				c.Total += 1
				if d:IsA("BasePart") then
					c.BasePart += 1
					if d.Material == Enum.Material.Neon then c.Neon += 1 end
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
	-- BoundsGuard "Trading" box: X 7300..8790, Y 1930..2110, Z 7375..8725 (margins reported)
	local margin = string.format("bbox X %.0f..%.0f Y %.0f..%.0f Z %.0f..%.0f | BoundsGuard margins W %.0f E %.0f N %.0f S %.0f top %.0f",
		minv.X, maxv.X, minv.Y, maxv.Y, minv.Z, maxv.Z, 8790 - maxv.X, minv.X - 7300, 8725 - maxv.Z, minv.Z - 7375, 2110 - maxv.Y)
	return table.concat(parts, " ") .. "\n" .. margin
end

return G
