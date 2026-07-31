-- Campfire UI: prompt at YOUR campfire. Two rituals share this one panel --
--   FUSE  : 5 identical unplaced brainrots -> 1 at the next mutation tier
--           (none -> Golden -> Diamond -> Rainbow).
--   OFFER : burn ONE spare into the fire, forever, for a small PERMANENT luck
--           bonus (ReplicatedStorage.Modules.OfferingConfig).
-- Offering destroys an item and hands back nothing you can hold, so it is gated
-- behind a confirm panel that names the EXACT brainrot the fire will eat.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fusionRemote = remotes:WaitForChild("FusionRequest")
local offerRemote = remotes:WaitForChild("OfferBrainrot")
local modules = ReplicatedStorage:WaitForChild("Modules")
local Mutations = require(modules:WaitForChild("MutationConfig"))
local OfferingConfig = require(modules:WaitForChild("OfferingConfig"))
local UITheme = require(modules:WaitForChild("UITheme"))
local SideRail = require(modules:WaitForChild("SideRail"))
local P = UITheme.Palette
local CF = UITheme.Camp
local FONT = UITheme.Font
local BODY = Enum.Font.GothamMedium

-- re-tint an already-styled element's border stroke to solid black (campfire look)
local function blackRim(o, thick)
	for _, s in ipairs(o:GetChildren()) do
		if s:IsA("UIStroke") and s.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
			s.Color = CF.ink; s.Thickness = thick or 3; s.Transparency = 0
		end
	end
end

-- Must mirror FusionHandler's ladder exactly. Rainbow and Glitched no longer drop
-- from throwing at all, so fusion is the ONLY way to reach them -- if this table
-- falls behind the server's, that tier becomes unreachable in practice.
local NEXT_MUTATION = { [""] = "Golden", Golden = "Diamond", Diamond = "Rainbow", Rainbow = "Glitched" }
local FUSE_COUNT = 5
local CLOSE_RANGE = 18

local state = { Brainrots = {}, Offerings = 0 }
local campfire = nil

local gui = Instance.new("ScreenGui")
gui.Name = "FusionUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "FusionFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.Size = UDim2.fromOffset(520, 466)
frame.Visible = false
frame.ZIndex = 10
frame.Parent = gui
UITheme.campPanel(frame)
SideRail.registerPanel(frame)   -- single-open: closes rail panels, folds the rail away

-- carved-wood banner that overhangs the panel top
local ribbon, title = UITheme.ribbon(frame, "CAMPFIRE", 0.62)

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(1, -44, 0, 20)
hint.Position = UDim2.new(0, 22, 0, 46)
hint.Font = FONT
hint.TextSize = 14
hint.TextColor3 = CF.muted
hint.Text = ("\u{1F525}  Fuse %d spares \u{2192} next mutation  \u{00B7}  or OFFER one for luck"):format(FUSE_COUNT)
hint.ZIndex = 12
hint.Parent = frame
UITheme.inkText(hint, 1.8)

-- ---- camp luck strip: what OFFERING has bought you so far ----
local luckCard, luckOuter = UITheme.accentCard(frame, CF.amber1, 12)
luckOuter.Size = UDim2.new(1, -32, 0, 52)
luckOuter.Position = UDim2.new(0, 16, 0, 70)
luckOuter.ZIndex = 11
luckCard.ZIndex = 12

local luckValue = Instance.new("TextLabel")
luckValue.BackgroundTransparency = 1
luckValue.Size = UDim2.new(0, 250, 1, 0)
luckValue.Position = UDim2.new(0, 14, 0, 0)
luckValue.Font = FONT
luckValue.TextSize = 19
luckValue.TextColor3 = CF.amber1
luckValue.TextXAlignment = Enum.TextXAlignment.Left
luckValue.Text = "\u{1F525} CAMP LUCK  \u{00D7}1.00"
luckValue.ZIndex = luckCard.ZIndex + 2
luckValue.Parent = luckCard
UITheme.inkText(luckValue, 2.6)

local luckNext = Instance.new("TextLabel")
luckNext.BackgroundTransparency = 1
luckNext.AnchorPoint = Vector2.new(1, 0.5)
luckNext.Size = UDim2.new(0, 200, 1, -8)
luckNext.Position = UDim2.new(1, -14, 0.5, 0)
luckNext.Font = BODY
luckNext.TextSize = 12
luckNext.TextColor3 = CF.muted
luckNext.TextXAlignment = Enum.TextXAlignment.Right
luckNext.TextWrapped = true
luckNext.Text = ""
luckNext.ZIndex = luckCard.ZIndex + 2
luckNext.Parent = luckCard
UITheme.inkText(luckNext, 1.6)

local function updateLuck()
	local n = state.Offerings or 0
	local mult = OfferingConfig.LuckMult(n)
	luckValue.Text = ("\u{1F525} CAMP LUCK  \u{00D7}%.2f"):format(mult)
	if mult >= 1 + OfferingConfig.MAX_BONUS - 0.0001 then
		luckNext.Text = ("MAXED OUT  \u{00B7}  %d offered"):format(n)
	else
		luckNext.Text = ("+1%% luck after %d more\n%d offered so far"):format(OfferingConfig.NextStepAt(n), n)
	end
end
updateLuck()

local closeBtn = Instance.new("TextButton")
closeBtn.Parent = frame
UITheme.styleClose(closeBtn)
closeBtn.ZIndex = 18
closeBtn.TextSize = 18
blackRim(closeBtn, 3)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -32, 1, -148)
list.Position = UDim2.new(0, 16, 0, 132)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 11
list.Parent = frame
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = list

local emptyLabel = Instance.new("TextLabel")
emptyLabel.BackgroundTransparency = 1
emptyLabel.Size = UDim2.new(1, -80, 0, 44)
emptyLabel.Position = UDim2.new(0, 40, 0, 210)
emptyLabel.Font = BODY
emptyLabel.TextSize = 14
emptyLabel.TextColor3 = CF.muted
emptyLabel.TextWrapped = true
emptyLabel.Text = "Catch brainrots to fuse or offer them here!"
emptyLabel.Visible = false
emptyLabel.ZIndex = 13
emptyLabel.Parent = frame
UITheme.inkText(emptyLabel, 1.6)

local function mutLabel(mut)
	return (mut and mut ~= "") and (mut .. " ") or ""
end

-- ================= OFFER confirmation (destructive) =================
-- The server always burns the LEAST valuable unplaced copy of the name, so this
-- panel resolves the same target and names it out loud -- the player must never
-- be surprised about which brainrot the fire took.
local pendingOffer = nil

local scrim = Instance.new("Frame")
scrim.Name = "OfferConfirm"
scrim.Size = UDim2.fromScale(1, 1)
scrim.BackgroundColor3 = CF.ink
scrim.BackgroundTransparency = 0.35
scrim.BorderSizePixel = 0
scrim.Visible = false
scrim.ZIndex = 40
scrim.Parent = frame
UITheme.corner(scrim, 18)

local box = Instance.new("Frame")
box.AnchorPoint = Vector2.new(0.5, 0.5)
box.Position = UDim2.new(0.5, 0, 0.5, 0)
box.Size = UDim2.fromOffset(424, 250)
box.ZIndex = 41
box.Parent = scrim
UITheme.campPanel(box)

local warnTitle = Instance.new("TextLabel")
warnTitle.BackgroundTransparency = 1
warnTitle.Size = UDim2.new(1, -28, 0, 28)
warnTitle.Position = UDim2.new(0, 14, 0, 16)
warnTitle.Font = FONT
warnTitle.TextSize = 21
warnTitle.TextColor3 = P.red1
warnTitle.Text = "\u{1F525} BURN THIS FOREVER?"
warnTitle.ZIndex = box.ZIndex + 2
warnTitle.Parent = box
UITheme.inkText(warnTitle, 3)

local targetLabel = Instance.new("TextLabel")
targetLabel.BackgroundTransparency = 1
targetLabel.Size = UDim2.new(1, -28, 0, 26)
targetLabel.Position = UDim2.new(0, 14, 0, 50)
targetLabel.Font = FONT
targetLabel.TextSize = 19
targetLabel.TextColor3 = CF.cream
targetLabel.TextTruncate = Enum.TextTruncate.AtEnd
targetLabel.Text = ""
targetLabel.ZIndex = box.ZIndex + 2
targetLabel.Parent = box
UITheme.inkText(targetLabel, 2.8)

local warnBody = Instance.new("TextLabel")
warnBody.BackgroundTransparency = 1
warnBody.Size = UDim2.new(1, -36, 0, 48)
warnBody.Position = UDim2.new(0, 18, 0, 82)
warnBody.Font = BODY
warnBody.TextSize = 13
warnBody.TextColor3 = CF.muted
warnBody.TextWrapped = true
warnBody.Text = "It is DESTROYED. No cash back, no refund, and it can never be traded or sold. Brainrots on your pads are safe -- this only burns a spare."
warnBody.ZIndex = box.ZIndex + 2
warnBody.Parent = box
UITheme.inkText(warnBody, 1.6)

local gainLabel = Instance.new("TextLabel")
gainLabel.BackgroundTransparency = 1
gainLabel.Size = UDim2.new(1, -28, 0, 24)
gainLabel.Position = UDim2.new(0, 14, 0, 136)
gainLabel.Font = FONT
gainLabel.TextSize = 16
gainLabel.TextColor3 = CF.amber1
gainLabel.Text = ""
gainLabel.ZIndex = box.ZIndex + 2
gainLabel.Parent = box
UITheme.inkText(gainLabel, 2.2)

local keepBtn = Instance.new("TextButton")
keepBtn.AnchorPoint = Vector2.new(0, 1)
keepBtn.Position = UDim2.new(0, 18, 1, -16)
keepBtn.Size = UDim2.new(0, 180, 0, 44)
keepBtn.Text = "KEEP IT"
keepBtn.ZIndex = box.ZIndex + 2
keepBtn.Parent = box
UITheme.campButton(keepBtn, CF.pine1, CF.pine2)
keepBtn.TextSize = 18

local burnBtn = Instance.new("TextButton")
burnBtn.AnchorPoint = Vector2.new(1, 1)
burnBtn.Position = UDim2.new(1, -18, 1, -16)
burnBtn.Size = UDim2.new(0, 180, 0, 44)
burnBtn.Text = "\u{1F525} BURN IT"
burnBtn.ZIndex = box.ZIndex + 2
burnBtn.Parent = box
UITheme.campButton(burnBtn, P.red1, P.red2)
burnBtn.TextSize = 18

-- same rule the server uses: lowest Mutations.Mult unplaced copy of the name
local function offerTarget(name)
	local best, bestMult
	for _, e in ipairs(state.Brainrots) do
		if e.Name == name and e.PadIndex == nil then
			local m = Mutations.Mult(e.Mutation)
			if not bestMult or m < bestMult then best, bestMult = e, m end
		end
	end
	return best
end

local function openConfirm(name)
	if #state.Brainrots <= 1 then return end
	local target = offerTarget(name)
	if not target then return end
	local mut = target.Mutation or ""
	pendingOffer = { Name = target.Name, Mutation = mut }
	targetLabel.Text = mutLabel(mut) .. target.Name
	targetLabel.TextColor3 = Mutations.Color(mut ~= "" and mut or nil) or CF.cream
	local n = state.Offerings or 0
	gainLabel.Text = ("Camp luck  \u{00D7}%.2f  \u{2192}  \u{00D7}%.2f"):format(OfferingConfig.LuckMult(n), OfferingConfig.LuckMult(n + 1))
	scrim.Visible = true
end

keepBtn.MouseButton1Click:Connect(function()
	pendingOffer = nil
	scrim.Visible = false
end)

burnBtn.MouseButton1Click:Connect(function()
	local offer = pendingOffer
	pendingOffer = nil
	scrim.Visible = false
	if offer then offerRemote:FireServer(offer.Name, offer.Mutation) end
end)

local function rebuild()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end

	-- group unplaced by name+mutation
	local groups = {}
	for _, e in ipairs(state.Brainrots) do
		if e.PadIndex == nil then
			-- every unplaced group is listed now: a Rainbow copy cannot be fused
			-- but it CAN be offered, so hiding it would strand it in this panel.
			local mut = e.Mutation or ""
			local key = e.Name .. "|" .. mut
			groups[key] = groups[key] or { Name = e.Name, Mutation = mut, Count = 0 }
			groups[key].Count += 1
		end
	end

	local rows = {}
	for _, g in pairs(groups) do table.insert(rows, g) end
	table.sort(rows, function(a, b)
		local ra = NEXT_MUTATION[a.Mutation] ~= nil and a.Count >= FUSE_COUNT
		local rb = NEXT_MUTATION[b.Mutation] ~= nil and b.Count >= FUSE_COUNT
		if ra ~= rb then return ra end
		if a.Name ~= b.Name then return a.Name < b.Name end
		return a.Mutation < b.Mutation
	end)

	emptyLabel.Visible = #rows == 0

	for i, g in ipairs(rows) do
		local nextMut = NEXT_MUTATION[g.Mutation]
		local ready = nextMut ~= nil and g.Count >= FUSE_COUNT

		-- ONE accent per card: the mutation colour, carried through the card border,
		-- the title text and the sunburst -- so the tier still reads at a glance.
		local accent = Mutations.Color(g.Mutation ~= "" and g.Mutation or nil) or CF.cream

		local card, outer = UITheme.accentCard(list, accent, 14)
		outer.Size = UDim2.new(1, -10, 0, 98)
		outer.LayoutOrder = i
		outer.ZIndex = 11
		card.ZIndex = 12
		if not ready then card.BackgroundTransparency = 0.2 end

		-- icon tile: sunburst backdrop tinted by the mutation accent
		local icon = Instance.new("Frame")
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Size = UDim2.fromOffset(52, 52)
		icon.Position = UDim2.new(0, 10, 0.5, 0)
		icon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		icon.BorderSizePixel = 0
		icon.ClipsDescendants = true
		icon.ZIndex = card.ZIndex + 1
		icon.Parent = card
		UITheme.corner(icon, 10)
		UITheme.sunburst(icon, accent, 12)
		UITheme.ink(icon, 3)

		local glyph = Instance.new("TextLabel")
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.BackgroundTransparency = 1
		glyph.Font = FONT
		glyph.TextSize = 28
		glyph.Text = "\u{1F9E0}"
		glyph.ZIndex = icon.ZIndex + 3
		glyph.Parent = icon

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, -218, 0, 22)
		name.Position = UDim2.new(0, 70, 0, 22)
		name.Font = FONT
		name.TextSize = 17
		name.TextColor3 = accent
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = mutLabel(g.Mutation) .. g.Name
		name.ZIndex = card.ZIndex + 2
		name.Parent = card
		UITheme.inkText(name, 2.8)

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.new(1, -218, 0, 20)
		sub.Position = UDim2.new(0, 70, 0, 50)
		sub.Font = BODY
		sub.TextSize = 13
		sub.TextColor3 = ready and CF.cream or CF.muted
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		if nextMut then
			sub.Text = ("%d/%d  \u{2192}  %s (\u{00D7}%d cash)"):format(math.min(g.Count, FUSE_COUNT), FUSE_COUNT, nextMut, Mutations.Mult(nextMut))
		else
			sub.Text = ("%d spare  \u{00B7}  top mutation, can't fuse"):format(g.Count)
		end
		sub.ZIndex = card.ZIndex + 2
		sub.Parent = card
		UITheme.inkText(sub, 1.6)

		local btn = Instance.new("TextButton")
		btn.AnchorPoint = Vector2.new(1, 0)
		btn.Position = UDim2.new(1, -12, 0, 8)
		btn.Size = UDim2.new(0, 128, 0, 34)
		btn.Text = nextMut and (ready and "FUSE!" or ("%d/%d"):format(g.Count, FUSE_COUNT)) or "MAX TIER"
		btn.ZIndex = card.ZIndex + 2
		btn.Parent = card
		if ready then
			UITheme.campButton(btn, CF.ember1, CF.ember2)
			btn.MouseButton1Click:Connect(function()
				fusionRemote:FireServer(g.Name, g.Mutation)
			end)
		else
			UITheme.campButton(btn, CF.panelTop, CF.panelBot)
			btn.AutoButtonColor = false
		end
		btn.TextSize = 17

		-- OFFER sits under FUSE and is deliberately RED: fusing gives you a better
		-- brainrot back, offering gives you nothing you can hold. Opens a confirm.
		local canOffer = #state.Brainrots > 1
		local offerBtn = Instance.new("TextButton")
		offerBtn.AnchorPoint = Vector2.new(1, 1)
		offerBtn.Position = UDim2.new(1, -12, 1, -8)
		offerBtn.Size = UDim2.new(0, 128, 0, 34)
		offerBtn.Text = canOffer and "\u{1F525} OFFER" or "LAST ONE"
		offerBtn.ZIndex = card.ZIndex + 2
		offerBtn.Parent = card
		if canOffer then
			UITheme.campButton(offerBtn, P.red1, P.red2)
			offerBtn.MouseButton1Click:Connect(function()
				openConfirm(g.Name)
			end)
		else
			UITheme.campButton(offerBtn, CF.panelTop, CF.panelBot)
			offerBtn.AutoButtonColor = false
		end
		offerBtn.TextSize = 17
	end
end

closeBtn.MouseButton1Click:Connect(function()
	frame.Visible = false
	scrim.Visible = false
end)

-- success VFX at the campfire
fusionRemote.OnClientEvent:Connect(function(info)
	if frame.Visible then rebuild() end
	if not campfire then return end
	local burst = Instance.new("Part")
	burst.Shape = Enum.PartType.Ball
	burst.Size = Vector3.new(2, 2, 2)
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.Material = Enum.Material.Neon
	burst.Color = Mutations.Color(info and info.NewMutation) or Color3.fromRGB(255, 170, 60)
	burst.Transparency = 0.1
	burst.CFrame = CFrame.new(campfire.Position + Vector3.new(0, 2, 0))
	burst.Parent = Workspace
	TweenService:Create(burst, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(11, 11, 11),
		Transparency = 1,
	}):Play()
	game:GetService("Debris"):AddItem(burst, 0.9)
end)

-- offering VFX: an ember flare that rises off the fire and burns out, so a burn
-- reads as "gone up in smoke" rather than as a reward pop.
offerRemote.OnClientEvent:Connect(function(info)
	if typeof(info) == "table" and info.Offerings then state.Offerings = info.Offerings end
	updateLuck()
	if frame.Visible then rebuild() end
	if not campfire then return end
	local flare = Instance.new("Part")
	flare.Shape = Enum.PartType.Ball
	flare.Size = Vector3.new(1.6, 1.6, 1.6)
	flare.Anchored = true
	flare.CanCollide = false
	flare.CanQuery = false
	flare.Material = Enum.Material.Neon
	flare.Color = Color3.fromRGB(255, 138, 48)
	flare.Transparency = 0.05
	flare.CFrame = CFrame.new(campfire.Position + Vector3.new(0, 2, 0))
	flare.Parent = Workspace
	TweenService:Create(flare, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(5.5, 5.5, 5.5),
		CFrame = CFrame.new(campfire.Position + Vector3.new(0, 9, 0)),
		Transparency = 1,
	}):Play()
	game:GetService("Debris"):AddItem(flare, 1.1)
end)

-- keep data fresh
remotes.DataUpdated.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.Brainrots then state.Brainrots = data.Brainrots end
	if data.Offerings ~= nil then state.Offerings = data.Offerings end
	updateLuck()
	if frame.Visible then rebuild() end
end)
task.spawn(function()
	local ok, snapshot = pcall(function() return remotes.GetInitialData:InvokeServer() end)
	if ok and typeof(snapshot) == "table" then
		if snapshot.Brainrots then state.Brainrots = snapshot.Brainrots end
		if snapshot.Offerings ~= nil then state.Offerings = snapshot.Offerings end
		updateLuck()
		if frame.Visible then rebuild() end
	end
end)

-- The fuse/offer ritual is intentionally OFF at plot campfires for now. The whole
-- mechanic (this UI + FusionHandler/offer handler on the server) is kept intact so
-- it can be re-homed elsewhere later; set this flag back to true to restore the
-- plot campfire prompt exactly as before.
local ATTACH_TO_PLOT_CAMPFIRE = false

-- attach a LOCAL prompt to our own campfire once we own a plot
if ATTACH_TO_PLOT_CAMPFIRE then
task.spawn(function()
	local basesFolder = Workspace:WaitForChild("PlayerBases")
	while true do
		local myPlot = nil
		for _, plot in ipairs(basesFolder:GetChildren()) do
			if plot:GetAttribute("OwnerUserId") == player.UserId then
				myPlot = plot
				break
			end
		end
		local fire = myPlot and myPlot:FindFirstChild("Campfire", true)
		if fire ~= campfire then
			campfire = fire
			if campfire and not campfire:FindFirstChild("FusionPrompt") then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "FusionPrompt"
				prompt.ActionText = "Fuse / Offer"
				prompt.ObjectText = "\u{1F525} Campfire"
				prompt.HoldDuration = 0.35
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Parent = campfire
				prompt.Triggered:Connect(function()
					frame.Visible = not frame.Visible
					scrim.Visible = false
					if frame.Visible then rebuild() end
				end)
			end
		end
		task.wait(2)
	end
end)
end  -- ATTACH_TO_PLOT_CAMPFIRE guard

-- walk away -> close
RunService.Heartbeat:Connect(function()
	if not frame.Visible then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if campfire and hrp and (campfire.Position - hrp.Position).Magnitude > CLOSE_RANGE then
		frame.Visible = false
		scrim.Visible = false
	end
end)
