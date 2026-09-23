-- TeleportFadeClient -- the curtain over a world hop.
--
-- WHY THIS EXISTS. A world jump is ~8,000 studs. The server asks the client to page the
-- destination in first (TeleportService.teleportCharacter -> RequestStreamAroundAsync),
-- but paging is not instant and it is not tidy: terrain arrives in chunks and visibly
-- pops and slides into place. This covers the whole hop so none of that is on screen.
--
-- The server owns the timing, not this script: it raises the curtain BEFORE it starts
-- yielding on the stream request and lowers it only once the character has actually been
-- placed. That is why there is no distance check or destination logic here -- if this
-- script ever decided for itself when to hide, it would be guessing at when the world
-- had finished loading.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local fadeRemote = remotes:WaitForChild("TeleportFade")

local FONT = Enum.Font.FredokaOne
local okTheme, UITheme = pcall(function() return require(ReplicatedStorage.Modules.UITheme) end)
if okTheme and UITheme and UITheme.Font then FONT = UITheme.Font end

local IN_TIME  = 0.22   -- must match TeleportService.CURTAIN_IN
local OUT_TIME = 0.35
local SETTLE   = 3.55   -- held after arrival: the last chunks land in this window
local FAILSAFE = 15     -- never leave a player staring at a black screen. Must stay well
                        -- above fade-in + stream wait + SETTLE + fade-out, or a slow hop
                        -- would trip it and yank the curtain during the hold.
local GROUND_WAIT = 3.0 -- longest we will wait for the floor to stream in under the player

local gui = Instance.new("ScreenGui")
gui.Name = "TeleportCurtain"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10000        -- above every panel; covering everything is the whole job
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local sheet = Instance.new("Frame")
sheet.Name = "Sheet"
sheet.Size = UDim2.fromScale(1, 1)
sheet.BackgroundColor3 = Color3.fromRGB(14, 11, 9)
sheet.BackgroundTransparency = 1
sheet.BorderSizePixel = 0
sheet.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.47)
title.Size = UDim2.fromOffset(520, 62)
title.BackgroundTransparency = 1
title.Font = FONT
title.Text = "TRAVELING"
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 236, 190)
title.TextTransparency = 1
title.Parent = sheet

local sub = Instance.new("TextLabel")
sub.Name = "Sub"
sub.AnchorPoint = Vector2.new(0.5, 0.5)
sub.Position = UDim2.fromScale(0.5, 0.545)
sub.Size = UDim2.fromOffset(420, 26)
sub.BackgroundTransparency = 1
sub.Font = FONT
sub.Text = "loading the world around you"
sub.TextScaled = true
sub.TextColor3 = Color3.fromRGB(176, 150, 116)
sub.TextTransparency = 1
sub.Parent = sheet

-- three pulsing dots: cheap, and it tells the player the game has not frozen
local dots = {}
for i = 1, 3 do
        local d = Instance.new("Frame")
        d.Name = "Dot" .. i
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.Position = UDim2.new(0.5, (i - 2) * 26, 0.60, 0)
        d.Size = UDim2.fromOffset(12, 12)
        d.BackgroundColor3 = Color3.fromRGB(255, 214, 140)
        d.BackgroundTransparency = 1
        d.BorderSizePixel = 0
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(1, 0)
        c.Parent = d
        d.Parent = sheet
        dots[i] = d
end

local shown = false
local token = 0
local pulse
-- forward declaration: raise()'s failsafe closes over this before it is assigned below.
-- Without the local it compiled as a GLOBAL, which works but leaks a name into _G.
local lowerNow

local function setText(t)
        for _, o in ipairs({ title, sub }) do
                TweenService:Create(o, TweenInfo.new(IN_TIME), { TextTransparency = t }):Play()
        end
end

local function raise()
        token += 1
        local mine = token
        shown = true
        gui.Enabled = true
        TweenService:Create(sheet, TweenInfo.new(IN_TIME), { BackgroundTransparency = 0 }):Play()
        setText(0)
        if not pulse then
                pulse = task.spawn(function()
                        local t = 0
                        while true do
                                t += 0.08
                                for i, d in ipairs(dots) do
                                        local a = math.sin(t * 4 + i * 0.9) * 0.5 + 0.5
                                        d.BackgroundTransparency = shown and (0.15 + a * 0.65) or 1
                                end
                                task.wait(0.08)
                        end
                end)
        end
        -- if the server never says we arrived, come down anyway
        task.delay(FAILSAFE, function()
                if shown and token == mine then
                        lowerNow()
                end
        end)
end

lowerNow = function()
        shown = false
        TweenService:Create(sheet, TweenInfo.new(OUT_TIME), { BackgroundTransparency = 1 }):Play()
        setText(1)
        for _, d in ipairs(dots) do
                TweenService:Create(d, TweenInfo.new(OUT_TIME), { BackgroundTransparency = 1 }):Play()
        end
        task.delay(OUT_TIME + 0.05, function()
                if not shown then gui.Enabled = false end
        end)
end

-- Turn the camera to face the arrival's look direction, keeping the player's zoom and
-- pitch. Sent only by arrivals that face somewhere specific (World 2's tunnel mouth, see
-- TeleportService portalDests .aim): otherwise the camera keeps whatever heading it had
-- before an 8,000-stud hop, which in the Cellar Pass could mean staring at the portal
-- home. Custom camera only -- a cutscene or reveal that owns the camera is left alone.
local function aimCamera(look)
        local cam = workspace.CurrentCamera
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not (cam and hrp) or cam.CameraType ~= Enum.CameraType.Custom then return end
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude < 1e-3 then return end
        flat = flat.Unit
        local focus = cam.Focus.Position
        local offset = cam.CFrame.Position - focus
        local dist = offset.Magnitude
        if dist < 1 then
                -- first person: just turn the view
                cam.CFrame = CFrame.lookAt(cam.CFrame.Position, cam.CFrame.Position + flat)
                return
        end
        local up = math.clamp(offset.Unit.Y, -0.9, 0.9)
        local back = -flat * math.sqrt(1 - up * up) + Vector3.new(0, up, 0)
        cam.CFrame = CFrame.lookAt(focus + back * dist, focus)
end

local function lower(look)
        -- Do NOT lift on a fixed timer. The server tells us the character has been PLACED,
        -- which is not the same as the world around it having finished arriving -- the
        -- floor itself can still be missing for a moment, and lifting then is exactly the
        -- "terrain shifting around" this curtain exists to hide.
        --
        -- So: wait until there is actually ground under the player, then hold a short
        -- settle for the surrounding chunks. Capped, because a player teleported over a
        -- genuine void would otherwise wait forever.
        local t0 = os.clock()
        while os.clock() - t0 < GROUND_WAIT do
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                        local rp = RaycastParams.new()
                        rp.FilterType = Enum.RaycastFilterType.Exclude
                        rp.FilterDescendantsInstances = { char }
                        if workspace:Raycast(hrp.Position, Vector3.new(0, -80, 0), rp) then
                                break
                        end
                end
                task.wait(0.08)
        end
        task.wait(SETTLE)
        if look then aimCamera(look) end
        if shown then lowerNow() end
end

fadeRemote.OnClientEvent:Connect(function(payload)
        local phase = typeof(payload) == "table" and payload.Phase or nil
        if phase == "Out" then
                raise()
        elseif phase == "In" then
                task.spawn(lower, typeof(payload.Look) == "Vector3" and payload.Look or nil)
        end
end)
