--!strict
--[[ =========================================================================
PlayerTagClient -- draws the name-plate title a player has earned from the
season pass above their head.
---------------------------------------------------------------------------
The title is published by SeasonPassHandler as a Player ATTRIBUTE
(`EquippedTag`, already resolved to its display label). Attributes replicate to
every client automatically and re-replicate to late joiners, so this script
needs no remote, no join handshake, and no knowledge of who is watching -- the
same reasoning PetHandler gives for publishing its follow loadout that way.

One BillboardGui per player, rebuilt on respawn, removed when they leave or
clear the tag. Deliberately small and always-on-top-of-nothing: it sits ABOVE
the Roblox name display rather than replacing it.
========================================================================= ]]

local Players = game:GetService("Players")

local TAG_NAME = "SeasonTag"

local function clear(character: Model?)
	if not character then return end
	local head = character:FindFirstChild("Head")
	local old = head and head:FindFirstChild(TAG_NAME)
	if old then old:Destroy() end
end

local function draw(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	clear(character)

	local label = player:GetAttribute("EquippedTag")
	if type(label) ~= "string" or label == "" then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = TAG_NAME
	bb.Size = UDim2.fromOffset(200, 26)
	-- clear of the Roblox name/health display rather than fighting it
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	bb.Parent = head

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.Font = Enum.Font.FredokaOne
	txt.TextScaled = true
	txt.TextColor3 = Color3.fromRGB(255, 214, 120)
	txt.Text = label
	-- our own keyline and font; the game-wide UIPolish sweep would otherwise
	-- force GothamBold white over it
	txt:SetAttribute("NoPolish", true)
	txt.Parent = bb

	local ink = Instance.new("UIStroke")
	ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ink.LineJoinMode = Enum.LineJoinMode.Round
	ink.Thickness = 2.6
	ink.Color = Color3.fromRGB(26, 20, 16)
	ink.Parent = txt

	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 18
	cap.Parent = txt
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("EquippedTag"):Connect(function()
		draw(player)
	end)
	player.CharacterAdded:Connect(function()
		-- the Head arrives with the character, but the attribute may already be set
		task.defer(draw, player)
	end)
	if player.Character then draw(player) end
end

for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerAdded:Connect(watch)
