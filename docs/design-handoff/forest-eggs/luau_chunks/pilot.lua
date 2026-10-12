-- egg mesh chunk (auto-generated). Builds groups via EditableMesh.
local AssetService = game:GetService("AssetService")
local staging = game.ServerStorage:FindFirstChild("EggMeshStaging")
if not staging then
	staging = Instance.new("Folder")
	staging.Name = "EggMeshStaging"
	staging.Parent = game.ServerStorage
end
local built, failed = 0, {}
local function addGroup(eggName, partName, verts, tris, r, g, b, cx, cy, cz)
	local ok, err = pcall(function()
		local em = AssetService:CreateEditableMesh()
		local ids = table.create(#verts / 3)
		for i = 1, #verts, 3 do
			ids[#ids + 1] = em:AddVertex(Vector3.new(verts[i], verts[i + 1], verts[i + 2]))
		end
		for i = 1, #tris, 3 do
			em:AddTriangle(ids[tris[i]], ids[tris[i + 1]], ids[tris[i + 2]])
		end
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		part.Name = partName
		part.Color = Color3.new(r, g, b)
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		local eggFolder = staging:FindFirstChild(eggName)
		if not eggFolder then
			eggFolder = Instance.new("Model")
			eggFolder.Name = eggName
			eggFolder.Parent = staging
		end
		part.CFrame = CFrame.new(cx, cy, cz)
		part.Parent = eggFolder
	end)
	if ok then built += 1 else table.insert(failed, partName .. ": " .. tostring(err)) end
end
addGroup("PilotTest", "stud_1_1", {0.026,-0.003,0.000,0.023,0.013,0.000,0.022,0.009,0.011,0.026,-0.003,0.000,0.022,-0.003,0.016,0.026,-0.003,0.000,0.022,-0.014,0.011,0.026,-0.003,0.000,0.022,-0.019,0.000,0.026,-0.003,0.000,0.022,-0.014,-0.011,0.026,-0.003,0.000,0.022,-0.003,-0.016,0.026,-0.003,0.000,0.022,0.009,-0.011,0.026,-0.003,0.000,0.023,0.013,0.000,0.013,0.017,0.020,0.014,0.025,0.000,0.013,-0.002,0.028,0.012,-0.022,0.020,0.012,-0.030,0.000,0.012,-0.022,-0.020,0.013,-0.002,-0.028,0.013,0.017,-0.020,0.014,0.025,0.000,0.001,0.021,0.023,0.001,0.030,0.000,-0.000,-0.002,0.032,-0.001,-0.025,0.023,-0.001,-0.034,0.000,-0.001,-0.025,-0.023,-0.000,-0.002,-0.032,0.001,0.021,-0.023,0.001,0.030,0.000,-0.012,0.018,0.020,-0.012,0.026,0.000,-0.013,-0.002,0.028,-0.014,-0.021,0.020,-0.014,-0.029,0.000,-0.014,-0.021,-0.020,-0.013,-0.002,-0.028,-0.012,0.018,-0.020,-0.012,0.026,0.000,-0.022,0.010,0.011,-0.022,0.015,0.000,-0.022,-0.001,0.016,-0.023,-0.013,0.011,-0.023,-0.017,0.000,-0.023,-0.013,-0.011,-0.022,-0.001,-0.016,-0.022,0.010,-0.011,-0.022,0.015,0.000,-0.026,-0.001,0.000,-0.026,-0.001,0.000,-0.026,-0.001,0.000,-0.026,-0.001,0.000,-0.026,-0.001,0.000,-0.026,-0.001,0.000,-0.026,-0.001,0.000,-0.026,-0.001,0.000}, {1,2,3,4,3,5,6,5,7,8,7,9,10,9,11,12,11,13,14,13,15,16,15,17,3,2,18,2,19,18,5,3,20,3,18,20,7,5,21,5,20,21,9,7,22,7,21,22,11,9,23,9,22,23,13,11,24,11,23,24,15,13,25,13,24,25,17,15,26,15,25,26,18,19,27,19,28,27,20,18,29,18,27,29,21,20,30,20,29,30,22,21,31,21,30,31,23,22,32,22,31,32,24,23,33,23,32,33,25,24,34,24,33,34,26,25,35,25,34,35,27,28,36,28,37,36,29,27,38,27,36,38,30,29,39,29,38,39,31,30,40,30,39,40,32,31,41,31,40,41,33,32,42,32,41,42,34,33,43,33,42,43,35,34,44,34,43,44,36,37,45,37,46,45,38,36,47,36,45,47,39,38,48,38,47,48,40,39,49,39,48,49,41,40,50,40,49,50,42,41,51,41,50,51,43,42,52,42,51,52,44,43,53,43,52,53,45,46,54,47,45,55,48,47,56,49,48,57,50,49,58,51,50,59,52,51,60,53,52,61}, 0.8070, 0.9301, 0.4342, -0.236, 0.453, 0.560)
return "built " .. built .. ", failed " .. #failed .. (#failed > 0 and (": " .. table.concat(failed, " | ")) or "")
