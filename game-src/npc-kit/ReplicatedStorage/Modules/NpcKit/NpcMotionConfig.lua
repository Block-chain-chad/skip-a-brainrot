-- NpcMotionConfig -- the animation PACKS as data (Phase 2.5 doc C).
--
-- Everything is authored in SEMANTIC axes (degrees / studs):
--   limbs: swing (+forward), spread (+away from body), twist (+outward)
--   spine: bend (+forward/nod), turn (+right), tilt (+toward the right shoulder)
--   any:   x y z (studs)
-- NpcMotion maps them to CFrames per joint side, so nobody here thinks about
-- signs. Nothing exceeds 40 deg on a limb except a character's one signature.
--
-- A LAYER computes one scalar over time (kind + period + amp + phase) and
-- applies it to several joints through `effects` (scale per effect). A
-- GESTURE is a keyframe list. Packs are resolved per character with dot-path
-- overrides (Resolve below), e.g. ["idle.breathe.period"] = 2.9.
--
-- USE_TRACKS: the hook for uploaded / in-place authored clips. Any layer or
-- gesture may carry `asset` or `sequence`; with USE_TRACKS true those play as
-- AnimationTracks (Transform) while the rest keep evaluating procedurally
-- (C0). False for the prototypes; flipping it is the whole migration.

local NpcMotionConfig = {}
NpcMotionConfig.Version = 1
NpcMotionConfig.USE_TRACKS = false

-- Amplitude ceilings the lint enforces on every pack (degrees).
NpcMotionConfig.Limits = { spineIdle = 4, limbIdleContinuous = 3, spineGesture = 40, shoulder = 60, elbow = 110, wrist = 30, leg = 20, signature = 90 }

local function E(joint, axis, scale, flags)
	local e = { joint = joint, axis = axis, scale = scale or 1 }
	if flags then for k, v in pairs(flags) do e[k] = v end end
	return e
end

-- ===== shared idle layers ===================================================
local function breathe(period, amp)
	return { kind = "sine", period = period, amp = amp, effects = {
		E("Waist", "bend", 1), E("Neck", "bend", -0.33), E("RightShoulder", "spread", 0.27), E("LeftShoulder", "spread", 0.27) } }
end
local function weightShift(period, amp)
	return { kind = "sine", period = period, amp = amp, plantedCounter = true, effects = {
		E("Root", "tilt", 1), E("LeftHip", "tilt", -1), E("RightHip", "tilt", -1) } }
end
local function weightDip(period)
	return { kind = "sineAbs", period = period / 2, amp = -0.03, effects = { E("Root", "y", 1) } }
end
local function look(period, amp)
	return { kind = "snap", period = period, amp = amp, ease = 0.18, priority = 1, effects = { E("Neck", "turn", 1), E("Waist", "turn", 0.3) } }
end
local function lookTilt(period)
	return { kind = "snap", period = period * 1.3, amp = 3, ease = 0.25, priority = 1, effects = { E("Neck", "tilt", 1) } }
end
local function handSway()
	return { kind = "sine", period = 4.1, amp = 3, effects = {
		E("LeftWrist", "swing", 1), E("LeftElbow", "swing", 0.66),
		E("RightWrist", "swing", 1, { unlessPlanted = "RightHand" }), E("RightElbow", "swing", 0.66, { unlessPlanted = "RightHand" }) } }
end

-- ===== shared gestures (keys in seconds; missing joints hold; last key returns to 0 unless hold) =====
local G = {}
G.adjustCollar = { weight = 2, cooldown = { 12, 20 }, duration = 1.2, keys = {
	{ t = 0 }, { t = 0.4, RightShoulder = { swing = 25 }, RightElbow = { swing = 40 } },
	{ t = 0.8, RightShoulder = { swing = 25 }, RightElbow = { swing = 40 } }, { t = 1.2 } } }
G.scratchBrim = { weight = 0, cooldown = { 12, 18 }, duration = 1.4, keys = {
	{ t = 0 }, { t = 0.45, LeftShoulder = { swing = 40, spread = 25 }, LeftElbow = { swing = 110 }, LeftWrist = { twist = -20 } },
	{ t = 0.95, LeftShoulder = { swing = 40, spread = 25 }, LeftElbow = { swing = 110 }, LeftWrist = { twist = -20 } }, { t = 1.4 } } }
G.handsOnHips = { weight = 1, cooldown = { 20, 40 }, duration = 6.0, hold = false, keys = {
	{ t = 0 }, { t = 0.6, LeftShoulder = { swing = 20, spread = 35 }, LeftElbow = { swing = 95 }, RightShoulder = { swing = 20, spread = 35 }, RightElbow = { swing = 95 } },
	{ t = 5.4, LeftShoulder = { swing = 20, spread = 35 }, LeftElbow = { swing = 95 }, RightShoulder = { swing = 20, spread = 35 }, RightElbow = { swing = 95 } }, { t = 6.0 } } }
G.inspectItem = { weight = 2, cooldown = { 15, 30 }, duration = 2.6, keys = {
	{ t = 0 }, { t = 0.6, RightShoulder = { swing = 55, spread = 10 }, RightElbow = { swing = 70 }, Neck = { bend = 10 } },
	{ t = 2.0, RightShoulder = { swing = 55, spread = 10 }, RightElbow = { swing = 70 }, Neck = { bend = 10, turn = 6 } }, { t = 2.6 } } }
G.glanceAtLandmark = { weight = 1, cooldown = { 25, 45 }, duration = 3.4, keys = {
	{ t = 0 }, { t = 0.7, Waist = { turn = 30 }, Neck = { turn = 20 } }, { t = 2.8, Waist = { turn = 30 }, Neck = { turn = 20 } }, { t = 3.4 } } }
G.wave = { weight = 0, cooldown = { 30, 60 }, duration = 1.6, keys = {
	{ t = 0 }, { t = 0.4, RightShoulder = { swing = 50, spread = 30 }, RightElbow = { swing = 80 } },
	{ t = 0.7, RightShoulder = { swing = 50, spread = 30 }, RightElbow = { swing = 80 }, RightWrist = { twist = 20 } },
	{ t = 1.0, RightShoulder = { swing = 50, spread = 30 }, RightElbow = { swing = 80 }, RightWrist = { twist = -20 } },
	{ t = 1.2, RightShoulder = { swing = 50, spread = 30 }, RightElbow = { swing = 80 }, RightWrist = { twist = 0 } }, { t = 1.6 } } }
G.nodGreet = { weight = 0, cooldown = { 30, 60 }, duration = 0.6, keys = { { t = 0 }, { t = 0.25, Neck = { bend = 8 } }, { t = 0.6 } } }
-- Gianluca's signature: the one gesture above 40 deg (doc C6)
G.ringBell = { weight = 0, cooldown = { 14, 26 }, duration = 2.4, signature = true, keys = {
	{ t = 0 },
	{ t = 0.45, RightShoulder = { swing = 75, spread = 8 }, RightElbow = { swing = 25 } },
	{ t = 0.65, RightShoulder = { swing = 75, spread = 8 }, RightElbow = { swing = 25 }, RightWrist = { twist = 22 } },
	{ t = 0.85, RightShoulder = { swing = 75, spread = 8 }, RightElbow = { swing = 25 }, RightWrist = { twist = -22 } },
	{ t = 1.05, RightShoulder = { swing = 75, spread = 8 }, RightElbow = { swing = 25 }, RightWrist = { twist = 22 } },
	{ t = 1.25, RightShoulder = { swing = 75, spread = 8 }, RightElbow = { swing = 25 }, RightWrist = { twist = 0 } },
	{ t = 1.45, RightShoulder = { swing = 75, spread = 8 }, RightElbow = { swing = 25 }, Neck = { turn = -38, bend = -4 }, Waist = { turn = -10 } },
	{ t = 1.85, RightShoulder = { swing = 75, spread = 8 }, RightElbow = { swing = 25 }, Neck = { turn = 38, bend = -4 }, Waist = { turn = 10 } },
	{ t = 2.15, RightShoulder = { swing = 75, spread = 8 }, RightElbow = { swing = 25 }, Neck = { turn = 0, bend = 0 }, Waist = { turn = 0 } },
	{ t = 2.40 } } }
-- merchant
G.countGems = { weight = 2, cooldown = { 10, 18 }, duration = 2.5, keys = {
	{ t = 0 }, { t = 0.5, RightShoulder = { swing = 35 }, RightElbow = { swing = 75 }, LeftShoulder = { swing = 35 }, LeftElbow = { swing = 75 }, Neck = { bend = 12 } },
	{ t = 1.1, RightShoulder = { swing = 35 }, RightElbow = { swing = 75 }, LeftShoulder = { swing = 35 }, LeftElbow = { swing = 75 }, RightWrist = { twist = 15 }, Neck = { bend = 12 } },
	{ t = 1.7, RightShoulder = { swing = 35 }, RightElbow = { swing = 75 }, LeftShoulder = { swing = 35 }, LeftElbow = { swing = 75 }, RightWrist = { twist = -15 }, Neck = { bend = 12 } },
	{ t = 2.5 } } }
G.beckon = { weight = 0, cooldown = { 20, 40 }, duration = 1.4, keys = {
	{ t = 0 }, { t = 0.4, RightShoulder = { swing = 40, spread = 20 }, RightElbow = { swing = 70 } },
	{ t = 0.7, RightShoulder = { swing = 40, spread = 20 }, RightElbow = { swing = 95 } },
	{ t = 1.0, RightShoulder = { swing = 40, spread = 20 }, RightElbow = { swing = 70 } }, { t = 1.4 } } }
-- guard
G.postureShift = { weight = 2, cooldown = { 12, 22 }, duration = 1.6, keys = {
	{ t = 0 }, { t = 0.5, Root = { tilt = 3 }, LeftHip = { tilt = -3 }, RightHip = { tilt = -3 }, Waist = { turn = -6 } },
	{ t = 1.1, Root = { tilt = 3 }, LeftHip = { tilt = -3 }, RightHip = { tilt = -3 }, Waist = { turn = -6 } }, { t = 1.6 } } }
G.alertGlance = { weight = 2, cooldown = { 8, 16 }, duration = 1.8, keys = {
	{ t = 0 }, { t = 0.18, Neck = { turn = 32 } }, { t = 1.3, Neck = { turn = 32 } }, { t = 1.8 } } }
-- survivor
G.warmHands = { weight = 2, cooldown = { 12, 24 }, duration = 2.2, keys = {
	{ t = 0 }, { t = 0.6, RightShoulder = { swing = 30, spread = -6 }, RightElbow = { swing = 100 }, LeftShoulder = { swing = 30, spread = -6 }, LeftElbow = { swing = 100 }, Waist = { bend = 4 } },
	{ t = 1.7, RightShoulder = { swing = 30, spread = -6 }, RightElbow = { swing = 100 }, LeftShoulder = { swing = 30, spread = -6 }, LeftElbow = { swing = 100 }, Waist = { bend = 4 } }, { t = 2.2 } } }
G.nervousGlance = { weight = 3, cooldown = { 6, 12 }, duration = 1.4, keys = {
	{ t = 0 }, { t = 0.15, Neck = { turn = -28 } }, { t = 0.6, Neck = { turn = -28 } }, { t = 0.8, Neck = { turn = 24 } }, { t = 1.1, Neck = { turn = 24 } }, { t = 1.4 } } }
G.lookUpward = { weight = 1, cooldown = { 30, 60 }, duration = 3.0, keys = {
	{ t = 0 }, { t = 0.8, Neck = { bend = -25 } }, { t = 2.4, Neck = { bend = -25 } }, { t = 3.0 } } }
-- talking
G.emphasis = { weight = 2, cooldown = { 4, 7 }, duration = 1.2, talk = true, keys = {
	{ t = 0 }, { t = 0.35, RightShoulder = { swing = 30 }, RightElbow = { swing = 55 } }, { t = 0.8, RightShoulder = { swing = 30 }, RightElbow = { swing = 55 } }, { t = 1.2 } } }
G.openHand = { weight = 2, cooldown = { 4, 7 }, duration = 1.4, talk = true, keys = {
	{ t = 0 }, { t = 0.4, LeftShoulder = { swing = 25, spread = 20 }, LeftElbow = { swing = 70 }, LeftWrist = { twist = 25 } },
	{ t = 0.95, LeftShoulder = { swing = 25, spread = 20 }, LeftElbow = { swing = 70 }, LeftWrist = { twist = 25 } }, { t = 1.4 } } }
G.nod = { weight = 1, cooldown = { 3, 5 }, duration = 0.5, talk = true, keys = { { t = 0 }, { t = 0.2, Neck = { bend = 3 } }, { t = 0.5 } } }

NpcMotionConfig.Gestures = G

local function pick(names)
	local out = {}
	for _, n in ipairs(names) do out[n] = G[n] end
	return out
end

-- ===== PACKS =================================================================
NpcMotionConfig.Packs = {}
local P = NpcMotionConfig.Packs

P.Background = {
	idle = { breathe = breathe(3.4, 1.5), weightShift = weightShift(9.0, 2.5), weightDip = weightDip(9.0), look = look(6.5, 22) },
	gestures = pick({ "adjustCollar" }),
	greet = "nodGreet",
	track = { maxTurn = 25, maxBend = 10, smooth = 0.3, promptWeight = 0.5 },
	talk = { every = { 5, 8 }, gestures = { "nod" } },
	gestureRange = 30,
}
P.Villager = {
	idle = { breathe = breathe(3.4, 1.5), weightShift = weightShift(9.0, 2.5), weightDip = weightDip(9.0),
		look = look(6.5, 22), lookTilt = lookTilt(6.5), handSway = handSway() },
	gestures = pick({ "adjustCollar", "scratchBrim", "handsOnHips", "inspectItem", "glanceAtLandmark", "wave", "nodGreet", "ringBell", "emphasis", "openHand", "nod" }),
	greet = "wave",
	track = { maxTurn = 35, maxBend = 15, smooth = 0.25, promptWeight = 0.6 },
	talk = { every = { 4, 7 }, gestures = { "emphasis", "openHand" }, nod = { every = { 3, 5 } } },
	gestureRange = 90,
}
P.Merchant = {
	idle = { breathe = breathe(3.2, 1.5), weightShift = weightShift(8.0, 2.0), weightDip = weightDip(8.0), look = look(5.5, 18), handSway = handSway() },
	gestures = pick({ "countGems", "inspectItem", "wave", "beckon", "emphasis", "openHand", "nod" }),
	greet = "beckon",
	track = { maxTurn = 35, maxBend = 15, smooth = 0.25, promptWeight = 0.6 },
	talk = { every = { 4, 6 }, gestures = { "emphasis", "openHand" }, nod = { every = { 3, 5 } } },
	speed = 1.0,
	gestureRange = 90,
}
P.Guard = {
	idle = { breathe = breathe(3.8, 1.2), weightShift = weightShift(11.0, 1.5), look = look(8.0, 16) },
	gestures = pick({ "postureShift", "alertGlance", "nodGreet", "emphasis", "nod" }),
	greet = "alertGlance",
	track = { maxTurn = 30, maxBend = 10, smooth = 0.2, promptWeight = 0.8 },
	talk = { every = { 6, 9 }, gestures = { "emphasis" }, nod = { every = { 4, 6 } } },
	gestureRange = 90,
}
P.Survivor = {
	idle = { breathe = breathe(3.6, 1.4), weightShift = weightShift(9.5, 2.0), weightDip = weightDip(9.5), look = look(5.0, 24), handSway = handSway(),
		hunch = { kind = "const", amp = 8, effects = { E("Waist", "bend", 1), E("Neck", "bend", -0.4) } } },
	gestures = pick({ "nervousGlance", "warmHands", "inspectItem", "lookUpward", "nodGreet", "emphasis", "openHand", "nod" }),
	greet = "nervousGlance",
	track = { maxTurn = 35, maxBend = 15, smooth = 0.3, promptWeight = 0.6 },
	talk = { every = { 4, 7 }, gestures = { "emphasis", "openHand" }, nod = { every = { 3, 5 } } },
	gestureRange = 90,
}
-- Story brainrots: whole-model breathe + optional head/wing joints, no gestures.
P.Creature = {
	idle = { breathe = { kind = "sine", period = 4.6, amp = 0.03, effects = { E("__model", "up", 1) } },
		glance = { kind = "snap", period = 11, amp = 14, ease = 0.3, optional = true, effects = { E("Head", "turn", 1) } },
		sag = { kind = "sine", period = 6, amp = 1.5, optional = true, effects = { E("WingL", "spread", -1) } } },
	gestures = {},
	greet = nil,
	track = { maxTurn = 40, maxBend = 8, smooth = 2.2, promptWeight = 1.0, holdAfter = 4, target = "Head" },
	talk = { every = { 5, 8 }, gestures = {}, nod = { every = { 5, 8 }, amp = 3 } },
	profiles = {
		Veteran  = { ["idle.breathe.period"] = 4.6 },
		Deserter = { ["idle.breathe.period"] = 3.6, ["idle.glance.period"] = 6, ["idle.glance.amp"] = 22 },
		Ancient  = { ["idle.breathe.period"] = 7.0, ["idle.glance.optional"] = true, ["idle.glance.amp"] = 0 },
	},
	gestureRange = 0,
}

-- ===== Resolve ===============================================================
local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = deepCopy(v) end
	return out
end

local function setPath(root, path, value)
	local cur = root
	local keys = {}
	for seg in string.gmatch(path, "[^%.]+") do keys[#keys + 1] = seg end
	for i = 1, #keys - 1 do
		if type(cur[keys[i]]) ~= "table" then cur[keys[i]] = {} end
		cur = cur[keys[i]]
	end
	cur[keys[#keys]] = value
end

-- Resolve(packId, overrides?, profileId?) -> a private deep copy with dot-path
-- overrides applied. `greet` may be overridden as a plain key.
function NpcMotionConfig.Resolve(packId, overrides, profileId)
	local src = P[packId]
	if not src then error("NpcMotionConfig: unknown pack " .. tostring(packId)) end
	local pack = deepCopy(src)
	pack.id = packId
	if profileId and src.profiles and src.profiles[profileId] then
		for path, v in pairs(src.profiles[profileId]) do setPath(pack, path, v) end
		pack.profile = profileId
	end
	if overrides then
		for path, v in pairs(overrides) do
			if type(path) == "string" and path:find("%.") then setPath(pack, path, v) else pack[path] = v end
		end
	end
	return pack
end

return NpcMotionConfig
