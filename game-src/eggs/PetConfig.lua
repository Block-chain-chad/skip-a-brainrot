-- PetConfig (Forest Egg Shop, Task 11) -- pet boosts, slots, gamepass.
--
-- ENABLED=false hides ALL pet UI and purchases. Flip only when the user's pet chart lands.
--
-- Every consumer (PetHandler.LuckMult/IncomeMult) reads ENABLED and returns a neutral 1x
-- instantly when it is false, so the ThrowHandler/IncomeLoop seams are safe to leave wired
-- live: there is no way for a disabled pet system to move a number until this flips.

local PetConfig = {}

PetConfig.ENABLED = false

-- Follow-slot caps. SLOTS_PREMIUM only applies once PET_SLOTS_GAMEPASS_ID is owned;
-- id == 0 means "no gamepass configured yet" -- the premium path stays inert (see
-- PetHandler) rather than ever calling UserOwnsGamePassAsync with a bogus id.
PetConfig.SLOTS_FREE = 3
PetConfig.SLOTS_PREMIUM = 6
PetConfig.PET_SLOTS_GAMEPASS_ID = 0

-- [petId] = { Name, Boost = { Type, Amount } }. TestAcorn is a TEST-ONLY placeholder for
-- the Step 5 probes and PetHandler.Grant plumbing -- it is never surfaced in any shop UI
-- (there is no shop UI yet; ENABLED=false hides the whole feature regardless).
PetConfig.Pets = {
	TestAcorn = {
		Name = "Test Acorn",
		Boost = { Type = "Luck", Amount = 0.10 },
	},
}

return PetConfig
