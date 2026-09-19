-- NpcLifeClient -- wires NpcLife (ReplicatedStorage.Modules.NpcKit.NpcLife) to
-- the real services. This is the ONLY per-frame connection the NPC-01 system
-- owns, and it is inert until a model carries the `NpcBody` tag (D-7):
--   * no workspace scans -- the registry fills from CollectionService only
--   * with zero tagged bodies the Heartbeat callback is one comparison
--   * legacy NPC rigs (Humanoid, no tag) are never touched
--   * every hook is guarded; a missing MerchantDialogUI just disables talk detection
--
-- Installed at Phase 3 step 8 behind its STOP gate; until then this file only
-- exists on disk (game-src/npc-kit) and in the harness.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local kit = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NpcKit")
local NpcLife = require(kit:WaitForChild("NpcLife"))
local modules = {
	RigSpec = require(kit:WaitForChild("NpcRigSpec")),
	FaceConfig = require(kit:WaitForChild("NpcFaceConfig")),
	MotionConfig = require(kit:WaitForChild("NpcMotionConfig")),
	LodProfiles = require(kit:WaitForChild("NpcLodProfiles")),
	Motion = require(kit:WaitForChild("NpcMotion")),
}

-- synchronised clock so every client sees the same phase; os.clock if unavailable
local function now()
	local ok, t = pcall(function() return Workspace:GetServerTimeNow() end)
	if ok and type(t) == "number" then return t end
	return os.clock()
end

local function playerHead()
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if head then return head.Position end
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then return hrp.Position + Vector3.new(0, 1.5, 0) end
	return nil
end

local life = NpcLife.new({
	CollectionService = CollectionService,
	Workspace = Workspace,
	Players = Players,
	camera = function() return Workspace.CurrentCamera end,
	playerHead = playerHead,
	now = now,
	modules = modules,
	log = print,
})
life:start()

-- one Heartbeat; inert when nothing is registered
RunService.Heartbeat:Connect(function(dt)
	life:step(dt, now())
end)

-- walk-up + conversation hooks (no edits to the locked UI files)
ProximityPromptService.PromptShown:Connect(function(prompt) life:onPromptShown(prompt) end)
ProximityPromptService.PromptHidden:Connect(function(prompt) life:onPromptHidden(prompt) end)
ProximityPromptService.PromptTriggered:Connect(function(prompt) life:onPromptTriggered(prompt, now()) end)

-- MerchantDialog builds PlayerGui.MerchantDialogUI.DialogRoot on the FIRST conversation,
-- which may be minutes into a session: hook it whenever it appears, never wait on a timer,
-- and never assume it exists (a missing UI only disables talk detection).
local function hookDialog(dialogUi)
	local root = dialogUi:FindFirstChild("DialogRoot") or dialogUi:WaitForChild("DialogRoot", 30)
	if not root then return end
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		life:onDialogVisible(root.Visible, now())
	end)
end
task.spawn(function()
	local gui = player:WaitForChild("PlayerGui")
	local existing = gui:FindFirstChild("MerchantDialogUI")
	if existing then hookDialog(existing) end
	gui.ChildAdded:Connect(function(child)
		if child.Name == "MerchantDialogUI" then task.defer(hookDialog, child) end
	end)
end)
