"""The V2 character art study: profiles keep the SR-Rig contract, every mesh is sound,
every character fits its tier envelope (caps read from NpcBudget.lua), pieces hang on
real bones, the fringe stays above the brows, and the shells export as an Import 3D batch."""
import numpy as np
import pytest

from brainrot_forge.export_glb import read_glb, write_glb

from npc_kit.v2 import characters as C
from npc_kit.v2 import kit as K
from npc_kit.v2 import lowpoly as L
from npc_kit.v2 import profiles as P

BONES = {p1 for _, _, p1, _, _ in P.JOINTS}


def caps(H, tier):
    Budget = H.require("ServerStorage/NpcBudget")
    lim = Budget.Limits.human[tier]
    return {k: int(lim[k]) for k in ("baseParts", "bespokeMeshes", "triangles", "motor6d", "welds")}


# ----- profiles ---------------------------------------------------------------------
def test_profiles_keep_the_rig_contract():
    for prof in P.candidates():
        assert set(prof.parts) == BONES | {"HumanoidRootPart"}
        assert set(prof.pivots) == {j[0] for j in P.JOINTS}
        assert prof.centre("HumanoidRootPart")[1] == pytest.approx(P.HRP_Y)
        assert 5.1 <= prof.height <= 5.6, prof.id
        assert 1.3 <= prof.head_offset <= 1.75, f"{prof.id} head centre {prof.head_offset} off the portrait line"
        # every pivot sits inside (or on) both parts it joins
        assert np.allclose(prof.pivots["Root"], prof.centre("HumanoidRootPart"))
        for name, p0, p1, kind, side in P.JOINTS:
            if name == "Root":
                continue                                   # the HRP is a convention (y = 3.0), not a body part
            pv = np.array(prof.pivots[name])
            for part in (p0, p1):
                pad = 0.45 if (name == "Neck" and part == "Head") else 0.12   # the head mesh carries the neck stub
                lo = prof.centre(part) - prof.size(part) / 2 - pad
                hi = prof.centre(part) + prof.size(part) / 2 + pad
                assert np.all(pv >= lo) and np.all(pv <= hi), f"{prof.id} {name} pivot off {part}"
        # feet on the ground, left/right mirrored
        assert prof.centre("RightFoot")[1] - prof.size("RightFoot")[1] / 2 == pytest.approx(0.0)
        assert prof.centre("LeftHand")[0] == pytest.approx(-prof.centre("RightHand")[0])


def test_v1_reference_matches_step0_numbers():
    v1 = P.profile("v1")
    assert v1.shoulder_span == pytest.approx(3.65, abs=1e-6)
    assert v1.height == pytest.approx(5.225, abs=0.05)
    p2 = P.profile("P2")
    assert p2.heads < v1.heads and p2.size("RightLowerArm")[0] > p2.size("RightUpperArm")[0]


def test_pose_fk_is_a_rigid_tree():
    prof = P.profile("P2")
    bones = P.pose(prof, {"RightShoulder": {"swing": 90}})
    hand = bones["RightHand"]
    rest = P.pose(prof, {})
    # swing +90 points the whole arm forward (-Z): the hand ends up an arm's length in front, at shoulder height
    assert hand.p[2] < rest["RightHand"].p[2] - 1.6 and abs(hand.p[1] - P.pivots_world(prof, rest)["RightShoulder"][1]) < 0.4
    piv = P.pivots_world(prof, bones)["RightShoulder"]
    d_posed = np.linalg.norm(P.pivots_world(prof, bones)["RightElbow"] - piv)
    d_rest = np.linalg.norm(P.pivots_world(prof, rest)["RightElbow"] - P.pivots_world(prof, rest)["RightShoulder"])
    assert d_posed == pytest.approx(d_rest, abs=1e-6)


# ----- meshes ------------------------------------------------------------------------
def _sound(m: L.Mesh):
    assert np.isfinite(m.verts).all(), m.name
    assert m.faces.min() >= 0 and m.faces.max() < len(m.verts), m.name
    t = m.triangles()
    area = np.linalg.norm(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]), axis=1) / 2
    assert (area > 1e-9).mean() > 0.9, f"{m.name}: degenerate faces"


def test_every_piece_is_a_sound_outward_mesh():
    for ch in C.cast():
        for p in ch.pieces:
            _sound(p.mesh)
            if not p.slot and p.category != "hair":
                continue                                   # flat annuli (mantle, brims) legitimately face inward on their inner edge
            # closed shells: most faces point away from the mesh centroid
            n = p.mesh.face_normals()
            out = p.mesh.triangles().mean(1) - p.mesh.centroid()
            assert ((n * out).sum(1) > 0).mean() > 0.6, f"{ch.id}.{p.name} winds inward"


def test_every_bone_has_exactly_one_visible_slot_and_pieces_use_real_bones():
    for ch in C.cast():
        slots = [p.bone for p in ch.pieces if p.slot]
        assert sorted(slots) == sorted(BONES), f"{ch.id}: slot coverage {sorted(slots)}"
        for p in ch.pieces:
            assert p.bone in BONES, f"{ch.id}.{p.name} hangs on unknown bone {p.bone}"
            if not p.world:
                # a bone-local piece must sit near its bone (welded accessories, shells)
                prof = ch.profile
                lo, hi = p.mesh.bounds()
                half = prof.size(p.bone) / 2
                assert np.all(lo <= half + 1.6) and np.all(hi >= -half - 1.6), f"{ch.id}.{p.name} floats off {p.bone}"


def test_face_keeps_the_step0_part_names_and_stays_on_the_face_plane():
    prof = P.profile("P2")
    hw, hh, hd = prof.size("Head")
    for ex in K.EXPRESSIONS:
        parts = {p.name: p for p in K.face(prof, ex)}
        assert set(parts) == {"EyeL", "EyeR", "PupilL", "PupilR", "BrowL", "BrowR", "Mouth"}
        for name, p in parts.items():
            lo, hi = p.mesh.bounds()
            assert lo[0] >= -hw / 2 and hi[0] <= hw / 2, f"{name} outside the head width ({ex})"
            assert lo[1] >= -hh / 2 and hi[1] <= hh / 2, f"{name} outside the head height ({ex})"
            assert -hd / 2 - 0.20 <= lo[2] <= -hd / 2 + 0.03, f"{name} is not on the face plane ({ex})"
        assert parts["EyeR"].mesh.bounds()[0][0] > parts["EyeL"].mesh.bounds()[1][0] + 0.15, "eyes must not touch"


def test_hair_fringe_stays_above_the_brows():
    prof = P.profile("P2")
    brow_top = max(K.face(prof, "neutral")[i].mesh.bounds()[1][1] for i in (4, 5) if K.face(prof, "neutral")[i].name.startswith("Brow"))
    hw, hh, hd = prof.size("Head")
    for style in ("crop", "tousled", "side", "bob"):
        hair = K.hair(prof, style).mesh
        front = hair.verts[hair.verts[:, 2] < -hd / 2 * 0.85]                    # everything at the face plane
        centre = front[np.abs(front[:, 0]) < 0.36 * hw]                          # ... above the eyes
        if len(centre):
            assert centre[:, 1].min() >= brow_top - 0.06, f"{style}: fringe {centre[:, 1].min():.2f} crosses the brows {brow_top:.2f}"


# ----- budgets against the real caps ------------------------------------------------
def test_characters_fit_their_tier_envelopes(H):
    for ch in C.cast():
        b = ch.budget()
        c = caps(H, ch.tier)
        for k in ("baseParts", "bespokeMeshes", "triangles", "motor6d", "welds"):
            assert b[k] <= c[k], f"{ch.id}: {k} {b[k]} > tier {ch.tier} cap {c[k]}"
    g = C.gianluca_v2().budget()
    c2 = caps(H, 2)
    assert g["baseParts"] <= c2["baseParts"] and g["welds"] <= c2["welds"] and g["bespokeMeshes"] <= c2["bespokeMeshes"] and g["triangles"] <= c2["triangles"], \
        "Gianluca V2 must still fit the Tier 2 envelope his recipe declares"
    assert g["triangles"] < 4500, "V2 shells should stay cheaper than the v1 voxel body target"


def test_gianluca_v2_contracts_and_asymmetry():
    g = C.gianluca_v2()
    names = {p.name for p in g.pieces}
    assert {"Hat", "HatBand", "Scarf", "Mantle", "ChimCollar", "Pouch", "Cane", "Bell"} <= names
    specific = {p.name for p in g.pieces if p.ownership == "specific"}
    assert specific == {"Hat", "HatBand", "ChimCollar"}
    # asymmetry: the rolled left sleeve has more geometry than the right, pouch left, collar right
    tris = {p.name: p.tris for p in g.pieces}
    assert tris["LeftUpperArm"] > tris["RightUpperArm"]
    pouch = next(p for p in g.pieces if p.name == "Pouch").mesh.centroid()
    collar = next(p for p in g.pieces if p.name == "ChimCollar").mesh.centroid()
    assert pouch[0] < 0 < collar[0]
    # the cane is planted: its lowest point on the ground, its knob at the right hand
    cane = next(p for p in g.pieces if p.name == "Cane").mesh
    bones = P.pose(g.profile, g.rest)
    assert cane.bounds()[0][1] == pytest.approx(0.0, abs=0.05)
    assert np.linalg.norm(cane.verts[cane.verts[:, 1].argmax()] - bones["RightHand"].p) < 0.6


def test_shells_export_as_an_import3d_batch(tmp_path):
    g = C.gianluca_v2()

    class _M:
        name = g.id
        palette = {p.name: "#%02x%02x%02x" % p.mesh.color for p in g.pieces}

    roles = {p.name: p.mesh.to_forge_mesh(p.name) for p in g.pieces}
    path = tmp_path / "gianluca_v2.glb"
    write_glb(path, [(_M, roles)])
    nodes = read_glb(path)
    assert set(nodes) == {f"{g.id}__{p.name}" for p in g.pieces}
    hat = nodes[f"{g.id}__Hat"]
    assert len(hat["indices"]) // 3 == roles["Hat"].triangles
