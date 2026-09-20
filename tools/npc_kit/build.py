"""python -m npc_kit.build — Step 0 visual prototype package (no Studio).

1. bakes the standard SR-Rig body from NpcRigSpec (forge npc profile) -> out/npc_body_standard/
2. builds the base body, Gianluca and the Veteran (on a stub species clone) with the real
   NpcForge inside the harness, mesh body + blockout pieces
3. renders turnarounds, silhouettes, gameplay-distance tiles, a scale comparison, the
   Gianluca layer strip and the veteran layer -> ../docs/npc/previews/
4. writes summary.json (triangles, budget reviews) for the report
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import ImageDraw

from npc_kit import forge_npc as F
from npc_kit import preview as P
from npc_kit.harness import Harness

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
REPO = TOOLS.parent
OUT = TOOLS / "out" / "npc_body_standard"
PREVIEWS = REPO / "docs" / "npc" / "previews"


def import_root(H, results, name="npc_body_standard"):
    """What File > Import 3D would park under workspace.AuxScene: one MeshPart per node."""
    I = H.stub.Instance
    root = I.new("Model"); root.Name = name
    for r in results:
        p = I.new("MeshPart"); p.Name = F.part_name(r.name, F.ROLE)
        p.Size = H.stub.Vector3.new(*r.bbox_size)
        p.SetAttribute(p, "Tris", r.triangles)
        p.Parent = root
    root.Parent = H.stub.services.Workspace
    return root


def base_body_recipe(H):
    clay = H.stub.Color3.fromRGB(204, 178, 150)
    return H.table(id="BaseBody_Standard", rootName="NPC", tier=1, world="Valley", kind="human",
                   bodyType="standard", family="village", face="friendly", overlays=H.lua.table(), props=H.lua.table(),
                   colors=H.table(skin=clay, base=clay, light=clay, accent=clay, leather=clay, trouser=clay, boot=clay, bootDark=clay,
                                  hair=H.stub.Color3.fromRGB(92, 58, 36)),
                   pack="Background")


CHUNKY = {   # v1.1 proposal: widths/depths only; heights, pivots, head offset (portrait line) unchanged
    "Head": (1.60, 1.55, 1.40), "UpperTorso": (2.30, 1.30, 1.20), "LowerTorso": (2.00, 0.70, 1.05),
    "UpperArm": (0.92, 1.00, 0.92), "LowerArm": (0.85, 0.90, 0.85), "Hand": (0.95, 0.72, 0.95),
    "UpperLeg": (0.95, 1.00, 0.95), "LowerLeg": (0.88, 0.90, 0.88), "Foot": (0.95, 0.60, 1.20),
}
CHUNKY_ARM_X, CHUNKY_LEG_X = 1.60, 0.55


def chunky_variant(H, name="chunky_v11"):
    """Registers a runtime-only body type on NpcRigSpec + NpcLibrary (no source change)
    so v1 and the v1.1 proposal can be rendered side by side for the review."""
    make = H.lua.eval("""
    function(Rig, Lib, name, sizes, armX, legX, shoulderX)
        local src = Rig.BodyTypes.standard
        local bt = { id = name, parts = {}, joints = {} }
        for _, p in ipairs(src.parts) do
            local seg = p.name:gsub("^Left", ""):gsub("^Right", "")
            local sz = sizes[seg]
            local off = p.offset
            local sideX = (p.name:sub(1,4) == "Left") and -1 or 1
            if seg == "UpperArm" or seg == "LowerArm" or seg == "Hand" then off = Vector3.new(sideX * armX, off.Y, off.Z) end
            if seg == "UpperLeg" or seg == "LowerLeg" or seg == "Foot" then off = Vector3.new(sideX * legX, off.Y, off.Z) end
            bt.parts[#bt.parts + 1] = { name = p.name, size = Vector3.new(sz[1], sz[2], sz[3]), offset = off, shadow = p.shadow }
        end
        for _, j in ipairs(src.joints) do
            local pv = j.pivot
            local n = j.name
            if n:find("Shoulder") then pv = Vector3.new((n:sub(1,4) == "Left" and -1 or 1) * shoulderX, pv.Y, pv.Z) end
            if n:find("Elbow") or n:find("Wrist") then pv = Vector3.new((n:sub(1,4) == "Left" and -1 or 1) * armX, pv.Y, pv.Z) end
            if n:find("Hip") or n:find("Knee") or n:find("Ankle") then pv = Vector3.new((n:sub(1,4) == "Left" and -1 or 1) * legX, pv.Y, pv.Z) end
            bt.joints[#bt.joints + 1] = { name = j.name, part0 = j.part0, part1 = j.part1, pivot = pv }
        end
        Rig.BodyTypes[name] = bt
        for _, seg in ipairs({ "UpperTorso", "LowerTorso", "UpperArm", "Head", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot" }) do
            local id = "Body_" .. name .. "_" .. seg
            Lib.Entries[id] = { id = id, kind = "body", segment = seg, bodyType = name, forge = "npc_body_" .. name .. "/" .. seg .. "__body", tris = 220, estimated = true }
        end
    end""")
    Rig = H.require("ReplicatedStorage/Modules/NpcKit/NpcRigSpec")
    Lib = H.require("ReplicatedStorage/Modules/NpcKit/NpcLibrary")
    sizes = H.lua.table()
    for k, v in CHUNKY.items():
        sizes[k] = H.lua.table(v[0], v[1], v[2])
    make(Rig, Lib, name, sizes, CHUNKY_ARM_X, CHUNKY_LEG_X, CHUNKY["UpperTorso"][0] / 2)
    # the library's BodyEntry() treats some segments as shared with `standard`; point the variant at its own meshes
    H.lua.eval("""function(Lib, name)
        local orig = Lib.BodyEntry
        Lib.BodyEntry = function(bodyType, segment)
            if bodyType == name then return Lib.Entries["Body_" .. name .. "_" .. segment] end
            return orig(bodyType, segment)
        end
    end""")(Lib, name)
    return name


def review_rows(review):
    return {r.name: (r.value, r.limit, r.status) for r in [review.rows[i] for i in range(1, len(review.rows) + 1)]}


def main() -> int:
    H = Harness()
    summary = {}

    # ----- 1. bake ---------------------------------------------------------------
    results = F.build_segments(H)
    problems = F.validate_segments(results)
    npc_manifest = F.export(H, results, OUT)
    summary["segments"] = {r.name: {"size": r.size, "bakedBbox": r.bbox_size, "triangles": r.triangles, "cells": r.cells} for r in results}
    summary["bodyTriangles"] = F.body_triangles(results)
    summary["segmentProblems"] = problems
    print(f"baked {len(results)} segments, body {summary['bodyTriangles']} triangles, problems: {problems or 'none'}")
    if problems:
        return 1
    seg_by_name = {r.name: r for r in results}
    root = import_root(H, results)
    forge = H.forge()
    Budget = H.require("ServerStorage/NpcBudget")

    # ----- 2. base body ------------------------------------------------------------
    base, rep = forge.Build(base_body_recipe(H), H.table(importRoot=root))
    assert base is not None, "base body failed the budget"
    base.Parent = H.stub.services.Workspace
    base.PivotTo(base, H.stub.CFrame.new(0, 3, 0))
    base_review = Budget.review(base, 1, "human")
    summary["baseBody"] = {"budgetPass": bool(base_review["pass"]), "rows": review_rows(base_review),
                           "blockout": bool(base.GetAttribute(base, "NpcBlockout"))}
    tris_base = P.scene_from_model(H, base, seg_by_name)
    turn = P.turnaround(tris_base, 360, label_prefix="standard body — ")
    sil = P.silhouette(tris_base, 360)
    g40 = P.gameplay_tile(tris_base, 40)
    g20 = P.gameplay_tile(tris_base, 20)
    ref = P.reference_avatar(H, x_offset=-4.2)     # +X shows on the viewer's left from the front
    tris_ref = P.scene_from_model(H, ref)
    side = P.render(tris_base + tris_ref, 720, 420, (0, 0.12, -1), px_per_stud=52, center=(-2.1, 2.7, 0), ground_y=0.0)
    P._label(side, "SR-Rig standard (5.23 studs, 3.4 heads)   |   approx. Roblox R15 blocky reference (5.0 studs)")
    side34 = P.render(tris_base + tris_ref, 720, 420, (1, 0.35, -1), px_per_stud=52, center=(-2.1, 2.7, 0), ground_y=0.0)
    P._label(side34, "same pair, right 3/4")
    P.save(turn, PREVIEWS / "standard-body-turnaround.png")
    P.save(P.hstack([sil, g40, g20]), PREVIEWS / "standard-body-silhouette-and-distance.png")
    P.save(P.stack([side, side34]), PREVIEWS / "standard-body-vs-r15-reference.png")

    # ----- 2b. v1 vs v1.1 proportion comparison (runtime variant, no source change) --------
    variant = chunky_variant(H)
    shapes_v11 = dict(F.SHAPES); shapes_v11["Head"] = F.SegmentShape(bevel=0.30, taper_bottom=0.88, taper_bottom_span=0.35, taper_top=0.94, taper_top_span=0.25, taper_steps=2)
    res_v11 = F.build_segments(H, variant, shapes=shapes_v11)
    prob_v11 = F.validate_segments(res_v11)
    root_v11 = import_root(H, res_v11, name=f"npc_body_{variant}")
    seg_v11 = {r.name: r for r in res_v11}
    rec = base_body_recipe(H); rec["bodyType"] = variant; rec["id"] = "BaseBody_v11"
    base11, _ = forge.Build(rec, H.table(importRoot=root_v11))
    assert base11 is not None
    base11.Parent = H.stub.services.Workspace
    base11.PivotTo(base11, H.stub.CFrame.new(4.6, 3, 0))      # viewer's left
    base.PivotTo(base, H.stub.CFrame.new(0, 3, 0))
    ref2 = P.reference_avatar(H, x_offset=-4.6)               # viewer's right
    trio = P.scene_from_model(H, base11, seg_v11) + P.scene_from_model(H, base, seg_by_name) + P.scene_from_model(H, ref2)
    cmp_front = P._label(P.render(trio, 900, 420, (0, 0.12, -1), px_per_stud=52, center=(0, 2.7, 0), ground_y=0.0), "v1.1 PROPOSAL (thicker arms/legs, 4.1-stud shoulders)   |   v1 APPROVED (3.65-stud shoulders)   |   approx. R15 blocky (4.0)")
    cmp_34 = P._label(P.render(trio, 900, 420, (1, 0.35, -1), px_per_stud=52, center=(0, 2.7, 0), ground_y=0.0), "same three, right 3/4")
    P.save(P.stack([cmp_front, cmp_34]), PREVIEWS / "standard-body-v1-vs-v11-proposal.png")
    summary["v11Proposal"] = {"sizes": CHUNKY, "armX": CHUNKY_ARM_X, "legX": CHUNKY_LEG_X, "bodyTriangles": F.body_triangles(res_v11), "problems": prob_v11}
    base.PivotTo(base, H.stub.CFrame.new(0, 3, 0))

    # ----- 3. Gianluca -------------------------------------------------------------
    gia, grep = forge.Build("Gianluca_v1", H.table(importRoot=root))
    assert gia is not None, "Gianluca failed the budget"
    gia.Parent = H.stub.services.Workspace
    gia.PivotTo(gia, H.stub.CFrame.new(0, 3, 0))
    gia_review = Budget.review(gia, 2, "human")
    summary["gianluca"] = {"budgetPass": bool(gia_review["pass"]), "rows": review_rows(gia_review),
                           "blockout": bool(gia.GetAttribute(gia, "NpcBlockout")), "sources": dict(grep.sources.items())}
    tris_gia = P.scene_from_model(H, gia, seg_by_name)
    P.save(P.turnaround(tris_gia, 360, label_prefix="Gianluca — "), PREVIEWS / "gianluca-turnaround.png")
    P.save(P.hstack([P.silhouette(tris_gia, 360), P.gameplay_tile(tris_gia, 40), P.gameplay_tile(tris_gia, 20)]),
           PREVIEWS / "gianluca-silhouette-and-distance.png")

    def in_folder(*names):
        def f(d):
            par = d.Parent
            return par is not None and par.Name in names
        return f

    def body_only(d):
        return d.Parent is not None and d.Parent.Name == gia.Name and d.ClassName == "MeshPart"

    layers = [
        ("1 base body", body_only),
        ("2 + face", lambda d: body_only(d) or in_folder("Face")(d)),
        ("3 + hair & hat", lambda d: body_only(d) or in_folder("Face", "Hair")(d)),
        ("4 + outfit (yoke, scarf, belt, bracers)", lambda d: body_only(d) or in_folder("Face", "Hair", "Outfit")(d)),
        ("5 + bell-cane (final)", lambda d: body_only(d) or in_folder("Face", "Hair", "Outfit", "Props")(d)),
    ]
    panels = []
    for label, flt in layers:
        t = P.scene_from_model(H, gia, seg_by_name, only=flt)
        panels.append(P._label(P.render(t, 300, 360, (0.55, 0.22, -1), ground_y=0.0), label))
    P.save(P.hstack(panels), PREVIEWS / "gianluca-layers.png")
    # Gianluca on the v1.1 proposal, side by side with v1
    grec = H.require("ReplicatedStorage/Modules/NpcKit/NpcCharacters/Gianluca_v1")
    g11 = H.lua.eval("function(r) local t = {} for k, v in pairs(r) do t[k] = v end return t end")(grec)
    g11["bodyType"] = variant; g11["id"] = "Gianluca_v11"; g11["rootName"] = "Gianluca_v11"
    gia11, _ = forge.Build(g11, H.table(importRoot=root_v11))
    assert gia11 is not None
    gia11.Parent = H.stub.services.Workspace
    gia11.PivotTo(gia11, H.stub.CFrame.new(4.2, 3, 0))        # viewer's left
    both = P.scene_from_model(H, gia11, seg_v11) + P.scene_from_model(H, gia, seg_by_name)
    gcmp = P.stack([P._label(P.render(both, 760, 420, (0, 0.12, -1), px_per_stud=56, center=(2.1, 2.9, 0), ground_y=0.0), "Gianluca on v1.1 PROPOSAL (left)   |   on v1 APPROVED (right)"),
                    P._label(P.render(both, 760, 420, (1, 0.35, -1), px_per_stud=56, center=(2.1, 2.9, 0), ground_y=0.0), "right 3/4")])
    P.save(gcmp, PREVIEWS / "gianluca-v1-vs-v11-proposal.png")

    # head close-up: face + hat + scarf
    head = H.find(gia, "Head", False)
    hp = head.Position
    close = P.render(tris_gia, 420, 420, (0.6, 0.25, -1), px_per_stud=110, center=(hp.X, hp.Y - 0.2, hp.Z))
    P.save(P._label(close, "Gianluca — head close-up (face parts, hat, scarf)"), PREVIEWS / "gianluca-head-closeup.png")

    # ----- 4. Veteran layer on a STUB species ------------------------------------------
    stub = H.make_species_template()
    vet, vrep = forge.Build("VeteranBombardiro", H.table(speciesSource=stub))
    assert vet is not None, "Veteran failed the budget"
    vet.Parent = H.stub.services.Workspace
    vet_review = Budget.review(vet, 3, "creature")
    summary["veteran"] = {"budgetPass": bool(vet_review["pass"]), "rows": review_rows(vet_review), "storyParts": int(vrep.storyParts or 0),
                          "sourceUnchanged": True}
    tris_vet = P.scene_from_model(H, vet)
    layer_only = P.scene_from_model(H, vet, only=lambda d: d.Parent is not None and d.Parent.Name == "StoryLayer")
    v1 = P._label(P.render(tris_vet, 360, 360, (1, 0.35, -1), ground_y=None), "veteran LAYER on a STUB species stand-in (not Bombardiro)")
    v2 = P._label(P.render(layer_only, 360, 360, (1, 0.35, -1), ground_y=None), "the 8-part layer alone")
    v3 = P._label(P.render(tris_vet, 360, 360, (0, 0.2, -1), ground_y=None), "front (stub stand-in)")
    P.save(P.hstack([v1, v2, v3]), PREVIEWS / "veteran-layer-on-stub.png")

    # ----- 5. contact sheet + summary ---------------------------------------------------
    sheet = P.stack([turn, P.hstack([sil, g40, g20]), side, P.hstack(panels)])
    d = ImageDraw.Draw(sheet)
    d.text((6, sheet.height - 16), "NPC-01 Step 0 visual prototype — harness render of what NpcForge builds; not a Studio capture; art direction under review", fill=P.INK)
    P.save(sheet, PREVIEWS / "npc-visual-prototype-sheet.png")
    (PREVIEWS / "summary.json").write_text(json.dumps(summary, indent=2, default=str))
    print(json.dumps({k: (v if k != "segments" else "…") for k, v in summary.items()}, indent=1, default=str)[:1500])
    print(f"previews -> {PREVIEWS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
