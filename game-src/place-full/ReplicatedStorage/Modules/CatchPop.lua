--!strict
-- CatchPop: the Common..Legendary reward reveal (spec S7). ONE beat structure --
-- appear -> bounce+burst -> text -> float -> close -- parameterised by a preset per
-- tier. Screen-space only: this module NEVER writes the camera, Lighting or another
-- gui's Enabled, so it has nothing to restore and cannot strand the camera.
-- Built from CatchReveal's viewport machinery and PullCeremony's stamp recipe.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotThumb = require(Modules:WaitForChild("BrainrotThumb"))
local Mutations = require(Modules:WaitForChild("MutationConfig"))
local MutationFX = require(Modules:WaitForChild("MutationFX"))
local Sizes = require(Modules:WaitForChild("SizeConfig"))
local UITheme = require(Modules:WaitForChild("UITheme"))
local SoundKit = require(Modules:WaitForChild("SoundKit"))

local player = Players.LocalPlayer

export type Grant = {
	Name: string, Rarity: string?, RarityColor: Color3?, Mutation: string?, Size: string?,
	Serial: number?, Exists: number?, IsNew: boolean?, OddsN: number?, TierCuePlayed: boolean?,
}

type Preset = {
	length: number, size: number, scaleFrom: number, overshoot: number, bounce: number,
	burst: number, burstSpread: number, glow: number, shockwave: boolean, rotation: number,
	uiBump: number, dim: number, orbit: number, textAt: number, textSlam: boolean, floatAmp: number,
	glowPulse: boolean,
}

-- ===== PRESETS (spec S7 table). Times in seconds, sizes in px. =====
local PRESETS: { [string]: Preset } = {
	Common    = { length = 0.90, size = 110, scaleFrom = 0.70, overshoot = 1.04, bounce = 0.06, burst = 6,  burstSpread = 40, glow = 0.20, shockwave = false, rotation = 0,  uiBump = 0,    dim = 0,    orbit = 0,  textAt = 0.30, textSlam = false, floatAmp = 2, glowPulse = false },
	Uncommon  = { length = 1.00, size = 116, scaleFrom = 0.65, overshoot = 1.08, bounce = 0.10, burst = 10, burstSpread = 50, glow = 0.35, shockwave = false, rotation = 0,  uiBump = 0,    dim = 0,    orbit = 0,  textAt = 0.30, textSlam = false, floatAmp = 2, glowPulse = false },
	Rare      = { length = 1.10, size = 124, scaleFrom = 0.55, overshoot = 1.14, bounce = 0.12, burst = 14, burstSpread = 60, glow = 0.50, shockwave = true,  rotation = 0,  uiBump = 0,    dim = 0,    orbit = 0,  textAt = 0.30, textSlam = false, floatAmp = 3, glowPulse = false },
	Epic      = { length = 1.35, size = 136, scaleFrom = 0.45, overshoot = 1.20, bounce = 0.14, burst = 20, burstSpread = 75, glow = 0.65, shockwave = true,  rotation = 8,  uiBump = 0.03, dim = 0,    orbit = 0,  textAt = 0.32, textSlam = true,  floatAmp = 3, glowPulse = false },
	Legendary = { length = 1.30, size = 144, scaleFrom = 0.40, overshoot = 1.18, bounce = 0.12, burst = 24, burstSpread = 85, glow = 0.80, shockwave = true,  rotation = 0,  uiBump = 0.03, dim = 0.12, orbit = 10, textAt = 0.40, textSlam = true,  floatAmp = 3, glowPulse = true },
}
-- FACE TO FACE (owner, 2026-09-18): the model opens dead-on to the player and stays
-- there, with a slow +/-SWAY_DEG showcase sway instead of the old CatchReveal's 70 deg/s
-- spin (which showed the back for half of every turn). One sway cycle is longer than
-- any pop, so it never returns past dead-on before the pop closes.
local SWAY_DEG = 18
local SWAY_PERIOD = 2.4  -- seconds per full sway cycle
local FRONT_DIR = Vector3.new(0, 0.45, -1).Unit   -- BrainrotThumb.DEFAULT_DIR's elevation, no side offset
local FOV = 30
local TOP_Y = 78         -- just under the top bar, same anchor CatchReveal used
local FADE_OUT = 0.16
local CATCH_SOUND = { Common = "catchCommon", Uncommon = "catchUncommon", Rare = "catchRare", Epic = "catchEpic", Legendary = "catchLegend" }
local CATCH_VOLUME = { Common = 0.13, Uncommon = 0.17, Rare = 0.21, Epic = 0.25, Legendary = 0.30 }

local M = {}
local gui: ScreenGui? = nil
local live: { [string]: any }? = nil
local token = 0

local function ensureGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "CatchPopUI"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 12
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	return g
end

local function label(parent: Instance, text: string, size: number, color: Color3, strokeT: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UITheme.Font
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.Size = UDim2.fromOffset(10, size + 6)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.ZIndex = 5
	local s = Instance.new("UIStroke")
	s.Thickness = strokeT
	s.Color = Color3.new(0, 0, 0)
	s.Parent = l
	l.Parent = parent
	return l
end

local function teardown(rec: { [string]: any })
	if rec.dead then
		return
	end
	rec.dead = true
	if rec.conn then
		rec.conn:Disconnect()
		rec.conn = nil
	end
	if rec.root then
		rec.root:Destroy()
		rec.root = nil
	end
	if live == rec then
		live = nil
	end
end

function M.isPlaying(): boolean
	return live ~= nil and not live.dead
end

-- Builds the spinning model. Returns the per-frame updater or nil (no model).
-- MUTATION (spec S9): the SAME MutationFX.apply the world uses, on the throwaway
-- viewport clone. Its per-part colour shifts and material swaps render inside a
-- ViewportFrame; its emitters/lights/highlights do not and are simply inert here.
-- One mutation path for pops and cuts alike -- nothing Golden/Diamond-specific.
local function buildViewport(rec: { [string]: any }, preset: Preset, grant: Grant, parent: Instance, mutation: string?): ((number) -> ())?
	local master = BrainrotThumb.master(grant.Name)
	if not master then
		return nil
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Model"
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.ZIndex = 3
	vp.Parent = parent
	local m = master:Clone()
	if mutation then
		pcall(MutationFX.apply, m, mutation)
	end
	m.Parent = vp
	local centre, dist = BrainrotThumb.framing(m, FOV)
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam
	rec.viewport = vp
	return function(t: number)
		local yaw = math.rad(SWAY_DEG) * math.sin(2 * math.pi * t / SWAY_PERIOD)
		local dir = CFrame.Angles(0, yaw, 0) * FRONT_DIR
		cam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	end
end

local function burst(parent: Frame, count: number, spread: number, colour: Color3, rng: Random)
	for i = 1, count do
		local sh = Instance.new("Frame")
		sh.AnchorPoint = Vector2.new(0.5, 0.5)
		sh.Position = UDim2.fromScale(0.5, 0.5)
		sh.Size = UDim2.fromOffset(6, 18)
		sh.BackgroundColor3 = colour
		sh.BorderSizePixel = 0
		sh.Rotation = i * (360 / count) + rng:NextNumber(-8, 8)
		sh.ZIndex = 2
		sh.Parent = parent
		local ang = math.rad(sh.Rotation - 90)
		local d = spread * rng:NextNumber(0.7, 1.2)
		TweenService:Create(sh, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(ang) * d, 0.5, math.sin(ang) * d),
			Size = UDim2.fromOffset(3, 8),
		}):Play()
		task.delay(0.42, function() sh:Destroy() end)
	end
end

local function shockwave(parent: Frame, colour: Color3, size: number): UIStroke
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(size * 0.5, size * 0.5)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 2
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = ring
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = 4
	s.Parent = ring
	ring.Parent = parent
	TweenService:Create(ring, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(size * 1.9, size * 1.9),
	}):Play()
	-- UIStroke.Transparency is not on the Tween allow-list: hand-lerped in the updater
	return s
end

-- grant -> blocks for preset.length (+ fade). Returns false when nothing was shown.
function M.play(grant: Grant): boolean
	if type(grant) ~= "table" or type(grant.Name) ~= "string" then
		return false
	end
	local preset = PRESETS[grant.Rarity or ""] or PRESETS.Common
	if live then
		teardown(live)
	end
	token += 1
	local myToken = token
	local rec: { [string]: any } = { dead = false, token = myToken }
	live = rec
	local accent = typeof(grant.RarityColor) == "Color3" and grant.RarityColor or Color3.fromRGB(190, 190, 190)
	local mut = (type(grant.Mutation) == "string" and grant.Mutation ~= "" and grant.Mutation ~= "None") and grant.Mutation or nil
	local haloColour = accent
	if mut then
		local ok, mc = pcall(Mutations.Color, mut)
		if ok and typeof(mc) == "Color3" then
			haloColour = mc
		end
	end
	local rng = Random.new(myToken)

	local okBuild, err = pcall(function()
		local root = Instance.new("Frame")
		root.Name = "Pop"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.Parent = ensureGui()
		rec.root = root

		if preset.dim > 0 then
			local dim = Instance.new("Frame")
			dim.Name = "Dim"
			dim.Size = UDim2.fromScale(1, 1)
			dim.BackgroundColor3 = Color3.new(0, 0, 0)
			dim.BackgroundTransparency = 1 - preset.dim
			dim.BorderSizePixel = 0
			dim.ZIndex = 1
			dim.Parent = root
			rec.dim = dim
		end

		local holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, TOP_Y)
		holder.Size = UDim2.fromOffset(preset.size, preset.size)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 2
		holder.Parent = root
		rec.holder = holder
		local scale = Instance.new("UIScale")
		scale.Scale = preset.scaleFrom
		scale.Parent = holder
		rec.scale = scale

		local halo = Instance.new("Frame")
		halo.Name = "Halo"
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.5)
		halo.Size = UDim2.fromScale(0.86, 0.86)
		halo.BackgroundColor3 = haloColour
		halo.BackgroundTransparency = 1
		halo.ZIndex = 2
		halo.Parent = holder
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(1, 0)
		hc.Parent = halo
		rec.halo = halo

		rec.spin = buildViewport(rec, preset, grant, holder, mut)

		local stamp = Instance.new("Frame")
		stamp.Name = "Stamp"
		stamp.AnchorPoint = Vector2.new(0.5, 0)
		stamp.Position = UDim2.new(0.5, 0, 0, TOP_Y + preset.size + 8)
		stamp.Size = UDim2.fromOffset(10, 10)
		stamp.AutomaticSize = Enum.AutomaticSize.XY
		stamp.BackgroundTransparency = 1
		stamp.ZIndex = 5
		stamp.Parent = root
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 2)
		list.Parent = stamp
		local header = label(stamp, grant.IsNew and "NEW BRAINROT!" or "YOU GOT!", 20, Color3.fromRGB(255, 240, 200), 2.5)
		header.LayoutOrder = 1
		local nameL = label(stamp, string.upper(Sizes.Label(mut, grant.Size, grant.Name)), 34, Color3.new(1, 1, 1), 4)
		nameL.LayoutOrder = 2
		local tierL = label(stamp, string.upper(grant.Rarity or ""), 22, accent, 3)
		tierL.LayoutOrder = 3
		if grant.Serial then
			local ex = grant.Exists and (" \u{00B7} ONLY " .. tostring(grant.Exists) .. " EXIST") or ""
			label(stamp, "#" .. tostring(grant.Serial) .. ex, 18, Color3.fromRGB(255, 216, 77), 2.5).LayoutOrder = 4
		end
		if grant.OddsN then
			label(stamp, "1 in " .. tostring(grant.OddsN) .. " of its tier", 15, Color3.fromRGB(200, 208, 200), 2).LayoutOrder = 5
		end
		local sScale = Instance.new("UIScale")
		sScale.Scale = 0
		sScale.Parent = stamp
		rec.stampScale = sScale
		rec.stamp = stamp
	end)
	if not okBuild then
		warn("[CatchPop] build failed: " .. tostring(err))
		teardown(rec)
		return false
	end

	if not grant.TierCuePlayed and CATCH_SOUND[grant.Rarity or ""] then
		pcall(SoundKit.play, CATCH_SOUND[grant.Rarity :: string], nil, { volume = CATCH_VOLUME[grant.Rarity :: string] })
	end

	-- ===== the timeline: appear -> bounce+burst -> text -> float -> close =====
	local L = preset.length
	local burstAt = 0.15
	local t = 0
	local burstDone, textDone = false, false
	local strokeRef: UIStroke? = nil
	rec.conn = RunService.RenderStepped:Connect(function(dt)
		if rec.dead then
			return
		end
		t += dt
		local scale = rec.scale :: UIScale
		local holder = rec.holder :: Frame
		local stampScale = rec.stampScale :: UIScale
		-- appear: scaleFrom -> overshoot by burstAt, then settle to 1 with a bounce
		if t < burstAt then
			local p = t / burstAt
			scale.Scale = preset.scaleFrom + (preset.overshoot - preset.scaleFrom) * (1 - (1 - p) * (1 - p))
		else
			local q = math.clamp((t - burstAt) / 0.25, 0, 1)
			local bounce = math.sin(q * math.pi) * preset.bounce
			scale.Scale = preset.overshoot + (1 - preset.overshoot) * q - bounce
		end
		if preset.rotation ~= 0 then
			holder.Rotation = math.sin(t * 6) * preset.rotation * math.max(0, 1 - t / L)
		end
		-- glow
		local halo = rec.halo :: Frame
		local glow = preset.glow * math.clamp(t / 0.3, 0, 1)
		if preset.glowPulse then
			glow = glow * (0.85 + 0.15 * math.sin(t * 9))
		end
		halo.BackgroundTransparency = 1 - glow
		-- burst + shockwave + UI bump, once
		if not burstDone and t >= burstAt then
			burstDone = true
			burst(rec.holder, preset.burst, preset.burstSpread, haloColour, rng)
			if preset.shockwave then
				strokeRef = shockwave(rec.holder, haloColour, preset.size)
			end
			if preset.uiBump > 0 then
				rec.bumpUntil = t + 0.12
			end
		end
		if strokeRef then
			strokeRef.Transparency = math.clamp((t - burstAt) / 0.38, 0, 1)
		end
		if rec.bumpUntil then
			local b = math.clamp((rec.bumpUntil - t) / 0.12, 0, 1)
			scale.Scale = scale.Scale * (1 + preset.uiBump * b)
		end
		-- text
		if not textDone and t >= preset.textAt then
			textDone = true
		end
		if textDone then
			local q = math.clamp((t - preset.textAt) / (preset.textSlam and 0.10 or 0.22), 0, 1)
			local s = preset.textSlam and (1.25 - 0.25 * q) or q
			stampScale.Scale = s
		end
		-- float
		if t > 0.3 then
			holder.Position = UDim2.new(0.5, 0, 0, TOP_Y + math.sin(t * 3) * preset.floatAmp)
		end
		-- orbiting particles (Legendary)
		if preset.orbit > 0 and not rec.orbiters then
			rec.orbiters = {}
			for i = 1, preset.orbit do
				local d = Instance.new("Frame")
				d.AnchorPoint = Vector2.new(0.5, 0.5)
				d.Size = UDim2.fromOffset(6, 6)
				d.BackgroundColor3 = haloColour
				d.BorderSizePixel = 0
				d.ZIndex = 4
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(1, 0)
				c.Parent = d
				d.Parent = rec.holder
				table.insert(rec.orbiters, { d, i * (2 * math.pi / preset.orbit) })
			end
		end
		if rec.orbiters then
			for _, o in ipairs(rec.orbiters) do
				local a = o[2] + t * 2.2
				o[1].Position = UDim2.new(0.5 + math.cos(a) * 0.55, 0, 0.5 + math.sin(a) * 0.55, 0)
			end
		end
		if rec.spin then
			rec.spin(t)
		end
		-- close: fade the viewport and stamp out over FADE_OUT
		if t >= L then
			local f = math.clamp((t - L) / FADE_OUT, 0, 1)
			local viewport = rec.viewport :: ViewportFrame?
			if viewport then
				viewport.ImageTransparency = f
			end
			stampScale.Scale = 1 - f
			halo.BackgroundTransparency = 1 - glow * (1 - f)
			local dim = rec.dim :: Frame?
			if dim then
				dim.BackgroundTransparency = 1 - preset.dim * (1 - f)
			end
			if f >= 1 then
				teardown(rec)
			end
		end
	end)

	while not rec.dead and rec.token == token do
		task.wait(0.05)
	end
	return true
end

return M
