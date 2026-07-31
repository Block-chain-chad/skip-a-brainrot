-- SettingsService: validates and persists the Settings panel's preferences
-- (kit README §3.3) into data.Settings. ONE remote: SettingsSave (RemoteEvent,
-- client->server, fire-and-forget -- see GameHUDPanels.SettingsPanel's
-- slider/segmented/toggle wiring). Self-heals the remote under
-- ReplicatedStorage.Remotes on Init() rather than assuming it was hand-built
-- in Studio, same spirit as this file's own creation.
--
-- WHITELIST DISCIPLINE: exactly the 5 keys the kit's Settings panel writes
-- (music, sfx, quality, fastSpin, hideOwnBanners). Anything else in the
-- payload is silently dropped (warn + skip that ONE key -- a malformed or
-- hostile client sending {Cash=999} alongside a legit {music=0.5} must not
-- lose the legit half of the update, and must never be able to touch a
-- field outside data.Settings). Numeric fields (music/sfx) are CLAMPED into
-- [0,1] rather than rejected outright -- an out-of-range value is still a
-- real intent ("turn it up/down"), so clamping preserves the direction
-- instead of discarding the whole update. quality/fastSpin/hideOwnBanners
-- are type+enum checked and dropped (not coerced) on mismatch.
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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataManager = require(ServerScriptService.Modules.PlayerDataManager)

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local QUALITY_VALUES = { Low = true, Medium = true, High = true }

local SettingsService = {}

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
		elseif key == "fastSpin" or key == "hideOwnBanners" then
			if type(value) == "boolean" then
				out[key] = value
			else
				warn("[SettingsService] dropped invalid " .. key .. ": " .. tostring(value))
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

local function onSettingsSave(player, tbl)
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

function SettingsService.Init()
	local save = remotes:FindFirstChild("SettingsSave")
	if not save then
		save = Instance.new("RemoteEvent")
		save.Name = "SettingsSave"
		save.Parent = remotes
	end
	save.OnServerEvent:Connect(onSettingsSave)
	print("SettingsService online")
end

return SettingsService
