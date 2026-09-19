-- LeaderboardBoards: the three physical boards in the lodge plaza.
--
-- Presentation only. LeaderboardHandler owns the data and calls back here after every
-- fetch; this module knows nothing about DataStores and vice versa.
--
-- Built at RUNTIME, not authored into the place. Rebuilding on every server start means
-- the geometry can never drift from the code, and Build() destroys the old folder first
-- so it is safe to call twice.
--
-- Server-built SurfaceGuis, which deviates from PlotSignClient's "server owns the parts,
-- client owns the GUI" split. That split exists because six plot signs update every few
-- ticks with per-plot data; these repaint once a minute with identical content for
-- everyone, so the replication is trivial and one server-side source of truth is both
-- simpler and guaranteed visible even if a client script fails.

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local Leaderboard = require(ServerScriptService.Modules.LeaderboardHandler)

local M = {}
local C = Color3.fromRGB

--=============================== placement ================================--
-- The lodge interior is clear across its full width between z=-220 and z=-240, and this
-- row faces the 23-stud doorway at (0, -208): you see all three the moment you walk in.
-- Bump this whenever the layout below changes. Build() rebuilds any folder stamped with
-- an older version, but LEAVES a current one alone -- which is what lets the boards be
-- authored into the place and dragged around in Studio without a server start
-- snapping them back to these coordinates.
local LAYOUT_VERSION = 3

local BOARD_Z      = -240
local FLOOR_Y      = 5.2      -- PlazaFloor top (centre 4.7, 1.0 thick)
local BOARD_W      = 10       -- 1.5x smaller than the 15x14 first pass
local BOARD_H      = 9.33
local SLOTS        = { -14, 0, 14 }   -- 14 apart, just clear of the 13.4-wide cap
local PPS          = 50       -- SurfaceGui pixels per stud -> 500 x 466 canvas

local ROWS_TOTAL   = 50
local ROW_PX       = 34       -- taller rows: the text got bigger, the board got smaller
local TEXT_PX      = 22       -- was 16

--================================= palette ================================--
local WOOD_DARK  = C(104, 66, 38)
local WOOD_MID   = C(170, 116, 68)
local PANEL_TOP  = C(40, 62, 42)
local PANEL_BOT  = C(17, 29, 20)
local INK        = C(12, 9, 7)
local CREAM      = C(255, 242, 219)
local MUTED      = C(198, 176, 152)
local AMBER1     = C(255, 200, 96)
local RANK_COLOR = {
	[1] = C(255, 214, 92),    -- gold
	[2] = C(214, 222, 232),   -- silver
	[3] = C(226, 152, 92),    -- bronze
}

--============================== build helpers =============================--
local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Wood
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = false
	p.Parent = parent
	return p
end

local function label(parent, name, size, pos, text, color, textSize, align)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color
	l.TextSize = textSize
	l.Font = Enum.Font.GothamBold
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextStrokeColor3 = INK
	l.TextStrokeTransparency = 0.55
	l.RichText = false          -- names are user content; never let one inject markup
	l.Parent = parent
	return l
end

--============================== one board =================================--
-- Returns { Rows = { {rank=,name=,value=}, ... } } so Paint can address the labels
-- without walking the tree every refresh.
local function buildBoard(parent, board, x)
	local model = Instance.new("Model")
	model.Name = "Leaderboard_" .. board.Id
	model.Parent = parent

	-- Rotated a half turn so the part's FRONT face (local -Z) points to world +Z, at the
	-- doorway. Using NormalId.Front on a turned part is far easier to reason about later
	-- than leaving it square and hanging the GUI off the Back face.
	local facing = CFrame.new(x, 0, BOARD_Z) * CFrame.Angles(0, math.rad(180), 0)
	local centreY = FLOOR_Y + BOARD_H / 2

	local panel = part(model, "Panel", Vector3.new(BOARD_W, BOARD_H, 0.6),
		facing * CFrame.new(0, centreY, 0), PANEL_BOT, Enum.Material.SmoothPlastic)
	-- MUST be queryable. SurfaceGui input is delivered by raycasting the mouse against
	-- the part; with CanQuery off the ray passes straight through and the scroll wheel
	-- does nothing. The rest of the frame stays non-queryable.
	panel.CanQuery = true
	model.PrimaryPart = panel

	-- frame: posts, cap, plinth
	local postX = BOARD_W / 2 + 0.5
	for _, sx in ipairs({ -1, 1 }) do
		part(model, "Post", Vector3.new(1.0, BOARD_H + 2.4, 1.0),
			facing * CFrame.new(sx * postX, FLOOR_Y + (BOARD_H + 2.4) / 2 - 0.6, 0), WOOD_DARK)
	end
	part(model, "Cap", Vector3.new(BOARD_W + 3.4, 1.1, 1.6),
		facing * CFrame.new(0, FLOOR_Y + BOARD_H + 1.3, 0), WOOD_MID)
	part(model, "Plinth", Vector3.new(BOARD_W + 3.4, 0.8, 2.0),
		facing * CFrame.new(0, FLOOR_Y + 0.4, 0), WOOD_MID)
	part(model, "Backer", Vector3.new(BOARD_W + 0.6, BOARD_H + 0.6, 0.3),
		facing * CFrame.new(0, centreY, 0.4), WOOD_DARK)

	--------------------------------------------------------------- surface gui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = panel

	local W, H = BOARD_W * PPS, BOARD_H * PPS   -- 500 x 466

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = PANEL_TOP
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(PANEL_TOP, PANEL_BOT)
	grad.Rotation = 90
	grad.Parent = bg

	-- title
	local TITLE_H = 46
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
	titleBar.BackgroundColor3 = C(28, 44, 30)
	titleBar.BorderSizePixel = 0
	titleBar.Parent = bg
	local t = label(titleBar, "Title", UDim2.new(1, -12, 1, 0), UDim2.new(0, 6, 0, 0),
		board.Icon .. "  " .. board.Title, AMBER1, 24, Enum.TextXAlignment.Center)
	t.TextScaled = true      -- "MOST BRAINROTS CAUGHT" would clip a 500px bar otherwise
	t.TextWrapped = false

	local underline = Instance.new("Frame")
	underline.Size = UDim2.new(1, 0, 0, 3)
	underline.Position = UDim2.new(0, 0, 0, TITLE_H)
	underline.BackgroundColor3 = AMBER1
	underline.BorderSizePixel = 0
	underline.Parent = bg

	local FOOT_H = 18
	local listTop = TITLE_H + 5
	local listH = H - listTop - FOOT_H

	-- SCROLLING list, single column. At 22px text on a 500px board only ~12 rows fit,
	-- so the other 38 live below the fold. Roblox routes mouse wheel and touch drag to a
	-- SurfaceGui when the cursor is over the surface -- which is why the Panel part must
	-- keep CanQuery on, or the ray never reaches it and the wheel does nothing.
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 0, listH)
	list.Position = UDim2.new(0, 0, 0, listTop)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Active = true
	list.ScrollingEnabled = true
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = AMBER1
	list.ScrollBarImageTransparency = 0.35
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.CanvasSize = UDim2.new(0, 0, 0, ROWS_TOTAL * ROW_PX)
	list.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	list.Parent = bg

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 0)
	layout.Parent = list

	local rows = {}
	for i = 1, ROWS_TOTAL do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -10, 0, ROW_PX)
		row.BackgroundColor3 = C(255, 255, 255)
		-- faint zebra banding; 50 unbroken lines of text is unreadable at a glance
		row.BackgroundTransparency = (i % 2 == 0) and 0.94 or 1
		row.BorderSizePixel = 0
		row.Visible = false
		row.Parent = list

		rows[i] = {
			frame = row,
			rank  = label(row, "Rank", UDim2.new(0, 58, 1, 0), UDim2.new(0, 8, 0, 0),
				"", MUTED, TEXT_PX, Enum.TextXAlignment.Left),
			-- "PlayerName", not "Name": a child called Name is shadowed by Instance.Name,
			-- so row.Name would return the string "Row7" instead of the label.
			name  = label(row, "PlayerName", UDim2.new(1, -216, 1, 0), UDim2.new(0, 70, 0, 0),
				"", CREAM, TEXT_PX, Enum.TextXAlignment.Left),
			value = label(row, "Value", UDim2.new(0, 140, 1, 0), UDim2.new(1, -146, 0, 0),
				"", AMBER1, TEXT_PX, Enum.TextXAlignment.Right),
		}
	end

	-- an empty-state line, hidden as soon as real rows arrive
	local empty = label(bg, "Empty", UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, listTop + 40),
		"no data yet", MUTED, 22, Enum.TextXAlignment.Center)

	-- footer stamp so players can tell a stale board from an empty one
	local foot = label(bg, "Updated", UDim2.new(1, -12, 0, FOOT_H), UDim2.new(0, 6, 1, -FOOT_H),
		"", MUTED, 13, Enum.TextXAlignment.Right)

	return { Rows = rows, Empty = empty, Foot = foot, List = list, Board = board }
end

--================================= painting ===============================--
local built = {}   -- [boardId] = the table returned by buildBoard (the valley set)
-- Every SET of boards in the place: { [1] = {[boardId] = handle}, ... }. World 2
-- has its own copy of the three boards, and a refresh has to reach both -- the
-- standings are global, so a board showing stale rows because it is in the other
-- world would just look broken.
local sites = {}

local function paintOne(b, data)
	if not b then return end
	local n = #data
	b.Empty.Visible = (n == 0)
	-- Send the list back to rank 1 on a refresh. Leaving a player parked at rank 40 while
	-- the rows underneath them change identity is worse than losing their scroll position.
	if b.List then b.List.CanvasPosition = Vector2.new(0, 0) end
	for i, row in ipairs(b.Rows) do
		local e = data[i]
		if e then
			row.frame.Visible = true
			row.rank.Text = "#" .. e.Rank
			row.rank.TextColor3 = RANK_COLOR[e.Rank] or MUTED
			row.name.Text = e.Name
			row.name.TextColor3 = RANK_COLOR[e.Rank] or CREAM
			row.value.Text = Leaderboard.FormatValue(b.Board.Format, e.Value)
		else
			row.frame.Visible = false
		end
	end
	b.Count = n
	M.TickFooter(b)
end

function M.Paint(boardId, data)
	for _, set in ipairs(sites) do
		paintOne(set[boardId], data)
	end
end

-- Footer carries the live countdown, so it is redrawn every second rather than only on a
-- fetch. Split out so both the ticker and Paint can call it.
function M.TickFooter(b)
	if not b or not b.Foot then return end
	local secs = math.ceil(Leaderboard.SecondsUntilRefresh())
	if secs < 0 then secs = 0 end
	local left = (b.Count and b.Count > 0) and ("top " .. b.Count) or "waiting for data"
	b.Foot.Text = ("%s  \u{2022}  next update %d:%02d"):format(left, math.floor(secs / 60), secs % 60)
end

-- Adopt boards that are already in the place instead of rebuilding them, so a folder
-- authored in Studio (and dragged wherever the owner likes) survives a server start.
-- Returns nil if anything is missing or renamed, in which case the caller rebuilds.
local function bindExisting(folder)
	local found = {}
	for _, board in ipairs(Leaderboard.BOARDS) do
		local model = folder:FindFirstChild("Leaderboard_" .. board.Id)
		local panel = model and (model.PrimaryPart or model:FindFirstChild("Panel"))
		local gui = panel and panel:FindFirstChildOfClass("SurfaceGui")
		local bg = gui and gui:FindFirstChildOfClass("Frame")
		local list = bg and bg:FindFirstChild("List")
		if not (bg and list) then return nil end

		local rows = {}
		for i = 1, ROWS_TOTAL do
			local r = list:FindFirstChild("Row" .. i)
			local rank = r and r:FindFirstChild("Rank")
			local nm = r and r:FindFirstChild("PlayerName")
			local val = r and r:FindFirstChild("Value")
			if not (rank and nm and val) then return nil end
			rows[i] = { frame = r, rank = rank, name = nm, value = val }
		end

		if panel then panel.CanQuery = true end   -- older builds had this off
		found[board.Id] = {
			Rows = rows,
			Empty = bg:FindFirstChild("Empty"),
			Foot = bg:FindFirstChild("Updated"),
			List = list,
			Board = board,
		}
	end
	return found
end

--============================== world 2 copy ==============================--
-- The tundra set is a CLONE of the valley set rather than a second call to
-- buildBoard: the three boards sit in a hand-placed arc that someone dragged into
-- position in Studio, and cloning keeps that arrangement exactly. Only the whole
-- group's position and facing change.
-- World 2 blockout (2026-09-19): the -X side of the Avenue's mouth, just north of the
-- Warming Circle. The daily wheel sits opposite at -7955 (see WheelBoard.SITES), so the
-- two flank the walk up to the camps.
--
-- Aiming note: the three boards are authored as an ARC, which converges on a point
-- a little in front of the set. Pointing the GROUP at the path leaves the two outer
-- boards ~33 degrees off it. placeTundraSet therefore turns each board
-- INDIVIDUALLY to face the walkway, so all three read straight on from the path.
local TUNDRA_AT     = Vector3.new(-8045, 2001.8, -8128)
local TUNDRA_LOOKAT = Vector3.new(-8000, 2001.8, -8128)

local function groupCentre(folder)
	local sum, n = Vector3.zero, 0
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then sum += m:GetPivot().Position; n += 1 end
	end
	return (n > 0) and (sum / n) or nil, n
end

-- A Folder is not a PVInstance, so the group is moved by transforming each board
-- model through the same world-space CFrame.
local function transformFolder(folder, transform)
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then m:PivotTo(transform * m:GetPivot()) end
	end
end

local function placeTundraSet(folder)
	local centre = groupCentre(folder)
	if not centre then return end
	transformFolder(folder, CFrame.new(TUNDRA_AT - centre))

	-- now yaw the whole group about its new centre so the boards face the walk
	local first
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then first = m; break end
	end
	local panel = first and (first.PrimaryPart or first:FindFirstChild("Panel"))
	if not panel then return end
	local cur = panel.CFrame.LookVector
	cur = Vector3.new(cur.X, 0, cur.Z)
	local want = TUNDRA_LOOKAT - TUNDRA_AT
	want = Vector3.new(want.X, 0, want.Z)
	if cur.Magnitude < 1e-3 or want.Magnitude < 1e-3 then return end
	cur, want = cur.Unit, want.Unit
	local yaw = math.atan2(want.X, want.Z) - math.atan2(cur.X, cur.Z)
	transformFolder(folder, CFrame.new(TUNDRA_AT) * CFrame.Angles(0, yaw, 0) * CFrame.new(-TUNDRA_AT))

	-- Then square each board up individually against the walkway. Without this the
	-- arc's outer two boards sit ~33 degrees off and read edge-on as you walk past.
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			local p = m.PrimaryPart or m:FindFirstChild("Panel")
			if p then
				local pivot = m:GetPivot()
				local c = p.CFrame.LookVector; c = Vector3.new(c.X, 0, c.Z)
				local t = Vector3.new(TUNDRA_LOOKAT.X - pivot.X, 0, 0)
				if c.Magnitude > 1e-4 and t.Magnitude > 1e-4 then
					c, t = c.Unit, t.Unit
					m:PivotTo(pivot * CFrame.Angles(0, math.atan2(t.X, t.Z) - math.atan2(c.X, c.Z), 0))
				end
			end
		end
	end

	-- SEAT THE GROUP. The move above lines up the group's CENTRE with TUNDRA_AT, which
	-- buries the boards by however far their bases sit below that centre (4.1 studs,
	-- since the valley set is built on a floor at Y 5.2 with its centre at 9.3). Drop
	-- the whole group onto whatever floor is actually underneath instead of trusting a
	-- hardcoded Y.
	local lowest = math.huge
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") then
			local cf, size = m:GetBoundingBox()
			lowest = math.min(lowest, cf.Y - size.Y / 2)
		end
	end
	if lowest == math.huge then return end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local hit = Workspace:Raycast(Vector3.new(TUNDRA_AT.X, lowest + 12, TUNDRA_AT.Z), Vector3.new(0, -120, 0), params)
	if not hit then return end
	transformFolder(folder, CFrame.new(0, hit.Position.Y - lowest, 0))
end

local function buildTundraSet(gw, valleyFolder)
	local existing = gw:FindFirstChild("LeaderboardsTundra")
	if existing and existing:GetAttribute("LayoutVersion") == LAYOUT_VERSION then
		local bound = bindExisting(existing)
		if bound then return bound end     -- adopt whatever position it was left in
	end
	if existing then existing:Destroy() end
	local clone = valleyFolder:Clone()
	clone.Name = "LeaderboardsTundra"
	clone:SetAttribute("LayoutVersion", LAYOUT_VERSION)
	clone.Parent = gw
	placeTundraSet(clone)
	return bindExisting(clone)
end

-- force: rebuild at the coded coordinates even if a current-version folder exists
function M.Build(force)
	local gw = Workspace:FindFirstChild("GameWorld") or Workspace
	local existing = gw:FindFirstChild("Leaderboards")

	if existing and not force and existing:GetAttribute("LayoutVersion") == LAYOUT_VERSION then
		local bound = bindExisting(existing)
		if bound then
			built = bound
			sites = { bound }
			local tundra = buildTundraSet(gw, existing)
			if tundra then table.insert(sites, tundra) end
			return existing, "reused"
		end
	end

	if existing then existing:Destroy() end
	built = {}

	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder:SetAttribute("LayoutVersion", LAYOUT_VERSION)
	folder.Parent = gw

	for i, board in ipairs(Leaderboard.BOARDS) do
		built[board.Id] = buildBoard(folder, board, SLOTS[i] or (i - 2) * (BOARD_W + 4))
	end
	sites = { built }
	local tundra = buildTundraSet(gw, folder)
	if tundra then table.insert(sites, tundra) end
	return folder, "built"
end

function M.Init()
	M.Build()
	Leaderboard.OnUpdate(function(boardId, rows)
		M.Paint(boardId, rows)
	end)

	-- one-second countdown on every board, so players can see the refresh coming
	task.spawn(function()
		while true do
			for _, set in ipairs(sites) do
				for _, b in pairs(set) do
					M.TickFooter(b)
				end
			end
			task.wait(1)
		end
	end)

	print(("LeaderboardBoards online (%d set(s) of boards, refresh every %ds)")
		:format(#sites, Leaderboard.RefreshInterval()))
end

return M
