--!strict
-- FxDriver -- the ONE Heartbeat for every kit animation (card auras, rainbow bands,
-- sparkles, busy dots, toast fades). TweenService cannot animate transparency or
-- gradient offsets in this place (probed live, see roblox-tweenservice-guiobject-only),
-- so every continuous decorative effect is a per-frame property write. One connection
-- for the whole client: it disconnects when the registry empties and reconnects on the
-- next register. Entries whose GuiObject is off screen are skipped, not removed, so a
-- hidden panel costs nothing per frame and resumes where it was.
-- Spec: docs/superpowers/specs/2026-09-18-ui-foundation-design.md §7.6, §12.
local RunService = game:GetService("RunService")

export type Step = (t: number, dt: number) -> ()
type Entry = { gui: GuiObject, step: Step }

local FxDriver = {}

local entries: { [number]: Entry } = {}
local count = 0
local nextId = 0
local conn: RBXScriptConnection? = nil
local clock = 0

-- "Is this gui actually being drawn?" Visible alone lies about hidden ancestors, so
-- walk up to the LayerCollector. Cheap: a card is ~10 levels deep.
local function isShown(gui: GuiObject): boolean
	if not gui.Parent then return false end
	local o: Instance? = gui
	while o and o:IsA("GuiObject") do
		if not (o :: GuiObject).Visible then return false end
		o = o.Parent
	end
	if o and o:IsA("LayerCollector") then return (o :: LayerCollector).Enabled end
	return o ~= nil
end

local function tick(dt: number)
	clock += dt
	-- Snapshot the ids first: a step may register (adding a key mid-`pairs` is
	-- undefined) or unregister. Registrations made during a tick run next frame.
	local ids: { number } = {}
	for id in pairs(entries) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local e = entries[id]
		if e and isShown(e.gui) then
			local ok, err = pcall(e.step, clock, dt)
			if not ok then
				warn(("[UIKit] FxDriver entry %d threw and was removed: %s\n%s"):format(id, tostring(err), debug.traceback()))
				FxDriver.unregister(id)
			end
		end
	end
end

-- Published as attributes on this ModuleScript so a probe from another Lua VM
-- (execute_luau runs in its own) can read the driver's state during verification.
local function publish()
	script:SetAttribute("FxEntries", count)
	script:SetAttribute("FxRunning", conn ~= nil)
end

function FxDriver.register(gui: GuiObject, step: Step): number
	nextId += 1
	local id = nextId
	entries[id] = { gui = gui, step = step }
	count += 1
	-- an entry dies with its gui: a caller that destroys the gui without
	-- unregistering (a busy button torn down mid-timeout) must not leak the entry
	gui.Destroying:Once(function() FxDriver.unregister(id) end)
	if not conn then
		conn = RunService.Heartbeat:Connect(tick)
	end
	publish()
	return id
end

function FxDriver.unregister(id: number?)
	if id == nil or entries[id] == nil then return end
	entries[id] = nil
	count -= 1
	if count <= 0 then
		count = 0
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end
	publish()
end

function FxDriver.isRunning(): boolean
	return conn ~= nil
end

function FxDriver.count(): number
	return count
end

function FxDriver.clock(): number
	return clock
end

return FxDriver