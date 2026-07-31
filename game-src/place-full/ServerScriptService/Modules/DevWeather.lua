-- DevWeather: developer-only shortcuts for forcing a weather event, so each one can be
-- tested without waiting out the 20-minute cooldown and a 50% roll.
--
-- ============================== WHY THIS IS GATED ==============================
-- Weather is GLOBAL and it is not cosmetic: every event is the only source of its paired
-- mutation (MutationConfig.Events), and those mutations multiply a brainrot's cash by up to
-- x95. An ungated command would let any player mint Demon and Angel brainrots on demand and
-- flatten the whole mutation economy. So the allowlist check happens HERE, on the server,
-- and the client half can only ask.
--
-- The client registers the chat command and fires a RemoteEvent; this module decides. That
-- split is deliberate: TextChatCommand.Triggered is only reliably raised on the client that
-- typed it, so a server-side-only command registration cannot be depended on. Putting the
-- authority here means it does not matter where the request comes from.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WeatherHandler = require(ServerScriptService.Modules.WeatherHandler)
local remotes = ReplicatedStorage.Remotes

-- ============================== THE ALLOWLIST ==============================
-- Add your friends' UserIds here. Keep this module in ServerScriptService so clients can
-- never read the list, the same reason Modules.CodeConfig lives server-side.
local ALLOWED = {
	[125861722] = true,   -- yeep1234
}

local DevWeather = {}

local function isDev(player)
	if ALLOWED[player.UserId] then return true end
	-- the place owner always counts. CreatorType is checked because a GROUP-owned place has
	-- no single owner UserId, and game.CreatorId would then be a group id -- matching a
	-- player's UserId against it could authorise the wrong person entirely.
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
		return true
	end
	return false
end

local function reply(player, ok, msg)
	local r = remotes:FindFirstChild("PurchaseResult")
	if r then r:FireClient(player, { Success = ok, Message = msg }) end
end

function DevWeather.Init()
	local request = remotes:FindFirstChild("DevWeatherRequest")
	if not request then
		request = Instance.new("RemoteEvent")
		request.Name = "DevWeatherRequest"
		request.Parent = remotes
	end

	request.OnServerEvent:Connect(function(player, arg)
		-- gate FIRST, before any parsing, and stay silent for non-devs: an "unauthorised"
		-- reply would advertise that the command exists to everyone who guesses it.
		if not isDev(player) then return end
		if typeof(arg) ~= "string" then
			reply(player, false, "usage: /wx <event>  |  /wx clear  |  /wx list")
			return
		end
		local want = arg:gsub("^%s+", ""):gsub("%s+$", "")
		if want == "" or want:lower() == "list" then
			reply(player, true, "events: " .. table.concat(WeatherHandler.EventNames(), ", ") .. ", clear")
			return
		end
		-- Long fixed duration: a forced event is for testing, and the normal 4-7 minute
		-- random roll would end it mid-inspection.
		local ok, applied = WeatherHandler.ApplyByName(want, 600)
		if ok then
			print(("[DevWeather] %s forced '%s'"):format(player.Name, applied))
			reply(player, true, ("\u{26C5} %s forced for 10 minutes"):format(applied))
		else
			reply(player, false, ("no event matching '%s'. try: %s, clear")
				:format(want, table.concat(WeatherHandler.EventNames(), ", ")))
		end
	end)

	print(("DevWeather online (%d allowlisted)"):format((function()
		local n = 0
		for _ in pairs(ALLOWED) do n += 1 end
		return n
	end)()))
end

return DevWeather
