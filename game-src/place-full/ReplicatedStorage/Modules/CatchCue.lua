-- CatchCue: the catcher's OWN feedback on landing a brainrot -- the burst around the
-- player and the per-tier sting -- shared by every faucet that can land one.
--
-- Extracted from CatchRevealClient (2026-08-23), unchanged, when ICE FISHING became the
-- second such faucet. A caught fish is a brainrot exactly like a thrown one (see
-- IceFishingEvent's grant, which already mirrors ThrowHandler.revealCatch), so it has to
-- sound and look like one -- and the way to guarantee that is one table, not a copy in
-- each client. A hand-copied ladder drifts the first time a volume is tuned, which is the
-- same reason PlayerDataManager.Snapshot ships SPOT_PRICES instead of letting the client
-- keep its own.
--
-- This is the part BELOW the reveal gate: it plays for every catch, including ones whose
-- ceremony the player has switched off in Settings. The takeover itself (PullCeremony)
-- and the size cutscene (MassiveEmergence) stay with their callers, because who is
-- allowed to skip them differs per faucet.
--
-- ONE FAMILY (2026-09-21 audio pass). The eight core samples are the owner's ear-picked
-- ladder (SoundKit.Ids, pass 4) and stay put -- picking sounds by reasoning has failed
-- twice in this file's history. What makes the rungs READ as one family now is a shared
-- spine layered under them in one consistent recipe: the same shimmer (`catchSparkle`)
-- joins at Rare and grows with every rung, and the same impact (`catchBigHit`) joins at
-- Legendary and grows to God. Every layer wears a small random pitch variation so the
-- same tier twice in a row never sounds copy-pasted. RareCatchClient's broadcast ladder
-- and CatchPop both read THIS table -- there is no second copy anywhere.
--
-- Still wanted from the owner (see the final report): a purpose-made eight-sting set on
-- one synth patch would make the family a family rather than a family resemblance.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CatchFX  = require(ReplicatedStorage.Modules.CatchFX)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)

local CatchCue = {}

-- The catcher's own cue, per tier. Each rung is a LIST OF LAYERS: { sound, volume,
-- delay?, pitchVar? }. Volume is the level for the catcher's OWN catch; callers pass a
-- scale (RareCatchClient plays somebody else's find at 0.30).
--
-- Rarity reads as rarer three ways at once: the core samples get longer, the level
-- climbs, and the spine layers stack -- length and volume alone run out of headroom
-- by Secret, so density carries the last stretch. A God is an impact, then the choir
-- over it, then a shimmer on top: three events in a third of a second that read as one.
CatchCue.TIER_SFX = {
	Common    = { { sound = "catchCommon",   volume = 0.14, pitchVar = 0.05 } },
	Uncommon  = { { sound = "catchUncommon", volume = 0.17, pitchVar = 0.05 } },
	Rare      = { { sound = "catchRare",     volume = 0.21 },
	              { sound = "catchSparkle",  volume = 0.07, delay = 0.05 } },
	Epic      = { { sound = "catchEpic",     volume = 0.25 },
	              { sound = "catchSparkle",  volume = 0.11, delay = 0.06 } },
	Legendary = { { sound = "catchBigHit",   volume = 0.12 },
	              { sound = "catchLegend",   volume = 0.30, delay = 0.02 },
	              { sound = "catchSparkle",  volume = 0.15, delay = 0.08 } },
	Mythic    = { { sound = "catchBigHit",   volume = 0.22 },
	              { sound = "catchMythic",   volume = 0.34, delay = 0.02 },
	              { sound = "catchSparkle",  volume = 0.18, delay = 0.07 } },
	-- The top two are normally voiced by their cuts (Secret's signature at the launch,
	-- God's choir); these rows serve the broadcast banner for OTHER players' finds and
	-- the reveal-skipped path.
	Secret    = { { sound = "catchBigHit",   volume = 0.30 },
	              { sound = "catchSecret",   volume = 0.40, delay = 0.03 },
	              { sound = "catchSparkle",  volume = 0.20, delay = 0.10 } },
	God       = { { sound = "catchBigHit",   volume = 0.44 },
	              { sound = "catchGod",      volume = 0.54, delay = 0.10 },
	              { sound = "catchDrama",    volume = 0.30, delay = 0.10 },
	              { sound = "catchSparkle",  volume = 0.30, delay = 0.34 } },
}
CatchCue.TIER_FALLBACK = { { sound = "catchRare", volume = 0.21 } }
CatchCue.DEFAULT_PITCH_VAR = 0.03

-- IN SYNC WITH THE SERVER. Both faucets broadcast RareCatch for exactly these, and
-- RareCatchClient plays the ladder for them at full level. Playing here as well would
-- stack two copies of the same sting on the biggest catches in the game.
function CatchCue.IsBroadcast(rarity, mutation)
	return rarity == "Secret" or rarity == "God"
		or mutation == "Rainbow" or mutation == "Glitched"
end

-- scale: 1 for your own catch, lower for somebody else's. Returns true if a row played.
function CatchCue.PlayTier(rarity, scale)
	local layers = CatchCue.TIER_SFX[rarity]
	if not layers then return false end
	local k = (type(scale) == "number") and scale or 1
	for _, layer in ipairs(layers) do
		local var = layer.pitchVar or CatchCue.DEFAULT_PITCH_VAR
		local speed = 1 + (math.random() - 0.5) * 2 * var
		local function fire()
			SoundKit.play(layer.sound, nil, { volume = layer.volume * k, speed = speed })
		end
		if (layer.delay or 0) <= 0 then
			fire()
		else
			task.delay(layer.delay, fire)
		end
	end
	return true
end

-- Burst first -- it reads as the catch LANDING, so it should not wait on any card.
-- Returns whether a tier cue was played, which the ceremony needs so it does not play
-- the same sting a second time.
function CatchCue.Play(info)
	pcall(CatchFX.play, {
		Rarity = info.Rarity,
		Color = info.Color,
		Mutation = info.Mutation,
	})
	if CatchCue.IsBroadcast(info.Rarity, info.Mutation) then return false end
	local ok, played = pcall(CatchCue.PlayTier, info.Rarity, 1)
	return ok and played == true
end

return CatchCue
