-- StealService -- the PLOT RAID mechanic. A player walks to another player's plot,
-- holds the "Steal" prompt on one of their placed brainrots, pays 39 Robux (a
-- Developer Product), and that brainrot moves off the victim's plot into the
-- thief's BAG (unplaced). Server-authoritative end to end.
--
-- REUSES the trade transfer path: BrainrotMover.TakeByUid pulls the record out of
-- the victim (draining its pending income and removing the pad model), and we drop
-- it into the thief's data with PadIndex=nil so InventoryHandler.SyncBackpack puts
-- it in their Bag -- same shape as a freshly caught pet.
--
-- PROTECTION RULES (all knobs in ReplicatedStorage.Modules.StealConfig):
--   * SHIELD -- can't start a raid while the owner is standing on their own plot.
--   * COOLDOWN -- after a successful steal the thief waits CooldownSeconds (3 min).
--   * OFFLINE owners can't be robbed: their plot is released when they leave, so
--     there is nothing in the world to raid (this also keeps every transfer between
--     two in-memory players -- no offline DataStore surgery).
--   * UNIQUE cap respected, same as trades.
--
-- PAYMENT LINKAGE: a Robux receipt only carries who-bought + which-product, never
-- which pet from whose plot. So initiation RESERVES the target (per thief), and the
-- receipt path (ProductRegistry -> CompletePurchasedSteal) consumes that reservation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")

local PDM = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotMover = require(ServerScriptService.Modules.BrainrotMover)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local EmeraldService = require(ServerScriptService.Modules.EmeraldService)
local ProductRegistry = require(ServerScriptService.Modules.ProductRegistry)
local StealConfig = require(ReplicatedStorage.Modules.StealConfig)
local SeasonConfig = require(ReplicatedStorage.Modules.SeasonConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)
-- Brainrot bag capacity. Checked at RESERVATION time only -- see the note there.
local BagConfig = require(ReplicatedStorage.Modules.BagConfig)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local StealService = {}
local inited = false

-- pending[thiefUserId] = { victimId, uid, plot, at } -- one reservation per thief
local pending = {}
-- cooldownUntil[thiefUserId] = os.clock() deadline set on a SUCCESSFUL steal
local cooldownUntil = {}

-- ToastClient renders { Success, Message } off PurchaseResult -- reuse it.
local function getRemote(name)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end
local purchaseResult = getRemote("PurchaseResult")
local function toast(player, success, msg)
	if player and player.Parent then
		purchaseResult:FireClient(player, { Success = success, Message = msg })
	end
end

-- === helpers =================================================================

-- The plot a brainrot model is standing on (models live under plot.Pads).
local function plotOf(model)
	local pads = model and model.Parent
	if pads and pads.Name == "Pads" then return pads.Parent end
	return nil
end

-- Owner physically home? Horizontal distance from the plot's Campfire.
local function ownerGuarding(plot, ownerId)
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	local char = owner and owner.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local fire = plot:FindFirstChild("Campfire") or plot:FindFirstChild("Platform")
	if not (hrp and fire) then return false end
	local a, b = hrp.Position, fire.Position
	local dx, dz = a.X - b.X, a.Z - b.Z
	return (dx * dx + dz * dz) <= (StealConfig.ShieldRadius * StealConfig.ShieldRadius)
end

local function valueOf(entry)
	local info = BrainrotMover.InfoByName[entry.Name]
	return (info and info.CashPerSecond or 0) * MutationConfig.Mult(entry.Mutation)
end

-- If the exact reserved pet is gone, the most valuable OTHER pet still on that same
-- plot, so a paid raid still lands something. Returns a taken record or nil.
local function takeBestOnPlot(victim, victimData, plot)
	local pads = plot and plot:FindFirstChild("Pads")
	if not pads then return nil end
	local onPlot = {}
	for _, child in ipairs(pads:GetChildren()) do
		local u = child:GetAttribute("Uid")
		if u then onPlot[u] = true end
	end
	local bestUid, bestScore
	for _, e in ipairs(victimData.Brainrots) do
		if e.Uid and onPlot[e.Uid] and not e.PlotFav then
			local s = valueOf(e)
			if not bestScore or s > bestScore then bestScore, bestUid = s, e.Uid end
		end
	end
	if not bestUid then return nil end
	return BrainrotMover.TakeByUid(victim, victimData, bestUid)
end

-- Drops a taken record into the thief's BAG (unplaced) -- never auto-placed.
local function toBag(thief, thiefData, record)
	local uid = PDM.TakeUid(thiefData)
	table.insert(thiefData.Brainrots, {
		Name = record.Name, Mutation = record.Mutation,
		Serial = record.Serial, MintedAt = record.MintedAt, Size = record.Size,
		PadIndex = nil, Pending = 0, Uid = uid,
	})
	InventoryHandler.SyncBackpack(thief)
	PDM.PushUpdate(thief)
	-- No Save here on purpose: on the paid path ProductRegistry saves the thief
	-- AFTER it logs the receipt, so the transfer and the receipt persist together --
	-- saving early would let a crash re-run the grant and steal a SECOND pet. The
	-- creator free-test path saves itself (it has no receipt).
end

-- Performs the actual transfer for a reservation. Returns true if a pet was taken.
-- Deliberately does NOT re-check the shield (payer-fair: once committed the steal
-- lands), but the plot must still belong to the same victim.
local function doTransfer(thief, thiefData, res)
	local victim = Players:GetPlayerByUserId(res.victimId)
	local victimData = victim and PDM.Get(victim)
	if not victim or not victimData or victimData.__noSave then return false end

	local record = BrainrotMover.TakeByUid(victim, victimData, res.uid)
	if not record then
		record = takeBestOnPlot(victim, victimData, res.plot)
	end
	if not record then return false end

	-- Unique cap for the thief. If they somehow can't hold it now, put it back on
	-- the victim rather than deleting it mid-transfer, and report failure.
	if not BrainrotMover.WithinUniqueCap(record.Name, BrainrotMover.CountOwned(thiefData, record.Name), 0, 1) then
		BrainrotMover.Give(victim, victimData, record)
		InventoryHandler.SyncBackpack(victim)
		PDM.PushUpdate(victim)
		return false
	end

	toBag(thief, thiefData, record)
	InventoryHandler.SyncBackpack(victim)
	PDM.PushUpdate(victim)
	PDM.Save(victim)

	cooldownUntil[thief.UserId] = os.clock() + StealConfig.CooldownSeconds
	local mut = record.Mutation and (record.Mutation .. " ") or ""
	toast(thief, true, ("You raided a %s%s!"):format(mut, record.Name))
	toast(victim, false, ("%s raided your %s!"):format(thief.Name, record.Name))
	return true
end

-- === receipt completion (called by ProductRegistry.grant) ====================
-- ALWAYS returns true so the Robux receipt resolves (never a stuck pending
-- purchase): either the pet lands, or the consolation emeralds do.
function StealService.CompletePurchasedSteal(thief, thiefData)
	local res = pending[thief.UserId]
	pending[thief.UserId] = nil
	if res and doTransfer(thief, thiefData, res) then
		return true
	end
	if StealConfig.ConsolationEmeralds > 0 then
		EmeraldService.Award(thief, StealConfig.ConsolationEmeralds, "raidfail")
		toast(thief, false, ("Raid missed -- %d gems refunded."):format(StealConfig.ConsolationEmeralds))
	else
		toast(thief, false, "Raid missed -- the target got away.")
	end
	return true
end

-- === initiation =============================================================
local function onTriggered(model, thief)
	if not thief or not thief.Parent then return end
	local creatorFree = StealConfig.CreatorFreeTest and SeasonConfig.IsCreator(thief.UserId)
	if not StealConfig.IsLive() and not creatorFree then
		toast(thief, false, "Raiding is coming soon!")
		return
	end

	local uid = model:GetAttribute("Uid")
	local plot = plotOf(model)
	if not uid or not plot then return end
	if plot:GetAttribute("Claimed") ~= true then return end
	local ownerId = plot:GetAttribute("OwnerUserId")
	if not ownerId then return end

	if ownerId == thief.UserId then
		toast(thief, false, "You can't raid your own plot.")
		return
	end
	local victim = Players:GetPlayerByUserId(ownerId)
	if not victim then
		toast(thief, false, "That plot's owner has left.")
		return
	end

	-- LOCKED pets can't be raided at all (PlotFavoriteService's pink-glow lock).
	local victimData = PDM.Get(victim)
	if victimData then
		for _, e in ipairs(victimData.Brainrots) do
			if e.Uid == uid then
				if e.PlotFav then
					toast(thief, false, "That brainrot is locked -- it can't be raided.")
					return
				end
				break
			end
		end
	end

	local now = os.clock()
	local until_ = cooldownUntil[thief.UserId]
	if until_ and now < until_ then
		toast(thief, false, ("Raid on cooldown -- %ds left."):format(math.ceil(until_ - now)))
		return
	end

	if ownerGuarding(plot, ownerId) then
		toast(thief, false, "Can't raid -- the owner is home!")
		return
	end

	local name = model.Name
	if not BrainrotMover.WithinUniqueCap(name, BrainrotMover.CountOwned(PDM.Get(thief) or { Brainrots = {} }, name), 0, 1) then
		toast(thief, false, "You already have the max of that one.")
		return
	end

	-- BAG SPACE, AND ONLY HERE (2026-08-20). This is the last point before the
	-- Robux prompt, so refusing costs the thief nothing. The transfer itself
	-- (doTransfer / CompletePurchasedSteal) deliberately does NOT re-check: by
	-- then a receipt exists, and taking someone's Robux and then handing back
	-- nothing because their bag filled up mid-purchase is strictly worse than
	-- letting one steal land one over the cap. Same payer-fair reasoning the
	-- shield re-check already documents.
	if not BagConfig.HasBrainrotSpace(PDM.Get(thief), 1) then
		toast(thief, false, BagConfig.BrainrotFullMessage(PDM.Get(thief)))
		return
	end

	-- Price tier by the target's rarity (Default 79 / Secret 499 / God 1999 R$).
	local info = BrainrotMover.InfoByName[name]
	local tier = StealConfig.TierFor(info and info.Rarity)
	if not creatorFree and not StealConfig.TierIsLive(tier) then
		toast(thief, false, "That kind of brainrot can't be raided yet.")
		return
	end

	local res = { victimId = ownerId, uid = uid, plot = plot, at = now }

	if creatorFree then
		local thiefData = PDM.Get(thief)
		if thiefData and doTransfer(thief, thiefData, res) then
			PDM.Save(thief)
		else
			toast(thief, false, "Raid failed.")
		end
		return
	end

	pending[thief.UserId] = res
	MarketplaceService:PromptProductPurchase(thief, tier.ProductId)
end

-- === prompt wiring ===========================================================
-- One "Steal" ProximityPrompt per placed brainrot. Brainrot bodies are tagged
-- BrainrotBody by BrainrotSpawner AFTER their Uid attribute is set, so the tag
-- signal is a safe moment to attach.
local function attachPrompt(model)
	if not model:IsA("Model") then return end
	if not model:GetAttribute("Uid") then return end
	local host = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not host or host:FindFirstChild("RaidPrompt") then return end

	local p = Instance.new("ProximityPrompt")
	p.Name = "RaidPrompt"
	local info = BrainrotMover.InfoByName[model.Name]
	local tier = StealConfig.TierFor(info and info.Rarity)
	p.ActionText = ("%s (%d R$)"):format(StealConfig.ActionText, tier.RobuxPrice)
	p.ObjectText = StealConfig.ObjectText
	p.HoldDuration = StealConfig.HoldDuration
	p.MaxActivationDistance = StealConfig.MaxDistance
	p.RequiresLineOfSight = false
	-- Shown to everyone the feature is usable for; RaidClient hides it on the local
	-- player's OWN plot. While nothing is live and no creator test is on, it stays off.
	p.Enabled = StealConfig.IsLive() or StealConfig.CreatorFreeTest
	p.Parent = host
	p.Triggered:Connect(function(plr) onTriggered(model, plr) end)
end

function StealService.Init()
	if inited then return end
	inited = true

	-- Register the pay-per-steal product. grant() calls back into this module via
	-- the def.Grant hook, so ProductRegistry never has to require StealService.
	-- Register every live price tier's product; they all complete through the same
	-- reservation-consuming grant, so the price the player paid doesn't matter here.
	local liveTiers = 0
	for _, tier in pairs(StealConfig.Tiers) do
		if StealConfig.TierIsLive(tier) then
			ProductRegistry.Register(tier.ProductId, {
				Type = "Steal",
				Grant = function(player, data) return StealService.CompletePurchasedSteal(player, data) end,
			})
			liveTiers += 1
		end
	end

	for _, m in ipairs(CollectionService:GetTagged("BrainrotBody")) do attachPrompt(m) end
	CollectionService:GetInstanceAddedSignal("BrainrotBody"):Connect(attachPrompt)

	Players.PlayerRemoving:Connect(function(p)
		pending[p.UserId] = nil
		cooldownUntil[p.UserId] = nil
	end)

	print(("StealService online (raid %d/%d/%d R$ by rarity, %ds cooldown, %d/3 tiers live)")
		:format(StealConfig.Tiers.Default.RobuxPrice, StealConfig.Tiers.Secret.RobuxPrice,
			StealConfig.Tiers.God.RobuxPrice, StealConfig.CooldownSeconds, liveTiers))
end

return StealService
