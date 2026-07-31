-- BrainrotMover (Trading Center section)
-- Shared helpers for moving brainrots between players' inventories and
-- keeping the plot pad visuals in sync. Used by TradeHandler and BoothHandler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local BrainrotSpawner = require(ServerScriptService.Modules.BrainrotSpawner)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local Mutations = require(ReplicatedStorage.Modules.MutationConfig)

local BrainrotMover = {}

BrainrotMover.InfoByName = {}
for _, entry in ipairs(BrainrotConfig) do
	BrainrotMover.InfoByName[entry.Name] = entry
end
BrainrotMover.TierByName = {}
for _, tier in ipairs(RarityConfig) do
	BrainrotMover.TierByName[tier.Name] = tier
end

-- Is this name flagged one-per-player in BrainrotConfig?
function BrainrotMover.IsUnique(name)
	local info = BrainrotMover.InfoByName[name]
	return (info and info.Unique) == true
end

-- Cap test for Unique items, netting a transfer in both directions so a straight
-- one-for-one swap of the same unique item still succeeds (you end on 1, not 2).
--   have     = how many the RECEIVER holds right now
--   outgoing = how many the receiver is simultaneously giving away
--   incoming = how many are arriving
-- Always true for non-unique names, so callers can apply it unconditionally.
function BrainrotMover.WithinUniqueCap(name, have, outgoing, incoming)
	if not BrainrotMover.IsUnique(name) then return true end
	return ((have or 0) - (outgoing or 0) + (incoming or 0)) <= 1
end

function BrainrotMover.CountOwned(data, name)
	local n = 0
	for _, entry in ipairs(data.Brainrots) do
		if entry.Name == name then n += 1 end
	end
	return n
end

function BrainrotMover.RemovePadVisual(player, padIndex)
	if not padIndex then return end
	local plot = PlayerDataManager.GetPlot(player)
	if not plot then return end
	local pads = plot:FindFirstChild("Pads")
	if not pads then return end
	for _, child in ipairs(pads:GetChildren()) do
		if child:GetAttribute("PadIndex") == padIndex then
			child:Destroy()
			break
		end
	end
end

-- NOTE: SpawnOnPlot was deleted. It was a SECOND, divergent spawn path that did not
-- set the Uid attribute or a StorePrompt, so anything received by trade/booth could
-- never be stored, sold or re-traded. Everything now routes through BrainrotSpawner.

-- Removes ONE brainrot with this name from the giver (data + plot visual) and
-- RETURNS THE RECORD that was removed, so the caller can hand the SAME item over.
--
-- Offers are name-based, so a name can match several copies with different
-- mutations. We deliberately take the LEAST valuable match: offering a plain
-- "Broccolo Torpedo" must never consume your Rainbow one off its pad.
function BrainrotMover.Take(giver, giverData, name)
	local bestIndex, bestMult
	for i, entry in ipairs(giverData.Brainrots) do
		if entry.Name == name then
			local mult = Mutations.Mult(entry.Mutation)
			if not bestMult or mult < bestMult then
				bestIndex, bestMult = i, mult
			end
		end
	end
	if not bestIndex then return nil end

	local entry = giverData.Brainrots[bestIndex]
	local record = { Name = entry.Name, Mutation = entry.Mutation }
	PlayerDataManager.DrainPending(giver, entry, giverData)
	BrainrotMover.RemovePadVisual(giver, entry.PadIndex)
	table.remove(giverData.Brainrots, bestIndex)
	return record
end

-- Gives ONE brainrot to the receiver (data + plot visual if a pad is free).
-- Pass the RECORD returned by Take so the mutation travels with the item; a bare
-- name string is still accepted for any legacy caller.
--
-- DELIBERATELY DOES NOT ENFORCE THE UNIQUE CAP. Take() has already mutated the giver
-- by the time Give runs, so refusing here would delete the item mid-transfer -- the
-- giver loses it and the receiver never gets it. The cap is therefore checked
-- PRE-FLIGHT by every caller, where a rejection can still fail safely:
--   TradeHandler.executeTrade  -- in the existing validation block, before any Take
--   BoothHandler  BoothBuy     -- alongside the cash/ownership checks, before the Take
--   GianlucaQuest.grantChim    -- before inserting the quest reward
-- Add a new transfer path and you must add the check there too; Give stays total.
function BrainrotMover.Give(receiver, receiverData, record)
	if type(record) == "string" then record = { Name = record } end
	if not record or not record.Name then return end

	local padIndex = PlayerDataManager.FindFreePad(receiverData)
	local uid = PlayerDataManager.TakeUid(receiverData)
	table.insert(receiverData.Brainrots, {
		Name = record.Name,
		Mutation = record.Mutation,   -- <- was silently dropped before; the whole bug
		PadIndex = padIndex,
		Pending = 0,
		Uid = uid,
	})
	if padIndex then
		local plot = PlayerDataManager.GetPlot(receiver)
		if plot then
			BrainrotSpawner.Spawn(plot, record.Name, padIndex, record.Mutation, uid)
		end
	end
end

return BrainrotMover
