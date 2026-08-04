-- CatchRevealClient: turns a catch into a reveal.
--
-- Deliberately thin. All the presentation lives in CatchReveal; this only
-- decides WHETHER to show one, which is exactly the decision the phase-2 Robux
-- upgrade needs to change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local CatchReveal = require(Modules:WaitForChild("CatchReveal"))
local PullCeremony = require(Modules:WaitForChild("PullCeremony"))
local BrainrotConfig = require(Modules:WaitForChild("BrainrotConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local throwResult = remotes:WaitForChild("ThrowResult")

-- within-tier odds for the ceremony's climbing counter: weights sum to 100,000
-- per tier, so "1 in N of its tier" with N = 100000/Weight is HONEST, not theater
local weightByName = {}
for _, e in ipairs(BrainrotConfig) do weightByName[e.Name] = e.Weight end

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
	local weight = weightByName[result.BrainrotName]
	local payload = {
		Name = result.BrainrotName,
		Rarity = result.Rarity,
		RarityColor = result.RarityColor,
		Mutation = result.Mutation,
		Serial = result.Serial,
		Exists = result.Exists,
		OddsN = weight and math.max(2, math.floor(100000 / weight + 0.5)) or nil,
	}
	-- Epic+ gets the full Pull ceremony (takeover / odds climb / burst / stamp);
	-- lower tiers keep the fast reveal untouched -- respect the grind.
	pcall(PullCeremony.play, payload)
end)
