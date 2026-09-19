-- NpcWorldThemes -- how one character is re-dressed per world (decision D-5:
-- the same recurring merchants, world-specific outfit variants).
--
-- A theme never changes the face, the body type, the pack or the identifying
-- prop; it changes colours (a palette shift + an accent), swaps or adds
-- overlays (weather gear), and decides whether lanterns may light.
--
-- `shift` is applied to every family colour EXCEPT skin/hair/metal: HSV
-- saturation and value deltas (-0.2 = 20 % less). `replaceOverlay` swaps a
-- library id for another when a recipe lists it; `addOverlays` are appended.

local NpcWorldThemes = {}
NpcWorldThemes.Version = 1

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

NpcWorldThemes.Themes = {
	Valley = {
		id = "Valley",
		shift = { sat = 0, val = 0 },
		accent = C(108, 160, 80),
		replaceOverlay = {},
		addOverlays = {},
		lightsAllowed = false,
		defaultFamilyByRole = { villager = "village", ranger = "ranger", merchant = "merchant" },
	},
	Tundra = {
		id = "Tundra",
		shift = { sat = -0.15, val = -0.05 },
		accent = C(226, 214, 196),          -- fur cream
		replaceOverlay = { CloakYoke = "CloakYoke", ScarfTail = "ScarfTail", Vest = "Vest" },   -- placeholders until FurCollar / JacketBody meshes exist (wave 2)
		addOverlays = {},                    -- wave 2: "FurCollar"
		hatDefault = "HatFlatCap",           -- wave 2: "HatKnitCap"
		lightsAllowed = true,
		defaultFamilyByRole = { villager = "winter", merchant = "merchant" },
		familyOverride = { merchant = { base = C(96, 116, 140), light = C(226, 214, 196) } },   -- the winter cut of the merchant family
	},
	Gardens = {
		id = "Gardens",
		shift = { sat = -0.25, val = -0.10 },
		accent = C(158, 234, 238),          -- one cyan crystal per district, never more
		replaceOverlay = {},
		addOverlays = {},                    -- wave 2: "ArmWrap" on merchants (patched cut)
		lightsAllowed = true,
		defaultFamilyByRole = { villager = "survivor", merchant = "merchant", guard = "castle", scavenger = "scavenger", elder = "survivor" },
		familyOverride = { merchant = { base = C(118, 118, 112), light = C(190, 146, 72), accent = C(150, 74, 44) } },   -- the patched cut
	},
	Trading = {
		id = "Trading",
		shift = { sat = 0.05, val = 0.05 },
		accent = C(54, 224, 214),
		replaceOverlay = {},
		addOverlays = {},
		lightsAllowed = false,
		defaultFamilyByRole = { merchant = "trader", noble = "noble" },
	},
}

function NpcWorldThemes.Get(id)
	local t = NpcWorldThemes.Themes[id]
	if not t then error("NpcWorldThemes: unknown theme " .. tostring(id)) end
	return t
end

-- HSV shift helper (pure). Skin, hair and metal are never shifted: a person
-- does not change colour with the weather, their coat does.
local PROTECTED = { skin = true, hair = true, metal = true }
function NpcWorldThemes.ApplyShift(colorSet, theme)
	local out = {}
	local s, v = theme.shift.sat or 0, theme.shift.val or 0
	for role, col in pairs(colorSet) do
		if PROTECTED[role] or (s == 0 and v == 0) then
			out[role] = col
		else
			local h, sat, val = col:ToHSV()
			sat = math.max(0, math.min(1, sat + s))
			val = math.max(0, math.min(1, val + v))
			out[role] = Color3.fromHSV(h, sat, val)
		end
	end
	return out
end

return NpcWorldThemes
