-- ReplicatedStorage.Modules.SizeConfig
-- SIZE is a SECOND, INDEPENDENT mutation axis (2026-08-07, owner's design).
--
-- MutationConfig owns the COLOUR/finish axis -- Golden, Diamond, Rainbow, the eight
-- weather variants. This owns SIZE. They stack: a brainrot can be Golden AND Massive,
-- and its income multiplies both ways. That is the whole point -- two independent things
-- to chase on the same catch instead of one slot they fight over.
--
-- WHY A SEPARATE MODULE rather than more rows in MutationConfig.List: that list is a
-- single-slot ladder (data.Brainrots[i].Mutation is ONE string) whose rungs are mutually
-- exclusive and whose order feeds the fusion map in FusionHandler. Size is orthogonal to
-- all of that. Keeping it apart means the fusion ladder, the event calibration and the
-- effective-rate table in MutationConfig are all untouched.
--
-- NO SAVE MIGRATION IS NEEDED. SessionLock.Save writes the profile table wholesale with
-- no field whitelist, and a brainrot entry is a plain table -- so a new Size field simply
-- persists. Every brainrot saved before today reads Size == nil, which IS "normal", so
-- old saves are correct by default rather than by conversion.

local Sizes = {}

-- Scale multiplies the size BrainrotSpawner already fitted, so it stacks on top of the
-- per-rarity HeightScale rather than replacing it.
--
-- These DELIBERATELY BREAK the pad-width cap. Camps were just widened so ordinary models
-- reach 9.5 studs without touching a neighbour; a Massive at 1.65 is ~15.7 studs and WILL
-- sprawl over the pads either side. That is the intent -- a Massive is meant to look
-- absurd and dominate the camp. Brainrots have CanCollide off, so overlap is purely
-- visual and nothing gets pushed around.
-- RESCALED 2026-08-07 (owner): what used to be Massive is now HUGE, and Massive was
-- tripled on top of that. Huge is the "noticeably bigger" rung; Massive is the one that
-- swallows the camp -- a 9.5-stud body becomes ~47 studs, wider than the whole pad ring.
Sizes.List = {
	{ Name = "Huge",    Scale = 1.65, Mult = 3, Chance = 0.020,  Color = Color3.fromRGB(120, 220, 255) },
	{ Name = "Massive", Scale = 4.95, Mult = 8, Chance = 0.0035, Color = Color3.fromRGB(255, 150, 60) },
}

Sizes.ByName = {}
for _, s in ipairs(Sizes.List) do
	Sizes.ByName[s.Name] = s
end

-- Rolled INDEPENDENTLY of MutationConfig.Roll, on the same catch. Rarest first so the
-- ladder cannot be short-circuited by an earlier, commoner rung.
-- boost (>1) scales the odds, matching how weather boosts colour mutations.
function Sizes.Roll(boost)
	boost = (type(boost) == "number" and boost > 0) and boost or 1
	for i = #Sizes.List, 1, -1 do
		local s = Sizes.List[i]
		if math.random() < s.Chance * boost then
			return s.Name
		end
	end
	return nil
end

-- nil-safe everywhere: an ordinary brainrot has no Size and must read as 1x / 1.0 scale.
function Sizes.Mult(name)
	local s = name and Sizes.ByName[name]
	return s and s.Mult or 1
end

function Sizes.Scale(name)
	local s = name and Sizes.ByName[name]
	return s and s.Scale or 1
end

function Sizes.Color(name)
	local s = name and Sizes.ByName[name]
	return s and s.Color or nil
end

-- "Golden Massive Kraken Congelato" -- size sits between the colour and the name, because
-- the colour is the adjective players say first.
function Sizes.Label(mutation, size, name)
	local bits = {}
	if mutation then bits[#bits + 1] = mutation end
	if size then bits[#bits + 1] = size end
	bits[#bits + 1] = name
	return table.concat(bits, " ")
end

return Sizes
