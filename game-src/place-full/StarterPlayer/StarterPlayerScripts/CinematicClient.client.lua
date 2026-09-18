--!strict
-- CinematicClient -- the client end of ThrowHandler's MassiveCinematic broadcast.
--
-- The server fires this to EVERYONE at flight start, with the arc's timing attached
-- (TotalTime/NContacts/SegTime) exactly as StoneThrown already does. Clients tick
-- their own clock from receipt, so the send latency cancels and everybody's bonk
-- lands on the same real-world instant as the server's final skip contact.
--
-- Three outcomes per broadcast, and EXACTLY one of them always happens:
--   1. thrower, size wants a cinematic   -> Bridge.arm + Takeover.play (full takeover)
--   2. bystander within SPECTATOR_RADIUS -> Takeover.play(spectator) (world FX only)
--   3. anyone else, or a declined/errored play -> stockLanding() below
--
-- (3) IS NOT OPTIONAL. The server suppresses the final splash and destroys its own
-- stone for EVERY client on a cinematic throw (ThrowHandler: "clients stage it
-- themselves"), so a client that runs no cinematic and stages no landing sees a
-- Massive throw as a rock silently ceasing to exist over open water. This file is
-- the only thing standing between that and the player.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local modules = ReplicatedStorage:WaitForChild("Modules")
local cinFolder = modules:WaitForChild("CatchCinematic")
local Config = require(cinFolder:WaitForChild("Config"))

-- Fail-soft, because of the header: this file is the ONLY thing that stages a
-- landing for a Massive throw. A broken or missing cinematic module at the top of
-- the file would kill the whole script, and every Massive rock in the game would
-- silently cease to exist over open water. So the two cinematic-stack requires
-- degrade to nil and the file falls back to stockLanding for everything.
-- The wait is BOUNDED on purpose: an unbounded WaitForChild for a module that will
-- never arrive hangs this script forever, which is the exact outcome being guarded
-- against. Typed `any` so --!strict stays happy with the optional shape.
local function softRequire(name: string): any
	local inst = cinFolder:WaitForChild(name, 5)
	if not inst then
		warn("[CinematicClient] " .. name .. " missing -- Massive throws take the stock landing")
		return nil
	end
	local ok, mod = pcall(require, inst)
	if not ok then
		warn("[CinematicClient] " .. name .. " failed to load (" .. tostring(mod) .. ") -- Massive throws take the stock landing")
		return nil
	end
	return mod
end

local Takeover = softRequire("Takeover")
-- Cuts.Registry, fail-soft like the two above: nil means no cut can be looked up,
-- so every broadcast collapses to the stock landing. (A Folder cannot go through
-- softRequire, which require()s its argument.)
local Registry = nil
do
	local cuts = cinFolder:WaitForChild("Cuts", 5)
	local inst = cuts and cuts:WaitForChild("Registry", 5)
	if inst then
		local ok, mod = pcall(require, inst)
		if ok then
			Registry = mod
		else
			warn("[CinematicClient] Cuts.Registry failed to load (" .. tostring(mod) .. ") -- stock landings only")
		end
	else
		warn("[CinematicClient] Cuts.Registry missing -- stock landings only")
	end
end
local Bridge = softRequire("Bridge")
local SoundKit = require(modules:WaitForChild("SoundKit"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local cinematicRemote = remotes:WaitForChild("CatchCinematic")

-- ============================ stock landing ============================

-- ThrowHandler's own big-landing numbers, matched on purpose: this has to be
-- indistinguishable from the splash the server would have played if the throw had
-- not been a cinematic one. Ring recipe is ThrowHandler.ripple()'s verbatim (thin
-- Neon cylinder rotated flat, Quad-EaseOut on Size + Transparency); sound is
-- playSplashSound()'s `big` branch (splashBig at 0.68, pitched to 0.95).
local RING_COLOR = Color3.fromRGB(226, 244, 255)

local function stockLanding(endPos: Vector3, surfaceY: number)
	local surf = Vector3.new(endPos.X, surfaceY, endPos.Z)

	local ok = pcall(function()
		local ring = Instance.new("Part")
		ring.Name = "CinematicFallbackRipple"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.12, 1.6, 1.6)
		ring.Material = Enum.Material.Neon
		ring.Color = RING_COLOR
		ring.Transparency = 0.35
		ring.CFrame = CFrame.new(surf.X, surf.Y + 0.04, surf.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Locked = true
		ring.Parent = Workspace

		TweenService:Create(
			ring,
			TweenInfo.new(1.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.12, 40, 40), Transparency = 1 }
		):Play()
		Debris:AddItem(ring, 1.6)
	end)
	if not ok then
		warn("[CinematicClient] stock landing ring failed")
	end

	pcall(SoundKit.play, "splashBig", surf, { volume = 0.68, speed = 0.95 })
end

-- ============================== preload ==============================

-- Fire-and-forget on its own thread: PreloadAsync YIELDS (potentially for seconds
-- on a cold client) and the bonk is on a hard clock. Worst case a texture pops in
-- late; the timeline never waits.
local SOUND_SLOTS = {
	"finalSkip", "massiveRumble", "bassDrop", "waterExplosion",
	"massiveRoar", "bannerHit", "cardWhoosh", "mythicBass", "secretHum", "secretLaunch",
	"godRumble", "beamRise", "godChoir", "goldShockwave",
}

local function preload(brainrotName: string)
	local list: { Instance } = {}
	local temps: { Instance } = {}

	local models = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local template = models and models:FindFirstChild(brainrotName)
	if template then
		table.insert(list, template)
	end

	local seen: { [string]: boolean } = {}
	for _, slot in ipairs(SOUND_SLOTS) do
		local ref = (Config.ASSETS :: any)[slot]
		local id: any = nil
		if type(ref) == "string" then
			if string.sub(ref, 1, 4) == "kit:" then
				id = (SoundKit :: any).Ids[string.sub(ref, 5)]
			else
				id = ref
			end
		end
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			-- Parentless throwaways purely as PreloadAsync handles; AudioBus makes
			-- the real Sound instances through SoundKit when the beat asks for them.
			local s = Instance.new("Sound")
			s.SoundId = id
			table.insert(list, s)
			table.insert(temps, s)
		end
	end

	if #list > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end
	for _, s in ipairs(temps) do
		s:Destroy()
	end
end

-- ============================== handler ==============================

local function onCinematic(payload: { [string]: any })
	if type(payload) ~= "table" then
		return
	end
	if typeof(payload.EndPos) ~= "Vector3" then
		return
	end
	local receipt = os.clock()
	local endPos = payload.EndPos :: Vector3
	local surfaceY = tonumber(payload.SurfaceY) or endPos.Y
	local totalTime = math.max(tonumber(payload.TotalTime) or 0, 0)

	-- ============================ Studio debug seam ============================
	-- __cutOverride is NEVER sent by the real server -- ThrowHandler only ever builds
	-- {UserId,BrainrotName,Rarity,RarityColor,Mutation,Size,Cut,RockId,RockColor,Seed}
	-- plus the arc fields. Only ServerScriptService.CinematicCommand's /cinematic debug
	-- command sets it, gated identically server-side. Gated AGAIN here (field presence
	-- + IsStudio()) as defence in depth: the payload arrives over a real RemoteEvent,
	-- so a non-Studio client must never honour it even if an upstream gate were ever
	-- weakened.
	--
	-- The server names the cut (payload.Cut). The client re-derives it from the same
	-- Config.CUT_FOR as a guard against a mid-session Config edit or an older server:
	-- when the two disagree, NO cut is safer than the wrong cut.
	local cutName: string? = Config.CUT_FOR(payload.Rarity, payload.Size)
	if type(payload.Cut) == "string" and payload.Cut ~= cutName then
		cutName = nil
	end
	if RunService:IsStudio() and type(payload.__cutOverride) == "string" then
		cutName = payload.__cutOverride
	end
	local cut = (cutName and Registry) and Registry.get(cutName) or nil
	-- Takeover == nil is the fail-soft above: no cut is possible, so every branch
	-- below collapses to the stock landing rather than touching a nil module.
	local wants = cut ~= nil and Takeover ~= nil

	local isThrower = payload.UserId == player.UserId
	local spectator = not isThrower

	if wants and spectator then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			wants = false
		elseif ((hrp :: BasePart).Position - endPos).Magnitude > Config.SPECTATOR_RADIUS then
			wants = false
		end
	end

	if wants and Takeover.isActive() then
		-- Never stack rigs. The Takeover would refuse anyway; checking here means
		-- the fallback is scheduled from the start instead of discovered late.
		wants = false
	end

	local bridgeGen: number? = nil
	-- Debug fabricated payloads have no ThrowResult behind them (CinematicCommand
	-- grants nothing, touches no data), so arming the Bridge would just wait out
	-- Config.CANCEL_TIMEOUT and cancel the run a few seconds in -- exactly the
	-- outcome a demo command must not have. Studio-only, same gate as above.
	local skipBridge = RunService:IsStudio() and payload.__debugNoBridge == true
	if wants and isThrower and not skipBridge and Bridge == nil then
		-- Bridge failed the fail-soft require: the reveal could be neither adopted nor
		-- suppressed, so a thrower cut would run over the top of an ordinary catch
		-- popup. Stock landing instead. Spectator runs never arm it, so they are fine.
		wants = false
	end
	if wants and isThrower and not skipBridge then
		-- Armed NOW, not at the bonk: ThrowResult can (just) beat our scheduled play()
		-- to the client, and CatchRevealClient has to be able to adopt it. The expiry
		-- covers the flight plus the cancel window; the Takeover's markRunning extends
		-- it to cover the cutscene itself once the run commits.
		bridgeGen = Bridge.arm(payload, totalTime + Config.CANCEL_TIMEOUT + 3)
		if bridgeGen == nil then
			-- An EARLIER catch's cinematic still owns the bridge, and the Bridge refuses
			-- to be clobbered (its rule R2). Flights really do overlap: the 1.05s throw
			-- cooldown is shorter than a 1.15-4.2s flight and far shorter than a 10.7s
			-- cutscene. So this throw takes the stock landing and its ordinary reveal --
			-- vastly better than stranding the running catch's reveal.
			wants = false
		end
	end
	if wants then
		task.spawn(preload, payload.BrainrotName)
	end

	-- ============== handing the camera over cleanly at the bonk ==============
	-- ClientMain's stone-tracking camera (any throw past TRACK_MIN_DISTANCE, which a
	-- Massive always is) holds CameraType = Scriptable for flightTime + 1.4s -- i.e.
	-- straight THROUGH the bonk. CameraRig:takeover() snapshots whatever CameraType
	-- and CFrame it finds so it can hand them back at the end, so without this flag it
	-- snapshots the tracking camera's Scriptable pose out at the landing point and
	-- "restores" the player into it -- camera frozen 900 studs away, permanently, on
	-- every real Massive catch. This tells ClientMain to release the camera a beat
	-- before the final contact so the snapshot is the player's real camera.
	-- Only a THROWER run takes the camera; spectator runs are world FX only.
	local takesCamera = wants and isThrower
	if takesCamera then
		player:SetAttribute("CinematicCameraInbound", true)
	end

	local wait = math.max(totalTime - (os.clock() - receipt), 0)
	task.delay(wait, function()
		-- Served its purpose: ClientMain released the camera CINEMATIC_CAM_LEAD seconds
		-- ago and takeover() is about to run (or not) on this very line.
		if takesCamera then
			player:SetAttribute("CinematicCameraInbound", nil)
		end
		if not wants then
			stockLanding(endPos, surfaceY)
			return
		end

		-- Takeover.play BLOCKS for the whole cinematic, but the accept/decline answer
		-- is needed NOW so the fallback lands ON the bonk rather than ten seconds after
		-- it. opts.onCommit fires synchronously the instant play commits, and task.spawn
		-- runs the thread up to its first yield -- which play only reaches after
		-- committing. So by the line below the answer already exists, with no reliance
		-- on a "play must not yield before returning" comment invariant and no
		-- isActive() guess (which can be true for somebody else's spectator run).
		local committed = false
		task.spawn(function()
			local ok, err = pcall(Takeover.play, cut, payload, {
				spectator = spectator,
				bridgeGen = bridgeGen,
				onCommit = function()
					committed = true
				end,
			})
			if not ok then
				warn("[CinematicClient] Takeover.play errored: " .. tostring(err))
			end
		end)

		if not committed then
			-- Declined (debounced / bad payload / no model) or errored before it ever
			-- took over. Generation-scoped release: a debounced play must never tear
			-- down the LIVE arm of the earlier throw whose cinematic is the very thing
			-- debouncing it -- that bug eats a catch.
			if bridgeGen ~= nil then
				Bridge.markFailedFor(bridgeGen)
			end
			stockLanding(endPos, surfaceY)
		end
	end)
end

cinematicRemote.OnClientEvent:Connect(function(payload)
	local ok, err = pcall(onCinematic, payload)
	if not ok then
		warn("[CinematicClient] handler errored: " .. tostring(err))
	end
end)

-- ============================== test seam ==============================

-- Studio only. The OnClientEvent path above can only be driven from a server, so the
-- harness needs a door into these functions with fabricated payloads and no real
-- throw (a real throw would GRANT, and Studio play sessions write the live
-- datastore). Never created in a published server.
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(action: string, arg: any): any
		if action == "cinematic" then
			onCinematic(arg)
			return true
		elseif action == "stock" then
			stockLanding(arg.EndPos, arg.SurfaceY or arg.EndPos.Y)
			return true
		elseif action == "preload" then
			preload(arg)
			return true
		end
		return false
	end
	hook.Parent = script
end
