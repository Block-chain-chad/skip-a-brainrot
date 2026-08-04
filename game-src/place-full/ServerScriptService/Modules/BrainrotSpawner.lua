-- Single source of truth for putting a brainrot on a plot pad.
--
-- Two visuals, one code path: if ServerStorage.BrainrotModels holds a model whose
-- name matches the config entry, it is cloned; otherwise the entry falls back to the
-- tier-coloured neon cube every brainrot used before real models existed. Adding a
-- model is therefore a content drop, not a code change.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local MutationFX = require(ReplicatedStorage.Modules.MutationFX)

local M = {}

local entryByName, tierByName = {}, {}
for _, e in ipairs(BrainrotConfig) do entryByName[e.Name] = e end
for _, t in ipairs(RarityConfig) do tierByName[t.Name] = t end

-- ===== idle motion policy =====
-- BrainrotIdleClient animates any Model tagged "BrainrotBody" by its Motion
-- attribute (bob/sway/hover/spin/shiver -- the presets live in that script).
-- The ladder makes motion itself a rarity read: grounded tiers rock or bob in
-- place, Epic/Legendary lift off and slowly turn, the top tiers do a lazy
-- showcase spin, and Secrets shiver. A BrainrotConfig entry can override any
-- of it with Motion = "spin" etc.; unknown values cost nothing client-side
-- (adopt() ignores what it does not recognise).
local MOTION_BY_RARITY = {
	Common = "ground", Uncommon = "ground", Rare = "ground",
	Epic = "hover", Legendary = "hover",
	Mythic = "spin", God = "spin",
	Secret = "shiver",
}
local function motionFor(entry)
	if entry.Motion then return entry.Motion end
	local m = MOTION_BY_RARITY[entry.Rarity] or "ground"
	if m == "ground" then
		-- deterministic bob/sway split so a row of Commons does not move in
		-- unison; same hash shape BrainrotIdleClient uses for phase stagger
		local h = 0
		for i = 1, #entry.Name do
			h = (h * 33 + string.byte(entry.Name, i)) % 8192
		end
		return (h % 2 == 0) and "bob" or "sway"
	end
	return m
end

-- Authored models are normalised to one height instead of being trusted at their
-- authored scale: Secret Pete is 9.71 studs tall, which on a 5x5 pad would dwarf the
-- plot, overlap its neighbours and push the billboard out of view.
-- Pads are 5x5 with 6.51 studs between centres, so WIDTH is the real constraint,
-- not height -- nothing is above a brainrot to collide with. Normalising by height
-- alone was the bug: the roster's width:height ratio runs from 0.37 to 4.06, so the
-- widest models sprawled across their neighbours while the tall thin ones looked
-- tiny. Fit each model to a BOX instead and the whole roster can grow.
local MODEL_HEIGHT = 6.0        -- target height (was 3.6)
-- Pad centres are 6.51 apart, so this is pushed as close to that as it can go
-- without neighbours touching. It is the binding limit for roughly half the
-- roster (median width:height is 0.94) -- going bigger than this needs either
-- accepted overlap or wider pad spacing on the plot itself.
local MODEL_MAX_WIDTH = 6.3

local function templateFor(name)
	-- moved to ReplicatedStorage so IndexClient can render real silhouettes from these
	-- same models; the server reads them from there instead of ServerStorage now
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	return folder and folder:FindFirstChild(name) or nil
end

local function buildModelVisual(template, pad)
	local model = template:Clone()
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end

	local _, extents = model:GetBoundingBox()
	if extents.Y > 0 then
		-- HeightScale lets the authored size ladder read on the plot (a Secret
		-- should tower over a Common) while the clamp stops any one model running away.
		local heightScale = math.clamp(template:GetAttribute("HeightScale") or 1, 0.7, 1.5)
		local width = math.max(extents.X, extents.Z)
		-- whichever limit bites first: tall-thin models go to full height, wide ones
		-- are held back by their footprint so they never cross onto a neighbour's pad
		local factor = math.min(
			(MODEL_HEIGHT * heightScale) / extents.Y,
			MODEL_MAX_WIDTH / math.max(width, 0.01)
		)
		-- ScaleTo is ABSOLUTE, so go through the current scale rather than assuming 1
		model:ScaleTo(model:GetScale() * factor)
	end

	-- Sit the model's BASE on the pad. PivotTo moves the PIVOT, which on a hand-built
	-- model is wherever the author left it and not the bounding-box centre -- so measure
	-- the box after scaling and translate by the delta rather than assuming they agree.
	local boxCF, boxSize = model:GetBoundingBox()
	local target = pad.Position + Vector3.new(0, pad.Size.Y * 0.5 + boxSize.Y * 0.5 + 0.05, 0)
	model:PivotTo(model:GetPivot() + (target - boxCF.Position))

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end

	-- Centre the model's pivot on its bounding box, upright. The pack models'
	-- authored PrimaryPart is an arbitrary limb -- often carrying its own
	-- authored PivotOffset -- so GetPivot lands studs off the visual body
	-- (CatchReveal measured 3.75 on a real one; Carloo is 1.42). Everything
	-- that rotates or measures a placed body (BrainrotIdleClient's idle yaw,
	-- the store prompt, walk-up feel) wants the visual centre, and a centred
	-- pivot makes the idle client's rel-capture immune to replication-order
	-- races. NOTE: Model.WorldPivot writes are a silent no-op on these models
	-- (probed live); write the PrimaryPart's PivotOffset directly.
	if model.PrimaryPart then
		local cf = model:GetBoundingBox()
		model.PrimaryPart.PivotOffset = model.PrimaryPart.CFrame:ToObjectSpace(CFrame.new(cf.Position))
	end
	return model
end

-- entryOrName: a BrainrotConfig entry, or its Name
function M.Spawn(plot, entryOrName, padIndex, mutation, uid)
	if not plot or not padIndex then return nil end
	local entry = type(entryOrName) == "table" and entryOrName or entryByName[entryOrName]
	if not entry then return nil end
	local pads = plot:FindFirstChild("Pads")
	if not pads then return nil end
	local pad = pads:FindFirstChild("Pad" .. padIndex)
	if not pad then return nil end

	local tier = tierByName[entry.Rarity]

	local template = templateFor(entry.Name)
	local model
	if template then
		model = buildModelVisual(template, pad)
	else
		model = Instance.new("Part")
		model.Size = Vector3.new(2.5, 2.5, 2.5)
		model.Material = Enum.Material.Neon
		model.Color = tier and tier.Color or Color3.fromRGB(255, 255, 255)
		model.Anchored = true
		model.CanCollide = false
		model.CFrame = pad.CFrame * CFrame.new(0, 1.8, 0)
	end
	model.Name = entry.Name
	model.Parent = pads
	model:SetAttribute("PadIndex", padIndex)
	if uid then model:SetAttribute("Uid", uid) end

	-- idle motion: only authored Models breathe -- the fallback cube is a
	-- marker, not a creature (and BrainrotIdleClient ignores non-Models
	-- anyway). Tag + attribute replicate, so the client needs no new wiring;
	-- this line is what turns the whole dormant idle system on.
	if model:IsA("Model") then
		model:SetAttribute("Motion", motionFor(entry))
		CollectionService:AddTag(model, "BrainrotBody")
	end

	-- walk up to a placed brainrot to put it back in your backpack
	local storePrompt = Instance.new("ProximityPrompt")
	storePrompt.Name = "StorePrompt"
	storePrompt.ActionText = "Store"
	storePrompt.ObjectText = entry.Name
	storePrompt.KeyboardKeyCode = Enum.KeyCode.E
	storePrompt.HoldDuration = 0.35
	storePrompt.MaxActivationDistance = 9
	storePrompt.RequiresLineOfSight = false
	-- MUST stay parented to the top-level instance: InventoryClient reads the Uid off
	-- prompt.Parent, so hanging this on a child part would silently break Store.
	storePrompt.Parent = model

	-- No collect prompt here on purpose: takings are picked up by WALKING OVER the
	-- brainrot (IncomeLoop.WALKUP_COLLECT), so there is nothing to press.

	if mutation then
		model:SetAttribute("Mutation", mutation)
		local isPart = model:IsA("BasePart")
		local mColor = Mutations.Color(mutation) or (isPart and model.Color) or Color3.fromRGB(255, 255, 255)
		-- Recolour the placeholder cube, but never an authored model: flattening all 47
		-- of Pete's parts to one colour would erase the thing that makes him readable.
		if isPart then model.Color = mColor end
		-- All twelve mutations used to render identically here (one light, one
		-- emitter, tinted). MutationFX scales the presentation up the 12-rung
		-- rarity ladder instead, so a Glitched no longer looks like a Golden.
		MutationFX.apply(model, mutation)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 140, 0, 36)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	-- Set HERE, not on an instance in Studio: this billboard is rebuilt every time a
	-- brainrot is spawned or a plot is restored, so an authored value would be discarded.
	-- 150 matches the campfire BankGui on the same plot, so everything plot-side fades
	-- together rather than a name tag hanging in the air after its plot has gone.
	-- With up to 16 pads across 6 plots these are the most numerous labels in the game;
	-- uncapped, every plot on the map was drawing text at you from anywhere.
	billboard.MaxDistance = 150
	-- Direct child of the top-level instance, because IncomeLoop finds it with
	-- FindFirstChildOfClass (not a recursive search). A Model has no surface of its own,
	-- so it needs an explicit Adornee.
	billboard.Parent = model
	if not model:IsA("BasePart") and model.PrimaryPart then
		billboard.Adornee = model.PrimaryPart
		-- The offset is measured from the ADORNEE, and on these pack models the
		-- PrimaryPart is an arbitrary limb (RootPart, Head, a hand) sitting anywhere
		-- inside the body -- so a fixed lift puts the label through the model's chest
		-- on some and miles above it on others. Measure the real gap to the top of the
		-- bounding box instead. This matters much more now models are 6 studs tall.
		local boxCF, boxSize = model:GetBoundingBox()
		local toTop = (boxCF.Position.Y + boxSize.Y / 2) - model.PrimaryPart.Position.Y
		billboard.StudsOffset = Vector3.new(0, toTop + 1.2, 0)
	end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = (mutation and (mutation .. " ") or "") .. entry.Name .. "\n\u{1F4B0} $0"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard

	return model
end

-- Wipe any existing brainrot models on the plot, then replay the saved list.
function M.RestoreAll(plot, brainrots)
	if not plot or not brainrots then return 0 end
	local pads = plot:FindFirstChild("Pads")
	if not pads then return 0 end
	for _, c in ipairs(pads:GetChildren()) do
		if not c.Name:match("^Pad%d+$") then c:Destroy() end
	end
	local placed = 0
	for _, e in ipairs(brainrots) do
		if e.PadIndex and M.Spawn(plot, e.Name, e.PadIndex, e.Mutation, e.Uid) then
			placed += 1
		end
	end
	return placed
end

return M
