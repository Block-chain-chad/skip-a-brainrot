"""kit.py — the V2 visual kit: authored low-poly pieces that hang on a BodyProfile.

Two kinds of piece:
  slot pieces  replace the visible mesh of a rig bone (the sleeve IS RightUpperArm, the boot
               shaft IS RightLowerLeg) — no hidden limb, no extra part, same Motor6D;
  welded pieces hang off a bone through a WeldConstraint (hair, hat, scarf, mantle, belt…).

Every builder works in the bone's local space (+Y up, -Z forward, +X = character's right),
takes the profile so it scales with the body, and tags ownership for the G sheet:
  skeleton  = the common body kit showing through
  reusable  = a parameterised library piece any character can wear
  specific  = authored for one character (counts against bespokeMeshes)
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from npc_kit.v2 import lowpoly as L
from npc_kit.v2 import profiles as P

RGB = tuple[int, int, int]


@dataclass
class Piece:
    name: str
    bone: str
    mesh: L.Mesh
    ownership: str = "reusable"      # skeleton | reusable | specific
    slot: bool = False               # True: this mesh IS the bone's visible part
    category: str = "outfit"         # body | face | hair | hat | outfit | prop | accessory | collider
    world: bool = False              # mesh already in world space (props placed by their grip)

    @property
    def tris(self) -> int:
        return self.mesh.tris


# ===== face =======================================================================
EXPRESSIONS = {
    #             brow angle (inner end up +), brow lift, mouth curve, mouth width, eye height, iris scale
    "neutral":   dict(brow=-3, lift=0.00, curve=0.02, width=1.0, eye=1.00, iris=1.00),
    "happy":     dict(brow=-2, lift=0.02, curve=0.09, width=1.25, eye=0.92, iris=1.00),
    "worried":   dict(brow=16, lift=0.03, curve=-0.045, width=0.95, eye=1.00, iris=0.95),
    "surprised": dict(brow=2, lift=0.10, curve=0.00, width=0.55, eye=1.12, iris=0.80, mouth_o=True),
    "angry":     dict(brow=-18, lift=-0.03, curve=-0.04, width=1.0, eye=0.82, iris=1.00),
    "sly":       dict(brow=-10, lift=0.0, curve=0.07, width=1.1, eye=0.75, iris=1.0),
}


def egg(n: int, rx: float, ry: float, k: float = 0.12) -> np.ndarray:
    """A rounded outline wider above its centre than below (friendly anime eye)."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        pts.append((rx * c * (1 + k * s), ry * s))
    return np.array(pts, dtype=float)


def face(profile: P.BodyProfile, expression: str = "neutral", iris: RGB = (48, 36, 34), brow: RGB = (70, 48, 32),
         mouth: RGB = (118, 52, 58), white: RGB = (250, 250, 248), look=(0.0, 0.0), eye_scale: float = 1.0) -> list[Piece]:
    """The V2 face: 7 parts, same names and roles as the Step 0 face system (EyeL/R, PupilL/R,
    BrowL/R, Mouth) so NpcFaceConfig keeps driving it — only the shapes change."""
    e = EXPRESSIONS[expression]
    hw, hh, hd = profile.size("Head")
    zf = -hd / 2
    ew, eh = 0.26 * hw * eye_scale, 0.30 * hh * e["eye"] * eye_scale
    ex, ey = 0.215 * hw, -0.03 * hh
    out = []
    for side, tag in ((1, "R"), (-1, "L")):
        x = side * ex
        eye_poly = egg(12, ew / 2, eh / 2)
        eye_m = L.extrude(eye_poly, 0.07, white, f"Eye{tag}", z0=zf + 0.01).translated(x, ey, 0)
        # highlight: a small square top-outer on the iris — same colour, so it lives in the Eye mesh
        hl = L.extrude(L.superellipse(4, 0.034 * hw, 0.034 * hw, 8), 0.04, white, z0=zf - 0.105)
        iw, ih = ew * 0.56 * e["iris"], eh * 0.64 * e["iris"]
        ix, iy = x - side * 0.015 * hw + look[0], ey - 0.025 * hh + look[1]
        hl = hl.translated(ix + side * iw * 0.22, iy + ih * 0.26, 0)
        out.append(Piece(f"Eye{tag}", "Head", L.merge([eye_m, hl], white, f"Eye{tag}"), "reusable", False, "face"))
        iris_m = L.extrude(egg(10, iw / 2, ih / 2, 0.08), 0.05, iris, f"Pupil{tag}", z0=zf - 0.055).translated(ix, iy, 0)
        out.append(Piece(f"Pupil{tag}", "Head", iris_m, "reusable", False, "face"))
        # brow: a tapered bar, thicker at the inner end, angled by the expression
        bl, bt = 0.27 * hw, 0.085 * hh
        poly = L.tapered_bar(bl, bt * 1.25, bt * 0.8, tilt=-side * e["brow"])
        by = ey + eh / 2 + 0.10 * hh + e["lift"] * hh
        brow_m = L.extrude(poly, 0.09, brow, f"Brow{tag}", z0=zf - 0.03)
        if side < 0:
            brow_m = brow_m.mirrored_x().translated(x, by, 0)
        else:
            brow_m = brow_m.translated(x, by, 0)
        out.append(Piece(f"Brow{tag}", "Head", brow_m, "reusable", False, "face"))
    mw = 0.19 * hw * e["width"]
    if e.get("mouth_o"):
        poly = L.superellipse(10, mw / 2, 0.065 * hh, 2.5)
    else:
        poly = L.curved_bar(mw, 0.04 * hh, e["curve"] * hh, n=5)
    mouth_m = L.extrude(poly, 0.05, mouth, "Mouth", z0=zf - 0.04).translated(0, -0.31 * hh, 0)
    out.append(Piece("Mouth", "Head", mouth_m, "reusable", False, "face"))
    return out


# ===== hair =======================================================================
def hair_ring(prof2d: np.ndarray, y_back: float, y_front: float, sx: float, sz: float, ox: float = 0.0, oz: float = 0.0) -> np.ndarray:
    """A ring whose height blends from y_back (behind) to y_front (in front, -Z)."""
    r = L.ring_xz(prof2d, 0.0, sx, sz, ox, oz)
    zn = r[:, 2] / max(1e-6, np.abs(r[:, 2]).max())     # -1 front .. +1 back
    r[:, 1] = y_front + (y_back - y_front) * (zn + 1) / 2
    return r


def hair(profile: P.BodyProfile, style: str = "tousled", color: RGB = (92, 58, 36), name: str = "Hair") -> Piece:
    """Low-poly hair masses. Styles: 'crop' (Tier 1 dome), 'tousled' (swept crown + fringe
    shards + side locks — Gianluca), 'side' (parted, swept to one side, under a cap),
    'bob' (crown + back mass to the jaw)."""
    hw, hh, hd = profile.size("Head")
    top = hh / 2
    prof = L.superellipse(12, hw / 2, hd / 2, 3.0)
    tuft = 0.0 if style == "crop" else 0.06
    sweep = {"crop": (0, 0), "tousled": (-0.10 * hw, -0.06 * hd), "side": (-0.16 * hw, -0.04 * hd), "bob": (0, 0.02 * hd)}[style]
    brow_line = 0.30 * hh                             # the fringe stays above the brows (kit rule)
    rings = [
        hair_ring(L.wobble(prof, tuft * 0.6, 5, 0.4), -0.08 * hh if style != "bob" else -0.30 * hh, brow_line + 0.02, 1.07, 1.06),
        hair_ring(L.wobble(prof, tuft, 5, 1.1), 0.22 * hh, brow_line + 0.08 * hh, 1.12, 1.10),
        hair_ring(L.wobble(prof, tuft, 4, 2.0), 0.44 * hh, 0.50 * hh, 1.06, 1.04, sweep[0] * 0.4, sweep[1] * 0.4),
        hair_ring(L.wobble(prof, tuft * 0.8, 3, 0.7), top + 0.08, top + 0.06, 0.74, 0.72, sweep[0] * 0.8, sweep[1] * 0.8),
        L.ring_xz(prof, top + 0.20, 0.28, 0.26, sweep[0], sweep[1]),
    ]
    crown = L.loft(rings, True, True, color, name)
    parts = [crown]
    if style in ("tousled", "side"):
        # fringe shards across the forehead, swept to the character's left
        n = 5 if style == "tousled" else 4
        for i in range(n):
            u = (i + 0.5) / n - 0.5                     # -0.5 .. 0.5 across the forehead
            bx = u * 0.66 * hw
            bw, bd = 0.15 * hw, 0.10 * hd
            by = brow_line + 0.14 * hh
            base = np.array([[bx - bw / 2, by, -hd / 2 * 1.05], [bx + bw / 2, by, -hd / 2 * 1.05],
                             [bx + bw / 2, by + 0.06, -hd / 2 * 1.05 + bd], [bx - bw / 2, by + 0.06, -hd / 2 * 1.05 + bd]])
            length = (0.15 + 0.05 * math.sin(i * 2.1)) * hh
            tip = np.array([bx - 0.12 * hw + (0.05 * hw if style == "side" else 0), by - length, -hd / 2 * 1.05 - 0.10 * hd])
            parts.append(L.shard(base, tip, color))
        # side locks in front of the ears
        for side in (1, -1):
            base = np.array([[side * hw / 2 * 1.02, 0.12 * hh, -0.28 * hd], [side * hw / 2 * 1.02, 0.12 * hh, -0.05 * hd],
                             [side * hw / 2 * 1.14, 0.18 * hh, -0.05 * hd], [side * hw / 2 * 1.14, 0.18 * hh, -0.28 * hd]])
            tip = np.array([side * hw / 2 * 1.10, -0.20 * hh if style == "tousled" else -0.05 * hh, -0.22 * hd])
            parts.append(L.shard(base, tip, color))
        # a few nape tufts
        for i in range(3):
            bx = (i - 1) * 0.22 * hw
            base = np.array([[bx - 0.08 * hw, -0.02 * hh, hd / 2 * 1.02], [bx + 0.08 * hw, -0.02 * hh, hd / 2 * 1.02],
                             [bx + 0.08 * hw, 0.06 * hh, hd / 2 * 1.08], [bx - 0.08 * hw, 0.06 * hh, hd / 2 * 1.08]])
            parts.append(L.shard(base, np.array([bx + 0.03 * hw, -0.22 * hh, hd / 2 * 1.06]), color))
    if style == "bob":
        for side in (1, -1):
            base = np.array([[side * hw / 2 * 1.05, -0.1 * hh, -0.25 * hd], [side * hw / 2 * 1.05, -0.1 * hh, 0.3 * hd],
                             [side * hw / 2 * 1.14, 0.0, 0.3 * hd], [side * hw / 2 * 1.14, 0.0, -0.25 * hd]])
            parts.append(L.shard(base, np.array([side * hw / 2 * 1.06, -0.48 * hh, 0.0]), color))
    return Piece(name, "Head", L.merge(parts, color, name), "reusable", False, "hair")


# ===== headwear ===================================================================
def ranger_hat(profile: P.BodyProfile, color: RGB = (108, 160, 80), band: RGB = (236, 224, 190)) -> list[Piece]:
    """Gianluca's hat (character-specific): a pinched crown pulled over the hair, a brim that
    dips at the front and is pinned up on his left, a pale band with a feather."""
    hw, hh, hd = profile.size("Head")
    top = hh / 2
    y0 = top - 0.16                                       # brim height: pulled down over the crown of the head
    prof = L.superellipse(14, hw / 2, hd / 2, 2.6)
    crown_rings = [
        L.ring_xz(prof, y0 - 0.06, 1.20, 1.18),
        L.ring_xz(prof, y0 + 0.22, 1.16, 1.14, 0.0, 0.02),
        L.ring_xz(prof, y0 + 0.44, 0.98, 0.98, 0.02, 0.04),
        L.ring_xz(prof, y0 + 0.60, 0.58, 0.86, 0.04, 0.06),       # pinched front-to-back
        L.ring_xz(prof, y0 + 0.66, 0.20, 0.62, 0.05, 0.08),
    ]
    crown = L.loft(crown_rings, True, True, color, "Hat")
    # brim: inner ring hugs the crown base, outer ring dips at the front and rises pinned on the left
    inner = L.ring_xz(prof, y0, 1.06, 1.05)                # starts inside the crown wall: no see-through ring
    outer = L.ring_xz(prof, y0, 1.62, 1.50)
    for i in range(len(outer)):
        x, _, z = outer[i]
        dip = -0.10 * max(0.0, -z / (hd / 2 * 1.5))            # front dips
        pin = 0.0
        if x < -0.25 * hw:
            t = min(1.0, (-x - 0.25 * hw) / (0.55 * hw))
            pin = 0.55 * t * t
            outer[i, 0] = x * (1 - 0.30 * t)                     # the pinned side folds in toward the crown
        outer[i, 1] = y0 + dip + pin + 0.02 * max(0.0, z / (hd / 2 * 1.5))
    brim = L.annulus(inner, outer, 0.06, color, "HatBrim")
    hat = L.merge([crown, brim], color, "Hat")
    band_m = L.tube(prof, [(y0 + 0.04, 1.23, 1.21), (y0 + 0.20, 1.19, 1.17)], band, "HatBand", cap_bottom=False, cap_top=False)
    # feather tucked at the right-back of the band, sweeping up and back
    fb = np.array([[0.42 * hw, y0 + 0.08, 0.30 * hd], [0.50 * hw, y0 + 0.08, 0.36 * hd], [0.50 * hw, y0 + 0.16, 0.36 * hd], [0.42 * hw, y0 + 0.16, 0.30 * hd]])
    f1 = L.shard(fb, np.array([0.62 * hw, y0 + 0.62, 0.72 * hd]), band)
    f2 = L.shard(fb + np.array([0.06 * hw, 0.16, 0.12 * hd]), np.array([0.58 * hw, y0 + 0.80, 0.96 * hd]), band)
    tilt = dict(rx=7, rz=4)                                   # worn jauntily: tipped back, cocked to his right
    pivot = np.array([0, y0, 0.0])
    hat = hat.translated(*(-pivot)).rotated(**tilt).translated(*pivot)
    band_all = L.merge([band_m, f1, f2], band, "HatBand").translated(*(-pivot)).rotated(**tilt).translated(*pivot)
    return [Piece("Hat", "Head", hat, "specific", False, "hat"),
            Piece("HatBand", "Head", band_all, "specific", False, "hat")]


def flat_cap(profile: P.BodyProfile, color: RGB = (96, 72, 52)) -> Piece:
    """Reusable merchant's flat cap: a low soft dome with a short peak."""
    hw, hh, hd = profile.size("Head")
    top = hh / 2
    prof = L.superellipse(12, hw / 2, hd / 2, 3.0)
    y0 = top - 0.14
    dome = L.loft([L.ring_xz(prof, y0, 1.14, 1.12), L.ring_xz(prof, y0 + 0.18, 1.20, 1.18, 0, 0.04),
                   L.ring_xz(prof, y0 + 0.36, 0.96, 1.02, 0, 0.10), L.ring_xz(prof, y0 + 0.44, 0.40, 0.50, 0, 0.16)], True, True, color, "Cap")
    peak_poly = np.array([[-0.34 * hw, 0], [0.34 * hw, 0], [0.26 * hw, 0.36 * hd], [-0.26 * hw, 0.36 * hd]])
    peak = L.extrude(peak_poly, 0.05, color).rotated(rx=-92).translated(0, y0 + 0.02, -hd / 2 * 1.05)
    return Piece("Cap", "Head", L.merge([dome, peak], color, "Cap"), "reusable", False, "hat")


# ===== neck / shoulders ===============================================================
def scarf(profile: P.BodyProfile, color: RGB = (168, 58, 86), tail_side: int = -1) -> Piece:
    """A wrapped scarf with a knot and a two-slab tail on one side (reusable; tail side is a parameter)."""
    uw, uh, ud = profile.size("UpperTorso")
    top = uh / 2
    prof = L.wobble(L.superellipse(12, uw / 2, ud / 2, 3.2), 0.06, 5, 0.3)
    hw = profile.size("Head")[0]
    k = (hw / 2 * 1.06) / (uw / 2)                          # the wrap is a little wider than the jaw so it reads under the chin
    loop = L.loft([L.ring_xz(prof, top - 0.16, k * 0.86, 0.96), L.ring_xz(prof, top + 0.06, k, 1.06, 0, -0.05),
                   L.ring_xz(prof, top + 0.30, k * 0.90, 0.92, 0, -0.07), L.ring_xz(prof, top + 0.46, k * 0.66, 0.66, 0, -0.06)],
                  True, True, color, "Scarf")
    knot = L.rounded_box((0.46, 0.36, 0.34), n=8, p=3, r_bottom=0.10, r_top=0.10, color=color).rotated(rz=tail_side * 18) \
        .translated(tail_side * 0.36, top - 0.02, -ud / 2 - 0.36)
    t1 = L.extrude(np.array([[-0.22, 0.0], [0.22, 0.0], [0.26, -0.62], [-0.18, -0.62]]), 0.13, color) \
        .rotated(rz=-tail_side * 10).translated(tail_side * 0.56, top - 0.20, -ud / 2 - 0.26)
    t2 = L.extrude(np.array([[-0.22, 0.0], [0.26, 0.0], [0.36, -0.66], [-0.26, -0.66]]), 0.12, color) \
        .rotated(rz=tail_side * 8).translated(tail_side * 0.66, top - 0.78, -ud / 2 - 0.22)
    return Piece("Scarf", "UpperTorso", L.merge([loop, knot, t1, t2], color, "Scarf"), "reusable", False, "accessory")


def neckerchief(profile: P.BodyProfile, color: RGB = (190, 70, 60)) -> Piece:
    uw, uh, ud = profile.size("UpperTorso")
    top = uh / 2
    prof = L.superellipse(10, uw / 2, ud / 2, 3.2)
    band = L.tube(prof, [(top - 0.12, 0.60, 0.86), (top + 0.10, 0.50, 0.70)], color, cap_bottom=False, cap_top=False)
    tri = L.extrude(np.array([[-0.34, 0.0], [0.34, 0.0], [0.04, -0.62]]), 0.08, color).translated(0.05, top - 0.10, -ud / 2 - 0.10)
    knot = L.rounded_box((0.24, 0.20, 0.18), n=6, p=3, r_bottom=0.06, r_top=0.06, color=color).translated(0.06, top - 0.06, -ud / 2 - 0.12)
    return Piece("Neckerchief", "UpperTorso", L.merge([band, tri, knot], color, "Neckerchief"), "reusable", False, "accessory")


def mantle(profile: P.BodyProfile, color: RGB = (70, 76, 50), reach: float = 0.62, drop: float = 0.55, front_point: float = 0.12, collar: float = 0.0) -> Piece:
    """A shoulder mantle / yoke that widens the silhouette past the sleeves (reusable)."""
    uw, uh, ud = profile.size("UpperTorso")
    top = uh / 2
    prof = L.superellipse(16, 1, 1, 2.4)
    inner = L.ring_xz(prof, top + 0.02, 0.58, 0.50)
    outer = L.ring_xz(L.wobble(prof, 0.04, 7, 0.5), top - drop, uw / 2 + reach, ud / 2 + reach * 0.75)
    for i in range(len(outer)):
        z = outer[i, 2]
        outer[i, 1] -= front_point * max(0.0, -z / (ud / 2 + reach * 0.75)) ** 2
    m = L.annulus(inner, outer, 0.07, color, "Mantle")
    if collar > 0:
        # a stand-up collar behind the neck: the back half of the inner ring, extruded upward
        ring_lo = L.ring_xz(prof, top + 0.02, 0.60, 0.54)
        ring_hi = L.ring_xz(prof, top + 0.02, 0.66, 0.60)
        for r in (ring_lo, ring_hi):
            for i in range(len(r)):
                r[i, 1] += collar * max(0.0, r[i, 2] / max(1e-6, abs(r[:, 2]).max())) ** 0.7
        m = L.merge([m, L.annulus(ring_lo, ring_hi, 0.06, color)], color, "Mantle")
    return Piece("Mantle", "UpperTorso", m, "reusable", False, "outfit")


# ===== torso shells ===================================================================
def coat_body(profile: P.BodyProfile, color: RGB = (110, 96, 62), chest: float = 1.08, shoulder: float = 1.16) -> Piece:
    """UpperTorso slot: a coat that is wider at the shoulders than the underlying torso."""
    uw, uh, ud = profile.size("UpperTorso")
    prof = L.superellipse(12, uw / 2, ud / 2, 4.2)
    m = L.tube(prof, [(-uh / 2, 1.07, 1.05), (-uh / 2 + 0.22, 1.00, 1.00), (0.12, chest, 1.06, 0, -0.03),
                      (uh / 2 - 0.18, shoulder, 1.08, 0, -0.01), (uh / 2, 1.02, 0.98)], color, "UpperTorso")
    return Piece("UpperTorso", "UpperTorso", m, "reusable", True, "outfit")


def tunic_front(profile: P.BodyProfile, color: RGB = (196, 168, 120)) -> Piece:
    """The inner tunic showing in the coat's open front (welded to UpperTorso)."""
    uw, uh, ud = profile.size("UpperTorso")
    poly = np.array([[-0.16 * uw, -uh / 2 + 0.06], [0.16 * uw, -uh / 2 + 0.06], [0.30 * uw, uh / 2 - 0.34], [0.0, uh / 2 - 0.02], [-0.30 * uw, uh / 2 - 0.34]])
    m = L.extrude(poly, 0.10, color, "TunicFront", z0=-ud / 2 * 1.08 - 0.06)
    return Piece("TunicFront", "UpperTorso", m, "reusable", False, "outfit")


def shirt(profile: P.BodyProfile, color: RGB = (214, 196, 160)) -> Piece:
    uw, uh, ud = profile.size("UpperTorso")
    prof = L.superellipse(12, uw / 2, ud / 2, 4.2)
    m = L.tube(prof, [(-uh / 2, 1.02, 1.0), (-uh / 2 + 0.2, 1.04, 1.02), (0.1, 1.08, 1.08, 0, -0.02), (uh / 2 - 0.16, 1.10, 1.06), (uh / 2, 1.0, 0.96)], color, "UpperTorso")
    return Piece("UpperTorso", "UpperTorso", m, "reusable", True, "outfit")


def hips(profile: P.BodyProfile, color: RGB, flare: float = 1.0, name: str = "LowerTorso") -> Piece:
    """LowerTorso slot: trousers / tunic hem block (the common kit block recoloured, optional flare)."""
    lw, lh, ld = profile.size("LowerTorso")
    prof = L.superellipse(10, lw / 2, ld / 2, 4.5)
    m = L.tube(prof, [(-lh / 2, 1.0 * flare, 1.0 * flare), (-lh / 2 + 0.1, 1.0 * flare, 1.0 * flare), (lh / 2 - 0.08, 1.0, 1.0), (lh / 2, 0.96, 0.96)], color, name)
    return Piece("LowerTorso", "LowerTorso", m, "skeleton" if flare == 1.0 else "reusable", True, "outfit")


def coat_skirts(profile: P.BodyProfile, color: RGB = (110, 96, 62), length: float = 1.15, split: bool = True) -> Piece:
    """Coat tails welded to the LowerTorso: a wide back flap and two shorter front flaps."""
    lw, lh, ld = profile.size("LowerTorso")
    top = lh / 2 - 0.02
    back = L.extrude(np.array([[-0.46 * lw, 0], [0.46 * lw, 0], [0.56 * lw, -length], [-0.56 * lw, -length]]), 0.10, color) \
        .rotated(rx=6).translated(0, top, ld / 2 + 0.06)
    parts = [back]
    if split:
        for side in (1, -1):
            f = L.extrude(np.array([[-0.24 * lw, 0], [0.24 * lw, 0], [0.30 * lw, -length * 0.78], [-0.20 * lw, -length * 0.78]]), 0.10, color) \
                .rotated(ry=side * 22, rx=-5).translated(side * 0.30 * lw, top, -ld / 2 - 0.10)
            parts.append(f)
    else:
        f = L.extrude(np.array([[-0.5 * lw, 0], [0.5 * lw, 0], [0.58 * lw, -length], [-0.58 * lw, -length]]), 0.10, color) \
            .rotated(rx=-6).translated(0, top, -ld / 2 - 0.08)
        parts.append(f)
    return Piece("CoatSkirts", "LowerTorso", L.merge(parts, color, "CoatSkirts"), "reusable", False, "outfit")


def apron(profile: P.BodyProfile, color: RGB = (236, 228, 208)) -> list[Piece]:
    uw, uh, ud = profile.size("UpperTorso")
    lw, lh, ld = profile.size("LowerTorso")
    bib = L.extrude(np.array([[-0.24 * uw, -uh / 2], [0.24 * uw, -uh / 2], [0.20 * uw, uh / 2 - 0.30], [-0.20 * uw, uh / 2 - 0.30]]), 0.08, color, z0=-ud / 2 * 1.10 - 0.05)
    strap_prof = L.superellipse(10, uw / 2, ud / 2, 3.2)
    strap = L.tube(strap_prof, [(uh / 2 - 0.30, 0.50, 0.74), (uh / 2 - 0.20, 0.48, 0.70)], color, cap_bottom=False, cap_top=False)
    skirt = L.extrude(np.array([[-0.50 * lw, 0], [0.50 * lw, 0], [0.62 * lw, -1.35], [-0.62 * lw, -1.35]]), 0.10, color) \
        .rotated(rx=-7).translated(0, lh / 2, -ld / 2 - 0.10)
    return [Piece("ApronBib", "UpperTorso", L.merge([bib, strap], color, "ApronBib"), "reusable", False, "outfit"),
            Piece("ApronSkirt", "LowerTorso", skirt, "reusable", False, "outfit")]


# ===== arms ==========================================================================
def sleeve(profile: P.BodyProfile, side: str, color: RGB, puff: float = 1.5, rolled: bool = False) -> Piece:
    """UpperArm slot: a sleeve wider than the arm, tapering toward the elbow; `rolled` ends
    in a thick cuff two-thirds down (asymmetry without an extra part)."""
    w, h, d = profile.size(f"{side}UpperArm")
    prof = L.superellipse(10, w / 2, d / 2, 3.5)
    if rolled:
        levels = [(-h / 2, 0.92, 0.92), (-h / 2 + 0.05, 1.08, 1.08), (-h / 2 + 0.30, puff * 1.05, puff * 1.05), (-h / 2 + 0.36, puff * 0.95, puff * 0.95),
                  (0.10, puff, puff), (h / 2 - 0.10, puff * 1.02, puff), (h / 2, puff * 0.90, puff * 0.88)]
    else:
        levels = [(-h / 2, puff * 0.82, puff * 0.82), (-h / 2 + 0.18, puff * 0.86, puff * 0.86), (0.10, puff, puff),
                  (h / 2 - 0.10, puff * 1.02, puff), (h / 2, puff * 0.90, puff * 0.88)]
    m = L.tube(prof, levels, color, f"{side}UpperArm")
    return Piece(f"{side}UpperArm", f"{side}UpperArm", m, "reusable", True, "outfit")


def bracer(profile: P.BodyProfile, side: str, color: RGB = (110, 76, 46), flare: float = 1.30) -> Piece:
    """LowerArm slot: leather bracer, wide at the elbow, strapped at the wrist."""
    w, h, d = profile.size(f"{side}LowerArm")
    prof = L.superellipse(10, w / 2, d / 2, 4.0)
    levels = [(-h / 2, 1.06, 1.06), (-h / 2 + 0.10, 1.16, 1.16), (-h / 2 + 0.16, 1.08, 1.08), (0.05, flare * 0.92, flare * 0.92),
              (h / 2 - 0.12, flare, flare), (h / 2, flare * 0.94, flare * 0.94)]
    m = L.tube(prof, levels, color, f"{side}LowerArm")
    return Piece(f"{side}LowerArm", f"{side}LowerArm", m, "reusable", True, "outfit")


def forearm(profile: P.BodyProfile, side: str, skin: RGB, cuff: RGB | None = None) -> list[Piece]:
    """LowerArm slot from the body kit (skin), optionally with a welded cuff / bracelet."""
    kit = P.body_kit(profile, skin=skin)
    out = [Piece(f"{side}LowerArm", f"{side}LowerArm", kit[f"{side}LowerArm"], "skeleton", True, "body")]
    if cuff:
        w, h, d = profile.size(f"{side}LowerArm")
        prof = L.superellipse(10, w / 2, d / 2, 3.5)
        m = L.tube(prof, [(-h / 2 + 0.02, 1.10, 1.10), (-h / 2 + 0.18, 1.14, 1.14)], cuff, f"{side}Cuff", cap_bottom=False, cap_top=False)
        out.append(Piece(f"{side}Cuff", f"{side}LowerArm", m, "reusable", False, "accessory"))
    return out


def hands(profile: P.BodyProfile, skin: RGB, thumb: bool = True) -> list[Piece]:
    out = []
    for side, s in (("Right", 1), ("Left", -1)):
        out.append(Piece(f"{side}Hand", f"{side}Hand", P.hand_mesh(profile.size(f"{side}Hand"), s, skin, f"{side}Hand", thumb), "skeleton", True, "body"))
    return out


# ===== legs ==========================================================================
def leg_block(profile: P.BodyProfile, side: str, color: RGB) -> Piece:
    kit = P.body_kit(profile, trousers=color)
    return Piece(f"{side}UpperLeg", f"{side}UpperLeg", kit[f"{side}UpperLeg"], "skeleton", True, "body")


def boots(profile: P.BodyProfile, side: str, color: RGB = (74, 50, 30), cuff: float = 1.0, oversize: float = 1.15) -> list[Piece]:
    """LowerLeg slot = boot shaft with a folded cuff; Foot slot = oversized boot with a heel."""
    w, h, d = profile.size(f"{side}LowerLeg")
    prof = L.superellipse(10, w / 2, d / 2, 4.0)
    o = oversize
    levels = [(-h / 2, 1.18 * o, 1.18 * o), (-h / 2 + 0.22, 1.24 * o, 1.22 * o), (h / 2 - 0.34, 1.30 * o, 1.26 * o),
              (h / 2 - 0.30, 1.30 * o * (1 + 0.16 * cuff), 1.26 * o * (1 + 0.16 * cuff)), (h / 2 - 0.06, 1.34 * o * (1 + 0.16 * cuff), 1.30 * o * (1 + 0.16 * cuff)),
              (h / 2, 1.10 * o, 1.08 * o)]
    shaft = L.tube(prof, levels, color, f"{side}LowerLeg")
    fw, fh, fd = profile.size(f"{side}Foot")
    foot = P.foot_mesh((fw * 1.18 * o, fh * 1.10, fd * 1.10), color, f"{side}Foot", toe_drop=0.30)
    heel = L.rounded_box((fw * 1.0 * o, fh * 0.45, fd * 0.32), n=6, p=5, r_bottom=0.03, r_top=0.03, color=color).translated(0, -fh * 0.55 + fh * 0.225, fd * 0.36)   # heel bottom on the sole plane
    return [Piece(f"{side}LowerLeg", f"{side}LowerLeg", shaft, "reusable", True, "outfit"),
            Piece(f"{side}Foot", f"{side}Foot", L.merge([foot, heel], color, f"{side}Foot"), "reusable", True, "outfit")]


def shoes(profile: P.BodyProfile, side: str, color: RGB = (88, 66, 48)) -> Piece:
    fw, fh, fd = profile.size(f"{side}Foot")
    return Piece(f"{side}Foot", f"{side}Foot", P.foot_mesh((fw, fh, fd), color, f"{side}Foot"), "skeleton", True, "body")


def shin(profile: P.BodyProfile, side: str, color: RGB) -> Piece:
    kit = P.body_kit(profile, trousers=color)
    return Piece(f"{side}LowerLeg", f"{side}LowerLeg", kit[f"{side}LowerLeg"], "skeleton", True, "body")


# ===== belts, bags, small things ===========================================================
def belt(profile: P.BodyProfile, color: RGB = (60, 44, 30), buckle: RGB | None = (196, 150, 72), thick: float = 0.16, over: float = 0.08) -> list[Piece]:
    lw, lh, ld = profile.size("LowerTorso")
    prof = L.superellipse(12, lw / 2 + over, ld / 2 + over, 4.5)
    m = L.tube(prof, [(lh / 2 - thick - 0.04, 1.0, 1.0), (lh / 2 - 0.04, 1.0, 1.0)], color, "Belt", cap_bottom=False, cap_top=False)
    out = [Piece("Belt", "LowerTorso", m, "reusable", False, "accessory")]
    if buckle:
        b = L.rounded_box((0.30, thick + 0.06, 0.10), n=6, p=6, r_bottom=0.02, r_top=0.02, color=buckle).translated(0, lh / 2 - thick / 2 - 0.04, -ld / 2 - over - 0.04)
        out.append(Piece("Buckle", "LowerTorso", b, "reusable", False, "accessory"))
    return out


def pouch(profile: P.BodyProfile, side: int = -1, color: RGB = (140, 104, 66), size=(0.52, 0.44, 0.30)) -> Piece:
    lw, lh, ld = profile.size("LowerTorso")
    body = L.rounded_box(size, n=8, p=3.5, r_bottom=0.10, r_top=0.06, color=color)
    flap = L.extrude(np.array([[-size[0] / 2 - 0.02, 0], [size[0] / 2 + 0.02, 0], [size[0] / 2, -0.20], [-size[0] / 2, -0.20]]), size[2] * 0.4 + 0.08, color) \
        .translated(0, size[1] / 2, -size[2] * 0.3)
    m = L.merge([body, flap], color, "Pouch").rotated(ry=side * -28).translated(side * (lw / 2 + 0.10), -0.08, -ld / 2 * 0.55)
    return Piece("Pouch", "LowerTorso", m, "reusable", False, "accessory")


def satchel(profile: P.BodyProfile, side: int = 1, color: RGB = (132, 96, 60)) -> list[Piece]:
    """A bag on one hip with a strap over the opposite shoulder (asymmetric, reusable)."""
    uw, uh, ud = profile.size("UpperTorso")
    lw, lh, ld = profile.size("LowerTorso")
    prof = L.superellipse(14, uw / 2 * 1.12 + 0.02, ud / 2 * 1.16 + 0.02, 4.0)
    strap = L.tube(prof, [(-0.10, 1.0, 1.0), (0.10, 1.0, 1.0)], color, "Strap", cap_bottom=False, cap_top=False).rotated(rz=side * -38).translated(0, 0.05, 0)
    bag = L.rounded_box((0.62, 0.56, 0.34), n=8, p=3.5, r_bottom=0.10, r_top=0.06, color=color)
    flap = L.extrude(np.array([[-0.33, 0], [0.33, 0], [0.30, -0.26], [-0.30, -0.26]]), 0.20, color).translated(0, 0.28, -0.12)
    bag = L.merge([bag, flap], color, "Satchel").rotated(ry=side * 14).translated(side * (lw / 2 + 0.16), -0.02, 0.05)
    return [Piece("SatchelStrap", "UpperTorso", strap, "reusable", False, "accessory"),
            Piece("Satchel", "LowerTorso", bag, "reusable", False, "accessory")]


def chim_collar(profile: P.BodyProfile, color: RGB = (74, 50, 30)) -> Piece:
    """Gianluca's empty Chim collar hanging off his belt (character-specific)."""
    lw, lh, ld = profile.size("LowerTorso")
    prof = L.superellipse(12, 1, 1, 2)
    inner = L.ring_xz(prof, 0, 0.21, 0.21)
    outer = L.ring_xz(prof, 0, 0.31, 0.31)
    ring = L.annulus(inner, outer, 0.06, color).rotated(rz=90)          # stands up vertically, plane facing +X
    tag = L.rounded_box((0.05, 0.14, 0.12), n=6, p=6, r_bottom=0.02, r_top=0.02, color=color).translated(0, -0.38, 0)
    m = L.merge([ring, tag], color, "ChimCollar").rotated(ry=18).translated(lw / 2 + 0.10, -0.30, -ld / 2 * 0.3)
    return Piece("ChimCollar", "LowerTorso", m, "specific", False, "accessory")


def rope_belt(profile: P.BodyProfile, color: RGB = (120, 90, 60)) -> Piece:
    lw, lh, ld = profile.size("LowerTorso")
    prof = L.wobble(L.superellipse(12, lw / 2 + 0.05, ld / 2 + 0.05, 4.5), 0.03, 6)
    m = L.tube(prof, [(lh / 2 - 0.30, 1.0, 1.0), (lh / 2 - 0.19, 1.0, 1.0)], color, "Belt", cap_bottom=False, cap_top=False)
    return Piece("Belt", "LowerTorso", m, "reusable", False, "accessory")


# ===== props =============================================================================
def cane_with_bell(hand_world: np.ndarray, ground_point: np.ndarray, wood: RGB = (74, 50, 30), brass: RGB = (196, 150, 72)) -> list[Piece]:
    """Built in WORLD space (props are placed by the grip): a planted cane from the ground
    point up to the hand, knob in the fist, bell hanging from the knob."""
    axis = hand_world - ground_point
    length = float(np.linalg.norm(axis))
    R = L.align_y(axis)
    prof = L.superellipse(6, 0.095, 0.095, 2)
    shaft = L.tube(prof, [(0.0, 0.85, 0.85), (0.10, 1.0, 1.0), (length - 0.30, 1.0, 1.0), (length - 0.12, 1.2, 1.2)], wood, "Cane")
    knob = L.rounded_box((0.30, 0.26, 0.30), n=8, p=3, r_bottom=0.08, r_top=0.08, color=wood).translated(0, length - 0.02, 0)
    cane = L.merge([shaft, knob], wood, "Cane").transformed(R, ground_point)
    bell_prof = L.superellipse(8, 1, 1, 2)
    bell = L.loft([L.ring_xz(bell_prof, 0.0, 0.21, 0.21), L.ring_xz(bell_prof, 0.10, 0.19, 0.19), L.ring_xz(bell_prof, 0.26, 0.12, 0.12),
                   L.ring_xz(bell_prof, 0.34, 0.06, 0.06)], True, True, brass, "Bell")
    clapper = L.rounded_box((0.08, 0.12, 0.08), n=4, p=8, color=brass).translated(0, -0.05, 0)
    strap = L.tube(L.superellipse(4, 0.025, 0.025, 8), [(0.32, 1, 1), (0.52, 1, 1)], brass)
    bell = L.merge([bell, clapper, strap], brass, "Bell").translated(0, length - 0.56, 0).transformed(R, ground_point + R @ np.array([0.20, 0, -0.14]))
    return [Piece("Cane", "RightHand", cane, "reusable", False, "prop", True), Piece("Bell", "RightHand", bell, "reusable", False, "prop", True)]


def coin_sack(color: RGB = (170, 140, 96), tie: RGB = (90, 60, 40)) -> L.Mesh:
    prof = L.wobble(L.superellipse(10, 1, 1, 2.2), 0.05, 4)
    body = L.loft([L.ring_xz(prof, 0.0, 0.18, 0.18), L.ring_xz(prof, 0.10, 0.30, 0.30), L.ring_xz(prof, 0.34, 0.30, 0.30),
                   L.ring_xz(prof, 0.50, 0.16, 0.16), L.ring_xz(prof, 0.58, 0.20, 0.20), L.ring_xz(prof, 0.68, 0.12, 0.12)], True, True, color, "Sack")
    return body


# ===== assembling ==========================================================================
def slot_defaults(profile: P.BodyProfile, skin: RGB, trousers: RGB, shirt: RGB | None = None) -> dict[str, Piece]:
    """Every bone gets the body-kit mesh unless a shell replaces it."""
    kit = P.body_kit(profile, skin=skin, trousers=trousers, shirt=shirt)
    return {name: Piece(name, name, m, "skeleton", True, "body") for name, m in kit.items()}


@dataclass
class Character:
    id: str
    label: str
    tier: int
    profile: P.BodyProfile
    pieces: list[Piece]
    rest: dict
    palette: dict

    def slots(self) -> dict[str, Piece]:
        return {p.bone: p for p in self.pieces if p.slot}

    def world_meshes(self, bones: dict[str, P.Bone] | None = None, include=None) -> list[L.Mesh]:
        bones = bones or P.pose(self.profile, self.rest)
        out = []
        for p in self.pieces:
            if include is not None and not include(p):
                continue
            if p.world:
                out.append(p.mesh)
            else:
                out.append(bones[p.bone].to_world(p.mesh))
        return out

    def budget(self) -> dict:
        tris = sum(p.tris for p in self.pieces)
        parts = len(self.pieces) + 1 + 1           # + HumanoidRootPart + collider (Tier 2/3)
        if self.tier == 1:
            parts -= 1
        welds = sum(1 for p in self.pieces if not p.slot and p.category != "face") + (1 if self.tier >= 2 else 0)
        motor6d = 15 + sum(1 for p in self.pieces if p.category == "face")
        bespoke = sum(1 for p in self.pieces if p.ownership == "specific")
        reusable = sum(1 for p in self.pieces if p.ownership == "reusable")
        skeleton = sum(1 for p in self.pieces if p.ownership == "skeleton")
        return {"id": self.id, "tier": self.tier, "baseParts": parts, "welds": welds, "motor6d": motor6d, "bespokeMeshes": bespoke,
                "reusableMeshes": reusable, "skeletonMeshes": skeleton, "triangles": tris,
                "trianglesByOwnership": {k: sum(p.tris for p in self.pieces if p.ownership == k) for k in ("skeleton", "reusable", "specific")}}
