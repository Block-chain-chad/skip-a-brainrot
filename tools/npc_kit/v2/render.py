"""render.py — study renders on top of npc_kit.preview's rasteriser: mesh lists -> panels,
depth-edge outlines (so form reads like a toon render), a projected skeleton overlay,
labels, and the sheet helpers the study composes with.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from npc_kit import preview as PV
from npc_kit.v2 import lowpoly as L

SKY = PV.SKY
PAPER = (244, 242, 236)
INK = PV.INK
VIEWS = {"front": (0, 0.12, -1), "back": (0, 0.12, 1), "left 3/4": (-1, 0.35, -1), "right 3/4": (1, 0.35, -1),
         "side": (1, 0.05, 0), "gameplay": (0.9, 0.45, -1.0)}

_FONT_CACHE: dict[int, ImageFont.ImageFont] = {}


def font(size: int = 14):
    if size not in _FONT_CACHE:
        try:
            _FONT_CACHE[size] = ImageFont.truetype("arial.ttf", size)
        except OSError:
            _FONT_CACHE[size] = ImageFont.load_default()
    return _FONT_CACHE[size]


def tris(meshes, tint=None) -> list[PV.Tri]:
    if meshes and isinstance(meshes[0], PV.Tri):
        if tint is None:
            return list(meshes)
        return [PV.Tri(t.verts, np.tile(np.array(tint, dtype=float), (len(t.verts), 1))) for t in meshes]
    out = []
    for m in meshes:
        if not len(m.faces):
            continue
        col = np.array(tint if tint is not None else m.color, dtype=float)
        out.append(PV.Tri(m.triangles(), np.tile(col, (len(m.faces), 1))))
    return out


def camera(cam_dir):
    d = np.array(cam_dir, dtype=float); d /= np.linalg.norm(d)
    f = -d
    r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return r, u, f


def project(points: np.ndarray, width: int, height: int, cam_dir, px_per_stud: float, center) -> np.ndarray:
    """Screen coordinates matching preview.render's orthographic camera."""
    r, u, f = camera(cam_dir)
    rel = np.asarray(points, dtype=float) - np.asarray(center, dtype=float)
    return np.column_stack([width / 2 + (rel @ r) * px_per_stud, height / 2 - (rel @ u) * px_per_stud])


def outline(img: Image.Image, depth: np.ndarray, threshold: float = 0.22, strength: float = 0.55) -> Image.Image:
    """Darken pixels where the depth buffer jumps (silhouettes and overlaps) — a cheap toon edge."""
    a = np.asarray(img).astype(float)
    d = depth.copy()
    d[~np.isfinite(d)] = 1e6
    edge = np.zeros(d.shape, dtype=bool)
    for dy, dx in ((0, 1), (1, 0)):
        diff = np.abs(np.diff(d, axis=0 if dy else 1))
        m = diff > threshold
        if dy:
            edge[:-1, :] |= m; edge[1:, :] |= m
        else:
            edge[:, :-1] |= m; edge[:, 1:] |= m
    # only draw the edge on the nearer side, and never on sky-to-sky
    near = d < 1e5
    edge &= near
    a[edge] *= (1 - strength)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


SHADOW = (150, 168, 176)


def shadow_disc(scene: list[PV.Tri], ground_y: float, color=SHADOW) -> PV.Tri | None:
    """A flat contact shadow under whatever stands near the ground (replaces a ground band,
    which does not project correctly under a tilted orthographic camera)."""
    allv = np.concatenate([t.verts.reshape(-1, 3) for t in scene])
    low = allv[allv[:, 1] < ground_y + 0.45]
    if len(low) == 0:
        return None
    cx, cz = (low[:, 0].min() + low[:, 0].max()) / 2, (low[:, 2].min() + low[:, 2].max()) / 2
    rx = (low[:, 0].max() - low[:, 0].min()) / 2 + 0.22
    rz = (low[:, 2].max() - low[:, 2].min()) / 2 + 0.22
    ring = L.ring_xz(L.superellipse(16, rx, rz, 2.0), ground_y + 0.004, ox=cx, oz=cz)
    centre = np.array([cx, ground_y + 0.004, cz])
    faces = np.array([[centre, ring[i], ring[(i + 1) % 16]] for i in range(16)])
    return PV.Tri(faces, np.tile(np.array(color, dtype=float), (16, 1)))


def render(meshes, width: int, height: int, view="front", px_per_stud: float | None = None, center=None,
           ground_y: float | None = 0.0, bg=SKY, edges: bool = True, tint=None, light=None) -> Image.Image:
    cam = VIEWS[view] if isinstance(view, str) else view
    scene = tris(meshes, tint)
    if ground_y is not None and scene:
        sh = shadow_disc(scene, ground_y)
        if sh is not None:
            scene = [sh] + scene
    im, depth = PV.render(scene, width, height, cam, px_per_stud=px_per_stud, center=center,
                          ground_y=None, bg=bg, light=light, return_depth=True)
    return outline(im, depth) if edges else im


def silhouette(meshes, width: int, height: int, view="front", px_per_stud=None, center=None, bg=PAPER, ink=(18, 18, 22)) -> Image.Image:
    """Solid black: every pixel the character covers becomes ink, whatever the shading."""
    im = render(meshes, width, height, view, px_per_stud, center, ground_y=None, bg=bg, edges=False, tint=(0, 0, 0))
    a = np.asarray(im)
    covered = np.any(a != np.array(bg, dtype=a.dtype), axis=2)
    out = np.empty_like(a)
    out[:] = bg
    out[covered] = ink
    return Image.fromarray(out)


def label(img: Image.Image, text: str, xy=(8, 6), size: int = 14, fill=INK) -> Image.Image:
    ImageDraw.Draw(img).text(xy, text, fill=fill, font=font(size))
    return img


def wrap(text: str, width_px: int, size: int) -> list[str]:
    f = font(size)
    out = []
    for para in text.split("\n"):
        line = ""
        for word in para.split(" "):
            trial = (line + " " + word).strip()
            if f.getlength(trial) > width_px and line:
                out.append(line)
                line = word
            else:
                line = trial
        out.append(line)
    return out


def caption(img: Image.Image, text: str, size: int = 14, pad: int = 8, bg=SKY) -> Image.Image:
    """Adds a word-wrapped caption strip below the image."""
    lines = wrap(text, img.width - 16, size)
    strip = Image.new("RGB", (img.width, pad * 2 + len(lines) * (size + 4)), bg)
    d = ImageDraw.Draw(strip)
    for i, line in enumerate(lines):
        d.text((8, pad + i * (size + 4)), line, fill=INK, font=font(size))
    return PV.stack([img, strip], bg=bg, pad=0)


def title(img: Image.Image, text: str, size: int = 20, bg=SKY) -> Image.Image:
    strip = Image.new("RGB", (img.width, size + 18), bg)
    ImageDraw.Draw(strip).text((10, 8), text, fill=INK, font=font(size))
    return PV.stack([strip, img], bg=bg, pad=0)


def overlay_skeleton(img: Image.Image, points: dict[str, np.ndarray], edges: list[tuple[str, str]], width: int, height: int,
                     cam_dir, px_per_stud: float, center, joint_color=(226, 90, 60), bone_color=(40, 44, 60)) -> Image.Image:
    names = list(points)
    P = project(np.array([points[n] for n in names]), width, height, cam_dir, px_per_stud, center)
    at = {n: tuple(P[i]) for i, n in enumerate(names)}
    d = ImageDraw.Draw(img)
    for a, b in edges:
        d.line([at[a], at[b]], fill=bone_color, width=3)
    for n, (x, y) in at.items():
        if ":" in n:
            continue
        r = 5 if n not in ("Root",) else 7
        d.ellipse([x - r, y - r, x + r, y + r], fill=joint_color, outline=(255, 255, 255), width=1)
    return img


stack = PV.stack
hstack = PV.hstack
save = PV.save


def grid(panels: list[Image.Image], cols: int, bg=SKY, pad: int = 8) -> Image.Image:
    rows = [hstack(panels[i:i + cols], bg=bg, pad=pad) for i in range(0, len(panels), cols)]
    return stack(rows, bg=bg, pad=pad)


def fit_scale(height_studs: float, panel_h: int, margin: float = 0.86) -> float:
    return panel_h * margin / height_studs
