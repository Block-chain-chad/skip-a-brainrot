-- The Roblox Backpack is the brainrot inventory.
-- This only bridges the "Store" prompt on a placed brainrot back to the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if prompt.Name ~= "StorePrompt" then return end
	if triggeringPlayer ~= player then return end
	local model = prompt.Parent
	local uid = model and model:GetAttribute("Uid")
	if uid then
		remotes.StoreBrainrot:FireServer(uid)
	end
end)
