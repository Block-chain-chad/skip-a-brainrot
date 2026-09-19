-- rbx_stub.lua -- just enough of the Roblox API, in plain Lua 5.1, for the
-- NPC-01 kit modules to load and RUN outside Studio (tools/npc_kit harness).
--
-- Not a Roblox emulator: the DataModel here is a tree of tables with the
-- properties, methods, signals and value types the kit touches (Vector3,
-- CFrame with real rotation math, Color3 with HSV, Enum items, Instances with
-- parenting/attributes/cloning/joints, CollectionService, PhysicsService,
-- RunService, Players, ProximityPromptService, a Camera). Where Roblox
-- semantics matter for the kit's correctness -- CFrame composition, joint
-- frames, pivot moves, clone remapping of joint references -- they are
-- implemented properly; everything else is a recording stub.

local stub = {}

-- ===== small utils ===========================================================
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
math.clamp = math.clamp or clamp
math.round = math.round or function(x) return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5) end
table.find = table.find or function(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
table.create = table.create or function(n, v) local t = {} for i = 1, n do t[i] = v end return t end

-- ===== Signal ================================================================
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ _conns = {} }, Signal) end
function Signal:Connect(fn)
	local conn = { fn = fn, connected = true }
	function conn:Disconnect() self.connected = false end
	self._conns[#self._conns + 1] = conn
	return conn
end
function Signal:Fire(...)
	local list = {}
	for _, c in ipairs(self._conns) do if c.connected then list[#list + 1] = c end end
	for _, c in ipairs(list) do c.fn(...) end
end
function Signal:Wait() return 1 / 60 end
stub.Signal = Signal

-- ===== Vector3 ===============================================================
local Vector3 = {}
Vector3.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z); if m == 0 then return Vector3.new(0, 0, 0) end return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return Vector3[k]
end
function Vector3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __type = "Vector3" }, Vector3) end
Vector3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
Vector3.__mul = function(a, b)
	if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3.__div = function(a, b)
	if type(b) == "number" then return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
	return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vector3.__eq = function(a, b) return math.abs(a.X - b.X) < 1e-9 and math.abs(a.Y - b.Y) < 1e-9 and math.abs(a.Z - b.Z) < 1e-9 end
Vector3.__tostring = function(v) return string.format("%.3f, %.3f, %.3f", v.X, v.Y, v.Z) end
function Vector3:Dot(b) return self.X * b.X + self.Y * b.Y + self.Z * b.Z end
function Vector3:Cross(b) return Vector3.new(self.Y * b.Z - self.Z * b.Y, self.Z * b.X - self.X * b.Z, self.X * b.Y - self.Y * b.X) end
function Vector3:Lerp(b, a) return self + (b - self) * a end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
stub.Vector3 = Vector3

-- ===== CFrame (3x3 rotation, row-major, + position) ==========================
local CFrame = {}
local function mat3mul(a, b)
	local c = {}
	for i = 0, 2 do for j = 0, 2 do
		local s = 0
		for k = 0, 2 do s = s + a[i * 3 + k + 1] * b[k * 3 + j + 1] end
		c[i * 3 + j + 1] = s
	end end
	return c
end
local function mat3vec(m, v) return Vector3.new(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z) end
local function mat3T(m) return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] } end
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function newCF(p, R) return setmetatable({ p = p, R = R or IDENT, __type = "CFrame" }, CFrame) end
CFrame.__index = function(cf, k)
	if k == "Position" then return cf.p
	elseif k == "X" then return cf.p.X elseif k == "Y" then return cf.p.Y elseif k == "Z" then return cf.p.Z
	elseif k == "RightVector" then return Vector3.new(cf.R[1], cf.R[4], cf.R[7])
	elseif k == "UpVector" then return Vector3.new(cf.R[2], cf.R[5], cf.R[8])
	elseif k == "LookVector" then return Vector3.new(-cf.R[3], -cf.R[6], -cf.R[9])
	elseif k == "Rotation" then return newCF(Vector3.zero, cf.R)
	end
	return CFrame[k]
end
function CFrame.new(a, b, c)
	if a == nil then return newCF(Vector3.zero, IDENT) end
	if type(a) == "table" and a.__type == "Vector3" then
		if b and b.__type == "Vector3" then return CFrame.lookAt(a, b) end
		return newCF(Vector3.new(a.X, a.Y, a.Z), IDENT)
	end
	return newCF(Vector3.new(a, b, c), IDENT)
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return newCF(Vector3.zero, mat3mul(Rx, mat3mul(Ry, Rz)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromAxisAngle(axis, a)
	local u = axis.Unit
	local c, s = math.cos(a), math.sin(a)
	local t = 1 - c
	local x, y, z = u.X, u.Y, u.Z
	return newCF(Vector3.zero, { t*x*x + c, t*x*y - s*z, t*x*z + s*y, t*x*y + s*z, t*y*y + c, t*y*z - s*x, t*x*z - s*y, t*y*z + s*x, t*z*z + c })
end
function CFrame.lookAt(pos, target, up)
	up = up or Vector3.new(0, 1, 0)
	local back = (pos - target).Unit
	local right = up:Cross(back).Unit
	local u = back:Cross(right)
	return newCF(pos, { right.X, u.X, back.X, right.Y, u.Y, back.Y, right.Z, u.Z, back.Z })
end
CFrame.__mul = function(a, b)
	if b.__type == "Vector3" then return mat3vec(a.R, b) + a.p end
	return newCF(mat3vec(a.R, b.p) + a.p, mat3mul(a.R, b.R))
end
CFrame.__add = function(a, v) return newCF(a.p + v, a.R) end
CFrame.__sub = function(a, v) return newCF(a.p - v, a.R) end
CFrame.__tostring = function(cf) return "CFrame(" .. tostring(cf.p) .. ")" end
function CFrame:Inverse() local RT = mat3T(self.R); return newCF(-mat3vec(RT, self.p), RT) end
function CFrame:ToObjectSpace(cf) return self:Inverse() * cf end
function CFrame:ToWorldSpace(cf) return self * cf end
function CFrame:PointToObjectSpace(v) return mat3vec(mat3T(self.R), v - self.p) end
function CFrame:PointToWorldSpace(v) return self * v end
function CFrame:VectorToObjectSpace(v) return mat3vec(mat3T(self.R), v) end
function CFrame:VectorToWorldSpace(v) return mat3vec(self.R, v) end
function CFrame:Lerp(b, a) return newCF(self.p:Lerp(b.p, a), a < 0.5 and self.R or b.R) end
function CFrame:GetComponents() local R = self.R; return self.p.X, self.p.Y, self.p.Z, R[1], R[2], R[3], R[4], R[5], R[6], R[7], R[8], R[9] end
CFrame.identity = newCF(Vector3.zero, IDENT)
stub.CFrame = CFrame

-- ===== Color3 ================================================================
local Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0, __type = "Color3" }, Color3) end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local m = i % 6
	if m == 0 then return Color3.new(v, t, p) elseif m == 1 then return Color3.new(q, v, p) elseif m == 2 then return Color3.new(p, v, t)
	elseif m == 3 then return Color3.new(p, q, v) elseif m == 4 then return Color3.new(t, p, v) else return Color3.new(v, p, q) end
end
function Color3:ToHSV()
	local r, g, b = self.R, self.G, self.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
		h = h / 6
	end
	local s = mx > 0 and d / mx or 0
	return h, s, mx
end
function Color3:Lerp(b, a) return Color3.new(self.R + (b.R - self.R) * a, self.G + (b.G - self.G) * a, self.B + (b.B - self.B) * a) end
Color3.__eq = function(a, b) return math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6 end
Color3.__tostring = function(c) return string.format("%d, %d, %d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
stub.Color3 = Color3

-- ===== Enum ==================================================================
local enumCache = {}
local Enum = setmetatable({}, { __index = function(_, enumType)
	local items = enumCache[enumType]
	if not items then
		items = setmetatable({}, { __index = function(t, name)
			local item = setmetatable({ Name = name, EnumType = enumType, __type = "EnumItem" }, { __tostring = function(i) return "Enum." .. enumType .. "." .. name end })
			rawset(t, name, item)
			return item
		end })
		enumCache[enumType] = items
	end
	return items
end })
stub.Enum = Enum

-- ===== Instance ==============================================================
local CLASSES = {
	Instance = nil,
	PVInstance = "Instance", Model = "PVInstance", BasePart = "PVInstance", Part = "BasePart", MeshPart = "BasePart", UnionOperation = "BasePart",
	Folder = "Instance", Attachment = "Instance", JointInstance = "Instance", Motor6D = "JointInstance", Weld = "JointInstance",
	WeldConstraint = "Instance", Constraint = "Instance", AnimationController = "Instance", Animator = "Instance", Humanoid = "Instance",
	ProximityPrompt = "Instance", Light = "Instance", PointLight = "Light", SpotLight = "Light", ParticleEmitter = "Instance",
	Highlight = "Instance", Beam = "Instance", Trail = "Instance", Sound = "Instance", LuaSourceContainer = "Instance",
	Script = "LuaSourceContainer", LocalScript = "LuaSourceContainer", ModuleScript = "LuaSourceContainer",
	Decal = "Instance", Texture = "Instance", SurfaceAppearance = "Instance", Camera = "Instance", ScreenGui = "Instance",
	GuiObject = "Instance", Frame = "GuiObject", Player = "Instance", Workspace = "Instance", ReplicatedStorage = "Instance",
	ServerStorage = "Instance", StarterPlayer = "Instance", PlayerGui = "Instance", DataModel = "Instance", Terrain = "BasePart",
	KeyframeSequence = "Instance", Animation = "Instance",
}
local function isA(class, want)
	local c = class
	while c do
		if c == want then return true end
		c = CLASSES[c]
	end
	return false
end

local Instance = {}
local InstanceMT = {}
local methods = {}

local PART_DEFAULTS = { Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true, CastShadow = true, Massless = false, Transparency = 0, Reflectance = 0,
	CollisionGroup = "Default", Material = Enum.Material.Plastic, Color = Color3.fromRGB(163, 162, 165), Shape = Enum.PartType.Block,
	TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth, MeshId = "", TextureID = "" }

function Instance.new(class, parent)
	assert(CLASSES[class] or class == "Instance", "Instance.new: unknown class " .. tostring(class))
	local o = { ClassName = class, Name = class, _children = {}, _attrs = {}, _props = {}, _signals = {}, _attrSignals = {}, _propSignals = {}, _parent = nil, _destroyed = false }
	if isA(class, "BasePart") then
		for k, v in pairs(PART_DEFAULTS) do o._props[k] = v end
		o._props.Size = Vector3.new(4, 1, 2)
		o._props.CFrame = CFrame.new()
	elseif class == "Attachment" then
		o._props.Position = Vector3.zero
		o._props.CFrame = CFrame.new()
	elseif isA(class, "JointInstance") then
		o._props.C0 = CFrame.new(); o._props.C1 = CFrame.new(); o._props.Transform = CFrame.new(); o._props.Enabled = true
	elseif class == "WeldConstraint" then
		o._props.Enabled = true
	elseif isA(class, "Light") then
		o._props.Enabled = true; o._props.Range = 8; o._props.Brightness = 1; o._props.Color = Color3.new(1, 1, 1)
	elseif class == "ProximityPrompt" then
		o._props.Enabled = true; o._props.HoldDuration = 0; o._props.MaxActivationDistance = 10; o._props.RequiresLineOfSight = true; o._props.ActionText = "Interact"; o._props.ObjectText = ""
		o._signals.Triggered = Signal.new()
	elseif class == "Model" then
		o._props.PrimaryPart = nil; o._props.ModelStreamingMode = Enum.ModelStreamingMode.Default; o._scale = 1
	elseif class == "Camera" then
		o._props.CFrame = CFrame.new(0, 5, 20); o._props.ViewportSize = Vector3.new(1280, 720, 0); o._props.FieldOfView = 70
	elseif class == "ScreenGui" or isA(class, "GuiObject") then
		o._props.Enabled = true; o._props.Visible = false
	elseif class == "ParticleEmitter" then
		o._props.Rate = 5; o._props.Enabled = true
	end
	setmetatable(o, InstanceMT)
	if parent then o.Parent = parent end
	return o
end

local function signal(o, name)
	local s = o._signals[name]
	if not s then s = Signal.new(); o._signals[name] = s end
	return s
end

local function fireAncestry(o)
	signal(o, "AncestryChanged"):Fire(o, o._parent)
	for _, c in ipairs(o._children) do fireAncestry(c) end
end

local function descendantAdded(node, added)
	local p = node
	while p do
		local s = p._signals.DescendantAdded
		if s then s:Fire(added) end
		p = p._parent
	end
end

InstanceMT.__index = function(o, k)
	local m = methods[k]
	if m then return m end
	if k == "Parent" then return o._parent end
	local v = o._props[k]
	if v ~= nil then return v end
	if k == "Position" and isA(o.ClassName, "BasePart") then return o._props.CFrame.Position end
	if k == "WorldPosition" and o.ClassName == "Attachment" then
		local par = o._parent
		return par and (par._props.CFrame * o._props.Position) or o._props.Position
	end
	if k == "WorldCFrame" and o.ClassName == "Attachment" then
		local par = o._parent
		return par and (par._props.CFrame * o._props.CFrame) or o._props.CFrame
	end
	if k == "AncestryChanged" or k == "Destroying" or k == "ChildAdded" or k == "ChildRemoved" or k == "DescendantAdded" or k == "Changed" or k == "Triggered" then
		return signal(o, k)
	end
	-- child lookup by name (Roblox allows instance.ChildName)
	for _, c in ipairs(o._children) do if c.Name == k then return c end end
	return nil
end

InstanceMT.__newindex = function(o, k, v)
	if k == "Parent" then
		local old = o._parent
		if old then
			for i, c in ipairs(old._children) do if c == o then table.remove(old._children, i) break end end
			signal(old, "ChildRemoved"):Fire(o)
		end
		o._parent = v
		if v then
			v._children[#v._children + 1] = o
			signal(v, "ChildAdded"):Fire(o)
			descendantAdded(v, o)
		end
		fireAncestry(o)
		return
	end
	if k == "Position" and isA(o.ClassName, "BasePart") then
		o._props.CFrame = newCF(v, o._props.CFrame.R)
	elseif k == "Position" and o.ClassName == "Attachment" then
		o._props.Position = v
		o._props.CFrame = CFrame.new(v)
	elseif k == "CFrame" and o.ClassName == "Attachment" then
		o._props.CFrame = v
		o._props.Position = v.Position
	else
		o._props[k] = v
	end
	local ps = o._propSignals[k]
	if ps then ps:Fire() end
end

function methods:IsA(class) return isA(self.ClassName, class) end
function methods:GetChildren() local t = {} for i, c in ipairs(self._children) do t[i] = c end return t end
function methods:GetDescendants()
	local out = {}
	local function walk(n) for _, c in ipairs(n._children) do out[#out + 1] = c; walk(c) end end
	walk(self)
	return out
end
function methods:FindFirstChild(name, recursive)
	for _, c in ipairs(self._children) do if c.Name == name then return c end end
	if recursive then
		for _, c in ipairs(self._children) do local r = c:FindFirstChild(name, true) if r then return r end end
	end
	return nil
end
function methods:FindFirstChildOfClass(class) for _, c in ipairs(self._children) do if c.ClassName == class then return c end end return nil end
function methods:FindFirstChildWhichIsA(class, recursive)
	for _, c in ipairs(self._children) do if c:IsA(class) then return c end end
	if recursive then for _, c in ipairs(self._children) do local r = c:FindFirstChildWhichIsA(class, true) if r then return r end end end
	return nil
end
function methods:FindFirstAncestor(name) local p = self._parent while p do if p.Name == name then return p end p = p._parent end return nil end
function methods:FindFirstAncestorOfClass(class) local p = self._parent while p do if p.ClassName == class then return p end p = p._parent end return nil end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:IsDescendantOf(anc) local p = self._parent while p do if p == anc then return true end p = p._parent end return false end
function methods:GetFullName()
	local names = { self.Name }
	local p = self._parent
	while p and p.ClassName ~= "DataModel" do table.insert(names, 1, p.Name); p = p._parent end
	return table.concat(names, ".")
end
function methods:GetAttribute(k) return self._attrs[k] end
function methods:SetAttribute(k, v)
	self._attrs[k] = v
	local s = self._attrSignals[k]
	if s then s:Fire() end
end
function methods:GetAttributes() local t = {} for k, v in pairs(self._attrs) do t[k] = v end return t end
function methods:GetAttributeChangedSignal(k) local s = self._attrSignals[k] if not s then s = Signal.new(); self._attrSignals[k] = s end return s end
function methods:GetPropertyChangedSignal(k) local s = self._propSignals[k] if not s then s = Signal.new(); self._propSignals[k] = s end return s end
function methods:Destroy()
	signal(self, "Destroying"):Fire()
	self.Parent = nil
	self._destroyed = true
	for _, c in ipairs(self:GetChildren()) do c:Destroy() end
end
function methods:Clone()
	local map = {}
	local function copy(src)
		local o = Instance.new(src.ClassName)
		o.Name = src.Name
		for k, v in pairs(src._props) do o._props[k] = v end
		for k, v in pairs(src._attrs) do o._attrs[k] = v end
		o._scale = src._scale
		map[src] = o
		for _, c in ipairs(src._children) do local cc = copy(c); cc._parent = o; o._children[#o._children + 1] = cc end
		return o
	end
	local root = copy(self)
	-- remap references (joints, welds, PrimaryPart, Adornee) into the clone
	for _, o in ipairs(root:GetDescendants()) do
		for _, k in ipairs({ "Part0", "Part1", "Adornee" }) do
			local v = o._props[k]
			if v and map[v] then o._props[k] = map[v] end
		end
	end
	if root._props.PrimaryPart and map[root._props.PrimaryPart] then root._props.PrimaryPart = map[root._props.PrimaryPart] end
	local ok, tags = pcall(function() return stub.CollectionService._tagsOf(self) end)
	if ok and tags then for tag in pairs(tags) do stub.CollectionService:AddTag(root, tag) end end
	return root
end
-- Model
local function bbox(model)
	local mn, mx
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local p, s = d._props.CFrame.Position, d._props.Size
			local lo = Vector3.new(p.X - s.X / 2, p.Y - s.Y / 2, p.Z - s.Z / 2)
			local hi = Vector3.new(p.X + s.X / 2, p.Y + s.Y / 2, p.Z + s.Z / 2)
			if not mn then mn, mx = lo, hi else
				mn = Vector3.new(math.min(mn.X, lo.X), math.min(mn.Y, lo.Y), math.min(mn.Z, lo.Z))
				mx = Vector3.new(math.max(mx.X, hi.X), math.max(mx.Y, hi.Y), math.max(mx.Z, hi.Z))
			end
		end
	end
	if not mn then return Vector3.zero, Vector3.zero end
	return mn, mx
end
function methods:GetPivot()
	if self:IsA("BasePart") then return self._props.CFrame end
	local pp = self._props.PrimaryPart
	if pp then return pp._props.CFrame end
	local mn, mx = bbox(self)
	return CFrame.new((mn + mx) / 2)
end
function methods:PivotTo(cf)
	if self:IsA("BasePart") then self._props.CFrame = cf return end
	local cur = self:GetPivot()
	local delta = cf * cur:Inverse()
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then d._props.CFrame = delta * d._props.CFrame end
	end
end
function methods:GetExtentsSize() local mn, mx = bbox(self) return mx - mn end
function methods:GetScale() return self._scale or 1 end
function methods:ScaleTo(s)
	local factor = s / (self._scale or 1)
	local pivot = self:GetPivot()
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d._props.CFrame)
			d._props.CFrame = pivot * newCF(rel.p * factor, rel.R)
			d._props.Size = d._props.Size * factor
		elseif d:IsA("JointInstance") then
			d._props.C0 = newCF(d._props.C0.p * factor, d._props.C0.R)
			d._props.C1 = newCF(d._props.C1.p * factor, d._props.C1.R)
		elseif d.ClassName == "Attachment" then
			d._props.Position = d._props.Position * factor
		end
	end
	self._scale = s
end
-- Camera
function methods:WorldToViewportPoint(v)
	local rel = self._props.CFrame:PointToObjectSpace(v)
	local depth = -rel.Z
	local vs = self._props.ViewportSize
	local tanH = math.tan(math.rad((self._props.FieldOfView or 70) / 2))
	local aspect = vs.X / vs.Y
	local sx = (rel.X / (depth * tanH * aspect)) * 0.5 + 0.5
	local sy = 0.5 - (rel.Y / (depth * tanH)) * 0.5
	local visible = depth > 0 and sx >= 0 and sx <= 1 and sy >= 0 and sy <= 1
	return Vector3.new(sx * vs.X, sy * vs.Y, depth), visible
end

stub.Instance = Instance
stub.isA = isA

-- ===== services ==============================================================
local CollectionService = { _tags = {}, _added = {}, _removed = {} }
function CollectionService._tagsOf(inst) return CollectionService._tags[inst] end
function CollectionService:AddTag(inst, tag)
	self._tags[inst] = self._tags[inst] or {}
	if self._tags[inst][tag] then return end
	self._tags[inst][tag] = true
	if self._added[tag] then self._added[tag]:Fire(inst) end
end
function CollectionService:RemoveTag(inst, tag)
	if self._tags[inst] and self._tags[inst][tag] then
		self._tags[inst][tag] = nil
		if self._removed[tag] then self._removed[tag]:Fire(inst) end
	end
end
function CollectionService:HasTag(inst, tag) return self._tags[inst] ~= nil and self._tags[inst][tag] == true end
function CollectionService:GetTagged(tag)
	local out = {}
	for inst, tags in pairs(self._tags) do if tags[tag] and not inst._destroyed then out[#out + 1] = inst end end
	return out
end
function CollectionService:GetInstanceAddedSignal(tag) self._added[tag] = self._added[tag] or Signal.new() return self._added[tag] end
function CollectionService:GetInstanceRemovedSignal(tag) self._removed[tag] = self._removed[tag] or Signal.new() return self._removed[tag] end
stub.CollectionService = CollectionService

local PhysicsService = { _groups = { Default = true }, _collidable = {}, calls = {} }
function PhysicsService:IsCollisionGroupRegistered(name) return self._groups[name] == true end
function PhysicsService:RegisterCollisionGroup(name) self._groups[name] = true; self.calls[#self.calls + 1] = "register:" .. name end
function PhysicsService:CollisionGroupSetCollidable(a, b, v) self._collidable[a .. "|" .. b] = v; self.calls[#self.calls + 1] = "collidable:" .. a .. "|" .. b .. "=" .. tostring(v) end
stub.PhysicsService = PhysicsService

local RunService = { Heartbeat = Signal.new(), Stepped = Signal.new(), RenderStepped = Signal.new() }
function RunService:IsClient() return true end
function RunService:IsServer() return false end
function RunService:IsStudio() return true end
stub.RunService = RunService

local ProximityPromptService = { PromptShown = Signal.new(), PromptHidden = Signal.new(), PromptTriggered = Signal.new() }
stub.ProximityPromptService = ProximityPromptService

local HttpService = {}
function HttpService:JSONEncode(t) return tostring(t) end
stub.HttpService = HttpService

-- DataModel
local game = Instance.new("DataModel"); game.Name = "game"
local Workspace = Instance.new("Workspace", game); Workspace.Name = "Workspace"
local ReplicatedStorage = Instance.new("ReplicatedStorage", game); ReplicatedStorage.Name = "ReplicatedStorage"
local ServerStorage = Instance.new("ServerStorage", game); ServerStorage.Name = "ServerStorage"
local StarterPlayer = Instance.new("StarterPlayer", game); StarterPlayer.Name = "StarterPlayer"
local sps = Instance.new("Folder", StarterPlayer); sps.Name = "StarterPlayerScripts"
local camera = Instance.new("Camera", Workspace); camera.Name = "Camera"
Workspace._props.CurrentCamera = camera
function Workspace:GetServerTimeNow() return stub.clock end
stub.clock = 0

local Players = Instance.new("Folder", game); Players.Name = "Players"
local localPlayer = Instance.new("Player"); localPlayer.Name = "LocalPlayer"
local playerGui = Instance.new("PlayerGui", localPlayer); playerGui.Name = "PlayerGui"
local character = Instance.new("Model", Workspace); character.Name = "LocalPlayerCharacter"
local chHrp = Instance.new("Part", character); chHrp.Name = "HumanoidRootPart"; chHrp.CFrame = CFrame.new(0, 3, 12)
local chHead = Instance.new("Part", character); chHead.Name = "Head"; chHead.CFrame = CFrame.new(0, 4.5, 12)
Instance.new("Humanoid", character)
localPlayer._props.Character = character
Players._props.LocalPlayer = localPlayer
function Players:GetPlayers() return { localPlayer } end
function Players:GetPlayerFromCharacter(m) if m == localPlayer._props.Character then return localPlayer end return nil end

local services = { Workspace = Workspace, ReplicatedStorage = ReplicatedStorage, ServerStorage = ServerStorage, StarterPlayer = StarterPlayer,
	Players = Players, CollectionService = CollectionService, PhysicsService = PhysicsService, RunService = RunService,
	ProximityPromptService = ProximityPromptService, HttpService = HttpService }
function game:GetService(name) local s = services[name]; assert(s, "GetService: " .. tostring(name)); return s end
stub.game = game
stub.services = services

-- ===== script loading (require by instance) ==================================
local moduleCache = {}     -- [ModuleScript instance] = result
local modulePath = {}      -- [ModuleScript instance] = file path
stub.log = {}

local function makeEnv(scriptInstance)
	local env = setmetatable({ script = scriptInstance }, { __index = _G })
	return env
end

function stub.registerScript(instance, path) modulePath[instance] = path end

function stub.loadScript(instance)
	local path = modulePath[instance]
	assert(path, "no file registered for " .. instance:GetFullName())
	local f = assert(io.open(path, "rb"))
	local src = f:read("*a")
	f:close()
	local chunk, err = loadstring(src, "=" .. instance:GetFullName())
	assert(chunk, err)
	setfenv(chunk, makeEnv(instance))
	return chunk
end

function stub.require(instance)
	if moduleCache[instance] ~= nil then return moduleCache[instance] end
	local chunk = stub.loadScript(instance)
	local result = chunk()
	moduleCache[instance] = result
	return result
end
function stub.resetModuleCache() moduleCache = {} end

-- ===== globals ===============================================================
_G.Vector3 = Vector3
_G.CFrame = CFrame
_G.Color3 = Color3
_G.Enum = Enum
_G.Instance = Instance
_G.game = game
_G.workspace = Workspace
_G.require = stub.require
_G.typeof = function(v)
	local t = type(v)
	if t == "table" then
		if v.__type then return v.__type end
		if v.ClassName then return "Instance" end
	end
	return t
end
_G.tick = function() return stub.clock end
_G.warn = function(...) local parts = {} for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end stub.log[#stub.log + 1] = "WARN " .. table.concat(parts, " ") end
local realPrint = print
_G.print = function(...) local parts = {} for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end stub.log[#stub.log + 1] = table.concat(parts, " ") end
_G.task = {
	spawn = function(fn, ...) local co = coroutine.create(fn) local ok, err = coroutine.resume(co, ...) if not ok then error(err) end end,
	defer = function(fn, ...) local co = coroutine.create(fn) local ok, err = coroutine.resume(co, ...) if not ok then error(err) end end,
	delay = function(_, fn, ...) local co = coroutine.create(fn) local ok, err = coroutine.resume(co, ...) if not ok then error(err) end end,
	wait = function(t) return t or 0 end,
}
_G.wait = function(t) return t or 0 end
_G.os = os
stub.realPrint = realPrint

return stub
