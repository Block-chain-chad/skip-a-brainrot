-- EggShopClient -- Forest Egg Shop panel: 5-egg buy list with data-driven odds,
-- a emerald chip, and the daily-quest mini list. Opens via the EggStall's
-- ProximityPrompt on the client (server never gates the OPEN, only the BUY).
--
-- ODDS ARE ALWAYS VISIBLE AND NEVER HARD-CODED: every percentage rendered here
-- comes from iterating EggConfig's own egg.Table at runtime -- the server rolls
-- from those exact same rows (EggHandler.RollFor), so shown odds can never
-- drift from real odds (Roblox requires published odds for paid random items).
--
-- The hatch itself (eggs, cracks, burst, reveal, plates) is ReplicatedStorage.Modules.
-- EggHatch since 2026-09-21; playHatch(result), further down, hands every EggResult to
-- it and hides / restores this panel around the run.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local EggConfig = require(ReplicatedStorage.Modules.EggConfig)
local BrainrotConfig = require(ReplicatedStorage.Modules.BrainrotConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SideRail = require(ReplicatedStorage.Modules.SideRail)
local BrainrotThumb = require(ReplicatedStorage.Modules.BrainrotThumb)
local RarityFX = require(ReplicatedStorage.Modules.RarityFX)
local SoundKit = require(ReplicatedStorage.Modules.SoundKit)
-- Emerald's face, drawn from primitives (UIKit.IconArt). pcall'd so a missing
-- module leaves the shop working with the old emoji rather than failing to open.
local okIconArt, IconArt = pcall(function()
	return require(ReplicatedStorage.Modules.UIKit.IconArt)
end)
if not okIconArt then IconArt = nil end

-- The kit itself. NOT pcall'd, unlike IconArt: the panel's shell, header and
-- rows are built out of these, so a failure here is not a degraded icon, it is
-- no shop at all -- better to throw at require time than to nil-index halfway
-- through building the panel.
local T = require(ReplicatedStorage.Modules.UIKit.Tokens)
local UI = require(ReplicatedStorage.Modules.UIKit.Builders)
-- 2026-09-18 UI ROUND 2: the header wears the kit's white-shell language (bubble
-- title, kit BUY GEMS, the pink kit close) so the egg shop stops being the one
-- coloured-slab header left in the game. Cards, odds, buy flow and the reveal are
-- untouched apart from the discount pip, which now sits INSIDE its button.
local PC = require(ReplicatedStorage.Modules.UIKit.PanelChrome)
local S = require(ReplicatedStorage.Modules.UIKit.SpecTheme)

local CF = UITheme.Camp
local BZ = UITheme.Bazaar   -- Bazaar dark stall-shop palette: used by the shop toast below
local FONT = UITheme.Font
local WORLD_ID = "Forest"
local world = EggConfig.GetWorld(WORLD_ID)

-- creature name -> tier colour, same lookup pattern BackpackClient/EggHandler use
local PetConfig = require(ReplicatedStorage.Modules.PetConfig)

local tierByName, rarityByName = {}, {}
for _, t in ipairs(RarityConfig) do tierByName[t.Name] = t end
for _, e in ipairs(BrainrotConfig.List or BrainrotConfig) do rarityByName[e.Name] = e.Rarity end

-- Egg tables name PETS as of 2026-08-01, so rarity resolves through PetConfig
-- first. The BrainrotConfig fallback is still live for the ten retired stand-in
-- pets, which are brainrots and have no PetConfig-only rarity of their own.
-- Pet tiers (Rare..Secret) all exist in RarityConfig, so the colour lookup is
-- unchanged either way.
local function rarityOf(creatureName)
	local id = PetConfig.IdFor(creatureName)
	local def = id and PetConfig.Pets[id]
	if def then return def.Rarity end
	return rarityByName[creatureName]
end

-- The hatch reveal spins the PET that was just hatched. BrainrotThumb.master is
-- hardwired to ReplicatedStorage.BrainrotModels, so pets need their own lookup
-- against PetModels (child named after the imported .glb, per PetConfig.Model),
-- falling through to BrainrotThumb for the retired stand-ins. Masters are cached
-- per key exactly like BrainrotThumb does, so a reveal clones rather than
-- rebuilds.
local petMasters = {}
local function petMaster(creatureName, petId)
	local key = petId or creatureName
	if key and petMasters[key] then return petMasters[key] end
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local def = petId and PetConfig.Pets[petId]
	local src = folder and ((def and def.Model and folder:FindFirstChild(def.Model))
		or (creatureName and folder:FindFirstChild(creatureName)))
	if src then
		local m = src:Clone()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
		end
		if key then petMasters[key] = m end
		return m
	end
	return BrainrotThumb.master(creatureName)
end

---------------------------------------------------------------- tiny UI helper
local function new(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do inst[k] = v end
	inst.Parent = parent
	return inst
end

-- 1240 -> "1,240" (the egg-shop handoff shows every count, price and shortfall
-- thousands-separated)
local function comma(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local k
	repeat
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

---------------------------------------------------------------- egg viewport
-- Eggs live under ReplicatedStorage.EggModels (one folder per world), a DIFFERENT
-- tree from the BrainrotModels folder BrainrotThumb.add() is hardwired to -- so eggs can't
-- go through .add() directly by name. Instead this reuses BrainrotThumb's own
-- public camera-framing maths (M.framing / M.DEFAULT_DIR) against a hand-cloned
-- egg model, so every 3D viewport in the game still shares one framing formula.
-- Eggs are static props (no spin), matching the brief's "no spin needed" note.
-- The EggModels ROOT, not one world's folder. Egg model names are globally
-- unique (ForestEgg1..5 / TundraEgg1..5), so a recursive lookup resolves any
-- world's egg without the shop having to know which folder it came from --
-- which is what lets ONE shell hold cards for several worlds at once.
local eggFolder = ReplicatedStorage:WaitForChild("EggModels")
local eggMasterCache = {}
local function eggMaster(modelName)
	if eggMasterCache[modelName] == nil then
		local real = eggFolder:FindFirstChild(modelName, true)
		eggMasterCache[modelName] = real and real:Clone() or false
	end
	return eggMasterCache[modelName] or nil
end
-- Row eggs turn slowly in their slots (user, 2026-07-31 -- the static "no spin"
-- brief is superseded). One shared RenderStepped drives every registered
-- viewport by orbiting its CAMERA, the same trick the hatch reveal uses so an
-- off-centre pivot can't make the model swing; phase-offset per slot so five
-- eggs don't rotate in lockstep. The loop is gated on the panel being visible,
-- so a closed shop costs nothing per frame.
local SLOT_SPIN_TIME = 6   -- seconds per revolution
local SLOT_BOB = 0.04      -- camera-height sine, as a fraction of framing dist
local eggSpinners = {}
local function addEggViewport(parent, modelName, opts)
	local master = eggMaster(modelName)
	if not master then return nil end
	opts = opts or {}
	local vp = new("ViewportFrame", {
		Size = opts.size or UDim2.fromScale(1, 1),
		Position = opts.position or UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		ZIndex = opts.zIndex or 1,
	}, parent)
	local m = master:Clone()
	m.Parent = vp
	local fov = opts.fov or 32
	local centre, dist = BrainrotThumb.framing(m, fov)
	local cam = new("Camera", { FieldOfView = fov })
	cam.CFrame = CFrame.lookAt(centre + BrainrotThumb.DEFAULT_DIR * dist, centre)
	cam.Parent = vp
	vp.CurrentCamera = cam
	if opts.spin then
		eggSpinners[#eggSpinners + 1] = {
			cam = cam, centre = centre, dist = dist,
			phase = #eggSpinners * 0.9,
		}
	end
	return vp
end

-- Pet render for the odds tiles and the multi-open result cards. petMaster
-- (defined above; the hatch reveal shares it) resolves PetModels first, then
-- the brainrot stand-ins; returns nil when neither folder has the model --
-- which is most pets today, since the .glb imports are still a pending user
-- step -- and callers fall back to text.
local function addPetViewport(parent, creatureName, petId, zIndex)
	local master = petMaster(creatureName, petId)
	if not master then return nil end
	local vp = new("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = zIndex or 1,
	}, parent)
	local m = master:Clone()
	m.Parent = vp
	local fov = 30
	local centre, dist = BrainrotThumb.framing(m, fov)
	local cam = new("Camera", { FieldOfView = fov })
	cam.CFrame = CFrame.lookAt(centre + BrainrotThumb.DEFAULT_DIR * dist, centre)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- UI.button hardcodes its caption label to ZIndex 3 (Builders ~line 174). Every
-- kit panel lives in a ScreenGui set to ZIndexBehavior.Sibling, where a child
-- always draws above its parent and that 3 never matters. THIS ScreenGui is
-- Global (it predates the kit), so a caption at 3 renders UNDERNEATH its own
-- button and the button comes out blank -- which is exactly what happened.
-- Lifting the caption is the surgical fix; flipping the whole ScreenGui to
-- Sibling would also re-layer the hatch reveal, which is not ours to disturb.
--
-- The z argument is not optional sugar: the caption's ZIndex has to be derived
-- from the button's FINAL one, and callers set that after UI.button returns. A
-- first cut read b.ZIndex inside here and got the default 1, so captions ended
-- up at 2 and stayed buried. Same eager-capture trap Builders documents for the
-- hover rest-position, one field over.
--
-- Declared HERE, above the panel, because the header's close button is its
-- first caller -- it used to live down in the egg-row section and was nil by
-- the time the header ran, which killed the script mid-build.
local function kitButton(parent, text, variant, size, z)
	local b = UI.button(parent, text, variant, size)
	b.ZIndex = z
	local cap = b:FindFirstChildWhichIsA("TextLabel")
	if cap then cap.ZIndex = z + 1 end
	return b, cap
end

---------------------------------------------------------------- ScreenGui + panel
-- EGG SHOP UI REBUILD -- TASK 1: the panel SHELL. ScreenGui, window, ONE red
-- header (title left, wallet + BUY EMERALDS + close right), the spec strip, and
-- an empty CardArea that Task 3 fills with the five egg cards.
--
-- The egg-row builder and the hatch-odds strip further down still belong to the
-- OLD layout. They are deliberately left RUNNING and now render inside CardArea:
-- they parent into `body`, which is this section's `cardArea` under its old name,
-- so removing it would nil-index the script dead at the first egg row. Tasks 2
-- and 3 replace them properly. A half-deleted egg list is worse than an ugly one.
--
-- TWEEN MEASUREMENT (task brief, Step 1). Measured in Play against the Client
-- datamodel on 2026-08-06, run twice with identical results:
--     BackgroundTransparency  ->  1.00   (want 1.00)   PASS
--     UIScale.Scale           ->  2.00   (want 2.00)   PASS
--     UIStroke.Transparency   ->  1.00                 PASS
--     TextTransparency        ->  1.00                 PASS
-- TweenService drives every property type this UI fades, so the later tasks'
-- opacity work can use TweenService directly and does NOT need a
-- RunService.RenderStepped setter. This CONTRADICTS an earlier session note
-- claiming tweens silently no-op on UIScale / BackgroundTransparency in this
-- place -- the measurement above is the record, taken on this datamodel.
--
-- REGISTER BUDGET, and it is not a style preference. This script's top-level
-- chunk sits close to Luau's hard ceiling of 200 local registers per function.
-- The first cut of this section declared everything it built at top level and
-- went straight through it -- "Out of local registers when trying to allocate
-- EGG_STALLS: exceeded limit 200" -- which is a COMPILE error, so the whole
-- script failed to load and the shop could not open at all. Everything the shell
-- builds therefore lives inside one `do ... end`, and only the names later code
-- genuinely needs are declared out here: 13 top-level locals against the 30 this
-- section replaces. Tasks 2-7 should wrap their own construction the same way.

-- The names that must outlive the build block, and who needs them:
--   showToast                      forward ref; the toast card below ASSIGNS it
--   gui / frame / scrim / openPop  setOpen (~line 2281) and both hatch reveals
--   SCRIM_ALPHA                    setOpen's scrim tween target
--   closeBtn                       wired to setOpen at the foot of this script
--   emeraldLabel                    applyEmerald writes it (balanceLabel is the
--                                  same instance under the rebuild plan's name)
--   discoveryLabel                 the spec strip's middle slot
--   cardArea / body                Task 3 fills it; the old egg list parents in
--   relayout                       Platform.Watch target
local showToast
local gui, frame, scrim, openPop
local SCRIM_ALPHA = T.scrimAlpha
local closeBtn, balanceLabel, emeraldLabel, discoveryLabel
local cardArea
local relayout

do
	local Platform = require(ReplicatedStorage.Modules:WaitForChild("Platform"))
	local HudLayout = require(ReplicatedStorage.Modules:WaitForChild("HudLayout"))

	local PANEL_W   = T.size.panelWidth.eggs   -- 940, reserved for this panel
	-- PANEL HEIGHT, raised 660 -> 700 by the card rebuild (Task 2). The finished
	-- shop is a 3 + 2 grid of 295x256 cards with an 11px gutter, so CardArea has
	-- to be at least 256 * 2 + 11 = 523 tall. CardArea = PANEL_H - 32 (this
	-- panel's own UIPadding) - 142 (header 92 + gap 12 + strip 26 + gap 12), so
	-- the old 660 gave 486 and the second row simply fell off the bottom.
	--
	-- The task brief asked for 690, which yields 516 -- still SEVEN PIXELS SHORT.
	-- That figure came from an AbsoluteSize reading taken while this panel's
	-- responsive UIScale sat at ~1.021 (Task 1 recorded CardArea as 927 x 496,
	-- which is the unscaled 908 x 486 times 1.021), so a SCALED measurement was
	-- being compared against an UNSCALED requirement. 700 is the constant that
	-- actually delivers the brief's own stated target of CardArea = 526.
	local PANEL_H   = 700
	local HEADER_H  = T.size.headerHeight      -- 92
	local STRIP_H   = 26
	local BLOCK_GAP = T.pad.gap                -- 12, vertical rhythm inside the window

	gui = new("ScreenGui", {
		Name = "EggShopUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = T.zindex.panel,
		-- KIT LAYERING, and it is load-bearing: the ScreenGui this replaces ran on
		-- the Global default, which is why UI.button's caption (hardcoded ZIndex 3)
		-- rendered UNDERNEATH its own button and came out blank -- see the kitButton
		-- note above. Every kit panel runs Sibling, where a child always draws above
		-- its parent, so the kit builders used below behave as designed.
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Enabled stays TRUE. setOpen opens and closes this shop through
		-- frame.Visible and never through gui.Enabled, so shipping the gui disabled
		-- would simply make the shop unopenable.
		Enabled = true,
	}, playerGui)
	-- notch / rounded-corner / safe-area handling. This also sets ScreenInsets,
	-- which supersedes IgnoreGuiInset above; CoreUISafeInsets is the live value.
	-- round 2.5: through HudLayout's registry, on its "Panel" layer (40+), instead
	-- of T.zindex.panel (25). HIDE UI lives on "Toggle" (30), so at 25 this shop
	-- opened UNDER the pill on a phone and the pill sat on the close button
	-- (round 2 QA). HudLayout.PrepareGui does the Platform.PrepareGui call itself;
	-- T.zindex.panel above stays as the fallback for a client running with the
	-- registry flag off.
	HudLayout.PrepareGui(gui, "Panel")

	-- Input-transparent full-screen frame, KEPT for wiring parity but it no longer
	-- paints (dim-to-blur, 2026-08-17): panel separation is the EggShopBlur
	-- BlurEffect, toggled by the Visible mirror below. setOpen only toggles Visible.
	scrim = new("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.scrim,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
	}, gui)

	-- THE REGISTERED FRAME -- a transparent box the exact size of the panel, and
	-- the thing whose .Visible means "the shop is open". setOpen, both hatch
	-- reveals and the stall prompt all read and write it, so it keeps that
	-- contract exactly.
	--
	-- The panel is built INSIDE it rather than being it, for one specific reason:
	-- UI.panel drops its hard shadow as a SIBLING (UIKit.Builders' UI.hardShadow:
	-- `sh.Parent = frame.Parent`). Parenting the panel straight into the ScreenGui
	-- would strand that shadow beside the panel where it does not inherit
	-- frame.Visible -- an opaque 940x660 slab parked over the game while the shop
	-- is CLOSED, which is exactly what it used to do. One level of nesting puts
	-- the shadow inside `frame` and the trap disappears.
	frame = new("Frame", {
		Name = "EggShopFrame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
	}, gui)
	SideRail.registerPanel(frame)

	-- The scrim MIRRORS the panel. Both reveals set frame.Visible = false for the
	-- length of a hatch and restore it in skip(); without this the scrim would
	-- stay lit, and now that this gui sits at T.zindex.panel (25) rather than the
	-- old 9 it would render OVER EggRevealUI and veil the x3/x10 multi-open.
	-- (Task 5 has since raised EggRevealUI's own DisplayOrder to 40, which fixes
	-- that layering at its source; this mirror stays regardless, because a lit
	-- scrim over a hidden panel is wrong whoever is drawing on top.) Done from
	-- here rather than by editing setOpen so the change stayed inside Task 1;
	-- setOpen's own scrim writes agree with it every time.
	-- DIM-TO-BLUR (2026-08-17 polish grammar): the scrim keeps its mirror wiring
	-- but never paints again -- panel separation is an instant backdrop blur, the
	-- HUDPanelBlur recipe under this shop's own effect name. Property writes only:
	-- NEVER tween a BlurEffect (TweenService silently no-ops on non-GuiObjects in
	-- this place).
	local function setEggShopBlur(on)
		local L = game:GetService("Lighting")
		local fx = L:FindFirstChild("EggShopBlur")
		if on then
			if not fx then
				fx = Instance.new("BlurEffect")
				fx.Name = "EggShopBlur"
				fx.Size = 10
				fx.Parent = L
			end
		elseif fx then
			fx:Destroy()
		end
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		scrim.Visible = frame.Visible
		setEggShopBlur(frame.Visible)
	end)

	-- RESPONSIVE FIT. Platform.FitPanel, NOT Platform.Fit: fitting the 1350x775
	-- design canvas spends ~30% of a handset's width on empty gutters, and fitting
	-- the panel's own box recovers it (0.307 -> 0.571 on an 896x414 phone).
	local hudScale = new("UIScale", { Name = "HudFixScale" }, frame)

	-- Open/close motion (open .92 -> 1 Back/Out 180ms, close -> .95 fade 120ms),
	-- driven by setOpen. It lives on its OWN holder rather than as a second
	-- UIScale on `frame`: two UIScales on the SAME GuiObject do not compose -- one
	-- simply wins -- so stacking them there would have thrown away the responsive
	-- fit the moment setOpen touched the pop. Parent and child scales DO compose.
	local popHolder = new("Frame", {
		Name = "PopHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = frame.ZIndex,
	}, frame)
	openPop = new("UIScale", { Name = "OpenPop" }, popHolder)

	-- THE WINDOW. Pet-Sim style: light gray gradient, 4px dark outline, 8px
	-- radius, 16px padding -- every child below is laid out inside that padded
	-- content box, which is why they sit at x = 0 rather than at a hand margin.
	local panel = UI.panel(popHolder, UDim2.fromOffset(PANEL_W, PANEL_H))
	panel.Name = "Panel"
	panel.ZIndex = T.zindex.panel

	------------------------------------------------------------------ header
	-- ONE red header bar, not two stacked slabs: title left, wallet chip +
	-- BUY EMERALDS + close right.
	local header = UI.surface(panel, UDim2.new(1, 0, 0, HEADER_H), "panel", T.radius.panel, T.stroke.panel)
	header.Name = "Header"
	-- LemonPop 2026-08-13: the BZ egg-header gradient below is the red family
	-- now -- a dark ground, so the title/wallet text keeps stroked white
	header.ZIndex = panel.ZIndex + 1
	-- UI.surface already parented a UIGradient (the window sweep). RETINTED rather
	-- than adding a second one: two UIGradients on one GuiObject do not blend,
	-- only one wins, and which one is not something to rely on. Same pattern the
	-- balance pill this replaces used.
	-- COLOUR: this used to be T.color.headerTop/Bottom, the same generic blue every
	-- panel wears, so the egg shop was indistinguishable from the rock and sell shops.
	-- BZ.eggHeader1/2 is the pink pair the Bazaar palette already defines FOR this
	-- shop and nothing was using -- sibling to rockHeader1/2 and sellHeader1/2, which
	-- their own panels do use.
	-- round 2: the WHITE shell plate; the egg-shop pink lives on in the title ink
	header.BackgroundColor3 = Color3.new(1, 1, 1)
	local headerGrad = header:FindFirstChildOfClass("UIGradient")
	if headerGrad then
		headerGrad.Color = ColorSequence.new(S.Plate.shop[1], S.Plate.shop[2])
	else
		UI.gradient(header, ColorSequence.new(S.Plate.shop[1], S.Plate.shop[2]))
	end
	do
		local hs = header:FindFirstChildOfClass("UIStroke")
		if hs then hs.Color = S.OutlineSoft; hs.Thickness = 2 end
	end

	-- PLACEHOLDER TEXT ONLY. cards.setWorld rewrites this to "<WORLD> EGGS" as soon
	-- as the cards are built, and again on every world switch, so this literal is
	-- what the player sees only if no world is shop-ready at all.
	local title = PC.shout({
		name = "Title", text = "EGG SHOP", size = 44,
		color = Color3.fromHex("FF4FA3"), strokeColor = Color3.new(1, 1, 1), -- the egg shop's pink, as bubble ink
		align = Enum.TextXAlignment.Left,
		frameSize = UDim2.new(1, -470, 0, 50), position = UDim2.new(0, 22, 0.5, 0), anchor = Vector2.new(0, 0.5),
		zIndex = header.ZIndex + 1, parent = header,
	})
	title.TextTruncate = Enum.TextTruncate.AtEnd

	local CTRL_H, CLUSTER_GAP = 44, 10
	local WALLET_W, BUY_W, CLOSE_W = 190, 168, 44

	local cluster = new("Frame", {
		Name = "HeaderControls",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(WALLET_W + BUY_W + CLOSE_W + CLUSTER_GAP * 2, CTRL_H),
		BackgroundTransparency = 1,
		ZIndex = header.ZIndex + 1,
	}, header)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, CLUSTER_GAP),
	}, cluster)

	-- SLOT WRAPPERS, and they are not optional: UI.button parents its hard shadow
	-- as a SIBLING (UIKit.Builders' UI.hardShadow: `sh.Parent = frame.Parent`), so
	-- three bare buttons dropped into that UIListLayout would give the layout SIX
	-- children -- the shadows become phantom list items and shove the real
	-- controls clean off the end of the row. Wrapping each control in its own
	-- frame keeps its shadow inside the slot and out of the layout. Codebase-wide
	-- pattern; the qty segments in the egg rows below carry the same note.
	local function controlSlot(name, order, width)
		return new("Frame", {
			Name = name,
			Size = UDim2.fromOffset(width, CTRL_H),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			ZIndex = cluster.ZIndex,
		}, cluster)
	end

	-- WALLET CHIP -- Emerald's face and the live balance, on a dark slot so it
	-- reads against the red header.
	local walletSlot = controlSlot("WalletSlot", 1, WALLET_W)
	local walletChip = UI.surface(walletSlot, UDim2.fromOffset(WALLET_W, CTRL_H), "slot", T.radius.chip, T.stroke.control)
	walletChip.Name = "WalletChip"
	walletChip.ZIndex = walletSlot.ZIndex + 1
	-- round 2: a light kit chip on the white header (was a dark slot on the pink bar)
	do
		local wg = walletChip:FindFirstChildOfClass("UIGradient")
		if wg then wg.Color = ColorSequence.new(S.Surface.RowTop, S.Surface.RowBottom) end
		local ws = walletChip:FindFirstChildOfClass("UIStroke")
		if ws then ws.Color = S.OutlineSoft; ws.Thickness = 2 end
	end

	local WALLET_ICON = 28
	local walletIcon = new("Frame", {
		Name = "EmeraldIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(WALLET_ICON, WALLET_ICON),
		BackgroundTransparency = 1,
		ZIndex = walletChip.ZIndex + 1,
	}, walletChip)
	if IconArt and IconArt.has("emerald") then
		IconArt.draw(walletIcon, "emerald", WALLET_ICON, walletChip.ZIndex + 1)
	end

	-- LIVE BALANCE. applyEmerald (~line 2258, out of this task's scope) writes
	-- emeraldLabel.Text on every EmeraldUpdate / EmeraldState payload, so emeraldLabel
	-- stays as an alias of this same instance while later tasks get balanceLabel,
	-- the name the rebuild plan uses. comma() supplies thousands separators.
	balanceLabel = UI.label(walletChip, comma(0), "value", T.color.textAccent)
	balanceLabel.Name = "Balance"
	balanceLabel.AnchorPoint = Vector2.new(0, 0.5)
	balanceLabel.Position = UDim2.new(0, 8 + WALLET_ICON + 8, 0.5, 0)
	balanceLabel.Size = UDim2.fromOffset(WALLET_W - (8 + WALLET_ICON + 8 + 10), 26)
	balanceLabel.AutomaticSize = Enum.AutomaticSize.None
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.TextTruncate = Enum.TextTruncate.AtEnd
	balanceLabel.ZIndex = walletChip.ZIndex + 1
	-- OPT OUT OF UIPolish, and the re-assert below is the point of it.
	-- StarterPlayerScripts.UIPolish force-sets EVERY TextLabel under PlayerGui to
	-- pure white and re-applies on every TextColor3 change, so the accent gold this
	-- label is specified in came out white on the first paint -- measured, not
	-- assumed. NoPolish is UIPolish's own documented escape hatch ("rarity tiers
	-- and similar colour-coded text are the intended users"), and a currency value
	-- is exactly that. The attribute has to be set AFTER UI.label returns, because
	-- UI.label parents the label last and UIPolish whitens it on DescendantAdded --
	-- hence setting the colour again here, which now survives.
	balanceLabel:SetAttribute("NoPolish", true)
	balanceLabel.TextColor3 = Color3.fromHex("1F8B34") -- round 2: gem green ink on the light chip (was the gold accent on a dark slot)
	balanceLabel.Font = S.Font.Shout
	do
		local bs = balanceLabel:FindFirstChildOfClass("UIStroke")
		if bs then bs.Color = Color3.new(1, 1, 1) end
	end
	emeraldLabel = balanceLabel

	-- BUY EMERALDS -- opens the HUD shop, which is where emeralds are actually sold.
	local buySlot = controlSlot("BuyEmeraldsSlot", 2, BUY_W)
	-- GOLD, deliberately: this is the one control in the shop that opens a REAL-MONEY
-- surface, and gold is now reserved for exactly that (2026-08-19 gold purge).
	-- round 2: the kit's gold button (real money) at the header control height
	local buyEmeralds = PC.button({
		kind = "gold", text = "BUY GEMS", name = "BuyEmeralds",
		size = UDim2.fromOffset(BUY_W, CTRL_H), textSize = 20, radius = 14, outline = 3,
		zIndex = buySlot.ZIndex + 1, parent = buySlot,
	})
	-- LIVE as of 2026-08-10. This was inert while no dev product existed (user
	-- decision 2026-08-06) and answered with a "coming soon" toast; the four packs
	-- are real developer products now, so that toast would be a lie.
	--
	-- IT HANDS OFF THROUGH A PLAYER ATTRIBUTE. The shop panel belongs to
	-- GameHUDClient and openPanel is a local in THAT script, so this cannot call it
	-- directly -- the same cross-LocalScript problem the join sequence's
	-- IntroDailyDone handoff solves the same way, and for the same reason (an
	-- attribute is still there for a listener that connected late).
	--
	-- A TIMESTAMP, NOT `true`: the value has to CHANGE or GetAttributeChangedSignal
	-- never fires a second time and this button would work exactly once per life.
	--
	-- Nothing closes this shop here, deliberately. Opening the HUD panel makes its
	-- `host` visible, and SideRail's single-open registry closes the legacy egg shop
	-- off that same transition -- see openPanel's "SideRail's legacy-closing
	-- behaviour" note. Closing it here as well would be a second, racing closer.
	buyEmeralds.Activated:Connect(function()
		player:SetAttribute("OpenShopRequest", os.clock())
	end)

	-- CLOSE. "X" the LETTER, never U+2715: this file already lost a close button
	-- once to a font with no glyph for the multiply-cross, and a blank close
	-- control on a modal is the worst possible place for that to happen again.
	local closeSlot = controlSlot("CloseSlot", 3, CLOSE_W)
	-- round 2: the kit's close -- pink-red rounded square, white edge, shout X
	closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundColor3 = S.Role.Destructive[1]
	closeBtn.BorderSizePixel = 0
	closeBtn.Size = UDim2.fromOffset(CLOSE_W, CTRL_H)
	closeBtn.ZIndex = closeSlot.ZIndex + 1
	closeBtn.Parent = closeSlot
	UI.corner(closeBtn, 14)
	do
		local cs = Instance.new("UIStroke")
		cs.Thickness = 3
		cs.Color = Color3.new(1, 1, 1)
		cs.Parent = closeBtn
		UI.gradient(closeBtn, ColorSequence.new(S.Role.Destructive[1], S.Role.Destructive[2]))
	end
	PC.shout({ text = "X", size = 26, zIndex = closeBtn.ZIndex + 1, parent = closeBtn })
	closeBtn:SetAttribute("SfxMuted", true)
	PC.bindPressFeedback(closeBtn)
	-- The click itself is wired at the foot of this script (next to setOpen) and
	-- is untouched, so closing behaves exactly as it does today.

	------------------------------------------------------------------ spec strip
	-- Three read-only facts under the header. The MIDDLE slot is discovery
	-- progress, never a restock countdown -- this shop does not restock.
	--
	-- Laid out as three fixed thirds rather than through a UIListLayout on
	-- purpose: a UIListLayout owns its children's Position, which is the one thing
	-- a later task's motion work has to be able to touch.
	--
	-- Ink, not the muted white: T.color.textMuted (#D8D8D8) is documented as
	-- reading on both the gray window and the dark slots, but this strip sits on
	-- the LIGHT end of the window gradient (#D6D6D6) and would be invisible there.
	-- Window ink held back with TextTransparency is what reads as "muted" here.
	local specStrip = new("Frame", {
		Name = "SpecStrip",
		Position = UDim2.fromOffset(0, HEADER_H + BLOCK_GAP),
		Size = UDim2.new(1, 0, 0, STRIP_H),
		BackgroundTransparency = 1,
		ZIndex = panel.ZIndex + 1,
	}, panel)
	-- One NoPolish on the STRIP covers all three labels: UIPolish honours the
	-- attribute on any ancestor, and it is set before the slots exist, so their ink
	-- is never whitened even on the first paint. Without it this whole row renders
	-- white-on-light-gray, i.e. invisible.
	specStrip:SetAttribute("NoPolish", true)

	local function specSlot(order, text, align)
		local slot = new("Frame", {
			Name = "Slot" .. order,
			Position = UDim2.new((order - 1) / 3, 0, 0, 0),
			Size = UDim2.new(1 / 3, 0, 1, 0),
			BackgroundTransparency = 1,
			ZIndex = specStrip.ZIndex,
		}, specStrip)
		local l = UI.label(slot, text, "meta", T.color.textOnWindow)
		l.Name = "Text"
		l.Size = UDim2.fromScale(1, 1)
		l.AutomaticSize = Enum.AutomaticSize.None
		l.TextXAlignment = align
		l.TextYAlignment = Enum.TextYAlignment.Center
		l.TextTransparency = 0.25
		l.ZIndex = slot.ZIndex + 1
		return l
	end

	-- Derived from EggConfig, never authored: five eggs today, and the strip
	-- should follow the config rather than have to be remembered when a sixth
	-- arrives.
	specSlot(1, string.format("%02d EGGS IN ROTATION", #world.Eggs), Enum.TextXAlignment.Left)
	discoveryLabel = specSlot(2, "0 / 0 PETS DISCOVERED", Enum.TextXAlignment.Center)
	local oddsHintLabel = specSlot(3, "HOVER A CARD FOR FULL HATCH ODDS", Enum.TextXAlignment.Right)

	-- DISCOVERY PROGRESS. Counted against EggConfig.ObtainablePetIds() so the
	-- denominator can never drift from the roster, and fed from the same snapshot
	-- the odds covers use (GetInitialData / DataUpdated, keyed by pet NAME).
	--
	-- Subscribed independently here rather than through applyDiscovered (~line
	-- 935): that function belongs to the egg-row section Tasks 2 and 3 replace
	-- wholesale, and this label has to survive that rewrite. The cost is one extra
	-- GetInitialData call at join, which is a read.
	local function refreshDiscovery(snap)
		local obtainable = EggConfig.ObtainablePetIds()
		local total, found, seen = 0, 0, {}
		for _ in pairs(obtainable) do total += 1 end
		if typeof(snap) == "table" then
			for key, v in pairs(snap) do
				if v == true then
					-- snapshots are name-keyed ("Moss Larva"); the `or` also accepts an
					-- id-keyed snapshot rather than silently counting zero if that changes
					local id = PetConfig.IdFor(key) or (obtainable[key] and key)
					if id and obtainable[id] and not seen[id] then
						seen[id] = true
						found += 1
					end
				end
			end
		end
		discoveryLabel.Text = string.format("%d / %d PETS DISCOVERED", found, total)
	end
	refreshDiscovery(nil)

	local function applyDiscoverySnapshot(snap)
		if typeof(snap) == "table" and typeof(snap.Discovered) == "table" then
			refreshDiscovery(snap.Discovered)
		end
	end
	-- WaitForChild, not a bare index: this subscription runs several hundred lines
	-- earlier in the script than the one it was modelled on, and a remote that has
	-- not replicated yet would be a nil index rather than a short wait.
	remotes:WaitForChild("DataUpdated").OnClientEvent:Connect(applyDiscoverySnapshot)
	task.spawn(function()
		local ok, snap = pcall(function()
			return remotes:WaitForChild("GetInitialData"):InvokeServer()
		end)
		if ok then applyDiscoverySnapshot(snap) end
	end)

	------------------------------------------------------------------ card area
	-- EMPTY BY DESIGN -- Task 3 builds the five egg cards in here.
	--
	-- `body` is the SAME instance under its old name. The egg-row builder and the
	-- hatch-odds strip below parent into `body`, so aliasing rather than deleting
	-- is what keeps them alive and rendering inside the new shell instead of
	-- killing the script at the first nil index. Their footprint still adds up
	-- exactly: list (1, -(ODDS_H + 12)) + 12 + odds strip 160 = this frame's height.
	--
	-- ClipsDescendants stays FALSE: card art, rarity rings and hard shadows are
	-- all meant to render outside their own bounds.
	cardArea = new("Frame", {
		Name = "CardArea",
		Position = UDim2.fromOffset(0, HEADER_H + BLOCK_GAP + STRIP_H + BLOCK_GAP),
		Size = UDim2.new(1, 0, 1, -(HEADER_H + BLOCK_GAP + STRIP_H + BLOCK_GAP)),
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		ZIndex = panel.ZIndex + 1,
	}, panel)

	------------------------------------------------------------------ responsive
	-- One relayout, registered through Platform.Watch, which fires NOW and again
	-- on every viewport / rotation / device change. The bespoke gui.AbsoluteSize
	-- listener and the recentre() retry loop this replaces are both gone.
	-- round 2.5: keep the centred desktop window clear of the HUD's currency
	-- cluster. At the canvas fit this 940-wide window's left edge landed 2px onto
	-- the gem "+" button (round 2 QA at 1891x793). The cluster is left-anchored
	-- and the window is centred, so the clearance comes off the SCALE, symmetric --
	-- about a 2% shrink at 1080p, nothing at all where the cluster is narrower.
	-- Same-space compare: every ScreenGui reports AbsolutePosition in one screen
	-- frame whatever its insets.
	local CLUSTER_GAP = 8
	local function clearCurrencyCluster(scale: number): number
		if not Platform.IsDesktop then return scale end
		local hud = playerGui:FindFirstChild("GameHUD")
		local chrome = hud and hud:FindFirstChild("Chrome")
		local cluster = chrome and chrome:FindFirstChild("CurrencyCluster")
		if not (cluster and cluster:IsA("GuiObject") and cluster.Visible) then return scale end
		-- PAINTED leaves only: the gem pill's hit box runs 8px past its own "+"
		-- button, and clearing invisible boxes would shrink the window for nothing.
		local right = -math.huge
		for _, d in ipairs(cluster:GetDescendants()) do
			if d:IsA("GuiObject") and d.Visible and d.AbsoluteSize.X > 0 then
				local painted = d.BackgroundTransparency < 0.95
					or ((d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image ~= "" and d.ImageTransparency < 0.95)
					or ((d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.TextTransparency < 0.95)
				if painted then
					right = math.max(right, d.AbsolutePosition.X + d.AbsoluteSize.X)
				end
			end
		end
		if right == -math.huge then return scale end
		local room = gui.AbsoluteSize.X - 2 * (right - gui.AbsolutePosition.X + CLUSTER_GAP)
		if room <= 0 then return scale end
		return math.min(scale, math.max(0.2, room / PANEL_W))
	end
	relayout = function()
		hudScale.Scale = clearCurrencyCluster(Platform.FitPanel(PANEL_W, PANEL_H))
		frame.Position = UDim2.fromScale(0.5, 0.5)
		-- the hint names the input the player actually has, and a handset or
		-- controller picked up mid-session re-runs this
		oddsHintLabel.Text = (Platform.IsTouch or Platform.IsPhone)
			and "TAP A CARD FOR FULL HATCH ODDS"
			or "HOVER A CARD FOR FULL HATCH ODDS"
	end
	Platform.Watch(function()
		-- CALLED THROUGH THE VARIABLE, not handed over as a value (Task 6).
		-- `relayout` is reassigned further down to wrap the phone branch around
		-- this one, and Platform.Watch(relayout) would have pinned the listener
		-- to the UNWRAPPED function object forever -- so every later device
		-- change would have re-run the desktop layout and nothing else.
		relayout()
	end)
end

---------------------------------------------------------------- egg cards
-- EGG SHOP UI REBUILD -- TASK 2: the CARD. One 295x256 card per egg, built by
-- buildCard(egg, index) and published in `cards` so Task 3 (the 3+2 grid), Task
-- 4 (hover odds) and Task 5 (purchases) can drive it without hunting instances
-- down by name.
--
-- THE REGISTRY IS A CONTRACT -- these five names are what Tasks 3-5 index:
--     cards[egg.Id] = {
--         root       = the Card_<Id> frame itself, 295x256
--         figure     = the dark slot holding the egg viewport
--         oddsHost   = empty full-card overlay; Task 4 parents its odds panel in
--         buyButtons = KEYED BY QUANTITY, not by position: [1] / [3] / [10]
--         stampHost  = empty full-card overlay; Task 5 parents its stamp in
--     }
-- Everything else in the record (egg, index, tier, tint, viewport, priceValue,
-- ribbon, slots) is additive convenience. Adding is safe; renaming is not.
--
-- REGISTER BUDGET, and it is the same hard rule Task 1 wrote down one section
-- up: this chunk carries 115 top-level locals against Luau's ceiling of 200
-- (COUNTED, not estimated -- column-0 `local` declarations in the live Source,
-- re-measured at the final-review pass, which retired Workspace, tierColor and
-- `body` from above the card block; that block now peaks at 193),
-- and going over is a COMPILE error ("Out of local registers") which presents
-- as "the shop does nothing" rather than as an error on the offending line.
-- Everything here is built inside one `do ... end` -- its ~20 locals are freed
-- at the `end` and their registers reused -- and only `cards` and `buildCard`
-- are declared at top level, because later tasks genuinely need both.
--
-- THE TIER RIBBON IS AN OVERLAY, NOT A BAND, and that is what buys the figure
-- its height. The brief stacked six things in a 295x256 card: 13 padding, four
-- 9px gaps, a 24-tall ribbon row, a 126 figure, a name row, a rarest row and a
-- 40-tall buy row. Measured live off this datamodel (GothamBold): "value" 22px,
-- "cardLabel" 17px, "meta" 14px, UI.ribbon a fixed 24 -- so that stack needs 292
-- in a 256 box, and it still overflows by 4 with every gap deleted. Stacked
-- literally, the figure lands at 90.
--
-- Lifting the meta row OFF the stack and onto the figure's own top corners
-- returns its 24 plus a 9px gap, and takes the figure to 123 -- within 3px of
-- the brief's 126, with the card still 256 and PANEL_H still 700. The ribbon
-- sits top-left over the art and the EGG-0N code top-right, which is where a
-- rarity badge belongs anyway: on the art, not beside it.
--
-- Growing the card was the alternative and it does not work. A 126 figure needs
-- a 292-tall card; two rows plus the gutter is 595; PANEL_H would have to be 769
-- against a 775-tall design canvas, i.e. a modal with no margin that clips
-- outright on a 1366x768 laptop. FIG_H stays DERIVED from whatever else is in
-- the stack, so it can never silently disagree with it.

local cards = {}
local buildCard

do
	------------------------------------------------------------------ geometry
	-- The source design's card is 345x300 inside a 1120-wide panel; this panel
	-- is 940, so every number here is the design's times 295/345 = 0.855.
	local CARD_W, CARD_H = 295, 256
	local CARD_PAD = 13
	local GAP = 9
	local META_H = 24     -- UI.ribbon's own fixed height; an OVERLAY now, not a band
	local NAME_H = 24     -- the "value" price is 22px, the tallest thing on that row
	local RAREST_H = 16   -- "meta" is 14px
	local BUY_W, BUY_H, BUY_GAP = 88, 40, 6
	local COL_W = CARD_W - CARD_PAD * 2                        -- 269
	-- DERIVED, never authored: FOUR bands (figure / name / rarest / buy) and
	-- THREE gaps, because the meta row is an overlay on the figure rather than a
	-- band of its own. 230 - 80 - 27 = 123.
	local FIG_H = (CARD_H - CARD_PAD * 2)
		- (NAME_H + RAREST_H + BUY_H) - GAP * 3

	-- The buy row is 3 x 88 + 2 x 6 = 276, SEVEN PIXELS WIDER than the 269
	-- content column. Kept at the brief's numbers and centred instead of
	-- squeezed to 85: the button size is the thing that was specified, the
	-- column is derived, and 276 centred still lands 9.5px inside the card.
	local BUY_ROW_W = BUY_W * 3 + BUY_GAP * 2

	-- INK, not white. The card is a "subPanel" surface -- the light gray
	-- #C4C4C4 -> #9C9C9C sweep -- and the kit's default white label is invisible
	-- on it. Muting is TextTransparency for the same reason: T.color.textMuted
	-- is a LIGHTER white and would disappear entirely. Same call Task 1 made for
	-- the spec strip one section up.
	local INK = T.color.textOnWindow
	local MUTED = 0.35

	-- Rarity colour on a light card. PetConfig.RARITY_COLOUR is authored for the
	-- dark bag tiles and washes out on #C4C4C4, so TEXT tints are the same hue
	-- pulled a third of the way to black; the ribbon keeps the pure colour,
	-- because it is a filled pill carrying its own dark outline.
	local function onLight(c) return c:Lerp(Color3.new(0, 0, 0), 0.32) end
	local function tierOf(creatureName)
		local r = rarityOf(creatureName)
		return r, (r and PetConfig.RARITY_COLOUR[r]) or T.color.rarityCommon
	end

	------------------------------------------------------------------ the card
	buildCard = function(egg, index, host)
		host = host or cardArea

		-- READ FROM EggConfig, NEVER AUTHORED -- no pet name and no percentage
		-- is written down twice in this file. Rows run worst-to-best and each
		-- egg holds a consecutive run of PetConfig's roster, so the LAST row is
		-- simultaneously the rarest and the strongest, which is exactly what the
		-- RAREST line claims. Indexed by #egg.Table rather than a literal 3 so a
		-- fourth row could never silently turn that line into a lie.
		local bestRow = egg.Table[#egg.Table]
		local bestName, bestChance = bestRow[1], bestRow[2]
		local tier, tint = tierOf(bestName)

		local card = UI.surface(host, UDim2.fromOffset(CARD_W, CARD_H), "subPanel",
			T.radius.panel, T.stroke.control)
		card.Name = "Card_" .. egg.Id
		card.ZIndex = (host.ZIndex or 1) + 1
		-- COLOUR: the grid was nine identical slate cards. `tint` (from tierOf above) is
		-- the rarest tier's colour and was only being spent on the ribbon, so the card
		-- body ignored it entirely. Mix it into the card's own gradient instead -- lightly
		-- (30% at the top, 14% at the bottom), because these cards carry white text and a
		-- full-strength tint would drown it. Retints the EXISTING UIGradient that
		-- UI.surface parented rather than adding a second one: two gradients on one
		-- GuiObject do not blend, one simply wins.
		local cardGrad = card:FindFirstChildOfClass("UIGradient")
		if cardGrad and tint then
			local function mix(base, t, a)
				return Color3.new(base.R + (t.R - base.R) * a,
					base.G + (t.G - base.G) * a,
					base.B + (t.B - base.B) * a)
			end
			cardGrad.Color = ColorSequence.new(mix(BZ.cardTop, tint, 0.30), mix(BZ.cardBot, tint, 0.14))
		end
		-- rarity rings, discount pips and hover art are all meant to render
		-- outside the card's own box
		card.ClipsDescendants = false
		-- ONE NoPolish, on the ROOT, set before a single label exists.
		-- StarterPlayerScripts.UIPolish force-whitens every text object under
		-- PlayerGui on DescendantAdded and re-asserts on every TextColor3
		-- change. It honours the attribute on any ANCESTOR, so this one line
		-- covers every label, ribbon and button caption below -- including on
		-- the first paint, which is when a card built without it renders
		-- white-on-light-gray, i.e. blank. Colours are still re-asserted after
		-- each UI.label returns: belt and braces, and it costs nothing.
		card:SetAttribute("NoPolish", true)

		-- CONTENT COLUMN. A plain inset frame rather than a UIPadding on the
		-- card, because a UIPadding would also inset the two overlay hosts at
		-- the bottom of this function -- and a stamp that cannot reach the
		-- card's edge is not a stamp.
		local content = new("Frame", {
			Name = "Content",
			Position = UDim2.fromOffset(CARD_PAD, CARD_PAD),
			Size = UDim2.fromOffset(COL_W, CARD_H - CARD_PAD * 2),
			BackgroundTransparency = 1,
			ZIndex = card.ZIndex + 1,
		}, card)
		-- The vertical rhythm. This layout OWNS its children's Position, so
		-- nothing that a later task tweens may be a direct child of it -- which
		-- is why the buy buttons live inside their own slot frames below.
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, GAP),
		}, content)

		---------------------------------------------------------- 1. figure
		-- NO STRIPED PLATE. That motif came from the source design and the user
		-- rejected it; the dark slot gradient is what separates the egg from the
		-- light card, and it does the job on its own.
		local figure = UI.surface(content, UDim2.fromOffset(COL_W, FIG_H), "slot", T.radius.slot)
		figure.Name = "Figure"
		figure.LayoutOrder = 1
		figure.ClipsDescendants = true
		figure.ZIndex = content.ZIndex + 1

		-- The real model, through the shared framing maths every 3D viewport in
		-- this game uses. spin = true matches the row eggs that shipped on
		-- 2026-07-31 and costs nothing extra: one shared RenderStepped drives
		-- every registered viewport and is gated on the panel being visible.
		local vp = addEggViewport(figure, egg.Model, {
			-- inset 2, not the row layout's 4: BrainrotThumb.framing fits the model's
			-- BOUNDING SPHERE, so the figure box already spends height on the egg's
			-- diagonal and there is none to give away to padding. The figure clips,
			-- so a tight fit cannot spill.
			size = UDim2.new(1, -4, 1, -4),
			position = UDim2.fromOffset(2, 2),
			zIndex = figure.ZIndex + 1,
			spin = true,
		})
		if not vp then
			-- a missing model must degrade to a tinted block, not to an empty
			-- slot that reads as a broken card
			local swatch = new("Frame", {
				Name = "ArtFallback",
				Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4),
				BackgroundColor3 = tint, BorderSizePixel = 0,
				ZIndex = figure.ZIndex + 1,
			}, figure)
			UI.corner(swatch, T.radius.art)
		end

		------------------------------------------------- meta overlay (on the figure)
		-- LEGIBILITY SCRIM, and it is not decoration. The ribbon and the code sit
		-- over a LIT 3D MODEL, not over the flat slot gradient, and the five eggs
		-- are nowhere near uniformly dark. Area-weighted mean luminance of the
		-- actual models, measured rather than eyeballed: Shard 0.635, Drip 0.507,
		-- Crown 0.499, Horned 0.354, Rune 0.324 -- a 2x spread, with peak parts up
		-- at 0.89 (Shard's studs). BrainrotThumb.framing fills the box, so a wide
		-- model's shoulder reaches straight up under the code: Crown's ring passes
		-- directly beneath it. Without a floor, #D8D8D8 on a pale egg is gone and a
		-- rarity tint loses its edge. This band supplies that floor and fades out
		-- well above the egg's midline, so contrast stops depending on which egg is
		-- in the frame. Verified against all five, brightest first.
		--
		-- The fade is a UIGradient's TRANSPARENCY sequence, not a second Frame
		-- stack: one instance, and the black stays black while only its alpha
		-- ramps. Parented to the figure so it clips with it.
		-- PS99 RESTYLE (2026-08-16): the cards are LIGHT now, so the black band
		-- read as a grey smudge -- BackgroundTransparency = 1 neutralizes it while
		-- keeping the instance (and anything that looks it up by name) intact.
		local scrim = new("Frame", {
			Name = "MetaScrim",
			Size = UDim2.new(1, 0, 0, META_H + 20),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1, -- neutralized: light cards need no legibility band
			BorderSizePixel = 0,
			ZIndex = figure.ZIndex + 2,
		}, figure)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.55, 0.72),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, scrim)

		-- INSET 8 FROM THE CORNER, deliberately, rather than flush. The figure
		-- runs ClipsDescendants, so a flush badge would be sliced by the slot's
		-- 8px radius and read as cut off rather than as a corner treatment. At an
		-- 8px inset nothing touches the clip boundary at all, so the question of
		-- whether the clip follows the rounded corner never arises.
		local META_INSET = 8
		local ribbon = UI.ribbon(figure, string.upper(tier or "COMMON"), "EQUIPPED")
		ribbon.Name = "TierRibbon"
		ribbon.AnchorPoint = Vector2.new(0, 0)
		ribbon.Position = UDim2.fromOffset(META_INSET, META_INSET)
		ribbon.ZIndex = figure.ZIndex + 3
		-- RETINT the gradient UI.ribbon already parented rather than adding a
		-- second one: two UIGradients on one GuiObject do not blend, one simply
		-- wins, and which one is not something to rely on. Same note the header
		-- carries one section up.
		local rgrad = ribbon:FindFirstChildOfClass("UIGradient")
		if rgrad then
			rgrad.Color = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.30), tint)
		end
		local rtext = ribbon:FindFirstChild("Text")
		if rtext then rtext.ZIndex = figure.ZIndex + 4 end

		-- MUTED INK (#7C8CA0) at FULL opacity: the card figure is light again
		-- under the PS99 restyle, so the muted ink reads directly on it and the
		-- neutralized scrim above no longer supplies (or needs to supply) a floor.
		local code = UI.label(figure,
			string.format("EGG-%02d \u{00B7} %02d/%02d", index, index, #world.Eggs),
			"meta", T.color.textMuted)
		code.Name = "Code"
		code.AnchorPoint = Vector2.new(1, 0.5)
		code.Position = UDim2.new(1, -META_INSET, 0, META_INSET + META_H / 2)
		code.TextXAlignment = Enum.TextXAlignment.Right
		code.TextTransparency = 0
		code.ZIndex = figure.ZIndex + 3
		code.TextColor3 = T.color.textMuted

		---------------------------------------------------------- 2. name row
		local nameRow = new("Frame", {
			Name = "NameRow", Size = UDim2.fromOffset(COL_W, NAME_H),
			BackgroundTransparency = 1, LayoutOrder = 2, ZIndex = content.ZIndex,
		}, content)

		-- WHITE here, not INK, and it is the one label on the card that breaks that
		-- rule. "cardLabel" is the only style in this stack carrying a 2px UIStroke,
		-- and that stroke is T.color.outline (#202020) -- so ink text (#2A2A2A)
		-- inside it is a dark word wearing a dark outline, which rendered as a muddy
		-- smear on the gray card (checked on a 2.3x capture, not assumed). White
		-- inside the same dark outline is exactly the treatment the gold price
		-- beside it already uses, and it is what every other card label in the game
		-- does. The strokeless styles on this card ("meta") keep ink, because they
		-- have no outline to fight.
		local eggName = UI.label(nameRow, egg.Name, "cardLabel", T.color.white)
		eggName.Name = "EggName"
		eggName.AnchorPoint = Vector2.new(0, 0.5)
		eggName.Position = UDim2.new(0, 0, 0.5, 0)
		-- CAPPED AND TRUNCATED. UI.label ships AutomaticSize.XY with no truncate, and
		-- the price group below is anchored to this row's RIGHT edge with
		-- AutomaticSize.X -- so the two grow toward each other across 269px with
		-- nothing between them. "Heartwood Egg" (111px) + the price group (63px)
		-- clears by 95px today and collides at a ~24-character name. 120 reserves the
		-- widest plausible price group; the name keeps 149, 38 more than it uses.
		eggName.AutomaticSize = Enum.AutomaticSize.None
		eggName.Size = UDim2.new(1, -120, 0, NAME_H)
		eggName.TextTruncate = Enum.TextTruncate.AtEnd
		eggName.ZIndex = nameRow.ZIndex + 1
		eggName.TextColor3 = T.color.white

		-- Emerald's face leads the number, the same order the header wallet uses,
		-- so a player comparing price against balance sees one mark in both
		-- places. AutomaticSize.X off an AnchorPoint of 1 grows the group
		-- LEFTWARD from the row's right edge, so the price stays pinned however
		-- many digits it has.
		local priceHolder = new("Frame", {
			Name = "Price",
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(0, NAME_H), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, ZIndex = nameRow.ZIndex + 1,
		}, nameRow)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 5),
		}, priceHolder)
		local PRICE_ICON = 22
		-- IconArt.draw parents a frame of its own into whatever it is given, so
		-- it needs this holder: handed `priceHolder` directly it would become a
		-- third item in that UIListLayout instead of the icon.
		local iconSlot = new("Frame", {
			Name = "EmeraldIcon", Size = UDim2.fromOffset(PRICE_ICON, PRICE_ICON),
			BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = priceHolder.ZIndex,
		}, priceHolder)
		if IconArt and IconArt.has("emerald") then
			IconArt.draw(iconSlot, "emerald", PRICE_ICON, priceHolder.ZIndex)
		end
		local priceValue = UI.label(priceHolder, comma(egg.Price), "value", T.color.textAccent)
		priceValue.Name = "Value"
		priceValue.LayoutOrder = 2
		priceValue.ZIndex = priceHolder.ZIndex + 1
		priceValue.TextColor3 = T.color.textAccent

		---------------------------------------------------------- 3. rarest row
		local rarestRow = new("Frame", {
			Name = "RarestRow", Size = UDim2.fromOffset(COL_W, RAREST_H),
			BackgroundTransparency = 1, LayoutOrder = 3, ZIndex = content.ZIndex,
		}, content)
		-- tag + name ride one auto-sizing group so the name always starts right
		-- after "RAREST" without anybody hard-coding that string's width
		-- SIZED IN SCALE, NOT AUTO. This group and the chance label at the row's right
		-- edge were both auto-width with nothing between them. On the PHONE card the
		-- row is only screenWidth-188 wide and the chance label reads "ODDS", so
		-- "RAREST Heartwood Guardian" (178px) + "ODDS" (34px) overlapped by 25px on a
		-- 375-wide handset -- this pair collides TODAY, not hypothetically. -46
		-- reserves the widest right label (34) plus a 12px gutter, at both card sizes.
		local rarestLeft = new("Frame", {
			Name = "Left",
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(1, -46, 0, RAREST_H), AutomaticSize = Enum.AutomaticSize.None,
			BackgroundTransparency = 1, ZIndex = rarestRow.ZIndex + 1,
		}, rarestRow)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}, rarestLeft)

		local rarestTag = UI.label(rarestLeft, "RAREST", "meta", INK)
		rarestTag.Name = "Tag"
		rarestTag.LayoutOrder = 1
		rarestTag.TextTransparency = MUTED
		rarestTag.ZIndex = rarestLeft.ZIndex + 1
		rarestTag.TextColor3 = INK

		local rarestName = UI.label(rarestLeft, bestName, "meta", onLight(tint))
		rarestName.Name = "PetName"
		-- takes whatever the RAREST tag leaves (49px of tag + the list's 6px pad) and
		-- truncates, rather than pushing the whole group into the chance label
		rarestName.AutomaticSize = Enum.AutomaticSize.None
		rarestName.Size = UDim2.new(1, -55, 0, RAREST_H)
		rarestName.TextTruncate = Enum.TextTruncate.AtEnd
		rarestName.LayoutOrder = 2
		rarestName.ZIndex = rarestLeft.ZIndex + 1
		rarestName.TextColor3 = onLight(tint)

		local rarestOdds = UI.label(rarestRow, string.format("%g%%", bestChance), "meta", INK)
		rarestOdds.Name = "Chance"
		rarestOdds.AnchorPoint = Vector2.new(1, 0.5)
		rarestOdds.Position = UDim2.new(1, 0, 0.5, 0)
		rarestOdds.TextXAlignment = Enum.TextXAlignment.Right
		rarestOdds.ZIndex = rarestRow.ZIndex + 1
		rarestOdds.TextColor3 = INK

		---------------------------------------------------------- 4. buy row
		local buyRow = new("Frame", {
			Name = "BuyRow", Size = UDim2.fromOffset(BUY_ROW_W, BUY_H),
			BackgroundTransparency = 1, LayoutOrder = 4, ZIndex = content.ZIndex,
		}, content)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, BUY_GAP),
		}, buyRow)

		local buyButtons = {}
		local buySlots = {}
		for i, qty in ipairs({ 1, 3, 10 }) do
			-- SLOT WRAPPER, and it is not optional: UI.button parents its hard
			-- shadow as a SIBLING (UIKit.Builders' UI.hardShadow:
			-- `sh.Parent = frame.Parent`), so three bare buttons in this
			-- UIListLayout would give the layout SIX children -- the shadows
			-- become phantom list items and shove the real buttons clean off the
			-- end of the row. The wrapper also keeps the button's Position free
			-- for UI.button's own hover/press tweens, which a layout would own.
			local slot = new("Frame", {
				Name = "BuySlot" .. qty, Size = UDim2.fromOffset(BUY_W, BUY_H),
				BackgroundTransparency = 1, LayoutOrder = i, ZIndex = buyRow.ZIndex,
			}, buyRow)
			-- BundleCost, NEVER egg.Price * qty: x3 and x10 are discounted and
			-- this is the same call EggHandler debits with, so a card can never
			-- advertise a price the server does not charge.
			local cost = EggConfig.BundleCost(egg, qty)
			-- 2026-08-19 gold purge: x10 buys with EMERALDS, and gold now means real money
			-- only. Emeralds are violet everywhere else, so the premium multi-buy takes
			-- purple. (The one button here that DOES lead to Robux -- BUY GEMS in the
			-- header -- took gold in the same pass.)
			local btn = UI.button(slot, "", (qty == 10) and "purple" or "tab",
				UDim2.fromOffset(BUY_W, BUY_H), "buttonM")
			btn.Name = "Buy" .. qty
			btn.ZIndex = slot.ZIndex + 1
			-- Deliberately UNWIRED. Task 5 owns purchases; a button that looks
			-- live and does nothing is worse than one that has not shipped yet,
			-- so nothing is connected here at all.

			-- QUANTITY over SUBTOTAL, two lines. The first line reuses the
			-- caption UI.button already made rather than adding a second label
			-- on top of it.
			local cap = btn:FindFirstChildWhichIsA("TextLabel")
			if cap then
				cap.Name = "Qty"
				cap.Text = "x" .. qty
				cap.Size = UDim2.new(1, 0, 0, 20)
				cap.Position = UDim2.new(0, 0, 0, 2)
				cap.TextYAlignment = Enum.TextYAlignment.Center
				cap.TextColor3 = T.color.white
				-- round 2: the discounted buttons carry their pip INSIDE, top-right, so
				-- the quantity moves to the left half of the top line to make room
				if (EggConfig.BUNDLE_DISCOUNT[qty] or 1) < 1 then
					cap.Size = UDim2.new(0.56, 0, 0, 20)
					cap.Position = UDim2.new(0, 8, 0, 2)
					cap.TextXAlignment = Enum.TextXAlignment.Left
				end
			end
			local sub = UI.label(btn, comma(cost or (egg.Price * qty)), "chip", T.color.white)
			sub.Name = "Subtotal"
			sub.AutomaticSize = Enum.AutomaticSize.None
			sub.Size = UDim2.new(1, 0, 0, 15)
			sub.Position = UDim2.new(0, 0, 0, 22)
			sub.TextXAlignment = Enum.TextXAlignment.Center
			sub.TextYAlignment = Enum.TextYAlignment.Center
			sub.ZIndex = 4
			sub.TextColor3 = T.color.white

			-- DISCOUNT PIP, derived from EggConfig.BUNDLE_DISCOUNT so the label
			-- can never disagree with the subtotal beside it. Parented to the
			-- BUTTON, not to the slot: the slot must keep exactly two children
			-- (button + its shadow) or the shadow-leak probe cannot tell a leak
			-- from a decoration, and neither the button nor anything above it
			-- clips, so the pip is free to hang outside. 18 tall rather than
			-- UI.ribbon's default 24 because it is centred on the button's top
			-- edge, and 24 would reach 12px up into the rarest row across a 9px
			-- gap; 18 stops exactly at that row's baseline.
			local pct = math.floor((1 - (EggConfig.BUNDLE_DISCOUNT[qty] or 1)) * 100 + 0.5)
			if pct > 0 then
				-- INSIDE the button's top-right corner (round 2). Centred on the top edge it
				-- reached 9px up into the 9px gap and sat on the rarest row's "10%" -- a
				-- collision on every card, on desktop and phone alike.
				local pip = UI.ribbon(btn, "-" .. pct .. "%", "NEW")
				pip.Name = "DiscountPip"
				pip.Size = UDim2.fromOffset(0, 15)
				pip.AnchorPoint = Vector2.new(1, 0)
				pip.Position = UDim2.new(1, -4, 0, 3)
				pip.ZIndex = 5
				local pd = pip:FindFirstChildOfClass("UIPadding")
				if pd then
					pd.PaddingLeft = UDim.new(0, 5)
					pd.PaddingRight = UDim.new(0, 5)
				end
				local pt = pip:FindFirstChild("Text")
				if pt then
					pt.ZIndex = 6
					pt.TextColor3 = T.color.white
					pt.TextSize = 11
				end
			end

			buyButtons[qty] = btn
			buySlots[qty] = slot
		end

		---------------------------------------------------------- overlays
		-- Two empty full-card hosts, so Tasks 4 and 5 never have to reach into
		-- the content stack (whose UIListLayout would immediately claim anything
		-- they parented there as a sixth band). Both sit OUTSIDE the padded
		-- column, so an odds panel or a stamp can cover the card edge to edge.
		local oddsHost = new("Frame", {
			Name = "OddsHost", Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1, ClipsDescendants = false,
			ZIndex = card.ZIndex + 6,
		}, card)
		local stampHost = new("Frame", {
			Name = "StampHost", Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1, ClipsDescendants = false,
			ZIndex = card.ZIndex + 7,
		}, card)

		cards[egg.Id] = {
			root = card,
			figure = figure,
			oddsHost = oddsHost,
			buyButtons = buyButtons,
			stampHost = stampHost,
			-- additive, for whoever wants them
			egg = egg, index = index, tier = tier, tint = tint,
			content = content, buySlots = buySlots,
			viewport = vp, priceValue = priceValue, ribbon = ribbon,
			rarestName = rarestName, rarestOdds = rarestOdds,
		}
		return card
	end

	------------------------------------------------------- card grid (Task 3)
	-- THE 3 + 2 GRID. Row1 takes cards 1-3 on a UIGridLayout (three even
	-- cells); Row2 takes cards 4-5 on a UIListLayout, centred, so the pair
	-- sits under the middle of the row above. 295 x 3 + 11 x 2 = 907 in the
	-- 908-wide CardArea -- 1px of slack, so nothing below adds padding,
	-- margins or a stroke on top of that, and neither layout carries an
	-- alignment or spacing property beyond what is written here.
	--
	-- Both layouts own their CHILDREN's Position, so no card is ever a direct
	-- child of a Row: each sits in its own fixed 295x256 CardHolder one level
	-- down first, the same handoff the egg-row list further down already uses
	-- for its own hover slide, one layout kind over. Task 4's hover lift
	-- tweens the CARD inside that stationary holder. The holder also stops
	-- UI.surface's hard shadow -- parented as a SIBLING of the card it
	-- shadows -- from landing straight in the layout as a phantom cell.
	--
	-- Static only: this task's brief is the 3 + 2 arrangement, nothing else.
	-- The responsive behaviour and entrance stagger the old comment here
	-- promised are NOT built here -- CardArea's own UIScale already covers
	-- responsiveness (Row1/Row2 are sized in Scale against it), and a
	-- stagger is animation, which is Task 4-6 territory, not this one.
	local GRID_GAP = T.pad.gridGap -- 11

	local row1 = new("Frame", {
		Name = "Row1",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, CARD_H),
		BackgroundTransparency = 1,
		ZIndex = cardArea.ZIndex + 1,
	}, cardArea)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD_W, CARD_H),
		CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells = 3,
	}, row1)

	local row2 = new("Frame", {
		Name = "Row2",
		Position = UDim2.fromOffset(0, CARD_H + GRID_GAP),
		Size = UDim2.new(1, 0, 0, CARD_H),
		BackgroundTransparency = 1,
		ZIndex = cardArea.ZIndex + 1,
	}, cardArea)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, GRID_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row2)

	local function holderFor(row, order, egg)
		return new("Frame", {
			Name = "CardHolder_" .. egg.Id,
			Size = UDim2.fromOffset(CARD_W, CARD_H),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			ZIndex = row.ZIndex,
		}, row)
	end

	------------------------------------------------------------ world switching
	-- EVERY shop-ready world's cards are built HERE, at load, into the same rows.
	-- Switching worlds then only toggles which five holders are VISIBLE.
	--
	-- VISIBILITY, NOT PARENTING, and that distinction is load-bearing. The phone
	-- branch of applyLayout OWNS every holder's Parent: it re-parents all of them
	-- into its one-column scroller and restores them from a P() snapshot on the way
	-- back to desktop. A world switch that also wrote Parent would fight it, and
	-- the symptom is nasty -- the restore replays the snapshot taken BEFORE the
	-- switch, so the panel ends up showing one world's TITLE over the other world's
	-- CARDS. Visible is a property no layout claims, so the two never race.
	-- Both layouts here skip an invisible child outright (measured; the phone
	-- branch's own comment already relies on it for UIListLayout), so a hidden card
	-- takes no cell and leaves no gap -- and an invisible button takes no input, so
	-- the off-world buy buttons are unreachable rather than merely unseen.
	--
	-- WHY NOT REBUILD PER WORLD: this chunk already sits at 193 of Luau's 200
	-- local registers and buildCard closes over most of them, so a rebuild path
	-- would have had to be a SECOND copy of the card code. Building once adds no
	-- top-level locals at all. The property that makes it legal is that egg ids are
	-- globally unique across worlds (ForestShard, TundraFrostcap), so one `cards`
	-- registry holds every world with no key collision -- the same reason the note
	-- above the registry gives.
	--
	-- `world` is retargeted around each pass so that everything buildCard reads
	-- off the world -- the "EGG-01 / 01/05" counter especially -- describes the
	-- world that card belongs to, not whichever one happened to load first.
	for _, wid in ipairs(EggConfig.ShopWorldIds()) do
		WORLD_ID, world = wid, EggConfig.GetWorld(wid)
		local nextEgg = 1
		for i = 1, 3 do
			local egg = world.Eggs[nextEgg]
			if egg then buildCard(egg, nextEgg, holderFor(row1, i, egg)) end
			nextEgg += 1
		end
		for i = 1, 2 do
			local egg = world.Eggs[nextEgg]
			if egg then buildCard(egg, nextEgg, holderFor(row2, i, egg)) end
			nextEgg += 1
		end
	end

	-- Published as a KEY ON `cards` rather than as a local, deliberately: the
	-- registry is only ever read as cards[egg.Id] and never iterated, so a named
	-- key is free -- and the alternative, one more top-level local, is the single
	-- thing this chunk cannot afford. Returns false for a world the shell cannot
	-- draw, which is how the prompt handler at the foot of this script decides to
	-- stay shut instead of opening an empty panel.
	cards.setWorld = function(id)
		local wr = id and EggConfig.GetWorld(id)
		if not wr or not wr.Active or wr.ShopReady == false then return false end
		WORLD_ID, world = id, wr
		-- THE PANEL NAMES THE WORLD IT IS SHOWING. Reached by path rather than by
		-- upvalue: the header is built in an earlier do-block and its `title` local is
		-- long out of scope by here, and one more top-level local is the thing this
		-- chunk cannot spend. Deliberately the same wording as the stall's own prompt
		-- for a world with no named keeper, so the sign outside and the sign inside
		-- agree instead of offering two names for one shop.
		local hdr = cardArea.Parent and cardArea.Parent:FindFirstChild("Header")
		local titleLbl = hdr and hdr:FindFirstChild("Title")
		if titleLbl then
			titleLbl.Text = string.upper(wr.DisplayName or id) .. " EGGS"
		end
		-- Holders keep the row and the LayoutOrder they were BUILT with -- only
		-- Visible moves. Orders repeat across worlds (each world numbers its own
		-- cards 1..3 then 1..2), which is harmless precisely because exactly one
		-- world is ever visible, so no layout ever sees a tie.
		for _, wid in ipairs(EggConfig.ShopWorldIds()) do
			local showing = (wid == id)
			for _, egg in ipairs(EggConfig.GetWorld(wid).Eggs) do
				local c = cards[egg.Id]
				local holder = c and c.root and c.root.Parent
				if holder then holder.Visible = showing end
			end
		end
		return true
	end

	-- The build loop left WORLD_ID pointing at whichever world came last; this
	-- restores the default and hides every other world's cards for the first time.
	cards.setWorld(EggConfig.DEFAULT_WORLD)
end

---------------------------------------------------- hover + hatch odds (Task 4)
-- EGG SHOP UI REBUILD -- TASK 4: the HOVER LIFT and the HATCH-ODDS PANEL. The
-- pointer picks a card up 5px, rings it gold and swells its egg, and the odds
-- panel slides up over the figure to publish that egg's real drop table.
--
-- NOT ONE PET NAME AND NOT ONE PERCENTAGE IS WRITTEN DOWN HERE. Every row is
-- read out of `egg.Table` at runtime, and EggHandler.RollFor rolls
-- NextInteger(1, 100) and walks that SAME table accumulating row[2] -- so row[2]
-- IS the percentage, and a row rendered straight off it cannot drift from what
-- the server actually rolls. Roblox requires published odds for a paid random
-- item, so that is a compliance property of this section, not a presentation
-- preference. The rarity colour arrives the same way -- rarityOf() into
-- PetConfig.RARITY_COLOUR -- never a swatch picked to match.
--
-- ONE `hoveredId`, NOT TWO HANDLERS RACING. MouseEnter on card B and MouseLeave
-- on card A are independent signals with no guaranteed order, and all four
-- orderings have to end with exactly ONE card lifted. So neither handler
-- animates anything: both call setActive(id), the only writer of `hoveredId`,
-- which always reverses the outgoing card before it lifts the incoming one. A
-- MouseLeave from A that lands AFTER B's MouseEnter then finds hoveredId == B
-- and does nothing -- that is the ordering that otherwise leaves A stuck lifted
-- while B is lifted too. Pointer presence is a COUNT per card (the card plus its
-- three buy buttons, the only Active objects inside it) and the close is
-- deferred one step, so a leave immediately followed by an enter -- the pointer
-- crossing between two touching cards inside the 180ms -- closes nothing.
--
-- REGISTER BUDGET, and it is why this whole section is a FUNCTION rather than a
-- bare `do` block. Measured on this datamodel before a line of it was written:
-- 115 top-level locals, and the card block above peaks at 193 against Luau's
-- hard ceiling of 200. Seven spare registers is not enough to build anything in.
--
-- THE 174/196 THIS HEADER CARRIED UNTIL THE FINAL-REVIEW PASS WAS STALE, and a
-- stale register number is the dangerous kind of wrong comment in this file --
-- the next person sizing a block starts from it, and overrunning 200 is a
-- COMPILE error that fails the whole script with no line to point at. 115 is a
-- recount of column-0 `local` declarations in the live Source (the same metric
-- the final review used); 193 is the old peak less the three dead declarations
-- retired above it. Re-measure rather than trusting either number.
-- Locals declared inside a function get that function's own register frame, so
-- this section costs the top-level chunk one temporary and nothing permanent.
-- Overrunning it is a COMPILE error that presents as "the shop does nothing".
do
	local function installHoverOdds()
		local Platform = require(ReplicatedStorage.Modules:WaitForChild("Platform"))
		-- TAP OR POINTER IS A RUNTIME QUESTION NOW, NOT A BUILD-TIME ONE (Task
		-- 6). This was `local IS_TOUCH = Platform.IsTouch`, read ONCE at load,
		-- and that had two consequences. The tap path could not be exercised
		-- from a desk at all -- PlatformOverride drives Platform.Class and so
		-- IsPhone, but deliberately does NOT force IsTouch -- which is how the
		-- toggle below shipped having never run. And a handset picked up
		-- mid-session was stuck with whichever affordance the client booted
		-- with, even though Platform.Watch re-runs the layout for exactly that
		-- case. Both paths are built below and each asks this at the moment it
		-- fires. A phone counts as tap even when the hardware reports no touch,
		-- which is what makes the override reach it; a real handset answers true
		-- either way, so nothing changes on real hardware, and Desktop and
		-- Tablet both answer exactly as they did before.
		local function tapMode()
			return Platform.IsTouch or Platform.IsPhone
		end

		-- the brief's numbers, verbatim
		local LIFT_Y, VP_ZOOM, SLIDE_Y = -5, 1.06, 8
		local LIFT_TW = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local ZOOM_TW = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local ODDS_TW = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		-- Only the paddings and the two fixed bands are authored. ROW HEIGHT is
		-- solved for whatever #egg.Table and the figure's own height turn out to
		-- be, so a fourth pet row could never push this panel past the box it is
		-- required to fill exactly.
		local PAD_X, PAD_Y = 12, 8
		local HEAD_H, DIV_H, GAP_Y = 16, 9, 3
		local REST_A, LINE_A, WASH_A = 0.18, 0.78, 0.86

		local recs = {}
		local hoveredId = nil

		local function retween(rec, inst, info, goal)
			local t = TweenService:Create(inst, info, goal)
			rec.tweens[#rec.tweens + 1] = t
			t:Play()
		end

		------------------------------------------------------------ the odds panel
		local function buildOdds(rec)
			local fig = rec.c.figure
			local tbl = rec.c.egg.Table
			local n = math.max(1, #tbl)
			-- READ BACK, not remembered: Task 2 DERIVES the figure's height out of
			-- the card's band stack, so asking the figure how tall it is is the
			-- only way this panel is guaranteed to keep filling it exactly.
			local rowH = math.max(12, math.floor(
				(fig.Size.Y.Offset - PAD_Y * 2 - HEAD_H - DIV_H - GAP_Y * (n + 1)) / n))

			-- INSET 0, parented to the FIGURE. fromScale(1, 1) at (0, 0) is the
			-- only "fills it exactly" that cannot drift if the card's band stack
			-- ever moves, and the figure already runs ClipsDescendants, so the 8px
			-- entrance slide is masked rather than spilling onto the name row.
			-- Task 2's oddsHost is a full-CARD overlay, sized so a stamp can reach
			-- the card's edges; this panel covers the FIGURE, so it belongs in the
			-- figure. oddsHost is left untouched and still free.
			local panel = UI.surface(fig, UDim2.fromScale(1, 1), "row", T.radius.slot)
			panel.Name = "OddsPanel"
			panel.Position = UDim2.fromOffset(0, SLIDE_Y)
			panel.Visible = false
			panel.Active = false
			-- ABOVE the MetaScrim (fig+2), the tier ribbon at (8,8) (fig+3) and the
			-- EGG-0N code (fig+3). The odds COVER those while shown -- nothing is
			-- moved, shrunk or hidden to make room, and all of it comes back
			-- intact on leave. Still BELOW Task 5's stampHost, which is a direct
			-- child of the card at card+7 and so wins on the sibling comparison
			-- one level up regardless of what is set in here.
			panel.ZIndex = fig.ZIndex + 5
			-- UIPolish force-whitens every TextLabel under PlayerGui and re-asserts
			-- on TextColor3 changed. The card root already carries NoPolish and the
			-- attribute is honoured on any ANCESTOR, but the panel root carries its
			-- own too, so the rarity colour below survives even if this panel is
			-- ever reparented off the card.
			panel:SetAttribute("NoPolish", true)
			rec.panel = panel

			-- One list of (instance, property, shown-value). The entrance tweens it
			-- to `shown`, the exit tweens all of it to 1, and every entry starts at
			-- 1 so the panel's first painted frame is already invisible.
			rec.fades = {}
			local function fadeable(inst, prop, shown)
				inst[prop] = 1
				rec.fades[#rec.fades + 1] = { inst, prop, shown }
			end
			fadeable(panel, "BackgroundTransparency", 0)
			-- UI.surface's stroke is ApplyStrokeMode.Border on a frame that fills a
			-- ClipsDescendants parent exactly, so it renders nowhere at all. Faded
			-- with the rest anyway rather than left sitting at 0 behind the group.
			local ps = panel:FindFirstChildOfClass("UIStroke")
			if ps then fadeable(ps, "Transparency", 0) end

			new("UIPadding", {
				PaddingTop = UDim.new(0, PAD_Y), PaddingBottom = UDim.new(0, PAD_Y),
				PaddingLeft = UDim.new(0, PAD_X), PaddingRight = UDim.new(0, PAD_X),
			}, panel)
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, GAP_Y),
			}, panel)

			local function cell(row, text, right, colour, shown, bump)
				local l = UI.label(row, text, "meta", colour)
				l.Name = right and "Chance" or "Label"
				l.AnchorPoint = Vector2.new(right and 1 or 0, 0.5)
				l.Position = UDim2.new(right and 1 or 0, 0, 0.5, 0)
				l.TextXAlignment = right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
				l.TextSize = l.TextSize + bump
				l.ZIndex = row.ZIndex + 1
				-- RE-ASSERTED after UI.label returns, per the card above: belt to
				-- NoPolish's brace, and it costs nothing.
				l.TextColor3 = colour
				fadeable(l, "TextTransparency", shown)
				return l
			end

			local head = new("Frame", {
				Name = "HeaderRow", Size = UDim2.new(1, 0, 0, HEAD_H),
				BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = panel.ZIndex + 1,
			}, panel)
			cell(head, "HATCH ODDS", false, T.color.textMutedOnDark, REST_A, 0) -- light muted ink: the odds panel rides the DARK row family
			cell(head, "CHANCE", true, T.color.textMutedOnDark, REST_A, 0)

			local div = new("Frame", {
				Name = "Divider", Size = UDim2.new(1, 0, 0, DIV_H),
				BackgroundTransparency = 1, LayoutOrder = 2, ZIndex = panel.ZIndex + 1,
			}, panel)
			local line = new("Frame", {
				Name = "Line", AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = T.color.white, BorderSizePixel = 0,
				ZIndex = div.ZIndex + 1,
			}, div)
			fadeable(line, "BackgroundTransparency", LINE_A)

			-- ONE ROW PER PET, in egg.Table's own order, worst to best. The LAST
			-- one is the rarest AND the strongest -- guaranteed by construction in
			-- EggConfig -- so it takes that pet's own tier colour, two extra points
			-- of type, full opacity against the others' 0.18, and a wash of its own
			-- rarity behind it. Indexed off #egg.Table, never off a literal 3.
			for i, r in ipairs(tbl) do
				local last = (i == #tbl)
				local rar = rarityOf(r[1])
				local colour = (last and ((rar and PetConfig.RARITY_COLOUR[rar]) or T.color.rarityCommon))
					or T.color.white
				local row = new("Frame", {
					Name = "OddsRow", Size = UDim2.new(1, 0, 0, rowH),
					BackgroundColor3 = colour, BackgroundTransparency = 1,
					BorderSizePixel = 0, LayoutOrder = 2 + i, ZIndex = panel.ZIndex + 1,
				}, panel)
				if last then
					UI.corner(row, T.radius.art)
					fadeable(row, "BackgroundTransparency", WASH_A)
				end
				cell(row, r[1], false, colour, last and 0 or REST_A, last and 2 or 0)
				cell(row, string.format("%g%%", r[2]), true, colour, last and 0 or REST_A, last and 2 or 0)
			end
		end

		------------------------------------------------------ one card at a time
		local function apply(rec, on)
			-- Every tween this card owns is cancelled first, so a reversal that
			-- lands mid-flight starts from where the card actually IS instead of
			-- fighting a tween still driving the same property.
			for _, t in ipairs(rec.tweens) do t:Cancel() end
			table.clear(rec.tweens)
			rec.gen += 1

			if on then rec.panel.Visible = true end
			retween(rec, rec.panel, ODDS_TW, { Position = UDim2.fromOffset(0, on and 0 or SLIDE_Y) })
			for _, f in ipairs(rec.fades) do
				retween(rec, f[1], ODDS_TW, { [f[2]] = on and f[3] or 1 })
			end
			if not on then
				-- Hidden only once it has finished fading, and only if nothing
				-- re-entered in the meantime -- `gen` is what a re-entry bumps.
				local gen = rec.gen
				task.delay(ODDS_TW.Time, function()
					if rec.gen == gen and hoveredId ~= rec.id then rec.panel.Visible = false end
				end)
			end
			if rec.toggle and tapMode() then rec.toggle.Text = on and "HIDE" or "ODDS" end
			if tapMode() then return end

			retween(rec, rec.root, LIFT_TW,
				{ Position = rec.basePos + UDim2.fromOffset(0, on and LIFT_Y or 0) })
			if rec.stroke then
				retween(rec, rec.stroke, LIFT_TW, { Color = on and T.color.activeRing or rec.baseRing })
			end
			if rec.vpScale then
				retween(rec, rec.vpScale, ZOOM_TW, { Scale = on and VP_ZOOM or 1 })
			end
		end

		local function setActive(id)
			if hoveredId == id then return end
			-- WRITTEN FIRST, and that is the whole invariant: the reversal below
			-- and every deferred close re-read this, so whichever order the two
			-- cards' events arrived in they all get the same answer.
			local prev = hoveredId
			hoveredId = id
			if prev and recs[prev] then apply(recs[prev], false) end
			if id and recs[id] then apply(recs[id], true) end
		end

		-- PUBLISHED FOR THE PHONE BRANCH (final review M2). Task 6's applyLayout
		-- lives in its own do-block and cannot see this closure, but a device-class
		-- change HAS to clear the hover or it strands whatever was open, and the
		-- strand is STICKY in both directions. Phone -> Desktop leaves an odds panel
		-- Visible over the figure with no pointer on it, and because setActive
		-- early-returns on `hoveredId == id` that card then ignores being hovered --
		-- it heals only after a hover AND a leave of that exact card. Desktop ->
		-- Phone leaves the card lifted -5px with a gold ring, which apply() cannot
		-- reverse at all: it returns early under tapMode(), and Platform.IsPhone is
		-- ALREADY true by the time a relayout reaches us.
		--
		-- SO IT SNAPS RATHER THAN TWEENS. A device-class change is a rebuild, not a
		-- transition; animating through one would only ever be seen half-done, and
		-- the tweens are cancelled first so nothing is left driving a property back
		-- off the resting value this just wrote.
		--
		-- HUNG ON THE EXISTING `cards` TABLE, not on a new top-level local: the
		-- register budget is the hard constraint in this file, and `cards` is only
		-- ever read as cards[egg.Id] -- never iterated -- so one extra named key is
		-- inert.
		cards.clearHover = function()
			setActive(nil)
			for _, r in pairs(recs) do
				r.depth = 0
				for _, t in ipairs(r.tweens) do t:Cancel() end
				table.clear(r.tweens)
				if r.panel then
					r.panel.Visible = false
					r.panel.Position = UDim2.fromOffset(0, SLIDE_Y)
					for _, f in ipairs(r.fades or {}) do f[1][f[2]] = 1 end
				end
				if r.root then r.root.Position = r.basePos end
				if r.stroke then r.stroke.Color = r.baseRing end
				if r.vpScale then r.vpScale.Scale = 1 end
			end
		end

		------------------------------------------------------------------ install
		-- EVERY world's cards, not just the one on screen: this runs ONCE, and a
		-- card with no hover record is a card that never lifts, rings or shows its
		-- odds panel -- which is exactly what a parked world's cards would be.
		for _, egg in ipairs(EggConfig.ShopEggs()) do
			local c = cards[egg.Id]
			if c and c.root and c.figure then
				local rec = {
					id = egg.Id, c = c, root = c.root,
					basePos = c.root.Position,
					stroke = c.root:FindFirstChildOfClass("UIStroke"),
					tweens = {}, depth = 0, gen = 0,
				}
				rec.baseRing = rec.stroke and rec.stroke.Color or T.color.outline
				buildOdds(rec)
				recs[egg.Id] = rec

				if c.viewport then
					-- RE-ANCHORED TO ITS OWN CENTRE FIRST, and it is not cosmetic.
					-- Task 2 laid the viewport in at AnchorPoint (0,0) with a 2px
					-- offset, which is the SAME rectangle as a centred one (2..267
					-- x 2..121 either way) -- but a UIScale grows an object away
					-- from its AnchorPoint, so left alone a 1.06 zoom would shove
					-- the egg down and right instead of swelling it in place.
					c.viewport.AnchorPoint = Vector2.new(0.5, 0.5)
					c.viewport.Position = UDim2.fromScale(0.5, 0.5)
					rec.vpScale = new("UIScale", { Scale = 1 }, c.viewport)
				end

				-- BOTH AFFORDANCES ARE BUILT, and tapMode() picks between them
				-- at the moment each one fires (Task 6). The tap target is the
				-- rarest row; the pointer's is the card itself. Neither can act
				-- while the other device class is live, so there is still
				-- exactly one way to open a card's odds at any moment.
				local lbl = c.rarestOdds
				local rrow = lbl and lbl.Parent
				if rrow then
					rec.toggle = lbl
					if tapMode() then lbl.Text = "ODDS" end
					-- 44 TALL AND GROWN UPWARD. The rarest row is 16 high on the
					-- desktop card and 34 on the phone one, and a 44 target
					-- centred on either would reach down into the buy row and
					-- start eating x1/x3/x10 taps. Bottom-aligned it takes the
					-- gap and the name/price above instead, neither of which is
					-- interactive. Full row width, so 44x44 is the floor rather
					-- than the size. INVISIBLE AND INACTIVE off tapMode: a
					-- transparent button lying over a pointer layout would
					-- swallow the card's own clicks, and it would show up in a
					-- minimum-touch-target sweep as a control nobody can see.
					local hit = new("TextButton", {
						Name = "OddsToggle", Text = "", AutoButtonColor = false,
						BackgroundTransparency = 1,
						Visible = tapMode(), Active = tapMode(),
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, 0),
						Size = UDim2.new(1, 0, 0, 44),
						ZIndex = rrow.ZIndex + 2,
					}, rrow)
					hit.Activated:Connect(function()
						if not tapMode() then return end
						-- SPELLED OUT, not `hoveredId == egg.Id and nil or egg.Id`:
						-- `x and nil or y` is always y in Lua, so that form can
						-- only ever re-open and never close.
						if hoveredId == egg.Id then
							setActive(nil)
						else
							setActive(egg.Id)
						end
					end)
				end

				-- A COUNT, not a boolean. Whether MouseLeave fires on the card
				-- when the pointer crosses onto one of its own buy buttons is
				-- not something to depend on, and this is correct either way:
				-- if it does fire, the button's own MouseEnter has already
				-- balanced it; if it does not, the count simply never dips.
				-- Both go dead under tapMode -- a finger has no hover, and an
				-- emulated handset in Studio is still driven by a real mouse
				-- that would otherwise keep firing these.
				local function pin()
					if tapMode() then return end
					rec.depth += 1
					setActive(egg.Id)
				end
				local function pout()
					if tapMode() then return end
					rec.depth = math.max(0, rec.depth - 1)
					-- DEFERRED one step so an enter that arrives in the same
					-- frame -- either order -- is already settled when this asks.
					task.defer(function()
						if rec.depth == 0 and hoveredId == egg.Id then setActive(nil) end
					end)
				end
				c.root.MouseEnter:Connect(pin)
				c.root.MouseLeave:Connect(pout)
				for _, b in pairs(c.buyButtons) do
					b.MouseEnter:Connect(pin)
					b.MouseLeave:Connect(pout)
				end
			end
		end

		-- Closing the shop has to clear the hover by hand: frame.Visible goes
		-- false with the pointer still inside a card, so no MouseLeave is ever
		-- delivered, and that card would be found still lifted, still ringed gold
		-- and still showing its odds the next time the shop opened.
		if frame then
			frame:GetPropertyChangedSignal("Visible"):Connect(function()
				if not frame.Visible then
					for _, r in pairs(recs) do r.depth = 0 end
					setActive(nil)
				end
			end)
		end
	end
	installHoverOdds()
end

---------------------------------------------------------------- buy state
-- WHAT IS LEFT of the egg-row section Task 7 retired below. The lock and the
-- remote call belong to fireBuy, which Task 5's card buy() calls through, and
-- the balance pair is what applyEmerald writes and every affordability repaint
-- reads.
local buyLocked = false
local qtyByEgg = {}  -- [eggId] = 1|3|10; Task 5's buy() writes it, fireBuy sends it
local refreshAffordability -- assigned by Task 5's card block; applyEmerald calls it
-- Live balance, so a card can show whether it is affordable. applyEmerald feeds
-- this; refreshAffordability re-runs on every balance change.
--
-- emeraldsKnown matters: EmeraldState answers a pull that beats the DataStore load
-- with a PLACEHOLDER {Darrels = 0} (the same lying-zero GameHUDClient documents
-- at length), and a 0 we have not confirmed would paint every egg "too poor" on
-- open. Until a payload proves the profile is loaded, cards stay in the neutral
-- affordable look rather than asserting something we cannot back up.
local currentEmeralds = 0
local emeraldsKnown = false

local function fireBuy(egg)
	if buyLocked then return end
	local qty = qtyByEgg[egg.Id] or 1
	-- the recessed "Need N" chassis is not a button; presses on it are ignored
	-- (the server re-checks regardless)
	-- Bundle price, NOT Price x qty: x3 and x10 are discounted (EggConfig.BundleCost,
	-- the same call EggHandler debits with), so gating on the undiscounted total
	-- would refuse a purchase the player can actually afford. The `or` keeps the old
	-- behaviour if a qty ever reaches here that the bundle table does not know.
	local cost = EggConfig.BundleCost(egg, qty) or (egg.Price * qty)
	if emeraldsKnown and currentEmeralds < cost then return end
	buyLocked = true
	-- The world is named off the EGG, not off whichever one the shell is showing.
	-- Ids are globally unique, so this is exact; WORLD_ID is only a fallback.
	remotes.EggBuy:FireServer(EggConfig.WorldIdOfEgg(egg.Id) or WORLD_ID, egg.Id, qty)
	task.delay(0.6, function()
		buyLocked = false
	end)
end

---------------------------------------------------------------- retired (Task 7)
-- THE OLD EGG-ROW LIST AND THE SHARED HATCH-ODDS STRIP WERE DELETED HERE.
-- They had been built-then-hidden since Task 2 only so that the several hundred
-- lines below could keep resolving their names. Every one of those references is
-- now gone -- proven by an identifier scan of this whole script before the cut --
-- so the instances, their builders and their helpers went with them.
--
-- GONE: the EggList ScrollingFrame and its five EggRow_* cards (art, name, price
-- chip, Open button, x1/x3/x10 segments, SelectHit ring), the OddsStrip with its
-- title/note/tiles, buildOddsFor, selectRow, rowCards, selectedEgg, the duplicate
-- discovered/applyDiscovered subscription (Task 1 refreshDiscovery already owns
-- that same GetInitialData + DataUpdated snapshot), priceRows and the priceRows
-- half of refreshAffordability together with popAffordable/wasAffordable, plus
-- ODDS_H, ROW_H, ART, RARITY_RANK, eggTier, KIT_RARITY, kitTint and openButtons.
--
-- KEPT, because they are still live: fireBuy above (Task 5 buy() calls it),
-- buyLocked, qtyByEgg, currentEmeralds, emeraldsKnown, the refreshAffordability
-- forward declaration (Task 5 assigns it, applyEmerald calls it), and kitButton
-- near the top of this file (the header's close button and the shop toast use it).
--
-- REGISTER BUDGET: Task 7 freed 23 top-level locals here. Recounted at the
-- final-review pass on ONE consistent metric -- column-0 `local` declarations in
-- the live Source -- the file stands at 115 against Luau's ceiling of 200, with
-- the card block peaking at 193.

---------------------------------------------------------------- local toast
-- Bazaar dark stall-shop card (bazaarPanel), matching the shop panel restyle --
-- slide/fade-ish hold-then-hide is unchanged. ToastClient itself is never
-- touched, per the brief.
-- PARENTED INTO THE PANEL, NOT THE SCREEN (2026-08-19). At a fixed screen y=132
-- this card was the one unscaled thing in a panel that is multiplied by
-- Platform.FitPanel -- so it sat on the panel's own header at 1920x1080 (header
-- y 74.6..202.8, covering ~106px of the wallet balance) and straight across the
-- "n / n PETS DISCOVERED" strip at 1280x720 (strip y 146.3..170.5). The shop's
-- toast was printing over the shop's own numbers, on every refused purchase.
-- PopHolder is the panel's exact unpadded box and carries both the responsive
-- fit and the open pop, so "bottom of the panel" stays that at every viewport.
local toastCard = new("Frame", {
	Name = "EggToast",
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(0, 380, 0, 46),
	Visible = false, ZIndex = 50,
}, frame:FindFirstChild("PopHolder") or gui)
UITheme.bazaarPanel(toastCard, 12)
local toastLabel = new("TextLabel", {
	Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1,
	-- GothamBoldItalic does NOT exist in Enum.Font (the Gotham family has no italic).
	-- Indexing it threw, and this line sits at TOP LEVEL -- so the whole script died
	-- here, at line ~1006 of 2374. Everything below never ran, including the stall
	-- prompt binding, which is why pressing E at Gino's stall did nothing at all.
	Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = BZ.notice, TextWrapped = true, Text = "", ZIndex = 51,
}, toastCard)

local toastToken = 0
-- ASSIGNS the forward-declared local at the top of the panel section (~line 253)
-- rather than declaring a fresh one: the header's BUY EMERALDS button is above
-- this point and a `local function` here would shadow it, leaving that button
-- calling nil. Same closure, same call sites, one keyword less.
showToast = function(message)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = message or "Something went wrong."
	toastCard.Visible = true
	task.delay(2.6, function()
		if token == toastToken then toastCard.Visible = false end
	end)
end

---------------------------------------------------------------- buy flow (Task 5)
-- EGG SHOP UI REBUILD -- TASK 5: PURCHASES. Three things, and they are the only
-- three this section owns: whether a buy button is AFFORDABLE, the ACQUIRED
-- stamp that lands on the card you just bought from, and the receipt ticket in
-- the panel's bottom-right corner.
--
-- THE CLIENT DECIDES NOTHING ABOUT THE MONEY. A click goes through the EXISTING
-- fireBuy(), which already owns the remote contract
-- (remotes.EggBuy:FireServer(WORLD_ID, egg.Id, qty)) and the 0.6s buy-lock, and
-- then this waits. EggHandler re-derives the price from its own EggConfig,
-- debits, rolls and grants; the balance on screen is whatever EmeraldUpdate says
-- it is (applyEmerald -> refreshAffordability). NOTHING here decrements a local
-- balance and treats it as truth, so the shop can never quietly disagree with
-- the server about what the player owns -- including when the server refuses a
-- purchase this client thought was fine.
--
-- COST IS ALWAYS EggConfig.BundleCost(egg, qty), NEVER egg.Price * qty: x3 is
-- 5% off and x10 is 12% off, and BundleCost is the same call EggHandler debits
-- with. Gating on the undiscounted total would refuse purchases the player can
-- actually afford, and a receipt built from it would quote a price nobody paid.
--
-- ONE GENERATION COUNTER, `gen`, shared by the stamp and the ticket -- the same
-- discipline revealGen/revealSkip use for the hatch reveal below. Every
-- deferred callback captures it and compares before it touches anything, and a
-- new purchase also tears its predecessor down eagerly rather than waiting on a
-- timer. Two buys 100ms apart therefore leave exactly ONE stamp, on the SECOND
-- card, and exactly one ticket with both of its timers restarted.
--
-- REGISTER BUDGET, and it is the same hard rule Tasks 1, 2 and 4 wrote down:
-- 115 top-level locals are live here against Luau's ceiling of 200 (recounted at
-- the final-review pass; the card block above peaks at 193), and going
-- over is a COMPILE error that presents as "the shop does nothing" rather than
-- as an error on the offending line. This section is therefore ONE `do ... end`
-- with ZERO new top-level locals; its ~30 are freed at the `end` and their
-- registers reused. Everything it needs already has a name: cards, world,
-- EggConfig, fireBuy, buyLocked, qtyByEgg, currentEmeralds, emeraldsKnown,
-- refreshAffordability, frame, new, comma, UI, T, IconArt.
do
	local BUY_QTYS = { 1, 3, 10 }

	------------------------------------------------------------- affordability
	-- Task 2 built these buttons through UI.button with a LIVE variant ("gold"
	-- for x10, "tab" for the rest), so its "disabled" branch never ran -- and it
	-- cannot be re-run, because UI.button decides everything at construction
	-- time. What the disabled variant IS, in the kit, is exactly four
	-- differences: Active false, the disabled gradient, textDisabled captions,
	-- and no hard shadow. This reproduces those four and reverses all four.
	-- (There is no fifth: UI.gloss is retired and draws nothing.)
	--
	-- The hard shadow is a SIBLING of the button, not a child (UIKit.Builders'
	-- UI.hardShadow: `sh.Parent = frame.Parent`), which is the whole reason Task
	-- 2 gave every button its own BuySlot wrapper -- so it is hidden through the
	-- slot, and the slot still holds exactly its two children either way.
	local function setBuyEnabled(c, qty, on)
		local btn = c.buyButtons and c.buyButtons[qty]
		if not btn then return end
		btn.Active = on
		local grad = btn:FindFirstChildOfClass("UIGradient")
		if grad then
			if on then
				grad.Color = T.gradient[if qty == 10 then "purple" else "tab"] -- must track the variant above or the next balance push repaints it gold
			else
				grad.Color = T.gradient.disabled
			end
		end
		-- SPELLED OUT rather than `on and T.color.white or T.color.textDisabled`
		-- only because the same shape one line up would have been a live trap:
		-- `x and nil or y` is always y in Lua, and Task 4 shipped that bug once.
		local ink
		if on then ink = T.color.white else ink = T.color.textDisabled end
		for _, n in ipairs({ "Qty", "Subtotal" }) do
			local l = btn:FindFirstChild(n)
			if l then l.TextColor3 = ink end
		end
		local slot = c.buySlots and c.buySlots[qty]
		local sh = slot and slot:FindFirstChild("HardShadow")
		if sh then sh.Visible = on end
	end

	-- PLACEHOLDER ZERO vs REAL ZERO, and the distinction is the whole guard.
	-- EmeraldState answers a pull that beats the DataStore load with
	-- { Darrels = 0 } and no .Daily table; applyEmerald only raises emeraldsKnown
	-- once that table arrives. Greying all fifteen buttons out during that
	-- window would tell the player they are broke on the strength of a number
	-- nobody has confirmed, so until it is confirmed every button stays live --
	-- exactly the call the old row list already makes one section up.
	local function refreshCards()
		-- Across every world's cards rather than the visible one's. Ten button
		-- rows is nothing to walk, and doing it this way means affordability can
		-- never depend on whether a world swap happened before or after a balance
		-- change landed.
		-- PET BAG ROOM (2026-08-24, owner direction: a full pet bag cannot open eggs).
		-- Read from the attribute PlayerDataManager publishes, so this asks EXACTLY
		-- the question EggHandler refuses on -- HasPetSpace(data, qty) -- rather than
		-- a second count that could disagree with it. nil reads as unlimited: an
		-- attribute that has not replicated yet must not lock the shop, and the server
		-- refuses independently if this client is wrong.
		local room = tonumber(player:GetAttribute("PetSpace"))
		for _, egg in ipairs(EggConfig.ShopEggs()) do
			local c = cards[egg.Id]
			if c and c.buyButtons then
				for _, qty in ipairs(BUY_QTYS) do
					local cost = EggConfig.BundleCost(egg, qty) or (egg.Price * qty)
					local affordable = (not emeraldsKnown) or currentEmeralds >= cost
					-- THE WHOLE BUNDLE MUST FIT, matching EggHandler line for line: an
					-- x10 into three free slots is refused there, so it must not be
					-- offered here. Hence `>= qty`, not `> 0` -- with two slots left, x1
					-- stays live and x3/x10 go dead, which is the true state of things.
					local fits = (room == nil) or (room >= qty)
					setBuyEnabled(c, qty, affordable and fits)
				end
			end
		end

		-- SAY WHY THE BUTTONS WENT DEAD. A greyed row with no reason reads as the
		-- shop being broken rather than as the player's bag being full -- the same
		-- reasoning behind EggHandler's refusal copy. Reached by path because the
		-- strip is built in an earlier do-block; its own default is stashed on the
		-- label the first time through so restoring it cannot guess wrong (the text
		-- differs on touch).
		local hint = cardArea and cardArea.Parent
			and cardArea.Parent:FindFirstChild("SpecStrip")
		hint = hint and hint:FindFirstChild("Slot3")
		hint = hint and hint:FindFirstChild("Text")
		if hint then
			if hint:GetAttribute("DefaultText") == nil then
				hint:SetAttribute("DefaultText", hint.Text)
			end
			if room ~= nil and room <= 0 then
				hint.Text = "PET BAG FULL \u{2014} SELL PETS TO HATCH MORE"
			elseif hint.Text:find("PET BAG FULL", 1, true) then
				hint.Text = hint:GetAttribute("DefaultText")
			end
		end
	end

	-- A PLAIN ASSIGNMENT, not the composition wrapper this used to be (final
	-- review M5). The wrapper read the forward declaration at the top of this
	-- section into `prevRefresh` and called through it, which was right while the
	-- hidden egg-row list still had a repaint of its own to do -- but Task 7
	-- deleted that list, and with it the only code that ever ASSIGNED
	-- refreshAffordability. prevRefresh has been permanently nil ever since, so
	-- `if prevRefresh then prevRefresh() end` could never fire and the comment
	-- explaining it was describing a list that no longer exists. The cards are now
	-- the only affordability surface in the file, so the name simply IS refreshCards.
	refreshAffordability = refreshCards

	-- Bag room moves INDEPENDENTLY of the emerald balance -- hatching, selling a
	-- pet, being gifted one, or buying a slot all change it without any purchase
	-- happening. None of those reach applyEmerald, so without this listener the
	-- buttons would stay dead (or stay live) until the next balance change happened
	-- to repaint them.
	player:GetAttributeChangedSignal("PetSpace"):Connect(refreshCards)

	------------------------------------------------------------------- tokens
	local gen = 0
	local stamp, ticket = nil, nil
	-- What we ASKED for, so the receipt can quote what was actually charged
	-- even in EggHandler's partial-hatch path (see onResult).
	local pend = nil

	local function clearStamp()
		if stamp then stamp:Destroy(); stamp = nil end
	end
	local function clearTicket()
		if ticket then ticket:Destroy(); ticket = nil end
	end

	---------------------------------------------------------- ACQUIRED stamp
	local STAMP_IN, STAMP_OUT, STAMP_HOLD = 0.35, 0.15, 1.10
	local STAMP_S0, STAMP_UNDER, STAMP_TILT = 1.5, 0.94, -8
	local STAMP_SCRIM = 0.42

	local function showStamp(myGen, c, qty)
		clearStamp()
		local fig, content = c.figure, c.content
		if not (c.stampHost and fig and content) then return end

		-- COVERS THE FIGURE, PARENTED TO stampHost. The figure runs
		-- ClipsDescendants, so a stamp built inside it would have the corners of
		-- a -8 degree word sliced off; stampHost is Task 2's full-CARD overlay
		-- at card+7, which also puts this above Task 4's odds panel without
		-- either of them having to know about the other. The rectangle is
		-- arithmetic rather than a live read: content.Position is the card's
		-- 13px pad, and the figure is the FIRST item in content's UIListLayout,
		-- so the layout writes its Position as (0, 0) and this lands on the
		-- figure's box exactly.
		local host = new("Frame", {
			Name = "AcquiredStamp",
			Position = UDim2.fromOffset(
				content.Position.X.Offset + fig.Position.X.Offset,
				content.Position.Y.Offset + fig.Position.Y.Offset),
			Size = UDim2.fromOffset(fig.Size.X.Offset, fig.Size.Y.Offset),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = c.stampHost.ZIndex + 1,
		}, c.stampHost)
		-- BEFORE the label exists: UIPolish force-whitens on DescendantAdded and
		-- again on a deferred second pass, and honours NoPolish on any ANCESTOR.
		-- The card root already carries one, but a stamp that is only legible
		-- because of an attribute two levels up is a stamp waiting to break.
		host:SetAttribute("NoPolish", true)
		UI.corner(host, T.radius.slot)
		stamp = host

		local txt = UI.label(host, ("x%d ACQUIRED"):format(qty), "cardLabel", T.color.textAccentOnDark)
		txt.Name = "Stamp"
		txt.AnchorPoint = Vector2.new(0.5, 0.5)
		txt.Position = UDim2.fromScale(0.5, 0.5)
		txt.Rotation = STAMP_TILT
		txt.TextTransparency = 1
		txt.ZIndex = host.ZIndex + 1
		txt.TextColor3 = T.color.textAccentOnDark   -- gold on the black stamp scrim; re-assert after UI.label returns
		local ink = txt:FindFirstChildOfClass("UIStroke")
		if ink then ink.Transparency = 1 end

		-- 1.5 -> 0.94 -> 1 over 350ms, driven as two chained tweens: Roblox's
		-- Back easing has a FIXED overshoot and the brief names an exact
		-- undershoot, so the curve is spelled out instead of approximated. The
		-- UIScale hangs on the LABEL, whose AnchorPoint is its own centre, so it
		-- swells in place rather than away from a corner.
		local sc = new("UIScale", { Scale = STAMP_S0 }, txt)
		local fade = TweenInfo.new(STAMP_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(sc, TweenInfo.new(STAMP_IN * 0.7, Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out), { Scale = STAMP_UNDER }):Play()
		TweenService:Create(host, fade, { BackgroundTransparency = STAMP_SCRIM }):Play()
		TweenService:Create(txt, fade, { TextTransparency = 0 }):Play()
		if ink then TweenService:Create(ink, fade, { Transparency = 0 }):Play() end
		task.delay(STAMP_IN * 0.7, function()
			if myGen ~= gen then return end
			TweenService:Create(sc, TweenInfo.new(STAMP_IN * 0.3, Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)

		-- CLEARED AT 1100ms, not fading FROM it. The brief's number is when the
		-- stamp is gone, so the fade starts STAMP_OUT early and the instance is
		-- destroyed on the beat itself -- which is also what makes "count the
		-- stamps at t+1.1s" a question with an unambiguous answer.
		task.delay(STAMP_HOLD - STAMP_OUT, function()
			if myGen ~= gen then return end
			local out = TweenInfo.new(STAMP_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(host, out, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(txt, out, { TextTransparency = 1 }):Play()
			if ink then TweenService:Create(ink, out, { Transparency = 1 }):Play() end
		end)
		task.delay(STAMP_HOLD, function()
			if myGen ~= gen then return end
			clearStamp()
		end)
	end

	----------------------------------------------------------- receipt ticket
	local TICKET_W, TICKET_INSET, TICKET_PAD = 250, 26, 12
	local TICKET_IN, TICKET_LIFT = 0.22, 14
	-- TICKET_LIFE IS SIZED OFF THE HOLD IT LIVES INSIDE (final review I1). This
	-- receipt is parented into frame.PopHolder (see showTicket's own note), and
	-- the bulk hold at the foot of this script is BULK_HOLD = 1.10 -- so
	-- playMultiReveal sets frame.Visible = false at t+1.10 and takes the ticket's
	-- whole subtree with it. At the old 2.80 the linear drain bar reached only
	-- 1.10/2.80 = 39% before the receipt vanished mid-count: a clock that could
	-- not finish, which is precisely the one thing a linear bar promises it will.
	-- 0.92 + TICKET_OUT 0.18 = 1.10 = BULK_HOLD = STAMP_HOLD, so the bar now hits
	-- zero, the ticket plays its own dismissal, and both it and the stamp clear on
	-- the same beat the ceremony starts.
	--
	-- THE TWO ALTERNATIVES WERE WEIGHED AND REJECTED. Reparenting to `gui` so the
	-- ticket outlives the hide: playReveal disables every OTHER ScreenGui but only
	-- HIDES this frame, so a ticket outside the frame would draw straight over the
	-- hatch -- exactly the trap PopHolder was chosen to avoid -- and it would need
	-- its own hide wired into the reveal, which this plan has protected all the
	-- way through. Lengthening BULK_HOLD to cover 2.80: the user does not want a
	-- pause between pressing buy and the payoff, and 2.80s of dead panel is that
	-- pause. Shortening the clock is the only change that costs nothing.
	--
	-- 2026-09-21 (egg hatch overhaul): BULK_HOLD is gone -- the EggHatch controller hides
	-- this panel the instant a result lands, for every quantity -- so the stamp and the
	-- ticket can no longer be seen and the result handler below no longer draws them.
	-- showStamp / showTicket are kept intact for a future "receipt after the hatch"
	-- pass; the timings above are theirs to reuse.
	local TICKET_LIFE, TICKET_OUT = 0.92, 0.18
	local BAR_H, BAR_INSET_X, BAR_INSET_Y = 2, 8, 6
	local L1_H, L2_H, L3_H, ROW_GAP = 16, 22, 16, 4
	local ICON = 18
	local TICKET_H = TICKET_PAD * 2 + L1_H + L2_H + L3_H + ROW_GAP * 2

	local function showTicket(myGen, egg, qty, cost)
		clearTicket()
		-- PARENTED TO PopHolder, not to the panel. UI.panel hangs a 16px
		-- UIPadding on the window, which would silently eat 16 of the brief's
		-- 26px inset; PopHolder is the panel's exact unpadded 940x700 box, so
		-- "inset 26" means 26. It also inherits both of the panel's scales (the
		-- responsive fit and the open pop), and -- the reason this is not a
		-- child of `gui` -- it inherits frame.Visible, so a ticket can never be
		-- left drawing over a hatch reveal the way the toast card can.
		local holder = frame:FindFirstChild("PopHolder")
		if not holder then return end
		local win = holder:FindFirstChild("Panel")
		local rest = UDim2.new(1, -TICKET_INSET, 1, -TICKET_INSET)

		local root = UI.surface(holder, UDim2.fromOffset(TICKET_W, TICKET_H), "row",
			T.radius.slot, T.stroke.control)
		root.Name = "Receipt"
		root.AnchorPoint = Vector2.new(1, 1)
		root.Position = rest + UDim2.fromOffset(0, TICKET_LIFT)
		-- Above the window's whole subtree. This ScreenGui runs
		-- ZIndexBehavior.Sibling, so the comparison that matters is against
		-- `Panel` one level up, not against anything inside it.
		root.ZIndex = ((win and win.ZIndex) or T.zindex.panel) + 5
		root:SetAttribute("NoPolish", true)
		ticket = root

		-- One list of (instance, property, shown-value), the same shape Task 4's
		-- odds panel uses. Every entry starts at 1 so the ticket's first painted
		-- frame is already invisible, the entrance tweens each to `shown`, and
		-- the dismissal tweens all of it back to 1.
		local fades = {}
		local function fadeable(inst, prop, shown)
			fades[#fades + 1] = { inst, prop, shown }
			inst[prop] = 1
		end
		local function fadeGroup(root2)
			-- IconArt draws its faces out of a dozen plain frames with their own
			-- transparencies, so they are collected generically and each one
			-- remembers ITS OWN resting value rather than being flattened to 0.
			for _, d in ipairs(root2:GetDescendants()) do
				if d:IsA("GuiObject") and d.BackgroundTransparency < 1 then
					fadeable(d, "BackgroundTransparency", d.BackgroundTransparency)
				end
				if d:IsA("ImageLabel") or d:IsA("ImageButton") then
					fadeable(d, "ImageTransparency", d.ImageTransparency)
				end
				if d:IsA("TextLabel") then fadeable(d, "TextTransparency", d.TextTransparency) end
				if d:IsA("UIStroke") then fadeable(d, "Transparency", d.Transparency) end
			end
		end

		fadeable(root, "BackgroundTransparency", 0)
		local rs = root:FindFirstChildOfClass("UIStroke")
		if rs then fadeable(rs, "Transparency", 0) end

		local function line(text, style, colour, y)
			local l = UI.label(root, text, style, colour)
			l.Position = UDim2.fromOffset(TICKET_PAD, y)
			l.ZIndex = root.ZIndex + 1
			l.TextColor3 = colour   -- re-assert after UI.label returns
			fadeable(l, "TextTransparency", 0)
			local st = l:FindFirstChildOfClass("UIStroke")
			if st then fadeable(st, "Transparency", 0) end
			return l
		end

		local y2 = TICKET_PAD + L1_H + ROW_GAP
		local y3 = y2 + L2_H + ROW_GAP
		line("ORDER CONFIRMED", "chip", T.color.claimRing, TICKET_PAD)
		line("SENT TO HATCH QUEUE", "chip", T.color.textMutedOnDark, y3) -- light muted ink on the dark ticket

		-- FIXED WIDTH AND TRUNCATED, unlike every other label here: this is the
		-- one line with something to collide with. UI.label ships
		-- AutomaticSize.XY, and "x10 Horned Egg" (the longest of the five at 17px
		-- GothamBold) plus a four-digit cost would have grown straight through
		-- the price group instead of stopping at it.
		local name = line(("x%d  %s"):format(qty, egg.Name), "cardLabel", T.color.white, y2)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Size = UDim2.fromOffset(TICKET_W - TICKET_PAD * 2 - 88, L2_H)
		name.TextYAlignment = Enum.TextYAlignment.Center
		name.TextTruncate = Enum.TextTruncate.AtEnd

		-- Emerald's face leads the number, the same order the card price and the
		-- header wallet use. AutomaticSize.X off an AnchorPoint of 1 grows the
		-- group LEFTWARD from the ticket's right pad, so the cost stays pinned
		-- however many digits it has.
		local costBox = new("Frame", {
			Name = "Cost", AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -TICKET_PAD, 0, y2 + L2_H / 2),
			Size = UDim2.fromOffset(0, L2_H), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, ZIndex = root.ZIndex + 1,
		}, root)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}, costBox)
		local iconSlot = new("Frame", {
			Name = "EmeraldIcon", Size = UDim2.fromOffset(ICON, ICON),
			BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = costBox.ZIndex,
		}, costBox)
		if IconArt and IconArt.has("emerald") then
			IconArt.draw(iconSlot, "emerald", ICON, costBox.ZIndex)
		end
		fadeGroup(iconSlot)
		local costL = UI.label(costBox, "-" .. comma(cost), "cardLabel", T.color.textAccentOnDark)
		costL.Name = "Value"
		costL.LayoutOrder = 2
		costL.ZIndex = costBox.ZIndex + 1
		costL.TextColor3 = T.color.textAccentOnDark   -- gold on the dark ticket; re-assert after UI.label returns
		fadeable(costL, "TextTransparency", 0)
		local cs = costL:FindFirstChildOfClass("UIStroke")
		if cs then fadeable(cs, "Transparency", 0) end

		-- THE DRAIN BAR EMPTIES LEFT TO RIGHT: anchored to the RIGHT edge and
		-- shrinking, so the moving edge travels left -> right, which is what the
		-- brief describes. Anchored left it would shrink the other way and the
		-- depletion would read right -> left. Inset by the corner radius so a
		-- square 2px end never pokes past the ticket's 8px curve.
		local bar = new("Frame", {
			Name = "Drain",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -BAR_INSET_X, 1, -BAR_INSET_Y),
			Size = UDim2.new(1, -BAR_INSET_X * 2, 0, BAR_H),
			BackgroundColor3 = T.color.textAccentOnDark, -- gold drain bar on the dark ticket
			BorderSizePixel = 0,
			ZIndex = root.ZIndex + 2,
		}, root)
		UI.corner(bar, 1)
		fadeable(bar, "BackgroundTransparency", 0)

		-- entrance: +14 -> 0 on Y with opacity, 220ms ease-out
		local ease = TweenInfo.new(TICKET_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(root, ease, { Position = rest }):Play()
		for _, f in ipairs(fades) do
			TweenService:Create(f[1], ease, { [f[2]] = f[3] }):Play()
		end
		-- LINEAR, and it has to be: this bar is a clock. Any easing would make it
		-- lie about how much of the 920ms is left.
		TweenService:Create(bar, TweenInfo.new(TICKET_LIFE, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(0, 0, 0, BAR_H) }):Play()

		task.delay(TICKET_LIFE, function()
			if myGen ~= gen then return end
			local out = TweenInfo.new(TICKET_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			for _, f in ipairs(fades) do
				TweenService:Create(f[1], out, { [f[2]] = 1 }):Play()
			end
			TweenService:Create(root, out, { Position = rest + UDim2.fromOffset(0, TICKET_LIFT) }):Play()
			task.delay(TICKET_OUT, function()
				if myGen ~= gen then return end
				clearTicket()
			end)
		end)
	end

	------------------------------------------------------------------- buying
	local function buy(egg, qty)
		if buyLocked then return end
		local cost = EggConfig.BundleCost(egg, qty) or (egg.Price * qty)
		-- The same two conditions setBuyEnabled paints, re-asked at click time.
		-- A disabled button is already Active = false and should never get here,
		-- but "the control looks dead" and "the control IS dead" have to be the
		-- same test or one of them will drift.
		if emeraldsKnown and currentEmeralds < cost then return end
		pend = { id = egg.Id, qty = qty, cost = cost }
		-- REUSES fireBuy rather than re-implementing it: that function owns the
		-- remote contract and the 0.6s buy-lock, and one buy path means one
		-- lock. It reads the quantity out of qtyByEgg, which is the (hidden) old
		-- row list's picker state -- writing it here keeps the two agreeing
		-- instead of letting fireBuy send a quantity nobody clicked.
		qtyByEgg[egg.Id] = qty
		fireBuy(egg)
	end

	-- Wired ONCE, for every world's cards. A parked card cannot be clicked (its
	-- ancestor is invisible), so wiring it early costs nothing and means a world
	-- swap never has to re-wire anything.
	for _, egg in ipairs(EggConfig.ShopEggs()) do
		local c = cards[egg.Id]
		if c and c.buyButtons then
			for _, qty in ipairs(BUY_QTYS) do
				local btn = c.buyButtons[qty]
				if btn then
					btn.Activated:Connect(function() buy(egg, qty) end)
				end
			end
		end
	end

	------------------------------------------------------------------- result
	-- A SECOND connection to EggResult, deliberately, rather than a call bolted
	-- into the one at the foot of this script. That handler owns setOpen and the
	-- reveal; this one owns the stamp and the ticket. Neither reads anything the
	-- other writes, so their firing order does not matter -- and the reveal
	-- section stays untouched, which is the whole point of this plan.
	remotes.EggResult.OnClientEvent:Connect(function(result)
		if type(result) ~= "table" or not result.Ok then pend = nil; return end
		-- A REWARD IS NOT A PURCHASE: nothing was spent, so there is no receipt to
		-- print and no shop card for the ACQUIRED stamp to land on. Everything below
		-- prices a bundle against `pend`, which a reward never sets.
		if result.Source == "reward" then pend = nil; return end
		local egg = EggConfig.GetEgg(EggConfig.WorldIdOfEgg(result.EggId) or WORLD_ID, result.EggId)
		if not egg then pend = nil; return end

		-- WHAT WAS GRANTED, not what was asked for. EggHandler rolls a batch and
		-- can stop early on a roster edited live in Studio, refunding the rest
		-- PRORATED out of the bundle -- so the honest quantity is #Results and
		-- the honest cost is the bundle minus that same prorated refund. When
		-- nothing went wrong (every real purchase) both reduce to the price the
		-- card advertised.
		local n = 1
		if typeof(result.Results) == "table" then n = math.max(1, #result.Results) end
		local cost
		if pend and pend.id == result.EggId and pend.qty >= n and pend.qty > 0 then
			cost = pend.cost - math.floor(pend.cost * (pend.qty - n) / pend.qty + 0.5)
		else
			-- NO `egg.Price * n` FALLBACK (final review M4). BundleCost returns nil
			-- for any n outside {1, 3, 10}, and n here is #result.Results -- so the
			-- ONLY way to reach that nil is EggHandler's partial-hatch path, which is
			-- exactly where the server charged a PRORATED slice of the bundle. The
			-- undiscounted Price x n would then quote a number strictly higher than
			-- the player was actually charged (at x10 that is list price against a
			-- 12%-off bundle). With `pend` missing or mispaired there is no honest
			-- number left to print, so nothing is printed: the receipt is skipped
			-- below and the ACQUIRED stamp still lands carrying the count. This was
			-- the last Price x qty in the file that could actually execute.
			cost = EggConfig.BundleCost(egg, n)
		end
		pend = nil

		-- DORMANT SINCE THE EGG HATCH OVERHAUL (2026-09-21). The hatch hides this panel
		-- in the same frame the result lands, for x1, x3 and x10 alike, so a stamp or a
		-- ticket drawn here would never be seen: they are cleared and not built. The
		-- `cost` above is still computed so this block keeps quoting the honest number
		-- if a post-hatch receipt is ever wanted.
		if true then
			gen += 1
			clearStamp()
			clearTicket()
			return
		end
		if n <= 1 then
			-- gen IS STILL BUMPED, and the pair is cleared eagerly: a x1 landing
			-- during a previous bulk buy's hold has to take that stamp and ticket
			-- down rather than leave them running over the ceremony it is about
			-- to start. Bumping alone would only stop their pending callbacks --
			-- the instances themselves are what has to go.
			gen += 1
			clearStamp()
			clearTicket()
			return
		end

		gen += 1
		local myGen = gen
		local c = cards[egg.Id]
		if c then showStamp(myGen, c, n) end
		-- `cost` is nil only on the unquotable partial hatch above; the stamp still
		-- runs, the receipt is the part that would have had to invent a number.
		if cost then showTicket(myGen, egg, n, cost) end
	end)

	-- First paint. emeraldsKnown is false this early, so this asserts nothing
	-- about the balance -- it just puts every button in a known state before
	-- pullEmeraldState's answer arrives and repaints them for real.
	refreshCards()
end

---------------------------------------------------------------- phone layout (Task 6)
-- EGG SHOP UI REBUILD -- TASK 6: THE ONE-COLUMN PHONE LAYOUT.
--
-- AN ADDED BRANCH, NOT A REPLACEMENT, and the mechanism is what guarantees it.
-- Nothing below re-authors a desktop number. Every phone value is PAIRED, in one
-- `plan` list, with the desktop value read off the live instance at install time
-- -- so "go back to desktop" is a write of the value that was actually there,
-- not a second copy of the desktop layout that could drift from the first.
--
-- IT KEYS OFF Platform.IsPhone, NOT Platform.IsTouch. The supported preview hook
-- (ReplicatedStorage:SetAttribute("PlatformOverride", "Phone")) drives
-- Platform.Class and therefore IsPhone, but deliberately does NOT force IsTouch
-- (`IsTouch = UserInputService.TouchEnabled and not IsDesktop`), and Studio's
-- device emulator LATCHES its touch flags for the rest of the session. A layout
-- branched on IsTouch would be unreachable from a desk, which is how the
-- previous task's touch toggle shipped never having run once.
--
-- SCALE 1 RATHER THAN FitPanel, and it is the one place this departs from the
-- brief's letter to keep its actual requirement. "Insets 10px from the screen
-- edge and fills the rest" means the panel IS the screen, so there is no fixed
-- box left for FitPanel to fit -- and FitPanel returns ~0.53 on a real handset,
-- which would render the specified 48px buy buttons at 25 REAL pixels and the
-- 44px floor at 23. Roblox's 44px minimum is a real-pixel rule, so the phone
-- panel is sized in real pixels (the gui's own safe box minus 2 x 10) at scale
-- 1. The desktop line is untouched and still goes through FitPanel.
--
-- REGISTER BUDGET, the same hard rule Tasks 1, 2, 4 and 5 each wrote down: 115
-- top-level locals against Luau's ceiling of 200, peaking at 193 inside the card
-- block. This section is one `do ... end` wrapped around ONE function, so its
-- ~45 locals live in that function's own register frame and the top-level chunk
-- pays for a single temporary that is freed at the `end`. ZERO new top-level
-- locals. Overrunning 200 is a COMPILE error that presents as "the shop does
-- nothing" rather than as an error on the offending line.
do
	local function installPhoneLayout()
		local Platform = require(ReplicatedStorage.Modules:WaitForChild("Platform"))

		------------------------------------------------------------- geometry
		-- The brief's numbers, verbatim, and nothing else authored twice.
		local EDGE      = 10    -- panel inset from every screen edge
		local BODY_PAD  = 12    -- padding inside the scrolling body
		local CARD_GAP  = 12    -- between cards
		local FIG_W     = 104   -- the horizontal card's figure
		local FIG_H     = 118
		local COL_GAP   = 10    -- figure -> right column
		local CARD_PAD  = 13    -- Task 2's CARD_PAD: the card's content inset
		local STACK_GAP = 9     -- Task 2's GAP: content's UIListLayout padding
		local RIB_H     = 24    -- UI.ribbon's own fixed height
		local NAME_H    = 26
		local NAME_SIZE = 22    -- "egg name (22)"
		local PRICE_H   = 24
		local RAREST_H  = 34    -- "a 34-high tappable RAREST ... ODDS row"
		local BUY_H     = 48    -- "buy buttons full-width beneath, 48 high"
		-- round 2.5: 150 -> 172. The balance label is WALLET_W - 54, and a seven-digit
		-- gem balance ("1,000,474") at the chip's 22px needs ~110px: at 96 it truncated
		-- to "1,000,4...". The header has the room -- the title is truncate-guarded.
		local WALLET_W  = 172
		local CLOSE_W   = 44
		local CTRL_GAP  = 10

		-- THE TOUCH-CONTROL BAND (Task 7 fix 2). Roblox draws the thumbstick
		-- bottom-left and the jump button bottom-right, and Platform.Insets()
		-- already reserves that strip -- TOUCH_CONTROL_BAND (140) x 0.8 on a
		-- phone = 112px. Task 6 simply never applied it, so the panel's bottom
		-- 112px sat underneath them.
		--
		-- THIS IS A FLOOR FOR THAT CALL'S ANSWER, not a rival number. Insets()
		-- only adds the band when Platform.IsTouch, and the supported preview
		-- override drives IsPhone WITHOUT IsTouch on purpose (this section's own
		-- header explains why) -- so from a desk the same call answers 0 and the
		-- fix would be invisible in exactly the place anyone would check it.
		-- This branch only ever runs on the phone class, where the controls are
		-- always drawn, so the floor is asserted here and Insets() still wins
		-- whenever it reports MORE than the band.
		local TOUCH_BAND = 112

		-- ODDS PANEL HEIGHT IS THE DESKTOP FIGURE'S HEIGHT, and that is not a
		-- coincidence to be tidied away: Task 4 solves its row height ONCE, at
		-- build time, out of `figure.Size.Y.Offset` -- 123 -- so a panel given
		-- any other height here would either strand rows or overflow them. The
		-- arithmetic it used (pad 16 + head 16 + divider 9 + n rows + n+1 gaps)
		-- lands at 122 for a 3-row egg, 120 for 4 and 119 for 5, so 123 always
		-- contains it exactly once.
		local ODDS_H = 123

		-- DERIVED, never authored: pad + figure + gap + buy row, and the open
		-- height is that plus one more gap and the odds panel. content is sized
		-- in SCALE off the card, so both add up on their own.
		local CARD_H      = CARD_PAD * 2 + FIG_H + STACK_GAP + BUY_H
		local CARD_H_OPEN = CARD_H + STACK_GAP + ODDS_H

		------------------------------------------------------------- the plan
		-- { instance, property, desktopValue, phoneValue }. P() reads the
		-- desktop value straight off the instance, which is what makes the
		-- desktop branch a restore rather than a re-implementation. PP() is for
		-- the handful of properties whose install-time value could itself have
		-- been decided by the platform (the odds toggle's Visible/Active), where
		-- capturing would record a phone value as "desktop" if the client
		-- happened to boot on a handset.
		local plan = {}
		local function P(inst, prop, phoneValue)
			if not inst then return end
			plan[#plan + 1] = { inst, prop, inst[prop], phoneValue }
		end
		local function PP(inst, prop, deskValue, phoneValue)
			if not inst then return end
			plan[#plan + 1] = { inst, prop, deskValue, phoneValue }
		end

		local onPhone = false
		local recs = {}

		--------------------------------------------------------- panel shell
		local hudScale    = frame:FindFirstChild("HudFixScale")
		local popHolder   = frame:FindFirstChild("PopHolder")
		local panel       = popHolder and popHolder:FindFirstChild("Panel")
		local panelShadow = popHolder and popHolder:FindFirstChild("HardShadow")
		local header      = panel and panel:FindFirstChild("Header")
		local strip       = panel and panel:FindFirstChild("SpecStrip")
		local DESK_FRAME  = frame.Size
		-- CAPTURED, not re-authored -- the same discipline P() uses. The phone fit
		-- below moves the panel off centre to clear the touch band, so going home
		-- has to be a write of the position that was actually there.
		local DESK_POS    = frame.Position

		-- The window fills the frame instead of being a fixed 940x700 box. Its
		-- hard shadow is a SIBLING (UIKit.Builders' UI.hardShadow:
		-- `sh.Parent = frame.Parent`) whose Size is COPIED at construction and
		-- only ever follows Position and AnchorPoint afterwards -- so a resized
		-- surface with an unresized shadow leaves a 940x700 slab poking out from
		-- under a full-screen panel. Same trap the buy buttons carry below.
		P(panel, "Size", UDim2.fromScale(1, 1))
		P(panelShadow, "Size", UDim2.fromScale(1, 1))

		-- HEADER, and this is a decision the brief did not cover. The cluster is
		-- 190 + 168 + 44 + two 10px gaps = 422px wide; a portrait handset gives
		-- the panel's padded content column about 362, so the desktop cluster
		-- does not fit and would push the wallet clean off the left edge. BUY
		-- EMERALDS is still the control that goes, but as of 2026-08-10 the REASON
		-- has changed and is worth writing down: it used to be free to drop
		-- because it was inert, and it is live now. It is dropped because it is
		-- the only DUPLICATE -- the HUD's own emerald counter opens that same shop
		-- panel and stays on screen behind this one, so a handset keeps a real
		-- way to buy. If that counter ever stops opening the shop, this hide
		-- becomes the phone losing the purchase path outright and has to be
		-- reworked rather than simply kept.
		-- The wallet and the close button keep their full 44px height.
		-- The title stops auto-sizing and truncates instead, so it can never
		-- reach the cluster however long a future title gets.
		if header then
			-- round 2 (measured on the iPhone 16 emulation, 733x371): the 92px header +
			-- 26px spec strip + the 112px touch band left a 232px panel with ~65px of
			-- card list -- less than a third of one phone card. The header drops to 60,
			-- the strip goes, and the touch band becomes scroll PADDING (below) rather
			-- than a slice off the panel, so the list gets ~200px and the last card can
			-- still be scrolled clear of the jump button.
			P(header, "Size", UDim2.new(1, 0, 0, 60))
			local title   = header:FindFirstChild("Title")
			local cluster = header:FindFirstChild("HeaderControls")
			local wallet  = cluster and cluster:FindFirstChild("WalletSlot")
			local buySlot = cluster and cluster:FindFirstChild("BuyEmeraldsSlot")
			local buyBtn  = buySlot and buySlot:FindFirstChild("BuyEmeralds")
			local chip    = wallet and wallet:FindFirstChild("WalletChip")
			local bal     = chip and chip:FindFirstChild("Balance")
			local clusterW = WALLET_W + CLOSE_W + CTRL_GAP
			P(buySlot, "Visible", false)
			P(buyBtn, "Visible", false)
			P(wallet, "Size", UDim2.fromOffset(WALLET_W, 44))
			P(chip, "Size", UDim2.fromOffset(WALLET_W, 44))
			P(bal, "Size", UDim2.fromOffset(WALLET_W - 54, 26))
			P(cluster, "Size", UDim2.fromOffset(clusterW, 44))
			P(title, "AutomaticSize", Enum.AutomaticSize.None)
			P(title, "Size", UDim2.new(1, -(clusterW + 18 + 16 + 10), 0, 34))
			P(title, "TextSize", 22)
			P(title, "TextTruncate", Enum.TextTruncate.AtEnd)
		end

		-- SPEC STRIP, same class of decision. Three fixed thirds of a 362px
		-- column are 120px each, and all three lines are 140-230px of 14px type
		-- with no clipping anywhere above them, so on a handset they overlap
		-- each other. DISCOVERY is the slot that survives -- it is the only one
		-- of the three carrying information the player cannot already see (the
		-- egg count is the list itself, and the hint is answered by the word
		-- ODDS sitting on every card) -- and it takes the full width.
		if strip then
			-- round 2: the whole strip goes on a phone (the discovery count is on the
			-- Index tab of the Bag); the card list takes its 26px + gap
			P(strip, "Visible", false)
		end
		-- T.pad.gap, not the shell block's BLOCK_GAP local: that `do` block's locals
		-- are not in scope here
		P(cardArea, "Position", UDim2.fromOffset(0, 60 + T.pad.gap))
		P(cardArea, "Size", UDim2.new(1, 0, 1, -(60 + T.pad.gap)))

		-- The 3 + 2 grid's two rows go dark; every CardHolder moves out of them
		-- and into the scroller below, and moves back on the way home.
		P(cardArea:FindFirstChild("Row1"), "Visible", false)
		P(cardArea:FindFirstChild("Row2"), "Visible", false)

		---------------------------------------------------- the scrolling body
		-- Built ONCE, hidden, and shown by the branch -- not built on demand, so
		-- a device change is a Visible flip and a reparent rather than a rebuild
		-- of five cards with five 3D viewports in them.
		--
		-- CardHolder is what gets parented in here, never the card: a holder has
		-- exactly one child, so nothing an UI.* builder hangs beside a surface
		-- can become a phantom list item and inflate AutomaticCanvasSize.
		local scroller = new("ScrollingFrame", {
			Name = "PhoneBody",
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = T.color.scrollThumb,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ClipsDescendants = true,
			Visible = false,
			ZIndex = cardArea.ZIndex + 1,
		}, cardArea)
		new("UIPadding", {
			-- bottom padding = the touch band: the last card scrolls clear of the jump
			-- button instead of the whole panel losing that height (round 2)
			PaddingTop = UDim.new(0, BODY_PAD), PaddingBottom = UDim.new(0, BODY_PAD + TOUCH_BAND),
			PaddingLeft = UDim.new(0, BODY_PAD), PaddingRight = UDim.new(0, BODY_PAD),
		}, scroller)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, CARD_GAP),
		}, scroller)
		P(scroller, "Visible", true)

		-- Opening the shop starts at the top, the same thing setOpen already
		-- does for the (hidden) legacy list.
		frame:GetPropertyChangedSignal("Visible"):Connect(function()
			if frame.Visible then scroller.CanvasPosition = Vector2.new(0, 0) end
		end)

		------------------------------------------------------- open/closed card
		-- Declared before the card loop because the per-card listener closes
		-- over it. The card GROWS to hold the odds panel rather than the panel
		-- covering anything: that is the whole difference between this layout
		-- and the desktop one.
		local syncCard
		syncCard = function(rec)
			local open = onPhone and rec.panel ~= nil and rec.panel.Visible
			if rec.oddsSlot then rec.oddsSlot.Visible = open end
			if rec.holder and onPhone then
				local h
				if open then h = CARD_H_OPEN else h = CARD_H end
				rec.holder.Size = UDim2.new(1, 0, 0, h)
			end
			if rec.lbl then
				if onPhone then
					if open then rec.lbl.Text = "HIDE" else rec.lbl.Text = "ODDS" end
				elseif not (Platform.IsTouch or Platform.IsPhone) then
					-- A TABLET is touch but not phone: it keeps the desktop card
					-- AND Task 4's tap toggle, so its ODDS caption is not ours to
					-- overwrite. Only a true pointer device gets the number back.
					rec.lbl.Text = rec.restText
				end
			end
		end

		----------------------------------------------------------- the cards
		-- Every world's, once. `i` is the card's slot WITHIN its own world, which
		-- is what the stagger wants, and ShopEggs() hands worlds over whole and in
		-- order so the count restarts naturally at each world's first egg.
		for i, egg in ipairs(EggConfig.ShopEggs()) do
			local c = cards[egg.Id]
			if c and c.root and c.content and c.figure then
				local card      = c.root
				local holder    = card.Parent
				local content   = c.content
				local figure    = c.figure
				local nameRow   = content:FindFirstChild("NameRow")
				local rarestRow = content:FindFirstChild("RarestRow")
				local buyRow    = content:FindFirstChild("BuyRow")
				local eggName   = nameRow and nameRow:FindFirstChild("EggName")
				local price     = nameRow and nameRow:FindFirstChild("Price")
				local ribbon    = c.ribbon
				local ribText   = ribbon and ribbon:FindFirstChild("Text")
				local codeL     = figure:FindFirstChild("Code")
				local metaScrim = figure:FindFirstChild("MetaScrim")
				local oddsPanel = figure:FindFirstChild("OddsPanel")
				local hit       = rarestRow and rarestRow:FindFirstChild("OddsToggle")

				-- THREE PHONE-ONLY CONTAINERS, invisible on desktop. A
				-- UIListLayout skips a non-visible child entirely -- no space
				-- and no gap -- so on desktop the content stack is still exactly
				-- figure / name / rarest / buy in that order, with the same 9px
				-- rhythm, and nothing had to be reordered to achieve it.
				local topRow = new("Frame", {
					Name = "PhoneTop", Size = UDim2.new(1, 0, 0, FIG_H),
					BackgroundTransparency = 1, LayoutOrder = 1, Visible = false,
					ZIndex = content.ZIndex,
				}, content)
				local rightCol = new("Frame", {
					Name = "PhoneCol", Position = UDim2.fromOffset(FIG_W + COL_GAP, 0),
					Size = UDim2.new(1, -(FIG_W + COL_GAP), 1, 0),
					BackgroundTransparency = 1, ZIndex = content.ZIndex,
				}, topRow)
				-- CLIPS, so Task 4's 8px entrance rise is masked here exactly as
				-- the figure masked it on desktop -- the panel slides up out of
				-- the slot's own floor instead of poking past the buy row.
				local oddsSlot = new("Frame", {
					Name = "PhoneOdds", Size = UDim2.new(1, 0, 0, ODDS_H),
					BackgroundTransparency = 1, ClipsDescendants = true,
					LayoutOrder = 2, Visible = false, ZIndex = content.ZIndex + 1,
				}, content)
				P(topRow, "Visible", true)

				-- the card itself: one column, fixed height, filling the body
				P(holder, "Parent", scroller)
				P(holder, "Size", UDim2.new(1, 0, 0, CARD_H))
				P(holder, "LayoutOrder", i)
				P(card, "Size", UDim2.new(1, 0, 1, 0))
				P(content, "Size", UDim2.new(1, -CARD_PAD * 2, 1, -CARD_PAD * 2))

				-- FIGURE, 104 x 118, on the left of the top row.
				P(figure, "Parent", topRow)
				P(figure, "Size", UDim2.fromOffset(FIG_W, FIG_H))
				P(figure, "Position", UDim2.fromOffset(0, 0))
				-- The EGG-0N code and its legibility scrim exist to keep the
				-- ribbon and the code readable ON the art. The ribbon moves off
				-- the art on this layout and 14px of "EGG-01 . 01/05" does not
				-- fit across 104px anyway, so both stand down rather than being
				-- squeezed into a size where neither reads.
				P(codeL, "Visible", false)
				P(metaScrim, "Visible", false)

				-- RIGHT COLUMN: ribbon, name, price, rarest row. Absolute
				-- positions, no layout -- Task 4 tweens things in here and a
				-- layout would own their Position.
				P(ribbon, "Parent", rightCol)
				P(ribbon, "Position", UDim2.fromOffset(0, 0))
				P(ribbon, "ZIndex", rightCol.ZIndex + 1)
				P(ribText, "ZIndex", rightCol.ZIndex + 2)

				P(nameRow, "Parent", rightCol)
				P(nameRow, "Position", UDim2.fromOffset(0, RIB_H + 2))
				P(nameRow, "Size", UDim2.new(1, 0, 0, NAME_H + 4 + PRICE_H))
				P(eggName, "AnchorPoint", Vector2.new(0, 0))
				P(eggName, "Position", UDim2.fromOffset(0, 0))
				P(eggName, "AutomaticSize", Enum.AutomaticSize.None)
				P(eggName, "Size", UDim2.new(1, 0, 0, NAME_H))
				P(eggName, "TextSize", NAME_SIZE)
				P(eggName, "TextYAlignment", Enum.TextYAlignment.Center)
				P(eggName, "TextTruncate", Enum.TextTruncate.AtEnd)
				-- the price group stops hanging off the row's right edge and
				-- sits under the name; its own AutomaticSize.X still grows it
				-- leftward-to-rightward from here however many digits it has
				P(price, "AnchorPoint", Vector2.new(0, 0))
				P(price, "Position", UDim2.fromOffset(0, NAME_H + 4))

				-- RAREST ... ODDS, 34 high, pinned to the bottom of the column.
				P(rarestRow, "Parent", rightCol)
				P(rarestRow, "Position", UDim2.fromOffset(0, FIG_H - RAREST_H))
				P(rarestRow, "Size", UDim2.new(1, 0, 0, RAREST_H))
				-- The hit target is Task 4's own: 44 tall, bottom-aligned, so it
				-- grows UPWARD out of the 34px row into the price line above,
				-- which is not interactive. 34 is the row; 44 is the floor.
				-- Platform.IsTouch, NOT A HARD-CODED false (final review M3). Task 4
				-- builds this button with Visible/Active = tapMode(), and tapMode() is
				-- `Platform.IsTouch or Platform.IsPhone` -- TRUE ON A TABLET, which
				-- keeps the desktop card and reaches its odds only through this tap
				-- target (pin/pout both return early under tapMode, so a tablet has no
				-- hover path at all). Writing false as the desktop value left a tablet
				-- with NO odds affordance whatsoever after a Phone -> non-Phone
				-- applyLayout. On the non-phone branch IsPhone is false by definition,
				-- so IsTouch is exactly what tapMode() answers there -- and unlike a
				-- captured layout state it is the device's own capability, so it stays
				-- right even for a client that booted under the Phone override (which
				-- deliberately does not force IsTouch).
				PP(hit, "Visible", Platform.IsTouch, true)
				PP(hit, "Active", Platform.IsTouch, true)

				-- BUY ROW, full width, 48 high. Thirds in SCALE so the row
				-- reflows with the card: 3 x (w/3 - 4) + 2 x 6 = w exactly.
				P(buyRow, "Size", UDim2.new(1, 0, 0, BUY_H))
				for _, qty in ipairs({ 1, 3, 10 }) do
					local slot = c.buySlots and c.buySlots[qty]
					local btn = c.buyButtons and c.buyButtons[qty]
					if slot and btn then
						P(slot, "Size", UDim2.new(1 / 3, -4, 1, 0))
						P(btn, "Size", UDim2.new(1, 0, 1, 0))
						-- UI.hardShadow COPIES the size once and thereafter only
						-- follows Position and AnchorPoint, so a resized button
						-- with an unresized shadow leaves an 88x40 dark block
						-- sticking out of a full-width control.
						P(slot:FindFirstChild("HardShadow"), "Size", UDim2.new(1, 0, 1, 0))
						local cap = btn:FindFirstChild("Qty")
						local sub = btn:FindFirstChild("Subtotal")
						P(cap, "Size", UDim2.new(1, 0, 0, 24))
						P(cap, "Position", UDim2.fromOffset(0, 6))
						P(sub, "Size", UDim2.new(1, 0, 0, 16))
						-- 30, not 28: the Qty box above occupies y 6..30, so 28 made the two
						-- label rects intersect by 2px. 30 + 16 = 46, still inside the
						-- 48-tall phone button.
						P(sub, "Position", UDim2.fromOffset(0, 30))
					end
				end

				-- THE ODDS PANEL MOVES, IT IS NOT REBUILT. Task 4 owns its rows,
				-- its colours, its fade list and its tweens; all this does is
				-- change which box it fills. It is fromScale(1, 1) at a Position
				-- Task 4 tweens between (0, 8) and (0, 0), so it fills whatever
				-- it is parented to and its entrance still reads the same.
				if oddsPanel then
					P(oddsPanel, "Parent", oddsSlot)
					P(oddsPanel, "ZIndex", oddsSlot.ZIndex + 1)
				end

				local best = egg.Table[#egg.Table]
				local rec = {
					holder = holder, oddsSlot = oddsSlot, panel = oddsPanel,
					lbl = c.rarestOdds,
					-- RECOMPUTED from EggConfig rather than read off the label:
					-- if this client booted on a handset the label already says
					-- ODDS, and capturing that would make "back to desktop" show
					-- the word ODDS where the percentage belongs.
					restText = string.format("%g%%", best[2]),
				}
				recs[#recs + 1] = rec
				if oddsPanel then
					oddsPanel:GetPropertyChangedSignal("Visible"):Connect(function()
						syncCard(rec)
					end)
				end
			end
		end

		------------------------------------------------------------- the branch
		local function fitPhonePanel()
			-- The GUI's own box, not Platform.Viewport: PrepareGui put this
			-- ScreenGui on CoreUISafeInsets, so its AbsoluteSize is already the
			-- notch-and-topbar-safe area, and the camera viewport is not.
			local w, h = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
			if w < 100 or h < 100 then
				w, h = Platform.Viewport.X, Platform.Viewport.Y
			end
			if hudScale then hudScale.Scale = 1 end
			-- gui.AbsoluteSize is already notch- and topbar-safe (PrepareGui put
			-- this ScreenGui on CoreUISafeInsets), but that says nothing about the
			-- touch controls: Platform keeps those in Insets().Bottom. The larger
			-- of the two, so a device reporting a real bottom inset keeps it.
			-- round 2: the touch band is scroll padding now (see the PhoneBody
			-- UIPadding), so the panel keeps the height and only clears a small
			-- margin; the frame is centred, so half of it comes off each end
			local band = 16
			frame.Size = UDim2.fromOffset(
				math.max(320, w - EDGE * 2), math.max(240, h - EDGE * 2 - band))
			frame.Position = UDim2.new(0.5, 0, 0.5, -math.floor(band / 2))
		end

		local function applyLayout(phone)
			-- HOVER FIRST, BEFORE ANYTHING MOVES (final review M2). Task 4's hover
			-- state is a closure in another block; `cards.clearHover` is the hook it
			-- publishes. Without this a class change strands an open odds panel and a
			-- lifted card, and the strand is sticky -- setActive early-returns on the
			-- card it still believes is hovered. Called BEFORE `onPhone` flips so the
			-- odds panel's own Visible listener collapses the holder under the layout
			-- that is still live.
			if cards.clearHover then cards.clearHover() end
			onPhone = phone
			for _, e in ipairs(plan) do
				-- SPELLED OUT, never `phone and e[4] or e[3]`: seven of these
				-- rows have `false` as their phone value, and `x and false or y`
				-- is always y in Lua. Task 4 shipped exactly that bug once.
				local v
				if phone then v = e[4] else v = e[3] end
				e[1][e[2]] = v
			end
			for _, rec in ipairs(recs) do syncCard(rec) end
		end

		-- WRAPS relayout rather than adding a second Platform.Watch listener,
		-- the same composition Task 5 used on refreshAffordability: the previous
		-- value is read into an upvalue FIRST and called through, so the panel
		-- fit, the recentre and the odds hint all still happen exactly as they
		-- did. Task 1's Watch call was changed to invoke `relayout` through a
		-- closure so that this reassignment is what the device-change signal
		-- actually reaches -- passing the function VALUE would have pinned the
		-- listener to the unwrapped original forever.
		local prevRelayout = relayout
		relayout = function()
			if prevRelayout then prevRelayout() end
			local phone = Platform.IsPhone
			if phone ~= onPhone then applyLayout(phone) end
			if phone then
				fitPhonePanel()
			else
				frame.Size = DESK_FRAME
				frame.Position = DESK_POS
			end
		end
		-- Once, now: Platform.Watch already fired the ORIGINAL relayout during
		-- Task 1's block, hundreds of lines before this wrapper existed, so a
		-- client that booted on a handset would otherwise sit in the desktop
		-- layout until something else changed.
		relayout()
	end
	installPhoneLayout()
end

---------------------------------------------------------------- hatch (EggHatch)
-- EGG HATCH OVERHAUL (2026-09-21). The two ceremonies that lived here -- a 1,850-line
-- ViewportFrame hatch for x1 (which had thrown on every purchase since 2026-08-26:
-- `Platform` was only ever required inside three do-blocks, so `Platform.Viewport` at
-- this scope indexed nil and no x1 hatch was ever seen) and a grid of result cards
-- for x3/x10 -- are gone. Presentation is ReplicatedStorage.Modules.EggHatch now: real
-- eggs staged in the world in front of the camera for every quantity, the creature on
-- screen before a single word of text, one rarity ladder, one restore path.
--
-- This file keeps exactly two jobs: decide WHEN a result plays, and hide / restore its
-- own panel around the run. A reward egg (Source = "reward") arrives with the shop shut
-- and has to leave it shut; a purchase arrives with it open and gets it back.
local EggHatch = require(ReplicatedStorage.Modules:WaitForChild("EggHatch"))

local function playHatch(result)
	local shopWasVisible = frame.Visible
	frame.Visible = false
	local started = EggHatch.play(result, {
		onDone = function()
			-- shopOpen re-latches off frame.Visible (see the open / close section), so
			-- putting the panel back is all it takes for the walk-away closer and the
			-- prompt toggle to see a normally-open shop again
			frame.Visible = shopWasVisible
		end,
	})
	if not started then frame.Visible = shopWasVisible end
end

---------------------------------------------------------------- emerald state pull
-- EmeraldUpdate's join-time push can race this script's own listener connecting
-- (Task 3's note), so this ALSO pulls current state via a RemoteFunction --
-- once at startup, and again every time the panel opens.
local emeraldStateRF = remotes:WaitForChild("EmeraldState")
local function applyEmerald(payload)
	if type(payload) ~= "table" then return end
	if payload.Darrels then
		currentEmeralds = math.floor(payload.Darrels)
		emeraldLabel.Text = comma(currentEmeralds)
		-- .Daily is only a table once the profile has actually loaded, so it is the
		-- discriminator that tells a real 0 from a placeholder 0.
		if typeof(payload.Daily) == "table" then emeraldsKnown = true end
		refreshAffordability()
	end
	-- payload.Daily is deliberately unused: quests render in the Goals panel now.
end
local function pullEmeraldState()
	task.spawn(function()
		local ok, res = pcall(function() return emeraldStateRF:InvokeServer() end)
		if ok then applyEmerald(res) end
	end)
end
pullEmeraldState()
remotes.EmeraldUpdate.OnClientEvent:Connect(applyEmerald)

---------------------------------------------------------------- open / close
-- THE LATCH IS THE FIX FOR THE STARVED CLOSE (final review C1).
--
-- setOpen(false) does not hide `frame` itself. It bumps openToken and defers the
-- hide 0.12s so the close tween can land, with the token there to let a reopen
-- racing it win. The walk-away Heartbeat at the foot of this script tested
-- `frame.Visible` -- which is precisely the value setOpen defers writing -- so
-- while the player stood out of range it called setOpen(false) on EVERY frame.
-- Each call bumped openToken and invalidated the pending hide roughly 7 frames
-- before its own 120ms could elapse; frame.Visible never went false, the guard
-- never tripped, the calls never stopped, and it leaked two Tweens plus a
-- task.delay per frame for as long as the player stayed away. Measured at 98.6
-- studs before the fix: 120 invocations in 120 frames, panel never closed.
--
-- `shopOpen` is written SYNCHRONOUSLY, at the moment the decision is made rather
-- than 120ms later, and a redundant close is a no-op -- so the Heartbeat's second
-- call and every one after it does nothing, and the hide the FIRST one scheduled
-- is allowed to land. This is the latch WheelClient uses on its own identical
-- walk-away closer (`if isOpen and not spinning then setOpen(false) end`), and
-- the closer below is spelled the same way so the intent is legible there too.
--
-- ONLY THE CLOSE PATH IS LATCHED, deliberately. setOpen(true) stays fully
-- repeatable: the EggResult handler calls it on every successful purchase to
-- re-pull emerald state, and an early return there would silently drop that
-- refresh.
--
-- NO NEW TOP-LEVEL REGISTER: openToken moved into the do-block below in exchange,
-- so this section still declares exactly two. The chunk peaks at 193 of Luau's
-- hard 200 and a 201st is a whole-script COMPILE failure whose symptom is "the
-- shop does nothing", not an error on the offending line.
local shopOpen = false
local setOpen
do
	local openToken = 0
	setOpen = function(open)
		open = not not open
		-- THE WHOLE FIX, in one line.
		if not open and not shopOpen then return end
		shopOpen = open
		openToken += 1
		local token = openToken
		if open then
			-- round 2.5: re-fit on every open. The desktop fit now clears the HUD's
			-- currency cluster, whose width follows the cash string, and the
			-- Platform.Watch pass ran at boot before the HUD had painted it.
			if relayout then relayout() end
			frame.Visible = true
			scrim.Visible = true
			openPop.Scale = 0.92
			TweenService:Create(openPop, T.tween.panelOpen, { Scale = 1 }):Play()
			-- scrim paint removed (dim-to-blur): EggShopBlur follows frame.Visible via the scrim mirror at the build site
			SoundKit.play("panelOpen", nil, { volume = 0.15 })
			pullEmeraldState()
		else
			TweenService:Create(openPop, T.tween.panelClose, { Scale = 0.95 }):Play()
			-- scrim un-paint removed (dim-to-blur): the mirror destroys EggShopBlur when the deferred hide lands
			-- hide after the close tween lands; the token guards a reopen racing it
			task.delay(0.12, function()
				if token ~= openToken then return end
				frame.Visible = false
				scrim.Visible = false
				openPop.Scale = 1
			end)
		end
	end
end

-- RE-LATCH OFF THE FRAME, and the latch is unsafe without it. Both hatch
-- ceremonies hide `frame` directly and skip() puts it back when they end, neither
-- through setOpen -- so the panel can return to the screen while shopOpen says
-- false, and a false latch is a panel nothing can close. Walking away DURING a
-- bulk hold is the reachable route: the closer runs, the latch goes false, and
-- then the ceremony ends and restores a panel the player is 100 studs from.
-- This can never undo the starvation guard above, because during the 0.12s
-- pending hide frame.Visible is still TRUE and unchanged, so no signal fires.
frame:GetPropertyChangedSignal("Visible"):Connect(function()
	if frame.Visible then shopOpen = true end
end)
closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

-- THE RESULT HANDLER. Every EggResult -- purchase, daily / season reward egg, pending
-- eggs flushed from the Bag -- lands here and goes straight into the hatch; the
-- 1.10s bulk hold that used to let the ACQUIRED stamp and the receipt ticket be seen
-- is gone with the card grid they were pacing (the panel is hidden the instant the
-- hatch starts, so neither would be visible anyway, and the hatch is the feedback).
-- Refusals are untouched: a refusal has no ceremony to wait for, its toast surfaces now.
do
	remotes.EggResult.OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then return end
		if not result.Ok then
			showToast(result.Message)
			return
		end
		-- A purchase refreshes the balance. setOpen(true) used to do this and also
		-- replayed the panel's open pop + sound on a panel that was already open and is
		-- about to be hidden for the hatch; a pull is the part that is actually wanted.
		-- A shut shop (a purchase result racing a walk-away close) still reopens, as before.
		-- NOT FOR A REWARD: a daily or season egg fires this same remote with the shop
		-- shut, and opening the shop on top of the panel the player is looking at would
		-- be a non-sequitur -- the hatch is its own full-screen moment.
		if result.Source ~= "reward" then
			if shopOpen then pullEmeraldState() else setOpen(true) end
		end
		playHatch(result)
	end)
end

---------------------------------------------------------------- stall prompt
-- Gino has a stall in each world; accept the prompt from any of them.
local StallPrompt = require(game:GetService("ReplicatedStorage").Modules.StallPrompt)
-- Gino's stalls, by model name. The trigger test is IDENTITY, not a table keyed by the
-- prompt instance.
--
-- WHY: this was briefly a weak-keyed table of prompt instances, and the shop stopped
-- opening. An Instance's Lua wrapper is collectable even while the instance itself is
-- perfectly alive in the DataModel, so a weak entry can vanish at any GC and the
-- PromptTriggered lookup then fails to recognise a prompt it had definitely bound.
-- Matching on name + owning stall has no such failure mode, and it survives streaming
-- replacing the prompt with a fresh instance.
-- VALUES ARE WORLD IDS, not `true` (2026-08-23). As a set of booleans this table
-- said "these three stalls open the egg shop" and nothing more, so all three opened
-- THIS shop -- whose WORLD_ID is a load-time constant of "Forest". That is how the
-- Frozen Tundra stall came to sell world 1's eggs. Naming each stall's world lets
-- the trigger handler below notice the mismatch.
local EGG_STALLS = { EggStall = "Forest", TundraEggStall = "Tundra", GardensEggStall = "Gardens" }
local eggParts = {}
-- Via StallPrompt: the old one-shot WaitForChild(..., 30) timed out for the tundra
-- stall whenever the player joined in the valley (streaming does not replicate parts
-- 11k studs away), so Gino's world 2 prompt opened nothing.
-- Still bound through StallPrompt, but only to collect the prompt PARTS for the
-- walk-away check; opening is handled by the identity test below.
local function bindEggStall(stallName)
	StallPrompt.Bind(stallName, "EggPrompt", function(part, prompt)
		table.insert(eggParts, part)
	end)
end
bindEggStall("EggStall")
bindEggStall("TundraEggStall")
bindEggStall("GardensEggStall")
ProximityPromptService.PromptTriggered:Connect(function(triggeredPrompt, who)
	if who ~= player then return end
	if triggeredPrompt.Name ~= "EggPrompt" then return end
	local stall = triggeredPrompt:FindFirstAncestorWhichIsA("Model")
	local stallWorld = stall and EGG_STALLS[stall.Name]
	if not stallWorld then return end
	-- ONE SHELL, EVERY WORLD. The shop holds a full set of cards per shop-ready
	-- world and swaps which set is on screen, so a stall opens its OWN catalogue
	-- instead of world 1's. Retarget BEFORE opening, and ONLY when opening: a
	-- press that is about to close the panel has no world to choose, and swapping
	-- cards under a panel already up would be a visible flicker. setWorld returns
	-- false for a world the shell cannot draw (unknown, not Active, or
	-- ShopReady = false); refusing there keeps this in step with EggHandler, which
	-- has already relabelled that stall to read "Coming Soon".
	if not shopOpen and not cards.setWorld(stallWorld) then return end
	-- OFF THE LATCH, not off frame.Visible (final review C1): during setOpen's
	-- 0.12s pending hide the frame is still visible although the shop is already
	-- closing, so the old test made a prompt press in that window re-issue a close
	-- instead of reopening. shopOpen is the value that flipped synchronously.
	setOpen(not shopOpen)
end)

-- the shared slot-spin driver (see addEggViewport); connected once, for life
RunService.RenderStepped:Connect(function()
	if not frame.Visible or #eggSpinners == 0 then return end
	local t = os.clock()
	local ang = (t / SLOT_SPIN_TIME) * (2 * math.pi)
	for _, s in ipairs(eggSpinners) do
		local a = ang + s.phase
		local dir = CFrame.Angles(0, a, 0) * BrainrotThumb.DEFAULT_DIR
		local bob = math.sin(t * 1.7 + s.phase) * SLOT_BOB * s.dist
		s.cam.CFrame = CFrame.lookAt(s.centre + dir * s.dist + Vector3.new(0, bob, 0), s.centre)
	end
end)

-- walk away -> close, same convention as the other stall panels (MerchantClient)
RunService.Heartbeat:Connect(function()
	if not frame.Visible then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local nearestEgg = math.huge
	for _, part in ipairs(eggParts) do
		-- a parentless part has STREAMED OUT; its last position is stale
		if part.Parent then
			nearestEgg = math.min(nearestEgg, (hrp and (hrp.Position - part.Position).Magnitude) or math.huge)
		end
	end
	-- GATED ON THE LATCH, NOT ON frame.Visible (final review C1). frame.Visible is
	-- the value setOpen DEFERS writing by 0.12s, so testing it here asked for a
	-- close on every one of the ~7 frames before the previous close could land --
	-- and each ask invalidated the last, forever. shopOpen flips synchronously
	-- inside setOpen, so this now fires exactly once per walk-away. Same shape
	-- WheelClient guards its own identical closer with.
	if hrp and #eggParts > 0 and nearestEgg > 24 and shopOpen then
		setOpen(false)
	end
end)
