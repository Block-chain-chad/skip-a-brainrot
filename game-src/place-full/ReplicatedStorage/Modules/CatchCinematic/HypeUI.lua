--!strict
-- CatchCinematic.HypeUI -- screen-space overlay for the MAX BRAINROT hype beat:
-- banner slam, wobbling rainbow name, the
-- HOLD TO SKIP prompt, and the bag-streak target used by BrainrotRig's
-- compressAndStreak. Own ScreenGui "CatchCinematicUI", DisplayOrder 55 (above
-- PullCeremony's 50), IgnoreGuiInset true, ResetOnSpawn false, parented under
-- PlayerGui. Font FredokaOne throughout via the label() helper below -- copied
-- from PullCeremony's own recipe (TextLabel + UIStroke), which is what keeps
-- FredokaOne surviving the game-wide UIPolish font override.
--
-- ALL MOTION IS HAND-LERPED FROM A CLOCK -- task.spawn + os.clock() stepping
-- loops, exactly like PostFX/AudioBus in this folder. NEVER TweenService on
-- UIScale (silently no-ops in this place -- see Config.lua's header) and NEVER
-- UIGradient.Rotation for the rainbow name (the gradient-rotation gotcha):
-- the wobble writes TextColor3 per character, per frame, instead.
--
-- Per-character name labels are positioned BY HAND (TextService:GetTextSize
-- per character), deliberately NOT via UIListLayout, even though a list
-- layout is the obvious way to flow characters. Recon-verified in this
-- codebase: "UIListLayout eats Position" -- a layout-managed child's Position
-- gets silently overwritten on the layout's next pass, which would fight the
-- per-frame sine Y-offset every single frame. See nameText() below.
--
-- Every random draw
-- comes from the injected `rng: Random`, drawn ONCE when the effect triggers
-- -- never per-frame, never math.random -- so a given seed replays identically
-- (RockRig's convention in this folder, copied here).
--
-- cfg is a COMBINED table -- { HYPE = Config.HYPE, SKIP = Config.SKIP,
-- PARTICLES = Config.PARTICLES } -- built by the caller (Sequencer/harness).
-- This module never requires Config itself.
--
-- Test-only internal seam: bagTarget()'s public signature takes no arguments
-- (contractual), so `self._bagSearchRootOverride` is the seam a harness pokes
-- directly to force the fallback branch without touching the real, live
-- GameHUD (renaming NavRail for a test would be far too invasive on a Team
-- Create place). Production code should never set this field.
--
-- IgnoreGuiInset SHIFTS ABSOLUTEPOSITION MATH (recon-verified gotcha,
-- confirmed live in this place: GuiInset reads (0, 58) here -- an
-- IgnoreGuiInset=true ScreenGui's own AbsolutePosition comes back (0, -58),
-- NOT (0, 0), even though its AbsoluteSize is still the full true viewport.
-- Every fixed-pixel Y position placed inside this gui -- and every TRUE
-- absolute screen Y read from another gui (e.g. bagTarget()'s NavRail hit)
-- and then used to place something INSIDE this gui -- has to be run through
-- topOffset()/bottomOffset() below or it lands `GuiInset.Y` pixels off from
-- where it visually should be. GuiInset.X is untouched (topbars are
-- horizontal), so X never needs this.
--
-- `timescale` (HypeUI.new's 5th arg, optional, default 1): every wall-clock
-- task.spawn loop's elapsed-time computation divides by it, so
-- Config.DEBUG_TIMESCALE-style tuning slows/speeds this module's bursts in
-- lockstep with the rest of the Sequencer's beats. `memeFlyIns(t)` is exempt
-- on purpose -- it stays a pure function of the caller's own `t`, and the
-- Sequencer's `t` is presumed already timescaled at the source.
--
-- `interrupt()` contract: the Sequencer calls this the instant a skip
-- resolves. It hard-cuts every in-flight hype effect (banner, name letters,
-- confetti, speed lines, meme slots, card pops) in the SAME synchronous
-- call -- generation counters bumped and the transient instances destroyed
-- outright, not merely faded. It deliberately does NOT touch the ScreenGui
-- itself or anything owned by showSkipPrompt/setSkipProgress/hideSkipPrompt
-- -- the skip prompt's own lifecycle is the Sequencer's call, made
-- separately (typically hideSkipPrompt() alongside interrupt()).

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local GuiService = game:GetService("GuiService")

local FONT = Enum.Font.FredokaOne
local STROKE_COLOR = Color3.fromRGB(20, 16, 8)

local function guiInsetY(): number
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(inset) == "Vector2" then
		return inset.Y
	end
	return 0
end

-- Converts a TRUE absolute screen Y (or a "pixels below the true top" value
-- for a Scale-0, AnchorPoint.Y=0 element) into the Position.Offset this
-- IgnoreGuiInset gui needs to land there.
local function topOffset(trueY: number): number
	return trueY + guiInsetY()
end

-- For AnchorPoint.Y=1, Position Y-Scale=1 elements: desiredPx = pixels above
-- the TRUE bottom of the screen.
local function bottomOffset(desiredPx: number): number
	return guiInsetY() - desiredPx
end

-- Reference pixel offsets from the top of the screen for the three stacked
-- hype elements, tuned at a ~1380x791 viewport (generous enough that even
-- the banner's peak bounce scale, up to Config.HYPE.bannerScalePop e.g.
-- 1.35x, never reaches down into the name band, and the name band, even
-- unshrunk, never reaches into the meme band). These are NOT used directly
-- for placement -- HypeUI.new() converts each to a FRACTION of the gui's
-- AbsoluteSize.Y at construction time (self._bannerYFrac etc.), and every
-- placement multiplies that fraction by the CURRENT AbsoluteSize.Y. This
-- keeps the three bands proportionally spaced (same relative gaps) across
-- different viewport heights instead of a fixed pixel gap that would eat a
-- shrinking screen alive.
local BANNER_Y_REF = 32
local NAME_Y_REF = 280

export type HypeCfg = {
	bannerScalePop: number?,
}
export type SkipCfg = {
	delay: number?,
	holdSeconds: number?,
	exitFadeSeconds: number?,
}
export type QualityCfg = { mult: number?, budget: number? }
export type ParticlesCfg = { high: QualityCfg?, low: QualityCfg? }

export type HypeUICfg = {
	HYPE: HypeCfg?,
	SKIP: SkipCfg?,
	PARTICLES: ParticlesCfg?,
}

-- Copied verbatim (shape) from PullCeremony's label() -- the house recipe:
-- AutomaticSize XY TextLabel + a UIStroke sized off TextSize. AutomaticSize
-- guarantees TextFits is trivially true for every label this module creates.
local function label(parent: Instance, text: string, size: number, color: Color3, strokeT: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = color
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Size = UDim2.fromOffset(0, 0)
	l.Parent = parent
	local s = Instance.new("UIStroke")
	s.Thickness = strokeT or math.max(3, size / 14)
	s.Color = STROKE_COLOR
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	return l
end

local HypeUI = {}
HypeUI.__index = HypeUI

export type Ui = typeof(setmetatable(
	{} :: {
		_hype: HypeCfg,
		_skip: SkipCfg,
		_particles: ParticlesCfg,
		_quality: string,
		_reducedMotion: boolean,
		_rng: Random,
		_timescale: number,
		_gui: ScreenGui,
		_destroyed: boolean,

		-- F3: fractions of AbsoluteSize.Y, computed once at construction from
		-- BANNER_Y_REF/NAME_Y_REF at the CURRENT viewport height.
		_bannerYFrac: number,
		_nameYFrac: number,
		
		_bannerLabel: TextLabel?,
		_bannerScale: UIScale?,
		_bannerGen: number,
		_lastBannerPeak: number?,

		_nameFrame: Frame?,
		_nameChars: { TextLabel },
		_nameGen: number,
		_lastNameAmp: number?,

		_skipHost: Frame?,
		_skipLabel: TextLabel?,
		_skipFillBar: Frame?,
		_skipGen: number,

		_bagSearchRootOverride: Instance?,
	},
	HypeUI
))

function HypeUI.new(cfg: HypeUICfg, quality: string, reducedMotion: boolean, rng: Random, timescale: number?): Ui
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	assert(playerGui ~= nil, "[HypeUI] no PlayerGui found -- must run client-side")

	local gui = Instance.new("ScreenGui")
	gui.Name = "CatchCinematicUI"
	gui.DisplayOrder = 55
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local ts = tonumber(timescale)
	local resolvedTimescale = (ts and ts > 0) and ts or 1

	-- F3: capture the CURRENT viewport height as the reference and express
	-- every band as a fraction of it -- see the BANNER_Y_REF header comment.
	local refH = gui.AbsoluteSize.Y
	if refH <= 0 then
		refH = 720
	end

	local self = setmetatable({
		_hype = cfg.HYPE or {},
		_skip = cfg.SKIP or {},
		_particles = cfg.PARTICLES or {},
		_quality = quality or "high",
		_reducedMotion = reducedMotion == true,
		_rng = rng,
		_timescale = resolvedTimescale,
		_gui = gui,
		_destroyed = false,

		_bannerYFrac = BANNER_Y_REF / refH,
		_nameYFrac = NAME_Y_REF / refH,

		_bannerLabel = nil,
		_bannerScale = nil,
		_bannerGen = 0,
		_lastBannerPeak = nil,

		_nameFrame = nil,
		_nameChars = {},
		_nameGen = 0,
		_lastNameAmp = nil,

		_skipHost = nil,
		_skipLabel = nil,
		_skipFillBar = nil,
		_skipGen = 0,

		_bagSearchRootOverride = nil,
	}, HypeUI)

	return (self :: any) :: Ui
end

function HypeUI:_particleMult(): number
	local q = self._particles[self._quality] or self._particles.high
	if q and type(q.mult) == "number" then
		return q.mult :: number
	end
	return 1
end

function HypeUI:_screenSize(): Vector2
	local size = self._gui.AbsoluteSize
	if size.X > 0 and size.Y > 0 then
		return size
	end
	return Vector2.new(1280, 720)
end

-- ===================== banner =====================
-- "MASSIVE" slam with an impact scale-bounce: UIScale.Scale is set PER FRAME
-- by a hand-lerp loop (0 -> bannerScalePop overshoot -> settle at 1), never
-- TweenService (which silently no-ops on UIScale in this place).
function HypeUI:banner(text: string, color: Color3)
	if self._destroyed then
		return
	end

	if not self._bannerLabel or not self._bannerLabel.Parent then
		local l = label(self._gui, "", 88, color, 8)
		l.Name = "Banner"
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0, topOffset(self._bannerYFrac * self:_screenSize().Y))
		l.ZIndex = 5
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = l
		self._bannerLabel = l
		self._bannerScale = scale
	end

	local l = self._bannerLabel :: TextLabel
	local scale = self._bannerScale :: UIScale

	-- shrink-to-fit: measure at a base size, scale down only if it would
	-- overflow 90% of the viewport width.
	local maxWidth = self:_screenSize().X * 0.9
	local baseSize = 88
	local bounds = TextService:GetTextSize(text, baseSize, FONT, Vector2.new(10000, 500))
	local sizeToUse = baseSize
	if bounds.X > maxWidth then
		sizeToUse = math.max(28, math.floor(baseSize * (maxWidth / bounds.X)))
	end
	l.TextSize = sizeToUse
	l.Text = text
	l.TextColor3 = color
	local strokeInst = l:FindFirstChildOfClass("UIStroke")
	if strokeInst then
		strokeInst.Thickness = math.max(3, sizeToUse / 14)
	end

	self._bannerGen += 1
	local myGen = self._bannerGen
	local peak = self._reducedMotion and 1.08 or (self._hype.bannerScalePop or 1.35)
	self._lastBannerPeak = peak

	task.spawn(function()
		local t0 = os.clock()
		local riseDur = 0.22
		local settleDur = 0.28
		local total = riseDur + settleDur
		while self._bannerGen == myGen and not self._destroyed and l.Parent do
			local elapsed = (os.clock() - t0) / self._timescale
			local s: number
			if elapsed < riseDur then
				local u = elapsed / riseDur
				s = peak * (1 - (1 - u) ^ 3)
			elseif elapsed < total then
				local u = (elapsed - riseDur) / settleDur
				local e = 1 - (1 - u) ^ 3
				s = peak + (1 - peak) * e
			else
				s = 1
			end
			scale.Scale = s
			if elapsed >= total then
				break
			end
			task.wait()
		end
		if self._bannerGen == myGen and not self._destroyed and scale.Parent then
			scale.Scale = 1
		end
	end)
end

-- ===================== name text =====================
-- Sizes.Label(...) output, wobbling rainbow: per-character TextLabels, hand
-- positioned (see module header re: UIListLayout), per-frame sine Y-offset +
-- hue rotation via TextColor3 -- never UIGradient.Rotation.
function HypeUI:nameText(text: string)
	if self._destroyed then
		return
	end

	if self._nameFrame and self._nameFrame.Parent then
		self._nameFrame:Destroy()
	end
	self._nameGen += 1
	local myGen = self._nameGen
	self._nameChars = {}

	local host = Instance.new("Frame")
	host.Name = "NameHost"
	host.AnchorPoint = Vector2.new(0.5, 0)
	host.Position = UDim2.new(0.5, 0, 0, topOffset(self._nameYFrac * self:_screenSize().Y))
	host.BackgroundTransparency = 1
	host.Size = UDim2.fromOffset(0, 0)
	host.ZIndex = 5
	host.Parent = self._gui
	self._nameFrame = host

	if #text == 0 then
		return
	end

	-- shrink-to-fit: measure the WHOLE string at a base size, scale down if
	-- it would overflow -- this is what guarantees the long-name case
	-- ("Golden Massive Kraken Congelato") always fits on screen.
	local maxWidth = self:_screenSize().X * 0.88
	local baseSize = 54
	local wholeBounds = TextService:GetTextSize(text, baseSize, FONT, Vector2.new(10000, 500))
	local finalSize = baseSize
	if wholeBounds.X > maxWidth then
		finalSize = math.max(16, math.floor(baseSize * (maxWidth / wholeBounds.X)))
	end

	local amp = self._reducedMotion and 3 or 8
	self._lastNameAmp = amp

	-- Per-character labels are sized EXPLICITLY from a direct TextService
	-- measurement, AutomaticSize = None -- NOT via the shared label() helper's
	-- AutomaticSize=XY. Verified live (failing harness run) that AutomaticSize
	-- on a label created and then immediately fought over every frame by this
	-- same function's own wobble loop (Position + TextColor3 writes starting
	-- the instant this loop finishes, before nameText() even returns -- see
	-- task.spawn below) can occasionally settle on an AbsoluteSize a hair
	-- tighter than TextFits itself requires, for a SPECIFIC character, in a
	-- way that would not reproduce in isolation. A deterministic, generously
	-- padded explicit Size sidesteps that race outright rather than chasing
	-- its exact trigger.
	local chars: { TextLabel } = {}
	local baseXs: { number } = {}
	local cursorX = 0
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		local measured = TextService:GetTextSize(ch, finalSize, FONT, Vector2.new(1000, 500))
		local charLabel = Instance.new("TextLabel")
		charLabel.Name = "Char" .. i
		charLabel.BackgroundTransparency = 1
		charLabel.Text = ch
		charLabel.Font = FONT
		charLabel.TextSize = finalSize
		charLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		charLabel.AutomaticSize = Enum.AutomaticSize.None
		charLabel.Size = UDim2.fromOffset(measured.X + 6, measured.Y + 16)
		charLabel.AnchorPoint = Vector2.new(0, 0)
		charLabel.Position = UDim2.fromOffset(cursorX, amp)
		charLabel.ZIndex = 5
		charLabel.Parent = host
		local charStroke = Instance.new("UIStroke")
		charStroke.Thickness = 3
		charStroke.Color = STROKE_COLOR
		charStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		charStroke.LineJoinMode = Enum.LineJoinMode.Round
		charStroke.Parent = charLabel
		table.insert(chars, charLabel)
		table.insert(baseXs, cursorX)
		cursorX += measured.X
	end
	host.Size = UDim2.fromOffset(cursorX, finalSize * 1.3 + amp * 2)
	self._nameChars = chars

	local hueSpacing = 0.045
	local hueSpeed = self._reducedMotion and 0.15 or 0.4
	local waveSpacing = 0.35
	local waveSpeed = self._reducedMotion and 3.5 or 6.0

	task.spawn(function()
		local t0 = os.clock()
		while self._nameGen == myGen and not self._destroyed and host.Parent do
			local t = (os.clock() - t0) / self._timescale
			for i, ch in ipairs(chars) do
				local phase = (i - 1) * waveSpacing
				local y = amp + math.sin(t * waveSpeed + phase) * amp
				ch.Position = UDim2.fromOffset(baseXs[i], y)
				local hue = (t * hueSpeed + (i - 1) * hueSpacing) % 1
				ch.TextColor3 = Color3.fromHSV(hue, 0.85, 1)
			end
			task.wait()
		end
	end)
end

-- ===================== bag target =====================
function HypeUI:bagTarget(): Vector2
	if self._destroyed then
		return Vector2.new(0, 0)
	end
	local screen = self:_screenSize()
	local fallback = Vector2.new(screen.X / 2, screen.Y - 40)

	local ok, found = pcall(function(): Vector2?
		local root: Instance? = self._bagSearchRootOverride
		if not root then
			local player = Players.LocalPlayer
			root = player and player:FindFirstChildOfClass("PlayerGui")
		end
		if not root then
			return nil
		end
		local gameHud = root:FindFirstChild("GameHUD")
		local chrome = gameHud and gameHud:FindFirstChild("Chrome")
		local navRail = chrome and chrome:FindFirstChild("NavRail")
		if not navRail then
			return nil
		end
		for _, child in ipairs(navRail:GetChildren()) do
			local nm = string.lower(child.Name)
			if string.find(nm, "bag", 1, true) or string.find(nm, "backpack", 1, true) then
				local hit = child:FindFirstChild("Hit", true)
				local target: GuiObject? = nil
				if hit and hit:IsA("GuiObject") then
					target = hit
				elseif child:IsA("GuiObject") then
					target = child
				end
				if target then
					local pos = target.AbsolutePosition
					local size = target.AbsoluteSize
					return pos + size / 2
				end
			end
		end
		return nil
	end)

	if ok and found then
		return found :: Vector2
	end
	return fallback
end

-- ===================== card arrive =====================
function HypeUI:cardArrive(color: Color3)
	if self._destroyed then
		return
	end

	-- bagTarget() returns a TRUE absolute screen point; topOffset() converts
	-- it into this (IgnoreGuiInset) gui's own local offset (see module header).
	local pos = self:bagTarget()
	local card = Instance.new("Frame")
	card.Name = "CardArrive"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromOffset(pos.X, topOffset(pos.Y))
	card.Size = UDim2.fromOffset(34, 44)
	card.BackgroundColor3 = color
	card.BorderSizePixel = 0
	card.ZIndex = 9
	card.Parent = self._gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = STROKE_COLOR
	stroke.Parent = card
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = card

	task.spawn(function()
		local t0 = os.clock()
		local popDur = 0.16
		local holdDur = 0.12
		local shrinkDur = 0.22
		local total = popDur + holdDur + shrinkDur
		while not self._destroyed and card.Parent do
			local elapsed = (os.clock() - t0) / self._timescale
			if elapsed < popDur then
				local u = elapsed / popDur
				scale.Scale = 1.3 * (1 - (1 - u) ^ 3)
			elseif elapsed < popDur + holdDur then
				scale.Scale = 1.3 - 0.3 * ((elapsed - popDur) / holdDur)
			elseif elapsed < total then
				local u = (elapsed - popDur - holdDur) / shrinkDur
				scale.Scale = math.max(0, 1 - u)
				card.BackgroundTransparency = u
				stroke.Transparency = u
			else
				break
			end
			task.wait()
		end
		if card.Parent then
			card:Destroy()
		end
	end)
end

-- ===================== skip prompt =====================
function HypeUI:showSkipPrompt()
	if self._destroyed then
		return
	end

	if not self._skipHost then
		local host = Instance.new("Frame")
		host.Name = "SkipHost"
		host.AnchorPoint = Vector2.new(1, 1)
		host.Position = UDim2.new(1, -24, 1, bottomOffset(24))
		host.Size = UDim2.fromOffset(220, 54)
		host.BackgroundTransparency = 1
		host.ZIndex = 7
		host.Parent = self._gui

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.AnchorPoint = Vector2.new(0, 1)
		track.Position = UDim2.new(0, 0, 1, 0)
		track.Size = UDim2.new(1, 0, 0, 8)
		track.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		track.BackgroundTransparency = 0.25
		track.BorderSizePixel = 0
		track.ZIndex = 7
		track.Parent = host
		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(1, 0)
		trackCorner.Parent = track

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.AnchorPoint = Vector2.new(0, 0)
		fill.Position = UDim2.fromScale(0, 0)
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(255, 216, 77)
		fill.BorderSizePixel = 0
		fill.ZIndex = 8
		fill.Parent = track
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill

		local l = label(host, "HOLD TO SKIP", 20, Color3.fromRGB(235, 235, 240), 3)
		l.Name = "Label"
		l.AnchorPoint = Vector2.new(1, 1)
		l.Position = UDim2.new(1, 0, 1, -14)
		l.ZIndex = 7

		self._skipHost = host
		self._skipLabel = l
		self._skipFillBar = fill
	end

	local host = self._skipHost :: Frame
	self._skipGen += 1

	host.Visible = true
	for _, d in ipairs(host:GetDescendants()) do
		if d:IsA("TextLabel") then
			d.TextTransparency = 0
			local st = d:FindFirstChildOfClass("UIStroke")
			if st then
				st.Transparency = 0
			end
		elseif d:IsA("Frame") then
			d.BackgroundTransparency = (d.Name == "Track") and 0.25 or 0
		end
	end
	(self._skipFillBar :: Frame).Size = UDim2.new(0, 0, 1, 0)
end

function HypeUI:setSkipProgress(alpha: number)
	if self._destroyed or not self._skipFillBar then
		return
	end
	local a = math.clamp(tonumber(alpha) or 0, 0, 1)
	self._skipFillBar.Size = UDim2.new(a, 0, 1, 0)
end

function HypeUI:hideSkipPrompt()
	if self._destroyed or not self._skipHost then
		return
	end
	local host = self._skipHost :: Frame
	self._skipGen += 1
	local myGen = self._skipGen
	local seconds = math.max(self._skip.exitFadeSeconds or 0.18, 0.02)

	local startText: { [TextLabel]: number } = {}
	local startStroke: { [UIStroke]: number } = {}
	local startBg: { [Frame]: number } = {}
	for _, d in ipairs(host:GetDescendants()) do
		if d:IsA("TextLabel") then
			startText[d] = d.TextTransparency
		elseif d:IsA("UIStroke") then
			startStroke[d] = d.Transparency
		elseif d:IsA("Frame") then
			startBg[d] = d.BackgroundTransparency
		end
	end

	task.spawn(function()
		local t0 = os.clock()
		while self._skipGen == myGen and not self._destroyed and host.Parent do
			local a = math.clamp(((os.clock() - t0) / self._timescale) / seconds, 0, 1)
			for d, s in pairs(startText) do
				d.TextTransparency = s + (1 - s) * a
			end
			for d, s in pairs(startStroke) do
				d.Transparency = s + (1 - s) * a
			end
			for d, s in pairs(startBg) do
				d.BackgroundTransparency = s + (1 - s) * a
			end
			if a >= 1 then
				break
			end
			task.wait()
		end
		if self._skipGen == myGen and not self._destroyed and host.Parent then
			host.Visible = false
		end
	end)
end

-- ===================== interrupt =====================
-- Hard-cuts every in-flight HYPE effect IMMEDIATELY, in this same
-- synchronous call: bumps every generation counter (so no straggling
-- task.spawn loop writes another frame) and destroys the transient
-- instances outright -- banner, name letters,
-- slots, and any live card pop(s). Deliberately does NOT touch the
-- ScreenGui itself, and does NOT touch anything owned by
-- showSkipPrompt/setSkipProgress/hideSkipPrompt -- see the module header's
-- "interrupt() contract" for why (the Sequencer owns the skip prompt's own
-- lifecycle and calls it separately). Meme-text assignment (_memeAssignment)
-- is intentionally preserved -- it's a per-cinematic constant, not a
-- per-effect one, and clearing it would make a post-interrupt memeFlyIns
-- re-roll which meme text goes with which punch, breaking "pure in t".
function HypeUI:interrupt()
	if self._destroyed then
		return
	end

	self._bannerGen += 1
	if self._bannerLabel then
		self._bannerLabel:Destroy()
		self._bannerLabel = nil
		self._bannerScale = nil
	end

	self._nameGen += 1
	if self._nameFrame then
		self._nameFrame:Destroy()
		self._nameFrame = nil
	end
	self._nameChars = {}

	for _, child in ipairs(self._gui:GetChildren()) do
		if child.Name == "CardArrive" then
			child:Destroy()
		end
	end
end

-- ===================== cleanup =====================
function HypeUI:cleanup()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._bannerGen += 1
	self._nameGen += 1
	self._skipGen += 1

	pcall(function()
		self._gui:Destroy()
	end)

	self._bannerLabel = nil
	self._bannerScale = nil
	self._nameFrame = nil
	self._nameChars = {}
	self._skipHost = nil
	self._skipLabel = nil
	self._skipFillBar = nil
	self._bagSearchRootOverride = nil

	-- M6: these fields aren't optional in the type (HypeCfg/SkipCfg/
	-- ParticlesCfg/Random), so the final release goes through an `any`
	-- alias rather than widening their declared types just for cleanup.
	local selfAny: any = self
	selfAny._hype = nil
	selfAny._skip = nil
	selfAny._particles = nil
	selfAny._rng = nil
end

return HypeUI
