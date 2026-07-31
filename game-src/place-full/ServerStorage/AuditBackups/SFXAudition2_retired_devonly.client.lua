-- RETIRED 2026-07-29: pulled out of StarterPlayerScripts so players cannot open it.
-- It shipped to every client and put a live sound board behind a button on the HUD.
--
-- Parked here in ServerStorage, which never replicates to clients, so this cannot
-- run where it is. Disabled is also set, deliberately: if it is ever dragged back
-- into StarterPlayerScripts it stays inert until someone clears that flag on purpose.
--
-- Kept rather than deleted because it carries the curated candidate lists for the
-- catch ladder, the wheel tick and the splash -- the pools those choices came from,
-- and the record of which families were rejected.
--
-- TO USE IT AGAIN: copy into StarterPlayerScripts, clear Disabled, playtest, then
-- move it back here. Do not ship it in StarterPlayerScripts.

-- _SFXAudition2 (board v2): click-to-hear audition board, cartoon game-feel pool. -- SFX2
-- Toggled by the small "SFX" TextButton bottom-left. Rows are grouped by SLOT -- SFX2
-- and play at that slot's shipping volume. [CURRENT] = whatever id SoundKit -- SFX2
-- ships right now (read live from ReplicatedStorage.Modules.SoundKit at run). -- SFX2
-- Candidate rows: [duration] name, sorted shortest-first within each slot. -- SFX2
-- Splash rows add a 1.6x button (the skip pitch-up). -- SFX2
-- Delete this ONE script to remove the whole board. -- SFX2
local Players = game:GetService("Players") -- SFX2
local SoundService = game:GetService("SoundService") -- SFX2
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- SFX2
local Debris = game:GetService("Debris") -- SFX2

local player = Players.LocalPlayer -- SFX2
local parentGui = (player and player:WaitForChild("PlayerGui")) or game:GetService("StarterGui") -- SFX2

-- live-wired defaults: read SoundKit.Ids at runtime so [CURRENT] stays truthful -- SFX2
local wired = {} -- SFX2
do -- SFX2
	local ok, kit = pcall(function() -- SFX2
		return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundKit")) -- SFX2
	end) -- SFX2
	if ok and typeof(kit) == "table" and typeof(kit.Ids) == "table" then -- SFX2
		for slot, v in pairs(kit.Ids) do -- SFX2
			wired[slot] = (tostring(v):gsub("rbxassetid://", "")) -- SFX2
		end -- SFX2
	end -- SFX2
end -- SFX2

-- ids kept as STRINGS: several are 15 digits and number tostring would mangle them -- SFX2
-- new pool v2: 57 cartoon/game-feel candidates, deduped by id, duration caps checked -- SFX2
local GROUPS = { -- SFX2
	{ slot = "cash", volume = 0.25, rows = { -- SFX2
		{ label = "[0.52s] coins_get", id = "607665037" }, -- SFX2
		{ label = "[0.69s] Success Correct Sound", id = "135165335432475" }, -- SFX2
		{ label = "[0.73s] Cash Collect Sound", id = "112763229157490" }, -- SFX2
		{ label = "[0.74s] Coin collect", id = "8646410774" }, -- SFX2
		{ label = "[0.86s] Cheez Coin", id = "109376364304066" }, -- SFX2
		{ label = "[0.87s] Coin Collect", id = "135483737426662" }, -- SFX2
		{ label = "[0.92s] pick_up", id = "7381723507" }, -- SFX2
		{ label = "[1.18s] Cash Collect", id = "77885036694063" }, -- SFX2
		{ label = "[1.31s] SpecialCoin", id = "6792280577" }, -- SFX2
		{ label = "[1.54s] UI - Level Up", id = "112485797063762" }, -- SFX2
	} }, -- SFX2
	{ slot = "uiClick", volume = 0.12, rows = { -- SFX2
		{ label = "[0.08s] balloon_pop_cute", id = "107763176353227" }, -- SFX2
		{ label = "[0.10s] Plop / Click", id = "119910592417841" }, -- SFX2
		{ label = "[0.10s] ui_tap-variant-01 (Material)", id = "3623733749" }, -- SFX2
		{ label = "[0.13s] plop (cheek)", id = "261732529" }, -- SFX2
		{ label = "[0.19s] cartoon_pop", id = "6586979979" }, -- SFX2
		{ label = "[0.22s] roblox_bubble_hit", id = "113835218571462" }, -- SFX2
		{ label = "[0.23s] pop two ui", id = "17815910619" }, -- SFX2
		{ label = "[0.25s] UI click SFX", id = "103866342467024" }, -- SFX2
		{ label = "[0.27s] Page (SFX)", id = "130167170451756" }, -- SFX2
		{ label = "[0.31s] Bubble Notification", id = "109385133702263" }, -- SFX2
	} }, -- SFX2
	{ slot = "splash", volume = 0.22, pitch = true, rows = { -- SFX2
		{ label = "[0.28s] Bubble Pop Hitsound", id = "119697580657161" }, -- SFX2
		{ label = "[0.39s] cartoon splash (aks_sukinsin)", id = "140727221118804" }, -- SFX2
		{ label = "[0.44s] cartoon splash (Starsation)", id = "111937445268981" }, -- SFX2
		{ label = "[0.45s] water droplet gmod", id = "102332681553777" }, -- SFX2
		{ label = "[0.48s] SLIME SQUISHY 1", id = "87295773843957" }, -- SFX2
		{ label = "[0.87s] Bubble Bloop Cute 1", id = "9112751536" }, -- SFX2
		{ label = "[0.93s] squish 1", id = "90416226721742" }, -- SFX2
	} }, -- SFX2
	{ slot = "panelOpen", volume = 0.15, rows = { -- SFX2
		{ label = "[0.12s] ui-simple-menu-open", id = "97861038165143" }, -- SFX2
		{ label = "[0.31s] mixkit dry pop-up notification", id = "17669542615" }, -- SFX2
		{ label = "[0.40s] Pop Up Sound!", id = "17481582653" }, -- SFX2
		{ label = "[0.55s] UI Popup", id = "135869563808171" }, -- SFX2
		{ label = "[0.63s] Twinkling SFX noise", id = "132990201173758" }, -- SFX2
		{ label = "[0.79s] Cartoon Jump BOING", id = "2772396665" }, -- SFX2
		{ label = "[0.85s] Roblox_UI_Whoosh_01", id = "15675024286" }, -- SFX2
		{ label = "[1.01s] cute-pop", id = "127044427614984" }, -- SFX2
		{ label = "[1.02s] Pop bubble", id = "132673746791429" }, -- SFX2
		{ label = "[1.03s] minimal-pop-click-ui", id = "17779566040" }, -- SFX2
	} }, -- SFX2
	{ slot = "panelClose", volume = 0.12, rows = { -- SFX2
		{ label = "[0.11s] ui-simple-menu-close", id = "110059957735733" }, -- SFX2
		{ label = "[0.28s] Roblox_UI_Cute_Goodbye", id = "15675081158" }, -- SFX2
		{ label = "[0.33s] Menu Close 1", id = "129716843702737" }, -- SFX2
		{ label = "[0.49s] Roblox_UI_Whoosh_02", id = "15675028888" }, -- SFX2
		{ label = "[0.54s] cartoon plop sound", id = "18145114696" }, -- SFX2
		{ label = "[0.68s] Bubble Wobble Comic Bloop 4", id = "9112752910" }, -- SFX2
		{ label = "[0.73s] menu close (CoreFrame)", id = "88861317075079" }, -- SFX2
		{ label = "[0.75s] slide whistle", id = "97197794979302" }, -- SFX2
		{ label = "[0.81s] Toon Hit Ground", id = "4660575211" }, -- SFX2
		{ label = "[1.01s] Blorp", id = "90087825083279" }, -- SFX2
	} }, -- SFX2
	{ slot = "fusion", volume = 0.3, rows = { -- SFX2
		{ label = "[1.30s] Success2", id = "118498912468172" }, -- SFX2
		{ label = "[1.56s] wooho succes22", id = "74439314522269" }, -- SFX2
		{ label = "[1.90s] Power_Up", id = "3406813517" }, -- SFX2
		{ label = "[1.90s] PowerUp.mp3", id = "84872960927850" }, -- SFX2
		{ label = "[2.00s] TaDa", id = "4757565956" }, -- SFX2
		{ label = "[2.04s] Cute level up (AshenS0los)", id = "105193542038988" }, -- SFX2
		{ label = "[2.04s] cute-level-up (Inkthirsty)", id = "17417730290" }, -- SFX2
		{ label = "[2.38s] Level_up", id = "3120909354" }, -- SFX2
		{ label = "[2.48s] Rewards Level Up - Next Tier", id = "134821092416328" }, -- SFX2
		{ label = "[2.70s] Roblox_UI_Cute_Pop", id = "15675055424" }, -- SFX2
	} }, -- SFX2
	-- Wheel ratchet. NOTE: the wheel restarts this every TICK_GAP (0.085s), so any
	-- sample LONGER than that gets cut off and smears -- which is exactly what the
	-- first pass (a 0.19s click at a 0.055s gap) did wrong. The rows at or under
	-- ~0.10s are the real candidates; the longer two are here for character only.
	{ slot = "wheelTick", volume = 0.40, rows = { -- SFX2
		{ label = "[0.08s] balloon_pop_cute", id = "107763176353227" }, -- SFX2
		{ label = "[0.10s] Plop / Click", id = "119910592417841" }, -- SFX2
		{ label = "[0.13s] plop (cheek)", id = "261732529" }, -- SFX2
		{ label = "[0.18s] bookclosed2 (wooden peg)", id = "4458781994" }, -- SFX2
		{ label = "[0.19s] cartoon_pop", id = "6586979979" }, -- SFX2
		{ label = "[0.25s] UI click SFX", id = "103866342467024" }, -- SFX2
		{ label = "[0.35s] lever-flip03 (mechanical)", id = "6003596258" }, -- SFX2
	} }, -- SFX2
	-- CATCH LADDER, one group per rarity. Rows are deliberately from DIFFERENT sound
	-- classes rather than one family at different sizes -- that was what made the
	-- first two ladders read as one sound eight ways. Each row plays at that rung's
	-- shipping volume, so a Common really is quiet here: that is the point.
	-- NOTE Mythic/Secret/God ship as LAYERED stacks; these rows are the lead layer
	-- only, so the real thing is bigger than what you hear here.
	{ slot = "catchCommon", volume = 0.13, rows = { -- SFX2
		{ label = "[0.08s] balloon_pop_cute", id = "107763176353227" }, -- SFX2
		{ label = "[0.18s] bookclosed2 (wooden tap)", id = "4458781994" }, -- SFX2
		{ label = "[0.28s] button", id = "4086020670" }, -- SFX2
		{ label = "[0.31s] Bubble Notification", id = "109385133702263" }, -- SFX2
		{ label = "[0.60s] earthcrumble1", id = "3848076724" }, -- SFX2
	} }, -- SFX2
	-- Pass-4 rows: rejected families (UI-success, bless, abyss, cork) deliberately
	-- left OUT of these lists so the board only offers directions not tried yet.
	{ slot = "catchUncommon", volume = 0.17, rows = { -- SFX2
		{ label = "[0.22s] roblox_bubble_hit", id = "113835218571462" }, -- SFX2
		{ label = "[0.48s] SLIME SQUISHY 1", id = "87295773843957" }, -- SFX2
		{ label = "[0.81s] Toon Hit Ground", id = "4660575211" }, -- SFX2
		{ label = "[0.92s] pick_up", id = "7381723507" }, -- SFX2
		{ label = "[0.93s] squish 1", id = "90416226721742" }, -- SFX2
	} }, -- SFX2
	{ slot = "catchRare", volume = 0.21, rows = { -- SFX2
		{ label = "[0.97s] magic-cast-a12", id = "4299512229" }, -- SFX2
		{ label = "[1.37s] brickburst2", id = "4307207693" }, -- SFX2
		{ label = "[1.49s] brickburst3", id = "4307208601" }, -- SFX2
		{ label = "[1.51s] magic-cast-a01", id = "3750958498" }, -- SFX2
		{ label = "[1.70s] ice-magic01", id = "747238556" }, -- SFX2
	} }, -- SFX2
	{ slot = "catchEpic", volume = 0.25, rows = { -- SFX2
		{ label = "[1.61s] electricity2 (crackle)", id = "4086009537" }, -- SFX2
		{ label = "[1.80s] flydash1 (whoosh)", id = "4085859074" }, -- SFX2
		{ label = "[1.87s] acid-burn3 (sizzle)", id = "3755119951" }, -- SFX2
		{ label = "[2.03s] swordswing4 (blade)", id = "4085938599" }, -- SFX2
		{ label = "[2.14s] magic-charge08 (rising)", id = "4299622114" }, -- SFX2
	} }, -- SFX2
	{ slot = "catchLegend", volume = 0.30, rows = { -- SFX2
		{ label = "[1.79s] earthburst1", id = "3778608737" }, -- SFX2
		{ label = "[2.02s] earthavalanche", id = "3848082818" }, -- SFX2
		{ label = "[2.04s] flydash2", id = "4085859364" }, -- SFX2
		{ label = "[2.08s] magic-cast-heavy03", id = "3750957896" }, -- SFX2
		{ label = "[2.20s] acid-burn1", id = "3755119108" }, -- SFX2
	} }, -- SFX2
	{ slot = "catchMythic", volume = 0.34, rows = { -- SFX2
		{ label = "[2.18s] magic-cast-heavy02", id = "3750956745" }, -- SFX2
		{ label = "[2.51s] magic-cast-heavy01", id = "3750956552" }, -- SFX2
		{ label = "[2.62s] ice-magic02", id = "632669170" }, -- SFX2
		{ label = "[2.97s] magic-cast-heavy14", id = "4299587602" }, -- SFX2
		{ label = "[3.52s] magic-cast-heavy05", id = "3750993877" }, -- SFX2
	} }, -- SFX2
	{ slot = "catchSecret", volume = 0.40, rows = { -- SFX2
		{ label = "[2.85s] magic-cast-b02", id = "3748210175" }, -- SFX2
		{ label = "[3.07s] magic-cast-heavy08", id = "4299585091" }, -- SFX2
		{ label = "[3.12s] magic-cast-b05", id = "3748209678" }, -- SFX2
		{ label = "[3.58s] magic-cast-heavy12", id = "4299586215" }, -- SFX2
		{ label = "[4.11s] magic-cast-b01", id = "3748209965" }, -- SFX2
	} }, -- SFX2
	{ slot = "catchGod", volume = 0.54, rows = { -- SFX2
		{ label = "[2.01s] bling BIG", id = "4612374036" }, -- SFX2
		{ label = "[2.38s] Level_up", id = "3120909354" }, -- SFX2
		{ label = "[2.45s] curse01", id = "3750940830" }, -- SFX2
		{ label = "[2.56s] abyssappear", id = "3755104468" }, -- SFX2
		{ label = "[2.70s] Roblox_UI_Cute_Pop", id = "15675055424" }, -- SFX2
	} }, -- SFX2
} -- SFX2

local function play(id, vol, speed) -- SFX2
	local s = Instance.new("Sound") -- SFX2
	s.Name = "SFXAudition2" -- SFX2
	s.SoundId = "rbxassetid://" .. id -- SFX2
	s.Volume = vol -- SFX2
	s.PlaybackSpeed = speed or 1 -- SFX2
	s.Parent = SoundService -- SFX2
	s:Play() -- SFX2
	Debris:AddItem(s, 6) -- SFX2
end -- SFX2

local gui = Instance.new("ScreenGui") -- SFX2
gui.Name = "SFXAudition2UI" -- SFX2
gui.ResetOnSpawn = false -- SFX2
gui.DisplayOrder = 100 -- SFX2
gui.Parent = parentGui -- SFX2

local toggle = Instance.new("TextButton") -- SFX2
toggle.Name = "Toggle" -- SFX2
toggle.AnchorPoint = Vector2.new(0, 1) -- SFX2
toggle.Position = UDim2.new(0, 12, 1, -14) -- SFX2
toggle.Size = UDim2.fromOffset(54, 30) -- SFX2
toggle.BackgroundColor3 = Color3.fromRGB(35, 38, 48) -- SFX2
toggle.TextColor3 = Color3.fromRGB(255, 255, 255) -- SFX2
toggle.Font = Enum.Font.GothamBold -- SFX2
toggle.TextSize = 14 -- SFX2
toggle.Text = "SFX" -- SFX2
toggle.BorderSizePixel = 0 -- SFX2
toggle.ZIndex = 100 -- SFX2
toggle.Parent = gui -- SFX2
local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(0, 8) tc.Parent = toggle -- SFX2

local panel = Instance.new("Frame") -- SFX2
panel.Name = "Panel" -- SFX2
panel.AnchorPoint = Vector2.new(0, 1) -- SFX2
panel.Position = UDim2.new(0, 12, 1, -52) -- SFX2
panel.Size = UDim2.fromOffset(370, 440) -- SFX2
panel.BackgroundColor3 = Color3.fromRGB(28, 31, 40) -- SFX2
panel.BorderSizePixel = 0 -- SFX2
panel.Visible = false -- SFX2
panel.ZIndex = 100 -- SFX2
panel.Parent = gui -- SFX2
local pc = Instance.new("UICorner") pc.CornerRadius = UDim.new(0, 10) pc.Parent = panel -- SFX2

local titleL = Instance.new("TextLabel") -- SFX2
titleL.BackgroundTransparency = 1 -- SFX2
titleL.Size = UDim2.new(1, -16, 0, 28) -- SFX2
titleL.Position = UDim2.new(0, 8, 0, 2) -- SFX2
titleL.Font = Enum.Font.GothamBold -- SFX2
titleL.TextSize = 14 -- SFX2
titleL.TextColor3 = Color3.fromRGB(255, 255, 255) -- SFX2
titleL.TextXAlignment = Enum.TextXAlignment.Left -- SFX2
titleL.Text = "SFX AUDITION v2 \u{2014} cartoon pool \u{2014} click PLAY" -- SFX2
titleL.ZIndex = 101 -- SFX2
titleL.Parent = panel -- SFX2

local list = Instance.new("ScrollingFrame") -- SFX2
list.Size = UDim2.new(1, -12, 1, -38) -- SFX2
list.Position = UDim2.new(0, 6, 0, 32) -- SFX2
list.BackgroundTransparency = 1 -- SFX2
list.BorderSizePixel = 0 -- SFX2
list.ScrollBarThickness = 6 -- SFX2
list.CanvasSize = UDim2.new() -- SFX2
list.AutomaticCanvasSize = Enum.AutomaticSize.Y -- SFX2
list.ZIndex = 101 -- SFX2
list.Parent = panel -- SFX2
local layout = Instance.new("UIListLayout") -- SFX2
layout.Padding = UDim.new(0, 4) -- SFX2
layout.SortOrder = Enum.SortOrder.LayoutOrder -- SFX2
layout.Parent = list -- SFX2

local order = 0 -- SFX2
local function addHeader(text) -- SFX2
	order += 1 -- SFX2
	local h = Instance.new("TextLabel") -- SFX2
	h.BackgroundColor3 = Color3.fromRGB(48, 52, 66) -- SFX2
	h.BorderSizePixel = 0 -- SFX2
	h.Size = UDim2.new(1, -8, 0, 24) -- SFX2
	h.Font = Enum.Font.GothamBold -- SFX2
	h.TextSize = 13 -- SFX2
	h.TextColor3 = Color3.fromRGB(255, 216, 107) -- SFX2
	h.TextXAlignment = Enum.TextXAlignment.Left -- SFX2
	h.Text = "  " .. text -- SFX2
	h.LayoutOrder = order -- SFX2
	h.ZIndex = 102 -- SFX2
	h.Parent = list -- SFX2
	local hc = Instance.new("UICorner") hc.CornerRadius = UDim.new(0, 6) hc.Parent = h -- SFX2
end -- SFX2

local function addRow(group, row) -- SFX2
	order += 1 -- SFX2
	local tag = row.tag or "" -- SFX2
	local r = Instance.new("Frame") -- SFX2
	r.BackgroundColor3 = Color3.fromRGB(37, 40, 52) -- SFX2
	r.BorderSizePixel = 0 -- SFX2
	r.Size = UDim2.new(1, -8, 0, 28) -- SFX2
	r.LayoutOrder = order -- SFX2
	r.ZIndex = 102 -- SFX2
	r.Parent = list -- SFX2
	local rc = Instance.new("UICorner") rc.CornerRadius = UDim.new(0, 6) rc.Parent = r -- SFX2

	local lbl = Instance.new("TextLabel") -- SFX2
	lbl.BackgroundTransparency = 1 -- SFX2
	lbl.Size = UDim2.new(1, group.pitch and -122 or -70, 1, 0) -- SFX2
	lbl.Position = UDim2.new(0, 8, 0, 0) -- SFX2
	lbl.Font = Enum.Font.Gotham -- SFX2
	lbl.TextSize = 11 -- SFX2
	lbl.TextColor3 = (tag == "CURRENT") and Color3.fromRGB(126, 255, 148) or Color3.fromRGB(225, 228, 238) -- SFX2
	lbl.TextXAlignment = Enum.TextXAlignment.Left -- SFX2
	lbl.TextTruncate = Enum.TextTruncate.AtEnd -- SFX2
	lbl.Text = (tag ~= "" and ("[" .. tag .. "]  ") or "") .. row.label -- SFX2
	lbl.ZIndex = 103 -- SFX2
	lbl.Parent = r -- SFX2

	local function mkBtn(text, xOff, w, speed) -- SFX2
		local b = Instance.new("TextButton") -- SFX2
		b.AnchorPoint = Vector2.new(1, 0.5) -- SFX2
		b.Position = UDim2.new(1, xOff, 0.5, 0) -- SFX2
		b.Size = UDim2.fromOffset(w, 22) -- SFX2
		b.BackgroundColor3 = Color3.fromRGB(66, 132, 88) -- SFX2
		b.TextColor3 = Color3.fromRGB(255, 255, 255) -- SFX2
		b.Font = Enum.Font.GothamBold -- SFX2
		b.TextSize = 11 -- SFX2
		b.Text = text -- SFX2
		b.BorderSizePixel = 0 -- SFX2
		b.ZIndex = 103 -- SFX2
		b.Parent = r -- SFX2
		local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 6) bc.Parent = b -- SFX2
		b.MouseButton1Click:Connect(function() -- SFX2
			play(row.id, group.volume, speed) -- SFX2
		end) -- SFX2
		return b -- SFX2
	end -- SFX2

	mkBtn("PLAY", -4, 56, nil) -- SFX2
	if group.pitch then -- SFX2
		local b = mkBtn("1.6x", -64, 46, 1.6) -- SFX2
		b.BackgroundColor3 = Color3.fromRGB(70, 110, 160) -- SFX2
	end -- SFX2
end -- SFX2

for _, group in ipairs(GROUPS) do -- SFX2
	addHeader(("%s   (vol %.2f, %d new)"):format(group.slot, group.volume, #group.rows)) -- SFX2
	local cur = wired[group.slot] -- SFX2
	addRow(group, { tag = "CURRENT", label = "wired: " .. (cur or "?"), id = cur or "0" }) -- SFX2
	for _, row in ipairs(group.rows) do -- SFX2
		addRow(group, row) -- SFX2
	end -- SFX2
end -- SFX2

toggle.MouseButton1Click:Connect(function() -- SFX2
	panel.Visible = not panel.Visible -- SFX2
end) -- SFX2
