"""bake.py — voxel cells -> flat-shaded meshes, ONE PER COLOUR ROLE.

Only faces exposed to air are emitted (a face against any other cell, same role
or not, is interior). Coplanar same-role faces are greedy-merged into rectangles;
each rectangle becomes 4 unshared vertices with one flat normal and 2 triangles,
so the voxel steps stay crisp. UVs are planar in studs / TILE_STUDS: the owner's
MaterialService.BrainrotTile holds 2 cells per texture at StudsPerTile 2, so this
makes the tile 1.0 stud on a mesh exactly as it is on a Part-built body.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .voxel import MAX_ROLES, Cell, VoxelModel

TILE_STUDS = 2.0
MAX_TRIS_MODEL = 8000
MAX_TRIS_ROLE = 2000

Vec3 = tuple[float, float, float]
FaceKey = tuple[int, int, int, str]  # (axis, sign, slice index, role)

_OTHER = {0: (1, 2), 1: (2, 0), 2: (0, 1)}  # axis -> (u axis, v axis)
_DIRS = ((0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1))


class BudgetError(ValueError):
    """The design is over the bake budget; nothing was exported."""


@dataclass
class Mesh:
    role: str
    positions: list[Vec3] = field(default_factory=list)
    normals: list[Vec3] = field(default_factory=list)
    uvs: list[tuple[float, float]] = field(default_factory=list)
    indices: list[int] = field(default_factory=list)
    colors: list[Vec3] | None = None   # per-vertex multiplier over the part colour (exact / representative); None = all 1

    @property
    def triangles(self) -> int:
        return len(self.indices) // 3

    def bounds(self) -> tuple[Vec3, Vec3]:
        xs = [p[0] for p in self.positions]
        ys = [p[1] for p in self.positions]
        zs = [p[2] for p in self.positions]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def exposed_faces(cells: dict[Cell, str]) -> dict[FaceKey, set[tuple[int, int]]]:
    out: dict[FaceKey, set[tuple[int, int]]] = {}
    for (x, y, z), role in cells.items():
        c = (x, y, z)
        for axis, sign in _DIRS:
            n = list(c)
            n[axis] += sign
            if tuple(n) in cells:
                continue
            ua, va = _OTHER[axis]
            out.setdefault((axis, sign, c[axis], role), set()).add((c[ua], c[va]))
    return out


def greedy_rects(grid: set[tuple[int, int]]) -> list[tuple[int, int, int, int]]:
    """Merge unit cells into maximal rectangles: grow along u, then along v while
    every cell of the next row is free. Deterministic (sorted scan)."""
    remaining = set(grid)
    rects: list[tuple[int, int, int, int]] = []
    for (u0, v0) in sorted(grid):
        if (u0, v0) not in remaining:
            continue
        w = 1
        while (u0 + w, v0) in remaining:
            w += 1
        h = 1
        while all((u0 + i, v0 + h) in remaining for i in range(w)):
            h += 1
        for i in range(w):
            for j in range(h):
                remaining.discard((u0 + i, v0 + j))
        rects.append((u0, v0, w, h))
    return rects


def _cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _quad(mesh: Mesh, axis: int, sign: int, k: int, rect: tuple[int, int, int, int], pitch: float) -> None:
    u0, v0, w, h = rect
    ua, va = _OTHER[axis]
    plane = (k + (1 if sign > 0 else 0)) * pitch
    uA, uB = u0 * pitch, (u0 + w) * pitch
    vA, vB = v0 * pitch, (v0 + h) * pitch
    normal = [0.0, 0.0, 0.0]
    normal[axis] = float(sign)
    n: Vec3 = (normal[0], normal[1], normal[2])
    corners = []
    for (u, v) in ((uA, vA), (uB, vA), (uB, vB), (uA, vB)):
        p = [0.0, 0.0, 0.0]
        p[axis] = plane
        p[ua] = u
        p[va] = v
        corners.append(((round(p[0], 6), round(p[1], 6), round(p[2], 6)),
                        (round(u / TILE_STUDS, 6), round(v / TILE_STUDS, 6))))
    if _dot(_cross(_sub(corners[1][0], corners[0][0]), _sub(corners[2][0], corners[0][0])), n) < 0:
        corners = [corners[0], corners[3], corners[2], corners[1]]
    base = len(mesh.positions)
    for pos, uv in corners:
        mesh.positions.append(pos)
        mesh.normals.append(n)
        mesh.uvs.append(uv)
    mesh.indices.extend((base, base + 1, base + 2, base, base + 2, base + 3))


def bake(model: VoxelModel) -> dict[str, Mesh]:
    if len(model.palette) > MAX_ROLES:
        raise BudgetError(f"{model.name}: too many roles ({len(model.palette)} > {MAX_ROLES})")
    meshes: dict[str, Mesh] = {}
    for (axis, sign, k, role), grid in sorted(exposed_faces(model.cells).items()):
        mesh = meshes.setdefault(role, Mesh(role))
        for rect in greedy_rects(grid):
            _quad(mesh, axis, sign, k, rect, model.pitch)
    total = 0
    for role, mesh in meshes.items():
        if mesh.triangles > MAX_TRIS_ROLE:
            raise BudgetError(f"{model.name}: role {role!r} has {mesh.triangles} triangles > {MAX_TRIS_ROLE}")
        total += mesh.triangles
    if total > MAX_TRIS_MODEL:
        raise BudgetError(f"{model.name}: {total} triangles > {MAX_TRIS_MODEL}")
    return dict(sorted(meshes.items()))


def triangle_report(meshes: dict[str, Mesh]) -> dict[str, int]:
    return {role: m.triangles for role, m in meshes.items()}
