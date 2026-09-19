-- Strips Roblox gear that players bring in with them.
--
-- WHY THIS IS NOT "DESTROY EVERY TOOL". This game's inventory IS Tools --
-- InventoryHandler.makeTool builds one per unplaced brainrot. Removing Tools
-- indiscriminately would delete players' brainrots out of their hands. Every tool the
-- game makes carries the BrainrotTool attribute, and makeTool sets it BEFORE the tool is
-- ever parented, so checking it on ChildAdded is safe and never races.
--
-- Gear reaches a player by two routes and both are covered:
--   * StarterGear  -- Roblox copies the player's equipped gear here on join, and copies
--                     it into the Backpack on EVERY respawn. Clearing only the Backpack
--                     would let it come straight back on death.
--   * Backpack / Character -- where it ends up, held or stowed.
--
-- The experience-level "allow gear" setting on the Creator Dashboard is the proper
-- source fix; this is the enforcement that holds regardless of that setting, and it
-- takes effect for players already mid-session.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local removed = 0
local reported = {}

local function allowed(tool)
	-- the game's own inventory
	if tool:GetAttribute("BrainrotTool") then return true end
	-- convention left open for any future legitimate game tool
	if tool:GetAttribute("GameItem") then return true end
	-- CellarDoor.hasKey accepts a Tool named after the cellar's RequiredKey as one of
	-- its two unlock routes, so that name must survive even though nothing grants it yet
	local gw = Workspace:FindFirstChild("GameWorld")
	local cellar = gw and gw:FindFirstChild("Cellar")
	local keyName = cellar and cellar:GetAttribute("RequiredKey")
	if keyName and tool.Name == keyName then return true end
	return false
end

local function strip(item, where)
	if not (item:IsA("Tool") or item:IsA("HopperBin")) then return end
	if item:IsA("Tool") and allowed(item) then return end
	removed += 1
	if not reported[item.Name] then
		reported[item.Name] = true
		warn(("[GearBlocker] removing gear %q (from %s). If this is a real game item, give it a GameItem attribute.")
			:format(item.Name, where))
	end
	item:Destroy()
end

local function watch(container, where)
	if not container then return end
	for _, child in ipairs(container:GetChildren()) do
		strip(child, where)
	end
	container.ChildAdded:Connect(function(child)
		-- defer one frame: attributes are set before parenting by our own code, but a
		-- deferred check costs nothing and is robust if that ever changes
		task.defer(function()
			if child.Parent then strip(child, where) end
		end)
	end)
end

local function onPlayer(player)
	watch(player:WaitForChild("StarterGear", 20), "StarterGear")
	watch(player:FindFirstChildOfClass("Backpack"), "Backpack")

	-- Backpack is destroyed and rebuilt on every respawn, so re-watch each new one
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then watch(child, "Backpack")
		elseif child:IsA("StarterGear") then watch(child, "StarterGear") end
	end)

	player.CharacterAdded:Connect(function(char)
		watch(char, "Character")            -- equipped gear parents into the character
		watch(player:FindFirstChildOfClass("Backpack"), "Backpack")
	end)
	if player.Character then watch(player.Character, "Character") end
end

for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end
Players.PlayerAdded:Connect(onPlayer)

print("GearBlocker online (strips gear; keeps tools flagged BrainrotTool / GameItem)")
