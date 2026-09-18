--!strict
-- CatchCinematic.Cuts.Registry -- cut lookup by name. Fail-soft: a cut module that
-- is missing or fails to load returns nil, and the caller falls back (stock landing
-- for the world, a pop for the reveal). Never throws.
local Types = require(script.Parent.Parent:WaitForChild("Types"))
type Cut = Types.Cut

local Registry = {}
local cache: { [string]: Cut } = {}

function Registry.get(name: string): Cut?
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if cache[name] then
		return cache[name]
	end
	local inst = script.Parent:FindFirstChild(name)
	if not inst or not inst:IsA("ModuleScript") then
		return nil
	end
	local ok, cut = pcall(require, inst)
	if not ok or type(cut) ~= "table" or type(cut.beats) ~= "table" or type(cut.handlers) ~= "table" then
		warn("[Cuts.Registry] cut '" .. name .. "' unavailable: " .. tostring(cut))
		return nil
	end
	cache[name] = cut
	return cut
end

Registry.NAMES = { "Mythic", "Secret", "God", "Huge", "Massive", "MassiveGod" }

return Registry
