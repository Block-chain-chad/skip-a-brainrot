--!strict
-- ViewportCuller -- mounts only the cards inside a ScrollingFrame's viewport (spec
-- 2026-09-18 UI foundation §8.3, handoff §20 "only render visible cards"). Lifted from
-- IndexPanel.updateVisible: decide from each card's REAL on-screen rectangle against
-- the scroll's rectangle (± margin), never from row maths that can drift from the
-- layout. Nearest-to-centre first under a live cap that is per-platform
-- (S.Card.MaxLive, replaced by the Gallery stress test) and ADAPTIVE: if Heartbeat
-- stays over budget for budgetFrames consecutive frames while cards are mounted, the
-- cap steps down 25% (floor 12) and does not climb back within one attach.
--
-- UI ROUND 4 (2026-09-19): mounts are SLICED. A pass used to mount every card the
-- plan wanted in one go -- a whole window of viewport clones (up to the cap) in the
-- frame a panel opened or a fast scroll landed, measured as the 100-260 ms hitches
-- on the Bag. A pass now mounts at most `mountsPerPass` (default 8) nearest-to-centre
-- cards and re-schedules itself for the NEXT frame while any remain, so the work
-- spreads over a few frames instead of one; unmounts are cheap and still happen in
-- full. Cards whose root is not Visible (a search miss kept for reuse) are treated as
-- off screen. A handle can also be SUSPENDED (suspend / resume): the scroll signals
-- and the Heartbeat let go while a panel is hidden, and what is mounted stays mounted
-- -- a hidden ViewportFrame renders nothing and its FxDriver entries are skipped, so a
-- re-open costs a scheduling pass instead of re-cloning the whole window.
-- The adaptive cap has a MOVING FLOOR: it never drops below the number of cards
-- actually intersecting the viewport (no margin), so what is on screen always has
-- its art, and frames in which a pass itself mounted cards are not counted against
-- the budget -- measured on a 250-card bag, the cap had fed back on itself (a scroll
-- makes frames long, the cap drops under the window, the nearest-to-centre plan
-- then churns mounts on every step, which makes frames longer).
-- A FLING MOUNTS NOTHING. While the canvas moves faster than `flingPx` per frame
-- (a quarter of the window by default) a pass only unmounts what left the margin;
-- the art for the rows racing past lands the frame the scroll slows down. Each
-- viewport shown mid-fling was work thrown away a frame later, and it is what held
-- a fast scroll of 250 cards at ~30 fps with the plates themselves costing 17 ms.
-- BUSY FRAMES ARE THE CONSUMER'S (setBusy): while the Bag builds new cards a few per
-- Heartbeat, every one of those frames runs 25-35 ms of engine layout, and 30 of
-- them in a row read as "this device cannot afford the cap" -- measured as
-- 64 -> 48 -> 36 -> 27 over three 250-card fills, and a handle that now lives for
-- the whole session (suspended on close, not detached) would never win it back.
-- A consumer that declares itself busy excludes those frames from the budget, the
-- same way the culler's own mount frames are excluded.
local RunService = game:GetService("RunService")
local S = require(script.Parent.SpecTheme)
local Platform = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Platform"))

export type Cullable = { root: GuiObject, mount: () -> (), unmount: () -> (), isMounted: () -> boolean }
export type Options = { margin: number?, maxLive: number?, budgetMs: number?, budgetFrames: number?, floor: number?, mountsPerPass: number?, flingPx: number? }
export type Rect = { y: number, h: number }
export type Handle = {
	refresh: () -> (), setCards: (cards: { Cullable }) -> (), detach: () -> (),
	suspend: () -> (), resume: () -> (), setBusy: (busy: boolean) -> (),
	isDetached: () -> boolean, live: () -> number, cap: () -> number,
}

local ViewportCuller = {}

function ViewportCuller.defaultCap(): number
	local caps = S.Card.MaxLive
	local class = Platform.Class
	if class == "Console" then class = "Desktop" end
	return caps[class] or caps.Desktop
end

local function safeUnmount(c: Cullable)
	if not c.isMounted() then return end
	local ok, err = pcall(c.unmount)
	if not ok then
		warn(("[UIKit] ViewportCuller: unmount failed for %s: %s\n%s"):format(c.root:GetFullName(), tostring(err), debug.traceback()))
	end
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
	table.sort(wanted, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.i < b.i end)
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
	local mountsPerPass = o.mountsPerPass or 8
	local flingPx = o.flingPx -- nil = a quarter of the window, resolved per pass
	local cap = o.maxLive or ViewportCuller.defaultCap()
	local items = cards
	local pending = false
	local detached = false
	local suspended = false
	local over = 0
	local mountedCount = 0
	local onScreen = 0          -- cards intersecting the viewport itself (margin 0)
	local mountedThisFrame = false
	local busy = false          -- the consumer is building: its frames are excused
	local lastY = scroll.CanvasPosition.Y
	local velocity = 0          -- canvas px moved since the previous pass
	local conns: { RBXScriptConnection } = {}
	local handle: Handle

	local function pass()
		pending = false
		if detached or suspended then return end
		local viewH = scroll.AbsoluteSize.Y
		if viewH <= 0 then return end
		local top = scroll.AbsolutePosition.Y
		local y = scroll.CanvasPosition.Y
		velocity = math.abs(y - lastY)
		lastY = y
		local flinging = velocity > (flingPx or viewH * 0.25)
		local rects: { Rect } = {}
		local alive: { Cullable } = {}
		for _, c in ipairs(items) do
			local r = c.root
			if r.Parent and r.Visible then
				table.insert(alive, c)
				table.insert(rects, { y = r.AbsolutePosition.Y, h = r.AbsoluteSize.Y })
			else
				safeUnmount(c)
			end
		end
		onScreen = 0
		for _, r in ipairs(rects) do
			local rel = r.y - top
			if rel < viewH and rel + r.h > 0 then onScreen += 1 end
		end
		local plan = ViewportCuller.planPass(rects, top, viewH, margin, math.max(cap, onScreen))
		for _, i in ipairs(plan.unmount) do
			local c = alive[i]
			safeUnmount(c)
		end
		local live = 0
		local mountedNow = 0
		local remaining = false
		for _, i in ipairs(plan.mount) do
			local c = alive[i]
			if not c.isMounted() then
				if flinging then
					remaining = true
				elseif mountedNow < mountsPerPass then
					mountedNow += 1
					mountedThisFrame = true
					local ok, err = pcall(c.mount)
					if not ok then
						warn(("[UIKit] ViewportCuller: mount failed for %s: %s\n%s"):format(c.root:GetFullName(), tostring(err), debug.traceback()))
					end
				else
					remaining = true
				end
			end
			if c.isMounted() then live += 1 end
		end
		mountedCount = live
		if remaining and not detached then
			-- the rest of the window lands next frame (task.delay(0) resumes on the
			-- next Heartbeat; task.defer would run again this same frame)
			pending = true
			task.delay(0, function()
				if pending and not detached then pass() end
			end)
		end
		-- published for cross-VM probes (execute_luau cannot reach this closure)
		scroll:SetAttribute("CullerLive", live)
		scroll:SetAttribute("CullerCap", cap)
	end

	local function schedule()
		if pending or detached or suspended then return end
		pending = true
		task.defer(pass) -- coalesce: one pass per frame however many signals fire
	end

	local function wire()
		table.insert(conns, scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(schedule))
		table.insert(conns, scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule))
		table.insert(conns, scroll:GetPropertyChangedSignal("AbsolutePosition"):Connect(schedule))
		-- AutomaticCanvasSize settling (or a re-layout) moves cards without any scroll input
		table.insert(conns, scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(schedule))
		-- a scroll that is destroyed or orphaned without detach() must not leak the Heartbeat
		table.insert(conns, scroll.AncestryChanged:Connect(function(_, parent)
			if parent == nil then handle.detach() end
		end))
		table.insert(conns, RunService.Heartbeat:Connect(function(dt)
			if mountedCount == 0 then
				over = 0
				return
			end
			if mountedThisFrame or busy then
				-- a frame we (or the consumer's card build) made long says nothing
				-- about the device
				mountedThisFrame = false
				return
			end
			if dt * 1000 > budgetMs then
				over += 1
				if over >= budgetFrames then
					over = 0
					local newCap = math.max(floorCap, onScreen, math.floor(cap * 0.75))
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
	end
	local function unwire()
		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)
	end
	wire()
	scroll:SetAttribute("CullerDetached", false)
	scroll:SetAttribute("CullerLive", 0)
	scroll:SetAttribute("CullerCap", cap)
	schedule()

	handle = {
		refresh = schedule,
		setCards = function(list: { Cullable })
			-- cards dropped from the working set must not stay mounted forever
			local keep: { [Cullable]: boolean } = {}
			for _, c in ipairs(list) do keep[c] = true end
			for _, c in ipairs(items) do
				if not keep[c] then safeUnmount(c) end
			end
			items = list
			schedule()
		end,
		suspend = function()
			if detached or suspended then return end
			suspended = true
			pending = false
			unwire()
			over = 0
		end,
		resume = function()
			if detached or not suspended then return end
			suspended = false
			wire()
			schedule()
		end,
		detach = function()
			if detached then return end
			detached = true
			suspended = false
			unwire()
			for _, c in ipairs(items) do
				safeUnmount(c)
			end
			mountedCount = 0
			if scroll.Parent then
				scroll:SetAttribute("CullerLive", 0)
				scroll:SetAttribute("CullerDetached", true)
			end
		end,
		setBusy = function(b: boolean) busy = b and true or false end,
		isDetached = function() return detached end,
		live = function() return mountedCount end,
		cap = function() return cap end,
	}
	return handle
end

return ViewportCuller
