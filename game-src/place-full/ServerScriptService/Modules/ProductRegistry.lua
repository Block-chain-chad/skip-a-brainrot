local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
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

	-- Darrel packs (user creates dev products on roblox.com, then replaces these zeros):
	local PACK_IDS = { 0, 0, 0, 0 }           -- <- fill with real dev product ids
	local PACK_AMOUNTS = { 80, 180, 400, 1000 }
	for i, id in ipairs(PACK_IDS) do
		M.Register(id, { Type = "Darrels", Amount = PACK_AMOUNTS[i] })
	end
end

return M
