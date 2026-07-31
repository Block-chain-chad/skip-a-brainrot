-- CatchRevealClient: turns a catch into a reveal.
--
-- Deliberately thin. All the presentation lives in CatchReveal; this only
-- decides WHETHER to show one, which is exactly the decision the phase-2 Robux
-- upgrade needs to change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CatchReveal = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CatchReveal"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local throwResult = remotes:WaitForChild("ThrowResult")

-- PHASE 2 SEAM: the purchasable "skip the animation" upgrade replaces this body
-- with a gamepass-ownership check plus the player's chosen rarities.
--
-- Skipping an ANIMATION is a pure presentation choice, so the client may own it
-- -- a client that lies about it gains nothing. The auto-sell half of that
-- upgrade is NOT the same and must never live here: a client that can say "sell
-- this catch" can say it about anything. Auto-sell belongs server-side in
-- ThrowHandler.revealCatch behind a verified MarketplaceService check.
local function shouldReveal(_result)
	return true
end

throwResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" or type(result.BrainrotName) ~= "string" then return end
	if not shouldReveal(result) then return end

	-- pcall: a broken reveal must never break the catch that produced it.
	pcall(CatchReveal.play, {
		Name = result.BrainrotName,
		Rarity = result.Rarity,
		RarityColor = result.RarityColor,
		Mutation = result.Mutation,
	})
end)
