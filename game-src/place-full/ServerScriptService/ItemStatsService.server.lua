-- ItemStatsService -- the read-only supply + price window the Brainrot Index asks.
--
-- WHY A REMOTEFUNCTION RATHER THAN REPLICATED STATE:
-- exists counts and camp prices move constantly, and only matter for the ~20 rows
-- a player is actually looking at. Replicating all 214 classes (x4 mutations) to
-- every client would cost far more than answering the handful that are on screen.
--
-- CONTRACT
--   local map, meta = GetItemStats:InvokeServer({ { Name = "X", Mutation = "Golden" }, ... })
--
--   map[key] = { Tracked = bool, Minted = n?, Exists = n?, Price = n?, Samples = n }
--     key     = Name .. "|" .. (Mutation or "")
--     Tracked = whether the class is worth a serial at all (Legendary+ or mutated).
--               When false the UI should show no supply line, because none exists.
--     Minted / Exists = nil while the mint registry is cold or its DataStore is
--               down. The UI must HIDE the line in that case, never print a
--               confident zero -- "0 exist" is a much worse lie than saying nothing.
--     Price   = 7-day MEDIAN of what players ACTUALLY PAID at the stalls. nil until
--               MinSamples counterparty pairs have traded. Not an official value.
--     Samples = pairs behind Price. Always present (may be 0) so the UI can say
--               "3 of 5 sales needed" honestly instead of inventing a number.
--   meta = { WindowDays, MinSamples } -- so the client's copy cannot drift from
--          PriceIndex's real tuning.
--
--   A nil map means THROTTLED, not "no data". The client must not cache that.
--
-- Standalone Script on purpose: both modules it reads are self-starting, so this
-- needs no ordering against Main's Init sequence and stays out of the wiring list.
-- Every call here is non-yielding, so the invoke returns within the frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MintRegistry   = require(ServerScriptService.Modules.MintRegistry)
local PriceIndex     = require(ServerScriptService.Modules.PriceIndex)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local Mutations      = require(ReplicatedStorage.Modules.MutationConfig)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getItemStats = remotes:WaitForChild("GetItemStats")

local MAX_ITEMS  = 40    -- one Index page asks for at most 2 classes per row
local BUCKET_MAX = 6     -- burst: opening the panel then paging a few times fast
local REFILL     = 1.5   -- tokens regained per second

-- Only names that really exist may be asked about. Without this, a spammed request
-- could mint registry cache keys (and the DataStore reads behind them) for
-- arbitrary strings.
local rarityOf = {}
for _, e in ipairs(BrainrotConfig) do rarityOf[e.Name] = e.Rarity end
local validMutation = {}
for _, m in ipairs(Mutations.List) do validMutation[m.Name] = true end

local META = { WindowDays = PriceIndex.WindowDays, MinSamples = PriceIndex.MinSamples }

local tokens, lastSeen = {}, {}
Players.PlayerRemoving:Connect(function(player)
	tokens[player.UserId] = nil
	lastSeen[player.UserId] = nil
end)

local function takeToken(player)
	local id = player.UserId
	local now = os.clock()
	local have = math.min(BUCKET_MAX, (tokens[id] or BUCKET_MAX) + (now - (lastSeen[id] or now)) * REFILL)
	lastSeen[id] = now
	if have < 1 then
		tokens[id] = have
		return false
	end
	tokens[id] = have - 1
	return true
end

getItemStats.OnServerInvoke = function(player, requests)
	if typeof(requests) ~= "table" then return nil, META end
	if not takeToken(player) then return nil, META end

	local out, seen, count = {}, {}, 0
	for _, req in ipairs(requests) do
		if count >= MAX_ITEMS then break end
		if typeof(req) == "table" then
			local name = req.Name
			local mutation = req.Mutation
			if type(mutation) ~= "string" or mutation == "" then mutation = nil end
			local rarity = (type(name) == "string") and rarityOf[name] or nil

			if rarity and (mutation == nil or validMutation[mutation]) then
				local key = name .. "|" .. (mutation or "")
				if not seen[key] then
					seen[key] = true
					count += 1

					local entry = {}
					-- IsTracked is the single source of truth for "worth a serial";
					-- asking Get() for an untracked class would create a cache key
					-- (and a DataStore read) for a Common nobody will ever quote.
					local tracked = MintRegistry.IsTracked(rarity, mutation)
					entry.Tracked = tracked
					if tracked then
						local okMint, minted, exists = pcall(MintRegistry.Get, name, mutation)
						if okMint and type(minted) == "number" then
							entry.Minted = minted
							entry.Exists = exists
						end
					end

					-- Price is kept for EVERY class, tracked or not: a Common with a
					-- real sale history still has a real price.
					local okPrice, median, samples = pcall(PriceIndex.Get, name, mutation)
					entry.Samples = (okPrice and type(samples) == "number") and samples or 0
					if okPrice and type(median) == "number" then entry.Price = median end

					out[key] = entry
				end
			end
		end
	end
	return out, META
end
