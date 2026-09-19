
-- Made by @FlayoDev
--Place in ServerScriptService

local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DisplayRemote = ReplicatedStorage:FindFirstChild("DisplayGlobalAnnouncement")
if not DisplayRemote then
	DisplayRemote = Instance.new("RemoteEvent")
	DisplayRemote.Name = "DisplayGlobalAnnouncement"
	DisplayRemote.Parent = ReplicatedStorage
end

local MessagesGui = game:GetService("StarterGui").Messages

local ALLOWED_USER_IDS = {71510820} --> the only UserId(s) allowed to send announcements, edit this number
local GLOBAL_COMMAND = MessagesGui:GetAttribute("GlobalCommand") or "?global" --> chat command that broadcasts to every server
local LOCAL_COMMAND = MessagesGui:GetAttribute("LocalCommand") or "?local" --> chat command that broadcasts to this server only
local MESSAGING_TOPIC = MessagesGui:GetAttribute("MessagingTopic") or "GlobalAnnouncement"
local DISPLAY_DURATION = MessagesGui:GetAttribute("DisplayDuration") or 7 --> seconds the message stays fully visible

local NAME_COLORS = {
	Color3.fromRGB(255, 70, 73),
	Color3.fromRGB(255, 170, 60),
	Color3.fromRGB(255, 230, 80),
	Color3.fromRGB(90, 220, 120),
	Color3.fromRGB(80, 190, 255),
	Color3.fromRGB(190, 120, 255),
	Color3.fromRGB(255, 120, 200),
}                                             --Name color is randomly picked from this list

local VERIFIED_ICON = utf8.char(0xE000)

local random = Random.new()

local function isAllowed(player: Player): boolean
	return table.find(ALLOWED_USER_IDS, player.UserId) ~= nil
end

local function formatAnnouncement(player: Player, message: string): string
	local nameColor = NAME_COLORS[random:NextInteger(1, #NAME_COLORS)]
	local colorText = string.format(
		"rgb(%d,%d,%d)",
		nameColor.R * 255,
		nameColor.G * 255,
		nameColor.B * 255
	)

	return string.format(
		"<font color='%s'>%s</font>%s : %s",
		colorText,
		player.DisplayName,
		VERIFIED_ICON,
		message
	)
end

local function displayLocally(formattedMessage: string)
	DisplayRemote:FireAllClients(formattedMessage, DISPLAY_DURATION)
end

local function broadcastGlobally(formattedMessage: string)
	local success, err = pcall(function()
		MessagingService:PublishAsync(MESSAGING_TOPIC, formattedMessage)
	end)
	if not success then
		warn("[GlobalAnnouncementsServer] Failed to publish announcement:", err)
	end
end

local function parseCommand(chatMessage: string): (string?, string?)
	for _, command in {GLOBAL_COMMAND, LOCAL_COMMAND} do
		local prefix = command .. " "
		if chatMessage:sub(1, #prefix) == prefix then
			local body = chatMessage:sub(#prefix + 1)
			if body ~= "" then
				return command, body
			end
			return command, nil
		end
	end
	return nil, nil
end

local function onPlayerChatted(player: Player, chatMessage: string)
	if not isAllowed(player) then
		return
	end

	local command, message = parseCommand(chatMessage)
	if not command or not message then
		return
	end

	local formattedMessage = formatAnnouncement(player, message)

	if command == GLOBAL_COMMAND then
		broadcastGlobally(formattedMessage)
	elseif command == LOCAL_COMMAND then
		displayLocally(formattedMessage)
	end
end

local function onPlayerAdded(player: Player)
	player.Chatted:Connect(function(chatMessage)
		onPlayerChatted(player, chatMessage)
	end)
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

MessagingService:SubscribeAsync(MESSAGING_TOPIC, function(message)
	local formattedMessage = message.Data
	displayLocally(formattedMessage)
end)