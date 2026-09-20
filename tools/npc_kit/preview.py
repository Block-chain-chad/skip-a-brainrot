"""preview.py — rendered previews of what NpcForge builds, without Studio.

The harness builds the model (mesh body from forge_npc + blockout pieces + face
parts) exactly as NpcForge would in Edit mode; this walks the resulting instance
tree and rasterises it with a small numpy Z-buffer (flat shading, orthographic
cameras) — no painter's artefacts where hats meet heads.

Views: front / back / left ¾ / right ¾, a gameplay-distance tile at the forge's
own 19.3 px-per-stud (40 studs, 70° fov on 1080p), and a side-by-side with an
approximate Roblox R15 blocky reference for scale.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from npc_kit import forge_npc as F

SKY = (198, 222, 236)
GROUND = (172, 182, 160)
INK = (28, 30, 40)
PX_PER_STUD_AT_40 = 19.3   # brainrot_forge.render.PX_PER_STUD_AT_PLOT


# ===== geometry helpers ========================================================
def _cf_to_np(cf):
    R = cf.R
    M = np.array([[R[1], R[2], R[3]], [R[4], R[5], R[6]], [R[7], R[8], R[9]]], dtype=float)
    p = np.array([cf.p.X, cf.p.Y, cf.p.Z], dtype=float)
    return M, p


def _box(size):
    sx, sy, sz = (s / 2 for s in size)
    v = np.array([[-sx, -sy, -sz], [sx, -sy, -sz], [sx, sy, -sz], [-sx, sy, -sz],
                  [-sx, -sy, sz], [sx, -sy, sz], [sx, sy, sz], [-sx, sy, sz]], dtype=float)
    faces = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
             (3, 7, 6), (3, 6, 2), (0, 4, 7), (0, 7, 3), (1, 2, 6), (1, 6, 5)]
    return v, np.array(faces)


def _cylinder(size, n=14):
    """Roblox Cylinder: axis along X, diameter = min(Y, Z)."""
    L = size[0] / 2
    ry, rz = size[1] / 2, size[2] / 2
    ring = [(math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n)) for i in range(n)]
    v = [[-L, ry * c, rz * s] for c, s in ring] + [[L, ry * c, rz * s] for c, s in ring] + [[-L, 0, 0], [L, 0, 0]]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(i, j, n + j), (i, n + j, n + i), (2 * n, j, i), (2 * n + 1, n + i, n + j)]
    return np.array(v, dtype=float), np.array(faces)


def _ball(size, n=10, m=7):
    rx, ry, rz = (s / 2 for s in size)
    v, faces = [], []
    for a in range(m + 1):
        th = math.pi * a / m
        for b in range(n):
            ph = 2 * math.pi * b / n
            v.append([rx * math.sin(th) * math.cos(ph), ry * math.cos(th), rz * math.sin(th) * math.sin(ph)])
    for a in range(m):
        for b in range(n):
            i0, i1 = a * n + b, a * n + (b + 1) % n
            j0, j1 = i0 + n, i1 + n
            faces += [(i0, j0, j1), (i0, j1, i1)]
    return np.array(v, dtype=float), np.array(faces)


@dataclass
class Tri:
    verts: np.ndarray   # (N, 3, 3) world positions
    colors: np.ndarray  # (N, 3) 0..255


def _color(c3):
    return np.array([c3.R * 255, c3.G * 255, c3.B * 255], dtype=float)


def scene_from_model(H, model, segment_meshes: dict[str, F.SegmentResult] | None = None, only=None, tint=None) -> list[Tri]:
    """Triangles for every visible BasePart of a harness-built model. MeshParts use
    the baked segment mesh (scaled to the part's Size); Parts use their Shape."""
    out = []
    for d in H.descendants(model):
        if not d.IsA(d, "BasePart") or d.Transparency >= 1:
            continue
        if only is not None and not only(d):
            continue
        M, p = _cf_to_np(d.CFrame)
        size = (d.Size.X, d.Size.Y, d.Size.Z)
        seg = d.Name.replace("Left", "").replace("Right", "")
        if d.ClassName == "MeshPart" and segment_meshes and seg in segment_meshes:
            r = segment_meshes[seg]
            scale = np.array([size[i] / r.bbox_size[i] for i in range(3)])
            v = np.array(r.mesh.positions, dtype=float) * scale
            idx = np.array(r.mesh.indices, dtype=int).reshape(-1, 3)
        else:
            shape = getattr(d.Shape, "Name", "Block") if d.Shape is not None else "Block"
            if shape == "Cylinder":
                v, idx = _cylinder(size)
            elif shape == "Ball":
                v, idx = _ball(size)
            else:
                v, idx = _box(size)
        world = v @ M.T + p
        tri = world[idx]
        col = np.tile(tint if tint is not None else _color(d.Color), (len(idx), 1))
        out.append(Tri(tri, col))
    return out


# ===== rasteriser ==============================================================
def render(tris: list[Tri], width: int, height: int, cam_dir, px_per_stud: float | None = None,
           center=None, ground_y: float | None = None, light=None, bg=SKY, return_depth: bool = False):
    """Orthographic camera looking along -cam_dir (cam_dir = scene -> camera)."""
    if not tris:
        im = Image.new("RGB", (width, height), bg)
        return (im, np.full((height, width), np.inf)) if return_depth else im
    d = np.array(cam_dir, dtype=float); d /= np.linalg.norm(d)
    f = -d
    r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    L = np.array(light if light is not None else [d[0] + 0.4, d[1] + 0.9, d[2] - 0.2], dtype=float); L /= np.linalg.norm(L)
    allv = np.concatenate([t.verts.reshape(-1, 3) for t in tris])
    c = np.array(center, dtype=float) if center is not None else (allv.min(0) + allv.max(0)) / 2
    rel = allv - c
    xs, ys = rel @ r, rel @ u
    if px_per_stud is None:
        ext = max(xs.max() - xs.min(), ys.max() - ys.min())
        px_per_stud = min(width, height) * 0.86 / max(ext, 1e-6)
    zbuf = np.full((height, width), np.inf)
    img = np.zeros((height, width, 3), dtype=float)
    img[:, :] = bg
    if ground_y is not None:
        gy = int(round(height / 2 - (ground_y - c[1]) * px_per_stud * u[1]))
        gy = max(0, min(height, gy))
        img[gy:, :] = GROUND
    ox, oy = width / 2, height / 2
    for t in tris:
        V = t.verts
        relv = V - c
        sx = ox + (relv @ r) * px_per_stud
        sy = oy - (relv @ u) * px_per_stud
        sz = relv @ f                          # distance along the camera's forward: smaller = nearer
        e1 = V[:, 1] - V[:, 0]
        e2 = V[:, 2] - V[:, 0]
        n = np.cross(e1, e2)
        nl = np.linalg.norm(n, axis=1, keepdims=True)
        n = n / np.where(nl == 0, 1, nl)
        shade = 0.42 + 0.58 * np.clip(n @ L, 0, 1)
        cols = t.colors * shade[:, None]
        for i in range(len(V)):
            x0, x1 = int(max(0, math.floor(sx[i].min()))), int(min(width - 1, math.ceil(sx[i].max())))
            y0, y1 = int(max(0, math.floor(sy[i].min()))), int(min(height - 1, math.ceil(sy[i].max())))
            if x1 < x0 or y1 < y0:
                continue
            X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            ax, ay, bx, by, cx, cy = sx[i][0], sy[i][0], sx[i][1], sy[i][1], sx[i][2], sy[i][2]
            det = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
            if abs(det) < 1e-9:
                continue
            w0 = ((bx - X) * (cy - Y) - (cx - X) * (by - Y)) / det
            w1 = ((cx - X) * (ay - Y) - (ax - X) * (cy - Y)) / det
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not inside.any():
                continue
            depth = w0 * sz[i][0] + w1 * sz[i][1] + w2 * sz[i][2]
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            mask = inside & (depth < sub)
            sub[mask] = depth[mask]
            img[y0:y1 + 1, x0:x1 + 1][mask] = cols[i]
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    return (out, zbuf) if return_depth else out


# ===== reference figure ========================================================
def reference_avatar(H, x_offset=0.0):
    """Approximate Roblox R15 blocky proportions (5.0 studs, 2-stud shoulders) as a
    scale reference — labelled approximate, not an asset from the place."""
    I = H.stub.Instance
    V3, CF, C3 = H.stub.Vector3, H.stub.CFrame, H.stub.Color3
    m = I.new("Model"); m.Name = "R15Reference"
    blue, yellow, green, grey = C3.fromRGB(0, 100, 160), C3.fromRGB(235, 190, 70), C3.fromRGB(110, 170, 80), C3.fromRGB(160, 160, 165)
    spec = [("Head", (1.2, 1.2, 1.2), (0, 4.4, 0), yellow), ("UpperTorso", (2, 1.6, 1), (0, 3.0, 0), blue),
            ("LowerTorso", (2, 0.4, 1), (0, 2.0, 0), blue),
            ("RightArm", (1, 2, 1), (1.5, 2.8, 0), yellow), ("LeftArm", (1, 2, 1), (-1.5, 2.8, 0), yellow),
            ("RightLeg", (1, 1.8, 1), (0.5, 0.9, 0), green), ("LeftLeg", (1, 1.8, 1), (-0.5, 0.9, 0), green)]
    for name, size, pos, col in spec:
        p = I.new("Part"); p.Name = name; p.Size = V3.new(*size); p.CFrame = CF.new(pos[0] + x_offset, pos[1], pos[2]); p.Color = col; p.Parent = m
    m.PrimaryPart = m.FindFirstChild(m, "LowerTorso")
    return m


# ===== sheets ==================================================================
VIEWS = [("front", (0, 0.12, -1)), ("back", (0, 0.12, 1)), ("left 3/4", (-1, 0.35, -1)), ("right 3/4", (1, 0.35, -1))]


def _label(img, text, xy=(6, 4)):
    ImageDraw.Draw(img).text(xy, text, fill=INK)
    return img


def turnaround(tris, size=360, ground_y=0.0, label_prefix=""):
    panels = []
    for name, d in VIEWS:
        im = render(tris, size, size, d, ground_y=ground_y)
        panels.append(_label(im, f"{label_prefix}{name}"))
    sheet = Image.new("RGB", (size * len(panels), size), SKY)
    for i, im in enumerate(panels):
        sheet.paste(im, (i * size, 0))
    return sheet


def gameplay_tile(tris, studs=40.0, w=420, h=300, ground_y=0.0):
    """Orthographic at the pixel scale of a 70-deg camera at `studs` on 1080p."""
    pps = PX_PER_STUD_AT_40 * (40.0 / studs)
    im = render(tris, w, h, (0.9, 0.45, -1.0), px_per_stud=pps, ground_y=ground_y)
    return _label(im, f"gameplay distance ~{int(studs)} studs ({pps:.1f} px/stud)")


def silhouette(tris, size=360):
    black = [Tri(t.verts, np.zeros_like(t.colors)) for t in tris]
    im = render(black, size, size, (0, 0.12, -1), bg=(240, 240, 236))
    return _label(im, "silhouette")


def stack(rows: list[Image.Image], bg=SKY, pad=8) -> Image.Image:
    w = max(r.width for r in rows)
    h = sum(r.height for r in rows) + pad * (len(rows) - 1)
    out = Image.new("RGB", (w, h), bg)
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height + pad
    return out


def hstack(items: list[Image.Image], bg=SKY, pad=8) -> Image.Image:
    w = sum(i.width for i in items) + pad * (len(items) - 1)
    h = max(i.height for i in items)
    out = Image.new("RGB", (w, h), bg)
    x = 0
    for i in items:
        out.paste(i, (x, 0))
        x += i.width + pad
    return out


def save(img: Image.Image, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    return path
