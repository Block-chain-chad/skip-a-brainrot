"""characters25.py — the V2.5 study cast on the P2 skeleton.

  Tier 1  Valley Villager   polished background NPC: reusable shells, hair, face, a skipping stone
  Tier 2  Valley Merchant   named quest NPC: unique silhouette, custom face combination, signature prop, posture
  Tier 3  Gianluca V2.5     major story NPC — OLD VETERAN: fought beside Elder Tung; ranger / survivor.

Gianluca's name, role, prompt and dialogue contracts are untouched (looks only).
"""
from __future__ import annotations

import numpy as np

from npc_kit.v2 import kit as K
from npc_kit.v2 import kit25 as K25
from npc_kit.v2 import profiles as P
from npc_kit.v2.kit import Character, Piece


def _replace(slots: dict[str, Piece], piece: Piece) -> None:
    slots[piece.bone] = piece


# ===== Tier 1 ==========================================================================
def villager(profile: P.BodyProfile | None = None) -> Character:
    profile = profile or P.profile("P2")
    pal = dict(skin=(222, 178, 138), hair=(74, 52, 36), tunic=(178, 150, 108), trousers=(96, 90, 76), boots=(92, 68, 48), rope=(126, 96, 62), stone=(150, 148, 140))
    slots = K.slot_defaults(profile, pal["skin"], pal["trousers"], pal["tunic"])
    _replace(slots, K25.head_shell(profile, pal["skin"], K25.YOUNG))
    _replace(slots, K.shirt(profile, pal["tunic"]))                                  # reusable tunic shell
    _replace(slots, K.hips(profile, pal["tunic"], flare=1.04))                       # tunic hem
    for side in ("Right", "Left"):
        _replace(slots, K.sleeve(profile, side, pal["tunic"], puff=1.22, rolled=False))
        for p in K.boots(profile, side, pal["boots"], cuff=0.0, oversize=1.02):    # reusable simple boots
            _replace(slots, p)
    pieces = list(slots.values())
    pieces += K25.face(profile, "happy", K25.YOUNG, iris=(52, 40, 34), brow=pal["hair"])
    pieces.append(K25.hair(profile, "cropped", pal["hair"]))
    pieces.append(K.rope_belt(profile, pal["rope"]))
    rest = {"Neck": {"turn": 12, "tilt": 3}, "RightShoulder": {"swing": 22, "spread": 8}, "RightElbow": {"swing": 48},
            "LeftShoulder": {"spread": 8}, "LeftElbow": {"swing": 8}, "Waist": {"tilt": 1.5}}
    bones = P.pose(profile, rest)
    pieces.append(K25.rock(bones["RightHand"], pal["stone"]))
    return Character("Villager_T1", "Tier 1 — Valley Villager (background, reusable shells)", 1, profile, pieces, rest, pal)


# ===== Tier 2 ==========================================================================
def merchant(profile: P.BodyProfile | None = None) -> Character:
    profile = profile or P.profile("P2")
    pal = dict(skin=(214, 166, 126), hair=(150, 110, 60), shirt=(214, 196, 160), apron=(236, 228, 208), trousers=(72, 66, 80), cap=(96, 72, 52),
               boots=(70, 52, 38), leather=(132, 96, 60), kerchief=(190, 70, 60), sack=(146, 112, 72), belt=(60, 44, 30))
    slots = K.slot_defaults(profile, pal["skin"], pal["trousers"], pal["shirt"])
    _replace(slots, K25.head_shell(profile, pal["skin"], K25.FaceStyle(lid=0.20, nose=0.4)))
    _replace(slots, K.shirt(profile, pal["shirt"]))
    for side in ("Right", "Left"):
        _replace(slots, K.sleeve(profile, side, pal["shirt"], puff=1.45, rolled=True))
        for p in K.boots(profile, side, pal["boots"], cuff=0.4, oversize=1.08):
            _replace(slots, p)
    pieces = list(slots.values())
    pieces += K.forearm(profile, "Left", pal["skin"], cuff=pal["leather"])[1:]
    pieces += K25.face(profile, "happy", K25.FaceStyle(lid=0.20, nose=0.4), iris=(60, 44, 36), brow=pal["hair"])
    pieces.append(K25.moustache(profile, pal["hair"]))                                # custom face combination
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
    hand = bones["LeftHand"]
    sack = K.coin_sack(pal["sack"]).translated(0, -0.72, 0).translated(hand.p[0], hand.p[1] - 0.28, hand.p[2] - 0.12)
    pieces.append(Piece("CoinSack", "LeftHand", sack, "reusable", False, "prop", True))
    return Character("Merchant_T2", "Tier 2 — Valley Merchant (named quest NPC)", 2, profile, pieces, rest, pal)


# ===== Tier 3 — Gianluca V2.5 =============================================================
PALETTE = dict(skin=(208, 162, 122), skin_dark=(170, 126, 94), hair=(182, 178, 170), beard=(198, 194, 186), brow=(80, 72, 66), iris=(72, 58, 44),
               coat=(96, 86, 58), hood=(60, 64, 44), tunic=(188, 164, 120), scarf=(150, 84, 96), belt=(58, 42, 28), pouch=(128, 96, 60),
               glove=(92, 66, 44), leather=(104, 74, 46), boots=(66, 46, 30), trousers=(78, 70, 58), iron=(112, 110, 104), brass=(150, 122, 70),
               wood=(70, 52, 34), steel=(150, 150, 146))

VETERAN_REST = {
    "Waist": {"bend": 9, "turn": 4, "tilt": 3},                 # forward lean, torso tipped toward the staff side
    "Neck": {"bend": 4, "turn": -8, "tilt": 4},                 # chin a little down, head turned, cocked
    "RightShoulder": {"swing": 40, "spread": 12}, "RightElbow": {"swing": 34},      # hand resting high on the staff
    "LeftShoulder": {"spread": 9, "swing": -12}, "LeftElbow": {"swing": 22},        # the plated arm hangs back
    "RightHip": {"spread": 2}, "LeftHip": {"spread": 9}, "LeftKnee": {"swing": 10},  # weight on the staff-side leg
    "LeftAnkle": {"swing": -10, "spread": -9},                  # sole stays flat on the ground
}

BEATS = {
    "idle — resting on the staff": dict(rest=VETERAN_REST, expression="serious", look=(0.0, 0.02)),
    "idle — weight shift, slow look": dict(rest={**VETERAN_REST, "Waist": {"bend": 8, "turn": -5, "tilt": -1}, "Neck": {"bend": 2, "turn": 24, "tilt": -3},
                                                 "RightHip": {"spread": 7}, "LeftHip": {"spread": 4}, "LeftKnee": {"swing": 3}, "RightKnee": {"swing": 6}},
                                           expression="neutral", look=(-0.03, 0.0)),
    "talking — restrained point": dict(rest={**VETERAN_REST, "Neck": {"bend": 1, "turn": 4, "tilt": 2}, "LeftShoulder": {"swing": 46, "spread": 14}, "LeftElbow": {"swing": 72}},
                                       expression="serious", look=(0.0, 0.0)),
    "war reaction — stiffen, grip, look away": dict(rest={**VETERAN_REST, "Waist": {"bend": 3, "turn": 2, "tilt": 1}, "Neck": {"bend": 7, "turn": 32, "tilt": -5},
                                                          "RightElbow": {"swing": 42}, "LeftShoulder": {"swing": -18, "spread": 7}, "LeftElbow": {"swing": 28}},
                                                    expression="tired", look=(0.05, -0.02)),
}


def gianluca_v25(profile: P.BodyProfile | None = None, expression: str = "serious", hair: str = "sweptback", beard_style: str = "short",
                 prop: str = "spear", rest: dict | None = None, look=(0.0, 0.02), hat: bool = False, palette: dict | None = None) -> Character:
    profile = profile or P.profile("P2")
    pal = dict(PALETTE, **(palette or {}))
    rest = rest or VETERAN_REST
    fs = K25.VETERAN
    slots = K.slot_defaults(profile, pal["skin"], pal["trousers"])
    _replace(slots, K25.head_shell(profile, pal["skin"], fs, jaw=0.92))
    _replace(slots, K.coat_body(profile, pal["coat"], chest=1.07, shoulder=1.14))
    _replace(slots, K.hips(profile, pal["trousers"]))
    _replace(slots, K.sleeve(profile, "Right", pal["coat"], puff=1.45, rolled=False))
    _replace(slots, K.sleeve(profile, "Left", pal["coat"], puff=1.45, rolled=False))
    _replace(slots, K.bracer(profile, "Right", pal["leather"], flare=1.26))
    _replace(slots, K.bracer(profile, "Left", pal["leather"], flare=1.20))
    for p in K25.gloves(profile, pal["glove"]):
        _replace(slots, p)
    for side in ("Right", "Left"):
        for p in K25.boots(profile, side, pal["boots"], oversize=1.16, straps=2):
            _replace(slots, p)
    pieces = list(slots.values())
    # head treatment
    pieces += K25.face(profile, expression, fs, iris=pal["iris"], brow=pal["brow"], look=look)
    pieces.append(K25.age_lines(profile, fs, pal["skin_dark"], beard=beard_style in ("short", "stubble", "goatee")))
    if beard_style != "none":
        pieces.append(K25.beard(profile, beard_style, pal["beard"], sideburns=True))
    pieces.append(K25.hair(profile, hair, pal["hair"]))
    if hat:
        hat_pieces = K.ranger_hat(profile, (96, 122, 70), (188, 176, 150))
        for hp in hat_pieces:                                   # pushed further back so the swept hair stays visible
            hp.mesh = hp.mesh.translated(0, -0.70, 0).rotated(rx=16).translated(0, 0.70 + 0.28, 0.06)
        pieces += hat_pieces
    # outfit: one designed set
    pieces.append(K25.hood_down(profile, pal["hood"]))
    pieces.append(K25.scarf(profile, pal["scarf"], tail_side=1))
    pieces.append(K25.clasp(profile, pal["brass"], at=(0.66, -0.42), size=0.27))   # pins the scarf tail high on his right                 # the Elder Tung clue (right of centre, on the scarf)
    pieces.append(K.tunic_front(profile, pal["tunic"]))
    pieces.append(K25.coat_skirts(profile, pal["coat"], length=1.25, frayed=True))
    pieces += K.belt(profile, pal["belt"], buckle=pal["brass"], thick=0.18, over=0.10)
    pieces.append(K.pouch(profile, side=-1, color=pal["pouch"]))
    pieces.append(K.chim_collar(profile, pal["wood"]))
    pieces.append(K25.belt_bell(profile, pal["brass"], side=1))
    pieces.append(K25.shoulder_plate(profile, side=-1, color=pal["iron"], cracked=True))
    pieces.append(K25.sleeve_patch(profile, "Left", pal["tunic"]))
    # prop, planted by the right foot, gripped by the right hand
    bones = P.pose(profile, rest)
    hand = bones["RightHand"]
    grip = hand.point((0.0, -0.02, -0.12))
    ground = np.array([grip[0] + 0.18, 0.0, grip[2] - 0.22])
    if prop == "spear":
        pieces += K25.spear_staff(grip, ground, pal["wood"], pal["steel"], pal["glove"], pal["scarf"])
    elif prop == "sword":
        pieces += K25.broken_sword_staff(grip, ground, pal["steel"], pal["glove"], pal["brass"])
    elif prop == "cane":
        pieces += K25.veteran_cane(grip, ground, pal["wood"], pal["iron"])
    return Character("Gianluca_V25", "Tier 3 — Gianluca V2.5 (old veteran, major story NPC)", 3, profile, pieces, rest, pal)


def cast(profile: P.BodyProfile | None = None) -> list[Character]:
    return [villager(profile), merchant(profile), gianluca_v25(profile)]


# outfit layer breakdown (progressive build) — names per layer, in order
LAYERS = [
    ("1 skeleton + body kit", None),
    ("2 body shells: head, gloves, boots", {"Head", "RightHand", "LeftHand", "RightLowerLeg", "LeftLowerLeg", "RightFoot", "LeftFoot", "LowerTorso", "RightUpperLeg", "LeftUpperLeg"}),
    ("3 + tunic, coat, sleeves, bracers, tails", {"UpperTorso", "TunicFront", "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm", "CoatSkirts"}),
    ("4 + hood down, faded scarf, clasp", {"HoodDown", "Scarf", "Clasp"}),
    ("5 + belt, pouch, Chim collar + bell", {"Belt", "Buckle", "Pouch", "ChimCollar", "Bell"}),
    ("6 + war remnants: shoulder plate, patch", {"ShoulderPlate", "LeftPatch"}),
    ("7 + head: hair, beard, age, face", {"Hair", "Beard", "AgeLines", "EyeL", "EyeR", "PupilL", "PupilR", "BrowL", "BrowR", "Mouth"}),
    ("8 + the spear-staff", {"Spear", "SpearGrip", "SpearHead", "SpearCloth"}),
]
