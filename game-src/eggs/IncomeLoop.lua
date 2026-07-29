local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local RebirthConfig = require(ReplicatedStorage.Modules.RebirthConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local DarrelService = require(ServerScriptService.Modules.DarrelService)
local PetHandler = require(ServerScriptService.Modules.PetHandler)

local cashPerSecondByName = {}
for _, entry in ipairs(BrainrotConfig) do
	cashPerSecondByName[entry.Name] = entry.CashPerSecond
end

local remotes = ReplicatedStorage.Remotes
local WALKUP_COLLECT   = false  -- USER DECISION U1: the campfire is now the collector
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

-- keep each brainrot billboard showing: name, stored cash, and small cash/sec line
local function updateBillboard(model, name, pending, cps)
	local bg = model:FindFirstChildOfClass("BillboardGui")
	if not bg then return end
	bg.Size = UDim2.new(0, 160, 0, 56)

	local main = bg:FindFirstChild("Main")
	if not main then
		main = bg:FindFirstChildOfClass("TextLabel")
		if main then main.Name = "Main" end
	end
	if main then
		main.Size = UDim2.new(1, 0, 0, 40)
		main.Position = UDim2.new(0, 0, 0, 0)
		main.TextScaled = true
		main.Text = name .. "\n\u{1F4B0} $" .. formatShort(pending)
	end

	local rate = bg:FindFirstChild("Rate")
	if not rate then
		rate = Instance.new("TextLabel")
		rate.Name = "Rate"
		rate.BackgroundTransparency = 1
		rate.Size = UDim2.new(1, 0, 0, 15)
		rate.Position = UDim2.new(0, 0, 0, 41)
		rate.Font = Enum.Font.GothamMedium
		rate.TextSize = 12
		rate.TextColor3 = Color3.fromRGB(185, 235, 195)
		rate.TextStrokeTransparency = 0.3
		rate.Parent = bg
	end
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
					local plot = PlayerDataManager.GetPlot(player)
					local pads = plot and plot:FindFirstChild("Pads")
					local char = player.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")

					-- accumulate pending for every placed brainrot
					for _, e in ipairs(data.Brainrots) do
						if e.PadIndex then
							e.Pending = (e.Pending or 0) + (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * rebirthMult * upMult * PetHandler.IncomeMult(player) * dt
						end
					end

					local entryByPad = {}
					for _, e in ipairs(data.Brainrots) do
						if e.PadIndex then entryByPad[e.PadIndex] = e end
					end

					-- billboards + per-brainrot walk-up collect
					local collected = 0
					if pads then
						for _, model in ipairs(pads:GetChildren()) do
							local pi = model:GetAttribute("PadIndex")
							-- Models as well as Parts: BrainrotSpawner clones an authored Model when
							-- one exists, and a BasePart-only gate would silently freeze its billboard
							-- at $0 while the brainrot kept earning.
							if pi and (model:IsA("BasePart") or model:IsA("Model")) then
								local e = entryByPad[pi]
								if e then
									local cps = (cashPerSecondByName[e.Name] or 0) * Mutations.Mult(e.Mutation) * rebirthMult * upMult
									local dispName = e.Mutation and (e.Mutation .. " " .. e.Name) or e.Name
									updateBillboard(model, dispName, e.Pending, cps)
									local mPos = model:IsA("BasePart") and model.Position or model:GetPivot().Position
									if WALKUP_COLLECT and hrp and e.Pending >= 1 and (mPos - hrp.Position).Magnitude <= BRAINROT_RANGE then
										collected += math.floor(e.Pending)
										e.Pending = e.Pending - math.floor(e.Pending)
									end
								end
							end
						end
					end
					if collected > 0 then
						PlayerDataManager.AddEarnings(player, collected, data)
						PlayerDataManager.SyncLeaderstat(player)
						remotes.CashTick:FireClient(player, data.Cash)
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
						if onFire and total >= 1 and (fresh or (now - cs.lastCollect) >= COLLECT_INTERVAL) then
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
