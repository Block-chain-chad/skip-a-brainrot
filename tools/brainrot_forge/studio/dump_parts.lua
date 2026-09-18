-- Dumps a group of Part-built brainrot templates as compact JSON for tools/brainrot_forge/ingest_parts.py.
-- Run from the MCP exec (Edit mode). Outputs >= ~30 KB are persisted by the harness to a file; copy that
-- file to tools/out/convert/dump/groupN.json. Keep groups to ~9 models so every output is persisted.
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local NAMES = { "__GROUP__" }

local rarity, world = {}, {}
for _, spec in ipairs({ { "BrainrotConfig", "Valley" }, { "BrainrotConfigTundra", "Tundra" } }) do
	local src = RS.Modules[spec[1]].Source
	for name, r in src:gmatch('Name%s*=%s*"([^"]+)"%s*,%s*Rarity%s*=%s*"([^"]+)"') do
		if not rarity[name] then rarity[name] = r; world[name] = spec[2] end
	end
end
local MAT = { Plastic = "P", SmoothPlastic = "S", Neon = "N" }
local function r4(x) return math.floor(x * 10000 + 0.5) / 10000 end
local out = {}
for _, name in ipairs(NAMES) do
	local m = RS.BrainrotModels:FindFirstChild(name) or error("missing " .. name)
	local parts, fx = {}, false
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name:sub(1, 10) == "BrainrotFx" then
				fx = true
			elseif d.Transparency < 1 then
				assert(d:IsA("Part") and d.Shape == Enum.PartType.Block, name .. " has a non-block part: " .. d.Name)
				local c = { d.CFrame:GetComponents() }
				local rec = { r4(c[1]), r4(c[2]), r4(c[3]), r4(d.Size.X), r4(d.Size.Y), r4(d.Size.Z), d.Color:ToHex(), MAT[d.Material.Name] or d.Material.Name }
				local ident = math.abs(c[4] - 1) < 1e-4 and math.abs(c[8] - 1) < 1e-4 and math.abs(c[12] - 1) < 1e-4
				if not ident then rec[9] = { r4(c[4]), r4(c[5]), r4(c[6]), r4(c[7]), r4(c[8]), r4(c[9]), r4(c[10]), r4(c[11]), r4(c[12]) } end
				parts[#parts + 1] = rec
			end
		end
	end
	local attrs = {}
	for k, v in pairs(m:GetAttributes()) do
		local t = typeof(v)
		if t == "number" or t == "string" or t == "boolean" then attrs[k] = v end
	end
	out[#out + 1] = { name = name, rarity = rarity[name] or "Unknown", world = world[name] or "Unknown", attrs = attrs, fx = fx, parts = parts }
end
return HS:JSONEncode(out)
