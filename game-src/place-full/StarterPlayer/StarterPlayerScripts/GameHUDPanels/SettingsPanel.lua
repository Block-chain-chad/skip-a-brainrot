--!strict
-- SettingsPanel: kit README §3.3 Settings panel -- a GameHUDPanels consumer
-- module (StarterPlayer.StarterPlayerScripts.GameHUDPanels.SettingsPanel).
--
-- Contract (same as every other panel in this family -- see GoalsPanel):
--   return { Id = "settings", Build = function(ctx) -> Frame }
-- Build is called ONCE lazily on first open; the shell (GameHUDClient) parents
-- the returned Frame into ctx.host and owns Visible toggling on every
-- open/close after that -- this module never sets its own Parent or drives
-- its own open/close animation.
--
-- 2026-08-04 RESTYLE (1d/1e sweep): visual-only pass to the shipped cream
-- recipe -- orange header, cream body, white row cards with #e5d3ac borders
-- and #4a3416 ink labels, plus a per-panel backdrop BlurEffect
-- ("SettingsPanelBlur"). SUPERSEDED the same day by the style replacement
-- below; noted rather than deleted because two things it established are
-- still load-bearing and NOT part of the replacement: the blur block, and
-- the body padding warning (EXACTLY T.pad.panel 16 per side -- the
-- BODY_H/BODY_INNER_W math below depends on it, do NOT copy DailyPanel's
-- panelWide 18).
--
-- 2026-08-04 STYLE REPLACEMENT (Pet-Sim guide, "Roblox Simulator UI Style
-- Guide"): the cream look is gone game-wide. Three changes land in THIS file
-- and nothing else does:
--   1. header  -- per-panel accents are dead; Settings' orange #ffb02e ->
--                 #ff7d00 becomes the guide's one red bar (T.gradient.header)
--   2. body    -- UI.surface kind "cream" -> "window": same shared token
--                 (cream is now a legacy alias for it), honest name, and the
--                 colour underneath is the guide's light gray
--   3. rows    -- the three row cards (slider / toggle / skip-reveal) stop
--                 being white+tan and go back to being a plain dark kit "row"
--                 surface, which IS the guide's dark slot; their labels, the
--                 value readouts and the section headers return to white.
-- Everything else here is inherited, not edited: T.radius / T.stroke /
-- T.font all moved in the shared Tokens pass, so the slider tracks + knobs,
-- the quality tab buttons, the toggle switches, the 8 per-rarity chips, the
-- footer buttons and the dark redeem box pick up the new numbers for free
-- and are untouched below. The ONE label that still deliberately reads dark
-- is the redeem message, because it floats directly on the light-gray window
-- instead of on a card (T.color.textOnWindow). ALL wiring -- saves, seams,
-- applySettings, the drag machine, the blur watchers -- is byte-identical.
--
-- ============================================================================
-- SCOPE (task-10-brief, kit README §3.3 MINUS Reset Data):
--   AUDIO    -- Music / Sound FX sliders. Live SoundKit.SetCategoryVolume
--              during drag, SettingsSave:FireServer on release (click-to-set
--              behaves the same way: InputBegan sets + previews once,
--              InputEnded fires the save even with zero movement).
--   GRAPHICS -- Low/Medium/High segmented quality control. Client-local only
--              (kit gives it no server-authoritative effect beyond
--              persistence): toggles Lighting.Bloom/SunRays Enabled,
--              nil-guarded (see applyQuality below).
--   GAMEPLAY -- two real toggles, each bridged into an EXISTING mechanism
--              rather than invented fresh -- see "REAL SEAM" 1/2 below:
--                fastSpin        -> WheelClient's own `fastSpin` local
--                hideOwnBanners  -> RareCatchClient's own-catch banner
--   FOOTER   -- Redeem Code only (Reset Data intentionally absent, per
--              brief). See REDEEM CODE DEVIATION below -- this reuses a
--              REAL, already-live remote instead of the stub the brief's
--              literal text describes.
--
-- ============================================================================
-- REDEEM CODE DEVIATION (read before touching this section again):
-- The task brief asks for a brand-new stub RemoteFunction named "RedeemCode"
-- under ReplicatedStorage.Remotes that always answers `false, "Invalid
-- code"`. That name is NOT free: ReplicatedStorage.Remotes.RedeemCode
-- already exists, as a RemoteEvent, wired end-to-end to a REAL promo-code
-- system --
--   ServerScriptService.Modules.DailyRewardHandler.redeemCode(player, code)
--   ServerScriptService.Modules.CodeConfig (4 live codes: WELCOME, BRAINROT,
--     LAKETAHOE, SKIPMASTER)
--   StarterPlayer.StarterPlayerScripts.DailyRewardClient (the legacy Daily
--     HUD's own REDEEM box, still live)
-- Two problems with following the brief literally: (1) Roblox allows two
-- sibling instances with the same Name, so creating a SECOND "RedeemCode"
-- (a RemoteFunction) next to the real one makes every future
-- `remotes.RedeemCode` / `remotes:WaitForChild("RedeemCode")` lookup in the
-- game ambiguous by insertion order; (2) a stub that always fails would be a
-- real functional regression the instant a player types a genuine code
-- (e.g. "WELCOME") into this NEW panel instead of the old Daily UI and gets
-- told it's invalid. So this panel's footer fires the EXISTING RedeemCode
-- RemoteEvent directly (remotes.RedeemCode:FireServer(code) /
-- .OnClientEvent for the {Success, Message} reply) -- nothing new was
-- created server-side for redemption. Documented in task-10-report.md.
--
-- QUALITY ENUM DEVIATION: the brief spells the quality whitelist
-- {"Low","Med","High"}, but StarterPlayerScripts.GameHUDClient's own
-- ctx.state.settings default (shipped Task 3, already live) is
-- `quality = "Medium"`, and the kit's own settings.png capture labels the
-- middle button "Medium" in full. SettingsService validates "Medium" (not
-- "Med") for the same reason -- see that module's own header comment.
-- ============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService") -- FIX F4 (2026-07-30 fix wave): shared slider-release watcher, see buildSliderRow

local player = Players.LocalPlayer
local modules = ReplicatedStorage:WaitForChild("Modules")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local SoundKit = require(modules:WaitForChild("SoundKit"))
-- tier names + colours for the per-rarity Skip Catch Animation chips
local RarityConfig = require(modules:WaitForChild("RarityConfig"))

-- Bounded wait (matches ToastClient's own `WaitForChild(name, 10)` -- see
-- StarterPlayerScripts.ToastClient): SettingsSave is SELF-HEAL created by
-- SettingsService.Init() server-side, which only runs during Play. A bare
-- unbounded WaitForChild here would hang forever if this module is ever
-- require()'d outside Play (e.g. an Edit-mode compile probe), since nothing
-- will ever create the remote in that context.
local settingsSaveRemote = remotes:WaitForChild("SettingsSave", 5)
if not settingsSaveRemote then
	warn("[SettingsPanel] SettingsSave remote missing (no server this session?) -- saves will no-op")
end
local function fireSave(tbl)
	if settingsSaveRemote then
		settingsSaveRemote:FireServer(tbl)
	end
end

local SettingsPanel = { Id = "settings" }

local QUALITY_OPTIONS = { "Low", "Medium", "High" }
local QUALITY_SET = { Low = true, Medium = true, High = true }

----------------------------------------------------------- local palette (style replacement 2026-08-04, Pet-Sim guide)
-- Four of the six 1d/1e constants are DELETED, not repointed, because the
-- guide's values for them all live in Tokens now and the file reaches them
-- through T inside Build: HEADER_TOP/HEADER_BOT (-> T.gradient.header),
-- CARD_BORDER #e5d3ac (-> UI.stroke's own T.color.outline), BODY_INK #4a3416
-- (-> T.color.white on the dark row slots, T.color.textOnWindow for the one
-- label on the window). Only the two redeem-feedback inks stay local -- they
-- are semantic status colours with no token, re-pointed from the cream-era
-- pair to the guide's accent green/red bottom stops.
local MSG_GREEN = Color3.fromHex("#2E8A1C") -- redeem success -- PS99 cool: darker green for contrast on the light body (was #4FB42E)
local MSG_RED = Color3.fromHex("#D83E3E") -- redeem failure -- guide accent red (was #A8140F, the kit red gradient's bottom stop)

----------------------------------------------------------- GRAPHICS: client-local Lighting toggles, nil-guarded
-- Confirmed live before writing this: game.Lighting currently has NEITHER a
-- BloomEffect NOR a SunRaysEffect instance (only ColorCorrectionEffect +
-- Sky) -- so today every quality level below is a no-op in practice, on
-- purpose: FindFirstChildOfClass returns nil and both branches skip. The
-- moment a lighting artist adds those effects to Lighting, this starts
-- working with no code change. Low = both off, Medium = Bloom on/SunRays
-- off, High = both on (task brief).
local function applyQuality(quality)
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	local bloomOn = quality == "Medium" or quality == "High"
	local sunRaysOn = quality == "High"
	if bloom then
		bloom.Enabled = bloomOn
	end
	if sunRays then
		sunRays.Enabled = sunRaysOn
	end
end

----------------------------------------------------------- REAL SEAM 1: fastSpin -> WheelClient
-- WheelClient (StarterPlayerScripts.WheelClient) is a LocalScript, not a
-- ModuleScript -- it returns nothing, so nothing can require() it or reach
-- into its module-local `fastSpin` variable directly. Bridged instead
-- through a client-local Instance Attribute on the player (no server round
-- trip needed for the RUNTIME effect, matching WheelClient's own
-- "client-local comfort setting... no server call" comment for what the
-- attribute drives). WheelClient was given a matching edit (see its own
-- "fast spin" section) to read/listen on this SAME attribute instead of
-- only its in-wheel toggle button, so both controls stay in sync no matter
-- which one the player uses. `player` is nil-guarded here since this
-- function can run in a probe/Edit-mode context where LocalPlayer is nil.
local function applyFastSpin(on)
	if player then
		player:SetAttribute("FastSpinPref", on == true)
	end
end

----------------------------------------------------------- REAL SEAM 2: hideOwnBanners -> RareCatchClient
-- RareCatchClient's rareCatch.OnClientEvent handler now checks this SAME
-- attribute before enqueueing a banner for a catch that was YOURS (see its
-- own "UIKIT (Task 10)" comment) -- other players' banners are completely
-- unaffected, this only ever suppresses your own. Cheap seam: one added
-- guard clause there, no restructuring of its sound/queue logic.
local function applyHideOwnBanners(on)
	if player then
		player:SetAttribute("HideOwnBanners", on == true)
	end
end

----------------------------------------------------------- REAL SEAM 2b/2c: cinematic prefs -> CatchCinematic (Sequencer/Config)
-- Same bridge shape as REAL SEAM 1/2 above: a client-local Instance Attribute,
-- read at the moment it matters rather than pushed through a bespoke remote.
-- CatchCinematic.Sequencer reads CinematicReducedMotion at the START of every
-- run (mid-run changes take effect on the NEXT catch, same "read at time of
-- use" contract skipReveal already keeps); Config.qualityFor reads
-- CinematicLowQuality on every run too. Task 8 brief: one Reduced Motion row
-- plus a second Low Quality Cinematics row (cheap while already in here -- the
-- plan's quality tier needed a non-touch opt-in).
local function applyCinematicReducedMotion(on)
	if player then
		player:SetAttribute("CinematicReducedMotion", on == true)
	end
end

local function applyCinematicLowQuality(on)
	if player then
		player:SetAttribute("CinematicLowQuality", on == true)
	end
end

----------------------------------------------------------- REAL SEAM 2d: quickThrow -> ThrowCam
-- Same bridge shape again (2026-09-21, throw-pacing pass). ReplicatedStorage.Modules.
-- ThrowCam reads the QuickThrow attribute on every StoneThrown: true = no stone-
-- tracking camera at all -- the player keeps their own camera, sees the stone leave
-- the dock, and the reward pop lands the moment the server confirms the catch.
-- Built for grinding and for phones; off by default so the chase stays the first-
-- time experience.
local function applyQuickThrow(on)
	if player then
		player:SetAttribute("QuickThrow", on == true)
	end
end

----------------------------------------------------------- REAL SEAM 3: skipReveal -> CatchRevealClient / ClientMain
-- Per-rarity catch-animation skip (user request 2026-08-04, v2 -- "just
-- skip the actual catch animation... for whatever rarity they desire"):
-- the Pull ceremony is skipped only for the rarities the player picked;
-- ClientMain's text card announces those catches instead. One boolean
-- attribute per tier (SkipRevealCommon .. SkipRevealGod), read at time of
-- use, so a mid-session change covers the very next catch. The v1 camera
-- skip is gone on purpose -- the tracking camera always flies again.
local function applySkipReveal(t)
	if not player then return end
	t = type(t) == "table" and t or {}
	for _, tier in ipairs(RarityConfig) do
		player:SetAttribute("SkipReveal" .. tier.Name, t[tier.Name] == true)
	end
end

----------------------------------------------------------- top-level settings apply (require-time wiring, correctly outside Build -- same pattern IndexPanel's `discovered` uses)
-- Applied the instant a Settings payload is known, whether or not this panel
-- has EVER been opened -- audio volume / quality / the two gameplay seams
-- above all need to take effect on join, not only after a player happens to
-- visit Settings. `applied` also seeds the panel's own controls on first
-- Build (see below), and `onAppliedChanged` (assigned inside Build once the
-- widgets exist) keeps them in sync if a payload lands again afterward.
local applied = { music = 0.7, sfx = 1, quality = "Medium", fastSpin = false, hideOwnBanners = false, cinematicReducedMotion = false, cinematicLowQuality = false, quickThrow = false, skipReveal = {} }
local onAppliedChanged = nil

local function applySettings(s)
	if typeof(s) ~= "table" then
		return
	end
	if typeof(s.music) == "number" then
		applied.music = math.clamp(s.music, 0, 1)
		SoundKit.SetCategoryVolume("music", applied.music)
	end
	if typeof(s.sfx) == "number" then
		applied.sfx = math.clamp(s.sfx, 0, 1)
		SoundKit.SetCategoryVolume("sfx", applied.sfx)
	end
	if typeof(s.quality) == "string" and QUALITY_SET[s.quality] then
		applied.quality = s.quality
		applyQuality(applied.quality)
	end
	if typeof(s.fastSpin) == "boolean" then
		applied.fastSpin = s.fastSpin
		applyFastSpin(applied.fastSpin)
	end
	if typeof(s.hideOwnBanners) == "boolean" then
		applied.hideOwnBanners = s.hideOwnBanners
		applyHideOwnBanners(applied.hideOwnBanners)
	end
	if typeof(s.cinematicReducedMotion) == "boolean" then
		applied.cinematicReducedMotion = s.cinematicReducedMotion
		applyCinematicReducedMotion(applied.cinematicReducedMotion)
	end
	if typeof(s.cinematicLowQuality) == "boolean" then
		applied.cinematicLowQuality = s.cinematicLowQuality
		applyCinematicLowQuality(applied.cinematicLowQuality)
	end
	if typeof(s.quickThrow) == "boolean" then
		applied.quickThrow = s.quickThrow
		applyQuickThrow(applied.quickThrow)
	end
	if typeof(s.skipReveal) == "table" then
		applied.skipReveal = s.skipReveal
		applySkipReveal(applied.skipReveal)
	elseif s.skipAnimations == true and next(applied.skipReveal) == nil then
		-- v1 migration: the short-lived single Skip Animations toggle becomes
		-- "skip every rarity", so a player who had it ON keeps the behavior
		-- until they touch the chips (which then persists the new shape)
		local all = {}
		for _, tier in ipairs(RarityConfig) do all[tier.Name] = true end
		applied.skipReveal = all
		applySkipReveal(all)
	end
	if onAppliedChanged then
		onAppliedChanged()
	end
end

remotes.DataUpdated.OnClientEvent:Connect(function(snap)
	if typeof(snap) == "table" then
		applySettings(snap.Settings)
	end
end)
task.spawn(function()
	local ok, snap = pcall(function()
		return remotes.GetInitialData:InvokeServer()
	end)
	if ok and typeof(snap) == "table" then
		applySettings(snap.Settings)
	end
end)

----------------------------------------------------------- Build
-- 2026-08-09 HUD upgrade (design_handoff_hud_upgrade): the whole view is the
-- sheet's PanelChrome now -- shell 1000x1090 (body scrolls), SLATE header,
-- white rows on the light body ground, section headings OUTSIDE the rows
-- (30px shout on the ground, never grey-on-grey), slider knobs that overhang
-- their tracks, toggles whose word sits INSIDE the track opposite the knob,
-- and rarity chips that wear their own tier ramp when ON. ALL wiring --
-- saves, seams, applySettings, redeem, the blur watchers -- is preserved:
-- every control still calls the same apply* + fireSave paths.
local UIKitTop = modules:WaitForChild("UIKit")
local PC = require(UIKitTop:WaitForChild("PanelChrome"))
local UIB = require(UIKitTop:WaitForChild("Builders")) -- UI.touchMin for the chip row
local S = require(UIKitTop:WaitForChild("SpecTheme"))

-- RarityConfig tier names -> the sheet's chip vocabulary + ramps
local SHORT = { Common = "COM", Uncommon = "UNC", Rare = "RARE", Epic = "EPIC",
	Legendary = "LEG", Mythic = "MYTH", Secret = "SEC", God = "GOD" }

function SettingsPanel.Build(ctx)
	local ROW_RADIUS = 24
	local ROW_PAD_X = 22
	local SLIDER_ROW_H = 104
	local SEGMENT_ROW_H = 92
	local TOGGLE_ROW_H = 92
	local CHIPS_ROW_H = 152
	local FOOTER_H = 92

	local shell = PC.shell({
		name = "SettingsPanel",
		title = "SETTINGS",
		key = "settings",
		icon = S.Art.settings, -- PS99 restyle: rail sticker in the header
		size = S.ShellFor.settings,
		scroll = true,
	})
	shell.close.Activated:Connect(function()
		ctx.closePanel()
	end)
	local wrapper = shell.root
	local body = shell.body
	local z = shell.z

	local order = 0
	local function nextOrder() order += 1 return order end

	-- every row is a white plate on the body ground (sheet, Settings)
	local function rowCard(h)
		local card = PC.plate({
			name = "Row" .. nextOrder(),
			size = UDim2.new(1, 0, 0, h),
			colors = { S.Surface.RowTop, S.Surface.RowBottom },
			radius = ROW_RADIUS,
			outline = 6,
			zIndex = z + 2,
			parent = body,
			gloss = false,
		})
		card.LayoutOrder = order
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, ROW_PAD_X)
		pad.PaddingRight = UDim.new(0, ROW_PAD_X)
		pad.Parent = card
		return card
	end

	local function sectionHeader(text)
		PC.sectionHead({
			text = text, parent = body, layoutOrder = nextOrder(),
			zIndex = z + 2, size = 30,
		})
	end

	----------------------------------------------------------- slider row (AUDIO)
	-- 104 tall: label / 38 track with green fill / 52 gold knob overhanging /
	-- 32px value, 96 wide, right-aligned. Save fires as a TRAILING save 0.6s
	-- after the last movement (SettingsService drops saves within 0.5s of the
	-- last one, and a drag is a burst); live SoundKit preview on every step.
	local function buildSliderRow(labelText, key, initialValue)
		local card = rowCard(SLIDER_ROW_H)

		local LABEL_W, VALUE_W, INNER_GAP = 200, 96, 20

		PC.read({
			name = "Label",
			text = labelText,
			size = 28,
			frameSize = UDim2.new(0, LABEL_W, 0, 34),
			position = UDim2.new(0, 0, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			zIndex = z + 3,
			parent = card,
		})

		local valueLabel = PC.read({
			name = "Value",
			text = "0%",
			size = 32,
			align = Enum.TextXAlignment.Right,
			frameSize = UDim2.new(0, VALUE_W, 0, 34),
			position = UDim2.new(1, 0, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			zIndex = z + 3,
			parent = card,
		})

		local saveToken = 0
		local function queueSave()
			saveToken += 1
			local my = saveToken
			task.delay(0.6, function()
				if my ~= saveToken then return end
				fireSave({ [key] = applied[key] })
			end)
		end

		local slider = PC.slider({
			size = UDim2.new(1, -(LABEL_W + VALUE_W + INNER_GAP * 2), 0, 60),
			position = UDim2.new(0, LABEL_W + INNER_GAP, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			value = initialValue,
			zIndex = z + 3,
			parent = card,
			onChanged = function(v)
				applied[key] = v
				valueLabel.Text = tostring(math.floor(v * 100 + 0.5)) .. "%"
				SoundKit.SetCategoryVolume(key, v) -- live preview during drag
				queueSave()
			end,
		})
		valueLabel.Text = tostring(math.floor((initialValue or 0) * 100 + 0.5)) .. "%"

		-- a drag on the track must not also scroll the body
		slider.track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				body.ScrollingEnabled = false
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				body.ScrollingEnabled = true
			end
		end)

		return {
			setValue = function(v)
				if slider.isDragging() then
					return -- don't fight a live drag with a server echo
				end
				slider.set(v or 0)
				valueLabel.Text = tostring(math.floor((v or 0) * 100 + 0.5)) .. "%"
			end,
		}
	end

	----------------------------------------------------------- segmented quality row (GRAPHICS)
	local function buildSegmentedRow()
		local holderSlot = Instance.new("Frame")
		holderSlot.Name = "QualitySlot"
		holderSlot.LayoutOrder = nextOrder()
		holderSlot.Size = UDim2.new(1, 0, 0, SEGMENT_ROW_H)
		holderSlot.BackgroundTransparency = 1
		holderSlot.ZIndex = z + 2
		holderSlot.Parent = body

		local seg = PC.segmented({
			options = QUALITY_OPTIONS,
			selected = 2,
			size = UDim2.new(1, 0, 1, 0),
			zIndex = z + 2,
			parent = holderSlot,
			onChanged = function(_, opt)
				applyQuality(opt) -- immediate client-local preview
				fireSave({ quality = opt })
			end,
		})

		return {
			setValue = function(q)
				for idx, opt in ipairs(QUALITY_OPTIONS) do
					if opt == q then seg.set(idx) end
				end
			end,
		}
	end

	----------------------------------------------------------- toggle row (GAMEPLAY)
	local function buildToggleRow(labelText, initialOn, onToggle)
		local card = rowCard(TOGGLE_ROW_H)

		PC.read({
			name = "Label",
			text = labelText,
			size = 28,
			frameSize = UDim2.new(1, -(S.Chrome.ToggleSize.X + 20), 0, 34),
			position = UDim2.new(0, 0, 0.5, 0),
			anchor = Vector2.new(0, 0.5),
			zIndex = z + 3,
			parent = card,
		})

		local toggle = PC.toggle({
			position = UDim2.new(1, 0, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			on = initialOn,
			zIndex = z + 3,
			parent = card,
			onChanged = onToggle,
		})

		return {
			setValue = function(v)
				toggle.set(v == true, true)
			end,
		}
	end

	----------------------------------------------------------- skip-catch-animation row (GAMEPLAY): 8 per-rarity chips
	-- A chip wearing its tier ramp = that rarity's Pull ceremony is skipped.
	-- OFF = the neutral plate, so the row reads with the same vocabulary as
	-- the toggles above it. COM through GOD legible without reading (sheet).
	local function buildSkipRevealRow()
		local card = rowCard(CHIPS_ROW_H)

		PC.read({
			name = "Label",
			text = "Skip Catch Animation",
			size = 28,
			frameSize = UDim2.new(1, 0, 0, 34),
			position = UDim2.new(0, 0, 0, 12),
			zIndex = z + 3,
			parent = card,
		})

		local chipRow = Instance.new("Frame")
		chipRow.Name = "Chips"
		chipRow.BackgroundTransparency = 1
		chipRow.Position = UDim2.new(0, 0, 0, 62)
		chipRow.Size = UDim2.new(1, 0, 0, S.Chrome.ChipHeight)
		chipRow.ZIndex = z + 3
		chipRow.Parent = card
		local chipList = Instance.new("UIListLayout")
		chipList.FillDirection = Enum.FillDirection.Horizontal
		chipList.SortOrder = Enum.SortOrder.LayoutOrder
		chipList.Padding = UDim.new(0, 9)
		chipList.Parent = chipRow

		-- trailing save, one full-table save 0.6s after the last click
		local saveToken = 0
		local function queueSave()
			saveToken += 1
			local my = saveToken
			task.delay(0.6, function()
				if my ~= saveToken then return end
				local copy = {}
				for _, tier in ipairs(RarityConfig) do copy[tier.Name] = applied.skipReveal[tier.Name] == true end
				fireSave({ skipReveal = copy })
			end)
		end

		local chips = {}
		local function paintChip(tierName)
			local c = chips[tierName]
			if not c then return end
			local on = applied.skipReveal[tierName] == true
			local ramp = on and (S.Rarity[SHORT[tierName]] or S.Rarity.COM) or S.Action.Neutral
			c.gradient.Color = ColorSequence.new(ramp[1], ramp[2])
			c.label.TextTransparency = on and 0 or 0.25
			-- pale Neutral (PS99): the OFF plate is light, so the bubble word flips to
			-- dark ink with a white stroke; ON tier ramps keep the white shout + dark stroke
			c.label.TextColor3 = on and Color3.new(1, 1, 1) or S.Surface.ReadInk
			local wordStroke = c.label:FindFirstChildOfClass("UIStroke")
			if wordStroke then
				wordStroke.Color = on and S.Outline or Color3.new(1, 1, 1)
			end
		end

		for i, tier in ipairs(RarityConfig) do
			local chip = Instance.new("TextButton")
			chip.Name = tier.Name .. "Chip"
			chip.Text = ""
			chip.AutoButtonColor = false
			chip.LayoutOrder = i
			chip.Size = UDim2.new(1 / #RarityConfig, -math.ceil(9 * (#RarityConfig - 1) / #RarityConfig), 0, S.Chrome.ChipHeight)
			chip.BackgroundColor3 = S.Action.Neutral[1]
			chip.BorderSizePixel = 0
			chip.ZIndex = z + 4
			chip.Parent = chipRow
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, S.Chrome.ChipRadius)
			corner.Parent = chip
			local edge = Instance.new("UIStroke")
			edge.Thickness = 4
			edge.Color = S.Outline
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.LineJoinMode = Enum.LineJoinMode.Round
			edge.Parent = chip
			local grad = Instance.new("UIGradient")
			grad.Rotation = 90
			grad.Color = ColorSequence.new(S.Action.Neutral[1], S.Action.Neutral[2])
			grad.Parent = chip
			-- TOUCH FLOOR (2026-08-25). These rendered 53x33 on a phone-classed
			-- client -- under the 44px minimum, and they are the ONLY controls in
			-- this row, so there is nothing else to hit. The row has to make room:
			-- the chip grows, then its holder and the card behind it grow by exactly
			-- the same amount, or taller chips spill over the setting below. All
			-- eight chips solve to the same size, so the writes are idempotent.
			UIB.touchMin(chip, 44, function(c)
				local grown = c.Size.Y.Offset
				local extra = grown - S.Chrome.ChipHeight
				if extra > 0.5 then
					chipRow.Size = UDim2.new(1, 0, 0, grown)
					card.Size = UDim2.new(card.Size.X.Scale, card.Size.X.Offset, 0, CHIPS_ROW_H + extra)
				end
			end)

			local word = PC.shout({
				name = "Word",
				text = SHORT[tier.Name] or string.upper(tier.Name),
				size = S.TextSize.Chip,
				zIndex = z + 5,
				parent = chip,
				scaled = true,
			})
			word.Size = UDim2.new(1, -6, 0.7, 0)
			word.Position = UDim2.new(0, 3, 0.15, 0)

			chips[tier.Name] = { gradient = grad, label = word }
			paintChip(tier.Name)

			chip.MouseButton1Click:Connect(function()
				applied.skipReveal[tier.Name] = not (applied.skipReveal[tier.Name] == true)
				paintChip(tier.Name)
				applySkipReveal(applied.skipReveal)
				queueSave()
			end)
		end

		return {
			setValue = function()
				for _, tier in ipairs(RarityConfig) do paintChip(tier.Name) end
			end,
		}
	end

	----------------------------------------------------------- footer: Redeem Code (Reset Data intentionally absent -- see module header)
	local function buildFooter()
		local slot = Instance.new("Frame")
		slot.Name = "RedeemSlot"
		slot.LayoutOrder = nextOrder()
		slot.Size = UDim2.new(1, 0, 0, FOOTER_H)
		slot.BackgroundTransparency = 1
		slot.ZIndex = z + 2
		slot.Parent = body

		local btn = PC.pill({
			name = "RedeemCodeButton",
			text = "REDEEM CODE",
			colors = S.Action.Neutral,
			size = UDim2.new(1, 0, 1, 0),
			zIndex = z + 3,
			parent = slot,
		})

		local inputRow = Instance.new("Frame")
		inputRow.Name = "RedeemInputRow"
		inputRow.Size = UDim2.new(1, 0, 1, 0)
		inputRow.BackgroundTransparency = 1
		inputRow.Visible = false
		inputRow.ZIndex = z + 3
		inputRow.Parent = slot

		local GO_W = 130
		local box = Instance.new("TextBox")
		box.Name = "CodeBox"
		box.Size = UDim2.new(1, -(GO_W + 14), 1, 0)
		box.BackgroundColor3 = S.Surface.RowTop
		box.BorderSizePixel = 0
		box.Text = ""
		box.PlaceholderText = "Enter code\u{2026}"
		box.PlaceholderColor3 = S.Surface.ReadSub
		box.TextColor3 = S.Surface.ReadInk
		box.Font = S.Font.Read
		box.TextSize = 26
		box.ClearTextOnFocus = false
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ZIndex = z + 3
		box:SetAttribute("NoPolish", true)
		box.Parent = inputRow
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, ROW_RADIUS)
		bc.Parent = box
		local bs = Instance.new("UIStroke")
		bs.Thickness = 6
		bs.Color = S.Outline
		bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		bs.LineJoinMode = Enum.LineJoinMode.Round
		bs.Parent = box
		local boxPad = Instance.new("UIPadding")
		boxPad.PaddingLeft = UDim.new(0, 18)
		boxPad.PaddingRight = UDim.new(0, 18)
		boxPad.Parent = box

		local goBtn = PC.pill({
			name = "GoButton",
			text = "GO",
			colors = S.Action.Go,
			size = UDim2.fromOffset(GO_W, FOOTER_H),
			position = UDim2.new(1, 0, 0, 0),
			anchor = Vector2.new(1, 0),
			zIndex = z + 3,
			parent = inputRow,
		})

		local msg = PC.read({
			name = "Message",
			text = "",
			size = 22,
			frameSize = UDim2.new(1, -4, 0, 24),
			position = UDim2.new(0, 2, 0, -26),
			zIndex = z + 3,
			parent = slot,
		})

		btn.Activated:Connect(function()
			btn.Visible = false
			inputRow.Visible = true
		end)

		-- REAL, existing remote -- see module header REDEEM CODE DEVIATION.
		local function submit()
			local code = box.Text
			if typeof(code) ~= "string" or #code:gsub("%s+", "") == 0 then
				return
			end
			remotes.RedeemCode:FireServer(code)
		end
		goBtn.Activated:Connect(submit)
		box.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				submit()
			end
		end)

		remotes.RedeemCode.OnClientEvent:Connect(function(r)
			if typeof(r) ~= "table" or typeof(r.Message) ~= "string" then
				return
			end
			msg.Text = r.Message
			msg.TextColor3 = r.Success == true and MSG_GREEN or MSG_RED
			if r.Success == true then
				box.Text = ""
			end
		end)
	end

	----------------------------------------------------------- assemble
	sectionHeader("AUDIO")
	local musicCtl = buildSliderRow("Music", "music", applied.music)
	local sfxCtl = buildSliderRow("Sound FX", "sfx", applied.sfx)

	sectionHeader("GRAPHICS")
	local qualityCtl = buildSegmentedRow()
	qualityCtl.setValue(applied.quality)

	sectionHeader("GAMEPLAY")
	local fastSpinCtl = buildToggleRow("Fast Spin", applied.fastSpin, function(on)
		applied.fastSpin = on
		applyFastSpin(on)
		fireSave({ fastSpin = on })
	end)
	local hideBannersCtl = buildToggleRow("Hide My Catch Banners", applied.hideOwnBanners, function(on)
		applied.hideOwnBanners = on
		applyHideOwnBanners(on)
		fireSave({ hideOwnBanners = on })
	end)
	local reducedMotionCtl = buildToggleRow("Reduced Motion (Cinematics)", applied.cinematicReducedMotion, function(on)
		applied.cinematicReducedMotion = on
		applyCinematicReducedMotion(on)
		fireSave({ cinematicReducedMotion = on })
	end)
	local lowQualityCtl = buildToggleRow("Low Quality Cinematics", applied.cinematicLowQuality, function(on)
		applied.cinematicLowQuality = on
		applyCinematicLowQuality(on)
		fireSave({ cinematicLowQuality = on })
	end)
	local quickThrowCtl = buildToggleRow("Quick Throw (no rock camera)", applied.quickThrow, function(on)
		applied.quickThrow = on
		applyQuickThrow(on)
		fireSave({ quickThrow = on })
	end)
	local skipRevealCtl = buildSkipRevealRow()

	buildFooter()

	----------------------------------------------------------- kit README §5 client state shape
	local function syncState()
		if ctx.state and ctx.state.settings then
			ctx.state.settings.music = applied.music
			ctx.state.settings.sfx = applied.sfx
			ctx.state.settings.quality = applied.quality
			ctx.state.settings.toggles = ctx.state.settings.toggles or {}
			ctx.state.settings.toggles.fastSpin = applied.fastSpin
			ctx.state.settings.toggles.hideOwnBanners = applied.hideOwnBanners
			ctx.state.settings.toggles.cinematicReducedMotion = applied.cinematicReducedMotion
			ctx.state.settings.toggles.cinematicLowQuality = applied.cinematicLowQuality
			ctx.state.settings.toggles.quickThrow = applied.quickThrow
			ctx.state.settings.toggles.skipReveal = applied.skipReveal
		end
	end
	syncState()

	----------------------------------------------------------- re-sync every control if a settings payload lands again after Build
	onAppliedChanged = function()
		musicCtl.setValue(applied.music)
		sfxCtl.setValue(applied.sfx)
		qualityCtl.setValue(applied.quality)
		fastSpinCtl.setValue(applied.fastSpin)
		hideBannersCtl.setValue(applied.hideOwnBanners)
		reducedMotionCtl.setValue(applied.cinematicReducedMotion)
		lowQualityCtl.setValue(applied.cinematicLowQuality)
		quickThrowCtl.setValue(applied.quickThrow)
		skipRevealCtl.setValue()
		syncState()
	end

	----------------------------------------------------------- backdrop blur (unchanged recipe; see pre-restyle history)
	local BLUR_NAME = "SettingsPanelBlur"
	local function setBlur(on: boolean)
		-- centralised 2026-08-17: GameHUDClient owns the one shared HUDPanelBlur
		-- (blur-never-dim); a second per-panel BlurEffect only stacked on top
		do return end
		local existing = Lighting:FindFirstChild(BLUR_NAME)
		if on and not existing then
			local blur = Instance.new("BlurEffect")
			blur.Name = BLUR_NAME
			blur.Size = 8
			blur.Parent = Lighting
		elseif not on and existing then
			existing:Destroy()
		end
	end

	wrapper:GetPropertyChangedSignal("Visible"):Connect(function()
		setBlur(wrapper.Visible)
	end)

	-- any path that hides the HOST while this wrapper stays Visible must
	-- still kill the global BlurEffect; restore it when the host returns
	ctx.host:GetPropertyChangedSignal("Visible"):Connect(function()
		if not ctx.host.Visible then
			setBlur(false)
		elseif wrapper.Visible then
			setBlur(true)
		end
	end)

	return wrapper
end

return SettingsPanel
