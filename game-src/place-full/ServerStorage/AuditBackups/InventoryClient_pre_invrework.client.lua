-- The Roblox Backpack is the brainrot inventory.
-- This only bridges the "Store" prompt on a placed brainrot back to the server. Earnings
-- are NOT a prompt: you collect a brainrot by walking over it (IncomeLoop).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if prompt.Name ~= "StorePrompt" then return end
	if triggeringPlayer ~= player then return end
	-- Uid lives on the top-level model, which is what the prompt is parented to
	local model = prompt.Parent
	local uid = model and model:GetAttribute("Uid")
	if uid then
		remotes.StoreBrainrot:FireServer(uid)
	end
end)

-- === Hide the "Store" prompt on plots you don't own ==========================
-- The StorePrompt is server-created on every placed brainrot and replicates to
-- ALL clients, so without this everyone sees "Store" on everyone's brainrots. The
-- server already rejects a non-owner's StoreBrainrot call (that's why it "did
-- nothing"), so this only stops the prompt from SHOWING. Enabled is toggled
-- LOCALLY on the replicated prompt -- the server never writes Enabled after
-- creation, so there is nothing to fight and other players are unaffected. The
-- cash billboard on each brainrot is left alone.
local Workspace = game:GetService("Workspace")

local function iOwn(plot)
	return plot:GetAttribute("OwnerUserId") == player.UserId
end

local function refreshPlot(plot)
	local owned = iOwn(plot)
	for _, d in ipairs(plot:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == "StorePrompt" then
			d.Enabled = owned
		end
	end
end

local function watchPlot(plot)
	-- On join the brainrot models and the OwnerUserId attribute arrive on separate
	-- replication streams, so a StorePrompt can appear before we know who owns the
	-- plot -- it starts disabled and this re-enables it once ownership lands (only
	-- ever matters for your OWN plot; other plots stay disabled).
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		refreshPlot(plot)
	end)
	plot.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") and d.Name == "StorePrompt" then
			d.Enabled = iOwn(plot)
		end
	end)
	refreshPlot(plot)
end

local bases = Workspace:WaitForChild("PlayerBases")
for _, plot in ipairs(bases:GetChildren()) do
	watchPlot(plot)
end
bases.ChildAdded:Connect(watchPlot)
