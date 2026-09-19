local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PDM = require(script.Parent.PlayerDataManager)
local EmeraldService = require(script.Parent.EmeraldService)

local M = {}
local PRODUCTS = {}  -- [productId] = { Type, Amount }

function M.Register(productId, def)
	if productId == 0 then return end  -- placeholder: inert until the user creates real ids
	assert(PRODUCTS[productId] == nil, "duplicate product id " .. productId)
	PRODUCTS[productId] = def
end

local function grant(player, data, def)
	-- General hook: a product can carry its own Grant(player, data) -> bool. Used by
	-- StealService (Type="Steal") so ProductRegistry never has to require it back --
	-- the same non-throw-after-mutation contract as the Emeralds branch applies.
	if def.Grant then return def.Grant(player, data) == true end
	if def.Type == "Emeralds" then
		-- Award returns false (never throws post-mutation) on invalid amounts. A
		-- false must NOT reach the ReceiptLog: once a PurchaseId is logged, the
		-- dedupe branch answers PurchaseGranted forever with nothing credited.
		return EmeraldService.Award(player, def.Amount, "robux:" .. tostring(def.Amount)) == true
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
	-- the assumption nothing was granted. EmeraldService.Award upholds this by
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
		-- emeralds AND the log entry vanish together -- a Roblox retry next session
		-- re-grants correctly. So NotProcessedYet is safe AND self-consistent.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function M.Init()
	-- Roblox allows exactly ONE ProcessReceipt per game. This is it. Add new
	-- purchasables via M.Register, never a second assignment.
	MarketplaceService.ProcessReceipt = M.ProcessReceipt

	-- Emerald packs. The catalog moved to ReplicatedStorage.Modules.EmeraldPackConfig
	-- so the shop can render prices and amounts from the SAME rows that get
	-- registered here -- see that file for how to create the products.
	--
	-- A pack whose ProductId is still 0 is skipped outright rather than registered
	-- under id 0: Register would otherwise stack all four unconfigured packs on one
	-- bogus key, and the last one written would win for any receipt that ever
	-- arrived carrying it.
	local EmeraldPackConfig = require(ReplicatedStorage.Modules.EmeraldPackConfig)
	local live = 0
	for _, pack in ipairs(EmeraldPackConfig.List) do
		if EmeraldPackConfig.IsLive(pack) then
			M.Register(pack.ProductId, { Type = "Emeralds", Amount = pack.Amount })
			live += 1
		end
	end
	-- The daily wheel's paid spin. Grant runs the SAME WheelHandler.TrySpin path the
	-- free daily and the in-world prompt use, with `paid` set -- so a bought spin
	-- cannot roll from a different table, skip a payout, or diverge from the free one
	-- as the wheel is retuned. It also does not stamp LastSpinAt, so buying a spin
	-- never burns the free daily the player still had.
	--
	-- Required lazily, inside Grant: ProductRegistry is required at server boot and
	-- WheelHandler pulls in SeasonPassHandler, so a top-level require here would widen
	-- the boot-time module graph for something only needed when a receipt arrives.
	local WheelConfig = require(ReplicatedStorage.Modules.WheelConfig)
	local wheelLive = WheelConfig.IsPaidSpinLive()
	if wheelLive then
		M.Register(WheelConfig.PAID_SPIN.ProductId, {
			Type = "WheelSpin",
			Grant = function(player, _data)
				return require(script.Parent.WheelHandler).TrySpin(player, true) == true
			end,
		})
	end

	print(("ProductRegistry online (%d/%d emerald packs live, paid wheel spin %s)")
		:format(live, #EmeraldPackConfig.List,
			wheelLive and ("live @ R$" .. WheelConfig.PAID_SPIN.RobuxPrice) or "NOT CREATED (ProductId 0)"))
end

return M
