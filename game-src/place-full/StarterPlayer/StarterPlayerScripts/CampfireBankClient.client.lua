-- CampfireBankClient -- the entire campfire visual + feedback layer. (BUILD SPEC v2 §7.2 / §8.2)
--
-- The SERVER publishes ONE number (Campfire.Banked); every client builds the pile locally.
-- With StreamingEnabled and ~16.5k BaseParts, server-created coins would cost replication,
-- streaming bandwidth and instance churn on every resize. Client-built coins cost nothing, get
-- per-client LOD, and other players STILL see your hoard (they run this same script off the
-- same replicated attribute) -- the flex is preserved.
--
-- Everything lives in a client-created Workspace.CampfireBankVFX folder -- NEVER parented into
-- the replicated plot Model, or streaming will destroy it.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local camera = Workspace.CurrentCamera

local cueRemote = remotes:WaitForChild("CampfireCollected", 10)

local C = Color3.fromRGB

local vfxFolder = Workspace:FindFirstChild("CampfireBankVFX")
if not vfxFolder then
	vfxFolder = Instance.new("Folder")
	vfxFolder.Name = "CampfireBankVFX"
	vfxFolder.Parent = Workspace
end

-- canonical abbreviator, K through Qi -- see Modules.NumberFormat
local formatShort = require(ReplicatedStorage.Modules.NumberFormat).Short

-- ===== pile maths (spec 7.2.2) =====
local TIER_MAX = 24
local function tierFor(banked)
	if banked < 1 then return 0 end
	return math.clamp(math.floor(math.log10(banked) * 3.5) + 1, 1, TIER_MAX)
end

-- Apron ring on the CLEAR dirt between the stones (outer face 3.45) and the collect ring (5.60).
-- Never inside the flame or the logs.
local R_IN, R_OUT_MIN, R_OUT_MAX = 3.60, 4.10, 5.30
local GOLDEN = 2.39996323
local function hash01(i) local v = math.sin(i * 12.9898 + 78.233) * 43758.5453 return v - math.floor(v) end

local function coinCFrame(i, n, tier, centre, baseY)
	local f    = tier / TIER_MAX
	local rOut = R_OUT_MIN + (R_OUT_MAX - R_OUT_MIN) * f
	local t    = (i - 0.5) / n
	local r    = math.sqrt(R_IN * R_IN + t * (rOut * rOut - R_IN * R_IN))   -- even area density
	local ang  = i * GOLDEN
	local u    = (r - R_IN) / math.max(rOut - R_IN, 0.01)
	local y    = baseY + 0.06 + (0.10 + 0.55 * f) * (1 - u) ^ 2             -- banked against the stones
	local tilt = (hash01(i) - 0.5) * 0.55                                  -- deterministic, no per-coin state
	return CFrame.new(centre.X + math.cos(ang) * r, y, centre.Z + math.sin(ang) * r)
	     * CFrame.Angles(0, ang, 0) * CFrame.Angles(0, 0, math.rad(90) + tilt)
end

-- Magnitude reads as MATERIAL, not size: income spans ~384,000x, which no radius change can encode.
local COIN_BANDS = {
	{ min = 0,        mat = Enum.Material.Metal, a = C(196, 118, 68),  b = C(168, 94, 54),  refl = 0.08 }, -- Copper
	{ min = 1000,     mat = Enum.Material.Metal, a = C(214, 220, 228), b = C(178, 186, 196), refl = 0.22 }, -- Silver
	{ min = 100000,   mat = Enum.Material.Metal, a = C(255, 205, 70),  b = C(240, 168, 40),  refl = 0.14 }, -- Gold
	{ min = 10000000, mat = Enum.Material.Neon,  a = C(150, 235, 255), b = C(196, 150, 255), refl = 0.00 }, -- Gem
}
local function bandFor(banked)
	local idx = 1
	for i, b in ipairs(COIN_BANDS) do
		if banked >= b.min then idx = i end
	end
	return idx
end

local MAX_COINS_TOTAL = 90
local ctl = {}      -- [CampfirePart] = controller

-- ===== controller =====
local function newController(cf, plot)
	local dirtTop = cf.Position.Y - 0.75

	local c = {
		cf = cf, plot = plot, dirtTop = dirtTop,
		folder = Instance.new("Folder"),
		ring = {}, coins = {},
		tier = -1, band = -1, lastRebuild = 0, lowSince = nil, ringArmed = nil,
		banked = 0, lastSampleAt = os.clock(), rate = 0, lastBanked = 0, lastBankedAt = os.clock(),
		lod = 3,
	}
	c.folder.Name = "VFX_" .. plot.Name
	c.folder.Parent = vfxFolder

	-- remember the untouched baseline so teardown can restore it exactly
	local fire = cf:FindFirstChildOfClass("Fire")
	local light = cf:FindFirstChildOfClass("PointLight")
	c.fire, c.light = fire, light
	if fire then c.fireSize0, c.fireSec0 = fire.Size, fire.SecondaryColor end
	if light then c.lightB0, c.lightR0 = light.Brightness, light.Range end

	-- one-shot spark emitter (Rate 0; the burst calls :Emit)
	local att = cf:FindFirstChild("CollectSparksAtt")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "CollectSparksAtt"
		att.Parent = cf
	end
	c.att = att
	local sparks = att:FindFirstChild("CollectSparks")
	if not sparks then
		sparks = Instance.new("ParticleEmitter")
		sparks.Name = "CollectSparks"
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Rate = 0
		sparks.Lifetime = NumberRange.new(0.4, 0.9)
		sparks.Speed = NumberRange.new(6, 12)
		sparks.SpreadAngle = Vector2.new(36, 36)
		sparks.Acceleration = Vector3.new(0, -8, 0)
		sparks.LightEmission = 0.8
		sparks.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparks.Color = ColorSequence.new(C(255, 214, 90))
		sparks.Parent = att
	end
	c.sparks = sparks

	-- Collect sound: a cash register. Cloned per play, because Sound:Play() rewinds the
	-- SAME instance, so a second cue landing mid-tail would cut the first one off.
	--
	-- WHY THIS ASSET: the cue can fire every COLLECT_INTERVAL (2 s) while the owner stands
	-- in the fire, so the clip has to finish inside that window or it overlaps itself. Most
	-- "cash register" uploads are 2-4 s and are therefore unusable here regardless of how
	-- good they sound. This one is 0.89 s and comfortably clears the cadence.
	-- Verified with ContentProvider:PreloadAsync in this place: AssetFetchStatus.Success.
	-- Alternates that also load, if this is not the right character (drop-in swap; the only
	-- hard constraint is staying under ~1.5 s):
	--   87219676100463  Cash Register Sound Effect     1.22 s
	--   131886985       cash register (classic ching)  0.69 s  -- pre-2022 upload
	local REGISTER_SOUND = "rbxassetid://18264787819"   -- "Cash Register Ding", 0.89 s
	-- Sound.Volume is a LINEAR scalar, not decibels, so a dB trim has to be converted:
	-- gain = 10^(dB/20). This is 0.42 taken down -0.5 dB -> 0.42 * 0.9441 = 0.3965.
	-- The repeat-gulp voice multiplies this by 0.72 below, so it scales with it.
	local REGISTER_VOLUME = 0.3965
	local ping = cf:FindFirstChild("BankPing")
	if not ping then
		ping = Instance.new("Sound")
		ping.Name = "BankPing"
		ping.RollOffMaxDistance = 60
		ping.Parent = cf
	end
	-- Set unconditionally rather than only on create: reconcile() reuses an existing
	-- BankPing, so find-and-keep would leave a stale SoundId behind after this change.
	ping.SoundId = REGISTER_SOUND
	ping.Volume = REGISTER_VOLUME
	c.ping = ping

	-- BankGui
	local gui = cf:FindFirstChild("BankGui")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "BankGui"
		gui.Size = UDim2.new(0, 210, 0, 66)
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.MaxDistance = 150
		gui.Parent = cf

		local amount = Instance.new("TextLabel")
		amount.Name = "Amount"
		amount.Size = UDim2.new(1, 0, 0, 42)
		amount.BackgroundTransparency = 1
		amount.Font = Enum.Font.GothamBlack
		amount.TextScaled = true
		amount.TextColor3 = C(255, 214, 90)
		amount.TextStrokeTransparency = 0.25
		amount.Text = ""        -- never flash Roblox's default "Label" before the first 10 Hz pass
		amount.Parent = gui

		local hint = Instance.new("TextLabel")
		hint.Name = "Hint"
		hint.Position = UDim2.new(0, 0, 0, 44)
		hint.Size = UDim2.new(1, 0, 0, 22)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.GothamBold
		hint.TextSize = 22
		hint.TextColor3 = C(230, 235, 240)
		hint.TextStrokeTransparency = 0.4
		hint.Text = "STAND ON THE FIRE TO COLLECT"
		hint.Parent = gui
	end
	c.gui = gui
	c.amount = gui:FindFirstChild("Amount")
	c.hint = gui:FindFirstChild("Hint")

	return c
end

local function clearCoins(c)
	for _, p in ipairs(c.coins) do p:Destroy() end
	c.coins = {}
end

local function teardown(c)
	-- restore the flame exactly as we found it; these were LOCAL writes on replicated parts
	if c.fire and c.fire.Parent then
		c.fire.Size = c.fireSize0
		c.fire.SecondaryColor = c.fireSec0
	end
	if c.light and c.light.Parent then
		c.light.Brightness = c.lightB0
		c.light.Range = c.lightR0
	end
	if c.gui then c.gui:Destroy() end
	if c.embers then c.embers:Destroy() end
	if c.folder then c.folder:Destroy() end
end

-- ===== collect ring: the affordance. r 5.60 EXACTLY matches CAMPFIRE_RADIUS and CampStand =====
local function buildRing(c)
	if #c.ring > 0 then return end
	for k = 0, 15 do
		local a = math.rad(k * 22.5)
		local seg = Instance.new("Part")
		seg.Name = "RingSeg"
		seg.Size = Vector3.new(1.75, 0.10, 0.30)
		seg.CFrame = CFrame.new(c.cf.Position.X + math.cos(a) * 5.60, c.dirtTop + 0.06, c.cf.Position.Z + math.sin(a) * 5.60)
			* CFrame.Angles(0, -a, 0)
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.CastShadow = false
		seg.Locked = true
		seg.Parent = c.folder
		table.insert(c.ring, seg)
	end
	c.ringArmed = nil
end

local function clearRing(c)
	for _, s in ipairs(c.ring) do s:Destroy() end
	c.ring = {}
	c.ringArmed = nil
end

local function setRingState(c, armed)
	if c.ringArmed == armed then return end
	c.ringArmed = armed
	for _, s in ipairs(c.ring) do
		if armed then
			s.Material = Enum.Material.Neon; s.Color = C(255, 200, 80); s.Transparency = 0.10
		else
			s.Material = Enum.Material.SmoothPlastic; s.Color = C(146, 118, 74); s.Transparency = 0.45
		end
	end
end

local function buildPile(c, tier, bandIdx, budget, animate)
	clearCoins(c)
	if tier <= 0 or budget <= 0 then return end
	local band = COIN_BANDS[bandIdx]
	local n = budget
	for i = 1, n do
		local coin = Instance.new("Part")
		coin.Name = "Coin"
		coin.Shape = Enum.PartType.Cylinder     -- Roblox cylinder axis is local +X, hence the roll
		coin.Size = Vector3.new(0.14, 1.05, 1.05)
		coin.CFrame = coinCFrame(i, n, tier, c.cf.Position, c.dirtTop)
		coin.Material = band.mat
		coin.Color = (i % 2 == 0) and band.a or band.b
		coin.Reflectance = band.refl
		coin.Anchored = true
		coin.CanCollide = false
		coin.CanQuery = false
		coin.CanTouch = false
		coin.CastShadow = false
		coin.Locked = true
		coin.Parent = c.folder
		table.insert(c.coins, coin)
		if animate then
			local target = coin.CFrame
			coin.CFrame = target + Vector3.new(0, 1.6, 0)
			coin.Transparency = 1
			TweenService:Create(coin, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = target, Transparency = 0 }):Play()
		end
	end
end

-- Flame banks up -- CAPPED. Fire.Heat is NEVER written (stays 0) and Fire.Color is unchanged.
local function applyFlame(c, f)
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if c.fire and c.fire.Parent then
		TweenService:Create(c.fire, info, {
			Size = 7 + 2.0 * f,
			SecondaryColor = C(228, 88, 28):Lerp(C(255, 196, 60), f),
		}):Play()
	end
	if c.light and c.light.Parent then
		TweenService:Create(c.light, info, {
			Brightness = 2.8 + 1.2 * f,
			Range = 26 + 5.0 * f,
		}):Play()
	end
end

local function applyEmbers(c, bandIdx, f)
	if bandIdx >= 3 then
		if not c.embers or not c.embers.Parent then
			local e = Instance.new("ParticleEmitter")
			e.Name = "GoldEmbers"          -- the existing `Embers` emitter is left untouched
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.LightEmission = 0.7
			e.Speed = NumberRange.new(3, 6)
			e.Acceleration = Vector3.new(0, 6, 0)
			e.Lifetime = NumberRange.new(0.8, 1.6)
			e.SpreadAngle = Vector2.new(22, 22)
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.28), NumberSequenceKeypoint.new(1, 0) })
			e.Parent = c.cf
			c.embers = e
		end
		c.embers.Rate = 2 + 8 * f
		c.embers.Color = ColorSequence.new(COIN_BANDS[bandIdx].a)
	elseif c.embers then
		c.embers:Destroy()
		c.embers = nil
	end
end

-- ===== 10 Hz update pass (NOT RenderStepped) =====
local function updateController(c, budget, now)
	local cf = c.cf
	local banked = cf:GetAttribute("Banked") or 0

	-- client-side rate derivation from consecutive Banked samples (EMA, negative deltas ignored).
	-- No server-side rate publication -> zero coupling to the income formula.
	if banked ~= c.lastBanked then
		local dt = now - c.lastBankedAt
		if dt > 0.05 then
			local d = banked - c.lastBanked
			if d > 0 then
				c.rate = c.rate * (2 / 3) + (d / dt) * (1 / 3)
			end
		end
		c.lastBanked = banked
		c.lastBankedAt = now
		c.lastSampleAt = now
		c.banked = banked
	end
	c.banked = banked

	local dist = (camera.CFrame.Position - cf.Position).Magnitude
	local lod = (dist <= 60) and 0 or ((dist <= 140) and 1 or 2)

	local tier = tierFor(banked)
	local bandIdx = bandFor(banked)

	-- hysteresis: tier may RISE immediately; it may only FALL after the lower value has held 0.6 s
	local effTier = tier
	if tier < c.tier then
		if not c.lowSince then c.lowSince = now end
		if (now - c.lowSince) < 0.6 then effTier = c.tier end
	else
		c.lowSince = nil
	end

	-- ring: built at LOD 0 and 1 regardless of Banked, so the mechanic is always legible
	if lod <= 1 then
		buildRing(c)
		setRingState(c, banked >= 1)
	else
		clearRing(c)
	end

	local lod0 = math.min(6 + math.floor(effTier * 1.6), 44)
	local want
	if lod == 0 then want = lod0
	elseif lod == 1 then want = math.min(math.ceil(lod0 * 0.3), 14)
	else want = 0 end
	if effTier <= 0 then want = 0 end
	want = math.min(want, budget)

	local changed = (effTier ~= c.tier) or (bandIdx ~= c.band) or (lod ~= c.lod)
	if changed and (now - c.lastRebuild) >= 0.4 then
		buildPile(c, effTier, bandIdx, want, lod == 0 and c.tier >= 0)
		c.tier, c.band, c.lod, c.lastRebuild = effTier, bandIdx, lod, now
		c.rebuilds = (c.rebuilds or 0) + 1
		local f = effTier / TIER_MAX
		applyFlame(c, f)
		applyEmbers(c, bandIdx, f)
	end

	-- BankGui
	local isOwner = (c.plot:GetAttribute("OwnerUserId") or 0) == player.UserId
	local visible = (lod <= 1) and (isOwner or banked >= 1)
	c.gui.Enabled = visible
	if visible then
		local shown = math.max(banked + c.rate * (now - c.lastSampleAt), banked)
		c.amount.Text = "$" .. formatShort(shown)     -- no fire emoji: FusionPrompt already shows one
		c.hint.Visible = isOwner
		local f = math.max(effTier, 0) / TIER_MAX
		c.gui.StudsOffsetWorldSpace = Vector3.new(0, 7.6 + 1.2 * f, 0)   -- always clears the 9-stud flame cap
	end

	return #c.coins
end

-- ===== collect feedback (spec 8.2) =====
local cashFrame = nil
local coinFly = Instance.new("ScreenGui")     -- created ONCE at script scope, never per burst
coinFly.Name = "CoinFlyGui"
coinFly.DisplayOrder = 50
coinFly.ResetOnSpawn = false
coinFly.Parent = playerGui

task.spawn(function()
	local mainUI = playerGui:WaitForChild("MainUI", 20)
	if not mainUI then return end
	cashFrame = mainUI:WaitForChild("CashFrame", 20)
	-- AbsolutePosition is reported in the OWNING ScreenGui's inset space; a mismatch lands
	-- every coin ~36 px off.
	local host = cashFrame and cashFrame:FindFirstAncestorWhichIsA("ScreenGui")
	coinFly.IgnoreGuiInset = (host and host.IgnoreGuiInset) or false
end)

local function punchCash()
	if not cashFrame then return end
	local scale = cashFrame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = cashFrame
	end
	scale.Scale = 1
	TweenService:Create(scale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
	task.delay(0.09, function()
		if scale.Parent then
			TweenService:Create(scale, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 }):Play()
		end
	end)
end

local function flyCoins(c, amount)
	if not cashFrame then return end
	local target = cashFrame.AbsolutePosition + cashFrame.AbsoluteSize / 2
	local sp, onScreen = camera:WorldToViewportPoint(c.cf.Position + Vector3.new(0, 1.5, 0))
	if not onScreen then return end            -- fire behind the camera: skip the fly entirely
	local n = math.clamp(4 + math.floor(math.log10(math.max(amount, 1)) * 2), 4, 14)
	for k = 1, n do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(22, 22)
		dot.Position = UDim2.fromOffset(sp.X - 11, sp.Y - 11)
		dot.BackgroundColor3 = C(255, 205, 70)
		dot.BorderSizePixel = 0
		dot.Parent = coinFly
		local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(1, 0); cor.Parent = dot
		local st = Instance.new("UIStroke"); st.Color = C(190, 130, 20); st.Thickness = 2; st.Parent = dot
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextSize = 14
		lbl.TextColor3 = C(90, 60, 10)
		lbl.Text = "$"
		lbl.Parent = dot

		local ang = (k / n) * math.pi * 2
		local burst = UDim2.fromOffset(sp.X - 11 + math.cos(ang) * 70, sp.Y - 11 + math.sin(ang) * 70)
		TweenService:Create(dot, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = burst }):Play()
		task.delay(0.18, function()
			if not dot.Parent then return end
			local t2 = TweenService:Create(dot, TweenInfo.new(0.40 + k * 0.03, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
				{ Position = UDim2.fromOffset(target.X - 11, target.Y - 11), Size = UDim2.fromOffset(10, 10) })
			t2:Play()
			t2.Completed:Connect(punchCash)
		end)
		Debris:AddItem(dot, 1.4)
	end
end

local function playCollect(c, amount, isEntry)
	-- 1. burst
	if isEntry then
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(2, 2, 2)
		ball.CFrame = CFrame.new(c.cf.Position + Vector3.new(0, 1.2, 0))
		ball.Material = Enum.Material.Neon
		ball.Color = C(255, 205, 70)
		ball.Transparency = 0.15
		ball.Anchored = true; ball.CanCollide = false; ball.CanQuery = false
		ball.CanTouch = false; ball.CastShadow = false; ball.Locked = true
		ball.Parent = c.folder
		TweenService:Create(ball, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(8, 8, 8), Transparency = 1 }):Play()
		Debris:AddItem(ball, 0.8)
	else
		-- repeat gulps get a flat expanding RING, not another sphere
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.12, 3, 3)
		ring.CFrame = CFrame.new(c.cf.Position.X, c.dirtTop + 0.12, c.cf.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Material = Enum.Material.Neon
		ring.Color = C(255, 205, 70)
		ring.Transparency = 0.3
		ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false
		ring.CanTouch = false; ring.CastShadow = false; ring.Locked = true
		ring.Parent = c.folder
		TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.12, 12, 12), Transparency = 1 }):Play()
		Debris:AddItem(ring, 0.6)
	end
	if c.sparks then c.sparks:Emit(isEntry and 34 or 8) end

	-- 2. collect sound -- ONE register hit, cloned so overlapping cues cannot rewind
	-- each other.
	--
	-- Deliberately a SINGLE voice now. The old asset was a 0.2 s electronic ping, so it was
	-- fired as a 5-voice rising arpeggio 0.055 s apart to build a flourish out of almost
	-- nothing. A cash register is already the whole gesture -- five of them 55 ms apart is
	-- mush, not a flourish. Entry gets it clean at full volume; repeat gulps come in
	-- quieter and slightly detuned so a long stay in the fire is not machine-gunned.
	if c.ping and c.ping.Parent then
		local s = c.ping:Clone()
		s.Volume = c.ping.Volume * (isEntry and 1 or 0.72)
		s.PlaybackSpeed = isEntry and 1 or (0.97 + math.random() * 0.06)
		s.Parent = c.cf
		s:Play()
		Debris:AddItem(s, 3)
	end

	-- 3. +$X popup
	local holder = Instance.new("Part")
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(c.cf.Position + Vector3.new(0, 3.2, 0))
	holder.Transparency = 1
	holder.Anchored = true; holder.CanCollide = false; holder.CanQuery = false
	holder.CanTouch = false; holder.CastShadow = false; holder.Locked = true
	holder.Parent = c.folder
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.new(0, 190, 0, 52)
	bg.AlwaysOnTop = false
	bg.LightInfluence = 0
	-- the floating "+$X" on collect. Same 150 as the BankGui it pops out of, so a distant
	-- plot cannot flash cash numbers at you from across the map.
	bg.MaxDistance = 150
	bg.Parent = holder
	local pl = Instance.new("TextLabel")
	pl.Size = UDim2.new(1, 0, 1, 0)
	pl.BackgroundTransparency = 1
	pl.Font = Enum.Font.GothamBlack
	pl.TextScaled = true
	pl.TextColor3 = C(140, 255, 160)
	pl.TextStrokeTransparency = 0.3
	pl.Text = "+$" .. formatShort(amount)
	pl.Parent = bg
	TweenService:Create(holder, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = holder.CFrame + Vector3.new(0, 4, 0) }):Play()
	task.delay(0.45, function()
		if pl.Parent then
			TweenService:Create(pl, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(holder, 1.1)

	-- 4. coins fly to the HUD
	flyCoins(c, amount)

	-- 5. pile teardown is driven by THIS cue, not by tier hitting 0. Bystanders (who get no cue)
	-- tear down via the hysteresis rule instead, so they still see the hoard vanish.
	local coins = c.coins
	c.coins = {}
	for i, coin in ipairs(coins) do
		task.delay(i * 0.012, function()
			if not coin.Parent then return end
			TweenService:Create(coin, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = coin.CFrame + Vector3.new(0, 2.4, 0),
				Size = Vector3.new(0.02, 0.02, 0.02), Transparency = 1 }):Play()
			Debris:AddItem(coin, 0.35)
		end)
	end
	c.tier = -1        -- force the next pass to rebuild from scratch
end

if cueRemote then
	cueRemote.OnClientEvent:Connect(function(amount, isEntry)
		if type(amount) ~= "number" or amount <= 0 then return end
		for _, c in pairs(ctl) do
			if (c.plot:GetAttribute("OwnerUserId") or 0) == player.UserId then
				playCollect(c, amount, isEntry == true)
				return
			end
		end
	end)
end

-- ===== reconcile (0.5 s) + 10 Hz update =====
local function reconcile()
	local bases = Workspace:FindFirstChild("PlayerBases")
	if not bases then return end
	for _, plot in ipairs(bases:GetChildren()) do
		local cf = plot:FindFirstChild("Campfire")     -- FindFirstChild, never WaitForChild
		if cf and not ctl[cf] then ctl[cf] = newController(cf, plot) end
	end
	for cf, c in pairs(ctl) do
		if cf.Parent == nil or c.plot.Parent == nil then
			teardown(c)
			ctl[cf] = nil
		end
	end
end

reconcile()
task.spawn(function()
	while true do
		task.wait(0.5)
		reconcile()
	end
end)

task.spawn(function()
	while true do
		task.wait(0.1)                     -- 10 Hz, NOT RenderStepped
		local now = os.clock()
		-- global cap allocated greedily NEAREST-FIRST
		local order = {}
		for cf, c in pairs(ctl) do
			table.insert(order, { c = c, d = (camera.CFrame.Position - cf.Position).Magnitude })
		end
		table.sort(order, function(a, b) return a.d < b.d end)
		local left = MAX_COINS_TOTAL
		for _, o in ipairs(order) do
			local used = updateController(o.c, math.max(left, 0), now)
			left -= used
		end
	end
end)
