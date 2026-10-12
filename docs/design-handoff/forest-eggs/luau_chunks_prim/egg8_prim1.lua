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
prim("ForestEgg3", "shell_body_1", "egg", 0.940,1.200,0.940, 0.0176,0.0782,0.0307, 1.692,0.600,-1.354)
prim("ForestEgg3", "stripe_1_2", "block", 0.118,1.184,0.439, 0.0497,0.2747,0.0595, 1.751,0.605,-1.099)
prim("ForestEgg3", "stripe_2_3", "block", 0.439,1.184,0.144, 0.0497,0.2747,0.0595, 1.946,0.605,-1.279)
prim("ForestEgg3", "stripe_3_4", "block", 0.266,1.184,0.412, 0.0497,0.2747,0.0595, 1.838,0.605,-1.589)
prim("ForestEgg3", "stripe_4_5", "block", 0.344,1.184,0.361, 0.0497,0.2747,0.0595, 1.499,0.605,-1.557)
prim("ForestEgg3", "stripe_5_6", "block", 0.421,1.184,0.243, 0.0497,0.2747,0.0595, 1.451,0.605,-1.221)
prim("ForestEgg3", "spike_1_7", "rod", 0.201,0.146,0.110, 0.2080,0.1690,0.1280, 2.164,0.699,-1.354)
prim("ForestEgg3", "spike_2_8", "rod", 0.153,0.146,0.174, 0.2080,0.1690,0.1280, 1.973,0.699,-0.993)
prim("ForestEgg3", "spike_3_9", "rod", 0.107,0.145,0.198, 0.2080,0.1690,0.1280, 1.604,0.700,-0.895)
prim("ForestEgg3", "spike_4_10", "rod", 0.189,0.144,0.125, 0.2080,0.1690,0.1280, 1.271,0.701,-1.168)
prim("ForestEgg3", "spike_5_11", "rod", 0.189,0.144,0.125, 0.2080,0.1690,0.1280, 1.271,0.701,-1.539)
prim("ForestEgg3", "spike_6_12", "rod", 0.107,0.145,0.198, 0.2080,0.1690,0.1280, 1.604,0.700,-1.813)
prim("ForestEgg3", "spike_7_13", "rod", 0.153,0.146,0.174, 0.2080,0.1690,0.1280, 1.973,0.699,-1.714)
prim("ForestEgg3", "horn_1_14", "rod", 0.136,0.246,0.120, 0.2080,0.1690,0.1280, 1.862,1.191,-1.354)
prim("ForestEgg3", "horn_2_15", "rod", 0.136,0.246,0.120, 0.2080,0.1690,0.1280, 1.522,1.191,-1.354)
prim("ForestEgg3", "shard_1_16", "block", 0.120,0.170,0.120, 0.2122,0.6445,0.1022, 1.253,0.780,-0.916)
prim("ForestEgg3", "shard_2_17", "block", 0.109,0.097,0.134, 0.2122,0.6445,0.1022, 1.140,0.958,-1.636)
prim("ForestEgg3", "shard_3_18", "block", 0.093,0.120,0.091, 0.2122,0.6445,0.1022, 1.790,0.734,-1.966)
prim("ForestEgg3", "shard_4_19", "block", 0.164,0.136,0.130, 0.2122,0.6445,0.1022, 2.305,0.613,-1.450)
prim("ForestEgg3", "shard_5_20", "block", 0.103,0.104,0.125, 0.2122,0.6445,0.1022, 1.973,0.869,-0.801)
return "built " .. built
