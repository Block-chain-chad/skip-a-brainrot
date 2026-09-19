-- CellarDoorClient: draws Elder Tung's cellar hatch, for THIS player only.
--
-- The hatch is deliberately not a world door. ServerScriptService.CellarDoor checks the
-- key and fires the CellarDoor remote to one client; everything below -- the padlock
-- falling, the leaves swinging, the prompt retiring -- happens locally, so a keyholder's
-- open hatch is still a shut hatch to everyone standing next to them.
--
-- Local writes to a workspace instance never replicate up, and the server does not touch
-- these parts after startup, so nothing overwrites this. The one thing that CAN undo it
-- is streaming (parts leaving and re-entering the client's view reset to the replicated
-- state), which is why the open pose is re-asserted on a slow loop rather than set once.
--
-- Physics follows for free: a character is simulated by its owning client, so with the
-- leaves non-colliding HERE this player drops down the shaft, while every other client
-- has them solid. ServerScriptService.CellarDoor's position check is the authoritative
-- backstop for anyone who tampers with that.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local doorRemote = remotes:WaitForChild("CellarDoor")

local cellar   = workspace:WaitForChild("GameWorld"):WaitForChild("Cellar")
local entrance = cellar:WaitForChild("Entrance")
local padlock  = entrance:WaitForChild("Padlock")
local prompt   = padlock:WaitForChild("Body"):WaitForChild("CellarPrompt")

local OPEN_TIME  = 1.1              -- seconds for the leaves to swing
local OPEN_ANGLE = math.rad(105)

-- Same hinge maths the server used to run. Captured ONCE, at the replicated (closed)
-- pose, so `base` is never a pose this script has already rotated.
local leaves = {}
for _, name in ipairs({ "LeafWest", "LeafEast" }) do
	local leaf = entrance:WaitForChild(name)
	local hingeX = leaf:GetAttribute("HingeX")
	table.insert(leaves, {
		model = leaf,
		pivot = Vector3.new(hingeX, 4.55, 87),
		-- the leaf swings up and away from its own hinge, so the direction of the
		-- rotation is just which side of the hinge the plank sits on
		sign  = hingeX < leaf.PrimaryPart.Position.X and 1 or -1,
		base  = leaf:GetPivot(),
	})
end

local function setAngle(theta)
	for _, l in ipairs(leaves) do
		local t = CFrame.new(l.pivot) * CFrame.Angles(0, 0, l.sign * theta) * CFrame.new(-l.pivot)
		l.model:PivotTo(t * l.base)
	end
end

local function setLeavesSolid(solid)
	for _, l in ipairs(leaves) do
		for _, d in ipairs(l.model:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide = solid end
		end
	end
end

local function play(name)
	local snd = padlock.Body:FindFirstChild(name)
	if snd then snd:Play() end          -- local: heard by this client only
end

local function hidePadlock()
	for _, d in ipairs(padlock:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	prompt.Enabled = false
end

local busy, isOpen = false, false

-- A short shudder against the padlock: the leaves lift a couple of degrees and drop
-- back, twice, so a locked pull reads as blocked rather than as nothing.
local function rattle()
	play("LockedRattle")
	for _ = 1, 2 do
		for i = 0, 1, 0.34 do
			setAngle(math.rad(2.5) * math.sin(i * math.pi))
			RunService.Heartbeat:Wait()
		end
	end
	setAngle(0)
end

local function open(animate)
	isOpen = true
	setLeavesSolid(false)

	if not animate then
		hidePadlock()
		setAngle(OPEN_ANGLE)
		return
	end

	play("UnlockClunk")
	task.wait(0.35)

	-- the padlock drops into the grass and is gone. Scripted rather than unanchored:
	-- these parts are owned by the server, so local physics on them would be fought
	-- by replication instead of falling.
	local start = padlock:GetPivot()
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = math.min((os.clock() - t0) / 0.6, 1)
			padlock:PivotTo(start * CFrame.new(0, -3.5 * a * a, -1.4 * a))
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		hidePadlock()
	end)

	play("HatchOpen")
	local t0 = os.clock()
	while true do
		local a = math.min((os.clock() - t0) / OPEN_TIME, 1)
		-- ease out, so the leaves land rather than slam
		setAngle(OPEN_ANGLE * (1 - (1 - a) ^ 3))
		if a >= 1 then break end
		RunService.Heartbeat:Wait()
	end
end

doorRemote.OnClientEvent:Connect(function(action)
	if action == "open" then
		if busy or isOpen then return end
		busy = true
		local ok, err = pcall(open, true)
		if not ok then warn("[CellarDoorClient] open failed: " .. tostring(err)) end
		busy = false
	elseif action == "already" then
		if busy then return end
		busy = true
		pcall(open, false)
		busy = false
	elseif action == "rattle" then
		if busy or isOpen then return end
		busy = true
		pcall(rattle)
		busy = false
	end
end)

-- Streaming can hand back the replicated (closed, solid, visible-padlock) pose at any
-- time. Cheap enough at 1Hz, and it only does anything once the door is actually open.
task.spawn(function()
	while true do
		task.wait(1)
		if isOpen and not busy then
			setAngle(OPEN_ANGLE)
			setLeavesSolid(false)
			if prompt.Enabled then hidePadlock() end
		end
	end
end)

--====================== THE TUNDRA IS MEANT TO BE A SURPRISE ================--
-- The portal's "FROZEN TUNDRA" billboard is authored DISABLED and only switched on
-- while this player is actually down in the dungeon.
--
-- A BillboardGui draws through the world at any range, so from up on the grass the
-- label hung in mid-air over the cellar roof and announced a destination the player
-- has no idea exists -- it gave away both the dungeon and what is past it before they
-- had either key. Local-only, like the hatch itself: nothing here replicates, so one
-- player reading the label never reveals it to anybody else.
task.spawn(function()
	local portals = workspace.GameWorld:WaitForChild("Portals", 30)
	local tundra = portals and portals:WaitForChild("TundraPortal", 30)
	local anchor = tundra and tundra:FindFirstChild("LabelAnchor")
	local label = anchor and anchor:FindFirstChildWhichIsA("BillboardGui")
	if not label then return end

	-- same box the server's trespass backstop uses, computed the same way
	local cf, size = cellar:GetBoundingBox()
	local minB, maxB = cf.Position - size * 0.5, cf.Position + size * 0.5
	local ceil = entrance:GetPivot().Position.Y - 2.5

	while true do
		task.wait(0.4)
		local char = Players.LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local p = hrp and hrp.Position
		label.Enabled = (p ~= nil)
			and p.Y < ceil
			and p.X > minB.X and p.X < maxB.X
			and p.Z > minB.Z and p.Z < maxB.Z
	end
end)
