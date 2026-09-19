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
-- needed to index EVERY world's roster, not just the valley's -- see entryByName below
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local MutationFX = require(ReplicatedStorage.Modules.MutationFX)
local MutationVisuals = require(ReplicatedStorage.Modules.MutationVisuals)
local Sizes = require(ReplicatedStorage.Modules.SizeConfig)

local M = {}

-- EVERY WORLD, not just the valley (fixed 2026-08-07). This was built from
-- BrainrotConfig alone, so the 30 tundra-exclusive brainrots resolved to nil here and
-- Spawn(plot, "<tundra name>", ...) returned nil at its `if not entry` guard -- meaning
-- a caught tundra brainrot could be owned and saved but could NEVER be placed on a camp.
-- InventoryHandler already walked WorldProgression.List(); this now matches it.
-- Valley first, so a name present in both keeps its World 1 entry.
local entryByName, tierByName = {}, {}
for _, e in ipairs(BrainrotConfig) do entryByName[e.Name] = e end
for _, t in ipairs(RarityConfig) do tierByName[t.Name] = t end
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	for _, e in ipairs((world and world.Pool) or {}) do
		if not entryByName[e.Name] then entryByName[e.Name] = e end
	end
	for _, t in ipairs((world and world.Rarities) or {}) do
		if not tierByName[t.Name] then tierByName[t.Name] = t end
	end
end

-- ===== idle motion policy =====
-- BrainrotIdleClient animates any Model tagged "BrainrotBody" by its Motion
-- attribute (bob/sway/hover/spin/shiver -- the presets live in that script).
-- The WHOLE roster now shares ONE idle: "hover" -- a slow up-and-down bob plus a
-- slow spin (the Ballerina Cappuccina look the user picked). Rarity no longer
-- changes the motion. Phase is still staggered per body (BrainrotIdleClient hashes
-- name + spawn position), so a row of the same brainrot does not move in unison.
-- A BrainrotConfig entry can still force a different Motion = "spin" etc.; unknown
-- values cost nothing client-side (adopt() ignores what it does not recognise).
local function motionFor(entry)
	return entry.Motion or "hover"
end

-- Authored models are normalised to one height instead of being trusted at their
-- authored scale: Secret Pete is 9.71 studs tall, which on a 5x5 pad would dwarf the
-- plot, overlap its neighbours and push the billboard out of view.
-- Pads are 5x5, and WIDTH is the real constraint, not height -- nothing is above a
-- brainrot to collide with. Normalising by height alone was the bug: the roster's
-- width:height ratio runs from 0.37 to 4.06, so the widest models sprawled across
-- their neighbours while the tall thin ones looked tiny. Fit each model to a BOX
-- instead and the whole roster can grow.
local MODEL_HEIGHT = 6.0        -- target height (was 3.6)
-- CAMPS WERE WIDENED 2026-08-07 to make big brainrots possible. Pad centres used to
-- be 6.51 apart, which capped width at 6.3 -- and because the cap is a math.min
-- against the height limit, that made the WIDEST models render SMALLEST. The Kraken
-- (8.6 x 6.6) came out 4.85 studs tall while a thin popsicle got the full 6.0, so the
-- most imposing creatures were the runts of the plot.
--
-- The two pad rings were pushed out (ring 1: 8.5 -> 13.0, ring 2: 14.0 -> 20.5) and the
-- fence/dressing/platform scaled with them. Closest pair is now 9.84 studs apart -- and
-- note that pair is ring1-to-ring2, not ring1-to-ring1: the rings interlock at 22.5
-- degrees, so the diagonal is what binds, which is why moving one ring alone made things
-- WORSE and both had to move together.
local MODEL_MAX_WIDTH = 9.5     -- 9.84 gap minus a little air

-- Share of a model's own longest bbox dimension below which a part is treated as
-- sub-visual ON A PLOT and dropped from the SPAWNED CLONE only. See the long note
-- in buildModelVisual for the measurements behind this number.
local TINY_SHARE = 0.04

-- WIDTH BUDGET SHARE (added 2026-08-22 for the ice-fishing fish).
-- MODEL_MAX_WIDTH is an absolute ceiling, and for any model whose authored box is
-- much wider than it is tall, that ceiling is what sets the final size -- the height
-- term never gets a look in. Measured across the 23 fish: for five of them (tadpole,
-- starfish, seal, narwhal, hammerhead) the cap binds across the WHOLE legal
-- HeightScale range, so HeightScale changed nothing at all, and a tadpole rendered
-- with exactly the same 9.5-stud footprint as a hammerhead shark.
-- WidthScale is that model's SHARE of the pad width budget. Default 1 is the old
-- behaviour to the last decimal, so none of the 192 models that predate this are
-- touched; a small creature opts in to a smaller share and finally reads small.
-- Clamped at 1 on purpose: this can only ever hold a model BACK, never let one
-- sprawl past the cap onto a neighbour's pad.
local MIN_WIDTH_SHARE = 0.35

local function templateFor(name)
	-- === PLOT COPY FIRST (2026-08-24) ======================================
	-- BrainrotModelsPlot holds coarser rebuilds of the heaviest models: the same
	-- creature resampled onto a 3x (or 2x) voxel lattice and greedy-meshed, which
	-- is the right fidelity for a body standing on a pad and seen from across a
	-- camp. 17,287 parts became 2,931 across the 43 models that qualified.
	--
	-- A MISS IS NOT A FAILURE. Only models that passed the silhouette gate are in
	-- that folder -- 11 were refused because coarsening broke them (antlers, thin
	-- limbs) and 161 were already cheap enough to leave alone. Falling through to
	-- the authored model is the correct answer for every one of those, so this
	-- cannot break a model it does not know about.
	--
	-- Everything that shows a brainrot CLOSE UP still reads BrainrotModels on
	-- purpose: BrainrotThumb's card art, the Index, and PullCeremony's reveal.
	local plot = ReplicatedStorage:FindFirstChild("BrainrotModelsPlot")
	local reduced = plot and plot:FindFirstChild(name)
	if reduced then return reduced end
	-- moved to ReplicatedStorage so IndexClient can render real silhouettes from these
	-- same models; the server reads them from there instead of ServerStorage now
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	return folder and folder:FindFirstChild(name) or nil
end

-- sizeVariant is the SIZE mutation ("Huge" / "Massive" / nil), which multiplies the
-- fitted scale. It is passed in rather than read off the model because the Mutation
-- attribute is not written until further down in Spawn, well after the fit happens.
local function buildModelVisual(template, pad, sizeVariant)
	local model = template:Clone()
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end

	local _, extents = model:GetBoundingBox()
	if extents.Y > 0 then
		-- HeightScale lets the authored size ladder read on the plot (a Secret
		-- should tower over a Common) while the clamp stops any one model running away.
		local heightScale = math.clamp(template:GetAttribute("HeightScale") or 1, 0.7, 1.5)
		-- see MIN_WIDTH_SHARE above: without this a long low creature ignores its
		-- HeightScale entirely and always renders at the full pad width
		local widthScale = math.clamp(template:GetAttribute("WidthScale") or 1, MIN_WIDTH_SHARE, 1)
		local width = math.max(extents.X, extents.Z)
		-- whichever limit bites first: tall-thin models go to full height, wide ones
		-- are held back by their footprint so they never cross onto a neighbour's pad
		local factor = math.min(
			(MODEL_HEIGHT * heightScale) / extents.Y,
			(MODEL_MAX_WIDTH * widthScale) / math.max(width, 0.01)
		)
		-- SIZE MUTATION, applied AFTER the box fit and deliberately OUTSIDE the min():
		-- a Huge/Massive is supposed to break the pad-width budget and sprawl over its
		-- neighbours. Clamping it here would defeat the entire point of the variant.
		-- Safe to overlap: every part of a placed brainrot has CanCollide off, so this
		-- is purely visual and nothing gets shoved off its pad.
		factor = factor * Sizes.Scale(sizeVariant)
		-- ScaleTo is ABSOLUTE, so go through the current scale rather than assuming 1
		model:ScaleTo(model:GetScale() * factor)
	end

	-- Sit the model's BASE on the pad. PivotTo moves the PIVOT, which on a hand-built
	-- model is wherever the author left it and not the bounding-box centre -- so measure
	-- the box after scaling and translate by the delta rather than assuming they agree.
	local boxCF, boxSize = model:GetBoundingBox()
	local target = pad.Position + Vector3.new(0, pad.Size.Y * 0.5 + boxSize.Y * 0.5 + 0.05, 0)
	model:PivotTo(model:GetPivot() + (target - boxCF.Position))

	-- === SPAWN-TIME COST TRIM (2026-08-24) ===================================
	-- A plot body is seen from across a camp, standing on a pad, about six studs
	-- tall. It does not need the fidelity the TEMPLATE carries for close-up
	-- viewport art and the catch reveal -- and only this CLONE is trimmed, so
	-- BrainrotThumb, PullCeremony and the Index are all untouched.
	--
	-- WHY: twelve heavy bodies measured 8,811 parts on ONE plot, and eighteen
	-- plots project to ~158,000 parts of brainrot alone. BrainrotIdleClient's LOD
	-- blanks distant bodies, but a blanked part still EXISTS -- it still costs
	-- instance memory and replication on every client, which is what an unplayable
	-- frame rate after a wave of plot claims actually looks like.
	--
	-- THE THREE FLAGS: parts default to casting shadows and to being query/touch
	-- candidates. Across eighteen populated plots that is ~10,000 shadow casters
	-- and ~9,600 query candidates that nothing ever raycasts against.
	--
	-- THE TINY CULL: measured across all 215 models, dropping parts whose largest
	-- dimension is under TINY_SHARE of the model's own bounding box removes 14% of
	-- every part in the pack for 0.0% of its volume -- these are 0.17-stud specks
	-- on a 6-stud body, sub-pixel at any range a plot is ever viewed from. It is
	-- deliberately conservative: at 0.06 one model starts losing 30% of its volume,
	-- so raising this eats real silhouette. Skips the PrimaryPart and anything
	-- carrying a child (Motor6D, Weld, Attachment, emitter) so a rigged model or an
	-- effect anchor can never be cut out from under itself.
	local tinyBelow = math.max(boxSize.X, boxSize.Y, boxSize.Z) * TINY_SHARE
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d ~= model.PrimaryPart
				and #d:GetChildren() == 0
				and math.max(d.Size.X, d.Size.Y, d.Size.Z) < tinyBelow then
				d:Destroy()
			else
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			end
		end
	end

	-- === WELD THE BODY INSTEAD OF ANCHORING EVERY PART (2026-08-25) ==========
	-- MEASURED root cause of the multiplayer frame collapse. BrainrotIdleClient
	-- animates every in-range body each Heartbeat with Model:PivotTo(). With every
	-- part individually Anchored and NO welds there is no assembly to move, so
	-- PivotTo writes EVERY part's CFrame one at a time in Lua: the cost is
	-- O(parts) per body per frame, which is why the game is fine alone and dies
	-- the moment other people's plots come into range.
	--
	-- Measured on a 494-part body (Inverno Eterno), same machine, same session:
	--     all anchored, no welds : PivotTo = 0.2682 ms
	--     root anchored + welds  : PivotTo = 0.0323 ms   -- 8.3x faster
	-- Across the 48 bodies the idle loop animates at once that was 5.42 ms of a
	-- 16.7 ms frame spent purely MOVING them, before anything is drawn. Camera
	-- near the plots measured 32.9 Hz; the same instances with the camera turned
	-- away, animating nothing, measured 59.5 Hz.
	--
	-- RULED OUT FIRST, by measurement, so nobody re-chases them: instance count
	-- (tripling workspace parts cost 2.8% of Heartbeat), rendering (30,578 parts
	-- held a locked 60 FPS with the GPU DOWNCLOCKED at 13-33%), the loop's own
	-- distance check (0.009 ms for 80 bodies), and the whole FX layer (disabling
	-- all 240 ParticleEmitters, 129 BillboardGuis and 239 Lights changed nothing).
	--
	-- Welds are created while everything is still anchored, and only then is
	-- everything but the root released -- so no part is ever unanchored and
	-- unwelded at the same time, and nothing can fall. Anchoring the ROOT keeps
	-- the body immovable exactly as before; the welded parts inherit that.
	-- A model with no PrimaryPart keeps the old all-anchored behaviour.
	-- REVERT: ServerStorage.AuditBackups.BrainrotSpawner_pre_weld
	local weldRoot = model.PrimaryPart
	if weldRoot then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= weldRoot then
				local w = Instance.new("WeldConstraint")
				w.Part0 = weldRoot
				w.Part1 = d
				w.Parent = weldRoot
			end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = (d == weldRoot)
			end
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
-- sizeVariant: the SIZE mutation ("Huge"/"Massive"/nil). Appended LAST so every existing
-- caller keeps working untouched -- an omitted size reads nil, which is "normal".
function M.Spawn(plot, entryOrName, padIndex, mutation, uid, sizeVariant)
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
		model = buildModelVisual(template, pad, sizeVariant)
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

	-- NO StorePrompt any more (2026-08-12 rework): picking up moved into the Bag
	-- panel -- click the brainrot's card (or its plot-rack slot) to store it. The
	-- old hold-E prompt, and the size-scaled reach maths that kept it usable on a
	-- Massive, retired together with the Tool system.

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

		--[[ THE PACK'S ADD-ON GEOMETRY, on every mutated brainrot standing on a pad.

		MutationFX above paints the creature's own surfaces with the pack's colour,
		material and glow. What it cannot do is add things that are not on the
		creature: Demon's horns, Angel's halo and wings, Frozen's ice crust, Wet's
		drips and puddle, Sandy's drift, Celestial's ring and orbiting stars. Those are
		real geometry in the pack, and without them a Demon is just a dark brainrot.

		bodyShell is DELIBERATELY ABSENT -- see the long note at CatchReveal's call
		site. Voxelising a mesh creature fills its bounding box solid and turns it into
		a coloured brick; only the add-ons are safe, because they are additive and do
		not depend on guessing what the mesh occupies.

		CHEAP ENOUGH FOR A FULL PLOT. Measured across the twelve: six of them add
		nothing at all (the pack gives them no geometry), and the two heaviest are
		Angel at 337 parts and Frozen at 309. A 16-pad plot of the worst case is ~5,400
		parts, and in practice mutations are rare -- Golden is the commonest at 13.5%.

		pcall'd because a pad spawn must never fail over decoration: the brainrot
		earning money matters more than its horns. ]]
		local okSkin, MutationSkin = pcall(require, ReplicatedStorage.Modules:FindFirstChild("MutationSkin"))
		if okSkin and MutationSkin then
			pcall(MutationSkin.Build, model, mutation, { maxParts = 1200 })
		end
	end

	-- 2026-08-13 mutation nameplate (design handoff): the mutation gets its own
	-- PILL above the name -- it does not prefix the name -- so long names stay
	-- readable and the plate colour is the first thing a player sees. (The old
	-- prefix also silently vanished on the first income tick, which rewrote the
	-- label without it; the pill fixes that bug by construction.) IncomeLoop's
	-- updateBillboard writes ONLY the Main/Rate labels and reads the HasPill
	-- attribute for its layout, so the two writers never fight.
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 160, 0, mutation and 82 or 56)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard:SetAttribute("HasPill", mutation ~= nil)
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

	if mutation then
		local v = MutationVisuals.For(mutation)
		local pill = Instance.new("Frame")
		pill.Name = "MutationPill"
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, 0)
		pill.Size = UDim2.new(0, 0, 0, 22)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.BackgroundColor3 = Color3.new(1, 1, 1)
		pill.BorderSizePixel = 0
		pill.Parent = billboard
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 999) -- UIKit pill radius
		corner.Parent = pill
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Color = Color3.fromHex("202020") -- UIKit ink
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = pill
		local grad = Instance.new("UIGradient")
		local seq, angle = MutationVisuals.PlateSequence(mutation)
		if seq then grad.Color = seq end
		grad.Rotation = angle or 90
		grad.Parent = pill
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = pill
		local txt = Instance.new("TextLabel")
		txt.Name = "PillText"
		txt.BackgroundTransparency = 1
		txt.Size = UDim2.new(0, 0, 1, 0)
		txt.AutomaticSize = Enum.AutomaticSize.X
		txt.Font = Enum.Font.GothamBold
		txt.TextSize = 13
		txt.Text = mutation:upper()
		txt.TextColor3 = Color3.new(1, 1, 1)
		txt.TextStrokeTransparency = 0
		txt.TextStrokeColor3 = Color3.fromHex("202020")
		txt.Parent = pill
	end

	local label = Instance.new("TextLabel")
	label.Name = "Main"
	label.Size = UDim2.new(1, 0, 0, 40)
	label.Position = UDim2.new(0, 0, 0, mutation and 24 or 0)
	label.BackgroundTransparency = 1
	label.Text = entry.Name .. "\n\u{1F4B0} $0"
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
		if e.PadIndex and M.Spawn(plot, e.Name, e.PadIndex, e.Mutation, e.Uid, e.Size) then
			placed += 1
		end
	end
	return placed
end

return M
