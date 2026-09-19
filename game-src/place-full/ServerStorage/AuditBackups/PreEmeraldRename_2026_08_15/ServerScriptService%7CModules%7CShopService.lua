-- ShopService -- the Robux shop's server half: open purchase prompts, and tell the
-- client which passes it already owns.
--
-- IT SELLS NOTHING ITSELF. A pass prompt goes through GamepassService.Prompt and a
-- pack prompt through MarketplaceService; the grant for a pack is ProductRegistry's
-- ProcessReceipt, which is the only thing Roblox will accept as proof of payment.
-- Nothing here may ever grant anything, because a client asked it to.
--
-- INERT UNTIL THE IDS ARE REAL. Every pass and pack ships with its id at 0, the
-- "not created yet" sentinel. Prompt() no-ops on those, this module refuses them
-- before that, and the panel draws them as unavailable -- three independent layers,
-- because the failure they prevent (a player pays and receives nothing) is the one
-- failure in this whole game that costs real money.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GamepassService = require(ServerScriptService.Modules.GamepassService)
local GamepassConfig = require(ReplicatedStorage.Modules.GamepassConfig)
local DarrelPackConfig = require(ReplicatedStorage.Modules.DarrelPackConfig)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local ShopService = {}
local inited = false

-- One prompt per player per second. Roblox already serialises its own purchase
-- dialog, but a held-down button would queue prompts behind it.
local PROMPT_COOLDOWN = 1
local lastPrompt = {}

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = remotes
	end
	return r
end
local promptRemote = getRemote("ShopPrompt", "RemoteEvent")
local stateRemote = getRemote("ShopState", "RemoteEvent")

function ShopService.SendState(player)
	local ownedPasses = {}
	for _, g in ipairs(GamepassConfig.List) do
		ownedPasses[g.Key] = GamepassService.Owns(player, g.Key)
	end
	stateRemote:FireClient(player, { Owned = ownedPasses })
end

function ShopService.Init()
	if inited then return end
	inited = true

	promptRemote.OnServerEvent:Connect(function(player, kind, key)
		if typeof(kind) ~= "string" or typeof(key) ~= "string" then return end
		local now = os.clock()
		if now - (lastPrompt[player] or 0) < PROMPT_COOLDOWN then return end
		lastPrompt[player] = now

		if kind == "pass" then
			local g = GamepassConfig.ByKey[key]
			if not g then return end
			-- already owned: a second prompt would only offer them a refund dialog
			if GamepassService.Owns(player, key) then return end
			GamepassService.Prompt(player, key)   -- itself a no-op while the id is 0

		elseif kind == "pack" then
			local pack = DarrelPackConfig.ByKey[key]
			if not (pack and DarrelPackConfig.IsLive(pack)) then return end
			MarketplaceService:PromptProductPurchase(player, pack.ProductId)
		end
	end)

	-- Ownership changes the moment a pass is bought, and the shop is the surface the
	-- player is looking at when it happens -- so re-push rather than make them
	-- reopen it to see OWNED.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _, wasPurchased)
		if not wasPurchased then return end
		-- after GamepassService's own handler has updated its cache
		task.defer(function()
			if player.Parent then ShopService.SendState(player) end
		end)
	end)

	-- THE REAL SIGNAL, not a timer. GamepassService tells us the moment a player's
	-- ownership cache is filled; the 2s guess below is kept only as a first paint for a
	-- client that opens the shop instantly, and is superseded by this the moment the
	-- checks land. With eight live passes the timer alone was losing the race and the
	-- panel offered to sell people things they already owned.
	if type(GamepassService.OnRefreshed) == "function" then
		GamepassService.OnRefreshed(function(player)
			if player.Parent then ShopService.SendState(player) end
		end)
	end

	local function onJoin(player)
		task.spawn(function()
			task.wait(2)   -- early paint; the OnRefreshed hook above is what settles it
			if player.Parent then ShopService.SendState(player) end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
	Players.PlayerRemoving:Connect(function(p) lastPrompt[p] = nil end)

	local livePasses = 0
	for _, g in ipairs(GamepassConfig.List) do
		if (g.GamepassId or 0) > 0 then livePasses += 1 end
	end
	local livePacks = 0
	for _, p in ipairs(DarrelPackConfig.List) do
		if DarrelPackConfig.IsLive(p) then livePacks += 1 end
	end
	print(("ShopService online (%d/%d passes and %d/%d packs have real ids)")
		:format(livePasses, #GamepassConfig.List, livePacks, #DarrelPackConfig.List))
end

return ShopService
