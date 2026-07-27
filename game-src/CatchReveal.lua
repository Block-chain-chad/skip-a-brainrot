-- CatchReveal: the catch moment.
--
-- When you catch a brainrot, the brainrot ITSELF appears on screen and spins
-- slowly. Four bands over the eight tiers, each adding a NEW KIND of thing
-- rather than more of the last -- the rule that makes the RarityFX and
-- MutationFX ladders readable at a glance:
--
--   1  Common/Uncommon   small viewport, no backdrop
--   2  Rare/Epic         bigger + a coloured halo
--   3  Legendary/Mythic  large + shimmer + sparkles, screen darkened
--   4  Secret/God        a REAL world model, camera locked, full MutationFX
--
-- Why band 4 is not a viewport: ParticleEmitters and Highlight DO NOT RENDER
-- inside a ViewportFrame (BrainrotThumb says as much in its own header), and
-- MutationFX is built entirely from those two. A viewport reveal structurally
-- cannot show a mutation. Secret and God are exactly the catches where a
-- mutation is most worth seeing, so those two get a real model instead.
--
-- This module knows nothing about remotes and nothing about Robux. It is given
-- a catch and it shows it. CatchRevealClient decides whether to call it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local UITheme = require(ReplicatedStorage.Modules.UITheme)

local M = {}

local CF = UITheme.Camp
local player = Players.LocalPlayer

local BAND_OF = {
	Common = 1, Uncommon = 1,
	Rare = 2, Epic = 2,
	Legendary = 3, Mythic = 3,
	Secret = 4, God = 4,
}

-- size    viewport square in px
-- hold    seconds fully on screen, excluding the fades
-- dark    how black the backdrop goes, as OPACITY (0 = no backdrop)
-- halo    coloured ring behind the model
-- shimmer seconds per shine sweep, or false
-- sparkle how many twinkles
local SPEC = {
	{ size = 180, hold = 1.4, dark = 0.00, halo = false, shimmer = false, sparkle = 0 },
	{ size = 280, hold = 2.0, dark = 0.15, halo = true,  shimmer = false, sparkle = 0 },
	{ size = 380, hold = 2.8, dark = 0.45, halo = true,  shimmer = 2.4,   sparkle = 4 },
	-- Band 4 is filled in by the world path. Until that exists it renders as
	-- band 3, so every tier already has a working reveal.
	{ size = 380, hold = 3.8, dark = 0.80, halo = true,  shimmer = 1.8,   sparkle = 5 },
}

local SPIN = 70     -- degrees per second, identical in every band
local FADE = 0.22   -- seconds, in and out
local FOV  = 30     -- viewport camera, matches BrainrotThumb

-- fixed sparkle spots so a reveal looks composed rather than random
local SPARKLE_AT = {
	Vector2.new(0.14, 0.22), Vector2.new(0.85, 0.28), Vector2.new(0.24, 0.74),
	Vector2.new(0.78, 0.70), Vector2.new(0.50, 0.10),
}

local gui             -- ScreenGui, built on first use
local live            -- the running reveal's record, or nil
local token = 0

local function ensureGui()
	if gui and gui.Parent then return gui end
	gui = Instance.new("ScreenGui")
	gui.Name = "CatchRevealUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- above the rare-catch banner (8) and every panel (9)
	gui.DisplayOrder = 12
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

-- Safe to call twice, and safe after a natural finish. Everything that can
-- outlive the reveal is torn down here and nowhere else, so there is exactly
-- one path out.
local function teardown(rec)
	if not rec or rec.dead then return end
	rec.dead = true
	if rec.conn then rec.conn:Disconnect(); rec.conn = nil end
	if rec.restore then pcall(rec.restore) end
	if rec.root then rec.root:Destroy(); rec.root = nil end
	if live == rec then live = nil end
end

-- The model, framed and spinning. Returns the per-frame updater, or nil when
-- there is no model for that name (caller falls back to text only).
local function buildViewport(rec, spec, info, parent)
	local master = BrainrotThumb.master(info.Name)
	if not master then return nil end

	local vp = Instance.new("ViewportFrame")
	vp.Name = "Model"
	vp.AnchorPoint = Vector2.new(0.5, 0)
	vp.Position = UDim2.fromScale(0.5, 0)
	vp.Size = UDim2.fromOffset(spec.size, spec.size)
	vp.BackgroundTransparency = 1
	vp.ZIndex = 3
	vp.Parent = parent

	local m = master:Clone()
	m.Parent = vp

	-- Frame from the REAL bounding box: these models run from under 5 studs to
	-- over 30, so one fixed distance would crop the big ones and shrink the
	-- small ones to a dot. Shared with BrainrotThumb.add so the grids and the
	-- reveal cannot disagree about how a model is framed.
	local centre, dist = BrainrotThumb.framing(m, FOV)

	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vp
	vp.CurrentCamera = cam

	rec.viewport = vp

	-- Spin the CAMERA around the model, not the model. Rotating the model would
	-- need its pivot moved to the bounding-box centre first, because on these
	-- packs the PrimaryPart is an arbitrary limb sitting anywhere inside the
	-- body -- it would wobble around an off-centre point. Orbiting the camera
	-- is identical on screen and cannot disturb the model at all.
	local base = BrainrotThumb.DEFAULT_DIR
	return function(t)
		local dir = CFrame.Angles(0, math.rad(SPIN) * t, 0) * base
		cam.CFrame = CFrame.lookAt(centre + dir * dist, centre)
	end
end

function M.isPlaying()
	return live ~= nil and not live.dead
end

-- info = { Name, Rarity, RarityColor, Mutation }
-- Returns a handle with :skip(), or nil if nothing could be shown.
function M.play(info)
	if type(info) ~= "table" or type(info.Name) ~= "string" then return nil end

	-- newest wins, matching the resultToken behaviour the old card had
	if live then teardown(live) end
	token += 1
	local myToken = token

	local band = BAND_OF[info.Rarity] or 1
	local spec = SPEC[band]
	local accent = typeof(info.RarityColor) == "Color3" and info.RarityColor
		or Color3.fromRGB(190, 190, 190)

	local rec = { dead = false, band = band, token = myToken }

	-- Everything below touches live Instances and third-party modules
	-- (BrainrotThumb, UITheme). It all runs inside ONE pcall: rec is reachable
	-- from the instant root is parented below, so no matter how far
	-- construction gets before something throws, teardown(rec) can still find
	-- and destroy whatever was built. Reveal must never be able to break the
	-- catch that triggered it.
	local ok, err = pcall(function()
		local root = Instance.new("Frame")
		root.Name = "Reveal"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.ZIndex = 1
		root.Parent = ensureGui()
		rec.root = root

		local fades = {}   -- {inst, prop, to}

		-- backdrop. Stated as OPACITY in SPEC, so invert it here -- "dark 0.8" read
		-- as a transparency would mean the opposite of what is intended.
		if spec.dark > 0 then
			local dim = Instance.new("Frame")
			dim.Name = "Dim"
			dim.Size = UDim2.fromScale(1, 1)
			dim.BackgroundColor3 = Color3.new(0, 0, 0)
			dim.BackgroundTransparency = 1
			dim.BorderSizePixel = 0
			dim.ZIndex = 1
			dim.Parent = root
			table.insert(fades, { dim, "BackgroundTransparency", 1 - spec.dark })
		end

		local holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.42)   -- above centre, clear of the hotbar
		holder.Size = UDim2.fromOffset(spec.size, spec.size + 92)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 2
		holder.Parent = root

		-- halo: an oversized ring behind the model carrying a coloured stroke
		local haloStroke
		if spec.halo then
			local halo = Instance.new("Frame")
			halo.Name = "Halo"
			halo.AnchorPoint = Vector2.new(0.5, 0.5)
			halo.Position = UDim2.new(0.5, 0, 0, spec.size / 2)
			halo.Size = UDim2.fromOffset(spec.size * 0.86, spec.size * 0.86)
			halo.BackgroundTransparency = 1
			halo.ZIndex = 2
			halo.Parent = holder
			local hc = Instance.new("UICorner")
			hc.CornerRadius = UDim.new(1, 0)
			hc.Parent = halo
			haloStroke = Instance.new("UIStroke")
			haloStroke.Color = accent
			haloStroke.Thickness = 6
			haloStroke.Transparency = 1
			haloStroke.LineJoinMode = Enum.LineJoinMode.Round
			haloStroke.Parent = halo
			table.insert(fades, { haloStroke, "Transparency", 0.35 })
		end

		local spin = buildViewport(rec, spec, info, holder)
		if rec.viewport then
			rec.viewport.ImageTransparency = 1
			table.insert(fades, { rec.viewport, "ImageTransparency", 0 })
		end

		-- shimmer lives on its OWN empty frame, never on anything holding text: a
		-- UIGradient tints its parent's glyphs too, which has bitten this codebase.
		local shimmerGrad
		if spec.shimmer then
			local shim = Instance.new("Frame")
			shim.Name = "Shimmer"
			shim.Size = UDim2.fromOffset(spec.size, spec.size)
			shim.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			shim.BackgroundTransparency = 0
			shim.BorderSizePixel = 0
			shim.ZIndex = 4
			shim.Parent = holder
			shimmerGrad = Instance.new("UIGradient")
			shimmerGrad.Rotation = 24
			shimmerGrad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.44, 1),
				NumberSequenceKeypoint.new(0.50, 0.62),
				NumberSequenceKeypoint.new(0.56, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
			shimmerGrad.Parent = shim
		end

		local sparkles = {}
		for i = 1, spec.sparkle do
			local at = SPARKLE_AT[i] or SPARKLE_AT[1]
			local s = Instance.new("TextLabel")
			s.Name = "Sparkle"
			s.AnchorPoint = Vector2.new(0.5, 0.5)
			s.Position = UDim2.new(at.X, 0, 0, at.Y * spec.size)
			s.Size = UDim2.fromOffset(40, 40)
			s.BackgroundTransparency = 1
			s.Font = UITheme.GlyphFont
			s.Text = "\u{2726}"
			s.TextColor3 = Color3.fromRGB(255, 255, 255)
			s.TextSize = 26
			s.TextTransparency = 1
			s.ZIndex = 5
			s.Parent = holder
			sparkles[i] = s
		end

		-- name, then rarity. No panel behind either -- that is the whole point.
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "BrainrotName"
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.Position = UDim2.new(0.5, 0, 0, spec.size + 6)
		nameLabel.Size = UDim2.fromOffset(spec.size + 160, 40)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = UITheme.Font
		nameLabel.TextSize = 30
		nameLabel.TextColor3 = CF.onDark
		nameLabel.TextScaled = false
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = info.Name
		nameLabel.TextTransparency = 1
		nameLabel.ZIndex = 6
		nameLabel.Parent = holder
		local nameInk = UITheme.inkText(nameLabel, 3)
		nameInk.Transparency = 1

		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "Rarity"
		rarityLabel.AnchorPoint = Vector2.new(0.5, 0)
		rarityLabel.Position = UDim2.new(0.5, 0, 0, spec.size + 48)
		rarityLabel.Size = UDim2.fromOffset(spec.size + 160, 32)
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Font = UITheme.Font
		rarityLabel.TextSize = 23
		rarityLabel.TextColor3 = accent
		rarityLabel.Text = string.upper(tostring(info.Rarity or "?"))
		rarityLabel.TextTransparency = 1
		rarityLabel.ZIndex = 6
		rarityLabel.Parent = holder
		local rarityInk = UITheme.inkText(rarityLabel, 2.6)
		rarityInk.Transparency = 1
		rec.rarityLabel = rarityLabel

		table.insert(fades, { nameLabel, "TextTransparency", 0 })
		table.insert(fades, { rarityLabel, "TextTransparency", 0 })
		table.insert(fades, { nameInk, "Transparency", 0 })
		table.insert(fades, { rarityInk, "Transparency", 0 })

		-- fade in
		for _, f in ipairs(fades) do
			TweenService:Create(f[1], TweenInfo.new(FADE), { [f[2]] = f[3] }):Play()
		end

		-- One driver for this reveal, disconnected in teardown. Nothing per-frame
		-- survives the reveal.
		local t = 0
		rec.conn = RunService.RenderStepped:Connect(function(dt)
			t += dt
			if spin then spin(t) end
			if haloStroke then
				haloStroke.Transparency = 0.35 + 0.22 * (0.5 + 0.5 * math.sin(t * 2.1))
			end
			if shimmerGrad then
				shimmerGrad.Offset = Vector2.new(((t / spec.shimmer) % 1) * 2.6 - 1.3, 0)
			end
			for i = 1, #sparkles do
				local k = 0.5 + 0.5 * math.sin(t * 3.1 + i * 1.9)
				sparkles[i].TextTransparency = 1 - k
				sparkles[i].TextSize = 14 + 14 * k
			end
		end)

		live = rec

		-- hold, fade out, tear down
		task.delay(FADE + spec.hold, function()
			if rec.dead or rec.token ~= token then return end
			for _, f in ipairs(fades) do
				local back = (f[2] == "ImageTransparency" or f[2] == "TextTransparency"
					or f[2] == "Transparency" or f[2] == "BackgroundTransparency") and 1 or 0
				TweenService:Create(f[1], TweenInfo.new(FADE), { [f[2]] = back }):Play()
			end
			task.delay(FADE, function()
				if rec.token == token then teardown(rec) end
			end)
		end)
	end)

	if not ok then
		warn(("[CatchReveal] M.play failed while building the reveal -- tearing down: %s"):format(tostring(err)))
		teardown(rec)
		return nil
	end

	return {
		skip = function()
			teardown(rec)
		end,
	}
end

return M
