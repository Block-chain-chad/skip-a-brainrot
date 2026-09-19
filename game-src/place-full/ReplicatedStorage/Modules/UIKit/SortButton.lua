--!strict
-- SortButton -- the handoff's Rarity / Newest / A-Z control (spec §6.5): a segmented
-- group of neutral chips, active = blue, others = grey. Thin wrapper over
-- PanelChrome.segmented so it shares the pill geometry and the grammar sweep.
local PC = require(script.Parent.PanelChrome)

export type Mode = { id: string, label: string }
export type Props = {
	modes: { Mode }, selected: string?, onChanged: (id: string) -> (),
	parent: Instance?, zIndex: number?, width: number?, height: number?, name: string?, layoutOrder: number?,
}
export type Api = { root: Frame, set: (id: string) -> (), get: () -> string, destroy: () -> () }

local SortButton = {}

function SortButton.new(props: Props): Api
	local h = props.height or 64
	local labels, index = {}, {}
	for i, m in ipairs(props.modes) do
		labels[i] = m.label
		index[m.id] = i
	end
	local seg = PC.segmented({
		options = labels,
		selected = index[props.selected or ""] or 1,
		size = UDim2.fromOffset(props.width or (#labels * 120 + (#labels - 1) * 12), h),
		parent = props.parent,
		zIndex = props.zIndex,
		radius = math.floor(h * 0.5),
		-- anything under the 56px row class is a SMALL control: thin edge, text sized to the
		-- chip (round 2: the Bag's phone controls are 50 tall and were getting the 6px CTA edge)
		outline = if h < 56 then 3 else nil,
		textSize = if h < 56 then math.max(12, math.floor(h * 0.42)) else nil,
		onChanged = function(i: number)
			props.onChanged(props.modes[i].id)
		end,
	})
	seg.root.Name = props.name or "SortButton"
	if props.layoutOrder then seg.root.LayoutOrder = props.layoutOrder end
	return {
		root = seg.root,
		set = function(id: string)
			local i = index[id]
			if i then seg.set(i) end
		end,
		get = function()
			local m = props.modes[seg.get()]
			return if m then m.id else ""
		end,
		destroy = function() seg.root:Destroy() end,
	}
end

return SortButton
