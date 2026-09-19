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
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GamepassConfig = require(ReplicatedStorage.Modules.GamepassConfig)
-- for IsCreator; a config module, so no cycle back to here
local SeasonConfig = require(ReplicatedStorage.Modules.SeasonConfig)

local GamepassService = {}

--[[ PASSES THE CREATORS OWN OUTRIGHT (2026-08-09, owner's request: permanent VIP).

Unlike the Studio-only override below, this holds on a LIVE server too -- which is the
point. The owner should not have to buy their own pass to have the thing they built, and
it should follow them into the real game rather than only working in Studio.

Eligibility is SeasonConfig.IsCreator, the same check the admin tag runs on: it resolves
the place owner automatically (user-owned places only -- a group's CreatorId is the group
id and matches nobody) and takes co-creators from SeasonConfig.CREATOR_IDS.

An allowlist of KEYS rather than a blanket "creators own everything", deliberately: a
creator silently holding 2x Cash can no longer tell whether that multiplier is wired up
correctly for a paying player, and this file has already shipped one round of passes
that took money and did nothing.
]]
local CREATOR_PASSES = { VIP = true }

local function creatorOwns(player, key)
	if not CREATOR_PASSES[key] then return false end
	local ok, isCreator = pcall(SeasonConfig.IsCreator, player and player.UserId)
	return ok and isCreator == true
end

-- owned[player] = { [Key] = true }. Session cache; cleared on leave.
local owned = {}

--[[ STUDIO-ONLY TEST OVERRIDE (2026-08-09).

Every GamepassId is still 0, so nobody owns anything and none of the pass EFFECTS
can be play-tested -- not the cash and luck multipliers, not the auto-skip gate, not
the VIP scooter. Chicken and egg: you would have to create and buy a real pass to
find out whether the thing it sells works.

Set ServerStorage's DevPasses attribute to a comma-separated list of Keys and this
session treats them as owned:

    ServerStorage:SetAttribute("DevPasses", "VIP,AutoSkip")
    ServerStorage:SetAttribute("DevPasses", "all")     -- every pass in the config

STUDIO ONLY, checked here rather than trusted to the caller. A live server ignores
the attribute completely, so this can never comp a pass in production even if
something sets it. Clients cannot write ServerStorage at all, so there is no client
route to it either.

Read live rather than cached: flip it mid-session and the next check sees it, which
is what makes "buy" and "do not buy" testable back to back without a restart.
]]
local function devOwns(key)
	if not RunService:IsStudio() then return false end
	local raw = ServerStorage:GetAttribute("DevPasses")
	if type(raw) ~= "string" or raw == "" then return false end
	if raw:lower() == "all" then return true end
	for entry in raw:gmatch("[^,%s]+") do
		if entry == key then return true end
	end
	return false
end

--[[ WHO WANTS TELLING WHEN THE CACHE IS ACTUALLY FILLED.

refresh() makes one blocking web call PER PASS. With eight live ids that is eight round
trips, and anything that guessed at a fixed delay before reading the result was racing
it -- ShopService pushed the shop on a 2s timer, which the checks routinely outlast, so
the panel drew a BUY button for a pass the player already owned. Clicking it did
nothing, because the server correctly refuses to prompt for something you own.

Invisible while every id was 0 (nobody owned anything, so an empty answer was the right
answer either way) and immediate the moment the ids went live.
]]
local refreshedCallbacks = {}

function GamepassService.OnRefreshed(fn)
	if type(fn) == "function" then table.insert(refreshedCallbacks, fn) end
end

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
	-- pcall'd per listener: one bad subscriber must not stop the others being told
	for _, fn in ipairs(refreshedCallbacks) do
		if player.Parent then pcall(fn, player) end
	end
end

function GamepassService.Owns(player, key)
	if devOwns(key) or creatorOwns(player, key) then return true end
	local set = owned[player]
	return set ~= nil and set[key] == true
end

-- product of a numeric effect across every owned pass (neutral 1 when none)
local function multOf(player, effectName)
	local set = owned[player] or {}
	local m = 1
	for _, g in ipairs(GamepassConfig.List) do
		if (set[g.Key] or devOwns(g.Key) or creatorOwns(player, g.Key))
			and g.Effects and type(g.Effects[effectName]) == "number" then
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
	local set = owned[player] or {}
	for _, g in ipairs(GamepassConfig.List) do
		if (set[g.Key] or devOwns(g.Key) or creatorOwns(player, g.Key))
			and g.Effects and g.Effects[flag] == true then return true end
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
			-- Tell the subscribers too, not just the cache. A pass that raises a CAP
			-- (the pet follow slots) is invisible until whoever publishes that cap
			-- recomputes it -- without this the player would have paid and still see
			-- the slot locked until they rejoined.
			for _, fn in ipairs(refreshedCallbacks) do
				if player.Parent then pcall(fn, player) end
			end
		end
	end)

	print("GamepassService online (" .. #GamepassConfig.List .. " passes configured, headless)")
end

return GamepassService
