"""ingest_parts.py — the Studio dump (tools/brainrot_forge/studio/dump_parts.lua) -> PartModel.

A PartModel is a list of axis-aligned boxes in studs (the template's own frame). Three fish were
re-posed with one rigid rotation on every part; unpose() rewrites those into the shared local
frame so the bake can cull faces, and records `pose` for the assembler to re-apply.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

Vec3 = tuple[float, float, float]
Rot = tuple[float, float, float, float, float, float, float, float, float]  # row-major R00..R22
MATERIALS = {"P": "Plastic", "S": "SmoothPlastic", "N": "Neon"}


@dataclass
class Box:
    pos: Vec3
    size: Vec3
    color: str          # "#RRGGBB"
    material: str       # Roblox Material name
    rot: Rot | None     # None = identity


@dataclass
class PartModel:
    name: str
    rarity: str
    world: str
    attrs: dict
    fx: bool
    boxes: list[Box]
    pose: Rot | None = None
    pose_centre: Vec3 | None = None   # the pivot unpose() rotated about; the assembler re-poses about it


def load_dump(path: str | Path) -> list[PartModel]:
    text = Path(path).read_text(encoding="utf-8")
    data = json.loads(text)
    if data and isinstance(data[0], dict) and "type" in data[0] and "text" in data[0]:   # harness wrapper
        data = json.loads(data[0]["text"])
    models = []
    for m in data:
        boxes = []
        for p in m["parts"]:
            rot = tuple(p[8]) if len(p) > 8 and p[8] else None
            boxes.append(Box((p[0], p[1], p[2]), (p[3], p[4], p[5]), "#" + p[6].upper(), MATERIALS.get(p[7], p[7]), rot))
        models.append(PartModel(m["name"], m.get("rarity", "Unknown"), m.get("world", "Unknown"), dict(m.get("attrs", {})), bool(m.get("fx")), boxes))
    return models


def bbox(boxes: list[Box]) -> tuple[Vec3, Vec3]:
    lo = [min(b.pos[i] - b.size[i] / 2 for b in boxes) for i in range(3)]
    hi = [max(b.pos[i] + b.size[i] / 2 for b in boxes) for i in range(3)]
    return (lo[0], lo[1], lo[2]), (hi[0], hi[1], hi[2])


def _same(a: Rot, b: Rot, tol=1e-3) -> bool:
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def unpose(model: PartModel) -> PartModel:
    rots = [b.rot for b in model.boxes if b.rot is not None]
    if not rots:
        return model
    if len(rots) != len(model.boxes) or not all(_same(r, rots[0]) for r in rots):
        raise ValueError(f"{model.name}: mixed rotations — cannot un-pose")
    R = rots[0]
    lo, hi = bbox(model.boxes)   # rotated boxes' AABB is only an approximation of the centre; any fixed pivot works
    c = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2)

    # local = R^T (p - c) + c   (row-major R: world = R * local)
    def to_local(p: Vec3) -> Vec3:
        d = (p[0] - c[0], p[1] - c[1], p[2] - c[2])
        return (R[0] * d[0] + R[3] * d[1] + R[6] * d[2] + c[0],
                R[1] * d[0] + R[4] * d[1] + R[7] * d[2] + c[1],
                R[2] * d[0] + R[5] * d[1] + R[8] * d[2] + c[2])

    boxes = [Box(to_local(b.pos), b.size, b.color, b.material, None) for b in model.boxes]
    return PartModel(model.name, model.rarity, model.world, model.attrs, model.fx, boxes, pose=R, pose_centre=c)
