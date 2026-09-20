"""characters.py — the V2 study cast: one character per visual tier on the same skeleton.

  Tier 1  Valley Villager  — the common body kit is allowed to show; hair + belt + face.
  Tier 2  Valley Merchant  — reusable shells (shirt, puff sleeves, apron, cap, work boots,
                             satchel, neckerchief) hide the base body; no bespoke mesh.
  Tier 3  Gianluca V2      — the human style test: bespoke hat + Chim collar on top of the
                             reusable ranger kit; every piece placed for his silhouette.

Only looks live here. Gianluca keeps his name, role, prompt and dialogue contracts
(see NpcCharacters/Gianluca.lua) — this module never touches them.
"""
from __future__ import annotations

import numpy as np

from npc_kit.v2 import kit as K
from npc_kit.v2 import profiles as P
from npc_kit.v2.kit import Character, Piece

SKIN = (222, 178, 138)
SKIN_WARM = (214, 166, 126)
SKIN_PALE = (232, 196, 160)


def _replace(slots: dict[str, Piece], piece: Piece) -> None:
    slots[piece.bone] = piece


def villager(profile: P.BodyProfile | None = None) -> Character:
    profile = profile or P.profile("P2")
    pal = dict(skin=SKIN, hair=(60, 42, 30), tunic=(176, 150, 110), trousers=(98, 92, 78), shoes=(88, 66, 48), rope=(120, 90, 60))
    slots = K.slot_defaults(profile, pal["skin"], pal["trousers"], pal["tunic"])
    _replace(slots, K.hips(profile, pal["tunic"], flare=1.0))          # tunic hem block over the hips
    for side in ("Right", "Left"):
        _replace(slots, K.shoes(profile, side, pal["shoes"]))
    pieces = list(slots.values())
    pieces += K.face(profile, "happy", iris=(52, 40, 34), brow=pal["hair"])
    pieces.append(K.hair(profile, "crop", pal["hair"]))
    pieces.append(K.rope_belt(profile, pal["rope"]))
    rest = {"Neck": {"turn": 10, "tilt": 3}, "RightShoulder": {"spread": 8}, "LeftShoulder": {"spread": 8},
            "RightElbow": {"swing": 8}, "LeftElbow": {"swing": 8}, "Waist": {"tilt": 1.5}}
    return Character("Villager_T1", "Tier 1 — Valley Villager (common kit)", 1, profile, pieces, rest, pal)


def merchant(profile: P.BodyProfile | None = None) -> Character:
    profile = profile or P.profile("P2")
    pal = dict(skin=SKIN_WARM, hair=(150, 110, 60), shirt=(214, 196, 160), apron=(236, 228, 208), trousers=(72, 66, 80), cap=(96, 72, 52),
               boots=(70, 52, 38), leather=(132, 96, 60), kerchief=(190, 70, 60), sack=(146, 112, 72), belt=(60, 44, 30))
    slots = K.slot_defaults(profile, pal["skin"], pal["trousers"], pal["shirt"])
    _replace(slots, K.shirt(profile, pal["shirt"]))
    for side in ("Right", "Left"):
        _replace(slots, K.sleeve(profile, side, pal["shirt"], puff=1.45, rolled=True))
        for p in K.boots(profile, side, pal["boots"], cuff=0.4, oversize=1.08):
            _replace(slots, p)
    pieces = list(slots.values())
    # asymmetry: one wrist cuff on the left forearm (welded), satchel strap over the left shoulder, bag on the right hip
    w, h, d = profile.size("LeftLowerArm")
    pieces += K.forearm(profile, "Left", pal["skin"], cuff=pal["leather"])[1:]
    pieces += K.face(profile, "happy", iris=(60, 44, 36), brow=pal["hair"])
    pieces.append(K.hair(profile, "side", pal["hair"]))
    pieces.append(K.flat_cap(profile, pal["cap"]))
    pieces.append(K.neckerchief(profile, pal["kerchief"]))
    pieces += K.apron(profile, pal["apron"])
    pieces += K.belt(profile, pal["belt"], buckle=None, thick=0.14)
    pieces += K.satchel(profile, side=1, color=pal["leather"])
    rest = {"Neck": {"turn": -8, "tilt": -4}, "Waist": {"turn": 4},
            "LeftShoulder": {"swing": 30, "spread": 16}, "LeftElbow": {"swing": 62},
            "RightShoulder": {"spread": 12, "swing": -10}, "RightElbow": {"swing": 10},
            "RightHip": {"spread": 3}, "LeftHip": {"spread": 3}}
    bones = P.pose(profile, rest)
    # the coin sack sits in the raised left hand
    hand = bones["LeftHand"]
    sack = K.coin_sack(pal["sack"]).translated(0, -0.72, 0).translated(hand.p[0], hand.p[1] - 0.28, hand.p[2] - 0.12)   # hangs below the fist
    pieces.append(Piece("CoinSack", "LeftHand", sack, "reusable", False, "prop", True))
    return Character("Merchant_T2", "Tier 2 — Valley Merchant (reusable shells)", 2, profile, pieces, rest, pal)


def gianluca_v2(profile: P.BodyProfile | None = None, expression: str = "worried") -> Character:
    profile = profile or P.profile("P2")
    pal = dict(skin=SKIN, hair=(92, 58, 36), accent=(168, 58, 86), hat=(108, 160, 80), band=(236, 224, 190), walnut=(74, 50, 30),
               metal=(196, 150, 72), coat=(110, 96, 62), mantle=(70, 76, 50), tunic=(196, 168, 120), trousers=(86, 74, 62),
               leather=(110, 76, 46), pouch=(140, 104, 66), belt=(60, 44, 30))
    slots = K.slot_defaults(profile, pal["skin"], pal["trousers"])
    _replace(slots, K.coat_body(profile, pal["coat"], chest=1.08, shoulder=1.16))
    _replace(slots, K.hips(profile, pal["trousers"]))
    _replace(slots, K.sleeve(profile, "Right", pal["coat"], puff=1.5, rolled=False))
    _replace(slots, K.sleeve(profile, "Left", pal["coat"], puff=1.5, rolled=True))          # rolled on his left: asymmetry
    _replace(slots, K.bracer(profile, "Right", pal["leather"], flare=1.30))
    _replace(slots, K.bracer(profile, "Left", pal["leather"], flare=1.22))
    for p in K.hands(profile, pal["skin"]):
        _replace(slots, p)
    for side in ("Right", "Left"):
        for p in K.boots(profile, side, pal["walnut"], cuff=1.0, oversize=1.15):
            _replace(slots, p)
    pieces = list(slots.values())
    pieces += K.face(profile, expression, iris=(70, 50, 36), brow=pal["hair"])
    pieces.append(K.hair(profile, "tousled", pal["hair"]))
    pieces += K.ranger_hat(profile, pal["hat"], pal["band"])
    pieces.append(K.scarf(profile, pal["accent"], tail_side=-1))
    pieces.append(K.mantle(profile, pal["mantle"], reach=0.60, drop=0.55, front_point=0.14, collar=0.30))
    pieces.append(K.tunic_front(profile, pal["tunic"]))
    pieces.append(K.coat_skirts(profile, pal["coat"], length=1.15, split=True))
    pieces += K.belt(profile, pal["belt"], buckle=pal["metal"], thick=0.18, over=0.10)
    pieces.append(K.pouch(profile, side=-1, color=pal["pouch"]))
    pieces.append(K.chim_collar(profile, pal["walnut"]))
    rest = {"Waist": {"bend": 4, "turn": 5}, "Neck": {"turn": -10, "tilt": 6},
            "RightShoulder": {"spread": 14, "swing": 26}, "RightElbow": {"swing": 40},
            "LeftShoulder": {"spread": 10, "swing": -6}, "LeftElbow": {"swing": 14},
            "LeftHip": {"spread": 5}, "LeftKnee": {"swing": 3}}
    bones = P.pose(profile, rest)
    hand = bones["RightHand"]
    grip = hand.point((0.0, -0.06, -0.10))
    ground = np.array([grip[0] + 0.30, 0.0, grip[2] - 0.30])
    pieces += K.cane_with_bell(grip, ground, pal["walnut"], pal["metal"])
    return Character("Gianluca_V2", "Tier 3 — Gianluca V2 (human style test)", 3, profile, pieces, rest, pal)


def cast(profile: P.BodyProfile | None = None) -> list[Character]:
    return [villager(profile), merchant(profile), gianluca_v2(profile)]
