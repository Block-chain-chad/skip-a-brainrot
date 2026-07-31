-- DialogueConfig: what the world's NPCs say.
--
-- Keyed by the NpcId attribute on the character model, so an NPC can be moved, renamed
-- or rebuilt without touching its lines. Lines is an ordered list -- talking to someone
-- again advances through it and then holds on the last entry, which is what lets a quest
-- later swap in a different list per stage without changing any of the display code.
--
-- Shared so the client can render a line the instant the server names it, rather than
-- shipping the text over the wire on every interaction.

local DialogueConfig = {}

DialogueConfig.NPCS = {
	Gianluca = {
		Name = "stupid gianluca",
		PromptAction = "Talk",
		-- how long the speech bubble and the on-screen box stay up
		Hold = 5.0,
		Colour = Color3.fromRGB(255, 186, 92),
		Lines = {
			"AAARGGGHHH!!! I CANT FIND MY CHIM!!!",
		},
	},
}

function DialogueConfig.Get(npcId)
	return DialogueConfig.NPCS[npcId]
end

-- index is 1-based and clamps to the last line, so repeat interactions never error and
-- never wrap back to the start
function DialogueConfig.LineAt(npcId, index)
	local e = DialogueConfig.NPCS[npcId]
	if not e or #e.Lines == 0 then return nil end
	return e.Lines[math.clamp(index or 1, 1, #e.Lines)]
end

return DialogueConfig
