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

-- Offsets from HumanoidRootPart, in the CHARACTER's local space. +Z is behind the
-- player (a CFrame's LookVector is its -Z), so every slot trails.
--
-- Slots 1-3 (the SLOTS_FREE range) form a TRIANGLE: two abreast right behind the
-- player, and the third centred behind that pair. Slots 4-6 only come into play with
-- SLOTS_PREMIUM and continue the same pattern into a second row, so a full six reads as
-- one arrow rather than a crowd.
--
-- Y is deliberately equal across every slot: the bob is the only vertical motion, so a
-- staggered resting height would read as pets sitting at wonky altitudes rather than as
-- a formation.
-- Vector2, not Vector3: X is lateral, Y is how far BEHIND. The vertical position is NOT
-- a constant here -- it is derived per character and per model (see footDrop/modelLift in
-- buildRig), because a fixed Y cannot put pets "just above the feet":
--   * the offset positions the model's PrimaryPart, which can sit anywhere inside the
--     model, so one fixed Y floats one creature and buries another; and
--   * the drop from HumanoidRootPart down to the feet depends on HipHeight.
local SLOT_OFFSETS = {
	Vector2.new(-1.8, 3.2),   -- 1: behind-left  }  the pair, abreast
	Vector2.new(1.8, 3.2),    -- 2: behind-right }  directly behind the player
	Vector2.new(0, 6.0),      -- 3: centred behind the pair -> triangle apex
	Vector2.new(-3.0, 8.6),
	Vector2.new(3.0, 8.6),
	Vector2.new(0, 11.2),
}
-- How far the pet's underside floats above the player's feet at rest. Must exceed the
-- bob's downswing (BOB_HEIGHT/2 = 0.225) or a pet clips through the ground at the bottom
-- of every cycle.
local PET_FOOT_CLEARANCE = 0.5
-- Lateral spread is only +/-1.8 rather than the wider first pass: at 2.2 out and 2.6
-- back the pair read as FLANKING the character instead of trailing it. 1.8 out and 3.2
-- back keeps them clear of the character's ~2-stud silhouette while still sitting
-- visibly behind, which is what "right behind the player" has to look like from the
-- default over-the-shoulder camera.

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
-- A pet now carries BOTH a luck and an income multiplier (a Secret is 5x luck AND 10x
-- money), which the old single Boost.Type shape could not express.
--
-- Boosts are looked up from PetConfig by Id at READ time, not read off the owned record.
-- That is deliberate: a rebalance in PetConfig then reaches pets players already own,
-- instead of leaving every existing pet frozen at whatever the numbers were on the day it
-- hatched. The stored record's Boost field is still honoured as a fallback so any pet
-- granted under the old shape keeps working.
local function boostsFor(pet)
	if not pet then return 1, 1 end
	local luck, income = PetConfig.BoostsFor(pet.Id)
	if luck == 1 and income == 1 and pet.Boost and pet.Boost.Type then
		-- legacy single-type record
		local amt = 1 + (pet.Boost.Amount or 0)
		if pet.Boost.Type == "Luck" then return amt, 1 end
		if pet.Boost.Type == "Income" then return 1, amt end
	end
	return luck, income
end

-- Stacking is ADDITIVE on the bonus portion: one 5x Secret gives 5x, two give 9x, not 25x.
-- Multiplying would make a third Secret worth more than the first two combined and put
-- luck somewhere no clamp could sensibly follow.
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
		local luck, income = boostsFor(petByUid[uid])
		local mult = (boostType == "Luck") and luck or income
		sum += math.max(0, mult - 1)
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
--
-- The record stores Uid + Id ONLY. Boosts are resolved from PetConfig on read (see
-- boostsFor) so rebalances apply retroactively; baking them in here is what would
-- freeze every owned pet at its hatch-day numbers.
function PetHandler.Grant(player, petId)
	local def = PetConfig.Pets[petId]
	if not def then return false end
	local data = PlayerDataManager.Get(player)
	if not data then return false end
	data.Pets = data.Pets or {}

	local uid = HttpService:GenerateGUID(false)
	table.insert(data.Pets, { Uid = uid, Id = petId })
	PlayerDataManager.PushUpdate(player)
	return true, uid
end

-- Read by the bag UI so it never has to duplicate the rarity/boost lookup.
function PetHandler.Describe(petId)
	local def = PetConfig.Pets[petId]
	if not def then return nil end
	local luck, income = PetConfig.BoostsFor(petId)
	return { Id = petId, Name = def.Name, Rarity = def.Rarity, Luck = luck, Income = income }
end

-- === Follow rig ================================================================
-- The rig is the pet's REAL model, cloned out of ReplicatedStorage.PetModels --
-- the 15 imported .glb pets, each folder child named after its source file (see
-- PetConfig's Model field).
--
-- ReplicatedStorage.BrainrotModels is kept as a SECOND lookup, not dead weight:
-- the ten retired stand-in pets (PetConfig's "RETIRED" block) are brainrots, and
-- a player who hatched one during testing still owns it and still deserves a rig
-- rather than the placeholder cube. New pets resolve from PetModels; old ones
-- fall through to BrainrotModels; anything in neither gets the placeholder.
--
-- Every part is Massless + CanCollide=false + CanQuery=false: an unanchored multi-part
-- assembly welded together must not add mass or a hitbox to whatever it is following
-- (see InventoryHandler's identical note on held-tool visuals). CanQuery=false also keeps
-- a pet out of the throw/aim raycasts -- a pet floating behind you must never be a
-- surface you can land a rock on.
-- Studs on the model's largest axis after scaling. 2.6 read as tiny next to a ~5-stud
-- character; 4.0 makes a pet a companion rather than a trinket. These models are tall
-- and narrow (e.g. 2.11 x 6.83 x 5.43), so normalising the LARGEST axis to 4.0 leaves
-- them only ~1.2-1.6 studs wide -- still clear of each other at the 3.6-stud lateral
-- spacing of slots 1 and 2.
local PET_TARGET_SIZE = 4.0

-- Resolved lazily rather than at require time: PetModels does not exist until the
-- art is imported, and a nil captured at boot would never recover without a
-- server restart.
local function rsFolder(name)
	return ReplicatedStorage:FindFirstChild(name)
end

-- petId is preferred; creatureName is what the old stand-in pets are stored under.
local function findPetSource(petId, creatureName)
	local def = petId and PetConfig.Pets[petId]
	local pets = rsFolder("PetModels")
	if pets and def and def.Model then
		local hit = pets:FindFirstChild(def.Model)
		if hit then return hit end
	end
	-- tolerate the model being renamed to the pet's display name on import
	if pets and creatureName then
		local hit = pets:FindFirstChild(creatureName)
		if hit then return hit end
	end
	local brainrots = rsFolder("BrainrotModels")
	return brainrots and creatureName and brainrots:FindFirstChild(creatureName) or nil
end

local function buildPetModel(creatureName, petId)
	local source = findPetSource(petId, creatureName)
	if not source then return nil end

	local model = source:Clone()
	model.Name = "PetRig"

	-- Defensive strip: these models are pure parts today, but a script, prompt or sound
	-- riding along on a clone that follows the player would be live, six times over.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ProximityPrompt") or d:IsA("Sound")
			or d:IsA("ClickDetector") then
			d:Destroy()
		end
	end

	local biggest, biggestVol
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Anchored = false
			local vol = d.Size.X * d.Size.Y * d.Size.Z
			if not biggestVol or vol > biggestVol then biggest, biggestVol = d, vol end
		end
	end
	if not biggest then model:Destroy() return nil end
	if not model.PrimaryPart then model.PrimaryPart = biggest end
	local root = model.PrimaryPart

	-- Weld everything to the root. A clone's parts are not guaranteed to arrive jointed,
	-- and an unwelded assembly under AlignPosition comes apart in mid-air.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
		end
	end

	-- Normalise to pet scale: these are brainrot models built at 6-7 studs tall, which
	-- would tower over the character if followed at source size.
	local _, bsize = model:GetBoundingBox()
	local largest = math.max(bsize.X, bsize.Y, bsize.Z)
	if largest > 0 then
		local scale = math.clamp(PET_TARGET_SIZE / largest, 0.05, 1)
		pcall(function() model:ScaleTo(scale) end)
	end

	return model, model.PrimaryPart
end

-- Placeholder, used only when a pet's creature has no model in BrainrotModels. Keeps a
-- missing asset from meaning "equip silently does nothing visible".
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
-- [player] = { { att = Attachment, baseY = number, phase = number } }. Drives the bob.
-- Kept separate from rigFolders because the bob animates the HRP-side attachment, not the
-- rig: AlignPosition is already chasing that attachment every frame, so moving IT makes
-- the pet bob smoothly whether the player is standing still or sprinting. Animating the
-- rig part directly would fight the constraint instead of riding it.
local bobbers = {}
local bobConn

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
	bobbers[player] = nil
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

	-- Where the player's feet are, relative to the HumanoidRootPart's centre. HipHeight is
	-- the gap from the root's BOTTOM face to the ground, so the full drop from its centre
	-- is HipHeight + half the root's height.
	local hum = character:FindFirstChildOfClass("Humanoid")
	local footDrop = ((hum and hum.HipHeight) or 2) + (hrp.Size.Y * 0.5)

	for i, uid in ipairs(data.PetSlots) do
		if petByUid[uid] then
			local slot = SLOT_OFFSETS[i] or SLOT_OFFSETS[#SLOT_OFFSETS]
			local pet = petByUid[uid]
			local def = pet and PetConfig.Pets[pet.Id]
			local model, root = buildPetModel(def and def.Name, pet.Id)
			if not model then model, root = buildAcorn() end

			-- How far the PrimaryPart sits above the model's own underside, so the slot
			-- height can mean "the pet's feet" instead of "wherever this particular model
			-- happens to keep its PrimaryPart".
			local bbCf, bbSize = model:GetBoundingBox()
			local modelLift = root.Position.Y - (bbCf.Position.Y - bbSize.Y * 0.5)
			local offset = Vector3.new(slot.X, -footDrop + PET_FOOT_CLEARANCE + modelLift, slot.Y)

			-- PivotTo moves the whole welded assembly via its PrimaryPart, so this both
			-- places the rig and keeps its parts together; setting root.CFrame as well
			-- would just be the same write twice.
			model:PivotTo(hrp.CFrame * CFrame.new(offset))
			model.Parent = folder

			local petAttach = Instance.new("Attachment")
			petAttach.Name = "PetAttach"
			petAttach.Parent = root

			local hrpAttach = Instance.new("Attachment")
			hrpAttach.Name = "PetSlot" .. i
			hrpAttach.Position = offset
			hrpAttach.Parent = hrp

			-- register for the bob; the phase step keeps slots from bobbing in lockstep
			bobbers[player] = bobbers[player] or {}
			table.insert(bobbers[player], {
				att = hrpAttach,
				baseY = offset.Y,
				phase = (i - 1) * PetConfig.BOB_PHASE_STEP,
			})

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

-- One shared Heartbeat for every player's every pet, rather than a loop per rig: the
-- work is a sine and a Vector3 write per equipped pet, so a single pass is cheaper than
-- the connection churn of building and tearing one down on every equip.
local function startBob()
	if bobConn then return end
	local RunService = game:GetService("RunService")
	bobConn = RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local w = (2 * math.pi) / math.max(0.05, PetConfig.BOB_PERIOD)
		local amp = PetConfig.BOB_HEIGHT * 0.5
		for player, list in pairs(bobbers) do
			for idx = #list, 1, -1 do
				local b = list[idx]
				if b.att.Parent then
					local p = b.att.Position
					b.att.Position = Vector3.new(p.X, b.baseY + math.sin(t * w + b.phase) * amp, p.Z)
				else
					-- character respawned out from under it; drop the dead entry
					table.remove(list, idx)
				end
			end
			if #list == 0 then bobbers[player] = nil end
		end
	end)
end

function PetHandler.Init()
	petEquipRemote.OnServerEvent:Connect(onPetEquip)
	startBob()

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
