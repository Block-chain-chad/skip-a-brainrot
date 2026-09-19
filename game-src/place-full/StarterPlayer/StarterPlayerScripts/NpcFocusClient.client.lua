-- NpcFocusClient -- the selection outline the reference clip puts on an NPC the
-- moment you are in range (2026-08-14). Ours had nothing: 42 walk-up prompts
-- across the world and no indication of WHICH thing the prompt belongs to, which
-- is why a prompt floating between Gino and his stall reads as ambiguous.
--
-- ONE Highlight, reused. Roblox caps the number of Highlights it will render
-- (16 by default) and silently drops the rest, so a per-NPC instance would work
-- in a quiet corner and quietly fail in a crowded camp. Adorning a single
-- instance also means "leaving" is one property write, not a search.
--
-- Driven off ProximityPromptService rather than per-prompt connections: it fires
-- for every prompt in the game, including ones spawned later (market stands,
-- plot pads), so nothing has to be registered and nothing can be missed.

local Players = game:GetService("Players")
local PPS = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local OUTLINE = Color3.fromRGB(255, 255, 255)
local FADE = 0.12

local hl, fadeToken = nil, 0

local function ensure()
	if hl and hl.Parent then return hl end
	hl = Instance.new("Highlight")
	hl.Name = "NpcFocus"
	hl.FillTransparency = 1            -- outline only; a fill washes out the art
	hl.OutlineColor = OUTLINE
	hl.OutlineTransparency = 1
	-- Occluded, NOT AlwaysOnTop: an always-on-top outline shows through walls and
	-- floors, so every NPC in the building lights up from outside it.
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = nil
	hl.Parent = player:WaitForChild("PlayerGui")
	return hl
end

-- Ramped by hand rather than tweened: Highlight is not a GuiObject, and this is
-- 8 frames of work either way.
local function fadeTo(target)
	fadeToken += 1
	local mine = fadeToken
	local from = hl.OutlineTransparency
	task.spawn(function()
		local t = 0
		while t < FADE do
			if mine ~= fadeToken or not hl then return end
			t += RunService.Heartbeat:Wait()
			local a = math.clamp(t / FADE, 0, 1)
			hl.OutlineTransparency = from + (target - from) * a
		end
		if mine == fadeToken and hl then
			hl.OutlineTransparency = target
			if target >= 1 then
				hl.Enabled = false
				hl.Adornee = nil
			end
		end
	end)
end

-- The thing worth outlining is the CHARACTER, not the building he stands in.
-- Walking up to the outermost Model looks right and isn't: these stalls ARE the
-- outermost model, so Marco's prompt lit up his whole shop -- counter, shelves,
-- stock and all -- which is what the first in-game screenshot showed. The
-- builders group the person in a child Model named "NPC" (the same convention
-- MerchantDialog's portrait relies on), so prefer that, then any model owning a
-- rig, and only then the whole thing.
--
-- The final fallbacks are deliberate: the Cellar, the Daily Wheel and a Market
-- Stand have no character in them, and there the building IS the interactable.
local function targetOf(prompt)
	local node, outer = prompt.Parent, nil
	while node and node ~= workspace do
		if node:IsA("Model") then outer = node end
		node = node.Parent
	end
	if outer then
		for _, d in ipairs(outer:GetDescendants()) do
			if d:IsA("Model") and d.Name == "NPC" then return d end
		end
		for _, d in ipairs(outer:GetDescendants()) do
			if d:IsA("Model") and (d:FindFirstChildOfClass("Humanoid")
				or d:FindFirstChild("HumanoidRootPart")) then return d end
		end
		return outer
	end
	local p = prompt.Parent
	return (p and p:IsA("BasePart")) and p or nil
end

PPS.PromptShown:Connect(function(prompt)
	local target = targetOf(prompt)
	if not target then return end
	ensure()
	hl.Adornee = target
	hl.Enabled = true
	fadeTo(0)
end)

PPS.PromptHidden:Connect(function()
	if hl and hl.Parent then fadeTo(1) end
end)

-- A prompt hidden by the object being destroyed (a claimed stand, a hatched egg)
-- never fires PromptHidden, which would strand the outline on a dead adornee.
RunService.Heartbeat:Connect(function()
	if hl and hl.Enabled and hl.Adornee and not hl.Adornee:IsDescendantOf(workspace) then
		hl.Enabled = false
		hl.Adornee = nil
	end
end)

print("NpcFocusClient online (outline on walk-up prompts)")
