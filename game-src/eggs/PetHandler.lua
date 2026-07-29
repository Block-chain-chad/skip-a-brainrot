-- PetHandler (Forest Egg Shop, Task 11) -- pets, shipped disabled.
--
-- PetConfig.ENABLED gates the whole feature. LuckMult/IncomeMult are read by ThrowHandler
-- and IncomeLoop on every throw/tick respectively, so both return a neutral 1 the instant
-- ENABLED is false -- no data lookup, no loop -- so those two seams can be wired live today
-- with zero effect on drop rates or income until a future task flips the flag.
--
-- Grant/PetEquip/the follow rig are NOT gated behind ENABLED: nothing reachable from the
-- (nonexistent) shop UI can call Grant while the feature is off, so there is no live path
-- for a player to ever own a pet. Gating them too would just be dead code guarding dead
-- code. TestAcorn (PetConfig.Pets) exists purely so Grant/equip/the mult seams can be
-- exercised from the command bar ahead of the real shop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local PetHandler = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local petEquipRemote = getRemote("PetEquip")

-- World-space-relative offsets from HumanoidRootPart, one per follow slot. Index 1-3 are
-- the SLOTS_FREE range; 4-6 only ever get used once SLOTS_PREMIUM is unlocked.
local SLOT_OFFSETS = {
	Vector3.new(-2.5, 1, 2.5),
	Vector3.new(2.5, 1, 2.5),
	Vector3.new(-3.5, 1.5, 4),
	Vector3.new(3.5, 1.5, 4),
	Vector3.new(-1.5, 2, 5),
	Vector3.new(1.5, 2, 5),
}

-- === Gamepass: premium slot cap ===============================================
-- [player] = bool, cached for the session so the cap check never blocks on
-- MarketplaceService more than once per player. Cleared on PlayerRemoving so a
-- rejoin re-checks rather than trusting a stale table keyed by a live Player object.
local premiumCache = {}

-- id == 0 means no gamepass is configured yet -- UserOwnsGamePassAsync is never called
-- with a bogus id; the premium path just stays inert and everyone gets SLOTS_FREE.
local function ownsPremiumSlots(player)
	local id = PetConfig.PET_SLOTS_GAMEPASS_ID
	if id == 0 then return false end
	if premiumCache[player] ~= nil then return premiumCache[player] end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	local result = (ok and owns) and true or false
	premiumCache[player] = result
	return result
end

local function slotCap(player)
	return ownsPremiumSlots(player) and PetConfig.SLOTS_PREMIUM or PetConfig.SLOTS_FREE
end

-- === Boost math =================================================================
-- 1 + sum of equipped pets' matching Boost.Amount. Neutral (1) instantly when the
-- feature is off, or when the player/data/pets can't be resolved -- callers on the hot
-- throw/income paths must never be able to turn a lookup failure into a multiplier of 0.
local function boostMult(player, boostType)
	if not PetConfig.ENABLED then return 1 end
	local data = PlayerDataManager.Get(player)
	if not data or type(data.Pets) ~= "table" or type(data.PetSlots) ~= "table" then return 1 end

	local petByUid = {}
	for _, pet in ipairs(data.Pets) do
		petByUid[pet.Uid] = pet
	end

	local sum = 0
	for _, uid in ipairs(data.PetSlots) do
		local pet = petByUid[uid]
		if pet and pet.Boost and pet.Boost.Type == boostType then
			sum += (pet.Boost.Amount or 0)
		end
	end
	return 1 + sum
end

function PetHandler.LuckMult(player)
	if not PetConfig.ENABLED then return 1 end
	return boostMult(player, "Luck")
end

function PetHandler.IncomeMult(player)
	if not PetConfig.ENABLED then return 1 end
	return boostMult(player, "Income")
end

-- Validates petId against PetConfig.Pets and appends a new owned-pet record. Does NOT
-- equip it -- PetEquip (client-driven) is the only path into data.PetSlots.
function PetHandler.Grant(player, petId)
	local def = PetConfig.Pets[petId]
	if not def then return false end
	local data = PlayerDataManager.Get(player)
	if not data then return false end
	data.Pets = data.Pets or {}

	local uid = HttpService:GenerateGUID(false)
	table.insert(data.Pets, {
		Uid = uid,
		Id = petId,
		Boost = table.clone(def.Boost),
	})
	PlayerDataManager.PushUpdate(player)
	return true, uid
end

-- === Follow rig: 8-part placeholder acorn (2-stud ball + 7 cap cubes) ==========
-- All 8 parts are Massless + CanCollide=false: an unanchored multi-part assembly
-- welded together must not add mass or hitbox to whatever it is following (see
-- InventoryHandler's identical note on held-tool visuals).
local CAP_OFFSETS = {
	Vector3.new(0, 1.1, 0),
	Vector3.new(0.5, 1.0, 0),
	Vector3.new(-0.5, 1.0, 0),
	Vector3.new(0, 1.0, 0.5),
	Vector3.new(0, 1.0, -0.5),
	Vector3.new(0.35, 1.0, 0.35),
	Vector3.new(-0.35, 1.0, -0.35),
}

local function buildAcorn()
	local model = Instance.new("Model")
	model.Name = "PetRig"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(2, 2, 2)
	root.Color = Color3.fromRGB(139, 94, 60)
	root.Material = Enum.Material.SmoothPlastic
	root.Massless = true
	root.CanCollide = false
	root.CanQuery = false
	root.Anchored = false
	root.Parent = model

	for i, offset in ipairs(CAP_OFFSETS) do
		local cube = Instance.new("Part")
		cube.Name = "Cap" .. i
		cube.Shape = Enum.PartType.Block
		cube.Size = Vector3.new(0.6, 0.6, 0.6)
		cube.Color = Color3.fromRGB(90, 60, 30)
		cube.Material = Enum.Material.SmoothPlastic
		cube.Massless = true
		cube.CanCollide = false
		cube.CanQuery = false
		cube.Anchored = false
		cube.CFrame = root.CFrame * CFrame.new(offset)
		cube.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = cube
		weld.Parent = cube
	end

	model.PrimaryPart = root
	return model, root
end

-- [player] = Folder containing every currently-built PetRig model for that player.
local rigFolders = {}

local function rigContainer()
	local ws = game:GetService("Workspace")
	local folder = ws:FindFirstChild("PetRigs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PetRigs"
		folder.Parent = ws
	end
	return folder
end

local function destroyRig(player)
	local folder = rigFolders[player]
	if folder then
		folder:Destroy()
		rigFolders[player] = nil
	end
end

-- Tears down and fully rebuilds every follow rig for `player` from the CURRENT
-- data.PetSlots. Called after every equip/unequip and every CharacterAdded, so it is
-- always the single source of truth for what is visually following the player --
-- there is no incremental add/remove path to drift out of sync.
local function buildRig(player)
	destroyRig(player)

	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end

	local data = PlayerDataManager.Get(player)
	if not data or type(data.PetSlots) ~= "table" or #data.PetSlots == 0 then return end

	local petByUid = {}
	for _, pet in ipairs(data.Pets or {}) do
		petByUid[pet.Uid] = pet
	end

	local folder = Instance.new("Folder")
	folder.Name = tostring(player.UserId)
	folder.Parent = rigContainer()
	rigFolders[player] = folder

	for i, uid in ipairs(data.PetSlots) do
		if petByUid[uid] then
			local offset = SLOT_OFFSETS[i] or SLOT_OFFSETS[#SLOT_OFFSETS]
			local model, root = buildAcorn()
			root.CFrame = hrp.CFrame * CFrame.new(offset)
			model.Parent = folder

			local petAttach = Instance.new("Attachment")
			petAttach.Name = "PetAttach"
			petAttach.Parent = root

			local hrpAttach = Instance.new("Attachment")
			hrpAttach.Name = "PetSlot" .. i
			hrpAttach.Position = offset
			hrpAttach.Parent = hrp

			local alignPos = Instance.new("AlignPosition")
			alignPos.Attachment0 = petAttach
			alignPos.Attachment1 = hrpAttach
			alignPos.Responsiveness = 15
			alignPos.MaxForce = 4e4
			alignPos.Parent = root

			-- hrpAttach carries no rotation offset, so its WorldCFrame orientation IS the
			-- character's orientation -- AlignOrientation tracking it is enough to make the
			-- rig face the character's LookVector with no extra math.
			local alignOrient = Instance.new("AlignOrientation")
			alignOrient.Attachment0 = petAttach
			alignOrient.Attachment1 = hrpAttach
			alignOrient.Parent = root
		end
	end
end

-- === PetEquip remote: uid must be an owned pet, and equipping is capped at slotCap ===
local function onPetEquip(player, uid, equip)
	if typeof(uid) ~= "string" then return end
	equip = equip and true or false

	local data = PlayerDataManager.Get(player)
	if not data or type(data.Pets) ~= "table" then return end

	local owned = false
	for _, pet in ipairs(data.Pets) do
		if pet.Uid == uid then owned = true break end
	end
	if not owned then return end

	data.PetSlots = data.PetSlots or {}
	local idx
	for i, u in ipairs(data.PetSlots) do
		if u == uid then idx = i break end
	end

	if equip then
		if idx then return end -- already equipped: no-op, not an error
		if #data.PetSlots >= slotCap(player) then return end
		table.insert(data.PetSlots, uid)
	else
		if not idx then return end
		table.remove(data.PetSlots, idx)
	end

	PlayerDataManager.PushUpdate(player)
	buildRig(player)
end

local function hookCharacter(player, character)
	local hum = character:WaitForChild("Humanoid", 5)
	if hum then
		hum.Died:Connect(function() destroyRig(player) end)
	end
	buildRig(player)
end

function PetHandler.Init()
	petEquipRemote.OnServerEvent:Connect(onPetEquip)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end)

	-- Handle players already in-game (Studio test start) the same way Main does.
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		if player.Character then
			hookCharacter(player, player.Character)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		destroyRig(player)
		premiumCache[player] = nil
	end)
end

return PetHandler
