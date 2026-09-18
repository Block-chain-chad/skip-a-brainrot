--!strict
-- CatchCinematic.RockRig -- the thrown rock during a cut. The server destroys its
-- own stone for every client on a cinematic throw, so this stages the final skip
-- contact: the rock sits on the surface at t=0, sinks over cfg.sinkSeconds with a
-- slow tumble, then hides. No ricochet, no second bonk (removed 2026-09-17 with the
-- comedy layer -- spec S8).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RockDesign = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RockDesign"))

export type RockRigCfg = { sinkSeconds: number?, sinkDepth: number?, spinRadPerSec: number? }
export type Rig = typeof(setmetatable({} :: { [string]: any }, {} :: { __index: any }))

local RockRig = {}
RockRig.__index = RockRig

function RockRig.new(cfg: RockRigCfg, stage: Folder, rockId: string?, rockColor: Color3?, surface: Vector3, rng: Random): Rig
	local self = setmetatable({}, RockRig)
	self.cfg = cfg
	self.surface = surface
	self.rng = rng
	self._destroyed = false
	local model = RockDesign.Build(rockId, rockColor or Color3.fromRGB(105, 100, 96))
	model.Name = "CinematicRock"
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	model:PivotTo(CFrame.new(surface + Vector3.new(0, 0.4, 0)))
	model.Parent = stage
	self.model = model
	self.hidden = false
	return (self :: any) :: Rig
end

-- Pure in t (cinematic seconds). Sink from the surface to -sinkDepth over sinkSeconds
-- with a slow tumble, then hide.
function RockRig:update(t: number)
	if self._destroyed or self.hidden then
		return
	end
	local secs = math.max(self.cfg.sinkSeconds or 0.8, 0.05)
	local depth = self.cfg.sinkDepth or 2.0
	local spin = self.cfg.spinRadPerSec or 2.0
	local p = math.clamp(t / secs, 0, 1)
	local y = 0.4 - depth * p * p
	local cf = CFrame.new(self.surface + Vector3.new(0, y, 0)) * CFrame.Angles(spin * t, spin * 0.7 * t, 0)
	self.model:PivotTo(cf)
	if p >= 1 then
		self.hidden = true
		for _, d in ipairs(self.model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Transparency = 1
			end
		end
	end
end

function RockRig:cleanup()
	if self._destroyed then
		return
	end
	self._destroyed = true
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

return RockRig
