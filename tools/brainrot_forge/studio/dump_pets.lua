-- Dumps the Part-built pet prototypes (ServerStorage._PETS_Prototypes) as compact JSON in the same
-- format as dump_parts.lua, positions in each model's own pivot frame (feet on y = 0, face -Z), for
-- `python -m brainrot_forge pets --before <file>`: the contact sheet draws them next to the new designs.
-- Read-only. Run from the MCP exec in Edit mode and save the output to tools/out/pets/item5_dump.json.
local HS = game:GetService("HttpService")
local P = game:GetService("ServerStorage")._PETS_Prototypes
local NAMES = { "vox_Heartwood", "vox_ElderStag", "vox_SapSnail", "vox_ForestEgg", "vox_TundraEgg" }
local MAT = { Plastic = "P", SmoothPlastic = "S", Neon = "N" }
local function r4(x) return math.floor(x * 10000 + 0.5) / 10000 end
local out = {}
for _, name in ipairs(NAMES) do
	local m = P[name]
	local piv = m:GetPivot()
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local c = { piv:ToObjectSpace(d.CFrame):GetComponents() }
			local rec = { r4(c[1]), r4(c[2]), r4(c[3]), r4(d.Size.X), r4(d.Size.Y), r4(d.Size.Z), d.Color:ToHex(), MAT[d.Material.Name] or d.Material.Name }
			if not (math.abs(c[4] - 1) < 1e-4 and math.abs(c[8] - 1) < 1e-4 and math.abs(c[12] - 1) < 1e-4) then
				rec[9] = { r4(c[4]), r4(c[5]), r4(c[6]), r4(c[7]), r4(c[8]), r4(c[9]), r4(c[10]), r4(c[11]), r4(c[12]) }
			end
			parts[#parts + 1] = rec
		end
	end
	out[#out + 1] = { name = name, rarity = "Item5", world = "Prototype", attrs = {}, fx = false, parts = parts }
end
return HS:JSONEncode(out)
