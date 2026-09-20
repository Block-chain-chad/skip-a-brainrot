--!nocheck
--[[
TradingWorldBuild.Generator -- BUILD-TIME ONLY greybox generator for the Brainrot Grand Exchange
(TW-01, Phase 2, Checkpoint 1). Installed at ServerStorage.TradingWorldBuild.Generator. Nothing in the
game requires it. Run from the command bar or the Studio MCP, in Edit mode:

    local G = loadstring(game:GetService("ServerStorage").TradingWorldBuild.Generator.Source)()
    G.ClearAll()                       -- removes GameWorld.TradingWorld_GE / TradingCenter_GE only
    G.BuildAll()                       -- or the sections one by one: G.Base(); G.Landing(); ...
    print(G.Contracts())               -- booth/zone contract self-check, "OK n/n"
    print(G.Stats())                   -- part / light / emitter / script counts

STAGING. Everything is generated in DESIGN SPACE (island centre C = (8000, 2002.4, 8000), the plaza
datum P = y 2002.4, compass N = +Z / E = -X / W = +X) and then shifted by G.OFFSET so the new island
stands BESIDE the live one (default +500 on X -> centre (8500, 2002.4, 8000), still inside the
BoundsGuard "Trading" box X 7300..8790). The live GameWorld.TradingWorld / TradingCenter / Portals are
never touched. At cutover the two staging Models are pivoted by -OFFSET (or regenerated with OFFSET =
Vector3.zero) and renamed; the booth Models keep today's exact contracts (BoothIndex attribute,
Counter.StandPrompt, Display1-3, SignBoard > SurfaceGui > TextLabel) so BoothHandler adopts them as-is.

Heights are WALKABLE SURFACES relative to P unless a comment says otherwise. Spec:
docs/TRADING-WORLD-REWORK-PHASE1B-INSPECTION.md sections 5-6 (approved 2026-09-19).
]]

local G = {}
G.VERSION = 1
G.C = Vector3.new(8000, 2002.4, 8000)      -- design centre; y = P
G.OFFSET = Vector3.new(500, 0, 0)          -- staging offset (see header)
G.ROOT_WORLD = "TradingWorld_GE"
G.ROOT_CENTER = "TradingCenter_GE"
G.ARCADE_STANDS = 12                        -- per arcade
G.ARCADE_HALF_ANGLE = 60                    -- degrees each side of the arcade axis

local Workspace = game:GetService("Workspace")
local CHS = game:GetService("ChangeHistoryService")

-- ============================================================ palette
local C3 = Color3.fromRGB
local PAL = {
	stone = C3(238, 226, 200), stone2 = C3(224, 210, 180), stoneDark = C3(198, 182, 150), stoneWarm = C3(232, 214, 176),
	slate = C3(52, 50, 58), slate2 = C3(72, 70, 80), slate3 = C3(96, 92, 104),
	gold = C3(255, 196, 64), goldDeep = C3(224, 138, 12), goldPale = C3(255, 224, 140),
	teal = C3(106, 222, 224), tealDeep = C3(32, 120, 178), water = C3(58, 176, 200),
	cream = C3(255, 251, 226), ink = C3(36, 31, 20), navy = C3(30, 34, 60),
	pink = C3(255, 90, 220), godGold = C3(255, 226, 120), white = C3(245, 250, 250),
}
-- RarityConfig ladder (Common -> God), used for banners
local RARITY = { C3(190, 190, 190), C3(80, 220, 90), C3(60, 140, 255), C3(180, 60, 255), C3(255, 170, 30), C3(255, 50, 50), C3(255, 90, 220), C3(255, 226, 120) }
local SP = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

-- ============================================================ frame helpers
local function W(x, y, z) return G.C + G.OFFSET + Vector3.new(x, y, z) end                     -- design -> world
local function polar(r, deg, y) local a = math.rad(deg); return W(r * math.cos(a), y or 0, r * math.sin(a)) end
local function centreAt(y) return W(0, y or 0, 0) end
-- LookVector = radial outward (local -Z outward, local +X tangential)
local function radialCF(pos)
	local c = Vector3.new(G.C.X + G.OFFSET.X, pos.Y, G.C.Z + G.OFFSET.Z)
	return CFrame.lookAt(pos, pos + (pos - c).Unit)
end
local function faceCentre(pos)
	local c = Vector3.new(G.C.X + G.OFFSET.X, pos.Y, G.C.Z + G.OFFSET.Z)
	return CFrame.lookAt(pos, c)
end

local counts = { parts = 0 }
local function mk(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Color = color or PAL.stone
	p.Material = material or SP
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then for k, v in pairs(props) do p[k] = v end end
	p.Parent = parent
	counts.parts += 1
	return p
end
-- vertical cylinder: Roblox cylinders point along local X, so rotate 90 about Z
local function cyl(parent, name, diameter, height, cf, color, material, props)
	local p = mk(parent, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
local function wedge(parent, name, size, cf, color, material, props)
	local p = Instance.new("WedgePart")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Anchored = true
	p.Color = color or PAL.stone; p.Material = material or SP
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	if props then for k, v in pairs(props) do p[k] = v end end
	p.Parent = parent
	counts.parts += 1
	return p
end
local function model(parent, name)
	local m = Instance.new("Model"); m.Name = name; m.Parent = parent; return m
end
local function folder(parent, name)
	local f = Instance.new("Folder"); f.Name = name; f.Parent = parent; return f
end
local function light(part, class, props)
	local l = Instance.new(class)
	for k, v in pairs(props) do l[k] = v end
	l.Parent = part
	return l
end
-- SurfaceGui text plate on a part face
local function plate(part, text, face, textColor, bgColor, bgTransparency, font, pps)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SurfaceGui"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps or 50
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = bgColor or PAL.navy
	label.BackgroundTransparency = bgTransparency == nil and 1 or bgTransparency
	label.BorderSizePixel = 0
	label.Font = font or Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = textColor or PAL.goldPale
	label.TextScaled = true
	label.TextStrokeTransparency = 0.6
	label.Parent = gui
	return gui, label
end

-- annular ring of chord blocks between rIn and rOut, top surface at yTop (relative to P)
local function ring(parent, name, rIn, rOut, yTop, thick, n, color, material, props, degA, degB)
	local a0, a1 = degA or 0, degB or 360
	local span = a1 - a0
	local segs = n
	local rMid = (rIn + rOut) / 2
	local radial = rOut - rIn
	local tang = 2 * rOut * math.tan(math.rad(span / segs) / 2) + 0.25
	for i = 0, segs - 1 do
		local deg = a0 + (i + 0.5) * span / segs
		local pos = polar(rMid, deg, yTop - thick / 2)
		mk(parent, name, Vector3.new(tang, thick, radial), radialCF(pos), color, material, props)
	end
end
-- ramp along an arc: r, from deg0 to deg1, rising y0 -> y1, n segments, width w (radial), kerb on the outer edge
local function arcRamp(parent, name, r, deg0, deg1, y0, y1, n, w, color, kerbColor)
	local thick = 1.0
	for i = 0, n - 1 do
		local t0, t1 = i / n, (i + 1) / n
		local a = polar(r, deg0 + (deg1 - deg0) * t0, y0 + (y1 - y0) * t0)
		local b = polar(r, deg0 + (deg1 - deg0) * t1, y0 + (y1 - y0) * t1)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude + 0.35
		local cf = CFrame.lookAt(mid, b) * CFrame.new(0, -thick / 2, 0)
		mk(parent, name, Vector3.new(w, thick, len), cf, color, SP)
		-- kerbs on both edges (the inner edge is open air between pylons below the arch spring)
		local c = Vector3.new(G.C.X + G.OFFSET.X, mid.Y, G.C.Z + G.OFFSET.Z)
		local outward = (mid - c).Unit
		for _, sgn in ipairs({ 1, -1 }) do
			local kpos = mid + outward * sgn * (w / 2 - 0.45) + Vector3.new(0, 0.55, 0)
			mk(parent, name .. "Kerb", Vector3.new(0.9, 1.5, len), CFrame.lookAt(kpos, kpos + (b - a)), kerbColor or PAL.gold, SP)
		end
	end
end
-- semicircular arch of n blocks; base = CFrame at span centre, spring height; local X along the span, local Z = depth axis
local function arch(parent, name, base, radius, n, thick, depth, color, material)
	local seglen = 2 * radius * math.sin(math.pi / (2 * n)) * 1.1
	for i = 0, n - 1 do
		local th = (i + 0.5) * math.pi / n
		local cf = base * CFrame.new(radius * math.cos(th), radius * math.sin(th), 0) * CFrame.Angles(0, 0, th + math.pi / 2)
		mk(parent, name, Vector3.new(seglen, thick, depth), cf, color, material or SP)
	end
end

-- ============================================================ roots
local function gameWorld() return Workspace:WaitForChild("GameWorld") end
local function rootWorld()
	local gw = gameWorld()
	local m = gw:FindFirstChild(G.ROOT_WORLD)
	if not m then m = model(gw, G.ROOT_WORLD); m:SetAttribute("GeneratorVersion", G.VERSION); m:SetAttribute("Staging", true) end
	return m
end
local function rootCenter()
	local gw = gameWorld()
	local m = gw:FindFirstChild(G.ROOT_CENTER)
	if not m then m = model(gw, G.ROOT_CENTER); m:SetAttribute("GeneratorVersion", G.VERSION); m:SetAttribute("Staging", true) end
	return m
end
local function section(name)
	local r = rootWorld()
	local old = r:FindFirstChild(name)
	if old then old:Destroy() end
	return model(r, name)
end

function G.ClearAll()
	local gw = gameWorld()
	for _, n in ipairs({ G.ROOT_WORLD, G.ROOT_CENTER }) do
		local m = gw:FindFirstChild(n)
		if m then m:Destroy() end
	end
	counts.parts = 0
	return "cleared"
end

-- ============================================================ sections
-- Base: hull, ground annulus, sunken Exchange Floor + steps, wadeable moat, outer stone ring, barrier + U-walls
function G.Base()
	local s = section("Base")
	-- sea hull (top P-2.4)
	cyl(s, "Hull", 250, 6, CFrame.new(centreAt(-5.4)), PAL.stoneDark, SP)
	-- ground: annulus r28..96 at P (the promenade, the arcades' floor and the rim), 2.4 thick
	ring(s, "Ground", 28, 96, 0, 2.4, 40, PAL.stoneWarm, SP)
	-- sunken Exchange Floor r22 at P-1.6 with a gold neon rim underneath
	cyl(s, "FloorRim", 44.6, 0.7, CFrame.new(centreAt(-2.05)), PAL.gold, NEON)
	cyl(s, "ExchangeFloor", 41.5, 0.8, CFrame.new(centreAt(-2.0)), PAL.cream, SP)
	-- ring steps: r22..25 top -0.8, r25..28 top 0
	ring(s, "Step1", 22, 25, -0.8, 1.6, 24, PAL.stone2, SP)
	ring(s, "Step2", 25, 28, 0, 2.4, 24, PAL.stone, SP)
	-- gold lane stripe at r58 (browse lane)
	ring(s, "LaneStripe", 57.55, 58.45, 0.09, 0.18, 32, PAL.gold, SP)
	-- wadeable moat r96..116, water top P-1, CanCollide TRUE (never a pit)
	ring(s, "MoatWater", 96, 116, -1.0, 1.4, 32, PAL.water, Enum.Material.Glass, { Transparency = 0.25, Reflectance = 0.05 })
	ring(s, "MoatBed", 96, 116, -2.4, 0.8, 32, PAL.tealDeep, SP)
	-- outer stone ring r116..124 at P
	ring(s, "OuterRing", 116, 124, 0, 2.4, 32, PAL.stone2, SP)
	-- barrier ring r150 (invisible), 24 segments, gaps at S (causeway/Landing) and N (Vault)
	local b = model(s, "Barrier")
	for i = 0, 23 do
		local deg = (i + 0.5) * 15
		local south = deg > 250 and deg < 290
		local north = deg > 70 and deg < 110
		if not south and not north then
			local pos = polar(150, deg, 20)
			mk(b, "BarrierWall", Vector3.new(2 * 150 * math.tan(math.rad(7.5)) + 0.6, 40, 2), radialCF(pos), PAL.stone, SP, { Transparency = 1, CanCollide = true, CastShadow = false })
		end
	end
	-- Landing U-wall (x +-39, z -145..-214) and Vault U-wall (x +-39, z +145..+190)
	for _, sgn in ipairs({ -1, 1 }) do
		mk(b, "LandingWall", Vector3.new(2, 40, 70), CFrame.new(W(sgn * 39, 20, -180)), PAL.stone, SP, { Transparency = 1, CanCollide = true, CastShadow = false })
		mk(b, "VaultWall", Vector3.new(2, 40, 46), CFrame.new(W(sgn * 39, 26, 168)), PAL.stone, SP, { Transparency = 1, CanCollide = true, CastShadow = false })
	end
	mk(b, "LandingWallS", Vector3.new(80, 40, 2), CFrame.new(W(0, 20, -215)), PAL.stone, SP, { Transparency = 1, CanCollide = true, CastShadow = false })
	mk(b, "VaultWallN", Vector3.new(80, 40, 2), CFrame.new(W(0, 26, 191)), PAL.stone, SP, { Transparency = 1, CanCollide = true, CastShadow = false })
	return s
end

-- Landing: arrival deck on the measured datums (deck top P, pad top P+0.4 under TRADE_POS), lamps, markers
function G.Landing()
	local s = section("Landing")
	mk(s, "Deck", Vector3.new(44, 2.4, 56), CFrame.new(W(0, -1.2, -182)), PAL.stoneWarm, SP)
	cyl(s, "ArrivalPad", 12, 0.4, CFrame.new(W(0, 0.2, -182)), PAL.gold, SP)
	cyl(s, "ArrivalPadCore", 6, 0.5, CFrame.new(W(0, 0.2, -182)), PAL.teal, NEON)
	-- gold arrow inlay pointing north
	mk(s, "ArrowShaft", Vector3.new(2, 0.12, 12), CFrame.new(W(0, 0.06, -168)), PAL.gold, SP)
	-- chevron with its vertex at the NORTH end (an arrow pointing up the causeway)
	mk(s, "ArrowHeadL", Vector3.new(1.6, 0.12, 7), CFrame.new(W(-2.2, 0.06, -160.5)) * CFrame.Angles(0, math.rad(40), 0), PAL.gold, SP)
	mk(s, "ArrowHeadR", Vector3.new(1.6, 0.12, 7), CFrame.new(W(2.2, 0.06, -160.5)) * CFrame.Angles(0, math.rad(-40), 0), PAL.gold, SP)
	-- edge lips (1.2 high)
	mk(s, "LipW", Vector3.new(1.2, 1.2, 56), CFrame.new(W(-21.4, 0.6, -182)), PAL.stoneDark, SP)
	mk(s, "LipE", Vector3.new(1.2, 1.2, 56), CFrame.new(W(21.4, 0.6, -182)), PAL.stoneDark, SP)
	mk(s, "LipS", Vector3.new(44, 1.2, 1.2), CFrame.new(W(0, 0.6, -209.4)), PAL.stoneDark, SP)
	-- lamp posts
	for _, sgn in ipairs({ -1, 1 }) do
		cyl(s, "LampPost", 0.9, 7, CFrame.new(W(sgn * 19, 3.5, -160)), PAL.slate, SP)
		local globe = mk(s, "LampGlobe", Vector3.new(1.8, 1.8, 1.8), CFrame.new(W(sgn * 19, 7.6, -160)), PAL.goldPale, NEON, { CanCollide = false })
		globe.Shape = Enum.PartType.Ball
		light(globe, "PointLight", { Range = 24, Brightness = 1.4, Color = PAL.goldPale, Shadows = false })
	end
	-- markers (NOT portals: no Dest attribute, not under Portals)
	mk(s, "TradePosMark", Vector3.new(2, 2, 2), CFrame.new(W(0, 2.2, -182)), PAL.teal, NEON, { Transparency = 0.7, CanCollide = false, CastShadow = false })
	local hp = mk(s, "HubPortalMark", Vector3.new(2.8, 11.2, 8.4), CFrame.new(W(-20, 5.6, -182)), PAL.teal, NEON, { Transparency = 0.6, CanCollide = false, CastShadow = false })
	hp:SetAttribute("Note", "HubPortal (Dest=Hub) target position at cutover; re-pivot the real Portals.HubPortal here")
	return s
end

-- Causeway: 24-wide deck z -154..-70, kerbs, 7 pairs of rarity banner masts, piers
function G.Causeway()
	local s = section("Causeway")
	mk(s, "Deck", Vector3.new(24, 1.6, 86), CFrame.new(W(0, -0.7, -112)), PAL.stoneWarm, SP)
	mk(s, "KerbW", Vector3.new(1, 1.0, 86), CFrame.new(W(-11.5, 0.6, -112)), PAL.stoneDark, SP)
	mk(s, "KerbE", Vector3.new(1, 1.0, 86), CFrame.new(W(11.5, 0.6, -112)), PAL.stoneDark, SP)
	mk(s, "AxisInlay", Vector3.new(1.2, 0.12, 84), CFrame.new(W(0, 0.16, -112)), PAL.gold, SP)
	for i = 0, 6 do
		local z = -148 + i * 12
		for _, sgn in ipairs({ -1, 1 }) do
			cyl(s, "Mast", 0.8, 14, CFrame.new(W(sgn * 10, 7, z)), PAL.slate, SP)
			local col = RARITY[(i % 8) + 1]
			mk(s, "Banner", Vector3.new(0.25, 5, 3), CFrame.new(W(sgn * 10 - sgn * 0.5, 10.5, z + 1.9)), col, SP, { CanCollide = false })
			local tip = mk(s, "MastTip", Vector3.new(1.4, 1.4, 1.4), CFrame.new(W(sgn * 10, 14.6, z)), col, NEON, { CanCollide = false })
			tip.Shape = Enum.PartType.Ball
		end
	end
	for _, z in ipairs({ -100, -124, -146 }) do
		for _, sgn in ipairs({ -1, 1 }) do
			cyl(s, "Pier", 3, 8, CFrame.new(W(sgn * 9, -4.6, z)), PAL.stoneDark, SP)
		end
	end
	return s
end

-- Great Arch at z -70: pylons to +36, semicircular arch to +54, gem keystone, two lights
function G.GreatArch()
	local s = section("GreatArch")
	for _, sgn in ipairs({ -1, 1 }) do
		mk(s, "Pylon", Vector3.new(8, 36, 8), CFrame.new(W(sgn * 18, 18, -70)), PAL.stone, SP)
		mk(s, "PylonBase", Vector3.new(10, 2, 10), CFrame.new(W(sgn * 18, 1, -70)), PAL.slate, SP)
		mk(s, "PylonBand", Vector3.new(8.6, 1.2, 8.6), CFrame.new(W(sgn * 18, 12, -70)), PAL.gold, SP)
		mk(s, "PylonBand", Vector3.new(8.6, 1.2, 8.6), CFrame.new(W(sgn * 18, 24, -70)), PAL.gold, SP)
		local lantern = mk(s, "PylonLantern", Vector3.new(1.4, 2.2, 1.4), CFrame.new(W(sgn * 13.6, 30, -70)), PAL.goldPale, NEON, { CanCollide = false })
		light(lantern, "PointLight", { Range = 30, Brightness = 1.2, Color = PAL.goldPale, Shadows = false })
	end
	arch(s, "ArchBlock", CFrame.new(W(0, 36, -70)), 18, 9, 3.2, 8, PAL.stone, SP)
	arch(s, "ArchTrim", CFrame.new(W(0, 36, -70)), 18, 9, 0.6, 8.6, PAL.gold, SP)
	-- keystone gem (a cube on its corner) at the apex
	mk(s, "Keystone", Vector3.new(4.2, 4.2, 4.2), CFrame.new(W(0, 55.5, -70)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), PAL.teal, NEON, { CanCollide = false })
	-- title plate under the keystone (facing south, toward arrivals)
	local title = mk(s, "TitlePlate", Vector3.new(30, 4, 0.6), CFrame.new(W(0, 40.5, -74.4)), PAL.navy, SP, { CanCollide = false })
	plate(title, "GRAND EXCHANGE", Enum.NormalId.Front, PAL.goldPale, PAL.navy, 0, Enum.Font.FredokaOne, 50)
	return s
end

-- Records terraces flanking the arch (static boards for v1)
function G.Records()
	local s = section("Records")
	local sets = {
		{ deg = 250, texts = { "TOP EARNERS", "MOST TIME PLAYED", "MOST BRAINROTS CAUGHT" }, name = "RecordsBoards" },   -- -X side (east)
		{ deg = 290, texts = { "MARKET PRICES", "HOW TO TRADE", "EXCHANGE RULES" }, name = "TickerBoards" },             -- +X side (west)
	}
	for _, set in ipairs(sets) do
		local plat = polar(80, set.deg, 0.6)
		mk(s, set.name .. "Terrace", Vector3.new(20, 1.2, 16), radialCF(plat), PAL.stone2, SP)
		for i, text in ipairs(set.texts) do
			local off = (i - 2) * 6.4
			-- tangential offset: rotate the polar angle slightly
			local dAng = math.deg(off / 87)
			local pos = polar(87, set.deg + dAng, 1.2 + 2.2)
			local board = mk(s, "Board", Vector3.new(5.6, 4.4, 0.6), faceCentre(pos), PAL.slate, SP)
			plate(board, text, Enum.NormalId.Front, PAL.goldPale, PAL.slate, 0, Enum.Font.GothamBlack, 50)
			mk(s, "BoardFoot", Vector3.new(1.2, 1.2, 1.2), faceCentre(polar(87, set.deg + dAng, 1.2 + 0.6)), PAL.gold, SP)
		end
	end
	return s
end

-- Exchange Hall: 8 pylons r44, arches, balcony ring +12 (r32..40), crown ring +30 (r40..46), ramps, bridges
function G.Hall()
	local s = section("ExchangeHall")
	-- pylons on the diagonals (axial openings stay clear)
	for k = 0, 7 do
		local deg = 22.5 + 45 * k
		local pos = polar(44, deg, 15)
		mk(s, "Pylon", Vector3.new(8, 30, 8), radialCF(pos), PAL.stone, SP)
		mk(s, "PylonBase", Vector3.new(9.6, 1.6, 9.6), radialCF(polar(44, deg, 0.8)), PAL.slate, SP)
		mk(s, "PylonBand", Vector3.new(8.6, 1.0, 8.6), radialCF(polar(44, deg, 10)), PAL.gold, SP)
		mk(s, "PylonBand", Vector3.new(8.6, 1.0, 8.6), radialCF(polar(44, deg, 20)), PAL.gold, SP)
		local lantern = mk(s, "PylonLantern", Vector3.new(1.2, 2.0, 1.2), radialCF(polar(39.4, deg, 26)), PAL.goldPale, NEON, { CanCollide = false })
		if k % 2 == 0 then light(lantern, "PointLight", { Range = 28, Brightness = 1.0, Color = PAL.goldPale, Shadows = false }) end
	end
	-- arches between adjacent pylons: chord 33.7 between centres, clear span ~25.7, spring +18
	for k = 0, 7 do
		local a = 22.5 + 45 * k
		local mid = polar(44 * math.cos(math.rad(22.5)), a + 22.5, 18)   -- chord midpoint sits inside r44
		local base = radialCF(mid)                                         -- local X tangential (along the chord), local -Z radial
		arch(s, "Arch", base, 12.8, 7, 2.6, 8, PAL.stone, SP)
		arch(s, "ArchTrim", base, 12.8, 7, 0.5, 8.6, PAL.gold, SP)
	end
	-- crown ring +30..+32 on top of pylons + arches, with an outer balustrade
	ring(s, "CrownRing", 40, 46.4, 32, 1.4, 32, PAL.stone2, SP)
	ring(s, "CrownBalustrade", 45.6, 46.6, 34.2, 2.2, 32, PAL.gold, SP)
	ring(s, "CrownInnerLip", 39.8, 40.6, 33.0, 1.0, 32, PAL.gold, SP)
	-- balcony ring +12 inside the pylons (r32..40) with an inner balustrade
	ring(s, "Balcony", 32, 40, 12, 1.0, 32, PAL.stone2, SP)
	ring(s, "BalconyBalustrade", 31.6, 32.6, 14.2, 2.2, 32, PAL.gold, SP)
	ring(s, "BalconyUnderTrim", 32, 40, 10.9, 0.3, 32, PAL.gold, SP)
	-- ramps hugging the drum at r52 (outer edge r56, inner r48 = pylon faces)
	arcRamp(s, "RampE", 52, -46, 0, 0, 12, 16, 8, PAL.stoneWarm, PAL.gold)       -- promenade -> balcony via the E opening
	arcRamp(s, "RampNE", 52, 0, 90, 12, 30, 24, 8, PAL.stoneWarm, PAL.gold)      -- balcony -> crown via the N opening
	arcRamp(s, "RampW", 52, 226, 180, 0, 12, 16, 8, PAL.stoneWarm, PAL.gold)     -- promenade -> balcony via the W opening
	arcRamp(s, "RampSW", 52, 180, 270, 12, 30, 24, 8, PAL.stoneWarm, PAL.gold)   -- balcony -> crown via the S opening
	-- bridges through the openings: E/W at +12 (r56 -> r40), N/S at +30 (r56 -> r46)
	for _, deg in ipairs({ 0, 180 }) do
		local pos = polar(48, deg, 12 - 0.5)
		mk(s, "BalconyBridge", Vector3.new(8, 1.0, 17), radialCF(pos), PAL.stoneWarm, SP)
		mk(s, "BridgeKerb", Vector3.new(0.9, 1.5, 17), radialCF(polar(48, deg + 4.3, 12.7)), PAL.gold, SP)
		mk(s, "BridgeKerb", Vector3.new(0.9, 1.5, 17), radialCF(polar(48, deg - 4.3, 12.7)), PAL.gold, SP)
	end
	for _, deg in ipairs({ 90, 270 }) do
		local pos = polar(51, deg, 30 - 0.5)
		mk(s, "CrownBridge", Vector3.new(8, 1.0, 11), radialCF(pos), PAL.stoneWarm, SP)
		mk(s, "BridgeKerb", Vector3.new(0.9, 1.5, 11), radialCF(polar(51, deg + 4.4, 30.7)), PAL.gold, SP)
		mk(s, "BridgeKerb", Vector3.new(0.9, 1.5, 11), radialCF(polar(51, deg - 4.4, 30.7)), PAL.gold, SP)
	end
	return s
end

-- Grand Gem: a hovering gem at +36 with attribute Spin (the existing CenterpieceSpinner drives it after
-- cutover; in staging it is static), one PointLight, a gold cage and the sky beam
function G.Gem()
	local s = section("GrandGem")
	local gem = mk(s, "GrandGem", Vector3.new(10, 10, 10), CFrame.new(centreAt(36)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), PAL.teal, NEON, { CanCollide = false })
	gem:SetAttribute("Spin", true)
	light(gem, "PointLight", { Range = 60, Brightness = 2, Color = PAL.teal, Shadows = false })
	mk(s, "GemCore", Vector3.new(5.5, 5.5, 5.5), CFrame.new(centreAt(36)) * CFrame.Angles(0, math.rad(45), math.rad(45)), PAL.godGold, NEON, { CanCollide = false })
	-- cage: two rings + four bars
	for _, y in ipairs({ 27, 45 }) do
		cyl(s, "CageRing", 18, 0.7, CFrame.new(centreAt(y)), PAL.gold, SP, { CanCollide = false })
	end
	for k = 0, 3 do
		local pos = polar(8.6, 45 + 90 * k, 36)
		mk(s, "CageBar", Vector3.new(0.7, 18, 0.7), CFrame.new(pos), PAL.gold, SP, { CanCollide = false })
	end
	-- sky beam (non-walkable, visual only)
	cyl(s, "SkyBeam", 3, 420, CFrame.new(centreAt(36 + 210)), PAL.teal, NEON, { Transparency = 0.55, CanCollide = false, CastShadow = false })
	return s
end

-- District totems on the diagonals of the promenade ring
function G.Totems()
	local s = section("Totems")
	local labels = { [45] = "ARCADES", [135] = "ARCADES", [225] = "THE VAULT", [315] = "EXCHANGE" }
	for deg, text in pairs(labels) do
		local post = mk(s, "Totem", Vector3.new(2.2, 8, 2.2), faceCentre(polar(66, deg, 4)), PAL.slate, SP)
		local cap = mk(s, "TotemGem", Vector3.new(1.8, 1.8, 1.8), CFrame.new(polar(66, deg, 9.6)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), PAL.teal, NEON, { CanCollide = false })
		local sign = mk(s, "TotemSign", Vector3.new(6, 1.6, 0.4), faceCentre(polar(64.6, deg, 6.2)), PAL.navy, SP, { CanCollide = false })
		plate(sign, text, Enum.NormalId.Front, PAL.goldPale, PAL.navy, 0, Enum.Font.GothamBlack, 50)
		cap.Name = "TotemGem"
	end
	return s
end

-- Arcade architecture (colonnade, roof, back wall, fascia, banners, roof lights) for one side.
-- axisDeg = 0 for the West Arcade (+X), 180 for the East Arcade (-X)
function G.Arcade(axisDeg)
	local name = axisDeg == 0 and "ArcadeWest" or "ArcadeEast"
	local s = section(name)
	local n = G.ARCADE_STANDS
	local half = G.ARCADE_HALF_ANGLE
	local pitch = (2 * half) / (n - 1)
	local a0 = axisDeg - half - pitch / 2
	local a1 = axisDeg + half + pitch / 2
	-- floor inlay (teal) under the stands
	ring(s, "ArcadeInlay", 66, 81, 0.08, 0.16, n, PAL.teal, SP, { CanCollide = false }, a0, a1)
	-- back wall r79..81, roof r66..81 at +9.6, fascia at the front edge
	ring(s, "BackWall", 79, 81, 8.6, 8.6, n, PAL.stone, SP, nil, a0, a1)
	ring(s, "Roof", 65, 81.5, 9.6, 0.7, n, PAL.stoneDark, SP, nil, a0, a1)
	ring(s, "Fascia", 64.8, 65.6, 9.9, 1.4, n, PAL.gold, SP, nil, a0, a1)
	-- columns at the stand boundaries
	for j = 0, n do
		local deg = a0 + j * pitch
		cyl(s, "Column", 1.6, 9.2, CFrame.new(polar(66, deg, 4.6)), PAL.slate, SP)
		mk(s, "ColumnCap", Vector3.new(2.2, 0.6, 2.2), CFrame.new(polar(66, deg, 9.0)), PAL.gold, SP)
		mk(s, "ColumnFoot", Vector3.new(2.2, 0.6, 2.2), CFrame.new(polar(66, deg, 0.3)), PAL.gold, SP)
	end
	-- banner mast + rarity banner per stand on the roof, roof light per two stands
	for k = 0, n - 1 do
		local deg = a0 + (k + 0.5) * pitch
		cyl(s, "RoofMast", 0.6, 6, CFrame.new(polar(74, deg, 12.6)), PAL.slate, SP, { CanCollide = false })
		mk(s, "RoofBanner", Vector3.new(2.6, 3.4, 0.25), faceCentre(polar(74, deg, 14.2)), RARITY[(k % 8) + 1], SP, { CanCollide = false })
		if k % 2 == 0 then
			local host = mk(s, "RoofLightHost", Vector3.new(1.6, 0.3, 1.6), CFrame.new(polar(72, deg + pitch / 2, 9.05)), PAL.goldPale, NEON, { CanCollide = false })
			light(host, "SurfaceLight", { Face = Enum.NormalId.Bottom, Range = 18, Angle = 120, Brightness = 1.2, Color = PAL.goldPale, Shadows = false })
		end
	end
	return s
end

-- One booth Model with today's exact contracts. idx = BoothIndex; deg = polar angle of the counter centre.
local function booth(parent, idx, deg)
	local b = model(parent, "Booth" .. idx)
	b:SetAttribute("BoothIndex", idx)
	local origin = faceCentre(polar(69.7, deg, 0))      -- local -Z toward the centre, ground level P
	local function L(x, y, z) return origin * CFrame.new(x, y, z) end
	mk(b, "Base", Vector3.new(12.4, 0.3, 12), L(0, 0.15, 3.6), PAL.slate2, SP)
	local counter = mk(b, "Counter", Vector3.new(11, 3.4, 3.4), L(0, 1.7, 0), PAL.slate, SP)
	mk(b, "CounterTrim", Vector3.new(11.2, 0.5, 3.6), L(0, 3.15, 0), PAL.gold, SP)
	mk(b, "CounterTrim", Vector3.new(11.2, 0.5, 3.6), L(0, 0.35, 0), PAL.gold, SP)
	for i, x in ipairs({ -3.4, 0, 3.4 }) do
		mk(b, "Display" .. i, Vector3.new(1.6, 1.0, 1.6), L(x, 3.9, 0), PAL.cream, SP)
	end
	local sign = mk(b, "SignBoard", Vector3.new(12, 3, 0.4), L(0, 6.5, 3.8), PAL.navy, SP)
	plate(sign, "AVAILABLE STAND", Enum.NormalId.Front, C3(255, 220, 90), PAL.navy, 0, Enum.Font.GothamBlack, 50)
	mk(b, "SignFrame", Vector3.new(12.6, 3.6, 0.3), L(0, 6.5, 4.05), PAL.gold, SP)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StandPrompt"
	prompt.ActionText = "Claim Stand"
	prompt.ObjectText = "Market Stand"
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration = 0.3
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = counter
	b.PrimaryPart = counter
	return b
end

-- Booth Models for one arcade into TradingCenter_GE.Booths (contracts live here, like today's TradingCenter.Booths)
function G.Booths(axisDeg)
	local rc = rootCenter()
	local boothsFolder = rc:FindFirstChild("Booths") or folder(rc, "Booths")
	local n = G.ARCADE_STANDS
	local half = G.ARCADE_HALF_ANGLE
	local pitch = (2 * half) / (n - 1)
	local first = axisDeg == 0 and 1 or (n + 1)
	for k = 0, n - 1 do
		local idx = first + k
		local old = boothsFolder:FindFirstChild("Booth" .. idx)
		if old then old:Destroy() end
		-- west: -60 -> +60 about +X (south -> north); east: 240 -> 120 about -X (south -> north)
		local deg = axisDeg == 0 and (axisDeg - half + k * pitch) or (axisDeg + half - k * pitch)
		booth(boothsFolder, idx, deg)
	end
	return boothsFolder
end

-- TradeZone: one box 46 x 22 x 46 centred (0, +3.6, 0) -> absolute (8000, 2006, 8000) after cutover
function G.TradeZone()
	local rc = rootCenter()
	local old = rc:FindFirstChild("TradeZone")
	if old then old:Destroy() end
	local z = mk(rc, "TradeZone", Vector3.new(46, 22, 46), CFrame.new(centreAt(3.6)) * CFrame.Angles(0, math.rad(180), 0), PAL.teal, SP, { Transparency = 1, CanCollide = false, CastShadow = false })
	return z
end

-- Vault plateau (+6) with ramp, portal arch, nave, six stand plinths (markers only at CP1), reliquary alcoves, flex pedestals
function G.Vault()
	local s = section("Vault")
	mk(s, "Plateau", Vector3.new(70, 6, 90), CFrame.new(W(0, 3, 137)), PAL.slate2, SP)
	mk(s, "PlateauTrim", Vector3.new(72, 0.6, 92), CFrame.new(W(0, 6.1, 137)), PAL.slate, SP)
	wedge(s, "Ramp", Vector3.new(16, 6, 26), CFrame.new(W(0, 3, 79)), PAL.stoneWarm, SP)
	mk(s, "RampKerb", Vector3.new(1, 1.4, 26), CFrame.new(W(-8.5, 3.4, 79)) * CFrame.Angles(math.rad(-13), 0, 0), PAL.gold, SP)
	mk(s, "RampKerb", Vector3.new(1, 1.4, 26), CFrame.new(W(8.5, 3.4, 79)) * CFrame.Angles(math.rad(-13), 0, 0), PAL.gold, SP)
	-- portal arch at z +92
	for _, sgn in ipairs({ -1, 1 }) do
		mk(s, "PortalPylon", Vector3.new(6, 20, 6), CFrame.new(W(sgn * 13, 16, 92)), PAL.slate, SP)
		mk(s, "PortalRim", Vector3.new(0.6, 20, 6.4), CFrame.new(W(sgn * 10.2, 16, 92)), sgn < 0 and PAL.pink or PAL.godGold, NEON, { CanCollide = false })
	end
	mk(s, "PortalLintel", Vector3.new(32, 4, 6), CFrame.new(W(0, 28, 92)), PAL.slate, SP)
	mk(s, "PortalRimTop", Vector3.new(32, 0.6, 6.4), CFrame.new(W(0, 26.2, 92)), PAL.godGold, NEON, { CanCollide = false })
	local vt = mk(s, "VaultTitle", Vector3.new(20, 3, 0.5), CFrame.new(W(0, 28, 88.6)), PAL.navy, SP, { CanCollide = false })
	plate(vt, "THE VAULT", Enum.NormalId.Front, PAL.pink, PAL.navy, 0, Enum.Font.FredokaOne, 50)
	-- nave inlay + side colonnades
	mk(s, "NaveInlay", Vector3.new(20, 0.14, 62), CFrame.new(W(0, 6.17, 130)), PAL.gold, SP, { CanCollide = false })
	for j = 0, 5 do
		for _, sgn in ipairs({ -1, 1 }) do
			cyl(s, "VaultColumn", 2, 18, CFrame.new(W(sgn * 33, 15, 100 + j * 12)), PAL.slate3, SP)
			mk(s, "VaultColumnCap", Vector3.new(2.6, 0.6, 2.6), CFrame.new(W(sgn * 33, 24.3, 100 + j * 12)), PAL.gold, SP)
		end
	end
	-- six Vault stand plinth markers (booth contracts for these come at Checkpoint 2)
	for _, x in ipairs({ -24, 24 }) do
		for _, z in ipairs({ 104, 120, 136 }) do
			mk(s, "VaultStandMark", Vector3.new(8, 0.6, 8), CFrame.new(W(x, 6.5, z)), PAL.stone2, SP)
		end
	end
	-- reliquary: five alcoves at z +165 (SECRET, GOD, GOLDEN, DIAMOND, MASSIVE)
	local alc = { { PAL.pink, "SECRET" }, { PAL.godGold, "GOD" }, { PAL.gold, "GOLDEN" }, { C3(120, 230, 255), "DIAMOND" }, { C3(255, 150, 60), "MASSIVE" } }
	for i, e in ipairs(alc) do
		local x = (i - 3) * 14
		local back = mk(s, "Alcove", Vector3.new(10, 16, 2), CFrame.new(W(x, 14, 166)), PAL.slate, SP)
		mk(s, "AlcoveRim", Vector3.new(10.6, 0.6, 2.4), CFrame.new(W(x, 22.3, 166)), e[1], NEON, { CanCollide = false })
		local plinth = mk(s, "AlcovePlinth", Vector3.new(6, 2, 6), CFrame.new(W(x, 7, 160)), PAL.slate3, SP)
		mk(s, "AlcovePlinthTrim", Vector3.new(6.4, 0.4, 6.4), CFrame.new(W(x, 8.2, 160)), e[1], NEON, { CanCollide = false })
		local lbl = mk(s, "AlcoveLabel", Vector3.new(8, 1.6, 0.3), CFrame.new(W(x, 10.5, 164.8)), PAL.navy, SP, { CanCollide = false })
		plate(lbl, e[2], Enum.NormalId.Front, e[1], PAL.navy, 0, Enum.Font.GothamBlack, 50)
		if i == 1 or i == 2 then
			light(back, "SpotLight", { Face = Enum.NormalId.Front, Range = 24, Angle = 90, Brightness = 1.6, Color = e[1], Shadows = false })
		end
	end
	mk(s, "BackWall", Vector3.new(72, 22, 2), CFrame.new(W(0, 17, 181)), PAL.slate2, SP)
	-- flex pedestals at z +98 with spotlights from above
	for _, x in ipairs({ -28, -12, 12, 28 }) do
		cyl(s, "FlexPedestal", 6, 0.6, CFrame.new(W(x, 6.3, 98)), PAL.cream, SP)
		cyl(s, "FlexPedestalRim", 6.6, 0.3, CFrame.new(W(x, 6.15, 98)), PAL.pink, NEON, { CanCollide = false })
		local host = mk(s, "FlexLightHost", Vector3.new(1, 0.4, 1), CFrame.new(W(x, 18, 98)), PAL.white, NEON, { CanCollide = false, Transparency = 0.4 })
		if x == -28 or x == 12 then
			light(host, "SpotLight", { Face = Enum.NormalId.Bottom, Range = 16, Angle = 60, Brightness = 2, Color = PAL.white, Shadows = false })
		end
	end
	local hpv = mk(s, "HubPortalVaultMark", Vector3.new(8.4, 11.2, 2.8), CFrame.new(W(0, 11.6, 186)), PAL.teal, NEON, { Transparency = 0.6, CanCollide = false, CastShadow = false })
	hpv:SetAttribute("Note", "HubPortalVault (Dest=Hub) position at cutover; create the real portal under GameWorld.Portals then")
	return s
end

-- Piers: Skipper's Pier (+X) and Colossus Walk (-X), r84 -> r124
function G.Piers()
	local s = section("Piers")
	for _, deg in ipairs({ 0, 180 }) do
		local pos = polar(104, deg, 0.6)
		mk(s, deg == 0 and "SkippersPier" or "ColossusWalk", Vector3.new(10, 1.2, 42), radialCF(pos), PAL.stoneWarm, SP)
		for _, r in ipairs({ 92, 116 }) do
			for _, t in ipairs({ -3.6, 3.6 }) do
				local dAng = math.deg(t / r)
				cyl(s, "PierPost", 2, 8, CFrame.new(polar(r, deg + dAng, -3.4)), PAL.stoneDark, SP)
			end
		end
		mk(s, "Bench", Vector3.new(1.4, 0.6, 5), radialCF(polar(112, deg + math.deg(3.6 / 112), 1.5)), PAL.slate, SP)
		mk(s, "Bench", Vector3.new(1.4, 0.6, 5), radialCF(polar(112, deg - math.deg(3.6 / 112), 1.5)), PAL.slate, SP)
	end
	return s
end

-- NPC anchor posts for NPC-01 (design coordinates from docs/trading-world/npc-roles-for-npc01.md)
function G.NpcPosts()
	local s = section("NpcPosts")
	local posts = {
		{ "ExchangeHost", 0, 0, -52, 0, 0, -1, 1, "TalkPrompt", "Host on the arch axis, faces arrivals" },
		{ "GemBroker", 32, 0, -48, -1, 0, 0, 1, "TalkPrompt", "Ticker wall, faces the axis" },
		{ "Curator", 0, 6, 148, 0, 0, -1, 2, "TalkPrompt", "Reliquary end of the Vault, faces the nave" },
		{ "AttendantWest", 36, 0, 62, -1, 0, 0, 2, "TalkPrompt", "north end of the West Arcade" },
		{ "AttendantEast", -36, 0, 62, 1, 0, 0, 2, "TalkPrompt", "north end of the East Arcade" },
		{ "Collector", -28, 12, -28, 1, 0, 1, 3, "TalkPrompt", "SE balcony, looks at the floor" },
		{ "TraderA", -12, -0.8, 12, 1, 0, 0, 3, "none", "floor step, faces TraderB" },
		{ "TraderB", 12, -0.8, 12, -1, 0, 0, 3, "none", "floor step, faces TraderA" },
		{ "Angler", 120, 0, 0, 1, 0, 0, 3, "none", "Skipper's Pier end, faces the sea (optional)" },
		{ "VaultGuardA", -14, 6, 92, 0, 0, -1, 3, "none", "Vault portal, faces S (optional)" },
		{ "VaultGuardB", 14, 6, 92, 0, 0, -1, 3, "none", "Vault portal, faces S (optional)" },
	}
	for _, e in ipairs(posts) do
		local pos = W(e[2], e[3], e[4])
		local look = Vector3.new(e[5], e[6], e[7]).Unit
		local cf = CFrame.lookAt(pos + Vector3.new(0, 0.1, 0), pos + Vector3.new(0, 0.1, 0) + Vector3.new(look.X, 0, look.Z))
		local p = mk(s, "NpcPost_" .. e[1], Vector3.new(4, 0.2, 4), cf, PAL.pink, SP, { Transparency = 1, CanCollide = false, CastShadow = false })
		p:SetAttribute("Role", e[1]); p:SetAttribute("Tier", e[8]); p:SetAttribute("Prompt", e[9]); p:SetAttribute("Note", e[10])
	end
	return s
end

-- ============================================================ checks
function G.Contracts()
	local rc = gameWorld():FindFirstChild(G.ROOT_CENTER)
	if not rc then return "no " .. G.ROOT_CENTER end
	local problems, ok, seen = {}, 0, {}
	local bf = rc:FindFirstChild("Booths")
	local zone = rc:FindFirstChild("TradeZone")
	if not (zone and zone:IsA("BasePart")) then table.insert(problems, "TradeZone missing") end
	local zones = 0
	for _, ch in ipairs(rc:GetChildren()) do if ch.Name == "TradeZone" then zones += 1 end end
	if zones ~= 1 then table.insert(problems, "TradeZone count " .. zones) end
	for _, b in ipairs(bf and bf:GetChildren() or {}) do
		local idx = b:GetAttribute("BoothIndex")
		local bad = {}
		if type(idx) ~= "number" then table.insert(bad, "BoothIndex") elseif seen[idx] then table.insert(bad, "duplicate index " .. idx) else seen[idx] = true end
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
		if #bad == 0 then ok += 1 else table.insert(problems, b.Name .. ": " .. table.concat(bad, ", ")) end
	end
	local total = bf and #bf:GetChildren() or 0
	return string.format("OK %d/%d booths; %d problems%s", ok, total, #problems, #problems > 0 and (" -- " .. table.concat(problems, "; ")) or "")
end

function G.Stats()
	local gw = gameWorld()
	local c = { BasePart = 0, MeshPart = 0, WedgePart = 0, Light = 0, ParticleEmitter = 0, Script = 0, Highlight = 0, SurfaceGui = 0, BillboardGui = 0, Neon = 0, Model = 0, Total = 0 }
	for _, n in ipairs({ G.ROOT_WORLD, G.ROOT_CENTER }) do
		local m = gw:FindFirstChild(n)
		if m then
			for _, d in ipairs(m:GetDescendants()) do
				c.Total += 1
				if d:IsA("BasePart") then c.BasePart += 1; if d.Material == NEON then c.Neon += 1 end end
				if d:IsA("MeshPart") then c.MeshPart += 1 end
				if d:IsA("WedgePart") then c.WedgePart += 1 end
				if d:IsA("Light") then c.Light += 1 end
				if d:IsA("ParticleEmitter") then c.ParticleEmitter += 1 end
				if d:IsA("LuaSourceContainer") then c.Script += 1 end
				if d:IsA("Highlight") then c.Highlight += 1 end
				if d:IsA("SurfaceGui") then c.SurfaceGui += 1 end
				if d:IsA("BillboardGui") then c.BillboardGui += 1 end
				if d:IsA("Model") then c.Model += 1 end
			end
		end
	end
	local parts = {}
	for k, v in pairs(c) do table.insert(parts, k .. "=" .. v) end
	table.sort(parts)
	return table.concat(parts, " ")
end

-- Checkpoint 1 scope: everything except the East Arcade and the Vault booth contracts
function G.BuildCheckpoint1()
	CHS:SetWaypoint("TW-01 GE build: before")
	G.Base(); G.Landing(); G.Causeway(); G.GreatArch(); G.Records(); G.Hall(); G.Gem(); G.Totems()
	G.Arcade(0); G.Booths(0); G.TradeZone(); G.Vault(); G.Piers(); G.NpcPosts()
	CHS:SetWaypoint("TW-01 GE build: checkpoint 1")
	return G.Stats()
end

function G.BuildAll()
	G.BuildCheckpoint1()
	G.Arcade(180); G.Booths(180)
	return G.Stats()
end

return G
