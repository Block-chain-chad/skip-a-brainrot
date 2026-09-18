--!strict
-- SearchBar -- the kit's search input (spec 2026-09-18 UI foundation §6.4). White
-- well, soft edge, magnifier glyph, clear-x when non-empty, debounced onChanged.
local S = require(script.Parent.SpecTheme)
local PC = require(script.Parent.PanelChrome)

export type Props = {
	placeholder: string?, width: number?, height: number?, onChanged: (query: string) -> (),
	parent: Instance?, zIndex: number?, name: string?, debounce: number?, layoutOrder: number?, textSize: number?,
}
export type Api = {
	root: Frame, box: TextBox, get: () -> string, set: (text: string) -> (),
	clear: () -> (), focus: () -> (), destroy: () -> (),
}

local SearchBar = {}

function SearchBar.new(props: Props): Api
	local h = props.height or 64
	local w = props.width or 320
	local z = props.zIndex or (PC.zBase + 2)
	local textSize = props.textSize or math.clamp(math.floor(h * 0.4), 14, 26)

	local root = Instance.new("Frame")
	root.Name = props.name or "SearchBar"
	root.Size = UDim2.fromOffset(w, h)
	root.BackgroundColor3 = S.Surface.RowTop
	root.BorderSizePixel = 0
	root.ZIndex = z
	if props.layoutOrder then root.LayoutOrder = props.layoutOrder end
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 999); c.Parent = root
	local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = S.OutlineSoft; st.Parent = root
	local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(S.Surface.RowTop, S.Surface.RowBottom); g.Parent = root

	-- magnifier from primitives (the Bag's own recipe): lens ring + tilted handle
	local magSize = math.floor(h * 0.42)
	local mag = Instance.new("Frame")
	mag.Name = "Mag"
	mag.BackgroundTransparency = 1
	mag.AnchorPoint = Vector2.new(0, 0.5)
	mag.Position = UDim2.new(0, math.floor(h * 0.32), 0.5, 0)
	mag.Size = UDim2.fromOffset(magSize, magSize)
	mag.ZIndex = z + 1
	mag.Parent = root
	local lens = Instance.new("Frame")
	lens.Name = "Lens"
	lens.Position = UDim2.fromOffset(1, 1)
	lens.Size = UDim2.new(0.7, 0, 0.7, 0)
	lens.BackgroundTransparency = 1
	lens.ZIndex = z + 1
	lens.Parent = mag
	local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0, 999); lc.Parent = lens
	local ls = Instance.new("UIStroke"); ls.Thickness = math.max(2, magSize * 0.14); ls.Color = S.Surface.ReadSub; ls.Parent = lens
	local handle = Instance.new("Frame")
	handle.Name = "Handle"
	handle.AnchorPoint = Vector2.new(1, 1)
	handle.Position = UDim2.new(1, 0, 1, 0)
	handle.Size = UDim2.new(0.45, 0, 0.18, 0)
	handle.Rotation = 45
	handle.BackgroundColor3 = S.Surface.ReadSub
	handle.BorderSizePixel = 0
	handle.ZIndex = z + 1
	handle.Parent = mag
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 999); hc.Parent = handle

	local clearW = math.floor(h * 0.6)
	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.BackgroundTransparency = 1
	box.Position = UDim2.new(0, math.floor(h * 0.32) + magSize + 10, 0, 0)
	box.Size = UDim2.new(1, -(math.floor(h * 0.32) + magSize + 10 + clearW + 12), 1, 0)
	box.Text = ""
	box.PlaceholderText = props.placeholder or "SEARCH..."
	box.PlaceholderColor3 = S.Surface.ReadSub
	box.TextColor3 = S.Surface.ReadInk
	box.Font = S.Font.Read
	box.TextSize = textSize
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.ZIndex = z + 1
	box:SetAttribute("NoPolish", true)
	box.Parent = root

	local clearBtn = Instance.new("TextButton")
	clearBtn.Name = "Clear"
	clearBtn.Text = ""
	clearBtn.AutoButtonColor = false
	clearBtn.BorderSizePixel = 0
	clearBtn.AnchorPoint = Vector2.new(1, 0.5)
	clearBtn.Position = UDim2.new(1, -math.floor(h * 0.2), 0.5, 0)
	clearBtn.Size = UDim2.fromOffset(clearW, clearW)
	clearBtn.BackgroundColor3 = S.Role.Disabled[1]
	clearBtn.ZIndex = z + 1
	clearBtn.Visible = false
	clearBtn:SetAttribute("NoPolish", true)
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 999); cc.Parent = clearBtn
	PC.shout({ name = "Label", text = "\u{00D7}", size = math.floor(clearW * 0.8), color = S.Surface.ReadInk, strokeColor = Color3.new(1, 1, 1), zIndex = z + 2, parent = clearBtn })
	clearBtn.Parent = root

	-- debounce: a query fires props.debounce (80ms) after the last keystroke; an
	-- EMPTY query (clear) fires at once. Generation-guarded so a stale timer never
	-- fires a superseded value.
	local gen = 0
	local function emit(immediate: boolean)
		gen += 1
		local my = gen
		local function fire()
			if my == gen and root.Parent then props.onChanged(box.Text) end
		end
		if immediate then fire() else task.delay(props.debounce or 0.08, fire) end
	end
	box:GetPropertyChangedSignal("Text"):Connect(function()
		clearBtn.Visible = box.Text ~= ""
		emit(box.Text == "")
	end)
	clearBtn.Activated:Connect(function()
		box.Text = ""
		box:CaptureFocus()
	end)

	local api: Api = {
		root = root,
		box = box,
		get = function() return box.Text end,
		set = function(text: string) box.Text = text end,
		clear = function() box.Text = "" end,
		focus = function() box:CaptureFocus() end,
		destroy = function() root:Destroy() end,
	}
	root.Parent = props.parent
	return api
end

return SearchBar
