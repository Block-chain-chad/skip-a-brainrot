-- RebirthConfig: prestige curves shared by RebirthHandler, IncomeLoop, ThrowHandler.
local RebirthConfig = {}

-- ===================== RETUNED ALONGSIDE THE ROCK LADDER =====================
-- The old cost was 1,000,000 x 1.8^n. Against 12 pads of Mythic brainrots that first
-- rebirth was EIGHT AND A HALF SECONDS of income, and the 1.8 growth never caught up
-- with a ~5.8x-per-tier income curve, so rebirth stopped being a decision.
--
-- The other half of this is RebirthHandler: rebirth wipes OwnedRocks back to Pebble.
-- That used to cost ~2.6M to rebuild; with the reworked RockConfig the full ladder is
-- ~725M, so the rock wipe is now the dominant sacrifice and the cash price has to sit
-- in the same order of magnitude or the gate is meaningless.
--
-- Payout was raised with it. At +10% per rebirth, giving up ~725M of rocks bought so
-- little that rebirthing was close to a trap; +15% keeps the loop worth entering. The
-- old comment claimed "the value is in rebirthing often" -- that is no longer the
-- shape of it. Rebirth is now an occasional milestone that replays the rock ladder,
-- which is exactly what makes the longer ladder worth having built.
--
-- Brainrots and their placements still survive, so income does NOT collapse on
-- rebirth: placed brainrots keep producing at their tier. What you lose is your cash
-- and your ability to CATCH high tiers until the rocks are rebought.

-- cash needed to perform the NEXT rebirth, given the current rebirth count
function RebirthConfig.Cost(rebirths)
	return math.floor(100000000 * (2.0 ^ (rebirths or 0)))
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
