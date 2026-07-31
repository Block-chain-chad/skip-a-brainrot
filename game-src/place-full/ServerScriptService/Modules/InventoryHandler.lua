-- Brainrot inventory lives in the player's real Roblox Backpack.
-- Each unplaced brainrot = one Tool. Equip it and click to place it on a free pad.
-- Walk up to a placed brainrot and hold E to store it back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")   -- held-display templates

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotSpawner = require(ServerScriptService.Modules.BrainrotSpawner)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)   -- held-display glow
local MutationFX = require(ReplicatedStorage.Modules.MutationFX)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
local remotes = ReplicatedStorage.Remotes

local infoByName = {}
for _, e in ipairs(BrainrotConfig) do infoByName[e.Name] = e end

local InventoryHandler = {}

local function notify(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

local function findByUid(data, uid)
	for _, e in ipairs(data.Brainrots) do
		if e.Uid == uid then return e end
	end
	return nil
end

-- padIndex is the spot the player picked. Nil falls back to the first free pad,
-- which is only used if the client could not resolve what they were aiming at.
local function place(player, uid, padIndex)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local entry = findByUid(data, uid)
	if not entry or entry.PadIndex then return end

	local plot = PlayerDataManager.GetPlot(player)
	if not plot then notify(player, false, "Claim a base first!") return end

	if padIndex then
		-- never trust the client: the spot must be unlocked and genuinely empty
		local limit = math.min(data.UnlockedSpots or 12, 16)
		if padIndex < 1 or padIndex > limit then
			notify(player, false, "That spot is locked \u{2014} unlock it first.")
			return
		end
		for _, e in ipairs(data.Brainrots) do
			if e.PadIndex == padIndex then
				notify(player, false, "That spot is taken \u{2014} pick an empty one.")
				return
			end
		end
	else
		padIndex = PlayerDataManager.FindFreePad(data)
		if not padIndex then notify(player, false, "No free spots! Unlock more or store one.") return end
	end

	entry.PadIndex = padIndex
	local placed = BrainrotSpawner.Spawn(plot, entry.Name, padIndex, entry.Mutation, entry.Uid)

	-- Positional, so it is heard by whoever is standing on the base rather than
	-- fired flat at everyone. Deliberately here in place() and NOT in Spawner.Spawn:
	-- Spawn also runs to restore every brainrot when a base is claimed, which
	-- would fire a wall of thuds on join.
	if placed then
		local at = placed:IsA("BasePart") and placed
			or (placed:IsA("Model") and placed.PrimaryPart)
		if at then
			SoundKit.play("place", at, { volume = 0.4, range = 70 })
		end
	end

	InventoryHandler.SyncBackpack(player)
	PlayerDataManager.PushUpdate(player)
end

local function store(player, uid)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local entry = findByUid(data, uid)
	if not entry or not entry.PadIndex then return end

	local plot = PlayerDataManager.GetPlot(player)
	if plot then
		local pads = plot:FindFirstChild("Pads")
		if pads then
			for _, m in ipairs(pads:GetChildren()) do
				if m:GetAttribute("Uid") == uid then m:Destroy() end
			end
		end
	end
	PlayerDataManager.DrainPending(player, entry, data)
	entry.PadIndex = nil
	InventoryHandler.SyncBackpack(player)
	PlayerDataManager.PushUpdate(player)
end

--=============================== held display ==============================--
-- Show the actual brainrot in the player's hand while its tool is equipped.
--
-- Built ON EQUIP and destroyed on unequip, deliberately. A player can hold 100+
-- unplaced brainrots and each model is 10-30 parts; baking a display into every
-- tool would put thousands of parts in one backpack. This way exactly one
-- exists at a time, per player.
-- Carried OUT IN FRONT at chest-to-knee height, big enough to be the thing you
-- notice about a player -- the Steal a Brainrot read the user asked for, rather
-- than a small trophy floating over the head.
local HELD_HEIGHT = 4.2      -- studs tall; nearly as tall as the character
local HELD_MAX_WIDTH = 5.5   -- the roster runs up to 4x wider than tall; without
                             -- this cap those models become absurd slabs
local HELD_FORWARD = 2.6     -- studs in front of the root, clear of the torso
local HELD_DROP = 0.8        -- studs below the root, so it sits at the hips

local function buildHeld(player, tool, entry)
	local char = player.Character
	if not char then return end
	-- Anchor to the ROOT, not the head or torso. HumanoidRootPart exists on both
	-- R6 and R15 and does not animate, so the creature rides steadily in front
	-- instead of bobbing with the walk cycle. The matching arms-forward carry
	-- pose is applied client-side in BrainrotHoldClient.
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- see BrainrotSpawner: the model folder moved to ReplicatedStorage
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local template = folder and folder:FindFirstChild(entry.Name)
	if not template then return end

	local model = template:Clone()
	model.Name = "HeldBrainrot"

	-- Rigged pack models carry Motor6Ds whose C0/C1 assume the authored pose.
	-- Strip them and re-weld from CURRENT positions, or the model explodes apart
	-- the moment its parts are unanchored. FakeRootPart is rig scaffolding that
	-- sits away from the mesh and silently inflates GetBoundingBox -- which was
	-- making every held model come out ~45% under the target size.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("AnimationController") or d:IsA("Animator")
			or d:IsA("Bone") or d.Name == "FakeRootPart" then
			d:Destroy()
		end
	end

	-- ScaleTo is ABSOLUTE (a multiplier on the model's authored size), so scale
	-- RELATIVE to the current scale, and run it twice: the first pass can shift
	-- the bounding box slightly on irregular models.
	for _ = 1, 2 do
		local _, s = model:GetBoundingBox()
		if s.Y > 0.01 then
			-- fit to a box, not just a height: whichever limit bites first
			local factor = math.min(
				HELD_HEIGHT / s.Y,
				HELD_MAX_WIDTH / math.max(s.X, s.Z, 0.01)
			)
			model:ScaleTo(model:GetScale() * factor)
		end
	end

	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then model:Destroy() return end
	model.PrimaryPart = root

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			-- Massless matters: an unanchored multi-part model welded to a limb
			-- otherwise drags the character's physics around.
			d.Massless = true
		end
	end

	-- Push it out in front and drop it to hip height, then freeze that
	-- relationship. Translating by the BOUNDING BOX delta rather than PivotTo'ing
	-- the pivot directly matters: on these pack models the authored pivot is
	-- rarely the visual centre, so pivoting straight to the target leaves the
	-- creature visibly off to one side.
	local boxCF = select(1, model:GetBoundingBox())
	local target = (hrp.CFrame * CFrame.new(0, -HELD_DROP, -HELD_FORWARD)).Position
	model:PivotTo(model:GetPivot() + (target - boxCF.Position))

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = root, d
			w.Parent = root
		end
	end
	local grip = Instance.new("WeldConstraint")
	grip.Part0, grip.Part1 = hrp, root
	grip.Parent = root

	-- the same escalating treatment a placed copy gets, so carrying a Glitched
	-- around actually looks like carrying a Glitched
	if entry.Mutation then
		MutationFX.apply(model, entry.Mutation)
	end

	model.Parent = tool
end

local function clearHeld(tool)
	local held = tool:FindFirstChild("HeldBrainrot")
	if held then held:Destroy() end
end

--=============================== hotbar budget =============================--
-- Roblox will happily put a Tool in the hotbar for all 130+ unplaced brainrots,
-- which is unusable. The hotbar is capped and the grid panel is the real
-- inventory. This is a TOOL cap, not a data cap: nothing is lost, the rest
-- simply have no Tool until you pick them out of the grid.
local HOTBAR_SLOTS = 6
local hotbar = {}   -- [player] = { uid, ... }, most-recently-chosen LAST

local function hotbarList(player)
	local l = hotbar[player]
	if not l then l = {}; hotbar[player] = l end
	return l
end

local function valueOf(entry)
	local info = infoByName[entry.Name]
	return (info and info.CashPerSecond or 0) * Mutations.Mult(entry.Mutation)
end

local function equippedUidOf(player)
	local char = player.Character
	if not char then return nil end
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") and t:GetAttribute("BrainrotTool") then
			return t:GetAttribute("Uid")
		end
	end
	return nil
end

local function makeTool(player, entry)
	local info = infoByName[entry.Name]
	local tool = Instance.new("Tool")
	tool.Name = (entry.Mutation and (entry.Mutation .. " ") or "") .. entry.Name
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = (info and ("$" .. tostring(info.CashPerSecond) .. "/s  \u{2022}  " .. info.Rarity .. "  \u{2022}  ") or "")
		.. "aim at an empty spot on your base and click to place"
	tool:SetAttribute("BrainrotTool", true)
	tool:SetAttribute("Uid", entry.Uid)

	-- hold the actual creature out while this tool is equipped
	tool.Equipped:Connect(function()
		clearHeld(tool)   -- idempotent: re-equipping fast must not stack copies
		local ok, err = pcall(buildHeld, player, tool, entry)
		if not ok then
			warn(("[InventoryHandler] held display failed for %q: %s"):format(entry.Name, tostring(err)))
		end
	end)
	tool.Unequipped:Connect(function() clearHeld(tool) end)

	-- Placement is driven by PlaceBrainrot from the client, which knows which pad
	-- the player is aiming at. Tool.Activated fires here too but carries no aim
	-- information, so it must NOT auto-place or it would steal the chosen spot.
	return tool
end

-- rebuild the backpack so it exactly mirrors the unplaced brainrots
function InventoryHandler.SyncBackpack(player)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	local have = {}
	local function collect(container)
		if not container then return end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("BrainrotTool") then
				have[t:GetAttribute("Uid")] = t
			end
		end
	end
	collect(backpack)
	collect(player.Character)

	local unplaced = {}
	for _, e in ipairs(data.Brainrots) do
		if not e.PadIndex and e.Uid then unplaced[e.Uid] = e end
	end

	local list = hotbarList(player)
	-- drop anything since placed, sold, fused or traded away
	for i = #list, 1, -1 do
		if not unplaced[list[i]] then table.remove(list, i) end
	end
	-- top up from the most valuable, so a fresh session opens with your best six
	if #list < HOTBAR_SLOTS then
		local inList = {}
		for _, uid in ipairs(list) do inList[uid] = true end
		local rest = {}
		for uid, e in pairs(unplaced) do
			if not inList[uid] then rest[#rest + 1] = e end
		end
		table.sort(rest, function(a, b) return valueOf(a) > valueOf(b) end)
		for _, e in ipairs(rest) do
			if #list >= HOTBAR_SLOTS then break end
			list[#list + 1] = e.Uid
		end
	end

	local want = {}
	for _, uid in ipairs(list) do
		want[uid] = true
		if not have[uid] then
			makeTool(player, unplaced[uid]).Parent = backpack
		end
	end
	for uid, tool in pairs(have) do
		if not want[uid] then tool:Destroy() end
	end

	-- Gianluca's Keys are NOT tools. They are shown as a row in the backpack UI
	-- (see BackpackClient) and cannot be equipped, held or used. An earlier pass
	-- did make them real Tools, so purge any that are still lying around in a
	-- profile from that version.
	for _, container in ipairs({ backpack, player.Character }) do
		if container then
			for _, t in ipairs(container:GetChildren()) do
				if t:IsA("Tool") and t:GetAttribute("KeyTool") then t:Destroy() end
			end
		end
	end
end

-- Pull a brainrot out of the grid into the hotbar and equip it. Evicts the
-- oldest slot when full -- never the one currently in hand, and never the one
-- being brought in.
function InventoryHandler.BringToHand(player, uid)
	local data = PlayerDataManager.Get(player)
	if not data then return end
	local entry
	for _, e in ipairs(data.Brainrots) do
		if e.Uid == uid and not e.PadIndex then entry = e break end
	end
	if not entry then return end   -- not owned, or it is placed on the base

	local held = equippedUidOf(player)
	local list = hotbarList(player)
	for i = #list, 1, -1 do
		if list[i] == uid then table.remove(list, i) end
	end
	list[#list + 1] = uid

	-- Evict the LEAST VALUABLE slot, not the oldest. Oldest-first looks tidy but
	-- the initial fill is in value order, so it threw out your best earner the
	-- very first time you pulled anything up from the grid.
	local byUid = {}
	for _, e in ipairs(data.Brainrots) do
		if e.Uid then byUid[e.Uid] = e end
	end
	while #list > HOTBAR_SLOTS do
		local worstI, worstV = nil, math.huge
		for i = 1, #list do
			local u = list[i]
			if u ~= held and u ~= uid then      -- never drop what is in hand or incoming
				local v = byUid[u] and valueOf(byUid[u]) or 0
				if v < worstV then worstV, worstI = v, i end
			end
		end
		table.remove(list, worstI or 1)
	end

	InventoryHandler.SyncBackpack(player)

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if hum and backpack then
		for _, t in ipairs(backpack:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("Uid") == uid then
				hum:EquipTool(t)
				break
			end
		end
	end
end

function InventoryHandler.Init()
	-- client resolves which pad the player clicked and sends it here
	remotes.PlaceBrainrot.OnServerEvent:Connect(function(player, uid, padIndex)
		if typeof(uid) ~= "number" then return end
		if padIndex ~= nil and typeof(padIndex) ~= "number" then return end
		place(player, uid, padIndex and math.floor(padIndex) or nil)
	end)

	-- client detects the StorePrompt and asks us to store it (validated here)
	remotes.StoreBrainrot.OnServerEvent:Connect(function(player, uid)
		if typeof(uid) ~= "number" then return end
		local plot = PlayerDataManager.GetPlot(player)
		if not plot then return end
		local pads = plot:FindFirstChild("Pads")
		if not pads then return end
		local owned = false
		for _, m in ipairs(pads:GetChildren()) do
			if m:GetAttribute("Uid") == uid then owned = true break end
		end
		if not owned then return end -- must be a brainrot on your own base
		store(player, uid)
	end)

	-- the grid asks for a brainrot that has no Tool yet
	remotes.EquipBrainrot.OnServerEvent:Connect(function(player, uid)
		if typeof(uid) ~= "number" then return end
		InventoryHandler.BringToHand(player, uid)
	end)

	Players.PlayerRemoving:Connect(function(p) hotbar[p] = nil end)

	local function hook(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.6)
			InventoryHandler.SyncBackpack(player)
		end)
		if player.Character then
			task.delay(0.6, function() InventoryHandler.SyncBackpack(player) end)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end

	-- claiming a base restores models, so refresh which tools should remain
	PlayerDataManager.OnPlotClaimed = function(player)
		task.defer(function() InventoryHandler.SyncBackpack(player) end)
	end

	print("InventoryHandler online")
end

return InventoryHandler
