--!strict
-- CatchCinematic.AuraFX -- a large rift/aura plane behind a creature plus orbiting
-- emitters: Secret's pink rift, God's descent glow. Owns its parts; cleanup()
-- destroys them. Rotation is driven by update(t) from the conductor's clock.
local AuraFX = {}
AuraFX.__index = AuraFX

export type Aura = typeof(setmetatable({} :: { [string]: any }, AuraFX))

local function decor(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Locked = true
end

-- opts.disc = false (2026-09-21): orbiting sparkles only -- no rift plane, no ring. The
-- Mythic cut frames its creature with this; the flat planes stay for Secret's rift and
-- God's descent glow, where "behind the creature" is the design.
function AuraFX.new(stage: Folder, pos: Vector3, color: Color3, radius: number, quality: string, rng: Random, opts: { disc: boolean? }?): Aura
	local self = setmetatable({}, AuraFX)
	self._pos = pos
	self._radius = radius
	self._destroyed = false
	self._parts = {}
	self._emitters = {}
	self._alpha = 0
	local withDisc = not (opts and opts.disc == false)

	-- the emitters need a host part either way; with no disc it is an invisible one
	local disc = Instance.new("Part")
	disc.Name = withDisc and "AuraRift" or "AuraHost"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = 1
	disc.Size = withDisc and Vector3.new(0.2, radius * 2, radius * 2) or Vector3.new(0.2, 0.2, 0.2)
	decor(disc)
	disc.Parent = stage
	self._disc = disc
	self._withDisc = withDisc
	table.insert(self._parts, disc)

	if withDisc then
		local ring = Instance.new("Part")
		ring.Name = "AuraRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.new(1, 1, 1):Lerp(color, 0.5)
		ring.Transparency = 1
		ring.Size = Vector3.new(0.25, radius * 2.3, radius * 2.3)
		decor(ring)
		ring.Parent = stage
		self._ring = ring
		table.insert(self._parts, ring)
	end

	local count = (quality == "low") and 1 or 3
	for i = 1, count do
		local a = Instance.new("Attachment")
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(color)
		e.Rate = (quality == "low") and 12 or 30
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(2, 5)
		e.Size = NumberSequence.new(0.6, 0)
		e.Transparency = NumberSequence.new(0.2, 1)
		e.LightEmission = 1
		e.Enabled = false
		e.Parent = a
		a.Parent = disc
		table.insert(self._emitters, { a, e, i * (2 * math.pi / count) + rng:NextNumber(0, 1) })
	end
	self:_place(0)
	return (self :: any) :: Aura
end

function AuraFX:_place(t: number)
	local cam = workspace.CurrentCamera
	local look = cam and (cam.CFrame.Position - self._pos).Unit or Vector3.new(0, 0, -1)
	-- cylinder axis is X: rotate so the flat face looks at the camera, then spin
	local base = CFrame.lookAt(self._pos, self._pos + look) * CFrame.Angles(0, math.rad(90), 0)
	self._disc.CFrame = base * CFrame.Angles(t * 0.6, 0, 0)
	if self._ring then
		self._ring.CFrame = base * CFrame.Angles(-t * 0.9, 0, 0)
	end
	for _, rec in ipairs(self._emitters) do
		local ang = rec[3] + t * 1.4
		rec[1].Position = Vector3.new(0, math.cos(ang) * self._radius * 0.8, math.sin(ang) * self._radius * 0.8)
	end
end

-- alpha 0..1: how present the aura is. Hand-set (Transparency is on the allow-list,
-- but the aura tracks the clock, so it is written per frame rather than tweened).
-- The planes never go past 0.45 / 0.4 opaque (the ring was 0.7): they are a glow
-- behind the creature, not a shape in front of the water.
function AuraFX:update(t: number, alpha: number?)
	if self._destroyed then
		return
	end
	if alpha then
		self._alpha = math.clamp(alpha, 0, 1)
	end
	if self._withDisc then
		self._disc.Transparency = 1 - 0.45 * self._alpha
		if self._ring then
			self._ring.Transparency = 1 - 0.4 * self._alpha
		end
	end
	for _, rec in ipairs(self._emitters) do
		rec[2].Enabled = self._alpha > 0.2
	end
	self:_place(t)
end

function AuraFX:setPos(pos: Vector3)
	self._pos = pos
end

function AuraFX:fade(seconds: number)
	if self._destroyed then
		return
	end
	local a0 = self._alpha
	task.spawn(function()
		local t0 = os.clock()
		while not self._destroyed do
			local a = math.clamp((os.clock() - t0) / math.max(seconds, 0.05), 0, 1)
			self._alpha = a0 * (1 - a)
			if self._withDisc then
				self._disc.Transparency = 1 - 0.45 * self._alpha
				if self._ring then
					self._ring.Transparency = 1 - 0.4 * self._alpha
				end
			end
			if a >= 1 then
				for _, rec in ipairs(self._emitters) do
					rec[2].Enabled = false
				end
				break
			end
			task.wait()
		end
	end)
end

function AuraFX:cleanup()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, p in ipairs(self._parts) do
		pcall(function()
			p:Destroy()
		end)
	end
	self._parts = {}
end

return AuraFX
