-- NpcRigLife -- wakes the shopkeeper NPCs up (2026-08-14).
--
-- WHAT WAS ACTUALLY WRONG. Five of these NPCs are complete, animation-ready R15
-- avatars: all 11 bones, a live Animator, HumanoidDescription, FaceControls. They
-- looked like statues because every part is ANCHORED, and an anchored part cannot
-- be moved by the animation system. Nothing needed authoring in the Animation
-- Editor and nothing needed uploading -- they were simply bolted to the floor.
--
-- (They use Roblox's newer constraint rig -- AnimationConstraint, BallSocket,
-- 54 Attachments -- and carry ZERO Motor6D joints, which is why a Motor6D scan
-- reports them as "not rigs". Do not trust that test on these models.)
--
-- THREE THINGS HAVE TO HAPPEN IN THIS ORDER, and the order is the whole script:
--
--  1. WELD THE CLOTHES ON. Marco's jacket, tie, lapels, cuffs, sleeves, trousers
--     and shoes are 17 separate parts held in place by NOTHING but their own
--     Anchored flag -- the model contains zero welds. Unanchor first and he
--     undresses onto the floor. Each loose part is welded to its nearest bone,
--     which lands anatomically every time (verified: Shoe->Foot 0.06 studs,
--     Cuff->Hand 0.15, Sleeve->UpperArm 0.27, Jacket->UpperTorso 0.00).
--  2. START THE ANIMATION. It has to be playing BEFORE anything is freed: this
--     rig is held by BallSocket/AnimationConstraints, so limbs with nothing
--     driving them sag under gravity the instant they are unanchored.
--  3. UNANCHOR EVERYTHING EXCEPT THE ROOT. The HumanoidRootPart stays anchored,
--     which plants him -- he cannot fall, drift, or be shoved by players -- while
--     every limb above it is free for the Animator to move.
--
-- The idle is one of ROBLOX'S OWN default R15 animations. Those are public
-- assets, so this needs no upload, no Animation Editor, and no place ownership.
-- Custom gestures (a wave, a shrug, a talk loop) still need a human in the
-- Animation Editor -- but the rigs are ready for them now, which they were not.

local Players = game:GetService("Players")

-- AUTO-DETECTED, NOT LISTED. A hand-written allowlist was the safe way to prove
-- this on one NPC, but a sweep of the world found FIFTEEN rig-complete
-- shopkeepers, not the five in the main camp: the Frozen Tundra hub has five
-- (Frost Eggs, Rime Charms, Stone Cache, Thaw Works, Frozen Haul) and the Gardens
-- has four more, and every one of them was anchored solid. Any stall added later
-- is picked up for free rather than being forgotten in a table.
--
-- The bar is deliberately high -- a Humanoid, a HumanoidRootPart and 11+ R15
-- bones -- so props and part-built NPCs (Michael, Elder Tung, Maxwell, the Daily
-- Wheel) are never touched. Those have no skeleton and can only be animated
-- procedurally, which is what NpcIdle already does for them.
local DISABLED = {
	-- ["SomeStall"] = true,   -- opt a specific one back out by model name
}

-- A POOL, NOT ONE ANIMATION. Fifteen shopkeepers all playing the same stock idle
-- reads as one puppet copied fifteen times, which is exactly how it looked. These
-- are Roblox's own public R15 idles from its animation packages (zombie, ninja,
-- robot, superhero, mage, pirate, elder, levitation...), so they still need no
-- upload and no Animation Editor -- but each NPC gets a DIFFERENT one.
--
-- Every id is verified at runtime by track.Length > 0 and a dud is simply skipped,
-- so a wrong guess in this list costs nothing. Assignment starts at a per-NPC
-- offset derived from its name, so it is stable across restarts (Marco is always
-- Marco) rather than random each boot.
local IDLE_POOL = {
	507766666, 507766951, 507766388,      -- default
	616158929, 616160636,                 -- zombie
	656117400, 656118341,                 -- ninja
	616088211, 616089559,                 -- robot
	616111295, 616112668,                 -- superhero
	616136790, 616138447,                 -- stylish
	707742142, 707855907,                 -- mage
	616006778, 616008087,                 -- levitation
	845397899, 845400520,                 -- elder
	750781874, 750782770,                 -- pirate
	657595757, 891621366, 1014390418,     -- knight / astronaut / cowboy
	1069977950, 1132473842, 910004836,    -- confident / sneaky / bubbly
}

-- Which slot this NPC starts hunting from. Deterministic, so the same shopkeeper
-- keeps the same personality every session.
local function poolStart(npc)
	local key = (npc.Name == "NPC" and npc.Parent) and npc.Parent.Name or npc.Name
	local h = #key
	for i = 1, #key do h = (h * 31 + string.byte(key, i)) % 100003 end
	return h % #IDLE_POOL
end

local R15 = {
	Head = true, UpperTorso = true, LowerTorso = true, HumanoidRootPart = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local function wake(npc)
	if npc:GetAttribute("RigLife") then return false, "already awake" end
	local hum = npc:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if not (hum and animator and hrp) then return false, "not a rig" end

	-- 1. clothes on
	local bones = {}
	for _, p in ipairs(npc:GetDescendants()) do
		if p:IsA("BasePart") and R15[p.Name] then bones[#bones + 1] = p end
	end
	if #bones < 11 then return false, "incomplete rig" end
	-- ⚠️ HELD PROPS ARE NOT CLOTHING. NpcPropLife parents a "PropLife" model inside
	-- the NPC and force-writes its parts' CFrames every frame. If this loop welds
	-- one of those into the body and unanchors it, that per-frame CFrame write is
	-- then dragging the whole physics assembly -- the anchored root fights it, the
	-- rig collapses and the NPC slides across the map. Measured before this guard:
	-- 10 of 15 NPCs drifting 2-17 studs/second, one 1,200 studs below the world.
	-- Both scripts run on task.defer, so whichever wins the race decided whether a
	-- given NPC survived -- which is exactly why it looked intermittent.
	local function isProp(p)
		return p:FindFirstAncestor("PropLife") ~= nil or p:GetAttribute("NpcProp") == true
	end

	local welded = 0
	for _, p in ipairs(npc:GetDescendants()) do
		-- Accessories are skipped: Roblox welds those itself once the character is
		-- in place, and adding a second weld fights its own.
		if p:IsA("BasePart") and not R15[p.Name]
			and not p:FindFirstAncestorOfClass("Accessory")
			and not isProp(p)
			and not p:FindFirstChild("RigLifeWeld") then
			local best, bd = nil, math.huge
			for _, b in ipairs(bones) do
				local d = (p.Position - b.Position).Magnitude
				if d < bd then best, bd = b, d end
			end
			if best then
				local w = Instance.new("WeldConstraint")
				w.Name = "RigLifeWeld"
				w.Part0, w.Part1 = best, p
				w.Parent = p
				welded += 1
			end
		end
	end

	-- 2. animation first
	local track, usedId
	local start = poolStart(npc)
	for i = 0, #IDLE_POOL - 1 do
		local id = IDLE_POOL[((start + i) % #IDLE_POOL) + 1]
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. id
		local ok, t = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and t then
			local waited = 0
			while t.Length <= 0 and waited < 2 do task.wait(0.1); waited += 0.1 end
			if t.Length > 0 then track, usedId = t, id break end
		end
	end
	if not track then
		-- LEAVE HIM ANCHORED. A frozen shopkeeper is a far better failure than a
		-- puddle of unanchored limbs behind the counter.
		return false, "no stock idle resolved -- left anchored"
	end
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Idle
	track:Play(0.3)
	-- START EACH ONE AT A DIFFERENT POINT IN THE LOOP. Woken together they breathe
	-- in perfect unison, and a row of shopkeepers moving as one reads as a chorus
	-- line rather than as people.
	track.TimePosition = math.random() * track.Length

	-- 3. free everything but the root
	local freed = 0
	for _, p in ipairs(npc:GetDescendants()) do
		if p:IsA("BasePart") and p ~= hrp and p.Anchored and not isProp(p) then
			p.Anchored = false
			freed += 1
		end
	end
	hrp.Anchored = true
	npc:SetAttribute("RigLife", true)

	-- Keep it running. A track can be stopped by a respawn, a state change, or
	-- another script; if that happens the limbs have nothing holding them.
	task.spawn(function()
		while npc.Parent and hrp.Parent do
			task.wait(3)
			if not track.IsPlaying then track:Play(0.3) end
		end
	end)
	npc:SetAttribute("RigLifeIdle", usedId)
	return true, ("idle %d (%.2fs), %d welds, %d parts freed"):format(usedId, track.Length, welded, freed)
end

-- PLAYERS ARE NOT SHOPKEEPERS. Every player character is also a rig-complete R15
-- model sitting in Workspace, and unanchoring/animating one would fight their own
-- controller. This is the single most important guard in the file.
local function isPlayerCharacter(m)
	if Players:GetPlayerFromCharacter(m) then return true end
	for _, pl in ipairs(Players:GetPlayers()) do
		local c = pl.Character
		if c and (m == c or m:IsDescendantOf(c)) then return true end
	end
	return false
end

local function isRig(m)
	if not (m:IsA("Model") and m:FindFirstChildOfClass("Humanoid")
		and m:FindFirstChild("HumanoidRootPart")) then return false end
	if isPlayerCharacter(m) then return false end
	local key = (m.Name == "NPC" and m.Parent) and m.Parent.Name or m.Name
	if DISABLED[key] then return false end
	local bones = 0
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and R15[p.Name] then bones += 1 end
	end
	return bones >= 11
end

local function tryWake(m, quiet)
	if not isRig(m) then return false end
	local ok, why = wake(m)
	if ok then
		print(("[NpcRigLife] %s awake -- %s"):format(m:GetFullName(), why))
	elseif not quiet then
		warn(("[NpcRigLife] %s skipped -- %s"):format(m:GetFullName(), why))
	end
	return ok
end

task.defer(function()
	local awake, seen = 0, 0
	for _, m in ipairs(workspace:GetDescendants()) do
		if isRig(m) then
			seen += 1
			if tryWake(m, true) then awake += 1 end
		end
	end
	print(("NpcRigLife online (%d/%d rigged NPCs animating)"):format(awake, seen))

	-- Stalls in the Tundra and Gardens hubs can stream in after this first pass,
	-- so catch late arrivals rather than rescanning 58k descendants on a timer.
	workspace.DescendantAdded:Connect(function(d)
		if not d:IsA("Humanoid") then return end
		task.defer(function()
			local m = d.Parent
			if m and m:IsA("Model") then tryWake(m, true) end
		end)
	end)
end)
