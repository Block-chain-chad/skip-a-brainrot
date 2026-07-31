-- Maxwell the cat: hold E to pet/talk to him. He runs a secret questline driven by
-- MaxwellQuest (server) -- that module is the state machine and the authority. This
-- client just renders his dialogue in the SAME box the merchants use (MerchantDialog)
-- and fires MaxwellTalk to accept the quest / claim the reward. Below Rebirth 3 he
-- only meows; the quest text and progress numbers all come from MaxwellState.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local MerchantDialog = require(ReplicatedStorage.Modules.MerchantDialog)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local CF = UITheme.Camp

-- Latest quest snapshot pushed by MaxwellQuest. Stored and read on trigger so the
-- dialogue always shows the real, server-authoritative state and progress.
local latest = { State = 0, Secrets = 0, SecretsNeeded = 5, Rebirths = 0, RebirthsNeeded = 15, Unlock = 3 }
remotes:WaitForChild("MaxwellState").OnClientEvent:Connect(function(s)
	if typeof(s) == "table" then latest = s end
end)
local talk = remotes:WaitForChild("MaxwellTalk")

local ACCENT = { CF.berry1, CF.berry2 }   -- purple "secret" plate, matching the tracker card

-- Wait for the cat and its prompt (added in Edit; may stream in a touch late).
local cat = Workspace:WaitForChild("Maxwell", 60)
if not cat then return end
local body = cat:WaitForChild("maxwell", 30)
local prompt = body and body:WaitForChild("PetPrompt", 30)
if not prompt then return end

-- Lines + final-button label + talk action for the current quest state. Maxwell is
-- a cat: unimpressed, self-important, entirely food-motivated.
local function dialogueFor(s)
	local state = tonumber(s.State) or 0
	local secrets, need = s.Secrets or 0, s.SecretsNeeded or 5
	local reb, rebNeed = s.Rebirths or 0, s.RebirthsNeeded or 15
	local unlock = s.Unlock or 3

	if state == 0 then
		if reb < unlock then
			return { "meow." }, "BYE", nil   -- locked: he can't be bothered with you yet
		end
		return {
			"meow. *slow blink* ...oh. it's you. the one who keeps throwing rocks.",
			"i am Maxwell. i do not chase string. i chase GREATNESS. and snacks.",
			("bring me ONE of every Secret in the index \u{2014} all %d of them. yes, ALL. cats don't do half-measures."):format(need),
		}, "ACCEPT (meow) \u{25B6}", "accept"
	elseif state == 1 then
		return {
			("%d of %d Secrets in the index. chop chop, human \u{2014} i haven't got all nine lives."):format(math.min(secrets, need), need),
			"...well. i do. but hustle anyway. meow.",
		}, "BYE", nil
	elseif state == 2 then
		return {
			"the secrets? adequate. *licks paw*",
			("now suffer for me: reach Rebirth %d. you're at %d. devotion is measured in rebirths."):format(rebNeed, math.min(reb, rebNeed)),
		}, "BYE", nil
	elseif state == 3 then
		return {
			"you actually did it. the secrets AND the rebirths. i am... mildly impressed.",
			"here. a piece of me: the GOD Maxwell. do NOT pet it without written permission.",
		}, "TAKE IT (meow) \u{25B6}", "claim"
	else   -- 4: done
		return {
			"we're square, human. now shoo.",
			"...and bring the good snacks next time. meow.",
		}, "BYE", nil
	end
end

prompt.Triggered:Connect(function(who)
	if who ~= player then return end
	local lines, finalLabel, action = dialogueFor(latest)
	local onDone = action and function() talk:FireServer(action) end or nil
	MerchantDialog.Show("Maxwell", lines, ACCENT, onDone, body, finalLabel)
end)
