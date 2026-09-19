"""forge_npc.py — the Brainrot Forge's NPC profile: SR-Rig body segments as voxel
lattices, baked with the forge's own baker (one MeshPart per segment), validated
against NpcRigSpec, exported as a File > Import 3D batch + an NPC manifest.

Isolated to npc-01: nothing in tools/brainrot_forge is modified. The brainrot
gates (MAX_ROLES, MIN_HEIGHT, eyes, feet-at-zero) are for catchable creatures;
segments have their own gate (`validate_segments`), and the bake budgets
(MAX_TRIS_ROLE / MAX_TRIS_MODEL) are reused unchanged.

Sizes come from NpcRigSpec (Lua) through the harness — the one source of truth.
Shapes are the "chunky hand-carved" language: beveled boxes with a taper, never
spheres, so flat faces greedy-merge into a handful of rectangles and the stepped
bevels read as carved edges at gameplay distance.

    cd tools && python -m npc_kit.build            # -> out/npc_body_standard/* and docs/npc/previews/*
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path

from brainrot_forge.bake import MAX_TRIS_ROLE, Mesh, bake
from brainrot_forge.export_glb import build_manifest, part_name, write_glb
from brainrot_forge.voxel import VoxelModel

PITCH = 0.05                 # studs per cell: exact SR-Rig sizes (all multiples of 0.05)
ROLE = "body"                # one colour role per segment; NpcForge paints by family
SEGMENTS = ["Head", "UpperTorso", "LowerTorso", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot"]
RIGHT_OF = {"UpperArm": "RightUpperArm", "LowerArm": "RightLowerArm", "Hand": "RightHand",
            "UpperLeg": "RightUpperLeg", "LowerLeg": "RightLowerLeg", "Foot": "RightFoot"}
SIZE_TOL = PITCH / 2 + 1e-6  # a baked bbox must equal the spec size to within half a cell
TARGET_TRIS_BODY = 4500      # doc F: Tier 2 target; the 15-part body should sit well under it
MAX_TRIS_BODY = 9000


# ===== shape language ==========================================================
@dataclass
class SegmentShape:
    """How a segment is carved. bevel = corner rounding radius (studs); taper_*
    shrink the x/z extents linearly over the given fraction of the height."""
    bevel: float = 0.12
    taper_bottom: float = 1.0      # x/z scale at the bottom edge (1 = none)
    taper_bottom_span: float = 0.4 # fraction of height the bottom taper acts over
    taper_top: float = 1.0
    taper_top_span: float = 0.3
    front_lift: float = 0.0        # feet: raise the front-bottom edge (toe) by this fraction of height
    round_mode: str = "l2"         # "l2" rounded corner, "l1" chamfer
    taper_steps: int = 3           # tapers change in this many discrete steps so flat faces greedy-merge


SHAPES = {
    # bevel in studs (2 cells = 0.10 keeps limbs at ~150 triangles; the head gets the round one)
    "Head":       SegmentShape(bevel=0.24, taper_bottom=0.88, taper_bottom_span=0.35, taper_top=0.94, taper_top_span=0.25, taper_steps=2),
    "UpperTorso": SegmentShape(bevel=0.12, taper_bottom=0.90, taper_bottom_span=0.6, taper_top=0.98, taper_top_span=0.15, taper_steps=2),
    "LowerTorso": SegmentShape(bevel=0.10, taper_bottom=0.96, taper_bottom_span=0.5, taper_steps=2),
    "UpperArm":   SegmentShape(bevel=0.10, taper_bottom=0.90, taper_bottom_span=0.6, taper_steps=2),
    "LowerArm":   SegmentShape(bevel=0.10, taper_bottom=0.88, taper_bottom_span=0.7, taper_steps=2),
    "Hand":       SegmentShape(bevel=0.12, taper_bottom=0.92, taper_bottom_span=0.5, taper_steps=2),
    "UpperLeg":   SegmentShape(bevel=0.10, taper_bottom=0.92, taper_bottom_span=0.6, taper_steps=2),
    "LowerLeg":   SegmentShape(bevel=0.10, taper_bottom=0.88, taper_bottom_span=0.7, taper_steps=2),
    "Foot":       SegmentShape(bevel=0.10, taper_top=0.90, taper_top_span=0.5, front_lift=0.18, taper_steps=2),
}


def _cells(size: tuple[float, float, float]) -> tuple[int, int, int]:
    return tuple(int(round(s / PITCH)) for s in size)  # type: ignore[return-value]


def carve_segment(name: str, size: tuple[float, float, float], shape: SegmentShape | None = None,
                  color: str = "#D6B08A") -> VoxelModel:
    """A beveled, tapered box of the exact stud size, cells centred on the origin
    (cell centres at (i + 0.5) * PITCH from -w/2), front = -Z."""
    shape = shape or SHAPES.get(name, SegmentShape())
    w, h, d = _cells(size)
    m = VoxelModel(name, "Common", world="Valley", pitch=PITCH)
    m.role(ROLE, color)
    hw, hh, hd = w / 2.0, h / 2.0, d / 2.0
    bev = shape.bevel / PITCH
    for iy in range(h):
        cy = iy + 0.5 - hh                       # -hh .. hh, cell centre
        fy = (iy + 0.5) / h                      # 0 bottom .. 1 top
        sx = 1.0
        steps = max(1, shape.taper_steps)
        if fy < shape.taper_bottom_span:
            t = math.floor((fy / shape.taper_bottom_span) * steps) / steps
            sx *= shape.taper_bottom + (1 - shape.taper_bottom) * t
        if fy > 1 - shape.taper_top_span:
            t = math.ceil(((fy - (1 - shape.taper_top_span)) / shape.taper_top_span) * steps) / steps
            sx *= 1 - (1 - shape.taper_top) * t
        ex, ez = hw * sx, hd * sx
        for ix in range(w):
            cx = ix + 0.5 - hw
            for iz in range(d):
                cz = iz + 0.5 - hd
                # toe lift: the front-bottom edge rises (front = -Z)
                if shape.front_lift and cz < 0:
                    lift = math.floor((-cz / hd) * 3) / 3 * shape.front_lift
                    if fy < lift:
                        continue
                if abs(cx) > ex or abs(cz) > ez:
                    continue
                # corner rounding: overshoot beyond the inner (un-beveled) box on each axis
                ox = max(0.0, abs(cx) - (ex - bev))
                oy = max(0.0, abs(cy) - (hh - bev))
                oz = max(0.0, abs(cz) - (ez - bev))
                if shape.round_mode == "l1":
                    r = ox + oy + oz
                else:
                    r = math.sqrt(ox * ox + oy * oy + oz * oz)
                if r > bev + 1e-9:
                    continue
                m.set(ix - w // 2, iy, iz - d // 2, ROLE)
    return m


# ===== the profile ============================================================
@dataclass
class SegmentResult:
    name: str
    size: tuple[float, float, float]
    model: VoxelModel
    mesh: Mesh
    bbox_size: tuple[float, float, float]
    triangles: int
    cells: int
    problems: list[str] = field(default_factory=list)


def _recentre(mesh: Mesh) -> tuple[float, float, float]:
    """Roblox centres a MeshPart's geometry on its bounding box; do the same so a
    renderer and the exported node agree with what Studio will show."""
    lo, hi = mesh.bounds()
    c = tuple((lo[i] + hi[i]) / 2 for i in range(3))
    mesh.positions = [(p[0] - c[0], p[1] - c[1], p[2] - c[2]) for p in mesh.positions]
    return (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])


def rig_sizes(H, body_type: str = "standard") -> dict[str, tuple[float, float, float]]:
    """Segment sizes straight from NpcRigSpec (Lua) via the harness."""
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    out = {}
    for seg in SEGMENTS:
        part = Rig.PartByName(body_type, RIGHT_OF.get(seg, seg))
        assert part is not None, seg
        out[seg] = (round(part.size.X, 6), round(part.size.Y, 6), round(part.size.Z, 6))
    return out


def build_segments(H, body_type: str = "standard", skin: str = "#D6B08A", shapes: dict | None = None) -> list[SegmentResult]:
    results = []
    for seg, size in rig_sizes(H, body_type).items():
        model = carve_segment(seg, size, (shapes or SHAPES).get(seg), color=skin)
        meshes = bake(model)              # forge budgets apply unchanged
        mesh = meshes[ROLE]
        bbox = _recentre(mesh)
        results.append(SegmentResult(seg, size, model, mesh, bbox, mesh.triangles, len(model.cells)))
    return results


def validate_segments(results: list[SegmentResult]) -> list[str]:
    problems = []
    total = 0
    for r in results:
        for axis, (want, got) in enumerate(zip(r.size, r.bbox_size)):
            if abs(want - got) > SIZE_TOL:
                problems.append(f"{r.name}: axis {axis} baked {got:.3f} vs spec {want:.3f}")
        if r.triangles > MAX_TRIS_ROLE:
            problems.append(f"{r.name}: {r.triangles} triangles > {MAX_TRIS_ROLE}")
        if r.cells == 0:
            problems.append(f"{r.name}: no cells")
        total += r.triangles
    # the 15-part body = 9 unique meshes, limbs used twice
    body_tris = sum(r.triangles * (2 if r.name in RIGHT_OF else 1) for r in results)
    if body_tris > MAX_TRIS_BODY:
        problems.append(f"body {body_tris} triangles > {MAX_TRIS_BODY}")
    return problems


def body_triangles(results: list[SegmentResult]) -> int:
    return sum(r.triangles * (2 if r.name in RIGHT_OF else 1) for r in results)


def batch_of(results: list[SegmentResult]):
    return [(r.model, {ROLE: r.mesh}) for r in results]


def npc_manifest(H, results: list[SegmentResult], body_type: str = "standard") -> dict:
    """The manifest NpcForge.AssembleHuman verifies against: segment sizes, joint
    pivots and attachments from NpcRigSpec, plus what the bake produced."""
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    bt = Rig.BodyTypes[body_type]
    joints = []
    for j in H.lua_list(bt.joints):
        c0, c1, _ = Rig.JointFrames(body_type, j.name)
        joints.append({"name": j.name, "part0": j.part0, "part1": j.part1,
                       "pivot": [j.pivot.X, j.pivot.Y, j.pivot.Z],
                       "c0": [c0.Position.X, c0.Position.Y, c0.Position.Z],
                       "c1": [c1.Position.X, c1.Position.Y, c1.Position.Z]})
    parts = [{"name": p.name, "size": [p.size.X, p.size.Y, p.size.Z], "offset": [p.offset.X, p.offset.Y, p.offset.Z],
              "segment": p.name.replace("Left", "").replace("Right", ""), "shadow": bool(p.shadow)} for p in H.lua_list(bt.parts)]
    attachments = {}
    for part, atts in Rig.Attachments.items():
        attachments[part] = {name: [v.X, v.Y, v.Z] for name, v in atts.items()}
    return {
        "profile": "npc", "version": 1, "pitch": PITCH, "bodyType": body_type,
        "hrp": {"size": [Rig.Root.HrpSize.X, Rig.Root.HrpSize.Y, Rig.Root.HrpSize.Z], "height": Rig.Root.HrpHeight, "headOffset": Rig.Root.HeadOffset},
        "segments": [{"name": r.name, "node": part_name(r.name, ROLE), "size": list(r.size), "bakedBbox": list(r.bbox_size),
                      "triangles": r.triangles, "cells": r.cells} for r in results],
        "bodyTriangles": body_triangles(results),
        "parts": parts, "joints": joints, "attachments": attachments,
        "collider": {"size": [Rig.Root.Collider.Size.X, Rig.Root.Collider.Size.Y, Rig.Root.Collider.Size.Z],
                     "offset": [Rig.Root.Collider.Offset.X, Rig.Root.Collider.Offset.Y, Rig.Root.Collider.Offset.Z],
                     "group": Rig.Root.CollisionGroup},
    }


def export(H, results: list[SegmentResult], out_dir: Path, body_type: str = "standard") -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    batch = batch_of(results)
    write_glb(out_dir / f"npc_body_{body_type}_batch.glb", batch, flip_z=False, roblox_forward=True)
    manifest = build_manifest(batch, roblox_forward=True)
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))
    npc = npc_manifest(H, results, body_type)
    (out_dir / "npc_manifest.json").write_text(json.dumps(npc, indent=2))
    return npc
