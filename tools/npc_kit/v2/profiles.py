"""profiles.py — V2 BodyProfiles (the underlying SR-Rig skeleton with study proportions),
forward kinematics for rest poses, and the Tier 1 body kit that is allowed to show.

A BodyProfile is the same 15-part / 15-joint SR-Rig skeleton (R15 names, Motor6D pivots,
HRP anchored at y = 3.0 so the MerchantDialog portrait line keeps working); only the
numbers differ. Nothing here changes NpcRigSpec.lua — the candidates are study data
until one is approved, then it becomes a `BodyTypes` entry.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from npc_kit.v2 import lowpoly as L

RGB = tuple[int, int, int]
HRP_Y = 3.0
HRP_SIZE = (2.0, 2.0, 1.0)

# joint -> (part0, part1, kind, side)
JOINTS = [
    ("Root", "HumanoidRootPart", "LowerTorso", "root", 0),
    ("Waist", "LowerTorso", "UpperTorso", "spine", 0),
    ("Neck", "UpperTorso", "Head", "spine", 0),
    ("RightShoulder", "UpperTorso", "RightUpperArm", "limb", 1),
    ("RightElbow", "RightUpperArm", "RightLowerArm", "limb", 1),
    ("RightWrist", "RightLowerArm", "RightHand", "limb", 1),
    ("LeftShoulder", "UpperTorso", "LeftUpperArm", "limb", -1),
    ("LeftElbow", "LeftUpperArm", "LeftLowerArm", "limb", -1),
    ("LeftWrist", "LeftLowerArm", "LeftHand", "limb", -1),
    ("RightHip", "LowerTorso", "RightUpperLeg", "limb", 1),
    ("RightKnee", "RightUpperLeg", "RightLowerLeg", "limb", 1),
    ("RightAnkle", "RightLowerLeg", "RightFoot", "limb", 1),
    ("LeftHip", "LowerTorso", "LeftUpperLeg", "limb", -1),
    ("LeftKnee", "LeftUpperLeg", "LeftLowerLeg", "limb", -1),
    ("LeftAnkle", "LeftLowerLeg", "LeftFoot", "limb", -1),
]


@dataclass
class BodyProfile:
    id: str
    label: str
    parts: dict[str, tuple[tuple[float, float, float], tuple[float, float, float]]]   # name -> (size, world centre)
    pivots: dict[str, tuple[float, float, float]]                                        # joint -> world pivot
    notes: str = ""
    dims: dict = field(default_factory=dict)

    # ----- measurements ---------------------------------------------------------
    def size(self, part: str) -> np.ndarray:
        return np.array(self.parts[part][0], dtype=float)

    def centre(self, part: str) -> np.ndarray:
        return np.array(self.parts[part][1], dtype=float)

    @property
    def height(self) -> float:
        s, c = self.parts["Head"]
        return c[1] + s[1] / 2

    @property
    def heads(self) -> float:
        return self.height / self.parts["Head"][0][1]

    @property
    def head_offset(self) -> float:
        """Head centre above the HRP centre — the portrait-line number (v1: 1.45)."""
        return self.parts["Head"][1][1] - HRP_Y

    @property
    def shoulder_span(self) -> float:
        s, c = self.parts["RightUpperArm"]
        return 2 * (c[0] + s[0] / 2)

    def summary(self) -> dict:
        return {"id": self.id, "label": self.label, "height": round(self.height, 3), "heads": round(self.heads, 2),
                "headOffset": round(self.head_offset, 3), "shoulderSpan": round(self.shoulder_span, 3),
                "head": self.parts["Head"][0], "upperTorso": self.parts["UpperTorso"][0],
                "lowerArm": self.parts["RightLowerArm"][0], "hand": self.parts["RightHand"][0],
                "lowerLeg": self.parts["RightLowerLeg"][0], "foot": self.parts["RightFoot"][0], "notes": self.notes}


def make_profile(pid: str, label: str, *, head=(1.72, 1.72, 1.58), ut=(2.10, 1.35, 1.10), lt=(1.85, 0.70, 1.00),
                 ua=(0.80, 0.95, 0.80), la=(0.82, 0.85, 0.82), hand=(0.90, 0.62, 0.88),
                 ul=(0.85, 1.00, 0.85), ll=(0.78, 0.85, 0.78), foot=(0.85, 0.50, 1.20),
                 leg_x=0.52, arm_gap=0.05, shoulder_drop=0.16, foot_forward=0.12, neck_gap=0.16, notes="") -> BodyProfile:
    """Build the skeleton bottom-up from the feet (y = 0) so leg lengths set the hip height,
    the torso stacks on the hips and the head on the neck; the HRP stays at y = 3.0."""
    parts, piv = {}, {}
    # legs
    ankle = foot[1] * 0.75
    ll_bottom = ankle - 0.10
    knee = ll_bottom + ll[1] - 0.05
    ul_bottom = knee - 0.08
    hip = ul_bottom + ul[1] - 0.08
    for side, sx in (("Right", 1), ("Left", -1)):
        x = sx * leg_x
        parts[f"{side}Foot"] = (foot, (x, foot[1] / 2, -foot_forward))
        parts[f"{side}LowerLeg"] = (ll, (x, ll_bottom + ll[1] / 2, 0.0))
        parts[f"{side}UpperLeg"] = (ul, (x, ul_bottom + ul[1] / 2, 0.0))
        piv[f"{side}Ankle"] = (x, ankle, 0.0)
        piv[f"{side}Knee"] = (x, knee, 0.0)
        piv[f"{side}Hip"] = (x, hip, 0.0)
    # torso
    lt_bottom = hip - 0.10
    waist = lt_bottom + lt[1] - 0.03
    ut_bottom = waist - 0.07
    neck = ut_bottom + ut[1] - 0.06
    parts["LowerTorso"] = (lt, (0.0, lt_bottom + lt[1] / 2, 0.0))
    parts["UpperTorso"] = (ut, (0.0, ut_bottom + ut[1] / 2, 0.0))
    parts["HumanoidRootPart"] = (HRP_SIZE, (0.0, HRP_Y, 0.0))
    piv["Root"] = (0.0, HRP_Y, 0.0)
    piv["Waist"] = (0.0, waist, 0.0)
    piv["Neck"] = (0.0, neck, 0.0)
    # head
    head_bottom = neck + neck_gap                  # V2: a short visible neck (scarves, collars, the chin line); v1 sat the head in the torso
    parts["Head"] = (head, (0.0, head_bottom + head[1] / 2, 0.0))
    # arms
    ut_top = ut_bottom + ut[1]
    shoulder_y = ut_top - shoulder_drop
    for side, sx in (("Right", 1), ("Left", -1)):
        ax = sx * (ut[0] / 2 + ua[0] / 2 + arm_gap)
        ua_top = shoulder_y + 0.14
        ua_c = ua_top - ua[1] / 2
        elbow = ua_top - ua[1] + 0.06
        la_top = elbow + 0.06
        la_c = la_top - la[1] / 2
        wrist = la_top - la[1] + 0.05
        hand_top = wrist + 0.05
        parts[f"{side}UpperArm"] = (ua, (ax, ua_c, 0.0))
        parts[f"{side}LowerArm"] = (la, (ax, la_c, 0.0))
        parts[f"{side}Hand"] = (hand, (ax, hand_top - hand[1] / 2, 0.0))
        piv[f"{side}Shoulder"] = (sx * ut[0] / 2, shoulder_y, 0.0)
        piv[f"{side}Elbow"] = (ax, elbow, 0.0)
        piv[f"{side}Wrist"] = (ax, wrist, 0.0)
    return BodyProfile(pid, label, parts, piv, notes)


# ----- the three V2 candidates (and v1 for reference) ---------------------------------
def candidates() -> list[BodyProfile]:
    v1 = make_profile("v1", "v1 (approved Step 0)",
                      head=(1.50, 1.55, 1.35), ut=(2.20, 1.30, 1.10), lt=(1.90, 0.70, 1.00),
                      ua=(0.75, 1.00, 0.75), la=(0.70, 0.90, 0.70), hand=(0.75, 0.70, 0.75),
                      ul=(0.80, 1.00, 0.80), ll=(0.75, 0.90, 0.75), foot=(0.80, 0.60, 1.10), leg_x=0.50, arm_gap=-0.025, neck_gap=-0.06,
                      notes="Step 0 numbers rebuilt bottom-up (joint overlaps make it 0.045 taller than the spec stack).")
    v1.dims["neckGap"] = -0.06
    p1 = make_profile("P1", "P1 — v1 frame, V2 hands/feet",
                      head=(1.60, 1.60, 1.45), ut=(2.15, 1.25, 1.10), lt=(1.88, 0.70, 1.00),
                      ua=(0.78, 0.95, 0.78), la=(0.78, 0.90, 0.78), hand=(0.84, 0.60, 0.82),
                      ul=(0.82, 1.00, 0.82), ll=(0.76, 0.85, 0.76), foot=(0.84, 0.50, 1.18), leg_x=0.50,
                      notes="Closest to v1: same leg length, slightly bigger head, broader hands and boots.")
    p2 = make_profile("P2", "P2 — recommended: 3.1 heads, short shins, thick forearms",
                      head=(1.72, 1.72, 1.58), ut=(2.10, 1.25, 1.10), lt=(1.85, 0.70, 1.00),
                      ua=(0.80, 0.92, 0.80), la=(0.82, 0.85, 0.82), hand=(0.90, 0.62, 0.88),
                      ul=(0.85, 1.00, 0.85), ll=(0.78, 0.80, 0.78), foot=(0.85, 0.50, 1.20), leg_x=0.52,
                      notes="Head +11%, lower leg -6%, forearm thicker than the upper arm, hands 0.90 wide, boots 1.2 long.")
    p3 = make_profile("P3", "P3 — 2.7 heads, compact",
                      head=(1.95, 1.95, 1.75), ut=(2.15, 1.20, 1.15), lt=(1.90, 0.65, 1.05),
                      ua=(0.85, 0.88, 0.85), la=(0.88, 0.80, 0.88), hand=(0.98, 0.66, 0.95),
                      ul=(0.90, 0.90, 0.90), ll=(0.82, 0.68, 0.82), foot=(0.92, 0.50, 1.25), leg_x=0.54,
                      notes="Chibi-leaning: biggest head, shortest legs; reads at 40 studs but crowds the hat/hair slot.")
    return [v1, p1, p2, p3]


def profile(pid: str) -> BodyProfile:
    for p in candidates():
        if p.id == pid:
            return p
    raise KeyError(pid)


# ===== forward kinematics =====================================================
@dataclass
class Bone:
    name: str
    M: np.ndarray          # world rotation
    p: np.ndarray          # world centre of the part
    size: np.ndarray

    def to_world(self, mesh: L.Mesh) -> L.Mesh:
        return mesh.transformed(self.M, self.p)

    def point(self, local) -> np.ndarray:
        return self.p + self.M @ np.asarray(local, dtype=float)


def joint_rotation(kind: str, side: int, axes: dict | None) -> np.ndarray:
    if not axes:
        return np.eye(3)
    if kind == "spine":
        return L.angles(-axes.get("bend", 0.0), -axes.get("turn", 0.0), -axes.get("tilt", 0.0))
    return L.angles(axes.get("swing", 0.0), side * axes.get("twist", 0.0), side * axes.get("spread", 0.0))


def pose(profile: BodyProfile, rest: dict[str, dict] | None = None) -> dict[str, Bone]:
    """World transforms of every part after the rest pose (semantic axes, degrees — the
    same vocabulary NpcMotion bakes into C0). Joints resolve parent-first."""
    rest = rest or {}
    bones: dict[str, Bone] = {}
    hrp = profile.centre("HumanoidRootPart")
    bones["HumanoidRootPart"] = Bone("HumanoidRootPart", np.eye(3), hrp, profile.size("HumanoidRootPart"))
    pending = list(JOINTS)
    while pending:
        for j in list(pending):
            name, p0, p1, kind, side = j
            if p0 not in bones:
                continue
            parent = bones[p0]
            pivot = np.array(profile.pivots[name], dtype=float)
            R = joint_rotation(kind, side, rest.get(name))
            pivot_world = parent.p + parent.M @ (pivot - profile.centre(p0))
            M = parent.M @ R
            c = pivot_world + M @ (profile.centre(p1) - pivot)
            bones[p1] = Bone(p1, M, c, profile.size(p1))
            pending.remove(j)
    return bones


def pivots_world(profile: BodyProfile, bones: dict[str, Bone]) -> dict[str, np.ndarray]:
    out = {}
    for name, p0, p1, kind, side in JOINTS:
        parent = bones[p0]
        pivot = np.array(profile.pivots[name], dtype=float)
        out[name] = parent.p + parent.M @ (pivot - profile.centre(p0))
    return out


# skeleton drawing graph: (from joint | part-end, to joint | part-end)
SKELETON_EDGES = [
    ("Root", "Waist"), ("Waist", "Neck"), ("Neck", "Head:top"),
    ("Neck", "RightShoulder"), ("RightShoulder", "RightElbow"), ("RightElbow", "RightWrist"), ("RightWrist", "RightHand:end"),
    ("Neck", "LeftShoulder"), ("LeftShoulder", "LeftElbow"), ("LeftElbow", "LeftWrist"), ("LeftWrist", "LeftHand:end"),
    ("Root", "RightHip"), ("RightHip", "RightKnee"), ("RightKnee", "RightAnkle"), ("RightAnkle", "RightFoot:toe"),
    ("Root", "LeftHip"), ("LeftHip", "LeftKnee"), ("LeftKnee", "LeftAnkle"), ("LeftAnkle", "LeftFoot:toe"),
]


def skeleton_points(profile: BodyProfile, bones: dict[str, Bone]) -> dict[str, np.ndarray]:
    pts = pivots_world(profile, bones)
    pts["Head:top"] = bones["Head"].point((0, bones["Head"].size[1] / 2, 0))
    for side in ("Right", "Left"):
        h = bones[f"{side}Hand"]
        pts[f"{side}Hand:end"] = h.point((0, -h.size[1] / 2, 0))
        f = bones[f"{side}Foot"]
        pts[f"{side}Foot:toe"] = f.point((0, 0, -f.size[2] / 2))
    return pts


# ===== the Tier 1 body kit (what a plain villager is allowed to show) ============
SKIN = (222, 178, 138)


def body_kit(profile: BodyProfile, skin: RGB = SKIN, trousers: RGB | None = None, shirt: RGB | None = None) -> dict[str, L.Mesh]:
    """Bone-local meshes for every part of the rig: chamfered, slightly tapered blocks —
    the visible common kit for Tier 1 and the hidden reference under Tier 2/3 shells."""
    out: dict[str, L.Mesh] = {}
    hd = profile.size("Head")
    head = L.rounded_box(hd, n=12, p=3.2, r_bottom=0.22, r_top=0.28, taper_bottom=0.90, color=skin, name="Head")
    neck = L.tube(L.superellipse(8, hd[0] * 0.26, hd[2] * 0.26, 3.0), [(-hd[1] / 2 - 0.40, 1.0, 1.0), (-hd[1] / 2 + 0.12, 1.0, 1.0)], skin, "Neck")
    out["Head"] = L.merge([head, neck], skin, "Head")
    ut = profile.size("UpperTorso")
    out["UpperTorso"] = L.rounded_box(ut, n=10, p=4.5, r_bottom=0.10, r_top=0.16, taper_top=0.92, taper_bottom=0.98,
                                      color=shirt or skin, name="UpperTorso")
    lt = profile.size("LowerTorso")
    out["LowerTorso"] = L.rounded_box(lt, n=10, p=4.5, r_bottom=0.10, r_top=0.08, color=trousers or shirt or skin, name="LowerTorso")
    limb_prof = L.superellipse(8, 1, 1, 3.5)
    for side in ("Right", "Left"):
        ua = profile.size(f"{side}UpperArm")
        out[f"{side}UpperArm"] = L.tube(limb_prof, [(-ua[1] / 2, ua[0] / 2 * 0.86, ua[2] / 2 * 0.86), (-ua[1] / 2 + 0.14, ua[0] / 2 * 0.95, ua[2] / 2 * 0.95),
                                                    (ua[1] / 2 - 0.16, ua[0] / 2, ua[2] / 2), (ua[1] / 2, ua[0] / 2 * 0.90, ua[2] / 2 * 0.90)],
                                        color=shirt or skin, name=f"{side}UpperArm")
        la = profile.size(f"{side}LowerArm")
        out[f"{side}LowerArm"] = L.tube(limb_prof, [(-la[1] / 2, la[0] / 2 * 0.80, la[2] / 2 * 0.80), (-la[1] / 2 + 0.12, la[0] / 2 * 0.90, la[2] / 2 * 0.90),
                                                    (la[1] / 2 - 0.14, la[0] / 2, la[2] / 2), (la[1] / 2, la[0] / 2 * 0.92, la[2] / 2 * 0.92)],
                                        color=skin, name=f"{side}LowerArm")
        hs = profile.size(f"{side}Hand")
        out[f"{side}Hand"] = hand_mesh(hs, 1 if side == "Right" else -1, skin, f"{side}Hand")
        ul = profile.size(f"{side}UpperLeg")
        out[f"{side}UpperLeg"] = L.tube(limb_prof, [(-ul[1] / 2, ul[0] / 2 * 0.88, ul[2] / 2 * 0.88), (-ul[1] / 2 + 0.14, ul[0] / 2 * 0.96, ul[2] / 2 * 0.96),
                                                    (ul[1] / 2 - 0.12, ul[0] / 2, ul[2] / 2), (ul[1] / 2, ul[0] / 2 * 0.94, ul[2] / 2 * 0.94)],
                                        color=trousers or skin, name=f"{side}UpperLeg")
        ll = profile.size(f"{side}LowerLeg")
        out[f"{side}LowerLeg"] = L.tube(limb_prof, [(-ll[1] / 2, ll[0] / 2 * 0.84, ll[2] / 2 * 0.84), (-ll[1] / 2 + 0.12, ll[0] / 2 * 0.92, ll[2] / 2 * 0.92),
                                                    (ll[1] / 2 - 0.12, ll[0] / 2, ll[2] / 2), (ll[1] / 2, ll[0] / 2 * 0.94, ll[2] / 2 * 0.94)],
                                        color=trousers or skin, name=f"{side}LowerLeg")
        fs = profile.size(f"{side}Foot")
        out[f"{side}Foot"] = foot_mesh(fs, color=(120, 92, 70), name=f"{side}Foot")
    return out


def hand_mesh(size, side: int, color: RGB, name: str = "Hand", thumb: bool = True) -> L.Mesh:
    """A stylised mitten: chamfered block plus a thumb wedge on the body side."""
    w, h, d = size
    palm = L.rounded_box((w, h, d), n=8, p=3.0, r_bottom=0.24, r_top=0.14, taper_bottom=0.86, color=color, name=name)
    if not thumb:
        return palm
    t = L.rounded_box((w * 0.34, h * 0.55, d * 0.42), n=6, p=2.5, r_bottom=0.08, r_top=0.08, color=color)
    t = t.rotated(rz=side * -28).translated(-side * (w * 0.50), h * 0.08, -d * 0.22)
    return L.merge([palm, t], color, name)


def foot_mesh(size, color: RGB, name: str = "Foot", toe_drop: float = 0.34, heel: float = 0.94) -> L.Mesh:
    """Lofted along Z (heel at +Z, toe at -Z); the toe ring is lower and narrower so the top
    slopes down while the sole stays flat."""
    w, h, d = size
    prof = L.superellipse(8, w / 2, h / 2, 3.2)
    rings = [
        L.ring_xy(prof, d / 2, heel, heel * 0.96, oy=h * (1 - heel * 0.96) / 2 * -1),
        L.ring_xy(prof, d / 2 - 0.16, 1.0, 1.0),
        L.ring_xy(prof, -d / 2 + 0.30, 1.0, 0.94, oy=-h * 0.03),
        L.ring_xy(prof, -d / 2 + 0.06, 0.92, 1 - toe_drop, oy=-h * toe_drop / 2),
        L.ring_xy(prof, -d / 2, 0.70, (1 - toe_drop) * 0.7, oy=-h * (toe_drop / 2 + (1 - toe_drop) * 0.15)),
    ]
    return L.loft(rings, True, True, color, name)
