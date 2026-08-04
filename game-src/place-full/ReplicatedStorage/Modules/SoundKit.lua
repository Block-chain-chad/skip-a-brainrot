-- SoundKit: every sound effect in the game, in one place.
--
-- Before this there was no audio layer at all -- three stock rbxasset sounds
-- scattered across three scripts, no Sound instances saved, nothing in
-- SoundService. Sounds are declared here BY NAME so a call site never carries
-- an asset id, and changing a sound is a one-line edit instead of a hunt.
--
-- Every id below was verified to actually LOAD in this experience before being
-- added. Roblox gates third-party audio and an unusable id fails SILENTLY --
-- no error, just no sound -- so "it looked right in the code" proves nothing.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")   -- M.loop's stop fade

local M = {}

-- UIKIT (Task 10): per-category volume state, driven by the Settings
-- panel's AUDIO sliders (SettingsPanel -> M.SetCategoryVolume). `sfx` scales
-- every M.play() call (see the Volume line inside M.play below); `music` has
-- no player of its own to scale YET -- this game has no ambient/background
-- music system at all today (SoundService was confirmed to have ZERO
-- children outside what M.play() clones in-and-out, live, before this
-- change) -- so `vol.music` is stored for a future SoundService.Music folder
-- to be scaled by (SetCategoryVolume nil-guards that lookup below), and
-- simply has no audible effect yet. Not a bug: the seam is forward-compatible.
local vol = { music = 0.7, sfx = 1 }

-- category: "music" | "sfx". v is clamped to 0..1 regardless of input.
function M.SetCategoryVolume(category, v)
	if type(v) ~= "number" or v ~= v then
		warn("[SoundKit] SetCategoryVolume: not a number: " .. tostring(v))
		return
	end
	v = math.clamp(v, 0, 1)
	if category == "music" then
		vol.music = v
		-- Forward-compatible seam: scales an existing SoundService.Music
		-- folder's children directly (ambient loops would be long-lived Sound
		-- instances, not M.play() clones -- the same reasoning WheelClient's
		-- own tickSound/windSound use persistent Sound instances instead of
		-- M.play()). Nil-guarded: no such folder exists in this game yet.
		local musicFolder = SoundService:FindFirstChild("Music")
		if musicFolder then
			for _, s in ipairs(musicFolder:GetChildren()) do
				if s:IsA("Sound") then
					s.Volume = v
				end
			end
		end
	elseif category == "sfx" then
		vol.sfx = v
	else
		warn("[SoundKit] SetCategoryVolume: unknown category: " .. tostring(category))
	end
end

M.Ids = {
	-- Catch ladder: ONE SAMPLE PER RARITY. Eight tiers, eight sounds.
	--
	-- The previous ladder was four ids from a single "bling diamond pickup" family
	-- shared across the eight tiers in pairs, so a Secret was indistinguishable from
	-- a Mythic and a God from a Secret -- the ladder had no top end at all.
	--
	-- These escalate in LENGTH as well as weight (0.30s -> 2.58s), which is what
	-- actually makes a rarity read as rarer: a Common has to be over before you
	-- notice it, a God should stop you. RareCatchClient climbs the VOLUME in step.
	-- All eight were load-verified in-engine, per the note at the top of this file.
	-- THIRD pass on this ladder. The first two were rejected by ear, and both failed
	-- the same way: every rung came from one family of UI "success" jingles, so the
	-- rungs differed only in length and level and the whole thing read as one sound
	-- played eight ways. Picking a MORE DRAMATIC jingle does not fix that.
	--
	-- So this pass changes the axis: each rung is a different CLASS of sound, not a
	-- different size of the same one. plop -> cork -> chime -> eerie -> blessing ->
	-- abyss -> curse+blessing -> choir. You should be able to name the tier from the
	-- sound alone with the screen off, which was never true of the previous two.
	--
	-- Mostly drawn from the sound library already in Workspace.SFX (bless / eerychime
	-- / abyss / curse), which is a far better fit for catching an absurd creature than
	-- the menu-feedback pool the earlier passes used. All load-verified in-engine.
	catchCommon    = "rbxassetid://261732529",       -- plop, 0.13s -- a deliberate non-event
	-- FOURTH pass on the middle of this ladder. Rejected by ear so far, and worth
	-- recording so nobody walks back into them:
	--   pass 2  the UI "success" family (Success Correct / Success2 / UI Level Up /
	--           Power_Up / Rewards Level Up) -- read as menu feedback, not a catch
	--   pass 3  the `bless` family (Rare/Legendary/Secret), `abyssappear` (Mythic)
	--           and `cork-off` (Uncommon)
	-- KEPT from pass 3, explicitly liked: Common (plop), Epic (eerychime3), God (choir).
	--
	-- So the five below come from FIVE DIFFERENT families -- cartoon, magic-cast,
	-- physics impact, heavy magic, ice -- with no two neighbouring rungs sharing a
	-- source. Same reasoning as the pass-3 note: what kills these ladders is family
	-- sameness, and using five rungs of one family is how the last two died.
	catchUncommon  = "rbxassetid://90087825083279",  -- Blorp, 1.01s -- cartoon bloop
	catchRare      = "rbxassetid://4299512490",      -- magic-cast-a13, 1.74s -- magic zap
	-- Epic is back to eerychime3, per the ladder that was signed off. It was briefly
	-- swapped to flydash4 (an ascending whoosh) when Epic was called out separately,
	-- but the approved table keeps eerychime3 here.
	catchEpic      = "rbxassetid://3755109830",      -- eerychime3, 1.90s -- odd, not triumphant
	catchLegend    = "rbxassetid://3778610036",      -- earthburst3, 2.07s -- physical impact burst
	catchMythic    = "rbxassetid://3750993658",      -- magic-cast-heavy04, 2.86s -- heavy cast
	catchSecret    = "rbxassetid://632669170",       -- ice-magic02, 2.62s -- icy shatter
	-- God is capped at 5 mints in the entire game (see RarityConfig): it gets the
	-- choir, the biggest thing in the kit. Shares the `angel` id below, which cannot
	-- collide in practice -- an Angel-mutated catch takes the mutation branch in
	-- RareCatchClient and never reaches the tier sound at all.
	catchGod       = "rbxassetid://102859001475552", -- choir, 2.58s
	-- Stacking layers for the top three rungs. Length and volume alone flatten out by
	-- the time you reach Secret -- there is nowhere left to go -- so density carries
	-- the last stretch: an impact to land the moment and a sparkle over the top.
	catchBigHit    = "rbxassetid://4612374036",      -- bling BIG, 2.01s -- impact layer
	catchSparkle   = "rbxassetid://132990201173758", -- Twinkling, 0.63s -- shimmer layer
	catchDrama     = "rbxassetid://3750940830",      -- curse01, 2.45s -- the "uh oh, this is big" layer
	-- generic sting for a rare mutation; REPLACES the catch sound, never layers
	mutation    = "rbxassetid://4612374036",
	-- The top mutations get their OWN voice rather than a pitched-up version of
	-- everything else. See MUTATION_SOUND in RareCatchClient for the mapping.
	angel       = "rbxassetid://102859001475552",   -- choir, 2.6s        (Angel, r12)
	demon       = "rbxassetid://9114628818",        -- deep growl, 2.1s   (Demon, r11)
	glitched    = "rbxassetid://137930743906958",   -- glitch sfx, 1.8s   (Glitched, r10)
	cash        = "rbxassetid://9113848943",        -- SFX2 default (was coin_effect 6786936397)
	place       = "rbxassetid://9113805426",        -- ProSoundEffects, dirt impact
	uiClick     = "rbxassetid://9119717523",        -- SFX2 default (was rbxasset switch.wav)
	splash      = "rbxassetid://9117946641",        -- SFX2 default, 0.39s: a SKIP tap, not a wash
	-- The final landing wants a genuinely different sample, not just a louder tap:
	-- 0.39s cannot sound heavy no matter what you do to its volume or pitch.
	splashBig   = "rbxassetid://4086001962",        -- water-splash-large, 3.51s
	-- Egg hatch (EggShopClient.playReveal): three crack beats, then the shell
	-- splits. All three ids are lifted straight out of the 476-sound library
	-- already sitting in Workspace.SFX -- those instances report a non-zero
	-- TimeLength in this place, which IS the load-verification this file's
	-- header demands, rather than an id picked off the website and hoped for.
	--
	-- ONE SAMPLE PER HIT, not one sample pitched three ways. Pitching a single
	-- tap down twice is the same family-sameness failure the catch ladder above
	-- died of twice: a shell that is nearly open must not sound like the first
	-- tap played lower. So these climb through three different CLASSES of break --
	-- a dry snap, a deeper fracture, then splintering give-way -- each with a
	-- crumble tail under it that grows with the damage.
	eggCrack1     = "rbxassetid://1093102664",      -- bone-snap01, 0.34s -- first tap, dry and small
	eggCrack2     = "rbxassetid://4086172699",      -- bonebreak3, 1.02s -- deeper, something gave
	eggCrack3     = "rbxassetid://4988580015",      -- wood-break1, 1.63s -- splintering, about to open
	eggCrumble    = "rbxassetid://3848076724",      -- earthcrumble1, 0.60s -- grit tail
	eggCrumbleBig = "rbxassetid://4307210855",      -- earthloudcrumble2, 1.51s -- tail on the last hit
	eggStrain     = "rbxassetid://3929463305",      -- bonecrackle, 2.63s -- quiet bed while it waits to be tapped
	eggSplit      = "rbxassetid://4307207693",      -- brickburst2, 1.37s -- the shell coming apart
	panelOpen   = "rbxassetid://9117847793",        -- SFX2 new: popup/panel appears
	panelClose  = "rbxassetid://9126267413",        -- SFX2 new: panel close (X buttons)
	fusion      = "rbxassetid://4612374036",        -- SFX2 new: same id as `mutation` above, the generic sting
	-- Shop walk-in cues, one per stall, played when you press E. The two
	-- config-driven merchants name theirs on their MerchantConfig entry; Marco's
	-- sell stall is wired in ClientMain because he keeps his own sell menu.
	-- All three are first-party ProSoundEffects and all three were load-verified
	-- in-engine before landing here, per the note at the top of this file.
	shopBell    = "rbxassetid://9119643158",        -- rock shop: store entry bell, close-mic take, 3.80s
	shopCoins   = "rbxassetid://9113849100",        -- sell stall: coins in pocket, metal rattle + clinks, 1.22s
	shopPour    = "rbxassetid://9113555949",        -- upgrades: bottle pour into glass, glass clink, 4.44s
	-- Daily wheel. The wheel was still running on two of the stock rbxasset
	-- sounds this module exists to retire (switch.wav / electronicpingshort.wav),
	-- which is why a spin read as near-silent. All four ids below are from the
	-- sound library already in Workspace.SFX and were load-verified in-engine.
	wheelWind       = "rbxassetid://15675024286",    -- Roblox_UI_Whoosh_01, 0.85s
	-- MUST be shorter than TICK_GAP or the ratchet does not work. The first pass
	-- used a 0.19s click at a 0.055s gap: every click was cut off at ~29% and
	-- retriggered, so the spin read as a stuttering smear rather than as clicks.
	-- 0.097s against the current 0.085s gap leaves each tap essentially complete.
	wheelTick       = "rbxassetid://3623733749",     -- ui_tap-variant-01, 0.097s, dry and crisp
	wheelWin        = "rbxassetid://4612374495",     -- the old catch-ladder bling, kept for the wheel
	-- The 1% jackpot gets its OWN voice rather than a louder win -- same principle
	-- as the top mutations above. Choir swell, with the big bling under it for the
	-- initial hit so the moment lands before the swell arrives.
	wheelJackpot    = "rbxassetid://102859001475552",-- same id as `angel`, choir, 2.58s
	wheelJackpotHit = "rbxassetid://4612374036",     -- same id as `mutation`, bling BIG, 2.01s
}

-- One template per sound, parented to SoundService so the asset resolves once
-- for the session instead of on every play.
local templates = {}
local function template(name)
	local id = M.Ids[name]
	if not id then
		warn("[SoundKit] unknown sound: " .. tostring(name))
		return nil
	end
	local t = templates[name]
	if not t or not t.Parent then
		t = Instance.new("Sound")
		t.Name = "tpl_" .. name
		t.SoundId = id
		t.Volume = 0
		t.Parent = SoundService
		templates[name] = t
	end
	return t
end

-- Warm every template up front so the first catch of a session is not silent
-- while the asset streams in.
function M.preload()
	for name in pairs(M.Ids) do template(name) end
end

-- where: nil for a flat 2D sound (UI, or something that happened to YOU),
--        a BasePart or Vector3 to place it in the world so distance applies.
-- opts:  volume, speed, range
function M.play(name, where, opts)
	local t = template(name)
	if not t then return nil end
	opts = opts or {}

	local s = t:Clone()
	s.Name = name
	-- 0.5 was too hot across the board -- feedback was "loud rings". Call sites
	-- should still pass an explicit volume; this default is for quiet incidentals.
	-- UIKIT (Task 10): scaled by the Settings panel's Sound FX slider
	-- (vol.sfx, default 1 = no change) -- every M.play() call site in the
	-- game routes through here, so this one multiply covers all of them.
	s.Volume = (opts.volume or 0.25) * vol.sfx
	s.PlaybackSpeed = opts.speed or 1

	-- TimeLength is 0 until the asset loads, so the cleanup delay needs a floor
	-- or a clone can be destroyed before it has made a sound.
	local life = math.max(t.TimeLength, 3) + 0.5

	if typeof(where) == "Instance" and where:IsA("BasePart") then
		s.RollOffMaxDistance = opts.range or 90
		s.Parent = where
	elseif typeof(where) == "Vector3" then
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.CFrame = CFrame.new(where)
		anchor.Parent = workspace
		s.RollOffMaxDistance = opts.range or 90
		s.Parent = anchor
		Debris:AddItem(anchor, life)
	else
		s.Parent = SoundService
	end

	s:Play()
	Debris:AddItem(s, life)
	return s
end


-- LOOPS. M.play is fire-and-forget with a Debris lifetime, which is wrong for a
-- charge bed: it must survive an arbitrarily long hold and then stop on command.
-- Same template/clone/volume-scaling path as M.play, so the Settings SFX slider
-- still governs it -- this is a second play SHAPE, not a second audio layer.
--
-- Returns a handle: :setSpeed(n) to drive pitch, :stop(fade) to fade and destroy.
-- stop() is idempotent, so a caller may call it from several teardown paths.
function M.loop(name, opts)
	local t = template(name)
	if not t then return nil end
	opts = opts or {}

	local s = t:Clone()
	s.Name = name .. "_loop"
	s.Looped = true
	s.Volume = (opts.volume or 0.2) * vol.sfx
	s.PlaybackSpeed = opts.speed or 1
	s.Parent = SoundService     -- 2D: this is happening to YOU, not somewhere
	s:Play()

	local handle = { sound = s }
	local stopped = false
	function handle:setSpeed(n)
		if stopped or not s.Parent then return end
		if type(n) ~= "number" or n ~= n then return end
		s.PlaybackSpeed = n
	end
	function handle:stop(fade)
		if stopped then return end
		stopped = true
		if not s.Parent then return end
		fade = fade or 0
		if fade <= 0 then
			s:Destroy()
			return
		end
		TweenService:Create(s, TweenInfo.new(fade), { Volume = 0 }):Play()
		Debris:AddItem(s, fade + 0.05)   -- destroyed even if the tween is interrupted
	end
	return handle
end

return M
