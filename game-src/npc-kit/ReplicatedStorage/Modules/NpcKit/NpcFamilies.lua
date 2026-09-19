-- NpcFamilies -- clothing families as COLOUR SETS + default overlays.
--
-- One colour role per body MeshPart (the forge rule), so most of what makes a
-- ranger a ranger is which role paints which segment. `bodyRoles` maps R15
-- part names to role names; `colors` maps role names to Color3. A recipe adds
-- overlays on top and may override any role.
--
-- Roles used across the kit: skin, hair, base (main cloth), light (yoke/apron),
-- accent, seam, leather, metal, walnut, stone, trouser, boot, bootDark, hat.

local NpcFamilies = {}
NpcFamilies.Version = 1

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

local SKIN_TAN = C(214, 176, 138)
local SKIN_PALE = C(228, 206, 186)
local SKIN_GREY = C(206, 196, 186)
local LEATHER = C(134, 96, 58)
local WALNUT = C(74, 50, 30)
local BRASS = C(196, 150, 72)
local IRON = C(96, 98, 104)
local SOOT = C(52, 50, 48)
local STONE = C(138, 138, 130)

-- The default segment -> role map; families override individual entries.
local BODY_ROLES = {
	Head = "skin", LowerTorso = "leather", UpperTorso = "base",
	RightUpperArm = "base", LeftUpperArm = "base",
	RightLowerArm = "skin", LeftLowerArm = "skin",       -- rolled sleeves by default
	RightHand = "skin", LeftHand = "skin",
	RightUpperLeg = "trouser", LeftUpperLeg = "trouser",
	RightLowerLeg = "boot", LeftLowerLeg = "boot",
	RightFoot = "bootDark", LeftFoot = "bootDark",
}

local function family(id, colors, roleOverrides, defaultOverlays)
	local roles = {}
	for k, v in pairs(BODY_ROLES) do roles[k] = v end
	for k, v in pairs(roleOverrides or {}) do roles[k] = v end
	local base = { skin = SKIN_TAN, hair = C(92, 58, 36), leather = LEATHER, metal = BRASS, walnut = WALNUT, stone = STONE,
		seam = WALNUT, trouser = WALNUT, boot = C(110, 78, 46), bootDark = C(86, 60, 36) }
	for k, v in pairs(colors) do base[k] = v end
	return { id = id, colors = base, bodyRoles = roles, defaultOverlays = defaultOverlays or {} }
end

NpcFamilies.Families = {
	village  = family("village",  { base = C(238, 226, 200), light = C(238, 226, 200), accent = C(168, 58, 86), hat = C(108, 160, 80) }, nil, { "Vest", "Belt" }),
	ranger   = family("ranger",   { base = C(98, 140, 70), light = C(238, 226, 200), accent = C(168, 58, 86), hat = C(108, 160, 80), seam = C(58, 40, 24) }, nil, { "TunicHem", "CloakYoke", "Bracer", "ToolBelt" }),
	merchant = family("merchant", { base = C(238, 226, 200), light = C(246, 240, 226), accent = C(255, 216, 96), hat = C(120, 88, 60) }, nil, { "ApronBib", "ApronSkirt" }),
	winter   = family("winter",   { skin = SKIN_PALE, base = C(96, 116, 140), light = C(226, 214, 196), accent = C(226, 214, 196), hat = C(44, 46, 52), seam = C(44, 46, 52), trouser = C(44, 46, 52) },
		{ RightLowerArm = "base", LeftLowerArm = "base" }, { "CloakYoke", "Belt" }),
	engineer = family("engineer", { base = C(58, 84, 110), light = C(226, 214, 196), accent = BRASS, hat = C(44, 46, 52) }, nil, { "ApronBib", "Bracer", "ToolBelt" }),
	castle   = family("castle",   { skin = SKIN_PALE, base = C(108, 112, 120), light = C(200, 200, 196), accent = BRASS, metal = IRON, hat = IRON, trouser = C(64, 66, 72) },
		{ RightLowerArm = "base", LeftLowerArm = "base" }, { "Belt", "Bracer" }),
	survivor = family("survivor", { skin = SKIN_GREY, base = C(118, 118, 112), light = C(190, 146, 72), accent = C(150, 74, 44), hat = SOOT, seam = SOOT, trouser = C(76, 72, 66), boot = C(60, 56, 50), bootDark = C(44, 42, 40) },
		nil, { "TunicHem", "Belt" }),
	miner    = family("miner",    { skin = SKIN_GREY, base = C(190, 146, 72), light = C(190, 146, 72), accent = BRASS, hat = SOOT, seam = SOOT, trouser = C(76, 72, 66) }, nil, { "ApronSkirt", "Bracer", "ToolBelt" }),
	scavenger = family("scavenger", { skin = SKIN_GREY, base = C(118, 118, 112), light = C(150, 74, 44), accent = C(150, 74, 44), hat = SOOT, seam = SOOT, trouser = C(76, 72, 66), boot = C(60, 56, 50), bootDark = C(44, 42, 40) },
		nil, { "ToolBelt", "Bracer" }),
	noble    = family("noble",    { skin = SKIN_PALE, base = C(64, 42, 110), light = C(245, 250, 250), accent = C(255, 196, 64), metal = C(255, 196, 64), hat = C(28, 26, 40), trouser = C(28, 26, 40) },
		{ RightLowerArm = "base", LeftLowerArm = "base" }, { "CloakYoke", "Belt" }),
	trader   = family("trader",   { base = C(245, 250, 250), light = C(245, 250, 250), accent = C(54, 224, 214), metal = C(255, 196, 64), hat = C(238, 214, 166), trouser = C(238, 214, 166) },
		nil, { "Vest", "Belt" }),
}

function NpcFamilies.Get(id)
	local f = NpcFamilies.Families[id]
	if not f then error("NpcFamilies: unknown family " .. tostring(id)) end
	return f
end

-- Resolve a colour reference: a Color3 passes through, a role name looks up
-- the (already merged) colour set, nil falls back to the role the caller gives.
function NpcFamilies.ResolveColor(colorSet, ref, fallbackRole)
	if typeof(ref) == "Color3" then return ref end
	if type(ref) == "string" and colorSet[ref] then return colorSet[ref] end
	return colorSet[fallbackRole] or colorSet.base
end

return NpcFamilies
