--[[ PippoMotionClient -- drives the Pippo pack's per-frame motion.

WHY A SEPARATE DRIVER. MutationFX paints a mutation ONCE, on the server, at the
pack's reference time t = 0.6. Six of the twelve are animated -- rainbow scrolls
its hue, aurora's curtains rise, electric reseeds arcs 7x a second, celestial
twinkles, demon's lava pulses, glitched tears its slices -- and a one-shot paint
freezes all of that on a single frame. This repaints them.

ONE HEARTBEAT FOR EVERY MUTATED MODEL IN VIEW, with distance culling, which is
the same shape MutationMotionClient already uses. A brainrot is repainted only
while it is close enough for the motion to be visible at all.

STATIC MUTATIONS ARE NEVER TOUCHED. Wet and Sandy have no `animate` block in the
pack, and Gold/Diamond's sparkle is rare enough that repainting them 20 times a
second buys nothing; PippoSkin.AnimateKind returns the pack's own kind, and
anything without one is skipped for the lifetime of the model.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local okSkin, PippoSkin = pcall(require, ReplicatedStorage.Modules:WaitForChild("PippoSkin", 10))
if not okSkin then
	warn("[PippoMotion] PippoSkin unavailable: " .. tostring(PippoSkin))
	return
end

local player = Players.LocalPlayer
local UPDATE_HZ = 20        -- the pack's own default; 20 looks identical to 60
local NEAR = 140            -- studs: beyond this the motion is not readable
local RESCAN = 1.0

-- Which pack ids are worth driving at all
local KINDS = {}
for _, id in ipairs({ "gold","diamond","wet","sandy","rainbow","electric","frozen",
	"aurora","celestial","glitched","demon","angel" }) do
	KINDS[id] = PippoSkin.AnimateKind(id)
end

local tracked = {}   -- [model] = { id = , kind = }
local scanAcc, paintAcc, clock = 0, 0, 0

local function rescan()
	table.clear(tracked)
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			local id = inst:GetAttribute("PippoId")
			if type(id) == "string" and KINDS[id] then
				tracked[inst] = { id = id, kind = KINDS[id] }
			end
		end
	end
end

local function originOf(inst)
	if inst:IsA("BasePart") then return inst.Position end
	local ok, pv = pcall(function() return inst:GetPivot().Position end)
	return ok and pv or nil
end

RunService.Heartbeat:Connect(function(dt)
	clock += dt
	scanAcc += dt
	paintAcc += dt
	if scanAcc >= RESCAN then
		scanAcc = 0
		rescan()
	end
	if paintAcc < 1 / UPDATE_HZ then return end
	paintAcc = 0

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local eye = hrp.Position

	for model, info in pairs(tracked) do
		if model.Parent then
			local pos = originOf(model)
			if pos and (pos - eye).Magnitude <= NEAR then
				-- quality 1 = 27 glow samples per part: the cheap tier, and at 20 Hz
				-- indistinguishable from the 125 the one-shot server paint uses
				pcall(PippoSkin.Paint, model, info.id, clock, 1)
				if info.kind == "sliceShift" then
					pcall(PippoSkin.SliceShift, model, clock)
				end
			end
		else
			tracked[model] = nil
		end
	end
end)

rescan()
print("[PippoMotion] online -- driving the pack's animated mutations at " .. UPDATE_HZ .. " Hz")
