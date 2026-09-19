-- ProgressPanel: Goals and the Season Pass under one rail tile.
--
-- It owns NO content. It draws the shell -- one header, one close button, two tabs
-- -- and mounts the existing GoalsPanel and PassPanel inside it, each built with
-- { embedded = true } so they skip their own header and start at the top. Both are
-- big, heavily-annotated panels (1135 and 857 lines); re-implementing their
-- innards to merge them would have been a rewrite, and this is a re-parenting.
--
-- Those two modules now answer to "goalsInner" / "passInner" and nothing opens
-- them directly -- this module is what the rail's "goals" tile reaches.
--
-- WHY THE TABS SIT IN THE HEADER. A tab strip on its own row would cost ~62px, and
-- the taller child (the pass ladder, 598px embedded) plus a 92px header already
-- comes to 700 -- which is GameHUDClient's PANEL_FIT_H, the height at which panels
-- start being scaled down. Putting the tabs in the header's spare middle costs
-- nothing vertically and keeps the ladder full size.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Panels = script.Parent
local GoalsPanel = require(Panels:WaitForChild("GoalsPanel"))
local PassPanel = require(Panels:WaitForChild("PassPanel"))

local ProgressPanel = { Id = "goals" }

local TABS = {
	{ Id = "Goals", Label = "GOALS" },
	{ Id = "Pass", Label = "SEASON PASS" },
}

-- 2026-08-09 HUD upgrade (design_handoff_hud_upgrade): the shell is the
-- sheet's PanelChrome now -- 1140x800, ORANGE header, and the two top-level
-- tabs live IN the header at their spec sizes (GOALS 190x72, SEASON PASS
-- 230x72), visibly senior to the Daily/Weekly sub-tabs in the body. The
-- embedded GoalsPanel / PassPanel children are mounted unchanged; their
-- content-level restyle onto spec rows is the next pass.
local UIKit = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIKit")
local PC = require(UIKit:WaitForChild("PanelChrome"))
local S = require(UIKit:WaitForChild("SpecTheme"))

function ProgressPanel.Build(ctx)
	local shell = PC.shell({
		name = "ProgressPanel",
		title = "PROGRESS",
		key = "goals",
		icon = S.Art.goals, -- PS99 restyle: rail sticker in the header
		size = S.ShellFor.goals,
		scroll = false,
		listLayout = false,
	})
	shell.close.Activated:Connect(function()
		if ctx.closePanel then ctx.closePanel() end
	end)

	----------------------------------------------------------- content hosts
	-- Each child returns a full-bleed wrapper whose own column is centred
	-- inside it, so parenting it into the body centres it whatever its own
	-- width is. No child geometry is touched.
	local built = {}
	local okGoals, goalsFrame = pcall(GoalsPanel.Build, ctx, { embedded = true })
	if okGoals and goalsFrame then
		goalsFrame.Parent = shell.body
		built.Goals = goalsFrame
	else
		warn("[ProgressPanel] GoalsPanel.Build failed: " .. tostring(goalsFrame))
	end

	local okPass, passFrame = pcall(PassPanel.Build, ctx, { embedded = true })
	if okPass and passFrame then
		passFrame.Parent = shell.body
		built.Pass = passFrame
	else
		warn("[ProgressPanel] PassPanel.Build failed: " .. tostring(passFrame))
	end

	----------------------------------------------------------- header tabs
	local tabs = shell.addHeaderTabs({
		{ text = "GOALS", width = 190 },
		{ text = "SEASON PASS", width = 230 },
	}, 1, function(idx)
		local active = TABS[idx].Id
		for _, def in ipairs(TABS) do
			local f = built[def.Id]
			if f then f.Visible = (def.Id == active) end
		end
	end)

	-- initial paint: Goals in front
	for _, def in ipairs(TABS) do
		local f = built[def.Id]
		if f then f.Visible = (def.Id == "Goals") end
	end

	return shell.root
end

return ProgressPanel
