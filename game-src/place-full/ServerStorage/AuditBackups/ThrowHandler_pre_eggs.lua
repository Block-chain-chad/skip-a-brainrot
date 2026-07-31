local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local RarityRoll = require(ServerScriptService.Modules.RarityRoll)
local RarityCurve = require(ReplicatedStorage.Modules.RarityCurve)
local PityConfig = require(ReplicatedStorage.Modules.PityConfig)
local RockConfig = require(ReplicatedStorage.Modules.RockConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local RebirthConfig = require(ReplicatedStorage.Modules.RebirthConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local OfferingConfig = require(ReplicatedStorage.Modules.OfferingConfig)
local BrainrotSpawner = require(ServerScriptService.Modules.BrainrotSpawner)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local MaxwellQuest = require(ServerScriptService.Modules.MaxwellQuest)
local SeasonPassHandler = require(ServerScriptService.Modules.SeasonPassHandler)
local MintRegistry = require(ServerScriptService.Modules.MintRegistry)
local LimitedStock = require(ServerScriptService.Modules.LimitedStock)
local Waves = require(ReplicatedStorage.Modules.BrainrotWaves)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RockDesign = require(ReplicatedStorage.Modules.RockDesign)

local remotes = ReplicatedStorage.Remotes
local THROW_Z = 15
local MAX_TOTAL_DISTANCE = 900

local rockById = {}
for _, rock in ipairs(RockConfig) do
	rockById[rock.Id] = rock
end

-- Pets that buff throw luck while PLACED on your base (BrainrotConfig.LuckMult).
-- Maxwell (the questline reward) is x5. LuckHUDClient mirrors this exact rule so the
-- displayed luck matches what the server rolls.
local petLuckByName = {}
for _, e in ipairs(BrainrotConfig) do
	if e.LuckMult then petLuckByName[e.Name] = e.LuckMult end
end

-- tier name -> index in RarityConfig (Common=1 .. God=8). Used by the pity system.
local tierIndexByName = {}
for i, t in ipairs(RarityConfig) do tierIndexByName[t.Name] = i end

-- fired to the throwing player when a pity boost lands, for the "<TIER> PITY THROW!" banner
local pityRemote = remotes:FindFirstChild("PityThrow")
if not pityRemote then
	pityRemote = Instance.new("RemoteEvent")
	pityRemote.Name = "PityThrow"
	pityRemote.Parent = remotes
end

-- Each rock's own thrown look now lives in ReplicatedStorage.Modules.RockDesign
-- so Rocco's shelf display and the thrown rock cannot drift apart. The private
-- table this replaces only covered the 8 original Ids, so the 6 later rocks all
-- threw as the same generic slate block.

local raritySignFolder = Workspace:WaitForChild("GameWorld")

local WATER_Y = 1.5

-- perfect = the release landed inside the sweet-spot band. The band is ISSUED
-- BY THIS SERVER (GetSweetSpot, single-use, aged) and judged here against the
-- power the throw actually uses -- the client only draws it. Its second
-- ThrowRequest argument is ignored: it was client-authoritative once, and
-- FireServer(0.01, true) was accepted in playtest. Judging power-vs-band server
-- side makes spoofing self-defeating: to be "perfect" a hacked client must move
-- its power INTO the band, paying the same strength trade-off honest players pay.
local PERFECT_DISTANCE_MULT = 1.1
local PERFECT_LUCK_MULT = 1.075
local BAND_WIDTH = 0.07     -- mirrors the client's strip width
local BAND_MAX_AGE = 30     -- seconds a charge may idle before perfect stops counting

-- [userId] = { min, max, issuedAt } -- the one band this player may cash in next
local pendingBand = {}

local function getThrowOrigin(player)
	local char = player and player.Character
	if char then
		local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local dir = hrp and hrp.CFrame.LookVector or Vector3.new(0, 0, 1)
		if hand then
			return hand.Position, dir
		elseif hrp then
			return hrp.Position + dir * 1.5 + Vector3.new(0, 1.5, 0), dir
		end
	end
	return Vector3.new(0, 4, THROW_Z), Vector3.new(0, 0, 1)
end

-- Built-in client asset: nothing to upload, nothing to moderate, and it is already
-- on disk so the first skip of a session does not play silently while a stream loads.
local SPLASH_SOUND = "rbxassetid://9117946641" -- SFX2 (was rbxasset impact_water.mp3)

-- One splash sound per water contact. Created server-side so every player at the dock
-- hears each other's skips positionally, which is most of the charm.
--   index/total: 1-based contact number, used to raise the pitch across the sequence
--                the way a real stone gets lighter and quicker as it loses energy.
--   big:         the final landing -- lower, fuller, and allowed to ring longer.
local function playSplashSound(pos, big, index, total)
	local host = Instance.new("Part")
	host.Name = "SplashAudio"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CastShadow = false
	host.CFrame = CFrame.new(pos.X, WATER_Y, pos.Z)
	host.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = SPLASH_SOUND
	-- Deliberately quiet. This fires up to 8 times per throw, and several players share
	-- the dock, so anything louder turns the lake into a washing machine.
	sound.Volume = big and 0.45 or 0.22
	-- The asset is a 2.4s wash. Pitching it up brightens the transient AND shortens the
	-- audible tail, which is what makes a skip read as a skip rather than a belly-flop.
	local progress = (total and total > 1) and ((index - 1) / (total - 1)) or 0
	local jitter = (math.random() - 0.5) * 0.08   -- so repeated skips are not identical
	sound.PlaybackSpeed = (big and 0.95 or (1.45 + progress * 0.35)) + jitter
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = 240
	sound.Parent = host
	sound:Play()

	-- Fade before removing the part: cutting a 2.4s wash dead mid-tail clicks.
	local hold = big and 1.15 or 0.42
	task.delay(math.max(hold - 0.14, 0.05), function()
		if sound.Parent then
			game:GetService("TweenService"):Create(sound, TweenInfo.new(0.14), { Volume = 0 }):Play()
		end
	end)
	Debris:AddItem(host, hold + 0.06)
end

-- ================================ SKIP SPLASH VFX ================================
-- Was one neon cylinder expanding plus one neon ball shrinking, which read as a flash
-- of light rather than water. Now three ideas layered:
--
--   RIPPLES   two rings, the second delayed and trailing the first. A single ring is
--             the tell that it is fake -- real water sheds a train of them. The rings
--             are also thinner and start further into transparency, so they read as a
--             disturbance on the surface instead of a glowing hoop.
--   DROPLETS  a ParticleEmitter burst instead of a shrinking ball. One part hosting an
--             emitter costs the same replication as the old ball but produces dozens of
--             droplets that arc under gravity -- by far the biggest visual win per byte.
--   COLUMN    a quick vertical spout, BIG LANDINGS ONLY, for the heavier "plunk".
--
-- Part budget matters: this fires up to 8 times per throw and it is SERVER-created, so
-- every part replicates to every client at the dock. Measured on a real 8-contact throw:
-- 16 ripples + 8 droplet hosts + 1 column = 25 parts, against 16 for the old version.
-- So it is ~1.5x the parts, not free -- but they are 0.12-stud anchored non-colliding
-- decor with sub-second Debris lifetimes, and the droplet emitter buys dozens of visible
-- droplets for ONE part, which is where the fidelity actually comes from.
local SPLASH_TEX = "rbxasset://textures/particles/smoke_main.dds"

-- Events that darken the sky (WeatherClient sets ClockTime 23.4-23.9 for these). During
-- them a Neon splash still GLOWS but casts no light, so a skip 600 studs out reads as a
-- faint smudge. The splash light below is boosted while one of these is live -- and the
-- server can know because WeatherHandler publishes WeatherName on ReplicatedStorage.
local NIGHT_EVENTS = {
	["Shooting Star"] = true,
	["Blood Moon"] = true,
	["Aurora"] = true,
}

local function decorPart(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.Parent = Workspace
	return p
end

local function ripple(pos, delay, startD, endD, life, alpha)
	task.delay(delay, function()
		local TweenService = game:GetService("TweenService")
		local ring = Instance.new("Part")
		ring.Name = "SkipRipple"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.12, startD, startD)
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(226, 244, 255)
		ring.Transparency = alpha
		ring.CFrame = CFrame.new(pos.X, WATER_Y + 0.04, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		decorPart(ring)
		-- Quad easing: a real ripple sprints outward then slows, where the old Linear
		-- tween expanded at a constant rate and looked mechanical.
		TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.12, endD, endD), Transparency = 1 }):Play()
		Debris:AddItem(ring, life + 0.15)
	end)
end

local function spawnSplash(pos, big)
	local TweenService = game:GetService("TweenService")
	local scale = big and 1.8 or 1

	-- lead ripple, plus a trailing one that chases it
	ripple(pos, 0, 1.6, 12 * scale, 0.62, 0.35)
	if big then
		ripple(pos, 0.10, 1.2, 18, 0.85, 0.62)
	else
		ripple(pos, 0.09, 1.0, 6.5, 0.44, 0.68)
	end

	-- droplet burst
	local host = Instance.new("Part")
	host.Name = "SkipSplash"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.CFrame = CFrame.new(pos.X, WATER_Y + 0.15, pos.Z)
	decorPart(host)

	local e = Instance.new("ParticleEmitter")
	e.Texture = SPLASH_TEX
	e.Rate = 0                                  -- burst only, via :Emit below
	e.Lifetime = NumberRange.new(0.30, 0.62)
	e.Speed = NumberRange.new(9, 20 + 10 * scale)
	e.EmissionDirection = Enum.NormalId.Top
	-- narrow-ish cone: water leaves the surface upward and outward, not spherically
	e.SpreadAngle = Vector2.new(46, 46)
	e.Acceleration = Vector3.new(0, -95, 0)     -- gravity, so droplets ARC instead of drifting
	e.Drag = 1.2
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.42 * scale, 0.18),
		NumberSequenceKeypoint.new(1, 0.06),
	})
	e.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.72, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 0.35
	e.LightInfluence = 0.4
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-140, 140)
	e.Parent = host
	e:Emit(big and 34 or 14)

	-- ACTUAL LIGHT, not just a glowing part. Neon is emissive but illuminates nothing, so
	-- on a dark night the skips were invisible past a few hundred studs. This flashes real
	-- light onto the water and fades out.
	--
	-- Parented to the droplet host, which already exists -- so the whole effect costs ZERO
	-- extra parts. Shadows are OFF: this fires up to 8 times per throw and shadow casting
	-- is the expensive half of a PointLight (every other light in this place is already
	-- Shadows = false for the same reason).
	local weather = ReplicatedStorage:GetAttribute("WeatherName")
	local nightBoost = NIGHT_EVENTS[weather] and 2.4 or 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(198, 232, 255)   -- cool white, matching the droplets
	light.Range = (big and 34 or 20) * (nightBoost > 1 and 1.35 or 1)
	light.Brightness = (big and 3.2 or 1.7) * nightBoost
	light.Shadows = false
	light.Parent = host
	-- Fade rather than cut: a light that vanishes mid-brightness pops. Short on a skip so
	-- eight of them never overlap into one continuous glow; longer on the landing.
	TweenService:Create(light, TweenInfo.new(big and 0.55 or 0.26,
		Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()

	Debris:AddItem(host, 1.0)

	-- vertical spout, only worth the part on the landing
	if big then
		local col = Instance.new("Part")
		col.Name = "SkipColumn"
		col.Shape = Enum.PartType.Cylinder
		col.Size = Vector3.new(0.6, 1.5, 1.5)
		col.Material = Enum.Material.Neon
		col.Color = Color3.fromRGB(240, 251, 255)
		col.Transparency = 0.28
		col.CFrame = CFrame.new(pos.X, WATER_Y + 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		decorPart(col)
		TweenService:Create(col, TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = Vector3.new(4.6, 1.1, 1.1) }):Play()
		task.delay(0.17, function()
			if col.Parent then
				TweenService:Create(col, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(col, 0.55)
	end
end

local function spawnSkippingStone(player, distance, rock, onLand)
	local origin, dir = getThrowOrigin(player)
	local horiz = Vector3.new(0, 0, 1) -- always toward the distance markers

	-- A detailed multi-part rock, not a bare primitive: chips, facets and flecks
	-- from RockDesign, which the shop preview and Rocco's shelf build from too, so
	-- the thing you throw is the thing you bought. Parts are anchored, so the
	-- flight below drives it with PivotTo rather than setting a CFrame.
	local stone = RockDesign.Build(rock and rock.Id,
		(rock and rock.Color) or Color3.fromRGB(105, 100, 96))
	stone.Name = "ThrownRock"
	stone:PivotTo(CFrame.new(origin))
	stone.Parent = Workspace

	-- start the skip path just past the dock's front edge so the rock skips on OPEN water, never under the deck floor
	local startFlat = Vector3.new(origin.X, WATER_Y, math.max(origin.Z, 28))
	-- fewer, clearer skips: aim for ~one skip every ~18 studs, 2..8 contacts
	local nContacts = math.clamp(math.floor(distance / 18) + 1, 2, 8)
	local points = { origin }
	for i = 1, nContacts do
		local d = distance * (i / nContacts)
		points[#points + 1] = startFlat + horiz * d
	end
	local hopLen = distance / nContacts

	local totalTime = math.clamp(0.9 + distance / 360, 1.15, 4.2)
	local segTime = totalTime / (#points - 1)

	remotes.StoneThrown:FireClient(player, origin, points[#points], totalTime, distance)

	task.spawn(function()
		local spin = 0
		for k = 1, #points - 1 do
			local a = points[k]
			local b = points[k + 1]
			-- clear, bouncy hop heights (flat-ish so it reads as skipping, not lobbing)
			local apex
			if k == 1 then
				apex = math.clamp(hopLen * 0.4, 3, 11)
			else
				apex = math.max(2.5, math.clamp(hopLen * 0.42, 3, 8) * (0.82 ^ (k - 2)))
			end
			local t0 = os.clock()
			while true do
				local dt = os.clock() - t0
				local alpha = math.clamp(dt / segTime, 0, 1)
				local pos = a:Lerp(b, alpha)
				local h = math.sin(alpha * math.pi) * apex
				spin = spin + 1.0
				stone:PivotTo(CFrame.new(pos.X, pos.Y + h, pos.Z)
					* CFrame.Angles(0, spin, 0)
					* CFrame.Angles(math.rad(12), 0, 0))
				if alpha >= 1 then break end
				task.wait()
			end
			-- splash at each water contact (bigger on the final landing)
			local isLast = k == #points - 1
			spawnSplash(b, isLast)
			playSplashSound(b, isLast, k, #points - 1)
		end
		local last = points[#points]
		stone:PivotTo(CFrame.new(last.X, WATER_Y, last.Z) * CFrame.Angles(math.rad(6), 0, 0))
		Debris:AddItem(stone, 1.3)
		if onLand then onLand() end -- the stone has settled in the water -> reveal the catch
	end)
end

local function spawnBrainrotOnPlot(player, brainrotEntry, padIndex, mutation)
	local plot = PlayerDataManager.GetPlot(player)
	if not plot then return end
	BrainrotSpawner.Spawn(plot, brainrotEntry, padIndex, mutation)
end

local function isInThrowZone(character)
	local zone = Workspace:FindFirstChild("GameWorld") and Workspace.GameWorld:FindFirstChild("ThrowZone")
	if not zone then return true end
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local rel = zone.CFrame:PointToObjectSpace(hrp.Position)
	local s = zone.Size / 2
	return math.abs(rel.X) <= s.X and math.abs(rel.Z) <= s.Z and math.abs(rel.Y) <= s.Y + 6
end

local ThrowHandler = {}

-- SERVER-AUTHORITATIVE throw rate. Before this, the only throttle was a variable
-- in ClientMain, so the faucet was governed entirely by the client.
local THROW_COOLDOWN = 1.05   -- matches the client's CYCLE_SECONDS
local lastThrow = {}          -- [userId] = os.clock()

-- ONE STONE AT A TIME. The cooldown alone could never enforce this: flight time is
-- clamp(0.9 + distance/360, 1.15, 4.2) seconds, so it is ALWAYS longer than the 1.05s
-- cooldown. That gap is what let a held throw button queue a second throw while the
-- first stone was still skipping. Enforced here rather than only in ClientMain because
-- a client-side lock is advisory -- anything firing the remote directly bypasses it.
local inFlight = {}           -- [userId] = true while that player's stone is skipping
local flightToken = {}        -- [userId] = id of the current throw, so a stale
                              -- watchdog can never unlock a newer throw
local MAX_FLIGHT = 4.2        -- the upper clamp in spawnSkippingStone

Players.PlayerRemoving:Connect(function(player)
	lastThrow[player.UserId] = nil
	inFlight[player.UserId] = nil
	flightToken[player.UserId] = nil
	pendingBand[player.UserId] = nil
end)

function ThrowHandler.Init()
	-- The sweet-spot handshake: the client asks for a band each time the charge
	-- minigame loads and draws whatever this returns. Single-use (consumed by the
	-- next ThrowRequest) and overwritten by each new ask, so there is exactly one
	-- live band per player and it can never be replayed.
	local sweetSpot = remotes:FindFirstChild("GetSweetSpot")
	if not sweetSpot then
		sweetSpot = Instance.new("RemoteFunction")
		sweetSpot.Name = "GetSweetSpot"
		sweetSpot.Parent = remotes
	end
	sweetSpot.OnServerInvoke = function(player)
		-- same reachable range the client used to roll locally: never hugging an end
		local center = math.random(22, 90) / 100
		local band = {
			min = math.clamp(center - BAND_WIDTH / 2, 0, 1),
			max = math.clamp(center + BAND_WIDTH / 2, 0, 1),
			issuedAt = os.clock(),
		}
		pendingBand[player.UserId] = band
		return { min = band.min, max = band.max }
	end

	remotes.ThrowRequest.OnServerEvent:Connect(function(player, power, clientPerfect)
		local now = os.clock()
		if now - (lastThrow[player.UserId] or 0) < THROW_COOLDOWN then return end
		if inFlight[player.UserId] then return end   -- previous stone is still skipping
		lastThrow[player.UserId] = now

		local data = PlayerDataManager.Get(player)
		if not data then return end
		if not PlayerDataManager.GetPlot(player) then
			local r = remotes:FindFirstChild("PurchaseResult")
			if r then r:FireClient(player, { Success = false, Message = "Claim a base first! Walk onto an available plot." }) end
			return
		end
		if typeof(power) ~= "number" then return end
		if power ~= power then return end
		power = math.clamp(power, 0, 1)
		-- PERFECT IS SERVER-JUDGED (see the header note). clientPerfect is legacy
		-- display chatter and deliberately unread.
		local band = pendingBand[player.UserId]
		pendingBand[player.UserId] = nil   -- single-use: no replay across throws
		local perfect = band ~= nil
			and (now - band.issuedAt) <= BAND_MAX_AGE
			and power >= band.min and power <= band.max

		if not isInThrowZone(player.Character) then return end

		-- Claim the flight slot HERE -- immediately after the last cheap validation and
		-- BEFORE any of the roll / mint / season work below.
		--
		-- It used to be claimed just above the launch, ~40 lines further down, which left
		-- a window: something in between yields, so a second request cleared the gate
		-- while the first was still mid-handler. Measured: 12 requests fired 0.13s apart
		-- produced 2 stones instead of 1. Claiming at the moment of acceptance closes it,
		-- and does so without needing to know which call yields.
		local token = (flightToken[player.UserId] or 0) + 1
		flightToken[player.UserId] = token
		inFlight[player.UserId] = true

		-- Any early return past this point MUST release the slot, or the player is locked
		-- out until the watchdog fires.
		local function abandonFlight()
			if flightToken[player.UserId] == token then
				inFlight[player.UserId] = nil
			end
		end

		local rock = rockById[data.EquippedRock] or rockById["Pebble"]
		local variance = math.random(-2, 2)
		local distance = math.clamp(power * rock.MaxDistance
			* UpgradeConfig.Mult(data.Upgrades, "Power")
			* RebirthConfig.PowerMult(data.Rebirths)          -- prestige throw power
			* PlayerDataManager.BoostMult(data, "Power")      -- timed daily-wheel boost
			* (perfect and PERFECT_DISTANCE_MULT or 1) + variance, 0, MAX_TOTAL_DISTANCE)

		-- === Rarity: DISTANCE + LUCK weight a probabilistic roll (RarityCurve) ===
		-- Distance no longer GUARANTEES a tier -- it unlocks higher tiers and shifts the
		-- odds up; luck shifts them further; higher tiers are geometrically rarer and
		-- nothing is a lock. The old model floored the tier at your distance, which made
		-- Mythic+ a certainty for a long enough throw. Tunables + curve live in
		-- ReplicatedStorage.Modules.RarityCurve (shared with the luck HUD).
		local rebirthLuck = RebirthConfig.LuckMult(data.Rebirths)
		local weatherLuck = ReplicatedStorage:GetAttribute("WeatherLuck") or 1
		local weatherMut = ReplicatedStorage:GetAttribute("WeatherMut") or 1

		-- access luck shifts the whole curve up: rock + upgrades + OFFERINGS + wheel boost
		-- + placed-pet + perfect. Rebirth luck is deliberately excluded here (it feeds
		-- MUTATION odds below instead) so a permanent multiplier can't run tier access away.
		local petLuck = 1
		for _, e in ipairs(data.Brainrots) do
			if e.PadIndex and petLuckByName[e.Name] then petLuck *= petLuckByName[e.Name] end
		end
		local accessLuck = rock.Luck
			* UpgradeConfig.Mult(data.Upgrades, "Luck")
			* OfferingConfig.LuckMult(data.Offerings)
			* PlayerDataManager.BoostMult(data, "Luck")
			* petLuck
			* (perfect and PERFECT_LUCK_MULT or 1)

		-- roll a tier from the curve. A top-of-curve (Secret) roll is routed through the
		-- God index so Pete still gets his independent 1-in-a-million FixedChance shot;
		-- PickInTier(God) rolls Pete, else falls through to a Secret. pickIndex is reused
		-- by the reveal-time re-rolls below (vaulted / limited fallbacks).
		local rolledTier = RarityCurve.RollTierIndex(distance, accessLuck)

		-- === Pity: cap dry streaks. Every throw that REACHES a tier's distance ticks that
		-- tier's counter up; once it passes the threshold, the HIGHEST eligible tier gets ONE
		-- boosted (never guaranteed) shot to bump this roll up to it. Counters reset when you
		-- actually catch that tier or higher (revealCatch). See PityConfig for the tunables.
		data.Pity = data.Pity or {}
		for _, pity in ipairs(PityConfig) do
			local tIdx = tierIndexByName[pity.Tier]
			if tIdx and distance >= RarityConfig[tIdx].MinDistance then
				data.Pity[pity.Tier] = (data.Pity[pity.Tier] or 0) + 1
			end
		end
		local pityTierName
		for i = #PityConfig, 1, -1 do   -- highest tier first: one pity bump per throw
			local pity = PityConfig[i]
			local tIdx = tierIndexByName[pity.Tier]
			if tIdx and tIdx > rolledTier
				and distance >= RarityConfig[tIdx].MinDistance
				and (data.Pity[pity.Tier] or 0) >= pity.Threshold
				and math.random() < pity.Chance then
				rolledTier = tIdx
				pityTierName = pity.Tier
				break
			end
		end
		-- pity fired: flash a "<TIER> PITY THROW!" banner as the rock flies. The catch that
		-- lands will be at least this tier (rolledTier was just bumped up to it).
		if pityTierName then
			local pt = RarityConfig[tierIndexByName[pityTierName]]
			pityRemote:FireClient(player, pityTierName, pt and pt.Color)
		end

		local pickIndex = (rolledTier >= RarityCurve.TopTier) and RarityCurve.GodIndex or rolledTier
		local brainrotEntry, tier = RarityRoll.PickInTier(pickIndex)
		if not brainrotEntry then abandonFlight(); return end   -- empty tier: never hand out a nil catch

		-- set by the test hook below; makes this catch exempt from the
		-- reveal-time catchability re-check (see revealCatch)
		local forcedCatch = false

		-- === TEST HOOK: one-shot forced catch ===============================
		-- Armed by setting attributes on ServerStorage. They live in the place
		-- file, so they survive the Edit -> Play transition (a module-level Lua
		-- flag would not -- the server VM is rebuilt on Play).
		--     ForceNextCatch    = "<brainrot name>"   e.g. "Chim"
		--     ForceNextCatchFor = "<username>"        optional; blank = anyone
		--
		-- CONSUMED EXACTLY ONCE: the attribute is cleared the instant it fires,
		-- so a flag left armed by accident cannot quietly keep minting. It is
		-- cleared BEFORE any yield for the same reason the LimitedStock claim is.
		--
		-- Deliberately bypasses both the weighted pool and the catchability
		-- schedule -- that is the whole point. Chim is questline-exclusive and
		-- never rolls from a throw, so there is no other way to test it.
		do
			local want = ServerStorage:GetAttribute("ForceNextCatch")
			local who = ServerStorage:GetAttribute("ForceNextCatchFor")
			if type(want) == "string" and want ~= ""
				and (who == nil or who == "" or who == player.Name) then
				local forced
				for _, e in ipairs(BrainrotConfig) do
					if e.Name == want then forced = e break end
				end
				local forcedTier
				if forced then
					for _, t in ipairs(RarityConfig) do
						if t.Name == forced.Rarity then forcedTier = t break end
					end
				end
				if forced and forcedTier then
					ServerStorage:SetAttribute("ForceNextCatch", nil)
					brainrotEntry, tier = forced, forcedTier
					forcedCatch = true
					warn(("[ThrowHandler] TEST override consumed: %s caught %s (%s)")
						:format(player.Name, forced.Name, forcedTier.Name))
				else
					warn("[ThrowHandler] ForceNextCatch names an unknown brainrot: " .. tostring(want))
				end
			end
		end

		-- rebirth + weather luck overflow into MUTATION odds instead of tier access
		weatherMut = weatherMut * math.clamp(rebirthLuck * weatherLuck, 1, 6)
		-- the live event's own mutation gets first refusal, then the base table
		local mutation = Mutations.Roll(weatherMut, ReplicatedStorage:GetAttribute("WeatherName"))

		-- === serial identity: only for catches worth arguing over ===
		-- Top three tiers or anything mutated. Commons would flood the mint store
		-- with keys nobody will ever quote in a trade.
		local tracked = MintRegistry.IsTracked(tier.Name, mutation)
		if tracked then
			-- Warm the serial block NOW, while the stone is still in the air (the skip
			-- takes 1.15-4.2s). By the time revealCatch runs the number is already in
			-- memory, so the catch itself never waits on a DataStore. Non-yielding.
			pcall(MintRegistry.Prepare, brainrotEntry.Name, mutation)
		end

		-- throw progress counts right away; the catch is granted + revealed only once
		-- the stone finishes skipping and settles in the water (see onLand below).
		SeasonPassHandler.Notify(player, "Throw", 1)
		if perfect then SeasonPassHandler.Notify(player, "Perfect", 1) end

		local function revealCatch()
			local liveData = PlayerDataManager.Get(player)
			if not liveData then return end -- player left mid-flight

			-- === hard mint cap: reserve a slot BEFORE anything is granted ===
			-- Claimed here rather than at roll time for two reasons: this is the moment the
			-- item actually becomes the player's, and TryClaim yields on UpdateAsync, which
			-- the throw handler must never do. At 1e-6 this branch runs essentially never.
			--
			-- Deliberately fail-CLOSED, unlike MintRegistry above: a serial is a garnish and
			-- is fine to lose, but minting a sixth Pete cannot be undone. If the last slot
			-- went to another server between the roll and this reveal, the player gets an
			-- ordinary catch for the tier instead of nothing.
			-- The stone flies for up to 4.2s: a weekly tide flip or a season turn
			-- mid-flight must not land an away/vaulted catch. Clock-pure and
			-- non-yielding, so it is allowed on the reveal path.
			-- forcedCatch bypasses this: a test override deliberately targets
			-- entries the schedule says are unobtainable (Chim is questline-only),
			-- so re-checking here would silently swap it for an ordinary catch.
			if not forcedCatch and not Waves.IsObtainable(brainrotEntry.Name) then
				local fallback, fallbackTier = RarityRoll.PickInTier(baseTier + promotions, true)
				if not fallback then return end
				brainrotEntry, tier = fallback, fallbackTier
				tracked = MintRegistry.IsTracked(tier.Name, mutation)
			end

			if LimitedStock.IsLimited(brainrotEntry.Name) then
				if not LimitedStock.TryClaim(brainrotEntry.Name) then
					local fallback, fallbackTier = RarityRoll.PickInTier(baseTier + promotions, true)
					if not fallback then return end
					brainrotEntry, tier = fallback, fallbackTier
					-- re-evaluated because the fallback may sit in a different tier; its serial
					-- block was never warmed, so Mint() will likely return nil and the catch
					-- simply arrives without a serial
					tracked = MintRegistry.IsTracked(tier.Name, mutation)
				end
			end

			liveData.Discovered = liveData.Discovered or {}
			liveData.Discovered[brainrotEntry.Name] = true
			SeasonPassHandler.NotifyCatch(player, tier.Name)
			-- Maxwell's step 1 counts Secret-rarity catches. Guarded so a quest hiccup
			-- can never break the catch itself.
			pcall(MaxwellQuest.NotifyCatch, player, tier.Name)

			-- Mint() never yields and never errors -- it returns nil whenever the
			-- registry is cold or the DataStore is down. A missing serial costs the
			-- player a garnish; a blocked or lost catch would cost them the catch.
			-- The pcall is belt-and-braces so no failure mode can reach the grant below.
			local serial, mintedAt, exists
			if tracked then
				local okMint, s = pcall(MintRegistry.Mint, brainrotEntry.Name, mutation)
				if okMint and type(s) == "number" then
					serial = s
					mintedAt = os.time()
					local okGet, _, live = pcall(MintRegistry.Get, brainrotEntry.Name, mutation)
					if okGet and type(live) == "number" then exists = live end
				end
			end

			-- caught brainrots go to the inventory; the player places them when they choose
			local caught = {
				Name = brainrotEntry.Name,
				PadIndex = nil,
				Pending = 0,
				Mutation = mutation,
				Uid = PlayerDataManager.TakeUid(liveData),
			}
			if serial then
				caught.Serial = serial       -- mint number within its (Name, Mutation) class
				caught.MintedAt = mintedAt   -- os.time() of the catch; proves who had it first
			end
			table.insert(liveData.Brainrots, caught)
			-- Leaderboard stat. Counted HERE and nowhere else, so it measures catches rather
			-- than holdings: trades, booth buys and eggs must never inflate it.
			liveData.BrainrotsCaught = (liveData.BrainrotsCaught or 0) + 1
			InventoryHandler.SyncBackpack(player)

			-- server-wide hype banner for top-end catches
			if tier.Name == "Secret" or tier.Name == "God" or mutation == "Rainbow" or mutation == "Glitched" then
				local rare = remotes:FindFirstChild("RareCatch")
				if rare then
					rare:FireAllClients(player.Name, tier.Name, brainrotEntry.Name, tier.Color, mutation)
				end
			end

			remotes.ThrowResult:FireClient(player, {
				Distance = math.floor(distance),
				BrainrotName = brainrotEntry.Name,
				Rarity = tier.Name,
				RarityColor = tier.Color,
				CashPerSecond = brainrotEntry.CashPerSecond,
				Mutation = mutation,
				MutationMult = Mutations.Mult(mutation),
				Perfect = perfect,
				-- all three are nil unless this catch was worth tracking AND the mint
				-- registry answered; the popup should just omit the line when nil
				Serial = serial,     -- e.g. 47 -> the popup can show "#47"
				MintedAt = mintedAt,
				Exists = exists,     -- how many of this exact class are still alive
			})

			-- pity: catching a tier clears its dry streak, and every LOWER pity tier's too
			local caughtIdx = tierIndexByName[tier.Name]
			if caughtIdx and liveData.Pity then
				for _, pity in ipairs(PityConfig) do
					local tIdx = tierIndexByName[pity.Tier]
					if tIdx and caughtIdx >= tIdx then liveData.Pity[pity.Tier] = 0 end
				end
			end

			PlayerDataManager.PushUpdate(player)
		end

		-- launch the skip; reveal the catch the moment the stone settles
		task.delay(0.16, function()
			spawnSkippingStone(player, distance, rock, function()
				-- Cleared AFTER the reveal, not before: revealCatch can yield on a limited
				-- mint claim, and the throw should stay locked for that. pcall so a failed
				-- reveal can never leave the player permanently unable to throw.
				local ok, err = pcall(revealCatch)
				if flightToken[player.UserId] == token then
					inFlight[player.UserId] = nil
				end
				if not ok then
					warn("[ThrowHandler] revealCatch failed for " .. player.Name .. ": " .. tostring(err))
				end
			end)
		end)

		-- Watchdog: if that task ever dies before landing, the flag would strand the
		-- player unable to throw for the rest of the session. Token-guarded so it only
		-- ever clears the throw it was started for.
		task.delay(MAX_FLIGHT + 2, function()
			if flightToken[player.UserId] == token and inFlight[player.UserId] then
				inFlight[player.UserId] = nil
				warn("[ThrowHandler] flight watchdog cleared a stuck throw for " .. player.Name)
			end
		end)
	end)
end

return ThrowHandler
