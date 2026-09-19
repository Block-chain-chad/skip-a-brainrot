-- Centres MainUI's shop panels (Rocco's rocks, Enzo's upgrades, Lil Miss's charms all
-- share ShopFrame; Marco uses SellFrame).
--
-- WHY A SCRIPT RATHER THAN AUTHORED VALUES. MainUI is IgnoreGuiInset = true, so its
-- coordinate space starts at the very top of the WINDOW, above the topbar -- TabBar
-- depends on that, sitting at y -48..32. A frame at Position.Y = 0.5 in that space
-- therefore lands half the topbar too high, and the authored 0.45 pushed it higher again.
-- Measured live at 1530x576: the panel sat at y 1..401, its top edge under the topbar and
-- its centre 86px above the screen centre.
--
-- The topbar inset is NOT a constant across devices, so it is read at runtime instead of
-- being baked into the authored Position. Re-applied on viewport changes because
-- GetGuiInset reports differently once the client has finished laying out.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainUI")

local FRAMES = { "ShopFrame", "SellFrame" }

local function centre()
	local inset = GuiService:GetGuiInset().Y
	for _, name in ipairs(FRAMES) do
		local f = gui:FindFirstChild(name)
		if f and f:IsA("GuiObject") then
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.new(0.5, 0, 0.5, inset)
		end
	end
end

centre()
-- the panels are restyled at runtime (widened 360 -> 440, Bazaar chrome added), which can
-- land after this runs, so re-assert rather than setting once
for _, name in ipairs(FRAMES) do
	local f = gui:FindFirstChild(name)
	if f then
		f:GetPropertyChangedSignal("Size"):Connect(centre)
		f:GetPropertyChangedSignal("Visible"):Connect(centre)
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(centre)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(centre)
