--[[ ServerStorage.BrainrotBudget -- BUILD-TIME performance/build gate for brainrot templates.

Standard: docs/brainrot-build-standard.md (section 2.1 caps, section 3 report). The baseline is
the 148 imported .glb pack models, measured 2026-09-17 (p50 / p90). Never required by game code;
run from the command bar / MCP in Edit mode:

    local B = require(game.ServerStorage.BrainrotBudget:Clone())
    print(B.review(game.ReplicatedStorage.BrainrotModels["Nonno Ghiacciaio"]))
    print(B.compareMany({ modelA, modelB, ... }))       -- side-by-side columns
    print(game:GetService("HttpService"):JSONEncode(B.baseline(folder, predicate)))

Verdicts: PASS <= typical, WARN <= max, FAIL above max or any forbidden object present.
]]
local RunService = game:GetService("RunService")

local M = {}

-- pack p50 / p90, 148 rigged-mesh models, 2026-09-17 (standard section 1.2)
M.BASELINE = {
	baseParts = { p50 = 11, p90 = 19 }, visibleParts = { p50 = 8, p90 = 14 }, invisibleParts = { p50 = 3, p90 = 6 },
	meshParts = { p50 = 8, p90 = 14 }, descendants = { p50 = 57, p90 = 111 },
	particleEmitters = { p50 = 4, p90 = 16 }, particlesAlive = { p50 = 43, p90 = 152 },
	surfaceAppearances = { p50 = 1, p90 = 1 }, neonParts = { p50 = 0, p90 = 0 },
	attachments = { p50 = 29, p90 = 52 }, beams = { p50 = 0, p90 = 0 }, transparentParts = { p50 = 0, p90 = 0 },
}
-- standard section 2.1: typical (PASS) and max (WARN up to, FAIL above)
M.RANGES = {
	{ key = "baseParts", typical = 15, max = 20 }, { key = "visibleParts", typical = 11, max = 14 },
	{ key = "invisibleParts", typical = 3, max = 4 }, { key = "meshParts", typical = 11, max = 14 },   -- 4 = RootPart + the three BrainrotFX hosts (2.4)
	{ key = "descendants", typical = 60, max = 80 }, { key = "particleEmitters", typical = 6, max = 8 },
	{ key = "particlesAlive", typical = 80, max = 100 }, { key = "attachments", typical = 6, max = 8 },
	{ key = "surfaceAppearances", typical = 1, max = 1 }, { key = "beams", typical = 0, max = 2 },
	{ key = "neonParts", typical = 0, max = 3 }, { key = "transparentParts", typical = 0, max = 1 },
}
M.FORBIDDEN = { "unions", "trails", "lights", "highlights", "scripts", "localScripts", "moduleScripts", "motor6d",
	"bones", "welds", "constraints", "humanoids", "animationControllers", "sounds", "billboardGuis", "surfaceGuis",
	"decals", "textures", "textureIds", "canCollideParts", "surfaceAppearanceMaps" }
M.ALLOWED_MATERIALS = { Plastic = true, SmoothPlastic = true, Neon = true }

local COUNTERS = { "descendants", "baseParts", "visibleParts", "invisibleParts", "meshParts", "parts", "unions", "wedges",
	"attachments", "bones", "motor6d", "welds", "weldConstraints", "constraints", "particleEmitters", "particlesAlive",
	"trails", "beams", "lights", "highlights", "scripts", "localScripts", "moduleScripts", "decals", "textures",
	"textureIds", "surfaceAppearances", "surfaceAppearanceMaps", "materialVariants", "neonParts", "transparentParts",
	"canCollideParts", "unanchoredParts", "castShadowParts", "sounds", "billboardGuis", "surfaceGuis", "humanoids",
	"animationControllers", "uniqueMeshIds", "other" }

function M.report(model)
	local r = { name = model.Name, className = model.ClassName, materials = {},
		hasPrimaryPart = model:IsA("Model") and model.PrimaryPart ~= nil, attributes = model:GetAttributes() }
	for _, k in ipairs(COUNTERS) do r[k] = 0 end
	local meshIds = {}
	for _, d in ipairs(model:GetDescendants()) do
		r.descendants += 1
		if d:IsA("BasePart") then
			r.baseParts += 1
			if d.Transparency >= 1 then r.invisibleParts += 1 else
				r.visibleParts += 1
				if d.Transparency > 0 then r.transparentParts += 1 end
			end
			if d.Material == Enum.Material.Neon then r.neonParts += 1 end
			if d.MaterialVariant ~= "" then r.materialVariants += 1 end
			if d.CanCollide then r.canCollideParts += 1 end
			if not d.Anchored then r.unanchoredParts += 1 end
			if d.CastShadow then r.castShadowParts += 1 end
			r.materials[d.Material.Name] = (r.materials[d.Material.Name] or 0) + 1
			if d:IsA("MeshPart") then
				r.meshParts += 1
				meshIds[d.MeshId] = true
				if d.TextureID ~= "" then r.textureIds += 1 end
			elseif d:IsA("UnionOperation") then r.unions += 1
			elseif d:IsA("WedgePart") or d:IsA("CornerWedgePart") then r.wedges += 1
			elseif d:IsA("Part") then r.parts += 1 end
		elseif d:IsA("Bone") then r.bones += 1              -- Bone IsA Attachment: test first
		elseif d:IsA("Attachment") then r.attachments += 1
		elseif d:IsA("ParticleEmitter") then
			r.particleEmitters += 1
			r.particlesAlive += d.Rate * (d.Lifetime.Min + d.Lifetime.Max) * 0.5
		elseif d:IsA("Trail") then r.trails += 1
		elseif d:IsA("Beam") then r.beams += 1
		elseif d:IsA("Light") then r.lights += 1
		elseif d:IsA("Highlight") then r.highlights += 1
		elseif d:IsA("LocalScript") then r.localScripts += 1
		elseif d:IsA("ModuleScript") then r.moduleScripts += 1
		elseif d:IsA("Script") then r.scripts += 1
		elseif d:IsA("Texture") then r.textures += 1           -- Texture IsA Decal: test first
		elseif d:IsA("Decal") then r.decals += 1
		elseif d:IsA("SurfaceAppearance") then
			r.surfaceAppearances += 1
			for _, map in ipairs({ d.NormalMap, d.MetalnessMap, d.RoughnessMap }) do
				if map ~= "" then r.surfaceAppearanceMaps += 1 end
			end
		elseif d:IsA("Motor6D") then r.motor6d += 1
		elseif d:IsA("WeldConstraint") then r.weldConstraints += 1
		elseif d:IsA("JointInstance") then r.welds += 1
		elseif d:IsA("Constraint") then r.constraints += 1
		elseif d:IsA("Sound") then r.sounds += 1
		elseif d:IsA("BillboardGui") then r.billboardGuis += 1
		elseif d:IsA("SurfaceGui") then r.surfaceGuis += 1
		elseif d:IsA("Humanoid") then r.humanoids += 1
		elseif d:IsA("AnimationController") then r.animationControllers += 1
		else r.other += 1 end
	end
	for _ in pairs(meshIds) do r.uniqueMeshIds += 1 end
	r.particlesAlive = math.floor(r.particlesAlive + 0.5)
	return r
end

local function worst(a, b)
	local rank = { PASS = 1, WARN = 2, FAIL = 3 }
	return rank[b] > rank[a] and b or a
end

function M.compare(model)
	local r = M.report(model)
	local rows, verdict = {}, "PASS"
	for _, range in ipairs(M.RANGES) do
		local v = r[range.key]
		local b = M.BASELINE[range.key] or {}
		local vd = (v <= range.typical) and "PASS" or (v <= range.max and "WARN" or "FAIL")
		verdict = worst(verdict, vd)
		rows[#rows + 1] = { key = range.key, value = v, p50 = b.p50, p90 = b.p90, typical = range.typical, max = range.max, verdict = vd }
	end
	for _, key in ipairs(M.FORBIDDEN) do
		local v = r[key]
		local vd = v > 0 and "FAIL" or "PASS"
		verdict = worst(verdict, vd)
		rows[#rows + 1] = { key = key, value = v, p50 = 0, p90 = 0, typical = 0, max = 0, verdict = vd }
	end
	for mat, n in pairs(r.materials) do
		if not M.ALLOWED_MATERIALS[mat] then
			verdict = "FAIL"
			rows[#rows + 1] = { key = "material:" .. mat, value = n, p50 = 0, p90 = 0, typical = 0, max = 0, verdict = "FAIL" }
		end
	end
	if not r.hasPrimaryPart then
		verdict = "FAIL"
		rows[#rows + 1] = { key = "PrimaryPart", value = 0, p50 = 1, p90 = 1, typical = 1, max = 1, verdict = "FAIL" }
	end
	return { report = r, rows = rows, verdict = verdict }
end

local function pad(s, n) s = tostring(s) return s .. string.rep(" ", math.max(0, n - #s)) end

function M.review(model)
	local c = M.compare(model)
	local r = c.report
	local out = { ("BrainrotBudget review: %s  [%s]"):format(model.Name, c.verdict),
		pad("metric", 24) .. pad("value", 8) .. pad("pack p50", 10) .. pad("pack p90", 10) .. pad("typical", 9) .. pad("max", 6) .. "verdict" }
	for _, row in ipairs(c.rows) do
		out[#out + 1] = pad(row.key, 24) .. pad(row.value, 8) .. pad(row.p50 or "-", 10) .. pad(row.p90 or "-", 10) .. pad(row.typical, 9) .. pad(row.max, 6) .. row.verdict
	end
	local within = true
	for _, row in ipairs(c.rows) do if row.p90 and row.value > row.p90 then within = false end end
	local function yn(b) return b and "yes" or "NO" end
	out[#out + 1] = ""
	out[#out + 1] = "1. Object count reasonable?        " .. yn(r.baseParts <= 20 and r.descendants <= 80)
	out[#out + 1] = "2. Geometry complexity reasonable? " .. yn(r.meshParts <= 14) .. " (triangles: run BrainrotBudget.triangles with Studio focused)"
	out[#out + 1] = "3. Texture/material use reasonable?" .. yn(r.textureIds == 0 and r.surfaceAppearances <= 1 and r.surfaceAppearanceMaps == 0 and r.neonParts <= 3)
	out[#out + 1] = "4. No unnecessary runtime effects? " .. yn(r.particleEmitters <= 8 and r.particlesAlive <= 100 and r.trails == 0 and r.lights == 0 and r.beams <= 2)
	out[#out + 1] = "5. No scripts?                     " .. yn(r.scripts + r.localScripts + r.moduleScripts == 0)
	out[#out + 1] = "6. No physics?                     " .. yn(r.constraints + r.motor6d + r.welds + r.humanoids + r.canCollideParts == 0)
	out[#out + 1] = "7. Profile within pack p90?        " .. yn(within)
	out[#out + 1] = "8. Visually belongs?               HUMAN CHECK (Play mode, 20-60 studs from a pad)"
	out[#out + 1] = "9. Completely original?            HUMAN CHECK (name/concept vs both rosters + lexicon)"
	return table.concat(out, "\n")
end

function M.compareMany(models)
	local keys = { "baseParts", "visibleParts", "meshParts", "descendants", "particleEmitters", "particlesAlive",
		"attachments", "bones", "motor6d", "surfaceAppearances", "neonParts", "beams", "trails", "lights", "scripts" }
	local reports = {}
	for i, m in ipairs(models) do reports[i] = M.report(m) end
	local lines = { pad("metric", 20) }
	for _, r in ipairs(reports) do lines[1] = lines[1] .. pad(r.name:sub(1, 16), 18) end
	for _, k in ipairs(keys) do
		local line = pad(k, 20)
		for _, r in ipairs(reports) do line = line .. pad(r[k], 18) end
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

-- Percentiles over a folder so BASELINE can be refreshed. predicate(model) -> bool selects the population
-- (pack = has a MeshPart AND a Motor6D; voxel = no MeshPart).
function M.baseline(folder, predicate)
	local reports = {}
	for _, m in ipairs(folder:GetChildren()) do
		if not predicate or predicate(m) then reports[#reports + 1] = M.report(m) end
	end
	local out = { n = #reports }
	for _, k in ipairs(COUNTERS) do
		local v = {}
		for i, r in ipairs(reports) do v[i] = r[k] end
		table.sort(v)
		local n = #v
		local function q(x) return n > 0 and v[math.max(1, math.min(n, math.ceil(x * n)))] or 0 end
		out[k] = { min = v[1] or 0, p50 = q(0.5), p75 = q(0.75), p90 = q(0.9), max = v[n] or 0 }
	end
	return out
end

-- Opaque triangles of this model alone, fitted to 6 studs, minus an empty-sky baseline. Needs Studio
-- to be RENDERING (window focused/visible); returns nil + reason when the counter is frozen.
function M.triangles(model)
	local SceneAnalysisService = game:GetService("SceneAnalysisService")
	local cam = workspace.CurrentCamera
	local savedCF, savedType = cam.CFrame, cam.CameraType
	local function opaque()
		local res = SceneAnalysisService:GetTriangleCompositionAsync()
		for _, c in ipairs(res.Children) do if c.Name == "Opaque" then return c.Sizes.Triangles, c.Sizes.Drawcalls end end
		return 0, 0
	end
	local site = Vector3.new(0, 4000, 0)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(site + Vector3.new(0, 3, 20), site)
	for _ = 1, 10 do RunService.RenderStepped:Wait() end
	local base = opaque()
	local clone = model:Clone()
	for _, d in ipairs(clone:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end
	clone.Parent = workspace
	local _, ext = clone:GetBoundingBox()
	if ext.Y > 0 then clone:ScaleTo(clone:GetScale() * (6 / ext.Y)) end
	local bcf = clone:GetBoundingBox()
	clone:PivotTo(clone:GetPivot() + (site - bcf.Position))
	for _ = 1, 15 do RunService.RenderStepped:Wait() end
	local withModel, drawcalls = opaque()
	clone:Destroy()
	cam.CameraType = savedType
	cam.CFrame = savedCF
	if withModel == base then
		return nil, "render counters did not change: Studio is not rendering (focus the 3D viewport) or the model drew nothing"
	end
	return withModel - base, ("drawcalls=%d"):format(drawcalls)
end

return M
