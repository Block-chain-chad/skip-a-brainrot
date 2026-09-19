-- NpcLodProfiles -- distance bands per tier (Phase 2.5 doc F2) and the global
-- animated-set cap. Read by NpcLife every ranking pass.
--
-- Bands are checked in order; the first whose maxDist >= distance wins.
-- procEvery = evaluate the procedural pose every Nth frame (1 = every frame).
-- Beyond the last band, or off-screen, a body holds its last pose and nothing
-- is written -- that is the "stop" state, not a snap to rest.

local NpcLodProfiles = {}
NpcLodProfiles.Version = 1

NpcLodProfiles.Global = {
	maxAnimated = 12,      -- nearest N bodies evaluate per frame; the rest hold
	rankEvery = 10,        -- frames between distance rankings
	offscreenDot = -0.2,   -- behind the camera below this dot product
	offscreenHold = 0.5,   -- seconds of hysteresis before a body counts as off-screen
	worldRadius = 2000,    -- bodies further than this from the camera are not even ranked (other worlds)
}

NpcLodProfiles.Tiers = {
	[1] = {
		bands = {
			{ maxDist = 30, procEvery = 1, gestures = true,  face = true,  lights = true },
			{ maxDist = 60, procEvery = 2, gestures = false, face = false, lights = true },
			{ maxDist = 90, procEvery = 4, gestures = false, face = false, lights = false },
		},
		faceRange = 20, gestureRange = 30, talkRange = 0, trackRange = 0,
	},
	[2] = {
		bands = {
			{ maxDist = 40,  procEvery = 1, gestures = true,  face = true,  lights = true },
			{ maxDist = 90,  procEvery = 2, gestures = true,  face = false, lights = true },
			{ maxDist = 140, procEvery = 4, gestures = false, face = false, lights = false },
		},
		faceRange = 40, gestureRange = 90, talkRange = 24, trackRange = 24,
	},
	[3] = {
		bands = {
			{ maxDist = 50,  procEvery = 1, gestures = true,  face = true,  lights = true },
			{ maxDist = 100, procEvery = 2, gestures = true,  face = false, lights = true },
			{ maxDist = 160, procEvery = 4, gestures = false, face = false, lights = false },
		},
		faceRange = 50, gestureRange = 100, talkRange = 24, trackRange = 24,
	},
}

-- Prompt defaults for NEW NPC-01 characters (decision D-8). Existing prompts
-- are never touched by the kit.
NpcLodProfiles.PromptDefaults = { MaxActivationDistance = 10, HoldDuration = 0.3, RequiresLineOfSight = false }

function NpcLodProfiles.Get(tier)
	return NpcLodProfiles.Tiers[tier] or NpcLodProfiles.Tiers[2]
end

-- BandFor(profile, dist) -> band table or nil (nil = beyond range: hold)
function NpcLodProfiles.BandFor(profile, dist)
	for _, b in ipairs(profile.bands) do
		if dist <= b.maxDist then return b end
	end
	return nil
end

return NpcLodProfiles
