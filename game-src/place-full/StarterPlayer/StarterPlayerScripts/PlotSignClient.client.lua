-- PlotSignClient -- renders every pixel of the camp board. (BUILD SPEC v2 §7.1)
--
-- Ownership split: the SERVER (PlotBoardHandler) owns the physical parts, the LikePrompt and
-- all like authority; this CLIENT owns all three SurfaceGuis and their children. A SurfaceGui
-- on real wood reads as scenery and holds its size at every distance -- the old 36-stud
-- camera-facing billboard is exactly why the previous sign felt like HUD spam.
--
-- State arrives as ATTRIBUTES on the plot Model (replicated for free). No per-plot remote,
-- no per-tick string write. EVERY attribute read is defaulted at the read site: ClaimPlotFor
-- writes OwnerUserId before Claimed, and formatShort(nil) errors on its first line.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local plotsFolder = Workspace:WaitForChild("PlayerBases")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local P = UITheme.Palette

local likeRemote = remotes:WaitForChild("LikePlot", 10)
local likeResult = remotes:WaitForChild("LikeResult", 10)

local C = Color3.fromRGB
local MAXDIST = 200         -- board AND plaque share this; a mismatch shows a blank square

-- The nine local copies this file warned about are now one module. NumberFormat.Short
-- is nil-safe, so the "formatShort(nil) errors on its first line" hazard noted above
-- is handled inside the module rather than at each read site.
local formatShort = require(ReplicatedStorage.Modules.NumberFormat).Short
local function cash(n) return "$" .. formatShort(n) end

-- ===== data plumbing =====
-- PlotSignClient touches neither DataUpdated nor GetInitialData today, and ClientMain's `state`
-- is a file-local, so this script must fetch LikedPlayers itself.
local myLikes = {}
local renderAll   -- forward declaration

local function ingest(snap)
	if type(snap) ~= "table" then return end      -- Main:33 CAN return nil after its 5 s poll
	if type(snap.LikedPlayers) == "table" then myLikes = snap.LikedPlayers end
	if renderAll then renderAll() end
end

-- ===== gui construction =====
local function newSurface(parent, name, face, active)
	local sg = Instance.new("SurfaceGui")
	sg.Name = name
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(550, 300)
	sg.LightInfluence = 0
	sg.AlwaysOnTop = false        -- U6: a physical sign may be occluded; never fake it to the front
	sg.MaxDistance = MAXDIST
	sg.ZOffset = 0
	if active then sg.Active = true end
	sg.Parent = parent
	return sg
end

-- Header + EarnedCard tree, shared by the front and back faces.
local function buildBoardFace(sg, isBack)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Position = UDim2.new(0, 0, 0, 0)
	header.Size = UDim2.new(1, 0, 0, 86)
	header.BackgroundColor3 = C(255, 255, 255)
	header.BorderSizePixel = 0
	header.Parent = sg
	local hg = Instance.new("UIGradient")
	hg.Rotation = 90
	hg.Color = ColorSequence.new(C(226, 138, 54), C(186, 96, 30))   -- ember
	hg.Parent = header
	local hs = Instance.new("UIStroke")
	hs.Color = C(74, 36, 12); hs.Thickness = 3; hs.Parent = header
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 10); hc.Parent = header
	local hp = Instance.new("UIPadding")
	hp.PaddingLeft = UDim.new(0, 12); hp.PaddingRight = UDim.new(0, 12); hp.Parent = header

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextSize = 50
	nameLabel.TextScaled = false
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextColor3 = C(255, 246, 228)
	nameLabel.TextStrokeColor3 = C(74, 36, 12)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.Parent = header

	local card = Instance.new("Frame")
	card.Name = "EarnedCard"
	card.Position = UDim2.new(0, 16, 0, 104)
	card.Size = UDim2.new(0, 330, 0, 172)
	card.BackgroundColor3 = C(43, 31, 23)
	card.BackgroundTransparency = 0.15
	card.BorderSizePixel = 0
	card.Parent = sg
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 12); cc.Parent = card
	local cs = Instance.new("UIStroke"); cs.Color = C(28, 19, 13); cs.Thickness = 2; cs.Parent = card
	local cp = Instance.new("UIPadding")
	cp.PaddingLeft = UDim.new(0, 10); cp.PaddingRight = UDim.new(0, 10); cp.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "EarnedTitle"
	title.Size = UDim2.new(1, 0, 0, 42)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 40
	title.TextColor3 = C(206, 182, 148)
	title.Text = "TOTAL EARNED"
	title.Parent = card

	local value = Instance.new("TextLabel")
	value.Name = "EarnedValue"
	value.Position = UDim2.new(0, 0, 0, 44)
	value.Size = UDim2.new(1, 0, 0, 118)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBlack
	value.TextSize = 72
	value.TextScaled = true
	value.TextColor3 = P.cashText
	value.TextStrokeColor3 = C(16, 46, 24)
	value.TextStrokeTransparency = 0.3
	value.Text = ""      -- never leave Roblox's default "Label" behind a Visible=false flip
	value.Parent = card
	local vc = Instance.new("UITextSizeConstraint")
	vc.MaxTextSize = 72; vc.Parent = value

	local likeCount = Instance.new("TextLabel")
	likeCount.Name = "LikeCount"
	likeCount.BackgroundTransparency = 1
	likeCount.Font = Enum.Font.GothamBold
	likeCount.TextColor3 = C(255, 196, 196)
	likeCount.TextXAlignment = Enum.TextXAlignment.Center
	if isBack then
		-- no plaque on this face, so the counter is not dodging a cut-out
		likeCount.Position = UDim2.new(0, 360, 0, 120)
		likeCount.Size = UDim2.new(0, 180, 0, 40)
		likeCount.TextSize = 30
	else
		-- sits UNDER the physical plaque cut-out (plaque covers x 367.5->537.5, y 97.5->267.5)
		likeCount.Position = UDim2.new(0, 372, 0, 272)
		likeCount.Size = UDim2.new(0, 160, 0, 26)
		likeCount.TextSize = 22
	end
	likeCount.Parent = sg

	return { header = header, grad = hg, name = nameLabel, title = title, value = value, likeCount = likeCount }
end

local function buildLikeFace(plaque)
	local sg = newSurface(plaque, "LikeGui", Enum.NormalId.Front, true)
	sg.CanvasSize = Vector2.new(170, 170)

	local btn = Instance.new("TextButton")
	btn.Name = "Btn"
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.Text = ""
	btn.Parent = sg
	-- styleButton takes THREE args; it internally calls corner(btn, 9) and sets
	-- AutoButtonColor = true, so BOTH overrides must come AFTER it.
	UITheme.styleButton(btn, C(226, 84, 88), C(186, 46, 56))
	UITheme.corner(btn, 28)                 -- reuses the same UICorner instance
	btn.AutoButtonColor = false

	local heart = Instance.new("TextLabel")
	heart.Name = "Heart"
	heart.Position = UDim2.new(0, 0, 0, 0)
	heart.Size = UDim2.new(1, 0, 0, 95)
	heart.BackgroundTransparency = 1
	heart.TextSize = 74
	-- styleButton styles btn.Text, and Btn.Text is "" -- so the visible glyphs need their OWN stroke
	heart.TextStrokeColor3 = C(84, 18, 24)
	heart.TextStrokeTransparency = 0.25
	heart.Parent = btn

	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Position = UDim2.new(0, 0, 0, 95)
	count.Size = UDim2.new(1, 0, 0, 75)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamBlack
	count.TextSize = 44
	count.TextColor3 = C(255, 255, 255)
	count.TextStrokeTransparency = 0.4
	count.Parent = btn

	return { gui = sg, btn = btn, heart = heart, count = count }
end

-- ===== render =====
local cache = {}    -- [BoardPart] = entry

local function renderEntry(e)
	local plot = e.plot
	if not plot or plot.Parent == nil then return end

	-- EVERY read defaulted at the read site (spec 2.6 nil-default rule)
	local claimed = plot:GetAttribute("Claimed") == true
	local ownerId = plot:GetAttribute("OwnerUserId") or 0
	local ownerName = plot:GetAttribute("OwnerName") or ""
	local earned = plot:GetAttribute("TotalEarned") or 0
	local likes = plot:GetAttribute("PlotLikes") or 0

	local isMine = claimed and ownerId == player.UserId
	local liked = myLikes[tostring(ownerId)] == true

	for _, f in ipairs(e.faces) do
		if claimed then
			f.grad.Color = ColorSequence.new(C(226, 138, 54), C(186, 96, 30))
			f.name.Text = (ownerName ~= "" and ownerName or "Camper") .. "'s Camp"
			f.name.TextColor3 = C(255, 246, 228)
			f.title.Text = "TOTAL EARNED"
			f.title.Size = UDim2.new(1, 0, 0, 42)
			f.title.TextSize = 40
			f.value.Visible = true
			f.value.Text = cash(earned)
			f.likeCount.Text = likes == 1 and "1 like" or (likes .. " likes")
		else
			f.grad.Color = ColorSequence.new(P.gold1, P.gold2)
			f.name.Text = "AVAILABLE PLOT"
			f.name.TextColor3 = C(58, 38, 14)
			-- single centred line; claiming is Platform.Touched, and the board sits OUTSIDE
			-- the r-22 platform, so "walk up to claim" would be a lie
			f.title.Text = "STEP ONTO THE CAMP"
			f.title.Size = UDim2.new(1, 0, 1, 0)
			f.title.TextSize = 34
			f.value.Visible = false
			f.likeCount.Text = ""
		end
	end

	local L = e.like
	if L then
		local canLike = claimed and not isMine and not liked
		if not claimed then
			UITheme.setColors(L.btn, P.hudMuted1, P.hudMuted2)
			L.heart.Text = "\u{2665}"; L.heart.TextColor3 = C(210, 214, 224)
			L.count.Text = "\u{2014}"
		elseif isMine then
			UITheme.setColors(L.btn, P.hudMuted1, P.hudMuted2)
			L.heart.Text = "\u{2665}"; L.heart.TextColor3 = C(210, 214, 224)
			L.count.Text = tostring(likes)
		elseif liked then
			UITheme.setColors(L.btn, C(226, 84, 88), C(186, 46, 56))
			L.heart.Text = "\u{2665}"; L.heart.TextColor3 = C(255, 236, 236)
			L.count.Text = tostring(likes)
		else
			UITheme.setColors(L.btn, C(226, 84, 88), C(186, 46, 56))
			L.heart.Text = "\u{2661}"; L.heart.TextColor3 = C(255, 236, 236)
			L.count.Text = tostring(likes)
		end
		L.btn.Active = canLike

		-- Cosmetic only: client property writes do not replicate. Server-side
		-- PlotBoardHandler.TryLike is the real gate.
		if e.prompt then e.prompt.Enabled = canLike end
	end
end

function renderAll()
	for _, e in pairs(cache) do renderEntry(e) end
end

local ATTRS = { "Claimed", "OwnerUserId", "OwnerName", "TotalEarned", "PlotLikes" }

local function ensurePlot(plot)
	if not plot:IsA("Model") then return end
	local boardModel = plot:FindFirstChild("PlotBoard")
	local board = boardModel and boardModel:FindFirstChild("Board")
	local plaque = boardModel and boardModel:FindFirstChild("LikePlaque")
	if not board then return end

	local e = cache[board]
	if e and e.plaque == plaque and board:FindFirstChild("BoardGui") then
		renderEntry(e)
		return
	end

	if e then
		for _, c in ipairs(e.conns) do c:Disconnect() end
	end

	e = { plot = plot, board = board, plaque = plaque, faces = {}, conns = {} }

	local old = board:FindFirstChild("BoardGui"); if old then old:Destroy() end
	local oldB = board:FindFirstChild("BackGui"); if oldB then oldB:Destroy() end
	table.insert(e.faces, buildBoardFace(newSurface(board, "BoardGui", Enum.NormalId.Front, false), false))
	table.insert(e.faces, buildBoardFace(newSurface(board, "BackGui", Enum.NormalId.Back, false), true))

	if plaque then
		local oldL = plaque:FindFirstChild("LikeGui"); if oldL then oldL:Destroy() end
		e.like = buildLikeFace(plaque)
		e.prompt = plaque:FindFirstChild("LikePrompt")
		e.like.btn.MouseButton1Click:Connect(function()
			if not e.like.btn.Active then return end
			if likeRemote then likeRemote:FireServer(plot:GetAttribute("PlotIndex")) end
		end)
	end

	for _, a in ipairs(ATTRS) do
		table.insert(e.conns, plot:GetAttributeChangedSignal(a):Connect(function()
			renderEntry(e)
		end))
	end

	cache[board] = e
	renderEntry(e)
end

-- ===== like feedback: ONE shared path for both inputs, gated on the server's answer =====
-- No optimistic pop. On every rejection PlotLikes does NOT change, so an optimistic "+1"
-- would show forever on a self-like and hide all five server guards.
local function entryForIndex(idx)
	for _, e in pairs(cache) do
		if e.plot and e.plot:GetAttribute("PlotIndex") == idx then return e end
	end
	return nil
end

local function playLikeFeedback(ok, plotIndex)
	local e = entryForIndex(plotIndex)
	if not e or not e.plaque then return end
	local plaque = e.plaque

	if ok then
		local base = plaque.Size
		TweenService:Create(plaque, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = base * 1.12 }):Play()
		task.delay(0.09, function()
			if plaque.Parent then
				TweenService:Create(plaque, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Size = base }):Play()
			end
		end)

		if e.like then
			local pop = Instance.new("TextLabel")
			pop.Name = "Pop"
			pop.BackgroundTransparency = 1
			pop.Size = UDim2.new(1, 0, 0, 60)
			pop.Position = UDim2.new(0, 0, 0, 40)
			pop.Font = Enum.Font.GothamBlack
			pop.TextSize = 52
			pop.TextColor3 = C(255, 236, 236)
			pop.TextStrokeColor3 = C(84, 18, 24)
			pop.TextStrokeTransparency = 0.2
			pop.Text = "+1"
			pop.Parent = e.like.gui
			TweenService:Create(pop, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, 0, 0, -20), TextTransparency = 1, TextStrokeTransparency = 1,
			}):Play()
			Debris:AddItem(pop, 0.8)
		end

		local s = Instance.new("Sound")
		s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		s.Volume = 0.5
		s.Parent = plaque
		s:Play()
		Debris:AddItem(s, 2)
	else
		if e.like then
			local stroke
			for _, s in ipairs(e.like.btn:GetChildren()) do
				if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then stroke = s end
			end
			if stroke then
				local was = stroke.Color
				stroke.Color = C(255, 70, 70)
				task.delay(0.12, function()
					if stroke.Parent then stroke.Color = was end
				end)
			end
		end
	end
end

if likeResult then
	likeResult.OnClientEvent:Connect(function(res)
		if type(res) ~= "table" then return end
		playLikeFeedback(res.Success == true, res.PlotIndex)
	end)
end

-- The primary input is the server-owned LikePrompt; no local pop here, the reply drives it.
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who == player and prompt.Name == "LikePrompt" then
		-- intentionally empty: feedback waits for LikeResult (~50-100 ms, well under the
		-- 350 ms HoldDuration the player already spent)
	end
end)

-- ===== reconcile + teardown (streaming) =====
local function reconcile()
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		ensurePlot(plot)
	end
	-- teardown: with StreamingEnabled the per-plot cache would otherwise accumulate
	-- references to destroyed instances over a long session
	for board, e in pairs(cache) do
		if board.Parent == nil then
			for _, c in ipairs(e.conns) do c:Disconnect() end
			cache[board] = nil
		end
	end
end

plotsFolder.ChildAdded:Connect(function()
	task.wait()
	reconcile()
end)

task.spawn(function()
	local ok, snap = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok then ingest(snap) end
end)
if remotes:FindFirstChild("DataUpdated") then
	-- fires for the LIKER and the OWNER; must not assume it is about the local player's plot
	remotes.DataUpdated.OnClientEvent:Connect(ingest)
end

reconcile()
task.spawn(function()
	while true do
		task.wait(0.5)
		reconcile()
	end
end)
