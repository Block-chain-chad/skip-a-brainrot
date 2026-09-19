-- Server-wide rare catch banner: everyone sees when someone lands a Secret or a Rainbow/Glitched mutation
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local rareCatch = remotes:WaitForChild("RareCatch")
local SoundKit = require(game:GetService("ReplicatedStorage").Modules.SoundKit)
local Mutations = require(game:GetService("ReplicatedStorage").Modules.MutationConfig)

-- How triumphant the catch sounds, by tier. Each rung is a LIST OF LAYERS.
--
-- Rarity reads as rarer three ways at once: the samples get longer, the level
-- climbs, and the top three rungs STACK. The stacking is the important part --
-- length and volume alone have run out of headroom by the time you reach Secret,
-- so density has to carry the last stretch. A God is an impact, then a choir over
-- it, then a shimmer on top: three events in 0.32s that read as one huge one.
--
-- ON LAYERING, because this file used to forbid it: the old rule came from layering
-- the TIER sound and the MUTATION sound, both at full level, 0.12s apart -- two
-- unrelated stings that just read as one long ring. These layers are different in
-- kind: they are chosen to compose, the supporting layers sit well under the lead,
-- and the offsets are short enough to fuse into a single hit. The mutation rule is
-- unchanged below -- a big mutation still REPLACES the tier sound, never stacks.
local TIER_SFX = {
	Common    = { { sound = "catchCommon",   volume = 0.13 } },
	Uncommon  = { { sound = "catchUncommon", volume = 0.17 } },
	Rare      = { { sound = "catchRare",     volume = 0.21 } },
	Epic      = { { sound = "catchEpic",     volume = 0.25 } },
	Legendary = { { sound = "catchLegend",   volume = 0.30 } },
	Mythic    = { { sound = "catchMythic",   volume = 0.34 },
	              { sound = "catchSparkle",  volume = 0.18, delay = 0.06 } },
	-- catchDrama (curse01) dropped from Secret with the pass-4 reshuffle: it was from
	-- the same rejected corner as bless/abyss. God keeps it -- God was not complained
	-- about, and the choir is what carries that stack anyway.
	Secret    = { { sound = "catchSecret",   volume = 0.40 },
	              { sound = "catchBigHit",   volume = 0.24, delay = 0.06 } },
	God       = { { sound = "catchBigHit",   volume = 0.44 },
	              { sound = "catchGod",      volume = 0.54, delay = 0.10 },
	              { sound = "catchDrama",    volume = 0.30, delay = 0.10 },
	              { sound = "catchSparkle",  volume = 0.30, delay = 0.34 } },
}
local TIER_FALLBACK = { { sound = "catchRare", volume = 0.21 } }

-- scale: 1 for your own catch, lower for somebody else's -- see the call sites.
local function playCatch(tierName, scale)
	for _, layer in ipairs(TIER_SFX[tierName] or TIER_FALLBACK) do
		local vol = layer.volume * scale
		if (layer.delay or 0) <= 0 then
			SoundKit.play(layer.sound, nil, { volume = vol })
		else
			task.delay(layer.delay, function()
				SoundKit.play(layer.sound, nil, { volume = vol })
			end)
		end
	end
end
-- Every mutation has its OWN voice now (phase 2 of the mutation-visuals
-- handoff, 2026-08-13) -- the generic `mutation` sting only survives as the
-- fallback for anything unmapped. All ids are existing, load-verified kit
-- sounds; the two new cue names (aurora/celestial) reuse the weather beds
-- those mutations drop from, which is the association the moment wants.
local MUTATION_SOUND = {
	Angel    = "angel",       -- choir
	Demon    = "demon",       -- deep growl
	Glitched = "glitched",    -- digital glitch
	Wet      = "splash",      -- the skip tap
	Sandy    = "eggCrumble",  -- dry grit
	Electric = "catchRare",   -- magic zap
	Frozen   = "catchSecret", -- icy shatter
	Aurora   = "aurora",      -- airy swells (the event's own bed)
	Celestial = "celestial",  -- deep synth swell (ditto)
	Golden   = "cash",        -- coin ching, per the spec
	Diamond  = "catchSparkle",-- crystal twinkle
	Rainbow  = "catchEpic",   -- eerie chime (nearest to a rising arpeggio in the kit)
}
SoundKit.preload()
local Platform = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Platform"))

-- House feedback grammar (PS99 chrome): passive info is NAKED bubble text.
-- The old plated cream card (UITheme.campPanel + accent bar + sunburst tile)
-- sat top-centre at y=58 and covered the SKIP HERE world marker and the
-- player-nameplate band, so the plate is gone entirely -- three stacked
-- text lines now:
--   1  rarity word, tier-coloured, dark-navy contextual stroke
--   2  catch name, white, same stroke
--   3  "skipped up by ..." byline, muted silver, smaller
local INK = Color3.fromRGB(49, 61, 79)      -- #313D4F contextual stroke
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(147, 161, 180) -- #93A1B4 quiet/idle silver

local gui = Instance.new("ScreenGui")
gui.Name = "RareCatchUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 8
-- UIPolish force-whitens any unexempted label; the tier line (tier colour)
-- and byline (muted silver) must keep their own colours, so opt the whole
-- surface out once at the root (UIPolish honours NoPolish on any ancestor).
gui:SetAttribute("NoPolish", true)
gui.Parent = player:WaitForChild("PlayerGui")

-- Shown position hugs the top edge, well above the centre-screen band where
-- the SKIP HERE marker and nameplates live. On touch devices Roblox draws
-- chrome around the top-centre, so the stack sits a little further below
-- the inset there. Recomputed on every device/viewport change; the tween
-- goal tables in showNext read these at call time, so trigger/queue/timing
-- behaviour is untouched.
local hiddenPos = UDim2.new(0.5, 0, 0, -96)
local shownPos = UDim2.new(0.5, 0, 0, 6)
Platform.Watch(function()
	shownPos = UDim2.new(0.5, 0, 0, Platform.IsTouch and 38 or 6)
end)

-- transparent container: only the text renders, so even when the banner is
-- up, the world behind it stays readable
local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = hiddenPos
banner.Size = UDim2.new(1, -32, 0, 78)
banner.BackgroundTransparency = 1
banner.Visible = false
banner.Parent = gui

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 2)
listLayout.Parent = banner

-- one naked bubble-text line: FredokaOne + dark-navy Contextual stroke on
-- the glyphs, zero plate behind it
local function bubbleLine(name, order, height, textSize, color, strokeThickness)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, height)
	l.Font = Enum.Font.FredokaOne
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Color = INK
	s.Thickness = strokeThickness
	s.Parent = l
	l.Parent = banner
	return l
end

local tierLine = bubbleLine("Tier", 1, 30, 26, WHITE, 3) -- retinted per catch in showNext
local nameLine = bubbleLine("Name", 2, 24, 20, WHITE, 2.6)
local byLine = bubbleLine("By", 3, 18, 15, MUTED, 2)

local queue = {}
local showing = false

local function showNext()
	local item = table.remove(queue, 1)
	if not item then
		showing = false
		return
	 end
	showing = true

	local mutPrefix = (item.mutation and item.mutation ~= "" and item.mutation ~= "None") and (item.mutation .. " ") or ""
	tierLine.Text = string.upper(item.tierName)
	tierLine.TextColor3 = item.color -- the tier's own colour carries the rarity read
	nameLine.Text = mutPrefix .. item.brainrotName
	byLine.Text = ("skipped up by %s!"):format(item.playerName)

	-- Audio for the catch. Broadcast to EVERY player, so someone else's find is
	-- near-silent while yours is merely audible.
	--
	-- Deliberately quiet and NEVER layered. The first version played a chime for
	-- the tier and a second chime for the mutation 0.12s later, both loud, which
	-- just read as one long ring. One sound per catch, and a rare mutation
	-- REPLACES the tier sound instead of stacking on top of it.
	local mine = (item.playerName == Players.LocalPlayer.Name)
	local r = (item.mutation and item.mutation ~= "" and item.mutation ~= "None")
		and Mutations.Rarity(item.mutation) or 0
	if not mine then
		-- someone else's find: same layers, a third of the level, so the ladder is
		-- still legible across the server without anyone else's luck talking over you
		playCatch(item.tierName, 0.30)
	elseif r >= 5 then
		local special = item.mutation and MUTATION_SOUND[item.mutation]
		if special then
			-- its own sample, so NO pitch shifting -- a stretched choir sounds wrong
			SoundKit.play(special, nil, { volume = 0.3 })
		else
			-- otherwise the generic sting, pitched up the rarity ladder
			SoundKit.play("mutation", nil, { volume = 0.22, speed = 0.9 + 0.03 * r })
		end
	else
		playCatch(item.tierName, 1)
	end

	banner.Visible = true
	banner.Position = hiddenPos
	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = shownPos }):Play()
	task.delay(4.5, function()
		local tw = TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = hiddenPos })
		tw:Play()
		tw.Completed:Wait()
		banner.Visible = false
		showNext()
	end)
end

rareCatch.OnClientEvent:Connect(function(playerName, tierName, brainrotName, tierColor, mutation)
	if typeof(playerName) ~= "string" or typeof(tierName) ~= "string" or typeof(brainrotName) ~= "string" then return end
	-- UIKIT (Task 10): Settings panel GAMEPLAY toggle "hideOwnBanners" --
	-- cheapest real seam in this file: one guard clause, before the item
	-- ever reaches the queue. This skips the WHOLE event for a catch that
	-- was YOURS (banner AND its sound layer together, since both are driven
	-- from the same queued item inside showNext) rather than only hiding the
	-- visual bar -- splitting those would mean duplicating showNext's
	-- sound-selection logic here. Other players' banners are completely
	-- unaffected; this only ever short-circuits an item whose playerName is
	-- the local player's own.
	if playerName == player.Name and player:GetAttribute("HideOwnBanners") == true then
		return
	end
	table.insert(queue, {
		playerName = playerName,
		tierName = tierName,
		brainrotName = brainrotName,
		color = typeof(tierColor) == "Color3" and tierColor or Color3.fromRGB(255, 90, 220),
		mutation = typeof(mutation) == "string" and mutation or nil,
	})
	if #queue > 4 then table.remove(queue, 1) end
	if not showing then showNext() end
end)
