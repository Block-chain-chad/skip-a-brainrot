-- DevWeatherClient: registers the dev weather chat commands and forwards them to the server.
--
-- This half has NO authority. It cannot decide who is a developer and does not try -- the
-- allowlist lives in ServerScriptService.Modules.DevWeather, where a client cannot read or
-- reach it. All this does is turn typed text into a RemoteEvent call, so a non-dev typing
-- any of these simply gets silence. Adding more client commands therefore adds no security
-- surface: every one of them lands on the same gated remote.
--
-- Registered on the CLIENT because TextChatCommand.Triggered is only reliably raised on the
-- client that typed the message.
--
-- AutocompleteVisible is false throughout so these do not appear in every player's chat
-- autocomplete. That is discoverability, not security.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local request = remotes:WaitForChild("DevWeatherRequest", 20)
if not request then return end

local commands = TextChatService:FindFirstChild("TextChatCommands")
if not commands then
	commands = Instance.new("Folder")
	commands.Name = "TextChatCommands"
	commands.Parent = TextChatService
end

-- One dedicated command per event, plus the general /wx form.
--   { primary, secondary, argument sent to the server }
-- The argument is the EXACT event name from WeatherHandler.EVENTS -- ApplyByName does
-- accept prefixes, but sending the full name means a future event whose name shares a
-- prefix cannot silently steal one of these shortcuts.
-- No "/clear": confirmed taken -- Roblox's own RBXClearCommand already owns /clear and
-- /cls. The wipe is "/wxoff" instead (and "/wx clear" still works).
-- Also avoided for the same reason: /e /m /t /w /v /? and /console.
local COMMANDS = {
	{ "/fog",           nil,             "Fog" },
	{ "/sandstorm",     "/sand",         "Sandstorm" },
	{ "/thunderstorm",  "/storm",        "Thunderstorm" },
	{ "/blizzard",      "/snow",         "Blizzard" },
	{ "/aurora",        nil,             "Aurora" },
	{ "/shootingstar",  "/star",         "Shooting Star" },
	{ "/bloodmoon",     "/moon",         "Blood Moon" },
	{ "/goldenhour",    "/golden",       "Golden Hour" },
	{ "/wxoff",         "/clearweather", "clear" },
}

-- Wipe any previous registration so a re-run does not leave duplicates behind.
-- Pattern match, not sub(1, 9): "DevWeather" is TEN characters, so comparing a 9-char slice
-- against it never matched and the cleanup silently did nothing.
for _, c in ipairs(commands:GetChildren()) do
	if c:IsA("TextChatCommand") and c.Name:find("^DevWeather") then
		c:Destroy()
	end
end

for i, spec in ipairs(COMMANDS) do
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "DevWeatherEvent" .. i
	cmd.PrimaryAlias = spec[1]
	if spec[2] then cmd.SecondaryAlias = spec[2] end
	cmd.AutocompleteVisible = false
	cmd.Enabled = true
	cmd.Parent = commands
	local arg = spec[3]
	cmd.Triggered:Connect(function()
		request:FireServer(arg)
	end)
end

-- the general form, kept so "/wx list" and partial names still work
local wx = Instance.new("TextChatCommand")
wx.Name = "DevWeatherCommand"
wx.PrimaryAlias = "/wx"
wx.SecondaryAlias = "/weather"
wx.AutocompleteVisible = false
wx.Enabled = true
wx.Parent = commands
wx.Triggered:Connect(function(_, message)
	-- message is the WHOLE line including the alias, so strip the first word
	local arg = tostring(message):match("^%s*%S+%s+(.*)$") or ""
	request:FireServer(arg)
end)
