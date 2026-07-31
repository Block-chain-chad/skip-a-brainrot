-- LimitedStock: a hard, universe-wide mint cap for the rarest brainrots.
--
-- Why a cap and not just a smaller FixedChance:
--   A probability does not create scarcity, throughput does. At 1 in 1,000,000 an
--   endgame player needs ~550 hours of perfect throws per catch -- which reads as
--   "nobody has it" at 50 players and "fifteen a day" at 5,000. Lowering the odds only
--   moves that threshold. A cap is the only thing that holds no matter how big the game
--   gets, because it bounds the TOTAL rather than the rate.
--
-- The odds and the cap do different jobs and both matter: FixedChance decides how long
-- the window stays open, MAX decides how many exist once it closes.
--
-- Counts MINTS, not current holders. Selling or trading a Pete never frees a slot --
-- "only 5 were ever created" is the property we want, and it survives players quitting.

local DataStoreService = game:GetService("DataStoreService")

-- [config entry Name] = how many may EVER be granted, across every server, forever.
-- Ladder tracks the Secret tier's internal power ladder: the weakest Secret is
-- the most common trophy, the strongest is nearly one-of-a-kind. Once a cap is
-- hit the name is trade-only forever -- that is the point.
-- Must stay in exact lockstep with SupplySchedule.CAPPED (the shared name set
-- the Index badges read).
-- Roster rebuilt 2026-07-25: these are the 11 Secrets of the new pack roster,
-- ordered by their income ladder so the weakest Secret is the most common
-- trophy and the strongest is nearly one-of-a-kind. Pete sits alone in God tier.
local MAX = {
	["Tralalero Tralala"] = 500,
	["Los Tralaleritos"] = 400,
	["La Vacca Saturno Saturnita"] = 320,
	["Las Vaquitas Saturnitas"] = 250,
	["La Grande Combinasion"] = 200,
	["Los Combinasionas"] = 150,
	["Matteo"] = 120,
	["Odin Din Din Dun"] = 90,
	["Secret Lucky Block"] = 65,
	["Brainrot God Lucky Block"] = 45,
	["Admin Lucky Block"] = 25,
	["Secret Pete"] = 5,
}

local store = DataStoreService:GetDataStore("BrainrotSkip_LimitedStock_v1")
local REFRESH_SECONDS = 60

local M = {}
M.MAX = MAX

-- [name] = minted count. Deliberately allowed to be stale: it only gates the cheap
-- non-yielding pre-check. TryClaim is the authority.
local minted = {}

function M.IsLimited(name)
	return MAX[name] ~= nil
end

-- Cheap and NEVER yields -- safe to call on the throw path. May be stale by up to
-- REFRESH_SECONDS, and returns false while the count is still unknown, so a claim can
-- still be attempted and correctly refused by TryClaim.
function M.SoldOut(name)
	local cap = MAX[name]
	if not cap then return false end
	local have = minted[name]
	if not have then return false end
	return have >= cap
end

-- Authoritative reservation. YIELDS (UpdateAsync), so call it only when a roll has
-- actually hit -- at 1e-6 that is close to never, which is what keeps this off the
-- per-throw budget entirely.
--
-- UpdateAsync is atomic per key across every server, so two players hitting the last
-- slot in the same instant cannot both win: the second transform sees the first's write.
function M.TryClaim(name)
	local cap = MAX[name]
	if not cap then return true end   -- not a limited item: nothing to reserve

	local granted = false
	local ok, err = pcall(function()
		store:UpdateAsync(name, function(current)
			current = tonumber(current) or 0
			if current >= cap then
				granted = false
				return nil          -- nil cancels the write: no wasted budget on a refusal
			end
			granted = true
			return current + 1
		end)
	end)

	if not ok then
		-- Fail CLOSED. An outage that let claims through would over-mint permanently and
		-- there is no way to un-mint; refusing costs one player one roll. Loud on purpose.
		warn(("[LimitedStock] UpdateAsync failed for %q (%s) -- refusing the claim to protect the cap")
			:format(name, tostring(err)))
		return false
	end

	if granted then
		minted[name] = (minted[name] or 0) + 1
		print(("[LimitedStock] MINTED %q -- %d of %d now exist"):format(name, minted[name], cap))
	end
	return granted
end

-- nil while the count has not been read yet
function M.Remaining(name)
	local cap = MAX[name]
	if not cap then return nil end
	local have = minted[name]
	if not have then return nil end
	return math.max(cap - have, 0)
end

function M.Init()
	task.spawn(function()
		while true do
			for name in pairs(MAX) do
				local ok, v = pcall(function() return store:GetAsync(name) end)
				if ok then minted[name] = tonumber(v) or 0 end
			end
			task.wait(REFRESH_SECONDS)
		end
	end)
	print("LimitedStock online")
end

return M
