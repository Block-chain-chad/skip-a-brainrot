--!strict
-- ViewportCuller -- mounts only the cards inside a ScrollingFrame's viewport (spec
-- 2026-09-18 UI foundation §8.3, handoff §20 "only render visible cards"). Lifted from
-- IndexPanel.updateVisible: decide from each card's REAL on-screen rectangle against
-- the scroll's rectangle (± margin), never from row maths that can drift from the
-- layout. Nearest-to-centre first under a live cap that is per-platform
-- (S.Card.MaxLive, replaced by the Gallery stress test) and ADAPTIVE: if Heartbeat
-- stays over budget for budgetFrames consecutive frames while cards are mounted, the
-- cap steps down 25% (floor 12) and does not climb back within one attach.
local RunService = game:GetService("RunService")
local S = require(script.Parent.SpecTheme)
local Platform = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Platform"))

export type Cullable = { root: GuiObject, mount: () -> (), unmount: () -> (), isMounted: () -> boolean }
export type Options = { margin: number?, maxLive: number?, budgetMs: number?, budgetFrames: number?, floor: number? }
export type Rect = { y: number, h: number }
export type Handle = {
	refresh: () -> (), setCards: (cards: { Cullable }) -> (), detach: () -> (),
	isDetached: () -> boolean, live: () -> number, cap: () -> number,
}

local ViewportCuller = {}

function ViewportCuller.defaultCap(): number
	local caps = S.Card.MaxLive
	local class = Platform.Class
	if class == "Console" then class = "Desktop" end
	return caps[class] or caps.Desktop
end

--- Pure planning step: which indices to mount (nearest-to-centre first, up to cap)
--- and which to unmount. rects are card rectangles in the same space as viewTop.
function ViewportCuller.planPass(rects: { Rect }, viewTop: number, viewH: number, margin: number, cap: number): { mount: { number }, unmount: { number } }
	local m = viewH * margin
	local centre = viewTop + viewH * 0.5
	local wanted: { { i: number, d: number } } = {}
	local unmount: { number } = {}
	for i, r in ipairs(rects) do
		local rel = r.y - viewTop
		if rel < viewH + m and rel + r.h > -m then
			table.insert(wanted, { i = i, d = math.abs((r.y + r.h * 0.5) - centre) })
		else
			table.insert(unmount, i)
		end
	end
	table.sort(wanted, function(a, b) return a.d < b.d end)
	local mount: { number } = {}
	for k, w in ipairs(wanted) do
		if k <= cap then table.insert(mount, w.i) else table.insert(unmount, w.i) end
	end
	return { mount = mount, unmount = unmount }
end

function ViewportCuller.attach(scroll: ScrollingFrame, cards: { Cullable }, opts: Options?): Handle
	local o: Options = opts or {}
	local margin = o.margin or 0.5
	local budgetMs = o.budgetMs or 22
	local budgetFrames = o.budgetFrames or 30
	local floorCap = o.floor or 12
	local cap = o.maxLive or ViewportCuller.defaultCap()
	local items = cards
	local pending = false
	local detached = false
	local over = 0
	local mountedCount = 0
	local conns: { RBXScriptConnection } = {}

	local function pass()
		pending = false
		if detached then return end
		local viewH = scroll.AbsoluteSize.Y
		if viewH <= 0 then return end
		local top = scroll.AbsolutePosition.Y
		local rects: { Rect } = {}
		local alive: { Cullable } = {}
		for _, c in ipairs(items) do
			local r = c.root
			if r.Parent then
				table.insert(alive, c)
				table.insert(rects, { y = r.AbsolutePosition.Y, h = r.AbsoluteSize.Y })
			elseif c.isMounted() then
				c.unmount()
			end
		end
		local plan = ViewportCuller.planPass(rects, top, viewH, margin, cap)
		for _, i in ipairs(plan.unmount) do
			local c = alive[i]
			if c.isMounted() then c.unmount() end
		end
		local live = 0
		for _, i in ipairs(plan.mount) do
			local c = alive[i]
			if not c.isMounted() then
				local ok, err = pcall(c.mount)
				if not ok then
					warn(("[UIKit] ViewportCuller: mount failed for %s: %s\n%s"):format(c.root:GetFullName(), tostring(err), debug.traceback()))
				end
			end
			if c.isMounted() then live += 1 end
		end
		mountedCount = live
		-- published for cross-VM probes (execute_luau cannot reach this closure)
		scroll:SetAttribute("CullerLive", live)
		scroll:SetAttribute("CullerCap", cap)
	end

	local function schedule()
		if pending or detached then return end
		pending = true
		task.defer(pass) -- coalesce: one pass per frame however many signals fire
	end

	table.insert(conns, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(schedule))
	table.insert(conns, scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule))
	table.insert(conns, scroll:GetPropertyChangedSignal("AbsolutePosition"):Connect(schedule))
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if mountedCount == 0 then
			over = 0
			return
		end
		if dt * 1000 > budgetMs then
			over += 1
			if over >= budgetFrames then
				over = 0
				local newCap = math.max(floorCap, math.floor(cap * 0.75))
				if newCap < cap then
					warn(("[UIKit] ViewportCuller: %d frames over %dms with %d live viewports -- cap %d -> %d (last dt %.1fms)"):format(budgetFrames, budgetMs, mountedCount, cap, newCap, dt * 1000))
					cap = newCap
					schedule()
				end
			end
		else
			over = 0
		end
	end))
	schedule()

	local handle: Handle = {
		refresh = schedule,
		setCards = function(list: { Cullable })
			-- cards dropped from the working set must not stay mounted forever
			local keep: { [Cullable]: boolean } = {}
			for _, c in ipairs(list) do keep[c] = true end
			for _, c in ipairs(items) do
				if not keep[c] and c.isMounted() then c.unmount() end
			end
			items = list
			schedule()
		end,
		detach = function()
			if detached then return end
			detached = true
			for _, c in ipairs(conns) do c:Disconnect() end
			table.clear(conns)
			for _, c in ipairs(items) do
				if c.isMounted() then c.unmount() end
			end
			mountedCount = 0
			if scroll.Parent then
				scroll:SetAttribute("CullerLive", 0)
				scroll:SetAttribute("CullerDetached", true)
			end
		end,
		isDetached = function() return detached end,
		live = function() return mountedCount end,
		cap = function() return cap end,
	}
	return handle
end

return ViewportCuller
