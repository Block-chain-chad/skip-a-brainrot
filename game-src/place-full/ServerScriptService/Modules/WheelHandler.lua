-- WheelHandler: the free daily spin.
--
-- The server owns the roll and the clock. The client asks to spin, the server decides
-- whether it may, picks the slot, pays out, and replies with the winning index -- the
-- client's only job is to animate to that index. Nothing about the outcome is ever taken
-- from the client, and the cooldown is re-checked here rather than trusted from the UI.
--
-- Cooldown is a ROLLING 24 hours from the last spin (os.time based), not calendar
-- midnight. That is the literal reading of "resets every 24 hours", and it avoids the
-- timezone question entirely -- but it does mean the free spin drifts later each day if
-- a player always claims it immediately.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local WheelConfig = require(ReplicatedStorage.Modules.WheelConfig)
local WheelBoard = require(ServerScriptService.Modules.WheelBoard)

local M = {}
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Per-player RNG seeded off the server's own clock. math.random's global state is shared
-- with every other system on this server; a dedicated stream keeps the wheel's odds
-- independent of how many throws or mutations happened to roll first.
local rng = Random.new()

local function getRemote(name, class)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class or "RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local spinRemote  = getRemote("WheelSpin")
local stateRemote = getRemote("WheelState")
-- The client says "the chest is finished with" on this, and the crate's eggs are
-- handed to the egg shop's own hatch ceremony THEN -- see the pendingHatch note.
local doneRemote  = getRemote("WheelCrateDone")

--[[ THE CRATE'S EGGS WAIT FOR THE CHEST TO FINISH.

The crate pays one of every egg in the world, and GrantReward hatches each one
the moment it grants it -- there is no such thing as an unopened egg in the save.
So the pets exist immediately, but the player should not be TOLD immediately:
the chest hands over five eggs, and only once it is done do those eggs get
opened, on the egg shop's own reveal.

So the hatch rows are parked here between the two halves. The client fires
WheelCrateDone when the chest tears down, and that is what releases them. A
backstop timer releases them anyway if the client never speaks up -- the pets are
already banked either way, and a player who never sees what came out of their
eggs is the one outcome worth avoiding. ]]
local pendingHatch = {}   -- [player] = { rows = {...}, eggId = <first egg id> }
-- Broadcast, not FireClient. The wheel is shared scenery standing in the world, so
-- everyone nearby should watch it turn -- not just whoever pressed E.
local spunRemote  = getRemote("WheelSpun")

-- seconds until this player may spin again; 0 means ready now
local function cooldownLeft(data)
	local last = tonumber(data.LastSpinAt) or 0
	if last <= 0 then return 0 end
	return math.max(0, (last + WheelConfig.COOLDOWN) - os.time())
end

local function stateFor(player, data, extra)
	data = data or PlayerDataManager.Get(player)
	if not data then return nil end
	local payload = {
		Cooldown = cooldownLeft(data),
		LuckLeft = PlayerDataManager.BoostRemaining(data, "Luck"),
		PowerLeft = PlayerDataManager.BoostRemaining(data, "Power"),
	}
	if extra then
		for k, v in pairs(extra) do payload[k] = v end
	end
	return payload
end

function M.SendState(player, extra)
	local payload = stateFor(player, nil, extra)
	if payload then stateRemote:FireClient(player, payload) end
end

-- Headline text on the wheel's sign. Shows the shortest cooldown among players currently
-- online, so someone walking past sees "ready" whenever it is ready for anyone. Per-player
-- truth still comes from the state remote; this is only the sign.
local function refreshSign()
	local best
	for _, plr in ipairs(Players:GetPlayers()) do
		local d = PlayerDataManager.Get(plr)
		if d then
			local left = cooldownLeft(d)
			if not best or left < best then best = left end
		end
	end
	if not best then
		WheelBoard.SetState("walk up and press E")
	elseif best <= 0 then
		WheelBoard.SetState("FREE SPIN READY")
	else
		WheelBoard.SetState(("next free spin in %dh %02dm")
			:format(math.floor(best / 3600), math.floor((best % 3600) / 60)))
	end
end

-- Which EggConfig world a spin should pay from. PlayerDataManager.PlayerWorld
-- answers in WorldProgression's names (Valley / Tundra); EggConfig is keyed
-- separately (Forest). WheelConfig owns that mapping -- see the note there about
-- Tundra having no egg table of its own yet.
local function eggWorldFor(player)
	local world = PlayerDataManager.PlayerWorld(player)
	local mapped = world and WheelConfig.EGG_WORLD_BY_WORLD[world]
	if mapped then return mapped end
	-- Loud, because the player is being paid the WRONG WORLD's eggs. Silently
	-- handing out Forest eggs in the tundra is the kind of thing that ships and is
	-- then discovered by a player rather than by us.
	warn(("[WheelHandler] no egg table for world %q -- loot crate paying %s eggs instead. "
		.. "Author that world in EggConfig.WORLDS and add it to WheelConfig.EGG_WORLD_BY_WORLD.")
		:format(tostring(world), WheelConfig.FALLBACK_EGG_WORLD))
	return WheelConfig.FALLBACK_EGG_WORLD
end

-- Applies one slot's rewards. Returns a short description for the client toast.
--
-- Every row is handed to SeasonPassHandler.GrantReward rather than being paid out
-- here. That function is the game's one reward granter and already implements the
-- three things this wedge set needs and that a local copy would get subtly wrong:
-- the Tag branch's already-owned -> FallbackCash rule, the Egg branch's hatch plus
-- the shop's own reveal, and the boost EXTEND rule. Required lazily so
-- ProductRegistry -> WheelHandler -> SeasonPassHandler cannot close a require cycle
-- at module load.
local function award(player, data, slot)
	local SeasonPassHandler = require(ServerScriptService.Modules.SeasonPassHandler)
	local fallbackCash = slot.FallbackCash or 0
	local label = slot.Label

	-- THE CRATE'S MANIFEST. Only a Crate slot builds one, because it is the only
	-- wedge that pays more than one thing AND the only one whose contents cannot be
	-- read off WheelConfig: its eggs HATCH, so what the player actually won is a
	-- list of pets that comes into existence right here, on this call. Every other
	-- slot leaves this nil and keeps the one-line toast it has always had.
	local reveal = slot.Crate and {} or nil
	local function record(row)
		if reveal then reveal[#reveal + 1] = row end
	end

	for _, row in ipairs(slot.Grants or {}) do
		-- Checked BEFORE granting, because the grant is what makes it owned. A player
		-- who already holds the title is quietly paid FallbackCash instead, and a toast
		-- still reading "PRO WHEEL SPINNER" would be the wedge lying about what it paid.
		if row.Kind == "Tag" and data.Tags and data.Tags[row.Id] and slot.RepeatLabel then
			label = slot.RepeatLabel
		end
	end

	for _, row in ipairs(slot.Grants or {}) do
		if row.Kind == "EggSet" then
			-- "one of each egg from the world it is spun in". Expanded here rather than
			-- in the config because the egg ids differ per world and the world is only
			-- known now, at spin time.
			local EggConfig = require(ReplicatedStorage.Modules.EggConfig)
			local eggWorld = eggWorldFor(player)
			local w = EggConfig.GetWorld(eggWorld)
			local hatchRows, firstEggId = {}, nil
			-- Eggs the player's FULL PET BAG could not take (2026-08-20). They are
			-- not lost: GrantReward parks each one on data.PendingEggs, and the chest
			-- below still shows every egg because the player genuinely won them --
			-- they are simply waiting to be opened. Counted here so the wedge writes
			-- ONE summary line rather than five identical warnings; see NoParkToast.
			local parkedTotal = 0
			for _, egg in ipairs((w and w.Eggs) or {}) do
				-- NoReveal, on the crate path only. A reward egg normally fires EggResult
				-- so the shop's hatch ceremony plays -- and a crate pays one of EVERY egg,
				-- so that is five ceremonies back to back on top of a wheel still
				-- spinning. The crate takes the hatch rows back instead and walks the
				-- player through them itself. `or nil` keeps the field absent rather than
				-- false off the crate path, so nothing else sees a new key at all.
				local hatched, parked = SeasonPassHandler.GrantReward(player, data,
					{ Kind = "Egg", World = eggWorld, Id = egg.Id, Qty = 1,
					  NoReveal = (reveal ~= nil) or nil,
					  NoParkToast = (reveal ~= nil) or nil },
					fallbackCash, "wheel " .. slot.Id, "wheel:" .. slot.Id)
				if (parked or 0) > 0 then parkedTotal += 1 end
				-- THE CHEST SHOWS THE EGG, not what came out of it. The pet rows are
				-- held back for the hatch ceremony that follows the chest, so the player
				-- gets to open the eggs rather than being handed the answer.
				for _, pet in ipairs(hatched or {}) do
					hatchRows[#hatchRows + 1] = pet
				end
				firstEggId = firstEggId or egg.Id
				record({ Kind = "Egg", Name = egg.Name, Model = egg.Model, World = eggWorld })
			end
			if reveal and #hatchRows > 0 then
				-- A second crate before the first was opened (two paid spins back to
				-- back) would otherwise drop the first player's pets on the floor.
				if pendingHatch[player] then M.FlushHatch(player) end
				pendingHatch[player] = { rows = hatchRows, eggId = firstEggId }
			end

			-- THE 1% WITH A FULL BAG (owner spec, 2026-08-20): "the game will tell
			-- the player to claim reward after making space for eggs". Deferred by
			-- task.delay so the line lands AFTER the chest ceremony rather than
			-- underneath it -- the crate takes about half a minute to walk through
			-- its prizes, and a warning fired now would be gone before the player
			-- looked away from the wheel. The eggs themselves are already banked on
			-- the profile, so nothing depends on this firing at all.
			if parkedTotal > 0 then
				local n = parkedTotal
				task.delay(6, function()
					if not player.Parent then return end
					local r = remotes:FindFirstChild("PurchaseResult")
					if r then
						r:FireClient(player, { Success = false, Message =
							("%d crate egg%s waiting to hatch \u{2014} your pet bag is full. Sell a pet or buy space from Enzo, then claim %s in your Bag.")
								:format(n, n == 1 and "" or "s", n == 1 and "it" or "them") })
					end
				end)
			end
		else
			SeasonPassHandler.GrantReward(player, data, row,
				fallbackCash, "wheel " .. slot.Id, "wheel:" .. slot.Id)
			-- Recorded off the ROW THAT WAS JUST GRANTED rather than from a second
			-- list written by hand, so the chest can never advertise a prize the
			-- player was not actually paid.
			if row.Kind == "Cash" or row.Kind == "Emeralds" then
				record({ Kind = row.Kind, Amount = row.Amount })
			end
		end
	end

	return label, reveal
end

-- Hands the crate's hatched pets to the egg shop's reveal. Fires the SAME remote
-- with the SAME payload shape EggHandler fires after a purchase, so the shop's
-- existing ceremony plays, and one call carrying every row opens all five eggs
-- together as a bundle rather than five times in a row.
--
-- Idempotent: the entry is cleared before anything is sent, so the client's
-- signal and the backstop timer cannot both fire a reveal.
function M.FlushHatch(player)
	local p = pendingHatch[player]
	if not p then return end
	pendingHatch[player] = nil
	local eggResult = remotes:FindFirstChild("EggResult")
	if not eggResult then
		warn("[WheelHandler] no EggResult remote -- crate eggs granted but never revealed")
		return
	end
	local first = p.rows[1]
	eggResult:FireClient(player, {
		Ok = true,
		EggId = p.eggId,
		Name = first.Name,
		Rarity = first.Rarity,
		PetUid = first.PetUid,
		PetId = first.PetId,
		Results = p.rows,
		Source = "reward",
	})
end

-- The one place a spin can happen. Every entry point -- the in-world prompt, the
-- remote, and the Robux product -- funnels through here, so the cooldown and the
-- payout cannot diverge between them.
--
-- `paid` marks a spin bought with Robux (ProductRegistry). It skips the cooldown
-- CHECK and deliberately does not stamp LastSpinAt: paying for an extra spin must
-- not burn the free daily one the player had banked. It is only ever set on the
-- server side of a verified receipt -- the client cannot ask for a free bypass.
function M.TrySpin(player, paid)
	local data = PlayerDataManager.Get(player)
	if not data then return false end

	-- read-only sessions happen when the DataStore load failed; letting them spin
	-- would hand out a prize that is discarded at logout
	if data.__noSave then
		M.SendState(player, { Error = "Your save could not be loaded. Try rejoining." })
		return false
	end

	if not paid and cooldownLeft(data) > 0 then
		-- the UI and the prompt both hide themselves on cooldown, so reaching here means
		-- a stale client or someone firing the remote directly; just resend the truth
		M.SendState(player)
		return false
	end

	local index, slot = WheelConfig.Roll(rng)
	if not paid then data.LastSpinAt = os.time() end
	local text, reveal = award(player, data, slot)

	PlayerDataManager.PushUpdate(player)
	M.SendState(player, {
		Result = index,        -- the slot the client must land the wheel on
		ResultId = slot.Id,
		ResultText = text,
		-- The crate's contents, and ONLY for whoever won them -- which is why this
		-- rides the per-player state remote rather than the WheelSpun broadcast
		-- below. A bystander watching the wheel turn across the plaza has no reason
		-- to be told which pets somebody else just hatched, and nil on every other
		-- slot keeps the broadcast the same three cheap values it has always been.
		Reveal = reveal,
		Paid = paid or nil,
	})
	spunRemote:FireAllClients(index, player.Name, text)
	-- Backstop only. The chest tears itself down inside a minute -- every wait in
	-- it is bounded -- so in practice WheelCrateDone always lands first and this
	-- finds nothing to do.
	if pendingHatch[player] then
		task.delay(120, function() M.FlushHatch(player) end)
	end
	refreshSign()
	return true
end

function M.Init()
	spinRemote.OnServerEvent:Connect(function(player)
		M.TrySpin(player)
	end)

	-- clients ask for state on open, and once on join
	stateRemote.OnServerEvent:Connect(function(player)
		M.SendState(player)
	end)

	-- "the chest is done, open my eggs now". Carries no data and grants nothing --
	-- it only releases what the server already rolled and already paid out, so a
	-- client spamming it gets one reveal and then nothing.
	doneRemote.OnServerEvent:Connect(function(player)
		M.FlushHatch(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			if player.Parent then
				M.SendState(player)
				-- refresh here too: the sign otherwise reads "walk up and press E" until the
				-- next 20s tick, because at join time no profile had loaded yet
				pcall(refreshSign)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pendingHatch[player] = nil
		task.defer(function() pcall(refreshSign) end)
	end)

	-- the physical wheels: walking up and pressing E runs the same path as the remote.
	-- One per world (see WheelBoard.SITES) and EVERY one is bound -- the cooldown is
	-- per player, so which wheel they walk up to makes no difference to the outcome.
	-- Server-side Triggered, so content streaming cannot leave a wheel dead the way it
	-- did the tundra shop prompts.
	local model = WheelBoard.Build()
	local wheels = WheelBoard.All()
	for _, board in ipairs(wheels) do
		board.Prompt.Triggered:Connect(function(player)
			M.TrySpin(player)
		end)
	end

	task.spawn(function()
		while true do
			pcall(refreshSign)
			task.wait(20)
		end
	end)

	print(("WheelHandler online (%d slots, %dh cooldown, %d wheel(s) in world)")
		:format(#WheelConfig.SLOTS, WheelConfig.COOLDOWN / 3600, #wheels))
end

return M
