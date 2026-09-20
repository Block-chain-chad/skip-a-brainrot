"""study.py — renders the V2 CHARACTER ART STUDY sheets (A–H) to docs/npc/previews/v2/
and writes v2-summary.json. Visual study only: nothing here touches the kit's Lua.

    cd tools && python -m npc_kit.v2.study
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from npc_kit import forge_npc as F
from npc_kit import preview as PV
from npc_kit.build import chunky_variant, import_root
from npc_kit.harness import Harness
from npc_kit.v2 import characters as C
from npc_kit.v2 import kit as K
from npc_kit.v2 import lowpoly as L
from npc_kit.v2 import profiles as P
from npc_kit.v2 import render as R

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[1]
REPO = TOOLS.parent
OUT = REPO / "docs" / "npc" / "previews" / "v2"
GLB_OUT = TOOLS / "out" / "npc_v2_study"

PPS = 60                      # px per stud for the character panels
PANEL = (300, 420)
CENTRE = (0, 2.85, 0)
GHOST = (208, 206, 200)
OWN_COLORS = {"skeleton": (176, 178, 184), "reusable": (92, 150, 210), "specific": (236, 138, 54)}
TIER_CAPS: dict[int, dict] = {}     # filled from NpcBudget.Limits.human through the harness (no drift)


def load_caps(H: Harness) -> None:
    Budget = H.require("ServerStorage/NpcBudget")
    for tier in (1, 2, 3):
        lim = Budget.Limits.human[tier]
        TIER_CAPS[tier] = {k: int(lim[k]) for k in ("baseParts", "bespokeMeshes", "triangles", "motor6d", "welds")}


def panel(meshes, view, w=PANEL[0], h=PANEL[1], pps=PPS, centre=CENTRE, text=None, **kw):
    im = R.render(meshes, w, h, view, pps, centre, **kw)
    if text:
        R.label(im, text)
    return im


# ===== A. the skeleton underneath ==================================================
def sheet_a(profile: P.BodyProfile, rest: dict) -> Image.Image:
    bones = P.pose(profile, rest)
    kit = P.body_kit(profile)
    ghost = [bones[n].to_world(m.recolored(GHOST)) for n, m in kit.items()]
    pts = P.skeleton_points(profile, bones)
    panels = []
    for view in ("front", "side", "left 3/4"):
        im = R.render(ghost, *PANEL, view, PPS, CENTRE, edges=True)
        R.overlay_skeleton(im, pts, P.SKELETON_EDGES, PANEL[0], PANEL[1], R.VIEWS[view], PPS, CENTRE)
        panels.append(R.label(im, f"SR-Rig skeleton ({profile.id}) — {view}"))
    # the same skeleton, unposed, with the joint names
    bones0 = P.pose(profile, {})
    pts0 = P.skeleton_points(profile, bones0)
    ghost0 = [bones0[n].to_world(m.recolored(GHOST)) for n, m in kit.items()]
    im = R.render(ghost0, 360, PANEL[1], "front", PPS, CENTRE)
    R.overlay_skeleton(im, pts0, P.SKELETON_EDGES, 360, PANEL[1], R.VIEWS["front"], PPS, CENTRE)
    proj = R.project(np.array([pts0[n] for n in ("Neck", "RightShoulder", "RightElbow", "RightWrist", "Waist", "Root", "RightHip", "RightKnee", "RightAnkle")]),
                     360, PANEL[1], R.VIEWS["front"], PPS, CENTRE)
    d = ImageDraw.Draw(im)
    for (x, y), n in zip(proj, ("Neck", "Shoulder", "Elbow", "Wrist", "Waist", "Root/HRP", "Hip", "Knee", "Ankle")):
        d.text((x + 8, y - (22 if n == "Neck" else 7)), n, fill=R.INK, font=R.font(12))
    panels.append(R.label(im, "15 Motor6D joints, R15 names — unposed"))
    body = R.hstack(panels)
    cap = (f"A. The underlying skeleton: SR-Rig v1 joints and part names unchanged; only the BodyProfile numbers move. "
           f"{profile.id}: {profile.height:.2f} studs, {profile.heads:.2f} heads, head centre +{profile.head_offset:.2f} above the HRP (v1: +1.45), "
           f"shoulders {profile.shoulder_span:.2f}. Grey = the Tier 1 body kit, which Tier 2/3 shells replace slot-for-slot (no hidden limb).")
    return R.title(R.caption(body, cap), "A — human base skeleton underneath")


def sheet_proportions() -> Image.Image:
    rest = {"RightShoulder": {"spread": 8}, "LeftShoulder": {"spread": 8}, "RightElbow": {"swing": 6}, "LeftElbow": {"swing": 6}}
    panels = []
    for prof in P.candidates():
        bones = P.pose(prof, rest)
        kit = P.body_kit(prof, trousers=(96, 100, 118), shirt=(172, 154, 122))
        world = [bones[n].to_world(m) for n, m in kit.items()]
        world += [bones["Head"].to_world(p.mesh) for p in K.face(prof, "neutral")]
        im = R.render(world, 260, PANEL[1], "front", PPS, CENTRE)
        R.label(im, f"{prof.id}: {prof.height:.2f} st, {prof.heads:.2f} heads", size=13)
        im2 = R.render(world, 260, PANEL[1], "left 3/4", PPS, CENTRE)
        panels.append(R.stack([im, im2]))
    body = R.hstack(panels)
    cap = ("V2 proportion studies on the same skeleton (same joint list, same HRP height). v1 = the Step 0 body for reference. "
           "P1 keeps v1's frame with V2 hands/feet; P2 (recommended) is 3.2 heads with shorter shins, forearms thicker than the upper arms, "
           "0.90-wide hands and 1.2-long boots; P3 is 2.8 heads and crowds the hat/hair slot. Every Tier 1/2/3 sheet below uses P2.")
    return R.title(R.caption(body, cap), "A2 — proportion candidates (studies, not a decision)")


# ===== B/C/D. tiers =================================================================
def character_sheet(ch: C.Character, letter: str, note: str) -> Image.Image:
    world = ch.world_meshes()
    panels = [panel(world, v, text=f"{ch.id} — {v}") for v in ("front", "left 3/4", "back")]
    sil = R.silhouette(world, PANEL[0], PANEL[1], "front", PPS, CENTRE)
    R.label(sil, "silhouette")
    pps40 = PV.PX_PER_STUD_AT_40
    g40 = R.render(world, 300, 240, "gameplay", pps40, (0, 2.8, 0))
    R.label(g40, "~40 studs (19.3 px/stud)", size=12)
    g20 = R.render(world, 300, 240, "gameplay", pps40 * 2, (0, 2.8, 0))
    R.label(g20, "~20 studs", size=12)
    right = R.stack([g40, g20], pad=4)
    body = R.hstack(panels + [sil, right])
    b = ch.budget()
    cap = (f"{note}\nBudget: {b['baseParts']} parts, {b['welds']} welds, {b['motor6d']} Motor6D, {b['bespokeMeshes']} bespoke meshes, "
           f"{b['triangles']:,} triangles (Tier {ch.tier} caps: {TIER_CAPS[ch.tier]['baseParts']} parts, {TIER_CAPS[ch.tier]['welds']} welds, "
           f"{TIER_CAPS[ch.tier]['bespokeMeshes']} bespoke, {TIER_CAPS[ch.tier]['triangles']:,} triangles).")
    return R.title(R.caption(body, cap), f"{letter} — {ch.label}")


def sheet_tier_ladder(profile: P.BodyProfile, cast: list[C.Character]) -> Image.Image:
    """Skeleton -> Tier 1 -> Tier 2 -> Tier 3 in one row, same pose family, same scale."""
    bones = P.pose(profile, cast[0].rest)
    kit = P.body_kit(profile)
    ghost = [bones[n].to_world(m.recolored(GHOST)) for n, m in kit.items()]
    im = R.render(ghost, *PANEL, "left 3/4", PPS, CENTRE)
    R.overlay_skeleton(im, P.skeleton_points(profile, bones), P.SKELETON_EDGES, PANEL[0], PANEL[1], R.VIEWS["left 3/4"], PPS, CENTRE)
    panels = [R.label(im, "skeleton + body kit")]
    for ch in cast:
        panels.append(panel(ch.world_meshes(), "left 3/4", text=f"Tier {ch.tier}"))
    sils = [R.silhouette(ch.world_meshes(), PANEL[0], PANEL[1], "front", PPS, CENTRE) for ch in cast]
    body = R.stack([R.hstack(panels), R.hstack([Image.new("RGB", PANEL, R.SKY)] + sils)])
    cap = ("The same 15-bone skeleton under all three. Tier 1 shows the common kit; Tier 2 hides it under reusable shells; "
           "Tier 3 adds character-specific meshes and asymmetry. Bottom row: front silhouettes — each tier should be identifiable in solid black.")
    return R.title(R.caption(body, cap), "B/C/D — the three visual tiers on one skeleton")


# ===== E. Gianluca V2 =================================================================
def sheet_e(g: C.Character) -> tuple[Image.Image, Image.Image]:
    world = g.world_meshes()
    turn = R.hstack([panel(world, v, text=f"Gianluca V2 — {v}") for v in ("front", "back", "left 3/4", "right 3/4")])
    pps40 = PV.PX_PER_STUD_AT_40
    g40 = R.render(world, 420, 300, "gameplay", pps40, (0, 2.8, 0)); R.label(g40, "gameplay distance ~40 studs (19.3 px/stud)")
    g20 = R.render(world, 420, 300, "gameplay", pps40 * 2, (0, 2.8, 0)); R.label(g20, "~20 studs (38.6 px/stud)")
    sil_f = R.silhouette(world, 300, 420, "front", PPS, CENTRE); R.label(sil_f, "silhouette — front")
    sil_q = R.silhouette(world, 300, 420, "left 3/4", PPS, CENTRE); R.label(sil_q, "silhouette — 3/4")
    sil_b = R.silhouette(world, 300, 420, "back", PPS, CENTRE); R.label(sil_b, "silhouette — back")
    row2 = R.hstack([sil_f, sil_q, sil_b, R.stack([g40, g20], pad=4)])
    cap = ("E. Gianluca V2 on P2: bespoke pinned ranger hat with band + feather, tousled hair (fringe shards, side locks, nape tufts), "
           "V2 face 'worried', wrapped scarf with a knot and tail on his left, shoulder mantle, layered coat over a tunic front, "
           "wide sleeves (left one rolled), leather bracers, mitten hands, belt + brass buckle, pouch on the left hip, empty Chim collar on the right, "
           "split coat tails, oversized cuffed boots, planted bell-cane in the right hand. Name, role, prompt and dialogue contracts untouched.")
    sheet = R.title(R.caption(R.stack([turn, row2]), cap), "E — Gianluca V2 (human style test)")
    # head close-up + expression strip
    bones = P.pose(g.profile, g.rest)
    hp = tuple(bones["Head"].p)
    head = g.world_meshes(include=lambda p: p.bone in ("Head", "UpperTorso"))
    hc = [R.render(head, 400, 400, v, 140, hp) for v in ("front", "left 3/4", "right 3/4")]
    for im, v in zip(hc, ("front", "left 3/4", "right 3/4")):
        R.label(im, f"head close-up — {v}")
    strip = []
    for ex in ("neutral", "happy", "worried", "surprised", "angry"):
        gx = C.gianluca_v2(g.profile, expression=ex)
        bx = P.pose(gx.profile, gx.rest)
        hm = gx.world_meshes(bx, include=lambda p: p.bone == "Head")
        im = R.render(hm, 180, 200, "front", 62, tuple(bx["Head"].p), ground_y=None)
        strip.append(R.label(im, ex, size=12))
    row = R.hstack(hc)
    exp = R.hstack(strip)
    cap2 = ("Face V2: the same seven driven parts as Step 0 (EyeL/R, PupilL/R, BrowL/R, Mouth on FaceJoint Motor6Ds) with a new visual language — "
            "large egg-shaped eyes with a fixed highlight, tapered brows, a small curved mouth, no nose. Expression strip at ~20-stud pixel scale.")
    close = R.title(R.caption(R.stack([row, exp]), cap2), "E2 — Gianluca V2 head close-up and expressions")
    return sheet, close


# ===== F. v1 / v1.1 / V2 ==============================================================
def legacy_gianlucas(H: Harness):
    """Build Gianluca on the Step 0 v1 body and on the v1.1 proposal through the real
    NpcForge (harness), exactly as docs/npc/previews/gianluca-v1-vs-v11-proposal.png was made."""
    results = F.build_segments(H)
    root = import_root(H, results)
    seg = {r.name: r for r in results}
    forge = H.forge()
    gia, _ = forge.Build("Gianluca", H.table(importRoot=root))
    gia.Parent = H.stub.services.Workspace
    variant = chunky_variant(H)
    shapes = dict(F.SHAPES)
    shapes["Head"] = F.SegmentShape(bevel=0.30, taper_bottom=0.88, taper_bottom_span=0.35, taper_top=0.94, taper_top_span=0.25, taper_steps=2)
    res11 = F.build_segments(H, variant, shapes=shapes)
    root11 = import_root(H, res11, name=f"npc_body_{variant}")
    seg11 = {r.name: r for r in res11}
    grec = H.require("ReplicatedStorage/Modules/NpcKit/NpcCharacters/Gianluca")
    g11 = H.lua.eval("function(r) local t = {} for k, v in pairs(r) do t[k] = v end return t end")(grec)
    g11["bodyType"] = variant; g11["id"] = "Gianluca_v11"; g11["rootName"] = "Gianluca_v11"
    gia11, _ = forge.Build(g11, H.table(importRoot=root11))
    gia11.Parent = H.stub.services.Workspace
    Budget = H.require("ServerStorage/NpcBudget")
    rv = Budget.review(gia, 2, "human")
    rows = {r.name: (r.value, r.limit) for r in [rv.rows[i] for i in range(1, len(rv.rows) + 1)]}
    return (PV.scene_from_model(H, gia, seg), PV.scene_from_model(H, gia11, seg11), rows, F.body_triangles(results), F.body_triangles(res11))


def sheet_f(g: C.Character, v1_tris, v11_tris) -> Image.Image:
    world = g.world_meshes()
    w, h = 320, 440
    c1 = (0, 2.75, 0)
    cols = [(R.render(v1_tris, w, h, "front", PPS, c1), R.render(v1_tris, w, h, "left 3/4", PPS, c1), R.silhouette(v1_tris, w, h, "front", PPS, c1), "v1 — Step 0 (approved framework)"),
            (R.render(v11_tris, w, h, "front", PPS, c1), R.render(v11_tris, w, h, "left 3/4", PPS, c1), R.silhouette(v11_tris, w, h, "front", PPS, c1), "v1.1 — proportion proposal (D-11)"),
            (R.render(world, w, h, "front", PPS, CENTRE), R.render(world, w, h, "left 3/4", PPS, CENTRE), R.silhouette(world, w, h, "front", PPS, CENTRE), "V2 — this study")]
    panels = []
    for f, q, s, text in cols:
        R.label(f, text)
        panels.append(R.stack([f, q, s], pad=4))
    body = R.hstack(panels)
    cap = ("Same camera, same 60 px/stud. v1 and v1.1 are the real NpcForge builds (harness) of the Step 0 recipe: voxel-baked body + blockout accessories. "
           "V2 keeps the skeleton and the Motor6D/face/NpcLife architecture and replaces every visible mesh with authored shells.")
    return R.title(R.caption(body, cap), "F — Gianluca: current v1  |  proposed v1.1  |  V2")


# ===== G. ownership ====================================================================
def sheet_g(g: C.Character) -> Image.Image:
    bones = P.pose(g.profile, g.rest)

    def coloured(pred):
        out = []
        for p in g.pieces:
            m = p.mesh.recolored(OWN_COLORS[p.ownership])
            out.append(m if p.world else bones[p.bone].to_world(m))
            if not pred(p):
                out.pop()
        return out

    kit = P.body_kit(g.profile)
    ghost = [bones[n].to_world(m.recolored(GHOST)) for n, m in kit.items()]
    im0 = R.render(ghost, *PANEL, "left 3/4", PPS, CENTRE)
    R.overlay_skeleton(im0, P.skeleton_points(g.profile, bones), P.SKELETON_EDGES, PANEL[0], PANEL[1], R.VIEWS["left 3/4"], PPS, CENTRE)
    R.label(im0, "shared skeleton (+ kit ghost)")
    im1 = panel(coloured(lambda p: p.ownership == "skeleton"), "left 3/4", text="kit meshes that stay visible (grey)")
    im2 = panel(coloured(lambda p: p.ownership in ("skeleton", "reusable")), "left 3/4", text="+ reusable library meshes (blue)")
    im3 = panel(coloured(lambda p: True), "left 3/4", text="+ character-specific meshes (orange)")
    im4 = panel(coloured(lambda p: True), "front", text="front")
    body = R.hstack([im0, im1, im2, im3, im4])
    # legend + piece table
    lines = []
    for own, title_ in (("skeleton", "SHARED SKELETON / KIT (grey)"), ("reusable", "REUSABLE MESH (blue)"), ("specific", "CHARACTER-SPECIFIC MESH (orange)")):
        names = [f"{p.name}{'*' if p.slot else ''}" for p in g.pieces if p.ownership == own]
        tris = sum(p.tris for p in g.pieces if p.ownership == own)
        lines.append(f"{title_}: {len(names)} pieces, {tris:,} tris — " + ", ".join(names))
    lines.append("* = slot piece (it IS the bone's visible MeshPart; no hidden limb, no extra weld). Everything else is welded to the bone named in its recipe entry.")
    cap = "\n".join(lines)
    return R.title(R.caption(body, cap, size=12), "G — which pieces are shared skeleton, reusable mesh, character-specific mesh")


# ===== H. budgets =======================================================================
def sheet_h(cast: list[C.Character], v1_rows: dict, v1_body_tris: int, v11_body_tris: int) -> tuple[Image.Image, dict]:
    rows = []
    v1_parts, v1_welds, v1_m6 = v1_rows.get("baseParts", (41, 49))[0], v1_rows.get("welds", (17, 18))[0], v1_rows.get("motor6d", (22, 22))[0]
    v1_bespoke = str(v1_rows.get("bespokeMeshes", (0, 3))[0]) + " (collar was a Part)"
    rows.append(("Gianluca v1 (Step 0, blockout accessories)", 2, v1_parts, v1_welds, v1_m6, v1_bespoke, f"{v1_body_tris:,} body + primitives", "PASS w/ blockout allowance"))
    rows.append(("Gianluca v1.1 (proportion proposal)", 2, v1_parts, v1_welds, v1_m6, v1_bespoke, f"{v11_body_tris:,} body + primitives", "PASS w/ blockout allowance"))
    data = {}
    for ch in cast:
        b = ch.budget()
        caps = TIER_CAPS[ch.tier]
        ok = b["baseParts"] <= caps["baseParts"] and b["welds"] <= caps["welds"] and b["motor6d"] <= caps["motor6d"] and b["bespokeMeshes"] <= caps["bespokeMeshes"] and b["triangles"] <= caps["triangles"]
        rows.append((ch.label, ch.tier, b["baseParts"], b["welds"], b["motor6d"], str(b["bespokeMeshes"]), f"{b['triangles']:,} (all meshes)", "PASS" if ok else "OVER"))
        data[ch.id] = b
    # Gianluca V2 against the Tier 2 envelope as well (his recipe says tier = 2)
    g = cast[-1].budget()
    c2 = TIER_CAPS[2]
    fit2 = g["baseParts"] <= c2["baseParts"] and g["welds"] <= c2["welds"] and g["bespokeMeshes"] <= c2["bespokeMeshes"] and g["triangles"] <= c2["triangles"]
    rows.append(("Gianluca V2 measured against TIER 2 caps (38 / 14 / 22 / 3 / 9,000)", 2, g["baseParts"], g["welds"], g["motor6d"], str(g["bespokeMeshes"]), f"{g['triangles']:,}", "FITS" if fit2 else "OVER"))
    header = ("character", "tier", "parts", "welds", "Motor6D", "bespoke", "triangles", "verdict")
    widths = (430, 40, 60, 60, 70, 150, 200, 200)
    W = sum(widths) + 20
    H_ = 30 * (len(rows) + 3) + 90
    img = Image.new("RGB", (W, H_), R.PAPER)
    d = ImageDraw.Draw(img)
    x = 10
    for hname, wd in zip(header, widths):
        d.text((x, 12), hname, fill=R.INK, font=R.font(14)); x += wd
    d.line([(10, 36), (W - 10, 36)], fill=R.INK, width=1)
    for i, r in enumerate(rows):
        x = 10
        y = 46 + i * 30
        for val, wd in zip(r, widths):
            d.text((x, y), str(val), fill=R.INK, font=R.font(13)); x += wd
    y = 46 + len(rows) * 30 + 8
    caps_txt = " · ".join(f"T{t} {c['baseParts']} parts / {c['welds']} welds / {c['bespokeMeshes']} bespoke / {c['triangles']:,} tris" for t, c in sorted(TIER_CAPS.items()))
    note = (f"Tier caps (NpcBudget.Limits.human): {caps_txt}. V2 counts every visible triangle; v1 counted the baked body only (accessories were Parts). "
            "V2 shells cost fewer triangles than the v1 voxel body because they are authored lofts (8–14 sides) instead of greedy-merged 0.05-stud lattices. "
            "Parts = pieces + HumanoidRootPart + collider (Tier 2/3); welds = welded pieces + collider; Motor6D = 15 rig + 7 face.")
    for i, line in enumerate(R.wrap(note, W - 20, 12)):
        d.text((10, y + i * 17), line, fill=R.INK, font=R.font(12))
    return R.title(img, "H — part / triangle budget comparison", bg=R.PAPER), data


# ===== export the V2 shells as an Import 3D batch (proof the pieces are Roblox-compatible) =====
def export_glb(cast: list[C.Character]) -> dict:
    from brainrot_forge.export_glb import write_glb
    GLB_OUT.mkdir(parents=True, exist_ok=True)
    out = {}
    for ch in cast:
        class _M:  # duck-typed VoxelModel for write_glb: name + palette
            name = ch.id
            palette = {}
        roles = {}
        for p in ch.pieces:
            role = p.name
            _M.palette[role] = "#%02x%02x%02x" % p.mesh.color
            roles[role] = p.mesh.to_forge_mesh(role)
        path = GLB_OUT / f"{ch.id}.glb"
        write_glb(path, [(_M, roles)])
        out[ch.id] = {"glb": str(path.relative_to(TOOLS)), "nodes": len(roles), "bytes": path.stat().st_size}
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    H = Harness()
    load_caps(H)
    profile = P.profile("P2")
    cast = C.cast(profile)
    villager, merchant, gianluca = cast
    summary = {"profile": profile.summary(), "candidates": [p.summary() for p in P.candidates()]}

    R.save(sheet_a(profile, gianluca.rest), OUT / "v2-A-skeleton.png")
    R.save(sheet_proportions(), OUT / "v2-A2-proportion-studies.png")
    R.save(character_sheet(villager, "B", "Tier 1: the common body kit shows (skin arms, kit legs and shoes); hair crop, rope belt and the V2 face are the only additions."), OUT / "v2-B-tier1-villager.png")
    R.save(character_sheet(merchant, "C", "Tier 2: reusable shells replace every visible slot (shirt, rolled puff sleeves, work boots) plus cap, side-swept hair, neckerchief, apron, satchel on one hip with the strap over the other shoulder, one wrist cuff — zero bespoke meshes."), OUT / "v2-C-tier2-merchant.png")
    R.save(character_sheet(gianluca, "D", "Tier 3: the same reusable kit plus character-specific meshes (pinned hat + band/feather, Chim collar) and an asymmetric arrangement (rolled left sleeve, scarf tail, pouch left, collar right, cane right)."), OUT / "v2-D-tier3-gianluca.png")
    R.save(sheet_tier_ladder(profile, cast), OUT / "v2-BCD-tier-ladder.png")
    e1, e2 = sheet_e(gianluca)
    R.save(e1, OUT / "v2-E-gianluca-turnaround.png")
    R.save(e2, OUT / "v2-E2-gianluca-head.png")

    v1_tris, v11_tris, v1_rows, v1_body, v11_body = legacy_gianlucas(H)
    R.save(sheet_f(gianluca, v1_tris, v11_tris), OUT / "v2-F-gianluca-v1-v11-v2.png")
    R.save(sheet_g(gianluca), OUT / "v2-G-piece-ownership.png")
    h_img, budgets = sheet_h(cast, v1_rows, v1_body, v11_body)
    R.save(h_img, OUT / "v2-H-budgets.png")
    summary["budgets"] = budgets
    summary["v1"] = {"rows": {k: list(v) for k, v in v1_rows.items()}, "bodyTriangles": v1_body}
    summary["v11"] = {"bodyTriangles": v11_body}
    summary["glb"] = export_glb(cast)
    summary["pieces"] = {ch.id: [{"name": p.name, "bone": p.bone, "slot": p.slot, "ownership": p.ownership, "category": p.category, "tris": p.tris} for p in ch.pieces] for ch in cast}

    # contact sheet
    sheets = [Image.open(OUT / n) for n in ("v2-BCD-tier-ladder.png", "v2-E-gianluca-turnaround.png", "v2-F-gianluca-v1-v11-v2.png")]
    wmax = max(s.width for s in sheets)
    scaled = [s.resize((wmax, int(s.height * wmax / s.width))) if s.width != wmax else s for s in sheets]
    contact = R.stack(scaled)
    R.label(contact, "NPC-01 V2 character art study — harness renders of the study kit; not Studio captures; art direction NOT final until approved", (8, contact.height - 20), 12)
    R.save(contact, OUT / "v2-study-sheet.png")
    (OUT / "v2-summary.json").write_text(json.dumps(summary, indent=2, default=str))
    print(json.dumps(budgets, indent=1))
    print(f"sheets -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
