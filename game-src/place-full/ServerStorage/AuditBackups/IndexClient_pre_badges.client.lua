-- Brainrot Index: browse every brainrot grouped by rarity; locked until you catch one.
--
-- This panel is now the game's honesty surface for VALUE. Three things it must
-- never fudge:
--   1. AVAILABILITY. 214 names are authored, ~67 are catchable this wave. An
--      entry you simply have not caught yet and an entry the game has not
--      released look completely different, because only the first is something
--      the player can go and do.
--   2. SUPPLY. Exists counts and mint serials come from the server's MintRegistry
--      and are shown ONLY when it actually answered -- a cold registry hides the
--      line rather than printing a confident "0 exist".
--   3. PRICE. The camp price is the median of what players ACTUALLY PAID at the
--      stalls in the last 7 days, carries its sample count, and is never dressed
--      up as an official value.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local Waves = require(ReplicatedStorage.Modules.BrainrotWaves)
local SupplySchedule = require(ReplicatedStorage.Modules.SupplySchedule)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local BrainrotLooks = require(ReplicatedStorage.Modules.BrainrotLooks)
local BodyBuilder = require(ReplicatedStorage.Modules.BrainrotBodyBuilder)

local P = UITheme.Palette
local CF = UITheme.Camp
local BLACK = Color3.fromRGB(0, 0, 0)
local FONT = UITheme.Font
local discovered = {}
-- [name] = { Mult, Mutation, Serial } for the single copy of that name worth
-- quoting: rarest mutation you own, ties broken by the lowest (earliest) serial.
local ownedByName = {}

-- was capped at M, so a Secret earning 9.99B/s rendered as "10000.0M/s"
local shorten = require(ReplicatedStorage.Modules.NumberFormat).Short
local function blackRim(o, thick)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = BLACK; s.Thickness = thick or 3; s.Transparency = 0
		end
	end
end
local function inkText(o, thick)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Color = BLACK; st.Thickness = thick or 2; st.Transparency = 0.05
	st.Parent = o
	return st
end

-- ======================= the roster, flattened once =======================
-- The list is flattened at require time in RarityConfig order, so paging is a
-- pair of indices rather than a re-scan, and the per-tier tallies never have to
-- be recounted while the player flicks through pages.
local ordered = {}                 -- { { E = entry, Tier = tier }, ... }
local tierTotal, tierLive = {}, {}

local AV_LIVE, AV_SOON, AV_VAULTED = 1, 2, 3

-- Supply status comes from SupplySchedule (clock-pure: the same answer the
-- server computes), refined into the three visual buckets. "away this week"
-- and "retired forever" mean OPPOSITE things to a player -- one is a schedule,
-- the other makes an owned copy worth MORE -- so the manual VAULTED override
-- is still read directly and never conflated with the tide.
local function availabilityOf(name)
	-- quest-reward-only items (e.g. Maxwell) are never catchable via a throw -- their only
	-- source is the quest grant. Never show them as "live" or count them as CATCHABLE.
	if Waves.QUEST_ONLY and Waves.QUEST_ONLY[name] then return AV_VAULTED, "quest", nil end
	if Waves.VAULTED and Waves.VAULTED[name] then return AV_VAULTED, "vaulted", nil end
	if Waves.FORCE_ON and Waves.FORCE_ON[name] then
		return AV_LIVE, SupplySchedule.CAPPED[name] and "capped" or "live", nil
	end
	local status, ts = SupplySchedule.StatusOf(name)
	if status == "vaulted" then return AV_VAULTED, status, ts end
	if status == "away" or status == "unreleased" then return AV_SOON, status, ts end
	return AV_LIVE, status or "live", ts
end

-- "3d 4h" / "5h 12m" / "42m" -- countdowns, never weekday names: every flip is
-- a Monday-00:00-UTC instant, so a weekday label would read "MON" forever and
-- actively mislead on Mondays. Server-synced clock, immune to device skew.
local function deltaText(ts)
	local left = math.max(0, math.floor(ts - workspace:GetServerTimeNow()))
	local d = math.floor(left / 86400)
	local h = math.floor(left % 86400 / 3600)
	if d > 0 then return d .. "d " .. h .. "h" end
	local m = math.floor(left % 3600 / 60)
	if h > 0 then return h .. "h " .. m .. "m" end
	return m .. "m"
end

-- Sold-out counts for capped names: server truth (LimitedStock), fetched
-- lazily on Index open and at most once a minute. nil until the first answer
-- arrives -- the copy below never does arithmetic on an unknown count.
local supplySnap, supplySnapAt = nil, 0
local function refreshSupplySnap()
	if os.clock() - supplySnapAt < 60 then return end
	supplySnapAt = os.clock()
	task.spawn(function()
		local ok, snap = pcall(function()
			return remotes.GetSupplySnapshot:InvokeServer()
		end)
		if ok and type(snap) == "table" then supplySnap = snap end
	end)
end

do
	local byRarity = {}
	for _, e in ipairs(BrainrotConfig) do
		byRarity[e.Rarity] = byRarity[e.Rarity] or {}
		table.insert(byRarity[e.Rarity], e)
	end
	for _, tier in ipairs(RarityConfig) do
		local entries = byRarity[tier.Name]
		tierTotal[tier.Name] = entries and #entries or 0
		tierLive[tier.Name] = 0
		if entries then
			for _, e in ipairs(entries) do
				ordered[#ordered + 1] = { E = e, Tier = tier }
			end
		end
	end
end

-- Availability is TIME-VARYING now (weekly tide, seasonal vault), so the live
-- tallies and the "catchable only" view refresh whenever the schedule period
-- turns -- keyed, so the common case (same week) costs one string compare.
-- orderedLive keeps its table identity: it is captured by the pager handlers.
local orderedLive = {}
local LIVE_COUNT, TOTAL_COUNT = 0, #ordered
local lastPeriodKey = nil
local function refreshAvailability()
	local key = SupplySchedule.PeriodKey() .. "#" .. Waves.OverrideKey()
	if key == lastPeriodKey then return end
	lastPeriodKey = key
	table.clear(orderedLive)
	for _, tier in ipairs(RarityConfig) do tierLive[tier.Name] = 0 end
	for _, rec in ipairs(ordered) do
		if availabilityOf(rec.E.Name) == AV_LIVE then
			orderedLive[#orderedLive + 1] = rec
			tierLive[rec.Tier.Name] += 1
		end
	end
	LIVE_COUNT = Waves.Counts()
end
refreshAvailability()

---------------------------------------------------------------- open button
local indexTile = SideRail.MakeTile({
	name = "Index", iconKind = "book", layoutOrder = 5,
	hueTop = Color3.fromRGB(120, 226, 190), hueBottom = Color3.fromRGB(24, 158, 126),
	accent = Color3.fromRGB(40, 190, 150),
})
local openBtn = indexTile.button

---------------------------------------------------------------- panel
local frame = Instance.new("Frame")
frame.Name = "IndexFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.Size = UDim2.fromOffset(788, 660)
frame.Visible = false
frame.ZIndex = 10
frame.Parent = gui
UITheme.campPanel(frame)
SideRail.registerPanel(frame)   -- only one rail panel open at a time

-- Short-viewport guard: shrink and push the panel down so it never covers the
-- top TabBar band (146px) and keeps a 40px bottom margin. Anchor stays (0.5, 0.5).
local FRAME_H = 660
local hudScale = Instance.new("UIScale")
hudScale.Name = "HudFixScale"
hudScale.Parent = frame
local function relayout()
	local vh = gui.AbsoluteSize.Y
	if vh <= 0 then return end
	local s = math.min(1, (vh - 146 - 40) / FRAME_H)
	hudScale.Scale = s
	-- clamp so the panel's top edge sits at or below the 146px band
	frame.Position = UDim2.new(0.5, 0, 0.5, math.max(0, 146 + FRAME_H * s / 2 - vh / 2))
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
relayout()

-- carved-wood banner that overhangs the panel top
local ribbon, title = UITheme.ribbon(frame, "BRAINROT INDEX", 0.68)

local counter = Instance.new("TextLabel")
counter.Size = UDim2.new(1, -44, 0, 22)
counter.Position = UDim2.new(0, 22, 0, 46)
counter.BackgroundTransparency = 1
counter.Font = FONT
counter.TextSize = 15
counter.TextColor3 = CF.muted
counter.Text = "0 / 0 DISCOVERED"
counter.ZIndex = 12
counter.Parent = frame
UITheme.inkText(counter, 1.8)

---------------------------------------------------------------- filter + pager
local controls = Instance.new("Frame")
controls.Size = UDim2.new(1, -44, 0, 28)
controls.Position = UDim2.new(0, 22, 0, 72)
controls.BackgroundTransparency = 1
controls.ZIndex = 12
controls.Parent = frame

-- A UIGradient tints its parent GuiObject's TEXT as well as its background, so a
-- TextButton styled by campButton renders its own caption in the button's own
-- colour. Every caption here therefore lives in a CHILD TextLabel -- the same fix
-- LuckHUDClient documents for the luck chip.
local function captionFor(btn, size)
	local l = Instance.new("TextLabel")
	l.Name = "Label"
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = CF.cream
	l.Text = ""
	l.ZIndex = btn.ZIndex + 1
	l.Parent = btn
	UITheme.inkText(l, 2.2)
	return l
end

-- With most of the roster uncatchable, "show me only what I can actually get" is
-- the most useful control in the panel.
local filterBtn = Instance.new("TextButton")
filterBtn.Size = UDim2.fromOffset(186, 28)
filterBtn.Text = ""
filterBtn.ZIndex = 13
filterBtn.Parent = controls
UITheme.campButton(filterBtn, CF.wood1, CF.wood2)
local filterLabel = captionFor(filterBtn, 14)

local function pagerButton(glyph, xOffset)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, xOffset, 0, 0)
	b.Size = UDim2.fromOffset(34, 28)
	b.Text = ""
	b.ZIndex = 13
	b.Parent = controls
	UITheme.campButton(b, CF.amber1, CF.amber2)
	local l = captionFor(b, 20)
	-- FredokaOne has no guillemet glyph, so the caption drops to GothamBold
	l.Font = Enum.Font.GothamBold
	l.Text = glyph
	return b, l
end

-- Kept as instances so the wiring further down still resolves, but hidden: there are
-- no pages any more, the sheet scrolls.
local nextBtn, nextLabel = pagerButton("\u{203A}", 0)
local prevBtn, prevLabel = pagerButton("\u{2039}", -164)
nextBtn.Visible = false
prevBtn.Visible = false

local pageLabel = Instance.new("TextLabel")
pageLabel.AnchorPoint = Vector2.new(1, 0)
pageLabel.Position = UDim2.new(1, 0, 0, 0)
pageLabel.Size = UDim2.fromOffset(180, 28)
pageLabel.BackgroundTransparency = 1
pageLabel.Font = FONT
pageLabel.TextSize = 14
pageLabel.TextColor3 = CF.cream
pageLabel.Text = "PAGE 1 / 1"
pageLabel.ZIndex = 13
pageLabel.Parent = controls
UITheme.inkText(pageLabel, 1.8)

local closeBtn = Instance.new("TextButton")
closeBtn.Parent = frame
UITheme.styleClose(closeBtn)
closeBtn.ZIndex = 18 -- set AFTER styleClose, which forces ZIndex 6
-- styleClose draws the X as two rotated Frames now, not a glyph. An earlier
-- version of this comment blamed FredokaOne and pinned GothamBold as a fix;
-- a proof board rendered in GothamBold was still blank, so that never worked.
closeBtn.TextSize = 18
blackRim(closeBtn, 3)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -36, 1, -146)
list.Position = UDim2.new(0, 18, 0, 110)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 11
list.Parent = frame
-- Cell geometry is declared here, next to the layout that consumes it, because the
-- virtualiser computes each tile's Y from these same numbers -- if they drifted apart
-- it would fill and clear the wrong tiles.
local CELL_W, CELL_H, CELL_PAD = 136, 156, 10
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(CELL_W, CELL_H)
layout.CellPadding = UDim2.fromOffset(CELL_PAD, CELL_PAD)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local footnote = Instance.new("TextLabel")
footnote.Size = UDim2.new(1, -44, 0, 22)
footnote.Position = UDim2.new(0, 22, 1, -30)
footnote.BackgroundTransparency = 1
footnote.Font = Enum.Font.GothamMedium
footnote.TextSize = 12
footnote.TextColor3 = CF.muted
footnote.TextXAlignment = Enum.TextXAlignment.Left
footnote.TextTruncate = Enum.TextTruncate.AtEnd
footnote.Text = ""
footnote.ZIndex = 12
footnote.Parent = frame
UITheme.inkText(footnote, 1.6)

---------------------------------------------------------------- supply + price
-- Exists counts (MintRegistry) and camp prices (PriceIndex) are server-side, so
-- they arrive over ReplicatedStorage.Remotes.GetItemStats. Two rules keep that
-- from becoming a firehose:
--   * ONE batched invoke per rendered page, never one call per row;
--   * a client cache, so paging back to a page you have already seen -- or just
--     scrolling it -- asks the server for nothing at all.
local statsRemote = remotes:WaitForChild("GetItemStats")
local statsCache = {}      -- [key] = { At = os.clock(), D = payload }
local statsMeta = { WindowDays = 7, MinSamples = 5 }   -- replaced by the server's real tuning
local POS_TTL = 90         -- the server answered with real numbers
local NEG_TTL = 15         -- it answered, but the mint registry was still cold
local inFlight = false
local pageRows = {}        -- rows of the CURRENT render, for in-place patching
local buildGen = 0         -- bumped per render, so a late reply cannot patch dead rows

local function statKey(name, mutation)
	return name .. "|" .. (mutation or "")
end

local function cacheFresh(key)
	local c = statsCache[key]
	if not c then return false end
	-- a tracked class that came back without numbers means the registry was cold and
	-- has now kicked off its own read, so it is worth asking again sooner
	local ttl = (c.D and c.D.Tracked and c.D.Minted == nil) and NEG_TTL or POS_TTL
	return (os.clock() - c.At) < ttl
end

local function hex(c)
	return ("#%02X%02X%02X"):format(
		math.clamp(math.floor(c.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.B * 255 + 0.5), 0, 255))
end
local function tint(color, s)
	return '<font color="' .. hex(color) .. '">' .. s .. '</font>'
end
local SEP = '<font color="#8A7A6C">   \u{00B7}   </font>'

-- One line of hard numbers per row. EVERY piece is optional: when the server has
-- not answered, or the class genuinely has no data, the piece is omitted rather
-- than printed as a zero. "0 EXIST" and "PAID $0" are far worse than silence.
local function statsText(key, owned)
	local parts = {}

	if owned and type(owned.Serial) == "number" then
		local col = (owned.Mutation and Mutations.Color(owned.Mutation)) or CF.amber1
		local tag = owned.Mutation
			and ("%s #%d"):format(string.upper(owned.Mutation), owned.Serial)
			or ("#%d"):format(owned.Serial)
		parts[#parts + 1] = tint(col, tag)
	end

	local cached = statsCache[key]
	local d = cached and cached.D
	if d then
		if d.Tracked and type(d.Exists) == "number" then
			parts[#parts + 1] = tint(CF.lake1, ("%s EXIST"):format(shorten(d.Exists)))
		end
		if type(d.Price) == "number" then
			-- PAID, never "value": the sample count travels with the number so a
			-- player can argue with it instead of trusting it.
			parts[#parts + 1] = tint(CF.pine1, ("PAID $%s (%d sales/%dd)"):format(
				shorten(d.Price), d.Samples or 0, statsMeta.WindowDays))
		elseif (d.Samples or 0) > 0 then
			parts[#parts + 1] = tint(CF.muted, ("PAID: %d of %d sales needed"):format(
				d.Samples, statsMeta.MinSamples))
		end
	end

	return table.concat(parts, SEP)
end

local function applyStats()
	for _, row in ipairs(pageRows) do
		if row.Label.Parent then
			local txt = statsText(row.Key, row.Owned)
			row.Label.Text = txt
			row.Label.Visible = txt ~= ""
		end
	end
	footnote.Text = ("PAID = %d-day median of what players really paid \u{00B7} EXIST = copies still alive")
		:format(statsMeta.WindowDays)
end

local function fetchStats()
	if inFlight or not frame.Visible then return end
	local reqs, seen = {}, {}
	for _, row in ipairs(pageRows) do
		if not seen[row.Key] and not cacheFresh(row.Key) then
			seen[row.Key] = true
			reqs[#reqs + 1] = { Name = row.Name, Mutation = row.Mutation }
		end
	end
	if #reqs == 0 then return end

	inFlight = true
	local gen = buildGen
	task.spawn(function()
		local ok, map, meta = pcall(function()
			return statsRemote:InvokeServer(reqs)
		end)
		inFlight = false
		-- A throttled call still succeeds and returns nil, which must NOT be cached as
		-- "no data" -- it just means ask again later.
		if not ok or typeof(map) ~= "table" then return end
		if typeof(meta) == "table" then
			statsMeta.WindowDays = tonumber(meta.WindowDays) or statsMeta.WindowDays
			statsMeta.MinSamples = tonumber(meta.MinSamples) or statsMeta.MinSamples
		end
		local now = os.clock()
		for key, payload in pairs(map) do
			if typeof(payload) == "table" then
				statsCache[key] = { At = now, D = payload }
			end
		end
		-- the cache is always updated; only the LABELS need the generation guard
		if gen == buildGen then applyStats() end
	end)
end

-- The rarest copy you own is the one worth quoting, and among equals the earliest
-- mint is. Recomputed whole rather than patched, because a trade or a fusion can
-- remove the copy that was previously the best.
local function recomputeOwned(brainrots)
	ownedByName = {}
	if typeof(brainrots) ~= "table" then return end
	for _, b in ipairs(brainrots) do
		if type(b) == "table" and type(b.Name) == "string" then
			local mult = Mutations.Mult(b.Mutation)
			local cur = ownedByName[b.Name]
			local better
			if not cur then
				better = true
			elseif mult > cur.Mult then
				better = true
			elseif mult == cur.Mult and type(b.Serial) == "number" then
				better = (type(cur.Serial) ~= "number") or (b.Serial < cur.Serial)
			end
			if better then
				ownedByName[b.Name] = { Mult = mult, Mutation = b.Mutation, Serial = b.Serial }
			end
		end
	end
end

---------------------------------------------------------------- thumbnails
-- One master model per name per session: Build() assembles a few dozen
-- primitives, and paging back to a page you have already seen must not pay
-- that again. Masters stay UNPARENTED; every viewport gets a CLONE, because a
-- card dies with its page render and would take a shared model down with it.
local SILHOUETTE = Color3.fromRGB(20, 20, 24)
-- front-quarter, slightly above; bodies stand on Y=0 facing -Z
local THUMB_DIR = Vector3.new(0.9, 0.45, -1).Unit
local thumbCache = {}   -- [name] = master Model, or false for "no recipe"

-- Viewports only draw BaseParts, but a real model also carries emitters, prompts,
-- billboards and sounds. Those render nothing and just make every clone heavier, so the
-- master is stripped once and all clones inherit the saving.
local KEEP = { BasePart = true, Model = true, Folder = true }
local function stripForViewport(model)
	for _, d in ipairs(model:GetDescendants()) do
		local keep = d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder")
			or d:IsA("SpecialMesh") or d:IsA("Texture") or d:IsA("Decal")
		if not keep then d:Destroy() end
	end
	return model
end

-- Prefer the REAL model over a recipe.
--
-- BrainrotLooks was generated for an older roster and matches none of the current names,
-- so the recipe path silently produced nothing and every entry fell back to the flat
-- swatch -- which is why no silhouettes were showing. ReplicatedStorage.BrainrotModels
-- holds a real model for 149 of the 150 entries, and a real model is a truer silhouette
-- than a preset body anyway. The recipe stays as a fallback for anything without a model.
local modelFolder = ReplicatedStorage:FindFirstChild("BrainrotModels")

local function thumbModel(name)
	if thumbCache[name] == nil then
		local built
		local real = modelFolder and modelFolder:FindFirstChild(name)
		if real then
			built = stripForViewport(real:Clone())
		else
			local recipe = BrainrotLooks[name]
			built = recipe and BodyBuilder.Build(name, recipe) or nil
		end
		-- false, not nil: a name with neither a model nor a recipe must not re-run
		-- the lookup on every render
		thumbCache[name] = built or false
	end
	return thumbCache[name] or nil
end

-- Returns true only when a viewport was actually added, so the caller can keep
-- the old flat swatch as the fallback for names without a recipe yet.
local function addThumb(parent, name, silhouette)
	local master = thumbModel(name)
	if not master then return false end

	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1   -- the sunburst behind stays the tier read
	-- locked: sit UNDER the state glyph (16); known: take the dot's old slot
	vp.ZIndex = silhouette and 15 or 16
	vp.Parent = parent

	local m = master:Clone()
	if silhouette then
		-- EVERY part goes near-black, eyes included: a locked entry may tease
		-- its shape but never its colours, and white eyes would light up the
		-- shadow and half-reveal the face
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then p.Color = SILHOUETTE end
		end
	end
	m.Parent = vp

	-- distance from the real bounding box, not a constant: the recipe Size
	-- field scales bodies far apart and a fixed distance would crop the big
	-- ones and shrink the small ones to a dot
	local cf, ext = m:GetBoundingBox()
	local dist = math.max(ext.X, ext.Y, ext.Z) / (2 * math.tan(math.rad(15))) + ext.Z * 0.5
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(cf.Position + THUMB_DIR * dist, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam

	return true
end

---------------------------------------------------------------- build rows
-- PAGING IS NOT COSMETIC. The roster is 214 entries, and one card is an
-- accentCard (2 frames, gradient, 2 strokes) plus a sunburst icon and four
-- labels -- call it ~4,000 Instances if the whole roster is built in one frame,
-- which visibly hitches on a phone. A page is ~20 cards, built on demand.
local PAGE_SIZE = 20
local page = 1
local catchableOnly = false

local DIM_TEXT = Color3.fromRGB(120, 108, 98)
local COLD_TEXT = Color3.fromRGB(118, 126, 142)

---------------------------------------------------------------- tile grid
-- One scrolling sheet of tiles, no pages: the tile IS the entry, so name, rarity
-- and silhouette live on the tile and nothing else is drawn beside it.
--
-- VIEWPORTS ARE VIRTUALISED. 150 tiles is cheap (a frame and two labels each), but
-- 150 live ViewportFrames is not -- each renders its own scene, and the models
-- average 12.5 parts. So every tile gets a shell up front and only tiles inside the
-- scroll window (plus a margin) are given a viewport; ones that scroll away have
-- theirs destroyed. Live viewports stay bounded no matter how long the roster gets.
local VIS_MARGIN = 0.6          -- extra screens of tiles kept alive above and below

local tiles = {}                -- [i] = { frame, holder, name, live }
local gridCols = 1

local function fillTile(t, rec)
	if t.live then return end
	local e = rec.E
	local known = discovered[e.Name] == true
	if addThumb(t.holder, e.Name, not known) then t.live = true end
end

local function clearTile(t)
	if not t.live then return end
	for _, c in ipairs(t.holder:GetChildren()) do
		if c:IsA("ViewportFrame") then c:Destroy() end
	end
	t.live = false
end

local function updateVisible()
	if #tiles == 0 then return end
	local viewH = list.AbsoluteSize.Y
	if viewH <= 0 then return end
	local top = list.CanvasPosition.Y - viewH * VIS_MARGIN
	local bottom = list.CanvasPosition.Y + viewH * (1 + VIS_MARGIN)
	local rowH = CELL_H + CELL_PAD
	for i, t in ipairs(tiles) do
		local row = math.floor((i - 1) / gridCols)
		local y0 = row * rowH
		if y0 + CELL_H >= top and y0 <= bottom then
			fillTile(t, t.rec)
		else
			clearTile(t)
		end
	end
end

-- Scrolling is the whole point of virtualising, so listen for it. Resizes matter too:
-- a narrower window changes the column count, which changes every tile's row.
list:GetPropertyChangedSignal("CanvasPosition"):Connect(updateVisible)
list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	local cols = math.max(1, math.floor((list.AbsoluteSize.X + CELL_PAD) / (CELL_W + CELL_PAD)))
	if cols ~= gridCols then gridCols = cols end
	updateVisible()
end)

local function buildList()
	buildGen += 1
	pageRows = {}
	tiles = {}
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end

	refreshAvailability()
	local found = 0
	for _, rec in ipairs(ordered) do
		if discovered[rec.E.Name] then found += 1 end
	end

	local source = catchableOnly and orderedLive or ordered

	counter.Text = ("%d CATCHABLE  /  %d KNOWN      \u{00B7}      %d FOUND")
		:format(LIVE_COUNT, TOTAL_COUNT, found)
	pageLabel.Text = ("%d SHOWN"):format(#source)
	filterLabel.Text = catchableOnly
		and ("CATCHABLE ONLY (%d)"):format(LIVE_COUNT)
		or ("SHOWING ALL (%d)"):format(TOTAL_COUNT)
	UITheme.setColors(filterBtn,
		catchableOnly and CF.pine1 or CF.wood1,
		catchableOnly and CF.pine2 or CF.wood2)

	list.CanvasPosition = Vector2.new(0, 0)
	gridCols = math.max(1, math.floor((list.AbsoluteSize.X + CELL_PAD) / (CELL_W + CELL_PAD)))

	for i, rec in ipairs(source) do
		local tier, e = rec.Tier, rec.E
		local known = discovered[e.Name] == true
		local av = availabilityOf(e.Name)

		-- rarity colour still carries availability: warm = catchable, cold = unreleased,
		-- berry = vaulted and never coming back
		local accent
		if known then
			accent = (av == AV_VAULTED) and tier.Color:Lerp(CF.berry1, 0.45) or tier.Color
		elseif av == AV_LIVE then
			accent = tier.Color:Lerp(Color3.fromRGB(104, 92, 82), 0.5)
		elseif av == AV_VAULTED then
			accent = tier.Color:Lerp(CF.berry2, 0.6)
		else
			accent = tier.Color:Lerp(Color3.fromRGB(66, 74, 88), 0.78)
		end

		local tile = Instance.new("Frame")
		tile.Name = "Tile" .. i
		tile.Size = UDim2.fromOffset(CELL_W, CELL_H)
		tile.LayoutOrder = i
		tile.BackgroundColor3 = known and Color3.fromRGB(46, 44, 52) or Color3.fromRGB(30, 29, 35)
		tile.BorderSizePixel = 0
		tile.ClipsDescendants = true
		tile.ZIndex = 11
		tile.Parent = list
		UITheme.corner(tile, 12)
		UITheme.ink(tile, 3)

		-- tier wash behind the silhouette, so the grid still reads by rarity at a glance
		local wash = Instance.new("Frame")
		wash.Size = UDim2.fromScale(1, 1)
		wash.BackgroundColor3 = accent
		wash.BackgroundTransparency = known and 0.72 or 0.86
		wash.BorderSizePixel = 0
		wash.ZIndex = 11
		wash.Parent = tile
		UITheme.corner(wash, 12)

		-- the viewport goes here later; kept empty until the tile scrolls into view
		local holder = Instance.new("Frame")
		holder.Name = "Thumb"
		holder.Size = UDim2.new(1, -10, 0, CELL_H - 58)
		holder.Position = UDim2.new(0, 5, 0, 4)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 12
		holder.Parent = tile

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -10, 0, 30)
		nameLbl.Position = UDim2.new(0, 5, 1, -52)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = FONT
		nameLbl.TextSize = 15
		nameLbl.TextScaled = true
		nameLbl.TextColor3 = known and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(176, 172, 184)
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Text = known and e.Name or "? ? ?"
		nameLbl.TextWrapped = true
		nameLbl.ZIndex = 14
		nameLbl.Parent = tile
		local nameCap = Instance.new("UITextSizeConstraint")
		nameCap.MaxTextSize = 15
		nameCap.MinTextSize = 10   -- floor it: below this a long name is unreadable anyway
		nameCap.Parent = nameLbl
		UITheme.inkText(nameLbl, 2.4)

		local rarLbl = Instance.new("TextLabel")
		rarLbl.Size = UDim2.new(1, -10, 0, 20)
		rarLbl.Position = UDim2.new(0, 5, 1, -22)
		rarLbl.BackgroundTransparency = 1
		rarLbl.Font = FONT
		rarLbl.TextSize = 14
		rarLbl.TextScaled = true
		rarLbl.TextColor3 = accent
		rarLbl.Text = string.upper(tier.Name)
		local rarCap = Instance.new("UITextSizeConstraint")
		rarCap.MaxTextSize = 14
		rarCap.Parent = rarLbl
		rarLbl.ZIndex = 14
		rarLbl.Parent = tile
		UITheme.inkText(rarLbl, 2.4)

		tiles[i] = { frame = tile, holder = holder, rec = rec, live = false }
	end

	-- populate whatever is on screen right now
	task.defer(updateVisible)
end

---------------------------------------------------------------- wiring
local function setOpen(open)
	frame.Visible = open
	if open then
		local shop = gui:FindFirstChild("ShopFrame")
		local sell = gui:FindFirstChild("SellFrame")
		if shop then shop.Visible = false end
		if sell then sell.Visible = false end
		refreshSupplySnap()   -- cap badges: lazy, throttled to one fetch a minute
		buildList()
	end
end

openBtn.Activated:Connect(function() setOpen(not frame.Visible) end)
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

prevBtn.MouseButton1Click:Connect(function()
	if page > 1 then
		page -= 1
		buildList()
	end
end)

nextBtn.MouseButton1Click:Connect(function()
	local source = catchableOnly and orderedLive or ordered
	if page < math.max(1, math.ceil(#source / PAGE_SIZE)) then
		page += 1
		buildList()
	end
end)

filterBtn.MouseButton1Click:Connect(function()
	catchableOnly = not catchableOnly
	page = 1   -- page 4 of the full roster is nowhere near page 4 of the live one
	buildList()
end)

local function applySnapshot(snap)
	if typeof(snap) ~= "table" then return end
	local changed = false
	if snap.Discovered then
		discovered = snap.Discovered
		changed = true
	end
	if snap.Brainrots then
		-- serials live on the player's own copies, so the value line needs the
		-- inventory as well as the discovery set
		recomputeOwned(snap.Brainrots)
		changed = true
	end
	if changed and frame.Visible then buildList() end
end

task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok then applySnapshot(snap) end
end)
remotes.DataUpdated.OnClientEvent:Connect(applySnapshot)

-- Exists counts and camp prices move while the panel is open, and a class whose
-- registry was cold on the first ask usually answers on the second. This poll is
-- a no-op whenever the panel is shut or the page is fully cached, so it costs
-- nothing in the common case.
task.spawn(function()
	while true do
		task.wait(12)
		if frame.Visible then fetchStats() end
	end
end)

buildList()
