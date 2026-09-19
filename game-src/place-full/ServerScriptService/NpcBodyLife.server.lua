-- NpcBodyLife -- the reason the shopkeepers still looked identical (2026-08-14).
--
-- MEASURED, NOT GUESSED. After giving all 15 NPCs different stock idle animations
-- they STILL read as the same person. Sampling the actual skeletons explained it:
-- 11 of the 15 move their right hand through a range of under 0.12 studs over a
-- full cycle, several under 0.03. Roblox's stock STANDING idles are all the same
-- gesture -- a weight shift and a glance -- so swapping asset ids changes the data
-- and not the silhouette. No amount of extra ids would ever have fixed it.
--
-- So the visible motion has to come from somewhere I control: the ROOT. The
-- HumanoidRootPart is anchored (NpcRigLife keeps it that way so nobody can shove
-- these NPCs around), and an anchored part can still be driven by CFrame -- the
-- constrained limbs follow it. Verified before writing this: driving the root
-- through an 18-degree turn plus a 0.09 bob left the rig upright (head +1.48
-- above root), detached zero parts, and restored exactly on release.
--
-- !! ALWAYS ABSOLUTE FROM A STORED ORIGIN, never read-current-and-add. Integrating
-- an offset every frame is what makes an NPC slowly walk away from its post --
-- NpcIdle's own comments carry that scar, and this file must not repeat it.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local D = math.rad

-- One body language per NPC. These are large enough to READ ACROSS A SHOP -- the
-- stock idles are 0.02-0.1 studs, these are 10-25 degrees of turn and up to a
-- tenth of a stud of bob, which is the difference between "alive" and "statue".
local BODY = {
	-- Gino watches his own egg: a slow rise and settle timed near the toss, with a
	-- small turn as he follows it up.
	["EggStall"] = function(t)
		return CFrame.Angles(0, D(10) * math.sin(t * 2.02), 0)
			* CFrame.new(0, math.sin(t * 2.02) * 0.07, 0)
			* CFrame.Angles(D(-4) * math.sin(t * 2.02), 0, 0)
	end,
	-- Marco leans in over the counter to count, then straightens.
	["SellStall"] = function(t)
		local lean = (math.sin(t * 0.62) + 1) * 0.5
		return CFrame.new(0, -0.06 * lean, 0)
			* CFrame.Angles(D(9) * lean, D(6) * math.sin(t * 0.45), 0)
	end,
	-- Rocco surveys the shelf, turning well to each side.
	["ShopStall"] = function(t)
		return CFrame.Angles(0, D(24) * math.sin(t * 0.38), 0)
			* CFrame.new(0, math.sin(t * 0.76) * 0.04, 0)
	end,
	-- Enzo rocks over his work, tinkering.
	["UpgradeStall"] = function(t)
		return CFrame.new(0, math.abs(math.sin(t * 1.5)) * 0.09, 0)
			* CFrame.Angles(D(11) * math.abs(math.sin(t * 1.5)), D(5) * math.sin(t * 0.7), 0)
	end,
	-- Lil Miss sways, weight on one hip then the other.
	["CharmStall"] = function(t)
		return CFrame.Angles(0, D(8) * math.sin(t * 0.55), D(5) * math.sin(t * 0.55))
			* CFrame.new(math.sin(t * 0.55) * 0.1, 0, 0)
	end,
	-- Gianluca is bored: shifts weight, turns away, turns back.
	["StupidGianluca"] = function(t)
		local turn = math.sin(t * 0.31)
		return CFrame.Angles(0, D(28) * turn, 0) * CFrame.new(0, math.sin(t * 1.1) * 0.05, 0)
	end,

	-- Tundra: everyone is cold, and each shows it differently.
	["Frost Eggs"] = function(t)      -- fine constant shiver
		return CFrame.new(math.sin(t * 17) * 0.022, math.sin(t * 13) * 0.02, 0)
			* CFrame.Angles(0, D(6) * math.sin(t * 0.5), D(2) * math.sin(t * 15))
	end,
	["Stone Cache"] = function(t)     -- heavy, slow, side to side
		return CFrame.Angles(0, D(14) * math.sin(t * 0.26), D(7) * math.sin(t * 0.26))
			* CFrame.new(0, math.sin(t * 0.52) * 0.06, 0)
	end,
	["Thaw Works"] = function(t)      -- jerky, machine-like corrections
		local step = math.floor(t * 1.3) % 4
		return CFrame.Angles(0, D(7) * (step - 1.5), 0) * CFrame.new(0, math.sin(t * 3.1) * 0.03, 0)
	end,
	["Frozen Haul"] = function(t)     -- hunched and still, with an occasional big shudder
		local burst = math.max(0, math.sin(t * 0.42) - 0.9) * 10
		return CFrame.Angles(D(6), 0, 0)
			* CFrame.new(math.sin(t * 19) * 0.03 * burst, 0, 0)
			* CFrame.Angles(0, D(4) * math.sin(t * 0.6), 0)
	end,
	["Rime Charms"] = function(t)     -- light, quick, up on her toes
		return CFrame.new(0, math.abs(math.sin(t * 1.9)) * 0.1, 0)
			* CFrame.Angles(0, D(11) * math.sin(t * 0.95), 0)
	end,

	-- Gardens: brighter and busier than the tundra.
	["GardensSellStall"] = function(t)
		return CFrame.new(0, math.sin(t * 2.6) * 0.05, 0)
			* CFrame.Angles(D(7) * math.sin(t * 2.6), D(12) * math.sin(t * 0.7), 0)
	end,
	["GardensShopStall"] = function(t)
		return CFrame.new(0, math.abs(math.sin(t * 2.1)) * 0.11, 0)
			* CFrame.Angles(0, D(9) * math.sin(t * 1.05), 0)
	end,
	["GardensUpgradeStall"] = function(t)
		local inOut = (math.sin(t * 0.85) + 1) * 0.5
		return CFrame.Angles(D(13) * inOut, D(6) * math.sin(t * 0.42), 0)
			* CFrame.new(0, -0.05 * inOut, 0)
	end,
	["GardensCharmStall"] = function(t)
		return CFrame.Angles(0, D(10) * math.sin(t * 0.6), D(6) * math.sin(t * 1.2))
			* CFrame.new(math.sin(t * 0.6) * 0.12, math.sin(t * 1.2) * 0.04, 0)
	end,
}

-- Same keying as NpcPropLife: the PARENT stall names the character, except where
-- the parent is just a container, otherwise the three Lil Miss models collapse
-- into a single entry.
local CONTAINERS = { GameWorld = true, Stalls = true, Hub = true, Workspace = true }
local function keyOf(npc)
	local parent = npc.Parent
	if parent and not CONTAINERS[parent.Name] then return parent.Name end
	return npc.Name
end

local live = {}

local function attach(npc)
	if npc:GetAttribute("BodyLife") then return false end
	local fn = BODY[keyOf(npc)]
	if not fn then return false end
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	live[#live + 1] = {
		npc = npc, hrp = hrp,
		cf0 = hrp.CFrame,          -- the origin every frame is computed FROM
		fn = fn,
		t0 = math.random() * 15,   -- nobody shares a phase
	}
	npc:SetAttribute("BodyLife", true)
	return true
end

RunService.Heartbeat:Connect(function()
	local now = time()
	for i = #live, 1, -1 do
		local r = live[i]
		if not (r.npc.Parent and r.hrp.Parent) then
			table.remove(live, i)
		elseif r.hrp.Anchored then
			-- only ever while anchored: writing CFrame into a free-floating assembly
			-- is what drags a whole character across the map
			r.hrp.CFrame = r.cf0 * r.fn(now + r.t0)
		end
	end
end)

task.defer(function()
	-- after NpcRigLife has woken them, so cf0 is captured on a settled rig
	task.wait(2)
	local n = 0
	for _, m in ipairs(workspace:GetDescendants()) do
		if m:IsA("Model") and m:FindFirstChild("HumanoidRootPart")
			and m:FindFirstChildOfClass("Humanoid")
			and not Players:GetPlayerFromCharacter(m) then
			if attach(m) then n += 1 end
		end
	end
	print(("NpcBodyLife online (%d NPCs with their own body language)"):format(n))
end)
