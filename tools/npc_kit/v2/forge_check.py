"""forge_check.py — port fidelity: render what NpcForge ACTUALLY builds from the generated
shell manifest (harness build, exported piece geometry, the rig's own Motor6D placement)
next to the approved study render of the same character, and measure the silhouette
overlap. Not a new design version: a check that the Lua assembly reproduces the study.

    cd tools && python -m npc_kit.v2.forge_check
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from npc_kit import preview as PV
from npc_kit.harness import Harness
from npc_kit.v2 import characters25 as C
from npc_kit.v2 import export_kit as X
from npc_kit.v2 import render as R

OUT = X.REPO / "docs" / "npc" / "previews" / "v25"


def silhouette_iou(a: Image.Image, b: Image.Image, bg) -> float:
    A = np.any(np.asarray(a) != np.array(bg, dtype=np.uint8), axis=2)
    B = np.any(np.asarray(b) != np.array(bg, dtype=np.uint8), axis=2)
    inter = np.logical_and(A, B).sum()
    union = np.logical_or(A, B).sum()
    return float(inter) / float(max(union, 1))


def main() -> int:
    ch = X.study_character()
    X.export(ch)                                                   # keep the manifest + pieces.json current
    shown = C.gianluca_v25()                                       # the study's own 'serious' render for the right-hand column
    pieces = json.loads((X.OUT / f"{ch.id}.pieces.json").read_text())

    H = Harness()
    forge = H.forge()
    root = H.import_root_for_shells("Gianluca_V25")
    model, report = forge.Build("Gianluca", H.table(importRoot=root))
    assert model is not None, "forge build failed the budget"
    forge_tris = PV.scene_from_model(H, model, shell_meshes=pieces, only=lambda d: d.Name != "Collider")
    study = shown.world_meshes()

    c = (0, 3.15, 0)
    pps = 54
    panels, ious = [], {}
    for view in ("front", "left 3/4", "back"):
        a = R.render(forge_tris, 300, 480, view, pps, c); R.label(a, f"NpcForge build — {view}")
        b = R.render(study, 300, 480, view, pps, c); R.label(b, f"study kit — {view}")
        sa = R.silhouette(forge_tris, 300, 480, view, pps, c)
        sb = R.silhouette(study, 300, 480, view, pps, c)
        ious[view] = silhouette_iou(sa, sb, R.PAPER)
        panels.append(R.stack([a, b], pad=4))
    r = {row.name: (row.value, row.limit, row.status) for row in [report.budget.rows[i] for i in range(1, len(report.budget.rows) + 1)]}
    cap = (f"Left of each pair: the model NpcForge assembles from NpcShells/Gianluca_V25 (harness build: slot MeshParts on the p2 rig, mesh face on "
           f"FaceJoints, shells welded, spear gripped) drawn with the exported piece geometry. Right: the study render. Silhouette overlap "
           f"front {ious['front']:.3f} · 3/4 {ious['left 3/4']:.3f} · back {ious['back']:.3f}. "
           f"Budget from NpcBudget: {r['baseParts'][0]} parts / {r['welds'][0]} welds / {r['motor6d'][0]} Motor6D / {r['bespokeMeshes'][0]} bespoke / "
           f"{r['trianglesEstimated'][0]:,} tris — {'PASS' if report.budget['pass'] else 'FAIL'} vs Tier 3 caps.")
    # the eight runtime states applied by NpcFaceConfig to the forge-built mesh face (deltas on the neutral export)
    FC = H.require("ReplicatedStorage/Modules/NpcKit/NpcFaceConfig")
    head = H.find(model, "Head", False)
    hp = (head.Position.X, head.Position.Y + 0.2, head.Position.Z)
    strip = []
    for state in ("neutral", "happy", "worried", "angry", "suspicious", "tired", "shocked", "serious"):
        FC.Apply(model, state)
        tris_head = PV.scene_from_model(H, model, shell_meshes=pieces, only=lambda d: d.Parent.Name in ("Face",) or d.Name in ("Head", "Hair", "Beard", "AgeLines"))
        im = R.render(tris_head, 190, 190, "front", 88, hp, ground_y=None)
        strip.append(R.label(im, state, size=12))
    FC.Apply(model, "serious")
    faces = R.hstack(strip)
    R.label(faces, "", (8, 6), 12)
    cap = cap + " Bottom row: the eight NpcFaceConfig states applied at build time to the forge-built mesh face (C0 offsets + scales on the seven driven parts)."
    sheet = R.title(R.caption(R.stack([R.hstack(panels), faces]), cap), "K — port fidelity: NpcForge build vs the approved study")
    R.save(sheet, OUT / "v25-K-forge-vs-study.png")
    print(json.dumps({"iou": ious, "budget": {k: r[k][0] for k in ("baseParts", "welds", "motor6d", "bespokeMeshes", "trianglesEstimated")}, "pass": bool(report.budget["pass"])}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
