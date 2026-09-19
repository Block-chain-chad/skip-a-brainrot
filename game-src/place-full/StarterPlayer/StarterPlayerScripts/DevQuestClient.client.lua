-- DevQuestClient: registers /tq and forwards it to the server.
--
-- No authority whatsoever, exactly like DevWeatherClient: the allowlist lives in
-- ServerScriptService.Modules.DevQuest where no client can reach it, so a non-dev typing
-- /tq simply gets silence. Registered on the CLIENT because TextChatCommand.Triggered is
-- only reliably raised on the client that typed the message.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local request = remotes:WaitForChild("DevQuestRequest", 20)
if not request then return end

local commands = TextChatService:FindFirstChild("TextChatCommands")
if not commands then
	commands = Instance.new("Folder")
	commands.Name = "TextChatCommands"
	commands.Parent = TextChatService
end

-- wipe any previous registration so a re-run leaves no duplicates
for _, c in ipairs(commands:GetChildren()) do
	if c:IsA("TextChatCommand") and c.Name:find("^DevQuest") then c:Destroy() end
end

local cmd = Instance.new("TextChatCommand")
cmd.Name = "DevQuestCommand"
cmd.PrimaryAlias = "/tq"
cmd.SecondaryAlias = "/tundraquest"
cmd.AutocompleteVisible = false
cmd.Enabled = true
cmd.Parent = commands
cmd.Triggered:Connect(function(_, message)
	-- message is the whole line including the alias; everything after the first word is
	-- the argument, and a bare "/tq" correctly sends ""
	local arg = tostring(message):match("^%s*%S+%s+(.*)$") or ""
	request:FireServer(arg)
end)
