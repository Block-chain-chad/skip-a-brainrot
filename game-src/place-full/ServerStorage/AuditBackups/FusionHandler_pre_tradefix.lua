-- Campfire Fusion: 5 identical UNPLACED brainrots (same name + same mutation)
-- fuse into 1 copy at the next mutation tier:
--
--     none -> Golden -> Diamond -> Rainbow -> Glitched
--
-- Rainbow and Glitched no longer drop from a throw (MutationConfig marks them
-- FusionOnly), so this ladder is now their ONLY source -- 125 plain copies of
-- one brainrot for a Rainbow, 625 for a Glitched. See the design note at the
-- top of ReplicatedStorage.Modules.MutationConfig for why.
--
-- Glitched is TERMINAL: it deliberately has no key in NEXT_MUTATION, so a fuse
-- request on Glitched copies falls into the "can't be fused further" branch
-- below and is rejected before anything is consumed.
--
-- The event mutations (Wet, Sandy, Electric, Frozen, Aurora, Celestial, Demon,
-- Angel) are intentionally absent from this map -- they stay terminal event
-- rewards and can be neither fused into nor fused from.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local InventoryHandler = require(ServerScriptService.Modules.InventoryHandler)
local SeasonPassHandler = require(ServerScriptService.Modules.SeasonPassHandler)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)

local remotes = ReplicatedStorage.Remotes

local FUSE_COUNT = 5
local CAMPFIRE_RANGE = 16

-- key = the mutation you hold ("" means none), value = what 5 of them become.
-- No "Glitched" key on purpose: that is the top of the ladder.
local NEXT_MUTATION = { [""] = "Golden", Golden = "Diamond", Diamond = "Rainbow", Rainbow = "Glitched" }

local validName = {}
for _, e in ipairs(BrainrotConfig) do validName[e.Name] = true end

local FusionHandler = {}

function FusionHandler.Init()
	remotes.FusionRequest.OnServerEvent:Connect(function(player, name, mutation)
		local data = PlayerDataManager.Get(player)
		if not data then return end
		if typeof(name) ~= "string" or not validName[name] then return end
		if mutation ~= nil and typeof(mutation) ~= "string" then return end
		if mutation == "" then mutation = nil end

		local result = remotes:FindFirstChild("PurchaseResult")
		local nextMut = NEXT_MUTATION[mutation or ""]
		if not nextMut then
			if result then result:FireClient(player, { Success = false, Message = "That mutation can't be fused further!" }) end
			return
		end

		-- must be at your own campfire
		local plot = PlayerDataManager.GetPlot(player)
		if not plot then return end
		local campfire = plot:FindFirstChild("Campfire", true)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not campfire or not hrp or (campfire.Position - hrp.Position).Magnitude > CAMPFIRE_RANGE then
			if result then result:FireClient(player, { Success = false, Message = "Stand by your campfire to fuse!" }) end
			return
		end

		-- collect 5 unplaced matching copies
		local matches = {}
		for i, e in ipairs(data.Brainrots) do
			if e.Name == name and e.PadIndex == nil and e.Mutation == mutation then
				table.insert(matches, i)
				if #matches >= FUSE_COUNT then break end
			end
		end
		if #matches < FUSE_COUNT then
			if result then result:FireClient(player, { Success = false, Message = ("Need %d unplaced copies to fuse!"):format(FUSE_COUNT) }) end
			return
		end

		-- remove back-to-front so indices stay valid, then add the fused one
		for i = #matches, 1, -1 do
			table.remove(data.Brainrots, matches[i])
		end
		table.insert(data.Brainrots, { Name = name, PadIndex = nil, Pending = 0, Mutation = nextMut, Uid = PlayerDataManager.TakeUid(data) })

		InventoryHandler.SyncBackpack(player)
		SeasonPassHandler.Notify(player, "Fuse", 1)
		PlayerDataManager.PushUpdate(player)
		if result then result:FireClient(player, { Success = true, Message = nextMut .. " " .. name .. " fused!" }) end
		remotes.FusionRequest:FireClient(player, { Name = name, NewMutation = nextMut })
	end)
	print("FusionHandler online")
end

return FusionHandler
