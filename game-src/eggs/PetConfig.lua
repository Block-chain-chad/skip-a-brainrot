-- PetConfig (Forest Egg Shop, Task 11) -- pet boosts, slots, gamepass.
--
-- ENABLED=false hides ALL pet UI and purchases. Flip only when the user's pet chart lands.
--
-- Every consumer (PetHandler.LuckMult/IncomeMult) reads ENABLED and returns a neutral 1x
-- instantly when it is false, so the ThrowHandler/IncomeLoop seams are safe to leave wired
-- live: there is no way for a disabled pet system to move a number until this flips.

local PetConfig = {}

PetConfig.ENABLED = false
-- flipped back OFF 2026-07-31 per user decision (was toggled on by an unknown editor)

-- Follow-slot caps. SLOTS_PREMIUM only applies once PET_SLOTS_GAMEPASS_ID is owned;
-- id == 0 means "no gamepass configured yet" -- the premium path stays inert (see
-- PetHandler) rather than ever calling UserOwnsGamePassAsync with a bogus id.
PetConfig.SLOTS_FREE = 3
PetConfig.SLOTS_PREMIUM = 6
PetConfig.PET_SLOTS_GAMEPASS_ID = 0

-- === Rarity ladder ============================================================
-- MULTIPLIERS, not bonuses: Luck = 5 means 5x. PetHandler converts these into the
-- additive amounts its boost sum works in, so the numbers here read the way the design
-- was specified rather than the way the maths happens to be stored.
--
-- Secret is pinned at the requested 5x luck / 10x money and every tier below is scaled
-- to land under it. Only these four tiers appear in EggConfig's forest tables (Epic x3,
-- Legendary x3, Mythic x3, Secret x1), so the ladder covers exactly what is obtainable.
-- Pets are equal within a tier on purpose: the three Mythics differ in CashPerSecond as
-- brainrots, but as pets their rarity is what you paid for, so making them differ would
-- just create a right answer and two traps.
PetConfig.RARITY_BOOSTS = {
	Epic      = { Luck = 1.50, Income = 2.00 },
	Legendary = { Luck = 2.25, Income = 3.50 },
	Mythic    = { Luck = 3.25, Income = 6.00 },
	Secret    = { Luck = 5.00, Income = 10.00 },
}

-- Display order + colours for the bag's Pets tab, rarest first.
PetConfig.RARITY_ORDER = { "Secret", "Mythic", "Legendary", "Epic" }
PetConfig.RARITY_COLOUR = {
	Secret    = Color3.fromRGB(255, 86, 86),
	Mythic    = Color3.fromRGB(198, 142, 255),
	Legendary = Color3.fromRGB(255, 196, 62),
	Epic      = Color3.fromRGB(126, 170, 255),
}

-- [petId] = { Name, Rarity, Model }. petId is the creature's name with spaces stripped,
-- so a pet record's Id stays stable and readable in a save file.
--
-- NEVER DELETE AN ENTRY. Owned pet records store only Uid + Id; boosts are looked up
-- from here at read time (see PetHandler.boostFor) precisely so a rebalance reaches pets
-- players already own -- but that also means a removed Id turns an owned pet into a
-- boost-less orphan. Retire by dropping it from EggConfig's roll tables instead.
local function pets(rarity, names)
	local t = {}
	for _, n in ipairs(names) do
		t[(n:gsub("%s+", ""))] = { Name = n, Rarity = rarity }
	end
	return t
end

PetConfig.Pets = {
	-- TEST-ONLY placeholder, kept so the command-bar probes in PetHandler's header still
	-- work. Not in any egg table, so it is unobtainable in normal play.
	TestAcorn = { Name = "Test Acorn", Rarity = "Epic" },
}
for rarity, names in pairs({
	Epic      = { "Cervolino Antlerino", "Fanghetto Palunko", "Strigolino Hootini" },
	Legendary = { "Rospino Bavaglio", "Corvacchio Beccarino", "Ceppone Zampalunga" },
	Mythic    = { "Alcione Trombettone", "Lucciolone Pantanini", "Gufocervo Stiltini" },
	Secret    = { "Muschione Cornaluna" },
}) do
	for id, def in pairs(pets(rarity, names)) do
		PetConfig.Pets[id] = def
	end
end

-- Id for a creature name, so EggHandler never has to duplicate the strip-spaces rule.
function PetConfig.IdFor(creatureName)
	if typeof(creatureName) ~= "string" then return nil end
	local id = (creatureName:gsub("%s+", ""))
	return PetConfig.Pets[id] and id or nil
end

-- Multipliers for a petId, or a neutral 1x pair if the id is unknown. Callers on the hot
-- throw/income paths must never be able to turn a lookup miss into a 0.
function PetConfig.BoostsFor(petId)
	local def = PetConfig.Pets[petId]
	local b = def and PetConfig.RARITY_BOOSTS[def.Rarity]
	if not b then return 1, 1 end
	return b.Luck or 1, b.Income or 1
end

-- === Follow behaviour =========================================================
-- Read by PetHandler's rig. The bob is what makes an equipped pet read as "happy"
-- rather than as a part being dragged along behind the player.
PetConfig.BOB_HEIGHT = 0.45      -- studs, peak-to-peak above/below the slot height
PetConfig.BOB_PERIOD = 1.6       -- seconds per full up-down cycle
PetConfig.BOB_PHASE_STEP = 0.7   -- radians between slots, so pets don't bob in lockstep
PetConfig.SPIN_PERIOD = 6.0      -- slow idle yaw, seconds per turn

return PetConfig
