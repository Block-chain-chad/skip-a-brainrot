-- PlotFavoriteClient -- the mirror of RaidClient. The server puts a "Favorite"
-- (hold-F) prompt on every placed brainrot, but favoriting is OWNER-ONLY, so this
-- hides that prompt on any pet the local player does NOT own. Result: on your own
-- plot you see "Favorite (F)" and no "Steal"; on someone else's you see "Steal (E)"
-- and no "Favorite". Setting .Enabled on the client only affects this client's view.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")

-- STORE via the hold-E prompt (owner-only). The StorePrompt sits on your own placed
-- brainrots; on trigger we fire the existing StoreBrainrot remote (server-validated)
-- with the brainrot's Uid, reusing the inventory path instead of duplicating it.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name ~= "StorePrompt" then return end
	local n = prompt.Parent
	while n do
		local uid = n:GetAttribute("Uid")
		if uid then
			remotes.StoreBrainrot:FireServer(uid)
			return
		end
		n = n.Parent
	end
end)

-- CUSTOM PROMPT UI for the owner walk-up prompts (styled off the reference): rounded
-- pills with a key badge, the brainrot's NAME on top and the action below, floated
-- ABOVE the brainrot so it stays visible. Store (E, dark) sits just above Favorite
-- (F, pink), close together. The server marks both Style=Custom; PromptHidden tears
-- each one down.
local PINK = {
	g1 = Color3.fromRGB(236, 96, 160), g2 = Color3.fromRGB(196, 52, 118),
	stroke = Color3.fromRGB(58, 18, 38), keyBg = Color3.fromRGB(255, 240, 247),
	keyInk = Color3.fromRGB(120, 34, 74), obj = Color3.fromRGB(255, 219, 234),
}
local DARK = {
	g1 = Color3.fromRGB(62, 68, 82), g2 = Color3.fromRGB(38, 42, 54),
	stroke = Color3.fromRGB(16, 18, 26), keyBg = Color3.fromRGB(236, 239, 246),
	keyInk = Color3.fromRGB(42, 48, 60), obj = Color3.fromRGB(206, 214, 226),
}

-- Y offset (studs) that sits the pills LOW -- down around the BASE of the model,
-- clear BELOW its name/income title (which floats above the head). Measured from the
-- adornee to the BOTTOM of the model's bounding box, so it lands right no matter which
-- limb the PrimaryPart happens to be (mirrors BrainrotSpawner's own toTop math).
local function baseOffset(host)
	local m = host
	while m and not m:IsA("Model") do m = m.Parent end
	if m and host and host:IsA("BasePart") then
		local boxCF, boxSize = m:GetBoundingBox()
		return (boxCF.Position.Y - boxSize.Y * 0.5) - host.Position.Y
	end
	return -1.5
end

local PILL_H = 52
local GAP = 6   -- pixels between the two pills. Tune this for more/less separation.

-- One pill FRAME (not its own BillboardGui) so both can share a single billboard
-- with a fixed pixel gap between them.
local function makePill(parent, keyText, objText, actText, pal, order)
	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(206, PILL_H); box.BorderSizePixel = 0
	box.BackgroundColor3 = pal.g2; box.LayoutOrder = order; box.Parent = parent
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 13)
	local grad = Instance.new("UIGradient"); grad.Rotation = 90
	grad.Color = ColorSequence.new(pal.g1, pal.g2); grad.Parent = box
	local st = Instance.new("UIStroke"); st.Thickness = 2.5; st.Color = pal.stroke; st.Parent = box

	local key = Instance.new("Frame")
	key.Size = UDim2.fromOffset(38, 38); key.Position = UDim2.fromOffset(7, 7)
	key.BackgroundColor3 = pal.keyBg; key.BorderSizePixel = 0; key.Parent = box
	Instance.new("UICorner", key).CornerRadius = UDim.new(0, 9)
	local kst = Instance.new("UIStroke"); kst.Thickness = 2; kst.Color = pal.stroke; kst.Parent = key
	local kl = Instance.new("TextLabel")
	kl.BackgroundTransparency = 1; kl.Size = UDim2.fromScale(1, 1)
	kl.Font = Enum.Font.FredokaOne; kl.TextScaled = true
	kl.Text = keyText; kl.TextColor3 = pal.keyInk; kl.Parent = key
	local kp = Instance.new("UIPadding")
	kp.PaddingTop = UDim.new(0, 6); kp.PaddingBottom = UDim.new(0, 6)
	kp.PaddingLeft = UDim.new(0, 6); kp.PaddingRight = UDim.new(0, 6); kp.Parent = kl

	local obj = Instance.new("TextLabel")
	obj.BackgroundTransparency = 1; obj.Position = UDim2.fromOffset(52, 6)
	obj.Size = UDim2.new(1, -60, 0, 16); obj.Font = Enum.Font.GothamMedium
	obj.TextSize = 13; obj.TextXAlignment = Enum.TextXAlignment.Left
	obj.TextColor3 = pal.obj; obj.TextTruncate = Enum.TextTruncate.AtEnd
	obj.Text = objText; obj.Parent = box

	local act = Instance.new("TextLabel")
	act.BackgroundTransparency = 1; act.Position = UDim2.fromOffset(52, 23)
	act.Size = UDim2.new(1, -60, 0, 23); act.Font = Enum.Font.FredokaOne
	act.TextSize = 20; act.TextXAlignment = Enum.TextXAlignment.Left
	act.TextColor3 = Color3.new(1, 1, 1); act.TextTruncate = Enum.TextTruncate.AtEnd
	act.Text = actText; act.Parent = box
	Instance.new("UIStroke", act).Color = pal.stroke
	return box, act
end

-- BOTH pills live in ONE BillboardGui so their gap is a fixed pixel value (GAP),
-- never a studs offset that drifts with camera distance -- Store (E, dark) on top,
-- Favorite (F, pink) below, floated above the brainrot so it stays visible. Built
-- when the Favorite prompt shows (Store shows with it on your own plot); the Store
-- prompt's own PromptShown is ignored. Torn down when the Favorite prompt hides.
ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom or prompt.Name ~= "FavPrompt" then return end
	local host = prompt.Parent
	if not host then return end
	local model = host
	while model and not model:IsA("Model") do model = model.Parent end
	local storePrompt = model and model:FindFirstChild("StorePrompt", true)

	local bb = Instance.new("BillboardGui")
	bb.Name = "OwnerPromptUI"
	bb.Adornee = host
	bb.Size = UDim2.fromOffset(206, PILL_H * 2 + GAP)
	-- Lowered 2026-08-22: pills now sit near the model's BASE, not above its head, so
	-- they never overlap the brainrot's name/income title. +1.0 keeps them just off the
	-- ground rather than clipping into the pad.
	bb.StudsOffset = Vector3.new(0, baseOffset(host) + 1.0, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 60
	bb.Parent = host

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bb

	if storePrompt then
		makePill(bb, storePrompt.KeyboardKeyCode.Name, storePrompt.ObjectText, storePrompt.ActionText, DARK, 1)
	end
	local _, favAct = makePill(bb, prompt.KeyboardKeyCode.Name, prompt.ObjectText, prompt.ActionText, PINK, 2)

	-- The pink pill's action label IS the favorited indicator: the server flips
	-- FavPrompt.ActionText between "Favorite" and "Unfavorite" the instant you toggle
	-- (PlotFavoriteService.setPromptText). Mirror that onto the button LIVE so it
	-- re-labels to "Unfavorite" the moment you favorite -- no walking away and back, and
	-- no separate status text.
	local actConn = prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		if favAct and favAct.Parent then favAct.Text = prompt.ActionText end
	end)

	local conn
	conn = prompt.PromptHidden:Connect(function()
		if conn then conn:Disconnect() end
		if actConn then actConn:Disconnect() end
		bb:Destroy()
	end)
end)

-- The plot MODEL a brainrot sits on, found STRUCTURALLY so it resolves even before
-- the OwnerUserId attribute has replicated (mirror of RaidClient).
local function plotOf(model)
	local n = model.Parent
	while n do
		if n:FindFirstChild("Campfire") and n:FindFirstChild("Pads") then return n end
		n = n.Parent
	end
	return nil
end

local function manage(model)
	if not model:IsA("Model") then return end
	task.spawn(function()
		local plot = plotOf(model)
		-- Favorite AND Store are OWNER-ONLY walk-up prompts: shown only on YOUR OWN plot.
		-- Find them ANYWHERE in the model (recursive) rather than on a self-computed host
		-- part -- PrimaryPart can be momentarily nil on the client, and a wrong host was
		-- leaving some pets ungated. Mirror of RaidClient (Steal hidden on your own plot).
		local function gate()
			local owner = plot and plot:GetAttribute("OwnerUserId")
			local isOwner = (owner ~= nil) and (owner == player.UserId)
			local fav = model:FindFirstChild("FavPrompt", true)
			local store = model:FindFirstChild("StorePrompt", true)
			if fav then fav.Enabled = isOwner end
			if store then store.Enabled = isOwner end
		end
		gate()
		model.DescendantAdded:Connect(function(d)
			if d.Name == "FavPrompt" or d.Name == "StorePrompt" then gate() end
		end)
		if plot then
			plot:GetAttributeChangedSignal("OwnerUserId"):Connect(gate)
		end
	end)
end

for _, m in ipairs(CollectionService:GetTagged("BrainrotBody")) do manage(m) end
CollectionService:GetInstanceAddedSignal("BrainrotBody"):Connect(manage)
