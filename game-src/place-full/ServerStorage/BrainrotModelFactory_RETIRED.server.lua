-- BrainrotModelFactory
-- Generates one template Model per BrainrotLooks recipe into
-- ServerStorage.BrainrotModels at server start. The spawner's existing
-- authored-model path does the rest (clone, height-normalize via ScaleTo,
-- seat base on pad, anchor), so this script must never scale or position
-- anything it builds -- doing so would double up with the spawner's math.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BrainrotLooks = require(Modules:WaitForChild("BrainrotLooks"))
local BrainrotBodyBuilder = require(Modules:WaitForChild("BrainrotBodyBuilder"))

-- BrainrotIdleClient animates every model carrying this tag; it must sit on
-- the TEMPLATE so clones inherit it and no per-spawn wiring is needed.
local BODY_TAG = "BrainrotBody"

-- The folder may already exist with hand-authored models inside (Secret
-- Pete); never recreate it, only fill the gaps.
local folder = ServerStorage:FindFirstChild("BrainrotModels")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "BrainrotModels"
	folder.Parent = ServerStorage
end

local built, skipped, failed = 0, 0, 0

for name, recipe in pairs(BrainrotLooks) do
	-- Hand-authored models win unconditionally: they exist precisely because
	-- someone decided the generated body wasn't good enough for that name.
	if folder:FindFirstChild(name) then
		skipped += 1
		continue
	end

	-- One bad recipe must never take down the other 200+ bodies. A missing
	-- template is safe anyway: the spawner falls back to the classic cube.
	local ok, result = pcall(BrainrotBodyBuilder.Build, name, recipe)
	if ok and typeof(result) == "Instance" and result:IsA("Model") then
		-- The spawner looks templates up by exact config-entry name, so
		-- Name is a contract here, not cosmetics.
		result.Name = name
		CollectionService:AddTag(result, BODY_TAG)
		if recipe.Motion ~= nil then
			result:SetAttribute("Motion", recipe.Motion)
		end
		result.Parent = folder
		built += 1
	else
		failed += 1
		if ok then
			-- Builder returned quietly-wrong data; surface it as loudly as
			-- a thrown error would have been.
			warn(("BrainrotModelFactory: builder returned no Model for %q"):format(tostring(name)))
			if typeof(result) == "Instance" then
				result:Destroy()
			end
		else
			warn(("BrainrotModelFactory: build failed for %q: %s"):format(tostring(name), tostring(result)))
		end
	end
end

print(("BrainrotModelFactory: built %d, skipped %d existing, %d failed"):format(built, skipped, failed))