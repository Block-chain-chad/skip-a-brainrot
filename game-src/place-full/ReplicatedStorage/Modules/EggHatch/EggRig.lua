--!strict
-- EggHatch.EggRig: one egg on the stage. Built from the same EggArt recipe as the shop
-- card and the shelf, plus what only a hatch needs: two subtle crack lines, six small
-- shards for the pop and a core light. The pose driver is a pure function of the rig's
-- local time against its `plan` (beat times the controller already scaled), so speed
-- controls and batches never touch this file.
--
-- THE MOTION IS SQUASH / STRETCH + ROTATION + TIMING. Every part is written each frame
-- from its canonical transform through a non-uniform scale (sy tall/short, sx = sz
-- volume-preserving) and a lean about the BASE of the egg -- an egg on a floor leans on
-- the point it touches. There is no Model:ScaleTo in the loop and no physics; the egg
-- itself carries the anticipation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggArt = require(ReplicatedStorage.Modules.EggArt)
local Config = require(script.Parent.Config)

local TAU = math.pi * 2

local EggRig = {}
EggRig.__index = EggRig

export type Plan = {
	enter: number, enterLen: number, settle: number, settleLen: number,
	lean: { { number } },       -- { time, degrees } keyframes (already offset)
	squash: number, squashLen: number, shake: number, shakeLen: number,
	pop: number,
}

export type Opts = {
	key: string, height: number, slot: Vector3, accent: Color3, seed: number?, light: number?,
}

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function easeOut(u: number): number
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) * (1 - u)
end

local function backOut(u: number, k: number?): number
	u = math.clamp(u, 0, 1)
	local s = k or 1.70158
	local x = u - 1
	return x * x * ((s + 1) * x + s) + 1
end

local function mkPart(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = parent
	return p
end

-- ---------------------------------------------------------------- build
function EggRig.new(stage, opts: Opts)
	local self = setmetatable({}, EggRig) :: any
	self.stage = stage
	self.opts = opts
	self.slot = opts.slot
	self.h = opts.height
	self.rng = Random.new(opts.seed or 7)
	self.dead = false
	self.popped = false
	self.popAt = nil
	self.crackStage = 0
	self.shown = false

	local build = EggArt.build(opts.key, { noScale = true }) or EggArt.build("ForestEgg1", { noScale = true })
	if not build then
		self.dead = true
		return self
	end
	self.build = build
	local model = build.model
	self.model = model
	local recipe = build.recipe
	local scale = opts.height / build.canonH
	self.baseScale = scale
	local top, bottom = EggArt.topOf(recipe), EggArt.bottomOf(recipe)
	self.centreY = (top + bottom) * 0.5 - bottom   -- above the base, canonical

	-- two subtle crack lines on the front, hidden until the wind-up
	local cracks = {}
	local function line(theta0: number, y0: number, steps: number, dirY: number, dirT: number)
		local th, y = theta0, y0
		for i = 1, steps do
			local turn = self.rng:NextNumber(-0.5, 0.5)
			local th2 = th + (dirT + turn * 0.6) * 0.15
			local y2 = math.clamp(y + (dirY + turn * 0.4) * 0.13, bottom + 0.2, top - 0.15)
			local a, b = EggArt.frameOn(recipe, th, y, 0.01), EggArt.frameOn(recipe, th2, y2, 0.01)
			local seg = b.Position - a.Position
			local up = (a.UpVector + b.UpVector).Unit
			local tangent = seg - up * seg:Dot(up)
			if tangent.Magnitude > 1e-4 then
				local right = tangent.Unit
				local back = right:Cross(up).Unit
				cracks[#cracks + 1] = mkPart(model, "crack", Vector3.new(seg.Magnitude * 1.06, 0.024, 0.026), CFrame.fromMatrix(a.Position:Lerp(b.Position, 0.5), right, up, back), recipe.dark, Enum.Material.SmoothPlastic)
			end
			th, y = th2, y2
			dirT += turn * 0.25
		end
	end
	line(0.25, (top + bottom) * 0.5 - 0.1, 5, 1.0, -0.8)
	line(-0.30, (top + bottom) * 0.5 + 0.25, 4, -1.0, 0.9)
	self.cracks = cracks

	-- six small shards on the shell for the pop, hidden until then
	local shards = {}
	local shell = build.shells[1]
	for i = 1, 6 do
		local th = self.rng:NextNumber(-1.4, 1.4) + ((i % 2 == 0) and math.pi or 0)
		local y = self.rng:NextNumber(bottom + 0.35, top - 0.3)
		shards[#shards + 1] = mkPart(model, "shard", Vector3.new(self.rng:NextNumber(0.16, 0.26), 0.05, self.rng:NextNumber(0.14, 0.22)), EggArt.frameOn(recipe, th, y, 0.0), EggArt.mul(shell.Color, 0.95), shell.Material)
	end
	self.shards = shards

	-- the core light (no visible ball): it leaks through the neon cracks and onto the
	-- floor as the wind-up builds, then flashes for a beat at the pop
	local core = mkPart(model, "core", Vector3.one * 0.2, CFrame.new(0, (top + bottom) * 0.5, 0), opts.accent, Enum.Material.SmoothPlastic)
	self.core = core
	local light = Instance.new("PointLight")
	light.Color = opts.accent
	light.Brightness = 0
	light.Range = 0
	light.Shadows = false
	light.Parent = core
	self.light = light
	self.lightRange = opts.height * 2.6

	-- canonical transforms relative to the base pivot, pre-scaled to the stage height
	local baseCF = CFrame.new(0, bottom, 0)
	local recs = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local rel = baseCF:ToObjectSpace(p.CFrame)
			recs[#recs + 1] = {
				part = p, pos = rel.Position * scale, rot = rel.Rotation, size = p.Size * scale,
				transp = p.Transparency,
			}
		end
	end
	self.recs = recs
	return self
end

-- ---------------------------------------------------------------- crack stages
function EggRig:setCracks(stage: number)
	if self.dead or stage <= self.crackStage then return end
	self.crackStage = stage
	local n = #self.cracks
	local show = (stage == 1) and math.ceil(n * 0.5) or n
	for i, p in ipairs(self.cracks) do
		if i <= show then
			p.Transparency = 0
			if stage >= 2 then
				p.Material = Enum.Material.Neon
				p.Color = self.opts.accent
			end
		end
	end
end

-- ---------------------------------------------------------------- the pop
-- Called by the driver once tl passes plan.pop + POP_HOLD: the shell is gone, six
-- shards fly for a quarter second, the core flashes.
local POP_HOLD = 0.045
function EggRig:pop(now: number)
	if self.dead or self.popped then return end
	self.popped = true
	self.popAt = now
	local stage = self.stage
	local inv = stage.frame:Inverse()
	local eggCF = self.eggCF or (stage.frame * CFrame.new(self.slot))
	local centre = inv * (eggCF * CFrame.new(0, self.centreY * self.baseScale, 0))
	local debris = {}
	for _, r in ipairs(self.recs) do
		local p = r.part
		if p.Name == "shard" then
			p.Transparency = 0
			local localCF = inv * p.CFrame
			local dir = localCF.Position - centre.Position
			dir = (dir.Magnitude > 1e-3) and dir.Unit or Vector3.yAxis
			debris[#debris + 1] = {
				part = p, cf = localCF,
				vel = dir * (2.6 + self.rng:NextNumber(0, 1.4)) * self.h + Vector3.new(0, (0.6 + self.rng:NextNumber(0, 0.8)) * self.h, 0),
				axis = Vector3.new(self.rng:NextNumber(-1, 1), self.rng:NextNumber(-1, 1), self.rng:NextNumber(-1, 1)).Unit,
				spin = self.rng:NextNumber(8, 16),
			}
		else
			p.Transparency = 1
		end
	end
	self.debris = debris
	self.light.Brightness = 1.8 * (self.opts.light or 1)
	self.light.Range = self.lightRange * 1.3
	self.coreLocal = inv * self.core.CFrame
end

-- ---------------------------------------------------------------- per frame
local SHARD_LIFE, SHARD_FADE = 0.22, 0.14

function EggRig:update(dt: number, tl: number, plan: Plan)
	if self.dead then return end
	local stage = self.stage
	local model = self.model

	if self.popped then
		local age = tl - self.popAt
		local g = 11 * self.h
		local f = (age > SHARD_LIFE) and math.clamp((age - SHARD_LIFE) / SHARD_FADE, 0, 1) or 0
		for _, d in ipairs(self.debris) do
			d.vel = d.vel + Vector3.new(0, -g * dt, 0)
			d.cf = CFrame.new(d.vel * dt) * d.cf * CFrame.fromAxisAngle(d.axis, d.spin * dt)
			d.part.CFrame = stage.frame * d.cf
			if f > 0 then d.part.Transparency = f end
		end
		self.core.CFrame = stage.frame * self.coreLocal
		self.light.Brightness = math.max(0, 1.8 * (self.opts.light or 1) * (1 - age / 0.3))
		if age > SHARD_LIFE + SHARD_FADE and not self.retired then
			self.retired = true
			for _, d in ipairs(self.debris) do d.part.Transparency = 1 end
		end
		return
	end

	if tl < 0 then return end
	if not self.shown then
		self.shown = true
		model.Parent = stage.folder
	end

	-- ---------------------------------------------------- channels
	local h = self.h
	local uni = 1          -- uniform scale
	local sy = 1           -- vertical squash/stretch (sx = sz follow, volume-preserving)
	local lean, leanZ, yaw = 0, 0, 0
	local dx, dy, dz = 0, 0, 0
	local B = plan

	-- ENTER: pops into the foreground -- small and a touch further back, rising
	if tl < B.enterLen then
		local u = tl / B.enterLen
		uni = 0.18 + 0.82 * backOut(u, 2.4)
		dy = -0.26 * h * (1 - easeOut(u))
		dz = -2.8 * (1 - easeOut(u))
	end
	-- SETTLE: the landing squash, then a small stretch back
	do
		local u = (tl - B.settle) / B.settleLen
		if u > 0 and u < 1 then
			sy *= 1 - 0.20 * math.sin(math.pi * u)
		elseif u >= 1 and u < 1.6 then
			sy *= 1 + 0.07 * math.sin(math.pi * (u - 1) / 0.6)
		end
	end
	-- LEANS: keyframed, eased, about the base; a lean stretches the egg a little
	do
		local keys = B.lean
		local first, last = keys[1], keys[#keys]
		if tl >= first[1] and tl <= last[1] then
			for i = 1, #keys - 1 do
				local a, b = keys[i], keys[i + 1]
				if tl >= a[1] and tl <= b[1] then
					local u = (tl - a[1]) / math.max(1e-3, b[1] - a[1])
					local deg = a[2] + (b[2] - a[2]) * smooth(u)
					lean = math.rad(deg)
					-- the far side lifts: a lean is also a small hop on the leaning edge,
					-- and the egg stretches a little along the lean
					dy += 0.02 * h * math.abs(math.sin(math.pi * u))
					sy *= 1 + 0.07 * math.abs(deg) / 20
					yaw = math.rad(deg) * 0.10
					break
				end
			end
		end
	end
	-- SQUASH: the wind-up compression, held into the shake
	local comp = 0
	do
		local u = (tl - B.squash) / B.squashLen
		if u > 0 then comp = 0.26 * smooth(u) end
	end
	-- SHAKE: rapid, small, releasing the compression into a stretch (a spring loading)
	do
		local u = (tl - B.shake) / B.shakeLen
		if u > 0 and u < 1 then
			lean += math.rad(5) * math.sin(TAU * 16 * u)
			leanZ += math.rad(3.5) * math.sin(TAU * 21 * u + 1.0)
			dx += 0.018 * h * math.sin(TAU * 30 * u)
			comp = 0.26 - 0.44 * smooth(u)   -- 0.26 compressed -> -0.18 stretched
		elseif u >= 1 then
			comp = -0.18
		end
	end
	sy *= 1 - comp
	-- POP: one sharp punch outward, then the driver pops the shell
	if tl >= B.pop then
		local u = (tl - B.pop) / POP_HOLD
		if u >= 1 then
			self:pop(tl)
			return
		end
		uni *= 1 + 0.16 * (1 - u * 0.5)
		sy *= 1.06
	end
	-- crack light: builds through the wind-up
	if self.crackStage >= 1 then
		local k = (self.crackStage >= 2) and 1.0 or 0.4
		local shakeU = math.clamp((tl - B.shake) / B.shakeLen, 0, 1)
		self.light.Brightness = (0.5 + 1.1 * shakeU) * k * (self.opts.light or 1)
		self.light.Range = self.lightRange
	end
	yaw += math.sin(tl * 2.1 + self.slot.X) * 0.03

	-- ---------------------------------------------------- write every part
	local sx = uni / math.sqrt(math.max(0.2, sy))
	sy = sy * uni
	local S = Vector3.new(sx, sy, sx)
	local eggCF = stage.frame * CFrame.new(self.slot + Vector3.new(dx, dy, dz)) * CFrame.Angles(lean, yaw, leanZ)
	self.eggCF = eggCF
	for _, r in ipairs(self.recs) do
		local rot = r.rot
		local p = r.pos * S
		local fx = Vector3.new(rot.XVector.X * sx, rot.XVector.Y * sy, rot.XVector.Z * sx).Magnitude
		local fy = Vector3.new(rot.YVector.X * sx, rot.YVector.Y * sy, rot.YVector.Z * sx).Magnitude
		local fz = Vector3.new(rot.ZVector.X * sx, rot.ZVector.Y * sy, rot.ZVector.Z * sx).Magnitude
		local part = r.part
		part.Size = Vector3.new(r.size.X * fx, r.size.Y * fy, r.size.Z * fz)
		part.CFrame = eggCF * CFrame.new(p) * rot
	end
end

-- world CFrame of the egg's centre right now
function EggRig:centreWorld(): CFrame
	return (self.eggCF or self.stage.frame * CFrame.new(self.slot)) * CFrame.new(0, self.centreY * self.baseScale, 0)
end

function EggRig:destroy()
	if self.dead then return end
	self.dead = true
	if self.model then self.model:Destroy() end
end

return EggRig
