-- NpcPropLife -- a hand-authored idle for EACH shopkeeper (2026-08-14).
--
-- The first cut of this file was five ARCHETYPES matched by name and stamped
-- across all fifteen NPCs, which is precisely why they still looked identical:
-- every egg seller tossed the same egg the same way. This version has ONE ENTRY
-- PER NPC. Same trade, different business: Gino tosses an egg gently in his hand,
-- Frost Eggs keeps one hovering half-frozen, Gardens tosses low and fast.
--
-- WHY PROPS AND NOT BODY ANIMATION. A bespoke body gesture is Animation Editor
-- work and needs uploading -- a human job. A prop is ours: nothing else writes to
-- it, so animating it can never fight the Animator the way overriding a limb
-- would. Each prop is positioned from the hand every frame, so the idle's own
-- hand motion carries into it for free.
--
-- !! GEOMETRY CONSTRAINT, measured, not assumed: these stall counters sit at
-- Y 8.58 while the NPC's shoulder is at 8.62 -- the counter IS shoulder height,
-- and the stock idles hang both arms at the sides, putting the hand 1.4 studs
-- BELOW the surface. So a literally-in-the-hand prop is invisible behind the
-- counter. Each profile therefore picks its own `rest`:
--   "hand"  - true hand height. Correct for anyone with no counter.
--   "lip"   - just over the counter, for a gentle toss that peaks in view.
--   "work"  - a hand's width above the counter, normal working height.
-- Anything higher reads as parked on the shoulder, which is the trap the
-- previous version fell into.
--
-- Runs on the server so every player sees the same thing.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- !! EVERY PROP PART MUST CARRY THIS. NpcRigLife walks the NPC looking for loose
-- clothing to weld onto the skeleton, and a held prop looks exactly like loose
-- clothing to it. If a prop is welded in AND unanchored, the per-frame CFrame
-- write below stops being "move the prop" and becomes "drag the whole character",
-- which threw NPCs across the map at up to 17 studs/second.
local function markProp(p)
	p:SetAttribute("NpcProp", true)
	return p
end

local function newPart(name, size, colour, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = colour
	p.Material = material
	p.Anchored = true
	markProp(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function rockMesh(which, scale, colour, material, holder, name)
	local src = ReplicatedStorage:FindFirstChild("RockMeshes")
	src = src and src:FindFirstChild(which)
	if not src then
		return newPart(name, Vector3.new(0.6, 0.55, 0.6),
			colour or Color3.fromRGB(138, 138, 130), material or Enum.Material.Slate, holder)
	end
	local r = src:Clone()
	r.Name = name
	r.Size = src.Size * scale
	r.Anchored, r.CanCollide, r.CanQuery, r.CanTouch, r.CastShadow = true, false, false, false, false
	if colour then r.Color = colour end
	if material then r.Material = material end
	markProp(r)
	r.Parent = holder
	return r
end

local BUILD = {}

function BUILD.egg(holder, tint)
	local e = newPart("Egg", Vector3.new(0.62, 0.82, 0.62),
		tint or Color3.fromRGB(255, 252, 235), Enum.Material.SmoothPlastic, holder)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = e
	for i = 1, 3 do
		local s = newPart("Speck", Vector3.new(0.15, 0.1, 0.15),
			Color3.fromRGB(206, 188, 148), Enum.Material.SmoothPlastic, holder)
		s:SetAttribute("Speck", i)
	end
	return e
end

function BUILD.money(holder)
	local top
	for i = 1, 5 do
		local n = newPart("Note", Vector3.new(0.8, 0.08, 0.44),
			Color3.fromRGB(104, 176, 92), Enum.Material.SmoothPlastic, holder)
		n:SetAttribute("Layer", i)
		top = n
	end
	return top
end

function BUILD.rock(holder)
	return rockMesh("rounded", 0.46, nil, nil, holder, "Rock")
end

function BUILD.pebbles(holder)
	local top
	for i = 1, 3 do
		local p = rockMesh("chunk", 0.26 - i * 0.04, nil, nil, holder, "Pebble")
		p:SetAttribute("Stack", i)
		top = p
	end
	return top
end

function BUILD.gear(holder)
	local g = newPart("Gear", Vector3.new(0.76, 0.18, 0.76),
		Color3.fromRGB(255, 206, 80), Enum.Material.Neon, holder)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Cylinder
	m.Parent = g
	for i = 1, 6 do
		local t = newPart("Tooth", Vector3.new(0.2, 0.15, 0.2),
			Color3.fromRGB(255, 224, 130), Enum.Material.Neon, holder)
		t:SetAttribute("Tooth", i)
	end
	return g
end

function BUILD.charm(holder, tint)
	return rockMesh("crystal", 0.34, tint or Color3.fromRGB(168, 126, 255),
		Enum.Material.Neon, holder, "Charm")
end

function BUILD.coin(holder)
	local c = newPart("Coin", Vector3.new(0.64, 0.1, 0.64),
		Color3.fromRGB(255, 205, 70), Enum.Material.Metal, holder)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Cylinder
	m.Parent = c
	return c
end

local function parabola(a, height) return 4 * height * a * (1 - a) end

local PROFILES = {
	["EggStall"] = { prop = "egg", rest = "lip", fwd = 0.9,
		build = { tint = Color3.fromRGB(255, 250, 228) },
		motion = function(t)
			local CYCLE, AIR = 3.1, 0.66
			local p = (t % CYCLE) / CYCLE
			if p < AIR then
				local a = p / AIR
				return CFrame.new(0, parabola(a, 0.85), 0) * CFrame.Angles(a * 1.1, a * 0.5, 0)
			end
			local s = (p - AIR) / (1 - AIR)
			return CFrame.new(0, -0.08 * math.sin(s * math.pi), 0) * CFrame.Angles(1.1, 0.5, 0)
		end },

	["SellStall"] = { prop = "money", rest = "work", fwd = 1.5,
		motion = function(t)
			local c = (t % 2.6) / 2.6
			local tilt = math.sin(c * math.pi * 2) * 0.34
			return CFrame.new(0, math.sin(c * math.pi * 4) * 0.045, 0)
				* CFrame.Angles(tilt, math.sin(c * math.pi * 2) * 0.2, 0)
		end },

	["ShopStall"] = { prop = "rock", rest = "work", fwd = 1.3,
		motion = function(t)
			local c = (t % 4.4) / 4.4
			local raise = math.sin(c * math.pi) * 0.42
			return CFrame.new(0, raise, 0) * CFrame.Angles(t * 0.55, t * 0.9, math.sin(t * 0.4) * 0.3)
		end },

	["UpgradeStall"] = { prop = "gear", rest = "work", fwd = 1.2,
		motion = function(t)
			return CFrame.new(0, 0.3 + math.sin(t * 2.4) * 0.06, 0) * CFrame.Angles(0, t * 5.5, 0)
		end },

	["CharmStall"] = { prop = "charm", rest = "work", fwd = 1.0,
		motion = function(t)
			return CFrame.new(0, 0.34 + math.sin(t * 1.3) * 0.12, 0)
				* CFrame.Angles(math.sin(t * 0.7) * 0.4, t * 1.4, 0)
		end },

	["StupidGianluca"] = { prop = "coin", rest = "hand", fwd = 0.2,
		motion = function(t)
			local CYCLE, AIR = 2.2, 0.7
			local p = (t % CYCLE) / CYCLE
			if p < AIR then
				local a = p / AIR
				return CFrame.new(0, parabola(a, 1.0), 0) * CFrame.Angles(a * math.pi * 8, 0, 0)
			end
			return CFrame.new() * CFrame.Angles(math.pi * 8, 0, 0)
		end },

	["Frost Eggs"] = { prop = "egg", rest = "work", fwd = 1.1,
		build = { tint = Color3.fromRGB(214, 238, 255) },
		motion = function(t)
			return CFrame.new(math.sin(t * 11) * 0.012, 0.34 + math.sin(t * 0.9) * 0.1, 0)
				* CFrame.Angles(0, t * 0.55, math.sin(t * 0.6) * 0.16)
		end },

	["Stone Cache"] = { prop = "pebbles", rest = "work", fwd = 1.2,
		motion = function(t)
			return CFrame.new(0, math.sin(t * 0.85) * 0.16, 0) * CFrame.Angles(0, t * 0.5, 0)
		end },

	["Thaw Works"] = { prop = "gear", rest = "work", fwd = 1.2,
		motion = function(t)
			local hitch = (math.sin(t * 1.7) > 0.85) and 0.25 or 1
			return CFrame.new(0, 0.3, 0) * CFrame.Angles(math.sin(t * 1.1) * 0.35, t * 3.2 * hitch, 0)
		end },

	["Frozen Haul"] = { prop = "money", rest = "work", fwd = 1.4,
		motion = function(t)
			return CFrame.new(0, math.sin(t * 1.1) * 0.05, 0)
				* CFrame.Angles(0.2 + math.sin(t * 0.9) * 0.12, t * 0.25, 0)
		end },

	["Rime Charms"] = { prop = "charm", rest = "work", fwd = 1.0,
		build = { tint = Color3.fromRGB(140, 220, 255) },
		motion = function(t)
			local r = 0.2
			return CFrame.new(math.cos(t * 2.2) * r, 0.36 + math.sin(t * 2.6) * 0.07, math.sin(t * 2.2) * r)
				* CFrame.Angles(0, t * 2.6, 0)
		end },

	["GardensSellStall"] = { prop = "money", rest = "work", fwd = 1.5,
		motion = function(t)
			return CFrame.new(0, math.sin(t * 5.5) * 0.06, 0)
				* CFrame.Angles(math.sin(t * 5.5) * 0.4, 0, math.sin(t * 2.1) * 0.15)
		end },

	["GardensShopStall"] = { prop = "rock", rest = "work", fwd = 1.3,
		motion = function(t)
			local CYCLE, AIR = 1.5, 0.55
			local p = (t % CYCLE) / CYCLE
			if p < AIR then
				local a = p / AIR
				return CFrame.new(0, parabola(a, 0.4), 0) * CFrame.Angles(a * 2.2, a * 1.4, 0)
			end
			return CFrame.new() * CFrame.Angles(2.2, 1.4, 0)
		end },

	["GardensUpgradeStall"] = { prop = "gear", rest = "work", fwd = 1.2,
		motion = function(t)
			return CFrame.new(0, 0.3, 0) * CFrame.Angles(0.45, t * 4.2, math.sin(t * 1.3) * 0.2)
		end },

	["GardensCharmStall"] = { prop = "charm", rest = "work", fwd = 1.0,
		build = { tint = Color3.fromRGB(190, 255, 170) },
		motion = function(t)
			return CFrame.new(math.sin(t * 1.2) * 0.26, 0.36 + math.sin(t * 2.4) * 0.09,
				math.sin(t * 2.4) * 0.12)
				* CFrame.Angles(0, t * 1.1, math.sin(t * 1.2) * 0.35)
		end },
}

local CONTAINERS = { GameWorld = true, Stalls = true, Hub = true, Workspace = true }
local function keyOf(npc)
	local parent = npc.Parent
	if parent and not CONTAINERS[parent.Name] then return parent.Name end
	return npc.Name
end

local live = {}
local COUNTER_RANGE = 12

local function attach(npc)
	if npc:GetAttribute("PropLife") then return false end
	local key = keyOf(npc)
	local profile = PROFILES[key]
	if not profile then return false end
	local hand = npc:FindFirstChild("RightHand") or npc:FindFirstChild("LeftHand")
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not (hand and root) then return false end

	local holder = Instance.new("Model")
	holder.Name = "PropLife"
	holder.Parent = npc
	local build = BUILD[profile.prop]
	if not build then holder:Destroy(); return false end
	build(holder, profile.build and profile.build.tint or nil)

	local lift = 0
	if profile.rest ~= "hand" then
		local top
		for _, p in ipairs((npc.Parent or npc):GetDescendants()) do
			if p:IsA("BasePart") and (p.Name == "CounterTop" or p.Name == "Counter")
				and (p.Position - root.Position).Magnitude <= COUNTER_RANGE then
				local y = p.Position.Y + p.Size.Y / 2
				if not top or y > top then top = y end
			end
		end
		if top then
			local margin = (profile.rest == "lip") and 0.05 or 0.30
			lift = math.clamp((top + margin) - hand.Position.Y, 0, 3)
		end
	end

	live[#live + 1] = {
		npc = npc, hand = hand, holder = holder, key = key,
		motion = profile.motion,
		lift = lift,
		forward = root.CFrame.LookVector * (profile.fwd or 1.0),
		t0 = math.random() * 12,
	}
	npc:SetAttribute("PropLife", true)
	print(("[NpcPropLife] %s -> %s (%s)"):format(key, profile.prop, profile.rest))
	return true
end

local PALM = CFrame.new(0, -0.35, 0)

RunService.Heartbeat:Connect(function()
	local now = time()
	for i = #live, 1, -1 do
		local r = live[i]
		if not (r.npc.Parent and r.hand.Parent and r.holder.Parent) then
			if r.holder.Parent then r.holder:Destroy() end
			table.remove(live, i)
		else
			local t = now + r.t0
			local palm = (r.hand.CFrame * PALM).Position + Vector3.new(0, r.lift, 0) + r.forward
			local mo = r.motion(t)
			local base = CFrame.new(palm + mo.Position) * (mo - mo.Position)
			for _, p in ipairs(r.holder:GetChildren()) do
				if p:IsA("BasePart") then
					if not p.Anchored then p.Anchored = true end
					local stray = p:FindFirstChild("RigLifeWeld")
					if stray then stray:Destroy() end
					local layer = p:GetAttribute("Layer")
					local speck = p:GetAttribute("Speck")
					local tooth = p:GetAttribute("Tooth")
					local stack = p:GetAttribute("Stack")
					if layer then
						p.CFrame = base * CFrame.new(0, layer * 0.085, 0) * CFrame.Angles(0, layer * 0.07, 0)
					elseif speck then
						local a = speck * 2.1
						p.CFrame = base * CFrame.new(math.cos(a) * 0.24, math.sin(a) * 0.18, math.sin(a) * 0.24)
					elseif tooth then
						local a = (tooth / 6) * math.pi * 2
						p.CFrame = base * CFrame.new(math.cos(a) * 0.42, 0, math.sin(a) * 0.42)
					elseif stack then
						p.CFrame = base * CFrame.new(0, (stack - 1) * 0.2, 0) * CFrame.Angles(0, stack * 1.1, 0)
					else
						p.CFrame = base
					end
				end
			end
		end
	end
end)

task.defer(function()
	local n, skipped = 0, {}
	for _, m in ipairs(workspace:GetDescendants()) do
		if m:IsA("Model") and m:FindFirstChild("RightHand") and m:FindFirstChildOfClass("Humanoid")
			and not Players:GetPlayerFromCharacter(m) then
			if attach(m) then
				n += 1
			elseif not m:GetAttribute("PropLife") then
				local k = keyOf(m)
				if not PROFILES[k] then skipped[#skipped + 1] = k end
			end
		end
	end
	print(("NpcPropLife online (%d bespoke idles)"):format(n))
	if #skipped > 0 then
		warn("[NpcPropLife] no profile for: " .. table.concat(skipped, ", "))
	end
end)
