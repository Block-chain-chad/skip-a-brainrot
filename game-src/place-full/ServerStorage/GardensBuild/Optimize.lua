-- Optimize -- performance pass over World 3.
--
-- Three things dominate the cost of a world this size, and none of them is the raw
-- part count:
--   1. LIGHTS. Every PointLight is a real-time light source. 2400 of them, mostly
--      stuck on decorative blossoms and flowers, is far past what the renderer can
--      absorb. Neon material still GLOWS without a light attached, so decoration
--      keeps its look while only genuine lamps keep an actual light.
--   2. SHADOWS. 20k shadow-casting parts, nearly all of them leaves and twigs, each
--      one costing shadow-map work for a contribution nobody can see.
--   3. QUERY/TOUCH. Decorative parts answering raycasts and touch events.
--
-- Re-runnable, and should be re-run after any further building.

local Optimize = {}

-- host parts that keep a real light: actual lamps, fires, beacons, and the few big
-- set-piece glows the world is lit by
local KEEP_LIGHT = {
	LanternCore = true, BrazierFire = true, TowerBeacon = true, SpireBeacon = true,
	VeilLight = true, ShrineLight = true, AltarLight = true, FountainCrown = true,
	BasinWater = true, WellWater = true, RoseHeart = true, GateGlow = true,
}
-- these keep a light but only a fraction of them
local THIN_LIGHT = {
	FallLight = 3, CrystalCore = 2, CapGlow = 3, WindowGlow = 5, TierWater = 2,
}
-- never casts a shadow, regardless of size
local NO_SHADOW = {
	Leaves = true, Branch = true, TreeRoot = true, Rootlet = true, RootJoint = true,
	Vine = true, VineLeaf = true, Frond = true, Bush = true, Petal = true,
	Blossom = true, Moss = true, WallMoss = true, Gill = true, CapSpot = true,
	Trunk = true, Stalk = true, ArchRoot = true, Root = true, RootletTip = true,
	Streak = true, FallRibbon = true, FallBody = true, FallSheet = true,
	Flower = true, Stem = true, Reed = true, LilyPad = true, PadNotch = true,
	Crystal = true, CrystalCore = true, Mane = true, Feather = true, Membrane = true,
}
local SHADOW_MIN_VOLUME = 320   -- below this, a part's shadow is not worth its cost

function Optimize.run(root)
	root = root or workspace.GameWorld.LushGardens
	local before = {parts = 0, lights = 0, shadows = 0, emitters = 0}
	local after = {lights = 0, shadows = 0, emitters = 0}
	local thinCount = {}

	local kill = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Light") then
			before.lights = before.lights + 1
			local host = d.Parent and d.Parent.Name or ""
			local keep = false
			if KEEP_LIGHT[host] then
				keep = true
			elseif THIN_LIGHT[host] then
				thinCount[host] = (thinCount[host] or 0) + 1
				keep = (thinCount[host] % THIN_LIGHT[host] == 0)
			end
			if keep then
				-- shadow-casting lights are several times the cost of one that does not
				d.Shadows = false
				after.lights = after.lights + 1
			else
				kill[#kill + 1] = d
			end
		elseif d:IsA("BasePart") then
			before.parts = before.parts + 1
			if d.CastShadow then before.shadows = before.shadows + 1 end
			local vol = d.Size.X * d.Size.Y * d.Size.Z
			if NO_SHADOW[d.Name] or vol < SHADOW_MIN_VOLUME then
				d.CastShadow = false
			end
			if d.CastShadow then after.shadows = after.shadows + 1 end
			-- decorative parts should not be answering spatial queries
			if not d.CanCollide and d.CanQuery and d.Name ~= "PortalTouch" then
				d.CanQuery = false
				d.CanTouch = false
			end
		elseif d:IsA("ParticleEmitter") then
			before.emitters = before.emitters + 1
			after.emitters = after.emitters + 1
		end
	end
	for _, d in ipairs(kill) do d:Destroy() end

	return string.format(
		"parts %d | lights %d -> %d | shadow casters %d -> %d | emitters %d",
		before.parts, before.lights, after.lights, before.shadows, after.shadows, before.emitters)
end

return Optimize
