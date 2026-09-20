"""study25.py — the combined V2.5 NPC art study: global tiers + Gianluca as the old veteran.
Renders to docs/npc/previews/v25/ and writes v25-summary.json. Visual study only.

    cd tools && python -m npc_kit.v2.study25
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from npc_kit import preview as PV
from npc_kit.harness import Harness
from npc_kit.v2 import characters as C2
from npc_kit.v2 import characters25 as C
from npc_kit.v2 import kit25 as K25
from npc_kit.v2 import profiles as P
from npc_kit.v2 import render as R
from npc_kit.v2 import study as S
from npc_kit.v2.study import CENTRE, GHOST, PANEL, PPS, TIER_CAPS, TOOLS, character_sheet, export_glb, legacy_gianlucas, load_caps, panel, sheet_a, sheet_g, sheet_tier_ladder

OUT = S.REPO / "docs" / "npc" / "previews" / "v25"
S.GLB_OUT = TOOLS / "out" / "npc_v25_study"


# ===== E1. turnaround ===================================================================
def sheet_e1(g) -> Image.Image:
    world = g.world_meshes()
    c = (0, 3.15, 0)
    turn = R.hstack([panel(world, v, h=480, pps=54, centre=c, text=f"Gianluca V2.5 — {v}") for v in ("front", "back", "left 3/4", "right 3/4")])
    pps40 = PV.PX_PER_STUD_AT_40
    g40 = R.render(world, 420, 300, "gameplay", pps40, (0, 2.9, 0)); R.label(g40, "gameplay distance ~40 studs (19.3 px/stud)")
    g20 = R.render(world, 420, 300, "gameplay", pps40 * 2, (0, 2.9, 0)); R.label(g20, "~20 studs (38.6 px/stud)")
    sils = []
    for v in ("front", "left 3/4", "back"):
        s = R.silhouette(world, 300, 480, v, 54, c); R.label(s, f"silhouette — {v}"); sils.append(s)
    row2 = R.hstack(sils + [R.stack([g40, g20], pad=4)])
    cap = ("E. Gianluca V2.5 — OLD VETERAN: gray swept-back hair with a receding hairline, short gray beard + moustache + sideburns, heavy brows, "
           "lidded eyes, age lines; hood pushed down, faded scarf pinned by a tarnished unit clasp, layered tunic under a worn coat with frayed tails, "
           "cracked shoulder plate on his left, patched left sleeve, old belt with pouch (left) and the empty Chim collar + bell (right), worn gloves, "
           "reinforced boots; shortened war spear used as a walking staff in his right hand. Veteran posture: forward lean, weight on the staff side. "
           "Name, role, prompt and dialogue contracts untouched.")
    return R.title(R.caption(R.stack([turn, row2]), cap), "E1 — Gianluca V2.5 turnaround, silhouettes, gameplay distance")


# ===== E2. face + expressions =============================================================
def sheet_e2(g) -> Image.Image:
    bones = P.pose(g.profile, g.rest)
    hp = tuple(bones["Head"].p)
    head = g.world_meshes(include=lambda p: p.bone in ("Head", "UpperTorso"))
    close = []
    for v in ("front", "left 3/4", "right 3/4"):
        im = R.render(head, 400, 400, v, 140, hp); R.label(im, f"face close-up — {v}"); close.append(im)
    rows = []
    for scale, label in ((100, "expressions — close"), (38.6, "expressions at ~20 studs")):
        strip = []
        for ex in ("neutral", "happy", "worried", "angry", "suspicious", "tired", "shocked", "serious"):
            gx = C.gianluca_v25(g.profile, expression=ex, rest={"Neck": {}})
            bx = P.pose(gx.profile, gx.rest)
            hm = gx.world_meshes(bx, include=lambda p: p.bone == "Head")
            size = 190 if scale >= 100 else 120
            im = R.render(hm, size, size, "front", scale * (0.88 if scale >= 100 else 1.0), tuple(bx["Head"].p), ground_y=None)
            strip.append(R.label(im, ex if scale >= 100 else "", size=12))
        row = R.hstack(strip)
        if scale < 100:
            R.label(row, label, (8, 6), 12)
        rows.append(row)
    cap = ("Face V2.5 language: moderate almond eyes (21 % of head width, not mascot eyes), a skin-coloured upper lid on the Head mesh, a dark lash line "
           "that belongs to the Brow part and follows its lift/tilt, heavy shaped brows, a small mouth, a nose wedge, stylised age lines (welded, static). "
           "Same seven driven parts as Step 0 (EyeL/R, PupilL/R, BrowL/R, Mouth). Eight states: neutral, happy, worried, angry, suspicious (asymmetric brows), "
           "tired, shocked, serious — shown close and at ~20-stud pixel scale.")
    return R.title(R.caption(R.stack([R.hstack(close)] + rows), cap), "E2 — Gianluca V2.5 face close-up and expression sheet")


# ===== E3. hair study =====================================================================
def sheet_e3(g) -> Image.Image:
    panels = []
    for hair in ("sweptback", "cropped", "tiedback"):
        for bd in ("short", "stubble", "moustache"):
            gx = C.gianluca_v25(g.profile, hair=hair, beard_style=bd)
            bx = P.pose(gx.profile, gx.rest)
            hm = gx.world_meshes(bx, include=lambda p: p.bone in ("Head", "UpperTorso"))
            im = R.render(hm, 250, 250, "left 3/4", 88, tuple(bx["Head"].p))
            panels.append(R.label(im, f"{hair} + {bd}", size=12))
    grid = R.grid(panels, 3)
    # chosen + hat-on + back
    chosen = []
    for v, hat in (("front", False), ("back", False), ("left 3/4", True)):
        gx = C.gianluca_v25(g.profile, hat=hat)
        bx = P.pose(gx.profile, gx.rest)
        hm = gx.world_meshes(bx, include=lambda p: p.bone in ("Head", "UpperTorso"))
        im = R.render(hm, 250, 250, v, 88, tuple(bx["Head"].p))
        chosen.append(R.label(im, "chosen: sweptback + short — " + ("with the old ranger hat pushed back" if hat else v), size=12))
    body = R.hstack([grid, R.stack(chosen)])
    cap = ("Hair study: three gray treatments (swept back with a receding hairline; cropped; swept back and tied at the nape) × three facial-hair "
           "treatments (short beard + moustache; stubble; moustache only), all with sideburns. Chosen: swept back + short beard — the strongest age and "
           "silhouette read at 40 studs. Right column: the chosen head front / back, and with the old ranger hat pushed back so the hair stays visible.")
    return R.title(R.caption(body, cap), "E3 — Gianluca V2.5 hair and facial-hair study")


# ===== E4. outfit layers ===================================================================
def sheet_e4(g) -> Image.Image:
    bones = P.pose(g.profile, g.rest)
    kit = P.body_kit(g.profile)
    ghost = [bones[n].to_world(m.recolored(GHOST)) for n, m in kit.items()]
    panels = []
    shown: set[str] = set()
    for label, names in C.LAYERS:
        if names is None:
            im = R.render(ghost, 250, 420, "left 3/4", 56, CENTRE)
            R.overlay_skeleton(im, P.skeleton_points(g.profile, bones), P.SKELETON_EDGES, 250, 420, R.VIEWS["left 3/4"], 56, CENTRE)
        else:
            shown |= names
            meshes = g.world_meshes(bones, include=lambda p, s=set(shown): p.name in s)
            # ghost the kit parts whose slot has not been dressed yet
            slots_dressed = {p.bone for p in g.pieces if p.slot and p.name in shown}
            meshes += [bones[n].to_world(m.recolored(GHOST)) for n, m in kit.items() if n not in slots_dressed]
            im = R.render(meshes, 250, 420, "left 3/4", 56, CENTRE)
        panels.append(R.label(im, label, size=12))
    cap = ("Outfit layer breakdown on the P2 skeleton (grey = undressed kit bones). Slot pieces replace the bone's own MeshPart (head, gloves, boots, coat body, "
           "sleeves, bracers, trousers block); everything else is welded to its bone. The costume is designed as one set: worn coat + tunic + hood + scarf "
           "in the same faded palette, leather for belt/pouch/bracers/gloves, one iron remnant, brass only on the clasp, buckle and bell.")
    return R.title(R.caption(R.hstack(panels), cap), "E4 — Gianluca V2.5 outfit layer breakdown")


# ===== E5. the war remnant ==================================================================
def sheet_e5(g) -> Image.Image:
    bones = P.pose(g.profile, g.rest)
    ut = bones["UpperTorso"]
    lt = bones["LowerTorso"]
    world = g.world_meshes()
    # the clasp on the scarf (chest, right of centre), the plate on the left shoulder, the bell + collar at the belt
    def centre_of(name):
        p = next(p for p in g.pieces if p.name == name)
        m = p.mesh if p.world else bones[p.bone].to_world(p.mesh)
        return tuple(m.centroid())
    clasp_c, plate_c, belt_c = centre_of("Clasp"), centre_of("ShoulderPlate"), centre_of("Bell")
    a = R.render(world, 360, 360, (0.45, 0.25, -1), 190, clasp_c); R.label(a, "the clue: a tarnished unit clasp pinning the scarf")
    b = R.render(world, 360, 360, (-1, 0.6, -0.9), 160, plate_c); R.label(b, "armour remnant: notched, dented shoulder plate, left")
    c = R.render(world, 360, 360, (1, 0.3, 0.55), 150, belt_c); R.label(c, "the empty Chim collar and the bell, at the belt (from his right, behind the staff)")
    only = g.world_meshes(include=lambda p: p.name in ("Clasp",))
    d = R.render(only, 360, 360, (0.15, 0.2, -1), 520, tuple(clasp_c), ground_y=None); R.label(d, "clasp alone: shield with a twin-notch chevron in relief")
    cap = ("Elder Tung connection — ONE subtle clue: the small brass clasp that pins his scarf is an old unit clasp, a shield with a twin-notch chevron. "
           "It reads as 'a worn fastener' until later lore names the unit. No moon imagery. The cracked shoulder plate is the single armour remnant "
           "(equipment, not a clue); the empty Chim collar + silent bell carry his current story (the lost Chim) exactly as before.")
    return R.title(R.caption(R.hstack([a, b, c, d]), cap), "E5 — Gianluca V2.5 war-remnant detail")


# ===== E6. prop study =========================================================================
def sheet_e6(g) -> Image.Image:
    panels, sils = [], []
    for prop, label in (("spear", "A — shortened war spear as a walking staff (chosen)"), ("sword", "B — broken longsword carried point-down"), ("cane", "C — iron-shod veteran field cane")):
        gx = C.gianluca_v25(g.profile, prop=prop)
        w = gx.world_meshes()
        panels.append(R.label(R.render(w, 300, 480, "left 3/4", 56, (0, 3.1, 0)), label, size=12))
        sils.append(R.silhouette(w, 300, 480, "front", 56, (0, 3.1, 0)))
    # spear head close-up
    gx = C.gianluca_v25(g.profile, prop="spear")
    head_m = gx.world_meshes(include=lambda p: p.name.startswith("Spear"))
    top = max(m.verts[:, 1].max() for m in head_m)
    xs = np.concatenate([m.verts for m in head_m])
    hx = xs[xs[:, 1] > top - 1.2][:, 0].mean(); hz = xs[xs[:, 1] > top - 1.2][:, 2].mean()
    close = R.render(head_m, 300, 480, (0.6, 0.2, -1), 150, (hx, top - 0.7, hz), ground_y=None)
    R.label(close, "spear head: chipped leaf blade, socket, faded cloth tie", size=12)
    cap = ("Prop study. A wins: the tallest silhouette line (the head rides above his own), reads 'carried something from the war' rather than "
           "'needs a stick', and gives the idle a hand-on-weapon rest. B reads as trophy/relic and hides in the silhouette; C reads as a walking aid. "
           "The old bell moves to the belt beside the Chim collar so the quest prop survives the swap.")
    return R.title(R.caption(R.stack([R.hstack(panels + [close]), R.hstack(sils)]), cap), "E6 — Gianluca V2.5 prop study")


# ===== E7. posture and idle beats =================================================================
def sheet_e7(g) -> Image.Image:
    panels = []
    for label, beat in C.BEATS.items():
        gx = C.gianluca_v25(g.profile, expression=beat["expression"], rest=beat["rest"], look=beat["look"])
        w = gx.world_meshes()
        im = R.render(w, 300, 480, "left 3/4", 56, (0, 3.1, 0))
        bones = P.pose(gx.profile, gx.rest)
        face = R.render(gx.world_meshes(bones, include=lambda p: p.bone == "Head"), 300, 170, "front", 70, tuple(bones["Head"].p), ground_y=None)
        panels.append(R.label(R.stack([im, face], pad=4), label, size=12))
    cap = ("Animation personality (stills of the procedural beats; NpcMotion axes, no uploaded clips). IDLE: slow breathing, deliberate head turns, "
           "weight shifts onto the staff side, hand resting on the spear, an occasional roll of the plated shoulder (old injury). TALKING: restrained gestures — "
           "one finger point, a small dismissive wave, eye contact on the important line. WAR / ELDER TUNG REACTION (dialogue mentions Elder Tung, the war, "
           "Bacon Head, the old army): he straightens, stops moving, tightens the grip, looks away, face to 'tired' — understated, then back to idle.")
    return R.title(R.caption(R.hstack(panels), cap), "E7 — Gianluca V2.5 posture and idle personality beats")


# ===== F. V1 / V2 / V2.5 ===================================================================
def sheet_f(g, v1_tris) -> Image.Image:
    g2 = C2.gianluca_v2(g.profile)
    w, h = 320, 480
    c = (0, 2.95, 0)
    cols = [(v1_tris, "V1 — Step 0 (blockout)"), (g2.world_meshes(), "V2 — young ranger (rejected)"), (g.world_meshes(), "V2.5 — old veteran")]
    panels = []
    for meshes, text in cols:
        f = R.render(meshes, w, h, "front", PPS, c); R.label(f, text)
        q = R.render(meshes, w, h, "left 3/4", PPS, c)
        s = R.silhouette(meshes, w, h, "front", PPS, c)
        panels.append(R.stack([f, q, s], pad=4))
    cap = ("Same camera, same 60 px/stud. V1 is the real NpcForge harness build of the Step 0 recipe. V2 kept the skeleton and rebuilt the skin but read as a "
           "young ranger. V2.5 corrects the canon: age, history (the clasp, the plate, the spear), emotional weight (posture, lidded eyes, serious face) and "
           "silhouette (gray head shape, hood, spear line, heavy boots).")
    return R.title(R.caption(R.hstack(panels), cap), "F — Gianluca: V1  |  V2 young ranger  |  V2.5 old veteran")


# ===== H. budgets ============================================================================
def sheet_h(cast, v1_rows, v1_body, g2) -> tuple[Image.Image, dict]:
    rows = []
    v1_parts, v1_welds, v1_m6 = v1_rows["baseParts"][0], v1_rows["welds"][0], v1_rows["motor6d"][0]
    rows.append(("Gianluca V1 (Step 0, blockout accessories)", 2, v1_parts, v1_welds, v1_m6, "0", "—", f"{v1_body:,} body + primitives", "PASS w/ allowance"))
    b2 = g2.budget()
    rows.append(("Gianluca V2 (young ranger, rejected)", 2, b2["baseParts"], b2["welds"], b2["motor6d"], str(b2["bespokeMeshes"]), str(b2["reusableMeshes"]), f"{b2['triangles']:,}", "fits T2"))
    data = {}
    for ch in cast:
        b = ch.budget()
        caps = TIER_CAPS[ch.tier]
        ok = all(b[k] <= caps[k] for k in ("baseParts", "welds", "motor6d", "bespokeMeshes", "triangles"))
        rows.append((ch.label, ch.tier, b["baseParts"], b["welds"], b["motor6d"], str(b["bespokeMeshes"]), str(b["reusableMeshes"]), f"{b['triangles']:,}", "PASS" if ok else "OVER"))
        data[ch.id] = b
    header = ("character", "tier", "parts", "welds", "Motor6D", "bespoke", "reusable", "triangles", "verdict")
    widths = (400, 40, 60, 60, 70, 70, 70, 170, 130)
    W = sum(widths) + 20
    H_ = 30 * (len(rows) + 3) + 110
    img = Image.new("RGB", (W, H_), R.PAPER)
    d = ImageDraw.Draw(img)
    x = 10
    for hname, wd in zip(header, widths):
        d.text((x, 12), hname, fill=R.INK, font=R.font(14)); x += wd
    d.line([(10, 36), (W - 10, 36)], fill=R.INK, width=1)
    for i, r in enumerate(rows):
        x = 10
        for val, wd in zip(r, widths):
            d.text((x, 46 + i * 30), str(val), fill=R.INK, font=R.font(13)); x += wd
    y = 46 + len(rows) * 30 + 8
    caps_txt = " · ".join(f"T{t} {c['baseParts']} parts / {c['welds']} welds / {c['bespokeMeshes']} bespoke / {c['triangles']:,} tris" for t, c in sorted(TIER_CAPS.items()))
    note = (f"Caps (NpcBudget.Limits.human): {caps_txt}. Parts = pieces + HumanoidRootPart + collider (T2/T3); welds = welded pieces + collider; Motor6D = 15 rig + 7 face. "
            "V2/V2.5 count every visible triangle; V1 counted the baked body only. Tier 3 spends its extra budget on the head (beard, age lines), the hood, the plate, "
            "the patch and a 4-part spear — a modest increase, all under the Tier 3 caps with room left for a cutscene prop.")
    for i, line in enumerate(R.wrap(note, W - 20, 12)):
        d.text((10, y + i * 17), line, fill=R.INK, font=R.font(12))
    return R.title(img, "H — part / triangle budget comparison per tier", bg=R.PAPER), data


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    H = Harness()
    load_caps(H)
    profile = P.profile("P2")
    cast = C.cast(profile)
    villager, merchant, gianluca = cast
    summary = {"profile": profile.summary()}

    R.save(sheet_a(profile, gianluca.rest), OUT / "v25-A-skeleton.png")
    R.save(character_sheet(villager, "B", "Tier 1 — background: reusable tunic shell, plain sleeves, simple boots, cropped hair, moderate face, a skipping stone; no bespoke mesh."), OUT / "v25-B-tier1-villager.png")
    R.save(character_sheet(merchant, "C", "Tier 2 — named quest NPC: unique silhouette (cap, puff sleeves, apron, satchel), custom face combination (moustache + happy + lids), signature prop (coin sack), posture; no bespoke mesh."), OUT / "v25-C-tier2-merchant.png")
    R.save(character_sheet(gianluca, "D", "Tier 3 — major story NPC: bespoke silhouette, story in the appearance (spear, plate, clasp, collar + bell), custom head treatment, character-specific asymmetry."), OUT / "v25-D-tier3-gianluca.png")
    R.save(sheet_tier_ladder(profile, cast), OUT / "v25-BCD-tier-ladder.png")
    R.save(sheet_e1(gianluca), OUT / "v25-E1-gianluca-turnaround.png")
    R.save(sheet_e2(gianluca), OUT / "v25-E2-face-expressions.png")
    R.save(sheet_e3(gianluca), OUT / "v25-E3-hair-study.png")
    R.save(sheet_e4(gianluca), OUT / "v25-E4-outfit-layers.png")
    R.save(sheet_e5(gianluca), OUT / "v25-E5-war-remnant.png")
    R.save(sheet_e6(gianluca), OUT / "v25-E6-prop-study.png")
    R.save(sheet_e7(gianluca), OUT / "v25-E7-posture-beats.png")

    v1_tris, v11_tris, v1_rows, v1_body, v11_body = legacy_gianlucas(H)
    R.save(sheet_f(gianluca, v1_tris), OUT / "v25-F-v1-v2-v25.png")
    R.save(sheet_g(gianluca), OUT / "v25-G-piece-ownership.png")
    g2 = C2.gianluca_v2(profile)
    h_img, budgets = sheet_h(cast, v1_rows, v1_body, g2)
    R.save(h_img, OUT / "v25-H-budgets.png")
    summary["budgets"] = budgets
    summary["v2Young"] = g2.budget()
    summary["v1"] = {"rows": {k: list(v) for k, v in v1_rows.items()}, "bodyTriangles": v1_body}
    summary["glb"] = export_glb(cast)
    summary["pieces"] = {ch.id: [{"name": p.name, "bone": p.bone, "slot": p.slot, "ownership": p.ownership, "category": p.category, "tris": p.tris} for p in ch.pieces] for ch in cast}
    summary["beats"] = {k: {"expression": v["expression"], "rest": v["rest"]} for k, v in C.BEATS.items()}

    sheets = [Image.open(OUT / n) for n in ("v25-BCD-tier-ladder.png", "v25-E1-gianluca-turnaround.png", "v25-F-v1-v2-v25.png")]
    wmax = max(s.width for s in sheets)
    scaled = [s.resize((wmax, int(s.height * wmax / s.width))) if s.width != wmax else s for s in sheets]
    contact = R.stack(scaled)
    R.label(contact, "NPC-01 V2.5 character art study — harness renders of the study kit; not Studio captures; art direction NOT final until approved", (8, contact.height - 20), 12)
    R.save(contact, OUT / "v25-study-sheet.png")
    (OUT / "v25-summary.json").write_text(json.dumps(summary, indent=2, default=str))
    print(json.dumps({k: {kk: vv for kk, vv in v.items() if kk != "trianglesByOwnership"} for k, v in budgets.items()}, indent=1))
    print(f"sheets -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
