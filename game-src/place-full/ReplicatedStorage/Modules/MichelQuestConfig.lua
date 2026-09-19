-- MichelQuestConfig -- Michael the eagle's questline, in the Frozen Tundra (World 2).
--
-- NAMING: he is "Michael" to the player, everywhere. The scripts, remotes, instances and
-- saved fields are all still spelled Michel* -- data.MichelQuest and data.MichelGiven are
-- PERSISTED keys, so renaming them would orphan every existing save for a cosmetic gain.
-- If a string is read by a player it says Michael; if it is an identifier it says Michel.
--
-- He wants FIVE Tung Tung Tung Sahurs and every one of them has to be MUTATED -- any
-- mutation counts, Golden through Angel. They are handed over exactly the way Elder Tung
-- takes his: the player picks EXACT copies out of a grid, a few at a time, and whatever
-- they choose is destroyed. The server state machine is ServerScriptService.Modules.
-- MichelQuest (progress is data.MichelGiven); this shared config is what the dialogue,
-- the picker panel and the quest tracker all read, so the quota can never be stated in
-- two places that disagree.
--
-- THE NAME HAS TO BE EXACT. Matching is a straight string compare against BrainrotConfig,
-- where the Mythic is spelled with THREE Tungs (it is Elder Tung's own namesake). Drop a
-- Tung here and the quest silently accepts nothing -- it does not error, it just never
-- counts anything.
local M = {}

M.NpcName = "Michael"

-- === THE ASK ==================================================================
-- Name is matched exactly against BrainrotConfig. "Mutated" means entry.Mutation is any
-- non-empty string -- deliberately NOT a list of accepted mutations, so a variant added
-- to MutationConfig later counts on the day it ships without this file being touched.
M.Brainrot = "Tung Tung Tung Sahur"
M.Count = 5

-- Paid once, on the hand-over that completes the fifth. EmeraldService is the only
-- authority on the balance; this is just the number.
M.RewardEmeralds = 1000

-- Handed over on that SAME completion, alongside the emeralds (MichelQuest.deliver).
-- Matched by exact name against BrainrotConfig, where the entry carries Weight = 0 and
-- QuestOnly = true -- finishing this questline is his ONLY source in the game, so if this
-- string and the config entry ever disagree the reward silently stops existing.
M.RewardBrainrot = "Pippo Olivardino"

-- === DIALOGUE =================================================================
-- Sentence case, full stops, the lot. He is a bird stage-whispering at you, so he SHOUTS
-- in caps for emphasis -- but only for emphasis; the punctuation underneath it is
-- ordinary. The first four are the authored lines, everything below is written to match.
M.Intro1  = "Hey! Psst. I need your help with something."
M.Intro2  = "I need you to bring me 5 mutated Tung Tung Tung Sahurs."
M.Confirm = "Are you ready to accept the %s?"
M.Refuse  = "AH! Get out of here, then!"

-- The quest's proper name, always all-caps, and the colour it is highlighted in: his own
-- eye and beak gold, so the emphasis reads as HIS rather than as generic UI yellow.
-- Anything that names the quest reads this rather than retyping it.
M.QuestLabel = "EAGLES QUEST"
M.Highlight = Color3.fromRGB(240, 200, 96)

-- The name-ribbon gradient on his dialogue card -- beak gold, so he is not mistaken for
-- Elder Tung's brown.
M.Accent = { Color3.fromRGB(226, 176, 62), Color3.fromRGB(196, 146, 48) }

M.Nag    = "Well? Five of them, and every single one has to be MUTATED. No plain ones."
M.Ready  = "AH! You've got the lot on you right now. Hand them over, hand them over!"
M.Done   = "Psst. We never spoke. Go on, get."
-- Formatted from RewardBrainrot so the creature is never named in two places that can
-- drift apart; still a plain string, which is what the dialogue client reads.
M.Reward = ("GOOD. Take your gems, and take %s off my claws. Forget my face."):format(M.RewardBrainrot) -- the currency is Gems to the player (2026-09-18)
-- Shown when the right brainrots exist but are sitting on the player's base, where they
-- cannot be handed over -- the same trap Elder Tung's hand-over warns about.
M.Placed = "Those are sitting on your base, not in your claws. Go and fetch them."
-- Fires once, when the player is first carrying everything he is still owed.
M.Carrying = "Psst! You've got the lot on you right now. Get over here."

-- The picker panel's own copy.
M.PickTitle = "Hand over to Michael"
M.PickHint  = "Mutated Tung Tung Tung Sahurs only. Whatever you choose is gone for good."
M.Empty     = "Nothing in hand that Michael wants -- he only takes MUTATED Tung Tung Tung Sahurs."
M.AllDone   = "Michael has everything he asked for."

-- === DERIVED ==================================================================
-- Composed here rather than in the client so the markup lives next to the colour that
-- drives it; MerchantDialog renders this with its RichText option.
local function hex(c: Color3): string
	return ("#%02X%02X%02X"):format(
		math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

function M.ConfirmLine(): string
	return M.Confirm:format(('<font color="%s"><b>%s</b></font>'):format(hex(M.Highlight), M.QuestLabel))
end

-- "Mutated Tung Tung Tung Sahurs 2/5" -- one line, used by the dialogue and the picker.
-- Plural because it is always a count of several; the singular case is only ever "5".
function M.ProgressLine(have: number?): string
	return ("Mutated %ss %d/%d"):format(M.Brainrot, math.clamp(tonumber(have) or 0, 0, M.Count), M.Count)
end

-- The single test every candidate brainrot goes through, on BOTH sides of the wire.
-- Shared so the picker can never offer something the server would then refuse.
function M.Accepts(entry): boolean
	if type(entry) ~= "table" then return false end
	if entry.Name ~= M.Brainrot then return false end
	return type(entry.Mutation) == "string" and entry.Mutation ~= ""
end

return M
