local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local remotes = ReplicatedStorage.Remotes

-- Fixed destinations (position, look direction)
local THROW_POS = Vector3.new(0, 6, 22)
local SHOPS_POS = Vector3.new(0, 9.53, -260) -- middle of the lodge interior (on PlazaFloor, among the stalls)
local TRADE_POS = Vector3.new(8000, 2006, 7905) -- island entrance (foot of the boardwalk, by the return portal)
local HUB_POS = Vector3.new(24, 6, -16) -- back in the hub, just west of the trade portal
local FORWARD = Vector3.new(0, 0, 1)
local TO_SHOPS = Vector3.new(0, 0, -1) -- face -Z toward the back shop counters (ShopStall / SellStall)
local TO_HUB = Vector3.new(-1, 0, 0) -- face back toward spawn when returning

local function teleportCharacter(player, pos, lookDir)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	character:PivotTo(CFrame.lookAt(pos, pos + lookDir))
end

-- Base-less player: drop them onto the first open plot. Touching it claims the base
-- (PlayerDataManager binds Touched on each plot's Platform).
--
-- Extracted into a function because it is needed from TWO destinations. The "Plot" tab
-- used to `if plot then ... end` with no else, so pressing it with no base did NOTHING --
-- no teleport, no message, no error. The open-plot logic existed but only "OpenPlot"
-- reached it, and only the throw button ever sends that.
local function teleportToOpenPlot(player)
	if PlayerDataManager.GetPlot(player) then return false end   -- already owns one
	local plotsFolder = workspace:FindFirstChild("PlayerBases")
	local target
	if plotsFolder then
		-- iterate the folder rather than Plot1..Plot6 by name: the count is not guaranteed
		-- and a renamed or added plot would be silently skipped by a hardcoded range.
		for _, plot in ipairs(plotsFolder:GetChildren()) do
			if plot:IsA("Model") and not plot:GetAttribute("Claimed") then
				target = plot
				break
			end
		end
	end
	if target then
		-- Land OFF-CENTRE. The plot pivot sits directly above the Campfire, so the old
		-- `pivot + (0,6,0)` dropped the player onto the fire and they never contacted the
		-- Platform at all -- which is what the claim listens to. Verified by raycast:
		-- offset 0 hits Campfire, -10 hits Pad1, -14 hits Platform cleanly.
		local pivot = target:GetPivot().Position
		teleportCharacter(player, pivot + Vector3.new(0, 6, -14), FORWARD)
		-- Then claim it OUTRIGHT rather than waiting for Platform.Touched to fire. A
		-- teleport is not a reliable touch -- the character can settle on a pad, a pit
		-- stone or the campfire and silently never claim, which is exactly the dead end
		-- this button had. Walking on still works via Touched; this just makes the
		-- button deterministic. ClaimPlotFor already refuses if the plot is taken or the
		-- player owns one, so it cannot double-claim.
		PlayerDataManager.ClaimPlotFor(player, target)
		return true
	end
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = false, Message = "All plots are taken right now!" }) end
	return false
end

remotes.TeleportTo.OnServerEvent:Connect(function(player, destination)
	if typeof(destination) ~= "string" then return end

	if destination == "Throw" then
		teleportCharacter(player, THROW_POS, FORWARD)
	elseif destination == "Shops" then
		teleportCharacter(player, SHOPS_POS, TO_SHOPS)
	elseif destination == "Trade" then
		teleportCharacter(player, TRADE_POS, FORWARD)
	elseif destination == "Plot" then
		local plot = PlayerDataManager.GetPlot(player)
		if plot then
			local pivot = plot:GetPivot()
			-- stand near the front edge of the plot, looking across the pads
			local pos = pivot.Position + Vector3.new(0, 6, -22)
			teleportCharacter(player, pos, FORWARD)
		else
			-- THE FIX: no base yet, so send them somewhere they can get one rather than
			-- doing nothing. This is the whole point of the button for a new player.
			teleportToOpenPlot(player)
		end
	elseif destination == "OpenPlot" then
		teleportToOpenPlot(player)
	end
end)

-- === Walk-through portals (Pet Sim style) ===
-- A player who touches a portal's PortalTouch part is teleported to the
-- destination named in its Dest attribute.
local portalDests = {
	Trade = { pos = TRADE_POS, look = FORWARD },
	Hub = { pos = HUB_POS, look = TO_HUB },
}

local lastPortalUse = {} -- [player] = os.clock(); debounce so one pass = one teleport

local function setupPortal(touchPart)
	local dest = touchPart:GetAttribute("Dest")
	local target = dest and portalDests[dest]
	if not target then return end
	touchPart.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then return end
		local now = os.clock()
		if lastPortalUse[player] and now - lastPortalUse[player] < 1.5 then return end
		lastPortalUse[player] = now
		teleportCharacter(player, target.pos, target.look)
	end)
end

task.spawn(function()
	local portals = workspace:WaitForChild("GameWorld"):WaitForChild("Portals")
	for _, model in ipairs(portals:GetChildren()) do
		local touch = model:FindFirstChild("PortalTouch")
		if touch then setupPortal(touch) end
	end
	portals.ChildAdded:Connect(function(model)
		local touch = model:FindFirstChild("PortalTouch") or model:WaitForChild("PortalTouch", 5)
		if touch then setupPortal(touch) end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastPortalUse[player] = nil
end)

print("TeleportService online")
