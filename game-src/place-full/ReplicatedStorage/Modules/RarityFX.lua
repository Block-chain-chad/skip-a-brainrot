-- RarityFX: escalating "this one is special" treatment for inventory tiles.
--
-- The point is CONTRAST. Common and Uncommon deliberately get NOTHING -- if every
-- tile shimmered, none would read as rare. Effects start at Rare and pile up, so
-- the good stuff announces itself across a dense grid.
--
-- ONE Heartbeat drives every tile. Per-tile connections would mean ~60 live
-- connections on a full backpack; this is a single loop over a registry that drops
-- entries as soon as their tile is destroyed, so a rebuild cleans itself up.

local RunService = game:GetService("RunService")

local M = {}

-- glow    = stroke transparency at rest (LOWER is stronger)
-- shimmer = seconds per sweep across the tile, or false
-- sparkle = how many twinkles
-- rainbow = hue cycles per second on the border, or false
-- The ladder adds ONE new kind of effect per step, so you can tell tiers apart at
-- a glance rather than just "more sparkly":
--     Rare/Epic  faint coloured rim, nothing moving
--     Legendary  + a shine sweep
--     Mythic     + sparkles
--     Secret/God + a cycling rainbow border
-- Tuned against a real end-game backpack, where 48 of 58 tiles were Rare or
-- better: starting the moving effects at Rare made almost everything shimmer,
-- which defeated the whole point.
local SPEC = {
	Common    = false,
	Uncommon  = false,
	Rare      = { glow = 0.72, shimmer = false, sparkle = 0, rainbow = false },
	Epic      = { glow = 0.60, shimmer = false, sparkle = 0, rainbow = false },
	Legendary = { glow = 0.42, shimmer = 3.0,   sparkle = 0, rainbow = false },
	Mythic    = { glow = 0.30, shimmer = 2.3,   sparkle = 3, rainbow = false },
	Secret    = { glow = 0.20, shimmer = 1.8,   sparkle = 4, rainbow = 0.22 },
	God       = { glow = 0.12, shimmer = 1.3,   sparkle = 5, rainbow = 0.45 },
}

-- fixed spots so a tile looks the same on every rebuild instead of jittering
local SPARKLE_AT = {
	Vector2.new(0.16, 0.20), Vector2.new(0.82, 0.30), Vector2.new(0.30, 0.68),
	Vector2.new(0.72, 0.62), Vector2.new(0.50, 0.14),
}

local active, conn, clock = {}, nil, 0

local function ensureDriver()
	if conn then return end
	conn = RunService.Heartbeat:Connect(function(dt)
		clock += dt
		for i = #active, 1, -1 do
			local e = active[i]
			if not e.root.Parent then
				table.remove(active, i)      -- tile destroyed by a rebuild
			else
				e.update(clock)
			end
		end
		if #active == 0 then conn:Disconnect(); conn = nil end
	end)
end

-- Drop every registered tile. The driver sheds them anyway once the instances are
-- destroyed; this just avoids a frame of animating corpses.
function M.reset()
	table.clear(active)
end

function M.tiers() return SPEC end

-- outer = the coloured border frame, inner = the card's content frame.
-- phase spreads the animation so a grid does not pulse in lockstep.
function M.attach(outer, inner, tierName, accent, phase)
	local spec = SPEC[tierName]
	if not spec then return false end
	phase = phase or 0

	local parts = {}

	-- halo: a slightly oversized frame BEHIND the tile carrying a coloured stroke.
	-- It sits in the grid's cell padding, so it costs no layout room.
	local glow = Instance.new("Frame")
	glow.Name = "RarityGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 8, 1, 8)
	glow.BackgroundTransparency = 1
	glow.ZIndex = (outer.ZIndex or 1) - 1
	glow.Parent = outer
	local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 16); gc.Parent = glow
	local gs = Instance.new("UIStroke")
	gs.Color = accent
	gs.Thickness = 4
	gs.Transparency = spec.glow
	gs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gs.LineJoinMode = Enum.LineJoinMode.Round
	gs.Parent = glow
	parts.glow = gs

	-- shine sweep. The gradient lives on its OWN empty frame, never on anything
	-- holding text -- a UIGradient tints its parent's glyphs too, which has bitten
	-- this codebase before.
	if spec.shimmer then
		local shim = Instance.new("Frame")
		shim.Name = "Shimmer"
		shim.Size = UDim2.fromScale(1, 1)
		shim.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		shim.BorderSizePixel = 0
		shim.ZIndex = 15   -- above the 3D render (14), below value/name text (16)
		shim.Parent = inner
		local shc = Instance.new("UICorner"); shc.CornerRadius = UDim.new(0, 10); shc.Parent = shim
		local sg = Instance.new("UIGradient")
		sg.Rotation = 24
		sg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.44, 1),
			NumberSequenceKeypoint.new(0.50, 0.55),
			NumberSequenceKeypoint.new(0.56, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sg.Parent = shim
		parts.shimmer = sg
	end

	local sparkleCount = spec.sparkle or 0
	for i = 1, sparkleCount do
		local at = SPARKLE_AT[i] or SPARKLE_AT[1]
		local s = Instance.new("TextLabel")
		s.Name = "Sparkle"
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.fromScale(at.X, at.Y)
		s.Size = UDim2.fromOffset(18, 18)
		s.BackgroundTransparency = 1
		s.Font = Enum.Font.GothamBold
		s.Text = "\u{2726}"
		s.TextColor3 = Color3.fromRGB(255, 255, 255)
		s.TextSize = 13
		s.ZIndex = 17
		s.Parent = inner
		parts[i] = s
	end

	active[#active + 1] = {
		root = outer,
		update = function(t)
			local tt = t + phase
			parts.glow.Transparency = spec.glow + 0.18 * (0.5 + 0.5 * math.sin(tt * 2.1))
			if parts.shimmer then
				parts.shimmer.Offset = Vector2.new(((tt / spec.shimmer) % 1) * 2.6 - 1.3, 0)
			end
			for i = 1, sparkleCount do
				local s = parts[i]
				if s then
					local k = 0.5 + 0.5 * math.sin(tt * 3.1 + i * 1.9)
					s.TextTransparency = 1 - k
					s.TextSize = 9 + 7 * k
				end
			end
			if spec.rainbow then
				-- the border itself cycles: unmistakable at a glance in a full grid
				outer.BackgroundColor3 = Color3.fromHSV((tt * spec.rainbow) % 1, 0.82, 1)
			end
		end,
	}
	ensureDriver()
	return true
end

return M
