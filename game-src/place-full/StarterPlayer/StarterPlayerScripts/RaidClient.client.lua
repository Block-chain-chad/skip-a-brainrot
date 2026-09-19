-- RaidClient -- cosmetic gate for the plot-raid "Steal" prompt (server logic lives
-- in StealService). Two jobs, both local-only:
--   1. Hide the RaidPrompt on brainrots that sit on the LOCAL player's OWN plot --
--      you can't rob yourself, and the server ignores it anyway; this just stops a
--      confusing "Steal" prompt appearing on your own pets.
--   2. Hide every RaidPrompt while the mechanic isn't usable for this player (no
--      live product, and not a creator during the free test), so a half-built
--      feature never shows a price to normal players.
-- Setting .Enabled on the client only affects THIS client's view of the prompt --
-- it never touches the server object, so other players can still raid.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local StealConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StealConfig"))

local canUse = StealConfig.CanUse(player.UserId)

-- The plot MODEL a brainrot sits on, found STRUCTURALLY (its Campfire + Pads
-- children) so it resolves even before the OwnerUserId attribute has replicated.
local function plotOf(model)
	local n = model.Parent
	while n do
		if n:FindFirstChild("Campfire") and n:FindFirstChild("Pads") then return n end
		n = n.Parent
	end
	return nil
end

local function manage(model)
	if not model:IsA("Model") then return end
	task.spawn(function()
		local plot = plotOf(model)
		-- Find the RaidPrompt ANYWHERE in the model (recursive), NOT on a `host` part we
		-- compute ourselves: the server attaches it to model.PrimaryPart, but PrimaryPart
		-- can be momentarily nil on the client, so a self-computed host lands on a
		-- DIFFERENT part and the prompt is never found/hidden -- that was the "Steal still
		-- shows on some of my own pets" bug. Steal shows ONLY on a KNOWN foreign plot.
		local function gate()
			local prompt = model:FindFirstChild("RaidPrompt", true)
			if not prompt then return end
			local owner = plot and plot:GetAttribute("OwnerUserId")
			prompt.Enabled = (canUse == true) and (owner ~= nil) and (owner ~= player.UserId)
		end
		gate()
		-- re-gate when the prompt replicates in late, and when ownership resolves/changes
		model.DescendantAdded:Connect(function(d)
			if d.Name == "RaidPrompt" then gate() end
		end)
		if plot then
			plot:GetAttributeChangedSignal("OwnerUserId"):Connect(gate)
		end
	end)
end

for _, m in ipairs(CollectionService:GetTagged("BrainrotBody")) do manage(m) end
CollectionService:GetInstanceAddedSignal("BrainrotBody"):Connect(manage)
