--!strict
-- CatchPop: the Common..Legendary reward reveal (spec S7). ONE beat structure --
-- (anticipation) -> appear -> bounce+burst -> name -> rarity -> float -> close --
-- parameterised by a preset per tier. Screen-space: this module never writes Lighting
-- or another gui's Enabled. Its ONE camera write is a short, self-restoring FOV
-- emphasis on Rare+ (cancelled the instant a takeover cut becomes active), so a pop
-- still has nothing to restore and cannot strand the camera.
-- Built from CatchReveal's viewport machinery and PullCeremony's stamp recipe.
--
-- 2026-09-21 reward-pacing pass:
--   * the router now waits for the stone camera to be HOME before a pop starts
--     (ThrowCamBusy), so "camera settles -> short anticipation -> brainrot appears"
--     happens in that order instead of the pop opening over the water
--   * name and rarity land as two beats (name first, rarity slams a hair later) --
--     the player reads WHAT before the text says how rare
--   * per-tier music duck through MusicDuck (Common/Uncommon none, Rare a touch,
--     Epic small, Legendary a noticeable short one) and a per-tier FOV emphasis
--   * Legendary got its anticipation beat (a glow forms, then the creature) and the
--     1.4-1.8s target; the tier sting comes from CatchCue's one family ladder
--   * a small mutation chip ("GOLDEN  x2") in the mutation's colour -- Golden/Diamond
--     are a material + a label, never a cinematic of their own
--   * the halo is three soft concentric layers, not one flat disc, and the whole pop
--     scales/sits by viewport so phones keep it clear of the top chrome
--   * publishes player attribute RevealPopActive while a pop is on screen so lower-
--     priority popups (PityThrow) can yield
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotThumb = require(Modules:WaitForChild("BrainrotThumb"))
local Mutations = require(Modules:WaitForChild("MutationConfig"))
local MutationFX = require(Modules:WaitForChild("MutationFX"))
local Sizes = require(Modules:WaitForChild("SizeConfig"))
local UITheme = require(Modules:WaitForChild("UITheme"))
local CatchCue = require(Modules:WaitForChild("CatchCue"))
local MusicDuck = require(Modules:WaitForChild("MusicDuck"))
local Platform = require(Modules:WaitForChild("Platform"))

local player = Players.LocalPlayer

export type Grant = {
	Name: string, Rarity: string?, RarityColor: Color3?, Mutation: string?, Size: string?,
	Serial: number?, Exists: number?, IsNew: boolean?, OddsN: number?, TierCuePlayed: boolean?,
}

type Preset = {
	length: number, size: number, scaleFrom: number, overshoot: number, bounce: number,
	burst: number, burstSpread: number, glow: number, shockwave: boolean, rotation: number,
	uiBump: number, dim: number, orbit: number, textAt: number, textSlam: boolean, floatAmp: number,
	glowPulse: boolean, preDelay: number, fov: number, duck: number, duckIn: number, duckOut: number,
}

-- ===== PRESETS (spec S7 table + the 2026-09-21 accents). Times in seconds, sizes in px. =====
-- preDelay: anticipation before the creature appears (glow forms first)
-- fov:      degrees of FOV tighten at the burst, eased back over ~0.35s (0 = none)
-- duck:     music multiplier during the pop (1 = untouched); duckIn/duckOut = ramp seconds
local PRESETS: { [string]: Preset } = {
	Common    = { length = 0.90, size = 110, scaleFrom = 0.70, overshoot = 1.04, bounce = 0.06, burst = 6,  burstSpread = 40, glow = 0.18, shockwave = false, rotation = 0,  uiBump = 0,    dim = 0,    orbit = 0,  textAt = 0.28, textSlam = false, floatAmp = 2, glowPulse = false, preDelay = 0,    fov = 0,   duck = 1,    duckIn = 0,    duckOut = 0 },
	Uncommon  = { length = 1.00, size = 116, scaleFrom = 0.65, overshoot = 1.08, bounce = 0.10, burst = 10, burstSpread = 50, glow = 0.30, shockwave = false, rotation = 0,  uiBump = 0,    dim = 0,    orbit = 0,  textAt = 0.28, textSlam = false, floatAmp = 2, glowPulse = false, preDelay = 0,    fov = 0,   duck = 1,    duckIn = 0,    duckOut = 0 },
	Rare      = { length = 1.10, size = 124, scaleFrom = 0.55, overshoot = 1.14, bounce = 0.12, burst = 14, burstSpread = 60, glow = 0.42, shockwave = true,  rotation = 0,  uiBump = 0,    dim = 0,    orbit = 0,  textAt = 0.30, textSlam = false, floatAmp = 3, glowPulse = false, preDelay = 0,    fov = 1.5, duck = 0.88, duckIn = 0.12, duckOut = 0.6 },
	Epic      = { length = 1.35, size = 136, scaleFrom = 0.45, overshoot = 1.20, bounce = 0.14, burst = 20, burstSpread = 75, glow = 0.55, shockwave = true,  rotation = 8,  uiBump = 0.03, dim = 0.08, orbit = 0,  textAt = 0.32, textSlam = true,  floatAmp = 3, glowPulse = false, preDelay = 0,    fov = 2.5, duck = 0.72, duckIn = 0.12, duckOut = 0.8 },
	Legendary = { length = 1.55, size = 144, scaleFrom = 0.40, overshoot = 1.18, bounce = 0.12, burst = 24, burstSpread = 85, glow = 0.70, shockwave = true,  rotation = 0,  uiBump = 0.04, dim = 0.14, orbit = 10, textAt = 0.42, textSlam = true,  floatAmp = 3, glowPulse = true,  preDelay = 0.14, fov = 3.5, duck = 0.45, duckIn = 0.10, duckOut = 1.0 },
}
-- FACE TO FACE (owner, 2026-09-18): the model opens dead-on to the player and stays
-- there, with a slow +/-SWAY_DEG showcase sway instead of the old CatchReveal's 70 deg/s
-- spin (which showed the back for half of every turn). One sway cycle is longer than
-- any pop, so it never returns past dead-on before the pop closes.
local SWAY_DEG = 18
local SWAY_PERIOD = 2.4  -- seconds per full sway cycle
local FRONT_DIR = Vector3.new(0, 0.45, -1).Unit   -- BrainrotThumb.DEFAULT_DIR's elevation, no side offset
local FOV = 30
local TOP_Y = 78         -- desktop: just under the top bar, same anchor CatchReveal used
local FADE_OUT = 0.16
local BURST_AT = 0.15    -- seconds after the creature appears
local RARITY_LAG = 0.09  -- rarity chip lands this long after the name
local FOV_BACK = 0.38    -- seconds the FOV emphasis takes to ease back
local DUCK_ID = "pop"
local POP_ATTR = "RevealPopActive"

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

-- Geometry by viewport: phones get a smaller pop that sits clear of the top chrome
-- (the currency cluster / luck chip band) and never eats more than a third of the
-- screen height; desktop keeps the tuned pixel sizes.
-- Measured on the iPhone 16 sim (733x371, 2026-09-21): the luck chip sits top-centre at
-- true y 130-174 and the AUTO SKIP button at 257-291, so the pop lives in y 37..~245:
-- model 0.28 of the height from y = 0.10 of it, one compact serial/odds line, and
-- LuckHUDClient hides its chip while RevealPopActive is set on phones.
local function layout(preset: Preset): (number, number, boolean)
	local vp = Platform.Viewport
	local cam = Workspace.CurrentCamera
	local vh = (cam and cam.ViewportSize.Y > 1) and cam.ViewportSize.Y or vp.Y
	local size = preset.size
	local top = TOP_Y
	local compact = false
	if Platform.IsPhone or vh < 480 then
		size = math.floor(math.min(preset.size, vh * 0.28))
		top = math.floor(vh * 0.10)
		compact = true
	elseif Platform.IsTouch then
		size = math.floor(math.min(preset.size, vh * 0.26))
		top = math.max(TOP_Y, math.floor(vh * 0.10))
	end
	return size, top, compact
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
	if rec.fovTween then
		pcall(function()
			rec.fovTween:Cancel()
		end)
		rec.fovTween = nil
	end
	if rec.fovBase and rec.fovApplied then
		-- hand the FOV back if the ease-back was cut short; never touch a Scriptable
		-- camera (a cut owns it now)
		local cam = Workspace.CurrentCamera
		if cam and cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.FieldOfView = rec.fovBase
		end
	end
	if rec.ducked then
		MusicDuck.clear(DUCK_ID, rec.duckOut or 0.6)
		rec.ducked = false
	end
	if live == rec then
		live = nil
		if player then
			player:SetAttribute(POP_ATTR, nil)
		end
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
			BackgroundTransparency = 0.6,
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

-- Three soft concentric layers behind the creature: reads as a glow, not a coin.
type HaloLayer = { frame: Frame, weight: number }
local HALO_LAYERS = { { scale = 0.62, weight = 1.0 }, { scale = 0.86, weight = 0.45 }, { scale = 1.12, weight = 0.18 } }
local function buildHalo(holder: Frame, colour: Color3): { HaloLayer }
	local out: { HaloLayer } = {}
	for i, spec in ipairs(HALO_LAYERS) do
		local h = Instance.new("Frame")
		h.Name = "Halo" .. i
		h.AnchorPoint = Vector2.new(0.5, 0.5)
		h.Position = UDim2.fromScale(0.5, 0.5)
		h.Size = UDim2.fromScale(spec.scale, spec.scale)
		h.BackgroundColor3 = colour
		h.BackgroundTransparency = 1
		h.BorderSizePixel = 0
		h.ZIndex = 2
		h.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = h
		table.insert(out, { frame = h, weight = spec.weight })
	end
	return out
end

local function setHalo(halo: { HaloLayer }, glow: number)
	for _, layer in ipairs(halo) do
		layer.frame.BackgroundTransparency = 1 - glow * layer.weight
	end
end

-- grant -> blocks for preset.length (+ preDelay + fade). Returns false when nothing was shown.
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
	if player then
		player:SetAttribute(POP_ATTR, true)
	end
	local accent = typeof(grant.RarityColor) == "Color3" and grant.RarityColor or Color3.fromRGB(190, 190, 190)
	local mut = (type(grant.Mutation) == "string" and grant.Mutation ~= "" and grant.Mutation ~= "None") and grant.Mutation or nil
	local haloColour = accent
	local mutMult: number? = nil
	if mut then
		local ok, mc = pcall(Mutations.Color, mut)
		if ok and typeof(mc) == "Color3" then
			haloColour = mc
		end
		local okM, mm = pcall(Mutations.Mult, mut)
		if okM and type(mm) == "number" and mm > 1 then
			mutMult = mm
		end
	end
	local rng = Random.new(myToken)
	local size, topY, compact = layout(preset)

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
			dim.BackgroundTransparency = 1
			dim.BorderSizePixel = 0
			dim.ZIndex = 1
			dim.Parent = root
			rec.dim = dim
		end

		local holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, topY)
		holder.Size = UDim2.fromOffset(size, size)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 2
		holder.Parent = root
		rec.holder = holder
		local scale = Instance.new("UIScale")
		scale.Scale = preset.preDelay > 0 and 0 or preset.scaleFrom
		scale.Parent = holder
		rec.scale = scale

		rec.halo = buildHalo(holder, haloColour)

		rec.spin = buildViewport(rec, preset, grant, holder, mut)

		local stamp = Instance.new("Frame")
		stamp.Name = "Stamp"
		stamp.AnchorPoint = Vector2.new(0.5, 0)
		stamp.Position = UDim2.new(0.5, 0, 0, topY + size + 8)
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
		local textMul = (size < preset.size) and math.max(size / preset.size, 0.7) or 1
		local header = label(stamp, grant.IsNew and "NEW BRAINROT!" or "YOU GOT!", math.floor(20 * textMul), Color3.fromRGB(255, 240, 200), 2.5)
		header.LayoutOrder = 1
		local nameL = label(stamp, string.upper(Sizes.Label(mut, grant.Size, grant.Name)), math.floor(34 * textMul), Color3.new(1, 1, 1), 4)
		nameL.LayoutOrder = 2
		-- the rarity chip is its own beat: it lands after the name, with a slam on the
		-- higher tiers, so the player reads the creature before the text rates it
		local tierWrap = Instance.new("Frame")
		tierWrap.Name = "TierWrap"
		tierWrap.BackgroundTransparency = 1
		tierWrap.AutomaticSize = Enum.AutomaticSize.XY
		tierWrap.Size = UDim2.fromOffset(10, 10)
		tierWrap.LayoutOrder = 3
		tierWrap.ZIndex = 5
		tierWrap.Parent = stamp
		local tierL = label(tierWrap, string.upper(grant.Rarity or ""), math.floor(22 * textMul), accent, 3)
		tierL.AnchorPoint = Vector2.new(0.5, 0)
		tierL.Position = UDim2.fromScale(0.5, 0)
		local tScale = Instance.new("UIScale")
		tScale.Scale = 0
		tScale.Parent = tierWrap
		rec.tierScale = tScale
		if mut then
			-- GOLDEN x2 / DIAMOND x5: a material and a label, never a cinematic (spec S3.8)
			local chip = string.upper(mut) .. (mutMult and ("  \u{00D7}" .. tostring(mutMult)) or "")
			label(stamp, chip, math.floor(17 * textMul), haloColour, 2.4).LayoutOrder = 4
		end
		if compact then
			-- one line on phones: the band under the model is short there
			local bits = {}
			if grant.Serial then
				table.insert(bits, "#" .. tostring(grant.Serial) .. (grant.Exists and (" \u{00B7} ONLY " .. tostring(grant.Exists) .. " EXIST") or ""))
			end
			if grant.OddsN then
				table.insert(bits, "1 in " .. tostring(grant.OddsN))
			end
			if #bits > 0 then
				label(stamp, table.concat(bits, " \u{00B7} "), math.floor(15 * textMul), Color3.fromRGB(255, 216, 77), 2.2).LayoutOrder = 5
			end
		else
			if grant.Serial then
				local ex = grant.Exists and (" \u{00B7} ONLY " .. tostring(grant.Exists) .. " EXIST") or ""
				label(stamp, "#" .. tostring(grant.Serial) .. ex, math.floor(18 * textMul), Color3.fromRGB(255, 216, 77), 2.5).LayoutOrder = 5
			end
			if grant.OddsN then
				label(stamp, "1 in " .. tostring(grant.OddsN) .. " of its tier", math.floor(15 * textMul), Color3.fromRGB(200, 208, 200), 2).LayoutOrder = 6
			end
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

	-- music: the duck starts with the anticipation so the sting lands in a hole
	if preset.duck < 1 then
		MusicDuck.set(DUCK_ID, preset.duck, preset.duckIn)
		rec.ducked = true
		rec.duckOut = preset.duckOut
	end

	-- ===== the timeline: (anticipation) -> appear -> bounce+burst -> name -> rarity -> float -> close =====
	local L = preset.length
	local pre = preset.preDelay
	local burstAt = pre + BURST_AT
	local textAt = pre + preset.textAt
	local tierAt = textAt + RARITY_LAG
	local t = 0
	local stingDone, burstDone, textDone, tierDone = false, false, false, false
	local strokeRef: UIStroke? = nil
	rec.conn = RunService.RenderStepped:Connect(function(dt)
		if rec.dead then
			return
		end
		t += dt
		local scale = rec.scale :: UIScale
		local holder = rec.holder :: Frame
		local stampScale = rec.stampScale :: UIScale
		local halo = rec.halo :: { HaloLayer }
		-- anticipation (Legendary): the glow forms first, the creature is not there yet
		if t < pre then
			scale.Scale = 0.001
			setHalo(halo, preset.glow * 0.6 * (t / pre))
			local dim = rec.dim :: Frame?
			if dim then
				dim.BackgroundTransparency = 1 - preset.dim * (t / pre)
			end
			return
		end
		local tt = t - pre
		-- the sting lands with the creature, not with the anticipation
		if not stingDone then
			stingDone = true
			if not grant.TierCuePlayed then
				pcall(CatchCue.PlayTier, grant.Rarity or "", 1)
			end
		end
		-- appear: scaleFrom -> overshoot by BURST_AT, then settle to 1 with a bounce
		if tt < BURST_AT then
			local p = tt / BURST_AT
			scale.Scale = preset.scaleFrom + (preset.overshoot - preset.scaleFrom) * (1 - (1 - p) * (1 - p))
		else
			local q = math.clamp((tt - BURST_AT) / 0.25, 0, 1)
			local bounce = math.sin(q * math.pi) * preset.bounce
			scale.Scale = preset.overshoot + (1 - preset.overshoot) * q - bounce
		end
		if preset.rotation ~= 0 then
			holder.Rotation = math.sin(tt * 6) * preset.rotation * math.max(0, 1 - tt / L)
		end
		-- glow
		local glow = preset.glow * math.clamp(0.6 + 0.4 * (tt / 0.3), 0, 1)
		if pre <= 0 then
			glow = preset.glow * math.clamp(tt / 0.3, 0, 1)
		end
		if preset.glowPulse then
			glow = glow * (0.85 + 0.15 * math.sin(tt * 9))
		end
		setHalo(halo, glow)
		local dim = rec.dim :: Frame?
		if dim and tt < L then
			dim.BackgroundTransparency = 1 - preset.dim
		end
		-- burst + shockwave + UI bump + FOV emphasis, once
		if not burstDone and t >= burstAt then
			burstDone = true
			burst(rec.holder, preset.burst, preset.burstSpread, haloColour, rng)
			if preset.shockwave then
				strokeRef = shockwave(rec.holder, haloColour, size)
			end
			if preset.uiBump > 0 then
				rec.bumpUntil = t + 0.12
			end
			if preset.fov > 0 then
				local cam = Workspace.CurrentCamera
				if cam and cam.CameraType ~= Enum.CameraType.Scriptable then
					rec.fovBase = cam.FieldOfView
					rec.fovApplied = true
					cam.FieldOfView = rec.fovBase - preset.fov
					rec.fovTween = TweenService:Create(cam, TweenInfo.new(FOV_BACK, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = rec.fovBase })
					rec.fovTween:Play()
					task.delay(FOV_BACK + 0.05, function()
						rec.fovApplied = false
					end)
				end
			end
		end
		if rec.fovApplied then
			-- a cut took the camera mid-emphasis: stop touching it at once
			local cam = Workspace.CurrentCamera
			if cam and cam.CameraType == Enum.CameraType.Scriptable and rec.fovTween then
				pcall(function() rec.fovTween:Cancel() end)
				rec.fovTween = nil
				rec.fovApplied = false
			end
		end
		if strokeRef then
			strokeRef.Transparency = math.clamp((t - burstAt) / 0.38, 0, 1)
		end
		if rec.bumpUntil then
			local b = math.clamp((rec.bumpUntil - t) / 0.12, 0, 1)
			scale.Scale = scale.Scale * (1 + preset.uiBump * b)
		end
		-- name, then rarity
		if not textDone and t >= textAt then
			textDone = true
		end
		if textDone then
			local q = math.clamp((t - textAt) / (preset.textSlam and 0.10 or 0.22), 0, 1)
			local s = preset.textSlam and (1.25 - 0.25 * q) or q
			stampScale.Scale = s
		end
		if not tierDone and t >= tierAt then
			tierDone = true
		end
		if tierDone then
			local q = math.clamp((t - tierAt) / (preset.textSlam and 0.12 or 0.2), 0, 1)
			local s = preset.textSlam and (1.5 - 0.5 * (1 - (1 - q) ^ 3)) or (1 - (1 - q) ^ 2)
			local ts = rec.tierScale :: UIScale
			ts.Scale = s
		end
		-- float
		if tt > 0.3 then
			holder.Position = UDim2.new(0.5, 0, 0, topY + math.sin(tt * 3) * preset.floatAmp)
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
				local a = o[2] + tt * 2.2
				o[1].Position = UDim2.new(0.5 + math.cos(a) * 0.55, 0, 0.5 + math.sin(a) * 0.55, 0)
			end
		end
		if rec.spin then
			rec.spin(tt)
		end
		-- close: fade the viewport and stamp out over FADE_OUT
		if tt >= L then
			local f = math.clamp((tt - L) / FADE_OUT, 0, 1)
			local viewport = rec.viewport :: ViewportFrame?
			if viewport then
				viewport.ImageTransparency = f
			end
			stampScale.Scale = 1 - f
			setHalo(halo, glow * (1 - f))
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
