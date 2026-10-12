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
prim("ForestEgg4", "shell_body_1", "egg", 0.960,1.240,0.960, 0.0437,0.0307,0.0168, 2.972,0.620,-2.377)
prim("ForestEgg4", "stripe_1_2", "block", 0.129,1.223,0.449, 0.0953,0.0648,0.0331, 3.036,0.625,-2.117)
prim("ForestEgg4", "stripe_2_3", "block", 0.417,1.223,0.288, 0.0953,0.0648,0.0331, 3.209,0.625,-2.219)
prim("ForestEgg4", "stripe_3_4", "block", 0.440,1.223,0.221, 0.0953,0.0648,0.0331, 3.224,0.625,-2.496)
prim("ForestEgg4", "stripe_4_5", "block", 0.204,1.223,0.443, 0.0953,0.0648,0.0331, 3.080,0.625,-2.632)
prim("ForestEgg4", "stripe_5_6", "block", 0.303,1.223,0.409, 0.0953,0.0648,0.0331, 2.804,0.625,-2.610)
prim("ForestEgg4", "stripe_6_7", "block", 0.448,1.223,0.130, 0.0953,0.0648,0.0331, 2.711,0.625,-2.420)
prim("ForestEgg4", "stripe_7_8", "block", 0.357,1.223,0.369, 0.0953,0.0648,0.0331, 2.771,0.625,-2.170)
prim("ForestEgg4", "rune_ring_1_9", "ringseg", 0.119,0.222,0.239, 0.3467,0.8879,0.5776, 3.407,0.309,-2.377)
prim("ForestEgg4", "rune_bar_1_10", "block", 0.053,0.086,0.159, 0.3467,0.8879,0.5776, 3.407,0.309,-2.377)
prim("ForestEgg4", "rune_ring_2_11", "ringseg", 0.177,0.237,0.185, 0.3467,0.8879,0.5776, 2.634,0.405,-2.068)
prim("ForestEgg4", "rune_bar_2_12", "block", 0.093,0.139,0.119, 0.3467,0.8879,0.5776, 2.634,0.405,-2.068)
prim("ForestEgg4", "rune_ring_3_13", "ringseg", 0.238,0.239,0.065, 0.3467,0.8879,0.5776, 3.012,0.508,-2.837)
prim("ForestEgg4", "rune_bar_3_14", "block", 0.151,0.110,0.033, 0.3467,0.8879,0.5776, 3.012,0.508,-2.837)
prim("ForestEgg4", "rune_ring_4_15", "ringseg", 0.197,0.233,0.169, 0.3467,0.8879,0.5776, 3.245,0.616,-2.020)
prim("ForestEgg4", "rune_bar_4_16", "block", 0.146,0.041,0.120, 0.3467,0.8879,0.5776, 3.245,0.616,-2.020)
prim("ForestEgg4", "rune_ring_5_17", "ringseg", 0.110,0.229,0.235, 0.3467,0.8879,0.5776, 2.556,0.726,-2.451)
prim("ForestEgg4", "rune_bar_5_18", "block", 0.064,0.161,0.085, 0.3467,0.8879,0.5776, 2.556,0.726,-2.451)
prim("ForestEgg4", "rune_ring_6_19", "ringseg", 0.168,0.219,0.208, 0.3467,0.8879,0.5776, 3.294,0.831,-2.582)
prim("ForestEgg4", "rune_bar_6_20", "block", 0.116,0.151,0.068, 0.3467,0.8879,0.5776, 3.294,0.831,-2.582)
prim("ForestEgg4", "rune_ring_7_21", "ringseg", 0.233,0.207,0.154, 0.3467,0.8879,0.5776, 2.885,0.929,-2.055)
prim("ForestEgg4", "rune_bar_7_22", "block", 0.164,0.044,0.069, 0.3467,0.8879,0.5776, 2.885,0.929,-2.055)
prim("ForestEgg4", "ring_1_23", "ringseg", 1.432,0.681,1.411, 0.3467,0.8879,0.5776, 2.972,0.600,-2.377)
prim("ForestEgg4", "shard_1_24", "block", 0.136,0.119,0.136, 0.3467,0.8879,0.5776, 2.519,0.850,-1.925)
prim("ForestEgg4", "shard_2_25", "block", 0.114,0.109,0.117, 0.3467,0.8879,0.5776, 2.354,1.068,-2.544)
prim("ForestEgg4", "shard_3_26", "block", 0.096,0.092,0.098, 0.3467,0.8879,0.5776, 2.807,0.794,-2.996)
prim("ForestEgg4", "shard_4_27", "block", 0.122,0.139,0.127, 0.3467,0.8879,0.5776, 3.425,0.646,-2.829)
prim("ForestEgg4", "shard_5_28", "block", 0.113,0.107,0.103, 0.3467,0.8879,0.5776, 3.590,0.959,-2.211)
prim("ForestEgg4", "shard_6_29", "block", 0.085,0.088,0.100, 0.3467,0.8879,0.5776, 3.137,1.026,-1.759)
return "built " .. built
