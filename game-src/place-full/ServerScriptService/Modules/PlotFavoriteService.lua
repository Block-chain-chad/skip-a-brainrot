-- PlotFavoriteService -- an owner-only LOCK on brainrots placed on YOUR plot. Walk
-- up to your own placed pet, hold F, and it gets a PINK GLOW and becomes raid-proof.
--
-- LOCKED = un-raidable (2026-08-20, owner's call): StealService refuses a locked pet
-- outright. How many you can lock is CAPACITY-GATED by the Padlock upgrade in Enzo's
-- shop (UpgradeConfig.FavoriteCap) -- one free, then one per level.
-- UNIFIED FAVORITE (2026-08-22): `entry.PlotFav` is now the game's ONE favorite --
-- it is raid-proof AND never-sell (SellValue/SellHandler gate on it), and it is set
-- from BOTH the plot (walk-up F) and the Bag (badge click / right-click -> ToggleLock).
-- The old separate never-sell `entry.Fav` is retired.
--
-- Uses hold-F so it never collides with StealService's hold-E "Steal" prompt that
-- sits on the same pet; RaidClient hides Steal for the owner and PlotFavoriteClient
-- hides Favorite for everyone else, so each player only ever sees the one that's
-- theirs to use. Owner-ship is re-checked server-side on every toggle regardless.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local PDM = require(ServerScriptService.Modules.PlayerDataManager)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local PlotFavoriteService = {}
local inited = false

local GLOW_FILL = Color3.fromRGB(255, 120, 200)   -- pink lock wash
local GLOW_LINE = Color3.fromRGB(255, 185, 225)   -- brighter pink outline

local function toast(player, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r and player and player.Parent then
		r:FireClient(player, { Success = true, Message = msg })
	end
end

local function hostOf(model)
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

local function plotOf(model)
	local pads = model and model.Parent
	if pads and pads.Name == "Pads" then return pads.Parent end
	return nil
end

local function findByUid(data, uid)
	if not data then return nil end
	for _, e in ipairs(data.Brainrots) do
		if e.Uid == uid then return e end
	end
	return nil
end

-- Add or remove the pink LOCK GLOW (a Highlight over the whole pet). A locked pet
-- can't be raided, and the glow is how everyone -- owner and would-be thief -- sees
-- that at a glance.
local function setGlow(model, on)
	local existing = model:FindFirstChild("FavGlow")
	if on then
		if existing then return end
		local hl = Instance.new("Highlight")
		hl.Name = "FavGlow"
		hl.Adornee = model
		hl.FillColor = GLOW_FILL
		hl.FillTransparency = 0.55
		hl.OutlineColor = GLOW_LINE
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
	elseif existing then
		existing:Destroy()
	end
end

local function setPromptText(model, on)
	local host = hostOf(model)
	local p = host and host:FindFirstChild("FavPrompt")
	if p then p.ActionText = on and "Unfavorite" or "Favorite" end
end

-- Apply a fav state to EVERY model of this uid across the owner's plots (a pet is
-- rendered on each world's plot, so both copies must show the star together).
local function applyToModels(player, uid, on)
	for _, plot in ipairs(PDM.GetPlots(player)) do
		local pads = plot:FindFirstChild("Pads")
		if pads then
			for _, child in ipairs(pads:GetChildren()) do
				if child:GetAttribute("Uid") == uid then
					child:SetAttribute("PlotFav", on)
					setGlow(child, on)
					setPromptText(child, on)
				end
			end
		end
	end
end

local function onToggle(model, player)
	if not player or not player.Parent then return end
	local plot = plotOf(model)
	if not plot or plot:GetAttribute("OwnerUserId") ~= player.UserId then return end  -- owner only
	local uid = model:GetAttribute("Uid")
	if not uid then return end
	local data = PDM.Get(player)
	local entry = findByUid(data, uid)
	if not entry then return end

	-- Turning a lock ON is capacity-gated: you can only protect as many brainrots as
	-- your Padlock upgrade allows (bought from Enzo). Turning OFF is always free.
	if not entry.PlotFav then
		local cap = UpgradeConfig.FavoriteCap(data.Upgrades)
		local used = 0
		for _, e in ipairs(data.Brainrots) do
			if e.PlotFav then used += 1 end
		end
		if used >= cap then
			toast(player, ("Locks full (%d/%d) -- buy a Padlock from Enzo to lock more."):format(used, cap))
			return
		end
	end

	entry.PlotFav = (not entry.PlotFav) or nil
	local on = entry.PlotFav == true
	applyToModels(player, uid, on)
	PDM.PushUpdate(player)
	-- No toast (2026-08-22): the walk-up button re-labels Favorite<->Unfavorite live and
	-- the pink glow shows the state, so a popup confirmation was just redundant yellow text.
end

-- Attach the prompt + reflect the saved fav state on a freshly spawned pet. Runs
-- for every BrainrotBody, so it covers join-restore, equip, swap and gift alike.
local function attach(model)
	if not model:IsA("Model") then return end
	local uid = model:GetAttribute("Uid")
	-- NO early-out on a missing Uid: EVERY owned brainrot must get the walk-up prompts.
	-- The Uid is read again at trigger time (and is set by the time a real pet is
	-- placed), so gating attach on it here was what left SOME pets with no option.
	local host = hostOf(model)
	if not host then return end

	local favNow = false
	local plot = plotOf(model)
	if plot then
		local owner = Players:GetPlayerByUserId(plot:GetAttribute("OwnerUserId") or 0)
		local entry = findByUid(owner and PDM.Get(owner), uid)
		favNow = entry ~= nil and entry.PlotFav == true
	end
	model:SetAttribute("PlotFav", favNow)
	setGlow(model, favNow)

	if not host:FindFirstChild("FavPrompt") then
		local p = Instance.new("ProximityPrompt")
		p.Name = "FavPrompt"
		p.Style = Enum.ProximityPromptStyle.Custom   -- PlotFavoriteClient draws the pink pill UI
		p.ActionText = favNow and "Unfavorite" or "Favorite"
		p.ObjectText = model.Name                    -- the brainrot's own name, like the reference
		p.KeyboardKeyCode = Enum.KeyCode.F           -- E is StealService's; keep them apart
		p.HoldDuration = 0                           -- press, not hold (a button, like the reference)
		p.MaxActivationDistance = 12
		p.RequiresLineOfSight = false
		p.Parent = host
		p.Triggered:Connect(function(plr) onToggle(model, plr) end)
	end

	-- STORE prompt (owner-only, hold-E): walk up to your OWN placed brainrot and hold
	-- E to store it back in your bag. Shares the E key with StealService's Steal prompt,
	-- but Steal is hidden on your own plot (RaidClient) while Store is shown there
	-- (PlotFavoriteClient) -- so only one E prompt is ever live. The store itself is
	-- fired client-side via the existing StoreBrainrot remote (already owner-validated),
	-- so there's no server Triggered handler here.
	if not host:FindFirstChild("StorePrompt") then
		local sp = Instance.new("ProximityPrompt")
		sp.Name = "StorePrompt"
		sp.Style = Enum.ProximityPromptStyle.Custom   -- PlotFavoriteClient draws the dark pill
		sp.ActionText = "Store"
		sp.ObjectText = model.Name
		sp.KeyboardKeyCode = Enum.KeyCode.E
		sp.HoldDuration = 0.35
		sp.MaxActivationDistance = 12
		sp.RequiresLineOfSight = false
		sp.Parent = host
	end
end

function PlotFavoriteService.Init()
	if inited then return end
	inited = true
	for _, m in ipairs(CollectionService:GetTagged("BrainrotBody")) do attach(m) end
	CollectionService:GetInstanceAddedSignal("BrainrotBody"):Connect(attach)

	-- BAG RIGHT-CLICK LOCK (2026-08-20): the Bag panel fires ToggleLock with a
	-- stack's uids -- toggle the WHOLE stack, capacity-gated by the Padlock upgrade.
	local toggleLock = remotes:FindFirstChild("ToggleLock")
	if not toggleLock then
		toggleLock = Instance.new("RemoteEvent")
		toggleLock.Name = "ToggleLock"
		toggleLock.Parent = remotes
	end
	toggleLock.OnServerEvent:Connect(function(player, uids)
		if typeof(uids) == "number" then uids = { uids } end
		if typeof(uids) ~= "table" or #uids == 0 or #uids > 512 then return end
		local data = PDM.Get(player)
		if not data then return end
		-- keep only uids that are really this player's
		local mine = {}
		for _, uid in ipairs(uids) do
			local e = findByUid(data, uid)
			if e then mine[#mine + 1] = e end
		end
		if #mine == 0 then return end
		-- all currently locked -> UNLOCK the stack; else LOCK the unlocked ones
		local allLocked = true
		for _, e in ipairs(mine) do if not e.PlotFav then allLocked = false break end end
		if allLocked then
			for _, e in ipairs(mine) do
				e.PlotFav = nil
				applyToModels(player, e.Uid, false)
			end
			PDM.PushUpdate(player)
			-- No toast: the bag badge / plot glow already show the change.
			return
		end
		local cap = UpgradeConfig.FavoriteCap(data.Upgrades)
		local used = 0
		for _, e in ipairs(data.Brainrots) do if e.PlotFav then used += 1 end end
		local room = cap - used
		local toLock = {}
		for _, e in ipairs(mine) do if not e.PlotFav then toLock[#toLock + 1] = e end end
		if room <= 0 then
			toast(player, ("Favorites full (%d/%d) -- buy a Padlock from Enzo to lock more."):format(used, cap))
			return
		end
		-- PARTIAL LOCK (2026-08-22): lock as many of the stack as the cap allows rather
		-- than refusing the whole batch. With locked copies stacking apart in the bag,
		-- favoriting a stack under a small cap locks what it can and those copies split
		-- into their own card; the rest stay loose. Matches the walk-up path's per-pet feel.
		local locked = 0
		for _, e in ipairs(toLock) do
			if locked >= room then break end
			e.PlotFav = true
			applyToModels(player, e.Uid, true)
			locked += 1
		end
		PDM.PushUpdate(player)
		-- Only toast the PARTIAL case: it warns that the cap stopped a full lock (why some
		-- of the stack stayed loose). A clean full lock shows via the badge/glow -- no popup.
		if locked < #toLock then
			toast(player, ("\u{1F512} Favorited %d (%d/%d) -- buy a Padlock from Enzo for more."):format(locked, used + locked, cap))
		end
	end)

	print("PlotFavoriteService online (walk-up F + bag right-click lock, pink glow, Padlock-gated)")
end

return PlotFavoriteService
