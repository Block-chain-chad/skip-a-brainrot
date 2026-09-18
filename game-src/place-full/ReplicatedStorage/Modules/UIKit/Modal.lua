--!strict
-- Modal -- the kit's confirmation dialog (spec 2026-09-18 UI foundation §6.6,
-- handoff §19). Dangerous actions ONLY; deliberately no generic alert. Singleton:
-- opening a second confirm cancels the first. Dark translucent scrim that swallows
-- every input (nothing behind is clickable); scrim click, ESC and gamepad B cancel
-- only when `cancelable`. World blur is NOT part of the modal -- a caller that wants
-- it uses GameHUDClient's HUDPanelBlur machinery.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local S = require(script.Parent.SpecTheme)
local PC = require(script.Parent.PanelChrome)
local Platform = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Platform"))

export type Props = {
	title: string, body: string, loss: string?, confirmText: string, confirmKind: string?,
	cancelText: string?, cancelable: boolean?, onConfirm: () -> (), onCancel: (() -> ())?,
	parent: Instance?, titleInk: Color3?,
}
export type Handle = { close: () -> (), root: TextButton }

local Modal = {}

local DISPLAY_ORDER = 90
local host: ScreenGui? = nil
local current: { root: TextButton, cancel: () -> () }? = nil

--- Tests (Edit mode has no PlayerGui) hand the modal a ScreenGui to live in.
function Modal.setHost(gui: ScreenGui?)
	host = gui
end

local function ensureHost(): ScreenGui
	if host and host.Parent then return host :: ScreenGui end
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	local sg = Instance.new("ScreenGui")
	sg.Name = "UIKitModal"
	sg.DisplayOrder = DISPLAY_ORDER
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = pg
	host = sg
	return sg
end

function Modal.isOpen(): boolean
	return current ~= nil
end

function Modal.closeCurrent()
	if current then current.cancel() end
end

function Modal.confirm(props: Props): Handle
	if current then current.cancel() end -- singleton
	local parent: Instance = props.parent or ensureHost()
	local z = PC.zBase + 60
	local cancelable = props.cancelable ~= false
	local conns: { RBXScriptConnection } = {}
	local closed = false

	local scrim = Instance.new("TextButton")
	scrim.Name = "ModalScrim"
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 0.45
	scrim.BorderSizePixel = 0
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.Active = true -- swallows every input: nothing behind the modal is clickable
	scrim.ZIndex = z
	scrim:SetAttribute("NoPolish", true)
	scrim.Parent = parent

	local dialog = PC.plate({
		name = "Dialog", size = UDim2.fromOffset(560, 380),
		position = UDim2.fromScale(0.5, 0.5), anchor = Vector2.new(0.5, 0.5),
		colors = { S.Surface.Shell, S.Surface.Body }, radius = 32, outline = 7,
		zIndex = z + 1, parent = scrim, gloss = false,
	})
	dialog.Active = true -- a click on the dialog itself must not reach the scrim
	-- the 560x380 dialog is authored on the 1920x1080 sheet; the scrim stays full-screen,
	-- only the dialog scales with the viewport (Platform.Bind rebinds on class changes)
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = dialog
	local unbindFit = Platform.Bind(fit, 1920, 1080)

	PC.shout({
		name = "Title", text = props.title, size = 44,
		color = props.titleInk or S.TitleInk.default, strokeColor = Color3.new(1, 1, 1),
		frameSize = UDim2.new(1, -48, 0, 70), position = UDim2.fromOffset(24, 18),
		zIndex = z + 3, parent = dialog,
	})
	local body = PC.read({
		name = "Body", text = props.body, size = S.TextSize.RowSub, color = S.Surface.ReadInk,
		frameSize = UDim2.new(1, -64, 0, 120), position = UDim2.fromOffset(32, 96),
		zIndex = z + 3, parent = dialog, align = Enum.TextXAlignment.Center,
	})
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	if props.loss and props.loss ~= "" then
		local loss = PC.read({
			name = "Loss", text = props.loss, size = S.TextSize.RowSub, color = S.Role.Destructive[2],
			frameSize = UDim2.new(1, -64, 0, 44), position = UDim2.fromOffset(32, 222),
			zIndex = z + 3, parent = dialog, align = Enum.TextXAlignment.Center,
		})
		loss.TextWrapped = true
	end

	local function finish(fn: (() -> ())?)
		if closed then return end
		closed = true
		for _, c in ipairs(conns) do c:Disconnect() end
		if current and current.root == scrim then current = nil end
		if UserInputService.GamepadEnabled then GuiService.SelectedObject = nil end
		unbindFit()
		scrim:Destroy()
		if fn then
			local ok, err = pcall(fn)
			if not ok then
				warn(("[UIKit] Modal callback failed: %s\n%s"):format(tostring(err), debug.traceback()))
			end
		end
	end
	local function cancel() finish(props.onCancel) end
	local function confirm() finish(props.onConfirm) end

	local cancelBtn = PC.button({
		kind = "secondary", text = props.cancelText or "CANCEL", size = UDim2.fromOffset(220, 72),
		anchor = Vector2.new(0, 1), position = UDim2.new(0, 32, 1, -28), zIndex = z + 3,
		parent = dialog, onActivated = cancel, name = "Cancel",
	})
	PC.button({
		kind = props.confirmKind or "destructive", text = props.confirmText, size = UDim2.fromOffset(220, 72),
		anchor = Vector2.new(1, 1), position = UDim2.new(1, -32, 1, -28), zIndex = z + 3,
		parent = dialog, onActivated = confirm, name = "Confirm",
	})

	table.insert(conns, scrim.Activated:Connect(function()
		if cancelable then cancel() end
	end))
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if cancelable then cancel() end
		end
	end))
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = cancelBtn
	end

	current = { root = scrim, cancel = cancel }
	return { close = cancel, root = scrim }
end

return Modal
