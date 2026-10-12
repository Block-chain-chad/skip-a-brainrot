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
prim("ForestEgg2", "shell_body_1", "egg", 0.940,1.200,0.940, 0.7454,0.3515,0.0319, 0.478,0.600,-0.383)
prim("ForestEgg2", "drip_1_1_2", "ball", 0.157,0.176,0.158, 0.9301,0.6105,0.1441, 0.710,0.993,-0.284)
prim("ForestEgg2", "drip_1_2_3", "ball", 0.135,0.151,0.136, 0.9301,0.6105,0.1441, 0.797,0.844,-0.247)
prim("ForestEgg2", "drip_1_3_4", "ball", 0.113,0.127,0.114, 0.9301,0.6105,0.1441, 0.863,0.669,-0.219)
prim("ForestEgg2", "drip_1_4_5", "ball", 0.091,0.102,0.092, 0.9301,0.6105,0.1441, 0.895,0.487,-0.206)
prim("ForestEgg2", "drip_2_1_6", "ball", 0.157,0.176,0.158, 0.9301,0.6105,0.1441, 0.261,0.937,-0.185)
prim("ForestEgg2", "drip_2_2_7", "ball", 0.135,0.151,0.136, 0.9301,0.6105,0.1441, 0.197,0.776,-0.127)
prim("ForestEgg2", "drip_2_3_8", "ball", 0.113,0.127,0.114, 0.9301,0.6105,0.1441, 0.155,0.597,-0.088)
prim("ForestEgg2", "drip_2_4_9", "ball", 0.091,0.102,0.092, 0.9301,0.6105,0.1441, 0.144,0.417,-0.077)
prim("ForestEgg2", "drip_3_1_10", "ball", 0.157,0.176,0.158, 0.9301,0.6105,0.1441, 0.367,0.966,-0.632)
prim("ForestEgg2", "drip_3_2_11", "ball", 0.135,0.151,0.136, 0.9301,0.6105,0.1441, 0.331,0.811,-0.715)
prim("ForestEgg2", "drip_3_3_12", "ball", 0.113,0.127,0.114, 0.9301,0.6105,0.1441, 0.305,0.633,-0.775)
prim("ForestEgg2", "drip_3_4_13", "ball", 0.091,0.102,0.092, 0.9301,0.6105,0.1441, 0.296,0.452,-0.798)
prim("ForestEgg2", "tape_14", "band", 0.820,0.200,0.820, 0.1470,0.0723,0.0331, 0.478,0.115,-0.383)
prim("ForestEgg2", "shard_1_15", "block", 0.127,0.180,0.127, 0.9301,0.6105,0.1441, 0.068,0.800,0.027)
prim("ForestEgg2", "shard_2_16", "block", 0.116,0.103,0.142, 0.9301,0.6105,0.1441, 0.068,0.939,-0.793)
prim("ForestEgg2", "shard_3_17", "block", 0.099,0.127,0.097, 0.9301,0.6105,0.1441, 0.889,0.764,-0.792)
prim("ForestEgg2", "shard_4_18", "block", 0.174,0.144,0.138, 0.9301,0.6105,0.1441, 0.888,0.670,0.028)
return "built " .. built
