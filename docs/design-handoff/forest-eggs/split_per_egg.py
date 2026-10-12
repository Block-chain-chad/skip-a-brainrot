"""Emit forest_egg_6.obj .. forest_egg_10.obj (one file per egg, groups kept).

Roblox's 3D importer fuses each FILE into one MeshPart (observed twice), so
one-file-per-egg yields exactly five clean fused egg meshes.
"""
import re
from pathlib import Path

src = Path(r"C:\Users\m\Coding\skip-a-brainrot\docs\design-handoff\forest-eggs\eggs_forest_set.obj")
outdir = Path(r"C:\Users\m\Downloads\Skip rocks for brainrots\Eggs desing skip rocks")

v, vt, vn = [], [], []
clusters, cur, cur_mtl, mtllib = [], None, None, None

def close(c):
    if c and c[1]:
        clusters[-1].append(c)

with src.open() as f:
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
            close(cur)
            cur = None
            if name == "shell_body":
                clusters.append([])
            if clusters:
                cur = (name, [], cur_mtl)
        elif s.startswith("usemtl "):
            cur_mtl = s.split(None, 1)[1]
            if cur and not cur[1]:
                cur = (cur[0], cur[1], cur_mtl)
        elif s.startswith("f ") and cur is not None:
            cur[1].append(s)
    close(cur)

assert len(clusters) == 10, len(clusters)
TOK = re.compile(r"(-?\d+)(?:/(-?\d*)(?:/(-?\d+))?)?")

for egg_i in range(6, 11):
    egg = clusters[egg_i - 1]
    uv, uvt, uvn = {}, {}, {}

    def rm(ix, used, tot):
        if not ix:
            return ""
        i = int(ix)
        if i < 0:
            i = tot + 1 + i
        if i not in used:
            used[i] = len(used) + 1
        return str(used[i])

    body = []
    for gname, faces, mtl in egg:
        body.append(f"o {gname}")
        if mtl:
            body.append(f"usemtl {mtl}")
        for face in faces:
            toks = []
            for t in face.split()[1:]:
                m = TOK.fullmatch(t)
                a = rm(m.group(1), uv, len(v))
                b = rm(m.group(2), uvt, len(vt)) if m.group(2) else ""
                c = rm(m.group(3), uvn, len(vn)) if m.group(3) else ""
                toks.append(a + ("/" + b if b or c else "") + ("/" + c if c else ""))
            body.append("f " + " ".join(toks))

    dst = outdir / f"forest_egg_{egg_i}.obj"
    with dst.open("w") as f:
        f.write(f"mtllib {mtllib}\n")
        for i in sorted(uv, key=uv.get):
            f.write(v[i - 1] + "\n")
        for i in sorted(uvt, key=uvt.get):
            f.write(vt[i - 1] + "\n")
        for i in sorted(uvn, key=uvn.get):
            f.write(vn[i - 1] + "\n")
        f.write("\n".join(body) + "\n")
    print(f"{dst.name}: {len(uv)} verts, {sum(len(g[1]) for g in egg)} faces, {len(egg)} groups")
