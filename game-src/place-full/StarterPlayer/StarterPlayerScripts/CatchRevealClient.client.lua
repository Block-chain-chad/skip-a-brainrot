-- CatchRevealClient: turns a catch into a reveal.
--
-- Deliberately thin. All the presentation lives in CatchReveal (the screen-space card)
-- and CatchFX (the burst around the player); this only decides WHETHER to show one,
-- which is exactly the decision the phase-2 Robux upgrade needs to change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CatchReveal = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CatchReveal"))
local PullCeremony = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PullCeremony"))
local BrainrotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BrainrotConfig"))
-- within-tier odds for the ceremony: weights sum to 100,000 per tier, so
-- "1 in N of its tier" with N = 100000/Weight is HONEST, not theater
local weightByName, voiceByName = {}, {}
for _, e in ipairs(BrainrotConfig) do
	weightByName[e.Name] = e.Weight
	-- optional per-creature voice line; nil for every entry today
	if type(e.VoiceId) == "string" and e.VoiceId ~= "" then voiceByName[e.Name] = e.VoiceId end
end
local CatchFX = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CatchFX"))
local SoundKit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundKit"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local throwResult = remotes:WaitForChild("ThrowResult")

-- REMOVED: the Legendary "ping". It was a raw Sound instance created here with a
-- hardcoded asset id, played through SoundService:PlayLocalSound at volume 0.65 --
-- outside SoundKit entirely, and roughly double the level of the tuned catch ladder
-- (0.13 to 0.54), which is why it stuck out. Legendary now gets its rung of that
-- ladder like every other tier.

-- The catcher's own cue, per tier. Mirrors the ladder in RareCatchClient because
-- these are the tiers that ladder never reaches: RareCatch is only broadcast for
-- Secret / God / Rainbow / Glitched (see ThrowHandler.revealCatch, ~line 890), so
-- Common through Mythic previously landed in total silence for the catcher.
local TIER_SFX = {
	Common    = { { sound = "catchCommon",   volume = 0.13 } },
	Uncommon  = { { sound = "catchUncommon", volume = 0.17 } },
	Rare      = { { sound = "catchRare",     volume = 0.21 } },
	Epic      = { { sound = "catchEpic",     volume = 0.25 } },
	Legendary = { { sound = "catchLegend",   volume = 0.30 },
	              { sound = "catchSparkle",  volume = 0.14, delay = 0.07 } },
	Mythic    = { { sound = "catchMythic",   volume = 0.34 },
	              { sound = "catchSparkle",  volume = 0.18, delay = 0.06 } },
}

-- IN SYNC WITH THE SERVER. ThrowHandler broadcasts RareCatch for exactly these, and
-- RareCatchClient plays the ladder for them at full level. Playing here as well would
-- stack two copies of the same sting on the biggest catches in the game.
local function isBroadcast(result)
	return result.Rarity == "Secret" or result.Rarity == "God"
		or result.Mutation == "Rainbow" or result.Mutation == "Glitched"
end

local function playTierCue(result)
	local layers = TIER_SFX[result.Rarity]
	if not layers then return end
	for _, layer in ipairs(layers) do
		if (layer.delay or 0) <= 0 then
			SoundKit.play(layer.sound, nil, { volume = layer.volume })
		else
			task.delay(layer.delay, function()
				SoundKit.play(layer.sound, nil, { volume = layer.volume })
			end)
		end
	end
end

-- PHASE 2 SEAM: the purchasable "skip the animation" upgrade replaces this body
-- with a gamepass-ownership check plus the player's chosen rarities.
--
-- Skipping an ANIMATION is a pure presentation choice, so the client may own it
-- -- a client that lies about it gains nothing. The auto-sell half of that
-- upgrade is NOT the same and must never live here: a client that can say "sell
-- this catch" can say it about anything. Auto-sell belongs server-side in
-- ThrowHandler.revealCatch behind a verified MarketplaceService check.
local function shouldReveal(_result)
	return true
end

throwResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" or type(result.BrainrotName) ~= "string" then return end

	-- Burst first: it reads as the catch LANDING, so it should not wait on the card.
	-- pcall for the same reason as the reveal -- an effect must never break a catch.
	pcall(CatchFX.play, {
		Rarity = result.Rarity,
		Color = result.RarityColor,
		Mutation = result.Mutation,
	})

	-- Recorded so PullCeremony does not play the SAME tier cue a second time.
	-- TIER_SFX has no Secret/God rungs, and broadcasts are skipped anyway, so on
	-- those tiers this stays false and the ceremony carries the lead itself.
	local tierCuePlayed = false
	if not isBroadcast(result) then
		pcall(playTierCue, result)
		tierCuePlayed = TIER_SFX[result.Rarity] ~= nil
	end

	if not shouldReveal(result) then return end

	-- pcall: a broken reveal must never break the catch that produced it.
	local weight = weightByName[result.BrainrotName]
	local payload = {
		Name = result.BrainrotName,
		Rarity = result.Rarity,
		RarityColor = result.RarityColor,
		Mutation = result.Mutation,
		Serial = result.Serial,
		Exists = result.Exists,
		OddsN = weight and math.max(2, math.floor(100000 / weight + 0.5)) or nil,
		TierCuePlayed = tierCuePlayed,
		VoiceId = voiceByName[result.BrainrotName],   -- nil unless authored
	}
	-- Epic+ gets the full Pull ceremony (takeover / odds climb / burst / stamp);
	-- lower tiers keep the fast reveal untouched -- respect the grind.
	pcall(PullCeremony.play, payload)
end)
