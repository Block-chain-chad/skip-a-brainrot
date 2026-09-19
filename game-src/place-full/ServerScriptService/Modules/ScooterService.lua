--[[ ============================================================================
ScooterService -- the VIP electric scooter (2026-08-09).

A Tool in the backpack rather than a vehicle: equip it and you are riding, unequip
and you are walking. No seat, no VehicleSeat, no network-ownership handover -- the
scooter is a welded prop plus two Humanoid numbers, which is the version that
cannot desync, cannot be left behind in the world, and cannot strand a player
sitting on a model that failed to load.

WHO OWNS WHAT, because the speed is the part that is easy to get wrong:

  THIS MODULE (server)  hands out the Tool, welds the prop on equip, and sets
                        player:SetAttribute("ScooterOn"). It never touches
                        WalkSpeed or JumpPower.
  ClientMain            owns Humanoid.WalkSpeed -- its sprint code writes that
                        property on every input and every respawn, so anything
                        set from here would be overwritten within a frame. It
                        reads the attribute and folds the scooter into the same
                        one writer, and owns the jump swap beside it.

Attributes replicate on their own and re-replicate to late joiners, so the flag
needs no remote.

GRANTED BY FLAG, not by pass key: any pass whose Effects carry Scooter = true
hands one out (today that is VIP). While every GamepassId is still 0 nobody owns
anything, so this module quietly does nothing -- same inert-until-real convention
as the rest of the monetization.

GearBlocker strips Tools that are not the game's own, so the Tool carries the
GameItem attribute it looks for, set BEFORE it is ever parented.
============================================================================ ]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local GamepassService = require(ServerScriptService.Modules.GamepassService)

local ScooterService = {}

-- HOW A CHARACTER STANDS ON ANYTHING IN ROBLOX. A Humanoid pins its feet to the
-- ground, so a prop welded "under the feet" is really welded into the floor -- the
-- first build of this had the deck at the foot plane and the wheels 0.45 studs
-- underground, invisible from any angle you actually play at.
--
-- The fix is the same one skateboards and vehicles use: the RIDER goes up.
-- ClientMain adds SCOOTER_LIFT to Humanoid.HipHeight while riding, which raises the
-- character off the floor without moving their feet relative to the root -- so the
-- deck, welded just below the foot plane, sits in the gap it opens up.
--
-- IT HOVERS NOW (2026-08-09). The wheels are gone: a wheel that never spins while you
-- glide reads as a bug, and the ride this is meant to feel like has no wheels at all.
-- Two glowing pads sit under the deck instead, and the lift leaves a visible band of
-- air beneath them -- which is what sells the float when it starts bobbing.
--
-- BOTH HALVES NEED THIS NUMBER and they cannot share it: this module lives in
-- ServerScriptService, which no client can require. ClientMain mirrors it as a
-- literal, named against this constant in a comment there. If one moves, move both
-- -- they disagree and the scooter either floats away or sinks into the floor.
ScooterService.LIFT = 0.7

local DECK_HALF = 0.09        -- half the deck's thickness
local PAD_DROP = 0.16         -- hover-pad centre below the deck centre
local PAD_HALF = 0.05

local TOOL_NAME = "Electric Scooter"
local FLAG = "Scooter"          -- GamepassConfig Effects key
local RIDING_ATTR = "ScooterOn" -- read by ClientMain's sprint/jump writer

local BODY = Color3.fromRGB(34, 38, 48)
local TRIM = Color3.fromRGB(90, 225, 255)
local RUBBER = Color3.fromRGB(20, 20, 22)

local function piece(parent, name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	-- A rider's own prop must not shove them, block a raycast, or weigh anything:
	-- a collidable scooter under the feet fights the Humanoid's floor detection and
	-- reads as the character juddering.
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Built in LOCAL space around the deck at the origin, then moved as one piece and
-- welded. Forward is -Z, matching a CFrame's LookVector, so the handlebars end up
-- in front of the rider rather than behind them.
local function buildScooter()
	local model = Instance.new("Model")
	model.Name = "ElectricScooter"

	local deck = piece(model, "Deck", Vector3.new(0.9, DECK_HALF * 2, 3.2), BODY)
	model.PrimaryPart = deck

	local layout = {
		-- the column, raked back a touch so it reads as a scooter rather than a post
		{ "Stem",      Vector3.new(0.2, 2.35, 0.2),   BODY,   CFrame.new(0, 1.16, -1.36) * CFrame.Angles(math.rad(-8), 0, 0) },
		{ "Handlebar", Vector3.new(1.6, 0.16, 0.16),  BODY,   CFrame.new(0, 2.28, -1.52) },
		{ "GripL",     Vector3.new(0.36, 0.22, 0.22), RUBBER, CFrame.new(-0.68, 2.28, -1.52) },
		{ "GripR",     Vector3.new(0.36, 0.22, 0.22), RUBBER, CFrame.new(0.68, 2.28, -1.52) },
		-- grip pad the rider actually stands on, proud of the deck
		{ "GripPad",   Vector3.new(0.78, 0.06, 2.5),  RUBBER, CFrame.new(0, DECK_HALF, 0.1) },
		{ "Headlight", Vector3.new(0.26, 0.26, 0.12), TRIM,   CFrame.new(0, 2.0, -1.62), Enum.Material.Neon },
		-- the spine light, so the deck reads as powered from above as well as below
		{ "Spine",     Vector3.new(0.12, 0.05, 2.2),  TRIM,   CFrame.new(0, DECK_HALF + 0.05, 0.1), Enum.Material.Neon },
	}
	for _, row in ipairs(layout) do
		local p = piece(model, row[1], row[2], row[3], row[5])
		p.CFrame = row[4]
	end

	-- HOVER PADS where the wheels were. Bottom lands DECK_HALF + PAD_DROP + PAD_HALF =
	-- 0.30 below the deck centre, against a LIFT of 0.7 -- so roughly a third of a stud
	-- of daylight stays under the scooter at rest, which is the gap the bob plays in.
	for _, spec in ipairs({ { "PadFront", -1.15 }, { "PadRear", 1.15 } }) do
		local pad = piece(model, spec[1], Vector3.new(0.62, PAD_HALF * 2, 0.9), TRIM, Enum.Material.Neon)
		pad.CFrame = CFrame.new(0, -PAD_DROP, spec[2])
	end

	for _, name in ipairs({ "PadFront", "PadRear" }) do
		local glow = Instance.new("PointLight")
		glow.Color = TRIM
		glow.Brightness = 1.8
		glow.Range = 9
		glow.Parent = model:FindFirstChild(name)
	end

	-- Weld every part to the deck AFTER all the CFrames are final: a WeldConstraint
	-- freezes the offset it sees at the moment it is enabled.
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p ~= deck then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = deck
			weld.Part1 = p
			weld.Parent = deck
		end
	end

	return model, deck
end

--[[ WHERE THE FLOOR IS, RELATIVE TO THE ROOT. Two wrong answers were tried first, and
both are instructive:

  LOWEST PART IN THE CHARACTER -- an ACCESSORY wins the moment one hangs low. Measured
  on a rig with a winged back accessory: its Handle sat 3.07 studs under the root
  against 2.39 for the lowest foot, so the deck was welded 0.68 too deep and the hover
  pads spent the ride 0.38 BELOW the ground. That is the "forcing me into the ground"
  report.

  LOWEST FOOT PART -- no accessories, but the feet MOVE. Whatever the legs happen to be
  doing at the instant of mounting gets baked into the weld for the whole ride: measured
  0.60 of drift between mounting mid-stride and mounting at rest, and mounting in mid-air
  with the legs dangling is worse again.

So: the Humanoid's OWN floor plane. rootBottom - HipHeight is where this character
stands, by definition, and it does not move when the legs do. With the deck top pinned
there, the rider ends up standing exactly LIFT above it -- board underneath, daylight
under the board.

R6 is the exception that needs the feet: those rigs report HipHeight 0, which would put
the deck through the character's waist.
]]
local FOOT_PARTS = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }

local function footDrop(char, hrp, stockHip)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hip = stockHip or (hum and hum.HipHeight) or 0
	if hip > 0.1 then
		return hrp.Size.Y * 0.5 + hip
	end
	local lowest = nil
	for _, name in ipairs(FOOT_PARTS) do
		local p = char:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			local bottom = p.Position.Y - p.Size.Y * 0.5
			lowest = lowest and math.min(lowest, bottom) or bottom
		end
	end
	if not lowest then return 3 end
	return math.clamp(hrp.Position.Y - lowest, 1, 6)
end

-- The rig's HipHeight BEFORE anyone rode anything. Read at mount time it would already
-- carry ClientMain's lift on a re-equip, and the deck would sink by LIFT every time.
-- Weak keys so a leaver's entry goes with them.
local stockHip = setmetatable({}, { __mode = "k" })

local function detach(player)
	local char = player.Character
	if char then
		local old = char:FindFirstChild("ElectricScooter")
		if old then old:Destroy() end
	end
	player:SetAttribute(RIDING_ATTR, false)
end

local function attach(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	detach(player)   -- never two scooters, whatever order equip/respawn arrived in

	local model, deck = buildScooter()
	-- Move the assembled model as one, so every welded offset above survives. Deck TOP
	-- flush with the rider's foot plane -- they stand ON it rather than in it. The lift
	-- ClientMain adds to HipHeight is what leaves room underneath; this offset is
	-- measured from the ROOT, so it holds whether the lift has landed yet or not and
	-- the two cannot race.
	model:PivotTo(hrp.CFrame * CFrame.new(0, -footDrop(char, hrp) - DECK_HALF, 0))
	model.Parent = char

	-- A REAL Weld, not a WeldConstraint: ClientMain animates C0 every frame to hover,
	-- bank and pitch the board, and a WeldConstraint has no offset to animate. C1 stays
	-- identity, so the deck simply renders at hrp.CFrame * C0.
	--
	-- The base is published as an attribute rather than left for the client to infer
	-- from the first C0 it happens to read -- by then it may already be a frame of its
	-- own animation, and the scooter would drift a little further out every mount.
	local base = CFrame.new(0, -footDrop(char, hrp, stockHip[player]) - DECK_HALF, 0)
	local ride = Instance.new("Weld")
	ride.Name = "RideWeld"
	ride.Part0 = hrp
	ride.Part1 = deck
	ride.C0 = base
	ride:SetAttribute("BaseC0", base)
	ride.Parent = deck

	player:SetAttribute(RIDING_ATTR, true)
end

local function makeTool()
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	-- BEFORE parenting: GearBlocker checks this the frame a Tool appears, and a
	-- scooter without it would be destroyed as imported Roblox gear.
	tool:SetAttribute("GameItem", true)
	tool.RequiresHandle = false   -- the scooter is welded under the rider, not held
	tool.CanBeDropped = false
	tool.ToolTip = "Ride the VIP electric scooter"
	return tool
end

local function hasScooterPass(player)
	local ok, has = pcall(GamepassService.HasFlag, player, FLAG)
	return ok and has == true
end

local function wire(player, tool)
	tool.Equipped:Connect(function() attach(player) end)
	tool.Unequipped:Connect(function() detach(player) end)
end

-- Idempotent: safe to call on join, on respawn, and again the moment the pass is
-- bought, without ever handing out a second one.
local function ensureTool(player)
	if not hasScooterPass(player) then return end
	local char = player.Character
	if char and char:FindFirstChild(TOOL_NAME) then return end   -- equipped right now
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or backpack:FindFirstChild(TOOL_NAME) then return end
	local tool = makeTool()
	wire(player, tool)
	tool.Parent = backpack
end

function ScooterService.Init()
	local function onCharacter(player)
		-- The character is new, so any scooter welded to the old one is gone with it;
		-- clear the flag or the client keeps riding a prop that no longer exists.
		player:SetAttribute(RIDING_ATTR, false)
		stockHip[player] = nil
		task.spawn(function()
			local char = player.Character
			local hum = char and char:WaitForChild("Humanoid", 10)
			-- captured before any ride can have touched it; see stockHip above
			if hum then stockHip[player] = hum.HipHeight end
		end)
		task.defer(function()
			if player.Parent then ensureTool(player) end
		end)
	end

	local function onPlayer(player)
		player:SetAttribute(RIDING_ATTR, false)
		player.CharacterAdded:Connect(function() onCharacter(player) end)
		if player.Character then onCharacter(player) end
		-- GamepassService refreshes ownership asynchronously on join, so the first
		-- ensureTool above can legitimately answer "no pass". One retry after that
		-- settles, matching the 2s ShopService already waits before its first push.
		task.delay(3, function()
			if player.Parent then ensureTool(player) end
		end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end

	-- THE PASS CACHE FILLS ASYNCHRONOUSLY, and the fixed 3s retry above was racing
	-- it. GamepassService.refresh makes ONE BLOCKING WEB CALL PER PASS -- eleven of
	-- them are configured -- so filling the cache routinely outlasts three seconds.
	-- A VIP who lost that race got NO SCOOTER AT ALL until they happened to respawn:
	-- observed 2026-08-22 on the owner's own account, where GamepassService.Owns
	-- ("VIP") and HasFlag("Scooter") both read true while the Backpack held nothing.
	--
	-- OnRefreshed is the hook GamepassService publishes for exactly this problem
	-- (see its own note about ShopService drawing a BUY button for a pass the player
	-- already owned), and ShopService and PetHandler both already use it. ensureTool
	-- is idempotent, so this and the retry above cannot hand out two scooters.
	GamepassService.OnRefreshed(function(player)
		if player.Parent then ensureTool(player) end
	end)

	-- Bought mid-session: hand it over now rather than at the next rejoin.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _, wasPurchased)
		if not wasPurchased then return end
		task.defer(function()   -- after GamepassService's own cache update
			if player.Parent then ensureTool(player) end
		end)
	end)

	print("ScooterService online (VIP electric scooter, granted by the Scooter pass flag)")
end

return ScooterService
