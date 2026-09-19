local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
-- indexes EVERY world's roster, not just the valley's -- see cashPerSecondByName
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
-- Size is a second, independent mutation axis: it MULTIPLIES on top of the colour
-- mutation rather than replacing it, so a Golden Massive earns 2 x 8.
local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
local RebirthConfig = require(ReplicatedStorage.Modules.RebirthConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local DarrelService = require(ServerScriptService.Modules.DarrelService)
local PetHandler = require(ServerScriptService.Modules.PetHandler)
-- Robux pass cash multiplier (2x Cash, VIP). Requires only GamepassConfig, no cycle.
local GamepassService = require(ServerScriptService.Modules.GamepassService)

-- EVERY WORLD (fixed 2026-08-07). Built from BrainrotConfig alone, this priced all 30
-- tundra-exclusive brainrots at nil -> `or 0` -> they earned NOTHING per second, however
-- rare or Massive they were. Valley first so a shared name keeps its World 1 price.
local cashPerSecondByName = {}
for _, entry in ipairs(BrainrotConfig) do
	cashPerSecondByName[entry.Name] = entry.CashPerSecond
end
for _, worldName in ipairs(WorldProgression.List()) do
	local world = WorldProgression.Resolve(worldName)
	for _, e in ipairs((world and world.Pool) or {}) do
		if cashPerSecondByName[e.Name] == nil then
			cashPerSecondByName[e.Name] = e.CashPerSecond
		end
	end
end

local remotes = ReplicatedStorage.Remotes
-- WALK OVER A BRAINROT AND IT PAYS OUT. This was switched off once ("the campfire is now
-- the collector") and is back on by request: the campfire remains the collect-all for the
-- whole camp, and walking the pads is how you take them one at a time. Deliberately not a
-- prompt -- a button on every brainrot meant sixteen keypresses to clear a camp.
local WALKUP_COLLECT   = true
local CAMPFIRE_RADIUS  = 5.60   -- horizontal studs (cylinder, not sphere) == CampStand radius
local CAMPFIRE_Y_BAND  = 6.0    -- vertical studs
local COLLECT_INTERVAL = 2.0    -- seconds between campfire gulps while standing in the fire
local CUE_COOLDOWN     = 2.0    -- matches COLLECT_INTERVAL: one cue per gulp, never more
local BANK_WRITE_EVERY = 3      -- ticks (~1.05 s) between attribute publishes
local cueState, tickCount = {}, 0
Players.PlayerRemoving:Connect(function(p) cueState[p] = nil end)
-- Main requires IncomeLoop (line 11) BEFORE PlotBoardHandler, so resolve the cue remote lazily.
local cueRemote
local function getCueRemote()
	if cueRemote and cueRemote.Parent then return cueRemote end
	cueRemote = remotes:FindFirstChild("CampfireCollected")
	return cueRemote
end
local BRAINROT_RANGE = 7

-- canonical abbreviator, K through Qi -- see Modules.NumberFormat
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local formatShort = NumberFormat.Short
local rateText = NumberFormat.Rate

-- keep each brainrot billboard showing: name, stored cash, and small cash/sec line.
-- 2026-08-13: mutated brainrots carry a MutationPill ABOVE the name (built by
-- BrainrotSpawner; HasPill attribute is the layout contract) -- this writer
-- only touches Main/Rate and offsets them under the pill, so the pill and the
-- income text never fight over the same pixels.
local function updateBillboard(model, name, pending, cps)
	local bg = model:FindFirstChildOfClass("BillboardGui")
	if not bg then return end
	local pillOffset = bg:GetAttribute("HasPill") and 24 or 0
	bg.Size = UDim2.new(0, 160, 0, 56 + pillOffset)

	local main = bg:FindFirstChild("Main")
	if not main then
		main = bg:FindFirstChildOfClass("TextLabel")
		if main then main.Name = "Main" end
	end
	if main then
		main.Size = UDim2.new(1, 0, 0, 40)
		main.Position = UDim2.new(0, 0, 0, pillOffset)
		main.TextScaled = true
		main.Text = name .. "\n\u{1F4B0} $" .. formatShort(pending)
	end

	local rate = bg:FindFirstChild("Rate")
	if not rate then
		rate = Instance.new("TextLabel")
		rate.Name = "Rate"
		rate.BackgroundTransparency = 1
		rate.Size = UDim2.new(1, 0, 0, 15)
		rate.Font = Enum.Font.GothamMedium
		rate.TextSize = 12
		rate.TextColor3 = Color3.fromRGB(185, 235, 195)
		rate.TextStrokeTransparency = 0.3
		rate.Parent = bg
	end
	rate.Position = UDim2.new(0, 0, 0, 41 + pillOffset)
	rate.Text = rateText(cps)
end

local function collectAll(player)
	local data = PlayerDataManager.Get(player)
	if not data then return 0 end
	local total = 0
	for _, e in ipairs(data.Brainrots) do
		if e.PadIndex and (e.Pending or 0) >= 1 then
			total += math.floor(e.Pending)
			e.Pending = e.Pending - math.floor(e.Pending)
		end
	end
	if total > 0 then
		PlayerDataManager.AddEarnings(player, total, data)
		PlayerDataManager.SyncLeaderstat(player)
		remotes.CashTick:FireClient(player, data.Cash)
	end
	return total
end

local IncomeLoop = {}

function IncomeLoop.Init()
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.35)
			local now = os.clock()
			local dt = now - last
			last = now
			tickCount += 1

			for _, player in ipairs(Players:GetPlayers()) do
				local okTick, errTick = pcall(function()
				local data = PlayerDataManager.Get(player)
				if data then
					local rebirthMult = RebirthConfig.IncomeMult(data.Rebirths)
					local upMult = UpgradeConfig.IncomeMult(data.Upgrades)
					-- Hoisted to a per-player local: it is the same value for every one of this
					-- player's brainrots, and it has to reach BOTH the accrual below and the
					-- billboard rate further down. It previously appeared only in the accrual,
					-- so every plot sign advertised a cash/sec that was lower than what the
					-- brainrot was actually paying -- by the whole pet multiplier.
					local petMult = PetHandler.IncomeMult(player)
					-- Robux passes (2x Cash, VIP). Wired 2026-08-09: GamepassService has
					-- exposed CashMult since it shipped and nothing multiplied by it, so
					-- those passes took money and changed nothing. Hoisted for the same
					-- reason petMult above is -- it has to reach the billboard rate too, or
					-- every plot sign advertises less than the brainrot actually pays.
					local passMult = GamepassService.CashMult(player)
					local plot = PlayerDataManager.GetPlot(player)
					local pads = plot and plot:FindFirstChild("Pads")
					local char = player.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")

					-- accumulate pending for every placed brainrot
					for _, e in ipairs(data.Brainrots) do
						if e.PadIndex then
							e.Pending = (e.Pending or 0) + (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * Sizes.Mult(e.Size) * rebirthMult * upMult * petMult * passMult * dt
						end
					end

					local entryByPad = {}
					for _, e in ipairs(data.Brainrots) do
						if e.PadIndex then entryByPad[e.PadIndex] = e end
					end

					-- BILLBOARDS ON EVERY CAMP, not just the one the owner is standing in. A player
					-- holds a camp per world and both render the same collection, so refreshing
					-- only the near one left the other frozen at whatever it last showed -- two
					-- camps quoting different takings for the same brainrot, and anyone visiting
					-- the camp you were away from reading a number that never moved.
					--
					-- The walk-up collect stays scoped to the camp you are actually at: it is a
					-- proximity check, and the mirror is 8000 studs away.
					local collected = 0
					for _, ownedPlot in ipairs(PlayerDataManager.GetPlots(player)) do
						local ownedPads = ownedPlot:FindFirstChild("Pads")
						local isHere = ownedPlot == plot
						if ownedPads then
							for _, model in ipairs(ownedPads:GetChildren()) do
								local pi = model:GetAttribute("PadIndex")
								-- Models as well as Parts: BrainrotSpawner clones an authored Model when
								-- one exists, and a BasePart-only gate would silently freeze its billboard
								-- at $0 while the brainrot kept earning.
								if pi and (model:IsA("BasePart") or model:IsA("Model")) then
									local e = entryByPad[pi]
									if e then
										local cps = (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * Sizes.Mult(e.Size) * rebirthMult * upMult * petMult * passMult
										local dispName = Sizes.Label(e.Mutation, e.Size, e.Name)
										updateBillboard(model, dispName, e.Pending, cps)
										local mPos = model:IsA("BasePart") and model.Position or model:GetPivot().Position
										if isHere and WALKUP_COLLECT and hrp and e.Pending >= 1 and (mPos - hrp.Position).Magnitude <= BRAINROT_RANGE then
											collected += math.floor(e.Pending)
											e.Pending = e.Pending - math.floor(e.Pending)
										end
									end
								end
							end
						end
					end
					if collected > 0 then
						PlayerDataManager.AddEarnings(player, collected, data)
						PlayerDataManager.SyncLeaderstat(player)
						remotes.CashTick:FireClient(player, data.Cash)
						-- counts toward Darrel's collect quests exactly as a campfire gulp does,
						-- or walking the pads would quietly be the worse way to play
						DarrelService.Notify(player, "Collect", collected)
					end

					-- campfire bank: publish the hoard, gulp it when the owner stands in the fire
					local total = 0
					for _, e in ipairs(data.Brainrots) do
						if e.PadIndex then total += (e.Pending or 0) end
					end
					local campfire = plot and plot:FindFirstChild("Campfire")
					if campfire then
						local cs = cueState[player]
						if not cs then cs = { last = -1e9, lastCollect = -1e9, accum = 0, inside = false }; cueState[player] = cs end

						-- CYLINDER test, not .Magnitude: the HRP sits ~1.6 studs above Campfire.Position,
						-- so a sphere would have to be inflated just to reach a standing player.
						local onFire = false
						if hrp then
							local dx = hrp.Position.X - campfire.Position.X
							local dz = hrp.Position.Z - campfire.Position.Z
							local dy = math.abs(hrp.Position.Y - campfire.Position.Y)
							onFire = (dx * dx + dz * dz) <= CAMPFIRE_RADIUS * CAMPFIRE_RADIUS
								and dy <= CAMPFIRE_Y_BAND
						end

						local now = os.clock()
						local fresh = onFire and not cs.inside
						local got = 0
						-- AUTO COLLECT (Robux pass), wired 2026-08-09 -- nothing read this flag
						-- before, so the pass would have taken Robux and done nothing.
						--
						-- It banks through the SAME collectAll the campfire uses, on the same
						-- interval, so quest progress, lifetime-earnings tracking and the
						-- floating "+$" cue all behave exactly as they do on foot. The only
						-- thing the pass removes is the walk back.
						local autoCollect = GamepassService.HasFlag(player, "AutoCollect")
						if (onFire or autoCollect) and total >= 1
							and (fresh or (now - cs.lastCollect) >= COLLECT_INTERVAL) then
							got = collectAll(player) or 0
							cs.lastCollect = now
						end

						if got > 0 then
							DarrelService.Notify(player, "Collect", got)
							total = math.max(total - got, 0)
							cs.accum += got
							if fresh or (now - cs.last) >= CUE_COOLDOWN then
								local r = getCueRemote()
								if r then r:FireClient(player, cs.accum, fresh) end
								cs.last, cs.accum = now, 0
							end
						end
						if cs.inside and not onFire and cs.accum > 0 then
							local r = getCueRemote()                     -- flush on exit
							if r then r:FireClient(player, cs.accum, false) end
							cs.accum = 0
						end
						cs.inside = onFire

						if got > 0 or tickCount % BANK_WRITE_EVERY == 0 then
							campfire:SetAttribute("Banked", math.floor(total))
						end
						if tickCount % BANK_WRITE_EVERY == 0 then
							plot:SetAttribute("TotalEarned", math.floor(data.TotalEarned or 0))
						end
					end
				end
				end)
				if not okTick then
					warn("[IncomeLoop] tick failed for " .. player.Name .. ": " .. tostring(errTick))
				end
			end
		end
	end)
end

return IncomeLoop
