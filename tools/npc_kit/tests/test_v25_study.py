"""V2.5 study: the mature face language keeps the seven-part contract and never floats,
gray hair styles keep the forehead and brows clear, the beard leaves the mouth open,
Gianluca V2.5 carries his story pieces with the intended asymmetry, every pose beat keeps
the spear planted in his hand, and every tier fits the NpcBudget caps read from the Lua."""
import numpy as np
import pytest

from brainrot_forge.export_glb import read_glb, write_glb

from npc_kit.v2 import characters25 as C
from npc_kit.v2 import kit25 as K25
from npc_kit.v2 import profiles as P

FACE = {"EyeL", "EyeR", "PupilL", "PupilR", "BrowL", "BrowR", "Mouth"}


def caps(H, tier):
    Budget = H.require("ServerStorage/NpcBudget")
    lim = Budget.Limits.human[tier]
    return {k: int(lim[k]) for k in ("baseParts", "bespokeMeshes", "triangles", "motor6d", "welds")}


def test_face25_keeps_the_contract_for_every_expression_and_style():
    prof = P.profile("P2")
    hw, hh, hd = prof.size("Head")
    zf = -hd / 2
    for fs in (K25.YOUNG, K25.MATURE, K25.VETERAN):
        for ex in ("neutral", "happy", "worried", "angry", "suspicious", "tired", "shocked", "serious"):
            parts = {p.name: p for p in K25.face(prof, ex, fs)}
            assert set(parts) == FACE
            for name, p in parts.items():
                lo, hi = p.mesh.bounds()
                assert lo[0] >= -hw / 2 and hi[0] <= hw / 2, f"{name} outside the head width ({fs}, {ex})"
                assert lo[1] >= -hh / 2 and hi[1] <= hh / 2, f"{name} outside the head height ({fs}, {ex})"
                assert lo[2] >= zf - 0.16 and lo[2] <= zf - 0.02, f"{name} not proud of the face plane ({ex}): {lo[2]:.3f} vs {zf:.3f}"
            # the lash line (part of the brow mesh) never floats above the eye: the brow mesh's lowest point stays inside the eye's height
            eye_lo, eye_hi = parts["EyeR"].mesh.bounds()
            brow_lo = parts["BrowR"].mesh.bounds()[0]
            assert eye_lo[1] - 0.02 <= brow_lo[1] <= eye_hi[1] + 0.02, f"lash line floats ({fs.lid}, {ex}): {brow_lo[1]:.3f} vs eye {eye_lo[1]:.3f}..{eye_hi[1]:.3f}"
            assert parts["EyeR"].mesh.bounds()[0][0] > parts["EyeL"].mesh.bounds()[1][0] + 0.15


def test_head_shell_lids_and_nose_are_geometry_only():
    prof = P.profile("P2")
    young = K25.head_shell(prof, (200, 160, 120), K25.YOUNG)
    old = K25.head_shell(prof, (200, 160, 120), K25.VETERAN)
    assert young.slot and old.slot and young.ownership == "skeleton"
    assert old.mesh.tris > young.mesh.tris                       # nose + heavier lids
    hw, hh, hd = prof.size("Head")
    assert old.mesh.bounds()[0][2] < -hd / 2 - 0.08              # the nose wedge is proud of the face


def test_gray_hair_styles_keep_the_forehead_clear():
    prof = P.profile("P2")
    hw, hh, hd = prof.size("Head")
    brow_top = max(p.mesh.bounds()[1][1] for p in K25.face(prof, "neutral", K25.VETERAN) if p.name.startswith("Brow"))
    for style in ("sweptback", "cropped", "tiedback"):
        hair = K25.hair(prof, style).mesh
        v = hair.verts
        front = v[(v[:, 2] < -0.35 * hd) & (np.abs(v[:, 0]) < 0.30 * hw)]
        assert front[:, 1].min() >= brow_top + 0.06, f"{style}: hairline {front[:, 1].min():.2f} crowds the brows {brow_top:.2f}"
        assert v[:, 1].max() > hh / 2 + 0.10, f"{style}: no volume above the crown"


def test_beard_leaves_the_mouth_open():
    prof = P.profile("P2")
    hw, hh, hd = prof.size("Head")
    mouth = next(p for p in K25.face(prof, "neutral", K25.VETERAN) if p.name == "Mouth").mesh
    m_lo, m_hi = mouth.bounds()
    for style in ("short", "stubble"):
        b = K25.beard(prof, style).mesh.verts
        # no beard / moustache vertex inside the mouth's box (padded), i.e. the mouth stays readable
        inside = ((b[:, 0] > m_lo[0] - 0.03) & (b[:, 0] < m_hi[0] + 0.03) & (b[:, 1] > m_lo[1] - 0.03) & (b[:, 1] < m_hi[1] + 0.03) & (b[:, 2] < -0.40 * hd))
        assert not inside.any(), f"{style} beard covers the mouth"


def test_v25_cast_fits_the_tier_caps(H):
    for ch in C.cast():
        b = ch.budget()
        c = caps(H, ch.tier)
        for k in ("baseParts", "bespokeMeshes", "triangles", "motor6d", "welds"):
            assert b[k] <= c[k], f"{ch.id}: {k} {b[k]} > tier {ch.tier} cap {c[k]}"
        slots = [p.bone for p in ch.pieces if p.slot]
        assert len(slots) == 15 and len(set(slots)) == 15, f"{ch.id}: every bone dressed exactly once"
    g = C.gianluca_v25().budget()
    assert g["bespokeMeshes"] <= 8 and g["reusableMeshes"] >= 25 and g["triangles"] < 6000


def test_gianluca_v25_story_pieces_and_asymmetry():
    g = C.gianluca_v25()
    names = {p.name for p in g.pieces}
    assert {"Spear", "SpearHead", "SpearGrip", "SpearCloth", "ShoulderPlate", "Clasp", "Beard", "AgeLines", "HoodDown", "Bell", "ChimCollar", "Pouch", "LeftPatch", "Scarf"} <= names
    by = {p.name: p for p in g.pieces}
    assert by["ShoulderPlate"].mesh.centroid()[0] < 0 < by["Clasp"].mesh.centroid()[0], "plate on his left, clasp on his right"
    assert by["Pouch"].mesh.centroid()[0] < 0 < by["Bell"].mesh.centroid()[0], "pouch left, bell + collar right"
    # the clasp sits on the scarf tail, below the wrapped loop, proud of the tail
    scarf = by["Scarf"].mesh
    loop_bottom = scarf.verts[np.abs(scarf.verts[:, 0]) < 0.2][:, 1].min()
    assert by["Clasp"].mesh.bounds()[1][1] < loop_bottom + 0.05
    assert by["Clasp"].mesh.bounds()[0][2] < scarf.verts[(scarf.verts[:, 0] > 0.5) & (scarf.verts[:, 1] < 0.3)][:, 2].min() - 0.02
    # the spear is planted and rides above his head
    spear = by["Spear"].mesh
    assert spear.bounds()[0][1] == pytest.approx(0.0, abs=0.05)
    assert by["SpearHead"].mesh.bounds()[1][1] > g.profile.height + 0.4
    # the face is the veteran language: narrower eyes than the villager's
    vill = {p.name: p for p in C.villager().pieces}
    assert by["EyeR"].mesh.size()[1] < vill["EyeR"].mesh.size()[1]


def test_every_beat_keeps_the_spear_in_hand():
    for label, beat in C.BEATS.items():
        g = C.gianluca_v25(expression=beat["expression"], rest=beat["rest"], look=beat["look"])
        bones = P.pose(g.profile, g.rest)
        grip = next(p for p in g.pieces if p.name == "SpearGrip").mesh
        d = np.linalg.norm(grip.centroid() - bones["RightHand"].p)
        assert d < 0.55, f"{label}: grip {d:.2f} from the hand"
        assert next(p for p in g.pieces if p.name == "Spear").mesh.bounds()[0][1] == pytest.approx(0.0, abs=0.05), label


def test_prop_candidates_all_plant_and_grip():
    for prop in ("spear", "sword", "cane"):
        g = C.gianluca_v25(prop=prop)
        bones = P.pose(g.profile, g.rest)
        world = [p for p in g.pieces if p.world]
        assert world, prop
        low = min(p.mesh.bounds()[0][1] for p in world)
        assert low == pytest.approx(0.0, abs=0.06), f"{prop} not planted"
        near = min(np.linalg.norm(p.mesh.verts - bones["RightHand"].p, axis=1).min() for p in world)
        assert near < 0.35, f"{prop} not in the hand"


def test_v25_shells_export_as_an_import3d_batch(tmp_path):
    g = C.gianluca_v25()

    class _M:
        name = g.id
        palette = {p.name: "#%02x%02x%02x" % p.mesh.color for p in g.pieces}

    roles = {p.name: p.mesh.to_forge_mesh(p.name) for p in g.pieces}
    path = tmp_path / "gianluca_v25.glb"
    write_glb(path, [(_M, roles)])
    nodes = read_glb(path)
    assert set(nodes) == {f"{g.id}__{p.name}" for p in g.pieces}
