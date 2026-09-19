--!strict
--[[ =========================================================================
GamepadHint -- the little controller glyph that tells a console player which
button does this.
---------------------------------------------------------------------------
WHY. Roblox's console guidelines require "dynamic button icons that display
appropriately for Xbox and PlayStation". Until this module the game bound R2 to
throw and L3 to sprint and said so NOWHERE on screen -- a controller player
walked to the dock, saw a power bar, and had to guess. That is both a bad first
minute and the kind of thing a certification tester writes up.

HOW. UserInputService:GetImageForKeyCode returns the texture for the CONNECTED
controller, so an Xbox pad gets the Xbox glyph and a DualSense gets the
PlayStation one with no branching here -- which is what "dynamic" is asking for.
Verified live: ButtonR2 resolves to
  rbxasset://textures/ui/Controls/DefaultController/ButtonR2@2x.png

GetStringForKeyCode is NOT usable for this. It returns the literal "ButtonR2" --
a Lua enum name, not something you put in front of a player.

Usage:
	GamepadHint.attach(throwButton, Enum.KeyCode.ButtonR2)

The glyph shows only while a gamepad is the ACTIVE input and hides the moment
the player goes back to mouse or touch, so desktop and mobile are unchanged --
including for a PC player who happens to have a controller plugged in but is
using the mouse.
========================================================================= ]]

local UserInputService = game:GetService("UserInputService")

local GamepadHint = {}

local GLYPH_PX = 26
local TAG = "GamepadHint"

-- Weak keys: a glyph whose button is destroyed with its panel drops out of here
-- on its own rather than pinning the instance forever.
local watched: { [ImageLabel]: Enum.KeyCode } = setmetatable({}, { __mode = "k" }) :: any

local function padActive(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Gamepad1
		or last == Enum.UserInputType.Gamepad2
		or last == Enum.UserInputType.Gamepad3
		or last == Enum.UserInputType.Gamepad4
end

local function refresh()
	local on = padActive()
	for label, keyCode in pairs(watched) do
		if label.Parent then
			-- The image is resolved whether or not a pad is active right now, so the
			-- texture is already decoded when the player first picks one up. Setting
			-- it only while active left a visible blank square on the first frame.
			-- pcall: GetImageForKeyCode is newer than some clients, and a missing
			-- glyph must cost the hint, not the HUD it is attached to.
			local ok, img = pcall(function()
				return UserInputService:GetImageForKeyCode(keyCode)
			end)
			if ok and type(img) == "string" and img ~= "" and label.Image ~= img then
				label.Image = img
			end
			label.Visible = on and label.Image ~= ""
		else
			watched[label] = nil
		end
	end
end

-- Parks the glyph inside `host`, against its right edge. Idempotent: calling it
-- twice on the same button returns the glyph that is already there, so a layout
-- pass that re-runs cannot stack them.
function GamepadHint.attach(host: GuiObject, keyCode: Enum.KeyCode): ImageLabel?
	if not host then return nil end
	local existing = host:FindFirstChild(TAG)
	if existing and existing:IsA("ImageLabel") then
		watched[existing] = keyCode
		refresh()
		return existing
	end

	local l = Instance.new("ImageLabel")
	l.Name = TAG
	l.AnchorPoint = Vector2.new(1, 0.5)
	l.Position = UDim2.new(1, -8, 0.5, 0)
	l.Size = UDim2.fromOffset(GLYPH_PX, GLYPH_PX)
	l.BackgroundTransparency = 1
	l.ScaleType = Enum.ScaleType.Fit
	l.ZIndex = host.ZIndex + 5
	l.Visible = false
	l.Parent = host

	watched[l] = keyCode
	refresh()
	return l
end

UserInputService.LastInputTypeChanged:Connect(refresh)
-- The pad itself can change without the input TYPE changing -- unplug an Xbox
-- controller, plug in a DualSense -- and the glyph has to follow.
UserInputService.GamepadConnected:Connect(refresh)
UserInputService.GamepadDisconnected:Connect(refresh)

return GamepadHint
