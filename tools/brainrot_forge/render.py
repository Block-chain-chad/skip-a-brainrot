"""render.py — software previews of the BAKED faces (exactly what Roblox will draw).

Orthographic front-quarter view along the game's own thumbnail direction
(BrainrotThumb.DEFAULT_DIR), painter's algorithm, one flat shade per face normal.
Two views per model: a close-up and a "plot tile" where the body is drawn at the
pixel height it has on screen at gameplay distance, so silhouettes are judged where
they are actually seen. Verifying offline, before any import, is a project rule.
"""
from __future__ import annotations

import math
import re
from pathlib import Path

from PIL import Image, ImageDraw

from .bake import Mesh
from .voxel import VoxelModel

DEFAULT_DIR = (0.9, 0.45, -1.0)
PX_PER_STUD_AT_PLOT = 19.3     # 1080 px / (2 * 40 studs * tan(35 deg))
PLOT_FIT_STUDS = 6.0           # BrainrotSpawner.MODEL_HEIGHT
SKY = (196, 224, 240)


def _norm(v):
    length = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / length for c in v)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def _hex_rgb(h: str):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _triangles(model: VoxelModel, meshes: dict[str, Mesh]):
    for role, mesh in meshes.items():
        rgb = _hex_rgb(model.palette[role])
        for i in range(0, len(mesh.indices), 3):
            ids = mesh.indices[i:i + 3]
            colour = rgb
            if mesh.colors is not None:
                k = mesh.colors[ids[0]]
                colour = (rgb[0] * k[0], rgb[1] * k[1], rgb[2] * k[2])
            yield [mesh.positions[j] for j in ids], mesh.normals[ids[0]], colour


def _project(model, meshes, size_px, height_px=None, dir=DEFAULT_DIR):
    """Returns (draw list sorted far->near, scale). height_px pins the projected
    model height; otherwise the model is fit into size_px with a margin."""
    d = _norm(dir)                      # centre -> camera
    f = tuple(-c for c in d)            # camera forward
    r = _norm(_cross(f, (0.0, 1.0, 0.0)))
    u = _cross(r, f)
    light = _norm((d[0] + 0.3, d[1] + 0.8, d[2]))
    tris = list(_triangles(model, meshes))
    pts = [p for t, _, _ in tris for p in t]
    cx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2
    cy = (min(p[1] for p in pts) + max(p[1] for p in pts)) / 2
    cz = (min(p[2] for p in pts) + max(p[2] for p in pts)) / 2
    proj = []
    for t, n, rgb in tris:
        sp = []
        for p in t:
            rel = (p[0] - cx, p[1] - cy, p[2] - cz)
            sp.append((_dot(rel, r), _dot(rel, u), _dot(rel, f)))
        shade = 0.45 + 0.55 * max(0.0, _dot(n, light))
        proj.append((sum(p[2] for p in sp) / 3, sp, tuple(int(c * shade) for c in rgb)))
    proj.sort(key=lambda e: -e[0])
    ys = [p[1] for _, sp, _ in proj for p in sp]
    if height_px is None:
        ext = max(max(abs(p[0]) for _, sp, _ in proj for p in sp), max(abs(y) for y in ys))
        scale = (size_px * 0.42) / ext
    else:
        # pin the PROJECTED extent (the camera has pitch, so this is a little more
        # than the stud height) to height_px: what is drawn is exactly that tall
        scale = height_px / (max(ys) - min(ys))
    return proj, scale


def _paint(proj, scale, size_px):
    img = Image.new("RGB", (size_px, size_px), SKY)
    draw = ImageDraw.Draw(img)
    ox, oy = size_px / 2, size_px / 2
    for _, sp, colour in proj:
        draw.polygon([(ox + x * scale, oy - y * scale) for x, y, _ in sp], fill=colour)
    return img


def render_model(model: VoxelModel, meshes: dict[str, Mesh], size: int = 512, dir=DEFAULT_DIR) -> Image.Image:
    proj, scale = _project(model, meshes, size, dir=dir)
    return _paint(proj, scale, size)


def render_plot_tile(model: VoxelModel, meshes: dict[str, Mesh], tile=(200, 200)) -> Image.Image:
    """The body at its on-screen height from a pad: the spawner fits it to
    PLOT_FIT_STUDS * HeightScale studs; at 40 studs that is PX_PER_STUD_AT_PLOT px per stud."""
    height_px = PLOT_FIT_STUDS * model.height_scale * PX_PER_STUD_AT_PLOT
    proj, scale = _project(model, meshes, tile[0], height_px=height_px)
    img = _paint(proj, scale, tile[0])
    return img.crop((0, 0, tile[0], tile[1]))


def _drawn_height(img: Image.Image) -> int:
    rows = [y for y in range(img.height) if any(img.getpixel((x, y)) != SKY for x in range(img.width))]
    return (max(rows) - min(rows) + 1) if rows else 0


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def contact_sheet(batch, out_dir) -> list[Path]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    rows = []
    for model, meshes in batch:
        close = render_model(model, meshes, 512)
        tile = render_plot_tile(model, meshes)
        row = Image.new("RGB", (512 + 220, 512), SKY)
        row.paste(close, (0, 0))
        row.paste(tile, (522, 156))
        ImageDraw.Draw(row).text((526, 120), f"{model.name} ({model.rarity}) at pad distance", fill=(20, 20, 30))
        p = out_dir / f"{slug(model.name)}.png"
        row.save(p)
        paths.append(p)
        rows.append(row)
    sheet = Image.new("RGB", (732, 512 * len(rows)), SKY)
    for i, row in enumerate(rows):
        sheet.paste(row, (0, 512 * i))
    p = out_dir / "contact_sheet.png"
    sheet.save(p)
    paths.append(p)
    return paths


def compare_sheet(pairs, out_dir, prefix: str, per_sheet: int = 6) -> list[Path]:
    """Rows of before (exact colours) | after (representative colours) | after at pad distance."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for s in range(0, len(pairs), per_sheet):
        chunk = pairs[s:s + per_sheet]
        sheet = Image.new("RGB", (300 + 300 + 220, 300 * len(chunk)), SKY)
        d = ImageDraw.Draw(sheet)
        for i, (bm, bk, am, ak) in enumerate(chunk):
            y = 300 * i
            sheet.paste(render_model(bm, bk, 300), (0, y))
            sheet.paste(render_model(am, ak, 300), (300, y))
            sheet.paste(render_plot_tile(am, ak), (610, y + 50))
            d.text((6, y + 4), f"{am.name}: BEFORE (parts, exact)", fill=(20, 20, 30))
            d.text((306, y + 4), "AFTER (mesh, flat colours = worst case)", fill=(20, 20, 30))
            d.text((614, y + 30), "pad distance", fill=(20, 20, 30))
        p = out_dir / f"{prefix}_sheet{s // per_sheet + 1}.png"
        sheet.save(p)
        paths.append(p)
    return paths
