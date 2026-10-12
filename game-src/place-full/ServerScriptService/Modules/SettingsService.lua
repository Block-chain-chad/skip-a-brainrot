-- SettingsService: validates and persists the Settings panel's preferences
-- (kit README §3.3) into data.Settings. ONE remote: SettingsSave (RemoteEvent,
-- client->server, fire-and-forget -- see GameHUDPanels.SettingsPanel's
-- slider/segmented/toggle wiring). Self-heals the remote under
-- ReplicatedStorage.Remotes on Init() rather than assuming it was hand-built
-- in Studio, same spirit as this file's own creation.
--
-- WHITELIST DISCIPLINE: the keys the kit's Settings panel writes (music, sfx,
-- quality, fastSpin, hideOwnBanners, cinematicReducedMotion, cinematicLowQuality,
-- quickThrow, skipReveal), plus the two HUD collapses
-- (navHidden, questsHidden) documented at their branch below. Anything else in the
-- payload is silently dropped (warn + skip that ONE key -- a malformed or
-- hostile client sending {Cash=999} alongside a legit {music=0.5} must not
-- lose the legit half of the update, and must never be able to touch a
-- field outside data.Settings). Numeric fields (music/sfx) are CLAMPED into
-- [0,1] rather than rejected outright -- an out-of-range value is still a
-- real intent ("turn it up/down"), so clamping preserves the direction
-- instead of discarding the whole update. quality and the booleans
-- (fastSpin/hideOwnBanners) are type+enum checked and dropped (not
-- coerced) on mismatch. skipReveal is a TABLE of {TierName = bool} --
-- rebuilt against the RarityConfig tier whitelist rather than trusted,
-- and replaced whole on every write (the panel always sends all chips).
-- (v1 note: a single boolean `skipAnimations` shipped briefly on
-- 2026-08-04 and was superseded the same day by per-rarity skipReveal;
-- the old field may linger inertly in old saves, and the panel migrates
-- it client-side to all-rarities-on.)
--
-- QUALITY ENUM DEVIATION: the task brief spells this enum
-- {"Low","Med","High"}, but StarterPlayerScripts.GameHUDClient's own
-- ctx.state.settings default (shipped Task 3, already live/committed) is
-- `quality = "Medium"`, and the kit's own settings.png capture labels the
-- middle button "Medium" in full. Validating against "Med" would reject
-- that pre-existing default the instant a client round-trips it, so this
-- module validates "Medium" (not "Med") for consistency with what Task 3
-- already shipped and what the kit literally shows on screen. Documented
-- deviation; see task-10-report.md.
--
-- REDEEM CODE: the kit's Settings footer also draws a "Redeem Code" button,
-- and the task brief asks for a stub RemoteFunction named "RedeemCode" here
-- that always answers `false, "Invalid code"`. That name is NOT free --
-- ReplicatedStorage.Remotes.RedeemCode already exists, as a RemoteEvent,
-- wired end-to-end to a REAL promo-code system (ServerScriptService.Modules.
-- DailyRewardHandler.redeemCode + ServerScriptService.Modules.CodeConfig's 4
-- live codes), already used by the legacy DailyRewardClient UI. A second
-- same-named instance would make every `remotes.RedeemCode` lookup in the
-- game ambiguous, and a permanently-failing stub would be a real regression
-- for a player who types a genuine code into the NEW panel instead of the
-- old one. SettingsPanel therefore fires the EXISTING RedeemCode remote
-- directly -- nothing added here. Documented deviation; see
-- task-10-report.md.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)
local RarityConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RarityConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local QUALITY_VALUES = { Low = true, Medium = true, High = true }

local SettingsService = {}

-- RATE LIMIT WITHOUT LOSING INTENT. At most one applied write per player per
-- window; anything arriving inside the window is COALESCED into a pending payload
-- and flushed when the window expires, rather than dropped.
--
-- This used to be a bare `return` on the debounce, and with a single settings panel
-- that was invisible: you cannot drag two sliders at once. Two independent HUD
-- collapse buttons broke it immediately (2026-08-07) -- press HIDE UI and the quest
-- toggle in quick succession and the second one applies on screen, fires, and is
-- thrown away, so the client shows one thing and the save holds another. The player
-- finds out on their next join, when the HUD comes back wrong.
--
-- Coalescing keeps the real protection (a client firing in a loop still cannot make
-- us apply+push in a loop) while honouring the last value for every key it sent.
local SAVE_WINDOW = 0.5
local lastSave = {}  -- [player] = os.clock() of the last APPLIED write
local pending = {}   -- [player] = merged payload awaiting flush (nil = none scheduled)

local function clamp01(n)
	if type(n) ~= "number" or n ~= n then
		return nil -- reject NaN/non-numbers outright, nothing sane to clamp
	end
	return math.clamp(n, 0, 1)
end

-- Validates ONE payload table against the whitelist. Returns a NEW table
-- containing only the keys that passed (clamped/typed) -- never mutates
-- `tbl`. Exposed so the fresh-clone whitelist probe (task brief Step 5) can
-- call it directly on a fabricated table without touching a live player:
-- rejects {Cash=999}, accepts {music=0.5}, clamps {sfx=99}->1.
function SettingsService._Validate(tbl)
	local out = {}
	if type(tbl) ~= "table" then
		return out
	end
	for key, value in pairs(tbl) do
		if key == "music" or key == "sfx" then
			local v = clamp01(value)
			if v then
				out[key] = v
			else
				warn("[SettingsService] dropped invalid " .. key .. ": " .. tostring(value))
			end
		elseif key == "quality" then
			if type(value) == "string" and QUALITY_VALUES[value] then
				out.quality = value
			else
				warn("[SettingsService] dropped invalid quality: " .. tostring(value))
			end
		-- navHidden / questsHidden (2026-08-07): the two independent HUD collapses.
		-- navHidden folds the rail and the teleport tabs; questsHidden folds the quest
		-- bar and tracker. They live in Settings rather than their own save fields so
		-- they ride the same validated round trip as every other preference -- and this
		-- whitelist is why it matters: an unlisted key is dropped with a warning, so a
		-- setting not named here silently never persists.
		--
		-- (An earlier single "hudHidden" key is deliberately NOT listed. It hid the
		-- currency and luck too, which is no longer wanted; any profile still carrying
		-- it simply keeps a value nothing reads.)
		elseif key == "fastSpin" or key == "hideOwnBanners"
			or key == "navHidden" or key == "questsHidden"
			-- cinematicReducedMotion / cinematicLowQuality (task 8, Massive Catch
			-- Cinematic): SettingsPanel's two new toggle rows, same shape as
			-- fastSpin/hideOwnBanners -- a live player Attribute write plus this
			-- validated round trip so the preference survives a rejoin.
			or key == "cinematicReducedMotion" or key == "cinematicLowQuality"
			-- quickThrow (2026-09-21, throw-pacing pass): Settings > Gameplay "Quick
			-- Throw" -- no stone-tracking camera, the reward lands the moment the server
			-- confirms it. Same shape as the two cinematic toggles above; ThrowCam reads
			-- the live player attribute the panel writes.
			or key == "quickThrow" then
			if type(value) == "boolean" then
				out[key] = value
			else
				warn("[SettingsService] dropped invalid " .. key .. ": " .. tostring(value))
			end
		elseif key == "skipReveal" then
			if type(value) == "table" then
				local t = {}
				for _, tier in ipairs(RarityConfig) do
					if type(value[tier.Name]) == "boolean" then t[tier.Name] = value[tier.Name] end
				end
				out.skipReveal = t
			else
				warn("[SettingsService] dropped invalid skipReveal: " .. tostring(value))
			end
		else
			warn("[SettingsService] dropped unknown key: " .. tostring(key))
		end
	end
	return out
end

-- Validates + merges directly into `data.Settings` (creating it if absent).
-- Returns the validated subset that was actually written, so the caller can
-- tell "nothing survived validation" (empty table) from "wrote something".
-- Exposed for the round-trip probe: a fabricated `{Settings = {}}` data
-- table in, a mixed valid/invalid payload, and data.Settings only carries
-- the valid half afterward.
function SettingsService._Apply(data, tbl)
	local valid = SettingsService._Validate(tbl)
	if next(valid) == nil then
		return valid
	end
	data.Settings = data.Settings or {}
	for k, v in pairs(valid) do
		data.Settings[k] = v
	end
	return valid
end

local function applyNow(player, tbl)
	local data = PlayerDataManager.Get(player)
	if not data then
		return
	end
	local valid = SettingsService._Apply(data, tbl)
	if next(valid) ~= nil then
		-- Echoes data.Settings back via DataUpdated -- SettingsPanel's own
		-- top-level listener re-applies it, closing the round trip.
		PlayerDataManager.PushUpdate(player)
	end
end

local function onSettingsSave(player, tbl)
	if type(tbl) ~= "table" then return end
	local now = os.clock()
	local last = lastSave[player]

	if last and now - last < SAVE_WINDOW then
		local queued = pending[player]
		if queued then
			-- A flush is already scheduled; fold this payload into it. Later keys win,
			-- which is what someone mashing one toggle expects: the last press sticks.
			for k, v in pairs(tbl) do queued[k] = v end
			return
		end
		-- Copy rather than keep the client's table: it is the one reference we hold
		-- across a yield, and _Validate must stay the thing that decides its contents.
		queued = {}
		for k, v in pairs(tbl) do queued[k] = v end
		pending[player] = queued

		task.delay(SAVE_WINDOW - (now - last), function()
			local payload = pending[player]
			pending[player] = nil
			-- Parent check: they may have left during the wait, and writing into a
			-- profile that is already being released is worse than losing a preference
			-- for someone who is gone.
			if payload and player.Parent then
				lastSave[player] = os.clock()
				applyNow(player, payload)
			end
		end)
		return
	end

	lastSave[player] = now
	applyNow(player, tbl)
end

function SettingsService.Init()
	local save = remotes:FindFirstChild("SettingsSave")
	if not save then
		save = Instance.new("RemoteEvent")
		save.Name = "SettingsSave"
		save.Parent = remotes
	end
	save.OnServerEvent:Connect(onSettingsSave)
	Players.PlayerRemoving:Connect(function(p)
		lastSave[p] = nil
		pending[p] = nil
	end)
	print("SettingsService online")
end

return SettingsService
