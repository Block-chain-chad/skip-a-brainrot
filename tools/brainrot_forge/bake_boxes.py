"""bake_boxes.py — axis-aligned boxes (a Part-built brainrot) -> per-role meshes, LOSSLESS.

Every box face is emitted unless it is fully covered by coplanar, opposite-facing faces of other
boxes (union coverage on a coordinate-compressed grid — exact). Faces are grouped into roles =
(colour cluster, material): at most `max_roles` per body, at most `max_neon` Neon roles. A role's
MeshPart colour is the per-channel MAX of its member colours and each vertex carries the ratio
exact / representative as COLOR_0, so the render is exact wherever the importer keeps vertex
colours and a flat representative where it does not. exact=True disables clustering (used for the
"before" render in the approval sheets).
"""
from __future__ import annotations

from dataclasses import dataclass

from .bake import BudgetError, Mesh, TILE_STUDS
from .ingest_parts import Box, PartModel, Vec3, bbox

_OTHER = {0: (1, 2), 1: (2, 0), 2: (0, 1)}
EPS = 1e-4


@dataclass
class Face:
    axis: int
    sign: int
    plane: float
    u0: float
    u1: float
    v0: float
    v1: float
    color: str
    material: str


@dataclass
class ConvertedModel:
    name: str
    rarity: str
    world: str
    palette: dict[str, str]
    materials: dict[str, str]
    meshes: dict[str, Mesh]
    attributes: dict
    fx: bool | None
    pose_rotation: tuple | None
    pose_centre: Vec3 | None
    vertex_colors: bool
    bounds: tuple[Vec3, Vec3]
    pitch: float = 0.2
    motion: str = "hover"
    material: str = "Plastic"

    @property
    def height_scale(self) -> float:
        return float(self.attributes.get("HeightScale", 1))

    @property
    def width_scale(self) -> float:
        return float(self.attributes.get("WidthScale", 1))

    def size_studs(self) -> tuple[float, float, float]:
        lo, hi = self.bounds
        return tuple(round(hi[i] - lo[i], 6) for i in range(3))  # type: ignore[return-value]


def faces(boxes: list[Box]) -> list[Face]:
    out = []
    for b in boxes:
        for axis in range(3):
            ua, va = _OTHER[axis]
            u0, u1 = b.pos[ua] - b.size[ua] / 2, b.pos[ua] + b.size[ua] / 2
            v0, v1 = b.pos[va] - b.size[va] / 2, b.pos[va] + b.size[va] / 2
            for sign in (1, -1):
                plane = b.pos[axis] + sign * b.size[axis] / 2
                out.append(Face(axis, sign, round(plane, 4), round(u0, 4), round(u1, 4), round(v0, 4), round(v1, 4), b.color, b.material))
    return out


def _covered(f: Face, others: list[Face]) -> bool:
    clipped = []
    for o in others:
        u0, u1 = max(f.u0, o.u0), min(f.u1, o.u1)
        v0, v1 = max(f.v0, o.v0), min(f.v1, o.v1)
        if u1 - u0 > EPS and v1 - v0 > EPS:
            clipped.append((u0, u1, v0, v1))
    if not clipped:
        return False
    us = sorted({f.u0, f.u1, *[c[0] for c in clipped], *[c[1] for c in clipped]})
    vs = sorted({f.v0, f.v1, *[c[2] for c in clipped], *[c[3] for c in clipped]})
    for i in range(len(us) - 1):
        cu = (us[i] + us[i + 1]) / 2
        if cu < f.u0 or cu > f.u1:
            continue
        for j in range(len(vs) - 1):
            cv = (vs[j] + vs[j + 1]) / 2
            if cv < f.v0 or cv > f.v1:
                continue
            if not any(c[0] <= cu <= c[1] and c[2] <= cv <= c[3] for c in clipped):
                return False
    return True


def cull_covered(all_faces: list[Face]) -> list[Face]:
    groups: dict[tuple[int, float, int], list[Face]] = {}
    for f in all_faces:
        groups.setdefault((f.axis, f.plane, f.sign), []).append(f)
    kept = []
    for f in all_faces:
        opposite = groups.get((f.axis, f.plane, -f.sign), [])
        if not _covered(f, opposite):
            kept.append(f)
    return kept


def _rgb(h: str) -> Vec3:
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))


def _hex(rgb) -> str:
    return "#%02X%02X%02X" % tuple(int(round(c)) for c in rgb)


def cluster_roles(kept: list[Face], max_roles: int, max_neon: int, exact: bool) -> dict[str, tuple[str, str, set[str]]]:
    """-> {role: (representative hex, material, member colours)}; roles named c00, c01, ... by area."""
    area: dict[tuple[str, str], float] = {}
    for f in kept:
        area[(f.color, f.material)] = area.get((f.color, f.material), 0) + (f.u1 - f.u0) * (f.v1 - f.v0)
    keys = sorted(area, key=lambda k: -area[k])
    by_mat: dict[str, list[tuple[str, str]]] = {}
    for k in keys:
        by_mat.setdefault(k[1], []).append(k)
    clusters: list[tuple[str, str, set[str]]] = []
    if exact or len(keys) <= max_roles and sum(1 for k in keys if k[1] == "Neon") <= max_neon:
        clusters = [(k[0], k[1], {k[0]}) for k in keys]
    else:
        # budget per material: proportional to its distinct colours, at least 1, Neon capped
        budget = {}
        remaining = max_roles
        mats = sorted(by_mat, key=lambda m: -len(by_mat[m]))
        for m in mats:
            budget[m] = 1
            remaining -= 1
        for m in mats:
            want = min(len(by_mat[m]), (max_neon if m == "Neon" else max_roles)) - budget[m]
            take = max(0, min(want, remaining))
            budget[m] += take
            remaining -= take
        for m in mats:
            colours = by_mat[m]
            reps = colours[: budget[m]]
            members: dict[tuple[str, str], set[str]] = {r: {r[0]} for r in reps}
            for k in colours[budget[m]:]:
                rgb = _rgb(k[0])
                nearest = min(reps, key=lambda r: sum((a - b) ** 2 for a, b in zip(rgb, _rgb(r[0]))))
                members[nearest].add(k[0])
            for r in reps:
                mem = members[r]
                rep_rgb = tuple(max(_rgb(c)[i] for c in mem) for i in range(3))
                clusters.append((_hex(rep_rgb), m, mem))
        clusters.sort(key=lambda c: -sum(area.get((col, c[1]), 0) for col in c[2]))
    return {f"c{i:02d}": c for i, c in enumerate(clusters)}


def _quad(mesh: Mesh, f: Face, ratio: Vec3 | None) -> None:
    ua, va = _OTHER[f.axis]
    n = [0.0, 0.0, 0.0]
    n[f.axis] = float(f.sign)
    corners = []
    for (u, v) in ((f.u0, f.v0), (f.u1, f.v0), (f.u1, f.v1), (f.u0, f.v1)):
        p = [0.0, 0.0, 0.0]
        p[f.axis] = f.plane
        p[ua] = u
        p[va] = v
        corners.append(((p[0], p[1], p[2]), (round(u / TILE_STUDS, 6), round(v / TILE_STUDS, 6))))
    a, b, c = corners[0][0], corners[1][0], corners[2][0]
    ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    cr = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
    if cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] < 0:
        corners = [corners[0], corners[3], corners[2], corners[1]]
    base = len(mesh.positions)
    for pos, uv in corners:
        mesh.positions.append(pos)
        mesh.normals.append((n[0], n[1], n[2]))
        mesh.uvs.append(uv)
        if mesh.colors is not None:
            mesh.colors.append(ratio or (1.0, 1.0, 1.0))
    mesh.indices.extend((base, base + 1, base + 2, base, base + 2, base + 3))


def bake_boxes(model: PartModel, max_roles: int = 12, max_neon: int = 3, exact: bool = False,
               max_tris_model: int = 12000, max_tris_role: int = 4000) -> ConvertedModel:
    kept = cull_covered(faces(model.boxes))
    roles = cluster_roles(kept, max_roles, max_neon, exact)
    role_of: dict[tuple[str, str], str] = {}
    for role, (rep, mat, members) in roles.items():
        for col in members:
            role_of[(col, mat)] = role
    clustered = any(len(c[2]) > 1 for c in roles.values())
    meshes: dict[str, Mesh] = {}
    palette, materials = {}, {}
    for role, (rep, mat, members) in roles.items():
        meshes[role] = Mesh(role, colors=[] if clustered else None)   # uniform: every role carries ratios once any cluster exists
        palette[role] = rep
        materials[role] = mat
    for f in kept:
        role = role_of[(f.color, f.material)]
        rep = _rgb(palette[role])
        ratio = None
        if meshes[role].colors is not None:
            col = _rgb(f.color)
            ratio = tuple(min(1.0, col[i] / rep[i]) if rep[i] > 0 else 1.0 for i in range(3))
        _quad(meshes[role], f, ratio)
    total = 0
    for role, mesh in meshes.items():
        if mesh.triangles > max_tris_role:
            raise BudgetError(f"{model.name}: role {role} has {mesh.triangles} triangles > {max_tris_role}")
        total += mesh.triangles
    if total > max_tris_model:
        raise BudgetError(f"{model.name}: {total} triangles > {max_tris_model}")
    attrs = dict(model.attrs)
    return ConvertedModel(model.name, model.rarity, model.world, palette, materials, meshes, attrs,
                          True if model.fx else None, model.pose, model.pose_centre, clustered, bbox(model.boxes))


def repose(cm: ConvertedModel) -> ConvertedModel:
    """Bake the rigid pose back into the vertices: world = R (local - c) + c for positions, R n for
    normals. The exported MeshParts then sit unrotated with the exact AABB of the tilted body (a
    rotated MeshPart would report an inflated, conservative bounding box to the spawner's fit)."""
    if cm.pose_rotation is None or cm.pose_centre is None:
        return cm
    R, c = cm.pose_rotation, cm.pose_centre

    def rot(v):
        return (R[0] * v[0] + R[1] * v[1] + R[2] * v[2],
                R[3] * v[0] + R[4] * v[1] + R[5] * v[2],
                R[6] * v[0] + R[7] * v[1] + R[8] * v[2])

    meshes: dict[str, Mesh] = {}
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for role, m in cm.meshes.items():
        positions = []
        for p in m.positions:
            d = rot((p[0] - c[0], p[1] - c[1], p[2] - c[2]))
            w = (round(d[0] + c[0], 6), round(d[1] + c[1], 6), round(d[2] + c[2], 6))
            positions.append(w)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
        normals = [tuple(round(x, 6) for x in rot(n)) for n in m.normals]
        meshes[role] = Mesh(m.role, positions, normals, list(m.uvs), list(m.indices), None if m.colors is None else list(m.colors))
    return ConvertedModel(cm.name, cm.rarity, cm.world, dict(cm.palette), dict(cm.materials), meshes, dict(cm.attributes),
                          cm.fx, None, None, cm.vertex_colors, ((lo[0], lo[1], lo[2]), (hi[0], hi[1], hi[2])),
                          cm.pitch, cm.motion, cm.material)
