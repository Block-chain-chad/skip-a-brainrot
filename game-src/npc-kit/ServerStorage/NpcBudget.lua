--[[ ServerStorage.NpcBudget -- the gate every NPC-01 model runs through (Phase 2.5 doc F).

    local B = require(game.ServerStorage.NpcBudget)
    local r = B.report(model)                 -- counts
    local review = B.review(model, tier, kind) -- PASS / WARN / FAIL per row, review.pass

Same shape as BrainrotBudget (docs/brainrot-build-standard.md §3), with the NPC rows:
orphan parts (a non-anchored part with no joint/weld path to an anchored root),
face parts, overlays, props, Motor6D, collider rules, CanQuery / CanTouch.
Build-time only; NpcForge calls it and refuses to stage a FAIL.
]]

local NpcBudget = {}
NpcBudget.Version = 1

-- ===== limits (doc F1) =======================================================
NpcBudget.Limits = {
	human = {
		[1] = { baseParts = 30, bespokeMeshes = 0, triangles = 5000, motor6d = 22, welds = 8, attachments = 16, emitters = 0, lights = 0, neon = 0, descendants = 90 },
		[2] = { baseParts = 38, bespokeMeshes = 3, triangles = 9000, motor6d = 22, welds = 14, attachments = 18, emitters = 2, lights = 1, neon = 1, descendants = 110 },
		[3] = { baseParts = 50, bespokeMeshes = 8, triangles = 16000, motor6d = 27, welds = 24, attachments = 20, emitters = 6, lights = 1, neon = 2, descendants = 140 },
	},
	creature = {
		[1] = { storyParts = 4, baseParts = 24, triangles = 9000, emitters = 0, lights = 0, neon = 2, descendants = 80 },
		[2] = { storyParts = 6, baseParts = 26, triangles = 12000, emitters = 2, lights = 0, neon = 2, descendants = 90 },
		[3] = { storyParts = 8, baseParts = 28, triangles = 16000, emitters = 6, lights = 1, neon = 2, descendants = 100 },
	},
}
-- always-fail rows regardless of tier
NpcBudget.Hard = { scripts = 0, humanoids = 0, constraints = 0, highlights = 0, unions = 0, canQuery = 0, canTouch = 0, canCollideMax = 1, orphans = 0 }

local function isAnchoredRoot(p) return p:IsA("BasePart") and p.Anchored end

-- parts reachable from an anchored part through joints/welds (either direction)
local function connectedToAnchor(model)
	local adj = {}
	local function link(a, b)
		if not (a and b) then return end
		adj[a] = adj[a] or {}; adj[b] = adj[b] or {}
		adj[a][b] = true; adj[b][a] = true
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then link(d.Part0, d.Part1) end
	end
	local seen, stack = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if isAnchoredRoot(d) then seen[d] = true; stack[#stack + 1] = d end
	end
	while #stack > 0 do
		local p = table.remove(stack)
		for q in pairs(adj[p] or {}) do
			if not seen[q] then seen[q] = true; stack[#stack + 1] = q end
		end
	end
	return seen
end

function NpcBudget.report(model)
	local r = {
		baseParts = 0, meshParts = 0, parts = 0, unions = 0, motor6d = 0, welds = 0, attachments = 0, orphans = 0,
		anchored = 0, humanoids = 0, animationControllers = 0, animators = 0, faceParts = 0, overlays = 0, props = 0, storyParts = 0,
		lights = 0, emitters = 0, highlights = 0, beams = 0, trails = 0, scripts = 0, decals = 0, textures = 0, surfaceAppearances = 0,
		neon = 0, transparentParts = 0, canCollide = 0, canQuery = 0, canTouch = 0, constraints = 0, sounds = 0,
		descendants = 0, hasPrimaryPart = model.PrimaryPart ~= nil, tag = false, triangles = nil, trianglesEstimated = 0,
		bespokeMeshes = 0,
	}
	local connected = connectedToAnchor(model)
	local descendants = model:GetDescendants()
	r.descendants = #descendants
	for _, d in ipairs(descendants) do
		if d:IsA("BasePart") then
			r.baseParts = r.baseParts + 1
			if d:IsA("MeshPart") then r.meshParts = r.meshParts + 1 elseif d:IsA("UnionOperation") then r.unions = r.unions + 1 else r.parts = r.parts + 1 end
			if d.Anchored then r.anchored = r.anchored + 1 elseif not connected[d] then r.orphans = r.orphans + 1 end
			if d.Material == Enum.Material.Neon then r.neon = r.neon + 1 end
			if d.Transparency > 0 and d.Transparency < 1 then r.transparentParts = r.transparentParts + 1 end
			if d.CanCollide then r.canCollide = r.canCollide + 1 end
			if d.CanQuery then r.canQuery = r.canQuery + 1 end
			if d.CanTouch then r.canTouch = r.canTouch + 1 end
			local parent = d.Parent
			local pname = parent and parent.Name or ""
			if pname == "Face" then r.faceParts = r.faceParts + 1
			elseif pname == "Outfit" or pname == "Hair" then r.overlays = r.overlays + 1
			elseif pname == "Props" then r.props = r.props + 1 end
			if d:GetAttribute("NpcStoryLayer") then r.storyParts = r.storyParts + 1 end
			if d:GetAttribute("NpcBespoke") then r.bespokeMeshes = r.bespokeMeshes + 1 end
			local tris = d:GetAttribute("Tris")
			if tris then r.trianglesEstimated = r.trianglesEstimated + tris end
		elseif d:IsA("Motor6D") then r.motor6d = r.motor6d + 1
		elseif d:IsA("WeldConstraint") or d:IsA("Weld") then r.welds = r.welds + 1
		elseif d:IsA("Attachment") then r.attachments = r.attachments + 1
		elseif d:IsA("Humanoid") then r.humanoids = r.humanoids + 1
		elseif d:IsA("AnimationController") then r.animationControllers = r.animationControllers + 1
		elseif d:IsA("Animator") then r.animators = r.animators + 1
		elseif d:IsA("Light") then r.lights = r.lights + 1
		elseif d:IsA("ParticleEmitter") then r.emitters = r.emitters + 1
		elseif d:IsA("Highlight") then r.highlights = r.highlights + 1
		elseif d:IsA("Beam") then r.beams = r.beams + 1
		elseif d:IsA("Trail") then r.trails = r.trails + 1
		elseif d:IsA("LuaSourceContainer") then r.scripts = r.scripts + 1
		elseif d:IsA("Decal") then r.decals = r.decals + 1
		elseif d:IsA("Texture") then r.textures = r.textures + 1
		elseif d:IsA("SurfaceAppearance") then r.surfaceAppearances = r.surfaceAppearances + 1
		elseif d:IsA("Constraint") then r.constraints = r.constraints + 1
		elseif d:IsA("Sound") then r.sounds = r.sounds + 1
		end
	end
	local ok, tagged = pcall(function() return game:GetService("CollectionService"):HasTag(model, "NpcBody") end)
	r.tag = ok and tagged or false
	return r
end

local function row(rows, name, value, limit)
	local status = "PASS"
	if limit ~= nil and value > limit then status = "FAIL" end
	rows[#rows + 1] = { name = name, value = value, limit = limit, status = status }
	return status
end

-- Blockout builds (primitive pieces standing in for meshes, NpcBlockout = true
-- on the root) get a bounded allowance on the instance rows and a WARN row
-- saying so; the mesh build must pass the real caps.
NpcBudget.BlockoutAllowance = { baseParts = 1.3, welds = 1.3, descendants = 1.2 }

-- review(model, tier, kind) -> { pass = bool, rows = {...}, report = r }
function NpcBudget.review(model, tier, kind)
	kind = kind or "human"
	tier = tier or 2
	local base = NpcBudget.Limits[kind][tier] or NpcBudget.Limits[kind][2]
	local L = {}
	for k, v in pairs(base) do L[k] = v end
	local blockout = model:GetAttribute("NpcBlockout") == true
	if blockout then
		for k, mult in pairs(NpcBudget.BlockoutAllowance) do
			if L[k] then L[k] = math.floor(L[k] * mult + 0.5) end
		end
	end
	local H = NpcBudget.Hard
	local r = NpcBudget.report(model)
	local rows = {}
	local pass = true
	if blockout then rows[#rows + 1] = { name = "blockout allowance", value = 1, limit = 0, status = "WARN" } end
	local function check(name, value, limit)
		if row(rows, name, value, limit) == "FAIL" then pass = false end
	end
	check("baseParts", r.baseParts, L.baseParts)
	check("descendants", r.descendants, L.descendants)
	check("emitters", r.emitters, L.emitters)
	check("lights", r.lights, L.lights)
	check("neon", r.neon, L.neon)
	if L.motor6d then check("motor6d", r.motor6d, L.motor6d) end
	if L.welds then check("welds", r.welds, L.welds) end
	if L.attachments then check("attachments", r.attachments, L.attachments) end
	if L.storyParts then check("storyParts", r.storyParts, L.storyParts) end
	if L.bespokeMeshes then check("bespokeMeshes", r.bespokeMeshes, L.bespokeMeshes) end
	if r.trianglesEstimated > 0 then check("trianglesEstimated", r.trianglesEstimated, L.triangles) end
	check("scripts", r.scripts, H.scripts)
	check("humanoids", r.humanoids, H.humanoids)
	check("constraints", r.constraints, H.constraints)
	check("highlights", r.highlights, H.highlights)
	check("unions", r.unions, H.unions)
	check("canQuery", r.canQuery, H.canQuery)
	check("canTouch", r.canTouch, H.canTouch)
	check("canCollide", r.canCollide, H.canCollideMax)
	check("orphans", r.orphans, H.orphans)
	-- structural musts
	if not r.hasPrimaryPart then rows[#rows + 1] = { name = "primaryPart", value = 0, limit = 1, status = "FAIL" }; pass = false end
	if not r.tag then rows[#rows + 1] = { name = "tag NpcBody", value = 0, limit = 1, status = "FAIL" }; pass = false end
	if kind == "human" then
		if r.faceParts < 7 then rows[#rows + 1] = { name = "faceParts", value = r.faceParts, limit = 7, status = "FAIL" }; pass = false end
		if r.animationControllers ~= 1 then rows[#rows + 1] = { name = "animationController", value = r.animationControllers, limit = 1, status = "FAIL" }; pass = false end
	end
	return { pass = pass, rows = rows, report = r }
end

function NpcBudget.print(review)
	print(("NpcBudget: %s"):format(review.pass and "PASS" or "FAIL"))
	for _, row2 in ipairs(review.rows) do
		print(("  %-22s %6s / %-6s %s"):format(row2.name, tostring(row2.value), tostring(row2.limit), row2.status))
	end
end

return NpcBudget
