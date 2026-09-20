-- WorldTravelConfig -- the fast-travel board: where you can go, and what it is
-- called. Shared, so the Worlds panel and the server agree on both the list and
-- the rules without either restating them.
--
-- A DESTINATION IS NOT A NEW TELEPORT. Every entry names a `Dest` that
-- TeleportService's portals already use, so fast travel arrives exactly where
-- walking through the portal would -- same coordinates, same facing, same
-- RequestStreamAroundAsync wait for an 8,000-stud hop. Adding a world here does
-- not mean writing any travel code; it means naming a portal that exists.
--
-- `Region` is the BoundsGuard region name, which is what PlayerDataManager
-- .PlayerWorld returns and therefore the game's one definition of "where you
-- are". It is what unlocking is keyed on: stand in a region and it is yours.
local M = {}

-- The Valley is the one you spawn into, so it can never be locked -- a player who
-- had not "discovered" their own starting world would have an empty board.
M.Home = "Valley"

M.Destinations = {
	{
		Id = "Valley", Region = "Valley", Dest = "Hub",
		Label = "The Valley", Glyph = "\u{1F3D5}\u{FE0F}",
		Blurb = "The lake, the lodge and your first camp.",
		Tint = Color3.fromRGB(104, 190, 92),
	},
	{
		Id = "Tundra", Region = "Tundra", Dest = "Tundra",
		Label = "Frozen Tundra", Glyph = "\u{2744}\u{FE0F}",
		Blurb = "Ice, aurora and a colder catch pool.",
		Tint = Color3.fromRGB(120, 196, 236),
	},
	-- WORLD 3 IS OPEN (2026-08-11), and the board is not what gates it. Entry is the shaft
	-- Elder Tung's drill opens: GameWorld.Portals.DepthsPortal carries RequiresFlag =
	-- "CaveUnlocked", the flag TundraQuest's last stage stamps, so the only way to first
	-- reach the Gardens is to finish that questline.
	--
	-- Listing it here is therefore safe rather than a second door: IsUnlocked() keys on
	-- having VISITED the region, and the only way to have visited it is to have gone down
	-- the shaft. Players who have not are refused by the same check as before.
	{
		Id = "Gardens", Region = "Gardens", Dest = "Gardens",
		Label = "Lush Gardens", Glyph = "\u{1F33F}",
		Blurb = "Overgrown terraces down the gorge.",
		Tint = Color3.fromRGB(150, 205, 96),
		-- HELD BACK (2026-08-19). World 3 is BUILT but not open to players yet. Delete
		-- this one line to ship it -- everything else keys off it: the board row draws
		-- COMING SOON instead of TRAVEL, CanTravel refuses fast travel, and the shaft
		-- under Elder Tung's drill turns players away at the mouth. Deliberately NOT
		-- done by removing this entry, so the row still advertises the world, and NOT
		-- by unstamping CaveUnlocked, so everyone who already finished the drill
		-- questline keeps their credit and walks straight in on opening day.
		ComingSoon = true,
	},
	{
		Id = "Trading", Region = "Trading", Dest = "Trade",
		Label = "Trading Island", Glyph = "\u{1F91D}",
		Blurb = "Booths, deals and other campers.",
		Tint = Color3.fromRGB(236, 188, 104),
		-- HELD BACK (2026-08-23, owner: the trading centre "isnt great right now").
		-- Same one-line switch the Gardens uses above, and everything keys off it:
		-- the Worlds board row draws COMING SOON instead of TRAVEL, IsUnlocked refuses
		-- fast travel for everyone including players who have already stood there, and
		-- TeleportService.passesLock turns walkers away at the TradePortal before any
		-- other lock is even considered.
		--
		-- This is the whole gate. Player-to-player trading is only reachable from inside
		-- GameWorld.TradingCenter.TradeZone (TradeClient watches for that part and builds
		-- the player list there), and the booths are on the island too -- so shutting the
		-- door shuts the feature. TradeHandler/BoothHandler are deliberately left running
		-- and untouched: nothing can reach them, and gutting them would be work to undo.
		--
		-- Delete this one line to ship it.
		ComingSoon = true,
	},
}

M.ById = {}
for _, d in ipairs(M.Destinations) do M.ById[d.Id] = d end

-- The saved set is keyed by REGION, not by Id. They happen to match today, and
-- deliberately are not assumed to: a future world could add a second arrival point
-- into a region it shares with another entry.
function M.RegionOf(id: string?): string?
	local d = id and M.ById[id]
	return d and d.Region or nil
end

-- One place that answers "can this player go here", so the panel greys out exactly
-- what the server would refuse. Home is always true; everywhere else has to have
-- been stood in at least once.
function M.IsUnlocked(visited, id: string?): boolean
	local d = id and M.ById[id]
	if not d then return false end
	-- Held-back worlds are locked for EVERYONE, including players who have already
	-- stood in the region (dev accounts, and anyone who played while it was open).
	-- This is first so no amount of save state can out-vote it.
	if d.ComingSoon then return false end
	if d.Region == M.Home then return true end
	return type(visited) == "table" and visited[d.Region] == true
end

-- Is this destination held back? Two lookups because a portal knows its `Dest`
-- (the arrival point) while the board knows its `Id`, and the two are NOT the same
-- string in general -- the Valley's Dest is "Hub", Trading's is "Trade".
function M.IsComingSoon(id: string?): boolean
	local d = id and M.ById[id]
	return (d and d.ComingSoon) == true
end

function M.IsDestComingSoon(destName: string?): boolean
	if not destName then return false end
	for _, d in ipairs(M.Destinations) do
		if d.Dest == destName and d.ComingSoon then return true end
	end
	return false
end

return M
