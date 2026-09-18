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
-- RockConfig is reached through WorldProgression now: the index below has to cover
-- every world's shelf, not just the valley's.
local WorldProgression = require(ReplicatedStorage.Modules.WorldProgression)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
-- SIZE is a second, INDEPENDENT mutation axis, rolled separately from Mutations and
-- stored beside it rather than instead of it -- see SizeConfig's header for why it is
-- not simply more rows in MutationConfig.List.
local Sizes = require(ReplicatedStorage.Modules.SizeConfig)
local RebirthConfig = require(ReplicatedStorage.Modules.RebirthConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local OfferingConfig = require(ReplicatedStorage.Modules.OfferingConfig)
local BrainrotSpawner = require(ServerScriptService.Modules.BrainrotSpawner)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local MaxwellQuest = require(ServerScriptService.Modules.MaxwellQuest)

local TungQuest = require(ServerScriptService.Modules.TungQuest)
local TundraQuest = require(ServerScriptService.Modules.TundraQuest)
local SeasonPassHandler = require(ServerScriptService.Modules.SeasonPassHandler)
local MintRegistry = require(ServerScriptService.Modules.MintRegistry)
local LimitedStock = require(ServerScriptService.Modules.LimitedStock)
local Waves = require(ReplicatedStorage.Modules.BrainrotWaves)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RockDesign = require(ReplicatedStorage.Modules.RockDesign)
local DarrelService = require(ServerScriptService.Modules.DarrelService)
local PetHandler = require(ServerScriptService.Modules.PetHandler)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)

local remotes = ReplicatedStorage.Remotes
local THROW_Z = 15
local MAX_TOTAL_DISTANCE = 900

-- EVERY world's rocks, not just the valley's. A rock bought at the tundra stall is a
-- normal owned rock and can be thrown anywhere; if this index held only RockConfig,
-- data.EquippedRock would miss and the fallback below would silently demote its owner
-- to Pebble mid-throw.
local rockById = {}
for _, rock in ipairs(WorldProgression.AllRocks()) do
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

-- Names capped at one per player. Needed here because a throw can now roll a Unique
-- name (Chim) -- see the cap check on the reveal path below.
local uniqueByName = {}
for _, e in ipairs(BrainrotConfig) do
	if e.Unique then uniqueByName[e.Name] = true end
end

-- fired to the throwing player when a pity boost lands, for the "<TIER> PITY THROW!" banner
local pityRemote = remotes:FindFirstChild("PityThrow")
if not pityRemote then
	pityRemote = Instance.new("RemoteEvent")
	pityRemote.Name = "PityThrow"
	pityRemote.Parent = remotes
end

-- fired to EVERY client at flight start when a throw has already rolled a
-- cinematic-worthy size: the thrower stages the takeover, nearby players the
-- spectator variant. Fired from spawnSkippingStone because only it knows the
-- arc's timing and end point.
-- Renamed MassiveCinematic -> CatchCinematic (2026-09-17): it now carries every cut
-- (Mythic, Secret, God, Huge, Massive, MassiveGod), chosen by Config.CUT_FOR.
local cinematicRemote = remotes:FindFirstChild("CatchCinematic")
if not cinematicRemote then
	cinematicRemote = Instance.new("RemoteEvent")
	cinematicRemote.Name = "CatchCinematic"
	cinematicRemote.Parent = remotes
end
-- COSMETIC MODULE, DELIBERATELY A SOFT DEPENDENCY. This is the core throw loop, and a
-- cutscene must never eat a catch: a hard require here would mean that renaming,
-- deleting or breaking CatchCinematic takes EVERY throw in the game down with it. The
-- pcall covers the path lookup as well as the require, because indexing a missing
-- CatchCinematic folder throws on its own. The fallback is a CUT_FOR that always says
-- nil, which reads as "nothing is cinematic" -- throws then grant catches exactly as
-- they did before this build, just with no cutscene.
local okCin, CinematicConfig = pcall(function()
	return require(ReplicatedStorage.Modules.CatchCinematic.Config)
end)
if not okCin or type(CinematicConfig) ~= "table" or type(CinematicConfig.CUT_FOR) ~= "function" then
	warn("[ThrowHandler] CatchCinematic.Config unavailable (" .. tostring(CinematicConfig)
		.. "); catch cutscenes are disabled for this server")
	CinematicConfig = { CUT_FOR = function() return nil end }
end

-- Each rock's own thrown look now lives in ReplicatedStorage.Modules.RockDesign
-- so Rocco's shelf display and the thrown rock cannot drift apart. The private
-- table this replaces only covered the 8 original Ids, so the 6 later rocks all
-- threw as the same generic slate block.

local raritySignFolder = Workspace:WaitForChild("GameWorld")

--============================ SKIP SURFACES =============================--
-- THERE ARE TWO SKIP AREAS NOW. The hub lake is open water at y 1.5; the Frozen
-- Tundra's is a solid sea-ice plane at y 1999, 8000 studs away. Everything a throw
-- draws -- the skip path, the splashes, the ripples, the settle pose -- used to be
-- pinned to the hub's single WATER_Y, so a stone thrown in the tundra skipped along
-- an invisible plane two thousand studs beneath the ice.
--
-- A skip area is any BasePart named ThrowZone under GameWorld. It carries its own
-- surface height and the Z its skip path starts at as attributes, so a third one is a
-- build-time job with no edit here. Defaults are the hub's old constants, which means
-- a zone authored without attributes still behaves exactly as before.
local DEFAULT_SURFACE_Y = 1.5
local DEFAULT_SKIP_START_Z = 28

local function surfaceYOf(zone)
	return (zone and zone:GetAttribute("SurfaceY")) or DEFAULT_SURFACE_Y
end

local function skipStartZOf(zone)
	return (zone and zone:GetAttribute("SkipStartZ")) or DEFAULT_SKIP_START_Z
end

-- Cached rather than walked per throw: GameWorld has tens of thousands of descendants
-- and this would otherwise run on every skip, every splash.
-- DOES THIS WORLD HAVE ANYTHING TO CATCH AT ALL (2026-08-07).
-- World 2's roster (BrainrotConfigTundra) is deliberately EMPTY pending real content,
-- and an empty pool makes RarityRoll.PickInTier return nil for every tier -- so a throw
-- there falls into the "empty tier" abandon below. To the player that is indistinguishable
-- from the game swallowing the throw: the bar charges, PERFECT lands, and then nothing
-- happens until the client's ~6.7s watchdog frees the bar.
--
-- Publishing the answer as an ATTRIBUTE ON THE DOCK lets the client refuse BEFORE the
-- charge and say why. No remote needed: attributes on workspace parts replicate on their
-- own, and the flag re-derives itself whenever the zone list is rebuilt -- so the day the
-- tundra roster is filled in, this turns true with no code change anywhere.
local function worldHasCatches(worldName)
	local w = worldName and WorldProgression.Resolve(worldName)
	return w ~= nil and #(w.Pool or {}) > 0
end

local throwZones = {}
local function rebuildThrowZones()
	table.clear(throwZones)
	local gw = Workspace:FindFirstChild("GameWorld")
	if not gw then return end
	for _, d in ipairs(gw:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "ThrowZone" then
			table.insert(throwZones, d)
			-- FAIL OPEN: only ever written false for a world positively known to be
			-- empty. A client reading nil (zone seen before this ran) treats the dock
			-- exactly as it always did, so the valley can never be blocked by a race.
			d:SetAttribute("CatchesEnabled", worldHasCatches(PlayerDataManager.WorldOf(d.Position)))
		end
	end
end

task.spawn(function()
	local gw = Workspace:WaitForChild("GameWorld")
	rebuildThrowZones()
	gw.DescendantAdded:Connect(function(d)
		if d.Name == "ThrowZone" and d:IsA("BasePart") then rebuildThrowZones() end
	end)
	gw.DescendantRemoving:Connect(function(d)
		if d.Name == "ThrowZone" and d:IsA("BasePart") then task.defer(rebuildThrowZones) end
	end)
end)

-- The zone the character is standing in, or nil. Y is generous (+6) because the stance
-- mats sit above the deck bed and a jumping player should not drop out of the zone.
local function throwZoneOf(character)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	for _, zone in ipairs(throwZones) do
		local rel = zone.CFrame:PointToObjectSpace(hrp.Position)
		local s = zone.Size / 2
		if math.abs(rel.X) <= s.X and math.abs(rel.Z) <= s.Z and math.abs(rel.Y) <= s.Y + 6 then
			return zone
		end
	end
	return nil
end

-- perfect = the release landed inside the sweet-spot band. The band is ISSUED
-- BY THIS SERVER (GetSweetSpot, single-use, aged) and judged here against the
-- power the throw actually uses -- the client only draws it. Its second
-- ThrowRequest argument is ignored: it was client-authoritative once, and
-- FireServer(0.01, true) was accepted in playtest.
--
-- THE BAND MOVES AGAIN. It was pinned to the top of the bar for a while, which made
-- power = 1 both the strongest throw AND always inside the band: perfect became free,
-- and PERFECT_DISTANCE_MULT / PERFECT_LUCK_MULT turned into baseline rather than a
-- reward for precision. That is what let the auto-skip button score a perfect on every
-- throw and let a fixed-cadence macro farm perfects overnight -- neither had to aim.
--
-- It now rolls per charge inside BAND_MIN_LO..BAND_MIN_HI and never reaches the top, so
-- releasing in the band costs raw power (and so distance, which gates tier access) in
-- exchange for the two multipliers. Full power is still a fine choice; it just is not a
-- free perfect.
--
-- NOTE ON SPOOFING: a client that fakes its power can still aim straight at the band it
-- was told about, so perfect is not cheat-proof -- it never was. What the handshake buys
-- is that the client does not get to DECLARE a throw perfect, and that the honest cases
-- this game actually ships (the auto button, and macros driving real input) cannot hit it
-- reliably.
local PERFECT_DISTANCE_MULT = 1.1
local PERFECT_LUCK_MULT = 1.075

-- Where the sweet-spot band may land. Deliberately NOT touching the top of the bar: see
-- the GetSweetSpot comment for why pinning it there made perfect free.
local BAND_MIN_LO, BAND_MIN_HI = 0.62, 0.90

-- AUTO SKIP PENALTIES. Auto exists so players can idle for hours, which means it must be
-- the WORST way to fish for rares or it becomes the only way anyone plays. Distance gates
-- which tiers are reachable at all and luck shifts the odds inside them, so both are cut:
-- trimming luck alone would still let an overnight session brute-force the top tiers.
-- Auto can also never score perfect (see the auto branch below).
--
-- HONEST-CLIENT ENFORCEMENT, and worth being clear-eyed about: the server cannot tell an
-- auto throw from a manual one, so this trusts the client's own flag. That is fine for
-- what it is for -- the AFK button this game ships -- but it is not anti-cheat. What DOES
-- hold against a cheating client is that perfect is judged here against a band this
-- server issued, so nobody can simply declare their throws perfect.
-- 0.80 is not arbitrary. It is applied AFTER the MAX_TOTAL_DISTANCE clamp, so a maxed
-- player on auto lands at 900 * 0.80 = 720 studs. Read that against RarityConfig's gates:
-- Mythic opens at 640, Secret at 780, God at 900. Auto therefore tops out inside Mythic
-- and CANNOT reach Secret or God at all, which is what keeps the top of the ladder
-- something you have to actually play for.
--
-- It has to be after the clamp, not inside it: a late-game player's raw distance already
-- overshoots 900 by a wide margin, so a multiplier applied before the clamp is simply
-- swallowed by it and the penalty does nothing at all for exactly the players most able
-- to farm overnight. (Measured: manual and auto both came back at 900.0 until this moved.)
local AUTO_DISTANCE_MULT = 0.80
local AUTO_LUCK_MULT = 0.55
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

-- Ids come from SoundKit rather than living here, per the note at the top of that
-- module. TWO samples, not one pitched two ways: the skip tap is 0.39s and simply
-- cannot read as heavy, so the landing uses a 3.51s large-splash sample instead.
local SPLASH_SOUND = SoundKit.Ids.splash        -- 0.39s, the skips
local SPLASH_BIG_SOUND = SoundKit.Ids.splashBig -- 3.51s, the landing only

-- One splash sound per water contact. Created server-side so every player at the dock
-- hears each other's skips positionally, which is most of the charm.
--   index/total: 1-based contact number, used to raise the pitch across the sequence
--                the way a real stone gets lighter and quicker as it loses energy.
--   big:         the final landing -- lower, fuller, and allowed to ring longer.
local function playSplashSound(pos, big, index, total, surfaceY)
	local host = Instance.new("Part")
	host.Name = "SplashAudio"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CastShadow = false
	host.CFrame = CFrame.new(pos.X, surfaceY or DEFAULT_SURFACE_Y, pos.Z)
	host.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = big and SPLASH_BIG_SOUND or SPLASH_SOUND
	-- Still restrained -- this fires up to 8 times per throw and several players share
	-- the dock -- but 0.22 was under the music bed and the skips were getting lost.
	-- Raised to 0.32; the rolloff below is what keeps other people's throws in check,
	-- not the raw level.
	sound.Volume = big and 0.68 or 0.32
	-- The skip asset is 0.39s (an earlier comment here claimed 2.4s -- it was wrong).
	-- Pitching it UP brightens the transient and shortens the tail further, which is
	-- what makes a skip read as a skip rather than a belly-flop.
	local progress = (total and total > 1) and ((index - 1) / (total - 1)) or 0
	local jitter = (math.random() - 0.5) * 0.08   -- so repeated skips are not identical
	-- The landing only eases DOWN to 0.95 -- its sample is already a heavy wash, and
	-- pitching a 3.51s file much lower just turns the tail to mud.
	sound.PlaybackSpeed = (big and 0.95 or (1.45 + progress * 0.35)) + jitter
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = 240
	sound.Parent = host
	sound:Play()

	-- Fade before removing the part: cutting a wash dead mid-tail clicks. The landing
	-- holds 1.8s and is faded out from 1.66s -- deliberately SHORTER than its 3.7s
	-- sample, so the lake gets a big front end without a tail that outlasts the throw.
	local hold = big and 1.80 or 0.42
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
-- The final landing was scaled up across all five layers (ripples, droplets,
-- light, column, sound): it is the payoff of the whole throw and it was reading
-- as just one more skip. It fires ONCE per throw, so the extra third ripple is
-- one additional part on one contact -- the per-skip cost is unchanged.
--
-- Part budget matters: this fires up to 8 times per throw and it is SERVER-created, so
-- every part replicates to every client at the dock. Measured on a real 8-contact throw:
-- 17 ripples + 8 droplet hosts + 1 column = 26 parts, against 16 for the old version.
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

local function ripple(pos, delay, startD, endD, life, alpha, surfaceY)
	task.delay(delay, function()
		local TweenService = game:GetService("TweenService")
		local ring = Instance.new("Part")
		ring.Name = "SkipRipple"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.12, startD, startD)
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(226, 244, 255)
		ring.Transparency = alpha
		ring.CFrame = CFrame.new(pos.X, (surfaceY or DEFAULT_SURFACE_Y) + 0.04, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		decorPart(ring)
		-- Quad easing: a real ripple sprints outward then slows, where the old Linear
		-- tween expanded at a constant rate and looked mechanical.
		TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.12, endD, endD), Transparency = 1 }):Play()
		Debris:AddItem(ring, life + 0.15)
	end)
end

local function spawnSplash(pos, big, surfaceY)
	local TweenService = game:GetService("TweenService")
	local scale = big and 2.6 or 1
	surfaceY = surfaceY or DEFAULT_SURFACE_Y

	-- lead ripple, plus a trailing one that chases it. The landing sheds a THIRD,
	-- slowest, widest ring -- a big impact pushes out a longer train than a skip,
	-- and the late wide ring is what makes the lake look like it took the hit.
	ripple(pos, 0, 1.6, 12 * scale, big and 0.80 or 0.62, 0.35, surfaceY)
	if big then
		ripple(pos, 0.10, 1.2, 28, 1.05, 0.58, surfaceY)
		ripple(pos, 0.26, 1.0, 40, 1.45, 0.72, surfaceY)
	else
		ripple(pos, 0.09, 1.0, 6.5, 0.44, 0.68, surfaceY)
	end

	-- droplet burst
	local host = Instance.new("Part")
	host.Name = "SkipSplash"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.Transparency = 1
	host.CFrame = CFrame.new(pos.X, surfaceY + 0.15, pos.Z)
	decorPart(host)

	local e = Instance.new("ParticleEmitter")
	e.Texture = SPLASH_TEX
	e.Rate = 0                                  -- burst only, via :Emit below
	e.Lifetime = NumberRange.new(0.30, big and 0.92 or 0.62)
	e.Speed = NumberRange.new(big and 16 or 9, 20 + 10 * scale)
	e.EmissionDirection = Enum.NormalId.Top
	-- narrow-ish cone: water leaves the surface upward and outward, not spherically
	e.SpreadAngle = Vector2.new(46, 46)
	e.Acceleration = Vector3.new(0, -95, 0)     -- gravity, so droplets ARC instead of drifting
	e.Drag = 1.2
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, big and 0.85 or 0.42, 0.18),
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
	e:Emit(big and 70 or 14)

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
	light.Range = (big and 48 or 20) * (nightBoost > 1 and 1.35 or 1)
	light.Brightness = (big and 4.6 or 1.7) * nightBoost
	light.Shadows = false
	light.Parent = host
	-- Fade rather than cut: a light that vanishes mid-brightness pops. Short on a skip so
	-- eight of them never overlap into one continuous glow; longer on the landing.
	TweenService:Create(light, TweenInfo.new(big and 0.80 or 0.26,
		Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()

	-- must outlast the droplet Lifetime above or the burst is cut mid-arc
	Debris:AddItem(host, big and 1.60 or 1.0)

	-- vertical spout, only worth the part on the landing
	if big then
		local col = Instance.new("Part")
		col.Name = "SkipColumn"
		col.Shape = Enum.PartType.Cylinder
		col.Size = Vector3.new(0.6, 2.4, 2.4)
		col.Material = Enum.Material.Neon
		col.Color = Color3.fromRGB(240, 251, 255)
		col.Transparency = 0.28
		col.CFrame = CFrame.new(pos.X, surfaceY + 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
		decorPart(col)
		TweenService:Create(col, TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = Vector3.new(10.5, 2.0, 2.0) }):Play()
		task.delay(0.21, function()
			if col.Parent then
				TweenService:Create(col, TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(col, 0.80)
	end
end

local function spawnSkippingStone(player, distance, rock, onLand, zone, cinematic)
	local origin, dir = getThrowOrigin(player)
	local horiz = Vector3.new(0, 0, 1) -- always toward the distance markers
	-- Both skip areas face +Z, so the path is still a straight run up the lane; what
	-- differs per zone is how high the surface is and where the lane starts.
	local surfaceY = surfaceYOf(zone)

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
	local startFlat = Vector3.new(origin.X, surfaceY, math.max(origin.Z, skipStartZOf(zone)))
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

	-- nContacts + segTime ride the EXISTING payload rather than a new remote or one
	-- event per bounce: the arc is fully deterministic, so the client ticks its own
	-- counter off segTime. One payload change instead of up to 8 fires per throw.
	-- Splash k happens at k*segTime after this fires (see the loop below), and the
	-- client receives this payload and hears each splash both one-way-late, so the
	-- latency cancels and a client-side tick at k*segTime lands on the splash.
	remotes.StoneThrown:FireClient(player, origin, points[#points], totalTime, distance, nContacts, segTime)

	-- The SAME moment, but to EVERYONE. Only this function knows the arc's timing and
	-- where it ends, so the fields the client cannot derive are appended here rather
	-- than at roll time. Clients tick their own clock from receipt, exactly as they
	-- already do for StoneThrown above, so the send latency cancels the same way.
	if cinematic then
		-- The settle point, used as-is: every point after the origin is built from
		-- startFlat, whose Y is already surfaceY, so there is nothing to reconstruct.
		cinematic.EndPos = points[#points]
		cinematic.SurfaceY = surfaceY
		cinematic.TotalTime = totalTime
		cinematic.NContacts = nContacts
		cinematic.SegTime = segTime
		cinematicRemote:FireAllClients(cinematic)
	end

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
			-- A cinematic throw's FINAL contact is the bonk: clients stage it
			-- themselves (dry clonk, ricochet), so the server plays no splash
			-- and hands the stone off by destroying its copy at the contact.
			if not (isLast and cinematic) then
				spawnSplash(b, isLast, surfaceY)
				playSplashSound(b, isLast, k, #points - 1, surfaceY)
			end
		end
		local last = points[#points]
		if cinematic then
			stone:Destroy()
		else
			stone:PivotTo(CFrame.new(last.X, surfaceY, last.Z) * CFrame.Angles(math.rad(6), 0, 0))
			Debris:AddItem(stone, 1.3)
		end
		-- Hand the settle point UP to the reveal. A Massive catch stages a cutscene of the
		-- creature rising out of the water, and this is the only place that knows exactly
		-- where the water was broken -- surfaceY comes from the zone, so it is right for the
		-- tundra deck as well as the hub dock.
		if onLand then onLand(Vector3.new(last.X, surfaceY, last.Z)) end
	end)
end

-- EVERY camp the player owns. A brainrot is one entry in data.Brainrots rendered on each
-- of their plots, so a catch made in the valley has to appear on the tundra camp too --
-- otherwise walking through the portal looks like it ate half your collection.
local function spawnBrainrotOnPlot(player, brainrotEntry, padIndex, mutation, sizeVariant)
	for _, plot in ipairs(PlayerDataManager.GetPlots(player)) do
		BrainrotSpawner.Spawn(plot, brainrotEntry, padIndex, mutation, nil, sizeVariant)
	end
end

-- Unchanged contract: no zones authored at all means no gating, exactly as when this
-- looked up a single GameWorld.ThrowZone and let the throw through if it was missing.
local function isInThrowZone(character)
	if #throwZones == 0 then return true end
	return throwZoneOf(character) ~= nil
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
		-- ROLLED PER CHARGE, and never touching the top of the bar.
		--
		-- This was previously pinned to the last BAND_WIDTH of the bar, on the reasoning
		-- that the perfect release and the full-power release should not pull against each
		-- other. The consequence was that holding to full power was ALWAYS perfect: no
		-- timing, no decision, no way to miss. That is what made the auto-skip button score
		-- a perfect every single time, and what made a fixed-cadence macro able to farm
		-- perfects overnight -- neither had to aim at anything.
		--
		-- With the band back in the middle of the bar the tension is the point: releasing
		-- in the band costs you raw power (and therefore distance, which gates tier access)
		-- but pays PERFECT_DISTANCE_MULT and PERFECT_LUCK_MULT. Full power is still a
		-- legitimate choice; it just is not a free perfect any more.
		--
		-- Still single-use and aged, so a client cannot replay one band across throws.
		local lo = BAND_MIN_LO + math.random() * (BAND_MIN_HI - BAND_MIN_LO)
		local band = {
			min = lo,
			max = math.min(1, lo + BAND_WIDTH),
			issuedAt = os.clock(),
		}
		pendingBand[player.UserId] = band
		return { min = band.min, max = band.max }
	end

	remotes.ThrowRequest.OnServerEvent:Connect(function(player, power, clientPerfect, auto)
		-- ICE FISHING: while the Frozen Tundra lake is frozen, World-2 throwing is OFF --
		-- players fish at the holes instead. Authoritative backstop; ClientMain also hides
		-- the throw minigame at the tundra dock. Valley throwing is unaffected.
		if ReplicatedStorage:GetAttribute("IceFishingActive")
			and PlayerDataManager.PlayerWorld(player) == "Tundra" then
			return
		end
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
		local isAuto = auto and true or false
		-- An auto throw can never be perfect, whatever power it happens to land on. Without
		-- this, randomising the auto release would still hand it the occasional perfect and
		-- an all-night session would collect plenty of them.
		local perfect = (not isAuto)
			and band ~= nil
			and (now - band.issuedAt) <= BAND_MAX_AGE
			and power >= band.min and power <= band.max

		if not isInThrowZone(player.Character) then return end
		-- Captured HERE, at the last validation, rather than at launch: the reveal path
		-- below yields (mint claims, season writes) and the player can wander off the deck
		-- in between. The stone should skip on the surface they threw from.
		local throwZone = throwZoneOf(player.Character)

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

		-- AFTER the clamp, deliberately -- see AUTO_DISTANCE_MULT's comment. Inside it, a
		-- maxed player's auto throws stayed pinned at the 900 cap and the penalty vanished.
		if isAuto then
			distance = distance * AUTO_DISTANCE_MULT
		end

		-- === Rarity: DISTANCE + LUCK weight a probabilistic roll (RarityCurve) ===
		-- Distance no longer GUARANTEES a tier -- it unlocks higher tiers and shifts the
		-- odds up; luck shifts them further; higher tiers are geometrically rarer and
		-- nothing is a lock. The old model floored the tier at your distance, which made
		-- Mythic+ a certainty for a long enough throw. Tunables + curve live in
		-- ReplicatedStorage.Modules.RarityCurve (shared with the luck HUD).
		local rebirthLuck = RebirthConfig.LuckMult(data.Rebirths)
		local weatherLuck = ReplicatedStorage:GetAttribute("WeatherLuck") or 1
		local weatherMut = ReplicatedStorage:GetAttribute("WeatherMut") or 1

		-- ADDITIVE access luck: every source contributes a BONUS (its multiplier minus 1)
		-- and the bonuses SUM onto a base of 1, instead of multiplying against each other.
		-- Stacking is now linear and self-limiting -- rock + charm + offerings + wheel boost +
		-- placed pets each add their bit, so a maxed setup lands near +15 rather than the old
		-- runaway x60. Rebirth luck is still excluded here (it feeds MUTATION odds below).
		-- Placed-brainrot luck is summed the same way PetConfig.StackedMult already sums
		-- equipped pets: two +0.5 pets make +1.0, never x2.25.
		local petLuckBonus = 0
		for _, e in ipairs(data.Brainrots) do
			if e.PadIndex and petLuckByName[e.Name] then
				petLuckBonus += (petLuckByName[e.Name] - 1)
			end
		end
		-- Weather adds a flat event bonus IDENTICAL for every player. weatherLuck is a
		-- multiplier attribute, so (weatherLuck - 1) is that bonus -- 0 when no luck event is live.
		local weatherAccessBonus = math.max(weatherLuck - 1, 0)
		local personalAccess = 1
			+ (rock.Luck - 1)
			+ (UpgradeConfig.Mult(data.Upgrades, "Luck") - 1)
			+ (OfferingConfig.LuckMult(data.Offerings) - 1)
			+ (PlayerDataManager.BoostMult(data, "Luck") - 1)
			+ petLuckBonus
		-- Perfect and auto stay as per-throw MULTIPLIERS on the summed total: they are throw
		-- quality, not a stacked source. (Folding auto into the sum would erase the AFK penalty --
		-- -0.45 off a ~15 total is nothing; x0.55 on the total is not.)
		local accessLuck = (personalAccess + weatherAccessBonus)
			* (perfect and PERFECT_LUCK_MULT or 1)
			* (isAuto and AUTO_LUCK_MULT or 1)

		-- roll a tier from the curve. A top-of-curve (Secret) roll is routed through the
		-- God index so Pete still gets his independent 1-in-a-million FixedChance shot;
		-- PickInTier(God) rolls Pete, else falls through to a Secret. pickIndex is reused
		-- by the reveal-time re-rolls below (vaulted / limited fallbacks).
		-- WHICH WORLD IS THIS THROW IN. The tundra has its own ladder and its own pool, so
		-- the curve, the pick and the pity bands all have to be asked for that world.
		-- PlayerWorld returns BoundsGuard's region name, which is what WorldProgression
		-- is keyed on.
		local throwWorld = PlayerDataManager.PlayerWorld(player)
		local curve = RarityCurve.For(throwWorld)
		-- tier name -> index within THIS world's ladder. The module-level tierIndexByName
		-- is the valley's, and the tundra's bands are not the same distances.
		local wIdx = {}
		for i, t in ipairs(curve.Rarities) do wIdx[t.Name] = i end
		local rolledTier = curve.RollTierIndex(distance, accessLuck)

		-- === Pity: cap dry streaks. Every throw that REACHES a tier's distance ticks that
		-- tier's counter up; once it passes the threshold, the HIGHEST eligible tier gets ONE
		-- boosted (never guaranteed) shot to bump this roll up to it. Counters reset when you
		-- actually catch that tier or higher (revealCatch). See PityConfig for the tunables.
		data.Pity = data.Pity or {}
		for _, pity in ipairs(PityConfig) do
			local tIdx = wIdx[pity.Tier]
			if tIdx and distance >= curve.Rarities[tIdx].MinDistance then
				data.Pity[pity.Tier] = (data.Pity[pity.Tier] or 0) + 1
			end
		end
		local pityTierName
		for i = #PityConfig, 1, -1 do   -- highest tier first: one pity bump per throw
			local pity = PityConfig[i]
			local tIdx = wIdx[pity.Tier]
			if tIdx and tIdx > rolledTier
				and distance >= curve.Rarities[tIdx].MinDistance
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
			local pt = curve.Rarities[wIdx[pityTierName]]
			pityRemote:FireClient(player, pityTierName, pt and pt.Color)
		end

		-- A top-of-curve roll is routed at this world's APEX tier so its FixedChance
		-- entries get their shot first and otherwise fall back to the tier below.
		-- Valley: Secret Pete. Tundra: the ten Glitched. Same mechanism, different table.
		local pickIndex = (rolledTier >= curve.TopTier) and curve.ApexIndex or rolledTier
		local brainrotEntry, tier = RarityRoll.PickInTier(pickIndex, false, throwWorld)
		-- Empty tier: never hand out a nil catch. Kept as the last line of defence --
		-- the client now refuses to charge at a dock whose world has no roster (see
		-- worldHasCatches / the CatchesEnabled attribute above), so in normal play this
		-- is unreachable. It still catches the narrower case of a world that HAS a
		-- roster whose every entry is filtered out by isLive (all vaulted / sold out).
		if not brainrotEntry then abandonFlight(); return end

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

		-- ADDITIVE mutation luck, same rule as access luck above: rebirth + equipped-pet bonuses
		-- SUM onto a base of 1, and the event's own mutation value adds the same flat bonus for
		-- everyone. The old x6 clamp is GONE -- additive stacking is already self-limiting, and
		-- the clamp only existed to stop the multiplicative product exploding (which also made
		-- rebirth luck swallow pet luck whole). Equipped pets come through PetHandler.LuckMult,
		-- which is itself additive across pets, so this is one consistent sum end to end.
		local mutBoost = 1
			+ (rebirthLuck - 1)                     -- +0.07 per rebirth
			+ (PetHandler.LuckMult(player) - 1)     -- equipped egg pets (already additive)
			+ math.max(weatherMut - 1, 0)           -- event mutation bonus, same for everyone
		-- the live event's own mutation gets first refusal, then the base table (scaled by boost)
		local mutation = Mutations.Roll(mutBoost, ReplicatedStorage:GetAttribute("WeatherName"))

		-- SIZE ROLLED AT THROW TIME (2026-08-08, cinematic build). It rolled in
		-- revealCatch at landing before; the cinematic needs the answer while the
		-- stone is still airborne so the FINAL skip can play as the bonk. Every
		-- input to the roll (weatherMut) was already read above at this moment,
		-- so the odds are byte-identical -- the roll just happens 1-4s earlier.
		local sizeVariant = Sizes.Roll(weatherMut)
		-- TEST HOOK, mirror of ForceNextCatch above: consumed exactly once.
		do
			local wantSize = ServerStorage:GetAttribute("ForceNextSize")
			if type(wantSize) == "string" and wantSize ~= "" then
				if Sizes.ByName[wantSize] then
					ServerStorage:SetAttribute("ForceNextSize", nil)
					sizeVariant = wantSize
					warn("[ThrowHandler] TEST override consumed: next catch is " .. wantSize)
				else
					-- Left ARMED on purpose, exactly as ForceNextCatch leaves a bad name in
					-- place: a typo is fixed by correcting the attribute, and a hook that
					-- silently disarmed itself would look identical to one that fired.
					warn("[ThrowHandler] ForceNextSize names an unknown size: " .. tostring(wantSize))
				end
			end
		end
		-- Which cut, if any, this throw will play (spec S4). nil on the overwhelmingly
		-- common throw, which is exactly the "no cutscene" case.
		local cutName = CinematicConfig.CUT_FOR(tier.Name, sizeVariant)
		local cinematic = cutName and {
			UserId = player.UserId,
			BrainrotName = brainrotEntry.Name,   -- may be superseded by reveal-time
			Rarity = tier.Name,                  -- fallback swaps; client prefers
			RarityColor = tier.Color,            -- ThrowResult's name if it differs
			Mutation = mutation,
			Size = sizeVariant,
			Cut = cutName,
			RockId = rock.Id, RockColor = rock.Color,
			Seed = math.random(1, 2 ^ 30),
		} or nil

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
		DarrelService.Notify(player, "Throw", 1)
		if perfect then SeasonPassHandler.Notify(player, "Perfect", 1) end

		local function revealCatch(splashPos)
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
			-- entries the schedule says are unobtainable (Maxwell is questline-only),
			-- so re-checking here would silently swap it for an ordinary catch.
			if not forcedCatch and not Waves.IsObtainable(brainrotEntry.Name) then
				local fallback, fallbackTier = RarityRoll.PickInTier(pickIndex, true, throwWorld)
				if not fallback then return end
				brainrotEntry, tier = fallback, fallbackTier
				tracked = MintRegistry.IsTracked(tier.Name, mutation)
			end

			-- === UNIQUE CAP, ON THE CATCH PATH ===
			-- New here. BrainrotMover.Give documents the one-per-player cap as checked
			-- PRE-FLIGHT by every caller that can hand an item over -- trade, booth, quest
			-- grant -- and a THROW was never one of them, because no Unique name could be
			-- rolled. Chim can be now, so without this a player holding a Chim could simply
			-- catch a second one, which is the exact thing Unique exists to forbid.
			-- Falls back to an ordinary catch for the tier, same as a LimitedStock miss --
			-- the player still gets a Mythic, just not a duplicate of a one-off.
			if uniqueByName[brainrotEntry.Name] then
				local owned = 0
				for _, e in ipairs(liveData.Brainrots) do
					if e.Name == brainrotEntry.Name then owned += 1 end
				end
				if owned >= 1 then
					local fallback, fallbackTier = RarityRoll.PickInTier(pickIndex, true, throwWorld)
					if not fallback then return end
					brainrotEntry, tier = fallback, fallbackTier
					tracked = MintRegistry.IsTracked(tier.Name, mutation)
				end
			end

			if LimitedStock.IsLimited(brainrotEntry.Name) then
				if not LimitedStock.TryClaim(brainrotEntry.Name) then
					local fallback, fallbackTier = RarityRoll.PickInTier(pickIndex, true, throwWorld)
					if not fallback then return end
					brainrotEntry, tier = fallback, fallbackTier
					-- re-evaluated because the fallback may sit in a different tier; its serial
					-- block was never warmed, so Mint() will likely return nil and the catch
					-- simply arrives without a serial
					tracked = MintRegistry.IsTracked(tier.Name, mutation)
				end
			end

			-- Read BEFORE the write below: the reveal's "NEW BRAINROT!" header is server
			-- authoritative (spec S10) and "new" means "not in the index before this grant".
			local wasDiscovered = liveData.Discovered ~= nil and liveData.Discovered[brainrotEntry.Name] == true
			liveData.Discovered = liveData.Discovered or {}
			liveData.Discovered[brainrotEntry.Name] = true
			SeasonPassHandler.NotifyCatch(player, tier.Name)
			if tierIndexByName[tier.Name] and tierIndexByName[tier.Name] >= 4 then DarrelService.Notify(player, "Catch", 1) end
			-- Maxwell's step 1 counts Secret-rarity catches. Guarded so a quest hiccup
			-- can never break the catch itself.
			pcall(MaxwellQuest.NotifyCatch, player, tier.Name)

			pcall(TungQuest.NotifyCatch, player, tier.Name)
			-- World 2's arc: this ONE hook does both of its jobs -- counting the trial
			-- tiers and rolling the drill salvage -- because both mean "a skip finished
			-- in the tundra", and throwWorld is the only thing that decides whether it
			-- is that world's business at all.
			pcall(TundraQuest.NotifyCatch, player, tier.Name, throwWorld)
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
			-- Rolled at THROW time now, not here -- sizeVariant is an upvalue of this closure
			-- (see the roll above) because the cinematic has to be staged while the stone is
			-- still in the air. It is still rolled on the SAME catch as the colour mutation,
			-- and stored ALONGSIDE it: the two stack, so "Golden Massive" is a real outcome.
			-- nil is the overwhelmingly common result, and nil is exactly what every brainrot
			-- saved before today already reads as -- which is why this needs no migration.
			local caught = {
				Name = brainrotEntry.Name,
				PadIndex = nil,
				Pending = 0,
				Mutation = mutation,
				Size = sizeVariant,
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
				-- SIZE is the second mutation axis. Size drives the emergence cutscene on the
				-- client, and SplashPos is where to stage it -- both nil on an ordinary catch,
				-- which is exactly the "no cutscene" case.
				Size = sizeVariant,
				SizeMult = Sizes.Mult(sizeVariant),
				SplashPos = splashPos,
				Perfect = perfect,
				-- all three are nil unless this catch was worth tracking AND the mint
				-- registry answered; the popup should just omit the line when nil
				Serial = serial,     -- e.g. 47 -> the popup can show "#47"
				MintedAt = mintedAt,
				Exists = exists,     -- how many of this exact class are still alive
				IsNew = not wasDiscovered,   -- server-authoritative "NEW BRAINROT!" (spec S10)
			})

			-- pity: catching a tier clears its dry streak, and every LOWER pity tier's too
			local caughtIdx = tierIndexByName[tier.Name]
			if caughtIdx and liveData.Pity then
				for _, pity in ipairs(PityConfig) do
					local tIdx = wIdx[pity.Tier]
					if tIdx and caughtIdx >= tIdx then liveData.Pity[pity.Tier] = 0 end
				end
			end

			PlayerDataManager.PushUpdate(player)
		end

		-- launch the skip; reveal the catch the moment the stone settles
		task.delay(0.16, function()
			spawnSkippingStone(player, distance, rock, function(splashPos)
				-- Cleared AFTER the reveal, not before: revealCatch can yield on a limited
				-- mint claim, and the throw should stay locked for that. pcall so a failed
				-- reveal can never leave the player permanently unable to throw.
				local ok, err = pcall(revealCatch, splashPos)
				if flightToken[player.UserId] == token then
					inFlight[player.UserId] = nil
				end
				if not ok then
					warn("[ThrowHandler] revealCatch failed for " .. player.Name .. ": " .. tostring(err))
				end
			end, throwZone, cinematic)
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
