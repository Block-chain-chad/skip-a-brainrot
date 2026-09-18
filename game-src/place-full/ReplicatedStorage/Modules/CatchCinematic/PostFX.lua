--!strict
-- CatchCinematic.PostFX -- the hype grade. Creates its OWN Lighting instances
-- (CinematicCC / CinematicBloom / CinematicBlur), tagged, and NEVER touches any
-- pre-existing Lighting effect (this place already has a ColorCorrection,
-- TundraGrade, SunRays, Atmosphere, GardensGrade -- all off-limits).
--
-- Every animated value here (ColorCorrectionEffect.Saturation/Contrast,
-- BloomEffect.Intensity, BlurEffect.Size) is a hand-lerp: render-throttle-safe
-- and proven correct, rather than depending on TweenService progress, which
-- read back as stalled during a backgrounded/render-throttled verification
-- session (not a place-wide TweenService defect). Each of hypeOn/easeBack/flash
-- runs its own task.spawn stepping loop with task.wait().
-- hypeOn/easeBack share a generation counter (_gen) so the later call always
-- wins and cleanly supersedes an in-flight one -- no property fight between two
-- competing loops. flash() uses a separate counter (_flashGen) because it drives
-- a different property (Brightness) and must not be cancelled by a hypeOn/
-- easeBack call landing mid-pulse.
--
-- Baselines for the hand-lerp are simply 0 (Saturation/Contrast/Bloom.Intensity/
-- Blur.Size all default to 0 on a freshly-created instance) -- no snapshot
-- needed, unlike AudioBus, because these are OUR OWN new instances with nothing
-- pre-existing to remember.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local CINEMATIC_TAG = "CatchCinematicPostFX"

export type PostFXCfg = {
	hypeSaturation: number?,
	hypeContrast: number?,
	hypeBloomIntensity: number?,
	blurSizeHigh: number?,
	blurSizeLow: number?,
	flashSeconds: number?,
	easeBackSeconds: number?,
}

local PostFX = {}
PostFX.__index = PostFX

export type Fx = typeof(setmetatable(
	{} :: {
		_cfg: PostFXCfg,
		_quality: string,
		_reducedMotion: boolean,
		_cc: ColorCorrectionEffect,
		_bloom: BloomEffect,
		_blur: BlurEffect,
		_gen: number,
		_flashGen: number,
		_destroyed: boolean,
	},
	PostFX
))

function PostFX.new(cfg: PostFXCfg, quality: string, reducedMotion: boolean): Fx
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "CinematicCC"
	cc.Saturation = 0
	cc.Contrast = 0
	cc.Brightness = 0
	cc.Parent = Lighting
	CollectionService:AddTag(cc, CINEMATIC_TAG)

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "CinematicBloom"
	bloom.Intensity = 0
	bloom.Size = 24
	bloom.Threshold = 2
	bloom.Parent = Lighting
	CollectionService:AddTag(bloom, CINEMATIC_TAG)

	local blur = Instance.new("BlurEffect")
	blur.Name = "CinematicBlur"
	blur.Size = 0
	blur.Parent = Lighting
	CollectionService:AddTag(blur, CINEMATIC_TAG)

	local self = setmetatable({
		_cfg = cfg,
		_quality = quality,
		_reducedMotion = reducedMotion,
		_cc = cc,
		_bloom = bloom,
		_blur = blur,
		_gen = 0,
		_flashGen = 0,
		_destroyed = false,
	}, PostFX)
	return (self :: any) :: Fx
end

-- Quick white-pulse via ColorCorrectionEffect.Brightness, up then back down.
-- Skipped entirely when reducedMotion is true, per the brief.
function PostFX:flash()
	if self._destroyed or self._reducedMotion then
		return
	end
	self._flashGen += 1
	local myGen = self._flashGen
	local seconds = math.max(self._cfg.flashSeconds or 0.08, 0.02)
	local cc = self._cc
	local upT = seconds * 0.35
	local downT = math.max(seconds - upT, 0.01)

	task.spawn(function()
		local t0 = os.clock()
		while self._flashGen == myGen and not self._destroyed do
			local a = math.clamp((os.clock() - t0) / upT, 0, 1)
			cc.Brightness = a
			if a >= 1 then
				break
			end
			task.wait()
		end
		if self._destroyed or self._flashGen ~= myGen then
			return
		end
		local t1 = os.clock()
		while self._flashGen == myGen and not self._destroyed do
			local a = math.clamp((os.clock() - t1) / downT, 0, 1)
			cc.Brightness = 1 - a
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Hand-lerped Saturation/Contrast/Bloom up + blur per quality (blur target is 0
-- on "low" -- dropped entirely, per Config.POSTFX's own comment).
function PostFX:hypeOn(seconds: number)
	if self._destroyed then
		return
	end
	seconds = math.max(seconds, 0.05)
	self._gen += 1
	local myGen = self._gen
	local cfg = self._cfg
	local cc, bloom, blur = self._cc, self._bloom, self._blur

	local blurTarget = (self._quality == "low") and (cfg.blurSizeLow or 0) or (cfg.blurSizeHigh or 8)
	local startSat, startCon = cc.Saturation, cc.Contrast
	local startBloom, startBlur = bloom.Intensity, blur.Size
	local targetSat = cfg.hypeSaturation or 0.35
	local targetCon = cfg.hypeContrast or 0.12
	local targetBloom = cfg.hypeBloomIntensity or 0.9

	task.spawn(function()
		local t0 = os.clock()
		while self._gen == myGen and not self._destroyed do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			local e = a * a * (3 - 2 * a) -- smoothstep
			cc.Saturation = startSat + (targetSat - startSat) * e
			cc.Contrast = startCon + (targetCon - startCon) * e
			bloom.Intensity = startBloom + (targetBloom - startBloom) * e
			blur.Size = startBlur + (blurTarget - startBlur) * e
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Hand-lerped back toward baseline (0 on every axis). Supersedes any in-flight
-- hypeOn via the shared generation counter.
function PostFX:easeBack(seconds: number)
	if self._destroyed then
		return
	end
	seconds = math.max(seconds, 0.05)
	self._gen += 1
	local myGen = self._gen
	local cc, bloom, blur = self._cc, self._bloom, self._blur
	local startSat, startCon = cc.Saturation, cc.Contrast
	local startBloom, startBlur = bloom.Intensity, blur.Size

	task.spawn(function()
		local t0 = os.clock()
		while self._gen == myGen and not self._destroyed do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			local e = 1 - (1 - a) ^ 3
			cc.Saturation = startSat * (1 - e)
			cc.Contrast = startCon * (1 - e)
			bloom.Intensity = startBloom * (1 - e)
			blur.Size = startBlur * (1 - e)
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Destroys all three instances, always -- idempotent, safe even if hypeOn was
-- never called.
function PostFX:cleanup()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._gen += 1
	self._flashGen += 1
	pcall(function()
		self._cc:Destroy()
	end)
	pcall(function()
		self._bloom:Destroy()
	end)
	pcall(function()
		self._blur:Destroy()
	end)
end

return PostFX
