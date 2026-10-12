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
prim("ForestEgg5", "shell_body_1", "egg", 1.400,1.820,1.400, 0.0685,0.0423,0.0194, 4.760,1.051,-3.808)
prim("ForestEgg5", "cap_2", "band", 1.307,0.721,1.312, 0.1144,0.3231,0.0497, 4.760,1.601,-3.808)
prim("ForestEgg5", "cap_drip_1_3", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 5.397,1.270,-3.808)
prim("ForestEgg5", "cap_drip_2_4", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 5.355,1.156,-3.494)
prim("ForestEgg5", "cap_drip_3_5", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 5.121,1.270,-3.281)
prim("ForestEgg5", "cap_drip_4_6", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 4.838,1.156,-3.137)
prim("ForestEgg5", "cap_drip_5_7", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 4.530,1.270,-3.209)
prim("ForestEgg5", "cap_drip_6_8", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 4.252,1.156,-3.360)
prim("ForestEgg5", "cap_drip_7_9", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 4.136,1.270,-3.655)
prim("ForestEgg5", "cap_drip_8_10", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 4.101,1.156,-3.969)
prim("ForestEgg5", "cap_drip_9_11", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 4.278,1.270,-4.232)
prim("ForestEgg5", "cap_drip_10_12", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 4.518,1.156,-4.439)
prim("ForestEgg5", "cap_drip_11_13", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 4.834,1.270,-4.443)
prim("ForestEgg5", "cap_drip_12_14", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 5.141,1.156,-4.363)
prim("ForestEgg5", "cap_drip_13_15", "ball", 0.161,0.170,0.163, 0.1144,0.3231,0.0497, 5.324,1.270,-4.105)
prim("ForestEgg5", "stripe_1_16", "block", 0.100,1.171,0.530, 0.0284,0.1470,0.0343, 4.809,0.746,-3.366)
prim("ForestEgg5", "stripe_2_17", "block", 0.439,1.171,0.393, 0.0284,0.1470,0.0343, 5.105,0.746,-3.504)
prim("ForestEgg5", "stripe_3_18", "block", 0.530,1.171,0.100, 0.0284,0.1470,0.0343, 5.201,0.746,-3.857)
prim("ForestEgg5", "stripe_4_19", "block", 0.393,1.171,0.439, 0.0284,0.1470,0.0343, 5.063,0.746,-4.153)
prim("ForestEgg5", "stripe_5_20", "block", 0.100,1.171,0.530, 0.0284,0.1470,0.0343, 4.710,0.746,-4.249)
prim("ForestEgg5", "stripe_6_21", "block", 0.439,1.171,0.393, 0.0284,0.1470,0.0343, 4.414,0.746,-4.111)
prim("ForestEgg5", "stripe_7_22", "block", 0.530,1.171,0.100, 0.0284,0.1470,0.0343, 4.318,0.746,-3.758)
prim("ForestEgg5", "stripe_8_23", "block", 0.393,1.171,0.439, 0.0284,0.1470,0.0343, 4.456,0.746,-3.462)
prim("ForestEgg5", "rune_ring_1_24", "ringseg", 0.099,0.242,0.250, 0.4678,0.9301,0.3916, 5.409,0.617,-3.808)
prim("ForestEgg5", "rune_bar_1_25", "block", 0.042,0.072,0.171, 0.4678,0.9301,0.3916, 5.409,0.617,-3.808)
prim("ForestEgg5", "rune_ring_2_26", "ringseg", 0.194,0.243,0.195, 0.4678,0.9301,0.3916, 5.219,0.617,-3.348)
prim("ForestEgg5", "rune_bar_2_27", "block", 0.121,0.159,0.075, 0.4678,0.9301,0.3916, 5.219,0.617,-3.348)
prim("ForestEgg5", "rune_ring_3_28", "ringseg", 0.252,0.244,0.100, 0.4678,0.9301,0.3916, 4.760,0.617,-3.158)
prim("ForestEgg5", "rune_bar_3_29", "block", 0.064,0.173,0.068, 0.4678,0.9301,0.3916, 4.760,0.617,-3.158)
prim("ForestEgg5", "rune_ring_4_30", "ringseg", 0.194,0.243,0.195, 0.4678,0.9301,0.3916, 4.300,0.617,-3.348)
prim("ForestEgg5", "rune_bar_4_31", "block", 0.143,0.049,0.141, 0.4678,0.9301,0.3916, 4.300,0.617,-3.348)
prim("ForestEgg5", "rune_ring_5_32", "ringseg", 0.099,0.242,0.250, 0.4678,0.9301,0.3916, 4.110,0.617,-3.808)
prim("ForestEgg5", "rune_bar_5_33", "block", 0.056,0.126,0.151, 0.4678,0.9301,0.3916, 4.110,0.617,-3.808)
prim("ForestEgg5", "rune_ring_6_34", "ringseg", 0.195,0.240,0.195, 0.4678,0.9301,0.3916, 4.300,0.617,-4.267)
prim("ForestEgg5", "rune_bar_6_35", "block", 0.104,0.169,0.051, 0.4678,0.9301,0.3916, 4.300,0.617,-4.267)
prim("ForestEgg5", "rune_ring_7_36", "ringseg", 0.252,0.244,0.100, 0.4678,0.9301,0.3916, 4.760,0.617,-4.457)
prim("ForestEgg5", "rune_bar_7_37", "block", 0.170,0.032,0.032, 0.4678,0.9301,0.3916, 4.760,0.617,-4.457)
prim("ForestEgg5", "rune_ring_8_38", "ringseg", 0.195,0.240,0.195, 0.4678,0.9301,0.3916, 5.219,0.617,-4.267)
prim("ForestEgg5", "rune_bar_8_39", "block", 0.057,0.173,0.075, 0.4678,0.9301,0.3916, 5.219,0.617,-4.267)
prim("ForestEgg5", "crown_ring_40", "ringseg", 0.622,0.070,0.619, 0.7758,0.6867,0.4793, 4.760,1.848,-3.808)
prim("ForestEgg5", "crown_point_1_41", "rod", 0.134,0.441,0.110, 0.7758,0.6867,0.4793, 5.036,2.059,-3.808)
prim("ForestEgg5", "crown_tip_1_42", "rod", 0.110,0.110,0.110, 0.4678,0.9301,0.3916, 5.103,2.279,-3.808)
prim("ForestEgg5", "crown_point_2_43", "rod", 0.102,0.441,0.123, 0.7758,0.6867,0.4793, 4.923,2.058,-3.600)
prim("ForestEgg5", "crown_tip_2_44", "rod", 0.110,0.110,0.110, 0.4678,0.9301,0.3916, 4.974,2.279,-3.539)
prim("ForestEgg5", "crown_point_3_45", "rod", 0.095,0.442,0.139, 0.7758,0.6867,0.4793, 4.703,2.058,-3.542)
prim("ForestEgg5", "crown_tip_3_46", "rod", 0.110,0.110,0.110, 0.4678,0.9301,0.3916, 4.683,2.279,-3.473)
prim("ForestEgg5", "crown_point_4_47", "rod", 0.126,0.442,0.110, 0.7758,0.6867,0.4793, 4.513,2.058,-3.697)
prim("ForestEgg5", "crown_tip_4_48", "rod", 0.110,0.110,0.110, 0.4678,0.9301,0.3916, 4.450,2.279,-3.659)
prim("ForestEgg5", "crown_point_5_49", "rod", 0.126,0.442,0.110, 0.7758,0.6867,0.4793, 4.513,2.058,-3.919)
prim("ForestEgg5", "crown_tip_5_50", "rod", 0.110,0.110,0.110, 0.4678,0.9301,0.3916, 4.450,2.279,-3.957)
prim("ForestEgg5", "crown_point_6_51", "rod", 0.095,0.442,0.139, 0.7758,0.6867,0.4793, 4.703,2.058,-4.073)
prim("ForestEgg5", "crown_tip_6_52", "rod", 0.110,0.110,0.110, 0.4678,0.9301,0.3916, 4.683,2.279,-4.143)
prim("ForestEgg5", "crown_point_7_53", "rod", 0.102,0.441,0.123, 0.7758,0.6867,0.4793, 4.923,2.058,-4.015)
prim("ForestEgg5", "crown_tip_7_54", "rod", 0.110,0.110,0.110, 0.4678,0.9301,0.3916, 4.974,2.279,-4.076)
prim("ForestEgg5", "ring_1_55", "ringseg", 1.948,1.014,1.912, 0.4678,0.9301,0.3916, 4.760,1.021,-3.808)
prim("ForestEgg5", "ring_2_56", "ringseg", 1.779,0.928,1.745, 0.4678,0.9301,0.3916, 4.760,1.021,-3.808)
prim("ForestEgg5", "shard_1_57", "block", 0.175,0.153,0.175, 0.4678,0.9301,0.3916, 4.066,1.241,-3.115)
prim("ForestEgg5", "shard_2_58", "block", 0.147,0.140,0.150, 0.4678,0.9301,0.3916, 3.780,1.519,-3.809)
prim("ForestEgg5", "shard_3_59", "block", 0.123,0.119,0.126, 0.4678,0.9301,0.3916, 4.067,1.169,-4.501)
prim("ForestEgg5", "shard_4_60", "block", 0.157,0.179,0.163, 0.4678,0.9301,0.3916, 4.761,0.982,-4.788)
prim("ForestEgg5", "shard_5_61", "block", 0.146,0.137,0.132, 0.4678,0.9301,0.3916, 5.453,1.379,-4.500)
prim("ForestEgg5", "shard_6_62", "block", 0.110,0.113,0.129, 0.4678,0.9301,0.3916, 5.740,1.465,-3.807)
prim("ForestEgg5", "shard_7_63", "block", 0.169,0.162,0.159, 0.4678,0.9301,0.3916, 5.452,1.045,-3.114)
prim("ForestEgg5", "shard_8_64", "block", 0.131,0.136,0.151, 0.4678,0.9301,0.3916, 4.759,1.068,-2.828)
prim("ForestEgg5", "halo_ring_65", "ringseg", 1.790,0.353,1.781, 0.7758,0.6867,0.4793, 4.760,2.341,-3.808)
prim("ForestEgg5", "link_1_1_66", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 5.620,2.301,-3.808)
prim("ForestEgg5", "link_1_2_67", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 5.620,2.211,-3.808)
prim("ForestEgg5", "link_1_3_68", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 5.620,2.121,-3.808)
prim("ForestEgg5", "link_1_4_69", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 5.620,2.031,-3.808)
prim("ForestEgg5", "link_1_5_70", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 5.620,1.941,-3.808)
prim("ForestEgg5", "link_1_6_71", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 5.620,1.851,-3.808)
prim("ForestEgg5", "link_1_7_72", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 5.620,1.762,-3.808)
prim("ForestEgg5", "link_1_8_73", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 5.620,1.672,-3.808)
prim("ForestEgg5", "link_2_1_74", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 4.760,2.301,-2.948)
prim("ForestEgg5", "link_2_2_75", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 4.760,2.211,-2.948)
prim("ForestEgg5", "link_2_3_76", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 4.760,2.121,-2.948)
prim("ForestEgg5", "link_2_4_77", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 4.760,2.031,-2.948)
prim("ForestEgg5", "link_2_5_78", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 4.760,1.941,-2.948)
prim("ForestEgg5", "link_2_6_79", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 4.760,1.851,-2.948)
prim("ForestEgg5", "link_2_7_80", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 4.760,1.762,-2.948)
prim("ForestEgg5", "link_2_8_81", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 4.760,1.672,-2.948)
prim("ForestEgg5", "link_3_1_82", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 3.900,2.301,-3.808)
prim("ForestEgg5", "link_3_2_83", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 3.900,2.211,-3.808)
prim("ForestEgg5", "link_3_3_84", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 3.900,2.121,-3.808)
prim("ForestEgg5", "link_3_4_85", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 3.900,2.031,-3.808)
prim("ForestEgg5", "link_3_5_86", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 3.900,1.941,-3.808)
prim("ForestEgg5", "link_3_6_87", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 3.900,1.851,-3.808)
prim("ForestEgg5", "link_3_7_88", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 3.900,1.762,-3.808)
prim("ForestEgg5", "link_3_8_89", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 3.900,1.672,-3.808)
prim("ForestEgg5", "link_4_1_90", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 4.760,2.301,-4.668)
prim("ForestEgg5", "link_4_2_91", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 4.760,2.211,-4.668)
prim("ForestEgg5", "link_4_3_92", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 4.760,2.121,-4.668)
prim("ForestEgg5", "link_4_4_93", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 4.760,2.031,-4.668)
prim("ForestEgg5", "link_4_5_94", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 4.760,1.941,-4.668)
prim("ForestEgg5", "link_4_6_95", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 4.760,1.851,-4.668)
prim("ForestEgg5", "link_4_7_96", "block", 0.151,0.033,0.143, 0.0284,0.1470,0.0343, 4.760,1.762,-4.668)
prim("ForestEgg5", "link_4_8_97", "block", 0.033,0.143,0.151, 0.0284,0.1470,0.0343, 4.760,1.672,-4.668)
return "built " .. built
