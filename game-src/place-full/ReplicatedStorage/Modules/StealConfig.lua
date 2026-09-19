-- StealConfig -- shared knobs for the PLOT RAID mechanic: pay Robux to steal a
-- brainrot off another player's plot. SHARED so the client (RaidClient) and the
-- server (StealService) read the same numbers.
--
-- >>> INERT UNTIL LIVE <<<
-- ProductId is 0 until you create the Developer Product on the Creator Dashboard
-- (Creations > this game > Monetization > Developer Products > Create a Product,
-- price it 39 Robux), then paste its id below. While it is 0, StealService never
-- prompts a purchase and RaidClient never shows the steal prompt to normal players
-- -- exactly the "0 = not created yet" convention the emerald packs and gamepasses
-- already use.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SeasonConfig = require(ReplicatedStorage.Modules.SeasonConfig) -- IsCreator, for the free test path

local M = {}

-- PAY-PER-STEAL PRICING, by the RARITY of the pet you're stealing. Each price is a
-- SEPARATE Developer Product (a Robux product's price is fixed on the dashboard, so
-- a different price = a different product). Create all three, paste each id below;
-- 0 = not created yet, and that tier stays inert. The steal flow prompts whichever
-- product matches the target brainrot's rarity.
M.Tiers = {
	Default = { ProductId = 0, RobuxPrice = 79 },   -- everything Common..Legendary/Mythic
	Secret  = { ProductId = 0, RobuxPrice = 499 },  -- Secret-rarity brainrots
	God     = { ProductId = 0, RobuxPrice = 1999 }, -- God-rarity brainrots
}

-- Which price tier applies to a brainrot of this rarity.
function M.TierFor(rarity)
	if rarity == "God" then return M.Tiers.God end
	if rarity == "Secret" then return M.Tiers.Secret end
	return M.Tiers.Default
end

function M.TierIsLive(tier)
	return tier ~= nil and type(tier.ProductId) == "number" and tier.ProductId > 0
end

-- After a SUCCESSFUL steal the thief cannot raid again for this long (seconds).
-- 3 minutes -- owner's call, 2026-08-18. The clock starts the moment a pet is
-- actually taken, not when the purchase prompt opens.
M.CooldownSeconds = 180

-- SHIELD: the owner is safe while physically standing on their own plot. A raid
-- cannot be STARTED against a plot whose owner's character is within this many
-- studs (horizontal) of the plot's Campfire. Checked at initiation only -- once a
-- purchase is committed the steal still completes, so stepping on the plot mid-
-- purchase does not rob the payer of their Robux.
M.ShieldRadius = 28

-- ProximityPrompt feel on each stealable brainrot.
M.HoldDuration = 0.6
M.MaxDistance = 12
M.ActionText = "Steal"
M.ObjectText = "Brainrot"

-- RARE fallback. The Robux prompt is async (~1-2s); if by the time it clears the
-- reserved pet is gone AND the plot has no other stealable pet (owner stored or
-- left everything in that window), the thief is handed this many emeralds instead
-- so the purchase is never spent for literally nothing. 0 disables it.
M.ConsolationEmeralds = 20

-- Let the game creator(s) run the WHOLE flow for FREE in Studio, with no live
-- product, so the mechanic can be tested before the 39 R$ product exists. Only
-- applies to SeasonConfig.IsCreator user(s). Set false before launch if you don't
-- want creators raiding for free.
M.CreatorFreeTest = true

-- True if ANY tier has a live product (decides whether prompts show at all).
function M.IsLive()
	for _, t in pairs(M.Tiers) do
		if M.TierIsLive(t) then return true end
	end
	return false
end

-- May THIS user act on the mechanic at all right now (live product, or a creator
-- while the free test is on)? Used by both sides to gate the prompt/flow.
function M.CanUse(userId)
	if M.IsLive() then return true end
	return M.CreatorFreeTest == true and SeasonConfig.IsCreator(userId) == true
end

return M
