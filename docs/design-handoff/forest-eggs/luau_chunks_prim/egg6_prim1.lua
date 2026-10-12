-- egg primitive chunk (auto-generated, save-proof native geometry)
local staging = game.ServerStorage:FindFirstChild("EggPrimStaging")
if not staging then
	staging = Instance.new("Folder")
	staging.Name = "EggPrimStaging"
	staging.Parent = game.ServerStorage
end
local built = 0
local function prim(eggName, partName, shape, sx, sy, sz, r, g, b, cx, cy, cz)
	local p = Instance.new("Part")
	p.Name = partName
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.new(r, g, b)
	local rot = CFrame.new()
	if shape == "egg" or shape == "ball" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	elseif shape == "rod" then
		-- CylinderMesh is Y-up; rotate so Y follows the longest extent
		local m = Instance.new("CylinderMesh")
		m.Parent = p
		if sx >= sy and sx >= sz then
			rot = CFrame.Angles(0, 0, math.rad(90)); sx, sy = sy, sx
		elseif sz >= sy and sz >= sx then
			rot = CFrame.Angles(math.rad(90), 0, 0); sz, sy = sy, sz
		end
	elseif shape == "band" then
		-- shell-hugging ellipsoid band: inflate the two large axes slightly so
		-- it sits just proud of the shell; the small axis is the band height
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
		sx, sz = sx * 1.04, sz * 1.04
	elseif shape == "ringseg" then
		-- segmented circle of 10 small blocks (primitives cannot make holes);
		-- ring plane = the two largest extents, tube = the smallest
		local ax = { { sx, "x" }, { sy, "y" }, { sz, "z" } }
		table.sort(ax, function(a, b) return a[1] > b[1] end)
		local radius = (ax[1][1] + ax[2][1]) / 4
		local tube = math.max(ax[3][1], 0.06)
		local plane = ax[3][2]  -- axis perpendicular to the ring plane
		local segs = 10
		local segLen = 2 * math.pi * radius / segs * 1.15
		for k = 1, segs do
			local a = (k / segs) * 2 * math.pi
			local px, py, pz, r0
			if plane == "y" then
				px, py, pz = math.cos(a) * radius, 0, math.sin(a) * radius
				r0 = CFrame.Angles(0, -a, 0)
			elseif plane == "z" then
				px, py, pz = math.cos(a) * radius, math.sin(a) * radius, 0
				r0 = CFrame.Angles(0, 0, a)
			else
				px, py, pz = 0, math.cos(a) * radius, math.sin(a) * radius
				r0 = CFrame.Angles(a, 0, 0)
			end
			local seg = Instance.new("Part")
			seg.Name = partName .. "_s" .. k
			seg.Anchored = true; seg.CanCollide = false; seg.CanQuery = false; seg.CastShadow = false
			seg.TopSurface = Enum.SurfaceType.Smooth; seg.BottomSurface = Enum.SurfaceType.Smooth
			seg.Material = Enum.Material.SmoothPlastic
			seg.Color = Color3.new(r, g, b)
			seg.Size = Vector3.new(segLen, tube, tube)
			seg.CFrame = CFrame.new(cx + px, cy + py, cz + pz) * r0
			local eggModel = staging:FindFirstChild(eggName)
			if not eggModel then
				eggModel = Instance.new("Model"); eggModel.Name = eggName; eggModel.Parent = staging
			end
			seg.Parent = eggModel
		end
		built += 1
		return
	end
	p.Size = Vector3.new(math.max(sx, 0.05), math.max(sy, 0.05), math.max(sz, 0.05))
	p.CFrame = CFrame.new(cx, cy, cz) * rot
	local eggModel = staging:FindFirstChild(eggName)
	if not eggModel then
		eggModel = Instance.new("Model")
		eggModel.Name = eggName
		eggModel.Parent = staging
	end
	p.Parent = eggModel
	built += 1
end
prim("ForestEgg1", "shell_body_1", "egg", 0.940,1.200,0.940, 0.0284,0.2122,0.0685, -0.700,0.600,0.560)
prim("ForestEgg1", "stripe_1_2", "block", 0.096,1.184,0.439, 0.2747,0.6939,0.1441, -0.652,0.605,0.815)
prim("ForestEgg1", "stripe_2_3", "block", 0.371,1.184,0.316, 0.2747,0.6939,0.1441, -0.489,0.605,0.738)
prim("ForestEgg1", "stripe_3_4", "block", 0.439,1.184,0.096, 0.2747,0.6939,0.1441, -0.445,0.605,0.512)
prim("ForestEgg1", "stripe_4_5", "block", 0.316,1.184,0.371, 0.2747,0.6939,0.1441, -0.523,0.605,0.349)
prim("ForestEgg1", "stripe_5_6", "block", 0.096,1.184,0.439, 0.2747,0.6939,0.1441, -0.749,0.605,0.305)
prim("ForestEgg1", "stripe_6_7", "block", 0.371,1.184,0.316, 0.2747,0.6939,0.1441, -0.912,0.605,0.383)
prim("ForestEgg1", "stripe_7_8", "block", 0.439,1.184,0.096, 0.2747,0.6939,0.1441, -0.955,0.605,0.608)
prim("ForestEgg1", "stripe_8_9", "block", 0.316,1.184,0.371, 0.2747,0.6939,0.1441, -0.878,0.605,0.772)
prim("ForestEgg1", "stud_1_10", "ball", 0.051,0.064,0.064, 0.8070,0.9301,0.4342, -0.236,0.451,0.560)
prim("ForestEgg1", "stud_2_11", "ball", 0.054,0.062,0.059, 0.8070,0.9301,0.4342, -0.299,0.451,0.792)
prim("ForestEgg1", "stud_3_12", "ball", 0.059,0.062,0.054, 0.8070,0.9301,0.4342, -0.468,0.451,0.962)
prim("ForestEgg1", "stud_4_13", "ball", 0.064,0.064,0.051, 0.8070,0.9301,0.4342, -0.700,0.451,1.024)
prim("ForestEgg1", "stud_5_14", "ball", 0.059,0.062,0.054, 0.8070,0.9301,0.4342, -0.932,0.451,0.962)
prim("ForestEgg1", "stud_6_15", "ball", 0.054,0.062,0.059, 0.8070,0.9301,0.4342, -1.102,0.451,0.792)
prim("ForestEgg1", "stud_7_16", "ball", 0.051,0.064,0.064, 0.8070,0.9301,0.4342, -1.165,0.451,0.560)
prim("ForestEgg1", "stud_8_17", "ball", 0.054,0.062,0.059, 0.8070,0.9301,0.4342, -1.102,0.451,0.328)
prim("ForestEgg1", "stud_9_18", "ball", 0.059,0.062,0.054, 0.8070,0.9301,0.4342, -0.932,0.451,0.158)
prim("ForestEgg1", "stud_10_19", "ball", 0.064,0.064,0.051, 0.8070,0.9301,0.4342, -0.700,0.451,0.096)
prim("ForestEgg1", "stud_11_20", "ball", 0.059,0.062,0.054, 0.8070,0.9301,0.4342, -0.468,0.451,0.158)
prim("ForestEgg1", "stud_12_21", "ball", 0.054,0.062,0.059, 0.8070,0.9301,0.4342, -0.299,0.451,0.328)
prim("ForestEgg1", "shard_1_22", "block", 0.146,0.128,0.146, 0.8070,0.9301,0.4342, -1.125,0.720,0.984)
prim("ForestEgg1", "shard_2_23", "block", 0.122,0.117,0.125, 0.8070,0.9301,0.4342, -1.235,0.918,0.287)
prim("ForestEgg1", "shard_3_24", "block", 0.103,0.099,0.105, 0.8070,0.9301,0.4342, -0.606,0.669,-0.032)
prim("ForestEgg1", "shard_4_25", "block", 0.131,0.149,0.136, 0.8070,0.9301,0.4342, -0.108,0.535,0.467)
prim("ForestEgg1", "shard_5_26", "block", 0.121,0.114,0.110, 0.8070,0.9301,0.4342, -0.429,0.819,1.095)
return "built " .. built
