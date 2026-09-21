-- push.lua -- execute_luau chunk (Edit mode) that pulls mirror files through the bridge and
-- writes them into the place. Edit the LIST, paste the whole file as the code argument.
--   entry = { "<mirror path under game-src>", "<dot path of the container>", "<ClassName>" }
-- The container is created if missing (parents must exist). Sources over 200k chars go
-- through ScriptEditorService:UpdateSourceAsync (the only route past the Source cap).
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local LIST = {
	-- { "place-full/ReplicatedStorage/Modules/EggArt.lua", "ReplicatedStorage.Modules.EggArt", "ModuleScript" },
}
local function resolve(dotPath)
	local node = game
	local parentNode, leaf = nil, nil
	for seg in dotPath:gmatch("[^%.]+") do
		parentNode = node
		leaf = seg
		node = node:FindFirstChild(seg)
		if not node then return nil, parentNode, leaf end
	end
	return node, parentNode, leaf
end
local was = HS.HttpEnabled
HS.HttpEnabled = true
local out = {}
for _, e in ipairs(LIST) do
	local rel, dot, class = e[1], e[2], e[3]
	local ok, src = pcall(function() return HS:GetAsync("http://127.0.0.1:8731/src/" .. rel) end)
	if not ok then
		out[#out + 1] = rel .. " -> FETCH FAILED " .. tostring(src)
	else
		local inst, parentNode, leaf = resolve(dot)
		if not inst then
			if not parentNode then
				out[#out + 1] = dot .. " -> parent missing"
				continue
			end
			inst = Instance.new(class)
			inst.Name = leaf
			inst.Parent = parentNode
		end
		local okS, err = pcall(function()
			if #src > 190000 then
				SES:UpdateSourceAsync(inst, function() return src end)
			else
				inst.Source = src
			end
		end)
		out[#out + 1] = dot .. " -> " .. (okS and ("ok " .. #src .. " chars") or ("WRITE FAILED " .. tostring(err)))
	end
end
HS.HttpEnabled = was
return "HttpEnabled=" .. tostring(HS.HttpEnabled) .. "\n" .. table.concat(out, "\n")
