-- ============================================================================
-- GamepassService -- server ownership + effects for the Robux gamepasses in
-- ReplicatedStorage.Modules.GamepassConfig.
--
-- Deliberately HEADLESS: no UI, no auto-prompts, nothing visible. It just:
--   (a) caches who owns which pass,
--   (b) keeps that fresh when a pass is bought mid-session, and
--   (c) exposes the accessors the game / a future shop UI will call:
--        GamepassService.Owns(player, key)        -> bool
--        GamepassService.CashMult(player)         -> number (1 if none owned)
--        GamepassService.LuckMult(player)         -> number
--        GamepassService.PowerMult(player)        -> number
--        GamepassService.ChargeMult(player)       -> number
--        GamepassService.HasFlag(player, flag)    -> bool  (AutoCollect / VIP)
--        GamepassService.Prompt(player, key)      -> opens the Robux buy prompt
--
-- Passes with GamepassId == 0 are skipped, so this stays inert and safe until
-- real ids are filled into GamepassConfig. Ownership cache matches the PetHandler
-- convention (keyed by Player, pcall'd, cleared on PlayerRemoving).
-- ============================================================================
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamepassConfig = require(ReplicatedStorage.Modules.GamepassConfig)

local GamepassService = {}

-- owned[player] = { [Key] = true }. Session cache; cleared on leave.
local owned = {}

local function refresh(player)
	local set = {}
	for _, g in ipairs(GamepassConfig.List) do
		if g.GamepassId and g.GamepassId > 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, g.GamepassId)
			end)
			if ok and has then set[g.Key] = true end
		end
	end
	owned[player] = set
end

function GamepassService.Owns(player, key)
	local set = owned[player]
	return set ~= nil and set[key] == true
end

-- product of a numeric effect across every owned pass (neutral 1 when none)
local function multOf(player, effectName)
	local set = owned[player]
	if not set then return 1 end
	local m = 1
	for _, g in ipairs(GamepassConfig.List) do
		if set[g.Key] and g.Effects and type(g.Effects[effectName]) == "number" then
			m = m * g.Effects[effectName]
		end
	end
	return m
end

function GamepassService.Mult(player, effectName) return multOf(player, effectName) end
function GamepassService.CashMult(player)   return multOf(player, "CashMult")   end
function GamepassService.LuckMult(player)   return multOf(player, "LuckMult")   end
function GamepassService.PowerMult(player)  return multOf(player, "PowerMult")  end
function GamepassService.ChargeMult(player) return multOf(player, "ChargeMult") end

function GamepassService.HasFlag(player, flag)
	local set = owned[player]
	if not set then return false end
	for _, g in ipairs(GamepassConfig.List) do
		if set[g.Key] and g.Effects and g.Effects[flag] == true then return true end
	end
	return false
end

-- Open the Robux purchase prompt (call from a future shop UI / remote). No-op
-- for a pass that has not been created yet.
function GamepassService.Prompt(player, key)
	local g = GamepassConfig.ByKey[key]
	if g and g.GamepassId and g.GamepassId > 0 then
		MarketplaceService:PromptGamePassPurchase(player, g.GamepassId)
	end
end

function GamepassService.Init()
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(refresh, p) end
	Players.PlayerAdded:Connect(function(p) task.spawn(refresh, p) end)
	Players.PlayerRemoving:Connect(function(p) owned[p] = nil end)

	-- keep the cache fresh the instant a pass is bought this session
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
		if not wasPurchased then return end
		local g = GamepassConfig.ByGamepassId(gamepassId)
		if g then
			owned[player] = owned[player] or {}
			owned[player][g.Key] = true
		end
	end)

	print("GamepassService online (" .. #GamepassConfig.List .. " passes configured, headless)")
end

return GamepassService
