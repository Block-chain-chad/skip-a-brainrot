-- EmeraldPackConfig -- the Robux gem packs (developer products).
-- 2026-08-13: the currency's DISPLAY name is EMERALDS now (was "emeralds"). Module
-- name, keys and ProductIds unchanged -- the four products on the Roblox site
-- are still titled "... of Emeralds" and only the OWNER can rename them there.
--
-- SHARED so the shop can render them. These four used to be two locals inside
-- ProductRegistry.Init, which meant no UI could name a pack, price it, or say how
-- many emeralds it gives without repeating the numbers -- and a repeated price is a
-- price that eventually disagrees with the one Roblox charges.
--
-- >>> TO ACTIVATE A PACK <<<
--   1. Creator Dashboard: Creations > (this game) > Monetization >
--      Developer Products > Create a Developer Product
--   2. Set its price to RobuxPrice below (Roblox charges what the PRODUCT says,
--      not what this file says -- this number is only what the shop DISPLAYS, so
--      if the two ever disagree the shop is lying to the player).
--   3. Copy the Product ID and paste it as ProductId, replacing the 0.
--
-- ProductId == 0 means "not created yet", the same sentinel GamepassConfig uses:
-- ProductRegistry never registers it and the shop shows it as unavailable rather
-- than as a button that takes a click and does nothing.
--[[ >>> THE PACKS ARE LIVE <<<  (2026-08-10)

The four ids below were re-created as DEVELOPER PRODUCTS and are filled in. Each one was
verified against Roblox before being pasted here, with GetProductInfo:

-- ⚠ THE LIVE PRODUCTS ARE STILL NAMED "... of Darrels" ON ROBLOX.
-- The currency was renamed to Emeralds in code and UI on 2026-08-15, but a
-- dev product's name lives on the Roblox website, not in this file, so only
-- the place owner can change it. The four names below are recorded EXACTLY
-- as they still appear in the purchase prompt -- do not "fix" them here.
  3701622469  Pouch of Darrels   R$99    InfoType.Product OK / InfoType.GamePass errors
  3701623028  Bag of Darrels     R$199   InfoType.Product OK / InfoType.GamePass errors
  3701623573  Crate of Darrels   R$399   InfoType.Product OK / InfoType.GamePass errors
  3701623991  Hoard of Darrels   R$899   InfoType.Product OK / InfoType.GamePass errors

That check is the point, and it is what the previous attempt failed. The ids supplied on
2026-08-09 -- Pouch 1940389301, Bag 1941487308, Crate 1940629410, Hoard 1941643413 --
looked like ids and were pasted like ids, but every one of them resolved as a GAME PASS.
As passes they could not have worked, for two independent reasons:

  * a pass is a ONE-TIME entitlement, so a player could buy "400 Emeralds" exactly ONCE in
    their life and Roblox would block the second attempt with "you already own this item";
  * there is no receipt. MarketplaceService.ProcessReceipt -- the callback ProductRegistry
    uses to grant emeralds, and the ONLY thing Roblox accepts as proof of payment -- fires
    for developer products alone. A pass purchase would have taken the Robux and granted
    nothing at all.

So: ANY id pasted below must answer to InfoType.Product. An id that only answers to
InfoType.GamePass belongs in GamepassConfig, not here, however right its name and price
look. The four OLD pass versions above should be off sale so nobody buys one by accident.

The RobuxPrice column is display only -- Roblox charges what the PRODUCT says. The prices
above were read back off Roblox and match this file; if you ever change one, change it on
the dashboard too or the shop starts lying about the price.
]]
local M = {}

M.List = {
	-- Name is the player-facing card title: the currency is GEMS in every label
	-- (2026-09-18). Keys, ids and amounts are untouched.
	{ Key = "Pack80",   ProductId = 3701622469, Amount = 80,   RobuxPrice = 99,  Name = "Pouch of Gems" },
	{ Key = "Pack180",  ProductId = 3701623028, Amount = 180,  RobuxPrice = 199, Name = "Bag of Gems" },
	{ Key = "Pack400",  ProductId = 3701623573, Amount = 400,  RobuxPrice = 399, Name = "Crate of Gems", Best = true },
	{ Key = "Pack1000", ProductId = 3701623991, Amount = 1000, RobuxPrice = 899, Name = "Hoard of Gems" },
}

M.ByKey = {}
for _, p in ipairs(M.List) do M.ByKey[p.Key] = p end

-- 0 is the not-created-yet sentinel and must never match, or a lookup of 0 would
-- return whichever unconfigured pack happens to sit first and grant it.
function M.ByProductId(id)
	if type(id) ~= "number" or id <= 0 then return nil end
	for _, p in ipairs(M.List) do
		if p.ProductId == id then return p end
	end
	return nil
end

function M.IsLive(p): boolean
	return type(p) == "table" and type(p.ProductId) == "number" and p.ProductId > 0
end

return M
