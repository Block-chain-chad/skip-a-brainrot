-- BoundsGuard: last-resort containment, enforced server-side.
--
-- Workspace.GameWorld.ValleyBarrier is the actual fence and it holds at every speed a
-- player can really reach: WalkSpeed is 21, and it was measured blocked at 200 and 400
-- studs/s in all eight directions including every corner. What collision CANNOT stop is a
-- client that sets its own velocity directly -- around 2000 studs/s is 2000/60 = 33 studs
-- of travel per physics frame, and no wall thickness beats an arbitrarily large number
-- (the 40-stud walls were punched through at the south-west corner in testing). So the
-- wall cannot be the only line of defence. This runs on the server, where an exploiting
-- client gets no vote, and simply puts anyone who ends up outside the world back at spawn.
--
-- Deliberately GENEROUS. Wrongly teleporting a legitimate player mid-game is far worse
-- than letting an exploiter stand fifty studs past the wall for half a second, so the
-- regions sit ~30 studs OUTSIDE the barrier rather than hugging it, and it takes two
-- consecutive failed checks to act.

local Players = game:GetService("Players")

local M = {}

-- THE PLAYABLE WORLD IS TWO SEPARATE PLACES. The trading island is 8000 studs away at
-- Y ~2010 and players legitimately teleport there (TeleportService.TRADE_POS is
-- 8000, 2006, 7905). If you ever edit this table, keep BOTH regions -- dropping the
-- island would rubber-band every trading player straight back to the valley the moment
-- they arrived, which would look like the trade portal being broken.
--
-- Measured extents these are derived from:
--   ValleyBarrier  X -295..300   Y  -80..400   Z -430..1030
--   TradingWorld   X 7336..8749  Y 1973..2047  Z 7411..8686
local REGIONS = {
	{ Name = "Valley",  Min = Vector3.new(-325, -140, -460),  Max = Vector3.new(330, 460, 1060) },
	{ Name = "Trading", Min = Vector3.new(7300, 1930, 7375),  Max = Vector3.new(8790, 2110, 8725) },
}

local INTERVAL = 0.25   -- how often each player is checked
local STRIKES  = 2      -- consecutive out-of-bounds checks before acting (~0.5s of grace)
local WARN_GAP = 10     -- seconds between warns per player, so a stuck exploiter can't spam output

-- Fallback only. The real return point is the SpawnLocation, read live below, because
-- hardcoding it here would silently drift the day someone moves the spawn.
local FALLBACK_RETURN = Vector3.new(24, 6, -16)   -- TeleportService's HUB_POS

local strikes, lastWarn = {}, {}
M.Returns = 0   -- count of corrections made this server's lifetime, for a quick sanity read

local function returnPoint()
	local sl = workspace:FindFirstChildOfClass("SpawnLocation")
	if sl then return sl.Position + Vector3.new(0, 4, 0) end
	return FALLBACK_RETURN
end

local function regionOf(p)
	for _, r in ipairs(REGIONS) do
		if p.X >= r.Min.X and p.X <= r.Max.X
			and p.Y >= r.Min.Y and p.Y <= r.Max.Y
			and p.Z >= r.Min.Z and p.Z <= r.Max.Z then
			return r
		end
	end
	return nil
end

-- Exposed so a test can ask the question without waiting on the loop.
function M.IsInBounds(pos)
	return regionOf(pos) ~= nil
end

function M.RegionName(pos)
	local r = regionOf(pos)
	return r and r.Name or nil
end

local function sendBack(player, pos)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	char:PivotTo(CFrame.new(returnPoint()))
	-- Zero the velocity. Someone who tunnelled out is still travelling at whatever speed
	-- got them through, and without this they punch straight back out on the next frame --
	-- the teleport would just add a stutter to their escape instead of stopping it.
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	M.Returns += 1
	local now = os.clock()
	if not lastWarn[player] or now - lastWarn[player] > WARN_GAP then
		lastWarn[player] = now
		warn(string.format("[BoundsGuard] returned %s from out of bounds at %.0f, %.0f, %.0f",
			player.Name, pos.X, pos.Y, pos.Z))
	end
end

function M.Init()
	Players.PlayerRemoving:Connect(function(player)
		strikes[player] = nil
		lastWarn[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				-- Skip a dead or still-loading character: it has no meaningful position, and
				-- respawn puts it back inside the world anyway.
				if hrp and hum and hum.Health > 0 then
					if regionOf(hrp.Position) then
						strikes[player] = nil
					else
						strikes[player] = (strikes[player] or 0) + 1
						if strikes[player] >= STRIKES then
							strikes[player] = nil
							sendBack(player, hrp.Position)
						end
					end
				else
					strikes[player] = nil
				end
			end
		end
	end)

	print(string.format("BoundsGuard online (%d regions, %.2fs interval)", #REGIONS, INTERVAL))
end

return M
