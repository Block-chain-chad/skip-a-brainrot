--[[ ==========================================================================
InteractionPrompt -- the walk-up prompt, on the kit (UI round 3, 2026-09-19).
---------------------------------------------------------------------------
One presentation for every ProximityPrompt in the world: the object's name
above, a white pill with the input cap and the ACTION as the strongest read:

            Rocco the Rock Dealer
         +-------------------------+
         |  [E]   SHOP             |
         +-------------------------+

InteractionPromptClient owns the lifecycle (it flips Default-style prompts to
Custom LOCALLY and calls attach/detach on PromptShown/PromptHidden); this
module only knows how to draw one prompt and play its states:

  local h = InteractionPrompt.attach(prompt, inputType)
  h.setInput(inputType)     -- keyboard / gamepad / touch glyph
  h.holdBegin() / h.holdEnd()  -- the hold fill over prompt.HoldDuration
  h.success()               -- the quick confirmation on Triggered
  h.destroy()

NOTHING ABOUT THE PROMPT ITSELF CHANGES: HoldDuration, MaxActivationDistance,
RequiresLineOfSight, Enabled, KeyboardKeyCode, GamepadKeyCode and the server's
Triggered wiring are all the prompt's own. On touch the pill is the button and
drives prompt:InputHoldBegin()/InputHoldEnd(), which is how a custom prompt
supports a tap (and a hold) on a handset.

Two optional attributes a prompt may carry (none do yet -- the seam is for the
next system that needs it): `PromptState = "locked"` greys the pill and
`PromptHint = "Needs a key"` puts that line under the action.

Calm until touched: the only motion is the settle-in on appear (Size), the hold
fill (Size), and a short flash on success. No loops.
========================================================================== ]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKitFolder = script.Parent
local PC = require(UIKitFolder:WaitForChild("PanelChrome"))
local S = require(UIKitFolder:WaitForChild("SpecTheme"))
local Platform = require(ReplicatedStorage.Modules:WaitForChild("Platform"))

local InteractionPrompt = {}

local PILL_W, PILL_H = 176, 46
local NAME_H = 22
local CAP = 34
local GAP = 6
local BOARD_W, BOARD_H = 240, NAME_H + GAP + PILL_H + 20   -- room for the hint line

local SETTLE_IN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local RELEASE = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The verb by prompt NAME first (reliable across the three world copies, which
-- word the same stall four ways), then the first word of ActionText.
local VERB_BY_NAME = {
	ShopPrompt = "SHOP", UpgradePrompt = "UPGRADE", SellPrompt = "SELL", EggPrompt = "OPEN",
	CharmPrompt = "CHARMS", SpinPrompt = "SPIN", StandPrompt = "CLAIM", LikePrompt = "LIKE",
	ChimPrompt = "TAKE", CellarPrompt = "UNLOCK", PetPrompt = "PET",
	TalkPrompt = "TALK", TungTalkPrompt = "TALK", TungCavePrompt = "TALK", MichelPrompt = "TALK",
}

function InteractionPrompt.actionFor(prompt: ProximityPrompt): string
	local byName = VERB_BY_NAME[prompt.Name]
	if byName then return byName end
	local first = tostring(prompt.ActionText or ""):match("^%s*([%a']+)")
	if first and #first > 0 then return string.upper(first) end
	return "USE"
end

local GAMEPAD_GLYPH = {
	ButtonX = "X", ButtonA = "A", ButtonB = "B", ButtonY = "Y",
	ButtonR1 = "RB", ButtonL1 = "LB", ButtonR2 = "RT", ButtonL2 = "LT",
}

function InteractionPrompt.glyphFor(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType?): string
	if inputType == Enum.ProximityPromptInputType.Touch then return "TAP" end
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return GAMEPAD_GLYPH[prompt.GamepadKeyCode.Name] or prompt.GamepadKeyCode.Name
	end
	local name = prompt.KeyboardKeyCode.Name
	if #name > 3 then name = name:sub(1, 3) end
	return name
end

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = inst; return c
end

function InteractionPrompt.attach(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType?, container: Instance?)
	local anchor = prompt.Parent
	if not anchor then return nil end

	local board = Instance.new("BillboardGui")
	board.Name = "InteractionPrompt"
	board.Adornee = anchor
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.ResetOnSpawn = false
	board.Size = UDim2.fromOffset(BOARD_W, BOARD_H)
	board.SizeOffset = Vector2.new(0, 0)
	-- the stock prompt sits at the part's centre; UIOffset is the prompt's own px nudge
	board.StudsOffset = Vector3.new(0, 0, 0)
	board.MaxDistance = math.max(prompt.MaxActivationDistance + 6, 12)
	board.ClipsDescendants = false
	board:SetAttribute("NoPolish", true)

	local scale = Instance.new("UIScale")
	scale.Name = "DeviceScale"
	scale.Scale = Platform.IsPhone and math.max(Platform.Widget(), 0.7) or 1
	scale.Parent = board

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Position = UDim2.fromOffset(prompt.UIOffset.X, prompt.UIOffset.Y)
	root.Parent = board

	-- object name, above the pill: white shout with the navy edge, like every HUD caption
	local nameLabel = PC.shout({
		name = "Object", text = tostring(prompt.ObjectText or ""), size = 17,
		color = Color3.new(1, 1, 1), strokeColor = S.Outline,
		frameSize = UDim2.new(1, 0, 0, NAME_H), position = UDim2.fromOffset(0, 0),
		zIndex = 2, parent = root,
	})
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Visible = (prompt.ObjectText or "") ~= ""

	-- the pill: a white kit plate; on touch it IS the button
	local pill = Instance.new("TextButton")
	pill.Name = "Pill"
	pill.Text = ""
	pill.AutoButtonColor = false
	pill.BackgroundColor3 = S.Surface.RowTop
	pill.BorderSizePixel = 0
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, NAME_H + GAP)
	pill.Size = UDim2.fromOffset(PILL_W, PILL_H)
	pill.ZIndex = 3
	pill.ClipsDescendants = true
	pill.Parent = root
	corner(pill, 16)
	do
		local s = Instance.new("UIStroke"); s.Thickness = 4; s.Color = S.Outline; s.LineJoinMode = Enum.LineJoinMode.Round; s.Parent = pill
		local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(S.Surface.RowTop, S.Surface.RowBottom); g.Parent = pill
	end

	-- hold fill: sweeps left to right behind the content over HoldDuration
	local fill = Instance.new("Frame")
	fill.Name = "HoldFill"
	fill.BackgroundColor3 = S.Action.GreenFill[1]
	fill.BackgroundTransparency = 0.25
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 4
	fill.Parent = pill

	-- the input cap: navy square with the key / button letter, or TAP on touch
	local cap = Instance.new("Frame")
	cap.Name = "Cap"
	cap.BackgroundColor3 = S.Outline
	cap.BorderSizePixel = 0
	cap.AnchorPoint = Vector2.new(0, 0.5)
	cap.Position = UDim2.new(0, 6, 0.5, 0)
	cap.Size = UDim2.fromOffset(CAP, CAP)
	cap.ZIndex = 5
	cap.Parent = pill
	corner(cap, 10)
	do local s = Instance.new("UIStroke"); s.Thickness = 2; s.Color = Color3.new(1, 1, 1); s.Transparency = 0.35; s.Parent = cap end
	local capLabel = PC.shout({ name = "Key", text = "E", size = 20, zIndex = 6, parent = cap, scaled = true, frameSize = UDim2.new(1, -4, 1, -4), position = UDim2.fromOffset(2, 2) })

	local action = PC.shout({
		name = "Action", text = InteractionPrompt.actionFor(prompt), size = 22,
		color = S.Surface.ReadInk, strokeColor = Color3.new(1, 1, 1), align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -(CAP + 18), 1, 0), position = UDim2.fromOffset(CAP + 14, 0),
		zIndex = 5, parent = pill, scaled = true,
	})

	-- optional hint under the pill (locked reason etc.)
	local hint = PC.shout({
		name = "Hint", text = tostring(prompt:GetAttribute("PromptHint") or ""), size = 13,
		color = Color3.new(1, 1, 1), strokeColor = S.Outline,
		frameSize = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, NAME_H + GAP + PILL_H + 2),
		zIndex = 2, parent = root,
	})
	hint.Visible = hint.Text ~= ""

	-- success flash: a green sheet over the pill for a beat
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = S.Action.Go[1]
	flash.BackgroundTransparency = 0.15
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.Visible = false
	flash.ZIndex = 7
	flash.Parent = pill

	local handle = { board = board }
	local holdTween: Tween? = nil

	local function applyLocked()
		local locked = prompt:GetAttribute("PromptState") == "locked"
		pill.BackgroundColor3 = locked and S.Role.DisabledButton[1] or S.Surface.RowTop
		local g = pill:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = locked and ColorSequence.new(S.Role.DisabledButton[1], S.Role.DisabledButton[2])
				or ColorSequence.new(S.Surface.RowTop, S.Surface.RowBottom)
		end
		action.TextTransparency = locked and 0.35 or 0
		capLabel.Text = locked and "\u{1F512}" or capLabel.Text
	end

	function handle.setInput(it: Enum.ProximityPromptInputType?)
		capLabel.Text = InteractionPrompt.glyphFor(prompt, it)
		if it == Enum.ProximityPromptInputType.Touch then
			cap.BackgroundColor3 = S.Action.Go[2]
		else
			cap.BackgroundColor3 = S.Outline
		end
		applyLocked()
	end

	function handle.holdBegin()
		if holdTween then holdTween:Cancel() end
		local dur = math.max(prompt.HoldDuration, 0.05)
		fill.Size = UDim2.fromScale(0, 1)
		holdTween = TweenService:Create(fill, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		holdTween:Play()
	end

	function handle.holdEnd()
		if holdTween then holdTween:Cancel(); holdTween = nil end
		TweenService:Create(fill, RELEASE, { Size = UDim2.fromScale(0, 1) }):Play()
	end

	function handle.success()
		if holdTween then holdTween:Cancel(); holdTween = nil end
		fill.Size = UDim2.fromScale(0, 1)
		flash.Visible = true
		-- a quick settle: the pill dips and comes back
		pill.Size = UDim2.fromOffset(math.floor(PILL_W * 0.94), math.floor(PILL_H * 0.94))
		TweenService:Create(pill, SETTLE_IN, { Size = UDim2.fromOffset(PILL_W, PILL_H) }):Play()
		task.delay(0.22, function() if flash.Parent then flash.Visible = false end end)
	end

	function handle.destroy()
		if holdTween then holdTween:Cancel(); holdTween = nil end
		board:Destroy()
	end

	-- TOUCH: the pill is the button. A press begins the hold, a release ends it --
	-- the same InputHoldBegin/End pair Roblox's own prompt UI uses on a handset,
	-- so a 0s prompt triggers on the tap and a held one fills like the stock UI.
	pill.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)
	pill.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)

	handle.setInput(inputType)

	-- appear: a small settle-in (the brief's rise / scale settle), once
	pill.Size = UDim2.fromOffset(math.floor(PILL_W * 0.86), math.floor(PILL_H * 0.86))
	TweenService:Create(pill, SETTLE_IN, { Size = UDim2.fromOffset(PILL_W, PILL_H) }):Play()

	board.Parent = container or prompt.Parent
	return handle
end

return InteractionPrompt
