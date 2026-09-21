-- NpcTalk -- turns an NpcDialogue table into ONE conversation for MerchantDialog.
--
-- Pure logic, no instances, no services: the client (GianlucaClient) owns the
-- per-player memory table and the quest context, calls Next(), shows the result with
-- MerchantDialog.Show(name, lines, accent, onDone, anchor, label), and calls
-- Remember() when the box actually opened. Deterministic, so the harness can walk a
-- whole relationship (first meeting, returns, quest stages) without Roblox.
--
--   local r = NpcTalk.Next(dialogue, memory, { questState = 0, hasChim = false, userId = 123 })
--   r.lines      the strings to show, in order
--   r.label      the primary button text
--   r.action     nil | "start" | "handover"  (what the primary button fires)
--   r.reaction   nil | reaction id for the body driver (set NpcReaction on the model)
--   r.tags       the tags of the lines shown
--   r.kind       "first" | "return" | "searching" | "holding" | "done"
--
-- Written in Lua 5.1-compatible syntax on purpose (the harness runs it under plain Lua).

local NpcTalk = {}
NpcTalk.Version = 1

local function textOf(entry)
	if type(entry) == "table" then return entry[1] or entry.text end
	return entry
end

local function tagOf(entry)
	if type(entry) == "table" then return entry.tag end
	return nil
end

-- a stable pick per player: the same greeting every time THIS player meets him
local function pickFor(list, userId)
	local n = #list
	if n == 0 then return nil end
	local id = tonumber(userId) or 0
	return list[(math.floor(math.abs(id)) % n) + 1]
end

-- rotate through a list with a cursor kept in memory; every entry is heard once per lap
local function rotate(list, memory, key)
	local n = #list
	if n == 0 then return nil end
	local i = (memory[key] or 0) % n + 1
	memory[key] = i
	return list[i]
end

local function reactionFor(dialogue, tags)
	local map = dialogue.reactions or {}
	for _, t in ipairs(tags) do
		if t and map[t] then return map[t] end
	end
	return nil
end
NpcTalk.ReactionFor = reactionFor

-- Fresh memory for one player (the client keeps one per session).
function NpcTalk.NewMemory()
	return { met = false, talks = 0, loreCursor = 0, returnCursor = 0, guidanceCursor = 0 }
end

function NpcTalk.Next(dialogue, memory, ctx)
	memory = memory or NpcTalk.NewMemory()
	ctx = ctx or {}
	local q = dialogue.quest or {}
	local questState = tonumber(ctx.questState) or 0
	local lines, tags = {}, {}
	local function add(entry)
		if entry == nil then return end
		lines[#lines + 1] = textOf(entry)
		tags[#tags + 1] = tagOf(entry) or false
	end
	local function addAll(list)
		for _, e in ipairs(list or {}) do add(e) end
	end

	local kind, label, action
	local met = memory.met or questState > 0          -- the quest state stands in for "met before" across sessions
	if ctx.hasChim and q.holding then
		kind = "holding"
		add(rotate(dialogue.returning, memory, "returnCursor"))
		addAll(q.holding.lines)
		label, action = q.holding.label, q.holding.action
	elseif not met then
		kind = "first"
		add(pickFor(dialogue.greetings, ctx.userId))
		if q.offer and questState == 0 then
			addAll(q.offer.lines)
			label, action = q.offer.label, q.offer.action
		else
			add(rotate(dialogue.guidance, memory, "guidanceCursor"))
		end
	elseif questState == 1 and q.searching then
		kind = "searching"
		add(rotate(dialogue.returning, memory, "returnCursor"))
		addAll(q.searching.lines)
		label, action = q.searching.label, q.searching.action
	elseif questState == 3 and q.done and not memory.thankedForChim then
		kind = "done"
		addAll(q.done.lines)
		label, action = q.done.label, q.done.action
	else
		kind = "return"
		add(rotate(dialogue.returning, memory, "returnCursor"))
		local every = dialogue.guidanceEvery or 3
		if every > 0 and (memory.talks + 1) % every == 0 and #(dialogue.guidance or {}) > 0 then
			add(rotate(dialogue.guidance, memory, "guidanceCursor"))
		else
			add(rotate(dialogue.lore, memory, "loreCursor"))
		end
	end
	if #lines == 0 then lines[1] = "..." end
	return {
		kind = kind, lines = lines, tags = tags, label = label or "OK ▶", action = action,
		reaction = reactionFor(dialogue, tags), accent = dialogue.accent, name = dialogue.name or dialogue.id,
	}
end

-- Call when the conversation was actually shown (not when the prompt merely fired).
function NpcTalk.Remember(memory, result)
	memory.met = true
	memory.talks = (memory.talks or 0) + 1
	if result and result.kind == "done" then memory.thankedForChim = true end
	return memory
end

-- A server note (GianlucaState.Note) -> the popup to show, or nil for unknown notes.
function NpcTalk.Note(dialogue, note)
	local n = dialogue.quest and dialogue.quest.notes and dialogue.quest.notes[note]
	if not n then return nil end
	return { name = n.name or dialogue.name, lines = n.lines, label = n.label or "OK ▶", accent = dialogue.accent }
end

-- Every line of the table, flattened, for lints / tests (voice rules live in the tests).
function NpcTalk.AllLines(dialogue)
	local out = {}
	local function take(list) for _, e in ipairs(list or {}) do out[#out + 1] = textOf(e) end end
	take(dialogue.greetings); take(dialogue.returning); take(dialogue.lore); take(dialogue.guidance)
	local q = dialogue.quest or {}
	for _, k in ipairs({ "offer", "searching", "holding", "done" }) do if q[k] then take(q[k].lines) end end
	for _, n in pairs(q.notes or {}) do take(n.lines) end
	return out
end

return NpcTalk
