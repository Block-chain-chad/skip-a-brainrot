-- BuildPortals -- the way into and out of World 3.
--
-- Valley side: an arch of pale elven stone and living root standing in the meadow at
-- (160, 4, 60), 171 studs from spawn. World 3 side: its twin in the arrival chamber
-- at the far end of the gorge, so the first thing a player sees on arriving is a
-- narrow winding slot -- and then the cavern opening out ahead of them.

local L = require(script.Parent.Lib)
local F = require(script.Parent.Field)
local A = require(script.Parent.Arch)
local P = require(script.Parent.Props)
local Fl = require(script.Parent.Flora)

local M = {}

local function gate(parent, cf, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = opts.name or "Portal"
	m.Parent = parent
	local stone = opts.stone or L.C.PaleStone
	local W, Hh, T = 26, 34, 5
	local rise = 17

	-- plinth and steps
	L.box(m, "Plinth", cf * CFrame.new(0, 1.0, 0), Vector3.new(W + 22, 2.0, 26), L.C.WeatheredStone, L.M.Stone, {solid = true})
	L.box(m, "Step", cf * CFrame.new(0, 0.4, -12), Vector3.new(W + 14, 1.6, 8), L.C.WeatheredStone, L.M.Stone, {solid = true})

	-- the arch, as a wall with one pointed opening: guarantees a closed surround
	A.wall(m, cf * CFrame.new(0, 2, 0), W + 20, Hh + rise + 10, T,
		{openings = {{x = 0, w = W, sill = 0, h = Hh, rise = rise}},
		 color = stone, mat = L.M.Stone, trimColor = L.C.ElvenStone, name = "GateWall", slices = 16})

	-- the veil: a glowing sheet filling the opening, sliced to follow the arch
	local prof = A.archProfile(W, rise)
	for i = 0, 13 do
		local x = -W / 2 + (i + 0.5) * (W / 14)
		local hgt = Hh + prof(x)
		local v = L.box(m, "Veil", cf * CFrame.new(x, 2 + hgt / 2, 0), Vector3.new(W / 14 + 0.06, hgt, 0.8),
			opts.veil or L.C.GlowGreen, Enum.Material.Neon, {collide = false, shadow = false})
		v.Transparency = 0.45 + (i % 3) * 0.08
	end
	local lp = L.box(m, "VeilLight", cf * CFrame.new(0, 2 + Hh * 0.5, 0), Vector3.new(1, 1, 1), opts.veil or L.C.GlowGreen,
		Enum.Material.Neon, {collide = false, shadow = false, transparency = 1})
	L.light(lp, opts.veil or L.C.GlowGreen, 4, 80)

	-- flanking piers and braziers
	for _, s in ipairs({-1, 1}) do
		L.box(m, "Pier", cf * CFrame.new(s * (W / 2 + 12), 2 + (Hh + rise) * 0.5, 0), Vector3.new(7, Hh + rise, 8), stone, L.M.Stone, {solid = true})
		A.spire(m, cf * CFrame.new(s * (W / 2 + 12), 2 + Hh + rise, 0), 3.6, 16, {segs = 9, color = L.C.DeepStone, mat = L.M.Stone, finialColor = L.C.Gold})
		P.brazier(m, (cf * CFrame.new(s * (W / 2 + 22), 2, -8)).Position, {fire = opts.veil or L.C.GlowGreen})
		-- living root growing over the stonework
		P.root(m, {
			(cf * CFrame.new(s * (W / 2 + 17), 0, 6)).Position,
			(cf * CFrame.new(s * (W / 2 + 11), 20, 3)).Position,
			(cf * CFrame.new(s * (W / 2 + 4), 38, 0)).Position,
			(cf * CFrame.new(s * 5, 50, -1)).Position,
			(cf * CFrame.new(-s * 8, 47, 2)).Position,
		}, 3.4, 1.0, {color = L.C.Root, rootlets = 6, seed = s > 0 and 3 or 8, name = "GateRoot"})
	end

	-- carved keystone and runes
	P.carving(m, cf * CFrame.new(0, 2 + Hh + rise + 5, T / 2), 14, 8, {glow = opts.veil or L.C.GlowGreen, seed = 5})

	-- greenery
	for i = 1, 8 do
		local a = (i / 8) * 6.283
		Fl.flowerPatch(m, (cf * CFrame.new(math.cos(a) * 30, 0, math.sin(a) * 22 - 6)).Position,
			{seed = i, radius = 6, count = 7, colors = {L.C.GlowPink, L.C.GlowCyan, L.C.GlowGreen}})
	end

	-- the trigger
	local touch = L.box(m, "PortalTouch", cf * CFrame.new(0, 2 + Hh * 0.45, 0), Vector3.new(W - 3, Hh * 0.9, 4),
		Color3.new(1, 1, 1), Enum.Material.Neon, {collide = false, shadow = false, transparency = 1, solid = true})
	touch.CanCollide = false
	touch:SetAttribute("Dest", opts.dest)

	-- a sign so players know where it goes
	local anchor = L.box(m, "LabelAnchor", cf * CFrame.new(0, 2 + Hh + rise + 14, 0), Vector3.new(1, 1, 1),
		Color3.new(1, 1, 1), Enum.Material.Neon, {collide = false, shadow = false, transparency = 1})
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 320, 0, 70)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 400
	bb.Parent = anchor
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.GothamBold
	tl.TextScaled = true
	tl.TextColor3 = opts.veil or L.C.GlowGreen
	tl.TextStrokeTransparency = 0.35
	tl.Text = opts.label or "The Lush Gardens"
	tl.Parent = bb
	return m
end

-- opts.valleyGate: build the World 1 -> World 3 gate. OFF by default.
--
-- Jayden removed that gate on purpose: the way into World 3 is to come from WORLD 2,
-- not from the valley, and it is not meant to be reachable yet. An audit re-ran this
-- module and silently put the valley gate back, which undid that decision -- hence
-- the opt-in flag rather than building it every time.
function M.run(opts)
	opts = opts or {}
	local gw = workspace.GameWorld
	local portals = gw.Portals
	-- clean up BOTH the correct name and the default one an earlier run left behind
	for _, n in ipairs({"GardensPortal", "Portal"}) do
		local o = portals:FindFirstChild(n)
		if o then o:Destroy() end
	end
	local old2 = gw.LushGardens.Portals:FindFirstChild("GardensReturnPortal"); if old2 then old2:Destroy() end

	-- ===== valley side (opt-in only) =====
	if opts.valleyGate then
		local vcf = CFrame.new(Vector3.new(160, 4, 60)) * CFrame.Angles(0, math.rad(-120), 0)
		gate(portals, vcf, {dest = "Gardens", veil = L.C.GlowGreen, label = "The Lush Gardens",
			name = "GardensPortal"})
	end

	-- ===== world 3 side, in the arrival chamber =====
	local cx, cz = F.ARRIVAL_CHAMBER.X, F.ARRIVAL_CHAMBER.Y
	local gy = F.ground(cx, cz + 26, F.ceiling(cx, cz + 26))
	local rcf = CFrame.new(L.wv(cx, gy, cz + 26)) * CFrame.Angles(0, math.rad(180), 0)
	gate(gw.LushGardens.Portals, rcf, {dest = "Hub", veil = L.C.GlowCyan, label = "Return to the Valley",
		name = "GardensReturnPortal"})

	-- light the chamber and the first stretch of the gorge, so arriving players can see
	for i = 0, 9 do
		local t = i / 9
		local p = L.spline({
			Vector3.new(cx, 0, cz), Vector3.new(cx - 70, 0, cz - 60), Vector3.new(cx + 45, 0, cz - 132),
			Vector3.new(cx - 40, 0, cz - 214), Vector3.new(cx + 30, 0, cz - 296), Vector3.new(cx, 0, cz - 372),
		}, t)
		local py = F.ground(p.X, p.Z, F.ceiling(p.X, p.Z))
		Fl.crystals(gw.LushGardens.Portals, L.wv(p.X + (i % 2 == 0 and 24 or -24), py, p.Z),
			{seed = i, count = 5, spread = 7, minH = 6, maxH = 20,
			color = (i % 2 == 0) and L.C.GlowCyan or L.C.GlowGreen, brightness = 2.2, range = 48})
		Fl.giantMushroom(gw.LushGardens.Portals, L.wv(p.X + (i % 2 == 0 and -22 or 22), py, p.Z),
			{seed = i * 3, height = 14 + (i % 3) * 6, cap = L.C.GlowPink, gill = L.C.GlowCyan})
	end

	-- the arrival point: a few studs in front of the return portal, facing up the gorge
	local ax, az = cx, cz + 6
	local ay = F.ground(ax, az, F.ceiling(ax, az)) + 5
	return string.format("GARDENS_POS = Vector3.new(%.0f, %.0f, %.0f)  -- arrival chamber, facing -Z up the gorge\nvalley gate: %s",
		L.ORIGIN.X + ax, L.ORIGIN.Y + ay, L.ORIGIN.Z + az,
		opts.valleyGate and "built (explicitly requested)" or "NOT built")
end

return M
