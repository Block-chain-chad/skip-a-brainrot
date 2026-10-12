"""Convert eggs 6-10 of eggs_forest_set.obj into Luau data chunk files.

Each output file is a self-contained execute_luau script that appends group
records to a staging ModuleScript-backed table via _G (no persistence needed:
each chunk BUILDS its groups immediately via EditableMesh and parents the
resulting MeshParts under ServerStorage.EggMeshStaging.<eggName>).

Groups are emitted with vertices RELATIVE to the group centroid; the chunk
script pivots each built MeshPart to the centroid so the egg reassembles
exactly. Colors come from the MTL Kd values.

Usage: python obj_to_luau.py [--pilot]
  --pilot: emit only egg6's first stud group as pilot.lua
"""
import re
import sys
from pathlib import Path

BASE = Path(__file__).parent
SRC = BASE / "eggs_forest_set.obj"
MTL = BASE / "eggs_forest_set.mtl"
OUT = BASE / "luau_chunks"
OUT.mkdir(exist_ok=True)

# --- MTL colors ---
colors = {}
cur = None
for line in MTL.read_text().splitlines():
    s = line.strip()
    if s.startswith("newmtl "):
        cur = s.split(None, 1)[1]
    elif s.startswith("Kd ") and cur:
        r, g, b = (float(x) for x in s.split()[1:4])
        colors[cur] = (r, g, b)

# --- parse OBJ ---
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
                curg = (name, [], cur_mtl)
        elif s.startswith("usemtl "):
            cur_mtl = s.split(None, 1)[1]
            if curg and not curg[1]:
                curg = (curg[0], curg[1], cur_mtl)
        elif s.startswith("f ") and curg is not None:
            idx = []
            for t in s.split()[1:]:
                i = int(t.split("/")[0])
                if i < 0:
                    i = len(v) + 1 + i
                idx.append(i)
            for k in range(1, len(idx) - 1):        # fan-triangulate
                curg[1].append((idx[0], idx[k], idx[k + 1]))
    close(curg)

assert len(clusters) == 10, len(clusters)

def group_luau(egg_name, gname, gi, tris, mtl):
    used = {}
    for t in tris:
        for i in t:
            if i not in used:
                used[i] = len(used) + 1
    order = sorted(used, key=used.get)
    cx = sum(v[i - 1][0] for i in order) / len(order)
    cy = sum(v[i - 1][1] for i in order) / len(order)
    cz = sum(v[i - 1][2] for i in order) / len(order)
    vparts = ",".join(
        f"{v[i-1][0]-cx:.3f},{v[i-1][1]-cy:.3f},{v[i-1][2]-cz:.3f}" for i in order
    )
    fparts = ",".join(f"{used[a]},{used[b]},{used[c]}" for a, b, c in tris)
    r, g, b = colors.get(mtl, (0.5, 0.5, 0.5))
    return (
        f'addGroup("{egg_name}", "{gname}_{gi}", {{{vparts}}}, {{{fparts}}}, '
        f"{r:.4f}, {g:.4f}, {b:.4f}, {cx:.3f}, {cy:.3f}, {cz:.3f})\n"
    )

HEADER = """-- egg mesh chunk (auto-generated). Builds groups via EditableMesh.
local AssetService = game:GetService("AssetService")
local staging = game.ServerStorage:FindFirstChild("EggMeshStaging")
if not staging then
	staging = Instance.new("Folder")
	staging.Name = "EggMeshStaging"
	staging.Parent = game.ServerStorage
end
local built, failed = 0, {}
local function addGroup(eggName, partName, verts, tris, r, g, b, cx, cy, cz)
	local ok, err = pcall(function()
		local em = AssetService:CreateEditableMesh()
		local ids = table.create(#verts / 3)
		for i = 1, #verts, 3 do
			ids[#ids + 1] = em:AddVertex(Vector3.new(verts[i], verts[i + 1], verts[i + 2]))
		end
		for i = 1, #tris, 3 do
			em:AddTriangle(ids[tris[i]], ids[tris[i + 1]], ids[tris[i + 2]])
		end
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		part.Name = partName
		part.Color = Color3.new(r, g, b)
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		local eggFolder = staging:FindFirstChild(eggName)
		if not eggFolder then
			eggFolder = Instance.new("Model")
			eggFolder.Name = eggName
			eggFolder.Parent = staging
		end
		part.CFrame = CFrame.new(cx, cy, cz)
		part.Parent = eggFolder
	end)
	if ok then built += 1 else table.insert(failed, partName .. ": " .. tostring(err)) end
end
"""

FOOTER = 'return "built " .. built .. ", failed " .. #failed .. (#failed > 0 and (": " .. table.concat(failed, " | ")) or "")\n'

if "--pilot" in sys.argv:
    egg6 = clusters[5]
    for gname, tris, mtl in egg6:
        if gname.startswith("stud"):
            (OUT / "pilot.lua").write_text(
                HEADER + group_luau("PilotTest", gname, 1, tris, mtl) + FOOTER
            )
            print(f"pilot.lua: group {gname}, {len(tris)} tris, mtl {mtl}")
            break
    sys.exit()

MAX_CHUNK = 120_000
egg_names = {6: "ForestEgg1", 7: "ForestEgg2", 8: "ForestEgg3", 9: "ForestEgg4", 10: "ForestEgg5"}
manifest = []
for egg_i in range(6, 11):
    egg = clusters[egg_i - 1]
    body, n_chunk, n_groups = "", 1, 0
    for gi, (gname, tris, mtl) in enumerate(egg, 1):
        piece = group_luau(egg_names[egg_i], gname, gi, tris, mtl)
        if len(body) + len(piece) > MAX_CHUNK and body:
            p = OUT / f"egg{egg_i}_chunk{n_chunk}.lua"
            p.write_text(HEADER + body + FOOTER)
            manifest.append(f"{p.name}: {n_groups} groups")
            body, n_chunk, n_groups = "", n_chunk + 1, 0
        body += piece
        n_groups += 1
    if body:
        p = OUT / f"egg{egg_i}_chunk{n_chunk}.lua"
        p.write_text(HEADER + body + FOOTER)
        manifest.append(f"{p.name}: {n_groups} groups")

print("\n".join(manifest))
print(f"total files: {len(manifest)}")
