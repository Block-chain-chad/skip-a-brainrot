-- BoothHandler (Trading Center section)
-- Market stands, Pet Simulator style: claim a stand, put brainrots up for
-- sale at a price you choose, and other players walk up and buy them.
-- EVERY rule is enforced here on the server. The client UI can only ask.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotMover = require(ServerScriptService.Modules.BrainrotMover)
local PriceIndex = require(ServerScriptService.Modules.PriceIndex)

local remotes = ReplicatedStorage.Remotes

local MAX_LISTINGS = 3 -- one per display pedestal on the stand
local MAX_PRICE = 1000000000

local booths = {} -- [index] = { index, model, ownerUserId, listings = { {Id, Name, Price} } }
local nextListingId = 1

local BoothHandler = {}

local function formatMoney(n)
	n = math.floor(n)
	if n >= 1000000000 then
		return string.format("%.2fB", n / 1000000000)
	elseif n >= 1000000 then
		return string.format("%.2fM", n / 1000000)
	elseif n >= 1000 then
		return string.format("%.1fK", n / 1000)
	end
	return tostring(n)
end

local function toast(player, message)
	remotes.BoothState:FireClient(player, { Phase = "Toast", Message = message })
end

local function setSign(booth, text)
	local sign = booth.model:FindFirstChild("SignBoard")
	if not sign then return end
	for _, gui in ipairs(sign:GetChildren()) do
		if gui:IsA("SurfaceGui") then
			local label = gui:FindFirstChildOfClass("TextLabel")
			if label then label.Text = text end
		end
	end
end

-- open=true means the owner asked to open the window (via the stand prompt);
-- otherwise this is a background refresh that must NOT force the window open on
-- their screen while they are off playing elsewhere.
local function pushManageState(booth, open)
	local owner = booth.ownerUserId and Players:GetPlayerByUserId(booth.ownerUserId)
	if not owner then return end
	remotes.BoothState:FireClient(owner, {
		Phase = "Manage",
		Open = open == true,
		BoothIndex = booth.index,
		Listings = booth.listings,
		MaxListings = MAX_LISTINGS,
	})
end

-- Rebuild the glowing display items + price tags + buy prompts on the counter.
local function refreshDisplays(booth)
	for _, child in ipairs(booth.model:GetChildren()) do
		if child.Name == "ListingDisplay" then child:Destroy() end
	end
	local owner = booth.ownerUserId and Players:GetPlayerByUserId(booth.ownerUserId)
	for slot, listing in ipairs(booth.listings) do
		local anchor = booth.model:FindFirstChild("Display" .. slot)
		if anchor then
			local info = BrainrotMover.InfoByName[listing.Name]
			local tier = info and BrainrotMover.TierByName[info.Rarity]

			local cube = Instance.new("Part")
			cube.Name = "ListingDisplay"
			cube.Size = Vector3.new(1.8, 1.8, 1.8)
			cube.Anchored = true
			cube.CanCollide = false
			cube.Material = Enum.Material.Neon
			cube.Color = tier and tier.Color or Color3.fromRGB(255, 255, 255)
			cube.CFrame = anchor.CFrame * CFrame.new(0, 1.7, 0)
			cube.Parent = booth.model

			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.new(0, 130, 0, 40)
			billboard.StudsOffset = Vector3.new(0, 1.8, 0)
			billboard.AlwaysOnTop = true
			billboard.Parent = cube

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.Text = listing.Name .. "\n$" .. formatMoney(listing.Price)
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeTransparency = 0
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.Parent = billboard

			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "BuyPrompt"
			prompt.ActionText = "Buy for $" .. formatMoney(listing.Price)
			prompt.ObjectText = listing.Name
			prompt.HoldDuration = 0.3
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt:SetAttribute("BoothIndex", booth.index)
			prompt:SetAttribute("ListingId", listing.Id)
			prompt:SetAttribute("ItemName", listing.Name)
			prompt:SetAttribute("Price", listing.Price)
			prompt:SetAttribute("SellerName", owner and owner.DisplayName or "?")
			prompt.Parent = cube
			-- NOTE: the server never connects BuyPrompt.Triggered. The client
			-- shows a confirm popup, then fires the BoothBuy remote, and THAT
			-- is validated below.
		end
	end
end

local function releaseBooth(booth)
	booth.ownerUserId = nil
	booth.listings = {}
	refreshDisplays(booth)
	setSign(booth, "AVAILABLE STAND")
	local prompt = booth.model.Counter:FindFirstChild("StandPrompt")
	if prompt then prompt.ActionText = "Claim Stand" end
end

local function boothOwnedBy(player)
	for _, booth in ipairs(booths) do
		if booth.ownerUserId == player.UserId then return booth end
	end
	return nil
end

local function countListed(booth, name)
	local n = 0
	for _, listing in ipairs(booth.listings) do
		if listing.Name == name then n += 1 end
	end
	return n
end

local BUY_RADIUS = 26 -- studs; the buyer must actually be standing at the stand

local function characterNearBooth(player, booth)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local counter = booth.model:FindFirstChild("Counter")
	local origin = counter and counter.Position or booth.model:GetPivot().Position
	return (hrp.Position - origin).Magnitude <= BUY_RADIUS
end

local function onStandPrompt(booth, player)
	if booth.ownerUserId == nil then
		if boothOwnedBy(player) then
			toast(player, "You already have a stand. Unclaim it first.")
			return
		end
		booth.ownerUserId = player.UserId
		setSign(booth, string.upper(player.DisplayName) .. "'S STAND")
		local prompt = booth.model.Counter:FindFirstChild("StandPrompt")
		if prompt then prompt.ActionText = "Manage Stand" end
		pushManageState(booth, true)
	elseif booth.ownerUserId == player.UserId then
		pushManageState(booth, true)
	else
		local owner = Players:GetPlayerByUserId(booth.ownerUserId)
		toast(player, "This stand belongs to " .. (owner and owner.DisplayName or "someone else") .. ". Hold E on a display item to buy it.")
	end
end

function BoothHandler.Init()
	local tradingCenter = Workspace:WaitForChild("GameWorld"):WaitForChild("TradingCenter")
	local boothsFolder = tradingCenter:WaitForChild("Booths")
	for _, model in ipairs(boothsFolder:GetChildren()) do
		local idx = model:GetAttribute("BoothIndex")
		if idx then
			local booth = { index = idx, model = model, ownerUserId = nil, listings = {} }
			booths[idx] = booth
			local prompt = model:WaitForChild("Counter"):WaitForChild("StandPrompt")
			prompt.Triggered:Connect(function(player)
				onStandPrompt(booth, player)
			end)
		end
	end

	remotes.BoothList.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" or typeof(payload.Action) ~= "string" then return end
		local booth = boothOwnedBy(player)
		if not booth then return end
		local data = PlayerDataManager.Get(player)
		if not data then return end

		if payload.Action == "Add" then
			local name = payload.Name
			if typeof(name) ~= "string" or not BrainrotMover.InfoByName[name] then return end
			if #booth.listings >= MAX_LISTINGS then
				toast(player, "Your stand is full (" .. MAX_LISTINGS .. " items max).")
				return
			end
			local price = tonumber(payload.Price)
			if not price or price ~= price then return end -- reject non-numbers and NaN
			price = math.floor(price)
			if price < 1 or price > MAX_PRICE then
				toast(player, "Price must be between $1 and $" .. formatMoney(MAX_PRICE) .. ".")
				return
			end
			-- can't list more copies than you actually own
			if countListed(booth, name) + 1 > BrainrotMover.CountOwned(data, name) then
				toast(player, "You don't own enough " .. name .. " to list another.")
				return
			end
			table.insert(booth.listings, { Id = nextListingId, Name = name, Price = price })
			nextListingId += 1
			refreshDisplays(booth)
			pushManageState(booth)

		elseif payload.Action == "Remove" then
			for i, listing in ipairs(booth.listings) do
				if listing.Id == payload.Id then
					table.remove(booth.listings, i)
					break
				end
			end
			refreshDisplays(booth)
			pushManageState(booth)

		elseif payload.Action == "Unclaim" then
			releaseBooth(booth)
			toast(player, "Stand unclaimed.")
		end
	end)

	remotes.BoothBuy.OnServerEvent:Connect(function(buyer, boothIndex, listingId)
		if typeof(boothIndex) ~= "number" or typeof(listingId) ~= "number" then return end
		local booth = booths[boothIndex]
		if not booth or not booth.ownerUserId then return end

		local listingPos, listing
		for i, l in ipairs(booth.listings) do
			if l.Id == listingId then
				listingPos, listing = i, l
				break
			end
		end
		if not listing then
			toast(buyer, "That item was just sold or removed.")
			return
		end

		local seller = Players:GetPlayerByUserId(booth.ownerUserId)
		if not seller then
			releaseBooth(booth)
			return
		end
		if buyer == seller then
			toast(buyer, "You can't buy from your own stand.")
			return
		end
		if not characterNearBooth(buyer, booth) then
			toast(buyer, "Walk up to the stand to buy this.")
			return
		end

		local buyerData = PlayerDataManager.Get(buyer)
		local sellerData = PlayerDataManager.Get(seller)
		if not buyerData or not sellerData then return end

		if buyerData.Cash < listing.Price then
			toast(buyer, "Not enough cash \u{2014} that costs $" .. formatMoney(listing.Price) .. ".")
			return
		end
		if BrainrotMover.CountOwned(sellerData, listing.Name) < 1 then
			-- seller no longer owns it (sold or traded it away) -> stale listing
			table.remove(booth.listings, listingPos)
			refreshDisplays(booth)
			pushManageState(booth)
			toast(buyer, "That brainrot is no longer available.")
			return
		end
		-- UNIQUE cap, checked BEFORE the Take below. Refusing inside BrainrotMover.Give
		-- would delete the item mid-transfer, because Take has already pulled it off the
		-- seller by then. Bailing here costs the buyer nothing.
		if not BrainrotMover.WithinUniqueCap(listing.Name,
			BrainrotMover.CountOwned(buyerData, listing.Name), 0, 1) then
			toast(buyer, "You can only have one " .. listing.Name .. ".")
			return
		end

		-- Do the sale. No yields between the checks above and the swap below,
		-- so two buyers can never both pass validation for the same listing.
		-- carry the taken RECORD across so a mutated brainrot stays mutated
		local record = BrainrotMover.Take(seller, sellerData, listing.Name)
		if not record then
			toast(buyer, "That brainrot is no longer available.")
			return
		end
		BrainrotMover.Give(buyer, buyerData, record)
		buyerData.Cash -= listing.Price   -- spending: deliberately not through GrantCash
		PlayerDataManager.GrantCash(sellerData, listing.Price)
		table.remove(booth.listings, listingPos)

		-- The swap has settled, so this is a real price: someone chose to pay it
		-- and someone chose to accept it. Feeding it to the index is what lets the
		-- game publish its own honest values instead of players having to trust an
		-- off-platform list. Use the RECORD's name and mutation rather than the
		-- listing's -- a Golden copy is its own market and must not be priced as a
		-- plain one. RecordSale only touches memory and never yields, so it cannot
		-- open a gap in the no-yield window guarded above.
		PriceIndex.RecordSale(record.Name, record.Mutation, listing.Price, buyer.UserId, seller.UserId)

		refreshDisplays(booth)
		pushManageState(booth)
		PlayerDataManager.PushUpdate(buyer)
		PlayerDataManager.PushUpdate(seller)
		PlayerDataManager.Save(buyer)
		PlayerDataManager.Save(seller)

		toast(buyer, "\u{2705} Bought " .. listing.Name .. " for $" .. formatMoney(listing.Price) .. "!")
		toast(seller, "\u{1F4B0} " .. buyer.DisplayName .. " bought your " .. listing.Name .. " for $" .. formatMoney(listing.Price) .. "!")
	end)

	Players.PlayerRemoving:Connect(function(player)
		local booth = boothOwnedBy(player)
		if booth then
			releaseBooth(booth)
		end
	end)

	-- Periodically prune listings whose brainrot the seller no longer owns
	-- (sold at the sell stall, or traded away), so stands don't keep
	-- advertising phantom items until a buyer walks up and fails.
	task.spawn(function()
		while true do
			task.wait(3)
			for _, booth in ipairs(booths) do
				if booth.ownerUserId then
					local owner = Players:GetPlayerByUserId(booth.ownerUserId)
					local data = owner and PlayerDataManager.Get(owner)
					if data then
						local counts = {}
						local kept = {}
						local changed = false
						for _, listing in ipairs(booth.listings) do
							counts[listing.Name] = (counts[listing.Name] or 0) + 1
							if BrainrotMover.CountOwned(data, listing.Name) >= counts[listing.Name] then
								table.insert(kept, listing)
							else
								changed = true
							end
						end
						if changed then
							booth.listings = kept
							refreshDisplays(booth)
							pushManageState(booth)
						end
					end
				end
			end
		end
	end)

	print("BoothHandler online")
end

return BoothHandler
