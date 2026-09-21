--!strict
-- EggHatch.RewardRig: the hatched creature on the stage. Clones the real model
-- (PetModels by PetConfig.Model, then BrainrotThumb's masters for the retired stand-ins),
-- fits it to a target on-screen height, turns its FACE to the camera, pops it out of
-- the egg with a squash on landing, and keeps it alive with a bob and sway until the
-- run ends, when it scales away. Nothing here is text: the plate is a separate module
-- that only exists once this rig is visible, which is what keeps the reward unspoiled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PetConfig = require(Modules:WaitForChild("PetConfig"))
local BrainrotThumb = require(Modules:WaitForChild("BrainrotThumb"))
local okFX, MutationFX = pcall(function() return require(Modules:WaitForChild("MutationFX")) end)
if not okFX then MutationFX = nil end

local RewardRig = {}
RewardRig.__index = RewardRig

export type Opts = {
	name: string, petId: string?, mutation: string?, height: number, slot: Vector3,
	sizeMult: number?, pop: number?, bounce: number?,
}

local function backOut(u: number, k: number): number
	u = math.clamp(u, 0, 1)
	local x = u - 1
	return x * x * ((k + 1) * x + k) + 1
end

local function easeIn(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u
end

local masters: { [string]: Model } = {}
local function master(name: string, petId: string?): Model?
	local key = petId or name
	if masters[key] then return masters[key] end
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local def = petId and PetConfig.Pets[petId]
	local src = folder and ((def and def.Model and folder:FindFirstChild(def.Model)) or folder:FindFirstChild(name))
	local m: Model? = nil
	if src and src:IsA("Model") then
		m = src:Clone()
	else
		local ok, bm = pcall(BrainrotThumb.master, name)
		if ok and bm then m = bm end
	end
	if m then
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			elseif d:IsA("Script") or d:IsA("LocalScript") then
				d:Destroy()
			end
		end
		masters[key] = m
	end
	return m
end

-- Which way the model FACES, measured on the model itself. There is no single correct
-- yaw across the pet roster (the previous ceremony measured 191 models and found the
-- authored "front" spread round the whole circle), so it is read from the strongest
-- signal available: named eye parts, then a HeadAttachment, then the pivot's look.
local function facingOf(model: Model): Vector3
	local bcf, bsz = model:GetBoundingBox()
	local centre = bcf.Position
	local minXZ = 0.08 * math.max(bsz.X, bsz.Z)
	local sum, n = Vector3.zero, 0
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name:lower():find("eye") then
			sum += p.Position
			n += 1
		end
	end
	if n > 0 then
		local d = sum / n - centre
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > minXZ then return d.Unit end
	end
	for _, a in ipairs(model:GetDescendants()) do
		if a:IsA("Attachment") and a.Name == "HeadAttachment" then
			local d = a.WorldPosition - centre
			d = Vector3.new(d.X, 0, d.Z)
			if d.Magnitude > minXZ then return d.Unit end
		end
	end
	local lv = model:GetPivot().LookVector
	local d = Vector3.new(lv.X, 0, lv.Z)
	return (d.Magnitude > 0.01) and d.Unit or Vector3.zAxis
end

function RewardRig.new(stage, opts: Opts)
	local self = setmetatable({}, RewardRig) :: any
	self.stage = stage
	self.opts = opts
	self.slot = opts.slot
	self.h = opts.height * (opts.sizeMult or 1)
	self.mode = "hidden"
	self.dead = false
	self.popK = ((opts.pop or 1.12) - 1) * 17   -- Back overshoot constant: 1.7 = 10 %
	self.bounce = opts.bounce or 0
	self.exitT = nil

	local src = master(opts.name, opts.petId)
	local model: Model
	if src then
		model = src:Clone()
	else
		-- no art for this name: a plain block so the sequence still has a body to reveal
		model = Instance.new("Model")
		local p = Instance.new("Part")
		p.Size = Vector3.new(1, 1, 1)
		p.Color = Color3.fromRGB(230, 230, 230)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Parent = model
		model.PrimaryPart = p
		warn("[EggHatch.RewardRig] no model for " .. tostring(opts.name) .. " -- placeholder")
	end
	model.Name = "Reward_" .. tostring(opts.name)
	if opts.mutation and MutationFX then
		pcall(MutationFX.apply, model, opts.mutation)
	end
	-- facing, measured before anything moves
	local f = facingOf(model)
	self.yawFix = math.atan2(-f.X, f.Z)

	-- fit: height, or 0.62 of the footprint for the long low ones (caterpillars, snails)
	local ext = model:GetExtentsSize()
	local fit = math.max(ext.Y, 0.62 * math.max(ext.X, ext.Z))
	local fitScale = (fit > 0.01) and (self.h / fit) or 1
	model:ScaleTo(fitScale)
	-- anchor = the bottom centre of the fitted model, yawed so the face looks at +Z
	local bcf, bsz = model:GetBoundingBox()
	local anchor = CFrame.new(bcf.Position - Vector3.new(0, bsz.Y * 0.5, 0)) * CFrame.Angles(0, self.yawFix, 0)
	self.bboxH = bsz.Y
	self.model = model
	-- every part relative to the anchor: the emergence writes them through a
	-- non-uniform scale exactly like the egg does
	local recs = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = anchor:ToObjectSpace(d.CFrame)
			recs[#recs + 1] = { part = d, pos = rel.Position, rot = rel.Rotation, size = d.Size, transp = d.Transparency }
		end
	end
	self.recs = recs
	return self
end

function RewardRig:reveal(now: number)
	if self.dead or self.mode ~= "hidden" then return end
	self.mode = "pop"
	self.t0 = now
	self.model.Parent = self.stage.folder
end

-- uniform scale `uni`, vertical squash `sy` (x/z volume-preserving), rise dy, yaw sway
function RewardRig:write(uni: number, sy: number, dy: number, yaw: number)
	local W = self.stage.frame * CFrame.new(self.slot + Vector3.new(0, dy, 0)) * CFrame.Angles(0, yaw, 0)
	local sx = uni / math.sqrt(math.max(0.2, sy))
	local vy = sy * uni
	local S = Vector3.new(sx, vy, sx)
	for _, r in ipairs(self.recs) do
		local rot = r.rot
		local fx = Vector3.new(rot.XVector.X * sx, rot.XVector.Y * vy, rot.XVector.Z * sx).Magnitude
		local fy = Vector3.new(rot.YVector.X * sx, rot.YVector.Y * vy, rot.YVector.Z * sx).Magnitude
		local fz = Vector3.new(rot.ZVector.X * sx, rot.ZVector.Y * vy, rot.ZVector.Z * sx).Magnitude
		r.part.Size = Vector3.new(r.size.X * fx, r.size.Y * fy, r.size.Z * fz)
		r.part.CFrame = W * CFrame.new(r.pos * S) * rot
	end
end

function RewardRig:update(dt: number, now: number)
	if self.dead or self.mode == "hidden" then return end
	local t = now - self.t0
	local h = self.h
	local uni, sy, dy, yaw = 1, 1, 0, 0
	-- EMERGE: a fast pop with the tier's overshoot, rising out of the shell
	local POP = 0.22
	if t < POP then
		local u = t / POP
		uni = 0.10 + 0.90 * backOut(u, self.popK)
		dy = 0.16 * h * math.sin(math.pi * u)
	end
	-- LAND: a squash on touch-down, then a small stretch back
	do
		local u = (t - POP) / 0.13
		if u > 0 and u < 1 then
			sy *= 1 - 0.14 * math.sin(math.pi * u)
		elseif u >= 1 and u < 1.7 then
			sy *= 1 + 0.05 * math.sin(math.pi * (u - 1) / 0.7)
		end
	end
	-- BOUNCE (Epic+): a second, smaller hop with its own landing
	if self.bounce > 0 then
		local u = (t - POP - 0.15) / 0.24
		if u > 0 and u < 1 then
			dy += self.bounce * h * 3 * math.sin(math.pi * u)
		elseif u >= 1 and u < 1.5 then
			sy *= 1 - 0.07 * math.sin(math.pi * (u - 1) / 0.5)
		end
	end
	-- IDLE: a slow bob and a showcase sway once the entrance has landed
	local settled = math.clamp((t - 0.35) / 0.4, 0, 1)
	dy += 0.025 * h * math.sin(t * 2.6) * settled
	yaw = math.rad(8) * math.sin(t * 1.5) * settled
	-- EXIT: scale away, dropping a touch
	if self.exitT then
		local u = math.clamp((now - self.exitT) / self.exitLen, 0, 1)
		uni *= 1 - easeIn(u)
		dy -= 0.08 * h * u
		if u >= 1 then
			for _, r in ipairs(self.recs) do r.part.Transparency = 1 end
			return
		end
	end
	self:write(uni, sy, dy, yaw)
end

-- clean exit: the creature scales away over `seconds` (authored)
function RewardRig:exit(now: number, seconds: number)
	if self.dead or self.exitT then return end
	self.exitT = now
	self.exitLen = math.max(0.05, seconds)
end

function RewardRig:centreLocal(): Vector3
	return self.slot + Vector3.new(0, self.bboxH * 0.5, 0)
end

function RewardRig:destroy()
	if self.dead then return end
	self.dead = true
	if self.model then self.model:Destroy() end
end

return RewardRig
