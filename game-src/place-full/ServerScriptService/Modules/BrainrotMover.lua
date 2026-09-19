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

-- Both camps: the same brainrot is rendered on each of the player's plots, so removing
-- it from one and not the other leaves a ghost standing on the world they are not in.
function BrainrotMover.RemovePadVisual(player, padIndex)
	if not padIndex then return end
	for _, plot in ipairs(PlayerDataManager.GetPlots(player)) do
		local pads = plot:FindFirstChild("Pads")
		if pads then
			for _, child in ipairs(pads:GetChildren()) do
				if child:GetAttribute("PadIndex") == padIndex then
					child:Destroy()
					break
				end
			end
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
	local record = { Name = entry.Name, Mutation = entry.Mutation, Serial = entry.Serial, MintedAt = entry.MintedAt }
	PlayerDataManager.DrainPending(giver, entry, giverData)
	BrainrotMover.RemovePadVisual(giver, entry.PadIndex)
	table.remove(giverData.Brainrots, bestIndex)
	return record
end

-- Removes the brainrot with THIS EXACT Uid and returns its record.
--
-- WHY THIS EXISTS ALONGSIDE Take(). Take resolves by NAME and deliberately takes
-- the least valuable match, which is right for a trade offer ("one Broccolo
-- Torpedo") and WRONG for gifting: the player is holding one specific copy, and
-- name-matching would hand over their plain one while the Rainbow they are
-- actually holding stays put. A gift has to move the thing in your hand.
--
-- Uid is per-player and unique, so this cannot be ambiguous the way a name is.
-- Same pending-drain and pad-visual removal as Take, so the two paths leave the
-- giver in identical shape.
function BrainrotMover.TakeByUid(giver, giverData, uid)
	if uid == nil then return nil end
	for i, entry in ipairs(giverData.Brainrots) do
		if entry.Uid == uid then
			local record = {
				Name = entry.Name, Mutation = entry.Mutation,
				Serial = entry.Serial, MintedAt = entry.MintedAt, Size = entry.Size,
			}
			PlayerDataManager.DrainPending(giver, entry, giverData)
			BrainrotMover.RemovePadVisual(giver, entry.PadIndex)
			table.remove(giverData.Brainrots, i)
			return record
		end
	end
	return nil
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
--   GiftService  (2026-08-07)  -- checked twice: when the offer is made AND again
--                                 when it is accepted, since the receiver can catch
--                                 a second copy while the popup is on their screen
-- Add a new transfer path and you must add the check there too; Give stays total.
function BrainrotMover.Give(receiver, receiverData, record)
	if type(record) == "string" then record = { Name = record } end
	if not record or not record.Name then return end

	local padIndex = PlayerDataManager.FindFreePad(receiverData)
	local uid = PlayerDataManager.TakeUid(receiverData)
	table.insert(receiverData.Brainrots, {
		Name = record.Name,
		Mutation = record.Mutation,   -- <- was silently dropped before; the whole bug
		Serial = record.Serial,       -- mint identity travels with the item...
		MintedAt = record.MintedAt,   -- ...or the serial dies on every trade
		PadIndex = padIndex,
		Pending = 0,
		Uid = uid,
	})
	if padIndex then
		for _, plot in ipairs(PlayerDataManager.GetPlots(receiver)) do
			BrainrotSpawner.Spawn(plot, record.Name, padIndex, record.Mutation, uid, record.Size)
		end
	end
end

return BrainrotMover
