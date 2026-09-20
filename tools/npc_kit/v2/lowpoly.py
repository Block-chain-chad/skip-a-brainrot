"""lowpoly.py — a small procedural low-poly mesh toolkit for the V2 character study.

Everything here builds faceted meshes directly (lofts, extrusions, shards) instead of
voxel lattices, because authored shells want clean silhouettes at a few hundred
triangles each. Meshes are plain numpy (verts (N,3), faces (M,3) CCW-outward) and
convert to the forge's bake.Mesh for write_glb (one node per piece, flat-shaded).

Conventions match the SR-Rig: +Y up, -Z forward (the face), +X = the character's right.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

RGB = tuple[int, int, int]


# ===== mesh =====================================================================
@dataclass
class Mesh:
    verts: np.ndarray
    faces: np.ndarray
    color: RGB = (200, 200, 200)
    name: str = ""

    @property
    def tris(self) -> int:
        return int(len(self.faces))

    def copy(self) -> "Mesh":
        return Mesh(self.verts.copy(), self.faces.copy(), self.color, self.name)

    def transformed(self, M=None, p=None) -> "Mesh":
        v = self.verts
        if M is not None:
            v = v @ np.asarray(M, dtype=float).T
        if p is not None:
            v = v + np.asarray(p, dtype=float)
        return Mesh(v, self.faces.copy(), self.color, self.name)

    def translated(self, x=0.0, y=0.0, z=0.0) -> "Mesh":
        return self.transformed(p=(x, y, z))

    def rotated(self, rx=0.0, ry=0.0, rz=0.0) -> "Mesh":
        """Degrees, applied like CFrame.Angles (X, then Y, then Z about the origin)."""
        return self.transformed(M=angles(rx, ry, rz))

    def scaled(self, sx=1.0, sy=None, sz=None) -> "Mesh":
        sy = sx if sy is None else sy
        sz = sx if sz is None else sz
        return Mesh(self.verts * np.array([sx, sy, sz], dtype=float), self.faces.copy(), self.color, self.name)

    def mirrored_x(self) -> "Mesh":
        v = self.verts * np.array([-1.0, 1.0, 1.0])
        f = self.faces[:, [0, 2, 1]]          # a mirror flips handedness: re-wind to stay CCW outward
        return Mesh(v, f, self.color, self.name)

    def recolored(self, color: RGB, name: str | None = None) -> "Mesh":
        return Mesh(self.verts.copy(), self.faces.copy(), color, self.name if name is None else name)

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        return self.verts.min(0), self.verts.max(0)

    def size(self) -> np.ndarray:
        lo, hi = self.bounds()
        return hi - lo

    def centroid(self) -> np.ndarray:
        return self.verts.mean(0)

    def triangles(self) -> np.ndarray:
        """(M, 3, 3) world triangles — what the preview rasteriser eats."""
        return self.verts[self.faces]

    def face_normals(self) -> np.ndarray:
        t = self.triangles()
        n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
        l = np.linalg.norm(n, axis=1, keepdims=True)
        return n / np.where(l == 0, 1, l)

    def to_forge_mesh(self, role: str):
        """Flat-shaded bake.Mesh (vertices split per face) for brainrot_forge.export_glb.write_glb."""
        from brainrot_forge.bake import Mesh as ForgeMesh
        t = self.triangles()
        n = self.face_normals()
        positions = [tuple(map(float, p)) for tri in t for p in tri]
        normals = [tuple(map(float, nn)) for nn in n for _ in range(3)]
        uvs = [(0.0, 0.0)] * len(positions)
        return ForgeMesh(role=role, positions=positions, normals=normals, uvs=uvs, indices=list(range(len(positions))))


def merge(meshes: list[Mesh], color: RGB | None = None, name: str = "") -> Mesh:
    meshes = [m for m in meshes if m is not None and len(m.faces)]
    if not meshes:
        return Mesh(np.zeros((0, 3)), np.zeros((0, 3), dtype=int), color or (200, 200, 200), name)
    verts, faces, off = [], [], 0
    for m in meshes:
        verts.append(m.verts)
        faces.append(m.faces + off)
        off += len(m.verts)
    return Mesh(np.concatenate(verts), np.concatenate(faces), color or meshes[0].color, name or meshes[0].name)


# ===== rotations ================================================================
def rot_x(deg: float) -> np.ndarray:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=float)


def rot_y(deg: float) -> np.ndarray:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=float)


def rot_z(deg: float) -> np.ndarray:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=float)


def angles(rx=0.0, ry=0.0, rz=0.0) -> np.ndarray:
    """CFrame.Angles(rx, ry, rz): v' = Rx(Ry(Rz(v)))."""
    return rot_x(rx) @ rot_y(ry) @ rot_z(rz)


def align_y(direction) -> np.ndarray:
    """Rotation taking +Y onto `direction` (used to lay a cane along its grip line)."""
    d = np.asarray(direction, dtype=float); d /= np.linalg.norm(d)
    y = np.array([0.0, 1.0, 0.0])
    v = np.cross(y, d); s = np.linalg.norm(v); c = float(y @ d)
    if s < 1e-9:
        return np.eye(3) if c > 0 else rot_x(180)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * ((1 - c) / (s * s))


# ===== 2-D profiles =============================================================
def superellipse(n: int, rx: float, rz: float, p: float = 2.0, phase: float = 0.0) -> np.ndarray:
    """n points on |x/rx|^p + |z/rz|^p = 1 (p=2 ellipse, 4 rounded square, 8 near-square),
    ordered counter-clockwise seen from +Y. Returns (n, 2) as (x, z)."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n + phase
        c, s = math.cos(t), math.sin(t)
        pts.append((rx * math.copysign(abs(c) ** (2 / p), c), rz * math.copysign(abs(s) ** (2 / p), s)))
    return np.array(pts, dtype=float)


def wobble(pts2d: np.ndarray, amount: float, lobes: int, phase: float = 0.0) -> np.ndarray:
    """Radially modulate a ring for tufts / cloth folds (deterministic)."""
    out = pts2d.copy()
    n = len(pts2d)
    for i in range(n):
        t = 2 * math.pi * i / n
        out[i] *= 1 + amount * math.sin(lobes * t + phase)
    return out


def ring_xz(pts2d: np.ndarray, y: float, sx: float = 1.0, sz: float | None = None, ox: float = 0.0, oz: float = 0.0,
            ry: float = 0.0, tilt_x: float = 0.0, tilt_z: float = 0.0) -> np.ndarray:
    """Place a 2-D (x, z) profile as a 3-D ring at height y (horizontal cross-section).
    tilt_x / tilt_z: rotate the ring plane about X / Z (degrees) around its own centre."""
    sz = sx if sz is None else sz
    r = np.zeros((len(pts2d), 3))
    r[:, 0] = pts2d[:, 0] * sx
    r[:, 2] = pts2d[:, 1] * sz
    if ry:
        r = r @ rot_y(ry).T
    if tilt_x or tilt_z:
        r = r @ (rot_x(tilt_x) @ rot_z(tilt_z)).T
    r[:, 0] += ox
    r[:, 1] += y
    r[:, 2] += oz
    return r


def ring_xy(pts2d: np.ndarray, z: float, sx: float = 1.0, sy: float | None = None, ox: float = 0.0, oy: float = 0.0) -> np.ndarray:
    """Place a 2-D (x, y) profile as a vertical ring at depth z (cross-section of something
    that runs along Z, like a foot). Winding is flipped so lofts toward -Z stay outward."""
    sy = sx if sy is None else sy
    r = np.zeros((len(pts2d), 3))
    r[:, 0] = pts2d[:, 0] * sx + ox
    r[:, 1] = pts2d[:, 1] * sy + oy
    r[:, 2] = z
    return r


# ===== builders =================================================================
def _orient(verts: np.ndarray, faces: np.ndarray, refs: np.ndarray) -> np.ndarray:
    """Re-wind each face so its normal points away from its reference point."""
    t = verts[faces]
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    out = t.mean(1) - refs
    flip = (n * out).sum(1) < 0
    faces = faces.copy()
    faces[flip] = faces[flip][:, [0, 2, 1]]
    return faces


def loft(rings: list[np.ndarray], cap_bottom: bool = True, cap_top: bool = True, color: RGB = (200, 200, 200),
         name: str = "", closed: bool = True) -> Mesh:
    """Skin consecutive rings (same point count) with quads (2 tris each); caps are fans
    from the ring centre. Faces are oriented away from the local spine, so any convex-ish
    cross-section is outward-wound regardless of the rings' winding."""
    k = len(rings[0])
    assert all(len(r) == k for r in rings), "loft rings must share a point count"
    verts = [np.asarray(r, dtype=float) for r in rings]
    faces, refs = [], []
    for j in range(len(rings) - 1):
        a, b = j * k, (j + 1) * k
        spine = (verts[j].mean(0) + verts[j + 1].mean(0)) / 2
        for i in range(k if closed else k - 1):
            i2 = (i + 1) % k
            faces += [(a + i, a + i2, b + i2), (a + i, b + i2, b + i)]
            refs += [spine, spine]
    v = np.concatenate(verts)
    body_centre = v.mean(0)
    if cap_bottom:
        c = len(v); v = np.concatenate([v, verts[0].mean(0, keepdims=True)])
        for i in range(k if closed else k - 1):
            faces.append((c, i, (i + 1) % k)); refs.append(body_centre)
    if cap_top:
        c = len(v); v = np.concatenate([v, verts[-1].mean(0, keepdims=True)])
        base = (len(rings) - 1) * k
        for i in range(k if closed else k - 1):
            faces.append((c, base + i, base + (i + 1) % k)); refs.append(body_centre)
    f = _orient(v, np.array(faces, dtype=int), np.array(refs))
    return Mesh(v, f, color, name)


def tube(profile: np.ndarray, levels: list[tuple], color: RGB = (200, 200, 200), name: str = "",
         cap_bottom=True, cap_top=True) -> Mesh:
    """levels: (y, sx[, sz[, ox, oz]]) from bottom to top — a lofted, tapered limb / sleeve / shaft."""
    rings = []
    for lv in levels:
        y, sx = lv[0], lv[1]
        sz = lv[2] if len(lv) > 2 else sx
        ox = lv[3] if len(lv) > 3 else 0.0
        oz = lv[4] if len(lv) > 4 else 0.0
        rings.append(ring_xz(profile, y, sx, sz, ox, oz))
    return loft(rings, cap_bottom, cap_top, color, name)


def rounded_box(size, n: int = 8, p: float = 4.0, r_bottom: float = 0.18, r_top: float = 0.18,
                color: RGB = (200, 200, 200), name: str = "", taper_top: float = 1.0, taper_bottom: float = 1.0,
                shift_top=(0.0, 0.0), shift_bottom=(0.0, 0.0)) -> Mesh:
    """A chamfered block: superellipse rings, the end rings pulled in by r_* so the top and
    bottom edges read as bevels. taper_* scale the end rings (jaw, shoulder slope)."""
    w, h, d = size
    prof = superellipse(n, w / 2, d / 2, p)
    rb, rt = min(r_bottom, h * 0.45), min(r_top, h * 0.45)
    kb = max(0.35, 1 - rb / max(w, d) * 1.6)
    kt = max(0.35, 1 - rt / max(w, d) * 1.6)
    levels = [
        (-h / 2, kb * taper_bottom, kb * taper_bottom, shift_bottom[0], shift_bottom[1]),
        (-h / 2 + rb, taper_bottom, taper_bottom, shift_bottom[0] * 0.5, shift_bottom[1] * 0.5),
        (h / 2 - rt, taper_top, taper_top, shift_top[0] * 0.5, shift_top[1] * 0.5),
        (h / 2, kt * taper_top, kt * taper_top, shift_top[0], shift_top[1]),
    ]
    return tube(prof, levels, color, name)


def extrude(poly_xy: np.ndarray, depth: float, color: RGB = (200, 200, 200), name: str = "", z0: float | None = None) -> Mesh:
    """Extrude a 2-D polygon (x, y), CCW or CW, along Z; centred on z=0 unless z0 (back face) is given."""
    poly = np.asarray(poly_xy, dtype=float)
    k = len(poly)
    zb = -depth / 2 if z0 is None else z0
    zf = zb + depth
    back = np.column_stack([poly, np.full(k, zb)])
    front = np.column_stack([poly, np.full(k, zf)])
    v = np.concatenate([back, front])
    faces, refs = [], []
    cb, cf = back.mean(0), front.mean(0)
    centre = v.mean(0)
    # sides
    for i in range(k):
        i2 = (i + 1) % k
        faces += [(i, i2, k + i2), (i, k + i2, k + i)]
        refs += [centre, centre]
    # caps as fans (fine for convex / star-shaped outlines, which is all we draw)
    v = np.concatenate([v, cb[None], cf[None]])
    ib, if_ = 2 * k, 2 * k + 1
    for i in range(k):
        i2 = (i + 1) % k
        faces += [(ib, i, i2), (if_, k + i, k + i2)]
        refs += [centre, centre]
    f = _orient(v, np.array(faces, dtype=int), np.array(refs))
    return Mesh(v, f, color, name)


def shard(base: np.ndarray, tip, color: RGB = (200, 200, 200), name: str = "") -> Mesh:
    """A pyramid from a small polygon base to a tip — hair tufts, feathers, claws."""
    base = np.asarray(base, dtype=float)
    k = len(base)
    v = np.concatenate([base, np.asarray(tip, dtype=float)[None], base.mean(0)[None]])
    centre = v.mean(0)
    faces, refs = [], []
    for i in range(k):
        i2 = (i + 1) % k
        faces += [(i, i2, k), (k + 1, i, i2)]
        refs += [centre, centre]
    f = _orient(v, np.array(faces, dtype=int), np.array(refs))
    return Mesh(v, f, color, name)


def annulus(inner: np.ndarray, outer: np.ndarray, thickness: float, color: RGB = (200, 200, 200), name: str = "") -> Mesh:
    """A flat ring with thickness between two 3-D rings (hat brim, mantle, collar). Both
    rings may carry their own per-point heights (a pinned-up brim is just a lifted outer ring)."""
    k = len(inner)
    up = np.array([0, thickness, 0.0])
    ib, ob, it, ot = inner, outer, inner + up, outer + up
    v = np.concatenate([ib, ob, it, ot])
    faces, refs = [], []
    centre = v.mean(0)
    far = centre + np.array([0, -50.0, 0])
    high = centre + np.array([0, 50.0, 0])
    for i in range(k):
        i2 = (i + 1) % k
        # bottom face -> normal down; top face -> normal up; outer edge -> outward; inner edge -> inward
        faces += [(i, i2, k + i2), (i, k + i2, k + i)]; refs += [high, high]
        faces += [(2 * k + i, 2 * k + i2, 3 * k + i2), (2 * k + i, 3 * k + i2, 3 * k + i)]; refs += [far, far]
        faces += [(k + i, k + i2, 3 * k + i2), (k + i, 3 * k + i2, 3 * k + i)]; refs += [centre, centre]
        faces += [(i, i2, 2 * k + i2), (i, 2 * k + i2, 2 * k + i)]
        refs += [centre + (outer[i] - centre) * 4, centre + (outer[i] - centre) * 4]
    f = _orient(v, np.array(faces, dtype=int), np.array(refs))
    return Mesh(v, f, color, name)


def ellipsoid(size, n: int = 10, m: int = 6, color: RGB = (200, 200, 200), name: str = "") -> Mesh:
    rx, ry, rz = (s / 2 for s in size)
    prof = superellipse(n, 1.0, 1.0, 2.0)
    rings = []
    for a in range(1, m):
        th = math.pi * a / m
        rings.append(ring_xz(prof, ry * math.cos(th), rx * math.sin(th), rz * math.sin(th)))
    rings = [ring_xz(prof, ry * 0.98, rx * 0.12, rz * 0.12)] + rings[::-1] + [ring_xz(prof, -ry * 0.98, rx * 0.12, rz * 0.12)]
    return loft(rings, True, True, color, name)


def curved_bar(width: float, thick: float, curve: float, n: int = 5) -> np.ndarray:
    """Polygon (x, y) of a bar bent by `curve` (positive = ends up: a smile), for mouths / brows."""
    xs = np.linspace(-width / 2, width / 2, n)
    top = [(x, curve * (2 * x / width) ** 2 + thick / 2) for x in xs]
    bot = [(x, curve * (2 * x / width) ** 2 - thick / 2) for x in xs]
    return np.array(top + bot[::-1], dtype=float)


def tapered_bar(length: float, thick_a: float, thick_b: float, tilt: float = 0.0) -> np.ndarray:
    """Polygon (x, y) of a bar thicker at one end (brows), optionally tilted (degrees)."""
    pts = np.array([(-length / 2, -thick_a / 2), (length / 2, -thick_b / 2), (length / 2, thick_b / 2), (-length / 2, thick_a / 2)], dtype=float)
    if tilt:
        c, s = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
        pts = pts @ np.array([[c, s], [-s, c]])
    return pts


def budget(meshes: list[Mesh]) -> dict:
    return {"pieces": len(meshes), "triangles": int(sum(m.tris for m in meshes)),
            "vertices": int(sum(len(m.verts) for m in meshes))}
