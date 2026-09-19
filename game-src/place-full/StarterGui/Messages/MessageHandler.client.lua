-- Made by @FlayoDev

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DisplayRemote = ReplicatedStorage:WaitForChild("DisplayGlobalAnnouncement")

local gui = script.Parent
local container = gui.Container
local template = container.AnnouncementMessage

-- Config (Attributes on this ScreenGui, editable in the Properties panel):
-- FadeTime (number)       -- seconds the fade in/out animation takes
-- DisplayDuration (number) -- seconds the message stays fully visible
local FADE_TIME = gui:GetAttribute("FadeTime") or 0.5

local fadeTweenInfo = TweenInfo.new(
	FADE_TIME,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.Out
)

local function setHidden(messageFrame: Frame)
	local background = messageFrame.Background
	local textLabel = background.TextLabel

	background.BackgroundTransparency = 1
	textLabel.TextTransparency = 1
	textLabel.UIStroke.Transparency = 1
end

local function fadeIn(messageFrame: Frame)
	local background = messageFrame.Background
	local textLabel = background.TextLabel

	TweenService:Create(background, fadeTweenInfo, {BackgroundTransparency = 0}):Play()
	TweenService:Create(textLabel, fadeTweenInfo, {TextTransparency = 0}):Play()
	TweenService:Create(textLabel.UIStroke, fadeTweenInfo, {Transparency = 0}):Play()
end

local function fadeOut(messageFrame: Frame)
	local background = messageFrame.Background
	local textLabel = background.TextLabel

	TweenService:Create(background, fadeTweenInfo, {BackgroundTransparency = 1}):Play()
	TweenService:Create(textLabel, fadeTweenInfo, {TextTransparency = 1}):Play()
	local strokeTween = TweenService:Create(textLabel.UIStroke, fadeTweenInfo, {Transparency = 1})
	strokeTween:Play()

	strokeTween.Completed:Wait()
end

local function displayMessage(message: string, duration: number)
	local messageFrame = template:Clone()
	messageFrame.Background.TextLabel.Text = message
	messageFrame.Visible = true

	setHidden(messageFrame)
	messageFrame.Parent = container

	fadeIn(messageFrame)
	script.Sound:Play()
	task.wait(duration)
	fadeOut(messageFrame)

	messageFrame:Destroy()
end

DisplayRemote.OnClientEvent:Connect(displayMessage)