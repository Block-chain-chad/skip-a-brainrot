--!strict
-- CatchCinematic.BeamFX -- the heavenly beam: a neon core column + a wide translucent
-- outer column + a base light, from a base point straight up. fire() grows it from
-- nothing; fade() takes it away; setBase() re-anchors it (Massive God: on the rig);
-- setAlpha() drives it directly from a beat clock (the "tiny light grows" beat).
local BeamFX = {}
BeamFX.__index = BeamFX

export type Beam = typeof(setmetatable({} :: { [string]: any }, BeamFX))

local function decor(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Locked = true
end

function BeamFX.new(stage: Folder, basePos: Vector3, color: Color3, height: number, radius: number, quality: string): Beam
	local self = setmetatable({}, BeamFX)
	self._base = basePos
	self._height = height
	self._radius = radius
	self._color = color
	self._quality = quality
	self._destroyed = false
	self._alpha = 0
	self._gen = 0
	self._parts = {}

	local core = Instance.new("Part")
	core.Name = "BeamCore"
	core.Shape = Enum.PartType.Cylinder
	core.Material = Enum.Material.Neon
	core.Color = Color3.new(1, 1, 1):Lerp(color, 0.35)
	core.Transparency = 1
	decor(core)
	core.Parent = stage
	self._core = core
	table.insert(self._parts, core)

	local outer = Instance.new("Part")
	outer.Name = "BeamOuter"
	outer.Shape = Enum.PartType.Cylinder
	outer.Material = Enum.Material.ForceField
	outer.Color = color
	outer.Transparency = 1
	decor(outer)
	outer.Parent = stage
	self._outer = outer
	table.insert(self._parts, outer)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 0
	light.Range = 60
	light.Parent = core
	self._light = light

	self:_apply()
	return (self :: any) :: Beam
end

function BeamFX:_apply()
	local a = self._alpha
	local h = math.max(self._height * a, 0.1)
	local mid = self._base + Vector3.new(0, h / 2, 0)
	local cf = CFrame.new(mid) * CFrame.Angles(0, 0, math.rad(90))
	self._core.Size = Vector3.new(h, self._radius * 2 * a, self._radius * 2 * a)
	self._core.CFrame = cf
	self._core.Transparency = 1 - 0.85 * a
	self._outer.Size = Vector3.new(h, self._radius * 5 * a, self._radius * 5 * a)
	self._outer.CFrame = cf
	self._outer.Transparency = 1 - 0.35 * a
	self._light.Brightness = 6 * a
end

function BeamFX:setBase(pos: Vector3)
	self._base = pos
	self:_apply()
end

local function ramp(self: any, to: number, seconds: number)
	local from = self._alpha
	self._gen += 1
	local myGen = self._gen
	task.spawn(function()
		local t0 = os.clock()
		while not self._destroyed and self._gen == myGen do
			local a = math.clamp((os.clock() - t0) / math.max(seconds, 0.05), 0, 1)
			self._alpha = from + (to - from) * (a * a * (3 - 2 * a))
			self:_apply()
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Direct level, no ramp: Massive God's "tiny gold light grows" beat drives this per
-- frame from the conductor's clock.
function BeamFX:setAlpha(a: number)
	if self._destroyed then
		return
	end
	self._gen += 1 -- cancels any in-flight ramp
	self._alpha = math.clamp(a, 0, 1)
	self:_apply()
end

function BeamFX:fire(seconds: number)
	if self._destroyed then
		return
	end
	ramp(self, 1, seconds)
end

function BeamFX:fade(seconds: number)
	if self._destroyed then
		return
	end
	ramp(self, 0, seconds)
end

function BeamFX:cleanup()
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

return BeamFX
