-- MerchantDialog: the NPC conversation box. EVERY talking NPC routes through here --
-- Gianluca, Maxwell, Tung, Marco and the merchants -- so this one file is what the
-- whole game's NPC interaction looks like.
--
--   MerchantDialog.Show(npcName, lines, accent, onDone, anchor, finalLabel, opts)
--
-- THE FIRST SIX ARE FROZEN. Five call sites pass those positional arguments and none
-- of them were touched by the 2026-07-31 rebuild; changing the order here breaks all
-- of them silently, because Luau will happily assign a table to `accent`. `opts` was
-- added AFTER them for exactly that reason -- a seventh optional table costs the five
-- existing callers nothing.
--
-- Advances through `lines`; on the last line the primary button calls onDone(). onDone
-- is dropped if the player LEAVEs or walks away (Hide()).
--
-- opts (all optional):
--   DeclineLabel  what the grey button says ON THE LAST LINE -- "NO" for a real
--                 question. It still reads "Leave" up to that point: a decision the
--                 player has not been asked yet should not already be on screen.
--   OnDecline     called when that button is pressed WHILE it reads as the refusal,
--                 which is how an NPC gets to answer "no" instead of just closing.
--                 Pressing Leave part-way through the speech means "not now", not
--                 "no", and deliberately does not fire it.
--   RichText      render the lines as markup (see richPrefix below). Off by default,
--                 so a stray "<" in ordinary copy still prints as a "<".
--
-- REBUILT 2026-07-31 to the user's reference recording. What that pattern is:
--   * the NPC's OWN 3D model as a portrait, breaking out ABOVE the panel's top edge
--     rather than boxed inside it -- this is what makes it read as a character
--     speaking rather than a system message
--   * a name ribbon notched into the panel's top-left, tinted by the caller's accent
--   * the body text TYPEWRITES in, and the choice buttons do not exist until it
--     finishes -- the reference is strict about this, and it is what stops players
--     mashing through dialogue they never read
--   * two equal-width choices below the panel: coloured primary, grey Leave
-- Skinned in UIKit (Tokens/Builders) rather than the older campfire UITheme, so it
-- matches the egg shop and the six HUD panels.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local T = require(ReplicatedStorage.Modules.UIKit.Tokens)
local UI = require(ReplicatedStorage.Modules.UIKit.Builders)
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local CF = UITheme.Camp
local FONT = UITheme.Font
local BODY = Enum.Font.GothamMedium
local player = Players.LocalPlayer

-- typewriter blip; pcall'd so a missing SoundKit leaves the dialogue silent, not broken
local okSound, SoundKit = pcall(function()
	return require(ReplicatedStorage.Modules.SoundKit)
end)
if not okSound then SoundKit = nil end

local M = {}
local gui, root, box, namePlate, nameText, lineText, contBtn, contText
local leaveBtn, leaveText, btnRow, portrait, contDots
local scrim, colourFx, hiddenGuis, stageToken, failsafeConns = nil, nil, nil, 0, {}
-- What the core UI looked like BEFORE we staged, so restoreHud puts back what it
-- found instead of blanket-enabling everything (2026-08-19). The blanket version
-- meant two overlapping cinematics re-lit each other's chat and topbar mid-scene:
-- close a merchant dialogue during an egg-hatch reveal and the reveal got the chat
-- back. Kept in lockstep with hiddenGuis -- both are set in hideHud, both cleared
-- in restoreHud.
local coreWas = nil
local portraitConn                     -- drives the live portrait pose; see buildPortrait
local lines, idx, onDone, anchorPart, finalLabel, opts
local typeToken = 0      -- bumped by every new line and by Hide(); stale typers no-op
local typing = false     -- true while characters are still being revealed

local BOX_W, BOX_H = 640, 150
local PORTRAIT_W, PORTRAIT_H = 184, 200
local CHARS_PER_SEC = 45
-- Portrait framing, expressed against the ANCHOR PART rather than the model: how far
-- above the anchor the aim sits (in multiples of the anchor's own height), and how many
-- studs of subject to fit vertically.
--
-- RISE aims at the CHEST, not the head. Gianluca's root is 2 studs tall with his head
-- 1.6 above it, so an earlier 0.85 put the aim point above his head entirely -- he sat
-- in the bottom half of the frame and the transparent top half showed the scenery behind
-- the viewport, which read as "the portrait is full of crates".
local PORTRAIT_RISE = 0.50
local PORTRAIT_SPAN = 4.6

---------------------------------------------------------------- portrait
-- The NPC's real model, framed head-and-shoulders. Derived from the `anchor` part the
-- caller already passes for the walk-away check, so no call site has to supply art and
-- every NPC gets a portrait for free -- including ones added later.
local function npcModelFrom(anchor)
	if not anchor then return nil end
	local inst = anchor
	while inst and inst.Parent do
		if inst:IsA("Model") and inst ~= workspace then return inst end
		inst = inst.Parent
	end
	return nil
end

-- WHICH PART OF THE MODEL IS THE PERSON. The prompt hangs off a "PromptPart" on
-- the OUTERMOST model, and that model is the whole shop -- Marco's is 223 parts of
-- counter, shelves and stock, Gino's is 2020. Rendering all of it is what made the
-- portrait an opaque rectangle of scenery: a "photo in a box" with no box.
--
-- Verified against every prompt in the world before it was written: the builders
-- consistently group the character in a child Model named "NPC" (Marco 33/223,
-- Gino 35/2020, Rocco 33/181, Enzo 31/109), and where they didn't, the character
-- model still owns a HumanoidRootPart (Lil Miss 53/131, Gianluca 37/37).
--
-- The fallback returns the whole model on PURPOSE. Michael and Elder Tung ARE
-- standalone characters with no stall, and the Cellar, the Daily Wheel and the
-- Egg Shop are props where the "scenery" is precisely what should be pictured.
local function portraitSubject(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") and d.Name == "NPC" then return d end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") and (d:FindFirstChildOfClass("Humanoid")
			or d:FindFirstChild("HumanoidRootPart")) then return d end
	end
	return model
end

local function buildPortrait(parent, anchor)
	if not (anchor and anchor:IsA("BasePart")) then return nil end
	local source = npcModelFrom(anchor)
	if not source then return nil end
	source = portraitSubject(source)
	local ok, clone = pcall(function() return source:Clone() end)
	if not ok or not clone then return nil end

	-- LIVE POSE MAP. A ViewportFrame does not run Animators, so a cloned NPC is a
	-- freeze-frame; copying CFrames per frame is what lets the portrait breathe with
	-- the idle the NPC is actually playing in the world.
	--
	-- PAIRED BY NAME+POSITION, NOT BY DESCENDANT ORDER. Zipping the two
	-- GetDescendants() lists looks obvious and is WRONG: Instance:Clone() does not
	-- preserve child order, and a dry run over every NPC in the world showed the two
	-- lists disagreeing on exactly the character models (Marco, Gino, Rocco, Enzo,
	-- Gianluca, Lil Miss). Pairing by index there would have written each limb's
	-- CFrame onto a different limb and visibly dismembered them.
	--
	-- Name alone is not unique either -- these bodies carry several parts called
	-- "Lapel" and "Panel" -- so the key is name plus position, which IS unique and
	-- IS identical on both sides at this instant, because the clone was taken on
	-- this frame and nothing has yielded since.
	local liveMap = {}
	do
		local function keyOf(p)
			local v = p.Position
			return ("%s|%.2f,%.2f,%.2f"):format(p.Name, v.X, v.Y, v.Z)
		end
		local byKey = {}
		for _, p in ipairs(source:GetDescendants()) do
			if p:IsA("BasePart") then byKey[keyOf(p)] = p end
		end
		for _, p in ipairs(clone:GetDescendants()) do
			if p:IsA("BasePart") then
				local live = byKey[keyOf(p)]
				if live then liveMap[#liveMap + 1] = { live, p } end
			end
		end
	end

	-- Viewports draw BaseParts only, and a live NPC carries prompts, scripts, emitters
	-- and sounds that would all come along on the clone.
	for _, d in ipairs(clone:GetDescendants()) do
		if not (d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder")
			or d:IsA("SpecialMesh") or d:IsA("Decal") or d:IsA("Texture")
			or d:IsA("Humanoid") or d:IsA("Accessory") or d:IsA("Shirt")
			or d:IsA("Pants") or d:IsA("BodyColors")) then
			d:Destroy()
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
	end
	-- A Humanoid inside a ViewportFrame has nothing to stand on and can re-pose or
	-- rescale the rig; the portrait only needs the geometry.
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then hum:Destroy() end


	-- NO BACKDROP. It existed because a portrait of a whole shop needed grounding
	-- against the world behind it; a cut-out of just the character does not, and any
	-- panel behind him is exactly the box the reference doesn't have. The character
	-- now sits directly on the dimmed stage -- which is what the scrim is for.

	local vp = Instance.new("ViewportFrame")
	vp.Name = "Portrait"
	vp.AnchorPoint = Vector2.new(0, 1)
	-- sits ABOVE the panel's top edge and overlaps it; this overhang is the whole point
	vp.Position = UDim2.new(0, 6, 0, 34)
	vp.Size = UDim2.fromOffset(PORTRAIT_W, PORTRAIT_H)
	vp.BackgroundTransparency = 1
	vp.ZIndex = 24
	vp.Parent = parent
	clone.Parent = vp

	-- FRAME ON THE ANCHOR PART, NOT THE MODEL'S BOUNDING BOX. These "NPC models" contain
	-- the NPC's furniture -- Gianluca's model is 37 parts of stall, crates and cane with a
	-- person somewhere in it -- so a bbox fit centres on the stall and leaves the face in
	-- a corner, which is what the first two attempts did. The anchor the caller already
	-- passes IS the character's root, so it is the one reliable handle on the body.
	--
	-- The clone still holds the whole model, so the stall stays in shot behind him as
	-- context; only the camera's aim changes.
	-- Frame on the character's OWN root when it has one -- the PromptPart is a
	-- separate box sitting a little in front of the body, and now that the shop is
	-- no longer in shot there is nothing else to hide the offset.
	local framePart = source:FindFirstChild("HumanoidRootPart") or anchor
	local fov = 26
	local target = framePart.Position + Vector3.new(0, framePart.Size.Y * PORTRAIT_RISE, 0)
	local dist = (PORTRAIT_SPAN * 0.5) / math.sin(math.rad(fov * 0.5))
	local cam = Instance.new("Camera")
	cam.FieldOfView = fov
	-- STAND IN FRONT OF THE NPC'S OWN FACING, not a fixed world direction. NPCs are
	-- rotated arbitrarily where they were placed, so a constant direction photographs
	-- whoever happens to be turned the right way and shows everyone else their back --
	-- which is exactly what Gianluca's first portrait was.
	local look = framePart.CFrame
	local dir = (look.LookVector + look.RightVector * 0.35 + Vector3.new(0, 0.20, 0)).Unit
	cam.CFrame = CFrame.lookAt(target + dir * dist, target)
	cam.Parent = vp
	vp.CurrentCamera = cam

	-- LIT LIKE A CHARACTER, not like scenery. With the furniture gone there is
	-- nothing behind him to catch light, so the key has to come from the camera's
	-- side or he reads as a silhouette against the dark stage.
	vp.Ambient = Color3.fromRGB(146, 150, 160)
	vp.LightColor = Color3.fromRGB(255, 250, 238)
	vp.LightDirection = Vector3.new(-0.45, -0.6, -1).Unit

	-- ...and the pose follows the real NPC every frame, so his idle plays in the
	-- portrait. One connection, replaced per conversation and cut in M.Hide, so it
	-- can never outlive the box. Parent checks make a destroyed source part a no-op
	-- rather than an error mid-conversation.
	if portraitConn then portraitConn:Disconnect() end
	portraitConn = RunService.Heartbeat:Connect(function()
		for _, pair in ipairs(liveMap) do
			local live, copy = pair[1], pair[2]
			if live.Parent and copy.Parent then copy.CFrame = live.CFrame end
		end
	end)
	return vp
end

---------------------------------------------------------------- richtext reveal
-- string.sub() CANNOT type out markup: cutting inside <font color="#FFCD50"> puts raw
-- tag text on screen for a few frames. These two walk the string instead -- tags are
-- copied whole and cost nothing against the budget, and any tag still open at the cut
-- is closed again, so every intermediate frame is valid markup rather than a fragment.
-- Entities (&amp;) are not decoded into one character; no dialogue in the game uses one.
local function visibleLen(text)
	local n, i = 0, 1
	while i <= #text do
		if text:sub(i, i) == "<" then
			local close = text:find(">", i, true)
			if not close then break end
			i = close + 1
		else
			n += 1
			i += 1
		end
	end
	return n
end

local function richPrefix(text, budget)
	local out, open = {}, {}
	local i, shown = 1, 0
	while i <= #text and shown < budget do
		if text:sub(i, i) == "<" then
			local close = text:find(">", i, true)
			if not close then break end
			local tag = text:sub(i, close)
			out[#out + 1] = tag
			local shut = tag:match("^</(%a+)")
			if shut then
				for k = #open, 1, -1 do
					if open[k] == shut then table.remove(open, k) break end
				end
			elseif not tag:match("/>$") then
				local name = tag:match("^<(%a+)")
				if name then open[#open + 1] = name end
			end
			i = close + 1
		else
			out[#out + 1] = text:sub(i, i)
			shown += 1
			i += 1
		end
	end
	for k = #open, 1, -1 do out[#out + 1] = "</" .. open[k] .. ">" end
	return table.concat(out)
end

----------------------------------------------------------------
-- Reveals `text` one character at a time. Returns immediately; the caller checks
-- `typing` to know whether a click should skip ahead instead of advancing.
local function typeLine(text)
	typeToken += 1
	local myToken = typeToken
	typing = true
	local rich = (opts and opts.RichText) and true or false
	-- set EVERY line, not once at build: leaving it on would make a later caller's
	-- ordinary "<" disappear as an unknown tag
	lineText.RichText = rich
	lineText.Text = ""
	btnRow.Visible = false      -- the reference does not offer a choice mid-sentence
	contDots.Visible = false
	task.spawn(function()
		local n = rich and visibleLen(text) or #text
		local shown = 0
		while shown < n do
			if myToken ~= typeToken then return end
			shown = math.min(n, shown + math.max(1, math.floor(CHARS_PER_SEC / 30)))
			lineText.Text = rich and richPrefix(text, shown) or string.sub(text, 1, shown)
			-- A blip every few characters, not every one, or it is a buzz. `wheelTick` is
			-- SoundKit's dry 0.097s ui_tap -- there is no dedicated typewriter slot, and
			-- inventing one silently plays nothing (SoundKit resolves by key).
			if SoundKit and shown % 4 == 0 then
				pcall(function() SoundKit.play("wheelTick", nil, { volume = 0.05, speed = 1.7 }) end)
			end
			task.wait(1 / 30)
		end
		if myToken ~= typeToken then return end
		typing = false
		lineText.Text = text
		btnRow.Visible = true
		contDots.Visible = true
		-- buttons pop in rather than blink, matching the reference's beat
		local s = btnRow:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		s.Parent = btnRow
		s.Scale = 0.9
		TweenService:Create(s, T.tween.pop, { Scale = 1 }):Play()
	end)
end

-- Finishes the current line instantly. Clicking while text is still running should
-- complete it, never skip the line -- otherwise a fast clicker never sees the words.
local function finishTyping()
	typeToken += 1
	typing = false
	if lines and lines[idx] then lineText.Text = lines[idx] end
	btnRow.Visible = true
	contDots.Visible = true
end

-- Is the player being asked the question yet? Both button captions turn on this: the
-- primary stops saying NEXT, and the grey one stops saying Leave.
local function onLastLine()
	return lines ~= nil and idx >= #lines
end

local function refreshLeaveLabel()
	if not leaveText then return end
	leaveText.Text = (opts and opts.DeclineLabel and onLastLine())
		and opts.DeclineLabel
		or "Leave"
end

local function advance()
	if not lines then return end
	if typing then finishTyping() return end
	if idx < #lines then
		idx += 1
		contText.Text = (idx < #lines) and "NEXT \u{25B6}" or finalLabel
		refreshLeaveLabel()
		typeLine(lines[idx])
	else
		local d = onDone
		M.Hide()
		if d then d() end
	end
end

----------------------------------------------------------------
-- THE STAGING (2026-08-14). Measured off the reference clip frame by frame at
-- 30fps: pressing E there does NOT pop a box onto a live scene. Over about two
-- seconds it clears the stage and walks the character into it --
--
--   0-470ms   the HUD FADES out (rail energy 48 -> 23 on a decelerating curve)
--   70-270ms  the world dims 34% AND desaturates 21%, ease-out, together
--   ~200ms    the box appears NARROW and grows outward
--   ~400ms    a lit copy of the NPC rises in while the world NPC stays dimmed
--   200-1900  the line types
--   ~2000ms   only then do the choice buttons arrive
--
-- We already had the typewriter, the held-back buttons and the portrait. What we
-- never had was any of the staging: two tweens in the whole module, on a scene
-- that stayed fully lit with the entire HUD competing for attention.
--
-- RAMPED ON HEARTBEAT, NOT TWEENED. The dim has to drive a ColorCorrectionEffect
-- (not a GuiObject) and TweenService's behaviour on non-GuiObject instances is
-- not something to gamble a stuck screen on -- a scrim that fails to fade back
-- leaves the player staring through a black sheet. One ramp drives every value,
-- carries its own generation token so a re-open cancels the old one mid-flight,
-- and always lands exactly on the final value.
local DESAT = -0.30             -- its 21% colour drain
local STAGE_IN = 0.27           -- 267ms measured
local STAGE_OUT = 0.18

local function ramp(seconds, token, fn)
	task.spawn(function()
		local RunService = game:GetService("RunService")
		local t = 0
		while t < seconds do
			if token ~= stageToken then return end
			t += RunService.Heartbeat:Wait()
			local a = math.clamp(t / seconds, 0, 1)
			fn(1 - (1 - a) ^ 3)          -- cubic ease-out, the curve the clip shows
		end
		if token == stageToken then fn(1) end
	end)
end

-- Everything else on screen goes away, exactly as the reference does. Only OUR
-- ScreenGuis and the CoreGui are touched, and restoreHud puts back precisely what
-- it hid -- never "enable everything", which would light up panels the player had
-- closed. Failsafes below guarantee it runs even if a caller never closes us.
local function hideHud()
	if hiddenGuis then return end       -- already staged; a second Show must not re-capture
	hiddenGuis = {}
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
				g.Enabled = false
				hiddenGuis[#hiddenGuis + 1] = g
			end
		end
	end
	-- Enum.CoreGuiType.All cannot be QUERIED with GetCoreGuiEnabled, so the concrete
	-- types are enumerated to capture their prior state before switching them off.
	coreWas = {}
	pcall(function()
		local sg = game:GetService("StarterGui")
		for _, t in ipairs({ Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList,
			Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health,
			Enum.CoreGuiType.EmotesMenu }) do
			coreWas[t] = sg:GetCoreGuiEnabled(t)
			sg:SetCoreGuiEnabled(t, false)
		end
	end)
	pcall(function() game:GetService("StarterGui"):SetCore("TopbarEnabled", false) end)
end

local function restoreHud()
	if not hiddenGuis then return end
	for _, g in ipairs(hiddenGuis) do
		if g.Parent then g.Enabled = true end
	end
	hiddenGuis = nil
	-- Restore what we found, not "everything on". `or {}` keeps this inert rather
	-- than an error if coreWas is ever nil (it cannot be today: the hiddenGuis guard
	-- above returns first, and the two are always set together).
	pcall(function()
		local sg = game:GetService("StarterGui")
		for t, was in pairs(coreWas or {}) do sg:SetCoreGuiEnabled(t, was) end
	end)
	coreWas = nil
	pcall(function() game:GetService("StarterGui"):SetCore("TopbarEnabled", true) end)
end

-- BLUR, NOT DIM (2026-08-17 grammar sweep). Same recipe as GameHUDClient's
-- shared HUDPanelBlur, under this surface's own name so the two can never
-- fight over one instance: instant on, instant off, NEVER tweened --
-- TweenService silently no-ops on non-GuiObjects in this place. The
-- ColorCorrection grade below is the owner-approved 2026-08-14 staging
-- (desaturate + slight darken) and is NOT part of this conversion.
local function setMerchantBlur(on)
	local Lighting = game:GetService("Lighting")
	local existing = Lighting:FindFirstChild("MerchantBlur")
	if on and not existing then
		local blur = Instance.new("BlurEffect")
		blur.Name = "MerchantBlur"
		blur.Size = 10
		blur.Parent = Lighting
	elseif not on and existing then
		existing:Destroy()
	end
end

local function build()
	if gui and gui.Parent then return end
	gui = Instance.new("ScreenGui")
	gui.Name = "MerchantDialogUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- BLUR-NOT-DIM (2026-08-17): the scrim no longer paints -- separation comes
	-- from the MerchantBlur BlurEffect (setMerchantBlur) plus the owner-approved
	-- ColorCorrection grade. The Frame stays only for its ZIndex-1 slot.
	scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.fromRGB(6, 8, 10)
	scrim.BackgroundTransparency = 1
	scrim.BorderSizePixel = 0
	scrim.Visible = false
	scrim.ZIndex = 1
	scrim.Parent = gui

	-- ROOT is a transparent column holding the portrait, the panel and the button row.
	-- The portrait overhangs the panel's top edge, so it cannot be a child of the panel
	-- without being clipped by it -- hence the shared parent.
	root = Instance.new("Frame")
	root.Name = "DialogRoot"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -120)
	root.Size = UDim2.fromOffset(BOX_W, BOX_H + 62)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 20
	root.Parent = gui

	-- 2026-08-05 cross-platform. Every talking NPC in the game comes through
	-- here, so this box IS the mobile dialogue experience -- and at its authored
	-- 640x212 it covered 85% of the width of a 750x361 handset, which is what
	-- "Gianluca's quest UI covers the whole screen" was.
	--
	-- Deliberately a SEPARATE UIScale from the "PopScale" the show animation
	-- drives: the two multiply cleanly, whereas sharing one would mean the
	-- tween stomping the device scale every time the box opens.
	local Platform = require(script.Parent:WaitForChild("Platform"))
	local deviceScale = Instance.new("UIScale")
	deviceScale.Name = "DeviceScale"
	deviceScale.Parent = root
	Platform.Watch(function()
		-- also lifts the box off the bottom edge, where a phone's on-screen
		-- controls live; -120 was authored against a desktop window
		-- The Choices row overhangs root's bottom edge, and Roblox's own core
		-- hotbar occupies the bottom band of a phone, so the offset has to clear
		-- both -- measured, the buttons were landing within a few px of it.
		if Platform.IsPhone then
			deviceScale.Scale = 0.72
			root.Position = UDim2.new(0.5, 0, 1, -100)
		elseif Platform.IsTablet then
			deviceScale.Scale = 0.88
			root.Position = UDim2.new(0.5, 0, 1, -110)
		else
			deviceScale.Scale = 1
			root.Position = UDim2.new(0.5, 0, 1, -120)
		end
	end)

	box = UI.surface(root, UDim2.fromOffset(BOX_W, BOX_H), "panel", T.radius.panel, T.stroke.panel)
	box.Name = "DialogBox"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, 44)
	box.ZIndex = 21
	UI.gloss(box, T.radius.panel)

	-- NAME RIBBON, notched into the panel's top-left and overlapping it. Tinted per call
	-- by the caller's `accent` pair so each NPC keeps their own colour.
	namePlate = Instance.new("Frame")
	namePlate.Name = "NameTag"
	namePlate.AnchorPoint = Vector2.new(0, 0.5)
	namePlate.Position = UDim2.new(0, 196, 0, 44)
	namePlate.Size = UDim2.fromOffset(260, 40)
	namePlate.BackgroundColor3 = T.color.white
	namePlate.BorderSizePixel = 0
	namePlate.ZIndex = 26
	namePlate.Parent = root
	UI.corner(namePlate, T.radius.chip)
	UI.stroke(namePlate, T.stroke.control)
	UI.gloss(namePlate, T.radius.chip, 0.35)

	nameText = Instance.new("TextLabel")
	nameText.Name = "Value"
	nameText.Size = UDim2.fromScale(1, 1)
	nameText.BackgroundTransparency = 1
	nameText.Font = FONT
	nameText.TextSize = 19
	nameText.TextColor3 = T.color.white
	nameText.TextTruncate = Enum.TextTruncate.AtEnd
	nameText.ZIndex = 28
	nameText.Parent = namePlate
	UITheme.inkText(nameText, 2.6)

	lineText = Instance.new("TextLabel")
	lineText.Name = "Line"
	-- left edge clears the portrait's overhang; the reference centres its copy
	lineText.AnchorPoint = Vector2.new(0, 0)
	lineText.Position = UDim2.fromOffset(196, 26)
	lineText.Size = UDim2.fromOffset(BOX_W - 216, 84)
	lineText.BackgroundTransparency = 1
	lineText.Font = BODY
	lineText.TextSize = 18
	lineText.TextColor3 = Color3.fromRGB(255, 255, 255)
	lineText.TextWrapped = true
	lineText.TextXAlignment = Enum.TextXAlignment.Left
	lineText.TextYAlignment = Enum.TextYAlignment.Top
	lineText.ZIndex = 23
	lineText.Parent = box
	UITheme.inkText(lineText, 1.8)

	contDots = Instance.new("TextLabel")
	contDots.Name = "More"
	contDots.AnchorPoint = Vector2.new(0.5, 1)
	contDots.Position = UDim2.new(0.5, 0, 1, -6)
	contDots.Size = UDim2.fromOffset(40, 18)
	contDots.BackgroundTransparency = 1
	contDots.Font = FONT
	contDots.TextSize = 20
	contDots.Text = "\u{2022}\u{2022}\u{2022}"
	contDots.TextColor3 = T.color.textMuted
	contDots.ZIndex = 23
	contDots.Parent = box

	-- CLICK-ANYWHERE catcher over the panel: completes the typewriter, then advances.
	-- Sits under the buttons so a press on a real choice still reaches it.
	local skipHit = Instance.new("TextButton")
	skipHit.Name = "SkipHit"
	skipHit.Size = UDim2.fromScale(1, 1)
	skipHit.BackgroundTransparency = 1
	skipHit.Text = ""
	skipHit.AutoButtonColor = false
	skipHit.ZIndex = 22
	skipHit.Parent = box
	skipHit.Activated:Connect(function()
		if typing then finishTyping() end
	end)

	-- BUTTON ROW below the panel. Each button gets a slot wrapper: UI.button parents its
	-- hard shadow as a SIBLING, so bare buttons in a UIListLayout become six list items
	-- and shove each other out of the row.
	btnRow = Instance.new("Frame")
	btnRow.Name = "Choices"
	btnRow.AnchorPoint = Vector2.new(0.5, 0)
	btnRow.Position = UDim2.new(0.5, 0, 0, 44 + BOX_H + 10)
	btnRow.Size = UDim2.fromOffset(BOX_W - 40, 52)
	btnRow.BackgroundTransparency = 1
	btnRow.ZIndex = 25
	btnRow.Parent = root
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 14)
	rowLayout.Parent = btnRow

	local BTN_W, BTN_H = 250, 52
	local function slot(name, order)
		local s = Instance.new("Frame")
		s.Name = name
		s.Size = UDim2.fromOffset(BTN_W, BTN_H)
		s.BackgroundTransparency = 1
		s.LayoutOrder = order
		s.ZIndex = 25
		s.Parent = btnRow
		return s
	end

	local leaveSlot = slot("LeaveSlot", 1)
	leaveBtn = UI.button(leaveSlot, "Leave", "tab", UDim2.fromOffset(BTN_W, BTN_H))
	leaveBtn.Name = "Leave"
	leaveBtn.ZIndex = 26
	leaveText = leaveBtn:FindFirstChildWhichIsA("TextLabel")
	if leaveText then leaveText.ZIndex = 27; leaveText.TextSize = 20 end
	leaveBtn.Activated:Connect(function()
		-- captured BEFORE Hide(), which clears opts -- same order advance() uses for onDone
		local decline = (opts and opts.OnDecline and onLastLine()) and opts.OnDecline or nil
		M.Hide()
		if decline then decline() end
	end)

	local contSlot = slot("PrimarySlot", 2)
	contBtn = UI.button(contSlot, "OK", "green", UDim2.fromOffset(BTN_W, BTN_H))
	contBtn.Name = "Primary"
	contBtn.ZIndex = 26
	contText = contBtn:FindFirstChildWhichIsA("TextLabel")
	if contText then contText.ZIndex = 27; contText.TextSize = 20 end
	contBtn.Activated:Connect(advance)

	-- walk away from the NPC -> dismiss the dialogue
	RunService.Heartbeat:Connect(function()
		if not (root and root.Visible and anchorPart) then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - anchorPart.Position).Magnitude > 24 then M.Hide() end
	end)
end

function M.Show(npcName, dlgLines, accent, done, anchor, finalTxt, options)
	build()
	anchorPart = anchor
	opts = (type(options) == "table") and options or nil
	finalLabel = finalTxt or "OPEN SHOP \u{25B6}"
	lines = (type(dlgLines) == "table" and #dlgLines > 0) and dlgLines or { "..." }
	idx = 1
	onDone = done
	nameText.Text = npcName or "Merchant"
	UITheme.gradient(namePlate, (accent and accent[1]) or CF.amber1, (accent and accent[2]) or CF.amber2, 90)

	-- Portrait is rebuilt per conversation: the anchor differs by NPC, and some callers
	-- pass no anchor at all (the reward popups), which correctly yields no portrait and
	-- a text-only box rather than whoever spoke last.
	if portrait then portrait:Destroy(); portrait = nil end
	local oldBack = root:FindFirstChild("PortraitBackdrop")
	if oldBack then oldBack:Destroy() end
	portrait = buildPortrait(root, anchor)
	-- With no portrait the copy has no overhang to clear, so it reclaims that column.
	local textLeft = portrait and 196 or 26
	lineText.Position = UDim2.fromOffset(textLeft, 26)
	lineText.Size = UDim2.fromOffset(BOX_W - textLeft - 20, 84)
	namePlate.Position = UDim2.new(0, textLeft, 0, 44)

	contText = contBtn:FindFirstChildWhichIsA("TextLabel")
	if contText then
		contText.Text = (#lines > 1) and "NEXT \u{25B6}" or finalLabel
	end
	refreshLeaveLabel()

	root.Visible = true
	stageToken += 1
	local myStage = stageToken

	-- 1. THE STAGE CLEARS. The HUD goes at once (the reference's rails are gone
	--    inside ~200ms) while the world dims and drains colour together.
	hideHud()
	setMerchantBlur(true)
	if scrim then
		scrim.Visible = true
		scrim.BackgroundTransparency = 1
	end
	if not colourFx then
		colourFx = Instance.new("ColorCorrectionEffect")
		colourFx.Name = "MerchantDialogGrade"
		colourFx.Parent = game:GetService("Lighting")
	end
	colourFx.Saturation, colourFx.Brightness, colourFx.Enabled = 0, 0, true
	ramp(STAGE_IN, myStage, function(a)
		if colourFx then
			colourFx.Saturation = DESAT * a
			colourFx.Brightness = -0.06 * a
		end
	end)

	-- 2. THE BOX OPENS OUTWARD instead of popping. AnchorPoint is 0.5 on X, so
	--    driving Size expands it from its own centre, which is what the clip does.
	--    (A UIScale cannot do this -- it is uniform, and would squash the height.)
	local s = root:FindFirstChild("PopScale") or Instance.new("UIScale")
	s.Name = "PopScale"; s.Parent = root; s.Scale = 0.92
	TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if box then
		box.Size = UDim2.fromOffset(math.floor(BOX_W * 0.55), BOX_H)
		ramp(0.26, myStage, function(a)
			box.Size = UDim2.fromOffset(math.floor(BOX_W * (0.55 + 0.45 * a)), BOX_H)
		end)
	end

	-- 3. THE NPC RISES IN, 100ms behind the box, growing as it arrives -- the clip's
	--    lit copy stepping forward. Both the viewport and its backdrop ramp from
	--    their AUTHORED resting values so this can never leave them mistinted.
	if portrait then
		local back = root:FindFirstChild("PortraitBackdrop")
		local restImg = portrait.ImageTransparency
		local restBack = back and back.BackgroundTransparency or 0
		local ps = Instance.new("UIScale")
		ps.Name = "PortraitPop"; ps.Scale = 0.72; ps.Parent = portrait
		local bs
		if back then
			bs = Instance.new("UIScale")
			bs.Name = "PortraitPop"; bs.Scale = 0.72; bs.Parent = back
			back.BackgroundTransparency = 1
		end
		portrait.ImageTransparency = 1
		task.delay(0.10, function()
			if myStage ~= stageToken then return end
			ramp(0.32, myStage, function(a)
				if ps.Parent then ps.Scale = 0.72 + 0.28 * a end
				if portrait and portrait.Parent then
					portrait.ImageTransparency = 1 - a * (1 - restImg)
				end
				if back and back.Parent then
					if bs then bs.Scale = 0.72 + 0.28 * a end
					back.BackgroundTransparency = 1 - a * (1 - restBack)
				end
			end)
		end)
	end

	if SoundKit then
		pcall(function() SoundKit.play("panelOpen", nil, { volume = 0.12 }) end)
	end

	-- 4. FAILSAFES. hideHud turned off every other ScreenGui, the CoreGui and the
	--    topbar, and M.Hide is the only thing that puts them back -- so a death, a
	--    respawn or a caller that simply never closes us must still reach it.
	for _, c in ipairs(failsafeConns) do pcall(function() c:Disconnect() end) end
	table.clear(failsafeConns)
	table.insert(failsafeConns, player.CharacterRemoving:Connect(function() M.Hide() end))
	do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then table.insert(failsafeConns, hum.Died:Connect(function() M.Hide() end)) end
	end
	task.delay(180, function()
		if myStage == stageToken and root and root.Visible then
			warn("[MerchantDialog] failsafe closed a dialogue left open 180s -- restoring the HUD")
			M.Hide()
		end
	end)

	typeLine(lines[1])
end

function M.IsOpen()
	return root ~= nil and root.Visible
end

function M.Hide()
	onDone = nil
	lines = nil
	opts = nil
	anchorPart = nil
	typeToken += 1   -- kill any in-flight typewriter so it cannot write into a closed box
	typing = false
	if portraitConn then portraitConn:Disconnect(); portraitConn = nil end
	if portrait then portrait:Destroy(); portrait = nil end
	if root then
		local back = root:FindFirstChild("PortraitBackdrop")
		if back then back:Destroy() end
		root.Visible = false
	end

	-- UNSTAGE. The HUD comes back immediately -- there is no version of this where
	-- the player is left without it -- and the world brightens back over 180ms.
	-- Bumping stageToken first cancels every in-flight entrance ramp, so a dialogue
	-- closed mid-open cannot keep darkening the screen after it is gone.
	stageToken += 1
	local myStage = stageToken
	restoreHud()
	for _, c in ipairs(failsafeConns) do pcall(function() c:Disconnect() end) end
	table.clear(failsafeConns)
	setMerchantBlur(false)
	local fromS = colourFx and colourFx.Saturation or 0
	local fromB = colourFx and colourFx.Brightness or 0
	ramp(STAGE_OUT, myStage, function(a)
		if colourFx then
			colourFx.Saturation = fromS * (1 - a)
			colourFx.Brightness = fromB * (1 - a)
		end
	end)
	task.delay(STAGE_OUT + 0.05, function()
		if myStage ~= stageToken then return end
		if scrim then scrim.Visible = false; scrim.BackgroundTransparency = 1 end
		if colourFx then colourFx:Destroy(); colourFx = nil end
	end)
end

return M