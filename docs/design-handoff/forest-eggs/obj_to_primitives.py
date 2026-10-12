"""Eggs 6-10 -> Luau chunks building NATIVE primitive parts (save-proof).

EditableMesh content does not survive a cloud save/reload (proven 2026-07-30:
post-reload the MeshParts render as checkerboard error blocks). This emits the
same per-group geometry as axis-aligned native parts instead:

  shell_body            -> Block + SpecialMesh Sphere (ellipsoid egg)
  stud/drip/spore/bud/nub/cap_drip -> Block + SpecialMesh Sphere
  spike/horn/thorn/crown_point/crown_tip -> Block + CylinderMesh, Y along longest axis
  ring/halo_ring/rune_ring/crown_ring -> Block + CylinderMesh, Y along SHORTEST axis (disc)
  everything else (stripe/tape/rune_bar/link/shard/cap/...) -> plain Block

Position/size/color per group come straight from the OBJ + MTL. Native
geometry serializes with the place like every other part in the game.
"""
import re
from pathlib import Path

BASE = Path(__file__).parent
SRC = BASE / "eggs_forest_set.obj"
MTL = BASE / "eggs_forest_set.mtl"
OUT = BASE / "luau_chunks_prim"
OUT.mkdir(exist_ok=True)

colors = {}
cur = None
for line in MTL.read_text().splitlines():
    s = line.strip()
    if s.startswith("newmtl "):
        cur = s.split(None, 1)[1]
    elif s.startswith("Kd ") and cur:
        r, g, b = (float(x) for x in s.split()[1:4])
        colors[cur] = (r, g, b)

v = []
clusters, curg, cur_mtl = [], None, None

def close(g):
    if g and g[1]:
        clusters[-1].append(g)

with SRC.open() as f:
    for line in f:
        s = line.strip()
        if s.startswith("v "):
            v.append(tuple(float(x) for x in s.split()[1:4]))
        elif s.startswith(("o ", "g ")):
            name = s.split(None, 1)[1]
            close(curg)
            curg = None
            if name == "shell_body":
                clusters.append([])
            if clusters:
                curg = (name, set(), cur_mtl)
        elif s.startswith("usemtl "):
            cur_mtl = s.split(None, 1)[1]
            if curg and not curg[1]:
                curg = (curg[0], curg[1], cur_mtl)
        elif s.startswith("f ") and curg is not None:
            for t in s.split()[1:]:
                i = int(t.split("/")[0])
                if i < 0:
                    i = len(v) + 1 + i
                curg[1].add(i)
    close(curg)

assert len(clusters) == 10, len(clusters)

BALLS = ("stud", "drip", "spore", "bud", "nub", "cap_drip")
RODS = ("spike", "horn", "thorn", "crown_point", "crown_tip")
RINGS = ("halo_ring", "rune_ring", "crown_ring", "ring")
BANDS = ("stripe", "tape", "rune_bar")

def shape_for(name, ex, ey, ez, shell_ex):
    """Pick a build shape. Wrapping decorations (bbox ~ shell bbox in two
    axes) must NOT become solid slabs: rings -> segmented circles, wide
    stripes -> thin shell-hugging ellipsoid bands."""
    n = name.lower()
    if n.startswith("shell_body"):
        return "egg"
    if n.startswith(BALLS):
        return "ball"
    if n.startswith(RODS):
        return "rod"
    if n.startswith(RINGS):
        return "ringseg"
    if n.startswith(BANDS):
        # wraps the shell if it spans most of the shell in X and Z
        if shell_ex and ex > 0.7 * shell_ex[0] and ez > 0.7 * shell_ex[2]:
            return "band"
        return "block"
    if n.startswith("cap") and shell_ex and ex > 0.7 * shell_ex[0]:
        return "band"  # mushroom cap: shell-hugging dome band
    return "block"

HEADER = """-- egg primitive chunk (auto-generated, save-proof native geometry)
local staging = game.ServerStorage:FindFirstChild("EggPrimStaging")
if not staging then
	staging = Instance.new("Folder")
	staging.Name = "EggPrimStaging"
	staging.Parent = game.ServerStorage
end
local built = 0
local function prim(eggName, partName, shape, sx, sy, sz, r, g, b, cx, cy, cz)
	local p = Instance.new("Part")
	p.Name = partName
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.new(r, g, b)
	local rot = CFrame.new()
	if shape == "egg" or shape == "ball" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	elseif shape == "rod" then
		-- CylinderMesh is Y-up; rotate so Y follows the longest extent
		local m = Instance.new("CylinderMesh")
		m.Parent = p
		if sx >= sy and sx >= sz then
			rot = CFrame.Angles(0, 0, math.rad(90)); sx, sy = sy, sx
		elseif sz >= sy and sz >= sx then
			rot = CFrame.Angles(math.rad(90), 0, 0); sz, sy = sy, sz
		end
	elseif shape == "band" then
		-- shell-hugging ellipsoid band: inflate the two large axes slightly so
		-- it sits just proud of the shell; the small axis is the band height
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
		sx, sz = sx * 1.04, sz * 1.04
	elseif shape == "ringseg" then
		-- segmented circle of 10 small blocks (primitives cannot make holes);
		-- ring plane = the two largest extents, tube = the smallest
		local ax = { { sx, "x" }, { sy, "y" }, { sz, "z" } }
		table.sort(ax, function(a, b) return a[1] > b[1] end)
		local radius = (ax[1][1] + ax[2][1]) / 4
		local tube = math.max(ax[3][1], 0.06)
		local plane = ax[3][2]  -- axis perpendicular to the ring plane
		local segs = 10
		local segLen = 2 * math.pi * radius / segs * 1.15
		for k = 1, segs do
			local a = (k / segs) * 2 * math.pi
			local px, py, pz, r0
			if plane == "y" then
				px, py, pz = math.cos(a) * radius, 0, math.sin(a) * radius
				r0 = CFrame.Angles(0, -a, 0)
			elseif plane == "z" then
				px, py, pz = math.cos(a) * radius, math.sin(a) * radius, 0
				r0 = CFrame.Angles(0, 0, a)
			else
				px, py, pz = 0, math.cos(a) * radius, math.sin(a) * radius
				r0 = CFrame.Angles(a, 0, 0)
			end
			local seg = Instance.new("Part")
			seg.Name = partName .. "_s" .. k
			seg.Anchored = true; seg.CanCollide = false; seg.CanQuery = false; seg.CastShadow = false
			seg.TopSurface = Enum.SurfaceType.Smooth; seg.BottomSurface = Enum.SurfaceType.Smooth
			seg.Material = Enum.Material.SmoothPlastic
			seg.Color = Color3.new(r, g, b)
			seg.Size = Vector3.new(segLen, tube, tube)
			seg.CFrame = CFrame.new(cx + px, cy + py, cz + pz) * r0
			local eggModel = staging:FindFirstChild(eggName)
			if not eggModel then
				eggModel = Instance.new("Model"); eggModel.Name = eggName; eggModel.Parent = staging
			end
			seg.Parent = eggModel
		end
		built += 1
		return
	end
	p.Size = Vector3.new(math.max(sx, 0.05), math.max(sy, 0.05), math.max(sz, 0.05))
	p.CFrame = CFrame.new(cx, cy, cz) * rot
	local eggModel = staging:FindFirstChild(eggName)
	if not eggModel then
		eggModel = Instance.new("Model")
		eggModel.Name = eggName
		eggModel.Parent = staging
	end
	p.Parent = eggModel
	built += 1
end
"""

FOOTER = 'return "built " .. built\n'

MAX_CHUNK = 120_000
egg_names = {6: "ForestEgg1", 7: "ForestEgg2", 8: "ForestEgg3", 9: "ForestEgg4", 10: "ForestEgg5"}
manifest = []
HORNED_BRIGHT = {"spike": (0.208, 0.169, 0.128), "horn": (0.208, 0.169, 0.128)}
for egg_i in range(6, 11):
    egg = clusters[egg_i - 1]
    shell_ex = None
    for gname, verts, _ in egg:
        if gname.startswith("shell_body"):
            pts = [v[i - 1] for i in verts]
            xs, ys, zs = zip(*pts)
            shell_ex = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
            break
    body, n_chunk, n_groups = "", 1, 0
    for gi, (gname, verts, mtl) in enumerate(egg, 1):
        pts = [v[i - 1] for i in verts]
        xs, ys, zs = zip(*pts)
        mnx, mxx, mny, mxy, mnz, mxz = min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)
        cx, cy, cz = (mnx + mxx) / 2, (mny + mxy) / 2, (mnz + mxz) / 2
        sx, sy, sz = mxx - mnx, mxy - mny, mxz - mnz
        r, g, b = colors.get(mtl, (0.5, 0.5, 0.5))
        if egg_i == 8:  # keep the approved Horned brighten baked in
            for pref, rgb in HORNED_BRIGHT.items():
                if gname.startswith(pref):
                    r, g, b = rgb
        piece = (
            f'prim("{egg_names[egg_i]}", "{gname}_{gi}", "{shape_for(gname, sx, sy, sz, shell_ex)}", '
            f"{sx:.3f},{sy:.3f},{sz:.3f}, {r:.4f},{g:.4f},{b:.4f}, {cx:.3f},{cy:.3f},{cz:.3f})\n"
        )
        if len(body) + len(piece) > MAX_CHUNK and body:
            p = OUT / f"egg{egg_i}_prim{n_chunk}.lua"
            p.write_text(HEADER + body + FOOTER)
            manifest.append(f"{p.name}: {n_groups} groups")
            body, n_chunk, n_groups = "", n_chunk + 1, 0
        body += piece
        n_groups += 1
    if body:
        p = OUT / f"egg{egg_i}_prim{n_chunk}.lua"
        p.write_text(HEADER + body + FOOTER)
        manifest.append(f"{p.name}: {n_groups} groups")

print("\n".join(manifest))
