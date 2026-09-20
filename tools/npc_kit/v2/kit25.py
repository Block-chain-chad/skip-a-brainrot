"""kit25.py — the V2.5 visual kit: a more mature face language (moderate eyes, real
eyelids, lash line, shaped brows), ageing pieces, gray hair / facial hair styles, worn
ranger gear, a war remnant, and prop candidates. Builds on kit.py (V2 stays intact for
the comparison sheet).

Face contract unchanged: the seven driven parts are still EyeL/R, PupilL/R, BrowL/R,
Mouth on FaceJoint Motor6Ds (NpcFaceConfig API). What changed:
  * the upper eyelid is skin-coloured geometry on the Head mesh (free: same part),
    so the eye reads narrower / heavier without a new driven part;
  * the dark lash line is part of the Brow mesh and follows the brow's lift and tilt,
    which is what closes / opens the eye in the expression table;
  * beards, moustaches, sideburns and age lines are welded, static pieces.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

from npc_kit.v2 import lowpoly as L
from npc_kit.v2 import profiles as P
from npc_kit.v2.kit import Piece, egg

RGB = tuple[int, int, int]


# ===== face layout =====================================================================
@dataclass
class FaceStyle:
    eye_w: float = 0.21          # of head width
    eye_h: float = 0.26          # of head height
    eye_x: float = 0.20          # centre offset, of head width
    eye_y: float = -0.02         # of head height
    lid: float = 0.16            # fraction of the eye hidden under the upper lid (0.16 young .. 0.40 old)
    lid_slope: float = 4.0       # degrees: outer end of the lid lower (tired / mature)
    brow_thick: float = 0.085    # of head height
    brow_heavy: float = 0.0      # 0 = shaped, 1 = bushy veteran brows
    brow_gap: float = 0.07       # brow bar above the eye top, of head height
    mouth_w: float = 0.17        # of head width
    mouth_y: float = -0.31       # of head height
    nose: float = 0.0            # 0 = none, 1 = a small wedge
    age: float = 0.0             # 0 = none, 1 = full age lines


YOUNG = FaceStyle()
MATURE = FaceStyle(eye_h=0.22, lid=0.30, lid_slope=6.0, brow_thick=0.10, brow_heavy=0.6, nose=0.6, age=0.5)
VETERAN = FaceStyle(eye_w=0.215, eye_h=0.21, eye_y=-0.01, lid=0.32, lid_slope=7.0, brow_thick=0.11, brow_heavy=1.0, brow_gap=0.045,
                    mouth_w=0.15, mouth_y=-0.33, nose=1.0, age=1.0)

#                brow tilt (inner end up +), brow lift (of hh), lash follow, mouth curve, mouth width, eye height scale, iris scale
EXPRESSIONS = {
    "neutral":    dict(brow=-3, lift=0.00, curve=0.01, width=1.0, eye=1.00, iris=1.00),
    "happy":      dict(brow=-1, lift=0.02, curve=0.08, width=1.30, eye=0.90, iris=1.00),
    "worried":    dict(brow=14, lift=0.03, curve=-0.05, width=0.90, eye=1.00, iris=0.95),
    "angry":      dict(brow=-17, lift=-0.04, curve=-0.04, width=1.05, eye=0.80, iris=1.00),
    "suspicious": dict(brow=-8, lift=-0.02, curve=0.00, width=0.80, eye=0.72, iris=0.95, browL=dict(brow=6, lift=0.05), browR=dict(brow=-14, lift=-0.05)),
    "tired":      dict(brow=4, lift=-0.03, curve=-0.02, width=0.90, eye=0.62, iris=1.00),
    "shocked":    dict(brow=2, lift=0.11, curve=0.00, width=0.60, eye=1.15, iris=0.78, mouth_o=True),
    "serious":    dict(brow=-9, lift=-0.02, curve=-0.015, width=1.05, eye=0.88, iris=1.00),
    # aliases used by the V2 comparison recipe
    "surprised":  dict(brow=2, lift=0.11, curve=0.00, width=0.60, eye=1.15, iris=0.78, mouth_o=True),
    # the EXPORT rest: no brow tilt or lift, eyes at 1.0, a mild smile the runtime turns into every state
    # (NpcFaceConfig applies the eight states as deltas on top of this geometry)
    "rest":       dict(brow=0, lift=0.00, curve=0.035, width=1.0, eye=1.00, iris=1.00),
}


def layout(profile: P.BodyProfile, fs: FaceStyle, e: dict, side: int) -> dict:
    hw, hh, hd = profile.size("Head")
    eye_h = fs.eye_h * hh * e["eye"]
    eye_w = fs.eye_w * hw
    return dict(hw=hw, hh=hh, hd=hd, zf=-hd / 2, eye_w=eye_w, eye_h=eye_h, x=side * fs.eye_x * hw, y=fs.eye_y * hh,
                top=fs.eye_y * hh + fs.eye_h * hh / 2)            # `top` = the eye's neutral top edge (lids are static)


def face(profile: P.BodyProfile, expression: str = "neutral", fs: FaceStyle = YOUNG, iris: RGB = (48, 36, 34),
         brow: RGB = (64, 50, 40), mouth: RGB = (118, 52, 58), white: RGB = (248, 246, 240), look=(0.0, 0.0)) -> list[Piece]:
    """The seven driven face parts in the V2.5 language."""
    e = EXPRESSIONS[expression]
    out = []
    for side, tag in ((1, "R"), (-1, "L")):
        ex = dict(e)
        ex.update(e.get("brow" + tag, {}))
        lo = layout(profile, fs, e, side)
        hw, hh, hd, zf = lo["hw"], lo["hh"], lo["hd"], lo["zf"]
        ew, eh, x, y = lo["eye_w"], lo["eye_h"], lo["x"], lo["y"]
        # eye white: an almond, a little wider at the top; the static lid on the head hides its upper `lid` fraction
        poly = egg(12, ew / 2, eh / 2, 0.10)
        eye_m = L.extrude(poly, 0.05, white, f"Eye{tag}", z0=zf - 0.03).translated(x, y, 0)
        iw, ih = ew * 0.50 * e["iris"], eh * 0.66 * e["iris"]
        ix, iy = x - side * 0.012 * hw + look[0], y - 0.03 * hh + look[1]
        hl = L.extrude(L.superellipse(4, 0.026 * hw, 0.026 * hw, 8), 0.035, white, z0=zf - 0.075).translated(ix + side * iw * 0.18, iy + ih * 0.28, 0)
        out.append(Piece(f"Eye{tag}", "Head", L.merge([eye_m, hl], white, f"Eye{tag}"), "reusable", False, "face"))
        iris_m = L.extrude(egg(10, iw / 2, ih / 2, 0.06), 0.045, iris, f"Pupil{tag}", z0=zf - 0.05).translated(ix, iy, 0)
        out.append(Piece(f"Pupil{tag}", "Head", iris_m, "reusable", False, "face"))
        # brow bar (+ lash line): thicker at the inner end; bushy variant gets a broken top edge
        bl, bt = (0.26 + 0.04 * fs.brow_heavy) * hw, fs.brow_thick * hh
        bar = L.tapered_bar(bl, bt * (1.15 + 0.25 * fs.brow_heavy), bt * 0.75, tilt=-side * ex["brow"])
        if fs.brow_heavy > 0:
            # a couple of bristle notches along the top edge
            bar = np.array(list(bar[:2]) + [bar[2] + np.array([0, 0.012 * hh * fs.brow_heavy]), (bar[2] + bar[3]) / 2 + np.array([0, 0.03 * hh * fs.brow_heavy]),
                                             bar[3] + np.array([0, 0.01 * hh * fs.brow_heavy])])
        by = lo["top"] + fs.brow_gap * hh + ex["lift"] * hh
        brow_m = L.extrude(bar, 0.09, brow, f"Brow{tag}", z0=zf - 0.03)
        # lash line: the eye's visible top edge, following the brow's lift and tilt at half strength
        lash_len, lash_t = ew * 1.02, 0.022 * hh
        lash = L.tapered_bar(lash_len, lash_t * 1.3, lash_t * 0.9, tilt=-side * ex["brow"] * 0.5)
        lash_y = y + eh / 2 - fs.lid * eh + ex["lift"] * hh * 0.30
        lash_m = L.extrude(lash, 0.05, brow, z0=zf - 0.09)
        if side < 0:
            brow_m = brow_m.mirrored_x().translated(x, by, 0)
            lash_m = lash_m.mirrored_x().translated(x, lash_y, 0)
        else:
            brow_m = brow_m.translated(x, by, 0)
            lash_m = lash_m.translated(x, lash_y, 0)
        out.append(Piece(f"Brow{tag}", "Head", L.merge([brow_m, lash_m], brow, f"Brow{tag}"), "reusable", False, "face"))
    hw, hh, hd = profile.size("Head")
    zf = -hd / 2
    mw = fs.mouth_w * hw * e["width"]
    if e.get("mouth_o"):
        poly = L.superellipse(10, mw / 2, 0.055 * hh, 2.5)
    else:
        poly = L.curved_bar(mw, 0.035 * hh, e["curve"] * hh, n=5)
    mouth_m = L.extrude(poly, 0.05, mouth, "Mouth", z0=zf - 0.04).translated(0, fs.mouth_y * hh, 0)
    out.append(Piece("Mouth", "Head", mouth_m, "reusable", False, "face"))
    return out


def head_shell(profile: P.BodyProfile, skin: RGB, fs: FaceStyle = YOUNG, jaw: float = 0.90, name: str = "Head") -> Piece:
    """The Head slot mesh: the kit block plus skin-coloured upper eyelids (and a nose wedge)
    — geometry only, so the mature / heavy-lidded read costs no extra part."""
    hw, hh, hd = profile.size("Head")
    head = L.rounded_box((hw, hh, hd), n=12, p=3.2, r_bottom=0.22, r_top=0.28, taper_bottom=jaw, color=skin, name=name)
    neck = L.tube(L.superellipse(8, hw * 0.26, hd * 0.26, 3.0), [(-hh / 2 - 0.40, 1.0, 1.0), (-hh / 2 + 0.12, 1.0, 1.0)], skin, "Neck")
    parts = [head, neck]
    e = EXPRESSIONS["neutral"]
    for side in (1, -1):
        lo = layout(profile, fs, e, side)
        ew, eh, x, y, zf = lo["eye_w"], lo["eye_h"], lo["x"], lo["y"], lo["zf"]
        depth = fs.lid * eh + 0.05
        # a lid slab covering the top `lid` of the eye, sloping down toward the outer corner
        poly = np.array([[-ew / 2 - 0.05, 0.10], [ew / 2 + 0.05, 0.10], [ew / 2 + 0.05, -depth], [-ew / 2 - 0.05, -depth * 0.55]])
        if side > 0:
            poly = poly[:, :] * np.array([1, 1])
        lid = L.extrude(poly, 0.075, skin, z0=zf - 0.06)
        lid = lid.rotated(rz=-side * fs.lid_slope)
        if side < 0:
            lid = lid.mirrored_x()
        parts.append(lid.translated(x, y + eh / 2 + 0.02, 0))
    if fs.nose > 0:
        nb = np.array([[-0.06 * hw, -0.17 * hh, -hd / 2 + 0.01], [0.06 * hw, -0.17 * hh, -hd / 2 + 0.01], [0.05 * hw, -0.02 * hh, -hd / 2 + 0.01], [-0.05 * hw, -0.02 * hh, -hd / 2 + 0.01]])
        parts.append(L.shard(nb, np.array([0.0, -0.13 * hh, -hd / 2 - 0.11 * fs.nose]), skin))
    return Piece(name, "Head", L.merge(parts, skin, name), "skeleton", True, "body")


def age_lines(profile: P.BodyProfile, fs: FaceStyle, color: RGB, beard: bool = False) -> Piece:
    """Stylised ageing: under-eye forms, crow's feet, a forehead crease, nasolabial lines
    (skipped when a beard covers them). One welded piece in a darker skin tone."""
    hw, hh, hd = profile.size("Head")
    zf = -hd / 2
    e = EXPRESSIONS["neutral"]
    parts = []
    for side in (1, -1):
        lo = layout(profile, fs, e, side)
        ew, eh, x, y = lo["eye_w"], lo["eye_h"], lo["x"], lo["y"]
        bag = L.extrude(L.curved_bar(ew * 0.85, 0.028 * hh, 0.025 * hh, 5), 0.035, color, z0=zf - 0.02).translated(x, y - eh / 2 - 0.045 * hh, 0)
        parts.append(bag)
        for k in range(2):
            cf = L.extrude(L.tapered_bar(0.09 * hw, 0.022 * hh, 0.012 * hh, tilt=(14 - 28 * k)), 0.03, color, z0=zf - 0.01)
            if side < 0:
                cf = cf.mirrored_x()
            parts.append(cf.translated(x + side * (ew / 2 + 0.06 * hw), y + (0.05 - 0.10 * k) * hh, 0))
        if not beard:
            nl = L.extrude(L.tapered_bar(0.13 * hh, 0.02 * hh, 0.012 * hh, tilt=-62), 0.03, color, z0=zf - 0.01)
            if side < 0:
                nl = nl.mirrored_x()
            parts.append(nl.translated(side * 0.11 * hw, -0.22 * hh, 0))
    crease = L.extrude(L.curved_bar(0.36 * hw, 0.022 * hh, -0.02 * hh, 5), 0.03, color, z0=zf - 0.01).translated(0, 0.29 * hh, 0)
    parts.append(crease)
    return Piece("AgeLines", "Head", L.merge(parts, color, "AgeLines"), "reusable", False, "hair")


# ===== facial hair ====================================================================
def beard(profile: P.BodyProfile, style: str = "short", color: RGB = (176, 172, 164), sideburns: bool = True) -> Piece:
    """'short' = a cropped full beard hugging the jaw + moustache; 'stubble' = a thin jaw
    plate + moustache; 'moustache' = moustache only; 'goatee' = chin mass + moustache."""
    hw, hh, hd = profile.size("Head")
    zf = -hd / 2
    prof = L.superellipse(14, hw / 2, hd / 2, 3.2)
    parts = []

    def jaw_ring(y, sx, sz, hide_back=True, oz=0.0):
        r = L.ring_xz(prof, y, sx, sz, 0, oz)
        if hide_back:
            for i in range(len(r)):
                if r[i, 2] > 0.05 * hd:                      # behind the ears: tuck inside the head
                    r[i, 0] *= 0.80; r[i, 2] *= 0.70
        return r

    if style in ("short", "stubble", "goatee"):
        thick = {"short": 1.08, "stubble": 1.035, "goatee": 1.0}[style]
        drop = {"short": 0.14, "stubble": 0.05, "goatee": 0.14}[style]
        top_ring = jaw_ring(-0.30 * hh, thick * 0.99, thick * 0.99)
        for i in range(len(top_ring)):                       # the top edge dips under the mouth in the middle, rises to the sideburns at the sides
            xn = min(1.0, abs(top_ring[i, 0]) / (hw / 2))
            if top_ring[i, 2] < 0:
                top_ring[i, 1] = (-0.40 + 0.18 * xn ** 1.4) * hh
        rings = [top_ring, jaw_ring(-0.44 * hh, thick, thick, oz=-0.02),
                 jaw_ring(-hh / 2 - drop * 0.6, thick * 0.94 * 0.92, thick * 0.9, oz=-0.04), jaw_ring(-hh / 2 - drop, 0.60, 0.52, oz=-0.10)]
        if style == "goatee":
            rings = [L.ring_xz(prof, -0.30 * hh, 0.36, 0.30, 0, -hd / 2 * 0.72), L.ring_xz(prof, -hh / 2 - 0.02, 0.40, 0.30, 0, -hd / 2 * 0.74),
                     L.ring_xz(prof, -hh / 2 - drop, 0.26, 0.22, 0, -hd / 2 * 0.66)]
        parts.append(L.loft(rings, True, True, color, "Beard"))
    if style in ("short", "stubble", "goatee", "moustache"):
        for side in (1, -1):
            m = L.extrude(L.tapered_bar(0.17 * hw, 0.06 * hh, 0.035 * hh, tilt=-side * 22), 0.10, color, z0=zf - 0.06)
            if side < 0:
                m = m.mirrored_x()
            parts.append(m.translated(side * 0.10 * hw, -0.225 * hh, 0))
    if sideburns:
        for side in (1, -1):
            sb = L.extrude(np.array([[-0.06 * hw, 0.16 * hh], [0.06 * hw, 0.16 * hh], [0.05 * hw, -0.22 * hh], [-0.07 * hw, -0.22 * hh]]), 0.14, color) \
                .rotated(ry=side * 90).translated(side * (hw / 2 + 0.02), 0.0, -0.06 * hd)
            parts.append(sb)
    return Piece("Beard", "Head", L.merge(parts, color, "Beard"), "reusable", False, "hair")


# ===== hair (new styles) ================================================================
def hair(profile: P.BodyProfile, style: str = "sweptback", color: RGB = (182, 178, 170), name: str = "Hair") -> Piece:
    """'sweptback' — receding at the temples, clumps combed back, side and back masses, nape;
    'cropped' — short with a straight hairline and volume at the sides/back;
    'tiedback' — swept back into a short tail at the nape."""
    hw, hh, hd = profile.size("Head")
    top = hh / 2
    prof = L.superellipse(14, hw / 2, hd / 2, 3.0)

    def ring(y_back, y_front, sx, sz, ox=0.0, oz=0.0, temple_lift=0.0, amount=0.05, lobes=5, phase=0.0):
        r = L.ring_xz(L.wobble(prof, amount, lobes, phase), 0.0, sx, sz, ox, oz)
        zn = r[:, 2] / max(1e-6, np.abs(r[:, 2]).max())
        r[:, 1] = y_front + (y_back - y_front) * (zn + 1) / 2
        if temple_lift:
            # recede at the temples: front points that are off-centre rise
            for i in range(len(r)):
                if r[i, 2] < -0.2 * hd:
                    xn = min(1.0, abs(r[i, 0]) / (hw / 2))
                    r[i, 1] += temple_lift * (xn ** 1.5)
        return r

    if style == "sweptback":
        rings = [ring(-0.34 * hh, 0.40 * hh, 1.07, 1.07, 0, 0.02 * hd, temple_lift=0.12 * hh, amount=0.04),
                 ring(-0.02 * hh, 0.46 * hh, 1.12, 1.12, 0, 0.04 * hd, temple_lift=0.03 * hh, phase=1.0),
                 ring(0.34 * hh, top + 0.08, 1.08, 1.07, 0, 0.10 * hd, amount=0.04, phase=2.2),
                 ring(top + 0.14, top + 0.12, 0.82, 0.80, 0, 0.22 * hd, amount=0.06, lobes=4),
                 L.ring_xz(prof, top + 0.24, 0.30, 0.34, 0, 0.36 * hd)]
    elif style == "cropped":
        rings = [ring(-0.18 * hh, 0.34 * hh, 1.06, 1.05, amount=0.03), ring(0.10 * hh, 0.40 * hh, 1.10, 1.09, phase=1.0),
                 ring(0.40 * hh, 0.44 * hh, 1.04, 1.03, amount=0.04, phase=2.0), ring(top + 0.08, top + 0.06, 0.74, 0.74, amount=0.04, lobes=4),
                 L.ring_xz(prof, top + 0.16, 0.26, 0.26)]
    else:  # tiedback
        rings = [ring(-0.30 * hh, 0.38 * hh, 1.07, 1.07, 0, 0.02 * hd, temple_lift=0.08 * hh, amount=0.03),
                 ring(0.00 * hh, 0.45 * hh, 1.12, 1.12, 0, 0.04 * hd, temple_lift=0.02 * hh, phase=1.0),
                 ring(0.34 * hh, top + 0.08, 1.08, 1.07, 0, 0.10 * hd, amount=0.04, phase=2.2),
                 ring(top + 0.08, top + 0.05, 0.76, 0.78, 0, 0.18 * hd, lobes=4),
                 L.ring_xz(prof, top + 0.14, 0.26, 0.30, 0, 0.30 * hd)]
    # close the underside with a ring folded INSIDE the head (a centroid fan would slice
    # through the face plane and drape hair over the forehead)
    inner = rings[0].copy()
    inner[:, 0] *= 0.78; inner[:, 2] = inner[:, 2] * 0.78 + 0.04 * hd
    inner[:, 1] += 0.05 * hh
    parts = [L.loft([inner] + rings, True, True, color, name)]
    # combed-back clumps over the crown (shards lying backward)
    n = 5 if style != "cropped" else 3
    for i in range(n):
        u = (i + 0.5) / n - 0.5
        bx = u * 0.70 * hw
        by = top - 0.04 + 0.03 * math.cos(i * 1.7)
        bz = -0.25 * hd + 0.05 * hd * math.sin(i * 2.3)
        base = np.array([[bx - 0.07 * hw, by, bz], [bx + 0.07 * hw, by, bz], [bx + 0.06 * hw, by + 0.10, bz + 0.06 * hd], [bx - 0.06 * hw, by + 0.10, bz + 0.06 * hd]])
        tip = np.array([bx * 0.8 + 0.03 * hw, by + 0.13 + 0.05 * (i % 2), bz + (0.62 if style != "cropped" else 0.30) * hd])
        parts.append(L.shard(base, tip, color))
    # side masses over the ears and nape clumps
    for side in (1, -1):
        sm = L.extrude(np.array([[-0.16 * hd, 0.30 * hh], [0.28 * hd, 0.32 * hh], [0.30 * hd, -0.18 * hh], [-0.08 * hd, -0.05 * hh]]), 0.12, color) \
            .rotated(ry=side * 90).translated(side * (hw / 2 * 1.02), 0, 0)
        parts.append(sm)
    for i in range(4):
        bx = (i - 1.5) * 0.20 * hw
        base = np.array([[bx - 0.07 * hw, -0.20 * hh, hd / 2 * 1.0], [bx + 0.07 * hw, -0.20 * hh, hd / 2 * 1.0],
                         [bx + 0.07 * hw, -0.10 * hh, hd / 2 * 1.08], [bx - 0.07 * hw, -0.10 * hh, hd / 2 * 1.08]])
        parts.append(L.shard(base, np.array([bx + 0.02 * hw, -0.44 * hh, hd / 2 * 1.04]), color))
    if style == "tiedback":
        tail = L.tube(L.superellipse(8, 0.10 * hw, 0.08 * hd, 3), [(-0.55 * hh, 0.7, 0.7), (-0.35 * hh, 1.0, 1.0), (-0.10 * hh, 0.9, 0.9)], color) \
            .translated(0, 0, hd / 2 * 1.10)
        parts.append(tail)
    return Piece(name, "Head", L.merge(parts, color, name), "reusable", False, "hair")


# ===== worn gear =======================================================================
def hood_down(profile: P.BodyProfile, color: RGB = (64, 68, 46)) -> Piece:
    """A hood pushed down: a collapsed mass behind the neck, its edge running around the
    shoulders (reusable — the ranger / survivor collar that leaves the hair visible)."""
    uw, uh, ud = profile.size("UpperTorso")
    top = uh / 2
    prof = L.superellipse(14, 1, 1, 2.6)
    inner = L.ring_xz(L.wobble(prof, 0.04, 5, 0.3), top + 0.02, 0.62, 0.56, 0, 0.05)
    outer = L.ring_xz(L.wobble(prof, 0.05, 6, 1.2), top - 0.30, uw / 2 + 0.34, ud / 2 + 0.36, 0, 0.12)
    for i in range(len(outer)):
        z = outer[i, 2]
        outer[i, 1] -= 0.10 * max(0.0, -z / (ud / 2 + 0.36)) ** 2          # dips at the front
    collar = L.annulus(inner, outer, 0.09, color)
    # the collapsed hood mass at the back
    hood_prof = L.wobble(L.superellipse(12, 1, 1, 2.4), 0.07, 5, 0.8)
    mass = L.loft([L.ring_xz(hood_prof, top - 0.20, 0.70, 0.30, 0, ud / 2 + 0.14), L.ring_xz(hood_prof, top + 0.10, 0.82, 0.42, 0, ud / 2 + 0.22),
                   L.ring_xz(hood_prof, top + 0.42, 0.70, 0.36, 0, ud / 2 + 0.30), L.ring_xz(hood_prof, top + 0.60, 0.34, 0.20, 0, ud / 2 + 0.34)],
                  True, True, color)
    return Piece("HoodDown", "UpperTorso", L.merge([collar, mass], color, "HoodDown"), "reusable", False, "outfit")


def shoulder_plate(profile: P.BodyProfile, side: int = -1, color: RGB = (112, 110, 104), cracked: bool = True) -> Piece:
    """One armour remnant: a strapped plate over one shoulder, split by an old crack (character-specific)."""
    uw, uh, ud = profile.size("UpperTorso")
    ua = profile.size("RightUpperArm")
    cx = side * (uw / 2 + ua[0] * 0.30)
    cy = uh / 2 - 0.02
    prof = L.superellipse(10, 1, 1, 2.2)
    rings = [L.ring_xz(prof, cy - 0.30, 0.50, 0.46), L.ring_xz(prof, cy - 0.10, 0.54, 0.50), L.ring_xz(prof, cy + 0.10, 0.46, 0.44), L.ring_xz(prof, cy + 0.22, 0.24, 0.24)]
    if cracked:
        # a bite out of the rim on the outer-front edge: pull two rim points inward, and a dent above it
        for r in rings[:2]:
            for i in range(len(r)):
                if r[i, 0] * side > 0.30 and r[i, 2] < -0.05:
                    r[i, 0] *= 0.62; r[i, 2] *= 0.70
    dome = L.loft(rings, False, True, color).translated(cx, 0, 0)
    rim_in = L.ring_xz(prof, cy - 0.30, 0.50, 0.46); rim_out = L.ring_xz(prof, cy - 0.34, 0.58, 0.54)
    rim = L.annulus(rim_in, rim_out, 0.07, color).translated(cx, 0, 0)
    parts = [dome, rim]
    if cracked:
        dent = L.shard(np.array([[cx - 0.10, cy + 0.02, -0.16], [cx + 0.10, cy + 0.02, -0.16], [cx + 0.10, cy + 0.02, 0.0], [cx - 0.10, cy + 0.02, 0.0]]),
                       np.array([cx, cy - 0.06, -0.08]), color)
        parts.append(dent)
    strap = L.tube(L.superellipse(10, 0.10, 0.10, 3), [(-0.55, 1, 1), (0.55, 1, 1)], color, cap_bottom=False, cap_top=False) \
        .rotated(rz=90 + side * 24).translated(cx * 0.55, cy - 0.30, -ud / 2 * 0.9)
    parts.append(strap)
    return Piece("ShoulderPlate", "UpperTorso", L.merge(parts, color, "ShoulderPlate"), "specific", False, "outfit")


def clasp(profile: P.BodyProfile, color: RGB = (150, 122, 70), at=(0.30, 0.10), size: float = 0.22) -> Piece:
    """The Elder Tung clue: a tarnished unit clasp pinning the scarf — a small shield with a
    twin-notch chevron in relief. Nothing lunar. (character-specific)"""
    uw, uh, ud = profile.size("UpperTorso")
    s = size
    shield = np.array([[-s / 2, s * 0.45], [s / 2, s * 0.45], [s / 2, -s * 0.05], [0, -s * 0.55], [-s / 2, -s * 0.05]])
    base = L.extrude(shield, 0.06, color, z0=-ud / 2 - 0.40)
    chev = L.extrude(np.array([[-s * 0.32, s * 0.02], [0, s * 0.26], [s * 0.32, s * 0.02], [s * 0.32, -s * 0.10], [0, s * 0.14], [-s * 0.32, -s * 0.10]]), 0.06, color, z0=-ud / 2 - 0.46)
    m = L.merge([base, chev], color, "Clasp").rotated(rz=-10).translated(at[0], uh / 2 - 0.20 + at[1], 0)
    return Piece("Clasp", "UpperTorso", m, "specific", False, "accessory")


def sleeve_patch(profile: P.BodyProfile, side: str, color: RGB = (188, 164, 120)) -> Piece:
    w, h, d = profile.size(f"{side}UpperArm")
    sx = 1 if side == "Right" else -1
    m = L.extrude(np.array([[-0.20, -0.22], [0.22, -0.20], [0.20, 0.20], [-0.22, 0.22]]), 0.06, color).rotated(ry=sx * 90, rz=sx * 8) \
        .translated(sx * (w / 2 * 1.5 + 0.0), -0.05, -0.05)
    return Piece(f"{side}Patch", f"{side}UpperArm", m, "reusable", False, "outfit")


def gloves(profile: P.BodyProfile, color: RGB = (92, 66, 44)) -> list[Piece]:
    out = []
    for side, s in (("Right", 1), ("Left", -1)):
        w, h, d = profile.size(f"{side}Hand")
        hand = P.hand_mesh((w, h, d), s, color, f"{side}Hand", True)
        cuff = L.tube(L.superellipse(8, w / 2 * 1.10, d / 2 * 1.10, 3.5), [(h / 2 - 0.16, 1, 1), (h / 2 + 0.06, 1.06, 1.06)], color, cap_bottom=False, cap_top=False)
        out.append(Piece(f"{side}Hand", f"{side}Hand", L.merge([hand, cuff], color, f"{side}Hand"), "reusable", True, "outfit"))
    return out


def boots(profile: P.BodyProfile, side: str, color: RGB = (66, 46, 30), oversize: float = 1.15, straps: int = 2) -> list[Piece]:
    """Reinforced boots: shaft with a folded cuff and strap bands (geometry only), oversized foot with a heel."""
    w, h, d = profile.size(f"{side}LowerLeg")
    prof = L.superellipse(10, w / 2, d / 2, 4.0)
    o = oversize
    levels = [(-h / 2, 1.18 * o, 1.18 * o), (-h / 2 + 0.22, 1.24 * o, 1.22 * o), (h / 2 - 0.34, 1.30 * o, 1.26 * o),
              (h / 2 - 0.30, 1.30 * o * 1.14, 1.26 * o * 1.14), (h / 2 - 0.06, 1.34 * o * 1.14, 1.30 * o * 1.14), (h / 2, 1.10 * o, 1.08 * o)]
    shaft = L.tube(prof, levels, color, f"{side}LowerLeg")
    parts = [shaft]
    for k in range(straps):
        y = -h / 2 + 0.12 + k * 0.22
        parts.append(L.tube(prof, [(y, 1.26 * o, 1.24 * o), (y + 0.08, 1.27 * o, 1.25 * o)], color, cap_bottom=False, cap_top=False))
    fw, fh, fd = profile.size(f"{side}Foot")
    foot = P.foot_mesh((fw * 1.18 * o, fh * 1.10, fd * 1.10), color, f"{side}Foot", toe_drop=0.30)
    heel = L.rounded_box((fw * 1.0 * o, fh * 0.45, fd * 0.32), n=6, p=5, r_bottom=0.03, r_top=0.03, color=color).translated(0, -fh * 0.55 + fh * 0.225, fd * 0.36)   # heel bottom on the sole plane
    toe = L.tube(L.superellipse(8, fw / 2 * 1.16 * o, fh / 2 * 0.9, 3.2), [(0, 1, 1), (0.10, 1, 1)], color, cap_bottom=False, cap_top=False) \
        .rotated(rx=90).translated(0, -fh * 0.02, -fd * 0.22)
    return [Piece(f"{side}LowerLeg", f"{side}LowerLeg", L.merge(parts, color, f"{side}LowerLeg"), "reusable", True, "outfit"),
            Piece(f"{side}Foot", f"{side}Foot", L.merge([foot, heel, toe], color, f"{side}Foot"), "reusable", True, "outfit")]


def coat_skirts(profile: P.BodyProfile, color: RGB, length: float = 1.2, frayed: bool = True) -> Piece:
    """Coat tails with a worn, uneven hem (back flap + two split front flaps)."""
    lw, lh, ld = profile.size("LowerTorso")
    top = lh / 2 - 0.02

    def flap(w0, w1, ln, n=5):
        xs = np.linspace(-w1, w1, n)
        hem = [(x, -ln + (0.06 * ((i * 7) % 3) if frayed else 0.0)) for i, x in enumerate(xs)]
        return np.array([(-w0, 0.0), (w0, 0.0)] + hem[::-1], dtype=float)

    back = L.extrude(flap(0.46 * lw, 0.58 * lw, length), 0.10, color).rotated(rx=6).translated(0, top, ld / 2 + 0.06)
    parts = [back]
    for side in (1, -1):
        f = L.extrude(flap(0.24 * lw, 0.30 * lw, length * 0.80, 4), 0.10, color).rotated(ry=side * 22, rx=-5).translated(side * 0.30 * lw, top, -ld / 2 - 0.10)
        parts.append(f)
    return Piece("CoatSkirts", "LowerTorso", L.merge(parts, color, "CoatSkirts"), "reusable", False, "outfit")


def scarf(profile: P.BodyProfile, color: RGB, tail_side: int = -1, loose: bool = True) -> Piece:
    """A faded scarf worn loose: a thick wrap that sits low on the collar, tail on one side."""
    from npc_kit.v2.kit import scarf as v2_scarf
    p = v2_scarf(profile, color, tail_side)
    return Piece("Scarf", "UpperTorso", p.mesh.scaled(1.0, 0.92, 1.0).translated(0, -0.08, 0), "reusable", False, "accessory")


def belt_bell(profile: P.BodyProfile, color: RGB = (150, 122, 70), side: int = 1) -> Piece:
    """The small Chim bell, now hung at the belt beside the collar (silent, D-4)."""
    lw, lh, ld = profile.size("LowerTorso")
    prof = L.superellipse(8, 1, 1, 2)
    bell = L.loft([L.ring_xz(prof, 0.0, 0.15, 0.15), L.ring_xz(prof, 0.07, 0.14, 0.14), L.ring_xz(prof, 0.19, 0.09, 0.09), L.ring_xz(prof, 0.25, 0.045, 0.045)], True, True, color)
    clapper = L.rounded_box((0.06, 0.09, 0.06), n=4, p=8, color=color).translated(0, -0.03, 0)
    strap = L.tube(L.superellipse(4, 0.02, 0.02, 8), [(0.24, 1, 1), (0.40, 1, 1)], color)
    m = L.merge([bell, clapper, strap], color, "Bell").translated(side * (lw / 2 + 0.24), -0.22, -ld / 2 * 0.25)
    return Piece("Bell", "LowerTorso", m, "reusable", False, "prop")


def rock(hand: P.Bone, color: RGB = (150, 148, 140)) -> Piece:
    """A skipping stone in the palm (Tier 1 low-cost prop, world-placed)."""
    m = L.rounded_box((0.42, 0.14, 0.34), n=8, p=2.2, r_bottom=0.04, r_top=0.04, color=color)
    return Piece("Rock", hand.name, m.transformed(hand.M, hand.point((0, -0.34, -0.18))), "reusable", False, "prop", True)


def moustache(profile: P.BodyProfile, color: RGB) -> Piece:
    hw, hh, hd = profile.size("Head")
    zf = -hd / 2
    parts = []
    for side in (1, -1):
        m = L.extrude(L.tapered_bar(0.15 * hw, 0.05 * hh, 0.03 * hh, tilt=-side * 16), 0.08, color, z0=zf - 0.05)
        if side < 0:
            m = m.mirrored_x()
        parts.append(m.translated(side * 0.085 * hw, -0.235 * hh, 0))
    return Piece("Moustache", "Head", L.merge(parts, color, "Moustache"), "reusable", False, "hair")


# ===== props (world-placed, gripped by the right hand) ======================================
def _plant(hand_world: np.ndarray, ground_point: np.ndarray, top_extra: float = 0.0):
    axis = hand_world - ground_point
    up = axis / np.linalg.norm(axis)
    return L.align_y(up), float(np.linalg.norm(axis)), up


def spear_staff(hand_world, ground_point, wood: RGB = (70, 52, 34), steel: RGB = (150, 150, 146), wrap: RGB = (92, 66, 44),
                cloth: RGB | None = (150, 84, 96), total: float = 6.3) -> list[Piece]:
    """A shortened war spear used as a walking staff: the grip sits at the hand, the chipped
    head rides above the shoulder, a faded strip of cloth is tied under the head."""
    R, grip_h, up = _plant(np.asarray(hand_world, float), np.asarray(ground_point, float))
    prof = L.superellipse(6, 0.085, 0.085, 2)
    shaft = L.tube(prof, [(0.0, 0.85, 0.85), (0.15, 1.0, 1.0), (total - 1.05, 1.0, 1.0), (total - 0.95, 1.25, 1.25), (total - 0.85, 1.0, 1.0)], wood, "Spear")
    ferrule = L.tube(prof, [(-0.02, 1.15, 1.15), (0.20, 1.15, 1.15)], wood, cap_bottom=True, cap_top=False)
    shaft = L.merge([shaft, ferrule], wood, "Spear").transformed(R, ground_point)
    # leather grip wrap around the hand height
    wrap_m = L.tube(L.superellipse(8, 0.115, 0.115, 2.5), [(grip_h - 0.45, 1, 1), (grip_h - 0.32, 1.06, 1.06), (grip_h - 0.10, 1.0, 1.0), (grip_h + 0.28, 1.05, 1.05), (grip_h + 0.40, 1, 1)], wrap, "SpearGrip") \
        .transformed(R, ground_point)
    # head: a leaf blade, one edge chipped, on a short socket
    y0 = total - 0.85
    blade = np.array([[-0.07, 0.0], [0.07, 0.0], [0.24, 0.28], [0.21, 0.72], [0.05, 1.14], [0.0, 1.24], [-0.06, 1.12], [-0.19, 0.76], [-0.15, 0.60], [-0.23, 0.34]])
    head = L.extrude(blade, 0.08, steel, "SpearHead", z0=-0.04).translated(0, y0 + 0.16, 0)
    socket = L.tube(L.superellipse(8, 0.11, 0.11, 2.5), [(y0 - 0.02, 1.0, 1.0), (y0 + 0.18, 0.8, 0.8)], steel)
    head = L.merge([head, socket], steel, "SpearHead").transformed(R, ground_point)
    out = [Piece("Spear", "RightHand", shaft, "specific", False, "prop", True), Piece("SpearGrip", "RightHand", wrap_m, "specific", False, "prop", True),
           Piece("SpearHead", "RightHand", head, "specific", False, "prop", True)]
    if cloth:
        knot = L.rounded_box((0.22, 0.14, 0.22), n=6, p=3, color=cloth).translated(0, y0 - 0.12, 0)
        strip = L.extrude(np.array([[-0.07, 0.0], [0.08, 0.0], [0.14, -0.96], [-0.02, -0.92]]), 0.06, cloth).rotated(rz=-16, ry=30).translated(0.10, y0 - 0.14, 0.06)
        out.append(Piece("SpearCloth", "RightHand", L.merge([knot, strip], cloth, "SpearCloth").transformed(R, ground_point), "specific", False, "prop", True))
    return out


def broken_sword_staff(hand_world, ground_point, steel: RGB = (150, 150, 146), wrap: RGB = (92, 66, 44), brass: RGB = (150, 122, 70)) -> list[Piece]:
    """A snapped longsword carried point-down as a support: the grip at the hand, the
    cross-guard above the fist, the broken blade planted."""
    R, grip_h, up = _plant(np.asarray(hand_world, float), np.asarray(ground_point, float))
    blade = np.array([[-0.14, 0.0], [0.02, 0.0], [0.12, 0.35], [0.12, grip_h - 0.20], [-0.12, grip_h - 0.20], [-0.12, 0.30]])
    blade_m = L.extrude(blade, 0.05, steel, "Sword").transformed(R, ground_point)
    guard = L.rounded_box((0.70, 0.10, 0.14), n=6, p=6, r_bottom=0.02, r_top=0.02, color=brass).translated(0, grip_h - 0.18, 0).transformed(R, ground_point)
    grip = L.tube(L.superellipse(8, 0.09, 0.07, 3), [(grip_h - 0.16, 1, 1), (grip_h + 0.42, 1, 1)], wrap, "SwordGrip").transformed(R, ground_point)
    pommel = L.rounded_box((0.20, 0.16, 0.20), n=8, p=3, color=brass).translated(0, grip_h + 0.50, 0).transformed(R, ground_point)
    return [Piece("Sword", "RightHand", blade_m, "specific", False, "prop", True), Piece("SwordGuard", "RightHand", L.merge([guard, pommel], brass, "SwordGuard"), "specific", False, "prop", True),
            Piece("SwordGrip", "RightHand", grip, "specific", False, "prop", True)]


def veteran_cane(hand_world, ground_point, wood: RGB = (70, 52, 34), iron: RGB = (112, 110, 104)) -> list[Piece]:
    """A reinforced field cane: iron shoe and bands, a thick knob worn smooth, a lanyard."""
    R, grip_h, up = _plant(np.asarray(hand_world, float), np.asarray(ground_point, float))
    prof = L.superellipse(6, 0.10, 0.10, 2)
    shaft = L.tube(prof, [(0.0, 0.9, 0.9), (0.12, 1.0, 1.0), (grip_h - 0.30, 1.0, 1.0), (grip_h - 0.10, 1.3, 1.3)], wood, "Cane")
    knob = L.rounded_box((0.34, 0.26, 0.34), n=8, p=3, r_bottom=0.08, r_top=0.08, color=wood).translated(0, grip_h - 0.02, 0)
    cane = L.merge([shaft, knob], wood, "Cane").transformed(R, ground_point)
    shoe = L.tube(prof, [(-0.02, 1.2, 1.2), (0.30, 1.15, 1.15)], iron)
    bands = L.merge([L.tube(prof, [(y, 1.15, 1.15), (y + 0.10, 1.15, 1.15)], iron, cap_bottom=False, cap_top=False) for y in (0.9, 1.7, grip_h - 0.5)], iron)
    return [Piece("Cane", "RightHand", cane, "specific", False, "prop", True), Piece("CaneIron", "RightHand", L.merge([shoe, bands], iron, "CaneIron").transformed(R, ground_point), "specific", False, "prop", True)]
