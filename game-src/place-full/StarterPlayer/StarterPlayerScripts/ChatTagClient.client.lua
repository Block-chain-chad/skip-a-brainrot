--!strict
--[[ =========================================================================
ChatTagClient -- puts a player's earned season-pass title in front of what they
say, in parentheses:  (Pro Rock Skipper) SomePlayer: hello
---------------------------------------------------------------------------
This place runs the modern TextChatService (ChatVersion == TextChatService), so
the hook is OnIncomingMessage: it runs on the RECEIVING client for every message
and may return a TextChatMessageProperties whose PrefixText replaces the default
"Name:" prefix. Returning nil leaves the message untouched.

The title is read off the SPEAKER's `EquippedTag` attribute, which
SeasonPassHandler publishes and which replicates to every client -- so this works
for other people's messages, not just your own, with no remote of its own.
========================================================================= ]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local TAG_COLOUR = "#FFD678"   -- same warm gold the overhead plate uses

TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local source = message.TextSource
	if not source then return nil end   -- system message, not a player

	local player = Players:GetPlayerByUserId(source.UserId)
	if not player then return nil end

	local label = player:GetAttribute("EquippedTag")
	if type(label) ~= "string" or label == "" then return nil end

	local props = Instance.new("TextChatMessageProperties")
	-- message.PrefixText is already "Name:" (or a decorated form of it), so
	-- prepending keeps whatever the default chat wanted to show and only adds
	-- the title in front of it.
	props.PrefixText = string.format('<font color="%s">(%s)</font> %s',
		TAG_COLOUR, label, message.PrefixText)
	return props
end
