-- RebirthConfig: prestige curves shared by RebirthHandler, IncomeLoop, ThrowHandler.
local RebirthConfig = {}

-- ===================== ROCKS SURVIVE, CASH IS THE PRICE (2026-09-03) =====================
-- History: 1M x 1.8^n (rebirth was seconds of income), then 100M x 2^n with a ROCK WIPE
-- sized against a ~725M ladder. The ladder then grew to ~20B in the valley (Singularity
-- alone 7.38B) and 10B-950B in the tundra, while the price stayed at 100M -- so rebirth
-- became a trap: weeks of rock purchases gone for +15% income, which Golden Touch sells
-- for 1.1B with no loss. Nobody past Cometfall should have pressed it, and nobody before
-- it felt the sacrifice.
--
-- Now: rocks are KEPT (RebirthHandler no longer touches OwnedRocks/EquippedRock) and the
-- cash price carries the whole sacrifice: 1B x 2^n. That is ~10 hours of a Legendary camp
-- for the first one, ~2 hours of a Mythic camp, and it scales with the rock ladder instead
-- of sitting under it. Growth stays 2.0 rather than steeper because MaxwellQuest asks for
-- Rebirth 15: at 2.0 that is 16.4T for the last step (~a week of a mutated tundra camp);
-- at 2.5 it would be 373T, a decade.
--
-- Payout unchanged: +15% income, +7% luck (mutation odds only, never tier access), +7%
-- power per rebirth, permanent. Brainrots and their placements survive as before.

-- cash needed to perform the NEXT rebirth, given the current rebirth count
function RebirthConfig.Cost(rebirths)
	return math.floor(1000000000 * (2.0 ^ (rebirths or 0)))
end

-- permanent money multiplier (+15% per rebirth)
function RebirthConfig.IncomeMult(rebirths)
	return 1 + 0.15 * (rebirths or 0)
end

-- permanent luck multiplier -- feeds the mutation-odds boost, NOT tier access
-- (ThrowHandler deliberately excludes rebirth luck from tier access) (+7% per rebirth)
function RebirthConfig.LuckMult(rebirths)
	return 1 + 0.07 * (rebirths or 0)
end

-- permanent throw power -- scales how far a skip goes (+7% per rebirth)
function RebirthConfig.PowerMult(rebirths)
	return 1 + 0.07 * (rebirths or 0)
end

return RebirthConfig
