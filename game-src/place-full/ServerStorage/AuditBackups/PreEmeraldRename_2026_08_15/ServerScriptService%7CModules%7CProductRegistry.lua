local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PDM = require(script.Parent.PlayerDataManager)
local DarrelService = require(script.Parent.DarrelService)

local M = {}
local PRODUCTS = {}  -- [productId] = { Type, Amount }

function M.Register(productId, def)
	if productId == 0 then return end  -- placeholder: inert until the user creates real ids
	assert(PRODUCTS[productId] == nil, "duplicate product id " .. productId)
	PRODUCTS[productId] = def
end

local function grant(player, data, def)
	if def.Type == "Darrels" then
		-- Award returns false (never throws post-mutation) on invalid amounts. A
		-- false must NOT reach the ReceiptLog: once a PurchaseId is logged, the
		-- dedupe branch answers PurchaseGranted forever with nothing credited.
		return DarrelService.Award(player, def.Amount, "robux:" .. tostring(def.Amount)) == true
	end
	return false
end

-- The actual receipt-processing logic, kept as a standalone function so it can
-- be unit-tested (and reused by Task 12's idempotence test) without going
-- through MarketplaceService. M.Init() assigns THIS SAME function to
-- MarketplaceService.ProcessReceipt -- see the comment there for why that
-- assignment must never be duplicated anywhere else in the game.
function M.ProcessReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local data = PDM.Get(player)
	if not data or data.__noSave then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local key = tostring(info.PurchaseId)
	if table.find(data.ReceiptLog, key) then
		-- grant already in memory; only confirm once it has persisted at least once
		local saved = PDM.Save(player)
		if saved then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		else
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	local def = PRODUCTS[info.ProductId]
	if not def then
		warn("[ProductRegistry] unknown product id " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- pcall is defense-in-depth only: grant implementations must never throw
	-- AFTER mutating data, because a caught failure returns NotProcessedYet on
	-- the assumption nothing was granted. DarrelService.Award upholds this by
	-- pcall'ing its own post-mutation notify path.
	local ok, granted = pcall(grant, player, data, def)
	if not ok then
		warn("[ProductRegistry] grant threw for product " .. tostring(info.ProductId) .. ": " .. tostring(granted))
	end
	if not ok or granted ~= true then return Enum.ProductPurchaseDecision.NotProcessedYet end
	table.insert(data.ReceiptLog, key)
	if #data.ReceiptLog > 50 then table.remove(data.ReceiptLog, 1) end
	local saved = PDM.Save(player)
	if not saved then
		-- Grant + log are in-memory only. If this session never saves, both the
		-- darrels AND the log entry vanish together -- a Roblox retry next session
		-- re-grants correctly. So NotProcessedYet is safe AND self-consistent.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function M.Init()
	-- Roblox allows exactly ONE ProcessReceipt per game. This is it. Add new
	-- purchasables via M.Register, never a second assignment.
	MarketplaceService.ProcessReceipt = M.ProcessReceipt

	-- Darrel packs. The catalog moved to ReplicatedStorage.Modules.DarrelPackConfig
	-- so the shop can render prices and amounts from the SAME rows that get
	-- registered here -- see that file for how to create the products.
	--
	-- A pack whose ProductId is still 0 is skipped outright rather than registered
	-- under id 0: Register would otherwise stack all four unconfigured packs on one
	-- bogus key, and the last one written would win for any receipt that ever
	-- arrived carrying it.
	local DarrelPackConfig = require(ReplicatedStorage.Modules.DarrelPackConfig)
	local live = 0
	for _, pack in ipairs(DarrelPackConfig.List) do
		if DarrelPackConfig.IsLive(pack) then
			M.Register(pack.ProductId, { Type = "Darrels", Amount = pack.Amount })
			live += 1
		end
	end
	print(("ProductRegistry online (%d/%d darrel packs live)")
		:format(live, #DarrelPackConfig.List))
end

return M
