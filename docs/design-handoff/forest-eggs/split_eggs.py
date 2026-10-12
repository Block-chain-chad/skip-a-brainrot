"""Split eggs_forest_set.obj: extract eggs 6-10, one `o` object per group.

The source OBJ uses `g`/`o` group markers that Roblox's Import 3D merges into
a single MeshPart. Rewriting every group as its own `o` object (with a unique
egg-prefixed name) makes the importer produce one MeshPart per group, which
Task 6 needs (shard/drip/crown decorations animate separately).

OBJ v/vt/vn indices are file-global, so extracted faces are re-indexed.
Output: eggs_forest_6to10.obj beside the source, same mtllib.
"""
import re
from pathlib import Path

SRC = Path(__file__).parent / "eggs_forest_set.obj"
DST = Path(__file__).parent / "eggs_forest_6to10.obj"

v, vt, vn = [], [], []          # global vertex data, 1-indexed by position
clusters = []                    # list of eggs; each = list of (groupname, [facelines], usemtl-at-start)
cur_group = None                 # (name, faces:list[str], mtl:str)
cur_mtl = None
mtllib = None

def close_group():
    global cur_group
    if cur_group and cur_group[1]:
        clusters[-1].append(cur_group)
    cur_group = None

with SRC.open() as f:
    for line in f:
        s = line.strip()
        if s.startswith("mtllib "):
            mtllib = s.split(None, 1)[1]
        elif s.startswith("v "):
            v.append(s)
        elif s.startswith("vt "):
            vt.append(s)
        elif s.startswith("vn "):
            vn.append(s)
        elif s.startswith(("o ", "g ")):
            name = s.split(None, 1)[1]
            close_group()
            if name == "shell_body":
                clusters.append([])          # a new egg starts at each shell_body
            if clusters:                     # ignore anything before the first egg
                cur_group = (name, [], cur_mtl)
        elif s.startswith("usemtl "):
            cur_mtl = s.split(None, 1)[1]
            if cur_group and not cur_group[1]:
                cur_group = (cur_group[0], cur_group[1], cur_mtl)
        elif s.startswith("f ") and cur_group is not None:
            cur_group[1].append(s)
    close_group()

assert len(clusters) == 10, f"expected 10 eggs, found {len(clusters)}"
picked = clusters[5:10]          # eggs 6..10 (0-indexed 5..9)

# Re-index: collect used indices per stream, remap to 1..n
FACE_TOKEN = re.compile(r"(-?\d+)(?:/(-?\d*)(?:/(-?\d+))?)?")

used_v, used_vt, used_vn = {}, {}, {}
def remap(idx_str, used, total):
    if not idx_str:
        return ""
    i = int(idx_str)
    if i < 0:
        i = total + 1 + i        # negative indices are relative
    if i not in used:
        used[i] = len(used) + 1
    return str(used[i])

out_faces = []                   # (eggnum, groupname, mtl, [remapped face lines])
for egg_i, egg in enumerate(picked, start=6):
    for gname, faces, mtl in egg:
        lines = []
        for face in faces:
            toks = face.split()[1:]
            new_toks = []
            for t in toks:
                m = FACE_TOKEN.fullmatch(t)
                a = remap(m.group(1), used_v, len(v))
                b = remap(m.group(2), used_vt, len(vt)) if m.group(2) else ""
                c = remap(m.group(3), used_vn, len(vn)) if m.group(3) else ""
                if c:
                    new_toks.append(f"{a}/{b}/{c}")
                elif b:
                    new_toks.append(f"{a}/{b}")
                else:
                    new_toks.append(a)
            lines.append("f " + " ".join(new_toks))
        out_faces.append((egg_i, gname, mtl, lines))

with DST.open("w") as f:
    f.write("# eggs 6-10 extracted from eggs_forest_set.obj, one o-object per group\n")
    if mtllib:
        f.write(f"mtllib {mtllib}\n")
    for i in sorted(used_v, key=used_v.get):
        f.write(v[i - 1] + "\n")
    for i in sorted(used_vt, key=used_vt.get):
        f.write(vt[i - 1] + "\n")
    for i in sorted(used_vn, key=used_vn.get):
        f.write(vn[i - 1] + "\n")
    for egg_i, gname, mtl, lines in out_faces:
        f.write(f"o egg{egg_i}_{gname}\n")
        if mtl:
            f.write(f"usemtl {mtl}\n")
        f.write("\n".join(lines) + "\n")

n_objects = len(out_faces)
n_faces = sum(len(x[3]) for x in out_faces)
print(f"wrote {DST.name}: {n_objects} o-objects, {len(used_v)} verts, {n_faces} faces")
per_egg = {}
for egg_i, gname, _, lines in out_faces:
    per_egg.setdefault(egg_i, [0, 0])
    per_egg[egg_i][0] += 1
    per_egg[egg_i][1] += len(lines)
for k in sorted(per_egg):
    print(f"  egg{k}: {per_egg[k][0]} groups, {per_egg[k][1]} faces")
