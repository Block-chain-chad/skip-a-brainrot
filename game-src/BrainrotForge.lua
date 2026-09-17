--[[ ServerStorage.BrainrotForge -- BUILD-TIME assembler: File > Import 3D output + manifest.json
-> brainrot templates that satisfy the content-drop contract (docs/brainrot-build-standard.md, 2.7).

Never required by game code. From the command bar / MCP in Edit mode, after the user has imported
tools/out/<batch>/<batch>_batch.glb (the importer parks it under workspace.AuxScene):

    local F = loadstring(game.ServerStorage.BrainrotForge.Source)()   -- or require(...:Clone()) from the command bar
    local models, errors = F.Assemble(workspace.AuxScene, MANIFEST_JSON, { tile = true })

Per model, all-or-nothing: on any error the imported parts are put back under the import root with
their original names and nothing is parented into BrainrotModels. Existing templates are never
overwritten unless opts.replace, and then the old one is moved to ServerStorage.AuditBackups first.

NOTE ON LOADING: the MCP exec sandbox cannot `require` any ModuleScript in this place (they carry
default script Capabilities the sandbox lacks), so helpers are loaded with loadModule() below, which
tries require and falls back to loadstring(Source)(). Build-time only; never do this in game code.
]]
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local M = {}
M.TARGET_FOLDER = "BrainrotModels"
M.TILE_VARIANT = "BrainrotTile"
M.BACKUP_FOLDER = "AuditBackups"

local function loadModule(moduleScript)
	local ok, mod = pcall(require, moduleScript:Clone())
	if ok then return mod end
	local chunk, err = loadstring(moduleScript.Source)
	assert(chunk, ("cannot load %s: %s"):format(moduleScript:GetFullName(), tostring(err)))
	return chunk()
end
M.loadModule = loadModule

local function hexToColor3(hex)
	local h = hex:gsub("#", "")
	return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
end

local function findParts(root, names)
	local wanted, found, missing = {}, {}, {}
	for _, n in ipairs(names) do wanted[n] = true end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and wanted[d.Name] then
			if found[d.Name] then error(("duplicate imported part %q under %s"):format(d.Name, root:GetFullName())) end
			found[d.Name] = d
		end
	end
	for _, n in ipairs(names) do if not found[n] then missing[#missing + 1] = n end end
	if #missing > 0 then error("missing imported parts: " .. table.concat(missing, ", ")) end
	return found
end

local function flags(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

-- Builds one template. Throws on any problem; the caller restores the imported parts.
function M.AssembleOne(root, name, entry, opts)
	opts = opts or {}
	local tile = opts.tile ~= false
	local parts = findParts(root, entry.parts)
	local model = Instance.new("Model")
	model.Name = name
	for _, partName in ipairs(entry.parts) do
		local role = partName:sub(#name + 3) -- strip "<name>__"
		local p = parts[partName]
		assert(entry.roles[role], ("manifest has no colour for role %q"):format(role))
		p.Name = role
		p.Color = hexToColor3(entry.roles[role])
		if p:IsA("MeshPart") then
			-- PluginSecurity write: fine from the command bar / MCP; never touch RenderFidelity here
			local okCF = pcall(function() p.CollisionFidelity = Enum.CollisionFidelity.Box end)
			if not okCF then warn("BrainrotForge: could not set CollisionFidelity on " .. partName .. " (set it by hand in Properties)") end
		end
		if tile then
			p.Material = Enum.Material.Plastic       -- BrainrotTile.BaseMaterial; a variant is ignored on any other Material
			p.MaterialVariant = M.TILE_VARIANT
		else
			p.Material = Enum.Material.SmoothPlastic
			p.MaterialVariant = ""
		end
		flags(p)
		for _, child in ipairs(p:GetChildren()) do child:Destroy() end -- the importer adds nothing we want
		p.Parent = model
	end
	if opts.turn180 then
		-- Roblox's glTF importer turns a model 180 degrees about Y (glTF is +Z-forward, Roblox is
		-- -Z-forward). Batches exported before the forge pre-turned them arrive facing +Z; this undoes it
		-- about the group's own centre so the face ends up at -Z where BrainrotThumb/the reveal look.
		local c = model:GetBoundingBox().Position
		local turn = CFrame.new(c) * CFrame.Angles(0, math.pi, 0) * CFrame.new(-c)
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") then p.CFrame = turn * p.CFrame end
		end
	end
	local cf, size = model:GetBoundingBox()
	local rootPart = Instance.new("Part")
	rootPart.Name = "RootPart"
	rootPart.Size = size
	rootPart.CFrame = cf
	rootPart.Transparency = 1
	flags(rootPart)
	rootPart.Parent = model
	model.PrimaryPart = rootPart
	model:SetAttribute("HeightScale", entry.heightScale or 1)
	model:SetAttribute("WidthScale", entry.widthScale or 1)
	if entry.fx and opts.fx ~= false then
		local FX = loadModule(ReplicatedStorage.Modules.BrainrotFX)
		local n = FX.apply(model, entry.rarity)
		if n == 0 then warn(("BrainrotForge: %s has fx in its manifest but BrainrotFX.RECIPES has no row for it (add the recipe, then FX.apply again)"):format(name)) end
	end
	return model
end

function M.Assemble(root, manifestJson, opts)
	opts = opts or {}
	local manifest = HttpService:JSONDecode(manifestJson)
	local folder = ReplicatedStorage:FindFirstChild(M.TARGET_FOLDER) or error("ReplicatedStorage." .. M.TARGET_FOLDER .. " missing")
	local models, errors = {}, {}
	local names = {}
	for name in pairs(manifest.models) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local entry = manifest.models[name]
		local existing = folder:FindFirstChild(name)
		if existing and not opts.replace then
			errors[name] = "a template named " .. name .. " already exists; pass { replace = true } to back it up and replace"
		else
			-- remember the imported parts so a failure can put them back exactly as they were
			local originals = {}
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") then originals[#originals + 1] = { part = d, name = d.Name, parent = d.Parent } end
			end
			local ok, result = pcall(M.AssembleOne, root, name, entry, opts)
			if ok then
				if existing then
					local backups = ServerStorage:FindFirstChild(M.BACKUP_FOLDER) or Instance.new("Folder")
					backups.Name = M.BACKUP_FOLDER
					backups.Parent = ServerStorage
					existing.Name = ("BrainrotForge_%s_%s"):format(name, os.date("%Y-%m-%d"))
					existing.Parent = backups
				end
				result.Parent = folder
				models[name] = result
				print(("BrainrotForge: assembled %s (%d parts)"):format(name, #entry.parts + 1))
			else
				for _, o in ipairs(originals) do
					if o.part.Parent ~= o.parent then o.part.Name = o.name; o.part.Parent = o.parent end
				end
				errors[name] = tostring(result)
				warn("BrainrotForge: " .. name .. " FAILED: " .. tostring(result))
			end
		end
	end
	local budget = ServerStorage:FindFirstChild("BrainrotBudget")
	if budget then
		local B = loadModule(budget)
		for _, name in ipairs(names) do if models[name] then print(B.review(models[name])) end end
	end
	return models, errors
end

return M
