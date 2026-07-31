-- CellarDoor: the padlocked hatch on the grass west of the fishing hut.
--
-- The key does not exist in the game yet, so hasKey() is false for everyone today and
-- every trigger falls through to the rattle. The whole unlock path below is already
-- wired though -- padlock drops, both leaves swing, the prompt retires -- so shipping
-- the key later is one of:
--     * give the player a Tool named exactly KEY_NAME (Backpack or equipped), or
--     * player:SetAttribute("HasCellarKey", true) from whatever grants it.
-- Nothing in this script needs editing for either.
--
-- The cellar is a WORLD door, not a per-player one: once any keyholder opens it, it
-- stays open for the rest of that server. Making it per-player would mean replicating
-- two different door states to two different clients, which is a client-side rebuild
-- of the whole hatch -- not worth it for a shared overworld prop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local cellar   = workspace:WaitForChild("GameWorld"):WaitForChild("Cellar")
local entrance = cellar:WaitForChild("Entrance")
local padlock  = entrance:WaitForChild("Padlock")
local prompt   = padlock.Body:WaitForChild("CellarPrompt")

local KEY_NAME   = cellar:GetAttribute("RequiredKey") or "Cellar Key"
local OPEN_TIME  = 1.1              -- seconds for the leaves to swing
local OPEN_ANGLE = math.rad(105)

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

local function play(name)
	local snd = padlock.Body:FindFirstChild(name)
	if snd then snd:Play() end
end

local function notify(player, message)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("PurchaseResult")
	if remote then
		remote:FireClient(player, { Success = false, Message = message })
	end
end

local function hasKey(player)
	if player:GetAttribute("HasCellarKey") then return true end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and backpack:FindFirstChild(KEY_NAME) then return true end
	local char = player.Character
	if char and char:FindFirstChild(KEY_NAME) then return true end
	return false
end

local busy = false

local function rattle()
	-- a short shudder against the padlock: the leaves lift a couple of degrees and
	-- drop back, twice, so a locked pull reads as blocked rather than as nothing
	play("LockedRattle")
	for _ = 1, 2 do
		for i = 0, 1, 0.34 do
			setAngle(math.rad(2.5) * math.sin(i * math.pi))
			RunService.Heartbeat:Wait()
		end
	end
	setAngle(0)
end

local function open()
	cellar:SetAttribute("Locked", false)
	prompt.Enabled = false
	play("UnlockClunk")
	task.wait(0.35)

	-- padlock falls off into the grass and is gone for good
	local body = padlock.Body
	for _, d in ipairs(padlock:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = true
		end
	end
	body.AssemblyLinearVelocity = Vector3.new(0, 4, -6)
	task.delay(4, function() padlock:Destroy() end)

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

prompt.Triggered:Connect(function(player)
	if busy or not cellar:GetAttribute("Locked") then return end
	busy = true

	if hasKey(player) then
		open()
	else
		notify(player, "The cellar is padlocked. You need the " .. KEY_NAME .. ".")
		rattle()
		busy = false
	end
end)

print("CellarDoor online (locked, requires '" .. KEY_NAME .. "')")
