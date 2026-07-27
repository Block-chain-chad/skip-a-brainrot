-- BrainrotThumb: shared 3D thumbnail helper.
--
-- Renders a real brainrot model into a ViewportFrame, the way Pet Simulator
-- shows its pets. Two grids need this (the Index and the Backpack) and each was
-- about to grow its own copy of the camera maths, so it lives here once.
--
-- Masters are built ONCE per name and kept UNPARENTED; every viewport gets a
-- CLONE, because a tile dies with its rebuild and would take a shared master
-- down with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local M = {}

local modelFolder = ReplicatedStorage:FindFirstChild("BrainrotModels")
local cache = {}   -- [name] = master Model, or false for "nothing to render"

-- Viewports only draw BaseParts, but a real model also carries emitters,
-- prompts, billboards, sounds and scripts. Those render nothing and make every
-- clone heavier, so the master is stripped once and all clones inherit it.
local function strip(model)
	for _, d in ipairs(model:GetDescendants()) do
		local keep = d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder")
			or d:IsA("SpecialMesh") or d:IsA("Texture") or d:IsA("Decal")
		if not keep then d:Destroy() end
	end
	return model
end

function M.master(name)
	if cache[name] == nil then
		local real = modelFolder and modelFolder:FindFirstChild(name)
		-- false, not nil: a name with no model must not re-run the lookup on
		-- every rebuild
		cache[name] = real and strip(real:Clone()) or false
	end
	return cache[name] or nil
end

-- front-quarter, slightly above; bodies stand on Y=0 facing -Z
local DEFAULT_DIR = Vector3.new(0.9, 0.45, -1).Unit
M.DEFAULT_DIR = DEFAULT_DIR

-- Where to put a camera so a model of any size fills the frame: the point it
-- looks at, and how far back to stand. Extracted so CatchReveal can ORBIT the
-- camera using the same numbers add() uses to place it once -- two copies of
-- this calculation would drift.
function M.framing(model, fov)
	fov = fov or 30
	local cf, ext = model:GetBoundingBox()
	local dist = math.max(ext.X, ext.Y, ext.Z) / (2 * math.tan(math.rad(fov / 2))) + ext.Z * 0.5
	return cf.Position, dist
end

-- Returns the ViewportFrame, or nil when there is no model for that name, so
-- the caller can fall back to a flat swatch.
function M.add(parent, name, opts)
	local master = M.master(name)
	if not master then return nil end
	opts = opts or {}

	local vp = Instance.new("ViewportFrame")
	vp.Size = opts.size or UDim2.fromScale(1, 1)
	vp.Position = opts.position or UDim2.fromScale(0, 0)
	vp.BackgroundTransparency = 1
	vp.ZIndex = opts.zIndex or 1
	vp.Parent = parent

	local m = master:Clone()
	if opts.silhouette then
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then p.Color = opts.silhouette end
		end
	end
	m.Parent = vp

	-- Frame from the REAL bounding box rather than a constant distance: these
	-- models range from under 5 studs to over 30, so one fixed distance would
	-- crop the big ones and shrink the small ones to a dot.
	local fov = opts.fov or 30
	local centre, dist = M.framing(m, fov)
	local cam = Instance.new("Camera")
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(centre + (opts.dir or DEFAULT_DIR) * dist, centre)
	cam.Parent = vp
	vp.CurrentCamera = cam

	return vp
end

return M
