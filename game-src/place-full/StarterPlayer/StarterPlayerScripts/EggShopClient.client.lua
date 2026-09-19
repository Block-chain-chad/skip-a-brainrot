-- EggShopClient -- Forest Egg Shop panel: 5-egg buy list with data-driven odds,
-- a emerald chip, and the daily-quest mini list. Opens via the EggStall's
-- ProximityPrompt on the client (server never gates the OPEN, only the BUY).
--
-- ODDS ARE ALWAYS VISIBLE AND NEVER HARD-CODED: every percentage rendered here
-- comes from iterating EggConfig's own egg.Table at runtime -- the server rolls
-- from those exact same rows (EggHandler.RollFor), so shown odds can never
-- drift from real odds (Roblox requires published odds for paid random items).
--
-- playReveal(result), further down, plays the hatch animation (Task 8):
-- shake -> crack -> tier-lit creature spin -> skip/fade. Everything around it
-- (buy -> disable -> result -> reopen) is unrelated and untouched by that task.
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
-- near the top of this file -- playMultiReveal's Skip button is still its caller.
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
	-- IF BULK_HOLD MOVES, MOVE THIS. The invariant is
	-- TICKET_LIFE + TICKET_OUT == BULK_HOLD, and nothing enforces it at runtime
	-- because the two live in different do-blocks.
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

		-- BULK ORDERS ONLY (Task 7, the user's ruling). Task 6 proved these two
		-- are never seen on a x1 buy: playReveal sets frame.Visible = false and
		-- disables every other ScreenGui in the same frame they are created, and
		-- the ceremony outlives both. Rather than have them fight a single hatch
		-- for the screen, they now belong to the purchase that actually reads as
		-- an ORDER -- x3 and x10 -- which is also what the ticket's own SENT TO
		-- HATCH QUEUE line says out loud. The reveal handler at the foot of this
		-- script holds the ceremony back 1.10s on the same test, so on a bulk buy
		-- both are seen in full before it takes the screen.
		--
		-- THE SAME TEST, OFF THE SAME FIELD: this asks n > 1 from #Results, and
		-- so does the reveal handler when it picks playMultiReveal over
		-- playReveal. The two connections can never disagree about which kind of
		-- purchase this was, however their firing order lands.
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

---------------------------------------------------------------- hatch reveal
-- EGG HATCH -- a 1:1 build of the "Egg Hatch: 3D Egg Opening Sequence" design
-- handoff (design_handoff_egg_hatch: README.md + egg-scene.js, 2026-08-13). It
-- REPLACES the ten-beat "Animation Spec v1" ceremony that used to live here.
--
-- WHAT IS 1:1. Every number the handoff calls final is transcribed literally into
-- `D` below and used nowhere else: the phase offsets (0 / 900 / 1500 / 2350 ms),
-- the exponentially damped easing and its six lambdas, the idle spin and bob, the
-- four shake curves, the split transforms for both halves, the reveal lift, the
-- seven-chunk rigid burst (pivots, velocities, gravity, per-axis spin, the 0.95 s
-- hold before a 0.30 s fade), the pet rise, the camera (FOV 32, 42 when narrower
-- than 0.85 aspect, z 7.6 -> 8.6 at lambda 3) and the whole 2D layer -- sunburst,
-- radial glow, vignette, split flash, rarity ring, captions and the reveal card.
--
-- The handoff's distances are in ITS egg's units (that egg is 2.48 tall, RY 1.24).
-- `u` maps them onto whichever shell the real egg has, so the motion is
-- proportionally identical across all five eggs instead of being right for one.
--
-- FOUR DELIBERATE DEVIATIONS, each forced by the engine or by this game:
--
--  1. THE EGG ART IS OURS -- REBUILT IN VOXELS. The brief was to keep our five
--     egg designs and adopt the handoff's SEQUENCE. Since 2026-08-13 the
--     ceremony shows a cube-built rebuild of the authored egg FROM THE FIRST
--     FRAME (user: the smooth egg clashed with the game's voxel feel): the
--     shell becomes a hollow one-cube-thick lattice in its own colour, the
--     decorations are refilled cube-by-cube on the same lattice (near-invisible
--     aura shells dropped -- the 2D glow carries that job), fully-opaque
--     decoration colours are painted onto the shell cubes they touch, and every
--     cube is dealt to cap or cradle by its own centre against the seam. The
--     pet is voxelised the same way at the reveal (display only -- the granted
--     pet stays authored art everywhere else). The handoff's jagged 5-tooth
--     seam, its +-0.20 tooth depth and its below-centre split line are
--     reproduced exactly.
--
--  2. NO POINT LIGHT. ViewportFrames do not render Lights at all -- the ceremony
--     this replaces parented a PointLight into one and it drew nothing, ever.
--     The handoff's "core light, intensity = glow x 6" is a neon core orb inside
--     the shell plus a rarity-ward tint on the viewport's own Ambient, both
--     driven by the same damped `glow`, so every beat it lit still lights.
--
--  3. TIER COLOURS ARE THE GAME'S. The handoff ships a COMMON..MYTHIC palette;
--     our pets are Rare..Secret and RarityConfig's colours are the language the
--     backpack, the index and every card in the game already speak. Accent comes
--     from RarityConfig and the handoff's second "glow" tone is derived from it.
--
--  4. THE CARD'S PRIMARY BUTTON IS "COLLECT", NOT "SEND TO FLOCK". EggHandler has
--     already granted the pet into data.Pets by the time this plays, so there is
--     nothing left to send; the button keeps the handoff's filled-accent slot and
--     its pressed treatment, and closes the ceremony. HATCH ANOTHER re-buys the
--     same egg through the shop's own fireBuy, so the buy lock, the bundle price
--     and the affordability check are all the ones the shop already enforces.
--
-- The surrounding contract is unchanged: revealGen/revealSkip still make a second
-- EggResult arriving mid-reveal safe, skip() is still the only thing that
-- restores the HUD, and the three failsafes below it still guarantee skip() runs.
local revealGui
local function ensureRevealGui()
	if revealGui and revealGui.Parent then return revealGui end
	revealGui = new("ScreenGui", {
		-- DISPLAY ORDER 40 is the fallback: EggShopUI used to sit at T.zindex.panel
		-- (25) with every other panel, so without this the SHOP rendered above the
		-- hatch it launches. round 2.5 moved the shop onto HudLayout's "Panel"
		-- layer (40+), so the reveal now registers on "Dialog" (50+) -- a step
		-- above the shop, still under ToastClient (60) so a real system toast can
		-- reach the player. Full-bleed: the ceremony wants the whole screen.
		Name = "EggRevealUI", DisplayOrder = 40, IgnoreGuiInset = true, ResetOnSpawn = false,
	}, playerGui)
	require(ReplicatedStorage.Modules:WaitForChild("HudLayout")).PrepareGui(revealGui, "Dialog", true)
	return revealGui
end

-- Shared by BOTH ceremonies (this one and playMultiReveal below). The generation
-- counter is what makes a second EggResult arriving mid-reveal safe, and
-- revealSkip is the handle whichever reveal is live registers so the next one can
-- end it.
local FADE_TIME = 0.3
local DIM_TARGET = 0.72
local SKIP_GRACE = 0.35
local revealGen, revealSkip = 0, nil

local playReveal
do
	-- THE HANDOFF, TRANSCRIBED. Nothing in this table is a taste call -- every
	-- entry is a literal from README.md or egg-scene.js, in the handoff's units.
	-- If the design moves, this table is the only thing that moves with it.
	local D = {
		RY = 1.24,                                    -- handoff egg half-height: the unit map
		FOV = 32, FOV_NARROW = 42, NARROW_AT = 0.85,
		CAM_Y = 0.2, CAM_Z = 7.6, CAM_Z_OUT = 8.6, LOOK_Y = 0.02,
		-- damped approach: value += (target - value) * (1 - e^(-lambda*dt))
		-- LAM_OPEN raised 5.5 -> 11 (2026-08-14, measured): the reference shell reaches
		-- 68% of its full gap in 130ms and ours took ~250ms, so the split read as a
		-- drift rather than a snap. Everything else keeps its damping.
		LAM_SHAKE = 9, LAM_OPEN = 11, LAM_GLOW = 7, LAM_PET = 6, LAM_LIFT = 4, LAM_CAM = 3,
		-- RETIMED to the user's reference clip, measured frame-by-frame 2026-08-14
		-- (30fps, re-based at the frame the new egg appears): crack 2.20, split 2.47,
		-- reveal ~3.40. The old 0.90/1.50/2.35 cracked before any anticipation had
		-- built, which is why the payoff did not land -- the reference spends 2.2s
		-- just wobbling. Note crack->split TIGHTENS (0.60 -> 0.27): the shell snaps.
		AT_CRACK = 2.20, AT_SPLIT = 2.47, AT_REVEAL = 3.40,
		SPIN_IDLE = 0.42, SPIN_BUSY = 0.12, BOB_HZ = 1.5, BOB_AMP = 0.045,
		SHAKE = 1, SHAKE_CRACK = 1.7, SHAKE_MIN = 0.32,
		GLOW_CRACK = 0.9, GLOW_SPLIT = 2.2, GLOW_REVEAL = 0.45,
		TOP_Y = 1.35, TOP_X = 0.12, TOP_RX = 0.2, TOP_RZ = -0.16,
		BOT_Y = -0.12, BOT_RX = -0.06,
		LIFT = 0.48, CORE_Y = 0.1, CORE_DY = 0.3,
		SECT = 7, BURST_CAP = 1.25, BURST_G = 2.4, BURST_R = 0.45, BURST_H = 0.4,
		BURST_HOLD = 0.95, BURST_FADE = 0.3,
		-- PET_S/PET_DS raised 0.5/0.55 -> 0.62/0.72 (2026-08-14, user: "you cant even
		-- see the pet"). Measured at reveal, the pet came out 0.82 wide against a
		-- 4.05-wide cradle -- a fifth of the egg -- and its own colours were fine
		-- (mean luminance 0.66, zero near-black parts), so it read as invisible
		-- purely from being small and nested down among the decorations.
		PET_Y = -1.1, PET_DY = 0.98, PET_S = 0.70, PET_DS = 0.85, PET_H = 0.95,
		-- seam: yCut(theta) = -0.05 + 0.20 * tri(theta, 5). FIVE teeth, +-0.20
		-- deep (~16% of egg height), centred BELOW the equator so the cradle is
		-- the larger piece -- the handoff calls out all three as must-keeps.
		SEAM_MID = -0.05, SEAM_AMP = 0.20, TEETH = 5, SHELL = 0.30, INNER_R = 0.745,
		RX = 0.94,   -- handoff egg half-WIDTH; the framing match below needs both
	}

	-- THE BACKDROP IS THE HANDOFF'S, NOT THE OLD CEREMONY'S DIM. The handoff draws
	-- this sequence on a solid #07090a stage, and its vignette, radial glow and
	-- sunburst are all authored against that ground -- at the 0.72 dim the ceremony
	-- this replaced used, the lit world behind kept reading through them and the
	-- glow had nothing to sit on. DIM_TARGET itself is left alone: it still belongs
	-- to playMultiReveal, which is not this design.
	local STAGE_DIM = 0.04

	-- TERRACED TIERS, not a cube lattice (user's two reference videos,
	-- 2026-08-14). The reference egg is a stack of about a DOZEN thick discs,
	-- each carrying a visible lip, finished with a few BIG rim teeth -- its
	-- blocky read comes from a handful of large vertical STEPS, not from
	-- cube-sized detail. The 294-cube lattice tried the opposite and came out
	-- FINER than the smooth mesh it replaced, so it read as mush on screen and
	-- cost ~25x the parts. WEDGES cuts the tooth band (4 segments per tooth,
	-- so each of the 5 teeth is a chunky stepped triangle) and the inner wall.
	-- 9 tiers, measured off the reference: its silhouette shows 7-8 countable
	-- plateaus, each about an eighth of the egg's height. 12 was a shade too fine
	-- and started blending back toward a curve.
	local TIERS, WEDGES = 9, 20

	-- VOXEL_SHELL (2026-08-14). Flip to false to get the 9 terraced tiers back --
	-- the tier code below is untouched, it just moves into the else branch.
	-- Measured off the user's 2026-08-13 reference clip: its silhouette shows ~11
	-- clean plateaus averaging 6-7% of egg height (the four shorter ones are rim
	-- pebbles, not steps), i.e. a ~13-14 row lattice. That disagrees with the 9
	-- terraced discs read off the 08-14 clips -- they are DIFFERENT videos of
	-- different eggs, and the user pointed at the 08-13 one.
	local VOXEL_SHELL, VOX_ROWS = true, 16   -- 16 to match Modules.VoxelEgg; 14 drifted from the shop eggs

	-- TWO UNIT MAPS, and the split between them is load-bearing.
	--
	-- `uShell` (= b / RY) maps the handoff's units onto THE SHELL, and everything
	-- measured on the shell uses it: the seam heights, the tooth depth, the shell
	-- thickness. It has to, or a tall egg would get its seam sliced at the wrong
	-- fraction of its own height.
	--
	-- `uScene` maps them onto THE FRAME, and the camera plus every travelled
	-- distance uses it: the cap's rise, the reveal lift, the burst pivots and
	-- velocities, the pet's size and its climb. Those are all things the handoff
	-- specifies as a fraction of the frame -- and our eggs are not its egg. The
	-- five carry spiked, crowned and haloed decoration running 1.3-1.7x the
	-- shell's own height and up to 2.6x its width, so scaling the camera off the
	-- shell (as the first cut did) pushed a third of that furniture outside the
	-- frame. Scaling off the bounding sphere -- BrainrotThumb.framing's rule -- is
	-- safe but frames on the space diagonal, which shrinks the egg well below the
	-- handoff's read.
	--
	-- So uScene asks the question directly: at this FOV and this aspect, how much
	-- further away than the handoff's own egg does OUR egg have to sit to subtend
	-- the same fraction of the frame? Both distances are a real frustum fit on
	-- height AND width, so the answer stays right in portrait -- where a wide egg
	-- is width-limited and the handoff's egg is too -- as well as in landscape.
	local function sceneScale(model, fov, aspect)
		local tanV = math.tan(math.rad(fov / 2))
		local tanH = tanV * math.max(0.05, aspect)
		local ext = model:GetExtentsSize()
		local need = math.max(ext.Y / 2 / tanV, math.max(ext.X, ext.Z) / 2 / tanH)
		return need / math.max(1e-4, math.max(D.RY / tanV, D.RX / tanH))
	end
	local TAU = math.pi * 2

	local TAP_TIMEOUT = 4.0      -- the ceremony must never wait forever for a tap
	local AUTO_DISMISS = 12      -- ...nor sit on the card forever
	local REVEAL_FAILSAFE = 30
	local REVEAL_BLUR = 24
	local CRACK_SFX = { "eggCrack1", "eggCrack2", "eggCrack3" }
	local STING = {
		Rare = "catchRare", Epic = "catchEpic", Legendary = "catchLegend",
		Mythic = "catchMythic", Secret = "catchSecret",
	}

	local function damp(cur, target, lambda, dt)
		return target + (cur - target) * math.exp(-lambda * dt)
	end

	-- triangular wave in [-1,1], k periods around the circle -> the chunky teeth
	local function tri(a, k)
		local p = ((k * a) / TAU) % 1
		if p < 0 then p += 1 end
		return math.abs(4 * (p - 0.5)) - 1
	end

	-- the handoff's own deterministic hash, so the burst is the burst in the
	-- reference clip rather than a fresh scatter every hatch
	local function rand(i, s)
		local x = math.sin(i * 127.1 + s * 311.7) * 43758.5453
		return x - math.floor(x)
	end

	local function seamOf(theta) return D.SEAM_MID + D.SEAM_AMP * tri(theta, D.TEETH) end

	-- The handoff's tier "glow" is a deep, desaturated companion to the tier
	-- colour (#B7F36A -> #4F8A1F). Derived rather than tabled, because the tier
	-- colours themselves are RarityConfig's -- see deviation 3.
	local function deepen(col)
		local h, s, v = col:ToHSV()
		return Color3.fromHSV(h, math.min(1, s * 1.12), v * 0.42)
	end

	-- hex alpha -> Roblox transparency, so the handoff's 0x22 / 0x77 / 0xcc read
	-- here exactly as they are written there
	local function alpha(a) return 1 - a / 255 end

	-- N stacked layers whose alphas compound to `peak` at the centre
	local function perLayer(peak, n) return 1 - (1 - peak) ^ (1 / n) end

	-- Roblox has no letter-spacing. The handoff's mono chips are set at 0.24em,
	-- which is most of why they read as chips at all, so the short ones are spaced
	-- by hand -- the standard trick, and it only ever touches a few words.
	local function spaced(s)
		-- per CODEPOINT, not per byte: a byte-wise gsub("(.)") splits the
		-- \u{00B7} middot's two UTF-8 bytes apart and the label draws
		-- replacement glyphs where the interpunct belongs
		local out = {}
		for _, cp in utf8.codes(tostring(s):upper()) do
			out[#out + 1] = utf8.char(cp)
		end
		return table.concat(out, " ")
	end

	-- The handoff's corner chip counts the player's collection; ours counts pets.
	-- Its own listener rather than a hook into the discovery snapshot further up,
	-- so the chip cannot go stale if that block is ever rewritten. EggHandler
	-- pushes data BEFORE it fires EggResult, so by the time a ceremony reads this
	-- the pet it just granted is already counted.
	local petsOwned = nil
	remotes:WaitForChild("DataUpdated").OnClientEvent:Connect(function(snap)
		if typeof(snap) == "table" and typeof(snap.Pets) == "table" then
			local n = 0
			for _ in pairs(snap.Pets) do n += 1 end
			petsOwned = n
		end
	end)

	----------------------------------------------------------------- 2D helpers
	-- The handoff's radial gradients, in a UI that only has linear ones. A bright
	-- centre falling to nothing is N concentric rounded frames: the centre is
	-- covered by every layer and the rim by one, and that is the falloff.
	local function radialStack(parent, colour, w, h, layers, peak, z)
		local holder = new("Frame", {
			Name = "Radial", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(w, h), BackgroundTransparency = 1, ZIndex = z,
		}, parent)
		local per = perLayer(peak, layers)
		local list = {}
		for i = 1, layers do
			local f = new("Frame", {
				Name = "L" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(i / layers, i / layers), BackgroundColor3 = colour,
				BackgroundTransparency = 1 - per, BorderSizePixel = 0, ZIndex = z,
			}, holder)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
			list[#list + 1] = f
		end
		return list
	end

	-- The vignette is the inverse shape, so it is four edge bars instead: each
	-- fades from rgba(3,4,4,0.55) at its own edge to nothing inward, and the
	-- corners double up on their own -- which is what a vignette does anyway.
	local function vignette(parent, z)
		local g = new("Frame", {
			Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z,
		}, parent)
		local bars = {}
		local edges = {
			{ UDim2.fromScale(1, 0.34), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), 270 },
			{ UDim2.fromScale(1, 0.34), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1), 90 },
			{ UDim2.fromScale(0.30, 1), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), 180 },
			{ UDim2.fromScale(0.30, 1), UDim2.fromScale(1, 0.5), Vector2.new(1, 0.5), 0 },
		}
		for _, e in ipairs(edges) do
			local bar = new("Frame", {
				Size = e[1], Position = e[2], AnchorPoint = e[3],
				BackgroundColor3 = Color3.fromRGB(3, 4, 4), BackgroundTransparency = 0,
				BorderSizePixel = 0, ZIndex = z,
			}, g)
			new("UIGradient", {
				Rotation = e[4],
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(1, 0.45),
				}),
			}, bar)
			bars[#bars + 1] = bar
		end
		return bars
	end

	----------------------------------------------------------------- shell build
	-- Generates the two halves the handoff splits, out of the egg we actually
	-- have: a one-cube-thick voxel shell in the authored egg's own colour and
	-- material (with a small deterministic per-cube shade jitter -- the clip's
	-- checkered voxel read), a dark inner wall so the open cradle reads hollow,
	-- and a floor so you cannot see out through the bottom. Everything comes
	-- back VISIBLE: since the voxel-from-idle change the cube egg IS the egg on
	-- stage from the first frame, its halves sitting flush until the split.
	local function buildHalves(topM, botM, a, b, c, u, colour, material)
		local made = {}
		local t = D.SHELL * u                       -- shell thickness, the handoff's 0.30
		local yLo = (D.SEAM_MID - D.SEAM_AMP) * u   -- bottom of the tooth band
		local yHi = (D.SEAM_MID + D.SEAM_AMP) * u   -- top of it
		local function mk(parent, name, size, cf, col, mat)
			local p = new("Part", {
				Name = name, Size = size, CFrame = cf, Color = col, Material = mat,
				Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
				CastShadow = false, TopSurface = Enum.SurfaceType.Smooth,
				BottomSurface = Enum.SurfaceType.Smooth, Transparency = 0,
			}, parent)
			made[#made + 1] = p
			return p
		end

		-- THE TIERS. Each is one disc whose radius follows the ellipsoid at its
		-- own mid-height, so the STEP between neighbours is the whole effect. They
		-- stop at the tooth band, because the band itself is the teeth.
		local function kAt(y)
			local ny = math.clamp(y / b, -1, 1)
			return math.sqrt(math.max(0, 1 - ny * ny))
		end
		local function tier(parent, name, y0, y1)
			local h = y1 - y0
			if h <= 1e-4 then return end
			local ym = (y0 + y1) / 2
			local k = kAt(ym)
			if k < 0.02 then return end
			local p = mk(parent, name, Vector3.new(2 * a * k, h, 2 * c * k),
				CFrame.new(0, ym, 0), colour, material)
			new("SpecialMesh", { MeshType = Enum.MeshType.Cylinder }, p)
		end
		if VOXEL_SHELL then
			-- One column per (x,z) cell, merged vertically into at most two boxes --
			-- one per half -- so the lattice reads chunky without paying a part per
			-- cube. Cells are dealt cap/cradle by the SAME seamOf() the authored
			-- decorations use, so the toothed seam falls out for free and shell and
			-- decoration can never disagree about which half they belong to.
			local CELL = (2 * b) / VOX_ROWS
			local NX = math.max(3, math.round((2 * a) / CELL))
			local NZ = math.max(3, math.round((2 * c) / CELL))
			local hue, sat, val = colour:ToHSV()
			local function vjit(ix, iz, k)
				local n = bit32.bxor(ix * 73856093, iz * 19349663, (k + 3) * 83492791)
				return bit32.band(bit32.rshift(n, 7), 1023) / 1023
			end
			-- 2026-08-15: THE PROFILE, not an ellipsoid. This block used to test
			-- (x/a)^2+(z/c)^2+(y/b)^2 <= 1, which builds a symmetric blob. The real
			-- egg -- voxel_egg.py, the recipe that matched the user's reference clip
			-- and now ReplicatedStorage.Modules.VoxelEgg -- has a WIDE FLAT BASE from
			-- a shallower lower exponent. The ceremony egg not matching the shop egg
			-- was the whole complaint; this is what fixes the silhouette.
			-- Returns the row's radius as a fraction of the widest row.
			local function profile(iy)
				local t = ((iy + 0.5) / VOX_ROWS) * 1.94 - 0.97
				local s = math.max(0, 1 - t * t) ^ (t > 0 and 0.5 or 0.36)
				return s * (1 - 0.14 * t)
			end
			for ix = 0, NX - 1 do
				for iz = 0, NZ - 1 do
					local x = (ix + 0.5 - NX / 2) * CELL
					local z = (iz + 0.5 - NZ / 2) * CELL
					-- +-0.4 cell wobble, so the silhouette is not a perfect ellipse
					local jit = (vjit(ix, iz, 11) - 0.5) * 0.8 * (CELL / math.max(a, c))
					local lo, hi
					for iy = 0, VOX_ROWS - 1 do
						local f = profile(iy) + jit
						if f > 0.02 and (x / (a * f)) ^ 2 + (z / (c * f)) ^ 2 <= 1 then
							lo = lo or iy
							hi = iy
						end
					end
					if lo then
						local cut = math.clamp(seamOf(math.atan2(z, x)) * u, yLo, yHi)
						local iCut = math.clamp(math.floor(cut / CELL + VOX_ROWS / 2), lo, hi + 1)
						local function emit(i0, i1, parent, nm)
							if i1 < i0 then return end
							local y0 = (i0 - VOX_ROWS / 2) * CELL
							local y1 = (i1 + 1 - VOX_ROWS / 2) * CELL
							local k = 1 + (vjit(ix, iz, i0) - 0.5) * 0.17
							mk(parent, nm, Vector3.new(CELL, y1 - y0, CELL),
								CFrame.new(x, (y0 + y1) / 2, z),
								Color3.fromHSV(hue, sat, math.clamp(val * k, 0, 1)), material)
						end
						emit(lo, iCut - 1, botM, "cradle_v" .. ix .. "_" .. iz)
						emit(iCut, hi, topM, "cap_v" .. ix .. "_" .. iz)
					end
				end
			end

			-- PEBBLES. Axis-aligned, never free-rotated: a rotated cube inside an
			-- otherwise grid-aligned voxel body pokes a CORNER out and reads as a flat
			-- tan sticky note stuck on the shell. Aligned and half-buried it reads as
			-- an embedded nugget. Outer face lands at (r + 0.35) cells.
			local PEB_N = 24
			local pebLt = Color3.fromRGB(216, 200, 156)
			local pebDk = Color3.fromRGB(168, 152, 112)
			for n = 1, PEB_N do
				local r1, r2, r3 = rand(n, 91), rand(n, 92), rand(n, 93)
				local iy = math.floor(VOX_ROWS * (0.10 + (r1 ^ 1.35) * 0.75))
				local f = profile(iy)
				if f > 0.20 then
					local ang = r2 * TAU
					local sz = CELL * (0.90 + r3 * 0.40)
					local rx = a * f + 0.35 * CELL - sz / 2
					local rz = c * f + 0.35 * CELL - sz / 2
					local y = (iy + 0.5 - VOX_ROWS / 2) * CELL
					local cut = math.clamp(seamOf(ang) * u, yLo, yHi)
					mk(y >= cut and topM or botM,
						(y >= cut and "cap_peb_" or "cradle_peb_") .. n,
						Vector3.new(sz, sz * (0.88 + r1 * 0.12), sz),
						CFrame.new(math.cos(ang) * rx, y, math.sin(ang) * rz),
						(r3 < 0.30) and pebDk or pebLt, material)
				end
			end
		else
		local step = 2 * b / TIERS
		local nBot = math.max(1, math.round((yLo + b) / step))
		local nTop = math.max(1, math.round((b - yHi) / step))
		for i = 0, nBot - 1 do
			tier(botM, "cradle_tier_" .. (i + 1),
				-b + (yLo + b) * (i / nBot), -b + (yLo + b) * ((i + 1) / nBot))
		end
		for i = 0, nTop - 1 do
			tier(topM, "cap_tier_" .. (i + 1),
				yHi + (b - yHi) * (i / nTop), yHi + (b - yHi) * ((i + 1) / nTop))
		end
		end

		-- THE TEETH, sampled at wedge EDGES rather than centres: 20 centres against
		-- 5 teeth all land where tri() is exactly +-0.5, which built every tooth at
		-- HALF the +-0.20 depth the handoff calls a must-keep. Edges hit 1/0/-1/0.
		-- the voxel lattice already spans the tooth band and is dealt by seamOf, so
		-- the separate wedge teeth would just double up inside it
		for j = 1, (VOXEL_SHELL and 0 or WEDGES) do
			local th = (j - 1) / WEDGES * TAU
			local cut = math.clamp(seamOf(th) * u, yLo, yHi)
			local dir = Vector3.new(math.cos(th), 0, math.sin(th))
			local tang = Vector3.new(-math.sin(th), 0, math.cos(th))
			local function tooth(parent, name, y0, y1)
				local h = y1 - y0
				if h <= 1e-4 then return end
				local ym = (y0 + y1) / 2
				local k = kAt(ym)
				local len = (TAU * ((a + c) / 2) * k) / WEDGES * 1.06
				local pos = Vector3.new(dir.X * (a * k - t / 2), ym, dir.Z * (c * k - t / 2))
				mk(parent, name, Vector3.new(t, h, len),
					CFrame.lookAt(pos, pos + tang, Vector3.yAxis), colour, material)
			end
			tooth(botM, "cradle_tooth_" .. j, yLo, cut)
			tooth(topM, "cap_tooth_" .. j, cut, yHi)
		end

		-- Dark inner lining, kept from the slab build: the cube shell is hollow
		-- already, but its far side seen through the opening would be
		-- shell-bright -- the wall ring and floor are what make the bowl read
		-- deep instead of solid, and the floor is what the pet stands on.
		local dark = Color3.fromRGB(13, 12, 9)          -- the handoff's interior #0D0C09
		local innerLo = yLo - 0.06 * b
		local ir = D.INNER_R
		for j = 1, WEDGES do
			local th = (j - 0.5) / WEDGES * TAU
			local dir = Vector3.new(math.cos(th), 0, math.sin(th))
			local tang = Vector3.new(-math.sin(th), 0, math.cos(th))
			local pos = Vector3.new(dir.X * a * ir, (yHi + innerLo) / 2, dir.Z * c * ir)
			mk(botM, "inner_wall_" .. j,
				Vector3.new(t * 0.6, yHi - innerLo, (TAU * ((a + c) / 2) * ir) / WEDGES * 1.08),
				CFrame.lookAt(pos, pos + tang, Vector3.yAxis), dark, Enum.Material.SmoothPlastic)
		end
		local floor = mk(botM, "inner_floor", Vector3.new(2 * a * ir, 0.10 * b, 2 * c * ir),
			CFrame.new(0, innerLo + 0.05 * b, 0), dark, Enum.Material.SmoothPlastic)
		new("SpecialMesh", { MeshType = Enum.MeshType.Cylinder }, floor)
		return made
	end

	----------------------------------------------------------------- the ceremony
	playReveal = function(result)
		-- Back-to-back safety: a second EggResult while a reveal is live skips the
		-- current one, then plays the new one straight after.
		if revealSkip then revealSkip() end
		revealGen += 1
		local myGen = revealGen

		-- RESTORE WHAT WAS THERE, do not assume the shop was open: a daily or
		-- season EGG REWARD fires this same remote with the panel shut.
		local shopWasVisible = frame.Visible

		-- Off the RESULT's own world: a hatch can land after the shell has been
		-- retargeted, and resolving it against the visible world would miss.
		local eggDef = EggConfig.GetEgg(EggConfig.WorldIdOfEgg(result.EggId) or WORLD_ID, result.EggId)
		local tier = tierByName[result.Rarity]
		local accent = (tier and tier.Color) or CF.ink
		local glowCol = deepen(accent)

		-- "HATCH ODDS 1 IN N" -- the handoff's own phrasing, computed from the SAME
		-- egg.Table the server rolled from, so published odds can never drift.
		local oddsText = "HATCH ODDS"
		if eggDef and eggDef.Table then
			local total, mine = 0, nil
			for _, row in ipairs(eggDef.Table) do
				total += (row[2] or 0)
				if row[1] == result.Name then mine = row[2] end
			end
			if mine and mine > 0 and total > 0 then
				oddsText = ("HATCH ODDS 1 IN %s"):format(comma(math.floor(total / mine + 0.5)))
			end
		end

		-- Platform.Viewport, not the raw camera (2026-08-26): identical live, and the
		-- only one of the two a device preview can drive -- see PlatformClient.fitPanels.
		local vpSize = Platform.Viewport
		-- The handoff is authored in CSS px on a full-screen stage; S maps that
		-- canvas onto whatever this device is, and every px below goes through it.
		local S = math.clamp(math.min(vpSize.X / 1280, vpSize.Y / 800), 0.62, 1.5)
		local narrow = (vpSize.X / math.max(1, vpSize.Y)) < D.NARROW_AT

		local root = new("Frame", {
			Name = "Hatch", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1,
		}, ensureRevealGui())

		local fades = {}   -- everything skip() dissolves, as {instance, property}
		local dead = false
		local conn, failsafeConns = nil, {}
		local canSkip = false

		------------------------------------------------------------ 2D: backdrop
		-- ONE FLAT OPAQUE FIELD, and nothing else behind the egg. Sampling the
		-- reference hatch at corners, edges and centre returns exactly RGB(10,8,13)
		-- every time: no vignette, no gradient, no glow, no blur. Its "glow" is
		-- free -- a bright model on flat black IS the contrast -- which is why the
		-- reference reads crisp while a stack of translucent layers reads muddy.
		local bg = new("Frame", {
			Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 8, 13),
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
		}, root)
		TweenService:Create(bg, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 0 }):Play()
		fades[#fades + 1] = { bg, "BackgroundTransparency" }

		-- THE STAGE SNAP, and deliberately ONE frame (2026-08-14). The reference
		-- clip's ground is not static: it sits near-black through the anticipation,
		-- SNAPS lit on the crack and ramps again through the reveal -- measured
		-- corner green 15 -> 35 -> 58.6. That beat is most of why the impact reads.
		-- The 84-frame sunburst that used to live here is still gone: this buys the
		-- brightness change without the fill-rate, driven by stageLit below.
		-- A FLAT fill was wrong. Measured, the reference's 58.6 average is bright rays
		-- against near-black GAPS; matching the average with an even wash matched the
		-- number and lost the contrast, so the stage just went green and the impact
		-- stopped reading. Banded falloff keeps the ground dark top and bottom and
		-- puts the light behind the egg, which is where the reference concentrates it.
		local snapGlow = new("Frame", {
			Name = "StageSnap", Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(88, 158, 92),
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2,
		}, root)
		local snapGrad = Instance.new("UIGradient")
		snapGrad.Rotation = 90
		snapGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.00, 1.00),
			NumberSequenceKeypoint.new(0.26, 0.62),
			NumberSequenceKeypoint.new(0.50, 0.00),
			NumberSequenceKeypoint.new(0.74, 0.62),
			NumberSequenceKeypoint.new(1.00, 1.00),
		})
		snapGrad.Parent = snapGlow

		-- THE FLASH (2026-08-15). Distinct from StageSnap, and it has to be: the
		-- reference's 2.20 beat is a HARD luma spike -- measured 200 -> 252 in a
		-- single frame -- while stageLit is an exponentially DAMPED approach and by
		-- construction cannot snap. StageSnap gives the sustained stage brightening;
		-- it can never give the impact. This frame is the impact.
		--
		-- It is UI, not a Light, on purpose: this ceremony renders in a ViewportFrame
		-- and ViewportFrames draw BaseParts only -- a PointLight parented in here
		-- "drew nothing, ever". A full-screen frame over the viewport is the only way
		-- a flash can exist on this surface at all.
		--
		-- Near-white, barely tinted by the tier: the reference spike is essentially
		-- white, and pushing it to the rarity colour turned the impact into a wash.
		local flashFrame = new("Frame", {
			Name = "HatchFlash", Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1):Lerp(accent, 0.12),
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 11,
		}, root)
		fades[#fades + 1] = { flashFrame, "BackgroundTransparency" }

		-- NO RADIAL GLOW. The 10-layer stack was ten full-screen-ish translucent
		-- frames composited for the whole ceremony, and it raised the visual floor
		-- so nothing later could read as an impact. Kept as an empty list so the
		-- shake beat's fade loop stays valid and this stays a one-line revert.
		local glowLayers, glowLit = {}, 0

		-- NO SUNBURST AND NO VIGNETTE. Between them they were 84 large translucent
		-- frames (16 arms x 5 overlapping bands, plus 4 edge bars) composited over
		-- the whole screen for the entire ceremony -- the single biggest fill-rate
		-- cost here, and the reference hatch has neither. A rotating fan also never
		-- lets the stage go quiet, and the reference's impact works precisely
		-- BECAUSE it interrupts a dead-still frame.
		--
		-- `fan` and `rays` stay declared: the per-frame driver spins the fan and the
		-- split beat recolours the rays, and both are written to tolerate nil/empty
		-- so this remains one edit to undo.
		local fan, rays = nil, {}

		------------------------------------------------------------ 3D: the stage
		local eggVp = new("ViewportFrame", {
			Name = "Stage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			-- The handoff's three-light rig, in the only lighting a ViewportFrame
			-- has: Ambient carries the hemisphere plus the #E6ECFF fill, and
			-- LightColor/LightDirection are the white key from (2.0, 3.0, 4.6).
			-- brighter than a straight read of the hemisphere: the handoff's rig sums
			-- to well over full white (0.85 + 1.75 + 0.75) and a ViewportFrame's key
			-- caps at white, so the surplus has to land in Ambient or dark pets --
			-- the wooden ones especially -- come out as silhouettes in the cradle
			Ambient = Color3.fromRGB(178, 181, 172), LightColor = Color3.fromRGB(255, 255, 255),
			LightDirection = -Vector3.new(2.0, 3.0, 4.6).Unit, ZIndex = 5,
		}, root)
		local baseAmbient = eggVp.Ambient
		fades[#fades + 1] = { eggVp, "ImageTransparency" }
		local eggCam = new("Camera", { FieldOfView = narrow and D.FOV_NARROW or D.FOV }, eggVp)
		eggVp.CurrentCamera = eggCam

		local u, us, a, b, c = 1, 1, 0.94, 1.24, 0.94   -- u: the shell map, us: the scene map
		local intactShell, intactRest, coreOrb, coreHalo, coreBase
		local topM, botM, petM = nil, nil, nil
		local petBase, petYaw, petScaleNow, petLift = 1, 0, -1, 0
		local petFixed = false   -- one-shot live correction, see the reveal block below
		local chunks, capParts, genParts, petParts = {}, {}, {}, {}
		local eggReady = false

		local master = eggDef and eggDef.Model and eggMaster(eggDef.Model)
		if master then
			local egg = master:Clone()
			for _, d in ipairs(egg:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored, d.CanCollide, d.CanQuery, d.CastShadow = true, false, false, false
				end
			end
			local shell = egg:FindFirstChild("shell_body_1") or egg.PrimaryPart
			-- Centre the shell on the origin: every transform below is expressed
			-- about the egg's own centre, exactly as the handoff's scene is.
			egg:PivotTo(egg:GetPivot() + (Vector3.zero - (shell and shell.Position or egg:GetPivot().Position)))

			if shell then
				a, b, c = shell.Size.X / 2, shell.Size.Y / 2, shell.Size.Z / 2
			else
				local ext = egg:GetExtentsSize()
				a, b, c = ext.X / 2, ext.Y / 2, ext.Z / 2
			end
			u = b / D.RY
			us = sceneScale(egg, eggCam.FieldOfView, vpSize.X / math.max(1, vpSize.Y))

			topM = new("Model", { Name = "Cap" }, eggVp)
			botM = new("Model", { Name = "Cradle" }, eggVp)

			genParts = buildHalves(topM, botM, a, b, c, u,
				shell and shell.Color or Color3.fromRGB(255, 253, 246),
				shell and shell.Material or Enum.Material.SmoothPlastic)

			-- THE AUTHORED DECORATIONS, dealt to the two halves along the seam and
			-- CUT where they straddle it. Reverted from the cube-refill (user's
			-- reference videos, 2026-08-14): the reference egg's surface art is a
			-- handful of BIG round spots, and our authored decorations already ARE
			-- chunky parts of exactly that kind -- refilling them with 0.18 cubes
			-- made them mushy and added several hundred parts per hatch to say the
			-- same thing. Only unmeshed blocks standing on world Y are cut; anything
			-- else goes whole by its centre, because resizing a part that carries a
			-- mesh would deform the mesh with it.
			local loose = {}
			for _, d in ipairs(egg:GetDescendants()) do
				if d:IsA("BasePart") and d ~= shell then loose[#loose + 1] = d end
			end
			for _, part in ipairs(loose) do
				local p = part.Position
				local cut = seamOf(math.atan2(p.Z, p.X)) * u
				local half = part.Size.Y / 2
				local upright = part.CFrame.UpVector:Dot(Vector3.yAxis) > 0.98
				if upright and #part:GetChildren() == 0
					and cut > p.Y - half + 0.02 and cut < p.Y + half - 0.02 then
					local hiH = (p.Y + half) - cut
					local loH = cut - (p.Y - half)
					local upper = part:Clone()
					upper.Size = Vector3.new(part.Size.X, hiH, part.Size.Z)
					upper.CFrame = part.CFrame * CFrame.new(0, (part.Size.Y - hiH) / 2, 0)
					upper.Parent = topM
					part.CFrame = part.CFrame * CFrame.new(0, -(part.Size.Y - loH) / 2, 0)
					part.Size = Vector3.new(part.Size.X, loH, part.Size.Z)
					part.Parent = botM
				elseif p.Y > cut then
					part.Parent = topM
				else
					part.Parent = botM
				end
			end
			egg:Destroy()

			-- The core, standing in for the handoff's point light (deviation 2). A
			-- SMALL, translucent neon ball wrapped in a much fainter halo: the first
			-- cut was a*1.15 across at near-full opacity and, once the shell opened
			-- around it, read as a solid billiard ball sitting in the egg rather than
			-- as light getting out. A light is not an object -- the halo is what sells
			-- it, and the 2D radial glow behind the stage carries the rest.
			coreBase = a * 0.52
			coreOrb = new("Part", {
				Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.new(coreBase, coreBase, coreBase),
				Color = accent, Material = Enum.Material.Neon, Transparency = 1,
				Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false,
			}, eggVp)
			coreHalo = new("Part", {
				Name = "CoreHalo", Shape = Enum.PartType.Ball,
				Size = Vector3.new(coreBase, coreBase, coreBase) * 2.3,
				Color = accent, Material = Enum.Material.Neon, Transparency = 1,
				Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false,
			}, eggVp)

			-- SEVEN RIGID CHUNKS, one per 51.4-degree sector, cut now while
			-- everything still sits at identity so each chunk's pivot is exactly
			-- the handoff's (cos t * 0.45, 0.4, sin t * 0.45). Rigidity is the
			-- single most important detail of the burst -- scattering the parts
			-- individually reads as confetti and is wrong -- so a chunk is a Model
			-- moved by ONE PivotTo, never a bag of parts moved one at a time.
			-- Cutting them up front also lets the pre-burst beats drive the same
			-- seven models as one cap, with an identity chunk transform.
			local isGen = {}
			for _, p in ipairs(genParts) do isGen[p] = true end
			for s = 0, D.SECT - 1 do
				local ang = (s + 0.5) / D.SECT * TAU - math.pi
				local piv = Vector3.new(math.cos(ang) * D.BURST_R, D.BURST_H, math.sin(ang) * D.BURST_R) * us
				chunks[#chunks + 1] = {
					model = new("Model", { Name = "Chunk" .. (s + 1) }, topM),
					pivot = piv, home = CFrame.new(piv),
					vel = Vector3.new(math.cos(ang) * (0.75 + rand(s, 41) * 0.5),
						1.15 + rand(s, 43) * 0.7,
						math.sin(ang) * (0.75 + rand(s, 47) * 0.5)) * us,
					spin = Vector3.new((rand(s, 53) - 0.5) * 1.7, (rand(s, 59) - 0.5) * 1.7,
						(rand(s, 61) - 0.5) * 1.7),
				}
			end
			for _, d in ipairs(topM:GetDescendants()) do
				if d:IsA("BasePart") then
					local ang = math.atan2(d.Position.Z, d.Position.X)
					local s = math.min(D.SECT, math.floor((ang + math.pi) / TAU * D.SECT) + 1)
					-- base transparency = what this part shows once the split has
					-- happened; the burst fade drives every one of them from it
					capParts[#capParts + 1] = { d, isGen[d] and 0 or d.Transparency }
					d.Parent = chunks[s].model
				end
			end
			for _, ck in ipairs(chunks) do ck.model.WorldPivot = ck.home end
			botM.WorldPivot = CFrame.new()
			eggReady = true
		end

		-- The pet. Re-pivoted onto its own feet, so the rise and the grow both
		-- happen from the floor of the cradle, and yawed to the angle BrainrotThumb
		-- frames pets from, so the side the game shows everywhere else is the side
		-- that faces this camera.
		--
		-- SIZED AGAINST THE SHELL (u), NOT THE FRAME (us) -- the one place the two
		-- maps must not be swapped. The handoff's pet is 0.95 tall in an egg that is
		-- 2.48 tall, i.e. 38% of the egg, and in the reference clip it reads as about
		-- a third of the cradle's width with its head a little over the rim. The
		-- handoff's egg is bare, so its egg IS its shell; ours are not, and taking
		-- that 38% against the whole model -- spikes, crowns, halos and all -- made
		-- the pet 61% of the SHELL and left it wearing the cradle rather than
		-- sitting in it. The shell is the thing that has to hold the pet, so the
		-- shell is what it is measured against.
		local petSrc = eggReady and petMaster(result.Name, result.PetId) or nil
		if petSrc then
			petM = petSrc:Clone()
			for _, d in ipairs(petM:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored, d.CanCollide, d.CanQuery = true, false, false
					-- remember what it was: a pet with a deliberately translucent
					-- part must not be flattened to solid when it goes visible
					petParts[#petParts + 1] = { d, d.Transparency }
					d.Transparency = 1
				end
			end
			-- FIT ON HEIGHT *AND* FOOTPRINT. The handoff says the pet should "fill
			-- roughly the same volume (about 0.95 units tall at final scale)", and for
			-- its placeholder rooster those are one sentence -- it is taller than it
			-- is wide, so its height IS its largest dimension. Ten of our fifteen pets
			-- are not: Moss Larva is a caterpillar, Sap Snail a shell on its side.
			--
			-- Fitting height alone scaled those up until their LENGTH sprawled well
			-- past the cradle. Fitting the largest dimension alone fixed the sprawl
			-- and created the opposite fault: a long, flat pet came out so short it
			-- sat below the rim and the reveal had nothing to show.
			--
			-- So the fit is against whichever of the two BINDS: the model's height, or
			-- 0.62 of its footprint. A tall pet is height-bound and lands on the
			-- handoff's number exactly; a long one is footprint-bound and comes out
			-- about as long as the cradle is wide, which still leaves it standing
			-- clear of the rim.
			local ext = petM:GetExtentsSize()
			local fit = math.max(ext.Y, 0.62 * math.max(ext.X, ext.Z))
			petBase = petM:GetScale()
			if fit > 0.01 then
				petBase = petBase * ((D.PET_H / (D.PET_S + D.PET_DS)) * u / fit)
				petM:ScaleTo(petBase)
			end
			-- HIGHER THAN THE HANDOFF'S FLOOR (user, 2026-08-13: "the pets are
			-- blocked by the egg -- the pet needs to appear higher"). The handoff
			-- ends the rise with the feet on the cradle floor, which its BARE egg
			-- could afford. Ours cannot: the full-depth front teeth already reach
			-- +0.15u, and the authored decorations dealt to the cradle stand far
			-- taller still on some eggs (Hollow's band crosses the front right at
			-- pet height). So the cradle's REAL front silhouette is measured --
			-- the tallest cradle part whose footprint crosses the camera-facing
			-- centre strip AND is actually wall-like: opaque and at least half
			-- the cradle's radius wide. Both guards are load-bearing -- Mossy
			-- carries a half-clear glow ray and Reedwater a lone thin reed stalk
			-- across the front strip, 0.5-0.9u tall, and counting those as walls
			-- pinned the rise at its cap with the pet hovering in mid-air above
			-- the whole egg. A glow and a reed hide nothing; the rim does. The
			-- generated teeth fail the width guard individually, which is fine:
			-- frontTop STARTS at the rim line they top out at. The rise then ends
			-- with only ~15% of the pet's own
			-- final height behind it, whatever the egg and whatever the pet's
			-- shape. Capped so a freak decoration cannot fire the pet into the
			-- sky, floored at the handoff's own resting height so a low-walled
			-- egg keeps the design's nestled look. petLift rides petUp's damped
			-- ramp, so the motion stays one continuous rise.
			local petClearH = D.PET_H * (fit > 0.01 and math.min(1, ext.Y / fit) or 1)
			-- WHY THE WIDTH GUARD IS GONE (2026-08-14). The scan used to require a part at
			-- least half the egg's radius wide before it counted as a wall. The voxel shell's
			-- cells are one CELL wide and the generated teeth are thinner still, so NOTHING
			-- passed and frontTop never left its seam-constant baseline of 0.15u. That is why
			-- raising the cap did nothing: the cap was never the binding constraint, the
			-- measurement was. Measured live, the pet's bottom sat 0.5 BELOW the cradle's top.
			-- Opacity is still guarded, which is what actually excluded Mossy's half-clear
			-- glow ray; the width test was only ever protecting against Reedwater's thin reed
			-- stalk, and over-lifting by a stalk's height is far better than burying the pet.
			local frontTop = (D.SEAM_MID + D.SEAM_AMP) * u
			if botM then
				for _, p in ipairs(botM:GetDescendants()) do
					if p:IsA("BasePart") and p.Transparency < 0.4 then
						frontTop = math.max(frontTop, p.Position.Y + p.Size.Y / 2)
					end
				end
			end
			-- RAISED AGAIN (owner: "raise it up higher dude"). 12% nestled still read as
			-- sitting down in the bowl, so the feet now clear the cradle's real top by 10%
			-- of the pet's own height -- the pet is presented ABOVE the shell rather than
			-- seated in it. Cap 2.0 so the tall decorated eggs can still reach it.
			petLift = math.max(0,
				math.min(2.0, frontTop / u + 0.10 * petClearH) - (D.PET_Y + D.PET_DY))
			local box, size = petM:GetBoundingBox()
			petM.WorldPivot = CFrame.new(box.Position.X, box.Position.Y - size.Y / 2, box.Position.Z)
			petM:PivotTo(CFrame.new())

			-- UNIT-MAP SAFETY NET, and the reason the last two lift fixes did not land.
			-- petLift is computed in handoff units against the SHELL map (u), but the cradle
			-- is laid out on the SCENE map -- this file's own header calls mixing the two
			-- load-bearing, and measured live the pet still came out 96% of its height BELOW
			-- the rim even after the cap and the target were both raised. Rather than chase
			-- the conversion, place the pet at its computed offset ONCE, measure the real gap
			-- against the cradle, and fold the shortfall straight back into the lift. Feet end
			-- up a clear 10% of the pet's own height above the cradle's true top, whatever
			-- either unit map is doing.
			if botM then
				petM:PivotTo(CFrame.new(0, (D.PET_Y + (D.PET_DY + petLift)) * u, 0))
				local pcf2, psz2 = petM:GetBoundingBox()
				local bcf2, bsz2 = botM:GetBoundingBox()
				local want = bcf2.Position.Y + bsz2.Y / 2 + 0.10 * psz2.Y
				local have = pcf2.Position.Y - psz2.Y / 2
				if want > have then petLift += (want - have) / math.max(u, 1e-3) end
				petM:PivotTo(CFrame.new())
			end
			-- The pet is the AUTHORED model, not a voxel replica (user's reference
			-- videos, 2026-08-14). The reference game's rooster is about a dozen
			-- chunky boxes -- a head, two square eyes, a beak, a comb -- and our pets
			-- are already built that way. Rebuilding them as a ~10-row cube lattice
			-- destroyed exactly the crisp features that make them read, and cost
			-- hundreds of parts to do it.
			-- FACE THE PLAYER (owner, 2026-08-14: "the pets face should always face the
			-- screen"). This used BrainrotThumb.DEFAULT_DIR, which is (0.9, 0.45, -1) --
			-- the front-quarter the THUMBNAIL cameras sit on, at -Z. The ceremony camera
			-- sits at +Z (D.CAM_Z = 7.6) and looks the other way, so borrowing that yaw
			-- turned every hatched pet ~138 degrees away and showed the player its back
			-- at the one moment the reveal exists to show the thing off.
			-- PER-PET FACING (2026-08-14, owner: "the pets face should always face the
			-- screen"). THERE IS NO SINGLE CORRECT YAW HERE. Measured across all 191 models,
			-- the direction a pet actually faces is spread over the whole circle: only 45%
			-- land within +-45 deg of the median, and the best single signal available
			-- (PrimaryPart's LookVector) agrees for just 61%. Three different constants were
			-- tried -- DEFAULT_DIR's yaw, a +Z yaw, and DEFAULT_DIR + pi -- and every one was
			-- wrong for most pets, which is what "facing away" then "that's a profile" were
			-- both reporting. A constant cannot solve this; the models disagree with it.
			--
			-- So facing is MEASURED on the model itself, best signal first:
			--   named eye parts (truest) -> HeadAttachment's offset from centre -> pivot.
			-- Measured BEFORE the pivot is reset below, so it reads the authored transform.
			-- A facing at angle phi rotated by -phi lands on +Z, which is where the ceremony
			-- camera sits (D.CAM_Z = 7.6).
			local function petFacing(model)
				local bcf, bsz = model:GetBoundingBox()
				local centre = bcf.Position
				-- relative threshold: these models differ hugely in scale, and a head sitting
				-- straight on top of the body has a near-zero XZ offset whose .Unit is noise
				local minXZ = 0.08 * math.max(bsz.X, bsz.Z)
				local sum, n = Vector3.zero, 0
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") and p.Name:lower():find("eye") then
						sum += p.Position
						n += 1
					end
				end
				if n > 0 then
					local d = sum / n - centre
					d = Vector3.new(d.X, 0, d.Z)
					if d.Magnitude > minXZ then return d.Unit end
				end
				for _, a in ipairs(model:GetDescendants()) do
					if a:IsA("Attachment") and a.Name == "HeadAttachment" then
						local d = a.WorldPosition - centre
						d = Vector3.new(d.X, 0, d.Z)
						if d.Magnitude > minXZ then return d.Unit end
					end
				end
				local lv = model:GetPivot().LookVector
				local d = Vector3.new(lv.X, 0, lv.Z)
				return (d.Magnitude > 0.01) and d.Unit or Vector3.new(0, 0, 1)
			end
			-- The +pi is MEASURED, not assumed. With plain -atan2 the posed pet came back at
			-- dot(toCamera) = -1.000 exactly -- perfectly backwards -- so the sign convention
			-- here is the opposite of the one the derivation assumed. Half a turn corrects it,
			-- and because the facing is now per-model this holds for every pet, not just one.
			local fdir = petFacing(petM)
			petYaw = -math.atan2(fdir.X, fdir.Z) + math.pi
			petM.Parent = eggVp
		end

		------------------------------------------------------------ 2D: captions
		local function caption(name, text, size, anchorY, posY, colour, z)
			local l = new("TextLabel", {
				Name = name, AnchorPoint = Vector2.new(0.5, anchorY), Position = UDim2.fromScale(0.5, posY),
				Size = UDim2.new(0.9, 0, 0, math.floor(size * 1.5)), BackgroundTransparency = 1,
				Font = FONT, TextSize = size, TextColor3 = colour, Text = text, ZIndex = z,
			}, root)
			local ink = UITheme.inkText(l, math.max(2, size * 0.16))
			fades[#fades + 1] = { l, "TextTransparency" }
			fades[#fades + 1] = { ink, "Transparency" }
			return l, ink
		end

		local tapCap, tapInk = caption("TapPrompt", "TAP TO HATCH!", math.floor(38 * S), 1, 0.92,
			Color3.new(1, 1, 1), 12)
		local tapSub = new("TextLabel", {
			Name = "TapSub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.925),
			Size = UDim2.new(0.9, 0, 0, math.floor(16 * S)), BackgroundTransparency = 1,
			Font = Enum.Font.Code, TextSize = math.floor(11 * S), TextColor3 = Color3.new(1, 1, 1),
			TextTransparency = 0.6,
			Text = spaced(((eggDef and eggDef.Name) or "MYSTERY EGG") .. " \u{00B7} 1 OF 1"), ZIndex = 12,
		}, root)
		fades[#fades + 1] = { tapSub, "TextTransparency" }

		local qCap = caption("Cracking", "???", math.floor(40 * S), 1, 0.88, Color3.new(1, 1, 1), 12)
		qCap.Visible = false

		local chipHolder = new("Frame", {
			Name = "Chip", Position = UDim2.fromOffset(math.floor(28 * S), math.floor(26 * S)),
			Size = UDim2.fromOffset(math.floor(240 * S), math.floor(30 * S)),
			BackgroundTransparency = 1, ZIndex = 12,
		}, root)
		local chipBox = new("Frame", {
			Size = UDim2.fromOffset(math.floor(30 * S), math.floor(30 * S)),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = alpha(0x14),
			BorderSizePixel = 0, ZIndex = 12,
		}, chipHolder)
		new("UICorner", { CornerRadius = UDim.new(0, math.floor(9 * S)) }, chipBox)
		new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = alpha(0x24) }, chipBox)
		local chipLbl = new("TextLabel", {
			Position = UDim2.fromOffset(math.floor(40 * S), 0), Size = UDim2.new(1, -math.floor(40 * S), 1, 0),
			BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = math.floor(10 * S),
			TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.58,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = spaced(petsOwned and ("PETS \u{00B7} " .. petsOwned)
				or ((eggDef and eggDef.Name) or "MYSTERY EGG")), ZIndex = 12,
		}, chipHolder)
		fades[#fades + 1] = { chipBox, "BackgroundTransparency" }
		fades[#fades + 1] = { chipLbl, "TextTransparency" }

		------------------------------------------------------------ input + skip
		-- The handoff sinks input for the whole sequence: the catcher stays Active
		-- so stray clicks are SWALLOWED rather than passed through to the world.
		-- Below the card (ZIndex 17) on purpose -- at 20 it ate its own buttons.
		local catcher = new("TextButton", {
			Name = "Catcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Text = "", AutoButtonColor = false, ZIndex = 6,
		}, root)

		frame.Visible = false   -- hide the shop panel behind the ceremony

		-- NO BLUR. A full-screen BlurEffect is a per-pixel post-process pass over
		-- the whole framebuffer every frame, and it was buying nothing: the stage
		-- above is opaque, so there is no longer anything behind to compete with.
		-- Neither reference game blurs anything, ever -- not for its hatch and not
		-- behind its shop panels, where the world stays razor sharp. It also softens
		-- exactly the hard block edges that sell the chunky look. skip() already
		-- tests `blur` before touching it, so nil is a supported value here.
		local blur = nil

		-- world input during a cutscene: the "E / Open" prompt renders in 3D and
		-- would draw straight over the egg
		local prompts = game:GetService("ProximityPromptService")
		prompts.Enabled = false

		-- "Nothing else in the frame is part of this sequence."
		local StarterGui = game:GetService("StarterGui")
		local myGui = root.Parent
		local hiddenGuis = {}
		for _, g in ipairs(myGui.Parent:GetChildren()) do
			if g:IsA("ScreenGui") and g ~= myGui and g.Enabled then
				g.Enabled = false
				hiddenGuis[#hiddenGuis + 1] = g
			end
		end
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
		-- SetCoreGuiEnabled does NOT cover the topbar; it needs its own SetCore call
		pcall(function() StarterGui:SetCore("TopbarEnabled", false) end)

		local function skip()
			if dead then return end
			dead = true
			revealGen += 1
			if revealSkip == skip then revealSkip = nil end
			if conn then conn:Disconnect(); conn = nil end
			for _, cn in ipairs(failsafeConns) do pcall(function() cn:Disconnect() end) end
			table.clear(failsafeConns)
			catcher.Active = false
			prompts.Enabled = true
			for _, g in ipairs(hiddenGuis) do
				if g.Parent then g.Enabled = true end
			end
			pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
			pcall(function() StarterGui:SetCore("TopbarEnabled", true) end)
			if blur then
				local dying = blur
				blur = nil
				TweenService:Create(dying, TweenInfo.new(FADE_TIME), { Size = 0 }):Play()
				task.delay(FADE_TIME + 0.05, function() dying:Destroy() end)
			end
			for _, f in ipairs(fades) do
				TweenService:Create(f[1], TweenInfo.new(FADE_TIME), { [f[2]] = 1 }):Play()
			end
			frame.Visible = shopWasVisible
			task.delay(FADE_TIME, function()
				if root then root:Destroy(); root = nil end
			end)
		end
		revealSkip = skip

		-- FAILSAFE. Everything above hid EVERY ScreenGui, ALL CoreGui and the
		-- topbar, and skip() is the only thing that puts them back -- so a death, a
		-- disconnect or an error anywhere in the staged animation must still reach
		-- it. Three belts, all idempotent (skip() early-returns once `dead`).
		table.insert(failsafeConns, player.CharacterRemoving:Connect(function() skip() end))
		do
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then table.insert(failsafeConns, hum.Died:Connect(function() skip() end)) end
		end
		task.delay(REVEAL_FAILSAFE, function()
			if not dead then
				warn("[EggShop] hatch failsafe fired after " .. REVEAL_FAILSAFE .. "s -- restoring the HUD")
				skip()
			end
		end)

		------------------------------------------------------------ state
		local phase = "idle"
		local t, spinY = 0, 0
		local shake, open, glow, petUp, lift, burstT = 0, 0, 0, 0, 0, 0
		local stageLit = 0
		local camZ = D.CAM_Z

		local function tween(o, secs, props, style, dir, delay)
			return TweenService:Create(o, TweenInfo.new(secs, style or Enum.EasingStyle.Quad,
				dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
		end

		------------------------------------------------------------ split beat, 2D
		local function splitBurstUI()
			-- White flash at the seam (46% of viewport height): 300px, white ->
			-- #FFF8D6 -> transparent, scaling 0.15 -> 1.1 -> 2.8 as it fades, 700ms.
			local flash = new("Frame", {
				Name = "Flash", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46),
				Size = UDim2.fromOffset(300 * S, 300 * S), BackgroundColor3 = Color3.fromRGB(255, 248, 214),
				BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 14,
			}, root)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, flash)
			local core = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.55, 0.55), BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 14,
			}, flash)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, core)
			local fs = new("UIScale", { Scale = 0.15 }, flash)
			tween(fs, 0.07, { Scale = 1.1 }):Play()
			tween(flash, 0.07, { BackgroundTransparency = 0.15 }):Play()
			tween(core, 0.07, { BackgroundTransparency = 0 }):Play()
			task.delay(0.07, function()
				if myGen ~= revealGen or not flash.Parent then return end
				tween(fs, 0.63, { Scale = 2.8 }):Play()
				tween(flash, 0.63, { BackgroundTransparency = 1 }):Play()
				tween(core, 0.63, { BackgroundTransparency = 1 }):Play()
			end)
			task.delay(0.75, function() if flash then flash:Destroy() end end)

			-- rarity ring, same origin: 280px, a 5px border, 0.4 -> 2.6 fading out
			local ring = new("Frame", {
				Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46),
				Size = UDim2.fromOffset(280 * S, 280 * S), BackgroundTransparency = 1, ZIndex = 14,
			}, root)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
			local rs = new("UIStroke", { Color = accent, Thickness = 5 * S, Transparency = 0.05 }, ring)
			local rsc = new("UIScale", { Scale = 0.4 }, ring)
			tween(rsc, 0.7, { Scale = 2.6 }):Play()
			tween(rs, 0.7, { Transparency = 1 }):Play()
			task.delay(0.75, function() if ring then ring:Destroy() end end)

			-- NO LIGHT SHAFT. Three more translucent strips growing across the stage,
			-- on the exact frame the flash and the ring are already carrying the beat.
			-- The reference's entire split budget is a flash, two hollow rings and
			-- some opaque debris -- everything else is subtraction.

			-- the sunburst takes the rarity glow, 600ms crossfade
			for _, ray in ipairs(rays) do
				ray.BackgroundColor3 = glowCol
				tween(ray, 0.6, { BackgroundTransparency = alpha(0xcc) }):Play()
			end
		end

		------------------------------------------------------------ reveal, 2D
		local function revealUI()
			-- NEW badge: 42px in #FFE45C with a gold glow, top 6%, popping in at
			-- 200ms -- scale 0 -> 1.25 -> 1 with a slight rotate, over 520ms
			local badge, badgeInk = caption("NewBadge", "NEW", math.floor(42 * S), 0, 0.06,
				Color3.fromRGB(255, 228, 92), 16)
			badgeInk.Color = Color3.fromRGB(120, 78, 0)
			local bs = new("UIScale", { Scale = 0 }, badge)
			badge.Rotation = -14
			task.delay(0.2, function()
				if myGen ~= revealGen or not badge.Parent then return end
				tween(bs, 0.31, { Scale = 1.25 }, Enum.EasingStyle.Back):Play()
				tween(badge, 0.31, { Rotation = 6 }, Enum.EasingStyle.Back):Play()
				task.delay(0.31, function()
					if myGen ~= revealGen or not badge.Parent then return end
					tween(bs, 0.21, { Scale = 1 }):Play()
					tween(badge, 0.21, { Rotation = -3 }):Play()
				end)
			end)

			-- Reveal card: bottom 3%, 460 wide (max 92%), 18 radius, sliding up
			-- 46px and fading in over 420ms after a 300ms delay.
			local cardW = math.min(460 * S, vpSize.X * 0.92)
			local cardH = math.floor(196 * S)
			local holder = new("Frame", {
				Name = "CardHolder", AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 0.97, 46 * S), Size = UDim2.fromOffset(cardW, cardH),
				BackgroundTransparency = 1, ZIndex = 17,
			}, root)
			local card = new("Frame", {
				Name = "Card", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(9, 12, 10),
				BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 17,
			}, holder)
			new("UICorner", { CornerRadius = UDim.new(0, math.floor(18 * S)) }, card)
			local cardStroke = new("UIStroke", { Color = accent, Thickness = 2 * S, Transparency = 1 }, card)
			fades[#fades + 1] = { card, "BackgroundTransparency" }
			fades[#fades + 1] = { cardStroke, "Transparency" }

			-- the handoff's inner rarity glow (inset 0 0 40px at 0x33 alpha): one
			-- gradient frame per axis, visible only near its own pair of edges --
			-- the vignette's trick turned inward and accent-tinted. The 60px-blur
			-- DROP shadow is deliberately absent: Frames cannot blur, and against
			-- the near-black stage a hard un-blurred slab is all it could add.
			local glowSeq = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.80),
				NumberSequenceKeypoint.new(0.32, 1),
				NumberSequenceKeypoint.new(0.68, 1),
				NumberSequenceKeypoint.new(1, 0.80),
			})
			local innerGlow1, innerGlow2
			for i, rot in ipairs({ 0, 90 }) do
				local g = new("Frame", {
					Name = "InnerGlow" .. i, Size = UDim2.fromScale(1, 1), BackgroundColor3 = accent,
					BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 17,
				}, card)
				new("UICorner", { CornerRadius = UDim.new(0, math.floor(18 * S)) }, g)
				new("UIGradient", { Rotation = rot, Transparency = glowSeq }, g)
				fades[#fades + 1] = { g, "BackgroundTransparency" }
				if i == 1 then innerGlow1 = g else innerGlow2 = g end
			end
			local slide = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.3)
			TweenService:Create(holder, slide, { Position = UDim2.new(0.5, 0, 0.97, 0) }):Play()
			TweenService:Create(card, slide, { BackgroundTransparency = 0.06 }):Play()
			TweenService:Create(cardStroke, slide, { Transparency = alpha(0x66) }):Play()

			local nameL = new("TextLabel", {
				Name = "PetName", AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, math.floor(14 * S)),
				Size = UDim2.new(1, -math.floor(24 * S), 0, math.floor(34 * S)),
				BackgroundTransparency = 1, Font = FONT, TextSize = math.floor(30 * S),
				TextColor3 = Color3.new(1, 1, 1), TextTruncate = Enum.TextTruncate.AtEnd,
				Text = tostring(result.Name or "???"), ZIndex = 18,
			}, card)
			local nameInk = UITheme.inkText(nameL, 3)
			fades[#fades + 1] = { nameL, "TextTransparency" }
			fades[#fades + 1] = { nameInk, "Transparency" }

			local chip = new("TextLabel", {
				Name = "RarityChip", AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, math.floor(52 * S)),
				Size = UDim2.fromOffset(math.floor(190 * S), math.floor(24 * S)),
				BackgroundColor3 = glowCol, BackgroundTransparency = alpha(0x2e),
				Font = Enum.Font.Code, TextSize = math.floor(11 * S), TextColor3 = accent,
				Text = spaced(tostring(result.Rarity or "?")), ZIndex = 18,
			}, card)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, chip)
			local chipStroke = new("UIStroke", {
				Color = accent, Thickness = 1.5 * S, Transparency = alpha(0x80),
			}, chip)
			fades[#fades + 1] = { chip, "BackgroundTransparency" }
			fades[#fades + 1] = { chip, "TextTransparency" }
			fades[#fades + 1] = { chipStroke, "Transparency" }

			local odds = new("TextLabel", {
				Name = "Odds", AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, math.floor(82 * S)),
				Size = UDim2.new(1, -math.floor(24 * S), 0, math.floor(16 * S)),
				BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = math.floor(10 * S),
				TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0.55, Text = oddsText, ZIndex = 18,
			}, card)
			fades[#fades + 1] = { odds, "TextTransparency" }

			local pad, gapX = math.floor(14 * S), math.floor(10 * S)
			local btnH = math.floor(38 * S)
			local btnY = cardH - pad - btnH
			local function button(x, w, fill, fillA, border, borderA, textCol, label)
				local btn = new("TextButton", {
					Name = label, Position = UDim2.fromOffset(x, btnY), Size = UDim2.fromOffset(w, btnH),
					BackgroundColor3 = fill, BackgroundTransparency = fillA, AutoButtonColor = false,
					BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = math.floor(13 * S),
					TextColor3 = textCol, Text = label, ZIndex = 18,
				}, card)
				new("UICorner", { CornerRadius = UDim.new(0, math.floor(12 * S)) }, btn)
				local st = new("UIStroke", { Color = border, Thickness = 2 * S, Transparency = borderA }, btn)
				fades[#fades + 1] = { btn, "BackgroundTransparency" }
				fades[#fades + 1] = { btn, "TextTransparency" }
				fades[#fades + 1] = { st, "Transparency" }
				return btn, st
			end
			local bw = math.floor((cardW - pad * 2 - gapX) / 2)
			local rebuyable = (eggDef ~= nil) and (result.Source ~= "reward")
			local again, againStroke = button(pad, bw, Color3.new(1, 1, 1), alpha(0x14),
				Color3.new(1, 1, 1), alpha(0x29), Color3.new(1, 1, 1), "HATCH ANOTHER")
			local keep, keepStroke = button(pad + bw + gapX, bw, accent, 0, accent, 0,
				Color3.fromRGB(11, 18, 12), "COLLECT")
			if not rebuyable then
				-- a reward egg has no purchase to repeat; COLLECT takes the row
				again.Visible = false
				keep.Position = UDim2.fromOffset(pad, btnY)
				keep.Size = UDim2.fromOffset(cardW - pad * 2, btnH)
			end

			-- THE CONTENTS RIDE THE CARD'S OWN FADE (spec: slides up + fades in
			-- as a unit, 420ms after a 300ms delay). Children do not inherit a
			-- Frame's transparency, so each element is born clear and tweened back
			-- to the resting value it was authored with, on the same delayed
			-- TweenInfo the card rides -- without this the text and buttons hang
			-- fully opaque over a still-transparent slab for the 720ms entrance.
			for _, e in ipairs({
				{ nameL, "TextTransparency" }, { nameInk, "Transparency" },
				{ chip, "BackgroundTransparency" }, { chip, "TextTransparency" },
				{ chipStroke, "Transparency" }, { odds, "TextTransparency" },
				{ again, "BackgroundTransparency" }, { again, "TextTransparency" },
				{ againStroke, "Transparency" },
				{ keep, "BackgroundTransparency" }, { keep, "TextTransparency" },
				{ keepStroke, "Transparency" },
				{ innerGlow1, "BackgroundTransparency" }, { innerGlow2, "BackgroundTransparency" },
			}) do
				local resting = e[1][e[2]]
				e[1][e[2]] = 1
				TweenService:Create(e[1], slide, { [e[2]] = resting }):Play()
			end

			-- the handoff's hover on HATCH ANOTHER: fill and border brighten under
			-- the pointer (desktop only -- touch never fires MouseEnter)
			again.MouseEnter:Connect(function()
				if dead then return end
				TweenService:Create(again, TweenInfo.new(0.12), { BackgroundTransparency = alpha(0x24) }):Play()
				TweenService:Create(againStroke, TweenInfo.new(0.12), { Transparency = alpha(0x45) }):Play()
			end)
			again.MouseLeave:Connect(function()
				if dead then return end
				TweenService:Create(again, TweenInfo.new(0.12), { BackgroundTransparency = alpha(0x14) }):Play()
				TweenService:Create(againStroke, TweenInfo.new(0.12), { Transparency = alpha(0x29) }):Play()
			end)

			again.Activated:Connect(function()
				if dead or not rebuyable then return end
				skip()
				task.delay(FADE_TIME * 0.5, function() fireBuy(eggDef) end)
			end)
			keep.Activated:Connect(function()
				if dead then return end
				-- the handoff's pressed state: the fill drops away, the border and
				-- label take the tier colour, and the ceremony closes
				-- tweened, not set: a bare set would be overwritten a frame later
				-- if the press lands while the card's entrance tween still runs
				TweenService:Create(keep, TweenInfo.new(0.06), { BackgroundTransparency = 1 }):Play()
				keep.TextColor3 = accent
				keep.Text = "COLLECTED \u{2713}"
				keepStroke.Color = accent
				task.delay(0.28, skip)
			end)

			task.delay(SKIP_GRACE + 0.37, function()
				if myGen ~= revealGen then return end
				canSkip = true
				task.delay(AUTO_DISMISS, function()
					if myGen ~= revealGen then return end
					skip()
				end)
			end)
		end

		------------------------------------------------------------ phases
		local function setPhase(p)
			if dead or phase == p then return end
			phase = p
			if p == "shake" then
				tapCap.Visible, tapSub.Visible = false, false
				SoundKit.play("eggStrain", nil, { volume = 0.20, speed = 0.9 })
				SoundKit.play(CRACK_SFX[1], nil, { volume = 0.30 })
				-- the radial glow lifts 0x22 -> 0x77 over 500ms on the first shake
				for _, f in ipairs(glowLayers) do
					tween(f, 0.5, { BackgroundTransparency = 1 - glowLit }):Play()
				end
			elseif p == "crack" then
				SoundKit.play(CRACK_SFX[2], nil, { volume = 0.40, speed = 1.122 })
			elseif p == "split" then
				qCap.Visible = true
				SoundKit.play(CRACK_SFX[3], nil, { volume = 0.48, speed = 0.95 })
				SoundKit.play("eggSplit", nil, { volume = 0.5 })
				-- No swap any more: the voxel egg has been the egg on stage since
				-- the first frame (deviation 1), so the split just... splits.
				-- THE PET UNCOVERS WITH THE SHELL, not a beat later at the reveal.
				-- It is still down at PET_Y (-1.1), under the cradle floor and behind
				-- the slab stack, so nothing shows yet -- but from here on the egg is
				-- OPEN, and whatever is inside it should be what the opening reveals.
				-- Un-hiding at the reveal instead meant the pet popped into being in
				-- mid-air on the same frame the cap began to shatter, and the rise out
				-- of the shell -- which is the whole point of the beat -- was never
				-- actually seen. It now climbs up through the opening in view.
				for _, rec in ipairs(petParts) do rec[1].Transparency = rec[2] end
				splitBurstUI()
			elseif p == "reveal" then
				qCap.Visible = false
				SoundKit.play("eggCrumbleBig", nil, { volume = 0.34, speed = 1.05 })
				SoundKit.play(STING[result.Rarity] or "catchRare", nil, { volume = 0.45 })
				task.delay(4 / 60, function()
					if myGen == revealGen then SoundKit.play("catchBigHit", nil, { volume = 0.42 }) end
				end)
				revealUI()
			end
		end

		local started = false
		-- when the shake actually began: tap-to-hatch means it is NOT t == 0, and the
		-- anticipation ramp below has to measure from here or it starts mid-way
		local hatchAt = nil
		local function hatch()
			if started or dead then return end
			started = true
			hatchAt = t
			setPhase("shake")
			task.delay(D.AT_CRACK, function() if myGen == revealGen then setPhase("crack") end end)
			task.delay(D.AT_SPLIT, function() if myGen == revealGen then setPhase("split") end end)
			task.delay(D.AT_REVEAL, function() if myGen == revealGen then setPhase("reveal") end end)
		end

		catcher.Activated:Connect(function()
			if not started then
				hatch()
			elseif canSkip then
				skip()
			end
		end)
		-- ...and it must never wait forever: a hatch left sitting here would leave
		-- the player with no HUD and their emeralds already spent.
		task.delay(TAP_TIMEOUT, function()
			if myGen == revealGen then hatch() end
		end)

		------------------------------------------------------------ per-frame driver
		-- ONE RenderStepped connection drives every animation in this ceremony, and
		-- skip() disconnects it, so a reveal can never leak a per-frame cost after
		-- it ends. Each continuous value is an exponentially damped approach to a
		-- target -- frame-rate independent, and the reason the phase boundaries do
		-- not snap. Nothing here re-derives a value from wall-clock time per phase.
		-- PER-EGG AURA (2026-08-15). Viewport flavour only: motes as PARTS, because
		-- a ViewportFrame draws BaseParts and MeshParts and nothing else -- no
		-- ParticleEmitter, no Light. The ground GROWTH half of Modules.VoxelEggAura
		-- is deliberately not built here: this stage has no ground for it to grow
		-- out of. That half belongs to the world stall.
		-- Keyed off eggDef.Model ("ForestEgg1"...), which is exactly the EggPalettes
		-- key, so each egg brings its own aura colour to its own hatch.
		local AuraMod, auraMotes, auraH = nil, nil, 0
		do
			local RSx = game:GetService("ReplicatedStorage")
			local okA, A = pcall(require, RSx.Modules:FindFirstChild("VoxelEggAura"))
			local okP, Pal = pcall(require, RSx.Modules:FindFirstChild("EggPalettes"))
			local spec = (okP and type(Pal) == "table" and eggDef and eggDef.Model) and Pal[eggDef.Model] or nil
			if okA and type(A) == "table" and spec then
				AuraMod = A
				auraH = D.RY * 2 * us
				local model
				model, auraMotes = A.buildViewport(spec, auraH, 4242, 16)
				model.Parent = eggVp
			end
		end

		conn = RunService.RenderStepped:Connect(function(dt)
			dt = math.min(dt, 0.05)
			t += dt
			local p = phase

			-- RAMPED, not stepped. The reference's shake amplitude roughly doubles
			-- across the anticipation (measured +-5k -> +-10k shell pixels); a flat
			-- target made the longer wait read as dead time instead of a build.
			local shakeT = 0
			if p == "shake" then
				local k = hatchAt and math.clamp((t - hatchAt) / math.max(0.01, D.AT_CRACK), 0, 1) or 0
				shakeT = D.SHAKE * (D.SHAKE_MIN + (1 - D.SHAKE_MIN) * k)
			elseif p == "crack" then
				shakeT = D.SHAKE_CRACK
			end
			local glowT = (p == "crack" and D.GLOW_CRACK) or (p == "split" and D.GLOW_SPLIT)
				or (p == "reveal" and D.GLOW_REVEAL) or 0

			shake = damp(shake, shakeT, D.LAM_SHAKE, dt)
			open = damp(open, ((p == "split" or p == "reveal") and 1) or 0, D.LAM_OPEN, dt)
			glow = damp(glow, glowT, D.LAM_GLOW, dt)
			stageLit = damp(stageLit, (p == "crack" and 0.45) or (p == "split" and 0.78)
				or (p == "reveal" and 1.0) or 0, D.LAM_GLOW, dt)
			-- user asked for a lighter ground than the reference's own measured 58.6
			-- green, so this deliberately overshoots the clip: ~98 green at full lift.
			if snapGlow then snapGlow.BackgroundTransparency = 1 - stageLit * 0.60 end

			-- FLASH: stateless, derived straight from the hatch clock, so it fires on
			-- exactly the measured beats and needs no trigger or extra state. Two pops:
			-- the big one at AT_CRACK (the reference's 2.20 spike) and a smaller one at
			-- AT_SPLIT when the shell actually breaks. Fast decay -- ~0.09s half-life --
			-- because a slow one reads as a wash instead of an impact.
			if flashFrame and hatchAt then
				local since = t - hatchAt
				local fl = 0
				if since >= D.AT_CRACK then
					fl = math.exp(-7.5 * (since - D.AT_CRACK))
				end
				if since >= D.AT_SPLIT then
					fl = math.max(fl, 0.55 * math.exp(-8.0 * (since - D.AT_SPLIT)))
				end
				flashFrame.BackgroundTransparency = 1 - math.clamp(fl, 0, 1) * 0.88
			end
			petUp = damp(petUp, (p == "reveal") and 1 or 0, D.LAM_PET, dt)
			lift = damp(lift, (p == "reveal") and D.LIFT or 0, D.LAM_LIFT, dt)
			camZ = damp(camZ, (p == "reveal") and D.CAM_Z_OUT or D.CAM_Z, D.LAM_CAM, dt)
			if p == "reveal" then burstT = math.min(D.BURST_CAP, burstT + dt) end

			if fan then fan.Rotation = (t / 40) * 360 % 360 end
			if not started then
				local pulse = 0.25 - 0.25 * math.sin(t * (TAU / 1.1))
				tapCap.TextTransparency, tapInk.Transparency = pulse, pulse
			end

			if not eggReady then return end

			spinY += dt * ((p == "idle") and D.SPIN_IDLE or D.SPIN_BUSY)
			local sh = shake
			local bob = math.sin(t * D.BOB_HZ) * D.BOB_AMP * (1 - open) + lift
			-- ROCK ON THE BASE, not around the middle (2026-08-15). Tilting about the
			-- egg's centre reads as a floating object being rotated; an egg on a floor
			-- turns about its contact point. Same tilt angles, completely different
			-- read -- this was the single biggest cause of the motion feeling stiff.
			-- Yaw is unaffected: spinY is about the Y axis, and the pivot sits ON that
			-- axis, so shifting it changes the tilts only.
			-- Two non-harmonic terms per axis as well: one clean sine reads as clockwork.
			local rockX = (math.sin(t * 27 + 1.1) + 0.42 * math.sin(t * 46.7 + 0.4)) * 0.05 * sh
			local rockZ = (math.sin(t * 34) + 0.30 * math.sin(t * 58.2)) * 0.075 * sh
			local baseY = D.RY * us
			local eggCF = CFrame.new(math.sin(t * 41) * 0.035 * sh * us, bob * us, 0)
				* CFrame.new(0, -baseY, 0)
				* CFrame.Angles(rockX, spinY, rockZ)
				* CFrame.new(0, baseY, 0)

			-- The handoff's uniform egg puff is applied to the CAMERA rather than by
			-- rescaling ~80 parts every frame: scaling the scene about the origin
			-- and dividing the camera by that same factor are the same picture, and
			-- while the puff is running the egg is the only thing in the scene.
			-- ANTICIPATION (2026-08-15). AT_CRACK 2.20 -> AT_SPLIT 2.47 was 270ms in
			-- which nothing changed but the shake, so the split arrived like a cut. The
			-- egg now draws IN across that window and springs on release. Non-uniform
			-- squash is not affordable here -- see the camera-puff note above -- so this
			-- is a uniform gather, which still buys the wind-up.
			local antic = 0
			if hatchAt then
				local since = t - hatchAt
				if p == "crack" then
					local k = math.clamp((since - D.AT_CRACK) / math.max(0.01, D.AT_SPLIT - D.AT_CRACK), 0, 1)
					antic = -0.055 * math.sin(k * math.pi * 0.5)
				elseif p == "split" or p == "reveal" then
					local u2 = math.max(0, since - D.AT_SPLIT)
					antic = 0.055 * math.exp(-5.0 * u2) * math.cos(u2 * 14.0)
				end
			end
			-- motes orbit the STAGE, not the egg: they deliberately do not inherit the
			-- rock, so the egg reads as moving against them rather than dragging them
			if AuraMod and auraMotes then
				AuraMod.stepViewport(auraMotes, t, auraH, math.clamp(t * 1.5, 0, 1))
			end

			local puff = 1 + 0.035 * sh * math.sin(t * 18) + antic
			eggCam.CFrame = CFrame.lookAt(
				Vector3.new(0, D.CAM_Y * us, camZ * us) / puff,
				Vector3.new(0, D.LOOK_Y * us, 0) / puff)

			local o = open
			local topLocal = CFrame.new(D.TOP_X * o * us, D.TOP_Y * o * us, 0)
				* CFrame.Angles(D.TOP_RX * o, 0, D.TOP_RZ * o)
			local botLocal = CFrame.new(0, D.BOT_Y * o * us, 0) * CFrame.Angles(D.BOT_RX * o, 0, 0)

			-- CRADLE RECOIL: it has just had its lid blown off and used to not react
			-- at all. Damped dip-and-settle driven off the burst clock.
			local recoil = (burstT > 0)
				and (math.exp(-6.0 * burstT) * math.cos(burstT * 17.0) * 0.045) or 0
			botM:PivotTo(eggCF * botLocal * CFrame.new(0, -recoil * us, 0))

			local bt = burstT
			for ci, ck in ipairs(chunks) do
				local chunkCF = ck.home
				-- STAGGERED, up to 90ms apart (2026-08-15). All seven leaving on the
				-- identical frame reads as one rigid lid disassembling rather than a
				-- shell bursting. rand() is the handoff's own deterministic hash, so
				-- the offsets are the same burst every hatch.
				local cbt = math.max(0, bt - rand(ci, 77) * 0.09)
				if cbt > 0 then
					-- spin eases in rather than snapping to full rate on frame one
					local sp = cbt ^ 1.25
					chunkCF = CFrame.new(ck.pivot + ck.vel * cbt
						+ Vector3.new(0, -D.BURST_G * us * cbt * cbt, 0))
						* CFrame.Angles(ck.spin.X * sp, ck.spin.Y * sp, ck.spin.Z * sp)
				end
				ck.model:PivotTo(eggCF * topLocal * chunkCF)
			end
			if bt > D.BURST_HOLD then
				local f = math.clamp((bt - D.BURST_HOLD) / D.BURST_FADE, 0, 1)
				for _, rec in ipairs(capParts) do
					rec[1].Transparency = rec[2] + (1 - rec[2]) * f
				end
			end

			if coreOrb then
				local at = eggCF * CFrame.new(0, (D.CORE_Y + o * D.CORE_DY) * us, 0)
				local g = math.clamp(glow / D.GLOW_SPLIT, 0, 1)
				coreOrb.CFrame, coreHalo.CFrame = at, at
				coreOrb.Size = Vector3.new(1, 1, 1) * coreBase * (0.45 + 0.55 * g)
				coreHalo.Size = coreOrb.Size * 2.3
				coreOrb.Transparency = 1 - math.clamp(glow * 0.34, 0, 0.72)
				coreHalo.Transparency = 1 - math.clamp(glow * 0.10, 0, 0.22)
				-- a rarity-coloured spill, not a wash: at 0.42 the whole scene -- egg,
				-- chunks, pet -- went the tier's colour through the split
				eggVp.Ambient = baseAmbient:Lerp(accent, math.clamp(glow * 0.08, 0, 0.18))
			end

			-- driven from the SPLIT, not the reveal: petUp is still ~0 through the
			-- split so the pet simply sits under the cradle floor until it rises
			if petM and open > 0.01 then
				local uu = petUp
				local sc = D.PET_S + uu * D.PET_DS
				if math.abs(petScaleNow - sc) > 0.004 then
					petM:ScaleTo(petBase * sc)
					petScaleNow = sc
				end
				petM:PivotTo(eggCF
					* CFrame.new(0, (D.PET_Y + uu * (D.PET_DY + petLift) + math.sin(t * 2.1) * 0.04 * uu) * u, 0)
					* CFrame.Angles(0, petYaw + math.sin(t * 0.9) * 0.16, 0))

				-- ONE-SHOT LIVE CORRECTION (2026-08-14). Height and facing were BOTH being
				-- computed ahead of time and BOTH kept coming out wrong: petLift is derived in
				-- the SHELL unit map while the cradle is laid out on the SCENE map, so a
				-- build-time measurement compares two different spaces and returned a zero
				-- correction while the pet sat 96% of its height below the rim. And the yaw
				-- needs a rotation convention that three separate derivations each got wrong.
				--
				-- Both are fixed HERE instead, once, in the live viewport after the rise has
				-- settled: measure what is actually on screen and correct against it. No unit
				-- map and no sign convention is assumed, and because the facing is measured per
				-- model it works for all 191 pets, which disagree with each other about which
				-- way "forward" is (only 61% share a dominant direction).
				if not petFixed and uu > 0.98 then
					petFixed = true
					local pcf, psz = petM:GetBoundingBox()
					if botM then
						local bc, bs = botM:GetBoundingBox()
						local want = bc.Position.Y + bs.Y / 2 + 0.10 * psz.Y
						local have = pcf.Position.Y - psz.Y / 2
						if want > have then petLift += (want - have) / math.max(u, 1e-3) end
					end
					local centre = pcf.Position
					local minXZ = 0.08 * math.max(psz.X, psz.Z)
					local sum, n = Vector3.zero, 0
					for _, p in ipairs(petM:GetDescendants()) do
						if p:IsA("BasePart") and p.Name:lower():find("eye") then
							sum += p.Position
							n += 1
						end
					end
					local dir
					if n > 0 then
						local d = sum / n - centre
						d = Vector3.new(d.X, 0, d.Z)
						if d.Magnitude > minXZ then dir = d.Unit end
					end
					if not dir then
						for _, a in ipairs(petM:GetDescendants()) do
							if a:IsA("Attachment") and a.Name == "HeadAttachment" then
								local d = a.WorldPosition - centre
								d = Vector3.new(d.X, 0, d.Z)
								if d.Magnitude > minXZ then
									dir = d.Unit
									break
								end
							end
						end
					end
					if dir then
						local cp = eggCam.CFrame.Position
						local toCam = Vector3.new(cp.X - centre.X, 0, cp.Z - centre.Z)
						if toCam.Magnitude > 1e-3 then
							toCam = toCam.Unit
							petYaw += math.atan2(toCam.X, toCam.Z) - math.atan2(dir.X, dir.Z)
						end
					end
				end
			end
		end)
	end
end

---------------------------------------------------------------- multi-open reveal
-- x3/x10 batches skip the tap-to-crack theatre: the handoff shows the results
-- as a grid of rarity-framed cards popping in on a 90ms stagger, with Skip.
-- Shares revealGen/revealSkip with playReveal so the two can never stack, and
-- restores frame.Visible through the same skip() contract.
local MULTI_CARD_W, MULTI_CARD_H = 150, 196
local MULTI_GAP = 10
local MULTI_STAGGER = 0.09
local MULTI_HOLD = 5.0

local function playMultiReveal(result)
	if revealSkip then revealSkip() end
	revealGen += 1
	local myGen = revealGen
	local results = result.Results
	-- see the same note in playReveal: a reward bundle opens with the shop shut,
	-- and it has to still be shut when the ceremony ends
	local shopWasVisible = frame.Visible

	local root = new("Frame", {
		Name = "MultiReveal", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = 1,
	}, ensureRevealGui())

	local dim = new("Frame", {
		Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
	}, root)
	-- dim-to-blur (2026-08-17): Dim keeps its layer slot but no longer paints;
	-- separation is an instant backdrop blur (the HUDPanelBlur recipe under this
	-- ceremony's own name). Property writes only -- NEVER tween a BlurEffect
	-- (TweenService silently no-ops on non-GuiObjects in this place).
	if not game:GetService("Lighting"):FindFirstChild("EggRevealBlur") then
		local fx = Instance.new("BlurEffect")
		fx.Name = "EggRevealBlur"
		fx.Size = 10
		fx.Parent = game:GetService("Lighting")
	end

	local clickCatcher = new("TextButton", {
		Name = "ClickCatcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 2,
	}, root)

	frame.Visible = false

	-- every popped element carries its own UIScale; skip() shrinks them all so
	-- the dismissal reads as one motion instead of a hard cut
	local pops = {}
	local dead = false
	local canSkip = false
	local function skip()
		if dead then return end
		dead = true
		revealGen += 1
		if revealSkip == skip then revealSkip = nil end
		frame.Visible = shopWasVisible
		local revealBlurFx = game:GetService("Lighting"):FindFirstChild("EggRevealBlur")
		if revealBlurFx then revealBlurFx:Destroy() end
		for _, p in ipairs(pops) do
			TweenService:Create(p, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end
		task.delay(FADE_TIME, function()
			if root then root:Destroy(); root = nil end
		end)
	end
	revealSkip = skip
	clickCatcher.Activated:Connect(function()
		if canSkip then skip() end
	end)

	SoundKit.play("eggSplit", nil, { volume = 0.5 })

	local n = #results
	local cols = math.min(n, 5)
	local rowsN = math.ceil(n / 5)
	local gridW = cols * MULTI_CARD_W + (cols - 1) * MULTI_GAP
	local gridH = rowsN * MULTI_CARD_H + (rowsN - 1) * MULTI_GAP

	local titleL = new("TextLabel", {
		Name = "Title", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.5, -gridH / 2 - 16),
		Size = UDim2.fromOffset(520, 40), BackgroundTransparency = 1,
		Font = FONT, TextSize = 28, TextColor3 = CF.onDark,
		Text = n .. " EGGS OPENED!", ZIndex = 3,
	}, root)
	UITheme.inkText(titleL, 2.8)
	local titleScale = new("UIScale", { Scale = 0 }, titleL)
	pops[#pops + 1] = titleScale
	TweenService:Create(titleScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local grid = new("Frame", {
		Name = "Cards", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(gridW, gridH),
		BackgroundTransparency = 1, ZIndex = 3,
	}, root)

	for i, res in ipairs(results) do
		local col = (i - 1) % 5
		local rowI = math.floor((i - 1) / 5)
		local tier = tierByName[res.Rarity]
		local accent = (tier and tier.Color) or CF.ink

		local slot = new("Frame", {
			Name = "Result" .. i,
			Position = UDim2.fromOffset(col * (MULTI_CARD_W + MULTI_GAP), rowI * (MULTI_CARD_H + MULTI_GAP)),
			Size = UDim2.fromOffset(MULTI_CARD_W, MULTI_CARD_H),
			BackgroundTransparency = 1, ZIndex = 4,
		}, grid)
		local pop = new("UIScale", { Scale = 0 }, slot)

		local card, outer = UITheme.accentCard(slot, accent, 12)
		outer.Name = "ResultCard"
		outer.Size = UDim2.new(1, 0, 1, -40)
		outer.Position = UDim2.fromOffset(0, 0)
		outer.ZIndex = 4
		card.ZIndex = 5
		RarityFX.attach(outer, card, res.Rarity, accent, 0)

		local vp = addPetViewport(card, res.Name, res.PetId, 6)
		if not vp then
			local sw = new("Frame", {
				Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6),
				BackgroundColor3 = accent, BackgroundTransparency = 0.5, ZIndex = 6,
			}, card)
			UITheme.corner(sw, 10)
		end

		-- NO BLEED (2026-08-19). Card is 150 wide on a 160 pitch, so a box of (1, 20)
		-- starting at -10 runs to +160 while the neighbour's starts at +150 -- adjacent
		-- result cards' name and tier boxes literally intersect across the whole
		-- gutter. Today's longest pet name is 139px so glyphs do not reach it, but
		-- these labels are NOT NoPolish, so UIPolish's 2.2-3.6px contextual stroke is
		-- ink that crosses first -- and the Back-easing pop overshoots past scale 1.
		local nameL = new("TextLabel", {
			Name = "Name", Position = UDim2.new(0, 0, 1, -38), Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = CF.onDark,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = res.Name, ZIndex = 6,
		}, slot)
		UITheme.inkText(nameL, 2.2)
		local tierL = new("TextLabel", {
			Name = "Tier", Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 16), -- no bleed; see Name above
			BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = accent,
			Text = string.upper(tostring(res.Rarity or "?")), ZIndex = 6,
		}, slot)
		UITheme.inkText(tierL, 2)

		pops[#pops + 1] = pop
		task.delay(MULTI_STAGGER * (i - 1), function()
			if myGen ~= revealGen then return end
			SoundKit.play("catchSparkle", nil, { volume = 0.18, speed = 1 + 0.03 * i })
			TweenService:Create(pop, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end

	-- Skip: kitButton's hard shadow lands in this holder rather than in root
	-- (the codebase-wide slot-wrapper pattern), and the holder carries the pop.
	local skipHolder = new("Frame", {
		Name = "SkipHolder", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, gridH / 2 + 22),
		Size = UDim2.fromOffset(132, 52), BackgroundTransparency = 1, ZIndex = 7,
	}, root)
	pops[#pops + 1] = new("UIScale", { Scale = 0 }, skipHolder)
	local skipBtn = kitButton(skipHolder, "Skip", "red", UDim2.fromOffset(132, 52), 8)
	skipBtn.Name = "SkipButton"
	skipBtn.Activated:Connect(skip)
	task.delay(MULTI_STAGGER * n + 0.1, function()
		if myGen ~= revealGen then return end
		TweenService:Create(pops[#pops], TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)

	task.delay(SKIP_GRACE + MULTI_STAGGER * n, function()
		if myGen ~= revealGen then return end
		canSkip = true
	end)
	task.delay(MULTI_HOLD + MULTI_STAGGER * n, function()
		if myGen ~= revealGen then return end
		skip()
	end)
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

-- BULK BUYS HOLD THE CEREMONY BACK 1.10s (Task 7 fix 1). Task 5's ACQUIRED stamp
-- and receipt ticket are drawn into the shop panel, and playReveal hides `frame`
-- and disables every other ScreenGui in the very frame they are created -- so
-- with no hold they are never seen at all. x1 still goes straight to the
-- ceremony, which is the fast path a single hatch wants. BULK_HOLD is the
-- stamp's own STAMP_HOLD, so the ceremony starts on the beat the stamp finishes
-- clearing rather than cutting across it.
--
-- ITS OWN TOKEN, DELIBERATELY NOT revealGen. revealGen belongs to whichever
-- ceremony is LIVE; playReveal, playMultiReveal and skip() all bump it. Reaching
-- in from out here to cancel a ceremony that has not started yet would silently
-- orphan a RUNNING one instead -- every scheduled callback would no-op without
-- skip() ever restoring frame.Visible or destroying the overlay, leaving the
-- player staring at a dimmed screen with the shop gone. holdToken only ever
-- cancels a PENDING start, and it is bumped on every successful result (x1
-- included), so a second purchase during the hold REPLACES the pending ceremony
-- rather than queueing a second one. Task 5's own `gen` clears the stamp and
-- ticket on that same second result, so nothing is left stranded either.
do
	-- PAIRED WITH THE RECEIPT (final review I1): TICKET_LIFE 0.92 + TICKET_OUT
	-- 0.18 == this. The ticket is parented into frame.PopHolder, so this hold is
	-- the entire window it has to be seen in -- move this number and the receipt
	-- either dies mid-count or outlives the panel. STAMP_HOLD is 1.10 too.
	local BULK_HOLD = 1.10
	local holdToken = 0
	remotes.EggResult.OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then return end
		if not result.Ok then
			-- UNTOUCHED BY THE HOLD, and it has to be: a refusal has no ceremony
			-- to wait for, so its toast still surfaces immediately.
			showToast(result.Message)
			return
		end
		-- setOpen first so emerald/quest state refreshes and the panel is the one
		-- the reveal hides behind its own overlay; both reveals restore
		-- frame.Visible themselves when they end or are skipped. It also has to
		-- happen NOW rather than after the hold: the stamp lands on a card inside
		-- this panel and the ticket is parented into it.
		--
		-- NOT FOR A REWARD. A daily or season egg reward fires this same remote so it
		-- gets the same ceremony, but it is not a purchase: opening the shop on top of
		-- the rewards panel the player is actually looking at would be a non-sequitur,
		-- and there is no card here for a stamp to land on. gui.Enabled is always true
		-- and the reveal is its own full-screen overlay, so it draws perfectly well
		-- with the panel shut.
		if result.Source ~= "reward" then
			setOpen(true)
		end
		local bulk = typeof(result.Results) == "table" and #result.Results > 1
		holdToken += 1
		local myHold = holdToken
		local function startReveal()
			if bulk then playMultiReveal(result) else playReveal(result) end
		end
		if bulk then
			task.delay(BULK_HOLD, function()
				if myHold ~= holdToken then return end
				startReveal()
			end)
		else
			startReveal()
		end
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
