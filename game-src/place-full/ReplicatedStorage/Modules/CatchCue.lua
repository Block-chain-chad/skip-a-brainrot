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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CatchFX  = require(ReplicatedStorage.Modules.CatchFX)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)

local CatchCue = {}

-- The catcher's own cue, per tier. Mirrors the ladder in RareCatchClient because these
-- are the tiers that ladder never reaches: RareCatch is only broadcast for Secret / God /
-- Rainbow / Glitched, so Common through Mythic would otherwise land in total silence for
-- the catcher.
CatchCue.TIER_SFX = {
	Common    = { { sound = "catchCommon",   volume = 0.13 } },
	Uncommon  = { { sound = "catchUncommon", volume = 0.17 } },
	Rare      = { { sound = "catchRare",     volume = 0.21 } },
	Epic      = { { sound = "catchEpic",     volume = 0.25 } },
	Legendary = { { sound = "catchLegend",   volume = 0.30 },
	              { sound = "catchSparkle",  volume = 0.14, delay = 0.07 } },
	Mythic    = { { sound = "catchMythic",   volume = 0.34 },
	              { sound = "catchSparkle",  volume = 0.18, delay = 0.06 } },
}

-- IN SYNC WITH THE SERVER. Both faucets broadcast RareCatch for exactly these, and
-- RareCatchClient plays the ladder for them at full level. Playing here as well would
-- stack two copies of the same sting on the biggest catches in the game.
function CatchCue.IsBroadcast(rarity, mutation)
	return rarity == "Secret" or rarity == "God"
		or mutation == "Rainbow" or mutation == "Glitched"
end

function CatchCue.PlayTier(rarity)
	local layers = CatchCue.TIER_SFX[rarity]
	if not layers then return false end
	for _, layer in ipairs(layers) do
		if (layer.delay or 0) <= 0 then
			SoundKit.play(layer.sound, nil, { volume = layer.volume })
		else
			task.delay(layer.delay, function()
				SoundKit.play(layer.sound, nil, { volume = layer.volume })
			end)
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
	local ok, played = pcall(CatchCue.PlayTier, info.Rarity)
	return ok and played == true
end

return CatchCue
