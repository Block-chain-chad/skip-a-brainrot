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
-- Mutations with their OWN voice, instead of the generic sting pitched up.
-- These are the top three rungs of the 12-rung ladder and all are vanishingly
-- rare, so each is worth hearing as something completely different:
--   Angel    r12, 0.018% per catch  -> choir
--   Demon    r11, 0.070% per catch  -> deep growl
--   Glitched r10, fusion-only       -> digital glitch
local MUTATION_SOUND = {
	Angel    = "angel",
	Demon    = "demon",
	Glitched = "glitched",
}
SoundKit.preload()
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local P = UITheme.Palette
local CF = UITheme.Camp

local gui = Instance.new("ScreenGui")
gui.Name = "RareCatchUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 8
gui.Parent = player:WaitForChild("PlayerGui")

local HIDDEN_POS = UDim2.new(0.5, 0, 0, -64)
local SHOWN_POS = UDim2.new(0.5, 0, 0, 58)

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = HIDDEN_POS
banner.Size = UDim2.new(0, 640, 0, 56)
banner.BackgroundColor3 = P.white
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = gui
UITheme.campPanel(banner)
UITheme.corner(banner, 14)

-- accent bar: showNext still retints BackgroundColor3 with the caught tier's colour;
-- the white->grey gradient turns that one colour into the campfire two-tone.
local accent = Instance.new("Frame")
accent.Size = UDim2.new(0, 8, 1, -16)
accent.Position = UDim2.new(0, 10, 0, 8)
accent.BorderSizePixel = 0
accent.ZIndex = 2
accent.Parent = banner
UITheme.corner(accent, 4)
UITheme.gradient(accent, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150), 90)
UITheme.ink(accent, 2)

-- sunburst icon tile; the rays are retinted with the tier colour in showNext
local icon = Instance.new("Frame")
icon.Name = "Icon"
icon.AnchorPoint = Vector2.new(0, 0.5)
icon.Position = UDim2.new(0, 28, 0.5, 0)
icon.Size = UDim2.fromOffset(40, 40)
icon.BackgroundColor3 = P.white
icon.BorderSizePixel = 0
icon.ClipsDescendants = true
icon.ZIndex = 2
icon.Parent = banner
UITheme.corner(icon, 10)
local burst = UITheme.sunburst(icon, CF.amber1, 12)
UITheme.ink(icon, 2.5)

local star = Instance.new("TextLabel")
star.Name = "Star"
star.Size = UDim2.fromScale(1, 1)
star.BackgroundTransparency = 1
star.Font = Enum.Font.FredokaOne
star.TextSize = 24
star.Text = "\u{1F31F}"
star.ZIndex = icon.ZIndex + 2
star.Parent = icon

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Size = UDim2.new(1, -104, 1, 0)
label.Position = UDim2.new(0, 82, 0, 0)
label.Font = Enum.Font.FredokaOne
label.TextSize = 19
label.TextColor3 = CF.cream
label.TextXAlignment = Enum.TextXAlignment.Center
label.TextTruncate = Enum.TextTruncate.AtEnd
label.ZIndex = 2
label.Parent = banner
UITheme.inkText(label, 2.8)

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
	label.Text = ("%s skipped up a %s%s (%s)!"):format(item.playerName, mutPrefix, item.brainrotName, item.tierName)
	accent.BackgroundColor3 = item.color
	for _, ray in ipairs(burst:GetChildren()) do
		if ray.Name == "Ray" then ray.BackgroundColor3 = item.color end
	end

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
	banner.Position = HIDDEN_POS
	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = SHOWN_POS }):Play()
	task.delay(4.5, function()
		local tw = TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = HIDDEN_POS })
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
