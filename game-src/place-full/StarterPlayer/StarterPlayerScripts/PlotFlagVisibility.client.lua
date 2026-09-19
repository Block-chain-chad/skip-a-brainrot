-- PlotFlagVisibility -- the entrance STRING FLAG (the bunting rope + its pennant triangles)
-- marks an AVAILABLE plot: the dirt trails lead a new player straight to one. The instant a
-- plot is claimed the string flag fades away, so a claimed camp reads as lived-in.
--
-- ONLY the strung line fades -- `BuntingRope` + `Pennant1..5`. Every other piece of
-- CampDressing (the fence logs, gate posts, corner stones, entry planks, and the standing
-- FlagPole/FlagPennant) is LEFT ALONE: the camp keeps its decor, just loses the welcome
-- bunting once someone moves in. See isStringFlag() for the exact filter.
--
-- Purely cosmetic + client-side, in the same spirit as PlotBillboardVisibility and
-- PlotSignClient: driven entirely by the plot's replicated `Claimed` attribute, which
-- PlayerDataManager sets true on claim (ClaimPlotFor) and false on release (releaseOnePlot).
-- Because it only ever reads that one authoritative flag, it can never disagree with real
-- ownership and needs no remote of its own. The owner name-sign is a separate PlotBoard
-- model, so nothing else fights us for these parts.
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FADE_TIME = 0.6
local TWEEN_INFO = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local bases = Workspace:WaitForChild("PlayerBases")

-- The build-time look of each dressing part, so a fade-IN restores exactly what was there
-- (a pennant at Transparency 0, a rope that was collidable, etc.) rather than guessing.
local original = {}   -- [BasePart] = { transparency = number, canCollide = boolean }
local active = {}     -- [BasePart] = Tween, so a reversed fade cancels the half-done one

local function remember(part)
	if not original[part] then
		original[part] = { transparency = part.Transparency, canCollide = part.CanCollide }
	end
end

local function applyPart(part, shown, instant)
	remember(part)
	local o = original[part]
	local targetT = shown and o.transparency or 1
	-- an invisible pennant must not become an invisible wall the owner walks into
	part.CanCollide = shown and o.canCollide
	if active[part] then active[part]:Cancel(); active[part] = nil end
	if instant then
		part.Transparency = targetT
	else
		local tw = TweenService:Create(part, TWEEN_INFO, { Transparency = targetT })
		active[part] = tw
		tw.Completed:Connect(function()
			if active[part] == tw then active[part] = nil end
		end)
		tw:Play()
	end
end

-- The entrance string only: the rope and the triangles hung on it. Deliberately NOT
-- `FlagPennant` (that is the flag on the standing FlagPole, which stays), so the pattern is
-- anchored -- `^Pennant%d+$` matches Pennant1..5 but not FlagPennant.
local function isStringFlag(part)
	local n = part.Name
	return n == "BuntingRope" or n:match("^Pennant%d+$") ~= nil
end

local function applyDressing(dressing, shown, instant)
	for _, part in ipairs(dressing:GetDescendants()) do
		if part:IsA("BasePart") and isStringFlag(part) then applyPart(part, shown, instant) end
	end
end

local function isAvailable(plot)
	return not plot:GetAttribute("Claimed")
end

local function hookPlot(plot)
	-- `shown` is the plot's CURRENT availability, kept live so the stream-in handler below
	-- catches late parts up to the right state without re-reading anything.
	local shown = isAvailable(plot)

	local dressing = plot:FindFirstChild("CampDressing")
	if dressing then applyDressing(dressing, shown, true) end   -- instant: no fade on spawn

	plot:GetAttributeChangedSignal("Claimed"):Connect(function()
		shown = isAvailable(plot)
		local dd = plot:FindFirstChild("CampDressing")
		if dd then applyDressing(dd, shown, false) end          -- animated: this is the claim/release
	end)

	-- STREAMING. With StreamingEnabled on, a distant plot's parts (all of the Tundra, seen
	-- from the Valley) are not replicated at join and arrive only once the player travels
	-- near. Parts that stream in AFTER we hooked the plot must be snapped to its current
	-- state -- instantly, because a part the player is only now streaming in shouldn't fade
	-- in front of them. Filtered to CampDressing so pads/brainrots/props are ignored.
	plot.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") and isStringFlag(inst) then
			local dd = plot:FindFirstChild("CampDressing")
			if dd and inst:IsDescendantOf(dd) then
				applyPart(inst, shown, true)
			end
		end
	end)
end

for _, plot in ipairs(bases:GetChildren()) do
	if plot:IsA("Model") then hookPlot(plot) end
end
bases.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		task.defer(hookPlot, child)   -- let CampDressing replicate in before we read it
	end
end)
